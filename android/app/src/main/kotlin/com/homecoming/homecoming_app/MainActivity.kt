package com.homecoming.homecoming_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.homecoming.app/overlay"
    
    // Tell Flutter to use transparent rendering
    override fun getTransparencyMode(): TransparencyMode {
        return TransparencyMode.transparent
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Set up method channel to enable click-through from Flutter
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "enableClickThrough") {
                // Patch the overlay window to add click-through support!
                ClickThroughPatcher.patchOverlayWindow(this)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }
}
