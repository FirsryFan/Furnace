import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/questions/application/question_corpus_reader.dart';

/// 「按能力动作找题」的读表口径：
///
///  * 只认**最新一条链**的动作序列（旧链里出现过不算）；
///  * 没解过链的题不出现；
///  * 排序 = 来源分级高的在前，平手按 id（同一份库刷两次顺序一样）。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedQuestion({
    required String id,
    String stem = '',
    String sourceLevel = 'school',
  }) async {
    await db.into(db.questions).insert(
          QuestionsCompanion.insert(
            id: id,
            stem: stem.isEmpty ? '题干 $id' : stem,
            createdAt: 1,
            updatedAt: 1,
            sourceLevel: Value(sourceLevel),
          ),
        );
  }

  Future<void> seedChain({
    required String questionId,
    required String chainId,
    required int createdAt,
    required List<String> actions,
  }) async {
    await db.into(db.reasoningChains).insert(
          ReasoningChainsCompanion.insert(
            id: chainId,
            questionId: questionId,
            createdAt: createdAt,
            summary: const Value(''),
            stepCount: Value(actions.length),
          ),
        );
    for (var i = 0; i < actions.length; i++) {
      await db.into(db.reasoningSteps).insert(
            ReasoningStepsCompanion.insert(
              id: '$chainId-step-$i',
              chainId: chainId,
              idx: i,
              goal: '第 $i 步',
              actionType: Value(actions[i]),
              createdAt: createdAt,
            ),
          );
    }
  }

  test('只返回最新一条链里含这个动作的题；没链的题不出现', () async {
    await seedQuestion(id: 'q-hit', sourceLevel: 'gaokao');
    await seedQuestion(id: 'q-other', sourceLevel: 'gaokao');
    await seedQuestion(id: 'q-nochain', sourceLevel: 'gaokao');
    await seedChain(
      questionId: 'q-hit',
      chainId: 'chain-hit',
      createdAt: 10,
      actions: const <String>['case_split', 'sanity_check'],
    );
    await seedChain(
      questionId: 'q-other',
      chainId: 'chain-other',
      createdAt: 10,
      actions: const <String>['induction'],
    );

    final rows = await readQuestionsForAction(db, 'case_split');

    expect(rows.map((row) => row.questionId).toList(), <String>['q-hit']);
    expect(
        rows.single.actionTypes, const <String>['case_split', 'sanity_check']);
    expect(rows.single.stem, '题干 q-hit');
  });

  test('旧链里出现过、最新一条链里没有 → 不算命中', () async {
    await seedQuestion(id: 'q-1');
    await seedChain(
      questionId: 'q-1',
      chainId: 'chain-old',
      createdAt: 5,
      actions: const <String>['case_split'],
    );
    await seedChain(
      questionId: 'q-1',
      chainId: 'chain-new',
      createdAt: 9,
      actions: const <String>['induction'],
    );

    expect(await readQuestionsForAction(db, 'case_split'), isEmpty);
    expect(
      (await readQuestionsForAction(db, 'induction')).single.questionId,
      'q-1',
    );
  });

  test('排序：来源分级高的在前，平手按 id；空动作/没命中都返回空', () async {
    for (final id in <String>['q-school', 'q-gaokao-b', 'q-gaokao-a']) {
      await seedQuestion(
        id: id,
        sourceLevel: id == 'q-school' ? 'school' : 'gaokao',
      );
      await seedChain(
        questionId: id,
        chainId: 'chain-$id',
        createdAt: 10,
        actions: const <String>['case_split'],
      );
    }

    final rows = await readQuestionsForAction(db, ' case_split ');
    expect(
      rows.map((row) => row.questionId).toList(),
      <String>['q-gaokao-a', 'q-gaokao-b', 'q-school'],
    );

    expect(await readQuestionsForAction(db, '  '), isEmpty);
    expect(await readQuestionsForAction(db, 'not_a_move'), isEmpty);
  });
}
