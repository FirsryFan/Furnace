import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow/domain/entities/card_template.dart';
import 'package:knowflow/domain/entities/knowledge_point.dart';
import 'package:knowflow/domain/services/cloze/cloze_generator.dart';

void main() {
  group('ClozeGenerator', () {
    test('blanks after 是 for Chinese definition', () {
      const point = KnowledgePoint(
        id: 'kp1',
        title: '光合作用场所',
        content: '光合作用的主要场所是叶绿体。',
      );

      final template = ClozeGenerator.generateFillBlank(point);

      expect(template, isNotNull);
      expect(template!.type, CardTemplateType.fillBlank);
      expect(template.question, '光合作用的主要场所是___。');
      expect(template.answer, '叶绿体');
    });

    test('blanks explicit keyword when provided', () {
      const point = KnowledgePoint(
        id: 'kp2',
        title: 'ATP',
        content: 'ATP 是细胞的能量货币。',
        tags: ['ATP'],
      );

      final template = ClozeGenerator.generateFillBlank(point);

      expect(template, isNotNull);
      expect(template!.answer, 'ATP');
    });

    test('returns null for empty content', () {
      const point = KnowledgePoint(
        id: 'kp3',
        title: 'Empty',
        content: '',
      );

      expect(ClozeGenerator.generateFillBlank(point), isNull);
    });
  });
}
