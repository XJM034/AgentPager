package com.agentgrid.mobile

import com.agentgrid.mobile.domain.AgentLifecycle
import org.junit.Assert.assertEquals
import org.junit.Test

class ScreenBrightnessPolicyTest {
    @Test
    fun `活动任务使用用户设置的亮度`() {
        val activeLifecycles = listOf(
            AgentLifecycle.STARTING,
            AgentLifecycle.RUNNING,
            AgentLifecycle.WAITING_APPROVAL,
            AgentLifecycle.WAITING_ANSWER,
        )

        activeLifecycles.forEach { lifecycle ->
            assertEquals(
                0.42f,
                ScreenBrightnessPolicy.brightnessFor(lifecycle, 0.42f),
                0.0001f,
            )
        }
    }

    @Test
    fun `没有活动任务时使用空闲亮度`() {
        val inactiveLifecycles = listOf(
            null,
            AgentLifecycle.OFFLINE,
            AgentLifecycle.IDLE,
            AgentLifecycle.SUCCEEDED,
            AgentLifecycle.INTERRUPTED,
        )

        inactiveLifecycles.forEach { lifecycle ->
            assertEquals(
                ScreenBrightnessPolicy.IDLE_BRIGHTNESS,
                ScreenBrightnessPolicy.brightnessFor(lifecycle, 0.8f),
                0.0001f,
            )
        }
    }

    @Test
    fun `任务亮度会限制在系统允许范围内`() {
        assertEquals(
            ScreenBrightnessPolicy.MIN_ACTIVE_BRIGHTNESS,
            ScreenBrightnessPolicy.sanitizeActiveBrightness(-1f),
            0.0001f,
        )
        assertEquals(
            ScreenBrightnessPolicy.MAX_ACTIVE_BRIGHTNESS,
            ScreenBrightnessPolicy.sanitizeActiveBrightness(2f),
            0.0001f,
        )
        assertEquals(
            ScreenBrightnessPolicy.DEFAULT_ACTIVE_BRIGHTNESS,
            ScreenBrightnessPolicy.sanitizeActiveBrightness(Float.NaN),
            0.0001f,
        )
    }
}
