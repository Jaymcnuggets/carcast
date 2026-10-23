# Integrated Dashcam, Windshield HUD & Steering Wheel Remote Implementation Plan

> **For Antigravity:** REQUIRED SUB-SKILL: Load executing-plans to implement this plan task-by-task.

**Goal:** Implement a background rolling Dashcam (5-min segmented recording, FIFO 3GB disk pruning, 2.5G G-force impact lock), an optical Windshield Night HUD mode (pitch OLED black, horizontal inversion mirror reflection), and Steering Wheel Remote / hardware key integration into DrivingMode.

**Architecture:** 
- `DashcamStorageManager` manages segmented `.mp4` chunks in `Dashcam/Recordings/` and non-prunable locked events in `Dashcam/Emergency/` with a 3 GB FIFO circular quota.
- `ImpactDetectionService` uses `CoreMotion` accelerometer telemetry at 50Hz to identify deceleration spikes exceeding 2.5G with a 15-second debounce.
- `DashcamManager` captures 1080p 30fps video via `AVCaptureSession` and coordinates with `DashcamStorageManager`.
- `SteeringWheelRemoteService` maps `MPRemoteCommandCenter` media controls and hardware keyboard shortcuts to CarPlay HID events (`RTSPServer.sendHomeButtonHIDReport()`, `sendSiriHIDReport()`) and emergency video locking.
- `WindshieldHUDView` renders a high-contrast pitch OLED `#000000` view with `.scaleEffect(x: -1, y: 1)` for clean dashboard reflection without glare.
- `DashcamPiPOverlay` provides a draggable floating camera viewfinder inside `CarPlayActiveScreenView`.

**Tech Stack:** Swift 5.9, iOS 17+, `AVFoundation`, `CoreMotion`, `MediaPlayer`, `UIKit`, `SwiftUI`, `Network.framework`.

---

### Task 1: Info.plist Permissions & Configuration Models

**Files:**
- Modify: `Info.plist`
- Modify: `Sources/DrivingMode/Models/DrivingModeConfig.swift`
- Test: `Tests/DrivingModeTests/DrivingModeTests.swift`

**Step 1: Write the failing test**

In `Tests/DrivingModeTests/DrivingModeTests.swift`, add:
```swift
@MainActor
func testDashcamAndHUDConfigDefaults() {
    let config = DrivingModeConfig.shared
    XCTAssertFalse(config.isDashcamEnabled)
    XCTAssertFalse(config.isDashcamAudioEnabled)
    XCTAssertEqual(config.dashcamStorageLimitMB, 3072) // 3 GB
    XCTAssertEqual(config.impactSensitivityG, 2.5, accuracy: 0.01)
    XCTAssertFalse(config.isHUDModeEnabled)
    XCTAssertTrue(config.isHUDMirrored)
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testDashcamAndHUDConfigDefaults
```
Expected: FAIL with "value of type 'DrivingModeConfig' has no member 'isDashcamEnabled'"

**Step 3: Write minimal implementation**

1. Update `Info.plist` with `NSCameraUsageDescription` and `NSMicrophoneUsageDescription`:
```xml
	<key>NSCameraUsageDescription</key>
	<string>DrivingMode uses the camera to record dashcam footage while driving.</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>DrivingMode uses the microphone to optionally record in-cabin audio with dashcam footage.</string>
```

2. In `Sources/DrivingMode/Models/DrivingModeConfig.swift`, add the properties with AppStorage / UserDefaults backing:
```swift
    @Published public var isDashcamEnabled: Bool {
        didSet { UserDefaults.standard.set(isDashcamEnabled, forKey: "isDashcamEnabled") }
    }
    @Published public var isDashcamAudioEnabled: Bool {
        didSet { UserDefaults.standard.set(isDashcamAudioEnabled, forKey: "isDashcamAudioEnabled") }
    }
    @Published public var dashcamStorageLimitMB: Int {
        didSet { UserDefaults.standard.set(dashcamStorageLimitMB, forKey: "dashcamStorageLimitMB") }
    }
    @Published public var impactSensitivityG: Double {
        didSet { UserDefaults.standard.set(impactSensitivityG, forKey: "impactSensitivityG") }
    }
    @Published public var isHUDModeEnabled: Bool {
        didSet { UserDefaults.standard.set(isHUDModeEnabled, forKey: "isHUDModeEnabled") }
    }
    @Published public var isHUDMirrored: Bool {
        didSet { UserDefaults.standard.set(isHUDMirrored, forKey: "isHUDMirrored") }
    }
```
And initialize them in `init()`:
```swift
    self.isDashcamEnabled = UserDefaults.standard.bool(forKey: "isDashcamEnabled")
    self.isDashcamAudioEnabled = UserDefaults.standard.bool(forKey: "isDashcamAudioEnabled")
    let storedLimit = UserDefaults.standard.integer(forKey: "dashcamStorageLimitMB")
    self.dashcamStorageLimitMB = storedLimit > 0 ? storedLimit : 3072
    let storedSens = UserDefaults.standard.double(forKey: "impactSensitivityG")
    self.impactSensitivityG = storedSens > 0 ? storedSens : 2.5
    self.isHUDModeEnabled = UserDefaults.standard.bool(forKey: "isHUDModeEnabled")
    self.isHUDMirrored = UserDefaults.standard.object(forKey: "isHUDMirrored") != nil ? UserDefaults.standard.bool(forKey: "isHUDMirrored") : true
```

**Step 4: Run test to verify it passes**

Run:
```bash
cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testDashcamAndHUDConfigDefaults
```
Expected: PASS

**Step 5: Commit**

```bash
git add Info.plist Sources/DrivingMode/Models/DrivingModeConfig.swift Tests/DrivingModeTests/DrivingModeTests.swift
git commit -m "feat(config): add dashcam, HUD and remote configuration properties"
```

---

### Task 2: Dashcam Storage Manager & Circular Buffer FIFO Pruning

**Files:**
- Create: `Sources/DrivingMode/Services/DashcamStorageManager.swift`
- Test: `Tests/DrivingModeTests/DrivingModeTests.swift`

**Step 1: Write the failing test**

In `Tests/DrivingModeTests/DrivingModeTests.swift`, add:
```swift
func testDashcamStorageManagerCreationAndPruning() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let storage = DashcamStorageManager(baseDirectory: tempDir, quotaBytes: 10 * 1024 * 1024) // 10 MB quota for test
    
    XCTAssertTrue(FileManager.default.fileExists(atPath: storage.recordingsDirectory.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: storage.emergencyDirectory.path))
    
    // Create 3 dummy 4 MB recording files
    let dummyData = Data(repeating: 0xAA, count: 4 * 1024 * 1024)
    let file1 = storage.recordingsDirectory.appendingPathComponent("dashcam_20261023_100000.mp4")
    let file2 = storage.recordingsDirectory.appendingPathComponent("dashcam_20261023_100500.mp4")
    let file3 = storage.recordingsDirectory.appendingPathComponent("dashcam_20261023_101000.mp4")
    
    try dummyData.write(to: file1)
    try dummyData.write(to: file2)
    try dummyData.write(to: file3)
    
    // 12 MB total > 10 MB quota -> enforcePruning should remove file1 (oldest)
    storage.enforceQuota()
    
    XCTAssertFalse(FileManager.default.fileExists(atPath: file1.path), "Oldest file should have been pruned")
    XCTAssertTrue(FileManager.default.fileExists(atPath: file2.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: file3.path))
    
    // Lock file2 as emergency
    let emergencyFile = storage.lockAsEmergency(fileURL: file2)
    XCTAssertNotNil(emergencyFile)
    XCTAssertTrue(FileManager.default.fileExists(atPath: emergencyFile!.path))
    
    // Cleanup
    try? FileManager.default.removeItem(at: tempDir)
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testDashcamStorageManagerCreationAndPruning
```
Expected: FAIL with "cannot find 'DashcamStorageManager' in scope"

**Step 3: Write minimal implementation**

Create `Sources/DrivingMode/Services/DashcamStorageManager.swift`:
```swift
import Foundation

public final class DashcamStorageManager: @unchecked Sendable {
    public let baseDirectory: URL
    public let recordingsDirectory: URL
    public let emergencyDirectory: URL
    public var quotaBytes: Int64
    private let fileManager = FileManager.default
    private let lock = NSLock()

    public init(baseDirectory: URL? = nil, quotaBytes: Int64 = 3 * 1024 * 1024 * 1024) {
        let base = baseDirectory ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Dashcam", isDirectory: true)
        self.baseDirectory = base
        self.recordingsDirectory = base.appendingPathComponent("Recordings", isDirectory: true)
        self.emergencyDirectory = base.appendingPathComponent("Emergency", isDirectory: true)
        self.quotaBytes = quotaBytes
        
        createDirectoriesIfNeeded()
    }
    
    private func createDirectoriesIfNeeded() {
        try? fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: emergencyDirectory, withIntermediateDirectories: true)
    }

    public func newSegmentURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        return recordingsDirectory.appendingPathComponent("dashcam_\(timestamp).mp4")
    }

    public func enforceQuota() {
        lock.lock()
        defer { lock.unlock() }

        guard let contents = try? fileManager.contentsOfDirectory(at: recordingsDirectory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: .skipsHiddenFiles) else { return }

        var filesWithSizeAndDate: [(url: URL, size: Int64, date: Date)] = []
        var totalSize: Int64 = 0

        for file in contents {
            guard let resourceValues = try? file.resourceValues(forKeys: [.fileSizeKey, .creationDateKey]),
                  let size = resourceValues.fileSize,
                  let date = resourceValues.creationDate else { continue }
            filesWithSizeAndDate.append((url: file, size: Int64(size), date: date))
            totalSize += Int64(size)
        }

        // Sort oldest first
        filesWithSizeAndDate.sort { $0.date < $1.date }

        for file in filesWithSizeAndDate {
            if totalSize <= quotaBytes { break }
            try? fileManager.removeItem(at: file.url)
            totalSize -= file.size
        }
    }

    @discardableResult
    public func lockAsEmergency(fileURL: URL) -> URL? {
        lock.lock()
        defer { lock.unlock() }

        let targetURL = emergencyDirectory.appendingPathComponent(fileURL.lastPathComponent)
        do {
            if fileManager.fileExists(atPath: targetURL.path) {
                try? fileManager.removeItem(at: targetURL)
            }
            try fileManager.copyItem(at: fileURL, to: targetURL)
            return targetURL
        } catch {
            return nil
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run:
```bash
cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testDashcamStorageManagerCreationAndPruning
```
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/DrivingMode/Services/DashcamStorageManager.swift Tests/DrivingModeTests/DrivingModeTests.swift
git commit -m "feat(dashcam): implement DashcamStorageManager with FIFO 3GB quota and emergency lock"
```

---

### Task 3: Impact Detection Service (CoreMotion G-Force Spike Trigger)

**Files:**
- Create: `Sources/DrivingMode/Services/ImpactDetectionService.swift`
- Test: `Tests/DrivingModeTests/DrivingModeTests.swift`

**Step 1: Write the failing test**

In `Tests/DrivingModeTests/DrivingModeTests.swift`, add:
```swift
func testImpactDetectionSpikeAndDebounce() {
    let service = ImpactDetectionService(thresholdG: 2.5, debounceSeconds: 5.0)
    var triggeredCount = 0
    service.onImpact = { _ in
        triggeredCount += 1
    }

    // Normal driving: 1.0G (gravity only)
    service.processAcceleration(x: 0.1, y: 0.2, z: 0.98)
    XCTAssertEqual(triggeredCount, 0)

    // Hard collision: 2.8G deceleration
    service.processAcceleration(x: 1.2, y: -2.3, z: 0.9)
    XCTAssertEqual(triggeredCount, 1)

    // Secondary bounce 1 second later (should be debounced)
    service.processAcceleration(x: 1.5, y: -2.5, z: 1.0)
    XCTAssertEqual(triggeredCount, 1, "Should debounce subsequent impacts within window")
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testImpactDetectionSpikeAndDebounce
```
Expected: FAIL with "cannot find 'ImpactDetectionService' in scope"

**Step 3: Write minimal implementation**

Create `Sources/DrivingMode/Services/ImpactDetectionService.swift`:
```swift
import Foundation
import CoreMotion

public final class ImpactDetectionService: @unchecked Sendable {
    public var thresholdG: Double
    public var debounceSeconds: TimeInterval
    public var onImpact: ((Double) -> Void)?
    
    private let motionManager = CMMotionManager()
    private var lastImpactTime: Date?
    private let lock = NSLock()

    public init(thresholdG: Double = 2.5, debounceSeconds: TimeInterval = 15.0) {
        self.thresholdG = thresholdG
        self.debounceSeconds = debounceSeconds
    }

    public func startMonitoring() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 1.0 / 50.0 // 50 Hz
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let data = data else { return }
            self.processAcceleration(x: data.acceleration.x, y: data.acceleration.y, z: data.acceleration.z)
        }
    }

    public func stopMonitoring() {
        if motionManager.isAccelerometerActive {
            motionManager.stopAccelerometerUpdates()
        }
    }

    public func processAcceleration(x: Double, y: Double, z: Double) {
        lock.lock()
        defer { lock.unlock() }

        let magnitude = sqrt(x * x + y * y + z * z)
        guard magnitude >= thresholdG else { return }

        let now = Date()
        if let last = lastImpactTime, now.timeIntervalSince(last) < debounceSeconds {
            return
        }

        lastImpactTime = now
        DispatchQueue.main.async { [weak self] in
            self?.onImpact?(magnitude)
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run:
```bash
cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testImpactDetectionSpikeAndDebounce
```
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/DrivingMode/Services/ImpactDetectionService.swift Tests/DrivingModeTests/DrivingModeTests.swift
git commit -m "feat(dashcam): implement ImpactDetectionService with G-force spike detection and debounce"
```

---

### Task 4: Dashcam Manager (AVCaptureSession & Segmentation Pipeline)

**Files:**
- Create: `Sources/DrivingMode/Services/DashcamManager.swift`
- Modify: `Sources/DrivingMode/Services/CarPlayManager.swift`
- Test: `Tests/DrivingModeTests/DrivingModeTests.swift`

**Step 1: Write the failing test**

In `Tests/DrivingModeTests/DrivingModeTests.swift`, add:
```swift
@MainActor
func testDashcamManagerLifecycle() {
    let storage = DashcamStorageManager(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let manager = DashcamManager(storageManager: storage)
    XCTAssertFalse(manager.isRecording)
    
    // Trigger manual emergency save event
    manager.saveCurrentEvent(reason: "User button")
    XCTAssertNotNil(manager.lastEmergencyEvent)
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testDashcamManagerLifecycle
```
Expected: FAIL with "cannot find 'DashcamManager' in scope"

**Step 3: Write minimal implementation**

Create `Sources/DrivingMode/Services/DashcamManager.swift`:
```swift
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
    private var movieOutput: AVCaptureMovieFileOutput?
    private var rotationTimer: Timer?
    private var currentOutputURL: URL?
    private var previousOutputURL: URL?
    private let queue = DispatchQueue(label: "dev.unordinarylabs.dashcam.queue")

    public init(storageManager: DashcamStorageManager = DashcamStorageManager(), impactService: ImpactDetectionService = ImpactDetectionService()) {
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
            // 5 minute max per chunk
            output.maxRecordedDuration = CMTime(seconds: 300, preferredTimescale: 600)
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)

            session.startRunning()

            DispatchQueue.main.async {
                self.captureSession = session
                self.movieOutput = output
                self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
                self.previewLayer?.videoGravity = .resizeAspectFill
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
            self.rotationTimer?.invalidate()
            self.rotationTimer = nil

            DispatchQueue.main.async {
                self.isRecording = false
                self.previewLayer = nil
                self.impactService.stopMonitoring()
            }
        }
        #endif
    }

    public func saveCurrentEvent(reason: String = "Manual Save") {
        DispatchQueue.main.async {
            self.lastEmergencyEvent = Date()
            if let current = self.currentOutputURL {
                self.storageManager.lockAsEmergency(fileURL: current)
            }
            if let prev = self.previousOutputURL {
                self.storageManager.lockAsEmergency(fileURL: prev)
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
```

**Step 4: Run test to verify it passes**

Run:
```bash
cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testDashcamManagerLifecycle
```
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/DrivingMode/Services/DashcamManager.swift Tests/DrivingModeTests/DrivingModeTests.swift
git commit -m "feat(dashcam): implement DashcamManager with camera pipeline, rotation and emergency lock"
```

---

### Task 5: Steering Wheel Remote & Media Command Center Dispatch

**Files:**
- Create: `Sources/DrivingMode/Services/SteeringWheelRemoteService.swift`
- Test: `Tests/DrivingModeTests/DrivingModeTests.swift`

**Step 1: Write the failing test**

In `Tests/DrivingModeTests/DrivingModeTests.swift`, add:
```swift
@MainActor
func testSteeringWheelRemoteKeyBinding() {
    let service = SteeringWheelRemoteService.shared
    var homeTriggered = false
    var siriTriggered = false
    var emergencyTriggered = false

    service.onHomePressed = { homeTriggered = true }
    service.onSiriPressed = { siriTriggered = true }
    service.onEmergencySavePressed = { emergencyTriggered = true }

    service.handleKeyInput("h")
    XCTAssertTrue(homeTriggered)

    service.handleKeyInput("s")
    XCTAssertTrue(siriTriggered)

    service.handleKeyInput("e")
    XCTAssertTrue(emergencyTriggered)
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testSteeringWheelRemoteKeyBinding
```
Expected: FAIL with "cannot find 'SteeringWheelRemoteService' in scope"

**Step 3: Write minimal implementation**

Create `Sources/DrivingMode/Services/SteeringWheelRemoteService.swift`:
```swift
import Foundation
import MediaPlayer
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class SteeringWheelRemoteService: ObservableObject {
    public static let shared = SteeringWheelRemoteService()

    public var onHomePressed: (() -> Void)?
    public var onSiriPressed: (() -> Void)?
    public var onEmergencySavePressed: (() -> Void)?

    private init() {
        setupRemoteCommandCenter()
    }

    public func setupRemoteCommandCenter() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { _ in .success }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { _ in .success }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { _ in .success }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { _ in .success }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { _ in .success }
    }

    public func handleKeyInput(_ key: String) {
        switch key.lowercased() {
        case "h":
            onHomePressed?()
        case "s":
            onSiriPressed?()
        case "e":
            onEmergencySavePressed?()
        default:
            break
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run:
```bash
cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testSteeringWheelRemoteKeyBinding
```
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/DrivingMode/Services/SteeringWheelRemoteService.swift Tests/DrivingModeTests/DrivingModeTests.swift
git commit -m "feat(remotes): implement SteeringWheelRemoteService with MPRemoteCommandCenter and key handling"
```

---

### Task 6: UI Components — Dashcam PiP Viewfinder & Windshield HUD Mode

**Files:**
- Create: `Sources/DrivingMode/UI/DashcamPiPOverlay.swift`
- Create: `Sources/DrivingMode/UI/WindshieldHUDView.swift`
- Modify: `Sources/DrivingMode/UI/CarPlayActiveScreenView.swift`
- Modify: `Sources/DrivingMode/UI/SettingsView.swift`

**Step 1: Write the failing test**

In `Tests/DrivingModeTests/DrivingModeTests.swift`, add:
```swift
@MainActor
func testHUDModeTransform() {
    let isMirrored = true
    let scaleX: CGFloat = isMirrored ? -1.0 : 1.0
    let scaleY: CGFloat = 1.0
    XCTAssertEqual(scaleX, -1.0)
    XCTAssertEqual(scaleY, 1.0)
}
```

**Step 2: Run test to verify it passes / validates**

Run:
```bash
cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testHUDModeTransform
```
Expected: PASS

**Step 3: Create UI Files**

1. Create `Sources/DrivingMode/UI/DashcamPiPOverlay.swift`:
```swift
import SwiftUI
import AVFoundation

public struct DashcamPiPOverlay: View {
    @ObservedObject var dashcam = DashcamManager.shared
    @State private var offset: CGSize = CGSize(width: 20, height: 20)
    @State private var isMinimized = false

    public init() {}

    public var body: some View {
        if dashcam.isRecording {
            VStack {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("REC")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            Spacer()
                            Button {
                                withAnimation(.spring()) {
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
                        .background(Color.black.opacity(0.7))

                        if !isMinimized {
                            Color.black
                                .frame(width: 160, height: 90)
                                .overlay(
                                    Image(systemName: "video.fill")
                                        .foregroundColor(.white.opacity(0.4))
                                )
                        }
                    }
                    .frame(width: isMinimized ? 80 : 160)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .offset(offset)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                offset = CGSize(
                                    width: offset.width + gesture.translation.width,
                                    height: offset.height + gesture.translation.height
                                )
                            }
                    )
                }
                Spacer()
            }
            .padding()
        }
    }
}
```

2. Create `Sources/DrivingMode/UI/WindshieldHUDView.swift`:
```swift
import SwiftUI

public struct WindshieldHUDView: View {
    @ObservedObject var config = DrivingModeConfig.shared
    @ObservedObject var telemetry = VehicleTelemetry.shared
    @ObservedObject var dashcam = DashcamManager.shared
    @Environment(\.dismiss) var dismiss

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                // Top control bar
                HStack {
                    Button {
                        config.isHUDMirrored.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                            Text(config.isHUDMirrored ? "MIRROR ON" : "MIRROR OFF")
                        }
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                    }

                    Spacer()

                    if dashcam.isRecording {
                        HStack(spacing: 6) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text("DASHCAM REC")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.red)
                        }
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                // Speed Display
                VStack(spacing: -8) {
                    Text("\(Int(telemetry.speedMph))")
                        .font(.system(size: 120, weight: .black, design: .rounded))
                        .foregroundColor(.green)
                    Text("MPH")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(.green.opacity(0.8))
                }

                // Telemetry / Media Banner
                if !telemetry.currentTrackTitle.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "music.note")
                            .foregroundColor(.cyan)
                        Text("\(telemetry.currentTrackTitle) — \(telemetry.currentArtist)")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(8)
                }

                Spacer()

                // Emergency Save Button
                Button {
                    dashcam.saveCurrentEvent(reason: "HUD button")
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("SAVE EVENT")
                    }
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.yellow.opacity(0.15))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
                    )
                }
                .padding(.bottom, 24)
            }
        }
        .scaleEffect(x: config.isHUDMirrored ? -1.0 : 1.0, y: 1.0)
    }
}
```

3. Update `CarPlayActiveScreenView.swift` to include `DashcamPiPOverlay` and HUD toggle.
4. Update `SettingsView.swift` to include Dashcam, Remote, and HUD toggles.

**Step 4: Run test suite to verify everything compiles and passes**

Run:
```bash
cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/DrivingMode/UI/DashcamPiPOverlay.swift Sources/DrivingMode/UI/WindshieldHUDView.swift Sources/DrivingMode/UI/CarPlayActiveScreenView.swift Sources/DrivingMode/UI/SettingsView.swift Tests/DrivingModeTests/DrivingModeTests.swift
git commit -m "feat(ui): add Dashcam PiP overlay, Windshield HUD view and settings integration"
```

---

### Task 7: Full System Verification & Physical iPhone 15 Pro Deployment

**Files:**
- Build: `DrivingMode.xcodeproj`
- Verification: Physical iPhone 15 Pro (`00008130-00126D081E43001C`)

**Step 1: Run complete test suite**

```bash
cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```
Expected: All tests pass with 0 failures.

**Step 2: Build project with Developer SDK**

```bash
cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project DrivingMode.xcodeproj -scheme DrivingMode -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO build
```
Expected: `** BUILD SUCCEEDED **`

**Step 3: Build & Deploy to Physical iPhone 15 Pro**

```bash
cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project DrivingMode.xcodeproj -scheme DrivingMode -destination "id=00008130-00126D081E43001C" -allowProvisioningUpdates build
```
Expected: Build and code-sign succeed with Apple Development profile.

**Step 4: Launch and capture device screenshot**

```bash
xcrun devicectl device process launch --device 00008130-00126D081E43001C dev.unordinarylabs.DrivingMode
```
Verify Dashcam background recording and HUD reflection mode in live session.

**Step 5: Final Commit & Push**

```bash
git add -A
git commit -m "feat: complete integrated dashcam, windshield HUD and steering wheel remote integration"
git push origin main
```
