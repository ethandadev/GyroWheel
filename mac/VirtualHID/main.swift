//
//  GyroWheel — userspace virtual gamepad (IOHIDUserDevice)
//
//  The lightest "true analog" path: a single signed CLI that publishes a virtual
//  HID gamepad directly from user space — no DriverKit, no system extension, no
//  embedding. Receives the iOS app's 60 Hz InputPacket over UDP and posts HID
//  reports.
//
//  Build:  ./build.sh
//  Run:    sudo ./gyrohid            (or just ./gyrohid with SIP/AMFI disabled)
//
//  Requires EITHER the com.apple.developer.hid.virtual.device entitlement
//  (paid account) OR — for personal use — SIP + AMFI disabled so the ad-hoc
//  signed entitlement is honored. See build.sh / README for the exact steps.
//

import Foundation
import IOKit
import Network

// MARK: - HID report descriptor (gamepad: 8 buttons, X=steer i16, Z=throttle, Rz=brake)
// Report layout = 5 bytes: [buttons, steerLo, steerHi, throttle, brake]
let reportDescriptor: [UInt8] = [
    0x05, 0x01,             // Usage Page (Generic Desktop)
    0x09, 0x05,             // Usage (Game Pad)
    0xA1, 0x01,             // Collection (Application)
      0xA1, 0x00,           //   Collection (Physical)
        0x05, 0x09,         //     Usage Page (Button)
        0x19, 0x01,         //     Usage Minimum (Button 1)
        0x29, 0x1E,         //     Usage Maximum (Button 30)
        0x15, 0x00,         //     Logical Minimum (0)
        0x25, 0x01,         //     Logical Maximum (1)
        0x75, 0x01,         //     Report Size (1)
        0x95, 0x1E,         //     Report Count (30)
        0x81, 0x02,         //     Input (Data,Var,Abs)
        0x75, 0x01,         //     Report Size (1)   -- 2 bits padding
        0x95, 0x02,         //     Report Count (2)
        0x81, 0x03,         //     Input (Const,Var,Abs)
        0x05, 0x01,         //     Usage Page (Generic Desktop)
        0x09, 0x30,         //     Usage (X)
        0x16, 0x01, 0x80,   //     Logical Minimum (-32767)
        0x26, 0xFF, 0x7F,   //     Logical Maximum (32767)
        0x75, 0x10,         //     Report Size (16)
        0x95, 0x01,         //     Report Count (1)
        0x81, 0x02,         //     Input (Data,Var,Abs)
        0x09, 0x32,         //     Usage (Z)   -- throttle
        0x09, 0x35,         //     Usage (Rz)  -- brake
        0x15, 0x00,         //     Logical Minimum (0)
        0x26, 0xFF, 0x00,   //     Logical Maximum (255)
        0x75, 0x08,         //     Report Size (8)
        0x95, 0x02,         //     Report Count (2)
        0x81, 0x02,         //     Input (Data,Var,Abs)
      0xC0,                 //   End Collection
    0xC0                    // End Collection
]

// MARK: - Create the virtual device
func makeDevice() -> IOHIDUserDevice? {
    let props: [String: Any] = [
        kIOHIDReportDescriptorKey: Data(reportDescriptor),
        kIOHIDVendorIDKey: 0x16C0,
        kIOHIDProductIDKey: 0x27DB,
        kIOHIDVersionNumberKey: 0x0100,
        kIOHIDManufacturerKey: "GyroWheel",
        kIOHIDProductKey: "GyroWheel Virtual Gamepad",
        kIOHIDPrimaryUsagePageKey: 0x01,   // Generic Desktop
        kIOHIDPrimaryUsageKey: 0x05        // Game Pad
    ]
    return IOHIDUserDeviceCreateWithProperties(kCFAllocatorDefault, props as CFDictionary, 0)
}

guard let device = makeDevice() else {
    FileHandle.standardError.write(Data("""
        ❌ Could not create the virtual HID device.
           Run with `sudo`, or (personal use) disable SIP + AMFI so the
           ad-hoc entitlement is honored. See build.sh / README.

        """.utf8))
    exit(1)
}

let hidQueue = DispatchQueue(label: "com.gyrowheel.hid")
IOHIDUserDeviceSetDispatchQueue(device, hidQueue)
IOHIDUserDeviceSetCancelHandler(device) { }
IOHIDUserDeviceActivate(device)

func sendReport(_ report: [UInt8]) {
    report.withUnsafeBufferPointer { buf in
        guard let base = buf.baseAddress else { return }
        _ = IOHIDUserDeviceHandleReportWithTimeStamp(device, mach_absolute_time(), base, buf.count)
    }
}

// MARK: - Packet → report
struct InputPacket: Decodable {
    let steer: Float
    let throttle: Float
    let brake: Float
    let buttons: [String: Bool]
}

// MARK: - F1 25 telemetry (speed-sensitive steering + lockup/wheelspin haptics)
enum Telcfg {
    static let enabled = true
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
        return self.subdata(in: (startIndex + o)..<(startIndex + o + 4)).withUnsafeBytes {
            $0.loadUnaligned(as: Float.self)
        }
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
    var phoneConnection: NWConnection?

    var currentSpeed: Double { lock.lock(); defer { lock.unlock() }; return speedKmh }

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
                // 1=Rumble strip, 2=Concrete(often flat kerbs/runoffs), 9=Cobblestone, 10=Metal, 11=Ridged
                if surfaces.contains(where: { [1, 2, 9, 10, 11].contains($0) }) { onKerb = true }
                // 3=Rock, 4=Gravel, 5=Mud, 6=Sand, 7=Grass
                if surfaces.contains(where: { [3, 4, 5, 6, 7].contains($0) }) { isOfftrack = true }
            }

            lock.lock(); speedKmh = Double(sp); throttle = Double(th); brake = Double(br); lock.unlock()
            
            if speedKmh > 5.0 {
                detectSurfaceHaptics(kerb: onKerb, offtrack: isOfftrack)
            }

        case 13: // Motion Ex
            let off = header + 64
            guard let rl = data.f32le(off), let rr = data.f32le(off + 4),
                  let fl = data.f32le(off + 8), let fr = data.f32le(off + 12) else { return }
            lock.lock()
            frontSlipMin = min(Double(fl), Double(fr))   // most-negative = locking
            rearSlipMax = max(Double(rl), Double(rr))     // most-positive = spinning
            let br = brake, th = throttle
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

let telemetry = TelemetryEngine()

/// Steering compression: full lock at low speed, heavily reduced at high speed.
func speedSteerScale() -> Float {
    guard Telcfg.speedSteer else { return 1 }
    let speed = telemetry.currentSpeed
    guard speed > 1 else { return 1 }
    let m = 1.0 - (min(speed, Telcfg.maxSpeedKmh) / Telcfg.maxSpeedKmh) * Telcfg.damping
    return Float(min(max(m, Telcfg.minScale), 1.0))
}

func report(from p: InputPacket) -> [UInt8] {
    let steer = Int16(max(-1, min(1, p.steer * speedSteerScale())) * 32767)
    let s = UInt16(bitPattern: steer)
    let throttle = UInt8(max(0, min(1, p.throttle)) * 255)
    let brake = UInt8(max(0, min(1, p.brake)) * 255)
    var btn: [UInt8] = [0, 0, 0, 0]
    for bit in 0..<30 where p.buttons["btn\(bit + 1)"] == true { btn[bit / 8] |= UInt8(1 << (bit % 8)) }
    return [btn[0], btn[1], btn[2], btn[3], UInt8(s & 0xFF), UInt8((s >> 8) & 0xFF), throttle, brake]
}

let port: UInt16 = 5005
var packetCount = 0

func receive(on connection: NWConnection) {
    connection.start(queue: hidQueue)
    telemetry.phoneConnection = connection
    func loop() {
        connection.receiveMessage { data, _, _, error in
            if let data, let packet = try? JSONDecoder().decode(InputPacket.self, from: data) {
                packetCount += 1
                sendReport(report(from: packet))
            }
            if error == nil { loop() }
        }
    }
    loop()
}

let listener = try! NWListener(using: .udp, on: NWEndpoint.Port(rawValue: port)!)
let macName = Host.current().localizedName ?? "Mac"
listener.service = NWListener.Service(name: "GyroWheel — \(macName)", type: "_gyrowheel._udp")
listener.newConnectionHandler = { receive(on: $0) }
listener.start(queue: hidQueue)

if Telcfg.enabled, let telPort = NWEndpoint.Port(rawValue: Telcfg.port),
   let telListener = try? NWListener(using: .udp, on: telPort) {
    telListener.newConnectionHandler = { conn in
        conn.start(queue: hidQueue)
        func tloop() {
            conn.receiveMessage { data, _, _, error in
                if let data { telemetry.parse(data) }
                if error == nil { tloop() }
            }
        }
        tloop()
    }
    telListener.start(queue: hidQueue)
    print("Telemetry: listening on UDP \(Telcfg.port) (point F1 here for speed-steering + haptics)")
}

let hzTimer = DispatchSource.makeTimerSource(queue: hidQueue)
hzTimer.schedule(deadline: .now() + 1, repeating: 1)
hzTimer.setEventHandler {
    let hz = packetCount; packetCount = 0
    
    // 10Hz stream to send limit back to phone. (We just do it every 1 second here for `main.swift` 
    // or we can attach it to the telemetry packets directly.
    // Actually, sending it 1Hz is fine for main.swift, let's keep it simple here.
    if let conn = telemetry.phoneConnection {
        let limit = speedSteerScale()
        conn.send(content: "{\"haptic\":\"none\",\"limit\":\(limit)}".data(using: .utf8), completion: .contentProcessed { _ in })
    }
    
    print("virtual gamepad live · \(hz) Hz")
}
hzTimer.resume()

print("""
============================================================
 GyroWheel virtual gamepad (IOHIDUserDevice)
   Listening on UDP \(port)
   Device "GyroWheel Virtual Gamepad" is now published.
   Ctrl+C to quit.
============================================================
""")

dispatchMain()
