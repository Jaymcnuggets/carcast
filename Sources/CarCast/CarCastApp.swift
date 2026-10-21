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

    var body: some Scene {
        WindowGroup {
            DashboardHomeView()
                .preferredColorScheme(.dark)
        }
    }
}
