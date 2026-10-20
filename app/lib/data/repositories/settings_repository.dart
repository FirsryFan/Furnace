import 'package:drift/drift.dart';

import '../database/database.dart';
import '../ids.dart';

/// Repository for local profile and app settings.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Future<Profile?> getProfile() async {
    final rows = await _db.select(_db.profiles).get();
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  Future<Profile> ensureProfile({required String displayName}) async {
    final existing = await getProfile();
    if (existing != null) {
      return existing;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _newId();
    await _db.into(_db.profiles).insert(
          ProfilesCompanion.insert(
            id: id,
            displayName: displayName,
            createdAt: now,
          ),
        );

    return (await _db.select(_db.profiles)
          ..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<LocalSetting?> getSettings() async {
    final rows = await _db.select(_db.localSettings).get();
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  Future<LocalSetting> ensureSettings({
    String language = 'system',
    String themeMode = 'system',
    String? profileId,
  }) async {
    final existing = await getSettings();
    if (existing != null) {
      return existing;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.localSettings).insert(
          LocalSettingsCompanion.insert(
            id: Value(1),
            language: Value(language),
            themeMode: Value(themeMode),
            profileId: Value(profileId),
            createdAt: now,
            updatedAt: now,
          ),
        );

    return (await _db.select(_db.localSettings)
          ..where((t) => t.id.equals(1)))
        .getSingle();
  }

  Future<void> updateProfileName(String displayName) async {
    final profile = await getProfile();
    if (profile == null) {
      await ensureProfile(displayName: displayName);
      return;
    }
    await (_db.update(_db.profiles)..where((t) => t.id.equals(profile.id)))
        .write(
      ProfilesCompanion(
        displayName: Value(displayName),
      ),
    );
  }

  Future<void> updateLanguage(String language) async {
    await (_db.update(_db.localSettings)..where((t) => t.id.equals(1)))
        .write(LocalSettingsCompanion(
      language: Value(language),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  Future<void> updateThemeMode(String themeMode) async {
    await (_db.update(_db.localSettings)..where((t) => t.id.equals(1)))
        .write(LocalSettingsCompanion(
      themeMode: Value(themeMode),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  /// Persists the thread status bar's attention-hint switch (schema v15).
  ///
  /// `true` / `false` are the user's own choice; the column stays NULL until
  /// they make one, and the app reads NULL as "show the reading"
  /// (`docs/MINDNET_ROADMAP.md` §3 row 4). That is why this method never
  /// writes a default on the user's behalf.
  Future<void> updateRhythmHintsEnabled(bool enabled) async {
    await (_db.update(_db.localSettings)..where((t) => t.id.equals(1)))
        .write(LocalSettingsCompanion(
      rhythmHintsEnabled: Value(enabled),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  /// Persists the mechanism panel's first user-side switch (schema v21): whether
  /// the library-diagnosis run installs the goal mechanism (`context.goal`).
  ///
  /// Same rule as [updateRhythmHintsEnabled]: the column stays NULL until the
  /// user makes a choice, and the app reads NULL as "install it", which is the
  /// behaviour every build before this switch had. This method therefore never
  /// writes a default on the user's behalf - a user who never touches the panel
  /// keeps exactly the engine they had
  /// (`docs/MINDNET_ROADMAP.md` §3 row 8).
  Future<void> updateGoalMechanismEnabled(bool enabled) async {
    await (_db.update(_db.localSettings)..where((t) => t.id.equals(1)))
        .write(LocalSettingsCompanion(
      goalMechanismEnabled: Value(enabled),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  /// Persists the first slider of the mechanism panel (schema v22): how strongly
  /// the goal mechanism pulls (`context.goal.beta_goal`).
  ///
  /// Same rule as the two switches above, extended to a continuous value: the
  /// column stays NULL until the user moves the slider, NULL reads as the
  /// transcribed value, and passing `null` here is how the panel's "back to the
  /// shipped value" button puts the row back. The app never writes the shipped
  /// value into the column - that would freeze today's number into every install
  /// and make a later change of it unreachable
  /// (`docs/MINDNET_ROADMAP.md` §3 row 8).
  Future<void> updateGoalBeta(double? beta) async {
    await (_db.update(_db.localSettings)..where((t) => t.id.equals(1)))
        .write(LocalSettingsCompanion(
      goalBeta: Value(beta),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  /// Persists the user's capability-action overlay JSON (schema v25).
  ///
  /// `null` is a real value here, not "absent": it means "the user never
  /// changed the vocabulary", which reads as the shipped built-in catalog.
  /// The editor's "back to shipped" path therefore writes null instead of an
  /// empty JSON object - storing `{"version":1,"customActions":[]}` would
  /// freeze an empty choice into the row and lose the distinction between
  /// "never touched" and "deliberately emptied" (the same rule as
  /// [updateGoalBeta] and the switches above, see
  /// `docs/REASONING_LAYER_DESIGN.md` §4).
  ///
  /// Callers must ensure the single settings row exists first
  /// ([ensureSettings]); this method only updates row `id = 1`.
  Future<void> updateCapabilityActionOverlayJson(String? json) async {
    await (_db.update(_db.localSettings)..where((t) => t.id.equals(1)))
        .write(LocalSettingsCompanion(
      capabilityActionOverlayJson: Value(json),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  /// Reads the review-reminder switch (schema v28, 轮次一百三十五).
  ///
  /// No settings row / NULL column means "the user never made a choice" and
  /// reads as `false`: a reminder that posts system notifications is opt-in, so
  /// an upgrade must not turn it on for anybody (the same rule as
  /// `goalMechanismEnabled` / `rhythmHintsEnabled`).
  Future<bool> getReviewReminderEnabled() async {
    final row = await getSettings();
    return row?.reviewReminderEnabled ?? false;
  }

  /// Reads the review-reminder time of day (schema v28) as minutes since
  /// local midnight, or `null` when the user never picked one.
  ///
  /// `null` is not 0: 0 is midnight, a legal deliberate choice, so the two stay
  /// distinguishable. The caller turns `null` into the domain-layer shipped
  /// default (today 20:00, `kDefaultReviewReminderMinutesOfDay`); this repository
  /// never resolves the default itself - the number belongs to the domain layer.
  Future<int?> getReviewReminderMinutes() async {
    final row = await getSettings();
    return row?.reviewReminderMinutes;
  }

  /// Persists the review-reminder switch (schema v28).
  Future<void> updateReviewReminderEnabled(bool enabled) async {
    await (_db.update(_db.localSettings)..where((t) => t.id.equals(1)))
        .write(LocalSettingsCompanion(
      reviewReminderEnabled: Value(enabled),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  /// Persists the review-reminder time of day (schema v28), in minutes since
  /// local midnight.
  ///
  /// Throws [ArgumentError] outside 0..1439 instead of clamping: a silent clamp
  /// would store a different time than the caller asked for and make the wrong
  /// reminder look like the user's own choice. Conversion to the next actual
  /// `DateTime` belongs to the domain layer (`planReviewReminder`).
  Future<void> updateReviewReminderMinutes(int minutes) async {
    if (minutes < 0 || minutes > 1439) {
      throw ArgumentError.value(
          minutes, 'minutes', 'review reminder minutes must be within 0..1439');
    }
    await (_db.update(_db.localSettings)..where((t) => t.id.equals(1)))
        .write(LocalSettingsCompanion(
      reviewReminderMinutes: Value(minutes),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  /// Reads the tag-tree sort mode (schema v29, 轮次一百三十八) as the raw
  /// stored code, or `null` when the user never picked one.
  ///
  /// `null` is not a mode: the caller translates it into the shipped default
  /// (`tagTreeSortModeFromStorage` → 字典序); this repository does not import
  /// the domain layer, so it hands back exactly what the row says and lets the
  /// read side own the meaning.
  Future<String?> getTagTreeSortMode() async {
    final row = await getSettings();
    return row?.tagTreeSortMode;
  }

  /// Persists the tag-tree sort mode (schema v29) as a stable code
  /// (`TagTreeSortMode.code`), or `null` to fall back to the shipped default.
  ///
  /// Blank input is stored as NULL rather than `''`: "empty" is not a mode and
  /// must not become a third state the reader has to guess about. Unknown codes
  /// are not rejected here — the domain-layer enum owns the legal set, and a
  /// future version may add a mode this build cannot name; the reader already
  /// degrades unknown values to 字典序.
  Future<void> updateTagTreeSortMode(String? mode) async {
    final code = mode?.trim();
    await (_db.update(_db.localSettings)..where((t) => t.id.equals(1)))
        .write(LocalSettingsCompanion(
      tagTreeSortMode: Value(code == null || code.isEmpty ? null : code),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  String _newId() => Ids.next('p');
}
