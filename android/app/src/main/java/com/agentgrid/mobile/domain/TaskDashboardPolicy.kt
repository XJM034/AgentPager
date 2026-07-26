package com.agentgrid.mobile.domain

object TaskDashboardPolicy {
    const val IDLE_DELAY_MILLIS = 90_000L

    fun manualDashboardOverrideAfterTaskUpdate(
        previousTerminalStates: Map<String, Boolean>?,
        currentTasks: List<TaskSnapshot>,
        currentOverride: Boolean?,
    ): Boolean? {
        if (previousTerminalStates == null) return currentOverride

        val hasNewTask = currentTasks.any { task ->
            val wasTerminal = previousTerminalStates[task.id]
            wasTerminal == null || (wasTerminal && !task.isTerminal)
        }
        return if (hasNewTask) null else currentOverride
    }

    fun shouldShowDashboard(
        tasks: List<TaskSnapshot>,
        now: Long,
        idleDelayMillis: Long = IDLE_DELAY_MILLIS,
    ): Boolean = timeUntilDashboard(
        tasks = tasks,
        now = now,
        idleDelayMillis = idleDelayMillis,
    ) == 0L

    fun timeUntilDashboard(
        tasks: List<TaskSnapshot>,
        now: Long,
        idleDelayMillis: Long = IDLE_DELAY_MILLIS,
    ): Long {
        if (tasks.any { !it.isTerminal }) return Long.MAX_VALUE

        val lastFinishedAt = tasks.maxOfOrNull {
            it.completedAt ?: it.updatedAt
        } ?: return 0L
        return (lastFinishedAt + idleDelayMillis - now).coerceAtLeast(0L)
    }
}
