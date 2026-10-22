# Design Document: Forcing Actual Apple CarPlay Video Stream

**Date**: 2026-10-21  
**Author**: Antigravity  
**Status**: Approved  

---

## 1. Objective

Completely eliminate all simulated SwiftUI CarPlay replicas, faux docks, mock app grids, and drawn split dashboards in CarCast. Replace them with a dedicated, hardware-accelerated **Apple CarPlay H.264 video streaming pipeline** (`AVSampleBufferDisplayLayer`) that renders the authentic, genuine Apple CarPlay stream broadcast from a connected iPhone over Wi-Fi / AirPlay (ports 7000 RTSP, 7100 Screen).

---

## 2. Key Architecture & Components

### 2.1 Video Stream Display Layer (`VideoCanvasView.swift`)
- **Direct Hardware Decoding**: Bind directly to `AVSampleBufferDisplayLayer` via `RawVideoCanvasView` with low-latency real-time decompression.
- **Eliminate Faux Desktop**: Remove `CarPlayHomeDesktopView` and all mock iOS apps/docks.
- **Authentic Receiver Standby State**: When no active video stream is incoming (`manager.lastSampleBuffer == nil`), present a native, high-tech automotive receiver standby interface:
  - Active Bonjour advertisement status (`_airplay._tcp`, `_carplay._tcp`)
  - Server socket endpoints (RTSP `:7000`, Video `:7100`)
  - Vehicle identification profile (`CarCast-XXXX`)
  - Clear connection readiness and wireless pairing instructions.

### 2.2 Live CarPlay Stream in Ultra Cluster (`CarPlayUltraClusterView.swift`)
- **Primary Viewport**: Embed the live `VideoCanvasView` receiving genuine Apple CarPlay frames.
- **Display Modes**:
  1. **Full Stream Mode**: Edge-to-edge uncompromised Apple CarPlay stream.
  2. **Cluster Split Mode**: Live Apple CarPlay stream flanked by native hardware instruments (real GPS speed, CoreLocation compass heading, and vehicle telemetry).
- **Zero Mock UI**: No simulated iOS CarPlay controls, no faux turn banners, no fake Apple Maps canvas.

### 2.3 Stream Coordination & Lifecycle (`CarPlayManager.swift`)
- Ensure immediate socket binding and Bonjour advertisement when navigating to CarPlay screens.
- Feed `CMSampleBuffer`s directly from `AirPlayScreenReceiver` to the video canvas with minimal latency.

---

## 3. Verification & Validation
- Unit tests (`swift test`) pass without regression.
- Project compiles cleanly for iOS Simulator and physical hardware (`00008130-00126D081E43001C`).
- Screen capture verification of standby and streaming states.
