//
//  VideoCanvasView.swift
//  DrivingMode
//
//  Hardware-accelerated video canvas with touch forwarding for iOS and macOS,
//  displaying genuine Apple CarPlay video frames via AVSampleBufferDisplayLayer.
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
            Color.black.ignoresSafeArea()
            RawVideoCanvasView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Native Video Stream Layer

#if canImport(UIKit)
import UIKit

public struct RawVideoCanvasView: UIViewRepresentable {
    @ObservedObject var manager = CarPlayManager.shared
    @ObservedObject var config = DrivingModeConfig.shared
    public var onTouchPoint: ((CGPoint?) -> Void)? = nil

    public init(onTouchPoint: ((CGPoint?) -> Void)? = nil) {
        self.onTouchPoint = onTouchPoint
    }

    public func makeUIView(context: Context) -> SampleBufferContainerView {
        let view = SampleBufferContainerView()
        view.onTouchEvent = { action, normX, normY in
            CarPlayManager.shared.sendTouchEvent(action: action, x: normX, y: normY)
        }
        view.onRawTouchPoint = { pt in
            self.onTouchPoint?(pt)
        }
        return view
    }

    public func updateUIView(_ uiView: SampleBufferContainerView, context: Context) {
        if !manager.isStreamingActive {
            uiView.flush()
        }
        uiView.updateVideoGravity()
        uiView.setNeedsLayout()
    }
}

public final class SampleBufferContainerView: UIView {
    public let sampleLayer = AVSampleBufferDisplayLayer()

    public var onTouchEvent: ((Int, Double, Double) -> Void)?
    public var onRawTouchPoint: ((CGPoint?) -> Void)?

    #if targetEnvironment(simulator)
    private let simulatorPreviewView = UIImageView()
    private var simulatorTouchStart: CGPoint? = nil
    private var currentSimulatorScreen: String = "carplay_screen_grid"

    private func loadSimulatorScreen(_ name: String) {
        currentSimulatorScreen = name
        NSLog("[DrivingMode][Touch] Switching simulator screen to: %@", name)
        if let resourcePath = Bundle.main.resourcePath {
            let p1 = (resourcePath as NSString).appendingPathComponent("CarPlayScreens/\(name).png")
            let p2 = (resourcePath as NSString).appendingPathComponent("AppIcon/\(name).png")
            let p3 = (resourcePath as NSString).appendingPathComponent("\(name).png")
            for p in [p1, p2, p3] {
                if let img = UIImage(contentsOfFile: p) {
                    UIView.transition(with: simulatorPreviewView, duration: 0.12, options: .transitionCrossDissolve, animations: {
                        self.simulatorPreviewView.image = img
                    })
                    return
                }
            }
        }
        if let img = UIImage(named: name) {
            simulatorPreviewView.image = img
        }
    }

    private var lastSimulatorTouchTime: TimeInterval = 0

    private func handleSimulatorTouch(loc: CGPoint, normX: Double, normY: Double) {
        let now = CACurrentMediaTime()
        guard now - lastSimulatorTouchTime > 0.15 else { return }
        lastSimulatorTouchTime = now
        NSLog("[DrivingMode][Touch] handleSimulatorTouch: norm=(%.3f, %.3f), screen=%@", normX, normY, currentSimulatorScreen)
        if let start = simulatorTouchStart {
            let dx = loc.x - start.x
            let dy = loc.y - start.y
            if abs(dx) > 30 && abs(dx) > abs(dy) {
                // Horizontal swipe between Dashboard and App Grid
                if dx < 0 {
                    if currentSimulatorScreen == "carplay_screen_dashboard" {
                        loadSimulatorScreen("carplay_screen_grid")
                    }
                } else {
                    if currentSimulatorScreen == "carplay_screen_grid" {
                        loadSimulatorScreen("carplay_screen_dashboard")
                    }
                }
                simulatorTouchStart = nil
                return
            }
        }
        simulatorTouchStart = nil

        // Left Dock (normX < 0.14)
        if normX < 0.14 {
            if normY >= 0.18 && normY < 0.38 {
                // Top Dock App: Maps
                loadSimulatorScreen("carplay_screen_maps")
            } else if normY >= 0.38 && normY < 0.58 {
                // Middle Dock App: Music / Now Playing
                loadSimulatorScreen("carplay_screen_music")
            } else if normY >= 0.58 && normY < 0.76 {
                // Bottom Dock App: Phone
                loadSimulatorScreen("carplay_screen_phone")
            } else if normY >= 0.76 {
                // Home / App Grid toggle button
                if currentSimulatorScreen == "carplay_screen_grid" {
                    loadSimulatorScreen("carplay_screen_dashboard")
                } else {
                    loadSimulatorScreen("carplay_screen_grid")
                }
            }
            return
        }

        // Main app area taps
        if currentSimulatorScreen == "carplay_screen_grid" {
            if normY >= 0.12 && normY <= 0.50 {
                // Row 1 of App Grid
                if normX >= 0.14 && normX < 0.35 {
                    loadSimulatorScreen("carplay_screen_phone")
                } else if normX >= 0.35 && normX < 0.55 {
                    loadSimulatorScreen("carplay_screen_music")
                } else if normX >= 0.55 && normX < 0.75 {
                    loadSimulatorScreen("carplay_screen_maps")
                } else if normX >= 0.75 {
                    loadSimulatorScreen("carplay_screen_phone")
                }
            } else if normY > 0.50 && normY <= 0.85 {
                // Row 2 of App Grid
                if normX >= 0.14 && normX < 0.35 {
                    loadSimulatorScreen("carplay_screen_music")
                } else if normX >= 0.35 && normX < 0.55 {
                    loadSimulatorScreen("carplay_screen_music")
                } else if normX >= 0.55 && normX < 0.75 {
                    loadSimulatorScreen("carplay_screen_dashboard")
                } else if normX >= 0.75 {
                    loadSimulatorScreen("carplay_screen_dashboard")
                }
            } else if normY > 0.85 {
                loadSimulatorScreen("carplay_screen_dashboard")
            }
        } else if currentSimulatorScreen == "carplay_screen_dashboard" {
            if normX < 0.58 {
                // Left big tile: Maps
                loadSimulatorScreen("carplay_screen_maps")
            } else {
                // Right tiles: Upper = Grid, Lower = Music
                if normY < 0.50 {
                    loadSimulatorScreen("carplay_screen_grid")
                } else {
                    loadSimulatorScreen("carplay_screen_music")
                }
            }
        } else {
            // Any tap in top bar or navigation returns to grid
            if normY < 0.12 {
                loadSimulatorScreen("carplay_screen_grid")
            }
        }
    }
    #endif

    public func flush() {
        sampleLayer.flush()
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
        setupTouches()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
        setupTouches()
    }

    private func setupLayer() {
        backgroundColor = .black
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sampleLayer.videoGravity = .resizeAspect
        sampleLayer.backgroundColor = UIColor.black.cgColor
        sampleLayer.preventsDisplaySleepDuringVideoPlayback = true
        layer.addSublayer(sampleLayer)
        updateVideoGravity()

        #if targetEnvironment(simulator)
        simulatorPreviewView.contentMode = DrivingModeConfig.shared.fillScreenEdgeToEdge ? .scaleToFill : .scaleAspectFit
        simulatorPreviewView.clipsToBounds = true
        simulatorPreviewView.isUserInteractionEnabled = false
        addSubview(simulatorPreviewView)
        loadSimulatorScreen("carplay_screen_grid")
        #endif

        VideoFrameBus.shared.add(self) { [weak self] buffer in
            self?.enqueue(buffer)
        }
    }

    deinit {
        VideoFrameBus.shared.remove(self)
    }

    private func setupTouches() {
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = true
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let geometry = computeRenderGeometry()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sampleLayer.frame = geometry.frame
        CATransaction.commit()
        updateVideoGravity()
        #if targetEnvironment(simulator)
        simulatorPreviewView.frame = geometry.frame
        #endif
    }

    public func updateVideoGravity() {
        let isFill = DrivingModeConfig.shared.fillScreenEdgeToEdge
        if isFill {
            sampleLayer.videoGravity = .resize
            #if targetEnvironment(simulator)
            simulatorPreviewView.contentMode = .scaleToFill
            #endif
        } else {
            sampleLayer.videoGravity = .resizeAspect
            #if targetEnvironment(simulator)
            simulatorPreviewView.contentMode = .scaleAspectFit
            #endif
        }
    }

    private func computeRenderGeometry() -> (frame: CGRect, offsetX: CGFloat, offsetY: CGFloat, renderW: CGFloat, renderH: CGFloat) {
        let viewW = bounds.width
        let viewH = bounds.height
        guard viewW > 0, viewH > 0 else {
            return (bounds, 0, 0, viewW, viewH)
        }

        if DrivingModeConfig.shared.fillScreenEdgeToEdge {
            return (bounds, 0, 0, viewW, viewH)
        }

        let streamW: Double
        let streamH: Double
        #if targetEnvironment(simulator)
        if let imgSize = simulatorPreviewView.image?.size, imgSize.width > 0, imgSize.height > 0 {
            streamW = Double(imgSize.width)
            streamH = Double(imgSize.height)
        } else {
            streamW = 1344.0
            streamH = 720.0
        }
        #else
        if CarPlayManager.shared.currentStreamResolution.width > 0 && CarPlayManager.shared.currentStreamResolution.height > 0 {
            streamW = Double(CarPlayManager.shared.currentStreamResolution.width)
            streamH = Double(CarPlayManager.shared.currentStreamResolution.height)
        } else {
            streamW = 1920.0
            streamH = 1080.0
        }
        #endif

        let streamAspect = streamW / streamH
        let viewAspect = Double(viewW / viewH)

        var renderW = viewW
        var renderH = viewH
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0

        if viewAspect >= streamAspect {
            // View is wider than stream -> pillarboxed (bars on left/right)
            renderH = viewH
            renderW = CGFloat(Double(viewH) * streamAspect)
            offsetX = (viewW - renderW) / 2.0
            offsetY = 0
        } else {
            // View is taller than stream -> letterboxed:
            // BOTTOM JUSTIFIED: CarPlay rests flush against bottom edge.
            // Entire letterbox gap sits at the top for enlarged automotive controls.
            renderW = viewW
            renderH = CGFloat(Double(viewW) / streamAspect)
            offsetX = 0
            offsetY = viewH - renderH
        }

        let frame = CGRect(x: offsetX, y: offsetY, width: renderW, height: renderH)
        return (frame, offsetX, offsetY, renderW, renderH)
    }

    private var lastTouchBeganTime: TimeInterval = 0

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        lastTouchBeganTime = CACurrentMediaTime()
        let loc = touch.location(in: self)
        #if targetEnvironment(simulator)
        simulatorTouchStart = loc
        #endif
        onRawTouchPoint?(loc)
        let (normX, normY) = normalizedPoint(for: loc)
        onTouchEvent?(1, normX, normY)
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)
        onRawTouchPoint?(loc)
        let (normX, normY) = normalizedPoint(for: loc)
        onTouchEvent?(2, normX, normY)
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)
        let (normX, normY) = normalizedPoint(for: loc)
        #if targetEnvironment(simulator)
        handleSimulatorTouch(loc: loc, normX: normX, normY: normY)
        #endif
        let elapsed = CACurrentMediaTime() - lastTouchBeganTime
        let remaining = max(0.06 - elapsed, 0.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            self?.onTouchEvent?(0, normX, normY)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining + 0.15) { [weak self] in
            self?.onRawTouchPoint?(nil)
        }
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        #if targetEnvironment(simulator)
        simulatorTouchStart = nil
        #endif
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)
        let (normX, normY) = normalizedPoint(for: loc)
        onTouchEvent?(0, normX, normY)
        onRawTouchPoint?(nil)
    }

    private func normalizedPoint(for loc: CGPoint) -> (Double, Double) {
        let geometry = computeRenderGeometry()
        let renderW = geometry.renderW
        let renderH = geometry.renderH
        let offsetX = geometry.offsetX
        let offsetY = geometry.offsetY

        let normX = min(max(Double((loc.x - offsetX) / max(renderW, 1.0)), 0.0), 1.0)
        let normY = min(max(Double((loc.y - offsetY) / max(renderH, 1.0)), 0.0), 1.0)
        return (normX, normY)
    }

    private var enqueuedCount = 0

    public func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if sampleLayer.status == .failed {
            writeAppLog("[VideoView] AVSampleBufferDisplayLayer failed: \(String(describing: sampleLayer.error)) — flushing & requesting keyframe")
            sampleLayer.flush()
            CarPlayManager.shared.requestKeyFrame()
        }
        enqueuedCount += 1
        if enqueuedCount <= 5 || enqueuedCount % 60 == 0 {
            writeAppLog("[VideoView] Enqueued frame #\(enqueuedCount) (status=\(sampleLayer.status.rawValue), bounds=\(bounds.size.width)x\(bounds.size.height))")
            NSLog("[DrivingMode][Video] Enqueued frame #%d (status=%d, bounds=%@)", enqueuedCount, sampleLayer.status.rawValue, NSCoder.string(for: bounds))
        }
        sampleLayer.enqueue(sampleBuffer)
    }
}
#else
public struct RawVideoCanvasView: View {
    public init(onTouchPoint: ((CGPoint?) -> Void)? = nil) {}
    public var body: some View {
        Color.black
    }
}
#endif
