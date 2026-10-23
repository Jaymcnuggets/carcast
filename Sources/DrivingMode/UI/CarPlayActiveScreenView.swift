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

    @State private var touchIndicatorPoint: CGPoint? = nil

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Hardware-accelerated Apple CarPlay H.264 video layer
                RawVideoCanvasView(onTouchPoint: { pt in
                    withAnimation(.easeOut(duration: 0.15)) {
                        touchIndicatorPoint = pt
                    }
                })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(config.avoidNotch ? [] : .all)

                // Touch feedback indicator
                if let pt = touchIndicatorPoint {
                    Circle()
                        .stroke(Color.white.opacity(0.85), lineWidth: 2)
                        .background(Circle().fill(Color.white.opacity(0.35)))
                        .frame(width: 44, height: 44)
                        .position(pt)
                        .allowsHitTesting(false)
                }

                // Live status badge in top trailing corner
                VStack {
                    HStack {
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
                .allowsHitTesting(false)

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
        }
        #if os(iOS)
        .statusBarHidden(true)
        #endif
        .onAppear {
            if manager.state == .idle {
                manager.startReceiver()
            }
        }
        .onChange(of: manager.isStreamingActive) { active in
            if !active {
                dismiss()
            }
        }
    }
}
