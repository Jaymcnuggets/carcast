//
//  DrivingModeConfig.swift
//  DrivingMode
//
//  Central persistent configuration for DrivingMode receiver and vehicle settings.
//

import Foundation
import Combine

public enum DrivingPosition: String, Codable, CaseIterable, Sendable {
    case leftHandDrive = "lhd"
    case rightHandDrive = "rhd"

    public var title: String {
        switch self {
        case .leftHandDrive: return "Left-hand drive"
        case .rightHandDrive: return "Right-hand drive"
        }
    }
}

public enum DisplayPreset: String, Codable, CaseIterable, Sendable {
    case fitScreen = "fit"
    case standard800x480 = "800x480"
    case widescreen1920x720 = "1920x720"
    case fullHD1920x1080 = "1920x1080"

    public var title: String {
        switch self {
        case .fitScreen: return "Fit this screen (Native)"
        case .standard800x480: return "Standard (800 × 480)"
        case .widescreen1920x720: return "Widescreen (1920 × 720)"
        case .fullHD1920x1080: return "Full HD (1920 × 1080)"
        }
    }

    public var dimensions: (width: Int, height: Int)? {
        switch self {
        case .fitScreen: return nil
        case .standard800x480: return (800, 480)
        case .widescreen1920x720: return (1920, 720)
        case .fullHD1920x1080: return (1920, 1080)
        }
    }
}

public enum ClusterContentMode: String, Codable, CaseIterable, Sendable {
    case map = "map"
    case turnCard = "turn_card"
    case appDecides = "app_decides"

    public var title: String {
        switch self {
        case .map: return "Map"
        case .turnCard: return "Turn Card"
        case .appDecides: return "Navigation App Decides"
        }
    }
}

public enum ClusterSize: String, Codable, CaseIterable, Sendable {
    case small = "small"
    case medium = "medium"
    case large = "large"

    public var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}

public enum NightModeSetting: String, Codable, CaseIterable, Sendable {
    case auto = "auto"
    case on = "on"
    case off = "off"

    public var title: String {
        switch self {
        case .auto: return "Auto (System Dark Mode)"
        case .on: return "Always On (Dark)"
        case .off: return "Always Off (Light)"
        }
    }
}

@MainActor
public final class DrivingModeConfig: ObservableObject {
    public static let shared = DrivingModeConfig()

    private let defaults = UserDefaults.standard

    @Published public var carName: String {
        didSet { defaults.set(carName, forKey: "carcast.car.name") }
    }

    public let deviceId: String

    @Published public var selectedBrandId: String {
        didSet { defaults.set(selectedBrandId, forKey: "carcast.car.brand_id") }
    }

    @Published public var customLogoLabel: String {
        didSet { defaults.set(customLogoLabel, forKey: "carcast.car.logo_label") }
    }

    @Published public var drivingPosition: DrivingPosition {
        didSet { defaults.set(drivingPosition.rawValue, forKey: "carcast.car.driving_pos") }
    }

    @Published public var displayPreset: DisplayPreset {
        didSet { defaults.set(displayPreset.rawValue, forKey: "carcast.display.preset") }
    }

    @Published public var isPortraitAllowed: Bool {
        didSet { defaults.set(isPortraitAllowed, forKey: "carcast.display.portrait") }
    }

    @Published public var avoidNotch: Bool {
        didSet { defaults.set(avoidNotch, forKey: "carcast.display.avoid_notch") }
    }

    @Published public var showTouches: Bool {
        didSet { defaults.set(showTouches, forKey: "carcast.display.show_touches") }
    }

    @Published public var videoPlaybackAllowed: Bool {
        didSet { defaults.set(videoPlaybackAllowed, forKey: "carcast.display.video_playback") }
    }

    @Published public var nightMode: NightModeSetting {
        didSet { defaults.set(nightMode.rawValue, forKey: "carcast.display.night_mode") }
    }

    @Published public var playSoundLocally: Bool {
        didSet { defaults.set(playSoundLocally, forKey: "carcast.audio.play_local") }
    }

    @Published public var instrumentClusterMode: ClusterContentMode {
        didSet { defaults.set(instrumentClusterMode.rawValue, forKey: "carcast.cluster.mode") }
    }

    @Published public var instrumentClusterSize: ClusterSize {
        didSet { defaults.set(instrumentClusterSize.rawValue, forKey: "carcast.cluster.size") }
    }

    @Published public var showClusterETA: Bool {
        didSet { defaults.set(showClusterETA, forKey: "carcast.cluster.show_eta") }
    }

    @Published public var carPlayUltraEnabled: Bool {
        didSet { defaults.set(carPlayUltraEnabled, forKey: "carcast.cluster.ultra_enabled") }
    }

    @Published public var wifiSSID: String {
        didSet {
            defaults.set(wifiSSID, forKey: "carcast.wifi.ssid")
            if !wifiSSID.isEmpty, let saved = WiFiNetworkService.shared.getPassword(for: wifiSSID), !saved.isEmpty {
                wifiPassphrase = saved
            }
        }
    }

    @Published public var wifiPassphrase: String {
        didSet {
            defaults.set(wifiPassphrase, forKey: "carcast.wifi.passphrase")
            if !wifiSSID.isEmpty && !wifiPassphrase.isEmpty {
                WiFiNetworkService.shared.savePassword(wifiPassphrase, for: wifiSSID)
            }
        }
    }

    @Published public var wifiChannel: Int {
        didSet { defaults.set(wifiChannel, forKey: "carcast.wifi.channel") }
    }

    public var deviceIdUInt64: UInt64 {
        let clean = deviceId.replacingOccurrences(of: ":", with: "")
        return UInt64(clean, radix: 16) ?? 170054366648252
    }

    private init() {
        let persistentDeviceId: String
        if let savedId = defaults.string(forKey: "carcast.device.id"), !savedId.isEmpty, savedId.hasSuffix("57:BC") {
            persistentDeviceId = savedId
        } else {
            persistentDeviceId = "9A:A9:72:31:57:BC"
            defaults.set(persistentDeviceId, forKey: "carcast.device.id")
            defaults.set(persistentDeviceId, forKey: "deviceID")
        }
        self.deviceId = persistentDeviceId

        // Canonical car name is always derived from the persistent deviceId
        let cleanId = persistentDeviceId.replacingOccurrences(of: ":", with: "")
        let suffix = cleanId.suffix(4).uppercased()
        let canonicalName = "CarCast-\(suffix)"
        self.carName = canonicalName
        defaults.set(canonicalName, forKey: "carcast.car.name")

        self.selectedBrandId = defaults.string(forKey: "carcast.car.brand_id") ?? "lexus"
        self.customLogoLabel = defaults.string(forKey: "carcast.car.logo_label") ?? ""

        if let dpStr = defaults.string(forKey: "carcast.car.driving_pos"), let dp = DrivingPosition(rawValue: dpStr) {
            self.drivingPosition = dp
        } else {
            self.drivingPosition = .leftHandDrive
        }

        if let dpStr = defaults.string(forKey: "carcast.display.preset"), let dp = DisplayPreset(rawValue: dpStr) {
            self.displayPreset = dp
        } else {
            self.displayPreset = .fitScreen
        }

        self.isPortraitAllowed = defaults.object(forKey: "carcast.display.portrait") as? Bool ?? false
        self.avoidNotch = defaults.object(forKey: "carcast.display.avoid_notch") as? Bool ?? true
        self.showTouches = defaults.object(forKey: "carcast.display.show_touches") as? Bool ?? false
        self.videoPlaybackAllowed = defaults.object(forKey: "carcast.display.video_playback") as? Bool ?? true

        if let nmStr = defaults.string(forKey: "carcast.display.night_mode"), let nm = NightModeSetting(rawValue: nmStr) {
            self.nightMode = nm
        } else {
            self.nightMode = .auto
        }

        self.playSoundLocally = defaults.object(forKey: "carcast.audio.play_local") as? Bool ?? true

        if let cmStr = defaults.string(forKey: "carcast.cluster.mode"), let cm = ClusterContentMode(rawValue: cmStr) {
            self.instrumentClusterMode = cm
        } else {
            self.instrumentClusterMode = .map
        }

        if let csStr = defaults.string(forKey: "carcast.cluster.size"), let cs = ClusterSize(rawValue: csStr) {
            self.instrumentClusterSize = cs
        } else {
            self.instrumentClusterSize = .medium
        }

        self.showClusterETA = defaults.object(forKey: "carcast.cluster.show_eta") as? Bool ?? true
        self.carPlayUltraEnabled = defaults.object(forKey: "carcast.cluster.ultra_enabled") as? Bool ?? true

        let savedSSID = defaults.string(forKey: "carcast.wifi.ssid") ?? ""
        self.wifiSSID = savedSSID
        if !savedSSID.isEmpty, let savedPwd = WiFiNetworkService.shared.getPassword(for: savedSSID), !savedPwd.isEmpty {
            self.wifiPassphrase = savedPwd
        } else {
            self.wifiPassphrase = defaults.string(forKey: "carcast.wifi.passphrase") ?? ""
        }
        self.wifiChannel = defaults.object(forKey: "carcast.wifi.channel") as? Int ?? 6
    }

    public func resetToDefaults() {
        let cleanId = deviceId.replacingOccurrences(of: ":", with: "")
        let suffix = cleanId.suffix(4).uppercased()
        carName = "DrivingMode-\(suffix)"
        selectedBrandId = "lexus"
        customLogoLabel = ""
        drivingPosition = .leftHandDrive
        displayPreset = .fitScreen
        isPortraitAllowed = false
        avoidNotch = true
        showTouches = false
        videoPlaybackAllowed = true
        nightMode = .auto
        playSoundLocally = true
        instrumentClusterMode = .map
        instrumentClusterSize = .medium
        showClusterETA = true
        carPlayUltraEnabled = true
        wifiSSID = ""
        wifiPassphrase = ""
        wifiChannel = 6
    }
}
