package com.agentgrid.mobile.render

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.Choreographer
import android.view.View
import com.agentgrid.mobile.domain.AgentActivity
import com.agentgrid.mobile.domain.AgentLifecycle
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.sin

class PixelCoreSurfaceView(context: Context) :
    View(context),
    Choreographer.FrameCallback {

    private val paint = Paint().apply {
        isAntiAlias = false
        style = Paint.Style.FILL
    }

    @Volatile
    private var renderState = PixelRenderState()
    private var lastFrameNanos = 0L
    private var currentFrameNanos = System.nanoTime()

    fun updateState(state: PixelRenderState) {
        if (renderState.lifecycle != state.lifecycle || renderState.activity != state.activity) {
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
        val frameInterval = 1_000_000_000L / targetFps(renderState, frameTimeNanos)
        if (frameTimeNanos - lastFrameNanos >= frameInterval) {
            currentFrameNanos = frameTimeNanos
            postInvalidateOnAnimation()
            lastFrameNanos = frameTimeNanos
        }
        Choreographer.getInstance().postFrameCallback(this)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawColor(BACKGROUND)
        drawGrid(canvas, currentFrameNanos)
    }

    private fun drawGrid(canvas: Canvas, frameTimeNanos: Long) {
        val gridSize = 5
        val side = min(width, height) * 0.62f
        val gap = side * 0.045f
        val cell = (side - gap * (gridSize - 1)) / gridSize
        val left = (width - side) / 2f
        val top = (height - side) / 2f
        val seconds = frameTimeNanos / 1_000_000_000.0
        val tick = (seconds * speed(renderState.lifecycle)).toInt()
        val pulse = (0.78 + sin(seconds * speed(renderState.lifecycle)) * 0.17).toFloat()

        for (row in 0 until gridSize) {
            for (column in 0 until gridSize) {
                val distance = abs(row - 2) + abs(column - 2)
                val active = pixelActive(renderState, row, column, tick)
                val alpha = if (active) pulse else 0.10f
                val x = left + column * (cell + gap)
                val y = top + row * (cell + gap)
                val rect = RectF(x, y, x + cell, y + cell)
                val color = color(renderState.lifecycle, distance)

                // 多层硬边光晕兼容 API 29，同时保留像素边缘。
                paint.color = withAlpha(color, alpha * 0.035f)
                canvas.drawRect(rect.expanded(cell * 0.50f), paint)
                paint.color = withAlpha(color, alpha * 0.085f)
                canvas.drawRect(rect.expanded(cell * 0.25f), paint)
                paint.color = withAlpha(color, alpha)
                canvas.drawRect(rect, paint)
            }
        }
    }

    private fun targetFps(state: PixelRenderState, now: Long): Long {
        val burst = now - state.changedAtNanos < 1_200_000_000L
        return when {
            burst -> 60
            state.lifecycle == AgentLifecycle.IDLE || state.lifecycle == AgentLifecycle.OFFLINE -> 12
            state.lifecycle == AgentLifecycle.STARTING ||
                state.lifecycle == AgentLifecycle.RUNNING ||
                state.lifecycle == AgentLifecycle.WAITING_APPROVAL ||
                state.lifecycle == AgentLifecycle.WAITING_ANSWER -> 60
            else -> 30
        }
    }

    private fun speed(lifecycle: AgentLifecycle): Double = when (lifecycle) {
        AgentLifecycle.WAITING_APPROVAL, AgentLifecycle.WAITING_ANSWER -> 8.0
        AgentLifecycle.FAILED -> 12.0
        AgentLifecycle.SUCCEEDED -> 7.0
        AgentLifecycle.RUNNING -> 5.0
        else -> 2.0
    }

    private fun pixelActive(
        state: PixelRenderState,
        row: Int,
        column: Int,
        tick: Int,
    ): Boolean = when (state.lifecycle) {
        AgentLifecycle.WAITING_APPROVAL ->
            row == tick.mod(5) || column == tick.mod(5)
        AgentLifecycle.WAITING_ANSWER ->
            (row + column + tick).mod(3) != 0
        AgentLifecycle.FAILED ->
            row == column || row + column == 4
        AgentLifecycle.SUCCEEDED ->
            row >= 2 && column <= row
        AgentLifecycle.STARTING ->
            abs(row - 2) + abs(column - 2) <= tick.mod(5)
        AgentLifecycle.INTERRUPTED ->
            row == 2
        AgentLifecycle.RUNNING ->
            activityPattern(state.activity, row, column, tick)
        AgentLifecycle.OFFLINE, AgentLifecycle.IDLE ->
            abs(row - 2) + abs(column - 2) <= 1
    }

    private fun activityPattern(
        activity: AgentActivity?,
        row: Int,
        column: Int,
        tick: Int,
    ): Boolean = when (activity) {
        AgentActivity.READING -> row == tick.mod(5) || row == (tick + 1).mod(5)
        AgentActivity.SEARCHING, AgentActivity.BROWSING ->
            abs(row - 2) + abs(column - 2) == tick.mod(5)
        AgentActivity.EDITING -> (row * 5 + column + tick).mod(3) != 0
        AgentActivity.TESTING -> (row + column + tick).mod(2) == 0
        AgentActivity.DELEGATING -> row == column || row + column == 4
        AgentActivity.EXECUTING -> column == tick.mod(5)
        AgentActivity.THINKING, null -> (row * 5 + column + tick).mod(4) != 0
    }

    private fun color(lifecycle: AgentLifecycle, distance: Int): Int = when (lifecycle) {
        AgentLifecycle.WAITING_APPROVAL -> Color.rgb(255, 159, 67)
        AgentLifecycle.WAITING_ANSWER -> Color.rgb(244, 201, 93)
        AgentLifecycle.FAILED -> Color.rgb(255, 98, 110)
        AgentLifecycle.SUCCEEDED -> Color.rgb(87, 214, 141)
        AgentLifecycle.INTERRUPTED -> Color.rgb(132, 139, 153)
        AgentLifecycle.OFFLINE -> Color.rgb(72, 78, 91)
        else -> PALETTE[min(distance, PALETTE.lastIndex)]
    }

    private fun withAlpha(color: Int, alpha: Float): Int =
        Color.argb((alpha.coerceIn(0f, 1f) * 255).toInt(), Color.red(color), Color.green(color), Color.blue(color))

    private fun RectF.expanded(value: Float): RectF =
        RectF(left - value, top - value, right + value, bottom + value)

    private companion object {
        const val BACKGROUND = 0xFF090B10.toInt()
        val PALETTE = intArrayOf(
            Color.rgb(255, 116, 79),
            Color.rgb(166, 120, 255),
            Color.rgb(78, 140, 255),
            Color.rgb(53, 199, 180),
        )
    }
}
