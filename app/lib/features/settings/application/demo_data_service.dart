import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/repositories/tag_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../data/repositories/thread_state_repository.dart';
import '../../../data/repositories/time_block_repository.dart';

/// Loads a small, realistic demo workspace so the app can be inspected without
/// hand-entering data first.
///
/// Deliberately one-shot: it refuses to run when the event list is not empty,
/// so it can never pile duplicate demo rows on top of real work.
class DemoDataService {
  DemoDataService({
    required this.tagRepository,
    required this.taskRepository,
    required this.ankiRepository,
    required this.timeBlockRepository,
    required this.threadStateRepository,
  });

  final TagRepository tagRepository;
  final TaskRepository taskRepository;
  final AnkiRepository ankiRepository;
  final TimeBlockRepository timeBlockRepository;
  final ThreadStateRepository threadStateRepository;

  /// True when the workspace already has data.
  Future<bool> hasExistingData() async {
    final tasks = await taskRepository.getTasks(includeDone: true);
    if (tasks.isNotEmpty) {
      return true;
    }
    final points = await ankiRepository.getKnowledgePoints();
    return points.isNotEmpty;
  }

  /// Creates the demo workspace. Returns a short description of what happened.
  Future<String> seed() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // --- tag tree (this is Mindnet now, blueprint 2.8) ---------------------
    final culture = await tagRepository.createTag(name: '文化课');
    final math = await tagRepository.createTag(name: '数学', parentId: culture.id);
    final chinese =
        await tagRepository.createTag(name: '语文', parentId: culture.id);
    final english =
        await tagRepository.createTag(name: '英语', parentId: culture.id);
    final algebra = await tagRepository.createTag(name: '代数', parentId: math.id);
    final geometry =
        await tagRepository.createTag(name: '几何', parentId: math.id);
    final composition =
        await tagRepository.createTag(name: '作文', parentId: chinese.id);
    final words = await tagRepository.createTag(name: '单词', parentId: english.id);

    // --- knowledge points with blankable Chinese content -------------------
    final kpAlgebra = await ankiRepository.createKnowledgePoint(
      title: '一次函数',
      content: '一次函数的图像是一条直线，其中 k 决定倾斜程度，b 决定与 y 轴的交点。',
    );
    final kpGeometry = await ankiRepository.createKnowledgePoint(
      title: '三角形内角和',
      content: '三角形内角和为 180 度，这个结论在平面几何中总是成立。',
    );
    final kpComposition = await ankiRepository.createKnowledgePoint(
      title: '议论文结构',
      content: '议论文的常见结构是总起、分论、总结，核心是论点必须明确。',
    );
    final kpWords = await ankiRepository.createKnowledgePoint(
      title: '单词 abandon',
      content: 'abandon 的意思是放弃，常用搭配是 abandon oneself to。',
    );

    await tagRepository.addTagToObject(
        tagId: algebra.id, objectType: 'knowledge_point', objectId: kpAlgebra.id);
    await tagRepository.addTagToObject(
        tagId: geometry.id,
        objectType: 'knowledge_point',
        objectId: kpGeometry.id);
    await tagRepository.addTagToObject(
        tagId: composition.id,
        objectType: 'knowledge_point',
        objectId: kpComposition.id);
    await tagRepository.addTagToObject(
        tagId: words.id, objectType: 'knowledge_point', objectId: kpWords.id);

    // --- Thread events, spread across every state the list can show --------
    // Times are relative to NOW, not to midnight: the archive view must have
    // an overdue event and the main list a genuinely tight one no matter what
    // time of day the demo is loaded.
    final events = <({String title, int? estimate, int? energy, DateTime? due})>[
      (
        title: '数学卷子最后一题',
        estimate: 30,
        energy: 9,
        due: now.add(const Duration(hours: 6)),
      ),
      (
        title: '背 20 个英语单词',
        estimate: 20,
        energy: 5,
        due: now.add(const Duration(hours: 10)),
      ),
      (
        title: '整理语文作文素材',
        estimate: 45,
        energy: 6,
        due: now.add(const Duration(days: 3)),
      ),
      (title: '复习几何错题', estimate: 25, energy: 7, due: null),
      (
        title: '补交上周的物理作业',
        estimate: 30,
        energy: 4,
        due: now.subtract(const Duration(hours: 5)),
      ),
      (
        // Deadline sooner than the estimate itself: this one lands in
        // "not enough time" whatever time of day the demo is loaded.
        title: '写一篇 800 字读书笔记',
        estimate: 480,
        energy: 8,
        due: now.add(const Duration(hours: 4)),
      ),
    ];
    for (final event in events) {
      final task = await taskRepository.createTask(
        title: event.title,
        estimateMinutes: event.estimate,
        energyRequired: event.energy,
        dueAt: event.due?.millisecondsSinceEpoch,
        expectedAt: event.due == null
            ? null
            : event.due!.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
      );
      final tag = switch (event.title) {
        '数学卷子最后一题' => algebra.id,
        '复习几何错题' => geometry.id,
        '整理语文作文素材' => composition.id,
        '背 20 个英语单词' => words.id,
        _ => null,
      };
      if (tag != null) {
        await tagRepository.addTagToObject(
            tagId: tag, objectType: 'task', objectId: task.id);
      }
    }

    // --- schedule blocks: busy hard blocks + open soft blocks -------------
    // Anchored to a wall-clock grid (today 08:00 / 19:00 / 12:30) so the
    // calendar looks like a real day; the ranking test only needs the busy
    // minutes that fall inside an event's deadline window.
    await timeBlockRepository.createTimeBlock(
      title: '上午上课',
      startAt: today.add(const Duration(hours: 8)).millisecondsSinceEpoch,
      endAt: today.add(const Duration(hours: 12)).millisecondsSinceEpoch,
      available: false,
      repeatRule: '{"type":"daily"}',
    );
    await timeBlockRepository.createTimeBlock(
      title: '晚自习',
      startAt: today.add(const Duration(hours: 19)).millisecondsSinceEpoch,
      endAt: today.add(const Duration(hours: 21)).millisecondsSinceEpoch,
      available: false,
    );
    await timeBlockRepository.createTimeBlock(
      title: '碎片时间',
      startAt: today.add(const Duration(hours: 12, minutes: 30)).millisecondsSinceEpoch,
      endAt: today.add(const Duration(hours: 13, minutes: 30)).millisecondsSinceEpoch,
      available: true,
      energy: 'medium',
      suitableFor: 'memorize',
    );

    // --- Thread status bar: energy + a goal that matches tagged events ----
    await threadStateRepository.updateState(energy: 7, goalText: '数学');

    return '示例数据已载入：4 个词条、6 个事件、3 个日程块、8 个标签。';
  }
}

final demoDataServiceProvider = Provider<DemoDataService>((ref) {
  return DemoDataService(
    tagRepository: ref.watch(tagRepositoryProvider),
    taskRepository: ref.watch(taskRepositoryProvider),
    ankiRepository: ref.watch(ankiRepositoryProvider),
    timeBlockRepository: ref.watch(timeBlockRepositoryProvider),
    threadStateRepository: ref.watch(threadStateRepositoryProvider),
  );
});
