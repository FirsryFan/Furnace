/// 推理层：今日计划步骤 → 跳转目标的纯逻辑映射。
///
/// 为什么需要这一层：§24 的 [DailyStudyPlan] 告诉用户「今天做什么」，但「点了
/// 去哪」如果直接写进 widget，就没法单测，也容易把用户送到空页面。这一层只把
/// [DailyPlanStep] 翻译成 [DailyPlanStepDestination]（目标种类 + 必要的导航
/// 参数），不 import Flutter、不读数据库、不读时钟、不调模型；页面只负责按
/// [DailyPlanStepDestination.kind] 找路由，并按 [DailyPlanStepDestination.isNavigable]
/// 决定这一步可不可点。
///
/// 诚实性规则：
/// 1. **不把用户送到空页面**：练习步骤没有题号 → 不可导航；复习步骤没有到期
///    卡片（null / <= 0）→ 不可导航。kind 仍如实保留，界面据此可以说明原因，
///    而不是谎称没有这一步。
/// 2. **没有目标就说没有**：noData 映射为 [DailyPlanDestinationKind.none]
///    （不可导航），不假装有页面可去。
/// 3. **节奏不是任务**：keepGoing 只是「保持节奏」，不可导航。
/// 4. **补齐思维链只带动作 key，不猜题号**：collectChains 的 actionType 原样
///    透传（可能为 null）；题库页自己决定怎么筛，本层不虚构题号 / 知识点。
/// 5. **未知动作只指向词表**：reviewVocabulary 只映射到能力动作词表页，不在
///    计划层构造任何动作内容，也不把动作名当路由参数猜。
/// 6. **参数按种类收窄**：练习只带题号、复习只带卡片数、补齐思维链只带动作 key；
///    步骤上其它字段即使有值也不夹带（避免 UI 误用）。
/// 7. **确定性 + 值语义**：同一输入两次调用结果相同；[DailyPlanStepDestination]
///    实现 `==` / `hashCode`，questionIds 去重且保持输入顺序。
///
/// 映射表（[DailyPlanStepKind] → [DailyPlanDestinationKind]）：
/// - practiceQuestions → practiceQuestions（questionIds 非空才可导航）
/// - reviewDueCards → ankiReview（cardCount > 0 才可导航）
/// - collectChains → collectChains（总是可导航，带 actionType）
/// - reviewVocabulary → vocabulary（总是可导航）
/// - keepGoing → keepGoing（不可导航）
/// - noData → none（不可导航）
library;

import 'daily_study_plan.dart';

/// 今日计划一步的跳转目标属于哪一类页面。
///
/// 与 [DailyPlanStepKind] 一一对应，但语义不同：这里描述「去哪」，而且可能
/// 是 [none]（没有页面可去）。
enum DailyPlanDestinationKind {
  /// 练习配题：带着题号去练习页。
  practiceQuestions,

  /// 间隔重复复习：带着到期卡片数去复习队列页。
  ankiReview,

  /// 补齐思维链：去题库 / 搜索页，可选带一个能力动作 key 作为筛选提示。
  collectChains,

  /// 补能力动作词表：去词表编辑页。
  vocabulary,

  /// 继续保持：只是节奏提示，没有页面可去。
  keepGoing,

  /// 没有跳转目标：当前步骤没有可去的页面。
  none,
}

/// 今日计划一步的跳转目标（不可变、纯数据、值语义）。
///
/// [questionIds] 在构造时就去重、去空白并保持输入顺序，之后不可变；
/// [isNavigable] 是派生判定：页面只看它决定这一步是否可点。
class DailyPlanStepDestination {
  /// 构造一个跳转目标。
  ///
  /// [questionIds] 会 trimmed、丢弃空串、去重（保留首次出现顺序）；
  /// [cardCount] 与 [actionType] 原样保留（不猜默认值）。
  DailyPlanStepDestination({
    required this.kind,
    List<String> questionIds = const <String>[],
    this.cardCount,
    this.actionType,
  }) : questionIds = List<String>.unmodifiable(_normalizeIds(questionIds));

  /// 目标页面种类。
  final DailyPlanDestinationKind kind;

  /// 练习页要打开的题号（去重、保序、不可变）；其它种类为空列表。
  final List<String> questionIds;

  /// 复习队列页要清理的到期卡片数；只有 [DailyPlanDestinationKind.ankiReview]
  /// 会携带。null / <= 0 表示没有到期卡片。
  final int? cardCount;

  /// 能力动作 key；只有 [DailyPlanDestinationKind.collectChains] 会携带，
  /// 且原样透传（可能为 null）。
  final String? actionType;

  /// 这一步是否有页面可去。
  ///
  /// 练习必须有题号、复习必须有正数到期卡片；补齐思维链与补词表总有页面；
  /// 继续保持与 none 永远不可导航。
  bool get isNavigable {
    switch (kind) {
      case DailyPlanDestinationKind.practiceQuestions:
        return questionIds.isNotEmpty;
      case DailyPlanDestinationKind.ankiReview:
        final count = cardCount;
        return count != null && count > 0;
      case DailyPlanDestinationKind.collectChains:
      case DailyPlanDestinationKind.vocabulary:
        return true;
      case DailyPlanDestinationKind.keepGoing:
      case DailyPlanDestinationKind.none:
        return false;
    }
  }

  /// 固定键序的 JSON：kind, question_ids, card_count, action_type,
  /// is_navigable。
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'question_ids': List<String>.of(questionIds),
        'card_count': cardCount,
        'action_type': actionType,
        'is_navigable': isNavigable,
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is DailyPlanStepDestination &&
        kind == other.kind &&
        cardCount == other.cardCount &&
        actionType == other.actionType &&
        _sameIds(questionIds, other.questionIds);
  }

  @override
  int get hashCode =>
      Object.hash(kind, Object.hashAll(questionIds), cardCount, actionType);

  @override
  String toString() =>
      'DailyPlanStepDestination(kind: ${kind.name}, questionIds: $questionIds, '
      'cardCount: $cardCount, actionType: $actionType)';
}

/// 把今日计划的一步映射成跳转目标（纯函数）。
///
/// 参数按种类收窄：练习只带题号、复习只带卡片数、补齐思维链只带动作 key；
/// 不读 [DailyPlanStep] 的标题 / 说明 / 预计分钟等展示字段。
DailyPlanStepDestination destinationOf(DailyPlanStep step) {
  switch (step.kind) {
    case DailyPlanStepKind.practiceQuestions:
      return DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.practiceQuestions,
        questionIds: step.questionIds,
      );
    case DailyPlanStepKind.reviewDueCards:
      return DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.ankiReview,
        cardCount: step.cardCount,
      );
    case DailyPlanStepKind.collectChains:
      return DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.collectChains,
        actionType: step.actionType,
      );
    case DailyPlanStepKind.reviewVocabulary:
      return DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.vocabulary,
      );
    case DailyPlanStepKind.keepGoing:
      return DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.keepGoing,
      );
    case DailyPlanStepKind.noData:
      return DailyPlanStepDestination(
        kind: DailyPlanDestinationKind.none,
      );
  }
}

List<String> _normalizeIds(Iterable<String> rawIds) {
  final normalized = <String>[];
  for (final raw in rawIds) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || normalized.contains(trimmed)) {
      continue;
    }
    normalized.add(trimmed);
  }
  return normalized;
}

bool _sameIds(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
