package com.gyrowheel

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Reads the gravity vector and converts the "steering-wheel" rotation (about the
 * screen-normal axis) into a value in -1.0…1.0 — the Android twin of the iOS
 * MotionManager. Also runs the adaptive back-tap detector off linear acceleration.
 */
class MotionManager(context: Context) : SensorEventListener {
    private val sm = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val gravitySensor: Sensor? = sm.getDefaultSensor(Sensor.TYPE_GRAVITY)
    private val linearSensor: Sensor? = sm.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)

    var settings: AppSettings? = null
    var onSteer: ((Double) -> Unit)? = null
    var onSoftLock: (() -> Unit)? = null
    var onBackTap: (() -> Unit)? = null

    /** Dynamic grip limit provided by Mac telemetry (1.0 = full lock, <1.0 = reduced). */
    @Volatile var currentDynamicGripLimit: Double = 1.0

    private var calibrationOffset = 0.0
    private var lastRawAngle = 0.0
    private var smoothedValue = 0.0
    private var lastOutput = 0.0
    private var lastTimeNs = 0L
    private var hasFiredSoftLock = false

    // Back-tap detection.
    private var prevAccel: FloatArray? = null
    private var jerkBaseline = 0.0
    private var lastTapNs = 0L
    private val tapBaselineAlpha = 0.04
    private val tapDebounceNs = 200_000_000L // 0.20 s
    @Volatile private var backTapSuppressUntilNs = 0L

    /** Call when a screen button is tapped to briefly suppress back-tap detection
     * (screen taps jostle the phone and can look like a back-tap). */
    fun suppressBackTap(durationMs: Long = 350) {
        val t = System.nanoTime() + durationMs * 1_000_000L
        if (t > backTapSuppressUntilNs) backTapSuppressUntilNs = t
    }

    fun start() {
        gravitySensor?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
        linearSensor?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_FASTEST) }
        lastTimeNs = System.nanoTime()
    }

    fun stop() {
        sm.unregisterListener(this)
        prevAccel = null
        jerkBaseline = 0.0
    }

    fun calibrate() {
        calibrationOffset = lastRawAngle
        smoothedValue = 0.0
        lastOutput = 0.0
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_GRAVITY -> handleGravity(event.values, event.timestamp)
            Sensor.TYPE_LINEAR_ACCELERATION -> detectBackTap(event.values)
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun handleGravity(g: FloatArray, timestampNs: Long) {
        val s = settings
        // Negate X so the steering direction matches the device's landscape orientation
        // (the iOS axis convention is mirrored on Android); the user's Invert toggle still applies on top.
        val rawAngle = atan2(-g[0].toDouble(), g[1].toDouble())
        lastRawAngle = rawAngle

        if (s?.recenterAssist == true) {
            var rel = rawAngle - calibrationOffset
            rel = atan2(sin(rel), cos(rel))
            val dzRad = (s.deadzoneDegrees) * Math.PI / 180.0
            if (kotlin.math.abs(rel) < dzRad) {
                calibrationOffset += rel * 0.03
                calibrationOffset = atan2(sin(calibrationOffset), cos(calibrationOffset))
            }
        }

        val target = computeSteer(rawAngle)

        val smooth = (s?.smoothing ?: 0.25).coerceIn(0.0, 0.95)
        smoothedValue += (1.0 - smooth) * (target - smoothedValue)
        var out = smoothedValue

        val now = if (timestampNs != 0L) timestampNs else System.nanoTime()
        val dt = ((now - lastTimeNs) / 1_000_000_000.0).coerceIn(0.0, 0.1)
        lastTimeNs = now
        val rl = s?.steerRateLimit ?: 0.0
        if (rl > 0) {
            val maxStep = rl * dt
            out = out.coerceIn(lastOutput - maxStep, lastOutput + maxStep)
        }
        lastOutput = out

        onSteer?.invoke(out)
    }

    private fun computeSteer(rawAngle: Double): Double {
        val s = settings
        var angle = rawAngle - calibrationOffset
        angle = atan2(sin(angle), cos(angle))
        var degrees = angle * 180.0 / Math.PI

        val deadzone = s?.deadzoneDegrees ?: 2.5
        if (kotlin.math.abs(degrees) < deadzone) return 0.0
        degrees -= if (degrees > 0) deadzone else -deadzone

        val maxLock = ((s?.maxLockDegrees ?: 90.0) - deadzone).coerceAtLeast(1.0)
        var value = degrees / maxLock

        // Soft lock against the current dynamic grip limit.
        val dynamicLimit = currentDynamicGripLimit
        val absoluteValue = kotlin.math.abs(value)
        if (absoluteValue >= dynamicLimit * 0.98) {
            if (!hasFiredSoftLock) {
                hasFiredSoftLock = true
                onSoftLock?.invoke()
            }
        } else if (absoluteValue < dynamicLimit * 0.85) {
            hasFiredSoftLock = false
        }

        // Push-past-limit: allow it, but at half effectiveness.
        if (absoluteValue > dynamicLimit) {
            val sgn = if (value < 0) -1.0 else 1.0
            val overflow = absoluteValue - dynamicLimit
            value = sgn * (dynamicLimit + overflow * 0.5)
        }

        value *= (s?.sensitivity ?: 1.0)
        if (s?.invertSteering == true) value = -value
        value = value.coerceIn(-2.0, 2.0)

        val gamma = s?.steerCurve ?: 1.0
        if (gamma != 1.0) {
            val sgn = if (value < 0) -1.0 else 1.0
            value = if (kotlin.math.abs(value) <= 1.0) {
                sgn * kotlin.math.abs(value).pow(gamma)
            } else {
                sgn * (1.0.pow(gamma) + (kotlin.math.abs(value) - 1.0))
            }
        }
        return value
    }

    /** Jerk-based back-tap with an adaptive ambient baseline (mirrors BackTapTest). */
    private fun detectBackTap(a: FloatArray) {
        if (settings?.backTapShiftEnabled != true) {
            prevAccel = null
            return
        }
        if (System.nanoTime() < backTapSuppressUntilNs) return
        val p = prevAccel
        if (p == null) {
            prevAccel = floatArrayOf(a[0], a[1], a[2])
            return
        }
        val dx = (a[0] - p[0]).toDouble()
        val dy = (a[1] - p[1]).toDouble()
        val dz = (a[2] - p[2]).toDouble()
        p[0] = a[0]; p[1] = a[1]; p[2] = a[2]

        val jerk = sqrt(dx * dx + dy * dy + dz * dz)
        val floor = settings?.backTapSensitivity ?: 2.5
        val ratio = settings?.backTapSharpness ?: 3.5
        val tripLevel = maxOf(floor, jerkBaseline * ratio)
        val isSpike = jerk > tripLevel

        if (!isSpike) {
            jerkBaseline = tapBaselineAlpha * jerk + (1 - tapBaselineAlpha) * jerkBaseline
            return
        }
        val now = System.nanoTime()
        if (now - lastTapNs <= tapDebounceNs) return
        lastTapNs = now
        onBackTap?.invoke()
    }
}
