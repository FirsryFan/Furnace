// Read-only probe over the *real* Furnace database: prints what the cognitive
// model currently thinks about every card.
//
// Usage (from `app/`):
//   dart run tool/mindnet_probe.dart [--db <path>] [--json] [--limit N] [--now <iso8601>]
//
// Default `--db`: `%APPDATA%\FirsryFan\Furnace\furnace.db` (plus the two legacy
// file names this install may still be using - see `_databaseCandidates`).
//
// ## The safety rule (why this file copies instead of opening)
//
// **The real database is never opened.** The file - together with its `-wal` /
// `-shm` companions - is copied into a temp directory first, and only the copy
// is opened, and only read-only (`OpenMode.readOnly`). The original is watched
// with SHA-256 + mtime + size before and after, and the report says so. The copy
// is deleted before the process exits.
//
// ## Why a Flutter host is involved (and what this file does *not* do)
//
// This file is plain Dart on purpose, so `dart run` works. It cannot read the
// model itself: `CognitiveModel` lives behind `database.dart` -> `path_provider`
// -> `package:flutter` -> `dart:ui`, and the plain Dart VM has no `dart:ui`
// (measured; §9.9 of docs/MINDNET_CONTRACT.md records the same finding). So the
// division of labour is:
//
//   * **this file** - arguments, the copy, the integrity witnesses, the
//     read-only export of `card_states` into the units JSON both sides share,
//     launching the host, and rendering (human / `--json`);
//   * **the host** - `test/tool/mindnet_probe_test.dart` (the `mindnet probe
//     readings host` test) - the only place that runs the model seam, which it
//     reaches through `CognitiveModel` and `ReviewAdvisory` and nothing else.
//     `test/tool/mindnet_probe_report_test.dart` is the same host under its
//     own documented invocation (`--dart-define=PROBE_DB=...`), kept for §9.9.
//
// No arithmetic of the model lives here, and none is re-derived: `R`, the gain,
// the bands, the zones and the counters all arrive from the host as JSON. The
// one number this file computes for display is FSRS's own "what would a '记得'
// answer schedule" - and it does not even compute that (the host does); see
// `CognitiveCardReading.suggestedIntervalDays`.
//
// ## Reading the output
//
//   R    = R0 · Psi(t/S): how well the card is known *right now* (0..1)
//   gain = the multiplicative stability gain of reviewing now (>= 1); it is what
//          orders the model band, so "low R + high gain" = "about to be
//          forgotten, and reviewing now is worth the most"
//   band = why the card sits where it does: forced -> boosted -> model -> unseen
//   zone = the diagnosis vocabulary; `unavailable` means no diagnosis was
//          produced, which is *not* `healthy`
//
// `ls` / `W_DAR` / `beta_goal` / `T_ign` and friends are **uncalibrated**, and
// the model is an advisor: it never changes `dueAt` (D1).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Printed for `--help` and on a usage error.
const String probeUsage = '''
Read-only cognitive-model probe over a *copy* of the Furnace database.

  dart run tool/mindnet_probe.dart [options]

Options:
  --db <path>     database to inspect (default: %APPDATA%\\FirsryFan\\Furnace\\furnace.db)
  --json          machine-readable output instead of the table
  --limit <n>     print at most n cards (the summary still counts all of them)
  --now <iso8601> freeze the reading clock (default: now)
  --help          this text
''';

/// Parsed command line.
class ProbeOptions {
  const ProbeOptions({
    required this.dbPath,
    this.json = false,
    this.limit,
    this.now,
    this.help = false,
  });

  final String dbPath;
  final bool json;

  /// Cap on printed cards (the summary always counts everything).
  final int? limit;

  /// Frozen reading moment, for a reproducible report.
  final DateTime? now;

  final bool help;

  /// The app support directory's database, `%APPDATA%\FirsryFan\Furnace\...`.
  ///
  /// The directory name comes from the exe metadata (`CompanyName`), which is
  /// why it is `FirsryFan` and not `Furnace`; `database.dart` records the
  /// measurement. Legacy file names are kept because an install that predates a
  /// rename is still served from one (`database.dart` `_adoptLegacyDatabase`).
  static String defaultDbPath({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final appData = env['APPDATA'];
    if (appData == null || appData.isEmpty) {
      throw StateError(
        'APPDATA is not set: pass --db <path> explicitly',
      );
    }
    return '$appData${Platform.pathSeparator}FirsryFan'
        '${Platform.pathSeparator}Furnace${Platform.pathSeparator}furnace.db';
  }

  /// The files this install could be using, newest name first.
  static List<String> databaseCandidates(String primaryPath) {
    final dir = p.dirname(primaryPath);
    return [
      for (final name in const ['furnace.db', 'threadflow.db', 'knowflow.db'])
        p.join(dir, name),
    ];
  }

  static ProbeOptions parse(
    List<String> args, {
    Map<String, String>? environment,
  }) {
    String? dbPath;
    var json = false;
    var help = false;
    int? limit;
    DateTime? now;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      switch (arg) {
        case '--db':
          if (i + 1 >= args.length) {
            throw ArgumentError('--db needs a path');
          }
          dbPath = args[++i];
        case '--json':
          json = true;
        case '--help':
          help = true;
        case '--limit':
          if (i + 1 >= args.length) {
            throw ArgumentError('--limit needs a number');
          }
          final raw = args[++i];
          final parsed = int.tryParse(raw);
          if (parsed == null || parsed < 0) {
            throw ArgumentError('--limit expects a non-negative integer, got $raw');
          }
          limit = parsed;
        case '--now':
          if (i + 1 >= args.length) {
            throw ArgumentError('--now needs an ISO-8601 timestamp');
          }
          final raw = args[++i];
          final parsed = DateTime.tryParse(raw);
          if (parsed == null) {
            throw ArgumentError('--now expects an ISO-8601 timestamp, got $raw');
          }
          now = parsed;
        default:
          throw ArgumentError('unknown argument: $arg');
      }
    }
    final resolved = dbPath ??
        (help ? '' : _firstExisting(ProbeOptions.databaseCandidates(
          defaultDbPath(environment: environment),
        )));
    return ProbeOptions(
      dbPath: resolved,
      json: json,
      limit: limit,
      now: now,
      help: help,
    );
  }

  /// The first candidate that exists, or the primary name when none does (so
  /// the error message names what the app would have created).
  static String _firstExisting(List<String> candidates) {
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return candidates.first;
  }
}

/// SHA-256, so the report can say "the original is byte-for-byte unchanged"
/// instead of "it looks untouched".
///
/// Self-contained on purpose: `package:crypto` is only a transitive dependency
/// here, and an integrity witness must not need a new pubspec entry. Correctness
/// is pinned against the NIST vectors in `test/tool/mindnet_probe_test.dart`.
String sha256Hex(List<int> bytes) {
  final hash = _Sha256()..add(bytes);
  return hash.digestHex();
}

String sha256HexOfFile(File file) {
  final hash = _Sha256();
  final sink = file.openSync();
  try {
    final buffer = List<int>.filled(1 << 16, 0);
    while (true) {
      final read = sink.readIntoSync(buffer);
      if (read == 0) {
        break;
      }
      hash.add(buffer.sublist(0, read));
    }
  } finally {
    sink.closeSync();
  }
  return hash.digestHex();
}

class _Sha256 {
  static const List<int> _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, //
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  final List<int> _h = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];
  final List<int> _pending = <int>[];
  int _length = 0;
  bool _closed = false;

  void add(List<int> bytes) {
    if (_closed) {
      throw StateError('sha256 sink already closed');
    }
    _length += bytes.length;
    _pending.addAll(bytes);
    var offset = 0;
    while (_pending.length - offset >= 64) {
      _compress(_pending, offset);
      offset += 64;
    }
    _pending.removeRange(0, offset);
  }

  String digestHex() {
    if (!_closed) {
      _closed = true;
      final bitLength = _length * 8;
      final pad = <int>[0x80];
      while ((_pending.length + pad.length) % 64 != 56) {
        pad.add(0);
      }
      for (var i = 7; i >= 0; i--) {
        pad.add((bitLength >> (8 * i)) & 0xff);
      }
      _pending.addAll(pad);
      for (var offset = 0; offset < _pending.length; offset += 64) {
        _compress(_pending, offset);
      }
      _pending.clear();
    }
    return _h.map((word) => word.toRadixString(16).padLeft(8, '0')).join();
  }

  void _compress(List<int> block, int offset) {
    final w = List<int>.filled(64, 0);
    for (var i = 0; i < 16; i++) {
      final base = offset + i * 4;
      w[i] = (block[base] << 24) |
          (block[base + 1] << 16) |
          (block[base + 2] << 8) |
          block[base + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var a = _h[0], b = _h[1], c = _h[2], d = _h[3];
    var e = _h[4], f = _h[5], g = _h[6], h = _h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ (~e & g);
      final temp1 = (h + s1 + ch + _k[i] + w[i]) & 0xffffffff;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + maj) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }
    _h[0] = (_h[0] + a) & 0xffffffff;
    _h[1] = (_h[1] + b) & 0xffffffff;
    _h[2] = (_h[2] + c) & 0xffffffff;
    _h[3] = (_h[3] + d) & 0xffffffff;
    _h[4] = (_h[4] + e) & 0xffffffff;
    _h[5] = (_h[5] + f) & 0xffffffff;
    _h[6] = (_h[6] + g) & 0xffffffff;
    _h[7] = (_h[7] + h) & 0xffffffff;
  }

  static int _rotr(int value, int shift) =>
      ((value >> shift) | (value << (32 - shift))) & 0xffffffff;
}

/// The original file's witnesses, taken before and after the run.
class ProbeIntegrity {
  const ProbeIntegrity({
    required this.path,
    required this.bytesBefore,
    required this.bytesAfter,
    required this.sha256Before,
    required this.sha256After,
    required this.modifiedBefore,
    required this.modifiedAfter,
  });

  final String path;
  final int bytesBefore;
  final int bytesAfter;
  final String sha256Before;
  final String sha256After;
  final DateTime modifiedBefore;
  final DateTime modifiedAfter;

  /// The whole promise of the probe: the file it read from was never written to.
  bool get unchanged =>
      sha256Before == sha256After &&
      bytesBefore == bytesAfter &&
      modifiedBefore == modifiedAfter;

  Map<String, Object?> toJson() => {
        'path': path,
        'bytes': bytesAfter,
        'sha256_before': sha256Before,
        'sha256_after': sha256After,
        'modified_before': modifiedBefore.toIso8601String(),
        'modified_after': modifiedAfter.toIso8601String(),
        'unchanged': unchanged,
      };
}

/// The temp copy the probe actually reads.
class ProbeCopy {
  const ProbeCopy({
    required this.directory,
    required this.path,
    required this.copiedFiles,
  });

  final String directory;
  final String path;
  final List<String> copiedFiles;

  /// Removes the copy. The caller runs it in a `finally`, so a failure anywhere
  /// in between cannot leave a copy of the user's database behind.
  void dispose() {
    final dir = Directory(directory);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }
}

/// What the Flutter host is asked to do, and what came back.
class ProbeHostRequest {
  const ProbeHostRequest({
    required this.appDirectory,
    required this.unitsPath,
    required this.readingsPath,
    required this.now,
  });

  final String appDirectory;
  final String unitsPath;
  final String readingsPath;
  final DateTime now;
}

class ProbeHostResult {
  const ProbeHostResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  String get tail {
    final text = '$stdout\n$stderr';
    return text.length <= 2000 ? text : text.substring(text.length - 2000);
  }
}

typedef ProbeHostRunner = Future<ProbeHostResult> Function(
  ProbeHostRequest request,
);

/// Runs the host under `flutter test`, which is the only runtime the model seam
/// compiles in.
///
/// This is deliberately a *subprocess* and not an import: `package:flutter` is
/// not loadable here, and re-deriving the model in pure Dart is exactly the
/// second source of truth the integration must avoid.
Future<ProbeHostResult> runFlutterHost(ProbeHostRequest request) async {
  final flutter = resolveFlutterExecutable();
  final args = <String>[
    'test',
    probeHostFile,
    '--plain-name',
    probeHostTestName,
    '--dart-define=PROBE_IN=${request.unitsPath}',
    '--dart-define=PROBE_OUT=${request.readingsPath}',
    '--dart-define=PROBE_NOW=${request.now.toUtc().toIso8601String()}',
  ];
  try {
    final result = await Process.run(
      flutter,
      args,
      workingDirectory: request.appDirectory,
      // `flutter` is a `.bat` on Windows: CreateProcess cannot start it
      // directly, so the shell resolves it. The POC for this is the probe's own
      // end-to-end run (docs/MINDNET_CONTRACT.md §9.9).
      runInShell: Platform.isWindows,
    );
    return ProbeHostResult(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
  } on ProcessException catch (error) {
    return ProbeHostResult(
      exitCode: -1,
      stdout: '',
      stderr: 'could not run the Flutter host ($flutter): $error',
    );
  }
}

/// The test name the host is selected by (`--plain-name`).
const String probeHostTestName = 'mindnet probe readings host';

/// The host file, relative to the app directory. It lives next to this probe's
/// own unit tests, and it is the file §9.9's host entry drives in-process.
const String probeHostFile = 'test/tool/mindnet_probe_test.dart';

/// The Flutter launcher, preferring the SDK the running Dart came from.
String resolveFlutterExecutable({
  Map<String, String>? environment,
  bool Function(String path)? exists,
}) {
  final env = environment ?? Platform.environment;
  final binary = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final isFile = exists ?? (path) => File(path).existsSync();
  final candidates = <String>[
    if (env['FLUTTER_ROOT'] case final root? when root.isNotEmpty)
      p.join(root, 'bin', binary),
    // <flutter>/bin/cache/dart-sdk/bin/dart.exe -> <flutter>/bin/<binary>
    p.join(
      p.dirname(
        p.dirname(p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable)))),
      ),
      'bin',
      binary,
    ),
  ];
  for (final candidate in candidates) {
    if (isFile(candidate)) {
      return candidate;
    }
  }
  return binary;
}

/// The app directory the host must run in (the one with `pubspec.yaml`).
///
/// `Platform.script` is the tool file under `dart run`, but a compiled
/// artifact under `flutter test` - and the host entry (§9.9) calls the probe
/// from inside a test process. So the guess is *verified* rather than trusted:
/// the script's grandparent must hold `pubspec.yaml`, and otherwise the
/// directory tree is walked up from [from] looking for this very file.
String appDirectoryOf(String scriptPath, {Directory? from}) {
  final fromScript = p.dirname(p.dirname(scriptPath));
  if (File(p.join(fromScript, 'pubspec.yaml')).existsSync()) {
    return fromScript;
  }
  var dir = (from ?? Directory.current).absolute.path;
  for (var i = 0; i < 8; i++) {
    if (File(p.join(dir, 'tool', 'mindnet_probe.dart')).existsSync()) {
      return dir;
    }
    final parent = p.dirname(dir);
    if (parent == dir) {
      break;
    }
    dir = parent;
  }
  return fromScript;
}

/// Everything the probe found.
class ProbeReport {
  const ProbeReport({
    required this.options,
    required this.integrity,
    required this.copy,
    required this.units,
    required this.unitsPath,
    required this.readings,
    required this.knowledgePoints,
    required this.host,
    required this.runAt,
  });

  final ProbeOptions options;
  final ProbeIntegrity integrity;
  final ProbeCopy copy;

  /// The units JSON handed to the host (kept for the JSON output; the file is
  /// gone by then).
  final Map<String, Object?> units;
  final String unitsPath;

  /// The host's readings JSON, verbatim: `cards` plus `bandByCardStateId` /
  /// `scoreByCardStateId` / `zoneByKnowledgePoint`, all keyed by card state id.
  final Map<String, Object?> readings;

  final int knowledgePoints;
  final ProbeHostResult host;
  final DateTime runAt;

  /// The original's witnesses, under the names §9.9's host entry
  /// (`test/tool/mindnet_probe_report_test.dart`) already reads.
  bool get originalUntouched => integrity.unchanged;
  String get sourcePath => integrity.path;
  int get originalSizeBefore => integrity.bytesBefore;
  int get originalSizeAfter => integrity.bytesAfter;
  DateTime get originalModifiedBefore => integrity.modifiedBefore;
  DateTime get originalModifiedAfter => integrity.modifiedAfter;

  List<Map<String, Object?>> get cards {
    final cards = readings['cards'] as List? ?? const [];
    return [for (final card in cards) (card as Map).cast<String, Object?>()];
  }

  String get modelId => '${readings['modelId'] ?? 'unknown'}';

  Map<String, Object?> get summary =>
      (readings['summary'] as Map?)?.cast<String, Object?>() ?? const {};

  Map<String, Object?> toJson() => {
        // The model's own output first, flattened: `cards` and both advisor maps
        // are keyed by card state id (`bandByCardStateId` /
        // `scoreByCardStateId`). The envelope is written *after* the spread so
        // its keys cannot be shadowed by the reading's own (`schema`).
        for (final entry in readings.entries)
          if (entry.key != 'schema') entry.key: entry.value,
        'readings_schema': readings['schema'],
        'schema': 'mindnet.probe/1',
        'generated_at': runAt.toUtc().toIso8601String(),
        'source': integrity.toJson(),
        'copy': {
          'directory': copy.directory,
          'files': copy.copiedFiles,
        },
        'knowledge_points': knowledgePoints,
        'units': (units['units'] as List?)?.length ?? 0,
        'host': {
          'exit_code': host.exitCode,
          'test': probeHostTestName,
        },
      };
}

/// Copies the database (and its WAL companions) into a temp directory and reads
/// the copy *read-only*. The original is only ever stat-ed and hashed.
Future<ProbeReport> collectProbe({
  required ProbeOptions options,
  DateTime? now,
  ProbeHostRunner? host,
}) async {
  final source = File(options.dbPath);
  if (!source.existsSync()) {
    throw StateError('database not found: ${options.dbPath}');
  }
  final moment = (now ?? options.now ?? DateTime.now()).toUtc();
  final runAt = DateTime.now().toUtc();
  final statBefore = source.statSync();
  final shaBefore = sha256HexOfFile(source);

  final tempDir = Directory.systemTemp.createTempSync('mindnet_probe_');
  final copy = ProbeCopy(
    directory: tempDir.path,
    path: p.join(tempDir.path, p.basename(options.dbPath)),
    copiedFiles: <String>[],
  );
  try {
    final copied = <String>[];
    source.copySync(copy.path);
    copied.add(p.basename(copy.path));
    // A `-wal` holds committed pages that are not in the main file yet, so
    // copying it keeps the copy faithful to what the app is actually reading.
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('${options.dbPath}$suffix');
      if (sidecar.existsSync()) {
        sidecar.copySync('${copy.path}$suffix');
        copied.add('${p.basename(copy.path)}$suffix');
      }
    }
    final withFiles = ProbeCopy(
      directory: copy.directory,
      path: copy.path,
      copiedFiles: copied,
    );

    final units = readUnitsFromCopy(copy.path);
    final unitsPath = p.join(tempDir.path, 'units.json');
    File(unitsPath).writeAsStringSync(jsonEncode(units));

    final readingsPath = p.join(tempDir.path, 'readings.json');
    final hostResult = await (host ?? runFlutterHost)(ProbeHostRequest(
      appDirectory: appDirectoryOf(Platform.script.toFilePath()),
      unitsPath: unitsPath,
      readingsPath: readingsPath,
      now: moment,
    ));
    if (hostResult.exitCode != 0) {
      throw StateError(
        'the Flutter host failed (exit ${hostResult.exitCode}).\n'
        '${hostResult.tail}',
      );
    }
    final readingsFile = File(readingsPath);
    if (!readingsFile.existsSync()) {
      throw StateError(
        'the Flutter host produced no readings.\n${hostResult.tail}',
      );
    }
    final readings =
        (jsonDecode(readingsFile.readAsStringSync()) as Map).cast<String, Object?>();

    final statAfter = source.statSync();
    final shaAfter = sha256HexOfFile(source);
    final knowledgePointIds = <String>{
      for (final unit
          in (units['units'] as List? ?? const []) as Iterable<Object?>)
        if (((unit as Map)['row'] as Map?)?['knowledgePointId'] case final id?)
          '$id',
    };

    return ProbeReport(
      options: options,
      integrity: ProbeIntegrity(
        path: options.dbPath,
        bytesBefore: statBefore.size,
        bytesAfter: statAfter.size,
        sha256Before: shaBefore,
        sha256After: shaAfter,
        modifiedBefore: statBefore.modified,
        modifiedAfter: statAfter.modified,
      ),
      copy: withFiles,
      units: units,
      unitsPath: unitsPath,
      readings: readings,
      knowledgePoints: knowledgePointIds.length,
      host: hostResult,
      runAt: runAt,
    );
  } finally {
    copy.dispose();
  }
}

// --- the read-only export of `card_states` ---------------------------------

/// Reads the copy (read-only!) into the units JSON the host consumes.
///
/// The field names inside `row` are `CardState`'s, so the host can rebuild the
/// row without a second dictionary. Columns a pre-v6 file lacks are exported as
/// null instead of failing: `encoding_strength` / `savings` only exist from v6
/// (the app self-heals them on open, and the probe must not be the one thing
/// that cannot read an older file).
Map<String, Object?> readUnitsFromCopy(String copyPath) {
  final db = sqlite3.open(copyPath, mode: OpenMode.readOnly);
  try {
    final units = <Map<String, Object?>>[];
    if (_tableExists(db, 'card_states')) {
      final columns = _columnsOf(db, 'card_states');
      final titles = <String, String>{};
      if (_tableExists(db, 'knowledge_points')) {
        for (final row in db.select('SELECT id, title FROM knowledge_points')) {
          titles['${row['id']}'] = '${row['title']}';
        }
      }
      final tagCounts = <String, int>{};
      if (_tableExists(db, 'object_tags')) {
        final rows = db.select(
          'SELECT object_id, COUNT(*) AS n FROM object_tags '
          "WHERE object_type = 'knowledge_point' GROUP BY object_id",
        );
        for (final row in rows) {
          tagCounts['${row['object_id']}'] = (row['n'] as int?) ?? 0;
        }
      }
      final rows = db.select('''
SELECT id,
       ${_column(columns, 'card_template_id')},
       ${_column(columns, 'due_at')},
       ${_column(columns, 'interval_days')},
       ${_column(columns, 'ease')},
       ${_column(columns, 'repetitions')},
       ${_column(columns, 'lapses')},
       ${_column(columns, 'state')},
       ${_column(columns, 'last_reviewed_at')},
       ${_column(columns, 'created_at')},
       ${_column(columns, 'updated_at')},
       ${_column(columns, 'knowledge_point_id')},
       ${_column(columns, 'unit_key')},
       ${_column(columns, 'stability')},
       ${_column(columns, 'difficulty')},
       ${_column(columns, 'encoding_strength')},
       ${_column(columns, 'savings')},
       ${_column(columns, 'forced')},
       ${_column(columns, 'forced_streak')}
FROM card_states
ORDER BY id
''');
      for (final row in rows) {
        final knowledgePointId = row['knowledge_point_id']?.toString();
        final repetitions = (row['repetitions'] as int?) ?? 0;
        units.add({
          'knowledgePointTitle':
              knowledgePointId == null ? '' : titles[knowledgePointId] ?? '',
          'tagCount':
              knowledgePointId == null ? 0 : tagCounts[knowledgePointId] ?? 0,
          // D4: "never shown before" is the review flow's flag, and the flow
          // derives it from `repetitions == 0` (`ReviewService._itemFor`).
          'isNew': repetitions == 0,
          'row': {
            'id': row['id'],
            'cardTemplateId': row['card_template_id'],
            'dueAt': row['due_at'],
            'intervalDays': row['interval_days'],
            'ease': row['ease'],
            'repetitions': repetitions,
            'lapses': row['lapses'],
            'state': row['state'],
            'lastReviewedAt': row['last_reviewed_at'],
            'createdAt': row['created_at'],
            'updatedAt': row['updated_at'],
            'knowledgePointId': knowledgePointId,
            'unitKey': row['unit_key'],
            'stability': row['stability'],
            'difficulty': row['difficulty'],
            'encodingStrength': row['encoding_strength'],
            'savings': row['savings'],
            'forced': row['forced'],
            'forcedStreak': row['forced_streak'],
          },
        });
      }
    }

    final boosts = <String, double>{};
    if (_tableExists(db, 'boost_entries')) {
      for (final row in db.select(
        'SELECT knowledge_point_id, factor FROM boost_entries',
      )) {
        final id = row['knowledge_point_id'];
        final factor = row['factor'];
        if (id != null && factor is num) {
          boosts['$id'] = factor.toDouble();
        }
      }
    }

    return {
      'schema': 'mindnet.units/1',
      'units': units,
      'boostFactorByKnowledgePoint': boosts,
    };
  } finally {
    db.dispose();
  }
}

/// `name` when the table has it, otherwise a typed NULL so older files still
/// read.
String _column(Set<String> columns, String name) {
  if (columns.contains(name)) {
    return name;
  }
  return 'NULL AS $name';
}

bool _tableExists(Database db, String name) {
  final rows = db.select(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    [name],
  );
  return rows.isNotEmpty;
}

Set<String> _columnsOf(Database db, String table) {
  final rows = db.select('PRAGMA table_info($table)');
  return {for (final row in rows) '${row['name']}'};
}

// --- rendering --------------------------------------------------------------

/// Renders a report for a human (default) or for `--json`.
String renderProbe(ProbeReport report, {required bool json, int? limit}) {
  if (json) {
    final encoded = report.toJson();
    final cards = (encoded['cards'] as List?) ?? const [];
    if (limit != null && cards.length > limit) {
      encoded['cards'] = cards.take(limit).toList();
      encoded['cards_omitted'] = cards.length - limit;
    }
    return const JsonEncoder.withIndent('  ').convert(encoded);
  }

  final buffer = StringBuffer()
    ..writeln('数据库（只读副本）: ${report.integrity.path}')
    ..writeln('模型: ${report.modelId}')
    ..writeln('原库未被修改: ${report.integrity.unchanged ? '是' : '否 —— 立即停止并排查'}')
    ..writeln('SHA256 前: ${report.integrity.sha256Before}')
    ..writeln('SHA256 后: ${report.integrity.sha256After}')
    ..writeln('副本: ${report.copy.directory}（'
        '${report.copy.copiedFiles.join(', ')}）')
    ..writeln('知识点 ${report.knowledgePoints} 个 · '
        '卡 ${report.cards.length} 张 · '
        '新卡 ${report.summary['newCards'] ?? 0} 张')
    ..writeln('R: 最低 ${_fixed(report.summary['minR'], 3)} · '
        '平均 ${_fixed(report.summary['meanR'], 3)} · '
        '平均增益 ${_fixed(report.summary['meanGain'], 3)}')
    ..writeln('分组: ${_counts(report.summary['bandCounts'])} · '
        '发展区/死角: ${_counts(report.summary['zoneCounts'])}')
    ..writeln('边权 ls 等参数未标定；模型只做顾问，不改到期时间')
    ..writeln('')
    ..writeln('R      增益   分组      发展区/死角   排程间隔/建议  标签  新卡  '
        '卡ID（39 字符 UUID）                      标题');

  final cards = report.cards;
  final shown = limit == null ? cards : cards.take(limit).toList();
  for (final card in shown) {
    buffer.writeln(
      '${_fixed(card['r'], 3).padRight(7)}'
      '${_fixed(card['gain'], 2).padRight(7)}'
      '${'${card['band']}'.padRight(9)}'
      '${'${card['zone']}'.padRight(14)}'
      '${'${_fixed(card['intervalDays'], 1)}/${card['suggestedIntervalDays']}'
          .padRight(15)}'
      '${'${card['tagCount']}'.padRight(6)}'
      '${(card['isNew'] == true ? '是' : '否').padRight(5)}'
      '${'${card['cardStateId']}'.padRight(40)}'
      '${card['knowledgePointTitle']}',
    );
  }
  if (limit != null && cards.length > limit) {
    buffer.writeln('… 其余 ${cards.length - limit} 张未显示（--limit）');
  }
  return buffer.toString();
}

String _fixed(Object? value, int digits) =>
    value is num ? value.toStringAsFixed(digits) : '—';

String _counts(Object? counts) {
  if (counts is! Map) {
    return '—';
  }
  final parts = [
    for (final entry in counts.entries)
      if (entry.value is num && (entry.value as num) > 0)
        '${entry.key}=${entry.value}',
  ];
  return parts.isEmpty ? '—' : parts.join(' · ');
}

Future<void> main(List<String> args) async {
  ProbeOptions options;
  try {
    options = ProbeOptions.parse(args);
  } on ArgumentError catch (error) {
    stderr.writeln('$error\n');
    stderr.writeln(probeUsage);
    exitCode = 2;
    return;
  } on StateError catch (error) {
    stderr.writeln('$error');
    exitCode = 3;
    return;
  }
  if (options.help) {
    stdout.writeln(probeUsage);
    return;
  }

  try {
    final report = await collectProbe(options: options);
    stdout.write(renderProbe(report, json: options.json, limit: options.limit));
    if (!report.integrity.unchanged) {
      stderr.writeln('原库被改动，这是缺陷：${report.integrity.path}');
      exitCode = 2;
    }
  } on StateError catch (error) {
    stderr.writeln('$error');
    exitCode = error.message.toString().startsWith('database not found') ? 3 : 4;
  }
}
