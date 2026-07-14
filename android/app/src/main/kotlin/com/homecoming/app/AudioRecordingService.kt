package com.homecoming.app

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
 * Required because Android blocks microphone access from overlay windows.
 * This service runs as a proper foreground service with microphone permission.
 */
class AudioRecordingService : Service() {
    
    private var mediaRecorder: MediaRecorder? = null
    private var recordingFile: File? = null
    private val binder = AudioRecordingBinder()
    
    companion object {
        private const val TAG = "AudioRecordingService"
        private const val CHANNEL_ID = "audio_recording_channel"
        private const val NOTIFICATION_ID = 1001
    }
    
    inner class AudioRecordingBinder : Binder() {
        fun getService(): AudioRecordingService = this@AudioRecordingService
    }
    
    override fun onBind(intent: Intent?): IBinder {
        Log.d(TAG, "✅ Service bound")
        return binder
    }
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "✅ Service created")
        createNotificationChannel()
        
        // Start foreground immediately (required within 5 seconds)
        startForeground(NOTIFICATION_ID, createNotification("Ready to record"))
    }
    
    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "🛑 Service destroyed")
        stopRecording()
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Voice Recording",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when Kai is recording your voice"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
            Log.d(TAG, "✅ Notification channel created")
        }
    }
    
    private fun createNotification(text: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Kai Voice Input")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }
    
    /**
     * Start recording audio.
     * @return Path to the recording file, or null if failed
     */
    fun startRecording(): String? {
        Log.d(TAG, "🎤 startRecording() called")
        
        // Stop any existing recording
        if (mediaRecorder != null) {
            Log.w(TAG, "⚠️ Stopping existing recording first")
            stopRecording()
        }
        
        try {
            // Update notification
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(NOTIFICATION_ID, createNotification("🎤 Recording..."))
            
            // Create output file
            val cacheDir = applicationContext.cacheDir
            recordingFile = File.createTempFile("voice_", ".m4a", cacheDir)
            Log.d(TAG, "📁 Recording to: ${recordingFile?.absolutePath}")
            
            // Create and configure MediaRecorder with service context
            mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            
            mediaRecorder?.apply {
                setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioEncodingBitRate(64000)
                setAudioSamplingRate(16000)
                setOutputFile(recordingFile?.absolutePath)
                
                prepare()
                start()
                Log.d(TAG, "✅ MediaRecorder started")
            }
            
            // Check microphone amplitude after a brief delay
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                mediaRecorder?.let { recorder ->
                    try {
                        val amplitude = recorder.maxAmplitude
                        Log.d(TAG, "🎤 Microphone amplitude: $amplitude ${if (amplitude == 0) "⚠️ NO AUDIO!" else "✅"}")
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Could not check amplitude", e)
                    }
                }
            }, 500)
            
            return recordingFile?.absolutePath
            
        } catch (e: IOException) {
            Log.e(TAG, "❌ Failed to start recording", e)
            mediaRecorder?.release()
            mediaRecorder = null
            return null
        }
    }
    
    /**
     * Stop recording audio.
     * @return Path to the recording file, or null if not recording
     */
    fun stopRecording(): String? {
        Log.d(TAG, "🛑 stopRecording() called")
        
        val filePath = recordingFile?.absolutePath
        
        if (mediaRecorder != null) {
            try {
                mediaRecorder?.stop()
                Log.d(TAG, "✅ MediaRecorder stopped")
                
                // Check file size
                recordingFile?.let { file ->
                    if (file.exists()) {
                        val size = file.length()
                        Log.d(TAG, "📊 File size: $size bytes ${if (size < 1000) "⚠️ TOO SMALL!" else "✅"}")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error stopping MediaRecorder", e)
            } finally {
                mediaRecorder?.release()
                mediaRecorder = null
            }
        }
        
        // Update notification
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, createNotification("Ready to record"))
        
        return filePath
    }
    
    /**
     * Check if currently recording.
     */
    fun isRecording(): Boolean {
        return mediaRecorder != null
    }

    /**
     * Get the current peak amplitude from MediaRecorder (0-32767).
     * Returns 0 if not recording or on error.
     * Note: maxAmplitude resets after each call (it's a peak-since-last-call meter).
     */
    fun getAmplitude(): Int {
        return try { mediaRecorder?.maxAmplitude ?: 0 } catch (e: Exception) { 0 }
    }
}
