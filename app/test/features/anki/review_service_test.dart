import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/diffusion_log_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/domain/services/cloze/tag_diffusion.dart';
import 'package:furnace/domain/services/srs/fsrs_scheduler.dart';
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

      final states = await anki.unitStatesForKnowledgePoint(item.knowledgePointId);
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

      final states = await anki.unitStatesForKnowledgePoint(item.knowledgePointId);
      expect(states.single.forced, 0);
      expect(states.single.forcedStreak, 0);
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
      expect(feedbackState.stability, plainState.stability);
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
      final plainLog =
          logs.firstWhere((l) => l.cardStateId == plainState.id);
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

    test('the same pre-review row predicts the same thing either way', () async {
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
}
