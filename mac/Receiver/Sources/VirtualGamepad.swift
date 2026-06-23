import Foundation
import IOKit

/// Wraps a userspace virtual HID gamepad (IOHIDUserDevice): 8 buttons + analog
/// steer (X, int16), throttle (Z), brake (Rz). Report = 5 bytes.
final class VirtualGamepad {
    private var device: IOHIDUserDevice?
    private let queue = DispatchQueue(label: "com.gyrowheel.vhid")

    static let descriptor: [UInt8] = [
        0x05, 0x01,             // Usage Page (Generic Desktop)
        0x09, 0x05,             // Usage (Game Pad)
        0xA1, 0x01,             // Collection (Application)
          0xA1, 0x00,           //   Collection (Physical)
            0x05, 0x09,         //     Usage Page (Button)
            0x19, 0x01,         //     Usage Minimum (1)
            0x29, 0x1E,         //     Usage Maximum (30)
            0x15, 0x00, 0x25, 0x01,
            0x75, 0x01, 0x95, 0x1E,
            0x81, 0x02,         //     30 buttons
            0x75, 0x01, 0x95, 0x02,
            0x81, 0x03,         //     2 bits padding
            0x05, 0x01,         //     Usage Page (Generic Desktop)
            0x09, 0x30,         //     Usage (X)
            0x16, 0x01, 0x80,   //     Logical Min (-32767)
            0x26, 0xFF, 0x7F,   //     Logical Max (32767)
            0x75, 0x10, 0x95, 0x01,
            0x81, 0x02,         //     steer
            0x09, 0x32,         //     Usage (Z)  throttle
            0x09, 0x35,         //     Usage (Rz) brake
            0x15, 0x00, 0x26, 0xFF, 0x00,
            0x75, 0x08, 0x95, 0x02,
            0x81, 0x02,
          0xC0,
        0xC0
    ]

    @discardableResult
    func start() -> Bool {
        if device != nil { return true }
        let props: [String: Any] = [
            kIOHIDReportDescriptorKey: Data(Self.descriptor),
            kIOHIDVendorIDKey: 0x16C0,
            kIOHIDProductIDKey: 0x27DB,
            kIOHIDVersionNumberKey: 0x0100,
            kIOHIDManufacturerKey: "GyroWheel",
            kIOHIDProductKey: "GyroWheel Virtual Gamepad",
            kIOHIDPrimaryUsagePageKey: 0x01,
            kIOHIDPrimaryUsageKey: 0x05
        ]
        guard let d = IOHIDUserDeviceCreateWithProperties(kCFAllocatorDefault, props as CFDictionary, 0) else {
            return false
        }
        IOHIDUserDeviceSetDispatchQueue(d, queue)
        IOHIDUserDeviceSetCancelHandler(d) { }
        IOHIDUserDeviceActivate(d)
        device = d
        return true
    }

    func stop() {
        if let d = device { IOHIDUserDeviceCancel(d) }
        device = nil
    }

    func post(_ report: [UInt8]) {
        guard let d = device else { return }
        report.withUnsafeBufferPointer { b in
            guard let base = b.baseAddress else { return }
            _ = IOHIDUserDeviceHandleReportWithTimeStamp(d, mach_absolute_time(), base, b.count)
        }
    }
}

/// InputPacket (matches the iOS app) → 8-byte HID report. `steerScale` applies
/// telemetry-driven speed-sensitive steering (1 = full lock).
func gamepadReport(from p: InputPacket, steerScale: Float = 1) -> [UInt8] {
    let steer = Int16(max(-1, min(1, p.steer * steerScale)) * 32767)
    let s = UInt16(bitPattern: steer)
    let throttle = UInt8(max(0, min(1, p.throttle)) * 255)
    let brake = UInt8(max(0, min(1, p.brake)) * 255)
    var btn: [UInt8] = [0, 0, 0, 0]
    for bit in 0..<30 where p.buttons["btn\(bit + 1)"] == true { btn[bit / 8] |= UInt8(1 << (bit % 8)) }
    return [btn[0], btn[1], btn[2], btn[3], UInt8(s & 0xFF), UInt8((s >> 8) & 0xFF), throttle, brake]
}
