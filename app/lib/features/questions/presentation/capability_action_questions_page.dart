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
///
/// 学科多选（轮次一百四十七）：点多个学科 chip = 这几个学科里的题都要（读表按学科集合
/// 过滤，一次查询）；再点一次已选 chip 取消；「全部学科」清空选择。换叠加动作 /
/// 切换「都要出现」时清空学科选择 —— 可选学科是从当前动作的查询结果里算出来的，
/// 留着旧选中态只会问出一张空表却没有可点的 chip。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/reasoning/capability_action.dart';
import '../../../l10n/app_localizations.dart';
import '../application/capability_action_questions_provider.dart';
import '../application/question_corpus_reader.dart';
import '../application/question_stem_display_provider.dart';
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
  /// 学科筛选（可多选；空集 = 全部学科）。
  ///
  /// 用 `Set` 是因为 chip 的选择语义是"并集"：`{'math', 'physics'}` = 数学或物理的题。
  final Set<String> _subjectKeys = <String>{};

  /// 再叠加一个动作（空串 = 不叠加）；与页面入口那一个动作一起构成 `actionTypes`。
  String _secondAction = '';

  /// 两个动作时要不要"都出现在同一条链里"（`requireAll`）。
  bool _requireAll = false;

  String get _label =>
      CapabilityAction.byKey(widget.actionType)?.labelZh ??
      widget.actionType.trim();

  List<String> get _actionTypes => <String>[
        widget.actionType,
        if (_secondAction.isNotEmpty) _secondAction,
      ];

  /// 不带学科筛选时的查询（同时用来收集"有哪些学科可选"）。
  CapabilityQuestionQuery get _baseQuery => CapabilityQuestionQuery(
        actionTypes: _actionTypes,
        requireAll: _requireAll,
      );

  CapabilityQuestionQuery get _query => CapabilityQuestionQuery(
        actionTypes: _actionTypes,
        requireAll: _requireAll,
        subjectKeys: _subjectKeys.toList(),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // 题干一行文本（快照题显示摘录/标签）一次取全表，传给每一行。
    final displays = ref.watch(questionStemDisplayProvider).valueOrNull;
    final base = ref.watch(questionsForCapabilitiesProvider(_baseQuery));
    final rows = _subjectKeys.isEmpty
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
          ..._actionCompose(l10n, theme),
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
                      _QuestionRow(
                        row: row,
                        actionLabel: _label,
                        display: displays?[row.questionId],
                      ),
                  ],
          ),
        ],
      ),
    );
  }

  /// 「再叠加一个动作」+「都要出现」开关：问法本身来自工具面的组合查询，这里给它个界面。
  List<Widget> _actionCompose(AppLocalizations l10n, ThemeData theme) {
    final others = <CapabilityAction>[
      for (final action in CapabilityAction.catalog)
        if (action.key != widget.actionType) action,
    ];
    return <Widget>[
      const SizedBox(height: 12),
      Text(
        l10n.capabilityActionQuestionsSecondAction,
        style: theme.textTheme.labelLarge,
      ),
      DropdownButton<String>(
        value: _secondAction,
        isExpanded: true,
        items: <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(
            value: '',
            child: Text(l10n.capabilityActionQuestionsSecondActionNone),
          ),
          for (final action in others)
            DropdownMenuItem<String>(
              value: action.key,
              child: Text('${action.labelZh}（${action.key}）'),
            ),
        ],
        onChanged: (value) => setState(() {
          _secondAction = value ?? '';
          if (_secondAction.isEmpty) _requireAll = false;
          // 可选学科随动作组合变化：清空选择，避免留下夹在空表里的旧选中态。
          _subjectKeys.clear();
        }),
      ),
      if (_secondAction.isNotEmpty)
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _requireAll,
          onChanged: (value) => setState(() {
            _requireAll = value;
            _subjectKeys.clear();
          }),
          title: Text(l10n.capabilityActionQuestionsRequireAll),
        ),
    ];
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
          FilterChip(
            label: Text(l10n.capabilityActionQuestionsAllSubjects),
            selected: _subjectKeys.isEmpty,
            onSelected: (_) => setState(_subjectKeys.clear),
          ),
          for (final subject in subjects)
            FilterChip(
              label: Text(
                CapabilityAction.subjectLabelsZh[subject] ?? subject,
              ),
              selected: _subjectKeys.contains(subject),
              onSelected: (selected) => setState(() {
                if (selected) {
                  _subjectKeys.add(subject);
                } else {
                  _subjectKeys.remove(subject);
                }
              }),
            ),
        ],
      ),
    ];
  }
}

class _QuestionRow extends StatelessWidget {
  const _QuestionRow({
    required this.row,
    required this.actionLabel,
    this.display,
  });

  final CapabilityQuestionRow row;
  final String actionLabel;

  /// 题干的一行显示文本；provider 未回来或这题没条目时为 null，回退原文。
  final QuestionStemDisplay? display;

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
          display == null || display!.isEmpty ? row.stem : display!.text,
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
