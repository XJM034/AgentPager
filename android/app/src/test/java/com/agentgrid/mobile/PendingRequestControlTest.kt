package com.agentgrid.mobile

import com.agentgrid.mobile.domain.ControlAction
import com.agentgrid.mobile.domain.PendingRequest
import com.agentgrid.mobile.domain.PendingRequestKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class PendingRequestControlTest {
    @Test
    fun `Android 审批意图只携带用户所选 pending request ID`() {
        val first = PendingRequest(
            taskID = "zcode-session-1",
            requestID = "zcode:first",
            kind = PendingRequestKind.APPROVAL,
            summary = "读取文件 · 等待批准",
        )
        val second = first.copy(
            requestID = "zcode:second",
            summary = "执行工具 · 等待批准",
        )

        assertEquals(
            "zcode:first",
            first.controlIntent(ControlAction.APPROVE)?.pendingRequestID,
        )
        assertEquals(
            "zcode:second",
            second.controlIntent(ControlAction.DENY)?.pendingRequestID,
        )
        assertNull(first.controlIntent(ControlAction.ANSWER))
        val legacyIntent = first.copy(requestID = null).controlIntent(ControlAction.APPROVE)
        assertNotNull(legacyIntent)
        assertNull(legacyIntent?.pendingRequestID)
    }
}
