/// 题库标签筛选对话框：从题库现有标签路径里多选，确定后回填筛选条件。
///
/// 路径清单由调用方（题库页）从 `QuestionLibrarySnapshot.tagPaths` 传入，对话框
/// 本身不读库；返回 `Set<String>`（确定）、空集（清除标签筛选）或 `null`（取消）。
/// 匹配口径由 `question_library_filter.dart` 负责：父路径命中其所有子孙标签。
library;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// 对话框本体（测试定位用）。
const Key questionLibraryTagFilterDialogKey = Key(
  'question-library-tag-filter-dialog',
);

/// 搜索框（测试定位用）。
const Key questionLibraryTagFilterSearchKey = Key(
  'question-library-tag-filter-search',
);

/// 「清除标签」按钮（测试定位用）：返回空集。
const Key questionLibraryTagFilterClearKey = Key(
  'question-library-tag-filter-clear',
);

/// 「确定」按钮（测试定位用）：返回当前勾选集合。
const Key questionLibraryTagFilterConfirmKey = Key(
  'question-library-tag-filter-confirm',
);

/// 打开标签筛选对话框；取消/点外部返回 `null`。
Future<Set<String>?> showQuestionLibraryTagFilterDialog(
  BuildContext context, {
  required List<String> tagPaths,
  Set<String> initialSelection = const <String>{},
}) {
  return showDialog<Set<String>>(
    context: context,
    builder: (context) => QuestionLibraryTagFilterDialog(
      tagPaths: tagPaths,
      initialSelection: initialSelection,
    ),
  );
}

/// 标签路径多选面板。
class QuestionLibraryTagFilterDialog extends StatefulWidget {
  const QuestionLibraryTagFilterDialog({
    super.key,
    required this.tagPaths,
    this.initialSelection = const <String>{},
  });

  /// 候选路径（页面传 snapshot.tagPaths；这里会去空、去重、排序）。
  final List<String> tagPaths;

  /// 进来时已经勾上的路径。
  final Set<String> initialSelection;

  @override
  State<QuestionLibraryTagFilterDialog> createState() =>
      _QuestionLibraryTagFilterDialogState();
}

class _QuestionLibraryTagFilterDialogState
    extends State<QuestionLibraryTagFilterDialog> {
  late final TextEditingController _search;
  late final List<String> _paths;
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
    _paths = <String>{
      for (final path in widget.tagPaths)
        if (path.trim().isNotEmpty) path.trim(),
    }.toList()
      ..sort();
    _selected = <String>{
      for (final path in widget.initialSelection)
        if (path.trim().isNotEmpty) path.trim(),
    };
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> _visible() {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _paths;
    }
    return <String>[
      for (final path in _paths)
        if (path.toLowerCase().contains(query)) path,
    ];
  }

  void _toggle(String path, bool? selected) {
    setState(() {
      if (selected == true) {
        _selected.add(path);
      } else {
        _selected.remove(path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final Widget emptyHint = Center(
      child: Text(l10n.questionBulkTagNoMatch, textAlign: TextAlign.center),
    );
    return AlertDialog(
      key: questionLibraryTagFilterDialogKey,
      title: Text(l10n.questionBankTagFilterTitle),
      content: SizedBox(
        width: 520,
        height: 420,
        child: _paths.isEmpty
            ? emptyHint
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    key: questionLibraryTagFilterSearchKey,
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: l10n.questionBulkTagSearchHint,
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final visible = _visible();
                        if (visible.isEmpty) {
                          return emptyHint;
                        }
                        return ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final path = visible[index];
                            return CheckboxListTile(
                              value: _selected.contains(path),
                              onChanged: (value) => _toggle(path, value),
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                path,
                                style: theme.textTheme.bodySmall,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: <Widget>[
        TextButton(
          key: questionLibraryTagFilterClearKey,
          onPressed: () => Navigator.of(context).pop(const <String>{}),
          child: Text(l10n.questionBankTagFilterClear),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: questionLibraryTagFilterConfirmKey,
          onPressed: () => Navigator.of(context).pop(_selected.toSet()),
          child: Text(l10n.commonConfirm),
        ),
      ],
    );
  }
}
