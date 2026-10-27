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

/// The queue's card-group scope (user m20816): a deck is a tag subtree, so
/// "review only this deck" means "only knowledge points carrying a tag path
/// inside that subtree" - and "review the ungrouped ones" means the opposite.
///
/// The load-bearing claims:
///
///  * the filter is applied to the knowledge point, before any card is built,
///    so a scoped queue can be exactly empty without falling back to the whole
///    library;
///  * a forced (answered-wrong-today) card obeys the same scope - it does not
///    leak into another deck's queue;
///  * ungrouped cards are the ones no configured group's tag paths cover, and
///    they are not blocked by a group's daily allowance;
///  * with no scope arguments the queue is the old, global one.
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

  Future<KnowledgePoint> makePoint(
    String title,
    String content, {
    Tag? tag,
  }) async {
    final point = await anki.createKnowledgePoint(
      title: title,
      content: content,
    );
    if (tag != null) {
      await tags.addTagToObject(
        tagId: tag.id,
        objectType: 'knowledge_point',
        objectId: point.id,
      );
    }
    return point;
  }

  CardGroupPlan planFor(
    Tag tag, {
    int newCardsPerDay = 5,
    int reviewCardsPerDay = 3,
  }) =>
      CardGroupPlan(
        id: 'rgp::${tag.id}',
        tagId: tag.id,
        tagPath: tag.path ?? tag.name,
        newCardsPerDay: newCardsPerDay,
        reviewCardsPerDay: reviewCardsPerDay,
      );

  ReviewGroupLoad groupFor(
    CardGroupPlan plan, {
    int newRemaining = 5,
    int? remainingReviews,
  }) =>
      ReviewGroupLoad(
        plan: plan,
        memberPaths: [plan.tagPath],
        alreadyDoneToday: 0,
        newDoneToday: 0,
        reviewDoneToday: 0,
        newRemaining: newRemaining,
        remainingReviews: remainingReviews,
      );

  ReviewDayLoad dayFor(List<ReviewGroupLoad> groups) {
    return ReviewDayLoad(
      dayStart: DateTime(2026, 10, 27),
      groups: groups,
      pathsByGroup: {
        for (final group in groups) group.plan.tagId: group.memberPaths,
      },
    );
  }

  final emptyDay = ReviewDayLoad.empty(dayStart: DateTime(2026, 10, 27));

  List<String> pointIds(List<ReviewItem> queue) => [
        for (final item in queue) item.knowledgePointId,
      ];

  group('onlyPaths：按卡组标签子树过滤', () {
    test('只出命中该卡组的卡', () async {
      final math = await tags.createTag(name: '数学');
      final physics = await tags.createTag(name: '物理');
      final mathPoint = await makePoint(
        '函数单调性',
        '函数在区间上是单调递增的。',
        tag: math,
      );
      final physicsPoint = await makePoint(
        '自由落体',
        '自由落体运动的加速度是重力加速度。',
        tag: physics,
      );

      final queue = await service.buildQueue(
        plan: emptyDay,
        onlyPaths: {math.path!},
      );

      expect(pointIds(queue), [mathPoint.id]);
      expect(pointIds(queue), isNot(contains(physicsPoint.id)));
    });

    test('同时给两个卡组：两组都出', () async {
      final math = await tags.createTag(name: '数学');
      final physics = await tags.createTag(name: '物理');
      final mathPoint = await makePoint(
        '函数单调性',
        '函数在区间上是单调递增的。',
        tag: math,
      );
      final physicsPoint = await makePoint(
        '自由落体',
        '自由落体运动的加速度是重力加速度。',
        tag: physics,
      );

      final queue = await service.buildQueue(
        plan: emptyDay,
        onlyPaths: {math.path!, physics.path!},
      );

      expect(pointIds(queue).toSet(), {mathPoint.id, physicsPoint.id});
    });

    test('空集是「这一组今天没卡」，不是「回退到全部」', () async {
      await makePoint('函数单调性', '函数在区间上是单调递增的。');

      final queue = await service.buildQueue(
        plan: emptyDay,
        onlyPaths: <String>{},
      );

      expect(queue, isEmpty);
    });

    test('卡组里没有任何卡时返回空队列且不抛异常', () async {
      await makePoint('函数单调性', '函数在区间上是单调递增的。');

      final queue = await service.buildQueue(
        plan: emptyDay,
        onlyPaths: {'一个不存在的标签'}.toSet(),
      );

      expect(queue, isEmpty);
    });

    test('今日答错的卡跟着它自己的卡组走，不串组', () async {
      final math = await tags.createTag(name: '数学');
      final physics = await tags.createTag(name: '物理');
      final mathPoint = await makePoint(
        '函数单调性',
        '函数在区间上是单调递增的。',
        tag: math,
      );
      await makePoint(
        '自由落体',
        '自由落体运动的加速度是重力加速度。',
        tag: physics,
      );

      final item = (await service.buildQueue()).firstWhere(
        (entry) => entry.knowledgePointId == mathPoint.id,
      );
      final outcome = await service.grade(
        item: item,
        correct: false,
        rating: FsrsRating.good,
        submitted: '答错了',
      );
      expect(outcome.stillForced, isTrue);

      final mathQueue = await service.buildQueue(
        plan: emptyDay,
        onlyPaths: {math.path!},
      );
      expect(mathQueue, hasLength(1));
      expect(mathQueue.single.knowledgePointId, mathPoint.id);

      final physicsQueue = await service.buildQueue(
        plan: emptyDay,
        onlyPaths: {physics.path!},
      );
      expect(
        pointIds(physicsQueue),
        isNot(contains(mathPoint.id)),
        reason: '数学的错题不许出现在物理卡组里',
      );
    });
  });

  group('onlyUngrouped：只出没被任何卡组覆盖的卡', () {
    test('排除组内卡，留下没打标签的卡', () async {
      final math = await tags.createTag(name: '数学');
      final mathPoint = await makePoint(
        '函数单调性',
        '函数在区间上是单调递增的。',
        tag: math,
      );
      final loose = await makePoint(
        '细胞呼吸',
        '细胞呼吸的主要场所是线粒体。',
      );
      final plan = planFor(math);
      final day = dayFor([groupFor(plan)]);

      final queue = await service.buildQueue(plan: day, onlyUngrouped: true);

      expect(pointIds(queue), [loose.id]);
      expect(pointIds(queue), isNot(contains(mathPoint.id)));
    });

    test('一个卡组都没配置时，所有卡都算未分组', () async {
      final first = await makePoint(
        '函数单调性',
        '函数在区间上是单调递增的。',
      );
      final second = await makePoint(
        '细胞呼吸',
        '细胞呼吸的主要场所是线粒体。',
      );

      final queue = await service.buildQueue(
        plan: emptyDay,
        onlyUngrouped: true,
      );

      expect(pointIds(queue).toSet(), {first.id, second.id});
    });

    test('没标签的卡不受任何卡组每日上限限制', () async {
      final math = await tags.createTag(name: '数学');
      await makePoint(
        '函数单调性',
        '函数在区间上是单调递增的。',
        tag: math,
      );
      final loose = await makePoint(
        '细胞呼吸',
        '细胞呼吸的主要场所是线粒体。',
      );
      final plan = planFor(math);
      // 这一组今天的新卡额度已经用完：组内的卡进不了队列，但未分组的卡
      // 不属于任何额度，不能被别人的上限连坐。
      final day = dayFor([
        groupFor(plan, newRemaining: 0, remainingReviews: 0),
      ]);

      final queue = await service.buildQueue(plan: day, onlyUngrouped: true);

      expect(pointIds(queue), [loose.id]);
    });
  });

  group('默认行为不变', () {
    test('两个 scope 参数都不传时，队列还是全库队列', () async {
      final math = await tags.createTag(name: '数学');
      final loose = await makePoint(
        '细胞呼吸',
        '细胞呼吸的主要场所是线粒体。',
      );
      final mathPoint = await makePoint(
        '函数单调性',
        '函数在区间上是单调递增的。',
        tag: math,
      );

      final queue = await service.buildQueue();

      expect(pointIds(queue).toSet(), {mathPoint.id, loose.id});
    });

    test('scope 内仍然受该卡组的每日额度约束', () async {
      final math = await tags.createTag(name: '数学');
      await makePoint(
        '函数单调性',
        '函数在区间上是单调递增的。',
        tag: math,
      );
      final plan = planFor(math);
      final day = dayFor([groupFor(plan, newRemaining: 0)]);

      final queue = await service.buildQueue(
        plan: day,
        onlyPaths: {math.path!},
      );

      expect(
        queue,
        isEmpty,
        reason: '只看这一组也绕不过这一组的每日新卡上限',
      );
    });
  });
}
