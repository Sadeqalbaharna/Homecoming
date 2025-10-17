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
            stopRecording();
        }

        // Create output file
        File outputDir = context.getCacheDir();
        recordingFile = File.createTempFile("voice_", ".m4a", outputDir);
        
        Log.d(TAG, "Starting recording to: " + recordingFile.getAbsolutePath());

        // Create and configure MediaRecorder
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            mediaRecorder = new MediaRecorder(context);
        } else {
            mediaRecorder = new MediaRecorder();
        }

        mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC);
        mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);
        mediaRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);
        mediaRecorder.setAudioEncodingBitRate(128000);
        mediaRecorder.setAudioSamplingRate(44100);
        mediaRecorder.setOutputFile(recordingFile.getAbsolutePath());

        try {
            mediaRecorder.prepare();
            mediaRecorder.start();
            Log.d(TAG, "Recording started successfully");
        } catch (IOException e) {
            Log.e(TAG, "MediaRecorder prepare/start failed", e);
            if (mediaRecorder != null) {
                mediaRecorder.release();
                mediaRecorder = null;
            }
            throw e;
        }

        return recordingFile.getAbsolutePath();
    }

    private String stopRecording() {
        String filePath = recordingFile != null ? recordingFile.getAbsolutePath() : null;
        
        if (mediaRecorder != null) {
            try {
                mediaRecorder.stop();
                Log.d(TAG, "Recording stopped successfully");
            } catch (Exception e) {
                Log.e(TAG, "Error stopping MediaRecorder", e);
            } finally {
                mediaRecorder.release();
                mediaRecorder = null;
            }
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
