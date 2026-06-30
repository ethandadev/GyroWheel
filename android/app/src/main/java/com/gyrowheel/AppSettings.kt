package com.gyrowheel

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.mutableStateOf
import org.json.JSONArray
import org.json.JSONObject
import kotlin.reflect.KProperty

/**
 * User-tunable configuration + freeform HUD layout, persisted to SharedPreferences.
 * Positions are normalized (0…1) to the play area so they adapt to any device.
 * Each property is backed by Compose state so the UI recomposes on change.
 */
class AppSettings(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("gyrowheel.settings", Context.MODE_PRIVATE)

    // MARK: - Compose-observable, prefs-backed delegate
    private inner class Pref<T>(
        private val key: String,
        default: T,
        private val load: (String, T) -> T,
        private val save: (String, T) -> Unit
    ) {
        private val state = mutableStateOf(load(key, default))
        operator fun getValue(thisRef: Any?, p: KProperty<*>): T = state.value
        operator fun setValue(thisRef: Any?, p: KProperty<*>, v: T) {
            state.value = v
            save(key, v)
        }
    }

    private fun boolPref(key: String, def: Boolean) = Pref(key, def,
        { k, d -> prefs.getBoolean(k, d) }, { k, v -> prefs.edit().putBoolean(k, v).apply() })

    private fun intPref(key: String, def: Int) = Pref(key, def,
        { k, d -> prefs.getInt(k, d) }, { k, v -> prefs.edit().putInt(k, v).apply() })

    private fun dblPref(key: String, def: Double) = Pref(key, def,
        { k, d -> if (prefs.contains(k)) prefs.getFloat(k, d.toFloat()).toDouble() else d },
        { k, v -> prefs.edit().putFloat(k, v.toFloat()).apply() })

    private fun strPref(key: String, def: String) = Pref(key, def,
        { k, d -> prefs.getString(k, d) ?: d }, { k, v -> prefs.edit().putString(k, v).apply() })

    private fun intListPref(key: String, def: List<Int>) = Pref(key, def,
        { k, d -> prefs.getString(k, null)?.let { jsonToIntList(it) } ?: d },
        { k, v -> prefs.edit().putString(k, intListToJson(v)).apply() })

    private fun dblListPref(key: String, def: List<Double>) = Pref(key, def,
        { k, d -> prefs.getString(k, null)?.let { jsonToDblList(it) } ?: d },
        { k, v -> prefs.edit().putString(k, dblListToJson(v)).apply() })

    private fun strListPref(key: String, def: List<String>) = Pref(key, def,
        { k, d -> prefs.getString(k, null)?.let { jsonToStrList(it) } ?: d },
        { k, v -> prefs.edit().putString(k, strListToJson(v)).apply() })

    // MARK: - Connection
    var host by strPref("host", "192.168.1.50")
    var port by intPref("port", 5005)
    var autoConnect by boolPref("autoConnect", false)
    var sendRateHz by intPref("sendRateHz", 120)

    // MARK: - Steering
    var sensitivity by dblPref("sensitivity", 1.0)
    var deadzoneDegrees by dblPref("deadzoneDegrees", 2.5)
    var maxLockDegrees by dblPref("maxLockDegrees", 90.0)
    var smoothing by dblPref("smoothing", 0.25)
    var steerCurve by dblPref("steerCurve", 1.0)
    var invertSteering by boolPref("invertSteering", false)
    var autoInvert by boolPref("autoInvert", true)
    var calibrateOnLaunch by boolPref("calibrateOnLaunch", true)

    // MARK: - Assists
    var assistLevel by intPref("assistLevel", 1)
    var recenterAssist by boolPref("recenterAssist", true)
    var steerRateLimit by dblPref("steerRateLimit", 6.0)
    var throttleEase by dblPref("throttleEase", 0.25)
    var brakeGamma by dblPref("brakeGamma", 1.9)
    var throttleGamma by dblPref("throttleGamma", 1.0)
    var telemetryHaptics by boolPref("telemetryHaptics", true)

    // MARK: - Paddle Shifter (back-tap)
    var backTapShiftEnabled by boolPref("backTapShiftEnabled", false)
    var backTapSensitivity by dblPref("backTapSensitivity", 2.5) // m/s² per sample (Android units)
    var backTapSharpness by dblPref("backTapSharpness", 3.5)
    var upshiftButton by intPref("upshiftButton", 0)
    var downshiftButton by intPref("downshiftButton", 1)
    var shiftHaptics by boolPref("shiftHaptics", true)

    // MARK: - Pedals
    var invertPedals by boolPref("invertPedals", false)

    // MARK: - Feedback
    var hapticsEnabled by boolPref("hapticsEnabled", true)
    var hapticOnConnect by boolPref("hapticOnConnect", true)

    // MARK: - Appearance
    var accentColorIndex by intPref("accentColorIndex", 0)
    var backgroundStyle by intPref("backgroundStyle", 1)
    var controlOpacity by dblPref("controlOpacity", 1.0)
    var buttonShape by intPref("buttonShape", 0)
    var showAngleReadout by boolPref("showAngleReadout", true)
    var throttleColorIndex by intPref("throttleColorIndex", 0)
    var brakeColorIndex by intPref("brakeColorIndex", 1)

    // MARK: - Onboarding
    var hasOnboarded by boolPref("hasOnboarded", false)

    // MARK: - Macro buttons
    var buttonCount by intPref("buttonCount", 4)
    var buttonLabels by strListPref("buttonLabels", defaultLabels())
    var buttonColors by intListPref("buttonColors", defaultColors())
    var buttonModes by intListPref("buttonModes", defaultModes())
    var buttonPosX by dblListPref("buttonPosX", defaultPosX())
    var buttonPosY by dblListPref("buttonPosY", defaultPosY())
    var buttonSize by dblListPref("buttonSize", defaultSizes())

    // MARK: - HUD elements (normalized center + size)
    var showWheel by boolPref("showWheel", true)
    var wheelPosX by dblPref("wheelPosX", 0.5)
    var wheelPosY by dblPref("wheelPosY", 0.56)
    var wheelSize by dblPref("wheelSize", 180.0)
    var sliderPosX by dblPref("sliderPosX", 0.92)
    var sliderPosY by dblPref("sliderPosY", 0.5)
    var sliderWidth by dblPref("sliderWidth", 96.0)
    var sliderHeight by dblPref("sliderHeight", 320.0)

    // MARK: - Element mutators (reassign whole list so Compose + prefs update)
    fun setLabel(i: Int, v: String) { buttonLabels = buttonLabels.toMutableList().also { it[i] = v } }
    fun setColor(i: Int, v: Int) { buttonColors = buttonColors.toMutableList().also { it[i] = v } }
    fun setMode(i: Int, v: Int) { buttonModes = buttonModes.toMutableList().also { it[i] = v } }
    fun setSize(i: Int, v: Double) { buttonSize = buttonSize.toMutableList().also { it[i] = v } }
    fun setPosX(i: Int, v: Double) { buttonPosX = buttonPosX.toMutableList().also { it[i] = v } }
    fun setPosY(i: Int, v: Double) { buttonPosY = buttonPosY.toMutableList().also { it[i] = v } }

    /** Bundle steering assists into one easy knob. */
    fun applyAssistPreset() {
        when (assistLevel) {
            0 -> { smoothing = 0.10; deadzoneDegrees = 1.5; recenterAssist = false; steerRateLimit = 0.0; throttleEase = 0.0 }
            2 -> { smoothing = 0.45; deadzoneDegrees = 4.0; recenterAssist = true; steerRateLimit = 3.5; throttleEase = 0.40 }
            else -> { smoothing = 0.25; deadzoneDegrees = 2.5; recenterAssist = true; steerRateLimit = 6.0; throttleEase = 0.25 }
        }
    }

    fun resetLayout() {
        buttonPosX = defaultPosX(); buttonPosY = defaultPosY(); buttonSize = defaultSizes()
        showWheel = true
        wheelPosX = 0.5; wheelPosY = 0.56; wheelSize = 180.0
        sliderPosX = 0.92; sliderPosY = 0.5; sliderWidth = 96.0; sliderHeight = 320.0
    }

    fun resetAll() {
        autoConnect = false; sendRateHz = 120
        sensitivity = 1.0; maxLockDegrees = 90.0; steerCurve = 1.0; invertSteering = false
        autoInvert = true; calibrateOnLaunch = true
        assistLevel = 1; applyAssistPreset()
        brakeGamma = 1.9; throttleGamma = 1.0; telemetryHaptics = true
        backTapShiftEnabled = false; backTapSensitivity = 2.5; backTapSharpness = 3.5
        upshiftButton = 0; downshiftButton = 1; shiftHaptics = true
        invertPedals = false; hapticsEnabled = true; hapticOnConnect = true
        accentColorIndex = 0; backgroundStyle = 1; controlOpacity = 1.0
        buttonShape = 0; showAngleReadout = true; throttleColorIndex = 0; brakeColorIndex = 1
        buttonCount = 4
        buttonLabels = defaultLabels(); buttonColors = defaultColors(); buttonModes = defaultModes()
        resetLayout()
    }

    // MARK: - Import / Export (JSON keys match the iOS LayoutProfile for cross-device profiles)
    fun exportLayout(): String {
        val o = JSONObject()
        o.put("buttonCount", buttonCount)
        o.put("buttonLabels", JSONArray(buttonLabels))
        o.put("buttonColors", JSONArray(buttonColors))
        o.put("buttonModes", JSONArray(buttonModes))
        o.put("buttonPosX", JSONArray(buttonPosX))
        o.put("buttonPosY", JSONArray(buttonPosY))
        o.put("buttonSize", JSONArray(buttonSize))
        o.put("showWheel", showWheel)
        o.put("wheelPosX", wheelPosX); o.put("wheelPosY", wheelPosY); o.put("wheelSize", wheelSize)
        o.put("sliderPosX", sliderPosX); o.put("sliderPosY", sliderPosY)
        o.put("sliderWidth", sliderWidth); o.put("sliderHeight", sliderHeight)
        return o.toString()
    }

    fun importLayout(json: String): Boolean {
        return try {
            val o = JSONObject(json)
            buttonCount = o.optInt("buttonCount", buttonCount).coerceIn(2, kMaxButtons)
            buttonLabels = pad(jsonArrToStr(o.optJSONArray("buttonLabels")), defaultLabels())
            buttonColors = pad(jsonArrToInt(o.optJSONArray("buttonColors")), defaultColors())
            buttonModes = pad(jsonArrToInt(o.optJSONArray("buttonModes")), defaultModes())
            buttonPosX = pad(jsonArrToDbl(o.optJSONArray("buttonPosX")), defaultPosX())
            buttonPosY = pad(jsonArrToDbl(o.optJSONArray("buttonPosY")), defaultPosY())
            buttonSize = pad(jsonArrToDbl(o.optJSONArray("buttonSize")), defaultSizes())
            showWheel = o.optBoolean("showWheel", showWheel)
            wheelPosX = o.optDouble("wheelPosX", wheelPosX)
            wheelPosY = o.optDouble("wheelPosY", wheelPosY)
            wheelSize = o.optDouble("wheelSize", wheelSize)
            sliderPosX = o.optDouble("sliderPosX", sliderPosX)
            sliderPosY = o.optDouble("sliderPosY", sliderPosY)
            sliderWidth = o.optDouble("sliderWidth", sliderWidth)
            sliderHeight = o.optDouble("sliderHeight", sliderHeight)
            true
        } catch (e: Exception) {
            false
        }
    }

    companion object {
        fun defaultLabels(): List<String> {
            val named = listOf("A", "B", "X", "Y", "LB", "RB", "LT", "RT", "L3", "R3")
            return (0 until kMaxButtons).map { if (it < named.size) named[it] else "${it + 1}" }
        }
        fun defaultColors(): List<Int> = (0 until kMaxButtons).map { it % 8 }
        fun defaultModes(): List<Int> = List(kMaxButtons) { 0 }
        fun defaultPosX(): List<Double> = (0 until kMaxButtons).map { 0.07 + (it % 5) * 0.09 }
        fun defaultPosY(): List<Double> = (0 until kMaxButtons).map { 0.28 + (it / 5) * 0.12 }
        fun defaultSizes(): List<Double> = List(kMaxButtons) { 72.0 }

        fun <T> pad(arr: List<T>?, def: List<T>): List<T> {
            val a = (arr ?: def).toMutableList()
            if (a.size < kMaxButtons) a.addAll(def.subList(a.size, kMaxButtons))
            return a.take(kMaxButtons)
        }

        private fun jsonToIntList(s: String) = jsonArrToInt(JSONArray(s))
        private fun jsonToDblList(s: String) = jsonArrToDbl(JSONArray(s))
        private fun jsonToStrList(s: String) = jsonArrToStr(JSONArray(s))
        private fun intListToJson(v: List<Int>) = JSONArray(v).toString()
        private fun dblListToJson(v: List<Double>) = JSONArray(v).toString()
        private fun strListToJson(v: List<String>) = JSONArray(v).toString()

        private fun jsonArrToInt(a: JSONArray?): List<Int> =
            if (a == null) emptyList() else (0 until a.length()).map { a.getInt(it) }
        private fun jsonArrToDbl(a: JSONArray?): List<Double> =
            if (a == null) emptyList() else (0 until a.length()).map { a.getDouble(it) }
        private fun jsonArrToStr(a: JSONArray?): List<String> =
            if (a == null) emptyList() else (0 until a.length()).map { a.getString(it) }
    }
}
