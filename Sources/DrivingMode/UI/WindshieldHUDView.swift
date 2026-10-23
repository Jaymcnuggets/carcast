//
//  WindshieldHUDView.swift
//  DrivingMode
//
//  High-contrast pitch OLED windshield reflection display.
//  Inverts horizontally to project cleanly onto car glass at night without glare.
//

import SwiftUI

public struct WindshieldHUDView: View {
    @ObservedObject var config = DrivingModeConfig.shared
    @ObservedObject var telemetry = VehicleTelemetry.shared
    @ObservedObject var dashcam = DashcamManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showSavedAlert: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            // Pitch OLED pure black canvas to prevent windshield glare
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                // Top controls bar
                HStack {
                    Button {
                        config.isHUDMirrored.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                            Text(config.isHUDMirrored ? "MIRROR ON" : "MIRROR OFF")
                        }
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(8)
                    }

                    Spacer()

                    if dashcam.isRecording {
                        HStack(spacing: 6) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text("DASHCAM REC")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(6)
                    }

                    Spacer()

                    Button {
                        config.isHUDModeEnabled = false
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.65))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)

                Spacer()

                // Primary Speedometer Display
                VStack(spacing: -10) {
                    Text("\(Int(telemetry.speedMph))")
                        .font(.system(size: 130, weight: .black, design: .rounded))
                        .foregroundColor(.green)
                    Text("MPH")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(.green.opacity(0.85))
                }

                // Turn-by-Turn / Telemetry / Media Banner
                if !telemetry.currentTrackTitle.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "music.note")
                            .font(.system(size: 18))
                            .foregroundColor(.cyan)
                        Text("\(telemetry.currentTrackTitle) — \(telemetry.currentArtist)")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                }

                Spacer()

                // Bottom Action: Emergency Save
                HStack(spacing: 16) {
                    Button {
                        dashcam.saveCurrentEvent(reason: "HUD Button")
                        withAnimation {
                            showSavedAlert = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation {
                                showSavedAlert = false
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: showSavedAlert ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                            Text(showSavedAlert ? "CLIP SAVED TO EMERGENCY" : "SAVE DASHCAM CLIP")
                        }
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(showSavedAlert ? .green : .yellow)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background((showSavedAlert ? Color.green : Color.yellow).opacity(0.18))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke((showSavedAlert ? Color.green : Color.yellow).opacity(0.4), lineWidth: 1)
                        )
                    }
                }
                .padding(.bottom, 24)
            }
        }
        // Optical reflection transform: flips horizontally so reflection on glass is correct
        .scaleEffect(x: config.isHUDMirrored ? -1.0 : 1.0, y: 1.0)
    }
}
