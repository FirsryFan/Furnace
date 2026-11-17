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

  group('tag tree sort mode (v29)', () {
    test('no settings row yet reads as never picked', () async {
      expect(await repo.getTagTreeSortMode(), isNull);
    });

    test('writes the stable code and reads it back', () async {
      await repo.ensureSettings();
      expect(await repo.getTagTreeSortMode(), isNull);

      await repo.updateTagTreeSortMode('object_count');
      expect(await repo.getTagTreeSortMode(), 'object_count');

      await repo.updateTagTreeSortMode('created_at');
      expect(await repo.getTagTreeSortMode(), 'created_at',
          reason: '后一次选择覆盖前一次，不是追加');
    });

    test('trims blank to NULL and keeps unknown codes untouched', () async {
      await repo.ensureSettings();
      await repo.updateTagTreeSortMode('  ');
      expect(await repo.getTagTreeSortMode(), isNull,
          reason: '空白不是第三种状态，写 NULL 表示没选过');

      await repo.updateTagTreeSortMode('alphabetical');
      expect(await repo.getTagTreeSortMode(), 'alphabetical');
      await repo.updateTagTreeSortMode(null);
      expect(await repo.getTagTreeSortMode(), isNull, reason: 'null = 恢复出厂排序');

      await repo.updateTagTreeSortMode('by_pinyin');
      expect(await repo.getTagTreeSortMode(), 'by_pinyin',
          reason: '合法集合归域层管，仓库不拒未知编码；读侧降级');
    });
  });

  group('tag tree expansion (v48)', () {
    test('no settings row yet reads as never saved', () async {
      expect(await repo.getTagTreeExpandedIds(), isNull);
    });

    test('creates the settings row on demand and round-trips the JSON',
        () async {
      // 第一行设置可能还没建（ensureSettings 是懒建的）：写展开状态必须自己
      // 建行，否则更新 0 行、用户状态悄悄丢失。
      expect(await db.select(db.localSettings).get(), isEmpty);

      await repo.updateTagTreeExpandedIds('["t-a","t-b"]');
      expect(await repo.getTagTreeExpandedIds(), '["t-a","t-b"]');

      await repo.updateTagTreeExpandedIds('[]');
      expect(await repo.getTagTreeExpandedIds(), '[]',
          reason: '空数组是"用户明确全折叠"，必须与 NULL（没保存过）区分');
    });

    test('trims blank to NULL and keeps malformed payloads untouched',
        () async {
      await repo.ensureSettings();
      await repo.updateTagTreeExpandedIds('   ');
      expect(await repo.getTagTreeExpandedIds(), isNull,
          reason: '空白不是第三种状态，写 NULL 表示没保存过');

      // 合法集合归域层管，仓库只存原文；坏值由读侧宽容降级成全折叠。
      await repo.updateTagTreeExpandedIds('not-json');
      expect(await repo.getTagTreeExpandedIds(), 'not-json');

      await repo.updateTagTreeExpandedIds(null);
      expect(await repo.getTagTreeExpandedIds(), isNull);
    });
  });
}
