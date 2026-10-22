/// 题库能力（Q12 找相似题）接进 AI 工具层。
///
/// 用户口径：AI **不出题**，只解题 / 拆题 / **找相似题**。所以这个工具只做一件事：
/// 把"一道题（或一组条件）"交给 `SimilarQuestionFinder`，在**已有题库**里排序，
/// 返回题干摘要与人话理由；找不到就如实说没有，绝不生成题干。它是
/// `docs/SIMILAR_QUESTIONS_DESIGN.md` 的工具面，也是 `evaluate_problem_fit` 的兄弟：
/// 那个回答"现在做哪道划得来"，这个回答"这道题还有哪些同型邻居"。
///
/// 为什么它在这里而不是在页面里：页面上"找相似题"区块只服务"眼前这道题"，而
/// 对话里的模型经常需要反着问——"给我两道和这个知识点同型、但学科不同的题"
/// （只有 `knowledge_point_ids` / `action_types`，没有 `question_id`）。同一个领域层
/// 排序器，两种问法。
///
/// 读表走 `questions/application/question_corpus_reader.dart` 的纯函数（和组卷页、
/// 详情页同一份"题目 → 覆盖知识点/思维链动作"的推导），工具自己**不写 SQL**、
/// 不重写规则、不设阈值（阈值/权重都在领域层）。
library;

import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/question_repository.dart';
import '../../../domain/services/paper/similar_questions.dart';
import '../../../domain/services/questions/question_number.dart';
import '../../../domain/services/questions/question_serial_batch.dart';
import '../../../domain/services/questions/question_snapshot_summary.dart';
import '../../../domain/services/reasoning/capability_action.dart';
import '../../questions/application/question_corpus_reader.dart';
import '../domain/ai_tool.dart';

/// 附件角色在**读侧**折叠后的两类（v27 `attachments.role`，镜像 `QuestionImageRole`）。
///
/// 为什么在这里复制字面量、不 import `question_media_store.dart`：那个文件要
/// `dart:io` + `path_provider`，AI 工具层保持只依赖 drift / 纯 Dart，不把 IO 栈
/// 拖进来。角色词表改动时两处一起改：见 `tables.dart` 的 `Attachments.role` 注释
/// 与 `question_media_store.dart` 的 `effectiveQuestionImageRole`。
///
/// 语义与 `effectiveQuestionImageRole` 一致：NULL / 空串 / 纯空白都算题干配图；
/// 不认识的值（例如以后新增的角色）**两桶都不算**，只如实不计。
bool _isStemQuestionImageRole(String? stored) {
  final role = stored?.trim() ?? '';
  return role.isEmpty || role == 'stem';
}

bool _isAnswerQuestionImageRole(String? stored) {
  final role = stored?.trim() ?? '';
  return role == 'answer' || role == 'solution';
}

/// 题干是整卡截图时给摘要补的一句；非快照返回空串（既有摘要一字不改）。
///
/// 口径与 `question_snapshot_summary.dart` 的 [QuestionSnapshotSummary.labelZh]
/// 一致：快照有占位报「N 处公式/图」，没有占位只说「整题截图」。
String _snapshotClauseOf(QuestionSnapshotSummary snapshot) {
  if (!snapshot.isSnapshot) {
    return '';
  }
  final detail = snapshot.placeholderCount > 0
      ? '（${snapshot.placeholderCount} 处公式/图）'
      : '';
  return '；题干是整题截图$detail，正文可能只是占位，原题看图片';
}

/// 在已有题库里给一道题（或一组条件）找相似题。
class FindSimilarQuestionsTool extends AiTool {
  FindSimilarQuestionsTool({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  /// 一次调用默认返回几条。
  static const int defaultLimit = 5;

  /// 上限：再多也不是"相似"，而是把整个题库倒出来。
  static const int maxLimit = 20;

  /// 题干在结果里截断到多少个字（模型只需要认得出是哪道题）。
  static const int stemPreviewLength = 120;

  @override
  String get name => 'find_similar_questions';

  @override
  String get description => '在用户**已有的题库**里找相似题：给一道题 id（或给知识点/能力动作/学科/难度等条件），'
      '按"共用知识点 → 同型解题步骤 → 同学科 → 难度接近"排序，返回每题为什么像、是否值得'
      '跨学科迁移训练。用在你需要"同型题练手"的时候：刚讲完一道题想配一道同型的、'
      '想知道某知识点库里还有几道题、想找学科不同但解题步骤同型的题。'
      '**只读**：不写数据、不生成题干、不落库——它只报库里已有的题，找不到就说没有。'
      '这不是搜关键词：它比的是知识点覆盖与思维链动作序列。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'question_id': {
            'type': 'string',
            'description': '基准题的 id（库里已有的题）。给它会用它自己的知识点、学科、'
                '难度和思维链动作；和下面的条件可以一起给，这里给的条件优先用它的。',
          },
          'knowledge_point_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '基准要练的知识点 id（没有 question_id 时至少给一项，'
                '否则会失败）。权重最高的信号。',
          },
          'action_types': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '基准的解题能力动作 key 序列（如 classify_discussion / '
                'layer_answer）；跨学科迁移靠它。',
          },
          'subject_key': {
            'type': 'string',
            'description': '基准学科键（如 math）。只作加分项，不是必须。',
          },
          'question_type': {
            'type': 'string',
            'description': '基准题型（如 multiple_choice / solution）。',
          },
          'difficulty': {
            'type': 'number',
            'description': '基准难度 1..10；缺省时难度分量取中性，不惩罚"不知道"。',
          },
          'limit': {
            'type': 'integer',
            'description': '最多返回几条，默认 $defaultLimit（上限 $maxLimit）',
          },
        },
        'required': <String>[],
      };

  /// 只读、无 action：`riskFor` 用中性 `write` + `reversibleFor` true，正是这个组合
  /// 让 `ApprovalEngine` 在两种权限模式下都不会逐条询问它（同 `evaluate_problem_fit`）。
  @override
  ToolRisk riskFor(String action) => ToolRisk.write; // unused: no actions

  @override
  bool reversibleFor(String action) => true;

  @override
  bool get readOnly => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    try {
      final args = ToolArgs(invocation.arguments);
      final questionId = args.optString('question_id');
      final pointIds =
          args.optStringList('knowledge_point_ids') ?? const <String>[];
      final actionTypes =
          args.optStringList('action_types') ?? const <String>[];
      final subjectKey = args.optString('subject_key') ?? '';
      final questionType = args.optString('question_type') ?? '';
      final difficulty = args.optDouble('difficulty');
      final limit = _limitOf(args);

      final hasBasis = questionId != null ||
          pointIds.isNotEmpty ||
          actionTypes.isNotEmpty ||
          subjectKey.isNotEmpty ||
          questionType.isNotEmpty ||
          difficulty != null;
      if (!hasBasis) {
        throw ToolArgError(
          '缺少基准：给 `question_id`（库里已有的题），或至少一个 '
          '`knowledge_point_ids` / `action_types` / `subject_key` / '
          '`question_type` / `difficulty`',
        );
      }

      final corpus = await readPaperCorpus(_db);
      if (corpus.candidates.isEmpty) {
        return const ToolResult(
          ok: true,
          summary: '题库里还没有题，所以没有可找的相似题——我不会自己出题；'
              '先去收题页录入这道题或几道同知识点的真题。',
          modelResult: {
            'returned': 0,
            'bank_size': 0,
            'questions': <Object?>[],
          },
        );
      }

      final actionByQuestion = await readChainActionTypes(_db);
      final candidates = <SimilarityCandidate>[
        for (final candidate in corpus.candidates)
          SimilarityCandidate(
            questionId: candidate.questionId,
            knowledgePointIds: candidate.matchedKnowledgePointIds,
            subjectKey: candidate.subjectKey,
            questionType: candidate.questionType,
            sourceLevel: candidate.sourceLevel,
            difficulty: candidate.difficulty,
            actionTypes:
                actionByQuestion[candidate.questionId] ?? const <String>[],
          ),
      ];

      final SimilarityFocus focus;
      if (questionId != null) {
        final fromBank = _focusOf(candidates, questionId);
        if (fromBank != null) {
          focus = fromBank;
        } else {
          // 题不在题库快照里（题干为空，或刚被删）：仍可按它的学科/难度找邻居，
          // 但知识点与动作只能为空——查无此题才失败。
          final row = await (_db.select(_db.questions)
                ..where((t) => t.id.equals(questionId)))
              .getSingleOrNull();
          if (row == null) {
            return ToolResult.failure('题库里没有 id 为 `$questionId` 的题');
          }
          focus = SimilarityFocus(
            questionId: row.id,
            subjectKey: row.subjectKey,
            questionType: row.questionType,
            difficulty: row.difficulty,
            actionTypes: actionByQuestion[row.id] ?? const <String>[],
          );
        }
      } else {
        focus = SimilarityFocus(
          questionId: '',
          knowledgePointIds: pointIds,
          actionTypes: actionTypes,
          subjectKey: subjectKey,
          questionType: questionType,
          difficulty: difficulty,
        );
      }

      final found = SimilarQuestionFinder.rank(
        focus: focus,
        candidates: candidates,
        limit: limit,
        knowledgePointNames: corpus.knowledgePointNames,
      );
      final stems = await readQuestionStems(
        _db,
        ids: [for (final item in found) item.questionId],
      );

      return ToolResult(
        ok: true,
        summary: _summaryOf(found, stems, candidates.length),
        modelResult: {
          'returned': found.length,
          'bank_size': candidates.length,
          'min_score': kMinSimilarityScore,
          'focus': {
            'question_id': focus.questionId,
            'knowledge_point_ids': focus.knowledgePointIds,
            'subject_key': focus.subjectKey,
            'difficulty': focus.difficulty,
            'action_types': focus.actionTypes,
          },
          'questions': [
            for (final item in found)
              {
                'id': item.questionId,
                'stem': previewStem(stems[item.questionId]),
                'score': item.score,
                'components': item.components,
                'cross_subject_transfer': item.crossSubjectTransfer,
                'shared_knowledge_point_ids': item.sharedKnowledgePointIds,
                'shared_knowledge_points': [
                  for (final id in item.sharedKnowledgePointIds)
                    corpus.knowledgePointNames[id] ?? id,
                ],
                'shared_action_types': item.sharedActionTypes,
                'shared_actions_zh': [
                  for (final key in item.sharedActionTypes)
                    CapabilityAction.byKey(key)?.labelZh ?? key,
                ],
                'reason': item.reasonZh,
              },
          ],
        },
      );
    } on ToolArgError catch (e) {
      // Caused by the model, so it becomes something it can read and correct.
      return ToolResult.failure(e.message);
    }
  }

  /// 在候选里找这道题自己的基准（题干空/已删的题不在候选里 → null）。
  SimilarityFocus? _focusOf(
    List<SimilarityCandidate> candidates,
    String questionId,
  ) {
    for (final candidate in candidates) {
      if (candidate.questionId == questionId) {
        return SimilarityFocus(
          questionId: candidate.questionId,
          knowledgePointIds: candidate.knowledgePointIds,
          subjectKey: candidate.subjectKey,
          questionType: candidate.questionType,
          difficulty: candidate.difficulty,
          actionTypes: candidate.actionTypes,
        );
      }
    }
    return null;
  }

  int _limitOf(ToolArgs args) {
    final raw = args.optInt('limit') ?? defaultLimit;
    if (raw < 1) {
      return defaultLimit;
    }
    return raw > maxLimit ? maxLimit : raw;
  }

  /// 用户读的一行：找到时点名最像的三道（题干摘要 + 分数），找不到时说明"库里有
  /// 多少道、但我不会自己出题"。
  String _summaryOf(
    List<SimilarQuestion> found,
    Map<String, String> stems,
    int bankSize,
  ) {
    if (found.isEmpty) {
      return '题库里共 $bankSize 道题，没有一道够像（相似度 ≥ '
          '${kMinSimilarityScore.toStringAsFixed(2)}）——我不会自己出题，'
          '要么去收题页补同知识点的题，要么放宽条件（给知识点或动作序列）。';
    }
    final top = found
        .take(3)
        .map((item) =>
            '${previewStem(stems[item.questionId])}（${item.score.toStringAsFixed(2)}）')
        .join('；');
    final cross = found.where((item) => item.crossSubjectTransfer).length;
    return '在题库 $bankSize 道题里找到 ${found.length} 道相似题'
        '${cross > 0 ? '（其中 $cross 道是跨学科但解题步骤同型）' : ''}：$top';
  }
}

/// 按能力动作找题：链上出现过某个（或某几个）跨学科动作的题
/// （`docs/REASONING_LAYER_DESIGN.md` §13 的工具面）。
///
/// 与页面上那一条同源（`readQuestionsForCapabilities`，同一个"只认最新一条链"口径）：页面给
/// 用户点，工具给模型问。为什么模型需要它：聊到"我老是在分类讨论这一步卡住"时，
/// 模型要能**直接查到**哪几道题会练到这个动作，而不是让用户自己去题库里翻；但它仍然
/// 只从已有题库里找，**不出题**。
///
/// 组合问法（轮次一百零七）：`action_types` + `match`（任一 / 全部）+ `subject_key`
/// —— "分类讨论和回代检验都得用上的题""分类讨论类的物理题还剩几道"都能问。
class FindQuestionsByCapabilityTool extends AiTool {
  FindQuestionsByCapabilityTool({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  /// 一次调用默认返回几条。
  static const int defaultLimit = 10;

  /// 上限：再多就是把题库倒出来，不是"按动作找题"。
  static const int maxLimit = 50;

  @override
  String get name => 'find_questions_by_capability';

  @override
  String get description => '按**能力动作**（跨学科思维动作，如分类讨论 / 回代检验 / 极端化）在用户已有的题库里找题：'
      '返回链上出现过这些动作的题（题干摘要 + 学科 + 来源 + 命中动作 + 链上全部动作）。'
      '用在"我在某个动作上反复卡住，该练哪几道"的时候；配套的读数在认知模型页的'
      '「能力动作画像」（那条画像回答"哪个动作最该练"，这个工具回答"练哪几道"）。'
      '可以组合：给多个 `action_types` + `match`（`any` 任一 / `all` 全部）+ `subject_key` 学科。'
      '**只读**：不写数据、不生成题干、不落库——只报库里已有的题，没有就说没有。'
      '口径：只认每道题**最新一条**解题链的动作序列；没解过链的题不会出现在结果里。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'action_types': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '能力动作 key 列表（词表里的稳定标识，如 `case_split`）。'
                '与 `action_type` 二选一或一起给（合并去重）；都不给时必须给 `subject_key`。'
                '不认识的 key 会失败并列出可用值。',
          },
          'action_type': {
            'type': 'string',
            'description': '单个能力动作 key（`action_types` 的简写，给一个动作时用）。',
          },
          'match': {
            'type': 'string',
            'enum': <String>['any', 'all'],
            'description': '多个动作时怎么算命中：`any`（默认，命中一个就算）或 `all`'
                '（每个动作都要出现在最新一条链里）。',
          },
          'subject_key': {
            'type': 'string',
            'description': '只在这个学科里找（如 `math` / `physics`）；不给 = 不限学科。',
          },
          'limit': {
            'type': 'integer',
            'description': '最多返回几条，默认 $defaultLimit（上限 $maxLimit）',
          },
        },
        'required': <String>[],
      };

  /// 只读、无 action：与 `find_similar_questions` / `evaluate_problem_fit` 同一个中性组合。
  @override
  ToolRisk riskFor(String action) => ToolRisk.write; // unused: no actions

  @override
  bool reversibleFor(String action) => true;

  @override
  bool get readOnly => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    final args = ToolArgs(invocation.arguments);
    final single = (args.optString('action_type') ?? '').trim();
    final actions = <String>{
      for (final raw in args.optStringList('action_types') ?? const <String>[])
        if (raw.trim().isNotEmpty) raw.trim(),
      if (single.isNotEmpty) single,
    }.toList();
    final subjectKey = (args.optString('subject_key') ?? '').trim();
    final match = (args.optString('match') ?? 'any').trim();

    if (match != 'any' && match != 'all') {
      throw ToolArgError('`match` 只能是 `any` 或 `all`（收到 `$match`）');
    }
    if (actions.isEmpty && subjectKey.isEmpty) {
      throw ToolArgError(
        '缺少查询条件：至少给一个 `action_types`（数组）/ `action_type`（单个）'
        '或 `subject_key`',
      );
    }
    final unknown = <String>[
      for (final action in actions)
        if (!CapabilityAction.isKnownKey(action)) action,
    ];
    if (unknown.isNotEmpty) {
      final available = CapabilityAction.catalog
          .map((action) => '`${action.key}`（${action.labelZh}）')
          .join(' / ');
      return ToolResult.failure(
        '不认识的能力动作 ${unknown.map((key) => '`$key`').join('、')}。可用：$available',
      );
    }

    final query = CapabilityQuestionQuery(
      actionTypes: actions,
      subjectKey: subjectKey,
      requireAll: match == 'all',
    );
    final rows = await readQuestionsForCapabilities(_db, query);
    final limit = _limitOf(args);
    final shown = rows.take(limit).toList(growable: false);

    if (rows.isEmpty) {
      return ToolResult(
        ok: true,
        summary: _emptySummary(actions, subjectKey),
        modelResult: {
          'query': _queryJson(query),
          'returned': 0,
          'candidates': 0,
          'rule': 'latest_chain_only',
          'questions': <Object?>[],
        },
      );
    }

    return ToolResult(
      ok: true,
      summary: _summaryOfCapability(shown, rows.length, query),
      modelResult: {
        'query': _queryJson(query),
        'returned': shown.length,
        'candidates': rows.length,
        'rule': 'latest_chain_only',
        'questions': [
          for (final row in shown)
            {
              'id': row.questionId,
              'stem': previewStem(row.stem),
              'subject_key': row.subjectKey,
              'subject': _subjectOf(row.subjectKey),
              'source_level': row.sourceLevel,
              'matched_action_types': row.matchedActionTypes,
              'matched_actions_zh': _labelsOf(row.matchedActionTypes),
              'action_types': row.actionTypes,
              'action_labels_zh': _labelsOf(row.actionTypes),
            },
        ],
      },
    );
  }

  int _limitOf(ToolArgs args) {
    final raw = args.optInt('limit') ?? defaultLimit;
    if (raw < 1) {
      return defaultLimit;
    }
    return raw > maxLimit ? maxLimit : raw;
  }

  Map<String, Object?> _queryJson(CapabilityQuestionQuery query) {
    final normalized = query.normalized();
    return {
      'action_types': normalized.actionTypes,
      'action_labels_zh': _labelsOf(normalized.actionTypes),
      'subject_key': normalized.subjectKey,
      'subject': _subjectOf(normalized.subjectKey),
      'match': normalized.requireAll ? 'all' : 'any',
    };
  }

  String _emptySummary(List<String> actions, String subjectKey) {
    final subject = subjectKey.isEmpty ? '' : '「${_subjectOf(subjectKey)}」';
    if (actions.isEmpty) {
      return '题库里还没有解过链的$subject题——我不会自己出题；先去某道题的详情页按一次'
          '「AI 解题」，让它落一条解题链，之后这里才有东西可找。';
    }
    final labels = _labelsOf(actions).map((label) => '「$label」').join('、');
    return '题库里还没有解过含$labels的$subject题——我不会自己出题；先去某道题的详情页按一次'
        '「AI 解题」，让它落一条解题链，之后这里才有东西可找。';
  }

  String _summaryOfCapability(
    List<CapabilityQuestionRow> shown,
    int total,
    CapabilityQuestionQuery query,
  ) {
    final normalized = query.normalized();
    final labels = _labelsOf(normalized.actionTypes);
    final subject = normalized.subjectKey.isEmpty
        ? ''
        : '「${_subjectOf(normalized.subjectKey)}」里的';
    final String rule;
    if (labels.isEmpty) {
      rule = '解过链的$subject';
    } else if (normalized.requireAll) {
      rule = '最新链同时含${labels.map((label) => '「$label」').join('、')}的$subject';
    } else {
      rule = '最新链含${labels.map((label) => '「$label」').join('或')}的$subject';
    }
    final top = shown.take(3).map((row) {
      return '${previewStem(row.stem)}（${_subjectOf(row.subjectKey)}）';
    }).join('；');
    final more =
        total > shown.length ? '（共 $total 道，这里只给 ${shown.length} 道）' : '';
    return '$rule题 $total 道$more：$top。'
        '只算每道题最新一条解题链；这些是题库里已有的题，不是我出的。';
  }

  List<String> _labelsOf(List<String> keys) => <String>[
        for (final key in keys) CapabilityAction.byKey(key)?.labelZh ?? key,
      ];

  String _subjectOf(String subjectKey) {
    if (subjectKey.trim().isEmpty) {
      return '';
    }
    return CapabilityAction.subjectLabelsZh[subjectKey] ?? subjectKey;
  }
}

/// 读一道题的完整内容（题干 / 选项 / 答案 / 解析 / 知识点 / 解题链动作
/// / 题干配图与答案/解析截图数）。
///
/// 用户口径：AI **不出题**，只解题 / 拆题 / 找相似题。要解题先得看见题——
/// 对话里在此之前只能靠 `find_similar_questions` 拿题干摘要，模型讲不清一道具体题
/// 的选项与解析。这个工具补上「读题」这一步，它仍然**只读**：不写库、不出题；
/// 题号解析复用 `domain/services/questions/question_number.dart`，与题库页同一口径。
///
/// 题干是整卡截图时（1 张题干图 + 至少 2 处「［图N］」占位且没有已知尺寸，
/// B2 口径），`modelResult` 的 `stem_is_snapshot` 为 true、`stem_snapshot_label`
/// 给「整题截图 · N 处公式/图」，摘要补一句让模型别把占位当正文。
class ReadQuestionTool extends AiTool {
  ReadQuestionTool({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  String get name => 'read_question';

  @override
  String get description => '读题库里一道题的完整内容：给 `question_id` 或题号 `serial`'
      '（如 TR-00042 / 42），返回完整题干、选项、答案、解析、知识点、最新一条解题链的'
      '能力动作、题干配图数与答案/解析截图数。用在你需要讲清 / 拆解一道**用户库里已有的题**的时候'
      '（例如用户问「帮我讲讲这道题」）。**只读**：不写库、不生成题干、不猜题——'
      '库里没有就如实说没有。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'question_id': {
            'type': 'string',
            'description': '题目 id（库里已有）。与 `serial` 二选一；两个都给时以它为准。',
          },
          'serial': {
            'type': 'string',
            'description': '题号：TR-00042 / tr-42 / 00042 / 42 都能读（题号只增不减）。',
          },
        },
        'required': <String>[],
      };

  /// 只读、无 action：与 `find_similar_questions` 同一中性组合（`write` + 可逆），
  /// 让 `ApprovalEngine` 在任何权限模式下都不逐条询问。
  @override
  ToolRisk riskFor(String action) => ToolRisk.write; // unused: no actions

  @override
  bool reversibleFor(String action) => true;

  @override
  bool get readOnly => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    try {
      final args = ToolArgs(invocation.arguments);
      final questionId = args.optString('question_id');
      final serialText = args.optString('serial');
      if (questionId == null && serialText == null) {
        throw ToolArgError(
          '缺少题目定位：给 `question_id`，或给题号 `serial`（如 TR-00042 / 42）',
        );
      }

      final serialNo =
          serialText == null ? null : tryParseQuestionSerial(serialText);
      if (questionId == null && serialNo == null) {
        throw ToolArgError(
          '读不出题号 `$serialText`：给 TR-00042、tr-42、00042 或 42 这类写法',
        );
      }

      final repository = QuestionRepository(_db);
      final Question? row = questionId != null
          ? await repository.byId(questionId)
          : await repository.findBySerialNo(serialNo!);
      if (row == null) {
        if (questionId != null) {
          return ToolResult.failure('题库里没有 id 为 `$questionId` 的题');
        }
        return ToolResult.failure(
          '题库里没有题号 ${formatQuestionSerial(serialNo!)} 的题'
          '（题号只增不减，删掉的题不会把号让出来）',
        );
      }

      final serialLabel = _serialLabelOf(row);
      final options = await repository.optionsOf(row.id);
      final corpus = await readPaperCorpus(_db);
      final pointIds = _pointIdsOf(corpus, row.id);
      final actionTypes =
          (await readChainActionTypes(_db))[row.id] ?? const <String>[];
      final actionLabels = <String>[
        for (final key in actionTypes)
          CapabilityAction.byKey(key)?.labelZh ?? key,
      ];
      final attachmentRows = await (_db.select(_db.attachments)
            ..where((t) =>
                t.ownerType.equals('question') & t.ownerId.equals(row.id)))
          .get();
      var stemImageCount = 0;
      var answerImageCount = 0;
      for (final attachment in attachmentRows) {
        if (_isStemQuestionImageRole(attachment.role)) {
          stemImageCount += 1;
        } else if (_isAnswerQuestionImageRole(attachment.role)) {
          answerImageCount += 1;
        }
      }

      // 整卡快照口径交给领域层（task-135）；这里只按题干图数量复算，
      // 不自己数「［图N］」占位。
      final stemSnapshot = summarizeQuestionStemSnapshot(
        stem: row.stem,
        stemImageCount: stemImageCount,
      );

      return ToolResult(
        ok: true,
        summary: _summaryOf(
          row: row,
          serialLabel: serialLabel,
          options: options,
          pointIds: pointIds,
          pointNames: corpus.knowledgePointNames,
          actionTypes: actionTypes,
          stemImageCount: stemImageCount,
          answerImageCount: answerImageCount,
          stemSnapshot: stemSnapshot,
        ),
        modelResult: {
          'rule': 'library_only',
          'id': row.id,
          'serial_no': row.serialNo,
          'serial_label': serialLabel,
          'stem': row.stem,
          'answer': row.answer,
          'solution': row.solution,
          'options': [
            for (final option in options)
              {
                'label': option.label,
                'content': option.content,
                'is_correct': option.isCorrect,
                'sort_order': option.sortOrder,
              },
          ],
          'subject_key': row.subjectKey,
          'subject': _subjectOf(row.subjectKey),
          'source_level': row.sourceLevel,
          'source_label': row.sourceLabel,
          'source_level_zh': _sourceLevelOf(row.sourceLevel),
          'year': row.year,
          'region': row.region,
          'difficulty': row.difficulty,
          'difficulty_source': row.difficultySource,
          'question_type': row.questionType,
          'state': row.state,
          'ai_quality': row.aiQuality,
          'trap_note': row.trapNote,
          'knowledge_point_ids': pointIds,
          'knowledge_points': [
            for (final id in pointIds)
              {'id': id, 'title': corpus.knowledgePointNames[id] ?? id},
          ],
          'action_types': actionTypes,
          'action_labels_zh': actionLabels,
          'image_count': stemImageCount,
          'answer_image_count': answerImageCount,
          'stem_is_snapshot': stemSnapshot.isSnapshot,
          'stem_snapshot_label': stemSnapshot.labelZh,
        },
      );
    } on ToolArgError catch (e) {
      // 模型给错了参数：变成它能读、能改的结果，而不是异常。
      return ToolResult.failure(e.message);
    }
  }

  String _serialLabelOf(Question question) {
    final serialNo = question.serialNo;
    if (serialNo == null || serialNo < 1) {
      return kUnnumberedQuestionLabel;
    }
    return formatQuestionSerial(serialNo);
  }

  /// 题目覆盖的知识点：与组卷/详情页同一口径（题目和知识点挂同一个标签）。
  List<String> _pointIdsOf(PaperCorpus corpus, String questionId) {
    for (final candidate in corpus.candidates) {
      if (candidate.questionId == questionId) {
        return candidate.matchedKnowledgePointIds;
      }
    }
    return const <String>[];
  }

  String _summaryOf({
    required Question row,
    required String serialLabel,
    required List<QuestionOption> options,
    required List<String> pointIds,
    required Map<String, String> pointNames,
    required List<String> actionTypes,
    required int stemImageCount,
    required int answerImageCount,
    required QuestionSnapshotSummary stemSnapshot,
  }) {
    final subject = _subjectOf(row.subjectKey);
    final source = _sourceLevelOf(row.sourceLevel);
    final meta = [
      if (subject.isNotEmpty) subject,
      if (source.isNotEmpty) source,
    ].join(' · ');
    final stem = previewStem(row.stem);
    final answer = _oneLine(row.answer);
    final solutionLength = _oneLine(row.solution).length;
    final parts = <String>[
      options.isEmpty ? '没存选项' : '${options.length} 个选项',
      answer.isEmpty ? '库里没存答案' : '答案 $answer',
      solutionLength == 0 ? '没存解析' : '解析 $solutionLength 字',
      pointIds.isEmpty
          ? '没挂知识点'
          : '知识点 ${pointIds.length} 个（${_namesOf(pointIds, pointNames)}）',
      if (actionTypes.isNotEmpty) '最新解题链动作 ${actionTypes.length} 个',
      if (stemImageCount > 0) '配图 $stemImageCount 张',
      if (answerImageCount > 0) '答案/解析截图 $answerImageCount 张',
    ];
    final head = meta.isEmpty ? serialLabel : '$serialLabel（$meta）';
    return '$head：$stem。${parts.join('，')}${_snapshotClauseOf(stemSnapshot)}。'
        '这些是题库里已有的题，我不会自己出题。';
  }

  String _namesOf(List<String> ids, Map<String, String> names) {
    final labels = [for (final id in ids) names[id] ?? id];
    if (labels.length <= 3) {
      return labels.join('、');
    }
    return '${labels.take(3).join('、')} 等 ${labels.length} 个';
  }

  String _oneLine(String? text) {
    final compact = (text ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.length <= 80) {
      return compact;
    }
    return '${compact.substring(0, 80)}…';
  }

  String _subjectOf(String subjectKey) {
    if (subjectKey.trim().isEmpty) {
      return '';
    }
    return CapabilityAction.subjectLabelsZh[subjectKey] ?? subjectKey;
  }

  String _sourceLevelOf(String key) => switch (key.trim()) {
        'gaokao' => '高考真题',
        'provincial_diagnostic' => '省市诊断',
        'elite_school' => '名校测试',
        'school' => '校内题',
        'personal' => '自建题',
        'unknown' => '',
        _ => key.trim(),
      };
}

/// 批量读题（轮次一百三十）：用户把"整卷题号"贴进来时，一次核对/读出这一批。
///
/// 为什么需要它：`read_question` 一次只读一道题。用户说"这套卷子 1..20 我录了
/// 几道、缺哪几道"或"把 3、5 到 9 号找出来讲讲"时，逐号调用既慢又把对话塞满。
/// 这个工具复用 `domain/services/questions/question_serial_batch.dart` 的题号/
/// 区间解析，把清单变成一组**摘要**：哪些号在库、哪些号缺、每道题的学科/来源/
/// 题干摘要/有没有答案/解析/选项/题干配图与答案/解析截图数。
///
/// 刻意只给摘要、不给完整题干：讲题请用 `read_question`。这样一次读 200 道也
/// 不会撑爆上下文。AI 不出题：清单里的号在库里没有就如实报缺，绝不补写题干。
///
/// 每条 item 都带 `stem_is_snapshot` / `stem_snapshot_label`（口径同
/// `read_question`，按每条自己的题干图数量）；摘要里补「其中 K 道题题干是整题截图」。
class ReadQuestionsBySerialsTool extends AiTool {
  ReadQuestionsBySerialsTool({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  /// 一次最多读多少道（默认与硬上限）。超出的号由解析器截断并记 `truncated`。
  static const int defaultMaxCount = 50;
  static const int hardMaxCount = 200;

  @override
  String get name => 'read_questions_by_serials';

  @override
  String get description => '按一份题号清单批量读题库里已有的题：`serials` 支持逗号/顿号/'
      '空白分隔、区间（`1..20`、`3-9`）、`TR-00042` / `42` 两种写法。返回每个号在不在库，'
      '以及每道题的题号、学科、来源、题干摘要、有没有答案/解析、选项数、'
      '题干配图数与答案/解析截图数。'
      '用在用户贴出一整卷题号（如「1..20 里我录了几道」「5 到 9 号都找出来」）时。'
      '**只读**：不写库、不出题——库里没有的号如实报缺，绝不生成题干。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'serials': {
            'type': 'string',
            'description': '题号清单，例如 `1..20`、`TR-00001, 3, 5-8`；逗号/顿号/空白分隔，'
                '区间用 `..` 或 `-`。',
          },
          'max_count': {
            'type': 'integer',
            'description': '最多读多少道（默认 $defaultMaxCount，上限 $hardMaxCount）。',
          },
        },
        'required': <String>['serials'],
      };

  /// 只读、无 action：与 `read_question` 同一中性组合（`write` + 可逆），
  /// 让 `ApprovalEngine` 在任何权限模式下都不逐条询问。
  @override
  ToolRisk riskFor(String action) => ToolRisk.write; // unused: no actions

  @override
  bool reversibleFor(String action) => true;

  @override
  bool get readOnly => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    try {
      final args = ToolArgs(invocation.arguments);
      final serialsText = args.optString('serials');
      if (serialsText == null) {
        throw ToolArgError(
          '缺少题号清单：给 `serials`，例如 `1..20` 或 `TR-00001, 3, 5-8`',
        );
      }
      final requestedMax = args.optInt('max_count') ?? defaultMaxCount;
      final maxCount = requestedMax <= 0
          ? defaultMaxCount
          : (requestedMax < hardMaxCount ? requestedMax : hardMaxCount);

      final batch = parseQuestionSerialBatch(serialsText, maxCount: maxCount);
      if (batch.serials.isEmpty) {
        final rejected = batch.rejectedSegments;
        throw ToolArgError(
          rejected.isEmpty
              ? '读不出题号清单 `$serialsText`：给 `1..20`、`TR-00001, 3, 5-8` 这类写法'
                  '（逗号/顿号/空白分隔，区间用 `..` 或 `-`）'
              : '清单里没有可用的题号（${_labelsOf(rejected)} 没认出来）：'
                  '给 `1..20`、`TR-00001, 3, 5-8` 这类写法',
        );
      }

      final repository = QuestionRepository(_db);
      final rows = await repository.search(
        serialNos: batch.serials.toSet(),
        limit: batch.serials.length,
      );
      // 题号跨设备 append 导入可能撞号（docs/QUESTION_BANK_DESIGN.md §11.1）：
      // 一个号对应多条时按 search 的价值序取第一条，不在这里报错。
      final bySerial = <int, Question>{};
      for (final row in rows) {
        final serialNo = row.serialNo;
        if (serialNo != null) {
          bySerial.putIfAbsent(serialNo, () => row);
        }
      }

      final foundIds = [for (final row in bySerial.values) row.id];
      final optionCounts = <String, int>{};
      final stemImageCounts = <String, int>{};
      final answerImageCounts = <String, int>{};
      if (foundIds.isNotEmpty) {
        final optionRows = await (_db.select(_db.questionOptions)
              ..where((t) => t.questionId.isIn(foundIds)))
            .get();
        for (final row in optionRows) {
          optionCounts[row.questionId] =
              (optionCounts[row.questionId] ?? 0) + 1;
        }
        final attachmentRows = await (_db.select(_db.attachments)
              ..where((t) =>
                  t.ownerType.equals('question') & t.ownerId.isIn(foundIds)))
            .get();
        for (final row in attachmentRows) {
          if (_isStemQuestionImageRole(row.role)) {
            stemImageCounts[row.ownerId] =
                (stemImageCounts[row.ownerId] ?? 0) + 1;
          } else if (_isAnswerQuestionImageRole(row.role)) {
            answerImageCounts[row.ownerId] =
                (answerImageCounts[row.ownerId] ?? 0) + 1;
          }
        }
      }

      final questions = <Map<String, Object?>>[];
      final missing = <String>[];
      var snapshotCount = 0;
      for (final serial in batch.serials) {
        final row = bySerial[serial];
        if (row == null) {
          missing.add(formatQuestionSerial(serial));
          continue;
        }
        final stemImageCount = stemImageCounts[row.id] ?? 0;
        final stemSnapshot = summarizeQuestionStemSnapshot(
          stem: row.stem,
          stemImageCount: stemImageCount,
        );
        if (stemSnapshot.isSnapshot) {
          snapshotCount += 1;
        }
        questions.add({
          'serial_no': serial,
          'serial_label': formatQuestionSerial(serial),
          'id': row.id,
          'subject_key': row.subjectKey,
          'subject': _subjectOf(row.subjectKey),
          'source_level': row.sourceLevel,
          'source_level_zh': _sourceLevelOf(row.sourceLevel),
          'source_label': row.sourceLabel,
          'year': row.year,
          'region': row.region,
          'stem_preview': previewStem(row.stem),
          'has_answer': _hasText(row.answer),
          'has_solution': _hasText(row.solution),
          'option_count': optionCounts[row.id] ?? 0,
          'image_count': stemImageCount,
          'answer_image_count': answerImageCounts[row.id] ?? 0,
          'stem_is_snapshot': stemSnapshot.isSnapshot,
          'stem_snapshot_label': stemSnapshot.labelZh,
        });
      }

      return ToolResult(
        ok: true,
        summary: _summaryOf(
          batch: batch,
          foundCount: questions.length,
          missing: missing,
          snapshotCount: snapshotCount,
        ),
        modelResult: {
          'rule': 'library_only',
          'requested_count': batch.count,
          'found_count': questions.length,
          'missing_count': missing.length,
          'truncated': batch.truncated,
          'rejected_segments': batch.rejectedSegments,
          'questions': questions,
          'missing': missing,
        },
      );
    } on ToolArgError catch (e) {
      // 模型给错了参数：变成它能读、能改的结果，而不是异常。
      return ToolResult.failure(e.message);
    }
  }

  String _summaryOf({
    required QuestionSerialBatch batch,
    required int foundCount,
    required List<String> missing,
    required int snapshotCount,
  }) {
    final missingCount = missing.length;
    final parts = <String>[
      '要 ${batch.count} 道题号',
      if (foundCount == 0) '库里一道都没有' else '找到 $foundCount 道',
      if (missingCount > 0) '缺 $missingCount 道（${_labelsOf(missing)}）',
      if (batch.truncated) '题号太多，只读了前 ${batch.count} 个',
      if (batch.rejectedSegments.isNotEmpty)
        '有 ${batch.rejectedSegments.length} 段没认出来'
            '（${_labelsOf(batch.rejectedSegments)}）',
    ];
    final snapshotNote =
        snapshotCount > 0 ? '其中 $snapshotCount 道题题干是整题截图。' : '';
    return '${parts.join('，')}。$snapshotNote'
        '这些是题库里已有的题，我不会自己出题。';
  }

  String _labelsOf(List<String> labels) {
    if (labels.length <= 6) {
      return labels.join('、');
    }
    return '${labels.take(6).join('、')} 等';
  }

  bool _hasText(String? text) => (text ?? '').trim().isNotEmpty;

  String _subjectOf(String subjectKey) {
    final key = subjectKey.trim();
    if (key.isEmpty) {
      return '';
    }
    return CapabilityAction.subjectLabelsZh[key] ?? key;
  }

  String _sourceLevelOf(String key) => switch (key.trim()) {
        'gaokao' => '高考真题',
        'provincial_diagnostic' => '省市诊断',
        'elite_school' => '名校测试',
        'school' => '校内题',
        'personal' => '自建题',
        'unknown' => '',
        _ => key.trim(),
      };
}

/// 题干摘要：只给模型/用户"认得出是哪道题"的量，空题干也明确说出来（不冒充有题）。
String previewStem(String? stem) {
  final text = (stem ?? '').trim();
  if (text.isEmpty) {
    return '(题干为空)';
  }
  if (text.length <= FindSimilarQuestionsTool.stemPreviewLength) {
    return text;
  }
  return '${text.substring(0, FindSimilarQuestionsTool.stemPreviewLength)}…';
}
