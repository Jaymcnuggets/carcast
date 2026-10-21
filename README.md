# CarCast — Multiplatform CarPlay Receiver Engine

<p align="center">
  <strong>Native 1:1 Ground-Truth Apple CarPlay Receiver, Protocol Engine, and Digital Instrument Cluster</strong><br>
  Reverse-engineered with Ghidra, REA, and JADX from CarCast native binaries and MFi iAP2 protocol specifications.
</p>

---

## Overview

**CarCast** turns an iOS or iPadOS device (or Mac) into an authentic Apple CarPlay Head Unit receiver and digital instrument cluster. It can run in **"This iPhone"** loopback mode for local simulation, **"Head Unit Mode"** over Wi-Fi / Bonjour to accept incoming wireless CarPlay connections from other iPhones, or **"Connect"** mode to mirror to remote displays.

Every protocol frame, video depacketizer opcode, accessory identification handshake, and UI layout is reconstructed from deep reverse-engineering of `libcarcast.so`, `libairplay.so`, and Dalvik bytecode extracted from the official CarCast releases.

---

## Reverse Engineering & Protocol Architecture

### 1. MFi iAP2 Framing & Accessory Identification (`iAP2ProtocolEngine.swift`)
- **Packet Structure**:
  - Sync Bytes: `0xFF 0x5A`
  - 2-byte Big-Endian Length (inclusive of header and checksum)
  - Control byte (`SYN 0x80`, `ACK 0x40`, `EAK 0x20`, `RST 0x10`)
  - Packet Sequence Number & Acknowledgment Sequence Number
  - Session Identifier
  - Header Checksum: 2's complement of header sum ($\sum + \text{csum} = 0$)
  - Payload + 1-byte Payload Checksum
- **CarPlay Identification Handshake**:
  - Message `0x1D01` (`StartIdentification`)
  - Sub-element `0x0018` (`Transport.WirelessCarPlay.WifiCarPlayTransport1`): Encodes SSID, WPA2 passphrase, Wi-Fi Channel, MAC address, and IPv6 link-local endpoint (`fe80::...`).
  - Vehicle telemetry & metadata exchange (Manufacturer, Model, Serial, Firmware).

### 2. RTSP Control Protocol (`RTSPServer.swift`)
- Listens on TCP port `7000`.
- Implements RFC 2326 streaming control:
  - `OPTIONS`: Advertises server capabilities (`org.airplay.srclist`, `playback-info`).
  - `ANNOUNCE`: Receives SDP session descriptions with video format (`H.264/90000`) and audio parameters (`AAC-ELD` / `L16`).
  - `SETUP`: Allocates streaming sessions, server ports (port `7100` video, `7002` audio).
  - `RECORD`: Starts streaming timeline.
  - `GET_PARAMETER` / `SET_PARAMETER`: Volume control, display latency, metadata, and keep-alives.
  - `TEARDOWN`: Graceful stream termination.

### 3. AirPlay Video Stream Receiver (`AirPlayScreenReceiver.swift`)
- Listens on TCP port `7100`.
- Depacketizes 8-byte big-endian binary headers:
  - `0x0001`: SPS / PPS parameter sets. Initializes `CMVideoFormatDescription`.
  - `0x0000`: Video Frame NALUs. Synthesizes `CMSampleBuffer` instances directly rendered to hardware `AVSampleBufferDisplayLayer`.
  - `0x0002`: Heartbeat / Keep-Alive.

### 4. 114 OEM Car Brand Logos (`CarBrandCatalog.swift`)
- Complete database of 114 manufacturer logos and Chinese localized brand names (`logos.json`).
- High-resolution SVG-derived PNG assets (`120x120`, `180x180`, `256x256`) bundled for all major global manufacturers (Lexus, Porsche, BMW, Ferrari, Tesla, Audi, Aston Martin, etc.).

---

## Features

- 🏎️ **CarPlay Ultra Cluster**: Full digital cockpit instrument cluster with RPM dial, speedometer, fuel level, range, turn signals, and interactive Now Playing music widget.
- 🔍 **Real-Time Protocol Inspector**: Visual network sniffer capturing iAP2, RTSP, Bonjour, and Screen frame packets with color-coded badges, timestamps, and hex dumps.
- 📐 **Display Presets**: Fit Screen, Stretch, and Native Pillarbox/Letterbox aspect ratio modes.
- 🕹️ **Touch Forwarding**: Normalizes touch and pointer coordinates from display layer back to the CarPlay device coordinates.
- 📡 **Bonjour Discovery**: Automatically advertises `_airplay._tcp`, `_carplay._tcp`, and `_carcast._tcp` over the local network.

---

## Directory Structure

```
carcast/
├── Sources/CarCast/
│   ├── CarCastApp.swift               # App Lifecycle & State Injection
│   ├── Models/
│   │   ├── CarBrandCatalog.swift      # 114 OEM Brand Parser & Logo Resolver
│   │   ├── CarCastConfig.swift        # App & Vehicle Settings
│   │   ├── ProtocolMessage.swift      # Real-time Circular Protocol Logger
│   │   └── VehicleTelemetry.swift     # Speed, RPM, Fuel, & Now Playing State
│   ├── Protocols/
│   │   ├── iAP2ProtocolEngine.swift   # 0xFF 0x5A Framing, Sync, Handshake
│   │   ├── RTSPServer.swift           # Port 7000 RTSP Server
│   │   └── AirPlayScreenReceiver.swift# Port 7100 Video Depacketizer & Frame Synthesizer
│   ├── Services/
│   │   ├── AirPlayBonjourAdvertiser.swift # _airplay, _carplay Bonjour Advertiser
│   │   ├── AirPlayBonjourBrowser.swift    # Remote Receiver Network Browser
│   │   └── CarPlayManager.swift       # Orchestrator & Touch Coordinator
│   └── UI/
│       ├── DashboardHomeView.swift    # Cockpit Control Center
│       ├── CarPlayActiveScreenView.swift # Full-Screen CarPlay Display Layer
│       ├── CarPlayUltraClusterView.swift # Next-Gen Instrument Cluster
│       ├── ProtocolInspectorView.swift# Packet Sniffer & Hex Inspector
│       ├── SettingsView.swift         # Vehicle & Audio Config
│       ├── ConnectRemoteView.swift    # Remote Radar & Casting
│       └── VideoCanvasView.swift      # AVSampleBufferDisplayLayer View
├── Tests/CarCastTests/
│   └── CarCastTests.swift             # Unit & Framing Tests
├── Resources/
│   ├── logos.json                     # 114 OEM Car Brands
│   ├── Logos/                         # 342 High-Res Brand Icons (120, 180, 256)
│   └── AppIcon/                       # Launcher Assets
├── Info.plist                         # Bonjour & Network Capabilities
├── CarCast.entitlements               # App Sandbox & Entitlements
├── project.yml                        # XcodeGen Specification
└── Package.swift                      # Swift Package Definition
```

---

## Building and Running

### Prerequisites
- macOS 14.0+
- Xcode 16.0+ (iOS 17.0+ SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### 1. Run Unit Tests via Swift Package Manager
```bash
swift test
```

### 2. Generate Xcode Project
```bash
xcodegen generate
```

### 3. Build & Install to Connected iPhone via Devicectl
```bash
# Build Debug binary
xcodebuild -project CarCast.xcodeproj -scheme CarCast -destination "generic/platform=iOS" -configuration Debug build

# Install to paired device
xcrun devicectl device install app --device <DEVICE_UDID> path/to/CarCast.app
```

---

## License

Reverse-engineered for interoperability, research, and non-commercial educational purposes.
CarPlay is a trademark of Apple Inc. All vehicle brand trademarks and logos belong to their respective owners.
