import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

/// The single local SQLite database for Furnace.
@DriftDatabase(
  tables: [
    Profiles,
    LocalSettings,
    Tags,
    ObjectTags,
    MindMaps,
    MindNodes,
    Tasks,
    TaskDependencies,
    TimeBlocks,
    TaskTimeBlocks,
    KnowledgePoints,
    CardTemplates,
    CardStates,
    ReviewLogs,
    KnowledgePackages,
    PackageItems,
    // v2 (Threadflow, historical name)
    ThreadStates,
    TaskTemplates,
    CompletionLogs,
    ClozeSlots,
    ClozeHistory,
    BoostEntries,
    Themes,
    Attachments,
    // v3 (blueprint v2, user annotations 2026-09-08)
    ThreadRankSettings,
    DiffusionLogs,
    // v4 (Time module, user feedback item 3)
    TimeTemplates,
    TimeViewSettings,
    // v6 (AI integration + MindNet port prerequisites)
    AiConversations,
    AiMessages,
    AiActions,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Creates an in-memory/testing database from an existing [executor].
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
      },
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          await _upgradeV1ToV2();
        }
        if (from < 3) {
          await _upgradeV2ToV3();
        }
        if (from < 4) {
          await _upgradeV3ToV4();
        }
        if (from < 5) {
          await _upgradeV4ToV5();
        }
        if (from < 6) {
          await _upgradeV5ToV6();
        }
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
        // Self-heal a version number that claims more than the file actually
        // has. Drift only runs `onUpgrade` when the stored user_version is
        // BELOW the schema version, so a file stamped v5 without every v5
        // column never gets repaired - and Drift's generated mapper then
        // throws on a non-null read (observed on a real development database
        // whose time_view_settings had no minutes_per_row_chosen column while
        // user_version already read 5).
        await _ensureColumns();
      },
    );
  }

  /// Adds any column the current schema expects but the file lacks.
  ///
  /// Safe to run on every open: each entry is probed first, so a healthy
  /// database does nothing here.
  Future<void> _ensureColumns() async {
    final expected = <String, List<GeneratedColumn<Object>>>{
      'tasks': [tasks.startedAt],
      'completion_logs': [
        completionLogs.actualMinutes,
        completionLogs.includeInModel,
        completionLogs.durationSuspicious,
      ],
      'time_view_settings': [timeViewSettings.minutesPerRowChosen],
      // v6: without these the generated mappers throw on existing rows when a
      // file is stamped v6 but was written by an older build.
      'local_settings': [
        localSettings.aiEnabled,
        localSettings.aiApiKey,
        localSettings.aiBaseUrl,
        localSettings.aiModel,
        localSettings.aiPermissionMode,
      ],
      'card_states': [
        cardStates.encodingStrength,
        cardStates.savings,
      ],
    };
    final m = Migrator(this);
    for (final entry in expected.entries) {
      if (!await _tableExists(entry.key)) {
        continue;
      }
      for (final column in entry.value) {
        await _addColumnIfMissing(m, entry.key, column);
      }
    }
  }

  /// v4 -> v5: the day/week grid no longer defaults to whole-hour rows.
  ///
  /// The old shipped default was 60 minutes per row. Everyone who never chose
  /// a row size themselves is moved to the new 30-minute default, while a
  /// deliberate 15/30/60 choice is preserved (that is what
  /// `minutes_per_row_chosen` records).
  /// v5 -> v6: AI conversation storage, AI settings columns, and the two
  /// cognitive-model fields.
  ///
  /// Three separate things land here on purpose, as ONE migration:
  ///
  ///  1. `ai_conversations` / `ai_messages` / `ai_actions` - the conversation is
  ///     the AI surface, so it is ordinary user data (docs/AI_DESIGN.md).
  ///  2. `local_settings` gains the AI configuration columns. Everything is
  ///     nullable/defaulted so an existing row means "AI is off" without a
  ///     rewrite - the app must behave exactly as before until a key is set.
  ///  3. `card_states` gains `encoding_strength` (MindNet `R0`) and `savings`
  ///     (`Sigma`). These are prerequisites for porting the cognitive model:
  ///     without R0 the FSRS curve and MindNet's `R = R0*Psi(t/S)` disagree
  ///     once `R0 < 1`, and without Sigma the stability-increase term is
  ///     incomplete (docs/MINDNET_CONTRACT.md 8.3).
  ///
  /// Additive only, and idempotent: `Migrator.createTable` always emits the
  /// current schema, so a database arriving from v1 already has these tables
  /// after [_upgradeV1ToV2] and every step is existence-probed first.
  Future<void> _upgradeV5ToV6() async {
    final m = Migrator(this);

    if (!await _tableExists('ai_conversations')) {
      await m.createTable(aiConversations);
    }
    if (!await _tableExists('ai_messages')) {
      await m.createTable(aiMessages);
    }
    if (!await _tableExists('ai_actions')) {
      await m.createTable(aiActions);
    }

    if (await _tableExists('local_settings')) {
      for (final column in [
        localSettings.aiEnabled,
        localSettings.aiApiKey,
        localSettings.aiBaseUrl,
        localSettings.aiModel,
        localSettings.aiPermissionMode,
      ]) {
        await _addColumnIfMissing(m, 'local_settings', column);
      }
    }

    if (await _tableExists('card_states')) {
      for (final column in [
        cardStates.encodingStrength,
        cardStates.savings,
      ]) {
        await _addColumnIfMissing(m, 'card_states', column);
      }
    }
  }

  Future<void> _upgradeV4ToV5() async {    if (!await _tableExists('time_view_settings')) {
      return;
    }
    // A database whose time_view_settings was created from the pre-v5 schema
    // has no `minutes_per_row_chosen` column, and Drift cannot map its rows
    // without it (the generated mapper does a non-null read). Add it first;
    // that also records "no deliberate choice" for every existing row, which
    // is exactly the state the UPDATE below needs.
    final m = Migrator(this);
    await _addColumnIfMissing(
        m, 'time_view_settings', timeViewSettings.minutesPerRowChosen);
    await customStatement(
      'UPDATE time_view_settings SET minutes_per_row = 30 '
      'WHERE minutes_per_row_chosen = 0',
    );
  }

  /// v3 -> v4 (Time module, user feedback item 3): weekly/daily schedule
  /// templates and the single-row view preferences for the long-range
  /// timeline. Additive only; guarded by existence probes so the v1 -> v4 and
  /// v2 -> v4 paths (where `createTable` already emitted the current schema)
  /// do not fail.
  Future<void> _upgradeV3ToV4() async {
    final m = Migrator(this);
    if (!await _tableExists('time_templates')) {
      await m.createTable(timeTemplates);
    }
    if (!await _tableExists('time_view_settings')) {
      await m.createTable(timeViewSettings);
    }
  }

  /// v2 -> v3 (blueprint v2 / user annotations 2026-09-08):
  /// - Tasks.started_at: the moment the user started the event.
  /// - CompletionLogs.actual_minutes / include_in_model / duration_suspicious:
  ///   actual duration recorded from two stamps, plus the anomaly guard.
  /// - New tables: thread_rank_settings (public, editable ranking parameters)
  ///   and diffusion_logs (daily study ledger for the review-insight screen).
  ///
  /// Purely additive: no existing column is rewritten, so legacy rows keep
  /// working (they read as NULL / defaulted).
  ///
  /// Idempotent on purpose: `Migrator.createTable` always emits the CURRENT
  /// schema, so a database coming from v1 already has the v3 columns (and the
  /// v3 tables) after [_upgradeV1ToV2] ran. Everything here is therefore
  /// guarded by an existence probe so the v1 -> v3 path does not double-add.
  Future<void> _upgradeV2ToV3() async {
    final m = Migrator(this);

    if (!await _tableExists('thread_rank_settings')) {
      await m.createTable(threadRankSettings);
    }
    if (!await _tableExists('diffusion_logs')) {
      await m.createTable(diffusionLogs);
    }

    await _addColumnIfMissing(m, 'tasks', tasks.startedAt);
    await _addColumnIfMissing(
        m, 'completion_logs', completionLogs.actualMinutes);
    await _addColumnIfMissing(
        m, 'completion_logs', completionLogs.includeInModel);
    await _addColumnIfMissing(
        m, 'completion_logs', completionLogs.durationSuspicious);
  }

  Future<void> _addColumnIfMissing(
    Migrator m,
    String table,
    GeneratedColumn<Object> column,
  ) async {
    if (await _columnExists(table, column.name)) {
      return;
    }
    await m.addColumn(_tableFor(table), column);
  }

  // --- logical dump support (.tfpkg) ---------------------------------------

  /// Every user table in the database, in dependency-friendly order.
  ///
  /// Excludes SQLite's own bookkeeping and Drift's migration metadata. Reading
  /// the list instead of hard-coding it means a new table is exported
  /// automatically and can never be forgotten in a backup.
  Future<List<String>> userTables() async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ).get();
    return [for (final row in rows) row.read<String>('name')];
  }

  /// The column names of [table].
  Future<List<String>> columnsOf(String table) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return [for (final row in rows) row.read<String>('name')];
  }

  /// Reads a whole table as JSON-safe maps.
  Future<List<Map<String, dynamic>>> dumpTable(String table) async {
    final rows = await customSelect('SELECT * FROM $table').get();
    return [
      for (final row in rows)
        {
          for (final name in row.data.keys) name: _toJsonSafe(row.data[name]),
        },
    ];
  }

  /// Writes rows into [table], inserting only the columns that both the file
  /// and the current schema know about.
  ///
  /// [mode] `replace` empties the table first (used by the overwrite import),
  /// `insert` leaves existing rows alone and skips primary-key clashes (used
  /// by the append import).
  Future<int> restoreTable(
    String table,
    List<Map<String, dynamic>> rows, {
    String mode = 'insert',
  }) async {
    if (rows.isEmpty) {
      return 0;
    }
    final known = (await columnsOf(table)).toSet();
    if (mode == 'replace') {
      await customStatement('DELETE FROM $table');
    }
    var written = 0;
    for (final row in rows) {
      final entries = [
        for (final entry in row.entries)
          if (known.contains(entry.key)) entry,
      ];
      if (entries.isEmpty) {
        continue;
      }
      final columns = entries.map((e) => e.key).join(', ');
      final placeholders = List.filled(entries.length, '?').join(', ');
      final verb = mode == 'replace' ? 'INSERT' : 'INSERT OR IGNORE';
      await customStatement(
        '$verb INTO $table ($columns) VALUES ($placeholders)',
        [for (final entry in entries) _fromJsonSafe(entry.value)],
      );
      written++;
    }
    return written;
  }

  /// Turns a stored value into something `jsonEncode` accepts.
  ///
  /// BLOBs are the only awkward case: they are base64-tagged so a round trip
  /// through JSON stays byte-exact instead of turning into a list of numbers.
  static Object? _toJsonSafe(Object? value) {
    if (value is Uint8List) {
      return {'__blob__': base64Encode(value)};
    }
    return value;
  }

  /// Reverses [_toJsonSafe].
  static Object? _fromJsonSafe(Object? value) {
    if (value is Map && value.containsKey('__blob__')) {
      return base64Decode(value['__blob__'] as String);
    }
    return value;
  }

  /// The generated table object for a SQL table name.
  ///
  /// Used by the `_ensureColumns` self-heal pass and by the `.tfpkg` dump /
  /// restore path, so every table those two touch must appear here.
  TableInfo<Table, dynamic> _tableFor(String name) {
    switch (name) {
      case 'tasks':
        return tasks;
      case 'completion_logs':
        return completionLogs;
      case 'time_view_settings':
        return timeViewSettings;
      case 'time_templates':
        return timeTemplates;
      // v6: the self-heal pass adds columns to these two, and the package
      // dump/restore path resolves every user table by name.
      case 'local_settings':
        return localSettings;
      case 'card_states':
        return cardStates;
      case 'ai_conversations':
        return aiConversations;
      case 'ai_messages':
        return aiMessages;
      case 'ai_actions':
        return aiActions;
      default:
        throw ArgumentError('unknown table $name');
    }
  }

  Future<bool> _tableExists(String name) async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(name)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> _columnExists(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    for (final row in rows) {
      if (row.read<String>('name') == column) {
        return true;
      }
    }
    return false;
  }

  /// v1 -> v2: new tables, new columns, relaxed card_state /
  /// review_log FKs and backfills. See docs/DATA_MODEL.md §7.
  ///
  /// The rebuilds (card_states, review_logs) run while foreign keys are still
  /// OFF (they are only enabled in beforeOpen), so dropping/renaming parent
  /// tables mid-migration cannot trip FK enforcement.
  Future<void> _upgradeV1ToV2() async {
    final m = Migrator(this);

    // 1. New tables.
    await m.createTable(threadStates);
    await m.createTable(taskTemplates);
    await m.createTable(completionLogs);
    await m.createTable(clozeSlots);
    await m.createTable(clozeHistory);
    await m.createTable(boostEntries);
    await m.createTable(themes);
    await m.createTable(attachments);

    // 2. Plain ADD COLUMN on existing tables.
    await m.addColumn(tasks, tasks.expectedAt);
    await m.addColumn(tasks, tasks.energyRequired);
    await m.addColumn(tasks, tasks.completedAt);
    await m.addColumn(localSettings, localSettings.activeThemeId);
    await m.addColumn(knowledgePoints, knowledgePoints.contentFormat);
    await m.addColumn(tags, tags.parentId);
    await m.addColumn(tags, tags.path);

    // 3. Rebuild card_states with nullable card_template_id + v2 fields.
    await customStatement('''
CREATE TABLE card_states_new (
  id TEXT NOT NULL PRIMARY KEY,
  card_template_id TEXT REFERENCES card_templates(id),
  due_at INTEGER,
  interval_days REAL NOT NULL DEFAULT 0,
  ease REAL NOT NULL DEFAULT 2.5,
  repetitions INTEGER NOT NULL DEFAULT 0,
  lapses INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL DEFAULT 'new',
  last_reviewed_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  knowledge_point_id TEXT REFERENCES knowledge_points(id),
  unit_key TEXT,
  stability REAL,
  difficulty REAL,
  forced INTEGER NOT NULL DEFAULT 0,
  forced_streak INTEGER NOT NULL DEFAULT 0
)''');
    await customStatement('''
INSERT INTO card_states_new (
  id, card_template_id, due_at, interval_days, ease, repetitions, lapses,
  state, last_reviewed_at, created_at, updated_at
)
SELECT id, card_template_id, due_at, interval_days, ease, repetitions, lapses,
       state, last_reviewed_at, created_at, updated_at
FROM card_states''');
    await customStatement('DROP TABLE card_states');
    await customStatement('ALTER TABLE card_states_new RENAME TO card_states');

    // 4. Backfill presentation-unit fields for legacy preset cards.
    await customStatement('''
UPDATE card_states
SET knowledge_point_id = (
      SELECT knowledge_point_id FROM card_templates t
      WHERE t.id = card_states.card_template_id
    ),
    unit_key = 'preset:' || card_template_id
WHERE card_template_id IS NOT NULL''');

    // 5. Rebuild review_logs with nullable card_template_id + v2 fields.
    await customStatement('''
CREATE TABLE review_logs_new (
  id TEXT NOT NULL PRIMARY KEY,
  card_state_id TEXT REFERENCES card_states(id),
  card_template_id TEXT REFERENCES card_templates(id),
  unit_key TEXT,
  rating INTEGER NOT NULL,
  rating_fsrs INTEGER,
  correct INTEGER,
  judge_mode TEXT,
  format TEXT,
  ms_taken INTEGER,
  reviewed_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
)''');
    await customStatement('''
INSERT INTO review_logs_new (
  id, card_state_id, card_template_id, rating, reviewed_at, created_at
)
SELECT id, card_state_id, card_template_id, rating, reviewed_at, created_at
FROM review_logs''');
    await customStatement('DROP TABLE review_logs');
    await customStatement('ALTER TABLE review_logs_new RENAME TO review_logs');

    // 6. Tags: backfill authoritative path, de-duplicate same-name top tags
    // (keep the oldest id plain, suffix the rest).
    await customStatement("UPDATE tags SET path = name WHERE path IS NULL");
    await customStatement('''
UPDATE tags
SET path = name || '-' || rn
FROM (
  SELECT id, ROW_NUMBER() OVER (PARTITION BY name ORDER BY id) AS rn
  FROM tags
) x
WHERE tags.id = x.id AND x.rn > 1''');
    await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_path ON tags(path)');

    // 7. v2 indexes.
    await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_card_states_unit '
        'ON card_states(knowledge_point_id, unit_key)');
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final target = File(p.join(dir.path, 'furnace.db'));

    // Database file resolution, newest name first.
    //
    // The app has been renamed twice, and each name used to own the database
    // file. An existing install must keep its data, so the legacy names are
    // still served - the schema migration runs in place on open, exactly as it
    // did when the file was current.
    //
    //   furnace.db      (current)
    //   threadflow.db   (previous name)
    //   knowflow.db     (original name)
    final active = _adoptLegacyDatabase(dir, target);
    return NativeDatabase(active);
  });
}

/// Resolves the file that actually holds this install's data.
///
/// Two kinds of legacy layout have to keep working:
///
///  1. **Same directory, older file name.** `furnace.db` / `threadflow.db` /
///     `knowflow.db` inside the current app-support directory.
///  2. **Older directory.** `getApplicationSupportDirectory()` is derived from
///     the executable's company/product metadata on Windows and from the
///     application id on Android. Renaming the app changed both, so a
///     pre-rename install keeps its data under a *different* directory. That
///     case cannot be handled by file-name fallback alone, which is exactly how
///     the rename could have silently started the user on an empty database.
///
/// When a legacy database is found in another directory it is **copied** to
/// [target] and the copy wins from then on. The copy is deliberate, not a move:
/// if it fails, the original is left untouched and the app keeps using it.
///
/// Verified on this machine: renaming the Windows metadata moved the directory
/// from `%APPDATA%\com.example\knowflow` to `%APPDATA%\FirsryFan\Furnace`, and
/// the legacy file there held the real rows (time blocks) while the freshly
/// created `furnace.db` held only seed data. After the fix, the copy landed at
/// the new path with an identical file hash and the original was untouched.
///
/// [applicationDataDir] overrides the roaming-app-data root and exists for
/// tests; production always reads the environment.
File _adoptLegacyDatabase(
  Directory dir,
  File target, {
  String? applicationDataDir,
}) {
  if (target.existsSync()) return target;

  for (final name in const ['threadflow.db', 'knowflow.db']) {
    final sibling = File(p.join(dir.path, name));
    if (sibling.existsSync()) return sibling;
  }

  final missed = _firstLegacyDirectoryOutside(dir, applicationDataDir);
  if (missed != null) {
    try {
      missed.copySync(target.path);
      return target;
    } on FileSystemException {
      // Read-only or full disk: never lose the data, keep using the original.
      return missed;
    }
  }

  return target;
}

/// Test seam for [_adoptLegacyDatabase]: the file-name/directory resolution that
/// decides which database an install actually opens.
///
/// Exposed because the failure it guards against is invisible in normal use -
/// a wrong answer is not an exception, it is an empty-looking app.
File resolveDatabaseFileForTest(
  String currentDirectory,
  File target, {
  String? applicationDataDir,
}) =>
    _adoptLegacyDatabase(
      Directory(currentDirectory),
      target,
      applicationDataDir: applicationDataDir,
    );

/// Looks in the directories this install used before the rename.
///
/// A candidate only counts when it actually holds a database, so an empty
/// leftover directory never hijacks a fresh install.
File? _firstLegacyDirectoryOutside(Directory current, [String? applicationDataDir]) {
  final appData = applicationDataDir ?? Platform.environment['APPDATA'];
  final candidates = <String>[
    if (appData != null && appData.isNotEmpty)
      p.join(appData, 'com.example', 'knowflow'),
    if (appData != null && appData.isNotEmpty)
      p.join(appData, 'FirsryFan', 'Furnace'),
    p.join(p.dirname(current.path), 'knowflow'),
  ];

  for (final candidate in candidates) {
    if (p.equals(candidate, current.path)) continue;
    for (final name in const ['furnace.db', 'threadflow.db', 'knowflow.db']) {
      final file = File(p.join(candidate, name));
      if (file.existsSync() && file.lengthSync() > 0) return file;
    }
  }
  return null;
}
