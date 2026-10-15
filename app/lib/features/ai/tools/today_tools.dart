/// 控制层 in the AI tool layer: "今天做这几件事" (roadmap §1 控制层行 / §3 第 5 行).
///
/// The tool is a **thin, read-only wrapper** (AI_DESIGN D2) around
/// [TodayPlanner]: it reads the cards that are due now and - when the model
/// hands it candidate problems - evaluates them through the *same* assembly
/// `evaluate_problem_fit` uses (see `cognitive_tools.dart`), then formats the
/// list. It contains no judgement logic of its own: no thresholds, no ordering,
/// no memory arithmetic, and it writes nothing anywhere.
///
/// Why it exists: the plan core (`today_plan.dart`, Q32a) is a pure function
/// nobody can reach without a caller. This is that caller, so the plan cannot
/// rot as dead code - and the model gets the one answer the roadmap asks for:
/// a list ranked by gain per unit cost, with the metric each price was measured
/// in and a sentence saying why each item is on it.
library;

import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/tag_repository.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/cognitive/problem_evaluator.dart';
import '../../../domain/services/scheduling/today_plan.dart';
import '../domain/ai_tool.dart';
import 'cognitive_tools.dart';

/// Builds the day's list from due cards plus the candidate problems the model
/// supplied.
class PlanTodayTool extends AiTool {
  PlanTodayTool({
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

  /// Injected so a test can pin "now" and get the same list twice.
  final DateTime Function() _clock;

  /// How many items the list keeps unless the model asks for another number.
  static const int defaultMaxActions = TodayPlanner.kTodayPlanDefaultMaxActions;

  /// The window a retention price is measured over, in hours.
  static const double defaultHorizonHours =
      TodayPlanner.kTodayPlanDefaultHorizonHours;

  @override
  String get name => 'plan_today';

  @override
  String get description => '把"现在到期的闪存卡"和用户给的候选题合成一份「今天做这几件事」的清单，'
      '按收益/成本 V(π) 排序。每条给出：做它买到了什么（`retention` 复习能多留下多少留存 / '
      '`reachability` 开一条线索能多到达多少）、价格 V、以及一句人话理由。没有正收益的项目'
      '（已经在上限的卡、没有价格的题）不编造 0，它们排在清单末尾并只说理由。'
      '**只读**：不写数据、不改到期日、不排复习、不动任何卡片。'
      '加成常数全部未标定：这是"下一步做什么"的提示，不是测量，清单会把这件事标出来。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'problems': {
            'type': 'array',
            'description': '可选：这次可以考虑的候选题（与 evaluate_problem_fit 同一形状）。'
                '不给就只有到期卡片。',
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
                  'description': '题目自报难度 0..1，只作没有复习记录时的先验',
                },
              },
              'required': <String>['id'],
            },
          },
          'start_knowledge_point_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '用户此刻在脑子里的闪存卡（通常是刚复习/刚做错的），可空',
          },
          'max_actions': {
            'type': 'integer',
            'description': '清单最多几件，默认 $defaultMaxActions',
          },
          'horizon_hours': {
            'type': 'number',
            'description': '留存价格的窗口（小时），默认 $defaultHorizonHours',
          },
          'now': {
            'type': 'string',
            'description': '可选 ISO-8601 时刻，用于复现同一份清单；默认当前时间',
          },
        },
      };

  /// Reading is not a risk and the tool asks for no action - the neutral
  /// `write` with [reversibleFor] `true` is what keeps `ApprovalEngine` from
  /// asking per call (same choice as `evaluate_problem_fit`).
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
    final nowMs = args.optEpochMs('now');
    final moment =
        nowMs == null ? _clock() : DateTime.fromMillisecondsSinceEpoch(nowMs);
    final maxActions =
        (args.optInt('max_actions') ?? defaultMaxActions).clamp(1, 50);
    final horizonHours =
        (args.optDouble('horizon_hours') ?? defaultHorizonHours)
            .clamp(1.0, 720.0);

    final candidates = parseProblemCandidates(invocation.arguments['problems']);
    final report = candidates.isEmpty
        ? const ProblemEvaluationReport(
            evaluations: <ProblemEvaluation>[],
            fastLayerRan: false,
            nodesWithoutMs: <String>[],
          )
        : await evaluateProblems(
            ankiRepository: _anki,
            tagRepository: _tags,
            model: _model,
            candidates: candidates,
            moment: moment,
            startKnowledgePointIds:
                args.optStringList('start_knowledge_point_ids') ??
                    const <String>[],
          );

    // 到期卡是"今天"这个集合的定义；未来的卡不在清单里（也不改任何到期日）。
    final dueCards =
        await _anki.getDueCardStates(moment.millisecondsSinceEpoch);
    final names = <String, String>{
      for (final point in await _anki.getKnowledgePoints())
        point.id: point.title,
    };

    final plan = TodayPlanner.build(
      cards: dueCards,
      problems: report,
      nowHours: modelHoursOf(moment),
      knowledgePointNames: names,
      horizonHours: horizonHours,
      maxActions: maxActions,
    );

    if (plan.actions.isEmpty) {
      return ToolResult(
        ok: true,
        summary: '今天没有到期要复习的卡，也没有可排的题：清单是空的'
            '（这不是"没事做"，只是到期队列与候选题都空着）',
        modelResult: plan.toJson(),
      );
    }

    final lines = <String>[];
    for (var i = 0; i < plan.actions.length; i++) {
      final action = plan.actions[i];
      final price = action.priced
          ? '，${action.metric!.name} V=${action.value!.toStringAsFixed(3)}'
          : '';
      final kind = action.kind == TodayActionKind.review ? '复习' : '练习';
      lines.add('${i + 1}. [$kind] ${action.title}$price —— ${action.why}');
    }
    final omitted = plan.omitted > 0 ? '，另有 ${plan.omitted} 件排在清单外' : '';

    return ToolResult(
      ok: true,
      summary: '今天做这几件事（${plan.actions.length} 件$omitted）：\n'
          '${lines.join('\n')}\n'
          '加成未标定：这份顺序是提示，不是测量。',
      modelResult: plan.toJson(),
    );
  }
}
