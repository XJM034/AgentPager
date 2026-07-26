package com.agentgrid.mobile.domain

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class AgentSource {
    @SerialName("codexDesktop")
    CODEX_DESKTOP,

    @SerialName("codexCLI")
    CODEX_CLI,
}

@Serializable
enum class AgentLifecycle {
    @SerialName("offline")
    OFFLINE,

    @SerialName("idle")
    IDLE,

    @SerialName("starting")
    STARTING,

    @SerialName("running")
    RUNNING,

    @SerialName("waitingApproval")
    WAITING_APPROVAL,

    @SerialName("waitingAnswer")
    WAITING_ANSWER,

    @SerialName("succeeded")
    SUCCEEDED,

    @SerialName("failed")
    FAILED,

    @SerialName("interrupted")
    INTERRUPTED,
}

@Serializable
enum class AgentActivity {
    @SerialName("thinking")
    THINKING,

    @SerialName("reading")
    READING,

    @SerialName("searching")
    SEARCHING,

    @SerialName("editing")
    EDITING,

    @SerialName("executing")
    EXECUTING,

    @SerialName("testing")
    TESTING,

    @SerialName("browsing")
    BROWSING,

    @SerialName("delegating")
    DELEGATING,
}

@Serializable
enum class TaskCapability {
    @SerialName("approve")
    APPROVE,

    @SerialName("deny")
    DENY,

    @SerialName("answer")
    ANSWER,

    @SerialName("interrupt")
    INTERRUPT,

    @SerialName("retry")
    RETRY,
}

@Serializable
data class TaskSnapshot(
    val id: String,
    val source: AgentSource,
    val projectName: String,
    val lifecycle: AgentLifecycle,
    val activity: AgentActivity? = null,
    val startedAt: Long,
    val updatedAt: Long,
    val completedAt: Long? = null,
    val isUnread: Boolean = false,
    val isPinned: Boolean = false,
    val isMuted: Boolean = false,
    val capabilities: Set<TaskCapability> = emptySet(),
) {
    val attentionPriority: Int
        get() {
            val lifecycleValue = when (lifecycle) {
                AgentLifecycle.WAITING_APPROVAL -> 600
                AgentLifecycle.WAITING_ANSWER -> 500
                AgentLifecycle.FAILED -> 400
                AgentLifecycle.SUCCEEDED -> 300
                AgentLifecycle.STARTING, AgentLifecycle.RUNNING -> 200
                else -> 100
            }
            val unreadValue = if (isUnread && lifecycle == AgentLifecycle.SUCCEEDED) 50 else 0
            val pinnedValue = if (isPinned) 25 else 0
            return lifecycleValue + unreadValue + pinnedValue
        }
}

@Serializable
data class UsageWindow(
    val key: String,
    val label: String,
    val usedPercentage: Double,
    val remainingPercentage: Double,
    val windowMinutes: Int,
    val resetsAt: Long? = null,
)

@Serializable
data class UsageSnapshot(
    val capturedAt: Long? = null,
    val planType: String? = null,
    val limitID: String? = null,
    val windows: List<UsageWindow> = emptyList(),
)

@Serializable
data class StateSnapshotPayload(
    val tasks: List<TaskSnapshot>,
    val usage: UsageSnapshot? = null,
    val focusedTaskID: String? = null,
    val pendingRequests: List<PendingRequest> = emptyList(),
)

@Serializable
enum class PendingRequestKind {
    @SerialName("approval")
    APPROVAL,

    @SerialName("question")
    QUESTION,
}

@Serializable
data class PendingRequest(
    val taskID: String,
    val kind: PendingRequestKind,
    val summary: String? = null,
    val options: List<String> = emptyList(),
)

@Serializable
data class StateEnvelope(
    val version: Int,
    val messageId: String,
    val type: String,
    val sentAt: Long,
    val payload: StateSnapshotPayload,
)

@Serializable
enum class ControlAction {
    @SerialName("approve")
    APPROVE,

    @SerialName("deny")
    DENY,

    @SerialName("answer")
    ANSWER,

    @SerialName("interrupt")
    INTERRUPT,

    @SerialName("retry")
    RETRY,

    @SerialName("mute")
    MUTE,

    @SerialName("markRead")
    MARK_READ,

    @SerialName("pin")
    PIN,
}

@Serializable
data class ControlPayload(
    val taskID: String,
    val action: ControlAction,
    val value: String? = null,
)

@Serializable
data class SignedControlEnvelope(
    val version: Int = 1,
    val messageId: String,
    val type: String = "control.request",
    val sentAt: Long,
    val deviceId: String,
    val sequence: ULong,
    val nonce: String,
    val payload: ControlPayload,
    val signature: String,
)

@Serializable
data class PairingPayload(
    val version: Int,
    val serviceID: String,
    val host: String,
    val port: Int,
    val secret: String,
)
