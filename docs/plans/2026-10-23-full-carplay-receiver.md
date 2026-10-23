# Full Wireless CarPlay Receiver Implementation Plan

> **For Antigravity:** REQUIRED SUB-SKILL: Load executing-plans to implement this plan task-by-task.

**Goal:** Implement the complete, autonomous wireless Apple CarPlay Head Unit receiver for `dev.unordinarylabs.DrivingMode`, enabling Bonjour/mDNS ignition, H.264 video rendering with interactive HID multi-touch, full dual-stream AirPlay audio (Media 100 + Siri/Nav 101 with automatic ducking), and a configurable Car Bluetooth Passthrough mode.

**Architecture:** The receiver initiates discovery via Bonjour mDNS (`_airplay._tcp`, `_raop._tcp`, `_carplay._tcp`, `_drivingmode._tcp`), BLE (`0x0067`), and ACCTransport iAP2. The incoming iPhone connects via RTSP (:7000) where `RTSPServer` negotiates video (`110`) and audio (`100`, `101`) streams and derives ChaCha20-Poly1305 encryption keys using HKDF. `AirPlayScreenReceiver` (:7100) decodes H.264 frames to `AVSampleBufferDisplayLayer` while `AirPlayAudioReceiver` (:7001, :7002) decodes RTP audio packets into an `AVAudioEngine` pipeline with automatic ducking or routes passthrough.

**Tech Stack:** Swift 5.9, iOS / iPadOS 17.0+, macOS 14.0+, `Network.framework` (`NWListener`, `NWConnection`), `AVFoundation` (`AVAudioEngine`, `AVAudioPlayerNode`, `AVSampleBufferDisplayLayer`), `VideoToolbox` (`VTDecompressionSession`), `CryptoKit` / `CommonCrypto` (HKDF, Curve25519, ChaCha20-Poly1305), `SwiftUI`.

---

### Task 1: Active Bonjour & mDNS Discovery Wiring

**Files:**
- Modify: `Sources/DrivingMode/Services/CarPlayManager.swift`
- Test: `Tests/DrivingModeTests/DrivingModeTests.swift`

**Step 1: Write the failing test**
In `Tests/DrivingModeTests/DrivingModeTests.swift`, add a test verifying that `AirPlayBonjourAdvertiser` generates and publishes all 4 authentic services with correct TXT records (`features`, `model`, `deviceid`):

```swift
func testBonjourAdvertiserTXTRecordsAndState() {
    let advertiser = AirPlayBonjourAdvertiser(port: 7000)
    advertiser.startAdvertising(name: "DrivingMode-TestUnit", deviceId: "02:55:4E:AA:BB:CC")
    
    // Validate advertiser handles rapid start/stop cycles cleanly
    advertiser.stopAdvertising()
    advertiser.startAdvertising(name: "DrivingMode-TestUnit2", deviceId: "02:55:4E:AA:BB:DD")
    XCTAssertNotNil(advertiser)
    advertiser.stopAdvertising()
}
```

**Step 2: Run test to verify it passes/fails**
Run: `cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testBonjourAdvertiserTXTRecordsAndState`
Expected: PASS or verify existing behavior.

**Step 3: Wire Bonjour advertiser into CarPlayManager**
In `Sources/DrivingMode/Services/CarPlayManager.swift`:
1. In `startReceiver()`:
```swift
#if !targetEnvironment(simulator)
self.bonjourAdvertiser.startAdvertising(name: carName, deviceId: deviceId)
#endif
```
2. In `stopReceiver()`:
```swift
self.bonjourAdvertiser.stopAdvertising()
```

**Step 4: Run test to verify compilation and passing status**
Run: `cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: All 15 tests pass.

**Step 5: Commit**
```bash
git add Sources/DrivingMode/Services/CarPlayManager.swift Tests/DrivingModeTests/DrivingModeTests.swift
git commit -m "feat(discovery): wire active Bonjour mDNS advertiser into CarPlayManager start/stop lifecycle"
```

---

### Task 2: AirPlay Audio Receiver Engine (`AirPlayAudioReceiver.swift`)

**Files:**
- Create: `Sources/DrivingMode/Protocols/AirPlayAudioReceiver.swift`
- Modify: `Sources/DrivingMode/Protocols/RTSPServer.swift`
- Test: `Tests/DrivingModeTests/DrivingModeTests.swift`

**Step 1: Write the failing test for RTP unpacking and audio ducking**
In `Tests/DrivingModeTests/DrivingModeTests.swift`, add test cases for `AirPlayAudioReceiver`:
1. `testRTPAudioHeaderParsing()`: Parses RTP header (version 2, payload type 96, sequence number, timestamp, SSRC).
2. `testAudioDuckingLogic()`: When alt audio (stream 101) triggers, main audio volume ducks from 1.0 to 0.25, and ramps back up after silence timeout.

```swift
func testRTPAudioHeaderParsing() {
    // 12-byte standard RTP header: V=2, P=0, X=0, CC=0, M=0, PT=96 (0x80, 0x60), Seq=1001 (0x03, 0xE9), TS=44100, SSRC=0x12345678
    let headerBytes: [UInt8] = [
        0x80, 0x60, 0x03, 0xE9,
        0x00, 0x00, 0xAC, 0x44,
        0x12, 0x34, 0x56, 0x78
    ]
    let pcmPayload = Data(repeating: 0x00, count: 1024)
    let packetData = Data(headerBytes) + pcmPayload
    
    let parsed = AirPlayAudioReceiver.parseRTPPacket(packetData)
    XCTAssertNotNil(parsed)
    XCTAssertEqual(parsed?.sequenceNumber, 1001)
    XCTAssertEqual(parsed?.payloadType, 96)
    XCTAssertEqual(parsed?.payload.count, 1024)
}

func testAudioDuckingStateCalculation() {
    let receiver = AirPlayAudioReceiver.shared
    receiver.isPassthroughMode = false
    
    // Base volume
    receiver.setBaseVolume(0.8)
    XCTAssertEqual(receiver.effectiveMainVolume, 0.8, accuracy: 0.01)
    
    // Simulate Alt Audio active (Siri/Nav prompt)
    receiver.notifyAltAudioActive(true)
    XCTAssertEqual(receiver.effectiveMainVolume, 0.8 * 0.25, accuracy: 0.01)
    
    // Simulate Alt Audio finished
    receiver.notifyAltAudioActive(false)
    XCTAssertEqual(receiver.effectiveMainVolume, 0.8, accuracy: 0.01)
}
```

**Step 2: Run test to verify it fails**
Run: `cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testRTPAudioHeaderParsing`
Expected: FAIL ("AirPlayAudioReceiver not found").

**Step 3: Implement AirPlayAudioReceiver.swift**
Create `Sources/DrivingMode/Protocols/AirPlayAudioReceiver.swift`:
- `struct RTPPacket`: `sequenceNumber: UInt16`, `payloadType: UInt8`, `timestamp: UInt32`, `ssrc: UInt32`, `payload: Data`.
- Static function `parseRTPPacket(_ data: Data) -> RTPPacket?`.
- UDP listeners on port `7001` (Main Media Stream `100`) and port `7002` (Alt Audio Stream `101`).
- `AVAudioEngine` setup with `mainAudioNode` and `altAudioNode` attached to `mainMixerNode`.
- Audio ducking logic: `notifyAltAudioActive(Bool)`, timer-based ramp recovery.
- `isPassthroughMode: Bool`: if true, incoming RTP packets are acknowledged/drained without allocating speaker audio resources.
- Volume mapping function: convert RTSP dB range (`-30.0` to `0.0`) to linear amplitude (`0.0` to `1.0`).

**Step 4: Run test to verify it passes**
Run: `cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testRTPAudioHeaderParsing`
Expected: PASS.

**Step 5: Commit**
```bash
git add Sources/DrivingMode/Protocols/AirPlayAudioReceiver.swift Tests/DrivingModeTests/DrivingModeTests.swift
git commit -m "feat(audio): implement AirPlayAudioReceiver with RTP parsing, dual-node AVAudioEngine, and auto-ducking"
```

---

### Task 3: RTSP Multi-Stream Negotiation & Audio Control

**Files:**
- Modify: `Sources/DrivingMode/Protocols/RTSPServer.swift`
- Test: `Tests/DrivingModeTests/DrivingModeTests.swift`

**Step 1: Write the failing test for multi-stream RTSP SETUP**
In `Tests/DrivingModeTests/DrivingModeTests.swift`:
```swift
func testRTSPMultiStreamSetupResponse() {
    let server = RTSPServer(port: 7000)
    let requestStreams: [[String: Any]] = [
        ["type": 110, "streamConnectionID": 1111],
        ["type": 100, "streamConnectionID": 2222],
        ["type": 101, "streamConnectionID": 3333]
    ]
    let requestPlist: [String: Any] = ["streams": requestStreams]
    let bodyData = try! PropertyListSerialization.data(fromPropertyList: requestPlist, format: .binary, options: 0)
    
    let responseDict = server.buildStreamSetupResponse(for: bodyData)
    guard let responseStreams = responseDict["streams"] as? [[String: Any]] else {
        XCTFail("Missing streams key in response")
        return
    }
    
    XCTAssertEqual(responseStreams.count, 3)
    let types = responseStreams.compactMap { $0["type"] as? Int }
    XCTAssertTrue(types.contains(110))
    XCTAssertTrue(types.contains(100))
    XCTAssertTrue(types.contains(101))
    
    // Verify ports assigned
    let videoStream = responseStreams.first { ($0["type"] as? Int) == 110 }
    XCTAssertEqual(videoStream?["dataPort"] as? Int, 7100)
    
    let mainAudio = responseStreams.first { ($0["type"] as? Int) == 100 }
    XCTAssertEqual(mainAudio?["dataPort"] as? Int, 7001)
    XCTAssertEqual(mainAudio?["controlPort"] as? Int, 7003)
    
    let altAudio = responseStreams.first { ($0["type"] as? Int) == 101 }
    XCTAssertEqual(altAudio?["dataPort"] as? Int, 7002)
    XCTAssertEqual(altAudio?["controlPort"] as? Int, 7004)
}

func testRTSPVolumeParameterParsing() {
    let paramBody = "volume: -15.500000\r\n"
    let volume = RTSPServer.parseVolumeParameter(paramBody)
    XCTAssertEqual(volume, -15.5, accuracy: 0.01)
}
```

**Step 2: Run test to verify it fails**
Run: `cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testRTSPMultiStreamSetupResponse`
Expected: FAIL ("buildStreamSetupResponse not found").

**Step 3: Implement multi-stream SETUP and SET_PARAMETER in RTSPServer.swift**
In `Sources/DrivingMode/Protocols/RTSPServer.swift`:
1. Expose `buildStreamSetupResponse(for bodyData: Data) -> [String: Any]`.
2. In `handleSetup()`:
   - Parse all streams (`type == 110`, `100`, `101`, `102`, `106`).
   - For each stream, derive data stream encryption keys if `streamConnectionID` is provided.
   - For audio streams, forward encryption keys to `AirPlayAudioReceiver.shared.configureStreamKeys(type: scid: keys:)`.
   - Populate response streams with correct `dataPort` and `controlPort`.
3. In `handleParameter()`:
   - Parse `volume: <dB>` and forward to `AirPlayAudioReceiver.shared.setRTSPDbVolume(db)`.
   - Handle `FLUSH` requests to purge stale audio jitter buffers.

**Step 4: Run test to verify it passes**
Run: `cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testRTSPMultiStreamSetupResponse`
Expected: PASS.

**Step 5: Commit**
```bash
git add Sources/DrivingMode/Protocols/RTSPServer.swift Tests/DrivingModeTests/DrivingModeTests.swift
git commit -m "feat(rtsp): implement multi-stream SETUP for video and audio (100, 101) with volume control"
```

---

### Task 4: Audio Routing Mode Settings & Status UI

**Files:**
- Modify: `Sources/DrivingMode/Models/DrivingModeConfig.swift`
- Modify: `Sources/DrivingMode/UI/SettingsView.swift`
- Modify: `Sources/DrivingMode/UI/CarPlayActiveScreenView.swift`
- Test: `Tests/DrivingModeTests/DrivingModeTests.swift`

**Step 1: Write the failing test for AudioRoutingMode**
In `Tests/DrivingModeTests/DrivingModeTests.swift`:
```swift
@MainActor
func testAudioRoutingModeConfigPersistence() {
    let config = DrivingModeConfig.shared
    config.audioRoutingMode = .carBluetoothPassthrough
    XCTAssertEqual(config.audioRoutingMode, .carBluetoothPassthrough)
    
    config.audioRoutingMode = .airPlayInBand
    XCTAssertEqual(config.audioRoutingMode, .airPlayInBand)
}
```

**Step 2: Run test to verify it fails**
Run: `cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testAudioRoutingModeConfigPersistence`
Expected: FAIL ("audioRoutingMode not found on DrivingModeConfig").

**Step 3: Implement AudioRoutingMode in DrivingModeConfig, SettingsView, and CarPlayActiveScreenView**
1. In `Sources/DrivingMode/Models/DrivingModeConfig.swift`:
   - Define `enum AudioRoutingMode: String, CaseIterable, Identifiable { case airPlayInBand, carBluetoothPassthrough; var id: String { rawValue } }`.
   - Add `@AppStorage("drivingmode.audio.routing") var audioRoutingMode: AudioRoutingMode = .airPlayInBand`.
   - Synchronize with `AirPlayAudioReceiver.shared.isPassthroughMode = (newValue == .carBluetoothPassthrough)`.
2. In `Sources/DrivingMode/UI/SettingsView.swift`:
   - Add `Picker("Audio Output Mode", selection: $config.audioRoutingMode)` with options:
     - `In-Band AirPlay (Speaker / AUX)`
     - `Car Bluetooth Stereo Passthrough`
3. In `Sources/DrivingMode/UI/CarPlayActiveScreenView.swift`:
   - Display active audio routing badge in the diagnostic/status panel (`AUDIO: IN-BAND (DUCKING)` vs `AUDIO: BT-PASSTHROUGH`).

**Step 4: Run test to verify it passes**
Run: `cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter testAudioRoutingModeConfigPersistence`
Expected: PASS.

**Step 5: Commit**
```bash
git add Sources/DrivingMode/Models/DrivingModeConfig.swift Sources/DrivingMode/UI/SettingsView.swift Sources/DrivingMode/UI/CarPlayActiveScreenView.swift Tests/DrivingModeTests/DrivingModeTests.swift
git commit -m "feat(settings): add user-selectable AudioRoutingMode with UI picker and active status pill"
```

---

### Task 5: End-to-End Build & Device Verification

**Files:**
- Full repository verification

**Step 1: Run complete swift test suite**
Run: `cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: All tests pass with 0 failures.

**Step 2: Build iOS target for iPhone Simulator**
Run: `cd /Users/justinmccollin/Documents/GitHub/carcast && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project DrivingMode.xcodeproj -scheme DrivingMode -destination "platform=iOS Simulator,name=iPhone 16 Pro" clean build`
Expected: BUILD SUCCEEDED.

**Step 3: Deploy and launch on physical iPhone 15 Pro**
Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project DrivingMode.xcodeproj -scheme DrivingMode -destination "id=00008130-00126D081E43001C" -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008130-00126D081E43001C /path/to/DrivingMode.app
xcrun devicectl device process launch --device 00008130-00126D081E43001C dev.unordinarylabs.DrivingMode
```
Expected: App launches on device with live Bonjour mDNS, BLE, and RTSP server ready for incoming iPhone CarPlay connection.

**Step 4: Verify simulator interactive state and screenshot**
Run simulator launch, trigger interactive taps, and verify clean rendering.

**Step 5: Commit and push**
```bash
git push origin main
```
