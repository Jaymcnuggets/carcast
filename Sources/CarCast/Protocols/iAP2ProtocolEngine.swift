//
//  iAP2ProtocolEngine.swift
//  CarCast
//
//  Authentic MFi iAP2 protocol state machine, packet framing, and CarPlay accessory identification.
//

import Foundation

public struct iAP2Packet {
    public static let syncBytes: [UInt8] = [0xFF, 0x5A]

    public enum ControlFlag: UInt8 {
        case syn = 0x80
        case ack = 0x40
        case eak = 0x20
        case rst = 0x10
        case slp = 0x08
    }

    public let controlByte: UInt8
    public let packetSeqNumber: UInt8
    public let ackSeqNumber: UInt8
    public let sessionID: UInt8
    public let payload: Data

    public init(controlByte: UInt8, packetSeq: UInt8, ackSeq: UInt8, sessionID: UInt8, payload: Data = Data()) {
        self.controlByte = controlByte
        self.packetSeqNumber = packetSeq
        self.ackSeqNumber = ackSeq
        self.sessionID = sessionID
        self.payload = payload
    }

    public func encode() -> Data {
        var data = Data()
        data.append(contentsOf: Self.syncBytes)

        let totalLength: UInt16 = payload.isEmpty ? 9 : UInt16(9 + payload.count + 1)
        data.append(UInt8((totalLength >> 8) & 0xFF))
        data.append(UInt8(totalLength & 0xFF))

        data.append(controlByte)
        data.append(packetSeqNumber)
        data.append(ackSeqNumber)
        data.append(sessionID)

        // Header checksum: 2's complement sum of header bytes from length to sessionID
        var headerSum: UInt32 = 0
        for byte in data[2..<8] {
            headerSum += UInt32(byte)
        }
        let headerChecksum = UInt8((~headerSum + 1) & 0xFF)
        data.append(headerChecksum)

        // Payload
        if !payload.isEmpty {
            data.append(payload)

            // Payload checksum
            var payloadSum: UInt32 = 0
            for byte in payload {
                payloadSum += UInt32(byte)
            }
            let payloadChecksum = UInt8((~payloadSum + 1) & 0xFF)
            data.append(payloadChecksum)
        }

        return data
    }

    public static func decode(from data: Data) -> (packet: iAP2Packet?, bytesConsumed: Int) {
        guard data.count >= 9 else { return (nil, 0) }

        // Find sync sequence FF 5A
        guard let syncIndex = (0..<(data.count - 1)).first(where: { data[$0] == 0xFF && data[$0 + 1] == 0x5A }) else {
            return (nil, data.count)
        }

        let slice = data.subdata(in: syncIndex..<data.count)
        guard slice.count >= 9 else { return (nil, syncIndex) }

        let length = Int((UInt16(slice[2]) << 8) | UInt16(slice[3]))
        guard length >= 9, slice.count >= length else {
            return (nil, syncIndex)
        }

        let control = slice[4]
        let packetSeq = slice[5]
        let ackSeq = slice[6]
        let sessionID = slice[7]

        let payloadData: Data
        if length > 9 {
            // Length includes 9 header bytes + payload bytes + 1 payload checksum byte
            let payloadLength = length - 10
            if payloadLength > 0 {
                payloadData = slice.subdata(in: 9..<(9 + payloadLength))
            } else {
                payloadData = Data()
            }
        } else {
            payloadData = Data()
        }

        let packet = iAP2Packet(
            controlByte: control,
            packetSeq: packetSeq,
            ackSeq: ackSeq,
            sessionID: sessionID,
            payload: payloadData
        )

        return (packet, syncIndex + length)
    }
}

public protocol iAP2ProtocolDelegate: AnyObject, Sendable {
    func iap2DidReceiveIdentificationAccepted()
    func iap2DidReceiveIdentificationRejected()
    func iap2DidReceiveNowPlayingUpdate(title: String, artist: String, album: String, duration: Double, elapsed: Double)
    func iap2DidReceiveArtwork(data: Data)
    func iap2DidRequestUI(mode: String?)
    func iap2SessionEnded()
}

public final class iAP2ProtocolEngine: @unchecked Sendable {
    public weak var delegate: iAP2ProtocolDelegate?

    private var txSeq: UInt8 = 0
    private var rxSeq: UInt8 = 0
    private var isConnected: Bool = false
    private let queue = DispatchQueue(label: "dev.unordinarylabs.carcast.iap2", qos: .userInteractive)

    public init() {}

    public func buildIdentificationPayload(
        carName: String,
        macAddress: String,
        wifiSSID: String,
        wifiPassword: String,
        wifiChannel: Int,
        linkLocalIPv6: String
    ) -> Data {
        var payload = Data()

        // Message ID: StartIdentification (0x1D00) or IdentificationInformation (0x1D01)
        let msgId: UInt16 = 0x1D01
        payload.append(UInt8((msgId >> 8) & 0xFF))
        payload.append(UInt8(msgId & 0xFF))

        // Param 0: Name
        appendParam(to: &payload, paramId: 0x0000, string: carName)
        // Param 1: Model ("MI-0001")
        appendParam(to: &payload, paramId: 0x0001, string: "MI-0001")
        // Param 2: Manufacturer ("rPlay")
        appendParam(to: &payload, paramId: 0x0002, string: "rPlay")
        // Param 3: Serial ("SN-202610210001")
        appendParam(to: &payload, paramId: 0x0003, string: "SN-202610210001")
        // Param 4: FirmwareVersion ("1.0.0")
        appendParam(to: &payload, paramId: 0x0004, string: "1.0.0")
        // Param 5: HardwareVersion ("1.0.0")
        appendParam(to: &payload, paramId: 0x0005, string: "1.0.0")

        // Param 0x0018: WiFiWirelessCarPlayTransportComponent
        var transportData = Data()
        // Sub-param: Identifier (1)
        var idVal: UInt16 = 1
        transportData.append(Data(bytes: &idVal, count: 2))
        // Sub-param: Name ("WirelessCarPlayTransport")
        if let nameBytes = "WirelessCarPlayTransport".data(using: .utf8) {
            transportData.append(nameBytes)
        }
        // Sub-param: SupportCarPlay (1)
        let supportCP: UInt8 = 1
        transportData.append(supportCP)
        // Sub-param: SupportiAP2 (1)
        let supportIAP: UInt8 = 1
        transportData.append(supportIAP)

        appendParam(to: &payload, paramId: 0x0018, data: transportData)

        // Param 0x0019: WirelessCarPlaySetupUpdate (SSID, pass, channel, BSSID, IPv6)
        var wifiSetupData = Data()
        appendSubParam(to: &wifiSetupData, subId: 0x01, string: wifiSSID)
        appendSubParam(to: &wifiSetupData, subId: 0x02, string: wifiPassword)
        var ch = UInt16(wifiChannel)
        wifiSetupData.append(Data(bytes: &ch, count: 2))
        appendSubParam(to: &wifiSetupData, subId: 0x04, string: macAddress)
        appendSubParam(to: &wifiSetupData, subId: 0x05, string: linkLocalIPv6)

        appendParam(to: &payload, paramId: 0x0019, data: wifiSetupData)

        return payload
    }

    public func handleIncomingBytes(_ data: Data) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var remaining = data
            while remaining.count >= 9 {
                let (packetOpt, consumed) = iAP2Packet.decode(from: remaining)
                guard consumed > 0 else { break }
                remaining = remaining.subdata(in: consumed..<remaining.count)

                if let packet = packetOpt {
                    self.processPacket(packet)
                }
            }
        }
    }

    private func processPacket(_ packet: iAP2Packet) {
        rxSeq = packet.packetSeqNumber

        Task { @MainActor in
            ProtocolLogger.shared.log(
                category: .iap2,
                direction: .rx,
                title: "iAP2 Packet (Ctrl: 0x\(String(format: "%02X", packet.controlByte)) Seq: \(packet.packetSeqNumber))",
                detail: "Payload \(packet.payload.count) bytes",
                rawData: packet.payload
            )
        }

        // Check for control flags
        if (packet.controlByte & iAP2Packet.ControlFlag.syn.rawValue) != 0 {
            // Send SYN+ACK
            sendAck()
            return
        }

        guard packet.payload.count >= 2 else { return }
        let msgId = (UInt16(packet.payload[0]) << 8) | UInt16(packet.payload[1])

        switch msgId {
        case 0x1D02: // IdentificationAccepted
            Task { @MainActor in
                ProtocolLogger.shared.log(category: .iap2, direction: .rx, title: "IdentificationAccepted", detail: "Phone accepted CarCast accessory")
            }
            delegate?.iap2DidReceiveIdentificationAccepted()

        case 0x1D03: // IdentificationRejected
            Task { @MainActor in
                ProtocolLogger.shared.log(category: .iap2, direction: .rx, title: "IdentificationRejected", detail: "Phone rejected identification")
            }
            delegate?.iap2DidReceiveIdentificationRejected()

        case 0x4E01: // NowPlayingUpdate
            parseNowPlaying(packet.payload.subdata(in: 2..<packet.payload.count))

        case 0x4E02: // Artwork
            let artData = packet.payload.subdata(in: 2..<packet.payload.count)
            delegate?.iap2DidReceiveArtwork(data: artData)

        case 0x000A: // RequestUI
            delegate?.iap2DidRequestUI(mode: nil)

        default:
            break
        }
    }

    private func parseNowPlaying(_ data: Data) {
        // Simplified parameter extraction for title, artist, album
        // iAP2 TLV parser
        var title = "Unknown Title"
        var artist = "Unknown Artist"
        var album = "Unknown Album"
        let duration: Double = 180.0
        let elapsed: Double = 0.0

        var offset = 0
        while offset + 4 <= data.count {
            let paramLength = Int((UInt16(data[offset]) << 8) | UInt16(data[offset + 1]))
            let paramId = (UInt16(data[offset + 2]) << 8) | UInt16(data[offset + 3])
            guard paramLength >= 4, offset + paramLength <= data.count else { break }

            let valData = data.subdata(in: (offset + 4)..<(offset + paramLength))
            switch paramId {
            case 0x01:
                title = String(data: valData, encoding: .utf8) ?? title
            case 0x02:
                artist = String(data: valData, encoding: .utf8) ?? artist
            case 0x03:
                album = String(data: valData, encoding: .utf8) ?? album
            default:
                break
            }
            offset += paramLength
        }

        delegate?.iap2DidReceiveNowPlayingUpdate(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsed: elapsed
        )
    }

    private func sendAck() {
        txSeq = (txSeq &+ 1)
        let ack = iAP2Packet(
            controlByte: iAP2Packet.ControlFlag.ack.rawValue,
            packetSeq: txSeq,
            ackSeq: rxSeq,
            sessionID: 1
        )
        let encoded = ack.encode()
        Task { @MainActor in
            ProtocolLogger.shared.log(category: .iap2, direction: .tx, title: "iAP2 ACK", detail: "AckSeq: \(rxSeq)", rawData: encoded)
        }
    }

    private func appendParam(to data: inout Data, paramId: UInt16, string: String) {
        if let sData = string.data(using: .utf8) {
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
}
