/// 「按能力动作找题」页：从能力动作画像点进来，看"哪些题会练到这个动作"。
///
/// 为什么要这一页：认知模型页上的画像回答"我最该练哪个动作"，但用户看完还是得
/// 自己回题库里翻 —— 这一页把"动作 → 题目"接上，组卷搜题才算闭环（AI 不出题，
/// 只从已有题库里找，与本仓库一贯口径一致）。
///
/// 只读：读 `reasoning_chains` / `reasoning_steps` / `questions`，不写任何表。
/// 点一行进题目详情页（那里有 AI 解题与卡点评估）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/reasoning/capability_action.dart';
import '../../../l10n/app_localizations.dart';
import '../application/capability_action_questions_provider.dart';
import '../application/question_corpus_reader.dart';
import 'question_detail_page.dart';
import 'question_vocab_labels.dart';

class CapabilityActionQuestionsPage extends ConsumerWidget {
  const CapabilityActionQuestionsPage({super.key, required this.actionType});

  /// 能力动作 key（词表里的稳定标识；词表外的也照原样显示）。
  final String actionType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final label =
        CapabilityAction.byKey(actionType)?.labelZh ?? actionType.trim();
    final rows = ref.watch(questionsForActionProvider(actionType));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.capabilityActionQuestionsTitle(label))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.capabilityActionQuestionsNote,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          ...rows.when(
            loading: () => <Widget>[const LinearProgressIndicator()],
            error: (error, _) => <Widget>[
              Text(l10n.capabilityActionQuestionsFailed('$error')),
            ],
            data: (items) => items.isEmpty
                ? <Widget>[Text(l10n.capabilityActionQuestionsEmpty(label))]
                : <Widget>[
                    for (final row in items)
                      _QuestionRow(row: row, actionLabel: label),
                  ],
          ),
        ],
      ),
    );
  }
}

class _QuestionRow extends StatelessWidget {
  const _QuestionRow({required this.row, required this.actionLabel});

  final CapabilityQuestionRow row;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final actions = <String>[
      for (final action in row.actionTypes)
        CapabilityAction.byKey(action)?.labelZh ?? action,
    ];
    // 学科显示名与收题/组卷同一份词表（`CapabilityAction.subjectLabelsZh`）。
    final subject = row.subjectKey.trim().isEmpty
        ? l10n.questionIntakeSubjectNone
        : CapabilityAction.subjectLabelsZh[row.subjectKey] ?? row.subjectKey;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          row.stem,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          l10n.capabilityActionQuestionsMeta(
            subject,
            sourceLevelLabel(l10n, row.sourceLevel),
            actions.join('、'),
          ),
          style: theme.textTheme.bodySmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => QuestionDetailPage(questionId: row.questionId),
          ),
        ),
      ),
    );
  }
}
