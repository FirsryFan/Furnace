import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/scheduling/review_reminder_plan.dart';

const int _hugeMillis = 1 << 62;
const int _maxInt = 9223372036854775807;

DateTime local(
  int year,
  int month,
  int day,
  int hour,
  int minute, [
  int second = 0,
  int millisecond = 0,
]) =>
    DateTime(year, month, day, hour, minute, second, millisecond);

ReviewReminderPlan planFor({
  required DateTime now,
  int preferred = kDefaultReviewReminderMinutesOfDay,
  int dueCards = 0,
  int? nextDue,
  bool enabled = true,
}) =>
    planReviewReminder(
      now: now,
      preferredMinutesOfDay: preferred,
      dueCardCount: dueCards,
      nextDueAtMillis: nextDue,
      enabled: enabled,
    );

void main() {
  group('默认偏好时刻 20:00 的边界', () {
    test('19:59 有到期卡：排今天 20:00', () {
      final plan = planFor(now: local(2026, 3, 10, 19, 59), dueCards: 1);
      expect(plan.shouldSchedule, isTrue);
      expect(plan.reason, ReviewReminderReason.dueNow);
      expect(plan.dueCardCount, 1);
      expect(plan.when, local(2026, 3, 10, 20, 0));
    });

    test('20:00 整：偏好时刻不晚于 now，排明天 20:00', () {
      final plan = planFor(now: local(2026, 3, 10, 20, 0), dueCards: 1);
      expect(plan.reason, ReviewReminderReason.dueNow);
      expect(plan.when, local(2026, 3, 11, 20, 0));
    });

    test('20:00:00.001：已经过了，排明天 20:00', () {
      final plan = planFor(
        now: local(2026, 3, 10, 20, 0, 0, 1),
        dueCards: 1,
      );
      expect(plan.when, local(2026, 3, 11, 20, 0));
    });

    test('20:01：排明天 20:00', () {
      final plan = planFor(now: local(2026, 3, 10, 20, 1), dueCards: 1);
      expect(plan.when, local(2026, 3, 11, 20, 0));
    });

    test('19:59:59.999：仍排今天 20:00', () {
      final plan = planFor(
        now: local(2026, 3, 10, 19, 59, 59, 999),
        dueCards: 1,
      );
      expect(plan.when, local(2026, 3, 10, 20, 0));
    });

    test('没有到期卡也没有下一次到期：nothingDue 且 when 为空', () {
      final plan = planFor(now: local(2026, 3, 10, 19, 59));
      expect(plan.shouldSchedule, isFalse);
      expect(plan.reason, ReviewReminderReason.nothingDue);
      expect(plan.dueCardCount, 0);
      expect(plan.when, isNull);
      expect(plan.isEmpty, isTrue);
    });

    test('有到期卡时 nextDue 不参与决策，仍排下一个偏好时刻', () {
      final plan = planFor(
        now: local(2026, 3, 10, 10, 0),
        dueCards: 1,
        nextDue: local(2026, 3, 10, 15, 0).millisecondsSinceEpoch,
      );
      expect(plan.reason, ReviewReminderReason.dueNow);
      expect(plan.when, local(2026, 3, 10, 20, 0));
    });
  });

  group('凌晨与跨天', () {
    test('00:00 有到期卡：排今天 20:00', () {
      final plan = planFor(now: local(2026, 3, 10, 0, 0), dueCards: 1);
      expect(plan.when, local(2026, 3, 10, 20, 0));
    });

    test('00:01 有到期卡：排今天 20:00', () {
      final plan = planFor(now: local(2026, 3, 10, 0, 1), dueCards: 1);
      expect(plan.when, local(2026, 3, 10, 20, 0));
    });

    test('23:59 有到期卡：排明天 20:00', () {
      final plan = planFor(now: local(2026, 3, 10, 23, 59), dueCards: 1);
      expect(plan.when, local(2026, 3, 11, 20, 0));
    });

    test('23:59:59.999 有到期卡：排明天 20:00', () {
      final plan = planFor(
        now: local(2026, 3, 10, 23, 59, 59, 999),
        dueCards: 1,
      );
      expect(plan.when, local(2026, 3, 11, 20, 0));
    });

    test('偏好 00:00 且 now 正好 00:00：严格晚于，排明天 00:00', () {
      final plan = planFor(
        now: local(2026, 3, 10, 0, 0),
        preferred: 0,
        dueCards: 1,
      );
      expect(plan.when, local(2026, 3, 11, 0, 0));
    });

    test('偏好 23:59 且 now 正好 23:59：排明天 23:59', () {
      final plan = planFor(
        now: local(2026, 3, 10, 23, 59),
        preferred: 1439,
        dueCards: 1,
      );
      expect(plan.when, local(2026, 3, 11, 23, 59));
    });
  });

  group('偏好分钟数 clamp 到 0..1439', () {
    test('负数 -30 夹到 0：now 19:00 时排明天 00:00', () {
      final plan = planFor(
        now: local(2026, 3, 10, 19, 0),
        preferred: -30,
        dueCards: 1,
      );
      expect(plan.when, local(2026, 3, 11, 0, 0));
    });

    test('负数 -1 夹到 0：now 00:00 时排明天 00:00', () {
      final plan = planFor(
        now: local(2026, 3, 10, 0, 0),
        preferred: -1,
        dueCards: 1,
      );
      expect(plan.when, local(2026, 3, 11, 0, 0));
    });

    test('1440 夹到 1439：排今天 23:59', () {
      final plan = planFor(
        now: local(2026, 3, 10, 23, 0),
        preferred: 1440,
        dueCards: 1,
      );
      expect(plan.when, local(2026, 3, 10, 23, 59));
    });

    test('1500 夹到 1439：排今天 23:59', () {
      final plan = planFor(
        now: local(2026, 3, 10, 23, 0),
        preferred: 1500,
        dueCards: 1,
      );
      expect(plan.when, local(2026, 3, 10, 23, 59));
    });

    test('0 分钟：now 00:00 排明天 00:00', () {
      final plan = planFor(
        now: local(2026, 3, 10, 0, 0),
        preferred: 0,
        dueCards: 1,
      );
      expect(plan.when, local(2026, 3, 11, 0, 0));
    });

    test('1 分钟：now 00:00 排今天 00:01', () {
      final plan = planFor(
        now: local(2026, 3, 10, 0, 0),
        preferred: 1,
        dueCards: 1,
      );
      expect(plan.when, local(2026, 3, 10, 0, 1));
    });

    test('1439 分钟：now 23:00 排今天 23:59', () {
      final plan = planFor(
        now: local(2026, 3, 10, 23, 0),
        preferred: 1439,
        dueCards: 1,
      );
      expect(plan.when, local(2026, 3, 10, 23, 59));
    });

    test('maxInt 分钟数也不抛并夹到 1439', () {
      final plan = planFor(
        now: local(2026, 3, 10, 23, 0),
        preferred: _maxInt,
        dueCards: 1,
      );
      expect(plan.when, local(2026, 3, 10, 23, 59));
    });
  });

  group('dueCardCount clamp 与 dueNow', () {
    test('1 张到期卡：dueNow、when 为下一个偏好时刻', () {
      final plan = planFor(now: local(2026, 3, 10, 9, 0), dueCards: 1);
      expect(plan.shouldSchedule, isTrue);
      expect(plan.reason, ReviewReminderReason.dueNow);
      expect(plan.dueCardCount, 1);
      expect(plan.when, local(2026, 3, 10, 20, 0));
    });

    test('5 张到期卡：数量原样保留', () {
      final plan = planFor(now: local(2026, 3, 10, 9, 0), dueCards: 5);
      expect(plan.dueCardCount, 5);
      expect(plan.reason, ReviewReminderReason.dueNow);
    });

    test('最大 int 张到期卡也不抛', () {
      final plan = planFor(now: local(2026, 3, 10, 9, 0), dueCards: _maxInt);
      expect(plan.reason, ReviewReminderReason.dueNow);
      expect(plan.dueCardCount, _maxInt);
    });

    test('0 张到期卡且没有下一次到期：nothingDue', () {
      final plan = planFor(now: local(2026, 3, 10, 9, 0));
      expect(plan.reason, ReviewReminderReason.nothingDue);
      expect(plan.dueCardCount, 0);
      expect(plan.when, isNull);
    });

    test('-1 张到期卡夹到 0', () {
      final plan = planFor(now: local(2026, 3, 10, 9, 0), dueCards: -1);
      expect(plan.reason, ReviewReminderReason.nothingDue);
      expect(plan.dueCardCount, 0);
    });

    test('-100 张到期卡夹到 0 且序列化也是 0', () {
      final plan = planFor(now: local(2026, 3, 10, 9, 0), dueCards: -100);
      expect(plan.dueCardCount, 0);
      expect(plan.toJson()['due_card_count'], 0);
    });

    test('有到期卡且 nextDue 已过期：仍然 dueNow', () {
      final plan = planFor(
        now: local(2026, 3, 10, 9, 0),
        dueCards: 2,
        nextDue: local(2026, 3, 9, 8, 0).millisecondsSinceEpoch,
      );
      expect(plan.reason, ReviewReminderReason.dueNow);
      expect(plan.dueCardCount, 2);
      expect(plan.when, local(2026, 3, 10, 20, 0));
    });
  });

  group('nextDueAtMillis 分支', () {
    test('下一次到期在 now 之后、偏好时刻之前：dueSoon 且 when=nextDue', () {
      final nextDue = local(2026, 3, 10, 15, 0);
      final plan = planFor(
        now: local(2026, 3, 10, 10, 0),
        nextDue: nextDue.millisecondsSinceEpoch,
      );
      expect(plan.shouldSchedule, isTrue);
      expect(plan.reason, ReviewReminderReason.dueSoon);
      expect(plan.when, nextDue);
    });

    test('下一次到期 19:59：dueSoon', () {
      final nextDue = local(2026, 3, 10, 19, 59);
      final plan = planFor(
        now: local(2026, 3, 10, 10, 0),
        nextDue: nextDue.millisecondsSinceEpoch,
      );
      expect(plan.reason, ReviewReminderReason.dueSoon);
      expect(plan.when, nextDue);
    });

    test('下一次到期正好等于偏好时刻：nothingDue（不早于）', () {
      final plan = planFor(
        now: local(2026, 3, 10, 10, 0),
        nextDue: local(2026, 3, 10, 20, 0).millisecondsSinceEpoch,
      );
      expect(plan.reason, ReviewReminderReason.nothingDue);
      expect(plan.when, isNull);
    });

    test('下一次到期晚于偏好时刻：nothingDue', () {
      final plan = planFor(
        now: local(2026, 3, 10, 10, 0),
        nextDue: local(2026, 3, 10, 20, 1).millisecondsSinceEpoch,
      );
      expect(plan.reason, ReviewReminderReason.nothingDue);
      expect(plan.when, isNull);
    });

    test('下一次到期早于 now：dueNow 且排到 nextPreferred，不排到过去', () {
      final plan = planFor(
        now: local(2026, 3, 10, 10, 0),
        nextDue: local(2026, 3, 10, 9, 0).millisecondsSinceEpoch,
      );
      expect(plan.reason, ReviewReminderReason.dueNow);
      expect(plan.when, local(2026, 3, 10, 20, 0));
    });

    test('下一次到期正好等于 now：dueNow', () {
      final now = local(2026, 3, 10, 10, 0);
      final plan = planFor(now: now, nextDue: now.millisecondsSinceEpoch);
      expect(plan.reason, ReviewReminderReason.dueNow);
      expect(plan.when, local(2026, 3, 10, 20, 0));
    });

    test('now 已过偏好时刻：下一次到期在明天偏好前 → dueSoon', () {
      final nextDue = local(2026, 3, 11, 10, 0);
      final plan = planFor(
        now: local(2026, 3, 10, 21, 0),
        nextDue: nextDue.millisecondsSinceEpoch,
      );
      expect(plan.reason, ReviewReminderReason.dueSoon);
      expect(plan.when, nextDue);
    });

    test('下一次到期在 now 之后 1 毫秒：dueSoon', () {
      final now = local(2026, 3, 10, 10, 0);
      final plan = planFor(
        now: now,
        nextDue: now.millisecondsSinceEpoch + 1,
      );
      expect(plan.reason, ReviewReminderReason.dueSoon);
      expect(plan.when, local(2026, 3, 10, 10, 0, 0, 1));
    });

    test('下一次到期在 now 之前 1 毫秒：dueNow', () {
      final now = local(2026, 3, 10, 10, 0);
      final plan = planFor(
        now: now,
        nextDue: now.millisecondsSinceEpoch - 1,
      );
      expect(plan.reason, ReviewReminderReason.dueNow);
      expect(plan.when, local(2026, 3, 10, 20, 0));
    });

    test('nextDue 为 0（1970）视为早已过期：dueNow', () {
      final plan = planFor(now: local(2026, 3, 10, 10, 0), nextDue: 0);
      expect(plan.reason, ReviewReminderReason.dueNow);
      expect(plan.when, local(2026, 3, 10, 20, 0));
    });

    test('明天 23:59:59.999 早于明天 23:59 偏好？不早于 → nothingDue', () {
      final plan = planFor(
        now: local(2026, 3, 10, 23, 0),
        preferred: 1439,
        nextDue: local(2026, 3, 11, 23, 59, 59, 999).millisecondsSinceEpoch,
      );
      expect(plan.reason, ReviewReminderReason.nothingDue);
      expect(plan.when, isNull);
    });
  });

  group('disabled 压过一切', () {
    test('有到期卡也返回 disabled 且 when 为空', () {
      final plan = planFor(
        now: local(2026, 3, 10, 9, 0),
        dueCards: 5,
        enabled: false,
      );
      expect(plan.shouldSchedule, isFalse);
      expect(plan.reason, ReviewReminderReason.disabled);
      expect(plan.dueCardCount, 5);
      expect(plan.when, isNull);
      expect(plan.isEmpty, isTrue);
    });

    test('下一次到期在偏好前也返回 disabled', () {
      final plan = planFor(
        now: local(2026, 3, 10, 10, 0),
        nextDue: local(2026, 3, 10, 15, 0).millisecondsSinceEpoch,
        enabled: false,
      );
      expect(plan.reason, ReviewReminderReason.disabled);
      expect(plan.when, isNull);
    });

    test('什么数据都没有也返回 disabled', () {
      final plan = planFor(now: local(2026, 3, 10, 10, 0), enabled: false);
      expect(plan.reason, ReviewReminderReason.disabled);
      expect(plan.shouldSchedule, isFalse);
    });

    test('关闭时 dueCardCount 仍然 clamp 到 >= 0', () {
      final plan = planFor(
        now: local(2026, 3, 10, 10, 0),
        dueCards: -7,
        enabled: false,
      );
      expect(plan.dueCardCount, 0);
    });

    test('enabled 显式 true 与默认 true 结果相等', () {
      final now = local(2026, 3, 10, 19, 59);
      expect(planFor(now: now, dueCards: 1, enabled: true),
          planFor(now: now, dueCards: 1));
    });

    test('disabled 的 toJson 标记 disabled 且 when 为 null', () {
      final plan = planFor(
        now: local(2026, 3, 10, 9, 0),
        dueCards: 3,
        enabled: false,
      );
      expect(plan.toJson(), <String, Object?>{
        'should_schedule': false,
        'reason': 'disabled',
        'due_card_count': 3,
        'when': null,
      });
    });
  });

  group('月末、年末、闰年用日期构造器进位', () {
    test('1 月 31 日 21:00：排 2 月 1 日 20:00', () {
      final plan = planFor(now: local(2026, 1, 31, 21, 0), dueCards: 1);
      expect(plan.when, local(2026, 2, 1, 20, 0));
    });

    test('1 月 31 日 19:00：仍排当天 20:00', () {
      final plan = planFor(now: local(2026, 1, 31, 19, 0), dueCards: 1);
      expect(plan.when, local(2026, 1, 31, 20, 0));
    });

    test('12 月 31 日 21:00：排次年 1 月 1 日 20:00', () {
      final plan = planFor(now: local(2026, 12, 31, 21, 0), dueCards: 1);
      expect(plan.when, local(2027, 1, 1, 20, 0));
    });

    test('12 月 31 日 19:00：仍排当天 20:00', () {
      final plan = planFor(now: local(2026, 12, 31, 19, 0), dueCards: 1);
      expect(plan.when, local(2026, 12, 31, 20, 0));
    });

    test('闰年 2028-02-28 21:00：排 02-29 20:00', () {
      final plan = planFor(now: local(2028, 2, 28, 21, 0), dueCards: 1);
      expect(plan.when, local(2028, 2, 29, 20, 0));
    });

    test('平年 2027-02-28 21:00：排 03-01 20:00', () {
      final plan = planFor(now: local(2027, 2, 28, 21, 0), dueCards: 1);
      expect(plan.when, local(2027, 3, 1, 20, 0));
    });

    test('4 月 30 日 21:00：排 5 月 1 日 20:00', () {
      final plan = planFor(now: local(2026, 4, 30, 21, 0), dueCards: 1);
      expect(plan.when, local(2026, 5, 1, 20, 0));
    });
  });

  group('极端时间戳与永不抛', () {
    test('1<<62 毫秒：不抛，按没有下一次到期处理', () {
      final plan = planFor(
        now: local(2026, 3, 10, 10, 0),
        nextDue: _hugeMillis,
      );
      expect(plan.shouldSchedule, isFalse);
      expect(plan.reason, ReviewReminderReason.nothingDue);
      expect(plan.when, isNull);
    });

    test('最大 int 毫秒：不抛且 nothingDue', () {
      final plan = planFor(now: local(2026, 3, 10, 10, 0), nextDue: _maxInt);
      expect(plan.reason, ReviewReminderReason.nothingDue);
      expect(plan.when, isNull);
    });

    test('-(1<<62) 毫秒：不抛；要么 dueNow 且 when 在 now 之后，要么 nothingDue', () {
      final now = local(2026, 3, 10, 10, 0);
      final plan = planFor(now: now, nextDue: -_hugeMillis);
      expect(plan.shouldSchedule, plan.when != null);
      if (plan.when != null) {
        expect(plan.when!.isAfter(now), isTrue);
        expect(plan.reason, ReviewReminderReason.dueNow);
      } else {
        expect(plan.reason, ReviewReminderReason.nothingDue);
      }
    });

    test('极端毫秒戳在有到期卡时不影响 dueNow 路径', () {
      final plan = planFor(
        now: local(2026, 3, 10, 9, 0),
        dueCards: 1,
        nextDue: _hugeMillis,
      );
      expect(plan.reason, ReviewReminderReason.dueNow);
      expect(plan.when, local(2026, 3, 10, 20, 0));
    });
  });

  group('toJson、相等性、toString、isEmpty', () {
    test('dueNow 的 toJson 键与值完整', () {
      final plan = planFor(now: local(2026, 3, 10, 19, 59), dueCards: 2);
      expect(plan.toJson(), <String, Object?>{
        'should_schedule': true,
        'reason': 'dueNow',
        'due_card_count': 2,
        'when': local(2026, 3, 10, 20, 0).toIso8601String(),
      });
    });

    test('dueSoon 的 reason.name 是 dueSoon', () {
      final plan = planFor(
        now: local(2026, 3, 10, 10, 0),
        nextDue: local(2026, 3, 10, 15, 0).millisecondsSinceEpoch,
      );
      expect(plan.toJson()['reason'], 'dueSoon');
    });

    test('nothingDue 的 toJson should_schedule 为 false 且 when 为 null', () {
      final plan = planFor(now: local(2026, 3, 10, 10, 0));
      expect(plan.toJson()['should_schedule'], isFalse);
      expect(plan.toJson()['reason'], 'nothingDue');
      expect(plan.toJson()['when'], isNull);
    });

    test('toJson 可以被 jsonEncode/jsonDecode 往返', () {
      final plan = planFor(now: local(2026, 3, 10, 19, 59), dueCards: 2);
      final decoded =
          jsonDecode(jsonEncode(plan.toJson())) as Map<String, dynamic>;
      expect(decoded['should_schedule'], isTrue);
      expect(decoded['reason'], 'dueNow');
      expect(decoded['due_card_count'], 2);
      expect(decoded['when'], local(2026, 3, 10, 20, 0).toIso8601String());
    });

    test('相同输入两次规划相等且 hashCode 相同', () {
      final now = local(2026, 3, 10, 19, 59);
      final a = planFor(now: now, dueCards: 1);
      final b = planFor(now: now, dueCards: 1);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('reason 不同则不等', () {
      final now = local(2026, 3, 10, 10, 0);
      final dueNowPlan =
          planFor(now: now, dueCards: 1, nextDue: now.millisecondsSinceEpoch);
      final nothingPlan = planFor(now: now);
      expect(dueNowPlan, isNot(nothingPlan));
    });

    test('when 相差 1 毫秒则不等', () {
      final when = local(2026, 3, 10, 20, 0);
      final a = ReviewReminderPlan(
        shouldSchedule: true,
        reason: ReviewReminderReason.dueNow,
        dueCardCount: 0,
        when: when,
      );
      final b = ReviewReminderPlan(
        shouldSchedule: true,
        reason: ReviewReminderReason.dueNow,
        dueCardCount: 0,
        when: local(2026, 3, 10, 20, 0, 0, 1),
      );
      expect(a, isNot(b));
    });

    test('when 按毫秒时间戳比较，同一时刻不同 isUtc 也相等', () {
      final whenUtc = DateTime.utc(2026, 3, 10, 20, 0);
      final whenLocal =
          DateTime.fromMillisecondsSinceEpoch(whenUtc.millisecondsSinceEpoch);
      final a = ReviewReminderPlan(
        shouldSchedule: true,
        reason: ReviewReminderReason.dueNow,
        dueCardCount: 0,
        when: whenUtc,
      );
      final b = ReviewReminderPlan(
        shouldSchedule: true,
        reason: ReviewReminderReason.dueNow,
        dueCardCount: 0,
        when: whenLocal,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('isEmpty 与 shouldSchedule 相反', () {
      final now = local(2026, 3, 10, 10, 0);
      expect(planFor(now: now, dueCards: 1).isEmpty, isFalse);
      expect(planFor(now: now).isEmpty, isTrue);
      expect(planFor(now: now, dueCards: 1, enabled: false).isEmpty, isTrue);
      expect(
        planFor(
          now: now,
          nextDue: local(2026, 3, 10, 15, 0).millisecondsSinceEpoch,
        ).isEmpty,
        isFalse,
      );
    });

    test('toString 带原因、到期数与时点', () {
      final plan = planFor(now: local(2026, 3, 10, 19, 59), dueCards: 2);
      expect(plan.toString(), contains('dueNow'));
      expect(plan.toString(), contains('dueCardCount: 2'));
      expect(
        plan.toString(),
        contains(local(2026, 3, 10, 20, 0).toIso8601String()),
      );
    });
  });
}
