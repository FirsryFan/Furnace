/// 组卷页的「组卷质量体检」卡片：把 [paperQualityReportProvider] 的报告排版出来。
///
/// 分工：
/// * 17 条判据、中文 messageZh、evidence 字段全部来自领域层
///   `domain/services/paper/paper_quality_report.dart`，这里不改判据、不重算；
/// * 应用层装配（逐题难度、展示名）在 `application/paper_quality_provider.dart`；
/// * 本文件只做展示：摘要、按严重度分组、evidence 的键名中文化与取值格式化都在
///   这里（纯函数在上半部分，widget 测试与单测可以直接调）。
///
/// evidence 的键名标签与取值标签沿用领域层中文（与 messageZh 同口径：英文界面
/// 下这两者仍是中文），只有卡片框架文案走 l10n 的 `paperQuality*`。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/paper/paper_composer.dart';
import '../../../domain/services/paper/paper_quality_report.dart';
import '../../../domain/services/reasoning/capability_action.dart';
import '../../../l10n/app_localizations.dart';
import '../application/paper_quality_provider.dart';

/// 体检卡片根节点 key。
const Key paperQualitySectionKey = Key('paper-quality-section');

/// 某一严重度分组的标题 key。
Key paperQualityGroupKey(PaperQualitySeverity severity) =>
    Key('paper-quality-group-${severity.name}');

/// 第 [index] 条判据（[PaperQualityReport.warnings] 的下标）根节点 key。
Key paperQualityWarningKey(int index) => Key('paper-quality-warning-$index');

/// 第 [index] 条判据的「查看依据 / 收起依据」按钮 key。
Key paperQualityEvidenceToggleKey(int index) =>
    Key('paper-quality-evidence-$index');

/// evidence 键 → 中文标签。
///
/// 只影响展示：未收录的键原样显示（不隐藏信息）。键集与领域层各判据写入的
/// evidence 字段一致；新增判据时在这里补一行即可，判据本身不用动。
const Map<String, String> paperQualityEvidenceLabels = <String, String>{
  'requested_count': '想要几道',
  'candidate_count': '候选题数',
  'question_count': '题数',
  'missing_count': '缺少几道',
  'fill_ratio': '填充率',
  'subject_key': '学科',
  'count': '数量',
  'ratio': '占比',
  'threshold': '阈值',
  'source_level': '来源档位',
  'uncovered_count': '未覆盖知识点数',
  'covered_count': '已覆盖知识点数',
  'coverage': '知识点覆盖率',
  'knowledge_point_ids': '知识点 id',
  'knowledge_point_labels': '知识点',
  'zone': '学习区',
  'known_count': '有难度读数的题数',
  'item_count': '统计题数',
  'spread': '极差',
  'mean': '平均难度',
  'target': '目标难度',
  'deviation': '偏差',
  'tolerance': '容差',
  'minimum_count': '保底几道',
  'selected_count': '已排几道',
  'available_count': '可用候选',
  'domain': '领域',
  'subject_blocked_count': '被学科上限挡下',
  'domain_blocked_count': '被领域上限挡下',
  'subject_counts': '各学科被挡',
  'domain_counts': '各领域被挡',
  'missing_ids': '找不到的题数',
  'skipped_ids': '装不下的题数',
  'conflict_ids': '冲突的题数',
  'missing_preview': '找不到的题号',
  'skipped_preview': '装不下的题号',
  'conflict_preview': '冲突的题号',
  'truncated': '是否截断',
  'total_for_code': '同类共几条',
  'shown_for_code': '已显示几条',
};

/// 比例 → 百分比文本（0.5 → `50%`）。
///
/// 非有限值或负数记 `—`：坏数据不能冒充成 0%（与领域层「缺数据不冒充读数」
/// 同口径）。
String paperQualityPercent(double ratio) {
  if (!ratio.isFinite || ratio < 0) return '—';
  return '${(ratio * 100).round()}%';
}

/// evidence 键的中文标签；未收录的键原样返回。
String paperQualityEvidenceLabel(String key) =>
    paperQualityEvidenceLabels[key] ?? key;

/// evidence 取值的展示文本。
///
/// 比例类转百分比；学科 / 来源档位 / zone 转中文名；布尔转「是 / 否」；其余原样。
String paperQualityEvidenceValue(String key, String value) {
  switch (key) {
    case 'fill_ratio':
    case 'ratio':
    case 'coverage':
      final parsed = double.tryParse(value);
      return parsed == null ? value : paperQualityPercent(parsed);
    case 'subject_key':
      final subject = value.trim();
      if (subject.isEmpty) return kPaperQualityUnknownSubjectLabel;
      return CapabilityAction.subjectLabelsZh[subject] ?? subject;
    case 'source_level':
      return kPaperQualitySourceLevelLabels[value] ?? value;
    case 'zone':
      return paperQualityZoneLabel(value) ?? value;
    case 'truncated':
      return value == 'true' ? '是' : '否';
    default:
      return value;
  }
}

/// zone 的稳定键（`PaperZone.name`）→ 中文名；未收录返回 null。
String? paperQualityZoneLabel(String zoneName) {
  for (final zone in PaperZone.values) {
    if (zone.name == zoneName) return zone.labelZh;
  }
  return null;
}

/// 一条 evidence → 可读的「标签 / 取值」行（保持 evidence 原顺序）。
List<({String label, String value})> paperQualityEvidenceRows(
  Map<String, String> evidence,
) {
  return <({String label, String value})>[
    for (final entry in evidence.entries)
      (
        label: paperQualityEvidenceLabel(entry.key),
        value: paperQualityEvidenceValue(entry.key, entry.value),
      ),
  ];
}

/// 某严重度下的判据（保持报告里的顺序；报告已按 error → warning → info 排好）。
List<PaperQualityWarning> paperQualityWarningsOf(
  PaperQualityReport report,
  PaperQualitySeverity severity,
) {
  return <PaperQualityWarning>[
    for (final warning in report.warnings)
      if (warning.severity == severity) warning,
  ];
}

/// 严重度图标。
IconData paperQualitySeverityIcon(PaperQualitySeverity severity) {
  switch (severity) {
    case PaperQualitySeverity.error:
      return Icons.error_outline;
    case PaperQualitySeverity.warning:
      return Icons.warning_amber_outlined;
    case PaperQualitySeverity.info:
      return Icons.info_outline;
  }
}

/// 严重度颜色（跟随主题语义色）。
Color paperQualitySeverityColor(
  ThemeData theme,
  PaperQualitySeverity severity,
) {
  switch (severity) {
    case PaperQualitySeverity.error:
      return theme.colorScheme.error;
    case PaperQualitySeverity.warning:
      return theme.colorScheme.tertiary;
    case PaperQualitySeverity.info:
      return theme.colorScheme.outline;
  }
}

/// 组卷页的「组卷质量体检」卡片。
///
/// 空卷也渲染：领域层会给一条 `empty_plan` 的 error，不能把它折叠成不占高度。
class PaperQualitySection extends ConsumerWidget {
  const PaperQualitySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final report = ref.watch(paperQualityReportProvider);
    return report.when(
      // 报告算得慢时先不占高度：体检是补充信息，不该把控制项往下挤。
      loading: () => const SizedBox.shrink(),
      error: (error, _) => Card(
        key: paperQualitySectionKey,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(l10n.paperQualityFailed),
        ),
      ),
      data: (report) => _PaperQualityCard(report: report),
    );
  }
}

class _PaperQualityCard extends StatelessWidget {
  const _PaperQualityCard({required this.report});

  final PaperQualityReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bodySmall = theme.textTheme.bodySmall;
    final groups = <PaperQualitySeverity>[
      for (final severity in PaperQualitySeverity.values)
        if (paperQualityWarningsOf(report, severity).isNotEmpty) severity,
    ];

    return Card(
      key: paperQualitySectionKey,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.health_and_safety_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.paperQualityTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  l10n.paperQualitySummary(
                    report.questionCount,
                    report.requestedCount,
                    paperQualityPercent(report.fillRatio),
                  ),
                  style: bodySmall,
                ),
                Text(
                  l10n.paperQualityCoverage(
                    paperQualityPercent(report.knowledgePointCoverage),
                  ),
                  style: bodySmall,
                ),
              ],
            ),
            if (!report.quotaSatisfied) ...[
              const SizedBox(height: 6),
              Text(
                l10n.paperQualityQuotaUnsatisfied,
                style: bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            if (report.truncatedWarningCount > 0) ...[
              const SizedBox(height: 4),
              Text(
                l10n.paperQualityTruncated(report.truncatedWarningCount),
                style: bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            if (groups.isEmpty)
              Text(l10n.paperQualityClean, style: bodySmall)
            else
              for (final severity in groups)
                _PaperQualityGroup(report: report, severity: severity),
          ],
        ),
      ),
    );
  }
}

class _PaperQualityGroup extends StatelessWidget {
  const _PaperQualityGroup({required this.report, required this.severity});

  final PaperQualityReport report;
  final PaperQualitySeverity severity;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = paperQualitySeverityColor(theme, severity);
    final warnings = paperQualityWarningsOf(report, severity);
    final indexes = <int>[
      for (var i = 0; i < report.warnings.length; i++)
        if (report.warnings[i].severity == severity) i,
    ];

    return Padding(
      key: paperQualityGroupKey(severity),
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(paperQualitySeverityIcon(severity), size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                l10n.paperQualityGroupHeader(severity.labelZh, warnings.length),
                style: theme.textTheme.labelMedium?.copyWith(color: color),
              ),
            ],
          ),
          for (var i = 0; i < warnings.length; i++)
            _PaperQualityWarningTile(
              warning: warnings[i],
              index: indexes[i],
            ),
        ],
      ),
    );
  }
}

class _PaperQualityWarningTile extends StatefulWidget {
  const _PaperQualityWarningTile({required this.warning, required this.index});

  final PaperQualityWarning warning;
  final int index;

  @override
  State<_PaperQualityWarningTile> createState() =>
      _PaperQualityWarningTileState();
}

class _PaperQualityWarningTileState extends State<_PaperQualityWarningTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final evidence = widget.warning.evidence;
    return Padding(
      key: paperQualityWarningKey(widget.index),
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.warning.messageZh, style: theme.textTheme.bodySmall),
          if (evidence.isNotEmpty)
            TextButton(
              key: paperQualityEvidenceToggleKey(widget.index),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded
                    ? l10n.paperQualityEvidenceCollapse
                    : l10n.paperQualityEvidenceToggle,
              ),
            ),
          if (_expanded && evidence.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.paperQualityEvidenceTitle,
                    style: theme.textTheme.labelSmall,
                  ),
                  for (final row in paperQualityEvidenceRows(evidence))
                    Text(
                      '${row.label}：${row.value}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
