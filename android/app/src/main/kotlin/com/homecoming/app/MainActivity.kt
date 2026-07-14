package com.homecoming.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import flutter.overlay.window.flutter_overlay_window.AudioRecorderPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.homecoming.app/activity"
    private val TAG = "MainActivity"
    private var audioRecorderPlugin: AudioRecorderPlugin? = null
    private var micStreamPlugin: KaiMicStreamPlugin? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // Schedule background proactive checks (safe to call every launch — uses KEEP policy)
        KaiProactiveWorker.schedule(this)
    }

    // Tell Flutter to use transparent rendering
    override fun getTransparencyMode(): TransparencyMode {
        return TransparencyMode.transparent
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize AudioRecorderPlugin
        audioRecorderPlugin = AudioRecorderPlugin(this)

        // Register Kai tools channel (agentic function calling)
        KaiToolsPlugin(this).register(flutterEngine.dartExecutor.binaryMessenger)

        // Register PCM mic stream (for sherpa-onnx keyword spotting)
        micStreamPlugin = KaiMicStreamPlugin()
        micStreamPlugin!!.register(flutterEngine.dartExecutor.binaryMessenger)

        // Register AudioRecorder channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AudioRecorderPlugin.CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                audioRecorderPlugin?.handleMethodCall(call, result)
            }

        // Register Activity channel (moveTaskToBack only — overlay tap goes via WindowSetup.messenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "finishActivity" -> {
                        Log.d(TAG, "finishActivity called via MethodChannel")
                        window.addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)
                        window.addFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE)
                        window.addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL)
                        finish()
                        result.success(true)
                    }
                    "moveTaskToBack" -> {
                        Log.d(TAG, "moveTaskToBack called via MethodChannel")
                        moveTaskToBack(true)
                        result.success(true)
                    }
                    "requestBatteryExemption" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(POWER_SERVICE) as PowerManager
                            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                                val intent = Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")
                                )
                                startActivity(intent)
                            }
                        }
                        result.success(true)
                    }
                    // Called by Flutter on resume to drain any WorkManager-queued message
                    "consumePendingProactive" -> {
                        val payload = KaiProactiveWorker.consumePending(this)
                        if (payload != null) {
                            result.success(mapOf(
                                "trigger" to payload.optString("trigger"),
                                "mood"    to payload.optString("mood"),
                                "message" to payload.optString("message"),
                            ))
                        } else {
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        // Stop the mic reader thread BEFORE super.onDestroy() tears down the
        // Flutter engine / JNI bridge — prevents the "FlutterJNI was detached"
        // warning flood in logcat on every hot restart.
        micStreamPlugin?.destroy()
        audioRecorderPlugin?.cleanup()
        super.onDestroy()
    }
}
