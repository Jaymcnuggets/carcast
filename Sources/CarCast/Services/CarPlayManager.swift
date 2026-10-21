//
//  CarPlayManager.swift
//  CarCast
//
//  Central coordinator for CarPlay & AirPlay receiver lifecycle and media pipeline.
//

import Foundation
import Combine
import CoreMedia

public enum ReceiverState: String, Sendable {
    case idle = "Ready"
    case starting = "Starting…"
    case waitingForPhone = "Waiting for iPhone"
    case connecting = "Connecting…"
    case streaming = "CarPlay Connected"
    case error = "Error"

    public var statusColor: String {
        switch self {
        case .idle: return "gray"
        case .starting, .waitingForPhone, .connecting: return "yellow"
        case .streaming: return "green"
        case .error: return "red"
        }
    }
}

@MainActor
public final class CarPlayManager: ObservableObject, @unchecked Sendable {
    public static let shared = CarPlayManager()

    @Published public private(set) var state: ReceiverState = .idle
    @Published public private(set) var connectedClientName: String? = nil
    @Published public private(set) var currentStreamResolution: CGSize = .zero
    @Published public private(set) var isStreamingActive: Bool = false
    @Published public var lastSampleBuffer: CMSampleBuffer? = nil

    private let rtspServer: RTSPServer
    private let screenReceiver: AirPlayScreenReceiver
    private let bonjourAdvertiser: AirPlayBonjourAdvertiser
    private let iap2Engine: iAP2ProtocolEngine

    private init() {
        self.rtspServer = RTSPServer(port: 7000)
        self.screenReceiver = AirPlayScreenReceiver(port: 7100)
        self.bonjourAdvertiser = AirPlayBonjourAdvertiser(port: 7000)
        self.iap2Engine = iAP2ProtocolEngine()

        self.screenReceiver.delegate = self
        self.rtspServer.delegate = self
        self.iap2Engine.delegate = self
    }

    public func startReceiver() {
        guard state == .idle || state == .error else { return }
        state = .starting

        let config = CarCastConfig.shared
        let carName = config.carName
        let deviceId = "0200" + String(format: "%08X", Int.random(in: 0x10000000...0x7FFFFFFF))

        do {
            try rtspServer.start()
            try screenReceiver.start()
            bonjourAdvertiser.startAdvertising(name: carName, deviceId: deviceId)
            state = .waitingForPhone

            ProtocolLogger.shared.log(
                category: .system,
                title: "CarPlay Receiver Started",
                detail: "Name: \(carName) | RTSP :7000 | Screen :7100"
            )
        } catch {
            state = .error
            ProtocolLogger.shared.log(
                category: .system,
                title: "Failed to Start Receiver",
                detail: error.localizedDescription
            )
        }
    }

    public func stopReceiver() {
        bonjourAdvertiser.stopAdvertising()
        screenReceiver.stop()
        rtspServer.stop()

        state = .idle
        connectedClientName = nil
        isStreamingActive = false
        currentStreamResolution = .zero
        lastSampleBuffer = nil

        ProtocolLogger.shared.log(category: .system, title: "CarPlay Receiver Stopped")
    }

    public func returnToCarPlay() {
        // Triggers UI shift back to full screen CarPlay
        if isStreamingActive {
            state = .streaming
        }
    }

    public func sendTouchEvent(action: Int, x: Double, y: Double) {
        // Forward normalized touch to iPhone
        ProtocolLogger.shared.log(
            category: .screen,
            direction: .tx,
            title: "Touch Event",
            detail: "Action: \(action) (X: \(String(format: "%.3f", x)), Y: \(String(format: "%.3f", y)))"
        )
    }

    public func sendHomeButtonPress() {
        ProtocolLogger.shared.log(
            category: .iap2,
            direction: .tx,
            title: "Home Button Pressed",
            detail: "Sending Home to CarPlay"
        )
    }
}

extension CarPlayManager: AirPlayScreenReceiverDelegate {
    nonisolated public func screenReceiverDidReceiveSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        Task { @MainActor in
            self.lastSampleBuffer = sampleBuffer
        }
    }

    nonisolated public func screenReceiverDidReceiveDimensions(width: Int, height: Int) {
        Task { @MainActor in
            self.currentStreamResolution = CGSize(width: width, height: height)
        }
    }

    nonisolated public func screenReceiverStateChanged(isActive: Bool) {
        Task { @MainActor in
            self.isStreamingActive = isActive
            if isActive {
                self.state = .streaming
            } else if self.state == .streaming {
                self.state = .waitingForPhone
            }
        }
    }
}

extension CarPlayManager: RTSPServerDelegate {
    nonisolated public func rtspServerDidStartSession(clientName: String?) {
        Task { @MainActor in
            self.connectedClientName = clientName ?? "iPhone"
            self.state = .connecting
        }
    }

    nonisolated public func rtspServerDidEndSession() {
        Task { @MainActor in
            self.connectedClientName = nil
            self.isStreamingActive = false
            self.state = .waitingForPhone
        }
    }

    nonisolated public func rtspServerDidUpdateVolume(_ volume: Float) {}
}

extension CarPlayManager: iAP2ProtocolDelegate {
    nonisolated public func iap2DidReceiveIdentificationAccepted() {
        Task { @MainActor in
            self.state = .streaming
        }
    }

    nonisolated public func iap2DidReceiveIdentificationRejected() {
        Task { @MainActor in
            self.state = .error
        }
    }

    nonisolated public func iap2DidReceiveNowPlayingUpdate(
        title: String,
        artist: String,
        album: String,
        duration: Double,
        elapsed: Double
    ) {
        Task { @MainActor in
            VehicleTelemetry.shared.updateNowPlaying(
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                elapsed: elapsed
            )
        }
    }

    nonisolated public func iap2DidReceiveArtwork(data: Data) {
        Task { @MainActor in
            VehicleTelemetry.shared.albumArtworkData = data
        }
    }

    nonisolated public func iap2DidRequestUI(mode: String?) {
        Task { @MainActor in
            // Return to native car UI
            self.state = .waitingForPhone
        }
    }

    nonisolated public func iap2SessionEnded() {
        Task { @MainActor in
            self.isStreamingActive = false
            self.state = .waitingForPhone
        }
    }
}
