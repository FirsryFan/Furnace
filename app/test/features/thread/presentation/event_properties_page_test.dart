import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/thread/presentation/event_properties_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// Q27：事件属性页的「期望时刻」撞上忙碌日程块时，弹警告 + 「移到这块之前/之后」。
///
/// 这些测试故意**只走 UI**（点期望时刻 → 日期/时间都按确定 → 保存 → 读库），因为
/// 要钉住的正是「选完时刻到落库之间」这一段行为：
///   * 撞上忙碌块 → 出现警告，移动动作落到引擎判定为空闲的最近时刻；
///   * 不撞（空闲 / 开放块）→ 不打扰用户，选什么就是什么；
///   * 点掉警告 → **放弃这次选择**（期望时刻保持原值）；
///   * **只挪期望时刻**：截止时刻卡片不参与冲突解析（蓝图 2.4 / 用户 16）。
///
/// 判定口径不在这里重写：按钮上的候选时刻由 `ScheduleConflict` 给出，领域层
/// `app/test/domain/services/scheduling/schedule_conflict_test.dart` 已经把
/// 「半开区间 / 首尾相接不算 / ±1 分钟探测 / 重复规则展开」钉在引擎口径上。
/// 弹出的是 Q23 已经交付的同一个弹窗（`ScheduleConflictDialog`），本片不新造文案。
void main() {
  /// 用「明天」当基准日，避开日期选择器的 firstDate/lastDate 边界。
  final day = DateTime.now().add(const Duration(days: 1));

  DateTime at(int hour, [int minute = 0]) =>
      DateTime(day.year, day.month, day.day, hour, minute);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<AppDatabase> openDatabase() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    return db;
  }

  /// 造一个「事件」（thread 侧的事件就是 tasks 行）。
  Future<String> seedEvent(AppDatabase db,
      {required DateTime expectedAt}) async {
    final task = await TaskRepository(db).createTask(
      title: '写物理作业',
      expectedAt: expectedAt.millisecondsSinceEpoch,
    );
    return task.id;
  }

  Future<void> seedBlock(
    AppDatabase db, {
    required int startHour,
    required int endHour,
    bool available = false,
  }) async {
    await TimeBlockRepository(db).createTimeBlock(
      title: '上课',
      startAt: at(startHour).millisecondsSinceEpoch,
      endAt: at(endHour).millisecondsSinceEpoch,
      available: available,
    );
  }

  Future<void> pumpPage(
    WidgetTester tester,
    AppDatabase db,
    String taskId,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EventPropertiesPage(taskId: taskId),
        ),
      ),
    );
    await settle(tester);
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(EventPropertiesPage)));

  /// 从库里读回期望时刻（毫秒）。
  Future<int?> expectedAtIn(AppDatabase db, String taskId) async {
    final task = await TaskRepository(db).getTaskById(taskId);
    return task?.expectedAt;
  }

  /// 日期选择器与时间选择器的「确定」按钮文案。
  String okLabel(WidgetTester tester) => MaterialLocalizations.of(
        tester.element(find.byType(EventPropertiesPage)),
      ).okButtonLabel;

  /// 点「期望时刻」卡片里的日历按钮 → 两个选择器都按确定。
  ///
  /// 期望时刻卡片排在截止时刻卡片之前，所以 `.first` 就是它；两个选择器的初值都是
  /// 库里已有的期望时刻，于是「按确定」= 选回同一个时刻。
  Future<void> pickExpectedAt(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.edit_calendar).first);
    await settle(tester);
    await tester.tap(find.text(okLabel(tester)));
    await settle(tester);
    await tester.tap(find.text(okLabel(tester)));
    await settle(tester);
  }

  /// 点「截止时刻」卡片里的日历按钮（本片**不该**对它做冲突解析）。
  Future<void> pickDeadline(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.edit_calendar).last);
    await settle(tester);
    await tester.tap(find.text(okLabel(tester)));
    await settle(tester);
    await tester.tap(find.text(okLabel(tester)));
    await settle(tester);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byTooltip(l10nOf(tester).commonSave));
    await settle(tester);
  }

  /// 从 l10n 里拿按钮文案的前半段（「移到这块之前」），避免在测试里抄字面量。
  String moveBeforePrefix(AppLocalizations l10n) =>
      l10n.tasksDueAtConflictMoveBefore('').split('（').first;

  String moveAfterPrefix(AppLocalizations l10n) =>
      l10n.tasksDueAtConflictMoveAfter('').split('（').first;

  testWidgets('撞上忙碌块：弹警告；选「移到这块之后」→ 期望时刻落在块结束后一分钟', (tester) async {
    final db = await openDatabase();
    final id = await seedEvent(db, expectedAt: at(10));
    await seedBlock(db, startHour: 9, endHour: 11);
    await pumpPage(tester, db, id);

    await pickExpectedAt(tester);
    final l10n = l10nOf(tester);
    expect(find.text(l10n.tasksDueAtConflictTitle), findsOneWidget);

    await tester.tap(find.textContaining(moveAfterPrefix(l10n)));
    await settle(tester);
    await save(tester);

    // 9:00–11:00 的块：块结束那一刻按引擎口径仍算忙碌，再往后一分钟才空闲。
    expect(await expectedAtIn(db, id), at(11, 1).millisecondsSinceEpoch);
  });

  testWidgets('撞上忙碌块：选「移到这块之前」→ 期望时刻落在块开始前一分钟', (tester) async {
    final db = await openDatabase();
    final id = await seedEvent(db, expectedAt: at(10));
    await seedBlock(db, startHour: 9, endHour: 11);
    await pumpPage(tester, db, id);

    await pickExpectedAt(tester);
    final l10n = l10nOf(tester);
    await tester.tap(find.textContaining(moveBeforePrefix(l10n)));
    await settle(tester);
    await save(tester);

    expect(await expectedAtIn(db, id), at(8, 59).millisecondsSinceEpoch);
  });

  testWidgets('撞上忙碌块：选「保持不动」→ 保存后仍是所选时刻', (tester) async {
    final db = await openDatabase();
    final id = await seedEvent(db, expectedAt: at(10));
    await seedBlock(db, startHour: 9, endHour: 11);
    await pumpPage(tester, db, id);

    await pickExpectedAt(tester);
    await tester.tap(find.text(l10nOf(tester).tasksDueAtConflictKeep));
    await settle(tester);
    await save(tester);

    expect(await expectedAtIn(db, id), at(10).millisecondsSinceEpoch);
  });

  testWidgets('点掉警告（barrier）→ 放弃这次选择，期望时刻不动', (tester) async {
    final db = await openDatabase();
    final id = await seedEvent(db, expectedAt: at(10));
    await seedBlock(db, startHour: 9, endHour: 11);
    await pumpPage(tester, db, id);

    await pickExpectedAt(tester);
    expect(find.text(l10nOf(tester).tasksDueAtConflictTitle), findsOneWidget);

    // 点弹窗外面 = 放弃这次选择。
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    expect(find.text(l10nOf(tester).tasksDueAtConflictTitle), findsNothing);

    await save(tester);
    expect(await expectedAtIn(db, id), at(10).millisecondsSinceEpoch);
  });

  testWidgets('不撞忙碌块：不弹警告，选什么就是什么', (tester) async {
    final db = await openDatabase();
    final id = await seedEvent(db, expectedAt: at(10));
    await seedBlock(db, startHour: 12, endHour: 13);
    await pumpPage(tester, db, id);

    await pickExpectedAt(tester);
    expect(find.text(l10nOf(tester).tasksDueAtConflictTitle), findsNothing);

    await save(tester);
    expect(await expectedAtIn(db, id), at(10).millisecondsSinceEpoch);
  });

  testWidgets('开放块（available=true）不算占用：不弹警告', (tester) async {
    final db = await openDatabase();
    final id = await seedEvent(db, expectedAt: at(10));
    await seedBlock(db, startHour: 9, endHour: 11, available: true);
    await pumpPage(tester, db, id);

    await pickExpectedAt(tester);
    expect(find.text(l10nOf(tester).tasksDueAtConflictTitle), findsNothing);

    await save(tester);
    expect(await expectedAtIn(db, id), at(10).millisecondsSinceEpoch);
  });

  testWidgets('改「截止时刻」不触发冲突警告：本片只挪期望时刻', (tester) async {
    final db = await openDatabase();
    final id = await seedEvent(db, expectedAt: at(10));
    await seedBlock(db, startHour: 9, endHour: 11);
    await pumpPage(tester, db, id);

    await pickDeadline(tester);
    expect(find.text(l10nOf(tester).tasksDueAtConflictTitle), findsNothing);

    await save(tester);
    // 期望时刻没有被这次操作碰过。
    expect(await expectedAtIn(db, id), at(10).millisecondsSinceEpoch);
  });
}
