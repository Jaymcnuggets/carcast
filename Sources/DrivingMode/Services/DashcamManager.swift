//
//  DashcamManager.swift
//  DrivingMode
//
//  Orchestrates background camera recording, rolling 5-minute video chunks,
//  manual/automatic emergency event saves, and PiP viewfinder preview.
//

import Foundation
import AVFoundation
import SwiftUI

public final class DashcamManager: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = DashcamManager()

    @Published public private(set) var isRecording = false
    @Published public private(set) var isStarting = false
    @Published public private(set) var lastEmergencyEvent: Date?
    @Published public private(set) var captureSession: AVCaptureSession?
    @Published public var previewLayer: AVCaptureVideoPreviewLayer?
    @Published public private(set) var recordingStartTime: Date?

    public let storageManager: DashcamStorageManager
    public let impactService: ImpactDetectionService
    #if os(iOS)
    private var movieOutput: AVCaptureMovieFileOutput?
    #endif
    private var currentOutputURL: URL?
    private var previousOutputURL: URL?
    private let queue = DispatchQueue(label: "dev.unordinarylabs.dashcam.queue")

    public init(storageManager: DashcamStorageManager = DashcamStorageManager(),
                impactService: ImpactDetectionService = ImpactDetectionService()) {
        self.storageManager = storageManager
        self.impactService = impactService
        super.init()

        impactService.onImpact = { [weak self] gForce in
            self?.saveCurrentEvent(reason: String(format: "Crash impact detected (%.1fG)", gForce))
        }
    }

    public func startRecording(withAudio: Bool = false) {
        #if os(iOS)
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.startRecording(withAudio: withAudio)
                    }
                }
            }
            return
        } else if status != .authorized {
            NSLog("[Dashcam] Video capture unauthorized: %ld", status.rawValue)
            return
        }

        // Instant UI feedback on main thread (0ms latency)
        self.isStarting = true

        queue.async { [weak self] in
            guard let self = self, self.captureSession == nil else {
                DispatchQueue.main.async { self?.isStarting = false }
                return
            }

            let session = AVCaptureSession()
            session.beginConfiguration()

            if session.canSetSessionPreset(.hd1920x1080) {
                session.sessionPreset = .hd1920x1080
            } else {
                session.sessionPreset = .high
            }

            // Direct device lookup is instantaneous (0.1ms vs 100ms+ discovery scan)
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video)

            guard let camera = camera,
                  let videoInput = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(videoInput) else {
                session.commitConfiguration()
                NSLog("[Dashcam] Failed to create video input from back camera")
                DispatchQueue.main.async { self.isStarting = false }
                return
            }
            session.addInput(videoInput)

            if withAudio, let mic = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: mic),
               session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }

            let output = AVCaptureMovieFileOutput()
            output.maxRecordedDuration = CMTime(seconds: 300, preferredTimescale: 600)
            if session.canAddOutput(output) {
                session.addOutput(output)
                if let conn = output.connection(with: .video), conn.isVideoOrientationSupported {
                    conn.videoOrientation = .landscapeRight
                }
            }

            session.commitConfiguration()

            let pLayer = AVCaptureVideoPreviewLayer(session: session)
            pLayer.videoGravity = .resizeAspectFill

            // Mount UI and preview immediately so user sees layout instantly
            DispatchQueue.main.async {
                self.captureSession = session
                self.movieOutput = output
                self.previewLayer = pLayer
                self.isRecording = true
                self.isStarting = false
                self.recordingStartTime = Date()
                self.startNextSegment()
                self.impactService.startMonitoring()
            }

            // Spin up hardware capture pipeline asynchronously in background
            session.startRunning()
        }
        #endif
    }

    public func stopRecording() {
        #if os(iOS)
        queue.async { [weak self] in
            guard let self = self else { return }
            self.movieOutput?.stopRecording()
            self.captureSession?.stopRunning()
            self.movieOutput = nil

            DispatchQueue.main.async {
                self.captureSession = nil
                self.isRecording = false
                self.isStarting = false
                self.previewLayer = nil
                self.recordingStartTime = nil
                self.impactService.stopMonitoring()
            }
        }
        #endif
    }

    public func saveCurrentEvent(reason: String = "Manual Save") {
        let now = Date()
        if Thread.isMainThread {
            self.lastEmergencyEvent = now
            if let current = self.currentOutputURL {
                self.storageManager.lockAsEmergency(fileURL: current)
            }
            if let prev = self.previousOutputURL {
                self.storageManager.lockAsEmergency(fileURL: prev)
            }
        } else {
            DispatchQueue.main.async {
                self.lastEmergencyEvent = now
                if let current = self.currentOutputURL {
                    self.storageManager.lockAsEmergency(fileURL: current)
                }
                if let prev = self.previousOutputURL {
                    self.storageManager.lockAsEmergency(fileURL: prev)
                }
            }
        }
    }

    private func startNextSegment() {
        #if os(iOS)
        queue.async { [weak self] in
            self?.storageManager.enforceQuota()
        }
        let nextURL = storageManager.newSegmentURL()
        if let current = currentOutputURL {
            previousOutputURL = current
        }
        currentOutputURL = nextURL

        movieOutput?.startRecording(to: nextURL, recordingDelegate: self)
        #endif
    }
}

#if os(iOS)
extension DashcamManager: AVCaptureFileOutputRecordingDelegate {
    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        storageManager.enforceQuota()
        if isRecording {
            startNextSegment()
        }
    }
}
#endif
