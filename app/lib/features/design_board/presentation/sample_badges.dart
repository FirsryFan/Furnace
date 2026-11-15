import 'package:flutter/material.dart';

/// Status chip used by the design board and the content-sample page.
///
/// Kept public in one place so the摘要 card and the detail page agree on how
/// 已落地 / 审核中 / 否定 / 待完善 / 数据未完成 are coloured.
class SampleStatusChip extends StatelessWidget {
  const SampleStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      '已落地' => const Color(0xFF2E7D32),
      '审核中' => const Color(0xFF1565C0),
      '否定' => const Color(0xFFC62828),
      '数据未完成' => const Color(0xFF616161),
      _ => const Color(0xFFE65100),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Warning-style flag chip used by the real-content sample card/page.
///
/// The flags a reviewer must not miss ("DAG 未独立审核", "private_study_only")
/// are tinted amber; informational flags follow the theme primary colour.
class SampleFlagChip extends StatelessWidget {
  const SampleFlagChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = label.contains('未独立审核') ||
        label.contains('private_study_only') ||
        label.contains('无官方评分细则') ||
        label.contains('AI 均分');
    final color = warning ? const Color(0xFFB26A00) : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, height: 1.3, color: color),
      ),
    );
  }
}
