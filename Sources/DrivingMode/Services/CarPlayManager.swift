//
//  CarPlayManager.swift
//  DrivingMode
//
//  Central coordinator for CarPlay & AirPlay receiver lifecycle and media pipeline.
//

import Foundation
import Combine
import CoreMedia

public enum ReceiverState: String, Sendable {
    case idle = "Ready"
    case starting = "Starting…"
    case waitingForPhone = "Waiting for iPhone"
    case connecting = "Connecting…"
    case streaming = "CarPlay Connected"
    case error = "Error"

    public var statusColor: String {
        switch self {
        case .idle: return "gray"
        case .starting, .waitingForPhone, .connecting: return "yellow"
        case .streaming: return "green"
        case .error: return "red"
        }
    }
}

@MainActor
public final class CarPlayManager: ObservableObject, @unchecked Sendable {
    public static let shared = CarPlayManager()

    @Published public private(set) var state: ReceiverState = .idle
    @Published public private(set) var stateReason: String = "Idle — tap 'This iPhone' or 'Connect' to start receiver"
    @Published public private(set) var connectedClientName: String? = nil
    @Published public private(set) var currentStreamResolution: CGSize = .zero
    @Published public private(set) var isStreamingActive: Bool = false
    @Published public private(set) var isSimulating: Bool = false
    @Published public var lastSampleBuffer: CMSampleBuffer? = nil
    public var hasSampleBuffer: Bool { lastSampleBuffer != nil }
    public var onSampleBuffer: ((CMSampleBuffer) -> Void)? = nil
    @Published public private(set) var totalFramesReceived: Int = 0
    @Published public private(set) var lastFrameTime: Date? = nil
    private var internalFrameCount: Int = 0

    private let rtspServer: RTSPServer
    private let screenReceiver: AirPlayScreenReceiver
    private let bonjourAdvertiser: AirPlayBonjourAdvertiser
    private let iap2Engine: iAP2ProtocolEngine

    private init() {
        self.rtspServer = RTSPServer(port: 7000)
        self.screenReceiver = AirPlayScreenReceiver(port: 7100)
        self.bonjourAdvertiser = AirPlayBonjourAdvertiser(port: 7000)
        self.iap2Engine = iAP2ProtocolEngine()

        self.screenReceiver.delegate = self
        self.rtspServer.delegate = self
        self.iap2Engine.delegate = self

        self.iap2Engine.onSendData = { data in
            CarPlayBluetoothAdvertiser.shared.sendData(data)
        }
        CarPlayBluetoothAdvertiser.shared.onDataReceived = { [weak self] data in
            self?.iap2Engine.handleIncomingBytes(data)
        }
        CarPlayBluetoothAdvertiser.shared.onCentralConnectionChanged = { [weak self] count, detail in
            Task { @MainActor [weak self] in
                guard let self = self, self.state == .waitingForPhone else { return }
                self.transitionState(
                    to: .waitingForPhone,
                    reason: "\(detail) (subscribedCentrals=\(count))",
                    source: "CarPlayBluetoothAdvertiser"
                )
            }
        }
        CarPlayLockdownService.shared.onStateReasonChanged = { [weak self] suggestedState, reason in
            Task { @MainActor [weak self] in
                guard let self = self, self.state != .idle, self.state != .streaming else { return }
                self.transitionState(
                    to: suggestedState,
                    reason: reason,
                    source: "CarPlayLockdownService(\(CarPlayLockdownService.shared.currentPhase))"
                )
            }
        }
        setupTouchTriggerWatcher()
        DeveloperTouchService.shared.start()
    }

    public func transitionState(to newState: ReceiverState, reason: String, source: String) {
        let oldState = self.state
        self.state = newState
        self.stateReason = reason

        let bleAdv = CarPlayBluetoothAdvertiser.shared.isAdvertising ? 1 : 0
        let bleCentrals = CarPlayBluetoothAdvertiser.shared.subscribedCentralCount
        let lockdownPhase = CarPlayLockdownService.shared.currentPhase
        let rtspPort = rtspServer.boundPort
        let rtspConns = rtspServer.activeConnectionCount
        let screenActive = isStreamingActive ? 1 : 0

        writeAppLog("[State] \(oldState.rawValue) -> \(newState.rawValue) [\(source)] \(reason)")
        NSLog(
            "[DrivingMode][State] %@ -> %@ [source=%@] reason=%@ | BLE(adv=%d, centrals=%d) | Lockdown(phase=%@) | RTSP(port=%d, conns=%d) | Screen(active=%d, frames=%d)",
            oldState.rawValue,
            newState.rawValue,
            source,
            reason,
            bleAdv,
            bleCentrals,
            lockdownPhase,
            rtspPort,
            rtspConns,
            screenActive,
            totalFramesReceived
        )

        ProtocolLogger.shared.log(
            category: .system,
            title: "State: \(newState.rawValue) [\(source)]",
            detail: "\(reason) | BLE(adv=\(bleAdv), centrals=\(bleCentrals)) | Lockdown(\(lockdownPhase)) | RTSP(:\(rtspPort), conns=\(rtspConns))"
        )
    }

    public func startReceiver() {
        if isStreamingActive { return }
        #if targetEnvironment(simulator)
        startLocalSimulation()
        return
        #else
        transitionState(
            to: .starting,
            reason: "Starting RTSP (:7000), AirPlay Screen (:7100), BLE Advertiser, and ACCTransport Lockdown",
            source: "CarPlayManager.startReceiver"
        )

        let config = DrivingModeConfig.shared
        let carName = config.carName
        let deviceId = config.deviceId

        do {
            try rtspServer.start()
            try screenReceiver.start()

            // Start Bluetooth CarPlay advertisement so iOS Settings > General > CarPlay discovers the vehicle
            CarPlayBluetoothAdvertiser.shared.startAdvertising(carName: carName)

            // Start Bonjour mDNS advertisement (_airplay._tcp, _raop._tcp, _carplay._tcp, _drivingmode._tcp)
            self.bonjourAdvertiser.startAdvertising(name: carName, deviceId: deviceId)

            let boundRtspPort: UInt16 = rtspServer.boundPort != 0 ? rtspServer.boundPort : 7000
            let currentIP = WiFiNetworkService.shared.currentIPAddress ?? "192.168.86.46"
            let currentSSID = config.wifiSSID.isEmpty ? "HiFi" : config.wifiSSID
            NSLog("[DrivingMode][Network] Selected CarPlay IP=%@ (interfaces: %@)", currentIP, WiFiNetworkService.shared.ipv4InterfaceSummary)

            // Launch CoreAccessories iAP2 lockdown ignition sequence
            CarPlayLockdownService.shared.startSession(
                rtspPort: boundRtspPort,
                ip: currentIP,
                ssid: currentSSID,
                passphrase: config.wifiPassphrase,
                carName: carName,
                deviceId: deviceId
            )

            transitionState(
                to: .waitingForPhone,
                reason: "BLE advertising is active (external phones only, centrals=0); waiting for local accessoryd iAP2 handshake & RTSP connection on \(currentIP):\(boundRtspPort)",
                source: "CarPlayManager.startReceiver"
            )

            ProtocolLogger.shared.log(
                category: .system,
                title: "CarPlay Receiver Started",
                detail: "Name: \(carName) (ID: \(deviceId)) | RTSP :\(boundRtspPort) | Screen :7100"
            )
        } catch {
            transitionState(
                to: .error,
                reason: "Failed to start RTSP/Screen listeners: \(error.localizedDescription)",
                source: "CarPlayManager.startReceiver"
            )
            ProtocolLogger.shared.log(
                category: .system,
                title: "Failed to Start Receiver",
                detail: error.localizedDescription
            )
        }
        #endif
    }

    private var simulationTimer: Timer?

    public func enqueueLoopbackSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        self.lastSampleBuffer = sampleBuffer
        self.totalFramesReceived += 1
        self.lastFrameTime = Date()
        if !self.isStreamingActive {
            self.isStreamingActive = true
            self.transitionState(
                to: .streaming,
                reason: "Receiving H.264 sample buffers from loopback stream",
                source: "CarPlayManager.enqueueLoopbackSampleBuffer"
            )
            if self.connectedClientName == nil {
                self.connectedClientName = "This iPhone"
            }
            self.currentStreamResolution = CGSize(width: 1344, height: 720)
        }
        self.onSampleBuffer?(sampleBuffer)
    }

    public func startLocalSimulation() {
        isSimulating = true
        #if !targetEnvironment(simulator)
        if state == .idle || state == .error {
            startReceiver()
        }
        #endif

        isStreamingActive = true
        transitionState(
            to: .streaming,
            reason: "Local CarPlay simulation active on loopback head unit",
            source: "CarPlayManager.startLocalSimulation"
        )
        connectedClientName = "This iPhone"
        currentStreamResolution = CGSize(width: 1344, height: 720)

        ProtocolLogger.shared.log(
            category: .system,
            title: "Local CarPlay Simulation Active",
            detail: "Loopback head unit running on device"
        )

        // Start dynamic vehicle telemetry loop for cockpit cluster
        simulationTimer?.invalidate()
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isStreamingActive else { return }
                self.totalFramesReceived += 6 // simulate 60fps frame increments
                let t = Date().timeIntervalSince1970
                let speed = 45.0 + 20.0 * sin(t * 0.3)
                let rpm = 2200.0 + 1200.0 * sin(t * 0.8)
                let gear = speed < 15 ? "1" : (speed < 30 ? "2" : (speed < 45 ? "3" : (speed < 60 ? "4" : "D")))

                VehicleTelemetry.shared.updateDriving(
                    speed: max(0, speed),
                    rpm: max(800, rpm),
                    gear: gear,
                    turnSignal: sin(t * 0.2) > 0.7 ? .left : (sin(t * 0.2) < -0.7 ? .right : .off)
                )
            }
        }
    }

    public func stopReceiver() {
        isSimulating = false
        simulationTimer?.invalidate()
        simulationTimer = nil
        CarPlayLockdownService.shared.stopSession()
        CarPlayBluetoothAdvertiser.shared.stopAdvertising()
        bonjourAdvertiser.stopAdvertising()
        screenReceiver.stop()
        rtspServer.stop()

        transitionState(
            to: .idle,
            reason: "Receiver stopped by user",
            source: "CarPlayManager.stopReceiver"
        )
        connectedClientName = nil
        isStreamingActive = false
        currentStreamResolution = .zero
        lastSampleBuffer = nil

        ProtocolLogger.shared.log(category: .system, title: "CarPlay Receiver Stopped")
    }

    public func returnToCarPlay() {
        // Triggers UI shift back to full screen CarPlay
        if isStreamingActive {
            transitionState(
                to: .streaming,
                reason: "Returned to active CarPlay video stream",
                source: "CarPlayManager.returnToCarPlay"
            )
        }
    }

    public func sendTouchEvent(action: Int, x: Double, y: Double) {
        if isSimulating {
            return
        }
        // Forward normalized touch to iPhone with primary input device uuid "0"
        rtspServer.sendTouchHIDReport(action: action, x: x, y: y, uuid: "0")
        ProtocolLogger.shared.log(
            category: .screen,
            direction: .tx,
            title: "Touch Event",
            detail: "Action: \(action) (X: \(String(format: "%.3f", x)), Y: \(String(format: "%.3f", y)))"
        )
    }

    private var touchTriggerTimer: DispatchSourceTimer?

    public func simulateTap(x: Double, y: Double) {
        writeAppLog("[TouchWatcher] Executing tap at x=\(x), y=\(y)")
        sendTouchEvent(action: 1, x: x, y: y)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            self?.sendTouchEvent(action: 0, x: x, y: y)
        }
    }

    private func setupTouchTriggerWatcher() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 0.2, repeating: 0.2)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fileURL = docs.appendingPathComponent("touch_trigger.json")
                if let data = try? Data(contentsOf: fileURL),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    try? FileManager.default.removeItem(at: fileURL)
                    if let home = json["home"] as? Bool, home {
                        writeAppLog("[TouchWatcher] Triggering HOME button")
                        self.sendHomeButtonPress()
                    } else if let x = json["x"] as? Double, let y = json["y"] as? Double {
                        writeAppLog("[TouchWatcher] Triggering tap at x=\(x), y=\(y)")
                        self.simulateTap(x: x, y: y)
                    }
                }
            }
        }
        timer.resume()
        self.touchTriggerTimer = timer
    }

    public func sendHomeButtonPress() {
        writeAppLog("[HID] Sending Knob & Buttons Home press")
        rtspServer.sendHomeButtonHIDReport()
        ProtocolLogger.shared.log(
            category: .screen,
            direction: .tx,
            title: "Home Button Pressed",
            detail: "Sending Home HID report to CarPlay"
        )
    }

    public func requestKeyFrame() {
        rtspServer.requestKeyFrame()
    }
}

extension CarPlayManager: AirPlayScreenReceiverDelegate {
    nonisolated public func screenReceiverDidReceiveSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // Deliver every frame straight to the display layer(s); only publish SwiftUI state for the first frame and
        // about once per second so the whole view tree doesn't re-render at 60 fps.
        VideoFrameBus.shared.publish(sampleBuffer)
        Task { @MainActor in
            self.internalFrameCount += 1
            if self.lastSampleBuffer == nil || self.internalFrameCount % 60 == 0 {
                self.totalFramesReceived = self.internalFrameCount
                self.lastSampleBuffer = sampleBuffer
                self.lastFrameTime = Date()
            }
            self.onSampleBuffer?(sampleBuffer)
        }
    }

    nonisolated public func screenReceiverDidReceiveDimensions(width: Int, height: Int) {
        Task { @MainActor in
            self.currentStreamResolution = CGSize(width: width, height: height)
        }
    }

    nonisolated public func screenReceiverStateChanged(isActive: Bool) {
        Task { @MainActor [weak self] in
            guard let self = self, !self.isSimulating else { return }
            guard self.state != .idle else {
                self.isStreamingActive = false
                return
            }
            self.isStreamingActive = isActive
            if isActive {
                self.transitionState(
                    to: .streaming,
                    reason: "AirPlay H.264 screen stream connected on TCP :7100",
                    source: "AirPlayScreenReceiver.screenReceiverStateChanged(true)"
                )
                self.rtspServer.requestKeyFrame()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.rtspServer.requestKeyFrame()
                }
            } else if self.state == .streaming {
                self.transitionState(
                    to: .waitingForPhone,
                    reason: "AirPlay H.264 screen stream on TCP :7100 disconnected; waiting for phone to reconnect",
                    source: "AirPlayScreenReceiver.screenReceiverStateChanged(false)"
                )
            }
        }
    }

    nonisolated public func screenReceiverNeedsKeyFrame() {
        Task { @MainActor in
            self.rtspServer.requestKeyFrame()
        }
    }
}

extension CarPlayManager: RTSPServerDelegate {
    nonisolated public func rtspServerDidStartSession(clientName: String?) {
        Task { @MainActor in
            self.connectedClientName = clientName ?? "iPhone"
            self.transitionState(
                to: .connecting,
                reason: "RTSP ANNOUNCE received from \(clientName ?? "iPhone"); negotiating video stream setup",
                source: "RTSPServer.rtspServerDidStartSession"
            )
        }
    }

    nonisolated public func rtspServerDidEndSession() {
        Task { @MainActor in
            guard self.state != .idle else { return }
            self.connectedClientName = nil
            self.isStreamingActive = false
            self.transitionState(
                to: .waitingForPhone,
                reason: "RTSP TEARDOWN received; CarPlay session ended, waiting for iPhone",
                source: "RTSPServer.rtspServerDidEndSession"
            )
        }
    }

    nonisolated public func rtspServerDidUpdateVolume(_ volume: Float) {}
}

extension CarPlayManager: iAP2ProtocolDelegate {
    nonisolated public func iap2DidReceiveIdentificationAccepted() {
        Task { @MainActor in
            self.transitionState(
                to: .streaming,
                reason: "iAP2 IdentificationAccepted received over BLE",
                source: "iAP2ProtocolEngine.iap2DidReceiveIdentificationAccepted"
            )
        }
    }

    nonisolated public func iap2DidReceiveIdentificationRejected() {
        Task { @MainActor in
            self.transitionState(
                to: .error,
                reason: "iAP2 IdentificationRejected received over BLE",
                source: "iAP2ProtocolEngine.iap2DidReceiveIdentificationRejected"
            )
        }
    }

    nonisolated public func iap2DidReceiveRequestStartCarPlay() {
        Task { @MainActor in
            self.transitionState(
                to: .connecting,
                reason: "iAP2 RequestStartCarPlay received over BLE",
                source: "iAP2ProtocolEngine.iap2DidReceiveRequestStartCarPlay"
            )
        }
    }

    nonisolated public func iap2DidReceiveNowPlayingUpdate(
        title: String,
        artist: String,
        album: String,
        duration: Double,
        elapsed: Double
    ) {
        Task { @MainActor in
            VehicleTelemetry.shared.updateNowPlaying(
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                elapsed: elapsed
            )
        }
    }

    nonisolated public func iap2DidReceiveArtwork(data: Data) {
        Task { @MainActor in
            VehicleTelemetry.shared.albumArtworkData = data
        }
    }

    nonisolated public func iap2DidRequestUI(mode: String?) {
        Task { @MainActor in
            // Return to native car UI
            self.transitionState(
                to: .waitingForPhone,
                reason: "iAP2 RequestUI(mode=\(mode ?? "nil")) requested return to native car UI",
                source: "iAP2ProtocolEngine.iap2DidRequestUI"
            )
        }
    }

    nonisolated public func iap2SessionEnded() {
        Task { @MainActor in
            guard self.state != .idle else { return }
            self.isStreamingActive = false
            self.transitionState(
                to: .waitingForPhone,
                reason: "iAP2 session ended; waiting for iPhone to reconnect",
                source: "iAP2ProtocolEngine.iap2SessionEnded"
            )
        }
    }
}


/// Thread-safe fan-out of decoded CarPlay video sample buffers to on-screen AVSampleBufferDisplayLayers.
public final class VideoFrameBus: @unchecked Sendable {
    public static let shared = VideoFrameBus()
    private let lock = NSLock()
    private var observers: [ObjectIdentifier: (CMSampleBuffer) -> Void] = [:]
    private var lastBuffer: CMSampleBuffer?

    public func add(_ owner: AnyObject, handler: @escaping (CMSampleBuffer) -> Void) {
        lock.lock()
        observers[ObjectIdentifier(owner)] = handler
        let cached = lastBuffer
        lock.unlock()
        if let buf = cached {
            handler(buf)
        }
        Task { @MainActor in
            CarPlayManager.shared.requestKeyFrame()
        }
    }

    public func remove(_ owner: AnyObject) {
        lock.lock(); observers[ObjectIdentifier(owner)] = nil; lock.unlock()
    }

    public func publish(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        lastBuffer = sampleBuffer
        let handlers = Array(observers.values)
        lock.unlock()
        handlers.forEach { $0(sampleBuffer) }
    }
}

// MARK: - Developer Touch Service
import Network

public final class DeveloperTouchService: @unchecked Sendable {
    public static let shared = DeveloperTouchService()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "dev.unordinarylabs.drivingmode.devtouch")

    private init() {}

    public func start() {
        queue.async { [weak self] in
            guard let self = self, self.listener == nil else { return }
            do {
                let params = NWParameters.tcp
                let listener = try NWListener(using: params, on: 8999)
                listener.stateUpdateHandler = { state in
                    writeAppLog("[DevTouch] Listener state: \(state)")
                }
                listener.newConnectionHandler = { [weak self] conn in
                    self?.handleConnection(conn)
                }
                listener.start(queue: self.queue)
                self.listener = listener
                writeAppLog("[DevTouch] Server listening on port 8999")
            } catch {
                writeAppLog("[DevTouch] Failed to start listener: \(error)")
            }
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.listener?.cancel()
            self?.listener = nil
        }
    }

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak conn] data, _, _, _ in
            guard let conn = conn, let data = data, let req = String(data: data, encoding: .utf8) else {
                conn?.cancel()
                return
            }

            let firstLine = req.components(separatedBy: "\r\n").first ?? ""
            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2 else {
                conn.cancel()
                return
            }

            let path = String(parts[1])
            var responseJson = "{\"ok\": true}"

            if path.starts(with: "/tap") {
                var x = 0.5
                var y = 0.5
                if let urlComponents = URLComponents(string: "http://localhost" + path) {
                    if let xStr = urlComponents.queryItems?.first(where: { $0.name == "x" })?.value, let xVal = Double(xStr) {
                        x = xVal
                    }
                    if let yStr = urlComponents.queryItems?.first(where: { $0.name == "y" })?.value, let yVal = Double(yStr) {
                        y = yVal
                    }
                }
                writeAppLog("[DevTouch] Received HTTP /tap request (x=\(x), y=\(y))")
                DispatchQueue.main.async {
                    CarPlayManager.shared.simulateTap(x: x, y: y)
                }
                responseJson = "{\"ok\": true, \"action\": \"tap\", \"x\": \(x), \"y\": \(y)}"
            } else if path.starts(with: "/home") {
                writeAppLog("[DevTouch] Received HTTP /home request")
                DispatchQueue.main.async {
                    CarPlayManager.shared.sendHomeButtonPress()
                }
                responseJson = "{\"ok\": true, \"action\": \"home\"}"
            } else if path.starts(with: "/menu") {
                writeAppLog("[DevTouch] Received HTTP /menu request")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .returnToMainMenu, object: nil)
                }
                responseJson = "{\"ok\": true, \"action\": \"menu\"}"
            } else if path.starts(with: "/carplay") {
                writeAppLog("[DevTouch] Received HTTP /carplay request")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .returnToCarPlay, object: nil)
                }
                responseJson = "{\"ok\": true, \"action\": \"carplay\"}"
            } else if path.starts(with: "/dashcam") {
                writeAppLog("[DevTouch] Received HTTP /dashcam request")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .toggleDashcam, object: nil)
                }
                responseJson = "{\"ok\": true, \"action\": \"dashcam\"}"
            } else if path.starts(with: "/keyframe") {
                writeAppLog("[DevTouch] Received HTTP /keyframe request")
                DispatchQueue.main.async {
                    CarPlayManager.shared.requestKeyFrame()
                }
                responseJson = "{\"ok\": true, \"action\": \"keyframe\"}"
            } else if path.starts(with: "/logs") {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                let logUrl = docs?.appendingPathComponent("status.txt")
                let content = (logUrl != nil ? (try? String(contentsOf: logUrl!)) : nil) ?? "No logs yet"
                let httpResp = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(content.utf8.count)\r\nConnection: close\r\n\r\n\(content)"
                conn.send(content: httpResp.data(using: .utf8), completion: .contentProcessed { _ in
                    conn.cancel()
                })
                return
            } else if path.starts(with: "/status") {
                DispatchQueue.main.async {
                    let state = CarPlayManager.shared.state.rawValue
                    let frames = CarPlayManager.shared.totalFramesReceived
                    let active = CarPlayManager.shared.isStreamingActive
                    let statusJson = "{\"ok\": true, \"state\": \"\(state)\", \"frames\": \(frames), \"streaming\": \(active)}"
                    let httpResp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(statusJson.utf8.count)\r\nConnection: close\r\n\r\n\(statusJson)"
                    conn.send(content: httpResp.data(using: .utf8), completion: .contentProcessed { _ in
                        conn.cancel()
                    })
                }
                return
            }

            let httpResp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(responseJson.utf8.count)\r\nConnection: close\r\n\r\n\(responseJson)"
            conn.send(content: httpResp.data(using: .utf8), completion: .contentProcessed { _ in
                conn.cancel()
            })
        }
    }
}

public extension Notification.Name {
    static let returnToMainMenu = Notification.Name("dev.unordinarylabs.drivingmode.returnToMainMenu")
    static let returnToCarPlay = Notification.Name("dev.unordinarylabs.drivingmode.returnToCarPlay")
    static let toggleDashcam = Notification.Name("dev.unordinarylabs.drivingmode.toggleDashcam")
}
