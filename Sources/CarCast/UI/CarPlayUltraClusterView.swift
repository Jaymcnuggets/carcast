//
//  CarPlayUltraClusterView.swift
//  CarCast
//
//  Authentic CarPlay Ultra automotive digital instrument cluster display.
//

import SwiftUI

public struct CarPlayUltraClusterView: View {
    @ObservedObject var telemetry = VehicleTelemetry.shared
    @ObservedObject var config = CarCastConfig.shared

    @State private var nowPlayingOffset: CGSize = .zero
    @State private var isMetric: Bool = false
    @State private var selectedTheme: GaugeTheme = .cyan

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
        ZStack {
            // Dashboard background
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.07, blue: 0.12), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                // Top status bar
                HStack(spacing: 24) {
                    // Turn Signal Left
                    Button {
                        telemetry.turnSignal = telemetry.turnSignal == .left ? .off : .left
                    } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(telemetry.turnSignal == .left || telemetry.turnSignal == .hazard ? .green : .gray.opacity(0.3))
                    }

                    // Headlights
                    Button {
                        telemetry.headlampsOn.toggle()
                    } label: {
                        Image(systemName: telemetry.headlampsOn ? "headlight.low.beam.fill" : "headlight.low.beam")
                            .font(.system(size: 14))
                            .foregroundColor(telemetry.headlampsOn ? .green : .gray.opacity(0.4))
                    }

                    // PRND Gear
                    HStack(spacing: 12) {
                        ForEach(["P", "R", "N", "D"], id: \.self) { g in
                            Button {
                                telemetry.gear = g
                            } label: {
                                Text(g)
                                    .font(.system(size: 15, weight: telemetry.gear == g ? .heavy : .regular, design: .rounded))
                                    .foregroundColor(telemetry.gear == g ? selectedTheme.color : .gray.opacity(0.5))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())

                    // Hazard Lights
                    Button {
                        telemetry.turnSignal = telemetry.turnSignal == .hazard ? .off : .hazard
                    } label: {
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(telemetry.turnSignal == .hazard ? .red : .gray.opacity(0.4))
                    }

                    // Seatbelt
                    Button {
                        telemetry.seatbeltFastened.toggle()
                    } label: {
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .font(.system(size: 14))
                            .foregroundColor(telemetry.seatbeltFastened ? .green : .red)
                    }

                    // Turn Signal Right
                    Button {
                        telemetry.turnSignal = telemetry.turnSignal == .right ? .off : .right
                    } label: {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(telemetry.turnSignal == .right || telemetry.turnSignal == .hazard ? .green : .gray.opacity(0.3))
                    }
                }
                .padding(.top, 16)

                Spacer()

                // Dual Main Gauges: Speedometer & Tachometer
                HStack(spacing: 40) {
                    // Speedometer (Tap to toggle MPH / KMH)
                    Button {
                        withAnimation {
                            isMetric.toggle()
                        }
                    } label: {
                        GaugeDialView(
                            value: isMetric ? telemetry.speedMph * 1.60934 : telemetry.speedMph,
                            maxValue: isMetric ? 260 : 160,
                            unit: isMetric ? "KM/H" : "MPH",
                            title: "SPEED",
                            accentColor: selectedTheme.color
                        )
                    }
                    .buttonStyle(.plain)

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
                .padding(.horizontal, 24)

                Spacer()

                // Bottom Telemetry Bar: Fuel, Range, Battery, Coolant
                HStack(spacing: 32) {
                    // Fuel
                    HStack(spacing: 8) {
                        Image(systemName: "fuelpump.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.orange)
                        Text("\(Int(telemetry.fuelPercent * 100))%")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }

                    // Range
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 13))
                            .foregroundColor(.green)
                        let range = isMetric ? Int(Double(telemetry.rangeMiles) * 1.60934) : telemetry.rangeMiles
                        let unit = isMetric ? "km" : "mi"
                        Text("\(range) \(unit)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }

                    // Coolant
                    HStack(spacing: 8) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 13))
                            .foregroundColor(.blue)
                        Text("\(Int(telemetry.coolantTempC))°C")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }

                    // Battery
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.yellow)
                        Text("\(Int(telemetry.batteryPercent * 100))%")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
                .padding(.bottom, 16)
            }

            // Draggable Now Playing overlay card (from CarCast 0.3.24)
            VStack {
                Spacer()
                HStack {
                    NowPlayingCardView()
                        .offset(nowPlayingOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { val in
                                    nowPlayingOffset = val.translation
                                }
                                .onEnded { _ in
                                    // Soft spring settle
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        nowPlayingOffset = .zero
                                    }
                                }
                        )
                    Spacer()
                }
                .padding(.leading, 24)
                .padding(.bottom, 24)
            }
        }
    }
}

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
                .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 14, lineCap: .round))
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
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(90))

            // Center readout
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.gray)

                Text(String(format: displayDivider == 1.0 ? "%.0f" : "%.1f", value / displayDivider))
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                Text(unit)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(accentColor)
            }
        }
        .frame(width: 170, height: 170)
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
                .font(.system(size: 20))
                .foregroundColor(.white)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
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
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Track details
            VStack(alignment: .leading, spacing: 4) {
                Text(telemetry.currentTrackTitle)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("\(telemetry.currentArtist) — \(telemetry.currentAlbum)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)

                // Track progress line
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 3)
                        Capsule()
                            .fill(Color.cyan)
                            .frame(width: geo.size.width * CGFloat(telemetry.trackProgress), height: 3)
                    }
                }
                .frame(height: 3)
                .padding(.top, 2)
            }
            .frame(maxWidth: 160)

            // Playback Controls
            HStack(spacing: 12) {
                Button {
                    telemetry.isPlaying.toggle()
                } label: {
                    Image(systemName: telemetry.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }

                Button {
                    telemetry.trackProgress = 0.0
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.trailing, 4)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}
