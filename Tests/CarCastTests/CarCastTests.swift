//
//  CarCastTests.swift
//  CarCastTests
//
//  Unit tests verifying protocol parity, packet framing, and vehicle catalog.
//

import XCTest
import Network
@testable import CarCast

final class CarCastTests: XCTestCase {

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
            carName: "CarCast-TEST",
            macAddress: "02:00:11:22:33:44",
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
        let config = CarCastConfig.shared
        XCTAssertFalse(config.carName.isEmpty)
        XCTAssertTrue(config.carName.hasPrefix("CarCast-"))
        XCTAssertEqual(config.displayPreset, .fitScreen)
        XCTAssertEqual(config.drivingPosition, .leftHandDrive)
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
        var headerData = Data()
        let length: UInt32 = 256
        let opcode: UInt16 = 0x0001 // SPS/PPS
        let reserved: UInt16 = 0

        headerData.append(UInt8((length >> 24) & 0xFF))
        headerData.append(UInt8((length >> 16) & 0xFF))
        headerData.append(UInt8((length >> 8) & 0xFF))
        headerData.append(UInt8(length & 0xFF))

        headerData.append(UInt8((opcode >> 8) & 0xFF))
        headerData.append(UInt8(opcode & 0xFF))

        headerData.append(UInt8((reserved >> 8) & 0xFF))
        headerData.append(UInt8(reserved & 0xFF))

        let parsed = AirPlayScreenHeader.parse(from: headerData)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.payloadLength, 256)
        XCTAssertEqual(parsed?.opcode, .videoConfig)
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
        let testName = "CarCast-UnitTest-\(UUID().uuidString.prefix(6))"
        advertiser.startAdvertising(name: testName, deviceId: "02:00:AA:BB:CC:DD")

        let exp = expectation(description: "Bonjour service discovered over local network")

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_carcast._tcp.", domain: "local.")
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
}
