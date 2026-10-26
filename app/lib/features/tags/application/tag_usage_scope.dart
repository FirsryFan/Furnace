/// 标签用途边界（schema v37，docs/REVIEW_FEEDBACK.md §10：“标签系统到处都有，没有边界处理”）。
///
/// 时间表与闪卡各接过一次；这里把「某个域的选择器只看属于本域的标签」收成一个
/// 共享 helper，题库（question）、任务（task）、认知测评范围（knowledge）共用，
/// 避免三份复制粘贴的过滤逻辑。
///
/// 解析口径不在这里重写：继承/整树无声明=不限制都在 [TagUsageResolver] 里，
/// 本文件只负责读库、过滤、保序与界面文案。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/tags/tag_usage.dart';
import '../../../l10n/app_localizations.dart';
import 'tag_usage_providers.dart';

/// 某用途下的一次标签快照。
@immutable
class TagUsageScope {
  const TagUsageScope({
    required this.usage,
    required this.tags,
    required this.visibleTags,
    required this.hasAnyDeclaration,
  });

  /// 空态对话框的 Key（测试定位用）。
  static const Key emptyDialogKey = Key('tag-usage-scope-empty');

  /// 这个选择器属于哪个域。
  final TagUsage usage;

  /// 整棵标签树里的全部标签（顺序沿用读取顺序）。
  final List<Tag> tags;

  /// 只保留本用途可见的标签（顺序沿用 [tags]）。
  final List<Tag> visibleTags;

  /// 树里是否有任何标签声明过用途。
  ///
  /// 用来区分两种空：「还没设过边界（默认全部可选）」与「设过了但没有本域的
  /// 标签（应提示去标签树补用途）」。
  final bool hasAnyDeclaration;

  /// 本域一个可选标签都没有。
  bool get isEmpty => visibleTags.isEmpty;
}

/// 纯函数：用解析器把一批标签过滤成 [usage] 的可见集合。
TagUsageScope buildTagUsageScope({
  required TagUsage usage,
  required Iterable<Tag> tags,
  required TagUsageResolver resolver,
}) {
  final all = tags.toList(growable: false);
  final visibleIds =
      resolver.visibleOf(all.map((tag) => tag.id), usage).toSet();
  return TagUsageScope(
    usage: usage,
    tags: all,
    visibleTags: <Tag>[
      for (final tag in all)
        if (visibleIds.contains(tag.id)) tag,
    ],
    hasAnyDeclaration: resolver.hasAnyDeclaration,
  );
}

/// 读一次库 + 解析器：某个域的选择器该显示哪些标签。
Future<TagUsageScope> loadTagUsageScope(WidgetRef ref, TagUsage usage) async {
  final tags = await ref.read(tagRepositoryProvider).getAllTags();
  final resolver = await ref.read(tagUsageResolverProvider.future);
  return buildTagUsageScope(usage: usage, tags: tags, resolver: resolver);
}

/// 用途在界面上的名字（题库 / 任务 / 知识网络）。
///
/// 时间表与闪卡已有各自的专用文案；传进来属于接线错误，直接抛。
String tagUsageLabel(AppLocalizations l10n, TagUsage usage) => switch (usage) {
      TagUsage.question => l10n.tagUsageQuestion,
      TagUsage.task => l10n.tagUsageTask,
      TagUsage.knowledge => l10n.tagUsageKnowledge,
      _ => throw ArgumentError.value(
          usage,
          'usage',
          '没有为这个标签用途定义界面名字',
        ),
    };

/// 选择器顶部的范围提示。
///
/// 没声明过就说明「默认全列」；声明过就说明「只显示本域的标签」。
String tagUsageScopeHint(AppLocalizations l10n, TagUsageScope scope) =>
    scope.hasAnyDeclaration
        ? l10n.tagUsageScopeHintNamed(tagUsageLabel(l10n, scope.usage))
        : l10n.tagUsageScopeDefaultHint;

/// 「设过边界但本域没有标签」的空态说明。
String tagUsageScopeEmptyText(AppLocalizations l10n, TagUsageScope scope) =>
    l10n.tagUsageScopeEmptyNamed(tagUsageLabel(l10n, scope.usage));

/// 弹一个空态对话框：告诉用户去标签树设用途，而不是给一个空列表。
Future<void> showTagUsageScopeEmptyDialog(
  BuildContext context,
  TagUsage usage, {
  required AppLocalizations l10n,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: TagUsageScope.emptyDialogKey,
      title: Text(l10n.tagUsageDialogTitle),
      content: Text(l10n.tagUsageScopeEmptyNamed(tagUsageLabel(l10n, usage))),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    ),
  );
}
