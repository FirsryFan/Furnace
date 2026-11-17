import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart'
    show ReasoningEffort;
import 'package:sqlite3/sqlite3.dart' as sql;

/// v45 -> v46: the eight `local_settings` columns of the model-parameter layer
/// (MODEL-CONFIG-2026-11-15.md).
///
/// Four claims, each of which can fail independently:
///
///  1. A real v45 file opens and gains all eight columns; the existing settings
///     row (language, key, model, permission mode) is unchanged.
///  2. The upgraded row reads NULL for every parameter, i.e. the app resolves
///     the old shipped values - the migration must not freeze today's defaults
///     into the file.
///  3. A file stamped v46 whose columns were never written is healed by the
///     `beforeOpen` self-heal that every other additive column uses, because
///     Drift skips `onUpgrade` when the stored version is already current.
///  4. A fresh database (onCreate) has the columns at the current schemaVersion
///     (v47 since the ThreadFlow/content foundation), and the chosen values
///     survive a write/read round-trip.
void main() {
  late Directory tempDir;

  const v46Columns = <String>[
    'ai_reasoning_effort',
    'ai_temperature',
    'ai_answer_temperature',
    'ai_verifier_temperature',
    'ai_max_reasoning_tokens',
    'ai_answer_reserve_tokens',
    'ai_verifier_model',
    'ai_verifier_effort',
  ];

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig46_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Current-schema database with one settings row written, then the eight v46
  /// columns dropped and `user_version` forced to [userVersion] - i.e. the file
  /// a v45 install has, or a file stamped v46 before the columns existed.
  Future<File> buildPreV46Db({
    required String name,
    int userVersion = 45,
  }) async {
    final file = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(file));
    await fresh.into(fresh.localSettings).insert(
          LocalSettingsCompanion.insert(
            id: const Value(1),
            language: const Value('zh'),
            createdAt: 1700000000000,
            updatedAt: 1700000000000,
          ),
        );
    await (fresh.update(fresh.localSettings)
          ..where((t) => t.id.equals(1)))
        .write(const LocalSettingsCompanion(
      aiEnabled: Value(true),
      aiApiKey: Value('sk-old-key'),
      aiModel: Value('deepseek-chat'),
      aiPermissionMode: Value('auto'),
    ));
    await fresh.close();

    final raw = sql.sqlite3.open(file.path);
    try {
      for (final column in v46Columns) {
        raw.execute('ALTER TABLE local_settings DROP COLUMN $column');
      }
      raw.execute('PRAGMA user_version = $userVersion');
    } finally {
      raw.dispose();
    }
    return file;
  }

  int userVersionOf(String path) {
    final raw = sql.sqlite3.open(path);
    try {
      return raw.select('PRAGMA user_version').single['user_version'] as int;
    } finally {
      raw.dispose();
    }
  }

  Future<void> expectAllColumnsPresent(AppDatabase db) async {
    final columns = await db.columnsOf('local_settings');
    for (final column in v46Columns) {
      expect(columns, contains(column));
    }
  }

  Future<void> expectOldSettingsIntact(AppDatabase db) async {
    final row = (await db.select(db.localSettings).get()).single;
    expect(row.id, 1);
    expect(row.language, 'zh');
    expect(row.themeMode, 'system');
    expect(row.aiEnabled, isTrue);
    expect(row.aiApiKey, 'sk-old-key');
    expect(row.aiModel, 'deepseek-chat');
    expect(row.aiPermissionMode, 'auto');
    // The new columns are NULL: "the user never chose", so the repository
    // resolves the pre-v46 values.
    expect(row.aiReasoningEffort, isNull);
    expect(row.aiTemperature, isNull);
    expect(row.aiAnswerTemperature, isNull);
    expect(row.aiVerifierTemperature, isNull);
    expect(row.aiMaxReasoningTokens, isNull);
    expect(row.aiAnswerReserveTokens, isNull);
    expect(row.aiVerifierModel, isNull);
    expect(row.aiVerifierEffort, isNull);

    final config = await AiRepository(db).getConfig();
    expect(config.enabled, isTrue);
    expect(config.apiKey, 'sk-old-key');
    expect(config.model, 'deepseek-chat');
    expect(config.permissionMode, AiPermissionMode.auto);
    expect(config.effectiveTemperature, 0.6);
    expect(config.effectiveAnswerTemperature, 0.2);
    expect(config.effectiveVerifierTemperature, 0.2);
    expect(config.effectiveMaxReasoningTokens, 20000);
    expect(config.effectiveAnswerReserveTokens, 3000);
    expect(config.reasoningEffort, isNull);
    expect(config.verifierEffort, isNull);
    expect(config.effectiveVerifierModel, 'deepseek-chat');
  }

  test('a real v45 file gains the eight columns and keeps its settings',
      () async {
    final file = await buildPreV46Db(name: 'v45_upgrade');
    expect(userVersionOf(file.path), 45);

    final db = AppDatabase.forTesting(NativeDatabase(file));
    await expectAllColumnsPresent(db);
    await expectOldSettingsIntact(db);

    // The new columns are writable through the repository.
    final repository = AiRepository(db);
    final config = await repository.getConfig();
    await repository.saveConfig(
      config.copyWith(
        reasoningEffort: ReasoningEffort.low,
        temperature: 1.1,
        maxReasoningTokens: 50000,
        answerReserveTokens: 1200,
        verifierModel: 'deepseek-flash',
        verifierEffort: ReasoningEffort.max,
      ),
      fallbackLanguage: 'system',
    );
    final reloaded = await repository.getConfig();
    expect(reloaded.reasoningEffort, ReasoningEffort.low);
    expect(reloaded.temperature, 1.1);
    expect(reloaded.maxReasoningTokens, 50000);
    expect(reloaded.answerReserveTokens, 1200);
    expect(reloaded.verifierModel, 'deepseek-flash');
    expect(reloaded.verifierEffort, ReasoningEffort.max);
    await db.close();

    expect(userVersionOf(file.path), 48);
  });

  test('migration is idempotent: opening twice does not throw or change data',
      () async {
    final file = await buildPreV46Db(name: 'twice');

    var db = AppDatabase.forTesting(NativeDatabase(file));
    await expectAllColumnsPresent(db);
    await expectOldSettingsIntact(db);
    await db.close();
    expect(userVersionOf(file.path), 48);

    // Second open: onUpgrade no longer runs, only beforeOpen probes.
    db = AppDatabase.forTesting(NativeDatabase(file));
    await expectAllColumnsPresent(db);
    await expectOldSettingsIntact(db);
    await db.close();
    expect(userVersionOf(file.path), 48);
  });

  test('a file stamped v46 but missing the columns is healed on open',
      () async {
    final file = await buildPreV46Db(name: 'fake46', userVersion: 46);
    expect(userVersionOf(file.path), 46);

    // Without the self-heal this read would throw "no such column".
    final db = AppDatabase.forTesting(NativeDatabase(file));
    await expectAllColumnsPresent(db);
    await expectOldSettingsIntact(db);
    await db.close();
    expect(userVersionOf(file.path), 48, reason: '打开时补上 v46 列，并一路升到当前 v48');
  });

  test('a fresh database has the current schemaVersion and the columns',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    expect(db.schemaVersion, 48);
    await db.select(db.localSettings).get(); // triggers onCreate
    await expectAllColumnsPresent(db);
    await db.close();
  });
}
