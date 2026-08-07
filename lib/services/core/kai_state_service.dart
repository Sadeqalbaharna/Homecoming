// KaiStateService
// Single source of truth for Kai's inner state across all surfaces.
//
// Firebase RTDB is canonical. Offline reads/writes are handled automatically
// by Firebase's built-in persistence (setPersistenceEnabled(true)).
// SharedPreferences is no longer used for state — it was redundant.
//
// Firebase structure:
//   /kai/{personaId}/state/mood/        — current mood traits
//   /kai/{personaId}/state/affinity/    — current affinity
//   /kai/{personaId}/state/personality/ — personality traits
//   /kai/{personaId}/state/meta/        — lastUpdated, surface

library;

import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'kai_db.dart';
import 'firebase_service.dart';

const _moodKeys = {
  'valence',
  'energy',
  'warmth',
  'confidence',
  'playfulness',
  'focus'
};
const _affinityKeys = {'intimacy', 'physicality'};
const _personalityKeys = {'extraversion', 'intuition', 'feeling', 'perceiving'};

class KaiStateService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final KaiStateService _instance = KaiStateService._internal();
  factory KaiStateService() => _instance;
  KaiStateService._internal();

  String _surface = 'unknown';

  void setSurface(String surface) {
    _surface = surface;
    print('🌐 [KaiState] Surface: $surface');
  }

  // ── Firebase path helpers ──────────────────────────────────────────────────

  static String _moodPath(String p) => 'kai/$p/state/mood';
  static String _affinityPath(String p) => 'kai/$p/state/affinity';
  static String _personalityPath(String p) => 'kai/$p/state/personality';
  static String _metaPath(String p) => 'kai/$p/state/meta';

  static KaiDb? get _db => FirebaseService.isAvailable ? KaiDb.instance : null;

  // ── Concurrent bodies and the lost update ──────────────────────────────────
  //
  // saveMood/saveAffinity/savePersonality write the WHOLE map. That is correct
  // while exactly one turn can be in flight, and silently wrong the moment two
  // bodies can talk to Kai at once:
  //
  //   Messenger reads {valence: 50, energy: 50}
  //   desktop   reads {valence: 50, energy: 50}
  //   Messenger writes {60, 50}      (+10 valence — he was cheered up)
  //   desktop   writes {50, 60}      (+10 energy  — and it lands last)
  //
  // The cheering up is gone. No error, no log, nothing to trace. Six weeks
  // later his mood "feels flat" and there is no way to find out why.
  //
  // The deltas already exist — ai_service computes actualMoodDeltas and then
  // discards them by writing the absolute map. So apply the delta instead, as a
  // server-side increment per key. Both writes land, in either order.
  //
  // `{'.sv': {'increment': n}}` is RTDB's own sentinel and is exactly what the
  // plugin's ServerValue.increment produces, so it works unchanged through both
  // halves of the KaiDb facade — plugin on mobile, raw JSON over REST on
  // desktop.
  //
  // Bounds: a server increment cannot clamp, so a long run in one direction
  // could drift a stored value past its range and then sit there while several
  // turns of the opposite sign do nothing visible. Reads clamp, and a read that
  // finds a value out of range writes the clamped value back — rare, cheap, and
  // it keeps the store honest rather than only the display.

  static const _moodBounds = (min: 0, max: 100);
  static const _affinityBounds = (min: 0, max: 100);
  static const _personalityBounds = (min: 0, max: 1000);

  static Map<String, Object?> _incrementPayload(
    Map<String, int> deltas,
    Set<String> allowedKeys,
  ) {
    final payload = <String, Object?>{};
    deltas.forEach((key, delta) {
      if (delta == 0 || !allowedKeys.contains(key)) return;
      payload[key] = {
        '.sv': {'increment': delta}
      };
    });
    return payload;
  }

  Future<void> _applyDeltas(
    String path,
    Map<String, int> deltas,
    Set<String> allowedKeys,
  ) async {
    if (_db == null) return;
    final payload = _incrementPayload(deltas, allowedKeys);
    if (payload.isEmpty) return;
    try {
      await _db!.ref(path).update(payload);
    } catch (e) {
      print('⚠️ [KaiState] Delta write failed for $path: $e');
    }
  }

  /// Apply mood movement without clobbering another body's turn.
  Future<void> applyMoodDeltas(String personaId, Map<String, int> deltas) =>
      _applyDeltas(_moodPath(personaId), deltas, _moodKeys);

  Future<void> applyAffinityDeltas(String personaId, Map<String, int> deltas) =>
      _applyDeltas(_affinityPath(personaId), deltas, _affinityKeys);

  Future<void> applyPersonalityDeltas(
          String personaId, Map<String, int> deltas) =>
      _applyDeltas(_personalityPath(personaId), deltas, _personalityKeys);

  /// Clamp a stored map into range, and report whether anything was out.
  static ({Map<String, int> values, bool healed}) clampState(
    Map<String, int> raw, {
    required int min,
    required int max,
  }) {
    var healed = false;
    final out = <String, int>{};
    raw.forEach((key, value) {
      final clamped = value < min ? min : (value > max ? max : value);
      if (clamped != value) healed = true;
      out[key] = clamped;
    });
    return (values: out, healed: healed);
  }

  // ── Mood ───────────────────────────────────────────────────────────────────

  Stream<Map<String, int>> moodStream(String personaId) {
    if (_db == null) return const Stream.empty();
    return _db!.ref(_moodPath(personaId)).onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return {};
      final raw = _parseIntMap(event.snapshot.value as Map, _moodKeys);
      final clamped = clampState(
        raw,
        min: _moodBounds.min,
        max: _moodBounds.max,
      );
      if (clamped.healed) {
        unawaited(_db!.ref(_moodPath(personaId)).update(clamped.values));
      }
      return clamped.values;
    });
  }

  Future<Map<String, int>?> getMood(String personaId) async {
    if (_db == null) return null;
    try {
      final snap = await _db!.ref(_moodPath(personaId)).get();
      if (snap.exists && snap.value != null) {
        final result = _parseIntMap(snap.value as Map, _moodKeys);
        if (result.isNotEmpty) {
          final clamped =
              clampState(result, min: _moodBounds.min, max: _moodBounds.max);
          // Self-heal: increments cannot clamp, so a long run in one direction
          // can drift past the range. Write the bounded value back rather than
          // only showing it bounded, or the next several opposite turns do
          // nothing visible.
          if (clamped.healed) {
            unawaited(_db!.ref(_moodPath(personaId)).update(clamped.values));
          }
          return clamped.values;
        }
      }
    } catch (e) {
      print('⚠️ [KaiState] Mood read failed: $e');
    }
    return null;
  }

  Future<void> saveMood(String personaId, Map<String, int> mood) async {
    if (_db == null) return;
    try {
      await _db!.ref(_moodPath(personaId)).set(mood);
      await _writeMeta(personaId);
    } catch (e) {
      print('⚠️ [KaiState] Mood write failed: $e');
    }
  }

  // ── Affinity ───────────────────────────────────────────────────────────────

  Stream<Map<String, int>> affinityStream(String personaId) {
    if (_db == null) return const Stream.empty();
    return _db!.ref(_affinityPath(personaId)).onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return {};
      final raw = _parseIntMap(event.snapshot.value as Map, _affinityKeys);
      final clamped = clampState(
        raw,
        min: _affinityBounds.min,
        max: _affinityBounds.max,
      );
      if (clamped.healed) {
        unawaited(_db!.ref(_affinityPath(personaId)).update(clamped.values));
      }
      return clamped.values;
    });
  }

  Future<Map<String, int>?> getAffinity(String personaId) async {
    if (_db == null) return null;
    try {
      final snap = await _db!.ref(_affinityPath(personaId)).get();
      if (snap.exists && snap.value != null) {
        final result = _parseIntMap(snap.value as Map, _affinityKeys);
        if (result.isNotEmpty) {
          final clamped = clampState(
            result,
            min: _affinityBounds.min,
            max: _affinityBounds.max,
          );
          if (clamped.healed) {
            unawaited(
              _db!.ref(_affinityPath(personaId)).update(clamped.values),
            );
          }
          return clamped.values;
        }
      }
    } catch (e) {
      print('⚠️ [KaiState] Affinity read failed: $e');
    }
    return null;
  }

  Future<void> saveAffinity(String personaId, Map<String, int> affinity) async {
    if (_db == null) return;
    try {
      await _db!.ref(_affinityPath(personaId)).set(affinity);
      await _writeMeta(personaId);
    } catch (e) {
      print('⚠️ [KaiState] Affinity write failed: $e');
    }
  }

  // ── Personality ────────────────────────────────────────────────────────────

  Stream<Map<String, int>> personalityStream(String personaId) {
    if (_db == null) return const Stream.empty();
    return _db!.ref(_personalityPath(personaId)).onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return {};
      final raw = _parseIntMap(event.snapshot.value as Map, _personalityKeys);
      final clamped = clampState(
        raw,
        min: _personalityBounds.min,
        max: _personalityBounds.max,
      );
      if (clamped.healed) {
        unawaited(
          _db!.ref(_personalityPath(personaId)).update(clamped.values),
        );
      }
      return clamped.values;
    });
  }

  Future<Map<String, int>?> getPersonality(String personaId) async {
    if (_db == null) return null;
    try {
      final snap = await _db!.ref(_personalityPath(personaId)).get();
      if (snap.exists && snap.value != null) {
        final result = _parseIntMap(snap.value as Map, _personalityKeys);
        if (result.isNotEmpty) {
          final clamped = clampState(
            result,
            min: _personalityBounds.min,
            max: _personalityBounds.max,
          );
          if (clamped.healed) {
            unawaited(
              _db!.ref(_personalityPath(personaId)).update(clamped.values),
            );
          }
          return clamped.values;
        }
      }
    } catch (e) {
      print('⚠️ [KaiState] Personality read failed: $e');
    }
    return null;
  }

  Future<void> savePersonality(
      String personaId, Map<String, int> personality) async {
    if (_db == null) return;
    try {
      await _db!.ref(_personalityPath(personaId)).set(personality);
    } catch (e) {
      print('⚠️ [KaiState] Personality write failed: $e');
    }
  }

  // ── Last update time ───────────────────────────────────────────────────────

  Future<DateTime?> getLastUpdateTime(String personaId) async {
    if (_db == null) return null;
    try {
      final snap = await _db!.ref('${_metaPath(personaId)}/lastUpdated').get();
      if (snap.exists && snap.value != null) {
        return DateTime.fromMillisecondsSinceEpoch((snap.value as num).toInt());
      }
    } catch (e) {
      // non-fatal
    }
    return null;
  }

  Future<void> saveLastUpdateTime(String personaId, DateTime time) async {
    if (_db == null) return;
    try {
      await _db!
          .ref('${_metaPath(personaId)}/lastUpdated')
          .set(time.millisecondsSinceEpoch);
    } catch (e) {
      // non-fatal
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Map<String, int> _parseIntMap(Map raw, Set<String> allowedKeys) {
    final result = <String, int>{};
    for (final entry in raw.entries) {
      if (allowedKeys.contains(entry.key) && entry.value != null) {
        result[entry.key as String] = (entry.value as num).toInt();
      }
    }
    return result;
  }

  Future<void> _writeMeta(String personaId) async {
    try {
      await _db!.ref(_metaPath(personaId)).update({
        'lastUpdated': ServerValue.timestamp,
        'surface': _surface,
      });
    } catch (_) {
      // metadata is best-effort
    }
  }
}
