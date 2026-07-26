package com.agentgrid.mobile.network

import com.agentgrid.mobile.domain.ControlAction
import com.agentgrid.mobile.domain.ControlPayload
import com.agentgrid.mobile.domain.SignedControlEnvelope
import java.nio.charset.StandardCharsets
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlinx.serialization.json.Json

object ControlSigner {
    private val json = Json {
        encodeDefaults = false
        explicitNulls = false
    }

    fun sign(envelope: SignedControlEnvelope, secret: ByteArray): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret, "HmacSHA256"))
        val signature = mac.doFinal(signingText(envelope).toByteArray(StandardCharsets.UTF_8))
        return Base64.getEncoder().encodeToString(signature)
    }

    fun signingText(envelope: SignedControlEnvelope): String {
        val payload = canonicalPayload(envelope.payload)
        return listOf(
            envelope.version.toString(),
            envelope.messageId.lowercase(),
            envelope.sentAt.toString(),
            envelope.deviceId,
            envelope.sequence.toString(),
            envelope.nonce,
            envelope.type,
            payload,
        ).joinToString("\n")
    }

    private fun canonicalPayload(payload: ControlPayload): String {
        val action = when (payload.action) {
            ControlAction.APPROVE -> "approve"
            ControlAction.DENY -> "deny"
            ControlAction.ANSWER -> "answer"
            ControlAction.INTERRUPT -> "interrupt"
            ControlAction.RETRY -> "retry"
            ControlAction.MUTE -> "mute"
            ControlAction.MARK_READ -> "markRead"
            ControlAction.PIN -> "pin"
        }
        val escapedAction = json.encodeToString(action)
        val escapedTask = json.encodeToString(payload.taskID)
        return if (payload.value == null) {
            """{"action":$escapedAction,"taskID":$escapedTask}"""
        } else {
            val escapedValue = json.encodeToString(payload.value)
            """{"action":$escapedAction,"taskID":$escapedTask,"value":$escapedValue}"""
        }
    }
}
