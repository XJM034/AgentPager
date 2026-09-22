package com.agentgrid.mobile.ui

import com.agentgrid.mobile.ArcadeSoundCue
import com.agentgrid.mobile.ScreenBrightnessPolicy
import com.agentgrid.mobile.domain.StateSnapshotPayload
import com.agentgrid.mobile.domain.TaskDashboardProjection
import java.io.File
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
    fun `真实 Bridge 轮次快照复用焦点完成收起 提醒去重静音和亮度`() {
        // Captured by paseoTurnProgressReachesPhone through the actual phone WebSocket.
        val fixture = listOf(File("../../protocol/fixtures/paseo-omp-turns.json"),
            File("../protocol/fixtures/paseo-omp-turns.json")).first { it.exists() }
        val snapshots = Json { ignoreUnknownKeys = true }
            .decodeFromString<List<StateSnapshotPayload>>(fixture.readText())
        val tracker = TaskSoundTracker()
        val expected = listOf(null, ArcadeSoundCue.TASK_ACKNOWLEDGE, null,
            ArcadeSoundCue.TASK_COMPLETE, ArcadeSoundCue.TASK_ACKNOWLEDGE, null)
        var projection: TaskDashboardProjection? = null
        val identity = snapshots.first().tasks.single().id
        snapshots.forEachIndexed { index, snapshot ->
            val task = snapshot.tasks.single()
            assertEquals(identity, task.id)
            projection = TaskDashboardProjector.project(snapshot, projection, task.updatedAt)
            assertEquals(identity, projection?.focusedTaskID)
            assertEquals(expected[index], tracker.nextCue(projection!!.visibleTasks))
            assertNull(tracker.nextCue(projection!!.visibleTasks))
            assertEquals(if (task.lifecycle == AgentLifecycle.RUNNING) 0.8f else 0.2f,
                ScreenBrightnessPolicy.brightnessFor(task.lifecycle, 0.8f, 0.2f))
        }
        val completed = snapshots[3]
        val at = completed.tasks.single().completedAt!!
        val settled = TaskDashboardProjector.project(completed, null, at + 90_001)
        assertTrue(settled.dashboardVisible)
        val resumed = TaskDashboardProjector.project(snapshots[4], settled,
            snapshots[4].tasks.single().updatedAt)
        assertFalse(resumed.dashboardVisible)
        assertEquals("正在思考", taskActivitySummary(snapshots[1].tasks.single()))
        assertEquals("读取文件", taskActivitySummary(snapshots[2].tasks.single()))
        assertEquals("编辑文件", taskActivitySummary(snapshots[5].tasks.single()))

        val muted = TaskSoundTracker()
        snapshots.forEach { snapshot ->
            assertNull(muted.nextCue(snapshot.tasks.map { it.copy(isMuted = true) }))
        }
        assertNull(muted.nextCue(snapshots.last().tasks))
        val disabled = TaskSoundTracker()
        snapshots.forEach { assertNull(disabled.nextCue(it.tasks, soundEnabled = false)) }
        assertNull(disabled.nextCue(snapshots.last().tasks, soundEnabled = true))
        val historical = TaskSoundTracker()
        assertNull(historical.nextCue(completed.tasks))
    }

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
