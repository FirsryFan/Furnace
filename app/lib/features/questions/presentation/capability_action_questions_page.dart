/// 「按能力动作找题」页：从能力动作画像点进来，看"哪些题会练到这个动作"。
///
/// 为什么要这一页：认知模型页上的画像回答"我最该练哪个动作"，但用户看完还是得
/// 自己回题库里翻 —— 这一页把"动作 → 题目"接上，组卷搜题才算闭环（AI 不出题，
/// 只从已有题库里找，与本仓库一贯口径一致）。
///
/// 只读：读 `reasoning_chains` / `reasoning_steps` / `questions`，不写任何表。
/// 点一行进题目详情页（那里有 AI 解题与卡点评估）。
///
/// 学科筛选（轮次一百零八）：同一页可以只看某个学科。筛选**走读表**（
/// `readQuestionsForCapabilities`，与工具面的组合查询同一份函数），不是在前端把已经
/// 加载的结果过滤一下 —— 否则"页面上看到的"和"模型查到的"迟早会分叉（D2）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/reasoning/capability_action.dart';
import '../../../l10n/app_localizations.dart';
import '../application/capability_action_questions_provider.dart';
import '../application/question_corpus_reader.dart';
import 'question_detail_page.dart';
import 'question_vocab_labels.dart';

class CapabilityActionQuestionsPage extends ConsumerStatefulWidget {
  const CapabilityActionQuestionsPage({super.key, required this.actionType});

  /// 能力动作 key（词表里的稳定标识；词表外的也照原样显示）。
  final String actionType;

  @override
  ConsumerState<CapabilityActionQuestionsPage> createState() =>
      _CapabilityActionQuestionsPageState();
}

class _CapabilityActionQuestionsPageState
    extends ConsumerState<CapabilityActionQuestionsPage> {
  /// 学科筛选（空串 = 全部学科）。
  String _subjectKey = '';

  String get _label =>
      CapabilityAction.byKey(widget.actionType)?.labelZh ??
      widget.actionType.trim();

  /// 不加学科筛选时的查询（同时用来收集"有哪些学科可选"）。
  CapabilityQuestionQuery get _baseQuery =>
      CapabilityQuestionQuery(actionTypes: <String>[widget.actionType]);

  CapabilityQuestionQuery get _query => CapabilityQuestionQuery(
        actionTypes: <String>[widget.actionType],
        subjectKey: _subjectKey,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final base = ref.watch(questionsForCapabilitiesProvider(_baseQuery));
    final rows = _subjectKey.isEmpty
        ? base
        : ref.watch(questionsForCapabilitiesProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.capabilityActionQuestionsTitle(_label)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.capabilityActionQuestionsNote,
            style: theme.textTheme.bodySmall,
          ),
          // 学科筛选项来自"这个动作下真实出现过的学科"（没出现过的学科不摆出来骗点击）。
          ..._subjectChips(l10n, base),
          const SizedBox(height: 12),
          ...rows.when(
            loading: () => <Widget>[const LinearProgressIndicator()],
            error: (error, _) => <Widget>[
              Text(l10n.capabilityActionQuestionsFailed('$error')),
            ],
            data: (items) => items.isEmpty
                ? <Widget>[Text(l10n.capabilityActionQuestionsEmpty(_label))]
                : <Widget>[
                    for (final row in items)
                      _QuestionRow(row: row, actionLabel: _label),
                  ],
          ),
        ],
      ),
    );
  }

  List<Widget> _subjectChips(
    AppLocalizations l10n,
    AsyncValue<List<CapabilityQuestionRow>> base,
  ) {
    final subjects = <String>{
      for (final row in base.value ?? const <CapabilityQuestionRow>[])
        if (row.subjectKey.trim().isNotEmpty) row.subjectKey.trim(),
    }.toList()
      ..sort();
    if (subjects.length <= 1) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          ChoiceChip(
            label: Text(l10n.capabilityActionQuestionsAllSubjects),
            selected: _subjectKey.isEmpty,
            onSelected: (_) => setState(() => _subjectKey = ''),
          ),
          for (final subject in subjects)
            ChoiceChip(
              label: Text(
                CapabilityAction.subjectLabelsZh[subject] ?? subject,
              ),
              selected: _subjectKey == subject,
              onSelected: (_) => setState(() => _subjectKey = subject),
            ),
        ],
      ),
    ];
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
