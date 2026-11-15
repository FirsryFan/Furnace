/// 确定性 Precheck：纯规则检查预处理后的 trace / claim / 答案。
///
/// 输出 [PrecheckResult] 三态（设计 §7.5）：
///
///  * **invalid**：确定问题（空答案、缺小问、答案与过程的区间/单位不一致、
///    重复步骤/循环 n-gram、缺分支、required 锚点未覆盖）→ 回 solver 改；
///  * **unknown**：信息不足或无法判断（抽不到 claim、过程/答案单位无法对齐、
///    过程没有不等式但答案有）→ 回 solver 弄清；**不是 pass**；
///  * **clean**：没有任何 finding → 唯一允许 handoff 的状态。
///
/// 每条 finding 都带 `stepId` / `evidenceRef`（trace step、claim、锚点、分支
/// id），所以 invalid/unknown 能指向具体证据，而不是泛泛而谈。全部检查确定性、
/// 无模型调用；不确定时宁可 unknown，也不把判断交给 Checker。
library;

import 'checker_handoff.dart';
import 'checkpoint.dart';
import 'claim_extractor.dart';
import 'normalizer.dart';

/// 纯规则预检器。
class DeterministicPrecheck {
  const DeterministicPrecheck({
    this.ngramSize = 6,
    this.minNgramRepeats = 3,
    this.checkpoints,
    this.branchCases = const <String>[],
  });

  /// 循环检测的字符 n-gram 长度。
  final int ngramSize;

  /// 同一 n-gram 出现在多少个不同步骤以上算循环。
  final int minNgramRepeats;

  /// 题目锚点（只执行 required 锚点；conditional 锚点留给 Checker，设计 §7.6）。
  final CheckpointSet? checkpoints;

  /// 分支 case table（例如题目要求枚举的情况）；为空时跳过分支覆盖检查。
  final List<String> branchCases;

  static const Normalizer _normalizer = Normalizer();
  static final RegExp _inequalityPattern =
      RegExp(r'<=|>=|!=|(?<![<>=!])<(?![<=])|(?<![<>=!])>(?![>=])');

  /// 对预处理结果做确定性预检。
  PrecheckResult check({
    required String question,
    required String frozenAnswer,
    required List<NormalizedStep> steps,
    required List<ExtractedClaim> claims,
  }) {
    final normalizedAnswer = _normalizer.normalize(frozenAnswer);
    final invalid = <PrecheckFinding>[];
    final unknown = <PrecheckFinding>[];

    void addInvalid(
      String code,
      String detail, {
      String? stepId,
      String? evidenceRef,
    }) {
      invalid.add(PrecheckFinding(
        code: code,
        detail: detail,
        stepId: stepId,
        evidenceRef: evidenceRef,
      ));
    }

    void addUnknown(
      String code,
      String detail, {
      String? stepId,
      String? evidenceRef,
    }) {
      unknown.add(PrecheckFinding(
        code: code,
        detail: detail,
        stepId: stepId,
        evidenceRef: evidenceRef,
      ));
    }

    if (steps.isEmpty) {
      addUnknown('empty_trace', '没有可检查的 trace 步骤');
      return _finish(steps, claims, invalid, unknown);
    }

    // --- 答案覆盖 -----------------------------------------------------------
    if (normalizedAnswer.isEmpty) {
      addInvalid('answer_empty', '答案卡里没有最终答案', evidenceRef: 'answer');
      return _finish(steps, claims, invalid, unknown);
    }

    final subQuestionNumbers = <String>{
      for (final match
          in RegExp(r'[（(]\s*([0-9]{1,2})\s*[）)]').allMatches(question))
        match.group(1) ?? '',
    }..removeWhere((number) => number.isEmpty);
    for (final number in subQuestionNumbers) {
      if (!normalizedAnswer.contains('($number)')) {
        addInvalid(
          'answer_missing_sub_question',
          '小问（$number）的答案没有出现在答案卡里',
          evidenceRef: 'answer#sub_question_$number',
        );
      }
    }

    // --- 区间/端点一致性 ----------------------------------------------------
    final processHasInequality =
        claims.any((claim) => claim.kind == ExtractedClaimKind.inequality);
    final answerHasInequality = _inequalityPattern.hasMatch(normalizedAnswer);
    if (processHasInequality && !answerHasInequality) {
      final sourceClaim = claims.lastWhere(
        (claim) => claim.kind == ExtractedClaimKind.inequality,
      );
      addInvalid(
        'answer_missing_inequality',
        '过程推导出范围/不等式，但答案没有区间或不等式表示',
        stepId: sourceClaim.stepId,
        evidenceRef: sourceClaim.evidenceRef,
      );
    } else if (!processHasInequality && answerHasInequality) {
      addUnknown(
        'process_inequality_unverified',
        '答案含区间/不等式，但过程里没有可核对的不等式 claim',
        evidenceRef: 'answer',
      );
    }

    // --- 单位 ---------------------------------------------------------------
    final claimUnits = <String>{
      for (final claim in claims) ...claim.units,
    };
    final answerUnits = Normalizer.unitsIn(normalizedAnswer).toSet();
    if (claimUnits.isNotEmpty && answerUnits.isEmpty) {
      addInvalid(
        'answer_missing_unit',
        '过程里的结果带单位（${claimUnits.join('、')}），答案没有单位',
        evidenceRef: 'answer#unit',
      );
    } else if (claimUnits.isNotEmpty &&
        answerUnits.isNotEmpty &&
        answerUnits.intersection(claimUnits).isEmpty) {
      addUnknown(
        'unit_mismatch',
        '答案单位（${answerUnits.join('、')}）与过程单位'
            '（${claimUnits.join('、')}）对不上，无法判断',
        evidenceRef: 'answer#unit',
      );
    }

    // --- 重复/循环/无新 claim -----------------------------------------------
    final stepIdsByHash = <String, List<String>>{};
    for (final step in steps) {
      stepIdsByHash
          .putIfAbsent(step.sourceHash, () => <String>[])
          .add(step.stepId);
    }
    var hasExactDuplicate = false;
    for (final entry in stepIdsByHash.entries) {
      if (entry.value.length < 2) {
        continue;
      }
      hasExactDuplicate = true;
      addInvalid(
        'repeated_step',
        '步骤内容完全重复（${entry.value.join('、')}）',
        stepId: entry.value.last,
        evidenceRef: 'trace:${entry.value.first}',
      );
    }
    if (!hasExactDuplicate) {
      final ngramSteps = <String, Set<String>>{};
      for (final step in steps) {
        final text = step.normalized;
        if (text.length < ngramSize) {
          continue;
        }
        for (var index = 0; index + ngramSize <= text.length; index++) {
          ngramSteps
              .putIfAbsent(text.substring(index, index + ngramSize), () => {})
              .add(step.stepId);
        }
      }
      for (final entry in ngramSteps.entries) {
        if (entry.value.length >= minNgramRepeats) {
          final ids = entry.value.toList();
          addInvalid(
            'loop_ngram',
            '同一段推理在 ${ids.length} 个不同步骤里重复出现'
                '（n-gram「${entry.key}」）',
            stepId: ids.last,
            evidenceRef: 'trace:${ids.first},trace:${ids[1]}',
          );
          break;
        }
      }
    }
    for (var index = 1; index < claims.length; index++) {
      if (claims[index].normalized == claims[index - 1].normalized) {
        addInvalid(
          'no_new_claim',
          '连续 claim 完全相同，没有产生新结论',
          stepId: claims[index].stepId,
          evidenceRef: claims[index].evidenceRef,
        );
        break;
      }
    }

    // --- required 锚点覆盖（设计 §7.6：AnswerGate/Precheck 只执行 required） ---
    final checkpoints = this.checkpoints;
    if (checkpoints != null) {
      for (final checkpoint in checkpoints.required) {
        final needles = <String>[
          for (final constraint in checkpoint.constraints)
            if (constraint.isCheckable)
              for (final value in <String>[
                ...constraint.acceptable,
                ...constraint.alternatives,
              ])
                if (_normalizer.normalize(value).isNotEmpty)
                  _normalizer.normalize(value),
        ];
        if (needles.isEmpty) {
          continue;
        }
        final covered = needles.any(
          (needle) =>
              normalizedAnswer.contains(needle) ||
              steps.any((step) => step.normalized.contains(needle)),
        );
        if (!covered) {
          addInvalid(
            'anchor_missing',
            'required 锚点「${checkpoint.label}」没有在过程或答案里覆盖',
            evidenceRef: 'anchor:${checkpoint.id}',
          );
        }
      }
    }

    // --- 分支覆盖（有 case table 时才检查） ---------------------------------
    if (branchCases.isNotEmpty) {
      for (final branch in branchCases) {
        final needle = _normalizer.normalize(branch);
        if (needle.isEmpty) {
          continue;
        }
        final covered = normalizedAnswer.contains(needle) ||
            steps.any((step) => step.normalized.contains(needle)) ||
            claims.any((claim) => claim.normalized.contains(needle));
        if (!covered) {
          addInvalid(
            'branch_missing',
            '分支「$branch」在过程/答案里都没有出现',
            evidenceRef: 'branch:$branch',
          );
        }
      }
    }

    // --- 抽不到 claim：无法判断，不是 pass ---------------------------------
    if (claims.isEmpty) {
      addUnknown('no_claims', '没有从 trace 抽到任何可核对的 claim');
    }

    return _finish(steps, claims, invalid, unknown);
  }

  PrecheckResult _finish(
    List<NormalizedStep> steps,
    List<ExtractedClaim> claims,
    List<PrecheckFinding> invalid,
    List<PrecheckFinding> unknown,
  ) {
    final findings = <PrecheckFinding>[...invalid, ...unknown];
    if (invalid.isNotEmpty) {
      return PrecheckResult.invalid(
        reason: _reason('确定问题', invalid),
        questions: _questionsFor(findings),
        findings: findings,
        checkedSteps: steps.length,
      );
    }
    if (unknown.isNotEmpty) {
      return PrecheckResult.unknown(
        reason: _reason('无法判断', unknown),
        questions: _questionsFor(findings),
        findings: findings,
        checkedSteps: steps.length,
      );
    }
    return PrecheckResult.clean(checkedSteps: steps.length);
  }

  static String _reason(String label, List<PrecheckFinding> findings) {
    final codes = findings.map((finding) => finding.code).toSet().join('、');
    return '确定性预检发现 ${findings.length} 个$label：$codes';
  }

  /// 每个 finding code 对应一个确定性的澄清问题（回 solver）。
  static List<String> _questionsFor(List<PrecheckFinding> findings) {
    final questions = <String>[];
    for (final finding in findings) {
      final question = switch (finding.code) {
        'answer_empty' => '答案卡是空的，请给出完整最终答案。',
        'answer_missing_sub_question' => '请补上缺少的小问答案：${finding.detail}。',
        'answer_missing_inequality' => '过程得到的是范围/不等式，请确认答案是否应写成区间并补上端点。',
        'answer_missing_unit' => '过程里带单位的结果，在答案里请补上单位。',
        'unit_mismatch' => '答案单位与过程单位不一致，请说明换算或改正。',
        'repeated_step' => '请说明重复步骤的必要性，或合并重复推理。',
        'loop_ngram' => '推理在原地打转：请换一种推导，或用已有结论收尾。',
        'no_new_claim' => '连续步骤没有产生新结论，请删掉重复推理。',
        'anchor_missing' => '题目要求的关键量/定义域/端点是否在答案里？请补全。',
        'branch_missing' => '缺少一个分支，请补全所有情况。',
        'no_claims' => '请把推理写成带步骤和依据、且可被结构化识别的过程。',
        'empty_trace' => '请重新输出带步骤的推理过程。',
        'process_inequality_unverified' => '答案里的区间/不等式依据是什么？请在过程中写出对应推导。',
        _ => '请说明并修正：${finding.detail}。',
      };
      if (!questions.contains(question)) {
        questions.add(question);
      }
    }
    return questions;
  }
}
