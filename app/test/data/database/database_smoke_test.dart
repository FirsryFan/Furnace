import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow/data/database/database.dart';
import 'package:knowflow/data/repositories/settings_repository.dart';
import 'package:knowflow/data/repositories/tag_repository.dart';
import 'package:knowflow/data/repositories/task_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late TagRepository tags;
  late TaskRepository tasks;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
    tags = TagRepository(db);
    tasks = TaskRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('creates profile, tag and task', () async {
    final profile = await settings.ensureProfile(displayName: '张三');
    expect(profile.displayName, '张三');

    final tag = await tags.createTag(name: '光合作用', color: 123);
    expect(tag.name, '光合作用');

    final task = await tasks.createTask(
      title: '复习光合作用',
      priority: 2,
      estimateMinutes: 30,
    );
    expect(task.title, '复习光合作用');
    expect(task.priority, 2);

    final allTasks = await tasks.getOpenTasks();
    expect(allTasks, hasLength(1));
  });
}
