import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_search_plan.dart';

QuestionSearchPlan planOf(String raw, {int maxSerialCount = 200}) =>
    parseQuestionSearchPlan(raw, maxSerialCount: maxSerialCount);

void main() {
  group('空输入与纯空白', () {
    test('空串返回空计划', () {
      final QuestionSearchPlan plan = planOf('');
      expect(plan.raw, '');
      expect(plan.isEmpty, isTrue);
      expect(plan.stemContains, isNull);
      expect(plan.serialNos, isEmpty);
      expect(plan.rejectedSegments, isEmpty);
      expect(plan.truncated, isFalse);
      expect(plan.isSerialOnly, isFalse);
      expect(plan.isStemOnly, isFalse);
      expect(plan.serialCount, 0);
    });

    test('纯空格保留原始输入但语义为空', () {
      final QuestionSearchPlan plan = planOf('   ');
      expect(plan.raw, '   ');
      expect(plan.isEmpty, isTrue);
      expect(plan.stemContains, isNull);
      expect(plan.serialNos, isEmpty);
    });

    test('制表符换行与全角空格都是空白', () {
      expect(planOf('\t\n　 ').isEmpty, isTrue);
    });

    test('全角空格单独输入也是空计划', () {
      final QuestionSearchPlan plan = planOf('　');
      expect(plan.isEmpty, isTrue);
      expect(plan.raw, '　');
    });

    test('空计划 toJson 的键与值', () {
      final Map<String, Object?> json = planOf('').toJson();
      expect(
        json.keys.toList(),
        orderedEquals(<String>[
          'raw',
          'stem_contains',
          'serial_nos',
          'rejected_segments',
          'truncated',
        ]),
      );
      expect(json['raw'], '');
      expect(json['stem_contains'], isNull);
      expect(json['serial_nos'], <int>[]);
      expect(json['rejected_segments'], <String>[]);
      expect(json['truncated'], isFalse);
    });
  });

  group('纯单号', () {
    test('单号', () {
      final QuestionSearchPlan plan = planOf('7');
      expect(plan.serialNos, <int>[7]);
      expect(plan.serialCount, 1);
      expect(plan.stemContains, isNull);
      expect(plan.isSerialOnly, isTrue);
      expect(plan.isEmpty, isFalse);
      expect(plan.truncated, isFalse);
    });

    test('TR-00042 前缀写法', () {
      expect(planOf('TR-00042').serialNos, <int>[42]);
    });

    test('小写 tr-42', () {
      expect(planOf('tr-42').serialNos, <int>[42]);
    });

    test('没有连字符的 TR42', () {
      expect(planOf('TR42').serialNos, <int>[42]);
    });

    test('井号写法', () {
      expect(planOf('#7').serialNos, <int>[7]);
    });

    test('全角井号与全角数字', () {
      expect(planOf('＃７').serialNos, <int>[7]);
    });

    test('补零写法', () {
      expect(planOf('00042').serialNos, <int>[42]);
    });

    test('全角数字', () {
      expect(planOf('１２').serialNos, <int>[12]);
    });

    test('前后空白不影响解析但 raw 保留原样', () {
      final QuestionSearchPlan plan = planOf(' 12 ');
      expect(plan.serialNos, <int>[12]);
      expect(plan.raw, ' 12 ');
    });

    test('同一个题号写两遍只留一个', () {
      final QuestionSearchPlan plan = planOf('7,7');
      expect(plan.serialNos, <int>[7]);
      expect(plan.serialCount, 1);
      expect(plan.rejectedSegments, isEmpty);
    });
  });

  group('多号与分隔符', () {
    test('半角逗号', () {
      expect(planOf('1,2,3').serialNos, <int>[1, 2, 3]);
    });

    test('全角逗号', () {
      expect(planOf('1，2，3').serialNos, <int>[1, 2, 3]);
    });

    test('顿号', () {
      expect(planOf('1、2、3').serialNos, <int>[1, 2, 3]);
    });

    test('半角分号', () {
      expect(planOf('1;2;3').serialNos, <int>[1, 2, 3]);
    });

    test('全角分号', () {
      expect(planOf('1；2；3').serialNos, <int>[1, 2, 3]);
    });

    test('空白分隔', () {
      expect(planOf('3 1 2').serialNos, <int>[1, 2, 3]);
    });

    test('分隔符混用', () {
      expect(planOf('3,1 2、1').serialNos, <int>[1, 2, 3]);
    });

    test('题号写法混用', () {
      expect(planOf('TR-1,#2,３').serialNos, <int>[1, 2, 3]);
    });
  });

  group('区间', () {
    test('两个点连接符', () {
      final QuestionSearchPlan plan = planOf('1..5');
      expect(plan.serialNos, <int>[1, 2, 3, 4, 5]);
      expect(plan.truncated, isFalse);
      expect(plan.isSerialOnly, isTrue);
    });

    test('波浪号连接符', () {
      expect(planOf('1~5').serialNos, <int>[1, 2, 3, 4, 5]);
    });

    test('破折号连接符', () {
      expect(planOf('1—5').serialNos, <int>[1, 2, 3, 4, 5]);
    });

    test('连字符连接符只用于纯数字两端', () {
      expect(planOf('1-5').serialNos, <int>[1, 2, 3, 4, 5]);
    });

    test('降序区间也按升序展开', () {
      expect(planOf('5..1').serialNos, <int>[1, 2, 3, 4, 5]);
    });

    test('带 TR 前缀的区间', () {
      expect(planOf('TR-3..TR-5').serialNos, <int>[3, 4, 5]);
    });

    test('空白分隔的区间', () {
      final QuestionSearchPlan plan = planOf('1 - 5');
      expect(plan.serialNos, <int>[1, 2, 3, 4, 5]);
      expect(plan.rejectedSegments, isEmpty);
      expect(plan.stemContains, isNull);
    });

    test('空白分隔的两点区间', () {
      expect(planOf('1 .. 5').serialNos, <int>[1, 2, 3, 4, 5]);
    });

    test('相邻区间合并', () {
      expect(planOf('1..2,3..4').serialNos, <int>[1, 2, 3, 4]);
    });

    test('重叠区间合并', () {
      expect(planOf('1..5,3..7').serialNos, <int>[1, 2, 3, 4, 5, 6, 7]);
    });

    test('区间与单号混用', () {
      expect(planOf('1..5,7').serialNos, <int>[1, 2, 3, 4, 5, 7]);
    });

    test('井号区间', () {
      expect(planOf('#1..3').serialNos, <int>[1, 2, 3]);
    });
  });

  group('区间上限与截断', () {
    test('超过上限保留最小的题号', () {
      final QuestionSearchPlan plan = planOf('1..5,10', maxSerialCount: 5);
      expect(plan.serialNos, <int>[1, 2, 3, 4, 5]);
      expect(plan.truncated, isTrue);
    });

    test('刚好等于上限不截断', () {
      final QuestionSearchPlan plan = planOf('1..5,10', maxSerialCount: 6);
      expect(plan.serialNos, <int>[1, 2, 3, 4, 5, 10]);
      expect(plan.truncated, isFalse);
    });

    test('上限为 0 时没有题号但标记截断', () {
      final QuestionSearchPlan plan = planOf('1,2,3', maxSerialCount: 0);
      expect(plan.serialNos, isEmpty);
      expect(plan.truncated, isTrue);
      expect(plan.stemContains, '1,2,3');
      expect(plan.isEmpty, isFalse);
      expect(plan.isStemOnly, isTrue);
    });

    test('上限为负数同样截断', () {
      final QuestionSearchPlan plan = planOf('1..5', maxSerialCount: -3);
      expect(plan.serialNos, isEmpty);
      expect(plan.truncated, isTrue);
      expect(plan.stemContains, '1..5');
    });

    test('上限为 0 且没有可认题号时不截断', () {
      final QuestionSearchPlan plan = planOf('函数', maxSerialCount: 0);
      expect(plan.serialNos, isEmpty);
      expect(plan.truncated, isFalse);
      expect(plan.stemContains, '函数');
    });

    test('超大区间只展开前几个', () {
      final QuestionSearchPlan plan = planOf('1..1000', maxSerialCount: 3);
      expect(plan.serialNos, <int>[1, 2, 3]);
      expect(plan.truncated, isTrue);
    });

    test('默认上限为 200', () {
      final QuestionSearchPlan plan = planOf('1..250');
      expect(plan.serialNos.length, 200);
      expect(plan.serialNos.first, 1);
      expect(plan.serialNos.last, 200);
      expect(plan.truncated, isTrue);
    });

    test('刚好 200 个不截断', () {
      final QuestionSearchPlan plan = planOf('1..200');
      expect(plan.serialNos.length, 200);
      expect(plan.truncated, isFalse);
    });

    test('硬上限防止超大区间吃内存', () {
      final QuestionSearchPlan plan =
          planOf('1..300000', maxSerialCount: 1000000);
      expect(plan.serialNos.length, kQuestionSearchPlanSerialHardLimit);
      expect(plan.serialNos.last, kQuestionSearchPlanSerialHardLimit);
      expect(plan.truncated, isTrue);
    });
  });

  group('混合题号与题干', () {
    test('题号加一个关键词', () {
      final QuestionSearchPlan plan = planOf('7 函数');
      expect(plan.serialNos, <int>[7]);
      expect(plan.stemContains, '函数');
      expect(plan.isSerialOnly, isFalse);
      expect(plan.isStemOnly, isFalse);
    });

    test('前缀题号加关键词', () {
      final QuestionSearchPlan plan = planOf('TR-1 二次函数');
      expect(plan.serialNos, <int>[1]);
      expect(plan.stemContains, '二次函数');
    });

    test('多个关键词保留原顺序并用单空格连接', () {
      final QuestionSearchPlan plan = planOf('1 已知 函数 图像');
      expect(plan.serialNos, <int>[1]);
      expect(plan.stemContains, '已知 函数 图像');
    });

    test('区间加关键词', () {
      final QuestionSearchPlan plan = planOf('1..3 导数');
      expect(plan.serialNos, <int>[1, 2, 3]);
      expect(plan.stemContains, '导数');
    });

    test('关键词写在题号前面', () {
      final QuestionSearchPlan plan = planOf('函数 1');
      expect(plan.serialNos, <int>[1]);
      expect(plan.stemContains, '函数');
    });

    test('多个题号与多个关键词交错', () {
      final QuestionSearchPlan plan = planOf('1 2 函数 图像');
      expect(plan.serialNos, <int>[1, 2]);
      expect(plan.stemContains, '函数 图像');
    });

    test('逗号分隔的题号与关键词', () {
      final QuestionSearchPlan plan = planOf('7,函数,9');
      expect(plan.serialNos, <int>[7, 9]);
      expect(plan.stemContains, '函数');
    });
  });

  group('坏区间与拒绝段', () {
    test('一端不是题号的区间进拒绝段', () {
      final QuestionSearchPlan plan = planOf('1..x');
      expect(plan.serialNos, isEmpty);
      expect(plan.rejectedSegments, <String>['1..x']);
      expect(plan.stemContains, '1..x');
      expect(plan.isStemOnly, isTrue);
      expect(plan.isEmpty, isFalse);
    });

    test('另一端非法同样整段拒绝', () {
      final QuestionSearchPlan plan = planOf('x..1');
      expect(plan.serialNos, isEmpty);
      expect(plan.rejectedSegments, <String>['x..1']);
      expect(plan.stemContains, 'x..1');
    });

    test('区间缺右边', () {
      final QuestionSearchPlan plan = planOf('1..');
      expect(plan.rejectedSegments, <String>['1..']);
      expect(plan.serialNos, isEmpty);
      expect(plan.stemContains, '1..');
    });

    test('区间缺左边', () {
      final QuestionSearchPlan plan = planOf('..5');
      expect(plan.rejectedSegments, <String>['..5']);
      expect(plan.serialNos, isEmpty);
    });

    test('多个连接符整段拒绝', () {
      final QuestionSearchPlan plan = planOf('1..5..9');
      expect(plan.rejectedSegments, <String>['1..5..9']);
      expect(plan.serialNos, isEmpty);
    });

    test('有题号时坏区间不进题干', () {
      final QuestionSearchPlan plan = planOf('2 abc 3..x');
      expect(plan.serialNos, <int>[2]);
      expect(plan.stemContains, 'abc');
      expect(plan.rejectedSegments, <String>['3..x']);
      expect(plan.isSerialOnly, isFalse);
    });

    test('空白分隔的坏区间整段拒绝', () {
      final QuestionSearchPlan plan = planOf('1 - x');
      expect(plan.serialNos, isEmpty);
      expect(plan.rejectedSegments, <String>['1 - x']);
      expect(plan.stemContains, '1 - x');
    });

    test('含连字符的普通文字当题干', () {
      final QuestionSearchPlan plan = planOf('abc-def');
      expect(plan.serialNos, isEmpty);
      expect(plan.rejectedSegments, isEmpty);
      expect(plan.stemContains, 'abc-def');
    });

    test('TR-1-2 这类写法不拆坏', () {
      final QuestionSearchPlan plan = planOf('TR-1-2');
      expect(plan.serialNos, isEmpty);
      expect(plan.rejectedSegments, isEmpty);
      expect(plan.stemContains, 'TR-1-2');
    });

    test('连接符两侧都不是题号时当题干', () {
      final QuestionSearchPlan plan = planOf('abc..def');
      expect(plan.serialNos, isEmpty);
      expect(plan.rejectedSegments, isEmpty);
      expect(plan.stemContains, 'abc..def');
    });
  });

  group('回退与题干形态', () {
    test('只有分隔符时题干回退成整段输入', () {
      final QuestionSearchPlan plan = planOf(',,,');
      expect(plan.serialNos, isEmpty);
      expect(plan.rejectedSegments, isEmpty);
      expect(plan.stemContains, ',,,');
      expect(plan.isStemOnly, isTrue);
      expect(plan.isEmpty, isFalse);
    });

    test('没有题号时题干关键词是整段 trim 后的输入', () {
      final QuestionSearchPlan plan = planOf('（  ）');
      expect(plan.stemContains, '（  ）');
    });

    test('英文关键词与题号混合', () {
      final QuestionSearchPlan plan = planOf('function 7');
      expect(plan.serialNos, <int>[7]);
      expect(plan.stemContains, 'function');
    });

    test('单独的连接符 token 进拒绝段', () {
      final QuestionSearchPlan plan = planOf('..');
      expect(plan.rejectedSegments, <String>['..']);
      expect(plan.serialNos, isEmpty);
      expect(plan.stemContains, '..');
    });

    test('单独的连字符 token 当题干而不是拒绝段', () {
      final QuestionSearchPlan plan = planOf('-');
      expect(plan.rejectedSegments, isEmpty);
      expect(plan.stemContains, '-');
    });

    test('emoji 与题号混合', () {
      final QuestionSearchPlan plan = planOf('😀 1');
      expect(plan.serialNos, <int>[1]);
      expect(plan.stemContains, '😀');
    });

    test('题号 0 当题干', () {
      final QuestionSearchPlan plan = planOf('0');
      expect(plan.serialNos, isEmpty);
      expect(plan.stemContains, '0');
    });

    test('超过 9 位的数字当题干', () {
      final QuestionSearchPlan plan = planOf('0000000001');
      expect(plan.serialNos, isEmpty);
      expect(plan.stemContains, '0000000001');
    });

    test('区间端点位数超限整段拒绝', () {
      final QuestionSearchPlan plan = planOf('1..0000000001');
      expect(plan.rejectedSegments, <String>['1..0000000001']);
      expect(plan.serialNos, isEmpty);
    });
  });

  group('相等性与 JSON', () {
    test('toJson 的键名、键序与取值', () {
      final Map<String, Object?> json = planOf('7 函数').toJson();
      expect(
        json.keys.toList(),
        orderedEquals(<String>[
          'raw',
          'stem_contains',
          'serial_nos',
          'rejected_segments',
          'truncated',
        ]),
      );
      expect(json['raw'], '7 函数');
      expect(json['stem_contains'], '函数');
      expect(json['serial_nos'], <int>[7]);
      expect(json['rejected_segments'], <String>[]);
      expect(json['truncated'], isFalse);
    });

    test('toJson 带拒绝段与截断标记', () {
      final Map<String, Object?> json =
          planOf('2,3 4..x', maxSerialCount: 1).toJson();
      expect(json['raw'], '2,3 4..x');
      expect(json['stem_contains'], isNull);
      expect(json['serial_nos'], <int>[2]);
      expect(json['rejected_segments'], <String>['4..x']);
      expect(json['truncated'], isTrue);
    });

    test('toJson 可被 jsonEncode', () {
      final Map<String, Object?> decoded =
          jsonDecode(jsonEncode(planOf('1..3 函数').toJson()))
              as Map<String, Object?>;
      expect(decoded['serial_nos'], <int>[1, 2, 3]);
      expect(decoded['stem_contains'], '函数');
    });

    test('相等性只看语义字段，不看 raw', () {
      expect(planOf(' 7 '), planOf('7'));
      expect(planOf(' 7 ').hashCode, planOf('7').hashCode);
    });

    test('题干不同就不相等', () {
      expect(planOf('7 函数'), isNot(planOf('7 导数')));
    });

    test('拒绝段不同就不相等', () {
      expect(planOf('1..x'), isNot(planOf('1..y')));
    });

    test('toString 给出题号数、题干与拒绝段数', () {
      final String text = planOf('7 函数').toString();
      expect(text, contains('serialCount: 1'));
      expect(text, contains('stemContains: 函数'));
      expect(text, contains('rejected: 0'));
      expect(text, contains('truncated: false'));
    });

    test('同一输入两次解析结果相同且列表不可修改', () {
      final QuestionSearchPlan first = planOf('1,2 函数');
      final QuestionSearchPlan second = planOf('1,2 函数');
      expect(first, second);
      expect(() => first.serialNos.add(9), throwsUnsupportedError);
      final QuestionSearchPlan rejectedPlan = planOf('1..x');
      expect(
          () => rejectedPlan.rejectedSegments.add('y'), throwsUnsupportedError);
    });
  });

  group('永不抛异常', () {
    test('各种脏输入都不抛', () {
      const List<String> inputs = <String>[
        '',
        ' ',
        '\t\n',
        ',',
        ',,,',
        '..',
        '1..',
        '..1',
        '-',
        '~',
        '—',
        '1-2-3',
        'TR-',
        '#',
        '1234567890123',
        '😀',
        '1 2 3',
        'a-b..c',
        '1，，2',
        '　',
        '1..999999999',
        '1 ~ 5',
        '1 — 5',
      ];
      for (final String input in inputs) {
        expect(() => parseQuestionSearchPlan(input), returnsNormally);
      }
    });

    test('超大区间与默认上限', () {
      final QuestionSearchPlan plan = parseQuestionSearchPlan('1..999999999');
      expect(plan.serialNos.length, 200);
      expect(plan.truncated, isTrue);
    });

    test('确定的重复解析结果', () {
      const String raw = 'TR-1..TR-3 已知 函数,7,,2..x';
      final QuestionSearchPlan first = parseQuestionSearchPlan(raw);
      final QuestionSearchPlan second = parseQuestionSearchPlan(raw);
      expect(first, second);
      expect(first.serialNos, <int>[1, 2, 3, 7]);
      expect(first.stemContains, '已知 函数');
      expect(first.rejectedSegments, <String>['2..x']);
    });
  });
}
