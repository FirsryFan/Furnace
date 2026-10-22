/// 题库批量打标签计划的单元测试（纯逻辑，不读库）。
///
/// 覆盖 6 组：空输入与边界、id/路径规范化、可用与缺失分类、
/// 已挂标签跳过、多题多标签矩阵与顺序、不可变/toString/确定性。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_bulk_tag_plan.dart';

void main() {
  group('空输入与边界', () {
    test('全空输入返回空计划', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>[],
        tagPaths: const <String>[],
        knownTagPaths: const <String>[],
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.isNotEmpty, isFalse);
      expect(plan.usableTagPaths, isEmpty);
      expect(plan.missingTagPaths, isEmpty);
      expect(plan.questionIdsByTagPath, isEmpty);
      expect(plan.linkCount, 0);
      expect(plan.affectedQuestionCount, 0);
      expect(plan.skippedExistingLinkCount, 0);
      expect(plan.hasMissingTagPaths, isFalse);
      expect(plan.requestedTagPathCount, 0);
    });

    test('题目为空时即使有标签也返回空计划', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>[],
        tagPaths: const <String>['a'],
        knownTagPaths: const <String>['a'],
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.usableTagPaths, isEmpty);
      expect(plan.missingTagPaths, isEmpty);
    });

    test('标签为空时返回空计划', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1'],
        tagPaths: const <String>[],
        knownTagPaths: const <String>['a'],
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.questionIdsByTagPath, isEmpty);
    });

    test('只有空白题 id 与路径时返回空计划', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['  ', '\t'],
        tagPaths: const <String>[' ', '\n'],
        knownTagPaths: const <String>['a'],
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.linkCount, 0);
    });

    test('空计划 toString 可读', () {
      const QuestionBulkTagPlan plan = QuestionBulkTagPlan.empty;
      expect(plan.toString(), contains('usable: 0'));
      expect(plan.toString(), contains('links: 0'));
    });

    test('空输入重复调用不抛且保持一致', () {
      final QuestionBulkTagPlan first = planQuestionBulkTag(
        questionIds: const <String>[],
        tagPaths: const <String>[],
        knownTagPaths: const <String>[],
      );
      final QuestionBulkTagPlan second = planQuestionBulkTag(
        questionIds: const <String>[],
        tagPaths: const <String>[],
        knownTagPaths: const <String>[],
      );
      expect(first.isEmpty, second.isEmpty);
      expect(first.linkCount, second.linkCount);
    });
  });

  group('id 与路径规范化', () {
    test('题 id 做 trim、去空、去重并保序', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>[' q2 ', 'q1', '', 'q2', '   '],
        tagPaths: const <String>['a'],
        knownTagPaths: const <String>['a'],
      );
      expect(plan.questionIdsByTagPath['a'], <String>['q2', 'q1']);
      expect(plan.linkCount, 2);
      expect(plan.affectedQuestionCount, 2);
    });

    test('标签路径做 trim、去空、去重并保序', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1'],
        tagPaths: const <String>[' b ', 'a', 'b', ' '],
        knownTagPaths: const <String>['a', 'b'],
      );
      expect(plan.usableTagPaths, <String>['b', 'a']);
      expect(plan.missingTagPaths, isEmpty);
      expect(plan.linkCount, 2);
    });

    test('knownTagPaths 先 trim 再比较，空项忽略', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1'],
        tagPaths: const <String>['a', 'b'],
        knownTagPaths: const <String>[' a ', '', '   '],
      );
      expect(plan.usableTagPaths, <String>['a']);
      expect(plan.missingTagPaths, <String>['b']);
    });

    test('路径比较大小写敏感', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1'],
        tagPaths: const <String>['math', 'Math'],
        knownTagPaths: const <String>['Math'],
      );
      expect(plan.usableTagPaths, <String>['Math']);
      expect(plan.missingTagPaths, <String>['math']);
    });

    test('路径分隔符原样比较', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1'],
        tagPaths: const <String>['/a/b', '/a//b'],
        knownTagPaths: const <String>['/a/b', '/a//b'],
      );
      expect(plan.usableTagPaths, <String>['/a/b', '/a//b']);
      expect(plan.missingTagPaths, isEmpty);
    });

    test('重复请求的路径只计一次', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1', 'q2'],
        tagPaths: const <String>['a', 'a', ' a '],
        knownTagPaths: const <String>['a'],
      );
      expect(plan.usableTagPaths, <String>['a']);
      expect(plan.requestedTagPathCount, 1);
      expect(plan.linkCount, 2);
    });
  });

  group('可用与缺失分类', () {
    test('单题单可用标签生成一条挂载', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1'],
        tagPaths: const <String>['a'],
        knownTagPaths: const <String>['a'],
      );
      expect(plan.usableTagPaths, <String>['a']);
      expect(plan.missingTagPaths, isEmpty);
      expect(plan.questionIdsByTagPath, <String, List<String>>{
        'a': <String>['q1'],
      });
      expect(plan.linkCount, 1);
      expect(plan.affectedQuestionCount, 1);
      expect(plan.skippedExistingLinkCount, 0);
      expect(plan.isEmpty, isFalse);
      expect(plan.hasMissingTagPaths, isFalse);
      expect(plan.requestedTagPathCount, 1);
    });

    test('未知路径只进缺失列表且不产生挂载', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1'],
        tagPaths: const <String>['x'],
        knownTagPaths: const <String>[],
      );
      expect(plan.usableTagPaths, isEmpty);
      expect(plan.missingTagPaths, <String>['x']);
      expect(plan.questionIdsByTagPath, isEmpty);
      expect(plan.linkCount, 0);
      expect(plan.affectedQuestionCount, 0);
      expect(plan.isEmpty, isFalse);
      expect(plan.hasMissingTagPaths, isTrue);
    });

    test('可用与缺失各自按请求顺序分开', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1'],
        tagPaths: const <String>['x', 'a', 'y', 'b'],
        knownTagPaths: const <String>['a', 'b'],
      );
      expect(plan.usableTagPaths, <String>['a', 'b']);
      expect(plan.missingTagPaths, <String>['x', 'y']);
    });

    test('全部路径都缺失时 map 为空但计划非空', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1', 'q2'],
        tagPaths: const <String>['x', 'y'],
        knownTagPaths: const <String>[],
      );
      expect(plan.usableTagPaths, isEmpty);
      expect(plan.missingTagPaths, <String>['x', 'y']);
      expect(plan.questionIdsByTagPath, isEmpty);
      expect(plan.isEmpty, isFalse);
    });

    test('knownTagPaths 只有空白时全部缺失', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1'],
        tagPaths: const <String>['x'],
        knownTagPaths: const <String>['  '],
      );
      expect(plan.missingTagPaths, <String>['x']);
    });

    test('缺失路径不参与已挂跳过统计', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1'],
        tagPaths: const <String>['x'],
        knownTagPaths: const <String>[],
        existingTagPathsByQuestionId: const <String, Set<String>>{
          'q1': <String>{'x'},
        },
      );
      expect(plan.missingTagPaths, <String>['x']);
      expect(plan.skippedExistingLinkCount, 0);
      expect(plan.linkCount, 0);
    });
  });

  group('已挂标签跳过', () {
    test('全部题都已挂时为空计划并记录跳过数', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1', 'q2'],
        tagPaths: const <String>['a'],
        knownTagPaths: const <String>['a'],
        existingTagPathsByQuestionId: const <String, Set<String>>{
          'q1': <String>{'a'},
          'q2': <String>{'a'},
        },
      );
      expect(plan.usableTagPaths, <String>['a']);
      expect(plan.questionIdsByTagPath, isEmpty);
      expect(plan.linkCount, 0);
      expect(plan.affectedQuestionCount, 0);
      expect(plan.skippedExistingLinkCount, 2);
      expect(plan.isEmpty, isTrue);
    });

    test('部分题已挂时只给未挂的题挂载', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1', 'q2', 'q3'],
        tagPaths: const <String>['a'],
        knownTagPaths: const <String>['a'],
        existingTagPathsByQuestionId: const <String, Set<String>>{
          'q2': <String>{'a'},
        },
      );
      expect(plan.questionIdsByTagPath, <String, List<String>>{
        'a': <String>['q1', 'q3'],
      });
      expect(plan.skippedExistingLinkCount, 1);
      expect(plan.linkCount, 2);
      expect(plan.affectedQuestionCount, 2);
    });

    test('多标签异构已挂按 (题, 路径) 对分别计数', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1', 'q2'],
        tagPaths: const <String>['a', 'b'],
        knownTagPaths: const <String>['a', 'b'],
        existingTagPathsByQuestionId: const <String, Set<String>>{
          'q1': <String>{'a'},
        },
      );
      expect(plan.questionIdsByTagPath, <String, List<String>>{
        'a': <String>['q2'],
        'b': <String>['q1', 'q2'],
      });
      expect(plan.skippedExistingLinkCount, 1);
      expect(plan.linkCount, 3);
      expect(plan.affectedQuestionCount, 2);
    });

    test('不含某题的键视为该题没有已挂标签', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1', 'q2', 'q3'],
        tagPaths: const <String>['a'],
        knownTagPaths: const <String>['a'],
        existingTagPathsByQuestionId: const <String, Set<String>>{
          'q2': <String>{'a'},
        },
      );
      expect(plan.questionIdsByTagPath['a'], <String>['q1', 'q3']);
    });

    test('已挂集合里的无关路径不影响结果', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1', 'q2'],
        tagPaths: const <String>['a'],
        knownTagPaths: const <String>['a'],
        existingTagPathsByQuestionId: const <String, Set<String>>{
          'q1': <String>{'other', 'a'},
        },
      );
      expect(plan.questionIdsByTagPath['a'], <String>['q2']);
      expect(plan.skippedExistingLinkCount, 1);
    });

    test('已挂路径按原样精确比较，不做 trim', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1'],
        tagPaths: const <String>['a'],
        knownTagPaths: const <String>['a'],
        existingTagPathsByQuestionId: const <String, Set<String>>{
          'q1': <String>{' a '},
        },
      );
      expect(plan.skippedExistingLinkCount, 0);
      expect(plan.linkCount, 1);
    });

    test('多路径全部已挂时跳过数按对累加', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1'],
        tagPaths: const <String>['a', 'b'],
        knownTagPaths: const <String>['a', 'b'],
        existingTagPathsByQuestionId: const <String, Set<String>>{
          'q1': <String>{'a', 'b'},
        },
      );
      expect(plan.skippedExistingLinkCount, 2);
      expect(plan.linkCount, 0);
      expect(plan.isEmpty, isTrue);
    });
  });

  group('多题多标签矩阵与顺序', () {
    test('2 题 2 标签全量矩阵', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q2', 'q1'],
        tagPaths: const <String>['t2', 't1'],
        knownTagPaths: const <String>['t1', 't2'],
      );
      expect(plan.questionIdsByTagPath, <String, List<String>>{
        't2': <String>['q2', 'q1'],
        't1': <String>['q2', 'q1'],
      });
      expect(plan.linkCount, 4);
      expect(plan.affectedQuestionCount, 2);
    });

    test('map 键顺序跟随可用路径顺序', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1'],
        tagPaths: const <String>['b', 'a'],
        knownTagPaths: const <String>['a', 'b'],
      );
      expect(plan.questionIdsByTagPath.keys.toList(), <String>['b', 'a']);
    });

    test('完全被跳过的路径不出现在 map 里', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1', 'q2'],
        tagPaths: const <String>['a', 'b'],
        knownTagPaths: const <String>['a', 'b'],
        existingTagPathsByQuestionId: const <String, Set<String>>{
          'q1': <String>{'a'},
          'q2': <String>{'a'},
        },
      );
      expect(plan.questionIdsByTagPath.keys.toList(), <String>['b']);
      expect(plan.linkCount, 2);
      expect(plan.skippedExistingLinkCount, 2);
    });

    test('每题待挂题 id 保持请求顺序', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q3', 'q1', 'q2'],
        tagPaths: const <String>['a'],
        knownTagPaths: const <String>['a'],
      );
      expect(plan.questionIdsByTagPath['a'], <String>['q3', 'q1', 'q2']);
    });

    test('汇总计数在多标签多题下正确', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1', 'q2', 'q3'],
        tagPaths: const <String>['a', 'b'],
        knownTagPaths: const <String>['a', 'b'],
        existingTagPathsByQuestionId: const <String, Set<String>>{
          'q2': <String>{'a'},
        },
      );
      expect(plan.skippedExistingLinkCount, 1);
      expect(plan.linkCount, 5);
      expect(plan.affectedQuestionCount, 3);
      expect(plan.requestedTagPathCount, 2);
    });

    test('缺失与已挂混合时互不影响', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1', 'q2'],
        tagPaths: const <String>['a', 'x'],
        knownTagPaths: const <String>['a'],
        existingTagPathsByQuestionId: const <String, Set<String>>{
          'q1': <String>{'a'},
        },
      );
      expect(plan.usableTagPaths, <String>['a']);
      expect(plan.missingTagPaths, <String>['x']);
      expect(plan.questionIdsByTagPath['a'], <String>['q2']);
      expect(plan.skippedExistingLinkCount, 1);
      expect(plan.linkCount, 1);
      expect(plan.affectedQuestionCount, 1);
    });
  });

  group('不可变、toString、确定性', () {
    test('usableTagPaths 不可变', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1'],
        tagPaths: const <String>['a', 'b'],
        knownTagPaths: const <String>['a', 'b'],
      );
      expect(() => plan.usableTagPaths.add('z'), throwsUnsupportedError);
    });

    test('missingTagPaths 不可变', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1'],
        tagPaths: const <String>['x'],
        knownTagPaths: const <String>[],
      );
      expect(() => plan.missingTagPaths.clear(), throwsUnsupportedError);
    });

    test('questionIdsByTagPath 与内层列表都不可变', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1'],
        tagPaths: const <String>['a'],
        knownTagPaths: const <String>['a'],
      );
      expect(
        () => plan.questionIdsByTagPath['a']!.add('q2'),
        throwsUnsupportedError,
      );
      expect(
        () => plan.questionIdsByTagPath.remove('a'),
        throwsUnsupportedError,
      );
    });

    test('toString 含计数信息', () {
      final QuestionBulkTagPlan plan = planQuestionBulkTag(
        questionIds: const <String>['q1'],
        tagPaths: const <String>['a', 'x'],
        knownTagPaths: const <String>['a'],
        existingTagPathsByQuestionId: const <String, Set<String>>{
          'q1': <String>{'a'},
        },
      );
      expect(plan.toString(), contains('usable: 1'));
      expect(plan.toString(), contains('missing: 1'));
      expect(plan.toString(), contains('links: 0'));
      expect(plan.toString(), contains('skipped: 1'));
    });

    test('相同输入两次调用结果一致', () {
      final QuestionBulkTagPlan first = planQuestionBulkTag(
        questionIds: const <String>['q2', 'q1'],
        tagPaths: const <String>['a', 'b'],
        knownTagPaths: const <String>['a'],
        existingTagPathsByQuestionId: const <String, Set<String>>{
          'q1': <String>{'a'},
        },
      );
      final QuestionBulkTagPlan second = planQuestionBulkTag(
        questionIds: const <String>['q2', 'q1'],
        tagPaths: const <String>['a', 'b'],
        knownTagPaths: const <String>['a'],
        existingTagPathsByQuestionId: const <String, Set<String>>{
          'q1': <String>{'a'},
        },
      );
      expect(second.usableTagPaths, first.usableTagPaths);
      expect(second.questionIdsByTagPath, first.questionIdsByTagPath);
      expect(second.linkCount, first.linkCount);
      expect(second.skippedExistingLinkCount, first.skippedExistingLinkCount);
    });

    test('怪异输入不抛异常且结果可预期', () {
      late final QuestionBulkTagPlan plan;
      expect(
        () => plan = planQuestionBulkTag(
          questionIds: const <String>['🧪q', ' 中文题 ', 'q', '', '🧪q'],
          tagPaths: const <String>[' 标签/一 ', '标签/一', 'a b', '🧪'],
          knownTagPaths: const <String>['标签/一', 'a b'],
          existingTagPathsByQuestionId: const <String, Set<String>>{
            'q': <String>{'🧪'},
          },
        ),
        returnsNormally,
      );
      expect(plan.usableTagPaths, <String>['标签/一', 'a b']);
      expect(plan.missingTagPaths, <String>['🧪']);
      expect(plan.linkCount, 6);
      expect(plan.affectedQuestionCount, 3);
      expect(plan.skippedExistingLinkCount, 0);
    });
  });
}
