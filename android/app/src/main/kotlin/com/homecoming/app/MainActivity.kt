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

    // Tell Flutter to use transparent rendering
    override fun getTransparencyMode(): TransparencyMode {
        return TransparencyMode.transparent
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize AudioRecorderPlugin
        audioRecorderPlugin = AudioRecorderPlugin(this)

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
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        super.onDestroy()
        audioRecorderPlugin?.cleanup()
    }
}
