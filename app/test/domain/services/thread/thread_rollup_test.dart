import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/thread/thread_node_kind.dart';
import 'package:furnace/domain/services/thread/thread_rollup.dart';
import 'package:furnace/domain/services/thread/thread_status.dart';

/// `ThreadRollup`（schema v47，2026-11-15）：契约
/// `INTEGRATION-CONTRACT-2026-11-15.md` §3.4（父容器状态规则）/ §3.5
/// （`parentRollup = done / total`，跳过/卡住单列、不算完成）。
///
/// 这里全部是纯值对象测试（不建库）：状态优先级、五种计数、估时 null 语义、
/// 进度分母为 0 时返回 null、空子集不猜状态。
void main() {
  ThreadRollupNode node(
    String id,
    ThreadStatus status, {
    int? estimate,
    ThreadNodeKind kind = ThreadNodeKind.task,
    String? parentId = 'parent',
  }) =>
      ThreadRollupNode(
        id: id,
        status: status,
        kind: kind,
        parentId: parentId,
        estimateMinutes: estimate,
      );

  ThreadRollup rollupOf(
    List<ThreadRollupNode> children, {
    String parentId = 'parent',
  }) =>
      ThreadRollup.of(
        parent: ThreadRollupNode(id: parentId, status: ThreadStatus.todo),
        children: children,
      );

  group('状态规则（doing > blocked > todo > done/skipped 折叠）', () {
    test('全部 done → done，进度 100%', () {
      final rollup = rollupOf([
        node('a', ThreadStatus.done),
        node('b', ThreadStatus.done),
      ]);
      expect(rollup.status, ThreadStatus.done);
      expect(rollup.counts.done, 2);
      expect(rollup.counts.total, 2);
      expect(rollup.fraction, 1.0);
      expect(rollup.percent, 100);
      expect(rollup.isComplete, isTrue);
      expect(rollup.allTerminal, isTrue);
    });

    test('任一 doing → doing（优先于 blocked 与 todo）', () {
      final rollup = rollupOf([
        node('a', ThreadStatus.todo),
        node('b', ThreadStatus.blocked),
        node('c', ThreadStatus.doing),
        node('d', ThreadStatus.done),
      ]);
      expect(rollup.status, ThreadStatus.doing);
      expect(rollup.counts.doing, 1);
      expect(rollup.counts.blocked, 1);
      expect(rollup.counts.todo, 1);
      expect(rollup.counts.done, 1);
      expect(rollup.counts.total, 4);
      expect(rollup.percent, 25);
    });

    test('没有 doing 时任一 blocked → blocked（优先于 todo）', () {
      final rollup = rollupOf([
        node('a', ThreadStatus.todo),
        node('b', ThreadStatus.blocked),
        node('c', ThreadStatus.done),
      ]);
      expect(rollup.status, ThreadStatus.blocked);
      expect(rollup.counts.blocked, 1);
    });

    test('没有 doing/blocked 时任一 todo → todo', () {
      final rollup = rollupOf([
        node('a', ThreadStatus.todo),
        node('b', ThreadStatus.done),
        node('c', ThreadStatus.skipped),
      ]);
      expect(rollup.status, ThreadStatus.todo);
      expect(rollup.counts.todo, 1);
      expect(rollup.percent, 33);
      expect(rollup.allTerminal, isFalse);
    });

    test('全部 skipped → skipped，进度 0%，不是 todo 也不是 done', () {
      final rollup = rollupOf([
        node('a', ThreadStatus.skipped),
        node('b', ThreadStatus.skipped),
      ]);
      expect(rollup.status, ThreadStatus.skipped);
      expect(rollup.counts.skipped, 2);
      expect(rollup.counts.done, 0);
      expect(rollup.percent, 0);
      expect(rollup.isComplete, isFalse);
      expect(rollup.allTerminal, isTrue);
    });

    test('done + skipped（没有 doing/blocked/todo）→ done', () {
      final rollup = rollupOf([
        node('a', ThreadStatus.done),
        node('b', ThreadStatus.skipped),
      ]);
      expect(rollup.status, ThreadStatus.done);
      expect(rollup.percent, 50);
      expect(rollup.isComplete, isFalse);
      expect(rollup.allTerminal, isTrue);
    });

    test('空子集：不猜状态，也没有假的 0%', () {
      final rollup = rollupOf(const []);
      expect(rollup.status, isNull);
      expect(rollup.isEmpty, isTrue);
      expect(rollup.counts.total, 0);
      expect(rollup.counts.todo, 0);
      expect(rollup.counts.done, 0);
      expect(rollup.estimateMinutes, isNull);
      expect(rollup.fraction, isNull);
      expect(rollup.percent, isNull);
      expect(rollup.isComplete, isFalse);
      expect(rollup.allTerminal, isFalse);
    });
  });

  group('counts：五值各计一次，total 恒等于五项之和', () {
    test('覆盖 todo/doing/done/blocked/skipped', () {
      final rollup = rollupOf([
        node('a', ThreadStatus.todo),
        node('b', ThreadStatus.doing),
        node('c', ThreadStatus.done),
        node('d', ThreadStatus.blocked),
        node('e', ThreadStatus.skipped),
      ]);
      final counts = rollup.counts;
      expect(counts.total, 5);
      expect(counts.todo, 1);
      expect(counts.doing, 1);
      expect(counts.done, 1);
      expect(counts.blocked, 1);
      expect(counts.skipped, 1);
      expect(
        counts.total,
        counts.todo +
            counts.doing +
            counts.done +
            counts.blocked +
            counts.skipped,
      );
      expect(counts.terminal, 2);
    });

    test('ThreadRollupCounts.of 与 plus 口径一致', () {
      final a = ThreadRollupCounts.of([
        ThreadStatus.todo,
        ThreadStatus.done,
      ]);
      final b = ThreadRollupCounts.of([
        ThreadStatus.done,
        ThreadStatus.skipped,
      ]);
      final sum = a.plus(b);
      expect(sum.total, 4);
      expect(sum.todo, 1);
      expect(sum.done, 2);
      expect(sum.skipped, 1);
      expect(sum.terminal, 3);
    });
  });

  group('estimate：子节点之和，null 不冒充 0', () {
    test('全部有估时 → 求和（done/skipped 子节点也计入计划容量）', () {
      final rollup = rollupOf([
        node('a', ThreadStatus.done, estimate: 7),
        node('b', ThreadStatus.skipped, estimate: 3),
        node('c', ThreadStatus.todo, estimate: 5),
      ]);
      expect(rollup.estimateMinutes, 15);
    });

    test('任一子节点估时为 null → 整个估时为 null', () {
      final rollup = rollupOf([
        node('a', ThreadStatus.todo, estimate: 7),
        node('b', ThreadStatus.todo),
      ]);
      expect(rollup.estimateMinutes, isNull);
    });

    test('子节点全为 null 估时 → null（不是 0）', () {
      final rollup = rollupOf([
        node('a', ThreadStatus.todo),
        node('b', ThreadStatus.done),
      ]);
      expect(rollup.estimateMinutes, isNull);
    });
  });

  group('progress：done / total，分母为 0 可空', () {
    test('1/3 四舍五入为 33%，fraction 约 0.333', () {
      final rollup = rollupOf([
        node('a', ThreadStatus.done),
        node('b', ThreadStatus.todo),
        node('c', ThreadStatus.blocked),
      ]);
      expect(rollup.percent, 33);
      expect(rollup.fraction, closeTo(1 / 3, 1e-9));
    });

    test('0 完成但有子节点 → 0%（不是 null）', () {
      final rollup = rollupOf([
        node('a', ThreadStatus.todo),
        node('b', ThreadStatus.todo),
      ]);
      expect(rollup.percent, 0);
      expect(rollup.fraction, 0.0);
    });
  });

  group('merge：多个容器的汇总（chips 聚合）', () {
    test('计数相加、状态与进度按合并后的计数重算', () {
      final a = rollupOf([node('a', ThreadStatus.done, estimate: 10)]);
      final b = rollupOf([node('b', ThreadStatus.todo, estimate: 30)]);
      final merged = ThreadRollup.merge([a, b]);
      expect(merged, isNotNull);
      expect(merged!.counts.total, 2);
      expect(merged.counts.done, 1);
      expect(merged.status, ThreadStatus.todo);
      expect(merged.percent, 50);
      expect(merged.estimateMinutes, 40);
      expect(merged.parentId, isNull);
    });

    test('任一汇总估时未知 → 合并估时也是 null', () {
      final known = rollupOf([node('a', ThreadStatus.done, estimate: 10)]);
      final unknown = rollupOf([node('b', ThreadStatus.todo)]);
      final merged = ThreadRollup.merge([known, unknown]);
      expect(merged!.estimateMinutes, isNull);
      expect(merged.counts.total, 2);
    });

    test('空输入 → null（没有可汇总的容器）', () {
      expect(ThreadRollup.merge(const []), isNull);
    });
  });
}
