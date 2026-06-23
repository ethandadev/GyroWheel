import Foundation
import Network

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

final class TelemetryEngine {
    private let lock = NSLock()
    private var speedKmh = 0.0
    private var frontSlipMin = 0.0
    private var rearSlipMax = 0.0
    private var brake = 0.0
    private var throttle = 0.0
    private var lastLockup: CFTimeInterval = 0
    private var lastWheelspin: CFTimeInterval = 0
    private var lastKerb: CFTimeInterval = 0
    private var lastOfftrack: CFTimeInterval = 0
    private var lastSoftLock: CFTimeInterval = 0
    private var lastPacket: CFTimeInterval = 0

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.gyrowheel.telemetry")

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
        if now - lastSoftLock > 0.3 {
            lastSoftLock = now
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

    func parse(_ data: Data) {
        guard let fmt = data.u16le(0), fmt >= 2018,
              let pid = data.u8(6), let player = data.u8(27) else { return }
        let header = 29
        switch pid {
        case 6: // Car Telemetry
            let off = header + Int(player) * 60
            guard let sp = data.u16le(off), let th = data.f32le(off + 2), let br = data.f32le(off + 10) else { return }
            
            var onKerb = false
            var isOfftrack = false
            if let fl = data.u8(off + 56), let fr = data.u8(off + 57), 
               let rl = data.u8(off + 58), let rr = data.u8(off + 59) {
                let surfaces = [fl, fr, rl, rr]
                if surfaces.contains(where: { [1, 2, 9, 10, 11].contains($0) }) { onKerb = true }
                if surfaces.contains(where: { [3, 4, 5, 6, 7].contains($0) }) { isOfftrack = true }
            }

            lock.lock(); speedKmh = Double(sp); throttle = Double(th); brake = Double(br); lastPacket = CFAbsoluteTimeGetCurrent(); lock.unlock()
            
            if speedKmh > 5.0 {
                detectSurfaceHaptics(kerb: onKerb, offtrack: isOfftrack)
            }

        case 13: // Motion Ex
            let off = header + 64
            guard let rl = data.f32le(off), let rr = data.f32le(off + 4),
                  let fl = data.f32le(off + 8), let fr = data.f32le(off + 12) else { return }
            lock.lock()
            frontSlipMin = min(Double(fl), Double(fr))
            rearSlipMax = max(Double(rl), Double(rr))
            let br = brake, th = throttle
            lastPacket = CFAbsoluteTimeGetCurrent()
            lock.unlock()
            detectHaptics(brake: br, throttle: th)
        default: break
        }
    }

    private func detectSurfaceHaptics(kerb: Bool, offtrack: Bool) {
        guard Telcfg.haptics, let conn = phoneConnection else { return }
        let now = CFAbsoluteTimeGetCurrent()
        
        if offtrack, now - lastOfftrack > 0.2 {
            lastOfftrack = now
            send("{\"haptic\":\"offtrack\",\"intensity\":1.0}", conn)
        } else if kerb, now - lastKerb > 0.1 {
            lastKerb = now
            send("{\"haptic\":\"kerb\"}", conn)
        }
    }

    private func detectHaptics(brake: Double, throttle: Double) {
        guard Telcfg.haptics, let conn = phoneConnection else { return }
        lock.lock(); let fs = frontSlipMin, rs = rearSlipMax; lock.unlock()
        let now = CFAbsoluteTimeGetCurrent()
        if brake > 0.25, fs < -Telcfg.lockupSlip, now - lastLockup > 0.12 {
            lastLockup = now
            send("{\"haptic\":\"lockup\"}", conn)
        } else if throttle > 0.35, rs > Telcfg.wheelspinSlip, now - lastWheelspin > 0.15 {
            lastWheelspin = now
            let intensity = min(1.0, rs / 0.6)
            send("{\"haptic\":\"wheelspin\",\"intensity\":\(String(format: "%.2f", intensity))}", conn)
        }
    }

    private func send(_ s: String, _ conn: NWConnection) {
        conn.send(content: s.data(using: .utf8), completion: .contentProcessed { _ in })
    }
}
