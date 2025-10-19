package flutter.overlay.window.flutter_overlay_window;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
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
    private boolean isBindingInProgress = false;

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
                isBindingInProgress = false;
                Log.d(TAG, "✅ AudioRecordingService bound successfully");
            } catch (Exception e) {
                Log.e(TAG, "❌ Failed to bind AudioRecordingService", e);
                isBindingInProgress = false;
            }
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
            Log.w(TAG, "⚠️ AudioRecordingService disconnected");
            audioService = null;
            isServiceBound = false;
            isBindingInProgress = false;
        }
    };

    public AudioRecorderPlugin(Context context) {
        this.context = context;
        // DON'T bind service on startup - wait for first recording request
        // This allows app to request permissions first
    }

    private void bindAudioService() {
        if (isServiceBound || isBindingInProgress) {
            return;  // Already bound or binding in progress
        }
        
        isBindingInProgress = true;
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
            
            if (!bound) {
                isBindingInProgress = false;
            }
        } catch (Exception e) {
            Log.e(TAG, "❌ Error binding to AudioRecordingService", e);
            isBindingInProgress = false;
        }
    }

    public void handleMethodCall(io.flutter.plugin.common.MethodCall call, MethodChannel.Result result) {
        // Bind service on first method call (after permissions are granted)
        if (!isServiceBound) {
            if (!isBindingInProgress) {
                Log.d(TAG, "🔗 Service not bound yet, binding now...");
                bindAudioService();
            }
            
            // Wait for service to bind (up to 3 seconds)
            waitForServiceAndExecute(call, result, 0);
            return;
        }

        executeMethodCall(call, result);
    }
    
    private void waitForServiceAndExecute(io.flutter.plugin.common.MethodCall call, MethodChannel.Result result, int attemptCount) {
        if (isServiceBound && audioService != null) {
            // Service is ready!
            executeMethodCall(call, result);
            return;
        }
        
        if (attemptCount >= 30) {  // 30 attempts * 100ms = 3 seconds max
            Log.e(TAG, "❌ Service binding timeout after 3 seconds");
            result.error("SERVICE_TIMEOUT", "Audio recording service failed to start. Please restart the app.", null);
            return;
        }
        
        // Wait 100ms and try again
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            waitForServiceAndExecute(call, result, attemptCount + 1);
        }, 100);
    }
    
    private void executeMethodCall(io.flutter.plugin.common.MethodCall call, MethodChannel.Result result) {
        if (audioService == null) {
            result.error("SERVICE_NOT_BOUND", "Audio recording service not available", null);
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
