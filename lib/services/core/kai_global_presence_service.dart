import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kai_db.dart';

const String kKaiPresencePersona = 'truekai';
const Duration kKaiGlobalPresenceLease = Duration(seconds: 90);

enum KaiCoordinatorLeaseAction { none, expire, renew }

/// Decides whether this process may mutate Kai's one central heartbeat.
///
/// Visible bodies are observers even when they run on the owner desktop. This
/// default-deny decision prevents a desktop-body timer from racing the hidden
/// coordinator and briefly declaring Central Kai asleep.
KaiCoordinatorLeaseAction resolveKaiCoordinatorLeaseAction({
  required bool managesCoordinatorLease,
  required bool requestedAwake,
}) {
  if (!managesCoordinatorLease) return KaiCoordinatorLeaseAction.none;
  return requestedAwake
      ? KaiCoordinatorLeaseAction.renew
      : KaiCoordinatorLeaseAction.expire;
}

class KaiGlobalBody {
  const KaiGlobalBody({
    required this.bodyId,
    required this.deviceId,
    required this.surface,
    required this.leaseExpiresAt,
    this.sessionId = '',
    this.status = 'idle',
    this.foreground = false,
    this.gogglesOn = false,
    this.lastUserActivityAt,
  });

  final String bodyId;
  final String deviceId;
  final String surface;
  final DateTime leaseExpiresAt;
  final String sessionId;
  final String status;
  final bool foreground;
  final bool gogglesOn;
  final DateTime? lastUserActivityAt;
}

class KaiGlobalPresenceSnapshot {
  const KaiGlobalPresenceSnapshot({
    required this.connected,
    required this.coordinatorLeaseExpiresAt,
    required this.bodies,
    required this.observedAt,
  });

  const KaiGlobalPresenceSnapshot.connecting()
      : connected = false,
        coordinatorLeaseExpiresAt = null,
        bodies = const [],
        observedAt = null;

  final bool connected;
  final DateTime? coordinatorLeaseExpiresAt;
  final List<KaiGlobalBody> bodies;
  final DateTime? observedAt;

  bool get isAwake => connected && coordinatorLeaseExpiresAt != null;
  int get bodyCount => bodies.length;
}

/// Parses the central lease table and rejects expired or malformed bodies.
/// Kept pure so the meaning of "Kai is awake" can be regression-tested without
/// a Firebase emulator.
KaiGlobalPresenceSnapshot resolveKaiGlobalPresence({
  required Object? coordinatorValue,
  required Object? bodiesValue,
  required DateTime serverNow,
  required bool connected,
}) {
  final active = <KaiGlobalBody>[];
  DateTime? coordinatorLease;
  if (coordinatorValue is Map) {
    final coordinator = Map<Object?, Object?>.from(coordinatorValue);
    final expiresMs = coordinator['leaseExpiresAt'];
    if (expiresMs is num) {
      final expires = DateTime.fromMillisecondsSinceEpoch(
        expiresMs.toInt(),
        isUtc: true,
      );
      if (expires.isAfter(serverNow.toUtc())) coordinatorLease = expires;
    }
  }
  if (bodiesValue is Map) {
    for (final entry in bodiesValue.entries) {
      if (entry.value is! Map) continue;
      final body = Map<Object?, Object?>.from(entry.value as Map);
      final expiresMs = body['leaseExpiresAt'];
      final surface = body['surface']?.toString().trim() ?? '';
      if (expiresMs is! num || surface.isEmpty) continue;
      final expires = DateTime.fromMillisecondsSinceEpoch(
        expiresMs.toInt(),
        isUtc: true,
      );
      if (!expires.isAfter(serverNow.toUtc())) continue;
      active.add(KaiGlobalBody(
        bodyId: entry.key.toString(),
        deviceId: body['deviceId']?.toString().trim().isNotEmpty == true
            ? body['deviceId'].toString().trim()
            : entry.key.toString(),
        surface: surface,
        leaseExpiresAt: expires,
        sessionId: body['sessionId']?.toString() ?? '',
        status: body['status']?.toString() ?? 'idle',
        foreground: body['foreground'] == true,
        gogglesOn: body['gogglesOn'] == true,
        lastUserActivityAt: body['lastUserActivityAt'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (body['lastUserActivityAt'] as num).toInt(),
                isUtc: true,
              )
            : null,
      ));
    }
  }
  active.sort((a, b) => a.surface.compareTo(b.surface));
  return KaiGlobalPresenceSnapshot(
    connected: connected,
    coordinatorLeaseExpiresAt: coordinatorLease,
    bodies: List.unmodifiable(active),
    observedAt: serverNow.toUtc(),
  );
}

class KaiPairingException implements Exception {
  const KaiPairingException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Central, authenticated body registry for every Kai surface.
///
/// A body is awake only while an approved device renews a short Firebase lease.
/// Stale records never count. Firebase Auth owns device identity; pairing grants
/// one device permission to write exactly its own lease.
class KaiGlobalPresenceService {
  KaiGlobalPresenceService._();
  static final KaiGlobalPresenceService instance = KaiGlobalPresenceService._();

  final StreamController<KaiGlobalPresenceSnapshot> _snapshots =
      StreamController<KaiGlobalPresenceSnapshot>.broadcast();

  StreamSubscription<KaiEvent>? _bodiesSub;
  StreamSubscription<KaiEvent>? _coordinatorSub;
  StreamSubscription<DatabaseEvent>? _connectionSub;
  Timer? _heartbeatTimer;
  Timer? _expiryTimer;
  KaiRef? _bodyRef;
  Object? _rawBodies;
  Object? _rawCoordinator;
  bool _firebaseConnected = false;
  int _serverOffsetMs = 0;
  bool _started = false;
  String? _deviceId;
  String? _bodyId;
  String? _surface;
  String? _sessionId;
  String? _uid;
  bool _publishBodyLease = true;
  bool _managesCoordinatorLease = false;
  bool _foreground = true;
  bool _gogglesOn = false;
  String _status = 'idle';
  int? _lastUserActivityAt;
  bool _coordinatorRequestedAwake = false;
  KaiGlobalPresenceSnapshot _latest =
      const KaiGlobalPresenceSnapshot.connecting();

  Stream<KaiGlobalPresenceSnapshot> get snapshots => _snapshots.stream;
  KaiGlobalPresenceSnapshot get latest => _latest;
  String? get deviceId => _deviceId;
  String? get bodyId => _bodyId;
  String? get surface => _surface;

  Future<void> startBody({
    required String surface,
    required bool canBootstrapOwner,
    bool publishBodyLease = true,
    bool managesCoordinatorLease = false,
    String? sessionId,
    bool foreground = true,
    bool gogglesOn = false,
    String status = 'idle',
  }) async {
    if (_started) return;
    final user = FirebaseAuth.instance.currentUser;
    if (!kaiDbUsesRest && user == null) {
      throw const KaiPairingException('Firebase sign-in missing');
    }
    _started = true;
    _uid = kaiDbUsesRest ? await KaiDb.instance.stableRestUid() : user!.uid;
    _surface = surface;
    _deviceId = await _resolveDeviceId(surface);
    _bodyId = await _resolveBodyId(surface);
    _sessionId = sessionId ??
        '$surface-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    _publishBodyLease = publishBodyLease;
    _managesCoordinatorLease = managesCoordinatorLease;
    _foreground = foreground;
    _gogglesOn = gogglesOn;
    _status = status;

    if (kaiDbUsesRest) {
      // Desktop uses Homecoming's authenticated RTDB REST facade because the
      // native Windows database plugin implements neither get nor transactions.
      _firebaseConnected = true;
    } else {
      try {
        final offset =
            await FirebaseDatabase.instance.ref('.info/serverTimeOffset').get();
        _serverOffsetMs = (offset.value as num?)?.toInt() ?? 0;
      } catch (_) {}
      _connectionSub = FirebaseDatabase.instance
          .ref('.info/connected')
          .onValue
          .listen((event) {
        _firebaseConnected = event.snapshot.value == true;
        _emit();
        if (_firebaseConnected) {
          unawaited(_renewIfEnrolled());
          unawaited(_renewCoordinatorIfOwner());
        }
      }, onError: (_) {
        _firebaseConnected = false;
        _emit();
      });
    }

    _bodiesSub = KaiDb.instance
        .ref('kai_core/bodies/$kKaiPresencePersona')
        .onValue
        .listen((event) {
      _rawBodies = event.snapshot.value;
      _emit();
    }, onError: (_) {
      _firebaseConnected = false;
      _emit();
    });
    _coordinatorSub = KaiDb.instance
        .ref('kai_core/coordinator/$kKaiPresencePersona')
        .onValue
        .listen((event) {
      _rawCoordinator = event.snapshot.value;
      _emit();
    }, onError: (_) {
      _firebaseConnected = false;
      _emit();
    });

    if (canBootstrapOwner) await _bootstrapOwnerAndDesktop();
    await _renewIfEnrolled();
    await _renewCoordinatorIfOwner();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        unawaited(_renewIfEnrolled());
        unawaited(_renewCoordinatorIfOwner());
      },
    );
    _expiryTimer = Timer.periodic(const Duration(seconds: 5), (_) => _emit());
  }

  Future<bool> get isCurrentDeviceEnrolled async {
    final id = _deviceId;
    final uid = _uid;
    if (id == null || uid == null) return false;
    final snapshot = await KaiDb.instance
        .ref('kai_core/enrollments/$kKaiPresencePersona/$id')
        .get();
    if (snapshot.value is! Map) return false;
    final enrollment = Map<Object?, Object?>.from(snapshot.value as Map);
    return enrollment['ownerUid'] == uid && enrollment['surface'] == _surface;
  }

  Future<void> updateBodyState({
    bool? foreground,
    bool? gogglesOn,
    String? status,
    bool userActive = false,
  }) async {
    if (foreground != null) _foreground = foreground;
    if (gogglesOn != null) _gogglesOn = gogglesOn;
    if (status != null && status.trim().isNotEmpty) _status = status.trim();
    if (userActive) _lastUserActivityAt = _serverNow().millisecondsSinceEpoch;
    await _renewIfEnrolled();
  }

  /// Mirrors authenticated loopback embodiments into the global registry.
  ///
  /// Unity cannot talk to Firebase directly and should never receive those
  /// credentials. The owner coordinator therefore republishes only bounded
  /// presence metadata from Kai Core; leases disappear naturally if heartbeats
  /// stop. Chat text and world perception never enter this registry.
  Future<void> mirrorCoreBodies(Iterable<Map<String, dynamic>> records) async {
    if (!_started || !_firebaseConnected) return;
    final uid = _uid;
    if (uid == null) return;
    final owner =
        await KaiDb.instance.ref('kai_core/owner/$kKaiPresencePersona').get();
    if (owner.value != uid) return;
    final now = _serverNow();
    for (final record in records) {
      final surface = record['surface']?.toString().trim().toLowerCase() ?? '';
      if (surface != 'vr' && surface != 'ar') continue;
      final deviceId = record['deviceId']?.toString().trim() ?? '';
      if (deviceId.isEmpty) continue;
      final safeId = deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
      final bodyId = 'core-$surface-$safeId';
      final interaction = DateTime.tryParse(
        record['lastInteractionAt']?.toString() ?? '',
      );
      await KaiDb.instance
          .ref('kai_core/bodies/$kKaiPresencePersona/$bodyId')
          .set({
        'ownerUid': uid,
        'bodyId': bodyId,
        'deviceId': deviceId,
        'surface': surface,
        'sessionId': record['sessionId']?.toString() ?? '$surface-session',
        'status': record['status']?.toString() ?? 'idle',
        'foreground': record['foreground'] == true,
        'gogglesOn': record['gogglesOn'] == true,
        if (interaction != null)
          'lastUserActivityAt': interaction.toUtc().millisecondsSinceEpoch,
        'lastHeartbeatAt': ServerValue.timestamp,
        'leaseExpiresAt':
            now.add(kKaiGlobalPresenceLease).millisecondsSinceEpoch,
      });
    }
  }

  Future<String> createPairingCode() async {
    final uid = _uid;
    if (uid == null) throw const KaiPairingException('Presence not started');
    final owner =
        await KaiDb.instance.ref('kai_core/owner/$kKaiPresencePersona').get();
    if (owner.value != uid) {
      throw const KaiPairingException(
          'Only Kai’s owner device can pair bodies');
    }
    final code = _randomCode();
    final now = _serverNow();
    await KaiDb.instance
        .ref('kai_core/pairings/$kKaiPresencePersona/$code')
        .set({
      'creatorUid': uid,
      'createdAt': now.millisecondsSinceEpoch,
      'expiresAt': now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
    });
    return code;
  }

  /// Publishes the one lease that drives every visible heart.
  ///
  /// Only the enrolled owner desktop may write it, and it is renewed only after
  /// the local Kai Core sidecar has answered a real heartbeat.
  Future<void> setCoordinatorAwake(bool awake) async {
    _coordinatorRequestedAwake = awake;
    await _renewCoordinatorIfOwner();
  }

  Future<void> _renewCoordinatorIfOwner() async {
    if (!_started || !_firebaseConnected || _surface != 'desktop') return;
    final action = resolveKaiCoordinatorLeaseAction(
      managesCoordinatorLease: _managesCoordinatorLease,
      requestedAwake: _coordinatorRequestedAwake,
    );
    if (action == KaiCoordinatorLeaseAction.none) return;
    final uid = _uid;
    if (uid == null) return;
    final owner =
        await KaiDb.instance.ref('kai_core/owner/$kKaiPresencePersona').get();
    if (owner.value != uid) return;
    final ref = KaiDb.instance.ref('kai_core/coordinator/$kKaiPresencePersona');
    if (action == KaiCoordinatorLeaseAction.expire) {
      await ref.update({'leaseExpiresAt': ServerValue.timestamp});
      return;
    }
    final now = _serverNow();
    await ref.set({
      'ownerUid': uid,
      'role': 'central_core',
      'lastHeartbeatAt': ServerValue.timestamp,
      'leaseExpiresAt': now.add(kKaiGlobalPresenceLease).millisecondsSinceEpoch,
    });
    if (!kaiDbUsesRest) {
      try {
        // Schedule cleanup only after the complete record exists. Rules evaluate
        // onDisconnect when it is registered, so doing this before set() makes
        // the partial leaseExpiresAt-only write invalid on first enrollment.
        await FirebaseDatabase.instance
            .ref('kai_core/coordinator/$kKaiPresencePersona')
            .onDisconnect()
            .update({'leaseExpiresAt': ServerValue.timestamp});
      } catch (_) {
        // Lease expiry remains the source of truth; onDisconnect only shortens
        // the failover window when the native transport supports it.
      }
    }
  }

  Future<void> claimPairingCode(String rawCode) async {
    final code = rawCode.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final uid = _uid;
    final id = _deviceId;
    final activeSurface = _surface;
    if (code.length != 12 ||
        uid == null ||
        id == null ||
        activeSurface == null) {
      throw const KaiPairingException('That pairing code is not valid');
    }
    final pairing =
        KaiDb.instance.ref('kai_core/pairings/$kKaiPresencePersona/$code');
    try {
      await pairing.update({
        'claimedBy': uid,
        'claimedDeviceId': id,
        'claimedSurface': activeSurface,
        'claimedAt': ServerValue.timestamp,
      });
      await KaiDb.instance
          .ref('kai_core/enrollments/$kKaiPresencePersona/$id')
          .set({
        'ownerUid': uid,
        'surface': activeSurface,
        'pairingId': code,
        'approvedAt': ServerValue.timestamp,
      });
      await _renewIfEnrolled();
    } catch (_) {
      throw const KaiPairingException(
          'Code expired, was already used, or was wrong');
    }
  }

  Future<void> _bootstrapOwnerAndDesktop() async {
    final uid = _uid!;
    final id = _deviceId!;
    final ownerRef = KaiDb.instance.ref('kai_core/owner/$kKaiPresencePersona');
    // The Windows Firebase plugin does not implement runTransaction. Security
    // rules still make first-owner assignment atomic: after the first accepted
    // write, every different UID is rejected.
    final existing = await ownerRef.get();
    if (!existing.exists) {
      try {
        await ownerRef.set(uid);
      } catch (_) {
        // Another first writer may have won between get and set. Re-read below
        // and accept only an exact UID match.
      }
    }
    final owner = await ownerRef.get();
    if (owner.value != uid) return;
    await KaiDb.instance
        .ref('kai_core/enrollments/$kKaiPresencePersona/$id')
        .set({
      'ownerUid': uid,
      'surface': _surface,
      'pairingId': 'owner-bootstrap',
      'approvedAt': ServerValue.timestamp,
    });
  }

  Future<void> _renewIfEnrolled() async {
    if (!_publishBodyLease ||
        !_firebaseConnected ||
        !await isCurrentDeviceEnrolled) {
      return;
    }
    final now = _serverNow();
    final ref =
        KaiDb.instance.ref('kai_core/bodies/$kKaiPresencePersona/$_bodyId');
    _bodyRef = ref;
    await ref.set({
      'ownerUid': _uid,
      'bodyId': _bodyId,
      'deviceId': _deviceId,
      'surface': _surface,
      'sessionId': _sessionId,
      'status': _status,
      'foreground': _foreground,
      'gogglesOn': _gogglesOn,
      if (_lastUserActivityAt != null)
        'lastUserActivityAt': _lastUserActivityAt,
      'lastHeartbeatAt': ServerValue.timestamp,
      'leaseExpiresAt': now.add(kKaiGlobalPresenceLease).millisecondsSinceEpoch,
    });
    if (!kaiDbUsesRest) {
      try {
        await FirebaseDatabase.instance
            .ref('kai_core/bodies/$kKaiPresencePersona/$_bodyId')
            .onDisconnect()
            .update({'leaseExpiresAt': ServerValue.timestamp});
      } catch (_) {
        // A fresh lease still expires safely even if native disconnect cleanup
        // cannot be registered.
      }
    }
  }

  Future<String> _resolveDeviceId(String surface) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'kai_global_presence_device_id_$surface';
    final existing = prefs.getString(key)?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final suffix = List.generate(
      12,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    final id = '$surface-$suffix';
    await prefs.setString(key, id);
    return id;
  }

  Future<String> _resolveBodyId(String surface) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'kai_global_presence_body_id_$surface';
    final existing = prefs.getString(key)?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final suffix = List.generate(
      12,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    final id = '$surface-body-$suffix';
    await prefs.setString(key, id);
    return id;
  }

  DateTime _serverNow() =>
      DateTime.now().toUtc().add(Duration(milliseconds: _serverOffsetMs));

  void _emit() {
    _latest = resolveKaiGlobalPresence(
      coordinatorValue: _rawCoordinator,
      bodiesValue: _rawBodies,
      serverNow: _serverNow(),
      connected: _firebaseConnected,
    );
    _snapshots.add(_latest);
  }

  String _randomCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(
      12,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  Future<void> stop() async {
    _heartbeatTimer?.cancel();
    _expiryTimer?.cancel();
    await _bodiesSub?.cancel();
    await _coordinatorSub?.cancel();
    await _connectionSub?.cancel();
    final ref = _bodyRef;
    if (ref != null) {
      try {
        await ref.update({'leaseExpiresAt': ServerValue.timestamp});
        if (!kaiDbUsesRest) {
          await FirebaseDatabase.instance
              .ref('kai_core/bodies/$kKaiPresencePersona/$_bodyId')
              .onDisconnect()
              .cancel();
        }
      } catch (_) {}
    }
    if (_managesCoordinatorLease) {
      _coordinatorRequestedAwake = false;
      try {
        await _renewCoordinatorIfOwner();
      } catch (_) {}
    }
    _started = false;
  }
}
