package com.agentgrid.mobile

import com.agentgrid.mobile.domain.AgentLifecycle
import com.agentgrid.mobile.domain.AgentSource
import com.agentgrid.mobile.domain.TaskOrdering
import com.agentgrid.mobile.domain.TaskSnapshot
import org.junit.Assert.assertEquals
import org.junit.Test

class TaskOrderingTest {
    @Test
    fun `等待用户审批的任务始终排在首位`() {
        val approval = task("approval", AgentLifecycle.WAITING_APPROVAL, updatedAt = 10)
        val interrupted = task("interrupted", AgentLifecycle.INTERRUPTED, updatedAt = 20)
        val running = task("running", AgentLifecycle.RUNNING, updatedAt = 30)

        val orderedIDs = TaskOrdering.sorted(listOf(approval, interrupted, running)).map { it.id }

        assertEquals(listOf("approval", "running", "interrupted"), orderedIDs)
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
    fun `刚完成任务插在最后一个未完成任务之后`() {
        val runningRecent = task("running-recent", AgentLifecycle.RUNNING, updatedAt = 30)
        val runningOld = task("running-old", AgentLifecycle.RUNNING, updatedAt = 20)
        val justSucceeded = task("just-succeeded", AgentLifecycle.SUCCEEDED, updatedAt = 40)
        val succeededOld = task("succeeded-old", AgentLifecycle.SUCCEEDED, updatedAt = 10)

        val orderedIDs = TaskOrdering.sorted(
            listOf(justSucceeded, succeededOld, runningOld, runningRecent),
        ).map { it.id }

        assertEquals(
            listOf("running-recent", "running-old", "just-succeeded", "succeeded-old"),
            orderedIDs,
        )
    }

    @Test
    fun `列表内任务换位不视为新进入`() {
        val first = task("first", AgentLifecycle.RUNNING, updatedAt = 20)
        val second = task("second", AgentLifecycle.RUNNING, updatedAt = 30)

        val enteringIDs = TaskOrdering.enteringVisibleTaskIDs(
            previousVisibleTaskIDs = linkedSetOf("first", "second"),
            orderedTasks = TaskOrdering.sorted(listOf(first, second)),
        )

        assertEquals(emptySet<String>(), enteringIDs)
    }

    @Test
    fun `列表外任务进入可见区时标记为新进入`() {
        val outside = task("outside", AgentLifecycle.RUNNING, updatedAt = 60)
        val previousVisibleTasks = (1..5).map { index ->
            task("visible-$index", AgentLifecycle.RUNNING, updatedAt = (50 - index).toLong())
        }

        val enteringIDs = TaskOrdering.enteringVisibleTaskIDs(
            previousVisibleTaskIDs = previousVisibleTasks.mapTo(linkedSetOf()) { it.id },
            orderedTasks = TaskOrdering.sorted(previousVisibleTasks + outside),
        )

        assertEquals(setOf("outside"), enteringIDs)
    }

    @Test
    fun `其他状态保留注意力优先级顺序`() {
        val starting = task("starting", AgentLifecycle.STARTING, updatedAt = 30)
        val approval = task("approval", AgentLifecycle.WAITING_APPROVAL, updatedAt = 10)

        val orderedIDs = TaskOrdering.sorted(listOf(starting, approval)).map { it.id }

        assertEquals(listOf("approval", "starting"), orderedIDs)
    }

    @Test
    fun `查看未读任务后已读状态变化不改变任务位置`() {
        val clicked = task(
            id = "clicked",
            lifecycle = AgentLifecycle.SUCCEEDED,
            updatedAt = 10,
            isUnread = true,
        )
        val other = task(
            id = "other",
            lifecycle = AgentLifecycle.SUCCEEDED,
            updatedAt = 20,
        )
        val before = TaskOrdering.sorted(listOf(clicked, other)).map { it.id }
        val after = TaskOrdering.sorted(
            listOf(clicked.copy(isUnread = false), other),
        ).map { it.id }

        assertEquals(before, after)
    }

    private fun task(
        id: String,
        lifecycle: AgentLifecycle,
        updatedAt: Long,
        isUnread: Boolean = false,
    ) = TaskSnapshot(
        id = id,
        source = AgentSource.CODEX_CLI,
        projectName = id,
        lifecycle = lifecycle,
        startedAt = 0,
        updatedAt = updatedAt,
        isUnread = isUnread,
    )
}
