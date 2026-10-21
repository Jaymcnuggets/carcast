//
//  AirPlayScreenReceiver.swift
//  CarCast
//
//  Real-time AirPlay / CarPlay video frame receiver and depacketizer.
//

import Foundation
import Network
import CoreMedia
import VideoToolbox

public enum AirPlayScreenOpCode: UInt16, Sendable {
    case videoFrame = 0x0000
    case videoConfig = 0x0001
    case keepAlive = 0x0002
    case ignore = 0xFFFF
}

public struct AirPlayScreenHeader: Sendable, Equatable {
    public let payloadLength: Int
    public let opcode: AirPlayScreenOpCode
    public let reserved: UInt16

    public init(payloadLength: Int, opcode: AirPlayScreenOpCode, reserved: UInt16 = 0) {
        self.payloadLength = payloadLength
        self.opcode = opcode
        self.reserved = reserved
    }

    public static func parse(from data: Data) -> AirPlayScreenHeader? {
        guard data.count >= 8 else { return nil }
        let length = Int((UInt32(data[0]) << 24) | (UInt32(data[1]) << 16) | (UInt32(data[2]) << 8) | UInt32(data[3]))
        let rawOpcode = (UInt16(data[4]) << 8) | UInt16(data[5])
        let opcode = AirPlayScreenOpCode(rawValue: rawOpcode) ?? .ignore
        let reserved = (UInt16(data[6]) << 8) | UInt16(data[7])
        return AirPlayScreenHeader(payloadLength: length, opcode: opcode, reserved: reserved)
    }
}

public protocol AirPlayScreenReceiverDelegate: AnyObject, Sendable {
    func screenReceiverDidReceiveSampleBuffer(_ sampleBuffer: CMSampleBuffer)
    func screenReceiverDidReceiveDimensions(width: Int, height: Int)
    func screenReceiverStateChanged(isActive: Bool)
}

public final class AirPlayScreenReceiver: @unchecked Sendable {
    public weak var delegate: AirPlayScreenReceiverDelegate?

    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "dev.unordinarylabs.carcast.screen", qos: .userInteractive)

    private var formatDescription: CMVideoFormatDescription?
    private var spsData: Data?
    private var ppsData: Data?

    public init(port: UInt16 = 7100) {
        self.port = NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 7100)
    }

    public func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

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
            self?.handleNewConnection(connection)
        }

        listener.start(queue: queue)
    }

    public func stop() {
        activeConnection?.cancel()
        activeConnection = nil
        listener?.cancel()
        listener = nil
        delegate?.screenReceiverStateChanged(isActive: false)
    }

    private func handleNewConnection(_ connection: NWConnection) {
        activeConnection?.cancel()
        activeConnection = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor in
                    ProtocolLogger.shared.log(category: .screen, direction: .rx, title: "Screen Stream Connected", detail: "Client connected to port \(self?.port.rawValue ?? 0)")
                }
                self?.delegate?.screenReceiverStateChanged(isActive: true)
                self?.readNextHeader()
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

    private func readNextHeader() {
        guard let connection = activeConnection else { return }

        // AirPlay Screen Header is 8 bytes minimum:
        // [0..3]: payload size (UInt32 big-endian)
        // [4..5]: opcode (UInt16 big-endian)
        // [6..7]: reserved/flags (UInt16)
        connection.receive(minimumIncompleteLength: 8, maximumLength: 8) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                Task { @MainActor in
                    ProtocolLogger.shared.log(category: .screen, title: "Header Read Error", detail: error.localizedDescription)
                }
                return
            }

            guard let data = content, data.count == 8 else {
                if isComplete {
                    self.delegate?.screenReceiverStateChanged(isActive: false)
                }
                return
            }

            if let header = AirPlayScreenHeader.parse(from: data) {
                self.readPayload(size: header.payloadLength, opcode: header.opcode)
            } else {
                self.readNextHeader()
            }
        }
    }

    private func readPayload(size: Int, opcode: AirPlayScreenOpCode) {
        guard let connection = activeConnection, size > 0 else {
            readNextHeader()
            return
        }

        connection.receive(minimumIncompleteLength: size, maximumLength: size) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            if let data = content, data.count == size {
                self.processFrameData(data, opcode: opcode)
            }
            if !isComplete {
                self.readNextHeader()
            }
        }
    }

    private func processFrameData(_ data: Data, opcode: AirPlayScreenOpCode) {
        switch opcode {
        case .videoConfig:
            parseVideoConfig(data)
        case .videoFrame:
            parseVideoFrame(data)
        case .keepAlive:
            break
        case .ignore:
            break
        }
    }

    private func parseVideoConfig(_ data: Data) {
        // Parse SPS and PPS NALUs from AVCC or parameter set
        // Standard AVCC or Annex-B start codes 00 00 00 01
        var offset = 0
        var foundSPS: Data?
        var foundPPS: Data?

        while offset + 4 < data.count {
            if data[offset] == 0 && data[offset+1] == 0 && data[offset+2] == 0 && data[offset+3] == 1 {
                let nalType = data[offset + 4] & 0x1F
                let start = offset + 4
                // Find next start code or end
                var end = data.count
                for next in (start + 1)..<(data.count - 3) {
                    if data[next] == 0 && data[next+1] == 0 && data[next+2] == 0 && data[next+3] == 1 {
                        end = next
                        break
                    }
                }
                let nalData = data.subdata(in: start..<end)
                if nalType == 7 { // SPS
                    foundSPS = nalData
                } else if nalType == 8 { // PPS
                    foundPPS = nalData
                }
                offset = end
            } else {
                offset += 1
            }
        }

        if let sps = foundSPS, let pps = foundPPS {
            self.spsData = sps
            self.ppsData = pps
            createFormatDescription(sps: sps, pps: pps)
        }
    }

    private func createFormatDescription(sps: Data, pps: Data) {
        let spsBytes = [UInt8](sps)
        let ppsBytes = [UInt8](pps)

        var parameterSets: [UnsafePointer<UInt8>] = []
        var parameterSetSizes: [Int] = []

        spsBytes.withUnsafeBufferPointer { spsBuf in
            ppsBytes.withUnsafeBufferPointer { ppsBuf in
                if let spsBase = spsBuf.baseAddress, let ppsBase = ppsBuf.baseAddress {
                    parameterSets = [spsBase, ppsBase]
                    parameterSetSizes = [sps.count, pps.count]

                    var formatDesc: CMFormatDescription?
                    let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: 2,
                        parameterSetPointers: parameterSets,
                        parameterSetSizes: parameterSetSizes,
                        nalUnitHeaderLength: 4,
                        formatDescriptionOut: &formatDesc
                    )

                    if status == noErr, let desc = formatDesc {
                        self.formatDescription = desc
                        let dim = CMVideoFormatDescriptionGetDimensions(desc)
                        self.delegate?.screenReceiverDidReceiveDimensions(width: Int(dim.width), height: Int(dim.height))

                        Task { @MainActor in
                            ProtocolLogger.shared.log(
                                category: .screen,
                                title: "Video Config SPS/PPS",
                                detail: "\(dim.width)x\(dim.height) H.264"
                            )
                        }
                    }
                }
            }
        }
    }

    private func parseVideoFrame(_ data: Data) {
        guard let formatDesc = formatDescription else { return }

        // Create CMBlockBuffer
        var blockBuffer: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard status == kCMBlockBufferNoErr, let buffer = blockBuffer else { return }

        data.withUnsafeBytes { rawBuf in
            if let base = rawBuf.baseAddress {
                CMBlockBufferReplaceDataBytes(
                    with: base,
                    blockBuffer: buffer,
                    offsetIntoDestination: 0,
                    dataLength: data.count
                )
            }
        }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )

        let sampleStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: buffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        if sampleStatus == noErr, let sb = sampleBuffer {
            delegate?.screenReceiverDidReceiveSampleBuffer(sb)
        }
    }
}
