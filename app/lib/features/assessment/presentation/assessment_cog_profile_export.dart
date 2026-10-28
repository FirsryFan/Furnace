/// 认知档案导出：能力/参数估计 → `.cogprofile` JSON → 系统「另存为」。
///
/// 分工：
/// - JSON 结构与编码在 `domain/assessment_cog_profile.dart`（纯逻辑，只读复用）；
/// - 保存走 `file_picker` 的静态 `saveFile`；静态方法在 widget test 里没法替换
///   平台通道，所以用 [cogProfileFileSaverProvider] 留 seam；
/// - 文件名是纯函数，时间由调用方注入，本文件不读时钟。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/assessment_cog_profile.dart';
import '../domain/assessment_models.dart';

/// 保存 `.cogprofile` 的动作：返回落盘位置（`Uri`），用户取消则返回 null。
///
/// 抽成 typedef 是为了让 widget test 能截获保存动作：`FilePicker.saveFile` 是
/// 静态方法，平台通道没法在测试里被 mock。
typedef CogProfileFileSaver = Future<Uri?> Function({
  required String fileName,
  required List<int> bytes,
});

/// 默认保存实现：弹系统「另存为」，由 file_picker 平台实现写盘。
///
/// 不自己再 `File.write`；取消（null）由界面判断为「不提示」。
Future<Uri?> saveCogProfileWithFilePicker({
  required String fileName,
  required List<int> bytes,
}) {
  return FilePicker.saveFile(
    dialogTitle: 'Export cognitive profile',
    fileName: fileName,
    bytes: Uint8List.fromList(bytes),
    type: FileType.custom,
    allowedExtensions: const <String>['cogprofile'],
  );
}

/// 保存动作的 provider：测试 override 它，不弹真实对话框、不碰磁盘。
final cogProfileFileSaverProvider = Provider<CogProfileFileSaver>(
  (ref) => saveCogProfileWithFilePicker,
);

/// 导出文件名：`furnace-cogprofile-yyyyMMdd-HHmm.cogprofile`（本地时间）。
///
/// 月、日、时、分都补零；[at] 是 UTC 时先转本地再取字段，避免文件名与本机
/// 展示时间不一致。
String cogProfileFileName(DateTime at) {
  final local = at.toLocal();
  final date = local.year.toString().padLeft(4, '0') +
      local.month.toString().padLeft(2, '0') +
      local.day.toString().padLeft(2, '0');
  final time = local.hour.toString().padLeft(2, '0') +
      local.minute.toString().padLeft(2, '0');
  return 'furnace-cogprofile-$date-$time.cogprofile';
}

/// 生成导出的 JSON 字节（UTF-8）。
///
/// 排序/净化/隐私声明都交给 [buildCogProfile] 与 [encodeCogProfile]；这里只做
/// 编码。调用方负责传入已读出的估计（通常是档案页的 profile snapshot）。
Future<List<int>> buildCogProfileBytes({
  required List<AbilityEstimate> abilities,
  required List<ParamEstimate> cognitiveParams,
  required DateTime exportedAt,
}) async {
  final profile = buildCogProfile(
    abilities: abilities,
    cognitiveParams: cognitiveParams,
    exportedAt: exportedAt,
  );
  return utf8.encode(encodeCogProfile(profile));
}
