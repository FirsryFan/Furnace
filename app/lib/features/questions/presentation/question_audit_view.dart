/// 入库体检的界面：题目详情页的「入库体检」区块与题库列表的小徽标。
///
/// 判据、严重度与中文文案都在 `domain/services/questions/question_intake_audit.dart`
/// （纯逻辑，不碰 DB）；这里只 watch `questionAuditReportProvider` 把结论摊开：
/// 详情页列出每条 finding 的中文说明与可展开的 evidence，列表页只在有
/// error/warning 时给一个带数量的小徽标。
///
/// 两条界面上必须成立的事：
///  * 体检只报不改：区块自己没有修数据按钮；
///  * 体检失败不挡页面：报告还没读出来或读失败时，区块与徽标都不占版面。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/questions/question_intake_audit.dart';
import '../../../l10n/app_localizations.dart';
import '../application/question_audit_reader.dart';

/// 详情页「入库体检」区块的 key（报告没读出来/读失败时不渲染，测试用它断言）。
const Key questionAuditSectionKey = Key('question-audit-section');

/// 题库列表 error/warning 徽标的 key（干净题不渲染徽标）。
const Key questionAuditBadgeKey = Key('question-audit-badge');

/// 一次体检里按严重度筛出的条目（保持报告原顺序）。
List<QuestionAuditFinding> _findingsWithSeverity(
  List<QuestionAuditFinding> findings,
  QuestionAuditSeverity severity,
) {
  return [
    for (final finding in findings)
      if (finding.severity == severity) finding,
  ];
}

Color _severityColor(ThemeData theme, QuestionAuditSeverity severity) {
  return switch (severity) {
    QuestionAuditSeverity.error => theme.colorScheme.error,
    QuestionAuditSeverity.warning => Colors.orange.shade800,
    QuestionAuditSeverity.info => theme.colorScheme.primary,
  };
}

IconData _severityIcon(QuestionAuditSeverity severity) {
  return switch (severity) {
    QuestionAuditSeverity.error => Icons.error_outline,
    QuestionAuditSeverity.warning => Icons.warning_amber_rounded,
    QuestionAuditSeverity.info => Icons.info_outline,
  };
}

/// 题目详情页的入库体检区块。
///
/// 报告还没读出来（loading）或读失败（error）时返回零高度：体检是附加信息，
/// 不能挡题面、配图、组卷网搜索与解题入口。没有结论时显示「未发现硬伤」。
class QuestionAuditSection extends ConsumerWidget {
  const QuestionAuditSection({super.key, required this.questionId});

  final String questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(questionAuditReportProvider).valueOrNull;
    if (report == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final findings = report.findingsFor(questionId);
    final groups = <Widget>[
      for (final severity in QuestionAuditSeverity.values)
        ..._buildFindingGroup(
          l10n: l10n,
          theme: theme,
          findings: _findingsWithSeverity(findings, severity),
          severity: severity,
        ),
    ];
    return Card(
      key: questionAuditSectionKey,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.fact_check_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.questionAuditSectionTitle,
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (findings.isEmpty) ...[
              Text(
                l10n.questionAuditClean,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.questionAuditReadOnly,
                style: theme.textTheme.bodySmall,
              ),
            ] else ...[
              ...groups,
              const SizedBox(height: 8),
              Text(
                l10n.questionAuditReadOnly,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFindingGroup({
    required AppLocalizations l10n,
    required ThemeData theme,
    required List<QuestionAuditFinding> findings,
    required QuestionAuditSeverity severity,
  }) {
    if (findings.isEmpty) {
      return const [];
    }
    final color = _severityColor(theme, severity);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 2),
        child: Row(
          children: [
            Icon(_severityIcon(severity), size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              l10n.questionAuditGroupHeader(severity.labelZh, findings.length),
              style: theme.textTheme.labelLarge?.copyWith(color: color),
            ),
          ],
        ),
      ),
      for (final finding in findings)
        _QuestionAuditFindingTile(finding: finding, theme: theme),
    ];
  }
}

class _QuestionAuditFindingTile extends StatelessWidget {
  const _QuestionAuditFindingTile({required this.finding, required this.theme});

  final QuestionAuditFinding finding;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = _severityColor(theme, finding.severity);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  _severityIcon(finding.severity),
                  size: 14,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${finding.severity.labelZh} · ${finding.messageZh}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          if (finding.evidence.isNotEmpty)
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: Key('question-audit-evidence-${finding.code}'),
                tilePadding: const EdgeInsets.only(left: 20),
                childrenPadding: const EdgeInsets.only(
                  left: 20,
                  right: 0,
                  bottom: 6,
                ),
                dense: true,
                visualDensity: VisualDensity.compact,
                title: Text(
                  l10n.questionAuditEvidence,
                  style: theme.textTheme.bodySmall,
                ),
                children: [
                  for (final entry in finding.evidence.entries)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: SelectableText(
                          '${entry.key}: ${entry.value}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 题库列表里一道题的体检徽标：只有 error/warning 时才占位。
///
/// 显示「图标 + 数量」，tooltip 分开写错误与存疑条数；有 error 时用错误色。
class QuestionAuditBadge extends ConsumerWidget {
  const QuestionAuditBadge({super.key, required this.questionId});

  final String questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(questionAuditReportProvider).valueOrNull;
    if (report == null) {
      return const SizedBox.shrink();
    }
    final findings = report.findingsFor(questionId);
    final errors =
        _findingsWithSeverity(findings, QuestionAuditSeverity.error).length;
    final warnings =
        _findingsWithSeverity(findings, QuestionAuditSeverity.warning).length;
    if (errors == 0 && warnings == 0) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = errors > 0 ? theme.colorScheme.error : Colors.orange.shade800;
    return Tooltip(
      key: questionAuditBadgeKey,
      message: l10n.questionAuditBadgeTooltip(errors, warnings),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              errors > 0 ? Icons.error_outline : Icons.warning_amber_rounded,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 2),
            Text(
              '${errors + warnings}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
