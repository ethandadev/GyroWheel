package com.gyrowheel

import android.app.Application
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import kotlin.math.pow

/**
 * Ties motion + network + haptics + discovery + settings together and exposes
 * Compose-observable state to the UI. Android twin of the iOS GameController.
 */
class GameController(app: Application) : AndroidViewModel(app) {
    val settings = AppSettings(app)
    val discovery = Discovery(app)

    private val motion = MotionManager(app)
    private val network = NetworkManager()
    private val haptics = HapticsEngine(app)
    private val main = Handler(Looper.getMainLooper())

    var steer by mutableStateOf(0.0); private set
    var throttle by mutableStateOf(0.0); private set
    var brake by mutableStateOf(0.0); private set
    val buttons = mutableStateListOf<Boolean>().apply { repeat(kMaxButtons) { add(false) } }
    var status by mutableStateOf<ConnectionState>(ConnectionState.Setup); private set
    var txRate by mutableStateOf(0); private set
    var target by mutableStateOf(""); private set

    private var orientationFlipped = false
    private var lastUiSteerNs = 0L

    init {
        motion.settings = settings

        motion.onSoftLock = {
            if (settings.hapticsEnabled) main.post { haptics.softLock() }
        }

        motion.onBackTap = { handleBackTapShift() }

        motion.onSteer = { value ->
            var v = value
            if (settings.autoInvert && orientationFlipped) v = -v
            network.updateSteer(v)
            val now = System.nanoTime()
            if (now - lastUiSteerNs >= 16_000_000L) { // ~60 Hz UI cap
                lastUiSteerNs = now
                main.post { steer = v }
            }
        }

        network.onState = { state ->
            main.post {
                status = state
                if (!state.isConnected) txRate = 0
            }
        }
        network.onRate = { rate -> main.post { txRate = rate } }
        network.onHaptic = { cue ->
            cue.limit?.let { motion.currentDynamicGripLimit = it }
            if (settings.telemetryHaptics) main.post {
                when (cue.haptic) {
                    "lockup" -> haptics.lockup()
                    "wheelspin" -> haptics.wheelspin(cue.intensity ?: 0.6)
                    "kerb" -> haptics.kerb()
                    "offtrack" -> haptics.offtrack(cue.intensity ?: 0.7)
                    "softLock" -> haptics.softLock()
                }
            }
        }
    }

    fun start() = motion.start()
    fun stop() = motion.stop()
    fun setLandscapeFlipped(flipped: Boolean) { orientationFlipped = flipped }

    val targetLabel: String get() = if (target.isEmpty()) "${settings.host}:${settings.port}" else target

    fun connect() {
        target = "${settings.host}:${settings.port}"
        network.sendRateHz = settings.sendRateHz
        network.connect(settings.host, settings.port)
        if (settings.calibrateOnLaunch) calibrate()
    }

    fun connect(mac: DiscoveredMac) {
        target = mac.name
        network.sendRateHz = settings.sendRateHz
        network.connect(mac.host, mac.port)
        if (settings.calibrateOnLaunch) calibrate()
    }

    fun disconnect() {
        network.disconnect()
        main.post { txRate = 0; status = ConnectionState.Setup }
    }

    fun calibrate() = motion.calibrate()

    fun setThrottleBrake(throttle: Double, brake: Double) {
        this.throttle = throttle
        this.brake = brake
        network.throttleEase = settings.throttleEase
        val t = curve(throttle, settings.throttleGamma)
        val b = curve(brake, settings.brakeGamma)
        if (settings.invertPedals) network.updateThrottleBrake(b, t)
        else network.updateThrottleBrake(t, b)
    }

    private fun curve(v: Double, gamma: Double): Double {
        if (gamma == 1.0 || v <= 0) return v
        return v.coerceIn(0.0, 1.0).pow(gamma)
    }

    fun buttonDown(index: Int) {
        if (index !in buttons.indices) return
        motion.suppressBackTap()
        when (ButtonMode.from(settings.buttonModes.getOrElse(index) { 0 })) {
            ButtonMode.HOLD -> setButton(index, true)
            ButtonMode.TOGGLE -> setButton(index, !buttons[index])
            ButtonMode.TAP -> {
                setButton(index, true)
                main.postDelayed({ setButton(index, false) }, 100)
            }
        }
    }

    fun buttonUp(index: Int) {
        if (index !in buttons.indices) return
        if (ButtonMode.from(settings.buttonModes.getOrElse(index) { 0 }) == ButtonMode.HOLD) setButton(index, false)
    }

    private fun setButton(index: Int, pressed: Boolean) {
        if (index !in buttons.indices) return
        buttons[index] = pressed
        network.updateButton("btn${index + 1}", pressed)
    }

    // MARK: - Back-tap paddle shifter
    private fun handleBackTapShift() {
        if (!settings.backTapShiftEnabled) return
        main.post {
            val up = throttle >= 0.5
            val index = if (up) settings.upshiftButton else settings.downshiftButton
            pulseShift(index)
            if (settings.shiftHaptics && settings.hapticsEnabled) haptics.shift(up)
        }
    }

    private fun pulseShift(index: Int) {
        if (index !in buttons.indices) return
        setButton(index, true)
        main.postDelayed({ setButton(index, false) }, 90)
    }

    override fun onCleared() {
        super.onCleared()
        network.disconnect()
        motion.stop()
        discovery.stop()
    }
}
