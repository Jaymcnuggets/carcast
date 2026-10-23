//
//  RTSPServer.swift
//  DrivingMode
//
//  Authentic RTSP and HTTP signaling server for CarPlay.
//

import Foundation
import Network
import CryptoKit

public protocol RTSPServerDelegate: AnyObject, Sendable {
    func rtspServerDidStartSession(clientName: String?)
    func rtspServerDidEndSession()
}

public final class RTSPServer: @unchecked Sendable {
    public weak var delegate: RTSPServerDelegate?

    private var listener: NWListener?
    private let requestedPort: UInt16
    private let queue = DispatchQueue(label: "dev.unordinarylabs.drivingmode.rtsp", qos: .userInteractive)
    private var activeConnections: [NWConnection] = []
    public var activeConnectionCount: Int { activeConnections.count }
    private var nextServerCSeq: Int = 100

    /// HAP-style encrypted control channel state (enabled after pair-verify completes on a connection).
    /// Frame: [UInt16 LE length (<=1024)] [ciphertext] [16-byte Poly1305 tag]; AAD = the 2 length bytes;
    /// nonce = 4 zero bytes + UInt64 LE counter (independent counter per direction, starting at 0).
    private final class ControlCipher {
        var decryptKey: SymmetricKey
        var encryptKey: SymmetricKey
        var rxCounter: UInt64 = 0
        var txCounter: UInt64 = 0
        var rxBuffer = Data()
        var verifiedDirection = false
        init(decrypt: Data, encrypt: Data) {
            decryptKey = SymmetricKey(data: decrypt)
            encryptKey = SymmetricKey(data: encrypt)
        }
        static func nonce(_ counter: UInt64) -> ChaChaPoly.Nonce {
            var n = Data(count: 4)
            withUnsafeBytes(of: counter.littleEndian) { n.append(contentsOf: $0) }
            return try! ChaChaPoly.Nonce(data: n)
        }
    }
    private var ciphers: [ObjectIdentifier: ControlCipher] = [:]
    private var eventConnection: NWConnection?
    private var eventCipher: ControlCipher?
    private var nextEventCSeq: Int = 1
    public var activeStreamUUID: String = "VideoStream.Main"
    /// Last listener bind failure (e.g. "port 7000: Address already in use"), nil once the listener is ready.
    nonisolated(unsafe) public static var lastBindError: String?

    public var boundPort: UInt16 {
        listener?.port?.rawValue ?? (requestedPort == 0 ? 7000 : requestedPort)
    }

    public init(port: UInt16 = 0) {
        self.requestedPort = port
    }

    public func resetSession() {
        queue.async {
            self.eventConnection?.cancel()
            self.eventConnection = nil
            self.eventCipher = nil
            self.nextEventCSeq = 1
            for conn in self.activeConnections {
                conn.cancel()
            }
            self.activeConnections.removeAll()
            self.ciphers.removeAll()
            HomeKitPairingService.shared.reset()
        }
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

        let listener: NWListener
        if requestedPort == 0 {
            listener = try NWListener(using: params)
        } else {
            let targetPort = NWEndpoint.Port(rawValue: requestedPort) ?? .init(integerLiteral: 7000)
            listener = try NWListener(using: params, on: targetPort)
        }
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let port = self?.boundPort ?? 7000
                NSLog("[DrivingMode][RTSP] RTSP Server Ready: listening on TCP port %d", port)
                RTSPServer.lastBindError = nil
                CarPlayLockdownService.shared.updateRtspPort(port)
                Task { @MainActor in
                    ProtocolLogger.shared.log(category: .rtsp, title: "RTSP Server Ready", detail: "Listening on port \(port)")
                }
            case .failed(let err):
                NSLog("[DrivingMode][RTSP] RTSP Server Failed: %@", err.localizedDescription)
                let wasNil = RTSPServer.lastBindError == nil
                RTSPServer.lastBindError = "port \(self?.requestedPort ?? 7000): \(err.localizedDescription)"
                if wasNil, case .posix(.EADDRINUSE) = err {
                    NSLog("[DrivingMode][RTSP] Port %d already in use — another CarPlay/AirPlay receiver (e.g. CarCast) is probably running on this device. Retrying every 1.5s.", self?.requestedPort ?? 7000)
                }
                Task { @MainActor in
                    ProtocolLogger.shared.log(category: .rtsp, title: "RTSP Server Failed", detail: err.localizedDescription)
                }
                // If port in TIME_WAIT (e.g. error 48 Address already in use), retry after 1.5s
                self?.queue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self = self, self.listener?.state != .ready else { return }
                    try? self.start()
                }
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }
        CarPlaySessionChannels.shared.onEventConnection = { [weak self] conn in
            self?.handleEventConnection(conn)
        }
        CarPlaySessionChannels.shared.start()

        listener.start(queue: queue)
    }

    public func stop() {
        resetSession()
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        activeConnections.append(connection)
        writeAppLog("[RTSP] Incoming TCP connection from \(connection.endpoint) (active=\(activeConnections.count))")
        NSLog("[DrivingMode][RTSP] Incoming TCP connection from %@ (active=%d)", String(describing: connection.endpoint), activeConnections.count)
        CarPlayLockdownService.shared.noteRtspConnection()

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            NSLog("[DrivingMode][RTSP] Connection state: %@", String(describing: state))
            switch state {
            case .failed, .cancelled:
                if let conn = connection {
                    self?.activeConnections.removeAll(where: { $0 === conn })
                    self?.ciphers[ObjectIdentifier(conn)] = nil
                }
            default:
                break
            }
        }

        connection.start(queue: queue)
        readRequest(from: connection)
    }

    private func readRequest(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            if let data = content, !data.isEmpty {
                if let cipher = self.ciphers[ObjectIdentifier(connection)] {
                    self.processEncryptedData(data, cipher: cipher, connection: connection)
                } else {
                    self.processRequestData(data, connection: connection)
                }
            }
            if !isComplete && error == nil {
                self.readRequest(from: connection)
            } else {
                NSLog("[DrivingMode][RTSP] Peer %@ closed control connection (complete=%d, error=%@, encrypted=%d)",
                      String(describing: connection.endpoint), isComplete ? 1 : 0, String(describing: error), self.ciphers[ObjectIdentifier(connection)] != nil ? 1 : 0)
            }
        }
    }

    private func processEncryptedData(_ data: Data, cipher: ControlCipher, connection: NWConnection) {
        cipher.rxBuffer.append(data)
        var plaintext = Data()
        while cipher.rxBuffer.count >= 2 {
            let b = cipher.rxBuffer
            let len = Int(b[b.startIndex]) | (Int(b[b.startIndex + 1]) << 8)
            guard b.count >= 2 + len + 16 else { break }
            let aad = b.subdata(in: b.startIndex..<(b.startIndex + 2))
            let ct = b.subdata(in: (b.startIndex + 2)..<(b.startIndex + 2 + len))
            let tag = b.subdata(in: (b.startIndex + 2 + len)..<(b.startIndex + 2 + len + 16))
            cipher.rxBuffer = b.subdata(in: (b.startIndex + 2 + len + 16)..<b.endIndex)

            func open(_ key: SymmetricKey) -> Data? {
                guard let box = try? ChaChaPoly.SealedBox(nonce: ControlCipher.nonce(cipher.rxCounter), ciphertext: ct, tag: tag) else { return nil }
                return try? ChaChaPoly.open(box, using: key, authenticating: aad)
            }
            if let pt = open(cipher.decryptKey) {
                plaintext.append(pt)
            } else if !cipher.verifiedDirection, let pt = open(cipher.encryptKey) {
                // Key direction was inverted; swap once and remember.
                NSLog("[DrivingMode][RTSP] Control channel keys were inverted — swapping read/write keys")
                swap(&cipher.decryptKey, &cipher.encryptKey)
                plaintext.append(pt)
            } else {
                NSLog("[DrivingMode][RTSP] Failed to decrypt control frame #%llu (len=%d) — dropping connection", cipher.rxCounter, len)
                connection.cancel()
                return
            }
            cipher.verifiedDirection = true
            cipher.rxCounter += 1
        }
        if !plaintext.isEmpty {
            if let line = String(data: plaintext.prefix(120), encoding: .utf8)?.components(separatedBy: "\r\n").first {
                writeAppLog("[RTSP] RX Decrypted (\(plaintext.count)b): \(line)")
                NSLog("[DrivingMode][RTSP] Decrypted request (%d bytes): %@", plaintext.count, line)
            }
            processRequestData(plaintext, connection: connection)
        }
    }

    private func sealFrames(_ data: Data, cipher: ControlCipher) -> Data {
        var out = Data()
        var offset = data.startIndex
        while offset < data.endIndex {
            let end = min(offset + 1024, data.endIndex)
            let chunk = data.subdata(in: offset..<end)
            var aad = Data()
            aad.append(UInt8(chunk.count & 0xFF)); aad.append(UInt8(chunk.count >> 8))
            if let box = try? ChaChaPoly.seal(chunk, using: cipher.encryptKey, nonce: ControlCipher.nonce(cipher.txCounter), authenticating: aad) {
                out.append(aad); out.append(box.ciphertext); out.append(box.tag)
            }
            cipher.txCounter += 1
            offset = end
        }
        return out
    }

    private func processRequestData(_ data: Data, connection: NWConnection) {
        guard let headerEndRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            // Partial data or non-HTTP header
            return
        }

        let headerData = data.subdata(in: 0..<headerEndRange.lowerBound)
        let bodyData = data.subdata(in: headerEndRange.upperBound..<data.count)

        guard let text = String(data: headerData, encoding: .utf8) else { return }

        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return }
        let tokens = requestLine.components(separatedBy: " ")
        guard tokens.count >= 2 else { return }

        let method = tokens[0]
        let uri = tokens[1]

        if method.hasPrefix("RTSP/") {
            var detail = requestLine
            if !bodyData.isEmpty, let plist = try? PropertyListSerialization.propertyList(from: bodyData, options: [], format: nil) {
                detail += " plist=\(plist)"
            }
            writeAppLog("[RTSP] Client response: \(detail)")
            NSLog("[DrivingMode][RTSP] Client response: %@", detail)
            return
        }

        var cseq = "1"
        for line in lines {
            if line.lowercased().hasPrefix("cseq:") {
                cseq = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            }
        }

        Task { @MainActor in
            ProtocolLogger.shared.log(
                category: .rtsp,
                direction: .rx,
                title: "RTSP \(method)",
                detail: "\(uri) (CSeq: \(cseq), Body: \(bodyData.count) bytes)",
                rawData: data
            )
        }

        if ["TEARDOWN", "RECORD", "GET", "SET_PARAMETER", "GET_PARAMETER"].contains(method) {
            var detail = "headers=[" + lines.dropFirst().joined(separator: " | ") + "]"
            if !bodyData.isEmpty {
                if let plist = try? PropertyListSerialization.propertyList(from: bodyData, options: [], format: nil) {
                    detail += " plist=" + String(describing: plist).replacingOccurrences(of: "\n", with: " ")
                } else {
                    detail += " body=" + (String(data: bodyData, encoding: .utf8) ?? "\(bodyData.count) bytes")
                }
            }
            NSLog("[DrivingMode][RTSP] %@ %@ %@", method, uri, String(detail.prefix(900)))
        }

        switch method {
        case "OPTIONS":
            handleOptions(cseq: cseq, connection: connection)
        case "GET":
            handleGet(uri: uri, cseq: cseq, connection: connection)
        case "ANNOUNCE":
            handleAnnounce(cseq: cseq, lines: lines, connection: connection)
        case "SETUP":
            handleSetup(uri: uri, cseq: cseq, bodyData: bodyData, connection: connection)
        case "RECORD":
            handleRecord(cseq: cseq, connection: connection)
        case "TEARDOWN":
            handleTeardown(cseq: cseq, connection: connection)
        case "GET_PARAMETER", "SET_PARAMETER":
            handleParameter(cseq: cseq, connection: connection)
        case "POST":
            handlePost(cseq: cseq, uri: uri, bodyData: bodyData, connection: connection)
        default:
            sendResponse(status: "200 OK", cseq: cseq, headers: [:], body: nil, connection: connection)
        }
    }

    private func handleOptions(cseq: String, connection: NWConnection) {
        let headers = [
            "Public": "ANNOUNCE, SETUP, RECORD, PAUSE, FLUSH, TEARDOWN, OPTIONS, POST, GET, PUT, GET_PARAMETER, SET_PARAMETER"
        ]
        sendResponse(status: "200 OK", cseq: cseq, headers: headers, body: nil, connection: connection)
    }

    private func handleAnnounce(cseq: String, lines: [String], connection: NWConnection) {
        var clientName: String?
        for line in lines {
            if line.lowercased().hasPrefix("x-apple-client-name:") {
                clientName = line.dropFirst(20).trimmingCharacters(in: .whitespaces)
            }
        }

        delegate?.rtspServerDidStartSession(clientName: clientName)
        sendResponse(status: "200 OK", cseq: cseq, headers: [:], body: nil, connection: connection)
    }

    private func handleSetup(uri: String, cseq: String, bodyData: Data, connection: NWConnection) {
        // Parse incoming binary plist if present to distinguish session vs stream setup
        var isStreamSetup = false
        if let plist = try? PropertyListSerialization.propertyList(from: bodyData, options: [], format: nil) as? [String: Any] {
            if plist["streams"] != nil {
                isStreamSetup = true
            }
            let desc = String(describing: plist).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "    ", with: " ")
            for (i, chunk) in stride(from: 0, to: desc.count, by: 700).enumerated() {
                let s = desc.index(desc.startIndex, offsetBy: chunk), e = desc.index(s, offsetBy: min(700, desc.count - chunk))
                NSLog("[DrivingMode][RTSP] SETUP %@ request plist [%d]: %@", uri, i, String(desc[s..<e]))
            }
        } else {
            NSLog("[DrivingMode][RTSP] SETUP %@ body not a plist (%d bytes)", uri, bodyData.count)
        }
        if uri.contains("VideoStream") || uri.contains("Screen/Video") {
            isStreamSetup = true
        }

        if isStreamSetup {
            if let lastComp = uri.split(separator: "/").last.map(String.init), !lastComp.isEmpty {
                self.activeStreamUUID = lastComp
                NSLog("[DrivingMode][RTSP] Active stream UUID set to %@", lastComp)
            }
            // Derive the screen stream ChaCha20-Poly1305 keys from the retained pair-verify session (CarCast @ 0x3aef88).
            if let plist = try? PropertyListSerialization.propertyList(from: bodyData, options: [], format: nil) as? [String: Any],
               let streams = plist["streams"] as? [[String: Any]] {
                for stream in streams where (stream["type"] as? NSNumber)?.intValue == 110 {
                    if let scid = (stream["streamConnectionID"] as? NSNumber)?.uint64Value,
                       let keys = HomeKitPairingService.shared.deriveDataStreamKeys(streamConnectionID: scid) {
                        AirPlayScreenReceiver.pendingStreamKeys = keys
                        // Variant: signed-decimal streamConnectionID in the salt.
                        let signed = Int64(bitPattern: scid)
                        AirPlayScreenReceiver.extraCandidateKeys = [
                            "DataStream-Output-Encryption-Key", "DataStream-Input-Encryption-Key"
                        ].compactMap { HomeKitPairingService.shared.deriveKey(salt: "DataStream-Salt\(signed)", info: $0) }
                        NSLog("[DrivingMode][RTSP] Screen stream keys ready (streamConnectionID=%llu)", scid)
                    }
                }
            }
            // CSeq 11: Screen/Video(110) stream setup -> route H.264 to port 7100
            let respDict: [String: Any] = [
                "streams": [
                    [
                        "dataPort": 7100,
                        "type": 110
                    ]
                ]
            ]
            let body = (try? PropertyListSerialization.data(fromPropertyList: respDict, format: .binary, options: 0)) ?? Data()
            let headers = [
                "Content-Type": "application/x-apple-binary-plist"
            ]
            sendResponse(status: "200 OK", cseq: cseq, headers: headers, body: body, connection: connection)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.requestKeyFrame()
            }
        } else {
            // CSeq 6: Session SETUP -> enable features & event/keepalive/timing ports
            let channels = CarPlaySessionChannels.shared
            channels.onEventConnection = { [weak self] conn in
                self?.handleEventConnection(conn)
            }
            channels.start()
            if !channels.waitUntilReady() {
                NSLog("[DrivingMode][RTSP] WARNING: session channel listeners not ready (event=%d timing=%d keepAlive=%d)", channels.eventPort, channels.timingPort, channels.keepAlivePort)
            }
            let respDict: [String: Any] = [
                "enabledFeatures": [
                    "viewAreas",
                    "uiContext"
                ],
                "eventPort": Int(channels.eventPort),
                "keepAlivePort": Int(channels.keepAlivePort),
                "timingPort": Int(channels.timingPort)
            ]
            NSLog("[DrivingMode][RTSP] Session SETUP reply: eventPort=%d timingPort=%d keepAlivePort=%d", channels.eventPort, channels.timingPort, channels.keepAlivePort)
            let body = (try? PropertyListSerialization.data(fromPropertyList: respDict, format: .binary, options: 0)) ?? Data()
            let headers = [
                "Content-Type": "application/x-apple-binary-plist"
            ]
            sendResponse(status: "200 OK", cseq: cseq, headers: headers, body: body, connection: connection)
        }
    }

    private func handleGet(uri: String, cseq: String, connection: NWConnection) {
        if uri.contains("/info") {
            let carName = UserDefaults.standard.string(forKey: "drivingmode.car.name") ?? "DrivingMode"
            let deviceId = UserDefaults.standard.string(forKey: "drivingmode.device.id") ?? "02:55:4E:44:52:56"

            let cleanDeviceId = deviceId.replacingOccurrences(of: ":", with: "").uppercased()
            let macWithColons: String
            if cleanDeviceId.count == 12 {
                macWithColons = stride(from: 0, to: 12, by: 2)
                    .map { cleanDeviceId[cleanDeviceId.index(cleanDeviceId.startIndex, offsetBy: $0)..<cleanDeviceId.index(cleanDeviceId.startIndex, offsetBy: $0 + 2)] }
                    .joined(separator: ":")
            } else {
                macWithColons = deviceId
            }

            // Authentic 107-byte multi-touch digitizer descriptor with 1920x1028 resolution (CarCast 0x100555ce4 / 0x593cfa)
            // Patched at offsets 0x25..0x26 (X max 1920 = 0x0780), 0x30..0x31 (Y max 1028 = 0x0404),
            // 0x58..0x59 (X max 1920 = 0x0780), 0x63..0x64 (Y max 1028 = 0x0404).
            let touchDescriptorHex = "050d0904a1010922a1020938750895018102150025010933750195018102950781030501268007093075109501810226040409318102c0050d0922a1020938750895018102150025010933750195018102950781030501268007093075109501810226040409318102c0c0"
            let touchDescriptor = hexToData(touchDescriptorHex)

            // Authentic 70-byte Knob & Buttons descriptor (CarCast 0x100555894 / 0x593a4e):
            // Buttons: bit 0 = Select (0x01), bit 1 = Home (0x02), bit 2 = Back (0x04)
            // Relative X, Y, Wheel (rotation)
            let knobDescriptorHex = "05010908a1010509090115002501750195018102050c0a23020a2402950281029505810105010901a100093009311581257f750895028102c009381581257f750895018106c0"
            let knobDescriptor = hexToData(knobDescriptorHex)

            // Authentic 22-byte proximity sensor descriptor (CarCast 0x100555a20 / 0x593b16)
            let proximityDescriptorHex = "05200911a10105200ab10415002501750895018102c0"
            let proximityDescriptor = hexToData(proximityDescriptorHex)

            // audioFormats / audioLatencies / bluetoothIDs / featuresEx / firmwareRevision: verified against the working
            // CarCast receiver (libcarcast.so platform CopyProperty @ 0x33f6bc, audioFormats builder @ 0x34088c,
            // audioLatencies builder @ 0x340a90, /info builder @ 0x39a650). Stream types: 100=MainAudio, 101=AltAudio,
            // 102=MainHighAudio, 106/107=speech streams. Without audioFormats the iPhone tears the session down after RECORD.
            func audioFormat(_ type: Int, _ audioType: String, input: UInt32, output: UInt32) -> [String: Any] {
                ["type": type, "audioType": audioType, "audioInputFormats": Int(input), "audioOutputFormats": Int(output)]
            }
            let audioFormats: [[String: Any]] = [
                audioFormat(100, "compatibility", input: 0x54, output: 0x8854),
                audioFormat(101, "compatibility", input: 0, output: 0x8800),
                audioFormat(100, "alert", input: 0, output: 0x4000_8800),
                audioFormat(100, "default", input: 0x3000_0050, output: 0x3000_0050),
                audioFormat(100, "media", input: 0, output: 0x8800),
                audioFormat(100, "telephony", input: 0x7000_0150, output: 0x7000_0150),
                audioFormat(100, "speechRecognition", input: 0x2000_0040, output: 0x2000_0040),
                audioFormat(101, "default", input: 0, output: 0x4000_8800),
                audioFormat(102, "media", input: 0, output: 0xC0_0000),
                audioFormat(106, "speechRecognition", input: 0, output: 0x4000_4000),
                audioFormat(107, "speechRecognition", input: 0x1000_0010, output: 0)
            ]
            let audioLatencies: [[String: Any]] = [
                ["type": 100],
                ["type": 100, "audioType": "default"],
                ["type": 100, "audioType": "media"],
                ["type": 100, "audioType": "telephony"],
                ["type": 100, "audioType": "speechRecognition"],
                ["type": 100, "audioType": "alert"],
                ["type": 101],
                ["type": 101, "audioType": "default"],
                ["type": 102, "audioType": "media"]
            ].map { entry -> [String: Any] in
                var e = entry
                e["inputLatencyMicros"] = 0
                e["outputLatencyMicros"] = 0
                return e
            }

            let infoDict: [String: Any] = [
                // Required when "uiContext" is in enabledFeatures — otherwise airplayd fails activation with
                // "carEndpoint_checkCarPlayFeatureAcceptance failed: uiContextLastOnDisplayURLs or uiContextNowOnDisplayURLs
                // structures not found" (-16720) and sends TEARDOWN. Values from CarCast (libcarcast.so @ 0x340080).
                "uiContextLastOnDisplayURLs": ["maps:", "mobilephone:", "messages:", "nowplaying:"],
                "uiContextNowOnDisplayURLs": ["nowplaying:", "maps:"],
                "audioFormats": audioFormats,
                "audioLatencies": audioLatencies,
                "bluetoothIDs": [macWithColons],
                "featuresEx": "gAIEBGEAAABA",
                "firmwareRevision": "1",
                "hardwareRevision": "1",
                "sourceVersion": "509.11",
                "features": 416679199360 as UInt64,
                "statusFlags": 4,
                "model": "DrivingMode",
                "manufacturer": "Apple",
                "deviceID": macWithColons,
                "name": carName,
                "nightMode": true,
                "rightHandDrive": false,
                "keepAliveLowPower": true,
                "keepAliveSendStatsAsBody": true,
                "altScreenSuggestUIURLs": [
                    "maps:/car/instrumentcluster",
                    "maps:/car/instrumentcluster/map",
                    "maps:/car/instrumentcluster/instructioncard"
                ],
                "modes": [
                    "resources": [
                        ["resourceID": 1, "transferType": 1, "transferPriority": 100, "takeConstraint": 100, "borrowConstraint": 100],
                        ["resourceID": 2, "transferType": 1, "transferPriority": 100, "takeConstraint": 100, "borrowConstraint": 100]
                    ],
                    "appStates": [
                        ["appStateID": 2, "state": false],
                        ["appStateID": 1, "speechMode": -1],
                        ["appStateID": 3, "state": false]
                    ],
                    "initialPermanentEntity": [
                        ["permanentEntity": 1, "resourceID": 1],
                        ["permanentEntity": 1, "resourceID": 2]
                    ]
                ],
                "displayPanels": [
                    [
                        "uid": "DisplayPanel.Main",
                        "widthPixels": 1920,
                        "heightPixels": 1028,
                        "widthPhysical": 114,
                        "heightPhysical": 61,
                        "initialVideoStreams": [
                            [
                                "uuid": "VideoStream.Main",
                                "originXPixels": 0,
                                "originYPixels": 0,
                                "zIndex": 0
                            ]
                        ],
                        "properties": []
                    ]
                ],
                "displays": [
                    [
                        "uuid": "VideoStream.Main",
                        "type": 110,
                        "maxFPS": 60,
                        "features": 12,
                        "primaryInputDevice": 0,
                        "widthPixels": 1920,
                        "heightPixels": 1028,
                        "widthPhysical": 114,
                        "heightPhysical": 61,
                        "initialViewArea": 0,
                        "viewAreas": [
                            [
                                "widthPixels": 1920,
                                "heightPixels": 1028,
                                "originXPixels": 0,
                                "originYPixels": 0,
                                "viewAreaStatusBarEdge": 0,
                                "viewAreaSupportsFocusTransfer": false,
                                "viewAreaTransitionControl": false
                            ]
                        ]
                    ]
                ],
                "hidDevices": [
                    [
                        "uuid": "0",
                        "name": "Touch Screen",
                        "displayUUID": "VideoStream.Main",
                        "hidCountryCode": 0,
                        "hidProductID": 0,
                        "hidVendorID": 0,
                        "hidDescriptor": touchDescriptor
                    ],
                    [
                        "uuid": "1",
                        "name": "Knob & Buttons",
                        "displayUUID": "VideoStream.Main",
                        "hidCountryCode": 0,
                        "hidProductID": 0,
                        "hidVendorID": 0,
                        "hidDescriptor": knobDescriptor
                    ],
                    [
                        "uuid": "2",
                        "name": "Proximity Sensor",
                        "displayUUID": "VideoStream.Main",
                        "hidCountryCode": 0,
                        "hidProductID": 0,
                        "hidVendorID": 0,
                        "hidDescriptor": proximityDescriptor
                    ]
                ]
            ]

            let bodyData: Data
            if let serialized = try? PropertyListSerialization.data(fromPropertyList: infoDict, format: .binary, options: 0) {
                bodyData = serialized
            } else {
                bodyData = Data()
            }

            let headers = [
                "Content-Type": "application/x-apple-binary-plist"
            ]
            sendResponse(status: "200 OK", cseq: cseq, headers: headers, body: bodyData, connection: connection)
        } else {
            sendResponse(status: "200 OK", cseq: cseq, headers: [:], body: nil, connection: connection)
        }
    }

    private func handleRecord(cseq: String, connection: NWConnection) {
        sendResponse(status: "200 OK", cseq: cseq, headers: [:], body: nil, connection: connection)
    }

    private func handleTeardown(cseq: String, connection: NWConnection) {
        delegate?.rtspServerDidEndSession()
        sendResponse(status: "200 OK", cseq: cseq, headers: [:], body: nil, connection: connection)
    }

    private func handleParameter(cseq: String, connection: NWConnection) {
        sendResponse(status: "200 OK", cseq: cseq, headers: [:], body: nil, connection: connection)
    }

    private func handlePost(cseq: String, uri: String, bodyData: Data, connection: NWConnection) {
        if uri.contains("/pair-setup") {
            let (resp, hkpState) = HomeKitPairingService.shared.exchangePairSetup(data: bodyData)
            var headers = [
                "Content-Type": "application/octet-stream"
            ]
            if let state = hkpState {
                headers["X-Apple-HKP"] = "\(state)"
            }
            sendResponse(status: "200 OK", cseq: cseq, headers: headers, body: resp ?? Data([0x06, 0x01, 0x02]), connection: connection)
        } else if uri.contains("/pair-verify") {
            let resp = HomeKitPairingService.shared.exchangePairVerify(data: bodyData)
            let headers = [
                "Content-Type": "application/octet-stream"
            ]
            sendResponse(status: "200 OK", cseq: cseq, headers: headers, body: resp ?? Data([0x06, 0x01, 0x04]), connection: connection)
            if let keys = HomeKitPairingService.shared.takeControlKeys() {
                ciphers[ObjectIdentifier(connection)] = ControlCipher(decrypt: keys.decrypt, encrypt: keys.encrypt)
                NSLog("[DrivingMode][RTSP] pair-verify complete — control channel now encrypted for %@", String(describing: connection.endpoint))
            }
        } else if uri.contains("/auth-setup") {
            let resp = HomeKitPairingService.shared.exchangeAuthSetup(data: bodyData)
            let headers = [
                "Content-Type": "application/octet-stream"
            ]
            sendResponse(status: "200 OK", cseq: cseq, headers: headers, body: resp ?? Data(), connection: connection)
        } else if uri.contains("/command") {
            // CSeq 9, 10, 12: modesChanged, disableBluetooth -> return empty binary plist
            let emptyPlist = (try? PropertyListSerialization.data(fromPropertyList: [String: Any](), format: .binary, options: 0)) ?? Data()
            let headers = [
                "Content-Type": "application/x-apple-binary-plist"
            ]
            sendResponse(status: "200 OK", cseq: cseq, headers: headers, body: emptyPlist, connection: connection)
        } else if uri.contains("/feedback") {
            let emptyPlist = (try? PropertyListSerialization.data(fromPropertyList: [String: Any](), format: .binary, options: 0)) ?? Data()
            let headers = [
                "Content-Type": "application/x-apple-binary-plist"
            ]
            sendResponse(status: "200 OK", cseq: cseq, headers: headers, body: emptyPlist, connection: connection)
        } else {
            sendResponse(status: "200 OK", cseq: cseq, headers: [:], body: nil, connection: connection)
        }
    }

    private var pendingKeyFrameRequest = false

    public func requestKeyFrame(uuid: String? = nil) {
        queue.async {
            // Authentic CarCast 0x10052f584 parity:
            // Send forceKeyFrame with the active session stream UUID directly on eventConnection.
            guard let evConn = self.eventConnection, let evCipher = self.eventCipher else {
                writeAppLog("[RTSP] Cannot request keyframe yet: eventConnection not ready, queuing request")
                self.pendingKeyFrameRequest = true
                return
            }
            self.pendingKeyFrameRequest = false

            var targets = ["VideoStream.Main", "DisplayPanel.Main"]
            if let u = uuid, !u.isEmpty, !targets.contains(u) {
                targets.append(u)
            }
            if !self.activeStreamUUID.isEmpty && !targets.contains(self.activeStreamUUID) {
                targets.append(self.activeStreamUUID)
            }

            for targetUUID in targets {
                let dict: [String: Any] = [
                    "type": "forceKeyFrame",
                    "params": [
                        "uuid": targetUUID
                    ]
                ]
                guard let bodyData = try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0) else { continue }

                let cseq = self.nextEventCSeq
                self.nextEventCSeq += 1

                var req = "POST /command RTSP/1.0\r\n"
                req += "CSeq: \(cseq)\r\n"
                req += "Content-Type: application/x-apple-binary-plist\r\n"
                req += "Content-Length: \(bodyData.count)\r\n\r\n"

                var reqData = req.data(using: .utf8) ?? Data()
                reqData.append(bodyData)
                reqData = self.sealFrames(reqData, cipher: evCipher)

                evConn.send(content: reqData, contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed { err in
                    if let err = err {
                        writeAppLog("[RTSP] Error sending forceKeyFrame(\(targetUUID)) on eventConnection: \(err.localizedDescription)")
                        NSLog("[DrivingMode][RTSP] Error sending forceKeyFrame(%@) on eventConnection: %@", targetUUID, err.localizedDescription)
                    } else {
                        writeAppLog("[RTSP] forceKeyFrame(\(targetUUID)) sent on eventConnection (cseq=\(cseq), bytes=\(reqData.count))")
                        NSLog("[DrivingMode][RTSP] forceKeyFrame(%@) sent on eventConnection (cseq=%d, bytes=%d)", targetUUID, cseq, reqData.count)
                    }
                })
            }
        }
    }

    private func handleEventConnection(_ connection: NWConnection) {
        queue.async {
            writeAppLog("[EventChannel] New event channel connection from \(connection.endpoint)")
            NSLog("[DrivingMode][EventChannel] New event channel connection from %@", String(describing: connection.endpoint))
            guard let keys = HomeKitPairingService.shared.deriveEventsKeys() else {
                writeAppLog("[EventChannel] ERROR: Could not derive Events keys")
                NSLog("[DrivingMode][EventChannel] ERROR: Could not derive Events keys")
                return
            }
            let cipher = ControlCipher(decrypt: keys.decrypt, encrypt: keys.encrypt)
            self.eventConnection = connection
            self.eventCipher = cipher
            self.nextEventCSeq = 1
            writeAppLog("[EventChannel] Events cipher configured (read/write keys derived)")

            connection.stateUpdateHandler = { [weak self, weak connection] state in
                writeAppLog("[EventChannel] State update: \(state)")
                NSLog("[DrivingMode][EventChannel] State: %@", String(describing: state))
                switch state {
                case .ready:
                    writeAppLog("[EventChannel] Event channel is READY! Immediately sending forceKeyFrame to CarPlay")
                    self?.requestKeyFrame()
                case .failed, .cancelled:
                    if let c = connection {
                        self?.queue.async {
                            if self?.eventConnection === c {
                                self?.eventConnection = nil
                                self?.eventCipher = nil
                            }
                        }
                    }
                default:
                    break
                }
            }

            connection.start(queue: self.queue)
            self.readEventChannel(from: connection, cipher: cipher)
        }
    }

    private func readEventChannel(from connection: NWConnection, cipher: ControlCipher) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] content, _, isComplete, error in
            guard let self = self, let connection = connection else { return }
            if let data = content, !data.isEmpty {
                self.processEncryptedEventData(data, cipher: cipher, connection: connection)
            }
            if error == nil && !(content == nil && isComplete) {
                self.readEventChannel(from: connection, cipher: cipher)
            } else {
                writeAppLog("[EventChannel] Peer closed event connection (complete=\(isComplete ? 1 : 0), error=\(String(describing: error)))")
            }
        }
    }

    private func processEncryptedEventData(_ data: Data, cipher: ControlCipher, connection: NWConnection) {
        cipher.rxBuffer.append(data)
        while cipher.rxBuffer.count >= 18 {
            let frameLen = Int(cipher.rxBuffer[0]) | (Int(cipher.rxBuffer[1]) << 8)
            let totalLen = 2 + frameLen + 16
            if cipher.rxBuffer.count < totalLen { break }

            let frameData = cipher.rxBuffer.subdata(in: 0..<totalLen)
            cipher.rxBuffer.removeSubrange(0..<totalLen)

            let aad = frameData.subdata(in: 0..<2)
            let ciphertext = frameData.subdata(in: 2..<(2 + frameLen))
            let tag = frameData.subdata(in: (2 + frameLen)..<totalLen)

            guard let box = try? ChaChaPoly.SealedBox(nonce: ControlCipher.nonce(cipher.rxCounter), ciphertext: ciphertext, tag: tag),
                  let plaintext = try? ChaChaPoly.open(box, using: cipher.decryptKey, authenticating: aad) else {
                writeAppLog("[EventChannel] ChaCha20 decrypt failed on event frame (rxCounter=\(cipher.rxCounter))")
                break
            }
            cipher.rxCounter += 1
            if let str = String(data: plaintext, encoding: .utf8) {
                let firstLine = str.components(separatedBy: "\r\n").first ?? str
                writeAppLog("[EventChannel] RX Decrypted (\(plaintext.count)b): \(firstLine)")
            } else {
                writeAppLog("[EventChannel] RX Decrypted (\(plaintext.count)b)")
            }
        }
    }

    public func sendTouchHIDReport(action: Int, x: Double, y: Double, uuid: String = "0") {
        queue.async {
            let connection = self.eventConnection ?? self.activeConnections.last(where: { self.ciphers[ObjectIdentifier($0)] != nil }) ?? self.activeConnections.last
            guard connection != nil else {
                NSLog("[DrivingMode][RTSP] Cannot send touch — no active connection")
                return
            }

            // Authentic 12-byte multi-touch input report (CarCast 0x100059f94 / 107-byte descriptor):
            // Finger 1 (bytes 0..5):
            //   Byte 0: Contact ID (0x00)
            //   Byte 1: Tip switch bit (0x01 = down/contact, 0x00 = up/released)
            //   Byte 2..3: X (0..1920) Little Endian
            //   Byte 4..5: Y (0..1028) Little Endian
            // Finger 2 (bytes 6..11):
            //   Byte 6: Contact ID (0x01)
            //   Byte 7: Tip switch (0x00 = up)
            //   Byte 8..11: X, Y (0x00)
            let isDown = (action == 1 || action == 2)
            let xClamped = UInt16(min(max(x * 1920.0, 0.0), 1920.0))
            let yClamped = UInt16(min(max(y * 1028.0, 0.0), 1028.0))

            var report = Data(count: 12)
            report[0] = 0x00
            report[1] = isDown ? 0x01 : 0x00
            report[2] = UInt8(xClamped & 0xFF)
            report[3] = UInt8((xClamped >> 8) & 0xFF)
            report[4] = UInt8(yClamped & 0xFF)
            report[5] = UInt8((yClamped >> 8) & 0xFF)
            report[6] = 0x01
            report[7] = 0x00
            report[8] = 0x00
            report[9] = 0x00
            report[10] = 0x00
            report[11] = 0x00

            writeAppLog("[HID] Touch dispatch: down=\(isDown ? 1 : 0) x=\(xClamped) y=\(yClamped)")
            self.dispatchHIDReport(report, uuid: uuid, connection: connection)
        }
    }

    public func sendHomeButtonHIDReport() {
        queue.async {
            let connection = self.eventConnection ?? self.activeConnections.last(where: { self.ciphers[ObjectIdentifier($0)] != nil }) ?? self.activeConnections.last
            guard connection != nil else {
                NSLog("[DrivingMode][RTSP] Cannot send home button — no active connection")
                return
            }

            // Authentic 4-byte Knob & Buttons report:
            // Byte 0: Bit 0=Select, Bit 1=Home, Bit 2=Back
            // Byte 1: Rotation
            // Byte 2..3: Relative Pan X, Y
            let downReport = Data([0x02, 0x00, 0x00, 0x00])
            let upReport = Data([0x00, 0x00, 0x00, 0x00])

            self.dispatchHIDReport(downReport, uuid: "1", connection: connection)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.queue.async {
                    self?.dispatchHIDReport(upReport, uuid: "1", connection: connection)
                }
            }
        }
    }

    private func dispatchHIDReport(_ report: Data, uuid: String, connection: NWConnection?) {
        let dict: [String: Any] = [
            "type": "hidSendReport",
            "uuid": uuid,
            "hidReport": report
        ]
        guard let bodyData = try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0) else { return }

        let targetConn: NWConnection
        let targetCipher: ControlCipher?
        let cseq: Int

        if let evConn = self.eventConnection, let evCipher = self.eventCipher {
            targetConn = evConn
            targetCipher = evCipher
            cseq = self.nextEventCSeq
            self.nextEventCSeq += 1
            writeAppLog("[HID] Routing to eventPort channel (cseq=\(cseq), bytes=\(report.count))")
        } else if let conn = connection {
            targetConn = conn
            targetCipher = self.ciphers[ObjectIdentifier(conn)]
            cseq = self.nextServerCSeq
            self.nextServerCSeq += 1
            writeAppLog("[HID] WARNING: No eventPort channel; falling back to control connection (cseq=\(cseq))")
        } else {
            writeAppLog("[HID] ERROR: Cannot dispatch HID — no connection available")
            return
        }

        var req = "POST /command RTSP/1.0\r\n"
        req += "CSeq: \(cseq)\r\n"
        req += "Content-Type: application/x-apple-binary-plist\r\n"
        req += "Content-Length: \(bodyData.count)\r\n\r\n"

        var reqData = req.data(using: .utf8) ?? Data()
        reqData.append(bodyData)

        if let cipher = targetCipher {
            reqData = self.sealFrames(reqData, cipher: cipher)
        }

        targetConn.send(content: reqData, contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed { err in
            if let err = err {
                writeAppLog("[HID] Error dispatching HID to uuid \(uuid): \(err.localizedDescription)")
            } else {
                writeAppLog("[HID] Sent HID report to uuid \(uuid): \(report.count)b on \(targetConn === self.eventConnection ? "eventChannel" : "controlChannel") (cseq=\(cseq))")
            }
        })
    }

    private func sendResponse(
        status: String,
        cseq: String,
        headers: [String: String],
        body: Data?,
        connection: NWConnection
    ) {
        var resp = "RTSP/1.0 \(status)\r\n"
        resp += "Server: AirTunes/509.11\r\n"
        resp += "CSeq: \(cseq)\r\n"

        for (k, v) in headers {
            resp += "\(k): \(v)\r\n"
        }

        if let body = body, !body.isEmpty {
            resp += "Content-Length: \(body.count)\r\n\r\n"
            var respData = resp.data(using: .utf8) ?? Data()
            respData.append(body)
            if let cipher = ciphers[ObjectIdentifier(connection)] { respData = sealFrames(respData, cipher: cipher) }
            connection.send(content: respData, contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed { _ in })
        } else {
            resp += "Content-Length: 0\r\n\r\n"
            var respData = resp.data(using: .utf8) ?? Data()
            if let cipher = ciphers[ObjectIdentifier(connection)] { respData = sealFrames(respData, cipher: cipher) }
            connection.send(content: respData, contentContext: .defaultMessage, isComplete: false, completion: .contentProcessed { _ in })
        }

        Task { @MainActor in
            ProtocolLogger.shared.log(
                category: .rtsp,
                direction: .tx,
                title: "RTSP \(status)",
                detail: "CSeq: \(cseq) Body: \(body?.count ?? 0) bytes"
            )
        }
    }

    private func hexToData(_ hex: String) -> Data {
        var data = Data()
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let nextIdx = hex.index(idx, offsetBy: 2)
            if let byte = UInt8(hex[idx..<nextIdx], radix: 16) {
                data.append(byte)
            }
            idx = nextIdx
        }
        return data
    }
}
