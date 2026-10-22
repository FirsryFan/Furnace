/// 题目命名对话框：题库列表行的「改名」与题目详情页的笔形按钮共用同一个入口。
///
/// 对话框自己负责写库（`setQuestionTitle`）并让题库两档数据源（前 500 题总览 /
/// 筛选生效时的全库）与题目详情读表 provider 一起失效，调用方拿到的只是「用户
/// 最终改成了什么」，不需要再碰 repository。
/// 列表顶部的批量自动命名复用下面的纯函数 [suggestBulkQuestionTitles]。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/questions/question_title_suggestion.dart';
import '../../../l10n/app_localizations.dart';
import '../application/question_library_provider.dart';
import 'question_detail_providers.dart';

/// 题名输入框。
const Key questionTitleFieldKey = Key('question-title-field');

/// 「自动生成」按钮。
const Key questionTitleAutoButtonKey = Key('question-title-auto');

/// 「保存」按钮。
const Key questionTitleSaveButtonKey = Key('question-title-save');

/// 「清除题名」按钮。
const Key questionTitleClearButtonKey = Key('question-title-clear');

/// 详情页/列表行上的改名入口图标。
const Key questionTitleEditButtonKey = Key('question-title-edit');

/// 列表行 ⋮ 菜单按题 id 生成 key：`question-bank-menu-<questionId>`。
String questionBankRowMenuKeyFor(String questionId) =>
    'question-bank-menu-$questionId';

/// 改完题名后回给调用方的东西。
///
/// [title] 是归一化之后的题名（`null` = 用户清除了题名）；[changed] 表示这次是否
/// 真的写了库（用户原样保存或直接取消时为 false，调用方据此决定要不要提示）。
class QuestionTitleDialogResult {
  const QuestionTitleDialogResult({required this.title, required this.changed});

  final String? title;
  final bool changed;
}

/// 打开题目命名对话框；用户取消时返回 `null`。
Future<QuestionTitleDialogResult?> showQuestionTitleDialog(
  BuildContext context, {
  required String questionId,
  required String stem,
  String? currentTitle,
  String? subjectKey,
  String? questionType,
  List<String> knowledgePointNames = const <String>[],
  List<String> existingTitles = const <String>[],
}) {
  return showDialog<QuestionTitleDialogResult>(
    context: context,
    builder: (context) => QuestionTitleDialog(
      questionId: questionId,
      stem: stem,
      currentTitle: currentTitle,
      subjectKey: subjectKey,
      questionType: questionType,
      knowledgePointNames: knowledgePointNames,
      existingTitles: existingTitles,
    ),
  );
}

/// 命名对话框本体：输入框 + 自动生成 + 清除 + 取消 + 保存。
class QuestionTitleDialog extends ConsumerStatefulWidget {
  const QuestionTitleDialog({
    super.key,
    required this.questionId,
    required this.stem,
    this.currentTitle,
    this.subjectKey,
    this.questionType,
    this.knowledgePointNames = const <String>[],
    this.existingTitles = const <String>[],
  });

  final String questionId;
  final String stem;
  final String? currentTitle;
  final String? subjectKey;
  final String? questionType;
  final List<String> knowledgePointNames;
  final List<String> existingTitles;

  @override
  ConsumerState<QuestionTitleDialog> createState() =>
      _QuestionTitleDialogState();
}

class _QuestionTitleDialogState extends ConsumerState<QuestionTitleDialog> {
  /// 与 `isValidQuestionTitle` 默认上限一致；列表上的题名也是这个长度。
  static const int _maxLength = 80;

  late final TextEditingController _controller;
  String? _error;
  bool _saving = false;
  bool _autoFilled = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentTitle ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 按题干 + 学科生成一个建议题名填进输入框；用户还能接着改。
  void _autoGenerate() {
    final suggestion = suggestQuestionTitle(
      stem: widget.stem,
      subjectKey: widget.subjectKey,
      questionType: widget.questionType,
      knowledgePointNames: widget.knowledgePointNames,
      existingTitles: widget.existingTitles,
      maxLength: _maxLength,
    );
    setState(() {
      _controller.text = suggestion.title;
      _controller.selection = TextSelection.collapsed(
        offset: suggestion.title.length,
      );
      _error = null;
      _autoFilled = true;
    });
  }

  /// 保存/清除共用一条路径：空输入就是清除题名。
  Future<void> _commit(String? rawTitle) async {
    final l10n = AppLocalizations.of(context);
    final normalized = normalizeQuestionTitle(rawTitle);
    if (normalized != null &&
        !isValidQuestionTitle(normalized, maxLength: _maxLength)) {
      setState(() => _error = l10n.questionTitleInvalid(_maxLength));
      return;
    }
    if (normalized == normalizeQuestionTitle(widget.currentTitle)) {
      Navigator.of(context).pop(
        QuestionTitleDialogResult(title: normalized, changed: false),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(questionRepositoryProvider)
          .setQuestionTitle(widget.questionId, normalized);
      ref.invalidate(questionLibraryOverviewProvider);
      // 题库页在筛选生效时读全库（questionLibraryFullProvider），只失效总览会
      // 让「从详情页改名后返回筛选态题库」看到旧题名。
      ref.invalidate(questionLibraryFullProvider);
      ref.invalidate(questionDetailProvider(widget.questionId));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              normalized == null
                  ? l10n.questionTitleCleared
                  : l10n.questionTitleSaved,
            ),
          ),
        );
      Navigator.of(context).pop(
        QuestionTitleDialogResult(title: normalized, changed: true),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = l10n.questionTitleSaveFailed('$error');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.questionTitleDialogTitle),
      content: SizedBox(
        width: 460,
        child: TextField(
          key: questionTitleFieldKey,
          controller: _controller,
          autofocus: true,
          enabled: !_saving,
          maxLength: _maxLength,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: l10n.questionTitleFieldLabel,
            hintText: l10n.questionTitleFieldHint,
            helperText: _autoFilled ? l10n.questionTitleAutoFilled : null,
            errorText: _error,
            errorMaxLines: 3,
          ),
          onSubmitted: (value) {
            if (!_saving) {
              _commit(value);
            }
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: questionTitleClearButtonKey,
          onPressed: _saving ? null : () => _commit(null),
          child: Text(l10n.questionTitleClear),
        ),
        TextButton(
          key: questionTitleAutoButtonKey,
          onPressed: _saving ? null : _autoGenerate,
          child: Text(l10n.questionTitleAutoGenerate),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: questionTitleSaveButtonKey,
          onPressed: _saving ? null : () => _commit(_controller.text),
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}

/// 单行「自动命名」用：按这道题的题干/学科生成一个建议题名。
///
/// 返回 `null` 表示生成结果不合法（理论上不该发生，兜底不写库）。
String? suggestQuestionTitleForEntry(
  QuestionLibraryEntry entry, {
  List<String> existingTitles = const <String>[],
  int maxLength = 80,
}) {
  final suggestion = suggestQuestionTitle(
    stem: entry.stem,
    subjectKey: entry.subjectKey,
    questionType: entry.questionType,
    existingTitles: existingTitles,
    maxLength: maxLength,
  );
  if (!isValidQuestionTitle(suggestion.title, maxLength: maxLength)) {
    return null;
  }
  return suggestion.title;
}

/// 批量自动命名：只补没有题名的行；已有题名不动，生成结果之间也不重复。
///
/// 返回 `questionId -> 题名`；空 map 表示「没有需要命名的题」。
Map<String, String> suggestBulkQuestionTitles(
  List<QuestionLibraryEntry> entries, {
  int maxLength = 80,
}) {
  final existingTitles = <String>[
    for (final entry in entries)
      if (entry.hasTitle) entry.title!.trim(),
  ];
  final titles = <String, String>{};
  for (final entry in entries) {
    if (entry.hasTitle) {
      continue;
    }
    final title = suggestQuestionTitleForEntry(
      entry,
      existingTitles: existingTitles,
      maxLength: maxLength,
    );
    if (title == null) {
      continue;
    }
    titles[entry.questionId] = title;
    existingTitles.add(title);
  }
  return titles;
}
