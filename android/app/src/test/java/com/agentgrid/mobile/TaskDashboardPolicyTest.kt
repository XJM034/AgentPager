package com.agentgrid.mobile

import com.agentgrid.mobile.domain.AgentLifecycle
import com.agentgrid.mobile.domain.AgentSource
import com.agentgrid.mobile.domain.TaskDashboardPolicy
import com.agentgrid.mobile.domain.TaskSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TaskDashboardPolicyTest {
    @Test
    fun `活跃任务存在时始终显示任务列表`() {
        val now = 1_000_000L
        val running = task(
            lifecycle = AgentLifecycle.RUNNING,
            updatedAt = now - 10_000,
        )

        assertFalse(TaskDashboardPolicy.shouldShowDashboard(listOf(running), now))
        assertEquals(
            Long.MAX_VALUE,
            TaskDashboardPolicy.timeUntilDashboard(listOf(running), now),
        )
    }

    @Test
    fun `最后一个任务结束九十秒后显示默认态`() {
        val now = 1_000_000L
        val interrupted = task(
            lifecycle = AgentLifecycle.INTERRUPTED,
            updatedAt = now - 90_000,
            completedAt = now - 90_000,
        )

        assertTrue(TaskDashboardPolicy.shouldShowDashboard(listOf(interrupted), now))
    }

    @Test
    fun `终态任务仍在保留期时不影响九十秒倒计时`() {
        val now = 1_000_000L
        val succeeded = task(
            lifecycle = AgentLifecycle.SUCCEEDED,
            updatedAt = now - 30_000,
            completedAt = now - 30_000,
        )

        assertFalse(TaskDashboardPolicy.shouldShowDashboard(listOf(succeeded), now))
        assertEquals(
            60_000L,
            TaskDashboardPolicy.timeUntilDashboard(listOf(succeeded), now),
        )
    }

    @Test
    fun `没有任何任务时立即显示默认态`() {
        assertTrue(TaskDashboardPolicy.shouldShowDashboard(emptyList(), now = 1_000_000L))
    }

    @Test
    fun `新增任务会清除手动显示选择`() {
        val previousStates = mapOf("existing" to false)
        val currentTasks = listOf(
            task(id = "existing", lifecycle = AgentLifecycle.RUNNING, updatedAt = 10),
            task(id = "new", lifecycle = AgentLifecycle.STARTING, updatedAt = 20),
        )

        assertNull(
            TaskDashboardPolicy.manualDashboardOverrideAfterTaskUpdate(
                previousTerminalStates = previousStates,
                currentTasks = currentTasks,
                currentOverride = true,
            ),
        )
    }

    @Test
    fun `同一任务从终态重新启动也视为新任务`() {
        val previousStates = mapOf("task" to true)
        val restarted = task(
            lifecycle = AgentLifecycle.STARTING,
            updatedAt = 20,
        )

        assertNull(
            TaskDashboardPolicy.manualDashboardOverrideAfterTaskUpdate(
                previousTerminalStates = previousStates,
                currentTasks = listOf(restarted),
                currentOverride = true,
            ),
        )
    }

    @Test
    fun `现有任务普通更新不会打断手动切换`() {
        val previousStates = mapOf("task" to false)
        val updated = task(
            lifecycle = AgentLifecycle.RUNNING,
            updatedAt = 20,
        )

        assertEquals(
            true,
            TaskDashboardPolicy.manualDashboardOverrideAfterTaskUpdate(
                previousTerminalStates = previousStates,
                currentTasks = listOf(updated),
                currentOverride = true,
            ),
        )
    }

    @Test
    fun `首次记录任务状态时保留当前显示选择`() {
        val current = task(
            lifecycle = AgentLifecycle.RUNNING,
            updatedAt = 20,
        )

        assertEquals(
            true,
            TaskDashboardPolicy.manualDashboardOverrideAfterTaskUpdate(
                previousTerminalStates = null,
                currentTasks = listOf(current),
                currentOverride = true,
            ),
        )
    }

    private fun task(
        id: String = "task",
        lifecycle: AgentLifecycle,
        updatedAt: Long,
        completedAt: Long? = null,
    ) = TaskSnapshot(
        id = id,
        source = AgentSource.CODEX_CLI,
        projectName = "AgentGrid",
        lifecycle = lifecycle,
        startedAt = updatedAt - 10_000,
        updatedAt = updatedAt,
        completedAt = completedAt,
    )
}
