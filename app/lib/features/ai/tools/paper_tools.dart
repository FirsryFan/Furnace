/// 组卷能力（Q9/Q11）接进 AI 工具层。
///
/// 用户口径（历史记录）：**AI 不能自己出题**。所以这个工具只做一件事：把"想练什么"
/// 变成一次 `PaperComposer.compose(...)` 调用，从**已有题库**里按薄弱/危险区知识点
/// 凑题，并把"为什么是这道、缺哪些知识点"如实报出来。凑不齐就说缺什么、建议去收题，
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
import '../../../domain/services/paper/paper_composer.dart';
import '../../../domain/services/paper/subject_quota.dart';
import '../../../domain/services/reasoning/capability_profile.dart';
import '../../cognitive/application/library_diagnosis_reader.dart';
import '../../questions/application/paper_plan_builder.dart';
import '../../questions/application/question_corpus_reader.dart';
import '../domain/ai_tool.dart';

/// 按薄弱/危险区知识点，从已有题库里凑一份卷子（AI 不出题）。
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
      '凑不齐时如实列出"缺哪些知识点"（`uncovered_knowledge_point_ids`）让人去收题。'
      '用在你需要"现在该练什么"的时候。**只读**：不写数据、不生成题干、不落库——'
      '它只从库里挑已有的题，挑不出来就说挑不出来，绝不自己编一道题填空。'
      '这不是随机抽题：它按诊断读数排序，并受学科/来源/每知识点配额约束。'
      '默认还会参考"我最该练的动作"（能力动作画像，未标定，可用 '
      '`use_capability_profile: false` 关掉）。';

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
      final spec = _specOf(args);
      final useCapabilityProfile =
          args.optBool('use_capability_profile') ?? true;

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

      return ToolResult(
        ok: true,
        summary: _summaryOf(
          plan: plan,
          corpus: corpus,
          diagnosisRan: diagnosis.fastLayerRan,
        ),
        modelResult: {
          'requested_count': plan.requestedCount,
          'item_count': plan.items.length,
          'is_short': plan.isShort,
          'candidate_count': plan.candidateCount,
          'bank_size': corpus.candidates.length,
          'overall_need': plan.overallNeed,
          'weights': plan.weights.toMap(),
          'diagnosis_ran': diagnosis.fastLayerRan,
          'readings_used': build.readingsUsed,
          'preferred_action_types': preferredActions,
          'capability_profile_used': preferredActions.isNotEmpty,
          if (plan.subjectQuota != null) 'by_subject': plan.bySubject,
          if (plan.subjectQuota != null)
            'quota_blocked_questions': [
              for (final blocked in plan.quotaBlockedQuestions)
                blocked.toJson(),
            ],
          if (plan.subjectQuota != null)
            'subject_shortfalls': [
              for (final shortfall in plan.subjectShortfalls)
                shortfall.toJson(),
            ],
          if (plan.subjectQuota != null)
            'subject_quota': plan.subjectQuota!.toJson(),
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
        },
      );
    } on ToolArgError catch (error) {
      return ToolResult.failure(error.message);
    }
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

  /// 摘要说人话：凑了几道、哪几道是为了哪个知识点、缺什么、以及"我不会自己出题"。
  String _summaryOf({
    required PaperPlan plan,
    required PaperCorpus corpus,
    required bool diagnosisRan,
  }) {
    final buffer = StringBuffer();
    if (corpus.candidates.isEmpty) {
      buffer.write(
        '题库里还没有任何可用的题（题干为空的题不算），所以凑不出卷子。'
        '我不会自己出题——先去收题页把题目收进来（可以拍照/粘贴），再让我组卷。',
      );
      return buffer.toString();
    }

    if (plan.items.isEmpty) {
      buffer.write(
        '题库里有 ${corpus.candidates.length} 道题，但按当前条件'
        '（学科/来源/难度/配额）一道都排不出来。',
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
        '——建议去收题（我不会自己出题）。',
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
    if (!diagnosisRan) {
      buffer.write(
        ' 注意：认知快层这轮没有跑出结论（没有标签或没有卡片观测），'
        '所以所有知识点都按"没有读数"处理——**不是**"健康"。',
      );
    }
    return buffer.toString();
  }
}
