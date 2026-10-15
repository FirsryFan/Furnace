import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/thread_rank_repository.dart';
import 'package:furnace/features/thread/application/thread_rank_service.dart';

/// 认知排序档位的开关真的被 `ThreadFeedNotifier` 读到了（Q29d）。
///
/// `test/features/thread/thread_rank_service_cognitive_test.dart` 钉的是服务本身；
/// 这一条钉的是接线：provider 图解析得动、开关从库里读、素材读不出来时退化成
/// "没有读数"而不是整个排序失败。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer container() {
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<ThreadFeed> sortAndRead(ProviderContainer container) async {
    await container.read(threadFeedProvider.notifier).sort();
    return container.read(threadFeedProvider).value!;
  }

  test('开关关着：排序结果里没有认知档位', () async {
    await TaskRepository(db).createTask(title: '写物理作业', estimateMinutes: 15);

    final feed = await sortAndRead(container());

    expect(feed.cognitiveRank, isNull);
    expect(feed.readyTasks.length, 1);
  });

  test('库里打开开关之后：排序结果带上认知档位，素材读不出来也不炸', () async {
    final task = await TaskRepository(db)
        .createTask(title: '写物理作业', estimateMinutes: 15);
    final container2 = container();
    expect((await sortAndRead(container2)).cognitiveRank, isNull,
        reason: '默认关');

    await ThreadRankRepository(db).setCognitiveRankEnabled(true);
    final feed = await sortAndRead(container2);

    expect(feed.cognitiveRank, isNotNull);
    expect(feed.readyTasks.single.id, task.id);
    expect(feed.cognitiveReasonFor(task.id), contains('没有认知读数'),
        reason: '空库里没有起点：这一档如实说自己没读数');
  });
}
