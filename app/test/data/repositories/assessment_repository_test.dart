import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/assessment_repository.dart';
import 'package:furnace/domain/services/cognitive/assessment_prior.dart';

/// 测评层 M1b 的持久化：会话、步骤、派生的先验。
///
/// 这几条断言是这张表存在的理由，缺一条整个设计就塌：
///
///  * 步骤是**证据**，一轮里"自评"和"抽检"必须各自留下来，不能压成一个分数；
///  * 没有证据的步骤**当场被拒**（写进去只会让读数多一个空洞样本）；
///  * 先验是**派生的**——证据没了，先验必须跟着没，不能靠人工记得去清。
void main() {
  late AppDatabase db;
  late AssessmentRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AssessmentRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedPoint(String id) => db.into(db.knowledgePoints).insert(
        KnowledgePointsCompanion.insert(
          id: id,
          title: id,
          content: '内容 $id',
          createdAt: 1700000000000,
          updatedAt: 1700000000000,
        ),
      );

  test('一轮的步骤原样回来，结束时间只记一次', () async {
    await seedPoint('kp1');
    await seedPoint('kp2');
    final started = DateTime(2026, 10, 15, 9);
    final id = await repo.startSession(
      subjectKey: 'biology',
      scopeTagIds: const <String>['t1', 't2'],
      budget: const <String, Object?>{'items': 6},
      note: '生物·光合作用',
      now: started,
    );

    await repo.addStep(
      sessionId: id,
      stepKind: AssessmentRepository.selfReportStep,
      knowledgePointId: 'kp1',
      selfRating: 4,
      confidence: 5,
      elapsedMs: 4200,
      now: started.add(const Duration(minutes: 1)),
    );
    await repo.addStep(
      sessionId: id,
      stepKind: AssessmentRepository.objectiveStep,
      knowledgePointId: 'kp1',
      prompt: '光合作用的场所？',
      answer: '叶绿体',
      correct: false,
      now: started.add(const Duration(minutes: 2)),
    );
    await repo.addStep(
      sessionId: id,
      stepKind: AssessmentRepository.objectiveStep,
      knowledgePointId: 'kp2',
      correct: true,
      now: started.add(const Duration(minutes: 3)),
    );

    final firstFinish = started.add(const Duration(minutes: 4));
    await repo.finishSession(id, now: firstFinish);
    await repo.finishSession(id, now: started.add(const Duration(hours: 2)));

    final session = await repo.session(id);
    expect(session!.subjectKey, 'biology');
    expect(session.scopeTagIds, '["t1","t2"]');
    expect(session.budget, '{"items":6}');
    expect(session.note, '生物·光合作用');
    expect(
      session.finishedAt,
      firstFinish.millisecondsSinceEpoch,
      reason: '结束时间是事实，重复点击不该把它往后推',
    );

    final steps = await repo.steps(id);
    expect(steps, hasLength(3));
    expect(steps.map((s) => s.stepKind).toList(), <String>[
      AssessmentRepository.selfReportStep,
      AssessmentRepository.objectiveStep,
      AssessmentRepository.objectiveStep,
    ]);
    expect(steps.first.selfRating, 4);
    expect(steps.first.correct, isNull, reason: '自评这一步没有客观判分');
    expect(steps[1].correct, isFalse, reason: '错答记的是 false，不是 NULL');
    expect(steps[1].judgedBy, 'self');
    expect(await repo.sessions(limit: 5), hasLength(1));
  });

  test('没有证据的步骤当场被拒，且一行都不落库', () async {
    await seedPoint('kp1');
    final id = await repo.startSession(now: DateTime(2026, 10, 15, 9));

    await expectLater(
      repo.addStep(
        sessionId: id,
        stepKind: AssessmentRepository.selfReportStep,
        knowledgePointId: 'kp1',
      ),
      throwsArgumentError,
      reason: '自评步骤没有自评值 = 调用方漏填',
    );
    await expectLater(
      repo.addStep(
        sessionId: id,
        stepKind: AssessmentRepository.objectiveStep,
        knowledgePointId: 'kp1',
      ),
      throwsArgumentError,
      reason: '客观步骤没有判分 = 调用方漏填',
    );
    await expectLater(
      repo.addStep(
        sessionId: id,
        stepKind: AssessmentRepository.recallStep,
        knowledgePointId: 'kp1',
      ),
      throwsArgumentError,
      reason: '只有 elapsedMs 之类的步骤不携带证据，不该写',
    );
    await expectLater(
      repo.addStep(
        sessionId: id,
        stepKind: AssessmentRepository.selfReportStep,
        knowledgePointId: 'kp1',
        selfRating: 6,
      ),
      throwsArgumentError,
      reason: '自评是 0–5 的 JOL',
    );

    expect(await repo.steps(id), isEmpty);
  });

  test('先验是派生的：重算与读数一致，证据没了先验也得没', () async {
    await seedPoint('kp1');
    await seedPoint('kp2');
    final started = DateTime(2026, 10, 15, 9);
    final id = await repo.startSession(now: started);

    // kp1：自评 5 加两道抽检（一对一错）→ 两种信号都有 → blended。
    await repo.addStep(
      sessionId: id,
      stepKind: AssessmentRepository.selfReportStep,
      knowledgePointId: 'kp1',
      selfRating: 5,
      now: started.add(const Duration(minutes: 1)),
    );
    await repo.addStep(
      sessionId: id,
      stepKind: AssessmentRepository.objectiveStep,
      knowledgePointId: 'kp1',
      correct: true,
      now: started.add(const Duration(minutes: 2)),
    );
    await repo.addStep(
      sessionId: id,
      stepKind: AssessmentRepository.objectiveStep,
      knowledgePointId: 'kp1',
      correct: false,
      now: started.add(const Duration(minutes: 3)),
    );
    // kp2：只有自评 → 只够给"主观流畅度"型先验，难度必须留空。
    await repo.addStep(
      sessionId: id,
      stepKind: AssessmentRepository.selfReportStep,
      knowledgePointId: 'kp2',
      selfRating: 1,
      now: started.add(const Duration(minutes: 4)),
    );

    final reading = await repo.rebuildPriors(
      now: started.add(const Duration(minutes: 5)),
    );
    expect(reading.estimates, hasLength(2));
    // 读数必须与"拿同一批证据直接跑纯逻辑层"一致：仓储不做第二套算术。
    final fromScratch = AssessmentPrior.read(
      evidence: await repo.evidenceFor(id),
    );
    expect(
      reading.estimates.map((e) => e.r0).toList(),
      fromScratch.estimates.map((e) => e.r0).toList(),
    );
    expect(reading.calibrationBias, fromScratch.calibrationBias);

    final priors = await repo.priorsFor(<String>['kp1', 'kp2']);
    expect(priors.keys, containsAll(<String>['kp1', 'kp2']));
    final kp1 = priors['kp1']!.single;
    expect(kp1.source, AssessmentRepository.blendedSource);
    expect(kp1.d, isNotNull);
    expect(kp1.fluency, isNotNull);
    expect(kp1.n, 3);
    expect(kp1.calibrated, 0, reason: '首版全部未标定');
    final kp2 = priors['kp2']!.single;
    expect(kp2.source, AssessmentRepository.selfSource);
    expect(kp2.d, isNull, reason: '没有抽检就给不出难度');
    expect(kp2.n, 1);

    // 证据消失 → 先验跟着消失。
    await repo.deleteSession(id);
    expect(await repo.steps(id), isEmpty);
    expect(await repo.session(id), isNull);
    expect(
      (await repo.priorsFor(<String>['kp1'])).isEmpty,
      isFalse,
      reason: '先验是派生的，删证据不会顺手删它——重算才是它的来源',
    );
    final after = await repo.rebuildPriors();
    expect(after.estimates, isEmpty);
    expect(await db.select(db.cognitivePriors).get(), isEmpty);
  });

  test('多来源先验的合并优先取混合，其次客观，最后自评', () async {
    await seedPoint('kp1');
    // rebuildPriors 每个知识点只产出一行（来源由信号推导），但表允许同一知识点
    // 有多来源（主键是 知识点 + 来源），所以合并规则必须自己写清楚。
    await db.batch((batch) {
      batch.insertAll(db.cognitivePriors, [
        CognitivePriorsCompanion.insert(
          knowledgePointId: 'kp1',
          source: AssessmentRepository.selfSource,
          r0: 0.45,
          fluency: const Value(0.2),
          n: const Value(1),
          createdAt: 1700000000000,
        ),
        CognitivePriorsCompanion.insert(
          knowledgePointId: 'kp1',
          source: AssessmentRepository.objectiveSource,
          r0: 0.62,
          d: const Value(6.0),
          n: const Value(3),
          createdAt: 1700000000001,
        ),
        CognitivePriorsCompanion.insert(
          knowledgePointId: 'kp1',
          source: AssessmentRepository.blendedSource,
          r0: 0.55,
          d: const Value(5.0),
          fluency: const Value(0.4),
          n: const Value(4),
          createdAt: 1700000000002,
        ),
      ]);
    });

    final merged = await repo.priorFor('kp1');
    expect(merged!.r0, 0.55);
    expect(merged.n, 4);
    expect(
      merged.confidence,
      closeTo(4 / 7, 1e-9),
      reason: '置信度由 n 决定，不单独存',
    );
    expect(merged.basis.single, 'prior:${AssessmentRepository.blendedSource}');

    expect(await repo.clearPriors(source: AssessmentRepository.selfSource), 1);
    expect(await repo.priorsFor(<String>['kp1']), hasLength(1));
    expect(await repo.clearPriors(), 2);
    expect(await repo.clearPriors(), 0);
  });

  test('批量先验与逐个先验给出同一答案（读数页用的就是批量版）', () async {
    await seedPoint('kp1');
    await seedPoint('kp2');
    await db.batch((batch) {
      batch.insertAll(db.cognitivePriors, [
        CognitivePriorsCompanion.insert(
          knowledgePointId: 'kp1',
          source: AssessmentRepository.selfSource,
          r0: 0.45,
          fluency: const Value(0.2),
          n: const Value(1),
          createdAt: 1700000000000,
        ),
        CognitivePriorsCompanion.insert(
          knowledgePointId: 'kp1',
          source: AssessmentRepository.blendedSource,
          r0: 0.55,
          d: const Value(5.0),
          fluency: const Value(0.4),
          n: const Value(4),
          createdAt: 1700000000001,
        ),
        CognitivePriorsCompanion.insert(
          knowledgePointId: 'kp2',
          source: AssessmentRepository.objectiveSource,
          r0: 0.80,
          d: const Value(3.0),
          n: const Value(2),
          createdAt: 1700000000002,
        ),
      ]);
    });

    final batch = await repo.priorEstimatesFor(<String>['kp1', 'kp2', 'kp3']);

    // kp3 has no prior: it must be absent, not a zero-filled guess.
    expect(batch.keys.toSet(), {'kp1', 'kp2'});
    final one = await repo.priorFor('kp1');
    expect(batch['kp1']!.r0, one!.r0);
    expect(batch['kp1']!.basis, one.basis);
    expect(batch['kp1']!.confidence, one.confidence);
    expect(batch['kp2']!.basis.single,
        'prior:${AssessmentRepository.objectiveSource}');
    expect(batch['kp2']!.difficulty, 3.0);
    expect(batch['kp2']!.fluency, isNull);
    // 空输入不查库、也不报错。
    expect(await repo.priorEstimatesFor(const <String>[]), isEmpty);
  });
}
