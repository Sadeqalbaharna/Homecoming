package com.homecoming.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * KaiBankAlertStore — the one notification stream that cannot afford to be lossy.
 *
 * ── Why this is not the normal notification store ────────────────────────────
 *
 * KaiNotificationService keeps the last 20 notifications PER APP, in memory, so
 * Kai can be asked "what did I miss". That is exactly right for chat: it is a
 * convenience, the data is still on the phone, and losing it costs nothing.
 *
 * A ledger is different in both directions:
 *
 *  1. Bank alerts usually arrive through the SMS app, alongside every OTP,
 *     delivery update and marketing message. Twenty-five texts in an afternoon
 *     and the morning's transaction has been evicted by a Talabat promo.
 *  2. The store dies with the process. A transaction that arrives while the app
 *     is not running never existed — and unlike a chat message there is no
 *     second copy anywhere Kai can reach.
 *
 * A ledger that is quietly missing rows is worse than one that is obviously
 * empty, because it still adds up. So enrolled senders get their own store:
 * durable, append-only, and not competing with anything for space.
 *
 * ── Enrolment is the trust boundary ──────────────────────────────────────────
 *
 * Only senders on the enrolled list are written here at all. That is the same
 * rule the Dart side enforces — the sender is the channel, the message is the
 * payload — applied one layer earlier so a spoofed alert does not even occupy
 * space in the durable queue.
 *
 * Nothing here interprets the text. Amounts, direction and merchant are the
 * Dart side's job, where the logic is pure and testable. This file's only
 * responsibilities are: catch it, keep it, hand it over once.
 */
object KaiBankAlertStore {

    private const val FILE = "kai_bank_alerts.json"
    private const val MAX_QUEUED = 500

    /**
     * Senders whose alerts may be captured, synced down from Dart.
     *
     * EMPTY BY DEFAULT, on purpose. An earlier version shipped with five
     * guessed Bahraini sender ids already enrolled, which invented a trust
     * boundary rather than asking for one — and a wrong guess here fails as
     * SILENCE, the worst possible way for a trust boundary to be wrong.
     *
     * Dart owns the list; this copy is a capture filter, not the authority.
     * Persisted so a restart cannot quietly empty it: an enrolment that
     * forgets is worse than no enrolment, because the ledger simply stops
     * filling and nothing says why.
     */
    private var enrolled: Set<String> = emptySet()
    private var loaded = false

    private const val ENROL_FILE = "kai_bank_senders.json"

    @Synchronized
    fun setEnrolled(ctx: Context, senders: List<String>) {
        enrolled = senders.map { it.trim().uppercase() }.filter { it.isNotEmpty() }.toSet()
        loaded = true
        runCatching {
            val arr = JSONArray()
            enrolled.forEach { arr.put(it) }
            File(ctx.filesDir, ENROL_FILE).writeText(arr.toString())
        }
    }

    @Synchronized
    private fun ensureLoaded(ctx: Context) {
        if (loaded) return
        loaded = true
        runCatching {
            val f = File(ctx.filesDir, ENROL_FILE)
            if (!f.exists()) return
            val arr = JSONArray(f.readText())
            val out = HashSet<String>(arr.length())
            for (i in 0 until arr.length()) out.add(arr.optString(i).uppercase())
            enrolled = out
        }
    }

    fun enrolledSenders(ctx: Context): Set<String> {
        ensureLoaded(ctx)
        return enrolled
    }

    /**
     * Exact match only. A pattern like "contains BANK" would match a scammer
     * calling themselves BANK-ALERT, which is the whole attack.
     */
    fun isEnrolled(ctx: Context, sender: String?, pkg: String?): Boolean {
        ensureLoaded(ctx)
        if (enrolled.isEmpty()) return false
        val s = sender?.trim()?.uppercase() ?: ""
        val p = pkg?.trim()?.uppercase() ?: ""
        return enrolled.contains(s) || enrolled.contains(p)
    }


    // ── Liveness ─────────────────────────────────────────────────────────────
    //
    // A listener can stop without saying so: OEM battery managers unbind it,
    // and "remove permissions if app unused" revokes the grant after days of
    // not opening the app. Neither produces an error, and an empty ledger looks
    // exactly like a quiet week.
    //
    // The disambiguator is that this service sees EVERY notification, not only
    // bank alerts — dozens a day, entirely independent of whether Sadeq spent
    // anything. So a recent heartbeat with no bank alerts means a quiet week,
    // and no heartbeat at all means the pipe is dead.
    //
    // Written on every notification and read rarely, so it is kept in its own
    // tiny file rather than rewriting the alert queue.

    private const val HEALTH_FILE = "kai_capture_health.json"

    @Synchronized
    fun noteSeen(ctx: Context, timestamp: Long) {
        runCatching {
            val f = File(ctx.filesDir, HEALTH_FILE)
            val o = if (f.exists()) JSONObject(f.readText()) else JSONObject()
            o.put("lastAnyNotification", timestamp)
            f.writeText(o.toString())
        }
    }

    @Synchronized
    fun noteListenerState(ctx: Context, connected: Boolean) {
        runCatching {
            val f = File(ctx.filesDir, HEALTH_FILE)
            val o = if (f.exists()) JSONObject(f.readText()) else JSONObject()
            o.put("listenerConnected", connected)
            o.put("listenerStateAt", System.currentTimeMillis())
            f.writeText(o.toString())
        }
    }

    fun health(ctx: Context): Map<String, Any?> {
        val o = runCatching {
            val f = File(ctx.filesDir, HEALTH_FILE)
            if (f.exists()) JSONObject(f.readText()) else JSONObject()
        }.getOrDefault(JSONObject())
        return mapOf(
            "lastAnyNotification" to
                (if (o.has("lastAnyNotification")) o.optLong("lastAnyNotification") else null),
            // Absent means never observed. Defaulting to true would report a
            // listener that has never run as healthy.
            "listenerConnected" to
                (if (o.has("listenerConnected")) o.optBoolean("listenerConnected") else false),
            "queued" to pending(ctx),
        )
    }

    /**
     * Append one alert. Idempotent on (sender, text, timestamp): Android
     * redelivers notifications on reconnect, and a duplicated row in a ledger
     * is a wrong balance rather than a cosmetic repeat.
     */
    @Synchronized
    fun capture(ctx: Context, sender: String, text: String, timestamp: Long) {
        if (text.isBlank()) return
        val existing = readRaw(ctx)
        val key = keyOf(sender, text, timestamp)
        for (i in 0 until existing.length()) {
            if (existing.optJSONObject(i)?.optString("key") == key) return
        }
        existing.put(
            JSONObject()
                .put("key", key)
                .put("sender", sender)
                .put("text", text)
                .put("receivedAt", timestamp)
        )
        // Drop the OLDEST if the queue is somehow never drained. Losing the
        // oldest is the least-bad option and it is at least visible: the Dart
        // side sees a gap in timestamps rather than silence.
        while (existing.length() > MAX_QUEUED) existing.remove(0)
        write(ctx, existing)
    }

    /**
     * Hand everything over and clear. Called once per drain from Dart.
     *
     * Clear-on-read is safe here because the Dart side fingerprints every
     * candidate before it reaches the ledger, so a drain that is delivered
     * twice cannot double-count. The failure this avoids is the other one:
     * a queue that is never cleared grows until it is the whole SMS history.
     */
    @Synchronized
    fun drain(ctx: Context): List<Map<String, Any>> {
        val arr = readRaw(ctx)
        val out = ArrayList<Map<String, Any>>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            out.add(
                mapOf(
                    "sender" to o.optString("sender"),
                    "text" to o.optString("text"),
                    "receivedAt" to o.optLong("receivedAt"),
                )
            )
        }
        write(ctx, JSONArray())
        return out
    }

    @Synchronized
    fun pending(ctx: Context): Int = readRaw(ctx).length()

    private fun keyOf(sender: String, text: String, ts: Long) =
        "$sender|${text.trim()}|$ts"

    private fun file(ctx: Context) = File(ctx.filesDir, FILE)

    private fun readRaw(ctx: Context): JSONArray = runCatching {
        val f = file(ctx)
        if (!f.exists()) JSONArray() else JSONArray(f.readText())
    }.getOrDefault(JSONArray())

    private fun write(ctx: Context, arr: JSONArray) {
        runCatching {
            // Write-then-rename, so a kill mid-write leaves the previous queue
            // intact rather than a truncated file. Same reason Core keeps a
            // backup: the thing that eats a ledger is a half-written save.
            val tmp = File(ctx.filesDir, "$FILE.tmp")
            tmp.writeText(arr.toString())
            tmp.renameTo(file(ctx))
        }
    }
}
