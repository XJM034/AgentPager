package com.agentgrid.mobile.ui

import com.agentgrid.mobile.TaskSoundTracker
import com.agentgrid.mobile.domain.AgentLifecycle
import com.agentgrid.mobile.domain.AgentSource
import com.agentgrid.mobile.domain.TaskDashboardProjector
import com.agentgrid.mobile.domain.TaskSnapshot
import kotlinx.serialization.json.Json
import org.junit.Assert.*
import org.junit.Test

class OmpTaskPresentationTest {
    @Test
    fun `omp 未输入空闲会话可见且明确标记来源 不制造完成音`() {
        val source = Json.decodeFromString<AgentSource>("\"omp\"")
        assertEquals("omp", source.wireName)
        assertEquals("omp", agentBadge(source))
        assertEquals("Paseo", agentOriginLabel(source))
        val task = TaskSnapshot(
            id = "paseo:omp:one", source = source, projectName = "AgentPager",
            lifecycle = AgentLifecycle.IDLE, startedAt = 1, updatedAt = 2,
        )
        val projection = TaskDashboardProjector.project(
            tasks = listOf(task), preferredFocusedTaskID = null, previous = null, now = 200_000,
        )
        assertEquals(listOf(task), projection.visibleTasks)
        assertEquals(AgentLifecycle.IDLE, projection.focusedTask?.lifecycle)
        assertEquals("空闲", taskActivitySummary(task))
        assertNull(projection.focusedTask?.completedAt)
        assertTrue(task.capabilities.isEmpty())
        val tracker = TaskSoundTracker()
        assertNull(tracker.nextCue(projection.visibleTasks))
        assertNull(tracker.nextCue(projection.visibleTasks))
        assertEquals(AgentSource.UNKNOWN, Json.decodeFromString<AgentSource>("\"future-source\""))
    }
}
