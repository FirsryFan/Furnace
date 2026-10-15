import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/domain/services/cognitive/fast_diagnosis.dart';
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart'
    show cognitiveLibraryDiagnosisProvider;
import 'package:furnace/features/thread/application/thread_balance_provider.dart';
import 'package:furnace/features/thread/application/thread_rank_service.dart';

/// Segment B's application layer: the database's tag mounts plus the cognitive
/// page's **own** diagnosis, turned into the pure input record the ranker eats.
///
/// The diagnosis provider is overridden here on purpose: this test is about the
/// assembly (which rows become which field), not about how a bottleneck is
/// decided - that belongs to the cognitive layer's own tests.
///
/// The ids in here are deliberately *not* interchangeable: a knowledge point is
/// `kp-…` and a tag is `tag-…`, so a test that used one for both would hide a
/// broken link. The translation itself lives in the domain entry points (Q8) and
/// is pinned by `test/features/cognitive/knowledge_point_key_space_test.dart`.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// A knowledge point, a tag mounted on it, and a task sharing that tag.
  ///
  /// This is the only way this app can say "this task practises that point":
  /// there is no task -> point column, the shared tag *is* the link (D2: one
  /// number, one source).
  Future<({Task task, String tagId, String knowledgePointId})> seedTaggedTask({
    required String tagName,
    required String knowledgePointTitle,
  }) async {
    final tags = TagRepository(db);
    final knowledgePoint = await AnkiRepository(db).createKnowledgePoint(
      title: knowledgePointTitle,
      content: '$knowledgePointTitle 的内容',
    );
    final tag = await tags.createTag(name: tagName);
    await tags.addTagToObject(
      tagId: tag.id,
      objectType: 'knowledge_point',
      objectId: knowledgePoint.id,
    );
    final task = await TaskRepository(db)
        .createTask(title: '$tagName 练习', estimateMinutes: 15);
    await tags.addTagToObject(
      tagId: tag.id,
      objectType: 'task',
      objectId: task.id,
    );
    return (task: task, tagId: tag.id, knowledgePointId: knowledgePoint.id);
  }

  ProviderContainer containerWith(LibraryDiagnosis diagnosis) {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        cognitiveLibraryDiagnosisProvider.overrideWith((ref) async => diagnosis),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('tag mounts become task -> knowledge point links, with readings',
      () async {
    final seeded =
        await seedTaggedTask(tagName: '数学', knowledgePointTitle: '一次函数');
    final container = containerWith(
      LibraryDiagnosis(
        // 键是**知识点 id**：Q8 之后，标签 → 知识点的翻译发生在
        // `LibraryDiagnosisRunner.run` 里（它认识标签图，出口一律是调用方的键），
        // 所以页面 provider 交出来的是 kp 键的结论。桥本身由
        // `test/features/cognitive/knowledge_point_key_space_test.dart` 用真实数据钉住。
        byKnowledgePoint: {seeded.knowledgePointId: BottleneckType.danger},
        fastLayerRan: true,
      ),
    );

    final inputs = await container.read(threadBalanceInputsProvider.future);

    expect(seeded.knowledgePointId, isNot(seeded.tagId),
        reason: '两个命名空间本来就不同，测试必须保留这个差异，否则翻译会被藏起来');
    expect(
      inputs.taskKnowledgePoints[seeded.task.id],
      [seeded.knowledgePointId],
    );
    final reading = inputs.readings.single;
    expect(reading.knowledgePointId, seeded.knowledgePointId);
    expect(reading.inDangerZone, isTrue,
        reason: '结论按知识点 id 查得到，否则真实数据里永远匹配不上');
    expect(inputs.knowledgePointNames[seeded.knowledgePointId], '一次函数');
    expect(inputs.tags.single.name, '数学');
    expect(inputs.taskTagLinks.single.taskId, seeded.task.id);
    expect(inputs.hasData, isTrue);
  });

  test('a diagnosis that never ran yields no readings, not healthy ones',
      () async {
    await seedTaggedTask(tagName: '数学', knowledgePointTitle: '一次函数');
    final container = containerWith(LibraryDiagnosis.notRun);

    final inputs = await container.read(threadBalanceInputsProvider.future);

    expect(inputs.readings, isEmpty,
        reason: 'fastLayerRan == false 是"没跑"，不能当成"健康"');
    expect(inputs.taskKnowledgePoints, isNotEmpty,
        reason: '挂载关系与诊断无关，仍然要读出来');
  });

  test('sort() publishes the balanced order and the reason line', () async {
    final seeded =
        await seedTaggedTask(tagName: '数学', knowledgePointTitle: '一次函数');
    final plain =
        await TaskRepository(db).createTask(title: '随便一件事', estimateMinutes: 15);
    final container = containerWith(
      LibraryDiagnosis(
        byKnowledgePoint: {seeded.knowledgePointId: BottleneckType.danger},
        fastLayerRan: true,
      ),
    );

    await container.read(threadFeedProvider.notifier).sort();

    final feed = container.read(threadFeedProvider).value!;
    expect(feed.readyTasks.map((t) => t.id).toSet(), {seeded.task.id, plain.id});
    expect(feed.readyTasks.first.id, seeded.task.id,
        reason: '危险区读数把它的有效性从 0.5 拉到 0.85');
    // 理由行念名字，不念 id：知识点名字来自 `KnowledgePoints.title`。
    expect(feed.reasonFor(seeded.task.id), contains('知识点「一次函数」'));
    expect(feed.reasonFor(seeded.task.id), contains('危险区'));
  });
}
