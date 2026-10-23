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

        queue.async { [weak self] in
            guard let self = self, self.captureSession == nil else { return }
            let session = AVCaptureSession()
            if session.canSetSessionPreset(.hd1920x1080) {
                session.sessionPreset = .hd1920x1080
            } else {
                session.sessionPreset = .high
            }

            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera],
                mediaType: .video,
                position: .back
            )
            let camera = discovery.devices.first
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video)

            guard let camera = camera,
                  let videoInput = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(videoInput) else {
                NSLog("[Dashcam] Failed to create video input from back camera")
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
            guard session.canAddOutput(output) else {
                NSLog("[Dashcam] Cannot add movie output to session")
                return
            }
            session.addOutput(output)

            if let conn = output.connection(with: .video), conn.isVideoOrientationSupported {
                conn.videoOrientation = .landscapeRight
            }

            session.startRunning()

            DispatchQueue.main.async {
                self.captureSession = session
                self.movieOutput = output
                let pLayer = AVCaptureVideoPreviewLayer(session: session)
                pLayer.videoGravity = .resizeAspectFill
                self.previewLayer = pLayer
                self.isRecording = true
                self.recordingStartTime = Date()
                self.startNextSegment()
                self.impactService.startMonitoring()
            }
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
        storageManager.enforceQuota()
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
