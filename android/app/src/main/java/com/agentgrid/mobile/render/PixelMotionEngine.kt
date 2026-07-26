package com.agentgrid.mobile.render

import com.agentgrid.mobile.domain.AgentActivity
import com.agentgrid.mobile.domain.AgentLifecycle
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
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
    const val TRANSITION_DURATION_SECONDS = 0.24
    const val INNER_GLOW_OPACITY = 0.68f
    const val MIDDLE_GLOW_OPACITY = 0.36f
    const val OUTER_GLOW_OPACITY = 0.17f
    const val INNER_GLOW_RADIUS = 3.8f
    const val MIDDLE_GLOW_RADIUS = 9f
    const val OUTER_GLOW_RADIUS = 18f

    private val spiralOrder = intArrayOf(4, 1, 2, 5, 8, 7, 6, 3, 0)
    private val perimeterOrder = intArrayOf(0, 1, 2, 5, 8, 7, 6, 3)
    private val successOrder = intArrayOf(6, 7, 5, 2)
    private val thinkingOrder = intArrayOf(0, 2, 8, 6)

    fun sample(
        lifecycle: AgentLifecycle,
        activity: AgentActivity?,
        elapsed: Double,
    ): List<PixelSample> = (0 until 9).map { index ->
        val row = (index / 3 - 1).toDouble()
        val column = (index % 3 - 1).toDouble()
        val phase = index * 0.73
        val values = motion(
            lifecycle = lifecycle,
            activity = activity,
            index = index,
            row = row,
            column = column,
            phase = phase,
            t = max(0.0, elapsed),
        )
        PixelSample(
            index = index,
            intensity = values.intensity.coerceIn(0.0, 1.0).toFloat(),
            offsetX = values.offsetX.coerceIn(-1.0, 1.0).toFloat(),
            offsetY = values.offsetY.coerceIn(-1.0, 1.0).toFloat(),
            scale = values.scale.coerceIn(0.62, 1.28).toFloat(),
        )
    }

    /**
     * 每个亮格独立计算三层 Bloom。先压掉暗格能量，再加强中高亮格，
     * 让负空间保持干净，同时让真正发光的像素更像硬件灯珠。
     */
    fun glowLayers(intensity: Float, burst: Float): List<PixelGlowLayer> {
        val energy = glowEnergy(intensity, burst)
        return listOf(
            PixelGlowLayer(energy * INNER_GLOW_OPACITY, INNER_GLOW_RADIUS),
            PixelGlowLayer(energy * MIDDLE_GLOW_OPACITY, MIDDLE_GLOW_RADIUS),
            PixelGlowLayer(energy * OUTER_GLOW_OPACITY, OUTER_GLOW_RADIUS),
        )
    }

    /** 绘制热路径只计算能量，不创建 Bloom 图层对象。 */
    fun glowEnergy(intensity: Float, burst: Float): Float {
        val visibleIntensity = ((intensity - 0.06f) / 0.94f).coerceIn(0f, 1f)
        return (visibleIntensity * burst * 1.18f).coerceIn(0f, 1.45f)
    }

    /** 保持原有状态帧率；完成类状态播放完一次后不再请求空帧。 */
    fun targetFps(
        lifecycle: AgentLifecycle,
        elapsed: Double,
        motionEnabled: Boolean,
    ): Long = when {
        !motionEnabled -> 0
        lifecycle == AgentLifecycle.STARTING && elapsed >= 1.2 -> 0
        (
            lifecycle == AgentLifecycle.SUCCEEDED ||
                lifecycle == AgentLifecycle.INTERRUPTED
            ) && elapsed >= 1.2 -> 0
        lifecycle == AgentLifecycle.IDLE || lifecycle == AgentLifecycle.OFFLINE -> 30
        else -> 60
    }

    /**
     * 为不同设备的 VSync 时钟保留 1 毫秒容差，避免理论 60 FPS 被误节流为 30 FPS。
     */
    fun shouldRenderFrame(
        lastFrameNanos: Long,
        frameTimeNanos: Long,
        fps: Long,
    ): Boolean {
        if (fps <= 0) return false
        if (lastFrameNanos == 0L) return true
        val frameInterval = 1_000_000_000L / fps
        val tolerance = min(1_000_000L, frameInterval / 10)
        return frameTimeNanos - lastFrameNanos >= frameInterval - tolerance
    }

    fun burst(lifecycle: AgentLifecycle, elapsed: Double): Float {
        if (elapsed >= 1.2) return 1f
        return when (lifecycle) {
            AgentLifecycle.WAITING_APPROVAL,
            AgentLifecycle.WAITING_ANSWER,
            AgentLifecycle.SUCCEEDED,
            -> (1 + 0.4 * easeOutCubic(1 - elapsed / 1.2)).toFloat()
            else -> 1f
        }
    }

    /** 状态切换使用强减速曲线，快速响应并平稳落位。 */
    fun transitionProgress(elapsed: Double): Float {
        val linear = (elapsed / TRANSITION_DURATION_SECONDS).coerceIn(0.0, 1.0)
        return easeOutQuint(linear).toFloat()
    }

    /** 对两组 3×3 样本逐格插值，供 View 在连续状态切换时复用。 */
    fun blendSamples(
        from: List<PixelSample>,
        to: List<PixelSample>,
        progress: Float,
    ): List<PixelSample> {
        val amount = progress.coerceIn(0f, 1f)
        if (amount <= 0f) return from
        if (amount >= 1f) return to
        return to.mapIndexed { position, target ->
            val start = from.getOrNull(position)
                ?.takeIf { it.index == target.index }
                ?: target
            PixelSample(
                index = target.index,
                intensity = lerp(start.intensity, target.intensity, amount),
                offsetX = lerp(start.offsetX, target.offsetX, amount),
                offsetY = lerp(start.offsetY, target.offsetY, amount),
                scale = lerp(start.scale, target.scale, amount),
            )
        }
    }

    /** 关闭系统动画时选择有辨识度的静止帧，而不是退回没有语义的满格。 */
    fun reducedMotionElapsed(lifecycle: AgentLifecycle): Double = when (lifecycle) {
        AgentLifecycle.STARTING -> 0.82
        AgentLifecycle.SUCCEEDED,
        AgentLifecycle.INTERRUPTED,
        -> 1.2
        else -> 0.68
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
        index: Int,
        row: Double,
        column: Double,
        phase: Double,
        t: Double,
    ): Values = when (lifecycle) {
        AgentLifecycle.OFFLINE -> {
            val cycle = positiveModulo(t, 3.6)
            val pulse = max(
                pulse(cycle, center = 0.12, radius = 0.10),
                pulse(cycle, center = 0.34, radius = 0.10) * 0.42,
            )
            val belongsToCross = abs(abs(row) - abs(column)) < 0.01
            Values(
                if (belongsToCross) 0.20 + 0.24 * pulse else 0.025,
                if (row == 0.0) column * 0.08 else 0.0,
                if (belongsToCross) -0.035 * pulse else 0.04,
                if (belongsToCross) 0.80 + 0.08 * pulse else 0.66,
            )
        }
        AgentLifecycle.IDLE -> {
            val distance = abs(row) + abs(column)
            val breath = wave(t * 1.12)
            val base = when (distance) {
                0.0 -> 0.58
                1.0 -> 0.18
                else -> 0.035
            }
            val amplitude = when (distance) {
                0.0 -> 0.32
                1.0 -> 0.18
                else -> 0.045
            }
            Values(
                base + amplitude * breath,
                column * 0.015 * breath,
                row * 0.015 * breath,
                0.76 + (0.08 + 0.12 * breath) / (distance + 1),
            )
        }
        AgentLifecycle.STARTING -> {
            val order = spiralOrder.indexOf(index).coerceAtLeast(0)
            val localProgress = ((t - order * 0.055) / 0.24).coerceIn(0.0, 1.0)
            val ignition = easeOutQuint(localProgress)
            val spark = pulse(t, center = order * 0.055 + 0.13, radius = 0.13)
            val settle = easeOutCubic(((t - 0.66) / 0.30).coerceIn(0.0, 1.0))
            val belongsToCore = abs(row) + abs(column) <= 1
            val settledIntensity = if (belongsToCore) 0.72 else 0.12
            val settledScale = if (belongsToCore) 0.96 else 0.74
            val ignitionIntensity = 0.08 + 0.58 * ignition + 0.34 * spark
            val ignitionScale = 0.68 + 0.28 * ignition + 0.08 * spark
            Values(
                lerp(ignitionIntensity, settledIntensity, settle),
                -column * 0.54 * (1 - ignition),
                -row * 0.54 * (1 - ignition),
                lerp(ignitionScale, settledScale, settle),
            )
        }
        AgentLifecycle.WAITING_APPROVAL -> {
            val cycle = positiveModulo(t, 1.55)
            val beat = max(
                pulse(cycle, center = 0.13, radius = 0.12),
                pulse(cycle, center = 0.39, radius = 0.11) * 0.76,
            )
            val centerImpact = max(
                pulse(cycle, center = 0.19, radius = 0.12),
                pulse(cycle, center = 0.45, radius = 0.11) * 0.76,
            )
            val isCenter = row == 0.0 && column == 0.0
            Values(
                if (isCenter) 0.24 + 0.76 * centerImpact else 0.34 + 0.66 * beat,
                if (isCenter) 0.0 else -column * 0.16 * beat,
                if (isCenter) 0.0 else -row * 0.16 * beat,
                0.88 + 0.16 * if (isCenter) centerImpact else beat,
            )
        }
        AgentLifecycle.WAITING_ANSWER -> {
            val cycle = positiveModulo(t, 1.75)
            val columnOrder = (column + 1).roundToInt()
            val dot = pulse(
                cycle,
                center = 0.20 + columnOrder * 0.27,
                radius = 0.18,
            )
            val belongsToEllipsis = row == 0.0
            Values(
                if (belongsToEllipsis) 0.28 + 0.72 * dot else 0.025 + 0.12 * dot,
                0.0,
                if (belongsToEllipsis) -0.10 * dot else -row * 0.14 * dot,
                if (belongsToEllipsis) 0.86 + 0.18 * dot else 0.68 + 0.12 * dot,
            )
        }
        AgentLifecycle.SUCCEEDED -> {
            val burstProgress = min(1.0, t / 0.30)
            val explosion = sin(burstProgress * PI) * 0.58
            val resolve = easeOutQuint(((t - 0.16) / 0.48).coerceIn(0.0, 1.0))
            val pathOrder = successOrder.indexOf(index)
            val belongsToCheck = pathOrder >= 0
            val draw = if (belongsToCheck) {
                easeOutQuint(((t - 0.32 - pathOrder * 0.055) / 0.18).coerceIn(0.0, 1.0))
            } else {
                0.0
            }
            val flourish = if (belongsToCheck) {
                pulse(t, center = 0.78 + pathOrder * 0.035, radius = 0.10)
            } else {
                0.0
            }
            Values(
                if (belongsToCheck) {
                    0.20 + 0.74 * draw + 0.06 * flourish
                } else {
                    0.82 * (1 - resolve) + 0.035
                },
                column * explosion * (1 - resolve),
                row * explosion * (1 - resolve),
                if (belongsToCheck) 0.82 + 0.16 * draw + 0.08 * flourish else 0.70,
            )
        }
        AgentLifecycle.INTERRUPTED -> {
            val progress = easeOutQuint(min(1.0, t / 0.42))
            val severed = (row == 0.0 && column == 0.0) ||
                (row == 1.0 && column == -1.0)
            val flicker = if (t < 0.34) 0.30 + 0.70 * wave(t * 34 + phase) else 0.0
            val settledIntensity = if (severed) {
                0.025
            } else if (row == 0.0) {
                0.22
            } else {
                0.42
            }
            val settledX = if (row == 0.0) {
                if (column < 0) -0.18 else 0.18
            } else {
                column * 0.035
            }
            val settledY = if (row == 0.0) 0.12 else row * 0.02
            val jitter = sin(t * 58 + phase) * 0.22 * (1 - progress)
            Values(
                flicker * (1 - progress) + settledIntensity * progress,
                jitter + settledX * progress,
                settledY * progress,
                (0.92 + 0.08 * wave(t * 9 + phase)) * (1 - progress) +
                    (if (severed) 0.68 else 0.86) * progress,
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
            val scanPosition = -1.0 + positiveModulo(t * 0.72, 1.0) * 2.0
            val scan = (1 - abs(row - scanPosition) / 0.82).coerceIn(0.0, 1.0)
            Values(
                0.10 + 0.90 * scan,
                column * 0.035 * scan,
                -0.08 + 0.16 * scan,
                0.84 + 0.18 * scan,
            )
        }
        AgentActivity.SEARCHING -> {
            val order = perimeterOrder.indexOf((row + 1).roundToInt() * 3 + (column + 1).roundToInt())
            val travel = positiveModulo(t * 0.48, 1.0)
            val energy = if (order >= 0) {
                cyclicPulse(travel, order / perimeterOrder.size.toDouble(), 0.17)
            } else {
                0.18 + 0.12 * wave(t * 2.2)
            }
            Values(
                0.08 + 0.92 * energy,
                column * 0.08 * energy,
                row * 0.08 * energy,
                0.80 + 0.22 * energy,
            )
        }
        AgentActivity.BROWSING -> {
            val pagePosition = 1.25 - positiveModulo(t * 0.62, 1.0) * 2.5
            val band = (1 - abs(row - pagePosition) / 0.72).coerceIn(0.0, 1.0)
            val columnLead = 1 - (column + 1) * 0.10
            Values(
                0.10 + 0.90 * band * columnLead,
                0.0,
                -0.18 * band,
                0.82 + 0.18 * band,
            )
        }
        AgentActivity.EDITING -> {
            val stroke = wave(t * 5.0 - row * 1.18)
            val caret = pulse(positiveModulo(t, 1.12), center = 0.14, radius = 0.12)
            val isCaret = column == 0.0
            val energy = if (isCaret) max(caret, stroke * 0.56) else stroke
            Values(
                0.12 + 0.88 * energy,
                if (isCaret) 0.0 else -column * (0.08 + 0.10 * stroke),
                -row * 0.035 * stroke,
                0.84 + 0.18 * energy,
            )
        }
        AgentActivity.EXECUTING -> {
            val stream = positiveModulo(t * 2.4 + ((phase * 10).toInt() % 3) / 3.0, 1.0)
            val energy = sin(PI * stream)
            Values(0.24 + 0.76 * energy, column * 0.05, 0.48 - stream * 0.96, 0.86 + 0.17 * energy)
        }
        AgentActivity.TESTING -> {
            val cycle = positiveModulo(t, 1.46)
            val diagonal = row + column + 2
            val sweepPosition = (cycle / 0.94).coerceIn(0.0, 1.0) * 4
            val scan = (1 - abs(diagonal - sweepPosition) / 0.82).coerceIn(0.0, 1.0)
            val verdict = pulse(cycle, center = 1.15, radius = 0.15)
            val energy = max(scan, verdict)
            Values(
                0.08 + 0.92 * energy,
                column * 0.08 * scan,
                row * 0.08 * scan,
                0.82 + 0.20 * energy,
            )
        }
        AgentActivity.DELEGATING -> {
            val cycle = positiveModulo(t, 1.34)
            val distance = (abs(row) + abs(column)) / 2
            val branch = pulse(
                cycle,
                center = 0.14 + distance * 0.62,
                radius = 0.19,
            )
            val isCenter = distance == 0.0
            Values(
                (if (isCenter) 0.48 else 0.10) + (if (isCenter) 0.42 else 0.90) * branch,
                column * 0.20 * branch,
                row * 0.14 * branch,
                0.82 + 0.20 * branch,
            )
        }
        AgentActivity.THINKING, null -> {
            val index = (row + 1).roundToInt() * 3 + (column + 1).roundToInt()
            val order = thinkingOrder.indexOf(index)
            val travel = positiveModulo(t * 0.34, 1.0)
            val cornerEnergy = if (order >= 0) {
                cyclicPulse(travel, order / thinkingOrder.size.toDouble(), 0.22)
            } else {
                0.0
            }
            val isCenter = row == 0.0 && column == 0.0
            val energy = if (isCenter) 0.46 + 0.18 * wave(t * 1.8) else cornerEnergy
            Values(
                if (isCenter || order >= 0) 0.08 + 0.92 * energy else 0.035,
                if (order >= 0) -column * 0.08 * cornerEnergy else 0.0,
                if (order >= 0) -row * 0.08 * cornerEnergy else 0.0,
                0.78 + 0.24 * energy,
            )
        }
    }

    private fun wave(value: Double): Double = (sin(value) + 1) / 2

    private fun pulse(value: Double, center: Double, radius: Double): Double {
        val distance = abs(value - center)
        if (distance >= radius) return 0.0
        return (cos(PI * distance / radius) + 1) / 2
    }

    private fun cyclicPulse(value: Double, center: Double, radius: Double): Double {
        val directDistance = abs(value - center)
        val distance = min(directDistance, 1 - directDistance)
        if (distance >= radius) return 0.0
        return (cos(PI * distance / radius) + 1) / 2
    }

    private fun positiveModulo(value: Double, divisor: Double): Double {
        val result = value % divisor
        return if (result >= 0) result else result + divisor
    }

    private fun easeOutCubic(value: Double): Double =
        1 - (1 - value.coerceIn(0.0, 1.0)).pow(3)

    private fun easeOutQuint(value: Double): Double =
        1 - (1 - value.coerceIn(0.0, 1.0)).pow(5)

    private fun lerp(from: Float, to: Float, progress: Float): Float =
        from + (to - from) * progress

    private fun lerp(from: Double, to: Double, progress: Double): Double =
        from + (to - from) * progress
}
