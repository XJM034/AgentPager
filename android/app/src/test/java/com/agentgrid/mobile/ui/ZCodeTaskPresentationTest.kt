package com.agentgrid.mobile.ui

import com.agentgrid.mobile.domain.AgentActivity
import com.agentgrid.mobile.domain.AgentLifecycle
import com.agentgrid.mobile.domain.AgentSource
import com.agentgrid.mobile.domain.TaskSnapshot
import org.junit.Assert.assertEquals
import org.junit.Test

class ZCodeTaskPresentationTest {
    @Test
    fun `ZCode 复用现有徽标活动和空闲状态语言`() {
        assertEquals("ZCode", agentBadge(AgentSource.ZCODE))
        assertEquals("ZCode", agentOriginLabel(AgentSource.ZCODE))
        assertEquals("正在思考", activityText(AgentActivity.THINKING))
        assertEquals("正在协作", activityText(AgentActivity.DELEGATING))
        assertEquals("空闲", statusText(AgentLifecycle.IDLE))

        val starting = zcodeTask(
            lifecycle = AgentLifecycle.STARTING,
            activity = AgentActivity.THINKING,
        )
        val thinking = zcodeTask(
            lifecycle = AgentLifecycle.RUNNING,
            activity = AgentActivity.THINKING,
        )
        assertEquals("正在启动", taskActivitySummary(starting))
        assertEquals("正在思考", taskActivitySummary(thinking))
    }

    private fun zcodeTask(
        lifecycle: AgentLifecycle,
        activity: AgentActivity?,
    ) = TaskSnapshot(
        id = "zcode-session-1",
        source = AgentSource.ZCODE,
        projectName = "AgentPager",
        lifecycle = lifecycle,
        activity = activity,
        startedAt = 1,
        updatedAt = 2,
    )
}
