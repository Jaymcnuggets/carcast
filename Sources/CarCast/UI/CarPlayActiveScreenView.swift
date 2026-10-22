//
//  CarPlayActiveScreenView.swift
//  CarCast
//
//  Authentic 1:1 Apple CarPlay UI & Presentation matching genuine iPhone screenshots
//  (iphone-this-iphone-carplay.png & iphone-portrait-carplay.png).
//

import SwiftUI
import AVFoundation

public struct CarPlayActiveScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager = CarPlayManager.shared
    @ObservedObject var config = CarCastConfig.shared

    @State private var activeApp: CarPlayAppType? = nil
    @State private var isDashboardSplit: Bool = false
    @State private var touchLocation: CGPoint? = nil
    @State private var showTouchIndicator: Bool = false
    @State private var currentTimeString: String = ""
    @State private var timeTimer: Timer? = nil

    public init() {}

    public enum CarPlayAppType: String, Identifiable {
        case phone = "Phone"
        case music = "Music"
        case maps = "Maps"
        case messages = "Messages"
        case nowPlaying = "Now Playing"
        case podcasts = "Podcasts"
        case audiobooks = "Audiobooks"
        case calendar = "Calendar"
        case settings = "Settings"
        case rplayFling = "rPlayFling"
        case weChat = "WeChat"

        public var id: String { rawValue }
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Authentic Apple CarPlay Dynamic Metallic Wallpaper
                carPlayWallpaper

                if config.isPortraitAllowed {
                    // Upright Portrait CarPlay matching iphone-portrait-carplay.png
                    portraitCarPlayLayout(size: geo.size)
                } else {
                    // Landscape CarPlay matching iphone-this-iphone-carplay.png
                    landscapeCarPlayLayout(size: geo.size)
                }

                // If live hardware video frames are actively received, overlay video stream
                if manager.isStreamingActive {
                    RawVideoCanvasView()
                        .ignoresSafeArea(config.avoidNotch ? [] : .all)
                }

                // Active In-CarPlay App Modal (e.g. Maps, Music)
                if let app = activeApp {
                    carPlayAppModalView(app: app, size: geo.size)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                }

                // Touch indicator overlay when "Show touches" is enabled in Settings
                if config.showTouches, let loc = touchLocation, showTouchIndicator {
                    Circle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 2))
                        .position(loc)
                        .allowsHitTesting(false)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        if config.showTouches {
                            touchLocation = val.location
                            showTouchIndicator = true
                        }
                        // Forward normalized touch coordinates to CarPlay manager
                        let normX = min(max(val.location.x / max(geo.size.width, 1.0), 0.0), 1.0)
                        let normY = min(max(val.location.y / max(geo.size.height, 1.0), 0.0), 1.0)
                        manager.sendTouchEvent(action: 1, x: normX, y: normY)
                    }
                    .onEnded { val in
                        if config.showTouches {
                            withAnimation(.easeOut(duration: 0.3)) {
                                showTouchIndicator = false
                            }
                        }
                        let normX = min(max(val.location.x / max(geo.size.width, 1.0), 0.0), 1.0)
                        let normY = min(max(val.location.y / max(geo.size.height, 1.0), 0.0), 1.0)
                        manager.sendTouchEvent(action: 0, x: normX, y: normY)
                    }
            )
        }
        .onAppear {
            updateTime()
            timeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                updateTime()
            }
        }
        .onDisappear {
            timeTimer?.invalidate()
            timeTimer = nil
        }
    }

    private func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        currentTimeString = formatter.string(from: Date())
    }

    // MARK: - Authentic Wallpaper

    private var carPlayWallpaper: some View {
        ZStack {
            // Fluid champagne/platinum curves matching authentic iOS CarPlay wallpaper
            LinearGradient(
                colors: [
                    Color(red: 0.88, green: 0.84, blue: 0.80),
                    Color(red: 0.65, green: 0.62, blue: 0.68),
                    Color(red: 0.28, green: 0.26, blue: 0.32)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle dark wave overlays
            GeometryReader { geo in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geo.size.height * 0.15))
                    path.addCurve(
                        to: CGPoint(x: geo.size.width, y: geo.size.height * 0.85),
                        control1: CGPoint(x: geo.size.width * 0.45, y: geo.size.height * 0.1),
                        control2: CGPoint(x: geo.size.width * 0.6, y: geo.size.height * 0.95)
                    )
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    path.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.25), Color.black.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }

    // MARK: - Landscape Layout (iphone-this-iphone-carplay.png)

    private func landscapeCarPlayLayout(size: CGSize) -> some View {
        HStack(spacing: 0) {
            // Authentic Left Sidebar Dock
            leftSidebarDock
                .frame(width: 76)
                .padding(.leading, 8)
                .padding(.vertical, 8)

            // Main CarPlay Canvas
            VStack(spacing: 16) {
                Spacer()

                if isDashboardSplit {
                    splitDashboardView
                } else {
                    // 4x2 App Grid
                    appGridLandscape
                }

                Spacer()

                // Dots Page Indicator: ● ○ ○ ○
                HStack(spacing: 8) {
                    Circle().fill(Color.white.opacity(0.9)).frame(width: 7, height: 7)
                    Circle().fill(Color.white.opacity(0.3)).frame(width: 7, height: 7)
                    Circle().fill(Color.white.opacity(0.3)).frame(width: 7, height: 7)
                    Circle().fill(Color.white.opacity(0.3)).frame(width: 7, height: 7)
                }
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
        }
        .ignoresSafeArea(config.avoidNotch ? [] : .all)
    }

    // MARK: - Left Sidebar Dock (Landscape)

    private var leftSidebarDock: some View {
        VStack(spacing: 12) {
            // Status area: Time + Cellular + Wi-Fi + Battery
            VStack(spacing: 4) {
                Text(currentTimeString.isEmpty ? "5:59" : currentTimeString)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.black)

                HStack(spacing: 3) {
                    // 4 Cellular Dots
                    HStack(spacing: 1.5) {
                        ForEach(0..<4) { _ in
                            Circle().fill(Color.black.opacity(0.7)).frame(width: 3.5, height: 3.5)
                        }
                    }
                    Image(systemName: "wifi")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.black)
                }

                // Battery Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.black.opacity(0.8), lineWidth: 1.5)
                        .frame(width: 22, height: 11)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(red: 0.2, green: 0.8, blue: 0.3))
                        .frame(width: 17, height: 7)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(.black)
                }
            }
            .padding(.top, 10)

            Spacer()

            // 3 Recent App Icons
            VStack(spacing: 10) {
                recentDockAppButton(icon: "map.fill", color: .cyan, title: "Maps") {
                    activeApp = .maps
                }
                recentDockAppButton(icon: "music.note", color: .red, title: "Music") {
                    activeApp = .music
                }
                recentDockAppButton(icon: "gearshape.fill", color: .gray, title: "Settings") {
                    activeApp = .settings
                }
            }

            Spacer()

            // Home Button: Squircle outline [ ]
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if activeApp != nil {
                        activeApp = nil
                    } else {
                        isDashboardSplit.toggle()
                    }
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.black.opacity(0.85), lineWidth: 2.5)
                        .frame(width: 30, height: 26)
                }
                .frame(width: 44, height: 44)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color(red: 0.94, green: 0.90, blue: 0.84)
                .opacity(0.88)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 2, y: 0)
    }

    private func recentDockAppButton(icon: String, color: Color, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 42, height: 42)
                    .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 2)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(color)
            }
        }
    }

    // MARK: - App Grid Landscape (4 Columns x 2 Rows)

    private var appGridLandscape: some View {
        let columns = [
            GridItem(.flexible(), spacing: 20),
            GridItem(.flexible(), spacing: 20),
            GridItem(.flexible(), spacing: 20),
            GridItem(.flexible(), spacing: 20)
        ]

        return LazyVGrid(columns: columns, spacing: 18) {
            // Row 1
            carPlayAppIconView(
                title: "Phone",
                badge: "47",
                systemIcon: "phone.fill",
                gradient: [Color(red: 0.28, green: 0.85, blue: 0.40), Color(red: 0.15, green: 0.70, blue: 0.30)]
            ) {
                activeApp = .phone
            }

            carPlayAppIconView(
                title: "Music",
                badge: nil,
                systemIcon: "music.note",
                gradient: [Color(red: 0.98, green: 0.20, blue: 0.36), Color(red: 0.85, green: 0.10, blue: 0.25)]
            ) {
                activeApp = .music
            }

            carPlayAppIconView(
                title: "Maps",
                badge: nil,
                systemIcon: "location.north.line.fill",
                gradient: [Color(red: 0.20, green: 0.75, blue: 0.85), Color(red: 0.10, green: 0.55, blue: 0.80)]
            ) {
                activeApp = .maps
            }

            carPlayAppIconView(
                title: "Messages",
                badge: "935",
                systemIcon: "message.fill",
                gradient: [Color(red: 0.30, green: 0.85, blue: 0.40), Color(red: 0.18, green: 0.72, blue: 0.32)]
            ) {
                activeApp = .messages
            }

            // Row 2
            carPlayAppIconView(
                title: "Now Playing",
                badge: nil,
                systemIcon: "waveform",
                gradient: [Color(red: 0.98, green: 0.25, blue: 0.50), Color(red: 0.85, green: 0.15, blue: 0.35)]
            ) {
                activeApp = .nowPlaying
            }

            // Central OEM Car App (e.g. LEXUS / BMW) — TAPPING THIS RETURNS TO CARCAST HOME!
            carPlayOemAppIconView

            carPlayAppIconView(
                title: "Podcasts",
                badge: nil,
                systemIcon: "antenna.radiowaves.left.and.right",
                gradient: [Color(red: 0.65, green: 0.28, blue: 0.92), Color(red: 0.48, green: 0.18, blue: 0.80)]
            ) {
                activeApp = .podcasts
            }

            carPlayAppIconView(
                title: "Audiobooks",
                badge: nil,
                systemIcon: "book.fill",
                gradient: [Color(red: 0.98, green: 0.58, blue: 0.12), Color(red: 0.88, green: 0.45, blue: 0.08)]
            ) {
                activeApp = .audiobooks
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - OEM Car App Icon (Returns to CarCast Home)

    private var carPlayOemAppIconView: some View {
        let brandTitle = config.customLogoLabel.isEmpty ?
            (CarBrandCatalog.shared.brand(for: config.selectedBrandId)?.oemLabel ?? "LEXUS") :
            config.customLogoLabel

        return Button {
            // Per authentic CarCast user guide:
            // "The CarPlay home screen has an icon for the car itself (LEXUS until you pick one).
            // Tap it to leave CarPlay for CarCast's own screen, which says 'CarPlay is connected'."
            dismiss()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black)
                        .frame(width: 72, height: 72)
                        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 4)

                    #if canImport(UIKit)
                    if let img = CarBrandCatalog.shared.logoImage(for: config.selectedBrandId, size: 180) {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 54, height: 54)
                    } else {
                        Image(systemName: "car.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                    }
                    #else
                    Image(systemName: "car.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    #endif
                }

                // Label pill matching authentic screenshot
                Text(brandTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.94, green: 0.90, blue: 0.84).opacity(0.85))
                    )
            }
        }
    }

    // MARK: - App Icon View Component

    private func carPlayAppIconView(
        title: String,
        badge: String?,
        systemIcon: String,
        gradient: [Color],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 72, height: 72)
                        .shadow(color: Color.black.opacity(0.28), radius: 6, x: 0, y: 4)

                    Image(systemName: systemIcon)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 72, height: 72)

                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 8, y: -6)
                            .shadow(color: Color.red.opacity(0.4), radius: 4, x: 0, y: 2)
                    }
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.94, green: 0.90, blue: 0.84).opacity(0.85))
                    )
            }
        }
    }

    // MARK: - Portrait CarPlay Layout (iphone-portrait-carplay.png)

    private func portraitCarPlayLayout(size: CGSize) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 44)

            // 4 Columns x 3 Rows App Grid
            let columns = [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)
            ]

            LazyVGrid(columns: columns, spacing: 20) {
                // Row 1
                carPlayAppIconView(title: "Phone", badge: "1,005", systemIcon: "phone.fill", gradient: [Color.green, Color.green.opacity(0.8)]) {
                    activeApp = .phone
                }
                carPlayAppIconView(title: "Music", badge: nil, systemIcon: "music.note", gradient: [Color.red, Color.red.opacity(0.85)]) {
                    activeApp = .music
                }
                carPlayAppIconView(title: "Maps", badge: nil, systemIcon: "location.north.line.fill", gradient: [Color.cyan, Color.blue]) {
                    activeApp = .maps
                }
                carPlayAppIconView(title: "Messages", badge: "9", systemIcon: "message.fill", gradient: [Color.green, Color.green.opacity(0.8)]) {
                    activeApp = .messages
                }

                // Row 2
                carPlayAppIconView(title: "Now Playing", badge: nil, systemIcon: "waveform", gradient: [Color.pink, Color.red]) {
                    activeApp = .nowPlaying
                }
                carPlayOemAppIconView
                carPlayAppIconView(title: "Podcasts", badge: nil, systemIcon: "antenna.radiowaves.left.and.right", gradient: [Color.purple, Color.indigo]) {
                    activeApp = .podcasts
                }
                carPlayAppIconView(title: "Audiobooks", badge: nil, systemIcon: "book.fill", gradient: [Color.orange, Color.orange.opacity(0.85)]) {
                    activeApp = .audiobooks
                }

                // Row 3
                carPlayAppIconView(title: "Calendar", badge: nil, systemIcon: "calendar", gradient: [Color.white, Color(white: 0.9)]) {
                    activeApp = .calendar
                }
                carPlayAppIconView(title: "Settings", badge: nil, systemIcon: "gearshape.fill", gradient: [Color.gray, Color.gray.opacity(0.85)]) {
                    activeApp = .settings
                }
                carPlayAppIconView(title: "rPlayFling", badge: nil, systemIcon: "play.tv.fill", gradient: [Color.red, Color.orange]) {
                    activeApp = .rplayFling
                }
                carPlayAppIconView(title: "WeChat", badge: nil, systemIcon: "bubble.left.and.bubble.right.fill", gradient: [Color.green, Color.mint]) {
                    activeApp = .weChat
                }
            }
            .padding(.horizontal, 16)

            Spacer()

            // Page Dots
            HStack(spacing: 8) {
                Circle().fill(Color.black.opacity(0.7)).frame(width: 7, height: 7)
                Circle().fill(Color.black.opacity(0.3)).frame(width: 7, height: 7)
                Circle().fill(Color.black.opacity(0.3)).frame(width: 7, height: 7)
            }
            .padding(.bottom, 16)

            // Authentic Portrait Bottom Dock Bar matching iphone-portrait-carplay.png
            HStack(spacing: 16) {
                // Home Button [ ]
                Button {
                    activeApp = nil
                } label: {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.black.opacity(0.85), lineWidth: 2.2)
                        .frame(width: 24, height: 20)
                }

                // Time
                Text(currentTimeString.isEmpty ? "7:25" : currentTimeString)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.black)

                Spacer()

                // Dock App Shortcuts
                HStack(spacing: 12) {
                    recentDockAppButton(icon: "location.north.line.fill", color: .cyan, title: "Maps") {
                        activeApp = .maps
                    }
                    recentDockAppButton(icon: "music.note", color: .red, title: "Music") {
                        activeApp = .music
                    }
                    recentDockAppButton(icon: "play.tv.fill", color: .orange, title: "rPlayFling") {
                        activeApp = .rplayFling
                    }
                }

                Spacer()

                // Signal + Wi-Fi + Battery
                HStack(spacing: 4) {
                    HStack(alignment: .bottom, spacing: 1.5) {
                        Capsule().fill(Color.black).frame(width: 2.5, height: 4)
                        Capsule().fill(Color.black).frame(width: 2.5, height: 7)
                        Capsule().fill(Color.black).frame(width: 2.5, height: 10)
                        Capsule().fill(Color.black.opacity(0.3)).frame(width: 2.5, height: 13)
                    }
                    Image(systemName: "wifi")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                    ZStack {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.black, lineWidth: 1.5)
                            .frame(width: 22, height: 11)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.black)
                            .frame(width: 17, height: 7)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Color(red: 0.94, green: 0.90, blue: 0.84)
                    .opacity(0.85)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Split Dashboard View

    private var splitDashboardView: some View {
        HStack(spacing: 14) {
            // Left Half: Turn-by-Turn Map Card
            ZStack {
                Color(red: 0.18, green: 0.22, blue: 0.28)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "arrow.turn.up.right")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("In 500 ft")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text("Turn right on Grand Avenue")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    Spacer()
                    HStack {
                        Text("24 min · 14 mi · ETA 6:23 PM")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Right Half: Stacked Now Playing and Calendar
            VStack(spacing: 12) {
                // Now Playing Card
                ZStack {
                    Color(red: 0.14, green: 0.15, blue: 0.20)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.red.opacity(0.8))
                            .frame(width: 48, height: 48)
                            .overlay(Image(systemName: "music.note").foregroundColor(.white))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Blinding Lights")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("The Weeknd")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }

                        Spacer()

                        Image(systemName: "play.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                    }
                    .padding(12)
                }

                // Smart Suggestions Card
                ZStack {
                    Color(red: 0.14, green: 0.15, blue: 0.20)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    HStack(spacing: 12) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Navigate Home")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("Usual route: 18 min")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .padding(12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - In-CarPlay App Modal

    private func carPlayAppModalView(app: CarPlayAppType, size: CGSize) -> some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 0) {
                // Modal Top Bar
                HStack {
                    Button {
                        withAnimation { activeApp = nil }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                            Text("Home")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.blue)
                    }

                    Spacer()

                    Text(app.rawValue)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Text(config.customLogoLabel.isEmpty ? (CarBrandCatalog.shared.brand(for: config.selectedBrandId)?.oemLabel ?? "CAR") : config.customLogoLabel)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(white: 0.12))

                // Modal Content
                Group {
                    switch app {
                    case .music, .nowPlaying:
                        nowPlayingAppView
                    case .maps:
                        mapsAppView
                    case .phone:
                        phoneAppView
                    case .messages:
                        messagesAppView
                    default:
                        genericAppView(title: app.rawValue)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(white: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    private var nowPlayingAppView: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.red.opacity(0.8))
                    .frame(width: 140, height: 140)
                    .shadow(color: Color.red.opacity(0.3), radius: 12, x: 0, y: 6)
                Image(systemName: "music.note")
                    .font(.system(size: 54))
                    .foregroundColor(.white)
            }

            VStack(spacing: 4) {
                Text("Starboy")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("The Weeknd · Daft Punk")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
            }

            HStack(spacing: 48) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                Image(systemName: "pause.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
                Image(systemName: "forward.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
            }
            .padding(.top, 12)
            Spacer()
        }
    }

    private var mapsAppView: some View {
        ZStack {
            Color(red: 0.12, green: 0.18, blue: 0.24)
            VStack(spacing: 16) {
                Image(systemName: "location.north.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.cyan)
                Text("Apple Maps Navigation")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Route: Interstate 280 South · 18 min to Destination")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
        }
    }

    private var phoneAppView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "phone.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(.green)
            Text("Recent Calls")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("No missed calls")
                .font(.system(size: 14))
                .foregroundColor(.gray)
            Spacer()
        }
    }

    private var messagesAppView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "message.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(.green)
            Text("Messages")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Siri can read your unread messages")
                .font(.system(size: 14))
                .foregroundColor(.gray)
            Spacer()
        }
    }

    private func genericAppView(title: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "app.fill")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Spacer()
        }
    }
}
