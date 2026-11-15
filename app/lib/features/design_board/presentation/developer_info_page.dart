import 'package:flutter/material.dart';

import '../domain/design_board.dart';
import 'sample_badges.dart';

/// Audit/developer view for one content sample.
///
/// Everything a student should not see (trust level, hashes, source pointers,
/// evidence counts, machine validation, Problem State, unreviewed DAG list)
/// lives here; it is reached from a small "开发者信息" link on the student page.
class DeveloperInfoPage extends StatelessWidget {
  const DeveloperInfoPage({super.key, required this.sample});

  final DesignBoardCard sample;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('开发者信息（只读）')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sample.title,
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (sample.statusLabel.isNotEmpty)
                        SampleStatusChip(status: sample.statusLabel),
                    ],
                  ),
                  if (sample.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(sample.subtitle, style: text.bodySmall),
                  ],
                  if (sample.chips.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final chip in sample.chips)
                          SampleFlagChip(label: chip),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    '开发/审计信息，不面向学生；不能证明答案正确或内容质量。',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          if (sample.problemState != null) ...[
            const SizedBox(height: 10),
            _ProblemStateCard(state: sample.problemState!),
          ],
          if (sample.studentContent != null) ...[
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '另一种答案与 Thinking DAG（开发者记录）',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '另一种答案与理由是 AI 生成、非官方、未经独立审核；'
                      'Thinking DAG 为 AI 整理，没有语义校验。'
                      '学生页只显示【AI】标题标记，不显示这些说明。',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
          for (final section in sample.detailSections) ...[
            const SizedBox(height: 10),
            _DevSectionCard(section: section),
          ],
        ],
      ),
    );
  }
}

class _DevSectionCard extends StatelessWidget {
  const _DevSectionCard({required this.section});

  final DesignBoardSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              section.title,
              style: text.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
            for (final item in section.items) ...[
              const SizedBox(height: 8),
              Text('• $item', style: text.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// Problem State snapshot block (previously on the student page).
class _ProblemStateCard extends StatelessWidget {
  const _ProblemStateCard({required this.state});

  final ProblemStateSummary state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Problem State（只读）',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SampleStatusChip(status: '未审批'),
              ],
            ),
            const SizedBox(height: 6),
            Text(state.note, style: text.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _CountPill(label: 'facts ${state.facts}'),
                _CountPill(label: 'assumptions ${state.assumptions}'),
                _CountPill(label: 'decisions ${state.decisions}'),
                _CountPill(label: 'unknowns ${state.unknowns}'),
                _CountPill(label: 'artifacts ${state.artifacts}'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'decisions：${state.decisionsProposed} 全部 proposed'
              '（accepted ${state.decisionsAccepted} / '
              'rejected ${state.decisionsRejected}；decided_at=null，无审批记录）',
              style: text.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'facts trust：verified ${state.factTrustVerified} / '
              'reported ${state.factTrustReported}',
              style: text.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              '未知项（${state.unknowns}）：',
              style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            for (var i = 0; i < state.unknownsShown.length; i++) ...[
              const SizedBox(height: 4),
              Text(
                '${i + 1}. ${state.unknownsShown[i]}',
                style: text.bodySmall,
              ),
            ],
            if (state.unknownsMore > 0) ...[
              const SizedBox(height: 4),
              Text(
                '另有 ${state.unknownsMore} 条未展示（见 problem-state JSON）',
                style: text.bodySmall,
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'oracle：${state.oracleKind.isEmpty ? '未记录' : state.oracleKind}；'
              'budget：${state.budgetNull ? 'null（未记录 token/时长/轮次）' : '已记录'}',
              style: text.bodySmall,
            ),
            if (state.oracleDescription.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(state.oracleDescription, style: text.bodySmall),
            ],
            const SizedBox(height: 6),
            Text(
              '节点状态：${state.nodeStatus}；数据来自 problem-state 快照，'
              '未接 ProblemStateStore/DB/UI。',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}
