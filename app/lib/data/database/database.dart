import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

/// The single local SQLite database for Threadflow.
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
    // v2 (Threadflow)
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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Creates an in-memory/testing database from an existing [executor].
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 5;

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
  Future<void> _upgradeV4ToV5() async {
    if (!await _tableExists('time_view_settings')) {
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

  /// v1 -> v2 (Threadflow): new tables, new columns, relaxed card_state /
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
    // v2 database file name. Keep serving an existing v1 file so early users
    // keep their data; it is migrated in place on open.
    final v2File = File(p.join(dir.path, 'threadflow.db'));
    if (!v2File.existsSync()) {
      final legacyFile = File(p.join(dir.path, 'knowflow.db'));
      if (legacyFile.existsSync()) {
        return NativeDatabase(legacyFile);
      }
    }
    return NativeDatabase(v2File);
  });
}
