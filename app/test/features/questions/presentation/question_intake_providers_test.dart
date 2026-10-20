/// 题库搜索框的解析规则：多题号 / 区间 / 题干关键字的分流。
///
/// 搜索框只有一个输入口，用户既能一次贴多个题号（`TR-00001, 2-5`），也能在
/// 题号旁边附带题干关键词；这里锁住「哪些进题号清单、哪些进题干、坏区间怎么
/// 办、回落原文怎么保留」的纯逻辑。规则本体在 domain 层
/// `question_search_plan.dart`，本文件只验证 presentation 层的转发与
/// 筛选条件（copyWith / 相等性）没有丢语义。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/questions/presentation/question_intake_providers.dart';

void main() {
  group('parseQuestionLibrarySearch', () {
    test('单个题号：读成清单，题干为空（纯号输入保留原文供回落）', () {
      final query = parseQuestionLibrarySearch('TR-00042');
      expect(query.serialNos, <int>[42]);
      expect(query.stemContains, isNull);
      expect(query.isSerialOnly, isTrue);
      expect(query.raw, 'TR-00042');
      expect(query.isEmpty, isFalse);
    });

    test('多种题号写法等价：tr-42 / 42 / 00042 / #7 / 全角数字', () {
      expect(parseQuestionLibrarySearch('tr-42').serialNos, <int>[42]);
      expect(parseQuestionLibrarySearch('42').serialNos, <int>[42]);
      expect(parseQuestionLibrarySearch('00042').serialNos, <int>[42]);
      expect(parseQuestionLibrarySearch('#7').serialNos, <int>[7]);
      expect(parseQuestionLibrarySearch('＃７').serialNos, <int>[7]);
      expect(parseQuestionLibrarySearch('１２').serialNos, <int>[12]);
    });

    test('多个题号：逗号/顿号/分号分隔 → 去重升序清单', () {
      final query = parseQuestionLibrarySearch('TR-3, 1、TR-2；3');
      expect(query.serialNos, <int>[1, 2, 3]);
      expect(query.stemContains, isNull);
      expect(query.serialCount, 3);
      expect(query.isSerialOnly, isTrue);
    });

    test('区间：2-5 → 2,3,4,5；TR-1~TR-3 也认', () {
      expect(parseQuestionLibrarySearch('2-5').serialNos, <int>[2, 3, 4, 5]);
      expect(
        parseQuestionLibrarySearch('TR-1~TR-3').serialNos,
        <int>[1, 2, 3],
      );
    });

    test('题号 + 题干混合：两边都保留（并集搜索用）', () {
      final query = parseQuestionLibrarySearch('牛顿 2-3');
      expect(query.serialNos, <int>[2, 3]);
      expect(query.stemContains, '牛顿');
      expect(query.isSerialOnly, isFalse);
      expect(query.isEmpty, isFalse);
    });

    test('认不出的文字仍按题干搜，不被静默丢掉', () {
      final query = parseQuestionLibrarySearch('牛顿第二定律');
      expect(query.serialNos, isEmpty);
      expect(query.stemContains, '牛顿第二定律');
      expect(query.isEmpty, isFalse);
      expect(parseQuestionLibrarySearch('TR-').stemContains, 'TR-');
    });

    test('坏区间进 rejectedSegments，整段仍回退成题干（题号为空时）', () {
      final query = parseQuestionLibrarySearch('1..x');
      expect(query.serialNos, isEmpty);
      expect(query.rejectedSegments, <String>['1..x']);
      expect(query.stemContains, '1..x');
    });

    test('空白输入：字段全空（不触发搜索）', () {
      final query = parseQuestionLibrarySearch('   ');
      expect(query.isEmpty, isTrue);
      expect(query.stemContains, isNull);
      expect(query.serialNos, isEmpty);
      expect(query.rejectedSegments, isEmpty);
    });
  });

  group('questionLibraryFilterForSearch', () {
    test('学科/来源/状态在改搜索词时保留', () {
      const current = QuestionLibraryFilter(
        subjectKey: 'math',
        sourceLevel: 'gaokao',
        state: 'raw',
      );
      final next = questionLibraryFilterForSearch(current, 'TR-3');
      expect(next.subjectKey, 'math');
      expect(next.sourceLevel, 'gaokao');
      expect(next.state, 'raw');
      expect(next.serialNos, <int>[3]);
      expect(next.serialFallbackStem, 'TR-3');
      expect(next.hasStemFilter, isFalse);
    });

    test('多题号输入：回落原文保留 trim 后的整段输入', () {
      final next = questionLibraryFilterForSearch(
        const QuestionLibraryFilter(),
        '  TR-3, TR-5  ',
      );
      expect(next.serialNos, <int>[3, 5]);
      expect(next.serialFallbackStem, 'TR-3, TR-5');
      expect(next.stemContains, isNull);
    });

    test('混合输入：没有回落原文，题号与题干都写进筛选', () {
      final next = questionLibraryFilterForSearch(
        const QuestionLibraryFilter(),
        '牛顿 2',
      );
      expect(next.serialNos, <int>[2]);
      expect(next.stemContains, '牛顿');
      expect(next.serialFallbackStem, isNull);
      expect(next.hasStemFilter, isTrue);
    });

    test('改回普通文本时题号与回落都被清掉（不留上一轮）', () {
      final next = questionLibraryFilterForSearch(
        const QuestionLibraryFilter(
          serialNos: <int>[9],
          serialFallbackStem: 'TR-00009',
        ),
        '牛顿',
      );
      expect(next.serialNos, isEmpty);
      expect(next.serialFallbackStem, isNull);
      expect(next.stemContains, '牛顿');
    });
  });

  group('QuestionLibraryFilter.serialNos', () {
    test('题号参与 isEmpty：只有题号也是在筛选', () {
      expect(
        const QuestionLibraryFilter(serialNos: <int>[5]).isEmpty,
        isFalse,
      );
      expect(const QuestionLibraryFilter().isEmpty, isTrue);
    });

    test('copyWith 设置、保留与显式清空题号（清题号时回落原文一起清）', () {
      final withSerial = const QuestionLibraryFilter(subjectKey: 'math')
          .copyWith(serialNos: <int>[7, 8], serialFallbackStem: '7,8');
      expect(withSerial.serialNos, <int>[7, 8]);
      expect(withSerial.serialFallbackStem, '7,8');
      expect(withSerial.subjectKey, 'math');
      // 不传 serialNos 时保持原值。
      expect(withSerial.copyWith(state: 'raw').serialNos, <int>[7, 8]);
      final cleared = withSerial.copyWith(clearSerialNos: true);
      expect(cleared.serialNos, isEmpty);
      expect(cleared.serialFallbackStem, isNull);
      expect(withSerial.copyWith(clearStem: true).stemContains, isNull);
    });

    test('== 与 hashCode 包含题号清单（filter provider 靠它判断变化）', () {
      const a = QuestionLibraryFilter(serialNos: <int>[7, 8]);
      const b = QuestionLibraryFilter(serialNos: <int>[7, 8]);
      const c = QuestionLibraryFilter(serialNos: <int>[8, 7]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
