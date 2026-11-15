/// 组卷能力（Q9/Q11）接进 AI 工具层。
///
/// 用户口径：**AI 不凭空出题**（用户拍照/粘贴的题由 `create_questions` 工具誊写进
/// 题库）。所以这个工具只做一件事：把"想练什么"变成一次 `PaperComposer.compose(...)`
/// 调用，从**已有题库**里按薄弱/危险区知识点凑题，并把"为什么是这道、缺哪些知识点"
/// 如实报出来。凑不齐就说缺什么、请用户把题目拍照/粘贴发给 agent 誊写进库，
/// 绝不用模型生成一道题来填空。
///
/// 为什么它敢和组卷页给出同一份卷子：诊断读数以前只活在页面的 Riverpod provider 里，
/// 工具拿不到（Q13 之前 `compose_paper` 一直没做，正是这个原因——硬做而不喂读数，
/// `uncoveredKnowledgePointIds` 永远是空的，"没跑"就被当成"健康"，属于用工具撒谎）。
/// 现在读表与诊断都在 `cognitive/application/library_diagnosis_reader.dart` +
/// `questions/application/question_corpus_reader.dart`，页面与工具调**同一份函数**：
/// 同一个库、同一个模型、同一个时钟 → 同一份结论（D2）。
library;

import '../../../data/database/database.dart';
import '../../../data/repositories/question_repository.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/paper/domain_quota.dart';
import '../../../domain/services/paper/paper_composer.dart';
import '../../../domain/services/paper/paper_quality_report.dart';
import '../../../domain/services/paper/subject_quota.dart';
import '../../../domain/services/reasoning/capability_action.dart';
import '../../../domain/services/reasoning/capability_profile.dart';
import '../../../domain/services/scheduling/thread_windows.dart';
import '../../../domain/services/thread/paper_task_materializer.dart';
import '../../../domain/services/thread/thread_node_kind.dart';
import '../../cognitive/application/library_diagnosis_reader.dart';
import '../../questions/application/paper_plan_builder.dart';
import '../../questions/application/question_corpus_reader.dart';
import '../domain/ai_tool.dart';

/// 按薄弱/危险区知识点，从已有题库里凑一份卷子（AI 不凭空出题）。
class ComposePaperTool extends AiTool {
  ComposePaperTool({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  /// 一次练习默认要几道题。
  static const int defaultTargetCount = 10;

  /// 上限：再多也不是"一份练习"，而是把题库倒出来。
  static const int maxTargetCount = 50;

  @override
  String get name => 'compose_paper';

  @override
  String get description => '按**薄弱/危险区知识点**从用户已有的题库里凑一份练习卷：'
      '每题都带"为什么是它"（危险/发展区读数 + 来源质量 + 难度贴合）与下一步提升建议；'
      '凑不齐时如实列出"缺哪些知识点"（`uncovered_knowledge_point_ids`），并提示用户把题目'
      '拍照/粘贴发给 agent 誊写进题库。'
      '用在你需要"现在该练什么"的时候。**只读**：不写数据、不生成题干、不落库——'
      '它只从库里挑已有的题，挑不出来就说挑不出来，绝不自己编一道题填空。'
      '这不是随机抽题：它按诊断读数排序，并受学科/领域/来源/每知识点配额约束。'
      '默认还会参考"我最该练的动作"（能力动作画像，未标定，可用 '
      '`use_capability_profile: false` 关掉）。'
      '`model_result.quality` 是这份卷子的质量体检（17 条确定性判据：题数/学科集中/'
      '来源单一/难度过平或偏离/知识点缺口/zone 失衡/配额缺口等），'
      '摘要里会报最该看的一条——如实转述，不要自己"感觉"卷子好坏。'
      '本工具**永远只读、不落库**；要把这份卷子真的排进 ThreadFlow'
      '（生成本周/本日的任务树），用 `materialize_paper`。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'target_count': {
            'type': 'integer',
            'description': '想要几道题，默认 $defaultTargetCount（上限 $maxTargetCount）',
          },
          'subject_keys': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '只要这些学科（如 math / physics）；不给 = 不限。',
          },
          'min_source_level': {
            'type': 'string',
            'description': '来源分级下限（含）：gaokao > provincial_diagnostic > '
                'elite_school > school > personal > unknown；不给 = 不限。',
          },
          'per_knowledge_point_cap': {
            'type': 'integer',
            'description': '每个知识点最多几道；不给 = 由组卷器按候选分布自动算。',
          },
          'target_difficulty': {
            'type': 'number',
            'description': '目标难度 1..10；不给 = 难度分量取中性（不惩罚"不知道"）。',
          },
          'use_capability_profile': {
            'type': 'boolean',
            'description': '可选：组卷时要不要参考"我最该练的动作"（能力动作画像，'
                '**未标定**的先验；命中只把题往前排一点，不做过滤）。默认 true；'
                '给 false 就完全不参考，卷子与没有画像时一致。',
          },
          'subject_quota': {
            'type': 'object',
            'description': '可选：按学科配额。学科键 -> {max, min}，整数且 >= 0；'
                'max = 该科最多几道（max=0 表示这一科一道都不取），min = 至少几道'
                '（题库不够时如实报缺口）。没列出的学科不限；不给 = 不启用配额。'
                'min > max 时保底优先。',
            'additionalProperties': {
              'type': 'object',
              'properties': {
                'max': {'type': 'integer', 'minimum': 0},
                'min': {'type': 'integer', 'minimum': 0},
              },
              'required': <String>[],
            },
          },
          // 领域键是标签路径的第一段（完整 `Tags.path`，如 `物理/力学` 的
          // 领域是 `物理`）。与 subject_quota 分开传：同一道题可以同时受两个
          // 配额约束（学科上限先行，领域配额在填充/保底阶段判定）。
          'domain_quota': {
            'type': 'object',
            'description': '可选：按领域配额（领域 = 知识标签路径的第一段，'
                '如 `物理/力学` 属于 `物理`）。领域键 -> {max, min}，整数且 >= 0；'
                'max = 该领域最多几道（max=0 表示这一领域一道都不取），min = 至少'
                '几道（题库不够时如实报缺口）。没列出的领域不限；不给 = 不启用配额。'
                'min > max 时保底优先。',
            'additionalProperties': {
              'type': 'object',
              'properties': {
                'max': {'type': 'integer', 'minimum': 0},
                'min': {'type': 'integer', 'minimum': 0},
              },
              'required': <String>[],
            },
          },
          // 手工指定/排除：放的是题目 id（questions.id），不是题号——题号给人看，
          // 工具层让模型先查题拿到 id 再传进来。排除优先于入选；入选在保底与填充
          // 之前强制进卷，只受 target_count 硬上限。
          'manual_include_question_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '可选：必须收进卷子的题目 id 列表。会绕过学科/来源/难度过滤与'
                '知识点/学科/领域上限，但仍受 target_count 限制；装不下或被挤掉的会'
                '在结果里如实报。不给 = 不启用。',
          },
          'manual_exclude_question_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '可选：绝对不要收进卷子的题目 id 列表（优先级最高，任何阶段'
                '都不会选；与入选名单冲突时按排除处理并如实报）。不给 = 不启用。',
          },
        },
        'required': <String>[],
      };

  /// 只读、无 action：`riskFor` 用中性 `write` + `reversibleFor` true，正是这个组合
  /// 让 `ApprovalEngine` 在两种权限模式下都不会逐条询问它（同 `find_similar_questions`）。
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
      final composed = await _compose(args);
      return ToolResult(
        ok: true,
        summary: _summaryOf(
          plan: composed.plan,
          corpus: composed.corpus,
          quality: composed.quality,
          diagnosisRan: composed.diagnosisRan,
        ),
        modelResult: _modelResultOf(composed),
      );
    } on ToolArgError catch (error) {
      return ToolResult.failure(error.message);
    }
  }

  /// 组卷的共同前半段：读题库/诊断/画像 → `PaperPlan` + 质量体检。
  ///
  /// `compose_paper`（只读）与 `materialize_paper`（落库）都调这一个方法，所以
  /// "同一份库、同一份诊断 → 同一份卷子"这条约束不会因为多一个工具而破。
  Future<_ComposedPaper> _compose(ToolArgs args) async {
    final spec = _specOf(args);
    final useCapabilityProfile = args.optBool('use_capability_profile') ?? true;

    final corpus = await readPaperCorpus(_db);
    // 诊断与页面同源：模型用默认的 `MindNetCognitiveModel`（与 `ToolRegistry.forApp`
    // 的默认值一致），时间用"现在"。页面注入了自定义模型时两边可能不同，这是
    // 有意的——工具没有 `Ref`，只能用默认模型；`model_result.diagnosis_ran` 会
    // 如实说明这轮到底有没有结论。
    final diagnosis = await readLibraryDiagnosis(
      _db,
      model: const MindNetCognitiveModel(),
    );

    // 与页面同源：能力动作画像（推理层读数）。装配本身在
    // `questions/application/paper_plan_builder.dart` —— 页面与工具调同一个函数，
    // 同一份库两边挑出来的卷子一致（D2：一个数字一个来源）。
    final capabilitySteps = await QuestionRepository(_db).allReasoningSteps();
    final profile = CapabilityProfile.of(<CapabilityStepSample>[
      for (final step in capabilitySteps)
        CapabilityStepSample(
          actionType: step.actionType,
          stuckRisk: step.stuckRisk,
        ),
    ]);
    final preferredActions = useCapabilityProfile
        ? preferredActionTypesOf(profile)
        : const <String>[];

    final build = await buildPaperPlan(
      db: _db,
      corpus: corpus,
      spec: spec,
      diagnosis: diagnosis,
      preferredActionTypes: preferredActions,
    );
    final plan = build.plan;

    // 质量体检跟着卷子一起给模型看：判据在 domain 层（纯逻辑），这里只把题库候选
    // 上已有的逐题难度带过去（`PaperPlan` 不保留难度；NaN/±inf 当没有读数）。
    final quality = PaperQualityReport.build(
      plan: plan,
      subjectNames: CapabilityAction.subjectLabelsZh,
      knowledgePointNames: corpus.knowledgePointNames,
      difficultyByQuestionId: <String, double>{
        for (final candidate in corpus.candidates)
          if (candidate.difficulty != null && candidate.difficulty!.isFinite)
            candidate.questionId: candidate.difficulty!,
      },
      targetDifficulty: spec.targetDifficulty,
    );

    return _ComposedPaper(
      plan: plan,
      corpus: corpus,
      quality: quality,
      build: build,
      preferredActions: preferredActions,
      diagnosisRan: diagnosis.fastLayerRan,
    );
  }

  /// 模型看到的组卷结果（逐题理由 / 质量体检 / 缺口 / 配额回报）。
  Map<String, Object?> _modelResultOf(_ComposedPaper composed) {
    final plan = composed.plan;
    final corpus = composed.corpus;
    final quality = composed.quality;
    return {
      'requested_count': plan.requestedCount,
      'item_count': plan.items.length,
      'is_short': plan.isShort,
      'candidate_count': plan.candidateCount,
      'bank_size': corpus.candidates.length,
      'overall_need': plan.overallNeed,
      'weights': plan.weights.toMap(),
      'diagnosis_ran': composed.diagnosisRan,
      'readings_used': composed.build.readingsUsed,
      'preferred_action_types': composed.preferredActions,
      'capability_profile_used': composed.preferredActions.isNotEmpty,
      if (plan.subjectQuota != null) 'by_subject': plan.bySubject,
      if (plan.subjectQuota != null)
        'quota_blocked_questions': [
          for (final blocked in plan.quotaBlockedQuestions) blocked.toJson(),
        ],
      if (plan.subjectQuota != null)
        'subject_shortfalls': [
          for (final shortfall in plan.subjectShortfalls) shortfall.toJson(),
        ],
      if (plan.subjectQuota != null)
        'subject_quota': plan.subjectQuota!.toJson(),
      if (plan.domainQuota != null) 'by_domain': plan.byDomain,
      if (plan.domainQuota != null)
        'quota_blocked_by_domain': [
          for (final blocked in plan.quotaBlockedByDomain) blocked.toJson(),
        ],
      if (plan.domainQuota != null)
        'domain_shortfalls': [
          for (final shortfall in plan.domainShortfalls) shortfall.toJson(),
        ],
      if (plan.domainQuota != null) 'domain_quota': plan.domainQuota!.toJson(),
      if (plan.manualSelectionEnabled) ...{
        'manual_included_count': plan.manualIncludedCount,
        'manual_missing_question_ids': plan.manualMissingQuestionIds,
        'manual_skipped_question_ids': plan.manualSkippedQuestionIds,
        'manual_conflict_question_ids': plan.manualConflictQuestionIds,
      },
      'uncovered_knowledge_point_ids': plan.uncoveredKnowledgePointIds,
      'uncovered_knowledge_points': [
        for (final id in plan.uncoveredKnowledgePointIds)
          {
            'knowledge_point_id': id,
            'knowledge_point_name': corpus.knowledgePointNames[id] ?? '',
          },
      ],
      'deferred_knowledge_point_ids': plan.deferredKnowledgePointIds,
      'by_knowledge_point': plan.byKnowledgePoint,
      'quality': quality.toJson(),
      'items': [
        for (final item in plan.items)
          {
            'question_id': item.questionId,
            'knowledge_point_id': item.knowledgePointId,
            'knowledge_point_name':
                corpus.knowledgePointNames[item.knowledgePointId] ?? '',
            'matched_knowledge_point_ids': item.matchedKnowledgePointIds,
            'subject_key': item.subjectKey,
            'source_level': item.sourceLevel,
            'question_type': item.questionType,
            'zone': item.zone.name,
            'zone_zh': item.zone.labelZh,
            'need': item.need,
            'quality': item.quality,
            'score': item.score,
            'reason': item.reasonZh,
            'improvement_note': item.improvementNote,
            'background': item.backgroundZh,
            if (item.matchedPreferredActions.isNotEmpty)
              'matched_preferred_actions': item.matchedPreferredActions,
          },
      ],
    };
  }

  /// 入参 → `PaperSpec`。范围外的数字**钳**而不是静默丢弃，并让 `model_result`
  /// 里的 `requested_count` 说出实际生效的值。
  PaperSpec _specOf(ToolArgs args) {
    final rawTargetCount = args.optInt('target_count') ?? defaultTargetCount;
    final targetCount = rawTargetCount.clamp(1, maxTargetCount);

    final subjectKeys = <String>{
      for (final key in args.optStringList('subject_keys') ?? const <String>[])
        if (key.trim().isNotEmpty) key.trim(),
    };

    final rawMinSourceLevel = args.optString('min_source_level')?.trim();
    String? minSourceLevel;
    if (rawMinSourceLevel != null && rawMinSourceLevel.isNotEmpty) {
      if (!kSourceLevelPriority.containsKey(rawMinSourceLevel)) {
        throw ToolArgError(
          '不认识的来源分级 `$rawMinSourceLevel`；可用的有：'
          '${kSourceLevelPriority.keys.join(' / ')}',
        );
      }
      minSourceLevel = rawMinSourceLevel;
    }

    final rawCap = args.optInt('per_knowledge_point_cap');
    if (rawCap != null && rawCap < 1) {
      throw ToolArgError('`per_knowledge_point_cap` 至少是 1，收到 $rawCap');
    }

    final rawDifficulty = args.optDouble('target_difficulty');
    if (rawDifficulty != null &&
        (rawDifficulty.isNaN || rawDifficulty < 1 || rawDifficulty > 10)) {
      throw ToolArgError(
        '`target_difficulty` 必须在 1..10 之间，收到 $rawDifficulty',
      );
    }

    return PaperSpec(
      targetCount: targetCount,
      subjectKeys: subjectKeys,
      perKnowledgePointCap: rawCap,
      targetDifficulty: rawDifficulty,
      minSourceLevel: minSourceLevel,
      subjectQuota: _subjectQuotaOf(args),
      domainQuota: _domainQuotaOf(args),
      manualIncludeQuestionIds:
          _manualIdsOf(args, 'manual_include_question_ids'),
      manualExcludeQuestionIds:
          _manualIdsOf(args, 'manual_exclude_question_ids'),
    );
  }

  /// 解析可选的 `subject_quota` 对象。错形状给出可执行的报错（而不是静默当没给）。
  SubjectQuota? _subjectQuotaOf(ToolArgs args) {
    final raw = args.raw['subject_quota'];
    if (raw == null) return null;
    if (raw is! Map) {
      throw ToolArgError(
        '`subject_quota` 必须是对象：学科键 -> {max, min}；收到 ${raw.runtimeType}',
      );
    }
    final max = <String, int>{};
    final min = <String, int>{};
    final seenSubjects = <String>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString().trim();
      if (key.isEmpty) {
        throw ToolArgError('`subject_quota` 的学科键不能为空白');
      }
      if (!seenSubjects.add(key)) {
        throw ToolArgError('`subject_quota` 里有重复学科键 `$key`（trim 后是同一科）');
      }
      final value = entry.value;
      if (value is! Map) {
        throw ToolArgError(
          '`subject_quota.$key` 必须是对象 {max, min}；收到 ${value.runtimeType}',
        );
      }
      final seenFields = <String>{};
      for (final inner in value.entries) {
        final field = inner.key.toString().trim();
        if (field != 'max' && field != 'min') {
          throw ToolArgError(
            '`subject_quota.$key` 只认识 max / min，收到 `$field`',
          );
        }
        if (!seenFields.add(field)) {
          throw ToolArgError(
            '`subject_quota.$key` 里 `$field` 重复（trim 后同名）',
          );
        }
        final count = _quotaCount(inner.value, '`subject_quota.$key.$field`');
        if (field == 'max') {
          max[key] = count;
        } else {
          min[key] = count;
        }
      }
    }
    if (max.isEmpty && min.isEmpty) return null;
    final quota = SubjectQuota(maxPerSubject: max, minPerSubject: min);
    try {
      quota.resolve();
    } on ArgumentError catch (error) {
      throw ToolArgError('`subject_quota` 配置无效：${error.message}');
    }
    return quota;
  }

  /// 解析可选的 `domain_quota` 对象。错形状给出可执行的报错（而不是静默当没给）。
  ///
  /// 领域键 = 完整标签路径的第一段（`物理/力学` → `物理`）；与 `subject_quota`
  /// 相同，空对象视同不启用（返回 null，而不是一个什么都不限的空壳）。
  DomainQuota? _domainQuotaOf(ToolArgs args) {
    final raw = args.raw['domain_quota'];
    if (raw == null) return null;
    if (raw is! Map) {
      throw ToolArgError(
        '`domain_quota` 必须是对象：领域键 -> {max, min}；收到 ${raw.runtimeType}',
      );
    }
    final max = <String, int>{};
    final min = <String, int>{};
    final seenDomains = <String>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString().trim();
      if (key.isEmpty) {
        throw ToolArgError('`domain_quota` 的领域键不能为空白');
      }
      if (!seenDomains.add(key)) {
        throw ToolArgError('`domain_quota` 里有重复领域键 `$key`（trim 后是同一领域）');
      }
      final value = entry.value;
      if (value is! Map) {
        throw ToolArgError(
          '`domain_quota.$key` 必须是对象 {max, min}；收到 ${value.runtimeType}',
        );
      }
      final seenFields = <String>{};
      for (final inner in value.entries) {
        final field = inner.key.toString().trim();
        if (field != 'max' && field != 'min') {
          throw ToolArgError(
            '`domain_quota.$key` 只认识 max / min，收到 `$field`',
          );
        }
        if (!seenFields.add(field)) {
          throw ToolArgError(
            '`domain_quota.$key` 里 `$field` 重复（trim 后同名）',
          );
        }
        final count = _quotaCount(inner.value, '`domain_quota.$key.$field`');
        if (field == 'max') {
          max[key] = count;
        } else {
          min[key] = count;
        }
      }
    }
    if (max.isEmpty && min.isEmpty) return null;
    final quota = DomainQuota(maxPerDomain: max, minPerDomain: min);
    try {
      quota.resolve();
    } on ArgumentError catch (error) {
      throw ToolArgError('`domain_quota` 配置无效：${error.message}');
    }
    return quota;
  }

  int _quotaCount(Object? value, String label) {
    final int? parsed;
    if (value is int) {
      parsed = value;
    } else if (value is num) {
      parsed = value.toInt();
    } else {
      parsed = int.tryParse(value?.toString().trim() ?? '');
    }
    if (parsed == null || parsed < 0) {
      throw ToolArgError('$label 必须是非负整数，收到 `$value`');
    }
    return parsed;
  }

  /// 解析可选的题目 id 列表（手工指定/排除）。形状不对报错，不静默吞。
  ///
  /// 空数组按"不启用"处理（null），避免库里出现"启用了但什么都不做"的空壳。
  Set<String>? _manualIdsOf(ToolArgs args, String key) {
    final raw = args.raw[key];
    if (raw == null) return null;
    if (raw is! List) {
      throw ToolArgError(
        '$key 必须是题目 id 的数组；收到 ${raw.runtimeType}',
      );
    }
    final ids = <String>{};
    for (final item in raw) {
      if (item is! String) {
        throw ToolArgError(
          '$key 里的元素必须是字符串题目 id，收到 ${item.runtimeType}',
        );
      }
      final id = item.trim();
      if (id.isEmpty) {
        throw ToolArgError('$key 里不能有空字符串');
      }
      ids.add(id);
    }
    return ids.isEmpty ? null : ids;
  }

  /// 摘要说人话：凑了几道、哪几道是为了哪个知识点、缺什么、以及"我不凭空出题"＋
  /// 补充途径（拍照/粘贴发给 agent 誊写进库）。
  String _summaryOf({
    required PaperPlan plan,
    required PaperCorpus corpus,
    required PaperQualityReport quality,
    required bool diagnosisRan,
  }) {
    final buffer = StringBuffer();
    if (corpus.candidates.isEmpty) {
      buffer.write(
        '题库里还没有任何可用的题（题干为空的题不算），所以凑不出卷子。'
        '我不凭空出题；把题目拍照或粘贴发给我，我誊写进题库，再让我组卷。',
      );
      return buffer.toString();
    }

    if (plan.items.isEmpty) {
      buffer.write(
        '题库里有 ${corpus.candidates.length} 道题，但按当前条件'
        '（学科/领域/来源/难度/配额）一道都排不出来。',
      );
    } else {
      buffer.write(
        '从 ${corpus.candidates.length} 道候选里凑出 ${plan.items.length} 道'
        '（想要 ${plan.requestedCount} 道）',
      );
      final named = plan.items.take(3).toList();
      if (named.isNotEmpty) {
        buffer.write('：');
        buffer.write(
          named
              .map(
                (item) =>
                    '「${corpus.knowledgePointNames[item.knowledgePointId] ?? '未标知识点'}」'
                    '${item.zone.labelZh}',
              )
              .join('、'),
        );
        if (plan.items.length > named.length) {
          buffer.write(' 等');
        }
      }
      buffer.write('。每题都带理由行与提升建议，请照 `reason` / `improvement_note` 转述。');
    }

    if (plan.isShort) {
      buffer.write(
        ' 没凑够：还差 ${plan.requestedCount - plan.items.length} 道——题库里够条件的题不够。',
      );
    }
    if (plan.uncoveredKnowledgePointIds.isNotEmpty) {
      final names = [
        for (final id in plan.uncoveredKnowledgePointIds.take(5))
          corpus.knowledgePointNames[id] ?? id,
      ];
      buffer.write(
        ' 这些知识点诊断上是危险/发展区，但题库里一道候选都没有：'
        '${names.join('、')}'
        '${plan.uncoveredKnowledgePointIds.length > names.length ? ' 等' : ''}'
        '——建议把题目拍照或粘贴发给我誊写进题库，再让我组卷。',
      );
    }
    if (plan.deferredKnowledgePointIds.isNotEmpty) {
      buffer.write(
        ' 另有 ${plan.deferredKnowledgePointIds.length} 个知识点有候选但这轮没排进来'
        '（数量/配额限制），想练它们就把 `target_count` 调大或提高 '
        '`per_knowledge_point_cap`。',
      );
    }
    final quota = plan.subjectQuota;
    if (quota != null && quota.isEnabled) {
      final bySubject = plan.bySubject.entries.toList()
        ..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          return byCount != 0 ? byCount : a.key.compareTo(b.key);
        });
      if (bySubject.isNotEmpty) {
        buffer.write(
          ' 学科分布：${bySubject.map((e) => '${e.key} ${e.value} 道').join('、')}。',
        );
      }
      if (plan.quotaBlockedQuestions.isNotEmpty) {
        buffer.write(
          ' 另有 ${plan.quotaBlockedQuestions.length} 道本来能进卷的题被学科上限挡下'
          '（提高对应学科的 max 或 `target_count` 才能看到它们）。',
        );
      }
      if (plan.subjectShortfalls.isNotEmpty) {
        final short = [
          for (final shortfall in plan.subjectShortfalls.take(5))
            '${shortfall.subjectKey} 差 '
                '${shortfall.minimumCount - shortfall.selectedCount} 道'
                '（${shortfall.isUncovered ? '题库里这一科没有可用题' : '可用候选 ${shortfall.availableCount} 道'}）',
        ];
        buffer.write(' 学科保底没凑够：${short.join('、')}。');
      }
    }
    final domainQuota = plan.domainQuota;
    if (domainQuota != null) {
      final byDomain = plan.byDomain.entries.toList()
        ..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          return byCount != 0 ? byCount : a.key.compareTo(b.key);
        });
      if (byDomain.isNotEmpty) {
        buffer.write(
          ' 领域分布：${byDomain.map((e) => '${e.key} ${e.value} 道').join('、')}。',
        );
      }
      if (plan.quotaBlockedByDomain.isNotEmpty) {
        buffer.write(
          ' 另有 ${plan.quotaBlockedByDomain.length} 道本来能进卷的题被领域上限挡下'
          '（提高对应领域的 max 或 `target_count` 才能看到它们）。',
        );
      }
      if (plan.domainShortfalls.isNotEmpty) {
        final short = [
          for (final shortfall in plan.domainShortfalls.take(5))
            '${shortfall.domain} 差 '
                '${shortfall.minimumCount - shortfall.selectedCount} 道'
                '（${shortfall.isUncovered ? '题库里这一领域没有可用题' : '可用候选 ${shortfall.availableCount} 道'}）',
        ];
        buffer.write(' 领域保底没凑够：${short.join('、')}。');
      }
    }
    if (plan.manualSelectionEnabled) {
      buffer.write(' 手工指定：入选 ${plan.manualIncludedCount} 道');
      if (plan.manualMissingQuestionIds.isNotEmpty) {
        buffer.write(
          '；有 ${plan.manualMissingQuestionIds.length} 道指定必收的题在候选池里'
          '找不到（可能学科/来源不符合条件，或题被删了）',
        );
      }
      if (plan.manualSkippedQuestionIds.isNotEmpty) {
        buffer.write(
          '；有 ${plan.manualSkippedQuestionIds.length} 道因为 target_count '
          '装不下，这轮没进卷',
        );
      }
      if (plan.manualConflictQuestionIds.isNotEmpty) {
        buffer.write(
          '；有 ${plan.manualConflictQuestionIds.length} 道同时被指定入选和排除，'
          '按排除处理了',
        );
      }
      buffer.write('。');
    }
    _writeQuality(buffer, quality);
    if (!diagnosisRan) {
      buffer.write(
        ' 注意：认知快层这轮没有跑出结论（没有标签或没有卡片观测），'
        '所以所有知识点都按"没有读数"处理——**不是**"健康"。',
      );
    }
    return buffer.toString();
  }

  /// 质量体检说人话：三档计数 + 最该看的一条（不是让模型自己"感觉"卷子好坏）。
  void _writeQuality(StringBuffer buffer, PaperQualityReport quality) {
    if (quality.warnings.isEmpty) {
      buffer.write(' 质量体检：没有命中任何判据。');
      return;
    }
    final counts = quality.countsBySeverity;
    buffer.write(
      ' 质量体检：错误 ${counts[PaperQualitySeverity.error]} 条、'
      '警告 ${counts[PaperQualitySeverity.warning]} 条、'
      '提示 ${counts[PaperQualitySeverity.info]} 条',
    );
    final top = quality.warnings.first;
    buffer.write('；最该看：${top.messageZh}');
    if (quality.warnings.length > 1) {
      buffer
          .write('（另有 ${quality.warnings.length - 1} 条，见 `quality.warnings`）');
    }
    buffer.write('。');
  }
}

/// 一次组卷的共同结果（`compose_paper` / `materialize_paper` 共享）。
class _ComposedPaper {
  const _ComposedPaper({
    required this.plan,
    required this.corpus,
    required this.quality,
    required this.build,
    required this.preferredActions,
    required this.diagnosisRan,
  });

  final PaperPlan plan;
  final PaperCorpus corpus;
  final PaperQualityReport quality;
  final PaperPlanBuild build;
  final List<String> preferredActions;
  final bool diagnosisRan;
}

/// 组卷并**落库**成 ThreadFlow 任务树（schema v47，2026-11-15）。
///
/// 与 `compose_paper` 的分工：那个工具只读、永远不写；这个工具是它唯一允许的
/// "写"路径——同一份组卷装配（[ComposePaperTool._compose]）之后调用
/// [PaperTaskMaterializer]，把卷子物化成「week/day 父容器 + 每题一个子任务」。
///
/// 三条硬约束：
///
///  1. **默认不改变只读路径**：`compose_paper` 的 `readOnly` 没动；想落库必须
///     显式调用本工具。把 `readOnly` 做成"按参数变"是不可能且危险的——
///     `ApprovalEngine` 与 `ToolRegistry.isReadOnly` 都是按工具粒度的。
///  2. **幂等**：容器键 = `paper:<week|day>:<窗口标签>:<paperKey>`，同一周/同一天
///     重复调用命中的是同一行，不新建第二个容器；要并存第二份卷子，显式传
///     `paper_key`（"明确新卷"）。
///  3. **不自动执行**：本工具**没有**可靠的撤销快照（撤销要连带删掉这次新建的
///     任务树），所以 `reversibleFor` 返回 false——按 D13b，两种权限模式下都必须
///     逐条确认；宁可多问一次，也不假装可撤销。
class MaterializePaperTool extends ComposePaperTool {
  MaterializePaperTool({required super.db, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// 稳定工具名（撤销/审计/测试都按它认）。
  static const String toolName = 'materialize_paper';

  final DateTime Function() _clock;

  @override
  String get name => toolName;

  @override
  String get description => '把一份组好的练习卷**落进 ThreadFlow**：按周/日创建父容器，每题创建一个子任务'
      '（带 expectedAt/dueAt/remindAt/精力，缺省不猜），并写 `created`/`planned` 事件。'
      '`compose_paper` 只给卷子、不写库；**只有用户确实要把这份卷子排进计划时**才调本工具。'
      '参数与 `compose_paper` 相同（target_count/subject_keys/来源/难度/配额/手工选排），'
      '另加：`container`（week 默认 / day / paper）、`paper_key`（可选；不传 = '
      '同一周/同一天只有一个容器，传了 = 明确的新卷）、`window_start`/`window_end`'
      '（默认本周一至下周一 / 今天至明天）、`remind_at`、`energy_required`、'
      '`minutes_per_item`、`container_title`。'
      '要锁定与刚才 `compose_paper` 完全相同的题，把那些 question_id 传进 '
      '`manual_include_question_ids`。'
      '它**只写任务节点**：不改题库、不生成题干、不写答案/解析。这道写操作不能自动撤销，'
      '需要用户确认。';

  @override
  Map<String, Object?> get parameters {
    final base = super.parameters;
    final baseProperties =
        (base['properties']! as Map<String, Object?>).cast<String, Object?>();
    return {
      'type': 'object',
      'properties': {
        ...baseProperties,
        'container': {
          'type': 'string',
          'enum': ['week', 'day', 'paper'],
          'description': '父容器种类，默认 week（本周）。day = 本日；paper = 不挂周/日的单卷。',
        },
        'paper_key': {
          'type': 'string',
          'description': '卷子身份（如 QSET-…）。不传 = 同一周/同一天复用同一个容器'
              '（重卷只补题、不建第二个容器）；传了就按它新建/复用另一份卷子。',
        },
        'container_title': {
          'type': 'string',
          'description':
              '父容器标题；不传按窗口生成（week：组卷 · yyyy-Www；day：组卷 · yyyy-MM-dd）。',
        },
        'window_start': {
          'type': 'string',
          'description': '计划窗口起点（ISO-8601 或毫秒）。week/day 的日期标签与子任务 '
              'expectedAt 都用它；不传 = 本周一 / 今天 00:00。',
        },
        'window_end': {
          'type': 'string',
          'description': '计划窗口终点 → 子任务与容器的 dueAt（硬截止）。'
              '不传 = 下周一 / 明天 00:00。',
        },
        'remind_at': {
          'type': 'string',
          'description': '提醒时刻（ISO-8601 或毫秒）；不传 = 不设提醒。',
        },
        'energy_required': {
          'type': 'integer',
          'description': '子任务所需精力 1-10；不传 = 不写（容器不写精力）。',
        },
        'minutes_per_item': {
          'type': 'integer',
          'description': '每题估时（分钟）；不传 = 不估时（父容器估时也随之 unknown）。',
        },
      },
      'required': <String>[],
    };
  }

  /// 写操作：`ToolRisk.write`（没有删除语义）。
  @override
  ToolRisk riskFor(String action) => ToolRisk.write;

  /// 不可撤销：撤销要连带删掉这次新建的任务树，本工具不产出可靠快照 ⇒ 必须逐条确认
  /// （`AI_DESIGN.md` D13b：不能可靠撤销的操作永不自动执行）。
  @override
  bool reversibleFor(String action) => false;

  /// 写工具，不是查询：结果要出现在对话里（`ToolRegistry.isReadOnly` 读这个）。
  @override
  bool get readOnly => false;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    try {
      final args = ToolArgs(invocation.arguments);
      final composed = await _compose(args);
      final plan = composed.plan;
      final kind = _containerKindOf(args);
      final now = _clock();
      final (windowStart, windowEnd) = _windowOf(args, kind, now);
      final paperKey = _paperKeyOf(args, kind, plan);
      final composeSummary = _summaryOf(
        plan: plan,
        corpus: composed.corpus,
        quality: composed.quality,
        diagnosisRan: composed.diagnosisRan,
      );
      final composePayload = _modelResultOf(composed);

      // 0 题的卷子不建空容器：那只会给 Thread 留一条永远做不完的壳。
      if (plan.items.isEmpty) {
        return ToolResult(
          ok: true,
          summary: '$composeSummary 这份卷子 0 题，没有落库（不建空容器）。',
          modelResult: {
            ...composePayload,
            'materialized': false,
            'materialized_reason': 'empty_plan',
            'paper_key': paperKey,
          },
        );
      }

      final tree = await PaperTaskMaterializer(_db).materialize(
        PaperMaterializeRequest(
          plan: plan,
          containerKind: kind,
          paperKey: paperKey,
          windowStart: windowStart,
          windowEnd: windowEnd,
          remindAt: _asDateTime(args.optEpochMs('remind_at')),
          energyRequired: args.optInt('energy_required'),
          minutesPerItem: args.optInt('minutes_per_item'),
          containerTitle: args.optString('container_title') ??
              _defaultContainerTitle(kind, windowStart),
          at: now,
        ),
      );

      final createdCount = tree.createdQuestionIds.length;
      final reusedCount = tree.items.length - createdCount;
      return ToolResult(
        ok: true,
        summary: '$composeSummary '
            '已写入 ThreadFlow：${tree.container.title}'
            '（${tree.items.length} 个子任务，'
            '${tree.createdContainer ? '新建' : '复用'}容器；'
            '本次新增 $createdCount 题'
            '${reusedCount > 0 ? '，$reusedCount 题已在计划里' : ''}）。',
        modelResult: {
          ...composePayload,
          'materialized': true,
          'container_kind': kind.id,
          'container_id': tree.container.id,
          'container_title': tree.container.title,
          'container_source_key': PaperTaskMaterializer.containerSourceKey(
            containerKind: kind,
            paperKey: paperKey,
            windowStart: windowStart,
          ),
          'paper_key': paperKey,
          // 卷子内容自己的指纹（题序无关）：想按"这份卷子"而不再按"这一周"建容器时，
          // 把这个值作为 paper_key 传回来即可。
          'question_set_key': PaperTaskMaterializer.paperKeyOf(plan),
          'created_container': tree.createdContainer,
          'created_question_ids': tree.createdQuestionIds,
          'child_task_ids': [for (final item in tree.items) item.id],
          'item_count': tree.items.length,
          'estimate_minutes': tree.estimateMinutes,
          'expected_at_ms': windowStart?.millisecondsSinceEpoch,
          'due_at_ms': windowEnd?.millisecondsSinceEpoch,
        },
      );
    } on ToolArgError catch (error) {
      return ToolResult.failure(error.message);
    } on ArgumentError catch (error) {
      // 物化器的输入校验（窗口颠倒、精力越界、kind 不支持…）：模型能读懂并重试。
      return ToolResult.failure('落库参数无效：${error.message ?? error}');
    } on StateError catch (error) {
      // `source_key` 已被别的 kind 占用之类的真实冲突：交给用户/下一轮修。
      return ToolResult.failure('落库失败：${error.message}');
    }
  }

  /// `container` → [ThreadNodeKind]（只接受 week/day/paper）。
  ThreadNodeKind _containerKindOf(ToolArgs args) {
    final raw = args.optString('container') ?? 'week';
    for (final kind in const [
      ThreadNodeKind.week,
      ThreadNodeKind.day,
      ThreadNodeKind.paper,
    ]) {
      if (kind.id == raw) {
        return kind;
      }
    }
    throw ToolArgError(
      '`container` 只支持 week / day / paper，收到 `$raw`',
    );
  }

  /// 默认窗口：week = 本周一至下周一；day = 今天至明天；paper = 不排窗口。
  ///
  /// 手工传了 `window_start` 时，终点缺省按同一个起点的自然窗口算（而不是"现在"
  /// 的窗口），否则用户指定下周一开做时终点会落在今天之后、窗口颠倒。
  (DateTime?, DateTime?) _windowOf(
    ToolArgs args,
    ThreadNodeKind kind,
    DateTime now,
  ) {
    final startMs = args.optEpochMs('window_start');
    final endMs = args.optEpochMs('window_end');
    if (kind == ThreadNodeKind.paper) {
      return (_asDateTime(startMs), _asDateTime(endMs));
    }
    final start = _asDateTime(startMs) ??
        switch (kind) {
          ThreadNodeKind.week => weekWindow(now).start,
          ThreadNodeKind.day => dayWindow(now).start,
          _ => weekWindow(now).start,
        };
    final naturalEnd = switch (kind) {
      ThreadNodeKind.week => weekWindow(start).end,
      ThreadNodeKind.day => dayWindow(start).end,
      _ => weekWindow(start).end,
    };
    return (start, _asDateTime(endMs) ?? naturalEnd);
  }

  /// 容器身份：
  ///
  ///  * 显式 `paper_key` → 原样使用（"明确新卷"）；
  ///  * week/day → 固定 `plan`：容器键里已经有周/日标签，所以同一周/同一天重卷
  ///    只会复用同一容器（B4）；
  ///  * paper（不挂窗口）→ 题目集合指纹（契约 §R8 的兜底口径）。
  String _paperKeyOf(ToolArgs args, ThreadNodeKind kind, PaperPlan plan) {
    final explicit = args.optString('paper_key');
    if (explicit != null) {
      return explicit;
    }
    return switch (kind) {
      ThreadNodeKind.paper => PaperTaskMaterializer.paperKeyOf(plan),
      _ => 'plan',
    };
  }

  /// 默认容器标题**不带题数**：容器被复用时旧标题不会更新，带数字会越看越假。
  String? _defaultContainerTitle(ThreadNodeKind kind, DateTime? windowStart) {
    if (windowStart == null) {
      return null;
    }
    return switch (kind) {
      ThreadNodeKind.week =>
        '组卷 · ${PaperTaskMaterializer.isoWeekLabel(windowStart)}',
      ThreadNodeKind.day => '组卷 · ${_dateLabel(windowStart)}',
      _ => null,
    };
  }

  static DateTime? _asDateTime(int? epochMs) =>
      epochMs == null ? null : DateTime.fromMillisecondsSinceEpoch(epochMs);

  static String _dateLabel(DateTime day) {
    final year = day.year.toString().padLeft(4, '0');
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    return '$year-$month-$date';
  }
}
