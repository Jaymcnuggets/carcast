//
//  CarPlaySessionChannels.swift
//  DrivingMode
//
//  Real listeners for the ports advertised in the CarPlay session SETUP reply.
//  The iPhone connects to `eventPort` (TCP) immediately after SETUP; if nothing is listening the connect is refused
//  and it tears down the RTSP control connection within ~1 ms. `timingPort` (UDP, NTP-style) and
//  `keepAlivePort` (UDP, keepAliveLowPower) are also bound here so every advertised port is real.
//

import Foundation
import Network

public final class CarPlaySessionChannels: @unchecked Sendable {
    public static let shared = CarPlaySessionChannels()

    private let queue = DispatchQueue(label: "dev.unordinarylabs.DrivingMode.SessionChannels", qos: .userInteractive)
    private var eventListener: NWListener?
    private var timingListener: NWListener?
    private var keepAliveListener: NWListener?
    private var eventConnections: [NWConnection] = []

    public private(set) var eventPort: UInt16 = 0
    public private(set) var timingPort: UInt16 = 0
    public private(set) var keepAlivePort: UInt16 = 0

    /// Called with each event-channel connection once established (for encryption setup by the owner).
    public var onEventConnection: ((NWConnection) -> Void)?

    private init() {}

    public var isReady: Bool { eventPort != 0 && timingPort != 0 && keepAlivePort != 0 }

    public func start() {
        queue.async { [weak self] in
            guard let self = self, self.eventListener == nil else { return }
            self.eventListener = self.makeListener(name: "event", udp: false) { [weak self] port in self?.eventPort = port }
            self.timingListener = self.makeListener(name: "timing", udp: true) { [weak self] port in self?.timingPort = port }
            self.keepAliveListener = self.makeListener(name: "keepAlive", udp: true) { [weak self] port in self?.keepAlivePort = port }
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            [self.eventListener, self.timingListener, self.keepAliveListener].forEach { $0?.cancel() }
            self.eventConnections.forEach { $0.cancel() }
            self.eventConnections.removeAll()
            self.eventListener = nil; self.timingListener = nil; self.keepAliveListener = nil
            self.eventPort = 0; self.timingPort = 0; self.keepAlivePort = 0
        }
    }

    /// Blocks briefly (max ~1 s) until all listeners have ports, so SETUP can advertise real values.
    public func waitUntilReady(timeout: TimeInterval = 1.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !isReady && Date() < deadline { usleep(10_000) }
        return isReady
    }

    private func makeListener(name: String, udp: Bool, onReady: @escaping (UInt16) -> Void) -> NWListener? {
        do {
            let listener = try NWListener(using: udp ? .udp : .tcp, on: .any)
            listener.stateUpdateHandler = { [weak listener] state in
                switch state {
                case .ready:
                    let port = listener?.port?.rawValue ?? 0
                    onReady(port)
                    writeAppLog("[Session] \(name) listener ready on port \(port) (\(udp ? "UDP" : "TCP"))")
                    NSLog("[DrivingMode][Session] %@ listener ready on port %d (%@)", name, port, udp ? "UDP" : "TCP")
                case .failed(let err):
                    writeAppLog("[Session] \(name) listener FAILED: \(err.localizedDescription)")
                    NSLog("[DrivingMode][Session] %@ listener FAILED: %@", name, err.localizedDescription)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                guard let self = self else { return }
                writeAppLog("[Session] \(name) channel: incoming connection from \(conn.endpoint)")
                NSLog("[DrivingMode][Session] %@ channel: connection from %@", name, String(describing: conn.endpoint))
                if name == "event" {
                    self.eventConnections.append(conn)
                    if let handler = self.onEventConnection {
                        handler(conn)
                        return
                    }
                }
                conn.stateUpdateHandler = { st in
                    if case .failed(let e) = st { NSLog("[DrivingMode][Session] %@ channel connection failed: %@", name, e.localizedDescription) }
                    if case .cancelled = st { NSLog("[DrivingMode][Session] %@ channel connection closed", name) }
                }
                conn.start(queue: self.queue)
                self.receiveLoop(conn, name: name, udp: udp)
            }
            listener.start(queue: queue)
            return listener
        } catch {
            NSLog("[DrivingMode][Session] Failed to create %@ listener: %@", name, error.localizedDescription)
            return nil
        }
    }

    private func receiveLoop(_ conn: NWConnection, name: String, udp: Bool) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            if let d = data, !d.isEmpty {
                NSLog("[DrivingMode][Session] %@ RX %d bytes: %@", name, d.count, d.prefix(24).map { String(format: "%02X", $0) }.joined(separator: " "))
            }
            // For UDP, isComplete marks the end of each datagram, not the end of the flow.
            if error != nil || (complete && !udp) {
                NSLog("[DrivingMode][Session] %@ peer closed (complete=%d error=%@)", name, complete ? 1 : 0, String(describing: error))
                return
            }
            self?.receiveLoop(conn, name: name, udp: udp)
        }
    }
}
