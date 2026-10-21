//
//  CarPlayUltraClusterView.swift
//  CarCast
//
//  Authentic Next-Generation Apple CarPlay Ultra automotive digital instrument cluster display,
//  featuring integrated Apple Maps navigation, live CarPlay stream embedding, ADAS assist, and Apple gauges.
//

import SwiftUI
import CoreMedia

public struct CarPlayUltraClusterView: View {
    @ObservedObject var telemetry = VehicleTelemetry.shared
    @ObservedObject var config = CarCastConfig.shared
    @ObservedObject var manager = CarPlayManager.shared

    @State private var selectedMode: ClusterDisplayMode = .navigation
    @State private var isMetric: Bool = false
    @State private var selectedTheme: GaugeTheme = .cyan
    @State private var nowPlayingOffset: CGSize = .zero
    @State private var mapAnimationPhase: CGFloat = 0.0

    public enum ClusterDisplayMode: String, CaseIterable, Sendable {
        case navigation = "Maps"
        case liveCarPlay = "Live"
        case dualDials = "Dials"
        case assist = "ADAS"

        var icon: String {
            switch self {
            case .navigation: return "map.fill"
            case .liveCarPlay: return "play.tv.fill"
            case .dualDials: return "gauge.medium"
            case .assist: return "steeringwheel"
            }
        }
    }

    public enum GaugeTheme: String, CaseIterable, Sendable {
        case cyan = "Sport Cyan"
        case red = "Redline"
        case gold = "Luxury Amber"
        case white = "Monochrome"

        var color: Color {
            switch self {
            case .cyan: return .cyan
            case .red: return .red
            case .gold: return Color(red: 1.0, green: 0.78, blue: 0.28)
            case .white: return .white
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

                // Mode-specific main background
                switch selectedMode {
                case .navigation:
                    AppleMapsRouteCanvas(phase: mapAnimationPhase)
                        .ignoresSafeArea()
                        .overlay(
                            LinearGradient(
                                colors: [Color.black.opacity(0.65), Color.black.opacity(0.2), Color.black.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                case .liveCarPlay:
                    VideoCanvasView()
                        .ignoresSafeArea()
                case .dualDials:
                    LinearGradient(
                        colors: [Color(red: 0.04, green: 0.06, blue: 0.10), Color.black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                case .assist:
                    AdasHighwayCanvas(phase: mapAnimationPhase)
                        .ignoresSafeArea()
                }

                // Overlaid Cluster HUD (Gauges, Turn-by-Turn, Top Bar, Bottom Bar)
                if selectedMode != .liveCarPlay {
                    VStack(spacing: 0) {
                        // 1. Top Automotive Status Bar
                        topStatusBar
                            .padding(.horizontal, isLandscape ? 24 : 16)
                            .padding(.top, isLandscape ? 12 : 8)

                        // 2. Center Content Area (Depends on mode & orientation)
                        Spacer(minLength: 6)
                        centerContent(in: geo.size, isLandscape: isLandscape)
                        Spacer(minLength: 6)

                        // 3. Mode Switcher & Telemetry Bar
                        bottomControlBar(isLandscape: isLandscape)
                            .padding(.horizontal, isLandscape ? 24 : 16)
                            .padding(.bottom, isLandscape ? 12 : 8)
                    }
                } else {
                    // Floating minimal HUD overlay for Live CarPlay mode
                    VStack {
                        HStack {
                            // Mini speed pill
                            HStack(spacing: 6) {
                                Text("\(Int(isMetric ? telemetry.speedMph * 1.60934 : telemetry.speedMph))")
                                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                                Text(isMetric ? "KM/H" : "MPH")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.gray)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())

                            Spacer()

                            // Return / Mode selector
                            clusterModePicker(isLandscape: isLandscape)
                                .scaleEffect(0.9)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                        Spacer()
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 20.0).repeatForever(autoreverses: false)) {
                mapAnimationPhase = 1000.0
            }
        }
    }

    // MARK: - Center Content Layouts

    @ViewBuilder
    private func centerContent(in size: CGSize, isLandscape: Bool) -> some View {
        switch selectedMode {
        case .navigation:
            if isLandscape {
                navigationModeLandscape(in: size)
            } else {
                navigationModePortrait(in: size)
            }
        case .dualDials:
            dualDialsContent(isLandscape: isLandscape)
        case .assist:
            assistModeContent(isLandscape: isLandscape)
        case .liveCarPlay:
            EmptyView()
        }
    }

    // MARK: - 1. Apple Maps Navigation (Landscape)

    private func navigationModeLandscape(in size: CGSize) -> some View {
        VStack(spacing: 12) {
            AppleTurnByTurnCard()
                .padding(.horizontal, 32)

            Spacer()

            HStack(spacing: 24) {
                // Left: Apple Speedometer with Speed Limit Sign
                VStack(spacing: 8) {
                    AppleSpeedDial(
                        speed: isMetric ? telemetry.speedMph * 1.60934 : telemetry.speedMph,
                        maxSpeed: isMetric ? 260 : 160,
                        unit: isMetric ? "KM/H" : "MPH",
                        accentColor: selectedTheme.color
                    )

                    AppleSpeedLimitSign(limit: isMetric ? 100 : 65)
                }
                .frame(width: 140)

                Spacer()

                // Center: Dynamic Lane Guidance & ETA Banner
                VStack(spacing: 8) {
                    laneGuidancePill
                    etaSummaryCard
                }

                Spacer()

                // Right: Apple Power / Tachometer Dial + Gear
                VStack(spacing: 8) {
                    AppleTachDial(
                        rpm: telemetry.rpm,
                        gear: telemetry.gear,
                        accentColor: selectedTheme.color
                    )

                    cruiseIndicator
                }
                .frame(width: 140)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - 1. Apple Maps Navigation (Portrait)

    private func navigationModePortrait(in size: CGSize) -> some View {
        VStack(spacing: 10) {
            AppleTurnByTurnCard()
                .padding(.horizontal, 16)

            Spacer(minLength: 4)

            // Dials & Speed Limit Row
            HStack(spacing: 12) {
                AppleSpeedDial(
                    speed: isMetric ? telemetry.speedMph * 1.60934 : telemetry.speedMph,
                    maxSpeed: isMetric ? 260 : 160,
                    unit: isMetric ? "KM/H" : "MPH",
                    accentColor: selectedTheme.color,
                    size: 115
                )

                AppleSpeedLimitSign(limit: isMetric ? 100 : 65)

                AppleTachDial(
                    rpm: telemetry.rpm,
                    gear: telemetry.gear,
                    accentColor: selectedTheme.color,
                    size: 115
                )
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 4)

            // Lane guidance & ETA row
            HStack(spacing: 12) {
                laneGuidancePill
                etaSummaryCard
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 4)
        }
    }

    // MARK: - Reusable Navigation Elements

    private var laneGuidancePill: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up")
                .foregroundColor(.gray.opacity(0.6))
            Image(systemName: "arrow.up")
                .foregroundColor(.gray.opacity(0.6))
            Image(systemName: "arrow.turn.up.right")
                .foregroundColor(.white)
                .padding(5)
                .background(Color.green)
                .clipShape(Circle())
        }
        .font(.system(size: 13, weight: .bold))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var etaSummaryCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("10:42")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("ETA")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.gray)
            }

            Divider()
                .frame(height: 18)
                .background(Color.white.opacity(0.2))

            VStack(alignment: .leading, spacing: 1) {
                Text("18")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.green)
                Text("MIN")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.gray)
            }

            Divider()
                .frame(height: 18)
                .background(Color.white.opacity(0.2))

            VStack(alignment: .leading, spacing: 1) {
                Text("14.2")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(isMetric ? "KM" : "MI")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var cruiseIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.needle.fill")
                .font(.system(size: 10))
            Text("CRUISE 68")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .foregroundColor(.green)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.green.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - 2. Dual Dials Mode (Classic Performance)

    private func dualDialsContent(isLandscape: Bool) -> some View {
        HStack(spacing: isLandscape ? 28 : 16) {
            // Speed Dial
            GaugeDialView(
                value: isMetric ? telemetry.speedMph * 1.60934 : telemetry.speedMph,
                maxValue: isMetric ? 260 : 160,
                unit: isMetric ? "KM/H" : "MPH",
                title: "SPEED",
                accentColor: selectedTheme.color
            )

            // Center Widget: Now Playing or Speed Limit
            VStack(spacing: 10) {
                NowPlayingCardView()

                AppleSpeedLimitSign(limit: isMetric ? 100 : 65)
            }
            .frame(maxWidth: isLandscape ? 200 : 160)

            // Tachometer
            GaugeDialView(
                value: telemetry.rpm,
                maxValue: 8000,
                unit: "RPM × 1000",
                title: "TACH",
                accentColor: selectedTheme.color == .cyan ? .purple : selectedTheme.color,
                displayDivider: 1000
            )
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 3. ADAS Assist Mode (Autopilot / Highway Visualization)

    private func assistModeContent(isLandscape: Bool) -> some View {
        VStack(spacing: 14) {
            // Autopilot Status Header
            HStack(spacing: 10) {
                Image(systemName: "steeringwheel")
                    .foregroundColor(.cyan)
                Text("CarPlay Driver Assist Active")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())

            Spacer()

            // Center speed and distance
            HStack(spacing: isLandscape ? 32 : 16) {
                VStack(spacing: 1) {
                    Text("\(Int(isMetric ? telemetry.speedMph * 1.60934 : telemetry.speedMph))")
                        .font(.system(size: isLandscape ? 56 : 44, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text(isMetric ? "KM/H" : "MPH")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(selectedTheme.color)
                }

                AppleSpeedLimitSign(limit: isMetric ? 100 : 65)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "car.side.front.open.fill")
                        Text("Follow: 3 cars")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)

                    HStack(spacing: 5) {
                        Image(systemName: "road.lanes")
                        Text("Lane Keeping: Active")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.green)
                }
            }

            Spacer()
        }
    }

    // MARK: - Top Status Bar

    private var topStatusBar: some View {
        HStack(spacing: 14) {
            // Turn Signal Left
            Button {
                telemetry.turnSignal = telemetry.turnSignal == .left ? .off : .left
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(telemetry.turnSignal == .left || telemetry.turnSignal == .hazard ? .green : .gray.opacity(0.3))
            }

            // Headlights
            Button {
                telemetry.headlampsOn.toggle()
            } label: {
                Image(systemName: telemetry.headlampsOn ? "headlight.low.beam.fill" : "headlight.low.beam")
                    .font(.system(size: 13))
                    .foregroundColor(telemetry.headlampsOn ? .green : .gray.opacity(0.4))
            }

            Spacer()

            // CarPlay Connected Client Banner
            HStack(spacing: 4) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 11))
                Text(manager.state == .streaming ? "CarPlay" : "Ultra")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())

            // PRND Gear Selector
            HStack(spacing: 10) {
                ForEach(["P", "R", "N", "D"], id: \.self) { g in
                    Button {
                        telemetry.gear = g
                    } label: {
                        Text(g)
                            .font(.system(size: 13, weight: telemetry.gear == g ? .heavy : .regular, design: .rounded))
                            .foregroundColor(telemetry.gear == g ? selectedTheme.color : .gray.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())

            Spacer()

            // Seatbelt
            Button {
                telemetry.seatbeltFastened.toggle()
            } label: {
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .font(.system(size: 13))
                    .foregroundColor(telemetry.seatbeltFastened ? .green : .red)
            }

            // Hazard Lights
            Button {
                telemetry.turnSignal = telemetry.turnSignal == .hazard ? .off : .hazard
            } label: {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(telemetry.turnSignal == .hazard ? .red : .gray.opacity(0.4))
            }

            // Turn Signal Right
            Button {
                telemetry.turnSignal = telemetry.turnSignal == .right ? .off : .right
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(telemetry.turnSignal == .right || telemetry.turnSignal == .hazard ? .green : .gray.opacity(0.3))
            }
        }
    }

    // MARK: - Bottom Control Bar

    private func bottomControlBar(isLandscape: Bool) -> some View {
        HStack(spacing: 8) {
            // Mode selector pills
            clusterModePicker(isLandscape: isLandscape)

            Spacer()

            // Telemetry Metrics (Fuel/Battery, Range, Coolant)
            HStack(spacing: 8) {
                // Fuel / EV
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 10))
                    Text("\(Int(telemetry.batteryPercent * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                }

                // Range
                HStack(spacing: 3) {
                    Image(systemName: "arrow.left.and.right")
                        .foregroundColor(.green)
                        .font(.system(size: 10))
                    let range = isMetric ? Int(Double(telemetry.rangeMiles) * 1.60934) : telemetry.rangeMiles
                    let unit = isMetric ? "km" : "mi"
                    Text("\(range)\(unit)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                }

                // Unit toggle (MPH / KM/H)
                Button {
                    withAnimation { isMetric.toggle() }
                } label: {
                    Text(isMetric ? "KM/H" : "MPH")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.cyan.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
        }
    }

    private func clusterModePicker(isLandscape: Bool = true) -> some View {
        HStack(spacing: 3) {
            ForEach(ClusterDisplayMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedMode = mode
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11))
                        if isLandscape {
                            Text(mode.rawValue)
                                .font(.system(size: 10, weight: selectedMode == mode ? .bold : .medium, design: .rounded))
                                .lineLimit(1)
                        }
                    }
                    .foregroundColor(selectedMode == mode ? .black : .white.opacity(0.85))
                    .padding(.horizontal, isLandscape ? 8 : 7)
                    .padding(.vertical, 5)
                    .background(selectedMode == mode ? Color.cyan : Color.clear)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }
}

// MARK: - Apple Turn-by-Turn Navigation Card

struct AppleTurnByTurnCard: View {
    var body: some View {
        HStack(spacing: 12) {
            // Maneuver Icon
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 38, height: 38)
                Image(systemName: "arrow.turn.up.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(red: 0.11, green: 0.65, blue: 0.25))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("500 ft")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("•")
                        .foregroundColor(.white.opacity(0.6))
                    Text("De Anza Blvd")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Text("Then take I-280 North towards San Francisco")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer()

            // Mini maneuver badge
            VStack(alignment: .trailing, spacing: 1) {
                Image(systemName: "location.north.line.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                Text("Route 280")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.trailing, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.58, blue: 0.23), Color(red: 0.08, green: 0.46, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.2), lineWidth: 1))
        .shadow(color: Color.green.opacity(0.3), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Apple Speed Limit Sign

struct AppleSpeedLimitSign: View {
    let limit: Int

    var body: some View {
        VStack(spacing: 1) {
            Text("SPEED")
                .font(.system(size: 6, weight: .bold, design: .rounded))
                .foregroundColor(.black)
            Text("LIMIT")
                .font(.system(size: 6, weight: .bold, design: .rounded))
                .foregroundColor(.black)
            Text("\(limit)")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(.black)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.black, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Apple Speedometer Dial

struct AppleSpeedDial: View {
    let speed: Double
    let maxSpeed: Double
    let unit: String
    let accentColor: Color
    var size: CGFloat = 130

    private var progress: Double {
        return max(0, min(1.0, speed / maxSpeed))
    }

    var body: some View {
        ZStack {
            // Background arc
            Circle()
                .trim(from: 0.2, to: 0.8)
                .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: size > 120 ? 9 : 7, lineCap: .round))
                .rotationEffect(.degrees(90))

            // Neon progress arc
            Circle()
                .trim(from: 0.2, to: 0.2 + (progress * 0.60))
                .stroke(
                    AngularGradient(
                        colors: [accentColor.opacity(0.8), accentColor, .orange],
                        center: .center,
                        startAngle: .degrees(162),
                        endAngle: .degrees(378)
                    ),
                    style: StrokeStyle(lineWidth: size > 120 ? 9 : 7, lineCap: .round)
                )
                .rotationEffect(.degrees(90))

            // Center readout
            VStack(spacing: 0) {
                Text("\(Int(speed))")
                    .font(.system(size: size > 120 ? 36 : 28, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(unit)
                    .font(.system(size: size > 120 ? 10 : 9, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Apple Tachometer Dial

struct AppleTachDial: View {
    let rpm: Double
    let gear: String
    let accentColor: Color
    var size: CGFloat = 130

    private var progress: Double {
        return max(0, min(1.0, rpm / 8000.0))
    }

    var body: some View {
        ZStack {
            // Background arc
            Circle()
                .trim(from: 0.2, to: 0.8)
                .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: size > 120 ? 9 : 7, lineCap: .round))
                .rotationEffect(.degrees(90))

            // Progress arc
            Circle()
                .trim(from: 0.2, to: 0.2 + (progress * 0.60))
                .stroke(
                    AngularGradient(
                        colors: [.purple, accentColor, .red],
                        center: .center,
                        startAngle: .degrees(162),
                        endAngle: .degrees(378)
                    ),
                    style: StrokeStyle(lineWidth: size > 120 ? 9 : 7, lineCap: .round)
                )
                .rotationEffect(.degrees(90))

            // Center readout: Gear and RPM
            VStack(spacing: 0) {
                Text(gear)
                    .font(.system(size: size > 120 ? 30 : 24, weight: .heavy, design: .rounded))
                    .foregroundColor(accentColor)
                Text(String(format: "%.1f", rpm / 1000.0))
                    .font(.system(size: size > 120 ? 12 : 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                Text("RPM")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.gray)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Apple Maps Route Canvas (Vector Simulation)

struct AppleMapsRouteCanvas: View {
    let phase: CGFloat

    var body: some View {
        Canvas { context, size in
            // Dark map terrain base
            let baseRect = CGRect(origin: .zero, size: size)
            context.fill(Path(baseRect), with: .color(Color(red: 0.05, green: 0.07, blue: 0.10)))

            // Secondary roads grid
            var gridPath = Path()
            let spacing: CGFloat = 80
            for x in stride(from: CGFloat(0), to: size.width, by: spacing) {
                gridPath.move(to: CGPoint(x: x, y: 0))
                gridPath.addLine(to: CGPoint(x: x + 40, y: size.height))
            }
            for y in stride(from: CGFloat(0), to: size.height, by: spacing) {
                gridPath.move(to: CGPoint(x: 0, y: y))
                gridPath.addLine(to: CGPoint(x: size.width, y: y + 20))
            }
            context.stroke(gridPath, with: .color(Color.white.opacity(0.04)), lineWidth: 1.5)

            // Curved Main Highway Route
            var route = Path()
            let start = CGPoint(x: size.width * 0.5, y: size.height + 40)
            let mid1 = CGPoint(x: size.width * 0.52, y: size.height * 0.6)
            let mid2 = CGPoint(x: size.width * 0.45, y: size.height * 0.3)
            let end = CGPoint(x: size.width * 0.6, y: -20)

            route.move(to: start)
            route.addCurve(to: end, control1: mid1, control2: mid2)

            // Highway casing (dark border)
            context.stroke(route, with: .color(Color(red: 0.02, green: 0.15, blue: 0.35)), lineWidth: 32)

            // Highway blue route line (Apple Maps signature blue)
            context.stroke(
                route,
                with: .color(Color(red: 0.00, green: 0.48, blue: 1.0)),
                style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round)
            )

            // Center neon route stripe
            context.stroke(
                route,
                with: .color(Color(red: 0.40, green: 0.80, blue: 1.0)),
                style: StrokeStyle(lineWidth: 6, lineCap: .round)
            )

            // Vehicle navigation chevron arrow
            let carPos = CGPoint(x: size.width * 0.5, y: size.height * 0.65)
            var chevron = Path()
            chevron.move(to: CGPoint(x: carPos.x, y: carPos.y - 14))
            chevron.addLine(to: CGPoint(x: carPos.x + 12, y: carPos.y + 12))
            chevron.addLine(to: CGPoint(x: carPos.x, y: carPos.y + 6))
            chevron.addLine(to: CGPoint(x: carPos.x - 12, y: carPos.y + 12))
            chevron.closeSubpath()

            // Chevron shadow & glow
            context.fill(chevron, with: .color(.cyan))
        }
    }
}

// MARK: - ADAS Highway Canvas (Lane Detection)

struct AdasHighwayCanvas: View {
    let phase: CGFloat

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let horizon = h * 0.35

            // Road surface
            var road = Path()
            road.move(to: CGPoint(x: w * 0.45, y: horizon))
            road.addLine(to: CGPoint(x: w * 0.55, y: horizon))
            road.addLine(to: CGPoint(x: w * 0.85, y: h))
            road.addLine(to: CGPoint(x: w * 0.15, y: h))
            road.closeSubpath()
            context.fill(road, with: .color(Color(red: 0.06, green: 0.08, blue: 0.12)))

            // Left lane boundary (green active)
            var leftLane = Path()
            leftLane.move(to: CGPoint(x: w * 0.45, y: horizon))
            leftLane.addLine(to: CGPoint(x: w * 0.22, y: h))
            context.stroke(leftLane, with: .color(Color.green), lineWidth: 4)

            // Right lane boundary (green active)
            var rightLane = Path()
            rightLane.move(to: CGPoint(x: w * 0.55, y: horizon))
            rightLane.addLine(to: CGPoint(x: w * 0.78, y: h))
            context.stroke(rightLane, with: .color(Color.green), lineWidth: 4)

            // Center dashed lane line
            var centerLane = Path()
            centerLane.move(to: CGPoint(x: w * 0.5, y: horizon))
            centerLane.addLine(to: CGPoint(x: w * 0.5, y: h))
            context.stroke(
                centerLane,
                with: .color(Color.white.opacity(0.4)),
                style: StrokeStyle(lineWidth: 3, dash: [20, 15], dashPhase: phase)
            )

            // Host vehicle icon
            let hostCar = CGRect(x: w * 0.5 - 20, y: h * 0.72, width: 40, height: 60)
            context.fill(Path(roundedRect: hostCar, cornerRadius: 8), with: .color(Color.cyan))

            // Lead vehicle ahead
            let leadCar = CGRect(x: w * 0.5 - 15, y: h * 0.48, width: 30, height: 44)
            context.fill(Path(roundedRect: leadCar, cornerRadius: 6), with: .color(Color.gray.opacity(0.7)))
        }
    }
}

// MARK: - Existing Gauge & Now Playing Support

struct GaugeDialView: View {
    let value: Double
    let maxValue: Double
    let unit: String
    let title: String
    let accentColor: Color
    var displayDivider: Double = 1.0

    private var progress: Double {
        return max(0, min(1.0, value / maxValue))
    }

    var body: some View {
        ZStack {
            // Background arc
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(90))

            // Progress arc
            Circle()
                .trim(from: 0.15, to: 0.15 + (progress * 0.70))
                .stroke(
                    AngularGradient(
                        colors: [accentColor.opacity(0.7), accentColor, .red],
                        center: .center,
                        startAngle: .degrees(144),
                        endAngle: .degrees(396)
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(90))

            // Center readout
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(.gray)

                Text(String(format: displayDivider == 1.0 ? "%.0f" : "%.1f", value / displayDivider))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                Text(unit)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(accentColor)
            }
        }
        .frame(width: 120, height: 120)
    }
}

struct NowPlayingCardView: View {
    @ObservedObject var telemetry = VehicleTelemetry.shared

    private var placeholderArt: some View {
        ZStack {
            LinearGradient(
                colors: [.purple, .indigo],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 16))
                .foregroundColor(.white)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Album Artwork
            ZStack {
                #if canImport(UIKit)
                if let art = telemetry.albumArtworkData, let uiImage = UIImage(data: art) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    placeholderArt
                }
                #elseif canImport(AppKit)
                if let art = telemetry.albumArtworkData, let nsImage = NSImage(data: art) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    placeholderArt
                }
                #endif
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Track details
            VStack(alignment: .leading, spacing: 2) {
                Text(telemetry.currentTrackTitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(telemetry.currentArtist)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            // Play/Pause
            Button {
                telemetry.isPlaying.toggle()
            } label: {
                Image(systemName: telemetry.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}
