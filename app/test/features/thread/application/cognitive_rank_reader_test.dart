import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/thread_state_repository.dart';
import 'package:furnace/domain/services/scheduling/cognitive_rank.dart';
import 'package:furnace/domain/services/scheduling/cognitive_rank_inputs.dart';
import 'package:furnace/features/thread/application/cognitive_rank_reader.dart';
import 'package:furnace/features/thread/application/study_rhythm_reader.dart';

/// Q29b：`cognitive_rank_reader` 是"数据库 → 认知排序素材"之间唯一的一跳。
///
/// 它要如实回答：目标节点在哪、刚活动过哪些知识点、每个知识点挂在标签树哪里、
/// 名字是什么、α(τ) 是多少。**不许推断**：日志指向的卡状态没有知识点时就不出现，
/// 提示关掉时 α 取中性而不是 0，任务标签不进知识点标签表。
void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late TagRepository tags;
  late ThreadStateRepository threadStates;
  late SettingsRepository settings;
  late CognitiveRankSeedReader reader;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    tags = TagRepository(db);
    threadStates = ThreadStateRepository(db);
    settings = SettingsRepository(db);
    reader = CognitiveRankSeedReader(
      db,
      anki,
      tags,
      threadStates,
      StudyRhythmReader(db, settings),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<KnowledgePoint> point(String title) =>
      anki.createKnowledgePoint(title: title, content: '$title 的内容');

  /// 走生产写入路径写一条复习日志。
  ///
  /// 卡状态走 v2 的**单元卡**（`getOrCreateUnitCardState`，一定会写
  /// `knowledge_point_id`）。v1 的 [`getOrCreateCardState`] 只写 `card_template_id`、
  /// 知识点留空 —— 那种卡状态在认知排序眼里**没有节点**（下面单独有一条用例钉住），
  /// 所以这里不能拿它当"正常的复习"。
  Future<void> logReview(KnowledgePoint p, DateTime when) async {
    final template = await anki.createTemplate(
      knowledgePointId: p.id,
      type: 'fill_blank',
      question: '${p.title}？',
      answer: p.title,
    );
    final state =
        await anki.getOrCreateUnitCardState(p.id, 'unit:${template.id}');
    await anki.addReviewLog(
      cardStateId: state.id,
      cardTemplateId: template.id,
      rating: 3,
      reviewedAt: when.millisecondsSinceEpoch,
    );
  }

  Future<void> logExposure(
    KnowledgePoint p,
    String unitKey,
    DateTime when,
  ) async {
    final state = await anki.getOrCreateUnitCardState(p.id, unitKey);
    await anki.addExposureLog(
      cardStateId: state.id,
      exposedAt: when.millisecondsSinceEpoch,
    );
  }

  /// 标签树：物理 ─ 力学 ─ 牛顿定律。
  Future<({Tag phi, Tag mech, Tag sub})> tree() async {
    final phi = await tags.createTag(name: '物理');
    final mech = await tags.createTag(name: '力学', parentId: phi.id);
    final sub = await tags.createTag(name: '牛顿定律', parentId: mech.id);
    return (phi: phi, mech: mech, sub: sub);
  }

  test('空库 ⇒ 中性 α、没有起点、没有图，"什么都不知道"', () async {
    final seed = await reader.read(now: DateTime.now());

    expect(seed.availability, 1);
    expect(seed.goalNodeId, isNull);
    expect(seed.activeKnowledgePointIds, isEmpty);
    expect(seed.tagNodes, isEmpty);
    expect(seed.knowledgePointTagIds, isEmpty);
    expect(seed.hasOrigins, isFalse);
    // 没素材时接线层确实什么都不说（不是"编一条近路"）。
    final inputs = CognitiveRankWiring.build(
      seed: seed,
      candidates: const [
        CognitiveRankCandidate(taskId: 'task-1', knowledgePointIds: ['kp-x']),
      ],
    );
    expect(inputs.originByKnowledgePoint, isEmpty);
  });

  test('目标节点与标签树原样透传：parentId 就是边，顺序显式排定', () async {
    final t = await tree();
    await threadStates.updateState(goalNodeId: t.sub.id);

    final seed = await reader.read(now: DateTime.now());

    expect(seed.goalNodeId, t.sub.id);
    expect(
      seed.tagNodes.map((n) => n.id).toList(),
      [t.phi.id, t.mech.id, t.sub.id]..sort(),
    );
    final byId = {for (final n in seed.tagNodes) n.id: n.parentId};
    expect(byId[t.phi.id], isNull);
    expect(byId[t.mech.id], t.phi.id);
    expect(byId[t.sub.id], t.mech.id);
    expect(seed.hasOrigins, isTrue);
  });

  test('刚活动来自复习日志：最近的在前、同一个知识点只出现一次、窗口外不算', () async {
    final now = DateTime.now();
    final first = await point('动量守恒');
    final second = await point('机械能守恒');
    await logReview(first, now.subtract(const Duration(hours: 1)));
    await logReview(second, now.subtract(const Duration(minutes: 30)));
    // 窗口（12h）之外的更早复习不该算"刚做过"。
    await logReview(first, now.subtract(const Duration(hours: 13)));

    final seed = await reader.read(now: now);

    expect(seed.activeKnowledgePointIds, [second.id, first.id]);
  });

  test('曝光日志也算活动，和复习日志按时间合并', () async {
    final now = DateTime.now();
    final read = await point('光合作用');
    final reviewed = await point('细胞呼吸');
    await logReview(reviewed, now.subtract(const Duration(hours: 2)));
    await logExposure(
        read, 'unit-1', now.subtract(const Duration(minutes: 10)));

    final seed = await reader.read(now: now);

    expect(seed.activeKnowledgePointIds, [read.id, reviewed.id]);
  });

  test('卡状态没有知识点 ⇒ 不出现（宁可少说，不猜）', () async {
    final now = DateTime.now();
    final p = await point('牛顿第一定律');
    final template = await anki.createTemplate(
      knowledgePointId: p.id,
      type: 'fill_blank',
      question: '惯性？',
      answer: '保持原状态',
    );
    // 直接写一条没有 knowledge_point_id 的卡状态：老库（v1 之前）里真实存在这种行。
    await db.into(db.cardStates).insert(
          CardStatesCompanion.insert(
            id: 'cs-orphan',
            createdAt: now.millisecondsSinceEpoch,
            updatedAt: now.millisecondsSinceEpoch,
          ),
        );
    await anki.addReviewLog(
      cardStateId: 'cs-orphan',
      cardTemplateId: template.id,
      rating: 3,
      reviewedAt:
          now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
    );

    final seed = await reader.read(now: now);

    expect(seed.activeKnowledgePointIds, isEmpty);
  });

  test('知识点标签只认 knowledge_point 这一类，列表有序，任务标签不算', () async {
    final t = await tree();
    final p = await point('牛顿第二定律');
    await tags.addTagToObject(
      tagId: t.mech.id,
      objectType: kCognitiveRankKnowledgePointObjectType,
      objectId: p.id,
    );
    await tags.addTagToObject(
      tagId: t.phi.id,
      objectType: kCognitiveRankKnowledgePointObjectType,
      objectId: p.id,
    );
    await tags.addTagToObject(
      tagId: t.sub.id,
      objectType: 'task',
      objectId: 'task-1',
    );

    final seed = await reader.read(now: DateTime.now());

    expect(seed.knowledgePointTagIds[p.id], [t.phi.id, t.mech.id]..sort());
    expect(seed.knowledgePointTagIds.containsKey('task-1'), isFalse);
  });

  test('名字取知识点标题，理由行才有话说', () async {
    final p = await point('楞次定律');

    final seed = await reader.read(now: DateTime.now());

    expect(seed.knowledgePointNames[p.id], '楞次定律');
  });

  test('α：开着且刚做过 ⇒ 就是读数本身；关掉 ⇒ 中性 1（不编数）', () async {
    final now = DateTime.now();
    await settings.ensureSettings();
    final p = await point('电场强度');
    await logReview(p, now.subtract(const Duration(minutes: 3)));

    final snapshot = await StudyRhythmReader(db, settings).read(now: now);
    final open = await reader.read(now: now);
    expect(open.availability, closeTo(snapshot.reading!.availability, 1e-9));

    await settings.updateRhythmHintsEnabled(false);
    final off = await reader.read(now: now);
    expect(off.availability, 1);
  });

  test('读出来的素材真的能排：目标 2 跳写 goal，刚复习过的写 activity', () async {
    final now = DateTime.now();
    final t = await tree();
    final p = await point('牛顿第二定律');
    await tags.addTagToObject(
      tagId: t.sub.id,
      objectType: kCognitiveRankKnowledgePointObjectType,
      objectId: p.id,
    );
    await threadStates.updateState(goalNodeId: t.phi.id);

    var seed = await reader.read(now: now);
    var inputs = CognitiveRankWiring.build(
      seed: seed,
      candidates: [
        CognitiveRankCandidate(taskId: 'task-1', knowledgePointIds: [p.id])
      ],
    );
    // 目标在「物理」，知识点挂在「牛顿定律」：物理 → 力学 → 牛顿定律 = 2 跳。
    expect(inputs.originByKnowledgePoint[p.id]!.hops, 2);
    expect(inputs.originByKnowledgePoint[p.id]!.link, CognitiveRankLink.goal);

    await logReview(p, now.subtract(const Duration(minutes: 5)));
    seed = await reader.read(now: now);
    inputs = CognitiveRankWiring.build(
      seed: seed,
      candidates: [
        CognitiveRankCandidate(taskId: 'task-1', knowledgePointIds: [p.id])
      ],
    );
    // 刚复习过 ⇒ 0 跳（最近的那个来源胜出），而且名字是读出来的标题。
    expect(inputs.originByKnowledgePoint[p.id]!.hops, 0);
    expect(
        inputs.originByKnowledgePoint[p.id]!.link, CognitiveRankLink.activity);
    expect(inputs.knowledgePointNames[p.id], '牛顿第二定律');
  });
}
