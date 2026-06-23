//
//  GamepadReceiverApp.swift
//  Ties the UDP receiver to the virtual-gamepad driver and shows status.
//

import SwiftUI

@main
struct GamepadReceiverApp: App {
    @StateObject private var driver = DriverManager()
    @StateObject private var udp = UDPReceiver()
    @State private var port: String = "5005"
    @State private var wired = false

    var body: some Scene {
        WindowGroup("GyroWheel Receiver") {
            VStack(alignment: .leading, spacing: 16) {
                Text("GyroWheel Virtual Gamepad")
                    .font(.title2).bold()

                GroupBox("1 · Driver") {
                    HStack {
                        Circle().fill(driver.driverConnected ? .green : .orange)
                            .frame(width: 10, height: 10)
                        Text(driver.status).font(.callout)
                        Spacer()
                        Button("Install / Activate") { driver.installDriver() }
                        Button("Connect") { driver.connect() }
                    }
                }

                GroupBox("2 · Network") {
                    HStack {
                        Circle().fill(udp.listening ? .green : .red)
                            .frame(width: 10, height: 10)
                        Text(udp.listening ? "Listening · \(udp.hz) Hz" : "Stopped").font(.callout)
                        Spacer()
                        Text("Port")
                        TextField("5005", text: $port).frame(width: 64)
                        Button(udp.listening ? "Stop" : "Start") {
                            if udp.listening { udp.stop() }
                            else { udp.start(port: UInt16(port) ?? 5005) }
                        }
                    }
                }

                Text("Enter this Mac's LAN IP + the port above on the phone.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(width: 460)
            .onAppear { wireOnce() }
        }
    }

    private func wireOnce() {
        guard !wired else { return }
        wired = true
        driver.connect()
        udp.onPacket = { packet in
            let steer = Int16(max(-1, min(1, packet.steer)) * 32767)
            let throttle = UInt8(max(0, min(1, packet.throttle)) * 255)
            let brake = UInt8(max(0, min(1, packet.brake)) * 255)
            var btn: [UInt8] = [0, 0, 0, 0]
            for bit in 0..<30 where packet.buttons["btn\(bit + 1)"] == true { btn[bit / 8] |= UInt8(1 << (bit % 8)) }
            driver.post(buttons: btn, steer: steer, throttle: throttle, brake: brake)
        }
    }
}
