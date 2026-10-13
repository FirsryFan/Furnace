/// The user's default way of judging a new answer, and the value the practice
/// screen's per-answer control starts from.
///
/// Two different things live in this file and must not be confused:
///
///  * [AnswerMode] is the *practice screen's* vocabulary: strict auto, lenient
///    auto, or self. It is what the segmented control shows and what the screen
///    switches between **per answer**.
///  * [JudgeModePreference] is the *persisted* preference: which of those three
///    a freshly opened review starts in. It never overrides the control - a
///    preference that forced a judging mode onto an individual answer would take
///    away the one thing the control exists for.
///
/// The wire values are the same three words (`strict` / `lenient` / `self`) and
/// are written verbatim to `local_settings.anki_judge_mode`. They are explicitly
/// spelled out rather than taken from `Enum.name`, so a later rename of a Dart
/// identifier cannot silently change what an already-written setting means.
///
/// A NULL (or unparsable) stored value resolves to [JudgeModePreference.strict],
/// which is exact character comparison: the behaviour the app had before the
/// preference existed. That is the whole reason the column is nullable - "the
/// user never chose" has to stay distinguishable from "the user chose".
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/repository_providers.dart';

/// How one answer is judged, as the practice screen's control offers it.
enum AnswerMode {
  /// The app compares characters exactly (Chinese dictation, English spelling).
  strict,

  /// The app compares tolerantly (`ReviewService.lenientMatch`).
  lenient,

  /// The user judges their own answer after seeing the expected one.
  self,
}

/// The three values of `local_settings.anki_judge_mode`.
enum JudgeModePreference {
  /// Exact comparison. The default, and therefore today's behaviour.
  strict('strict'),

  /// Tolerant comparison.
  lenient('lenient'),

  /// Self-judged: the app shows the answer instead of comparing.
  self('self');

  const JudgeModePreference(this.storageValue);

  /// The exact string stored in the database, and the string the UI writes.
  final String storageValue;

  /// The practice screen's arm of this preference.
  AnswerMode get answerMode => switch (this) {
        JudgeModePreference.strict => AnswerMode.strict,
        JudgeModePreference.lenient => AnswerMode.lenient,
        JudgeModePreference.self => AnswerMode.self,
      };

  /// Reads a stored value back.
  ///
  /// An unknown string (a setting written by a build that knew a fourth mode) or
  /// a NULL (never chosen) both mean [JudgeModePreference.strict]. Falling back
  /// to the strictest mode rather than to the most forgiving one is deliberate:
  /// a card shown with the answer already revealed cannot be un-revealed, so of
  /// the two possible mistakes the recoverable one is the stricter default.
  static JudgeModePreference fromStorage(String? value) {
    for (final preference in JudgeModePreference.values) {
      if (preference.storageValue == value) {
        return preference;
      }
    }
    return JudgeModePreference.strict;
  }
}

/// The app's view of the persisted default judging mode.
///
/// Asynchronous because the value lives in SQLite. The screen reads it once, when
/// it builds the queue; the per-answer control then owns the mode for the rest of
/// the session, so a late-arriving read can never change an answer in progress.
class JudgeModePreferenceController
    extends AsyncNotifier<JudgeModePreference> {
  @override
  Future<JudgeModePreference> build() =>
      ref.watch(reviewPlanRepositoryProvider).getJudgeModePreference();

  /// Persists the choice and reflects it immediately.
  Future<void> select(JudgeModePreference preference) async {
    state = AsyncData(preference);
    await ref
        .read(reviewPlanRepositoryProvider)
        .setJudgeModePreference(preference);
  }
}

final judgeModePreferenceProvider =
    AsyncNotifierProvider<JudgeModePreferenceController, JudgeModePreference>(
  JudgeModePreferenceController.new,
);

/// The default mode for a queue that is being built **right now**.
///
/// `read` is deliberate, not a shortcut: the practice screen calls this from an
/// event handler (`_load`), and a `watch` there would rebuild the screen - and
/// rebuild the text field under the user's fingers - every time the settings row
/// changes.
///
/// An extension on `WidgetRef` rather than a free function taking `Ref`:
/// `WidgetRef` is not a subtype of `Ref` in this Riverpod version, so a single
/// free function could not serve both a widget and a provider.
extension JudgeModePreferenceRef on WidgetRef {
  /// The persisted default judging mode, or [JudgeModePreference.strict] while
  /// the (asynchronous, local) read is still in flight.
  ///
  /// The fallback is the strict default on purpose: a queue that started before
  /// the setting arrived must not behave more forgivingly than the setting the
  /// user chose, because an answer the app accepted is not something the app can
  /// take back.
  JudgeModePreference get judgeModePreference => read(
        judgeModePreferenceProvider,
      ).maybeWhen(
        data: (preference) => preference,
        orElse: () => JudgeModePreference.strict,
      );

  /// The mode the practice screen's control starts in.
  AnswerMode get initialAnswerMode => judgeModePreference.answerMode;
}
