//
//  UDPReceiver.swift
//  Listens for the iOS app's 60 Hz InputPacket and forwards each packet.
//

import Foundation
import Network

/// Mirrors the iOS app's packet exactly.
struct InputPacket: Decodable {
    let steer: Float
    let throttle: Float
    let brake: Float
    let buttons: [String: Bool]
}

final class UDPReceiver: ObservableObject {
    @Published var listening = false
    @Published var hz: Int = 0

    /// Delivered on a background queue for every decoded packet.
    var onPacket: ((InputPacket) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.gyrowheel.udp.recv")
    private var packetCount = 0
    private var rateTimer: DispatchSourceTimer?

    func start(port: UInt16) {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        do {
            listener = try NWListener(using: .udp, on: nwPort)
        } catch {
            print("[udp] listener error: \(error)")
            return
        }
        let macName = Host.current().localizedName ?? "Mac"
        listener?.service = NWListener.Service(name: "GyroWheel — \(macName)", type: "_gyrowheel._udp")
        listener?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.listening = (state == .ready)
            }
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.receive(on: connection)
        }
        listener?.start(queue: queue)
        startRateTimer()
    }

    func stop() {
        rateTimer?.cancel(); rateTimer = nil
        listener?.cancel(); listener = nil
        DispatchQueue.main.async { self.listening = false; self.hz = 0 }
    }

    private func receive(on connection: NWConnection) {
        connection.start(queue: queue)
        func loop() {
            connection.receiveMessage { [weak self] data, _, _, error in
                if let data, let packet = try? JSONDecoder().decode(InputPacket.self, from: data) {
                    self?.packetCount += 1
                    self?.onPacket?(packet)
                }
                if error == nil { loop() }
            }
        }
        loop()
    }

    private func startRateTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let count = self.packetCount
            self.packetCount = 0
            DispatchQueue.main.async { self.hz = count }
        }
        timer.resume()
        rateTimer = timer
    }
}
