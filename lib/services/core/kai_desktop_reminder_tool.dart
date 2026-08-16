// `set_reminder` on the desktop workbench: a promise, not a phone alarm.
//
// On Android the tool reaches the native reminder plugin and always has. On
// desktop that plugin does not exist, so the same words now become a durable
// Central Core commitment — the front door to the vertical slice Briefs 013-016
// built behind it.
//
// The whole file exists to make one thing hard to get wrong: Kai must not say
// "done" until Core says so. Every failure below returns an honest refusal and
// leaves nothing behind, because a reminder Sadeq was promised and never gets
// is worse than one he was told couldn't be set.
library;

import 'kai_core_client.dart';
import 'kai_scheduled_commitment.dart';

/// What the desktop path did, in the tool's own reply vocabulary.
class KaiDesktopReminderResult {
  const KaiDesktopReminderResult._(this.ok, this.message, {this.commitmentId});

  const KaiDesktopReminderResult.failure(String message)
      : this._(false, message);

  const KaiDesktopReminderResult.success(
    String message, {
    required String commitmentId,
  }) : this._(true, message, commitmentId: commitmentId);

  final bool ok;
  final String message;
  final String? commitmentId;
}

/// Creates one Core commitment from the model's `set_reminder` arguments.
class KaiDesktopReminderTool {
  KaiDesktopReminderTool({
    required this.client,
    required this.now,
    this.personaId = 'truekai',
  });

  final KaiCoreClient client;
  final DateTime Function() now;
  final String personaId;

  /// The model's arguments are Bahrain wall-clock components, always.
  ///
  /// Not the host's timezone, and not UTC. Sadeq says "remind me at nine" in
  /// the only clock he lives in; a coordinator on a machine set to London must
  /// still fire at nine in Bahrain. The offset is stated, never derived.
  Future<KaiDesktopReminderResult> create(Map<String, dynamic> args) async {
    final rawMessage = args['message'];
    if (rawMessage is! String || rawMessage.trim().isEmpty) {
      return const KaiDesktopReminderResult.failure(
        'I need the reminder text before I can set it.',
      );
    }
    // Trim decides emptiness; it does not become the stored text. What Sadeq
    // is read back must be what was promised, byte for byte.
    final message = rawMessage;

    final year = _integer(args['year']);
    final month = _integer(args['month']);
    final day = _integer(args['day']);
    final hour = _integer(args['hour']);
    final minute = _integer(args['minute']);
    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null) {
      return const KaiDesktopReminderResult.failure(
        'I need a complete date and time — year, month, day, hour and minute.',
      );
    }

    final DateTime dueAtUtc;
    try {
      // Validates rather than normalises: 31 February would otherwise become
      // 3 March and Kai would confidently promise a date nobody chose.
      dueAtUtc = KaiScheduledCommitment.bahrainWallToUtc(
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
      );
    } on FormatException catch (error) {
      return KaiDesktopReminderResult.failure(
        "That date and time doesn't exist (${error.message}).",
      );
    }

    if (!dueAtUtc.isAfter(now().toUtc())) {
      return const KaiDesktopReminderResult.failure(
        "That time has already passed — I can't set a reminder in the past.",
      );
    }

    final commitmentId = KaiScheduledCommitment.deterministicId(
      personaId: personaId,
      text: message,
      dueAtUtc: dueAtUtc,
    );

    try {
      // Await the DURABLE result. Reporting success from anything else — a
      // queued write, a local echo, an optimistic assumption — is how a
      // promise gets lost while sounding kept.
      final stored = await client.createCommitment(
        commitmentId: commitmentId,
        personaId: personaId,
        text: message,
        dueAt: dueAtUtc,
        dueWallClock: KaiScheduledCommitment.wallClockLabel(
          year: year,
          month: month,
          day: day,
          hour: hour,
          minute: minute,
        ),
        dueWallOffsetMinutes: KaiScheduledCommitment.bahrainOffsetMinutes,
      );

      // Read the confirmation back off the STORED record, so the receipt
      // describes what Core actually holds. A deterministic id means a retry
      // after an uncertain response returns this same record rather than
      // minting a second promise.
      final storedWall = stored['dueWallClock']?.toString() ?? '';
      return KaiDesktopReminderResult.success(
        'Reminder set for $storedWall Bahrain time.',
        commitmentId: stored['commitmentId']?.toString() ?? commitmentId,
      );
    } on KaiCoreException catch (error) {
      return KaiDesktopReminderResult.failure(
        "I couldn't save that reminder (${error.message}). "
        'Nothing was scheduled — ask me again and it will be safe to retry.',
      );
    } catch (error) {
      // Timeout, socket failure, Core not running. Same honesty: no receipt.
      return const KaiDesktopReminderResult.failure(
        "I couldn't reach my core to save that reminder, so nothing was "
        'scheduled. Ask me again and it will be safe to retry.',
      );
    }
  }

  /// Accepts an int, or a num/String that is exactly an integer.
  ///
  /// The model sometimes sends `"9"` or `9.0`. It must never send `9.5` and
  /// have it silently become a time.
  static int? _integer(Object? value) {
    if (value is int) return value;
    if (value is num) {
      return value == value.roundToDouble() ? value.toInt() : null;
    }
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}
