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
        sampleLayer.videoGravity = .resizeAspect
        sampleLayer.backgroundColor = UIColor.black.cgColor
        sampleLayer.preventsDisplaySleepDuringVideoPlayback = true

        #if targetEnvironment(simulator)
        simulatorPreviewView.contentMode = .scaleAspectFit
        simulatorPreviewView.clipsToBounds = true
        if let img = UIImage(named: "carplay_preview") ?? UIImage(contentsOfFile: Bundle.main.path(forResource: "carplay_preview", ofType: "png") ?? "") {
            simulatorPreviewView.image = img
        } else if let resourcePath = Bundle.main.resourcePath {
            let p = (resourcePath as NSString).appendingPathComponent("AppIcon/carplay_preview.png")
            simulatorPreviewView.image = UIImage(contentsOfFile: p)
        }
        addSubview(simulatorPreviewView)
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
        #if targetEnvironment(simulator)
        simulatorPreviewView.frame = bounds
        #endif
    }

    private var lastTouchBeganTime: TimeInterval = 0

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        lastTouchBeganTime = CACurrentMediaTime()
        let loc = touch.location(in: self)
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
        var offsetY: CGFloat = 0

        if viewAspect > streamAspect {
            // View is wider than stream -> pillarbox (black bars left and right)
            renderW = CGFloat(Double(viewH) * streamAspect)
            offsetX = (viewW - renderW) / 2.0
        } else {
            // View is taller than stream -> letterbox (black bars top and bottom)
            renderH = CGFloat(Double(viewW) / streamAspect)
            offsetY = (viewH - renderH) / 2.0
        }

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
