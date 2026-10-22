//
//  CarPlayControlClient.swift
//  DrivingMode
//
//  Client for discovering iOS CarPlay control endpoints (_carplay-ctrl._tcp)
//  and triggering wireless CarPlay session initiation via GET /ctrl-int/1/connect.
//

import Foundation
import Network

public final class CarPlayControlClient: @unchecked Sendable {
    public static let shared = CarPlayControlClient()

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "dev.unordinarylabs.drivingmode.ctrl", qos: .userInitiated)
    private var activeConnections: [NWConnection] = []

    private init() {}

    /// Initiates discovery of iOS CarPlay control endpoint and sends the connect probe.
    public func triggerCarPlayConnect(deviceId: String, completion: (@Sendable (Bool) -> Void)? = nil) {
        let cleanDeviceId = deviceId.replacingOccurrences(of: ":", with: "").uppercased()

        Task { @MainActor in
            ProtocolLogger.shared.log(
                category: .system,
                direction: .tx,
                title: "CarPlay Trigger Initiated",
                detail: "Scanning for _carplay-ctrl._tcp to trigger connect (ID: \(cleanDeviceId))"
            )
        }

        // Discover iOS CarPlay control daemon via Bonjour _carplay-ctrl._tcp
        discoverAndProbe(deviceId: cleanDeviceId, completion: completion)
    }

    private func discoverAndProbe(deviceId: String, completion: (@Sendable (Bool) -> Void)?) {
        browser?.cancel()

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_carplay-ctrl._tcp.", domain: "local.")
        let params = NWParameters()
        params.includePeerToPeer = true

        let browser = NWBrowser(for: descriptor, using: params)
        self.browser = browser

        var hasTriggered = false

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self, !hasTriggered else { return }
            for result in results {
                if case .service = result.endpoint {
                    hasTriggered = true
                    self.browser?.cancel()
                    self.browser = nil

                    self.probeEndpoint(result.endpoint, deviceId: deviceId, completion: completion)
                    break
                }
            }
        }

        browser.start(queue: queue)

        // Timeout fallback after 3 seconds if Bonjour discovery didn't find external ctrl
        queue.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard !hasTriggered else { return }
            self?.browser?.cancel()
            self?.browser = nil
            completion?(false)
        }
    }

    private func probeEndpoint(_ endpoint: NWEndpoint, deviceId: String, completion: (@Sendable (Bool) -> Void)?) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        activeConnections.append(connection)

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let connection = connection else { return }
            switch state {
            case .ready:
                self.sendConnectRequest(to: connection, hostDescription: endpoint.debugDescription, deviceId: deviceId, completion: completion)
            case .failed, .cancelled:
                self.activeConnections.removeAll(where: { $0 === connection })
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    public func probeHost(_ host: String, port: UInt16, deviceId: String, completion: (@Sendable (Bool) -> Void)? = nil) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            completion?(false)
            return
        }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        let connection = NWConnection(to: endpoint, using: .tcp)
        activeConnections.append(connection)

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let connection = connection else { return }
            switch state {
            case .ready:
                self.sendConnectRequest(to: connection, hostDescription: "\(host):\(port)", deviceId: deviceId, completion: completion)
            case .failed:
                connection.cancel()
                self.activeConnections.removeAll(where: { $0 === connection })
                completion?(false)
            case .cancelled:
                self.activeConnections.removeAll(where: { $0 === connection })
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func sendConnectRequest(
        to connection: NWConnection,
        hostDescription: String,
        deviceId: String,
        completion: (@Sendable (Bool) -> Void)?
    ) {
        let cleanId = deviceId.replacingOccurrences(of: ":", with: "")
        let deviceIdUInt64 = UInt64(cleanId, radix: 16) ?? 170054366648252
        let decimalDeviceId = "\(deviceIdUInt64)"

        let requestString = "GET /ctrl-int/1/connect HTTP/1.1\r\n" +
            "Host: \(hostDescription)\r\n" +
            "User-Agent: AirPlay/509.11\r\n" +
            "AirPlay-Receiver-Device-ID: \(decimalDeviceId)\r\n" +
            "Connection: close\r\n" +
            "\r\n"

        guard let requestData = requestString.data(using: .utf8) else {
            connection.cancel()
            completion?(false)
            return
        }

        Task { @MainActor in
            ProtocolLogger.shared.log(
                category: .system,
                direction: .tx,
                title: "CarPlay Connect Probe Sent",
                detail: "To \(hostDescription): GET /ctrl-int/1/connect (DeviceID: \(deviceId))"
            )
        }

        connection.send(content: requestData, completion: .contentProcessed { [weak self, weak connection] error in
            guard let self = self, let connection = connection else { return }
            if error != nil {
                connection.cancel()
                self.activeConnections.removeAll(where: { $0 === connection })
                completion?(false)
                return
            }

            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self, weak connection] data, _, _, _ in
                guard let self = self, let connection = connection else { return }
                connection.cancel()
                self.activeConnections.removeAll(where: { $0 === connection })

                if let data = data, let resp = String(data: data, encoding: .utf8), resp.contains("200 OK") {
                    Task { @MainActor in
                        ProtocolLogger.shared.log(
                            category: .system,
                            direction: .rx,
                            title: "CarPlay Connect Probe Acknowledged",
                            detail: "iOS returned 200 OK: session starting"
                        )
                    }
                    completion?(true)
                } else {
                    completion?(false)
                }
            }
        })
    }

    public func cancel() {
        browser?.cancel()
        browser = nil
        for conn in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
    }
}
