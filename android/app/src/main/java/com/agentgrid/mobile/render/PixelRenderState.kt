package com.agentgrid.mobile.render

import com.agentgrid.mobile.domain.AgentActivity
import com.agentgrid.mobile.domain.AgentLifecycle

data class PixelRenderState(
    val lifecycle: AgentLifecycle = AgentLifecycle.IDLE,
    val activity: AgentActivity? = null,
    val changedAtNanos: Long = System.nanoTime(),
)

