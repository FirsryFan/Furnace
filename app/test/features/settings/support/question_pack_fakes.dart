/// 题库包（`.tqb`）设置页测试用的替身：文件选择器、用户选中的文件、题库包服务。
///
/// 为什么要它们：
///
///  * `FilePicker.saveFile` / `pickFiles` 都走 `FilePickerPlatform.instance`，
///    测试里没有平台实现（调用直接 `UnimplementedError`），所以导出/导入这两条
///    通路只有替换平台实例才测得到；替身同时把文件名/字节记下来供断言。
///  * `QuestionPackService` 要真的 DB、图片目录和标签仓库才能构造；设置页 UI 只
///    消费它的三个方法，所以用接口替身，避免在 widget test 里造整套数据层。
library;

import 'dart:async';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:furnace/domain/services/package/question_pack_import_preview.dart';
import 'package:furnace/domain/services/package/question_pack_selection.dart';
import 'package:furnace/features/questions/application/question_pack_service.dart';
import 'package:path/path.dart' as p;

/// 内存里的一个"用户选中的文件"：`readAsBytes()` 不碰磁盘。
final class FakeQuestionPackFile extends PlatformFile {
  FakeQuestionPackFile(this.name, this.bytes);

  @override
  final String name;

  final Uint8List bytes;

  @override
  Uri get uri => Uri.file('/fake/${p.basename(name)}');

  @override
  XFile get xFile => XFile.fromData(bytes, name: name);

  @override
  int? lengthSync() => bytes.length;

  @override
  Future<int> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() async* {
    yield bytes;
  }
}

/// 记录调用参数的选择器替身；`cancelSave` / `saveError` 用来模拟取消与失败。
final class FakeQuestionPackPicker extends FilePickerPlatform {
  FakeQuestionPackPicker({List<PlatformFile>? picked})
      : picked = picked ?? <PlatformFile>[];

  List<PlatformFile> picked;

  /// 导出时"用户取消保存框"。
  bool cancelSave = false;

  /// 导出时保存框抛错（磁盘满等）。
  Object? saveError;

  int pickCalls = 0;
  int saveCalls = 0;
  String? savedFileName;
  Uint8List? savedBytes;
  String? savedMimeType;
  String? savedDialogTitle;
  List<String>? pickedAllowedExtensions;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    pickCalls++;
    pickedAllowedExtensions = allowedExtensions;
    return picked;
  }

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    saveCalls++;
    savedFileName = fileName;
    savedBytes = bytes;
    savedMimeType = mimeType;
    savedDialogTitle = dialogTitle;
    if (saveError != null) {
      throw saveError!;
    }
    if (cancelSave) {
      return null;
    }
    return Uri.file('/fake/$fileName');
  }
}

/// 题库包服务替身：记录调用次数与字节，可注入错误并挂起导出。
final class FakeQuestionPackService implements QuestionPackService {
  QuestionPackExportResult exportResult = QuestionPackExportResult(
    bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
    questionCount: 2,
    mediaCount: 1,
  );

  /// [peek] 的返回值（UI 已改用 [planImport]，保留为接口完整性）。
  QuestionPackPreview preview = const QuestionPackPreview(
    questionCount: 2,
    mediaCount: 1,
  );

  /// [planImport] 的返回值；缺省是「3 道题里新建 2、跳过 1、无告警」。
  QuestionPackImportPreview importPreview = const QuestionPackImportPreview(
    manifestQuestionCount: 3,
    manifestMediaCount: 2,
    recordCount: 3,
    mediaCount: 2,
    appVersion: '0.5.3',
    exportedAt: null,
    createCount: 2,
    skipCount: 1,
    missingTagCount: 0,
    warnings: <String>[],
    missingTagPaths: <String>[],
  );

  QuestionPackImportReport importReport = const QuestionPackImportReport(
    createdCount: 2,
    skippedCount: 1,
    mediaCount: 1,
    warnings: <String>[],
    failures: <String>[],
  );

  /// [listBackups] 的返回值；删除成功会同步从这里移除（模拟刷新后条目变少）。
  List<QuestionPackBackup> backups = const <QuestionPackBackup>[];

  /// [readBackupBytes] 返回的字节（恢复时应原样交给 planImport/importPack）。
  Uint8List backupBytes = Uint8List.fromList(<int>[7, 7, 7]);

  Object? exportError;
  Object? previewError;
  Object? planError;
  Object? importError;
  Object? listBackupsError;
  Object? deleteBackupError;
  Object? readBackupBytesError;

  /// 挂住导出（挂起期间断言两行 tile 都被禁用）。
  Completer<void>? exportGate;

  int exportCalls = 0;
  int peekCalls = 0;
  int planCalls = 0;
  int importCalls = 0;
  int listBackupsCalls = 0;
  int readBackupBytesCalls = 0;
  final List<String> deletedBackupPaths = <String>[];
  final List<String> readBackupBytesPaths = <String>[];
  final List<Uint8List> peekedBytes = <Uint8List>[];
  final List<Uint8List> plannedBytes = <Uint8List>[];
  final List<Uint8List> importedBytes = <Uint8List>[];

  /// 每次导出收到的筛选条件；[lastSelection] 是最后一次。
  final List<QuestionPackSelection> selections = <QuestionPackSelection>[];
  QuestionPackSelection? lastSelection;

  /// 每次导出收到的题目 id 集合；[lastQuestionIds] 是最后一次。
  final List<Set<String>> questionIdSets = <Set<String>>[];
  Set<String>? lastQuestionIds;

  @override
  Future<QuestionPackExportResult> exportBytes({
    DateTime? now,
    QuestionPackSelection selection = const QuestionPackSelection(),
    Set<String> questionIds = const <String>{},
  }) async {
    exportCalls++;
    lastSelection = selection;
    selections.add(selection);
    lastQuestionIds = questionIds;
    questionIdSets.add(questionIds);
    if (exportError != null) {
      throw exportError!;
    }
    final gate = exportGate;
    if (gate != null) {
      await gate.future;
    }
    return exportResult;
  }

  @override
  QuestionPackPreview peek(Uint8List bytes) {
    peekCalls++;
    peekedBytes.add(bytes);
    if (previewError != null) {
      throw previewError!;
    }
    return preview;
  }

  @override
  Future<QuestionPackImportPreview> planImport(Uint8List bytes) async {
    planCalls++;
    plannedBytes.add(bytes);
    if (planError != null) {
      throw planError!;
    }
    return importPreview;
  }

  @override
  Future<QuestionPackImportReport> importPack(
    Uint8List bytes, {
    DateTime? now,
  }) async {
    importCalls++;
    importedBytes.add(bytes);
    if (importError != null) {
      throw importError!;
    }
    return importReport;
  }

  @override
  Future<List<QuestionPackBackup>> listBackups() async {
    listBackupsCalls++;
    if (listBackupsError != null) {
      throw listBackupsError!;
    }
    return backups;
  }

  @override
  Future<void> deleteBackup(String path) async {
    deletedBackupPaths.add(path);
    if (deleteBackupError != null) {
      throw deleteBackupError!;
    }
    backups =
        backups.where((backup) => backup.path != path).toList(growable: false);
  }

  @override
  Future<Uint8List> readBackupBytes(String path) async {
    readBackupBytesCalls++;
    readBackupBytesPaths.add(path);
    if (readBackupBytesError != null) {
      throw readBackupBytesError!;
    }
    return backupBytes;
  }
}
