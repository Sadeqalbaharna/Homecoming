package com.homecoming.app

// KaiProactiveWorker — background proactive checks via WorkManager.
//
// Fires even when the app is closed. Two jobs:
//
//   Morning brief  (8 am daily)    → calendar + gentle "good morning" nudge
//   Event reminder (every 15 min)  → look for events starting in 10–20 minutes
//
// Bridge to Flutter: writes a pending proactive payload to SharedPreferences.
// When Flutter resumes it reads the payload, plays the attention sound, and
// pulses the avatar amber. The attention_sound_service.dart handles the actual
// "hmm?" / "huh?" clips.
//
// For users who don't open the app at the right moment, a quiet status-bar
// notification is also posted (no sound, just a badge in the shade).

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.*
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.TimeUnit

class KaiProactiveWorker(
    private val ctx: Context,
    params: WorkerParameters,
) : CoroutineWorker(ctx, params) {

    companion object {
        private const val TAG          = "KaiProactiveWorker"
        private const val PREFS        = "kai_proactive_prefs"
        private const val KEY_PAYLOAD  = "kai_pending_proactive"
        private const val KEY_MORNING  = "kai_last_morning_date"   // yyyy-MM-dd
        private const val KEY_REMINDER = "kai_last_event_reminder" // event title
        private const val NOTIF_CH     = "kai_proactive"
        private const val NOTIF_ID     = 9001

        // Called once from MainActivity — schedules both periodic workers.
        fun schedule(context: Context) {
            val wm = WorkManager.getInstance(context)

            // Morning brief — runs every 24 h, triggers between 7:30–10am in doWork()
            val morningReq = PeriodicWorkRequestBuilder<KaiProactiveWorker>(24, TimeUnit.HOURS)
                .setInitialDelay(minutesUntil(8, 0), TimeUnit.MILLISECONDS)
                .addTag("kai_morning")
                .build()
            wm.enqueueUniquePeriodicWork(
                "kai_morning_brief",
                ExistingPeriodicWorkPolicy.KEEP,
                morningReq,
            )

            // Event check — every 15 minutes
            val reminderReq = PeriodicWorkRequestBuilder<KaiProactiveWorker>(15, TimeUnit.MINUTES)
                .addTag("kai_reminder")
                .build()
            wm.enqueueUniquePeriodicWork(
                "kai_event_reminder",
                ExistingPeriodicWorkPolicy.KEEP,
                reminderReq,
            )

            Log.d(TAG, "WorkManager jobs scheduled")
        }

        // Cancel all Kai proactive workers (e.g. during logout / reset).
        fun cancel(context: Context) {
            val wm = WorkManager.getInstance(context)
            wm.cancelUniqueWork("kai_morning_brief")
            wm.cancelUniqueWork("kai_event_reminder")
        }

        // Read the pending payload from SharedPreferences (called by Flutter via MethodChannel).
        fun consumePending(context: Context): JSONObject? {
            val prefs  = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val raw    = prefs.getString(KEY_PAYLOAD, null) ?: return null
            prefs.edit().remove(KEY_PAYLOAD).apply()
            return try { JSONObject(raw) } catch (_: Exception) { null }
        }

        // ── Helpers ────────────────────────────────────────────────────────────

        private fun minutesUntil(hour: Int, minute: Int): Long {
            val now = Calendar.getInstance()
            val target = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                if (before(now)) add(Calendar.DATE, 1)
            }
            return (target.timeInMillis - now.timeInMillis).coerceAtLeast(0)
        }

        private fun todayStr(): String =
            SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
    }

    // ── doWork ─────────────────────────────────────────────────────────────────

    override suspend fun doWork(): Result {
        val tags = tags
        return when {
            "kai_morning"  in tags -> checkMorning()
            "kai_reminder" in tags -> checkReminder()
            else                   -> checkReminder() // default
        }
    }

    // ── Morning brief ──────────────────────────────────────────────────────────

    private fun checkMorning(): Result {
        val now = Calendar.getInstance()
        val h   = now.get(Calendar.HOUR_OF_DAY)
        val m   = now.get(Calendar.MINUTE)

        // Only fire in the 7:30–10:00 window
        val afterStart  = h > 7 || (h == 7 && m >= 30)
        val beforeEnd   = h < 10
        if (!afterStart || !beforeEnd) return Result.success()

        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (prefs.getString(KEY_MORNING, "") == todayStr()) return Result.success()

        val eventLine = firstEventToday()
        val message = if (eventLine != null) {
            "Morning. You have $eventLine today."
        } else {
            "Morning — hope you slept well."
        }

        prefs.edit().putString(KEY_MORNING, todayStr()).apply()
        storePending("morning", "curious", message)
        postNotification("curious", message)
        Log.d(TAG, "Morning brief fired: $message")
        return Result.success()
    }

    // ── Event reminder ─────────────────────────────────────────────────────────

    private fun checkReminder(): Result {
        val nowMs  = System.currentTimeMillis()
        val loMs   = nowMs + 10 * 60 * 1000L   // 10 min from now
        val hiMs   = nowMs + 20 * 60 * 1000L   // 20 min from now

        val event = nextEventBetween(loMs, hiMs) ?: return Result.success()

        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (prefs.getString(KEY_REMINDER, "") == event) return Result.success()
        prefs.edit().putString(KEY_REMINDER, event).apply()

        val message = "Heads up — $event is coming up soon."
        storePending("reminder", "worried", message)
        postNotification("worried", message)
        Log.d(TAG, "Event reminder fired: $message")
        return Result.success()
    }

    // ── Calendar helpers ───────────────────────────────────────────────────────

    private fun firstEventToday(): String? {
        val now = Calendar.getInstance()
        val eod = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 23)
            set(Calendar.MINUTE, 59)
            set(Calendar.SECOND, 59)
        }
        return nextEventBetween(now.timeInMillis, eod.timeInMillis)
    }

    private fun nextEventBetween(fromMs: Long, toMs: Long): String? {
        return try {
            val uri: Uri = Uri.parse("content://com.android.calendar/events")
            val projection = arrayOf("title", "dtstart", "dtend", "allDay")
            val selection  = "dtstart >= ? AND dtstart <= ? AND deleted = 0"
            val args       = arrayOf(fromMs.toString(), toMs.toString())
            val cursor: Cursor? = ctx.contentResolver.query(
                uri, projection, selection, args, "dtstart ASC"
            )
            cursor?.use { c ->
                if (c.moveToFirst()) {
                    val title   = c.getString(c.getColumnIndexOrThrow("title")) ?: return null
                    val startMs = c.getLong(c.getColumnIndexOrThrow("dtstart"))
                    val cal     = Calendar.getInstance().apply { timeInMillis = startMs }
                    val h       = cal.get(Calendar.HOUR_OF_DAY)
                    val m       = cal.get(Calendar.MINUTE).toString().padStart(2, '0')
                    val ampm    = if (h < 12) "am" else "pm"
                    val h12     = if (h % 12 == 0) 12 else h % 12
                    "$title at $h12:$m $ampm"
                } else null
            }
        } catch (e: Exception) {
            Log.w(TAG, "Calendar query failed: $e")
            null
        }
    }

    // ── SharedPreferences payload ──────────────────────────────────────────────

    private fun storePending(trigger: String, mood: String, message: String) {
        val payload = JSONObject().apply {
            put("trigger", trigger)
            put("mood",    mood)
            put("message", message)
            put("ts",      System.currentTimeMillis())
        }
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PAYLOAD, payload.toString())
            .apply()
    }

    // ── Silent notification (so users who don't open the app still notice) ─────

    private fun postNotification(mood: String, message: String) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                NOTIF_CH,
                "Kai",
                NotificationManager.IMPORTANCE_LOW,   // no sound, no heads-up — just shade
            ).apply { description = "Kai's gentle nudges" }
            nm.createNotificationChannel(ch)
        }

        val intent = ctx.packageManager
            .getLaunchIntentForPackage(ctx.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            ?: return

        val pi = PendingIntent.getActivity(
            ctx, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val emoji = if (mood == "worried") "🤔" else "💭"
        val notif = NotificationCompat.Builder(ctx, NOTIF_CH)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("$emoji Kai")
            .setContentText(message)
            .setContentIntent(pi)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        nm.notify(NOTIF_ID, notif)
    }
}
