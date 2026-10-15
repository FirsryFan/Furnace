import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/thread_rank_repository.dart';
import 'package:furnace/data/repositories/thread_state_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/domain/services/cloze/diffusion_boost.dart';
import 'package:furnace/domain/services/scheduling/cognitive_rank.dart';
import 'package:furnace/domain/services/scheduling/cognitive_rank_inputs.dart';
import 'package:furnace/domain/services/scheduling/domain_balance.dart';
import 'package:furnace/domain/services/scheduling/thread_balance_inputs.dart';
import 'package:furnace/features/thread/application/thread_rank_service.dart';

/// 认知排序档位接进 `ThreadRankService`（roadmap §2-D 的另一半，Q29d）。
///
/// 这一档只重排段落 B 已经排好的候选，所以用例都锁"相对位置"：
/// 先跑一次开关关着的排序拿到基准次序，再断言被注入读数的那条任务动了、动的方向对、
/// 理由行说得清。基准次序由段落 B 自己决定，用例不假设它是什么——只假设它稳定。
void main() {
  late AppDatabase db;
  late ThreadRankService service;
  late TaskRepository tasks;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tasks = TaskRepository(db);
    service = ThreadRankService(
      taskRepository: tasks,
      timeBlockRepository: TimeBlockRepository(db),
      tagRepository: TagRepository(db),
      threadRankRepository: ThreadRankRepository(db),
      threadStateRepository: ThreadStateRepository(db),
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// 两条都排得进今天、都没有截止时间：认知档位是它们之间唯一的差别。
  Future<(Task, Task)> twoTasks() async {
    final a = await tasks.createTask(title: '甲', estimateMinutes: 15);
    final b = await tasks.createTask(title: '乙', estimateMinutes: 15);
    return (a, b);
  }

  ThreadBalanceInputs inputsFor(Task a, Task b,
      {List<KnowledgePointReading> readings = const []}) {
    return ThreadBalanceInputs(
      taskKnowledgePoints: {
        a.id: const ['kp-a'],
        b.id: const ['kp-b'],
      },
      readings: readings,
    );
  }

  test('开关关着：认知档位完全不产出，次序就是原来的', () async {
    final (a, b) = await twoTasks();
    final balance = inputsFor(a, b);

    final feed = await service.build(balance: balance);

    expect(feed.cognitiveRank, isNull);
    expect(feed.cognitiveFor(a.id), isNull);
    expect(feed.cognitiveReasonFor(a.id), isNull);
    expect(feed.readyTasks.map((t) => t.id).toSet(), {a.id, b.id});
  });

  test('开着但什么都不知道：一个都不动，理由行如实说没有读数', () async {
    final (a, b) = await twoTasks();
    final balance = inputsFor(a, b);

    final off = await service.build(balance: balance);
    final on = await service.build(
      balance: balance,
      cognitiveRankEnabled: true,
      cognitiveSeed: CognitiveRankSeed.empty,
    );

    expect(on.cognitiveRank, isNotNull);
    expect(on.readyTasks.map((t) => t.id).toList(),
        off.readyTasks.map((t) => t.id).toList(),
        reason: '没有起点就没有 origin，分数全是 1.0，次序原样');
    for (final id in [a.id, b.id]) {
      final hit = on.cognitiveFor(id)!;
      expect(hit.score, 1.0);
      expect(hit.movedUp, isFalse);
      expect(hit.origin, isNull);
      expect(hit.reasonZh, contains('没有认知读数'));
      expect(CognitiveRankHit.uncalibrated, isTrue, reason: '加成未标定，必须自己说出来');
    }
  });

  test('刚复习过的知识点把那条任务提到最前（0 跳 ×1.6）', () async {
    final (a, b) = await twoTasks();
    final balance = inputsFor(a, b);

    // 基准次序（开关关着）决定"谁原来在后面"——用例不假设段落 B 怎么排。
    final off = await service.build(balance: balance);
    final baseOrder = off.readyTasks.map((t) => t.id).toList();
    expect(baseOrder.length, 2);
    final behind = baseOrder.last;
    final activeKp = behind == a.id ? 'kp-a' : 'kp-b';

    final on = await service.build(
      balance: balance,
      cognitiveRankEnabled: true,
      cognitiveSeed: CognitiveRankSeed(
        availability: 1,
        tagNodes: const [
          MindNodeInfo(id: 'tag-a', parentId: null),
          MindNodeInfo(id: 'tag-b', parentId: null),
        ],
        activeKnowledgePointIds: [activeKp],
        knowledgePointTagIds: const {
          'kp-a': ['tag-a'],
          'kp-b': ['tag-b'],
        },
      ),
    );

    final hit = on.cognitiveFor(behind)!;
    expect(on.readyTasks.first.id, behind);
    expect(hit.reachability, kCognitiveRankDistance0Boost);
    expect(hit.movedUp, isTrue, reason: '它原来是第二个，现在在最前');
    expect(hit.origin!.link, CognitiveRankLink.activity);
    expect(hit.reasonZh, contains('刚活动过'));
  });

  test('离当前目标一跳的知识点给 ×1.3，够不着的什么都不给', () async {
    final (a, b) = await twoTasks();
    final balance = inputsFor(a, b);

    final off = await service.build(balance: balance);
    final behind = off.readyTasks.map((t) => t.id).toList().last;
    final liftedKp = behind == a.id ? 'kp-a' : 'kp-b';
    final detachedKp = behind == a.id ? 'kp-b' : 'kp-a';

    final on = await service.build(
      balance: balance,
      cognitiveRankEnabled: true,
      cognitiveSeed: CognitiveRankSeed(
        availability: 1,
        // 目标 = 物理，力学是它的孩子；另一条任务的知识点挂在一张不在图里的标签上。
        tagNodes: const [
          MindNodeInfo(id: 'physics', parentId: null),
          MindNodeInfo(id: 'mechanics', parentId: 'physics'),
        ],
        goalNodeId: 'physics',
        knowledgePointTagIds: {
          liftedKp: const ['mechanics'],
          detachedKp: const ['nowhere'],
        },
      ),
    );

    final hit = on.cognitiveFor(behind)!;
    expect(on.readyTasks.first.id, behind);
    expect(hit.reachability, kCognitiveRankDistance1Boost);
    expect(hit.origin!.hops, 1);
    expect(hit.origin!.link, CognitiveRankLink.goal);
    expect(hit.reasonZh, contains('离目标'));

    final other = on.readyTasks.last.id;
    expect(on.cognitiveFor(other)!.origin, isNull,
        reason: '挂在图外的知识点：够不着就不猜一条近路');
  });

  test('难度代理取最弱的那块编码上限，且只认置信度 > 0 的先验', () async {
    final (a, b) = await twoTasks();
    // 甲挂两个知识点：一个编码上限 0.9（强）、一个 0.2（弱）⇒ 难度 = 0.8；
    // 乙的先验置信度是 0（"只是先验，不参与加权"）⇒ 没有难度读数。
    final balance = ThreadBalanceInputs(
      taskKnowledgePoints: {
        a.id: const ['kp-strong', 'kp-weak'],
        b.id: const ['kp-unbelief'],
      },
      readings: const [
        KnowledgePointReading(
          knowledgePointId: 'kp-strong',
          priorR0: 0.9,
          priorConfidence: 1,
        ),
        KnowledgePointReading(
          knowledgePointId: 'kp-weak',
          priorR0: 0.2,
          priorConfidence: 1,
        ),
        KnowledgePointReading(
          knowledgePointId: 'kp-unbelief',
          priorR0: 0.2,
          priorConfidence: 0,
        ),
      ],
    );

    final off = await service.build(balance: balance);
    final firstId = off.readyTasks.first.id;
    // 让"本来在最前"的那条承担最弱编码，这样注意力低时它该被换下去。
    final weakTaskId = firstId;
    final neutralTaskId = firstId == a.id ? b.id : a.id;
    final weakKpIds =
        weakTaskId == a.id ? const ['kp-strong', 'kp-weak'] : const ['kp-weak'];
    final neutralKpIds = weakTaskId == a.id
        ? const ['kp-unbelief']
        : const ['kp-strong', 'kp-unbelief'];
    final rebalanced = ThreadBalanceInputs(
      taskKnowledgePoints: {
        weakTaskId: weakKpIds,
        neutralTaskId: neutralKpIds,
      },
      readings: balance.readings,
    );

    final on = await service.build(
      balance: rebalanced,
      cognitiveRankEnabled: true,
      // α = 0：注意力低 ⇒ 该先做容易的（难度 0.8 的任务被压下去）。
      cognitiveSeed: const CognitiveRankSeed(
        availability: 0,
        tagNodes: [MindNodeInfo(id: 'tag-a', parentId: null)],
      ),
    );

    final weakHit = on.cognitiveFor(weakTaskId)!;
    final neutralHit = on.cognitiveFor(neutralTaskId)!;
    expect(weakHit.availabilityFactor, closeTo(0.85, 1e-9),
        reason: '1 + 0.25×(2×(0×0.8 + 1×0.2) − 1)');
    expect(neutralHit.availabilityFactor, 1.0, reason: '置信度 0 的先验不算难度，这一项保持中性');
    expect(on.readyTasks.first.id, neutralTaskId, reason: '注意力低时弱编码的任务让位');
    expect(weakHit.movedUp, isFalse);
    expect(weakHit.reasonZh, contains('先做容易的'));
  });
}
