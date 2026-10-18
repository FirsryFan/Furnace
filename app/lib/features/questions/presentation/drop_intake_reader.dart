/// 把 OS 拖进来的 `DropItem` 读成「可以直接交给 `HandwritingIntakeStore.save` 的
/// 图片字节」。
///
/// 分工：分类 / 去重 / 魔数规则在 `drop_intake_filter.dart`（纯函数，可单测）；
/// 这里只做两件事——磁盘 I/O 和 `DropItem` → `PlatformFile` 的适配。
///
/// Windows 端 `desktop_drop` 的 `performOperation` 只给 `List<String> paths`
/// （`channel.dart` 里映射成 `DropItemFile(path)`），没有 name / mimeType；
/// 微信聊天记录拖出来的又是临时目录里的中文/空格路径。所以文件名一律从 path
/// 自己算，字节自己读，不信任 `DropItem` 上的元数据。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart' show PlatformFile;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'drop_intake_filter.dart';

/// 页面用的拖拽读取器。测试里 override 成假实现（真实现要走 `dart:io` 的异步
/// 文件 API，在 `testWidgets` 的假时钟里等不到回调）。
final Provider<DropIntakeReader> dropIntakeReaderProvider =
    Provider<DropIntakeReader>((ref) => const DropIntakeReader());

/// 一批拖拽的读取结果：分类计划和每张图的完整字节。
class DropIntakeBatch {
  const DropIntakeBatch({required this.plan, required this.bytes});

  final DropIntakePlan plan;

  /// path → 图片完整字节。计划里是图片、但这里没有对应 key 的，说明整读失败，
  /// 页面把它算成「读不出来」而不是直接报错。
  final Map<String, Uint8List> bytes;
}

/// `DropItem` → 候选文件 → 纯函数排计划 → 读整张图的字节。
class DropIntakeReader {
  const DropIntakeReader();

  /// 读取一次拖拽事件里的全部文件。
  ///
  /// 顺序保留：先按拖入顺序排计划，再按计划里的图片顺序读字节，页面照序落盘。
  Future<DropIntakeBatch> examine(List<DropItem> items) async {
    final candidates = <DropIntakeCandidate>[];
    for (final item in items) {
      candidates.add(await _candidateOf(item));
    }
    final plan = planDropIntake(
      candidates,
      // Windows / macOS 的文件系统大小写不敏感：同一个临时文件不该收两遍。
      ignorePathCase: Platform.isWindows || Platform.isMacOS,
    );
    final bytes = <String, Uint8List>{};
    for (final decision in plan.images) {
      final payload = await _readBytes(decision.path);
      if (payload != null) {
        bytes[decision.path] = payload;
      }
    }
    return DropIntakeBatch(plan: plan, bytes: bytes);
  }

  Future<DropIntakeCandidate> _candidateOf(DropItem item) async {
    final path = item.path;
    final fileName = dropIntakeFileName(path);
    if (item is DropItemDirectory) {
      return DropIntakeCandidate(
        path: path,
        fileName: fileName,
        isDirectory: true,
      );
    }
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.directory) {
      return DropIntakeCandidate(
        path: path,
        fileName: fileName,
        isDirectory: true,
      );
    }
    if (type != FileSystemEntityType.file) {
      return DropIntakeCandidate(
        path: path,
        fileName: fileName,
        readError: StateError('not a regular file ($type)'),
      );
    }
    try {
      return DropIntakeCandidate(
        path: path,
        fileName: fileName,
        head: await _readHead(path),
      );
    } catch (error) {
      return DropIntakeCandidate(
        path: path,
        fileName: fileName,
        readError: error,
      );
    }
  }

  Future<Uint8List> _readHead(String path) async {
    final file = await File(path).open();
    try {
      return await file.read(dropIntakeHeadByteCount);
    } finally {
      await file.close();
    }
  }

  Future<Uint8List?> _readBytes(String path) async {
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }
}

/// `DropItem` 不是 `PlatformFile`，而 `HandwritingIntakeStore.save` 只用到
/// `name` + `readAsBytes()`：补一个最小实现，把已经从磁盘读出来的字节直接递过去，
/// 不再二次读盘。
///
/// `xFile` 返回 `Never` 是故意的：要实现真正的 `XFile` 就得直接 import
/// `package:cross_file`，它只是 file_picker 的传递依赖、不在本项目的 pubspec
/// 里，import 会触发 `depend_on_referenced_packages`。`save()` 不走这条；真有人
/// 调用会立刻炸出来，比悄悄返回一个假 XFile 安全。
final class DropIntakePlatformFile extends PlatformFile {
  DropIntakePlatformFile({
    required this.name,
    required this.path,
    required this.bytes,
  });

  @override
  final String name;

  @override
  final String path;

  final Uint8List bytes;

  @override
  Uri get uri => Uri.file(path);

  @override
  Never get xFile => throw UnsupportedError(
        'DropIntakePlatformFile only serves HandwritingIntakeStore.save; xFile is not supported.',
      );

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
