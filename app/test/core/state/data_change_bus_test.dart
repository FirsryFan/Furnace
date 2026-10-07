import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/core/state/data_change_bus.dart';

void main() {
  setUp(() => DataChangeBus.instance.debugReset());

  test('coalesces everything issued in one microtask', () async {
    final events = <int>[];
    final subscription = DataChangeBus.instance.changes.listen(events.add);

    DataChangeBus.instance.recordChange();
    DataChangeBus.instance.recordChange();
    DataChangeBus.instance.recordChange();
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    expect(DataChangeBus.instance.revision, 1);
    await subscription.cancel();
  });

  test('reports a later batch as a later revision', () async {
    final events = <int>[];
    final subscription = DataChangeBus.instance.changes.listen(events.add);

    DataChangeBus.instance.recordChange();
    await Future<void>.delayed(Duration.zero);
    DataChangeBus.instance.recordChange();
    await Future<void>.delayed(Duration.zero);

    expect(events, [1, 2]);
    await subscription.cancel();
  });

  test('the revision is readable as a value without a listener', () async {
    DataChangeBus.instance.recordChange();
    await Future<void>.delayed(Duration.zero);

    final events = <int>[];
    final subscription = DataChangeBus.instance.changes.listen(events.add);
    await Future<void>.delayed(Duration.zero);

    // A broadcast stream does not replay, which is why the revision is also
    // readable as a plain value.
    expect(events, isEmpty);
    expect(DataChangeBus.instance.revision, 1);
    await subscription.cancel();
  });
}
