/// 用途 1 in the AI tool layer: "which of these problems is worth doing now?"
///
/// The tool is a **thin, read-only wrapper** (AI_DESIGN D2): it reads the user's
/// tags and card rows through the repositories, hands them to
/// [ProblemEvaluator] together with the [CognitiveModel] seam, and formats the
/// answer. It contains **no judgement logic of its own** - no thresholds, no
/// ranking, no memory arithmetic - and it writes nothing anywhere (no SQL, no
/// repository write method, no `update*` call).
///
/// Why it is in the AI layer at all: §6.3's "约 20 行胶水" only becomes real
/// when something can call it. This is that caller, so the evaluator cannot rot
/// as dead code.
library;

import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/tag_repository.dart';
import '../../../domain/services/cognitive/cognitive_graph.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/cognitive/knowledge_point_tag_bridge.dart';
import '../../../domain/services/cognitive/library_diagnosis.dart'
    show representativeCardRow;
import '../../../domain/services/cognitive/problem_evaluator.dart';
import '../domain/ai_tool.dart';

/// Evaluates a batch of candidate problems and ranks them.
class EvaluateProblemFitTool extends AiTool {
  EvaluateProblemFitTool({
    required AnkiRepository ankiRepository,
    required TagRepository tagRepository,
    CognitiveModel model = const MindNetCognitiveModel(),
    DateTime Function()? clock,
  })  : _anki = ankiRepository,
        _tags = tagRepository,
        _model = model,
        _clock = clock ?? DateTime.now;

  final AnkiRepository _anki;
  final TagRepository _tags;
  final CognitiveModel _model;

  /// Injected so a test can pin "now" and get the same ranking twice.
  final DateTime Function() _clock;

  /// How many problems one call evaluates unless the model asks for another
  /// number. The cap exists because every candidate runs its own diffusion.
  static const int defaultLimit = 20;

  @override
  String get name => 'evaluate_problem_fit';

  @override
  String get description => '评估一批候选题"现在值不值得做"，并给出推荐顺序。每道题得到判定（too_easy 已经会了 / '
      'zpd 发展中区 / too_hard 现在做是硬啃 / out_of_scope 超纲或死角 / redundant 与另一题重复 / '
      'high_value 值得现在做）、排序键和人话理由。判定来自认知模型：闪存卡标签 → 认知图 → '
      '快层扩散诊断（"差点想起来"= 发展区、"进不去/走不下去"= 死角），并结合用户自己的复习状态。'
      '**只读**：不写数据、不排复习、不改任何卡片。题目自报的难度只作"没有复习记录时"的先验。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'problems': {
            'type': 'array',
            'description': '候选题列表（必填）。id 必填，其余可省。',
            'items': {
              'type': 'object',
              'properties': {
                'id': {'type': 'string', 'description': '题目 id（唯一）'},
                'stem': {
                  'type': 'string',
                  'description': '题干摘要，只用于人话理由',
                },
                'knowledge_point_ids': {
                  'type': 'array',
                  'items': {'type': 'string'},
                  'description': '这道题用到的闪存卡标签 id；没有标签时无法判定',
                },
                'difficulty_hint': {
                  'type': 'number',
                  'description': '题目自报难度 0..1。只在没有任何复习记录时作先验，'
                      '**不会**作为模型的 difficulty（契约 §6.3）',
                },
              },
              'required': <String>['id'],
            },
          },
          'start_knowledge_point_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '用户此刻在脑子里的闪存卡（通常是刚复习/刚做错的），可空；'
                '图外 id 会被忽略',
          },
          'now': {
            'type': 'string',
            'description': '可选 ISO-8601 时刻，用于复现同一次评估；默认当前时间',
          },
          'limit': {
            'type': 'integer',
            'description': '最多评估几道题，默认 $defaultLimit',
          },
        },
        'required': <String>['problems'],
      };

  /// Reading is not a risk (`ai_tool.dart` D12 v2 has only write/destructive),
  /// and this tool never asks for an action - so the value is the neutral
  /// `write` with [reversibleFor] `true`, which is exactly what makes
  /// `ApprovalEngine` never ask per call for it (it can only reach
  /// `executeNow` or the turn's single batch confirmation).
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
    final candidates = parseProblemCandidates(invocation.arguments['problems']);
    if (candidates.isEmpty) {
      return const ToolResult(
        ok: true,
        summary: '没有可评估的题：请在 problems 里给出至少一道题（每道题需要 id）',
        modelResult: {
          'returned': 0,
          'fast_layer_ran': false,
          'problems': <Object?>[],
        },
      );
    }

    final limit = (args.optInt('limit') ?? defaultLimit).clamp(1, 200);
    final limited = candidates.take(limit).toList();

    final nowMs = args.optEpochMs('now');
    final moment =
        nowMs == null ? _clock() : DateTime.fromMillisecondsSinceEpoch(nowMs);

    // Read-only reads: the tag tree (the projection's input) and one
    // representative card row per knowledge point. The assembly is shared with
    // `plan_today` (see [evaluateProblems]) so the two tools cannot drift into
    // two different pictures of the same user state.
    final report = await evaluateProblems(
      ankiRepository: _anki,
      tagRepository: _tags,
      model: _model,
      candidates: limited,
      moment: moment,
      startKnowledgePointIds:
          args.optStringList('start_knowledge_point_ids') ?? const <String>[],
    );

    final counts = <String, int>{};
    for (final evaluation in report.evaluations) {
      final id = _verdictId(evaluation.verdict);
      counts[id] = (counts[id] ?? 0) + 1;
    }

    return ToolResult(
      ok: true,
      summary: '评估了 ${report.evaluations.length} 道题（'
          '${counts.entries.map((e) => '${e.key} ${e.value}').join(' / ')}）'
          '${report.fastLayerRan ? '，诊断层已运行' : '，仅用记忆层（无诊断）'}',
      modelResult: {
        'returned': report.evaluations.length,
        'truncated': candidates.length > limited.length,
        'fast_layer_ran': report.fastLayerRan,
        'nodes_without_ms': report.nodesWithoutMs,
        'problems': [
          for (final evaluation in report.evaluations)
            {
              'id': evaluation.problemId,
              'verdict': _verdictId(evaluation.verdict),
              'rank_key': evaluation.rankKey,
              'reason': evaluation.reason,
              'knowledge_point_ids': evaluation.knowledgePointIds,
              'judged_knowledge_point_ids': evaluation.judgedKnowledgePointIds,
              'diagnosis': {
                for (final entry
                    in evaluation.diagnosisByKnowledgePoint.entries)
                  entry.key: entry.value.id,
              },
              // §2-A 缺①: the counterfactual line, in the model's own numbers.
              // `value` is `V(π) = ΔR / cost`, an **uncalibrated** tie-break -
              // `rank_key` stays the primary key - and it is absent when nothing
              // could be simulated (a `retention` instruction needs the memory
              // layer wired through `RetentionProbe`).
              if (evaluation.counterfactualValue != null)
                'counterfactual': {
                  'metric': evaluation.counterfactualMetric,
                  'instruction': evaluation.counterfactualInstruction,
                  'value': evaluation.counterfactualValue,
                  'why': evaluation.counterfactualWhy,
                },
            },
        ],
      },
    );
  }

  /// The contract's wire names (`too_easy`, …). A pure format mapping - the
  /// verdict itself is [ProblemEvaluator]'s.
  static String _verdictId(ProblemVerdict verdict) => switch (verdict) {
        ProblemVerdict.tooEasy => 'too_easy',
        ProblemVerdict.zpd => 'zpd',
        ProblemVerdict.tooHard => 'too_hard',
        ProblemVerdict.outOfScope => 'out_of_scope',
        ProblemVerdict.redundant => 'redundant',
        ProblemVerdict.highValue => 'high_value',
      };
}

/// The read-only assembly both §2-A tools need: the tag tree, one representative
/// card row per knowledge point, and the knowledge-point → tag bridge.
///
/// Extracted rather than copied so `evaluate_problem_fit` and `plan_today`
/// cannot drift into two different pictures of the same user state; it reads
/// through the repositories and writes nothing.
Future<ProblemEvaluationReport> evaluateProblems({
  required AnkiRepository ankiRepository,
  required TagRepository tagRepository,
  required CognitiveModel model,
  required List<ProblemCandidate> candidates,
  required DateTime moment,
  List<String> startKnowledgePointIds = const <String>[],
}) async {
  final tags = [
    for (final row in await tagRepository.getAllTags())
      CognitiveTag.fromTag(row),
  ];
  final rows = <String, CardState>{};
  // Knowledge-point -> tag links, collected while reading the points: the
  // evaluator's graph is built from **tags**, so the rows below have to be
  // translated into that key space (same bridge as the page and the thread
  // feed - see `docs/THREADFLOW_TWO_SEGMENT.md` §8.3 for the silent failure
  // this prevents).
  final links = <ObjectTagLink>[];
  for (final point in await ankiRepository.getKnowledgePoints()) {
    final states = await ankiRepository.unitStatesForKnowledgePoint(point.id);
    final row = representativeCardRow(states);
    if (row == null) {
      continue;
    }
    rows[point.id] = row;
    for (final tag in await tagRepository.tagsForObject(
      objectType: kKnowledgePointObjectType,
      objectId: point.id,
    )) {
      links.add(
        ObjectTagLink(
          tagId: tag.id,
          objectType: kKnowledgePointObjectType,
          objectId: point.id,
        ),
      );
    }
  }

  return ProblemEvaluator.evaluate(
    candidates: candidates,
    tags: tags,
    rowsByKnowledgePoint: rows,
    model: model,
    nowHours: modelHoursOf(moment),
    startKnowledgePointIds: startKnowledgePointIds,
    // Same boundary as the page: the evaluator translates into the graph's tag
    // key space and reports back in knowledge-point ids (Q8).
    tagIdsByKnowledgePoint:
        KnowledgePointTagBridge.tagIdsByKnowledgePoint(links),
  );
}

/// Parses the `problems` argument both §2-A tools accept. A malformed entry is
/// skipped, not guessed at; `id` is the only required key.
List<ProblemCandidate> parseProblemCandidates(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  final out = <ProblemCandidate>[];
  for (final entry in raw) {
    if (entry is! Map) {
      continue;
    }
    final id = entry['id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      continue;
    }
    out.add(ProblemCandidate(
      id: id,
      stem: entry['stem']?.toString() ?? '',
      knowledgePointIds: stringListOf(entry['knowledge_point_ids']),
      difficultyHint: doubleOrNullOf(entry['difficulty_hint']),
    ));
  }
  return out;
}

/// One string or a list of strings, trimmed; empty entries dropped.
List<String> stringListOf(Object? raw) {
  if (raw is List) {
    return [
      for (final item in raw)
        if (item != null && item.toString().trim().isNotEmpty)
          item.toString().trim(),
    ];
  }
  if (raw == null) {
    return const [];
  }
  final single = raw.toString().trim();
  return single.isEmpty ? const [] : [single];
}

/// A number from either a JSON number or a numeric string.
double? doubleOrNullOf(Object? raw) {
  if (raw is num) {
    return raw.toDouble();
  }
  return raw == null ? null : double.tryParse(raw.toString().trim());
}
