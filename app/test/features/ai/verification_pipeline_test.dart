import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/checker_handoff.dart';
import 'package:furnace/features/ai/domain/checker_report.dart';
import 'package:furnace/features/ai/domain/claim.dart';
import 'package:furnace/features/ai/domain/unverified_delivery.dart';
import 'package:furnace/features/ai/domain/verification_pipeline.dart';

/// 验证流水线契约（设计 §7.5）：
/// precheck invalid/unknown 回 solver、不进 Checker；clean 才 handoff；
/// checker 两轮不过 -> unverified 交付 + 教学延伸 + 学习记录；verified 不生成延伸。
void main() {
  const question = 'Q15 斜面与物块，求动摩擦因数与能量范围';
  const answer = '（2）m2/m1<=1 或 7；（3）17/2<=E<=12';
  const runId = 'run-1';
  const traceRef = 'student_solver_traces/run-1.json';
  const traceHash = 'trace-hash-1';
  const steps = <ProcessedStep>[
    ProcessedStep(
      id: 'p1',
      claim: 'm2/m1=7 是一支可行解',
      evidence: '由向心力与静摩擦条件联立',
      sourceStepId: 's1',
      deterministicFlags: <String>['unit_ok'],
    ),
    ProcessedStep(
      id: 'p2',
      claim: '17/2<=E<=12',
      evidence: '端点代入后取交集',
      sourceStepId: 's2',
    ),
  ];

  VerificationPipeline buildPipeline({
    String frozenAnswer = answer,
    List<ProcessedStep> processedSteps = steps,
    String sourceTraceRef = traceRef,
    String sourceTraceHash = traceHash,
    String provenanceRunId = runId,
  }) {
    return VerificationPipeline(
      question: question,
      frozenAnswer: frozenAnswer,
      processedSteps: processedSteps,
      provenanceRunId: provenanceRunId,
      sourceTraceRef: sourceTraceRef,
      sourceTraceHash: sourceTraceHash,
      claims: <Claim>[Claim.given(id: 'c1', statement: 'm2/m1=7')],
      toolEvidence: const <String, Object?>{'unit_check': 'ok'},
      allowedCheckerTools: const <String>['read_question', 'run_python'],
    );
  }

  CheckIssue issue(
    String id, {
    CheckIssueCategory category = CheckIssueCategory.missingCase,
    CheckSeverity severity = CheckSeverity.fatal,
  }) {
    return CheckIssue(
      id: id,
      stepId: 's3',
      category: category,
      severity: severity,
      evidence: '证据-$id',
      violated: '规则-$id',
      minimalFix: '修复-$id',
    );
  }

  CheckReport report({
    required CheckReportVerdict verdict,
    List<CheckIssue> issues = const <CheckIssue>[],
  }) {
    return CheckReport(
      answerVersion: 'a1',
      cotVersion: 'c1',
      verdict: verdict,
      issues: issues,
    );
  }

  CheckReport passReport() => report(verdict: CheckReportVerdict.processPass);

  CheckReport failReport({
    String id = 'i1',
    CheckIssueCategory category = CheckIssueCategory.missingCase,
    CheckSeverity severity = CheckSeverity.fatal,
  }) {
    return report(
      verdict: CheckReportVerdict.processFail,
      issues: <CheckIssue>[issue(id, category: category, severity: severity)],
    );
  }

  CheckReport uncheckableReport() =>
      report(verdict: CheckReportVerdict.uncheckable);

  group('precheck：invalid/unknown 不进 Checker，clean 才 handoff', () {
    test('invalid 回 solver 改：无 handoff、有澄清、record 抛错', () {
      final pipeline = buildPipeline();
      final precheck = PrecheckResult.invalid(
        reason: '答案缺单位',
        questions: const <String>['最终量的单位是什么？'],
        affectedSteps: const <String>['s2'],
      );

      final result = pipeline.screen(precheck);

      expect(result.status, VerificationPipelineStatus.solverRevisionRequired);
      expect(result.handoff, isNull);
      expect(result.clarification, isNotNull);
      expect(result.clarification!.reason, '答案缺单位');
      expect(result.clarification!.questions, isNotEmpty);
      expect(result.delivery, isNull);
      expect(result.deliveryStatus, isNull);
      expect(result.canAcceptCheckerReport, isFalse);
      expect(
        () => pipeline.record(previous: result, report: passReport()),
        throwsStateError,
      );
    });

    test('unknown 回 solver 弄清：无 handoff、有澄清、record 抛错', () {
      final pipeline = buildPipeline();
      final precheck = PrecheckResult.unknown(
        reason: 'E 的下界无法确定',
        questions: const <String>['端点能不能取到？'],
      );

      final result = pipeline.screen(precheck);

      expect(
        result.status,
        VerificationPipelineStatus.solverClarificationRequired,
      );
      expect(result.handoff, isNull);
      expect(result.clarification!.reason, 'E 的下界无法确定');
      expect(result.delivery, isNull);
      expect(
        () => pipeline.record(previous: result, report: passReport()),
        throwsStateError,
      );
    });

    test('解析失败 -> unknown 澄清，不生成 handoff', () {
      final pipeline = buildPipeline();
      final result = pipeline.screen(
        PrecheckResult.parseFailure(detail: 'trace 第 3 行不是可识别结构'),
      );

      expect(
        result.status,
        VerificationPipelineStatus.solverClarificationRequired,
      );
      expect(result.handoff, isNull);
      expect(result.clarification!.reason, contains('无法解析'));
      expect(
        () => pipeline.record(previous: result, report: passReport()),
        throwsStateError,
      );
    });

    test('clean 才构造 handoff：来源/版本/hash 齐全且可复核', () {
      final pipeline = buildPipeline();
      final result = pipeline.screen(PrecheckResult.clean());

      expect(result.status, VerificationPipelineStatus.awaitingChecker);
      expect(result.clarification, isNull);
      expect(result.handoff, isNotNull);
      expect(result.canAcceptCheckerReport, isTrue);
      expect(result.checkerRounds, 0);
      expect(result.delivery, isNull);
      expect(result.deliveryStatus, isNull);

      final handoff = result.handoff!;
      expect(handoff.schemaVersion, checkerHandoffSchemaVersion);
      expect(handoff.sourceRunId, runId);
      expect(handoff.sourceTraceRef, traceRef);
      expect(handoff.sourceTraceHash, traceHash);
      expect(handoff.frozenAnswer, answer);
      expect(
          handoff.allowedCheckerTools, <String>['read_question', 'run_python']);
      expect(handoff.verifyContentHash(), isTrue);
    });
  });

  group('checker 两轮', () {
    test('verified：pass 即终止，不生成教学延伸', () {
      final pipeline = buildPipeline();
      final handoffResult = pipeline.screen(PrecheckResult.clean());
      final result = pipeline.record(
        previous: handoffResult,
        report: passReport(),
      );

      expect(result.status, VerificationPipelineStatus.verified);
      expect(result.isTerminal, isTrue);
      expect(result.delivery, isNull);
      expect(result.deliveryStatus, DeliveryStatus.verified);
      expect(result.checkerRounds, 1);
      expect(result.checkerReport!.verdict, CheckReportVerdict.processPass);
    });

    test('第 1 轮 fail：只回 solver 局部重推过程，不交付', () {
      final pipeline = buildPipeline();
      final result = pipeline.record(
        previous: pipeline.screen(PrecheckResult.clean()),
        report: failReport(),
      );

      expect(
        result.status,
        VerificationPipelineStatus.solverProcessRepairRequired,
      );
      expect(result.delivery, isNull);
      expect(result.canAcceptCheckerReport, isTrue);
      expect(result.checkerRounds, 1);
      expect(result.checkerReport!.issues.single.id, 'i1');
    });

    test('两轮 fail：unverified 交付 + 教学延伸 + 学习记录', () {
      final pipeline = buildPipeline();
      final first = pipeline.record(
        previous: pipeline.screen(PrecheckResult.clean()),
        report: failReport(id: 'i1'),
      );
      final second = pipeline.record(
        previous: first,
        report: failReport(
          id: 'i2',
          category: CheckIssueCategory.unit,
          severity: CheckSeverity.major,
        ),
      );

      expect(second.status, VerificationPipelineStatus.unverified);
      expect(second.isTerminal, isTrue);
      expect(second.checkerRounds, 2);
      expect(second.deliveryStatus, DeliveryStatus.unverified);

      final delivery = second.delivery;
      expect(delivery, isNotNull);
      expect(delivery!.status, DeliveryStatus.unverified);
      expect(delivery.answer, answer);
      expect(delivery.isVerified, isFalse);
      expect(delivery.reason, contains('2 轮'));
      expect(delivery.reason, contains('修复-i2'));

      // 教学延伸来自失败轮次的结构化 issue，不是空壳。
      expect(delivery.extension.title, isNotEmpty);
      expect(delivery.extension.hiddenIssue, contains('证据-i2'));
      expect(delivery.extension.hiddenIssue, contains('规则-i2'));
      expect(delivery.extension.userPrompts, isNotEmpty);
      expect(delivery.extension.expectedReasoning, isNotEmpty);

      // 学习记录：cluster / 类别 / 证据 / 架构提示 / 来源 run。
      final record = delivery.learningRecord;
      expect(record.cluster, 'student_exam');
      expect(record.issueCategory, CheckIssueCategory.unit);
      expect(record.evidence, contains('证据-i2'));
      expect(record.architectureHint, isNotEmpty);
      expect(record.provenanceRunId, runId);
    });

    test('第 2 轮 pass 仍是 verified，不生成延伸', () {
      final pipeline = buildPipeline();
      final first = pipeline.record(
        previous: pipeline.screen(PrecheckResult.clean()),
        report: failReport(),
      );
      final second = pipeline.record(
        previous: first,
        report: passReport(),
      );

      expect(second.status, VerificationPipelineStatus.verified);
      expect(second.checkerRounds, 2);
      expect(second.delivery, isNull);
      expect(second.deliveryStatus, DeliveryStatus.verified);
    });

    test('rehandoff：repair 后重建过程，但冻结答案不变', () {
      final pipeline = buildPipeline();
      final handoffResult = pipeline.screen(PrecheckResult.clean());
      final originalDigest = handoffResult.handoff!.frozenAnswerDigest;
      final firstFail = pipeline.record(
        previous: handoffResult,
        report: failReport(),
      );

      final revised = pipeline.rehandoff(
        previous: firstFail,
        processedSteps: const <ProcessedStep>[
          ProcessedStep(
            id: 'p1r',
            claim: '补上 m2/m1=7 分支',
            evidence: '重推静摩擦条件',
            sourceStepId: 's1r',
          ),
        ],
        sourceTraceRef: 'student_solver_traces/run-1-repair.json',
        sourceTraceHash: 'trace-hash-2',
      );

      expect(revised.status, VerificationPipelineStatus.awaitingChecker);
      expect(revised.checkerRounds, 1, reason: '第 1 轮报告要保留');
      expect(revised.handoff!.frozenAnswer, answer);
      expect(revised.handoff!.frozenAnswerDigest, originalDigest);
      expect(revised.handoff!.processedSteps.single.id, 'p1r');
      expect(revised.handoff!.sourceTraceHash, 'trace-hash-2');
      expect(revised.handoff!.verifyContentHash(), isTrue);

      final secondFail = pipeline.record(
        previous: revised,
        report: failReport(id: 'i2'),
      );
      expect(secondFail.status, VerificationPipelineStatus.unverified);
      expect(secondFail.checkerRounds, 2);
      expect(secondFail.delivery!.answer, answer);
    });

    test('uncheckable：无法判断即转人工交付', () {
      final pipeline = buildPipeline();
      final result = pipeline.record(
        previous: pipeline.screen(PrecheckResult.clean()),
        report: uncheckableReport(),
      );

      expect(result.status, VerificationPipelineStatus.humanRequired);
      expect(result.delivery, isNotNull);
      expect(result.delivery!.status, DeliveryStatus.humanRequired);
      expect(result.deliveryStatus, DeliveryStatus.humanRequired);
      expect(result.delivery!.extension.userPrompts, isNotEmpty);
    });

    test('fail 但没有可关闭的阻塞 issue：不猜，转人工', () {
      final pipeline = buildPipeline();
      final result = pipeline.record(
        previous: pipeline.screen(PrecheckResult.clean()),
        report: failReport(severity: CheckSeverity.minor),
      );

      expect(result.status, VerificationPipelineStatus.humanRequired);
      expect(result.delivery!.status, DeliveryStatus.humanRequired);
    });

    test('终止后不能再接报告或重建 handoff', () {
      final pipeline = buildPipeline();
      final verified = pipeline.record(
        previous: pipeline.screen(PrecheckResult.clean()),
        report: passReport(),
      );
      expect(
        () => pipeline.record(previous: verified, report: failReport()),
        throwsStateError,
      );
      expect(
        () => pipeline.rehandoff(
          previous: verified,
          processedSteps: steps,
          sourceTraceRef: traceRef,
          sourceTraceHash: traceHash,
        ),
        throwsStateError,
      );

      final unverified = pipeline.record(
        previous: pipeline.record(
          previous: pipeline.screen(PrecheckResult.clean()),
          report: failReport(id: 'a'),
        ),
        report: failReport(id: 'b'),
      );
      expect(unverified.status, VerificationPipelineStatus.unverified);
      expect(
        () => pipeline.record(previous: unverified, report: passReport()),
        throwsStateError,
      );
    });

    test('没有 checker 报告时不能重建 handoff', () {
      final pipeline = buildPipeline();
      final handoffResult = pipeline.screen(PrecheckResult.clean());
      expect(
        () => pipeline.rehandoff(
          previous: handoffResult,
          processedSteps: steps,
          sourceTraceRef: traceRef,
          sourceTraceHash: traceHash,
        ),
        throwsStateError,
      );
    });

    test('没有 handoff（invalid/unknown 路径）不能重建 handoff', () {
      final pipeline = buildPipeline();
      final result = pipeline.screen(
        PrecheckResult.invalid(
          reason: '缺单位',
          questions: const <String>['单位是什么？'],
        ),
      );
      expect(
        () => pipeline.rehandoff(
          previous: result,
          processedSteps: steps,
          sourceTraceRef: traceRef,
          sourceTraceHash: traceHash,
        ),
        throwsStateError,
      );
    });
  });

  test('Checker 最多两轮', () {
    expect(VerificationPipeline.maxCheckerRounds, 2);
  });

  test('流水线必须知道来源 run 与 trace', () {
    expect(
      () => buildPipeline(provenanceRunId: ' '),
      throwsArgumentError,
    );
    expect(
      () => buildPipeline(sourceTraceRef: ''),
      throwsArgumentError,
    );
    expect(
      () => buildPipeline(sourceTraceHash: ' '),
      throwsArgumentError,
    );
  });
}
