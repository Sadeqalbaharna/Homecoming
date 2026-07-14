package com.homecoming.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * KaiAccessibilityService — reads visible screen content on demand.
 *
 * Setup required (one-time):
 *   Settings → Accessibility → Installed apps → Homecoming → enable
 *
 * Design principles:
 *  • Passive — only captures on screen-change events, never polls
 *  • Privacy-safe — skips password fields, never logs raw content
 *  • On-demand — KaiToolsPlugin pulls a snapshot; nothing is sent anywhere
 *    automatically
 *
 * KaiToolsPlugin calls getSnapshot() when the user asks Kai to read the screen.
 */
class KaiAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG        = "KaiAccessibility"
        private const val MAX_CHARS  = 4000

        // Set by this service instance; null when service is not running
        private var instance: KaiAccessibilityService? = null

        fun isRunning() = instance != null

        /**
         * Returns a snapshot of the current screen: app name + visible text.
         * Returns null if the service is not running.
         */
        fun getSnapshot(): ScreenSnapshot? {
            val svc = instance ?: return null
            return svc.captureCurrentScreen()
        }
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        serviceInfo = serviceInfo.apply {
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = flags or
                    AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                    AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
        }
        Log.d(TAG, "Accessibility service connected")
    }

    override fun onDestroy() {
        instance = null
        Log.d(TAG, "Accessibility service destroyed")
        super.onDestroy()
    }

    // ── Event handling ────────────────────────────────────────────────────
    // We don't need to do anything in onAccessibilityEvent because we capture
    // on demand via rootInActiveWindow — no need to cache stale state.

    override fun onAccessibilityEvent(event: AccessibilityEvent) { /* intentionally empty */ }
    override fun onInterrupt() { /* no-op */ }

    // ── Screen capture ────────────────────────────────────────────────────

    private fun captureCurrentScreen(): ScreenSnapshot {
        val root = rootInActiveWindow

        // Which app is in the foreground
        val appPkg  = root?.packageName?.toString() ?: "unknown"
        val appName = runCatching {
            packageManager.getApplicationLabel(
                packageManager.getApplicationInfo(appPkg, 0)
            ).toString()
        }.getOrDefault(appPkg)

        val buf = StringBuilder()
        if (root != null) {
            extractText(root, buf)
            root.recycle()
        }

        val text = buf.toString()
            .lines()
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .distinct()             // remove duplicate lines (toolbars, tab bars)
            .joinToString("\n")
            .take(MAX_CHARS)

        Log.d(TAG, "Screen captured: $appName — ${text.length} chars")
        return ScreenSnapshot(appName = appName, packageName = appPkg, text = text)
    }

    /**
     * Recursively walks the accessibility node tree and appends all
     * visible, non-password text to [buf].
     */
    private fun extractText(node: AccessibilityNodeInfo, buf: StringBuilder) {
        // Skip password fields — never read passwords
        if (node.isPassword) {
            node.recycle()
            return
        }

        // Append text content
        node.text?.toString()?.trim()?.let {
            if (it.isNotBlank()) buf.appendLine(it)
        }
        // Append content descriptions (images, icons with labels)
        node.contentDescription?.toString()?.trim()?.let {
            if (it.isNotBlank() && !buf.contains(it)) buf.appendLine(it)
        }

        // Recurse into children
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            extractText(child, buf)
        }
        node.recycle()
    }
}

/** Immutable snapshot of the screen at a point in time. */
data class ScreenSnapshot(
    val appName:     String,
    val packageName: String,
    val text:        String,
)
