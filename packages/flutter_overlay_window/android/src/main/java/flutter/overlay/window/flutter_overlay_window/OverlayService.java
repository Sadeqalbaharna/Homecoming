package flutter.overlay.window.flutter_overlay_window;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.content.res.AssetFileDescriptor;
import android.content.res.Configuration;
import android.content.res.Resources;
import android.graphics.PixelFormat;
import android.app.PendingIntent;
import android.media.MediaPlayer;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.util.DisplayMetrics;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.WindowManager;

import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import androidx.core.app.NotificationCompat;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.BasicMessageChannel;
import io.flutter.plugin.common.JSONMessageCodec;

/**
 * Foreground service that hosts the native FlameNativeView overlay.
 *
 * Design notes:
 *  - We intentionally do NOT create a Flutter overlay engine here.
 *    Doing so would cause FlutterOverlayWindowPlugin.onAttachedToEngine()
 *    to be called for the overlay engine, overwriting WindowSetup.messenger
 *    (which must stay pointed at the MAIN engine so Java→Dart messages
 *    reach the main app's _overlayMsgSub listener).
 *
 *  Tap:       removes flame, brings app to foreground ({action:expand}).
 *  Long press: dims flame, uses SpeechRecognizer in-place. App stays hidden.
 *              Sends {action:pauseVoice} so Dart releases the mic from Porcupine,
 *              then captures speech, then sends {action:message, text:"..."} so
 *              Dart can call _send() silently. Flame re-brightens when done.
 */
public class OverlayService extends Service {

    public static final String INTENT_EXTRA_IS_CLOSE_WINDOW = "IsCloseWindow";

    private static OverlayService instance;
    public static boolean isRunning = false;

    private WindowManager windowManager = null;
    private FlameNativeView flameView = null;
    private WindowManager.LayoutParams flameParams = null;

    private SpeechRecognizer speechRecognizer = null;
    private boolean isListening = false;

    private Resources mResources;
    private Integer mStatusBarHeight = -1;
    private Integer mNavigationBarHeight = -1;

    private static final int DEFAULT_NAV_BAR_HEIGHT_DP = 48;
    private static final int DEFAULT_STATUS_BAR_HEIGHT_DP = 25;

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    @Nullable
    @Override
    public IBinder onBind(Intent intent) { return null; }

    @Override
    public void onCreate() {
        createNotificationChannel();

        Intent notificationIntent = new Intent(this, FlutterOverlayWindowPlugin.class);
        int pendingFlags = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
                ? PendingIntent.FLAG_IMMUTABLE
                : PendingIntent.FLAG_UPDATE_CURRENT;
        PendingIntent pendingIntent = PendingIntent.getActivity(this, 0, notificationIntent, pendingFlags);

        final int notifyIcon = getDrawableResourceId("mipmap", "launcher");
        Notification notification = new NotificationCompat.Builder(this, OverlayConstants.CHANNEL_ID)
                .setContentTitle(WindowSetup.overlayTitle)
                .setContentText(WindowSetup.overlayContent)
                .setSmallIcon(notifyIcon == 0 ? R.drawable.notification_icon : notifyIcon)
                .setContentIntent(pendingIntent)
                .setVisibility(WindowSetup.notificationVisibility)
                .build();

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(OverlayConstants.NOTIFICATION_ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else {
            startForeground(OverlayConstants.NOTIFICATION_ID, notification);
        }
        instance = this;
    }

    @RequiresApi(api = Build.VERSION_CODES.JELLY_BEAN_MR1)
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) {
            Log.w("OverlayService", "Null intent on restart — stopping");
            stopSelf();
            return START_NOT_STICKY;
        }

        mResources = getApplicationContext().getResources();

        boolean isCloseWindow = intent.getBooleanExtra(INTENT_EXTRA_IS_CLOSE_WINDOW, false);
        if (isCloseWindow) {
            removeFlameView();
            isRunning = false;
            stopSelf();
            return START_STICKY;
        }

        if (windowManager != null && flameView != null) {
            removeFlameView();
            stopSelf();
        }

        isRunning = true;
        Log.d("OverlayService", "Starting flame overlay");

        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        DisplayMetrics dm = new DisplayMetrics();
        windowManager.getDefaultDisplay().getMetrics(dm);
        int sizePx = dpToPx(90);

        flameParams = new WindowManager.LayoutParams(
                sizePx, sizePx,
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                        ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                        : WindowManager.LayoutParams.TYPE_PHONE,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
        );
        flameParams.gravity = Gravity.TOP | Gravity.LEFT;
        flameParams.x = dm.widthPixels - sizePx;
        flameParams.y = dm.heightPixels / 2 - sizePx / 2;

        flameView = new FlameNativeView(getApplicationContext());
        flameView.attach(windowManager, flameParams,
                /* tap */        () -> sendActionAndLaunch("expand"),
                /* long press */ this::startBackgroundListening
        );

        windowManager.addView(flameView, flameParams);
        Log.d("OverlayService", "Flame overlay added at x=" + flameParams.x + " y=" + flameParams.y);
        return START_STICKY;
    }

    @RequiresApi(api = Build.VERSION_CODES.M)
    @Override
    public void onDestroy() {
        Log.d("OverlayService", "onDestroy");
        destroySpeechRecognizer();
        removeFlameView();
        isRunning = false;
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) nm.cancel(OverlayConstants.NOTIFICATION_ID);
        instance = null;
    }

    // ── Public static API (called by FlutterOverlayWindowPlugin) ─────────────

    public static Map<String, Double> getCurrentPosition() {
        if (instance != null && instance.flameParams != null && instance.mResources != null) {
            Map<String, Double> pos = new HashMap<>();
            pos.put("x", instance.pxToDp(instance.flameParams.x));
            pos.put("y", instance.pxToDp(instance.flameParams.y));
            return pos;
        }
        return null;
    }

    public static boolean moveOverlay(int x, int y) {
        if (instance == null || instance.windowManager == null
                || instance.flameView == null || instance.flameParams == null) {
            return false;
        }
        instance.flameParams.x = (x == -1999 || x == -1) ? -1 : instance.dpToPx(x);
        instance.flameParams.y = instance.dpToPx(y);
        instance.windowManager.updateViewLayout(instance.flameView, instance.flameParams);
        return true;
    }

    // ── Tap: remove flame + bring app forward ─────────────────────────────────

    private void sendActionAndLaunch(String action) {
        removeFlameView();
        sendMessage(action, null);
        Intent launch = getApplicationContext()
                .getPackageManager()
                .getLaunchIntentForPackage(getApplicationContext().getPackageName());
        if (launch != null) {
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            getApplicationContext().startActivity(launch);
        }
    }

    // ── Long press: listen in background, flame stays ─────────────────────────

    private void startBackgroundListening() {
        if (isListening) return;
        if (!SpeechRecognizer.isRecognitionAvailable(getApplicationContext())) {
            Log.w("OverlayService", "SpeechRecognizer not available on this device");
            return;
        }

        isListening = true;

        // Haptic + audio feedback: user knows Kai is listening
        vibrate(60);
        playSound("assets/audio/record_start.wav");

        // Dim the flame as a visual "listening" cue
        if (flameView != null) flameView.setAlpha(0.4f);

        // Tell Dart to pause Porcupine so it releases the mic
        sendMessage("pauseVoice", null);

        // Small delay so Porcupine has time to release the mic before we open it
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(getApplicationContext());
            speechRecognizer.setRecognitionListener(new RecognitionListener() {

                @Override
                public void onResults(Bundle results) {
                    ArrayList<String> matches =
                            results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
                    String text = (matches != null && !matches.isEmpty()) ? matches.get(0) : "";
                    Log.d("OverlayService", "STT result: " + text);
                    onListeningFinished(text);
                }

                @Override public void onError(int error) {
                    Log.w("OverlayService", "STT error: " + error);
                    onListeningFinished("");
                }

                // ── Required stubs ─────────────────────────────────────────────
                @Override public void onReadyForSpeech(Bundle params) {
                    Log.d("OverlayService", "STT ready");
                }
                @Override public void onBeginningOfSpeech() {}
                @Override public void onRmsChanged(float rmsdB) {}
                @Override public void onBufferReceived(byte[] buffer) {}
                @Override public void onEndOfSpeech() {}
                @Override public void onPartialResults(Bundle partialResults) {}
                @Override public void onEvent(int eventType, Bundle params) {}
            });

            Intent recIntent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
            recIntent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
            recIntent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1);
            recIntent.putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE,
                    getApplicationContext().getPackageName());
            speechRecognizer.startListening(recIntent);

        }, 250); // 250 ms for Porcupine to release the mic
    }

    private void onListeningFinished(String text) {
        isListening = false;
        destroySpeechRecognizer();

        // Audio + haptic: confirm capture (double-tap feel for success, single for empty)
        playSound("assets/audio/record_stop.wav");
        vibrate(text.isEmpty() ? 30 : 80);

        // Restore flame brightness
        if (flameView != null) flameView.setAlpha(1.0f);

        // Send transcript (or empty string) to Dart — Dart will resume voice + call _send()
        sendMessage("message", text);
    }

    private void destroySpeechRecognizer() {
        if (speechRecognizer != null) {
            try { speechRecognizer.destroy(); } catch (Exception ignored) {}
            speechRecognizer = null;
        }
    }

    // ── Messenger helper ──────────────────────────────────────────────────────

    private void sendMessage(String action, String text) {
        try {
            if (WindowSetup.messenger != null) {
                org.json.JSONObject msg = new org.json.JSONObject();
                msg.put("action", action);
                if (text != null) msg.put("text", text);
                WindowSetup.messenger.send(msg, null);
            }
        } catch (Exception e) {
            Log.e("OverlayService", "Failed to send: " + action, e);
        }
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    /** Play a Flutter asset WAV without opening the app. Fire-and-forget. */
    private void playSound(String flutterAssetPath) {
        try {
            AssetFileDescriptor afd = getApplicationContext().getAssets()
                    .openFd("flutter_assets/" + flutterAssetPath);
            MediaPlayer mp = new MediaPlayer();
            mp.setDataSource(afd.getFileDescriptor(), afd.getStartOffset(), afd.getLength());
            mp.setOnCompletionListener(MediaPlayer::release);
            mp.prepare();
            mp.start();
        } catch (Exception e) {
            Log.w("OverlayService", "Could not play sound: " + flutterAssetPath, e);
        }
    }

    /** Short haptic pulse — requires VIBRATE permission. */
    private void vibrate(long ms) {
        Vibrator v = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
        if (v == null || !v.hasVibrator()) return;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            v.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE));
        } else {
            v.vibrate(ms);
        }
    }

    private void removeFlameView() {
        if (windowManager != null && flameView != null) {
            try { windowManager.removeView(flameView); } catch (Exception ignored) {}
            flameView.cleanup();
        }
        flameView = null;
        windowManager = null;
        flameParams = null;
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    OverlayConstants.CHANNEL_ID,
                    "Foreground Service Channel",
                    NotificationManager.IMPORTANCE_LOW
            );
            NotificationManager mgr = getSystemService(NotificationManager.class);
            if (mgr != null) mgr.createNotificationChannel(channel);
        }
    }

    private int getDrawableResourceId(String resType, String name) {
        return getApplicationContext().getResources()
                .getIdentifier(String.format("ic_%s", name), resType, getApplicationContext().getPackageName());
    }

    private int dpToPx(int dp) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP,
                dp, mResources.getDisplayMetrics());
    }

    private double pxToDp(int px) {
        return (double) px / mResources.getDisplayMetrics().density;
    }

    int navigationBarHeightPx() {
        if (mNavigationBarHeight == -1) {
            int id = mResources.getIdentifier("navigation_bar_height", "dimen", "android");
            mNavigationBarHeight = id > 0 ? mResources.getDimensionPixelSize(id) : dpToPx(DEFAULT_NAV_BAR_HEIGHT_DP);
        }
        return mNavigationBarHeight;
    }
}
