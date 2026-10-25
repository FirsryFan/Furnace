import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/diffusion_log_repository.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/domain/services/cloze/tag_diffusion.dart';
import 'package:furnace/domain/services/cognitive/cognitive_model.dart';
import 'package:furnace/domain/services/srs/fsrs_scheduler.dart';
import 'package:furnace/domain/services/srs/review_retention.dart';
import 'package:furnace/features/anki/application/review_service.dart';

/// The review engine (blueprint 4; user annotations 17, 18, 19):
/// one blank per question, a wrong answer bound to come back the same day,
/// exact-character strict grading, and tag-tree diffusion recorded per day.
void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late TagRepository tags;
  late ReviewService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    tags = TagRepository(db);
    service = ReviewService(
      ankiRepository: anki,
      tagRepository: tags,
      taskRepository: TaskRepository(db),
      diffusionLogRepository: DiffusionLogRepository(db),
      random: Random(7),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('tag-tree diffusion replaces the node graph', () {
    test('distance keeps the spec meaning: 1 = parent/child or siblings', () {
      // parent / child
      expect(TagDiffusion.distance('文化课/数学/函数', '文化课/数学'), 1);
      // siblings (same parent)
      expect(TagDiffusion.distance('文化课/数学/函数', '文化课/数学/几何'), 1);
      // grandparent / grandchild
      expect(TagDiffusion.distance('文化课/数学/函数', '文化课'), 2);
      // cousins share a grandparent: 2 up + 2 down
      expect(TagDiffusion.distance('文化课/数学/函数', '文化课/语文/作文'), 4);
      // different roots are unrelated
      expect(TagDiffusion.distance('文化课', '体育'), isNull);
      // itself
      expect(TagDiffusion.distance('文化课/数学', '文化课/数学'), 0);
    });

    test('factors stay x1.8 / x1.3 and nothing beyond distance 2', () {
      // distance 1: sibling
      expect(
        TagDiffusion.boostFactor(
          wrongPaths: const ['文化课/数学/函数'],
          candidatePath: '文化课/数学/几何',
        ),
        1.8,
      );
      // distance 2: grandparent
      expect(
        TagDiffusion.boostFactor(
          wrongPaths: const ['文化课/数学/函数'],
          candidatePath: '文化课',
        ),
        1.3,
      );
      // distance 4 (cousin) and unrelated roots get nothing
      expect(
        TagDiffusion.boostFactor(
          wrongPaths: const ['文化课/数学/函数'],
          candidatePath: '文化课/语文/作文',
        ),
        1.0,
      );
      expect(
        TagDiffusion.boostFactor(
          wrongPaths: const ['文化课/数学/函数'],
          candidatePath: '体育/篮球',
        ),
        1.0,
      );
    });
  });

  group('strict grading (annotation 18)', () {
    test('characters must match exactly, no normalisation at all', () {
      expect(ReviewService.strictMatch('叶绿体', '叶绿体'), isTrue);
      expect(ReviewService.strictMatch('叶绿体', '叶绿体 '), isFalse,
          reason: 'no whitespace trimming');
      expect(ReviewService.strictMatch('叶绿体', ' 叶绿体'), isFalse);
      expect(ReviewService.strictMatch('叶绿体', '叶绿體'), isFalse);
      expect(ReviewService.strictMatch('ATP', 'atp'), isFalse,
          reason: 'case matters for spelling practice');
      expect(ReviewService.strictMatch('1/2', '0.5'), isFalse);
    });
  });

  group('queue, binding and the day ledger', () {
    Future<KnowledgePoint> makePoint(String title, String content) {
      return anki.createKnowledgePoint(title: title, content: content);
    }

    test('a queued item shows exactly one blank', () async {
      await makePoint('光合作用场所', '光合作用的主要场所是叶绿体。');
      final queue = await service.buildQueue();

      expect(queue, hasLength(1));
      final item = queue.single;
      expect(item.question, contains('______'));
      expect(item.question.split('______'), hasLength(2),
          reason: 'one blank per question');
      expect(item.answer, '叶绿体');
      expect(item.slotStart, isNotNull);
    });

    test('a wrong answer binds that blank for the same day', () async {
      await makePoint('光合作用场所', '光合作用的主要场所是叶绿体。');
      final item = (await service.buildQueue()).single;

      final outcome = await service.grade(
        item: item,
        correct: false,
        rating: FsrsRating.good,
        submitted: '线粒体',
      );

      expect(outcome.correct, isFalse);
      expect(outcome.stillForced, isTrue,
          reason: 'the unit must come back today');
      expect(outcome.released, isFalse);
      expect(outcome.nextDueAt.difference(DateTime.now()).inMinutes,
          lessThanOrEqualTo(10));

      final states =
          await anki.unitStatesForKnowledgePoint(item.knowledgePointId);
      expect(states.single.forced, 1);
      expect(states.single.forcedStreak, 0);
      expect(states.single.state, 'learning_forced');

      // The next queue draws the bound unit so it really does reappear.
      final again = await service.buildQueue();
      expect(again, hasLength(1));
      expect(again.single.unitKey, item.unitKey);
    });

    test('two correct answers in a row release the binding', () async {
      await makePoint('光合作用场所', '光合作用的主要场所是叶绿体。');
      var item = (await service.buildQueue()).single;
      await service.grade(
        item: item,
        correct: false,
        rating: FsrsRating.good,
      );

      item = (await service.buildQueue()).single;
      final first = await service.grade(
        item: item,
        correct: true,
        rating: FsrsRating.good,
      );
      expect(first.stillForced, isTrue);
      expect(first.released, isFalse);

      item = (await service.buildQueue()).single;
      final second = await service.grade(
        item: item,
        correct: true,
        rating: FsrsRating.good,
      );
      expect(second.released, isTrue);
      expect(second.stillForced, isFalse);

      final states =
          await anki.unitStatesForKnowledgePoint(item.knowledgePointId);
      expect(states.single.forced, 0);
      expect(states.single.forcedStreak, 0);
    });

    test(
        'a wrong answer is forced back into today\'s queue, and the redo '
        'grades from a freshly read row', () async {
      await makePoint('光合作用场所', '光合作用的主要场所是叶绿体。');
      final item = (await service.buildQueue()).single;

      final wrong = await service.grade(
        item: item,
        correct: false,
        rating: FsrsRating.good,
      );
      expect(wrong.stillForced, isTrue);
      expect(wrong.immediateRedo, isTrue,
          reason: 'D11: 答错仍要回同一天队列（位置由 ForcedLoop 按 gap 排，不再原地紧跟）');

      // 队列里这一份还是「答错之前」的行（grade 的契约），会话内重做要先读一遍。
      final fresh = await service.refreshItem(item);
      expect(fresh.cardState.forced, 1);
      expect(fresh.cardState.forcedStreak, 0);
      // 只有行被换掉：单元身份与题干都是队列给的那一份。
      expect(fresh.unitKey, item.unitKey);
      expect(fresh.question, item.question);
      expect(fresh.answer, item.answer);
      expect(fresh.clozeSlotKey, item.clozeSlotKey);
      expect(fresh.slotStart, item.slotStart);

      final first = await service.grade(
        item: fresh,
        correct: true,
        rating: FsrsRating.good,
      );
      expect(first.stillForced, isTrue);
      expect(first.released, isFalse);
      expect(first.immediateRedo, isFalse,
          reason: '答对一次只进强制期：隔 gap 张、10 分钟后再出现');

      final second = await service.grade(
        item: await service.refreshItem(fresh),
        correct: true,
        rating: FsrsRating.good,
      );
      expect(second.released, isTrue);
      expect(second.stillForced, isFalse);
      expect(second.immediateRedo, isFalse);
    });

    test(
        'grading the queue snapshot again cannot count the second correct '
        'answer - which is why the redo refreshes the row', () async {
      await makePoint('光合作用场所', '光合作用的主要场所是叶绿体。');
      final item = (await service.buildQueue()).single;
      await service.grade(
        item: item,
        correct: false,
        rating: FsrsRating.good,
      );

      // 同一个老快照再判一次：grade 看到的还是「从来没被绑定过」的行，于是它认为
      // 这次答对不需要继续强制，顺手把绑定写掉了——D11 的连续两次永远数不到第二次。
      final stale = await service.grade(
        item: item,
        correct: true,
        rating: FsrsRating.good,
      );
      expect(stale.stillForced, isFalse);
      expect(stale.released, isFalse);

      final states =
          await anki.unitStatesForKnowledgePoint(item.knowledgePointId);
      expect(states.single.forced, 0,
          reason: '老快照把绑定洗掉了：闭环必须先 ReviewService.refreshItem');
    });

    test(
        'a template card refreshes its row too - the state row has no knowledge '
        'point id, so it can only be read by row id', () async {
      final point = await makePoint('光合作用场所', '光合作用的主要场所是叶绿体。');
      final template = await anki.createTemplate(
        knowledgePointId: point.id,
        type: 'essay',
        question: '光合作用的主要场所是？',
        answer: '叶绿体',
      );

      final item = (await service.buildQueue())
          .singleWhere((i) => i.templateId == template.id);
      expect(item.unitKey, 'preset:${template.id}');

      final wrong = await service.grade(
        item: item,
        correct: false,
        rating: FsrsRating.good,
      );
      expect(wrong.stillForced, isTrue);

      final fresh = await service.refreshItem(item);
      expect(fresh.cardState.id, item.cardState.id);
      expect(fresh.cardState.forced, 1,
          reason: '模板卡的 state 行 knowledge_point_id 是 NULL，'
              '按 (知识点, unitKey) 查会一直拿回答题前的旧快照');
      expect(fresh.cardState.forcedStreak, 0);

      final firstCorrect = await service.grade(
        item: fresh,
        correct: true,
        rating: FsrsRating.good,
      );
      expect(firstCorrect.stillForced, isTrue);
      expect(firstCorrect.released, isFalse, reason: '模板卡也要按 D11 数到第二次连续答对才解除');

      final secondCorrect = await service.grade(
        item: await service.refreshItem(fresh),
        correct: true,
        rating: FsrsRating.good,
      );
      expect(secondCorrect.released, isTrue);
      expect(secondCorrect.stillForced, isFalse);
    });

    test('a correct answer schedules through FSRS, not a fixed interval',
        () async {
      await makePoint('光合作用场所', '光合作用的主要场所是叶绿体。');
      final item = (await service.buildQueue()).single;
      final outcome = await service.grade(
        item: item,
        correct: true,
        rating: FsrsRating.good,
      );
      expect(outcome.scheduledDays, greaterThan(0));
      expect(outcome.nextDueAt.isAfter(DateTime.now()), isTrue);
    });

    test('a wrong answer lifts related items and writes the day ledger',
        () async {
      final math = await tags.createTag(name: '数学');
      final algebra = await tags.createTag(name: '代数', parentId: math.id);
      final geometry = await tags.createTag(name: '几何', parentId: math.id);
      final wrong = await makePoint('函数定义', '函数是一种对应关系。');
      final sibling = await makePoint('几何定义', '几何是研究图形的一门学科。');
      await tags.addTagToObject(
        tagId: algebra.id,
        objectType: 'knowledge_point',
        objectId: wrong.id,
      );
      await tags.addTagToObject(
        tagId: geometry.id,
        objectType: 'knowledge_point',
        objectId: sibling.id,
      );

      final item = (await service.buildQueue())
          .firstWhere((i) => i.knowledgePointId == wrong.id);
      final outcome = await service.grade(
        item: item,
        correct: false,
        rating: FsrsRating.good,
      );

      expect(outcome.boosted, hasLength(1));
      expect(outcome.boosted.single.title, '几何定义');
      expect(outcome.boosted.single.factor, 1.8);
      expect(outcome.boosted.single.distance, 1);

      final boost = await anki.boostFor(sibling.id);
      expect(boost, isNotNull);
      expect(boost!.remainingCycles, 3);

      final ledger = DiffusionLogRepository(db);
      final summary = await ledger.summarizeDay(DateTime.now());
      expect(summary.wrongCount, 1);
      expect(summary.boostCount, 1);
      expect(
        summary.entries.map((e) => e.kind),
        containsAll(<String>['wrong', 'boost']),
      );
      expect(summary.entries.first.dayKey,
          DiffusionLogRepository.dayKeyOf(DateTime.now()));
    });

    test('an unrelated knowledge point is not lifted', () async {
      final math = await tags.createTag(name: '数学');
      final sport = await tags.createTag(name: '体育');
      final wrong = await makePoint('函数定义', '函数是一种对应关系。');
      final other = await makePoint('篮球规则', '篮球每队五人。');
      await tags.addTagToObject(
        tagId: math.id,
        objectType: 'knowledge_point',
        objectId: wrong.id,
      );
      await tags.addTagToObject(
        tagId: sport.id,
        objectType: 'knowledge_point',
        objectId: other.id,
      );

      final item = (await service.buildQueue())
          .firstWhere((i) => i.knowledgePointId == wrong.id);
      final outcome = await service.grade(
        item: item,
        correct: false,
        rating: FsrsRating.good,
      );
      expect(outcome.boosted, isEmpty);
      expect(await anki.boostFor(other.id), isNull);
    });

    test('reviewing can create a Thread event (Knowledge -> Thread)', () async {
      await makePoint('待查概念', '这个概念需要查资料。');
      final item = (await service.buildQueue()).single;
      final task = await service.createEventFromItem(item);
      expect(task.title, '待查概念');
      expect(task.description, contains('来自复习'));
    });
  });

  group('a miss followed by the solution (MindNet IO_PROTOCOL 2.3)', () {
    test('is logged as feedback, and leaves the FSRS schedule untouched',
        () async {
      // Two identical cards, one reviewed each way. The point of the
      // distinction is the *cognitive model*, not the interval: FSRS stays the
      // only authority for the due date (design rule D1), which is exactly what
      // the review screen promises the user when it asks the question.
      final missed = await anki.createKnowledgePoint(
        title: '光合作用场所甲',
        content: '光合作用的主要场所是叶绿体。',
      );
      final nearMiss = await anki.createKnowledgePoint(
        title: '光合作用场所乙',
        content: '光合作用的主要场所是叶绿体。',
      );
      // Draw the queue once so the presentation units exist, ripen both equally
      // (S = 19.2h, reviewed 10 hours ago, so R stays high), then draw it again:
      // an item carries the row as it was when the queue was drawn, and a
      // brand-new row sits at `effort = 1` because the retrievability term alone
      // saturates the clamp - the two paths would then coincide for a reason
      // that has nothing to do with the event mapping.
      await service.buildQueue();
      final tenHoursAgo = DateTime.now()
          .subtract(const Duration(hours: 10))
          .millisecondsSinceEpoch;
      for (final kp in [missed, nearMiss]) {
        final row = (await anki.unitStatesForKnowledgePoint(kp.id)).single;
        await anki.updateUnitCardState(
          row.id,
          stability: 19.2,
          difficulty: 5.1618,
          lastReviewedAt: tenHoursAgo,
        );
      }
      final queue = await service.buildQueue();
      final plainItem =
          queue.firstWhere((i) => i.knowledgePointId == missed.id);
      final feedbackItem =
          queue.firstWhere((i) => i.knowledgePointId == nearMiss.id);

      await service.grade(
        item: plainItem,
        correct: false,
        rating: FsrsRating.good,
        submitted: '线粒体',
      );
      await service.grade(
        item: feedbackItem,
        correct: false,
        rating: FsrsRating.good,
        submitted: '线粒体',
        reviewedSolution: true,
        closeness: 0.6,
      );

      final plainState =
          (await anki.unitStatesForKnowledgePoint(missed.id)).single;
      final feedbackState =
          (await anki.unitStatesForKnowledgePoint(nearMiss.id)).single;

      // Same failed recall, so the same lapse in FSRS: same interval, same
      // forced binding, same model ceiling.
      //
      // 容差而不是相等：两次 `grade` 之间隔了几毫秒，FSRS 用"现在"算经过天数，
      // 浮点尾数会差出 1e-8 量级（实测 1.62332132 vs 1.62332135）—— 那不是
      // 认知模型的分歧，是钟的分歧。
      expect(plainState.stability, isNotNull);
      expect(feedbackState.stability, isNotNull);
      expect(
        (feedbackState.stability! - plainState.stability!).abs(),
        lessThan(1e-5),
      );
      // The due stamp is taken from the wall clock at write time, so the two
      // reviews differ by milliseconds; the interval is what must match.
      expect(
        (feedbackState.dueAt! - plainState.dueAt!).abs(),
        lessThan(2000),
        reason: 'the answer to the question must not move the schedule',
      );
      expect(feedbackState.forced, 1);
      expect(feedbackState.encodingStrength, plainState.encodingStrength,
          reason: 'R0 only moves on a successful retrieval');

      // The model does see the difference, through `Sigma`: the storage term
      // uses `effort = (1 - R) + (1 - closeness)`
      // (MindNet mechanisms/memory.dsr.js, the storage-strength line), so a
      // nearer miss claims slightly less of it than an unexplained one.
      expect(feedbackState.savings, isNotNull);
      expect(plainState.savings, isNotNull);
      expect(feedbackState.savings, lessThan(plainState.savings!));

      final logs = await db.select(db.reviewLogs).get();
      final plainLog = logs.firstWhere((l) => l.cardStateId == plainState.id);
      final feedbackLog =
          logs.firstWhere((l) => l.cardStateId == feedbackState.id);
      expect(plainLog.reviewedSolution, isFalse,
          reason: 'asked, and the answer was no');
      expect(plainLog.closeness, isNull);
      expect(feedbackLog.reviewedSolution, isTrue);
      expect(feedbackLog.closeness, closeTo(0.6, 1e-9));
      expect(feedbackLog.correct, 0);
    });

    test('a correct answer leaves both new columns null', () async {
      await anki.createKnowledgePoint(
        title: '光合作用场所',
        content: '光合作用的主要场所是叶绿体。',
      );
      final item = (await service.buildQueue()).single;
      await service.grade(item: item, correct: true, rating: FsrsRating.good);

      final log = (await db.select(db.reviewLogs).get()).single;
      expect(log.reviewedSolution, isNull,
          reason: 'the question is never asked after a correct answer, so the '
              'column must stay unknown rather than default to false');
      expect(log.closeness, isNull);
    });
  });

  group('the pre-review prediction (M6 calibration)', () {
    test('a graded review records the prediction, in range', () async {
      await anki.createKnowledgePoint(
        title: '光合作用场所',
        content: '光合作用的主要场所是叶绿体。',
      );
      final item = (await service.buildQueue()).single;

      await service.grade(item: item, correct: true, rating: FsrsRating.good);

      final log = (await db.select(db.reviewLogs).get()).single;
      expect(
        log.predictedR,
        isNotNull,
        reason: '预测必须在判分之前落库，否则这条日志永远进不了校准曲线',
      );
      expect(log.predictedR, greaterThan(0));
      expect(log.predictedR, lessThanOrEqualTo(1));
    });

    test('the same pre-review row predicts the same thing either way',
        () async {
      // 两张一模一样的卡（模型状态相同），一张答对、一张答错。预测值必须相同：
      // 它是在答案出现之前算的，如果哪天有人把它挪到判分之后，这条会红。
      final right = await anki.createKnowledgePoint(
        title: '光合作用场所甲',
        content: '光合作用的主要场所是叶绿体。',
      );
      final wrong = await anki.createKnowledgePoint(
        title: '光合作用场所乙',
        content: '光合作用的主要场所是叶绿体。',
      );
      final queue = await service.buildQueue();

      await service.grade(
        item: queue.firstWhere((i) => i.knowledgePointId == right.id),
        correct: true,
        rating: FsrsRating.good,
      );
      await service.grade(
        item: queue.firstWhere((i) => i.knowledgePointId == wrong.id),
        correct: false,
        rating: FsrsRating.good,
        submitted: '线粒体',
      );

      final logs = await db.select(db.reviewLogs).get();
      expect(logs, hasLength(2));
      final rightLog = logs.singleWhere((l) => l.correct == 1);
      final wrongLog = logs.singleWhere((l) => l.correct == 0);
      expect(rightLog.predictedR, isNotNull);
      expect(wrongLog.predictedR, isNotNull);
      expect(
        rightLog.predictedR,
        closeTo(wrongLog.predictedR!, 1e-3),
        reason: '预测只依赖复习前的行与时刻，与这次答对答错无关',
      );
    });
  });

  group('exposure（读了但没测）', () {
    test('记一次读过：不写复习记录、不动到期日，只更新模型两列', () async {
      await anki.createKnowledgePoint(
        title: '光合作用场所',
        content: '光合作用的主要场所是叶绿体。',
      );
      final queue = await service.buildQueue();
      expect(queue, hasLength(1));
      final item = queue.single;

      final before = await (db.select(db.cardStates)
            ..where((t) => t.id.equals(item.cardState.id)))
          .getSingle();

      final moment = DateTime(2026, 10, 16, 20);
      final outcome = await service.recordExposure(item: item, now: moment);

      expect(outcome.cardStateId, before.id);
      expect(outcome.exposedAt, moment);
      expect(outcome.modelState, isNotNull, reason: '默认 advisor 可用，两列会被写');

      final rows = await db.select(db.exposureLogs).get();
      expect(rows, hasLength(1));
      expect(rows.single.cardStateId, before.id);
      expect(rows.single.source, kExposureSourceAnswerReveal);
      expect(rows.single.exposedAt, moment.millisecondsSinceEpoch);
      expect(rows.single.createdAt, moment.millisecondsSinceEpoch);

      // 这不是一次测试：复习记录仍然空着，而留存率桶与标定曲线只读那张表。
      expect(await db.select(db.reviewLogs).get(), isEmpty);

      // FSRS 的每一个列都没动：读不是"记得"的证据，间隔只能由提取证据推动。
      final after = await (db.select(db.cardStates)
            ..where((t) => t.id.equals(before.id)))
          .getSingle();
      expect(after.dueAt, before.dueAt);
      expect(after.stability, before.stability);
      expect(after.difficulty, before.difficulty);
      expect(after.repetitions, before.repetitions);
      expect(after.lapses, before.lapses);
      expect(after.lastReviewedAt, before.lastReviewedAt);
      expect(after.forced, before.forced);

      // 模型两列被写了，而且 R0 天花板没有被抬（那是 retrieval_success 的专利）。
      expect(after.encodingStrength, isNotNull);
      final reading = const MindNetCognitiveModel()
          .modelReadingOf(before, nowHours: modelHoursOf(moment));
      expect(after.encodingStrength, closeTo(reading.r0, 1e-12));
    });
  });

  // 用户反馈（2026-10-25）：同一批闪存卡反反复复，新卡却总排不到——因为
  // unseen band 老老实实跟在所有复习卡后面，复习没做完停下就永远见不到新卡。
  // 现在新卡按固定节奏插进复习序列（review_pacing.dart），本组钉住队列顺序。
  group('新卡交错：新卡不再全堆在队尾（review pacing）', () {
    /// 造 [review] 张「今天到期、复习过」的卡和 [fresh] 张从未见过的新卡。
    ///
    /// 先抽一次队列让每个知识点都有 unit 行，再把复习卡改成「复习过且已到期」：
    /// band 依据 `isNew = repetitions == 0`，所以 repetitions=1 落进 model band，
    /// repetitions 仍为 0 的留在 unseen band。
    Future<void> seed({required int review, required int fresh}) async {
      final reviewIds = <String>[];
      for (var i = 0; i < review; i++) {
        final point = await anki.createKnowledgePoint(
          title: '复习卡$i',
          content: '复习卡$i 的正文内容。',
        );
        reviewIds.add(point.id);
      }
      for (var i = 0; i < fresh; i++) {
        await anki.createKnowledgePoint(
          title: '新卡$i',
          content: '新卡$i 的正文内容。',
        );
      }
      await service.buildQueue();
      final now = DateTime.now();
      final due = now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
      final reviewed =
          now.subtract(const Duration(hours: 10)).millisecondsSinceEpoch;
      for (final id in reviewIds) {
        final row = (await anki.unitStatesForKnowledgePoint(id)).single;
        await anki.updateUnitCardState(
          row.id,
          dueAt: due,
          repetitions: 1,
          lastReviewedAt: reviewed,
          stability: 19.2,
          difficulty: 5.1618,
        );
      }
    }

    List<int> newIndexes(List<ReviewItem> queue) => [
          for (var i = 0; i < queue.length; i++)
            if (queue[i].isNew) i,
        ];

    test('12 张复习卡 + 3 张新卡：新卡落在第 6、第 12 位和队尾', () async {
      await seed(review: 12, fresh: 3);
      final queue = await service.buildQueue();
      expect(queue, hasLength(15), reason: '新卡一张都不能丢');
      expect(newIndexes(queue), [5, 11, 14]);
      expect(queue[4].isNew, isFalse);
      expect(queue[5].isNew, isTrue);
    });

    test('复习卡不足 5 张时，新卡仍然接在它们后面', () async {
      await seed(review: 3, fresh: 2);
      final queue = await service.buildQueue();
      expect(queue, hasLength(5));
      expect(newIndexes(queue), [3, 4]);
    });

    test('全是新卡时顺序不变：没有复习卡可插', () async {
      await seed(review: 0, fresh: 3);
      final queue = await service.buildQueue();
      expect(queue, hasLength(3));
      expect(newIndexes(queue), [0, 1, 2]);
    });

    test('没有新卡时复习卡的数量与顺序不受影响', () async {
      await seed(review: 7, fresh: 0);
      final queue = await service.buildQueue();
      expect(queue, hasLength(7));
      expect(newIndexes(queue), isEmpty);
    });
  });

  group('复习间隔的目标保持率（schema v36）', () {
    // 用户反馈「闪存卡间隔时间太短了」：FSRS 的 requestRetention 以前写死 0.9
    // （新卡第一次答对 3 天后再来）。现在由复习偏好里的 更长/标准/更短 决定。
    Future<double> firstGoodInterval(
        ReviewSpacing spacing, String suffix) async {
      final point = await anki.createKnowledgePoint(
        title: '间隔测试$suffix',
        content: '光合作用的主要场所是叶绿体。',
      );
      final settings = SettingsRepository(db);
      await settings.updateReviewRetention(spacing.retention);
      final spaced = ReviewService(
        ankiRepository: anki,
        tagRepository: tags,
        taskRepository: TaskRepository(db),
        diffusionLogRepository: DiffusionLogRepository(db),
        settingsRepository: settings,
        random: Random(7),
      );
      final item = (await spaced.buildQueue())
          .singleWhere((i) => i.knowledgePointId == point.id);
      await spaced.grade(item: item, correct: true, rating: FsrsRating.good);
      final state = (await anki.unitStatesForKnowledgePoint(point.id)).single;
      return state.intervalDays;
    }

    test('保持率越低，第一次答对后的间隔越长', () async {
      final longer = await firstGoodInterval(ReviewSpacing.longer, '甲');
      final standard = await firstGoodInterval(ReviewSpacing.standard, '乙');
      final shorter = await firstGoodInterval(ReviewSpacing.shorter, '丙');
      expect(longer, greaterThan(standard));
      expect(standard, greaterThan(shorter));
      expect(shorter, lessThanOrEqualTo(3),
          reason: '0.90 就是这次改之前的出厂 3 天，锁住旧行为可回退');
    });

    test('没有注入设置仓储时按出厂 0.85 排期，不再退回 0.9', () async {
      final point = await anki.createKnowledgePoint(
        title: '间隔测试出厂',
        content: '光合作用的主要场所是叶绿体。',
      );
      final item = (await service.buildQueue())
          .singleWhere((i) => i.knowledgePointId == point.id);
      await service.grade(item: item, correct: true, rating: FsrsRating.good);
      final state = (await anki.unitStatesForKnowledgePoint(point.id)).single;
      expect(state.intervalDays, greaterThan(3),
          reason: '出厂从 0.9 改成 0.85，间隔必须比旧的 3 天长');
    });
  });
}
