package com.agentgrid.mobile

import android.app.Application
import android.provider.Settings
import androidx.core.content.edit
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.agentgrid.mobile.domain.ControlAction
import com.agentgrid.mobile.domain.PairingPayload
import com.agentgrid.mobile.domain.PendingRequest
import com.agentgrid.mobile.domain.TaskFocus
import com.agentgrid.mobile.domain.TaskSnapshot
import com.agentgrid.mobile.domain.UsageSnapshot
import com.agentgrid.mobile.network.AgentGridClient
import com.agentgrid.mobile.network.LinkState
import com.agentgrid.mobile.network.PairingStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json

data class AgentGridUiState(
    val pairing: PairingPayload? = null,
    val linkState: LinkState = LinkState.DISCONNECTED,
    val tasks: List<TaskSnapshot> = emptyList(),
    val focusedTaskID: String? = null,
    val usage: UsageSnapshot? = null,
    val pendingRequests: List<PendingRequest> = emptyList(),
    val pairingError: String? = null,
    val terminalMode: Boolean = true,
    val activeTaskBrightness: Float = ScreenBrightnessPolicy.DEFAULT_ACTIVE_BRIGHTNESS,
) {
    val focusedTask: TaskSnapshot?
        get() = tasks.firstOrNull { it.id == focusedTaskID } ?: TaskFocus.focused(tasks)
}

class AgentGridViewModel(application: Application) : AndroidViewModel(application) {
    private val pairingStore = PairingStore(application)
    private val preferences =
        application.getSharedPreferences("agentgrid-settings", Application.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }
    private val mutableState = MutableStateFlow(
        AgentGridUiState(
            pairing = pairingStore.load(),
            terminalMode = preferences.getBoolean("terminal-mode", true),
            activeTaskBrightness = ScreenBrightnessPolicy.sanitizeActiveBrightness(
                preferences.getFloat(
                    "active-task-brightness",
                    ScreenBrightnessPolicy.DEFAULT_ACTIVE_BRIGHTNESS,
                ),
            ),
        ),
    )
    val state: StateFlow<AgentGridUiState> = mutableState.asStateFlow()

    private val client = AgentGridClient(
        pairingStore = pairingStore,
        deviceID = Settings.Secure.getString(
            application.contentResolver,
            Settings.Secure.ANDROID_ID,
        ) ?: "agentgrid-android",
    ) { envelope ->
        mutableState.value = mutableState.value.copy(
            tasks = envelope.payload.tasks.sortedByDescending { it.updatedAt },
            focusedTaskID = envelope.payload.focusedTaskID,
            usage = envelope.payload.usage,
            pendingRequests = envelope.payload.pendingRequests,
        )
    }

    init {
        viewModelScope.launch {
            client.linkState.collect { link ->
                mutableState.value = mutableState.value.copy(linkState = link)
            }
        }
        mutableState.value.pairing?.let(client::connect)
    }

    fun pair(text: String) {
        val pairing = runCatching {
            json.decodeFromString<PairingPayload>(text.trim())
        }.getOrElse {
            mutableState.value = mutableState.value.copy(pairingError = "二维码内容不是有效的 AgentGrid 配对信息")
            return
        }

        if (pairing.version != 1 || pairing.secret.isBlank() || pairing.host.isBlank()) {
            mutableState.value = mutableState.value.copy(pairingError = "配对信息版本或地址无效")
            return
        }
        pairingStore.save(pairing)
        mutableState.value = mutableState.value.copy(pairing = pairing, pairingError = null)
        client.connect(pairing)
    }

    fun unpair() {
        client.disconnect()
        pairingStore.clear()
        val previousState = mutableState.value
        mutableState.value = AgentGridUiState(
            terminalMode = previousState.terminalMode,
            activeTaskBrightness = previousState.activeTaskBrightness,
        )
    }

    fun control(taskID: String, action: ControlAction, value: String? = null) {
        client.send(taskID, action, value)
    }

    fun focus(taskID: String) {
        mutableState.value = mutableState.value.copy(focusedTaskID = taskID)
    }

    fun setTerminalMode(enabled: Boolean) {
        preferences.edit { putBoolean("terminal-mode", enabled) }
        mutableState.value = mutableState.value.copy(terminalMode = enabled)
    }

    fun setActiveTaskBrightness(value: Float) {
        val brightness = ScreenBrightnessPolicy.sanitizeActiveBrightness(value)
        preferences.edit { putFloat("active-task-brightness", brightness) }
        mutableState.value = mutableState.value.copy(activeTaskBrightness = brightness)
    }

    override fun onCleared() {
        client.disconnect()
    }
}
