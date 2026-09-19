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

    return (await _db.select(_db.profiles)..where((t) => t.id.equals(id)))
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

  String _newId() => Ids.next('p');
}
