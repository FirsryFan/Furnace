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
  String get description =>
      '评估一批候选题"现在值不值得做"，并给出推荐顺序。每道题得到判定（too_easy 已经会了 / '
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
                  'description':
                      '题目自报难度 0..1。只在没有任何复习记录时作先验，'
                          '**不会**作为模型的 difficulty（契约 §6.3）',
                },
              },
              'required': <String>['id'],
            },
          },
          'start_knowledge_point_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                '用户此刻在脑子里的闪存卡（通常是刚复习/刚做错的），可空；'
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
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    final args = ToolArgs(invocation.arguments);
    final candidates = _parseProblems(invocation.arguments['problems']);
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
    // representative card row per knowledge point.
    final tags = [
      for (final row in await _tags.getAllTags()) CognitiveTag.fromTag(row),
    ];
    final rows = <String, CardState>{};
    for (final point in await _anki.getKnowledgePoints()) {
      final states = await _anki.unitStatesForKnowledgePoint(point.id);
      final row = _representativeRow(states);
      if (row != null) {
        rows[point.id] = row;
      }
    }

    final report = ProblemEvaluator.evaluate(
      candidates: limited,
      tags: tags,
      rowsByKnowledgePoint: rows,
      model: _model,
      nowHours: modelHoursOf(moment),
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
              'judged_knowledge_point_ids':
                  evaluation.judgedKnowledgePointIds,
              'diagnosis': {
                for (final entry in evaluation.diagnosisByKnowledgePoint
                    .entries)
                  entry.key: entry.value.id,
              },
            },
        ],
      },
    );
  }

  /// The row that represents a knowledge point: the unit with the most review
  /// history, ties broken by id so the choice cannot depend on query order.
  ///
  /// The evaluator reasons per knowledge point while Furnace stores per unit
  /// (a point can own several blanks); "the one that has been reviewed the
  /// most" is the closest thing to "what this point currently looks like", and
  /// it is stated here rather than hidden in a sort.
  static CardState? _representativeRow(List<CardState> states) {
    if (states.isEmpty) {
      return null;
    }
    final sorted = [...states]..sort((a, b) {
        final byReps = b.repetitions.compareTo(a.repetitions);
        return byReps != 0 ? byReps : a.id.compareTo(b.id);
      });
    return sorted.first;
  }

  static List<ProblemCandidate> _parseProblems(Object? raw) {
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
        knowledgePointIds: _stringList(entry['knowledge_point_ids']),
        difficultyHint: _doubleOrNull(entry['difficulty_hint']),
      ));
    }
    return out;
  }

  static List<String> _stringList(Object? raw) {
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

  static double? _doubleOrNull(Object? raw) {
    if (raw is num) {
      return raw.toDouble();
    }
    return raw == null ? null : double.tryParse(raw.toString().trim());
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
