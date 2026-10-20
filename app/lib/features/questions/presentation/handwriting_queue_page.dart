/// 拍照整理的待确认队列（`docs/QUESTION_BANK_DESIGN.md` §7.3–§7.4）。
///
/// 用户口径是「全部走待确认清单，逐个确认；**确认前不写库**」。这一页只做三件事：
/// 把待整理的照片排出来、把模型整理出来的提案摆出来、让用户逐条或整批确认。
/// 真正的写库动作在 [HandwritingQueueNotifier]（application 层）里，页面不碰仓储。
///
/// 三条显示纪律（与组卷页、详情页同一条）：
///
///  * `rationaleZh` 是领域层给用户看的话，**原样显示**，页面不另写一套文案；
///  * `confidence` **不显示成百分比**——0.83 会让人读成"83% 正确"，而它其实是
///    模型自己的犹豫程度。这里折成「较确定 / 拿不准 / 不太确定」三档；
///  * `analyze` 失败时**只显示失败原因**，不显示上一轮的旧提案：留着旧提案会让
///    用户以为这次整理成功了（队列层也已经把旧 set 删掉了，这里是第二道保险）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/intake/handwriting_proposals.dart';
import '../../../l10n/app_localizations.dart';
import '../application/handwriting_proposal_service.dart';
import '../data/handwriting_intake_store.dart';
import 'question_intake_page.dart';

/// 待确认队列页。
///
/// [initialRelPath] 用于"从收题页点某张照片的「整理」"这条入口：进来就选中它。
class HandwritingQueuePage extends ConsumerStatefulWidget {
  const HandwritingQueuePage({super.key, this.initialRelPath});

  final String? initialRelPath;

  @override
  ConsumerState<HandwritingQueuePage> createState() =>
      _HandwritingQueuePageState();
}

class _HandwritingQueuePageState extends ConsumerState<HandwritingQueuePage> {
  String? _selectedRelPath;

  @override
  void initState() {
    super.initState();
    _selectedRelPath = widget.initialRelPath;
    // `HandwritingQueueNotifier.build()` 给的是空 state（它不主动读磁盘），
    // 所以"打开这一页就能看到待整理清单"必须由页面自己触发。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(handwritingQueueProvider.notifier).refresh();
    });
  }

  PendingHandwritingImage? _selectedImage(
    List<PendingHandwritingImage> images,
  ) {
    if (images.isEmpty) {
      return null;
    }
    final current = _selectedRelPath;
    if (current != null) {
      for (final image in images) {
        if (image.relPath == current) {
          return image;
        }
      }
    }
    return images.first;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final queue = ref.watch(handwritingQueueProvider);

    // 清单刷新后，选中的照片可能已经被删掉了：回落到的第一张。
    ref.listen(handwritingQueueProvider, (previous, next) {
      final selection = _selectedImage(next.images);
      if (selection?.relPath != _selectedRelPath) {
        setState(() => _selectedRelPath = selection?.relPath);
      }
    });

    final selected = _selectedImage(queue.images);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.handwritingQueueTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.handwritingQueueSubtitle,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (queue.loading && queue.images.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: LinearProgressIndicator(),
            )
          else if (queue.images.isEmpty)
            _EmptyQueue(onOpenIntake: _openIntake)
          else ...[
            _PhotoStrip(
              images: queue.images,
              selectedRelPath: selected?.relPath,
              onSelect: (image) =>
                  setState(() => _selectedRelPath = image.relPath),
            ),
            const SizedBox(height: 12),
            if (selected != null)
              _SelectedPhotoPanel(image: selected, queue: queue),
          ],
        ],
      ),
    );
  }

  void _openIntake() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const QuestionIntakePage()),
    );
  }
}

/// 一张照片都没有：空态 + 去收题页（不编造"正在整理"的假象）。
class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue({required this.onOpenIntake});

  final VoidCallback onOpenIntake;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.handwritingQueueEmpty),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: onOpenIntake,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(l10n.handwritingQueueGoIntake),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 待整理照片清单；选中的那张高亮。
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.images,
    required this.selectedRelPath,
    required this.onSelect,
  });

  final List<PendingHandwritingImage> images;
  final String? selectedRelPath;
  final ValueChanged<PendingHandwritingImage> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.handwritingQueuePhotosLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final image in images)
                  ChoiceChip(
                    label: Text(image.fileName),
                    selected: image.relPath == selectedRelPath,
                    onSelected: (_) => onSelect(image),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 选中照片的整理面板：整理按钮、失败面、提案列表、确认与汇总。
class _SelectedPhotoPanel extends ConsumerWidget {
  const _SelectedPhotoPanel({required this.image, required this.queue});

  final PendingHandwritingImage image;
  final HandwritingQueueState queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notifier = ref.read(handwritingQueueProvider.notifier);
    final relPath = image.relPath;

    final analyzing = queue.analyzing.contains(relPath);
    final applying = queue.applying.contains(relPath);
    final failure = queue.failures[relPath];
    // 失败时不拿旧提案出来显示：这次没整理成功，就不该看到上次的结果。
    final set = failure == null ? queue.sets[relPath] : null;
    final report =
        queue.lastReport?.sourceRef == relPath ? queue.lastReport : null;
    final remaining = set != null && _hasRemaining(queue, relPath, set);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.image_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    image.fileName,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: analyzing ? null : () => notifier.analyze(relPath),
                  icon: analyzing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high_outlined),
                  label: Text(
                    analyzing
                        ? l10n.handwritingQueueAnalyzing
                        : l10n.handwritingQueueAnalyze,
                  ),
                ),
                if (set != null || failure != null) ...[
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: applying ? null : () => notifier.forget(relPath),
                    icon: const Icon(Icons.undo),
                    label: Text(l10n.handwritingQueueForget),
                  ),
                ],
              ],
            ),
            if (analyzing)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (failure != null) ...[
              const SizedBox(height: 12),
              _FailureCard(reason: failure),
            ],
            if (set != null) ...[
              const SizedBox(height: 12),
              if (set.isEmpty)
                Text(l10n.handwritingQueueNothingFound)
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.handwritingQueueProposalsLabel,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: (applying || !remaining)
                          ? null
                          : () => notifier.applyAll(relPath),
                      icon: const Icon(Icons.done_all),
                      label: Text(
                        applying
                            ? l10n.handwritingQueueApplying
                            : l10n.handwritingQueueApplyAll,
                      ),
                    ),
                  ],
                ),
                for (final proposal in set.proposals)
                  _ProposalCard(
                    proposal: proposal,
                    applied: queue.isApplied(relPath, proposal.id),
                    applying: applying,
                    outcome: _outcomeOf(report, proposal.id),
                    onApply: () => notifier.applyProposal(relPath, proposal.id),
                    onEditForIntake:
                        proposal.kind == HandwritingProposalKind.question
                            ? () => unawaited(_editForIntake(
                                  context,
                                  ref,
                                  relPath,
                                  proposal,
                                ))
                            : null,
                  ),
              ],
            ],
            if (report != null) ...[
              const SizedBox(height: 12),
              Text(
                l10n.handwritingQueueReportSummary(
                  report.appliedCount,
                  report.failedCount,
                ),
                style: theme.textTheme.labelLarge,
              ),
            ],
            if (failure == null && set == null && !analyzing) ...[
              const SizedBox(height: 12),
              Text(l10n.handwritingQueueNotAnalyzed),
            ],
          ],
        ),
      ),
    );
  }

  /// 「编辑后保存」：把题目提案的草稿带到收题页校对（应用层只装配，不写库）。
  ///
  /// 返回 null 表示题干是空的：这类提案连草稿都装不出来，卡片上只显示提示，不给
  /// 这个入口。
  Future<void> _editForIntake(
    BuildContext context,
    WidgetRef ref,
    String relPath,
    HandwritingProposal proposal,
  ) async {
    final draft = await ref
        .read(handwritingProposalServiceProvider)
        .questionDraftForIntake(proposal);
    if (draft == null || !context.mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => QuestionIntakePage(
          initialDraft: draft,
          initialRelPath: relPath,
          initialProposalId: proposal.id,
        ),
      ),
    );
  }
}

/// 整理失败的如实显示：原因照抄，不吞掉、不美化。
class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.handwritingQueueFailureTitle,
            style: TextStyle(
              color: scheme.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            reason,
            style: TextStyle(color: scheme.onErrorContainer),
          ),
        ],
      ),
    );
  }
}

/// 一条待确认产物。
class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.applied,
    required this.applying,
    required this.outcome,
    required this.onApply,
    this.onEditForIntake,
  });

  final HandwritingProposal proposal;
  final bool applied;
  final bool applying;
  final HandwritingApplyOutcome? outcome;
  final VoidCallback onApply;

  /// 题目提案的「编辑后保存」入口；其它 kind 为 null（它们确认即入库）。
  final VoidCallback? onEditForIntake;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 三类产物的中文名来自领域层词表（`HandwritingProposalKind.labelZh`），
                // 与"标签树/知识点/闪存卡"这些既有词汇保持一致，不另立一套文案。
                Chip(
                  label: Text(proposal.kind.labelZh),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    proposal.titleZh,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (proposal.kind == HandwritingProposalKind.question)
              _QuestionProposalDetails(
                proposal: proposal,
                applied: applied,
                applying: applying,
                onEditForIntake: onEditForIntake,
              ),
            if (proposal.rationaleZh.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(proposal.rationaleZh),
            ],
            const SizedBox(height: 4),
            Text(
              l10n.handwritingProposalConfidence(
                _confidenceBand(l10n, proposal.confidence),
              ),
              style: theme.textTheme.bodySmall,
            ),
            if (proposal.cards.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                l10n.handwritingProposalCardCount(proposal.cards.length),
                style: theme.textTheme.labelLarge,
              ),
              for (final card in proposal.cards)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 8),
                  child: Text('• ${card.question}'),
                ),
            ],
            if (outcome != null) ...[
              const SizedBox(height: 8),
              Text(
                outcome!.ok
                    ? outcome!.detailZh
                    : (outcome!.failureReason ?? ''),
                style: TextStyle(
                  color: outcome!.ok ? scheme.primary : scheme.error,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: (applied || applying) ? null : onApply,
                icon: Icon(
                  applied ? Icons.check_circle_outline : Icons.check,
                ),
                label: Text(
                  applied
                      ? l10n.handwritingProposalApplied
                      : l10n.handwritingProposalApply,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _hasRemaining(
  HandwritingQueueState queue,
  String relPath,
  HandwritingProposalSet set,
) {
  for (final proposal in set.proposals) {
    if (!queue.isApplied(relPath, proposal.id)) {
      return true;
    }
  }
  return false;
}

HandwritingApplyOutcome? _outcomeOf(
  HandwritingApplyReport? report,
  String proposalId,
) {
  if (report == null) {
    return null;
  }
  for (final outcome in report.outcomes) {
    if (outcome.proposalId == proposalId) {
      return outcome;
    }
  }
  return null;
}

/// 置信度折成三档：数字给人"精确"的错觉，档位才是模型真正表达的东西。
String _confidenceBand(AppLocalizations l10n, double confidence) {
  if (confidence >= 0.75) {
    return l10n.handwritingProposalConfidenceHigh;
  }
  if (confidence >= 0.5) {
    return l10n.handwritingProposalConfidenceMedium;
  }
  return l10n.handwritingProposalConfidenceLow;
}

/// 解析摘要：卡片上只放一行，先折叠空白再截断；空解析返回空串。
String handwritingProposalSolutionSummary(String? raw, {int maxChars = 80}) {
  final collapsed = (raw ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.length <= maxChars) {
    return collapsed;
  }
  return '${collapsed.substring(0, maxChars)}…';
}

/// 题目提案的原文展示：题干、选项、答案、解析摘要，外加「编辑后保存」入口。
///
/// 题目是四类产物里唯一不能"确认即入库"的一种：确认只代表模型读对了，真正建题
/// 要先生成 [QuestionDraft] 带到收题页校对，用户按「入库」才写库。这里显示的是
/// 模型读出来的原文，不做润色；没认出题干时只给提示、不给入口。
class _QuestionProposalDetails extends StatelessWidget {
  const _QuestionProposalDetails({
    required this.proposal,
    required this.applied,
    required this.applying,
    required this.onEditForIntake,
  });

  final HandwritingProposal proposal;
  final bool applied;
  final bool applying;
  final VoidCallback? onEditForIntake;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stem = (proposal.fields['stem'] ?? '').trim();
    if (stem.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 18, color: scheme.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.handwritingQuestionMissingStem,
                style: TextStyle(color: scheme.error),
              ),
            ),
          ],
        ),
      );
    }
    final answer = (proposal.fields['answer'] ?? '').trim();
    final solution = handwritingProposalSolutionSummary(
      proposal.fields['solution'],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            stem,
            key: Key('handwriting-question-stem-${proposal.id}'),
          ),
          if (proposal.options.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.handwritingQuestionOptions(proposal.options.length),
              style: theme.textTheme.labelLarge,
            ),
            for (final option in proposal.options)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 8),
                child: Text('${option.label}. ${option.content}'),
              ),
          ],
          const SizedBox(height: 6),
          Text(
            l10n.handwritingQuestionAnswer(
              answer.isEmpty ? l10n.handwritingQuestionEmptyValue : answer,
            ),
          ),
          Text(
            l10n.handwritingQuestionSolution(
              solution.isEmpty ? l10n.handwritingQuestionEmptyValue : solution,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: Key('handwriting-question-edit-${proposal.id}'),
              onPressed: (applied || applying) ? null : onEditForIntake,
              icon: const Icon(Icons.edit_note),
              label: Text(l10n.handwritingQuestionEditForIntake),
            ),
          ),
        ],
      ),
    );
  }
}
