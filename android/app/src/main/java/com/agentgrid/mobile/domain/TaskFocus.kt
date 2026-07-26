package com.agentgrid.mobile.domain

object TaskFocus {
    fun focused(tasks: List<TaskSnapshot>): TaskSnapshot? =
        tasks.maxWithOrNull(
            compareBy<TaskSnapshot> { it.attentionPriority }
                .thenBy { it.updatedAt },
        )
}

