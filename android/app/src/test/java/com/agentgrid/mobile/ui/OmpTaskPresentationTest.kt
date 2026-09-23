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
    fun `原生 Codex 的 Paseo 标签只附加到已关联会话且不改变 OMP`() {
        val fixture = listOf(File("../../protocol/fixtures/paseo-native-codex-origin.json"),
            File("../protocol/fixtures/paseo-native-codex-origin.json")).first { it.exists() }
        val snapshots = Json { ignoreUnknownKeys = true }
            .decodeFromString<List<StateSnapshotPayload>>(fixture.readText())
        val native = snapshots[1].tasks.single { it.isPaseoSession }
        assertEquals("Codex", agentBadge(native.source))
        assertEquals("Terminal · Paseo", taskOriginLabel(native))
        assertEquals("Terminal", taskOriginLabel(snapshots[1].tasks.single { it.id == "standalone-codex" }))
        assertEquals("Paseo", taskOriginLabel(snapshots[1].tasks.single { it.source == AgentSource.OMP }))
        assertEquals("Terminal", taskOriginLabel(snapshots[2].tasks.single { it.id == native.id }))
        assertEquals(4, snapshots[2].tasks.size)
        // Old Bridge payloads omit the flag entirely.
        val legacy = Json { ignoreUnknownKeys = true }.decodeFromString<TaskSnapshot>(
            """{"id":"legacy","source":"codexCLI","projectName":"Legacy","lifecycle":"idle","startedAt":0,"updatedAt":0}""",
        )
        assertFalse(legacy.isPaseoSession)
        assertEquals("Terminal", taskOriginLabel(legacy))
    }

    @Test
    fun `关闭恢复的真实 Bridge 输出不会恢复已解决等待或手机操作`() {
        val fixture = listOf(File("../../protocol/fixtures/paseo-omp-configuration.json"),
            File("../protocol/fixtures/paseo-omp-configuration.json")).first { it.exists() }
        val snapshots = Json { ignoreUnknownKeys = true }
            .decodeFromString<List<StateSnapshotPayload>>(fixture.readText())
        val identity = snapshots.first().tasks.single().id
        val expected = listOf(AgentLifecycle.IDLE, AgentLifecycle.RUNNING,
            AgentLifecycle.WAITING_APPROVAL, AgentLifecycle.WAITING_APPROVAL, AgentLifecycle.RUNNING)
        snapshots.forEachIndexed { index, snapshot ->
            val projection = TaskDashboardProjector.project(snapshot, null, snapshot.tasks.single().updatedAt)
            val task = projection.visibleTasks.single()
            assertEquals(identity, task.id)
            assertEquals(expected[index], task.lifecycle)
            assertTrue(task.capabilities.isEmpty())
            assertNull(task.completedAt)
            assertNull(TaskSoundTracker().nextCue(snapshot.tasks))
        }
        assertFalse(taskActivitySummary(snapshots.last().tasks.single()).contains("审批"))
    }

    @Test
    fun `实际恢复快照保留分支身份清理归档且不制造完成提醒`() {
        val fixture = listOf(File("../../protocol/fixtures/paseo-omp-recovery.json"),
            File("../protocol/fixtures/paseo-omp-recovery.json")).first { it.exists() }
        val snapshots = Json { ignoreUnknownKeys = true }
            .decodeFromString<List<StateSnapshotPayload>>(fixture.readText())
        val identity = snapshots.first().tasks.single().id
        val tracker = TaskSoundTracker()
        var projection: TaskDashboardProjection? = null
        snapshots.forEach { snapshot ->
            projection = TaskDashboardProjector.project(snapshot, projection, snapshot.tasks.maxOf { it.updatedAt })
            assertTrue(projection!!.visibleTasks.any { it.id == identity })
            assertNotEquals(ArcadeSoundCue.TASK_COMPLETE, tracker.nextCue(snapshot.tasks))
            assertNull(tracker.nextCue(snapshot.tasks))
            assertTrue(snapshot.tasks.all { it.completedAt == null && it.capabilities.isEmpty() })
        }
        assertEquals(2, snapshots[1].tasks.map { it.id }.toSet().size)
        assertEquals(listOf(identity), snapshots[2].tasks.map { it.id })
        assertNull(TaskSoundTracker().nextCue(snapshots.last().tasks))
    }

    @Test
    fun `真实 Bridge 请求与异常快照展示安全文案且沿用提醒静音`() {
        val fixture = listOf(File("../../protocol/fixtures/paseo-omp-attention.json"),
            File("../protocol/fixtures/paseo-omp-attention.json")).first { it.exists() }
        val snapshots = Json { ignoreUnknownKeys = true }
            .decodeFromString<List<StateSnapshotPayload>>(fixture.readText())
        val tracker = TaskSoundTracker()
        val expected = listOf(null, ArcadeSoundCue.TASK_ACKNOWLEDGE,
            ArcadeSoundCue.INPUT_REQUIRED, ArcadeSoundCue.INPUT_REQUIRED, ArcadeSoundCue.INPUT_REQUIRED,
            ArcadeSoundCue.TASK_ACKNOWLEDGE, ArcadeSoundCue.TASK_INTERRUPTED,
            ArcadeSoundCue.TASK_ACKNOWLEDGE, ArcadeSoundCue.INPUT_REQUIRED, ArcadeSoundCue.TASK_INTERRUPTED)
        val texts = mapOf(2 to "请回到 Paseo 处理工具审批", 3 to "请回到 Paseo 处理待确认事项",
            6 to "本轮执行失败，请回到 Paseo 查看", 8 to "请回到 Paseo 处理待确认事项", 9 to "本轮已取消")
        var projection: TaskDashboardProjection? = null
        snapshots.forEachIndexed { index, snapshot ->
            val task = snapshot.tasks.single()
            assertTrue(task.capabilities.isEmpty())
            projection = TaskDashboardProjector.project(snapshot, projection, task.updatedAt)
            assertEquals(task.id, projection?.focusedTaskID)
            assertEquals(expected[index], tracker.nextCue(projection!!.visibleTasks))
            assertNull(tracker.nextCue(projection!!.visibleTasks))
            texts[index]?.let { assertEquals(it, taskActivitySummary(task)) }
        }
        val muted = TaskSoundTracker()
        val disabled = TaskSoundTracker()
        snapshots.forEach {
            assertNull(muted.nextCue(it.tasks.map { task -> task.copy(isMuted = true) }))
            assertNull(disabled.nextCue(it.tasks, soundEnabled = false))
        }
        assertNull(disabled.nextCue(snapshots.last().tasks, soundEnabled = true))
        assertNull(muted.nextCue(snapshots.last().tasks))
        assertNull(TaskSoundTracker().nextCue(snapshots[2].tasks))
    }

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
