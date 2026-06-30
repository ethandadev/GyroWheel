package com.gyrowheel

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * Plays telemetry-driven cues (lockup buzz, wheelspin rumble, kerb ticks, off-track
 * rumble, soft-lock tap) and shift clicks through the system Vibrator. The iOS app
 * uses CoreHaptics; here we approximate the same feel with waveforms + amplitudes.
 */
class HapticsEngine(context: Context) {
    private val vibrator: Vibrator? = run {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val mgr = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            mgr?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private val hasAmplitude: Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && (vibrator?.hasAmplitudeControl() ?: false)

    private fun amp(intensity: Double): Int =
        (intensity.coerceIn(0.0, 1.0) * 255).toInt().coerceIn(1, 255)

    private fun oneShot(ms: Long, intensity: Double = 1.0) {
        val v = vibrator ?: return
        if (!v.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val a = if (hasAmplitude) amp(intensity) else VibrationEffect.DEFAULT_AMPLITUDE
            v.vibrate(VibrationEffect.createOneShot(ms, a))
        } else {
            @Suppress("DEPRECATION") v.vibrate(ms)
        }
    }

    private fun waveform(timings: LongArray, amplitudes: IntArray) {
        val v = vibrator ?: return
        if (!v.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            v.vibrate(VibrationEffect.createWaveform(timings, amplitudes, -1))
        } else {
            @Suppress("DEPRECATION") v.vibrate(timings, -1)
        }
    }

    /** Steering soft lock — a light single tap to signal you hit the limit. */
    fun softLock() = oneShot(12, 0.6)

    /** Gear shift — one crisp click; upshifts a touch shorter/brighter than downshifts. */
    fun shift(up: Boolean) = oneShot(if (up) 14 else 22, 1.0)

    /** Brake lockup — a rapid sharp triple burst (artificial ABS buzz). */
    fun lockup() = waveform(
        longArrayOf(0, 14, 16, 14, 16, 14),
        intArrayOf(0, 255, 0, 255, 0, 255)
    )

    /** Rear wheelspin — a heavier, softer pulse scaled by intensity. */
    fun wheelspin(intensity: Double) = oneShot(120, intensity.coerceIn(0.4, 1.0))

    /** Riding a kerb — crisp ridged ticks. */
    fun kerb() = waveform(
        longArrayOf(0, 10, 14, 10, 14, 10),
        intArrayOf(0, 230, 0, 230, 0, 230)
    )

    /** Off the track (grass/gravel) — a rough, heavy low rumble. */
    fun offtrack(intensity: Double) {
        val a = amp(intensity.coerceIn(0.7, 1.0))
        waveform(
            longArrayOf(0, 60, 20, 40, 20, 40),
            intArrayOf(0, a, a / 2, a, a / 2, a)
        )
    }
}
