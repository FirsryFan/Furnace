import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/student_answer_sheet.dart';

/// The answer-sheet contract: the solver's output is typed (choice / fill-in /
/// solution), not one free-form string. These tests pin the parser and the
/// render-back, including the fallback for a model that ignores the markers.
void main() {
  group('StudentAnswerSheet.parse', () {
    test('parses a solution sheet into result + necessary working', () {
      final sheet = StudentAnswerSheet.parse(
        '【题型】解答题\n'
        '【答案】(1) g sinθ；(2) m2/m1≤1 或 m2/m1=7\n'
        '【过程】由牛顿第二定律得 a=g sinθ；再用动量守恒分情况讨论。\n'
        '不要写完整思维链。',
      );

      expect(sheet.kind, StudentQuestionKind.solution);
      expect(sheet.result, contains('g sinθ'));
      expect(sheet.result, isNot(contains('牛顿第二定律')));
      expect(sheet.process, contains('动量守恒'));
      expect(sheet.choice, isNull);
      expect(sheet.structured, isTrue);
      expect(sheet.isEmpty, isFalse);
    });

    test('parses a choice sheet: option letters + final result', () {
      final sheet = StudentAnswerSheet.parse(
        '【题型】选择题\n【答案】B. m2/m1=7',
      );

      expect(sheet.kind, StudentQuestionKind.choice);
      expect(sheet.choice, 'B');
      expect(sheet.result, 'B. m2/m1=7');
      expect(sheet.process, isEmpty);
      expect(sheet.structured, isTrue);
    });

    test('parses multi-select option letters', () {
      final sheet = StudentAnswerSheet.parse(
        '【题型】选择题\n【答案】A、C',
      );

      expect(sheet.choice, 'AC');
      expect(sheet.result, 'A、C');
    });

    test('parses a fill-in sheet with only the final result', () {
      final sheet = StudentAnswerSheet.parse(
        '【题型】填空题\n【答案】17/2 < E_k0 < 16',
      );

      expect(sheet.kind, StudentQuestionKind.fillIn);
      expect(sheet.result, '17/2 < E_k0 < 16');
      expect(sheet.choice, isNull);
      expect(sheet.process, isEmpty);
      expect(sheet.structured, isTrue);
    });

    test('wraps a non-conforming answer instead of failing', () {
      final sheet = StudentAnswerSheet.parse('  自由文本答案  ');

      expect(sheet.kind, StudentQuestionKind.solution);
      expect(sheet.result, '自由文本答案');
      expect(sheet.raw, '自由文本答案');
      expect(sheet.structured, isFalse);
    });

    test('uses 【过程】 to infer a solution when 题型 is missing', () {
      final sheet = StudentAnswerSheet.parse(
        '【答案】v=3m/s\n【过程】由动能定理得……',
      );

      expect(sheet.kind, StudentQuestionKind.solution);
      expect(sheet.result, 'v=3m/s');
      expect(sheet.process, contains('动能定理'));
      expect(sheet.structured, isTrue);
    });

    test('a failed sheet is typed and empty', () {
      final sheet = StudentAnswerSheet.failed('');

      expect(sheet.kind, StudentQuestionKind.solution);
      expect(sheet.isEmpty, isTrue);
      expect(sheet.structured, isFalse);
    });
  });

  group('StudentAnswerSheet serialization', () {
    test('round-trips through toPlainText', () {
      const sheet = StudentAnswerSheet(
        kind: StudentQuestionKind.solution,
        raw: 'raw',
        result: '答案',
        process: '过程',
        structured: true,
      );

      final text = sheet.toPlainText();
      final reparsed = StudentAnswerSheet.parse(text);

      expect(reparsed.kind, StudentQuestionKind.solution);
      expect(reparsed.result, '答案');
      expect(reparsed.process, '过程');
      expect(reparsed.structured, isTrue);
    });

    test('toJson carries the fields a caller or trace needs', () {
      const sheet = StudentAnswerSheet(
        kind: StudentQuestionKind.choice,
        raw: 'raw',
        result: 'B',
        choice: 'B',
        structured: true,
      );

      final json = sheet.toJson();
      expect(json['kind'], 'choice');
      expect(json['kind_label'], '选择题');
      expect(json['choice'], 'B');
      expect(json['result'], 'B');
      expect(json['structured'], isTrue);
      expect(json['raw'], 'raw');
    });
  });
}
