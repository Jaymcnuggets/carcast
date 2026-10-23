//
//  DrivingModeTests.swift
//  DrivingModeTests
//
//  Unit tests verifying protocol parity, packet framing, and vehicle catalog.
//

import XCTest
import Network
@testable import DrivingMode

final class DrivingModeTests: XCTestCase {

    func testCarBrandCatalog() {
        let catalog = CarBrandCatalog.shared
        XCTAssertFalse(catalog.brands.isEmpty, "Catalog should have loaded car brands")

        let lexus = catalog.brand(for: "lexus")
        XCTAssertNotNil(lexus)
        XCTAssertEqual(lexus?.oemLabel, "LEXUS")

        let tesla = catalog.brand(for: "tesla")
        XCTAssertNotNil(tesla)
        XCTAssertEqual(tesla?.title, "Tesla")

        let porsche = catalog.brand(for: "porsche")
        XCTAssertNotNil(porsche)
    }

    func testIAP2PacketFramingAndChecksum() {
        let payload = Data([0x01, 0x02, 0x03, 0x04])
        let packet = iAP2Packet(
            controlByte: iAP2Packet.ControlFlag.ack.rawValue,
            packetSeq: 5,
            ackSeq: 3,
            sessionID: 1,
            payload: payload
        )

        let encoded = packet.encode()
        XCTAssertGreaterThan(encoded.count, 9)
        XCTAssertEqual(encoded[0], 0xFF)
        XCTAssertEqual(encoded[1], 0x5A)

        let (decodedOpt, consumed) = iAP2Packet.decode(from: encoded)
        XCTAssertNotNil(decodedOpt)
        XCTAssertEqual(consumed, encoded.count)

        if let decoded = decodedOpt {
            XCTAssertEqual(decoded.controlByte, iAP2Packet.ControlFlag.ack.rawValue)
            XCTAssertEqual(decoded.packetSeqNumber, 5)
            XCTAssertEqual(decoded.ackSeqNumber, 3)
            XCTAssertEqual(decoded.sessionID, 1)
            XCTAssertEqual(decoded.payload, payload)
        }
    }

    func testIdentificationPayloadGeneration() {
        let engine = iAP2ProtocolEngine()
        let payload = engine.buildIdentificationPayload(
            carName: "DrivingMode-TEST",
            macAddress: "02:55:4E:22:33:44",
            wifiSSID: "TestWiFi",
            wifiPassword: "SecretPassword123",
            wifiChannel: 36,
            linkLocalIPv6: "fe80::1"
        )

        XCTAssertFalse(payload.isEmpty)
        // Message ID 0x1D01
        XCTAssertEqual(payload[0], 0x1D)
        XCTAssertEqual(payload[1], 0x01)
    }

    @MainActor
    func testConfigDefaults() {
        let config = DrivingModeConfig.shared
        XCTAssertFalse(config.carName.isEmpty)
        XCTAssertTrue(config.carName.hasPrefix("DrivingMode"))
        XCTAssertEqual(config.displayPreset, .fitScreen)
        XCTAssertEqual(config.drivingPosition, .leftHandDrive)
    }

    @MainActor
    func testDashcamConfigDefaults() {
        let config = DrivingModeConfig.shared
        XCTAssertFalse(config.isDashcamEnabled)
        XCTAssertFalse(config.isDashcamAudioEnabled)
        XCTAssertEqual(config.dashcamStorageLimitMB, 3072) // 3 GB
        XCTAssertEqual(config.impactSensitivityG, 2.5, accuracy: 0.01)
    }

    func testDashcamStorageManagerCreationAndPruning() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = DashcamStorageManager(baseDirectory: tempDir, quotaBytes: 10 * 1024 * 1024) // 10 MB quota for test
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.recordingsDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.emergencyDirectory.path))
        
        // Create 3 dummy 4 MB recording files
        let dummyData = Data(repeating: 0xAA, count: 4 * 1024 * 1024)
        let file1 = storage.recordingsDirectory.appendingPathComponent("dashcam_20261023_100000.mp4")
        let file2 = storage.recordingsDirectory.appendingPathComponent("dashcam_20261023_100500.mp4")
        let file3 = storage.recordingsDirectory.appendingPathComponent("dashcam_20261023_101000.mp4")
        
        try dummyData.write(to: file1)
        // Give slightly different creation times
        try dummyData.write(to: file2)
        try dummyData.write(to: file3)
        
        // 12 MB total > 10 MB quota -> enforcePruning should remove file1 (oldest)
        storage.enforceQuota()
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: file1.path), "Oldest file should have been pruned")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file2.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file3.path))
        
        // Lock file2 as emergency
        let emergencyFile = storage.lockAsEmergency(fileURL: file2)
        XCTAssertNotNil(emergencyFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: emergencyFile!.path))
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testImpactDetectionSpikeAndDebounce() {
        let service = ImpactDetectionService(thresholdG: 2.5, debounceSeconds: 5.0)
        var triggeredCount = 0
        service.onImpact = { _ in
            triggeredCount += 1
        }

        // Normal driving: 1.0G (gravity only)
        service.processAcceleration(x: 0.1, y: 0.2, z: 0.98)
        XCTAssertEqual(triggeredCount, 0)

        // Hard collision: 2.8G deceleration
        service.processAcceleration(x: 1.2, y: -2.3, z: 0.9)
        XCTAssertEqual(triggeredCount, 1)

        // Secondary bounce 1 second later (should be debounced)
        service.processAcceleration(x: 1.5, y: -2.5, z: 1.0)
        XCTAssertEqual(triggeredCount, 1, "Should debounce subsequent impacts within window")
    }

    @MainActor
    func testDashcamManagerLifecycle() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = DashcamStorageManager(baseDirectory: tempDir)
        let manager = DashcamManager(storageManager: storage)
        XCTAssertFalse(manager.isRecording)

        // Trigger manual emergency save event
        manager.saveCurrentEvent(reason: "User button")
        XCTAssertNotNil(manager.lastEmergencyEvent)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @MainActor
    func testSteeringWheelRemoteKeyBinding() {
        let service = SteeringWheelRemoteService.shared
        var homeTriggered = false
        var siriTriggered = false
        var emergencyTriggered = false

        service.onHomePressed = { homeTriggered = true }
        service.onSiriPressed = { siriTriggered = true }
        service.onEmergencySavePressed = { emergencyTriggered = true }

        service.handleKeyInput("h")
        XCTAssertTrue(homeTriggered)

        service.handleKeyInput("s")
        XCTAssertTrue(siriTriggered)

        service.handleKeyInput("e")
        XCTAssertTrue(emergencyTriggered)
    }

    @MainActor
    func testVehicleTelemetry() {
        let telemetry = VehicleTelemetry.shared
        telemetry.updateNowPlaying(
            title: "Test Track",
            artist: "Test Artist",
            album: "Test Album",
            duration: 300,
            elapsed: 150
        )

        XCTAssertEqual(telemetry.currentTrackTitle, "Test Track")
        XCTAssertEqual(telemetry.currentArtist, "Test Artist")
        XCTAssertEqual(telemetry.trackProgress, 0.5, accuracy: 0.01)
    }

    func testAirPlayScreenHeaderParsing() {
        // Real CarPlay screen header: 128 bytes, little-endian payload size + payload type (1 = avcC codec config)
        var headerData = Data(count: AirPlayScreenHeader.size)
        headerData[0] = 0x29 // 41-byte avcC payload
        headerData[4] = 0x01
        headerData[6] = 0x16
        headerData[7] = 0x01

        let parsed = AirPlayScreenHeader.parse(from: headerData)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.payloadLength, 41)
        XCTAssertEqual(parsed?.opcode, .videoConfig)
        XCTAssertEqual(parsed?.flags, 0x0116)
    }

    @MainActor
    func testProtocolLoggerCircularCapacity() {
        let logger = ProtocolLogger.shared
        logger.clear()
        XCTAssertTrue(logger.messages.isEmpty)

        for i in 0..<100 {
            logger.log(
                category: .iap2,
                direction: .rx,
                title: "Test Message \(i)",
                detail: "Details for \(i)"
            )
        }

        XCTAssertEqual(logger.messages.count, 100)
        XCTAssertEqual(logger.messages.last?.title, "Test Message 99")
        logger.clear()
    }

    func testWiFiBonjourBroadcastAndDiscovery() async throws {
        let advertiser = AirPlayBonjourAdvertiser(port: 7000)
        let testName = "DrivingMode-UnitTest-\(UUID().uuidString.prefix(6))"
        advertiser.startAdvertising(name: testName, deviceId: "02:55:4E:BB:CC:DD")

        let exp = expectation(description: "Bonjour service discovered over local network")

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_drivingmode._tcp.", domain: "local.")
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: descriptor, using: params)

        browser.browseResultsChangedHandler = { results, _ in
            for res in results {
                if case let .service(name, _, _, _) = res.endpoint {
                    if name.contains(testName) {
                        exp.fulfill()
                        return
                    }
                }
            }
        }
        browser.start(queue: .main)

        await fulfillment(of: [exp], timeout: 6.0)

        browser.cancel()
        advertiser.stopAdvertising()
    }

    func testCarPlayReceiverStateTransitions() async throws {
        let manager = await CarPlayManager.shared
        await manager.startReceiver()
        var state = await manager.state
        XCTAssertEqual(state, .waitingForPhone)

        await manager.startLocalSimulation()
        let isStreaming = await manager.isStreamingActive
        state = await manager.state
        XCTAssertTrue(isStreaming)
        XCTAssertEqual(state, .streaming)

        await manager.stopReceiver()
        state = await manager.state
        let stoppedStreaming = await manager.isStreamingActive
        XCTAssertEqual(state, .idle)
        XCTAssertFalse(stoppedStreaming)
    }

    func testStopThenStartCycleReset() async throws {
        let manager = await CarPlayManager.shared
        await manager.startReceiver()
        var state = await manager.state
        XCTAssertEqual(state, .waitingForPhone)

        // User hits Stop
        await manager.stopReceiver()
        state = await manager.state
        XCTAssertEqual(state, .idle)

        // User hits Start again -> must cleanly transition back to waitingForPhone
        await manager.startReceiver()
        state = await manager.state
        XCTAssertEqual(state, .waitingForPhone)

        await manager.stopReceiver()
        state = await manager.state
        XCTAssertEqual(state, .idle)
    }

    func testWiFiNetworkServicePasswordPersistence() {
        let wifi = WiFiNetworkService.shared
        let testSSID = "TestNetwork_\(UUID().uuidString.prefix(6))"
        let testPwd = "SecretPassword123"

        XCTAssertNil(wifi.getPassword(for: testSSID))

        wifi.savePassword(testPwd, for: testSSID)
        XCTAssertEqual(wifi.getPassword(for: testSSID), testPwd)

        wifi.forgetPassword(for: testSSID)
        XCTAssertNil(wifi.getPassword(for: testSSID))
    }

    func testStartCarPlayInfo0x4301Generation() {
        let engine = iAP2ProtocolEngine()
        let payload = engine.buildStartCarPlayPayload(ip: "192.168.1.150", port: 7000, deviceId: "9A:A9:72:31:CA:9A")
        XCTAssertGreaterThanOrEqual(payload.count, 6)
        // Message ID 0x4301
        XCTAssertEqual(payload[0], 0x43)
        XCTAssertEqual(payload[1], 0x01)

        let packetData = engine.buildStartCarPlayPacket(ip: "192.168.1.150", port: 7000, deviceId: "9A:A9:72:31:CA:9A")
        let (decodedOpt, consumed) = iAP2Packet.decode(from: packetData)
        XCTAssertNotNil(decodedOpt)
        XCTAssertEqual(consumed, packetData.count)
        if let decoded = decodedOpt {
            XCTAssertEqual(decoded.payload[0], 0x43)
            XCTAssertEqual(decoded.payload[1], 0x01)
        }
    }

    @MainActor
    func testDrivingModeThisiPhoneSequence() async throws {
        // 1. Authenticate Wi-Fi credential handling
        let wifi = WiFiNetworkService.shared
        let testSSID = "HiFi"
        let testPass = "SecretCarPlayPass"
        wifi.savePassword(testPass, for: testSSID)
        XCTAssertEqual(wifi.getPassword(for: testSSID), testPass)

        let config = DrivingModeConfig.shared
        config.wifiSSID = testSSID
        config.wifiPassphrase = testPass

        // 2. Tapping "This iPhone" triggers startReceiver()
        let manager = CarPlayManager.shared
        manager.startReceiver()
        XCTAssertEqual(manager.state, .waitingForPhone)

        // 3. iAP2 Handshake: Simulating incoming RequestStartCarPlay (0x4300) from iOS carplayd
        let engine = iAP2ProtocolEngine()
        var lastSentData: Data?
        engine.onSendData = { data in
            lastSentData = data
        }

        // Build mock 0x4300 request packet
        let reqPayload = Data([0x43, 0x00])
        let reqPacket = iAP2Packet(
            controlByte: iAP2Packet.ControlFlag.ack.rawValue,
            packetSeq: 1,
            ackSeq: 0,
            sessionID: 1,
            payload: reqPayload
        )

        // Handle incoming 0x4300
        engine.handleIncomingBytes(reqPacket.encode())

        // Give the async queue a brief moment to process and emit 0x4301 response
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNotNil(lastSentData, "Engine must respond to 0x4300 with 0x4301")
        if let sent = lastSentData {
            let (decodedOpt, _) = iAP2Packet.decode(from: sent)
            XCTAssertNotNil(decodedOpt)
            if let decoded = decodedOpt {
                XCTAssertGreaterThanOrEqual(decoded.payload.count, 2)
                XCTAssertEqual(decoded.payload[0], 0x43)
                XCTAssertEqual(decoded.payload[1], 0x01)
            }
        }

        // 4. Test Stop & Reset behavior ("works but if i hit stop then start doesnt reset")
        manager.stopReceiver()
        XCTAssertEqual(manager.state, .idle)
        XCTAssertFalse(manager.isStreamingActive)

        // Tap Start again - must cleanly restart without error or port collision
        manager.startReceiver()
        XCTAssertEqual(manager.state, .waitingForPhone)

        manager.stopReceiver()
        XCTAssertEqual(manager.state, .idle)
        wifi.forgetPassword(for: testSSID)
    }

    func testAuthenticDrivingModeAirPlayInfoAndConnectProbe() throws {
        // 1. Test RTSP /info binary plist generation
        let server = RTSPServer(port: 7001)
        try server.start()

        // Test GET /ctrl-int/1/connect probe string construction
        let probe = "GET /ctrl-int/1/connect HTTP/1.1\r\n" +
            "Host: 127.0.0.1:7100\r\n" +
            "User-Agent: AirPlay/377.17.24.6\r\n" +
            "AirPlay-Receiver-Device-ID: 02554E445256\r\n" +
            "Connection: close\r\n\r\n"
        XCTAssertTrue(probe.contains("/ctrl-int/1/connect"))
        XCTAssertTrue(probe.contains("AirPlay-Receiver-Device-ID"))

        server.stop()
    }

    func testBonjourAdvertiserTXTRecordsAndState() {
        let advertiser = AirPlayBonjourAdvertiser(port: 7000)
        advertiser.startAdvertising(name: "DrivingMode-TestUnit", deviceId: "02:55:4E:AA:BB:CC")
        
        // Rapid stop/start cycle reset verification
        advertiser.stopAdvertising()
        advertiser.startAdvertising(name: "DrivingMode-TestUnit2", deviceId: "02:55:4E:AA:BB:DD")
        XCTAssertNotNil(advertiser)
        advertiser.stopAdvertising()
    }

    func testRTPAudioHeaderParsing() {
        // 12-byte standard RTP header: V=2, P=0, X=0, CC=0, M=0, PT=96 (0x80, 0x60), Seq=1001 (0x03, 0xE9), TS=44100, SSRC=0x12345678
        let headerBytes: [UInt8] = [
            0x80, 0x60, 0x03, 0xE9,
            0x00, 0x00, 0xAC, 0x44,
            0x12, 0x34, 0x56, 0x78
        ]
        let pcmPayload = Data(repeating: 0x55, count: 1024)
        let packetData = Data(headerBytes) + pcmPayload

        let parsed = AirPlayAudioReceiver.parseRTPPacket(packetData)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.sequenceNumber, 1001)
        XCTAssertEqual(parsed?.payloadType, 96)
        XCTAssertEqual(parsed?.timestamp, 44100)
        XCTAssertEqual(parsed?.ssrc, 0x12345678)
        XCTAssertEqual(parsed?.payload.count, 1024)
    }

    func testAudioDuckingStateCalculation() {
        let receiver = AirPlayAudioReceiver.shared
        receiver.isPassthroughMode = false

        // Base volume
        receiver.setBaseVolume(0.8)
        XCTAssertEqual(receiver.effectiveMainVolume, 0.8, accuracy: 0.01)

        // Simulate Alt Audio active (Siri/Nav prompt)
        receiver.notifyAltAudioActive(true)
        XCTAssertEqual(receiver.effectiveMainVolume, 0.8 * 0.25, accuracy: 0.01)

        // Simulate Alt Audio finished
        receiver.notifyAltAudioActive(false)
        XCTAssertEqual(receiver.effectiveMainVolume, 0.8, accuracy: 0.01)
    }

    func testRTSPDbToLinearVolumeConversion() {
        XCTAssertEqual(AirPlayAudioReceiver.dbToLinear(0.0), 1.0, accuracy: 0.001)
        XCTAssertEqual(AirPlayAudioReceiver.dbToLinear(-6.0), 0.501, accuracy: 0.01)
        XCTAssertEqual(AirPlayAudioReceiver.dbToLinear(-30.0), 0.031, accuracy: 0.01)
        XCTAssertEqual(AirPlayAudioReceiver.dbToLinear(-144.0), 0.0, accuracy: 0.001)
    }

    func testRTSPMultiStreamSetupResponse() {
        let server = RTSPServer(port: 7000)
        let requestStreams: [[String: Any]] = [
            ["type": 110, "streamConnectionID": 1111],
            ["type": 100, "streamConnectionID": 2222],
            ["type": 101, "streamConnectionID": 3333]
        ]
        let requestPlist: [String: Any] = ["streams": requestStreams]
        let bodyData = try! PropertyListSerialization.data(fromPropertyList: requestPlist, format: .binary, options: 0)

        let responseDict = server.buildStreamSetupResponse(for: bodyData)
        guard let responseStreams = responseDict["streams"] as? [[String: Any]] else {
            XCTFail("Missing streams key in response")
            return
        }

        XCTAssertEqual(responseStreams.count, 3)
        let types = responseStreams.compactMap { $0["type"] as? Int }
        XCTAssertTrue(types.contains(110))
        XCTAssertTrue(types.contains(100))
        XCTAssertTrue(types.contains(101))

        // Verify ports assigned
        let videoStream = responseStreams.first { ($0["type"] as? Int) == 110 }
        let videoPort = videoStream?["dataPort"] as? Int
        XCTAssertEqual(videoPort, 7100)

        let mainAudio = responseStreams.first { ($0["type"] as? Int) == 100 }
        let mainDataPort = mainAudio?["dataPort"] as? Int
        let mainControlPort = mainAudio?["controlPort"] as? Int
        XCTAssertEqual(mainDataPort, 7001)
        XCTAssertEqual(mainControlPort, 7003)

        let altAudio = responseStreams.first { ($0["type"] as? Int) == 101 }
        let altDataPort = altAudio?["dataPort"] as? Int
        let altControlPort = altAudio?["controlPort"] as? Int
        XCTAssertEqual(altDataPort, 7002)
        XCTAssertEqual(altControlPort, 7004)
    }

    func testRTSPVolumeParameterParsing() {
        let paramBody = "volume: -15.500000\r\n"
        let volume = RTSPServer.parseVolumeParameter(paramBody)
        XCTAssertNotNil(volume)
        XCTAssertEqual(Double(volume ?? 0), -15.5, accuracy: 0.01)

        let invalidBody = "status: ok\r\n"
        XCTAssertNil(RTSPServer.parseVolumeParameter(invalidBody))
    }

    @MainActor
    func testAudioRoutingModeConfigPersistence() {
        let config = DrivingModeConfig.shared
        config.audioRoutingMode = .carBluetoothPassthrough
        XCTAssertEqual(config.audioRoutingMode, .carBluetoothPassthrough)
        XCTAssertTrue(AirPlayAudioReceiver.shared.isPassthroughMode)

        config.audioRoutingMode = .airPlayInBand
        XCTAssertEqual(config.audioRoutingMode, .airPlayInBand)
        XCTAssertFalse(AirPlayAudioReceiver.shared.isPassthroughMode)
    }
}
