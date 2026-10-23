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
    }
}

public final class SampleBufferContainerView: UIView {
    public override class var layerClass: AnyClass {
        return AVSampleBufferDisplayLayer.self
    }

    public var sampleLayer: AVSampleBufferDisplayLayer {
        return self.layer as! AVSampleBufferDisplayLayer
    }

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
        updateVideoGravity()

        #if targetEnvironment(simulator)
        simulatorPreviewView.contentMode = .scaleToFill
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

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
    }

    @objc private func handleTapGesture(_ recognizer: UITapGestureRecognizer) {
        let loc = recognizer.location(in: self)
        let (normX, normY) = normalizedPoint(for: loc)
        NSLog("[DrivingMode][Touch] TapGesture recognized at (%f, %f) -> norm=(%f, %f)", loc.x, loc.y, normX, normY)
        onRawTouchPoint?(loc)
        #if targetEnvironment(simulator)
        handleSimulatorTouch(loc: loc, normX: normX, normY: normY)
        #endif
        onTouchEvent?(1, normX, normY)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.onTouchEvent?(0, normX, normY)
            self?.onRawTouchPoint?(nil)
        }
    }

    @objc private func handlePanGesture(_ recognizer: UIPanGestureRecognizer) {
        let loc = recognizer.location(in: self)
        let (normX, normY) = normalizedPoint(for: loc)
        switch recognizer.state {
        case .began:
            #if targetEnvironment(simulator)
            simulatorTouchStart = loc
            #endif
            onTouchEvent?(1, normX, normY)
        case .changed:
            onTouchEvent?(2, normX, normY)
        case .ended:
            #if targetEnvironment(simulator)
            handleSimulatorTouch(loc: loc, normX: normX, normY: normY)
            #endif
            onTouchEvent?(0, normX, normY)
        case .cancelled, .failed:
            #if targetEnvironment(simulator)
            simulatorTouchStart = nil
            #endif
            onTouchEvent?(0, normX, normY)
        default:
            break
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        sampleLayer.frame = bounds
        updateVideoGravity()
        #if targetEnvironment(simulator)
        simulatorPreviewView.frame = bounds
        #endif
    }

    private func updateVideoGravity() {
        if DrivingModeConfig.shared.fillScreenEdgeToEdge {
            sampleLayer.videoGravity = .resize
            return
        }
        guard bounds.width > 0, bounds.height > 0 else {
            sampleLayer.videoGravity = .resizeAspect
            return
        }
        let streamW: Double
        let streamH: Double
        if CarPlayManager.shared.currentStreamResolution.width > 0 && CarPlayManager.shared.currentStreamResolution.height > 0 {
            streamW = Double(CarPlayManager.shared.currentStreamResolution.width)
            streamH = Double(CarPlayManager.shared.currentStreamResolution.height)
        } else {
            streamW = 1920.0
            streamH = 1028.0
        }
        let streamAspect = streamW / streamH
        let viewAspect = Double(bounds.width / bounds.height)

        // When view is wider than stream (iPhone landscape), resizeAspect fills 100% of height.
        // When view is narrower/taller than stream (iPad), resizeAspectFill ensures height is 100% filled without vertical letterboxing.
        if viewAspect >= streamAspect {
            sampleLayer.videoGravity = .resizeAspect
        } else {
            sampleLayer.videoGravity = .resizeAspectFill
        }
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
        let viewW = bounds.width
        let viewH = bounds.height
        guard viewW > 0, viewH > 0 else { return (0, 0) }

        #if targetEnvironment(simulator)
        let normX = min(max(Double(loc.x / viewW), 0.0), 1.0)
        let normY = min(max(Double(loc.y / viewH), 0.0), 1.0)
        return (normX, normY)
        #else
        if DrivingModeConfig.shared.fillScreenEdgeToEdge {
            let normX = min(max(Double(loc.x / viewW), 0.0), 1.0)
            let normY = min(max(Double(loc.y / viewH), 0.0), 1.0)
            return (normX, normY)
        }

        let streamW: Double
        let streamH: Double
        if CarPlayManager.shared.currentStreamResolution.width > 0 && CarPlayManager.shared.currentStreamResolution.height > 0 {
            streamW = Double(CarPlayManager.shared.currentStreamResolution.width)
            streamH = Double(CarPlayManager.shared.currentStreamResolution.height)
        } else {
            streamW = 1920.0
            streamH = 1028.0
        }

        let streamAspect = streamW / streamH
        let viewAspect = Double(viewW / viewH)

        var renderW = viewW
        var renderH = viewH
        var offsetX: CGFloat = 0

        // Height is always 100% filled to screen height (renderH = viewH, offsetY = 0)
        renderH = viewH
        renderW = CGFloat(Double(viewH) * streamAspect)
        offsetX = (viewW - renderW) / 2.0

        let normX = min(max(Double((loc.x - offsetX) / max(renderW, 1.0)), 0.0), 1.0)
        let normY = min(max(Double(loc.y / max(viewH, 1.0)), 0.0), 1.0)
        return (normX, normY)
        #endif
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
