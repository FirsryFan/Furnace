import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/diffusion_log_repository.dart';
import 'package:furnace/data/repositories/review_plan_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/domain/services/srs/fsrs_scheduler.dart';
import 'package:furnace/features/anki/application/review_service.dart';

/// The per-group daily plan decides **what today's queue is**:
///
/// > a group hands out a new-card allowance and a review allowance; the queue
/// > shows the cards that still fit, in the model's order. A card with no budget
/// > left waits for tomorrow.
///
/// The cases below pin that down from both sides: each allowance must bite on
/// its own bucket (new vs review), a wrong answer today (annotation 17) must
/// survive both, a card outside every configured group must stay unlimited, and
/// with nothing configured the queue is built exactly as it was before the plan
/// existed.
void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late TagRepository tags;
  late ReviewPlanRepository plans;
  late ReviewService service;

  final moment = DateTime(2026, 10, 12, 20, 30);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    tags = TagRepository(db);
    plans = ReviewPlanRepository(db, anki);
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

  /// A knowledge point filed under [tagId], with a blankable sentence so the
  /// review engine can derive a unit from it.
  Future<KnowledgePoint> pointIn(String tagId, String title) async {
    final point = await anki.createKnowledgePoint(
      title: title,
      content: '$title在系统不受外力时守恒。',
    );
    await tags.addTagToObject(
      tagId: tagId,
      objectType: 'knowledge_point',
      objectId: point.id,
    );
    return point;
  }

  Future<void> logReviewAt(String knowledgePointId, DateTime when) async {
    final state =
        await anki.getOrCreateUnitCardState(knowledgePointId, 'cloze:s1');
    await anki.addReviewLog(
      cardStateId: state.id,
      cardTemplateId: state.unitKey ?? 'unit',
      rating: 2,
      reviewedAt: when.millisecondsSinceEpoch,
      correct: 1,
      judgeMode: 'auto',
    );
  }

  /// Makes [knowledgePointId] material the group already had: introduced
  /// yesterday (so today's answers count as reviews) and due again today.
  Future<void> makeOldMaterial(String knowledgePointId) async {
    final state =
        await anki.getOrCreateUnitCardState(knowledgePointId, 'cloze:s1');
    await anki.updateUnitCardState(
      state.id,
      dueAt: moment.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      repetitions: 2,
      lastReviewedAt:
          moment.subtract(const Duration(days: 3)).millisecondsSinceEpoch,
    );
    await logReviewAt(
      knowledgePointId,
      moment.subtract(const Duration(days: 1)),
    );
  }

  Future<List<ReviewItem>> queueFor({ReviewDayLoad? plan}) =>
      service.buildQueue(now: moment, plan: plan);

  test('the new-card allowance caps how many new cards enter the day',
      () async {
    final tag = await tags.createTag(name: '语文');
    await pointIn(tag.id, '动量');
    await pointIn(tag.id, '冲量');
    await pointIn(tag.id, '动能');

    await plans.setGroupPlan(
      tagId: tag.id,
      newCardsPerDay: 1,
      reviewCardsPerDay: 5,
    );
    final load = await plans.loadDay(now: moment);
    expect(load.groups.single.newRemaining, 1);

    final queue = await queueFor(plan: load);
    expect(queue, hasLength(1),
        reason: 'one new card a day means one card, not the library');
    expect(queue.single.isNew, isTrue);
  });

  test('the review allowance caps how many due reviews enter the day',
      () async {
    final tag = await tags.createTag(name: '数学');
    final x = await pointIn(tag.id, '函数');
    final y = await pointIn(tag.id, '导数');
    await makeOldMaterial(x.id);
    await makeOldMaterial(y.id);

    await plans.setGroupPlan(
      tagId: tag.id,
      newCardsPerDay: 0,
      reviewCardsPerDay: 1,
    );
    final load = await plans.loadDay(now: moment);
    expect(load.groups.single.remainingReviews, 1);

    final queue = await queueFor(plan: load);
    expect(queue, hasLength(1),
        reason: 'one review a day means one card, not every due card');
    expect([x.id, y.id], contains(queue.single.knowledgePointId));
  });

  test('zero new cards a day means no new cards today', () async {
    final tag = await tags.createTag(name: '物理');
    final fresh = await pointIn(tag.id, '功');
    final old = await pointIn(tag.id, '功率');
    await makeOldMaterial(old.id);

    await plans.setGroupPlan(
      tagId: tag.id,
      newCardsPerDay: 0,
      reviewCardsPerDay: 5,
    );
    final load = await plans.loadDay(now: moment);
    final queue = await queueFor(plan: load);
    final ids = {for (final item in queue) item.knowledgePointId};
    expect(ids, contains(old.id));
    expect(ids, isNot(contains(fresh.id)),
        reason: '0 is a real "none", not "unlimited"');
  });

  test('a wrong answer still comes back with both allowances spent', () async {
    final tag = await tags.createTag(name: '化学');
    final wrong = await pointIn(tag.id, '水');
    final unseen = await pointIn(tag.id, '氧气');

    // Material the group already had, so today's answer is a review rather than
    // a new card; answering it wrong binds it to reappear today (annotation 17).
    await makeOldMaterial(wrong.id);
    // Before any plan exists both the due review and the group's new material are
    // drawn; that is what makes the assertions below mean something.
    final firstQueue = await queueFor();
    expect(
      {for (final item in firstQueue) item.knowledgePointId},
      {wrong.id, unseen.id},
    );
    final item = firstQueue.firstWhere((e) => e.knowledgePointId == wrong.id);
    final outcome = await service.grade(
      item: item,
      correct: false,
      rating: FsrsRating.again,
      now: moment,
    );
    expect(outcome.stillForced, isTrue,
        reason: 'a wrong answer is pinned to today\'s queue');

    // Both buckets are now empty: no new cards, and the review allowance (1) was
    // spent by the answer above.
    await plans.setGroupPlan(
      tagId: tag.id,
      newCardsPerDay: 0,
      reviewCardsPerDay: 1,
    );
    final load = await plans.loadDay(now: moment);
    expect(load.groups.single.remainingReviews, 0);
    expect(load.groups.single.newRemaining, 0);
    expect(load.reviewExhaustedGroups, contains(tag.id));

    final queue = await queueFor(plan: load);
    final ids = [for (final entry in queue) entry.knowledgePointId];
    expect(ids, contains(wrong.id),
        reason: 'the forced retry is exempt from the allowances, by design');
    expect(
      queue.firstWhere((e) => e.knowledgePointId == wrong.id).cardState.forced,
      1,
    );
    expect(ids, isNot(contains(unseen.id)),
        reason: 'the new-card allowance is zero, so the new card waits');
  });

  test('a card in no configured group stays unlimited', () async {
    final configured = await tags.createTag(name: '语文');
    final other = await tags.createTag(name: '地理');
    final inside = await pointIn(configured.id, '动量');
    final outside = await pointIn(other.id, '气候');

    await plans.setGroupPlan(
      tagId: configured.id,
      newCardsPerDay: 0,
      reviewCardsPerDay: 5,
    );
    final load = await plans.loadDay(now: moment);
    final queue = await queueFor(plan: load);
    final ids = {for (final item in queue) item.knowledgePointId};
    expect(ids, isNot(contains(inside.id)),
        reason: 'the configured group asked for no new cards');
    expect(ids, contains(outside.id),
        reason: 'a plan must not hide material the user never filed anywhere');
  });

  test('with nothing configured the queue is drawn exactly as before',
      () async {
    final tag = await tags.createTag(name: '历史');
    final point = await pointIn(tag.id, '水');
    await logReviewAt(point.id, moment);

    // No target at all: the "first-run user" case.
    expect((await plans.loadDay(now: moment)).isEmpty, isTrue);

    // Both call shapes must agree: an explicit empty load and the pre-plan
    // signature with no plan argument at all.
    final withEmptyPlan = {
      for (final item in await queueFor(plan: await plans.loadDay(now: moment)))
        item.knowledgePointId,
    };
    final withoutPlan = {
      for (final item in await queueFor()) item.knowledgePointId,
    };
    expect(withEmptyPlan, contains(point.id), reason: 'no target means no cap');
    expect(withoutPlan, withEmptyPlan,
        reason: 'the plan argument is additive, never a behaviour change');
  });
}
