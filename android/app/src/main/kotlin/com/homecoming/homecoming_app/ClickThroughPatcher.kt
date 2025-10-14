package com.homecoming.homecoming_app

import android.content.Context
import android.view.WindowManager
import android.os.Handler
import android.os.Looper

/**
 * Runtime patcher that modifies flutter_overlay_window to add FLAG_NOT_TOUCH_MODAL
 * This allows transparent areas to pass clicks through while keeping Kai interactive!
 * 
 * How it works:
 * 1. Wait for flutter_overlay_window to create its overlay
 * 2. Find the overlay window view through WindowManager
 * 3. Modify the LayoutParams to add FLAG_NOT_TOUCH_MODAL
 * 4. Update the view - NOW TRANSPARENT AREAS ARE CLICK-THROUGH! 🎯
 */
object ClickThroughPatcher {
    
    fun patchOverlayWindow(context: Context) {
        // Give flutter_overlay_window time to create the overlay window
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                android.util.Log.d("ClickThroughPatcher", "🔍 Starting to search for overlay window...")
                
                val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
                
                // Use reflection to access the private WindowManagerGlobal instance
                val wmgClass = Class.forName("android.view.WindowManagerGlobal")
                val getInstance = wmgClass.getMethod("getInstance")
                val wmgInstance = getInstance.invoke(null)
                
                android.util.Log.d("ClickThroughPatcher", "📦 Got WindowManagerGlobal instance")
                
                // Get all views
                val getViewsMethod = wmgClass.getMethod("getViewRootNames")
                val viewRootNames = getViewsMethod.invoke(wmgInstance) as Array<*>
                
                android.util.Log.d("ClickThroughPatcher", "🔎 Found ${viewRootNames.size} view roots")
                
                val getViewMethod = wmgClass.getMethod("getRootView", String::class.java)
                
                // Find the overlay window view
                for (name in viewRootNames) {
                    android.util.Log.d("ClickThroughPatcher", "   Checking view: $name")
                    val view = getViewMethod.invoke(wmgInstance, name) as? android.view.View
                    if (view != null) {
                        val params = view.layoutParams as? WindowManager.LayoutParams
                        if (params != null) {
                            android.util.Log.d("ClickThroughPatcher", "   Type: ${params.type}, Flags: ${params.flags}")
                            if (params.type == WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY) {
                                // MAGIC HAPPENS HERE: Add FLAG_NOT_TOUCH_MODAL
                                // This makes transparent pixels non-interactive!
                                val oldFlags = params.flags
                                params.flags = params.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                                
                                // Update the view with new flags
                                windowManager.updateViewLayout(view, params)
                                
                                android.util.Log.d("ClickThroughPatcher", "✅ Successfully patched overlay! Old flags: $oldFlags, New flags: ${params.flags}")
                                break
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("ClickThroughPatcher", "❌ Failed to patch overlay", e)
            }
        }, 1000) // Wait 1 second for overlay to be created
    }
}
