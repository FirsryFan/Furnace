import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/theme/theme_profile.dart';
import '../database/database.dart';
import '../ids.dart';

/// Reads and writes appearance themes (spec §4).
///
/// A theme row stores the theme document as JSON in `payload`. The two shipped
/// themes are seeded on first use and marked `is_builtin`, so the UI can keep
/// them undeletable while letting the user duplicate and edit copies.
class ThemeRepository {
  ThemeRepository(this._db);

  final AppDatabase _db;

  /// The built-in themes, in the order the UI should list them.
  static const List<({String id, ThemeProfileData data})> builtins = [
    (id: 'builtin-dark', data: ThemeProfileData.builtinDark),
    (id: 'builtin-light', data: ThemeProfileData.builtinLight),
  ];

  /// Every theme, built-ins first.
  Future<List<ThemeProfile>> getAll() async {
    await ensureBuiltins();
    final rows = await (_db.select(_db.themes)
          ..orderBy([
            (t) => OrderingTerm.desc(t.isBuiltin),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .get();
    return rows;
  }

  Future<ThemeProfile?> getById(String id) {
    return (_db.select(_db.themes)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Inserts the shipped themes when the table is empty. Idempotent.
  Future<void> ensureBuiltins() async {
    for (final builtin in builtins) {
      final existing = await getById(builtin.id);
      if (existing != null) {
        continue;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db.into(_db.themes).insert(
            ThemesCompanion.insert(
              id: builtin.id,
              name: builtin.data.name,
              isBuiltin: const Value(1),
              payload: builtin.data.encode(),
              createdAt: now,
              updatedAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  /// Parses a stored row into the model. A malformed payload falls back to the
  /// built-in dark theme instead of throwing, so one bad row cannot make the
  /// app unusable.
  ThemeProfileData dataOf(ThemeProfile row) {
    try {
      return ThemeProfileData.decode(row.payload);
    } catch (_) {
      return ThemeProfileData.builtinDark;
    }
  }

  /// The active theme, or null when the user follows the system default.
  Future<({ThemeProfile row, ThemeProfileData data})?> active() async {
    final settings = await _db.select(_db.localSettings).getSingleOrNull();
    final id = settings?.activeThemeId;
    if (id == null) {
      return null;
    }
    final row = await getById(id);
    if (row == null) {
      return null;
    }
    return (row: row, data: dataOf(row));
  }

  /// Points local settings at [id]; pass null to follow the system theme.
  Future<void> setActive(String? id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await _db.select(_db.localSettings).getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.localSettings).insert(
            LocalSettingsCompanion.insert(
              createdAt: now,
              updatedAt: now,
              activeThemeId: Value(id),
            ),
          );
      return;
    }
    await (_db.update(_db.localSettings)).write(
      LocalSettingsCompanion(
        activeThemeId: Value(id),
        updatedAt: Value(now),
      ),
    );
  }

  /// Saves a theme. With [id] null a new row is created. Built-in rows are
  /// never overwritten in place: saving over one creates an editable copy so
  /// the shipped defaults stay intact.
  Future<ThemeProfile> save({
    String? id,
    required ThemeProfileData data,
    bool makeActive = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (id != null) {
      final existing = await getById(id);
      if (existing != null && existing.isBuiltin == 1) {
        // Duplicate instead of mutating the shipped theme.
        final copyId = Ids.next('theme');
        await _db.into(_db.themes).insert(
              ThemesCompanion.insert(
                id: copyId,
                name: data.name,
                isBuiltin: const Value(0),
                payload: data.encode(),
                createdAt: now,
                updatedAt: now,
              ),
            );
        if (makeActive) {
          await setActive(copyId);
        }
        return (await getById(copyId))!;
      }
      if (existing != null) {
        await (_db.update(_db.themes)..where((t) => t.id.equals(id))).write(
          ThemesCompanion(
            name: Value(data.name),
            payload: Value(data.encode()),
            updatedAt: Value(now),
          ),
        );
        if (makeActive) {
          await setActive(id);
        }
        return (await getById(id))!;
      }
    }
    final newId = id ?? Ids.next('theme');
    await _db.into(_db.themes).insert(
          ThemesCompanion.insert(
            id: newId,
            name: data.name,
            isBuiltin: const Value(0),
            payload: data.encode(),
            createdAt: now,
            updatedAt: now,
          ),
        );
    if (makeActive) {
      await setActive(newId);
    }
    return (await getById(newId))!;
  }

  /// Imports a theme document (the JSON text of a theme file).
  ///
  /// Returns the stored row. Throws [FormatException] when the document is not
  /// a valid theme, so the UI can report it instead of silently doing nothing.
  Future<ThemeProfile> importJson(String body, {bool makeActive = true}) async {
    final data = ThemeProfileData.decode(body);
    // Imported themes always become user themes, even if they claim to be a
    // built-in, otherwise an import could shadow a shipped default.
    return save(data: data, makeActive: makeActive);
  }

  /// Exports a theme as pretty-printed JSON.
  String exportJson(ThemeProfile row, {String? nameOverride}) {
    final data = dataOf(row);
    final export = nameOverride == null || nameOverride.isEmpty
        ? data
        : data.copyWith(name: nameOverride);
    return export.encode();
  }

  /// Deletes a user theme. Built-ins are refused (return false).
  Future<bool> delete(String id) async {
    final existing = await getById(id);
    if (existing == null || existing.isBuiltin == 1) {
      return false;
    }
    await (_db.delete(_db.themes)..where((t) => t.id.equals(id))).go();
    final settings = await _db.select(_db.localSettings).getSingleOrNull();
    if (settings?.activeThemeId == id) {
      await setActive(null);
    }
    return true;
  }

  /// A readable default file name for an exported theme.
  static String fileNameFor(ThemeProfileData data) {
    final safe = data.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return '${safe.isEmpty ? 'theme' : safe}.threadflow-theme.json';
  }

  /// True when [body] parses as a theme document. Used to give a clear error
  /// before touching the database.
  static bool isValidThemeJson(String body) {
    try {
      ThemeProfileData.decode(body);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Convenience for tests and callers that already hold a JSON map.
  static String encodeMap(Map<String, dynamic> json) =>
      const JsonEncoder.withIndent('  ').convert(json);
}
