import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/domain/services/thread/thread_event_kind.dart';
import 'package:furnace/domain/services/thread/thread_status.dart';
import 'package:furnace/features/tasks/presentation/task_detail_page.dart';
import 'package:furnace/features/tasks/presentation/tasks_page.dart';
import 'package:furnace/features/tasks/presentation/widgets/task_status_actions.dart';
import 'package:furnace/features/thread/application/thread_rank_service.dart';
import 'package:furnace/features/thread/presentation/thread_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// task-76 / task-90：提交 / 卡住 / 跳过 / 恢复的 UI 入口。
///
/// 覆盖：任务页的「待办 / 已完成 / 卡住·跳过」分段（blocked/skipped 不再画成
/// 未勾选的待办）、按状态可用的菜单与按钮、二次确认、详情页入口、Thread 页入口
/// （含归档视图里 blocked/skipped 的「恢复」），以及旧勾选行为（todo↔done）不回归
/// ——done→todo 现在也落一条 reopened 事件。
void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<(ProviderContainer, AppDatabase)> pump(
    WidgetTester tester,
    Widget Function() home, {
    required Future<void> Function(TaskRepository) seed,
    bool sortThread = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(TaskRepository(db));
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    if (sortThread) {
      await container.read(threadFeedProvider.notifier).sort();
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home(),
        ),
      ),
    );
    await settle(tester);
    return (container, db);
  }

  Future<List<String>> eventKindsOf(AppDatabase db, String taskId) async {
    final rows = await (db.select(db.threadEvents)
          ..where((e) => e.taskId.equals(taskId)))
        .get();
    return [for (final row in rows) row.kind]..sort();
  }

  Future<void> confirmDialog(WidgetTester tester) async {
    final dialog = find.byKey(const ValueKey('task-status-confirm-submitted'));
    expect(dialog, findsOneWidget);
    await tester.tap(
      find.descendant(of: dialog, matching: find.text(zh.commonConfirm)),
    );
    await settle(tester);
  }

  group('任务页：三段列表', () {
    testWidgets('blocked/skipped 出现在「卡住 / 跳过」段，不再画成待办圆圈', (tester) async {
      late String blockedId;
      late String skippedId;
      await pump(
        tester,
        () => const TasksPage(),
        seed: (tasks) async {
          await tasks.createTask(title: '待办的事');
          final done = await tasks.createTask(title: '做完的事');
          await tasks.completeTask(done.id);
          blockedId = (await tasks.createTask(title: '卡住的事')).id;
          await tasks.markTaskStuck(blockedId);
          skippedId = (await tasks.createTask(title: '跳过的事')).id;
          await tasks.skipTask(skippedId);
        },
      );

      expect(find.text(zh.tasksStatusSectionTodo), findsOneWidget);
      expect(find.text(zh.tasksStatusSectionDone), findsOneWidget);
      expect(find.text(zh.tasksStatusSectionArchived), findsOneWidget);

      // 只有那一条真正的待办画成"未完成圆圈"。
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);

      // 卡住/跳过行有自己的状态图标，不再冒充待办。
      expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_outlined), findsOneWidget);

      // 状态写进副标题，用户能看到为什么它在最后一段。
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, '卡住的事'),
          matching: find.text('中 · ${zh.tasksStatusBlocked}'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, '跳过的事'),
          matching: find.text('中 · ${zh.tasksStatusSkipped}'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('状态菜单按状态可用：blocked 可跳过或恢复', (tester) async {
      late String blockedId;
      await pump(
        tester,
        () => const TasksPage(),
        seed: (tasks) async {
          blockedId = (await tasks.createTask(title: '卡住了')).id;
          await tasks.markTaskStuck(blockedId);
        },
      );

      await tester.tap(find.byKey(ValueKey('task-status-menu-$blockedId')));
      await settle(tester);

      PopupMenuItem<TaskStatusAction> item(ThreadEventKind kind) =>
          tester.widget<PopupMenuItem<TaskStatusAction>>(
            find.byKey(ValueKey('task-status-menu-item-${kind.id}')),
          );

      expect(item(ThreadEventKind.submitted).enabled, isFalse);
      expect(item(ThreadEventKind.stuck).enabled, isFalse);
      expect(item(ThreadEventKind.skipped).enabled, isTrue);
      expect(item(ThreadEventKind.reopened).enabled, isTrue,
          reason: 'task-90：卡住的任务可以在行菜单里恢复');
    });

    testWidgets('从菜单跳过：二次确认后才写库，事件是 skipped', (tester) async {
      late String blockedId;
      final (_, db) = await pump(
        tester,
        () => const TasksPage(),
        seed: (tasks) async {
          blockedId = (await tasks.createTask(title: '准备跳过')).id;
          await tasks.markTaskStuck(blockedId);
        },
      );

      await tester.tap(find.byKey(ValueKey('task-status-menu-$blockedId')));
      await settle(tester);
      await tester.tap(find.byKey(
          const ValueKey('task-status-menu-item-skipped')));
      await settle(tester);

      // 确认框出现，点「取消」什么都不写。
      expect(
        find.byKey(const ValueKey('task-status-confirm-skipped')),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, zh.commonCancel));
      await settle(tester);
      expect(
        (await TaskRepository(db).getTaskById(blockedId))!.status,
        ThreadStatus.blocked.id,
      );

      // 再来一次，点「确认」才落库。
      await tester.tap(find.byKey(ValueKey('task-status-menu-$blockedId')));
      await settle(tester);
      await tester.tap(find.byKey(
          const ValueKey('task-status-menu-item-skipped')));
      await settle(tester);
      final dialog = find.byKey(const ValueKey('task-status-confirm-skipped'));
      await tester.tap(
        find.descendant(of: dialog, matching: find.text(zh.commonConfirm)),
      );
      await settle(tester);

      expect(
        (await TaskRepository(db).getTaskById(blockedId))!.status,
        ThreadStatus.skipped.id,
      );
      expect(await eventKindsOf(db, blockedId),
          contains(ThreadEventKind.skipped.id));
      expect(await db.select(db.completionLogs).get(), isEmpty);
    });

    testWidgets('旧勾选行为不回归：todo→done 写完成历史，done→todo 可重开',
        (tester) async {
      late String todoId;
      final (_, db) = await pump(
        tester,
        () => const TasksPage(),
        seed: (tasks) async {
          todoId = (await tasks.createTask(title: '勾它')).id;
        },
      );

      await tester.tap(find.byIcon(Icons.radio_button_unchecked));
      await settle(tester);
      expect(
        (await TaskRepository(db).getTaskById(todoId))!.status,
        ThreadStatus.done.id,
      );
      expect(await db.select(db.completionLogs).get(), hasLength(1));

      await tester.tap(find.byIcon(Icons.check_circle));
      await settle(tester);
      expect(
        (await TaskRepository(db).getTaskById(todoId))!.status,
        ThreadStatus.todo.id,
      );
      // done → todo 现在也走 reopened 事件（task-90），完成历史保留。
      expect(await eventKindsOf(db, todoId),
          contains(ThreadEventKind.reopened.id));
      expect(await db.select(db.completionLogs).get(), hasLength(1));
    });

    testWidgets('blocked 行首图标是「恢复」入口：取消不写库，确认后回到待办',
        (tester) async {
      late String blockedId;
      final (_, db) = await pump(
        tester,
        () => const TasksPage(),
        seed: (tasks) async {
          blockedId = (await tasks.createTask(title: '卡住要恢复')).id;
          await tasks.markTaskStuck(blockedId);
        },
      );

      // 行首图标（不是菜单）就是恢复入口。
      await tester.tap(find.byIcon(Icons.pause_circle_outline));
      await settle(tester);
      final dialog =
          find.byKey(const ValueKey('task-status-confirm-reopened'));
      expect(dialog, findsOneWidget);
      await tester.tap(
        find.descendant(of: dialog, matching: find.text(zh.commonCancel)),
      );
      await settle(tester);
      expect(
        (await TaskRepository(db).getTaskById(blockedId))!.status,
        ThreadStatus.blocked.id,
      );
      expect(
        await eventKindsOf(db, blockedId),
        isNot(contains(ThreadEventKind.reopened.id)),
        reason: '点取消不能写 reopened',
      );

      await tester.tap(find.byIcon(Icons.pause_circle_outline));
      await settle(tester);
      final confirm =
          find.byKey(const ValueKey('task-status-confirm-reopened'));
      await tester.tap(
        find.descendant(of: confirm, matching: find.text(zh.commonConfirm)),
      );
      await settle(tester);

      expect(
        (await TaskRepository(db).getTaskById(blockedId))!.status,
        ThreadStatus.todo.id,
      );
      expect(await eventKindsOf(db, blockedId),
          contains(ThreadEventKind.reopened.id));
      expect(find.byIcon(Icons.pause_circle_outline), findsNothing,
          reason: '恢复后回到待办段，不再是卡住图标');
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    });

    testWidgets('skipped 行菜单的「恢复」可用并生效', (tester) async {
      late String skippedId;
      final (_, db) = await pump(
        tester,
        () => const TasksPage(),
        seed: (tasks) async {
          skippedId = (await tasks.createTask(title: '跳过要恢复')).id;
          await tasks.skipTask(skippedId);
        },
      );

      await tester.tap(find.byKey(ValueKey('task-status-menu-$skippedId')));
      await settle(tester);
      final item = tester.widget<PopupMenuItem<TaskStatusAction>>(
        find.byKey(const ValueKey('task-status-menu-item-reopened')),
      );
      expect(item.enabled, isTrue);
      await tester.tap(
        find.byKey(const ValueKey('task-status-menu-item-reopened')),
      );
      await settle(tester);
      final dialog =
          find.byKey(const ValueKey('task-status-confirm-reopened'));
      expect(dialog, findsOneWidget);
      await tester.tap(
        find.descendant(of: dialog, matching: find.text(zh.commonConfirm)),
      );
      await settle(tester);

      expect(
        (await TaskRepository(db).getTaskById(skippedId))!.status,
        ThreadStatus.todo.id,
      );
      expect(await eventKindsOf(db, skippedId),
          contains(ThreadEventKind.reopened.id));
    });
  });

  group('任务详情页：三个按钮按状态可用', () {
    testWidgets('提交不改状态；卡住后「跳过 / 恢复」可点', (tester) async {
      late String taskId;
      final (_, db) = await pump(
        tester,
        () => TaskDetailPage(taskId: taskId),
        seed: (tasks) async {
          taskId = (await tasks.createTask(title: '详情里的任务')).id;
        },
      );

      expect(find.textContaining(zh.tasksStatus), findsWidgets);
      for (final action in TaskStatusAction.values) {
        final button = tester.widget<TextButton>(
          find.byKey(ValueKey('task-status-${action.eventKind.id}')),
        );
        // todo 的任务「恢复」没有来源状态；其余三个动作都可用。
        expect(
          button.onPressed,
          action == TaskStatusAction.reopen ? isNull : isNotNull,
          reason: action.name,
        );
      }

      // 提交：确认后状态不变，事件 submitted。
      await tester.tap(find.byKey(const ValueKey('task-status-submitted')));
      await settle(tester);
      await confirmDialog(tester);
      expect(
        (await TaskRepository(db).getTaskById(taskId))!.status,
        ThreadStatus.todo.id,
      );
      expect(await eventKindsOf(db, taskId),
          contains(ThreadEventKind.submitted.id));

      // 卡住：状态变 blocked，提交/卡住按钮都应禁用，跳过仍可用。
      await tester.tap(find.byKey(const ValueKey('task-status-stuck')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('task-status-confirm-stuck')),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, zh.commonConfirm));
      await settle(tester);
      expect(
        (await TaskRepository(db).getTaskById(taskId))!.status,
        ThreadStatus.blocked.id,
      );

      TextButton buttonOf(ThreadEventKind kind) => tester.widget<TextButton>(
            find.byKey(ValueKey('task-status-${kind.id}')),
          );
      expect(buttonOf(ThreadEventKind.submitted).onPressed, isNull);
      expect(buttonOf(ThreadEventKind.stuck).onPressed, isNull);
      expect(buttonOf(ThreadEventKind.skipped).onPressed, isNotNull);
      // task-90：卡住之后「恢复」可用（blocked → todo）。
      expect(buttonOf(ThreadEventKind.reopened).onPressed, isNotNull);
    });
  });

  group('Thread 页：事件行入口', () {
    testWidgets('菜单能提交；提交只追加事件、不改状态', (tester) async {
      late String taskId;
      final (_, db) = await pump(
        tester,
        () => const ThreadPage(),
        sortThread: true,
        seed: (tasks) async {
          taskId = (await tasks.createTask(title: '事件流里的任务')).id;
        },
      );

      // 行内菜单；AppBar 与状态栏上也有「编辑」提示，所以按行 key 定位。
      await tester.tap(find.byKey(ValueKey('event-actions-$taskId')));
      await settle(tester);
      expect(find.text(zh.tasksSubmit), findsOneWidget);
      expect(find.text(zh.tasksMarkStuck), findsOneWidget);
      expect(find.text(zh.tasksSkip), findsOneWidget);

      await tester.tap(find.text(zh.tasksSubmit));
      await settle(tester);
      await confirmDialog(tester);

      expect(
        (await TaskRepository(db).getTaskById(taskId))!.status,
        ThreadStatus.todo.id,
      );
      expect(await eventKindsOf(db, taskId),
          contains(ThreadEventKind.submitted.id));
    });

    testWidgets('旧完成行为不回归：行首圆圈完成并写完成历史', (tester) async {
      late String taskId;
      final (_, db) = await pump(
        tester,
        () => const ThreadPage(),
        sortThread: true,
        seed: (tasks) async {
          taskId = (await tasks.createTask(title: '要完成的任务')).id;
        },
      );

      await tester.tap(find.byIcon(Icons.radio_button_unchecked));
      await settle(tester);

      expect(
        (await TaskRepository(db).getTaskById(taskId))!.status,
        ThreadStatus.done.id,
      );
      expect(await db.select(db.completionLogs).get(), hasLength(1));
    });

    testWidgets('卡住后行从「全部」列表消失（不再显示为待办）', (tester) async {
      late String taskId;
      final (_, db) = await pump(
        tester,
        () => const ThreadPage(),
        sortThread: true,
        seed: (tasks) async {
          taskId = (await tasks.createTask(title: '会卡住的任务')).id;
        },
      );
      expect(find.text('会卡住的任务'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('event-actions-$taskId')));
      await settle(tester);
      await tester.tap(find.text(zh.tasksMarkStuck));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, zh.commonConfirm));
      await settle(tester);

      expect(
        (await TaskRepository(db).getTaskById(taskId))!.status,
        ThreadStatus.blocked.id,
      );
      expect(find.text('会卡住的任务'), findsNothing);
    });

    testWidgets('归档视图里 blocked/skipped 行有「恢复」（Thread 行入口）',
        (tester) async {
      late String blockedId;
      late String skippedId;
      final (_, db) = await pump(
        tester,
        () => const ThreadPage(),
        sortThread: true,
        seed: (tasks) async {
          blockedId = (await tasks.createTask(title: 'Thread 卡住')).id;
          await tasks.markTaskStuck(blockedId);
          skippedId = (await tasks.createTask(title: 'Thread 跳过')).id;
          await tasks.skipTask(skippedId);
        },
      );

      await tester.tap(find.text(zh.threadArchive));
      await settle(tester);

      expect(find.byKey(ValueKey('archived-restore-$blockedId')),
          findsOneWidget);
      expect(find.byKey(ValueKey('archived-restore-$skippedId')),
          findsOneWidget);

      await tester.tap(find.byKey(ValueKey('archived-restore-$skippedId')));
      await settle(tester);
      final dialog =
          find.byKey(const ValueKey('task-status-confirm-reopened'));
      expect(dialog, findsOneWidget);
      await tester.tap(
        find.descendant(of: dialog, matching: find.text(zh.commonConfirm)),
      );
      await settle(tester);

      expect(
        (await TaskRepository(db).getTaskById(skippedId))!.status,
        ThreadStatus.todo.id,
      );
      expect(await eventKindsOf(db, skippedId),
          contains(ThreadEventKind.reopened.id));
      expect(await db.select(db.completionLogs).get(), isEmpty);
    });
  });
}
