package com.agentgrid.mobile.domain

object TaskOrdering {
    fun sorted(tasks: List<TaskSnapshot>): List<TaskSnapshot> =
        tasks.sortedWith(
            compareByDescending<TaskSnapshot> { it.sortGroup }
                .thenByDescending { it.attentionPriority }
                .thenByDescending { it.updatedAt },
        )

    private val TaskSnapshot.sortGroup: Int
        get() = when (lifecycle) {
            AgentLifecycle.RUNNING -> 2
            AgentLifecycle.SUCCEEDED -> 0
            else -> 1
        }
}
