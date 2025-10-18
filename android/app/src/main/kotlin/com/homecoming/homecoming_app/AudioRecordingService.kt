package com.homecoming.homecoming_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.MediaRecorder
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.IOException

/**
 * Foreground service for audio recording.
 * Runs as a foreground service to maintain microphone access while overlay is active.
 */
class AudioRecordingService : Service() {
    private val TAG = "AudioRecordingService"
    private val CHANNEL_ID = "AudioRecordingChannel"
    private val NOTIFICATION_ID = 2001
    
    private var mediaRecorder: MediaRecorder? = null
    private var recordingFile: File? = null
    private val binder = AudioRecordingBinder()
    
    inner class AudioRecordingBinder : Binder() {
        fun getService(): AudioRecordingService = this@AudioRecordingService
    }
    
    override fun onBind(intent: Intent?): IBinder {
        return binder
    }
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "🎤 AudioRecordingService created")
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "🎤 AudioRecordingService started")
        return START_STICKY
    }
    
    override fun onDestroy() {
        super.onDestroy()
        stopRecordingInternal()
        Log.d(TAG, "🎤 AudioRecordingService destroyed")
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Audio Recording",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Recording audio for voice input"
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Voice Recording Active")
            .setContentText("Kai is listening...")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }
    
    fun startRecording(): String? {
        try {
            // Stop any existing recording
            if (mediaRecorder != null) {
                Log.w(TAG, "⚠️ MediaRecorder already exists, stopping previous recording")
                stopRecordingInternal()
            }
            
            // Create output file
            val outputDir = cacheDir
            recordingFile = File.createTempFile("voice_", ".m4a", outputDir)
            
            Log.d(TAG, "📁 Output directory: ${outputDir.absolutePath}")
            Log.d(TAG, "📄 Recording file: ${recordingFile?.absolutePath}")
            Log.d(TAG, "🎤 Starting recording in foreground service...")
            
            // Create and configure MediaRecorder
            mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this).also { Log.d(TAG, "✅ MediaRecorder created (Android S+)") }
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder().also { Log.d(TAG, "✅ MediaRecorder created (Legacy)") }
            }
            
            mediaRecorder?.apply {
                Log.d(TAG, "🔧 Setting audio source: MIC")
                setAudioSource(MediaRecorder.AudioSource.MIC)
                
                Log.d(TAG, "🔧 Setting output format: MPEG_4")
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                
                Log.d(TAG, "🔧 Setting audio encoder: AAC")
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                
                Log.d(TAG, "🔧 Setting bitrate: 128000")
                setAudioEncodingBitRate(128000)
                
                Log.d(TAG, "🔧 Setting sample rate: 44100")
                setAudioSamplingRate(44100)
                
                Log.d(TAG, "🔧 Setting output file: ${recordingFile?.absolutePath}")
                setOutputFile(recordingFile?.absolutePath)
                
                Log.d(TAG, "🔄 Preparing MediaRecorder...")
                prepare()
                Log.d(TAG, "✅ MediaRecorder prepared")
                
                Log.d(TAG, "▶️ Starting recording...")
                start()
                Log.d(TAG, "✅ Recording started successfully in foreground service!")
            }
            
            return recordingFile?.absolutePath
            
        } catch (e: IOException) {
            Log.e(TAG, "❌ MediaRecorder prepare/start failed", e)
            stopRecordingInternal()
            return null
        } catch (e: Exception) {
            Log.e(TAG, "❌ Unexpected error starting recording", e)
            stopRecordingInternal()
            return null
        }
    }
    
    fun stopRecording(): String? {
        val filePath = recordingFile?.absolutePath
        
        Log.d(TAG, "⏹️ Stopping recording in foreground service...")
        
        mediaRecorder?.let { recorder ->
            try {
                recorder.stop()
                Log.d(TAG, "✅ Recording stopped successfully")
                
                recordingFile?.let { file ->
                    if (file.exists()) {
                        val fileSize = file.length()
                        Log.d(TAG, "📊 Recording file size: $fileSize bytes")
                        when {
                            fileSize == 0L -> Log.e(TAG, "❌ WARNING: Recording file is EMPTY (0 bytes)!")
                            fileSize < 1000 -> Log.w(TAG, "⚠️ WARNING: Recording file is very small ($fileSize bytes)")
                            else -> Log.d(TAG, "✅ Recording file size looks good")
                        }
                    } else {
                        Log.e(TAG, "❌ Recording file does not exist: $filePath")
                    }
                }
                
            } catch (e: IllegalStateException) {
                Log.e(TAG, "❌ Error stopping MediaRecorder (illegal state)", e)
            } catch (e: RuntimeException) {
                Log.e(TAG, "❌ Error stopping MediaRecorder (runtime error)", e)
            } finally {
                try {
                    recorder.release()
                    Log.d(TAG, "✅ MediaRecorder released")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Error releasing MediaRecorder", e)
                }
                mediaRecorder = null
            }
        } ?: Log.w(TAG, "⚠️ MediaRecorder is null, nothing to stop")
        
        return filePath
    }
    
    private fun stopRecordingInternal() {
        try {
            mediaRecorder?.stop()
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping recorder: ${e.message}")
        }
        mediaRecorder?.release()
        mediaRecorder = null
        recordingFile = null
    }
    
    fun isRecording(): Boolean {
        return mediaRecorder != null
    }
}
