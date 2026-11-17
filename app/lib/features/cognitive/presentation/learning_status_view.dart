/// 用户层「学习状态」看板：学习状态首页的四块内容。
///
/// 用户反馈（task-103）：MindNet 的测试入口、评价体系、可视化太复杂，用户看什么
/// 与开发者看什么没分开。这一层只放**用户需要看的四件事**：
///
/// 1. 当前档位 S/A/B/C/D/`?`（不显示精确分数与模型参数）；
/// 2. 3 个强项 + 3 个弱项（知识点，带证据状态）；
/// 3. 今日复习/任务数量 + 一个主按钮（开始复习）；
/// 4. 一句话趋势（最近一周复习），没有数据就说「证据不足」。
///
/// **数字来源（2026-11-17 学习状态清理）**：这一层没有任何 MindNet 专属读数。
/// 档位与强项/弱项来自 `cognitiveReadingsProvider` 的卡片读数 `R = R0 * Psi(t/S)`，
/// 而那条链的输入是 `card_states` / `card_templates` / `knowledge_points`（见
/// `cognitive/application/library_diagnosis_reader.dart` 的
/// `readCognitiveObservationInputs`）；没有复习记录时档位退回学生预设起点。
/// 今日待复习来自到期卡队列，今日任务来自任务表，趋势来自 `review_logs`。
/// 因此页面对用户的说法只能是「来自复习记录」，不能叫「MindNet 认知评价」。
///
/// 旧 MindNet 的「知识网络图」不再出现在用户学习状态页（只保留在设置页
/// 开发者分区的 `CognitiveDeveloperPage` 里，作为开发者旧功能）。
///
/// 开发者字段（模型 id、R0/Gain/Σ、band/zone、每卡 due/interval、calibration、
/// orphan、fast layer、prior count、机制参数）全部在 `CognitiveDeveloperPage`，
/// 由设置页的「开发者信息」进入，默认不出现在这一层。
///
/// 这一层的数字全部来自既有 provider（`cognitiveReadingsProvider`、到期卡队列、
/// 任务表、复习日志），**不新增第二套算法**：折算规则在
/// `domain/services/cognitive/learning_status.dart`（纯函数，有单测）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/cognitive/ability_band.dart'
    show AbilitySource, AbilityUnknownReason;
import '../../../domain/services/cognitive/learning_status.dart';
import '../../../domain/services/cognitive/preset_prior.dart';
import '../../student_preset/application/preset_selection.dart';
import '../application/preset_matrix_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../anki/presentation/review_page.dart';
import 'cognitive_model_page.dart' show cognitiveReadingsProvider;
import 'today_plan_page.dart';

/// 档位卡：大字档位 + 一句依据。测试与将来首页卡片共用定位点。
const Key learningStatusBandKey = Key('learning-status-band');
const Key learningStatusStrengthsKey = Key('learning-status-strengths');
const Key learningStatusWeaknessesKey = Key('learning-status-weaknesses');
const Key learningStatusTodayKey = Key('learning-status-today');
const Key learningStatusTrendKey = Key('learning-status-trend');

/// 「开始复习」主按钮。
const Key mindnetStartReviewKey = Key('mindnet-start-review');

/// 入口：今日清单。旧 MindNet 的「知识网络图」入口已从这里删除。
const Key mindnetTodayPlanEntryKey = Key('mindnet-today-plan-entry');

/// 用户层学习状态：只有档位 + 强项/弱项（折算见 [buildLearningStatus]）。
///
/// 读数链沿用「认知模型」页那一份（`cognitiveReadingsProvider`），所以首页、
/// 认知模型页和开发者页说的是同一批数字（D2：一个数字一个来源）。
final learningStatusProvider =
    FutureProvider.autoDispose<LearningStatus>((ref) async {
  final readings = await ref.watch(cognitiveReadingsProvider.future);
  final selection = ref.watch(presetSelectionProvider);
  final matrix = ref.watch(presetMatrixSeedProvider).valueOrNull;
  return buildLearningStatus(
    cards: <LearningStatusCard>[
      for (final card in readings.cards)
        LearningStatusCard(
          knowledgePointId: card.knowledgePointId,
          knowledgePointTitle: card.knowledgePointTitle,
          retrievability: card.r,
          hasObservation: card.hasObservation,
        ),
    ],
    preset: PresetPrior.fromSelectionId(
      selection?.presetId,
      presetMeans: matrix?.presetGlobalMean,
    ),
  );
});

/// 今天到期的卡片数。
///
/// 到期与否只由 `getDueCardStates` 说了算（与复习页、今日清单同一个口径）；
/// 这一层不读 `dueAt` 自己判。读不到时上层显示「—」，不显示 0。
final dueCardCountProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watchDatabaseRevision();
  final cards = await ref
      .watch(ankiRepositoryProvider)
      .getDueCardStates(DateTime.now().millisecondsSinceEpoch);
  return cards.length;
});

/// 今日任务数：**未完成**且到期日不晚于今天结束的任务（含已逾期）。
///
/// 只数 `todo|doing`（`getOpenTasks` 的口径）；没有到期日的任务不算「今天」。
final todayTaskCountProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watchDatabaseRevision();
  final tasks = await ref.watch(taskRepositoryProvider).getOpenTasks();
  final now = DateTime.now();
  final endOfToday =
      DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;
  var count = 0;
  for (final task in tasks) {
    final due = task.dueAt;
    if (due != null && due < endOfToday) {
      count++;
    }
  }
  return count;
});

/// 最近一周的复习趋势（只数复习日志，不预测）。
final weeklyReviewTrendProvider =
    FutureProvider.autoDispose<WeeklyReviewTrend>((ref) async {
  ref.watchDatabaseRevision();
  final now = DateTime.now();
  final samples = await ref.watch(ankiRepositoryProvider).retentionSamples(
        sinceMillis:
            now.subtract(const Duration(days: 14)).millisecondsSinceEpoch,
      );
  return WeeklyReviewTrend.read(samples: samples, now: now);
});

/// 四块用户层内容。放在页面的滚动容器里用（本身不滚动）。
class LearningStatusView extends StatelessWidget {
  const LearningStatusView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _BandCard(),
        SizedBox(height: 8),
        _RankCard(kind: _RankKind.strengths),
        SizedBox(height: 8),
        _RankCard(kind: _RankKind.weaknesses),
        SizedBox(height: 8),
        _TodayCard(),
        SizedBox(height: 8),
        _TrendCard(),
      ],
    );
  }
}

/// 入口：只留「今日清单」。
///
/// 「今日清单」保留的理由（现有产品口径）：学习状态页的职责是回答「今天该做
/// 什么」，而今日清单页是同一口径下**唯一**展开今日任务/复习步骤的页面；它
/// 不是新入口，也不复制读数。旧 MindNet 的「知识网络图」入口已删除：那是一张
/// 开发者视图，现在只从设置 → 开发者信息（`CognitiveDeveloperPage`）进入。
class LearningStatusEntries extends StatelessWidget {
  const LearningStatusEntries({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            key: mindnetTodayPlanEntryKey,
            leading: const Icon(Icons.today_outlined),
            title: Text(l10n.todayPlanTitle),
            subtitle: Text(l10n.todayPlanUncalibrated),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TodayPlanPage()),
            ),
          ),
        ),
      ],
    );
  }
}

/// 卡片标题行（图标 + 标题）。
class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: theme.textTheme.titleMedium),
        ),
      ],
    );
  }
}

/// 档位卡：大字 `S/A/B/C/D/?` + 一句依据。**不显示均值/区间**。
class _BandCard extends ConsumerWidget {
  const _BandCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(learningStatusProvider);

    return Card(
      key: learningStatusBandKey,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: status.when(
          loading: () => const SizedBox(
            height: 96,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text(l10n.cognitiveErrorTitle),
          data: (data) {
            final theme = Theme.of(context);
            final known = data.hasBand;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _CardHeader(
                  icon: Icons.insights_outlined,
                  title: l10n.mindnetBandTitle,
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      data.band.band.label,
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: known
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _evidenceLine(l10n, data),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.mindnetBandHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 档位依据：有档说「多少个知识点有复习记录」，没档说清缺什么（不把 `?`
  /// 读成 0 分）。观测单位是知识点，不是闪存卡（task-113）。
  String _evidenceLine(AppLocalizations l10n, LearningStatus status) {
    if (status.hasBand) {
      if (status.band.source == AbilitySource.preset) {
        return l10n.mindnetBandPreset;
      }
      return l10n.mindnetBandEvidence(status.observedKnowledgePointCount);
    }
    if (!status.hasEvidence ||
        status.band.unknownReason == AbilityUnknownReason.tooFewObservations) {
      return l10n.mindnetBandInsufficient(status.bandMinObservations);
    }
    return l10n.mindnetBandUnstable;
  }
}

enum _RankKind { strengths, weaknesses }

/// 强项/弱项卡：最多 3 条，每条只带证据状态（「实测」——不再显示张卡数，
/// 用户层不以闪存卡计数为单位，task-113）。
class _RankCard extends ConsumerWidget {
  const _RankCard({required this.kind});

  final _RankKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = ref.watch(learningStatusProvider);
    final isStrengths = kind == _RankKind.strengths;

    return Card(
      key: isStrengths
          ? learningStatusStrengthsKey
          : learningStatusWeaknessesKey,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _CardHeader(
              icon: isStrengths ? Icons.trending_up : Icons.trending_down,
              title: isStrengths
                  ? l10n.mindnetStrengthsTitle
                  : l10n.mindnetWeaknessesTitle,
            ),
            const SizedBox(height: 8),
            status.when(
              loading: () => const SizedBox(
                height: 24,
                child: Center(
                  child: SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (error, _) => Text(
                l10n.cognitiveErrorTitle,
                style: theme.textTheme.bodySmall,
              ),
              data: (data) => _body(context, l10n, theme, data, isStrengths),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    LearningStatus status,
    bool isStrengths,
  ) {
    final items = isStrengths ? status.strengths : status.weaknesses;
    if (items.isEmpty) {
      return Text(
        isStrengths ? l10n.mindnetStrengthsEmpty : l10n.mindnetWeaknessesEmpty,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      children: <Widget>[
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Text(
                    item.knowledgePointTitle.trim().isEmpty
                        ? l10n.mindnetUntitledKnowledgePoint
                        : item.knowledgePointTitle,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 8),
                _EvidenceChip(
                  text: l10n.mindnetEvidenceMeasured,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 今日：待复习 N 张卡 / 今日任务 M 项 + 主按钮「开始复习」。
class _TodayCard extends ConsumerWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final due = ref.watch(dueCardCountProvider);
    final tasks = ref.watch(todayTaskCountProvider);

    return Card(
      key: learningStatusTodayKey,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _CardHeader(
                icon: Icons.today_outlined, title: l10n.mindnetTodayTitle),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _countText(
                      due,
                      l10n.mindnetTodayReviews,
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Expanded(
                  child: Text(
                    _countText(
                      tasks,
                      l10n.mindnetTodayTasks,
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: mindnetStartReviewKey,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ReviewPage()),
              ),
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.mindnetStartReview),
            ),
          ],
        ),
      ),
    );
  }

  String _countText(AsyncValue<int> value, String Function(int) format) {
    final data = value.valueOrNull;
    if (data != null) return format(data);
    // 读不出来就说读不出来，不写 0（0 是「今天没有」，不是「不知道」）。
    return value.hasError ? '—' : '…';
  }
}

/// 一句话趋势：最近一周复习次数与留存；两周都没记录说「证据不足」。
class _TrendCard extends ConsumerWidget {
  const _TrendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final trend = ref.watch(weeklyReviewTrendProvider);

    return Card(
      key: learningStatusTrendKey,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _CardHeader(
              icon: Icons.timeline_outlined,
              title: l10n.mindnetTrendTitle,
            ),
            const SizedBox(height: 8),
            trend.when(
              loading: () => const SizedBox(
                height: 20,
                child: Center(
                  child: SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (error, _) => Text(
                '—',
                style: theme.textTheme.bodySmall,
              ),
              data: (data) => Text(
                _sentence(l10n, data),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sentence(AppLocalizations l10n, WeeklyReviewTrend trend) {
    if (!trend.hasEvidence) return l10n.mindnetTrendEmpty;
    if (!trend.hasThisWeek) {
      return l10n.mindnetTrendNoThisWeek(trend.reviewsLastWeek);
    }
    final percent = (trend.retention! * 100).round();
    final base = l10n.mindnetTrendRetention(trend.reviewsThisWeek, percent);
    if (trend.reviewsLastWeek == 0) return base;
    return '$base ${l10n.mindnetTrendCompare(trend.reviewsLastWeek)}';
  }
}

/// 证据状态小徽标（「实测」）。
class _EvidenceChip extends StatelessWidget {
  const _EvidenceChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: theme.textTheme.labelSmall),
    );
  }
}
