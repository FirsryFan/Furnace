// Tests for the read-only probe in `tool/mindnet_probe.dart` and for the
// readings half it hands to the Flutter host.
//
// The probe's contract is "copy first, open only the copy, read-only, and never
// touch the original". These tests check the observable consequences of that:
// the original's SHA-256 and mtime are unchanged, the host is handed a path
// inside a temp directory, and every reading comes from the injected
// `CognitiveModel` rather than from arithmetic inside the probe.
//
// The Flutter host is stood in for by an in-process runner on purpose: the real
// one spawns `flutter test`, which cannot be nested inside `flutter test` (the
// end-to-end spawn is exercised by running the launcher itself; see the header
// of tool/mindnet_probe.dart and the evidence in the task report).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/cognitive_model.dart';
import 'package:furnace/features/anki/application/review_advisory.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import '../../tool/mindnet_probe.dart';

/// Defines the launcher sets when it asks this file to compute a reading. Empty
/// in a normal `flutter test` run, which is what keeps the host test inert.
const String _probeUnitsPath = String.fromEnvironment('PROBE_IN');
const String _probeReadingsPath = String.fromEnvironment('PROBE_OUT');
const String _probeNowRaw = String.fromEnvironment('PROBE_NOW');

/// A model with fixed, assertable answers. It is *the* model as far as the probe
/// is concerned: nothing else may produce a reading.
class _FixedModel implements CognitiveModel {
  const _FixedModel();

  @override
  String get id => 'test-fixed';

  @override
  double retrievabilityOf(CardState row, {required double nowHours}) => 0.5;

  @override
  double expectedGain(
    CardState row, {
    required double nowHours,
    double closeness = 0.5,
  }) =>
      2.0;

  @override
  List<AdvisorCandidate> orderAdvisory(
    List<AdvisorCandidate> candidates, {
    required double nowHours,
    Set<String> targetKpIds = const {},
  }) =>
      // Deterministic, and deliberately *not* the shipped rule: a stand-in must
      // not be able to pass for the real ordering.
      [...candidates]..sort((a, b) => a.row.id.compareTo(b.row.id));

  @override
  ({double r0, double sigma, double r}) modelReadingOf(
    CardState row, {
    required double nowHours,
  }) =>
      (r0: 0.7, sigma: 0.9, r: 0.42);

  @override
  ({double r0, double sigma}) modelStateAfterReview(
    CardState row, {
    required int rating,
    required double nowHours,
    bool reread = false,
    double closeness = 0.5,
  }) =>
      (r0: 0.7, sigma: 0.9);
}

/// A real database file: two knowledge points and three cards, one of each band
/// this probe can produce without a forced row (boosted / model / unseen).
void _seedDatabase(
  String path, {
  bool withModelColumns = true,
  bool withBoost = true,
  bool withTags = true,
}) {
  final db = sql.sqlite3.open(path);
  try {
    db.execute('''
CREATE TABLE knowledge_points (
  id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, content TEXT NOT NULL,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE card_states (
  id TEXT NOT NULL PRIMARY KEY, card_template_id TEXT, due_at INTEGER,
  interval_days REAL NOT NULL DEFAULT 0, ease REAL NOT NULL DEFAULT 2.5,
  repetitions INTEGER NOT NULL DEFAULT 0, lapses INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL DEFAULT 'new', last_reviewed_at INTEGER,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  knowledge_point_id TEXT, unit_key TEXT, stability REAL, difficulty REAL,
  forced INTEGER NOT NULL DEFAULT 0, forced_streak INTEGER NOT NULL DEFAULT 0
  ${withModelColumns ? ', encoding_strength REAL, savings REAL' : ''});
CREATE TABLE object_tags (
  id TEXT NOT NULL PRIMARY KEY, tag_id TEXT NOT NULL, object_type TEXT NOT NULL,
  object_id TEXT NOT NULL, created_at INTEGER NOT NULL);
CREATE TABLE boost_entries (
  id TEXT NOT NULL PRIMARY KEY, knowledge_point_id TEXT NOT NULL,
  factor REAL NOT NULL, remaining_cycles INTEGER NOT NULL DEFAULT 3,
  created_at INTEGER NOT NULL);
''');
    db.execute(
      "INSERT INTO knowledge_points VALUES ('kp-1', '光合作用', 'body', 1, 1), "
      "('kp-2', '呼吸作用', 'body', 1, 1)",
    );
    final columns = 'id, due_at, interval_days, ease, repetitions, lapses, '
        'state, last_reviewed_at, created_at, updated_at, knowledge_point_id, '
        'unit_key, stability, difficulty, forced, forced_streak'
        '${withModelColumns ? ', encoding_strength, savings' : ''}';
    final placeholders =
        List.filled(withModelColumns ? 18 : 16, '?').join(', ');
    void insertCard(List<Object?> values) {
      db.execute(
        'INSERT INTO card_states ($columns) VALUES ($placeholders)',
        values,
      );
    }

    insertCard([
      'cs-boost', 1700000000000, 3.5, 2.5, 4, 1, 'review', 1699000000000, 1, 2,
      'kp-1', 'cloze:0', 12.5, 6.0, 0, 0,
      if (withModelColumns) ...[0.9, 0.85],
    ]);
    insertCard([
      'cs-model', 1700000000000, 2.0, 2.5, 2, 0, 'review', 1699500000000, 1, 2,
      'kp-2', 'cloze:1', 5.0, 5.0, 0, 0,
      if (withModelColumns) ...[0.8, 0.8],
    ]);
    insertCard([
      'cs-new', null, 0, 2.5, 0, 0, 'new', null, 1, 2, 'kp-2', 'essay', null,
      null, 0, 0,
      if (withModelColumns) ...[null, null],
    ]);
    if (withTags) {
      db.execute(
        "INSERT INTO object_tags VALUES ('ot-1', 't-1', 'knowledge_point', "
        "'kp-1', 1), ('ot-2', 't-2', 'knowledge_point', 'kp-1', 1)",
      );
    }
    if (withBoost) {
      db.execute("INSERT INTO boost_entries VALUES ('b-1', 'kp-1', 1.8, 3, 1)");
    }
  } finally {
    db.dispose();
  }
}

/// Stands in for the real host (`test/tool/mindnet_probe_report_test.dart`): the
/// reading really does come from the injected model, through the same
/// `readingsFromUnitsJson` the host calls.
ProbeHostRunner _hostWith(CognitiveModel model) {
  return (request) async {
    final units = (jsonDecode(File(request.unitsPath).readAsStringSync()) as Map)
        .cast<String, Object?>();
    final readings = readingsFromUnitsJson(units, now: request.now, model: model);
    File(request.readingsPath).writeAsStringSync(jsonEncode(readings.toJson()));
    return const ProbeHostResult(exitCode: 0, stdout: '', stderr: '');
  };
}

void main() {
  // The host half of the probe: `dart run tool/mindnet_probe.dart` (and §9.9's
  // host entry, which drives the same function in-process) launches this file
  // with `--plain-name` + `--dart-define`, because a Flutter runtime is the only
  // place the model seam compiles. It is skipped in a normal suite run.
  test(
    probeHostTestName,
    () async {
      final units =
          (jsonDecode(File(_probeUnitsPath).readAsStringSync()) as Map)
              .cast<String, Object?>();
      final readings = readingsFromUnitsJson(
        units,
        now: DateTime.parse(_probeNowRaw).toUtc(),
      );
      File(_probeReadingsPath).writeAsStringSync(jsonEncode(readings.toJson()));
      // Shape checks, so a host that silently produced nothing fails here rather
      // than in the launcher's parser.
      expect(readings.cards, isNotEmpty);
      expect(
        readings.bandByCardStateId.keys.toSet(),
        readings.cards.map((card) => card.cardStateId).toSet(),
        reason: 'every band must be keyed by card state id',
      );
    },
    skip: _probeUnitsPath.isEmpty || _probeReadingsPath.isEmpty
        ? 'driven by tool/mindnet_probe.dart'
        : false,
  );

  late Directory tempDir;
  late String dbPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mindnet_probe_test_');
    dbPath = '${tempDir.path}${Platform.pathSeparator}furnace.db';
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('sha256', () {
    test('matches the published NIST vectors', () {
      expect(
        sha256Hex(const <int>[]),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        sha256Hex(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        sha256Hex(utf8.encode(
          'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
        )),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
    });

    test('a file and the same bytes in memory hash identically', () {
      final bytes = List<int>.generate(200000, (i) => (i * 7) & 0xff);
      final file = File('${tempDir.path}${Platform.pathSeparator}blob.bin')
        ..writeAsBytesSync(bytes);
      expect(file.lengthSync(), 200000);
      expect(sha256HexOfFile(file), sha256Hex(bytes));
    });

    test('streaming across chunk boundaries is not a different hash', () {
      final oneShot = sha256Hex(List<int>.filled(70000, 97));
      const chunkSize = 4096;
      final bytes = List<int>.filled(70000, 97);
      final pieces = <List<int>>[];
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        pieces.add(
          bytes.sublist(offset, (offset + chunkSize).clamp(0, bytes.length)),
        );
      }
      expect(pieces.expand((piece) => piece).length, bytes.length);
      expect(sha256Hex(pieces.expand((piece) => piece).toList()), oneShot);
    });
  });

  group('options', () {
    test('defaults to the app support path under APPDATA', () {
      final options = ProbeOptions.parse(
        const [],
        environment: const {'APPDATA': r'C:\Users\tester\AppData\Roaming'},
      );
      expect(
        options.dbPath,
        endsWith(
          'FirsryFan${Platform.pathSeparator}Furnace'
          '${Platform.pathSeparator}furnace.db',
        ),
      );
      expect(options.json, isFalse);
      expect(options.limit, isNull);
    });

    test('knows the legacy file names this install may still use', () {
      final candidates = ProbeOptions.databaseCandidates(
        '${tempDir.path}${Platform.pathSeparator}furnace.db',
      );
      expect(candidates.first, endsWith('furnace.db'));
      expect(candidates[1], endsWith('threadflow.db'));
      expect(candidates[2], endsWith('knowflow.db'));
    });

    test('parses --db, --json, --limit and --now', () {
      final options = ProbeOptions.parse(
        const [
          '--db',
          r'D:\somewhere\furnace.db',
          '--json',
          '--limit',
          '5',
          '--now',
          '2026-10-01T12:00:00Z',
        ],
        environment: const {},
      );
      expect(options.dbPath, r'D:\somewhere\furnace.db');
      expect(options.json, isTrue);
      expect(options.limit, 5);
      expect(options.now, DateTime.utc(2026, 10, 1, 12));
    });

    test('rejects unknown arguments and malformed values', () {
      expect(() => ProbeOptions.parse(const ['--nope']), throwsArgumentError);
      expect(() => ProbeOptions.parse(const ['--db']), throwsArgumentError);
      expect(() => ProbeOptions.parse(const ['--limit', 'x']),
          throwsArgumentError);
      expect(() => ProbeOptions.parse(const ['--limit', '-1']),
          throwsArgumentError);
      expect(() => ProbeOptions.parse(const ['--now', 'yesterday']),
          throwsArgumentError);
    });

    test('without APPDATA it asks for --db instead of guessing', () {
      expect(
        () => ProbeOptions.parse(const [], environment: const {}),
        throwsStateError,
      );
    });

    test('--help needs no APPDATA and carries no database path', () {
      final options =
          ProbeOptions.parse(const ['--help'], environment: const {});
      expect(options.help, isTrue);
      expect(options.dbPath, isEmpty);
      expect(probeUsage, contains('--db'));
    });
  });

  group('resolveFlutterExecutable', () {
    test('prefers FLUTTER_ROOT when it holds a launcher', () {
      final bin = Directory('${tempDir.path}${Platform.pathSeparator}bin')
        ..createSync();
      final launcher = File(
        '${bin.path}${Platform.pathSeparator}'
        '${Platform.isWindows ? 'flutter.bat' : 'flutter'}',
      )..writeAsStringSync('');
      expect(
        resolveFlutterExecutable(environment: {'FLUTTER_ROOT': tempDir.path}),
        launcher.path,
      );
    });
  });

  group('appDirectoryOf', () {
    test('does not trust a script path that is not the tool file', () {
      // Inside `flutter test`, `Platform.script` is a compiled artifact, not
      // `tool/mindnet_probe.dart`. The walk-up is what keeps the host entry's
      // own invocation working, so it is pinned here.
      final resolved = appDirectoryOf('/nowhere/else/artifact.dill');
      expect(
        File('$resolved${Platform.pathSeparator}pubspec.yaml').existsSync(),
        isTrue,
      );
      expect(
        File('$resolved${Platform.pathSeparator}tool'
            '${Platform.pathSeparator}mindnet_probe.dart').existsSync(),
        isTrue,
      );
    });
  });

  group('collectProbe', () {
    test('reads a read-only copy and leaves the original byte-for-byte alone',
        () async {
      _seedDatabase(dbPath);
      final before = File(dbPath).statSync();
      final shaBefore = sha256HexOfFile(File(dbPath));
      String? unitsPath;

      final report = await collectProbe(
        options: ProbeOptions(dbPath: dbPath),
        now: DateTime.utc(2026, 10, 2, 3),
        host: (request) async {
          unitsPath = request.unitsPath;
          return _hostWith(const _FixedModel())(request);
        },
      );

      // The host was handed a *copy* inside a temp directory.
      expect(unitsPath, isNotNull);
      expect(unitsPath, isNot(dbPath));
      expect(unitsPath, contains('mindnet_probe_'));
      expect(report.integrity.path, dbPath);
      expect(report.integrity.unchanged, isTrue);
      expect(report.integrity.sha256Before, shaBefore);
      expect(report.integrity.sha256After, shaBefore);
      expect(report.knowledgePoints, 2);

      // The original: same bytes, same SHA-256, same mtime.
      final after = File(dbPath).statSync();
      expect(after.size, before.size);
      expect(after.modified, before.modified);
      expect(sha256HexOfFile(File(dbPath)), shaBefore);

      // ...and the temp copy is gone again.
      expect(Directory(report.copy.directory).existsSync(), isFalse);
    });

    test('exports the row facts the model seam cannot see by itself', () async {
      _seedDatabase(dbPath);
      Map<String, Object?>? units;
      final runner = _hostWith(const _FixedModel());
      final report = await collectProbe(
        options: ProbeOptions(dbPath: dbPath),
        now: DateTime.utc(2026, 10, 2, 3),
        host: (request) async {
          units = (jsonDecode(File(request.unitsPath).readAsStringSync()) as Map)
              .cast<String, Object?>();
          return runner(request);
        },
      );

      final exported = (units!['units'] as List).cast<Map<String, Object?>>();
      expect(exported, hasLength(3));
      final boosted = exported.firstWhere(
        (unit) => (unit['row'] as Map)['id'] == 'cs-boost',
      );
      expect(boosted['knowledgePointTitle'], '光合作用');
      expect(boosted['tagCount'], 2);
      expect(boosted['isNew'], isFalse);
      expect((boosted['row'] as Map)['encodingStrength'], 0.9);
      expect((boosted['row'] as Map)['savings'], 0.85);
      expect((boosted['row'] as Map)['stability'], 12.5);
      expect(units!['boostFactorByKnowledgePoint'], {'kp-1': 1.8});

      final fresh = exported.firstWhere(
        (unit) => (unit['row'] as Map)['id'] == 'cs-new',
      );
      expect(fresh['isNew'], isTrue, reason: "repetitions == 0 is D4's flag");
      expect((fresh['row'] as Map)['lastReviewedAt'], isNull,
          reason: 'the probe must not invent a review moment for a new card');
      expect(report.modelId, 'test-fixed');
    });

    test('reads a pre-v6 file (no model columns) instead of failing', () async {
      _seedDatabase(dbPath, withModelColumns: false, withTags: false);
      final report = await collectProbe(
        options: ProbeOptions(dbPath: dbPath),
        now: DateTime.utc(2026, 10, 2, 3),
        host: _hostWith(const _FixedModel()),
      );
      expect(report.cards, hasLength(3));
      final rows = (report.units['units'] as List)
          .cast<Map<String, Object?>>()
          .map((unit) => (unit['row'] as Map).cast<String, Object?>())
          .toList();
      // A missing column reads as null; turning NULL into 1.0 / 0.8 is the
      // model's job (`CognitiveModel.modelReadingOf`), never the probe's.
      for (final row in rows) {
        expect(row['encodingStrength'], isNull);
        expect(row['savings'], isNull);
      }
      for (final card in report.cards) {
        expect(card['tagCount'], 0);
      }
    });

    test('missing database is reported, not silently treated as empty',
        () async {
      await expectLater(
        collectProbe(
          options: ProbeOptions(
            dbPath: '${tempDir.path}${Platform.pathSeparator}nope.db',
          ),
        ),
        throwsStateError,
      );
    });

    test('a failing host is reported with its output, and the copy is cleaned',
        () async {
      _seedDatabase(dbPath);
      await expectLater(
        collectProbe(
          options: ProbeOptions(dbPath: dbPath),
          host: (request) async => const ProbeHostResult(
            exitCode: 1,
            stdout: '',
            stderr: 'no Flutter runtime here',
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains('host failed'), contains('no Flutter runtime here')),
          ),
        ),
      );
      expect(Directory(tempDir.path).listSync(), hasLength(1));
    });
  });

  group('renderProbe', () {
    Future<ProbeReport> collected() => collectProbe(
          options: ProbeOptions(dbPath: dbPath),
          now: DateTime.utc(2026, 10, 2, 3),
          host: _hostWith(const _FixedModel()),
        );

    test('human output states that the original was not modified', () async {
      _seedDatabase(dbPath);
      final text = renderProbe(await collected(), json: false);
      expect(text, contains('原库未被修改: 是'));
      expect(text, contains('未标定'));
      expect(text, contains('SHA256 前: '));
      // The injected model's reading, not a re-derived one.
      expect(text, contains('0.420'));
      expect(text, contains('test-fixed'));
    });

    test('json output carries both advisor maps keyed by card state id',
        () async {
      _seedDatabase(dbPath);
      final decoded = jsonDecode(renderProbe(await collected(), json: true))
          as Map<String, Object?>;
      expect(decoded['schema'], 'mindnet.probe/1');
      expect(decoded['readings_schema'], 'mindnet.readings/1');
      expect((decoded['source'] as Map)['unchanged'], isTrue);
      expect(decoded['modelId'], 'test-fixed');
      expect(
        decoded['bandByCardStateId'],
        {
          'cs-boost': ReviewBand.boosted.name,
          'cs-model': ReviewBand.model.name,
          'cs-new': ReviewBand.unseen.name,
        },
      );
      expect(decoded['scoreByCardStateId'], {'cs-model': 2.0});
      expect(
        decoded['zoneByKnowledgePoint'],
        {
          'kp-1': ReviewZone.unavailable.name,
          'kp-2': ReviewZone.unavailable.name,
        },
      );
      final cards = (decoded['cards'] as List).cast<Map<String, Object?>>();
      expect(cards, hasLength(3));
      for (final card in cards) {
        expect(card['cardStateId'], isA<String>());
        expect(card['unitKey'], isNotNull);
      }
      expect((decoded['summary'] as Map)['cards'], 3);
      expect((decoded['summary'] as Map)['newCards'], 1);
      expect((decoded['summary'] as Map)['meanR'], 0.42);
    });

    test('--limit caps the printed cards but not the summary', () async {
      _seedDatabase(dbPath);
      final report = await collected();
      final limited = jsonDecode(renderProbe(report, json: true, limit: 1))
          as Map<String, Object?>;
      expect((limited['cards'] as List), hasLength(1));
      expect(limited['cards_omitted'], 2);
      expect((limited['summary'] as Map)['cards'], 3);
      expect(renderProbe(report, json: false, limit: 1), contains('未显示'));
    });
  });

  group('readings from the host handshake', () {
    test('bands, zones and scores are the advisor\'s, keyed by card state id',
        () async {
      _seedDatabase(dbPath);
      final report = await collectProbe(
        options: ProbeOptions(dbPath: dbPath),
        now: DateTime.utc(2026, 10, 2, 3),
        host: _hostWith(const _FixedModel()),
      );

      final seen = report.cards.firstWhere(
        (card) => card['cardStateId'] == 'cs-model',
      );
      expect(seen['r'], 0.42);
      expect(seen['gain'], 2.0);
      expect(seen['r0'], 0.7);
      expect(seen['sigma'], 0.9);
      expect(seen['band'], ReviewBand.model.name);
      expect(seen['zone'], ReviewZone.unavailable.name);
      expect(seen['scoreUsedForOrdering'], isTrue);
      expect(seen['rank'], 1);

      final boosted = report.cards.firstWhere(
        (card) => card['cardStateId'] == 'cs-boost',
      );
      expect(boosted['band'], ReviewBand.boosted.name);
      expect(boosted['scoreUsedForOrdering'], isFalse);
      expect(boosted['boostFactor'], 1.8);

      final fresh = report.cards.firstWhere(
        (card) => card['cardStateId'] == 'cs-new',
      );
      expect(fresh['band'], ReviewBand.unseen.name);
      expect(fresh['isNew'], isTrue);
      expect(fresh['scoreUsedForOrdering'], isFalse);
    });
  });
}
