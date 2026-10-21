//
//  VideoCanvasView.swift
//  CarCast
//
//  Hardware-accelerated video canvas with touch forwarding for iOS and macOS,
//  featuring an authentic interactive CarPlay desktop when idle or in local mode.
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
            CarPlayHomeDesktopView()

            RawVideoCanvasView()
                .opacity(manager.lastSampleBuffer == nil ? 0 : 1)
        }
    }
}

// MARK: - Authentic Interactive CarPlay Desktop

public struct CarPlayHomeDesktopView: View {
    @ObservedObject var config = CarCastConfig.shared
    @ObservedObject var telemetry = VehicleTelemetry.shared
    @State private var activeApp: String? = nil
    @State private var isPlaying: Bool = true
    @State private var currentTimeStr: String = ""

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // CarPlay Wallpaper Mesh
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.09, blue: 0.16),
                        Color(red: 0.03, green: 0.04, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                HStack(spacing: 0) {
                    if config.drivingPosition == .leftHandDrive {
                        dockBar
                    }

                    // Main Viewport (App Grid or Active App)
                    ZStack {
                        if let app = activeApp {
                            activeAppView(for: app)
                                .transition(.opacity)
                        } else {
                            appGridView(in: geo.size)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if config.drivingPosition == .rightHandDrive {
                        dockBar
                    }
                }
            }
        }
        .onAppear {
            updateTime()
        }
        .onReceive(timer) { _ in
            updateTime()
        }
    }

    private func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        currentTimeStr = formatter.string(from: Date())
    }

    // MARK: - Side Dock

    private var dockBar: some View {
        VStack(spacing: 16) {
            // Time & Status
            VStack(spacing: 3) {
                Text(currentTimeStr.isEmpty ? "9:41" : currentTimeStr)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                HStack(spacing: 3) {
                    Image(systemName: "cellularbars")
                        .font(.system(size: 9))
                    Image(systemName: "wifi")
                        .font(.system(size: 9))
                    Image(systemName: "battery.100")
                        .font(.system(size: 9))
                }
                .foregroundColor(.white.opacity(0.8))
            }
            .padding(.top, 14)

            Spacer()

            // Recent App Shortcuts
            VStack(spacing: 14) {
                dockAppIcon(icon: "phone.fill", color: .green, name: "phone")
                dockAppIcon(icon: "map.fill", color: .blue, name: "maps")
                dockAppIcon(icon: "music.note", color: .red, name: "music")
            }

            Spacer()

            // CarPlay Home Button
            Button {
                withAnimation(.spring(response: 0.3)) {
                    activeApp = nil
                }
                CarPlayManager.shared.sendHomeButtonPress()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.6), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                }
                .padding(.bottom, 14)
            }
        }
        .frame(width: 64)
        .background(Color.black.opacity(0.45))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1),
            alignment: config.drivingPosition == .leftHandDrive ? .trailing : .leading
        )
    }

    private func dockAppIcon(icon: String, color: Color, name: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                activeApp = name
            }
            CarPlayManager.shared.sendTouchEvent(action: 1, x: 0.5, y: 0.5)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color)
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            .shadow(color: color.opacity(0.3), radius: 4, x: 0, y: 2)
        }
    }

    // MARK: - App Grid

    private func appGridView(in size: CGSize) -> some View {
        let brand = CarBrandCatalog.shared.brand(for: config.selectedBrandId)
        let brandName = brand?.title ?? "Vehicle"

        let apps: [(name: String, label: String, icon: String, color: Color)] = [
            ("phone", "Phone", "phone.fill", .green),
            ("music", "Music", "music.note", .red),
            ("maps", "Maps", "map.fill", .blue),
            ("messages", "Messages", "message.fill", .green),
            ("nowplaying", "Now Playing", "play.circle.fill", .pink),
            ("car", brandName, "car.fill", .cyan),
            ("podcasts", "Podcasts", "antenna.radiowaves.left.and.right", .purple),
            ("settings", "Settings", "gearshape.fill", .gray)
        ]

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 4), spacing: 22) {
            ForEach(apps, id: \.name) { app in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        activeApp = app.name
                    }
                    CarPlayManager.shared.sendTouchEvent(action: 1, x: 0.5, y: 0.5)
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(app.color)
                                .frame(width: 62, height: 62)
                            Image(systemName: app.icon)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .shadow(color: app.color.opacity(0.35), radius: 6, x: 0, y: 3)

                        Text(app.label)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 24)
    }

    // MARK: - Active App Screens

    @ViewBuilder
    private func activeAppView(for app: String) -> some View {
        switch app {
        case "music", "nowplaying":
            musicAppView
        case "maps":
            mapsAppView
        case "phone":
            phoneAppView
        default:
            genericAppView(title: app.capitalized)
        }
    }

    private var musicAppView: some View {
        HStack(spacing: 32) {
            // Album Artwork
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.15, green: 0.18, blue: 0.28))
                    .frame(width: 140, height: 140)
                Image(systemName: "music.note.list")
                    .font(.system(size: 52))
                    .foregroundColor(.cyan)
            }
            .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 6)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(telemetry.currentTrackTitle)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(telemetry.currentArtist) — \(telemetry.currentAlbum)")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                }

                // Progress Bar
                VStack(spacing: 4) {
                    GeometryReader { pGeo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.15))
                            Capsule().fill(Color.cyan)
                                .frame(width: pGeo.size.width * CGFloat(telemetry.trackProgress))
                        }
                    }
                    .frame(height: 5)
                }

                // Playback Controls
                HStack(spacing: 24) {
                    Button {
                        CarPlayManager.shared.sendTouchEvent(action: 1, x: 0.4, y: 0.7)
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }

                    Button {
                        isPlaying.toggle()
                        CarPlayManager.shared.sendTouchEvent(action: 1, x: 0.5, y: 0.7)
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 38))
                            .foregroundColor(.cyan)
                    }

                    Button {
                        CarPlayManager.shared.sendTouchEvent(action: 1, x: 0.6, y: 0.7)
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .padding(28)
    }

    private var mapsAppView: some View {
        ZStack {
            // Stylized GPS Map Grid
            Color(red: 0.08, green: 0.12, blue: 0.16)

            VStack {
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.turn.up.right")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("In 500 feet")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.green)
                            Text("Turn right onto Grand Avenue")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(14)
                    .background(Color.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Spacer()
                }
                .padding(20)

                Spacer()
            }
        }
    }

    private var phoneAppView: some View {
        VStack(spacing: 12) {
            Text("Phone")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Hands-free wireless phone calls active via CarPlay")
                .font(.system(size: 13))
                .foregroundColor(.gray)
        }
    }

    private func genericAppView(title: String) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("App active in simulated CarPlay session")
                .font(.system(size: 13))
                .foregroundColor(.gray)
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
