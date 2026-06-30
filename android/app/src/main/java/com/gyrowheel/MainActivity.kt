package com.gyrowheel

import android.content.res.Configuration
import android.os.Bundle
import android.view.Surface
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

class MainActivity : ComponentActivity() {
    private val controller: GameController by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }

        updateFlip()

        setContent {
            GyroWheelTheme {
                ContentView(controller)
            }
        }
    }

    private fun updateFlip() {
        val rotation = if (android.os.Build.VERSION.SDK_INT >= 30) display?.rotation
        else @Suppress("DEPRECATION") windowManager.defaultDisplay.rotation
        controller.setLandscapeFlipped(rotation == Surface.ROTATION_270)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        updateFlip()
    }

    override fun onResume() {
        super.onResume()
        controller.start()
        controller.discovery.start()
    }

    override fun onPause() {
        super.onPause()
        controller.stop()
        controller.discovery.stop()
    }
}

@Composable
fun GyroWheelTheme(content: @Composable () -> Unit) {
    val scheme = darkColorScheme(
        primary = Color(0xFF34C759),
        background = Color.Black,
        surface = Color(0xFF1A1A1A),
        onPrimary = Color.White,
        onBackground = Color.White,
        onSurface = Color.White
    )
    MaterialTheme(colorScheme = scheme, content = content)
}
