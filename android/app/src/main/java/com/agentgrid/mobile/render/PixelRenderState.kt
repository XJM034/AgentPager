package com.agentgrid.mobile.render

import com.agentgrid.mobile.domain.AgentActivity
import com.agentgrid.mobile.domain.AgentLifecycle

data class PixelRenderState(
    val lifecycle: AgentLifecycle = AgentLifecycle.IDLE,
    val activity: AgentActivity? = null,
    val revision: Long = 0,
    val changedAtNanos: Long = System.nanoTime(),
) {
    fun requiresMotionRestart(previous: PixelRenderState): Boolean =
        lifecycle != previous.lifecycle ||
            activity != previous.activity ||
            revision != previous.revision
}
