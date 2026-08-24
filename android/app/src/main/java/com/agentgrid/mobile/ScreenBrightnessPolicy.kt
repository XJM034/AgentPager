package com.agentgrid.mobile

import com.agentgrid.mobile.domain.AgentLifecycle

internal object ScreenBrightnessPolicy {
    const val DEFAULT_ACTIVE_BRIGHTNESS = 1f
    const val DEFAULT_IDLE_BRIGHTNESS = 1f
    const val MIN_BRIGHTNESS = 0.05f
    const val MAX_BRIGHTNESS = 1f

    private val activeLifecycles = setOf(
        AgentLifecycle.STARTING,
        AgentLifecycle.RUNNING,
        AgentLifecycle.WAITING_APPROVAL,
        AgentLifecycle.WAITING_ANSWER,
    )

    fun sanitizeActiveBrightness(value: Float): Float {
        if (!value.isFinite()) return DEFAULT_ACTIVE_BRIGHTNESS
        return value.coerceIn(MIN_BRIGHTNESS, MAX_BRIGHTNESS)
    }

    fun sanitizeIdleBrightness(value: Float): Float {
        if (!value.isFinite()) return DEFAULT_IDLE_BRIGHTNESS
        return value.coerceIn(MIN_BRIGHTNESS, MAX_BRIGHTNESS)
    }

    fun brightnessFor(
        lifecycle: AgentLifecycle?,
        activeBrightness: Float,
        idleBrightness: Float,
    ): Float = if (lifecycle in activeLifecycles) {
        sanitizeActiveBrightness(activeBrightness)
    } else {
        sanitizeIdleBrightness(idleBrightness)
    }
}
