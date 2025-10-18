package flutter.overlay.window.flutter_overlay_window;

import android.content.Context;
import android.media.MediaRecorder;
import android.os.Build;
import android.util.Log;
import io.flutter.plugin.common.MethodChannel;
import java.io.File;
import java.io.IOException;

/**
 * Native audio recorder using Android MediaRecorder API.
 * Works in overlay isolates since it uses MethodChannel directly.
 */
public class AudioRecorderPlugin {
    private Context context;
    private MediaRecorder mediaRecorder;
    private File recordingFile;
    private final String TAG = "AudioRecorderPlugin";

    public static final String CHANNEL_NAME = "com.homecoming.app/audio_recorder";

    public AudioRecorderPlugin(Context context) {
        this.context = context;
    }

    public void handleMethodCall(io.flutter.plugin.common.MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "startRecording":
                try {
                    String filePath = startRecording();
                    result.success(filePath);
                } catch (Exception e) {
                    Log.e(TAG, "Failed to start recording", e);
                    result.error("RECORDING_ERROR", e.getMessage(), null);
                }
                break;
            case "stopRecording":
                try {
                    String filePath = stopRecording();
                    result.success(filePath);
                } catch (Exception e) {
                    Log.e(TAG, "Failed to stop recording", e);
                    result.error("RECORDING_ERROR", e.getMessage(), null);
                }
                break;
            case "isRecording":
                result.success(mediaRecorder != null);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    private String startRecording() throws IOException {
        // Stop any existing recording first
        if (mediaRecorder != null) {
            Log.w(TAG, "⚠️ MediaRecorder already exists, stopping previous recording");
            stopRecording();
        }

        // Create output file
        File outputDir = context.getCacheDir();
        recordingFile = File.createTempFile("voice_", ".m4a", outputDir);
        
        Log.d(TAG, "📁 Output directory: " + outputDir.getAbsolutePath());
        Log.d(TAG, "📄 Recording file: " + recordingFile.getAbsolutePath());
        Log.d(TAG, "🎤 Starting recording...");

        // Create and configure MediaRecorder
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            mediaRecorder = new MediaRecorder(context);
            Log.d(TAG, "✅ MediaRecorder created (Android S+)");
        } else {
            mediaRecorder = new MediaRecorder();
            Log.d(TAG, "✅ MediaRecorder created (Legacy)");
        }

        try {
            Log.d(TAG, "🔧 Setting audio source: MIC");
            mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC);
            
            Log.d(TAG, "🔧 Setting output format: MPEG_4");
            mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);
            
            Log.d(TAG, "🔧 Setting audio encoder: AAC");
            mediaRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);
            
            Log.d(TAG, "🔧 Setting bitrate: 128000");
            mediaRecorder.setAudioEncodingBitRate(128000);
            
            Log.d(TAG, "🔧 Setting sample rate: 44100");
            mediaRecorder.setAudioSamplingRate(44100);
            
            Log.d(TAG, "🔧 Setting output file: " + recordingFile.getAbsolutePath());
            mediaRecorder.setOutputFile(recordingFile.getAbsolutePath());

            Log.d(TAG, "🔄 Preparing MediaRecorder...");
            mediaRecorder.prepare();
            Log.d(TAG, "✅ MediaRecorder prepared");
            
            Log.d(TAG, "▶️ Starting recording...");
            mediaRecorder.start();
            Log.d(TAG, "✅ Recording started successfully!");
            
        } catch (IOException e) {
            Log.e(TAG, "❌ MediaRecorder prepare/start failed", e);
            if (mediaRecorder != null) {
                mediaRecorder.release();
                mediaRecorder = null;
            }
            throw e;
        } catch (IllegalStateException e) {
            Log.e(TAG, "❌ MediaRecorder in illegal state", e);
            if (mediaRecorder != null) {
                mediaRecorder.release();
                mediaRecorder = null;
            }
            throw new IOException("MediaRecorder illegal state: " + e.getMessage());
        } catch (RuntimeException e) {
            Log.e(TAG, "❌ MediaRecorder runtime error", e);
            if (mediaRecorder != null) {
                mediaRecorder.release();
                mediaRecorder = null;
            }
            throw new IOException("MediaRecorder runtime error: " + e.getMessage());
        }

        return recordingFile.getAbsolutePath();
    }

    private String stopRecording() {
        String filePath = recordingFile != null ? recordingFile.getAbsolutePath() : null;
        
        Log.d(TAG, "⏹️ Stopping recording...");
        
        if (mediaRecorder != null) {
            try {
                mediaRecorder.stop();
                Log.d(TAG, "✅ Recording stopped successfully");
                
                if (filePath != null) {
                    File file = new File(filePath);
                    if (file.exists()) {
                        long fileSize = file.length();
                        Log.d(TAG, "📊 Recording file size: " + fileSize + " bytes");
                        if (fileSize == 0) {
                            Log.e(TAG, "❌ WARNING: Recording file is EMPTY (0 bytes)!");
                        } else if (fileSize < 1000) {
                            Log.w(TAG, "⚠️ WARNING: Recording file is very small (" + fileSize + " bytes)");
                        } else {
                            Log.d(TAG, "✅ Recording file size looks good");
                        }
                    } else {
                        Log.e(TAG, "❌ Recording file does not exist: " + filePath);
                    }
                }
                
            } catch (IllegalStateException e) {
                Log.e(TAG, "❌ Error stopping MediaRecorder (illegal state)", e);
            } catch (RuntimeException e) {
                Log.e(TAG, "❌ Error stopping MediaRecorder (runtime error)", e);
            } finally {
                try {
                    mediaRecorder.release();
                    Log.d(TAG, "✅ MediaRecorder released");
                } catch (Exception e) {
                    Log.e(TAG, "❌ Error releasing MediaRecorder", e);
                }
                mediaRecorder = null;
            }
        } else {
            Log.w(TAG, "⚠️ MediaRecorder is null, nothing to stop");
        }

        return filePath;
    }

    public void cleanup() {
        if (mediaRecorder != null) {
            try {
                mediaRecorder.stop();
            } catch (Exception e) {
                // Ignore
            }
            mediaRecorder.release();
            mediaRecorder = null;
        }
        recordingFile = null;
    }
}
