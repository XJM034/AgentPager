package com.agentgrid.mobile

import com.agentgrid.mobile.domain.AgentActivity
import com.agentgrid.mobile.domain.AgentLifecycle
import com.agentgrid.mobile.render.PixelMotionEngine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PixelMotionEngineTest {
    @Test
    fun `像素状态使用连续强度与连续位移`() {
        val first = PixelMotionEngine.sample(
            AgentLifecycle.RUNNING,
            AgentActivity.EDITING,
            0.100,
        )
        val second = PixelMotionEngine.sample(
            AgentLifecycle.RUNNING,
            AgentActivity.EDITING,
            0.116,
        )

        assertEquals(9, first.size)
        assertTrue(first.zip(second).any { (lhs, rhs) ->
            kotlin.math.abs(lhs.intensity - rhs.intensity) > 0.0001f ||
                kotlin.math.abs(lhs.offsetX - rhs.offsetX) > 0.0001f ||
                kotlin.math.abs(lhs.offsetY - rhs.offsetY) > 0.0001f
        })
        assertTrue(first.zip(second).all { (lhs, rhs) ->
            kotlin.math.abs(lhs.intensity - rhs.intensity) < 0.30f &&
                kotlin.math.abs(lhs.offsetX - rhs.offsetX) < 0.30f &&
                kotlin.math.abs(lhs.offsetY - rhs.offsetY) < 0.30f
        })
        assertTrue(first.all {
            kotlin.math.abs(it.offsetX) <= 1f && kotlin.math.abs(it.offsetY) <= 1f
        })
    }

    @Test
    fun `每个亮像素拥有独立三层 Bloom`() {
        val lit = PixelMotionEngine.glowLayers(0.82f, 1f)
        val dark = PixelMotionEngine.glowLayers(0f, 1f)

        assertEquals(3, lit.size)
        assertTrue(lit.all { it.opacity > 0f && it.blurRadius > 0f })
        assertTrue(lit[0].opacity > lit[1].opacity)
        assertTrue(lit[1].opacity > lit[2].opacity)
        assertTrue(dark.all { it.opacity == 0f })
    }
}
