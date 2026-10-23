//
//  ImpactDetectionService.swift
//  DrivingMode
//
//  Monitors real-time accelerometer vector magnitude to detect sudden high-G deceleration/impacts,
//  triggering dashcam emergency protection with debouncing.
//

import Foundation
#if os(iOS)
import CoreMotion
#endif

public final class ImpactDetectionService: @unchecked Sendable {
    public var thresholdG: Double
    public var debounceSeconds: TimeInterval
    public var onImpact: ((Double) -> Void)?

    #if os(iOS)
    private let motionManager = CMMotionManager()
    #endif

    private var lastImpactTime: Date?
    private let lock = NSLock()

    public init(thresholdG: Double = 2.5, debounceSeconds: TimeInterval = 15.0) {
        self.thresholdG = thresholdG
        self.debounceSeconds = debounceSeconds
    }

    public func startMonitoring() {
        #if os(iOS)
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 1.0 / 50.0 // 50 Hz
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let data = data else { return }
            self.processAcceleration(x: data.acceleration.x, y: data.acceleration.y, z: data.acceleration.z)
        }
        #endif
    }

    public func stopMonitoring() {
        #if os(iOS)
        if motionManager.isAccelerometerActive {
            motionManager.stopAccelerometerUpdates()
        }
        #endif
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
        let callback = onImpact
        if Thread.isMainThread {
            callback?(magnitude)
        } else {
            DispatchQueue.main.async {
                callback?(magnitude)
            }
        }
    }
}
