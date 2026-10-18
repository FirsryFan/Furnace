/// 题库搜索框的解析规则：题号（TR-00042 / 42）与题干关键字的分流。
///
/// 搜索框只有一个输入口，用户既能敲题号也能敲题干片段；这里锁住"什么时候
/// 按号搜、什么时候按题干搜、号没命中时回落什么"的纯逻辑，页面只负责把
/// 解析结果写进筛选条件。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/questions/presentation/question_intake_providers.dart';

void main() {
  group('parseQuestionLibrarySearch', () {
    test('TR-00042：读出 42，同时保留原文供题号没命中时回落', () {
      final query = parseQuestionLibrarySearch('TR-00042');
      expect(query.serialNo, 42);
      expect(query.stemContains, 'TR-00042');
      expect(query.isEmpty, isFalse);
    });

    test('tr-42 与裸数字 42 等价（号码规则统一走 tryParseQuestionSerial）', () {
      expect(parseQuestionLibrarySearch('tr-42').serialNo, 42);
      expect(parseQuestionLibrarySearch('42').serialNo, 42);
      expect(parseQuestionLibrarySearch('00042').serialNo, 42);
    });

    test('前后空白不影响识别，题干关键字取 trim 后的文本', () {
      final query = parseQuestionLibrarySearch('  42  ');
      expect(query.serialNo, 42);
      expect(query.stemContains, '42');
    });

    test('普通文本没有号码，只作为题干关键字', () {
      final query = parseQuestionLibrarySearch('牛顿第二定律');
      expect(query.serialNo, isNull);
      expect(query.stemContains, '牛顿第二定律');
      expect(query.isEmpty, isFalse);
    });

    test('空白输入：两个字段都空（不触发搜索）', () {
      expect(parseQuestionLibrarySearch('   ').isEmpty, isTrue);
      expect(parseQuestionLibrarySearch('').stemContains, isNull);
      expect(parseQuestionLibrarySearch('').serialNo, isNull);
    });

    test('像号码但认不出的输入退回题干搜（TR- 后面没数字）', () {
      final query = parseQuestionLibrarySearch('TR-');
      expect(query.serialNo, isNull);
      expect(query.stemContains, 'TR-');
    });
  });

  group('questionLibraryFilterForSearch', () {
    test('学科/来源/状态筛选项在改搜索词时保留', () {
      const current = QuestionLibraryFilter(
        subjectKey: 'math',
        sourceLevel: 'gaokao',
        state: 'raw',
      );
      final next = questionLibraryFilterForSearch(current, 'TR-3');
      expect(next.subjectKey, 'math');
      expect(next.sourceLevel, 'gaokao');
      expect(next.state, 'raw');
      expect(next.serialNo, 3);
      expect(next.stemContains, 'TR-3');
    });

    test('改回普通文本时号码被清掉（不留上一轮的题号）', () {
      final next = questionLibraryFilterForSearch(
        const QuestionLibraryFilter(serialNo: 9, stemContains: 'TR-00009'),
        '牛顿',
      );
      expect(next.serialNo, isNull);
      expect(next.stemContains, '牛顿');
    });
  });

  group('QuestionLibraryFilter.serialNo', () {
    test('题号参与 isEmpty：只有题号也是在筛选', () {
      expect(const QuestionLibraryFilter(serialNo: 5).isEmpty, isFalse);
      expect(const QuestionLibraryFilter().isEmpty, isTrue);
    });

    test('copyWith 设置、保留与显式清空题号', () {
      final withSerial =
          const QuestionLibraryFilter(subjectKey: 'math').copyWith(serialNo: 7);
      expect(withSerial.serialNo, 7);
      expect(withSerial.subjectKey, 'math');
      // 不传 serialNo 时保持原值。
      expect(withSerial.copyWith(state: 'raw').serialNo, 7);
      // `null` 是"不筛"，清空要显式。
      expect(withSerial.copyWith(clearSerialNo: true).serialNo, isNull);
    });

    test('== 与 hashCode 包含题号（filter provider 靠它判断变化）', () {
      const a = QuestionLibraryFilter(serialNo: 7);
      const b = QuestionLibraryFilter(serialNo: 7);
      const c = QuestionLibraryFilter(serialNo: 8);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
