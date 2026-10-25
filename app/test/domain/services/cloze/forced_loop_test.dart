import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cloze/cloze_engine.dart';
import 'package:furnace/domain/services/cloze/forced_loop.dart';

/// 会话内强制绑定闭环的纯决策测试。
///
/// 当前口径（2026-10-18 用户原话）：
/// 「错题先空 2–3 张再重现；如果每日任务到了最后没有空的卡了，就只能连续重复出现。」
///
/// 对应到代码：
/// * 刚答错 → 位置 `currentIndex + 1 + gap`（夹到队尾），**不**套 10 分钟门；
/// * 答对一次但仍在绑定期内 → 同样隔 `gap` 张，并且受 `nextDueAt` 的
///   10 分钟下限约束（`ForcedMachine.grade` 里 `now + relearnMinutes`）；
/// * `gap` 由调用方传入（`ReviewService.relearnGapCards = 3`），本文件只有
///   产品下限 [kMinForcedRedoGapCards] = 2，防止传 0/负数时退化成原地重复。
///
/// 旧口径里「答错立即重做 = 紧跟当前这张」已被用户改掉；这里保留的
/// `immediateRedo` 入参名只表示「这一次是刚答错」。
void main() {
  final now = DateTime(2026, 9, 7, 20);
  final floor = now.add(const Duration(minutes: 10));

  group('ForcedLoop.reinsertAfter：位置口径（错题先空 gap 张）', () {
    test('队中答错 gap=3：隔 3 张再出现，不套 10 分钟门', () {
      final plan = ForcedLoop.reinsertAfter<int>(
        item: 7,
        stillForced: true,
        immediateRedo: true,
        nextDueAt: floor,
        currentIndex: 2,
        queueLength: 9,
        gap: 3,
      );

      expect(plan, isNotNull);
      expect(plan!.item, 7);
      // currentIndex + 1 + gap：当前这张之后还有 3 张，然后才是它。
      expect(plan.insertIndex, 6);
      expect(plan.timeGated, isFalse);
      // 刚答错那一次不受 10 分钟下限约束（即使引擎给了 nextDueAt 也不采用）。
      expect(plan.notBefore, isNull);
      expect(plan.gated, isFalse);
      expect(plan.visibleAt(now), isTrue);
      expect(plan.waitRemaining(now), Duration.zero);
    });

    test('队首答错 gap=3：仍然空 3 张（0 + 1 + 3）', () {
      final plan = ForcedLoop.reinsertAfter<int>(
        item: 0,
        stillForced: true,
        immediateRedo: true,
        nextDueAt: floor,
        currentIndex: 0,
        queueLength: 9,
        gap: 3,
      );

      expect(plan!.insertIndex, 4);
      expect(plan.timeGated, isFalse);
      expect(plan.notBefore, isNull);
    });

    test('队尾不足 gap 张：夹到 queueLength，接在队尾之后出现', () {
      final plan = ForcedLoop.reinsertAfter<int>(
        item: 3,
        stillForced: true,
        immediateRedo: true,
        nextDueAt: floor,
        currentIndex: 7,
        queueLength: 9,
        gap: 3,
      );

      // 7 + 1 + 3 = 11 > 9 → 放到末尾，等于「后面没卡了就连续/紧接」。
      expect(plan!.insertIndex, 9);
      expect(plan.insertIndex, plan.insertIndex.clamp(0, 9));
    });

    test('队列只剩 1 张（只有当前这张）时退化成连续重复', () {
      final plan = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: true,
        immediateRedo: true,
        nextDueAt: floor,
        currentIndex: 0,
        queueLength: 1,
        gap: 3,
      );

      // 0 + 1 + 3 = 4 → 夹到 1：插入后队列长度 2，advance 后它就在队首。
      expect(plan!.insertIndex, 1);
      expect(plan.timeGated, isFalse);
    });

    test('队列 2 张：当前在队首/队尾都夹到队尾', () {
      final head = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: true,
        immediateRedo: true,
        nextDueAt: floor,
        currentIndex: 0,
        queueLength: 2,
        gap: 3,
      );
      expect(head!.insertIndex, 2);

      final tail = ForcedLoop.reinsertAfter<int>(
        item: 2,
        stillForced: true,
        immediateRedo: true,
        nextDueAt: floor,
        currentIndex: 1,
        queueLength: 2,
        gap: 3,
      );
      expect(tail!.insertIndex, 2);
    });

    test('gap=2 与 gap=3 各自生效（用户口径「空 2–3 张」）', () {
      final gap2 = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: true,
        immediateRedo: true,
        nextDueAt: floor,
        currentIndex: 2,
        queueLength: 9,
        gap: 2,
      );
      expect(gap2!.insertIndex, 5);

      final gap3 = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: true,
        immediateRedo: true,
        nextDueAt: floor,
        currentIndex: 2,
        queueLength: 9,
        gap: 3,
      );
      expect(gap3!.insertIndex, 6);
    });

    test('gap=0 / 负数 / 1 都被抬到产品下限 2，不原地重复', () {
      expect(kMinForcedRedoGapCards, 2);
      for (final gap in [0, -5, 1]) {
        final plan = ForcedLoop.reinsertAfter<int>(
          item: 1,
          stillForced: true,
          immediateRedo: true,
          nextDueAt: floor,
          currentIndex: 1,
          queueLength: 8,
          gap: gap,
        );
        // 1 + 1 + 2 = 4：至少空 2 张。
        expect(plan!.insertIndex, 4, reason: 'gap=$gap 应被抬到 2');
      }
    });

    test('连续错两次：两次都按 gap 排位、都不套时间门；绑定不解除', () {
      // 第一次答错：3 张队列，当前第 2 张。
      final first = ForcedLoop.reinsertAfter<int>(
        item: 9,
        stillForced: true,
        immediateRedo: true,
        nextDueAt: floor,
        currentIndex: 1,
        queueLength: 3,
        gap: 3,
      );
      // 1 + 1 + 3 = 5 → 夹到 3（队尾）。
      expect(first!.insertIndex, 3);
      expect(first.timeGated, isFalse);

      // 插回后队列 4 张，下一次它重复到眼前时在队尾，再答错。
      final second = ForcedLoop.reinsertAfter<int>(
        item: 9,
        stillForced: true,
        immediateRedo: true,
        nextDueAt: floor,
        currentIndex: 3,
        queueLength: 4,
        gap: 3,
      );
      expect(second!.insertIndex, 4);
      expect(second.timeGated, isFalse);
      expect(second.notBefore, isNull);

      // 与状态机对齐：连续两次答错都仍是绑定态、都要回来。
      final wrong = ForcedMachine.grade(
        correct: false,
        forcedBefore: true,
        streakBefore: 0,
        now: now,
        relearnMinutes: 10,
        releaseStreak: 2,
      );
      expect(wrong.forced, isTrue);
      expect(wrong.immediateRedo, isTrue);
      expect(wrong.released, isFalse);
    });

    test('gap 很大时夹到队尾，不越界', () {
      final plan = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: true,
        immediateRedo: true,
        nextDueAt: floor,
        currentIndex: 2,
        queueLength: 5,
        gap: 10,
      );
      expect(plan!.insertIndex, 5);
    });

    test('空队列 / 负数下标 / 负队列长度等退化输入不抛异常', () {
      final empty = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: true,
        immediateRedo: false,
        nextDueAt: now,
        currentIndex: 0,
        queueLength: 0,
        gap: 3,
      );
      expect(empty!.insertIndex, 0);

      final negativeIndex = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: true,
        immediateRedo: false,
        nextDueAt: now,
        currentIndex: -3,
        queueLength: 4,
        gap: 3,
      );
      // 下标按 0 处理：0 + 1 + 3 = 4（夹到队列长度）。
      expect(negativeIndex!.insertIndex, 4);

      final negativeLength = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: true,
        immediateRedo: false,
        nextDueAt: now,
        currentIndex: 0,
        queueLength: -2,
        gap: 3,
      );
      expect(negativeLength!.insertIndex, 0);
    });

    test('同一输入重复调用结果完全一致（确定性）', () {
      ForcedRedoPlan<int>? call() => ForcedLoop.reinsertAfter<int>(
            item: 9,
            stillForced: true,
            immediateRedo: false,
            nextDueAt: floor,
            currentIndex: 2,
            queueLength: 9,
            gap: 3,
          );

      final a = call()!;
      final b = call()!;
      expect(a.insertIndex, b.insertIndex);
      expect(a.timeGated, b.timeGated);
      expect(a.notBefore, b.notBefore);
      expect(a.item, b.item);
    });
  });

  group('ForcedLoop.reinsertAfter：时间口径（答对一次后 10 分钟门不变）', () {
    test('答对但仍在强制期内：同样隔 gap 张，且到点前不出现', () {
      final plan = ForcedLoop.reinsertAfter<String>(
        item: 'c0',
        stillForced: true,
        immediateRedo: false,
        nextDueAt: floor,
        currentIndex: 2,
        queueLength: 9,
        gap: 3,
      );

      expect(plan, isNotNull);
      expect(plan!.item, 'c0');
      expect(plan.insertIndex, 6); // currentIndex + 1 + gap
      expect(plan.timeGated, isTrue);
      expect(plan.notBefore, floor);
      expect(plan.gated, isTrue);
      expect(plan.visibleAt(now), isFalse);
      expect(
          plan.visibleAt(floor.subtract(const Duration(minutes: 1))), isFalse);
      expect(plan.visibleAt(floor), isTrue); // 到点即可见（含等于）
      expect(plan.waitRemaining(now), const Duration(minutes: 10));
      expect(plan.waitRemaining(floor.add(const Duration(minutes: 5))),
          Duration.zero);
    });

    test('答错与答对一次位置一致，只差时间门（同一 gap 下）', () {
      final wrong = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: true,
        immediateRedo: true,
        nextDueAt: floor,
        currentIndex: 2,
        queueLength: 9,
        gap: 3,
      )!;
      final correct = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: true,
        immediateRedo: false,
        nextDueAt: floor,
        currentIndex: 2,
        queueLength: 9,
        gap: 3,
      )!;

      expect(wrong.insertIndex, correct.insertIndex);
      expect(wrong.notBefore, isNull);
      expect(correct.notBefore, floor);
      expect(wrong.gated, isFalse);
      expect(correct.gated, isTrue);
    });

    test('时间门没有给到 nextDueAt（null）时不显示等待', () {
      final plan = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: true,
        immediateRedo: false,
        nextDueAt: null,
        currentIndex: 2,
        queueLength: 9,
        gap: 3,
      )!;
      expect(plan.timeGated, isTrue);
      expect(plan.notBefore, isNull);
      expect(plan.gated, isFalse);
      expect(plan.visibleAt(now), isTrue);
    });

    test('连续两次答对解除绑定后不再插回队列', () {
      final plan = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: false,
        immediateRedo: false,
        nextDueAt: floor,
        currentIndex: 0,
        queueLength: 3,
        gap: 3,
      );
      expect(plan, isNull);
    });

    test('本来就没被强制绑定的卡不会插回', () {
      final plan = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: false,
        immediateRedo: false,
        nextDueAt: floor,
        currentIndex: 5,
        queueLength: 6,
        gap: 3,
      );
      expect(plan, isNull);
    });
  });

  group('ForcedRedoPlan：timeGated 直接决定时间门语义', () {
    test('timeGated=false 时即使带 notBefore 也立刻可见', () {
      final plan = ForcedRedoPlan<int>(
        item: 1,
        insertIndex: 2,
        timeGated: false,
        notBefore: floor,
      );
      expect(plan.gated, isFalse);
      expect(plan.visibleAt(now), isTrue);
      expect(plan.waitRemaining(now), Duration.zero);
    });

    test('timeGated=true 且 notBefore 非空时按时间下限等', () {
      final plan = ForcedRedoPlan<int>(
        item: 1,
        insertIndex: 2,
        timeGated: true,
        notBefore: floor,
      );
      expect(plan.gated, isTrue);
      expect(plan.visibleAt(now), isFalse);
      expect(plan.waitRemaining(now), const Duration(minutes: 10));
    });
  });

  group('ForcedLoop.mayShow / waitRemaining', () {
    test('没有时间下限就永远可显示', () {
      expect(ForcedLoop.mayShow(now: now, notBefore: null), isTrue);
      expect(
          ForcedLoop.waitRemaining(now: now, notBefore: null), Duration.zero);
    });

    test('到点前不可显示，到点后可显示', () {
      expect(ForcedLoop.mayShow(now: now, notBefore: floor), isFalse);
      expect(ForcedLoop.mayShow(now: floor, notBefore: floor), isTrue);
      expect(
          ForcedLoop.mayShow(
              now: floor.add(const Duration(seconds: 1)), notBefore: floor),
          isTrue);
    });

    test('待等时长取整到分钟（向上），到点后为零', () {
      expect(ForcedLoop.waitRemaining(now: now, notBefore: floor),
          const Duration(minutes: 10));
      // 还剩 9 分 30 秒 → 报 10 分钟；还剩 30 秒 → 报 1 分钟（界面不报「还有 0 分钟」）。
      expect(
        ForcedLoop.waitRemaining(
          now: floor.subtract(const Duration(minutes: 9, seconds: 30)),
          notBefore: floor,
        ),
        const Duration(minutes: 10),
      );
      expect(
        ForcedLoop.waitRemaining(
            now: floor.subtract(const Duration(seconds: 30)), notBefore: floor),
        const Duration(minutes: 1),
      );
      expect(ForcedLoop.waitRemaining(now: floor, notBefore: floor),
          Duration.zero);
    });
  });

  group('与 ForcedMachine 对齐（新口径）', () {
    test('答错 → 隔 gap 张、无时间门；答对一次 → gap + 10 分钟；答对两次 → 解除', () {
      final wrong = ForcedMachine.grade(
        correct: false,
        forcedBefore: false,
        streakBefore: 0,
        now: now,
        relearnMinutes: 10,
        releaseStreak: 2,
      );
      expect(wrong.forced, isTrue);
      expect(wrong.immediateRedo, isTrue);
      expect(wrong.nextDueAt, floor); // 引擎仍然给 10 分钟后的时刻
      final wrongPlan = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: wrong.forced,
        immediateRedo: wrong.immediateRedo,
        nextDueAt: wrong.nextDueAt,
        currentIndex: 0,
        queueLength: 5,
        gap: 3,
      )!;
      // 位置隔 gap；时间门不套用（引擎的 nextDueAt 只对「答对一次」生效）。
      expect(wrongPlan.insertIndex, 4);
      expect(wrongPlan.notBefore, isNull);
      expect(wrongPlan.gated, isFalse);

      final first = ForcedMachine.grade(
        correct: true,
        forcedBefore: true,
        streakBefore: 0,
        now: now,
        relearnMinutes: 10,
        releaseStreak: 2,
      );
      expect(first.forced, isTrue);
      expect(first.immediateRedo, isFalse);
      final plan = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: first.forced,
        immediateRedo: first.immediateRedo,
        nextDueAt: first.nextDueAt,
        currentIndex: 0,
        queueLength: 5,
        gap: 3,
      )!;
      expect(plan.insertIndex, 4);
      expect(plan.notBefore, floor);
      expect(plan.gated, isTrue);

      final second = ForcedMachine.grade(
        correct: true,
        forcedBefore: true,
        streakBefore: 1,
        now: now,
        relearnMinutes: 10,
        releaseStreak: 2,
      );
      expect(second.released, isTrue);
      expect(second.forced, isFalse);
      expect(
        ForcedLoop.reinsertAfter<int>(
          item: 1,
          stillForced: second.forced,
          immediateRedo: second.immediateRedo,
          nextDueAt: second.nextDueAt,
          currentIndex: 0,
          queueLength: 5,
          gap: 3,
        ),
        isNull,
      );
    });
  });

  group('ForcedLoop.mayReinsert：会话内重插上限', () {
    test('默认上限是 2 次', () {
      expect(kMaxForcedReinsertsPerSession, 2);
    });

    test('本轮 0 次 / 1 次：仍允许重插', () {
      expect(ForcedLoop.mayReinsert(reinsertsSoFar: 0), isTrue);
      expect(ForcedLoop.mayReinsert(reinsertsSoFar: 1), isTrue);
    });

    test('本轮 2 次 / 3 次：已经不允许重插', () {
      expect(ForcedLoop.mayReinsert(reinsertsSoFar: 2), isFalse);
      expect(ForcedLoop.mayReinsert(reinsertsSoFar: 3), isFalse);
    });

    test('负数按 0 处理：仍允许', () {
      expect(ForcedLoop.mayReinsert(reinsertsSoFar: -1), isTrue);
      expect(ForcedLoop.mayReinsert(reinsertsSoFar: -100), isTrue);
    });

    test('自定义 max=5：4 允许、5 不允许', () {
      expect(ForcedLoop.mayReinsert(reinsertsSoFar: 4, max: 5), isTrue);
      expect(ForcedLoop.mayReinsert(reinsertsSoFar: 5, max: 5), isFalse);
    });

    test('max=0 一律不允许', () {
      expect(ForcedLoop.mayReinsert(reinsertsSoFar: 0, max: 0), isFalse);
      expect(ForcedLoop.mayReinsert(reinsertsSoFar: -3, max: 0), isFalse);
    });

    test('max 为负数时也不允许（防御性）', () {
      expect(ForcedLoop.mayReinsert(reinsertsSoFar: 0, max: -1), isFalse);
    });
  });
}
