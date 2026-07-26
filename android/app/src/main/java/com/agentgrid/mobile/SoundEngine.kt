package com.agentgrid.mobile

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.VibrationEffect
import android.os.Vibrator
import com.agentgrid.mobile.domain.AgentLifecycle
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.sign
import kotlin.math.sin

class SoundEngine(context: Context) {
    private val executor = Executors.newSingleThreadExecutor()
    private val vibrator = context.getSystemService(Vibrator::class.java)

    fun play(lifecycle: AgentLifecycle) {
        val notes = when (lifecycle) {
            AgentLifecycle.STARTING -> listOf(523, 659)
            AgentLifecycle.WAITING_APPROVAL -> listOf(740, 988)
            AgentLifecycle.WAITING_ANSWER -> listOf(659, 784, 988)
            AgentLifecycle.SUCCEEDED -> listOf(523, 659, 784, 1047)
            AgentLifecycle.FAILED -> listOf(523, 392, 262)
            AgentLifecycle.INTERRUPTED -> listOf(440, 220)
            else -> return
        }
        executor.execute { playNotes(notes) }
        if (lifecycle == AgentLifecycle.FAILED) {
            vibrator?.vibrate(
                VibrationEffect.createWaveform(longArrayOf(0, 80, 70, 110), -1),
            )
        } else if (
            lifecycle == AgentLifecycle.WAITING_APPROVAL ||
            lifecycle == AgentLifecycle.WAITING_ANSWER
        ) {
            vibrator?.vibrate(VibrationEffect.createOneShot(70, 110))
        }
    }

    private fun playNotes(frequencies: List<Int>) {
        val sampleRate = 22_050
        val noteMillis = 80
        val samplesPerNote = sampleRate * noteMillis / 1_000
        val samples = ShortArray(samplesPerNote * frequencies.size)
        frequencies.forEachIndexed { noteIndex, frequency ->
            for (sample in 0 until samplesPerNote) {
                val envelope = 1.0 - sample.toDouble() / samplesPerNote
                val square = sign(sin(2 * PI * frequency * sample / sampleRate))
                samples[noteIndex * samplesPerNote + sample] =
                    (square * envelope * Short.MAX_VALUE * 0.16).toInt().toShort()
            }
        }

        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(samples.size * 2)
            .build()
        track.write(samples, 0, samples.size)
        track.play()
        Thread.sleep((noteMillis * frequencies.size + 30).toLong())
        track.stop()
        track.release()
    }
}

