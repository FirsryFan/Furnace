// 设置页「复习提醒」：开关 + 每天提醒时刻。
//
// 这条链路跨三层：设置页写库（schema v28 的两列）→ ReviewReminderService 重排
// 系统通知 → 系统没给通知权限时必须明确告诉用户。测试用内存库 + fake
// notifier，不碰插件/系统通知；固定时钟让「下一次提醒」可断言。
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
import 'package:furnace/features/settings/presentation/review_reminder_section.dart';
import 'package:furnace/features/settings/presentation/settings_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// 测试用 fake：只记录调用，不碰任何插件/系统通知。
class _FakeReminderNotifier implements ReminderNotifier {
  /// 系统是否给通知权限（scheduleReminder 的返回值）。
  bool permission = true;

  /// 取消过的通知 id。
  final List<int> cancelled = <int>[];

  /// 排过程的通知，按调用顺序。
  final List<({int id, String title, String body, DateTime when})> scheduled =
      <({int id, String title, String body, DateTime when})>[];

  @override
  Future<bool> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    scheduled.add((id: id, title: title, body: body, when: when));
    return permission;
  }

  @override
  Future<void> cancelReminder(int id) async {
    cancelled.add(id);
  }
}

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late AnkiRepository anki;
  late _FakeReminderNotifier notifier;
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
    anki = AnkiRepository(db);
    notifier = _FakeReminderNotifier();
    // 设置仓储只 update id=1 那一行；不先建行，写开关会静默改 0 行。
    await settings.ensureSettings();
  });

  tearDown(() => db.close());

  /// 固定时钟：本地 2026-10-21 19:30，晚于默认 20:00 之前，便于断言。
  DateTime now() => DateTime(2026, 10, 21, 19, 30);

  Future<void> pumpSettings(WidgetTester tester) async {
    // 设置页是一长列 tile：视口够高才保证「复习提醒」这一行被构建出来。
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = ReviewReminderService(
      settings: settings,
      anki: anki,
      notifier: notifier,
      clock: now,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          reviewReminderServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.byKey(reviewReminderSectionKey));
    await tester.pumpAndSettle();
    expect(find.byKey(reviewReminderDialogKey), findsOneWidget);
  }

  Future<void> closeDialog(WidgetTester tester) async {
    await tester.tap(find.descendant(
      of: find.byKey(reviewReminderDialogKey),
      matching: find.text(zh.commonClose),
    ));
    await tester.pumpAndSettle();
  }

  /// 一张「已经复习过、已经到期」的卡。
  Future<void> seedDueCard() async {
    final point = await anki.createKnowledgePoint(
      title: '动量守恒',
      content: '系统不受外力时总动量不变。',
    );
    final state = await anki.getOrCreateUnitCardState(point.id, 'essay');
    await anki.updateUnitCardState(
      state.id,
      repetitions: 3,
      stability: 5,
      difficulty: 5,
      dueAt: now().subtract(const Duration(days: 3)).millisecondsSinceEpoch,
      lastReviewedAt:
          now().subtract(const Duration(days: 6)).millisecondsSinceEpoch,
    );
  }

  testWidgets('默认关闭：设置页显示「复习提醒 / 关」', (tester) async {
    await pumpSettings(tester);

    expect(find.byKey(reviewReminderSectionKey), findsOneWidget);
    expect(find.text(zh.reviewReminderSettingTitle), findsOneWidget);
    expect(find.text(zh.reviewReminderSettingOff), findsOneWidget);
    expect(find.text(zh.reviewReminderSettingOn('20:00')), findsNothing);
  });

  testWidgets('打开开关：写库 true，副标题变「每天 20:00 提醒」，出现时间行', (tester) async {
    await pumpSettings(tester);
    await openDialog(tester);

    // 关闭时不该出现时间行。
    expect(find.byKey(reviewReminderTimeTileKey), findsNothing);

    await tester.tap(find.byKey(reviewReminderSwitchKey));
    await tester.pumpAndSettle();

    expect(await settings.getReviewReminderEnabled(), isTrue);
    // 没选过时间：库里保持 NULL，界面按域层默认 20:00 显示。
    expect(await settings.getReviewReminderMinutes(), isNull);
    expect(find.byKey(reviewReminderTimeTileKey), findsOneWidget);
    expect(find.text(reviewReminderMinutesText(20 * 60)), findsOneWidget);

    await closeDialog(tester);
    expect(find.text(zh.reviewReminderSettingOn('20:00')), findsOneWidget);
    expect(find.text(zh.reviewReminderSettingOff), findsNothing);
  });

  testWidgets('关闭开关：库写回 false，并取消已排的通知', (tester) async {
    await settings.updateReviewReminderEnabled(true);
    await pumpSettings(tester);
    await openDialog(tester);

    await tester.tap(find.byKey(reviewReminderSwitchKey));
    await tester.pumpAndSettle();

    expect(await settings.getReviewReminderEnabled(), isFalse);
    expect(notifier.cancelled, contains(kReviewReminderNotificationId));
    expect(find.byKey(reviewReminderTimeTileKey), findsNothing);
  });

  testWidgets('有到期卡但系统没给通知权限：SnackBar 明说提醒不会弹', (tester) async {
    notifier.permission = false;
    await seedDueCard();
    await pumpSettings(tester);
    await openDialog(tester);

    await tester.tap(find.byKey(reviewReminderSwitchKey));
    await tester.pumpAndSettle();

    expect(notifier.scheduled, isNotEmpty);
    expect(notifier.scheduled.single.id, kReviewReminderNotificationId);
    expect(find.text(zh.reviewReminderPermissionDenied), findsOneWidget);
  });

  group('reviewReminderMinutesText', () {
    test('0 / 1230 / 1439 → 00:00 / 20:30 / 23:59', () {
      expect(reviewReminderMinutesText(0), '00:00');
      expect(reviewReminderMinutesText(20 * 60 + 30), '20:30');
      expect(reviewReminderMinutesText(1439), '23:59');
    });

    test('越界值按边界显示，不抛异常', () {
      expect(reviewReminderMinutesText(-5), '00:00');
      expect(reviewReminderMinutesText(1440), '23:59');
    });
  });
}
