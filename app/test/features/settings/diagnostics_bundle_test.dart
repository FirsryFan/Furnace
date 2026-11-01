import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/package/tfpkg_codec.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/settings/application/diagnostics_bundle.dart';

/// The diagnostics bundle is what a user sends back when something went wrong
/// end-to-end: it must carry enough original text to reproduce the problem, and
/// it must never carry the API key - not in the settings summary, not inside the
/// attached workspace dump.
void main() {
  const fakeKey = 'sk-fake-diagnostics-key-9f3a';
  const stem = '已知函数 f(x)=x^2，求 f(x) 在 [0,1] 上的最小值。';

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // One configured AI key, one question and one AI conversation: the three
    // kinds of content the bundle is supposed to cover.
    await AiRepository(db).saveConfig(
      const AiConfig(
        enabled: true,
        apiKey: fakeKey,
        model: 'deepseek-chat',
        permissionMode: AiPermissionMode.auto,
      ),
      fallbackLanguage: 'zh',
    );
    await db.into(db.questions).insert(
          QuestionsCompanion.insert(
            id: 'q-1',
            stem: stem,
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    await db.into(db.aiConversations).insert(
          AiConversationsCompanion.insert(
            id: 'c-1',
            title: '二次函数求助',
            createdAt: 1,
            updatedAt: 2,
          ),
        );
    await db.into(db.aiMessages).insert(
          AiMessagesCompanion.insert(
            id: 'm-1',
            conversationId: 'c-1',
            role: 'user',
            content: const Value('帮我看看这道题'),
            createdAt: 2,
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  DiagnosticsBundleService service({
    DiagnosticsTfpkgExport? tfpkgExport,
    List<String> errors = const <String>[],
  }) =>
      DiagnosticsBundleService(
        database: db,
        tfpkgExport: tfpkgExport,
        now: () => DateTime.utc(2026, 11, 1, 12, 34),
        appVersion: '9.9.9',
        appBuildNumber: 99,
        platform: 'test-platform',
        errors: errors,
      );

  Map<String, List<int>> entriesOf(Uint8List bytes) => {
        for (final file in ZipDecoder().decodeBytes(bytes).files)
          if (file.isFile) file.name: file.content as List<int>,
      };

  Map<String, dynamic> diagOf(Map<String, List<int>> entries) =>
      jsonDecode(utf8.decode(entries[kDiagnosticsJsonEntry]!))
          as Map<String, dynamic>;

  test(
      'includes diag.json, README.txt and the workspace dump when content is on',
      () async {
    final bundle = await service().build(includeContent: true);
    expect(bundle.includesContent, isTrue);
    expect(bundle.fileName, 'furnace-diagnostics-20261101T1234.zip');

    final entries = entriesOf(bundle.bytes);
    expect(
      entries.keys,
      containsAll(<String>[
        kDiagnosticsJsonEntry,
        kDiagnosticsReadmeEntry,
        kDiagnosticsTfpkgEntry,
      ]),
    );
    expect(utf8.decode(entries[kDiagnosticsReadmeEntry]!), contains('.tfpkg'));

    final diag = diagOf(entries);
    expect(diag['format'], kDiagnosticsFormat);
    expect(diag['content_included'], isTrue);
    final app = diag['app'] as Map<String, dynamic>;
    expect(app['version'], '9.9.9');
    expect(app['build'], 99);
    expect(app['schema_version'], db.schemaVersion);
    expect(app['platform'], 'test-platform');
    expect(diag['question_bank'], containsPair('questions', 1));
    final samples = diag['question_samples'] as List<dynamic>;
    expect(samples, hasLength(1));
    expect(
      (samples.single as Map<String, dynamic>)['stem'],
      contains('f(x)=x^2'),
    );
    final conversations = diag['ai_conversations'] as List<dynamic>;
    expect(conversations, hasLength(1));
    expect((conversations.single as Map<String, dynamic>)['message_count'], 1);
    // The key is configured, so the summary has it - redacted.
    expect(
      (diag['settings_summary'] as Map<String, dynamic>)['ai_api_key'],
      '***',
    );
    expect((diag['ai'] as Map<String, dynamic>)['key_configured'], isTrue);
  });

  test('omits content when the switch is off, but keeps the summary', () async {
    final bundle = await service().build(includeContent: false);
    final entries = entriesOf(bundle.bytes);

    expect(entries.keys, hasLength(2));
    expect(entries.keys, isNot(contains(kDiagnosticsTfpkgEntry)));
    final diag = diagOf(entries);
    expect(diag['content_included'], isFalse);
    expect(diag.containsKey('question_samples'), isFalse);
    // Statistics survive even when the original text is left out.
    expect(diag['question_bank'], containsPair('questions', 1));
    // "A key exists" is a useful diagnostic and is not the key itself.
    expect((diag['ai'] as Map<String, dynamic>)['key_configured'], isTrue);
  });

  test('never contains the API key in any payload', () async {
    final bundle = await service().build(includeContent: true);
    final entries = entriesOf(bundle.bytes);

    for (final entry in entries.entries) {
      // diag.json / README.txt are plain text inside the zip.
      final text = utf8.decode(entry.value, allowMalformed: true);
      expect(
        text,
        isNot(contains(fakeKey)),
        reason: '${entry.key} must not contain the key',
      );
    }

    // workspace.tfpkg is compressed, so searching its raw bytes proves nothing;
    // decode it back to the logical dump and assert there.
    final dump = TfpkgCodec.readManifest(
      Uint8List.fromList(entries[kDiagnosticsTfpkgEntry]!),
    );
    final settingsRow = dump.tables['local_settings']!.rows.single;
    expect(
      settingsRow['ai_api_key'],
      isNull,
      reason: 'the dump must be generated with excludeSensitive=true',
    );
    final plaintext = jsonEncode(
      dump.tables.map((table, content) => MapEntry(table, content.rows)),
    );
    expect(plaintext, isNot(contains(fakeKey)));
  });

  test('aborts instead of leaking when the workspace dump carries the key',
      () async {
    var askedToExclude = false;
    Future<Uint8List> leaking({required bool excludeSensitive}) async {
      askedToExclude = excludeSensitive;
      return TfpkgCodec.encode(
        const TfpkgDump(
          tables: {
            'local_settings': TableDump(
              rows: [
                {'id': 1, 'ai_api_key': fakeKey},
              ],
            ),
          },
        ),
      );
    }

    await expectLater(
      service(tfpkgExport: leaking).build(includeContent: true),
      throwsA(isA<DiagnosticsBundleException>()),
    );
    expect(
      askedToExclude,
      isTrue,
      reason: 'the export seam must be asked to exclude secrets',
    );
  });

  test('carries the errors it was given', () async {
    final bundle = await service(errors: ['boom: failed to read widget']).build(
      includeContent: false,
    );
    final diag = diagOf(entriesOf(bundle.bytes));
    expect(diag['errors'], contains('boom: failed to read widget'));
  });
}
