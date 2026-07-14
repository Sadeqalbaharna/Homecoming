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
import 'firebase_service.dart';

const _moodKeys        = {'valence', 'energy', 'warmth', 'confidence', 'playfulness', 'focus'};
const _affinityKeys    = {'intimacy', 'physicality'};
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

  static String _moodPath(String p)        => 'kai/$p/state/mood';
  static String _affinityPath(String p)    => 'kai/$p/state/affinity';
  static String _personalityPath(String p) => 'kai/$p/state/personality';
  static String _metaPath(String p)        => 'kai/$p/state/meta';

  static FirebaseDatabase? get _db =>
      FirebaseService.isAvailable ? FirebaseDatabase.instance : null;

  // ── Mood ───────────────────────────────────────────────────────────────────

  Stream<Map<String, int>> moodStream(String personaId) {
    if (_db == null) return const Stream.empty();
    return _db!.ref(_moodPath(personaId)).onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return {};
      return _parseIntMap(event.snapshot.value as Map, _moodKeys);
    });
  }

  Future<Map<String, int>?> getMood(String personaId) async {
    if (_db == null) return null;
    try {
      final snap = await _db!.ref(_moodPath(personaId)).get();
      if (snap.exists && snap.value != null) {
        final result = _parseIntMap(snap.value as Map, _moodKeys);
        if (result.isNotEmpty) return result;
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
      return _parseIntMap(event.snapshot.value as Map, _affinityKeys);
    });
  }

  Future<Map<String, int>?> getAffinity(String personaId) async {
    if (_db == null) return null;
    try {
      final snap = await _db!.ref(_affinityPath(personaId)).get();
      if (snap.exists && snap.value != null) {
        final result = _parseIntMap(snap.value as Map, _affinityKeys);
        if (result.isNotEmpty) return result;
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
      return _parseIntMap(event.snapshot.value as Map, _personalityKeys);
    });
  }

  Future<Map<String, int>?> getPersonality(String personaId) async {
    if (_db == null) return null;
    try {
      final snap = await _db!.ref(_personalityPath(personaId)).get();
      if (snap.exists && snap.value != null) {
        final result = _parseIntMap(snap.value as Map, _personalityKeys);
        if (result.isNotEmpty) return result;
      }
    } catch (e) {
      print('⚠️ [KaiState] Personality read failed: $e');
    }
    return null;
  }

  Future<void> savePersonality(String personaId, Map<String, int> personality) async {
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
      await _db!.ref('${_metaPath(personaId)}/lastUpdated')
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
