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

  String _newId() => Ids.next('p');
}
