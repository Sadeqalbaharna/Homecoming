import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/factory_scan_session.dart';
import 'package:homecoming_app/services/core/factory_scan_session_repository.dart';

class _MemoryStore implements FactoryScanDocumentStore {
  final Map<String, Object?> documents = {};
  Object? readFailure;
  Object? writeFailure;

  @override
  Future<Object?> read(String path) async {
    if (readFailure != null) throw readFailure!;
    return documents[path];
  }

  @override
  Future<bool> writeIfRevision(
    String path,
    Map<String, Object?> document, {
    required int expectedRevision,
  }) async {
    if (writeFailure != null) throw writeFailure!;
    final existing = documents[path];
    final actualRevision =
        existing is Map ? (existing['revision'] as num?)?.toInt() ?? 0 : 0;
    if (actualRevision != expectedRevision) return false;
    documents[path] = document;
    return true;
  }
}

void main() {
  FactoryScanSession session([String id = 'scan-001']) =>
      FactoryScanSession.start(
        id: id,
        startedAtMs: 1000,
        scanPolicyVersion: 'signal-scan-v1',
      );

  test('uses an exact persona, Factory run, and scan-session path', () {
    expect(
      FactoryScanSessionRepository.pathFor(
        personaId: 'truekai',
        factoryRunId: 'run-001',
        scanSessionId: 'scan-001',
      ),
      'kai/truekai/factory/scan_sessions/run-001/scan-001',
    );
  });

  test('rejects unsafe Firebase path identifiers', () {
    for (final unsafe in ['', 'a/b', 'a.b', r'a$b', 'a[b]']) {
      expect(
        () => FactoryScanSessionRepository.pathFor(
          personaId: 'truekai',
          factoryRunId: unsafe,
          scanSessionId: 'scan-001',
        ),
        throwsArgumentError,
      );
    }
  });

  test('round trips the same session without mirrored mutable truth', () async {
    final store = _MemoryStore();
    final repository = FactoryScanSessionRepository(store: store);
    final original = session();

    final saved = await repository.save(
      personaId: 'truekai',
      factoryRunId: 'run-001',
      session: original,
      expectedRevision: 0,
    );
    final loaded = await repository.load(
      personaId: 'truekai',
      factoryRunId: 'run-001',
      scanSessionId: 'scan-001',
    );

    expect(saved.saved, isTrue);
    expect(store.documents, hasLength(1));
    expect(saved.revision, 1);
    final raw = store.documents[saved.path] as Map;
    expect(raw['personaId'], 'truekai');
    expect(raw['factoryRunId'], 'run-001');
    expect((raw['session'] as Map).containsKey('audit'), isFalse);
    expect((raw['session'] as Map).containsKey('transparentTraitWeights'),
        isFalse);
    expect(loaded.loaded, isTrue);
    expect(loaded.session!.toJson(), original.toJson());
  });

  test('loads a bound envelope containing a schema-zero session', () async {
    final store = _MemoryStore();
    final path = FactoryScanSessionRepository.pathFor(
      personaId: 'truekai',
      factoryRunId: 'run-001',
      scanSessionId: 'legacy',
    );
    store.documents[path] = {
      'repositorySchemaVersion': 1,
      'personaId': 'truekai',
      'factoryRunId': 'run-001',
      'scanSessionId': 'legacy',
      'revision': 1,
      'session': {'id': 'legacy', 'startedAtMs': 50},
    };
    final loaded = await FactoryScanSessionRepository(store: store).load(
      personaId: 'truekai',
      factoryRunId: 'run-001',
      scanSessionId: 'legacy',
    );

    expect(loaded.loaded, isTrue);
    expect(loaded.session!.schemaVersion, factoryScanSchemaVersion);
    expect(loaded.session!.attempts, isEmpty);
  });

  test('future schema and path/document identity mismatch fail closed',
      () async {
    final store = _MemoryStore();
    final path = FactoryScanSessionRepository.pathFor(
      personaId: 'truekai',
      factoryRunId: 'run-001',
      scanSessionId: 'scan-001',
    );
    Map<String, Object?> envelope(Object sessionDocument) => {
          'repositorySchemaVersion': 1,
          'personaId': 'truekai',
          'factoryRunId': 'run-001',
          'scanSessionId': 'scan-001',
          'revision': 1,
          'session': sessionDocument,
        };
    store.documents[path] = envelope({'schemaVersion': 99, 'id': 'scan-001'});
    final repository = FactoryScanSessionRepository(store: store);
    var loaded = await repository.load(
      personaId: 'truekai',
      factoryRunId: 'run-001',
      scanSessionId: 'scan-001',
    );
    expect(loaded.loaded, isFalse);
    expect(loaded.reason, contains('schema refused'));

    store.documents[path] = envelope(session('other-session').toJson());
    loaded = await repository.load(
      personaId: 'truekai',
      factoryRunId: 'run-001',
      scanSessionId: 'scan-001',
    );
    expect(loaded.loaded, isFalse);
    expect(loaded.reason, contains('does not match'));
  });

  test('copied document is refused across persona and Factory run paths',
      () async {
    final store = _MemoryStore();
    final repository = FactoryScanSessionRepository(store: store);
    final saved = await repository.save(
      personaId: 'truekai',
      factoryRunId: 'run-001',
      session: session(),
      expectedRevision: 0,
    );
    final document = store.documents[saved.path]!;
    final otherRunPath = FactoryScanSessionRepository.pathFor(
        personaId: 'truekai',
        factoryRunId: 'run-002',
        scanSessionId: 'scan-001');
    store.documents[otherRunPath] = document;
    var loaded = await repository.load(
        personaId: 'truekai',
        factoryRunId: 'run-002',
        scanSessionId: 'scan-001');
    expect(loaded.loaded, isFalse);
    expect(loaded.reason, contains('identity'));

    final otherPersonaPath = FactoryScanSessionRepository.pathFor(
        personaId: 'other', factoryRunId: 'run-001', scanSessionId: 'scan-001');
    store.documents[otherPersonaPath] = document;
    loaded = await repository.load(
        personaId: 'other', factoryRunId: 'run-001', scanSessionId: 'scan-001');
    expect(loaded.loaded, isFalse);
    expect(loaded.reason, contains('identity'));
  });

  test('stale revision cannot erase a newer session snapshot', () async {
    final store = _MemoryStore();
    final repository = FactoryScanSessionRepository(store: store);
    final first = await repository.save(
        personaId: 'truekai',
        factoryRunId: 'run-001',
        session: session(),
        expectedRevision: 0);
    expect(first.saved, isTrue);
    final stale = await repository.save(
        personaId: 'truekai',
        factoryRunId: 'run-001',
        session: session(),
        expectedRevision: 0);
    expect(stale.saved, isFalse);
    expect(stale.reason, contains('reload and reapply'));
    expect((store.documents[first.path] as Map)['revision'], 1);
  });

  test('missing, malformed, and store failures return explicit outcomes',
      () async {
    final store = _MemoryStore();
    final repository = FactoryScanSessionRepository(store: store);
    var loaded = await repository.load(
      personaId: 'truekai',
      factoryRunId: 'run-001',
      scanSessionId: 'scan-001',
    );
    expect(loaded.reason, 'scan session not found');

    final path = FactoryScanSessionRepository.pathFor(
      personaId: 'truekai',
      factoryRunId: 'run-001',
      scanSessionId: 'scan-001',
    );
    store.documents[path] = 'not an object';
    loaded = await repository.load(
      personaId: 'truekai',
      factoryRunId: 'run-001',
      scanSessionId: 'scan-001',
    );
    expect(loaded.reason, contains('not an object'));

    store.readFailure = StateError('offline');
    loaded = await repository.load(
      personaId: 'truekai',
      factoryRunId: 'run-001',
      scanSessionId: 'scan-001',
    );
    expect(loaded.reason, contains('load failed'));

    store.writeFailure = StateError('denied');
    final saved = await repository.save(
      personaId: 'truekai',
      factoryRunId: 'run-001',
      session: session(),
      expectedRevision: 0,
    );
    expect(saved.saved, isFalse);
    expect(saved.reason, contains('persistence failed'));
  });

  test('default KaiDb adapter fails closed without atomic compare-and-set',
      () async {
    const repository =
        FactoryScanSessionRepository(store: KaiDbFactoryScanDocumentStore());
    final saved = await repository.save(
        personaId: 'truekai',
        factoryRunId: 'run-001',
        session: session(),
        expectedRevision: 0);
    expect(saved.saved, isFalse);
    expect(saved.reason, contains('UnsupportedError'));
  });
}
