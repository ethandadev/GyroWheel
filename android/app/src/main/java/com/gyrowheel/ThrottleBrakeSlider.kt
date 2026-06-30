package com.gyrowheel

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Vertical throttle/brake control with spring-back-to-center. Fills the parent frame. */
@Composable
fun ThrottleBrakeSlider(
    controller: GameController,
    settings: AppSettings,
    editing: Boolean
) {
    val density = LocalDensity.current
    val thumbRadiusPx = with(density) { 26.dp.toPx() }
    var sizePx by remember { mutableStateOf(IntSize.Zero) }

    val thrColor = ButtonPalette.color(settings.throttleColorIndex)
    val brkColor = ButtonPalette.color(settings.brakeColorIndex)

    fun apply(y: Float) {
        val h = sizePx.height.toFloat()
        if (h <= 0) return
        val center = h / 2f
        val travel = (center - thumbRadiusPx).coerceAtLeast(1f)
        val v = ((center - y) / travel).coerceIn(-1f, 1f).toDouble()
        if (v >= 0) controller.setThrottleBrake(v, 0.0) else controller.setThrottleBrake(0.0, -v)
    }

    var mod = Modifier
        .fillMaxSize()
        .alpha(settings.controlOpacity.toFloat())
        .onSizeChanged { sizePx = it }

    if (!editing) {
        mod = mod.pointerInput(Unit) {
            detectDragGestures(
                onDragStart = { apply(it.y) },
                onDrag = { change, _ -> apply(change.position.y) },
                onDragEnd = { controller.setThrottleBrake(0.0, 0.0) },
                onDragCancel = { controller.setThrottleBrake(0.0, 0.0) }
            )
        }
    }

    Box(modifier = mod, contentAlignment = Alignment.Center) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val w = size.width
            val h = size.height
            val center = h / 2f
            val travel = (center - thumbRadiusPx).coerceAtLeast(1f)
            val trackW = minOf(w, with(density) { 54.dp.toPx() })
            val left = (w - trackW) / 2f
            val thr = controller.throttle.toFloat()
            val brk = controller.brake.toFloat()
            val value = (thr - brk)
            val thumbY = center - value * travel
            val r = CornerRadius(trackW / 2f, trackW / 2f)

            // Track
            drawRoundRect(
                color = Color.White.copy(alpha = 0.08f),
                topLeft = Offset(left, 0f),
                size = Size(trackW, h),
                cornerRadius = r
            )
            // Throttle fill (from center upward)
            val thrH = thr * travel
            if (thrH > 0) drawRoundRect(
                color = thrColor.copy(alpha = 0.6f),
                topLeft = Offset(left, center - thrH),
                size = Size(trackW, thrH),
                cornerRadius = r
            )
            // Brake fill (from center downward)
            val brkH = brk * travel
            if (brkH > 0) drawRoundRect(
                color = brkColor.copy(alpha = 0.6f),
                topLeft = Offset(left, center),
                size = Size(trackW, brkH),
                cornerRadius = r
            )
            // Center line
            drawRect(
                color = Color.White.copy(alpha = 0.4f),
                topLeft = Offset(left, center - 1f),
                size = Size(trackW, 2f)
            )
            // Thumb
            drawCircle(color = Color.White, radius = thumbRadiusPx, center = Offset(w / 2f, thumbY))
        }

        Text("THR", color = Color.White.copy(alpha = 0.6f),
            style = TextStyle(fontSize = 10.sp),
            modifier = Modifier.align(Alignment.TopCenter))
        Text("BRK", color = Color.White.copy(alpha = 0.6f),
            style = TextStyle(fontSize = 10.sp),
            modifier = Modifier.align(Alignment.BottomCenter))
    }
}
