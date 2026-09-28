package com.agentgrid.mobile

import com.agentgrid.mobile.domain.AgentLifecycle
import com.agentgrid.mobile.domain.AgentSource
import com.agentgrid.mobile.domain.TaskDashboardProjector
import com.agentgrid.mobile.domain.TaskSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class InactiveTaskVisibilityTest {
    private val now = 1_000_000L

    private fun task(id: String, source: AgentSource, state: AgentLifecycle) = TaskSnapshot(
        id = id,
        source = source,
        projectName = "Audit",
        lifecycle = state,
        startedAt = 0,
        updatedAt = now,
        completedAt = if (state in setOf(AgentLifecycle.SUCCEEDED, AgentLifecycle.INTERRUPTED)) now else null,
    )

    private fun project(vararg tasks: TaskSnapshot) = TaskDashboardProjector.project(
        tasks = tasks.toList(), preferredFocusedTaskID = null, previous = null, now = now,
    )

    @Test
    fun completedFeedbackExpiresEvenWhileAnotherTaskRuns() {
        for (state in listOf(AgentLifecycle.SUCCEEDED, AgentLifecycle.INTERRUPTED)) {
            val done = task("done", AgentSource.OMP, state)
            val running = task("running", AgentSource.CODEX_CLI, AgentLifecycle.RUNNING)
            val first = project(done, running)
            assertTrue(first.visibleTasks.any { it.id == "done" })
            assertEquals(now + 90_000L, first.nextRefreshAt)
            // A manual dashboard choice must not cancel the card expiry deadline.
            val manual = TaskDashboardProjector.project(
                tasks = listOf(done, running), preferredFocusedTaskID = null,
                previous = first.togglingDashboard(), now = now + 1,
            )
            assertEquals(now + 90_000L, manual.nextRefreshAt)
            val expired = TaskDashboardProjector.project(
                tasks = listOf(done, running), preferredFocusedTaskID = null,
                previous = manual, now = now + 90_000,
            )
            assertEquals(listOf("running"), expired.visibleTasks.map { it.id })
        }
    }

    @Test
    fun idleHiddenButWaitingRemainsVisibleForEverySource() {
        for (source in listOf(AgentSource.OMP, AgentSource.CODEX_CLI, AgentSource.CODEX_DESKTOP)) {
            assertTrue(project(task("idle", source, AgentLifecycle.IDLE)).visibleTasks.isEmpty())
            assertEquals(1, project(task("waiting", source, AgentLifecycle.WAITING_ANSWER)).visibleTasks.size)
            assertEquals(1, project(task("approval", source, AgentLifecycle.WAITING_APPROVAL)).visibleTasks.size)
        }
    }

    @Test
    fun offlineOmpMustNotOccupyVisibleList() {
        assertTrue(project(task("offline", AgentSource.OMP, AgentLifecycle.OFFLINE)).visibleTasks.isEmpty())
    }

    @Test
    fun offlineOmpMustNotBlockIdleDashboard() {
        assertTrue(project(task("offline", AgentSource.OMP, AgentLifecycle.OFFLINE)).dashboardVisible)
    }

    @Test
    fun inactiveOmpMustNotEvictCodexCompletion() {
        val tasks = (1..5).map { task("offline-$it", AgentSource.OMP, AgentLifecycle.OFFLINE) } +
            task("done", AgentSource.CODEX_CLI, AgentLifecycle.SUCCEEDED)
        assertEquals(listOf("done"), project(*tasks.toTypedArray()).visibleTasks.map { it.id })
    }
}
