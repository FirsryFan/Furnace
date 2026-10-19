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

import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/tag_repository.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/cognitive/problem_evaluator.dart';
import '../../../domain/services/reasoning/daily_study_plan.dart';
import '../../../domain/services/scheduling/today_plan.dart';
import '../../cognitive/application/daily_study_plan_reader.dart';
import '../domain/ai_tool.dart';
import 'cognitive_tools.dart';

/// Builds the day's list from due cards plus the candidate problems the model
/// supplied.
class PlanTodayTool extends AiTool {
  PlanTodayTool({
    required AnkiRepository ankiRepository,
    required TagRepository tagRepository,
    required AppDatabase database,
    CognitiveModel model = const MindNetCognitiveModel(),
    DateTime Function()? clock,
  })  : _anki = ankiRepository,
        _tags = tagRepository,
        _database = database,
        _model = model,
        _clock = clock ?? DateTime.now;

  final AnkiRepository _anki;
  final TagRepository _tags;

  /// The same shared assembly `evaluate_problem_fit` uses ([evaluateProblems])
  /// reads the user's tuned parameters from here - one place, so `plan_today`'s
  /// prices cannot be computed with a different `beta_goal` than that tool's.
  final AppDatabase _database;
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
            database: _database,
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

    // 两套口径并存，互不覆盖，注释写清各自回答的问题：
    // * 'actions'（TodayPlanner）：到期卡 + 模型这次给的候选题，按收益/成本 V(π)
    //   排序，只回答「这一轮先做哪件事最划算」；
    // * 'study_plan'（DailyStudyPlan，domain/services/reasoning/daily_study_plan.dart）：
    //   洞察 / 学习建议 / 配题推荐 / 到期卡四层**真实读数**排出的固定优先级计划，
    //   回答「今天整体怎么安排」。
    // 两者都只读数据；学习计划读取失败只是少了增量信息，不影响旧清单。
    DailyStudyPlan? studyPlan;
    String? studyPlanNotice;
    try {
      // 到期卡张数复用上面那次查询（同一个 moment），不再读第二次时钟：
      // 旧清单和新计划必须看同一个「今天」。
      studyPlan = await readDailyStudyPlan(
        database: _database,
        dueCardCount: dueCards.length,
      );
    } on Object {
      // 退化成没有 'study_plan' 字段，并在摘要里说明，不让整个工具失败。
      studyPlan = null;
      studyPlanNotice = '今天的学习计划读取失败，本次只返回旧的「今天做这几件事」清单。';
    }
    final studyPlanLine = studyPlan == null
        ? (studyPlanNotice ?? '')
        : _studyPlanSummaryLine(studyPlan);
    final modelResult = <String, Object?>{
      ...plan.toJson(),
      if (studyPlan != null) 'study_plan': studyPlan.toJson(),
    };

    if (plan.actions.isEmpty) {
      return ToolResult(
        ok: true,
        summary: '今天没有到期要复习的卡，也没有可排的题：清单是空的'
            '（这不是"没事做"，只是到期队列与候选题都空着）'
            '$studyPlanLine'
            '${tunedParametersNote(report.moduleDefaults)}',
        modelResult: modelResult,
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
          '$studyPlanLine\n'
          '加成未标定：这份顺序是提示，不是测量。'
          '${tunedParametersNote(report.moduleDefaults)}',
      modelResult: modelResult,
    );
  }
}

/// 学习计划的摘要句：只写计划里真实的分钟数 / 步数与一、二步标题。
///
/// 没有数据时（单条 noData）如实说「今天没有可依据的数据」，不虚构计划；
/// 这一步只是把 `DailyStudyPlan` 已有的读数翻译成一句人话，不改数字。
String _studyPlanSummaryLine(DailyStudyPlan studyPlan) {
  final steps = studyPlan.steps;
  if (steps.isEmpty) {
    return '今日学习计划为空（0 分钟）。';
  }
  if (steps.length == 1 && steps.first.kind == DailyPlanStepKind.noData) {
    return '今天预计 ${studyPlan.totalMinutes} 分钟、1 步：'
        '${steps.first.titleZh}。';
  }
  final next = steps.length > 1 ? '，再做：${steps[1].titleZh}' : '';
  return '今天预计 ${studyPlan.totalMinutes} 分钟、${steps.length} 步；'
      '先做：${steps.first.titleZh}$next。';
}
