package com.agentgrid.mobile.render

import com.agentgrid.mobile.domain.AgentActivity
import com.agentgrid.mobile.domain.AgentLifecycle
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

data class PixelSample(
    val index: Int,
    val intensity: Float,
    val offsetX: Float,
    val offsetY: Float,
    val scale: Float,
)

data class PixelGlowLayer(
    val opacity: Float,
    val blurRadius: Float,
)

object PixelMotionEngine {
    fun sample(
        lifecycle: AgentLifecycle,
        activity: AgentActivity?,
        elapsed: Double,
    ): List<PixelSample> = (0 until 9).map { index ->
        val row = (index / 3 - 1).toDouble()
        val column = (index % 3 - 1).toDouble()
        val phase = index * 0.73
        val values = motion(lifecycle, activity, row, column, phase, max(0.0, elapsed))
        PixelSample(
            index = index,
            intensity = values.intensity.coerceIn(0.0, 1.0).toFloat(),
            offsetX = values.offsetX.coerceIn(-1.0, 1.0).toFloat(),
            offsetY = values.offsetY.coerceIn(-1.0, 1.0).toFloat(),
            scale = values.scale.coerceIn(0.62, 1.28).toFloat(),
        )
    }

    /** 每个亮格独立计算三层 Bloom；暗格返回三层零透明度。 */
    fun glowLayers(intensity: Float, burst: Float): List<PixelGlowLayer> {
        val energy = (intensity * burst).coerceIn(0f, 1.4f)
        return listOf(
            PixelGlowLayer(energy * 0.46f, 2.8f),
            PixelGlowLayer(energy * 0.22f, 6.5f),
            PixelGlowLayer(energy * 0.09f, 12f),
        )
    }

    fun burst(lifecycle: AgentLifecycle, elapsed: Double): Float {
        if (elapsed >= 1.2) return 1f
        return when (lifecycle) {
            AgentLifecycle.WAITING_APPROVAL,
            AgentLifecycle.WAITING_ANSWER,
            AgentLifecycle.SUCCEEDED,
            AgentLifecycle.FAILED,
            -> (1 + 0.4 * easeOutCubic(1 - elapsed / 1.2)).toFloat()
            else -> 1f
        }
    }

    private data class Values(
        val intensity: Double,
        val offsetX: Double,
        val offsetY: Double,
        val scale: Double,
    )

    private fun motion(
        lifecycle: AgentLifecycle,
        activity: AgentActivity?,
        row: Double,
        column: Double,
        phase: Double,
        t: Double,
    ): Values = when (lifecycle) {
        AgentLifecycle.OFFLINE -> Values(0.16, 0.0, 0.0, 0.82)
        AgentLifecycle.IDLE -> {
            val breath = wave(t * 1.25 + phase * 0.28)
            Values(0.22 + breath * 0.26, 0.0, -0.05 * breath, 0.88 + breath * 0.08)
        }
        AgentLifecycle.STARTING -> {
            val rise = easeOutCubic(min(1.0, t / 0.55))
            val orbit = t * 4.8 + phase
            Values(
                0.28 + 0.72 * rise,
                cos(orbit) * (1 - rise) * 0.65,
                sin(orbit) * (1 - rise) * 0.65,
                0.70 + 0.30 * rise,
            )
        }
        AgentLifecycle.WAITING_APPROVAL -> {
            val pulse = wave(t * 5.2 + phase * 0.18)
            val outward = 0.10 + 0.16 * pulse
            Values(0.46 + 0.54 * pulse, column * outward, row * outward, 0.92 + 0.14 * pulse)
        }
        AgentLifecycle.WAITING_ANSWER -> {
            val pulse = wave(t * 4.3 + phase * 0.62)
            Values(0.34 + 0.66 * pulse, sin(t * 2.8 + phase) * 0.12, -0.12 * pulse, 0.88 + 0.16 * pulse)
        }
        AgentLifecycle.SUCCEEDED -> {
            val progress = min(1.0, t / 1.2)
            val explosion = sin(progress * PI) * 0.64
            val settled = if (progress >= 1) 1.0 else 0.72 + 0.28 * easeOutCubic(progress)
            Values(settled, column * explosion, row * explosion, 0.82 + 0.26 * sin(progress * PI))
        }
        AgentLifecycle.FAILED -> {
            val progress = min(1.0, t)
            val jitter = (1 - progress) * sin(t * 55 + phase) * 0.16
            val fall = easeInCubic(progress) * (0.26 + max(0.0, row) * 0.10)
            val broken = if (progress >= 1) (((phase * 10).toInt() % 3) - 1) * 0.10 else jitter
            Values(
                if (progress >= 1) 0.64 else 0.42 + wave(t * 10 + phase) * 0.58,
                broken,
                fall,
                1 - progress * 0.14,
            )
        }
        AgentLifecycle.INTERRUPTED -> {
            val progress = min(1.0, t / 0.8)
            Values(
                0.62 - progress * 0.24,
                sin(t * 5 + phase) * 0.10 * (1 - progress),
                0.0,
                0.96 - progress * 0.08,
            )
        }
        AgentLifecycle.RUNNING -> activityMotion(activity, row, column, phase, t)
    }

    private fun activityMotion(
        activity: AgentActivity?,
        row: Double,
        column: Double,
        phase: Double,
        t: Double,
    ): Values = when (activity) {
        AgentActivity.READING -> {
            val scan = wave(t * 4.2 - row * 1.2 + phase * 0.12)
            Values(0.22 + 0.78 * scan, column * 0.04, -0.16 + 0.32 * scan, 0.88 + 0.14 * scan)
        }
        AgentActivity.SEARCHING, AgentActivity.BROWSING -> {
            val orbit = t * 3.8 + phase
            val energy = wave(orbit)
            Values(0.20 + 0.80 * energy, cos(orbit) * 0.24, sin(orbit) * 0.24, 0.86 + 0.16 * energy)
        }
        AgentActivity.EDITING -> {
            val exchange = sin(t * 4.6 + row * 1.35 + phase * 0.16)
            val energy = wave(t * 5.0 + phase * 0.72)
            Values(0.24 + 0.76 * energy, exchange * 0.42, -exchange * 0.08, 0.86 + 0.18 * energy)
        }
        AgentActivity.EXECUTING -> {
            val stream = positiveModulo(t * 2.4 + ((phase * 10).toInt() % 3) / 3.0, 1.0)
            val energy = sin(PI * stream)
            Values(0.24 + 0.76 * energy, column * 0.05, 0.48 - stream * 0.96, 0.86 + 0.17 * energy)
        }
        AgentActivity.TESTING -> {
            val scan = wave(t * 5.4 + (row + column) * 1.35)
            Values(0.18 + 0.82 * scan, column * 0.10 * scan, row * 0.10 * scan, 0.84 + 0.18 * scan)
        }
        AgentActivity.DELEGATING -> {
            val split = sin(t * 3.5 + phase * 0.44)
            Values(0.28 + 0.72 * wave(t * 3.9 + phase), column * 0.30 * split, row * 0.22 * split, 0.88 + 0.12 * abs(split))
        }
        AgentActivity.THINKING, null -> {
            val orbit = t * 3.25 + phase
            val energy = wave(t * 3.9 + phase * 0.74)
            Values(0.20 + 0.80 * energy, cos(orbit) * 0.22, sin(orbit) * 0.22, 0.86 + 0.16 * energy)
        }
    }

    private fun wave(value: Double): Double = (sin(value) + 1) / 2

    private fun positiveModulo(value: Double, divisor: Double): Double {
        val result = value % divisor
        return if (result >= 0) result else result + divisor
    }

    private fun easeOutCubic(value: Double): Double =
        1 - (1 - value.coerceIn(0.0, 1.0)).pow(3)

    private fun easeInCubic(value: Double): Double =
        value.coerceIn(0.0, 1.0).pow(3)
}
