/// 选择题客观判分纯逻辑：题型口径、集合相等判分、空选择与确定性排序。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/objective_answer.dart';

void main() {
  ObjectiveOption option(String label, bool isCorrect) =>
      ObjectiveOption(label: label, isCorrect: isCorrect);

  ObjectiveAttemptResult score({
    String type = 'single_choice',
    List<ObjectiveOption>? options,
    List<String> selected = const <String>[],
  }) =>
      scoreObjectiveAnswer(
        questionType: type,
        options:
            options ?? <ObjectiveOption>[option('A', true), option('B', false)],
        selectedLabels: selected,
      );

  group('题型判定与可判分', () {
    test('single_choice / multi_choice（含大小写与空白）是客观题', () {
      for (final type in <String>[
        'single_choice',
        'multi_choice',
        ' SINGLE_CHOICE ',
        'Multi_Choice',
        'SINGLE_CHOICE',
      ]) {
        expect(isObjectiveQuestionType(type), isTrue, reason: type);
      }
    });

    test('其它题型不是客观题（填空/解答/开放/空串/空白/未知）', () {
      for (final type in <String>[
        'fill_blank',
        'solution',
        'open',
        '',
        '   ',
        'single choice',
        'true_false',
        'unknown',
      ]) {
        expect(isObjectiveQuestionType(type), isFalse, reason: type);
      }
    });

    test('可以判分的边界：客观题 + 至少一个正确选项', () {
      expect(
        canScoreObjectiveQuestion(
          questionType: 'single_choice',
          options: <ObjectiveOption>[option('A', true)],
        ),
        isTrue,
      );
      expect(
        canScoreObjectiveQuestion(
          questionType: ' multi_choice ',
          options: <ObjectiveOption>[option('A', false), option('B', true)],
        ),
        isTrue,
      );
    });

    test('不能判分的边界：无正确选项 / 空选项 / 题型不对', () {
      expect(
        canScoreObjectiveQuestion(
          questionType: 'single_choice',
          options: <ObjectiveOption>[option('A', false)],
        ),
        isFalse,
      );
      expect(
        canScoreObjectiveQuestion(
          questionType: 'single_choice',
          options: const <ObjectiveOption>[],
        ),
        isFalse,
      );
      expect(
        canScoreObjectiveQuestion(
          questionType: 'fill_blank',
          options: <ObjectiveOption>[option('A', true)],
        ),
        isFalse,
        reason: '题型不对时，即使有人标了正确答案也不能按客观题判',
      );
      expect(
        canScoreObjectiveQuestion(
          questionType: 'single_choice',
          options: <ObjectiveOption>[option(' ', true), option('', true)],
        ),
        isFalse,
        reason: '空标签不算正确选项',
      );
    });

    test('空白题型（纯空格）不是客观题', () {
      expect(isObjectiveQuestionType('   '), isFalse);
    });
  });

  group('判分：单选', () {
    test('选对 → correct，四个列表齐全且 isCorrect', () {
      final result = score(selected: const <String>['A']);
      expect(result.status, ObjectiveAttemptStatus.correct);
      expect(result.selectedLabels, <String>['A']);
      expect(result.correctLabels, <String>['A']);
      expect(result.missingLabels, isEmpty);
      expect(result.extraLabels, isEmpty);
      expect(result.isCorrect, isTrue);
      expect(result.isIncorrect, isFalse);
    });

    test('选错 → incorrect，正确项进 missing、错选项进 extra', () {
      final result = score(selected: const <String>['B']);
      expect(result.status, ObjectiveAttemptStatus.incorrect);
      expect(result.selectedLabels, <String>['B']);
      expect(result.correctLabels, <String>['A']);
      expect(result.missingLabels, <String>['A']);
      expect(result.extraLabels, <String>['B']);
      expect(result.isCorrect, isFalse);
      expect(result.isIncorrect, isTrue);
    });

    test('没选任何选项 → emptySelection，但正确答案照样填上', () {
      final result = score();
      expect(result.status, ObjectiveAttemptStatus.emptySelection);
      expect(result.selectedLabels, isEmpty);
      expect(result.correctLabels, <String>['A']);
      expect(result.missingLabels, isEmpty);
      expect(result.extraLabels, isEmpty);
      expect(result.isCorrect, isFalse);
      expect(result.isIncorrect, isFalse);
    });

    test('选择全是空白 → emptySelection（不构成一次作答）', () {
      final result = score(selected: const <String>['', '  ']);
      expect(result.status, ObjectiveAttemptStatus.emptySelection);
      expect(result.selectedLabels, isEmpty);
    });

    test('大小写与首尾空白归一化：b 与 B 相等', () {
      final result = score(
        options: <ObjectiveOption>[option(' a ', true), option('b ', false)],
        selected: const <String>['a'],
      );
      expect(result.status, ObjectiveAttemptStatus.correct);
      expect(result.correctLabels, <String>['A']);
      expect(result.selectedLabels, <String>['A']);
    });

    test('重复选择去重后仍判对', () {
      final result = score(selected: const <String>['A', 'a', ' A ']);
      expect(result.status, ObjectiveAttemptStatus.correct);
      expect(result.selectedLabels, <String>['A']);
    });

    test('单选多选了一项（含正确项与干扰项）→ 因为 extra 判错', () {
      final result = score(selected: const <String>['A', 'B']);
      expect(result.status, ObjectiveAttemptStatus.incorrect);
      expect(result.extraLabels, <String>['B']);
      expect(result.missingLabels, isEmpty);
    });
  });

  group('判分：多选', () {
    test('全对（顺序/大小写无关）→ correct，输出升序去重', () {
      final result = score(
        type: 'multi_choice',
        options: <ObjectiveOption>[
          option('A', true),
          option('B', false),
          option('C', true),
        ],
        selected: const <String>['c', ' A ', 'a'],
      );
      expect(result.status, ObjectiveAttemptStatus.correct);
      expect(result.selectedLabels, <String>['A', 'C']);
      expect(result.correctLabels, <String>['A', 'C']);
      expect(result.missingLabels, isEmpty);
      expect(result.extraLabels, isEmpty);
    });

    test('漏选 → incorrect，缺的进 missing，extra 为空', () {
      final result = score(
        type: 'multi_choice',
        options: <ObjectiveOption>[
          option('A', true),
          option('B', false),
          option('C', true),
        ],
        selected: const <String>['A'],
      );
      expect(result.status, ObjectiveAttemptStatus.incorrect);
      expect(result.missingLabels, <String>['C']);
      expect(result.extraLabels, isEmpty);
    });

    test('多选了一个错误项 → incorrect，extra 列出它', () {
      final result = score(
        type: 'multi_choice',
        options: <ObjectiveOption>[
          option('A', true),
          option('B', false),
          option('C', true),
        ],
        selected: const <String>['A', 'B', 'C'],
      );
      expect(result.status, ObjectiveAttemptStatus.incorrect);
      expect(result.missingLabels, isEmpty);
      expect(result.extraLabels, <String>['B']);
    });

    test('既漏选又多选了错误项 → 两个列表都填', () {
      final result = score(
        type: 'multi_choice',
        options: <ObjectiveOption>[
          option('A', true),
          option('B', false),
          option('C', true),
        ],
        selected: const <String>['A', 'B'],
      );
      expect(result.status, ObjectiveAttemptStatus.incorrect);
      expect(result.missingLabels, <String>['C']);
      expect(result.extraLabels, <String>['B']);
    });

    test('正确选项重复标注/大小写不同 → 去重成一个标签', () {
      final result = score(
        type: 'multi_choice',
        options: <ObjectiveOption>[
          option('A', true),
          option('a', true),
          option(' b ', false),
        ],
        selected: const <String>['A'],
      );
      expect(result.status, ObjectiveAttemptStatus.correct);
      expect(result.correctLabels, <String>['A']);
    });
  });

  group('不可判分', () {
    test('客观题但没有任何 isCorrect → notObjective，不是「全错」', () {
      final result = score(
        options: <ObjectiveOption>[option('A', false), option('B', false)],
        selected: const <String>['A'],
      );
      expect(result.status, ObjectiveAttemptStatus.notObjective);
      expect(result.selectedLabels, isEmpty);
      expect(result.correctLabels, isEmpty);
      expect(result.missingLabels, isEmpty);
      expect(result.extraLabels, isEmpty);
      expect(result.isCorrect, isFalse);
      expect(result.isIncorrect, isFalse);
    });

    test('正确选项全是空标签 → notObjective（空标签不参与正确集合）', () {
      final result = score(
        options: <ObjectiveOption>[option(' ', true), option('', true)],
        selected: const <String>['  '],
      );
      expect(result.status, ObjectiveAttemptStatus.notObjective);
      expect(result.correctLabels, isEmpty);
    });

    test('非客观题型：即使选项标了正确、用户又选了正确项，也不判分', () {
      for (final type in <String>[
        'fill_blank',
        'solution',
        'open',
        '',
        'unknown'
      ]) {
        final result = score(type: type, selected: const <String>['A']);
        expect(result.status, ObjectiveAttemptStatus.notObjective,
            reason: type);
        expect(result.selectedLabels, isEmpty, reason: type);
        expect(result.correctLabels, isEmpty, reason: type);
        expect(result.missingLabels, isEmpty, reason: type);
        expect(result.extraLabels, isEmpty, reason: type);
      }
    });

    test('客观题但 options 为空 → notObjective，不抛异常', () {
      final result = score(
          options: const <ObjectiveOption>[], selected: const <String>['A']);
      expect(result.status, ObjectiveAttemptStatus.notObjective);
      expect(result.correctLabels, isEmpty);
    });
  });

  group('确定性与边界', () {
    test('输出列表确定性升序：选项乱序、选择乱序也一样', () {
      final result = score(
        type: 'multi_choice',
        options: <ObjectiveOption>[
          option('D', true),
          option('B', false),
          option('C', true),
          option('A', true),
        ],
        selected: const <String>['d', 'C', 'a'],
      );
      expect(result.status, ObjectiveAttemptStatus.correct);
      expect(result.selectedLabels, <String>['A', 'C', 'D']);
      expect(result.correctLabels, <String>['A', 'C', 'D']);
    });

    test('extra 也按升序给出', () {
      final result = score(
        type: 'multi_choice',
        options: <ObjectiveOption>[option('A', true)],
        selected: const <String>['d', 'b', 'C'],
      );
      expect(result.status, ObjectiveAttemptStatus.incorrect);
      expect(result.extraLabels, <String>['B', 'C', 'D']);
    });

    test('同一输入两次判分结果完全一致', () {
      final first = score(type: 'multi_choice', selected: const <String>['B']);
      final second = score(type: 'multi_choice', selected: const <String>['B']);
      expect(first.status, second.status);
      expect(first.selectedLabels, second.selectedLabels);
      expect(first.correctLabels, second.correctLabels);
      expect(first.missingLabels, second.missingLabels);
      expect(first.extraLabels, second.extraLabels);
    });

    test('结果列表不可修改（调用方改不坏判分结果）', () {
      final result = score(selected: const <String>['B']);
      expect(result.status, ObjectiveAttemptStatus.incorrect);
      expect(() => result.selectedLabels.add('X'), throwsUnsupportedError);
      expect(() => result.correctLabels.clear(), throwsUnsupportedError);
      expect(() => result.missingLabels.add('X'), throwsUnsupportedError);
      expect(() => result.extraLabels.add('X'), throwsUnsupportedError);
    });
  });
}
