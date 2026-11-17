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
import '../../../domain/services/questions/question_group.dart';
import '../../../domain/services/questions/question_number.dart';
import '../../../domain/services/questions/question_readiness.dart';
import '../../../domain/services/questions/question_snapshot_summary.dart';
import '../../../domain/services/questions/question_stem_preview.dart';

/// 题干图/答案图的角色（与 `QuestionMediaStore` 的 [QuestionImageRole] 同一组值；
/// 这里不复用那个类型，是为了让读表层不 import `dart:io`）。
const String kQuestionLibraryStemRole = 'stem';
const String kQuestionLibraryAnswerRole = 'answer';
const String kQuestionLibrarySolutionRole = 'solution';

/// 材料块开头的 `【材料 S1-M1】` 标题行（摘要里剥掉，标题单独显示）。
final RegExp _materialMarkerLine = RegExp(r'^【材料[^】\n]*】[ \t]*\n?');

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
    this.isSnapshotStem = false,
    this.snapshotLabel,
    this.snapshotExcerpt,
    this.wrongAttemptCount = 0,
    this.readiness = QuestionReadiness.ready,
    this.groupKey,
    this.groupQuestionIds = const <String>[],
    this.groupSize = 1,
    this.groupLabel,
    this.groupMaterial,
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

  /// 题干图是「整题截图」（1 张大图 + 若干「［图N］」占位），正文只是碎片。
  ///
  /// 判定读表时用题干图数量 + 无尺寸兜底（B2）；界面要区分快照题时看这个字段。
  final bool isSnapshotStem;

  /// 快照题的中文标签（「整题截图 · 12 处公式/图」）；非快照题为 null。
  final String? snapshotLabel;

  /// 快照题从正文里剥掉占位后可读的摘录；没有可读正文时为 null。
  final String? snapshotExcerpt;

  /// 自测里答错过的次数（`question_attempts` 中 `is_correct = 0` 的行数）。
  ///
  /// 0 表示没答错过（没做过、只做对过、或只做过不可判分的题）。
  final int wrongAttemptCount;

  /// 完整性结论（缺答案/解析/配图）：主题库默认只列 [QuestionReadiness.isReady]
  /// 的题，「待处理题目」入口列待处理的题。默认 ready 是为了让历史构造点
  /// （测试/预览）不用全改。
  final QuestionReadiness readiness;

  /// 题组键（[QuestionGroupSignature.groupKey]）；null = 独立题。
  ///
  /// 同一篇文章的每个小问拿到的都是同一个键；读表时整组折成**一张卡**
  /// （见 [readQuestionLibrary]）。独立题永远是 null。
  final String? groupKey;

  /// 组内全部小问的题目 id（组键排序后的顺序；第一个是代表题，
  /// 也就是本 entry 的 [questionId]）。独立题为空表。
  final List<String> groupQuestionIds;

  /// 这道题代表几个小问（题组计数口径：一张卡 = 1 道题）。独立题为 1。
  final int groupSize;

  /// 题组的中文标签（`材料 S1-M1`）；独立题为 null。
  final String? groupLabel;

  /// 材料原文（含 `【材料 …】` 标题行，不含小问题干）；独立题或旧数据为 null。
  final String? groupMaterial;

  /// 是否是「一篇文章 + 多个小问」折成的题组卡。
  bool get isQuestionGroup => groupSize > 1 && groupQuestionIds.isNotEmpty;

  /// 材料摘要（列表卡上「材料 + N 小问」的那一行）；没有材料时为 null。
  String? get groupMaterialPreview {
    final material = (groupMaterial ?? '').trim();
    if (material.isEmpty) {
      return null;
    }
    // 材料块的第一行是 `【材料 S1-M1】` 标题：标题已经在 [groupLabel] 里，
    // 摘要从正文开始，不重复摆一遍标题。
    final body = material.replaceFirst(_materialMarkerLine, '').trim();
    final preview = questionStemPreview(body);
    return preview.isEmpty ? null : preview;
  }

  /// 是否待处理（不进主题库）。
  bool get isPending => readiness.isPending;

  /// 是否进错题本：至少答错过一次。
  bool get hasWrongAttempt => wrongAttemptCount > 0;

  /// `TR-00042`；还没编号时给「未编号」，与详情页/搜索口径一致。
  String get serialLabel =>
      serialNo == null ? '未编号' : formatQuestionSerial(serialNo!);

  /// 显示标题：题名 → 快照题可读摘录 → 快照标签 → 题干摘要。
  ///
  /// 整卡快照题的 [stemPreview] 是「…… ［图N］ ……」的碎片，直接上列表不好认；
  /// 先给从正文里剥出来的可读摘要，没有摘要就给「整题截图 · N 处公式/图」，
  /// 让用户知道这题的题面在图里。
  String get displayTitle {
    final named = (title ?? '').trim();
    if (named.isNotEmpty) {
      return named;
    }
    final excerpt = (snapshotExcerpt ?? '').trim();
    if (excerpt.isNotEmpty) {
      return excerpt;
    }
    final label = (snapshotLabel ?? '').trim();
    if (label.isNotEmpty) {
      return label;
    }
    final preview = stemPreview;
    return preview.isEmpty ? '（无题干）' : preview;
  }

  /// 题干摘要（单行、去 LaTeX 定界符与图片占位标记、折叠空白、截断到 60 字）。
  String get stemPreview => questionStemPreview(stem);

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

  /// 这次读到的**题组数**（受 `limit` 约束；不是库里题目总行数）。
  ///
  /// 判据生效时是「过滤后、截断前」的可见题组数（沿用主题库口径）；无判据时是
  /// 截断后实际返回的题组数。两者都按**题组**计数：一篇文章 + N 个小问算 1。
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
/// [limit] 默认 500（一个平板题库页一次最多画这么多**题组卡**；`<=0` 表示不限）。
/// 排序固定为 **updatedAt 降序、id 升序**：最近收/改的题在最上面，同一毫秒内
/// 也稳定。
///
/// **题组折叠**：整卷导入把材料内联进每个小问的 stem（`【材料 Sx-Mx】…`），同一篇
/// 文章的多行题在题库里应该是**一道题**（判据见
/// `domain/services/questions/question_group.dart`）。折叠必须在 `LIMIT` **之前**
/// 做：先读全表、按组键收拢、只给每组第一行建 [QuestionLibraryEntry]，再按
/// [limit] 截断——否则从第 500 行附近的一组会被截成半组。组卡保留组内全部小问
/// id（[QuestionLibraryEntry.groupQuestionIds]）；标签与答错次数按**全组**聚合
/// （筛「错题本」不会因为答错的是第 2 小问而漏掉）。
///
/// [policy] 是完整性判据：默认 [QuestionCompletenessPolicy.includeAll]（读表函数
/// 的历史行为，任何题都算完整）；主题库数据源传
/// [QuestionCompletenessPolicy.hidePending]，于是「没答案没解析」的题被滤掉。
/// [pendingOnly] 为 true 时反过来**只留待处理题**（「待处理题目」入口用）。
///
/// 有判据时更不能在 SQL 里先 `LIMIT`：那会把第 N 条之后的完整/待处理题判错，所以
/// 先读全表再折叠、再筛、再按 `limit` 截断（本地 SQLite、题量万级以内可接受）。
Future<QuestionLibrarySnapshot> readQuestionLibrary(
  AppDatabase db, {
  int limit = 500,
  QuestionCompletenessPolicy policy = QuestionCompletenessPolicy.includeAll,
  bool pendingOnly = false,
}) async {
  // 先读全表（不 SQL LIMIT）：题组折叠要知道每组的全部行。
  final questionRows = await (db.select(db.questions)
        ..orderBy([
          (t) => OrderingTerm.desc(t.updatedAt),
          (t) => OrderingTerm.asc(t.id),
        ]))
      .get();
  if (questionRows.isEmpty) {
    return const QuestionLibrarySnapshot(
      entries: <QuestionLibraryEntry>[],
      totalCount: 0,
    );
  }

  // 1) 每行的组签名；同组行按排序顺序收拢（第一行 = 代表行，组卡的入口）。
  final signatureByRowId = <String, QuestionGroupSignature>{};
  final rowIdsByGroupKey = <String, List<String>>{};
  for (final row in questionRows) {
    final signature = questionGroupSignatureOf(
      stem: row.stem,
      sourceLabel: row.sourceLabel,
    );
    if (signature == null) {
      continue;
    }
    signatureByRowId[row.id] = signature;
    (rowIdsByGroupKey[signature.groupKey] ??= <String>[]).add(row.id);
  }
  final groupIdsByRepresentative = <String, List<String>>{};
  final signatureByRepresentative = <String, QuestionGroupSignature>{};
  for (final entry in rowIdsByGroupKey.entries) {
    final ids = entry.value;
    if (ids.isEmpty) {
      continue;
    }
    groupIdsByRepresentative[ids.first] = List<String>.unmodifiable(ids);
    signatureByRepresentative[ids.first] = signatureByRowId[ids.first]!;
  }

  // 2) 代表行清单：独立题是自己；题组是排序后的第一行。
  final representativeIds = <String>[
    for (final row in questionRows)
      if (!signatureByRowId.containsKey(row.id) ||
          groupIdsByRepresentative[row.id]?.first == row.id)
        row.id,
  ];
  final allRowIds = <String>[for (final row in questionRows) row.id];
  // 附件只查代表行（组卡显示代表题的封面/答案图）；标签与错题记录按**全组**
  // 查询，折成一张卡后组内任一小问的标签/答错都不丢。
  final attachmentRows = await (db.select(db.attachments)
        ..where((t) =>
            t.ownerType.equals('question') & t.ownerId.isIn(representativeIds)))
      .get();
  final linkRows = await (db.select(db.objectTags)
        ..where((t) => t.objectType.equals('question') & t.objectId.isIn(allRowIds)))
      .get();
  // 错题本口径：只数答错的自测（`question_attempts.is_correct = 0`）；
  // 做对过的题不进错题本，没做过的题也不进。
  final wrongRows = await (db.select(db.questionAttempts)
        ..where((t) => t.questionId.isIn(allRowIds) & t.isCorrect.equals(false)))
      .get();
  final wrongCountByQuestion = <String, int>{};
  for (final row in wrongRows) {
    wrongCountByQuestion[row.questionId] =
        (wrongCountByQuestion[row.questionId] ?? 0) + 1;
  }
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

  final rowById = <String, Question>{
    for (final row in questionRows) row.id: row,
  };
  final entries = <QuestionLibraryEntry>[];
  for (final representativeId in representativeIds) {
    final row = rowById[representativeId];
    if (row == null) {
      continue;
    }
    final groupIds =
        groupIdsByRepresentative[representativeId] ?? const <String>[];
    final memberIds = groupIds.isEmpty ? <String>[representativeId] : groupIds;
    final signature = signatureByRepresentative[representativeId];
    final stemImages =
        _imagesOf(imagesByQuestion[representativeId], kQuestionLibraryStemRole);
    // 只拿到题干图数量、没有像素尺寸：走 B2 兜底（1 图 + >=2 处占位即快照）。
    final snapshot = summarizeQuestionStemSnapshot(
      stem: row.stem,
      stemImageCount: stemImages.length,
    );
    // 组内标签取并集、答错次数求和：折卡后「第 2 小问挂了标签/答错过」仍然可筛。
    final groupTagIds = <String>{
      for (final memberId in memberIds) ...?tagIdsByQuestion[memberId],
    };
    var groupWrongAttemptCount = 0;
    for (final memberId in memberIds) {
      groupWrongAttemptCount += wrongCountByQuestion[memberId] ?? 0;
    }
    entries.add(
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
        tagPaths: _sortedPaths(groupTagIds, pathByTagId),
        stemImages: stemImages,
        answerImages: _imagesOf(
          imagesByQuestion[representativeId],
          kQuestionLibraryAnswerRole,
        ),
        solutionImages: _imagesOf(
          imagesByQuestion[representativeId],
          kQuestionLibrarySolutionRole,
        ),
        isSnapshotStem: snapshot.isSnapshot,
        snapshotLabel: snapshot.labelZh.isEmpty ? null : snapshot.labelZh,
        snapshotExcerpt: snapshot.isSnapshot && snapshot.hasTextExcerpt
            ? snapshot.textExcerpt
            : null,
        wrongAttemptCount: groupWrongAttemptCount,
        readiness: evaluateQuestionReadiness(
          answer: row.answer,
          solution: row.solution,
          stem: row.stem,
          stemImageCount: stemImages.length,
          policy: policy,
        ),
        // 组卡只在真的多于一个小问时才摆「N 小问」；单行材料题仍按普通题显示。
        groupKey: signature?.groupKey,
        groupQuestionIds: groupIds.length > 1 ? groupIds : const <String>[],
        groupSize: groupIds.isEmpty ? 1 : groupIds.length,
        groupLabel: signature?.label,
        groupMaterial: signature?.material,
      ),
    );
  }

  final filtering = policy.filtersAnything || pendingOnly;
  if (!filtering) {
    final truncated = limit > 0 && entries.length > limit;
    final shown = truncated ? entries.sublist(0, limit) : entries;
    return QuestionLibrarySnapshot(
      entries: List<QuestionLibraryEntry>.unmodifiable(shown),
      totalCount: shown.length,
      truncated: truncated,
    );
  }

  // 判据生效：先按 entries 是否完整/待处理筛，再按 limit 截断。
  final visible = <QuestionLibraryEntry>[
    for (final entry in entries)
      if (pendingOnly ? entry.isPending : entry.readiness.isReady) entry,
  ];
  final totalCount = visible.length;
  final truncated = limit > 0 && totalCount > limit;
  final shown = truncated ? visible.sublist(0, limit) : visible;
  return QuestionLibrarySnapshot(
    entries: List<QuestionLibraryEntry>.unmodifiable(shown),
    totalCount: totalCount,
    truncated: truncated,
  );
}

/// 一道题所在的题组（详情页「本组共 N 小问」用）。
///
/// 独立题（没有材料前缀 / 来源标签为空）没有题组，读表函数返回 null；只有一个小问
/// 的材料题返回 size 为 1 的题组，页面据此不显示「本组共…」。
class QuestionGroupInfo {
  const QuestionGroupInfo({
    required this.groupKey,
    required this.label,
    required this.questionIds,
    this.material,
  });

  /// 组键（与读表折叠用的是同一个，见 `questionGroupSignatureOf`）。
  final String groupKey;

  /// 组的中文标签（`材料 S1-M1`）。
  final String label;

  /// 组内全部小问 id，按「updatedAt 降序、id 升序」排；第一个是代表题。
  final List<String> questionIds;

  /// 材料原文；旧数据无法切分时为 null。
  final String? material;

  int get size => questionIds.length;

  /// 是否真的多于一个小问。
  bool get isGroup => size > 1;

  /// 代表题（读表折叠后列表卡打开的那一道）。
  String get representativeId => questionIds.first;
}

/// 读这道题所在题组的成员与材料；独立题返回 null。
///
/// 只查同一 `source_label` 下的行（组键里带来源标签，跨来源不可能同组），再按组键
/// 过滤——不会把别的卷子的 `S1-M1` 算进来。
Future<QuestionGroupInfo?> readQuestionGroupInfo(
  AppDatabase db,
  String questionId,
) async {
  final row = await (db.select(db.questions)
        ..where((t) => t.id.equals(questionId)))
      .getSingleOrNull();
  if (row == null) {
    return null;
  }
  final signature = questionGroupSignatureOf(
    stem: row.stem,
    sourceLabel: row.sourceLabel,
  );
  if (signature == null) {
    return null;
  }
  final candidates = await (db.select(db.questions)
        ..where((t) => t.sourceLabel.equals(row.sourceLabel))
        ..orderBy([
          (t) => OrderingTerm.desc(t.updatedAt),
          (t) => OrderingTerm.asc(t.id),
        ]))
      .get();
  final questionIds = <String>[
    for (final candidate in candidates)
      if (questionGroupSignatureOf(
            stem: candidate.stem,
            sourceLabel: candidate.sourceLabel,
          )?.groupKey ==
          signature.groupKey)
        candidate.id,
  ];
  if (questionIds.isEmpty) {
    // 理论上不会发生（这道题自己就满足组键）；保守回落到单题，不抛错。
    questionIds.add(questionId);
  }
  return QuestionGroupInfo(
    groupKey: signature.groupKey,
    label: signature.label,
    questionIds: List<String>.unmodifiable(questionIds),
    material: signature.material,
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
