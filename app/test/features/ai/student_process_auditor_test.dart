import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/process_auditor.dart';
import 'package:furnace/features/ai/domain/reasoning_ledger.dart';
import 'package:furnace/features/ai/domain/student_run.dart';
import 'package:furnace/features/ai/infrastructure/student_process_auditor.dart';

/// 学生过程审计（设计文档 §7.4）：读 reasoning，查循环 / 反复自我怀疑 / 无进展，
/// 并把抽出的 claim 登记进 ClaimLedger（同一 claim 在版本未变时合并）。
///
/// 纯确定性启发式：不调模型、不读文件，同一段文本永远得到同一份报告。
void main() {
  group('过程信号', () {
    test('同一句重复出现 -> loopDetected + repeated_sentence', () async {
      final auditor = StudentProcessAuditor();
      final result = await auditor.audit(
        reasoning: '设物块质量为 m。\n设物块质量为 m。\n设物块质量为 m。\n所以 a=g sinθ。',
      );

      expect(result.report.loopDetected, isTrue);
      expect(result.report.flags, contains('repeated_sentence'));
      expect(result.report.hasProblems, isTrue);
    });

    test('动作序列周期 -> action_cycle', () async {
      final auditor = StudentProcessAuditor();
      final result = await auditor.audit(
        reasoning: '继续。',
        actionSequence: const ['step:model:solve', 'step:answer', 'step:model:solve', 'step:answer'],
      );

      expect(result.report.loopDetected, isTrue);
      expect(result.report.flags, contains('action_cycle'));
    });

    test('反复自我怀疑 -> self_doubt，且计数可见', () async {
      final auditor = StudentProcessAuditor();
      final result = await auditor.audit(
        reasoning: '我可能错了。再检查一遍。我怀疑这个符号不对。也许方向取反了。',
      );

      expect(result.report.flags, contains('self_doubt'));
      expect(result.report.selfDoubtCount, greaterThanOrEqualTo(3));
      // 自我怀疑只是「值得停下来看看」，不是判答案错。
      expect(result.report.loopDetected, isFalse);
    });

    test('与上一段相比没有新句子 -> stagnation', () async {
      final auditor = StudentProcessAuditor();
      final first = await auditor.audit(reasoning: '由牛顿第二定律得 a=g sinθ。');
      expect(first.report.stagnation, isFalse);

      final second = await auditor.audit(
        reasoning: '由牛顿第二定律得 a=g sinθ。',
        previousReasoning: '由牛顿第二定律得 a=g sinθ。',
      );
      expect(second.report.stagnation, isTrue);
      expect(second.report.flags, contains('no_progress_vs_previous'));
    });

    test('同一输入同一报告（确定性）', () async {
      const reasoning = '所以 μ=0.5。因此 a=3。';
      final first = await StudentProcessAuditor().audit(reasoning: reasoning);
      final second = await StudentProcessAuditor().audit(reasoning: reasoning);

      expect(second.report.flags, first.report.flags);
      expect(second.report.loopDetected, first.report.loopDetected);
      expect(
        second.report.extractedClaims.map((claim) => claim.canonical),
        first.report.extractedClaims.map((claim) => claim.canonical),
      );
    });

    test('审计结果带实际 claim 列表，且 blocker 按报告分类', () async {
      final auditor = StudentProcessAuditor();

      final loop = await auditor.audit(
        reasoning: '设物块质量为 m。\n设物块质量为 m。\n设物块质量为 m。\n所以 a=g sinθ。',
      );
      expect(loop.claims, isNotEmpty);
      expect(loop.blocker, StudentProcessBlocker.loop);

      final stagnation = await auditor.audit(
        reasoning: '由牛顿第二定律得 a=g sinθ。',
        previousReasoning: '由牛顿第二定律得 a=g sinθ。',
      );
      expect(stagnation.report.stagnation, isTrue);
      expect(stagnation.blocker, StudentProcessBlocker.loop);

      final selfDoubt = await auditor.audit(
        reasoning: '我可能错了。再检查一遍。我怀疑这个符号不对。也许方向取反了。',
      );
      expect(selfDoubt.blocker, StudentProcessBlocker.selfDoubt);
      expect(selfDoubt.blocker!.stopReason.id, 'process_self_doubt');

      final clean = await auditor.audit(reasoning: '由牛顿第二定律得 a=g sinθ。');
      expect(clean.blocker, isNull);
      expect(clean.claims, isNotEmpty);
    });
  });

  group('ClaimLedger 登记', () {
    test('抽出的 claim 进入 ledger，摘要给 verifier 用', () async {
      final ledger = ClaimLedger();
      final auditor = StudentProcessAuditor(ledger: ledger);
      final result = await auditor.audit(
        reasoning: '由牛顿第二定律得 a=g sinθ。\n所以 μ=0.5。',
      );

      expect(result.report.extractedClaims, isNotEmpty);
      expect(ledger.length, greaterThan(0));
      expect(result.registeredClaims, greaterThan(0));
      expect(result.claimSummary.claims, isNotEmpty);
      // 实际 claim 列表与给 verifier 的摘要一致（run 结束落 agent_claims 用的
      // 就是这份列表）。
      expect(
        result.claims.map((claim) => claim.id),
        result.claimSummary.claims.map((claim) => claim.id),
      );
      expect(result.claims, hasLength(ledger.length));
      // 摘要可渲染成 verifier 输入（不含 reasoning 原文之外的东西）。
      expect(result.claimSummary.toPromptText(), contains('['));
    });

    test('同一段 reasoning 二次审计命中已有 claim（版本未变则合并）', () async {
      final ledger = ClaimLedger();
      final auditor = StudentProcessAuditor(ledger: ledger);
      const reasoning = '由牛顿第二定律得 a=g sinθ。\n所以 μ=0.5。';

      final first = await auditor.audit(reasoning: reasoning);
      final second = await auditor.audit(reasoning: reasoning);

      expect(first.mergedClaims, 0);
      expect(second.mergedClaims, greaterThan(0));
      expect(second.report.flags, contains('repeated_claim'));
      expect(second.report.repeatedClaimCount, greaterThan(0));
      // 合并不会让 ledger 里长出新 claim。
      expect(ledger.length, first.registeredClaims);
    });

    test('没有 ledger 时仍产出 claim 摘要', () async {
      final auditor = StudentProcessAuditor();
      final result = await auditor.audit(
        reasoning: '由牛顿第二定律得 a=g sinθ。',
      );

      expect(result.registeredClaims, 0);
      expect(result.claimSummary.claims, isNotEmpty);
      // ClaimSummary 的形状与 ProcessReport.claimSummary 一致。
      expect(
        result.report.claimSummary.claims.length,
        result.claimSummary.claims.length,
      );
    });

    test('报告可 JSON 往返（落 agent_verifications 的 process_report_json）', () async {
      final auditor = StudentProcessAuditor();
      final result = await auditor.audit(
        reasoning: '设物块质量为 m。\n设物块质量为 m。\n设物块质量为 m。',
      );

      final restored = ProcessReport.fromJson(result.report.toJson());
      expect(restored.loopDetected, isTrue);
      expect(restored.flags, contains('repeated_sentence'));
      expect(restored.extractedClaims, isNotEmpty);
    });
  });
}
