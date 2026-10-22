//
//  CarPlayUltraClusterView.swift
//  CarCast
//
//  Authentic Digital Cockpit Cluster & Apple CarPlay Display,
//  embedding the genuine live H.264 video stream via VideoCanvasView,
//  with authentic automotive telemetry and mode switching.
//

import SwiftUI
import CoreMedia
import Combine

public struct CarPlayUltraClusterView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var telemetry = VehicleTelemetry.shared
    @ObservedObject var config = DrivingModeConfig.shared
    @ObservedObject var manager = CarPlayManager.shared
    @ObservedObject var location = NativeLocationService.shared

    @State private var displayMode: ClusterMode = .cockpitCluster
    @State private var isMetric: Bool = false

    public enum ClusterMode: String, CaseIterable, Sendable {
        case cockpitCluster = "Cockpit Cluster"
        case fullStream = "Full CarPlay Stream"

        var icon: String {
            switch self {
            case .cockpitCluster: return "gauge.with.needle.fill"
            case .fullStream: return "play.tv.fill"
            }
        }
    }

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                switch displayMode {
                case .fullStream:
                    // 100% full-bleed live Apple CarPlay stream / receiver
                    VideoCanvasView()
                        .ignoresSafeArea()

                case .cockpitCluster:
                    // Automotive instrument cluster with center live CarPlay video stream
                    clusterLayout(in: geo.size)
                }

                // Floating Mode Switcher & Stream Status
                VStack {
                    HStack {
                        // Live Stream Indicator Pill
                        HStack(spacing: 6) {
                            Circle()
                                .fill(manager.lastSampleBuffer != nil ? Color.green : Color.yellow)
                                .frame(width: 8, height: 8)
                            Text(manager.lastSampleBuffer != nil ? "LIVE CARPLAY STREAM" : "AIRPLAY STANDBY")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))

                        Spacer()

                        // Mode Picker & Close
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                ForEach(ClusterMode.allCases, id: \.self) { mode in
                                    Button {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            displayMode = mode
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: mode.icon)
                                                .font(.system(size: 11))
                                            Text(mode.rawValue)
                                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(displayMode == mode ? Color.cyan.opacity(0.3) : Color.clear)
                                        .foregroundColor(displayMode == mode ? .cyan : .white.opacity(0.7))
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(3)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))

                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    Spacer()
                }
            }
        }
        .onAppear {
            if manager.state == .idle || manager.state == .error {
                manager.startReceiver()
            }
        }
    }

    // MARK: - Cockpit Cluster Layout

    @ViewBuilder
    private func clusterLayout(in size: CGSize) -> some View {
        let isLandscape = size.width > size.height

        if isLandscape {
            HStack(spacing: 8) {
                // Left Gauge: Speedometer & Gear
                leftGaugeView
                    .frame(width: 140)

                // Center Console: Live CarPlay Video Canvas
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(red: 0.03, green: 0.04, blue: 0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
                        )

                    VideoCanvasView()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 4)

                // Right Gauge: Compass Heading, Tach & Battery
                rightGaugeView
                    .frame(width: 140)
            }
            .padding(.horizontal, 8)
        } else {
            // Portrait Cockpit Layout
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    leftGaugeCompact
                    rightGaugeCompact
                }
                .frame(height: 120)
                .padding(.top, 40)

                // Center Live Video Stream
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.03, green: 0.04, blue: 0.07))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))

                    VideoCanvasView()
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Left Instrument: Live Speedometer & Driving Gear

    private var leftGaugeView: some View {
        VStack(spacing: 14) {
            // Turn Signal Indicator & Vehicle status
            HStack(spacing: 12) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(telemetry.turnSignal == .left ? .green : .gray.opacity(0.3))

                Image(systemName: "car.side.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))

                Image(systemName: "headlight.high.beam.fill")
                    .font(.system(size: 14))
                    .foregroundColor(telemetry.highBeamsOn ? .blue : .gray.opacity(0.3))
            }

            Spacer()

            // Digital Speed Readout
            VStack(spacing: 2) {
                let speedMph = location.currentSpeedMPH > 0 ? location.currentSpeedMPH : telemetry.speedMph
                let displaySpeed = isMetric ? speedMph * 1.60934 : speedMph
                Text("\(Int(displaySpeed))")
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())

                Text(isMetric ? "KM/H" : "MPH")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
            }
            .onTapGesture {
                withAnimation {
                    isMetric.toggle()
                }
            }

            // Gear Selector (PRND)
            HStack(spacing: 8) {
                ForEach(["P", "R", "N", "D"], id: \.self) { g in
                    Text(g)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(telemetry.gear == g ? .black : .white.opacity(0.4))
                        .frame(width: 26, height: 26)
                        .background(telemetry.gear == g ? Color.white : Color.clear)
                        .clipShape(Circle())
                }
            }

            Spacer()

            // Speed Limit Sign
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.black, lineWidth: 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white))
                        .frame(width: 32, height: 40)

                    VStack(spacing: 0) {
                        Text("LIMIT")
                            .font(.system(size: 6, weight: .heavy))
                            .foregroundColor(.black)
                        Text("65")
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(.black)
                    }
                }

                Text("GPS Speed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.04, green: 0.05, blue: 0.09))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
    }

    // MARK: - Right Instrument: Compass Heading & Telemetry

    private var rightGaugeView: some View {
        VStack(spacing: 14) {
            // Turn Signal Right & Safety Status
            HStack(spacing: 12) {
                Image(systemName: "seatbelt.fill")
                    .font(.system(size: 14))
                    .foregroundColor(telemetry.seatbeltFastened ? .green : .red)

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14))
                    .foregroundColor(.cyan)

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(telemetry.turnSignal == .right ? .green : .gray.opacity(0.3))
            }

            Spacer()

            // Digital Compass Heading
            VStack(spacing: 2) {
                Text("\(Int(location.currentHeadingDegrees))°")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                Text(headingName(for: location.currentHeadingDegrees))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
            }

            // Tachometer Bar
            VStack(spacing: 4) {
                HStack {
                    Text("TACH")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(Int(telemetry.rpm)) RPM")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(min(1.0, telemetry.rpm / 8000.0)))
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 8)

            Spacer()

            // EV Battery / Fuel Level
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
                Text("\(Int(telemetry.batteryPercent * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Text("•")
                    .foregroundColor(.gray)

                Text("\(telemetry.rangeMiles) mi")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.04, green: 0.05, blue: 0.09))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
    }

    // MARK: - Compact Portrait Gauges

    private var leftGaugeCompact: some View {
        HStack {
            let speedMph = location.currentSpeedMPH > 0 ? location.currentSpeedMPH : telemetry.speedMph
            let displaySpeed = isMetric ? speedMph * 1.60934 : speedMph
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(displaySpeed))")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(isMetric ? "KM/H" : "MPH")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.cyan)
            }
            Spacer()
            Text(telemetry.gear)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.15))
                .clipShape(Circle())
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    private var rightGaugeCompact: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(location.currentHeadingDegrees))°")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(headingName(for: location.currentHeadingDegrees))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.cyan)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("⚡ \(Int(telemetry.batteryPercent * 100))%")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.green)
                Text("\(telemetry.rangeMiles) mi")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    private func headingName(for degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5).truncatingRemainder(dividingBy: 360) / 45.0)
        return directions[max(0, min(directions.count - 1, index))]
    }
}
