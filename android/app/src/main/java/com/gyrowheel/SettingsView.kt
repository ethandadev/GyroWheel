package com.gyrowheel

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val Accent = Color(0xFF34C759)
private val CardBg = Color(0xFF1C1C1E)
private val Hairline = Color(0xFF2C2C2E)

private enum class Route { ROOT, CONNECTION, DRIVING, PEDALS, PADDLE, LAYOUT, BUTTONS, APPEARANCE, IMPORT_EXPORT }

@Composable
fun SettingsScreen(controller: GameController, onClose: () -> Unit, onEditLayout: () -> Unit) {
    val settings = controller.settings
    var route by remember { mutableStateOf(Route.ROOT) }

    Surface(Modifier.fillMaxSize(), color = Color.Black) {
        Column(Modifier.fillMaxSize()) {
            Header(titleFor(route)) {
                if (route == Route.ROOT) onClose() else route = Route.ROOT
            }
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp, vertical = 8.dp)
            ) {
                when (route) {
                    Route.ROOT -> RootMenu(settings, onNavigate = { route = it })
                    Route.CONNECTION -> ConnectionScreen(controller, settings, onClose)
                    Route.DRIVING -> DrivingScreen(controller, settings)
                    Route.PEDALS -> PedalsScreen(settings)
                    Route.PADDLE -> PaddleScreen(settings)
                    Route.LAYOUT -> LayoutScreen(settings, onEditLayout)
                    Route.BUTTONS -> ButtonsScreen(settings)
                    Route.APPEARANCE -> AppearanceScreen(settings)
                    Route.IMPORT_EXPORT -> ImportExportScreen(settings)
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
}

private fun titleFor(route: Route) = when (route) {
    Route.ROOT -> "Settings"
    Route.CONNECTION -> "Connection"
    Route.DRIVING -> "Driving & Assists"
    Route.PEDALS -> "Pedals"
    Route.PADDLE -> "Paddle Shifter"
    Route.LAYOUT -> "Layout & HUD"
    Route.BUTTONS -> "Macro Buttons"
    Route.APPEARANCE -> "Appearance & Haptics"
    Route.IMPORT_EXPORT -> "Import / Export"
}

@Composable
private fun RootMenu(settings: AppSettings, onNavigate: (Route) -> Unit) {
    SectionTitle("Settings")
    Group {
        NavRow("Connection") { onNavigate(Route.CONNECTION) }
        Divider()
        NavRow("Driving & Assists") { onNavigate(Route.DRIVING) }
        Divider()
        NavRow("Pedal Calibration") { onNavigate(Route.PEDALS) }
        Divider()
        NavRow("Paddle Shifter") { onNavigate(Route.PADDLE) }
    }
    SectionTitle("Interface")
    Group {
        NavRow("Layout & HUD") { onNavigate(Route.LAYOUT) }
        Divider()
        NavRow("Macro Buttons") { onNavigate(Route.BUTTONS) }
        Divider()
        NavRow("Appearance & Haptics") { onNavigate(Route.APPEARANCE) }
    }
    SectionTitle("Data & Export")
    Group {
        NavRow("Import / Export Layout") { onNavigate(Route.IMPORT_EXPORT) }
        Divider()
        NavRow("Reset everything", danger = true) { settings.resetAll() }
    }
}

@Composable
private fun ConnectionScreen(controller: GameController, settings: AppSettings, onClose: () -> Unit) {
    val macs by controller.discovery.macs
    SectionTitle("Nearby receivers")
    Group {
        if (macs.isEmpty()) {
            Text("Scanning…", color = Color.Gray, modifier = Modifier.heightIn(min = 44.dp).padding(vertical = 12.dp))
        } else {
            macs.forEachIndexed { i, mac ->
                if (i > 0) Divider()
                NavRow(mac.name) { controller.connect(mac); onClose() }
            }
        }
    }
    SectionTitle("Connection (manual)")
    Group {
        LabeledField("Receiver IP", settings.host) { settings.host = it }
        Divider()
        StepperRow("Port", settings.port.toString()) { settings.port = (settings.port + it).coerceIn(1, 65535) }
        Divider()
        SwitchRow("Auto-connect on launch", settings.autoConnect) { settings.autoConnect = it }
        Divider()
        DropdownRow("Update rate", listOf("60 Hz", "90 Hz", "120 Hz"),
            when (settings.sendRateHz) { 60 -> 0; 90 -> 1; else -> 2 }) {
            settings.sendRateHz = listOf(60, 90, 120)[it]
        }
    }
}

@Composable
private fun DrivingScreen(controller: GameController, settings: AppSettings) {
    SectionTitle("Assists")
    Group {
        DropdownRow("Assist level", listOf("Off", "Light", "Strong"), settings.assistLevel) {
            settings.assistLevel = it; settings.applyAssistPreset()
        }
        Divider()
        SwitchRow("Auto-recenter (anti-drift)", settings.recenterAssist) { settings.recenterAssist = it }
        Divider()
        SliderRow("Steering smoothing", settings.smoothing, 0f..0.9f, "%.2f") { settings.smoothing = it }
        SliderRow("Steering speed limit", settings.steerRateLimit, 0f..12f, "%.1f") { settings.steerRateLimit = it }
        SliderRow("Throttle ease-off (s)", settings.throttleEase, 0f..0.6f, "%.2f") { settings.throttleEase = it }
    }
    SectionTitle("Steering")
    Group {
        SliderRow("Sensitivity", settings.sensitivity, 0.3f..3f, "%.2f") { settings.sensitivity = it }
        SliderRow("Deadzone", settings.deadzoneDegrees, 0f..10f, "%.1f°") { settings.deadzoneDegrees = it }
        SliderRow("Full-lock angle", settings.maxLockDegrees, 20f..120f, "%.0f°") { settings.maxLockDegrees = it }
        SliderRow("Response curve", settings.steerCurve, 1f..3f, "%.2f") { settings.steerCurve = it }
        Divider()
        SwitchRow("Invert steering", settings.invertSteering) { settings.invertSteering = it }
        Divider()
        SwitchRow("Auto-invert when flipped", settings.autoInvert) { settings.autoInvert = it }
        Divider()
        SwitchRow("Calibrate on launch", settings.calibrateOnLaunch) { settings.calibrateOnLaunch = it }
    }
    ActionButton("Calibrate now — set current position as center") { controller.calibrate() }
}

@Composable
private fun PedalsScreen(settings: AppSettings) {
    SectionTitle("Pedals")
    Group {
        SwitchRow("Swap throttle / brake", settings.invertPedals) { settings.invertPedals = it }
        Divider()
        SliderRow("Brake curve", settings.brakeGamma, 1f..3f, "%.2f") { settings.brakeGamma = it }
        SliderRow("Throttle curve", settings.throttleGamma, 1f..3f, "%.2f") { settings.throttleGamma = it }
    }
    Footnote("Higher brake curve = gentle at first, firmer near the end — precision for trail-braking.")
}

@Composable
private fun PaddleScreen(settings: AppSettings) {
    SectionTitle("Paddle Shifter")
    Group {
        SwitchRow("Back-tap to shift", settings.backTapShiftEnabled) { settings.backTapShiftEnabled = it }
    }
    Footnote("Tap the back of the phone to shift gears. Direction follows throttle: on the gas fires an upshift, off the gas (or braking) fires a downshift.")
    if (settings.backTapShiftEnabled) {
        val labels = (0 until kMaxButtons).map { "Button ${it + 1} — ${settings.buttonLabels.getOrElse(it) { "" }}" }
        SectionTitle("Gear buttons")
        Group {
            DropdownRow("Upshift fires", labels, settings.upshiftButton) { settings.upshiftButton = it }
            Divider()
            DropdownRow("Downshift fires", labels, settings.downshiftButton) { settings.downshiftButton = it }
        }
        SectionTitle("Tuning")
        Group {
            SliderRow("Min sensitivity (still hand)", settings.backTapSensitivity, 1f..8f, "%.1f") { settings.backTapSensitivity = it }
            SliderRow("Sharpness (reject wheel motion)", settings.backTapSharpness, 1.5f..6f, "%.1f") { settings.backTapSharpness = it }
            Divider()
            SwitchRow("Haptic on shift", settings.shiftHaptics) { settings.shiftHaptics = it }
        }
    }
}

@Composable
private fun LayoutScreen(settings: AppSettings, onEditLayout: () -> Unit) {
    ActionButton("Edit layout on screen (drag to arrange)") { onEditLayout() }
    SectionTitle("HUD")
    Group {
        SwitchRow("Show steering wheel", settings.showWheel) { settings.showWheel = it }
        Divider()
        SliderRow("Wheel size", settings.wheelSize, 90f..320f, "%.0f") { settings.wheelSize = it }
        SliderRow("Pedal width", settings.sliderWidth, 60f..160f, "%.0f") { settings.sliderWidth = it }
        SliderRow("Pedal height", settings.sliderHeight, 180f..460f, "%.0f") { settings.sliderHeight = it }
    }
    ActionButton("Reset layout to default") { settings.resetLayout() }
}

@Composable
private fun ButtonsScreen(settings: AppSettings) {
    SectionTitle("Buttons")
    Group {
        StepperRow("Count", settings.buttonCount.toString()) {
            settings.buttonCount = (settings.buttonCount + it).coerceIn(2, kMaxButtons)
        }
    }
    for (i in 0 until settings.buttonCount) {
        SectionTitle("Button ${i + 1}")
        Group {
            LabeledField("Label", settings.buttonLabels.getOrElse(i) { "" }) { settings.setLabel(i, it) }
            Divider()
            DropdownRow("Color", ButtonPalette.names, settings.buttonColors.getOrElse(i) { 0 }) { settings.setColor(i, it) }
            Divider()
            DropdownRow("Behavior", ButtonMode.entries.map { it.label }, settings.buttonModes.getOrElse(i) { 0 }) { settings.setMode(i, it) }
            SliderRow("Size", settings.buttonSize.getOrElse(i) { 72.0 }, 50f..150f, "%.0f") { settings.setSize(i, it) }
        }
    }
}

@Composable
private fun AppearanceScreen(settings: AppSettings) {
    SectionTitle("Look")
    Group {
        DropdownRow("Background", listOf("Black", "Gradient"), settings.backgroundStyle) { settings.backgroundStyle = it }
        Divider()
        DropdownRow("Button shape", listOf("Circle", "Rounded"), settings.buttonShape) { settings.buttonShape = it }
        Divider()
        DropdownRow("Accent / wheel", ButtonPalette.names, settings.accentColorIndex) { settings.accentColorIndex = it }
        Divider()
        DropdownRow("Throttle color", ButtonPalette.names, settings.throttleColorIndex) { settings.throttleColorIndex = it }
        Divider()
        DropdownRow("Brake color", ButtonPalette.names, settings.brakeColorIndex) { settings.brakeColorIndex = it }
        SliderRow("Control opacity", settings.controlOpacity, 0.4f..1f, "%.2f") { settings.controlOpacity = it }
        Divider()
        SwitchRow("Show angle readout", settings.showAngleReadout) { settings.showAngleReadout = it }
    }
    SectionTitle("Feedback")
    Group {
        SwitchRow("Button haptics", settings.hapticsEnabled) { settings.hapticsEnabled = it }
        Divider()
        SwitchRow("Haptic on connect", settings.hapticOnConnect) { settings.hapticOnConnect = it }
        Divider()
        SwitchRow("Telemetry haptics (lockup/slip)", settings.telemetryHaptics) { settings.telemetryHaptics = it }
    }
}

@Composable
private fun ImportExportScreen(settings: AppSettings) {
    val ctx = LocalContext.current
    var json by remember { mutableStateOf("") }
    var msg by remember { mutableStateOf<String?>(null) }

    SectionTitle("Layout Profile JSON")
    OutlinedTextField(
        value = json, onValueChange = { json = it },
        modifier = Modifier.fillMaxWidth().height(160.dp),
        textStyle = TextStyle(fontSize = 12.sp)
    )
    Spacer(Modifier.height(10.dp))
    ActionButton("Generate / Export Layout") { json = settings.exportLayout(); msg = null }
    ActionButton("Copy to Clipboard") {
        val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("GyroWheel layout", json))
        msg = "Copied to clipboard."
    }
    ActionButton("Import / Apply Layout") {
        msg = if (settings.importLayout(json)) "Layout applied." else "Invalid layout JSON."
    }
    msg?.let { Text(it, color = Accent, modifier = Modifier.padding(top = 10.dp)) }
}

// MARK: - Reusable building blocks

@Composable
private fun Header(title: String, onBack: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(Color(0xFF111111))
            .heightIn(min = 56.dp)
            .padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(40.dp).clip(CircleShape).clickable { onBack() },
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Filled.ArrowBack, "Back", tint = Color.White, modifier = Modifier.size(24.dp))
        }
        Spacer(Modifier.width(8.dp))
        Text(title, color = Color.White, style = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Bold))
    }
}

@Composable
private fun Group(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(bottom = 8.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(CardBg)
            .padding(horizontal = 14.dp),
        content = content
    )
}

@Composable
private fun Divider() {
    Box(Modifier.fillMaxWidth().height(1.dp).background(Hairline))
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text.uppercase(), color = Color.Gray,
        style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.6.sp),
        modifier = Modifier.padding(start = 4.dp, top = 18.dp, bottom = 6.dp)
    )
}

@Composable
private fun Footnote(text: String) {
    Text(text, color = Color.Gray, style = TextStyle(fontSize = 12.sp),
        modifier = Modifier.padding(start = 4.dp, top = 6.dp, bottom = 4.dp))
}

@Composable
private fun NavRow(label: String, danger: Boolean = false, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable { onClick() }.heightIn(min = 50.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, color = if (danger) Color(0xFFFF453A) else Color.White, modifier = Modifier.weight(1f))
        if (!danger) Icon(Icons.Filled.KeyboardArrowRight, null, tint = Color.Gray)
    }
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 50.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, color = Color.White, modifier = Modifier.weight(1f).padding(end = 12.dp))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun SliderRow(
    label: String, value: Double, range: ClosedFloatingPointRange<Float>,
    format: String, onChange: (Double) -> Unit
) {
    Column(Modifier.padding(vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(label, color = Color.White, style = TextStyle(fontSize = 14.sp), modifier = Modifier.weight(1f))
            Text(String.format(format, value), color = Accent,
                style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium))
        }
        Slider(
            value = value.toFloat().coerceIn(range.start, range.endInclusive),
            onValueChange = { onChange(it.toDouble()) },
            valueRange = range
        )
    }
}

@Composable
private fun DropdownRow(label: String, options: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().heightIn(min = 50.dp).clickable { expanded = true },
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, color = Color.White, modifier = Modifier.weight(1f).padding(end = 12.dp))
        Box {
            Text(options.getOrElse(selected) { "" }, color = Accent, maxLines = 1, textAlign = TextAlign.End)
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                options.forEachIndexed { i, opt ->
                    DropdownMenuItem(text = { Text(opt) }, onClick = { onSelect(i); expanded = false })
                }
            }
        }
    }
}

@Composable
private fun LabeledField(label: String, value: String, onChange: (String) -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, color = Color.White, modifier = Modifier.weight(1f))
        OutlinedTextField(
            value = value, onValueChange = onChange, singleLine = true,
            modifier = Modifier.width(160.dp)
        )
    }
}

@Composable
private fun StepperRow(label: String, value: String, onStep: (Int) -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("$label: $value", color = Color.White, modifier = Modifier.weight(1f))
        RoundStep("–") { onStep(-1) }
        Spacer(Modifier.width(10.dp))
        RoundStep("+") { onStep(1) }
    }
}

@Composable
private fun RoundStep(label: String, onClick: () -> Unit) {
    Box(
        Modifier.size(34.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.10f)).clickable { onClick() },
        contentAlignment = Alignment.Center
    ) {
        Text(label, color = Color.White, style = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Bold))
    }
}

@Composable
private fun ActionButton(label: String, danger: Boolean = false, onClick: () -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(top = 10.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(if (danger) Color(0xFFFF453A).copy(alpha = 0.18f) else Color.White.copy(alpha = 0.08f))
            .clickable { onClick() }
            .heightIn(min = 50.dp)
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(label, color = if (danger) Color(0xFFFF453A) else Color.White,
            textAlign = TextAlign.Center, style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Medium))
    }
}
