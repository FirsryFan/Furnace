import 'dart:async';

/// The one place that knows "something in the database changed".
///
/// Writes reach SQLite through `DbWriteInterceptor`, which calls [recordWrite];
/// the UI observes [changes] through `dataRevisionProvider`. Because the
/// notification sits *below* the repositories, a page, an AI tool, a package
/// import and the review engine are all covered without any of them having to
/// remember to refresh anything.
///
/// The bus is a plain Dart singleton on purpose: the database layer has no
/// `ProviderContainer`, and writes that happen before the first widget exists
/// (migrations, built-in rows) must be observable too.
class DataChangeBus {
  DataChangeBus._();

  static final DataChangeBus instance = DataChangeBus._();

  final _controller = StreamController<int>.broadcast();
  int _revision = 0;
  bool _flushScheduled = false;

  /// Monotonic counter of coalesced write batches.
  int get revision => _revision;

  /// Emits the new revision after a write batch.
  Stream<int> get changes => _controller.stream;

  /// Notes that something a reader can observe has changed.
  ///
  /// Called by the database write interceptor for every committed write, and by
  /// the app shell when the app comes back to the foreground (time moved on:
  /// due dates, today's schedule and "sorted N minutes ago" are all derived from
  /// the clock, with no write in between).
  ///
  /// Coalesced per microtask: several statements issued without awaiting in
  /// between (a batch insert, a package import loop, a page saving five rows)
  /// produce one event, so the UI refetches once instead of once per row.
  ///
  /// A microtask and not a `Timer` on purpose - a pending timer makes
  /// `flutter_test` fail a widget test that has already finished pumping.
  void recordChange() {
    if (_flushScheduled) {
      return;
    }
    _flushScheduled = true;
    scheduleMicrotask(_flush);
  }

  void _flush() {
    _flushScheduled = false;
    _revision++;
    if (!_controller.isClosed) {
      _controller.add(_revision);
    }
  }

  /// Test hook: drops the counter and any scheduled flush.
  ///
  /// Listeners are not removed; a test that needs a clean revision number calls
  /// this before subscribing.
  void debugReset() {
    _flushScheduled = false;
    _revision = 0;
  }
}
