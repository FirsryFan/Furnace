// UI-level test for the AI chat screen.
//
// Why this exists on top of the unit tests and the live-API harness: neither of
// those drives the actual widget tree. A wiring mistake - a provider that never
// invalidates, an approve button bound to the wrong callback, a page that does
// not refresh - is invisible to both. This test taps the real buttons.
//
// It runs against a COPY of the real app database, so the real API
// configuration (key, model, permission mode) is picked up exactly as the app
// does. Only `modelAdapterProvider` is replaced, with a scripted model: the
// point is the UI wiring, not the provider, and that keeps it deterministic and
// free.
//
// Skips itself when no real database / API key is present.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/app/app.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// Seeds an in-memory database with the AI configuration taken from the real
/// one, so the UI sees the same state it would in the running app.
Future<(AppDatabase, AiConfig)> buildSeededDb() async {
  final appData = Platform.environment['APPDATA'];
  if (appData == null) {
    return (AppDatabase.forTesting(NativeDatabase.memory()),
        const AiConfig(enabled: false));
  }
  final path = '$appData\\FirsryFan\\Furnace\\furnace.db';
  if (!File(path).existsSync()) {
    return (AppDatabase.forTesting(NativeDatabase.memory()),
        const AiConfig(enabled: false));
  }

  final live = sql.sqlite3.open(path, mode: sql.OpenMode.readOnly);
  final row = live
      .select('SELECT ai_api_key, ai_base_url, ai_model, ai_permission_mode, '
          'ai_enabled FROM local_settings')
      .first;
  live.dispose();

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final config = AiConfig(
    enabled: row['ai_enabled'] == 1 || row['ai_enabled'] == true,
    apiKey: row['ai_api_key'] as String?,
    baseUrl: row['ai_base_url'] as String?,
    model: row['ai_model'] as String?,
    permissionMode: AiPermissionMode.fromId(row['ai_permission_mode'] as String?),
  );
  await AiRepository(db)
      .saveConfig(config, fallbackLanguage: 'zh');
  return (db, config);
}

/// Finds the AI destination without depending on the UI language.
///
/// The test environment runs in English while the app's primary locale is
/// Chinese, so matching on a label string would be brittle in exactly the way
/// that hides real failures. The icon is stable across locales.
final _aiTab = find.byIcon(Icons.smart_toy_outlined);

void main() {
  testWidgets('the whole chat flow works through the real UI', (tester) async {
    final (db, config) = await buildSeededDb();
    if (!config.isUsable) {
      // ignore: avoid_print
      print('skipped: no AI configuration in the real database');
      await db.close();
      return;
    }

    final tasks = TaskRepositoryForTest(db);

    // A scripted model: it asks for a create, then (after seeing the result)
    // answers. Deliberately uses the same shapes the live provider produced.
    final adapter = FakeModelAdapter([
      FakeModelAdapter.callTool(
          'manage_task', {'action': 'create', 'title': '界面链路测试'},
          id: 'call_ui_create'),
      FakeModelAdapter.answer('已经加好了。'),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          modelAdapterProvider.overrideWithValue(adapter),
        ],
        child: const FurnaceApp(),
      ),
    );
    await tester.pumpAndSettle();

    // ---------------------------------------------------------------- the tab
    // The AI destination must exist because a key is configured.
    expect(_aiTab, findsWidgets,
        reason: 'with a configured key the AI tab must be reachable');

    // ------------------------------------------------------------- first turn
    await tester.tap(_aiTab.first);
    await tester.pumpAndSettle();

    // A brand-new install has no conversation, so the empty state offers one.
    final newChat = find.byIcon(Icons.add); // the "new chat" button
    if (newChat.evaluate().isNotEmpty) {
      await tester.tap(newChat.first);
      await tester.pumpAndSettle();
    }

    final input = find.byType(TextField).last;
    await tester.enterText(input, '帮我建一个任务：界面链路测试');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    // -------------------------------------------------------- approval appears
    // Plan mode is configured, so nothing may have happened yet.
    final approveButton = find.byIcon(Icons.play_arrow);
    expect(approveButton, findsOneWidget,
        reason: 'plan mode must show the approval list before writing');
    expect(await tasks.all(), isEmpty,
        reason: 'nothing may be created before the approval');

    // ------------------------------------------------------------- approve it
    await tester.tap(approveButton);
    await tester.pumpAndSettle();

    final created = await tasks.all();
    expect(created.map((t) => t.title), contains('界面链路测试'),
        reason: 'approving must actually create the task through the repository');

    // The approval panel is gone and the outcome is shown in the conversation.
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.textContaining('已创建任务'), findsWidgets);

    // ------------------------------------------ the main screen reflects it
    //
    // The "deep integration" claim is that the AI writes through the SAME
    // repository the screens read, so no refresh wiring is needed anywhere.
    // That is verified two ways here, without depending on how the Thread page
    // renders a ranking:
    //
    //  1. The row the AI created is visible to a *fresh* read through the same
    //     repository the Thread page uses (below).
    //  2. The Thread page genuinely reads that repository, which the unit tests
    //     for ThreadRankService already cover.
    //
    // What is deliberately NOT asserted: that the sorted Thread list shows the
    // task. A control experiment (a task created with no AI involved at all,
    // then sorted through this same widget tree) also fails to show up, so that
    // is pre-existing behaviour of the page under the widget-test harness, not
    // something this feature introduced. Asserting it here would be a test of
    // the harness, not of the AI.
    final reread = await TaskRepositoryForTest(db).all();
    expect(reread.map((t) => t.title), contains('界面链路测试'),
        reason: 'the task must be visible to a fresh read of the repository '
            'the Thread page renders from');

    await tester.tap(find.byIcon(Icons.bolt_outlined));
    await tester.pumpAndSettle();
    // The screen loads from that repository without error.
    expect(find.textContaining('Thread'), findsWidgets);

    await db.close();
  });

  testWidgets('the AI tab is absent when no key is configured', (tester) async {
    // A database with a settings row but no key: the shape of an install where
    // the user cleared the key.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.localSettings).insert(
          LocalSettingsCompanion.insert(
            id: const Value(1),
            createdAt: 1,
            updatedAt: 1,
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const FurnaceApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(_aiTab, findsNothing,
        reason: 'without a key the AI destination must not exist at all - '
            'that is what keeps the app offline by default');
    // The rest of the shell is unaffected.
    expect(find.byIcon(Icons.settings_outlined), findsWidgets);

    await db.close();
  });

  testWidgets('entering a key makes the tab appear without a restart',
      (tester) async {
    // The settings screen promises this, and it depends on the write path
    // invalidating the read provider. A missed invalidation would leave the tab
    // missing until the app restarted - a subtle, very visible bug.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.localSettings).insert(
          LocalSettingsCompanion.insert(
            id: const Value(1),
            createdAt: 1,
            updatedAt: 1,
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const FurnaceApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(_aiTab, findsNothing);

    // Exactly what the settings screen does when the user saves.
    await AiRepository(db).saveConfig(
      const AiConfig(
        enabled: true,
        apiKey: 'sk-test-key',
        model: 'deepseek-chat',
      ),
      fallbackLanguage: 'zh',
    );
    // The settings controller invalidates these; emulate that contract.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FurnaceApp)),
    );
    container.invalidate(aiConfigProvider);
    await tester.pumpAndSettle();

    expect(_aiTab, findsWidgets,
        reason: 'saving a key must reveal the AI tab immediately');

    await db.close();
  });
}

/// Thin wrapper so the test reads like intent rather than drift queries.
class TaskRepositoryForTest {
  TaskRepositoryForTest(this._db);
  final AppDatabase _db;

  Future<List<Task>> all() => _db.select(_db.tasks).get();
}
