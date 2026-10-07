import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data_change_bus.dart';

/// The revision every database-backed provider depends on.
///
/// A provider that calls `ref.watchDatabaseRevision()` re-runs after any write,
/// whoever performed it. This is what removes the "restart the app to see the
/// new schedule / task list" behaviour.
class DataRevision extends Notifier<int> {
  @override
  int build() {
    final subscription = DataChangeBus.instance.changes.listen((revision) {
      state = revision;
    });
    ref.onDispose(subscription.cancel);
    return DataChangeBus.instance.revision;
  }
}

/// Current database revision; changes after every committed write.
final dataRevisionProvider = NotifierProvider<DataRevision, int>(
  DataRevision.new,
);

/// Sugar for the one line every database reader starts with.
extension DataRevisionRef on Ref {
  /// Re-runs the calling provider whenever the database changes.
  void watchDatabaseRevision() => watch(dataRevisionProvider);
}
