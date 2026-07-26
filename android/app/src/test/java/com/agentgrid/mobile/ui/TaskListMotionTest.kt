package com.agentgrid.mobile.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class TaskListMotionTest {
    @Test
    fun `锚点始终保留一个物理像素在视口内`() {
        val anchorHeightPx = 3
        val scrollOffsetPx = taskListAnchorScrollOffsetPx(anchorHeightPx)

        assertEquals(1, anchorHeightPx - scrollOffsetPx)
    }
}
