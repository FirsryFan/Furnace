import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/scheduling/thread_windows.dart';
import 'package:furnace/domain/services/thread/thread_node_kind.dart';
import 'package:furnace/domain/services/thread/thread_status.dart';

/// 「本周任务 / 本日任务」的窗口规则（契约 §3.5）。
///
/// 这里钉的是**纯函数**：窗口边界、expectedAt 优先、全 NULL 归未排期、
/// done/skipped 不出现、blocked 出现、日窗口是周窗口的子集、分类内保持调用方
/// 给的顺序（不重排）。排序本身不在这里（唯一入口仍是 `ThreadRankService`）。
void main() {
  ThreadWindowNode node(
    String id, {
    DateTime? expectedAt,
    DateTime? dueAt,
    ThreadNodeKind kind = ThreadNodeKind.task,
    ThreadStatus status = ThreadStatus.todo,
  }) =>
      ThreadWindowNode(
        id: id,
        kind: kind,
        status: status,
        expectedAt: expectedAt,
        dueAt: dueAt,
      );

  group('窗口边界（本地日历，周一为一周第一天）', () {
    test('周日中午 → 本周是 2026-11-09 00:00 到下周一 00:00', () {
      final window = weekWindow(DateTime(2026, 11, 15, 12));

      expect(window.start, DateTime(2026, 11, 9));
      expect(window.end, DateTime(2026, 11, 16));
    });

    test('周一 00:00 属于本周，下周一 00:00 不属于（半开区间）', () {
      final window = weekWindow(DateTime(2026, 11, 15, 12));

      expect(window.contains(DateTime(2026, 11, 9)), isTrue);
      expect(window.contains(DateTime(2026, 11, 15, 23, 59, 59)), isTrue);
      expect(window.contains(DateTime(2026, 11, 16)), isFalse);
      expect(window.contains(DateTime(2026, 11, 8, 23, 59, 59)), isFalse);
    });

    test('跨年也按 ISO 周（周四定年）：2026-01-01 属于 2026-W01', () {
      final window = weekWindow(DateTime(2026, 1, 1, 9));

      expect(window.start, DateTime(2025, 12, 29));
      expect(window.end, DateTime(2026, 1, 5));
    });

    test('日窗口 = 今天 00:00 到明天 00:00', () {
      final window = dayWindow(DateTime(2026, 11, 15, 23, 30));

      expect(window.start, DateTime(2026, 11, 15));
      expect(window.end, DateTime(2026, 11, 16));
      expect(window.contains(DateTime(2026, 11, 15)), isTrue);
      expect(window.contains(DateTime(2026, 11, 16)), isFalse);
    });

    test('UTC 输入先转本地：同一时刻的两个表示给出同一个窗口', () {
      final local = DateTime(2026, 11, 15, 12);

      expect(weekWindow(local.toUtc()), weekWindow(local));
      expect(dayWindow(local.toUtc()), dayWindow(local));
    });
  });

  group('成员关系', () {
    test('锚点 = expectedAt ?? dueAt：expectedAt 优先', () {
      // expectedAt 在上周、dueAt 在本周：按 expectedAt 优先，不进本周窗。
      final priority = node(
        'expected-first',
        expectedAt: DateTime(2026, 11, 6, 10),
        dueAt: DateTime(2026, 11, 12, 10),
      );
      // 只有 dueAt 时用 dueAt。
      final dueOnly = node('due-only', dueAt: DateTime(2026, 11, 12, 10));

      final buckets = ThreadWindowProjection.project(
        nodes: [priority, dueOnly],
        orderedIds: ['priority', 'dueOnly'],
        now: DateTime(2026, 11, 15, 12),
      );

      expect(buckets.week.map((n) => n.id), ['due-only']);
      expect(
        buckets.week.first.anchor,
        DateTime(2026, 11, 12, 10),
        reason: '只有 dueAt 时锚点就是 dueAt',
      );
    });

    test('两个时间都为 NULL → 未排期，不进任何时间窗', () {
      final buckets = ThreadWindowProjection.project(
        nodes: [node('no-date')],
        orderedIds: const [],
        now: DateTime(2026, 11, 15, 12),
      );

      expect(buckets.week, isEmpty);
      expect(buckets.day, isEmpty);
      expect(buckets.unscheduled.map((n) => n.id), ['no-date']);
    });

    test('done / skipped 不出现；blocked 出现', () {
      final at = DateTime(2026, 11, 15, 9);
      final buckets = ThreadWindowProjection.project(
        nodes: [
          node('todo', expectedAt: at),
          node('doing', expectedAt: at, status: ThreadStatus.doing),
          node('blocked', expectedAt: at, status: ThreadStatus.blocked),
          node('done', expectedAt: at, status: ThreadStatus.done),
          node('skipped', expectedAt: at, status: ThreadStatus.skipped),
        ],
        orderedIds: const ['todo', 'doing', 'blocked', 'done', 'skipped'],
        now: DateTime(2026, 11, 15, 12),
      );

      expect(
        buckets.week.map((n) => n.id),
        ['todo', 'doing', 'blocked'],
        reason: 'done/skipped 归归档，blocked 是"卡住"仍要出现在窗口里',
      );
      expect(buckets.unscheduled, isEmpty);
    });

    test('日窗口是周窗口的子集：今天的东西同时进两桶', () {
      final today = DateTime(2026, 11, 15, 9);
      final buckets = ThreadWindowProjection.project(
        nodes: [node('today', expectedAt: today)],
        orderedIds: const ['today'],
        now: DateTime(2026, 11, 15, 12),
      );

      expect(buckets.week.map((n) => n.id), ['today']);
      expect(buckets.day.map((n) => n.id), ['today']);
    });

    test('周内、非今天的节点只进本周桶', () {
      final buckets = ThreadWindowProjection.project(
        nodes: [node('tuesday', expectedAt: DateTime(2026, 11, 10, 10))],
        orderedIds: const ['tuesday'],
        now: DateTime(2026, 11, 15, 12),
      );

      expect(buckets.week.map((n) => n.id), ['tuesday']);
      expect(buckets.day, isEmpty);
    });

    test('week / day / paper 容器与 task 一样参与（不按 kind 特判）', () {
      final at = DateTime(2026, 11, 15, 9);
      final buckets = ThreadWindowProjection.project(
        nodes: [
          node('week-container', expectedAt: at, kind: ThreadNodeKind.week),
          node('day-container', expectedAt: at, kind: ThreadNodeKind.day),
          node('paper-node', expectedAt: at, kind: ThreadNodeKind.paper),
        ],
        orderedIds: const [],
        now: DateTime(2026, 11, 15, 12),
      );

      expect(
        buckets.week.map((n) => n.id),
        ['week-container', 'day-container', 'paper-node'],
      );
    });
  });

  group('顺序与去重', () {
    test('保持调用方给的顺序（分类内不重排）', () {
      final at = DateTime(2026, 11, 15, 9);
      final buckets = ThreadWindowProjection.project(
        nodes: [
          node('a', expectedAt: at),
          node('b', expectedAt: at),
          node('c', expectedAt: at),
        ],
        orderedIds: const ['c', 'a'],
        now: DateTime(2026, 11, 15, 12),
      );

      expect(
        buckets.week.map((n) => n.id),
        ['c', 'a', 'b'],
        reason: 'c、a 按调用方顺序，b 不在 orderedIds 里，按输入顺序接在后面',
      );
    });

    test('重复的节点 id 只算一次；orderedIds 里的未知 id 被忽略', () {
      final at = DateTime(2026, 11, 15, 9);
      final buckets = ThreadWindowProjection.project(
        nodes: [
          node('a', expectedAt: at),
          node('a', expectedAt: at),
        ],
        orderedIds: const ['missing', 'a'],
        now: DateTime(2026, 11, 15, 12),
      );

      expect(buckets.week.map((n) => n.id), ['a']);
    });
  });

  group('空与计数', () {
    test('没有节点：isEmpty 为真（UI 据此不显示分类）', () {
      final buckets = ThreadWindowProjection.project(
        nodes: const [],
        orderedIds: const [],
        now: DateTime(2026, 11, 15, 12),
      );

      expect(buckets.isEmpty, isTrue);
      expect(buckets.totalCount, 0);
    });

    test('只有未排期节点：isEmpty 仍为真（时间窗里确实没任务）', () {
      final buckets = ThreadWindowProjection.project(
        nodes: [node('no-date')],
        orderedIds: const ['no-date'],
        now: DateTime(2026, 11, 15, 12),
      );

      expect(buckets.isEmpty, isTrue);
      expect(buckets.unscheduled, hasLength(1));
    });
  });
}
