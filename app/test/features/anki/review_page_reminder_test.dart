/// 复习页在「这一轮做完」时重排复习提醒。
///
/// 守的是行为而不是通知本身：队列清空说明今天没有到期卡了，提醒必须从
/// 「今天/现在」改成下一次到期（应用层 `ReviewReminderService` 负责算）。
/// 这里用真服务 + fake notifier，只看它到底有没有被叫到、被叫了几次。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/core/notifications/reminder_notifier.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/features/anki/application/review_reminder_service.dart';
import 'package:furnace/features/anki/presentation/review_page.dart';
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
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('一轮复习做完后重排一次提醒', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final anki = AnkiRepository(db);
    final point = await anki.createKnowledgePoint(
      title: '光合作用的意义',
      content: '把光能转成化学能。',
    );
    final template = await anki.createTemplate(
      knowledgePointId: point.id,
      type: 'essay',
      question: '光合作用的意义是什么？',
      answer: '把光能转成化学能。',
    );
    await anki.getOrCreateCardState(template.id);

    final notifier = _RecordingNotifier();
    final service = ReviewReminderService(
      settings: SettingsRepository(db),
      anki: anki,
      notifier: notifier,
      clock: () => DateTime(2026, 10, 21, 9),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          reviewReminderServiceProvider.overrideWith((ref) => service),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ReviewPage()),
        ),
      ),
    );
    await settle(tester);
    expect(notifier.calls, isEmpty, reason: '刚开始复习时不该重排');

    // essay 只能自判：提交 → 自己判「记得」。一张卡答对就进结束态。
    // （答错会被 ForcedLoop 插回队列，队列反而变长，不适合验证结束态。）
    await tester.tap(find.byTooltip('提交'));
    await settle(tester);
    await tester.tap(find.byTooltip('记得'));
    await settle(tester);

    expect(
      notifier.calls,
      ['cancel'],
      reason: '提醒默认关着：结束时仍会跑一次 refresh，把上次的通知撤掉',
    );
  });
}
