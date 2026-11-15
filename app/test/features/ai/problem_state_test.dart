import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/problem_state.dart';

ProblemNode _node({String id = 'problem-q15', int created = 1000}) =>
    ProblemNode(
      id: id,
      title: 'Q15 电容器',
      goal: '求出 m2/m1 与 E 的取值范围',
      created: created,
      updated: created,
    );

ProblemState _state({String id = 'problem-q15', int created = 1000}) =>
    ProblemState(node: _node(id: id, created: created));

ProblemFact _fact({String id = 'fact-1', int createdAt = 1001}) => ProblemFact(
      id: id,
      text: '题干给出 m1 = 2 kg',
      source: 'source/question.md#L12',
      evidence: 'm1 = 2 kg',
      confidence: 0.9,
      trust: FactTrust.verified,
      createdAt: createdAt,
    );

ProblemAssumption _assumption({
  String id = 'assumption-1',
  int createdAt = 1002,
}) =>
    ProblemAssumption(
      id: id,
      statement: '忽略摩擦',
      rationale: '题目未提摩擦',
      createdAt: createdAt,
    );

ProblemUnknown _unknown({String id = 'unknown-1'}) => ProblemUnknown(
      id: id,
      question: 'E 还有没有第三支？',
      owner: 'solver',
      createdAt: 1003,
    );

ProblemDecision _decision({String id = 'decision-1'}) => ProblemDecision(
      id: id,
      choice: '只取两支',
      rationale: '代入边界后 E >= 16 不成立',
      alternatives: ['取三支（含 E >= 16）'],
      createdAt: 1004,
    );

void main() {
  group('ProblemNode', () {
    test('keeps goal/status/timestamps', () {
      final node = _node();
      expect(node.goal, isNotEmpty);
      expect(node.status, ProblemStatus.draft);
      expect(node.created, 1000);
      expect(node.updated, 1000);
    });

    test('copyWith updates status/updated but keeps id/created', () {
      final node = _node().copyWith(
        status: ProblemStatus.active,
        updated: 1100,
      );
      expect(node.id, 'problem-q15');
      expect(node.created, 1000);
      expect(node.status, ProblemStatus.active);
      expect(node.updated, 1100);
    });

    test('status ids round-trip; unknown ids fall back to draft', () {
      for (final status in ProblemStatus.values) {
        expect(ProblemStatus.fromId(status.id), status);
      }
      expect(ProblemStatus.fromId(null), ProblemStatus.draft);
      expect(ProblemStatus.fromId('not-a-status'), ProblemStatus.draft);
    });

    test('terminal statuses are solved and revoked only', () {
      expect(ProblemStatus.solved.isTerminal, isTrue);
      expect(ProblemStatus.revoked.isTerminal, isTrue);
      expect(ProblemStatus.draft.isTerminal, isFalse);
      expect(ProblemStatus.active.isTerminal, isFalse);
      expect(ProblemStatus.paused.isTerminal, isFalse);
    });
  });

  group('facts and assumptions stay in separate buckets', () {
    test('adding a fact does not touch assumptions and vice versa', () {
      final state = _state();
      state.addFact(_fact(), nowMs: 1001);
      state.addAssumption(_assumption(), nowMs: 1002);

      expect(state.facts, hasLength(1));
      expect(state.assumptions, hasLength(1));
      expect(state.facts.single.id, 'fact-1');
      expect(state.assumptions.single.id, 'assumption-1');
      expect(state.facts.any((fact) => fact.id == 'assumption-1'), isFalse);
      expect(
        state.assumptions.any((assumption) => assumption.id == 'fact-1'),
        isFalse,
      );
      expect(state.events.first.kind, ProblemEventKind.factAdded);
      expect(state.events.last.kind, ProblemEventKind.assumptionAdded);
    });

    test('JSON keeps the two lists under different keys', () {
      final state = _state();
      state.addFact(_fact(), nowMs: 1001);
      state.addAssumption(_assumption(), nowMs: 1002);
      final json = state.toJson();
      expect(json.containsKey('facts'), isTrue);
      expect(json.containsKey('assumptions'), isTrue);
      expect(json['facts'], hasLength(1));
      expect(json['assumptions'], hasLength(1));

      final restored = ProblemState.fromJson(json);
      expect(restored, isNotNull);
      expect(restored!.facts, hasLength(1));
      expect(restored.assumptions, hasLength(1));
      expect(restored.facts.single.text, '题干给出 m1 = 2 kg');
      expect(restored.assumptions.single.statement, '忽略摩擦');
    });

    test('fact without a source is rejected (that is an assumption)', () {
      expect(
        () => ProblemFact(
          id: 'fact-2',
          text: 'm2/m1 = 7',
          source: '  ',
          createdAt: 1005,
        ),
        throwsArgumentError,
      );
    });

    test('assumption without content is rejected', () {
      expect(
        () => ProblemAssumption(
          id: 'assumption-2',
          statement: '',
          createdAt: 1005,
        ),
        throwsArgumentError,
      );
    });
  });

  group('version is monotonic and derived from append-only events', () {
    test('every mutation increments version by one', () {
      final state = _state();
      expect(state.version, 1);
      final versions = <int>[state.version];

      state.addFact(_fact(), nowMs: 1001);
      versions.add(state.version);
      state.addAssumption(_assumption(), nowMs: 1002);
      versions.add(state.version);
      state.addDecision(_decision(), nowMs: 1003);
      versions.add(state.version);
      state.attachTask(
        taskId: 'task-1',
        problemId: state.node.id,
        nowMs: 1004,
      );
      versions.add(state.version);
      state.revoke(reason: '题目抄错', nowMs: 1005);
      versions.add(state.version);

      expect(versions, [1, 2, 3, 4, 5, 6]);
      for (var i = 1; i < versions.length; i++) {
        expect(versions[i], greaterThan(versions[i - 1]));
      }
    });

    test('event seq is 1..n and version == events.length + 1', () {
      final state = _state();
      state.addFact(_fact(), nowMs: 1001);
      state.addUnknown(_unknown(), nowMs: 1003);
      expect([for (final event in state.events) event.seq], [1, 2]);
      expect(state.version, state.events.length + 1);
      expect(state.events.first.kind, ProblemEventKind.factAdded);
      expect(state.events.last.kind, ProblemEventKind.unknownAdded);
    });

    test('node.updated follows the injected clock, not the wall clock', () {
      final state = _state();
      state.addFact(_fact(), nowMs: 1234);
      expect(state.node.updated, 1234);
      state.addAssumption(_assumption(), nowMs: 5678);
      expect(state.node.updated, 5678);
    });

    test('version survives JSON round-trip', () {
      final state = _state();
      state.addFact(_fact(), nowMs: 1001);
      state.addDecision(_decision(), nowMs: 1002);
      final restored = ProblemState.fromJson(
        jsonDecode(jsonEncode(state.toJson())),
      );
      expect(restored!.version, state.version);
      expect(restored.events, hasLength(state.events.length));
    });
  });

  group('revoke keeps history', () {
    test('revoked node keeps every bucket and the event log', () {
      final state = _state();
      state.setOracle(
        AcceptanceOracle(
          kind: OracleKind.rubric,
          source: 'rubric/q15.json#answer',
          description: '三问 rubric 全部可判定',
        ),
        nowMs: 1001,
      );
      state.setBudget(
        const ProblemBudget(maxTokens: 1000, maxRounds: 4),
        nowMs: 1002,
      );
      state.addFact(_fact(), nowMs: 1003);
      state.addAssumption(_assumption(), nowMs: 1004);
      state.addDecision(_decision(), nowMs: 1005);
      state.addUnknown(_unknown(), nowMs: 1006);
      state.addArtifact(
        const ArtifactRef(path: 'traces/q15.jsonl', hash: 'abc123'),
        nowMs: 1007,
      );
      state.attachTask(
        taskId: 'task-1',
        problemId: state.node.id,
        nowMs: 1008,
      );

      final versionBeforeRevoke = state.version;
      state.revoke(reason: '题目抄错', nowMs: 2000);

      expect(state.node.status, ProblemStatus.revoked);
      expect(state.isRevoked, isTrue);
      expect(state.isMutable, isFalse);
      expect(state.version, greaterThan(versionBeforeRevoke));
      expect(state.facts, hasLength(1));
      expect(state.assumptions, hasLength(1));
      expect(state.decisions, hasLength(1));
      expect(state.unknowns, hasLength(1));
      expect(state.tasks, hasLength(1));
      expect(state.artifacts, hasLength(1));
      expect(state.oracle, isNotNull);
      expect(state.budget, isNotNull);
      expect(state.events.last.kind, ProblemEventKind.revoked);
      expect(state.events.last.payload['reason'], '题目抄错');

      // JSON 往返后历史仍然完整。
      final restored = ProblemState.fromJson(state.toJson());
      expect(restored, isNotNull);
      expect(restored!.node.status, ProblemStatus.revoked);
      expect(restored.facts, hasLength(1));
      expect(restored.assumptions, hasLength(1));
      expect(restored.decisions, hasLength(1));
      expect(restored.unknowns, hasLength(1));
      expect(restored.tasks, hasLength(1));
      expect(restored.artifacts, hasLength(1));
      expect(restored.events.last.kind, ProblemEventKind.revoked);
    });

    test('revoke is idempotent and does not append a second event', () {
      final state = _state()..revoke(nowMs: 2000);
      final version = state.version;
      state.revoke(nowMs: 2001);
      expect(state.version, version);
      expect(
        state.events.where(
          (event) => event.kind == ProblemEventKind.revoked,
        ),
        hasLength(1),
      );
    });

    test('revoked problems refuse new entries, history untouched', () {
      final state = _state()..addFact(_fact(), nowMs: 1001);
      state.revoke(nowMs: 2000);
      expect(
        () => state.addFact(_fact(id: 'fact-2'), nowMs: 2001),
        throwsStateError,
      );
      expect(
        () => state.addAssumption(
          _assumption(id: 'assumption-2'),
          nowMs: 2001,
        ),
        throwsStateError,
      );
      expect(state.facts, hasLength(1));
      expect(state.events, hasLength(2)); // factAdded + revoked
    });
  });

  group('budget and approval status', () {
    test('budget moves ok -> warning -> exhausted', () {
      final state = _state();
      state.setBudget(
        const ProblemBudget(maxTokens: 1000, maxTimeMs: 60000, maxRounds: 4),
        nowMs: 1001,
      );
      expect(state.budget!.status, BudgetStatus.ok);
      expect(state.budget!.remainingTokens, 1000);

      state.recordUsage(tokens: 850, timeMs: 1000, rounds: 1, nowMs: 1002);
      expect(state.budget!.status, BudgetStatus.warning);
      expect(state.budget!.usedTokens, 850);
      expect(state.budget!.remainingTokens, 150);
      expect(state.events.last.kind, ProblemEventKind.usageRecorded);

      state.recordUsage(tokens: 200, rounds: 3, nowMs: 1003);
      expect(state.budget!.status, BudgetStatus.exhausted);
      expect(state.budget!.isExhausted, isTrue);
      // 超预算照样记账，不夹回上限。
      expect(state.budget!.usedTokens, 1050);
      expect(state.budget!.remainingTokens, -50);
    });

    test('recordUsage without a budget is an error, not silent bookkeeping',
        () {
      final state = _state();
      expect(
        () => state.recordUsage(tokens: 1, nowMs: 1001),
        throwsStateError,
      );
    });

    test('budget JSON round-trip keeps limits and usage', () {
      final state = _state();
      state.setBudget(
        const ProblemBudget(maxTokens: 1000, maxRounds: 4),
        nowMs: 1001,
      );
      state.recordUsage(tokens: 900, rounds: 4, nowMs: 1002);
      final restored = ProblemState.fromJson(
        jsonDecode(jsonEncode(state.toJson())),
      )!;
      expect(restored.budget!.maxTokens, 1000);
      expect(restored.budget!.maxRounds, 4);
      expect(restored.budget!.usedTokens, 900);
      expect(restored.budget!.usedRounds, 4);
      expect(restored.budget!.status, BudgetStatus.exhausted);
    });

    test('decision starts proposed, moves through approval, survives JSON', () {
      final state = _state()..addDecision(_decision(), nowMs: 1001);
      expect(state.decisions.single.status, DecisionStatus.proposed);
      expect(state.decisions.single.isAccepted, isFalse);

      final accepted = state.updateDecisionStatus(
        'decision-1',
        DecisionStatus.accepted,
        note: '教师确认',
        nowMs: 1002,
      );
      expect(accepted.status, DecisionStatus.accepted);
      expect(accepted.isAccepted, isTrue);
      expect(accepted.decidedAt, 1002);
      expect(state.events.last.kind, ProblemEventKind.decisionStatusChanged);

      final restored = ProblemState.fromJson(
        jsonDecode(jsonEncode(state.toJson())),
      )!;
      expect(restored.decisions.single.status, DecisionStatus.accepted);
      expect(restored.decisions.single.decidedAt, 1002);
    });

    test('approval state is reworkable (accepted -> rejected)', () {
      final state = _state()..addDecision(_decision(), nowMs: 1001);
      state.updateDecisionStatus(
        'decision-1',
        DecisionStatus.accepted,
        nowMs: 1002,
      );
      final rejected = state.updateDecisionStatus(
        'decision-1',
        DecisionStatus.rejected,
        note: 'review 发现漏支',
        nowMs: 1003,
      );
      expect(rejected.status, DecisionStatus.rejected);
      expect(rejected.decidedAt, 1003);
    });

    test('updating a missing decision is an error', () {
      final state = _state();
      expect(
        () => state.updateDecisionStatus('nope', DecisionStatus.accepted),
        throwsStateError,
      );
    });

    test('unknown resolution fills status/resolution/resolvedAt', () {
      final state = _state()..addUnknown(_unknown(), nowMs: 1001);
      final resolved = state.markUnknownResolved(
        'unknown-1',
        resolution: '已经确认只有两支',
        nowMs: 1002,
      );
      expect(resolved.status, UnknownStatus.resolved);
      expect(resolved.isResolved, isTrue);
      expect(resolved.resolution, '已经确认只有两支');
      expect(resolved.resolvedAt, 1002);
      expect(state.unknowns.single.isResolved, isTrue);
      // 幂等：再次解决不覆盖第一次结论。
      final again = state.markUnknownResolved(
        'unknown-1',
        resolution: '另一说',
        nowMs: 1003,
      );
      expect(again.resolution, '已经确认只有两支');
    });

    test('resolving a missing unknown is an error', () {
      final state = _state();
      expect(
        () => state.markUnknownResolved('nope', nowMs: 1001),
        throwsStateError,
      );
    });
  });

  group('task must reference a problemId', () {
    test('empty problemId is rejected by the link and by the aggregate', () {
      expect(
        () => ProblemTaskLink(
          taskId: 'task-1',
          problemId: '',
          attachedAt: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => ProblemTaskLink(
          taskId: 'task-1',
          problemId: '   ',
          attachedAt: 1,
        ),
        throwsArgumentError,
      );

      final state = _state();
      expect(
        () => state.attachTask(taskId: 'task-1', problemId: ''),
        throwsArgumentError,
      );
      expect(state.tasks, isEmpty);
    });

    test('a task cannot be attached to a different problem', () {
      final state = _state();
      expect(
        () => state.attachTask(
          taskId: 'task-1',
          problemId: 'problem-other',
        ),
        throwsArgumentError,
      );
      expect(state.tasks, isEmpty);
    });

    test('attaching a task records the problem reference and is idempotent',
        () {
      final state = _state();
      final link = state.attachTask(
        taskId: 'task-1',
        problemId: 'problem-q15',
        title: '写答案',
        nowMs: 1001,
      );
      expect(link.problemId, 'problem-q15');
      expect(link.taskId, 'task-1');
      expect(state.tasks.single.problemId, state.node.id);

      final again = state.attachTask(
        taskId: 'task-1',
        problemId: 'problem-q15',
        nowMs: 1002,
      );
      expect(again.attachedAt, 1001);
      expect(state.tasks, hasLength(1));
    });
  });

  group('JSON round-trip', () {
    test('a fully populated state survives encode/decode', () {
      final state = _state();
      state.setOracle(
        AcceptanceOracle(
          kind: OracleKind.rubric,
          source: 'rubric/q15.json#answer',
          description: '三问 rubric 全部可判定',
        ),
        nowMs: 1001,
      );
      state.setBudget(
        const ProblemBudget(maxTokens: 1000, maxRounds: 4),
        nowMs: 1002,
      );
      state.recordUsage(tokens: 10, timeMs: 20, rounds: 1, nowMs: 1003);
      state.addFact(_fact(), nowMs: 1004);
      state.addAssumption(_assumption(), nowMs: 1005);
      state.addDecision(_decision(), nowMs: 1006);
      state.updateDecisionStatus(
        'decision-1',
        DecisionStatus.accepted,
        note: '教师确认',
        nowMs: 1007,
      );
      state.addUnknown(_unknown(), nowMs: 1008);
      state.markUnknownResolved(
        'unknown-1',
        resolution: '只有两支',
        nowMs: 1009,
      );
      state.addArtifact(
        const ArtifactRef(
          path: 'traces/q15.jsonl',
          hash: 'abc123',
          version: 2,
        ),
        nowMs: 1010,
      );
      state.attachTask(
        taskId: 'task-1',
        problemId: state.node.id,
        title: '写答案',
        nowMs: 1011,
      );

      final encoded = jsonEncode(state.toJson());
      final decoded = jsonDecode(encoded);
      final restored = ProblemState.fromJson(decoded);

      expect(restored, isNotNull);
      expect(restored!.toJson(), equals(state.toJson()));
      expect(restored.version, state.version);
      expect(restored.oracle!.kind, OracleKind.rubric);
      expect(restored.artifacts.single.version, 2);
      expect(restored.tasks.single.problemId, state.node.id);
    });

    test('bad JSON returns null instead of a half-built state', () {
      expect(ProblemState.fromJson(null), isNull);
      expect(ProblemState.fromJson('not a map'), isNull);
      expect(ProblemState.fromJson(<String, Object?>{}), isNull);
      expect(
        ProblemState.fromJson(
          <String, Object?>{
            'node': <String, Object?>{},
          },
        ),
        isNull,
      );
    });

    test('an event log with a gap is rejected (truncated history)', () {
      final state = _state();
      state.addFact(_fact(), nowMs: 1001);
      state.addAssumption(_assumption(), nowMs: 1002);
      final json = state.toJson();
      final events = (json['events']! as List).cast<Map<String, Object?>>();
      events.removeAt(0);
      expect(ProblemState.fromJson(json), isNull);
    });

    test('copy() is a deep copy: mutating the copy leaves the original', () {
      final state = _state()..addFact(_fact(), nowMs: 1001);
      final copy = state.copy();
      copy.addAssumption(_assumption(), nowMs: 1002);
      expect(state.assumptions, isEmpty);
      expect(copy.assumptions, hasLength(1));
      expect(copy.toJson(), isNot(equals(state.toJson())));
    });
  });
}
