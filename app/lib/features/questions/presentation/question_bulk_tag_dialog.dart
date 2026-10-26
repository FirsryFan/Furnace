/// 题库批量打标签对话框：列出标签词表（按路径排序）、可搜索、多选。
///
/// 面板只负责「选哪些标签路径」；真正写库由 `tagQuestions`（应用层）完成，
/// 调用方拿到 [Set] 后自己执行并上屏报告。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/tags/tag_usage.dart';
import '../../../l10n/app_localizations.dart';
import '../../tags/application/tag_usage_scope.dart';

/// 对话框本体（测试定位用）。
const Key questionBulkTagDialogKey = Key('question-bulk-tag-dialog');

/// 搜索框（测试定位用）。
const Key questionBulkTagSearchKey = Key('question-bulk-tag-search');

/// 「添加标签」确认按钮（测试定位用）。
const Key questionBulkTagConfirmKey = Key('question-bulk-tag-confirm');

/// 打开批量打标签对话框；取消/点外部返回 `null`。
Future<Set<String>?> showQuestionBulkTagDialog(BuildContext context) {
  return showDialog<Set<String>>(
    context: context,
    builder: (context) => const QuestionBulkTagDialog(),
  );
}

class QuestionBulkTagDialog extends ConsumerStatefulWidget {
  const QuestionBulkTagDialog({super.key});

  @override
  ConsumerState<QuestionBulkTagDialog> createState() =>
      _QuestionBulkTagDialogState();
}

class _QuestionBulkTagDialogState extends ConsumerState<QuestionBulkTagDialog> {
  late final TextEditingController _search;
  late final Future<TagUsageScope> _scopeFuture;
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
    _scopeFuture = _loadScope();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 只取「题库」用途可见的标签；整棵树还没声明过用途时全部可见。
  Future<TagUsageScope> _loadScope() =>
      loadTagUsageScope(ref, TagUsage.question);

  /// 标签路径：`tag.path` 优先，空时回落 `tag.name`（与标签树/打标签服务一致）；
  /// 去重、去空、按路径排序。
  List<String> _paths(TagUsageScope scope) {
    final paths = <String>{
      for (final tag in scope.visibleTags)
        if ((tag.path ?? '').trim().isNotEmpty)
          tag.path!.trim()
        else if (tag.name.trim().isNotEmpty)
          tag.name.trim(),
    };
    return paths.toList()..sort();
  }

  List<String> _visible(List<String> paths) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) {
      return paths;
    }
    return <String>[
      for (final path in paths)
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
    return AlertDialog(
      key: questionBulkTagDialogKey,
      title: Text(l10n.questionBulkTagDialogTitle),
      content: SizedBox(
        width: 520,
        height: 420,
        child: FutureBuilder<TagUsageScope>(
          future: _scopeFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  l10n.questionBankTagFailed('${snapshot.error}'),
                  textAlign: TextAlign.center,
                ),
              );
            }
            final scope = snapshot.data;
            if (scope == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (scope.tags.isEmpty) {
              // 整棵标签树是空的：沿用老口径的「没有匹配的标签」。
              return Center(child: Text(l10n.questionBulkTagNoMatch));
            }
            if (scope.isEmpty) {
              // 树里设过用途，但没有一个属于题库：说清楚比给空列表有用。
              return Center(
                child: Text(
                  tagUsageScopeEmptyText(l10n, scope),
                  textAlign: TextAlign.center,
                ),
              );
            }
            final visible = _visible(_paths(scope));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  tagUsageScopeHint(l10n, scope),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                TextField(
                  key: questionBulkTagSearchKey,
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
                  child: visible.isEmpty
                      ? Center(child: Text(l10n.questionBulkTagNoMatch))
                      : ListView.builder(
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
                        ),
                ),
              ],
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: questionBulkTagConfirmKey,
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected.toSet()),
          child: Text(l10n.questionBulkTagConfirm),
        ),
      ],
    );
  }
}
