// KaiDb — one database facade for Kai's brain across every presence.
//
// Problem: the firebase_database Flutter plugin has no Windows implementation,
// so on the desktop shell every RTDB call throws MissingPluginException. But
// Firebase's Realtime Database also speaks plain REST (…/<path>.json), which
// works everywhere.
//
// So: on desktop (Windows/Linux/macOS) KaiDb talks to RTDB over REST; on mobile
// and web it passes straight through to the firebase_database plugin, so nothing
// about existing mobile behaviour changes.
//
// The surface (ref/child/push/get/set/update/remove/onValue + orderBy/limit)
// mirrors the subset of the plugin the app actually uses, so services can swap
// `FirebaseDatabase.instance` → `KaiDb.instance` with no other change.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart' as fdb;
import 'package:http/http.dart' as http;

/// True when the firebase_database plugin is unavailable and we must use REST.
bool get kaiDbUsesRest =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

// ── Facade ──────────────────────────────────────────────────────────────────

class KaiDb {
  KaiDb._();
  static final KaiDb instance = KaiDb._();

  KaiRef ref(String path) => kaiDbUsesRest
      ? _RestRef(_normalize(path))
      : _PluginRef(fdb.FirebaseDatabase.instance.ref(path));

  /// No-op on desktop (REST has no local persistence); forwards on mobile.
  void setPersistenceEnabled(bool enabled) {
    if (!kaiDbUsesRest) {
      try {
        fdb.FirebaseDatabase.instance.setPersistenceEnabled(enabled);
      } catch (_) {}
    }
  }

  static String _normalize(String p) => p.replaceAll(RegExp(r'^/+|/+$'), '');
}

// ── Shared value types ──────────────────────────────────────────────────────

class KaiSnapshot {
  final Object? value;
  final String? key;
  KaiSnapshot(this.value, {this.key});

  bool get exists => value != null;

  /// Navigate to a nested child by key or slash-path (mirrors DataSnapshot.child).
  KaiSnapshot child(String path) {
    Object? cur = value;
    final segs = path.split('/').where((s) => s.isNotEmpty).toList();
    for (final seg in segs) {
      if (cur is Map) {
        cur = cur[seg];
      } else {
        cur = null;
        break;
      }
    }
    return KaiSnapshot(cur, key: segs.isEmpty ? key : segs.last);
  }

  Iterable<KaiSnapshot> get children {
    final v = value;
    if (v is Map) {
      return v.entries
          .map((e) => KaiSnapshot(e.value, key: e.key.toString()));
    }
    if (v is List) {
      final out = <KaiSnapshot>[];
      for (var i = 0; i < v.length; i++) {
        if (v[i] != null) out.add(KaiSnapshot(v[i], key: '$i'));
      }
      return out;
    }
    return const <KaiSnapshot>[];
  }
}

class KaiEvent {
  final KaiSnapshot snapshot;
  KaiEvent(this.snapshot);
}

// ── Query interface (read side) ─────────────────────────────────────────────

abstract class KaiQuery {
  KaiQuery orderByChild(String key);
  KaiQuery orderByKey();
  KaiQuery limitToLast(int n);
  KaiQuery limitToFirst(int n);
  KaiQuery equalTo(Object? value, {String? key});
  Future<KaiSnapshot> get();
  Stream<KaiEvent> get onValue;
}

/// Reference (read + write side).
abstract class KaiRef extends KaiQuery {
  KaiRef child(String path);
  KaiRef push();
  String? get key;
  Future<void> set(Object? value);
  Future<void> update(Map<String, Object?> value);
  Future<void> remove();
}

// ── Plugin-backed (mobile / web) ────────────────────────────────────────────

class _PluginQuery implements KaiQuery {
  final fdb.Query _q;
  _PluginQuery(this._q);

  @override
  KaiQuery orderByChild(String key) => _PluginQuery(_q.orderByChild(key));
  @override
  KaiQuery orderByKey() => _PluginQuery(_q.orderByKey());
  @override
  KaiQuery limitToLast(int n) => _PluginQuery(_q.limitToLast(n));
  @override
  KaiQuery limitToFirst(int n) => _PluginQuery(_q.limitToFirst(n));
  @override
  KaiQuery equalTo(Object? value, {String? key}) =>
      _PluginQuery(_q.equalTo(value, key: key));

  @override
  Future<KaiSnapshot> get() async {
    final s = await _q.get();
    return KaiSnapshot(s.value, key: s.key);
  }

  @override
  Stream<KaiEvent> get onValue =>
      _q.onValue.map((e) => KaiEvent(KaiSnapshot(e.snapshot.value, key: e.snapshot.key)));
}

class _PluginRef extends _PluginQuery implements KaiRef {
  final fdb.DatabaseReference _ref;
  _PluginRef(this._ref) : super(_ref);

  @override
  KaiRef child(String path) => _PluginRef(_ref.child(path));
  @override
  KaiRef push() => _PluginRef(_ref.push());
  @override
  String? get key => _ref.key;
  @override
  Future<void> set(Object? value) => _ref.set(value);
  @override
  Future<void> update(Map<String, Object?> value) => _ref.update(value);
  @override
  Future<void> remove() => _ref.remove();
}

// ── REST-backed (desktop) ───────────────────────────────────────────────────

class _RestRef implements KaiRef {
  final String _path; // no leading/trailing slash
  final Map<String, String> _params; // query params (orderBy/limit)
  _RestRef(this._path, [this._params = const {}]);

  static String? _baseCache;
  static String get _base {
    _baseCache ??= () {
      try {
        final url = Firebase.app().options.databaseURL;
        if (url != null && url.isNotEmpty) return url.replaceAll(RegExp(r'/+$'), '');
      } catch (_) {}
      // Fallback to Homecoming's RTDB.
      return 'https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app';
    }();
    return _baseCache!;
  }

  Future<Uri> _uri() async {
    final params = <String, String>{..._params};
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final t = await user.getIdToken();
        if (t != null && t.isNotEmpty) params['auth'] = t;
      } catch (_) {}
    }
    if (!params.containsKey('orderBy') &&
        (params.containsKey('limitToLast') ||
            params.containsKey('limitToFirst') ||
            params.containsKey('equalTo') ||
            params.containsKey('startAt') ||
            params.containsKey('endAt'))) {
      params['orderBy'] = '"\$key"';
    }
    return Uri.parse('$_base/$_path.json').replace(
        queryParameters: params.isEmpty ? null : params);
  }

  _RestRef _withParam(String k, String v) =>
      _RestRef(_path, {..._params, k: v});

  @override
  KaiRef child(String path) =>
      _RestRef('$_path/${KaiDb._normalize(path)}', _params);

  @override
  KaiRef push() => _RestRef('$_path/${_pushId()}', _params);

  @override
  String? get key {
    final i = _path.lastIndexOf('/');
    return i < 0 ? _path : _path.substring(i + 1);
  }

  @override
  KaiQuery orderByChild(String k) => _withParam('orderBy', jsonEncode(k));
  @override
  KaiQuery orderByKey() => _withParam('orderBy', '"\$key"');
  @override
  KaiQuery limitToLast(int n) => _withParam('limitToLast', '$n');
  @override
  KaiQuery limitToFirst(int n) => _withParam('limitToFirst', '$n');
  @override
  KaiQuery equalTo(Object? value, {String? key}) =>
      _withParam('equalTo', jsonEncode(value));

  @override
  Future<KaiSnapshot> get() async {
    final res = await http.get(await _uri());
    if (res.statusCode >= 400) {
      throw Exception('KaiDb GET $_path failed: ${res.statusCode} ${res.body}');
    }
    final decoded = (res.body.isEmpty || res.body == 'null')
        ? null
        : jsonDecode(res.body);
    return KaiSnapshot(decoded, key: key);
  }

  @override
  Future<void> set(Object? value) async {
    final res = await http.put(await _uri(), body: jsonEncode(value));
    if (res.statusCode >= 400) {
      throw Exception('KaiDb SET $_path failed: ${res.statusCode} ${res.body}');
    }
  }

  @override
  Future<void> update(Map<String, Object?> value) async {
    final res = await http.patch(await _uri(), body: jsonEncode(value));
    if (res.statusCode >= 400) {
      throw Exception('KaiDb UPDATE $_path failed: ${res.statusCode} ${res.body}');
    }
  }

  @override
  Future<void> remove() async {
    final res = await http.delete(await _uri());
    if (res.statusCode >= 400) {
      throw Exception('KaiDb REMOVE $_path failed: ${res.statusCode} ${res.body}');
    }
  }

  @override
  Stream<KaiEvent> get onValue {
    // No SSE on desktop — poll and emit on change. Fine for Kai's cadence.
    late StreamController<KaiEvent> ctrl;
    Timer? timer;
    String? last;

    Future<void> tick() async {
      try {
        final snap = await get();
        final enc = jsonEncode(snap.value);
        if (enc != last) {
          last = enc;
          if (!ctrl.isClosed) ctrl.add(KaiEvent(snap));
        }
      } catch (_) {/* keep polling */}
    }

    ctrl = StreamController<KaiEvent>(
      onListen: () {
        tick();
        timer = Timer.periodic(const Duration(seconds: 4), (_) => tick());
      },
      onCancel: () {
        timer?.cancel();
      },
    );
    return ctrl.stream;
  }

  // Firebase push-id algorithm (time-ordered, 20 chars).
  static const _pushChars =
      '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';
  static final _rand = Random();
  static int _lastPushTime = 0;
  static final List<int> _lastRandChars = List<int>.filled(12, 0);

  static String _pushId() {
    var now = DateTime.now().millisecondsSinceEpoch;
    final dup = now == _lastPushTime;
    _lastPushTime = now;

    final timeChars = List<String>.filled(8, '');
    for (var i = 7; i >= 0; i--) {
      timeChars[i] = _pushChars[now % 64];
      now = now ~/ 64;
    }
    final buf = StringBuffer(timeChars.join());

    if (!dup) {
      for (var i = 0; i < 12; i++) {
        _lastRandChars[i] = _rand.nextInt(64);
      }
    } else {
      var i = 11;
      for (; i >= 0 && _lastRandChars[i] == 63; i--) {
        _lastRandChars[i] = 0;
      }
      if (i >= 0) _lastRandChars[i]++;
    }
    for (var i = 0; i < 12; i++) {
      buf.write(_pushChars[_lastRandChars[i]]);
    }
    return buf.toString();
  }
}
