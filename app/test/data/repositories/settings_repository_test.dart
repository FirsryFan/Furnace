import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SettingsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('creates and updates profile name', () async {
    final profile = await repo.ensureProfile(displayName: '张三');
    expect(profile.displayName, '张三');

    await repo.updateProfileName('李四');
    final updated = await repo.getProfile();
    expect(updated!.displayName, '李四');
  });

  test('ensures single settings row', () async {
    final first = await repo.ensureSettings();
    final second = await repo.ensureSettings();
    expect(first.id, 1);
    expect(second.id, 1);

    await repo.updateLanguage('zh');
    final settings = await repo.getSettings();
    expect(settings!.language, 'zh');
  });
}
