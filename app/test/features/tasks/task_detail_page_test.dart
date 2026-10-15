import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/tasks/presentation/task_detail_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// Q23：任务的截止时刻落在忙碌日程块里时，弹窗警告 + 「移到这块之前/之后」。
///
/// 这些测试故意**只走 UI**（点编辑 → 点截止时间 → 日期/时间都按确定），
/// 因为要钉住的正是「选完时间到落库之间」这一段行为：
///   * 撞上忙碌块 → 出现警告，移动动作落到引擎判定为空闲的最近时刻；
///   * 不撞（空闲 / 开放块）→ 不打扰用户，选什么就是什么；
///   * 整天被重复忙碌块占满 → 两个动作禁用并如实说明，不硬造时刻。
///
/// 判定的口径不在这里重写：按钮上显示的候选时刻由 `ScheduleConflict` 给出，
/// 领域层 `app/test/domain/services/scheduling/schedule_conflict_test.dart`
/// 已经把「半开区间 / 首尾相接不算 / ±1 分钟探测 / 重复规则展开」钉在引擎口径上。
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

  Future<String> seedTask(AppDatabase db, {DateTime? dueAt}) async {
    final task = await TaskRepository(db).createTask(
      title: '写物理作业',
      dueAt: dueAt?.millisecondsSinceEpoch,
    );
    return task.id;
  }

  Future<void> seedBlock(
    AppDatabase db, {
    required int startHour,
    required int endHour,
    String title = '上课',
    bool available = false,
    String? repeatRule,
  }) async {
    await TimeBlockRepository(db).createTimeBlock(
      title: title,
      startAt: at(startHour).millisecondsSinceEpoch,
      endAt: at(endHour).millisecondsSinceEpoch,
      available: available,
      repeatRule: repeatRule,
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
          home: TaskDetailPage(taskId: taskId),
        ),
      ),
    );
    await settle(tester);
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(TaskDetailPage)));

  /// 从库里读回 dueAt（毫秒）。
  Future<int?> dueAtIn(AppDatabase db, String taskId) async {
    final task = await TaskRepository(db).getTaskById(taskId);
    return task?.dueAt;
  }

  /// 打开编辑框 → 点「截止时间」→ 日期与时间两个选择器都按确定。
  Future<void> pickDueAt(WidgetTester tester) async {
    final l10n = l10nOf(tester);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, l10n.tasksDueAt));
    await settle(tester);
    final ok = MaterialLocalizations.of(
      tester.element(find.byType(TaskDetailPage)),
    ).okButtonLabel;
    await tester.tap(find.text(ok));
    await settle(tester);
    await tester.tap(find.text(ok));
    await settle(tester);
  }

  /// 从 l10n 里拿按钮文案的前半段（「移到这块之前」），避免在测试里抄字面量。
  String moveBeforePrefix(AppLocalizations l10n) =>
      l10n.tasksDueAtConflictMoveBefore('').split('（').first;

  String moveAfterPrefix(AppLocalizations l10n) =>
      l10n.tasksDueAtConflictMoveAfter('').split('（').first;

  Future<void> saveDialog(WidgetTester tester) async {
    await tester.tap(find.text(l10nOf(tester).commonSave));
    await settle(tester);
  }

  testWidgets('撞上忙碌块：弹警告，选「移到这块之后」→ 落在块结束后一分钟', (tester) async {
    final db = await openDatabase();
    await seedBlock(db, startHour: 9, endHour: 10);
    final taskId = await seedTask(db, dueAt: at(9));
    await pumpPage(tester, db, taskId);

    await pickDueAt(tester);
    expect(find.text(l10nOf(tester).tasksDueAtConflictTitle), findsOneWidget);

    await tester.tap(find.textContaining(moveAfterPrefix(l10nOf(tester))));
    await settle(tester);
    await saveDialog(tester);

    expect(await dueAtIn(db, taskId), at(10, 1).millisecondsSinceEpoch);
  });

  testWidgets('撞上忙碌块：选「移到这块之前」→ 落在块开始前一分钟', (tester) async {
    final db = await openDatabase();
    await seedBlock(db, startHour: 9, endHour: 10);
    final taskId = await seedTask(db, dueAt: at(9, 30));
    await pumpPage(tester, db, taskId);

    await pickDueAt(tester);
    expect(find.text(l10nOf(tester).tasksDueAtConflictTitle), findsOneWidget);

    await tester.tap(find.textContaining(moveBeforePrefix(l10nOf(tester))));
    await settle(tester);
    await saveDialog(tester);

    expect(await dueAtIn(db, taskId), at(8, 59).millisecondsSinceEpoch);
  });

  testWidgets('撞上忙碌块：选「保持不动」→ 保存后仍是所选时刻', (tester) async {
    final db = await openDatabase();
    await seedBlock(db, startHour: 9, endHour: 10);
    final taskId = await seedTask(db, dueAt: at(9, 30));
    await pumpPage(tester, db, taskId);

    await pickDueAt(tester);
    await tester.tap(find.text(l10nOf(tester).tasksDueAtConflictKeep));
    await settle(tester);
    await saveDialog(tester);

    expect(await dueAtIn(db, taskId), at(9, 30).millisecondsSinceEpoch);
  });

  testWidgets('不撞忙碌块：不弹警告，选什么就是什么', (tester) async {
    final db = await openDatabase();
    await seedBlock(db, startHour: 14, endHour: 15);
    final taskId = await seedTask(db, dueAt: at(9));
    await pumpPage(tester, db, taskId);

    await pickDueAt(tester);
    expect(find.text(l10nOf(tester).tasksDueAtConflictTitle), findsNothing);

    await saveDialog(tester);
    expect(await dueAtIn(db, taskId), at(9).millisecondsSinceEpoch);
  });

  testWidgets('开放块（available=true）不算占用：不弹警告', (tester) async {
    final db = await openDatabase();
    await seedBlock(db, startHour: 9, endHour: 10, available: true);
    final taskId = await seedTask(db, dueAt: at(9, 30));
    await pumpPage(tester, db, taskId);

    await pickDueAt(tester);
    expect(find.text(l10nOf(tester).tasksDueAtConflictTitle), findsNothing);

    await saveDialog(tester);
    expect(await dueAtIn(db, taskId), at(9, 30).millisecondsSinceEpoch);
  });

  testWidgets('整天被重复忙碌块占满：两个动作禁用并说明找不到空闲时段', (tester) async {
    final db = await openDatabase();
    await seedBlock(
      db,
      startHour: 0,
      endHour: 24,
      title: '全天满课',
      repeatRule: '{"type":"daily"}',
    );
    final taskId = await seedTask(db, dueAt: at(9));
    await pumpPage(tester, db, taskId);

    await pickDueAt(tester);
    final l10n = l10nOf(tester);
    expect(find.text(l10n.tasksDueAtConflictTitle), findsOneWidget);
    expect(find.text(l10n.tasksDueAtConflictNoFreeMoment), findsOneWidget);

    for (final prefix in [
      moveBeforePrefix(l10n),
      moveAfterPrefix(l10n),
    ]) {
      final button = tester.widget<TextButton>(
        find
            .ancestor(
              of: find.textContaining(prefix),
              matching: find.byType(TextButton),
            )
            .first,
      );
      expect(button.onPressed, isNull, reason: '找不到空闲时刻时「$prefix」不该可选');
    }
  });
}
