/// 闪卡域的标签范围：用户只该看到、只该选到「纳入闪卡」的标签。
///
/// v37 起标签行带用途声明（`tags.usage_codes`，继承在读取时算，见
/// `domain/services/tags/tag_usage.dart`）。闪卡域的三个选择器——知识点列表
/// 新建卡片的「卡组」下拉、「给知识点加标签」对话框、复习计划的卡组选择——
/// 都从这里取候选，口径与时间表的标签选择器（`time_board_page.dart`）一致：
///
///  * **整棵树没有任何用途声明 = 不限制**，所有标签都可见（默认行为，升级不丢标签）；
///  * 过滤只影响候选列表，已经挂在知识点上的标签照常显示、可删；
///  * 过滤后为空不是错误：弹一个只有「关闭」的说明框，区分「有人设过用途但都
///    不含闪卡」与「整棵树没设过用途、只是都已选过」，绝不静默 return。
///
/// 本文件只读：不写库、不改用途（用途在标签树里设置）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/tags/tag_usage.dart';
import '../../../l10n/app_localizations.dart';
import '../../tags/application/tag_usage_providers.dart';

/// 闪卡域「没有可选标签」说明框的 key（widget 测试用它定位）。
const Key flashcardTagScopeEmptyKey =
    ValueKey<String>('flashcard-tag-scope-empty');

/// 一次标签快照 + 用途解析器，供闪卡域的选择器共用。
class FlashcardTagScope {
  const FlashcardTagScope({required this.tags, required this.resolver});

  /// 整棵树的标签，已按 `path ?? name` 升序（与各选择器原来的顺序一致）。
  final List<Tag> tags;

  /// 解析继承生效后的用途；未知 id 对解析器是安全的。
  final TagUsageResolver resolver;

  /// 闪卡域可见的标签，保持 [tags] 的顺序。
  List<Tag> get visibleTags => filterFlashcardTags(resolver, tags);

  /// 闪卡域一个标签都选不了（≠ 整棵树没有标签）。
  bool get isEmpty => visibleTags.isEmpty;

  /// 整棵树是否有人设过用途（用来解释「为什么没有可选的」）。
  bool get hasAnyDeclaration => resolver.hasAnyDeclaration;
}

/// 读用途解析器；provider 已 watch 数据库版本，改用途/改标签后自动重算。
Future<TagUsageResolver> flashcardTagResolver(WidgetRef ref) =>
    ref.read(tagUsageResolverProvider.future);

/// 只保留 `TagUsage.flashcard` 可见的标签，**保持输入顺序**；未知 id 安全。
List<Tag> filterFlashcardTags(TagUsageResolver resolver, Iterable<Tag> tags) {
  final visibleIds =
      resolver.visibleOf(tags.map((tag) => tag.id), TagUsage.flashcard).toSet();
  return <Tag>[
    for (final tag in tags)
      if (visibleIds.contains(tag.id)) tag,
  ];
}

/// 读一次整棵树的标签并解析用途：闪卡域所有选择器的唯一入口。
Future<FlashcardTagScope> loadFlashcardTagScope(WidgetRef ref) async {
  final tags = await ref.read(tagRepositoryProvider).getAllTags();
  tags.sort((a, b) => (a.path ?? a.name).compareTo(b.path ?? b.name));
  final resolver = await flashcardTagResolver(ref);
  return FlashcardTagScope(tags: tags, resolver: resolver);
}

/// 过滤后没有候选时的说明框：只有「关闭」，不静默返回。
Future<void> showFlashcardTagScopeEmptyDialog(
  BuildContext context, {
  required bool hasAnyDeclaration,
}) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      key: flashcardTagScopeEmptyKey,
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      children: [
        Text(
          hasAnyDeclaration
              ? l10n.tagUsageScopeEmptyFlashcard
              : l10n.tagUsageScopeDefaultHint,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.commonClose),
          ),
        ),
      ],
    ),
  );
}
