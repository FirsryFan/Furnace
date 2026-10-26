/// 能力画像（只读）：四项能力最近一次分数、测量次数、最近一次时间与趋势小图。
///
/// 数据来自 `ability_scores`（schema v38，docs/REVIEW_FEEDBACK.md 第 8 条）：本页只读，
/// 不写库、不放「开始测评」按钮——补测入口由设置页统一加。读取走
/// `ability_score_providers.dart` 的两个 provider，它们 `watchDatabaseRevision()`，
/// 所以刚测完切回来看到的已经是新分数。
///
/// 没测过的能力显示「还没测过」，而不是编一个 0 分：0 分与「没测过」不是一回事。
///
/// 趋势小图读 `abilityTrendProvider`（每项能力最多 30 个点）：不足两个点提示
/// 「至少测两次」，够两点画迷你折线并给方向词（变好 / 持平 / 变差，阈值 2 分）。
/// 趋势读失败只在那张卡里给一行短错误，不把整页打成错误态。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/ability_score_repository.dart';
import '../../../domain/services/cognitive/ability_assessment.dart';
import '../../../domain/services/cognitive/ability_trend.dart';
import '../../../l10n/app_localizations.dart';
import '../application/ability_score_providers.dart';

/// 能力画像页：四张卡对应四项能力。
class AbilityProfilePage extends ConsumerWidget {
  const AbilityProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final latestAsync = ref.watch(abilityLatestScoresProvider);
    final countsAsync = ref.watch(abilityScoreCountsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.abilityProfileTitle)),
      body: latestAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _MessageBody(
          message: l10n.abilityProfileLoadFailed('$error'),
          icon: Icons.error_outline,
          iconColor: Theme.of(context).colorScheme.error,
          textKey: const Key('ability-profile-error'),
        ),
        data: (latest) => countsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _MessageBody(
            message: l10n.abilityProfileLoadFailed('$error'),
            icon: Icons.error_outline,
            iconColor: Theme.of(context).colorScheme.error,
            textKey: const Key('ability-profile-error'),
          ),
          data: (counts) => latest.isEmpty
              ? _MessageBody(
                  message: l10n.abilityProfileEmpty,
                  icon: Icons.insights_outlined,
                )
              : _ProfileBody(latest: latest, counts: counts),
        ),
      ),
    );
  }
}

/// 至少有一项测过：顶部一行「最近一次」小标题 + 四张能力卡（AbilityKey.values 顺序）。
class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.latest, required this.counts});

  final Map<AbilityKey, AbilityScoreEntry> latest;
  final Map<AbilityKey, int> counts;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(l10n.abilityProfileLatest, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final ability in AbilityKey.values)
          _AbilityCard(
            ability: ability,
            entry: latest[ability],
            count: counts[ability] ?? 0,
          ),
      ],
    );
  }
}

/// 一项能力一张卡：测得过的给分数 / 次数 / 最近一次时间与趋势，没测过的只给「还没测过」。
class _AbilityCard extends StatelessWidget {
  const _AbilityCard({
    required this.ability,
    required this.entry,
    required this.count,
  });

  final AbilityKey ability;
  final AbilityScoreEntry? entry;
  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final entry = this.entry;
    return Card(
      key: Key('ability-profile-card-${ability.code}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _abilityTitle(l10n, ability),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (entry != null)
                  Text(
                    _formatCapturedAt(entry.capturedAt),
                    key: Key('ability-profile-time-${ability.code}'),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (entry == null)
              Text(
                l10n.abilityProfileNeverTested,
                key: Key('ability-profile-never-${ability.code}'),
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              )
            else ...[
              Text(
                l10n.abilityScoreLabel(entry.score.round()),
                key: Key('ability-profile-score-${ability.code}'),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.abilityProfileCount(count),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              const SizedBox(height: 12),
              // 测过一次之后才谈趋势：没测过的卡只显示「还没测过」，不重复提示。
              _AbilityTrendSection(ability: ability),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一张卡里的趋势区：不足两个点提示「至少测两次」，够两点画迷你折线 + 方向。
///
/// 只有测过的卡才挂这个组件（没测过的卡没有「最近一次分数」，提示也没有意义）。
class _AbilityTrendSection extends ConsumerWidget {
  const _AbilityTrendSection({required this.ability});

  final AbilityKey ability;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final trendAsync = ref.watch(abilityTrendProvider(ability));
    return trendAsync.when(
      // 趋势是附加信息：加载中不占位，避免卡片跳动。
      loading: () => const SizedBox.shrink(),
      // 读失败只在这张卡里给一行短错误，不把整页打成错误态。
      error: (error, _) => Text(
        l10n.abilityProfileLoadFailed('$error'),
        key: Key('ability-trend-error-${ability.code}'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
      data: (trend) {
        if (trend.length < 2) {
          return Text(
            l10n.abilityTrendHint,
            key: Key('ability-trend-hint-${ability.code}'),
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          );
        }
        final direction = trend.direction;
        final directionLabel = switch (direction) {
          AbilityTrendDirection.improving => l10n.abilityTrendImproving,
          AbilityTrendDirection.flat => l10n.abilityTrendFlat,
          AbilityTrendDirection.declining => l10n.abilityTrendDeclining,
        };
        final directionColor = switch (direction) {
          AbilityTrendDirection.improving => theme.colorScheme.primary,
          AbilityTrendDirection.flat => muted,
          AbilityTrendDirection.declining => theme.colorScheme.error,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              key: Key('ability-trend-chart-${ability.code}'),
              height: 36,
              width: double.infinity,
              child: CustomPaint(
                painter: _AbilityTrendPainter(
                  positions: trend.normalizedPositions,
                  scores: trend.normalizedScores,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  l10n.abilityTrendRecent(trend.length),
                  key: Key('ability-trend-recent-${ability.code}'),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                const SizedBox(width: 8),
                Text(
                  directionLabel,
                  key: Key('ability-trend-direction-${ability.code}'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: directionColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// 迷你折线：x 用均匀位置、y 用 `1 - 分数/100`（高分在上），线宽 2 + 2px 圆点。
///
/// 只用 Canvas 画，不引第三方图表包；坐标全部来自 [AbilityTrendSeries] 的
/// 归一化读数，所以同一份数据永远画成同一张图。
class _AbilityTrendPainter extends CustomPainter {
  const _AbilityTrendPainter({
    required this.positions,
    required this.scores,
    required this.color,
  });

  final List<double> positions;
  final List<double> scores;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.length < 2 || size.width <= 0 || size.height <= 0) return;
    // 留 3px 内边距：线宽 2 / 圆点半径 2 不会被画布边裁掉。
    const inset = 3.0;
    final width = size.width - inset * 2;
    final height = size.height - inset * 2;
    if (width <= 0 || height <= 0) return;
    final points = <Offset>[
      for (var i = 0; i < scores.length; i++)
        Offset(
          inset + positions[i] * width,
          inset + (1 - scores[i]) * height,
        ),
    ];
    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, line);
    final dot = Paint()
      ..color = color
      ..isAntiAlias = true;
    for (final point in points) {
      canvas.drawCircle(point, 2, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _AbilityTrendPainter oldDelegate) {
    if (oldDelegate.color != color) return true;
    if (oldDelegate.positions.length != positions.length ||
        oldDelegate.scores.length != scores.length) {
      return true;
    }
    for (var i = 0; i < positions.length; i++) {
      if (oldDelegate.positions[i] != positions[i] ||
          oldDelegate.scores[i] != scores[i]) {
        return true;
      }
    }
    return false;
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({
    required this.message,
    required this.icon,
    this.iconColor,
    this.textKey,
  });

  final String message;
  final IconData icon;
  final Color? iconColor;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: iconColor),
            const SizedBox(height: 12),
            Text(message, key: textKey, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// 能力标题：四项各用 l10n 里自己的名字（不要在页面里另抄一份中文）。
String _abilityTitle(AppLocalizations l10n, AbilityKey ability) {
  return switch (ability) {
    AbilityKey.reactionSpeed => l10n.abilityReactionTitle,
    AbilityKey.workingMemory => l10n.abilityWorkingMemoryTitle,
    AbilityKey.patternRecognition => l10n.abilityPatternTitle,
    AbilityKey.attentionStability => l10n.abilityAttentionTitle,
  };
}

/// 最近一次测量时间：yyyy-MM-dd HH:mm（本地时区，和库里的时间戳同一口径）。
String _formatCapturedAt(DateTime moment) {
  final local = moment.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
