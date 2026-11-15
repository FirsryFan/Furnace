import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/claim.dart';
import 'package:furnace/features/ai/domain/process_auditor.dart';

/// ProcessAuditor 的过程审计（STUDENT-MODE-AND-AGENT-LOOP-DESIGN §7.4）：
/// **读 reasoning 原文**，检测循环、反复自我怀疑、无进展，并抽取 claim 摘要。
///
/// 它不判答案对错——那件事归 ContentVerifier（`verifier.dart`）。这些用例刻意
/// 用「纯文本 fixture」，因为审计器的输入就是文本，没有模型、没有网络。
void main() {
  final auditor = ProcessAuditor();

  group('干净过程', () {
    const clean = '由题意，物块初速度 v0=6 m/s。\n'
        '加速度 a=-2 m/s²。\n'
        '取向右为正方向。\n'
        '所以 t=2 s 时速度为零。\n'
        '随后物块开始反向运动。\n'
        '因此 t=5 s 时位移为 3 m。';

    test('没有循环 / 停滞 / 自我怀疑', () {
      final report = auditor.audit(reasoning: clean);
      expect(report.loopDetected, isFalse);
      expect(report.stagnation, isFalse);
      expect(report.selfDoubtCount, 0);
      expect(report.flags, isEmpty);
      expect(report.hasProblems, isFalse);
      expect(report.suggestsRepair, isFalse);
    });

    test('抽出 claim 摘要（等式/结论句）', () {
      final report = auditor.audit(reasoning: clean);
      expect(report.extractedClaims, isNotEmpty);
      expect(
        report.extractedClaims.any((claim) => claim.statement.contains('v0=6')),
        isTrue,
        reason: '含等式的句子应被当成 claim',
      );
      expect(report.claimSummary.claims.length, report.extractedClaims.length);
    });

    test('同一段文本永远得到同一份报告', () {
      final first = auditor.audit(reasoning: clean);
      final second = auditor.audit(reasoning: clean);
      expect(first.toJson(), second.toJson());
    });
  });

  group('循环', () {
    test('同一句重复 3 次以上 -> loopDetected + repeated_sentence', () {
      const reasoning = '设物块质量为 m。\n'
          '设物块质量为 m。\n'
          '设物块质量为 m。\n'
          '设物块质量为 m。';
      final report = auditor.audit(reasoning: reasoning);
      expect(report.loopDetected, isTrue);
      expect(report.flags, contains('repeated_sentence'));
      expect(
        report.repeatedClaimCount,
        greaterThanOrEqualTo(2),
        reason: '同一 claim 出现 4 次，至少重复了 3 次',
      );
    });

    test('句子级周期 ABAB -> loopDetected + sentence_cycle', () {
      const reasoning = '第一步先求加速度。\n'
          '第二步再求速度。\n'
          '第一步先求加速度。\n'
          '第二步再求速度。';
      final report = auditor.audit(reasoning: reasoning);
      expect(report.loopDetected, isTrue);
      expect(report.flags, contains('sentence_cycle'));
    });

    test('动作序列周期 -> loopDetected + action_cycle', () {
      final report = auditor.audit(
        reasoning: '短推理。',
        actionSequence: const ['a', 'b', 'c', 'a', 'b', 'c'],
      );
      expect(report.loopDetected, isTrue);
      expect(report.flags, contains('action_cycle'));
    });

    test('在已 settled 的分支上重开 -> branch_reopened', () {
      const reasoning = '这部分已经算完。\n'
          '重新来一遍看看。\n'
          '从头再推一次。\n'
          '还是回到最初重新设未知数。';
      final report = auditor.audit(reasoning: reasoning);
      expect(report.flags, contains('branch_reopened'));
      expect(report.suggestsRepair, isTrue);
    });
  });

  group('反复自我怀疑', () {
    test('自我怀疑短语够多 -> self_doubt 标记', () {
      const reasoning = '我先按第一种理解做。也许这里取错方向了。\n'
          '我可能错了。再检查一遍。\n'
          '我怀疑这个符号不对。再检查一遍。\n'
          '也许应该重新考虑。';
      final report = auditor.audit(reasoning: reasoning);
      expect(report.selfDoubtCount, greaterThanOrEqualTo(3));
      expect(report.flags, contains('self_doubt'));
      expect(report.hasProblems, isTrue);
    });
  });

  group('无进展', () {
    test('唯一句占比过低 -> stagnation + repetitive_reasoning', () {
      const reasoning = '所以要算两个时刻的位移。\n'
          '先求速度随时间的表达式。\n'
          '再代入位移公式。\n'
          '最后比较两个结果。\n'
          '所以要算两个时刻的位移。\n'
          '再代入位移公式。\n'
          '先求速度随时间的表达式。\n'
          '最后比较两个结果。';
      final report = auditor.audit(reasoning: reasoning);
      expect(report.stagnation, isTrue);
      expect(report.flags, contains('repetitive_reasoning'));
      expect(report.loopDetected, isFalse,
          reason: '没有连续重复 3 次、也没有连续两段相同，不该判成循环');
    });

    test('后半段没有新数字/新结论 -> no_new_content_in_tail', () {
      // 专用配置：把「整段重复」与长度门槛调开，单独验证尾段推进检查。
      final tailAuditor = ProcessAuditor(
        config: const ProcessAuditorConfig(
          minCharsForTailCheck: 40,
          minSentencesForStagnation: 99,
        ),
      );
      const prefix = '所以 t=2 s 时速度为零。\n'
          '先说清楚原点的位置与正方向，沿斜面向下为正。\n'
          '再写出速度公式 v=v0+at 与位移公式 x=v0t+at²/2。\n'
          '把已知量代入后可以逐步算出中间结果。\n';
      // 尾段必须：不含任何新数字、不含任何新的 claim 句；长度足够让 60% 的分割
      // 点落在尾段（而不是把前缀的后半句误算成"新内容"）。
      const suffix = '所以 t=2 s 时速度为零。\n'
          '这一段只是把前面的叙述再重复一遍。\n'
          '整个过程的处理方式与之前完全一样。\n'
          '这些内容在前面已经出现过，没有增加新的东西。\n'
          '尾部只是复述，没有推进任何一种新的方向。\n'
          '这里没有新的条件，也没有新的中间结果。\n'
          '末尾再重复一次上面的描述，没有别的变化。';
      const text = '$prefix$suffix';
      expect(text.length, greaterThan(40));

      final report = tailAuditor.audit(reasoning: text);
      expect(report.flags, contains('no_new_content_in_tail'));
      expect(report.stagnation, isTrue);
    });

    test('与上一段相比没有新句子 -> no_progress_vs_previous', () {
      const previous = '第一步求加速度 a=2 m/s²。\n第二步求速度 v=4 m/s。';
      const current = '第一步求加速度 a=2 m/s²。';
      final report = auditor.audit(
        reasoning: current,
        previousReasoning: previous,
      );
      expect(report.flags, contains('no_progress_vs_previous'));
      expect(report.stagnation, isTrue);
    });

    test('状态指纹没变 -> state_unchanged', () {
      final report = auditor.audit(
        reasoning: '第一句说明。第二句说明。',
        stateFingerprint: 'fingerprint-1',
        previousStateFingerprint: 'fingerprint-1',
      );
      expect(report.flags, contains('state_unchanged'));
      expect(report.stagnation, isTrue);
    });
  });

  group('claim 摘要', () {
    test('同义引导词（所以/因此）下的同一 claim 会合并计数', () {
      const reasoning = '由题意得 v0=6 m/s。\n'
          '所以 t=2 s 时速度为零。\n'
          '因此 t=2 s 时速度为零。';
      final report = auditor.audit(reasoning: reasoning);
      final claim = report.extractedClaims
          .firstWhere((claim) => claim.canonical.contains('t=2s'));
      expect(claim.evidence, contains('2 次'));
      expect(report.repeatedClaimCount, greaterThanOrEqualTo(1));
      expect(report.flags, contains('repeated_claim'));
    });

    test('claim 摘要可 JSON 往返，坏 JSON 退化成空摘要', () {
      final report = auditor.audit(reasoning: '所以 t=2 s 时速度为零。');
      final decoded = ProcessReport.fromJson(report.toJson());
      expect(decoded.loopDetected, report.loopDetected);
      expect(decoded.stagnation, report.stagnation);
      expect(decoded.flags, report.flags);
      expect(decoded.extractedClaims.length, report.extractedClaims.length);
      expect(
        report.claimSummary.claims.length,
        report.extractedClaims.length,
      );
      expect(report.claimSummary.toPromptText(), contains('t=2 s'));

      expect(ProcessReport.fromJson(null), ProcessReport.clean);
      expect(ProcessReport.clean.claimSummary.isEmpty, isTrue);
      expect(const ClaimSummary.empty().isEmpty, isTrue);
    });
  });
}
