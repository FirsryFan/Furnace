import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/ai/domain/claim.dart';
import 'package:furnace/features/ai/infrastructure/experience_store.dart';

Claim _verifiedClaim({String id = 'claim-1'}) => Claim(
      id: id,
      kind: ClaimKind.equation,
      canonical: 'm2/m1=7',
      statement: 'm_2 / m_1 = 7',
      status: ClaimStatus.verified,
      checkMethod: ClaimCheckMethod.deterministic,
      evidence: '代入数值成立',
    );

Claim _proposedClaim() => Claim(
      id: 'claim-proposed',
      kind: ClaimKind.equation,
      canonical: 'm2/m1=8',
      statement: 'm_2 / m_1 = 8',
    );

void main() {
  group('ExperienceStore writes only verified experience', () {
    late InMemoryExperienceRepository repository;
    late ExperienceStore store;

    setUp(() {
      repository = InMemoryExperienceRepository();
      store = ExperienceStore(repository: repository);
    });

    test('rejects a proposed claim', () async {
      final admission = await store.record(
        claim: _proposedClaim(),
        cluster: 'student_solver',
        stateKey: 'q15',
        action: 'answer m2/m1=8',
        provenanceRunId: 'run-1',
        provenanceVerifierId: 'verifier-1',
      );
      expect(admission.accepted, isFalse);
      expect(admission.rejection, ExperienceRejectionReason.notVerified);
      expect(repository.allRows, isEmpty);
    });

    test('rejects a refuted claim', () async {
      final claim = _verifiedClaim()..status = ClaimStatus.refuted;
      final admission = await store.record(
        claim: claim,
        cluster: 'student_solver',
        stateKey: 'q15',
        action: 'answer',
        provenanceRunId: 'run-1',
        provenanceVerifierId: 'verifier-1',
      );
      expect(admission.rejection, ExperienceRejectionReason.notVerified);
      expect(repository.allRows, isEmpty);
    });

    test('writes a verified claim with provenance and version 1', () async {
      final admission = await store.record(
        claim: _verifiedClaim(),
        cluster: 'student_solver',
        stateKey: 'q15',
        action: 'answer m2/m1=7',
        reward: 0.9,
        id: 'exp-1',
        provenanceRunId: 'run-1',
        provenanceVerifierId: 'verifier-1',
        nowMs: 1700000000000,
      );
      expect(admission.accepted, isTrue);
      final record = admission.record!;
      expect(record.id, 'exp-1');
      expect(record.version, 1);
      expect(record.reward, 0.9);
      expect(record.provenanceRunId, 'run-1');
      expect(record.provenanceVerifierId, 'verifier-1');
      expect(record.revokedAt, isNull);
      expect(record.createdAt, 1700000000000);
      expect(repository.allRows, hasLength(1));
    });

    test('refuses records without provenance or with blank fields', () async {
      Future<ExperienceAdmission> record({
        String cluster = 'student_solver',
        String stateKey = 'q15',
        String action = 'answer',
        String runId = 'run-1',
        String verifierId = 'verifier-1',
        double reward = 1.0,
      }) =>
          store.record(
            claim: _verifiedClaim(),
            cluster: cluster,
            stateKey: stateKey,
            action: action,
            reward: reward,
            provenanceRunId: runId,
            provenanceVerifierId: verifierId,
          );

      expect(
        (await record(runId: ' ')).rejection,
        ExperienceRejectionReason.missingProvenance,
      );
      expect(
        (await record(verifierId: '')).rejection,
        ExperienceRejectionReason.missingVerifier,
      );
      expect(
        (await record(cluster: '')).rejection,
        ExperienceRejectionReason.emptyField,
      );
      expect(
        (await record(action: '')).rejection,
        ExperienceRejectionReason.emptyField,
      );
      expect(
        (await record(reward: double.nan)).rejection,
        ExperienceRejectionReason.invalidReward,
      );
      expect(repository.allRows, isEmpty);
    });
  });

  group('ExperienceStore versioning and revocation', () {
    late InMemoryExperienceRepository repository;
    late ExperienceStore store;

    setUp(() {
      repository = InMemoryExperienceRepository();
      store = ExperienceStore(repository: repository);
    });

    test('re-validating the same experience bumps the version in place',
        () async {
      final first = await store.record(
        claim: _verifiedClaim(),
        cluster: 'student_solver',
        stateKey: 'q15',
        action: 'answer m2/m1=7',
        reward: 0.7,
        id: 'exp-1',
        provenanceRunId: 'run-1',
        provenanceVerifierId: 'verifier-1',
        nowMs: 1700000000000,
      );
      final second = await store.record(
        claim: _verifiedClaim(),
        cluster: 'student_solver',
        stateKey: 'q15',
        action: 'answer m2/m1=7',
        reward: 1.0,
        provenanceRunId: 'run-2',
        provenanceVerifierId: 'verifier-2',
        nowMs: 1700000005000,
      );
      expect(second.accepted, isTrue);
      expect(second.record!.id, first.record!.id);
      expect(second.record!.version, 2);
      expect(second.record!.reward, 1.0);
      expect(second.record!.provenanceRunId, 'run-2');
      expect(second.record!.createdAt, 1700000000000);
      expect(repository.allRows, hasLength(1));

      final recalled = await store.recall(
        cluster: 'student_solver',
        stateKey: 'q15',
      );
      expect(recalled, hasLength(1));
      expect(recalled.single.version, 2);
    });

    test('revoking hides a record from recall but keeps the row', () async {
      await store.record(
        claim: _verifiedClaim(),
        cluster: 'student_solver',
        stateKey: 'q15',
        action: 'answer m2/m1=7',
        id: 'exp-1',
        provenanceRunId: 'run-1',
        provenanceVerifierId: 'verifier-1',
        nowMs: 1700000000000,
      );
      expect(await store.revoke('exp-1', nowMs: 1700000010000), isTrue);
      final revoked = await store.find('exp-1');
      expect(revoked, isNotNull);
      expect(revoked!.revoked, isTrue);
      expect(revoked.revokedAt, 1700000010000);
      expect(
        await store.recall(cluster: 'student_solver', stateKey: 'q15'),
        isEmpty,
      );
      expect(repository.allRows, hasLength(1));

      // Revoking twice, or an unknown id, reports "nothing to revoke".
      expect(await store.revoke('exp-1'), isFalse);
      expect(await store.revoke('missing'), isFalse);
    });

    test('re-recording after revocation inserts a new versioned row', () async {
      await store.record(
        claim: _verifiedClaim(),
        cluster: 'student_solver',
        stateKey: 'q15',
        action: 'answer m2/m1=7',
        id: 'exp-1',
        provenanceRunId: 'run-1',
        provenanceVerifierId: 'verifier-1',
      );
      await store.revoke('exp-1', nowMs: 1700000010000);

      final again = await store.record(
        claim: _verifiedClaim(),
        cluster: 'student_solver',
        stateKey: 'q15',
        action: 'answer m2/m1=7',
        id: 'exp-2',
        provenanceRunId: 'run-3',
        provenanceVerifierId: 'verifier-3',
        nowMs: 1700000020000,
      );
      expect(again.accepted, isTrue);
      expect(again.record!.version, 2);
      expect(again.record!.id, 'exp-2');
      expect(repository.allRows, hasLength(2));
      final recalled = await store.recall(
        cluster: 'student_solver',
        stateKey: 'q15',
      );
      expect(recalled, hasLength(1));
      expect(recalled.single.id, 'exp-2');
    });

    test('recall orders active records by reward then version', () async {
      Future<void> add(String action, double reward, String id) => store.record(
            claim: _verifiedClaim(),
            cluster: 'student_solver',
            stateKey: 'q15',
            action: action,
            reward: reward,
            id: id,
            provenanceRunId: 'run-1',
            provenanceVerifierId: 'verifier-1',
          );
      await add('action-a', 0.5, 'exp-a');
      await add('action-b', 0.9, 'exp-b');
      final recalled = await store.recall(
        cluster: 'student_solver',
        stateKey: 'q15',
      );
      expect(recalled.map((row) => row.id), ['exp-b', 'exp-a']);
    });
  });

  group('ExperienceRecord json', () {
    test('round-trips through the agent_experiences column shape', () {
      const record = ExperienceRecord(
        id: 'exp-1',
        cluster: 'student_solver',
        stateKey: 'q15',
        action: 'answer m2/m1=7',
        reward: 1.0,
        provenanceRunId: 'run-1',
        provenanceVerifierId: 'verifier-1',
        version: 3,
        revokedAt: 1700000000000,
        createdAt: 1699999999000,
      );
      final restored = ExperienceRecord.fromJson(record.toJson());
      expect(restored, isNotNull);
      expect(restored!.id, record.id);
      expect(restored.cluster, record.cluster);
      expect(restored.stateKey, record.stateKey);
      expect(restored.action, record.action);
      expect(restored.reward, record.reward);
      expect(restored.provenanceRunId, 'run-1');
      expect(restored.provenanceVerifierId, 'verifier-1');
      expect(restored.version, 3);
      expect(restored.revokedAt, 1700000000000);
      expect(restored.createdAt, 1699999999000);
      expect(restored.revoked, isTrue);
    });
  });

  group('DriftExperienceRepository on the v45 agent_experiences table', () {
    late AppDatabase database;
    late ExperienceStore store;

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      store = ExperienceStore(repository: DriftExperienceRepository(database));
    });

    tearDown(() async {
      await database.close();
    });

    test('writes, versions, revokes and recalls through the real table',
        () async {
      final admission = await store.record(
        claim: _verifiedClaim(),
        cluster: 'student_solver',
        stateKey: 'q15',
        action: 'answer m2/m1=7',
        reward: 0.8,
        id: 'exp-1',
        provenanceRunId: 'run-1',
        provenanceVerifierId: 'verifier-1',
        nowMs: 1700000000000,
      );
      expect(admission.accepted, isTrue);

      final recalled = await store.recall(
        cluster: 'student_solver',
        stateKey: 'q15',
      );
      expect(recalled, hasLength(1));
      expect(recalled.single.id, 'exp-1');
      expect(recalled.single.provenanceRunId, 'run-1');
      expect(recalled.single.reward, 0.8);

      // Re-validation updates the row in place and bumps the version.
      final again = await store.record(
        claim: _verifiedClaim(),
        cluster: 'student_solver',
        stateKey: 'q15',
        action: 'answer m2/m1=7',
        reward: 1.0,
        provenanceRunId: 'run-2',
        provenanceVerifierId: 'verifier-2',
        nowMs: 1700000005000,
      );
      expect(again.record!.version, 2);
      expect(
        await (database.select(database.agentExperiences)).get(),
        hasLength(1),
      );

      // Revocation is persisted as revoked_at, not as a delete.
      expect(await store.revoke('exp-1', nowMs: 1700000010000), isTrue);
      final row = await (database.select(database.agentExperiences)
            ..where((table) => table.id.equals('exp-1')))
          .getSingle();
      expect(row.revokedAt, 1700000010000);
      expect(
        await store.recall(cluster: 'student_solver', stateKey: 'q15'),
        isEmpty,
      );
      final all = await (database.select(database.agentExperiences)).get();
      expect(all, hasLength(1));
      expect(all.single.revokedAt, 1700000010000);
    });

    test('rejects unverified experience before touching the table', () async {
      final admission = await store.record(
        claim: _proposedClaim(),
        cluster: 'student_solver',
        stateKey: 'q15',
        action: 'answer m2/m1=8',
        provenanceRunId: 'run-1',
        provenanceVerifierId: 'verifier-1',
      );
      expect(admission.rejection, ExperienceRejectionReason.notVerified);
      expect(await (database.select(database.agentExperiences)).get(), isEmpty);
    });
  });
}
