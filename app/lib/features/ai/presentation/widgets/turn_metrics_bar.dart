import 'package:flutter/material.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../../domain/agent_loop.dart';
import '../../domain/agent_run.dart';
import 'turn_usage_panel.dart';

/// 输入框下面那条常驻的指标条（用户 2026-11-15 第 10 点）：
/// 多少轮、多少步、总 token、缓存命中率、当前上下文窗口占用。
///
/// 数据只有一个来源：[TurnUsageView]，也就是 [AgentLoop] 的 `TurnUsage`——每个
/// 数字要么是 provider 报告的、要么是秒表量的。没有数据就画 `—`：不拿 0 冒充
/// 「没缓存」，也不拿估算冒充测量（缓存命中率与上下文占用在 provider 没报时就是
/// 没有数据）。上下文占用按配置的窗口估算，所以那一段带 tooltip 说明。
///
/// 重开页面 / 刚切会话时内存态是空的，这时用 [persistedRun]（已落库的
/// `agent_runs`）补出**确实被记录过**的轮数与 token；缓存命中与上下文占用没有
/// 持久化列，仍然是 `—`。
///
/// 一条横排放不下时用 [Wrap] 折行，而不是溢出：窄窗口（700 逻辑像素）下这条
/// 也要能读。
class TurnMetricsBar extends StatelessWidget {
  const TurnMetricsBar({super.key, required this.view, this.persistedRun});

  final TurnUsageView view;

  /// 最近一次运行记录，仅在本轮没有内存态时使用。
  final AgentRunState? persistedRun;

  /// 每个指标的数值文本。测试通过它们读数字，翻译不会把测试弄坏。
  static const Key roundsKey = ValueKey<String>('ai-metrics-rounds');
  static const Key stepsKey = ValueKey<String>('ai-metrics-steps');
  static const Key totalTokensKey = ValueKey<String>('ai-metrics-total-tokens');
  static const Key cacheKey = ValueKey<String>('ai-metrics-cache');
  static const Key contextKey = ValueKey<String>('ai-metrics-context');

  /// 指标条的容器 key（整条存在，但数值可能是 `—`）。
  static const Key barKey = ValueKey<String>('ai-metrics-bar');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final usage = view.hasData ? view.usage : null;
    final dash = l10n.aiUsageUnavailable;

    // 内存态优先；没有内存态时退回最近一次落库的运行记录。两者的字段口径不同
    // （运行记录里 steps 是模型回合数，没有缓存/上下文列），所以只在各自的
    // 字段真的存在时才填数字。
    final recorded = usage == null ? persistedRun : null;

    final rounds = usage != null
        ? '${usage.rounds}/${usage.maxRounds}'
        : (recorded == null ? dash : '${recorded.steps}');
    final steps = usage == null ? dash : '${usage.toolCallsExecuted}';
    final tokens = usage != null
        ? (usage.hasUsage ? '${usage.totalTokens}' : dash)
        : (recorded == null
            ? dash
            : ((recorded.promptTokens + recorded.completionTokens) > 0
                ? '${recorded.promptTokens + recorded.completionTokens}'
                : dash));
    final cacheRatio = usage?.cacheHitRatio;
    final cache = cacheRatio == null ? dash : _percent(cacheRatio);
    final contextRatio = usage?.contextUsageRatio;
    final contextText = contextRatio == null ? dash : _percent(contextRatio);

    final scope = usage != null
        ? (view.generating ? l10n.aiUsageCurrent : l10n.aiUsageLast)
        : (recorded == null ? null : l10n.aiUsageLast);

    final smallStyle = TextStyle(
      fontSize: 11,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      key: barKey,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Wrap(
        spacing: 14,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (scope != null) Text(scope, style: smallStyle),
          _metric(
            context,
            key: roundsKey,
            label: l10n.aiUsageRounds,
            value: rounds,
            style: smallStyle,
          ),
          _metric(
            context,
            key: stepsKey,
            label: l10n.aiUsageSteps,
            value: steps,
            style: smallStyle,
          ),
          _metric(
            context,
            key: totalTokensKey,
            label: l10n.aiUsageTotalTokens,
            value: tokens,
            style: smallStyle,
          ),
          _metric(
            context,
            key: cacheKey,
            label: l10n.aiUsageCacheHit,
            value: cache,
            style: smallStyle,
          ),
          _metric(
            context,
            key: contextKey,
            label: l10n.aiUsageContext,
            value: contextText,
            style: smallStyle,
            tooltip: usage == null
                ? null
                : l10n.aiUsageContextEstimate(usage.contextWindowTokens),
          ),
        ],
      ),
    );
  }

  Widget _metric(
    BuildContext context, {
    required Key key,
    required String label,
    required String value,
    required TextStyle style,
    String? tooltip,
  }) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: style),
        const SizedBox(width: 4),
        Text(value, key: key, style: style),
      ],
    );
    if (tooltip == null) {
      return row;
    }
    return Tooltip(message: tooltip, child: row);
  }

  static String _percent(double ratio) =>
      '${(ratio * 100).toStringAsFixed(1)}%';
}

/// 绑定到 [TurnUsageNotifier] 的指标条。
class TurnMetricsSection extends StatelessWidget {
  const TurnMetricsSection({
    super.key,
    required this.notifier,
    this.persistedRun,
  });

  final TurnUsageNotifier notifier;

  /// 最近一次运行记录（`agent_runs`），仅在没有内存态时显示。
  final AgentRunState? persistedRun;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TurnUsageView>(
      valueListenable: notifier,
      builder: (context, view, _) =>
          TurnMetricsBar(view: view, persistedRun: persistedRun),
    );
  }
}
