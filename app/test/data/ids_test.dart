import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/ids.dart';

/// Regression guard for a real data-loss bug: every repository used to derive
/// ids from `DateTime.now().microsecondsSinceEpoch`, so several inserts inside
/// one microsecond produced duplicate primary keys
/// (`UNIQUE constraint failed: time_blocks.id` / `diffusion_logs.id`).
void main() {
  test('ids stay unique when generated back to back', () {
    final ids = <String>{};
    for (var i = 0; i < 5000; i++) {
      ids.add(Ids.next('tb'));
    }
    expect(ids, hasLength(5000),
        reason: 'a clock-derived id collides inside the same microsecond');
  });

  test('the prefix is kept for readability, uniqueness comes from the UUID', () {
    final first = Ids.next('cl');
    final second = Ids.next('cl');
    expect(first, startsWith('cl-'));
    expect(second, startsWith('cl-'));
    expect(first, isNot(second));
    // A v4 UUID tail is long enough that a collision is not a practical risk.
    expect(first.length, greaterThan(30));
  });

  test('unprefixed ids are unique as well', () {
    final ids = {for (var i = 0; i < 1000; i++) Ids.uuid()};
    expect(ids, hasLength(1000));
  });
}
