//
//  DashcamPiPOverlay.swift
//  DrivingMode
//
//  Draggable, resizable, floating Picture-in-Picture viewfinder overlay
//  providing live camera preview, fullscreen inspection, and emergency recording controls.
//

import SwiftUI
import AVFoundation
import Combine

public struct DashcamPiPOverlay: View {
    @ObservedObject var dashcam = DashcamManager.shared
    @State private var offset: CGSize = .zero
    @State private var currentDragTranslation: CGSize = .zero
    @State private var isMinimized: Bool = false
    @State private var isLarge: Bool = false
    @State private var isFullScreen: Bool = false
    @State private var showSavedNotice: Bool = false
    @State private var timerText: String = "00:00"

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    public init() {}

    private var pipWidth: CGFloat {
        if isMinimized { return 120 }
        return isLarge ? 340 : 208
    }

    private var pipHeight: CGFloat {
        if isMinimized { return 36 }
        return isLarge ? 191 : 117
    }

    public var body: some View {
        if dashcam.isRecording {
            ZStack {
                // Regular Floating PiP Overlay
                if !isFullScreen {
                    VStack {
                        HStack {
                            Spacer()
                            VStack(alignment: .trailing, spacing: 0) {
                                // Header bar
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)

                                    Text("REC")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)

                                    Text(timerText)
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.8))

                                    Spacer()

                                    // Lock Event
                                    Button {
                                        dashcam.saveCurrentEvent(reason: "PiP Button")
                                        withAnimation(.spring()) {
                                            showSavedNotice = true
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                            withAnimation {
                                                showSavedNotice = false
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.yellow)
                                    }
                                    .help("Lock event to Emergency folder")

                                    // Fullscreen Expand
                                    Button {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            isFullScreen = true
                                        }
                                    } label: {
                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                    .help("Expand Fullscreen")

                                    // Toggle Size / Minimize
                                    Button {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            isMinimized.toggle()
                                        }
                                    } label: {
                                        Image(systemName: isMinimized ? "chevron.down" : "minus")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                    .help(isMinimized ? "Restore" : "Minimize")
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.85))

                                // Camera preview or saved confirmation
                                if !isMinimized {
                                    ZStack {
                                        Color.black
                                            .frame(width: pipWidth, height: pipHeight)

                                        #if os(iOS)
                                        CameraPreviewRepresentable(session: dashcam.captureSession)
                                            .frame(width: pipWidth, height: pipHeight)
                                            .clipped()
                                        #else
                                        Image(systemName: "video.fill")
                                            .foregroundColor(.white.opacity(0.4))
                                        #endif

                                        if showSavedNotice {
                                            VStack(spacing: 4) {
                                                Image(systemName: "checkmark.shield.fill")
                                                    .foregroundColor(.yellow)
                                                Text("EVENT LOCKED")
                                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.yellow)
                                            }
                                            .frame(width: pipWidth, height: pipHeight)
                                            .background(Color.black.opacity(0.8))
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            isLarge.toggle()
                                        }
                                    }
                                }
                            }
                            .frame(width: pipWidth)
                            .background(Color.black.opacity(0.9))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                            .offset(x: offset.width + currentDragTranslation.width,
                                    y: offset.height + currentDragTranslation.height)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        currentDragTranslation = value.translation
                                    }
                                    .onEnded { value in
                                        offset.width += value.translation.width
                                        offset.height += value.translation.height
                                        currentDragTranslation = .zero
                                    }
                            )
                        }
                        Spacer()
                    }
                    .padding()
                }

                // Fullscreen Live Dashcam Inspector
                if isFullScreen {
                    ZStack {
                        Color.black.ignoresSafeArea()

                        #if os(iOS)
                        CameraPreviewRepresentable(session: dashcam.captureSession)
                            .ignoresSafeArea()
                        #endif

                        // Fullscreen Overlay Top Bar
                        VStack {
                            HStack {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 10, height: 10)
                                    Text("DASHCAM LIVE")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                    Text(timerText)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.65))
                                .cornerRadius(20)

                                Spacer()

                                Button {
                                    dashcam.saveCurrentEvent(reason: "Fullscreen Save")
                                    withAnimation(.spring()) {
                                        showSavedNotice = true
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        withAnimation {
                                            showSavedNotice = false
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                        Text("LOCK EVENT")
                                    }
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.yellow)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.65))
                                    .cornerRadius(20)
                                }

                                Button {
                                    withAnimation(.spring()) {
                                        isFullScreen = false
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark.circle.fill")
                                        Text("RETURN")
                                    }
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.65))
                                    .cornerRadius(20)
                                }
                            }
                            .padding(.top, 14)
                            .padding(.horizontal, 20)

                            Spacer()

                            if showSavedNotice {
                                Text("EMERGENCY EVENT SAVED")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(.yellow)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.black.opacity(0.75))
                                    .cornerRadius(12)
                                    .padding(.bottom, 24)
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .onReceive(timer) { _ in
                if let start = dashcam.recordingStartTime {
                    let elapsed = Int(Date().timeIntervalSince(start))
                    let minutes = elapsed / 60
                    let seconds = elapsed % 60
                    timerText = String(format: "%02d:%02d", minutes, seconds)
                } else {
                    timerText = "00:00"
                }
            }
        }
    }
}

// MARK: - Native AVCaptureVideoPreviewLayer Backing View

#if os(iOS)
public final class CameraPreviewUIView: UIView {
    public override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }

    public var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
    }

    public func attachSession(_ session: AVCaptureSession?) {
        guard previewLayer.session !== session else { return }
        previewLayer.session = session
        updateOrientation()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateOrientation()
    }

    public func updateOrientation() {
        guard let connection = previewLayer.connection, connection.isVideoOrientationSupported else { return }
        if let windowScene = window?.windowScene {
            switch windowScene.interfaceOrientation {
            case .landscapeLeft:
                connection.videoOrientation = .landscapeLeft
            case .landscapeRight:
                connection.videoOrientation = .landscapeRight
            case .portraitUpsideDown:
                connection.videoOrientation = .portraitUpsideDown
            case .portrait:
                connection.videoOrientation = .portrait
            @unknown default:
                connection.videoOrientation = .landscapeRight
            }
        } else {
            connection.videoOrientation = .landscapeRight
        }
    }
}

public struct CameraPreviewRepresentable: UIViewRepresentable {
    public let session: AVCaptureSession?

    public init(session: AVCaptureSession?) {
        self.session = session
    }

    public func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.attachSession(session)
        return view
    }

    public func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.attachSession(session)
        uiView.updateOrientation()
    }
}
#endif
