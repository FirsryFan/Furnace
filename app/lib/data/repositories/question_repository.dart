import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/services/questions/question_serial_allocator.dart';
import '../../domain/services/srs/dsr_memory.dart';
import '../database/database.dart';
import '../ids.dart';

/// 来源分级的排序权重（`docs/QUESTION_BANK_DESIGN.md` §1）。
///
/// 只影响"先给谁"，不影响"要不要"：低价值题不删，只压后。高考真题最高，
/// 强省强市诊断次之，未标注最低——这个次序来自用户口径（价值在选择与加工，
/// 高价值来源是高考真题、部分名校测试、部分强省强市诊断的高质量模拟）。
const Map<String, int> kSourceLevelWeight = {
  'gaokao': 5,
  'provincial_diagnostic': 4,
  'elite_school': 3,
  'school': 2,
  'personal': 1,
  'unknown': 0,
};

/// 题干指纹：去空白 + 标点归一 + 小写之后的 FNV-1a 64 位十六进制。
///
/// 纯 Dart（BigInt），不引依赖。它只挡**完全同一道题**的重复入库；
/// 近似重复（同题不同排版）留给后续"按考点链找相似题"。
String stemFingerprint(String stem) {
  final normalized = normalizeStem(stem);
  final mask = (BigInt.one << 64) - BigInt.one;
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  for (final code in normalized.codeUnits) {
    hash = ((hash ^ BigInt.from(code)) & mask);
    hash = ((hash * prime) & mask);
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// 题干归一：去掉所有空白与常见中英文标点，并统一小写。
String normalizeStem(String stem) => stem
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll(
      RegExp(r'''[，。！？；：、“”‘’（）《》【】〈〉·,.!?;:"'()\[\]{}<>]'''),
      '',
    )
    .toLowerCase();

/// 空串 / 全空白归一成 null（题源链接「清空这一列」的约定）。
String? _blankToNull(String raw) {
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// 一条待入库的选项。
class QuestionOptionDraft {
  const QuestionOptionDraft({
    required this.label,
    required this.content,
    this.isCorrect = false,
    this.sortOrder = 0,
  });

  final String label;
  final String content;
  final bool isCorrect;
  final int sortOrder;
}

/// 一条待入库的题目。字段与 `questions` 表一一对应（少了 id/指纹/状态，
/// 那三样由仓储按规则产生）。
class QuestionDraft {
  const QuestionDraft({
    required this.stem,
    this.answer,
    this.solution,
    this.subjectKey = '',
    this.questionType = 'solution',
    this.sourceLevel = 'unknown',
    this.sourceLabel = '',
    this.year,
    this.region,
    this.sourceUrl,
    this.zujuanQuestionId,
    this.zujuanBankId,
    this.difficulty,
    this.difficultySource,
    this.trapNote,
    this.aiQuality,
    this.aiQualityNote,
    this.origin = 'manual',
    this.state = 'structured',
    this.options = const [],
    this.tagIds = const {},
  });

  final String stem;
  final String? answer;
  final String? solution;
  final String subjectKey;
  final String questionType;
  final String sourceLevel;
  final String sourceLabel;
  final int? year;
  final String? region;

  /// 外部来源页链接（现在只有组卷网）；手写/拍照/自建题为 null。
  final String? sourceUrl;

  /// 组卷网 questionid / bankid：留着能重建链接、能按 qid 认题。
  final String? zujuanQuestionId;
  final String? zujuanBankId;

  final double? difficulty;
  final String? difficultySource;
  final String? trapNote;
  final double? aiQuality;
  final String? aiQualityNote;
  final String origin;

  /// 入库时的加工状态：收题页确认后给 `structured`，批量导入给 `raw`。
  final String state;
  final List<QuestionOptionDraft> options;
  final Set<String> tagIds;
}

/// 一条待入库的推理步骤。
class ReasoningStepDraft {
  const ReasoningStepDraft({
    required this.goal,
    this.actionType = 'unknown',
    this.justification = '',
    this.checkMethod = '',
    this.stuckRisk,
    this.knowledgeHints = const [],
    this.note,
  });

  final String goal;
  final String actionType;
  final String justification;
  final String checkMethod;
  final double? stuckRisk;
  final List<String> knowledgeHints;
  final String? note;
}

/// 一条待入库的推理链（一次 AI 亲自解题的产物）。
class ReasoningChainDraft {
  const ReasoningChainDraft({
    this.source = 'ai',
    this.model,
    this.summary = '',
    this.steps = const [],
  });

  final String source;
  final String? model;
  final String summary;
  final List<ReasoningStepDraft> steps;
}

/// 一道邻居题：详情页翻页只需要 id 与题号。
class QuestionSerialNeighbor {
  const QuestionSerialNeighbor({
    required this.questionId,
    required this.serialNo,
  });

  final String questionId;
  final int serialNo;
}

/// 详情页「上一题 / 下一题」的邻居：按题号前后各一道（都不含本题）。
class QuestionSerialNeighbors {
  const QuestionSerialNeighbors({this.previous, this.next});

  const QuestionSerialNeighbors.empty()
      : previous = null,
        next = null;

  final QuestionSerialNeighbor? previous;
  final QuestionSerialNeighbor? next;

  bool get isEmpty => previous == null && next == null;
  bool get isNotEmpty => !isEmpty;
}

/// 一道题在「按题号排好序的题库」里的位置：详情页「第 N / 共 M 题」。
///
/// [index] 从 1 起，口径是**题号 <= 本题号的题数**（同号多题时它们拿到同一个
/// index：题号不是主键，跨库合并允许同号，见 §11.1）；[total] 是题库里带题号
/// 的题数（未编号的题不参与，与 [QuestionRepository.serialNeighbors] 同口径）。
class QuestionSerialPosition {
  const QuestionSerialPosition({required this.index, required this.total});

  final int index;
  final int total;
}

/// 题库仓储（`docs/QUESTION_BANK_DESIGN.md`）。
///
/// 不变量：
///  - **只追加**：题干/选项一旦入库不再原地改写；加工只写 `state`/`trapNote`/
///    `difficulty`/`aiQuality` 这几个加工列（[updateProcessing]）。
///  - **入库前算指纹**：同指纹不重复插入，返回既有题目（[ingest]）。
///  - 生成的 schema 没有外键（本项目实测如此），所以删除时的级联只能显式做
///    （[deleteQuestion]）。
class QuestionRepository {
  QuestionRepository(this._db);

  final AppDatabase _db;

  /// 按指纹去重入库；同指纹已存在时返回既有题目且 `created == false`。
  Future<({Question question, bool created})> ingest(
    QuestionDraft draft, {
    DateTime? now,
  }) async {
    final stem = draft.stem.trim();
    if (stem.isEmpty) {
      throw ArgumentError('题干不能为空');
    }
    final fingerprint = stemFingerprint(stem);
    final existing = await findByFingerprint(fingerprint);
    if (existing != null) {
      return (question: existing, created: false);
    }

    final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final id = Ids.next('q');
    await _db.transaction(() async {
      // v24（轮次一百二十一）：题目编号在这个事务里分配，"读 MAX + 插入"是一次
      // 原子操作——放在事务外就可能两个 ingest 拿到同一个号。删题不回收号，所以
      // 号只增不减；导入的包可能把号带成重复的（append 模式不重编号）。
      //
      // v33（轮次一百六十三）：只读 MAX 是不够的——删掉最大号那道题以后，号会
      // 被下一道题接手（§11 的「发出即永久保留」没做到）。高水位表
      // `question_serial_counters` 记着这个库发出去过的最大号，分配规则取
      // `max(现存最大号, 高水位) + 1` 并回写高水位，同样在这个事务里，原子。
      final maxSerial = _db.questions.serialNo.max();
      final maxRow = await (_db.selectOnly(_db.questions)
            ..addColumns([maxSerial]))
          .getSingle();
      final counterRow = await (_db.select(_db.questionSerialCounters)
            ..where((t) => t.id.equals(1)))
          .getSingleOrNull();
      final serialNo = allocateQuestionSerial(
        highestExisting: maxRow.read(maxSerial),
        lastIssued: counterRow?.lastIssued,
      );
      await _db.into(_db.questionSerialCounters).insertOnConflictUpdate(
            QuestionSerialCountersCompanion.insert(
              id: const Value(1),
              lastIssued: serialNo,
            ),
          );
      await _db.into(_db.questions).insert(
            QuestionsCompanion.insert(
              id: id,
              serialNo: Value(serialNo),
              stem: stem,
              answer: Value(draft.answer),
              solution: Value(draft.solution),
              subjectKey: Value(draft.subjectKey),
              questionType: Value(draft.questionType),
              sourceLevel: Value(draft.sourceLevel),
              sourceLabel: Value(draft.sourceLabel),
              year: Value(draft.year),
              region: Value(draft.region),
              sourceUrl: Value(draft.sourceUrl),
              zujuanQuestionId: Value(draft.zujuanQuestionId),
              zujuanBankId: Value(draft.zujuanBankId),
              difficulty: Value(draft.difficulty),
              difficultySource: Value(draft.difficultySource),
              stemFingerprint: Value(fingerprint),
              trapNote: Value(draft.trapNote),
              state: Value(draft.state),
              aiQuality: Value(draft.aiQuality),
              aiQualityNote: Value(draft.aiQualityNote),
              origin: Value(draft.origin),
              createdAt: ms,
              updatedAt: ms,
            ),
          );
      await _insertOptions(id, draft.options, ms);
      await _linkTags(id, draft.tagIds, ms);
    });
    final question = await byId(id);
    return (question: question!, created: true);
  }

  Future<void> _insertOptions(
    String questionId,
    List<QuestionOptionDraft> options,
    int ms,
  ) async {
    for (var i = 0; i < options.length; i++) {
      final option = options[i];
      await _db.into(_db.questionOptions).insert(
            QuestionOptionsCompanion.insert(
              id: Ids.next('qo'),
              questionId: questionId,
              label: option.label,
              content: option.content,
              isCorrect: Value(option.isCorrect),
              sortOrder: Value(option.sortOrder),
              createdAt: ms,
            ),
          );
    }
  }

  Future<void> _linkTags(String questionId, Set<String> tagIds, int ms) async {
    for (final tagId in tagIds) {
      await _db.into(_db.objectTags).insert(
            ObjectTagsCompanion.insert(
              id: Ids.next('ot'),
              tagId: tagId,
              objectType: 'question',
              objectId: questionId,
              createdAt: ms,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  Future<Question?> byId(String id) =>
      (_db.select(_db.questions)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<Question?> findByFingerprint(String fingerprint) =>
      (_db.select(_db.questions)
            ..where((t) => t.stemFingerprint.equals(fingerprint))
            ..limit(1))
          .getSingleOrNull();

  /// 按人读题号精确查题（schema v24 的 `serial_no`，v25 起支持按号检索）。
  ///
  /// 题号是跨学科一个序列（`docs/QUESTION_BANK_DESIGN.md` §11.1），不是主键：
  /// 跨设备 append 导入可能撞号，所以这里 `limit(1)` 取任意一条而不是报"多条"
  /// —— 按号搜是给人找题用的，撞号这个代价是编号方案刻意接受的。传 0 / 负数
  /// 直接返回 null（号从 1 开始），不做一次注定查不到的查询。
  Future<Question?> findBySerialNo(int serialNo) async {
    if (serialNo < 1) {
      return null;
    }
    return (_db.select(_db.questions)
          ..where((t) => t.serialNo.equals(serialNo))
          ..limit(1))
        .getSingleOrNull();
  }

  /// 详情页「上一题 / 下一题」：按题号找前后最近的一道（都不含本题）。
  ///
  /// 题号是跨学科一条序列、且**不加 UNIQUE**（§11.1：跨库合并允许同号），所以：
  /// - 没有题号的题不参与翻页（NULL 比较天然不命中）；
  /// - 同号多题时按 `created_at` 升序、再按 `id` 升序取第一道，同一份库每次读到
  ///   的邻居是同一道，翻页不会抖；
  /// - 传 0 / 负数直接返回空邻居（号从 1 开始，不做注定查不到的查询）。
  Future<QuestionSerialNeighbors> serialNeighbors(int serialNo) async {
    if (serialNo < 1) {
      return const QuestionSerialNeighbors.empty();
    }
    final previous = await (_db.select(_db.questions)
          ..where((t) => t.serialNo.isSmallerThanValue(serialNo))
          ..orderBy([
            (t) => OrderingTerm.desc(t.serialNo),
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ])
          ..limit(1))
        .getSingleOrNull();
    final next = await (_db.select(_db.questions)
          ..where((t) => t.serialNo.isBiggerThanValue(serialNo))
          ..orderBy([
            (t) => OrderingTerm.asc(t.serialNo),
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ])
          ..limit(1))
        .getSingleOrNull();
    return QuestionSerialNeighbors(
      previous: previous == null
          ? null
          : QuestionSerialNeighbor(
              questionId: previous.id,
              serialNo: previous.serialNo!,
            ),
      next: next == null
          ? null
          : QuestionSerialNeighbor(
              questionId: next.id,
              serialNo: next.serialNo!,
            ),
    );
  }

  /// 一道题在按题号排好的题库里排第几、题库一共几道带题号的题。
  ///
  /// 详情页「第 N / 共 M 题」用它。两种口径与 [serialNeighbors] 保持一致：
  /// - 只数**带题号**的题（未编号的题不参与，NULL 比较天然不命中）；
  /// - 同号多题共享同一个 index（题号不是主键，§11.1）。
  ///
  /// 传 0 / 负数、或题库里一道带题号的题都没有时返回 `null`：那两种情况下
  /// 「第几题」没有意义，页面直接不显示这一行。
  Future<QuestionSerialPosition?> serialPosition(int serialNo) async {
    if (serialNo < 1) {
      return null;
    }
    final totalQuery = _db.selectOnly(_db.questions)
      ..addColumns([_db.questions.id.count()])
      ..where(_db.questions.serialNo.isNotNull());
    final total =
        (await totalQuery.getSingle()).read(_db.questions.id.count()) ?? 0;
    if (total == 0) {
      return null;
    }
    final indexQuery = _db.selectOnly(_db.questions)
      ..addColumns([_db.questions.id.count()])
      ..where(_db.questions.serialNo.isNotNull() &
          _db.questions.serialNo.isSmallerOrEqualValue(serialNo));
    final index =
        (await indexQuery.getSingle()).read(_db.questions.id.count()) ?? 0;
    return QuestionSerialPosition(index: index, total: total);
  }

  Future<List<Question>> all({int limit = 200}) => (_db.select(_db.questions)
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
        ..limit(limit))
      .get();

  Future<List<QuestionOption>> optionsOf(String questionId) =>
      (_db.select(_db.questionOptions)
            ..where((t) => t.questionId.equals(questionId))
            ..orderBy([
              (t) => OrderingTerm.asc(t.sortOrder),
              (t) => OrderingTerm.asc(t.label),
            ]))
          .get();

  Future<List<String>> tagIdsOf(String questionId) async {
    final rows = await (_db.select(_db.objectTags)
          ..where((t) =>
              t.objectType.equals('question') & t.objectId.equals(questionId)))
        .get();
    return [for (final row in rows) row.tagId];
  }

  /// 组卷/检索用：按来源分级与 AI 质量排序（不是按时间）。
  ///
  /// [tagIds] 给的是想要的标签 id 集合（一棵子树的展开交给调用方，仓储不懂标签树）；
  /// 只要题目挂着其中**任意一个**标签就算命中。
  /// [serialNos] 是题号过滤（schema v25 的按号搜题）：给空集与 [tagIds] 给空集
  /// 同一语义——用户明确要一组号，而这组号是空的，就没有任何题该命中；给
  /// `null` 表示不按号过滤。
  /// 排序：来源权重降序 → `aiQuality` 降序（NULL 最后）→ 创建时间降序 → id 升序。
  Future<List<Question>> search({
    String? subjectKey,
    Set<String>? tagIds,
    Set<String>? sourceLevels,
    Set<String>? states,
    Set<int>? serialNos,
    double? minQuality,
    String? stemContains,
    int limit = 50,
    int offset = 0,
  }) async {
    final query = _db.select(_db.questions);
    if (subjectKey != null && subjectKey.isNotEmpty) {
      query.where((t) => t.subjectKey.equals(subjectKey));
    }
    if (sourceLevels != null && sourceLevels.isNotEmpty) {
      query.where((t) => t.sourceLevel.isIn(sourceLevels));
    }
    if (states != null && states.isNotEmpty) {
      query.where((t) => t.state.isIn(states));
    }
    if (minQuality != null) {
      query.where((t) => t.aiQuality.isBiggerOrEqualValue(minQuality));
    }
    if (serialNos != null) {
      if (serialNos.isEmpty) {
        return const [];
      }
      query.where((t) => t.serialNo.isIn(serialNos));
    }
    if (stemContains != null && stemContains.isNotEmpty) {
      final escaped = stemContains
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      query.where((t) => t.stem.like('%$escaped%'));
    }
    final rows = await query.get();

    var candidates = rows;
    if (tagIds != null) {
      if (tagIds.isEmpty) {
        return const [];
      }
      final links = await (_db.select(_db.objectTags)
            ..where(
                (t) => t.objectType.equals('question') & t.tagId.isIn(tagIds)))
          .get();
      final allowed = {for (final link in links) link.objectId};
      candidates = [
        for (final row in rows)
          if (allowed.contains(row.id)) row,
      ];
    }

    candidates.sort(_byValue);
    if (offset >= candidates.length) {
      return const [];
    }
    final end = (offset + limit).clamp(0, candidates.length);
    return candidates.sublist(offset, end);
  }

  int _byValue(Question a, Question b) {
    final bySource = _weight(b.sourceLevel).compareTo(_weight(a.sourceLevel));
    if (bySource != 0) {
      return bySource;
    }
    final qualityA = a.aiQuality;
    final qualityB = b.aiQuality;
    if (qualityA != qualityB) {
      if (qualityA == null) {
        return 1;
      }
      if (qualityB == null) {
        return -1;
      }
      return qualityB.compareTo(qualityA);
    }
    final byTime = b.createdAt.compareTo(a.createdAt);
    if (byTime != 0) {
      return byTime;
    }
    return a.id.compareTo(b.id);
  }

  static int _weight(String level) => kSourceLevelWeight[level] ?? 0;

  /// 只改加工列：题干/选项是只追加的，加工产物可以重写。
  Future<void> updateProcessing(
    String id, {
    String? state,
    String? trapNote,
    double? difficulty,
    String? difficultySource,
    double? aiQuality,
    String? aiQualityNote,
    DateTime? now,
  }) async {
    final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;
    await (_db.update(_db.questions)..where((t) => t.id.equals(id))).write(
      QuestionsCompanion(
        state: state == null ? const Value.absent() : Value(state),
        trapNote: trapNote == null ? const Value.absent() : Value(trapNote),
        difficulty:
            difficulty == null ? const Value.absent() : Value(difficulty),
        difficultySource: difficultySource == null
            ? const Value.absent()
            : Value(difficultySource),
        aiQuality: aiQuality == null ? const Value.absent() : Value(aiQuality),
        aiQualityNote:
            aiQualityNote == null ? const Value.absent() : Value(aiQualityNote),
        updatedAt: Value(ms),
      ),
    );
  }

  /// 改**来源元信息**（来源分级 / 来源说明 / 年份 / 地区）。
  ///
  /// 为什么不并进 [updateProcessing]：来源分级有固定词表（[kSourceLevelWeight]），
  /// 传错值会悄悄变成权重 0、把排序弄歪；所以这里对 [sourceLevel] 做一次白名单校验。
  /// 题干 / 答案 / 选项仍然只追加 —— 这个口子只写四列来源信息。
  Future<void> updateSource(
    String id, {
    String? sourceLevel,
    String? sourceLabel,
    int? year,
    String? region,
    DateTime? now,
  }) async {
    if (sourceLevel != null && !kSourceLevelWeight.containsKey(sourceLevel)) {
      throw ArgumentError(
        '未知的来源分级 `$sourceLevel`（可用：${kSourceLevelWeight.keys.join(' / ')}）',
      );
    }
    final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;
    await (_db.update(_db.questions)..where((t) => t.id.equals(id))).write(
      QuestionsCompanion(
        sourceLevel:
            sourceLevel == null ? const Value.absent() : Value(sourceLevel),
        sourceLabel:
            sourceLabel == null ? const Value.absent() : Value(sourceLabel),
        year: year == null ? const Value.absent() : Value(year),
        region: region == null ? const Value.absent() : Value(region),
        updatedAt: Value(ms),
      ),
    );
  }

  /// 改**题名**（v30，轮次一百三十九）。
  ///
  /// 与 [updateProcessing] 分开的理由：题名是给人扫读/检索的标签，不是 AI 的
  /// 加工产物；长度、空值、去重后缀这些口径留给域层纯逻辑
  /// `question_title_suggestion.dart`，仓库只做存储归一（trim、空串 → NULL）。
  /// 返回是否真的改到了行（不存在的 id 返回 false，不抛）。
  Future<bool> setQuestionTitle(
    String id,
    String? title, {
    DateTime? now,
  }) async {
    final changed = await setQuestionTitles({id: title}, now: now);
    return changed > 0;
  }

  /// 批量改题名：一次事务。
  ///
  /// `titles` 的 key 是不存在/空白的 id 时静默跳过；`null`、空串、全空白都
  /// 写成 NULL（「还没有名字」）——不存在“第三种空值”。没有任何有效条目时
  /// 不写库、返回 0；返回真正被 UPDATE 命中的行数。
  Future<int> setQuestionTitles(
    Map<String, String?> titles, {
    DateTime? now,
  }) async {
    final normalized = <String, String?>{};
    titles.forEach((id, title) {
      final key = id.trim();
      if (key.isEmpty) {
        return;
      }
      normalized[key] = title == null ? null : _blankToNull(title);
    });
    if (normalized.isEmpty) {
      return 0;
    }
    final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;
    var changed = 0;
    await _db.transaction(() async {
      for (final entry in normalized.entries) {
        changed += await (_db.update(_db.questions)
              ..where((t) => t.id.equals(entry.key)))
            .write(QuestionsCompanion(
          title: Value(entry.value),
          updatedAt: Value(ms),
        ));
      }
    });
    return changed;
  }

  /// 改**题源链接**（原题 URL / 组卷网题目 id / 组卷网试卷 id）。
  ///
  /// 与 [updateSource] 分开的理由：来源分级是封闭词表、写错会弄歪排序；链接是
  /// 用户粘贴或入库带来的外部字符串，只需要归一空白、不参与排序。
  ///
  /// 约定：`null` = 这一列不动；空串或全空白 = 把这一列清空（写回 null）。
  /// 返回是否真的改到了行（不存在的 id 返回 false，不抛）。
  Future<bool> updateSourceLinks(
    String id, {
    String? sourceUrl,
    String? zujuanQuestionId,
    String? zujuanBankId,
    DateTime? now,
  }) async {
    final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;
    Value<String?> linkValue(String? raw) =>
        raw == null ? const Value.absent() : Value(_blankToNull(raw));
    final updated =
        await (_db.update(_db.questions)..where((t) => t.id.equals(id))).write(
      QuestionsCompanion(
        sourceUrl: linkValue(sourceUrl),
        zujuanQuestionId: linkValue(zujuanQuestionId),
        zujuanBankId: linkValue(zujuanBankId),
        updatedAt: Value(ms),
      ),
    );
    return updated > 0;
  }

  /// 按「题库包记录」更新一道**已经存在**的题（轮次一百四十五，包再导入用）。
  ///
  /// 与 [updateSource] / [updateSourceLinks] 的区别：那些是界面上的定点修改，
  /// 这里是**整条记录的补丁**——包里写了什么就补什么，没写的不动。补丁语义：
  ///
  ///  - [stem] 必填；trim 空 → [ArgumentError]（与 [ingest] 同口径）。题干总会
  ///    覆盖，并按新题干重算 `questions.stem_fingerprint`。
  ///  - 可空字符串字段（[answer] / [solution] / [subjectKey] / [questionType] /
  ///    [sourceLevel] / [sourceLabel] / [region] / [sourceUrl] /
  ///    [zujuanQuestionId] / [zujuanBankId] / [difficultySource] / [trapNote] /
  ///    [origin] / [state]）：`null` 或 trim 后空白 = 这一列不动；非空 = 覆盖
  ///    （写 trim 后的值）。答案/解析也走这条规则：包里没写答案时传 null/空串，
  ///    旧答案保留——这样「先收题干、后补答案」不会被空值冲掉。
  ///  - [year] / [difficulty]：`null` = 不动；非 `null` = 覆盖。
  ///  - [options] 非空 → 事务内先删这道题的全部 `question_options` 再按
  ///    [QuestionOptionDraft.sortOrder] 插入；空列表 = 保留旧选项（表示包里没
  ///    带选项，而不是「把选项清空」）。
  ///  - [additionalTagIds] → 只补挂缺失的 `object_tags`（insertOrIgnore），
  ///    不删除已有标签；空白 id 忽略。
  ///  - 题名 / 题号 / `createdAt` 绝不覆盖；`updatedAt` 写成 [now]。整个更新在
  ///    一个事务里（题目行 + 选项 + 标签边）。
  ///
  /// 返回 UPDATE 命中的行数：题目不存在时返回 0，不抛；[questionId] trim 后
  /// 为空也返回 0。
  Future<int> updateFromPack({
    required String questionId,
    required String stem,
    String? answer,
    String? solution,
    String? subjectKey,
    String? questionType,
    String? sourceLevel,
    String? sourceLabel,
    int? year,
    String? region,
    String? sourceUrl,
    String? zujuanQuestionId,
    String? zujuanBankId,
    double? difficulty,
    String? difficultySource,
    String? trapNote,
    String? origin,
    String? state,
    List<QuestionOptionDraft> options = const <QuestionOptionDraft>[],
    Set<String> additionalTagIds = const <String>{},
    DateTime? now,
  }) async {
    final id = questionId.trim();
    final cleanStem = stem.trim();
    if (cleanStem.isEmpty) {
      throw ArgumentError('题干不能为空');
    }
    if (id.isEmpty) {
      return 0;
    }
    final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;
    // 空值 = 不动（Value.absent），不是「写成 NULL」：包记录只补不带删。
    Value<String> requiredTextPatch(String? raw) {
      final cleaned = raw?.trim() ?? '';
      return cleaned.isEmpty ? const Value.absent() : Value(cleaned);
    }

    Value<String?> nullableTextPatch(String? raw) {
      final cleaned = raw?.trim() ?? '';
      return cleaned.isEmpty ? const Value.absent() : Value(cleaned);
    }

    var updated = 0;
    await _db.transaction(() async {
      updated = await (_db.update(_db.questions)..where((t) => t.id.equals(id)))
          .write(QuestionsCompanion(
        stem: Value(cleanStem),
        stemFingerprint: Value(stemFingerprint(cleanStem)),
        answer: nullableTextPatch(answer),
        solution: nullableTextPatch(solution),
        subjectKey: requiredTextPatch(subjectKey),
        questionType: requiredTextPatch(questionType),
        sourceLevel: requiredTextPatch(sourceLevel),
        sourceLabel: requiredTextPatch(sourceLabel),
        year: year == null ? const Value.absent() : Value(year),
        region: nullableTextPatch(region),
        sourceUrl: nullableTextPatch(sourceUrl),
        zujuanQuestionId: nullableTextPatch(zujuanQuestionId),
        zujuanBankId: nullableTextPatch(zujuanBankId),
        difficulty:
            difficulty == null ? const Value.absent() : Value(difficulty),
        difficultySource: nullableTextPatch(difficultySource),
        trapNote: nullableTextPatch(trapNote),
        origin: requiredTextPatch(origin),
        state: requiredTextPatch(state),
        updatedAt: Value(ms),
      ));
      if (updated == 0) {
        return;
      }
      if (options.isNotEmpty) {
        await (_db.delete(_db.questionOptions)
              ..where((t) => t.questionId.equals(id)))
            .go();
        await _insertOptions(id, options, ms);
      }
      final tagIds = <String>{};
      for (final raw in additionalTagIds) {
        final tagId = raw.trim();
        if (tagId.isNotEmpty) {
          tagIds.add(tagId);
        }
      }
      if (tagIds.isNotEmpty) {
        await _linkTags(id, tagIds, ms);
      }
    });
    return updated;
  }

  /// 按组卷网题目 id（`questions.zujuan_question_id`）批量查题——整卷页对照用。
  ///
  /// 返回 `zujuanQuestionId → 该 id 下的题目行`。同一组卷网 id 可能有多行
  /// （历史重复入库，库上没有唯一约束），顺序固定为 **updatedAt 降序、id 升序**，
  /// 调用方取第一行当"最新的一行"；本方法不替调用方挑行，也不合并。
  ///
  /// 空集合、或全部 trim 后为空 → 空 map，不查库。匹配口径是 trim 后精确相等
  /// （组卷网 id 是外部字符串，不做大小写/前导零归一——那是解析层的活）。
  Future<Map<String, List<Question>>> byZujuanQuestionIds(
    Set<String> zujuanQuestionIds,
  ) async {
    final ids = <String>{};
    for (final raw in zujuanQuestionIds) {
      final trimmed = raw.trim();
      if (trimmed.isNotEmpty) {
        ids.add(trimmed);
      }
    }
    if (ids.isEmpty) {
      return const {};
    }
    final rows = await (_db.select(_db.questions)
          ..where((t) =>
              t.zujuanQuestionId.isIn(ids) & t.zujuanQuestionId.isNotNull())
          ..orderBy([
            (t) => OrderingTerm.desc(t.updatedAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
    final grouped = <String, List<Question>>{};
    for (final row in rows) {
      final key = row.zujuanQuestionId;
      if (key == null || !ids.contains(key)) {
        continue;
      }
      (grouped[key] ??= <Question>[]).add(row);
    }
    return grouped;
  }

  /// 组卷网题目 id → 本地题目 id 的索引（轮次一百四十五，包再导入用）。
  ///
  /// 只读 `zujuan_question_id` 非空的行；key 是 **trim 后**的题号，trim 后为空
  /// 的 qid 跳过（不建索引）。同一个组卷网 id 可能有多行（库里没有唯一约束，
  /// 历史重复入库），取 **updatedAt 降序、id 升序**的第一行——与
  /// [byZujuanQuestionIds] 的行序一致，也就是「最新改过的那一行」；本方法不报
  /// 冲突、不合并。没有可用行时返回空 map。
  Future<Map<String, String>> questionIdsByZujuanQuestionId() async {
    final rows = await (_db.select(_db.questions)
          ..where((t) => t.zujuanQuestionId.isNotNull())
          ..orderBy([
            (t) => OrderingTerm.desc(t.updatedAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
    final index = <String, String>{};
    for (final row in rows) {
      final key = row.zujuanQuestionId?.trim() ?? '';
      if (key.isEmpty) {
        continue;
      }
      index.putIfAbsent(key, () => row.id);
    }
    return index;
  }

  /// 删除题目并显式清理它的一切（本项目没有外键，级联不会自己发生）。
  Future<void> deleteQuestion(String id) async {
    await _db.transaction(() async {
      final chains = await (_db.select(_db.reasoningChains)
            ..where((t) => t.questionId.equals(id)))
          .get();
      final chainIds = [for (final chain in chains) chain.id];
      if (chainIds.isNotEmpty) {
        await (_db.delete(_db.reasoningSteps)
              ..where((t) => t.chainId.isIn(chainIds)))
            .go();
      }
      await (_db.delete(_db.reasoningChains)
            ..where((t) => t.questionId.equals(id)))
          .go();
      await (_db.delete(_db.questionOptions)
            ..where((t) => t.questionId.equals(id)))
          .go();
      await (_db.delete(_db.objectTags)
            ..where(
                (t) => t.objectType.equals('question') & t.objectId.equals(id)))
          .go();
      // v32（轮次一百五十五）：自测作答记录跟着题一起走。不删的话，删完再导入
      // 同一道题（同题号更新会复用 id 的情况除外）会留下"孤儿作答"，历史页
      // 还能凭空读出几次自测。本项目没有外键级联，必须显式清。
      await (_db.delete(_db.questionAttempts)
            ..where((t) => t.questionId.equals(id)))
          .go();
      await (_db.delete(_db.questions)..where((t) => t.id.equals(id))).go();
    });
  }

  /// 存一条思维链（含步骤），并把题目标成已加工。
  ///
  /// 同题可以有多条链，互不覆盖。`idx` 按传入顺序从 0 起，`stuckRisk` 钳到
  /// [0,1]；步骤为空也允许（链可以先建、步骤后补）。
  Future<String> saveChain(
    String questionId,
    ReasoningChainDraft draft, {
    DateTime? now,
  }) async {
    final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final chainId = Ids.next('rc');
    await _db.transaction(() async {
      await _db.into(_db.reasoningChains).insert(
            ReasoningChainsCompanion.insert(
              id: chainId,
              questionId: questionId,
              source: Value(draft.source),
              model: Value(draft.model),
              summary: Value(draft.summary),
              stepCount: Value(draft.steps.length),
              createdAt: ms,
            ),
          );
      for (var i = 0; i < draft.steps.length; i++) {
        final step = draft.steps[i];
        final risk = step.stuckRisk;
        await _db.into(_db.reasoningSteps).insert(
              ReasoningStepsCompanion.insert(
                id: Ids.next('rs'),
                chainId: chainId,
                idx: i,
                goal: step.goal,
                actionType: Value(step.actionType),
                justification: Value(step.justification),
                checkMethod: Value(step.checkMethod),
                stuckRisk: Value(
                  risk == null ? null : DsrMemory.round6(risk.clamp(0.0, 1.0)),
                ),
                knowledgeHints: Value(jsonEncode(step.knowledgeHints)),
                note: Value(step.note),
                createdAt: ms,
              ),
            );
      }
      await (_db.update(_db.questions)..where((t) => t.id.equals(questionId)))
          .write(
        QuestionsCompanion(
          state: const Value('processed'),
          updatedAt: Value(ms),
        ),
      );
    });
    return chainId;
  }

  Future<List<ReasoningChain>> chainsOf(String questionId) =>
      (_db.select(_db.reasoningChains)
            ..where((t) => t.questionId.equals(questionId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Future<List<ReasoningStep>> stepsOf(String chainId) =>
      (_db.select(_db.reasoningSteps)
            ..where((t) => t.chainId.equals(chainId))
            ..orderBy([(t) => OrderingTerm.asc(t.idx)]))
          .get();

  /// 库里所有链的步骤（只读；能力动作画像用）。
  ///
  /// 不按题目/链过滤：画像要回答的是"我在哪些**动作**上反复卡"，跨题目聚合才有意义。
  /// 顺序不保证 —— 聚合层自己分桶统计，不依赖顺序。
  Future<List<ReasoningStep>> allReasoningSteps() =>
      _db.select(_db.reasoningSteps).get();
}
