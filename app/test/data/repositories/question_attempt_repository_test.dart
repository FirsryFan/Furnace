import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_attempt_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';

/// 自测作答仓储（schema v32，轮次一百五十五）的三条不变量：
///
///  * **只追加**：一次判分成功一行；同一题有多次作答时历史按新→旧排；
///  * **形状固定**：勾选 label 落库前 trim → 大写 → 去空 → 去重 → 升序，
///    同一组勾选永远得到同一段 JSON；
///  * **随题清理**：删题事务里显式删掉该题作答（本项目没有外键级联），
///    不留下孤儿行。
void main() {
  late AppDatabase db;
  late QuestionAttemptRepository repo;
  late QuestionRepository questions;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = QuestionAttemptRepository(db);
    questions = QuestionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> seedQuestion({String stem = '自测作答用的题'}) async {
    final ingested = await questions.ingest(
      QuestionDraft(
        stem: stem,
        answer: 'A',
        options: const <QuestionOptionDraft>[
          QuestionOptionDraft(label: 'A', content: '1', isCorrect: true),
          QuestionOptionDraft(label: 'B', content: '2'),
        ],
      ),
    );
    return ingested.question.id;
  }

  Future<QuestionAttempt> rowOf(String id) =>
      (db.select(db.questionAttempts)..where((t) => t.id.equals(id)))
          .getSingle();

  test('record 落库：id 非空、label 归一化、时间取 epoch 毫秒', () async {
    final questionId = await seedQuestion();
    final at = DateTime.fromMillisecondsSinceEpoch(1700000000123);
    final first = await repo.record(
      questionId: questionId,
      selectedLabels: const <String>[' b', 'a ', 'A', ''],
      isCorrect: true,
      now: at,
    );
    final second = await repo.record(
      questionId: questionId,
      selectedLabels: const <String>['c'],
      isCorrect: false,
      now: at.add(const Duration(milliseconds: 1)),
    );

    expect(first, isNotEmpty);
    expect(second, isNot(first));

    final row = await rowOf(first);
    expect(row.questionId, questionId);
    expect(row.selectedLabels, '["A","B"]');
    expect(jsonDecode(row.selectedLabels), <String>['A', 'B']);
    expect(row.isCorrect, isTrue);
    expect(row.attemptedAt, at.millisecondsSinceEpoch);
    expect((await rowOf(second)).isCorrect, isFalse);
  });

  test('historyFor 按 attemptedAt 新→旧', () async {
    final questionId = await seedQuestion();
    final base = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final ids = <String>[];
    for (var i = 0; i < 3; i++) {
      ids.add(await repo.record(
        questionId: questionId,
        selectedLabels: const <String>['A'],
        isCorrect: i == 1,
        now: base.add(Duration(milliseconds: i)),
      ));
    }

    final history = await repo.historyFor(questionId);
    expect(history.map((entry) => entry.id), [ids[2], ids[1], ids[0]]);
    expect(history.map((entry) => entry.isCorrect), [false, true, false]);
    expect(
        history.first.attemptedAt, base.add(const Duration(milliseconds: 2)));
  });

  test('同一毫秒的多条按 id 升序（与领域层口径一致）', () async {
    final questionId = await seedQuestion();
    final at = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final ids = <String>[];
    for (var i = 0; i < 4; i++) {
      ids.add(await repo.record(
        questionId: questionId,
        selectedLabels: const <String>['A'],
        isCorrect: i.isEven,
        now: at,
      ));
    }

    final history = await repo.historyFor(questionId);
    expect(history.map((entry) => entry.id), ids.toList()..sort());
    expect(history.map((entry) => entry.attemptedAt).toSet(), <DateTime>{at});
  });

  test('limit 限制条数，limit<=0 直接返回空表', () async {
    final questionId = await seedQuestion();
    final base = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final ids = <String>[];
    for (var i = 0; i < 5; i++) {
      ids.add(await repo.record(
        questionId: questionId,
        selectedLabels: const <String>['A'],
        isCorrect: true,
        now: base.add(Duration(milliseconds: i)),
      ));
    }

    expect(
      (await repo.historyFor(questionId, limit: 2)).map((entry) => entry.id),
      [ids[4], ids[3]],
    );
    expect(await repo.historyFor(questionId, limit: 1), hasLength(1));
    expect(await repo.historyFor(questionId, limit: 0), isEmpty);
    expect(await repo.historyFor(questionId, limit: -3), isEmpty);
    expect(await repo.historyFor('missing-question'), isEmpty);
  });

  test('deleteForQuestion 只删该题并返回删除行数', () async {
    final first = await seedQuestion(stem: '第一题的题干');
    final second = await seedQuestion(stem: '第二题的题干');
    await repo.record(
      questionId: first,
      selectedLabels: const <String>['A'],
      isCorrect: true,
    );
    await repo.record(
      questionId: first,
      selectedLabels: const <String>['B'],
      isCorrect: false,
    );
    await repo.record(
      questionId: second,
      selectedLabels: const <String>['A'],
      isCorrect: true,
    );

    expect(await repo.deleteForQuestion(first), 2);
    expect(await repo.historyFor(first), isEmpty);
    expect(await repo.historyFor(second), hasLength(1));
    expect(await repo.deleteForQuestion(first), 0);
  });

  test('删题连带清掉该题作答，不碰别的题', () async {
    final doomed = await seedQuestion(stem: '会被删掉的题');
    final kept = await seedQuestion(stem: '留下的题');
    await repo.record(
      questionId: doomed,
      selectedLabels: const <String>['A'],
      isCorrect: true,
    );
    await repo.record(
      questionId: doomed,
      selectedLabels: const <String>['A'],
      isCorrect: false,
    );
    await repo.record(
      questionId: kept,
      selectedLabels: const <String>['B'],
      isCorrect: true,
    );

    await questions.deleteQuestion(doomed);

    expect(await questions.byId(doomed), isNull);
    final rows = await db.select(db.questionAttempts).get();
    expect(rows, hasLength(1));
    expect(rows.single.questionId, kept);
    expect(await repo.historyFor(doomed), isEmpty);
    expect(await repo.historyFor(kept), hasLength(1));
  });
}
