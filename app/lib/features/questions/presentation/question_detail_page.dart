/// 题目详情页：一道题的完整视图 + 推理管道的入口与可读展示。
///
/// 三件事按顺序摊在一页上：
///
///  1. **题目现状**：题干、选项（标出正确答案）、答案、解析、来源/年份/难度。
///  2. **AI 解题**：按一下调 `QuestionReasoningService.solveAndDecompose`，
///     模型给的分步思维链当场展示，并（默认）落进 `reasoning_chains` /
///     `reasoning_steps`——链是派生数据，同一道题可以有多条，互不覆盖。
///  3. **卡点评估**：`StuckPointEvaluator` 把「模型判断的风险」和「你自己的记忆
///     状态读数」等权融合，逐步给建议。评估结果**不进数据库**：它是"此刻的看法"，
///     不是事实；链才是事实。
///
/// 两条本页坚持的诚实性规则：
///
///  * **失败面照样展示**：模型没配好、回复不合契约、题目 id 不存在，都显示
///    `failureReason` 与已收到的 `rawReply`，不弹一个"出错了"就吞掉。
///  * **没有状态数据要说出来**：`unmatchedHints` 是"本地没有你的读数"，不是
///    "这一步没问题"。两者在界面上的差别必须看得见。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/paper/similar_questions.dart';
import '../../../domain/services/reasoning/capability_action.dart';
import '../../../domain/services/reasoning/reasoning_prompt.dart';
import '../../../domain/services/reasoning/stuck_point_evaluator.dart';
import '../../../domain/services/srs/dsr_memory.dart';
import '../../../l10n/app_localizations.dart';
import '../application/question_reasoning_service.dart';
import '../application/similar_question_provider.dart';
import 'question_detail_providers.dart';
import 'question_intake_page.dart';
import 'question_vocab_labels.dart';

/// 详情页只吃一个 id：其余全部现读，页面上任何东西都不是调用方传进来的快照。
class QuestionDetailPage extends ConsumerStatefulWidget {
  const QuestionDetailPage({super.key, required this.questionId});

  final String questionId;

  @override
  ConsumerState<QuestionDetailPage> createState() => _QuestionDetailPageState();
}

class _QuestionDetailPageState extends ConsumerState<QuestionDetailPage> {
  bool _running = false;

  /// 本次按下按钮的结果。`null` = 这次进来还没按过——于是页面只显示库里那条链。
  ReasoningRunResult? _lastRun;

  Future<void> _solve() async {
    if (_running) {
      return;
    }
    setState(() {
      _running = true;
      _lastRun = null;
    });
    final result = await ref
        .read(questionReasoningServiceProvider)
        .solveAndDecompose(widget.questionId);
    if (!mounted) {
      return;
    }
    setState(() {
      _running = false;
      _lastRun = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detailAsync = ref.watch(questionDetailProvider(widget.questionId));
    final detail = detailAsync.valueOrNull;
    final missing = detailAsync.hasValue && detail == null;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.questionDetailTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (detailAsync.isLoading && !detailAsync.hasValue)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: LinearProgressIndicator(),
            )
          else if (detailAsync.hasError)
            Text('${detailAsync.error}')
          else if (missing)
            Text(l10n.questionDetailQuestionMissing)
          else if (detail != null)
            _QuestionCard(detail: detail),
          const SizedBox(height: 16),
          _ReasoningSection(
            questionId: widget.questionId,
            running: _running,
            lastRun: _lastRun,
            enabled: detail != null,
            onSolve: _solve,
          ),
          const SizedBox(height: 16),
          _SimilarQuestionsSection(questionId: widget.questionId),
        ],
      ),
    );
  }
}

/// 题目本身：题干、选项、答案、解析、来源与质量。
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.detail});

  final QuestionDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final question = detail.question;

    final meta = <String>[
      question.subjectKey.trim().isEmpty
          ? l10n.questionIntakeSubjectNone
          : CapabilityAction.subjectLabelsZh[question.subjectKey] ??
              question.subjectKey,
      sourceLevelLabel(l10n, question.sourceLevel),
      stateLabel(l10n, question.state),
      _originLabel(l10n, question.origin),
      if (question.year != null) l10n.questionDetailYear(question.year!),
      if (question.region != null && question.region!.trim().isNotEmpty)
        question.region!.trim(),
    ];

    final answer = question.answer?.trim() ?? '';
    final solution = question.solution?.trim() ?? '';
    final trapNote = question.trapNote?.trim() ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(meta.join(' · '), style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            SelectableText(question.stem, style: theme.textTheme.titleMedium),
            if (question.difficulty != null) ...[
              const SizedBox(height: 4),
              Text(
                l10n.questionDetailDifficulty(_number(question.difficulty!)),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (detail.options.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                l10n.questionIntakeOptionsLabel,
                style: theme.textTheme.titleSmall,
              ),
              for (final option in detail.options)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${option.label}. '),
                      Expanded(child: Text(option.content)),
                      if (option.isCorrect)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            l10n.questionDetailCorrectOption,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
            if (answer.isNotEmpty)
              _LabelledText(
                  label: l10n.questionIntakeAnswerLabel, value: answer),
            if (solution.isNotEmpty)
              _LabelledText(
                label: l10n.questionIntakeSolutionLabel,
                value: solution,
              ),
            if (trapNote.isNotEmpty)
              _LabelledText(
                  label: l10n.questionDetailTrapNote, value: trapNote),
            if (question.aiQuality != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.questionDetailAiQuality(_number(question.aiQuality!)),
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 推理管道区块：按钮 + 失败面 + 链与卡点评估。
class _ReasoningSection extends ConsumerWidget {
  const _ReasoningSection({
    required this.questionId,
    required this.running,
    required this.lastRun,
    required this.enabled,
    required this.onSolve,
  });

  final String questionId;
  final bool running;
  final ReasoningRunResult? lastRun;
  final bool enabled;
  final Future<void> Function() onSolve;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final stored =
        ref.watch(questionStoredChainProvider(questionId)).valueOrNull;
    final statesAsync = ref.watch(questionKnowledgeStatesProvider);
    final knowledgePointIds =
        ref.watch(questionKnowledgePointIdsProvider(questionId)).valueOrNull ??
            const <String>[];

    // 本次运行的结果优先（它比库里的新）；没按过按钮就看库里最新那条。
    final chain = lastRun?.chain ?? stored?.chain;
    final fromLibrary = lastRun?.chain == null && chain != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.questionDetailReasoningSection,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: (!enabled || running) ? null : onSolve,
                icon: running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  running
                      ? l10n.questionDetailSolving
                      : chain == null
                          ? l10n.questionDetailSolveButton
                          : l10n.questionDetailResolveButton,
                ),
              ),
            ),
            if (lastRun != null && !lastRun!.ok) _FailureCard(result: lastRun!),
            if (knowledgePointIds.isNotEmpty)
              _KnowledgePointChips(
                ids: knowledgePointIds,
                states: statesAsync.valueOrNull,
              ),
            const SizedBox(height: 12),
            if (chain == null)
              Text(
                l10n.questionDetailNoChainYet,
                style: theme.textTheme.bodyMedium,
              )
            else
              statesAsync.when(
                loading: () => Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(l10n.questionDetailStatesLoading),
                  ],
                ),
                error: (error, _) =>
                    Text(l10n.questionDetailStatesFailed('$error')),
                data: (states) => _ChainView(
                  chain: chain,
                  states: states,
                  fromLibrary: fromLibrary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 链的整体风险 + 逐步卡点。
class _ChainView extends StatelessWidget {
  const _ChainView({
    required this.chain,
    required this.states,
    required this.fromLibrary,
  });

  final ParsedChain chain;
  final Map<String, DsrState> states;
  final bool fromLibrary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final report = StuckPointEvaluator.evaluate(
      steps: chain.steps,
      // 评估器的"现在"与状态读数的"现在"必须是同一个时钟：两边都用
      // `modelHoursOf`（自 Unix 纪元起的小时），差一小时就会让风险读数漂。
      nowHours: modelHoursOf(DateTime.now()),
      statesByKnowledgePoint: states,
    );
    // 步骤的文字（justification / checkMethod / knowledgeHints）不在评估结果里，
    // 按步号配回原始步骤。步号重复时后一条覆盖前一条——不额外发明合并规则。
    final parsedByIndex = <int, ParsedStep>{
      for (final step in chain.steps) step.index: step,
    };
    final mostLikely = report.mostLikely;
    final covered = report.steps.where((step) => step.hasStateEvidence).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fromLibrary)
          Text(l10n.questionDetailChainFromLibrary,
              style: theme.textTheme.bodySmall),
        if (chain.summary.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(chain.summary, style: theme.textTheme.bodyLarge),
        ],
        const SizedBox(height: 8),
        Text(
            l10n.questionDetailOverallRisk((report.overallRisk * 100).round())),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: report.overallRisk),
        if (mostLikely != null) ...[
          const SizedBox(height: 4),
          Text(l10n.questionDetailMostLikelyStep(mostLikely.index)),
        ],
        const SizedBox(height: 4),
        Text(
          l10n.questionDetailEvidenceCoverage(covered, report.steps.length),
          style: theme.textTheme.bodySmall,
        ),
        for (final point in report.steps)
          _StepCard(point: point, step: parsedByIndex[point.index]),
        if (report.unmatchedHints.isNotEmpty)
          _UnmatchedHints(hints: report.unmatchedHints),
      ],
    );
  }
}

/// 一步：模型怎么说 + 融合后的风险 + 建议。
class _StepCard extends StatelessWidget {
  const _StepCard({required this.point, required this.step});

  final StepStuckPoint point;

  /// 对应的原始步骤；理论上总在（评估器就是拿它算的），缺失时退化成只显示评估结果。
  final ParsedStep? step;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final step = this.step;
    final riskColor =
        point.isHighRisk ? theme.colorScheme.error : theme.colorScheme.primary;
    final goal = (step?.goal ?? point.goal).trim();
    final justification = step?.justification.trim() ?? '';
    final checkMethod = step?.checkMethod.trim() ?? '';
    final hints = step?.knowledgeHints ?? const <String>[];

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  l10n.questionDetailStepTitle(point.index),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    point.actionLabelZh,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            if (step != null && !step.knownAction)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.questionDetailUnknownAction(point.actionType),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            if (goal.isNotEmpty)
              _LabelledText(
                  label: l10n.questionDetailStepGoalLabel, value: goal),
            if (justification.isNotEmpty)
              _LabelledText(
                label: l10n.questionDetailStepJustificationLabel,
                value: justification,
              ),
            if (checkMethod.isNotEmpty)
              _LabelledText(
                label: l10n.questionDetailStepCheckLabel,
                value: checkMethod,
              ),
            if (hints.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                l10n.questionDetailStepKnowledgeLabel,
                style: theme.textTheme.labelSmall,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final hint in hints)
                    Chip(
                      label: Text(hint),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              l10n.questionDetailModelRisk((point.modelRisk * 100).round()),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: point.modelRisk, color: riskColor),
            // 融合值只在真的有状态证据时才显示：否则它等于模型风险，多画一根
            // 一样的条会让人以为"你自己的数据也这么说了"。
            if (point.hasStateEvidence) ...[
              const SizedBox(height: 6),
              Text(
                l10n.questionDetailFusedRisk((point.fusedRisk * 100).round()),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: point.fusedRisk, color: riskColor),
            ],
            const SizedBox(height: 8),
            Text(
              l10n.questionDetailSuggestionLabel,
              style: theme.textTheme.labelSmall,
            ),
            Text(point.suggestion),
          ],
        ),
      ),
    );
  }
}

/// 失败面：原因 + 原始回复。
class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.result});

  final ReasoningRunResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rawReply = result.rawReply?.trim() ?? '';
    final failureReason = result.failureReason;

    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.questionDetailRunFailedTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (failureReason != null)
              _LabelledText(
                label: l10n.questionDetailFailureReasonLabel,
                value: failureReason,
              ),
            const SizedBox(height: 8),
            Text(
              l10n.questionDetailRawReplyLabel,
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: 4),
            SelectableText(
              rawReply.isNotEmpty
                  ? rawReply
                  : l10n.questionDetailRawReplyMissing,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// 全链没有状态读数的知识点提示：明说"不是没问题"。
class _UnmatchedHints extends StatelessWidget {
  const _UnmatchedHints({required this.hints});

  final List<String> hints;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.questionDetailUnmatchedHintsTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.questionDetailUnmatchedHintsBody,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final hint in hints)
                  Chip(
                    label: Text(hint),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 题目挂载的知识点；没有读数的那些标一个提示图标。
class _KnowledgePointChips extends StatelessWidget {
  const _KnowledgePointChips({required this.ids, required this.states});

  final List<String> ids;

  /// 状态读数还在路上时是 `null`——此时不标"没有读数"，因为还不知道。
  final Map<String, DsrState>? states;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final readings = states;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.questionDetailKnowledgePointsLabel,
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final id in ids)
                Chip(
                  label: Text(id),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: readings != null && !readings.containsKey(id)
                      ? Tooltip(
                          message: l10n.questionDetailKnowledgePointNoReading,
                          child: const Icon(Icons.help_outline, size: 16),
                        )
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一个"标签 + 值"的竖排小段。详情页上大量重复的排版只有这一种。
class _LabelledText extends StatelessWidget {
  const _LabelledText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }
}

/// 来源（`origin`）：手工 / 拍照扫描 / Furnace 内建。
String _originLabel(AppLocalizations l10n, String origin) => switch (origin) {
      'manual' => l10n.questionIntakeOriginManual,
      'ai_scan' => l10n.questionIntakeOriginAiScan,
      'furnace' => l10n.questionIntakeOriginFurnace,
      _ => origin.trim().isEmpty ? l10n.questionIntakeOriginManual : origin,
    };

/// 数值显示：整数不拖 `.0`，小数保留一位（难度 6 而不是 6.0）。
String _number(double value) {
  final rounded = value.roundToDouble();
  return rounded == value
      ? rounded.toInt().toString()
      : value.toStringAsFixed(1);
}

/// 找相似题：只从**已有题库**里找。领域层已经排好序、写好理由，这里不改顺序、
/// 不复算分量、不把 `score` 当百分比——只画 `reasonZh` 与「跨学科迁移」角标。
///
/// 一道都不像时（空列表）只给空态 + 去收题入口：**不许拿"看着像"的题凑数**，
/// 这是本片用户口径里最硬的一条。
class _SimilarQuestionsSection extends ConsumerWidget {
  const _SimilarQuestionsSection({required this.questionId});

  final String questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final similar = ref.watch(similarQuestionsProvider(questionId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.questionSimilarTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l10n.questionSimilarSubtitle,
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            similar.when(
              loading: () => Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(l10n.questionSimilarLoading),
                ],
              ),
              error: (error, _) => Text(l10n.questionSimilarFailed('$error')),
              data: (items) => items.isEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.questionSimilarEmpty),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonalIcon(
                            onPressed: () => _openIntake(context),
                            icon: const Icon(Icons.add),
                            label: Text(l10n.questionSimilarGoIntake),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.questionSimilarCount(items.length),
                          style: theme.textTheme.bodySmall,
                        ),
                        for (final item in items)
                          _SimilarQuestionTile(similar: item),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一条候选：题干摘要（点进它的详情页）+ 领域层给的理由原文。
class _SimilarQuestionTile extends ConsumerWidget {
  const _SimilarQuestionTile({required this.similar});

  final SimilarQuestion similar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final detail = ref.watch(questionDetailProvider(similar.questionId));
    final stem = detail.valueOrNull?.question.stem.trim();
    final loadingStem = detail.isLoading && !detail.hasValue;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Expanded(
            child: Text(
              loadingStem
                  ? '…'
                  : (stem == null || stem.isEmpty
                      ? l10n.questionDetailQuestionMissing
                      : stem),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (similar.crossSubjectTransfer) ...[
            const SizedBox(width: 8),
            _TransferBadge(label: l10n.questionSimilarCrossSubject),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(similar.reasonZh, style: theme.textTheme.bodySmall),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) =>
              QuestionDetailPage(questionId: similar.questionId),
        ),
      ),
    );
  }
}

/// 「跨学科迁移」角标：学科不同、但解题动作同型（`crossSubjectTransfer`）。
class _TransferBadge extends StatelessWidget {
  const _TransferBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
      ),
    );
  }
}

/// 空态里的「去收题」：AI 不出题，库里没有就去收。
void _openIntake(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const QuestionIntakePage()),
  );
}
