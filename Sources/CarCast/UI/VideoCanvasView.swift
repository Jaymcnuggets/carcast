//
//  VideoCanvasView.swift
//  CarCast
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

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
        setupTouches()
    }

    private func setupLayer() {
        sampleLayer.videoGravity = .resizeAspect
        sampleLayer.backgroundColor = UIColor.black.cgColor
        layer.addSublayer(sampleLayer)
    }

    private func setupTouches() {
        isUserInteractionEnabled = true
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let loc = gesture.location(in: self)
        let normX = min(max(loc.x / max(bounds.width, 1.0), 0.0), 1.0)
        let normY = min(max(loc.y / max(bounds.height, 1.0), 0.0), 1.0)
        onTouchEvent?(1, normX, normY)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.onTouchEvent?(0, normX, normY)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let loc = gesture.location(in: self)
        let normX = min(max(loc.x / max(bounds.width, 1.0), 0.0), 1.0)
        let normY = min(max(loc.y / max(bounds.height, 1.0), 0.0), 1.0)

        switch gesture.state {
        case .began:
            onTouchEvent?(1, normX, normY)
        case .changed:
            onTouchEvent?(2, normX, normY)
        case .ended, .cancelled:
            onTouchEvent?(0, normX, normY)
        default:
            break
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        sampleLayer.frame = bounds
    }

    public func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if sampleLayer.status == .failed {
            sampleLayer.flush()
        }
        if sampleLayer.isReadyForMoreMediaData {
            sampleLayer.enqueue(sampleBuffer)
        }
    }
}
#else
public struct RawVideoCanvasView: View {
    public init() {}
    public var body: some View {
        Color.black
    }
}
#endif
