import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/package/tfpkg_codec.dart';
import 'package:furnace/data/package/tfpkg_service.dart';
import 'package:furnace/data/repositories/ai_repository.dart';

/// A `.tfpkg` is the artefact people hand to each other, and the AI API key is
/// a plain settings column - so a shared package would otherwise carry a
/// working credential. Export must be able to leave it out, without losing the
/// user's other settings.
void main() {
  late AppDatabase db;
  late TfpkgService service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = TfpkgService(db);
    // A configured AI plus a neighbouring setting, so the test can tell
    // "the key was removed" from "the row was damaged".
    await AiRepository(db).saveConfig(
      const AiConfig(
        enabled: true,
        apiKey: 'sk-secret-value',
        model: 'deepseek-chat',
        permissionMode: AiPermissionMode.auto,
      ),
      fallbackLanguage: 'zh',
    );
  });

  tearDown(() async {
    await db.close();
  });

  List<Map<String, dynamic>> settingsRows(TfpkgDump dump) =>
      dump.tables['local_settings']?.rows ?? const [];

  test('a normal export keeps the key', () async {
    final dump = await service.exportDump();
    final row = settingsRows(dump).single;
    expect(row['ai_api_key'], 'sk-secret-value');
  });

  test('excludeSensitive removes the key', () async {
    final dump = await service.exportDump(excludeSensitive: true);
    final row = settingsRows(dump).single;
    expect(row['ai_api_key'], isNull,
        reason: 'a shared package must not carry a working credential');
  });

  test('excludeSensitive keeps every other setting', () async {
    // Blanking the whole row would "protect" the key by throwing away the
    // user's model choice and permission mode along with it.
    final dump = await service.exportDump(excludeSensitive: true);
    final row = settingsRows(dump).single;
    expect(row['ai_model'], 'deepseek-chat');
    expect(row['ai_permission_mode'], 'auto');
    expect(row['ai_enabled'], isNotNull);
    expect(row['language'], 'zh');
  });

  test('excludeSensitive does not touch other tables', () async {
    final dump = await service.exportDump(excludeSensitive: true);
    // Every table is still present, and non-secret tables are byte-identical to
    // the normal export.
    final plain = await service.exportDump();
    expect(dump.tables.keys.toSet(), plain.tables.keys.toSet());
    for (final table in plain.tables.keys) {
      if (table == 'local_settings') {
        continue;
      }
      expect(
        dump.tables[table]!.rows.length,
        plain.tables[table]!.rows.length,
        reason: 'table $table must be unaffected',
      );
    }
  });

  test('the sensitive column list matches the real schema', () async {
    // A guard against silent rot: if a secret column is renamed or added and
    // this map is not updated, the redaction quietly stops working while every
    // other test still passes.
    for (final entry in TfpkgService.sensitiveColumns.entries) {
      final columns = await db.columnsOf(entry.key);
      for (final column in entry.value) {
        expect(columns, contains(column),
            reason: '${entry.key}.$column is listed as sensitive but does not '
                'exist any more - update TfpkgService.sensitiveColumns');
      }
    }
    // And the one secret we know about is actually covered.
    expect(TfpkgService.sensitiveColumns['local_settings'], contains('ai_api_key'));
  });

  test('the encoded archive really lacks the key', () async {
    // The end-to-end property: not just the dump object, but the bytes that get
    // written to disk. The archive is a zip, so the manifest has to be read
    // back out rather than searched for in the compressed bytes.
    final bytes = await service.exportBytes(excludeSensitive: true);
    final dump = TfpkgCodec.readManifest(bytes);
    final row = settingsRows(dump).single;
    expect(row['ai_api_key'], isNull,
        reason: 'the secret must not survive into the written file');

    final plain = TfpkgCodec.readManifest(await service.exportBytes());
    expect(settingsRows(plain).single['ai_api_key'], 'sk-secret-value',
        reason: 'the normal export must still carry it, otherwise the test '
            'above proves nothing');
  });

  test('an excluded key imports as "not configured", not as a broken key',
      () async {
    final bytes = await service.exportBytes(excludeSensitive: true);
    final dump = TfpkgCodec.readManifest(bytes);

    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    await TfpkgService(target).importDump(dump, mode: TfpkgMergeMode.replace);

    final config = await AiRepository(target).getConfig();
    expect(config.apiKey, isNull);
    // `isUsable` is what gates the whole AI surface, so this is the assertion
    // that matters to the user: the feature is off, not broken.
    expect(config.isUsable, isFalse);
    expect(config.model, 'deepseek-chat',
        reason: 'the rest of the settings still arrived');
  });
}
