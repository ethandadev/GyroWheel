package com.gyrowheel

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun OnboardingView(controller: GameController, onFinish: () -> Unit) {
    val settings = controller.settings
    val macs by controller.discovery.macs
    var page by remember { mutableIntStateOf(0) }

    Box(
        Modifier
            .fillMaxSize()
            .background(Brush.linearGradient(listOf(Color(0xFF1A1A1A), Color.Black))),
        contentAlignment = Alignment.Center
    ) {
        when (page) {
            0 -> Page(
                Icons.Filled.SportsEsports, "GyroWheel",
                "Turn your phone into a gyroscope steering wheel with throttle, brake, and macro buttons. Tilt to steer; everything streams to your Mac or PC.",
                "Next"
            ) { page = 1 }
            1 -> Page(
                Icons.Filled.Computer, "Start the receiver",
                "On your computer, run the GyroWheel receiver. It shows the IP address. Keep the phone and computer on the same Wi-Fi.",
                "Next"
            ) { page = 2 }
            else -> ConnectStep(controller, settings, macs, onFinish)
        }
    }
}

@Composable
private fun Page(icon: ImageVector, title: String, body: String, cta: String, action: () -> Unit) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp),
        modifier = Modifier.padding(28.dp).widthIn(max = 560.dp)
    ) {
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(64.dp))
        Text(title, color = Color.White, style = TextStyle(fontSize = 34.sp, fontWeight = FontWeight.Bold))
        Text(body, color = Color.White.copy(alpha = 0.75f), style = TextStyle(fontSize = 15.sp),
            modifier = Modifier.padding(horizontal = 24.dp))
        Text(cta, color = Color.White, style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Bold),
            modifier = Modifier
                .background(Color.White.copy(alpha = 0.15f), CircleShape)
                .clickable { action() }
                .padding(horizontal = 40.dp, vertical = 12.dp))
    }
}

@Composable
private fun ConnectStep(
    controller: GameController,
    settings: AppSettings,
    macs: List<DiscoveredMac>,
    onFinish: () -> Unit
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .widthIn(max = 480.dp)
            .padding(24.dp)
            .verticalScroll(rememberScrollState())
    ) {
        Icon(Icons.Filled.Wifi, null, tint = Color(0xFF34C759), modifier = Modifier.size(40.dp))
        Text("Find your receiver", color = Color.White,
            style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Bold))
        Text("Run the GyroWheel receiver on the same Wi-Fi. It appears here automatically.",
            color = Color.White.copy(alpha = 0.7f), style = TextStyle(fontSize = 12.sp),
            modifier = Modifier.padding(horizontal = 24.dp))

        if (macs.isEmpty()) {
            Text("Searching…", color = Color.White.copy(alpha = 0.7f))
        } else {
            macs.forEach { mac ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .background(Color(0xFF34C759).copy(alpha = 0.25f), RoundedCornerShape(10.dp))
                        .clickable { controller.connect(mac); onFinish() }
                        .padding(14.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Filled.Computer, null, tint = Color.White, modifier = Modifier.size(20.dp))
                    Text(mac.name, color = Color.White, maxLines = 1)
                }
            }
        }

        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text("Or enter IP", color = Color.White.copy(alpha = 0.8f))
            Spacer(Modifier.weight(1f))
            OutlinedTextField(
                value = settings.host,
                onValueChange = { settings.host = it },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.width(190.dp)
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Port: ${settings.port}", color = Color.White)
            Spacer(Modifier.width(12.dp))
            StepBtn("–") { if (settings.port > 1) settings.port -= 1 }
            Spacer(Modifier.width(8.dp))
            StepBtn("+") { if (settings.port < 65535) settings.port += 1 }
        }

        Box(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(Color(0xFF34C759))
                .clickable { onFinish() }
                .padding(vertical = 14.dp),
            contentAlignment = Alignment.Center
        ) {
            Text("Start driving", color = Color.White,
                style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Bold))
        }
    }
}

@Composable
private fun StepBtn(label: String, onClick: () -> Unit) {
    Box(
        Modifier
            .size(36.dp)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.12f))
            .clickable { onClick() },
        contentAlignment = Alignment.Center
    ) {
        Text(label, color = Color.White, style = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Bold))
    }
}
