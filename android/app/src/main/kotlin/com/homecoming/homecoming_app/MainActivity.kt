package com.homecoming.homecoming_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.TransparencyMode

class MainActivity : FlutterActivity() {
    // Tell Flutter to use transparent rendering
    override fun getTransparencyMode(): TransparencyMode {
        return TransparencyMode.transparent
    }
}
