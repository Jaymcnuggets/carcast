//
//  DashboardHomeView.swift
//  CarCast
//
//  Authentic CarCast Home View for iOS/iPadOS matching 1:1 ground-truth layout.
//

import SwiftUI

public struct DashboardHomeView: View {
    @ObservedObject var manager = CarPlayManager.shared
    @ObservedObject var config = CarCastConfig.shared

    @State private var showingSettings: Bool = false
    @State private var showingConnect: Bool = false
    @State private var showingActiveCarPlay: Bool = false
    @State private var showingPasswordAlert: Bool = false
    @State private var enteredPassword: String = ""

    public init() {}

    private var statusText: String {
        switch manager.state {
        case .idle:
            return "Waiting for iPhone"
        case .starting:
            return "Starting…"
        case .waitingForPhone:
            return "Waiting for iPhone"
        case .connecting:
            return "Connecting…"
        case .streaming:
            return "CarPlay is connected"
        case .error:
            return "CarPlay didn't start"
        }
    }

    private var statusColor: Color {
        switch manager.state {
        case .streaming:
            return Color(white: 0.85)
        case .error:
            return Color(red: 1.0, green: 0.4, blue: 0.4)
        default:
            return Color(white: 0.6)
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                // Pure OLED Black Background matching authentic screenshot
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 40)

                    // Central CarCast Brand Icon
                    carCastAppIcon
                        .frame(width: 96, height: 96)
                        .padding(.bottom, 22)

                    // Car Name Title: e.g. "CarCast-D3F3"
                    Text(config.carName)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.bottom, 8)

                    // Subtitle Status: "Waiting for iPhone"
                    Text(statusText)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(statusColor)

                    Spacer(minLength: 60)

                    // Bottom Navigation Buttons matching authentic screenshot
                    bottomButtonBar
                        .padding(.horizontal, 32)
                        .padding(.bottom, 34)
                }
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            #if os(iOS)
            .fullScreenCover(isPresented: $showingActiveCarPlay) {
                CarPlayActiveScreenView()
            }
            #else
            .sheet(isPresented: $showingActiveCarPlay) {
                CarPlayActiveScreenView()
            }
            #endif
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingConnect) {
                ConnectRemoteView()
            }
            .alert("Wi-Fi Password", isPresented: $showingPasswordAlert) {
                let networkName = config.wifiSSID.isEmpty ? "your Wi-Fi" : config.wifiSSID
                SecureField("Password for \(networkName)", text: $enteredPassword)
                Button("Save and Connect") {
                    config.wifiPassphrase = enteredPassword
                    if !config.wifiSSID.isEmpty {
                        WiFiNetworkService.shared.savePassword(enteredPassword, for: config.wifiSSID)
                    }
                    startThisiPhoneSession()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                let networkName = config.wifiSSID.isEmpty ? "your Wi-Fi network" : "\"\(config.wifiSSID)\""
                Text("iOS requires the network password to register this car for CarPlay on \(networkName). It is stored securely on this iPhone.")
            }
            .onChange(of: manager.isStreamingActive) { active in
                showingActiveCarPlay = active
            }
            .onAppear {
                WiFiNetworkService.shared.fetchCurrentSSID { ssid in
                    if let ssid = ssid, !ssid.isEmpty {
                        config.wifiSSID = ssid
                    }
                }
            }
        }
    }

    // MARK: - App Icon View

    @ViewBuilder
    private var carCastAppIcon: some View {
        #if canImport(UIKit)
        if let icon = UIImage(named: "AppIcon") ?? UIImage(contentsOfFile: Bundle.main.path(forResource: "AppIcon", ofType: "png") ?? "") {
            Image(uiImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color.purple.opacity(0.3), radius: 16, x: 0, y: 8)
        } else {
            fallbackAppIcon
        }
        #else
        fallbackAppIcon
        #endif
    }

    private var fallbackAppIcon: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.38, green: 0.45, blue: 0.96),
                    Color(red: 0.65, green: 0.40, blue: 0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white, lineWidth: 3.5)
                        .frame(width: 52, height: 32)

                    HStack(spacing: 8) {
                        Image(systemName: "wifi")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                // Monitor Stand Base
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 8, height: 6)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 28, height: 3)
            }
        }
        .shadow(color: Color.purple.opacity(0.35), radius: 16, x: 0, y: 8)
    }

    // MARK: - Bottom Button Bar

    private var bottomButtonBar: some View {
        HStack(spacing: 0) {
            // Settings Button (Always on Left)
            Button {
                showingSettings = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .medium))
                    Text("Settings")
                        .font(.system(size: 17, weight: .regular))
                }
                .foregroundColor(Color(red: 0.0, green: 0.50, blue: 1.0))
            }

            Spacer()

            if manager.state == .streaming {
                // If CarPlay is connected: "Back to CarPlay" and "Stop"
                Button {
                    showingActiveCarPlay = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.tv.fill")
                            .font(.system(size: 18, weight: .medium))
                        Text("Back to CarPlay")
                            .font(.system(size: 17, weight: .medium))
                    }
                    .foregroundColor(Color(red: 0.0, green: 0.50, blue: 1.0))
                }

                Spacer()

                Button {
                    stopSession()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Stop")
                            .font(.system(size: 17, weight: .medium))
                    }
                    .foregroundColor(Color(red: 1.0, green: 0.27, blue: 0.23))
                }
            } else if manager.state == .starting || manager.state == .waitingForPhone || manager.state == .connecting {
                // While receiver active: show "Stop" button in red
                Button {
                    stopSession()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Stop")
                            .font(.system(size: 17, weight: .medium))
                    }
                    .foregroundColor(Color(red: 1.0, green: 0.27, blue: 0.23))
                }
            } else {
                // Standard Idle State matching authentic screenshot: "Connect" and "This iPhone"
                Button {
                    showingConnect = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 18, weight: .medium))
                        Text("Connect")
                            .font(.system(size: 17, weight: .regular))
                    }
                    .foregroundColor(Color(red: 0.0, green: 0.50, blue: 1.0))
                }

                Spacer()

                Button {
                    handleThisiPhoneTap()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "iphone")
                            .font(.system(size: 18, weight: .medium))
                        Text("This iPhone")
                            .font(.system(size: 17, weight: .regular))
                    }
                    .foregroundColor(Color(red: 0.0, green: 0.50, blue: 1.0))
                }
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.8).onEnded { _ in
                    WiFiNetworkService.shared.requestAuthorizationAndFetchSSID { detectedSSID in
                        if let ssid = detectedSSID, !ssid.isEmpty {
                            config.wifiSSID = ssid
                        }
                        enteredPassword = config.wifiPassphrase
                        showingPasswordAlert = true
                    }
                })
            }
        }
    }

    // MARK: - Actions

    private func handleThisiPhoneTap() {
        WiFiNetworkService.shared.requestAuthorizationAndFetchSSID { detectedSSID in
            if let ssid = detectedSSID, !ssid.isEmpty {
                config.wifiSSID = ssid
                if let savedPwd = WiFiNetworkService.shared.getPassword(for: ssid), !savedPwd.isEmpty {
                    config.wifiPassphrase = savedPwd
                }
            }

            if config.wifiPassphrase.isEmpty {
                enteredPassword = ""
                showingPasswordAlert = true
            } else {
                startThisiPhoneSession()
            }
        }
    }

    private func startThisiPhoneSession() {
        manager.startReceiver()
    }

    private func stopSession() {
        showingActiveCarPlay = false
        manager.stopReceiver()
    }
}
