//
//  CarPlayUltraClusterView.swift
//  CarCast
//
//  Authentic 1:1 Apple CarPlay Infotainment & Dashboard Display,
//  featuring the iconic iOS CarPlay Dashboard split-view (Apple Maps + Next Turn + Now Playing),
//  authentic frosted glass Dock, 2x4 App Launcher Grid, full-screen Maps & Music,
//  and live AirPlay stream overlay.
//

import SwiftUI
import CoreMedia
import Combine

public struct CarPlayUltraClusterView: View {
    @ObservedObject var telemetry = VehicleTelemetry.shared
    @ObservedObject var config = CarCastConfig.shared
    @ObservedObject var manager = CarPlayManager.shared

    // Navigation state within CarPlay
    @State private var activeScreen: CarPlayScreen = .dashboard
    @State private var isPlaying: Bool = true
    @State private var trackProgress: Double = 0.42
    @State private var currentTimeStr: String = "9:41"
    @State private var selectedWallpaper: CarPlayWallpaper = .midnight

    private let clockTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    private let playbackTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    public enum CarPlayScreen: String, CaseIterable, Sendable {
        case dashboard = "Dashboard"
        case appGrid = "Home"
        case maps = "Maps"
        case music = "Music"
        case phone = "Phone"
        case messages = "Messages"
        case oemCar = "OEM"
        case settings = "Settings"
    }

    public enum CarPlayWallpaper: String, CaseIterable, Sendable {
        case midnight = "Midnight"
        case slate = "Dark Slate"
        case aurora = "Aurora Indigo"
        case carbon = "Carbon"

        var gradient: [Color] {
            switch self {
            case .midnight:
                return [
                    Color(red: 0.06, green: 0.08, blue: 0.14),
                    Color(red: 0.03, green: 0.04, blue: 0.08)
                ]
            case .slate:
                return [
                    Color(red: 0.10, green: 0.12, blue: 0.16),
                    Color(red: 0.05, green: 0.06, blue: 0.09)
                ]
            case .aurora:
                return [
                    Color(red: 0.08, green: 0.07, blue: 0.18),
                    Color(red: 0.04, green: 0.04, blue: 0.10)
                ]
            case .carbon:
                return [
                    Color(red: 0.08, green: 0.08, blue: 0.09),
                    Color(red: 0.02, green: 0.02, blue: 0.03)
                ]
            }
        }
    }

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                // Background dark automotive canvas
                Color.black.ignoresSafeArea()

                // Full-screen authentic Apple CarPlay Interface
                carPlayDisplay(in: geo.size, isLandscape: isLandscape)
                    .ignoresSafeArea()

                // If live video is actively receiving from connected iPhone, overlay it
                if manager.lastSampleBuffer != nil {
                    VideoCanvasView()
                        .ignoresSafeArea()
                }
            }
        }
        .onAppear {
            updateClock()
        }
        .onReceive(clockTimer) { _ in
            updateClock()
        }
        .onReceive(playbackTimer) { _ in
            if isPlaying {
                trackProgress += 0.005
                if trackProgress > 1.0 { trackProgress = 0.0 }
            }
        }
    }

    private func updateClock() {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        currentTimeStr = formatter.string(from: Date())
    }

    // MARK: - Core Apple CarPlay Display Container

    @ViewBuilder
    private func carPlayDisplay(in size: CGSize, isLandscape: Bool) -> some View {
        ZStack {
            // Dynamic Apple CarPlay Wallpaper
            LinearGradient(
                colors: selectedWallpaper.gradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle Apple fluid ambient mesh circles
            Circle()
                .fill(Color(red: 0.12, green: 0.22, blue: 0.42).opacity(0.25))
                .frame(width: size.width * 0.7, height: size.width * 0.7)
                .offset(x: -size.width * 0.2, y: -size.height * 0.3)
                .blur(radius: 50)

            Circle()
                .fill(Color(red: 0.30, green: 0.12, blue: 0.35).opacity(0.20))
                .frame(width: size.width * 0.6, height: size.width * 0.6)
                .offset(x: size.width * 0.3, y: size.height * 0.3)
                .blur(radius: 50)

            // Main Layout: Dock + Viewport
            HStack(spacing: 0) {
                if config.drivingPosition == .leftHandDrive {
                    carPlayDock(height: size.height)
                }

                // Main Content Viewport
                let contentWidth = size.width - 66
                let contentSize = CGSize(width: contentWidth, height: size.height)

                ZStack {
                    switch activeScreen {
                    case .dashboard:
                        if isLandscape {
                            carPlayDashboardLandscape(in: contentSize)
                                .transition(.opacity)
                        } else {
                            carPlayDashboardPortrait(in: contentSize)
                                .transition(.opacity)
                        }
                    case .appGrid:
                        carPlayAppGrid(in: contentSize, isLandscape: isLandscape)
                            .transition(.opacity)
                    case .maps:
                        carPlayFullScreenMaps(in: contentSize)
                            .transition(.opacity)
                    case .music:
                        carPlayFullScreenMusic(in: contentSize, isLandscape: isLandscape)
                            .transition(.opacity)
                    case .phone:
                        carPlayFullScreenPhone(in: contentSize)
                            .transition(.opacity)
                    case .messages:
                        carPlayFullScreenMessages(in: contentSize)
                            .transition(.opacity)
                    case .oemCar:
                        carPlayFullScreenOem(in: contentSize)
                            .transition(.opacity)
                    case .settings:
                        carPlayFullScreenSettings(in: contentSize)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if config.drivingPosition == .rightHandDrive {
                    carPlayDock(height: size.height)
                }
            }
        }
    }

    // MARK: - 1. Authentic Apple CarPlay Dock (Sidebar)

    private func carPlayDock(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Time & Connectivity Status (Top)
            VStack(spacing: 4) {
                Text(currentTimeStr)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                HStack(spacing: 3) {
                    Image(systemName: "cellularbars")
                        .font(.system(size: 9, weight: .bold))
                    Image(systemName: "wifi")
                        .font(.system(size: 9, weight: .bold))
                    Image(systemName: "battery.100")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(.white.opacity(0.85))
            }
            .padding(.top, 48)

            Spacer()

            // 3 Recent App Shortcuts (Middle)
            VStack(spacing: 14) {
                dockAppShortcut(
                    name: "maps",
                    icon: "map.fill",
                    color: Color(red: 0.12, green: 0.60, blue: 0.98),
                    target: .maps
                )

                dockAppShortcut(
                    name: "music",
                    icon: "music.note",
                    color: Color(red: 0.98, green: 0.18, blue: 0.32),
                    target: .music
                )

                dockAppShortcut(
                    name: "phone",
                    icon: "phone.fill",
                    color: Color(red: 0.20, green: 0.82, blue: 0.38),
                    target: .phone
                )
            }

            Spacer()

            // CarPlay Home / Dashboard Switcher Button (Bottom)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    if activeScreen == .dashboard {
                        activeScreen = .appGrid
                    } else {
                        activeScreen = .dashboard
                    }
                }
                CarPlayManager.shared.sendHomeButtonPress()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 42, height: 42)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )

                    if activeScreen == .dashboard {
                        // 8-Dots Icon: Tap to go to App Grid
                        VStack(spacing: 3) {
                            HStack(spacing: 3) {
                                ForEach(0..<4) { _ in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.white)
                                        .frame(width: 3.5, height: 3.5)
                                }
                            }
                            HStack(spacing: 3) {
                                ForEach(0..<4) { _ in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.white)
                                        .frame(width: 3.5, height: 3.5)
                                }
                            }
                        }
                    } else {
                        // Dashboard Split View Icon: Tap to go to Dashboard
                        HStack(spacing: 2.5) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.white)
                                .frame(width: 10, height: 16)
                            VStack(spacing: 2.5) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.white)
                                    .frame(width: 10, height: 6.8)
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.white)
                                    .frame(width: 10, height: 6.8)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 36)
        }
        .frame(width: 66)
        .background(
            Color.black.opacity(0.60)
                .background(.ultraThinMaterial)
        )
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1),
            alignment: config.drivingPosition == .leftHandDrive ? .trailing : .leading
        )
    }

    private func dockAppShortcut(name: String, icon: String, color: Color, target: CarPlayScreen) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                activeScreen = target
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color)
                    .frame(width: 42, height: 42)
                    .shadow(color: color.opacity(0.35), radius: 4, x: 0, y: 2)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - 2. The Apple CarPlay Dashboard (Landscape Split View)

    private func carPlayDashboardLandscape(in size: CGSize) -> some View {
        HStack(spacing: 12) {
            // LEFT: Apple Maps Vector Navigation Canvas (~58% width)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    activeScreen = .maps
                }
            } label: {
                CarPlayVectorMapWidget()
            }
            .buttonStyle(ScaleButtonStyle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // RIGHT: Stacked Turn-by-Turn Card & Now Playing Card (~42% width)
            VStack(spacing: 12) {
                // Top Card: Turn-by-Turn Guidance
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        activeScreen = .maps
                    }
                } label: {
                    CarPlayDashboardTurnCard()
                }
                .buttonStyle(ScaleButtonStyle())
                .frame(maxHeight: .infinity)

                // Bottom Card: Now Playing Media Deck
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        activeScreen = .music
                    }
                } label: {
                    CarPlayDashboardNowPlayingCard()
                }
                .buttonStyle(ScaleButtonStyle())
                .frame(maxHeight: .infinity)
            }
            .frame(width: max(180, size.width * 0.40))
        }
        .padding(14)
    }

    // MARK: - 3. The Apple CarPlay Dashboard (Portrait Adaptive View)

    private func carPlayDashboardPortrait(in size: CGSize) -> some View {
        VStack(spacing: 12) {
            // Top: Apple Maps Navigation Canvas (~50% height)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    activeScreen = .maps
                }
            } label: {
                CarPlayVectorMapWidget()
            }
            .buttonStyle(ScaleButtonStyle())
            .frame(maxWidth: .infinity)
            .frame(height: size.height * 0.48)

            // Middle: Turn-by-Turn Card
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    activeScreen = .maps
                }
            } label: {
                CarPlayDashboardTurnCard()
            }
            .buttonStyle(ScaleButtonStyle())
            .frame(height: 96)

            // Bottom: Now Playing Card
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    activeScreen = .music
                }
            } label: {
                CarPlayDashboardNowPlayingCard()
            }
            .buttonStyle(ScaleButtonStyle())
            .frame(height: 96)

            // Bottom Complications Pill: Speedometer & Speed Limit
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Text("64")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("MPH")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.cyan)
                }

                Spacer()

                HStack(spacing: 8) {
                    ForEach(["P", "R", "N", "D"], id: \.self) { g in
                        Text(g)
                            .font(.system(size: 13, weight: g == "D" ? .heavy : .bold, design: .rounded))
                            .foregroundColor(g == "D" ? .cyan : .gray.opacity(0.4))
                    }
                }

                Spacer()

                // Speed Limit 65 Sign
                VStack(spacing: 1) {
                    Text("SPEED")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.black)
                    Text("LIMIT")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.black)
                    Text("65")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(.black)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.black, lineWidth: 1.2)
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.55).background(.ultraThinMaterial))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .padding(.horizontal, 12)
        .padding(.top, 48)
        .padding(.bottom, 24)
    }

    // MARK: - 4. Apple CarPlay App Launcher (2x4 Grid)

    private func carPlayAppGrid(in size: CGSize, isLandscape: Bool) -> some View {
        let brand = CarBrandCatalog.shared.brand(for: config.selectedBrandId)
        let brandName = brand?.title ?? "Vehicle"

        let apps: [(id: CarPlayScreen, label: String, icon: String, color: Color)] = [
            (.phone, "Phone", "phone.fill", Color(red: 0.20, green: 0.82, blue: 0.38)),
            (.music, "Music", "music.note", Color(red: 0.98, green: 0.18, blue: 0.32)),
            (.maps, "Maps", "map.fill", Color(red: 0.12, green: 0.60, blue: 0.98)),
            (.messages, "Messages", "message.fill", Color(red: 0.20, green: 0.82, blue: 0.38)),
            (.music, "Now Playing", "play.circle.fill", Color(red: 1.00, green: 0.22, blue: 0.38)),
            (.oemCar, brandName, "car.fill", Color(red: 0.08, green: 0.52, blue: 0.95)),
            (.music, "Podcasts", "antenna.radiowaves.left.and.right", Color(red: 0.68, green: 0.32, blue: 0.88)),
            (.settings, "Settings", "gearshape.fill", Color(red: 0.55, green: 0.55, blue: 0.58))
        ]

        let columns = isLandscape
            ? Array(repeating: GridItem(.flexible(), spacing: 20), count: 4)
            : Array(repeating: GridItem(.flexible(), spacing: 18), count: 2)

        return VStack(spacing: 16) {
            Spacer()

            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(apps, id: \.label) { app in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            activeScreen = app.id
                        }
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(app.color)
                                    .frame(width: 64, height: 64)
                                    .shadow(color: app.color.opacity(0.35), radius: 6, x: 0, y: 3)

                                Image(systemName: app.icon)
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundColor(.white)
                            }

                            Text(app.label)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Page Dots
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
            .padding(.bottom, 24)
        }
        .padding(.top, isLandscape ? 12 : 48)
    }

    // MARK: - 5. Full-Screen Apple Maps

    private func carPlayFullScreenMaps(in size: CGSize) -> some View {
        ZStack {
            // Full Canvas
            CarPlayVectorMapWidget(isFullScreen: true)

            // Top Turn Guidance Card
            VStack {
                HStack {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(red: 0.08, green: 0.62, blue: 0.28))
                                .frame(width: 38, height: 38)
                            Image(systemName: "arrow.turn.up.right")
                                .font(.system(size: 20, weight: .heavy))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("500 ft • Turn right")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("De Anza Blvd towards I-280")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75).background(.ultraThinMaterial))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                    Spacer()

                    // Speed Limit 65 Sign
                    VStack(spacing: 1) {
                        Text("SPEED")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.black)
                        Text("LIMIT")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.black)
                        Text("65")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundColor(.black)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.black, lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 4)
                }
                .padding(.horizontal, 14)
                .padding(.top, 48)

                Spacer()

                // Bottom ETA Bar
                HStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Text("10:42")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text("ETA")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)

                        Text("•")
                            .foregroundColor(.gray)

                        Text("18")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                        Text("MIN")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)

                        Text("•")
                            .foregroundColor(.gray)

                        Text("14.2")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("MI")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    Button {
                        withAnimation {
                            activeScreen = .dashboard
                        }
                    } label: {
                        Text("End")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.85))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.80).background(.ultraThinMaterial))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                .padding(.horizontal, 14)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - 6. Full-Screen Apple Music

    private func carPlayFullScreenMusic(in size: CGSize, isLandscape: Bool) -> some View {
        Group {
            if isLandscape {
                HStack(spacing: 24) {
                    // Album Artwork
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.85, green: 0.15, blue: 0.25), Color(red: 0.15, green: 0.05, blue: 0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: min(180, size.height - 48), height: min(180, size.height - 48))
                            .shadow(color: Color.red.opacity(0.35), radius: 16, x: 0, y: 8)

                        Image(systemName: "music.note")
                            .font(.system(size: 54, weight: .light))
                            .foregroundColor(.white)
                    }
                    .padding(.leading, 20)

                    musicControlsView
                }
            } else {
                VStack(spacing: 20) {
                    // Album Artwork
                    ZStack {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.85, green: 0.15, blue: 0.25), Color(red: 0.15, green: 0.05, blue: 0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 190, height: 190)
                            .shadow(color: Color.red.opacity(0.35), radius: 20, x: 0, y: 10)

                        Image(systemName: "music.note")
                            .font(.system(size: 64, weight: .light))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 54)

                    musicControlsView
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private var musicControlsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Blinding Lights")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                Text("The Weeknd — After Hours")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
            }

            // Scrubber Bar
            VStack(spacing: 4) {
                GeometryReader { pGeo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: pGeo.size.width * CGFloat(trackProgress))
                    }
                }
                .frame(height: 4)

                HStack {
                    Text("1:42")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.gray)
                    Spacer()
                    Text("-1:38")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }

            // Controls
            HStack(spacing: 28) {
                Button {
                    trackProgress = max(0, trackProgress - 0.1)
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                }

                Button {
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 46))
                        .foregroundColor(.white)
                }

                Button {
                    trackProgress = min(1.0, trackProgress + 0.1)
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                }

                Spacer()

                Button {
                    // Queue
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                }
            }
        }
    }

    // MARK: - 7. Full-Screen Phone & Messages & OEM & Settings

    private func carPlayFullScreenPhone(in size: CGSize) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.green)
                Text("Phone")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)

            HStack(spacing: 18) {
                // Keypad digits
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"], id: \.self) { digit in
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 44, height: 44)
                            Text(digit)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(maxWidth: 220)

                // Call Button
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.20, green: 0.82, blue: 0.38))
                            .frame(width: 54, height: 54)
                        Image(systemName: "phone.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }

                    Text("Hands-Free Active")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    private func carPlayFullScreenMessages(in size: CGSize) -> some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "message.fill")
                    .foregroundColor(.green)
                Text("Messages")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)

            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 52))
                    .foregroundColor(.green)
                Text("Siri is ready to read or send messages.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }

            Spacer()
        }
    }

    private func carPlayFullScreenOem(in size: CGSize) -> some View {
        let brand = CarBrandCatalog.shared.brand(for: config.selectedBrandId)
        let brandName = brand?.title ?? "Vehicle"

        return VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "car.fill")
                    .foregroundColor(.cyan)
                Text("\(brandName) Vehicle Cockpit")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)

            HStack(spacing: 16) {
                oemMetricTile(title: "Battery", value: "85%", sub: "340 mi range", icon: "bolt.fill", accent: .green)
                oemMetricTile(title: "Tires", value: "36 PSI", sub: "All 4 normal", icon: "circle.grid.cross.fill", accent: .cyan)
                oemMetricTile(title: "Drive Mode", value: "Sport", sub: "Direct response", icon: "flame.fill", accent: .orange)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    private func oemMetricTile(title: String, value: String, sub: String, icon: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(accent)
                Spacer()
            }
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
            Text(sub)
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(.gray)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private func carPlayFullScreenSettings(in size: CGSize) -> some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.gray)
                Text("CarPlay Settings")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)

            VStack(alignment: .leading, spacing: 10) {
                Text("WALLPAPER")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.gray)

                ForEach(CarPlayWallpaper.allCases, id: \.self) { wp in
                    Button {
                        selectedWallpaper = wp
                    } label: {
                        HStack {
                            Circle()
                                .fill(wp.gradient.first ?? .blue)
                                .frame(width: 14, height: 14)
                            Text(wp.rawValue)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            Spacer()
                            if selectedWallpaper == wp {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.cyan)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(selectedWallpaper == wp ? Color.white.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }
}

// MARK: - Apple Maps Vector Navigation Canvas Widget (Native MapKit)

public struct CarPlayVectorMapWidget: View {
    @ObservedObject var location = NativeLocationService.shared
    public var isFullScreen: Bool = false

    public init(isFullScreen: Bool = false) {
        self.isFullScreen = isFullScreen
    }

    public var body: some View {
        ZStack {
            // Live Native Apple MapKit 3D Vector View
            NativeMapKitView(
                coordinate: location.currentCoordinate,
                heading: location.currentHeadingDegrees,
                isPitchEnabled: true
            )
            .ignoresSafeArea()

            // Subtle map controls overlay
            VStack {
                HStack {
                    // Search Pill
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10, weight: .bold))
                        Text("Search")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .foregroundColor(.white)

                    Spacer()

                    // Compass Rose
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.7))
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))

                        VStack(spacing: 0) {
                            Triangle()
                                .fill(Color.red)
                                .frame(width: 5, height: 7)
                            Triangle()
                                .fill(Color.white)
                                .frame(width: 5, height: 7)
                                .rotationEffect(.degrees(180))
                        }
                    }
                }
                .padding(10)

                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isFullScreen ? 0 : 16))
        .overlay(
            RoundedRectangle(cornerRadius: isFullScreen ? 0 : 16)
                .stroke(Color.white.opacity(0.12), lineWidth: isFullScreen ? 0 : 1)
        )
    }
}

// MARK: - Dashboard Turn-by-Turn Card

public struct CarPlayDashboardTurnCard: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            // Maneuver Icon Squircle
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.12, green: 0.75, blue: 0.35), Color(red: 0.08, green: 0.60, blue: 0.26)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 46, height: 46)
                    .shadow(color: Color.green.opacity(0.3), radius: 6, x: 0, y: 3)

                Image(systemName: "arrow.turn.up.right")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("500 ft")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                Text("De Anza Blvd")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(1)

                // Lane Guidance
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.gray)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.gray)
                    Image(systemName: "arrow.turn.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.black.opacity(0.55)
                .background(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - Dashboard Now Playing Card (Native MediaPlayer)

public struct CarPlayDashboardNowPlayingCard: View {
    @ObservedObject var media = NativeMediaService.shared

    public init(isPlaying: Binding<Bool>? = nil, progress: Double? = nil) {}

    public var body: some View {
        HStack(spacing: 12) {
            // Album Artwork
            ZStack {
                #if os(iOS)
                if let img = media.albumArtworkImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    fallbackArtwork
                }
                #else
                fallbackArtwork
                #endif
            }

            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(media.trackTitle)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(media.artistName)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }

                // Audio Scrubber Progress
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(Color.white)
                            .frame(width: geo.size.width * CGFloat(media.playbackProgress))
                    }
                }
                .frame(height: 3)

                // Playback Controls
                HStack(spacing: 16) {
                    Button {
                        media.skipBackward()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }

                    Button {
                        media.togglePlayPause()
                    } label: {
                        Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                    }

                    Button {
                        media.skipForward()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }

                    Spacer()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.black.opacity(0.55)
                .background(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private var fallbackArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.90, green: 0.15, blue: 0.28), Color(red: 0.20, green: 0.05, blue: 0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 48, height: 48)
                .shadow(color: Color.red.opacity(0.35), radius: 6, x: 0, y: 3)

            Image(systemName: "music.note")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Helper Scale Button Style & Shapes

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
