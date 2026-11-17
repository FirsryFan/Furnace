import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/questions/question_readiness.dart';
import 'package:furnace/features/questions/application/question_library_reader.dart';

/// 「待处理题目」判据 + 读表过滤（真实库 105/170 的口径）。
///
/// 用户口径：入库但没有答案/解析的题**从主题库隐藏**，另设入口按原因统计；
/// 判据可配（不按学科/来源硬编码），默认口径是「答案与解析都为空」。
void main() {
  group('evaluateQuestionReadiness', () {
    QuestionReadiness evaluate({
      String? answer = 'A',
      String? solution = '解析',
      String stem = '题干',
      int imageCount = 0,
      QuestionCompletenessPolicy policy = QuestionCompletenessPolicy.hidePending,
    }) =>
        evaluateQuestionReadiness(
          answer: answer,
          solution: solution,
          stem: stem,
          stemImageCount: imageCount,
          policy: policy,
        );

    test('默认口径：有答案有解析 = 完整', () {
      expect(evaluate().isReady, isTrue);
    });

    test('默认口径：答案与解析都为空 = 待处理，且两条原因都记', () {
      final readiness = evaluate(answer: null, solution: '   ');
      expect(readiness.isPending, isTrue);
      expect(readiness.has(QuestionPendingReason.missingAnswer), isTrue);
      expect(readiness.has(QuestionPendingReason.missingSolution), isTrue);
    });

    test('默认口径：只有答案 = 完整（不是 105 那批的形态）', () {
      expect(evaluate(answer: 'B', solution: '').isReady, isTrue);
    });

    test('默认口径：只有解析 = 完整', () {
      expect(evaluate(answer: '', solution: '解析').isReady, isTrue);
    });

    test('可配置更严：缺答案也算待处理', () {
      final readiness = evaluate(
        answer: '',
        solution: '解析',
        policy: const QuestionCompletenessPolicy(
          requireAnswer: true,
          requireAnswerOrSolution: false,
        ),
      );
      expect(readiness.has(QuestionPendingReason.missingAnswer), isTrue);
      expect(readiness.has(QuestionPendingReason.missingSolution), isFalse);
    });

    test('可配置更严：缺解析也算待处理', () {
      final readiness = evaluate(
        answer: 'A',
        solution: '',
        policy: const QuestionCompletenessPolicy(
          requireSolution: true,
          requireAnswerOrSolution: false,
        ),
      );
      expect(readiness.has(QuestionPendingReason.missingSolution), isTrue);
    });

    test('配图判据：题面引用 {{asset}} 且库里没有题干图 = 缺配图', () {
      final readiness = evaluate(
        stem: '如图{{asset:q14_img01.png}}所示',
        imageCount: 0,
        policy: const QuestionCompletenessPolicy(
          requireAnswerOrSolution: false,
          requireStemMedia: true,
        ),
      );
      expect(readiness.has(QuestionPendingReason.missingStemMedia), isTrue);
    });

    test('配图判据：有图就不算缺配图', () {
      final readiness = evaluate(
        stem: '如图{{asset:q14_img01.png}}所示',
        imageCount: 1,
        policy: const QuestionCompletenessPolicy(
          requireAnswerOrSolution: false,
          requireStemMedia: true,
        ),
      );
      expect(readiness.isReady, isTrue);
    });

    test('includeAll：任何题都算完整（读表函数历史行为）', () {
      final readiness = evaluate(
        answer: '',
        solution: '',
        policy: QuestionCompletenessPolicy.includeAll,
      );
      expect(readiness.isReady, isTrue);
      expect(QuestionCompletenessPolicy.includeAll.filtersAnything, isFalse);
    });

    test('统计：按题去重、按原因分项', () {
      final stats = questionPendingStats(<QuestionReadiness>[
        evaluate(answer: '', solution: ''), // 缺答案 + 缺解析
        evaluate(answer: 'A', solution: ''),
        QuestionReadiness.ready,
      ]);
      expect(stats.total, 1);
      expect(stats.missingAnswer, 1);
      expect(stats.missingSolution, 1);
      expect(stats.reasonCounts[QuestionPendingReason.missingAnswer], 1);
    });
  });

  group('readQuestionLibrary 的完整性过滤', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });
    tearDown(() async {
      await db.close();
    });

    Future<void> seed(
      String id, {
      String? answer,
      String? solution,
      String stem = '题干',
    }) {
      return db.into(db.questions).insert(
            QuestionsCompanion.insert(
              id: id,
              stem: stem,
              createdAt: 1700000000000,
              updatedAt: 1700000000000,
              answer: Value(answer),
              solution: Value(solution),
            ),
          );
    }

    test('默认（includeAll）行为不变：所有题都读出来', () async {
      await seed('q-ready', answer: 'A', solution: '解析');
      await seed('q-pending');
      final snapshot = await readQuestionLibrary(db);
      expect(snapshot.entries.map((e) => e.questionId), containsAll(<String>[
        'q-ready',
        'q-pending',
      ]));
      expect(snapshot.entries.every((e) => e.readiness.isReady), isTrue);
    });

    test('hidePending：主题库只留完整题，待处理题带原因', () async {
      await seed('q-ready', answer: 'A', solution: '解析');
      await seed('q-pending');
      await seed('q-answer-only', answer: 'B');

      final ready = await readQuestionLibrary(
        db,
        policy: QuestionCompletenessPolicy.hidePending,
      );
      // 同一 updatedAt 时按 id 升序。
      expect(ready.entries.map((e) => e.questionId), <String>[
        'q-answer-only',
        'q-ready',
      ]);
      expect(ready.totalCount, 2);

      final pending = await readQuestionLibrary(
        db,
        limit: 0,
        policy: QuestionCompletenessPolicy.hidePending,
        pendingOnly: true,
      );
      expect(pending.entries.map((e) => e.questionId), <String>['q-pending']);
      expect(
        pending.entries.single.readiness.reasons,
        containsAll(<QuestionPendingReason>[
          QuestionPendingReason.missingAnswer,
          QuestionPendingReason.missingSolution,
        ]),
      );
    });

    test('待处理题的卡片摘要不出现原始 {{asset:...}} 占位', () async {
      await seed(
        'q-asset',
        stem: '利用铁基、钙基物质的化学循环（{{asset:q14_img01.wmf}}'
            '{{asset:q14_img02.png}}）可从高炉煤气中分离气体',
      );
      final pending = await readQuestionLibrary(
        db,
        policy: QuestionCompletenessPolicy.hidePending,
        pendingOnly: true,
      );
      final preview = pending.entries.single.stemPreview;
      expect(preview.contains('{{asset:'), isFalse);
      expect(preview.contains('［图］'), isTrue);
    });

    test('判据可配：requireAnswer 更严时「只有解析」也算待处理', () async {
      await seed('q-solution-only', solution: '解析');
      final pending = await readQuestionLibrary(
        db,
        limit: 0,
        policy: const QuestionCompletenessPolicy(
          requireAnswer: true,
          requireAnswerOrSolution: false,
        ),
        pendingOnly: true,
      );
      expect(pending.entries.map((e) => e.questionId), <String>[
        'q-solution-only',
      ]);
    });
  });
}
