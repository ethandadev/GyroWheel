package com.gyrowheel

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Column
import kotlinx.coroutines.delay
import kotlin.math.cos
import kotlin.math.sin

@Composable
fun ContentView(controller: GameController) {
    val settings = controller.settings
    var showSettings by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf(false) }
    var showOnboarding by remember { mutableStateOf(false) }
    val macs by controller.discovery.macs

    LaunchedEffect(Unit) {
        showOnboarding = !settings.hasOnboarded
        if (settings.autoConnect && !controller.status.isConnected) controller.connect()
        if (settings.calibrateOnLaunch) {
            delay(800)
            controller.calibrate()
        }
    }

    val bg = if (settings.backgroundStyle == 1) {
        Modifier.background(
            Brush.linearGradient(listOf(Color(0xFF1A1A1A), Color.Black))
        )
    } else {
        Modifier.background(Color.Black)
    }

    Box(Modifier.fillMaxSize().then(bg)) {
        // Play surface
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val wDp = maxWidth
            val hDp = maxHeight
            val wPx = constraints.maxWidth.toFloat()
            val hPx = constraints.maxHeight.toFloat()

            for (i in 0 until settings.buttonCount) {
                val dia = settings.buttonSize.getOrElse(i) { 72.0 }.dp
                ElementBox(
                    nx = settings.buttonPosX.getOrElse(i) { 0.1 },
                    ny = settings.buttonPosY.getOrElse(i) { 0.3 },
                    containerW = wDp, containerH = hDp, elemW = dia, elemH = dia,
                    editing = editing, wPx = wPx, hPx = hPx,
                    onMove = { x, y -> settings.setPosX(i, x); settings.setPosY(i, y) }
                ) {
                    MacroButton(controller, settings, i, editing)
                }
            }

            if (settings.showWheel) {
                val wheel = settings.wheelSize.dp
                ElementBox(
                    nx = settings.wheelPosX, ny = settings.wheelPosY,
                    containerW = wDp, containerH = hDp, elemW = wheel, elemH = wheel + 24.dp,
                    editing = editing, wPx = wPx, hPx = hPx,
                    onMove = { x, y -> settings.wheelPosX = x; settings.wheelPosY = y }
                ) {
                    WheelHUD(controller, settings)
                }
            }

            val sliderW = settings.sliderWidth.dp
            val sliderH = settings.sliderHeight.dp
            ElementBox(
                nx = settings.sliderPosX, ny = settings.sliderPosY,
                containerW = wDp, containerH = hDp, elemW = sliderW, elemH = sliderH,
                editing = editing, wPx = wPx, hPx = hPx,
                onMove = { x, y -> settings.sliderPosX = x; settings.sliderPosY = y }
            ) {
                Box(Modifier.size(sliderW, sliderH)) {
                    ThrottleBrakeSlider(controller, settings, editing)
                }
            }
        }

        // Top bar
        Column(Modifier.fillMaxWidth().padding(16.dp)) {
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                StatusPill(controller)
                ConnectButton(controller)
                Spacer(Modifier.weight(1f))
                IconChip(if (editing) Icons.Filled.Check else Icons.Filled.Edit) { editing = !editing }
                IconChip(Icons.Filled.Settings) { showSettings = true }
            }
            if (!controller.status.isConnected && macs.isNotEmpty()) {
                Row(
                    Modifier.padding(top = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Filled.Wifi, null, tint = Color(0xFF34C759), modifier = Modifier.size(16.dp))
                    macs.forEach { mac ->
                        Text(
                            mac.name,
                            color = Color.White,
                            maxLines = 1,
                            style = TextStyle(fontSize = 11.sp),
                            modifier = Modifier
                                .background(Color(0xFF34C759).copy(alpha = 0.25f), CircleShape)
                                .clickable { controller.connect(mac) }
                                .padding(horizontal = 10.dp, vertical = 5.dp)
                        )
                    }
                }
            }
        }

        // Edit bar
        if (editing) {
            Row(
                Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 14.dp)
                    .background(Color.Black.copy(alpha = 0.6f), CircleShape)
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Drag to arrange", color = Color.White.copy(alpha = 0.85f), style = TextStyle(fontSize = 12.sp))
                Text("Reset", color = Color.White, style = TextStyle(fontSize = 12.sp),
                    modifier = Modifier
                        .background(Color.White.copy(alpha = 0.12f), CircleShape)
                        .clickable { settings.resetLayout() }
                        .padding(horizontal = 12.dp, vertical = 6.dp))
                Text("Done", color = Color.White, style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold),
                    modifier = Modifier
                        .background(Color(0xFF34C759), CircleShape)
                        .clickable { editing = false }
                        .padding(horizontal = 14.dp, vertical = 6.dp))
            }
        }
    }

    if (showOnboarding) {
        OnboardingView(controller) {
            settings.hasOnboarded = true
            showOnboarding = false
        }
    }

    if (showSettings) {
        SettingsScreen(
            controller = controller,
            onClose = { showSettings = false },
            onEditLayout = { editing = true; showSettings = false }
        )
    }
}

@Composable
private fun ElementBox(
    nx: Double, ny: Double,
    containerW: Dp, containerH: Dp,
    elemW: Dp, elemH: Dp,
    editing: Boolean, wPx: Float, hPx: Float,
    onMove: (Double, Double) -> Unit,
    content: @Composable () -> Unit
) {
    val latestX by rememberUpdatedState(nx)
    val latestY by rememberUpdatedState(ny)
    val x = (containerW * nx.toFloat()) - elemW / 2f
    val y = (containerH * ny.toFloat()) - elemH / 2f

    var mod = Modifier.offset(x, y)
    if (editing) {
        mod = mod.pointerInput(Unit) {
            detectDragGestures { change, drag ->
                change.consume()
                val newX = (latestX + drag.x / wPx).coerceIn(0.03, 0.97)
                val newY = (latestY + drag.y / hPx).coerceIn(0.06, 0.94)
                onMove(newX, newY)
            }
        }
    }
    Box(mod) { content() }
}

@Composable
private fun StatusPill(controller: GameController) {
    val connected = controller.status.isConnected
    Row(
        Modifier
            .background(Color.White.copy(alpha = 0.06f), CircleShape)
            .padding(horizontal = 10.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.size(10.dp).background(if (connected) Color(0xFF34C759) else Color.Red, CircleShape))
        Column {
            Text(controller.status.text, color = Color.White,
                style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold))
            Text(
                controller.targetLabel + if (connected) "  ↑${controller.txRate}Hz" else "",
                color = Color.Gray, maxLines = 1, style = TextStyle(fontSize = 10.sp)
            )
        }
    }
}

@Composable
private fun ConnectButton(controller: GameController) {
    val connected = controller.status.isConnected
    Text(
        if (connected) "Disconnect" else "Connect",
        color = Color.White,
        style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold),
        modifier = Modifier
            .background(
                if (connected) Color.Red.copy(alpha = 0.85f) else Color(0xFF34C759).copy(alpha = 0.85f),
                CircleShape
            )
            .clickable { if (connected) controller.disconnect() else controller.connect() }
            .padding(horizontal = 14.dp, vertical = 8.dp)
    )
}

@Composable
private fun IconChip(icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit) {
    Box(
        Modifier
            .background(Color.White.copy(alpha = 0.06f), CircleShape)
            .clickable { onClick() }
            .padding(8.dp),
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(22.dp))
    }
}

/** Steering-wheel graphic + live angle readout. */
@Composable
private fun WheelHUD(controller: GameController, settings: AppSettings) {
    val size = settings.wheelSize.dp
    val accent = ButtonPalette.color(settings.accentColorIndex)
    val angle = (controller.steer * settings.maxLockDegrees).toFloat()

    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Canvas(
            Modifier
                .size(size)
                .rotate(angle)
        ) {
            val r = this.size.minDimension / 2f
            val c = Offset(this.size.width / 2f, this.size.height / 2f)
            val stroke = r * 0.12f
            // Outer rim
            drawCircle(color = accent, radius = r - stroke / 2f, center = c, style = Stroke(width = stroke))
            // Hub
            drawCircle(color = accent, radius = r * 0.18f, center = c)
            // Spokes (left, right, down)
            for (deg in listOf(0.0, 120.0, 240.0)) {
                val rad = Math.toRadians(deg + 90.0)
                val end = Offset(c.x + (r - stroke) * cos(rad).toFloat(), c.y + (r - stroke) * sin(rad).toFloat())
                drawLine(color = accent, start = c, end = end, strokeWidth = stroke * 0.8f)
            }
        }
        if (settings.showAngleReadout) {
            Text(
                String.format("%.0f°  (%+.2f)", controller.steer * settings.maxLockDegrees, controller.steer),
                color = Color.White.copy(alpha = 0.85f),
                style = TextStyle(fontSize = 12.sp)
            )
        }
    }
}
