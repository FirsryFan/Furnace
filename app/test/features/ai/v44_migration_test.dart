import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v43 -> v44: `ai_conversations.agent_preset_id` / `subagent_preset_id`.
///
/// The two claims that can fail independently:
///
///  1. A real v43 file opens and gains the columns (no missing-column crash on
///     the first conversation read).
///  2. A file stamped v44 whose columns were never written is healed on open by
///     the same `beforeOpen` self-heal every other additive column uses, because
///     Drift skips `onUpgrade` for a file whose version is already current.
///
/// The old row must read back as NULL for both columns: NULL is the explicit
/// "written before presets existed" state, which the repository resolves to
/// `assistant` / `inherit`. The migration deliberately writes no value - writing
/// 'assistant' into old rows would freeze a choice the user never made, the same
/// contract as `ai_max_rounds` and the other nullable preferences.
void main() {
  late Directory tempDir;

  /// A minimal v43-shaped database: only the table this migration touches, plus
  /// the old conversation row. Other tables are created by the self-heal where
  /// the migration code expects them; this test never reads them.
  File buildV43Db({int userVersion = 43, bool withV44Columns = false}) {
    final name = 'v43_${userVersion}_$withV44Columns.db';
    final file = File('${tempDir.path}/$name');
    final db = sql.sqlite3.open(file.path);
    db.execute('''
CREATE TABLE ai_conversations (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL${withV44Columns ? ', agent_preset_id TEXT, subagent_preset_id TEXT' : ''}
)''');
    db.execute('''
INSERT INTO ai_conversations (id, title, created_at, updated_at)
VALUES ('conv_old', '升级前的对话', 1700000000000, 1700000000000)''');
    db.execute('PRAGMA user_version = $userVersion');
    db.dispose();
    return file;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig44_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a real v43 file gains both preset columns, old rows read NULL',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase(buildV43Db()));

    final row = (await db.select(db.aiConversations).get()).single;
    expect(row.title, '升级前的对话', reason: 'the upgrade must keep the row');
    expect(row.agentPresetId, isNull,
        reason: 'NULL = written before presets existed, not a frozen choice');
    expect(row.subagentPresetId, isNull);
    await db.close();
  });

  test('a file stamped v44 but missing the columns is healed on open',
      () async {
    // The real-world shape this project already hit with v5/v6/v7: user_version
    // says the new version, so Drift skips onUpgrade entirely, yet the columns
    // were never written. beforeOpen must repair the file.
    final db = AppDatabase.forTesting(
      NativeDatabase(buildV43Db(userVersion: 44)),
    );
    final row = (await db.select(db.aiConversations).get()).single;
    expect(row.agentPresetId, isNull,
        reason: 'beforeOpen must have added the column');
    expect(row.subagentPresetId, isNull);
    await db.close();
  });

  test('a v44 file that already has the columns keeps their values', () async {
    final file = buildV43Db(userVersion: 44, withV44Columns: true);
    final raw = sql.sqlite3.open(file.path);
    raw.execute('''
UPDATE ai_conversations
SET agent_preset_id = 'student_solver', subagent_preset_id = 'student_solver'
WHERE id = 'conv_old' ''');
    raw.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    final row = (await db.select(db.aiConversations).get()).single;
    expect(row.agentPresetId, 'student_solver');
    expect(row.subagentPresetId, 'student_solver');
    await db.close();
  });
}
