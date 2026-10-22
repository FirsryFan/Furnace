/// 题库筛选条：搜索框 + 标签筛选按钮 + 已选标签 chips + 筛选计数/清除。
///
/// 无状态：筛选值存在题库页 State 的 `QuestionLibraryFilter` 里，搜索框
/// controller 也由页面持有并在这里复用（清除筛选时页面要能同步清空文字）。
/// 搜索/标签/学科三个条件是 AND 关系；这个条只收集输入，不自己过滤。
library;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// 搜索框（测试定位用）。
const Key questionBankSearchKey = Key('question-bank-search');

/// 搜索框里的「清空文字」按钮（测试定位用；只在有字时出现）。
const Key questionBankSearchClearKey = Key('question-bank-search-clear');

/// 「按标签筛选」按钮（测试定位用）；按钮文字同时显示已选标签数。
const Key questionBankTagFilterKey = Key('question-bank-tag-filter');

/// 「清除筛选」按钮（测试定位用）；只在筛选生效时出现。
const Key questionBankClearFilterKey = Key('question-bank-clear-filter');

/// 「已筛出 X / 共 Y 道」计数（测试定位用）。
const Key questionBankFilteredCountKey = Key('question-bank-filtered-count');

/// 无命中空态里的「清除筛选」按钮（测试定位用）。
///
/// 与筛选条里的 [questionBankClearFilterKey] 分开：无命中时两个按钮同时在树里，
/// 复用同一个 key 会让 `find.byKey` 二义。
const Key questionBankNoMatchClearFilterKey = Key(
  'question-bank-no-match-clear-filter',
);

/// 已选标签 chip 的 key（测试定位用）。
String questionBankTagChipKeyFor(String path) => 'question-bank-tag-chip-$path';

/// 标签 chip 上的叶子名（`文化课/数学` → `数学`）；空路径返回空串。
String questionLibraryTagChipLabel(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final slash = trimmed.lastIndexOf('/');
  return slash < 0 ? trimmed : trimmed.substring(slash + 1);
}

/// 题库列表上方的筛选条。
class QuestionLibraryFilterBar extends StatelessWidget {
  const QuestionLibraryFilterBar({
    super.key,
    required this.searchController,
    required this.selectedTagPaths,
    required this.shownCount,
    required this.totalCount,
    required this.filterActive,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onOpenTagFilter,
    required this.onRemoveTagPath,
    required this.onClear,
  });

  /// 搜索词输入框（页面持有，清除筛选时要一起清空）。
  final TextEditingController searchController;

  /// 已选标签路径（排序后展示；点 chip 的 × 单独移除）。
  final List<String> selectedTagPaths;

  /// 筛出条数 / 参与筛选的总条数（只统计已加载条目）。
  final int shownCount;
  final int totalCount;

  /// 是否有任何筛选生效（决定是否显示计数行）。
  final bool filterActive;

  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onOpenTagFilter;
  final ValueChanged<String> onRemoveTagPath;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tagCount = selectedTagPaths.length;
    final hasSearch = searchController.text.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                key: questionBankSearchKey,
                controller: searchController,
                decoration: InputDecoration(
                  hintText: l10n.questionBankSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: hasSearch
                      ? IconButton(
                          key: questionBankSearchClearKey,
                          tooltip: l10n.questionBankFilterClear,
                          onPressed: onClearSearch,
                          icon: const Icon(Icons.close),
                        )
                      : null,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.search,
                onChanged: onSearchChanged,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              key: questionBankTagFilterKey,
              onPressed: onOpenTagFilter,
              icon: const Icon(Icons.label_outline, size: 18),
              label: Text(
                tagCount == 0
                    ? l10n.questionBankTagFilterTitle
                    : l10n.questionBankTagFilterSelected(tagCount),
              ),
            ),
          ],
        ),
        if (tagCount > 0) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final path in selectedTagPaths)
                // InputChip 自带 tooltip 只在可点击（有 onPressed/onSelected）时生效，
                // 这里 chip 只做展示 + 删除，所以自己包一层 Tooltip。
                Tooltip(
                  message: path,
                  child: InputChip(
                    key: ValueKey(questionBankTagChipKeyFor(path)),
                    label: Text(questionLibraryTagChipLabel(path)),
                    onDeleted: () => onRemoveTagPath(path),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
        ],
        if (filterActive) ...[
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.questionBankFilteredCount(shownCount, totalCount),
                  key: questionBankFilteredCountKey,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                key: questionBankClearFilterKey,
                onPressed: onClear,
                child: Text(l10n.questionBankFilterClear),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
