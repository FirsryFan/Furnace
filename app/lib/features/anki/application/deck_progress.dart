/// 卡组当日进度换算（纯逻辑，不读数据库、不 import Flutter）。
///
/// 输入是 `ReviewGroupLoad`（定义见
/// `app/lib/data/repositories/review_plan_repository.dart:438`），
/// 输出是给卡组行 / 卡组列表直接展示的进度视图。
///
/// 语义（写死在这里，UI 里不要再推导一遍）：
/// * 新卡目标 = 今天已做新卡 + 今天剩余新卡额度；新卡额度永远有上限，
///   `newCardsPerDay == 0` 表示今天不学新卡，不是不限；
/// * 复习目标 = 今天已做复习 + 剩余复习额度；剩余额度为 null 表示复习不限，
///   此时 [DeckProgress.reviewTarget] 为 null、[DeckProgress.reviewComplete] 恒为 false；
/// * **复习不限的卡组永远不算今日完成**：没有上限就没有完成线；
/// * 进度条分母只统计有上限的部分（新卡目标 + 复习目标；复习不限时只加新卡目标），
///   分母为 0 时 [DeckProgress.fraction] 为 null，由 UI 决定怎么显示；
/// * fraction 夹在 0..1：超额完成显示满格，不越界。
library;

import '../../../data/repositories/review_plan_repository.dart';

/// 一个卡组今天的学习进度。
class DeckProgress {
  const DeckProgress({
    required this.newDone,
    required this.newTarget,
    required this.reviewDone,
    required this.reviewTarget,
    required this.newComplete,
    required this.reviewComplete,
    required this.isComplete,
    required this.fraction,
  });

  /// 今天已完成的新卡数。
  final int newDone;

  /// 今天的新卡目标（已做 + 剩余）。
  final int newTarget;

  /// 今天已完成的复习数。
  final int reviewDone;

  /// 今天的复习目标；null 表示复习不限。
  final int? reviewTarget;

  /// 新卡是否达到今日目标。
  final bool newComplete;

  /// 复习是否达到今日目标；复习不限时恒为 false。
  final bool reviewComplete;

  /// 今日整体是否完成 = 新卡完成且复习额度（非不限）已用尽。
  final bool isComplete;

  /// 给进度条用的 0..1 比例；没有有上限的目标（分母为 0）时为 null。
  final double? fraction;
}

/// 把 [ReviewGroupLoad] 换算成展示用的 [DeckProgress]。
DeckProgress deckProgressFor(ReviewGroupLoad group) {
  final newDone = group.newDoneToday;
  final newTarget = newDone + group.newRemaining;
  final reviewDone = group.reviewDoneToday;
  final remainingReviews = group.remainingReviews;
  final reviewTarget =
      remainingReviews == null ? null : reviewDone + remainingReviews;
  final newComplete = group.newRemaining == 0;
  final reviewComplete = reviewTarget != null && reviewDone >= reviewTarget;
  final isComplete = group.newRemaining == 0 &&
      remainingReviews != null &&
      remainingReviews == 0;
  final denominator = newTarget + (reviewTarget ?? 0);
  double? fraction;
  if (denominator > 0) {
    fraction =
        ((newDone + reviewDone) / denominator).clamp(0.0, 1.0).toDouble();
  }
  return DeckProgress(
    newDone: newDone,
    newTarget: newTarget,
    reviewDone: reviewDone,
    reviewTarget: reviewTarget,
    newComplete: newComplete,
    reviewComplete: reviewComplete,
    isComplete: isComplete,
    fraction: fraction,
  );
}
