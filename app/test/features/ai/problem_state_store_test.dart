import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/problem_state.dart';
import 'package:furnace/features/ai/domain/problem_state_store.dart';

ProblemState _state({String id = 'problem-q15', int created = 1000}) =>
    ProblemState(
      node: ProblemNode(
        id: id,
        title: 'Q15 电容器',
        goal: '求出 m2/m1 与 E 的取值范围',
        created: created,
        updated: created,
      ),
    );

ProblemFact _fact() => ProblemFact(
      id: 'fact-1',
      text: '题干给出 m1 = 2 kg',
      source: 'source/question.md#L12',
      confidence: 0.9,
      trust: FactTrust.verified,
      createdAt: 1001,
    );

ProblemAssumption _assumption() => ProblemAssumption(
      id: 'assumption-1',
      statement: '忽略摩擦',
      createdAt: 1002,
    );

ProblemDecision _decision() => ProblemDecision(
      id: 'decision-1',
      choice: '只取两支',
      rationale: '代入边界后 E >= 16 不成立',
      alternatives: ['取三支（含 E >= 16）'],
      createdAt: 1003,
    );

ProblemUnknown _unknown() => ProblemUnknown(
      id: 'unknown-1',
      question: 'E 还有没有第三支？',
      owner: 'solver',
      createdAt: 1004,
    );

void main() {
  group('save / load', () {
    test('round-trips a problem through the store', () async {
      final store = InMemoryProblemStateStore();
      final state = _state()..addFact(_fact(), nowMs: 1001);
      await store.save(state);

      final loaded = await store.load('problem-q15');
      expect(loaded, isNotNull);
      expect(loaded!.toJson(), equals(state.toJson()));
      expect(loaded.version, state.version);
      expect(loaded.facts, hasLength(1));
    });

    test('missing problem loads as null, not an empty state', () async {
      final store = InMemoryProblemStateStore();
      expect(await store.load('no-such-problem'), isNull);
    });

    test('save stores a snapshot, not the caller object', () async {
      final store = InMemoryProblemStateStore();
      final state = _state();
      await store.save(state);
      state.addAssumption(_assumption(), nowMs: 2000);
      expect((await store.load('problem-q15'))!.assumptions, isEmpty);
    });

    test('load returns a snapshot: mutating it does not change the store',
        () async {
      final store = InMemoryProblemStateStore([_state()]);
      final first = await store.load('problem-q15');
      expect(first, isNotNull);
      first!.addAssumption(_assumption(), nowMs: 2000);
      final second = await store.load('problem-q15');
      expect(second!.assumptions, isEmpty);
      expect(second.version, 1);
    });

    test('preset states are copied, not aliased', () async {
      final preset = _state();
      final store = InMemoryProblemStateStore([preset]);
      preset.addFact(_fact(), nowMs: 1500);
      expect((await store.load('problem-q15'))!.facts, isEmpty);
    });
  });

  group('append', () {
    test('bumps version and records the event', () async {
      final store = InMemoryProblemStateStore([_state()]);
      final after = await store.append(
        problemId: 'problem-q15',
        kind: ProblemEventKind.custom,
        summary: 'checker 返回 pass',
        payload: <String, Object?>{'verdict': 'pass'},
        nowMs: 1100,
      );
      expect(after.version, 2);
      expect(after.events.single.seq, 1);
      expect(after.events.single.kind, ProblemEventKind.custom);
      expect(after.events.single.payload['verdict'], 'pass');
      expect(after.node.updated, 1100);

      final loaded = await store.load('problem-q15');
      expect(loaded!.version, 2);
      expect(loaded.events.single.payload['verdict'], 'pass');
    });

    test('two appends keep the version monotonic', () async {
      final store = InMemoryProblemStateStore([_state()]);
      final first = await store.append(
        problemId: 'problem-q15',
        kind: ProblemEventKind.custom,
        nowMs: 1100,
      );
      final second = await store.append(
        problemId: 'problem-q15',
        kind: ProblemEventKind.custom,
        nowMs: 1200,
      );
      expect(second.version, greaterThan(first.version));
      expect([for (final event in second.events) event.seq], [1, 2]);
    });

    test('append to a missing problem is rejected', () async {
      final store = InMemoryProblemStateStore();
      await expectLater(
        store.append(
          problemId: 'missing',
          kind: ProblemEventKind.custom,
        ),
        throwsStateError,
      );
    });

    test('append to a revoked problem is rejected, history stays', () async {
      final store = InMemoryProblemStateStore([_state()]);
      final revoked = await store.revoke(
        problemId: 'problem-q15',
        reason: '题目抄错',
        nowMs: 2000,
      );
      await expectLater(
        store.append(
          problemId: 'problem-q15',
          kind: ProblemEventKind.custom,
          nowMs: 2001,
        ),
        throwsStateError,
      );
      final loaded = (await store.load('problem-q15'))!;
      expect(loaded.version, revoked.version);
      expect(loaded.events, hasLength(revoked.events.length));
    });
  });

  group('task must reference problemId', () {
    test('empty problemId is rejected and the store is unchanged', () async {
      final store = InMemoryProblemStateStore([_state()]);
      await expectLater(
        store.attachTask(problemId: '', taskId: 'task-1'),
        throwsArgumentError,
      );
      final loaded = (await store.load('problem-q15'))!;
      expect(loaded.tasks, isEmpty);
      expect(loaded.version, 1);
    });

    test('a whitespace-only problemId is rejected too', () async {
      final store = InMemoryProblemStateStore([_state()]);
      await expectLater(
        store.attachTask(problemId: '   ', taskId: 'task-1'),
        throwsArgumentError,
      );
    });

    test('empty taskId is rejected', () async {
      final store = InMemoryProblemStateStore([_state()]);
      await expectLater(
        store.attachTask(problemId: 'problem-q15', taskId: '  '),
        throwsArgumentError,
      );
    });

    test('attaching to a missing problem is rejected', () async {
      final store = InMemoryProblemStateStore();
      await expectLater(
        store.attachTask(problemId: 'missing', taskId: 'task-1'),
        throwsStateError,
      );
    });

    test('attaches a task and remembers the problem reference', () async {
      final store = InMemoryProblemStateStore([_state()]);
      final link = await store.attachTask(
        problemId: 'problem-q15',
        taskId: 'task-1',
        title: '写答案',
        nowMs: 1100,
      );
      expect(link.problemId, 'problem-q15');
      expect(link.taskId, 'task-1');
      expect(link.title, '写答案');

      final loaded = (await store.load('problem-q15'))!;
      expect(loaded.tasks.single.taskId, 'task-1');
      expect(loaded.tasks.single.problemId, 'problem-q15');
      expect(loaded.version, 2);
      expect(loaded.events.single.kind, ProblemEventKind.taskAttached);
    });

    test('attaching the same task twice is idempotent', () async {
      final store = InMemoryProblemStateStore([_state()]);
      final first = await store.attachTask(
        problemId: 'problem-q15',
        taskId: 'task-1',
        nowMs: 1100,
      );
      final second = await store.attachTask(
        problemId: 'problem-q15',
        taskId: 'task-1',
        nowMs: 1200,
      );
      expect(second.attachedAt, first.attachedAt);
      final loaded = (await store.load('problem-q15'))!;
      expect(loaded.tasks, hasLength(1));
      expect(loaded.events, hasLength(1));
    });
  });

  group('markUnknownResolved', () {
    test('resolves an unknown through the store', () async {
      final store = InMemoryProblemStateStore([_state()]);
      final withUnknown = (await store.load('problem-q15'))!
        ..addUnknown(_unknown(), nowMs: 1001);
      await store.save(withUnknown);

      final resolved = await store.markUnknownResolved(
        problemId: 'problem-q15',
        unknownId: 'unknown-1',
        resolution: '只有两支',
        nowMs: 1100,
      );
      expect(resolved.isResolved, isTrue);
      expect(resolved.resolution, '只有两支');
      expect(resolved.resolvedAt, 1100);

      final loaded = (await store.load('problem-q15'))!;
      expect(loaded.unknowns.single.isResolved, isTrue);
      expect(loaded.unknowns.single.resolution, '只有两支');
      expect(loaded.events.last.kind, ProblemEventKind.unknownResolved);
    });

    test('missing unknown is rejected without changing the store', () async {
      final store = InMemoryProblemStateStore([_state()]);
      await expectLater(
        store.markUnknownResolved(
          problemId: 'problem-q15',
          unknownId: 'no-such-unknown',
        ),
        throwsStateError,
      );
      expect((await store.load('problem-q15'))!.events, isEmpty);
    });

    test('no-op when the unknown is already resolved', () async {
      final store = InMemoryProblemStateStore([_state()]);
      final withUnknown = (await store.load('problem-q15'))!
        ..addUnknown(_unknown(), nowMs: 1001);
      await store.save(withUnknown);
      await store.markUnknownResolved(
        problemId: 'problem-q15',
        unknownId: 'unknown-1',
        resolution: '只有两支',
      );
      final version = (await store.load('problem-q15'))!.version;
      final again = await store.markUnknownResolved(
        problemId: 'problem-q15',
        unknownId: 'unknown-1',
        resolution: '另一说',
      );
      expect(again.resolution, '只有两支');
      expect((await store.load('problem-q15'))!.version, version);
    });
  });

  group('revoke keeps history', () {
    test('revoke keeps every bucket and the event log', () async {
      final store = InMemoryProblemStateStore([_state()]);
      final state = (await store.load('problem-q15'))!;
      state
        ..addFact(_fact(), nowMs: 1001)
        ..addAssumption(_assumption(), nowMs: 1002)
        ..addDecision(_decision(), nowMs: 1003)
        ..addUnknown(_unknown(), nowMs: 1004)
        ..attachTask(
          taskId: 'task-1',
          problemId: 'problem-q15',
          nowMs: 1005,
        );
      await store.save(state);
      final versionBefore = (await store.load('problem-q15'))!.version;

      final revoked = await store.revoke(
        problemId: 'problem-q15',
        reason: '题目抄错',
        nowMs: 2000,
      );
      expect(revoked.node.status, ProblemStatus.revoked);
      expect(revoked.version, greaterThan(versionBefore));
      expect(revoked.facts, hasLength(1));
      expect(revoked.assumptions, hasLength(1));
      expect(revoked.decisions, hasLength(1));
      expect(revoked.unknowns, hasLength(1));
      expect(revoked.tasks, hasLength(1));
      expect(revoked.events.last.kind, ProblemEventKind.revoked);
      expect(revoked.events.last.payload['reason'], '题目抄错');

      final loaded = (await store.load('problem-q15'))!;
      expect(loaded.node.status, ProblemStatus.revoked);
      expect(loaded.facts, hasLength(1));
      expect(loaded.events, hasLength(revoked.events.length));
    });

    test('revoking twice does not duplicate history', () async {
      final store = InMemoryProblemStateStore([_state()]);
      final first = await store.revoke(
        problemId: 'problem-q15',
        nowMs: 2000,
      );
      final second = await store.revoke(
        problemId: 'problem-q15',
        nowMs: 2001,
      );
      expect(second.version, first.version);
      expect(
        second.events.where(
          (event) => event.kind == ProblemEventKind.revoked,
        ),
        hasLength(1),
      );
    });

    test('revoking a missing problem is rejected', () async {
      final store = InMemoryProblemStateStore();
      await expectLater(
        store.revoke(problemId: 'missing'),
        throwsStateError,
      );
    });
  });

  group('all', () {
    test('returns every saved problem as a snapshot', () async {
      final store = InMemoryProblemStateStore([
        _state(),
        _state(id: 'problem-2'),
      ]);
      final all = await store.all();
      expect(
        all.map((state) => state.node.id).toSet(),
        {'problem-q15', 'problem-2'},
      );
    });

    test('mutating an all() snapshot does not change the store', () async {
      final store = InMemoryProblemStateStore([_state()]);
      final snapshot = (await store.all()).single;
      snapshot.addFact(_fact(), nowMs: 1500);
      expect((await store.load('problem-q15'))!.facts, isEmpty);
    });
  });
}
