import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/thread_rank_repository.dart';
import 'package:furnace/data/repositories/thread_state_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/settings/application/demo_data_service.dart';
import 'package:furnace/features/thread/application/thread_rank_service.dart';

/// The demo workspace is the first thing the user touches when reviewing the
/// UI, so it must actually produce a usable, non-empty workspace.
void main() {
  late AppDatabase db;
  late DemoDataService demo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    demo = DemoDataService(
      tagRepository: TagRepository(db),
      taskRepository: TaskRepository(db),
      ankiRepository: AnkiRepository(db),
      timeBlockRepository: TimeBlockRepository(db),
      threadStateRepository: ThreadStateRepository(db),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('seeds a workspace that every module can render', () async {
    expect(await demo.hasExistingData(), isFalse);

    final message = await demo.seed();
    expect(message, isNotEmpty);
    expect(await demo.hasExistingData(), isTrue);

    // Tag tree: parent/child paths are real.
    final tags = await TagRepository(db).getAllTags();
    expect(tags.length, greaterThanOrEqualTo(8));
    expect(
      tags.map((t) => t.path),
      containsAll(<String>['文化课', '文化课/数学', '文化课/数学/代数']),
    );

    // Knowledge points exist and are blankable.
    final points = await AnkiRepository(db).getKnowledgePoints();
    expect(points.length, 4);
    expect(points.every((p) => p.content.isNotEmpty), isTrue);

    // Events cover the states the Thread list distinguishes.
    final tasks = await TaskRepository(db).getTasks(includeDone: true);
    expect(tasks.length, 6);
    expect(tasks.where((t) => t.dueAt == null), isNotEmpty);
    expect(
      tasks.where((t) => t.dueAt != null && t.dueAt! < DateTime.now().millisecondsSinceEpoch),
      isNotEmpty,
      reason: 'one event must be overdue so the archive view has content',
    );

    // Schedule blocks: at least one busy hard block and one open soft block.
    final blocks = await TimeBlockRepository(db).getTimeBlocks();
    expect(blocks.where((b) => !b.available), isNotEmpty);
    expect(blocks.where((b) => b.available), isNotEmpty);
    expect(blocks.where((b) => b.repeatRule != null), isNotEmpty);

    // Status bar is populated so the first sort produces a meaningful order.
    final state = await ThreadStateRepository(db).getState();
    expect(state, isNotNull);
    expect(state!.energy, 7);
    expect(state.goalText, '数学');

    // And the ranking engine can actually consume it.
    final service = ThreadRankService(
      taskRepository: TaskRepository(db),
      timeBlockRepository: TimeBlockRepository(db),
      tagRepository: TagRepository(db),
      threadRankRepository: ThreadRankRepository(db),
      threadStateRepository: ThreadStateRepository(db),
    );
    final feed = await service.build();
    expect(feed.ranked.ready, isNotEmpty);
    expect(feed.ranked.overdue, isNotEmpty);
    expect(feed.ranked.insufficient, isNotEmpty);
  });
}
