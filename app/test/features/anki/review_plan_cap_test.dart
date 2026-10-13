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

/// The per-group daily plan's single enforcement rule:
///
/// > once a group's daily **review** allowance is used up, that group stops
/// > drawing **new** cards for today - and a card answered wrong today still
/// > comes back, always.
///
/// The three cases below pin that down from both sides: the cap must bite on a
/// brand-new card, it must not bite on a unit that already has a schedule, and
/// the wrong-answer return (annotation 17) must survive an exhausted allowance.
/// The fourth case is the other half of the contract: with nothing configured
/// the queue is built exactly as it was before the plan existed.
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

  Future<void> logReviewToday(String knowledgePointId) async {
    final state = await anki.getOrCreateUnitCardState(knowledgePointId, 'cloze:s1');
    await anki.addReviewLog(
      cardStateId: state.id,
      cardTemplateId: state.unitKey ?? 'unit',
      rating: 2,
      reviewedAt: moment.millisecondsSinceEpoch,
      correct: 1,
      judgeMode: 'auto',
    );
  }

  Future<Set<String>> queuedIds({ReviewDayLoad? plan}) async {
    final queue = await service.buildQueue(now: moment, plan: plan);
    return {for (final item in queue) item.knowledgePointId};
  }

  test('an exhausted group stops drawing new cards', () async {
    final tag = await tags.createTag(name: '语文');
    final reviewed = await pointIn(tag.id, '动量');
    final unseen = await pointIn(tag.id, '冲量');

    // Give the first card a history and log today's review, which is what the
    // plan counts; the second card is deliberately untouched.
    final state = await anki.getOrCreateUnitCardState(reviewed.id, 'cloze:s1');
    await anki.updateUnitCardState(
      state.id,
      dueAt: moment.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      repetitions: 2,
      lastReviewedAt: moment.subtract(const Duration(days: 3)).millisecondsSinceEpoch,
    );
    await logReviewToday(reviewed.id);

    await plans.setGroupPlan(
      tagId: tag.id,
      newCardsPerDay: 10,
      reviewCardsPerDay: 1,
    );
    final load = await plans.loadDay(now: moment);
    expect(load.reviewExhaustedGroups, contains(tag.id),
        reason: 'the one allowed review has happened');

    final ids = await queuedIds(plan: load);
    expect(ids, contains(reviewed.id),
        reason: 'the card that is due is an ordinary review, not a new card');
    expect(ids, isNot(contains(unseen.id)),
        reason: 'a card this group has never shown must not be drawn');
    expect(
      await anki.unitStatesForKnowledgePoint(unseen.id),
      isEmpty,
      reason: 'the cap blocks the card before any state is created for it',
    );
  });

  test('a wrong answer still comes back with the allowance used up', () async {
    final tag = await tags.createTag(name: '数学');
    final wrong = await pointIn(tag.id, '函数');
    final unseen = await pointIn(tag.id, '导数');

    // Answer the first card wrong: that binds it to reappear inside today's
    // queue (annotation 17), and this is the rule the cap must never touch.
    final wrongState =
        await anki.getOrCreateUnitCardState(wrong.id, 'cloze:s1');
    await anki.updateUnitCardState(
      wrongState.id,
      dueAt: moment.millisecondsSinceEpoch,
      repetitions: 1,
      lastReviewedAt: moment.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch,
    );
    // The queue before any cap exists: the newly-bound card and the group's new
    // material are both drawn. That 导数 is present here is what makes the
    // assertion further down ("the cap holds it back") mean something.
    final firstQueue = await service.buildQueue(now: moment);
    expect(
      {for (final entry in firstQueue) entry.knowledgePointId},
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

    // The day's allowance is now spent (the wrong answer itself is the review).
    await plans.setGroupPlan(
      tagId: tag.id,
      newCardsPerDay: 10,
      reviewCardsPerDay: 1,
    );
    final load = await plans.loadDay(now: moment);
    expect(load.reviewExhaustedGroups, contains(tag.id));

    final queue = await service.buildQueue(now: moment, plan: load);
    final ids = [for (final entry in queue) entry.knowledgePointId];
    expect(ids, contains(wrong.id),
        reason: 'the forced retry is exempt from the cap, by design');
    expect(queue.firstWhere((e) => e.knowledgePointId == wrong.id).cardState.forced,
        1);
    expect(ids, isNot(contains(unseen.id)),
        reason: 'the cap still holds back the new card');
  });

  test('a group under its allowance keeps drawing new cards', () async {
    final tag = await tags.createTag(name: '物理');
    final first = await pointIn(tag.id, '功');
    final second = await pointIn(tag.id, '功率');

    await logReviewToday(first.id);
    await plans.setGroupPlan(
      tagId: tag.id,
      newCardsPerDay: 10,
      reviewCardsPerDay: 5,
    );

    final load = await plans.loadDay(now: moment);
    expect(load.groups.single.newCardsAllowed, isTrue);
    final ids = await queuedIds(plan: load);
    expect(ids, contains(second.id),
        reason: 'one review out of five does not stop the group');
  });

  test('with nothing configured the queue is drawn exactly as before', () async {
    final tag = await tags.createTag(name: '化学');
    final point = await pointIn(tag.id, '水');
    await logReviewToday(point.id);

    // No target at all: the "first-run user" case.
    expect((await plans.loadDay(now: moment)).isEmpty, isTrue);

    // Both call shapes must agree: an explicit empty load and the pre-plan
    // signature with no plan argument at all.
    final withEmptyPlan = await queuedIds(
      plan: await plans.loadDay(now: moment),
    );
    final withoutPlan = await queuedIds();
    expect(withEmptyPlan, contains(point.id),
        reason: 'no target means no cap');
    expect(withoutPlan, withEmptyPlan,
        reason: 'the plan argument is additive, never a behaviour change');
  });
}
