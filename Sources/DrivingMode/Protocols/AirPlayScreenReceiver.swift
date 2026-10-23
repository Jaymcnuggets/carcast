//
//  AirPlayScreenReceiver.swift
//  DrivingMode
//
//  Real-time CarPlay screen stream receiver and depacketizer.
//
//  On-wire format (verified against the working CarCast receiver, AirPlayReceiverSessionScreen_ProcessFrames
//  in libcarcast.so @ 0x3b3f3c, and against live captures from iOS 27):
//
//    Frame = 128-byte header + payload
//      header[0..<4]   payload size, UInt32 little-endian (includes the 16-byte Poly1305 tag when encrypted)
//      header[4..<6]   payload type, UInt16 little-endian: 0 = video (encrypted AVCC), 1 = codec config (plaintext avcC),
//                      2 = heartbeat, 5 = other/ignored
//      header[6..<8]   flags
//      header[8..<16]  NTP timestamp
//      header[16..]    type-specific (type 1: Float32 LE width/height at 16/20 and 40/44)
//
//    Encrypted payloads: ChaCha20-Poly1305, key = DataStream key derived from pair-verify for this stream
//    (see HomeKitPairingService.deriveDataStreamKeys), AAD = the full 128-byte header,
//    nonce = 12-byte little-endian frame counter starting at 0 (incremented once per decrypted frame),
//    ciphertext = payload[0..<size-16], tag = payload[size-16..<size].
//

import Foundation
import Network
import CoreMedia
import VideoToolbox
import CryptoKit

public enum AirPlayScreenOpCode: UInt16, Sendable {
    case videoFrame = 0x0000
    case videoConfig = 0x0001
    case keepAlive = 0x0002
    case ignore = 0xFFFF
}

public struct AirPlayScreenHeader: Sendable, Equatable {
    public static let size = 128

    public let payloadLength: Int
    public let opcode: AirPlayScreenOpCode
    public let rawType: UInt16
    public let flags: UInt16

    public init(payloadLength: Int, opcode: AirPlayScreenOpCode, rawType: UInt16? = nil, flags: UInt16 = 0) {
        self.payloadLength = payloadLength
        self.opcode = opcode
        self.rawType = rawType ?? opcode.rawValue
        self.flags = flags
    }

    /// Parses the 128-byte little-endian screen frame header (only the first 8 bytes are required).
    /// Note: In libcarcast.so @ 0x3b3d00 (`ldrb w4, [x21, #0x6c]`), `header[4]` (1 byte) is the packet opcode
    /// (`0` = video frame, `1` = codec config, `2` = keepalive), while `header[5]` is frame flags (non-zero on IDR keyframes).
    public static func parse(from data: Data) -> AirPlayScreenHeader? {
        guard data.count >= 8 else { return nil }
        let b = [UInt8](data.prefix(8))
        let length = Int(UInt32(b[0]) | (UInt32(b[1]) << 8) | (UInt32(b[2]) << 16) | (UInt32(b[3]) << 24))
        let opcodeByte = UInt16(b[4])
        let rawType = UInt16(b[4]) | (UInt16(b[5]) << 8)
        let flags = UInt16(b[6]) | (UInt16(b[7]) << 8)
        return AirPlayScreenHeader(payloadLength: length, opcode: AirPlayScreenOpCode(rawValue: opcodeByte) ?? .ignore, rawType: rawType, flags: flags)
    }
}

public protocol AirPlayScreenReceiverDelegate: AnyObject, Sendable {
    func screenReceiverDidReceiveSampleBuffer(_ sampleBuffer: CMSampleBuffer)
    func screenReceiverDidReceiveDimensions(width: Int, height: Int)
    func screenReceiverStateChanged(isActive: Bool)
    func screenReceiverNeedsKeyFrame()
}

public final class AirPlayScreenReceiver: @unchecked Sendable {
    public weak var delegate: AirPlayScreenReceiverDelegate?

    /// Keys for the next screen stream connection, set by RTSPServer when the type-110 stream is SETUP.
    nonisolated(unsafe) public static var pendingStreamKeys: (output: Data, input: Data)?
    /// Additional candidate keys (e.g. signed-decimal salt variant) tried if the primary keys fail.
    nonisolated(unsafe) public static var extraCandidateKeys: [Data] = []

    /// Diagnostic: log raw stream bytes instead of parsing.
    nonisolated(unsafe) public static var rawCaptureMode = false

    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "dev.unordinarylabs.drivingmode.screen", qos: .userInteractive)

    private var formatDescription: CMVideoFormatDescription?
    private var nalLengthSize = 4

    // Decryption state
    private var candidateKeys: [SymmetricKey] = []
    private var activeKey: SymmetricKey?
    private var nonceCounter: UInt64 = 0
    private var framesDecoded = 0
    private var decryptFailures = 0
    private var hasSeenKeyframe = false

    public init(port: UInt16 = 7100) {
        self.port = NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 7100)
    }

    public func resetSession() {
        activeConnection?.cancel()
        activeConnection = nil
        formatDescription = nil
        activeKey = nil
        candidateKeys = []
        nonceCounter = 0
        framesDecoded = 0
        decryptFailures = 0
        hasSeenKeyframe = false
        delegate?.screenReceiverStateChanged(isActive: false)
    }

    public func start() throws {
        resetSession()

        if let existing = listener, existing.state == .ready {
            return
        }

        listener?.cancel()
        listener = nil

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = true

        let listener = try NWListener(using: params, on: port)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor in
                    ProtocolLogger.shared.log(category: .screen, title: "Screen Receiver Listening", detail: "Port \(self?.port.rawValue ?? 0)")
                }
            case .failed(let error):
                Task { @MainActor in
                    ProtocolLogger.shared.log(category: .screen, title: "Screen Receiver Failed", detail: error.localizedDescription)
                }
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            writeAppLog("[Screen] Incoming TCP connection from \(connection.endpoint)")
            self?.handleNewConnection(connection)
        }

        listener.start(queue: queue)
    }

    public func stop() {
        resetSession()
        listener?.cancel()
        listener = nil
    }

    private func handleNewConnection(_ connection: NWConnection) {
        activeConnection?.cancel()
        activeConnection = connection
        formatDescription = nil
        nonceCounter = 0
        framesDecoded = 0
        decryptFailures = 0
        activeKey = nil
        capturedFrames = 0
        hasSeenKeyframe = false
        if let keys = AirPlayScreenReceiver.pendingStreamKeys {
            // Try the sender's output key first, then the input key; the first one that authenticates is locked in.
            candidateKeys = [SymmetricKey(data: keys.output), SymmetricKey(data: keys.input)] + AirPlayScreenReceiver.extraCandidateKeys.map { SymmetricKey(data: $0) }
        } else {
            candidateKeys = []
            NSLog("[DrivingMode][Screen] WARNING: no stream keys available; video payloads will not decrypt")
        }

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor in
                    ProtocolLogger.shared.log(category: .screen, direction: .rx, title: "Screen Stream Connected", detail: "Client connected to port \(self?.port.rawValue ?? 0)")
                }
                self?.delegate?.screenReceiverStateChanged(isActive: true)
                if AirPlayScreenReceiver.rawCaptureMode {
                    self?.rawCapture(connection: connection, chunkIndex: 0, total: 0)
                } else {
                    self?.readNextHeader()
                }
            case .failed(let err):
                Task { @MainActor in
                    ProtocolLogger.shared.log(category: .screen, title: "Screen Stream Disconnected", detail: err.localizedDescription)
                }
                self?.delegate?.screenReceiverStateChanged(isActive: false)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func rawCapture(connection: NWConnection, chunkIndex: Int, total: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            var newTotal = total
            if let d = content, !d.isEmpty {
                newTotal += d.count
                if chunkIndex < 6 {
                    NSLog("[DrivingMode][ScreenRaw] chunk#%d len=%d total=%d head=%@", chunkIndex, d.count, newTotal,
                          d.prefix(160).map { String(format: "%02X", $0) }.joined(separator: " "))
                }
            }
            if isComplete || error != nil { return }
            self?.rawCapture(connection: connection, chunkIndex: chunkIndex + 1, total: newTotal)
        }
    }

    // MARK: - Framing

    private func readExact(length: Int, accumulated: Data = Data(), completion: @escaping (Data?) -> Void) {
        guard let connection = activeConnection else {
            completion(nil)
            return
        }
        let needed = length - accumulated.count
        guard needed > 0 else {
            completion(accumulated)
            return
        }
        let fetch = min(needed, 65536)
        connection.receive(minimumIncompleteLength: 1, maximumLength: fetch) { [weak self] content, _, isComplete, error in
            if let error = error {
                writeAppLog("[Screen] TCP receive error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            var next = accumulated
            if let chunk = content, !chunk.isEmpty {
                next.append(chunk)
            }
            if next.count == length {
                completion(next)
            } else if content == nil && isComplete {
                writeAppLog("[Screen] TCP EOF (accumulated \(next.count)/\(length) bytes)")
                completion(nil)
            } else {
                self?.readExact(length: length, accumulated: next, completion: completion)
            }
        }
    }

    private func readNextHeader() {
        readExact(length: AirPlayScreenHeader.size) { [weak self] headerData in
            guard let self = self, let header = headerData, header.count == AirPlayScreenHeader.size,
                  let parsed = AirPlayScreenHeader.parse(from: header) else {
                writeAppLog("[Screen] Stream closed or failed to read header (decoded \(self?.framesDecoded ?? 0) frames)")
                NSLog("[DrivingMode][Screen] Stream closed or failed to read header (decoded %d frames)", self?.framesDecoded ?? 0)
                self?.delegate?.screenReceiverStateChanged(isActive: false)
                return
            }
            self.readPayload(header: header, parsed: parsed)
        }
    }

    private func readPayload(header: Data, parsed: AirPlayScreenHeader) {
        guard parsed.payloadLength > 0 else {
            self.readNextHeader()
            return
        }
        readExact(length: parsed.payloadLength) { [weak self] payloadData in
            guard let self = self, let payload = payloadData, payload.count == parsed.payloadLength else {
                writeAppLog("[Screen] Failed to read full payload (expected \(parsed.payloadLength) bytes, got \(payloadData?.count ?? 0))")
                NSLog("[DrivingMode][Screen] Failed to read full payload (expected %d bytes)", parsed.payloadLength)
                self?.delegate?.screenReceiverStateChanged(isActive: false)
                return
            }
            self.processFrame(header: header, parsed: parsed, payload: payload)
            self.readNextHeader()
        }
    }

    private func processFrame(header: Data, parsed: AirPlayScreenHeader, payload: Data) {
        switch parsed.opcode {
        case .videoConfig:
            parseCodecConfig(header: header, payload: payload)
        case .videoFrame:
            guard let frame = decryptVideoPayload(header: header, payload: payload) else { return }
            enqueueVideoFrame(frame)
        default:
            break
        }
    }

    /// CarCast's screen cipher context stores an 8-byte little-endian frame counter as the nonce (ctx+0x338..0x340,
    /// zeroed by the key setter @ 0x3b397c). In 96-bit form that is 4 zero bytes followed by the 64-bit counter.
    private func nonce(_ counter: UInt64) -> ChaChaPoly.Nonce {
        var n = Data(count: 4)
        withUnsafeBytes(of: counter.littleEndian) { n.append(contentsOf: $0) }
        return try! ChaChaPoly.Nonce(data: n)
    }

    private func decryptVideoPayload(header: Data, payload: Data) -> Data? {
        guard payload.count > 16 else { return nil }
        if candidateKeys.isEmpty && activeKey == nil {
            return payload // unencrypted session
        }
        captureForOfflineAnalysis(header: header, payload: payload)
        let ct = payload.prefix(payload.count - 16)
        let tag = payload.suffix(16)

        let keys = activeKey.map { [$0] } ?? candidateKeys
        // Try the expected nonce first, then a fast resync window [-10...+40] in case frames or nonces were skipped.
        let minNonce = nonceCounter >= 10 ? nonceCounter - 10 : 0
        let maxNonce = nonceCounter + 40
        // Check current nonce first for 0-overhead fast path
        let candidateNonces = [nonceCounter] + Array(minNonce...maxNonce).filter { $0 != nonceCounter }

        for n in candidateNonces {
            guard let box = try? ChaChaPoly.SealedBox(nonce: nonce(n), ciphertext: ct, tag: tag) else { continue }
            for (idx, key) in keys.enumerated() {
                if let pt = try? ChaChaPoly.open(box, using: key, authenticating: header) {
                    if activeKey == nil {
                        activeKey = key
                        writeAppLog("[Screen] Locked in candidate key #\(idx), first nonce=\(n)")
                        NSLog("[DrivingMode][Screen] Screen payload decrypted with candidate key #%d frame nonce=%llu", idx, n)
                    } else if n != nonceCounter {
                        writeAppLog("[Screen] Resynced screen nonce \(nonceCounter) -> \(n)")
                        NSLog("[DrivingMode][Screen] Resynced screen nonce %llu -> %llu", nonceCounter, n)
                    }
                    nonceCounter = n + 1
                    return pt
                }
            }
        }
        decryptFailures += 1
        if decryptFailures <= 5 || decryptFailures % 60 == 0 {
            writeAppLog("[Screen] Decrypt failed for frame (expectedNonce=\(nonceCounter), size=\(payload.count), failures=\(decryptFailures))")
            NSLog("[DrivingMode][Screen] Failed to decrypt video frame #%llu (size=%d, failures=%d)", nonceCounter, payload.count, decryptFailures)
        }
        nonceCounter += 1
        return nil
    }

    // MARK: - Diagnostics

    private var capturedFrames = 0

    /// Writes the stream keys and the first few encrypted frames to Documents/screen_capture.bin for offline analysis.
    /// Format: "DMSC" | outKey(32) | inKey(32) | repeated { u32 LE headerLen | header | u32 LE payloadLen | payload }.
    private func captureForOfflineAnalysis(header: Data, payload: Data) {
        guard capturedFrames < 120, let keys = AirPlayScreenReceiver.pendingStreamKeys,
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = docs.appendingPathComponent("screen_capture.bin")
        var blob = Data()
        if capturedFrames == 0 {
            blob.append(Data("DMS2".utf8))
            let all = [keys.output, keys.input] + AirPlayScreenReceiver.extraCandidateKeys
            var n = UInt32(all.count).littleEndian; blob.append(Data(bytes: &n, count: 4))
            all.forEach { blob.append($0) }
            try? Data().write(to: url)
        }
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; blob.append(Data(bytes: &x, count: 4)) }
        u32(header.count); blob.append(header); u32(payload.count); blob.append(payload)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(blob); try? h.close() }
        capturedFrames += 1
        if capturedFrames == 4 { NSLog("[DrivingMode][Screen] Wrote screen_capture.bin for offline analysis") }
    }

    // MARK: - Codec config (avcC)

    private func parseCodecConfig(header: Data, payload: Data) {
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? payload.write(to: docs.appendingPathComponent("avcC.bin"))
        }
        let b = [UInt8](payload)
        // avcC: version(1) profile(1) compat(1) level(1) 0xFC|lengthSizeMinusOne(1) 0xE0|numSPS(1) [len(2) sps]... numPPS(1) [len(2) pps]...
        guard b.count >= 7, b[0] == 1 else {
            NSLog("[DrivingMode][Screen] Unexpected codec config (%d bytes): %@", b.count, payload.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " "))
            return
        }
        nalLengthSize = Int(b[4] & 0x03) + 1
        var i = 5
        var sets: [Data] = []
        let numSPS = Int(b[i] & 0x1F); i += 1
        for _ in 0..<numSPS {
            guard i + 2 <= b.count else { return }
            let len = Int(b[i]) << 8 | Int(b[i + 1]); i += 2
            guard i + len <= b.count else { return }
            sets.append(Data(b[i..<(i + len)])); i += len
        }
        guard i < b.count else { return }
        let numPPS = Int(b[i]); i += 1
        for _ in 0..<numPPS {
            guard i + 2 <= b.count else { return }
            let len = Int(b[i]) << 8 | Int(b[i + 1]); i += 2
            guard i + len <= b.count else { return }
            sets.append(Data(b[i..<(i + len)])); i += len
        }
        guard sets.count >= 2 else { return }
        createFormatDescription(parameterSets: sets)
    }

    private func createFormatDescription(parameterSets sets: [Data]) {
        let arrays = sets.map { [UInt8]($0) }
        var desc: CMFormatDescription?
        let status: OSStatus = withPointers(arrays) { pointers in
            let sizes = arrays.map { $0.count }
            return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: arrays.count,
                parameterSetPointers: pointers,
                parameterSetSizes: sizes,
                nalUnitHeaderLength: Int32(nalLengthSize),
                formatDescriptionOut: &desc
            )
        }
        guard status == noErr, let d = desc else {
            NSLog("[DrivingMode][Screen] CMVideoFormatDescriptionCreateFromH264ParameterSets failed: %d", status)
            return
        }
        formatDescription = d
        let dim = CMVideoFormatDescriptionGetDimensions(d)
        NSLog("[DrivingMode][Screen] Codec config: H.264 %dx%d (NAL length size %d)", dim.width, dim.height, nalLengthSize)
        delegate?.screenReceiverDidReceiveDimensions(width: Int(dim.width), height: Int(dim.height))
        Task { @MainActor in
            ProtocolLogger.shared.log(category: .screen, title: "Video Config SPS/PPS", detail: "\(dim.width)x\(dim.height) H.264")
        }
    }

    private func withPointers<R>(_ arrays: [[UInt8]], _ body: ([UnsafePointer<UInt8>]) -> R) -> R {
        func recurse(_ idx: Int, _ acc: [UnsafePointer<UInt8>]) -> R {
            if idx == arrays.count { return body(acc) }
            return arrays[idx].withUnsafeBufferPointer { recurse(idx + 1, acc + [$0.baseAddress!]) }
        }
        return recurse(0, [])
    }

    // MARK: - Video frames

    private func parseNALTypes(_ data: Data) -> [Int] {
        var types: [Int] = []
        var offset = 0
        let count = data.count
        data.withUnsafeBytes { raw in
            guard let ptr = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            while offset + 4 < count {
                let len = Int(UInt32(ptr[offset]) << 24 | UInt32(ptr[offset+1]) << 16 | UInt32(ptr[offset+2]) << 8 | UInt32(ptr[offset+3]))
                if offset + 4 < count {
                    let nalType = Int(ptr[offset + 4] & 0x1F)
                    types.append(nalType)
                }
                if len <= 0 || offset + 4 + len > count { break }
                offset += 4 + len
            }
        }
        return types
    }

    private func enqueueVideoFrame(_ data: Data) {
        guard let formatDesc = formatDescription else { return }

        let nalTypes = parseNALTypes(data)
        if nalTypes.contains(5) {
            hasSeenKeyframe = true
            writeAppLog("[Screen] *** IDR KEYFRAME DETECTED in frame #\(framesDecoded + 1) (len=\(data.count), NALs=\(nalTypes)) ***")
            NSLog("[DrivingMode][Screen] *** IDR KEYFRAME DETECTED in frame #%d (len=%d, NALs=%@) ***", framesDecoded + 1, data.count, String(describing: nalTypes))
        } else if !hasSeenKeyframe {
            // Request keyframe if no IDR frame arrived after 60 frames
            if (framesDecoded + 1) % 60 == 0 {
                writeAppLog("[Screen] Waiting for IDR keyframe (frame #\(framesDecoded + 1), NALs=\(nalTypes)) -> requesting keyframe from CarPlay host")
                delegate?.screenReceiverNeedsKeyFrame()
            }
        } else if framesDecoded % 60 == 0 {
            writeAppLog("[Screen] Frame #\(framesDecoded + 1) (len=\(data.count), NALs=\(nalTypes))")
        }

        var blockBuffer: CMBlockBuffer?
        // Authentic CarCast 0x100556dc0 parity: pass kCMBlockBufferAssureMemoryNowFlag = 1
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 1, // kCMBlockBufferAssureMemoryNowFlag
            blockBufferOut: &blockBuffer
        )
        guard status == kCMBlockBufferNoErr, let buffer = blockBuffer else { return }

        data.withUnsafeBytes { rawBuf in
            if let base = rawBuf.baseAddress {
                CMBlockBufferReplaceDataBytes(with: base, blockBuffer: buffer, offsetIntoDestination: 0, dataLength: data.count)
            }
        }

        var sampleBuffer: CMSampleBuffer?
        var sampleSize = data.count
        // Authentic CarCast 0x100556e10 parity:
        // Use CMSampleBufferCreateReady with sampleCount = 1, sampleTimingEntryCount = 0 and sampleTimingArray = nil, sampleSizeEntryCount = 1
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: buffer,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        if sampleStatus == noErr, let sb = sampleBuffer {
            // Display immediately (live stream) - authentic CarCast 0x100556e48 parity
            if let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true),
               CFArrayGetCount(attachments) > 0 {
                let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
                CFDictionarySetValue(dict, unsafeBitCast(kCMSampleAttachmentKey_DisplayImmediately, to: UnsafeRawPointer.self), unsafeBitCast(kCFBooleanTrue, to: UnsafeRawPointer.self))
            }
            framesDecoded += 1
            if framesDecoded == 1 {
                writeAppLog("[Screen] Enqueued video frame #1 (\(data.count) bytes) — requesting IDR keyframe from host")
                NSLog("[DrivingMode][Screen] Enqueued video frame #1 (%d bytes) — requesting IDR keyframe", data.count)
                delegate?.screenReceiverNeedsKeyFrame()
            } else if framesDecoded % 60 == 0 {
                writeAppLog("[Screen] Enqueued video frame #\(framesDecoded) (\(data.count) bytes)")
                NSLog("[DrivingMode][Screen] Enqueued video frame #%d (%d bytes)", framesDecoded, data.count)
            }
            delegate?.screenReceiverDidReceiveSampleBuffer(sb)
        }
    }
}
