import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/checker_handoff.dart';
import 'package:furnace/features/ai/domain/checkpoint.dart';
import 'package:furnace/features/ai/domain/claim.dart';
import 'package:furnace/features/ai/domain/claim_extractor.dart';
import 'package:furnace/features/ai/domain/deterministic_preprocessor.dart';
import 'package:furnace/features/ai/domain/handoff_builder.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/normalizer.dart';
import 'package:furnace/features/ai/domain/trace_parser.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';

/// 确定性预处理管线（task-18）：TraceParser → Normalizer → ClaimExtractor →
/// DeterministicPrecheck → HandoffBuilder，全部纯规则、零模型调用。
void main() {
  const question = 'Q15 斜面与物块。（1）求 F；（2）求 m_2/m_1 的所有可能值；'
      '（3）求 E 的范围（单位 J）';
  const cleanReasoning = '设物块质量 m_1，斜面倾角 \\theta，重力加速度 g。\n\n'
      '由向心力公式得 F=m_1 g \\tan\\theta。\n\n'
      '当 m_2/m_1=7 时，静摩擦达到临界。\n\n'
      '所以 m_2/m_1\\leq 1 或 7。\n\n'
      '由动能定理得 17/2\\leq E\\leq 12，单位 J。';
  const cleanProcess = '整理：E 的范围用区间表示，端点 17/2 与 12 都要保留。';
  const cleanAnswer = '（1）F=m_1 g \\tan\\theta；'
      '（2）m_2/m_1\\leq 1 或 7；'
      '（3）17/2\\leq E\\leq 12 J';

  DeterministicPreprocessResult runPipeline({
    String questionText = question,
    String rawReasoning = cleanReasoning,
    String processText = cleanProcess,
    String answer = cleanAnswer,
    List<String> branchCases = const <String>[],
    CheckpointSet? checkpoints,
    int tokenBudget = 4000,
    List<Claim> structuredClaims = const <Claim>[],
  }) {
    return DeterministicPreprocessor(
      checkpoints: checkpoints,
      branchCases: branchCases,
      tokenBudget: tokenBudget,
      allowedCheckerTools: const <String>['read_question', 'run_python'],
    ).run(
      runId: 'run-1',
      sourceTraceRef: 'student_solver_traces/run-1.json',
      question: questionText,
      rawReasoning: rawReasoning,
      processText: processText,
      frozenAnswer: answer,
      structuredClaims: structuredClaims,
    );
  }

  List<String> findingCodes(PrecheckResult precheck) =>
      <String>[for (final finding in precheck.findings) finding.code];

  group('TraceParser（纯规则切分）', () {
    test('空行/编号/公式块切分，offset 与 sourceHash 可追溯', () {
      final trace = const TraceParser().parse(
        rawReasoning: cleanReasoning,
        processText: cleanProcess,
      );
      expect(trace.succeeded, isTrue);
      // 5 段 reasoning + 1 段 process = 6 步。
      expect(trace.steps, hasLength(6));
      for (final step in trace.steps) {
        expect(
          trace.source.substring(step.sourceStart, step.sourceEnd),
          step.rawText,
          reason: 'sourceStart/sourceEnd 必须精确包住 rawText',
        );
        expect(step.rawText, isNot(startsWith('\n')));
        expect(step.rawText, isNot(endsWith('\n')));
        expect(step.sourceHash, stableClaimHash(step.rawText));
        expect(step.sourceStart, lessThan(step.sourceEnd));
      }
      for (var i = 1; i < trace.steps.length; i++) {
        expect(
          trace.steps[i].sourceStart,
          greaterThan(trace.steps[i - 1].sourceEnd - 1),
        );
      }
      expect(trace.steps.first.id, 'trace-step-1');
      expect(trace.steps.last.id, 'trace-step-6');
      expect(trace.source, contains('整理：E 的范围'));
    });

    test('编号与步骤标记也切分', () {
      final numbered = const TraceParser()
          .parse(rawReasoning: '1. 甲\n2. 乙', processText: '');
      expect(numbered.steps, hasLength(2));
      expect(numbered.steps.first.rawText, '1. 甲');
      expect(numbered.steps.last.rawText, '2. 乙');

      final labelled = const TraceParser()
          .parse(rawReasoning: '步骤1：甲\n步骤2：乙', processText: '');
      expect(labelled.steps, hasLength(2));
      expect(labelled.steps.first.rawText, '步骤1：甲');
    });

    test('公式块内部的空行不切分', () {
      final trace = const TraceParser().parse(
        rawReasoning: '甲。\n\n\$\$\na=b\n\nc=d\n\$\$\n\n乙。',
        processText: '',
      );
      expect(trace.succeeded, isTrue);
      expect(trace.steps, hasLength(3));
      expect(trace.steps[1].rawText, contains('a=b'));
      expect(trace.steps[1].rawText, contains('c=d'));
    });

    test('解析失败：空 trace 与未闭合公式块（不猜测、不补写）', () {
      final empty = const TraceParser().parse(
        rawReasoning: '   ',
        processText: '\n',
      );
      expect(empty.succeeded, isFalse);
      expect(empty.steps, isEmpty);
      expect(empty.failure, isNotEmpty);

      final unclosed = const TraceParser().parse(
        rawReasoning: '甲。\n\n\$\$ a=b',
        processText: '',
      );
      expect(unclosed.succeeded, isFalse);
      expect(unclosed.failure, contains('未闭合'));
    });

    test('切分稳定：重复 parse 得到同样的偏移与 hash', () {
      final first = const TraceParser().parse(
        rawReasoning: cleanReasoning,
        processText: cleanProcess,
      );
      final second = const TraceParser().parse(
        rawReasoning: cleanReasoning,
        processText: cleanProcess,
      );
      expect(second.sourceHash, first.sourceHash);
      expect(second.steps.length, first.steps.length);
      for (var i = 0; i < first.steps.length; i++) {
        expect(second.steps[i].sourceStart, first.steps[i].sourceStart);
        expect(second.steps[i].sourceEnd, first.steps[i].sourceEnd);
        expect(second.steps[i].sourceHash, first.steps[i].sourceHash);
      }
    });
  });

  group('Normalizer（纯规则、幂等、保留 raw）', () {
    test('LaTeX / Unicode / 单位规范化', () {
      const normalizer = Normalizer();
      expect(normalizer.normalize(r'\frac{a}{b}\leq \pi'), '(a)/(b)<=pi');
      expect(normalizer.normalize('１２３，≤，ｍ／ｓ²'), '123,<=,m/s^2');
      expect(normalizer.normalize(r'$\sqrt{x}\geq 0$'), 'sqrt(x)>=0');
      expect(normalizer.normalize('m/s²'), 'm/s^2');
    });

    test('normalize 幂等', () {
      const normalizer = Normalizer();
      const samples = <String>[
        r'$\frac{a}{b}\leq 1$',
        '若 ｍ₁≤７，所以 E≥１２',
        'F=10N，E=17/2 J',
        r'm_2/m_1\leq 1',
      ];
      for (final sample in samples) {
        final once = normalizer.normalize(sample);
        expect(normalizer.normalize(once), once, reason: '样本：$sample');
      }
    });

    test('raw 不变，只多一份 normalized', () {
      final trace = const TraceParser()
          .parse(rawReasoning: cleanReasoning, processText: '');
      final step = const Normalizer().normalizeStep(trace.steps.first);
      expect(step.traceStep.rawText, trace.steps.first.rawText);
      expect(step.traceStep.sourceHash, trace.steps.first.sourceHash);
      expect(step.normalized, isNot(equals(step.traceStep.rawText)));
      expect(step.normalized, contains('m_1'));
    });

    test('单位抽取带边界：变量不是单位', () {
      expect(Normalizer.unitsIn('F=10N'), contains('N'));
      expect(
          Normalizer.unitsIn('kg*m/s^2'), containsAll(<String>['kg', 'm/s^2']));
      expect(Normalizer.unitsIn('m_1g'), isEmpty);
      expect(Normalizer.unitsIn('17/2<=E<=12J'), contains('J'));
    });
  });

  group('ClaimExtractor（语法模式，不编造）', () {
    NormalizedStep norm(String raw) {
      return NormalizedStep(
        traceStep: TraceStep(
          id: 'trace-step-1',
          sourceStart: 0,
          sourceEnd: raw.length,
          sourceHash: stableClaimHash(raw),
          rawText: raw,
        ),
        normalized: const Normalizer().normalize(raw),
      );
    }

    test('六类 claim 与分支关键词', () {
      const raw = 'm_1>0。m_2/m_1=7。若 m_2 取 7 则临界。'
          '所以结论成立。E 是能量。①②两种情形都要讨论。';
      final claims = const ClaimExtractor().extract(norm(raw));

      expect(
        <ExtractedClaimKind>[for (final claim in claims) claim.kind],
        <ExtractedClaimKind>[
          ExtractedClaimKind.inequality,
          ExtractedClaimKind.equation,
          ExtractedClaimKind.condition,
          ExtractedClaimKind.result,
          ExtractedClaimKind.unclassified,
          ExtractedClaimKind.decision,
        ],
      );
      expect(claims.first.variables, contains('m_1'));
      expect(claims[1].variables, containsAll(<String>['m_2', 'm_1']));
      expect(claims[5].branchKeywords, containsAll(<String>['①', '情形']));
      expect(claims.first.evidenceRef, 'trace:trace-step-1#s0');
      expect(claims.first.sourceHash, stableClaimHash(claims.first.normalized));
    });

    test('单位与实体不发明：只认文本/词表', () {
      final unitClaims = const ClaimExtractor().extract(norm('F=10N。'));
      expect(unitClaims.single.kind, ExtractedClaimKind.equation);
      expect(unitClaims.single.units, contains('N'));

      final entityClaims = const ClaimExtractor().extract(
        norm('物块质量 m_1>0。'),
        entityVocabulary: const <String>['物块', '不存在的东西'],
      );
      expect(entityClaims.single.entities, <String>['物块']);

      // 完全不像 claim 的句子直接跳过，不强行生成。
      expect(const ClaimExtractor().extract(norm('先整理思路。')), isEmpty);
    });
  });

  group('DeterministicPrecheck（invalid/unknown/clean）', () {
    test('clean：覆盖齐全才 clean，且能构造 handoff', () {
      final result = runPipeline(
        branchCases: const <String>['m_2/m_1\\leq 1', 'm_2/m_1=7'],
      );
      expect(result.precheck.outcome, PrecheckOutcome.clean);
      expect(result.precheck.findings, isEmpty);
      expect(result.handoff, isNotNull);
    });

    test('invalid：缺小问答案 -> 回 solver，不生成 handoff', () {
      final result = runPipeline(
        answer: '（2）m_2/m_1\\leq 1 或 7；'
            '（3）17/2\\leq E\\leq 12 J',
      );
      expect(result.precheck.outcome, PrecheckOutcome.invalid);
      expect(findingCodes(result.precheck),
          contains('answer_missing_sub_question'));
      expect(result.handoff, isNull);
      expect(result.build.handoff, isNull);
      expect(result.precheck.clarification, isNotNull);
      expect(result.precheck.clarification!.questions, isNotEmpty);
    });

    test('invalid：答案缺单位 -> 回 solver', () {
      final result = runPipeline(
        answer: '（1）F=m_1 g \\tan\\theta；'
            '（2）m_2/m_1\\leq 1 或 7；'
            '（3）17/2\\leq E\\leq 12',
      );
      expect(result.precheck.outcome, PrecheckOutcome.invalid);
      expect(findingCodes(result.precheck), contains('answer_missing_unit'));
      expect(result.handoff, isNull);
    });

    test('invalid：答案丢掉区间/端点 -> 回 solver', () {
      final result = runPipeline(
        answer: '（1）F=m_1 g \\tan\\theta；'
            '（2）m_2/m_1=1 或 7；'
            '（3）E=12 J',
      );
      expect(result.precheck.outcome, PrecheckOutcome.invalid);
      expect(
          findingCodes(result.precheck), contains('answer_missing_inequality'));
      expect(result.handoff, isNull);
    });

    test('invalid：缺分支（有 case table 时）-> 回 solver', () {
      final result = runPipeline(
        rawReasoning: '设物块质量 m_1。\n\n'
            '由向心力公式得 F=m_1 g \\tan\\theta。\n\n'
            '所以 m_2/m_1\\leq 1。\n\n'
            '由动能定理得 17/2\\leq E\\leq 12，单位 J。',
        answer: '（1）F=m_1 g \\tan\\theta；'
            '（2）m_2/m_1\\leq 1；'
            '（3）17/2\\leq E\\leq 12 J',
        branchCases: const <String>['m_2/m_1\\leq 1', 'm_2/m_1=7'],
      );
      expect(result.precheck.outcome, PrecheckOutcome.invalid);
      expect(findingCodes(result.precheck), contains('branch_missing'));
      expect(result.handoff, isNull);
    });

    test('invalid：重复步骤/循环 -> 回 solver', () {
      final result = runPipeline(
        rawReasoning: '所以 m_2/m_1\\leq 1。\n\n'
            '所以 m_2/m_1\\leq 1。\n\n'
            '由动能定理得 17/2\\leq E\\leq 12，单位 J。',
        answer: '（1）F=1；（2）m_2/m_1\\leq 1；（3）17/2\\leq E\\leq 12 J',
      );
      expect(result.precheck.outcome, PrecheckOutcome.invalid);
      expect(findingCodes(result.precheck), contains('repeated_step'));
      expect(result.handoff, isNull);
    });

    test('invalid：required 锚点未覆盖 -> 回 solver', () {
      final result = runPipeline(
        checkpoints: const CheckpointSet(
          checkpoints: <Checkpoint>[
            Checkpoint(
              id: 'anchor-e',
              label: 'E 的区间',
              kind: CheckpointKind.quantity,
              scope: CheckpointScope.required,
              constraints: <CheckpointConstraint>[
                CheckpointConstraint(
                  kind: CheckpointConstraintKind.interval,
                  acceptable: <String>['99\\leq E\\leq 100'],
                ),
              ],
            ),
          ],
        ),
      );
      expect(result.precheck.outcome, PrecheckOutcome.invalid);
      final finding = result.precheck.findings
          .firstWhere((item) => item.code == 'anchor_missing');
      expect(finding.evidenceRef, 'anchor:anchor-e');
      expect(result.handoff, isNull);
    });

    test('unknown：抽不到 claim -> 回 solver 弄清，不生成 handoff', () {
      final result = runPipeline(
        rawReasoning: '先读题。\n\n再想想。',
        processText: '',
        answer: '（1）1；（2）2；（3）3',
      );
      expect(result.precheck.outcome, PrecheckOutcome.unknown);
      expect(findingCodes(result.precheck), contains('no_claims'));
      expect(result.handoff, isNull);
    });

    test('unknown：单位对不上 -> 回 solver 弄清', () {
      final result = runPipeline(
        answer: '（1）F=10N；（2）m_2/m_1\\leq 1 或 7；'
            '（3）17/2\\leq E\\leq 12 N',
      );
      expect(result.precheck.outcome, PrecheckOutcome.unknown);
      expect(findingCodes(result.precheck), contains('unit_mismatch'));
      expect(result.handoff, isNull);
    });

    test('unknown：解析失败 -> SolverClarificationRequest，不生成 handoff', () {
      final result =
          runPipeline(rawReasoning: '', processText: '', answer: 'x');
      expect(result.precheck.outcome, PrecheckOutcome.unknown);
      expect(result.precheck.clarification, isNotNull);
      expect(result.precheck.clarification!.reason, contains('无法解析'));
      expect(result.handoff, isNull);
      expect(result.build.handoff, isNull);
    });
  });

  group('HandoffBuilder（clean 才构造；预算截断保留 refs）', () {
    NormalizedStep makeStep(int index, String text) {
      return NormalizedStep(
        traceStep: TraceStep(
          id: 'trace-step-$index',
          sourceStart: 0,
          sourceEnd: text.length,
          sourceHash: stableClaimHash(text),
          rawText: text,
        ),
        normalized: const Normalizer().normalize(text),
      );
    }

    HandoffBuildResult buildWith({
      required PrecheckResult precheck,
      required List<NormalizedStep> steps,
      int tokenBudget = 4000,
      List<String> mustKeep = const <String>[],
    }) {
      return HandoffBuilder(
        tokenBudget: tokenBudget,
        allowedCheckerTools: const <String>['read_question', 'run_python'],
      ).build(
        runId: 'run-1',
        sourceTraceRef: 'student_solver_traces/run-1.json',
        sourceTraceHash: 'trace-hash-1',
        question: question,
        frozenAnswer: cleanAnswer,
        precheck: precheck,
        normalizedSteps: steps,
        claims: const <ExtractedClaim>[],
        toolEvidenceRefs: const <String>['tool:unit_check'],
        mustKeepStepIds: mustKeep,
      );
    }

    test('invalid/unknown 不生成 handoff', () {
      final invalid = PrecheckResult.invalid(
        reason: '缺单位',
        questions: const <String>['单位是什么？'],
      );
      final result = buildWith(precheck: invalid, steps: <NormalizedStep>[]);
      expect(result.handoff, isNull);
      expect(result.processedSteps, isEmpty);
    });

    test('超预算做确定性截断：保留首尾/锚点步骤与全部 refs，不做 LLM 摘要', () {
      final steps = <NormalizedStep>[
        for (var index = 1; index <= 12; index++)
          makeStep(
            index,
            index == 3
                ? 'MIDDLE-MARKER-ALPHA${'甲' * 120}'
                : '步骤$index内容${'乙' * 120}',
          ),
      ];
      final result = buildWith(
        precheck: PrecheckResult.clean(),
        steps: steps,
        tokenBudget: 700,
        mustKeep: const <String>['trace-step-6'],
      );

      expect(result.handoff, isNotNull);
      expect(result.truncated, isTrue);
      expect(result.droppedStepIds, isNotEmpty);
      final keptIds = <String>[
        for (final step in result.processedSteps) step.id,
      ];
      expect(keptIds, contains('trace-step-1'));
      expect(keptIds, contains('trace-step-12'));
      expect(keptIds, contains('trace-step-6'), reason: '锚点步骤必须保留');
      expect(keptIds, isNot(contains('trace-step-3')));
      expect(result.droppedStepIds, isNot(contains('trace-step-6')));

      for (final step in result.processedSteps) {
        expect(step.evidenceRefs, isNotEmpty);
        expect(step.evidenceRefs.first, 'trace:${step.id}');
        expect(step.sourceHash, isNotNull);
        expect(step.sourceStepId, step.id);
      }
      final total = result.processedSteps.fold<int>(
        0,
        (sum, step) => sum + HandoffBuilder.estimateStepTokens(step),
      );
      expect(total, lessThanOrEqualTo(700));

      final handoff = result.handoff!;
      expect(handoff.tokenBudget, 700);
      expect(handoff.truncated, isTrue);
      expect(handoff.toolEvidenceRefs, <String>['tool:unit_check']);
      expect(
          handoff.allowedCheckerTools, <String>['read_question', 'run_python']);
      expect(handoff.verifyContentHash(), isTrue);
      // 被丢弃步骤的原文不进入交接数据：截断是机械丢步，不是摘要。
      expect(
          handoff.toJson().toString(), isNot(contains('MIDDLE-MARKER-ALPHA')));
    });

    test('未超预算：全部步骤都进 handoff，每步都有 trace refs', () {
      final steps = <NormalizedStep>[
        for (var index = 1; index <= 4; index++)
          makeStep(index, '步骤$index：F=m_$index g。'),
      ];
      final result = buildWith(
        precheck: PrecheckResult.clean(),
        steps: steps,
      );
      expect(result.truncated, isFalse);
      expect(result.processedSteps, hasLength(4));
      expect(result.handoff!.truncated, isFalse);
      expect(result.handoff!.tokenBudget, 4000);
      expect(result.handoff!.processedSteps, hasLength(4));
      for (final step in result.handoff!.processedSteps) {
        expect(step.normalizedClaim, isNotNull);
        expect(step.evidenceRefs.first, 'trace:${step.id}');
        expect(step.sourceHash, isNotNull);
      }
    });
  });

  group('DeterministicPreprocessor（编排）', () {
    test('零模型调用：整条管线不碰任何 ModelAdapter', () {
      final adapter = FakeModelAdapter(<List<ModelEvent>>[]);
      final result = runPipeline(
        branchCases: const <String>['m_2/m_1\\leq 1', 'm_2/m_1=7'],
      );
      expect(adapter.requests, isEmpty);
      expect(result.hasHandoff, isTrue);
    });

    test('clean handoff 字段齐全、可追溯、hash 可复核', () {
      final result = runPipeline(
        branchCases: const <String>['m_2/m_1\\leq 1', 'm_2/m_1=7'],
        structuredClaims: <Claim>[
          Claim.given(id: 'c1', statement: 'm_2/m_1=7', createdAtMs: 0),
        ],
      );
      final handoff = result.handoff!;
      expect(handoff.schemaVersion, checkerHandoffSchemaVersion);
      expect(handoff.sourceTraceRef, 'student_solver_traces/run-1.json');
      expect(handoff.sourceHash, result.trace.sourceHash);
      expect(handoff.processedSteps, hasLength(result.trace.steps.length));
      for (var i = 0; i < handoff.processedSteps.length; i++) {
        expect(
          handoff.processedSteps[i].sourceHash,
          result.trace.steps[i].sourceHash,
        );
        expect(handoff.processedSteps[i].evidenceRefs, isNotEmpty);
      }
      expect(handoff.claims.single.id, 'c1');
      expect(handoff.toolEvidenceRefs, isEmpty);
      expect(
          handoff.allowedCheckerTools, <String>['read_question', 'run_python']);
      expect(handoff.verifyContentHash(), isTrue);
      // 不放整段 CoT / raw reasoning。
      expect(handoff.toJson().containsKey('reasoning'), isFalse);
      expect(handoff.toJson().containsKey('raw_cot'), isFalse);
    });

    test('确定性：同输入两次运行得到相同来源 hash 与内容 hash', () {
      final first = runPipeline(
        branchCases: const <String>['m_2/m_1\\leq 1', 'm_2/m_1=7'],
      );
      final second = runPipeline(
        branchCases: const <String>['m_2/m_1\\leq 1', 'm_2/m_1=7'],
      );
      expect(second.trace.sourceHash, first.trace.sourceHash);
      expect(second.precheck.outcome, first.precheck.outcome);
      expect(second.handoff!.contentHash, first.handoff!.contentHash);
      expect(second.build.truncated, first.build.truncated);
    });
  });
}
