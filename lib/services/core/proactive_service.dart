// ProactiveService
//
// Handles the Flutter side of Proactive Kai:
//   1. Registers the FCM token in Firebase so Cloud Functions can push to this device
//   2. Checks the proactive queue on app launch / notification tap
//   3. Returns a pending message to the UI (shown only after the notification is tapped)
//
// Firebase paths:
//   kai/{personaId}/fcm_tokens/{sanitizedToken}  → timestamp (set of tokens)
//   kai/{personaId}/proactive_queue/{id}          → {message, trigger, createdAt, delivered}
//
// Design:
//   - Notification body is intentionally blank — Kai only speaks after tap
//   - The pre-generated message waits in the queue until the app opens
//   - Once displayed, the entry is marked delivered so it never shows again

library;

import 'kai_db.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_service.dart';

class ProactiveMessage {
  final String id;
  final String message;
  final String trigger; // 'curiosity' | 'commitment' | 'checkin'
  final int createdAt;

  const ProactiveMessage({
    required this.id,
    required this.message,
    required this.trigger,
    required this.createdAt,
  });
}

class ProactiveService {
  static final ProactiveService _instance = ProactiveService._internal();
  factory ProactiveService() => _instance;
  ProactiveService._internal();

  static KaiDb? get _db =>
      FirebaseService.isAvailable ? KaiDb.instance : null;

  // ── Initialise (call once on app start) ───────────────────────────────────

  Future<void> initialize(String personaId) async {
    if (_db == null) return;

    try {
      final messaging = FirebaseMessaging.instance;

      // Request permission (required on iOS; Android auto-grants)
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Register this device's FCM token in Firebase
      final token = await messaging.getToken();
      if (token != null) await _registerToken(personaId, token);

      // Re-register whenever the token rotates
      messaging.onTokenRefresh.listen((newToken) {
        _registerToken(personaId, newToken);
      });

      // When notification is tapped and app was in background/terminated,
      // FirebaseMessaging.getInitialMessage() gives us the launch message.
      // We don't use its payload — instead we check the queue directly.
      // (The queue check happens via checkPendingMessage called from main_mobile)

      print('📲 [Proactive] Initialized for persona $personaId');
    } catch (e) {
      print('📲 [Proactive] Init failed: $e');
    }
  }

  Future<void> _registerToken(String personaId, String token) async {
    // Sanitize token for use as a Firebase key (replace . with _)
    final key = token.replaceAll('.', '_').replaceAll('\$', '_');
    try {
      await _db!
          .ref('kai/$personaId/fcm_tokens/$key')
          .set(DateTime.now().millisecondsSinceEpoch);
      print('📲 [Proactive] FCM token registered');
    } catch (e) {
      print('📲 [Proactive] Token registration failed: $e');
    }
  }

  // ── Queue check — call on app open ────────────────────────────────────────

  /// Returns the oldest undelivered proactive message, or null if none.
  /// Call this on every app resume / cold start, show the result in chat.
  Future<ProactiveMessage?> checkPendingMessage(String personaId) async {
    if (_db == null) return null;
    try {
      final snap = await _db!
          .ref('kai/$personaId/proactive_queue')
          .orderByChild('delivered')
          .equalTo(false)
          .limitToFirst(1)
          .get();

      if (!snap.exists || snap.value == null) return null;

      final entries = Map<String, dynamic>.from(snap.value as Map);
      final entry = entries.entries.first;
      final data = Map<String, dynamic>.from(entry.value as Map);

      return ProactiveMessage(
        id:        entry.key,
        message:   data['message']?.toString() ?? '',
        trigger:   data['trigger']?.toString() ?? 'checkin',
        createdAt: (data['createdAt'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      print('📲 [Proactive] Queue check failed: $e');
      return null;
    }
  }

  /// Mark a message as delivered so it never shows again.
  ///
  /// The `catch (_) {}` here used to be harmless — a failed write meant one
  /// message showed twice. It is now load-bearing: proactiveKai will not send
  /// another message while one sits unread, so a silent failure here makes Kai
  /// go quiet and gives nobody a reason why. That is the exact shape of every
  /// bug in this codebase — a real event, swallowed, rendered as nothing.
  ///
  /// Still swallowed, because a broken write must never break an app resume.
  /// But it says so now.
  Future<void> markDelivered(String personaId, String messageId) async {
    if (_db == null) return;
    try {
      await _db!
          .ref('kai/$personaId/proactive_queue/$messageId/delivered')
          .set(true);
    } catch (e) {
      print('📲 [Proactive] markDelivered FAILED for $messageId: $e — he will '
          'not reach out again until this clears or ages out.');
    }
  }
}
