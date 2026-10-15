import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database_provider.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/services/cognitive/study_rhythm.dart';

/// How many log rows on each side are considered when deriving the sitting.
///
/// The reading only needs "the chain that is still running", and a chain breaks
/// after `kStudySessionGap` (15 minutes) of silence, so a bounded tail is
/// enough; it also keeps the thread screen from scanning a year of history on
/// every rebuild. 500 is a ceiling, not a promise that a long sitting will be
/// reconstructed past it.
const int kStudyRhythmLogLimit = 500;

/// What the thread status bar should show (or not show) right now.
class StudyRhythmSnapshot {
  const StudyRhythmSnapshot({
    required this.enabled,
    required this.reading,
    required this.actionCount,
  });

  /// The user turned the hint off: nothing was read from the database and
  /// nothing is shown.
  const StudyRhythmSnapshot.hidden()
      : enabled = false,
        reading = null,
        actionCount = 0;

  final bool enabled;

  /// `null` means "there is nothing honest to say yet" - no sitting is running
  /// (or there are no logs at all). The UI says so instead of printing a
  /// fabricated availability.
  final StudyRhythmReading? reading;

  /// How many log rows went into this reading, for the empty-state wording.
  final int actionCount;

  bool get hasReading => reading != null;
}

/// Reads the attention-availability hint off the existing study logs.
///
/// The app has no session timer, so α(τ)'s `t_on` is derived from the timestamps
/// the app already writes - `review_logs.reviewed_at` (a graded answer) and
/// `exposure_logs.exposed_at` (a reading) - through [StudyRhythm], whose
/// 15-minute gap is an explicitly uncalibrated proxy. Nothing here invents a
/// second notion of "studying".
class StudyRhythmReader {
  StudyRhythmReader(this._db, this._settings);

  final AppDatabase _db;
  final SettingsRepository _settings;

  Future<StudyRhythmSnapshot> read({required DateTime now}) async {
    final settings = await _settings.getSettings();
    // NULL = the user never chose, which reads as the shipped default (show it).
    final enabled = settings?.rhythmHintsEnabled ?? true;
    if (!enabled) {
      return const StudyRhythmSnapshot.hidden();
    }
    final actions = await _recentActions();
    return StudyRhythmSnapshot(
      enabled: true,
      // `load` stays 0 on purpose: the cognitive engine is not running on this
      // screen, and the duty gate's cycle length is the only thing load would
      // change. Feeding it a made-up number would dress up a guess as a
      // measurement, so the reading reports vigilance and the default cycle.
      reading: StudyRhythm.read(actions: actions, now: now),
      actionCount: actions.length,
    );
  }

  Future<List<DateTime>> _recentActions() async {
    final reviews = await (_db.select(_db.reviewLogs)
          ..orderBy([(t) => OrderingTerm.desc(t.reviewedAt)])
          ..limit(kStudyRhythmLogLimit))
        .get();
    final exposures = await (_db.select(_db.exposureLogs)
          ..orderBy([(t) => OrderingTerm.desc(t.exposedAt)])
          ..limit(kStudyRhythmLogLimit))
        .get();
    return <DateTime>[
      for (final row in reviews)
        DateTime.fromMillisecondsSinceEpoch(row.reviewedAt),
      for (final row in exposures)
        DateTime.fromMillisecondsSinceEpoch(row.exposedAt),
    ];
  }
}

final studyRhythmReaderProvider = Provider<StudyRhythmReader>((ref) {
  return StudyRhythmReader(
    ref.watch(appDatabaseProvider),
    ref.watch(settingsRepositoryProvider),
  );
});

/// The reading shown by the thread status bar. Invalidated after the switch is
/// flipped so the bar reflects the choice without a restart.
final studyRhythmProvider = FutureProvider<StudyRhythmSnapshot>((ref) {
  return ref.watch(studyRhythmReaderProvider).read(now: DateTime.now());
});

/// Whether the attention hint is currently shown.
///
/// A NULL column means "the user never chose", and that reads as the shipped
/// default (shown). This is the value the toggle in the thread app bar renders
/// as its check mark.
final rhythmHintsEnabledProvider = FutureProvider<bool>((ref) async {
  final settings = await ref.watch(settingsRepositoryProvider).getSettings();
  return settings?.rhythmHintsEnabled ?? true;
});
