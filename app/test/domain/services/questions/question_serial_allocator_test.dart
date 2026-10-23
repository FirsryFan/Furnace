import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_serial_allocator.dart';

void main() {
  group('基本分配：合法候选取最大者 + 1', () {
    test('两个候选都是 null → 1', () {
      expect(allocateQuestionSerial(), 1);
      expect(
          allocateQuestionSerial(highestExisting: null, lastIssued: null), 1);
    });

    test('只有高水位（null/5）→ 6', () {
      expect(allocateQuestionSerial(lastIssued: 5), 6);
    });

    test('只有现存最大号（5/null）→ 6', () {
      expect(allocateQuestionSerial(highestExisting: 5), 6);
    });

    test('现存最大号小于高水位（5/9）→ 10', () {
      expect(allocateQuestionSerial(highestExisting: 5, lastIssued: 9), 10);
    });

    test('现存最大号大于高水位（9/5）→ 10', () {
      expect(allocateQuestionSerial(highestExisting: 9, lastIssued: 5), 10);
    });

    test('取最大者而不是相加：500/500 → 501', () {
      expect(
          allocateQuestionSerial(highestExisting: 500, lastIssued: 500), 501);
    });

    test('1/1 → 2', () {
      expect(allocateQuestionSerial(highestExisting: 1, lastIssued: 1), 2);
    });
  });

  group('非法候选（0 / 负数）被忽略', () {
    test('highestExisting 为 0 → 1', () {
      expect(allocateQuestionSerial(highestExisting: 0), 1);
    });

    test('highestExisting 为负数 → 1', () {
      expect(allocateQuestionSerial(highestExisting: -3), 1);
    });

    test('lastIssued 为 0 → 1', () {
      expect(allocateQuestionSerial(lastIssued: 0), 1);
    });

    test('lastIssued 为负数 → 1', () {
      expect(allocateQuestionSerial(lastIssued: -3), 1);
    });

    test('0/0 与负数混搭 → 1', () {
      expect(allocateQuestionSerial(highestExisting: 0, lastIssued: 0), 1);
      expect(allocateQuestionSerial(highestExisting: -1, lastIssued: -1), 1);
      expect(allocateQuestionSerial(highestExisting: -1, lastIssued: 0), 1);
    });

    test('一个非法一个合法：0/7 → 8、-2/7 → 8', () {
      expect(allocateQuestionSerial(highestExisting: 0, lastIssued: 7), 8);
      expect(allocateQuestionSerial(highestExisting: -2, lastIssued: 7), 8);
      expect(allocateQuestionSerial(highestExisting: 7, lastIssued: 0), 8);
    });
  });

  group('上限饱和（不回绕负数）', () {
    test('上限常量为 999999999', () {
      expect(kMaxAllocatableQuestionSerial, 999999999);
    });

    test('highestExisting = 999999999 → 999999999（饱和，不是 1000000000）', () {
      expect(allocateQuestionSerial(highestExisting: 999999999), 999999999);
    });

    test('lastIssued = 999999999 → 999999999', () {
      expect(allocateQuestionSerial(lastIssued: 999999999), 999999999);
    });

    test('999999998/999999998 → 999999999（刚好发出最后一个号）', () {
      expect(
        allocateQuestionSerial(
            highestExisting: 999999998, lastIssued: 999999998),
        999999999,
      );
    });

    test('超过上限的候选 → 999999999（不会回绕成负数）', () {
      expect(allocateQuestionSerial(highestExisting: 1000000000), 999999999);
      expect(allocateQuestionSerial(lastIssued: 1000000000), 999999999);
    });

    test('int 最大值候选 → 999999999（不会溢出回绕）', () {
      expect(
        allocateQuestionSerial(highestExisting: 9223372036854775807),
        999999999,
      );
      expect(
        allocateQuestionSerial(
            highestExisting: 9223372036854775807,
            lastIssued: 9223372036854775807),
        999999999,
      );
    });
  });

  group('性质：返回值恒定合法', () {
    test('循环样本：结果恒 >= 1、恒不大于上限、恒等于规范公式、两次调用一致', () {
      const List<int> samples = <int>[
        -5,
        -1,
        0,
        1,
        2,
        3,
        7,
        42,
        999,
        100000,
        999999998,
        999999999,
      ];
      for (final highest in samples) {
        for (final last in samples) {
          final int first = allocateQuestionSerial(
              highestExisting: highest, lastIssued: last);
          final int second = allocateQuestionSerial(
              highestExisting: highest, lastIssued: last);
          final String reason = 'highest=$highest last=$last';

          expect(first, second, reason: reason);
          expect(first, greaterThanOrEqualTo(1), reason: reason);
          expect(first, lessThanOrEqualTo(kMaxAllocatableQuestionSerial),
              reason: reason);

          int? legalMax;
          if (highest >= 1) {
            legalMax = highest;
          }
          if (last >= 1 && (legalMax == null || last > legalMax)) {
            legalMax = last;
          }
          if (legalMax == null) {
            expect(first, 1, reason: reason);
          } else if (legalMax < kMaxAllocatableQuestionSerial) {
            expect(first, legalMax + 1, reason: reason);
            expect(first, greaterThan(legalMax), reason: reason);
            if (highest >= 1) {
              expect(first, greaterThanOrEqualTo(highest), reason: reason);
            }
            if (last >= 1) {
              expect(first, greaterThanOrEqualTo(last), reason: reason);
            }
          } else {
            expect(first, kMaxAllocatableQuestionSerial, reason: reason);
            expect(first, lessThanOrEqualTo(legalMax), reason: reason);
          }
        }
      }
    });

    test('连续高水位：每发一个号高水位跟着涨，永不小于已发号', () {
      var lastIssued = 0;
      var highestExisting = 0;
      for (var i = 0; i < 200; i++) {
        final int issued = allocateQuestionSerial(
            highestExisting: highestExisting, lastIssued: lastIssued);
        expect(issued, greaterThanOrEqualTo(1));
        expect(issued, greaterThanOrEqualTo(lastIssued));
        expect(issued, greaterThanOrEqualTo(highestExisting));
        // 模拟「高水位前进 + 这次没被删」；偶尔让现存最大号落后于高水位。
        lastIssued = issued;
        highestExisting = i.isEven ? issued : (issued - 1).clamp(0, issued);
      }
      expect(lastIssued, 200);
    });
  });
}
