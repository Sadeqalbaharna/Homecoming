// Pure domain helpers for scheduled commitments.
//
// Deliberately separate from KaiCoreServer and free of I/O, so the two things
// most likely to be got quietly wrong — the timezone conversion and the
// identity digest — can be tested exactly and cheaply.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

class KaiScheduledCommitment {
  const KaiScheduledCommitment._();

  /// Bahrain is UTC+03:00 with no daylight saving, ever.
  ///
  /// Stated as a constant rather than derived, because deriving it would mean
  /// reading the host machine's timezone — and the host is not authoritative
  /// for when Sadeq asked to be reminded. A laptop on aeroplane time, a CI
  /// runner in UTC, and a future server elsewhere must all produce the same
  /// instant from the same words.
  static const bahrainOffset = Duration(hours: 3);
  static const bahrainOffsetMinutes = 180;

  /// Convert a Bahrain wall-clock reading to a UTC instant, once.
  ///
  /// Validates rather than normalises: Dart's DateTime constructor silently
  /// rolls month 13 into next January and day 30 of February into March, so a
  /// typo would otherwise become a real reminder at a time nobody asked for.
  static DateTime bahrainWallToUtc({
    required int year,
    required int month,
    required int day,
    required int hour,
    required int minute,
  }) {
    if (month < 1 || month > 12) {
      throw const FormatException('commitment_month_invalid');
    }
    if (day < 1 || day > 31) {
      throw const FormatException('commitment_day_invalid');
    }
    if (hour < 0 || hour > 23) {
      throw const FormatException('commitment_hour_invalid');
    }
    if (minute < 0 || minute > 59) {
      throw const FormatException('commitment_minute_invalid');
    }

    // Build in UTC so no host zone is consulted, then check the constructor
    // did not roll the date — which is how an invalid day is caught.
    final wall = DateTime.utc(year, month, day, hour, minute);
    if (wall.year != year ||
        wall.month != month ||
        wall.day != day ||
        wall.hour != hour ||
        wall.minute != minute) {
      throw const FormatException('commitment_date_invalid');
    }
    return wall.subtract(bahrainOffset);
  }

  /// The wall-clock provenance string stored beside the UTC instant.
  static String wallClockLabel({
    required int year,
    required int month,
    required int day,
    required int hour,
    required int minute,
  }) =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}T'
      '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}:00';

  /// A stable ID derived from persona, normalised text, and the UTC instant.
  ///
  /// Deterministic on purpose. A tool call that is retried — because the model
  /// repeated itself, or the first attempt failed after the write — must reach
  /// the SAME Core record. A random or clock-seeded ID would mint a second
  /// promise on every retry, and Sadeq would be reminded twice.
  ///
  /// Text is normalised (trimmed, whitespace collapsed, lower-cased) so
  /// cosmetic differences in the same intent do not fork the record. The exact
  /// original text is what gets stored and delivered; normalisation only
  /// affects identity.
  static String deterministicId({
    required String personaId,
    required String text,
    required DateTime dueAtUtc,
  }) {
    final normalized =
        text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final material = _digestMaterial([
      personaId,
      normalized,
      dueAtUtc.toUtc().toIso8601String(),
    ]);
    final digest = sha256.convert(utf8.encode(material)).toString();
    // Hex only — no character Firebase forbids in a path segment.
    return 'commit-${digest.substring(0, 32)}';
  }

  /// Length-prefixed digest input: `4:kai 6:remind 20:2026-…`.
  ///
  /// Two faults are fixed at once here. The delimiter used to be a literal NUL
  /// character, which left raw 0x00 bytes embedded in this Dart source — a text
  /// file that some editors, diff tools and terminals will treat as binary.
  ///
  /// And any delimiter is ambiguous, NUL included: with a plain separator,
  /// persona `a` + text `b c` and persona `a b` + text `c` produce identical
  /// material and therefore the SAME commitment id. Two different promises
  /// would silently collapse into one record. A length prefix cannot collide,
  /// because the length is read before the content and no content can forge it.
  static String _digestMaterial(List<String> fields) {
    final buffer = StringBuffer();
    for (final field in fields) {
      final encoded = utf8.encode(field);
      // Byte length, not rune count — the digest is computed over bytes.
      buffer
        ..write(encoded.length)
        ..write(':')
        ..write(field);
    }
    return buffer.toString();
  }

  /// Does [wallClock] under [offsetMinutes] actually produce [dueAtUtc]?
  ///
  /// Provenance is only worth storing if it is true. Without this check a
  /// caller could record "09:00 Bahrain" beside a UTC instant that is nothing
  /// of the kind, and every later reader — including a human auditing why Kai
  /// spoke when he did — would be misled by a field that looks authoritative.
  static bool wallClockMatchesUtc({
    required String wallClock,
    required int offsetMinutes,
    required DateTime dueAtUtc,
  }) {
    if (offsetMinutes != bahrainOffsetMinutes) return false;

    // Exactly the canonical form [wallClockLabel] emits — nothing else.
    //
    // `DateTime.parse` is far more permissive than provenance can afford. It
    // accepts a space separator, omitted seconds, fractional seconds and a `Z`
    // or numeric offset suffix, so four spellings of one instant would all
    // "match" and the stored provenance would no longer be a single canonical
    // reading anyone can compare or re-derive. Worse, it silently accepts a
    // trailing offset — provenance that contradicts the offset field beside it.
    final shape = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$')
        .firstMatch(wallClock);
    if (shape == null) return false;

    final year = int.parse(shape.group(1)!);
    final month = int.parse(shape.group(2)!);
    final day = int.parse(shape.group(3)!);
    final hour = int.parse(shape.group(4)!);
    final minute = int.parse(shape.group(5)!);
    final second = int.parse(shape.group(6)!);

    // The date must be REAL, not merely parseable. DateTime rolls 2026-02-30
    // forward to 2026-03-02, so without this a caller could store an impossible
    // day beside the instant it silently became — and the record would look
    // internally consistent while describing a date that never existed.
    final wall = DateTime.utc(year, month, day, hour, minute, second);
    if (wall.year != year ||
        wall.month != month ||
        wall.day != day ||
        wall.hour != hour ||
        wall.minute != minute ||
        wall.second != second) {
      return false;
    }

    return wall.subtract(Duration(minutes: offsetMinutes)) == dueAtUtc.toUtc();
  }

  /// The deterministic transcript key for one outbound.
  ///
  /// Writing the reminder under this key rather than a pushed ID is what makes
  /// desktop persistence idempotent: a retry after a crash rewrites the same
  /// record instead of adding a second visible turn.
  ///
  /// Contains no `/ . $ # [ ]`, which Firebase forbids in a path.
  static String transcriptKey(String outboundId) {
    final safe = outboundId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
    return 'commitment-$safe';
  }
}
