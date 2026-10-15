/// 会话内「错题强制绑定」闭环的纯决策逻辑（无 Flutter、无数据库、无副作用）。
///
/// ## 这个文件解决的口径差异（显式选择，不是新规则）
///
/// 仓库里关于「答错的空什么时候再出现」本来有两份口径：
///
/// 1. **位置口径** —— `ReviewService.buildQueue`
///    （app/lib/features/anki/application/review_service.dart:271-282）只把
///    `cardState.forced == 1` 的卡挑出来，交给 `_interleave`
///    （同文件 :378-391）按 `relearnGapCards = 3`（同文件 :225）安插；
///    它**完全不看 `dueAt`**。
/// 2. **时间口径** —— `ForcedStep.nextDueAt`
///    （app/lib/domain/services/cloze/cloze_engine.dart:211-257）在每次仍然被绑定时给出
///    `now + relearnMinutes`（默认 10 分钟，见 furnace_defaults.dart 的
///    `forcedRelearnMinutes`）。
///
/// 产品口径 D11（docs/FEATURE_MATRIX.md）写的是
/// 「答错立即重做 → 约 10 分钟短间隔再出现 → 连续两次正确解除」。
///
/// 本文件的取舍是 **两个门都过、取下限更晚者**：
///
/// * `immediateRedo == true`（刚答错）那一张**只受位置约束**，紧跟在当前这张后面
///   （`currentIndex + 1`），不套 10 分钟下限——这就是 D11 的「立即重做」；
/// * 仍然被绑定、但已经答对一次的那一次，位置按 `gap`（调用方传入
///   `ReviewService.relearnGapCards`）排在 `currentIndex + 1 + gap`，时间按
///   `nextDueAt` 卡在 10 分钟之后。
///
/// 两处代码位置就是上面引的 :271-282 / :378-391 与 cloze_engine.dart:211-257。
/// 这是把两份既有实现之间的差异**固定下来**，而不是引入第三条规则。
library;

/// 一次「把刚答过的卡插回本轮队列」的排位决策。
///
/// 纯数据，泛型只为了不依赖 `ReviewItem`（调用方传 `ReviewItem`，测试里可以传 `int`/`String`）。
class ForcedRedoPlan<T> {
  const ForcedRedoPlan({
    required this.item,
    required this.insertIndex,
    required this.immediate,
    required this.notBefore,
  });

  /// 要插回队列的那张卡（与传入的 `item` 是同一个对象）。
  final T item;

  /// 插回**去掉当前这张之后**的队列里的下标（已夹在 `[0, queueLength]`）。
  final int insertIndex;

  /// 是否为 D11 的「立即重做」那一次（不受时间下限约束）。
  final bool immediate;

  /// 早于此时刻不允许显示；`null` 表示立刻可见。
  final DateTime? notBefore;

  /// 是否受时间下限约束（立即重做那一次为 `false`）。
  bool get gated => !immediate && notBefore != null;

  /// 此刻能否把这张卡放出来。
  bool visibleAt(DateTime now) =>
      ForcedLoop.mayShow(now: now, notBefore: immediate ? null : notBefore);

  /// 还要等多久（向上取整到分钟；可显示时为 [Duration.zero]）。
  Duration waitRemaining(DateTime now) => ForcedLoop.waitRemaining(
      now: now, notBefore: immediate ? null : notBefore);
}

/// 会话内强制重做的排位规则。
abstract final class ForcedLoop {
  /// 根据一次作答之后的 `ForcedStep`（cloze_engine.dart:211-257）决定要不要把这张卡插回本轮队列。
  ///
  /// 返回 `null` = 不插回（已经解除绑定，或本来就没被绑定）。
  ///
  /// [currentIndex] 是刚答完这张卡在**插入前**队列里的下标；
  /// [queueLength] 是插入前队列长度；[gap] 由调用方传入
  /// `ReviewService.relearnGapCards`（= 3），这里不做默认值，避免第二处真相。
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
    final spacing = gap < 0 ? 0 : gap;

    if (immediateRedo) {
      return ForcedRedoPlan<T>(
        item: item,
        insertIndex: _clamp(index + 1, 0, length),
        immediate: true,
        notBefore: null,
      );
    }

    return ForcedRedoPlan<T>(
      item: item,
      insertIndex: _clamp(index + 1 + spacing, 0, length),
      immediate: false,
      notBefore: nextDueAt,
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

  static int _clamp(int value, int low, int high) {
    if (value < low) return low;
    if (value > high) return high;
    return value;
  }
}
