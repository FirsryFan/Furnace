/// 「今天做这几件事」：把"该复习的卡"和"该做的题"排成一份可以照做的清单。
///
/// 这是 roadmap §1 控制层那一行的验收面 —— 反事实规划器 `V(π) = 收益 / 成本`
/// 的排序结果必须真的变成一串动作，否则它只是判定层的一个数字。这一层自己
/// **不做任何判定**，只做搬运与排序：
///
/// * **卡片侧的价格**来自 `DsrCardState.read` + `DsrMemory`：复习一次，到
///   `nowHours + horizonHours` 时多出来的可提取度 `ΔR`。这与题目侧
///   `dsrRetentionProbe` 报的**是同一个量**（同一个记忆层、同一个时间窗、
///   同一份常数），所以两侧的 `retention` 价格放在一起看是有意义的。
/// * **题目侧的价格**来自 [ProblemEvaluation] 的反事实字段：瓶颈、指令与
///   `V(π)` 都由 `ProblemEvaluator` 算，这一层只搬运。`reachability`（开一条
///   线索）与 `retention`（复习一个节点）问的**不是同一个问题**，所以每一项
///   都带 [TodayAction.metric]；排序用的是"每单位成本买到多少"这个方便次序，
///   不是标定过的换算 —— [TodayPlan.uncalibrated] 恒为 `true`。
/// * **没有价格的项目不报价格**：已经在上限的卡复习了也买不到明天的留存
///   （`ΔR = 0`），它排在有价格的项目之后，按到期日排。`0.0` 不是价格，理由
///   与 `ProblemEvaluator` 的 `_bestPlanEntry` 相同：零增益永远不会改变次序，
///   写个 `0.0` 出去像在测量"这件事一文不值"，其实只是撞到上限。
///
/// **纯函数**：没有数据库、没有时钟、没有 IO。`nowHours` 是调用方的时钟
/// （Unix 纪元起的小时数，契约 §6.1），`horizonHours` 与成本都是 [未标定]。
library;

import '../../../data/database/database.dart';
import '../cognitive/problem_evaluator.dart';
import '../srs/dsr_card_state.dart';
import '../srs/dsr_memory.dart';

/// 今天这件事是复习一张卡，还是做一道题。
enum TodayActionKind {
  /// 复习一张已有排期的闪存卡。
  review,

  /// 做一道候选题。
  practice,
}

/// 一个价格回答的是哪个问题。
///
/// 两个值**不是**同一个量，所以一个计划里可以同时出现它们，但每一项都必须
/// 说清楚自己拿的是哪个答案。
enum TodayMetric {
  /// 复习/练一次之后，到 `horizon` 时多出来的可提取度 `ΔR`（卡片侧与题目侧
  /// 都有）。
  retention,

  /// 开一条线索（`add_in_edges`）带来的可达性增益，只有题目侧会有，成本是
  /// `costLink`。
  reachability,
}

/// 清单里的一件事：做什么、买到了多少、为什么排这里。
class TodayAction {
  const TodayAction({
    required this.kind,
    required this.id,
    required this.title,
    this.knowledgePointId,
    this.metric,
    this.value,
    this.gain,
    this.cost,
    required this.why,
    this.dueAtMs,
  });

  /// 复习或练习。
  final TodayActionKind kind;

  /// 卡片侧是 `card_states.id`，题目侧是题目 id。
  final String id;

  /// 给人看的名字（卡片用知识点名/单元键，题目用题干摘要）。
  final String title;

  final String? knowledgePointId;

  /// 价格回答的问题；null = 这件事没有价格。
  final TodayMetric? metric;

  /// `收益 / 成本`，null = 没有价格。它**只是**次序与解释，不是标定过的分数。
  final double? value;

  /// 收益本身（`retention` 是 ΔR，`reachability` 是可达性增量）。
  final double? gain;

  /// 成本（卡片侧默认 [TodayPlanner.kTodayPlanCostReview]，题目侧由 planner 给）。
  final double? cost;

  /// 人话理由。
  final String why;

  /// 排期（毫秒）；无价格的同类项目按它升序排。
  final int? dueAtMs;

  bool get priced => value != null;

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'id': id,
        'title': title,
        if (knowledgePointId != null) 'knowledge_point_id': knowledgePointId,
        if (metric != null) 'metric': metric!.name,
        if (value != null) 'value': value,
        if (gain != null) 'gain': gain,
        if (cost != null) 'cost': cost,
        'why': why,
        if (dueAtMs != null) 'due_at': dueAtMs,
      };
}

/// 一份计划。
class TodayPlan {
  const TodayPlan({
    required this.actions,
    required this.considered,
    required this.horizonHours,
    required this.nowHours,
  });

  /// 已经排好序、并按 `maxActions` 截断的动作。
  final List<TodayAction> actions;

  /// 截断前一共有多少件事（含没有价格的）。
  final int considered;

  final double horizonHours;
  final double nowHours;

  /// 这个计划里的数字全部未标定：它是次序提示，不是测量。
  static const bool uncalibrated = true;

  bool get isEmpty => actions.isEmpty;

  /// 计划里是否同时出现了两种度量（调用方可以据此分开呈现）。
  bool get mixesMetrics =>
      actions.map((a) => a.metric).whereType<TodayMetric>().toSet().length > 1;

  /// 被 `maxActions` 挡在外面的事情数。
  int get omitted => considered - actions.length;

  Map<String, Object?> toJson() => {
        'uncalibrated': uncalibrated,
        'now_hours': nowHours,
        'horizon_hours': horizonHours,
        'considered': considered,
        // 两种度量同时出现时如实说出来：调用方不该把两个数字当成同一个单位。
        'mixes_metrics': mixesMetrics,
        'actions': [for (final action in actions) action.toJson()],
      };
}

/// 把卡片与题目排成一份清单。
abstract final class TodayPlanner {
  /// 一次复习的成本，取 `FastPlannerParams.costRetrieval` 的同一个数
  /// （`fast_diagnosis.dart`），[未标定]：它是 MindNet 的指令成本单位，不是分钟。
  static const double kTodayPlanCostReview = 1.0;

  /// 开一条线索（`add_in_edges`）的成本，取 `FastPlannerParams.costLink` 的
  /// 同一个数，[未标定]。题目侧报 `reachability` 价格时用它。
  static const double kTodayPlanCostLink = 2.0;

  /// 价格回答的问题是"到明天还能留住多少"，所以默认窗口是 24 小时。
  static const double kTodayPlanDefaultHorizonHours = 24;

  /// 默认只列几件：清单是给人照做的，不是名录。
  static const int kTodayPlanDefaultMaxActions = 5;

  /// 复习这张卡到 [horizonHours] 之后多留下多少可提取度。
  ///
  /// `before` 是现在不动它、到窗口时的可提取度；`after` 是就地复习一次
  /// （`DsrReviewEvent()` = `retrieval_success` grade 3）之后同一个时刻的
  /// 可提取度。**上限处 gain 恰好是 0**（`R0` 已封顶、稳定性增益 1.0），
  /// 这不是错误，是"复习买不到明天的留存"的诚实读数。
  static ({double gain, double before, double after}) retentionGainOf(
    CardState row, {
    required double nowHours,
    double horizonHours = kTodayPlanDefaultHorizonHours,
    DsrParams params = const DsrParams(),
  }) {
    final state = DsrCardState.read(row, params: params, nowHours: nowHours);
    final horizon = nowHours + horizonHours;
    final before = DsrMemory.retrievability(state, horizon, params).r;
    final reviewed = state.copy();
    DsrMemory.applyReview(reviewed, nowHours, const DsrReviewEvent(), params);
    final after = DsrMemory.retrievability(reviewed, horizon, params).r;
    return (gain: after - before, before: before, after: after);
  }

  /// 排一份计划。
  ///
  /// [cards] 是调用方挑出来的"今天该看的卡"（通常是
  /// `AnkiRepository.getDueCardStates` 的结果，这一层不再筛）。
  /// [problems] 是 `ProblemEvaluator.evaluate` 的结果 —— 判定与价格已经算好，
  /// 这一层只读它的 `counterfactual*` 字段。
  static TodayPlan build({
    required List<CardState> cards,
    required ProblemEvaluationReport problems,
    required double nowHours,
    DsrParams params = const DsrParams(),
    Map<String, String> knowledgePointNames = const {},
    double horizonHours = kTodayPlanDefaultHorizonHours,
    double costReview = kTodayPlanCostReview,
    int maxActions = kTodayPlanDefaultMaxActions,
  }) {
    final actions = <TodayAction>[
      for (final row in cards)
        _cardAction(
          row,
          nowHours: nowHours,
          params: params,
          knowledgePointNames: knowledgePointNames,
          horizonHours: horizonHours,
          costReview: costReview,
        ),
      for (final evaluation in problems.evaluations) _problemAction(evaluation),
    ];

    // 键全部显式：value 降序（没有价格的排最后）→ 复习先于练习 → 到期日升序
    // （无期垫底）→ id 升序。不依赖 List.sort 的稳定性。
    final sorted = [...actions]..sort((a, b) {
        final byValue = _valueDesc(a.value, b.value);
        if (byValue != 0) {
          return byValue;
        }
        final byKind = a.kind.index.compareTo(b.kind.index);
        if (byKind != 0) {
          return byKind;
        }
        final byDue = _intAsc(a.dueAtMs, b.dueAtMs);
        if (byDue != 0) {
          return byDue;
        }
        return a.id.compareTo(b.id);
      });

    final cap = maxActions < 0 ? 0 : maxActions;
    return TodayPlan(
      actions: sorted.take(cap).toList(growable: false),
      considered: sorted.length,
      horizonHours: horizonHours,
      nowHours: nowHours,
    );
  }

  static TodayAction _cardAction(
    CardState row, {
    required double nowHours,
    required DsrParams params,
    required Map<String, String> knowledgePointNames,
    required double horizonHours,
    required double costReview,
  }) {
    final price = retentionGainOf(
      row,
      nowHours: nowHours,
      horizonHours: horizonHours,
      params: params,
    );
    final knowledgePointId = row.knowledgePointId;
    final name =
        knowledgePointId == null ? null : knowledgePointNames[knowledgePointId];
    final title = name ?? row.unitKey ?? knowledgePointId ?? row.id;

    // 零增益不是价格：它永远不会改变次序，而 0.0 读起来像"这张卡一文不值"。
    if (price.gain <= 0) {
      return TodayAction(
        kind: TodayActionKind.review,
        id: row.id,
        title: title,
        knowledgePointId: knowledgePointId,
        why: '复习这张卡买不到明天的留存（现在 ${_pct(price.before)}，复习后 '
            '${_pct(price.after)}），按到期日排',
        dueAtMs: row.dueAt,
      );
    }

    return TodayAction(
      kind: TodayActionKind.review,
      id: row.id,
      title: title,
      knowledgePointId: knowledgePointId,
      metric: TodayMetric.retention,
      value: price.gain / costReview,
      gain: price.gain,
      cost: costReview,
      why: '复习这张卡：${horizonHours.round()} 小时后多留下 '
          '${_pct(price.gain)}（现在 ${_pct(price.before)} → 复习后 '
          '${_pct(price.after)}）',
      dueAtMs: row.dueAt,
    );
  }

  static TodayAction _problemAction(ProblemEvaluation evaluation) {
    final value = evaluation.counterfactualValue;
    // 与 `ProblemEvaluator._bestPlanEntry` 同一条规则：零增益与"没算过"
    // 都不报价格。
    if (value == null || value <= 0) {
      return TodayAction(
        kind: TodayActionKind.practice,
        id: evaluation.problemId,
        title: evaluation.stem,
        knowledgePointId: evaluation.knowledgePointIds.isEmpty
            ? null
            : evaluation.knowledgePointIds.first,
        why: evaluation.reason,
      );
    }

    final metric = evaluation.counterfactualMetric == 'reachability'
        ? TodayMetric.reachability
        : TodayMetric.retention;
    final instruction = evaluation.counterfactualInstruction;
    return TodayAction(
      kind: TodayActionKind.practice,
      id: evaluation.problemId,
      title: evaluation.stem,
      knowledgePointId: evaluation.knowledgePointIds.isEmpty
          ? null
          : evaluation.knowledgePointIds.first,
      metric: metric,
      value: value,
      gain: _priceGain(evaluation, metric),
      cost: metric == TodayMetric.reachability
          ? kTodayPlanCostLink
          : kTodayPlanCostReview,
      why: '${evaluation.reason}（${instruction ?? '指令'}，'
          'V=${value.toStringAsFixed(3)}）',
    );
  }

  /// 题目侧不重算价格，只把 `V` 与成本还原成收益（`gain = V × cost`）。
  static double _priceGain(ProblemEvaluation evaluation, TodayMetric metric) {
    final value = evaluation.counterfactualValue ?? 0;
    return value *
        (metric == TodayMetric.reachability
            ? kTodayPlanCostLink
            : kTodayPlanCostReview);
  }

  static int _valueDesc(double? a, double? b) {
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    return b.compareTo(a);
  }

  static int _intAsc(int? a, int? b) {
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    return a.compareTo(b);
  }
}

String _pct(double value) => '${(value * 100).round()}%';
