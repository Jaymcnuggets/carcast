//
//  VideoCanvasView.swift
//  CarCast
//
//  Hardware-accelerated video canvas with touch forwarding for iOS and macOS.
//

import SwiftUI
import AVFoundation
import CoreMedia

#if canImport(UIKit)
import UIKit

public struct VideoCanvasView: UIViewRepresentable {
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
        backgroundColor = .black
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
        onTouchEvent?(1, normX, normY) // Down
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)
        let normX = Double(loc.x / max(1, bounds.width))
        let normY = Double(loc.y / max(1, bounds.height))
        onTouchEvent?(2, normX, normY) // Move
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)
        let normX = Double(loc.x / max(1, bounds.width))
        let normY = Double(loc.y / max(1, bounds.height))
        onTouchEvent?(0, normX, normY) // Up
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}

#elseif canImport(AppKit)
import AppKit

public struct VideoCanvasView: NSViewRepresentable {
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
        layer?.backgroundColor = NSColor.black.cgColor
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
