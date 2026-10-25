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
        Group {
            if manager.isStreamingActive && showingActiveCarPlay {
                CarPlayActiveScreenView(onReturnToMenu: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingActiveCarPlay = false
                    }
                })
                .ignoresSafeArea(.all)
            } else {
                dashboardView
            }
        }
        .ignoresSafeArea((manager.isStreamingActive && showingActiveCarPlay) ? .all : [])
        .onChange(of: manager.isStreamingActive) { _, active in
            if active {
                showingActiveCarPlay = true
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

                    VStack(spacing: 0) {
                        // Top Cockpit Status Bar
                        cockpitHeaderBar
                            .padding(.leading, max(geo.safeAreaInsets.leading, 32))
                            .padding(.trailing, max(geo.safeAreaInsets.trailing, 32))
                            .padding(.top, 12)
                            .padding(.bottom, 12)

                        // Main Cockpit Center Stage
                        ScrollView(.vertical, showsIndicators: false) {
                            cockpitCardsLayout(width: geo.size.width)
                                .padding(.leading, max(geo.safeAreaInsets.leading, 32))
                                .padding(.trailing, max(geo.safeAreaInsets.trailing, 32))
                                .padding(.vertical, 6)
                        }

                        // Bottom Navigation Action Bar
                        cockpitBottomBar
                            .padding(.leading, max(geo.safeAreaInsets.leading, 32))
                            .padding(.trailing, max(geo.safeAreaInsets.trailing, 32))
                            .padding(.vertical, 12)
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

    private var cockpitHeaderBar: some View {
        HStack(alignment: .center, spacing: 14) {
            // Vehicle Brand Emblem & Title
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(white: 0.15))
                        .frame(width: 38, height: 38)
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))

                    Image(systemName: "car.side.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.cyan)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(config.carName.uppercased())
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("COCKPIT ACTIVE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan.opacity(0.9))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }

            Spacer()

            // Dynamic Central Status Pill
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(statusText.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if manager.state == .streaming {
                    Text("•")
                        .foregroundColor(.white.opacity(0.4))
                    Text("\(manager.totalFramesReceived) frames")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color(white: 0.12).opacity(0.85))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .fixedSize(horizontal: true, vertical: true)

            Spacer()

            // Right System Indicators Cluster
            HStack(spacing: 8) {
                // Wi-Fi Badge
                HStack(spacing: 5) {
                    Image(systemName: "wifi")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                    Text(config.wifiSSID.isEmpty ? "Direct" : config.wifiSSID)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .fixedSize(horizontal: true, vertical: true)

                // Live Clock
                CockpitClockView()
            }
        }
    }

    // MARK: - Cockpit Cards Layout (Panoramic / Adaptive)

    @ViewBuilder
    private func cockpitCardsLayout(width: CGFloat) -> some View {
        if width >= 860 {
            // Wide Panoramic 3-Card Deck (iPad, CarPlay Ultra wide display)
            HStack(alignment: .top, spacing: 14) {
                carPlayHeroCard
                    .frame(maxWidth: .infinity)
                dashcamControlCard
                    .frame(maxWidth: .infinity)
                cockpitControlsCard
                    .frame(maxWidth: .infinity)
            }
        } else if width >= 480 {
            // Dual-Pane Automotive Cockpit Grid (iPhone Duo, iPhone Pro Max Landscape)
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    carPlayHeroCard
                        .frame(maxWidth: .infinity)
                    dashcamControlCard
                        .frame(maxWidth: .infinity)
                }

                cockpitControlsCard
                    .frame(maxWidth: .infinity)
            }
        } else {
            // Compact / Portrait Stack
            VStack(spacing: 14) {
                carPlayHeroCard
                dashcamControlCard
                cockpitControlsCard
            }
        }
    }

    // MARK: - Card 1: Apple CarPlay Hero Launchpad

    private var carPlayHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Row
            HStack(spacing: 12) {
                drivingModeAppIcon
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple CarPlay")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Wireless & USB Digital Receiver")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(manager.isStreamingActive ? Color.green : Color.blue)
                        .frame(width: 7, height: 7)
                    Text(manager.isStreamingActive ? "ACTIVE" : "STANDBY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
            }

            // Status Description
            VStack(alignment: .leading, spacing: 4) {
                if manager.isStreamingActive {
                    Text("CarPlay session is streaming live to this screen.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                    Text("H.264 video hardware decoded with zero frame drops.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.55))
                } else {
                    Text("Connect your iPhone via USB or Wireless CarPlay.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                    Text(manager.stateReason)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                }
            }
            .frame(minHeight: 44)

            // Primary Launch / Control Action Button
            if manager.state == .streaming {
                Button {
                    showingActiveCarPlay = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.tv.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("RETURN TO CARPLAY")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color(red: 0.1, green: 0.4, blue: 0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.blue.opacity(0.4), radius: 10, x: 0, y: 5)
                }
            } else {
                #if targetEnvironment(simulator)
                Button {
                    manager.startLocalSimulation()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.tv.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("SIMULATE CARPLAY")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.1, green: 0.7, blue: 0.4), Color(red: 0.05, green: 0.5, blue: 0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.green.opacity(0.35), radius: 10, x: 0, y: 5)
                }
                #else
                Button {
                    handleThisiPhoneTap()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 16, weight: .bold))
                        Text("START RECEIVER")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.0, green: 0.48, blue: 1.0), Color(red: 0.0, green: 0.35, blue: 0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

            // Specs Row
            HStack(spacing: 6) {
                Text("1080p @ 60 FPS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                Text("•")
                    .foregroundColor(.white.opacity(0.3))
                Text("Bottom-Justified")
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
        .padding(18)
        .background(Color(white: 0.09).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
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

    private var dashcamControlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Row
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(dashcam.isRecording ? Color.red.opacity(0.2) : Color.white.opacity(0.1))
                        .frame(width: 48, height: 48)

                    Image(systemName: dashcam.isRecording ? "record.circle.fill" : "camera.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(dashcam.isRecording ? .red : .white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Dashcam")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Rolling Loop & Impact Sentry")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                if dashcam.isRecording {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                        DashcamTimerText(startTime: dashcam.recordingStartTime, fontSize: 11)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.25))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.red.opacity(0.6), lineWidth: 1))
                } else {
                    Text("STANDBY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
            }

            // Metrics / Specs
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
                        .frame(width: 8, height: 8)
                    Text(dashcam.isRecording ? "STOP DASHCAM" : (dashcam.isStarting ? "STARTING SENSOR…" : "START DASHCAM"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    dashcam.isRecording ?
                        LinearGradient(colors: [Color.red.opacity(0.8), Color(red: 0.7, green: 0.1, blue: 0.1)], startPoint: .top, endPoint: .bottom) :
                        LinearGradient(colors: [Color(white: 0.22), Color(white: 0.14)], startPoint: .top, endPoint: .bottom)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.yellow.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.5), lineWidth: 1))
                }
            }
        }
        .padding(18)
        .background(Color(white: 0.09).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    dashcam.isRecording ? Color.red.opacity(0.6) : Color.white.opacity(0.12),
                    lineWidth: 1.2
                )
        )
    }

    // MARK: - Card 3: Cockpit Controls & System Settings

    private var cockpitControlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Row
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.cyan)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cockpit Controls")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Audio & Display Routing")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()
            }

            // Audio Routing Quick Toggle
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

            // Display Mode Quick Toggle
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
                            Text("Bottom Fit")
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

            // Advanced Settings Launcher Button
            Button {
                showingSettings = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text("ALL SETTINGS")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1.2)
                )
            }
        }
        .padding(18)
        .background(Color(white: 0.09).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1.2)
        )
    }

    // MARK: - Cockpit Bottom Navigation Dock Bar

    private var cockpitBottomBar: some View {
        HStack(spacing: 12) {
            // Pairing Guide
            Button {
                showingPairingGuide = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "book.pages.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Pairing Guide")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Color(white: 0.12))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
            }

            // Connect Remote iPhone
            Button {
                showingConnect = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "iphone.and.arrow.forward")
                        .font(.system(size: 14, weight: .bold))
                    Text("Connect Phone")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 16)
                .frame(height: 48)
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
                    HStack(spacing: 8) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("Stop Receiver")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.3))
                    .padding(.horizontal, 18)
                    .frame(height: 48)
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
