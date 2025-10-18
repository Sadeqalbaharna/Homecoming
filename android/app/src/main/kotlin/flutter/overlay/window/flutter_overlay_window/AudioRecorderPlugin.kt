package flutter.overlay.window.flutter_overlay_window

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class AudioRecorderPlugin(private val context: Context) {
    companion object {
        const val CHANNEL_NAME = "com.homecoming.app/audio_recorder"
        private const val TAG = "AudioRecorderPlugin"
    }
    
    private var mediaRecorder: MediaRecorder? = null
    private var currentRecordingFile: File? = null
    private var isRecording = false
    
    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startRecording" -> startRecording(result)
            "stopRecording" -> stopRecording(result)
            "isRecording" -> result.success(isRecording)
            else -> result.notImplemented()
        }
    }
    
    private fun startRecording(result: MethodChannel.Result) {
        try {
            if (isRecording) {
                Log.w(TAG, "Already recording, stopping previous recording first")
                stopRecordingInternal()
            }
            
            // Create output file
            val audioDir = File(context.cacheDir, "audio_recordings")
            if (!audioDir.exists()) {
                audioDir.mkdirs()
            }
            
            val timestamp = System.currentTimeMillis()
            currentRecordingFile = File(audioDir, "recording_$timestamp.m4a")
            
            Log.d(TAG, "Starting recording to: ${currentRecordingFile?.absolutePath}")
            
            // Create and configure MediaRecorder
            mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(context)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            
            mediaRecorder?.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioEncodingBitRate(128000)
                setAudioSamplingRate(44100)
                setOutputFile(currentRecordingFile?.absolutePath)
                
                try {
                    prepare()
                    start()
                    isRecording = true
                    
                    Log.d(TAG, "Recording started successfully")
                    result.success(currentRecordingFile?.absolutePath)
                } catch (e: IOException) {
                    Log.e(TAG, "Failed to start recording", e)
                    cleanup()
                    result.error("START_FAILED", "Failed to start recording: ${e.message}", null)
                }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error starting recording", e)
            cleanup()
            result.error("START_ERROR", "Error starting recording: ${e.message}", null)
        }
    }
    
    private fun stopRecording(result: MethodChannel.Result) {
        try {
            if (!isRecording) {
                Log.w(TAG, "Not recording, nothing to stop")
                result.success(null)
                return
            }
            
            val filePath = stopRecordingInternal()
            
            if (filePath != null && File(filePath).exists()) {
                val fileSize = File(filePath).length()
                Log.d(TAG, "Recording stopped: $filePath ($fileSize bytes)")
                result.success(filePath)
            } else {
                Log.w(TAG, "Recording file does not exist after stopping")
                result.success(null)
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping recording", e)
            cleanup()
            result.error("STOP_ERROR", "Error stopping recording: ${e.message}", null)
        }
    }
    
    private fun stopRecordingInternal(): String? {
        try {
            mediaRecorder?.apply {
                stop()
                reset()
                release()
            }
            mediaRecorder = null
            isRecording = false
            
            return currentRecordingFile?.absolutePath
            
        } catch (e: Exception) {
            Log.e(TAG, "Error in stopRecordingInternal", e)
            cleanup()
            return null
        }
    }
    
    fun cleanup() {
        try {
            if (isRecording) {
                stopRecordingInternal()
            }
            mediaRecorder?.release()
            mediaRecorder = null
            isRecording = false
        } catch (e: Exception) {
            Log.e(TAG, "Error during cleanup", e)
        }
    }
}
