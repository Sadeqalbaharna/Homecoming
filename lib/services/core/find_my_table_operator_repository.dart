/// Run-scoped persistence for the synthetic Find My Table internal operator.
///
/// The repository stores evidence only. It has no network, invitation, payment,
/// public-action, or authority-minting capability.
library;

import '../../logic/find_my_table_operator.dart';
import 'kai_db.dart';

abstract class FindMyTableDocumentStore {
  Future<Object?> read(String path);

  Future<bool> writeIfRevision(
    String path,
    Map<String, Object?> document, {
    required int expectedRevision,
  });
}

class KaiDbFindMyTableDocumentStore implements FindMyTableDocumentStore {
  const KaiDbFindMyTableDocumentStore();

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

class FindMyTableSaveResult {
  final bool saved;
  final String reason;
  final String? path;
  final int? revision;

  const FindMyTableSaveResult({
    required this.saved,
    required this.reason,
    this.path,
    this.revision,
  });
}

class FindMyTableLoadResult {
  final FindMyTableOperator? operator;
  final String reason;
  final String? path;
  final int? revision;

  const FindMyTableLoadResult({
    required this.operator,
    required this.reason,
    this.path,
    this.revision,
  });

  bool get loaded => operator != null;
}

class FindMyTableOperatorRepository {
  final FindMyTableDocumentStore _store;

  const FindMyTableOperatorRepository({
    required FindMyTableDocumentStore store,
  }) : _store = store;

  static final RegExp _safeKey = RegExp(r'^[A-Za-z0-9_-]+$');

  static String pathFor({
    required String personaId,
    required String factoryRunId,
    required String candidateId,
  }) {
    final persona = _validatedKey('personaId', personaId);
    final run = _validatedKey('factoryRunId', factoryRunId);
    final candidate = _validatedKey('candidateId', candidateId);
    return 'kai/$persona/factory/find_my_table/$run/$candidate';
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

  Future<FindMyTableSaveResult> save({
    required String personaId,
    required String factoryRunId,
    required String candidateId,
    required FindMyTableOperator operator,
    required int expectedRevision,
  }) async {
    if (expectedRevision < 0) {
      return const FindMyTableSaveResult(
        saved: false,
        reason: 'expected revision cannot be negative',
      );
    }
    if (operator.factoryRunId != factoryRunId.trim() ||
        operator.candidateId != candidateId.trim()) {
      return const FindMyTableSaveResult(
        saved: false,
        reason: 'operator belongs to another Factory run or candidate',
      );
    }
    String path;
    try {
      path = pathFor(
        personaId: personaId,
        factoryRunId: factoryRunId,
        candidateId: candidateId,
      );
    } on ArgumentError catch (error) {
      return FindMyTableSaveResult(
        saved: false,
        reason: error.message.toString(),
      );
    }

    try {
      final nextRevision = expectedRevision + 1;
      final snapshot = operator.toJson();
      final document = <String, Object?>{
        'repositorySchemaVersion': 1,
        'personaId': personaId.trim(),
        'packetId': operator.packetId,
        'factoryRunId': factoryRunId.trim(),
        'scanSessionId': operator.scanSessionId,
        'candidateId': candidateId.trim(),
        'revision': nextRevision,
        'operator': snapshot,
      };
      final written = await _store.writeIfRevision(
        path,
        document,
        expectedRevision: expectedRevision,
      );
      if (!written) {
        return FindMyTableSaveResult(
          saved: false,
          reason: 'stale operator snapshot; reload and reapply the mutation',
          path: path,
        );
      }
      return FindMyTableSaveResult(
        saved: true,
        reason: 'synthetic operator evidence persisted',
        path: path,
        revision: nextRevision,
      );
    } catch (error) {
      return FindMyTableSaveResult(
        saved: false,
        reason: 'operator persistence failed (${error.runtimeType})',
        path: path,
      );
    }
  }

  Future<FindMyTableLoadResult> load({
    required String personaId,
    required String factoryRunId,
    required String candidateId,
    String? assemblyAuthorizationId,
  }) async {
    String path;
    try {
      path = pathFor(
        personaId: personaId,
        factoryRunId: factoryRunId,
        candidateId: candidateId,
      );
    } on ArgumentError catch (error) {
      return FindMyTableLoadResult(
        operator: null,
        reason: error.message.toString(),
      );
    }

    try {
      final raw = await _store.read(path);
      if (raw == null) {
        return FindMyTableLoadResult(
          operator: null,
          reason: 'operator snapshot not found',
          path: path,
        );
      }
      if (raw is! Map) {
        return FindMyTableLoadResult(
          operator: null,
          reason: 'operator document is not an object',
          path: path,
        );
      }
      if ((raw['repositorySchemaVersion'] as num?)?.toInt() != 1) {
        return FindMyTableLoadResult(
          operator: null,
          reason: 'unsupported repository document refused',
          path: path,
        );
      }
      if (raw['personaId']?.toString() != personaId.trim() ||
          raw['factoryRunId']?.toString() != factoryRunId.trim() ||
          raw['candidateId']?.toString() != candidateId.trim() ||
          raw['packetId']?.toString() != findMyTablePacketId ||
          raw['scanSessionId']?.toString() != findMyTableScanSessionId) {
        return FindMyTableLoadResult(
          operator: null,
          reason:
              'stored document identity does not match exact run-scoped path',
          path: path,
        );
      }
      final revision = (raw['revision'] as num?)?.toInt() ?? -1;
      if (revision <= 0 || raw['operator'] is! Map) {
        return FindMyTableLoadResult(
          operator: null,
          reason: 'repository envelope is malformed',
          path: path,
        );
      }
      var operator = FindMyTableOperator.fromJson(
        Map<Object?, Object?>.from(raw['operator'] as Map),
      );
      if (operator.packetId != raw['packetId']?.toString() ||
          operator.factoryRunId != factoryRunId.trim() ||
          operator.scanSessionId != raw['scanSessionId']?.toString() ||
          operator.candidateId != candidateId.trim() ||
          !operator.syntheticOnly) {
        return FindMyTableLoadResult(
          operator: null,
          reason:
              'stored operator identity or safety mode does not match envelope',
          path: path,
        );
      }
      if (assemblyAuthorizationId != null) {
        try {
          operator = operator.reapplyRegisteredAssemblyAuthorization(
            assemblyAuthorizationId,
          );
        } on StateError catch (error) {
          return FindMyTableLoadResult(
            operator: null,
            reason: 'Assembly authority refused: ${error.message}',
            path: path,
          );
        }
      }
      return FindMyTableLoadResult(
        operator: operator,
        reason: assemblyAuthorizationId == null
            ? 'operator loaded without Assembly authority'
            : 'operator loaded and exact registered Assembly authority reapplied',
        path: path,
        revision: revision,
      );
    } on FormatException catch (error) {
      return FindMyTableLoadResult(
        operator: null,
        reason: 'operator schema refused: ${error.message}',
        path: path,
      );
    } catch (error) {
      return FindMyTableLoadResult(
        operator: null,
        reason: 'operator load failed (${error.runtimeType})',
        path: path,
      );
    }
  }
}
