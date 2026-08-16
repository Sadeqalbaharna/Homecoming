package com.homecoming.app

import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.text.SimpleDateFormat
import java.util.*

/**
 * KaiNotificationService — captures incoming notifications so Kai can read them.
 *
 * Setup required (one-time):
 *   Settings → Apps → Special app access → Notification access → enable Homecoming
 *
 * Stores the last MAX_PER_APP notifications per package name in memory.
 * KaiToolsPlugin reads from the static store via getNotifications().
 */
class KaiNotificationService : NotificationListenerService() {

    companion object {
        private const val TAG          = "KaiNotificationService"
        private const val MAX_PER_APP  = 20

        // packageName → ordered list of captured notifications (newest first)
        private val store = LinkedHashMap<String, ArrayDeque<CapturedNotification>>()

        // Known apps — common name → package
        private val packageAliases = mapOf(
            "whatsapp"  to "com.whatsapp",
            "telegram"  to "org.telegram.messenger",
            "instagram" to "com.instagram.android",
            "gmail"     to "com.google.android.gm",
            "messages"  to "com.google.android.apps.messaging",
            "sms"       to "com.google.android.apps.messaging",
            "texts"     to "com.google.android.apps.messaging",
            "twitter"   to "com.twitter.android",
            "x"         to "com.twitter.android",
            "snapchat"  to "com.snapchat.android",
            "linkedin"  to "com.linkedin.android",
            "slack"     to "com.Slack",
            "discord"   to "com.discord",
            "messenger" to "com.facebook.orca",
        )

        /**
         * Returns captured notifications for a given app (by name or package),
         * or from all apps if appName is null/empty.
         */
        fun getNotifications(appName: String?, limit: Int): List<CapturedNotification> {
            val pkg = resolvePackage(appName)
            return if (pkg == null) {
                // All apps — merge and sort by timestamp descending
                store.values
                    .flatten()
                    .sortedByDescending { it.timestamp }
                    .take(limit)
            } else {
                (store[pkg] ?: emptyList())
                    .take(limit)
            }
        }

        fun resolvePackage(appName: String?): String? {
            if (appName.isNullOrBlank() || appName == "all") return null
            return packageAliases[appName.lowercase().trim()]
        }

        fun hasAny() = store.isNotEmpty()
    }

    // ── NotificationListenerService callbacks ──────────────────────────────

    // The OS tells us directly when the binding comes and goes. Better evidence
    // than inferring it from a gap, and the only way to distinguish "unbound"
    // from "you had a quiet night".
    override fun onListenerConnected() {
        KaiBankAlertStore.noteListenerState(applicationContext, true)
    }

    override fun onListenerDisconnected() {
        KaiBankAlertStore.noteListenerState(applicationContext, false)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val pkg = sbn.packageName ?: return

        // Heartbeat on EVERY notification, before any filtering. This is what
        // separates "no transactions" from "the listener is dead": bank alerts
        // are rare, everything else is constant.
        KaiBankAlertStore.noteSeen(applicationContext, sbn.postTime)

        // Skip noise: system UI, ongoing (music player bars, etc.), group summaries
        if (pkg == "android" || pkg == "com.android.systemui") return
        if (sbn.isOngoing) return
        val notif   = sbn.notification ?: return
        val extras  = notif.extras  ?: return

        // Group summary notifications don't carry real content
        val isGroupSummary = (notif.flags and android.app.Notification.FLAG_GROUP_SUMMARY) != 0
        if (isGroupSummary) return

        val appLabel = runCatching {
            packageManager.getApplicationLabel(
                packageManager.getApplicationInfo(pkg, 0)
            ).toString()
        }.getOrDefault(pkg)

        val title = extras.getString("android.title")?.trim()

        // WhatsApp (and similar) bundles multiple messages in android.messages
        val messages = extras.getParcelableArray("android.messages")
        if (!messages.isNullOrEmpty()) {
            messages.reversed().forEach { raw ->
                val bundle = raw as? Bundle ?: return@forEach
                val sender  = bundle.getString("sender") ?: title ?: appLabel
                val msgText = bundle.getCharSequence("text")?.toString()?.trim() ?: return@forEach
                if (msgText.isBlank()) return@forEach
                push(pkg, CapturedNotification(
                    app       = appLabel,
                    pkg       = pkg,
                    sender    = sender,
                    text      = msgText,
                    timestamp = sbn.postTime,
                ))
            }
            return
        }

        // Single notification — use bigText if available, fall back to text
        val text = (extras.getCharSequence("android.bigText")
            ?: extras.getCharSequence("android.text"))
            ?.toString()?.trim()

        if (title.isNullOrBlank() && text.isNullOrBlank()) return

        push(pkg, CapturedNotification(
            app       = appLabel,
            pkg       = pkg,
            sender    = title ?: appLabel,
            text      = text ?: "",
            timestamp = sbn.postTime,
        ))

        // ── The one stream that cannot be lossy ────────────────────────────
        //
        // The store above keeps 20 per app, in memory. That is right for chat
        // and wrong for money: bank alerts arrive through the SMS app next to
        // every OTP and promo, so an afternoon of texts evicts the morning's
        // transaction — and the whole store dies with the process.
        //
        // Enrolled senders therefore get a durable, append-only queue of their
        // own. Captured HERE, at arrival, rather than on a pull: a transaction
        // that lands while nothing is asking must still be there later.
        if (KaiBankAlertStore.isEnrolled(applicationContext, title, pkg)) {
            runCatching {
                KaiBankAlertStore.capture(
                    applicationContext,
                    title ?: appLabel,
                    text ?: "",
                    sbn.postTime,
                )
            }.onFailure { Log.w(TAG, "bank alert capture failed: ${it.message}") }
        }

        Log.d(TAG, "Captured from $appLabel: ${title?.take(40)} — ${text?.take(60)}")
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) { /* intentionally empty */ }

    // ── Private ────────────────────────────────────────────────────────────

    private fun push(pkg: String, notif: CapturedNotification) {
        val deque = store.getOrPut(pkg) { ArrayDeque() }
        deque.addFirst(notif)
        while (deque.size > MAX_PER_APP) deque.removeLast()
    }
}

/** A single captured notification entry. */
data class CapturedNotification(
    val app:       String,
    val pkg:       String,
    val sender:    String,
    val text:      String,
    val timestamp: Long,
)
