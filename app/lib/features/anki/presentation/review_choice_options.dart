/// 闪存卡「选择题」的选项渲染（纯展示 + 受控选择）。
///
/// 为什么单独一个文件：作答/判分/会话是 review_page 的事（另一个 owner 在改），
/// 这里只负责"四个选项按钮长什么样、点了之后把哪几个下标报上去"。调用方持有
/// [selected]，通过 [onChanged] 收选择；提交后把正确下标交给 [correctIndexes]，
/// 面板只负责画对错，不自己判分。
///
/// 口径：
/// * 字母按 0-based 下标生成：A、B、C、D…（超过 26 个用数字，理论上不会发生）；
/// * [multiple] false = 单选（点另一个就替换），true = 多选（点一下切换）；
/// * [correctIndexes] 为 null = 还没判分（或自判模式）→ 不画对错、不给勾叉；
/// * [selfJudged] true = 自判模式：即使调用方给了 [correctIndexes] 也不画对错，
///   只保留"已选"高亮——自判只记录选择，不自动判分；
/// * [onChanged] 为 null = 整组禁用（已提交、或等待态）。
library;

import 'package:flutter/material.dart';

/// 第 [index] 个选项的字母（0-based）：0 → A，25 → Z，26+ → 数字序号。
String reviewOptionLetter(int index) {
  if (index < 0) {
    return '?';
  }
  if (index < 26) {
    return String.fromCharCode(0x41 + index);
  }
  return '${index + 1}';
}

/// 第 [index] 个选项按钮的稳定 key（widget 测试/接线用）。
Key reviewOptionButtonKey(int index) =>
    ValueKey<String>('review-option-$index');

/// 选项面板的根 key。
const Key reviewOptionsKey = Key('review-options');

/// 选择题的选项面板。
class ReviewChoiceOptions extends StatelessWidget {
  const ReviewChoiceOptions({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.multiple = false,
    this.correctIndexes,
    this.selfJudged = false,
  });

  /// 选项文本，顺序即 A/B/C/D…；空列表时整块不占版面。
  final List<String> options;

  /// 当前选中的 0-based 下标；调用方持有。
  final Set<int> selected;

  /// 选择变化回调；null = 整组禁用。多选时给的是新的完整集合。
  final ValueChanged<Set<int>>? onChanged;

  /// true = 多选（提交前可勾多个），false = 单选。
  final bool multiple;

  /// 提交后由调用方给出的正确选项下标；null = 未判分（不对错着色）。
  final Set<int>? correctIndexes;

  /// 自判模式：不自动判分，只记录选择（不画对错）。
  final bool selfJudged;

  /// 当前状态下第 [index] 个选项的对错：null = 不展示对错。
  bool? _correctnessOf(int index) {
    final correct = correctIndexes;
    if (selfJudged || correct == null) {
      return null;
    }
    return correct.contains(index);
  }

  void _select(int index) {
    final handler = onChanged;
    if (handler == null || index < 0 || index >= options.length) {
      return;
    }
    if (multiple) {
      final next = <int>{...selected};
      if (!next.remove(index)) {
        next.add(index);
      }
      handler(next);
      return;
    }
    // 单选：重复点同一个不重复上报，免得调用方多做一次无变化的重建。
    if (selected.length == 1 && selected.contains(index)) {
      return;
    }
    handler(<int>{index});
  }

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      key: reviewOptionsKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < options.length; index++)
          _ReviewOptionButton(
            key: reviewOptionButtonKey(index),
            letter: reviewOptionLetter(index),
            label: options[index],
            selected: selected.contains(index),
            correctness: _correctnessOf(index),
            multiple: multiple,
            onTap: onChanged == null ? null : () => _select(index),
          ),
      ],
    );
  }
}

/// 一个选项按钮：字母徽章 + 文本 + 选中/对错状态。
class _ReviewOptionButton extends StatelessWidget {
  const _ReviewOptionButton({
    super.key,
    required this.letter,
    required this.label,
    required this.selected,
    required this.correctness,
    required this.multiple,
    required this.onTap,
  });

  final String letter;
  final String label;
  final bool selected;

  /// null = 不展示对错；true = 正确选项；false = 错误选项。
  final bool? correctness;

  final bool multiple;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCorrect = correctness == true;
    final isWrongSelected = correctness == false && selected;
    final background = isCorrect
        ? Colors.green.withValues(alpha: 0.16)
        : isWrongSelected
            ? theme.colorScheme.error.withValues(alpha: 0.14)
            : selected
                ? theme.colorScheme.primary.withValues(alpha: 0.14)
                : null;
    final accent = isCorrect
        ? Colors.green.shade700
        : isWrongSelected
            ? theme.colorScheme.error
            : selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant;
    final IconData? trailing = isCorrect
        ? Icons.check_circle_outline
        : isWrongSelected
            ? Icons.cancel_outlined
            : selected
                ? (multiple
                    ? Icons.check_box_outlined
                    : Icons.radio_button_checked)
                : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          backgroundColor: background,
          // 判分后按钮会被禁用，高亮必须活下来——那正是它最该被看见的时候。
          disabledBackgroundColor: background,
          disabledForegroundColor: theme.colorScheme.onSurface,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          side: BorderSide(
            color: isCorrect || isWrongSelected || selected
                ? accent
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected || isCorrect || isWrongSelected
                    ? accent.withValues(alpha: 0.18)
                    : theme.colorScheme.surfaceContainerHighest,
              ),
              child: Text(
                letter,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  height: 1.4,
                ),
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: 8),
              Icon(trailing, size: 20, color: accent),
            ],
          ],
        ),
      ),
    );
  }
}
