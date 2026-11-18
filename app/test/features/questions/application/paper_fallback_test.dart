import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/paper/paper_composer.dart';
import 'package:furnace/features/questions/application/paper_fallback.dart';

PaperCandidate _c(String id, String subject) => PaperCandidate(
      questionId: id,
      subjectKey: subject,
      sourceLevel: 'gaokao',
      questionType: 'solution',
      difficulty: 5,
      aiQuality: 0.5,
      matchedKnowledgePointIds: ['kp-$id'],
      groupQuestionIds: id == 'q0' ? ['q0', 'q1'] : const [],
    );

void main() {
  final candidates = <PaperCandidate>[
    for (var i = 0; i < 21; i++)
      _c('q$i', const ['math', 'physics', 'chinese'][i % 3]),
  ];

  test('简版组卷：按学科均衡、数量正确、题组 id 保留', () {
    final plan = buildFallbackPaperPlan(
      candidates: candidates,
      spec: const PaperSpec(targetCount: 10),
    );
    expect(plan.items, hasLength(10));
    expect(plan.items.map((e) => e.questionId).toSet(), hasLength(10));
    expect(plan.items.map((e) => e.subjectKey).toSet(),
        containsAll(<String>['math', 'physics', 'chinese']));
    expect(
      plan.items.firstWhere((e) => e.questionId == 'q0').groupQuestionIds,
      hasLength(2),
    );
  });

  test('简版组卷：学科筛选后只出该科', () {
    final plan = buildFallbackPaperPlan(
      candidates: candidates,
      spec: const PaperSpec(
        targetCount: 5,
        subjectKeys: <String>{'physics'},
      ),
    );
    expect(plan.items, hasLength(5));
    expect(plan.items.every((e) => e.subjectKey == 'physics'), isTrue);
  });

  test('简版组卷：目标数大于候选数时不重复、不越界', () {
    final plan = buildFallbackPaperPlan(
      candidates: candidates.take(2).toList(),
      spec: const PaperSpec(targetCount: 10),
    );
    expect(plan.items, hasLength(2));
    expect(plan.items.map((e) => e.questionId).toSet(), hasLength(2));
  });
}
