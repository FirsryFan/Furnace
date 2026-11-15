/// 标签知识入口页：一个标签（可选整棵子树）下挂着的题 / 卡 / 任务。
///
/// 产品要求（`REMAINING-TASKS-2026-11-15.md` B8）：标签页不再只是标签树，
/// 选中标签后要能直接看到并进入题、卡、任务。查询统一走
/// `TagKnowledgeIndex`（契约 §4.3），这一页只负责展示与导航：
///
///  * 三块各自带数量；空块写「暂无」，不造行；
///  * 题 → `QuestionDetailPage`，任务 → `TaskDetailPage`；
///  * 卡 → 只读卡详情弹窗（现有路由里没有独立的卡详情页）；卡属于某个已配置
///    卡组时，弹窗里给「去复习卡组」按钮，走既有 `ReviewPage(scopeTagId:)`；
///  * 关系只来自 `object_tags` / 知识点 → 卡模板；`content_refs` 没有 tag 列，
///    不能按标签过滤，所以不参与这里（页面不拿它冒充关系）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../domain/services/questions/question_number.dart';
import '../../../domain/services/questions/question_stem_preview.dart';
import '../../../l10n/app_localizations.dart';
import '../../anki/presentation/review_page.dart';
import '../../questions/presentation/question_detail_page.dart';
import '../../tasks/presentation/task_detail_page.dart';
import '../../tasks/presentation/widgets/task_status_actions.dart';
import '../application/tag_knowledge_entry_providers.dart';
import '../application/tag_knowledge_index.dart';

/// 块标题上的数量角标（与标签树的内容量角标同一形状，但键独立）。
Key tagKnowledgeCountKey(String block) =>
    ValueKey<String>('tag-knowledge-count-$block');

/// 空态文案的键（测试与无障碍都能按块定位，而不靠中文硬编码）。
Key tagKnowledgeEmptyKey(String block) =>
    ValueKey<String>('tag-knowledge-empty-$block');

/// 范围开关的键。
const Key tagKnowledgeScopeSwitchKey = Key('tag-knowledge-scope-switch');

/// 一个标签的知识入口页。
class TagKnowledgeEntryPage extends ConsumerStatefulWidget {
  const TagKnowledgeEntryPage({
    super.key,
    required this.tagId,
    required this.tagLabel,
    this.initialIncludeDescendants = false,
  });

  /// 要看的标签 id。标签在打开前被删掉时页面如实说「已不存在」。
  final String tagId;

  /// 标签的显示名（`path` 优先），用作 AppBar 标题；查询本身只认 [tagId]。
  final String tagLabel;

  /// 首次打开时「含子标签」的开关状态；默认只看直挂对象。
  final bool initialIncludeDescendants;

  @override
  ConsumerState<TagKnowledgeEntryPage> createState() =>
      _TagKnowledgeEntryPageState();
}

class _TagKnowledgeEntryPageState extends ConsumerState<TagKnowledgeEntryPage> {
  late bool _includeDescendants;

  @override
  void initState() {
    super.initState();
    _includeDescendants = widget.initialIncludeDescendants;
  }

  TagKnowledgeQuery get _query =>
      (tagId: widget.tagId, includeDescendants: _includeDescendants);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snapshotAsync = ref.watch(tagKnowledgeSnapshotProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.tagLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: l10n.commonRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(tagKnowledgeSnapshotProvider(_query));
            },
          ),
        ],
      ),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _LoadFailed(
          message: l10n.tagKnowledgeLoadFailed('$error'),
          onRetry: () => ref.invalidate(tagKnowledgeSnapshotProvider(_query)),
        ),
        data: (snapshot) {
          if (snapshot.isMissingTag) {
            return _CenteredMessage(
              icon: Icons.sell_outlined,
              message: l10n.tagKnowledgeTagMissing,
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  l10n.tagKnowledgeEntryIntro,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              SwitchListTile(
                key: tagKnowledgeScopeSwitchKey,
                value: _includeDescendants,
                title: Text(l10n.tagKnowledgeIncludeDescendants),
                subtitle: Text(l10n.tagKnowledgeIncludeDescendantsHint),
                onChanged: (value) {
                  setState(() => _includeDescendants = value);
                },
              ),
              _KnowledgeSection(
                block: 'questions',
                icon: Icons.quiz_outlined,
                title: l10n.tagKnowledgeQuestions,
                count: snapshot.questions.length,
                emptyText: l10n.tagKnowledgeEmptyQuestions,
                children: [
                  for (final question in snapshot.questions)
                    _QuestionRow(
                      key: ValueKey<String>(
                          'tag-knowledge-question-${question.id}'),
                      question: question,
                      onTap: () => _openQuestion(question.id),
                    ),
                ],
              ),
              _KnowledgeSection(
                block: 'cards',
                icon: Icons.style_outlined,
                title: l10n.tagKnowledgeFlashcards,
                count: snapshot.cards.length,
                emptyText: l10n.tagKnowledgeEmptyFlashcards,
                children: [
                  for (final card in snapshot.cards)
                    _CardRow(
                      key: ValueKey<String>('tag-knowledge-card-${card.id}'),
                      card: card,
                      onTap: () => _openCardPreview(card, snapshot.reviewGroup),
                    ),
                ],
              ),
              _KnowledgeSection(
                block: 'tasks',
                icon: Icons.task_alt_outlined,
                title: l10n.tagKnowledgeTasks,
                count: snapshot.tasks.length,
                emptyText: l10n.tagKnowledgeEmptyTasks,
                children: [
                  for (final task in snapshot.tasks)
                    _TaskRow(
                      key: ValueKey<String>('tag-knowledge-task-${task.id}'),
                      task: task,
                      onTap: () => _openTask(task.id),
                    ),
                ],
              ),
              if (snapshot.missingTargets > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    l10n.tagKnowledgeMissingTargets(snapshot.missingTargets),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _openQuestion(String questionId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuestionDetailPage(questionId: questionId),
      ),
    );
  }

  void _openTask(String taskId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaskDetailPage(taskId: taskId),
      ),
    );
  }

  /// 只读卡详情弹窗；卡属于某个已配置卡组时，弹窗里给「去复习」按钮。
  Future<void> _openCardPreview(
    TagKnowledgeCard card,
    TagKnowledgeReviewGroup? reviewGroup,
  ) async {
    final l10n = AppLocalizations.of(context);
    final addReview = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.tagKnowledgeCardPreviewTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (card.knowledgePointTitle != null)
                  Text(
                    l10n.tagKnowledgeCardKnowledgePoint(
                      card.knowledgePointTitle!,
                    ),
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                const SizedBox(height: 12),
                _DialogLabel(l10n.tagKnowledgeCardFront),
                Text(
                  card.template.question.isEmpty
                      ? l10n.tagKnowledgeQuestionNoStem
                      : card.template.question,
                ),
                const SizedBox(height: 12),
                _DialogLabel(l10n.tagKnowledgeCardAnswer),
                Text(card.template.answer),
                if ((card.template.hint ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _DialogLabel(l10n.tagKnowledgeCardHint),
                  Text(card.template.hint!),
                ],
                if (reviewGroup == null) ...[
                  const SizedBox(height: 16),
                  Text(
                    l10n.tagKnowledgeNoReviewGroup,
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonClose),
          ),
          if (reviewGroup != null)
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                l10n.tagKnowledgeCardReview(reviewGroup.tagPath),
              ),
            ),
        ],
      ),
    );
    if (addReview != true || !mounted) {
      return;
    }
    final group = reviewGroup;
    if (group == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(group.tagPath)),
          body: ReviewPage(
            scopeTagId: group.tagId,
            scopeTitle: group.tagPath,
          ),
        ),
      ),
    );
  }
}

/// 一块（题/卡/任务）：标题 + 数量角标 + 行或「暂无」。
class _KnowledgeSection extends StatelessWidget {
  const _KnowledgeSection({
    required this.block,
    required this.icon,
    required this.title,
    required this.count,
    required this.emptyText,
    required this.children,
  });

  /// `questions` / `cards` / `tasks`：只用于测试键，不参与查询。
  final String block;
  final IconData icon;
  final String title;
  final int count;
  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              _CountBadge(
                key: tagKnowledgeCountKey(block),
                count: count,
              ),
            ],
          ),
        ),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              key: tagKnowledgeEmptyKey(block),
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 16,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Text(
                  emptyText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          )
        else
          ...children,
        const Divider(height: 1),
      ],
    );
  }
}

/// 数量角标：真实行数，不四舍五入、不留白。
class _CountBadge extends StatelessWidget {
  const _CountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// 一行题目：题名（没名字用题干摘要）→ 题号 · 来源。
class _QuestionRow extends StatelessWidget {
  const _QuestionRow({super.key, required this.question, required this.onTap});

  final Question question;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = (question.title ?? '').trim();
    final subtitleParts = <String>[
      questionSerialLabel(question.serialNo),
      if (question.sourceLabel.trim().isNotEmpty) question.sourceLabel.trim(),
    ];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: const Icon(Icons.quiz_outlined),
      title: Text(
        title.isNotEmpty
            ? title
            : _stemTitle(question.stem, l10n.tagKnowledgeQuestionNoStem),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitleParts.join(' · ')),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  static String _stemTitle(String stem, String fallback) {
    final preview = questionStemPreview(stem);
    return preview.isEmpty ? fallback : preview;
  }
}

/// 一行闪存卡：正面摘要 → 题型 · 所属知识点。
class _CardRow extends StatelessWidget {
  const _CardRow({super.key, required this.card, required this.onTap});

  final TagKnowledgeCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final parts = <String>[
      _cardTypeLabel(l10n, card.template.type),
      if ((card.knowledgePointTitle ?? '').trim().isNotEmpty)
        card.knowledgePointTitle!.trim(),
    ];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: const Icon(Icons.style_outlined),
      title: Text(
        _preview(card.template.question, l10n.tagKnowledgeQuestionNoStem),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(parts.join(' · ')),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  static String _preview(String text, String fallback) {
    final preview = questionStemPreview(text, maxLength: 80);
    return preview.isEmpty ? fallback : preview;
  }
}

/// 一行任务：标题 → 流程状态。
class _TaskRow extends StatelessWidget {
  const _TaskRow({super.key, required this.task, required this.onTap});

  final Task task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: const Icon(Icons.task_alt_outlined),
      title: Text(
        task.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(taskStatusLabel(l10n, task)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _DialogLabel extends StatelessWidget {
  const _DialogLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .labelMedium
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// 卡模板类型 → 现有中文题型名；认不出的类型给「卡片」，不猜成三种之一。
String _cardTypeLabel(AppLocalizations l10n, String type) => switch (type) {
      'mcq' => l10n.ankiTypeMcq,
      'fill_blank' => l10n.ankiTypeFillBlank,
      'essay' => l10n.ankiTypeEssay,
      _ => l10n.tagKnowledgeCardTypeUnknown,
    };
