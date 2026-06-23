import Foundation
import Network
import Darwin

/// Matches the iOS app's packet exactly.
struct InputPacket: Decodable {
    let steer: Float
    let throttle: Float
    let brake: Float
    let buttons: [String: Bool]
}

final class UDPReceiver {
    var onPacket: ((InputPacket) -> Void)?
    var onHz: ((Int) -> Void)?
    var onListening: ((Bool) -> Void)?
    var onConnection: ((NWConnection) -> Void)?   // for the reverse haptic channel

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.gyrowheel.udp", qos: .userInteractive)
    // Dedicated processing worker queue to keep the UDP socket empty and fast
    private let processingQueue = DispatchQueue(label: "com.gyrowheel.udp.processing", qos: .userInteractive, attributes: .concurrent)
    
    // Reuse a single decoder instance instead of spinning up 120/sec
    private let decoder = JSONDecoder()
    
    private var count = 0
    private var timer: DispatchSourceTimer?

    func start(port: UInt16) {
        stop()
        guard let p = NWEndpoint.Port(rawValue: port) else { return }
        do { listener = try NWListener(using: .udp, on: p) }
        catch { print("[udp] \(error)"); return }
        
        let macName = Host.current().localizedName ?? "Mac"
        listener?.service = NWListener.Service(name: "GyroWheel — \(macName)", type: "_gyrowheel._udp")
        listener?.stateUpdateHandler = { [weak self] st in
            self?.onListening?(st == .ready)
        }
        listener?.newConnectionHandler = { [weak self] c in self?.receive(on: c) }
        listener?.start(queue: queue)

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let n = self.count; self.count = 0
            self.onHz?(n)
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel(); timer = nil
        listener?.cancel(); listener = nil
        onListening?(false)
    }

    private func receive(on c: NWConnection) {
        c.start(queue: queue)
        onConnection?(c)
        processNextMessage(on: c)
    }

    private func processNextMessage(on c: NWConnection) {
        c.receiveMessage { [weak self] data, _, _, error in
            guard let self = self else { return }
            
            if let data = data {
                autoreleasepool {
                    if let pkt = try? self.decoder.decode(InputPacket.self, from: data) {
                        self.count += 1
                        
                        // Push processing out of the networking loop
                        self.processingQueue.async { [weak self] in
                            self?.onPacket?(pkt)
                        }
                    }
                }
            }
            
            if error == nil {
                self.processNextMessage(on: c)
            }
        }
    }
}

/// This Mac's LAN IP (the address to type on the phone).
func localIPAddress() -> String {
    let sock = socket(AF_INET, SOCK_DGRAM, 0)
    if sock < 0 { return "127.0.0.1" }
    defer { close(sock) }

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(53).bigEndian
    inet_pton(AF_INET, "8.8.8.8", &addr.sin_addr)
    let connectOK = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    if connectOK != 0 { return "127.0.0.1" }

    var local = sockaddr_in()
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameOK = withUnsafeMutablePointer(to: &local) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(sock, $0, &len) }
    }
    if nameOK != 0 { return "127.0.0.1" }

    var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
    inet_ntop(AF_INET, &local.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN))
    return String(cString: buf)
}
