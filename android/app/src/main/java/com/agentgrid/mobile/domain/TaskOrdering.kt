package com.agentgrid.mobile.domain

object TaskOrdering {
    fun sorted(tasks: List<TaskSnapshot>): List<TaskSnapshot> =
        tasks.sortedWith(
            compareByDescending<TaskSnapshot> { it.sortGroup }
                .thenByDescending { it.listPriority }
                .thenByDescending { it.updatedAt },
        )

    fun enteringVisibleTaskIDs(
        previousVisibleTaskIDs: Set<String>,
        orderedTasks: List<TaskSnapshot>,
        visibleLimit: Int = 5,
    ): Set<String> {
        if (previousVisibleTaskIDs.isEmpty()) return emptySet()

        return orderedTasks
            .take(visibleLimit)
            .mapTo(linkedSetOf()) { it.id }
            .filterNotTo(linkedSetOf()) { it in previousVisibleTaskIDs }
    }

    private val TaskSnapshot.listPriority: Int
        get() = when (lifecycle) {
            // 已读状态只控制提醒，不应让用户展开任务时改变列表位置。
            AgentLifecycle.SUCCEEDED -> if (isPinned) 1 else 0
            else -> attentionPriority
        }

    private val TaskSnapshot.sortGroup: Int
        get() = when (lifecycle) {
            AgentLifecycle.WAITING_APPROVAL -> 3
            AgentLifecycle.RUNNING -> 2
            AgentLifecycle.SUCCEEDED -> 0
            else -> 1
        }
}
