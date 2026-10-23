import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/attempt_stats.dart';

void main() {
  group('empty 常量与基本派生', () {
    test('empty 常量：0/0，isEmpty、percent 为 0', () {
      const QuestionAttemptStats stats = QuestionAttemptStats.empty;
      expect(stats.total, 0);
      expect(stats.correct, 0);
      expect(stats.incorrect, 0);
      expect(stats.isEmpty, isTrue);
      expect(stats.isNotEmpty, isFalse);
      expect(stats.percent, 0);
    });

    test('isEmpty/isNotEmpty 只看 total：答对 0 条但有判分就不算空', () {
      const QuestionAttemptStats none =
          QuestionAttemptStats(total: 0, correct: 0);
      expect(none.isEmpty, isTrue);
      expect(none.isNotEmpty, isFalse);

      const QuestionAttemptStats allWrong =
          QuestionAttemptStats(total: 3, correct: 0);
      expect(allWrong.isEmpty, isFalse);
      expect(allWrong.isNotEmpty, isTrue);
    });

    test('incorrect = total - correct', () {
      const QuestionAttemptStats partly =
          QuestionAttemptStats(total: 3, correct: 2);
      const QuestionAttemptStats perfect =
          QuestionAttemptStats(total: 5, correct: 5);
      const QuestionAttemptStats allWrong =
          QuestionAttemptStats(total: 4, correct: 0);
      expect(partly.incorrect, 1);
      expect(perfect.incorrect, 0);
      expect(allWrong.incorrect, 4);
    });
  });

  group('percent 取整', () {
    test('percent 取整表：0/5、5/5、1/2、2/3、1/3、99/100、1/200', () {
      expect(_percent(total: 5, correct: 0), 0, reason: '0/5');
      expect(_percent(total: 5, correct: 5), 100, reason: '5/5');
      expect(_percent(total: 2, correct: 1), 50, reason: '1/2');
      expect(_percent(total: 3, correct: 2), 67, reason: '2/3');
      expect(_percent(total: 3, correct: 1), 33, reason: '1/3');
      expect(_percent(total: 100, correct: 99), 99, reason: '99/100');
      expect(_percent(total: 200, correct: 1), 1, reason: '1/200');
    });

    test('percent 四舍五入到边界：12.5% 进位、99.5% 进位', () {
      expect(_percent(total: 8, correct: 1), 13, reason: '1/8 = 12.5%');
      expect(_percent(total: 200, correct: 199), 100,
          reason: '199/200 = 99.5%');
    });

    test('percent 恒在 0..100 之间（total 0..20 全组合）', () {
      for (var total = 0; total <= 20; total++) {
        for (var correct = 0; correct <= total; correct++) {
          final QuestionAttemptStats stats =
              QuestionAttemptStats(total: total, correct: correct);
          expect(stats.percent, inInclusiveRange(0, 100),
              reason: '$correct/$total');
        }
      }
    });
  });

  group('构造 assert', () {
    test('total 为负数时抛 AssertionError', () {
      expect(() => QuestionAttemptStats(total: -1, correct: 0),
          throwsAssertionError);
    });

    test('correct 为负数时抛 AssertionError', () {
      expect(() => QuestionAttemptStats(total: 1, correct: -1),
          throwsAssertionError);
    });

    test('correct 大于 total 时抛 AssertionError', () {
      expect(() => QuestionAttemptStats(total: 2, correct: 3),
          throwsAssertionError);
    });

    test('合法取值不抛：0/0、5/0、5/5', () {
      expect(() => const QuestionAttemptStats(total: 0, correct: 0),
          returnsNormally);
      expect(() => const QuestionAttemptStats(total: 5, correct: 0),
          returnsNormally);
      expect(() => const QuestionAttemptStats(total: 5, correct: 5),
          returnsNormally);
    });
  });

  group('大数与编译期常量', () {
    test('大数不溢出：1 << 40 条、一半答对 → percent 50', () {
      const int total = 1 << 40;
      const int correct = 1 << 39;
      const QuestionAttemptStats stats =
          QuestionAttemptStats(total: total, correct: correct);
      expect(stats.total, 1099511627776);
      expect(stats.correct, 549755813888);
      expect(stats.incorrect, correct);
      expect(stats.isEmpty, isFalse);
      expect(stats.percent, 50);
    });

    test('接近满分的大数：999999999/1000000000 → percent 100', () {
      const QuestionAttemptStats stats =
          QuestionAttemptStats(total: 1000000000, correct: 999999999);
      expect(stats.incorrect, 1);
      expect(stats.percent, 100);
    });

    test('const 上下文可构造并读到字段', () {
      const QuestionAttemptStats stats =
          QuestionAttemptStats(total: 3, correct: 2);
      expect(stats.total, 3);
      expect(stats.correct, 2);
      expect(stats.percent, 67);
    });
  });
}

int _percent({required int total, required int correct}) {
  return QuestionAttemptStats(total: total, correct: correct).percent;
}
