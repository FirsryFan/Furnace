/// 作答历史聚合：构造排序、计数、latest 语义与不可变行为。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/attempt_history.dart';

void main() {
  QuestionAttemptEntry entry({
    required String id,
    String questionId = 'q1',
    required bool isCorrect,
    required DateTime attemptedAt,
  }) =>
      QuestionAttemptEntry(
        id: id,
        questionId: questionId,
        isCorrect: isCorrect,
        attemptedAt: attemptedAt,
      );

  DateTime at(int minute) => DateTime.utc(2026, 10, 24, 9, minute);

  group('空输入与单条', () {
    test('空输入：entries 空、计数为 0、latest 为 null、latestIsCorrect false', () {
      final history = QuestionAttemptHistory.fromEntries(
        const <QuestionAttemptEntry>[],
      );
      expect(history.entries, isEmpty);
      expect(history.isEmpty, isTrue);
      expect(history.total, 0);
      expect(history.correct, 0);
      expect(history.incorrect, 0);
      expect(history.latest, isNull);
      expect(history.latestIsCorrect, isFalse);
    });

    test('单条正确作答：统计与 latest 都指向它', () {
      final only = entry(id: 'a', isCorrect: true, attemptedAt: at(5));
      final history = QuestionAttemptHistory.fromEntries(
        <QuestionAttemptEntry>[only],
      );
      expect(history.total, 1);
      expect(history.correct, 1);
      expect(history.incorrect, 0);
      expect(history.latest, same(only));
      expect(history.latestIsCorrect, isTrue);
      expect(history.entries.single, same(only));
    });

    test('单条错误作答：latestIsCorrect 为 false 且 latest 不为 null', () {
      final only = entry(id: 'a', isCorrect: false, attemptedAt: at(5));
      final history = QuestionAttemptHistory.fromEntries(
        <QuestionAttemptEntry>[only],
      );
      expect(history.isEmpty, isFalse);
      expect(history.latest, same(only));
      expect(history.latestIsCorrect, isFalse);
      expect(history.incorrect, 1);
    });
  });

  group('排序', () {
    test('乱序输入按新→旧排序（attemptedAt 降序）', () {
      final older = entry(id: 'a', isCorrect: true, attemptedAt: at(1));
      final middle = entry(id: 'b', isCorrect: true, attemptedAt: at(3));
      final newest = entry(id: 'c', isCorrect: false, attemptedAt: at(7));
      final history = QuestionAttemptHistory.fromEntries(
        <QuestionAttemptEntry>[middle, newest, older],
      );
      expect(
        history.entries.map((entry) => entry.id).toList(),
        <String>['c', 'b', 'a'],
      );
      expect(history.latest, same(newest));
    });

    test('同一毫秒按 id 升序 tie-break', () {
      final sameMoment = at(5);
      final b = entry(id: 'b', isCorrect: true, attemptedAt: sameMoment);
      final a = entry(id: 'a', isCorrect: false, attemptedAt: sameMoment);
      final c = entry(id: 'c', isCorrect: true, attemptedAt: sameMoment);
      final history = QuestionAttemptHistory.fromEntries(
        <QuestionAttemptEntry>[b, c, a],
      );
      expect(
        history.entries.map((entry) => entry.id).toList(),
        <String>['a', 'b', 'c'],
      );
      expect(history.latest, same(a));
    });

    test('输入顺序不影响结果：正序、逆序、乱序构造出同样顺序', () {
      final entries = <QuestionAttemptEntry>[
        entry(id: 'a', isCorrect: true, attemptedAt: at(1)),
        entry(id: 'b', isCorrect: true, attemptedAt: at(2)),
        entry(id: 'c', isCorrect: false, attemptedAt: at(3)),
      ];
      List<String> idsOf(Iterable<QuestionAttemptEntry> input) =>
          QuestionAttemptHistory.fromEntries(input)
              .entries
              .map((entry) => entry.id)
              .toList();
      expect(idsOf(entries), <String>['c', 'b', 'a']);
      expect(idsOf(entries.reversed), <String>['c', 'b', 'a']);
      expect(
        idsOf(<QuestionAttemptEntry>[entries[1], entries[2], entries[0]]),
        <String>['c', 'b', 'a'],
      );
    });

    test('同一条输入两次构造结果完全相同（确定性）', () {
      final input = <QuestionAttemptEntry>[
        entry(id: 'x', isCorrect: true, attemptedAt: at(2)),
        entry(id: 'y', isCorrect: false, attemptedAt: at(2)),
        entry(id: 'z', isCorrect: true, attemptedAt: at(9)),
      ];
      final first = QuestionAttemptHistory.fromEntries(input);
      final second = QuestionAttemptHistory.fromEntries(input);
      expect(
        first.entries.map((entry) => entry.id).toList(),
        second.entries.map((entry) => entry.id).toList(),
      );
      expect(first.total, second.total);
      expect(first.correct, second.correct);
    });

    test('重复 id 的条目全部保留（不去重）', () {
      final history = QuestionAttemptHistory.fromEntries(
        <QuestionAttemptEntry>[
          entry(id: 'dup', isCorrect: true, attemptedAt: at(1)),
          entry(id: 'dup', isCorrect: false, attemptedAt: at(2)),
        ],
      );
      expect(history.total, 2);
      expect(history.correct, 1);
      expect(history.incorrect, 1);
      expect(
        history.entries.map((entry) => entry.id).toList(),
        <String>['dup', 'dup'],
      );
    });
  });

  group('计数', () {
    test('total / correct / incorrect 统计正确', () {
      final history = QuestionAttemptHistory.fromEntries(
        <QuestionAttemptEntry>[
          entry(id: 'a', isCorrect: true, attemptedAt: at(1)),
          entry(id: 'b', isCorrect: false, attemptedAt: at(2)),
          entry(id: 'c', isCorrect: true, attemptedAt: at(3)),
          entry(id: 'd', isCorrect: true, attemptedAt: at(4)),
          entry(id: 'e', isCorrect: false, attemptedAt: at(5)),
        ],
      );
      expect(history.total, 5);
      expect(history.correct, 3);
      expect(history.incorrect, 2);
    });

    test('混合多题的 questionId 只统计、不分组也不报错', () {
      final history = QuestionAttemptHistory.fromEntries(
        <QuestionAttemptEntry>[
          entry(id: 'a', questionId: 'q1', isCorrect: true, attemptedAt: at(1)),
          entry(
              id: 'b', questionId: 'q2', isCorrect: false, attemptedAt: at(2)),
          entry(id: 'c', questionId: 'q3', isCorrect: true, attemptedAt: at(3)),
        ],
      );
      expect(history.total, 3);
      expect(history.correct, 2);
      expect(history.incorrect, 1);
      expect(
        history.entries.map((entry) => entry.questionId).toList(),
        <String>['q3', 'q2', 'q1'],
      );
    });

    test('全部答错时 correct 为 0、incorrect 等于 total', () {
      final history = QuestionAttemptHistory.fromEntries(
        <QuestionAttemptEntry>[
          entry(id: 'a', isCorrect: false, attemptedAt: at(1)),
          entry(id: 'b', isCorrect: false, attemptedAt: at(2)),
        ],
      );
      expect(history.correct, 0);
      expect(history.incorrect, 2);
      expect(history.latestIsCorrect, isFalse);
    });
  });

  group('latest', () {
    test('latest 取时间最新一条，与 id 大小无关', () {
      final old = entry(id: 'a', isCorrect: true, attemptedAt: at(1));
      final newest = entry(id: 'z', isCorrect: false, attemptedAt: at(9));
      final history = QuestionAttemptHistory.fromEntries(
        <QuestionAttemptEntry>[old, newest],
      );
      expect(history.latest, same(newest));
      expect(history.latestIsCorrect, isFalse);
    });

    test('最新一条判对时 latestIsCorrect 为 true', () {
      final history = QuestionAttemptHistory.fromEntries(
        <QuestionAttemptEntry>[
          entry(id: 'a', isCorrect: false, attemptedAt: at(1)),
          entry(id: 'b', isCorrect: true, attemptedAt: at(2)),
        ],
      );
      expect(history.latestIsCorrect, isTrue);
    });
  });

  group('不可变与输入', () {
    test('entries 不可修改：add / removeAt / clear 抛 UnsupportedError', () {
      final history = QuestionAttemptHistory.fromEntries(
        <QuestionAttemptEntry>[
          entry(id: 'a', isCorrect: true, attemptedAt: at(1)),
        ],
      );
      final extra = entry(id: 'b', isCorrect: false, attemptedAt: at(2));
      expect(() => history.entries.add(extra), throwsUnsupportedError);
      expect(() => history.entries.removeAt(0), throwsUnsupportedError);
      expect(() => history.entries.clear(), throwsUnsupportedError);
    });

    test('fromEntries 不修改传入的原列表', () {
      final input = <QuestionAttemptEntry>[
        entry(id: 'b', isCorrect: false, attemptedAt: at(2)),
        entry(id: 'a', isCorrect: true, attemptedAt: at(1)),
      ];
      final before = List<QuestionAttemptEntry>.of(input);
      QuestionAttemptHistory.fromEntries(input);
      expect(input, before);
      expect(
        input.map((entry) => entry.id).toList(),
        <String>['b', 'a'],
      );
    });

    test('传入惰性 Iterable 也能正确构造', () {
      final history = QuestionAttemptHistory.fromEntries(
        <QuestionAttemptEntry>[
          entry(id: 'a', isCorrect: true, attemptedAt: at(1)),
          entry(id: 'b', isCorrect: false, attemptedAt: at(2)),
        ].where((entry) => true),
      );
      expect(history.total, 2);
      expect(
        history.entries.map((entry) => entry.id).toList(),
        <String>['b', 'a'],
      );
    });
  });
}
