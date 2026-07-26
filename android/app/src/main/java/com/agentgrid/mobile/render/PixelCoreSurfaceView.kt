package com.agentgrid.mobile.render

import android.content.Context
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.Choreographer
import android.view.View
import com.agentgrid.mobile.domain.AgentActivity
import com.agentgrid.mobile.domain.AgentLifecycle
import kotlin.math.min

/**
 * 任务行左侧的 3×3 像素核心。
 *
 * 每个格子拥有独立的连续强度、位移、缩放和三层 Bloom。主体始终保持硬边，
 * 只有光晕层启用模糊，避免整枚图形变成一团发光贴图。
 */
class PixelCoreSurfaceView(context: Context) :
    View(context),
    Choreographer.FrameCallback {

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private var renderState = PixelRenderState()
    private var currentFrameNanos = System.nanoTime()
    private var lastFrameNanos = 0L

    init {
        setLayerType(LAYER_TYPE_SOFTWARE, null)
        setWillNotDraw(false)
    }

    fun updateState(state: PixelRenderState) {
        if (
            renderState.lifecycle != state.lifecycle ||
            renderState.activity != state.activity
        ) {
            renderState = state.copy(changedAtNanos = System.nanoTime())
            postInvalidateOnAnimation()
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        Choreographer.getInstance().postFrameCallback(this)
    }

    override fun onDetachedFromWindow() {
        Choreographer.getInstance().removeFrameCallback(this)
        super.onDetachedFromWindow()
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (!isAttachedToWindow) return
        val elapsed = (frameTimeNanos - renderState.changedAtNanos)
            .coerceAtLeast(0L) / 1_000_000_000.0
        val fps = targetFps(renderState.lifecycle, elapsed)
        if (fps > 0) {
            val frameInterval = 1_000_000_000L / fps
            if (frameTimeNanos - lastFrameNanos >= frameInterval) {
                currentFrameNanos = frameTimeNanos
                postInvalidateOnAnimation()
                lastFrameNanos = frameTimeNanos
            }
        }
        Choreographer.getInstance().postFrameCallback(this)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val elapsed = (currentFrameNanos - renderState.changedAtNanos)
            .coerceAtLeast(0L) / 1_000_000_000.0
        val samples = PixelMotionEngine.sample(
            renderState.lifecycle,
            renderState.activity,
            elapsed,
        )
        val burst = PixelMotionEngine.burst(renderState.lifecycle, elapsed)
        val color = PixelPalette.color(renderState.lifecycle, renderState.activity)

        val side = min(width, height) * 0.62f
        val step = side / 3f
        val cell = step * 0.58f
        val centerX = width / 2f
        val centerY = height / 2f

        samples.forEach { sample ->
            val row = sample.index / 3 - 1
            val column = sample.index % 3 - 1
            val x = centerX + (column + sample.offsetX) * step
            val y = centerY + (row + sample.offsetY) * step
            val cellSide = cell * sample.scale
            val rect = RectF(
                x - cellSide / 2,
                y - cellSide / 2,
                x + cellSide / 2,
                y + cellSide / 2,
            )

            // 每个亮格分别绘制外、中、内三层 Bloom，暗格不会发光。
            PixelMotionEngine.glowLayers(sample.intensity, burst)
                .asReversed()
                .forEach { layer ->
                    if (layer.opacity <= 0f) return@forEach
                    paint.isAntiAlias = true
                    paint.maskFilter = BlurMaskFilter(
                        layer.blurRadius * resources.displayMetrics.density,
                        BlurMaskFilter.Blur.NORMAL,
                    )
                    paint.color = color.withAlpha(layer.opacity)
                    canvas.drawRect(rect, paint)
                }

            paint.maskFilter = null
            paint.isAntiAlias = false
            paint.color = color.withAlpha(0.10f)
            canvas.drawRect(rect, paint)
            paint.color = color.withAlpha(0.22f + sample.intensity * 0.78f)
            canvas.drawRect(rect, paint)
        }
    }

    private fun targetFps(lifecycle: AgentLifecycle, elapsed: Double): Long = when {
        lifecycle in setOf(
            AgentLifecycle.SUCCEEDED,
            AgentLifecycle.FAILED,
            AgentLifecycle.INTERRUPTED,
        ) && elapsed >= 1.2 -> 0
        lifecycle == AgentLifecycle.IDLE || lifecycle == AgentLifecycle.OFFLINE -> 30
        else -> 60
    }

    private fun Int.withAlpha(alpha: Float): Int = Color.argb(
        (alpha.coerceIn(0f, 1f) * 255).toInt(),
        Color.red(this),
        Color.green(this),
        Color.blue(this),
    )
}

object PixelPalette {
    fun color(lifecycle: AgentLifecycle, activity: AgentActivity?): Int = when (lifecycle) {
        AgentLifecycle.WAITING_APPROVAL -> Color.rgb(253, 186, 74)
        AgentLifecycle.WAITING_ANSWER -> Color.rgb(250, 204, 21)
        AgentLifecycle.SUCCEEDED -> Color.rgb(74, 222, 128)
        AgentLifecycle.FAILED -> Color.rgb(251, 113, 133)
        AgentLifecycle.INTERRUPTED, AgentLifecycle.OFFLINE -> Color.rgb(100, 116, 139)
        AgentLifecycle.IDLE -> Color.rgb(94, 234, 212)
        AgentLifecycle.STARTING -> Color.rgb(167, 139, 250)
        AgentLifecycle.RUNNING -> when (activity) {
            AgentActivity.READING,
            AgentActivity.SEARCHING,
            AgentActivity.BROWSING,
            -> Color.rgb(94, 234, 212)
            AgentActivity.EDITING -> Color.rgb(129, 140, 248)
            AgentActivity.EXECUTING -> Color.rgb(251, 146, 60)
            AgentActivity.TESTING -> Color.rgb(96, 165, 250)
            AgentActivity.DELEGATING,
            AgentActivity.THINKING,
            null,
            -> Color.rgb(167, 139, 250)
        }
    }
}
