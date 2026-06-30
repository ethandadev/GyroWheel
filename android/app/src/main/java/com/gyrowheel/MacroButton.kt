package com.gyrowheel

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * A single macro button. In edit mode it ignores presses (the parent handles
 * drag-to-reposition); otherwise it reports presses per its behavior mode.
 */
@Composable
fun MacroButton(
    controller: GameController,
    settings: AppSettings,
    index: Int,
    editing: Boolean
) {
    val haptic = LocalHapticFeedback.current
    val isDown = controller.buttons.getOrElse(index) { false }
    val color = ButtonPalette.color(settings.buttonColors.getOrElse(index) { index })
    val label = settings.buttonLabels.getOrElse(index) { "?" }
    val diameter = (settings.buttonSize.getOrElse(index) { 72.0 }).dp
    val shape: Shape =
        if (settings.buttonShape == 0) CircleShape
        else RoundedCornerShape(diameter * 0.24f)

    val scale by animateFloatAsState(if (isDown) 0.92f else 1f, tween(80), label = "btnScale")

    var mod = Modifier
        .size(diameter)
        .scale(scale)
        .alpha((settings.controlOpacity * (if (editing) 0.9 else 1.0)).toFloat())
        .background(color.copy(alpha = if (isDown) 0.95f else 0.30f), shape)
        .border(3.dp, color, shape)

    if (editing) {
        mod = mod.border(1.5.dp, Color.White.copy(alpha = 0.8f), shape)
    } else {
        mod = mod.pointerInput(index) {
            awaitEachGesture {
                awaitFirstDown(requireUnconsumed = false)
                controller.buttonDown(index)
                if (settings.hapticsEnabled) haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                waitForUpOrCancellation()
                controller.buttonUp(index)
            }
        }
    }

    Box(modifier = mod, contentAlignment = Alignment.Center) {
        Text(
            text = label,
            color = Color.White,
            textAlign = TextAlign.Center,
            maxLines = 1,
            modifier = Modifier.padding(6.dp),
            style = TextStyle(
                fontSize = maxOf(14f, (diameter.value * 0.30f)).sp,
                fontWeight = FontWeight.Black
            )
        )
    }
}
