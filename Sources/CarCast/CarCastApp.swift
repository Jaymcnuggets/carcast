//
//  CarCastApp.swift
//  CarCast
//
//  Main application entry point for CarCast multiplatform iOS/iPadOS head unit receiver.
//

import SwiftUI

#if !SWIFT_PACKAGE
@main
#endif
struct CarCastApp: App {
    @StateObject private var manager = CarPlayManager.shared
    @StateObject private var config = CarCastConfig.shared
    @StateObject private var telemetry = VehicleTelemetry.shared

    private var initialScreen: String? {
        if let env = ProcessInfo.processInfo.environment["CARCAST_SCREEN"], !env.isEmpty {
            return env.lowercased()
        }
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "--screen"), idx + 1 < args.count {
            return args[idx + 1].lowercased()
        }
        return nil
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch initialScreen {
                case "cluster":
                    CarPlayUltraClusterView()
                case "active":
                    CarPlayActiveScreenView()
                case "inspector":
                    ProtocolInspectorView()
                case "settings":
                    SettingsView()
                case "connect":
                    ConnectRemoteView()
                case "guide":
                    PairingGuideView()
                default:
                    DashboardHomeView()
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
