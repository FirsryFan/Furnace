/// 组卷页「手工指定 / 排除」的界面契约：状态只写 `paperSpecProvider`，结果只读 `PaperPlan`。
///
/// 分工（与学科/领域配额同一套纪律）：
/// 1. 名单状态只认 [PaperSpecNotifier]（toggleManualInclude / toggleManualExclude /
///    clearManualSelection）：页面不自己存一份「已选题目」；
/// 2. 卷子生成后的问题名单全部来自 [PaperPlan]：missing（题库里没有）、
///    skipped（被目标题数挤掉）、conflict（与排除冲突）——只报不改，不静默丢；
/// 3. 题号用 [QuestionSerialBadgeById] 异步读，题干用 `questionStemDisplayProvider`
///    （快照感知：有正文摘录用摘录，没有就用「整题截图」标签）；候选过滤仍用
///    `questionStemsProvider` 的原题干（避免只搜到截断/清洗后的预览）；
///    找不到的 id（缺失名单）直接显示原始 id，不摆「未编号」冒充一道题。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/paper/paper_composer.dart';
import '../../../l10n/app_localizations.dart';
import '../application/paper_plan_provider.dart';
import '../application/question_stem_display_provider.dart';
import 'question_media_view.dart';

/// 已选手工名单卡片（名单为空时不渲染）。
const Key paperManualSelectionSectionKey =
    Key('paper-manual-selection-section');

/// 「选择题」入口：名单空不空都摆，否则清空之后就加不回来。
const Key paperManualSelectionAddKey = Key('paper-manual-selection-add');

/// 一键清空两个名单。
const Key paperManualSelectionClearKey = Key('paper-manual-selection-clear');

/// 卷子生成后的手工名单结果卡。
const Key paperManualSelectionOutcomeKey =
    Key('paper-manual-selection-outcome');

/// 选题对话框（含搜索框与候选列表）。
const Key paperManualSelectionPickerKey = Key('paper-manual-selection-picker');
const Key paperManualSelectionPickerFilterKey =
    Key('paper-manual-selection-picker-filter');

/// 必收名单一行。
Key paperManualSelectionIncludeRowKey(String questionId) =>
    Key('paper-manual-include-$questionId');

/// 排除名单一行。
Key paperManualSelectionExcludeRowKey(String questionId) =>
    Key('paper-manual-exclude-$questionId');

/// 必收名单行内的「移除」。
Key paperManualSelectionIncludeRemoveKey(String questionId) =>
    Key('paper-manual-include-remove-$questionId');

/// 排除名单行内的「移除」。
Key paperManualSelectionExcludeRemoveKey(String questionId) =>
    Key('paper-manual-exclude-remove-$questionId');

/// 选题对话框里「设为必收」。
Key paperManualPickerIncludeKey(String questionId) =>
    Key('paper-manual-picker-include-$questionId');

/// 选题对话框里「设为排除」。
Key paperManualPickerExcludeKey(String questionId) =>
    Key('paper-manual-picker-exclude-$questionId');

/// 名单展示顺序：题 id 去空、去重、字典序 —— spec 里是 Set，排序后页面与测试都稳定。
List<String> paperManualSortedIds(Iterable<String>? ids) {
  final unique = <String>{
    for (final id in ids ?? const <String>[])
      if (id.trim().isNotEmpty) id.trim(),
  }.toList()
    ..sort();
  return unique;
}

/// 题干一行预览：折掉换行/制表与连续空白，超长截断加省略号。
String paperManualStemPreview(String stem, {int maxChars = 20}) {
  final folded = stem.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (folded.isEmpty || maxChars <= 0) return folded;
  if (folded.length <= maxChars) return folded;
  return '${folded.substring(0, maxChars)}…';
}

/// 一行题干：display 为空或文本为空时回退题号；否则折白/截断（[paperManualStemPreview]）。
String _stemTextOf(String questionId, QuestionStemDisplay? display) {
  final text = display?.text.trim() ?? '';
  if (text.isEmpty) return questionId;
  return paperManualStemPreview(display!.text);
}

/// 一次读全表的题干一行文本；数据未到时用空 map（各行回退成题号）。
Map<String, QuestionStemDisplay> _watchStemDisplays(WidgetRef ref) =>
    ref.watch(questionStemDisplayProvider).maybeWhen(
          data: (value) => value,
          orElse: () => const <String, QuestionStemDisplay>{},
        );

/// 快照题的小标签：只在「有正文摘录」时摆——没有摘录时 [QuestionStemDisplay.text]
/// 本身就是「整题截图 · N 处公式/图」，再摆一次会重复（照题库列表的同一条口径）。
bool _showsSnapshotBadge(QuestionStemDisplay? display) =>
    display != null && display.isSnapshot && display.hasExcerpt;

/// 「整题截图」小标签（不加卡片，只占行尾一小段）。
Widget _snapshotBadge(BuildContext context) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Text(
      AppLocalizations.of(context).questionBankSnapshotBadge,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// 候选过滤：题干或题目 id 包含 query（不区分大小写）；空 query 全留。
List<PaperCandidate> paperManualFilterCandidates(
  List<PaperCandidate> candidates,
  Map<String, String> stems,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return candidates;
  return <PaperCandidate>[
    for (final candidate in candidates)
      if (candidate.questionId.toLowerCase().contains(needle) ||
          (stems[candidate.questionId] ?? '').toLowerCase().contains(needle))
        candidate,
  ];
}

/// 卷子生成后要不要报的三类手工名单。
enum PaperManualIssueKind { missing, skipped, conflict }

/// 一类名单：只展示前 [visibleIds]，其余用 [hiddenCount] 报数量。
class PaperManualIssueGroup {
  const PaperManualIssueGroup({
    required this.kind,
    required this.visibleIds,
    required this.totalCount,
  });

  final PaperManualIssueKind kind;
  final List<String> visibleIds;
  final int totalCount;

  int get hiddenCount => totalCount - visibleIds.length;

  bool get hasHidden => hiddenCount > 0;
}

/// 三类问题名单按 缺失 → 被目标题数挤掉 → 冲突 的顺序聚合；每类最多
/// [maxPerGroup] 条，其余只报数量（卷面不铺一屏 id）。
List<PaperManualIssueGroup> paperManualIssueGroups(
  PaperPlan plan, {
  int maxPerGroup = 3,
}) {
  final groups = <PaperManualIssueGroup>[];
  void add(PaperManualIssueKind kind, List<String> ids) {
    if (ids.isEmpty) return;
    final limit = maxPerGroup < 1 ? 1 : maxPerGroup;
    groups.add(
      PaperManualIssueGroup(
        kind: kind,
        visibleIds: ids.take(limit).toList(growable: false),
        totalCount: ids.length,
      ),
    );
  }

  add(PaperManualIssueKind.missing, plan.manualMissingQuestionIds);
  add(PaperManualIssueKind.skipped, plan.manualSkippedQuestionIds);
  add(PaperManualIssueKind.conflict, plan.manualConflictQuestionIds);
  return groups;
}

/// 结果卡是否该出现：启用了手工选择，且确实有「收下/缺失/挤掉/冲突」要说的事。
bool paperManualOutcomeVisible(PaperPlan plan) {
  if (!plan.manualSelectionEnabled) return false;
  return plan.manualIncludedCount > 0 ||
      plan.manualMissingQuestionIds.isNotEmpty ||
      plan.manualSkippedQuestionIds.isNotEmpty ||
      plan.manualConflictQuestionIds.isNotEmpty;
}

/// 「选择题」入口：不论名单空不空都摆（否则清空后就再也加不回来）。
class PaperManualSelectionButton extends ConsumerWidget {
  const PaperManualSelectionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: paperManualSelectionAddKey,
        onPressed: () => _openPaperManualSelectionDialog(context),
        icon: const Icon(Icons.playlist_add, size: 18),
        label: Text(l10n.paperManualSelectionAdd),
      ),
    );
  }
}

Future<void> _openPaperManualSelectionDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _PaperManualSelectionDialog(),
  );
}

/// 当前名单：必收/排除两栏 + 行内移除 + 一键清空；名单为空时整卡不渲染。
class PaperManualSelectionSection extends ConsumerWidget {
  const PaperManualSelectionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final spec = ref.watch(paperSpecProvider);
    final includeIds = paperManualSortedIds(spec.manualIncludeQuestionIds);
    final excludeIds = paperManualSortedIds(spec.manualExcludeQuestionIds);
    if (includeIds.isEmpty && excludeIds.isEmpty) {
      return const SizedBox.shrink();
    }
    final displays = _watchStemDisplays(ref);
    final notifier = ref.read(paperSpecProvider.notifier);

    return Card(
      key: paperManualSelectionSectionKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.paperManualSelectionTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.paperManualSelectionHint,
              style: theme.textTheme.bodySmall,
            ),
            if (includeIds.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                l10n.paperManualSelectionIncludeTitle(includeIds.length),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final questionId in includeIds)
                _ManualSelectionRow(
                  key: paperManualSelectionIncludeRowKey(questionId),
                  questionId: questionId,
                  display: displays[questionId],
                  removeKey: paperManualSelectionIncludeRemoveKey(questionId),
                  onRemove: () => notifier.toggleManualInclude(questionId),
                ),
            ],
            if (excludeIds.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                l10n.paperManualSelectionExcludeTitle(excludeIds.length),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final questionId in excludeIds)
                _ManualSelectionRow(
                  key: paperManualSelectionExcludeRowKey(questionId),
                  questionId: questionId,
                  display: displays[questionId],
                  removeKey: paperManualSelectionExcludeRemoveKey(questionId),
                  onRemove: () => notifier.toggleManualExclude(questionId),
                ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: paperManualSelectionClearKey,
                onPressed: notifier.clearManualSelection,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: Text(l10n.paperManualSelectionClear),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualSelectionRow extends StatelessWidget {
  const _ManualSelectionRow({
    super.key,
    required this.questionId,
    required this.display,
    required this.removeKey,
    required this.onRemove,
  });

  final String questionId;
  final QuestionStemDisplay? display;
  final Key removeKey;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = _stemTextOf(questionId, display);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          QuestionSerialBadgeById(questionId: questionId, copyable: false),
          const SizedBox(width: 8),
          Expanded(child: Text(text, overflow: TextOverflow.ellipsis)),
          if (_showsSnapshotBadge(display)) _snapshotBadge(context),
          IconButton(
            key: removeKey,
            tooltip: l10n.paperManualSelectionRemove,
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

/// 选题对话框：搜索 + 候选列表 + 每题「设为必收 / 设为排除」。
///
/// 两个开关互不排斥（冲突由域层按「排除优先」判定并记进冲突名单）：
/// 界面只负责把用户的选择如实写进 spec，不替用户悄悄改另一份名单。
class _PaperManualSelectionDialog extends ConsumerStatefulWidget {
  const _PaperManualSelectionDialog();

  @override
  ConsumerState<_PaperManualSelectionDialog> createState() =>
      _PaperManualSelectionDialogState();
}

class _PaperManualSelectionDialogState
    extends ConsumerState<_PaperManualSelectionDialog> {
  final TextEditingController _filterController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final spec = ref.watch(paperSpecProvider);
    final includeIds = spec.manualIncludeQuestionIds ?? const <String>{};
    final excludeIds = spec.manualExcludeQuestionIds ?? const <String>{};
    final notifier = ref.read(paperSpecProvider.notifier);
    final corpus = ref.watch(paperCorpusProvider);
    final stems = ref.watch(questionStemsProvider).maybeWhen(
          data: (value) => value,
          orElse: () => const <String, String>{},
        );
    final displays = _watchStemDisplays(ref);

    return AlertDialog(
      key: paperManualSelectionPickerKey,
      title: Text(l10n.paperManualSelectionPickerTitle),
      content: SizedBox(
        width: 560,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              key: paperManualSelectionPickerFilterKey,
              controller: _filterController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.paperManualSelectionPickerFilterHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.paperManualSelectionHint,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: corpus.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Text(
                  l10n.paperManualSelectionPickerFailed('$error'),
                ),
                data: (value) {
                  final candidates = paperManualFilterCandidates(
                    value.candidates,
                    stems,
                    _query,
                  );
                  if (candidates.isEmpty) {
                    return Text(l10n.paperManualSelectionPickerNone);
                  }
                  return ListView.builder(
                    itemCount: candidates.length,
                    itemBuilder: (context, index) {
                      final candidate = candidates[index];
                      final id = candidate.questionId;
                      return _ManualPickerRow(
                        questionId: id,
                        display: displays[id],
                        included: includeIds.contains(id),
                        excluded: excludeIds.contains(id),
                        onToggleInclude: () => notifier.toggleManualInclude(id),
                        onToggleExclude: () => notifier.toggleManualExclude(id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }
}

class _ManualPickerRow extends StatelessWidget {
  const _ManualPickerRow({
    required this.questionId,
    required this.display,
    required this.included,
    required this.excluded,
    required this.onToggleInclude,
    required this.onToggleExclude,
  });

  final String questionId;
  final QuestionStemDisplay? display;
  final bool included;
  final bool excluded;
  final VoidCallback onToggleInclude;
  final VoidCallback onToggleExclude;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final text = _stemTextOf(questionId, display);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          QuestionSerialBadgeById(questionId: questionId, copyable: false),
          const SizedBox(width: 8),
          Expanded(child: Text(text, overflow: TextOverflow.ellipsis)),
          if (_showsSnapshotBadge(display)) _snapshotBadge(context),
          IconButton(
            key: paperManualPickerIncludeKey(questionId),
            tooltip: l10n.paperManualSelectionPickerInclude,
            onPressed: onToggleInclude,
            icon: Icon(
              included ? Icons.playlist_add_check : Icons.playlist_add,
              size: 20,
              color: included ? theme.colorScheme.primary : null,
            ),
          ),
          IconButton(
            key: paperManualPickerExcludeKey(questionId),
            tooltip: l10n.paperManualSelectionPickerExclude,
            onPressed: onToggleExclude,
            icon: Icon(
              excluded ? Icons.block : Icons.remove_circle_outline,
              size: 20,
              color: excluded ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// 生成后的手工名单结果卡：收下几道 + 三类问题名单（每类最多 3 条）。
class PaperManualSelectionOutcome extends ConsumerWidget {
  const PaperManualSelectionOutcome({super.key, required this.plan});

  final PaperPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!paperManualOutcomeVisible(plan)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final groups = paperManualIssueGroups(plan);
    final displays = _watchStemDisplays(ref);

    return Card(
      key: paperManualSelectionOutcomeKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (plan.manualIncludedCount > 0) ...[
              Text(
                l10n.paperManualSelectionOutcomeIncluded(
                  plan.manualIncludedCount,
                ),
                style: theme.textTheme.titleSmall,
              ),
              if (groups.isNotEmpty) const SizedBox(height: 12),
            ],
            for (var index = 0; index < groups.length; index++) ...[
              if (index > 0) const SizedBox(height: 12),
              Text(
                _issueGroupTitle(l10n, groups[index]),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final questionId in groups[index].visibleIds)
                _ManualIssueRow(
                  questionId: questionId,
                  display: displays[questionId],
                ),
              if (groups[index].hasHidden)
                Text(
                  l10n.paperManualSelectionMore(
                    groups[index].hiddenCount,
                  ),
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String _issueGroupTitle(AppLocalizations l10n, PaperManualIssueGroup group) {
  switch (group.kind) {
    case PaperManualIssueKind.missing:
      return l10n.paperManualSelectionMissingTitle(group.totalCount);
    case PaperManualIssueKind.skipped:
      return l10n.paperManualSelectionSkippedTitle(group.totalCount);
    case PaperManualIssueKind.conflict:
      return l10n.paperManualSelectionConflictTitle(group.totalCount);
  }
}

class _ManualIssueRow extends StatelessWidget {
  const _ManualIssueRow({required this.questionId, required this.display});

  final String questionId;
  final QuestionStemDisplay? display;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (display == null || display!.text.trim().isEmpty) {
      // 题库里根本没有这个 id：直接显示原始 id，不摆「未编号」冒充一道题。
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(questionId, style: textTheme.bodySmall),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          QuestionSerialBadgeById(questionId: questionId, copyable: false),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _stemTextOf(questionId, display),
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall,
            ),
          ),
          if (_showsSnapshotBadge(display)) _snapshotBadge(context),
        ],
      ),
    );
  }
}
