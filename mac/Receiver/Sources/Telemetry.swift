import Foundation
import Network

// Telemetry state representation for engine decoupling
struct GameTelemetryState {
    let speedKmh: Double
    let throttle: Double
    let brake: Double
    let frontSlipMin: Double
    let rearSlipMax: Double
    let onKerb: Bool
    let isOfftrack: Bool
}

struct HapticCue {
    let haptic: String
    let intensity: Double?
    let limit: Float?
}

// Telemetry parsing contract
protocol TelemetryParserProtocol {
    func parse(data: Data) -> GameTelemetryState?
    func computeHaptics(state: GameTelemetryState) -> HapticCue?
}

// F1 25 telemetry → speed-sensitive steering + lockup/wheelspin haptics.
enum Telcfg {
    static let port: UInt16 = 20777
    static let speedSteer = true
    static let maxSpeedKmh = 320.0
    static let damping = 0.85
    static let minScale = 0.12
    static let haptics = true
    static let lockupSlip = 0.18
    static let wheelspinSlip = 0.20
}

private extension Data {
    func u8(_ o: Int) -> UInt8? { o + 1 <= count ? self[startIndex + o] : nil }
    func u16le(_ o: Int) -> UInt16? {
        guard o + 2 <= count else { return nil }
        return UInt16(self[startIndex + o]) | (UInt16(self[startIndex + o + 1]) << 8)
    }
    func f32le(_ o: Int) -> Float? {
        guard o + 4 <= count else { return nil }
        return subdata(in: (startIndex + o)..<(startIndex + o + 4)).withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
    }
}

// Concrete parser implementing TelemetryParserProtocol
final class F125TelemetryParser: TelemetryParserProtocol {
    private var frontSlipMin = 0.0
    private var rearSlipMax = 0.0
    private var brake = 0.0
    private var throttle = 0.0
    private var speedKmh = 0.0

    func parse(data: Data) -> GameTelemetryState? {
        guard let fmt = data.u16le(0), fmt >= 2018,
              let pid = data.u8(6), let player = data.u8(27) else { return nil }
        let header = 29
        
        switch pid {
        case 6: // Car Telemetry
            let off = header + Int(player) * 60
            guard let sp = data.u16le(off), let th = data.f32le(off + 2), let br = data.f32le(off + 10) else { return nil }
            
            var onKerb = false
            var isOfftrack = false
            if let fl = data.u8(off + 56), let fr = data.u8(off + 57), 
               let rl = data.u8(off + 58), let rr = data.u8(off + 59) {
                let surfaces = [fl, fr, rl, rr]
                if surfaces.contains(where: { [1, 2, 9, 10, 11].contains($0) }) { onKerb = true }
                if surfaces.contains(where: { [3, 4, 5, 6, 7].contains($0) }) { isOfftrack = true }
            }

            speedKmh = Double(sp)
            throttle = Double(th)
            brake = Double(br)
            
            return GameTelemetryState(
                speedKmh: speedKmh,
                throttle: throttle,
                brake: brake,
                frontSlipMin: frontSlipMin,
                rearSlipMax: rearSlipMax,
                onKerb: onKerb,
                isOfftrack: isOfftrack
            )

        case 13: // Motion Ex
            let off = header + 64
            guard let rl = data.f32le(off), let rr = data.f32le(off + 4),
                  let fl = data.f32le(off + 8), let fr = data.f32le(off + 12) else { return nil }
            
            frontSlipMin = min(Double(fl), Double(fr))
            rearSlipMax = max(Double(rl), Double(rr))
            
            return GameTelemetryState(
                speedKmh: speedKmh,
                throttle: throttle,
                brake: brake,
                frontSlipMin: frontSlipMin,
                rearSlipMax: rearSlipMax,
                onKerb: false,
                isOfftrack: false
            )
        default: return nil
        }
    }

    func computeHaptics(state: GameTelemetryState) -> HapticCue? {
        guard Telcfg.haptics else { return nil }
        
        if state.brake > 0.25, state.frontSlipMin < -Telcfg.lockupSlip {
            return HapticCue(haptic: "lockup", intensity: 1.0, limit: nil)
        } else if state.throttle > 0.35, state.rearSlipMax > Telcfg.wheelspinSlip {
            let intensity = min(1.0, state.rearSlipMax / 0.6)
            return HapticCue(haptic: "wheelspin", intensity: intensity, limit: nil)
        } else if state.isOfftrack {
            return HapticCue(haptic: "offtrack", intensity: 1.0, limit: nil)
        } else if state.onKerb {
            return HapticCue(haptic: "kerb", intensity: 1.0, limit: nil)
        }
        
        return nil
    }
}

final class TelemetryEngine {
    private let lock = NSLock()
    private var speedKmh = 0.0
    private var lastHapticTimes: [String: CFTimeInterval] = [:]
    private var lastPacket: CFTimeInterval = 0

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.gyrowheel.telemetry")

    private let parser: TelemetryParserProtocol = F125TelemetryParser()
    var phoneConnection: NWConnection?
    var onSpeed: ((Double, Bool) -> Void)?

    var currentSpeed: Double { lock.lock(); defer { lock.unlock() }; return speedKmh }

    func speedSteerScale() -> Float {
        guard Telcfg.speedSteer else { return 1.0 }
        let speed = currentSpeed
        guard speed > 5 else { return 1.0 }
        let m = 1.0 - (min(speed, Telcfg.maxSpeedKmh) / Telcfg.maxSpeedKmh) * Telcfg.damping
        return Float(min(max(m, Telcfg.minScale), 1.0))
    }

    func triggerSoftLock() {
        guard Telcfg.haptics, let conn = phoneConnection else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let lastTime = lastHapticTimes["softLock"] ?? 0
        if now - lastTime > 0.3 {
            lastHapticTimes["softLock"] = now
            send("{\"haptic\":\"softLock\"}", conn)
        }
    }

    func start() {
        stop()
        guard let p = NWEndpoint.Port(rawValue: Telcfg.port),
              let l = try? NWListener(using: .udp, on: p) else { return }
        l.newConnectionHandler = { [weak self] conn in
            conn.start(queue: self?.queue ?? .global())
            func loop() {
                conn.receiveMessage { [weak self] data, _, _, error in
                    if let data { self?.parse(data) }
                    if error == nil { loop() }
                }
            }
            loop()
        }
        l.start(queue: queue)
        listener = l

        // 10 Hz heartbeat to update UI speed AND stream the dynamic grip limit back to the phone
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 0.1)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let live = CFAbsoluteTimeGetCurrent() - self.lastPacket < 2.0
            
            // UI Update (only every 1 sec so we don't spam the main thread unnecessarily)
            if Int(CFAbsoluteTimeGetCurrent() * 10) % 10 == 0 {
                self.onSpeed?(self.currentSpeed, live)
            }
            
            // Stream dynamic limit to the phone
            if live, let conn = self.phoneConnection {
                let limit = self.speedSteerScale()
                self.send("{\"haptic\":\"none\",\"limit\":\(limit)}", conn)
            }
        }
        t.resume()
        heartbeat = t
    }
    private var heartbeat: DispatchSourceTimer?

    func stop() {
        listener?.cancel(); listener = nil
        heartbeat?.cancel(); heartbeat = nil
    }

    private func parse(_ data: Data) {
        guard let parsedState = parser.parse(data: data) else { return }
        
        lock.lock()
        speedKmh = parsedState.speedKmh
        lastPacket = CFAbsoluteTimeGetCurrent()
        lock.unlock()

        if speedKmh > 5.0, let cue = parser.computeHaptics(state: parsedState), let conn = phoneConnection {
            let now = CFAbsoluteTimeGetCurrent()
            let lastTime = lastHapticTimes[cue.haptic] ?? 0
            
            // Apply debounce thresholds based on haptic cue type
            let threshold: Double
            switch cue.haptic {
            case "lockup": threshold = 0.12
            case "wheelspin": threshold = 0.15
            case "kerb": threshold = 0.10
            case "offtrack": threshold = 0.20
            default: threshold = 0.10
            }
            
            if now - lastTime > threshold {
                lastHapticTimes[cue.haptic] = now
                if let intensity = cue.intensity {
                    send("{\"haptic\":\"\(cue.haptic)\",\"intensity\":\(String(format: "%.2f", intensity))}", conn)
                } else {
                    send("{\"haptic\":\"\(cue.haptic)\"}", conn)
                }
            }
        }
    }

    private func send(_ s: String, _ conn: NWConnection) {
        conn.send(content: s.data(using: .utf8), completion: .contentProcessed { _ in })
    }
}
