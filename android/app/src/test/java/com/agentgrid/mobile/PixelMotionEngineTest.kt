package com.agentgrid.mobile

import com.agentgrid.mobile.domain.AgentActivity
import com.agentgrid.mobile.domain.AgentLifecycle
import com.agentgrid.mobile.render.PixelMotionEngine
import com.agentgrid.mobile.render.PixelRenderState
import org.junit.Assert.assertFalse
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
    fun `每个亮像素保留原有三层 Bloom`() {
        val lit = PixelMotionEngine.glowLayers(0.82f, 1f)
        val dark = PixelMotionEngine.glowLayers(0f, 1f)

        assertEquals(3, lit.size)
        assertTrue(lit.all { it.opacity > 0f && it.blurRadius > 0f })
        assertTrue(lit[0].opacity > lit[1].opacity)
        assertTrue(lit[1].opacity > lit[2].opacity)
        assertTrue(lit[0].opacity > 0.60f)
        assertTrue(lit[2].opacity > 0.15f)
        assertTrue(lit[2].blurRadius >= 18f)
        assertTrue(dark.all { it.opacity == 0f })
    }

    @Test
    fun `帧调度保留原有节奏并让终态停止空转`() {
        assertEquals(
            60L,
            PixelMotionEngine.targetFps(
                lifecycle = AgentLifecycle.RUNNING,
                elapsed = 2.0,
                motionEnabled = true,
            ),
        )
        assertEquals(
            30L,
            PixelMotionEngine.targetFps(
                lifecycle = AgentLifecycle.IDLE,
                elapsed = 2.0,
                motionEnabled = true,
            ),
        )
        assertEquals(
            0L,
            PixelMotionEngine.targetFps(
                lifecycle = AgentLifecycle.SUCCEEDED,
                elapsed = 1.2,
                motionEnabled = true,
            ),
        )
        assertEquals(
            0L,
            PixelMotionEngine.targetFps(
                lifecycle = AgentLifecycle.RUNNING,
                elapsed = 0.2,
                motionEnabled = false,
            ),
        )
    }

    @Test
    fun `帧调度容忍设备时钟误差但不破坏三十帧节流`() {
        val firstFrame = 10_000_000_000L
        val nextVsync = firstFrame + 16_650_000L

        assertTrue(
            PixelMotionEngine.shouldRenderFrame(
                lastFrameNanos = firstFrame,
                frameTimeNanos = nextVsync,
                fps = 60,
            ),
        )
        assertFalse(
            PixelMotionEngine.shouldRenderFrame(
                lastFrameNanos = firstFrame,
                frameTimeNanos = nextVsync,
                fps = 30,
            ),
        )
    }

    @Test
    fun `第一排状态和中断态保留可辨识的像素图案`() {
        val cases = listOf(
            AgentLifecycle.OFFLINE to null,
            AgentLifecycle.IDLE to null,
            AgentLifecycle.STARTING to null,
            AgentLifecycle.RUNNING to AgentActivity.EDITING,
            AgentLifecycle.INTERRUPTED to null,
        )

        cases.forEach { (lifecycle, activity) ->
            val samples = PixelMotionEngine.sample(lifecycle, activity, 1.6)
            val ranges = listOf(
                samples.rangeOf { it.intensity },
                samples.rangeOf { it.offsetX },
                samples.rangeOf { it.offsetY },
                samples.rangeOf { it.scale },
            )

            assertTrue(
                "状态 $lifecycle 的稳定帧缺少可辨识图案",
                ranges.max() >= 0.08f,
            )
        }
    }

    @Test
    fun `相同模拟状态的新版本会重启动效`() {
        val previous = PixelRenderState(
            lifecycle = AgentLifecycle.INTERRUPTED,
            revision = 10,
            changedAtNanos = 100,
        )
        val replay = previous.copy(
            revision = 11,
            changedAtNanos = 200,
        )
        val unchanged = previous.copy(changedAtNanos = 300)

        assertTrue(replay.requiresMotionRestart(previous))
        assertFalse(unchanged.requiresMotionRestart(previous))
    }

    @Test
    fun `成功态最终收束为像素勾而不是满格`() {
        val samples = PixelMotionEngine.sample(
            AgentLifecycle.SUCCEEDED,
            null,
            1.2,
        )
        val litIndices = samples
            .filter { it.intensity >= 0.80f }
            .map { it.index }
            .toSet()
        val darkIndices = samples
            .filter { it.intensity <= 0.10f }
            .map { it.index }
            .toSet()

        assertEquals(setOf(2, 5, 6, 7), litIndices)
        assertEquals(setOf(0, 1, 3, 4, 8), darkIndices)
    }

    @Test
    fun `等待回答态使用中排三点依次提示`() {
        val samples = PixelMotionEngine.sample(
            AgentLifecycle.WAITING_ANSWER,
            null,
            0.20,
        )

        assertTrue(samples[3].intensity > 0.90f)
        assertTrue(samples[3].intensity > samples[4].intensity)
        assertTrue(samples[4].intensity >= samples[5].intensity)
        assertTrue(samples.filterIndexed { index, _ -> index !in 3..5 }
            .all { it.intensity < 0.18f })
    }

    @Test
    fun `运行活动在同一时刻拥有不同运动签名`() {
        val activities = AgentActivity.entries
        val signatures = activities.associateWith { activity ->
            PixelMotionEngine.sample(
                AgentLifecycle.RUNNING,
                activity,
                0.74,
            )
        }

        activities.forEachIndexed { index, lhs ->
            activities.drop(index + 1).forEach { rhs ->
                val distance = signatures.getValue(lhs)
                    .zip(signatures.getValue(rhs))
                    .sumOf { (first, second) ->
                        kotlin.math.abs(first.intensity - second.intensity).toDouble() +
                            kotlin.math.abs(first.offsetX - second.offsetX) +
                            kotlin.math.abs(first.offsetY - second.offsetY) +
                            kotlin.math.abs(first.scale - second.scale)
                    }
                assertTrue(
                    "活动 $lhs 与 $rhs 的像素签名过于相似",
                    distance > 0.20,
                )
            }
        }
    }

    @Test
    fun `状态过渡从旧帧连续插值到新帧`() {
        val from = PixelMotionEngine.sample(
            AgentLifecycle.IDLE,
            null,
            0.68,
        )
        val to = PixelMotionEngine.sample(
            AgentLifecycle.WAITING_APPROVAL,
            null,
            0.0,
        )

        assertEquals(from, PixelMotionEngine.blendSamples(from, to, 0f))
        assertEquals(to, PixelMotionEngine.blendSamples(from, to, 1f))

        val midpoint = PixelMotionEngine.blendSamples(from, to, 0.5f)
        midpoint.indices.forEach { index ->
            assertEquals(
                (from[index].intensity + to[index].intensity) / 2,
                midpoint[index].intensity,
                0.0001f,
            )
        }
        assertTrue(PixelMotionEngine.transitionProgress(0.08) > 0.33f)
        assertEquals(1f, PixelMotionEngine.transitionProgress(0.24), 0.0001f)
    }

    private fun List<com.agentgrid.mobile.render.PixelSample>.rangeOf(
        value: (com.agentgrid.mobile.render.PixelSample) -> Float,
    ): Float = maxOf(value) - minOf(value)
}
