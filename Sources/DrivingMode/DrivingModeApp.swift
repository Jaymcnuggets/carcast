//
//  DrivingModeApp.swift
//  DrivingMode
//
//  Main application entry point for DrivingMode multiplatform iOS/iPadOS head unit receiver.
//

import SwiftUI
#if canImport(UIKit)
import UIKit

public final class AppDelegate: NSObject, UIApplicationDelegate {
    public func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .all
    }
}
#endif

#if !SWIFT_PACKAGE
@main
#endif
struct DrivingModeApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @StateObject private var manager = CarPlayManager.shared
    @StateObject private var config = DrivingModeConfig.shared
    @StateObject private var telemetry = VehicleTelemetry.shared

    init() {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
    }

    private var initialScreen: String? {
        if let env = ProcessInfo.processInfo.environment["DRIVINGMODE_SCREEN"], !env.isEmpty {
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
            .onAppear {
                #if canImport(UIKit)
                DispatchQueue.main.async {
                    if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene ?? UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .all)) { error in
                            NSLog("[DrivingMode] requestGeometryUpdate error: %@", error.localizedDescription)
                        }
                    }
                }
                #endif
            }
        }
    }
}
