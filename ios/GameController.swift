import Foundation
import Combine

final class GameController: ObservableObject {
    @Published var steer: Double = 0
    @Published var throttle: Double = 0
    @Published var brake: Double = 0
    @Published var buttons: [Bool] = Array(repeating: false, count: kMaxButtons)
    @Published var status: ConnectionState = .setup
    @Published var txRate: Int = 0
    @Published var target: String = ""

    let settings: AppSettings
    private let motion = MotionManager()
    private let network = NetworkManager()
    private let haptics = HapticsEngine()
    private var orientationFlipped = false
    private var lastUISteerTime: CFTimeInterval = 0

    init(settings: AppSettings) {
        self.settings = settings
        motion.settings = settings

        motion.onSoftLock = { [weak self] in
            guard let self, self.settings.hapticsEnabled else { return }
            DispatchQueue.main.async {
                self.haptics.softLock()
            }
        }

        motion.onSteer = { [weak self] value in
            guard let self else { return }
            var v = value
            if self.settings.autoInvert && self.orientationFlipped { v = -v }
            self.network.updateSteer(v)
            let now = CFAbsoluteTimeGetCurrent()
            if now - self.lastUISteerTime >= 1.0 / 60.0 {
                self.lastUISteerTime = now
                DispatchQueue.main.async { self.steer = v }
            }
        }
        network.onState = { [weak self] state in
            guard let self else { return }
            DispatchQueue.main.async {
                self.status = state
                if !state.isConnected { self.txRate = 0 }
            }
        }
        network.onRate = { [weak self] rate in
            DispatchQueue.main.async { self?.txRate = rate }
        }
        network.onHaptic = { [weak self] cue in
            guard let self else { return }
            
            // If the Mac sends an updated dynamic grip limit, feed it to the motion manager
            if let newLimit = cue.limit {
                self.motion.currentDynamicGripLimit = newLimit
            }
            
            guard self.settings.telemetryHaptics else { return }
            DispatchQueue.main.async {
                switch cue.haptic {
                case "lockup":    self.haptics.lockup()
                case "wheelspin": self.haptics.wheelspin(cue.intensity ?? 0.6)
                case "kerb":      self.haptics.kerb()
                case "offtrack":  self.haptics.offtrack(cue.intensity ?? 0.7)
                case "softLock":  self.haptics.softLock()
                default: break
                }
            }
        }
    }

    func start() { motion.start(); haptics.prepare() }
    func stop()  { motion.stop() }
    func setLandscapeFlipped(_ flipped: Bool) { orientationFlipped = flipped }

    func connect() {
        target = "\(settings.host):\(settings.port)"
        network.sendRateHz = settings.sendRateHz
        network.connect(host: settings.host, port: UInt16(clamping: settings.port))
        if settings.calibrateOnLaunch { calibrate() }
    }

    func connect(to mac: DiscoveredMac) {
        target = mac.name
        network.sendRateHz = settings.sendRateHz
        network.connect(endpoint: mac.endpoint)
        if settings.calibrateOnLaunch { calibrate() }
    }

    var targetLabel: String { target.isEmpty ? "\(settings.host):\(settings.port)" : target }
    func disconnect() { network.disconnect(); txRate = 0 }
    func calibrate() { motion.calibrate() }

    func setThrottleBrake(throttle: Double, brake: Double) {
        self.throttle = throttle
        self.brake = brake
        network.throttleEase = settings.throttleEase
        let t = curve(throttle, settings.throttleGamma)
        let b = curve(brake, settings.brakeGamma)
        if settings.invertPedals {
            network.updateThrottleBrake(throttle: b, brake: t)
        } else {
            network.updateThrottleBrake(throttle: t, brake: b)
        }
    }

    private func curve(_ v: Double, _ gamma: Double) -> Double {
        guard gamma != 1.0, v > 0 else { return v }
        return pow(min(max(v, 0), 1), gamma)
    }

    func buttonDown(_ index: Int) {
        guard buttons.indices.contains(index) else { return }
        let mode = ButtonMode(rawValue: settings.buttonModes[index]) ?? .hold
        switch mode {
        case .hold:   setButton(index, true)
        case .toggle: setButton(index, !buttons[index])
        case .tap:
            setButton(index, true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
                self?.setButton(index, false)
            }
        }
    }

    func buttonUp(_ index: Int) {
        guard buttons.indices.contains(index) else { return }
        let mode = ButtonMode(rawValue: settings.buttonModes[index]) ?? .hold
        if mode == .hold { setButton(index, false) }
    }

    private func setButton(_ index: Int, _ pressed: Bool) {
        guard buttons.indices.contains(index) else { return }
        buttons[index] = pressed
        network.updateButton(name: "btn\(index + 1)", pressed: pressed)
    }
}
