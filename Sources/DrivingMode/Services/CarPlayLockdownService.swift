//
//  CarPlayLockdownService.swift
//  DrivingMode
//
//  Ground-truth CoreAccessories ACCTransport & iAP2 CarPlay lockdown engine.
//  Executes authentic MFi challenge-response authentication and wireless CarPlay session ignition.
//

import Foundation
import CryptoKit
import Security
import CommonCrypto
import Combine

public final class CarPlayLockdownService: @unchecked Sendable {
    public static let shared = CarPlayLockdownService()

    private let queue = DispatchQueue.main

    // Authentic MFi Certificate (607 bytes DER PKCS#7 signedData)
    private static let mfiCertHex = "3082025b06092a864886f70d010702a082024c308202480201013100300b06092a864886f70d010701a082022e3082022a308201d1a003020102021024acbb48646f8077f7463523085b60d2300a06082a8648ce3d040302308189310b300906035504061302555331133011060355040a130a4170706c6520496e632e31263024060355040b131d4170706c652043657274696669636174696f6e20417574686f72697479313d303b060355040313344170706c65204163636573736f726965732043657274696669636174696f6e20417574686f72697479202d203030303030303032301e170d3138303631333038333235395a170d3439313233313233353935395a306d310b300906035504061302555331133011060355040a130a4170706c6520496e632e311a3018060355040b13114170706c65204163636573736f72696573312d302b060355040314244950415f32344143424234383634364638303737463734363335323330383542363044323059301306072a8648ce3d020106082a8648ce3d03010703420004f498f7c8b4915ab5e62649ef3d67d0697f81f0a2059ec25cf765f5204246eec6fbafc3dbc69aec8c962b5892bed034933dfc9e2c84546037519eb29b5b567129a3363034303206092a864886f7636406240101ff042204200000000000000000000000000000000000000000000000000000000000000002300a06082a8648ce3d040302034700304402206982f4df2f178defc429d12a841a1124b074ef52423faf5898d3905d5bfea9f9022059e0b0f29a71300055abe2d44e3b976f25b4842c95373b001b90e5cfa5b78ec0a1003100"

    // Authentic SECP256R1 Private Key Scalar (32 bytes)
    private static let mfiScalarHex = "2fe02fbb687cb9db321464c5b66c02556fe7f603e13cf304bd7a9fef5c98ba86"

    private let certData: Data
    private let mfiSecKey: SecKey?

    // ACCTransportClient State
    private var clientInstance: NSObject?
    private var connectionUUID: String?
    private var endpointUUID: String?
    private var storedDataOutHandler: Any?
    private var isSessionActive = false
    private var presenceRetryTimer: DispatchSourceTimer?
    private var rtspWatchdog: DispatchWorkItem?
    private var rtspConnectionSeen = false
    public private(set) var currentPhase: String = "idle"
    public var onStateReasonChanged: ((ReceiverState, String) -> Void)?

    // Target parameters for 0x4301
    private var targetRtspPort: UInt16 = 7000
    private var targetIP: String = ""
    private var targetSSID: String = ""
    private var targetPassphrase: String = ""
    private var targetChannel: UInt8 = 36
    private var targetCarName: String = "DrivingMode"
    private var targetDeviceId: String = ""

    // iAP2 Packet Sequencing
    private var txSeq: UInt8 = 0x10
    private var rxSeq: UInt8 = 0x00

    private init() {
        self.certData = Self.hexToData(Self.mfiCertHex)
        let scalarData = Self.hexToData(Self.mfiScalarHex)

        if let p256Key = try? P256.Signing.PrivateKey(rawRepresentation: scalarData) {
            let attributes: [String: Any] = [
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
                kSecAttrKeySizeInBits as String: 256
            ]
            var error: Unmanaged<CFError>?
            self.mfiSecKey = SecKeyCreateWithData(p256Key.x963Representation as CFData, attributes as CFDictionary, &error)
            if self.mfiSecKey != nil {
                NSLog("[CarPlayLockdown] Loaded authentic MFi ECC key pair (SECP256R1)")
            } else {
                NSLog("[CarPlayLockdown] Failed to construct SecKey: %@", String(describing: error?.takeRetainedValue()))
            }
        } else {
            self.mfiSecKey = nil
            NSLog("[CarPlayLockdown] Failed to construct P256 PrivateKey")
        }
    }

    public func updateRtspPort(_ port: UInt16) {
        queue.async { [weak self] in
            guard let self = self, port != 0 else { return }
            self.targetRtspPort = port
            NSLog("[CarPlayLockdown] Updated targetRtspPort=%d", port)
        }
    }

    /// Called by RTSPServer when any TCP client connects; cancels the post-0x4301 watchdog.
    public func noteRtspConnection() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.rtspConnectionSeen = true
            if self.rtspWatchdog != nil {
                self.rtspWatchdog?.cancel()
                self.rtspWatchdog = nil
                NSLog("[CarPlayLockdown] RTSP connection received after 0x4301 — watchdog cleared")
            }
        }
    }

    /// After 0x4301 is ACKed, iOS CarPlay should open TCP to targetIP:targetRtspPort within a few seconds.
    /// If it doesn't, report exactly why we are stuck instead of sitting in "Connecting…" silently.
    private func armRtspWatchdog(seconds: Double = 10) {
        rtspWatchdog?.cancel()
        rtspConnectionSeen = false
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, self.isSessionActive, !self.rtspConnectionSeen else { return }
            let ifaces = WiFiNetworkService.shared.ipv4InterfaceSummary
            let ipIsLAN = WiFiNetworkService.shared.ipv4Interfaces.contains { $0.address == self.targetIP && $0.name.hasPrefix("en") }
            let hint = RTSPServer.lastBindError.map { "RTSP listener is NOT running (\($0)) — quit any other receiver app (e.g. CarCast) holding the port" } ?? (ipIsLAN
                ? "accessoryd accepted 0x4301 but CarPlay never connected (check Settings > General > CarPlay for a pairing prompt, and that Wi-Fi '\(self.targetSSID)' passphrase is set)"
                : "targetIP \(self.targetIP) is NOT a Wi-Fi (en*) address — CarPlay cannot reach it; connect to Wi-Fi or disable VPN")
            self.reportPhase(
                "carplay_rtsp_timeout",
                state: .waitingForPhone,
                reason: "No RTSP connection to \(self.targetIP):\(self.targetRtspPort) \(Int(seconds))s after 0x4301. \(hint). Interfaces: \(ifaces)"
            )
        }
        rtspWatchdog = item
        queue.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func reportPhase(_ phase: String, state: ReceiverState = .waitingForPhone, reason: String) {
        self.currentPhase = phase
        NSLog("[DrivingMode][LockdownPhase] phase=%@ | state=%@ | reason=%@", phase, state.rawValue, reason)
        let deliver = { @MainActor [weak self] in
            guard let self = self, self.isSessionActive else { return }
            ProtocolLogger.shared.log(
                category: .iap2,
                title: "Lockdown Phase: \(phase)",
                detail: reason
            )
            self.onStateReasonChanged?(state, reason)
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                deliver()
            }
        } else {
            Task { @MainActor in
                deliver()
            }
        }
    }

    public func startSession(
        rtspPort: UInt16,
        ip: String,
        ssid: String,
        passphrase: String = "",
        channel: UInt8 = 36,
        carName: String = "DrivingMode",
        deviceId: String = ""
    ) {
        let block = { [weak self] in
            guard let self = self else { return }
            self.stopSessionInternal()

            self.targetRtspPort = rtspPort != 0 ? rtspPort : 7000
            self.targetIP = ip.isEmpty ? (WiFiNetworkService.shared.currentIPAddress ?? "192.168.86.46") : ip
            self.targetSSID = ssid.isEmpty ? "HiFi" : ssid
            self.targetPassphrase = passphrase
            self.targetChannel = channel
            self.targetCarName = carName.isEmpty ? "DrivingMode" : carName
            let resolvedDeviceId = !deviceId.isEmpty ? deviceId : (UserDefaults.standard.string(forKey: "drivingmode.device.id") ?? "02:55:4E:44:52:56")
            self.targetDeviceId = resolvedDeviceId
            self.txSeq = 0x10
            self.rxSeq = 0x00

            self.setupACCTransport()
        }
        if Thread.isMainThread {
            block()
        } else {
            queue.async(execute: block)
        }
    }

    public func stopSession() {
        if Thread.isMainThread {
            stopSessionInternal()
        } else {
            queue.async { [weak self] in
                self?.stopSessionInternal()
            }
        }
    }

    private func stopSessionInternal() {
        presenceRetryTimer?.cancel()
        presenceRetryTimer = nil
        rtspWatchdog?.cancel()
        rtspWatchdog = nil

        if let client = clientInstance, let ep = endpointUUID {
            // Send Link RST packet on link control session 0x00 (header checksum over bytes 0..<8 = 0x8E)
            let rstPacket = Data([0xFF, 0x5A, 0x00, 0x09, 0x10, 0x00, 0x00, 0x00, 0x8E])
            sendToAccessoryd(data: rstPacket, endpointUUID: ep, client: client)

            // Destroy connection
            let selDestroy = NSSelectorFromString("destroyConnectionWithUUID:")
            if client.responds(to: selDestroy) {
                _ = client.perform(selDestroy, with: connectionUUID as NSString?)
            }
        }

        connectionUUID = nil
        endpointUUID = nil
        clientInstance = nil
        storedDataOutHandler = nil
        isSessionActive = false
        currentPhase = "stopped"
        UserDefaults.standard.removeObject(forKey: "drivingmode.lastConnectionUUID")
        NSLog("[CarPlayLockdown] ACCTransport session stopped")
    }

    // MARK: - CoreAccessories Setup

    private func setupACCTransport() {
        dlopen("/System/Library/PrivateFrameworks/CoreAccessories.framework/CoreAccessories", RTLD_NOW)
        guard let clientClass = NSClassFromString("ACCTransportClient") as? NSObject.Type else {
            NSLog("[CarPlayLockdown] CoreAccessories ACCTransportClient class not found")
            reportPhase("acc_unavailable", state: .waitingForPhone, reason: "ACCTransportClient unavailable on this runtime; waiting for external iPhone via BLE/RTSP")
            return
        }

        let selShared = NSSelectorFromString("sharedClient")
        guard clientClass.responds(to: selShared),
              let client = clientClass.perform(selShared)?.takeUnretainedValue() as? NSObject else {
            NSLog("[CarPlayLockdown] ACCTransportClient sharedClient unavailable")
            reportPhase("acc_shared_unavailable", state: .waitingForPhone, reason: "ACCTransportClient.sharedClient returned nil")
            return
        }
        self.clientInstance = client

        let targetMac = targetDeviceId

        // Clean up any stale ACCTransport connection from previous launches
        let selDestroy = NSSelectorFromString("destroyConnectionWithUUID:")
        if let staleConn = UserDefaults.standard.string(forKey: "drivingmode.lastConnectionUUID"), client.responds(to: selDestroy) {
            NSLog("[CarPlayLockdown] Tearing down stale ACCTransport connection from prior launch: %@", staleConn)
            _ = client.perform(selDestroy, with: staleConn as NSString)
            UserDefaults.standard.removeObject(forKey: "drivingmode.lastConnectionUUID")
        }

        // 1. createConnectionWithType:andIdentifier:
        typealias CreateConnFunc = @convention(c) (AnyObject, Selector, Int32, NSString) -> NSString?
        let selCreateConn = NSSelectorFromString("createConnectionWithType:andIdentifier:")
        guard let connMethod = class_getInstanceMethod(clientClass, selCreateConn) else {
            NSLog("[CarPlayLockdown] createConnectionWithType method not found")
            reportPhase("acc_method_missing", state: .waitingForPhone, reason: "ACCTransportClient.createConnectionWithType missing")
            return
        }
        let connImp = method_getImplementation(connMethod)
        let connFn = unsafeBitCast(connImp, to: CreateConnFunc.self)
        guard let connUUID = connFn(client, selCreateConn, 2, targetMac as NSString) else {
            NSLog("[CarPlayLockdown] createConnectionWithType failed")
            reportPhase("acc_conn_failed", state: .waitingForPhone, reason: "ACCTransportClient.createConnectionWithType returned nil (check com.apple.private.accessories.showallconnections entitlement)")
            return
        }
        self.connectionUUID = connUUID as String
        UserDefaults.standard.set(connUUID as String, forKey: "drivingmode.lastConnectionUUID")

        // 2. setEndpointEventHandlerQueue:
        let selQueue = NSSelectorFromString("setEndpointEventHandlerQueue:")
        if client.responds(to: selQueue) {
            _ = client.perform(selQueue, with: self.queue)
        }

        // 3. createEndpointWithTransportType:andProtocol:andIdentifier:andDataOutHandler:forConnectionWithUUID:publishConnection:
        // IMPORTANT (accessoryd acc_endpoint_processIncomingData @ 0x10011822c):
        // Passing andProtocol: 0 (kACCEndpoint_Protocol_None) causes accessoryd to run
        // acc_protocolParser_detectProtocol on our first FF 55 02 00 EE 10 packet, transition
        // the endpoint to protocol=4 (kACCEndpoint_Protocol_iAP2), and echo FF 55 02 00 EE 10 back!
        typealias DataOutBlock = @convention(block) (AnyObject?, AnyObject?, AnyObject?) -> Void
        typealias CreateEpFunc = @convention(c) (AnyObject, Selector, Int32, Int32, NSString, DataOutBlock, NSString, Bool) -> NSString?
        let selCreateEp = NSSelectorFromString("createEndpointWithTransportType:andProtocol:andIdentifier:andDataOutHandler:forConnectionWithUUID:publishConnection:")
        guard let epMethod = class_getInstanceMethod(clientClass, selCreateEp) else {
            NSLog("[CarPlayLockdown] createEndpointWithTransportType method not found")
            reportPhase("acc_ep_method_missing", state: .waitingForPhone, reason: "ACCTransportClient.createEndpointWithTransportType missing")
            return
        }

        let dataOutHandler: DataOutBlock = { [weak self] conn, ep, dataObj in
            guard let self = self else { return }
            var incomingData: Data? = nil
            if let d = dataObj as? Data {
                incomingData = d
            } else if let d = dataObj as? NSData {
                incomingData = d as Data
            } else if let d = conn as? Data {
                incomingData = d
            } else if let d = ep as? Data {
                incomingData = d
            }

            if let d = incomingData {
                self.handleIncomingAccessoryData(d)
            } else {
                NSLog("[CarPlayLockdown] dataOutHandler: could not extract Data from args: a1=%@ a2=%@ a3=%@", String(describing: conn), String(describing: ep), String(describing: dataObj))
            }
        }
        self.storedDataOutHandler = dataOutHandler

        let epImp = method_getImplementation(epMethod)
        let epFn = unsafeBitCast(epImp, to: CreateEpFunc.self)
        guard let epUUID = epFn(client, selCreateEp, 2, 0, targetMac as NSString, dataOutHandler, connUUID, true) else {
            NSLog("[CarPlayLockdown] createEndpointWithTransportType failed")
            reportPhase("acc_ep_failed", state: .waitingForPhone, reason: "ACCTransportClient.createEndpointWithTransportType returned nil")
            return
        }
        self.endpointUUID = epUUID as String

        self.isSessionActive = true
        NSLog("[CarPlayLockdown] Created ACCTransport connection=%@ (BT MAC=%@) endpoint=%@ (connectionType=2, transportType=2, initialProtocol=0)", connUUID, targetMac, epUUID)
        reportPhase(
            "presence_detect_tx",
            state: .waitingForPhone,
            reason: "ACCTransport endpoint \(epUUID) created (protocol=0 auto-detect); sending iAP2 Presence Detect (FF 55 02 00 EE 10) to accessoryd"
        )

        // 4. Send iAP2 Presence Detect with retry
        sendPresenceDetectWithRetry(client: client, endpointUUID: epUUID as String)
    }

    private func sendPresenceDetectWithRetry(client: NSObject, endpointUUID: String) {
        presenceRetryTimer?.cancel()
        let presenceDetect = Data([0xFF, 0x55, 0x02, 0x00, 0xEE, 0x10])
        var attempts = 0

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(300))
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isSessionActive else {
                timer.cancel()
                return
            }
            if attempts >= 6 {
                NSLog("[CarPlayLockdown] Presence Detect timed out after 6 attempts")
                self.reportPhase(
                    "presence_detect_timeout",
                    state: .waitingForPhone,
                    reason: "Timed out waiting for accessoryd to echo iAP2 Presence Detect (FF 55 02 00 EE 10) after 6 attempts"
                )
                timer.cancel()
                self.presenceRetryTimer = nil
                return
            }
            attempts += 1
            NSLog("[CarPlayLockdown] TX iAP2 Presence Detect (FF 55 02 00 EE 10) [attempt %d/6]", attempts)
            self.sendToAccessoryd(data: presenceDetect, endpointUUID: endpointUUID, client: client)
        }
        self.presenceRetryTimer = timer
        timer.resume()
    }

    private func sendToAccessoryd(data: Data, endpointUUID: String, client: NSObject) {
        typealias SendIncomingFunc = @convention(c) (AnyObject, Selector, NSData, NSString) -> Bool
        let selIncoming = NSSelectorFromString("processIncomingData:forEndpointWithUUID:")
        guard let inMethod = class_getInstanceMethod(type(of: client), selIncoming) else {
            NSLog("[CarPlayLockdown] sendToAccessoryd: processIncomingData method NOT FOUND!")
            return
        }
        let inImp = method_getImplementation(inMethod)
        let inFn = unsafeBitCast(inImp, to: SendIncomingFunc.self)
        let ok = inFn(client, selIncoming, data as NSData, endpointUUID as NSString)
        NSLog("[CarPlayLockdown] processIncomingData returned: %d (sent %d bytes to endpoint %@)", ok ? 1 : 0, data.count, endpointUUID)
    }

    // MARK: - Incoming Data Router

    private func handleIncomingAccessoryData(_ data: Data) {
        guard let client = clientInstance, let ep = endpointUUID else { return }
        let hexDump = data.prefix(64).map { String(format: "%02X", $0) }.joined(separator: " ")
        NSLog("[CarPlayLockdown] RX raw from accessoryd (%d bytes): %@", data.count, hexDump)

        // Check for Presence Detect Echo: FF 55 02 00 EE 10
        if data.contains(Data([0xFF, 0x55, 0x02, 0x00, 0xEE, 0x10])) {
            presenceRetryTimer?.cancel()
            presenceRetryTimer = nil
            NSLog("[CarPlayLockdown] RX iAP2 Presence Detect Echo (FF 55 02 00 EE 10)")
            reportPhase(
                "link_syn_tx",
                state: .waitingForPhone,
                reason: "Received iAP2 Presence Detect echo from accessoryd; negotiating 23-byte iAP2 Link SYN (Control Session ID=1)"
            )

            // Wait 10ms then TX authentic 23-byte iAP2 Link SYN (_iAP2PacketParseSYNData @ 0x100012858 requires payloadLen >= 10)
            queue.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                guard let self = self, self.isSessionActive, self.endpointUUID == ep else { return }
                let synPacket = self.buildLinkSynPacket(seq: self.txSeq)
                NSLog("[CarPlayLockdown] TX iAP2 Link SYN (seq=0x%02X, %d bytes)", self.txSeq, synPacket.count)
                self.sendToAccessoryd(data: synPacket, endpointUUID: ep, client: client)
            }
            return
        }

        // Parse iAP2 packets starting with FF 5A
        var offset = 0
        while offset + 9 <= data.count {
            guard data[offset] == 0xFF && data[offset + 1] == 0x5A else {
                offset += 1
                continue
            }

            let length = Int((UInt16(data[offset + 2]) << 8) | UInt16(data[offset + 3]))
            guard length >= 9, offset + length <= data.count else { break }

            let slice = data.subdata(in: offset..<(offset + length))
            processiAP2Frame(slice, client: client, ep: ep)
            offset += length
        }
    }

    private func processiAP2Frame(_ frame: Data, client: NSObject, ep: String) {
        guard frame.count >= 9 else { return }
        let control = frame[4]
        let packetSeq = frame[5]
        let ackSeq = frame[6]
        let sessionID = frame[7]
        self.rxSeq = packetSeq

        // Link SYN+ACK check (control == 0xC0)
        if (control & 0xC0) == 0xC0 {
            NSLog("[CarPlayLockdown] RX iAP2 Link SYN+ACK (seq=0x%02X, ack=0x%02X, sessionID=%d, len=%d)", packetSeq, ackSeq, sessionID, frame.count)
            reportPhase(
                "mfi_auth_wait",
                state: .waitingForPhone,
                reason: "iAP2 Link SYN+ACK received from accessoryd; sending Link ACK and waiting for 0xAA00 MFi Certificate Request"
            )
            let ackPacket = buildLinkAckPacket(seq: self.txSeq, ack: self.rxSeq)
            sendToAccessoryd(data: ackPacket, endpointUUID: ep, client: client)
            return
        }

        // Control session payload (length > 10)
        guard frame.count > 10 else { return }
        let payload = frame.subdata(in: 9..<(frame.count - 1)) // Strip header (9) and checksum (1)
        guard payload.count >= 4 else { return }

        // iAP2 Control Session messages start with 0x40 0x40 [msgLen:2] [msgId:2] or [msgId:2]
        let msgId: UInt16
        let paramStartOffset: Int
        if payload[0] == 0x40 && payload[1] == 0x40 && payload.count >= 6 {
            msgId = (UInt16(payload[4]) << 8) | UInt16(payload[5])
            paramStartOffset = 6
        } else {
            msgId = (UInt16(payload[0]) << 8) | UInt16(payload[1])
            paramStartOffset = 2
        }
        let paramBytes = max(0, payload.count - paramStartOffset)

        switch msgId {
        case 0xAA00:
            // RequestAuthenticationCertificate
            NSLog("[CarPlayLockdown] RX iAP2 Control Message: 0xAA00 (%d param bytes)", paramBytes)
            reportPhase(
                "mfi_cert_tx",
                state: .waitingForPhone,
                reason: "accessoryd requested MFi Certificate (0xAA00); sending 607-byte DER certificate (0xAA01)"
            )
            handleRequestCertificate(client: client, ep: ep, use4040Prefix: paramStartOffset == 6)

        case 0xAA02:
            // RequestAuthenticationChallengeResponse
            NSLog("[CarPlayLockdown] RX iAP2 Control Message: 0xAA02 (%d param bytes)", paramBytes)
            reportPhase(
                "mfi_challenge_tx",
                state: .waitingForPhone,
                reason: "accessoryd sent MFi 32-byte challenge (0xAA02); signing with SECP256R1 key and sending 0xAA03"
            )
            handleChallengeResponse(payload: payload, paramStartOffset: paramStartOffset, client: client, ep: ep, use4040Prefix: paramStartOffset == 6)

        case 0xAA04:
            // AuthenticationFailed
            NSLog("[CarPlayLockdown] RX 0xAA04 MFi Authentication FAILED!")
            reportPhase(
                "mfi_auth_failed",
                state: .error,
                reason: "accessoryd rejected MFi authentication (0xAA04 AuthenticationFailed)"
            )

        case 0xAA05:
            // AuthenticationSucceeded
            NSLog("[CarPlayLockdown] RX iAP2 Control Message: 0xAA05 (0 param bytes)")
            NSLog("[CarPlayLockdown] RX 0xAA05 MFi Authentication Succeeded!")
            let ackPacket = buildLinkAckPacket(seq: self.txSeq, ack: self.rxSeq)
            sendToAccessoryd(data: ackPacket, endpointUUID: ep, client: client)
            reportPhase(
                "ident_wait",
                state: .waitingForPhone,
                reason: "MFi Authentication Succeeded (0xAA05); waiting for accessoryd 0x1D00 RequestIdentification"
            )

        case 0x1D00:
            // RequestIdentification
            NSLog("[CarPlayLockdown] RX iAP2 Control Message: 0x1D00 (%d param bytes)", paramBytes)
            reportPhase(
                "ident_tx",
                state: .waitingForPhone,
                reason: "accessoryd requested Identification (0x1D00); sending 0x1D01 IdentificationInformation (USB+BT+WirelessCarPlay)"
            )
            handleRequestIdentification(client: client, ep: ep, use4040Prefix: paramStartOffset == 6)

        case 0x1D02:
            // IdentificationAccepted
            NSLog("[CarPlayLockdown] RX iAP2 Control Message: 0x1D02 (0 param bytes)")
            NSLog("[CarPlayLockdown] RX 0x1D02 IdentificationAccepted — waiting for 0x4300 CarPlayAvailability (tap Allow on CarPlay pairing alert if shown)...")
            let ackPacket = buildLinkAckPacket(seq: self.txSeq, ack: self.rxSeq)
            sendToAccessoryd(data: ackPacket, endpointUUID: ep, client: client)
            reportPhase(
                "carplay_availability_wait",
                state: .waitingForPhone,
                reason: "IdentificationAccepted (0x1D02) by accessoryd; waiting for 0x4300 CarPlayAvailability (accept CarPlay prompt if shown)"
            )

        case 0x1D03:
            // IdentificationRejected
            let rejectedHex = payload.subdata(in: paramStartOffset..<payload.count).map { String(format: "%02X", $0) }.joined(separator: " ")
            NSLog("[CarPlayLockdown] RX 0x1D03 IdentificationRejected! Rejected params hex: [%@]", rejectedHex)
            let ackPacket = buildLinkAckPacket(seq: self.txSeq, ack: self.rxSeq)
            sendToAccessoryd(data: ackPacket, endpointUUID: ep, client: client)
            reportPhase(
                "ident_rejected",
                state: .error,
                reason: "accessoryd rejected IdentificationInformation (0x1D03): [\(rejectedHex)]"
            )

        case 0x4300:
            // CarPlayAvailability
            let hexStr = payload.subdata(in: paramStartOffset..<payload.count).map { String(format: "%02X", $0) }.joined()
            NSLog("[CarPlayLockdown] RX iAP2 Control Message: 0x4300 (%d param bytes)", paramBytes)
            NSLog("[CarPlayLockdown] RX 0x4300 CarPlayAvailability [%@] -> Sending 0x4301 CarPlayStartSession", hexStr)
            reportPhase(
                "carplay_start_session_tx",
                state: .connecting,
                reason: "Received 0x4300 CarPlayAvailability; sending 0x4301 CarPlayStartSession -> \(targetIP):\(targetRtspPort) (SSID: \(targetSSID))"
            )
            handleCarPlayAvailability(client: client, ep: ep, use4040Prefix: paramStartOffset == 6)

        default:
            let ackPacket = buildLinkAckPacket(seq: self.txSeq, ack: self.rxSeq)
            sendToAccessoryd(data: ackPacket, endpointUUID: ep, client: client)
            NSLog("[CarPlayLockdown] RX iAP2 Control Message: 0x%04X (%d param bytes)", msgId, paramBytes)
        }
    }

    // MARK: - Message Responders

    private func handleRequestCertificate(client: NSObject, ep: String, use4040Prefix: Bool) {
        var msg = Data()
        msg.append(0xAA)
        msg.append(0x01)

        // Param 0x0000: Certificate (607 bytes)
        appendParam(to: &msg, paramId: 0x0000, data: certData)

        let packet = buildControlPacket(messageBody: msg, use4040Prefix: use4040Prefix)
        NSLog("[CarPlayLockdown] TX 0xAA01 AuthenticationCertificate (%d cert bytes, %d packet bytes)", certData.count, packet.count)
        sendToAccessoryd(data: packet, endpointUUID: ep, client: client)
    }

    private func handleChallengeResponse(payload: Data, paramStartOffset: Int, client: NSObject, ep: String, use4040Prefix: Bool) {
        // Extract challenge nonce TLV from payload starting at paramStartOffset
        // TLV: [paramLen: 2 bytes] [paramId: 2 bytes (0x0000)] [challenge: 32 bytes (or 20 bytes)]
        guard payload.count >= paramStartOffset + 4, let secKey = mfiSecKey else {
            NSLog("[CarPlayLockdown] Invalid challenge payload size: %d", payload.count)
            return
        }

        let tlvLen = Int((UInt16(payload[paramStartOffset]) << 8) | UInt16(payload[paramStartOffset + 1]))
        let challengeLen = max(0, min(tlvLen - 4, payload.count - (paramStartOffset + 4)))
        guard challengeLen >= 20 else {
            NSLog("[CarPlayLockdown] Challenge length too short: %d", challengeLen)
            return
        }
        let challenge = payload.subdata(in: (paramStartOffset + 4)..<(paramStartOffset + 4 + challengeLen))

        // Verified against MFAAuthentication.framework MFAAVerifyNonceSignature:
        // The 32-byte challenge in 0xAA02 is already the 32-byte digest; sign directly with .ecdsaSignatureDigestRFC4754 (64-byte raw r||s)
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(secKey, .ecdsaSignatureDigestRFC4754, challenge as CFData, &error) as Data?,
              signature.count == 64 else {
            NSLog("[CarPlayLockdown] Failed to sign challenge: %@", String(describing: error?.takeRetainedValue()))
            return
        }

        var msg = Data()
        msg.append(0xAA)
        msg.append(0x03)

        // Param 0x0000: Signature (64 bytes raw r||s)
        appendParam(to: &msg, paramId: 0x0000, data: signature)

        let packet = buildControlPacket(messageBody: msg, use4040Prefix: use4040Prefix)
        NSLog("[CarPlayLockdown] TX 0xAA03 AuthenticationResponse (ECDSA sig=64 bytes, challenge=%d bytes)", challengeLen)
        sendToAccessoryd(data: packet, endpointUUID: ep, client: client)
    }

    private func handleRequestIdentification(client: NSObject, ep: String, use4040Prefix: Bool) {
        var msg = Data()
        msg.append(0x1D)
        msg.append(0x01)

        // Required Identification parameters (verified in accessoryd _iap2_features_registerIdentificationParamHandlers @ 0x10020a6a8):
        // All strings MUST be null-terminated (_iAP2MsgGetDataAsString @ 0x1000c3368 checks lastByte == 0x00).
        appendNullTerminatedParam(to: &msg, paramId: 0x0000, string: targetCarName)         // Name (req)
        appendNullTerminatedParam(to: &msg, paramId: 0x0001, string: "DrivingMode")         // ModelIdentifier (req)
        appendNullTerminatedParam(to: &msg, paramId: 0x0002, string: "Unordinary Labs")     // Manufacturer (req)
        appendNullTerminatedParam(to: &msg, paramId: 0x0003, string: "DM-202610220001")     // SerialNumber (req)
        appendNullTerminatedParam(to: &msg, paramId: 0x0004, string: "1.0.0")               // FirmwareVersion (req)
        appendNullTerminatedParam(to: &msg, paramId: 0x0005, string: "1.0.0")               // HardwareVersion (req)

        // 0x0006: MessagesSentByAccessory (req) -> 0x4301 (CarPlayStartSession)
        appendParam(to: &msg, paramId: 0x0006, data: Data([0x43, 0x01]))
        // 0x0007: MessagesReceivedFromDevice (req) -> 0x4300 (CarPlayAvailability)
        appendParam(to: &msg, paramId: 0x0007, data: Data([0x43, 0x00]))
        // 0x0008: PowerProvidingCapability (req, 1-byte enum: 2 = Self-powered)
        appendParam(to: &msg, paramId: 0x0008, data: Data([0x02]))
        // 0x0009: MaximumCurrentDrawnFromDevice (req, 2-byte UInt16 BE: 0 mA)
        appendParam(to: &msg, paramId: 0x0009, data: Data([0x00, 0x00]))
        // 0x000C: CurrentLanguage (req, null-terminated string)
        appendNullTerminatedParam(to: &msg, paramId: 0x000C, string: "en")
        // 0x000D: SupportedLanguage (req, null-terminated string)
        appendNullTerminatedParam(to: &msg, paramId: 0x000D, string: "en")

        // 0x0010: USBHostTransportComponent (_cbIdentificationInfoUSBHostTransportComponentParams @ 0x1000e3350)
        var usbTransport = Data()
        appendParam(to: &usbTransport, paramId: 0x0000, data: Data([0x00, 0x01]))           // TransportComponentIdentifier = 1
        appendNullTerminatedParam(to: &usbTransport, paramId: 0x0001, string: "USBHost")    // TransportComponentName
        appendVoidParam(to: &usbTransport, paramId: 0x0002)                                 // TransportSupportsiAP2Connection
        appendVoidParam(to: &usbTransport, paramId: 0x0004)                                 // TransportSupportsCarPlay
        appendParam(to: &msg, paramId: 0x0010, data: usbTransport)

        // 0x0011: BluetoothTransportComponent (_cbIdentificationInfoBluetoothTransportComponentParams @ 0x1000e3564)
        // Required when endpoint->transportType == 4 (Bluetooth) in _iap2_identification_checkIdentificationInfo @ 0x10017ef94
        var btTransport = Data()
        appendParam(to: &btTransport, paramId: 0x0000, data: Data([0x00, 0x02]))            // TransportComponentIdentifier = 2
        appendNullTerminatedParam(to: &btTransport, paramId: 0x0001, string: "Bluetooth")   // TransportComponentName
        appendVoidParam(to: &btTransport, paramId: 0x0002)                                  // TransportSupportsiAP2Connection
        appendParam(to: &btTransport, paramId: 0x0003, data: macAddressBytes(from: targetDeviceId)) // 6-byte BT MAC
        appendParam(to: &msg, paramId: 0x0011, data: btTransport)

        // 0x0018: WirelessCarPlayTransportComponent (_cbIdentificationInfoWirelessCarPlayTransportComponentParams @ 0x1000e3768)
        var wifiTransport = Data()
        appendParam(to: &wifiTransport, paramId: 0x0000, data: Data([0x00, 0x03]))          // TransportComponentIdentifier = 3
        appendNullTerminatedParam(to: &wifiTransport, paramId: 0x0001, string: "WirelessCarPlay")
        appendVoidParam(to: &wifiTransport, paramId: 0x0002)                                // TransportSupportsiAP2Connection
        appendVoidParam(to: &wifiTransport, paramId: 0x0004)                                // TransportSupportsCarPlay
        appendParam(to: &msg, paramId: 0x0018, data: wifiTransport)

        let packet = buildControlPacket(messageBody: msg, use4040Prefix: use4040Prefix)
        NSLog("[CarPlayLockdown] TX 0x1D01 IdentificationInformation (%d msg bytes, %d packet bytes, USB+BT+WirelessCarPlay)", msg.count, packet.count)
        sendToAccessoryd(data: packet, endpointUUID: ep, client: client)
    }

    private func handleCarPlayAvailability(client: NSObject, ep: String, use4040Prefix: Bool) {
        var msg = Data()
        msg.append(0x43)
        msg.append(0x01)

        // Verified against accessoryd iap2_CarPlayStartSession @ 0x100147910:
        // Param 0x0000: USB Group (sub-param 0x0000 = usbIP null-terminated string)
        var usbGroup = Data()
        appendNullTerminatedParam(to: &usbGroup, paramId: 0x0000, string: targetIP)
        appendParam(to: &msg, paramId: 0x0000, data: usbGroup)

        // Param 0x0001: Wireless Group
        //   sub-param 0x0000 = ssid (null-terminated string)
        //   sub-param 0x0001 = pass (null-terminated string, if non-empty)
        //   sub-param 0x0002 = channel (1-byte UInt8)
        //   sub-param 0x0003 = wifiIP (null-terminated string)
        //   sub-param 0x0004 = securityType (1-byte UInt8: 0=none, 2=WPA2)
        var wirelessGroup = Data()
        appendNullTerminatedParam(to: &wirelessGroup, paramId: 0x0000, string: targetSSID)
        if !targetPassphrase.isEmpty {
            appendNullTerminatedParam(to: &wirelessGroup, paramId: 0x0001, string: targetPassphrase)
        }
        appendParam(to: &wirelessGroup, paramId: 0x0002, data: Data([targetChannel]))
        appendNullTerminatedParam(to: &wirelessGroup, paramId: 0x0003, string: targetIP)
        let secType: UInt8 = targetPassphrase.isEmpty ? 0x00 : 0x02
        appendParam(to: &wirelessGroup, paramId: 0x0004, data: Data([secType]))
        appendParam(to: &msg, paramId: 0x0001, data: wirelessGroup)

        // Param 0x0002: Port (4-byte UInt32 big-endian)
        var portBe = UInt32(targetRtspPort).bigEndian
        let portData = Data(bytes: &portBe, count: 4)
        appendParam(to: &msg, paramId: 0x0002, data: portData)

        // Param 0x0003: Device ID (null-terminated string, e.g. "02:55:4E:44:52:56")
        appendNullTerminatedParam(to: &msg, paramId: 0x0003, string: targetDeviceId)

        // Param 0x0005: Source Version (null-terminated string, "509.11")
        appendNullTerminatedParam(to: &msg, paramId: 0x0005, string: "509.11")

        let packet = buildControlPacket(messageBody: msg, use4040Prefix: use4040Prefix)
        NSLog("[CarPlayLockdown] TX 0x4301 CarPlayStartSession -> %@:%d (deviceID=%@, srcVer=509.11, wifiSSID=%@, channel=%d)", targetIP, targetRtspPort, targetDeviceId, targetSSID, targetChannel)
        sendToAccessoryd(data: packet, endpointUUID: ep, client: client)
        armRtspWatchdog()
    }

    // MARK: - Packet Encoding

    private func buildLinkSynPacket(seq: UInt8) -> Data {
        // 13-byte SYN payload required by _iAP2PacketParseSYNData @ 0x100012858:
        // version=1, maxOutstanding=5, maxPacketLen=2048 (0x0800), retransmitTimeout=2000ms (0x07D0),
        // cumAckTimeout=100ms (0x0064), maxRetransmit=3, maxCumAck=3,
        // Session 1: id=1, type=0 (Control), version=1
        let synPayload = Data([
            0x01,
            0x05,
            0x08, 0x00,
            0x07, 0xD0,
            0x00, 0x64,
            0x03,
            0x03,
            0x01, 0x00, 0x01
        ])
        let totalLength = UInt16(9 + synPayload.count + 1) // 23 (0x0017)
        var data = Data([
            0xFF, 0x5A,
            UInt8((totalLength >> 8) & 0xFF),
            UInt8(totalLength & 0xFF),
            0x80, // SYN
            seq,
            0x00,
            0x00  // Link layer session = 0
        ])
        // Header checksum over all 8 header bytes data[0..<8] (verified in accessoryd _iAP2PacketParseBuffer @ 0x100011490)
        var headerSum: UInt32 = 0
        for b in data[0..<8] { headerSum += UInt32(b) }
        data.append(UInt8((~headerSum + 1) & 0xFF))
        data.append(synPayload)
        var payloadSum: UInt32 = 0
        for b in synPayload { payloadSum += UInt32(b) }
        data.append(UInt8((~payloadSum + 1) & 0xFF))
        return data
    }

    private func buildLinkAckPacket(seq: UInt8, ack: UInt8) -> Data {
        var data = Data([
            0xFF, 0x5A,
            0x00, 0x09,
            0x40, // ACK
            seq,
            ack,
            0x00  // Link layer session = 0
        ])
        var headerSum: UInt32 = 0
        for b in data[0..<8] { headerSum += UInt32(b) }
        data.append(UInt8((~headerSum + 1) & 0xFF))
        return data
    }

    private func buildControlPacket(messageBody: Data, use4040Prefix: Bool) -> Data {
        var payload = Data()
        if use4040Prefix {
            payload.append(contentsOf: [0x40, 0x40])
            let msgLen = UInt16(4 + messageBody.count)
            payload.append(UInt8((msgLen >> 8) & 0xFF))
            payload.append(UInt8(msgLen & 0xFF))
        }
        payload.append(messageBody)
        return buildPacket(payload: payload)
    }

    private func buildPacket(payload: Data) -> Data {
        txSeq = (txSeq &+ 1)
        var data = Data()
        data.append(contentsOf: [0xFF, 0x5A])

        let totalLength: UInt16 = UInt16(9 + payload.count + 1)
        data.append(UInt8((totalLength >> 8) & 0xFF))
        data.append(UInt8(totalLength & 0xFF))

        data.append(0x40) // ACK
        data.append(txSeq)
        data.append(rxSeq)
        data.append(0x01) // Session ID 1

        // Header checksum: 2's complement of header bytes 0..<8 (including 0xFF, 0x5A)
        var headerSum: UInt32 = 0
        for b in data[0..<8] {
            headerSum += UInt32(b)
        }
        data.append(UInt8((~headerSum + 1) & 0xFF))

        // Payload
        data.append(payload)

        // Payload checksum: 2's complement of payload bytes
        var payloadSum: UInt32 = 0
        for b in payload {
            payloadSum += UInt32(b)
        }
        data.append(UInt8((~payloadSum + 1) & 0xFF))

        return data
    }

    private func appendVoidParam(to data: inout Data, paramId: UInt16) {
        data.append(0x00)
        data.append(0x04)
        data.append(UInt8((paramId >> 8) & 0xFF))
        data.append(UInt8(paramId & 0xFF))
    }

    private func macAddressBytes(from macString: String) -> Data {
        let parts = macString.split(separator: ":")
        if parts.count == 6 {
            var bytes = Data()
            for part in parts {
                if let b = UInt8(part, radix: 16) {
                    bytes.append(b)
                }
            }
            if bytes.count == 6 {
                return bytes
            }
        }
        return Data([0x02, 0x55, 0x4E, 0x44, 0x52, 0x56])
    }

    private func appendParam(to data: inout Data, paramId: UInt16, string: String) {
        if let sData = string.data(using: .utf8) {
            appendParam(to: &data, paramId: paramId, data: sData)
        }
    }

    private func appendNullTerminatedParam(to data: inout Data, paramId: UInt16, string: String) {
        if var sData = string.data(using: .utf8) {
            sData.append(0x00)
            appendParam(to: &data, paramId: paramId, data: sData)
        }
    }

    private func appendParam(to data: inout Data, paramId: UInt16, data paramData: Data) {
        let length = UInt16(4 + paramData.count)
        data.append(UInt8((length >> 8) & 0xFF))
        data.append(UInt8(length & 0xFF))
        data.append(UInt8((paramId >> 8) & 0xFF))
        data.append(UInt8(paramId & 0xFF))
        data.append(paramData)
    }

    private func appendSubParam(to data: inout Data, subId: UInt8, string: String) {
        if let sData = string.data(using: .utf8) {
            data.append(subId)
            data.append(UInt8(sData.count))
            data.append(sData)
        }
    }

    private static func hexToData(_ hex: String) -> Data {
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
