//
//  SteeringWheelRemoteService.swift
//  DrivingMode
//
//  Integrates standard AVRCP Bluetooth steering wheel controls (MPRemoteCommandCenter)
//  and hardware keyboard / remote shortcut dispatching to CarPlay HID events and emergency dashcam save.
//

import Foundation
#if canImport(MediaPlayer)
import MediaPlayer
#endif

@MainActor
public final class SteeringWheelRemoteService: ObservableObject {
    public static let shared = SteeringWheelRemoteService()

    public var onHomePressed: (() -> Void)?
    public var onSiriPressed: (() -> Void)?
    public var onEmergencySavePressed: (() -> Void)?
    public var onPlayPause: (() -> Void)?
    public var onNextTrack: (() -> Void)?
    public var onPreviousTrack: (() -> Void)?

    private init() {
        setupRemoteCommandCenter()
    }

    public func setupRemoteCommandCenter() {
        #if canImport(MediaPlayer)
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            self?.onPlayPause?()
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            self?.onPlayPause?()
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onPlayPause?()
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.onNextTrack?()
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPreviousTrack?()
            return .success
        }
        #endif
    }

    public func handleKeyInput(_ key: String) {
        switch key.lowercased() {
        case "h":
            onHomePressed?()
        case "s":
            onSiriPressed?()
        case "e":
            onEmergencySavePressed?()
        case " ":
            onPlayPause?()
        default:
            break
        }
    }
}
