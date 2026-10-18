/// 题库的**读表函数**（纯 Dart，不依赖 Riverpod）：组卷 / 找相似题 / AI 工具
/// 三处都要"读一次题库"，读法只写这一遍。
///
/// 为什么要从 provider 里搬出来：provider 只能活在 Riverpod 容器里，而 AI 工具
/// (`features/ai/tools/…`) 拿到的是裸的 `AppDatabase`（`ToolRegistry.forApp`
/// 只有 `db` 和几个仓库，没有 `Ref`）。如果读表逻辑留在 provider 内部，工具要么
/// 自己重写一遍"题目 → 知识点"的推导（两处规则必然分叉），要么为拿一个 `Ref`
/// 改掉工具注册工厂的签名。抽成函数是第三种、也是更小的做法：
/// provider = 数据版本 + 这层函数；工具 = 直接用这层函数。
///
/// 领域分工不变：题目 → 覆盖知识点一律走
/// `TaskKnowledgePointResolver.resolveFromTagLinks(..., sourceObjectType:
/// kQuestionObjectType)`，知识点 → 标签走 `KnowledgePointTagBridge`（键空间 Q8），
/// 阈值/权重/排序全留在 `domain/services/…`。这个文件只做读表与投影。
library;

import 'package:drift/drift.dart' show OrderingTerm;

import '../../../data/database/database.dart';
import '../../../data/repositories/assessment_repository.dart';
import '../../../data/repositories/question_repository.dart'
    show kSourceLevelWeight;
import '../../../domain/services/cognitive/fast_diagnosis.dart';
import '../../../domain/services/cognitive/knowledge_point_tag_bridge.dart';
import '../../../domain/services/cognitive/library_diagnosis.dart';
import '../../../domain/services/export/paper_docx.dart';
import '../../../domain/services/paper/paper_composer.dart';
import '../../../domain/services/questions/question_number.dart';
import '../../../domain/services/scheduling/cognitive_readings.dart';
import '../../../domain/services/scheduling/domain_balance.dart';
import '../../../domain/services/scheduling/thread_balance_inputs.dart';

/// 题库 + 知识点名字的一次读取快照：组卷、学科可选项、知识点名共用它，
/// 免得每个 provider 各读一遍表。
class PaperCorpus {
  const PaperCorpus({
    required this.candidates,
    required this.knowledgePointNames,
    required this.knowledgePointTagPaths,
  });

  /// 题干非空的全部题目（`state` 不筛：还没加工的题也能进卷，只是质量分低）。
  final List<PaperCandidate> candidates;

  /// 知识点 id → 标题（`KnowledgePoints.title`），用于理由行说人话。
  final Map<String, String> knowledgePointNames;

  /// 知识点 id → 它直挂的标签路径（`Tags.path`，形如 `文化课/学科/数学`），
  /// 用来给理由行补学科背景；挂载了标签但路径为空的点不会出现在这里。
  final Map<String, List<String>> knowledgePointTagPaths;

  bool get isEmpty => candidates.isEmpty;

  /// 题库里出现过的学科键（去空、去重、排序）。
  List<String> get subjectKeys {
    final keys = <String>{
      for (final candidate in candidates)
        if (candidate.subjectKey.trim().isNotEmpty) candidate.subjectKey.trim(),
    }.toList()
      ..sort();
    return keys;
  }
}

/// 读一次题库，拼出组卷需要的两张表（题目 + 知识点名/标签路径）。
Future<PaperCorpus> readPaperCorpus(AppDatabase db) async {
  final questionRows = await db.select(db.questions).get();
  final pointRows = await db.select(db.knowledgePoints).get();
  final tagRows = await db.select(db.tags).get();
  final linkRows = await db.select(db.objectTags).get();

  final objectLinks = <ObjectTagLink>[
    for (final row in linkRows)
      ObjectTagLink(
        tagId: row.tagId,
        objectType: row.objectType,
        objectId: row.objectId,
      ),
  ];
  // 题目自己的覆盖点：同一标签既挂题目、又挂知识点 → 这道题覆盖那个知识点。
  final pointsByQuestion = TaskKnowledgePointResolver.resolveFromTagLinks(
    objectLinks,
    sourceObjectType: kQuestionObjectType,
  );
  // 知识点挂的标签（键空间 Q8：`Tags.id` 是 `tag-…`，知识点 id 是 `kp-…`）。
  final tagIdsByPoint =
      KnowledgePointTagBridge.tagIdsByKnowledgePoint(objectLinks);
  final pathByTagId = <String, String>{
    for (final row in tagRows)
      if ((row.path ?? '').trim().isNotEmpty) row.id: row.path!.trim(),
  };

  return PaperCorpus(
    candidates: <PaperCandidate>[
      for (final row in questionRows)
        if (row.stem.trim().isNotEmpty)
          PaperCandidate(
            questionId: row.id,
            subjectKey: row.subjectKey,
            sourceLevel: row.sourceLevel,
            questionType: row.questionType,
            difficulty: row.difficulty,
            aiQuality: row.aiQuality,
            trapNote: row.trapNote,
            matchedKnowledgePointIds:
                pointsByQuestion[row.id] ?? const <String>[],
          ),
    ],
    knowledgePointNames: <String, String>{
      for (final row in pointRows)
        if (row.title.trim().isNotEmpty) row.id: row.title.trim(),
    },
    knowledgePointTagPaths: <String, List<String>>{
      for (final entry in tagIdsByPoint.entries)
        entry.key: <String>[
          for (final tagId in entry.value)
            if (pathByTagId.containsKey(tagId)) pathByTagId[tagId]!,
        ],
    },
  );
}

/// 一道题的最新一条链的步骤动作序列（`idx` 升序），键是题目 id。
///
/// 全部题目只读一次：`reasoning_chains` + `reasoning_steps` 各查一遍，
/// 免得为每道题各查一次表。一道题可能有多条链（不同模型/不同次）：只认最新那条，
/// 平手比 id，结果确定。`createdAt` 是 epoch 毫秒（int），不是 DateTime。
Future<Map<String, List<String>>> readChainActionTypes(AppDatabase db) async {
  final chains = await db.select(db.reasoningChains).get();
  final steps = await db.select(db.reasoningSteps).get();

  // 每条链的动作序列（idx 升序）。
  final actionsByChain = <String, List<String>>{};
  final sortedSteps = [...steps]..sort((a, b) {
      final byChain = a.chainId.compareTo(b.chainId);
      return byChain != 0 ? byChain : a.idx.compareTo(b.idx);
    });
  for (final step in sortedSteps) {
    final action = step.actionType.trim();
    if (action.isEmpty) continue;
    (actionsByChain[step.chainId] ??= <String>[]).add(action);
  }

  final latestByQuestion = <String, ({int createdAt, String id})>{};
  for (final chain in chains) {
    final questionId = chain.questionId.trim();
    if (questionId.isEmpty) continue;
    final current = latestByQuestion[questionId];
    final isNewer = current == null ||
        chain.createdAt > current.createdAt ||
        (chain.createdAt == current.createdAt &&
            chain.id.compareTo(current.id) > 0);
    if (isNewer) {
      latestByQuestion[questionId] = (createdAt: chain.createdAt, id: chain.id);
    }
  }

  return {
    for (final entry in latestByQuestion.entries)
      entry.key: List<String>.unmodifiable(
        actionsByChain[entry.value.id] ?? const <String>[],
      ),
  };
}

/// 一张"按能力动作找题"的检索行：题目本身 + 题干 + 它链上的动作序列。
class CapabilityQuestionRow {
  const CapabilityQuestionRow({
    required this.questionId,
    required this.stem,
    required this.subjectKey,
    required this.sourceLevel,
    required this.actionTypes,
    this.matchedActionTypes = const [],
  });

  final String questionId;
  final String stem;
  final String subjectKey;
  final String sourceLevel;

  /// 这一题**最新一条链**的全部动作（含命中的那些）。没解过链的题不会出现在这张表里。
  final List<String> actionTypes;

  /// 这一次查询**命中**的动作（按查询里的顺序）；没按动作筛时是空表。
  ///
  /// 与 [actionTypes] 分开：前者是"我为什么被选中"，后者是"这条链长什么样"。
  final List<String> matchedActionTypes;
}

/// 「按能力动作找题」的查询条件。
///
/// 单动作是最常见的问法（画像点开的那一行），但对话里经常是组合问法：
/// "我一碰到**分类讨论**和**回代检验**就卡，给我两道两道都得用上的题"（`requireAll`），
/// 或者"分类讨论类的**物理**题还有几道"（[subjectKey]）。
class CapabilityQuestionQuery {
  const CapabilityQuestionQuery({
    this.actionTypes = const <String>[],
    this.subjectKey = '',
    this.requireAll = false,
  });

  /// 要筛的动作 key（去空、去重；空 = 不按动作筛，只按学科）。
  final List<String> actionTypes;

  /// 只要这个学科（空 = 不限）。
  final String subjectKey;

  /// `true` = 最新链里**每个**动作都得出现；`false` = 命中一个就算。
  final bool requireAll;

  /// 归一化后的查询：去空/去重，学科 trim。
  CapabilityQuestionQuery normalized() => CapabilityQuestionQuery(
        actionTypes: actionTypes
            .map((action) => action.trim())
            .where((action) => action.isNotEmpty)
            .toSet()
            .toList(),
        subjectKey: subjectKey.trim(),
        requireAll: requireAll,
      );

  /// 值相等（按**归一化后**的动作集合 + 学科 + `requireAll` 比）。
  ///
  /// 这不是锦上添花：它让 `CapabilityQuestionQuery` 能当 Riverpod family 的键 ——
  /// 页面重建时同一个查询不会重复读表，`Set`/`==` 也让人在测试里直接比查询。
  @override
  bool operator ==(Object other) {
    if (other is! CapabilityQuestionQuery) return false;
    final mine = normalized();
    final theirs = other.normalized();
    final mineSet = mine.actionTypes.toSet();
    final theirsSet = theirs.actionTypes.toSet();
    return mine.subjectKey == theirs.subjectKey &&
        mine.requireAll == theirs.requireAll &&
        mineSet.length == theirsSet.length &&
        mineSet.containsAll(theirsSet);
  }

  @override
  int get hashCode {
    final normalizedQuery = normalized();
    return Object.hash(
      normalizedQuery.subjectKey,
      normalizedQuery.requireAll,
      Object.hashAllUnordered(normalizedQuery.actionTypes),
    );
  }
}

/// 按能力动作找题：题目最新一条链的动作序列里含 [actionType] 的题。
///
/// 为什么认"最新一条链"：与组卷的动作偏好、找相似题的动作对齐用同一个口径
/// （[readChainActionTypes]）—— 一处定义、三处复用；也避免"按画面筛出来的题"
/// 与"组卷里算的命中"是两份不同的判断。
///
/// 排序：来源分级高的在前（`kSourceLevelWeight` 与检索/组卷同序），平手按题目 id，
/// 保证同一份库刷两次顺序一样。
Future<List<CapabilityQuestionRow>> readQuestionsForAction(
  AppDatabase db,
  String actionType,
) =>
    readQuestionsForCapabilities(
      db,
      CapabilityQuestionQuery(actionTypes: <String>[actionType]),
    );

/// 组合查询：按一组动作（任一 / 全部）+ 学科筛题库里解过链的题。
///
/// 三条纪律：
/// 1. **动作与学科都不能为空**：两个都空就没有"问的是什么" —— 返回空表，不把整个
///    解过链的题库倒出来（那不是查询，那是导出）。
/// 2. **只认最新一条链**（与 [readQuestionsForAction] 同一份口径）。
/// 3. **命中项如实回报**（[CapabilityQuestionRow.matchedActionTypes]）：模型/界面得能
///    区分"我因为哪几个动作被选中"，而不是只看到"链上有一堆动作"。
Future<List<CapabilityQuestionRow>> readQuestionsForCapabilities(
  AppDatabase db,
  CapabilityQuestionQuery query,
) async {
  final wanted = query.normalized();
  if (wanted.actionTypes.isEmpty && wanted.subjectKey.isEmpty) {
    return const <CapabilityQuestionRow>[];
  }

  final actionsByQuestion = await readChainActionTypes(db);
  final matched = <String, List<String>>{};
  for (final entry in actionsByQuestion.entries) {
    final chainActions = entry.value;
    final hit = <String>[
      for (final action in wanted.actionTypes)
        if (chainActions.contains(action)) action,
    ];
    if (wanted.actionTypes.isNotEmpty) {
      final ok = wanted.requireAll
          ? hit.length == wanted.actionTypes.length
          : hit.isNotEmpty;
      if (!ok) continue;
    }
    matched[entry.key] = hit;
  }
  if (matched.isEmpty) {
    return const <CapabilityQuestionRow>[];
  }

  final rows = await (db.select(db.questions)
        ..where((t) => t.id.isIn(matched.keys.toList())))
      .get();
  final byId = {for (final row in rows) row.id: row};
  final result = <CapabilityQuestionRow>[
    for (final entry in matched.entries)
      if (byId[entry.key] != null &&
          byId[entry.key]!.stem.trim().isNotEmpty &&
          (wanted.subjectKey.isEmpty ||
              byId[entry.key]!.subjectKey.trim() == wanted.subjectKey))
        CapabilityQuestionRow(
          questionId: entry.key,
          stem: byId[entry.key]!.stem.trim(),
          subjectKey: byId[entry.key]!.subjectKey,
          sourceLevel: byId[entry.key]!.sourceLevel,
          actionTypes: actionsByQuestion[entry.key]!,
          matchedActionTypes: List<String>.unmodifiable(entry.value),
        ),
  ];
  result.sort((a, b) {
    final bySource = (kSourceLevelWeight[b.sourceLevel] ?? 0)
        .compareTo(kSourceLevelWeight[a.sourceLevel] ?? 0);
    return bySource != 0 ? bySource : a.questionId.compareTo(b.questionId);
  });
  return List<CapabilityQuestionRow>.unmodifiable(result);
}

/// 题目 id → 题干（已 trim，空题干不进结果）。
///
/// `SimilarQuestion` / `SimilarityCandidate` 里**没有题干**（领域层只比信号，不搬
/// 大段文本），所以"要让用户/模型看到是哪道题"的地方都得回表取一次。给 [ids]
/// 时只查这些行（AI 工具一次只返回十来条，不必扫全表）；不给就是全表。
Future<Map<String, String>> readQuestionStems(
  AppDatabase db, {
  Iterable<String>? ids,
}) async {
  final wanted = ids == null
      ? null
      : <String>{
          for (final id in ids)
            if (id.trim().isNotEmpty) id.trim(),
        };
  if (wanted != null && wanted.isEmpty) return const <String, String>{};

  final query = db.select(db.questions);
  if (wanted != null) {
    query.where((t) => t.id.isIn(wanted));
  }
  final rows = await query.get();
  return <String, String>{
    for (final row in rows)
      if (row.stem.trim().isNotEmpty) row.id: row.stem.trim(),
  };
}

/// 诊断结论 + 测评先验 → 组卷读数（Q11 的取舍，搬到这里好让 AI 工具复用）。
///
/// 读数覆盖**两类**知识点：题库里有候选的（用来打分），以及诊断出危险/发展区但题库
/// 一道候选都没有的（组卷器要靠它把"该去收题"的点报进
/// `PaperPlan.uncoveredKnowledgePointIds`——如果只喂有候选的点，这个清单永远是空的）。
///
/// 一个刻意的取舍：**只有拿到诊断结论（`danger` / `weak`）的知识点才进打分读数**。
/// `CognitiveReadingsAdapter` 会为"只有测评先验、没有诊断结论"的点也产出读数，而
/// 组卷器把"不是危险区、也不是发展区"的读数一律映射成 `PaperZone.healthy`
/// （need 0.15，**低于**"未知"的 0.35）——直接喂进去等于把"没测过"当成"学得好"。
/// 所以这里按结论过滤：没有结论的点按未知处理，先验仍作为已诊断点的 R0 补充
/// （`PaperItem.reasonZh` 会带上 `R0=`）。
///
/// [diagnosis] 用 `LibraryDiagnosis`（而不是裸 map）是为了让
/// "快层没跑"（`fastLayerRan == false`）与"跑了、没发现瓶颈"保持可区分：
/// 前者返回空读数（"没跑"不是"健康"），后者才按结论过滤。
Future<List<KnowledgePointReading>> readPaperReadings(
  AppDatabase db, {
  required Set<String> coveredKnowledgePointIds,
  required LibraryDiagnosis diagnosis,
}) async {
  // 快层没跑 = 没有结论 = 全部按未知，"没跑"不是"健康"。
  if (!diagnosis.fastLayerRan) return const <KnowledgePointReading>[];
  final verdicts = diagnosis.byKnowledgePoint;
  final diagnosedIds = <String>{
    for (final entry in verdicts.entries)
      if (_isDiagnosed(entry.value)) entry.key,
  };
  final ids = <String>{...coveredKnowledgePointIds, ...diagnosedIds};
  if (ids.isEmpty) return const <KnowledgePointReading>[];
  final priors = await AssessmentRepository(db).priorEstimatesFor(ids);
  return <KnowledgePointReading>[
    for (final reading in CognitiveReadingsAdapter.readingsFor(
      knowledgePointIds: ids,
      diagnosisByKnowledgePoint: verdicts,
      priors: priors,
    ))
      if (_isDiagnosed(verdicts[reading.knowledgePointId])) reading,
  ];
}

bool _isDiagnosed(BottleneckType? verdict) =>
    verdict == BottleneckType.danger || verdict == BottleneckType.weak;

/// 一道题的 docx 导出素材：题干/题号/来源/选项/答案/解析。
///
/// 为什么单独一个类型而不直接回 [PaperDocxQuestion]：那个类型还要求配图
/// （[PaperDocxImage] 里有字节），而读图字节要走 `QuestionMediaStore`（dart:io），
/// 这个文件是纯读表、不碰文件系统。应用层拿到本类型，再补上图片才装配成
/// [PaperDocxQuestion]。
class QuestionDocxRow {
  const QuestionDocxRow({
    required this.questionId,
    required this.stem,
    this.serialNo,
    this.subjectKey = '',
    this.sourceLevel = '',
    this.sourceLabel = '',
    this.year,
    this.region = '',
    this.questionType = '',
    this.options = const <PaperDocxOption>[],
    this.answer,
    this.solution,
  });

  final String questionId;

  /// 库里的整数编号（v24）；导出时再格式化成 `TR-00001`。
  final int? serialNo;
  final String stem;
  final String subjectKey;
  final String sourceLevel;
  final String sourceLabel;
  final int? year;

  /// 地区；库里是 nullable，这里空串表示没有。
  final String region;
  final String questionType;
  final List<PaperDocxOption> options;
  final String? answer;
  final String? solution;

  /// 补上图片后转成装配层要的题目对象。
  PaperDocxQuestion toPaperDocxQuestion({
    List<PaperDocxImage> images = const <PaperDocxImage>[],
  }) {
    return PaperDocxQuestion(
      questionId: questionId,
      stem: stem,
      serialNo: serialNo == null || serialNo! < 1
          ? null
          : formatQuestionSerial(serialNo!),
      subjectKey: subjectKey,
      sourceLevel: sourceLevel,
      sourceLabel: sourceLabel,
      year: year,
      region: region,
      questionType: questionType,
      options: options,
      answer: answer,
      solution: solution,
      images: images,
    );
  }
}

/// 题目 id → docx 导出素材。给 [ids] 时只查这些题（卷子就十来道，不必扫全表）；
/// 不给就是全表。
///
/// 空题干保留（与 [readQuestionStems] 不同）：导出要如实报「第 N 题题干为空」，
/// 悄悄少一道题比留个空题干更糟。
Future<Map<String, QuestionDocxRow>> readQuestionDocxRows(
  AppDatabase db, {
  Iterable<String>? ids,
}) async {
  final wanted = ids == null
      ? null
      : <String>{
          for (final id in ids)
            if (id.trim().isNotEmpty) id.trim(),
        };
  if (wanted != null && wanted.isEmpty) {
    return const <String, QuestionDocxRow>{};
  }

  final questionQuery = db.select(db.questions);
  if (wanted != null) {
    questionQuery.where((t) => t.id.isIn(wanted));
  }
  final questionRows = await questionQuery.get();
  if (questionRows.isEmpty) return const <String, QuestionDocxRow>{};

  final questionIds = <String>{for (final row in questionRows) row.id};
  final optionRows = await (db.select(db.questionOptions)
        ..where((t) => t.questionId.isIn(questionIds))
        ..orderBy([
          (t) => OrderingTerm.asc(t.sortOrder),
          (t) => OrderingTerm.asc(t.id),
        ]))
      .get();
  final optionsByQuestion = <String, List<PaperDocxOption>>{};
  for (final row in optionRows) {
    (optionsByQuestion[row.questionId] ??= <PaperDocxOption>[]).add(
      PaperDocxOption(
        label: row.label,
        content: row.content,
        isCorrect: row.isCorrect,
      ),
    );
  }

  return <String, QuestionDocxRow>{
    for (final row in questionRows)
      row.id: QuestionDocxRow(
        questionId: row.id,
        stem: row.stem,
        serialNo: row.serialNo,
        subjectKey: row.subjectKey,
        sourceLevel: row.sourceLevel,
        sourceLabel: row.sourceLabel,
        year: row.year,
        region: row.region ?? '',
        questionType: row.questionType,
        options: List<PaperDocxOption>.unmodifiable(
          optionsByQuestion[row.id] ?? const <PaperDocxOption>[],
        ),
        answer: row.answer,
        solution: row.solution,
      ),
  };
}

/// 知识点 id → 标题。docx 卷面的理由行要它；只读 knowledge_points 一张表。
Future<Map<String, String>> readKnowledgePointNames(AppDatabase db) async {
  final rows = await db.select(db.knowledgePoints).get();
  return <String, String>{
    for (final row in rows)
      if (row.title.trim().isNotEmpty) row.id: row.title.trim(),
  };
}
