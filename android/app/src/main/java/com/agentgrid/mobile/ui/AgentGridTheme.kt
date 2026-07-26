package com.agentgrid.mobile.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import com.agentgrid.mobile.R

val PixelFontFamily = FontFamily(
    Font(R.font.silkscreen_regular, FontWeight.Normal),
    Font(R.font.silkscreen_bold, FontWeight.Bold),
)

object AgentGridColors {
    val Background = Color(0xFF090B10)
    val Surface = Color(0xFF10141B)
    val SurfaceRaised = Color(0xFF171C25)
    val Text = Color(0xFFE7E9E4)
    val Muted = Color(0xFF818894)
    val Blue = Color(0xFF4E8CFF)
    val Cyan = Color(0xFF35C7B4)
    val Violet = Color(0xFFA678FF)
    val Orange = Color(0xFFFF9F43)
    val Amber = Color(0xFFF4C95D)
    val Green = Color(0xFF57D68D)
    val Red = Color(0xFFFF626E)
}

private val darkColors = darkColorScheme(
    primary = AgentGridColors.Amber,
    onPrimary = AgentGridColors.Background,
    secondary = AgentGridColors.Blue,
    onSecondary = AgentGridColors.Text,
    background = AgentGridColors.Background,
    onBackground = AgentGridColors.Text,
    surface = AgentGridColors.Surface,
    onSurface = AgentGridColors.Text,
    error = AgentGridColors.Red,
    onError = AgentGridColors.Background,
)

@Composable
fun AgentGridTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColors,
        content = content,
    )
}
