//
//  AirPlayBonjourAdvertiser.swift
//  CarCast
//
//  Publishes Bonjour mDNS advertisements for AirPlay and CarPlay receivers.
//

import Foundation
import Network

public final class AirPlayBonjourAdvertiser: NSObject, NetServiceDelegate, @unchecked Sendable {
    private var airPlayService: NetService?
    private var raopService: NetService?
    private var carPlayService: NetService?
    private var carCastService: NetService?

    private let port: Int32

    public init(port: UInt16 = 7000) {
        self.port = Int32(port)
        super.init()
    }

    public func startAdvertising(name: String, deviceId: String) {
        stopAdvertising()

        // Format MAC address with colons and without colons
        let cleanDeviceId = deviceId.replacingOccurrences(of: ":", with: "").uppercased()
        let macWithColons: String
        if cleanDeviceId.count == 12 {
            macWithColons = stride(from: 0, to: 12, by: 2)
                .map { cleanDeviceId[cleanDeviceId.index(cleanDeviceId.startIndex, offsetBy: $0)..<cleanDeviceId.index(cleanDeviceId.startIndex, offsetBy: $0 + 2)] }
                .joined(separator: ":")
        } else {
            macWithColons = deviceId
        }

        let pubKey = "E7B442A0C2258814D78B291244A003429815041B7F00224A1D88800166299100"
        let piUUID = UUID().uuidString.lowercased()
        let psiUUID = UUID().uuidString.uppercased()

        // 1. _airplay._tcp advertisement (Primary AirPlay discovery)
        let apService = NetService(domain: "local.", type: "_airplay._tcp.", name: name, port: port)
        let apTxt: [String: String] = [
            "model": "CarPlay,1",
            "srcvers": "377.17.24.6",
            "deviceid": macWithColons,
            "features": "0x4A7FDFD5,0x3C177FDE",
            "flags": "0x4",
            "protovers": "1.1",
            "vv": "2",
            "pk": pubKey,
            "pi": piUUID,
            "psi": psiUUID
        ]
        apService.setTXTRecord(NetService.data(fromTXTRecord: apTxt.mapValues { $0.data(using: .utf8) ?? Data() }))
        apService.delegate = self
        apService.schedule(in: .main, forMode: .common)
        apService.publish()
        self.airPlayService = apService

        // 2. _raop._tcp advertisement (AirPlay Audio & Screen Mirroring discovery)
        let raopName = "\(cleanDeviceId)@\(name)"
        let raopService = NetService(domain: "local.", type: "_raop._tcp.", name: raopName, port: port)
        let raopTxt: [String: String] = [
            "ch": "2",
            "cn": "0,1,2,3",
            "da": "true",
            "et": "0,3,5",
            "ft": "0x4A7FDFD5,0x3C177FDE",
            "sf": "0x4",
            "md": "0,1,2",
            "sr": "44100",
            "ss": "16",
            "sv": "false",
            "tp": "UDP",
            "vn": "65537",
            "pk": pubKey
        ]
        raopService.setTXTRecord(NetService.data(fromTXTRecord: raopTxt.mapValues { $0.data(using: .utf8) ?? Data() }))
        raopService.delegate = self
        raopService.schedule(in: .main, forMode: .common)
        raopService.publish()
        self.raopService = raopService

        // 3. _carplay._tcp advertisement (Wireless CarPlay handoff)
        let cpService = NetService(domain: "local.", type: "_carplay._tcp.", name: name, port: port)
        let cpTxt: [String: String] = [
            "name": name,
            "model": "CarPlay,1",
            "srcvers": "377.17.24.6",
            "deviceid": macWithColons
        ]
        cpService.setTXTRecord(NetService.data(fromTXTRecord: cpTxt.mapValues { $0.data(using: .utf8) ?? Data() }))
        cpService.delegate = self
        cpService.schedule(in: .main, forMode: .common)
        cpService.publish()
        self.carPlayService = cpService

        // 4. _carcast._tcp advertisement (Peer-to-peer CarCast discovery)
        let ccService = NetService(domain: "local.", type: "_carcast._tcp.", name: name, port: port)
        let ccTxt: [String: String] = [
            "version": "1.0",
            "name": name,
            "platform": "ios"
        ]
        ccService.setTXTRecord(NetService.data(fromTXTRecord: ccTxt.mapValues { $0.data(using: .utf8) ?? Data() }))
        ccService.delegate = self
        ccService.schedule(in: .main, forMode: .common)
        ccService.publish()
        self.carCastService = ccService

        Task { @MainActor in
            ProtocolLogger.shared.log(
                category: .bonjour,
                direction: .tx,
                title: "Publishing Bonjour Services",
                detail: "\(name) on port \(self.port) (_airplay, _raop, _carplay, _carcast)"
            )
        }
    }

    public func stopAdvertising() {
        airPlayService?.stop()
        airPlayService = nil
        raopService?.stop()
        raopService = nil
        carPlayService?.stop()
        carPlayService = nil
        carCastService?.stop()
        carCastService = nil
    }

    // MARK: - NetServiceDelegate

    public func netServiceDidPublish(_ sender: NetService) {
        Task { @MainActor in
            ProtocolLogger.shared.log(
                category: .bonjour,
                direction: .tx,
                title: "Bonjour Published",
                detail: "\(sender.name) (\(sender.type)) on port \(sender.port)"
            )
        }
    }

    public func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        Task { @MainActor in
            ProtocolLogger.shared.log(
                category: .bonjour,
                direction: .internal,
                title: "Bonjour Publish Error",
                detail: "\(sender.name) (\(sender.type)): \(errorDict)"
            )
        }
    }
}
