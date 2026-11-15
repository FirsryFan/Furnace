import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/ai/domain/agent_run.dart';
import 'package:furnace/features/ai/domain/claim.dart';
import 'package:furnace/features/ai/domain/process_auditor.dart';
import 'package:furnace/features/ai/domain/verifier.dart';
import 'package:furnace/features/ai/infrastructure/agent_run_store.dart';

/// AgentRunStore：run / step / verification 的读写（
/// STUDENT-MODE-AND-AGENT-LOOP-DESIGN §6.1）。
///
/// 用内存 Drift 库，不碰真实文件、不调真实 API。要锁的两件事：字段能原样往返；
/// 以及 §5.6 的硬约束——**库里没有 raw CoT**（列名与被写字段一起断言）。
void main() {
  late AppDatabase db;
  late AgentRunStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = AgentRunStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  AgentRunState newRun({String id = 'run-1', String conversationId = 'conv-1'}) {
    return AgentRunState.start(
      id: id,
      conversationId: conversationId,
      presetId: 'student_solver',
      mode: AgentMode.student,
      startedAt: 1000,
    );
  }

  group('run', () {
    test('保存后按 id 读回，字段原样往返', () async {
      final run = newRun();
      run.enterPhase(AgentPhase.answer);
      run.recordStep(
        promptTokens: 100,
        completionTokens: 200,
        reasoningTokens: 150,
        reasoningChars: 1200,
      );
      run.attachAnswerSheet('{"kind":"solution","result":"7"}');
      run.attachTrace('/tmp/student_solver_traces/trace.json');
      run.attachProcessReport('{"loop_detected":false}');
      run.attachVerifierVerdict('pass');
      run.finish(AgentRunStatus.answered, nowMs: 5000);
      await store.saveRun(run);

      final loaded = (await store.loadRun('run-1'))!;
      expect(loaded.id, 'run-1');
      expect(loaded.conversationId, 'conv-1');
      expect(loaded.presetId, 'student_solver');
      expect(loaded.mode, AgentMode.student);
      expect(loaded.phase, AgentPhase.answer);
      expect(loaded.status, AgentRunStatus.answered);
      expect(loaded.stopReason, isNull);
      expect(loaded.steps, 1);
      expect(loaded.promptTokens, 100);
      expect(loaded.completionTokens, 200);
      expect(loaded.reasoningTokens, 150);
      expect(loaded.reasoningChars, 1200);
      expect(loaded.answerSheetJson, '{"kind":"solution","result":"7"}');
      expect(loaded.tracePath, '/tmp/student_solver_traces/trace.json');
      expect(loaded.processReportJson, '{"loop_detected":false}');
      expect(loaded.verifierVerdict, 'pass');
      expect(loaded.startedAt, 1000);
      expect(loaded.endedAt, 5000);
      expect(loaded.durationMs, 4000);
    });

    test('stop_reason 用稳定 id 往返', () async {
      final run = newRun();
      run.finish(
        AgentRunStatus.stopped,
        stopReason: StopReason.reasoningBudget,
        nowMs: 2000,
      );
      await store.saveRun(run);
      final loaded = (await store.loadRun('run-1'))!;
      expect(loaded.status, AgentRunStatus.stopped);
      expect(loaded.stopReason, StopReason.reasoningBudget);
      // 文件里存的是 id，不是中文。
      final raw = await db.customSelect(
        'SELECT stop_reason FROM agent_runs WHERE id = ?',
        variables: [Variable.withString('run-1')],
      ).getSingle();
      expect(raw.readNullable<String>('stop_reason'), 'reasoning_budget');
    });

    test('过程 blocker 的 stop_reason 落库为 process_loop / process_self_doubt',
        () async {
      expect(StopReason.processLoop.id, 'process_loop');
      expect(StopReason.processSelfDoubt.id, 'process_self_doubt');

      final run = newRun();
      run.finish(
        AgentRunStatus.stopped,
        stopReason: StopReason.processLoop,
        nowMs: 2000,
      );
      await store.saveRun(run);
      final raw = await db.customSelect(
        'SELECT stop_reason FROM agent_runs WHERE id = ?',
        variables: [Variable.withString('run-1')],
      ).getSingle();
      expect(raw.readNullable<String>('stop_reason'), 'process_loop');
      expect((await store.loadRun('run-1'))!.stopReason, StopReason.processLoop);
      // 稳定 id 可以被反解析回来（读路径不丢原因）。
      expect(StopReason.fromId('process_self_doubt'),
          StopReason.processSelfDoubt);
    });

    test('同一个 id 再保存是更新，不会长出第二行', () async {
      final run = newRun();
      await store.saveRun(run);
      run.enterPhase(AgentPhase.verify);
      run.recordStep(completionTokens: 10);
      await store.saveRun(run);

      final loaded = (await store.loadRun('run-1'))!;
      expect(loaded.phase, AgentPhase.verify);
      expect(loaded.steps, 1);
      expect((await db.select(db.agentRuns).get()).length, 1);
    });

    test('recentRuns 按开始时间倒序，并能按会话过滤/限量', () async {
      await store.saveRun(
        AgentRunState.start(
          id: 'run-a',
          conversationId: 'conv-1',
          presetId: 'assistant',
          mode: AgentMode.chat,
          startedAt: 1000,
        ),
      );
      await store.saveRun(
        AgentRunState.start(
          id: 'run-b',
          conversationId: 'conv-2',
          presetId: 'assistant',
          mode: AgentMode.chat,
          startedAt: 1500,
        ),
      );
      await store.saveRun(
        AgentRunState.start(
          id: 'run-c',
          conversationId: 'conv-1',
          presetId: 'assistant',
          mode: AgentMode.chat,
          startedAt: 2000,
        ),
      );

      final all = await store.recentRuns();
      expect([for (final run in all) run.id], ['run-c', 'run-b', 'run-a']);

      final convOne = await store.recentRuns(conversationId: 'conv-1');
      expect([for (final run in convOne) run.id], ['run-c', 'run-a']);

      final limited = await store.recentRuns(limit: 2);
      expect([for (final run in limited) run.id], ['run-c', 'run-b']);
    });
  });

  group('step', () {
    test('appendStep 写入并按 seq 升序读回', () async {
      await store.appendStep(
        runId: 'run-1',
        seq: 2,
        phase: AgentPhase.answer,
        kind: AgentStepKind.answer,
        stateFingerprint: 'fp-2',
        summary: '模型返回答案卡',
        nowMs: 2000,
      );
      await store.appendStep(
        runId: 'run-1',
        seq: 1,
        phase: AgentPhase.solve,
        kind: AgentStepKind.model,
        toolName: 'question_read',
        argsHash: 'args-hash',
        claimHash: 'claim-hash',
        tokens: 321,
        status: AgentStepStatus.ok,
        nowMs: 1500,
      );

      final steps = await store.loadSteps('run-1');
      expect([for (final step in steps) step.seq], [1, 2]);
      expect(steps.first.kind, AgentStepKind.model);
      expect(steps.first.toolName, 'question_read');
      expect(steps.first.tokens, 321);
      expect(steps.first.createdAt, 1500);
      expect(steps.last.kind, AgentStepKind.answer);
      expect(steps.last.summary, '模型返回答案卡');
    });

    test('同一 (runId, seq) 写两次会失败（UNIQUE 约束）', () async {
      await store.appendStep(
        runId: 'run-1',
        seq: 1,
        phase: AgentPhase.solve,
        kind: AgentStepKind.model,
        nowMs: 1000,
      );
      await expectLater(
        store.appendStep(
          runId: 'run-1',
          seq: 1,
          phase: AgentPhase.solve,
          kind: AgentStepKind.model,
          nowMs: 1001,
        ),
        throwsA(anything),
      );
      expect((await store.loadSteps('run-1')).length, 1);
    });
  });

  group('verification', () {
    test('内容验证原样往返（issues / evidence / independent）', () async {
      await store.saveVerification(
        runId: 'run-1',
        verifierId: 'student_independent_v1',
        verification: Verification.fail(
          failureType: FailureType.missingAnswer,
          issues: const ['第 (3) 问没有答案'],
          evidence: const {'confidence': 0.2, 'detail': '缺少第(3)问'},
          independent: true,
        ),
        nowMs: 2500,
      );

      final stored = (await store.loadVerifications('run-1')).single;
      expect(stored.verifierId, 'student_independent_v1');
      expect(stored.kind, VerifierKind.content);
      expect(stored.independent, isTrue);
      expect(stored.verification.verdict, Verdict.fail);
      expect(stored.verification.failureType, FailureType.missingAnswer);
      expect(stored.verification.issues, ['第 (3) 问没有答案']);
      expect(stored.verification.evidence['detail'], '缺少第(3)问');
      expect(stored.createdAt, 2500);
      expect(stored.processReportJson, isNull);
    });

    test('过程审计记录成 kind=process、independent=false', () async {
      final report = ProcessAuditor().audit(
        reasoning: '设物块质量为 m。\n设物块质量为 m。\n设物块质量为 m。',
      );
      expect(report.loopDetected, isTrue);

      await store.saveProcessAudit(runId: 'run-1', report: report, nowMs: 3000);

      final stored = (await store.loadVerifications('run-1')).single;
      expect(stored.kind, VerifierKind.process);
      expect(stored.verifierId, AgentRunStore.processAuditorId);
      expect(stored.independent, isFalse);
      expect(stored.verification.verdict, Verdict.fail);
      expect(stored.verification.failureType, FailureType.loop);
      expect(stored.processReportJson, isNotNull);
      // 报告可还原：库里存的是报告 JSON 原文。
      final decoded = ProcessReport.fromJson(
        jsonDecode(stored.processReportJson!),
      );
      expect(decoded.loopDetected, isTrue);
      expect(decoded.flags, contains('repeated_sentence'));
    });

    test('只有自我怀疑时过程审计是 unknown，不是 fail 也不是 pass', () async {
      final report = ProcessAuditor().audit(
        reasoning: '也许这里取错方向了。\n我可能错了。再检查一遍。\n我怀疑这个符号不对。',
      );
      expect(report.flags, contains('self_doubt'));
      await store.saveProcessAudit(runId: 'run-1', report: report);
      final stored = (await store.loadVerifications('run-1')).single;
      expect(stored.verification.verdict, Verdict.unknown);
      expect(stored.verification.failureType, FailureType.selfDoubt);
      expect(stored.verification.allowsFinalize, isFalse);
    });
  });

  group('claim', () {
    Claim equationClaim({String id = 'claim-abc'}) => Claim(
          id: id,
          kind: ClaimKind.equation,
          canonical: 'm2/m1=7',
          statement: 'm_2 / m_1 = 7',
          deps: const [ClaimRef(claimId: 'claim-dep', version: 2)],
          status: ClaimStatus.proposed,
          evidence: '在 reasoning 里出现 2 次',
          // 过程审计抽取的 claim 没有真实时钟，createdAtMs = 0 由 store 补。
          createdAtMs: 0,
        );

    test('saveClaims 写 agent_claims 行，字段按 v45 表映射', () async {
      await store.saveClaims(
        runId: 'run-1',
        claims: [equationClaim()],
        nowMs: 4000,
      );

      final rows = await db.select(db.agentClaims).get();
      expect(rows, hasLength(1));
      final row = rows.single;
      // 行 id 带 runId：claim.id 是内容 hash，不同 run 的同一条 claim 必须分属
      // 不同行，否则第二次 run 会覆盖第一次的 run_id。
      expect(row.id, 'run-1-claim-abc');
      expect(row.runId, 'run-1');
      expect(row.kind, 'equation');
      expect(row.canonical, 'm2/m1=7');
      expect(row.statement, 'm_2 / m_1 = 7');
      expect(row.depsJson, isNotNull);
      expect(row.depsJson, contains('"id":"claim-dep"'));
      expect(row.depsJson, contains('"version":2'));
      expect(row.status, 'proposed');
      expect(row.checkMethod, isNull);
      expect(row.checkedVersion, 0);
      expect(row.evidence, '在 reasoning 里出现 2 次');
      // 抽取时 createdAtMs = 0，落库用注入时钟补上，不会写 0。
      expect(row.createdAt, 4000);
    });

    test('verified claim 的 status / checked_version / check_method 原样落库',
        () async {
      final claim = Claim(
        id: 'claim-verified',
        kind: ClaimKind.decision,
        canonical: 'μ=0.5',
        statement: '摩擦因数为 0.5',
        status: ClaimStatus.verified,
        checkedVersion: 2,
        version: 2,
        checkMethod: ClaimCheckMethod.deterministic,
        evidence: '代入数值成立',
      );
      await store.saveClaims(runId: 'run-1', claims: [claim], nowMs: 4000);
      final row = (await db.select(db.agentClaims).get()).single;
      expect(row.status, 'verified');
      expect(row.checkMethod, 'deterministic');
      expect(row.checkedVersion, 2);
      expect(row.evidence, '代入数值成立');
    });

    test('同一 run 重复 saveClaims 是幂等覆盖；不同 run 各自一行', () async {
      await store.saveClaims(
        runId: 'run-1',
        claims: [equationClaim()],
        nowMs: 4000,
      );
      await store.saveClaims(
        runId: 'run-1',
        claims: [equationClaim()],
        nowMs: 5000,
      );
      expect(await db.select(db.agentClaims).get(), hasLength(1));

      await store.saveClaims(
        runId: 'run-2',
        claims: [equationClaim()],
        nowMs: 6000,
      );
      final rows = await db.select(db.agentClaims).get();
      expect(rows, hasLength(2));
      expect(
        [for (final row in rows) row.runId]..sort(),
        ['run-1', 'run-2'],
      );
      expect(
        [for (final row in rows) row.id]..sort(),
        ['run-1-claim-abc', 'run-2-claim-abc'],
      );
    });

    test('空列表不写行', () async {
      final written = await store.saveClaims(runId: 'run-1', claims: const []);
      expect(written, 0);
      expect(await db.select(db.agentClaims).get(), isEmpty);
    });
  });

  group('不存 raw CoT', () {
    test('agent_runs / agent_steps 没有 reasoning 正文列', () async {
      final runColumns = await db.columnsOf('agent_runs');
      expect(runColumns, contains('reasoning_chars'));
      expect(runColumns, contains('reasoning_tokens'));
      expect(runColumns, isNot(contains('reasoning')));
      expect(runColumns, isNot(contains('raw_cot')));

      final stepColumns = await db.columnsOf('agent_steps');
      expect(stepColumns, isNot(contains('reasoning')));
      expect(stepColumns, isNot(contains('raw_cot')));
    });

    test('run 只带长度，答案卡 JSON 里也只有结构化答案', () async {
      final run = newRun();
      run.addUsage(reasoningChars: 20439, reasoningTokens: 9000);
      run.attachAnswerSheet('{"kind":"solution","result":"7","process":"..."}');
      await store.saveRun(run);

      final loaded = (await store.loadRun('run-1'))!;
      expect(loaded.reasoningChars, 20439);
      expect(loaded.reasoningTokens, 9000);
      expect(loaded.answerSheetJson, contains('"result":"7"'));
    });
  });
}
