//
//  CarPlayBluetoothAdvertiser.swift
//  DrivingMode
//
//  Authentic Wireless CarPlay CoreBluetooth Peripheral Advertiser:
//  Publishes Apple Wireless CarPlay GATT Service UUID:
//  00000000-DECA-FADE-DECA-DEAFDECACAFF
//  allowing iOS carplayd and Settings > General > CarPlay to discover this car.
//

import Foundation
import CoreBluetooth

public final class CarPlayBluetoothAdvertiser: NSObject, CBPeripheralManagerDelegate, @unchecked Sendable {
    public static let shared = CarPlayBluetoothAdvertiser()

    public static let carPlayServiceUUID = CBUUID(string: "00000000-DECA-FADE-DECA-DEAFDECACAFF")
    public static let iap1CharacteristicUUID = CBUUID(string: "00000000-DECA-FADE-DECA-DEAFDECACAFE")
    public static let handoffServiceUUID = CBUUID(string: "D31FBF50-5D57-2797-A240-41CD484388EC")

    private var peripheralManager: CBPeripheralManager?
    private var pendingCarName: String?
    public private(set) var isAdvertising = false
    private var servicesAdded = false
    private var iapCharacteristic: CBMutableCharacteristic?
    private var pendingOutgoingData: [Data] = []
    private var subscribedCentrals: [CBCentral] = []
    public var subscribedCentralCount: Int { subscribedCentrals.count }
    public var onDataReceived: ((Data) -> Void)?
    public var onCentralConnectionChanged: ((Int, String) -> Void)?
    private let queue = DispatchQueue(label: "dev.unordinarylabs.drivingmode.bluetooth", qos: .utility)

    public override init() {
        super.init()
    }

    public func startAdvertising(carName: String) {
        queue.async {
            self.pendingCarName = carName
            if self.peripheralManager == nil {
                self.peripheralManager = CBPeripheralManager(delegate: self, queue: self.queue)
            } else if self.peripheralManager?.state == .poweredOn {
                self.setupServicesAndAdvertise(name: carName)
            }
        }
    }

    public func stopAdvertising() {
        queue.async {
            self.isAdvertising = false
            self.pendingCarName = nil
            self.subscribedCentrals.removeAll()
            self.pendingOutgoingData.removeAll()
            self.peripheralManager?.stopAdvertising()
        }
    }

    private func setupServicesAndAdvertise(name: String) {
        guard let pm = peripheralManager, pm.state == .poweredOn else { return }

        if !servicesAdded {
            pm.removeAllServices()

            // 1. Primary Wireless CarPlay GATT Service with iAP1/iAP2 communication characteristic
            let carPlayService = CBMutableService(type: Self.carPlayServiceUUID, primary: true)
            let iapChar = CBMutableCharacteristic(
                type: Self.iap1CharacteristicUUID,
                properties: [.read, .write, .notify, .writeWithoutResponse],
                value: nil,
                permissions: [.readable, .writeable]
            )
            self.iapCharacteristic = iapChar
            carPlayService.characteristics = [iapChar]
            pm.add(carPlayService)

            // 2. CarPlay Handoff service
            let handoffService = CBMutableService(type: Self.handoffServiceUUID, primary: false)
            let handoffChar = CBMutableCharacteristic(
                type: Self.handoffServiceUUID,
                properties: [.read, .write],
                value: nil,
                permissions: [.readable, .writeable]
            )
            handoffService.characteristics = [handoffChar]
            pm.add(handoffService)

            servicesAdded = true
        }

        pm.stopAdvertising()

        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [Self.carPlayServiceUUID],
            CBAdvertisementDataLocalNameKey: name
        ]

        pm.startAdvertising(advertisementData)
        self.isAdvertising = true

        NSLog("[DrivingMode][BLE] Bluetooth CarPlay Advertiser Active: Broadcasting '%@' on UUID %@ (subscribedCentrals=%d; NOTE: BLE GATT only discovers external iPhones — same-device 'This iPhone' uses ACCTransport/RTSP loopback)", name, Self.carPlayServiceUUID.uuidString, self.subscribedCentrals.count)

        Task { @MainActor in
            ProtocolLogger.shared.log(
                category: .system,
                title: "Bluetooth CarPlay Advertiser Active",
                detail: "Broadcasting \(name) on UUID \(Self.carPlayServiceUUID.uuidString) (centrals=\(self.subscribedCentrals.count); external discovery only, loopback uses ACCTransport)"
            )
        }
    }

    // MARK: - CBPeripheralManagerDelegate

    public func sendData(_ data: Data) {
        queue.async {
            guard let pm = self.peripheralManager, let char = self.iapCharacteristic else {
                self.pendingOutgoingData.append(data)
                return
            }
            let success = pm.updateValue(data, for: char, onSubscribedCentrals: self.subscribedCentrals.isEmpty ? nil : self.subscribedCentrals)
            if !success {
                self.pendingOutgoingData.append(data)
            }
        }
    }

    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            if let name = pendingCarName {
                setupServicesAndAdvertise(name: name)
            }
        case .poweredOff, .unsupported, .unauthorized, .resetting, .unknown:
            isAdvertising = false
            servicesAdded = false
            iapCharacteristic = nil
        @unknown default:
            break
        }
    }

    public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let err = error {
            Task { @MainActor in
                ProtocolLogger.shared.log(
                    category: .system,
                    title: "Bluetooth Advertising Error",
                    detail: err.localizedDescription
                )
            }
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        queue.async {
            if !self.subscribedCentrals.contains(where: { $0.identifier == central.identifier }) {
                self.subscribedCentrals.append(central)
            }
            let count = self.subscribedCentrals.count
            let centralId = central.identifier.uuidString
            NSLog("[DrivingMode][BLE] Central subscribed to CarPlay GATT characteristic (%@), subscribedCentrals=%d", centralId, count)
            self.onCentralConnectionChanged?(count, "BLE central \(centralId) subscribed")
            if let char = self.iapCharacteristic {
                while !self.pendingOutgoingData.isEmpty {
                    let next = self.pendingOutgoingData.removeFirst()
                    peripheral.updateValue(next, for: char, onSubscribedCentrals: [central])
                }
            }
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        queue.async {
            self.subscribedCentrals.removeAll(where: { $0.identifier == central.identifier })
            let count = self.subscribedCentrals.count
            let centralId = central.identifier.uuidString
            NSLog("[DrivingMode][BLE] Central unsubscribed from CarPlay GATT characteristic (%@), subscribedCentrals=%d", centralId, count)
            self.onCentralConnectionChanged?(count, "BLE central \(centralId) unsubscribed")
        }
    }

    public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        queue.async {
            guard let char = self.iapCharacteristic else { return }
            while !self.pendingOutgoingData.isEmpty {
                let next = self.pendingOutgoingData.first!
                if peripheral.updateValue(next, for: char, onSubscribedCentrals: self.subscribedCentrals.isEmpty ? nil : self.subscribedCentrals) {
                    self.pendingOutgoingData.removeFirst()
                } else {
                    break
                }
            }
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        Task { @MainActor in
            ProtocolLogger.shared.log(
                category: .system,
                title: "Bluetooth GATT Read",
                detail: "Characteristic: \(request.characteristic.uuid.uuidString)"
            )
        }
        if request.characteristic.uuid == Self.iap1CharacteristicUUID && !pendingOutgoingData.isEmpty {
            request.value = pendingOutgoingData.removeFirst()
        } else {
            request.value = Data([0x01])
        }
        peripheral.respond(to: request, withResult: .success)
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for req in requests {
            if let data = req.value, !data.isEmpty {
                Task { @MainActor in
                    ProtocolLogger.shared.log(
                        category: .system,
                        title: "Bluetooth GATT Write",
                        detail: "Characteristic: \(req.characteristic.uuid.uuidString) (\(data.count) bytes)",
                        rawData: data
                    )
                }
                onDataReceived?(data)
            }
            peripheral.respond(to: req, withResult: .success)
        }
    }
}
