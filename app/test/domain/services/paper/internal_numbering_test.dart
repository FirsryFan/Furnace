import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/paper/internal_numbering.dart';
import 'package:furnace/domain/services/paper/paper_composer.dart';

PaperItem _item(String id, String subject) => PaperItem(
      questionId: id,
      subjectKey: subject,
      sourceLevel: 'gaokao',
      questionType: 'solution',
      knowledgePointId: null,
      matchedKnowledgePointIds: const [],
      zone: PaperZone.unknown,
      need: 0.35,
      quality: 0.5,
      score: 0.5,
      reasonZh: '',
      improvementNote: '',
      backgroundZh: '',
    );

void main() {
  test('内部编号：按学科分节、节内顺序编号，1.3 是第一节第 3 题', () {
    final map = assignInternalNumbers(<PaperItem>[
      _item('m1', 'math'),
      _item('m2', 'math'),
      _item('m3', 'math'),
      _item('p1', 'physics'),
    ]);
    expect(map['m1'], '1.1');
    expect(map['m2'], '1.2');
    expect(map['m3'], '1.3');
    expect(map['p1'], '2.1');
  });

  test('变式/知识/扩展编号挂原题层级', () {
    expect(variantInternalNo('1.3', 2), '【变 1.3.2】');
    expect(knowledgeInternalNo('1.3', 2), '【知 1.3.2】');
    expect(expansionInternalNo('1.3.2', 1), '【扩 1.3.2.1】');
  });
}
