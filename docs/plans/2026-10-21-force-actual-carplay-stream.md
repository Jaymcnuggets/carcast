# Force Actual Apple CarPlay Video Stream Implementation Plan

> **For Antigravity:** REQUIRED SUB-SKILL: Load executing-plans to implement this plan task-by-task.

**Goal:** Eliminate all simulated SwiftUI CarPlay replicas, faux docks, and mock app grids in CarCast, replacing them with a dedicated, hardware-accelerated Apple CarPlay video streaming pipeline (`AVSampleBufferDisplayLayer`) that displays genuine Apple CarPlay broadcast from a connecting iPhone over Wi-Fi / AirPlay.

**Architecture:** Purge `CarPlayHomeDesktopView` and mock views from `VideoCanvasView.swift` and `CarPlayUltraClusterView.swift`. Drive the display exclusively via `RawVideoCanvasView` (`AVSampleBufferDisplayLayer`) fed by `AirPlayScreenReceiver`. When no phone is streaming, present an authentic high-tech AirPlay receiver standby console rather than a simulated iOS replica.

**Tech Stack:** Swift 5.10, SwiftUI, AVFoundation (`AVSampleBufferDisplayLayer`), CoreMedia (`CMSampleBuffer`), Network.framework (Bonjour, RTSP port 7000, Screen port 7100).

---

### Task 1: Refactor `VideoCanvasView.swift` for Direct Hardware Video & Authentic Standby

**Files:**
- Modify: `Sources/CarCast/UI/VideoCanvasView.swift`
- Test: `Tests/CarCastTests/CarCastTests.swift`

**Step 1: Inspect and verify existing tests**
Run: `swift test`
Expected: 8 tests passing

**Step 2: Refactor `VideoCanvasView.swift`**
- Delete `CarPlayHomeDesktopView` and all child fake app views (music mock, maps mock, dock bar mock).
- When `manager.lastSampleBuffer != nil`, display `RawVideoCanvasView` with full hardware acceleration.
- When `manager.lastSampleBuffer == nil`, display `AirPlayReceiverStandbyView`:
  - Authentic radar / listener pulse
  - Real-time Bonjour advertising status (`_airplay._tcp`, `_carplay._tcp`)
  - Server endpoints (RTSP `:7000`, Video `:7100`)
  - Active vehicle identifier and connection guide

**Step 3: Run tests to verify no compilation errors**
Run: `swift test`
Expected: PASS

**Step 4: Commit**
```bash
git add Sources/CarCast/UI/VideoCanvasView.swift
git commit -m "refactor(video): remove mock CarPlay desktop, force hardware video layer with authentic receiver standby"
```

---

### Task 2: Refactor `CarPlayUltraClusterView.swift` to Embed Live Stream

**Files:**
- Modify: `Sources/CarCast/UI/CarPlayUltraClusterView.swift`
- Test: `Tests/CarCastTests/CarCastTests.swift`

**Step 1: Refactor `CarPlayUltraClusterView.swift`**
- Replace the replicated SwiftUI split dashboard and fake dock with embedded `VideoCanvasView`.
- Support two display modes:
  1. `Full Video Stream`: Uncompromised edge-to-edge Apple CarPlay stream.
  2. `Cockpit Cluster`: Center live Apple CarPlay stream bordered by native vehicle instruments (live GPS speedometer, compass heading, telemetry).
- Remove fake app launcher grids, fake wallpapers, and mock docks.

**Step 2: Run tests to verify compilation**
Run: `swift test`
Expected: PASS

**Step 3: Commit**
```bash
git add Sources/CarCast/UI/CarPlayUltraClusterView.swift
git commit -m "feat(cluster): embed live CarPlay video stream into digital instrument cluster"
```

---

### Task 3: Stream Lifecycle & Auto-Receiver Activation

**Files:**
- Modify: `Sources/CarCast/Services/CarPlayManager.swift`
- Test: `Tests/CarCastTests/CarCastTests.swift`

**Step 1: Ensure receiver auto-start and stream readiness**
- Ensure `CarPlayManager.shared.startReceiver()` automatically binds ports 7000 and 7100 and starts Bonjour advertisement when entering any CarPlay screen.
- Verify `lastSampleBuffer` publishing cleanly propagates to `VideoCanvasView`.

**Step 2: Run tests**
Run: `swift test`
Expected: PASS

**Step 3: Commit**
```bash
git add Sources/CarCast/Services/CarPlayManager.swift
git commit -m "fix(manager): ensure automatic receiver startup and seamless frame binding"
```

---

### Task 4: Hardware Build, Verification & Framebuffer Capture

**Files:**
- Modify: `carcast_views_and_deployment.md`
- Output: `02_cluster.png`

**Step 1: Build for physical iPhone 15 Pro & Simulator**
Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CarCast.xcodeproj -scheme CarCast -destination id=00008130-00126D081E43001C -configuration Debug build`
Expected: BUILD SUCCEEDED

**Step 2: Deploy to physical device**
Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl device install app --device 00008130-00126D081E43001C ...`
Expected: App installed

**Step 3: Capture Simulator framebuffer**
Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl io 9FF422C6-2087-4F67-BE51-8518FC631997 screenshot ...`
Expected: Clean screenshot of genuine standby / live stream layer

**Step 4: Commit and push**
```bash
git add .
git commit -m "chore: verify live CarPlay streaming pipeline and update device reports"
git push origin main
```
