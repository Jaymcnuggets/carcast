//
//  CarPlayActiveScreenView.swift
//  CarCast
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
    @ObservedObject var config = CarCastConfig.shared

    @State private var touchIndicatorPoint: CGPoint? = nil

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Hardware-accelerated Apple CarPlay H.264 video layer
                RawVideoCanvasView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(config.avoidNotch ? [] : .all)

                // Optional touch point visualizer for screen recordings
                if config.showTouches, let pt = touchIndicatorPoint {
                    Circle()
                        .fill(Color.white.opacity(0.65))
                        .frame(width: 44, height: 44)
                        .position(pt)
                        .allowsHitTesting(false)
                }

                // If stream is waiting or initializing, show clean subtle status
                if !manager.isStreamingActive {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        Text("Connecting to CarPlay…")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
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
        .onChange(of: manager.isStreamingActive) { active in
            if !active {
                dismiss()
            }
        }
    }
}
