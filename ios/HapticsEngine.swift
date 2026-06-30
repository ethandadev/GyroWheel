import Foundation
import CoreHaptics
import UIKit

/// Plays telemetry-driven cues: a sharp burst for brake lockup, a heavy rhythmic
/// rumble for wheelspin. Falls back to simple impacts on devices without the
/// Taptic Engine.
final class HapticsEngine {
    private var engine: CHHapticEngine?
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let fallbackGen = UIImpactFeedbackGenerator(style: .heavy) // Upgraded to heavy fallback
    private let softLockGen = UIImpactFeedbackGenerator(style: .rigid) // For the steering soft lock

    func prepare() {
        guard supported, engine == nil else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        try? engine?.start()
    }

    /// Steering soft lock (a light tap to let the user know they hit the limit)
    func softLock() {
        guard supported, let engine else { softLockGen.impactOccurred(intensity: 0.7); return }
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
        ], relativeTime: 0)
        play([event], on: engine)
    }

    /// Gear shift → one crisp click. Upshifts feel brighter/sharper, downshifts a touch heavier.
    func shift(up: Bool) {
        guard supported, let engine else { softLockGen.impactOccurred(intensity: 0.9); return }
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: up ? 0.95 : 0.55)
        ], relativeTime: 0)
        play([event], on: engine)
    }

    /// Brake lockup → rapid sharp burst (your artificial ABS buzz).
    func lockup() {
        guard supported, let engine else { fallbackGen.impactOccurred(); return }
        let events = (0..<3).map { i in
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            ], relativeTime: Double(i) * 0.045)
        }
        play(events, on: engine)
    }

    /// Rear wheelspin → heavier, softer continuous pulse.
    func wheelspin(_ intensity: Double) {
        guard supported, let engine else { fallbackGen.impactOccurred(); return }
        let i = Float(min(max(intensity, 0.4), 1.0))
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4) // Slightly sharper
        ], relativeTime: 0, duration: 0.16)
        play([event], on: engine)
    }

    /// Riding a kerb → crisp ridged ticks (the Mac re-sends while you're on it).
    func kerb() {
        guard supported, let engine else { fallbackGen.impactOccurred(); return }
        // F1 kerbs are harsh and vibrate quickly. 
        let events = (0..<3).map { i in
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
            ], relativeTime: Double(i) * 0.035)
        }
        play(events, on: engine)
    }

    /// Off the track (grass/gravel/sand) → rough, heavy low rumble.
    func offtrack(_ intensity: Double) {
        guard supported, let engine else { fallbackGen.impactOccurred(); return }
        let i = Float(min(max(intensity, 0.7), 1.0))
        
        let continuous = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
        ], relativeTime: 0, duration: 0.2)
        
        let transients = (0..<4).map { idx in
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            ], relativeTime: Double(idx) * 0.05)
        }
        
        play([continuous] + transients, on: engine)
    }

    private func play(_ events: [CHHapticEvent], on engine: CHHapticEngine) {
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Engine may have stopped; try to restart for next time.
            try? engine.start()
        }
    }
}
