package com.agentgrid.mobile

import com.agentgrid.mobile.domain.AgentLifecycle
import com.agentgrid.mobile.domain.AgentSource
import com.agentgrid.mobile.domain.TaskOrdering
import com.agentgrid.mobile.domain.TaskSnapshot
import org.junit.Assert.assertEquals
import org.junit.Test

class TaskOrderingTest {
    @Test
    fun `运行中的任务排在其他状态之前`() {
        val approval = task("approval", AgentLifecycle.WAITING_APPROVAL, updatedAt = 30)
        val failed = task("failed", AgentLifecycle.FAILED, updatedAt = 20)
        val running = task("running", AgentLifecycle.RUNNING, updatedAt = 10)

        val orderedIDs = TaskOrdering.sorted(listOf(approval, failed, running)).map { it.id }

        assertEquals(listOf("running", "approval", "failed"), orderedIDs)
    }

    @Test
    fun `多个运行任务按更新时间从新到旧排列`() {
        val old = task("old", AgentLifecycle.RUNNING, updatedAt = 10)
        val recent = task("recent", AgentLifecycle.RUNNING, updatedAt = 20)

        val orderedIDs = TaskOrdering.sorted(listOf(old, recent)).map { it.id }

        assertEquals(listOf("recent", "old"), orderedIDs)
    }

    @Test
    fun `已完成任务排在其他状态之后`() {
        val succeeded = task("succeeded", AgentLifecycle.SUCCEEDED, updatedAt = 30)
        val starting = task("starting", AgentLifecycle.STARTING, updatedAt = 20)
        val approval = task("approval", AgentLifecycle.WAITING_APPROVAL, updatedAt = 10)

        val orderedIDs = TaskOrdering.sorted(listOf(succeeded, starting, approval)).map { it.id }

        assertEquals(listOf("approval", "starting", "succeeded"), orderedIDs)
    }

    @Test
    fun `其他状态保留注意力优先级顺序`() {
        val starting = task("starting", AgentLifecycle.STARTING, updatedAt = 30)
        val approval = task("approval", AgentLifecycle.WAITING_APPROVAL, updatedAt = 10)

        val orderedIDs = TaskOrdering.sorted(listOf(starting, approval)).map { it.id }

        assertEquals(listOf("approval", "starting"), orderedIDs)
    }

    private fun task(
        id: String,
        lifecycle: AgentLifecycle,
        updatedAt: Long,
    ) = TaskSnapshot(
        id = id,
        source = AgentSource.CODEX_CLI,
        projectName = id,
        lifecycle = lifecycle,
        startedAt = 0,
        updatedAt = updatedAt,
    )
}
