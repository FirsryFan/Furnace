// Runs the read-only probe during a `flutter test` invocation.
//
// This is the *hosted* entry: the probe logic lives in `tool/mindnet_probe.dart`
// (pure Dart), while the model seam only compiles inside a Flutter runtime
// (`database.dart` -> `path_provider` -> `package:flutter` -> `dart:ui`, which a
// plain Dart VM does not have). `dart run tool/mindnet_probe.dart` works as a
// launcher that hands the reading request to this entry.
//
// The host runs **in-process** here (see `_hostInProcess`). The probe's default
// runner spawns a second `flutter test` (outer test + inner host), which took
// 21-36 s and straddled the default 30 s test timeout - green on a warm machine,
// flaky on a cold one. In-process the entry takes seconds.
//
// Usage (Windows PowerShell):
//   flutter test test/tool/mindnet_probe_report_test.dart `
//     --dart-define=PROBE_DB="$env:APPDATA\FirsryFan\Furnace\furnace.db"
//   # add --dart-define=PROBE_JSON=1 for JSON, --dart-define=PROBE_LIMIT=20 to cap
//
// Without PROBE_DB the test is skipped, so the normal suite stays green and
// nobody accidentally reads a real database in CI.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';

import '../../tool/mindnet_probe.dart';

const _dbPath = String.fromEnvironment('PROBE_DB');
const _asJson = String.fromEnvironment('PROBE_JSON') == '1';
const _limitRaw = String.fromEnvironment('PROBE_LIMIT');

/// Computes the reading in *this* process.
///
/// [ProbeHostRequest] carries the units JSON the probe wrote and the path the
/// readings must land in. `readingsFromUnitsJson` is the very function the real
/// host calls, so the numbers are identical - only the process boundary (and
/// with it a second `flutter test` boot) goes away.
Future<ProbeHostResult> _hostInProcess(ProbeHostRequest request) async {
  final units = (jsonDecode(File(request.unitsPath).readAsStringSync()) as Map)
      .cast<String, Object?>();
  final readings = readingsFromUnitsJson(units, now: request.now);
  File(request.readingsPath).writeAsStringSync(jsonEncode(readings.toJson()));
  return const ProbeHostResult(exitCode: 0, stdout: '', stderr: '');
}

void main() {
  test('cognitive model reading for the real database (read-only copy)', () async {
    if (_dbPath.isEmpty) {
      markTestSkipped('set --dart-define=PROBE_DB=<path> to run the probe');
      return;
    }

    final before = File(_dbPath).statSync();
    final report = await collectProbe(
      options: ProbeOptions(
        dbPath: _dbPath,
        json: _asJson,
        limit: _limitRaw.isEmpty ? null : int.parse(_limitRaw),
      ),
      now: DateTime.now(),
      // In-process host: no second `flutter test` process (see _hostInProcess).
      host: _hostInProcess,
    );
    final after = File(_dbPath).statSync();

    stdout.write(renderProbe(
      report,
      json: _asJson,
      limit: _limitRaw.isEmpty ? null : int.parse(_limitRaw),
    ));

    // The probe's whole safety claim: the original file is only ever stat-ed.
    expect(report.originalUntouched, isTrue,
        reason: 'the probe must never write to the real database');
    expect(after.size, before.size);
    expect(after.modified, before.modified);
    // Booting a Flutter runtime, copying the database and reading every card
    // takes tens of seconds (15-40 s measured on this machine) - over the
    // default 30 s test timeout. Without an explicit allowance the documented
    // command dies with `TimeoutException after 0:00:30` and looks like a
    // permanent failure. The headroom below is deliberately generous.
  }, timeout: const Timeout(Duration(minutes: 5)));
}
