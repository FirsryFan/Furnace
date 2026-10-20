import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/core/notifications/reminder_notifier.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/domain/services/scheduling/review_reminder_plan.dart';
import 'package:furnace/features/anki/application/review_reminder_service.dart';

/// 测试用 fake：只记录调用，不碰任何插件/系统通知。
class _FakeReminderNotifier implements ReminderNotifier {
  /// 系统是否给通知权限（scheduleReminder 的返回值）。
  bool permission = true;

  /// 按调用顺序记录 'cancel' / 'schedule'，用来钉 cancel 先于 schedule。
  final List<String> calls = <String>[];
  final List<int> cancelled = <int>[];
  final List<({int id, String title, String body, DateTime when})> scheduled =
      <({int id, String title, String body, DateTime when})>[];

  /// 非空时下一次调用直接抛出（模拟插件异常）。
  Object? failWith;

  @override
  Future<bool> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    calls.add('schedule');
    scheduled.add((id: id, title: title, body: body, when: when));
    final Object? error = failWith;
    if (error != null) {
      throw error;
    }
    return permission;
  }

  @override
  Future<void> cancelReminder(int id) async {
    calls.add('cancel');
    cancelled.add(id);
    final Object? error = failWith;
    if (error != null) {
      throw error;
    }
  }
}

void main() {
  const int stamp = 1761000000000;

  late AppDatabase db;
  late SettingsRepository settings;
  late AnkiRepository anki;
  late _FakeReminderNotifier notifier;
  late ReviewReminderService service;

  /// 固定时钟：本地 2026-10-21 19:30（测试里可改成别的时刻）。
  late DateTime now;

  final ReviewReminderTexts texts = ReviewReminderTexts(
    title: '该复习了',
    dueNowBody: (int count) => '现在有 $count 张卡到期',
    dueSoonBody: '今天还有卡会到期',
  );

  setUp(() async {
    now = DateTime(2026, 10, 21, 19, 30);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
    anki = AnkiRepository(db);
    notifier = _FakeReminderNotifier();
    service = ReviewReminderService(
      settings: settings,
      anki: anki,
      notifier: notifier,
      clock: () => now,
    );
    await settings.ensureSettings();
    await settings.updateReviewReminderEnabled(true);
    await settings.updateReviewReminderMinutes(20 * 60);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedCard(String id, {int? dueAtMillis}) async {
    await db.into(db.cardStates).insert(
          CardStatesCompanion.insert(
            id: id,
            dueAt: Value<int?>(dueAtMillis),
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
  }

  Future<void> seedDueCard(String id) =>
      seedCard(id, dueAtMillis: now.millisecondsSinceEpoch - 60 * 1000);

  Future<void> seedCardAt(String id, DateTime when) =>
      seedCard(id, dueAtMillis: when.millisecondsSinceEpoch);

  group('开关与空计划：只取消，不排程', () {
    test('还没有设置行时视为关闭，只取消', () async {
      await db.delete(db.localSettings).go();

      final ReviewReminderOutcome outcome = await service.refresh(texts: texts);

      expect(outcome.plan.reason, ReviewReminderReason.disabled);
      expect(outcome.plan.shouldSchedule, isFalse);
      expect(outcome.scheduled, isFalse);
      expect(outcome.cancelled, isTrue);
      expect(outcome.permissionDenied, isFalse);
      expect(notifier.calls, <String>['cancel']);
      expect(notifier.cancelled, <int>[kReviewReminderNotificationId]);
    });

    test('开关关掉时即使有到期卡也只取消', () async {
      await seedDueCard('due-1');
      await settings.updateReviewReminderEnabled(false);

      final ReviewReminderOutcome outcome = await service.refresh(texts: texts);

      expect(outcome.plan.reason, ReviewReminderReason.disabled);
      expect(outcome.plan.dueCardCount, 1);
      expect(outcome.scheduled, isFalse);
      expect(outcome.permissionDenied, isFalse);
      expect(notifier.calls, <String>['cancel']);
      expect(notifier.scheduled, isEmpty);
    });

    test('没有到期卡也没有下一次到期时只取消', () async {
      final ReviewReminderOutcome outcome = await service.refresh(texts: texts);

      expect(outcome.plan.reason, ReviewReminderReason.nothingDue);
      expect(outcome.plan.shouldSchedule, isFalse);
      expect(outcome.plan.dueCardCount, 0);
      expect(outcome.scheduled, isFalse);
      expect(notifier.calls, <String>['cancel']);
    });

    test('下一次到期晚于偏好时刻时只取消', () async {
      await seedCardAt('later', DateTime(2026, 10, 21, 21));

      final ReviewReminderOutcome outcome = await service.refresh(texts: texts);

      expect(outcome.plan.reason, ReviewReminderReason.nothingDue);
      expect(outcome.scheduled, isFalse);
      expect(notifier.calls, <String>['cancel']);
    });

    test('下一次到期恰好等于偏好时刻时只取消（要严格早于才算 dueSoon）', () async {
      await seedCardAt('edge', DateTime(2026, 10, 21, 20));

      final ReviewReminderOutcome outcome = await service.refresh(texts: texts);

      expect(outcome.plan.reason, ReviewReminderReason.nothingDue);
      expect(outcome.scheduled, isFalse);
      expect(notifier.calls, <String>['cancel']);
    });
  });

  group('有到期卡：排到下一个偏好时刻', () {
    test('两张到期卡（NULL + 已过期）排今天 20:00，正文带张数、标题与保留 id 正确', () async {
      await seedCard('due-null');
      await seedDueCard('due-past');

      final ReviewReminderOutcome outcome = await service.refresh(texts: texts);

      expect(outcome.plan.reason, ReviewReminderReason.dueNow);
      expect(outcome.plan.dueCardCount, 2);
      expect(outcome.plan.when, DateTime(2026, 10, 21, 20));
      expect(outcome.scheduled, isTrue);
      expect(outcome.cancelled, isTrue);
      expect(outcome.permissionDenied, isFalse);
      expect(notifier.calls, <String>['cancel', 'schedule']);
      expect(notifier.cancelled, <int>[kReviewReminderNotificationId]);
      expect(notifier.scheduled, hasLength(1));
      final ({int id, String title, String body, DateTime when}) call =
          notifier.scheduled.single;
      expect(call.id, kReviewReminderNotificationId);
      expect(call.title, '该复习了');
      expect(call.body, '现在有 2 张卡到期');
      expect(call.when, DateTime(2026, 10, 21, 20));
    });

    test('到期时刻正好是 now 时也算到期（仓储口径是 <= now）', () async {
      await seedCardAt('exact-now', now);

      final ReviewReminderOutcome outcome = await service.refresh(texts: texts);

      expect(outcome.plan.reason, ReviewReminderReason.dueNow);
      expect(outcome.plan.dueCardCount, 1);
      expect(outcome.plan.when, DateTime(2026, 10, 21, 20));
      expect(notifier.scheduled.single.body, '现在有 1 张卡到期');
    });

    test('now 是 19:59 时仍排今天 20:00', () async {
      now = DateTime(2026, 10, 21, 19, 59);
      await seedDueCard('due-1');

      final ReviewReminderOutcome outcome = await service.refresh(texts: texts);

      expect(outcome.plan.when, DateTime(2026, 10, 21, 20));
    });

    test('now 恰好是 20:00 时排次日 20:00（偏好时刻不严格晚于 now）', () async {
      now = DateTime(2026, 10, 21, 20);
      await seedDueCard('due-1');

      final ReviewReminderOutcome outcome = await service.refresh(texts: texts);

      expect(outcome.plan.when, DateTime(2026, 10, 22, 20));
      expect(notifier.scheduled.single.when, DateTime(2026, 10, 22, 20));
    });

    test('now 是 20:01 时排次日 20:00', () async {
      now = DateTime(2026, 10, 21, 20, 1);
      await seedDueCard('due-1');

      final ReviewReminderOutcome outcome = await service.refresh(texts: texts);

      expect(outcome.plan.when, DateTime(2026, 10, 22, 20));
    });
  });

  group('没有到期卡但下一次到期更早：dueSoon', () {
    test('下一次到期在偏好时刻前时排到下一次到期，并用 dueSoonBody', () async {
      await seedCardAt('soon', DateTime(2026, 10, 21, 19, 45));

      final ReviewReminderOutcome outcome = await service.refresh(texts: texts);

      expect(outcome.plan.reason, ReviewReminderReason.dueSoon);
      expect(outcome.plan.dueCardCount, 0);
      expect(outcome.plan.when, DateTime(2026, 10, 21, 19, 45));
      expect(outcome.scheduled, isTrue);
      expect(notifier.calls, <String>['cancel', 'schedule']);
      expect(notifier.scheduled.single.when, DateTime(2026, 10, 21, 19, 45));
      expect(notifier.scheduled.single.body, '今天还有卡会到期');
    });

    test('下一次到期只比 now 晚 1 毫秒也算 dueSoon', () async {
      final int justAfter = now.millisecondsSinceEpoch + 1;
      await seedCard('soon-1ms', dueAtMillis: justAfter);

      final ReviewReminderOutcome outcome = await service.refresh(texts: texts);

      expect(outcome.plan.reason, ReviewReminderReason.dueSoon);
      expect(outcome.plan.when, DateTime.fromMillisecondsSinceEpoch(justAfter));
    });
  });

  group('偏好时刻设置边界', () {
    test('minutes 为 NULL 时用域层默认 20:00', () async {
      await db.delete(db.localSettings).go();
      await settings.ensureSettings();
      await settings.updateReviewReminderEnabled(true);
      await seedDueCard('due-1');

      expect(await settings.getReviewReminderMinutes(), isNull);
      final ReviewReminderOutcome outcome = await service.refresh(texts: texts);

      expect(outcome.plan.when, DateTime(2026, 10, 21, 20));
    });

    test('minutes 为 0（午夜）时排次日 00:00', () async {
      await settings.updateReviewReminderMinutes(0);
      await seedDueCard('due-1');

      final ReviewReminderOutcome outcome = await service.refresh(texts: texts);

      expect(outcome.plan.when, DateTime(2026, 10, 22));
    });

    test('minutes 为 1439（23:59）时排今天 23:59', () async {
      await settings.updateReviewReminderMinutes(1439);
      await seedDueCard('due-1');

      final ReviewReminderOutcome outcome = await service.refresh(texts: texts);

      expect(outcome.plan.when, DateTime(2026, 10, 21, 23, 59));
    });
  });

  group('权限、调用顺序与 toJson', () {
    test('系统不给权限时 scheduled false、permissionDenied true，但仍先取消过', () async {
      notifier.permission = false;
      await seedDueCard('due-1');

      final ReviewReminderOutcome outcome = await service.refresh(texts: texts);

      expect(outcome.plan.shouldSchedule, isTrue);
      expect(outcome.scheduled, isFalse);
      expect(outcome.permissionDenied, isTrue);
      expect(outcome.cancelled, isTrue);
      expect(notifier.calls, <String>['cancel', 'schedule']);
    });

    test('成功排程也标记 cancelled=true，取消恰一次且先于排程', () async {
      await seedDueCard('due-1');

      final ReviewReminderOutcome outcome = await service.refresh(texts: texts);

      expect(notifier.calls, <String>['cancel', 'schedule']);
      expect(notifier.cancelled, hasLength(1));
      expect(outcome.cancelled, isTrue,
          reason: 'cancelled 的口径是这次调用过取消，不是最终有没有提醒');
    });

    test('自定义 notificationId 会用于取消与排程', () async {
      service = ReviewReminderService(
        settings: settings,
        anki: anki,
        notifier: notifier,
        clock: () => now,
        notificationId: 4242,
      );
      await seedDueCard('due-1');

      await service.refresh(texts: texts);

      expect(notifier.cancelled, <int>[4242]);
      expect(notifier.scheduled.single.id, 4242);
    });

    test('outcome.toJson 的四个键与内嵌 plan', () async {
      await seedDueCard('due-1');

      final ReviewReminderOutcome outcome = await service.refresh(texts: texts);
      final Map<String, Object?> json = outcome.toJson();

      expect(json.keys.toList(),
          <String>['scheduled', 'cancelled', 'permission_denied', 'plan']);
      expect(json['scheduled'], isTrue);
      expect(json['cancelled'], isTrue);
      expect(json['permission_denied'], isFalse);
      final Map<String, Object?> planJson =
          (json['plan'] as Map<String, Object?>);
      expect(planJson['should_schedule'], isTrue);
      expect(planJson['reason'], 'dueNow');
      expect(planJson['due_card_count'], 1);
      expect(planJson['when'], DateTime(2026, 10, 21, 20).toIso8601String());
    });
  });

  group('幂等与异常', () {
    test('连续两次 refresh 都重新取消并重排，不会叠出两条', () async {
      await seedDueCard('due-1');

      final ReviewReminderOutcome first = await service.refresh(texts: texts);
      final ReviewReminderOutcome second = await service.refresh(texts: texts);

      expect(first.scheduled, isTrue);
      expect(second.scheduled, isTrue);
      expect(
          notifier.calls, <String>['cancel', 'schedule', 'cancel', 'schedule']);
      expect(notifier.cancelled,
          <int>[kReviewReminderNotificationId, kReviewReminderNotificationId]);
      expect(notifier.scheduled, hasLength(2));
    });

    test('notifier 抛异常时原样外抛，本层不吞', () async {
      notifier.failWith = StateError('plugin boom');
      await seedDueCard('due-1');

      await expectLater(
        service.refresh(texts: texts),
        throwsA(isA<StateError>()),
      );
      expect(notifier.calls, <String>['cancel']);
      expect(notifier.scheduled, isEmpty);
    });
  });
}
