import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/services/questions/question_number.dart';
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
      // 号只增不减；导入的包可能把号带成重复的（append 模式不重编号），这里只要
      // 保证本地新题的号是现有最大 + 1。
      final maxSerial = _db.questions.serialNo.max();
      final maxRow = await (_db.selectOnly(_db.questions)
            ..addColumns([maxSerial]))
          .getSingle();
      final serialNo = nextQuestionSerial(maxRow.read(maxSerial));
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
