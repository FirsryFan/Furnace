import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/anki/application/review_pacing.dart';

/// 新卡插入节奏的纯函数测试。
///
/// 用户口径（2026-10-25）：「闪存卡重复出现频率高、难以推进新卡片」，
/// 所以新卡要按固定节奏均匀插进复习序列，而不是全堆到队尾。
void main() {
  List<String> reviews(int n) => [for (var i = 1; i <= n; i++) 'r$i'];
  List<String> newCards(int n) => [for (var i = 1; i <= n; i++) 'n$i'];

  group('精确节奏：每 every 张复习卡后插一张新卡', () {
    test('10 张复习 + 3 张新卡 + every=5 → 5/5 两处插入，余下接尾', () {
      expect(
        paceNewCards(
          reviews: reviews(10),
          newCards: newCards(3),
          every: 5,
        ),
        [
          'r1',
          'r2',
          'r3',
          'r4',
          'r5',
          'n1',
          'r6',
          'r7',
          'r8',
          'r9',
          'r10',
          'n2',
          'n3'
        ],
      );
    });

    test('5 张复习 + 10 张新卡 + every=5 → 只插得进一张，其余全接尾', () {
      expect(
        paceNewCards(
          reviews: reviews(5),
          newCards: newCards(10),
          every: 5,
        ),
        [
          'r1',
          'r2',
          'r3',
          'r4',
          'r5',
          'n1',
          'n2',
          'n3',
          'n4',
          'n5',
          'n6',
          'n7',
          'n8',
          'n9',
          'n10',
        ],
      );
    });

    test('插入点按复习卡下标累加，不因已有新卡而偏移', () {
      expect(
        paceNewCards(
          reviews: reviews(6),
          newCards: newCards(2),
          every: 2,
        ),
        ['r1', 'r2', 'n1', 'r3', 'r4', 'n2', 'r5', 'r6'],
      );
    });
  });

  group('剩余新卡接尾', () {
    test('3 张复习 + 8 张新卡 + every=2 → 前 3 张按节奏，其余接尾', () {
      expect(
        paceNewCards(
          reviews: reviews(3),
          newCards: newCards(8),
          every: 2,
        ),
        ['r1', 'r2', 'n1', 'r3', 'n2', 'n3', 'n4', 'n5', 'n6', 'n7', 'n8'],
      );
    });

    test('新卡一张都插不进时全部接尾（every 比复习卡多）', () {
      expect(
        paceNewCards(
          reviews: reviews(2),
          newCards: newCards(3),
          every: 3,
        ),
        ['r1', 'r2', 'n1', 'n2', 'n3'],
      );
    });
  });

  group('every 边界', () {
    test('every=1 → 复习卡与新卡交替，新卡多出部分接尾', () {
      expect(
        paceNewCards(reviews: reviews(3), newCards: newCards(5), every: 1),
        ['r1', 'n1', 'r2', 'n2', 'r3', 'n3', 'n4', 'n5'],
      );
    });

    test('every=0 抬到 1（不退化成除零或全堆队尾）', () {
      expect(
        paceNewCards(reviews: reviews(2), newCards: newCards(2), every: 0),
        ['r1', 'n1', 'r2', 'n2'],
      );
    });

    test('every 为负数同样抬到 1', () {
      expect(
        paceNewCards(reviews: reviews(2), newCards: newCards(2), every: -3),
        ['r1', 'n1', 'r2', 'n2'],
      );
    });

    test('every 远大于复习卡数：全部复习后接全部新卡', () {
      expect(
        paceNewCards(reviews: reviews(3), newCards: newCards(2), every: 100),
        ['r1', 'r2', 'r3', 'n1', 'n2'],
      );
    });
  });

  group('空表', () {
    test('两种都空 → 空表', () {
      expect(paceNewCards(reviews: <String>[], newCards: <String>[]), isEmpty);
    });

    test('复习为空 → 新卡副本（顺序不变、不是同一个对象）', () {
      final input = newCards(3);
      final result = paceNewCards(reviews: <String>[], newCards: input);
      expect(result, ['n1', 'n2', 'n3']);
      expect(identical(result, input), isFalse);
      result.add('n4');
      expect(input, ['n1', 'n2', 'n3']);
    });

    test('新卡为空 → 复习副本（顺序不变、不是同一个对象）', () {
      final input = reviews(3);
      final result = paceNewCards(reviews: input, newCards: <String>[]);
      expect(result, ['r1', 'r2', 'r3']);
      expect(identical(result, input), isFalse);
    });
  });

  group('不修改入参与泛型', () {
    test('传入不可变列表不抛异常，结果含全部条目且顺序正确', () {
      final frozenReviews = List<String>.unmodifiable(reviews(4));
      final frozenNew = List<String>.unmodifiable(newCards(2));
      final result = paceNewCards(
        reviews: frozenReviews,
        newCards: frozenNew,
        every: 2,
      );
      expect(result, ['r1', 'r2', 'n1', 'r3', 'r4', 'n2']);
      expect(frozenReviews, ['r1', 'r2', 'r3', 'r4']);
      expect(frozenNew, ['n1', 'n2']);
    });

    test('返回的是可增长列表（调用方还能继续 add）', () {
      final result = paceNewCards(reviews: reviews(2), newCards: newCards(1));
      result.add('x');
      expect(result, ['r1', 'r2', 'n1', 'x']);
    });

    test('int 泛型同样按节奏排列', () {
      expect(
        paceNewCards<int>(reviews: [1, 2, 3], newCards: [100, 200], every: 2),
        [1, 2, 100, 3, 200],
      );
    });
  });

  group('默认值与大量组合', () {
    test('不传 every 时等于 kNewCardEveryReviews（默认 5）', () {
      expect(kNewCardEveryReviews, 5);
      expect(
        paceNewCards(reviews: reviews(6), newCards: newCards(3)),
        paceNewCards(reviews: reviews(6), newCards: newCards(3), every: 5),
      );
    });

    test('100 张复习 + 20 张新卡 + every=7 → 120 张、新卡顺序完整', () {
      final result = paceNewCards(
        reviews: reviews(100),
        newCards: newCards(20),
        every: 7,
      );
      expect(result.length, 120);
      expect(
        result.where((item) => item.startsWith('n')).toList(),
        newCards(20),
      );
      expect(
        result.where((item) => item.startsWith('r')).toList(),
        reviews(100),
      );
    });

    test('新卡比复习卡多且 every=1：交替后余下新卡全接尾', () {
      expect(
        paceNewCards(reviews: reviews(2), newCards: newCards(5), every: 1),
        ['r1', 'n1', 'r2', 'n2', 'n3', 'n4', 'n5'],
      );
    });

    test('同一输入两次调用结果相等但对象不同（确定性）', () {
      final first = paceNewCards(reviews: reviews(7), newCards: newCards(4));
      final second = paceNewCards(reviews: reviews(7), newCards: newCards(4));
      expect(first, second);
      expect(identical(first, second), isFalse);
    });
  });
}
