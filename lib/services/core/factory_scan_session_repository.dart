// Durable, run-scoped persistence for Factory Signal Scan sessions.
//
// This repository stores session JSON only. It cannot execute search, record a
// sponsor verdict, authorize Blueprint, or advance Factory.
library;

import '../../logic/factory_scan_session.dart';
import 'kai_db.dart';

abstract class FactoryScanDocumentStore {
  Future<Object?> read(String path);
  Future<bool> writeIfRevision(
    String path,
    Map<String, Object?> document, {
    required int expectedRevision,
  });
}

class KaiDbFactoryScanDocumentStore implements FactoryScanDocumentStore {
  const KaiDbFactoryScanDocumentStore();

  @override
  Future<Object?> read(String path) async =>
      (await KaiDb.instance.ref(path).get()).value;

  @override
  Future<bool> writeIfRevision(
    String path,
    Map<String, Object?> document, {
    required int expectedRevision,
  }) =>
      throw UnsupportedError(
        'KaiDb has no atomic compare-and-set surface; refusing a blind write',
      );
}

class FactoryScanSaveResult {
  final bool saved;
  final String reason;
  final String? path;
  final int? revision;

  const FactoryScanSaveResult({
    required this.saved,
    required this.reason,
    this.path,
    this.revision,
  });
}

class FactoryScanLoadResult {
  final FactoryScanSession? session;
  final String reason;
  final String? path;
  final int? revision;

  const FactoryScanLoadResult({
    required this.session,
    required this.reason,
    this.path,
    this.revision,
  });

  bool get loaded => session != null;
}

class FactoryScanSessionRepository {
  final FactoryScanDocumentStore _store;

  const FactoryScanSessionRepository({required FactoryScanDocumentStore store})
      : _store = store;

  static final RegExp _safeKey = RegExp(r'^[A-Za-z0-9_-]+$');

  static String pathFor({
    required String personaId,
    required String factoryRunId,
    required String scanSessionId,
  }) {
    final persona = _validatedKey('personaId', personaId);
    final run = _validatedKey('factoryRunId', factoryRunId);
    final session = _validatedKey('scanSessionId', scanSessionId);
    return 'kai/$persona/factory/scan_sessions/$run/$session';
  }

  static String _validatedKey(String label, String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || !_safeKey.hasMatch(normalized)) {
      throw ArgumentError.value(
        value,
        label,
        'must contain only letters, numbers, underscore, or hyphen',
      );
    }
    return normalized;
  }

  Future<FactoryScanSaveResult> save({
    required String personaId,
    required String factoryRunId,
    required FactoryScanSession session,
    required int expectedRevision,
  }) async {
    if (expectedRevision < 0) {
      return const FactoryScanSaveResult(
        saved: false,
        reason: 'expected revision cannot be negative',
      );
    }
    String path;
    try {
      path = pathFor(
        personaId: personaId,
        factoryRunId: factoryRunId,
        scanSessionId: session.id,
      );
    } on ArgumentError catch (error) {
      return FactoryScanSaveResult(
          saved: false, reason: error.message.toString());
    }

    try {
      final nextRevision = expectedRevision + 1;
      final sessionJson = Map<String, Object?>.from(session.toJson())
        ..remove('audit')
        ..remove('transparentTraitWeights');
      final document = <String, Object?>{
        'repositorySchemaVersion': 1,
        'personaId': personaId.trim(),
        'factoryRunId': factoryRunId.trim(),
        'scanSessionId': session.id,
        'revision': nextRevision,
        'session': sessionJson,
      };
      final written = await _store.writeIfRevision(
        path,
        document,
        expectedRevision: expectedRevision,
      );
      if (!written) {
        return FactoryScanSaveResult(
          saved: false,
          reason: 'stale scan session; reload and reapply the mutation',
          path: path,
        );
      }
      return FactoryScanSaveResult(
        saved: true,
        reason: 'scan session persisted',
        path: path,
        revision: nextRevision,
      );
    } catch (error) {
      return FactoryScanSaveResult(
        saved: false,
        reason: 'scan session persistence failed (${error.runtimeType})',
        path: path,
      );
    }
  }

  Future<FactoryScanLoadResult> load({
    required String personaId,
    required String factoryRunId,
    required String scanSessionId,
  }) async {
    String path;
    try {
      path = pathFor(
        personaId: personaId,
        factoryRunId: factoryRunId,
        scanSessionId: scanSessionId,
      );
    } on ArgumentError catch (error) {
      return FactoryScanLoadResult(
        session: null,
        reason: error.message.toString(),
      );
    }

    try {
      final raw = await _store.read(path);
      if (raw == null) {
        return FactoryScanLoadResult(
          session: null,
          reason: 'scan session not found',
          path: path,
        );
      }
      if (raw is! Map) {
        return FactoryScanLoadResult(
          session: null,
          reason: 'scan session document is not an object',
          path: path,
        );
      }
      final repositorySchema =
          (raw['repositorySchemaVersion'] as num?)?.toInt();
      if (repositorySchema != 1) {
        return FactoryScanLoadResult(
          session: null,
          reason: 'unbound or unsupported repository document refused',
          path: path,
        );
      }
      if (raw['personaId']?.toString() != personaId.trim() ||
          raw['factoryRunId']?.toString() != factoryRunId.trim() ||
          raw['scanSessionId']?.toString() != scanSessionId) {
        return FactoryScanLoadResult(
          session: null,
          reason: 'stored document identity does not match its run-scoped path',
          path: path,
        );
      }
      final revision = (raw['revision'] as num?)?.toInt() ?? -1;
      if (revision <= 0 || raw['session'] is! Map) {
        return FactoryScanLoadResult(
          session: null,
          reason: 'repository envelope is malformed',
          path: path,
        );
      }
      final session = FactoryScanSession.fromJson(raw['session'] as Map);
      if (session.id != scanSessionId) {
        return FactoryScanLoadResult(
          session: null,
          reason: 'stored session id does not match its run-scoped path',
          path: path,
        );
      }
      return FactoryScanLoadResult(
        session: session,
        reason: 'scan session loaded',
        path: path,
        revision: revision,
      );
    } on FormatException catch (error) {
      return FactoryScanLoadResult(
        session: null,
        reason: 'scan session schema refused: ${error.message}',
        path: path,
      );
    } catch (error) {
      return FactoryScanLoadResult(
        session: null,
        reason: 'scan session load failed (${error.runtimeType})',
        path: path,
      );
    }
  }
}
