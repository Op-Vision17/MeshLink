package com.meshlink.meshlink.mesh

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Process
import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean

/**
 * High-Fidelity, Continuous Stream Full-Duplex VoIP Audio Engine.
 *
 * Captures 16kHz Mono 16-bit PCM audio (with hardware AEC, AGC, and NS),
 * streams exact 640-byte (20ms) frames over UDP port 8889 with urgent audio thread priority,
 * and plays back using primed continuous streaming to eliminate all periodic audio dropouts.
 */
class VoIPEngine(private val context: Context) {
    companion object {
        private const val TAG = "VoIPEngine"
        const val SAMPLE_RATE = 16000
        const val FRAME_SIZE_BYTES = 640 // 20ms frame at 16kHz 16-bit mono (320 samples * 2 bytes)
        const val DEFAULT_VOIP_PORT = 8889
        private const val JITTER_QUEUE_CAPACITY = 30 // ~600ms queue capacity
    }

    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var gainControl: AutomaticGainControl? = null

    private var udpSocket: DatagramSocket? = null
    private var senderThread: Thread? = null
    private var receiverThread: Thread? = null
    private var playbackThread: Thread? = null

    private val jitterQueue = ArrayBlockingQueue<ByteArray>(JITTER_QUEUE_CAPACITY)
    private val isCallActive = AtomicBoolean(false)
    private val isMuted = AtomicBoolean(false)
    private var previousAudioMode: Int = AudioManager.MODE_NORMAL

    /**
     * Starts live voice call audio streaming to peer IP.
     */
    @Synchronized
    fun startCall(targetIp: String, port: Int = DEFAULT_VOIP_PORT): Boolean {
        if (isCallActive.get()) {
            Log.w(TAG, "VoIP call already active")
            return true
        }

        return try {
            Log.i(TAG, "Starting continuous HD VoIP call to $targetIp:$port")

            // 1. Configure Audio Manager for communication mode & speaker
            previousAudioMode = audioManager.mode
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            audioManager.isSpeakerphoneOn = true

            // 2. Initialize AudioRecord (Microphone capture) with generous hardware buffer
            val minRecordBuf = AudioRecord.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            ).coerceAtLeast(FRAME_SIZE_BYTES * 16)

            val record = AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                minRecordBuf
            )

            if (record.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "AudioRecord failed to initialize")
                restoreAudioMode()
                return false
            }

            // Enable hardware DSP: AEC (Echo Cancellation), AGC (Gain Control), NS (Noise Suppression)
            val sessionId = record.audioSessionId
            if (AcousticEchoCanceler.isAvailable()) {
                try {
                    echoCanceler = AcousticEchoCanceler.create(sessionId)?.apply {
                        enabled = true
                        Log.i(TAG, "Hardware AcousticEchoCanceler enabled")
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Could not enable AcousticEchoCanceler: ${e.message}")
                }
            }
            if (AutomaticGainControl.isAvailable()) {
                try {
                    gainControl = AutomaticGainControl.create(sessionId)?.apply {
                        enabled = true
                        Log.i(TAG, "Hardware AutomaticGainControl enabled")
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Could not enable AutomaticGainControl: ${e.message}")
                }
            }
            if (NoiseSuppressor.isAvailable()) {
                try {
                    noiseSuppressor = NoiseSuppressor.create(sessionId)?.apply {
                        enabled = true
                        Log.i(TAG, "Hardware NoiseSuppressor enabled")
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Could not enable NoiseSuppressor: ${e.message}")
                }
            }

            // 3. Initialize AudioTrack (Speaker playback) with generous buffer
            val minTrackBuf = AudioTrack.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            ).coerceAtLeast(FRAME_SIZE_BYTES * 16)

            val track = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build()
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(SAMPLE_RATE)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                            .build()
                    )
                    .setBufferSizeInBytes(minTrackBuf)
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .build()
            } else {
                @Suppress("DEPRECATION")
                AudioTrack(
                    AudioManager.STREAM_VOICE_CALL,
                    SAMPLE_RATE,
                    AudioFormat.CHANNEL_OUT_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    minTrackBuf,
                    AudioTrack.MODE_STREAM
                )
            }

            if (track.state != AudioTrack.STATE_INITIALIZED) {
                Log.e(TAG, "AudioTrack failed to initialize")
                record.release()
                restoreAudioMode()
                return false
            }

            // Prime AudioTrack with a small lead-in (40ms silence) to eliminate initial playback clicks
            val primingSilence = ByteArray(FRAME_SIZE_BYTES * 2)
            track.write(primingSilence, 0, primingSilence.size)

            // 4. Initialize UDP Socket
            val socket = try {
                DatagramSocket(port)
            } catch (e: Exception) {
                Log.w(TAG, "Port $port bound, using dynamic port: ${e.message}")
                DatagramSocket()
            }
            socket.sendBufferSize = 128 * 1024
            socket.receiveBufferSize = 128 * 1024

            audioRecord = record
            audioTrack = track
            udpSocket = socket
            jitterQueue.clear()
            isCallActive.set(true)

            record.startRecording()
            track.play()

            val targetAddress = InetAddress.getByName(targetIp)

            // 5. Transmitter Thread (Microphone -> UDP)
            senderThread = Thread({
                Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
                val buffer = ByteArray(FRAME_SIZE_BYTES)
                while (isCallActive.get() && !Thread.currentThread().isInterrupted) {
                    val bytesRead = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        record.read(buffer, 0, FRAME_SIZE_BYTES, AudioRecord.READ_BLOCKING)
                    } else {
                        var readTotal = 0
                        while (readTotal < FRAME_SIZE_BYTES && isCallActive.get()) {
                            val r = record.read(buffer, readTotal, FRAME_SIZE_BYTES - readTotal)
                            if (r > 0) readTotal += r else break
                        }
                        readTotal
                    }

                    if (bytesRead == FRAME_SIZE_BYTES && !isMuted.get()) {
                        try {
                            val packet = DatagramPacket(buffer, FRAME_SIZE_BYTES, targetAddress, port)
                            socket.send(packet)
                        } catch (e: Exception) {
                            if (!isCallActive.get()) break
                        }
                    }
                }
            }, "VoIP-Transmitter").apply { start() }

            // 6. Receiver Thread (UDP Socket -> Jitter Queue)
            receiverThread = Thread({
                Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
                val recvBuffer = ByteArray(FRAME_SIZE_BYTES + 128)
                while (isCallActive.get() && !Thread.currentThread().isInterrupted) {
                    try {
                        val packet = DatagramPacket(recvBuffer, recvBuffer.size)
                        socket.receive(packet)
                        val length = packet.length
                        if (length > 0) {
                            val frame = packet.data.copyOfRange(packet.offset, packet.offset + length)
                            if (!jitterQueue.offer(frame)) {
                                jitterQueue.poll()
                                jitterQueue.offer(frame)
                            }
                        }
                    } catch (e: Exception) {
                        if (!isCallActive.get()) break
                    }
                }
            }, "VoIP-NetworkReceiver").apply { start() }

            // 7. Continuous Playback Thread (Jitter Queue -> AudioTrack with hardware clock pacing)
            playbackThread = Thread({
                Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
                while (isCallActive.get() && !Thread.currentThread().isInterrupted) {
                    try {
                        val frame = jitterQueue.take()
                        if (frame.isNotEmpty()) {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                track.write(frame, 0, frame.size, AudioTrack.WRITE_BLOCKING)
                            } else {
                                @Suppress("DEPRECATION")
                                track.write(frame, 0, frame.size)
                            }
                        }
                    } catch (e: InterruptedException) {
                        break
                    } catch (e: Exception) {
                        if (!isCallActive.get()) break
                    }
                }
            }, "VoIP-ContinuousPlayer").apply { start() }

            Log.i(TAG, "Continuous HD VoIP call engine active")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start VoIP call: ${e.message}", e)
            stopCall()
            false
        }
    }

    /**
     * Gracefully stops live voice call and frees audio resources.
     */
    @Synchronized
    fun stopCall(): Boolean {
        if (!isCallActive.getAndSet(false)) {
            return true
        }

        Log.i(TAG, "Stopping VoIP call")

        try {
            senderThread?.interrupt()
            receiverThread?.interrupt()
            playbackThread?.interrupt()
            udpSocket?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Error closing socket: ${e.message}")
        }

        try {
            audioRecord?.apply {
                if (recordingState == AudioRecord.RECORDSTATE_RECORDING) stop()
                release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping AudioRecord: ${e.message}")
        }

        try {
            audioTrack?.apply {
                if (playState == AudioTrack.PLAYSTATE_PLAYING) stop()
                release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping AudioTrack: ${e.message}")
        }

        try {
            echoCanceler?.release()
            gainControl?.release()
            noiseSuppressor?.release()
        } catch (_: Exception) {}

        restoreAudioMode()
        jitterQueue.clear()

        audioRecord = null
        audioTrack = null
        echoCanceler = null
        gainControl = null
        noiseSuppressor = null
        udpSocket = null
        senderThread = null
        receiverThread = null
        playbackThread = null
        isMuted.set(false)

        Log.i(TAG, "VoIP call stopped successfully")
        return true
    }

    /**
     * Sets local microphone mute state.
     */
    fun setMuted(muted: Boolean) {
        isMuted.set(muted)
        Log.i(TAG, "VoIP microphone muted: $muted")
    }

    /**
     * Toggles between loud speaker and earpiece.
     */
    fun setSpeakerphoneOn(speakerOn: Boolean) {
        try {
            audioManager.isSpeakerphoneOn = speakerOn
            Log.i(TAG, "VoIP speakerphone enabled: $speakerOn")
        } catch (e: Exception) {
            Log.w(TAG, "Could not toggle speakerphone: ${e.message}")
        }
    }

    fun isCallRunning(): Boolean = isCallActive.get()

    private fun restoreAudioMode() {
        try {
            audioManager.mode = previousAudioMode
            audioManager.isSpeakerphoneOn = false
        } catch (e: Exception) {
            Log.w(TAG, "Could not restore audio mode: ${e.message}")
        }
    }
}
