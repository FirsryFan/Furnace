/// 题库包导出筛选的「标签路径」选择：选项数据源 + 二级选择对话框。
///
/// 选项来自标签仓库（路径 + 该路径下的题目数），排序与截断交给纯逻辑
/// `domain/services/package/question_pack_tag_options.dart`；本文件只做
/// 「路径映射、搜索、勾选」这些界面层的事，不实现筛选语义。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/package/question_pack_tag_options.dart';
import '../../../l10n/app_localizations.dart';

/// 标签路径选择对话框的「取消」按钮（测试用稳定定位）。
const Key questionPackTagPickerCancelKey =
    ValueKey<String>('question-pack-tag-picker-cancel');

/// 标签路径选择对话框的「确认」按钮（测试用稳定定位）。
const Key questionPackTagPickerConfirmKey =
    ValueKey<String>('question-pack-tag-picker-confirm');

/// 题库包导出可用的标签路径选项（题数降序 -> 路径升序）。
///
/// 题目记录里的 `tagPaths` 存的是标签的权威路径（`tag.path`，为空时退化为
/// `tag.name`，与标签树一致），所以这里按同一规则把标签行映射成路径，再把
/// `object_tags` 里 `object_type = 'question'` 的计数累加到路径上。
final questionPackTagPathOptionsProvider =
    FutureProvider<List<QuestionPackTagPathOption>>((ref) async {
  ref.watchDatabaseRevision();
  final tags = await ref.watch(tagRepositoryProvider).getAllTags();
  final counts = await ref
      .watch(tagRepositoryProvider)
      .objectCountByTagId(objectTypes: const <String>{'question'});
  return questionPackTagPathOptionsFromTags(
    tags: tags,
    questionCountByTagId: counts,
  );
});

/// 把标签行整理成筛选选项：同一路径的题数相加，空名字的标签丢弃。
List<QuestionPackTagPathOption> questionPackTagPathOptionsFromTags({
  required Iterable<Tag> tags,
  Map<String, int> questionCountByTagId = const <String, int>{},
  int maxOptionCount = 200,
}) {
  final List<String> tagPaths = <String>[];
  final Map<String, int> countsByPath = <String, int>{};
  for (final Tag tag in tags) {
    final String? storedPath = tag.path;
    final String path =
        storedPath == null || storedPath.isEmpty ? tag.name : storedPath;
    if (path.trim().isEmpty) {
      continue;
    }
    tagPaths.add(path);
    final int count = questionCountByTagId[tag.id] ?? 0;
    countsByPath[path] = (countsByPath[path] ?? 0) + (count < 0 ? 0 : count);
  }
  return questionPackTagPathOptions(
    tagPaths: tagPaths,
    questionCountByPath: countsByPath,
    maxOptionCount: maxOptionCount,
  );
}

/// 二级对话框：搜索 + 复选标签路径，确认返回选中的路径集合，取消返回 null。
class QuestionPackTagPathPickerDialog extends ConsumerStatefulWidget {
  const QuestionPackTagPathPickerDialog({
    super.key,
    this.initialSelection = const <String>{},
  });

  /// 打开时已经选中的路径；再次打开时保留上次的选择。
  final Set<String> initialSelection;

  @override
  ConsumerState<QuestionPackTagPathPickerDialog> createState() =>
      _QuestionPackTagPathPickerDialogState();
}

class _QuestionPackTagPathPickerDialogState
    extends ConsumerState<QuestionPackTagPathPickerDialog> {
  late final Set<String> _selected =
      selectedQuestionPackTagPaths(widget.initialSelection).toSet();
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String path, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(path);
      } else {
        _selected.remove(path);
      }
    });
  }

  /// 选项池 = 仓库里的路径 + 已选但已从题库消失的路径（计 0，防止选不中
  /// 也取消不掉）；随后按搜索词过滤，但已选项始终保留。
  List<QuestionPackTagPathOption> _visibleOptions(
    List<QuestionPackTagPathOption> base,
  ) {
    final List<String> pool = <String>[
      for (final QuestionPackTagPathOption option in base) option.path,
    ];
    final Map<String, int> counts = <String, int>{
      for (final QuestionPackTagPathOption option in base)
        option.path: option.questionCount,
    };
    for (final String path in _selected) {
      if (counts.containsKey(path)) continue;
      pool.add(path);
      counts[path] = 0;
    }
    final List<QuestionPackTagPathOption> options = questionPackTagPathOptions(
      tagPaths: pool,
      questionCountByPath: counts,
      selectedPaths: _selected,
    );
    final String query = _search.text.trim().toLowerCase();
    if (query.isEmpty) {
      return options;
    }
    return <QuestionPackTagPathOption>[
      for (final QuestionPackTagPathOption option in options)
        if (option.selected || option.path.toLowerCase().contains(query))
          option,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<QuestionPackTagPathOption>> optionsAsync =
        ref.watch(questionPackTagPathOptionsProvider);
    final double listHeight =
        (MediaQuery.sizeOf(context).height * 0.6).clamp(240.0, 460.0);
    return AlertDialog(
      title: Text(l10n.settingsQuestionPackTagPickerTitle),
      content: SizedBox(
        width: 560,
        height: listHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.settingsQuestionPackTagPickerSearch,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: optionsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object error, StackTrace stack) =>
                    Center(child: Text('$error')),
                data: (List<QuestionPackTagPathOption> base) {
                  final List<QuestionPackTagPathOption> visible =
                      _visibleOptions(base);
                  if (visible.isEmpty) {
                    return Center(
                      child: Text(
                        base.isEmpty
                            ? l10n.settingsQuestionPackTagPickerEmpty
                            : l10n.settingsQuestionPackTagPickerNoMatch,
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (BuildContext context, int index) {
                      final QuestionPackTagPathOption option = visible[index];
                      return CheckboxListTile(
                        value: option.selected,
                        onChanged: (bool? value) =>
                            _toggle(option.path, value ?? false),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          '${option.path} · '
                          '${l10n.settingsQuestionPackTagQuestionCount(option.questionCount)}',
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
          key: questionPackTagPickerCancelKey,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: questionPackTagPickerConfirmKey,
          onPressed: () => Navigator.of(context).pop(_selected),
          child: Text(l10n.commonConfirm),
        ),
      ],
    );
  }
}
