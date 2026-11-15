import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/preset_selection.dart';
import '../data/preset_scoring_source.dart';
import '../domain/preset_scoring.dart';

/// 设置页入口与"已选"横幅的稳定 key（测试钉住）。
const Key presetSelectedBannerKey = Key('preset-selected-banner');

Key presetCardKey(String presetId) => Key('preset-card-$presetId');

Key presetSelectButtonKey(String presetId) => Key('preset-select-$presetId');

/// 4 档预设 + 3 题小样的选择页（原型）。
///
/// 只读本地 asset，不写 DB、不联网、不训练、不碰解题/评分。页面刻意**不**把
/// 18 分小样映射到任何高考分（150 分制或其他），因为那会把规则模型的预设估计
/// 伪装成成绩——用户明确禁止。
class PresetSelectPage extends ConsumerStatefulWidget {
  const PresetSelectPage({
    super.key,
    this.source = const AssetPresetScoringSource(),
  });

  /// 可注入，widget 测试不依赖 Flutter asset bundle。
  final PresetScoringSource source;

  @override
  ConsumerState<PresetSelectPage> createState() => _PresetSelectPageState();
}

class _PresetSelectPageState extends ConsumerState<PresetSelectPage> {
  late Future<PresetScoringData> _data;

  @override
  void initState() {
    super.initState();
    _data = widget.source.load();
  }

  void _reload() {
    setState(() {
      _data = widget.source.load();
    });
  }

  void _select(PresetOption option) {
    ref.read(presetSelectionProvider.notifier).state = PresetSelection(
      presetId: option.id,
      presetName: option.name,
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('已选预设：${option.name}（可随时改）')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(presetSelectionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('预设选择（原型）')),
      body: FutureBuilder<PresetScoringData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _PresetErrorView(
              message: '${snapshot.error}',
              onRetry: _reload,
            );
          }
          final data = snapshot.data!;
          final selected = data.optionById(selection?.presetId);
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              _DisclaimerCard(data: data),
              if (selection != null) ...[
                const SizedBox(height: 10),
                _SelectedBanner(
                  selection: selection,
                  data: data,
                ),
              ],
              for (final option in data.presets) ...[
                const SizedBox(height: 10),
                _PresetCard(
                  option: option,
                  isSelected: selected?.id == option.id,
                  onSelect: () => _select(option),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 顶部边界卡：一眼看到"3 题小样 / 预设估计 / 非高考分"。
class _DisclaimerCard extends StatelessWidget {
  const _DisclaimerCard({required this.data});

  final PresetScoringData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '这是 3 题小样诊断，不是高考分',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final badge in presetDisclaimerBadges)
                  _BadgeChip(label: badge, emphasized: true),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '4 档预设是规则模型估计（source=preset, calibrated=false），'
              '用于相对排序和对照，不是能力测量，也没有任何真实学生作答参与。',
              style: text.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              '3 题小样 = ${data.sample.questionCount} 题（每科 1 题）：'
              '每题按原型 6 分计，共 ${data.sample.pointsTotal.toStringAsFixed(0)} 分。'
              '18 分制不是高考分值，不能换算成高考科目分数或任何高考总分。',
              style: text.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(presetIntervalNote, style: text.bodySmall),
            const SizedBox(height: 4),
            Text(presetSelectionMemoryNote, style: text.bodySmall),
            const SizedBox(height: 8),
            Text('小样：${data.sampleLine}', style: text.labelSmall),
          ],
        ),
      ),
    );
  }
}

/// 已选横幅：明确"已选预设（可随时改）"，并说明只保存在内存。
class _SelectedBanner extends StatelessWidget {
  const _SelectedBanner({
    required this.selection,
    required this.data,
  });

  final PresetSelection selection;
  final PresetScoringData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final option = data.optionById(selection.presetId);
    final label = option == null
        ? selection.presetName
        : '${option.name} · ${option.pointsLabel} · ${option.rateLabel}';
    return Card(
      key: presetSelectedBannerKey,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle_outline, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '已选预设：$label（可随时改）',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '选择只保存在内存：本页与设置页同步显示，重启后重置；'
                    '原型阶段不影响解题、评分或 AI 调用。',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一张预设卡。
class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.option,
    required this.isSelected,
    required this.onSelect,
  });

  final PresetOption option;
  final bool isSelected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return Card(
      key: presetCardKey(option.id),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    option.name,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isSelected)
                  _BadgeChip(
                    label: '已选',
                    emphasized: true,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(option.description, style: text.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _BadgeChip(label: presetDisclaimerBadges[0]),
                _BadgeChip(label: presetDisclaimerBadges[1]),
                _BadgeChip(label: presetDisclaimerBadges[2], emphasized: true),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 18,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      _Metric(value: option.pointsLabel, label: '三题小样期望分'),
                      _Metric(value: option.rateLabel, label: '期望率'),
                      _Metric(value: option.intervalLabel, label: '90% 模型区间'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    option.questionLineLabels.join(' · '),
                    style: text.labelSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('强项：${option.strengths.join('；')}', style: text.bodySmall),
            const SizedBox(height: 2),
            Text('弱项：${option.weaknesses.join('；')}', style: text.bodySmall),
            const SizedBox(height: 6),
            Text(
              '预计卡点（模型假设，不是观测）',
              style: text.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            for (final line in option.questionLines)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '· ${line.stuckLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall,
                ),
              ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: isSelected
                  ? OutlinedButton.icon(
                      key: presetSelectButtonKey(option.id),
                      onPressed: onSelect,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('已选（可改选其他档）'),
                    )
                  : FilledButton.tonalIcon(
                      key: presetSelectButtonKey(option.id),
                      onPressed: onSelect,
                      icon: const Icon(Icons.touch_app_outlined, size: 18),
                      label: const Text('选这一档'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(label, style: text.labelSmall),
      ],
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({
    required this.label,
    this.emphasized = false,
    this.color,
  });

  final String label;
  final bool emphasized;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = color ?? theme.colorScheme.surfaceContainerHighest;
    final foreground = color == null
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: emphasized && color == null
            ? Border.all(color: theme.colorScheme.outlineVariant)
            : null,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: emphasized ? FontWeight.w600 : null,
        ),
      ),
    );
  }
}

class _PresetErrorView extends StatelessWidget {
  const _PresetErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 8),
            Text('预设数据读取失败', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(message, textAlign: TextAlign.center, style: text.bodySmall),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
