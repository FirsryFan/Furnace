// 对拍脚本（本仓库侧，临时用，跑完删）：把同一份信封跑成 Dart 的产物。
//
// 用法（在 app 目录下）：
//   dart run tool/ingest_dump.dart [fixture.json] [dart-out.json]
//
// 这是 INGEST 对拍三步的第 2 步（第 1 步 `ingest_parity_reference.cjs`，第 3 步
// `ingest_parity_compare.cjs`）。放在 app/tool/ 下是因为只有在这里 `package:furnace`
// 才解析得到；它不在 `dart analyze lib test` 与 `flutter test` 的范围内。
import 'dart:convert';
import 'dart:io';

import 'package:furnace/domain/services/ingest/material_ingest.dart';

void main(List<String> args) {
  final fixture = args.isNotEmpty
      ? args[0]
      : r'E:\dsh-tmp-aot\mindnet-material-fixture.json';
  final out = args.length > 1 ? args[1] : r'E:\dsh-tmp-aot\dart-out.json';
  final nowHours =
      double.tryParse(Platform.environment['NOW_HOURS'] ?? '') ?? 497321.25;

  final raw = File(fixture).readAsStringSync();
  final envelope = MaterialEnvelope.fromJson(
    (jsonDecode(raw) as Map).cast<String, Object?>(),
  );
  final result = MaterialIngest.convert(envelope, nowHours: nowHours);
  // 三样正产品 + 汇总。cards / tts / anki 是 INGEST §4 的可选呈现层，本层不做。
  final json = <String, Object?>{
    'items': <Object?>[
      for (final item in result.standardItems) item.toJson(),
    ],
    'graph_patch': result.graphPatch.toJson(),
    'run_request': result.runRequest.toJson(),
    'summary': result.summary.text,
  };
  File(out).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  stdout.writeln('Dart 端口 → $out');
}
