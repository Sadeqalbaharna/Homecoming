// TavernStatusService
//
// Reads live table occupancy and active guest list from kingdom-ac44f RTDB.
// The Pi writes here on every NFC tap; no Firestore dependency.
//
// Cached for 5 minutes (shorter than the menu TTL — this data changes faster).
// Falls back to last good cache on network failure.
//
// Usage:
//   final block = await TavernStatusService().getStatusBlock();

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

class TavernStatusService {
  static final TavernStatusService _i = TavernStatusService._();
  factory TavernStatusService() => _i;
  TavernStatusService._();

  static const _appName = 'tavern'; // shared with TavernMenuService
  static const _ttl     = Duration(minutes: 5);

  String?   _cached;
  DateTime? _cachedAt;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns a live tavern status block ready to inject into Kai's system prompt.
  /// Covers: who is currently at each table, VIPs, visit counts, usual orders.
  Future<String> getStatusBlock() async {
    if (_cached != null && _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _ttl) {
      return _cached!;
    }
    try {
      final db = _getDb();
      final results = await Future.wait([
        db.ref('tables').get(),
        db.ref('active_guests').get(),
      ]);

      final tablesSnap = results[0];
      final guestsSnap = results[1];

      final tables = (tablesSnap.exists && tablesSnap.value != null)
          ? Map<String, dynamic>.from(tablesSnap.value as Map)
          : <String, dynamic>{};

      final guests = (guestsSnap.exists && guestsSnap.value != null)
          ? Map<String, dynamic>.from(guestsSnap.value as Map)
          : <String, dynamic>{};

      _cached   = _format(tables, guests);
      _cachedAt = DateTime.now();
      return _cached!;
    } catch (e) {
      print('TavernStatusService: fetch failed — $e');
      return _cached ?? '';
    }
  }

  /// Force-refresh ignoring cache (call after an NFC tap notification).
  Future<String> refresh() async {
    _cachedAt = null;
    return getStatusBlock();
  }

  // ── Firebase ───────────────────────────────────────────────────────────────

  FirebaseDatabase _getDb() {
    // 'tavern' app is initialized by TavernMenuService.prime() at startup.
    // If somehow not yet initialized, fall through to the lazy init there.
    try {
      return FirebaseDatabase.instanceFor(app: Firebase.app(_appName));
    } catch (_) {
      rethrow;
    }
  }

  // ── Formatter ──────────────────────────────────────────────────────────────

  String _format(
    Map<String, dynamic> tables,
    Map<String, dynamic> guests,
  ) {
    if (tables.isEmpty && guests.isEmpty) {
      return '\n━━ TAVERN STATUS ━━\nNo guests currently checked in.\n━━━━━━━━━━━━━━━━━━━━━━━━━━\n';
    }

    final buf = StringBuffer('\n━━ TAVERN STATUS ━━\n');
    buf.writeln('Live table occupancy as of ${_timeAgo(null)}. '
        'Use this to answer questions like "who is here?" or "what\'s happening at the tavern?"\n');

    // ── Tables ───────────────────────────────────────────────────────────────
    if (tables.isNotEmpty) {
      // Sort by arrivedAt descending (most recent first)
      final sorted = tables.entries.toList()
        ..sort((a, b) {
          final at = (Map<String, dynamic>.from(a.value as Map))['arrivedAt'] as int? ?? 0;
          final bt = (Map<String, dynamic>.from(b.value as Map))['arrivedAt'] as int? ?? 0;
          return bt.compareTo(at);
        });

      buf.writeln('TABLES');
      for (final e in sorted) {
        final t         = Map<String, dynamic>.from(e.value as Map);
        final tableId   = e.key;
        final tableName = (t['tableName']  as String?) ?? tableId;
        final guestName = (t['guestName']  as String?) ?? 'Unknown';
        final visits    = (t['visitCount'] as int?)    ?? 1;
        final isVIP     = t['isVIP']        == true;
        final usual     = (t['usualOrder']  as String?) ?? '';
        final arrivedAt = t['arrivedAt']    as int?;

        final vip    = isVIP    ? ' ⭐ VIP' : '';
        final since  = arrivedAt != null ? ' (arrived ${_timeAgo(arrivedAt)})' : '';
        final usualStr = usual.isNotEmpty ? ', usual: $usual' : '';

        buf.writeln('• $tableName — $guestName$vip | visit #$visits$usualStr$since');
      }
      buf.writeln();
    }

    // ── Active guests summary ─────────────────────────────────────────────────
    if (guests.isNotEmpty) {
      final guestList = guests.values
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList()
        ..sort((a, b) {
          final at = (a['arrivedAt'] as int?) ?? 0;
          final bt = (b['arrivedAt'] as int?) ?? 0;
          return bt.compareTo(at);
        });

      // VIPs first
      final vips     = guestList.where((g) => g['isVIP'] == true).toList();
      final regulars = guestList.where((g) => g['isVIP'] != true).toList();

      if (vips.isNotEmpty) {
        buf.writeln('VIPs IN HOUSE');
        for (final g in vips) {
          final name  = (g['name']      as String?) ?? 'Guest';
          final table = (g['tableName'] as String?) ?? '';
          final notes = (g['notes']     as String?) ?? '';
          buf.write('• $name at $table');
          if (notes.isNotEmpty) buf.write(' — $notes');
          buf.writeln();
        }
        buf.writeln();
      }

      buf.writeln('TOTAL GUESTS IN HOUSE: ${guests.length}');
      if (regulars.isNotEmpty) {
        buf.writeln('Others: ${regulars.map((g) => (g['name'] as String?) ?? 'Guest').join(', ')}');
      }
    }

    buf.write('━━━━━━━━━━━━━━━━━━━━━━━━━━');
    return buf.toString();
  }

  String _timeAgo(int? epochMs) {
    if (epochMs == null) {
      final now = DateTime.now();
      return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    }
    final arrived = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final diff    = DateTime.now().difference(arrived);
    if (diff.inMinutes < 1)  return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
