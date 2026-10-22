//
//  WiFiNetworkService.swift
//  CarCast
//
//  Real iOS Wi-Fi Network Detection and Keychain Password Management:
//  - Queries current connected Wi-Fi SSID via NEHotspotNetwork and CNCopyCurrentNetworkInfo
//  - Requests Location permission required by iOS 14+ to read Wi-Fi network SSID
//  - Monitors Wi-Fi interface transitions via NWPathMonitor
//  - Stores Wi-Fi passphrases per SSID in Apple Keychain
//

import Foundation
import CoreLocation
import Network
import Security

#if canImport(NetworkExtension)
import NetworkExtension
#endif

#if canImport(SystemConfiguration.CaptiveNetwork)
import SystemConfiguration.CaptiveNetwork
#endif

public final class WiFiNetworkService: NSObject, ObservableObject, CLLocationManagerDelegate, @unchecked Sendable {
    public static let shared = WiFiNetworkService()

    private let locationManager = CLLocationManager()
    private let pathMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let monitorQueue = DispatchQueue(label: "dev.unordinarylabs.CarCast.WiFiMonitor", qos: .utility)

    @Published public var currentSSID: String? = nil
    @Published public var isConnectedToWiFi: Bool = false
    @Published public var isLocationAuthorized: Bool = false

    private var pendingSSIDCompletions: [(String?) -> Void] = []
    private let lock = NSLock()

    public override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers

        startNetworkMonitoring()
        checkLocationAuthorization()
        refreshCurrentSSID()
    }

    // MARK: - Monitoring

    private func startNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let isWiFi = path.status == .satisfied && path.usesInterfaceType(.wifi)
            Task { @MainActor in
                self.isConnectedToWiFi = isWiFi
                if isWiFi {
                    self.refreshCurrentSSID()
                } else {
                    self.currentSSID = nil
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    // MARK: - Location Authorization for Wi-Fi SSID Access

    public func checkLocationAuthorization() {
        #if os(iOS)
        let status = locationManager.authorizationStatus
        let authorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
        Task { @MainActor in
            self.isLocationAuthorized = authorized
        }
        #else
        Task { @MainActor in
            self.isLocationAuthorized = true
        }
        #endif
    }

    public func requestAuthorizationAndFetchSSID(completion: @escaping (String?) -> Void) {
        #if os(iOS)
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            lock.lock()
            pendingSSIDCompletions.append(completion)
            lock.unlock()
            DispatchQueue.main.async {
                self.locationManager.requestWhenInUseAuthorization()
            }
            return
        }
        #endif
        fetchCurrentSSID(completion: completion)
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkLocationAuthorization()
        refreshCurrentSSID { [weak self] ssid in
            guard let self = self else { return }
            self.lock.lock()
            let completions = self.pendingSSIDCompletions
            self.pendingSSIDCompletions.removeAll()
            self.lock.unlock()

            for completion in completions {
                completion(ssid)
            }
        }
    }

    // MARK: - SSID Fetching

    public func refreshCurrentSSID(completion: ((String?) -> Void)? = nil) {
        fetchCurrentSSID(completion: completion)
    }

    public func fetchCurrentSSID(completion: ((String?) -> Void)? = nil) {
        #if targetEnvironment(simulator)
        let simSSID = "Simulator Wi-Fi"
        Task { @MainActor in
            self.currentSSID = simSSID
            self.syncWithConfig(ssid: simSSID)
            completion?(simSSID)
        }
        #else

        #if os(iOS)
        // 1. Try NEHotspotNetwork (iOS 14+)
        NEHotspotNetwork.fetchCurrent { [weak self] hotspotNetwork in
            guard let self = self else { return }
            if let ssid = hotspotNetwork?.ssid, !ssid.isEmpty {
                Task { @MainActor in
                    self.currentSSID = ssid
                    self.syncWithConfig(ssid: ssid)
                    completion?(ssid)
                }
                return
            }

            // 2. Fallback to CNCopyCurrentNetworkInfo
            if let fallbackSSID = self.readCaptiveNetworkSSID(), !fallbackSSID.isEmpty {
                Task { @MainActor in
                    self.currentSSID = fallbackSSID
                    self.syncWithConfig(ssid: fallbackSSID)
                    completion?(fallbackSSID)
                }
                return
            }

            Task { @MainActor in
                completion?(self.currentSSID)
            }
        }
        #else
        Task { @MainActor in
            completion?(nil)
        }
        #endif

        #endif
    }

    private func readCaptiveNetworkSSID() -> String? {
        #if os(iOS)
        guard let interfaces = CNCopySupportedInterfaces() as? [String] else { return nil }
        for interface in interfaces {
            if let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: Any],
               let ssid = info[kCNNetworkInfoKeySSID as String] as? String,
               !ssid.isEmpty {
                return ssid
            }
        }
        #endif
        return nil
    }

    @MainActor
    private func syncWithConfig(ssid: String) {
        let config = CarCastConfig.shared
        if config.wifiSSID.isEmpty || config.wifiSSID == "CarCast-WiFi" || config.wifiSSID != ssid {
            config.wifiSSID = ssid
            if let savedPassword = getPassword(for: ssid), !savedPassword.isEmpty {
                config.wifiPassphrase = savedPassword
            } else {
                config.wifiPassphrase = ""
            }
        }
    }

    // MARK: - Keychain Password Management

    public func getPassword(for ssid: String) -> String? {
        guard !ssid.isEmpty else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: ssid,
            kSecAttrService as String: "dev.unordinarylabs.CarCast.WiFi",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let pwd = String(data: data, encoding: .utf8) {
            return pwd
        }
        // Fallback to UserDefaults cache
        return UserDefaults.standard.string(forKey: "carcast.wifi.pwd.\(ssid)")
    }

    public func savePassword(_ password: String, for ssid: String) {
        guard !ssid.isEmpty else { return }
        UserDefaults.standard.set(password, forKey: "carcast.wifi.pwd.\(ssid)")

        guard let data = password.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: ssid,
            kSecAttrService as String: "dev.unordinarylabs.CarCast.WiFi"
        ]

        SecItemDelete(query as CFDictionary)

        if !password.isEmpty {
            var attributes = query
            attributes[kSecValueData as String] = data
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    public func forgetPassword(for ssid: String) {
        guard !ssid.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: "carcast.wifi.pwd.\(ssid)")
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: ssid,
            kSecAttrService as String: "dev.unordinarylabs.CarCast.WiFi"
        ]
        SecItemDelete(query as CFDictionary)
    }
}
