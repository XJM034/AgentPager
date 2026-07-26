package com.agentgrid.mobile.network

import com.agentgrid.mobile.domain.ControlAction
import com.agentgrid.mobile.domain.ControlPayload
import com.agentgrid.mobile.domain.PairingPayload
import com.agentgrid.mobile.domain.SignedControlEnvelope
import com.agentgrid.mobile.domain.StateEnvelope
import java.util.Base64
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

enum class LinkState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
}

class AgentGridClient(
    private val pairingStore: PairingStore,
    private val deviceID: String,
    private val onSnapshot: (StateEnvelope) -> Unit,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        explicitNulls = false
    }
    private val httpClient = OkHttpClient.Builder()
        .pingInterval(20, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()
    private val mutableLinkState = MutableStateFlow(LinkState.DISCONNECTED)
    val linkState: StateFlow<LinkState> = mutableLinkState

    private var pairing: PairingPayload? = null
    private var socket: WebSocket? = null
    private var reconnectJob: Job? = null
    private var retryCount = 0
    private var stopped = false

    fun connect(value: PairingPayload) {
        pairing = value
        stopped = false
        reconnectJob?.cancel()
        openSocket()
    }

    fun disconnect() {
        stopped = true
        reconnectJob?.cancel()
        reconnectJob = null
        socket?.close(1000, "用户断开")
        socket = null
        mutableLinkState.value = LinkState.DISCONNECTED
    }

    fun send(taskID: String, action: ControlAction, value: String? = null): Boolean {
        val pairing = pairing ?: return false
        val unsigned = SignedControlEnvelope(
            messageId = UUID.randomUUID().toString(),
            sentAt = System.currentTimeMillis(),
            deviceId = deviceID,
            sequence = pairingStore.nextSequence(),
            nonce = UUID.randomUUID().toString(),
            payload = ControlPayload(taskID, action, value),
            signature = "",
        )
        val secret = Base64.getDecoder().decode(pairing.secret)
        val signed = unsigned.copy(signature = ControlSigner.sign(unsigned, secret))
        return socket?.send(json.encodeToString(signed)) == true
    }

    private fun openSocket() {
        val pairing = pairing ?: return
        socket?.cancel()
        mutableLinkState.value = LinkState.CONNECTING
        val request = Request.Builder()
            .url("ws://${pairing.host}:${pairing.port}/agentgrid")
            .build()
        socket = httpClient.newWebSocket(request, listener)
    }

    private val listener = object : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            retryCount = 0
            mutableLinkState.value = LinkState.CONNECTED
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            val envelope = runCatching { json.decodeFromString<StateEnvelope>(text) }.getOrNull()
            if (envelope?.type == "state.snapshot") {
                onSnapshot(envelope)
            }
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            mutableLinkState.value = LinkState.DISCONNECTED
            scheduleReconnect()
        }

        override fun onFailure(webSocket: WebSocket, throwable: Throwable, response: Response?) {
            mutableLinkState.value = LinkState.DISCONNECTED
            scheduleReconnect()
        }
    }

    private fun scheduleReconnect() {
        if (stopped || reconnectJob?.isActive == true) return
        reconnectJob = scope.launch {
            val exponent = minOf(retryCount++, 5)
            val waitMillis = minOf(30_000L, 1_000L shl exponent)
            delay(waitMillis)
            if (!stopped) openSocket()
        }
    }
}
