import Foundation
import Network

enum ConnectionState: Equatable {
    case setup
    case connecting
    case connected
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var text: String {
        switch self {
        case .setup:            return "Disconnected"
        case .connecting:       return "Connecting…"
        case .connected:        return "Connected"
        case .failed(let msg):  return "Error: \(msg)"
        }
    }
}

struct InputPacket: Codable {
    var steer: Float = 0
    var throttle: Float = 0
    var brake: Float = 0
    var buttons: [String: Bool] = Dictionary(uniqueKeysWithValues: (1...30).map { ("btn\($0)", false) })
}

struct HapticCue: Codable {
    let haptic: String
    let intensity: Double?
    let limit: Double? // Added to receive dynamic grip limit from Mac
}

final class NetworkManager {
    private var connection: NWConnection?
    private var resolver: NWConnection?
    private let queue = DispatchQueue(label: "com.gyrowheel.udp", qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    private let lock = NSLock()
    private var packet = InputPacket()
    private var isReady = false
    private let encoder = JSONEncoder()

    var sendRateHz: Int = 120
    var throttleEase: Double = 0
    private var targetThrottle: Float = 0
    private var targetBrake: Float = 0

    private var sendCount = 0
    private var rateWindowStart = CFAbsoluteTimeGetCurrent()

    var onState: ((ConnectionState) -> Void)?
    var onRate: ((Int) -> Void)?
    var onHaptic: ((HapticCue) -> Void)?

    func connect(host: String, port: UInt16) {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let nwPort = NWEndpoint.Port(rawValue: port) else {
            onState?(.failed("Invalid host/port"))
            return
        }
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        startConnection(NWConnection(host: NWEndpoint.Host(trimmed), port: nwPort, using: params))
    }

    func connect(endpoint: NWEndpoint) {
        disconnect()
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = true

        let probe = NWConnection(to: endpoint, using: params)
        resolver = probe
        onState?(.connecting)
        probe.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                let remote = probe.currentPath?.remoteEndpoint
                probe.cancel()
                self.resolver = nil
                if case let .hostPort(host, port)? = remote {
                    let p = NWParameters.udp
                    p.allowLocalEndpointReuse = true
                    self.startConnection(NWConnection(host: host, port: port, using: p))
                } else {
                    let p = NWParameters.udp
                    p.allowLocalEndpointReuse = true
                    p.includePeerToPeer = true
                    self.startConnection(NWConnection(to: endpoint, using: p))
                }
            case .failed(let err):
                self.resolver = nil
                self.onState?(.failed(err.localizedDescription))
            default:
                break
            }
        }
        probe.start(queue: queue)
    }

    private func startConnection(_ conn: NWConnection) {
        disconnect()
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.isReady = true
                self.onState?(.connected)
            case .preparing, .setup:
                self.isReady = false
                self.onState?(.connecting)
            case .waiting:
                self.isReady = false
                self.onState?(.connecting)
            case .failed(let err):
                self.isReady = false
                self.onState?(.failed(err.localizedDescription))
            case .cancelled:
                self.isReady = false
                self.onState?(.setup)
            @unknown default:
                break
            }
        }
        onState?(.connecting)
        conn.start(queue: queue)
        startTimer()
        receiveLoop(conn)
    }

    private func receiveLoop(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, let cue = try? JSONDecoder().decode(HapticCue.self, from: data) {
                self.onHaptic?(cue)
            }
            if error == nil, self.connection === conn { self.receiveLoop(conn) }
        }
    }

    func disconnect() {
        stopTimer()
        resolver?.cancel()
        resolver = nil
        connection?.cancel()
        connection = nil
        isReady = false
    }

    private func startTimer() {
        stopTimer()
        sendCount = 0
        rateWindowStart = CFAbsoluteTimeGetCurrent()

        let hz = max(30, min(sendRateHz, 200))
        let intervalUS = Int(1_000_000 / hz)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .microseconds(intervalUS), leeway: .microseconds(intervalUS / 4))
        t.setEventHandler { [weak self] in self?.sendCurrent() }
        timer = t
        t.resume()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func sendCurrent() {
        guard let conn = connection, isReady else { return }

        lock.lock()
        if targetThrottle >= packet.throttle || throttleEase <= 0 {
            packet.throttle = targetThrottle
        } else {
            let dt = 1.0 / Double(max(30, min(sendRateHz, 200)))
            let step = Float(dt / throttleEase)
            packet.throttle = max(targetThrottle, packet.throttle - step)
        }
        packet.brake = targetBrake
        let snapshot = packet
        lock.unlock()
        guard let data = try? encoder.encode(snapshot) else { return }

        conn.send(content: data, completion: .contentProcessed { _ in })

        sendCount += 1
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - rateWindowStart
        if elapsed > 1.5 {
            sendCount = 0
            rateWindowStart = now
        } else if elapsed >= 1.0 {
            onRate?(Int((Double(sendCount) / elapsed).rounded()))
            sendCount = 0
            rateWindowStart = now
        }
    }

    func updateSteer(_ value: Double) {
        lock.lock(); packet.steer = Float(value); lock.unlock()
    }

    func updateThrottleBrake(throttle: Double, brake: Double) {
        lock.lock(); targetThrottle = Float(throttle); targetBrake = Float(brake); lock.unlock()
    }

    func updateButton(name: String, pressed: Bool) {
        lock.lock(); packet.buttons[name] = pressed; lock.unlock()
    }
}
