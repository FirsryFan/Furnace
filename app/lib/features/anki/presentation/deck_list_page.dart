import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/review_plan_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../application/deck_progress.dart';
import 'review_page.dart';
import 'review_plan_page.dart';

/// 「全部」这一行：今天的总队列，不按卡组切。
const Key deckListAllTileKey = Key('deck-list-all');

/// 「未分组」这一行（只有存在没打标签的卡时才画）。
const Key deckListUngroupedTileKey = Key('deck-list-ungrouped');

/// 空态里的「新建卡组」。
const Key deckListCreateButtonKey = Key('deck-list-create');

/// AppBar 上进卡组设置的入口。
const Key deckListSettingsActionKey = Key('deck-list-settings');

/// 一张卡组行（测试与点击目标都能按 tagId 定位）。
Key deckListTileKey(String tagId) => ValueKey<String>('deck-list-$tagId');

/// 卡组行上的「今日目标已达成」徽标。
Key deckListProgressDoneKey(String tagId) =>
    ValueKey<String>('deck-list-done-$tagId');

/// 复习 Tab 的主界面：卡组列表加今天每组的进度。
///
/// 复习原来是「点进来直接做题」，卡组只藏在设置里；用户要的是先看卡组、
/// 再决定进哪一组（m20816）。这一页就是那一步：每一行是 [ReviewPlanPage]
/// 里配好的一个卡组，副标题是今天的新卡/复习进度，点进去只复习这一组。
///
/// 「全部」仍然是原样：不带 scope 的 [ReviewPage]，今天的总队列。
/// 「未分组」只在真的有卡不属于任何卡组时出现——那是一句提醒，不是第三类卡组。
///
/// 进度只来自 [DeckProgress]（[deckProgressFor]），这里不再推导一遍：卡片
/// 列表和卡组计划页对同一天的数字必须一致。
class DeckListPage extends ConsumerWidget {
  const DeckListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plans = ref.watch(reviewGroupPlansProvider);
    final load = ref.watch(reviewDayLoadProvider);
    final ungrouped =
        ref.watch(ungroupedKnowledgePointsProvider).valueOrNull ?? 0;

    final Widget body;
    if (plans.isLoading || load.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (plans.hasError || load.hasError) {
      body = _LoadErrorState(
        message: '${plans.error ?? load.error}',
        onRetry: () {
          ref.invalidate(reviewGroupPlansProvider);
          ref.invalidate(reviewDayLoadProvider);
        },
      );
    } else {
      final groups = load.requireValue.groups;
      body = groups.isEmpty
          ? _EmptyState(onCreate: () => _openPlans(context))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                _DeckCard(
                  key: deckListAllTileKey,
                  onTap: () => _openReview(
                    context,
                    ref,
                    title: l10n.deckListAllTitle,
                  ),
                  child: ListTile(
                    title: Text(l10n.deckListAllTitle),
                    subtitle: Text(l10n.deckListAllHint),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
                for (final group in groups)
                  _GroupRow(
                    key: deckListTileKey(group.plan.tagId),
                    group: group,
                    onTap: () => _openReview(
                      context,
                      ref,
                      title: group.plan.tagPath,
                      scopeTagId: group.plan.tagId,
                    ),
                  ),
                if (ungrouped > 0)
                  _DeckCard(
                    key: deckListUngroupedTileKey,
                    onTap: () => _openReview(
                      context,
                      ref,
                      title: l10n.deckListUngroupedTitle,
                      onlyUngrouped: true,
                    ),
                    child: ListTile(
                      title: Text(l10n.deckListUngroupedTitle),
                      subtitle: Text(l10n.deckListUngroupedHint),
                      trailing: Text('$ungrouped'),
                    ),
                  ),
              ],
            );
    }

    // 只返回 body：外层 KnowledgePage 已经有 Scaffold/AppBar，这里再套一层
    // 会出现上下两条标题栏。标题与「卡组设置」入口都上移到 KnowledgePage。
    return body;
  }

  Future<void> _openReview(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    String? scopeTagId,
    bool onlyUngrouped = false,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: ReviewPage(
            scopeTagId: scopeTagId,
            scopeTitle: title,
            onlyUngrouped: onlyUngrouped,
          ),
        ),
      ),
    );
    if (context.mounted) {
      // 答完卡回来，列表上的进度必须已经是新的。判分本身会写 review_logs、
      // dataRevision 会变，这里是一次兜底读取，不另造 provider。
      ref.invalidate(reviewDayLoadProvider);
    }
  }

  Future<void> _openPlans(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const ReviewPlanPage(),
      ),
    );
  }
}

/// 一行卡组：名字 + 今日进度 + 进度条。
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    super.key,
    required this.group,
    required this.onTap,
  });

  final ReviewGroupLoad group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final progress = deckProgressFor(group);
    final reviewTarget = progress.reviewTarget;
    return _DeckCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    group.plan.tagPath,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (progress.isComplete)
                  Row(
                    key: deckListProgressDoneKey(group.plan.tagId),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n.deckProgressDone,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                const Icon(Icons.chevron_right),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              l10n.deckNewCards(progress.newDone, progress.newTarget),
              style: theme.textTheme.bodySmall,
            ),
            Text(
              reviewTarget == null
                  ? l10n.deckReviewsUnlimited(progress.reviewDone)
                  : l10n.deckReviews(progress.reviewDone, reviewTarget),
              style: theme.textTheme.bodySmall,
            ),
            if (progress.fraction != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress.fraction,
                minHeight: 6,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一张可点的卡片，统一圆角、边距与点击态。
class _DeckCard extends StatelessWidget {
  const _DeckCard({
    super.key,
    required this.child,
    required this.onTap,
  });

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: child,
      ),
    );
  }
}

/// 一个卡组都没有：说明卡组是什么，并把新建入口放在这里。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.layers_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.deckListEmptyTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.deckListEmptyBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: deckListCreateButtonKey,
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text(l10n.deckListCreate),
            ),
          ],
        ),
      ),
    );
  }
}

/// 读不到卡组/计划时的状态：给出错误原文和一个重试入口，不假装是空。
class _LoadErrorState extends StatelessWidget {
  const _LoadErrorState({required this.message, required this.onRetry});

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
            Icon(
              Icons.error_outline,
              size: 40,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
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
