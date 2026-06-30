package com.gyrowheel

import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import kotlin.math.max
import kotlin.math.min

/**
 * Streams the input packet (steer/throttle/brake + btn1…btn30) over UDP at the
 * configured rate, eases the throttle on lift-off, and receives haptic cues +
 * the dynamic grip limit the Mac streams back. Android twin of the iOS NetworkManager.
 */
class NetworkManager {
    private var socket: DatagramSocket? = null
    @Volatile private var running = false
    private var sendThread: Thread? = null
    private var recvThread: Thread? = null

    private val lock = Any()
    private var steer = 0f
    private var brake = 0f
    private var packetThrottle = 0f
    private var targetThrottle = 0f
    private var targetBrake = 0f
    private val buttons = BooleanArray(kMaxButtons + 1) // index 1..kMaxButtons

    var sendRateHz = 120
    var throttleEase = 0.0

    var onState: ((ConnectionState) -> Unit)? = null
    var onRate: ((Int) -> Unit)? = null
    var onHaptic: ((HapticCue) -> Unit)? = null

    fun connect(host: String, port: Int) {
        val trimmed = host.trim()
        if (trimmed.isEmpty() || port !in 1..65535) {
            onState?.invoke(ConnectionState.Failed("Invalid host/port"))
            return
        }
        disconnect()
        running = true
        onState?.invoke(ConnectionState.Connecting)

        sendThread = Thread { runSendLoop(trimmed, port) }.also { it.start() }
    }

    fun disconnect() {
        running = false
        socket?.close()
        socket = null
        sendThread = null
        recvThread = null
    }

    private fun runSendLoop(host: String, port: Int) {
        try {
            val sock = DatagramSocket()
            socket = sock
            val address = InetAddress.getByName(host)

            recvThread = Thread { runReceiveLoop(sock) }.also { it.start() }

            var announced = false
            var sendCount = 0
            var windowStart = System.nanoTime()

            while (running) {
                val intervalMs = (1000L / max(30, min(sendRateHz, 200)))
                val data = buildPacket().toString().toByteArray()
                sock.send(DatagramPacket(data, data.size, address, port))

                if (!announced) {
                    announced = true
                    onState?.invoke(ConnectionState.Connected)
                }

                // Live transmit-rate readout (mirrors iOS).
                sendCount++
                val now = System.nanoTime()
                val elapsed = (now - windowStart) / 1_000_000_000.0
                if (elapsed >= 1.0) {
                    onRate?.invoke((sendCount / elapsed).toInt())
                    sendCount = 0
                    windowStart = now
                }

                Thread.sleep(intervalMs)
            }
        } catch (e: Exception) {
            if (running) onState?.invoke(ConnectionState.Failed(e.message ?: "Network error"))
        } finally {
            socket?.close()
            socket = null
        }
    }

    private fun runReceiveLoop(sock: DatagramSocket) {
        val buf = ByteArray(2048)
        while (running) {
            try {
                val packet = DatagramPacket(buf, buf.size)
                sock.receive(packet)
                val text = String(packet.data, 0, packet.length)
                val json = JSONObject(text)
                val haptic = json.optString("haptic", "")
                val intensity = if (json.has("intensity")) json.optDouble("intensity") else null
                val limit = if (json.has("limit")) json.optDouble("limit") else null
                onHaptic?.invoke(HapticCue(haptic, intensity, limit))
            } catch (e: Exception) {
                if (!running) break // socket closed on disconnect
            }
        }
    }

    private fun buildPacket(): JSONObject {
        synchronized(lock) {
            // Throttle applies instantly but releases gradually (ease-off); brake is instant.
            packetThrottle = if (targetThrottle >= packetThrottle || throttleEase <= 0) {
                targetThrottle
            } else {
                val dt = 1.0 / max(30, min(sendRateHz, 200))
                val step = (dt / throttleEase).toFloat()
                max(targetThrottle, packetThrottle - step)
            }
            brake = targetBrake

            val o = JSONObject()
            o.put("steer", steer.toDouble())
            o.put("throttle", packetThrottle.toDouble())
            o.put("brake", brake.toDouble())
            val b = JSONObject()
            for (i in 1..kMaxButtons) b.put("btn$i", buttons[i])
            o.put("buttons", b)
            return o
        }
    }

    fun updateSteer(value: Double) {
        synchronized(lock) { steer = value.toFloat() }
    }

    fun updateThrottleBrake(throttle: Double, brake: Double) {
        synchronized(lock) { targetThrottle = throttle.toFloat(); targetBrake = brake.toFloat() }
    }

    /** name is "btn1"…"btn30". */
    fun updateButton(name: String, pressed: Boolean) {
        val idx = name.removePrefix("btn").toIntOrNull() ?: return
        if (idx !in 1..kMaxButtons) return
        synchronized(lock) { buttons[idx] = pressed }
    }
}
