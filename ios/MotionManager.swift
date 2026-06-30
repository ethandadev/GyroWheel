import Foundation
import CoreMotion
import QuartzCore

/// Reads device attitude via CoreMotion and converts the "steering-wheel"
/// rotation (rotation about the screen-normal axis) into a value in -1.0...1.0.
final class MotionManager {
    private let manager = CMMotionManager()
    private let queue = OperationQueue()

    weak var settings: AppSettings?
    var onSteer: ((Double) -> Void)?
    var onSoftLock: (() -> Void)?
    /// Fires when an adaptive back-tap is detected (used for paddle shifting).
    var onBackTap: (() -> Void)?

    private var calibrationOffset: Double = 0
    private var lastRawAngle: Double = 0
    private var smoothedValue: Double = 0
    private var lastOutput: Double = 0
    private var lastTime: CFTimeInterval = 0
    private var hasFiredSoftLock = false

    // Back-tap detection — keys on jerk (change in user acceleration), with a slowly
    // adapting ambient baseline so wheel-turning won't trip it but a sharp tap will.
    private var prevAccel: CMAcceleration?
    private var jerkBaseline: Double = 0
    private var lastTapTime: CFTimeInterval = 0
    private let tapBaselineAlpha = 0.04
    private let tapDebounce: CFTimeInterval = 0.20
    private var backTapSuppressUntil: CFTimeInterval = 0

    /// Call when a screen button is tapped to suppress back-tap detection
    /// for a short window (screen taps jostle the phone and look like a tap).
    func suppressBackTap(for duration: CFTimeInterval = 0.35) {
        let t = CACurrentMediaTime() + duration
        if t > backTapSuppressUntil { backTapSuppressUntil = t }
    }
    
    // Dynamic grip limit provided by Mac telemetry (1.0 = full lock available, <1.0 = reduced steering available)
    var currentDynamicGripLimit: Double = 1.0

    init() {
        queue.name = "com.gyrowheel.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
    }

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        let hz = Double(settings?.sendRateHz ?? 120)
        manager.deviceMotionUpdateInterval = 1.0 / max(60.0, hz)
        lastTime = CACurrentMediaTime()
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            guard let self else { return }
            guard let motion else { return }

            let g = motion.gravity
            // Negate X to flip the default steering direction; the Invert toggle still applies on top.
            let rawAngle = atan2(-g.x, g.y)
            self.lastRawAngle = rawAngle

            if self.settings?.recenterAssist == true {
                var rel = rawAngle - self.calibrationOffset
                rel = atan2(sin(rel), cos(rel))
                let dzRad = (self.settings?.deadzoneDegrees ?? 2.5) * .pi / 180.0
                if abs(rel) < dzRad {
                    self.calibrationOffset += rel * 0.03
                    self.calibrationOffset = atan2(sin(self.calibrationOffset), cos(self.calibrationOffset))
                }
            }

            let target = self.computeSteer(rawAngle)

            let s = min(max(self.settings?.smoothing ?? 0.25, 0), 0.95)
            self.smoothedValue += (1.0 - s) * (target - self.smoothedValue)
            var out = self.smoothedValue

            let now = CACurrentMediaTime()
            let dt = min(max(now - self.lastTime, 0), 0.1)
            self.lastTime = now
            let rl = self.settings?.steerRateLimit ?? 0
            if rl > 0 {
                let maxStep = rl * dt
                out = min(max(out, self.lastOutput - maxStep), self.lastOutput + maxStep)
            }
            self.lastOutput = out

            self.onSteer?(out)

            self.detectBackTap(motion)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        prevAccel = nil
        jerkBaseline = 0
    }

    /// Mirrors BackTapTest's SingleTapEngine, but reuses the existing device-motion
    /// stream (one CMMotionManager for the whole app). Runs on the serial motion queue.
    private func detectBackTap(_ motion: CMDeviceMotion) {
        guard settings?.backTapShiftEnabled == true else { prevAccel = nil; return }
        guard CACurrentMediaTime() > backTapSuppressUntil else { return }
        let a = motion.userAcceleration
        defer { prevAccel = a }
        guard let p = prevAccel else { return }

        let dx = a.x - p.x, dy = a.y - p.y, dz = a.z - p.z
        let jerk = (dx * dx + dy * dy + dz * dz).squareRoot()

        let floor = settings?.backTapSensitivity ?? 0.25
        let ratio = settings?.backTapSharpness ?? 3.5
        let tripLevel = max(floor, jerkBaseline * ratio)
        let isSpike = jerk > tripLevel

        // Only non-spike samples move the baseline, so a tap can't inflate its own bar.
        if !isSpike {
            jerkBaseline = tapBaselineAlpha * jerk + (1 - tapBaselineAlpha) * jerkBaseline
        }

        guard isSpike else { return }
        let now = CACurrentMediaTime()
        guard now - lastTapTime > tapDebounce else { return }
        lastTapTime = now
        onBackTap?()
    }

    func calibrate() {
        calibrationOffset = lastRawAngle
        smoothedValue = 0
        lastOutput = 0
    }

    private func computeSteer(_ rawAngle: Double) -> Double {
        var angle = rawAngle - calibrationOffset
        angle = atan2(sin(angle), cos(angle))
        var degrees = angle * 180.0 / .pi

        let deadzone = settings?.deadzoneDegrees ?? 2.5
        if abs(degrees) < deadzone { return 0 }
        degrees -= (degrees > 0 ? deadzone : -deadzone)

        let maxLock = max(1.0, (settings?.maxLockDegrees ?? 90.0) - deadzone)
        var value = degrees / maxLock
        
        // This is the normalized physical turn of the phone. (1.0 = user hit their set max steering lock)
        
        // Soft Lock Check: We check against the current dynamic grip limit.
        // For example, if you're going 300km/h and the limit is 0.15, you hit the "wall" early.
        // If you're going 10km/h and the limit is 1.0, you hit it at the normal wheel lock.
        let dynamicLimit = currentDynamicGripLimit
        let absoluteValue = abs(value)
        
        if absoluteValue >= (dynamicLimit * 0.98) {
            if !hasFiredSoftLock {
                hasFiredSoftLock = true
                onSoftLock?()
            }
        } else if absoluteValue < (dynamicLimit * 0.85) {
            hasFiredSoftLock = false
        }
        
        // Override logic: if they try to push PAST the dynamic limit, let them, 
        // but scale it so it takes more physical movement to get less in-game movement.
        if absoluteValue > dynamicLimit {
            let sign = value < 0 ? -1.0 : 1.0
            let overflow = absoluteValue - dynamicLimit
            value = sign * (dynamicLimit + (overflow * 0.5))
        }

        value *= (settings?.sensitivity ?? 1.0)
        if settings?.invertSteering == true { value = -value }
        
        value = min(max(value, -2.0), 2.0)

        let gamma = settings?.steerCurve ?? 1.0
        if gamma != 1.0 {
            let sign: Double = value < 0 ? -1 : 1
            if abs(value) <= 1.0 {
                value = sign * pow(abs(value), gamma)
            } else {
                value = sign * (pow(1.0, gamma) + (abs(value) - 1.0))
            }
        }
        return value
    }
}
