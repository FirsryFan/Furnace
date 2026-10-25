import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/domain/services/tags/tag_usage.dart';
import 'package:furnace/features/timeboard/presentation/time_board_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// The board used to be titled "today's schedule" but listed every block. The
/// fix keeps "all" as the default and adds a real local-day filter: a block is
/// today's when it overlaps [today 00:00, tomorrow 00:00), so a block spanning
/// midnight counts for both days. The schedule card follows the same filter.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<AppDatabase> openDatabase() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    return db;
  }

  Future<void> pumpBoard(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TimeBoardPage(),
        ),
      ),
    );
    await settle(tester);
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(TimeBoardPage)));

  final dayStart = timeBoardDayStart(DateTime.now());
  DateTime at(int hour, {int dayOffset = 0}) => DateTime(
        dayStart.year,
        dayStart.month,
        dayStart.day + dayOffset,
        hour,
      );
  int ms(DateTime moment) => moment.millisecondsSinceEpoch;

  Future<TimeBlock> seedBlock(
    AppDatabase db, {
    required String title,
    required DateTime start,
    required DateTime end,
  }) {
    return TimeBlockRepository(db).createTimeBlock(
      title: title,
      startAt: ms(start),
      endAt: ms(end),
    );
  }

  Future<void> seedTask(
    AppDatabase db, {
    required String title,
    required String blockId,
  }) async {
    final repository = TaskRepository(db);
    final task = await repository.createTask(title: title);
    await repository.linkTaskToTimeBlock(
      taskId: task.id,
      timeBlockId: blockId,
    );
  }

  test('一天的交集判定用本地日期半开区间，跨午夜的块算今天', () async {
    final db = await openDatabase();
    final endsAtMidnight = await seedBlock(
      db,
      title: '昨天夜里的块',
      start: at(22, dayOffset: -1),
      end: at(0),
    );
    final startsAtMidnight = await seedBlock(
      db,
      title: '今天零点的块',
      start: at(0),
      end: at(1),
    );
    final crossMidnight = await seedBlock(
      db,
      title: '跨午夜的块',
      start: at(23, dayOffset: -1),
      end: at(1),
    );
    final tomorrow = await seedBlock(
      db,
      title: '明天的块',
      start: at(0, dayOffset: 1),
      end: at(1, dayOffset: 1),
    );

    expect(
      timeBoardDayStart(DateTime(2026, 3, 5, 14, 30)),
      DateTime(2026, 3, 5),
    );
    expect(timeBlockOverlapsDay(endsAtMidnight, dayStart), isFalse);
    expect(timeBlockOverlapsDay(startsAtMidnight, dayStart), isTrue);
    expect(timeBlockOverlapsDay(crossMidnight, dayStart), isTrue);
    expect(timeBlockOverlapsDay(tomorrow, dayStart), isFalse);
    expect(
      timeBlocksForDay(
        [endsAtMidnight, startsAtMidnight, crossMidnight, tomorrow],
        dayStart,
      ).map((block) => block.title),
      ['今天零点的块', '跨午夜的块'],
      reason: '过滤保留原有顺序',
    );
  });

  testWidgets('默认全部：昨天、今天、明天的块都显示，默认选中全部', (tester) async {
    final db = await openDatabase();
    await seedBlock(db,
        title: '昨天的块', start: at(9, dayOffset: -1), end: at(10, dayOffset: -1));
    await seedBlock(db, title: '今天的块', start: at(9), end: at(10));
    await seedBlock(db,
        title: '明天的块', start: at(9, dayOffset: 1), end: at(10, dayOffset: 1));

    await pumpBoard(tester, db);
    final l10n = l10nOf(tester);

    expect(find.text('昨天的块'), findsOneWidget);
    expect(find.text('今天的块'), findsOneWidget);
    expect(find.text('明天的块'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    expect(find.text(l10n.timeBoardFilterAll), findsOneWidget);
    expect(find.text(l10n.timeBoardFilterToday), findsOneWidget);
    expect(
      tester.widget<ChoiceChip>(find.byKey(timeBoardFilterAllKey)).selected,
      isTrue,
    );
    expect(
      tester.widget<ChoiceChip>(find.byKey(timeBoardFilterTodayKey)).selected,
      isFalse,
    );
  });

  testWidgets('切到今天：昨天和明天的块隐藏，跨午夜的块保留', (tester) async {
    final db = await openDatabase();
    await seedBlock(db,
        title: '昨天的块', start: at(9, dayOffset: -1), end: at(10, dayOffset: -1));
    await seedBlock(db, title: '今天的块', start: at(9), end: at(10));
    await seedBlock(db,
        title: '明天的块', start: at(9, dayOffset: 1), end: at(10, dayOffset: 1));
    await seedBlock(db,
        title: '跨午夜的块', start: at(23, dayOffset: -1), end: at(1));

    await pumpBoard(tester, db);
    await tester.tap(find.byKey(timeBoardFilterTodayKey));
    await settle(tester);

    expect(find.text('今天的块'), findsOneWidget);
    expect(find.text('跨午夜的块'), findsOneWidget);
    expect(find.text('昨天的块'), findsNothing);
    expect(find.text('明天的块'), findsNothing);
    expect(
      tester.widget<ChoiceChip>(find.byKey(timeBoardFilterTodayKey)).selected,
      isTrue,
    );
  });

  testWidgets('今天没有安排：显示今天空态与新建按钮，其他日期的块隐藏', (tester) async {
    final db = await openDatabase();
    await seedBlock(db,
        title: '明天的块', start: at(9, dayOffset: 1), end: at(10, dayOffset: 1));

    await pumpBoard(tester, db);
    await tester.tap(find.byKey(timeBoardFilterTodayKey));
    await settle(tester);
    final l10n = l10nOf(tester);

    expect(find.byKey(timeBoardTodayEmptyKey), findsOneWidget);
    expect(find.text(l10n.timeBoardTodayEmpty), findsOneWidget);
    expect(find.byKey(timeBoardTodayEmptyActionKey), findsOneWidget);
    expect(find.text('明天的块'), findsNothing);
    expect(find.byType(ChoiceChip), findsNWidgets(2));
  });

  testWidgets('日程卡随过滤只保留今天的任务', (tester) async {
    final db = await openDatabase();
    final todayBlock =
        await seedBlock(db, title: '今天的块', start: at(9), end: at(10));
    final tomorrowBlock = await seedBlock(db,
        title: '明天的块', start: at(9, dayOffset: 1), end: at(10, dayOffset: 1));
    await seedTask(db, title: '今天任务A', blockId: todayBlock.id);
    await seedTask(db, title: '明天任务B', blockId: tomorrowBlock.id);

    await pumpBoard(tester, db);
    expect(find.text('今天任务A'), findsOneWidget, reason: '全部时两条都在卡里');
    expect(find.text('明天任务B'), findsOneWidget);

    await tester.tap(find.byKey(timeBoardFilterTodayKey));
    await settle(tester);

    expect(find.byType(Card), findsOneWidget);
    expect(find.text('今天任务A'), findsOneWidget);
    expect(find.text('明天任务B'), findsNothing);
  });

  testWidgets('今天没有带任务的块时日程卡不渲染', (tester) async {
    final db = await openDatabase();
    await seedBlock(db, title: '今天的空块', start: at(9), end: at(10));
    final tomorrowBlock = await seedBlock(db,
        title: '明天的块', start: at(9, dayOffset: 1), end: at(10, dayOffset: 1));
    await seedTask(db, title: '明天的任务', blockId: tomorrowBlock.id);

    await pumpBoard(tester, db);
    expect(find.byType(Card), findsOneWidget);

    await tester.tap(find.byKey(timeBoardFilterTodayKey));
    await settle(tester);

    expect(find.byType(Card), findsNothing);
    expect(find.text('今天的空块'), findsOneWidget);
    expect(find.text('明天的任务'), findsNothing);
  });

  testWidgets('全部没有块：保持原空态，且不显示过滤片', (tester) async {
    final db = await openDatabase();

    await pumpBoard(tester, db);
    final l10n = l10nOf(tester);

    expect(find.byKey(timeBoardEmptyActionKey), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byKey(timeBoardTodayEmptyKey), findsNothing);

    await tester.tap(find.byKey(timeBoardEmptyActionKey));
    await settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(l10n.timeNewBlock), findsWidgets);
  });

  testWidgets('切回全部后恢复所有块，今天空态消失', (tester) async {
    final db = await openDatabase();
    await seedBlock(db,
        title: '明天的块', start: at(9, dayOffset: 1), end: at(10, dayOffset: 1));

    await pumpBoard(tester, db);
    await tester.tap(find.byKey(timeBoardFilterTodayKey));
    await settle(tester);
    expect(find.byKey(timeBoardTodayEmptyKey), findsOneWidget);

    await tester.tap(find.byKey(timeBoardFilterAllKey));
    await settle(tester);

    expect(find.byKey(timeBoardTodayEmptyKey), findsNothing);
    expect(find.text('明天的块'), findsOneWidget);
    expect(
      tester.widget<ChoiceChip>(find.byKey(timeBoardFilterAllKey)).selected,
      isTrue,
    );
  });

  group('编辑对话框的标签选择器按用途过滤（v37）', () {
    /// 编辑对话框的 Column 不滚动，默认 800x600 会 overflow。
    Future<void> useTallView(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<void> pumpUntil(
      WidgetTester tester,
      Finder finder, {
      int rounds = 60,
    }) async {
      for (var attempt = 0; attempt < rounds; attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (finder.evaluate().isNotEmpty) {
          return;
        }
      }
      fail('等待目标 widget 出现超时：$finder');
    }

    /// 打开某个时间块的编辑对话框（先等数据库里的标签读回来）。
    Future<void> openEditDialog(WidgetTester tester, String title) async {
      await tester.tap(find.descendant(
        of: find.widgetWithText(ListTile, title),
        matching: find.byTooltip(l10nOf(tester).commonEdit),
      ));
      await pumpUntil(tester, find.byType(AlertDialog));
    }

    Finder addTagButton() => find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byIcon(Icons.add),
        );

    testWidgets('只列出「纳入时间表」的标签', (tester) async {
      await useTallView(tester);
      final db = await openDatabase();
      await seedBlock(db, title: '晨读块', start: at(9), end: at(10));
      final tags = TagRepository(db);
      final timeTag = await tags.createTag(name: '晨读标签');
      final questionTag = await tags.createTag(name: '题库标签');
      await tags.updateTagUsageCodes(timeTag.id, {TagUsage.time});
      await tags.updateTagUsageCodes(questionTag.id, {TagUsage.question});
      await pumpBoard(tester, db);
      final l10n = l10nOf(tester);

      await openEditDialog(tester, '晨读块');
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(l10n.timeBlockTagScopeHint),
        ),
        findsOneWidget,
        reason: '过滤提示常显，用户不用点开才知道规则',
      );

      await tester.tap(addTagButton());
      await pumpUntil(tester, find.byType(SimpleDialog));

      expect(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text('晨读标签'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text('题库标签'),
        ),
        findsNothing,
        reason: '只声明了题库用途的标签不能出现在时间表的标签选择器里',
      );
    });

    testWidgets('整树没有用途声明时不过滤：所有标签都可见', (tester) async {
      await useTallView(tester);
      final db = await openDatabase();
      await seedBlock(db, title: '晨读块', start: at(9), end: at(10));
      final tags = TagRepository(db);
      await tags.createTag(name: '晨读标签');
      await tags.createTag(name: '题库标签');
      await pumpBoard(tester, db);

      await openEditDialog(tester, '晨读块');
      await tester.tap(addTagButton());
      await pumpUntil(tester, find.byType(SimpleDialog));

      expect(find.text('晨读标签'), findsOneWidget);
      expect(find.text('题库标签'), findsOneWidget);
    });

    testWidgets('只有标签声明了其他用途：说明空态而不是静默失败', (tester) async {
      await useTallView(tester);
      final db = await openDatabase();
      await seedBlock(db, title: '晨读块', start: at(9), end: at(10));
      final tags = TagRepository(db);
      final questionTag = await tags.createTag(name: '题库标签');
      await tags.updateTagUsageCodes(questionTag.id, {TagUsage.question});
      await pumpBoard(tester, db);
      final l10n = l10nOf(tester);

      await openEditDialog(tester, '晨读块');
      await tester.tap(addTagButton());
      await pumpUntil(
        tester,
        find.byKey(const ValueKey<String>('time-block-tag-scope-empty')),
      );

      expect(find.text(l10n.timeBlockTagScopeEmpty), findsOneWidget);
      expect(find.byType(SimpleDialogOption), findsNothing);
      expect(find.text('题库标签'), findsNothing);
    });

    testWidgets('没设过用途但标签都已挂上：给出默认提示', (tester) async {
      await useTallView(tester);
      final db = await openDatabase();
      final block =
          await seedBlock(db, title: '晨读块', start: at(9), end: at(10));
      final tags = TagRepository(db);
      final tag = await tags.createTag(name: '晨读标签');
      await tags.addTagToObject(
        tagId: tag.id,
        objectType: 'time_block',
        objectId: block.id,
      );
      await pumpBoard(tester, db);
      final l10n = l10nOf(tester);

      await openEditDialog(tester, '晨读块');
      await tester.tap(addTagButton());
      await pumpUntil(
        tester,
        find.byKey(const ValueKey<String>('time-block-tag-scope-empty')),
      );

      expect(find.text(l10n.timeBlockTagScopeDefaultHint), findsOneWidget);
      expect(find.byType(SimpleDialogOption), findsNothing);
    });
  });
}
