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

public enum AudioRoutingMode: String, Codable, CaseIterable, Sendable {
    case airPlayInBand = "in_band"
    case carBluetoothPassthrough = "bluetooth_passthrough"

    public var title: String {
        switch self {
        case .airPlayInBand: return "In-Band AirPlay (Speaker / AUX)"
        case .carBluetoothPassthrough: return "Car Bluetooth Passthrough"
        }
    }

    public var subtitle: String {
        switch self {
        case .airPlayInBand: return "Receiver plays media & Siri with auto-ducking"
        case .carBluetoothPassthrough: return "iPhone streams audio to car Bluetooth stereo"
        }
    }
}

@MainActor
public final class DrivingModeConfig: ObservableObject {
    public static let shared = DrivingModeConfig()

    private let defaults = UserDefaults.standard

    @Published public var carName: String {
        didSet { defaults.set(carName, forKey: "drivingmode.car.name") }
    }

    public let deviceId: String

    @Published public var selectedBrandId: String {
        didSet { defaults.set(selectedBrandId, forKey: "drivingmode.car.brand_id") }
    }

    @Published public var customLogoLabel: String {
        didSet { defaults.set(customLogoLabel, forKey: "drivingmode.car.logo_label") }
    }

    @Published public var drivingPosition: DrivingPosition {
        didSet { defaults.set(drivingPosition.rawValue, forKey: "drivingmode.car.driving_pos") }
    }

    @Published public var displayPreset: DisplayPreset {
        didSet { defaults.set(displayPreset.rawValue, forKey: "drivingmode.display.preset") }
    }

    @Published public var isPortraitAllowed: Bool {
        didSet { defaults.set(isPortraitAllowed, forKey: "drivingmode.display.portrait") }
    }

    @Published public var avoidNotch: Bool {
        didSet { defaults.set(avoidNotch, forKey: "drivingmode.display.avoid_notch") }
    }

    @Published public var showTouches: Bool {
        didSet { defaults.set(showTouches, forKey: "drivingmode.display.show_touches") }
    }

    @Published public var videoPlaybackAllowed: Bool {
        didSet { defaults.set(videoPlaybackAllowed, forKey: "drivingmode.display.video_playback") }
    }

    @Published public var nightMode: NightModeSetting {
        didSet { defaults.set(nightMode.rawValue, forKey: "drivingmode.display.night_mode") }
    }

    @Published public var playSoundLocally: Bool {
        didSet { defaults.set(playSoundLocally, forKey: "drivingmode.audio.play_local") }
    }

    @Published public var audioRoutingMode: AudioRoutingMode {
        didSet {
            defaults.set(audioRoutingMode.rawValue, forKey: "drivingmode.audio.routing")
            AirPlayAudioReceiver.shared.isPassthroughMode = (audioRoutingMode == .carBluetoothPassthrough)
        }
    }

    @Published public var instrumentClusterMode: ClusterContentMode {
        didSet { defaults.set(instrumentClusterMode.rawValue, forKey: "drivingmode.cluster.mode") }
    }

    @Published public var instrumentClusterSize: ClusterSize {
        didSet { defaults.set(instrumentClusterSize.rawValue, forKey: "drivingmode.cluster.size") }
    }

    @Published public var showClusterETA: Bool {
        didSet { defaults.set(showClusterETA, forKey: "drivingmode.cluster.show_eta") }
    }

    @Published public var carPlayUltraEnabled: Bool {
        didSet { defaults.set(carPlayUltraEnabled, forKey: "drivingmode.cluster.ultra_enabled") }
    }

    @Published public var wifiSSID: String {
        didSet {
            defaults.set(wifiSSID, forKey: "drivingmode.wifi.ssid")
            if !wifiSSID.isEmpty, let saved = WiFiNetworkService.shared.getPassword(for: wifiSSID), !saved.isEmpty {
                wifiPassphrase = saved
            }
        }
    }

    @Published public var wifiPassphrase: String {
        didSet {
            defaults.set(wifiPassphrase, forKey: "drivingmode.wifi.passphrase")
            if !wifiSSID.isEmpty && !wifiPassphrase.isEmpty {
                WiFiNetworkService.shared.savePassword(wifiPassphrase, for: wifiSSID)
            }
        }
    }

    @Published public var wifiChannel: Int {
        didSet { defaults.set(wifiChannel, forKey: "drivingmode.wifi.channel") }
    }

    @Published public var isDashcamEnabled: Bool {
        didSet { defaults.set(isDashcamEnabled, forKey: "drivingmode.dashcam.enabled") }
    }

    @Published public var isDashcamAudioEnabled: Bool {
        didSet { defaults.set(isDashcamAudioEnabled, forKey: "drivingmode.dashcam.audio_enabled") }
    }

    @Published public var dashcamStorageLimitMB: Int {
        didSet { defaults.set(dashcamStorageLimitMB, forKey: "drivingmode.dashcam.storage_limit_mb") }
    }

    @Published public var impactSensitivityG: Double {
        didSet { defaults.set(impactSensitivityG, forKey: "drivingmode.dashcam.impact_sensitivity_g") }
    }

    public var deviceIdUInt64: UInt64 {
        let clean = deviceId.replacingOccurrences(of: ":", with: "")
        return UInt64(clean, radix: 16) ?? 0x02554E445256
    }

    private init() {
        // Unique persistent MAC address under Unordinary Labs OUI prefix (02:55:4E)
        let resolvedDeviceId: String
        if let savedId = defaults.string(forKey: "drivingmode.device.id"),
           !savedId.isEmpty,
           savedId != "9A:A9:72:31:CA:9A" {
            resolvedDeviceId = savedId
        } else {
            var randomBytes = [UInt8](repeating: 0, count: 3)
            _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            resolvedDeviceId = String(format: "02:55:4E:%02X:%02X:%02X", randomBytes[0], randomBytes[1], randomBytes[2])
            defaults.set(resolvedDeviceId, forKey: "drivingmode.device.id")
            defaults.set(resolvedDeviceId, forKey: "deviceID")
        }
        self.deviceId = resolvedDeviceId

        // Canonical DrivingMode receiver name
        if let savedName = defaults.string(forKey: "drivingmode.car.name"),
           !savedName.isEmpty,
           !savedName.localizedCaseInsensitiveContains("carcast") {
            self.carName = savedName
        } else {
            let canonicalName = "DrivingMode"
            self.carName = canonicalName
            defaults.set(canonicalName, forKey: "drivingmode.car.name")
        }

        self.selectedBrandId = defaults.string(forKey: "drivingmode.car.brand_id") ?? "lexus"
        self.customLogoLabel = defaults.string(forKey: "drivingmode.car.logo_label") ?? ""

        if let dpStr = defaults.string(forKey: "drivingmode.car.driving_pos"),
           let dp = DrivingPosition(rawValue: dpStr) {
            self.drivingPosition = dp
        } else {
            self.drivingPosition = .leftHandDrive
        }

        if let dpStr = defaults.string(forKey: "drivingmode.display.preset"),
           let dp = DisplayPreset(rawValue: dpStr) {
            self.displayPreset = dp
        } else {
            self.displayPreset = .fitScreen
        }

        self.isPortraitAllowed = defaults.object(forKey: "drivingmode.display.portrait") as? Bool ?? false
        self.avoidNotch = defaults.object(forKey: "drivingmode.display.avoid_notch") as? Bool ?? false
        self.showTouches = defaults.object(forKey: "drivingmode.display.show_touches") as? Bool ?? false
        self.videoPlaybackAllowed = defaults.object(forKey: "drivingmode.display.video_playback") as? Bool ?? true

        if let nmStr = defaults.string(forKey: "drivingmode.display.night_mode"),
           let nm = NightModeSetting(rawValue: nmStr) {
            self.nightMode = nm
        } else {
            self.nightMode = .auto
        }

        self.playSoundLocally = defaults.object(forKey: "drivingmode.audio.play_local") as? Bool ?? true

        let resolvedAudioMode: AudioRoutingMode
        if let arStr = defaults.string(forKey: "drivingmode.audio.routing"),
           let ar = AudioRoutingMode(rawValue: arStr) {
            resolvedAudioMode = ar
        } else {
            resolvedAudioMode = .airPlayInBand
        }
        self.audioRoutingMode = resolvedAudioMode

        if let cmStr = defaults.string(forKey: "drivingmode.cluster.mode"),
           let cm = ClusterContentMode(rawValue: cmStr) {
            self.instrumentClusterMode = cm
        } else {
            self.instrumentClusterMode = .map
        }

        if let csStr = defaults.string(forKey: "drivingmode.cluster.size"),
           let cs = ClusterSize(rawValue: csStr) {
            self.instrumentClusterSize = cs
        } else {
            self.instrumentClusterSize = .medium
        }

        self.showClusterETA = defaults.object(forKey: "drivingmode.cluster.show_eta") as? Bool ?? true
        self.carPlayUltraEnabled = defaults.object(forKey: "drivingmode.cluster.ultra_enabled") as? Bool ?? true

        let savedSSID = defaults.string(forKey: "drivingmode.wifi.ssid") ?? ""
        self.wifiSSID = savedSSID
        if !savedSSID.isEmpty, let savedPwd = WiFiNetworkService.shared.getPassword(for: savedSSID), !savedPwd.isEmpty {
            self.wifiPassphrase = savedPwd
        } else {
            self.wifiPassphrase = defaults.string(forKey: "drivingmode.wifi.passphrase") ?? ""
        }
        self.wifiChannel = defaults.object(forKey: "drivingmode.wifi.channel") as? Int ?? 6

        self.isDashcamEnabled = defaults.bool(forKey: "drivingmode.dashcam.enabled")
        self.isDashcamAudioEnabled = defaults.bool(forKey: "drivingmode.dashcam.audio_enabled")
        let storedLimit = defaults.integer(forKey: "drivingmode.dashcam.storage_limit_mb")
        self.dashcamStorageLimitMB = storedLimit > 0 ? storedLimit : 3072
        let storedSens = defaults.double(forKey: "drivingmode.dashcam.impact_sensitivity_g")
        self.impactSensitivityG = storedSens > 0 ? storedSens : 2.5

        AirPlayAudioReceiver.shared.isPassthroughMode = (resolvedAudioMode == .carBluetoothPassthrough)
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
        avoidNotch = false
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
        isDashcamEnabled = false
        isDashcamAudioEnabled = false
        dashcamStorageLimitMB = 3072
        impactSensitivityG = 2.5
    }
}
