//
//  VehicleTelemetry.swift
//  CarCast
//
//  Simulated or connected automotive vehicle telemetry model for CarPlay Ultra.
//

import Foundation
import Combine

public enum TurnSignalState: String, Codable, Sendable {
    case off
    case left
    case right
    case hazard
}

@MainActor
public final class VehicleTelemetry: ObservableObject {
    public static let shared = VehicleTelemetry()

    @Published public var speedMph: Double = 65.0
    @Published public var rpm: Double = 2800.0
    @Published public var gear: String = "D"
    @Published public var fuelPercent: Double = 0.78
    @Published public var batteryPercent: Double = 0.85
    @Published public var rangeMiles: Int = 340
    @Published public var coolantTempC: Double = 90.0
    @Published public var odometerMiles: Double = 14250.0
    @Published public var turnSignal: TurnSignalState = .off
    @Published public var headlampsOn: Bool = false
    @Published public var highBeamsOn: Bool = false
    @Published public var seatbeltFastened: Bool = true
    @Published public var parkBrakeEngaged: Bool = false

    // Now Playing track info from CarPlay iAP2
    @Published public var currentTrackTitle: String = "Midnight City"
    @Published public var currentArtist: String = "M83"
    @Published public var currentAlbum: String = "Hurry Up, We're Dreaming"
    @Published public var trackProgress: Double = 0.42
    @Published public var trackDurationSeconds: Double = 243.0
    @Published public var isPlaying: Bool = true
    @Published public var albumArtworkData: Data? = nil

    private var simulationTimer: AnyCancellable?

    private init() {
        startSimulation()
    }

    public func startSimulation() {
        simulationTimer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tickSimulation()
            }
    }

    public func stopSimulation() {
        simulationTimer?.cancel()
        simulationTimer = nil
    }

    private func tickSimulation() {
        // Subtle organic needle fluctuation for realism
        let speedJitter = Double.random(in: -0.3...0.3)
        let rpmJitter = Double.random(in: -20...20)

        speedMph = max(0, min(160, speedMph + speedJitter))
        rpm = max(800, min(7500, rpm + rpmJitter))

        if isPlaying {
            trackProgress = min(1.0, trackProgress + (0.1 / trackDurationSeconds))
            if trackProgress >= 1.0 {
                trackProgress = 0.0
            }
        }
    }

    public func updateDriving(
        speed: Double,
        rpm: Double,
        gear: String,
        turnSignal: TurnSignalState = .off
    ) {
        self.speedMph = speed
        self.rpm = rpm
        self.gear = gear
        self.turnSignal = turnSignal
    }

    public func updateNowPlaying(
        title: String,
        artist: String,
        album: String,
        duration: Double,
        elapsed: Double,
        artwork: Data? = nil
    ) {
        self.currentTrackTitle = title
        self.currentArtist = artist
        self.currentAlbum = album
        self.trackDurationSeconds = max(1.0, duration)
        self.trackProgress = min(1.0, elapsed / trackDurationSeconds)
        self.isPlaying = true
        if let artwork = artwork {
            self.albumArtworkData = artwork
        }
    }
}
