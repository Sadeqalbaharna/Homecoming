package com.homecoming.app

// KaiMicStreamPlugin — streams raw PCM16 LE @ 16 kHz from the microphone
// to Dart via a Flutter EventChannel.
//
// Dart side subscribes to 'com.homecoming.app/mic_stream' and receives
// ByteArray chunks that it converts to Float32 for sherpa-onnx.
//
// The channel uses Flutter v2 embedding (EventChannel / StreamHandler) —
// no deprecated PluginRegistry.Registrar.

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

class KaiMicStreamPlugin {

    companion object {
        const val CHANNEL = "com.homecoming.app/mic_stream"
        private const val TAG = "KaiMicStreamPlugin"
        private const val SAMPLE_RATE = 16000
    }

    private var audioRecord: AudioRecord? = null
    @Volatile private var streaming = false
    // Nulled out in onCancel so queued main-thread lambdas stop calling success()
    // even if they fire after the Flutter engine has detached.
    @Volatile private var activeSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger) {
        EventChannel(messenger, CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                activeSink = events
                startStreaming(events)
            }

            override fun onCancel(arguments: Any?) {
                activeSink = null   // drop the sink reference first
                stopStreaming()
            }
        })
        Log.d(TAG, "EventChannel registered on $CHANNEL")
    }

    private fun startStreaming(events: EventChannel.EventSink) {
        stopStreaming()   // clean up any previous session

        val bufferSize = maxOf(
            AudioRecord.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            ) * 2,
            3200,   // ≥ 100 ms at 16 kHz, 16-bit mono
        )

        val rec = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize,
        )

        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "AudioRecord failed to initialise — no mic permission?")
            mainHandler.post { activeSink?.error("MIC_INIT_FAILED", "AudioRecord not initialised", null) }
            rec.release()
            return
        }

        audioRecord = rec
        streaming = true
        rec.startRecording()
        Log.d(TAG, "AudioRecord started (bufferSize=$bufferSize)")

        // Background reader thread — sends chunks to Dart via the main thread.
        // Guards:
        //   1. streaming == false  → stopStreaming() was called, thread exits cleanly
        //   2. activeSink == null  → onCancel fired (or engine detached), skip send
        //   3. try/catch around success() → swallows any FlutterJNI-detached exception
        //      without spamming logcat
        Thread {
            val chunk = ByteArray(bufferSize / 2)   // ~50 ms per chunk
            while (streaming) {
                val read = rec.read(chunk, 0, chunk.size)
                if (read > 0) {
                    val data = chunk.copyOf(read)
                    mainHandler.post {
                        val sink = activeSink ?: return@post
                        if (!streaming) return@post
                        try {
                            sink.success(data)
                        } catch (_: Exception) {
                            // FlutterJNI detached (hot-restart / engine shutdown).
                            // Kill the loop silently — no logcat spam.
                            activeSink = null
                            streaming = false
                        }
                    }
                } else if (read < 0) {
                    Log.e(TAG, "AudioRecord.read() error: $read")
                    break
                }
            }
            Log.d(TAG, "Reader thread exited")
        }.apply {
            isDaemon = true
            name = "KaiMicReader"
            start()
        }
    }

    /** Called from MainActivity.onDestroy() to ensure the reader thread stops
     *  before the Flutter engine / JNI bridge tears down. Without this, the
     *  reader keeps posting to the main handler and produces a flood of
     *  "FlutterJNI was detached" warnings in logcat on every hot restart. */
    fun destroy() {
        activeSink = null   // null first so any in-flight lambda is a no-op
        stopStreaming()
    }

    private fun stopStreaming() {
        streaming = false
        audioRecord?.let {
            try { it.stop() } catch (_: Exception) {}
            it.release()
        }
        audioRecord = null
        Log.d(TAG, "AudioRecord stopped")
    }
}
