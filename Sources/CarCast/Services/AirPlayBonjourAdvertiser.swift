//
//  AirPlayBonjourAdvertiser.swift
//  CarCast
//
//  Publishes Bonjour mDNS advertisements for AirPlay and CarPlay receivers.
//

import Foundation
import Network

public final class AirPlayBonjourAdvertiser: @unchecked Sendable {
    private var airPlayService: NetService?
    private var carPlayService: NetService?
    private var carCastService: NetService?

    private let port: Int32

    public init(port: UInt16 = 7000) {
        self.port = Int32(port)
    }

    public func startAdvertising(name: String, deviceId: String) {
        stopAdvertising()

        // 1. _airplay._tcp advertisement
        let apService = NetService(domain: "local.", type: "_airplay._tcp.", name: name, port: port)
        let txtDict: [String: String] = [
            "model": "CarCast,1",
            "srcvers": "377.17.24.6",
            "deviceid": deviceId,
            "features": "0x4A836,0x1C8340",
            "flags": "0x4",
            "vv": "2",
            "pk": "E7B442A0C2258814D78B291244A003429815041B7F00224A1D88800166299100"
        ]
        apService.setTXTRecord(NetService.data(fromTXTRecord: txtDict.mapValues { $0.data(using: .utf8) ?? Data() }))
        apService.publish()
        self.airPlayService = apService

        // 2. _carplay._tcp advertisement
        let cpService = NetService(domain: "local.", type: "_carplay._tcp.", name: name, port: port)
        let cpTxt: [String: String] = [
            "name": name,
            "srcvers": "377.17.24.6",
            "deviceid": deviceId
        ]
        cpService.setTXTRecord(NetService.data(fromTXTRecord: cpTxt.mapValues { $0.data(using: .utf8) ?? Data() }))
        cpService.publish()
        self.carPlayService = cpService

        // 3. _carcast._tcp advertisement for peer-to-peer CarCast discovery
        let ccService = NetService(domain: "local.", type: "_carcast._tcp.", name: name, port: port)
        let ccTxt: [String: String] = [
            "version": "1.0",
            "name": name,
            "platform": "ios"
        ]
        ccService.setTXTRecord(NetService.data(fromTXTRecord: ccTxt.mapValues { $0.data(using: .utf8) ?? Data() }))
        ccService.publish()
        self.carCastService = ccService

        Task { @MainActor in
            ProtocolLogger.shared.log(
                category: .bonjour,
                direction: .tx,
                title: "Published Bonjour Services",
                detail: "\(name) on port \(self.port) (_airplay, _carplay, _carcast)"
            )
        }
    }

    public func stopAdvertising() {
        airPlayService?.stop()
        airPlayService = nil
        carPlayService?.stop()
        carPlayService = nil
        carCastService?.stop()
        carCastService = nil
    }
}
