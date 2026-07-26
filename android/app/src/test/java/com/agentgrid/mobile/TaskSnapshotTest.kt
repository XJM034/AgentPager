package com.agentgrid.mobile

import com.agentgrid.mobile.domain.AgentLifecycle
import com.agentgrid.mobile.domain.AgentSource
import com.agentgrid.mobile.domain.TaskSnapshot
import org.junit.Assert.assertEquals
import org.junit.Test

class TaskSnapshotTest {
    @Test
    fun `运行中的任务使用当前时间计算耗时`() {
        val task = task(AgentLifecycle.RUNNING, updatedAt = 2_000)

        assertEquals(4_000, task.elapsedAt(now = 5_000))
    }

    @Test
    fun `完成的任务使用完成时间冻结耗时`() {
        val task = task(
            lifecycle = AgentLifecycle.SUCCEEDED,
            updatedAt = 3_000,
            completedAt = 2_500,
        )

        assertEquals(1_500, task.elapsedAt(now = 9_000))
    }

    private fun task(
        lifecycle: AgentLifecycle,
        updatedAt: Long,
        completedAt: Long? = null,
    ) = TaskSnapshot(
        id = "task-1",
        source = AgentSource.CODEX_CLI,
        projectName = "AgentGrid",
        lifecycle = lifecycle,
        startedAt = 1_000,
        updatedAt = updatedAt,
        completedAt = completedAt,
    )
}
