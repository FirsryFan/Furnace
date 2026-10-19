/// 题号检索纯逻辑：写法归一、拒绝口径、搜索框分流与匹配。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_number.dart';
import 'package:furnace/domain/services/questions/question_number_query.dart';

void main() {
  QuestionNumberQuery parse(String raw) {
    final query = parseQuestionNumberQuery(raw);
    expect(query, isNotNull, reason: '期望能解析: $raw');
    return query!;
  }

  int serialOf(String raw) => parse(raw).serialNo;

  String labelOf(String raw) => parse(raw).normalizedLabel;

  group('解析：前缀与数字写法归一', () {
    test('TR-00001 → 1 号，规范显示 TR-00001', () {
      final query = parse('TR-00001');
      expect(query.serialNo, 1);
      expect(query.normalizedLabel, 'TR-00001');
      expect(query.hasPrefix, isTrue);
      expect(query.raw, 'TR-00001');
    });

    test('小写 tr-12 同样接受', () {
      final query = parse('tr-12');
      expect(query.serialNo, 12);
      expect(query.normalizedLabel, 'TR-00012');
      expect(query.hasPrefix, isTrue);
    });

    test('无连字符 TR12 也接受', () {
      expect(serialOf('TR12'), 12);
      expect(parse('TR12').hasPrefix, isTrue);
    });

    test('井号 #7 按题号 7 处理', () {
      final query = parse('#7');
      expect(query.serialNo, 7);
      expect(query.normalizedLabel, 'TR-00007');
      expect(query.hasPrefix, isTrue);
    });

    test('裸数字 12 不带前缀', () {
      final query = parse('12');
      expect(query.serialNo, 12);
      expect(query.hasPrefix, isFalse);
    });

    test('全角数字 １２ 归一为 12', () {
      expect(serialOf('１２'), 12);
      expect(labelOf('１２'), 'TR-00012');
    });

    test('全角井号与全角数字 ＃７ 归一为 7', () {
      final query = parse('＃７');
      expect(query.serialNo, 7);
      expect(query.hasPrefix, isTrue);
    });

    test('全角连字符 TR－12 归一为 12', () {
      expect(serialOf('TR－12'), 12);
    });

    test('混合大小写 Tr-00012 归一为 12', () {
      expect(serialOf('Tr-00012'), 12);
    });

    test('前后空白（含全角空格）被 trim', () {
      final query = parse('　TR-00001　');
      expect(query.serialNo, 1);
      expect(query.raw, 'TR-00001');
    });

    test('TR-00001 / TR-1 / 1 问的是同一道题', () {
      final padded = parse('TR-00001');
      final plain = parse('TR-1');
      final bare = parse('1');
      expect(plain.serialNo, bare.serialNo);
      expect(padded.serialNo, bare.serialNo);
      expect(plain.normalizedLabel, bare.normalizedLabel);
      expect(padded.normalizedLabel, bare.normalizedLabel);
      expect(padded.hasPrefix, isTrue);
      expect(bare.hasPrefix, isFalse);
    });

    test('前导零 00001 归一为 1', () {
      expect(serialOf('00001'), 1);
      expect(labelOf('00001'), 'TR-00001');
    });
  });

  group('解析：格式化补零', () {
    test('不足 5 位补零', () {
      expect(labelOf('1'), 'TR-00001');
      expect(labelOf('7'), 'TR-00007');
      expect(labelOf('#12'), 'TR-00012');
    });

    test('正好 5 位原样', () {
      expect(labelOf('12345'), 'TR-12345');
    });

    test('超过 5 位不截断', () {
      expect(labelOf('100000'), 'TR-100000');
      expect(labelOf('999999999'), 'TR-999999999');
    });

    test('规范显示与 question_number.dart 的常量一致', () {
      final label = labelOf('1');
      expect(label, startsWith(kQuestionSerialPrefix));
      expect(label.length,
          kQuestionSerialPrefix.length + 1 + kQuestionSerialMinDigits);
    });
  });

  group('解析：位数上限与边界', () {
    test('9 位数字是可接受上限，值不变', () {
      expect(serialOf('999999999'), 999999999);
    });

    test('10 位数字拒绝（不截断）', () {
      expect(parseQuestionNumberQuery('1000000000'), isNull);
    });

    test('前导零也按位数算：TR-000000001（9 位）接受', () {
      expect(serialOf('TR-000000001'), 1);
    });

    test('前导零也按位数算：0000000001（10 位）拒绝', () {
      expect(parseQuestionNumberQuery('0000000001'), isNull);
    });

    test('带前缀的超位数同样拒绝', () {
      expect(parseQuestionNumberQuery('TR-1234567890'), isNull);
    });
  });

  group('拒绝：不猜的输入一律 null / false', () {
    test('空串与纯空白', () {
      for (final raw in <String>['', '   ', '\u3000', '\u3000 \u3000']) {
        expect(parseQuestionNumberQuery(raw), isNull, reason: raw);
        expect(isQuestionNumberQuery(raw), isFalse, reason: raw);
      }
    });

    test('纯前缀', () {
      for (final raw in <String>['TR', 'tr', 'tr-', '#', '＃', 'TR－']) {
        expect(parseQuestionNumberQuery(raw), isNull, reason: raw);
      }
    });

    test('0 号与全零', () {
      for (final raw in <String>['0', '00', '000', 'TR-0', '#000', '＃０']) {
        expect(parseQuestionNumberQuery(raw), isNull, reason: raw);
      }
    });

    test('负数与前导符号', () {
      for (final raw in <String>['-1', '+12', 'TR--1', 'TR-+1']) {
        expect(parseQuestionNumberQuery(raw), isNull, reason: raw);
      }
    });

    test('夹杂字母', () {
      for (final raw in <String>['TR-1a', 'TR1x', 'ABC', 'T12', 'TR-12号']) {
        expect(parseQuestionNumberQuery(raw), isNull, reason: raw);
      }
    });

    test('小数、内部空白与逗号', () {
      for (final raw in <String>['1.5', '1 2', 'TR 12', '1,2']) {
        expect(parseQuestionNumberQuery(raw), isNull, reason: raw);
      }
    });

    test('中文数字与整句', () {
      for (final raw in <String>['第十二题', '第 12 题', '十二']) {
        expect(parseQuestionNumberQuery(raw), isNull, reason: raw);
      }
    });

    test('多余连字符与其它符号', () {
      for (final raw in <String>['TR-1-2', '##7', 'TR-(1)']) {
        expect(parseQuestionNumberQuery(raw), isNull, reason: raw);
      }
    });
  });

  group('isQuestionNumberQuery 搜索框分流', () {
    test('题号写法分流为 true', () {
      for (final raw in <String>[
        'TR-00001',
        'tr-12',
        '#7',
        '12',
        '１２',
        ' 5 '
      ]) {
        expect(isQuestionNumberQuery(raw), isTrue, reason: raw);
      }
    });

    test('关键词与脏输入分流为 false', () {
      for (final raw in <String>['二次函数', 'TR-1a', '', '#', '第12题', 'a12']) {
        expect(isQuestionNumberQuery(raw), isFalse, reason: raw);
      }
    });

    test('分流结果与 parse 严格一致', () {
      const inputs = <String>[
        'TR-00001',
        'tr-12',
        '#7',
        '12',
        '',
        'TR',
        'TR-1a',
        '第十二题',
        '０',
        '00001',
      ];
      for (final raw in inputs) {
        expect(
            isQuestionNumberQuery(raw), parseQuestionNumberQuery(raw) != null,
            reason: raw);
      }
    });
  });

  group('值对象：确定性、相等性与回显字段', () {
    test('同一输入重复解析结果相等', () {
      final first = parse('TR-00001');
      final second = parse('TR-00001');
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first.raw, second.raw);
      expect(first.normalizedLabel, second.normalizedLabel);
    });

    test('跨写法相等只按题号算', () {
      expect(parse('TR-00001'), parse('1'));
      expect(parse('1'), parse('#1'));
      expect(parse('TR-00001').hashCode, parse('1').hashCode);
    });

    test('不同题号不相等', () {
      expect(parse('1'), isNot(parse('2')));
    });

    test('hasPrefix 记录写法但不影响相等', () {
      final bare = parse('7');
      final prefixed = parse('#7');
      expect(bare.hasPrefix, isFalse);
      expect(prefixed.hasPrefix, isTrue);
      expect(bare, prefixed);
    });

    test('raw 是 trim 后的原输入', () {
      expect(parse('  TR-12  ').raw, 'TR-12');
    });

    test('toString 含规范编号便于日志', () {
      expect(parse('TR-00012').toString(), contains('TR-00012'));
    });
  });

  group('matchQuestionSerial', () {
    test('命中同一题号', () {
      expect(matchQuestionSerial(7, parse('#7')), isTrue);
    });

    test('未编号 null 不命中', () {
      expect(matchQuestionSerial(null, parse('7')), isFalse);
    });

    test('不同题号不命中', () {
      expect(matchQuestionSerial(8, parse('7')), isFalse);
    });

    test('0 与负数不命中', () {
      expect(matchQuestionSerial(0, parse('1')), isFalse);
      expect(matchQuestionSerial(-1, parse('1')), isFalse);
    });

    test('带前缀的写法也命中', () {
      expect(matchQuestionSerial(1, parse('TR-00001')), isTrue);
    });

    test('5 位以上题号命中', () {
      expect(matchQuestionSerial(100000, parse('100000')), isTrue);
    });
  });

  group('不抛异常', () {
    test('超长数字输入只返回 null', () {
      final long = List<String>.filled(1000, '1').join();
      expect(parseQuestionNumberQuery(long), isNull);
      expect(isQuestionNumberQuery(long), isFalse);
    });

    test('任意脏字符串都不抛', () {
      final samples = <String>[
        '',
        ' ',
        'TR-',
        '#####',
        '٣',
        'TR-٣',
        '🔥',
        'TR-\u0000',
        'TR\n-1',
      ];
      for (final raw in samples) {
        expect(() => parseQuestionNumberQuery(raw), returnsNormally,
            reason: raw);
        expect(() => isQuestionNumberQuery(raw), returnsNormally, reason: raw);
      }
    });
  });
}
