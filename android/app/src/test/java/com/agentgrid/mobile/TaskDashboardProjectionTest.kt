package com.agentgrid.mobile

import com.agentgrid.mobile.domain.AgentLifecycle
import com.agentgrid.mobile.domain.AgentSource
import com.agentgrid.mobile.domain.StateSnapshotPayload
import com.agentgrid.mobile.domain.SubagentSnapshot
import com.agentgrid.mobile.domain.TaskDashboardProjector
import com.agentgrid.mobile.domain.TaskSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TaskDashboardProjectionTest {
    @Test
    fun `排序分组稳定且已读变化不移动完成任务`() {
        val approval = task("approval", AgentLifecycle.WAITING_APPROVAL, 10)
        val running = task("running", AgentLifecycle.RUNNING, 30)
        val starting = task("starting", AgentLifecycle.STARTING, 40)
        val succeededB = task("b", AgentLifecycle.SUCCEEDED, 20, completedAt = NOW, isUnread = true)
        val succeededA = task("a", AgentLifecycle.SUCCEEDED, 20, completedAt = NOW)

        val before = project(
            listOf(succeededB, starting, succeededA, running, approval),
        ).orderedTasks.map { it.id }
        val after = project(
            listOf(succeededB.copy(isUnread = false), starting, succeededA, running, approval),
        ).orderedTasks.map { it.id }

        assertEquals(listOf("approval", "running", "starting", "a", "b"), before)
        assertEquals(before, after)
    }

    @Test
    fun `重复 ID 保留更新时间较新且同时间保留最后一个`() {
        val old = task("same", AgentLifecycle.RUNNING, 10)
        val newer = task("same", AgentLifecycle.RUNNING, 20)
        val last = newer.copy(title = "最后一个")

        val projection = project(listOf(old, newer, last))

        assertEquals(1, projection.orderedTasks.size)
        assertEquals("最后一个", projection.orderedTasks.single().title)
    }

    @Test
    fun `列表换位不算进入而列表外任务进入前五会标记`() {
        val original = (1..6).map { index ->
            task("task-$index", AgentLifecycle.RUNNING, (100 - index).toLong())
        }
        val first = project(original)
        val reordered = project(
            original.map {
                if (it.id == "task-2") it.copy(updatedAt = 200) else it
            },
            previous = first,
        )
        val entered = project(
            original.map {
                if (it.id == "task-6") it.copy(updatedAt = 300) else it
            },
            previous = first,
        )

        assertTrue(reordered.enteringVisibleTaskIDs.isEmpty())
        assertEquals(setOf("task-6"), entered.enteringVisibleTaskIDs)
    }

    @Test
    fun `远端焦点优先否则保留用户焦点再回退自动焦点`() {
        val running = task("running", AgentLifecycle.RUNNING, 30)
        val approval = task("approval", AgentLifecycle.WAITING_APPROVAL, 10)
        val automatic = project(listOf(running, approval))
        val userFocused = automatic.focusing("running")

        val retained = TaskDashboardProjector.project(
            snapshot = StateSnapshotPayload(listOf(running, approval)),
            previous = userFocused,
            now = NOW,
        )
        val remote = TaskDashboardProjector.project(
            snapshot = StateSnapshotPayload(
                tasks = listOf(running, approval),
                focusedTaskID = "approval",
            ),
            previous = userFocused,
            now = NOW,
        )

        assertEquals("approval", automatic.focusedTaskID)
        assertEquals("running", retained.focusedTaskID)
        assertEquals("approval", remote.focusedTaskID)
    }

    @Test
    fun `审批任务优先自动展开否则仍允许 Claude 活跃子代理展开`() {
        val delegated = task("delegated", AgentLifecycle.RUNNING, 30).copy(
            source = AgentSource.CLAUDE_CODE,
            subagents = listOf(
                SubagentSnapshot(
                    id = "subagent",
                    path = "/root/subagent",
                    displayName = "子代理",
                    lifecycle = AgentLifecycle.RUNNING,
                    startedAt = 1,
                    updatedAt = 2,
                ),
            ),
        )
        val approval = task("approval", AgentLifecycle.WAITING_APPROVAL, 10)

        val delegatedOnly = project(listOf(delegated))
        val urgent = project(listOf(delegated, approval))

        assertEquals("delegated", delegatedOnly.automaticallyExpandedTaskID)
        assertNull(delegatedOnly.urgentTaskID)
        assertEquals("approval", urgent.automaticallyExpandedTaskID)
        assertEquals("approval", urgent.urgentTaskID)
    }

    @Test
    fun `空列表立即显示 Dashboard 活跃任务始终显示任务态`() {
        assertTrue(project(emptyList()).dashboardVisible)
        assertFalse(
            project(listOf(task("running", AgentLifecycle.RUNNING, NOW))).dashboardVisible,
        )
    }

    @Test
    fun `全部终态只返回一次九十秒绝对切换时间`() {
        val completedAt = NOW - 30_000
        val completed = task(
            "done",
            AgentLifecycle.SUCCEEDED,
            completedAt,
            completedAt = completedAt,
        )

        val waiting = project(listOf(completed))
        val expired = TaskDashboardProjector.project(
            tasks = listOf(completed),
            preferredFocusedTaskID = null,
            previous = waiting,
            now = NOW + 60_000,
        )

        assertFalse(waiting.dashboardVisible)
        assertEquals(NOW + 60_000, waiting.nextDashboardAt)
        assertTrue(expired.dashboardVisible)
        assertNull(expired.nextDashboardAt)
    }

    @Test
    fun `手动覆盖会保留直到新增任务或终态任务复活`() {
        val running = task("existing", AgentLifecycle.RUNNING, 10)
        val hidden = project(listOf(running)).togglingDashboard()
        val ordinaryUpdate = project(listOf(running.copy(updatedAt = 20)), previous = hidden)
        val newTask = project(
            listOf(running.copy(updatedAt = 30), task("new", AgentLifecycle.STARTING, 40)),
            previous = ordinaryUpdate,
        )
        val completed = project(
            listOf(
                task(
                    "existing",
                    AgentLifecycle.SUCCEEDED,
                    50,
                    completedAt = 50,
                ),
            ),
        ).togglingDashboard()
        val restarted = project(
            listOf(task("existing", AgentLifecycle.STARTING, 60)),
            previous = completed,
        )

        assertEquals(true, ordinaryUpdate.manualDashboardOverride)
        assertNull(newTask.manualDashboardOverride)
        assertFalse(newTask.dashboardVisible)
        assertNull(restarted.manualDashboardOverride)
        assertFalse(restarted.dashboardVisible)
    }

    @Test
    fun `终态缺完成时间时使用更新时间且时钟倒退仍确定`() {
        val completed = task("done", AgentLifecycle.INTERRUPTED, NOW + 10_000)

        val projection = project(listOf(completed))

        assertEquals(NOW + 100_000, projection.nextDashboardAt)
        assertFalse(projection.dashboardVisible)
    }

    @Test
    fun `ZCode 空闲会话不占任务列表且运行会话保持焦点`() {
        val running = TaskSnapshot(
            id = "zcode-running",
            source = AgentSource.ZCODE,
            projectName = "AgentPager",
            title = "AgentPager · 监控 ZCode",
            lifecycle = AgentLifecycle.RUNNING,
            startedAt = 1,
            updatedAt = 10,
        )
        val idle = running.copy(
            id = "zcode-idle",
            lifecycle = AgentLifecycle.IDLE,
            updatedAt = 20,
        )

        val projection = project(listOf(idle, running))

        assertEquals(listOf("zcode-running"), projection.orderedTasks.map { it.id })
        assertEquals("zcode-running", projection.focusedTaskID)
        assertFalse(projection.dashboardVisible)
        assertNull(projection.nextDashboardAt)
    }

    @Test
    fun `ZCode 未开始空闲离线不占前五也不抢远端焦点`() {
        val hidden = listOf(AgentLifecycle.STARTING, AgentLifecycle.IDLE, AgentLifecycle.OFFLINE)
            .map { task(it.name, it, NOW - 100_000).copy(source = AgentSource.ZCODE) }
        val running = task("main", AgentLifecycle.RUNNING, 10)
        val projection = TaskDashboardProjector.project(
            snapshot = StateSnapshotPayload(hidden + running, focusedTaskID = hidden.first().id),
            previous = null,
            now = NOW,
        )

        assertEquals(listOf("main"), projection.visibleTaskIDs)
        assertEquals("main", projection.focusedTaskID)
        assertTrue(project(hidden).dashboardVisible)
    }

    @Test
    fun `ZCode 本轮停止显示绿色完成九十秒并能在同一会话继续`() {
        val running = task("zcode", AgentLifecycle.RUNNING, NOW - 10).copy(source = AgentSource.ZCODE)
        val first = project(listOf(running))
        val idle = running.copy(lifecycle = AgentLifecycle.IDLE, updatedAt = NOW)
        val stopped = project(listOf(running, idle), previous = first)
        val completed = requireNotNull(stopped.focusedTask)
        assertEquals(AgentLifecycle.SUCCEEDED, completed.lifecycle)
        assertEquals(NOW, completed.completedAt)
        assertEquals("本轮已完成", completed.latestStep)
        assertFalse(stopped.dashboardVisible)
        assertEquals(NOW + 90_000, stopped.nextRefreshAt)
        assertEquals(NOW + 90_000, stopped.nextDashboardAt)
        assertEquals(AgentLifecycle.IDLE, idle.lifecycle)

        val repeated = TaskDashboardProjector.project(
            listOf(idle), null, stopped, now = NOW + 30_000,
        )
        assertEquals(NOW + 90_000, repeated.nextRefreshAt)
        val expired = TaskDashboardProjector.project(
            listOf(idle), null, repeated, now = NOW + 90_000,
        )
        assertTrue(expired.orderedTasks.isEmpty())
        assertTrue(expired.dashboardVisible)
        assertNull(expired.nextRefreshAt)

        val resumed = project(listOf(running.copy(updatedAt = NOW + 1)), previous = stopped)
        assertEquals(AgentLifecycle.RUNNING, resumed.focusedTask?.lifecycle)
        assertFalse(resumed.dashboardVisible)
        assertNull(resumed.nextRefreshAt)
    }

    @Test
    fun `其它任务运行或手动切换看板仍调度 ZCode 完成行清理`() {
        val idle = task("zcode", AgentLifecycle.IDLE, NOW).copy(source = AgentSource.ZCODE)
        val main = task("main", AgentLifecycle.RUNNING, NOW)
        val mixed = project(listOf(idle, main))
        assertNull(mixed.nextDashboardAt)
        assertEquals(NOW + 90_000, mixed.nextRefreshAt)
        val manual = TaskDashboardProjector.project(
            listOf(idle, main), null, mixed.togglingDashboard(), now = NOW + 1,
        )
        assertTrue(manual.dashboardVisible)
        assertEquals(NOW + 90_000, manual.nextRefreshAt)
        val expired = TaskDashboardProjector.project(
            listOf(idle, main), null, manual, now = NOW + 90_000,
        )
        assertEquals(listOf("main"), expired.visibleTaskIDs)
        assertTrue(expired.dashboardVisible)
        assertNull(expired.nextRefreshAt)
    }

    @Test
    fun `ZCode 完成提示音只播放一次收起时不再播放`() {
        val tracker = TaskSoundTracker()
        val running = task("zcode", AgentLifecycle.RUNNING, NOW - 10).copy(source = AgentSource.ZCODE)
        val first = project(listOf(running))
        assertNull(tracker.nextCue(first.orderedTasks))
        val idle = running.copy(lifecycle = AgentLifecycle.IDLE, updatedAt = NOW)
        val stopped = project(listOf(idle), previous = first)
        assertEquals(ArcadeSoundCue.TASK_COMPLETE, tracker.nextCue(stopped.orderedTasks))
        assertNull(tracker.nextCue(project(listOf(idle), previous = stopped).orderedTasks))
        val expired = TaskDashboardProjector.project(listOf(idle), null, stopped, now = NOW + 90_000)
        assertNull(tracker.nextCue(expired.orderedTasks))
    }

    @Test
    fun `Codex memories 后台整理任务隐藏且普通 memories 项目不误删`() {
        for (source in listOf(AgentSource.CODEX_CLI, AgentSource.CODEX_DESKTOP)) {
            val memory = task("memory", AgentLifecycle.RUNNING, NOW).copy(
                source = source, projectName = "memories",
                title = "memories · ## Memory Writing Agent: Phase 2 (",
                userPrompt = "## Memory Writing Agent: Phase 2 (Consolidation)",
            )
            val ordinary = memory.copy(
                id = "ordinary", title = "memories · 修复搜索功能", userPrompt = "修复搜索功能",
            )
            val sameWordsElsewhere = memory.copy(id = "elsewhere", projectName = "my-app")
            val projection = TaskDashboardProjector.project(
                StateSnapshotPayload(listOf(memory, ordinary, sameWordsElsewhere), focusedTaskID = memory.id),
                previous = null, now = NOW,
            )
            assertEquals(setOf("ordinary", "elsewhere"), projection.visibleTaskIDs.toSet())
            assertFalse(projection.focusedTaskID == memory.id)
            assertTrue(project(listOf(memory.copy(userPrompt = null))).dashboardVisible)
            assertTrue(project(listOf(memory.copy(lifecycle = AgentLifecycle.SUCCEEDED))).orderedTasks.isEmpty())
            assertFalse(project(listOf(memory.copy(source = AgentSource.CLAUDE_CODE))).orderedTasks.isEmpty())
        }
    }

    @Test
    fun `新版 Codex memory 包含截断标题和旧运行记录也隐藏`() {
        for (source in listOf(AgentSource.CODEX_CLI, AgentSource.CODEX_DESKTOP)) {
            val memory = task("memory-v2", AgentLifecycle.RUNNING, NOW).copy(
                source = source, projectName = "memories_v2",
                title = "memories_v2 · Consolidate the supplied rollout s",
                userPrompt = "Consolidate the supplied rollout summaries into `memory_summary.md`",
                startedAt = NOW - 4 * 60 * 60 * 1000,
            )
            for (candidate in listOf(memory, memory.copy(userPrompt = null),
                memory.copy(lifecycle = AgentLifecycle.SUCCEEDED, completedAt = NOW))) {
                val projection = TaskDashboardProjector.project(
                    StateSnapshotPayload(listOf(candidate), focusedTaskID = candidate.id),
                    previous = null, now = NOW,
                )
                assertTrue(projection.orderedTasks.isEmpty())
                assertNull(projection.focusedTaskID)
                assertNull(projection.automaticallyExpandedTaskID)
                assertNull(TaskSoundTracker().nextCue(projection.orderedTasks))
            }
            val ordinary = memory.copy(title = "memories_v2 · 修复搜索功能", userPrompt = "修复搜索功能")
            assertFalse(project(listOf(ordinary)).orderedTasks.isEmpty())
            assertFalse(project(listOf(memory.copy(projectName = "my-app"))).orderedTasks.isEmpty())
            assertFalse(project(listOf(memory.copy(source = AgentSource.CLAUDE_CODE))).orderedTasks.isEmpty())
        }
    }

    @Test
    fun `ZCode 审批和回答仍显示并自动展开`() {
        for (lifecycle in listOf(AgentLifecycle.WAITING_APPROVAL, AgentLifecycle.WAITING_ANSWER)) {
            val waiting = task("zcode", lifecycle, 10).copy(source = AgentSource.ZCODE)
            val projection = project(listOf(waiting))
            assertEquals(waiting, projection.focusedTask)
            assertEquals("zcode", projection.urgentTaskID)
            assertEquals("zcode", projection.automaticallyExpandedTaskID)
            assertFalse(projection.dashboardVisible)
        }
    }

    @Test
    fun `Codex 两种来源隐藏所有子代理但保留主任务进度审批和完成提醒`() {
        for (source in listOf(AgentSource.CODEX_CLI, AgentSource.CODEX_DESKTOP)) {
            val child = SubagentSnapshot(
                id = "child", path = "/root/child", displayName = "child",
                lifecycle = AgentLifecycle.RUNNING, startedAt = 1, updatedAt = 2,
            )
            val main = task("main", AgentLifecycle.RUNNING, 10).copy(
                source = source, latestStep = "主任务正在执行", subagents = listOf(child),
            )
            val projection = project(listOf(main))
            assertEquals(main.copy(subagents = emptyList()), projection.focusedTask)
            assertTrue(projection.visibleTasks.single().subagents.isEmpty())
            assertNull(projection.automaticallyExpandedTaskID)
            assertEquals(1, main.subagents.size)

            val approval = main.copy(lifecycle = AgentLifecycle.WAITING_APPROVAL)
            assertEquals("main", project(listOf(approval)).automaticallyExpandedTaskID)
            val done = main.copy(
                lifecycle = AgentLifecycle.SUCCEEDED, completedAt = NOW, isUnread = true,
                subagents = listOf(child.copy(lifecycle = AgentLifecycle.SUCCEEDED)),
            )
            val completed = project(listOf(done), previous = projection)
            assertEquals(done.copy(subagents = emptyList()), completed.focusedTask)
            assertEquals(NOW + 90_000, completed.nextDashboardAt)
        }
    }

    private fun project(
        tasks: List<TaskSnapshot>,
        previous: com.agentgrid.mobile.domain.TaskDashboardProjection? = null,
    ) = TaskDashboardProjector.project(
        tasks = tasks,
        preferredFocusedTaskID = null,
        previous = previous,
        now = NOW,
    )

    private fun task(
        id: String,
        lifecycle: AgentLifecycle,
        updatedAt: Long,
        completedAt: Long? = null,
        isUnread: Boolean = false,
    ) = TaskSnapshot(
        id = id,
        source = AgentSource.CODEX_CLI,
        projectName = id,
        title = id,
        lifecycle = lifecycle,
        startedAt = 0,
        updatedAt = updatedAt,
        completedAt = completedAt,
        isUnread = isUnread,
    )

    private companion object {
        const val NOW = 1_000_000L
    }
}
