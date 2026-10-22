/// 题库批量打标签的应用层：把「选中的题目 + 选中的标签路径」真正落进
/// `object_tags`，并返回一份可以直接上屏的报告。
///
/// 分工：
/// * 纯逻辑算「哪些路径能挂、哪些题已挂过、要新增几条」在
///   `planQuestionBulkTag`（`domain/services/questions/question_bulk_tag_plan.dart`）；
/// * 本层只做三件脏活：读标签词表与每道题已挂标签、按路径解析 tagId、
///   逐路径调 `TagRepository.addTagToObjects` 批量写入。
///
/// 口径：
/// * 题 id 与标签路径都 trim、去空、去重保序；任一边为空 → 空报告、不碰库；
/// * 标签路径取 `tag.path`，path 为空时回落 `tag.name`（与标签树显示一致）；
/// * 词表里没有的路径进 [QuestionBulkTagReport.missingTagPaths]，不写任何行；
/// * 某条路径写入抛异常只记进 [QuestionBulkTagReport.failedTagPaths]，
///   继续处理下一条路径（不因为一个坏标签丢掉整批）；
/// * [QuestionBulkTagReport.affectedQuestionCount] 只数真正新增过链接的题，
///   不是计划里的题数（写入失败时不会虚报）。
library;

import '../../../data/database/database.dart' show Tag;
import '../../../data/repositories/tag_repository.dart';
import '../../../domain/services/questions/question_bulk_tag_plan.dart';

/// 批量打标签作用的对象类型（题库题目）。
const String kQuestionBulkTagObjectType = 'question';

/// 一次批量打标签的结果（构造后不可变）。
class QuestionBulkTagReport {
  const QuestionBulkTagReport({
    required this.addedLinks,
    required this.skippedLinks,
    required this.affectedQuestionCount,
    required this.missingTagPaths,
    required this.failedTagPaths,
  });

  /// 什么都没做（没有请求、或请求为空）。
  static const QuestionBulkTagReport empty = QuestionBulkTagReport(
    addedLinks: 0,
    skippedLinks: 0,
    affectedQuestionCount: 0,
    missingTagPaths: <String>[],
    failedTagPaths: <String>[],
  );

  /// 真正写进 `object_tags` 的新链接数。
  final int addedLinks;

  /// 因为题目已经挂过该标签而跳过的链接数。
  final int skippedLinks;

  /// 至少新增了一个标签的题数。
  final int affectedQuestionCount;

  /// 标签词表里没有的路径（按请求顺序）。
  final List<String> missingTagPaths;

  /// 解析或写入失败的路径（按请求顺序）。
  final List<String> failedTagPaths;

  /// 没有任何动作、也没有任何问题。
  bool get isEmpty =>
      addedLinks == 0 &&
      skippedLinks == 0 &&
      missingTagPaths.isEmpty &&
      failedTagPaths.isEmpty;

  /// [isEmpty] 的取反。
  bool get isNotEmpty => !isEmpty;

  /// 是否有词表里没有的标签路径。
  bool get hasMissingTagPaths => missingTagPaths.isNotEmpty;

  /// 是否有写入失败的标签路径。
  bool get hasFailures => failedTagPaths.isNotEmpty;

  @override
  String toString() {
    return 'QuestionBulkTagReport(added: $addedLinks, skipped: $skippedLinks, '
        'affected: $affectedQuestionCount, missing: ${missingTagPaths.length}, '
        'failed: ${failedTagPaths.length})';
  }
}

/// 给 [questionIds] 批量挂 [tagPaths] 指定的标签。
///
/// [tags] 由调用方注入（测试可换 fake）；本函数不缓存词表、不碰 UI。
Future<QuestionBulkTagReport> tagQuestions({
  required TagRepository tags,
  required Iterable<String> questionIds,
  required Iterable<String> tagPaths,
}) async {
  final ids = _normalized(questionIds);
  final requested = _normalized(tagPaths);
  if (ids.isEmpty || requested.isEmpty) {
    return QuestionBulkTagReport.empty;
  }

  final allTags = await tags.getAllTags();
  final idByPath = <String, String>{};
  for (final tag in allTags) {
    final path = _pathOf(tag);
    if (path.isEmpty) {
      continue;
    }
    idByPath.putIfAbsent(path, () => tag.id);
  }

  final existing = <String, Set<String>>{};
  for (final id in ids) {
    final linked = await tags.tagsForObject(
      objectType: kQuestionBulkTagObjectType,
      objectId: id,
    );
    existing[id] = <String>{
      for (final tag in linked)
        if (_pathOf(tag).isNotEmpty) _pathOf(tag),
    };
  }

  final plan = planQuestionBulkTag(
    questionIds: ids,
    tagPaths: requested,
    knownTagPaths: idByPath.keys,
    existingTagPathsByQuestionId: existing,
  );

  var added = 0;
  final affected = <String>{};
  final failed = <String>[];
  for (final entry in plan.questionIdsByTagPath.entries) {
    final tagId = idByPath[entry.key];
    if (tagId == null) {
      failed.add(entry.key);
      continue;
    }
    try {
      final count = await tags.addTagToObjects(
        tagId: tagId,
        objectIds: entry.value,
        objectType: kQuestionBulkTagObjectType,
      );
      added += count;
      if (count > 0) {
        affected.addAll(entry.value);
      }
    } on Object {
      failed.add(entry.key);
    }
  }

  return QuestionBulkTagReport(
    addedLinks: added,
    skippedLinks: plan.skippedExistingLinkCount,
    affectedQuestionCount: affected.length,
    missingTagPaths: plan.missingTagPaths,
    failedTagPaths: List<String>.unmodifiable(failed),
  );
}

String _pathOf(Tag tag) {
  final path = tag.path?.trim();
  if (path != null && path.isNotEmpty) {
    return path;
  }
  return tag.name.trim();
}

List<String> _normalized(Iterable<String> raw) {
  final out = <String>[];
  final seen = <String>{};
  for (final value in raw) {
    final clean = value.trim();
    if (clean.isEmpty || !seen.add(clean)) {
      continue;
    }
    out.add(clean);
  }
  return out;
}
