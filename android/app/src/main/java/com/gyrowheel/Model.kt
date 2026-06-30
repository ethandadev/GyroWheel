package com.gyrowheel

import androidx.compose.ui.graphics.Color

/** Up to 30 macro buttons (btn1…btn30). Receivers map these to gamepad buttons. */
const val kMaxButtons = 30

enum class ButtonMode(val raw: Int) {
    HOLD(0), TOGGLE(1), TAP(2);

    val label: String
        get() = when (this) {
            HOLD -> "Hold"
            TOGGLE -> "Toggle"
            TAP -> "Tap"
        }

    companion object {
        fun from(raw: Int): ButtonMode = entries.firstOrNull { it.raw == raw } ?: HOLD
    }
}

/** Shared button color palette (mirrors the iOS ButtonPalette). */
object ButtonPalette {
    val colors: List<Color> = listOf(
        Color(0xFF34C759), // green
        Color(0xFFFF3B30), // red
        Color(0xFF0A84FF), // blue
        Color(0xFFFFD60A), // yellow
        Color(0xFFFF9F0A), // orange
        Color(0xFFAF52DE), // purple
        Color(0xFF30B0C7), // teal
        Color(0xFFFF2D55)  // pink
    )
    val names = listOf("Green", "Red", "Blue", "Yellow", "Orange", "Purple", "Teal", "Pink")

    fun color(index: Int): Color {
        val n = colors.size
        return colors[((index % n) + n) % n]
    }
}

/** A GyroWheel receiver found on the local network via NSD/Bonjour (`_gyrowheel._udp`). */
data class DiscoveredMac(val name: String, val host: String, val port: Int)

/** A haptic cue streamed back from the Mac receiver. */
data class HapticCue(val haptic: String, val intensity: Double?, val limit: Double?)

sealed class ConnectionState {
    object Setup : ConnectionState()
    object Connecting : ConnectionState()
    object Connected : ConnectionState()
    data class Failed(val message: String) : ConnectionState()

    val isConnected: Boolean get() = this is Connected

    val text: String
        get() = when (this) {
            is Setup -> "Disconnected"
            is Connecting -> "Connecting…"
            is Connected -> "Connected"
            is Failed -> "Error: $message"
        }
}
