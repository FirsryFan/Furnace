import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/review_plan_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/features/anki/application/card_type_preference.dart';
import 'package:furnace/features/anki/application/judge_mode_preference.dart';

/// Persistence of the two review preferences and of a group's daily target,
/// plus the plan-vs-actual arithmetic the plan screen and the queue both read.
///
/// The load-bearing claims here are:
///
///  * a **group is a tag together with its subtree** - a card filed under
///    `语文/作文` counts for the `语文` group, a card under `语文/现代文` counts for
///    it too, and a card under a sibling tag (`数学`) does not;
///  * **nothing configured means no limit**, which is what keeps a first-run
///    user from silently losing cards;
///  * a new card is a point whose **first review ever** happened today, and those
///    answers do not also eat the review allowance - they are not reviews of
///    material the group already had;
///  * a review target of 0 means *unlimited*, not "no reviews", because 0 is the
///    column default and a brand-new row must not stop reviews.
void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late TagRepository tags;
  late ReviewPlanRepository plans;

  /// A fixed clock, so "today" is a constant in every assertion.
  final moment = DateTime(2026, 10, 12, 20, 30);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    tags = TagRepository(db);
    plans = ReviewPlanRepository(db, anki);
  });

  tearDown(() async {
    await db.close();
  });

  /// The unit state of a knowledge point, created if the review engine or the
  /// queue has not made one yet.
  Future<CardState> unitState(String knowledgePointId) =>
      anki.getOrCreateUnitCardState(knowledgePointId, 'cloze:s1');

  Future<void> logReview({
    required String knowledgePointId,
    required DateTime when,
  }) async {
    final state = await unitState(knowledgePointId);
    await anki.addReviewLog(
      cardStateId: state.id,
      cardTemplateId: state.unitKey ?? 'unit',
      rating: 2,
      reviewedAt: when.millisecondsSinceEpoch,
      correct: 1,
      judgeMode: 'auto',
    );
  }

  group('review preferences round-trip', () {
    test('an unset preference is today\'s behaviour, not a stored default',
        () async {
      // No settings row and no preference row at all: the first-run case.
      expect(await plans.getJudgeModePreference(), JudgeModePreference.strict);
      expect(await plans.getCardTypePreference(), CardTypePreference.mixed);
    });

    test(
        'a chosen judging mode survives a re-read and creates the settings row',
        () async {
      expect(await db.select(db.localSettings).get(), isEmpty);

      await plans.setJudgeModePreference(JudgeModePreference.lenient);

      expect(await plans.getJudgeModePreference(), JudgeModePreference.lenient);
      expect((await db.select(db.localSettings).get()).single.ankiJudgeMode,
          'lenient');
      // The other preference is still unset: one write must not touch it.
      expect(await plans.getCardTypePreference(), CardTypePreference.mixed);
    });

    test('a chosen card type preference survives a re-read', () async {
      await plans.setCardTypePreference(CardTypePreference.mcq);
      expect(await plans.getCardTypePreference(), CardTypePreference.mcq);
      expect(await plans.getJudgeModePreference(), JudgeModePreference.strict);

      final both = await plans.getPreferences();
      expect(both.cardType, CardTypePreference.mcq);
      expect(both.judgeMode, JudgeModePreference.strict);

      // Choosing again overwrites rather than appending a second meaning.
      await plans.setCardTypePreference(CardTypePreference.essay);
      expect(await plans.getCardTypePreference(), CardTypePreference.essay);
    });

    test('the stored wire values are the documented ones', () async {
      // Spelled out rather than derived from Enum.name: an already-written
      // setting must keep meaning the same thing after a rename.
      await plans.setCardTypePreference(CardTypePreference.fillBlankLenient);
      final row = (await db.select(db.localSettings).get()).single;
      expect(row.ankiCardTypePreference, 'fill_blank_lenient');
      expect(CardTypePreference.fromStorage('fill_blank_lenient'),
          CardTypePreference.fillBlankLenient);
      expect(CardTypePreference.fromStorage('fill_blank'),
          CardTypePreference.fillBlank);
      expect(CardTypePreference.fromStorage('essay'), CardTypePreference.essay);
      // Unknown or missing means the shipped default, i.e. today's behaviour.
      expect(CardTypePreference.fromStorage(null), CardTypePreference.mixed);
      expect(
          CardTypePreference.fromStorage('quantum'), CardTypePreference.mixed);
      expect(JudgeModePreference.fromStorage(null), JudgeModePreference.strict);
      expect(JudgeModePreference.fromStorage('self'), JudgeModePreference.self);
      expect(JudgeModePreference.fromStorage('nonsense'),
          JudgeModePreference.strict,
          reason: 'an unknown mode must not become the forgiving one');
    });
  });

  group('a group is a tag and its subtree', () {
    test('membership counts the tag itself and every tag under it', () async {
      final chinese = await tags.createTag(name: '语文');
      final composition =
          await tags.createTag(name: '作文', parentId: chinese.id);
      final modern = await tags.createTag(name: '现代文', parentId: chinese.id);
      final math = await tags.createTag(name: '数学');

      final a = await anki.createKnowledgePoint(title: 'A', content: 'A 的内容。');
      final b = await anki.createKnowledgePoint(title: 'B', content: 'B 的内容。');
      final c = await anki.createKnowledgePoint(title: 'C', content: 'C 的内容。');
      final outside =
          await anki.createKnowledgePoint(title: 'D', content: 'D 的内容。');
      for (final link in [
        (a, chinese),
        (b, composition),
        (c, modern),
        (outside, math),
      ]) {
        await tags.addTagToObject(
          tagId: link.$2.id,
          objectType: 'knowledge_point',
          objectId: link.$1.id,
        );
      }

      await plans.setGroupPlan(
        tagId: chinese.id,
        newCardsPerDay: 10,
        reviewCardsPerDay: 20,
      );
      await plans.setGroupPlan(
        tagId: composition.id,
        newCardsPerDay: 5,
        reviewCardsPerDay: 5,
      );
      await plans.setGroupPlan(
        tagId: math.id,
        newCardsPerDay: 1,
        reviewCardsPerDay: 1,
      );

      // One review each, all of them today.
      for (final point in [a, b, c, outside]) {
        await logReview(knowledgePointId: point.id, when: moment);
      }

      final load = await plans.loadDay(now: moment);
      final byTag = {
        for (final group in load.groups) group.plan.tagId: group,
      };

      expect(byTag[chinese.id]!.alreadyDoneToday, 3,
          reason: '语文 itself plus both children');
      expect(byTag[composition.id]!.alreadyDoneToday, 1,
          reason: 'only the card filed directly under 作文');
      expect(byTag[math.id]!.alreadyDoneToday, 1,
          reason: '数学 is a sibling subtree, not part of 语文');
      // All three points were answered for the first time today, so they spend
      // the new-card allowance and not the review allowance.
      expect(byTag[chinese.id]!.newDoneToday, 3);
      expect(byTag[chinese.id]!.reviewDoneToday, 0);
      expect(byTag[chinese.id]!.newRemaining, 7);
      expect(byTag[chinese.id]!.remainingReviews, 20);
      expect(byTag[chinese.id]!.newCardsAllowed, isTrue);
    });

    test('a review logged yesterday does not count towards today', () async {
      final tag = await tags.createTag(name: '物理');
      final point = await anki.createKnowledgePoint(
        title: '动量',
        content: '动量守恒。',
      );
      await tags.addTagToObject(
        tagId: tag.id,
        objectType: 'knowledge_point',
        objectId: point.id,
      );
      await plans.setGroupPlan(
        tagId: tag.id,
        newCardsPerDay: 10,
        reviewCardsPerDay: 5,
      );
      await logReview(
        knowledgePointId: point.id,
        when: moment.subtract(const Duration(days: 1)),
      );

      final load = await plans.loadDay(now: moment);
      expect(load.groups.single.alreadyDoneToday, 0,
          reason: 'the allowance is per local calendar day');
      expect(load.groups.single.newDoneToday, 0);
      expect(load.groups.single.newRemaining, 10);
      expect(load.groups.single.remainingReviews, 5);
      expect(load.groups.single.newCardsAllowed, isTrue);
    });

    test(
        'material from an earlier day spends the review allowance, not the '
        'new-card one', () async {
      final tag = await tags.createTag(name: '生物');
      final point = await anki.createKnowledgePoint(
        title: '细胞',
        content: '细胞是基本单位。',
      );
      await tags.addTagToObject(
        tagId: tag.id,
        objectType: 'knowledge_point',
        objectId: point.id,
      );
      await plans.setGroupPlan(
        tagId: tag.id,
        newCardsPerDay: 10,
        reviewCardsPerDay: 2,
      );
      // Introduced yesterday, so today's answers are reviews of old material.
      await logReview(
        knowledgePointId: point.id,
        when: moment.subtract(const Duration(days: 1)),
      );
      await logReview(knowledgePointId: point.id, when: moment);
      await logReview(knowledgePointId: point.id, when: moment);

      final load = await plans.loadDay(now: moment);
      final group = load.groups.single;
      expect(group.alreadyDoneToday, 2);
      expect(group.newDoneToday, 0);
      expect(group.reviewDoneToday, 2);
      expect(group.newRemaining, 10);
      expect(group.remainingReviews, 0);
      expect(load.reviewExhaustedGroups, contains(tag.id));
    });

    test('a zero review target means unlimited, not "no reviews"', () async {
      final tag = await tags.createTag(name: '化学');
      final point = await anki.createKnowledgePoint(
        title: '水',
        content: '水由氢和氧组成。',
      );
      await tags.addTagToObject(
        tagId: tag.id,
        objectType: 'knowledge_point',
        objectId: point.id,
      );
      // Only a new-card number: the review field is left at its 0 default.
      await plans.setGroupPlan(
        tagId: tag.id,
        newCardsPerDay: 3,
        reviewCardsPerDay: 0,
      );
      await logReview(knowledgePointId: point.id, when: moment);
      await logReview(knowledgePointId: point.id, when: moment);
      await logReview(knowledgePointId: point.id, when: moment);

      final load = await plans.loadDay(now: moment);
      expect(load.groups.single.remainingReviews, isNull);
      expect(load.groups.single.newDoneToday, 1,
          reason: 'three answers to the same card are still one new card');
      expect(load.groups.single.newRemaining, 2);
      expect(load.groups.single.newCardsAllowed, isTrue,
          reason:
              '0 is the column default, so it cannot mean "stop reviewing"');
      expect(load.reviewExhaustedGroups, isEmpty);
    });

    test('nothing configured loads empty and reports no cap', () async {
      final load = await plans.loadDay(now: moment);
      expect(load.isEmpty, isTrue);
      expect(load.groups, isEmpty);
      expect(load.reviewExhaustedGroups, isEmpty);
    });

    test('clearing a target returns the group to unlimited', () async {
      final tag = await tags.createTag(name: '历史');
      await plans.setGroupPlan(
        tagId: tag.id,
        newCardsPerDay: 2,
        reviewCardsPerDay: 2,
      );
      expect(await plans.groupPlans(), hasLength(1));

      await plans.clearGroupPlan(tag.id);

      expect(await plans.groupPlans(), isEmpty,
          reason: 'a cleared target is absent, not zero');
    });
  });
}
