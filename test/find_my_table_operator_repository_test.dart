import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/logic/find_my_table_operator.dart';
import 'package:homecoming_app/services/core/find_my_table_operator_repository.dart';

class _MemoryStore implements FindMyTableDocumentStore {
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
    final actual =
        existing is Map ? (existing['revision'] as num?)?.toInt() ?? 0 : 0;
    if (actual != expectedRevision) return false;
    documents[path] = document;
    return true;
  }
}

FindMyTableOperator operator() => FindMyTableOperator.createAuthorized(
      authorizationId: findMyTableAssemblyAuthorizationId,
      players: const [],
      dms: const [],
      slots: const [],
    );

void main() {
  test('uses exact persona, run, and candidate path and rejects unsafe keys',
      () {
    expect(
      FindMyTableOperatorRepository.pathFor(
        personaId: 'truekai',
        factoryRunId: findMyTableFactoryRunId,
        candidateId: findMyTableCandidateId,
      ),
      'kai/truekai/factory/find_my_table/'
      '$findMyTableFactoryRunId/$findMyTableCandidateId',
    );
    expect(
      () => FindMyTableOperatorRepository.pathFor(
        personaId: 'truekai',
        factoryRunId: '../other',
        candidateId: findMyTableCandidateId,
      ),
      throwsArgumentError,
    );
  });

  test('round trip preserves snapshot and only registry reapplies authority',
      () async {
    final store = _MemoryStore();
    final repository = FindMyTableOperatorRepository(store: store);
    final saved = await repository.save(
      personaId: 'truekai',
      factoryRunId: findMyTableFactoryRunId,
      candidateId: findMyTableCandidateId,
      operator: operator(),
      expectedRevision: 0,
    );
    expect(saved.saved, isTrue);
    expect(saved.revision, 1);
    final raw = store.documents[saved.path] as Map;
    expect((raw['operator'] as Map).containsKey('authority'), isFalse);

    final untrusted = await repository.load(
      personaId: 'truekai',
      factoryRunId: findMyTableFactoryRunId,
      candidateId: findMyTableCandidateId,
    );
    expect(untrusted.loaded, isTrue);
    expect(untrusted.operator!.isAssemblyAuthorized, isFalse);

    final trusted = await repository.load(
      personaId: 'truekai',
      factoryRunId: findMyTableFactoryRunId,
      candidateId: findMyTableCandidateId,
      assemblyAuthorizationId: findMyTableAssemblyAuthorizationId,
    );
    expect(trusted.loaded, isTrue);
    expect(trusted.operator!.isAssemblyAuthorized, isTrue);
  });

  test('copied envelope, future schema, and forged authority fail closed',
      () async {
    final store = _MemoryStore();
    final repository = FindMyTableOperatorRepository(store: store);
    final saved = await repository.save(
      personaId: 'truekai',
      factoryRunId: findMyTableFactoryRunId,
      candidateId: findMyTableCandidateId,
      operator: operator(),
      expectedRevision: 0,
    );
    final path = saved.path!;
    final original = Map<String, Object?>.from(store.documents[path] as Map);
    store.documents[path] = {...original, 'factoryRunId': 'old-run'};
    var loaded = await repository.load(
      personaId: 'truekai',
      factoryRunId: findMyTableFactoryRunId,
      candidateId: findMyTableCandidateId,
    );
    expect(loaded.loaded, isFalse);
    expect(loaded.reason, contains('identity'));

    final futureOperator =
        Map<Object?, Object?>.from(original['operator'] as Map)
          ..['schemaVersion'] = 99;
    store.documents[path] = {...original, 'operator': futureOperator};
    loaded = await repository.load(
      personaId: 'truekai',
      factoryRunId: findMyTableFactoryRunId,
      candidateId: findMyTableCandidateId,
    );
    expect(loaded.loaded, isFalse);
    expect(loaded.reason, contains('schema refused'));

    store.documents[path] = original;
    loaded = await repository.load(
      personaId: 'truekai',
      factoryRunId: findMyTableFactoryRunId,
      candidateId: findMyTableCandidateId,
      assemblyAuthorizationId: 'forged',
    );
    expect(loaded.loaded, isFalse);
    expect(loaded.reason, contains('authority refused'));
  });

  test('stale revision and store failures are explicit', () async {
    final store = _MemoryStore();
    final repository = FindMyTableOperatorRepository(store: store);
    final first = await repository.save(
      personaId: 'truekai',
      factoryRunId: findMyTableFactoryRunId,
      candidateId: findMyTableCandidateId,
      operator: operator(),
      expectedRevision: 0,
    );
    expect(first.saved, isTrue);
    final stale = await repository.save(
      personaId: 'truekai',
      factoryRunId: findMyTableFactoryRunId,
      candidateId: findMyTableCandidateId,
      operator: operator(),
      expectedRevision: 0,
    );
    expect(stale.saved, isFalse);
    expect(stale.reason, contains('reload and reapply'));

    store.readFailure = StateError('offline');
    final loadFailure = await repository.load(
      personaId: 'truekai',
      factoryRunId: findMyTableFactoryRunId,
      candidateId: findMyTableCandidateId,
    );
    expect(loadFailure.reason, contains('load failed'));

    store.readFailure = null;
    store.writeFailure = StateError('denied');
    final saveFailure = await repository.save(
      personaId: 'truekai',
      factoryRunId: findMyTableFactoryRunId,
      candidateId: findMyTableCandidateId,
      operator: operator(),
      expectedRevision: 1,
    );
    expect(saveFailure.reason, contains('persistence failed'));
  });

  test('default KaiDb adapter refuses blind writes', () async {
    const repository = FindMyTableOperatorRepository(
      store: KaiDbFindMyTableDocumentStore(),
    );
    final result = await repository.save(
      personaId: 'truekai',
      factoryRunId: findMyTableFactoryRunId,
      candidateId: findMyTableCandidateId,
      operator: operator(),
      expectedRevision: 0,
    );
    expect(result.saved, isFalse);
    expect(result.reason, contains('UnsupportedError'));
  });
}
