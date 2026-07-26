package com.agentgrid.mobile.network

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

internal class OkHttpPhoneSessionTransport : PhoneSessionTransport {
    private val mutableEvents = MutableSharedFlow<TransportEvent>(extraBufferCapacity = 64)
    override val events: Flow<TransportEvent> = mutableEvents
    private val httpClient = OkHttpClient.Builder()
        .pingInterval(20, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    private var socket: WebSocket? = null
    private var generation = 0L

    override fun connect(endpoint: PhoneEndpoint) {
        generation += 1
        val currentGeneration = generation
        socket?.cancel()
        val request = runCatching {
            Request.Builder()
                .url("ws://${endpoint.host}:${endpoint.port}/agentgrid")
                .build()
        }.getOrElse {
            mutableEvents.tryEmit(TransportEvent.Failed(it.message))
            return
        }
        socket = httpClient.newWebSocket(
            request,
            object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    if (accepts(webSocket, currentGeneration)) {
                        mutableEvents.tryEmit(TransportEvent.Opened)
                    }
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    if (accepts(webSocket, currentGeneration)) {
                        mutableEvents.tryEmit(TransportEvent.TextReceived(text))
                    }
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    if (accepts(webSocket, currentGeneration)) {
                        socket = null
                        mutableEvents.tryEmit(TransportEvent.Closed(reason))
                    }
                }

                override fun onFailure(
                    webSocket: WebSocket,
                    t: Throwable,
                    response: Response?,
                ) {
                    if (accepts(webSocket, currentGeneration)) {
                        socket = null
                        mutableEvents.tryEmit(TransportEvent.Failed(t.message))
                    }
                }
            },
        )
    }

    override fun send(text: String): Boolean = socket?.send(text) == true

    override fun disconnect() {
        generation += 1
        socket?.close(1000, "用户断开")
        socket = null
    }

    override fun close() {
        disconnect()
        httpClient.dispatcher.executorService.shutdown()
        httpClient.connectionPool.evictAll()
    }

    private fun accepts(webSocket: WebSocket, eventGeneration: Long): Boolean =
        generation == eventGeneration && socket === webSocket
}
