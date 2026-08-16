package com.homecoming.app

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.*

/**
 * KaiToolsPlugin — Android-side handler for Kai's agentic tool calls.
 *
 * Registered on channel "com.homecoming.app/kai_tools" from MainActivity.
 * Each method corresponds to a tool in ToolExecutorService.toolDefinitions.
 *
 * Tools:
 *  setAlarm     → AlarmClock intent (no extra permissions needed)
 *  setTimer     → AlarmClock intent (no extra permissions needed)
 *  readCalendar → CalendarContract query (needs READ_CALENDAR permission)
 *  openApp      → PackageManager lookup + startActivity
 */
class KaiToolsPlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.homecoming.app/kai_tools"
        private const val TAG = "KaiToolsPlugin"
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
        Log.d(TAG, "KaiToolsPlugin registered on $CHANNEL")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "Tool call: ${call.method}")
        when (call.method) {
            "setAlarm"            -> setAlarm(call, result)
            "setTimer"            -> setTimer(call, result)
            "readCalendar"        -> readCalendar(call, result)
            "openApp"             -> openApp(call, result)
            "sendWhatsapp"        -> sendWhatsapp(call, result)
            "createCalendarEvent" -> createCalendarEvent(call, result)
            "callContact"         -> callContact(call, result)
            "playMusic"           -> playMusic(call, result)
            "navigateTo"          -> navigateTo(call, result)
            "sendSms"             -> sendSms(call, result)
            "setReminder"         -> setReminder(call, result)
            "readCalendarBetween"       -> readCalendarBetween(call, result)
            "readNotifications"         -> readNotifications(call, result)
            "checkNotificationAccess"   -> checkNotificationAccess(result)
            "openNotificationSettings"  -> openNotificationSettings(result)
            "readScreen"                -> readScreen(result)
            "checkAccessibilityAccess"  -> checkAccessibilityAccess(result)
            "openAccessibilitySettings" -> openAccessibilitySettings(result)
            "drainBankAlerts"           -> drainBankAlerts(result)
            "pendingBankAlerts"         -> result.success(KaiBankAlertStore.pending(context))
            "captureHealth"             -> result.success(
                KaiBankAlertStore.health(context) +
                    mapOf("accessGranted" to isNotificationAccessGranted())
            )
            "setBankSenders"            -> setBankSenders(call, result)
            else                        -> result.notImplemented()
        }
    }

    // ── Set alarm ─────────────────────────────────────────────────────────────
    // Uses AlarmClock.ACTION_SET_ALARM — works on all Android clock apps,
    // no special permission required.

    private fun setAlarm(call: MethodCall, result: MethodChannel.Result) {
        try {
            val hour   = call.argument<Int>("hour")          ?: 8
            val minute = call.argument<Int>("minute")        ?: 0
            val label  = call.argument<String>("label")      ?: "Kai alarm"

            val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(AlarmClock.EXTRA_HOUR, hour)
                putExtra(AlarmClock.EXTRA_MINUTES, minute)
                putExtra(AlarmClock.EXTRA_MESSAGE, label)
                putExtra(AlarmClock.EXTRA_SKIP_UI, true) // silent — no confirmation screen
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)

            val h = hour.toString().padStart(2, '0')
            val m = minute.toString().padStart(2, '0')
            val msg = "Alarm set for $h:$m — $label"
            Log.d(TAG, msg)
            result.success(msg)
        } catch (e: Exception) {
            Log.e(TAG, "setAlarm failed", e)
            result.error("ALARM_ERROR", e.message, null)
        }
    }

    // ── Set timer ─────────────────────────────────────────────────────────────
    // Uses AlarmClock.ACTION_SET_TIMER — works on all Android clock apps,
    // no special permission required.

    private fun setTimer(call: MethodCall, result: MethodChannel.Result) {
        try {
            val seconds = call.argument<Int>("seconds")      ?: 60
            val label   = call.argument<String>("label")     ?: "Kai timer"

            val intent = Intent(AlarmClock.ACTION_SET_TIMER).apply {
                putExtra(AlarmClock.EXTRA_LENGTH, seconds)
                putExtra(AlarmClock.EXTRA_MESSAGE, label)
                putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)

            val mins = seconds / 60
            val secs = seconds % 60
            val duration = when {
                mins > 0 && secs > 0 -> "${mins}m ${secs}s"
                mins > 0             -> "${mins} minute${if (mins != 1) "s" else ""}"
                else                 -> "${secs} second${if (secs != 1) "s" else ""}"
            }
            val msg = "Timer started: $duration ($label)"
            Log.d(TAG, msg)
            result.success(msg)
        } catch (e: Exception) {
            Log.e(TAG, "setTimer failed", e)
            result.error("TIMER_ERROR", e.message, null)
        }
    }

    // ── Read calendar ─────────────────────────────────────────────────────────
    // Requires READ_CALENDAR permission (declared in AndroidManifest + runtime grant).
    // Returns a human-readable event list for GPT to summarise.

    private fun readCalendar(call: MethodCall, result: MethodChannel.Result) {
        try {
            val daysAhead = (call.argument<Int>("daysAhead") ?: 7).coerceIn(1, 30)
            val now       = System.currentTimeMillis()
            val future    = now + daysAhead * 24 * 60 * 60 * 1000L

            val projection = arrayOf(
                CalendarContract.Events.TITLE,
                CalendarContract.Events.DTSTART,
                CalendarContract.Events.DTEND,
                CalendarContract.Events.DESCRIPTION,
                CalendarContract.Events.EVENT_LOCATION,
                CalendarContract.Events.ALL_DAY,
            )
            val selection = (
                "${CalendarContract.Events.DTSTART} >= ? AND " +
                "${CalendarContract.Events.DTSTART} <= ? AND " +
                "${CalendarContract.Events.DELETED} = 0"
            )
            val selArgs   = arrayOf(now.toString(), future.toString())
            val sortOrder = "${CalendarContract.Events.DTSTART} ASC"

            val cursor = context.contentResolver.query(
                CalendarContract.Events.CONTENT_URI,
                projection, selection, selArgs, sortOrder
            )

            if (cursor == null) {
                result.success("No calendar found or permission not granted.")
                return
            }

            val sdf = SimpleDateFormat("EEE d MMM 'at' HH:mm", Locale.ENGLISH)
            val buf = StringBuilder()
            var count = 0

            cursor.use { c ->
                while (c.moveToNext() && count < 15) {
                    val title    = c.getString(0) ?: "Untitled event"
                    val start    = c.getLong(1)
                    val desc     = c.getString(3)?.take(80)?.replace('\n', ' ')
                    val location = c.getString(4)
                    val allDay   = c.getInt(5) == 1

                    buf.append("• $title\n")
                    buf.append("  When: ${if (allDay) "All day" else sdf.format(Date(start))}\n")
                    if (!location.isNullOrBlank()) buf.append("  Where: $location\n")
                    if (!desc.isNullOrBlank())     buf.append("  Note: $desc\n")
                    buf.append("\n")
                    count++
                }
            }

            val response = if (count == 0) {
                "No events in the next $daysAhead day${if (daysAhead != 1) "s" else ""}."
            } else {
                "Upcoming events (next $daysAhead days):\n\n${buf.toString().trimEnd()}"
            }

            Log.d(TAG, "readCalendar: $count event(s) found")
            result.success(response)

        } catch (e: SecurityException) {
            // Permission not yet granted — Kai will tell the user
            Log.w(TAG, "Calendar permission denied")
            result.success(
                "I don't have calendar access yet. " +
                "Please grant the Calendar permission in Settings → Apps → Homecoming → Permissions."
            )
        } catch (e: Exception) {
            Log.e(TAG, "readCalendar failed", e)
            result.error("CALENDAR_ERROR", e.message, null)
        }
    }

    // ── Open app ──────────────────────────────────────────────────────────────
    // Looks up by known package name first, then fuzzy-matches installed app labels.

    private fun openApp(call: MethodCall, result: MethodChannel.Result) {
        try {
            val appName = (call.argument<String>("appName") ?: "").trim()
            val key     = appName.lowercase()
            val pm      = context.packageManager

            // Known package names — extend freely
            val knownPackages = mapOf(
                "maps"         to "com.google.android.apps.maps",
                "google maps"  to "com.google.android.apps.maps",
                "camera"       to "com.android.camera2",
                "settings"     to "com.android.settings",
                "spotify"      to "com.spotify.music",
                "youtube"      to "com.google.android.youtube",
                "whatsapp"     to "com.whatsapp",
                "instagram"    to "com.instagram.android",
                "twitter"      to "com.twitter.android",
                "x"            to "com.twitter.android",
                "telegram"     to "org.telegram.messenger",
                "chrome"       to "com.android.chrome",
                "gmail"        to "com.google.android.gm",
                "calendar"     to "com.google.android.calendar",
                "clock"        to "com.google.android.deskclock",
                "calculator"   to "com.google.android.calculator",
                "photos"       to "com.google.android.apps.photos",
                "netflix"      to "com.netflix.mediaclient",
                "uber"         to "com.ubercab",
                "snapchat"     to "com.snapchat.android",
                "tiktok"       to "com.zhiliaoapp.musically",
                "linkedin"     to "com.linkedin.android",
                "facebook"     to "com.facebook.katana",
                "messages"     to "com.google.android.apps.messaging",
                "phone"        to "com.google.android.dialer",
                "contacts"     to "com.google.android.contacts",
                "files"        to "com.google.android.apps.nbu.files",
                "play store"   to "com.android.vending",
                "maps"         to "com.google.android.apps.maps",
            )

            // Try known mapping first
            val packageName = knownPackages[key]
            var launchIntent = packageName?.let { pkg ->
                runCatching { pm.getLaunchIntentForPackage(pkg) }.getOrNull()
            }

            // Fallback: fuzzy match installed app labels
            if (launchIntent == null) {
                val installed = pm.getInstalledApplications(0)
                val match = installed.firstOrNull { appInfo ->
                    pm.getApplicationLabel(appInfo).toString().lowercase().contains(key)
                }
                launchIntent = match?.let {
                    runCatching { pm.getLaunchIntentForPackage(it.packageName) }.getOrNull()
                }
            }

            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(launchIntent)
                val msg = "Opened $appName."
                Log.d(TAG, msg)
                result.success(msg)
            } else {
                val msg = "Couldn't find \"$appName\" on this device."
                Log.w(TAG, msg)
                result.success(msg)
            }
        } catch (e: Exception) {
            Log.e(TAG, "openApp failed", e)
            result.error("APP_ERROR", e.message, null)
        }
    }

    // ── Send WhatsApp ─────────────────────────────────────────────────────────

    private fun sendWhatsapp(call: MethodCall, result: MethodChannel.Result) {
        try {
            val contact = (call.argument<String>("contact") ?: "").trim()
            val message = (call.argument<String>("message") ?: "").trim()

            val phone = if (contact.matches(Regex("[+\\d][\\d\\s\\-()]+"))) {
                contact.filter { it.isDigit() || it == '+' }
            } else {
                val matches = resolveAllContacts(contact)
                when {
                    matches.isEmpty() -> {
                        result.success(
                            "I couldn't find a phone number for \"$contact\" in your contacts. " +
                            "What's their WhatsApp number (with country code)?"
                        )
                        return
                    }
                    matches.size > 1 -> {
                        result.success(ambiguousContactResult(contact, matches))
                        return
                    }
                    else -> matches[0].second
                }
            }

            if (phone == null) {
                result.success(
                    "I couldn't find a phone number for \"$contact\" in your contacts. " +
                    "What's their WhatsApp number (with country code)?"
                )
                return
            }

            val cleanPhone = phone.filter { it.isDigit() || it == '+' }
            val intent = Intent(Intent.ACTION_VIEW,
                Uri.parse("https://api.whatsapp.com/send?phone=$cleanPhone&text=${Uri.encode(message)}")
            ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }

            context.startActivity(intent)
            Log.d(TAG, "sendWhatsapp: $cleanPhone")
            result.success("WhatsApp opened — send the message to $contact when ready.")
        } catch (e: Exception) {
            Log.e(TAG, "sendWhatsapp failed", e)
            result.error("WHATSAPP_ERROR", e.message, null)
        }
    }

    // ── Create calendar event ─────────────────────────────────────────────────

    private fun createCalendarEvent(call: MethodCall, result: MethodChannel.Result) {
        try {
            val title       = (call.argument<String>("title")       ?: "New Event").trim()
            val date        = (call.argument<String>("date")        ?: "").trim()
            val startTime   = (call.argument<String>("startTime")   ?: "09:00").trim()
            val endTime     = (call.argument<String>("endTime")     ?: "").trim()
            val description = (call.argument<String>("description") ?: "").trim()
            val location    = (call.argument<String>("location")    ?: "").trim()

            if (date.isEmpty()) {
                result.success("What date should I create the event on? (e.g. 2026-07-01)")
                return
            }

            val sdf = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.ENGLISH).apply {
                timeZone = TimeZone.getTimeZone("Asia/Bahrain")
            }
            val startMs = sdf.parse("$date $startTime")?.time ?: run {
                result.success("I couldn't parse \"$date $startTime\". Try format: 2026-07-01 14:00.")
                return
            }
            val endMs = if (endTime.isNotEmpty()) {
                sdf.parse("$date $endTime")?.time ?: (startMs + 3_600_000L)
            } else {
                startMs + 3_600_000L
            }

            // Try silent ContentResolver insert (requires WRITE_CALENDAR)
            try {
                val values = ContentValues().apply {
                    put(CalendarContract.Events.TITLE, title)
                    put(CalendarContract.Events.DTSTART, startMs)
                    put(CalendarContract.Events.DTEND, endMs)
                    put(CalendarContract.Events.DESCRIPTION, description)
                    put(CalendarContract.Events.EVENT_LOCATION, location)
                    put(CalendarContract.Events.CALENDAR_ID, 1)
                    put(CalendarContract.Events.EVENT_TIMEZONE, "Asia/Bahrain")
                }
                val uri = context.contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
                if (uri != null) {
                    Log.d(TAG, "createCalendarEvent: inserted — $title")
                    result.success("Done! \"$title\" added to your calendar on $date at $startTime.")
                    return
                }
            } catch (_: SecurityException) {
                Log.w(TAG, "WRITE_CALENDAR not granted — falling back to intent")
            }

            // Fallback: open Calendar app pre-filled (no permission needed)
            val intent = Intent(Intent.ACTION_INSERT, CalendarContract.Events.CONTENT_URI).apply {
                putExtra(CalendarContract.Events.TITLE, title)
                putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startMs)
                putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endMs)
                putExtra(CalendarContract.Events.DESCRIPTION, description)
                putExtra(CalendarContract.Events.EVENT_LOCATION, location)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            result.success("Calendar opened with \"$title\" pre-filled — just tap Save.")
        } catch (e: Exception) {
            Log.e(TAG, "createCalendarEvent failed", e)
            result.error("CALENDAR_WRITE_ERROR", e.message, null)
        }
    }

    // ── Call contact ──────────────────────────────────────────────────────────

    private fun callContact(call: MethodCall, result: MethodChannel.Result) {
        try {
            val contact = (call.argument<String>("contact") ?: "").trim()

            val phone = if (contact.matches(Regex("[+\\d][\\d\\s\\-()]+"))) {
                contact.filter { it.isDigit() || it == '+' }
            } else {
                val matches = resolveAllContacts(contact)
                when {
                    matches.isEmpty() -> {
                        result.success("I couldn't find a number for \"$contact\". What's their number?")
                        return
                    }
                    matches.size > 1 -> {
                        result.success(ambiguousContactResult(contact, matches))
                        return
                    }
                    else -> matches[0].second
                }
            }

            if (phone == null) {
                result.success("I couldn't find a number for \"$contact\". What's their number?")
                return
            }

            val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phone")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            Log.d(TAG, "callContact: $phone")
            result.success("Dialer opened for $contact — tap the green button to call.")
        } catch (e: Exception) {
            Log.e(TAG, "callContact failed", e)
            result.error("CALL_ERROR", e.message, null)
        }
    }

    // ── Play music ────────────────────────────────────────────────────────────

    private fun playMusic(call: MethodCall, result: MethodChannel.Result) {
        try {
            val query = (call.argument<String>("query") ?: "").trim()
            val app   = (call.argument<String>("app")   ?: "spotify").lowercase()

            if (query.isEmpty()) {
                result.success("What would you like me to play?")
                return
            }

            val spotifyInstalled = runCatching {
                context.packageManager.getPackageInfo("com.spotify.music", 0); true
            }.getOrDefault(false)

            if (app != "youtube" && spotifyInstalled) {
                val intent = Intent(Intent.ACTION_VIEW,
                    Uri.parse("spotify:search:${Uri.encode(query)}")
                ).apply {
                    setPackage("com.spotify.music")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                Log.d(TAG, "playMusic: Spotify — $query")
                result.success("Searching Spotify for \"$query\".")
            } else {
                val ytInstalled = runCatching {
                    context.packageManager.getPackageInfo("com.google.android.youtube", 0); true
                }.getOrDefault(false)

                val ytUri = Uri.parse("https://www.youtube.com/results?search_query=${Uri.encode(query)}")
                val intent = Intent(Intent.ACTION_VIEW, ytUri).apply {
                    if (ytInstalled) setPackage("com.google.android.youtube")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                Log.d(TAG, "playMusic: YouTube — $query")
                result.success("Searching YouTube for \"$query\".")
            }
        } catch (e: Exception) {
            Log.e(TAG, "playMusic failed", e)
            result.error("MUSIC_ERROR", e.message, null)
        }
    }

    // ── Shared helper: contact name → phone number ────────────────────────────

    /** Returns all (displayName, phone) pairs matching [name]. */
    private fun resolveAllContacts(name: String): List<Pair<String, String>> {
        return try {
            val cursor = context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.NUMBER,
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ),
                "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?",
                arrayOf("%$name%"),
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC"
            )
            val results = mutableListOf<Pair<String, String>>()
            cursor?.use { c ->
                val nameIdx = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                val numIdx  = c.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                while (c.moveToNext()) {
                    val displayName = c.getString(nameIdx) ?: continue
                    val phone       = c.getString(numIdx)  ?: continue
                    // Deduplicate by name (keep first number per unique name)
                    if (results.none { it.first == displayName }) {
                        results.add(Pair(displayName, phone))
                    }
                }
            }
            results
        } catch (e: SecurityException) {
            Log.w(TAG, "READ_CONTACTS denied — can't resolve \"$name\"")
            emptyList()
        }
    }

    /** Returns the phone number if exactly one contact matches, null otherwise. */
    private fun resolveContactPhone(name: String): String? {
        val matches = resolveAllContacts(name)
        return if (matches.size == 1) matches[0].second else null
    }

    /** Builds a disambiguation result string for Kai when multiple contacts match. */
    private fun ambiguousContactResult(name: String, matches: List<Pair<String, String>>): String {
        val nameList = matches.joinToString(" | ") { it.first }
        return "Multiple contacts found for \"$name\": ${matches.joinToString(", ") { it.first }}. " +
               "Please clarify which one. [CHOICES: $nameList]"
    }

    // ── Navigate to ───────────────────────────────────────────────────────────
    // Opens Google Maps in navigation mode. Falls back to a geo search if Maps
    // is not installed.

    private fun navigateTo(call: MethodCall, result: MethodChannel.Result) {
        try {
            val destination = (call.argument<String>("destination") ?: "").trim()
            if (destination.isEmpty()) {
                result.success("Where would you like me to navigate to?")
                return
            }

            // Try Google Maps navigation deep-link first
            val mapsInstalled = runCatching {
                context.packageManager.getPackageInfo("com.google.android.apps.maps", 0); true
            }.getOrDefault(false)

            val intent = if (mapsInstalled) {
                Intent(Intent.ACTION_VIEW,
                    Uri.parse("google.navigation:q=${Uri.encode(destination)}&mode=d")
                ).apply { setPackage("com.google.android.apps.maps") }
            } else {
                Intent(Intent.ACTION_VIEW,
                    Uri.parse("geo:0,0?q=${Uri.encode(destination)}")
                )
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)

            Log.d(TAG, "navigateTo: $destination")
            result.success("Navigation started to \"$destination\".")
        } catch (e: Exception) {
            Log.e(TAG, "navigateTo failed", e)
            result.error("NAV_ERROR", e.message, null)
        }
    }

    // ── Send SMS ──────────────────────────────────────────────────────────────
    // Opens the default SMS app with the number and message pre-filled.
    // No SEND_SMS permission needed — ACTION_SENDTO just opens the compose view.

    private fun sendSms(call: MethodCall, result: MethodChannel.Result) {
        try {
            val contact = (call.argument<String>("contact") ?: "").trim()
            val message = (call.argument<String>("message") ?: "").trim()

            val phone = if (contact.matches(Regex("[+\\d][\\d\\s\\-()]+"))) {
                contact.filter { it.isDigit() || it == '+' }
            } else {
                val matches = resolveAllContacts(contact)
                when {
                    matches.isEmpty() -> {
                        result.success(
                            "I couldn't find a number for \"$contact\" in your contacts. " +
                            "What's their number?"
                        )
                        return
                    }
                    matches.size > 1 -> {
                        result.success(ambiguousContactResult(contact, matches))
                        return
                    }
                    else -> matches[0].second
                }
            }

            if (phone == null) {
                result.success(
                    "I couldn't find a number for \"$contact\" in your contacts. " +
                    "What's their number?"
                )
                return
            }

            val intent = Intent(Intent.ACTION_SENDTO,
                Uri.parse("smsto:$phone")
            ).apply {
                putExtra("sms_body", message)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            Log.d(TAG, "sendSms: $phone")
            result.success("SMS app opened to $contact — tap Send when ready.")
        } catch (e: Exception) {
            Log.e(TAG, "sendSms failed", e)
            result.error("SMS_ERROR", e.message, null)
        }
    }

    // ── Set reminder ──────────────────────────────────────────────────────────
    // Uses AlarmClock.ACTION_SET_ALARM with a reminder-style label so it shows
    // up in the clock app as a named reminder. Silent (EXTRA_SKIP_UI = true).

    private fun setReminder(call: MethodCall, result: MethodChannel.Result) {
        try {
            val message = (call.argument<String>("message") ?: "Reminder").trim()
            val hour    = call.argument<Int>("hour")   ?: 9
            val minute  = call.argument<Int>("minute") ?: 0

            val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(AlarmClock.EXTRA_HOUR, hour)
                putExtra(AlarmClock.EXTRA_MINUTES, minute)
                putExtra(AlarmClock.EXTRA_MESSAGE, "🔔 $message")
                putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)

            val h = hour.toString().padStart(2, '0')
            val m = minute.toString().padStart(2, '0')
            Log.d(TAG, "setReminder: $h:$m — $message")
            result.success("Reminder set for $h:$m — \"$message\".")
        } catch (e: Exception) {
            Log.e(TAG, "setReminder failed", e)
                   result.error("REMINDER_ERROR", e.message, null)
        }
    }

    // ── Read calendar between two timestamps ──────────────────────────────────
    // Used by ContextInjectionService to find events that happened between the
    // last chat session and now (so Kai can ask "how did the meeting go?").

    private fun readCalendarBetween(call: MethodCall, result: MethodChannel.Result) {
        try {
            val fromMs = call.argument<Long>("fromMs") ?: return result.success("")
            val toMs   = call.argument<Long>("toMs")   ?: System.currentTimeMillis()

            val projection = arrayOf(
                CalendarContract.Events.TITLE,
                CalendarContract.Events.DTSTART,
                CalendarContract.Events.DTEND,
                CalendarContract.Events.ALL_DAY,
                CalendarContract.Events.EVENT_LOCATION,
            )
            val selection = (
                "${CalendarContract.Events.DTSTART} >= ? AND " +
                "${CalendarContract.Events.DTSTART} <= ? AND " +
                "${CalendarContract.Events.DELETED} = 0"
            )
            val cursor = context.contentResolver.query(
                CalendarContract.Events.CONTENT_URI,
                projection,
                selection,
                arrayOf(fromMs.toString(), toMs.toString()),
                "${CalendarContract.Events.DTSTART} ASC"
            ) ?: return result.success("")

            val sdf = SimpleDateFormat("EEE d MMM 'at' HH:mm", Locale.ENGLISH)
            val buf = StringBuilder()
            var count = 0

            cursor.use { c ->
                while (c.moveToNext() && count < 10) {
                    val title  = c.getString(0) ?: "Untitled"
                    val start  = c.getLong(1)
                    val allDay = c.getInt(3) == 1
                    val where  = c.getString(4)

                    buf.append("• $title")
                    if (!allDay) buf.append(" (${sdf.format(Date(start))})")
                    if (!where.isNullOrBlank()) buf.append(" @ $where")
                    buf.append("\n")
                    count++
                }
            }

            result.success(if (count == 0) "" else buf.toString().trimEnd())
        } catch (e: SecurityException) {
            result.success("")
        } catch (e: Exception) {
            Log.e(TAG, "readCalendarBetween failed", e)
            result.success("")
        }
    }

    // ── Read notifications ────────────────────────────────────────────────────
    // Reads from KaiNotificationService's in-memory store.
    // Returns empty + guidance if notification access hasn't been granted.

    private fun readNotifications(call: MethodCall, result: MethodChannel.Result) {
        if (!isNotificationAccessGranted()) {
            result.success(
                "I don't have notification access yet. " +
                "To fix this: go to Settings → Apps → Special app access → " +
                "Notification access → enable Homecoming. " +
                "Then I'll be able to read your WhatsApp messages and other notifications."
            )
            return
        }

        val appName = (call.argument<String>("appName") ?: "").trim()
        val limit   = (call.argument<Int>("limit") ?: 5).coerceIn(1, 20)
        val notifs  = KaiNotificationService.getNotifications(
            appName.ifBlank { null }, limit
        )

        if (notifs.isEmpty()) {
            val label = if (appName.isBlank()) "any app" else appName
            result.success(
                "No recent notifications from $label captured yet. " +
                "Notifications are only captured after Kai is running — " +
                "ask me again after you receive a new message."
            )
            return
        }

        val sdf = SimpleDateFormat("HH:mm", Locale.ENGLISH)
        val buf = StringBuilder()
        val label = if (appName.isBlank()) "recent notifications" else "$appName notifications"
        buf.appendLine("Here are your $label:")
        notifs.forEach { n ->
            val time = sdf.format(Date(n.timestamp))
            buf.appendLine("• [$time] ${n.sender}: ${n.text}")
        }
        Log.d(TAG, "readNotifications: ${notifs.size} returned")
        result.success(buf.toString().trimEnd())
    }

    // ── Check notification access ─────────────────────────────────────────────

    private fun checkNotificationAccess(result: MethodChannel.Result) {
        result.success(isNotificationAccessGranted())
    }

    private fun isNotificationAccessGranted(): Boolean {
        val enabled = android.provider.Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners"
        ) ?: return false
        return enabled.contains(context.packageName)
    }


    // ── Open notification settings ────────────────────────────────────────────

    private fun openNotificationSettings(result: MethodChannel.Result) {
        try {
            val intent = android.content.Intent(
                "android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS"
            ).apply { addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK) }
            context.startActivity(intent)
            result.success("Notification settings opened — enable Homecoming there.")
        } catch (e: Exception) {
            result.error("SETTINGS_ERROR", e.message, null)
        }
    }

    // ── Screen reading (AccessibilityService) ─────────────────────────────────

    private fun readScreen(result: MethodChannel.Result) {
        if (!KaiAccessibilityService.isRunning()) {
            result.success(
                "Accessibility access not granted. " +
                "Ask the user to go to Settings → Accessibility → Installed apps → Homecoming → enable it. " +
                "You can also call openAccessibilitySettings to open Settings directly."
            )
            return
        }
        val snapshot = KaiAccessibilityService.getSnapshot()
        if (snapshot == null) {
            result.success("Screen snapshot unavailable — try again in a moment.")
            return
        }
        val out = buildString {
            appendLine("APP: ${snapshot.appName} (${snapshot.packageName})")
            appendLine("---")
            append(snapshot.text.ifBlank { "(no readable text on screen)" })
        }
        result.success(out)
    }

    private fun checkAccessibilityAccess(result: MethodChannel.Result) {
        result.success(KaiAccessibilityService.isRunning())
    }

    private fun openAccessibilitySettings(result: MethodChannel.Result) {
        try {
            val intent = android.content.Intent(
                android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS
            ).apply { addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK) }
            context.startActivity(intent)
            result.success("Accessibility settings opened — tap Homecoming and enable it.")
        } catch (e: Exception) {
            result.error("SETTINGS_ERROR", e.message, null)
        }
    }

    // ── Bank alerts ───────────────────────────────────────────────────────────
    //
    // Hands the durable queue to Dart and clears it. Clear-on-read is safe
    // because every candidate is fingerprinted before it reaches the ledger, so
    // a drain delivered twice cannot double-count. The failure worth avoiding
    // is the other one: a queue never cleared becomes the whole SMS history.
    //
    // No parsing here. Amount, direction and merchant are decided in pure Dart
    // where the logic is testable without a phone.

    private fun drainBankAlerts(result: MethodChannel.Result) {
        if (!isNotificationAccessGranted()) {
            result.error(
                "no_notification_access",
                "Notification access is not granted, so bank alerts cannot be captured.",
                null,
            )
            return
        }
        result.success(KaiBankAlertStore.drain(context))
    }

    // Dart owns the enrolment list; this pushes it down as a capture filter.
    // Replaces rather than appends, so removing a sender in the app actually
    // removes it here — a revocation that only adds is not a revocation.
    private fun setBankSenders(call: MethodCall, result: MethodChannel.Result) {
        val senders = call.argument<List<String>>("senders") ?: emptyList()
        KaiBankAlertStore.setEnrolled(context, senders)
        result.success(KaiBankAlertStore.enrolledSenders(context).size)
    }

}
