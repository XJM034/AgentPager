package com.agentgrid.mobile

import com.agentgrid.mobile.domain.ControlAction
import com.agentgrid.mobile.domain.ControlPayload
import com.agentgrid.mobile.domain.SignedControlEnvelope
import com.agentgrid.mobile.network.ControlSigner
import java.util.Base64
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class ControlSignerTest {
    @Test
    fun `签名原文与 Swift 规范一致`() {
        val envelope = SignedControlEnvelope(
            messageId = "6f539e96-6bce-4fdc-94d5-3cf4ea755622",
            sentAt = 1_785_067_200_000,
            deviceId = "nova4",
            sequence = 7u,
            nonce = "nonce-7",
            payload = ControlPayload("task-1", ControlAction.APPROVE),
            signature = "",
        )

        assertEquals(
            """
            1
            6f539e96-6bce-4fdc-94d5-3cf4ea755622
            1785067200000
            nova4
            7
            nonce-7
            control.request
            {"action":"approve","taskID":"task-1"}
            """.trimIndent(),
            ControlSigner.signingText(envelope),
        )
    }

    @Test
    fun `相同内容和密钥生成稳定 HMAC`() {
        val secret = ByteArray(32) { 0x42 }
        val envelope = SignedControlEnvelope(
            messageId = "6f539e96-6bce-4fdc-94d5-3cf4ea755622",
            sentAt = 1_785_067_200_000,
            deviceId = "nova4",
            sequence = 7u,
            nonce = "nonce-7",
            payload = ControlPayload("task-1", ControlAction.APPROVE),
            signature = "",
        )

        val first = ControlSigner.sign(envelope, secret)
        val second = ControlSigner.sign(envelope, secret)
        assertEquals(first, second)
        assertEquals(32, Base64.getDecoder().decode(first).size)
        assertNotEquals(first, ControlSigner.sign(envelope.copy(payload = envelope.payload.copy(action = ControlAction.DENY)), secret))
    }
}

