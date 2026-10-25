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

                // Top Controls & Status Bar (Automotive Touch Enclosure)
                VStack(spacing: 0) {
                    topControls(geo: geo)
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
            #if !targetEnvironment(simulator)
            if config.isDashcamEnabled && !dashcam.isRecording {
                dashcam.startRecording(withAudio: config.isDashcamAudioEnabled)
            } else if !dashcam.isRecording {
                dashcam.prewarmPipeline(withAudio: config.isDashcamAudioEnabled)
            }
            #endif
            SteeringWheelRemoteService.shared.onEmergencySavePressed = {
                dashcam.saveCurrentEvent(reason: "Steering Wheel Remote")
            }
            SteeringWheelRemoteService.shared.onHomePressed = {
                manager.sendHomeButtonPress()
            }
        }
        .onDisappear {
            SteeringWheelRemoteService.shared.onEmergencySavePressed = nil
            SteeringWheelRemoteService.shared.onHomePressed = nil
        }
        .onChange(of: manager.isStreamingActive) { _, active in
            if !active {
                dismiss()
            }
        }
    }

    // MARK: - Header Controls Layout

    @ViewBuilder
    private func topControls(geo: GeometryProxy) -> some View {
        let isPortrait = geo.size.width < geo.size.height
        let leadingInset = max(geo.safeAreaInsets.leading, isPortrait ? 18 : 44)
        let trailingInset = max(geo.safeAreaInsets.trailing, isPortrait ? 18 : 44)
        let topInset = max(geo.safeAreaInsets.top, 14)

        if isPortrait {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    menuButton
                    Spacer()
                    statusCluster
                }
                HStack(spacing: 10) {
                    dashcamButton
                    if dashcam.isRecording {
                        lockClipButton
                    }
                    Spacer()
                }
            }
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .padding(.top, topInset)
        } else {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 10) {
                    menuButton
                    dashcamButton
                    if dashcam.isRecording {
                        lockClipButton
                    }
                }

                Spacer()

                statusCluster
            }
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .padding(.top, topInset)
        }
    }

    // MARK: - Subviews

    private var menuButton: some View {
        Button {
            onReturnToMenu?()
            NotificationCenter.default.post(name: .returnToMainMenu, object: nil)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                Text("MENU")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(height: 48)
            .padding(.horizontal, 18)
            .background(Color.black.opacity(0.75))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1.2)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
        }
    }

    private var dashcamButton: some View {
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
                    .fill(dashcam.isRecording ? Color.red : (dashcam.isStarting ? Color.yellow : Color.white.opacity(0.4)))
                    .frame(width: 10, height: 10)

                Image(systemName: dashcam.isRecording ? "record.circle.fill" : "camera.fill")
                    .font(.system(size: 16, weight: .bold))

                Text(dashcam.isRecording ? "DASHCAM REC" : (dashcam.isStarting ? "STARTING…" : "START DASHCAM"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                if dashcam.isRecording {
                    DashcamTimerText(startTime: dashcam.recordingStartTime, fontSize: 13)
                }
            }
            .foregroundColor(.white)
            .frame(height: 48)
            .padding(.horizontal, 18)
            .background(dashcam.isRecording ? Color.red.opacity(0.35) : (dashcam.isStarting ? Color.yellow.opacity(0.25) : Color.black.opacity(0.75)))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(dashcam.isRecording ? Color.red.opacity(0.8) : Color.white.opacity(0.22), lineWidth: 1.2)
            )
            .shadow(color: dashcam.isRecording ? Color.red.opacity(0.3) : Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
        }
    }

    private var lockClipButton: some View {
        Button {
            dashcam.saveCurrentEvent(reason: "CarPlay Screen")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .bold))
                Text("LOCK CLIP")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundColor(.yellow)
            .frame(height: 48)
            .padding(.horizontal, 16)
            .background(Color.yellow.opacity(0.18))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.yellow.opacity(0.7), lineWidth: 1.2)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
        }
    }

    private var statusCluster: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(manager.isStreamingActive ? Color.green : Color.orange)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text("CarPlay \(manager.isStreamingActive ? "Connected" : "Waiting")")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                HStack(spacing: 4) {
                    Text("\(manager.totalFramesReceived) frames")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                    Text(config.audioRoutingMode == .airPlayInBand ? "IN-BAND AUDIO" : "BT PASSTHROUGH")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(config.audioRoutingMode == .airPlayInBand ? .cyan : .yellow)
                }
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 16)
        .background(Color.black.opacity(0.75))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.22), lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
    }
}
