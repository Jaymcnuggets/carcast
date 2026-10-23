//
//  DashcamPiPOverlay.swift
//  DrivingMode
//
//  Draggable, resizable, floating Picture-in-Picture viewfinder overlay
//  providing live camera preview and emergency event recording controls.
//

import SwiftUI
import AVFoundation

public struct DashcamPiPOverlay: View {
    @ObservedObject var dashcam = DashcamManager.shared
    @State private var offset: CGSize = .zero
    @State private var currentDragTranslation: CGSize = .zero
    @State private var isMinimized: Bool = false
    @State private var showSavedNotice: Bool = false

    public init() {}

    public var body: some View {
        if dashcam.isRecording {
            VStack {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        // Header bar
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("REC")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)

                            Spacer()

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

                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isMinimized.toggle()
                                }
                            } label: {
                                Image(systemName: isMinimized ? "arrow.up.left.and.arrow.down.right" : "minus")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.85))

                        // Camera preview or saved confirmation
                        if !isMinimized {
                            ZStack {
                                Color.black
                                    .frame(width: 176, height: 99)

                                #if os(iOS)
                                if let previewLayer = dashcam.previewLayer {
                                    CameraPreviewUIViewRepresentable(previewLayer: previewLayer)
                                        .frame(width: 176, height: 99)
                                        .clipped()
                                } else {
                                    Image(systemName: "video.fill")
                                        .foregroundColor(.white.opacity(0.4))
                                }
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
                                    .frame(width: 176, height: 99)
                                    .background(Color.black.opacity(0.8))
                                }
                            }
                        }
                    }
                    .frame(width: isMinimized ? 90 : 176)
                    .background(Color.black.opacity(0.9))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
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
    }
}

#if os(iOS)
private struct CameraPreviewUIViewRepresentable: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.layer.addSublayer(previewLayer)
        previewLayer.frame = CGRect(x: 0, y: 0, width: 176, height: 99)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        previewLayer.frame = uiView.bounds
    }
}
#endif
