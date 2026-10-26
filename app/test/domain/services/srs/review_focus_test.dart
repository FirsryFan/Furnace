import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/srs/review_focus.dart';

/// 这个文件钉住「考前提前复习」的判定口径：哪些卡会被拉、哪些一律不动、
/// 排序与截断是否确定。纯逻辑，不碰数据库（落库与 undo 在
/// test/features/ai/review_focus_tool_test.dart）。
void main() {
  final now = DateTime(2026, 10, 26, 20);
  final nowMs = now.millisecondsSinceEpoch;

  /// 一张「已学过、未来 [offset] 到期」的卡。
  ReviewFocusCard learned(
    String id, {
    Duration offset = const Duration(days: 3),
    String knowledgePointId = 'kp-1',
    int repetitions = 3,
    String state = 'review',
  }) {
    return ReviewFocusCard(
      cardStateId: id,
      knowledgePointId: knowledgePointId,
      dueAt: nowMs + offset.inMilliseconds,
      repetitions: repetitions,
      state: state,
    );
  }

  group('一、会被拉的卡：未来 horizon 内到期的已学卡', () {
    test('未来 3 天到期的卡被拉，带着它原来的 due_at', () {
      final plan = planReviewFocus(cards: [learned('cs-1')], now: now);

      expect(plan.total, 1);
      expect(plan.pulled, hasLength(1));
      expect(plan.pulled.single.cardStateId, 'cs-1');
      expect(plan.pulled.single.knowledgePointId, 'kp-1');
      expect(plan.pulled.single.previousDueAt, nowMs + 3 * 86400000);
      expect(plan.isEmpty, isFalse);
      expect(plan.alreadyDue, 0);
      expect(plan.tooFar, 0);
      expect(plan.newCards, 0);
      expect(plan.beyondLimit, 0);
    });

    test('按原到期时间从近到远排序（与输入顺序无关）', () {
      final plan = planReviewFocus(
        cards: [
          learned('cs-late', offset: const Duration(days: 6)),
          learned('cs-early', offset: const Duration(days: 1)),
          learned('cs-mid', offset: const Duration(days: 3)),
        ],
        now: now,
      );

      expect(
        [for (final pull in plan.pulled) pull.cardStateId],
        ['cs-early', 'cs-mid', 'cs-late'],
      );
    });

    test('正好落在 horizon 边界上的卡算「未来」，会被拉', () {
      final plan = planReviewFocus(
        cards: [learned('cs-edge', offset: const Duration(days: 7))],
        now: now,
      );

      expect(plan.pulled.single.cardStateId, 'cs-edge');
      expect(plan.tooFar, 0);
    });

    test('pulled 是不可修改列表（调用方不能改排序结果）', () {
      final plan = planReviewFocus(cards: [learned('cs-1')], now: now);

      expect(
        () => plan.pulled.add(const ReviewFocusPull(
          cardStateId: 'x',
          knowledgePointId: 'x',
          previousDueAt: 0,
        )),
        throwsUnsupportedError,
      );
    });
  });

  group('二、一律不动的三类卡', () {
    test('超过 horizon 的卡计入 too_far，不被拉', () {
      final plan = planReviewFocus(
        cards: [learned('cs-far', offset: const Duration(days: 8))],
        now: now,
      );

      expect(plan.pulled, isEmpty);
      expect(plan.tooFar, 1);
    });

    test('due_at 为 NULL 表示现在到期，计入 already_due', () {
      final plan = planReviewFocus(
        cards: const [
          ReviewFocusCard(
            cardStateId: 'cs-null',
            knowledgePointId: 'kp-1',
            dueAt: null,
            repetitions: 4,
            state: 'review',
          ),
        ],
        now: now,
      );

      expect(plan.pulled, isEmpty);
      expect(plan.alreadyDue, 1);
    });

    test('已经到期或正好现在到期的卡计入 already_due', () {
      final plan = planReviewFocus(
        cards: [
          learned('cs-past', offset: const Duration(days: -2)),
          learned('cs-now', offset: Duration.zero),
        ],
        now: now,
      );

      expect(plan.pulled, isEmpty);
      expect(plan.alreadyDue, 2);
    });

    test('新卡（repetitions 0 或 state=new）不拉，哪怕 due_at 很近', () {
      final plan = planReviewFocus(
        cards: [
          learned('cs-zero', repetitions: 0),
          learned('cs-new', state: 'new'),
        ],
        now: now,
      );

      expect(plan.pulled, isEmpty);
      expect(plan.newCards, 2);
    });
  });

  group('三、horizon 与 limit', () {
    test('horizon 为 0 时没有「未来」，只统计已经到期的', () {
      final plan = planReviewFocus(
        cards: [
          learned('cs-soon', offset: const Duration(hours: 1)),
          learned('cs-past', offset: const Duration(days: -1)),
        ],
        now: now,
        horizon: Duration.zero,
      );

      expect(plan.pulled, isEmpty);
      expect(plan.alreadyDue, 1);
      expect(plan.tooFar, 1);
    });

    test('自定义 horizon（1 天）只拉 1 天内的卡', () {
      final plan = planReviewFocus(
        cards: [
          learned('cs-12h', offset: const Duration(hours: 12)),
          learned('cs-2d', offset: const Duration(days: 2)),
        ],
        now: now,
        horizon: const Duration(days: 1),
      );

      expect([for (final pull in plan.pulled) pull.cardStateId], ['cs-12h']);
      expect(plan.tooFar, 1);
    });

    test('limit 截断时留下最晚到期的卡，并计入 beyond_limit', () {
      final plan = planReviewFocus(
        cards: [
          learned('cs-1', offset: const Duration(days: 1)),
          learned('cs-2', offset: const Duration(days: 2)),
          learned('cs-3', offset: const Duration(days: 3)),
          learned('cs-4', offset: const Duration(days: 4)),
        ],
        now: now,
        limit: 2,
      );

      expect(
        [for (final pull in plan.pulled) pull.cardStateId],
        ['cs-1', 'cs-2'],
      );
      expect(plan.beyondLimit, 2);
    });

    test('limit 为 0 时不拉任何卡，全部计入 beyond_limit', () {
      final plan = planReviewFocus(
        cards: [learned('cs-1'), learned('cs-2')],
        now: now,
        limit: 0,
      );

      expect(plan.pulled, isEmpty);
      expect(plan.beyondLimit, 2);
      expect(plan.isEmpty, isTrue);
    });

    test('limit 为负抛 ArgumentError，不给静默兜底', () {
      expect(
        () => planReviewFocus(cards: const [], now: now, limit: -1),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('不能是负数'),
          ),
        ),
      );
    });
  });

  group('四、确定性与计数守恒', () {
    test('同一 due_at 的卡按 card_state_id 升序，结果与输入顺序无关', () {
      final cards = [
        learned('cs-b', offset: const Duration(days: 2)),
        learned('cs-a', offset: const Duration(days: 2)),
        learned('cs-c', offset: const Duration(days: 2)),
      ];
      final first = planReviewFocus(cards: cards, now: now);
      final second = planReviewFocus(cards: cards.reversed.toList(), now: now);

      expect([for (final pull in first.pulled) pull.cardStateId],
          ['cs-a', 'cs-b', 'cs-c']);
      expect([for (final pull in second.pulled) pull.cardStateId],
          ['cs-a', 'cs-b', 'cs-c']);
    });

    test('总数等于五类计数之和（不漏卡也不重复计）', () {
      final plan = planReviewFocus(
        cards: [
          learned('cs-pull-1', offset: const Duration(days: 1)),
          learned('cs-pull-2', offset: const Duration(days: 2)),
          learned('cs-due', offset: const Duration(days: -1)),
          learned('cs-far', offset: const Duration(days: 30)),
          learned('cs-new', repetitions: 0),
        ],
        now: now,
        limit: 1,
      );

      expect(plan.total, 5);
      expect(
        plan.pulled.length +
            plan.alreadyDue +
            plan.tooFar +
            plan.newCards +
            plan.beyondLimit,
        5,
      );
      expect(plan.pulled.single.cardStateId, 'cs-pull-1');
      expect(plan.beyondLimit, 1);
    });

    test('空输入得到空计划', () {
      final plan = planReviewFocus(cards: const [], now: now);

      expect(plan.total, 0);
      expect(plan.isEmpty, isTrue);
      expect(plan.pulled, isEmpty);
    });
  });
}
