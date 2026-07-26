package com.agentgrid.mobile

import com.agentgrid.mobile.domain.AgentLifecycle
import com.agentgrid.mobile.domain.AgentSource
import com.agentgrid.mobile.domain.TaskFocus
import com.agentgrid.mobile.domain.TaskSnapshot
import org.junit.Assert.assertEquals
import org.junit.Test

class TaskFocusTest {
    @Test
    fun `审批任务覆盖固定的运行任务`() {
        val running = task("running", AgentLifecycle.RUNNING, isPinned = true, updatedAt = 20)
        val approval = task("approval", AgentLifecycle.WAITING_APPROVAL, updatedAt = 10)

        assertEquals("approval", TaskFocus.focused(listOf(running, approval))?.id)
    }

    @Test
    fun `同优先级时选择最近更新任务`() {
        val old = task("old", AgentLifecycle.RUNNING, updatedAt = 10)
        val recent = task("recent", AgentLifecycle.RUNNING, updatedAt = 20)

        assertEquals("recent", TaskFocus.focused(listOf(old, recent))?.id)
    }

    private fun task(
        id: String,
        lifecycle: AgentLifecycle,
        isPinned: Boolean = false,
        updatedAt: Long,
    ) = TaskSnapshot(
        id = id,
        source = AgentSource.CODEX_CLI,
        projectName = id,
        lifecycle = lifecycle,
        startedAt = 0,
        updatedAt = updatedAt,
        isPinned = isPinned,
    )
}

