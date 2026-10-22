/// 题库总览的**读表函数**（纯 Dart，不依赖 Riverpod）。
///
/// 题库页要的不是组卷那样的打分输入，而是「一眼扫过去能认出是哪道题」：题名、
/// 题号、第一张大图、标签。此前页面拿 `paperCorpusProvider`（只有 id 与筛选维度）
/// 再配 `questionStemsProvider`，既没有题名也没有标签/图片，所以列表只能显示题干前
/// 两行。这里一次读全，把 UI 需要的东西投影成 [QuestionLibraryEntry]。
///
/// 为什么把读表抽成函数：AI 工具与页面都要读题库，读法只该有一份（与
/// `question_corpus_reader.dart` 同一个理由）；provider 只负责「数据版本 + 调它」。
///
/// 领域分工不变：题号显示走 `domain/services/questions/question_number.dart`，
/// 题名合法性由 `question_title_suggestion.dart` 把关，这个文件只做读表与投影，
/// 不碰 dart:io——图片绝对路径由界面层用 `QuestionMediaStore` 解析。
library;

import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import '../../../domain/services/questions/question_number.dart';

/// 题干图/答案图的角色（与 `QuestionMediaStore` 的 [QuestionImageRole] 同一组值；
/// 这里不复用那个类型，是为了让读表层不 import `dart:io`）。
const String kQuestionLibraryStemRole = 'stem';
const String kQuestionLibraryAnswerRole = 'answer';
const String kQuestionLibrarySolutionRole = 'solution';

/// 题库总览里的一道题的一张图。
class QuestionLibraryImage {
  const QuestionLibraryImage({
    required this.attachmentId,
    required this.relPath,
    required this.role,
    required this.sortOrder,
    this.mime,
  });

  final String attachmentId;

  /// 相对 app support 目录的 POSIX 路径；界面用 `QuestionMediaStore.absolutePath` 解析。
  final String relPath;

  /// `stem` / `answer` / `solution`；旧行的 NULL 在读表时已归一成 `stem`。
  final String role;

  final int sortOrder;
  final String? mime;

  bool get isStem => role == kQuestionLibraryStemRole;
  bool get isAnswer => role == kQuestionLibraryAnswerRole;
  bool get isSolution => role == kQuestionLibrarySolutionRole;

  @override
  String toString() => 'QuestionLibraryImage($role, $relPath)';
}

/// 题库总览里的一行：题目 + 题名/题号 + 标签路径 + 图片。
class QuestionLibraryEntry {
  const QuestionLibraryEntry({
    required this.questionId,
    required this.serialNo,
    this.title,
    required this.stem,
    required this.subjectKey,
    required this.sourceLevel,
    required this.sourceLabel,
    this.year,
    this.region,
    this.questionType = 'solution',
    this.difficulty,
    this.updatedAt = 0,
    this.tagPaths = const <String>[],
    this.stemImages = const <QuestionLibraryImage>[],
    this.answerImages = const <QuestionLibraryImage>[],
    this.solutionImages = const <QuestionLibraryImage>[],
  });

  final String questionId;
  final int? serialNo;

  /// 用户起的名字或自动生成的短名；NULL 表示还没名字。
  final String? title;

  /// 完整题干（含 `$…$` LaTeX 与「［图N］」占位）：批量自动命名需要它。
  final String stem;

  final String subjectKey;
  final String sourceLevel;
  final String sourceLabel;
  final int? year;
  final String? region;
  final String questionType;
  final double? difficulty;
  final int updatedAt;

  /// 这道题直挂的标签路径（`Tags.path`，形如 `文化课/学科/数学`），已去重排序。
  final List<String> tagPaths;

  final List<QuestionLibraryImage> stemImages;
  final List<QuestionLibraryImage> answerImages;
  final List<QuestionLibraryImage> solutionImages;

  /// `TR-00042`；还没编号时给「未编号」，与详情页/搜索口径一致。
  String get serialLabel =>
      serialNo == null ? '未编号' : formatQuestionSerial(serialNo!);

  /// 有名字用名字；没名字回落题干摘要（单行、折叠空白、截断到 40 字）。
  String get displayTitle {
    final named = (title ?? '').trim();
    if (named.isNotEmpty) {
      return named;
    }
    final preview = stemPreview;
    return preview.isEmpty ? '（无题干）' : preview;
  }

  /// 题干摘要（单行、折叠空白、截断到 60 字），供列表副标题兜底。
  String get stemPreview => _preview(stem, max: 60);

  bool get hasTitle => (title ?? '').trim().isNotEmpty;

  /// 列表封面图：先题干图，退答案图，再退解析图。
  QuestionLibraryImage? get coverImage {
    if (stemImages.isNotEmpty) {
      return stemImages.first;
    }
    if (answerImages.isNotEmpty) {
      return answerImages.first;
    }
    if (solutionImages.isNotEmpty) {
      return solutionImages.first;
    }
    return null;
  }

  int get imageCount =>
      stemImages.length + answerImages.length + solutionImages.length;

  @override
  String toString() => 'QuestionLibraryEntry($questionId, $serialLabel)';
}

/// 一次读全的题库总览快照。
class QuestionLibrarySnapshot {
  const QuestionLibrarySnapshot({
    required this.entries,
    required this.totalCount,
    this.truncated = false,
  });

  final List<QuestionLibraryEntry> entries;

  /// 这次读到的行数（受 `limit` 约束）；不是库里题目总数。
  final int totalCount;

  /// 是否因为 `limit` 截断（库里的题比这里多）。
  final bool truncated;

  bool get isEmpty => entries.isEmpty;

  /// 还没名字的题数（批量自动命名的目标）。
  int get untitledCount => entries.where((entry) => !entry.hasTitle).length;

  /// 题库里出现过的学科键（去空、去重、排序）。
  List<String> get subjectKeys {
    final keys = <String>{
      for (final entry in entries)
        if (entry.subjectKey.trim().isNotEmpty) entry.subjectKey.trim(),
    }.toList()
      ..sort();
    return keys;
  }

  /// 全部条目的标签路径并集（去重排序），供筛选下拉。
  List<String> get tagPaths {
    final paths = <String>{
      for (final entry in entries) ...entry.tagPaths,
    }.toList()
      ..sort();
    return paths;
  }
}

/// 读一次题库总览。
///
/// [limit] 默认 500（一个平板题库页一次最多画这么多行；`<=0` 表示不限）。
/// 排序固定为 **updatedAt 降序、id 升序**：最近收/改的题在最上面，同一毫秒内
/// 也稳定。
Future<QuestionLibrarySnapshot> readQuestionLibrary(
  AppDatabase db, {
  int limit = 500,
}) async {
  final capped = limit > 0 ? limit + 1 : 0;
  final query = db.select(db.questions)
    ..orderBy([
      (t) => OrderingTerm.desc(t.updatedAt),
      (t) => OrderingTerm.asc(t.id),
    ]);
  if (capped > 0) {
    query.limit(capped);
  }
  final questionRows = await query.get();
  final truncated = capped > 0 && questionRows.length > limit;
  final rows = truncated ? questionRows.sublist(0, limit) : questionRows;
  if (rows.isEmpty) {
    return const QuestionLibrarySnapshot(
      entries: <QuestionLibraryEntry>[],
      totalCount: 0,
    );
  }

  final ids = <String>[for (final row in rows) row.id];
  final attachmentRows = await (db.select(db.attachments)
        ..where((t) => t.ownerType.equals('question') & t.ownerId.isIn(ids)))
      .get();
  final linkRows = await (db.select(db.objectTags)
        ..where((t) => t.objectType.equals('question') & t.objectId.isIn(ids)))
      .get();
  final tagRows = await db.select(db.tags).get();

  final pathByTagId = <String, String>{
    for (final tag in tagRows)
      if ((tag.path ?? '').trim().isNotEmpty) tag.id: tag.path!.trim(),
  };
  final tagIdsByQuestion = <String, Set<String>>{};
  for (final link in linkRows) {
    (tagIdsByQuestion[link.objectId] ??= <String>{}).add(link.tagId);
  }
  final imagesByQuestion = <String, List<QuestionLibraryImage>>{};
  for (final row in attachmentRows) {
    // NULL 是 v27 之前写下的旧行：读成题干图，旧题库看起来不变。
    final rawRole = (row.role ?? '').trim();
    final role = rawRole.isEmpty ? kQuestionLibraryStemRole : rawRole;
    (imagesByQuestion[row.ownerId] ??= <QuestionLibraryImage>[]).add(
      QuestionLibraryImage(
        attachmentId: row.id,
        relPath: row.relPath,
        role: role,
        sortOrder: row.sortOrder,
        mime: row.mime,
      ),
    );
  }
  for (final images in imagesByQuestion.values) {
    images.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      return byOrder != 0 ? byOrder : a.attachmentId.compareTo(b.attachmentId);
    });
  }

  final entries = <QuestionLibraryEntry>[
    for (final row in rows)
      QuestionLibraryEntry(
        questionId: row.id,
        serialNo: row.serialNo,
        title: row.title,
        stem: row.stem,
        subjectKey: row.subjectKey,
        sourceLevel: row.sourceLevel,
        sourceLabel: row.sourceLabel,
        year: row.year,
        region: row.region,
        questionType: row.questionType,
        difficulty: row.difficulty,
        updatedAt: row.updatedAt,
        tagPaths: _sortedPaths(
          tagIdsByQuestion[row.id] ?? const <String>{},
          pathByTagId,
        ),
        stemImages:
            _imagesOf(imagesByQuestion[row.id], kQuestionLibraryStemRole),
        answerImages:
            _imagesOf(imagesByQuestion[row.id], kQuestionLibraryAnswerRole),
        solutionImages:
            _imagesOf(imagesByQuestion[row.id], kQuestionLibrarySolutionRole),
      ),
  ];

  return QuestionLibrarySnapshot(
    entries: List<QuestionLibraryEntry>.unmodifiable(entries),
    totalCount: entries.length,
    truncated: truncated,
  );
}

List<String> _sortedPaths(Set<String> tagIds, Map<String, String> pathByTagId) {
  final paths = <String>{
    for (final id in tagIds)
      if (pathByTagId[id] != null) pathByTagId[id]!,
  }.toList()
    ..sort();
  return List<String>.unmodifiable(paths);
}

List<QuestionLibraryImage> _imagesOf(
  List<QuestionLibraryImage>? images,
  String role,
) {
  final matching = <QuestionLibraryImage>[
    for (final image in images ?? const <QuestionLibraryImage>[])
      if (image.role == role) image,
  ];
  return List<QuestionLibraryImage>.unmodifiable(matching);
}

String _preview(String stem, {required int max}) {
  final collapsed = stem.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.length <= max) {
    return collapsed;
  }
  return '${collapsed.substring(0, max)}…';
}
