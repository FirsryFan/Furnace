import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/repositories/tag_repository.dart';
import '../../../domain/services/tags/tag_usage.dart';

/// 标签用途解析器（v37，轮次一百七十六；docs/REVIEW_FEEDBACK.md §10/§11）。
///
/// 任何写库都会让 [dataRevisionProvider] 变，从而重算——标签改名/移动/改用途后
/// 时间表与标签树的选择器自动刷新，不需要手动 invalidate。
final tagUsageResolverProvider =
    FutureProvider.autoDispose<TagUsageResolver>((ref) async {
  ref.watchDatabaseRevision();
  final TagRepository repository = ref.watch(tagRepositoryProvider);
  final tags = await repository.getAllTags();
  return repository.resolverFor(tags);
});

/// 保存一个标签的用途声明，并刷新解析器。
///
/// 失败原样上抛：调用方（标签树对话框）负责提示，别在 helper 里吞掉。
Future<void> setTagUsages(
  WidgetRef ref,
  String tagId,
  Set<TagUsage> usages,
) async {
  await ref.read(tagRepositoryProvider).updateTagUsageCodes(tagId, usages);
  ref.invalidate(tagUsageResolverProvider);
}
