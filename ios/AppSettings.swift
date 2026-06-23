import Foundation
import Combine
import SwiftUI

/// Up to 30 macro buttons (btn1…btn30). Receivers map these to gamepad buttons.
let kMaxButtons = 30

enum ButtonMode: Int, CaseIterable, Identifiable {
    case hold = 0, toggle = 1, tap = 2
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .hold:   return "Hold"
        case .toggle: return "Toggle"
        case .tap:    return "Tap"
        }
    }
}

// MARK: - Import/Export Profile
struct LayoutProfile: Codable {
    var buttonCount: Int
    var buttonLabels: [String]
    var buttonColors: [Int]
    var buttonModes: [Int]
    var buttonPosX: [Double]
    var buttonPosY: [Double]
    var buttonSize: [Double]
    var showWheel: Bool
    var wheelPosX: Double
    var wheelPosY: Double
    var wheelSize: Double
    var sliderPosX: Double
    var sliderPosY: Double
    var sliderWidth: Double
    var sliderHeight: Double
}

/// User-tunable configuration + freeform HUD layout, persisted to UserDefaults.
/// Positions are normalized (0…1) to the play area so they adapt to any device.
final class AppSettings: ObservableObject {
    private let store = UserDefaults.standard

    // MARK: Connection
    @Published var host: String        { didSet { store.set(host, forKey: "host") } }
    @Published var port: Int           { didSet { store.set(port, forKey: "port") } }
    @Published var autoConnect: Bool   { didSet { store.set(autoConnect, forKey: "autoConnect") } }
    /// Outgoing packet rate. 60 / 90 / 120.
    @Published var sendRateHz: Int     { didSet { store.set(sendRateHz, forKey: "sendRateHz") } }

    // MARK: Steering
    @Published var sensitivity: Double     { didSet { store.set(sensitivity, forKey: "sensitivity") } }
    @Published var deadzoneDegrees: Double { didSet { store.set(deadzoneDegrees, forKey: "deadzoneDegrees") } }
    @Published var maxLockDegrees: Double  { didSet { store.set(maxLockDegrees, forKey: "maxLockDegrees") } }
    @Published var smoothing: Double       { didSet { store.set(smoothing, forKey: "smoothing") } }
    @Published var steerCurve: Double      { didSet { store.set(steerCurve, forKey: "steerCurve") } }
    @Published var invertSteering: Bool    { didSet { store.set(invertSteering, forKey: "invertSteering") } }
    @Published var autoInvert: Bool        { didSet { store.set(autoInvert, forKey: "autoInvert") } }
    @Published var calibrateOnLaunch: Bool { didSet { store.set(calibrateOnLaunch, forKey: "calibrateOnLaunch") } }

    // MARK: Assists
    /// 0 = Off, 1 = Light, 2 = Strong. Setting it applies a preset.
    @Published var assistLevel: Int        { didSet { store.set(assistLevel, forKey: "assistLevel"); applyAssistPreset() } }
    /// Auto-trim: while held near center, slowly re-zeros so hand-shake on a
    /// straight doesn't slowly pull the car off line.
    @Published var recenterAssist: Bool    { didSet { store.set(recenterAssist, forKey: "recenterAssist") } }
    /// Max steering change per second (0 = off). Filters jitter spikes.
    @Published var steerRateLimit: Double  { didSet { store.set(steerRateLimit, forKey: "steerRateLimit") } }
    /// Throttle lift-off ease, in seconds (0 = instant). Throttle APPLIES
    /// instantly but RELEASES gradually when you lift your finger — like easing
    /// off the gas. Braking is never eased (instant release).
    @Published var throttleEase: Double  { didSet { store.set(throttleEase, forKey: "throttleEase") } }
    /// Pedal response curves (gamma). >1 = gentle at the start, steep at the end
    /// (trail-braking: ~1.9 maps 70% travel to ~50% force for precision near lockup).
    @Published var brakeGamma: Double      { didSet { store.set(brakeGamma, forKey: "brakeGamma") } }
    @Published var throttleGamma: Double   { didSet { store.set(throttleGamma, forKey: "throttleGamma") } }
    /// Vibrate on telemetry-detected lockup / wheelspin (cues sent by the Mac).
    @Published var telemetryHaptics: Bool  { didSet { store.set(telemetryHaptics, forKey: "telemetryHaptics") } }

    // MARK: Pedals
    @Published var invertPedals: Bool  { didSet { store.set(invertPedals, forKey: "invertPedals") } }

    // MARK: Feedback
    @Published var hapticsEnabled: Bool { didSet { store.set(hapticsEnabled, forKey: "hapticsEnabled") } }
    @Published var hapticOnConnect: Bool { didSet { store.set(hapticOnConnect, forKey: "hapticOnConnect") } }

    // MARK: Appearance
    @Published var accentColorIndex: Int   { didSet { store.set(accentColorIndex, forKey: "accentColorIndex") } }
    @Published var backgroundStyle: Int    { didSet { store.set(backgroundStyle, forKey: "backgroundStyle") } }
    @Published var controlOpacity: Double  { didSet { store.set(controlOpacity, forKey: "controlOpacity") } }
    @Published var buttonShape: Int        { didSet { store.set(buttonShape, forKey: "buttonShape") } }
    @Published var showAngleReadout: Bool  { didSet { store.set(showAngleReadout, forKey: "showAngleReadout") } }
    @Published var throttleColorIndex: Int { didSet { store.set(throttleColorIndex, forKey: "throttleColorIndex") } }
    @Published var brakeColorIndex: Int    { didSet { store.set(brakeColorIndex, forKey: "brakeColorIndex") } }

    // MARK: Onboarding
    @Published var hasOnboarded: Bool  { didSet { store.set(hasOnboarded, forKey: "hasOnboarded") } }

    // MARK: Macro buttons
    @Published var buttonCount: Int       { didSet { store.set(buttonCount, forKey: "buttonCount") } }
    @Published var buttonLabels: [String] { didSet { store.set(buttonLabels, forKey: "buttonLabels") } }
    @Published var buttonColors: [Int]    { didSet { store.set(buttonColors, forKey: "buttonColors") } }
    @Published var buttonModes: [Int]     { didSet { store.set(buttonModes, forKey: "buttonModes") } }
    @Published var buttonPosX: [Double]   { didSet { store.set(buttonPosX, forKey: "buttonPosX") } }
    @Published var buttonPosY: [Double]   { didSet { store.set(buttonPosY, forKey: "buttonPosY") } }
    @Published var buttonSize: [Double]   { didSet { store.set(buttonSize, forKey: "buttonSize") } }

    // MARK: HUD elements (normalized center + size)
    @Published var showWheel: Bool       { didSet { store.set(showWheel, forKey: "showWheel") } }
    @Published var wheelPosX: Double     { didSet { store.set(wheelPosX, forKey: "wheelPosX") } }
    @Published var wheelPosY: Double     { didSet { store.set(wheelPosY, forKey: "wheelPosY") } }
    @Published var wheelSize: Double     { didSet { store.set(wheelSize, forKey: "wheelSize") } }
    @Published var sliderPosX: Double    { didSet { store.set(sliderPosX, forKey: "sliderPosX") } }
    @Published var sliderPosY: Double    { didSet { store.set(sliderPosY, forKey: "sliderPosY") } }
    @Published var sliderWidth: Double   { didSet { store.set(sliderWidth, forKey: "sliderWidth") } }
    @Published var sliderHeight: Double  { didSet { store.set(sliderHeight, forKey: "sliderHeight") } }

    // MARK: Defaults
    static func defaultLabels() -> [String] {
        let named = ["A", "B", "X", "Y", "LB", "RB", "LT", "RT", "L3", "R3"]
        return (0..<kMaxButtons).map { $0 < named.count ? named[$0] : "\($0 + 1)" }
    }
    static func defaultColors() -> [Int] { (0..<kMaxButtons).map { $0 % 8 } }
    static func defaultModes() -> [Int]  { Array(repeating: 0, count: kMaxButtons) }
    // 5-column grid down the left side.
    static func defaultPosX() -> [Double] { (0..<kMaxButtons).map { 0.07 + Double($0 % 5) * 0.09 } }
    static func defaultPosY() -> [Double] { (0..<kMaxButtons).map { 0.28 + Double($0 / 5) * 0.12 } }
    static func defaultSizes() -> [Double] { Array(repeating: 72, count: kMaxButtons) }

    init() {
        host             = store.string(forKey: "host") ?? "192.168.1.50"
        port             = store.object(forKey: "port") as? Int ?? 5005
        autoConnect      = store.object(forKey: "autoConnect") as? Bool ?? false
        sendRateHz       = store.object(forKey: "sendRateHz") as? Int ?? 120
        sensitivity      = store.object(forKey: "sensitivity") as? Double ?? 1.0
        deadzoneDegrees  = store.object(forKey: "deadzoneDegrees") as? Double ?? 2.5
        maxLockDegrees   = store.object(forKey: "maxLockDegrees") as? Double ?? 90.0
        smoothing        = store.object(forKey: "smoothing") as? Double ?? 0.25
        steerCurve       = store.object(forKey: "steerCurve") as? Double ?? 1.0
        invertSteering   = store.object(forKey: "invertSteering") as? Bool ?? false
        autoInvert       = store.object(forKey: "autoInvert") as? Bool ?? true
        calibrateOnLaunch = store.object(forKey: "calibrateOnLaunch") as? Bool ?? true
        assistLevel      = store.object(forKey: "assistLevel") as? Int ?? 1
        recenterAssist   = store.object(forKey: "recenterAssist") as? Bool ?? true
        steerRateLimit   = store.object(forKey: "steerRateLimit") as? Double ?? 6.0
        throttleEase     = store.object(forKey: "throttleEase") as? Double ?? 0.25
        brakeGamma       = store.object(forKey: "brakeGamma") as? Double ?? 1.9
        throttleGamma    = store.object(forKey: "throttleGamma") as? Double ?? 1.0
        telemetryHaptics = store.object(forKey: "telemetryHaptics") as? Bool ?? true
        invertPedals     = store.object(forKey: "invertPedals") as? Bool ?? false
        hapticsEnabled   = store.object(forKey: "hapticsEnabled") as? Bool ?? true
        hapticOnConnect  = store.object(forKey: "hapticOnConnect") as? Bool ?? true
        accentColorIndex = store.object(forKey: "accentColorIndex") as? Int ?? 0
        backgroundStyle  = store.object(forKey: "backgroundStyle") as? Int ?? 1
        controlOpacity   = store.object(forKey: "controlOpacity") as? Double ?? 1.0
        buttonShape      = store.object(forKey: "buttonShape") as? Int ?? 0
        showAngleReadout = store.object(forKey: "showAngleReadout") as? Bool ?? true
        throttleColorIndex = store.object(forKey: "throttleColorIndex") as? Int ?? 0
        brakeColorIndex  = store.object(forKey: "brakeColorIndex") as? Int ?? 1
        hasOnboarded     = store.object(forKey: "hasOnboarded") as? Bool ?? false
        buttonCount      = store.object(forKey: "buttonCount") as? Int ?? 4
        buttonLabels     = AppSettings.pad(store.array(forKey: "buttonLabels") as? [String], AppSettings.defaultLabels())
        buttonColors     = AppSettings.pad(store.array(forKey: "buttonColors") as? [Int], AppSettings.defaultColors())
        buttonModes      = AppSettings.pad(store.array(forKey: "buttonModes") as? [Int], AppSettings.defaultModes())
        buttonPosX       = AppSettings.pad(store.array(forKey: "buttonPosX") as? [Double], AppSettings.defaultPosX())
        buttonPosY       = AppSettings.pad(store.array(forKey: "buttonPosY") as? [Double], AppSettings.defaultPosY())
        buttonSize       = AppSettings.pad(store.array(forKey: "buttonSize") as? [Double], AppSettings.defaultSizes())
        showWheel        = store.object(forKey: "showWheel") as? Bool ?? true
        wheelPosX        = store.object(forKey: "wheelPosX") as? Double ?? 0.5
        wheelPosY        = store.object(forKey: "wheelPosY") as? Double ?? 0.56
        wheelSize        = store.object(forKey: "wheelSize") as? Double ?? 180
        sliderPosX       = store.object(forKey: "sliderPosX") as? Double ?? 0.92
        sliderPosY       = store.object(forKey: "sliderPosY") as? Double ?? 0.5
        sliderWidth      = store.object(forKey: "sliderWidth") as? Double ?? 96
        sliderHeight     = store.object(forKey: "sliderHeight") as? Double ?? 320
    }

    /// Bundle steering assists into one easy knob.
    func applyAssistPreset() {
        switch assistLevel {
        case 0: // Off — direct
            smoothing = 0.10; deadzoneDegrees = 1.5; recenterAssist = false
            steerRateLimit = 0; throttleEase = 0
        case 2: // Strong — very forgiving
            smoothing = 0.45; deadzoneDegrees = 4.0; recenterAssist = true
            steerRateLimit = 3.5; throttleEase = 0.40
        default: // Light — recommended
            smoothing = 0.25; deadzoneDegrees = 2.5; recenterAssist = true
            steerRateLimit = 6.0; throttleEase = 0.25
        }
    }

    func resetLayout() {
        buttonPosX = AppSettings.defaultPosX()
        buttonPosY = AppSettings.defaultPosY()
        buttonSize = AppSettings.defaultSizes()
        showWheel = true
        wheelPosX = 0.5; wheelPosY = 0.56; wheelSize = 180
        sliderPosX = 0.92; sliderPosY = 0.5; sliderWidth = 96; sliderHeight = 320
    }

    func resetAll() {
        autoConnect = false; sendRateHz = 120
        sensitivity = 1.0; maxLockDegrees = 90.0; steerCurve = 1.0; invertSteering = false
        autoInvert = true; calibrateOnLaunch = true
        assistLevel = 1; applyAssistPreset()
        brakeGamma = 1.9; throttleGamma = 1.0; telemetryHaptics = true
        invertPedals = false; hapticsEnabled = true; hapticOnConnect = true
        accentColorIndex = 0; backgroundStyle = 1; controlOpacity = 1.0
        buttonShape = 0; showAngleReadout = true; throttleColorIndex = 0; brakeColorIndex = 1
        buttonCount = 4
        buttonLabels = AppSettings.defaultLabels()
        buttonColors = AppSettings.defaultColors()
        buttonModes  = AppSettings.defaultModes()
        resetLayout()
    }

    // MARK: - Import/Export Methods
    func exportLayout() -> String {
        let profile = LayoutProfile(
            buttonCount: buttonCount, buttonLabels: buttonLabels, buttonColors: buttonColors, buttonModes: buttonModes,
            buttonPosX: buttonPosX, buttonPosY: buttonPosY, buttonSize: buttonSize,
            showWheel: showWheel, wheelPosX: wheelPosX, wheelPosY: wheelPosY, wheelSize: wheelSize,
            sliderPosX: sliderPosX, sliderPosY: sliderPosY, sliderWidth: sliderWidth, sliderHeight: sliderHeight
        )
        if let data = try? JSONEncoder().encode(profile), let str = String(data: data, encoding: .utf8) {
            return str
        }
        return ""
    }

    func importLayout(json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let profile = try? JSONDecoder().decode(LayoutProfile.self, from: data) else { return false }
        
        self.buttonCount = profile.buttonCount
        self.buttonLabels = AppSettings.pad(profile.buttonLabels, AppSettings.defaultLabels())
        self.buttonColors = AppSettings.pad(profile.buttonColors, AppSettings.defaultColors())
        self.buttonModes = AppSettings.pad(profile.buttonModes, AppSettings.defaultModes())
        self.buttonPosX = AppSettings.pad(profile.buttonPosX, AppSettings.defaultPosX())
        self.buttonPosY = AppSettings.pad(profile.buttonPosY, AppSettings.defaultPosY())
        self.buttonSize = AppSettings.pad(profile.buttonSize, AppSettings.defaultSizes())
        
        self.showWheel = profile.showWheel
        self.wheelPosX = profile.wheelPosX
        self.wheelPosY = profile.wheelPosY
        self.wheelSize = profile.wheelSize
        
        self.sliderPosX = profile.sliderPosX
        self.sliderPosY = profile.sliderPosY
        self.sliderWidth = profile.sliderWidth
        self.sliderHeight = profile.sliderHeight
        return true
    }

    // Bindings into array elements (UIs use these so element edits persist).
    func labelBinding(_ i: Int) -> Binding<String> { Binding(get: { self.buttonLabels[i] }, set: { self.buttonLabels[i] = $0 }) }
    func colorBinding(_ i: Int) -> Binding<Int>    { Binding(get: { self.buttonColors[i] }, set: { self.buttonColors[i] = $0 }) }
    func modeBinding(_ i: Int) -> Binding<Int>     { Binding(get: { self.buttonModes[i] }, set: { self.buttonModes[i] = $0 }) }
    func sizeBinding(_ i: Int) -> Binding<Double>  { Binding(get: { self.buttonSize[i] }, set: { self.buttonSize[i] = $0 }) }
    func posXBinding(_ i: Int) -> Binding<Double>  { Binding(get: { self.buttonPosX[i] }, set: { self.buttonPosX[i] = $0 }) }
    func posYBinding(_ i: Int) -> Binding<Double>  { Binding(get: { self.buttonPosY[i] }, set: { self.buttonPosY[i] = $0 }) }
    var wheelXBinding: Binding<Double> { Binding(get: { self.wheelPosX }, set: { self.wheelPosX = $0 }) }
    var wheelYBinding: Binding<Double> { Binding(get: { self.wheelPosY }, set: { self.wheelPosY = $0 }) }
    var sliderXBinding: Binding<Double> { Binding(get: { self.sliderPosX }, set: { self.sliderPosX = $0 }) }
    var sliderYBinding: Binding<Double> { Binding(get: { self.sliderPosY }, set: { self.sliderPosY = $0 }) }

    private static func pad<T>(_ arr: [T]?, _ def: [T]) -> [T] {
        var a = arr ?? def
        if a.count < kMaxButtons { a += Array(def[a.count..<kMaxButtons]) }
        return Array(a.prefix(kMaxButtons))
    }
}
