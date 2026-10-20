/// 题库包（`.tqb`）选择性导出的筛选对话框：学科、来源档位、标签路径、
/// 题号范围。
///
/// 四条约束都留空就是「全部导出」。这里只负责收集条件并返回
/// [QuestionPackSelection]；真正的筛题、读配图、打 zip 都在 service 层，
/// 所以本文件不直接读数据库（标签路径选项由
/// `question_pack_tag_path_picker.dart` 的 provider 提供），纯逻辑部分
/// （题号校验、条件组装）抽成顶层函数便于单测。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/package/question_pack_selection.dart';
import '../../../domain/services/package/question_pack_tag_options.dart';
import '../../../domain/services/reasoning/capability_action.dart';
import '../../../l10n/app_localizations.dart';
import '../../questions/presentation/question_paper_page.dart'
    show subjectLabelOf;
import '../../questions/presentation/question_vocab_labels.dart';
import 'question_pack_tag_path_picker.dart';

/// 来源档位的候选顺序（与收题页/组卷页同一套六档）。
const List<String> questionPackFilterSourceLevels = <String>[
  'gaokao',
  'provincial_diagnostic',
  'elite_school',
  'school',
  'personal',
  'unknown',
];

/// 题号范围输入的校验结果。
enum QuestionPackSerialRangeIssue {
  /// 两端都是空的或都是合法数字，且起 <= 止。
  none,

  /// 起始题号不是纯数字。
  invalidFrom,

  /// 结束题号不是纯数字。
  invalidTo,

  /// 两端都合法但起始大于结束。
  reversed,
}

/// 校验两个题号输入框。
///
/// 空串/null 表示这一端不限，合法；非空但不是纯半角数字（规则见
/// [normalizeSerialBound]）判为非法；两端都合法且起始大于结束时判为反向。
QuestionPackSerialRangeIssue questionPackSerialRangeIssue(
  String? rawFrom,
  String? rawTo,
) {
  final int? from = normalizeSerialBound(rawFrom);
  final int? to = normalizeSerialBound(rawTo);
  if (rawFrom != null && rawFrom.trim().isNotEmpty && from == null) {
    return QuestionPackSerialRangeIssue.invalidFrom;
  }
  if (rawTo != null && rawTo.trim().isNotEmpty && to == null) {
    return QuestionPackSerialRangeIssue.invalidTo;
  }
  if (from != null && to != null && from > to) {
    return QuestionPackSerialRangeIssue.reversed;
  }
  return QuestionPackSerialRangeIssue.none;
}

/// 把对话框里的选择组装成筛选条件。
///
/// 题号两端为空串时各自不约束；标签路径走 [selectedQuestionPackTagPaths]
/// 归一（trim、丢空、去重），返回不可变集合。
QuestionPackSelection questionPackSelectionFromFilter({
  Set<String> subjectKeys = const <String>{},
  Set<String> sourceLevels = const <String>{},
  Set<String> tagPaths = const <String>{},
  String? serialFrom,
  String? serialTo,
}) {
  return QuestionPackSelection(
    subjectKeys: Set<String>.unmodifiable(subjectKeys),
    sourceLevels: Set<String>.unmodifiable(sourceLevels),
    tagPaths: selectedQuestionPackTagPaths(tagPaths),
    serialFrom: normalizeSerialBound(serialFrom),
    serialTo: normalizeSerialBound(serialTo),
  );
}

/// 「导出范围」对话框：返回用户确认的筛选条件，取消返回 null。
///
/// 默认全不选——此时点「导出」就是导出整个题库。
class QuestionPackExportFilterDialog extends ConsumerStatefulWidget {
  const QuestionPackExportFilterDialog({super.key});

  @override
  ConsumerState<QuestionPackExportFilterDialog> createState() =>
      _QuestionPackExportFilterDialogState();
}

class _QuestionPackExportFilterDialogState
    extends ConsumerState<QuestionPackExportFilterDialog> {
  final Set<String> _subjectKeys = <String>{};
  final Set<String> _sourceLevels = <String>{};
  Set<String> _tagPaths = const <String>{};
  final TextEditingController _serialFrom = TextEditingController();
  final TextEditingController _serialTo = TextEditingController();

  @override
  void dispose() {
    _serialFrom.dispose();
    _serialTo.dispose();
    super.dispose();
  }

  QuestionPackSerialRangeIssue get _serialIssue =>
      questionPackSerialRangeIssue(_serialFrom.text, _serialTo.text);

  QuestionPackSelection _selection() => questionPackSelectionFromFilter(
        subjectKeys: _subjectKeys,
        sourceLevels: _sourceLevels,
        tagPaths: _tagPaths,
        serialFrom: _serialFrom.text,
        serialTo: _serialTo.text,
      );

  /// Opens the tag-path picker; cancelling it keeps the previous paths.
  Future<void> _pickTagPaths() async {
    final Set<String>? picked = await showDialog<Set<String>>(
      context: context,
      builder: (_) => QuestionPackTagPathPickerDialog(
        initialSelection: _tagPaths,
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _tagPaths = selectedQuestionPackTagPaths(picked);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final QuestionPackSerialRangeIssue issue = _serialIssue;
    return AlertDialog(
      title: Text(l10n.settingsQuestionPackFilterTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.settingsQuestionPackFilterSubjects,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String key in CapabilityAction.subjectKeys)
                    FilterChip(
                      label: Text(subjectLabelOf(l10n, key)),
                      selected: _subjectKeys.contains(key),
                      onSelected: (bool selected) => setState(() {
                        if (selected) {
                          _subjectKeys.add(key);
                        } else {
                          _subjectKeys.remove(key);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                l10n.settingsQuestionPackFilterSources,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String level in questionPackFilterSourceLevels)
                    FilterChip(
                      label: Text(sourceLevelLabel(l10n, level)),
                      selected: _sourceLevels.contains(level),
                      onSelected: (bool selected) => setState(() {
                        if (selected) {
                          _sourceLevels.add(level);
                        } else {
                          _sourceLevels.remove(level);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                l10n.settingsQuestionPackFilterTags,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey<String>('question-pack-filter-tag-paths'),
                onPressed: _pickTagPaths,
                icon: const Icon(Icons.sell_outlined, size: 18),
                label: Text(
                  _tagPaths.isEmpty
                      ? l10n.settingsQuestionPackFilterTagSelect
                      : l10n.settingsQuestionPackFilterTagsSelected(
                          _tagPaths.length,
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.settingsQuestionPackFilterSerialRange,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _serialFrom,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.settingsQuestionPackFilterSerialFrom,
                        hintText: l10n.settingsQuestionPackFilterSerialHint,
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _serialTo,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.settingsQuestionPackFilterSerialTo,
                        hintText: l10n.settingsQuestionPackFilterSerialHint,
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              if (issue != QuestionPackSerialRangeIssue.none) ...[
                const SizedBox(height: 8),
                Text(
                  _serialIssueText(l10n, issue),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: issue == QuestionPackSerialRangeIssue.none
              ? () => Navigator.of(context).pop(_selection())
              : null,
          child: Text(l10n.settingsQuestionPackFilterExport),
        ),
      ],
    );
  }
}

String _serialIssueText(
  AppLocalizations l10n,
  QuestionPackSerialRangeIssue issue,
) {
  return switch (issue) {
    QuestionPackSerialRangeIssue.invalidFrom ||
    QuestionPackSerialRangeIssue.invalidTo =>
      l10n.settingsQuestionPackFilterSerialInvalid,
    QuestionPackSerialRangeIssue.reversed =>
      l10n.settingsQuestionPackFilterSerialReversed,
    QuestionPackSerialRangeIssue.none => '',
  };
}
