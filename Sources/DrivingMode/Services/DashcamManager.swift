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
    @Published public var previewLayer: AVCaptureVideoPreviewLayer?

    public let storageManager: DashcamStorageManager
    public let impactService: ImpactDetectionService
    private var captureSession: AVCaptureSession?
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
        queue.async { [weak self] in
            guard let self = self, self.captureSession == nil else { return }
            let session = AVCaptureSession()
            session.sessionPreset = .hd1920x1080

            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera],
                mediaType: .video,
                position: .back
            )
            guard let camera = discovery.devices.first,
                  let videoInput = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(videoInput) else {
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
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)

            session.startRunning()

            DispatchQueue.main.async {
                self.captureSession = session
                self.movieOutput = output
                let pLayer = AVCaptureVideoPreviewLayer(session: session)
                pLayer.videoGravity = .resizeAspectFill
                self.previewLayer = pLayer
                self.isRecording = true
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
            self.captureSession = nil
            self.movieOutput = nil

            DispatchQueue.main.async {
                self.isRecording = false
                self.previewLayer = nil
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
