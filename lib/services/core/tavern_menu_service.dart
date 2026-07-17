// TavernMenuService
//
// Reads the live menu from the kingdom-ac44f RTDB and formats it into a
// compact text block for Kai's system prompt.
//
// Results are cached for 30 minutes so every message doesn't hit Firebase.
// Falls back to the last good cache (or empty string) if the network fails.
//
// Usage:
//   final block = await TavernMenuService().getMenuBlock();

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'kai_db.dart' show kaiDbUsesRest;

class TavernMenuService {
  static final TavernMenuService _i = TavernMenuService._();
  factory TavernMenuService() => _i;
  TavernMenuService._();

  // ── kingdom-ac44f Firebase app config ─────────────────────────────────
  static const _tavernOptions = FirebaseOptions(
    apiKey:            'AIzaSyB5K8_jbh-95R78mz8mp2YunY7wHnIbxWk',
    appId:             '1:968566097636:android:f561d9a981d215d25a0ef1',
    messagingSenderId: '968566097636',
    projectId:         'kingdom-ac44f',
    databaseURL:       'https://kingdom-ac44f-default-rtdb.europe-west1.firebasedatabase.app',
    storageBucket:     'kingdom-ac44f.firebasestorage.app',
  );

  static const _appName = 'tavern';
  static const _ttl     = Duration(minutes: 30);

  String?   _cached;
  DateTime? _cachedAt;
  bool      _initialised = false;

  // ── Public API ─────────────────────────────────────────────────────────

  /// Returns a formatted menu + allergen block ready to inject into Kai's
  /// system prompt. Cached for 30 min; falls back to last cache on error.
  Future<String> getMenuBlock() async {
    // See TavernStatusService.getStatusBlock — the tavern is on a second
    // Firebase app reached via the firebase_database plugin, which does not
    // exist on Windows. This also spared a pointless Firebase.initializeApp
    // for an app whose every call was going to throw. (§4.5)
    if (kaiDbUsesRest) return '';

    if (_cached != null && _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _ttl) {
      return _cached!;
    }
    try {
      final db   = await _getDb();
      final snap = await db.ref('menu').get();
      if (!snap.exists || snap.value == null) return _cached ?? '';
      final raw = Map<String, dynamic>.from(snap.value as Map);
      _cached   = _format(raw);
      _cachedAt = DateTime.now();
      return _cached!;
    } catch (e) {
      print('TavernMenuService: fetch failed — $e');
      return _cached ?? '';
    }
  }

  /// Call this early (e.g. in main) to pre-warm the cache.
  Future<void> prime() async {
    try { await getMenuBlock(); } catch (_) {}
  }

  // ── Firebase init ──────────────────────────────────────────────────────

  Future<FirebaseDatabase> _getDb() async {
    if (!_initialised) {
      try {
        Firebase.app(_appName);
      } catch (_) {
        await Firebase.initializeApp(
          name:    _appName,
          options: _tavernOptions,
        );
      }
      _initialised = true;
    }
    return FirebaseDatabase.instanceFor(app: Firebase.app(_appName));
  }

  // ── Formatter ──────────────────────────────────────────────────────────

  static const _catOrder = [
    'To Share', 'Sandwiches', 'Hearty Meals', 'Flatbread', 'Bowls & Pies',
    'Big Salad Bowl', 'Sweet Tooth', 'Kids Meals', 'Everyday Drinks',
    'Signature Creations', 'Thematic Creations',
  ];

  String _format(Map<String, dynamic> menu) {
    // Group by category
    final Map<String, List<Map<String, dynamic>>> cats = {};
    for (final val in menu.values) {
      if (val == null) continue;
      final it  = Map<String, dynamic>.from(val as Map);
      final cat = (it['category'] as String?) ?? 'Other';
      cats.putIfAbsent(cat, () => []).add(it);
    }

    final buf = StringBuffer('''
━━ TAVERN MENU & ALLERGENS ━━
Prices in BHD (inclusive of tax). Answer food questions accurately from this list.
For serious allergies always add: "Check with the kitchen to be sure."

''');

    for (final cat in _catOrder) {
      final items = cats[cat];
      if (items == null || items.isEmpty) continue;

      // Sort by sortOrder
      items.sort((a, b) =>
          ((a['sortOrder'] as num?)?.toInt() ?? 0)
          .compareTo((b['sortOrder'] as num?)?.toInt() ?? 0));

      buf.writeln(cat.toUpperCase());

      for (final it in items) {
        // Skip unavailable items
        if (it['isAvailable'] == false) continue;

        final name      = (it['name'] as String?)      ?? '';
        final price     = it['price'];
        final allergens = _toStringList(it['allergens']);
        final kaiNotes  = (it['kaiNotes'] as String?)  ?? '';

        final flags = <String>[];
        if (it['isVegetarian'] == true) flags.add('veg');
        if (it['isVegan']      == true) flags.add('vegan');
        if (it['canBeVegan']   == true) flags.add('vegan-opt');
        if (it['isGlutenFree'] == true) flags.add('gf');

        final priceStr    = price != null ? '$price' : '?';
        final allergenStr = allergens.isNotEmpty ? allergens.join(', ') : 'no major allergens';
        final flagStr     = flags.isNotEmpty ? ' | ${flags.join(', ')}' : '';

        buf.writeln('• $name $priceStr — $allergenStr$flagStr');
        if (kaiNotes.isNotEmpty) buf.writeln('  ↳ $kaiNotes');
      }
      buf.writeln();
    }

    buf.write('━━━━━━━━━━━━━━━━━━━━━━━━━━');
    return buf.toString();
  }

  List<String> _toStringList(dynamic val) {
    if (val == null) return [];
    if (val is List) return val.map((e) => e.toString()).toList();
    if (val is Map)  return val.values.map((e) => e.toString()).toList();
    return [];
  }
}
