//
//  CarPlayBluetoothAdvertiser.swift
//  CarCast
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
    public static let iap1ServiceUUID = CBUUID(string: "00000000-DECA-FADE-DECA-DEAFDECACAFE")

    private var peripheralManager: CBPeripheralManager?
    private var pendingCarName: String?
    private var isAdvertising = false
    private let queue = DispatchQueue(label: "dev.unordinarylabs.carcast.bluetooth", qos: .utility)

    public override init() {
        super.init()
    }

    public func startAdvertising(carName: String) {
        queue.async {
            self.pendingCarName = carName
            if self.peripheralManager == nil {
                self.peripheralManager = CBPeripheralManager(delegate: self, queue: self.queue)
            } else if self.peripheralManager?.state == .poweredOn {
                self.performAdvertising(name: carName)
            }
        }
    }

    public func stopAdvertising() {
        queue.async {
            self.isAdvertising = false
            self.pendingCarName = nil
            self.peripheralManager?.stopAdvertising()
            self.peripheralManager?.removeAllServices()
        }
    }

    private func performAdvertising(name: String) {
        guard let pm = peripheralManager, pm.state == .poweredOn else { return }

        pm.stopAdvertising()
        pm.removeAllServices()

        // Create the primary Wireless CarPlay GATT Service
        let service = CBMutableService(type: Self.carPlayServiceUUID, primary: true)
        pm.add(service)

        // Broadcast CarPlay peripheral advertisement
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [Self.carPlayServiceUUID],
            CBAdvertisementDataLocalNameKey: name
        ]

        pm.startAdvertising(advertisementData)
        self.isAdvertising = true

        Task { @MainActor in
            ProtocolLogger.shared.log(
                category: .system,
                title: "Bluetooth CarPlay Advertiser Active",
                detail: "Broadcasting \(name) on UUID \(Self.carPlayServiceUUID.uuidString)"
            )
        }
    }

    // MARK: - CBPeripheralManagerDelegate

    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            if let name = pendingCarName {
                performAdvertising(name: name)
            }
        case .poweredOff, .unsupported, .unauthorized, .resetting, .unknown:
            isAdvertising = false
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
}
