import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cloze/cloze_engine.dart';
import 'package:furnace/domain/services/cloze/forced_loop.dart';

/// 会话内强制绑定闭环的纯决策测试。
///
/// 这里的每一条都对应两份既有口径里已经写死的行为，不是新规则：
/// * 位置口径：`ReviewService.buildQueue`
///   （app/lib/features/anki/application/review_service.dart:271-282，`_interleave` :378-391，
///   `relearnGapCards = 3` :225）；
/// * 时间口径：`ForcedStep.nextDueAt`
///   （app/lib/domain/services/cloze/cloze_engine.dart:211-257，`now + relearnMinutes`）；
/// * 产品口径：`docs/FEATURE_MATRIX.md` D11「答错立即重做 → 约 10 分钟短间隔再出现 → 连续两次正确解除」。
///
/// 本文件把「两份口径的差异」固定成了一个显式选择：**两个门都过，取下限更晚者**
/// （`immediateRedo` 那一张只受位置约束，之后的强制重现同时受 gap 与 `nextDueAt` 约束）。
void main() {
  final now = DateTime(2026, 9, 7, 20);

  group('ForcedLoop.reinsertAfter', () {
    test('答错（immediateRedo）时同一张卡立刻排回用户眼前', () {
      final plan = ForcedLoop.reinsertAfter<int>(
        item: 7,
        stillForced: true,
        immediateRedo: true,
        nextDueAt: now.add(const Duration(minutes: 10)),
        currentIndex: 2,
        queueLength: 9,
        gap: 3,
      );

      expect(plan, isNotNull);
      expect(plan!.item, 7);
      // 位置口径：紧跟在当前这张之后，而不是 gap 张之后。
      expect(plan.insertIndex, 3);
      expect(plan.immediate, isTrue);
      // 立即重做那一次不受 10 分钟下限约束（D11 写的是「立即重做」）。
      expect(plan.notBefore, isNull);
      expect(plan.gated, isFalse);
      expect(plan.visibleAt(now), isTrue);
      expect(plan.waitRemaining(now), Duration.zero);
    });

    test('答对但仍在强制期内：排到 gap 张之后，且到点前不出现', () {
      final floor = now.add(const Duration(minutes: 10));
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
      expect(plan.immediate, isFalse);
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

    test('连续两次答对解除绑定后不再插回队列', () {
      final plan = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: false,
        immediateRedo: false,
        nextDueAt: null,
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
        nextDueAt: now.add(const Duration(minutes: 10)),
        currentIndex: 5,
        queueLength: 6,
        gap: 3,
      );
      expect(plan, isNull);
    });

    test('队列尾部不会越界（立即重做 / gap 两种情况都夹到队尾）', () {
      final immediate = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: true,
        immediateRedo: true,
        nextDueAt: now,
        currentIndex: 3,
        queueLength: 4,
        gap: 3,
      );
      expect(immediate!.insertIndex, 4);

      final gapped = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: true,
        immediateRedo: false,
        nextDueAt: now.add(const Duration(minutes: 10)),
        currentIndex: 3,
        queueLength: 4,
        gap: 3,
      );
      expect(gapped!.insertIndex, 4);
    });

    test('gap 为 0 时排在当前这张之后；负数按 0 处理', () {
      final zero = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: true,
        immediateRedo: false,
        nextDueAt: now.add(const Duration(minutes: 10)),
        currentIndex: 1,
        queueLength: 8,
        gap: 0,
      );
      expect(zero!.insertIndex, 2);

      final negative = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: true,
        immediateRedo: false,
        nextDueAt: now.add(const Duration(minutes: 10)),
        currentIndex: 1,
        queueLength: 8,
        gap: -5,
      );
      expect(negative!.insertIndex, 2);
    });

    test('空队列 / 负数下标等退化输入不抛异常', () {
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

      final negative = ForcedLoop.reinsertAfter<int>(
        item: 1,
        stillForced: true,
        immediateRedo: false,
        nextDueAt: now,
        currentIndex: -3,
        queueLength: 4,
        gap: 3,
      );
      expect(negative!.insertIndex, 4);
    });

    test('同一输入重复调用结果完全一致（确定性）', () {
      ForcedRedoPlan<int>? call() => ForcedLoop.reinsertAfter<int>(
            item: 9,
            stillForced: true,
            immediateRedo: false,
            nextDueAt: now.add(const Duration(minutes: 10)),
            currentIndex: 2,
            queueLength: 9,
            gap: 3,
          );

      final a = call()!;
      final b = call()!;
      expect(a.insertIndex, b.insertIndex);
      expect(a.immediate, b.immediate);
      expect(a.notBefore, b.notBefore);
      expect(a.item, b.item);
    });
  });

  group('ForcedLoop.mayShow / waitRemaining', () {
    test('没有时间下限就永远可显示', () {
      expect(ForcedLoop.mayShow(now: now, notBefore: null), isTrue);
      expect(
          ForcedLoop.waitRemaining(now: now, notBefore: null), Duration.zero);
    });

    test('到点前不可显示，到点后可显示', () {
      final floor = now.add(const Duration(minutes: 10));
      expect(ForcedLoop.mayShow(now: now, notBefore: floor), isFalse);
      expect(ForcedLoop.mayShow(now: floor, notBefore: floor), isTrue);
      expect(
          ForcedLoop.mayShow(
              now: floor.add(const Duration(seconds: 1)), notBefore: floor),
          isTrue);
    });

    test('待等时长取整到分钟（向上），到点后为零', () {
      final floor = now.add(const Duration(minutes: 10));
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

  group('与 ForcedMachine 的既有口径对齐', () {
    test('答错 → 立即重做；答对一次 → gap + 10 分钟；答对两次 → 解除', () {
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
      expect(wrong.nextDueAt, now.add(const Duration(minutes: 10)));

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
      expect(plan.notBefore, now.add(const Duration(minutes: 10)));

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
}
