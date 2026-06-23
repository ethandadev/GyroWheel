import SwiftUI

@main
struct GyroWheelReceiverApp: App {
    @StateObject private var model = ReceiverModel()
    var body: some Scene {
        WindowGroup("GyroWheel Receiver") {
            ContentView().environmentObject(model)
        }
        .windowResizability(.contentSize)
    }
}

final class ReceiverModel: ObservableObject {
    @Published var deviceActive = false
    @Published var listening = false
    @Published var hz = 0
    @Published var errorText: String?
    @Published var port = 5005
    @Published var telemetrySpeed = 0
    @Published var telemetryLive = false
    let ip = localIPAddress()

    private let pad = VirtualGamepad()
    private let udp = UDPReceiver()
    private let telemetry = TelemetryEngine()

    init() {
        udp.onPacket = { [weak self] pkt in
            guard let self else { return }
            self.pad.post(gamepadReport(from: pkt, steerScale: self.telemetry.speedSteerScale()))
        }
        udp.onHz = { [weak self] n in DispatchQueue.main.async { self?.hz = n } }
        udp.onListening = { [weak self] on in DispatchQueue.main.async { self?.listening = on } }
        udp.onConnection = { [weak self] conn in self?.telemetry.phoneConnection = conn }
        telemetry.onSpeed = { [weak self] speed, live in
            DispatchQueue.main.async { self?.telemetrySpeed = Int(speed); self?.telemetryLive = live }
        }
    }

    func start() {
        errorText = nil
        guard pad.start() else {
            errorText = "Couldn't create the virtual gamepad. Make sure SIP + AMFI are disabled (personal use) or that this app is signed with the virtual-HID entitlement, then relaunch."
            return
        }
        deviceActive = true
        udp.start(port: UInt16(port))
        telemetry.start()
    }

    func stop() {
        udp.stop()
        pad.stop()
        telemetry.stop()
        deviceActive = false
        hz = 0
        telemetryLive = false
        telemetrySpeed = 0
    }
}

struct ContentView: View {
    @EnvironmentObject var model: ReceiverModel
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("GyroWheel Receiver").font(.title2).bold()

            GroupBox {
                HStack(spacing: 10) {
                    Circle().fill(model.deviceActive && model.listening ? .green : .orange)
                        .frame(width: 12, height: 12)
                    Text(statusText).font(.callout)
                    Spacer()
                    if model.listening { Text("\(model.hz) Hz").font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary) }
                }
            }

            GroupBox("On your phone, enter") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.ip).font(.system(.title, design: .monospaced)).bold().textSelection(.enabled)
                        Text("port \(model.port)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Stepper("", value: $model.port, in: 1...65535).labelsHidden()
                }
            }

            GroupBox {
                HStack(spacing: 10) {
                    Image(systemName: "speedometer")
                        .foregroundStyle(model.telemetryLive ? .green : .secondary)
                    if model.telemetryLive {
                        Text("F1 telemetry · \(model.telemetrySpeed) km/h · speed-steering + haptics active")
                            .font(.callout)
                    } else {
                        Text("F1 telemetry: waiting — point F1 at 127.0.0.1 : 20777 (Format 2025)")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            if let err = model.errorText {
                Text(err).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(model.listening ? "Stop" : "Start") {
                    model.listening ? model.stop() : model.start()
                }
                .keyboardShortcut(.defaultAction)
                Button("Setup help") { hasOnboarded = false }
                Spacer()
            }
        }
        .padding(22)
        .frame(width: 440)
        .sheet(isPresented: Binding(get: { !hasOnboarded }, set: { if !$0 { hasOnboarded = true } })) {
            OnboardingSheet(ip: model.ip) { hasOnboarded = true }
        }
    }

    private var statusText: String {
        if !model.deviceActive { return "Idle — press Start" }
        return model.listening ? "Virtual gamepad active · listening" : "Device ready · waiting for network"
    }
}

struct OnboardingSheet: View {
    let ip: String
    let onDone: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to GyroWheel").font(.title).bold()
            Text("This app creates a virtual game controller that macOS and your games can read. Your iPhone streams steering, throttle, brake and buttons to it.")
                .foregroundStyle(.secondary)

            step(1, "Same Wi-Fi", "Put this Mac and your iPhone on the same network.")
            step(2, "Press Start", "It publishes a “GyroWheel Virtual Gamepad” and listens on UDP 5005.")
            step(3, "On the phone", "Open GyroWheel, tap ⚙️, and enter this Mac's address:  \(ip)  ·  port 5005.")
            step(4, "In your game", "Bind steering → X axis, throttle → Z, brake → Rz.")

            Text("Personal-use note: creating a virtual HID device needs SIP + AMFI disabled (or an Apple-granted virtual-HID entitlement). If Start shows an error, that step isn't done yet.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Got it") { onDone() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func step(_ n: Int, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.headline).frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor.opacity(0.2)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(body).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
