//
//  CarPlayActiveScreenView.swift
//  CarCast
//
//  Full screen CarPlay video presentation with interactive floating controls.
//

import SwiftUI

public struct CarPlayActiveScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager = CarPlayManager.shared
    @ObservedObject var config = CarCastConfig.shared
    @State private var showControlsOverlay: Bool = true
    @State private var showSplitCluster: Bool = false
    @State private var controlsTimer: Timer?

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if showSplitCluster && config.carPlayUltraEnabled {
                    // Split view: CarPlay main on left/top, Ultra cluster on right/bottom
                    HStack(spacing: 0) {
                        VideoCanvasView()
                            .frame(width: geo.size.width * 0.65)
                        CarPlayUltraClusterView()
                            .frame(width: geo.size.width * 0.35)
                    }
                } else {
                    VideoCanvasView()
                        .ignoresSafeArea(config.avoidNotch ? [] : .all)
                }

                // Floating HUD Controls
                if showControlsOverlay {
                    VStack {
                        HStack(spacing: 16) {
                            // Car OEM Brand Logo button (returns to CarCast car screen)
                            Button {
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "car.fill")
                                        .font(.system(size: 16, weight: .bold))
                                    Text(config.customLogoLabel.isEmpty ? (CarBrandCatalog.shared.brand(for: config.selectedBrandId)?.oemLabel ?? "CAR") : config.customLogoLabel)
                                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            }

                            Spacer()

                            // Ultra Cluster Toggle
                            if config.carPlayUltraEnabled {
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        showSplitCluster.toggle()
                                    }
                                } label: {
                                    Image(systemName: showSplitCluster ? "gauge.with.needle.fill" : "gauge.with.needle")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(showSplitCluster ? .cyan : .white)
                                        .padding(10)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                }
                            }

                            // CarPlay Home Button
                            Button {
                                manager.sendHomeButtonPress()
                            } label: {
                                Image(systemName: "circle.grid.2x2.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }

                            // Disconnect Button
                            Button {
                                manager.stopReceiver()
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.red)
                                    .padding(10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                        Spacer()
                    }
                    .transition(.opacity)
                }
            }
            .onTapGesture(count: 2) {
                withAnimation {
                    showControlsOverlay.toggle()
                }
            }
        }
    }
}
