//
//  DriverManager.swift
//  Activates the DriverKit system extension and feeds it HID reports over an
//  IOKit user client.
//

import Foundation
import IOKit
import SystemExtensions

final class DriverManager: NSObject, ObservableObject {
    @Published var status: String = "Idle"
    @Published var driverConnected = false

    private let driverBundleID = "com.gyrowheel.VirtualGamepad.Driver"
    private let driverClassName = "VirtualGamepadDriver"   // == IOUserClass
    private var connection: io_connect_t = 0

    // MARK: - System extension activation

    func installDriver() {
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: driverBundleID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        status = "Requesting driver activation…"
    }

    // MARK: - User-client connection

    @discardableResult
    func connect() -> Bool {
        if connection != 0 { return true }

        let matching = IOServiceMatching(driverClassName)
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            status = "Service match failed"
            return false
        }
        defer { IOObjectRelease(iterator) }

        var opened = false
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var conn: io_connect_t = 0
            let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
            IOObjectRelease(service)
            if kr == KERN_SUCCESS {
                connection = conn
                opened = true
                break
            }
            service = IOIteratorNext(iterator)
        }

        driverConnected = opened
        status = opened ? "Connected to virtual gamepad"
                        : "Driver not found — install & approve it first"
        return opened
    }

    func disconnect() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
        driverConnected = false
    }

    // MARK: - Report posting

    /// Pushes one HID report. Bytes match the report descriptor:
    /// [btn0..btn3 (30 buttons), steerLo, steerHi, throttle, brake].
    func post(buttons: [UInt8], steer: Int16, throttle: UInt8, brake: UInt8) {
        guard connection != 0 else { return }
        let s = UInt16(bitPattern: steer)
        var bytes = [UInt8](repeating: 0, count: Int(kVirtualGamepadReportLength))
        for i in 0..<min(4, buttons.count) { bytes[i] = buttons[i] }
        bytes[4] = UInt8(s & 0xFF)
        bytes[5] = UInt8((s >> 8) & 0xFF)
        bytes[6] = throttle
        bytes[7] = brake

        bytes.withUnsafeBytes { raw in
            _ = IOConnectCallStructMethod(connection,
                                          UInt32(kGamepadUserClientPostReport),
                                          raw.baseAddress, raw.count,
                                          nil, nil)
        }
    }
}

extension DriverManager: OSSystemExtensionRequestDelegate {
    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        DispatchQueue.main.async {
            self.status = "Approve in System Settings → General → Login Items & Extensions"
        }
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        DispatchQueue.main.async {
            self.status = (result == .completed)
                ? "Driver activated"
                : "Activation finished (a reboot may be required)"
            self.connect()
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.status = "Activation failed: \(error.localizedDescription)"
        }
    }
}
