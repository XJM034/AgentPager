package com.agentgrid.mobile.ui

import com.agentgrid.mobile.domain.AgentLifecycle
import com.agentgrid.mobile.domain.TaskSnapshot

internal fun shouldShowTokenSummary(task: TaskSnapshot): Boolean =
    task.lifecycle == AgentLifecycle.SUCCEEDED
