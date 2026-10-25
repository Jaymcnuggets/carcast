//
//  DashboardHomeView.swift
//  DrivingMode
//
//  Automotive-grade cockpit dashboard for iOS, iPadOS, and CarPlay receivers:
//  Featuring panoramic hero launchpads for Apple CarPlay, Smart Dashcam & Sentry,
//  live vehicle telemetry, and quick audio/display routing controls.
//

import SwiftUI
import Combine

public struct DashboardHomeView: View {
    @ObservedObject var manager = CarPlayManager.shared
    @ObservedObject var config = DrivingModeConfig.shared
    @ObservedObject var dashcam = DashcamManager.shared

    @State private var showingSettings: Bool = false
    @State private var showingConnect: Bool = false
    @State private var showingPairingGuide: Bool = false
    @State private var showingActiveCarPlay: Bool = false
    @State private var showingPasswordAlert: Bool = false
    @State private var enteredPassword: String = ""
    @State private var hasPerformedInitialAutoStart: Bool = false

    public init() {}

    private var statusText: String {
        switch manager.state {
        case .idle:
            return "Ready to Connect"
        case .starting:
            return "Starting Receiver…"
        case .waitingForPhone:
            return "Waiting for iPhone"
        case .connecting:
            return "Connecting…"
        case .streaming:
            return "CarPlay Connected"
        case .error:
            return "CarPlay Error"
        }
    }

    private var statusColor: Color {
        switch manager.state {
        case .streaming:
            return Color.green
        case .error:
            return Color.red
        case .starting, .waitingForPhone, .connecting:
            return Color.yellow
        case .idle:
            return Color(red: 0.2, green: 0.6, blue: 1.0)
        }
    }

    public var body: some View {
        ZStack {
            if manager.isStreamingActive {
                CarPlayActiveScreenView(onReturnToMenu: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingActiveCarPlay = false
                    }
                })
                .opacity(showingActiveCarPlay ? 1.0 : 0.0)
                .allowsHitTesting(showingActiveCarPlay)
            }

            if !showingActiveCarPlay || !manager.isStreamingActive {
                dashboardView
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea(.all)
        .onChange(of: manager.isStreamingActive) { _, active in
            if active {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingActiveCarPlay = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .returnToMainMenu)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                showingActiveCarPlay = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .returnToCarPlay)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                showingActiveCarPlay = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleDashcam)) { _ in
            if dashcam.isRecording {
                dashcam.stopRecording()
                config.isDashcamEnabled = false
            } else {
                config.isDashcamEnabled = true
                dashcam.startRecording(withAudio: config.isDashcamAudioEnabled)
            }
        }
    }

    // MARK: - Main Cockpit Dashboard View

    private var dashboardView: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    // Deep OLED obsidian background with subtle cockpit illumination
                    Color.black.ignoresSafeArea()

                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.06, green: 0.14, blue: 0.32).opacity(0.35),
                            Color.black
                        ]),
                        center: .top,
                        startRadius: 40,
                        endRadius: max(geo.size.width, 700)
                    )
                    .ignoresSafeArea()

                    let isCompact = geo.size.width < 520
                    let hLeading = isCompact ? max(geo.safeAreaInsets.leading, 16) : max(geo.safeAreaInsets.leading, 32)
                    let hTrailing = isCompact ? max(geo.safeAreaInsets.trailing, 16) : max(geo.safeAreaInsets.trailing, 32)

                    VStack(spacing: 0) {
                        // Top Cockpit Status Bar
                        cockpitHeaderBar(width: geo.size.width)
                            .padding(.leading, hLeading)
                            .padding(.trailing, hTrailing)
                            .padding(.top, max(geo.safeAreaInsets.top, 12))
                            .padding(.bottom, 12)

                        // Main Cockpit Center Stage
                        ScrollView(.vertical, showsIndicators: false) {
                            cockpitCardsLayout(width: geo.size.width)
                                .padding(.leading, hLeading)
                                .padding(.trailing, hTrailing)
                                .padding(.vertical, isCompact ? 4 : 6)
                        }

                        // Bottom Navigation Action Bar
                        cockpitBottomBar(width: geo.size.width)
                            .padding(.leading, hLeading)
                            .padding(.trailing, hTrailing)
                            .padding(.bottom, max(geo.safeAreaInsets.bottom, 12))
                    }

                    // Floating live Dashcam viewfinder overlay
                    DashcamPiPOverlay()
                }
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingConnect) {
                ConnectRemoteView()
            }
            .sheet(isPresented: $showingPairingGuide) {
                PairingGuideView()
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
            .onAppear {
                // Pre-warm camera hardware capture pipeline for zero-latency dashcam start on device
                #if os(iOS) && !targetEnvironment(simulator)
                dashcam.prewarmPipeline(withAudio: config.isDashcamAudioEnabled)
                #endif

                guard !hasPerformedInitialAutoStart else { return }
                hasPerformedInitialAutoStart = true

                #if targetEnvironment(simulator)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    manager.startLocalSimulation()
                }
                #else
                WiFiNetworkService.shared.fetchCurrentSSID { ssid in
                    if let ssid = ssid, !ssid.isEmpty {
                        config.wifiSSID = ssid
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    manager.stopReceiver()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        startThisiPhoneSession()
                    }
                }
                #endif
            }
        }
    }

    // MARK: - Cockpit Header Bar

    private func cockpitHeaderBar(width: CGFloat) -> some View {
        let isCompact = width < 520
        return HStack(alignment: .center, spacing: isCompact ? 8 : 12) {
            // Vehicle Brand Emblem & Title
            HStack(spacing: isCompact ? 6 : 8) {
                ZStack {
                    Circle()
                        .fill(Color(white: 0.15))
                        .frame(width: isCompact ? 32 : 36, height: isCompact ? 32 : 36)
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))

                    Image(systemName: "car.side.fill")
                        .font(.system(size: isCompact ? 14 : 16, weight: .bold))
                        .foregroundColor(.cyan)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(config.carName.uppercased())
                        .font(.system(size: isCompact ? 11 : 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                        Text(width >= 560 ? "COCKPIT ACTIVE" : "ACTIVE")
                            .font(.system(size: isCompact ? 8 : 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan.opacity(0.9))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Dynamic Central / Inline Status Pill
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)

                Text(statusText.uppercased())
                    .font(.system(size: isCompact ? 9 : 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if width >= 640 && manager.state == .streaming {
                    Text("•")
                        .foregroundColor(.white.opacity(0.4))
                    Text("\(manager.totalFramesReceived) frames")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, isCompact ? 9 : 12)
            .padding(.vertical, isCompact ? 5 : 6)
            .background(Color(white: 0.12).opacity(0.85))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .lineLimit(1)

            if !isCompact {
                Spacer()
            }

            // Right System Indicators Cluster
            HStack(spacing: 8) {
                if width >= 560 {
                    // Wi-Fi Badge
                    HStack(spacing: 5) {
                        Image(systemName: "wifi")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                        Text(config.wifiSSID.isEmpty ? "Direct" : config.wifiSSID)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }

                // Live Clock
                CockpitClockView()
            }
        }
    }

    // MARK: - Cockpit Cards Layout (Panoramic / Adaptive)

    @ViewBuilder
    private func cockpitCardsLayout(width: CGFloat) -> some View {
        if width >= 1150 {
            // Wide Panoramic 3-Card Deck (Desktop, Ultra-wide display >= 1150)
            HStack(alignment: .top, spacing: 14) {
                carPlayHeroCard(width: width)
                    .frame(maxWidth: .infinity)
                dashcamControlCard(width: width)
                    .frame(maxWidth: .infinity)
                cockpitControlsCard(width: width)
                    .frame(maxWidth: .infinity)
            }
        } else if width >= 520 {
            // Balanced Bento Grid (iPhone Duo Opened 951pt, iPad, Landscape phones)
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    carPlayHeroCard(width: width)
                        .frame(maxWidth: .infinity)
                    dashcamControlCard(width: width)
                        .frame(maxWidth: .infinity)
                }

                cockpitControlsCard(width: width)
                    .frame(maxWidth: .infinity)
            }
        } else {
            // Compact / Cover Screen Vertical Stack (iPhone Duo Closed 466pt, Portrait Phones)
            VStack(spacing: 10) {
                carPlayHeroCard(width: width)
                dashcamControlCard(width: width)
                cockpitControlsCard(width: width)
            }
        }
    }

    // MARK: - Card 1: Apple CarPlay Hero Launchpad

    private func carPlayHeroCard(width: CGFloat) -> some View {
        let isCompact = width < 520
        return VStack(alignment: .leading, spacing: isCompact ? 10 : 14) {
            // Header Row
            HStack(spacing: isCompact ? 8 : 12) {
                drivingModeAppIcon
                    .frame(width: isCompact ? 42 : 52, height: isCompact ? 42 : 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple CarPlay")
                        .font(.system(size: isCompact ? 16 : 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("Wireless & USB Digital Receiver")
                        .font(.system(size: isCompact ? 10 : 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(manager.isStreamingActive ? Color.green : Color.blue)
                        .frame(width: 6, height: 6)
                    Text(manager.isStreamingActive ? "ACTIVE" : "STANDBY")
                        .font(.system(size: isCompact ? 9 : 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, isCompact ? 7 : 8)
                .padding(.vertical, isCompact ? 3 : 4)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
                .fixedSize(horizontal: true, vertical: true)
            }

            // Status Description
            VStack(alignment: .leading, spacing: 3) {
                if manager.isStreamingActive {
                    Text("CarPlay session is streaming live to this screen.")
                        .font(.system(size: isCompact ? 12 : 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                    if !isCompact {
                        Text("H.264 video hardware decoded with zero frame drops.")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.55))
                    }
                } else {
                    Text("Connect your iPhone via USB or Wireless CarPlay.")
                        .font(.system(size: isCompact ? 12 : 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                    if !isCompact {
                        Text(manager.stateReason)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(2)
                    }
                }
            }
            .frame(minHeight: isCompact ? 22 : 44)

            // Primary Launch / Control Action Button
            if manager.state == .streaming {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingActiveCarPlay = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.tv.fill")
                            .font(.system(size: isCompact ? 15 : 16, weight: .bold))
                        Text("RETURN TO CARPLAY")
                            .font(.system(size: isCompact ? 14 : 15, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: isCompact ? 46 : 50)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color(red: 0.1, green: 0.4, blue: 0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: isCompact ? 12 : 14, style: .continuous))
                    .shadow(color: Color.blue.opacity(0.4), radius: 10, x: 0, y: 5)
                }
            } else {
                #if targetEnvironment(simulator)
                Button {
                    manager.startLocalSimulation()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.tv.fill")
                            .font(.system(size: isCompact ? 15 : 16, weight: .bold))
                        Text("SIMULATE CARPLAY")
                            .font(.system(size: isCompact ? 14 : 15, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: isCompact ? 46 : 50)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.1, green: 0.7, blue: 0.4), Color(red: 0.05, green: 0.5, blue: 0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: isCompact ? 12 : 14, style: .continuous))
                    .shadow(color: Color.green.opacity(0.35), radius: 10, x: 0, y: 5)
                }
                #else
                Button {
                    handleThisiPhoneTap()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: isCompact ? 15 : 16, weight: .bold))
                        Text("START RECEIVER")
                            .font(.system(size: isCompact ? 14 : 15, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: isCompact ? 46 : 50)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.0, green: 0.48, blue: 1.0), Color(red: 0.0, green: 0.35, blue: 0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: isCompact ? 12 : 14, style: .continuous))
                    .shadow(color: Color.blue.opacity(0.35), radius: 10, x: 0, y: 5)
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
                #endif
            }

            if !isCompact {
                // Specs Row
                HStack(spacing: 6) {
                    Text("1080p @ 60 FPS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                    Text("•")
                        .foregroundColor(.white.opacity(0.3))
                    Text("Auto-Geometry")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                    Text("•")
                        .foregroundColor(.white.opacity(0.3))
                    Text("Multi-Touch")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 2)
            }
        }
        .padding(isCompact ? 14 : 18)
        .background(Color(white: 0.09).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: isCompact ? 16 : 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: isCompact ? 16 : 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.5), Color.purple.opacity(0.3), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
    }
    // MARK: - Card 2: Smart Dashcam & Sentry Console

    private func dashcamControlCard(width: CGFloat) -> some View {
        let isCompact = width < 520
        return VStack(alignment: .leading, spacing: isCompact ? 10 : 14) {
            // Header Row
            HStack(spacing: isCompact ? 8 : 12) {
                ZStack {
                    Circle()
                        .fill(dashcam.isRecording ? Color.red.opacity(0.2) : Color.white.opacity(0.1))
                        .frame(width: isCompact ? 38 : 48, height: isCompact ? 38 : 48)

                    Image(systemName: dashcam.isRecording ? "record.circle.fill" : "camera.fill")
                        .font(.system(size: isCompact ? 18 : 22, weight: .bold))
                        .foregroundColor(dashcam.isRecording ? .red : .white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Dashcam")
                        .font(.system(size: isCompact ? 16 : 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("Rolling Loop & Impact Sentry")
                        .font(.system(size: isCompact ? 10 : 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer()

                if dashcam.isRecording {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        DashcamTimerText(startTime: dashcam.recordingStartTime, fontSize: isCompact ? 10 : 11)
                    }
                    .padding(.horizontal, isCompact ? 7 : 8)
                    .padding(.vertical, isCompact ? 3 : 4)
                    .background(Color.red.opacity(0.25))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.red.opacity(0.6), lineWidth: 1))
                    .fixedSize(horizontal: true, vertical: true)
                } else {
                    Text("STANDBY")
                        .font(.system(size: isCompact ? 9 : 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, isCompact ? 7 : 8)
                        .padding(.vertical, isCompact ? 3 : 4)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: true)
                }
            }

            // Metrics / Specs
            if isCompact {
                HStack(spacing: 8) {
                    Label("Loop (5m)", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Label("Sentry (1.8G)", systemImage: "shield.checkered")
                        .foregroundColor(.green)
                    Spacer()
                    Label("3GB FIFO", systemImage: "internaldrive.fill")
                        .foregroundColor(.cyan)
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.75))
                .padding(8)
                .background(Color.black.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    HStack {
                        Label("Rolling Loop", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                        Spacer()
                        Text("5-min segments")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }

                    HStack {
                        Label("Impact Sentry", systemImage: "shield.checkered")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                        Spacer()
                        Text("Active (1.8G)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }

                    HStack {
                        Label("Quota Guard", systemImage: "internaldrive.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                        Spacer()
                        Text("3 GB FIFO")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                }
                .padding(10)
                .background(Color.black.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Action Button
            Button {
                if dashcam.isRecording {
                    dashcam.stopRecording()
                    config.isDashcamEnabled = false
                } else {
                    config.isDashcamEnabled = true
                    dashcam.startRecording(withAudio: config.isDashcamAudioEnabled)
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(dashcam.isRecording ? Color.white : (dashcam.isStarting ? Color.yellow : Color.red))
                        .frame(width: 7, height: 7)
                    Text(dashcam.isRecording ? "STOP DASHCAM" : (dashcam.isStarting ? "STARTING SENSOR…" : "START DASHCAM"))
                        .font(.system(size: isCompact ? 14 : 15, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: isCompact ? 46 : 50)
                .background(
                    dashcam.isRecording ?
                        LinearGradient(colors: [Color.red.opacity(0.8), Color(red: 0.7, green: 0.1, blue: 0.1)], startPoint: .top, endPoint: .bottom) :
                        LinearGradient(colors: [Color(white: 0.22), Color(white: 0.14)], startPoint: .top, endPoint: .bottom)
                )
                .clipShape(RoundedRectangle(cornerRadius: isCompact ? 12 : 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: isCompact ? 12 : 14, style: .continuous)
                        .stroke(dashcam.isRecording ? Color.red : Color.white.opacity(0.2), lineWidth: 1.2)
                )
                .shadow(color: dashcam.isRecording ? Color.red.opacity(0.4) : Color.clear, radius: 8, x: 0, y: 4)
            }

            // Quick Lock Button if recording
            if dashcam.isRecording {
                Button {
                    dashcam.saveCurrentEvent(reason: "Dashboard Menu")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("LOCK EMERGENCY CLIP")
                    }
                    .font(.system(size: isCompact ? 12 : 13, weight: .bold, design: .rounded))
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity)
                    .frame(height: isCompact ? 40 : 44)
                    .background(Color.yellow.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.5), lineWidth: 1))
                }
            }
        }
        .padding(isCompact ? 14 : 18)
        .background(Color(white: 0.09).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: isCompact ? 16 : 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: isCompact ? 16 : 20, style: .continuous)
                .stroke(
                    dashcam.isRecording ? Color.red.opacity(0.6) : Color.white.opacity(0.12),
                    lineWidth: 1.2
                )
        )
    }

    // MARK: - Card 3: Cockpit Controls & System Settings

    private func cockpitControlsCard(width: CGFloat) -> some View {
        let isCompact = width < 520
        return VStack(alignment: .leading, spacing: isCompact ? 10 : 14) {
            // Header Row
            HStack(spacing: isCompact ? 8 : 12) {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.15))
                        .frame(width: isCompact ? 36 : 44, height: isCompact ? 36 : 44)

                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: isCompact ? 17 : 20, weight: .bold))
                        .foregroundColor(.cyan)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cockpit Controls")
                        .font(.system(size: isCompact ? 16 : 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("Audio & Display Routing")
                        .font(.system(size: isCompact ? 10 : 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer()

                Button {
                    showingSettings = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: isCompact ? 11 : 12, weight: .semibold))
                        Text("SETTINGS")
                            .font(.system(size: isCompact ? 10 : 11, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, isCompact ? 9 : 12)
                    .frame(height: isCompact ? 32 : 36)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
            }

            if width >= 520 {
                HStack(alignment: .top, spacing: 14) {
                    audioRoutingSection
                        .frame(maxWidth: .infinity)
                    displayGeometrySection
                        .frame(maxWidth: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    audioRoutingSection
                    displayGeometrySection
                }
            }
        }
        .padding(isCompact ? 14 : 18)
        .background(Color(white: 0.09).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: isCompact ? 16 : 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: isCompact ? 16 : 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1.2)
        )
    }

    private var audioRoutingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AUDIO ROUTING")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))

            HStack(spacing: 8) {
                Button {
                    config.audioRoutingMode = .airPlayInBand
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 13))
                        Text("In-Band")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(config.audioRoutingMode == .airPlayInBand ? .white : .white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(config.audioRoutingMode == .airPlayInBand ? Color.cyan.opacity(0.35) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(config.audioRoutingMode == .airPlayInBand ? Color.cyan : Color.white.opacity(0.1), lineWidth: 1)
                    )
                }

                Button {
                    config.audioRoutingMode = .carBluetoothPassthrough
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 13))
                        Text("Bluetooth")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(config.audioRoutingMode == .carBluetoothPassthrough ? .white : .white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(config.audioRoutingMode == .carBluetoothPassthrough ? Color.orange.opacity(0.35) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(config.audioRoutingMode == .carBluetoothPassthrough ? Color.orange : Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
            }
        }
    }

    private var displayGeometrySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DISPLAY GEOMETRY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))

            HStack(spacing: 8) {
                Button {
                    config.fillScreenEdgeToEdge = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "aspectratio")
                            .font(.system(size: 13))
                        Text("Auto-Fit")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(!config.fillScreenEdgeToEdge ? .white : .white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(!config.fillScreenEdgeToEdge ? Color.blue.opacity(0.35) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(!config.fillScreenEdgeToEdge ? Color.blue : Color.white.opacity(0.1), lineWidth: 1)
                    )
                }

                Button {
                    config.fillScreenEdgeToEdge = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                            .font(.system(size: 13))
                        Text("Edge-to-Edge")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(config.fillScreenEdgeToEdge ? .white : .white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(config.fillScreenEdgeToEdge ? Color.purple.opacity(0.35) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(config.fillScreenEdgeToEdge ? Color.purple : Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - Cockpit Bottom Navigation Dock Bar

    private func cockpitBottomBar(width: CGFloat) -> some View {
        let isCompact = width < 520
        return HStack(spacing: isCompact ? 8 : 12) {
            // Pairing Guide
            Button {
                showingPairingGuide = true
            } label: {
                HStack(spacing: isCompact ? 6 : 8) {
                    Image(systemName: "book.pages.fill")
                        .font(.system(size: isCompact ? 13 : 14, weight: .bold))
                    Text(isCompact ? "Guide" : "Pairing Guide")
                        .font(.system(size: isCompact ? 13 : 14, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, isCompact ? 10 : 16)
                .frame(height: isCompact ? 42 : 48)
                .background(Color(white: 0.12))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
            }

            // Connect Remote iPhone
            Button {
                showingConnect = true
            } label: {
                HStack(spacing: isCompact ? 6 : 8) {
                    Image(systemName: "iphone.and.arrow.forward")
                        .font(.system(size: isCompact ? 13 : 14, weight: .bold))
                    Text(isCompact ? "Connect" : "Connect Phone")
                        .font(.system(size: isCompact ? 13 : 14, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, isCompact ? 10 : 16)
                .frame(height: isCompact ? 42 : 48)
                .background(Color(white: 0.12))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
            }

            Spacer()

            // Stop Session / Stop Receiver Button (if active)
            if manager.state != .idle {
                Button {
                    stopSession()
                } label: {
                    HStack(spacing: isCompact ? 5 : 8) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: isCompact ? 14 : 15, weight: .bold))
                        Text(isCompact ? "Stop" : "Stop Receiver")
                            .font(.system(size: isCompact ? 13 : 14, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.3))
                    .padding(.horizontal, isCompact ? 12 : 18)
                    .frame(height: isCompact ? 42 : 48)
                    .background(Color.red.opacity(0.18))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.red.opacity(0.6), lineWidth: 1))
                }
            }
        }
    }

    // MARK: - App Icon View

    @ViewBuilder
    private var drivingModeAppIcon: some View {
        #if canImport(UIKit)
        if let icon = UIImage(named: "AppIcon") ??
                      (Bundle.main.path(forResource: "AppIcon", ofType: "png", inDirectory: "CarPlayScreens").flatMap { UIImage(contentsOfFile: $0) }) ??
                      (Bundle.main.path(forResource: "AppIcon", ofType: "png").flatMap { UIImage(contentsOfFile: $0) }) {
            Image(uiImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.purple.opacity(0.35), radius: 8, x: 0, y: 4)
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
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(spacing: 2) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white, lineWidth: 2.5)
                        .frame(width: 32, height: 20)

                    HStack(spacing: 4) {
                        Image(systemName: "wifi")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .shadow(color: Color.purple.opacity(0.35), radius: 8, x: 0, y: 4)
    }

    // MARK: - Actions

    private func handleThisiPhoneTap() {
        startThisiPhoneSession()
    }

    private func startThisiPhoneSession() {
        manager.startReceiver()
    }

    private func stopSession() {
        showingActiveCarPlay = false
        manager.stopReceiver()
    }
}

// MARK: - Cockpit Real-time Clock View

public struct CockpitClockView: View {
    @State private var timeString: String = ""
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        Text(timeString.isEmpty ? "--:--" : timeString)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: true)
            .onReceive(timer) { _ in updateTime() }
            .onAppear { updateTime() }
    }

    private func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        timeString = formatter.string(from: Date())
    }
}
