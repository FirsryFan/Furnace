/// 会话内「错题强制绑定」闭环的纯决策逻辑（无 Flutter、无数据库、无副作用）。
///
/// ## 当前口径（2026-10-18 用户原话）
///
/// 「错题先空 2–3 张再重现；如果每日任务到了最后没有空的卡了，就只能连续重复出现。」
///
/// 落到本文件就是两条：
///
/// * **刚答错**的那一张：按位置排到 `currentIndex + 1 + gap`（夹在队尾），
///   **不**再叠 10 分钟时间下限——用户否掉了「原地立刻重复」，但间隔本身
///   已经够短，位置口径已经说明了它什么时候回来；
/// * **仍然被绑定、但已经答对一次**的那一张：同样排到
///   `currentIndex + 1 + gap`，并且受 `ForcedStep.nextDueAt` 的 10 分钟下限
///   约束（见 cloze_engine.dart 的 `ForcedMachine.grade`：`now + relearnMinutes`，
///   默认 10 分钟，来自 furnace_defaults.dart 的 `forcedRelearnMinutes`）。
///
/// 队列剩余不足 `gap` 张时 `insertIndex` 被夹到 `queueLength`：这张卡接在
/// 队尾之后出现，队列只有 1 张时就是连续重复——这正是「末尾没有空卡了才
/// 连续」的语义。
///
/// `gap` 由调用方传入（当前唯一来源：`ReviewService.relearnGapCards = 3`，
/// 见 app/lib/features/anki/application/review_service.dart 的 `buildQueue` /
/// `_interleave`）；本文件只保留一个**产品口径下限**
/// [kMinForcedRedoGapCards] = 2，防止调用方传 0/负数时退化成原地重复
/// （用户口径是「空两到三张」）。
///
/// ## 与旧口径的关系
///
/// 旧口径把产品口径 D11「答错立即重做」实现成 `insertIndex = currentIndex + 1`
/// （紧跟当前这张，不套 10 分钟门）。用户 2026-10-18 明确改掉了这一点：错题
/// 不再紧跟当前这张，而是先空 2–3 张。`immediateRedo` 这个**入参名**为了不改
/// 调用方暂时沿用（review_page.dart 不在本次改动的写作用域内），语义收敛成
/// 「这一次是刚答错，因此不套 [notBefore] 时间下限」；排位决策里对应的字段
/// 已经改名为 [ForcedRedoPlan.timeGated]，避免留下错名。
///
/// 产品文档 D11（docs/FEATURE_MATRIX.md）的旧描述由 Lead 统一改；本文件只负责
/// 把**代码行为**固定成用户最新口径。
library;

/// 错题重现的最小间隔（张）：用户口径「错题先空 2–3 张」，所以下限是 2。
///
/// 这是**产品口径下限**，不是默认值；默认间隔仍然只由调用方传入
/// （`ReviewService.relearnGapCards`，当前 = 3），避免出现第二处默认值真相。
const int kMinForcedRedoGapCards = 2;

/// 一次「把刚答过的卡插回本轮队列」的排位决策。
///
/// 纯数据，泛型只为了不依赖 `ReviewItem`（调用方传 `ReviewItem`，测试里可以传 `int`/`String`）。
class ForcedRedoPlan<T> {
  const ForcedRedoPlan({
    required this.item,
    required this.insertIndex,
    required this.timeGated,
    required this.notBefore,
  });

  /// 要插回队列的那张卡（与传入的 `item` 是同一个对象）。
  final T item;

  /// 插回**去掉当前这张之后**的队列里的下标（已夹在 `[0, queueLength]`）。
  ///
  /// 下标 `currentIndex + 1 + gap` 意味着「当前这张之后还有 gap 张卡，然后才轮到它」。
  final int insertIndex;

  /// 这一次是否套用 [notBefore] 时间下限。
  ///
  /// * 刚答错：`false`（位置已经隔开，不叠加 10 分钟门）；
  /// * 答对一次、仍在绑定期内：`true`。
  final bool timeGated;

  /// 早于此时刻不允许显示；`null` 表示立刻可见。
  final DateTime? notBefore;

  /// 是否真的受时间下限约束（`timeGated` 且拿到了 [notBefore]）。
  bool get gated => timeGated && notBefore != null;

  /// 此刻能否把这张卡放出来。
  bool visibleAt(DateTime now) =>
      ForcedLoop.mayShow(now: now, notBefore: timeGated ? notBefore : null);

  /// 还要等多久（向上取整到分钟；可显示时为 [Duration.zero]）。
  Duration waitRemaining(DateTime now) => ForcedLoop.waitRemaining(
      now: now, notBefore: timeGated ? notBefore : null);
}

/// 会话内强制重做的排位规则。
abstract final class ForcedLoop {
  /// 根据一次作答之后的 `ForcedStep`（cloze_engine.dart 的 `ForcedMachine.grade`）
  /// 决定要不要把这张卡插回本轮队列。
  ///
  /// 返回 `null` = 不插回（已经解除绑定，或本来就没被绑定）。
  ///
  /// [currentIndex] 是刚答完这张卡在**插入前**队列里的下标；
  /// [queueLength] 是插入前队列长度；[gap] 由调用方传入
  /// `ReviewService.relearnGapCards`（= 3），这里不做默认值，避免第二处真相；
  /// 但小于 [kMinForcedRedoGapCards] 的值会被抬到 2（用户口径「先空两到三张」）。
  ///
  /// [immediateRedo] 沿用 `ReviewOutcome.immediateRedo` 的旧名字，语义是
  /// 「这一次是刚答错」：位置同样隔 [gap] 张，但**不**套 [nextDueAt] 时间下限。
  /// 答对一次、仍在绑定期内则位置隔 [gap] 张且套 [nextDueAt]。
  static ForcedRedoPlan<T>? reinsertAfter<T>({
    required T item,
    required bool stillForced,
    required bool immediateRedo,
    required DateTime? nextDueAt,
    required int currentIndex,
    required int queueLength,
    required int gap,
  }) {
    if (!stillForced) return null;

    final length = queueLength < 0 ? 0 : queueLength;
    final index = currentIndex < 0 ? 0 : currentIndex;
    final spacing = _spacing(gap);

    return ForcedRedoPlan<T>(
      item: item,
      insertIndex: _clamp(index + 1 + spacing, 0, length),
      timeGated: !immediateRedo,
      notBefore: immediateRedo ? null : nextDueAt,
    );
  }

  /// 时间下限是否已放行（`notBefore == null` 视为没有下限）。
  static bool mayShow({required DateTime now, DateTime? notBefore}) {
    if (notBefore == null) return true;
    return !now.isBefore(notBefore);
  }

  /// 距离放行还有多久；已放行返回 [Duration.zero]。
  ///
  /// 取整到分钟并向上取整：界面上「还有 0 分钟」没有意义，
  /// 还剩 1 秒也要如实报「还有 1 分钟」。
  static Duration waitRemaining({required DateTime now, DateTime? notBefore}) {
    if (notBefore == null) return Duration.zero;
    final left = notBefore.difference(now);
    if (left <= Duration.zero) return Duration.zero;
    final minutes = (left.inSeconds + 59) ~/ 60;
    return Duration(minutes: minutes);
  }

  static int _spacing(int gap) =>
      gap < kMinForcedRedoGapCards ? kMinForcedRedoGapCards : gap;

  static int _clamp(int value, int low, int high) {
    if (value < low) return low;
    if (value > high) return high;
    return value;
  }
}
