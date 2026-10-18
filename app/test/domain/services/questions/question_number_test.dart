import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_number.dart';

// 题目编号是"给人看的号"：格式一旦发出去就不能再变（用户会把 TR-00042 抄在
// 错题本上），所以这里把格式、占位、下一个号、反解四件事逐条钉死。
void main() {
  group('formatQuestionSerial', () {
    test('从 1 开始，补到至少 5 位', () {
      expect(formatQuestionSerial(1), 'TR-00001');
      expect(formatQuestionSerial(42), 'TR-00042');
      expect(formatQuestionSerial(99999), 'TR-99999');
    });

    test('超过 5 位不截断，号码本身不换', () {
      expect(formatQuestionSerial(100000), 'TR-100000');
      expect(formatQuestionSerial(1234567), 'TR-1234567');
    });

    test('0 与负数当场报错（编号从 1 开始）', () {
      expect(() => formatQuestionSerial(0), throwsArgumentError);
      expect(() => formatQuestionSerial(-1), throwsArgumentError);
    });

    test('格式化再读回来是同一个号', () {
      for (final serial in [1, 2, 42, 999, 1000, 99999]) {
        expect(tryParseQuestionSerial(formatQuestionSerial(serial)), serial);
      }
    });
  });

  group('questionSerialLabel', () {
    test('有号给格式化的号', () {
      expect(questionSerialLabel(7), 'TR-00007');
      expect(questionSerialLabel(100000), 'TR-100000');
    });

    test('没号或脏数据给占位文案', () {
      expect(questionSerialLabel(null), kUnnumberedQuestionLabel);
      expect(questionSerialLabel(0), kUnnumberedQuestionLabel);
      expect(questionSerialLabel(-5), kUnnumberedQuestionLabel);
      expect(kUnnumberedQuestionLabel, 'TR-未编号');
    });
  });

  group('nextQuestionSerial', () {
    test('一条编号都没有时从 1 开始', () {
      expect(nextQuestionSerial(null), 1);
      expect(nextQuestionSerial(0), 1);
      expect(nextQuestionSerial(-3), 1);
    });

    test('接着最大值 + 1', () {
      expect(nextQuestionSerial(1), 2);
      expect(nextQuestionSerial(41), 42);
      expect(nextQuestionSerial(99999), 100000);
    });
  });

  group('tryParseQuestionSerial', () {
    test('认带前缀与不带的常见写法', () {
      expect(tryParseQuestionSerial('TR-00042'), 42);
      expect(tryParseQuestionSerial('tr-42'), 42);
      expect(tryParseQuestionSerial('TR00042'), 42);
      expect(tryParseQuestionSerial('00042'), 42);
      expect(tryParseQuestionSerial('42'), 42);
      expect(tryParseQuestionSerial('  TR-7  '), 7);
      expect(tryParseQuestionSerial('TR-100000'), 100000);
    });

    test('不是编号的一律 null', () {
      expect(tryParseQuestionSerial(''), isNull);
      expect(tryParseQuestionSerial('   '), isNull);
      expect(tryParseQuestionSerial('TR-'), isNull);
      expect(tryParseQuestionSerial('TR-0'), isNull);
      expect(tryParseQuestionSerial('TR--5'), isNull);
      expect(tryParseQuestionSerial('SCP-42'), isNull);
      expect(tryParseQuestionSerial('TR 42'), isNull);
      expect(tryParseQuestionSerial('abc'), isNull);
    });
  });
}
