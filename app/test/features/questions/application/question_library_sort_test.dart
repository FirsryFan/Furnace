/// 题库排序纯逻辑的单元测试。
///
/// 覆盖 6 组：空表与单条、newest 保序、serial 升序（null 最后与同号兜底）、
/// wrongFirst 降序（含稳定排序）、返回表不可变与入参不被改动、大表混合与确定性。
/// 全部纯 Dart 构造 [QuestionLibraryEntry] 假数据，不读库。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/questions/application/question_library_reader.dart';
import 'package:furnace/features/questions/application/question_library_sort.dart';

void main() {
  group('空表与单条', () {
    test('空表：三种排序都返回空列表，且不可修改', () {
      for (final QuestionLibrarySort sort in QuestionLibrarySort.values) {
        final List<QuestionLibraryEntry> result =
            sortQuestionLibraryEntries(const <QuestionLibraryEntry>[], sort);
        expect(result, isEmpty, reason: '$sort');
        expect(
            () => result.add(_entry(questionId: 'x')), throwsUnsupportedError,
            reason: '$sort');
      }
    });

    test('单条：三种排序都原样返回这一条', () {
      final QuestionLibraryEntry only =
          _entry(questionId: 'q1', serialNo: 7, wrongAttemptCount: 2);
      for (final QuestionLibrarySort sort in QuestionLibrarySort.values) {
        final List<QuestionLibraryEntry> result =
            sortQuestionLibraryEntries(<QuestionLibraryEntry>[only], sort);
        expect(_ids(result), <String>['q1'], reason: '$sort');
        expect(result.single, same(only), reason: '$sort');
      }
    });
  });

  group('newest：入参原样顺序', () {
    test('不按题号重排：q3/q1/q2 保持原序', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[
        _entry(questionId: 'q3', serialNo: 3),
        _entry(questionId: 'q1', serialNo: 1),
        _entry(questionId: 'q2', serialNo: 2),
      ];
      final List<QuestionLibraryEntry> result =
          sortQuestionLibraryEntries(entries, QuestionLibrarySort.newest);
      expect(_ids(result), <String>['q3', 'q1', 'q2']);
    });

    test('返回的是新列表，不是入参本身', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[
        _entry(questionId: 'q1', serialNo: 1),
      ];
      final List<QuestionLibraryEntry> result =
          sortQuestionLibraryEntries(entries, QuestionLibrarySort.newest);
      expect(result, isNot(same(entries)));
    });
  });

  group('serial：题号升序，未编号最后', () {
    test('按题号升序', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[
        _entry(questionId: 'qA', serialNo: 3),
        _entry(questionId: 'qB', serialNo: 1),
        _entry(questionId: 'qC', serialNo: 2),
      ];
      final List<QuestionLibraryEntry> result =
          sortQuestionLibraryEntries(entries, QuestionLibrarySort.serial);
      expect(_ids(result), <String>['qB', 'qC', 'qA']);
    });

    test('未编号（serialNo null）排最后', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[
        _entry(questionId: 'qNull', serialNo: null),
        _entry(questionId: 'q2', serialNo: 2),
        _entry(questionId: 'q1', serialNo: 1),
      ];
      final List<QuestionLibraryEntry> result =
          sortQuestionLibraryEntries(entries, QuestionLibrarySort.serial);
      expect(_ids(result), <String>['q1', 'q2', 'qNull']);
    });

    test('多个未编号时按 questionId 升序兜底', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[
        _entry(questionId: 'qC', serialNo: null),
        _entry(questionId: 'qA', serialNo: null),
        _entry(questionId: 'qB', serialNo: null),
      ];
      final List<QuestionLibraryEntry> result =
          sortQuestionLibraryEntries(entries, QuestionLibrarySort.serial);
      expect(_ids(result), <String>['qA', 'qB', 'qC']);
    });

    test('同号时按 questionId 升序兜底（与入参顺序无关）', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[
        _entry(questionId: 'q2', serialNo: 5),
        _entry(questionId: 'q1', serialNo: 5),
        _entry(questionId: 'q0', serialNo: 1),
      ];
      final List<QuestionLibraryEntry> result =
          sortQuestionLibraryEntries(entries, QuestionLibrarySort.serial);
      expect(_ids(result), <String>['q0', 'q1', 'q2']);
    });
  });

  group('wrongFirst：答错次数降序，同次数稳定', () {
    test('按答错次数降序', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[
        _entry(questionId: 'q0', serialNo: 1, wrongAttemptCount: 0),
        _entry(questionId: 'q3', serialNo: 2, wrongAttemptCount: 3),
        _entry(questionId: 'q1', serialNo: 3, wrongAttemptCount: 1),
      ];
      final List<QuestionLibraryEntry> result =
          sortQuestionLibraryEntries(entries, QuestionLibrarySort.wrongFirst);
      expect(_ids(result), <String>['q3', 'q1', 'q0']);
    });

    test('同次数保持入参原顺序（稳定排序）', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[
        _entry(questionId: 'a', serialNo: 1, wrongAttemptCount: 2),
        _entry(questionId: 'b', serialNo: 2, wrongAttemptCount: 1),
        _entry(questionId: 'c', serialNo: 3, wrongAttemptCount: 2),
        _entry(questionId: 'd', serialNo: 4, wrongAttemptCount: 1),
        _entry(questionId: 'e', serialNo: 5, wrongAttemptCount: 2),
      ];
      final List<QuestionLibraryEntry> result =
          sortQuestionLibraryEntries(entries, QuestionLibrarySort.wrongFirst);
      expect(_ids(result), <String>['a', 'c', 'e', 'b', 'd']);
    });

    test('全都没答错过：保持入参原顺序', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[
        _entry(questionId: 'q3', serialNo: 3),
        _entry(questionId: 'q1', serialNo: 1),
        _entry(questionId: 'q2', serialNo: 2),
      ];
      final List<QuestionLibraryEntry> result =
          sortQuestionLibraryEntries(entries, QuestionLibrarySort.wrongFirst);
      expect(_ids(result), <String>['q3', 'q1', 'q2']);
    });
  });

  group('返回表不可变、入参不被改动', () {
    test('三种排序都返回不可修改的列表', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[
        _entry(questionId: 'q2', serialNo: 2, wrongAttemptCount: 1),
        _entry(questionId: 'q1', serialNo: 1, wrongAttemptCount: 0),
      ];
      for (final QuestionLibrarySort sort in QuestionLibrarySort.values) {
        final List<QuestionLibraryEntry> result =
            sortQuestionLibraryEntries(entries, sort);
        expect(
            () => result.add(_entry(questionId: 'x')), throwsUnsupportedError,
            reason: '$sort');
        expect(() => result.removeAt(0), throwsUnsupportedError,
            reason: '$sort');
        expect(() => result.clear(), throwsUnsupportedError, reason: '$sort');
      }
    });

    test('三种排序都不改入参的顺序与内容', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[
        _entry(questionId: 'q3', serialNo: 3, wrongAttemptCount: 0),
        _entry(questionId: 'q1', serialNo: null, wrongAttemptCount: 2),
        _entry(questionId: 'q2', serialNo: 2, wrongAttemptCount: 1),
      ];
      final List<String> before = _ids(entries);
      for (final QuestionLibrarySort sort in QuestionLibrarySort.values) {
        sortQuestionLibraryEntries(entries, sort);
        expect(_ids(entries), before, reason: '$sort');
      }
      expect(entries, hasLength(3));
    });

    test('入参是普通可变列表时也不被排序（newest 不原地 sort）', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[
        _entry(questionId: 'b', serialNo: 2),
        _entry(questionId: 'a', serialNo: 1),
      ];
      sortQuestionLibraryEntries(entries, QuestionLibrarySort.serial);
      expect(_ids(entries), <String>['b', 'a']);
    });
  });

  group('大表混合与确定性', () {
    test('serial：30 条混合（含 null 与同号）升序、null 全在末尾、同号按 id', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[];
      for (var i = 0; i < 30; i++) {
        entries.add(_entry(
          questionId: _qid(i),
          serialNo: i % 3 == 0 ? null : (i % 7) + 1,
          wrongAttemptCount: i % 4,
        ));
      }
      final List<QuestionLibraryEntry> result =
          sortQuestionLibraryEntries(entries, QuestionLibrarySort.serial);
      expect(result, hasLength(30));
      final int firstNull = result.indexWhere((e) => e.serialNo == null);
      for (var i = 1; i < result.length; i++) {
        final int? previous = result[i - 1].serialNo;
        final int? current = result[i].serialNo;
        if (previous != null && current != null) {
          expect(previous, lessThanOrEqualTo(current));
          if (previous == current) {
            final int byId =
                result[i - 1].questionId.compareTo(result[i].questionId);
            expect(byId, lessThanOrEqualTo(0),
                reason: '同号 $previous 应按 questionId 升序，实际 '
                    '${result[i - 1].questionId} vs ${result[i].questionId}');
          }
        } else if (previous == null) {
          expect(current, isNull, reason: 'null 之后不能再出现已编号');
        }
      }
      expect(firstNull, greaterThan(0));
    });

    test('wrongFirst：30 条混合降序、同次数保持原序', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[];
      for (var i = 0; i < 30; i++) {
        entries.add(_entry(
          questionId: _qid(i),
          serialNo: i,
          wrongAttemptCount: i % 5,
        ));
      }
      final List<QuestionLibraryEntry> result =
          sortQuestionLibraryEntries(entries, QuestionLibrarySort.wrongFirst);
      expect(result, hasLength(30));
      for (var i = 1; i < result.length; i++) {
        expect(result[i - 1].wrongAttemptCount,
            greaterThanOrEqualTo(result[i].wrongAttemptCount));
      }
      // 同次数内部：入参里靠前的仍在前面。
      final Map<int, List<String>> originalByCount = <int, List<String>>{};
      for (final QuestionLibraryEntry entry in entries) {
        originalByCount
            .putIfAbsent(entry.wrongAttemptCount, () => <String>[])
            .add(entry.questionId);
      }
      final Map<int, List<String>> sortedByCount = <int, List<String>>{};
      for (final QuestionLibraryEntry entry in result) {
        sortedByCount
            .putIfAbsent(entry.wrongAttemptCount, () => <String>[])
            .add(entry.questionId);
      }
      for (final MapEntry<int, List<String>> group in sortedByCount.entries) {
        expect(group.value, originalByCount[group.key],
            reason: '答错次数 ${group.key} 应保持入参顺序');
      }
    });

    test('确定性：同一输入两次排序结果 questionId 序列相同', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[
        _entry(questionId: 'q2', serialNo: null, wrongAttemptCount: 1),
        _entry(questionId: 'q1', serialNo: 5, wrongAttemptCount: 1),
        _entry(questionId: 'q3', serialNo: 5, wrongAttemptCount: 0),
        _entry(questionId: 'q4', serialNo: null, wrongAttemptCount: 2),
      ];
      for (final QuestionLibrarySort sort in QuestionLibrarySort.values) {
        final List<String> first =
            _ids(sortQuestionLibraryEntries(entries, sort));
        final List<String> second =
            _ids(sortQuestionLibraryEntries(entries, sort));
        expect(second, first, reason: '$sort');
      }
    });
  });
}

QuestionLibraryEntry _entry({
  required String questionId,
  int? serialNo,
  int wrongAttemptCount = 0,
}) {
  return QuestionLibraryEntry(
    questionId: questionId,
    serialNo: serialNo,
    stem: '题干 $questionId',
    subjectKey: 'math',
    sourceLevel: 'school',
    sourceLabel: '校卷',
    wrongAttemptCount: wrongAttemptCount,
  );
}

String _qid(int index) => index < 10 ? 'q0$index' : 'q$index';

List<String> _ids(List<QuestionLibraryEntry> entries) {
  return <String>[
    for (final QuestionLibraryEntry entry in entries) entry.questionId
  ];
}
