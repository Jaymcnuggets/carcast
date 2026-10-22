//
//  VideoCanvasView.swift
//  CarCast
//
//  Hardware-accelerated video canvas with touch forwarding for iOS and macOS,
//  displaying genuine Apple CarPlay video frames via AVSampleBufferDisplayLayer,
//  with authentic receiver telemetry and standby status when waiting for incoming streams.
//

import SwiftUI
import AVFoundation
import CoreMedia
import Combine

public struct VideoCanvasView: View {
    @ObservedObject var manager = CarPlayManager.shared

    public init() {}

    public var body: some View {
        ZStack {
            if manager.lastSampleBuffer == nil {
                AirPlayReceiverStandbyView()
            }

            RawVideoCanvasView()
                .opacity(manager.lastSampleBuffer == nil ? 0 : 1)
        }
        .onAppear {
            if manager.state == .idle || manager.state == .error {
                manager.startReceiver()
            }
        }
    }
}

// MARK: - Authentic AirPlay & CarPlay Receiver Standby View

public struct AirPlayReceiverStandbyView: View {
    @ObservedObject var manager = CarPlayManager.shared
    @ObservedObject var config = CarCastConfig.shared
    @State private var radarPulse: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            // Dark automotive glass background
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.07, blue: 0.12),
                    Color(red: 0.02, green: 0.03, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle radar circles
            ZStack {
                Circle()
                    .stroke(Color.cyan.opacity(radarPulse ? 0.0 : 0.35), lineWidth: 1.5)
                    .frame(width: radarPulse ? 380 : 100, height: radarPulse ? 380 : 100)
                    .animation(.easeOut(duration: 2.5).repeatForever(autoreverses: false), value: radarPulse)

                Circle()
                    .stroke(Color.cyan.opacity(radarPulse ? 0.0 : 0.25), lineWidth: 1)
                    .frame(width: radarPulse ? 480 : 160, height: radarPulse ? 480 : 160)
                    .animation(.easeOut(duration: 2.5).delay(0.6).repeatForever(autoreverses: false), value: radarPulse)
            }
            .clipped()

            VStack(spacing: 14) {
                // Vehicle Brand & Name
                HStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.cyan)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(config.carName)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text("Apple CarPlay Wireless Receiver")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.cyan.opacity(0.85))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.cyan.opacity(0.3), lineWidth: 1))

                // Status Box
                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(manager.state == .streaming ? Color.green : Color.yellow)
                            .frame(width: 8, height: 8)
                        Text(manager.state == .streaming ? "STREAMING ACTIVE" : "WAITING FOR IPHONE CONNECTION")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }

                    // Network & Ports Specs
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("BONJOUR")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.gray)
                            Text("_airplay._tcp")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                        }

                        Divider().frame(height: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("RTSP")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.gray)
                            Text("Port 7000")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                        }

                        Divider().frame(height: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("H.264 VIDEO")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.gray)
                            Text("Port 7100")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))

                // Connection steps
                HStack(spacing: 12) {
                    Label("1. Settings > CarPlay", systemImage: "iphone")
                    Label("2. Tap \"\(config.carName)\"", systemImage: "car.fill")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 16)
        }
        .onAppear {
            radarPulse = true
            if manager.state == .idle || manager.state == .error {
                manager.startReceiver()
            }
        }
    }
}

// MARK: - Native Video Stream Layer

#if canImport(UIKit)
import UIKit

public struct RawVideoCanvasView: UIViewRepresentable {
    @ObservedObject var manager = CarPlayManager.shared

    public init() {}

    public func makeUIView(context: Context) -> SampleBufferContainerView {
        let view = SampleBufferContainerView()
        view.onTouchEvent = { action, normX, normY in
            CarPlayManager.shared.sendTouchEvent(action: action, x: normX, y: normY)
        }
        return view
    }

    public func updateUIView(_ uiView: SampleBufferContainerView, context: Context) {
        if let buffer = manager.lastSampleBuffer {
            uiView.enqueue(buffer)
        }
    }
}

public final class SampleBufferContainerView: UIView {
    public var onTouchEvent: ((Int, Double, Double) -> Void)?

    private let sampleLayer = AVSampleBufferDisplayLayer()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
        setupTouches()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
        setupTouches()
    }

    private func setupLayer() {
        backgroundColor = .clear
        sampleLayer.videoGravity = .resizeAspect
        layer.addSublayer(sampleLayer)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        sampleLayer.frame = bounds
    }

    public func enqueue(_ buffer: CMSampleBuffer) {
        if sampleLayer.status == .failed {
            sampleLayer.flush()
        }
        if sampleLayer.isReadyForMoreMediaData {
            sampleLayer.enqueue(buffer)
        }
    }

    private func setupTouches() {
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = true
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)
        let normX = Double(loc.x / max(1, bounds.width))
        let normY = Double(loc.y / max(1, bounds.height))
        onTouchEvent?(1, normX, normY)
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)
        let normX = Double(loc.x / max(1, bounds.width))
        let normY = Double(loc.y / max(1, bounds.height))
        onTouchEvent?(2, normX, normY)
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)
        let normX = Double(loc.x / max(1, bounds.width))
        let normY = Double(loc.y / max(1, bounds.height))
        onTouchEvent?(0, normX, normY)
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}

#elseif canImport(AppKit)
import AppKit

public struct RawVideoCanvasView: NSViewRepresentable {
    @ObservedObject var manager = CarPlayManager.shared

    public init() {}

    public func makeNSView(context: Context) -> SampleBufferContainerView {
        let view = SampleBufferContainerView()
        view.onTouchEvent = { action, normX, normY in
            CarPlayManager.shared.sendTouchEvent(action: action, x: normX, y: normY)
        }
        return view
    }

    public func updateNSView(_ nsView: SampleBufferContainerView, context: Context) {
        if let buffer = manager.lastSampleBuffer {
            nsView.enqueue(buffer)
        }
    }
}

public final class SampleBufferContainerView: NSView {
    public var onTouchEvent: ((Int, Double, Double) -> Void)?

    private let sampleLayer = AVSampleBufferDisplayLayer()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        sampleLayer.videoGravity = .resizeAspect
        layer?.addSublayer(sampleLayer)
    }

    public override func layout() {
        super.layout()
        sampleLayer.frame = bounds
    }

    public func enqueue(_ buffer: CMSampleBuffer) {
        if sampleLayer.status == .failed {
            sampleLayer.flush()
        }
        if sampleLayer.isReadyForMoreMediaData {
            sampleLayer.enqueue(buffer)
        }
    }

    public override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let normX = Double(loc.x / max(1, bounds.width))
        let normY = Double(1.0 - (loc.y / max(1, bounds.height)))
        onTouchEvent?(1, normX, normY)
    }

    public override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let normX = Double(loc.x / max(1, bounds.width))
        let normY = Double(1.0 - (loc.y / max(1, bounds.height)))
        onTouchEvent?(2, normX, normY)
    }

    public override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let normX = Double(loc.x / max(1, bounds.width))
        let normY = Double(1.0 - (loc.y / max(1, bounds.height)))
        onTouchEvent?(0, normX, normY)
    }
}
#endif
