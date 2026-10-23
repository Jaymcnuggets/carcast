//
//  AirPlayBonjourBrowser.swift
//  DrivingMode
//
//  Browses local network for available DrivingMode receivers and displays.
//

import Foundation
import Network

public struct DiscoveredReceiver: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let endpoint: String
    public let isDrivingModeNative: Bool

    public init(id: String, name: String, endpoint: String, isDrivingModeNative: Bool) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.isDrivingModeNative = isDrivingModeNative
    }
}

@MainActor
public final class AirPlayBonjourBrowser: ObservableObject {
    public static let shared = AirPlayBonjourBrowser()

    @Published public private(set) var receivers: [DiscoveredReceiver] = []
    @Published public private(set) var isScanning: Bool = false

    private var browser: NWBrowser?

    private init() {}

    public func startScanning() {
        stopScanning()
        isScanning = true

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_drivingmode._tcp.", domain: "local.")
        let params = NWParameters()
        params.includePeerToPeer = true

        let browser = NWBrowser(for: descriptor, using: params)
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                var list: [DiscoveredReceiver] = []
                for res in results {
                    if case let .service(name, _, _, _) = res.endpoint {
                        let id = res.endpoint.debugDescription
                        list.append(DiscoveredReceiver(
                            id: id,
                            name: name,
                            endpoint: res.endpoint.debugDescription,
                            isDrivingModeNative: true
                        ))
                    }
                }
                self.receivers = list
            }
        }

        browser.stateUpdateHandler = { state in
            if state == .ready {
                Task { @MainActor in
                    ProtocolLogger.shared.log(category: .bonjour, title: "Bonjour Browser Active", detail: "Scanning for _drivingmode._tcp")
                }
            }
        }

        browser.start(queue: .main)
    }

    public func stopScanning() {
        browser?.cancel()
        browser = nil
        isScanning = false
    }
}
