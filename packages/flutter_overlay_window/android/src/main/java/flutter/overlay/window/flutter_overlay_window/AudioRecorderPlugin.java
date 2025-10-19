package flutter.overlay.window.flutter_overlay_window;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.IBinder;
import android.util.Log;
import io.flutter.plugin.common.MethodChannel;

/**
 * Native audio recorder that delegates to AudioRecordingService.
 * The service runs as a foreground service with microphone access.
 * This works around Android's restriction on mic access from overlay windows.
 */
public class AudioRecorderPlugin {
    private Context context;
    private Object audioService;  // Will hold AudioRecordingService instance via reflection
    private final String TAG = "AudioRecorderPlugin";
    private boolean isServiceBound = false;

    public static final String CHANNEL_NAME = "com.homecoming.app/audio_recorder";

    private ServiceConnection serviceConnection = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder service) {
            Log.d(TAG, "✅ AudioRecordingService connected");
            try {
                // Use reflection to get the service instance
                Class<?> binderClass = service.getClass();
                java.lang.reflect.Method getServiceMethod = binderClass.getMethod("getService");
                audioService = getServiceMethod.invoke(service);
                isServiceBound = true;
                Log.d(TAG, "✅ AudioRecordingService bound successfully");
            } catch (Exception e) {
                Log.e(TAG, "❌ Failed to bind AudioRecordingService", e);
            }
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
            Log.w(TAG, "⚠️ AudioRecordingService disconnected");
            audioService = null;
            isServiceBound = false;
        }
    };

    public AudioRecorderPlugin(Context context) {
        this.context = context;
        bindAudioService();
    }

    private void bindAudioService() {
        try {
            Log.d(TAG, "🔗 Binding to AudioRecordingService...");
            Intent intent = new Intent();
            // Use the actual applicationId from build.gradle, not the namespace
            intent.setClassName("com.homecoming.app", 
                              "com.homecoming.homecoming_app.AudioRecordingService");
            
            // Start the service first (as foreground service)
            context.startForegroundService(intent);
            Log.d(TAG, "🚀 Foreground service start requested");
            
            // Then bind to it
            boolean bound = context.bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE);
            Log.d(TAG, bound ? "✅ Service binding initiated" : "❌ Service binding failed");
        } catch (Exception e) {
            Log.e(TAG, "❌ Error binding to AudioRecordingService", e);
        }
    }

    public void handleMethodCall(io.flutter.plugin.common.MethodCall call, MethodChannel.Result result) {
        if (!isServiceBound || audioService == null) {
            Log.w(TAG, "⚠️ AudioRecordingService not bound yet");
            result.error("SERVICE_NOT_BOUND", "Audio recording service not ready", null);
            return;
        }

        try {
            switch (call.method) {
                case "startRecording":
                    String startPath = (String) audioService.getClass().getMethod("startRecording").invoke(audioService);
                    result.success(startPath);
                    break;
                case "stopRecording":
                    String stopPath = (String) audioService.getClass().getMethod("stopRecording").invoke(audioService);
                    result.success(stopPath);
                    break;
                case "isRecording":
                    Boolean isRec = (Boolean) audioService.getClass().getMethod("isRecording").invoke(audioService);
                    result.success(isRec);
                    break;
                default:
                    result.notImplemented();
                    break;
            }
        } catch (Exception e) {
            Log.e(TAG, "❌ Error calling AudioRecordingService method", e);
            result.error("SERVICE_ERROR", e.getMessage(), null);
        }
    }

    public void cleanup() {
        try {
            if (isServiceBound) {
                context.unbindService(serviceConnection);
                isServiceBound = false;
                Log.d(TAG, "✅ AudioRecordingService unbound");
            }
        } catch (Exception e) {
            Log.e(TAG, "❌ Error unbinding AudioRecordingService", e);
        }
        audioService = null;
    }
}
