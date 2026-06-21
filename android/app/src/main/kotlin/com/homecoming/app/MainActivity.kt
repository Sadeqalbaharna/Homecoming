package com.homecoming.app

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.WindowManager
import flutter.overlay.window.flutter_overlay_window.OverlayService
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
    
    // No auto-finish on resume — overlay and main app coexist.
    // The Dart layer controls visibility via moveTaskToBack / bring-to-front.
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize AudioRecorderPlugin
        audioRecorderPlugin = AudioRecorderPlugin(this)
        
        // Register AudioRecorder channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AudioRecorderPlugin.CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                audioRecorderPlugin?.handleMethodCall(call, result)
            }
        
        // Register Activity channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
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
                else -> result.notImplemented()
            }
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        audioRecorderPlugin?.cleanup()
    }
}
