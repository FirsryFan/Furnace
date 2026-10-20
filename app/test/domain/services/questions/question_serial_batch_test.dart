import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_serial_batch.dart';

void main() {
  QuestionSerialBatch batch(String raw, {int maxCount = 200}) =>
      parseQuestionSerialBatch(raw, maxCount: maxCount);

  List<int> serials(String raw, {int maxCount = 200}) =>
      batch(raw, maxCount: maxCount).serials;

  group('单号与分隔符', () {
    test('单个数字', () {
      final result = batch('42');
      expect(result.serials, <int>[42]);
      expect(result.count, 1);
      expect(result.isEmpty, isFalse);
      expect(result.truncated, isFalse);
      expect(result.rejectedSegments, isEmpty);
    });

    test('TR-00042 前缀写法', () {
      expect(serials('TR-00042'), <int>[42]);
    });

    test('各种写法指向同一道题，去重后只有一个题号', () {
      expect(
        serials('TR-00042 tr-42 #42 00042 42'),
        <int>[42],
      );
    });

    test('半角逗号分隔', () {
      expect(serials('1,2,3'), <int>[1, 2, 3]);
    });

    test('全角逗号分隔', () {
      expect(serials('1，2，3'), <int>[1, 2, 3]);
    });

    test('顿号分隔', () {
      expect(serials('1、2、3'), <int>[1, 2, 3]);
    });

    test('半角与全角分号分隔', () {
      expect(serials('1;2;3'), <int>[1, 2, 3]);
      expect(serials('1；2；3'), <int>[1, 2, 3]);
    });

    test('空白分隔（空格、制表符、换行）', () {
      expect(serials('1 2\t3\n4'), <int>[1, 2, 3, 4]);
    });

    test('分隔符混用', () {
      expect(serials('1, 2、3；4\n5'), <int>[1, 2, 3, 4, 5]);
    });

    test('乱序输入按升序输出', () {
      expect(serials('5,1,3'), <int>[1, 3, 5]);
    });

    test('重复单号去重', () {
      expect(serials('1,1,TR-1,#1'), <int>[1]);
    });

    test('全角数字也认', () {
      expect(serials('１２、３'), <int>[3, 12]);
    });

    test('空串、纯空白、纯分隔符都是空结果', () {
      for (final String raw in <String>[
        '',
        '   ',
        '\n\t',
        ',',
        '，、；',
        ' , 、 '
      ]) {
        final result = batch(raw);
        expect(result.isEmpty, isTrue);
        expect(result.count, 0);
        expect(result.rejectedSegments, isEmpty);
        expect(result.truncated, isFalse);
        expect(result, const QuestionSerialBatch.empty());
      }
    });
  });

  group('区间', () {
    test('两个点连接符', () {
      expect(serials('1..5'), <int>[1, 2, 3, 4, 5]);
    });

    test('连字符连接符', () {
      expect(serials('1-5'), <int>[1, 2, 3, 4, 5]);
    });

    test('波浪号连接符', () {
      expect(serials('1~5'), <int>[1, 2, 3, 4, 5]);
    });

    test('破折号连接符', () {
      expect(serials('1—5'), <int>[1, 2, 3, 4, 5]);
    });

    test('带 TR 前缀的区间', () {
      expect(serials('TR-1..TR-5'), <int>[1, 2, 3, 4, 5]);
    });

    test('连接符两侧有空白', () {
      expect(serials('tr-3 ~ tr-5'), <int>[3, 4, 5]);
      expect(serials('1 - 5'), <int>[1, 2, 3, 4, 5]);
    });

    test('降序区间也按升序输出', () {
      expect(serials('5..1'), <int>[1, 2, 3, 4, 5]);
      expect(serials('10-3'), <int>[3, 4, 5, 6, 7, 8, 9, 10]);
    });

    test('区间与单号混用', () {
      expect(serials('1,3..5,9'), <int>[1, 3, 4, 5, 9]);
    });

    test('重叠区间合并去重', () {
      expect(serials('1..3,2..5'), <int>[1, 2, 3, 4, 5]);
    });

    test('相邻区间合并', () {
      expect(serials('1..2,3..4'), <int>[1, 2, 3, 4]);
    });

    test('空白分隔的多个区间', () {
      expect(serials('1..5 8..10'), <int>[1, 2, 3, 4, 5, 8, 9, 10]);
      expect(serials('1 - 5 8 ~ 10'), <int>[1, 2, 3, 4, 5, 8, 9, 10]);
    });

    test('两端都合法但连写多个连接符时整段拒绝', () {
      final result = batch('1..5..9');
      expect(result.serials, isEmpty);
      expect(result.rejectedSegments, <String>['1..5..9']);
    });
  });

  group('拒绝段', () {
    test('只有前缀没有数字', () {
      final result = batch('TR-');
      expect(result.serials, isEmpty);
      expect(result.rejectedSegments, <String>['TR-']);
    });

    test('# 单独一个井号 ', () {
      expect(batch('#').rejectedSegments, <String>['#']);
    });

    test('区间有一端认不出时整段拒绝，不猜另一端', () {
      final result = batch('1..x');
      expect(result.serials, isEmpty);
      expect(result.rejectedSegments, <String>['1..x']);
      expect(batch('x..5').rejectedSegments, <String>['x..5']);
    });

    test('字母段', () {
      expect(batch('abc').rejectedSegments, <String>['abc']);
    });

    test('超过 9 位的数字拒绝，不截断', () {
      final result = batch('0000000001');
      expect(result.serials, isEmpty);
      expect(result.rejectedSegments, <String>['0000000001']);
      expect(batch('1234567890').rejectedSegments, <String>['1234567890']);
    });

    test('数字 0 与 TR-0 都拒绝', () {
      final result = batch('0,TR-0');
      expect(result.serials, isEmpty);
      expect(result.rejectedSegments, <String>['0', 'TR-0']);
    });

    test('拒绝段顺序与输入一致', () {
      final result = batch('abc,1,def,2');
      expect(result.serials, <int>[1, 2]);
      expect(result.rejectedSegments, <String>['abc', 'def']);
    });

    test('区间一侧是字母时整段拒绝并保留连接符', () {
      final result = batch('1 - x');
      expect(result.serials, isEmpty);
      expect(result.rejectedSegments, <String>['1 - x']);
    });

    test('两端都不是数字的区间也整段拒绝', () {
      expect(batch('x - y').rejectedSegments, <String>['x - y']);
    });

    test('同一段里合法项保留、非法项进拒绝列表', () {
      final result = batch('TR-,5');
      expect(result.serials, <int>[5]);
      expect(result.rejectedSegments, <String>['TR-']);
    });
  });

  group('maxCount 截断', () {
    test('maxCount 为 0 时没有题号但标记截断', () {
      final result = batch('1,2', maxCount: 0);
      expect(result.serials, isEmpty);
      expect(result.rejectedSegments, isEmpty);
      expect(result.truncated, isTrue);
    });

    test('maxCount 为负数时同样截断', () {
      final result = batch('1,2', maxCount: -1);
      expect(result.serials, isEmpty);
      expect(result.truncated, isTrue);
    });

    test('maxCount 为 0 且本来没有内容时不算截断', () {
      expect(batch('', maxCount: 0).truncated, isFalse);
      expect(batch('abc', maxCount: 0).truncated, isFalse);
      expect(batch('abc', maxCount: 0).rejectedSegments, <String>['abc']);
    });

    test('超过 maxCount 时按升序保留最小的几个题号', () {
      final result = batch('3,1,2', maxCount: 1);
      expect(result.serials, <int>[1]);
      expect(result.truncated, isTrue);
    });

    test('刚好等于 maxCount 时不截断', () {
      final result = batch('1,2', maxCount: 2);
      expect(result.serials, <int>[1, 2]);
      expect(result.truncated, isFalse);
    });

    test('默认上限为 200', () {
      expect(batch('1..200').truncated, isFalse);
      expect(batch('1..200').count, 200);
      final over = batch('1..201');
      expect(over.count, 200);
      expect(over.truncated, isTrue);
    });

    test('超大区间按 maxCount 截断且不会展开整个区间', () {
      final result = batch('1..999999999', maxCount: 3);
      expect(result.serials, <int>[1, 2, 3]);
      expect(result.truncated, isTrue);
    });

    test('maxCount 大于实际数量时全部返回', () {
      final result = batch('1,3', maxCount: 100);
      expect(result.serials, <int>[1, 3]);
      expect(result.truncated, isFalse);
    });
  });

  group('JSON、相等性与确定性', () {
    test('toJson 的键与值', () {
      final result = batch('1, 3..4');
      expect(result.toJson(), <String, Object?>{
        'serials': <int>[1, 3, 4],
        'count': 3,
        'rejected_segments': <String>[],
        'truncated': false,
      });
      expect(jsonEncode(result.toJson()), contains('"serials":[1,3,4]'));
    });

    test('toJson 带拒绝段与截断标记', () {
      final result = batch('abc,5..9', maxCount: 2);
      expect(result.toJson(), <String, Object?>{
        'serials': <int>[5, 6],
        'count': 2,
        'rejected_segments': <String>['abc'],
        'truncated': true,
      });
    });

    test('内容相等才相等，hashCode 一致', () {
      final first = batch('1,3..4');
      final second = batch('TR-1, 4, 3');
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first == batch('1,3..4', maxCount: 2), isFalse);
      expect(first == batch('1,3'), isFalse);
      expect(first == batch('1,3..4,abc'), isFalse);
    });

    test('空结果与 const 空值相等', () {
      expect(batch(''), const QuestionSerialBatch.empty());
      expect(batch(',').hashCode, const QuestionSerialBatch.empty().hashCode);
    });

    test('同一输入两次解析结果完全相同', () {
      const String raw = 'TR-3、1..2, 9, abc, 2';
      final first = batch(raw, maxCount: 4);
      final second = batch(raw, maxCount: 4);
      expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
      expect(first, second);
    });

    test('toString 给出数量与拒绝段数量', () {
      final result = batch('1,2,abc');
      expect(result.toString(),
          'QuestionSerialBatch(count: 2, rejected: 1, truncated: false)');
    });

    test('返回的列表不可修改', () {
      final result = batch('1,2,abc');
      expect(() => result.serials.add(9), throwsUnsupportedError);
      expect(() => result.rejectedSegments.add('x'), throwsUnsupportedError);
    });

    test('任何奇怪输入都不抛异常', () {
      const List<String> inputs = <String>[
        '',
        '   ',
        ',',
        '，、；',
        'TR-',
        '#',
        '..',
        '-',
        '——',
        '1..2..3',
        '1 - 5 - 8',
        'x - y',
        '0000000001',
        '1..999999999',
        '１２３',
        '😀',
        ' 5 ',
        '\t\n',
      ];
      for (final String raw in inputs) {
        late QuestionSerialBatch result;
        expect(
          () {
            result = batch(raw);
          },
          returnsNormally,
        );
        expect(result.count, result.serials.length);
        expect(result.isEmpty, result.serials.isEmpty);
        for (var index = 0; index < result.serials.length; index++) {
          expect(result.serials[index], greaterThan(0));
          if (index > 0) {
            expect(
              result.serials[index],
              greaterThan(result.serials[index - 1]),
            );
          }
        }
        if (result.truncated) {
          expect(result.count, 200);
        }
      }
    });
  });
}
