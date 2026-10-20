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

  group('review reminder (v28)', () {
    test('no settings row yet reads as off / never picked', () async {
      expect(await repo.getReviewReminderEnabled(), isFalse);
      expect(await repo.getReviewReminderMinutes(), isNull);
    });

    test('writes and reads the switch and the minute of day', () async {
      await repo.ensureSettings();
      await repo.updateReviewReminderEnabled(true);
      await repo.updateReviewReminderMinutes(1230);
      expect(await repo.getReviewReminderEnabled(), isTrue);
      expect(await repo.getReviewReminderMinutes(), 1230);

      await repo.updateReviewReminderEnabled(false);
      expect(await repo.getReviewReminderEnabled(), isFalse,
          reason: '关掉开关不清时刻：用户再打开时还是上次选的时间');
      expect(await repo.getReviewReminderMinutes(), 1230);
    });

    test('minutes outside 0..1439 throw ArgumentError and leave the row alone',
        () async {
      await repo.ensureSettings();
      await expectLater(
          repo.updateReviewReminderMinutes(-1), throwsArgumentError);
      await expectLater(
          repo.updateReviewReminderMinutes(1440), throwsArgumentError);
      await expectLater(
          repo.updateReviewReminderMinutes(1 << 30), throwsArgumentError);
      expect(await repo.getReviewReminderMinutes(), isNull);

      await repo.updateReviewReminderMinutes(0);
      expect(await repo.getReviewReminderMinutes(), 0,
          reason: '0 = 午夜，合法且必须与 NULL 区分');
    });
  });
}
