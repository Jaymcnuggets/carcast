//
//  CarPlayActiveScreenView.swift
//  DrivingMode
//
//  Authentic Apple CarPlay live receiver display:
//  Displays the genuine decoded H.264 video stream from iOS (carplayd)
//  with normalized multi-touch input forwarding back to the iPhone.
//

import SwiftUI
import AVFoundation

public struct CarPlayActiveScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager = CarPlayManager.shared
    @ObservedObject var config = DrivingModeConfig.shared
    @ObservedObject var dashcam = DashcamManager.shared

    @State private var touchIndicatorPoint: CGPoint? = nil
    public var onReturnToMenu: (() -> Void)? = nil

    public init(onReturnToMenu: (() -> Void)? = nil) {
        self.onReturnToMenu = onReturnToMenu
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Hardware-accelerated Apple CarPlay H.264 video layer
                // Fills 100% of the screen height edge-to-edge
                RawVideoCanvasView(onTouchPoint: { pt in
                    withAnimation(.easeOut(duration: 0.15)) {
                        touchIndicatorPoint = pt
                    }
                })
                .frame(width: geo.size.width, height: geo.size.height)
                .ignoresSafeArea(.all)

                // Touch feedback indicator
                if let pt = touchIndicatorPoint {
                    Circle()
                        .stroke(Color.white.opacity(0.85), lineWidth: 2)
                        .background(Circle().fill(Color.white.opacity(0.35)))
                        .frame(width: 44, height: 44)
                        .position(pt)
                        .allowsHitTesting(false)
                }

                // Top Controls & Status Bar
                VStack {
                    HStack {
                        // Navigation & Dashcam quick controls
                        HStack(spacing: 8) {
                            // Return to Main Menu
                            Button {
                                onReturnToMenu?()
                                dismiss()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("MENU")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.65))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                )
                            }

                            // Always-visible Dashcam controls in CarPlay top bar
                            Button {
                                if dashcam.isRecording {
                                    dashcam.stopRecording()
                                    config.isDashcamEnabled = false
                                } else {
                                    config.isDashcamEnabled = true
                                    dashcam.startRecording(withAudio: config.isDashcamAudioEnabled)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(dashcam.isRecording ? Color.red : (dashcam.isStarting ? Color.yellow : Color.gray.opacity(0.8)))
                                        .frame(width: 8, height: 8)
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(dashcam.isRecording ? "DASHCAM REC" : (dashcam.isStarting ? "STARTING…" : "START DASHCAM"))
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(dashcam.isRecording ? Color.red.opacity(0.4) : (dashcam.isStarting ? Color.yellow.opacity(0.3) : Color.black.opacity(0.65)))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(dashcam.isRecording ? Color.red.opacity(0.7) : Color.white.opacity(0.2), lineWidth: 1)
                                )
                            }

                            if dashcam.isRecording {
                                Button {
                                    dashcam.saveCurrentEvent(reason: "CarPlay Screen")
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                        Text("LOCK CLIP")
                                    }
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.yellow)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.65))
                                    .cornerRadius(12)
                                }
                            }
                        }
                        .padding(.leading, 20)
                        .padding(.top, 10)

                        Spacer()

                        HStack(spacing: 6) {
                            Circle()
                                .fill(manager.isStreamingActive ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text("CarPlay \(manager.isStreamingActive ? "Live" : "Waiting") (\(manager.totalFramesReceived) frames)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                            Text("•")
                                .foregroundColor(.white.opacity(0.4))
                            Text(config.audioRoutingMode == .airPlayInBand ? "IN-BAND AUDIO" : "BT PASSTHROUGH")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(config.audioRoutingMode == .airPlayInBand ? .cyan : .yellow)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.65))
                        .cornerRadius(12)
                        .padding(.trailing, 20)
                        .padding(.top, 10)
                    }
                    Spacer()
                }

                // Floating Dashcam PiP Viewfinder
                DashcamPiPOverlay()

                // If stream is waiting or initializing, show clean subtle status
                if !manager.isStreamingActive {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        Text("Connecting to CarPlay…")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        Text("\(manager.state.rawValue) (frames: \(manager.totalFramesReceived))")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                        Button("Restart Session") {
                            manager.stopReceiver()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                manager.startReceiver()
                            }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 1.0))
                        .padding(.top, 4)
                    }
                    .padding(20)
                    .background(Color.black.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .ignoresSafeArea(.all)
        }
        .ignoresSafeArea(.all)
        #if os(iOS)
        .statusBarHidden(true)
        #endif
        .onAppear {
            if manager.state == .idle {
                manager.startReceiver()
            }
            if config.isDashcamEnabled && !dashcam.isRecording {
                dashcam.startRecording(withAudio: config.isDashcamAudioEnabled)
            }
            SteeringWheelRemoteService.shared.onEmergencySavePressed = {
                dashcam.saveCurrentEvent(reason: "Steering Wheel Remote")
            }
            SteeringWheelRemoteService.shared.onHomePressed = {
                manager.sendHomeButtonPress()
            }
        }
        .onChange(of: manager.isStreamingActive) { active in
            if !active {
                dismiss()
            }
        }
    }
}
