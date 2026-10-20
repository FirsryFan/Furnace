/// 复习提醒在应用外壳上的两个自动触发点：启动首帧、从后台回到前台。
///
/// 通知本身不在单测里验证（那是系统插件），这里守的是「外壳真的会去重排」
/// 这件事：用真的 `ReviewReminderService`（内存库 + fake notifier）替换
/// provider，记录 notifier 的 cancel / schedule 调用。
library;

import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/app/shell/home_shell.dart';
import 'package:furnace/core/notifications/reminder_notifier.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/anki/application/review_reminder_service.dart';
import 'package:furnace/l10n/app_localizations.dart';

class _RecordingNotifier implements ReminderNotifier {
  final List<String> calls = <String>[];

  @override
  Future<bool> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    calls.add('schedule');
    return true;
  }

  @override
  Future<void> cancelReminder(int id) async {
    calls.add('cancel');
  }
}

void main() {
  testWidgets('启动首帧重排一次复习提醒，回到前台再排一次', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final notifier = _RecordingNotifier();
    final service = ReviewReminderService(
      settings: SettingsRepository(db),
      anki: AnkiRepository(db),
      notifier: notifier,
      clock: () => DateTime(2026, 10, 21, 9),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          aiEnabledProvider.overrideWithValue(false),
          reviewReminderServiceProvider.overrideWith((ref) => service),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      notifier.calls,
      ['cancel'],
      reason: '提醒默认是关的：refresh 仍会跑一次，把上次可能排上的通知撤掉',
    );

    notifier.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(notifier.calls, ['cancel'], reason: '回到前台再重排一次');
  });
}
