package com.agentgrid.mobile

import com.agentgrid.mobile.domain.AgentLifecycle
import com.agentgrid.mobile.domain.SubagentSnapshot
import org.junit.Assert.assertEquals
import org.junit.Test

class SubagentSnapshotTest {
    @Test
    fun `运行中的子代理使用当前时间计算耗时`() {
        val subagent = subagent(AgentLifecycle.RUNNING, updatedAt = 2_000)

        assertEquals(4_000, subagent.elapsedAt(now = 5_000))
    }

    @Test
    fun `完成的子代理停止累计耗时`() {
        val subagent = subagent(AgentLifecycle.SUCCEEDED, updatedAt = 2_500)

        assertEquals(1_500, subagent.elapsedAt(now = 9_000))
    }

    private fun subagent(
        lifecycle: AgentLifecycle,
        updatedAt: Long,
    ) = SubagentSnapshot(
        id = "child-1",
        path = "/root/protocol_v2",
        displayName = "Protocol v2",
        lifecycle = lifecycle,
        startedAt = 1_000,
        updatedAt = updatedAt,
    )
}
