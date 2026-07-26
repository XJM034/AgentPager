package com.agentgrid.mobile

import com.agentgrid.mobile.domain.AgentLifecycle
import com.agentgrid.mobile.domain.AgentSource
import com.agentgrid.mobile.domain.TaskSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ArcadeSoundsTest {
    @Test
    fun `首次快照只建立基线不播放历史状态`() {
        val tracker = TaskSoundTracker()

        assertNull(tracker.nextCue(listOf(task("one", AgentLifecycle.RUNNING))))
    }

    @Test
    fun `每个任务独立检测完成状态`() {
        val tracker = TaskSoundTracker()
        tracker.nextCue(
            listOf(
                task("running", AgentLifecycle.RUNNING),
                task("done", AgentLifecycle.RUNNING),
            ),
        )

        val cue = tracker.nextCue(
            listOf(
                task("running", AgentLifecycle.RUNNING, updatedAt = 20),
                task("done", AgentLifecycle.SUCCEEDED, updatedAt = 30),
            ),
        )

        assertEquals(ArcadeSoundCue.TASK_COMPLETE, cue)
    }

    @Test
    fun `新任务首个快照已进入运行态仍播放接收音`() {
        val tracker = TaskSoundTracker()
        tracker.nextCue(emptyList())

        val cue = tracker.nextCue(
            listOf(task("new", AgentLifecycle.RUNNING)),
        )

        assertEquals(ArcadeSoundCue.TASK_ACKNOWLEDGE, cue)
    }

    @Test
    fun `模拟器切换状态会按真实生命周期播放对应提示音`() {
        val tracker = TaskSoundTracker()
        tracker.nextCue(emptyList())

        assertNull(
            tracker.nextCue(listOf(task("agentgrid-simulator", AgentLifecycle.STARTING))),
        )
        assertEquals(
            ArcadeSoundCue.TASK_ACKNOWLEDGE,
            tracker.nextCue(
                listOf(task("agentgrid-simulator", AgentLifecycle.RUNNING, updatedAt = 20)),
            ),
        )
        assertEquals(
            ArcadeSoundCue.INPUT_REQUIRED,
            tracker.nextCue(
                listOf(
                    task(
                        "agentgrid-simulator",
                        AgentLifecycle.WAITING_APPROVAL,
                        updatedAt = 30,
                    ),
                ),
            ),
        )
        assertEquals(
            ArcadeSoundCue.TASK_ACKNOWLEDGE,
            tracker.nextCue(
                listOf(task("agentgrid-simulator", AgentLifecycle.RUNNING, updatedAt = 40)),
            ),
        )
        assertEquals(
            ArcadeSoundCue.TASK_COMPLETE,
            tracker.nextCue(
                listOf(task("agentgrid-simulator", AgentLifecycle.SUCCEEDED, updatedAt = 50)),
            ),
        )
        assertEquals(
            ArcadeSoundCue.TASK_INTERRUPTED,
            tracker.nextCue(
                listOf(task("agentgrid-simulator", AgentLifecycle.INTERRUPTED, updatedAt = 60)),
            ),
        )
    }

    @Test
    fun `等待输入优先于同批完成提示`() {
        val tracker = TaskSoundTracker()
        tracker.nextCue(
            listOf(
                task("approval", AgentLifecycle.RUNNING),
                task("done", AgentLifecycle.RUNNING),
            ),
        )

        val cue = tracker.nextCue(
            listOf(
                task("approval", AgentLifecycle.WAITING_APPROVAL, updatedAt = 20),
                task("done", AgentLifecycle.SUCCEEDED, updatedAt = 30),
            ),
        )

        assertEquals(ArcadeSoundCue.INPUT_REQUIRED, cue)
    }

    @Test
    fun `普通内容更新与静音任务不播放`() {
        val tracker = TaskSoundTracker()
        tracker.nextCue(listOf(task("one", AgentLifecycle.RUNNING)))

        assertNull(
            tracker.nextCue(
                listOf(task("one", AgentLifecycle.RUNNING, updatedAt = 20)),
            ),
        )
        assertNull(
            tracker.nextCue(
                listOf(
                    task(
                        "one",
                        AgentLifecycle.SUCCEEDED,
                        updatedAt = 30,
                        isMuted = true,
                    ),
                ),
            ),
        )
    }

    @Test
    fun `关闭总开关时仍更新状态基线且重新开启不补播`() {
        val tracker = TaskSoundTracker()
        tracker.nextCue(listOf(task("one", AgentLifecycle.RUNNING)))

        assertNull(
            tracker.nextCue(
                listOf(task("one", AgentLifecycle.SUCCEEDED, updatedAt = 20)),
                soundEnabled = false,
            ),
        )
        assertNull(
            tracker.nextCue(
                listOf(task("one", AgentLifecycle.SUCCEEDED, updatedAt = 20)),
                soundEnabled = true,
            ),
        )
    }

    @Test
    fun `恢复出的四类街机音都有稳定且非静音的波形`() {
        val expectedLengths = mapOf(
            ArcadeSoundCue.TASK_ACKNOWLEDGE to 3_520,
            ArcadeSoundCue.INPUT_REQUIRED to 9_600,
            ArcadeSoundCue.TASK_COMPLETE to 17_600,
            ArcadeSoundCue.TASK_INTERRUPTED to 8_000,
        )
        ArcadeSoundCue.entries.forEach { cue ->
            val first = ArcadeSoundSynthesizer.render(cue, sampleRate = 16_000)
            val second = ArcadeSoundSynthesizer.render(cue, sampleRate = 16_000)

            assertEquals(expectedLengths.getValue(cue), first.size)
            assertTrue(first.any { it != 0.toShort() })
            assertTrue(first.contentEquals(second))
        }

        assertNotEquals(
            ArcadeSoundSynthesizer.render(
                ArcadeSoundCue.TASK_ACKNOWLEDGE,
                sampleRate = 16_000,
            ).contentHashCode(),
            ArcadeSoundSynthesizer.render(
                ArcadeSoundCue.TASK_COMPLETE,
                sampleRate = 16_000,
            ).contentHashCode(),
        )
    }

    @Test
    fun `完成提示使用源码第二版的厚方波而不是窄脉冲`() {
        val sampleRate = 16_000
        val samples = ArcadeSoundSynthesizer.render(
            ArcadeSoundCue.TASK_COMPLETE,
            sampleRate,
        )
        val steadyStart = (sampleRate * 0.01).toInt()
        val steadyEnd = (sampleRate * 0.06).toInt()
        val steadySamples = samples.sliceArray(steadyStart until steadyEnd)
        val positiveRatio = steadySamples.count { it > 0 }.toDouble() / steadySamples.size

        assertTrue(positiveRatio in 0.42..0.58)
    }

    private fun task(
        id: String,
        lifecycle: AgentLifecycle,
        updatedAt: Long = 10,
        isMuted: Boolean = false,
    ) = TaskSnapshot(
        id = id,
        source = AgentSource.CODEX_DESKTOP,
        projectName = "AgentGrid",
        lifecycle = lifecycle,
        startedAt = 1,
        updatedAt = updatedAt,
        completedAt = if (lifecycle == AgentLifecycle.SUCCEEDED) updatedAt else null,
        isMuted = isMuted,
    )
}
