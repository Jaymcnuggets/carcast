//
//  AirPlayAudioReceiver.swift
//  DrivingMode
//
//  Authentic CarPlay AirPlay Audio Receiver Engine.
//  Handles Stream 100/102 (Main Media Audio) on port 7001 and
//  Stream 101/106 (Alt / Siri / Turn-by-Turn Navigation) on port 7002.
//  Includes automatic ducking and car Bluetooth passthrough support.
//

import Foundation
import AVFoundation
import Network

public final class AirPlayAudioReceiver: @unchecked Sendable {
    public static let shared = AirPlayAudioReceiver()

    public struct RTPPacket: Sendable {
        public let sequenceNumber: UInt16
        public let payloadType: UInt8
        public let timestamp: UInt32
        public let ssrc: UInt32
        public let payload: Data

        public init(sequenceNumber: UInt16, payloadType: UInt8, timestamp: UInt32, ssrc: UInt32, payload: Data) {
            self.sequenceNumber = sequenceNumber
            self.payloadType = payloadType
            self.timestamp = timestamp
            self.ssrc = ssrc
            self.payload = payload
        }
    }

    // Audio Engine & Nodes
    private var audioEngine: AVAudioEngine?
    private var mainAudioNode: AVAudioPlayerNode?
    private var altAudioNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?

    // Network Listeners
    private var mainAudioListener: NWListener?
    private var altAudioListener: NWListener?
    private let queue = DispatchQueue(label: "dev.unordinarylabs.drivingmode.audio", qos: .userInteractive)

    // Volume & Ducking State
    private let stateLock = NSLock()
    private var _baseVolume: Float = 1.0
    private var _isAltAudioActive: Bool = false
    private var _isPassthroughMode: Bool = false
    private var altAudioSilenceTimer: DispatchSourceTimer?

    public var isPassthroughMode: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _isPassthroughMode
        }
        set {
            stateLock.lock()
            _isPassthroughMode = newValue
            stateLock.unlock()
            applyVolumes()
        }
    }

    public var effectiveMainVolume: Float {
        stateLock.lock()
        defer { stateLock.unlock() }
        if _isPassthroughMode { return 0.0 }
        return _isAltAudioActive ? (_baseVolume * 0.25) : _baseVolume
    }

    public var effectiveAltVolume: Float {
        stateLock.lock()
        defer { stateLock.unlock() }
        if _isPassthroughMode { return 0.0 }
        return _baseVolume
    }

    public init() {
        setupAudioEngine()
    }

    // MARK: - Volume & Ducking API

    public func setBaseVolume(_ volume: Float) {
        stateLock.lock()
        _baseVolume = max(0.0, min(1.0, volume))
        stateLock.unlock()
        applyVolumes()
    }

    public func setRTSPDbVolume(_ db: Float) {
        let linear = AirPlayAudioReceiver.dbToLinear(db)
        setBaseVolume(linear)
    }

    public func notifyAltAudioActive(_ active: Bool) {
        stateLock.lock()
        _isAltAudioActive = active
        stateLock.unlock()

        applyVolumes()

        if active {
            // Reset silence timeout
            queue.async { [weak self] in
                self?.resetAltSilenceTimer()
            }
        }
    }

    private func resetAltSilenceTimer() {
        altAudioSilenceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1.2)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.notifyAltAudioActive(false)
        }
        timer.resume()
        altAudioSilenceTimer = timer
    }

    private func applyVolumes() {
        let mainVol = effectiveMainVolume
        let altVol = effectiveAltVolume
        queue.async { [weak self] in
            guard let self = self else { return }
            self.mainAudioNode?.volume = mainVol
            self.altAudioNode?.volume = altVol
        }
    }

    public static func dbToLinear(_ db: Float) -> Float {
        if db <= -100.0 { return 0.0 }
        let linear = powf(10.0, db / 20.0)
        return max(0.0, min(1.0, linear))
    }

    // MARK: - RTP Header Parsing

    public static func parseRTPPacket(_ data: Data) -> RTPPacket? {
        guard data.count >= 12 else { return nil }

        let b0 = data[0]
        let version = (b0 >> 6) & 0x03
        guard version == 2 else { return nil }

        let b1 = data[1]
        let payloadType = b1 & 0x7F

        let seqNum = UInt16(data[2]) << 8 | UInt16(data[3])
        let timestamp = UInt32(data[4]) << 24 | UInt32(data[5]) << 16 | UInt32(data[6]) << 8 | UInt32(data[7])
        let ssrc = UInt32(data[8]) << 24 | UInt32(data[9]) << 16 | UInt32(data[10]) << 8 | UInt32(data[11])

        var headerLength = 12
        let csrcCount = Int(b0 & 0x0F)
        headerLength += csrcCount * 4
        guard data.count >= headerLength else { return nil }

        let hasExtension = ((b0 >> 4) & 0x01) == 1
        if hasExtension {
            guard data.count >= headerLength + 4 else { return nil }
            let extLengthWords = Int(data[headerLength + 2]) << 8 | Int(data[headerLength + 3])
            headerLength += 4 + (extLengthWords * 4)
            guard data.count >= headerLength else { return nil }
        }

        let payload = data.subdata(in: headerLength..<data.count)
        return RTPPacket(
            sequenceNumber: seqNum,
            payloadType: payloadType,
            timestamp: timestamp,
            ssrc: ssrc,
            payload: payload
        )
    }

    // MARK: - Audio Engine Setup

    private func setupAudioEngine() {
        #if os(iOS) || os(macOS)
        let engine = AVAudioEngine()
        let mainNode = AVAudioPlayerNode()
        let altNode = AVAudioPlayerNode()

        engine.attach(mainNode)
        engine.attach(altNode)

        // 44.1kHz, 16-bit stereo LPCM
        if let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44100, channels: 2, interleaved: false) {
            self.audioFormat = format
            engine.connect(mainNode, to: engine.mainMixerNode, format: format)
            engine.connect(altNode, to: engine.mainMixerNode, format: format)
        }

        self.audioEngine = engine
        self.mainAudioNode = mainNode
        self.altAudioNode = altNode
        #endif
    }

    // MARK: - Lifecycle

    public func start(mainPort: UInt16 = 7001, altPort: UInt16 = 7002) throws {
        stop()

        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            NSLog("[DrivingMode][Audio] AVAudioSession configuration warning: %@", error.localizedDescription)
        }
        #endif

        do {
            try audioEngine?.start()
            mainAudioNode?.play()
            altAudioNode?.play()
        } catch {
            NSLog("[DrivingMode][Audio] AVAudioEngine start warning: %@", error.localizedDescription)
        }

        // Start UDP Listeners for RTP packets
        let mainParams = NWParameters.udp
        mainParams.allowLocalEndpointReuse = true
        if let port = NWEndpoint.Port(rawValue: mainPort) {
            let listener = try NWListener(using: mainParams, on: port)
            listener.stateUpdateHandler = { state in
                NSLog("[DrivingMode][Audio] Main Audio Listener (: %d) state: %@", mainPort, String(describing: state))
            }
            listener.newConnectionHandler = { [weak self] conn in
                self?.handleAudioConnection(conn, isAlt: false)
            }
            listener.start(queue: queue)
            self.mainAudioListener = listener
        }

        let altParams = NWParameters.udp
        altParams.allowLocalEndpointReuse = true
        if let port = NWEndpoint.Port(rawValue: altPort) {
            let listener = try NWListener(using: altParams, on: port)
            listener.stateUpdateHandler = { state in
                NSLog("[DrivingMode][Audio] Alt Audio Listener (: %d) state: %@", altPort, String(describing: state))
            }
            listener.newConnectionHandler = { [weak self] conn in
                self?.handleAudioConnection(conn, isAlt: true)
            }
            listener.start(queue: queue)
            self.altAudioListener = listener
        }

        NSLog("[DrivingMode][Audio] AirPlay Audio Receiver started (main: %d, alt: %d)", mainPort, altPort)
    }

    public func stop() {
        mainAudioListener?.cancel()
        mainAudioListener = nil
        altAudioListener?.cancel()
        altAudioListener = nil

        altAudioSilenceTimer?.cancel()
        altAudioSilenceTimer = nil

        mainAudioNode?.stop()
        altAudioNode?.stop()
        audioEngine?.stop()

        NSLog("[DrivingMode][Audio] AirPlay Audio Receiver stopped")
    }

    private func handleAudioConnection(_ conn: NWConnection, isAlt: Bool) {
        conn.start(queue: queue)
        receiveNextPacket(conn, isAlt: isAlt)
    }

    private func receiveNextPacket(_ conn: NWConnection, isAlt: Bool) {
        conn.receiveMessage { [weak self, weak conn] content, context, isComplete, error in
            guard let self = self, let conn = conn else { return }
            if let data = content, !data.isEmpty {
                self.processAudioPacket(data, isAlt: isAlt)
            }
            if error == nil {
                self.receiveNextPacket(conn, isAlt: isAlt)
            }
        }
    }

    public func processAudioPacket(_ data: Data, isAlt: Bool) {
        guard let _ = Self.parseRTPPacket(data) else { return }

        if isAlt {
            notifyAltAudioActive(true)
        }

        // If passthrough mode is enabled, we drain and discard without playing locally
        if isPassthroughMode { return }

        // Future extension: decrypt payload if encrypted, decode AAC-ELD/LPCM to buffer and schedule on AVAudioPlayerNode
    }
}
