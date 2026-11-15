import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/checker_handoff.dart';
import 'package:furnace/features/ai/domain/claim.dart';

/// CheckerHandoff / Precheck 交接契约（设计 §7.5 / §7.6）。
///
/// 锁住三件事：
///  1. 只有 clean 能构造 CheckerHandoff，invalid/unknown 结构上被拒绝；
///  2. handoff 必须由确定性程序从 run/trace/claim 构造，带
///     sourceRunId/sourceTraceRef/sourceTraceHash/schemaVersion/contentHash，
///     内容不可变、hash 可复核；
///  3. 解析失败只能走 PrecheckResult.parseFailure（unknown）回 solver。
void main() {
  const runId = 'run-1';
  const traceRef = 'student_solver_traces/run-1.json';
  const traceHash = 'trace-hash-1';
  const question = 'Q15 斜面与物块，求动摩擦因数与能量范围';
  const answer = '（2）m2/m1<=1 或 7；（3）17/2<=E<=12';
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

  List<Claim> buildClaims() => <Claim>[
        // 固定 createdAtMs：确定性测试里 claim 本身也必须是确定输入。
        Claim.given(id: 'c1', statement: 'm2/m1=7', createdAtMs: 0),
      ];

  CheckerHandoff buildHandoff({
    PrecheckResult? precheck,
    String frozenAnswer = answer,
    List<ProcessedStep> processedSteps = steps,
  }) {
    return CheckerHandoff.fromPrecheck(
      precheck: precheck ?? PrecheckResult.clean(),
      sourceRunId: runId,
      sourceTraceRef: traceRef,
      sourceTraceHash: traceHash,
      question: question,
      frozenAnswer: frozenAnswer,
      processedSteps: processedSteps,
      claims: buildClaims(),
      toolEvidence: const <String, Object?>{'unit_check': 'ok'},
      allowedCheckerTools: const <String>['read_question', 'run_python'],
    );
  }

  group('PrecheckOutcome', () {
    test('只有 clean 允许 handoff；unknown/缺失值不能冒充 clean', () {
      expect(PrecheckOutcome.clean.allowsCheckerHandoff, isTrue);
      expect(PrecheckOutcome.clean.returnsToSolver, isFalse);
      expect(PrecheckOutcome.invalid.allowsCheckerHandoff, isFalse);
      expect(PrecheckOutcome.unknown.allowsCheckerHandoff, isFalse);
      expect(PrecheckOutcome.invalid.returnsToSolver, isTrue);
      expect(PrecheckOutcome.unknown.returnsToSolver, isTrue);

      expect(PrecheckOutcome.fromId('bogus'), PrecheckOutcome.unknown);
      expect(PrecheckOutcome.fromId(null), PrecheckOutcome.unknown);
      expect(PrecheckOutcome.fromId('clean'), PrecheckOutcome.clean);
      expect(PrecheckOutcome.fromId('invalid'), PrecheckOutcome.invalid);
    });

    test('clean 没有澄清请求；invalid/unknown 必须带具体原因与问题', () {
      final clean = PrecheckResult.clean();
      expect(clean.clarification, isNull);
      expect(clean.allowsCheckerHandoff, isTrue);

      final invalid = PrecheckResult.invalid(
        reason: '答案缺单位',
        questions: const <String>['最终量的单位是什么？'],
        affectedSteps: const <String>['s2'],
      );
      expect(invalid.clarification, isNotNull);
      expect(invalid.clarification!.reason, '答案缺单位');
      expect(invalid.clarification!.questions, hasLength(1));
      expect(invalid.clarification!.affectedSteps, <String>['s2']);
      expect(invalid.allowsCheckerHandoff, isFalse);

      final unknown = PrecheckResult.unknown(
        reason: 'E 的下界无法确定',
        questions: const <String>['端点能不能取到？'],
      );
      expect(unknown.clarification, isNotNull);
      expect(unknown.allowsCheckerHandoff, isFalse);

      expect(
        () => PrecheckResult.invalid(
            reason: '  ', questions: const <String>['x']),
        throwsArgumentError,
      );
      expect(
        () => PrecheckResult.unknown(
          reason: '不知道',
          questions: const <String>[],
        ),
        throwsArgumentError,
      );
    });

    test('解析失败 -> unknown 澄清，绝不清洁', () {
      final parseFailure = PrecheckResult.parseFailure(
        detail: '第 3 行不是 JSON / 没有可识别 claim',
      );
      expect(parseFailure.outcome, PrecheckOutcome.unknown);
      expect(parseFailure.allowsCheckerHandoff, isFalse);
      expect(parseFailure.clarification, isNotNull);
      expect(parseFailure.clarification!.reason, contains('无法解析'));
      expect(parseFailure.findings.single.code, 'trace_parse_failed');
      expect(parseFailure.clarification!.questions, isNotEmpty);
    });
  });

  group('Constructor 守卫：非 clean 不能构造 handoff', () {
    test('invalid 直接抛 StateError', () {
      expect(
        () => buildHandoff(
          precheck: PrecheckResult.invalid(
            reason: '缺单位',
            questions: const <String>['单位是什么？'],
          ),
        ),
        throwsStateError,
      );
    });

    test('unknown 直接抛 StateError', () {
      expect(
        () => buildHandoff(
          precheck: PrecheckResult.unknown(
            reason: '无法确定分支',
            questions: const <String>['E 的上界能否取到？'],
          ),
        ),
        throwsStateError,
      );
    });

    test('解析失败（unknown）不生成 handoff', () {
      expect(
        () => buildHandoff(
          precheck: PrecheckResult.parseFailure(detail: 'trace 无法解析'),
        ),
        throwsStateError,
      );
    });

    test('clean 但没有冻结答案 / 没有来源，也不生成 handoff', () {
      expect(
        () => buildHandoff(frozenAnswer: '   '),
        throwsStateError,
      );
      expect(
        () => CheckerHandoff.fromPrecheck(
          precheck: PrecheckResult.clean(),
          sourceRunId: '',
          sourceTraceRef: traceRef,
          sourceTraceHash: traceHash,
          question: question,
          frozenAnswer: answer,
          processedSteps: steps,
        ),
        throwsStateError,
      );
      expect(
        () => CheckerHandoff.fromPrecheck(
          precheck: PrecheckResult.clean(),
          sourceRunId: runId,
          sourceTraceRef: traceRef,
          sourceTraceHash: '',
          question: question,
          frozenAnswer: answer,
          processedSteps: steps,
        ),
        throwsStateError,
      );
    });
  });

  group('确定性交接数据', () {
    test('clean 才生成 handoff，字段来自 run/trace/claim 且可追溯', () {
      final handoff = buildHandoff();

      expect(handoff.schemaVersion, checkerHandoffSchemaVersion);
      expect(handoff.sourceRunId, runId);
      expect(handoff.sourceTraceRef, traceRef);
      expect(handoff.sourceTraceHash, traceHash);
      expect(handoff.question, question);
      expect(handoff.frozenAnswer, answer);
      expect(handoff.processedSteps, hasLength(2));
      expect(handoff.claims.single.id, 'c1');
      expect(
          handoff.allowedCheckerTools, <String>['read_question', 'run_python']);
      expect(handoff.toolEvidence['unit_check'], 'ok');
      expect(handoff.frozenAnswerDigest, stableClaimHash(answer));
      expect(handoff.contentHash, isNotEmpty);
      expect(handoff.verifyContentHash(), isTrue);

      final json = handoff.toJson();
      expect(json['schema_version'], checkerHandoffSchemaVersion);
      expect(json['source_run_id'], runId);
      expect(json['source_trace_ref'], traceRef);
      expect(json['source_trace_hash'], traceHash);
      expect(json['content_hash'], handoff.contentHash);
      expect(json['frozen_answer_digest'], handoff.frozenAnswerDigest);
      // handoff 没有 solver 的原始 CoT / reasoning 字段。
      expect(json.containsKey('reasoning'), isFalse);
      expect(json.containsKey('raw_cot'), isFalse);
    });

    test('clean 预检的发现带进 handoff（供 Checker 复核）', () {
      final handoff = buildHandoff(
        precheck: PrecheckResult.clean(
          findings: const <PrecheckFinding>[
            PrecheckFinding(code: 'unit_ok', detail: '单位一致', stepId: 's2'),
          ],
        ),
      );
      expect(handoff.precheckFindings.single.code, 'unit_ok');
    });

    test('同一输入得到同一 contentHash；输入变化 hash 变化', () {
      final first = buildHandoff();
      final second = buildHandoff();
      expect(second.contentHash, first.contentHash);

      final otherAnswer = buildHandoff(frozenAnswer: '（3）17/2<=E');
      expect(otherAnswer.contentHash, isNot(first.contentHash));

      final otherSteps = buildHandoff(
        processedSteps: const <ProcessedStep>[
          ProcessedStep(id: 'p1', claim: '只有一支', evidence: '漏了 m2/m1=7'),
        ],
      );
      expect(otherSteps.contentHash, isNot(first.contentHash));
    });

    test('handoff 内容不可变（调用方不能事后改写交接数据）', () {
      final handoff = buildHandoff();
      expect(
        () => handoff.processedSteps.add(
          const ProcessedStep(id: 'x', claim: 'x', evidence: 'x'),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => handoff.allowedCheckerTools.add('write_file'),
        throwsUnsupportedError,
      );
    });

    test('withProcess 只换过程，不换冻结答案', () {
      final handoff = buildHandoff();
      final revised = handoff.withProcess(
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

      expect(revised.frozenAnswer, handoff.frozenAnswer);
      expect(revised.frozenAnswerDigest, handoff.frozenAnswerDigest);
      expect(revised.processedSteps.single.id, 'p1r');
      expect(revised.sourceTraceRef, contains('repair'));
      expect(revised.sourceTraceHash, 'trace-hash-2');
      expect(revised.contentHash, isNot(handoff.contentHash));
      expect(revised.verifyContentHash(), isTrue);
    });
  });
}
