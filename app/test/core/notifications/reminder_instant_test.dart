import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Reminders are scheduled with `tz.TZDateTime.from(when, tz.local)`.
///
/// The trap this pins down: `tz.local` is UTC unless something calls
/// `setLocalLocation`, and the obvious reading of that is "reminders fire at the
/// wrong time". They do not - `TZDateTime.from` converts an *instant*, so the
/// wall clock the user picked survives whatever `tz.local` happens to be. The
/// test exists so the next person does not "fix" a non-bug by adding a
/// local-location lookup, and so a real regression in that conversion fails here
/// instead of in a user's reminder.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('the scheduled instant is the instant the user picked', () {
    final picked = DateTime(2026, 10, 8, 7, 30);

    final scheduled = tz.TZDateTime.from(picked, tz.local);

    expect(scheduled.millisecondsSinceEpoch, picked.millisecondsSinceEpoch);
  });

  test('that holds whichever location the scheduler resolves to', () {
    final picked = DateTime(2026, 3, 1, 23, 45);

    for (final name in const [
      'Etc/UTC',
      'Asia/Shanghai',
      'America/New_York',
    ]) {
      final scheduled = tz.TZDateTime.from(picked, tz.getLocation(name));
      expect(
        scheduled.millisecondsSinceEpoch,
        picked.millisecondsSinceEpoch,
        reason: name,
      );
    }
  });
}
