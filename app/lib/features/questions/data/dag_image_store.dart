/// DAG 图片落盘：一张思维链一张 PNG，按链 id 缓存。
///
/// 目录：`<app support>/question_dag_images/<chainId>.png`。缓存键是
/// `reasoning_chains.id`——链是不可变数据（同题可以有多条，每条一个新 id），
/// 所以"同一个 id 对应同一张图"成立，不需要比对内容或时间戳。
///
/// 文件是**真的生成并写入磁盘**的：详情页显示的字节就是写进文件的那些字节。
/// 生成失败不吞：包装成 [DagImageStoreException]，界面据此显示"生成失败 + 原因 +
/// 重试"，而不是留一块空白。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../data/storage/app_storage.dart';
import '../../../domain/services/reasoning/reasoning_prompt.dart';
import '../application/dag_image_renderer.dart';

/// 生成/落盘失败（message 可直接显示给用户）。
class DagImageStoreException implements Exception {
  const DagImageStoreException(this.message);

  final String message;

  @override
  String toString() => 'DagImageStoreException: $message';
}

/// 一张已经生成好的 DAG 图片。
class DagImageFile {
  const DagImageFile({
    required this.absolutePath,
    required this.bytes,
    required this.width,
    required this.height,
    required this.fromCache,
  });

  /// PNG 的绝对路径（详情页只用于诊断/日志；显示用的是 [bytes]）。
  final String absolutePath;

  final Uint8List bytes;
  final int width;
  final int height;

  /// true = 这次没有重新渲染，直接读了上次落盘的文件。
  final bool fromCache;

  bool get isPng =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47;
}

/// 生成 DAG 图片并写进 app support 目录。
class DagImageStore {
  DagImageStore({
    required DagImageRenderer renderer,
    Future<Directory> Function()? supportDirectory,
  })  : _renderer = renderer,
        _supportDirectory = supportDirectory ?? AppStorage.supportDirectory;

  /// app support 目录下的子目录名（与 `question_images` 同一层的兄弟目录）。
  static const String directoryName = 'question_dag_images';

  final DagImageRenderer _renderer;
  final Future<Directory> Function() _supportDirectory;

  /// 同一个链同时被两处要求生成时（解题回调预热 + 详情页首帧），只跑一次。
  final Map<String, Future<DagImageFile>> _inFlight =
      <String, Future<DagImageFile>>{};

  /// 图片缓存键：入库的链用链 id；没入库的"本次运行"链按步骤内容做稳定哈希。
  ///
  /// 同一份内容永远得到同一个键，所以同一张运行中的链不会每次都生成两个文件。
  static String cacheKeyOf(String? chainId, ParsedChain chain) {
    final id = chainId?.trim() ?? '';
    if (id.isNotEmpty) {
      return id;
    }
    var hash = 0x811c9dc5;
    void mix(String text) {
      for (final rune in text.runes) {
        hash ^= rune;
        hash = (hash * 0x01000193) & 0x7fffffff;
      }
      hash = (hash * 0x01000193) & 0x7fffffff;
    }

    mix(chain.summary);
    for (final step in chain.steps) {
      mix(step.index.toString());
      mix(step.actionType);
      mix(step.goal);
      mix(step.stuckRisk.toString());
    }
    return 'runtime-${hash.toRadixString(16)}';
  }

  /// 图片文件路径（不一定存在）。
  Future<File> fileFor(String cacheKey) async {
    final root = await _resolveRoot();
    return File(p.join(root.path, '${_safeFileName(cacheKey)}.png'));
  }

  /// 保证 `cacheKey` 对应的 DAG 图片已经生成并落盘，返回它的字节。
  Future<DagImageFile> ensure({
    required String cacheKey,
    required ParsedChain chain,
    String title = '思维 DAG',
  }) {
    final key = _safeFileName(cacheKey);
    final pending = _inFlight[key];
    if (pending != null) {
      return pending;
    }
    final future = _ensureUncached(key: key, chain: chain, title: title);
    _inFlight[key] = future;
    // 只负责清理登记表：错误仍然交给真正的调用方（`whenComplete` 的返回值不
    // 在这里链式使用，避免多出一条没人监听的错误 Future）。
    future.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    ).whenComplete(() {
      if (identical(_inFlight[key], future)) {
        _inFlight.remove(key);
      }
    });
    return future;
  }

  Future<DagImageFile> _ensureUncached({
    required String key,
    required ParsedChain chain,
    required String title,
  }) async {
    final file = await fileFor(key);
    final cached = await _readCached(file);
    if (cached != null) {
      return cached;
    }

    final DagImageRenderResult rendered;
    try {
      rendered = await _renderer.render(chain, title: title);
    } on DagImageRenderException {
      rethrow;
    } on Object catch (error) {
      throw DagImageStoreException('DAG 图片渲染失败：$error');
    }
    try {
      // 同步写：图片只有几十 KB，写盘耗时可以忽略；同步 IO 让「已缓存 / 已写
      // 入」这类判断在 Flutter 的 fake-async widget 测试里也能确定完成（异步
      // 文件 IO 需要 real-async 通道，widget 测试里会把界面卡在转圈上）。
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(rendered.bytes, flush: true);
    } on FileSystemException catch (error) {
      throw DagImageStoreException(
        'DAG 图片写不进本地目录（${file.path}）：'
        '${error.osError?.message ?? error.message}',
      );
    } on Object catch (error) {
      throw DagImageStoreException('DAG 图片写入本地目录失败：$error');
    }
    return DagImageFile(
      absolutePath: file.path,
      bytes: rendered.bytes,
      width: rendered.width,
      height: rendered.height,
      fromCache: false,
    );
  }

  Future<DagImageFile?> _readCached(File file) async {
    try {
      // 同步读，理由同 `_ensureUncached` 里的写：小文件、且让缓存命中在
      // fake-async widget 测试里也能确定完成。
      if (!file.existsSync()) {
        return null;
      }
      final bytes = file.readAsBytesSync();
      final size = _pngSize(bytes);
      if (size == null) {
        // 上次写了一半 / 文件坏了：删掉重画，不让一张坏图长期占着缓存键。
        try {
          file.deleteSync();
        } on FileSystemException {
          // 删不掉也照样重画；writeAsBytesSync 会覆盖它。
        }
        return null;
      }
      return DagImageFile(
        absolutePath: file.path,
        bytes: bytes,
        width: size.width,
        height: size.height,
        fromCache: true,
      );
    } on FileSystemException {
      return null;
    }
  }

  Future<Directory> _resolveRoot() async {
    final Directory support;
    try {
      support = await _supportDirectory();
    } on Object catch (error) {
      throw DagImageStoreException('读不到本机数据目录：$error');
    }
    return Directory(p.join(support.path, directoryName));
  }

  static String _safeFileName(String raw) {
    final trimmed = raw.trim();
    final source = trimmed.isEmpty ? 'unknown-chain' : trimmed;
    final buffer = StringBuffer();
    for (final unit in source.codeUnits) {
      final isDigit = unit >= 0x30 && unit <= 0x39;
      final isUpper = unit >= 0x41 && unit <= 0x5A;
      final isLower = unit >= 0x61 && unit <= 0x7A;
      final isDash = unit == 0x2D || unit == 0x5F;
      buffer.write(isDigit || isUpper || isLower || isDash ? String.fromCharCode(unit) : '_');
      if (buffer.length >= 96) {
        break;
      }
    }
    final name = buffer.toString();
    return name.isEmpty ? 'unknown-chain' : name;
  }

  /// 从 PNG 头里读尺寸；不是合法 PNG（签名/IHDR 不对）时返回 null。
  static ({int width, int height})? _pngSize(Uint8List bytes) {
    if (bytes.length < 24) {
      return null;
    }
    const signature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) {
        return null;
      }
    }
    final width = _readUint32(bytes, 16);
    final height = _readUint32(bytes, 20);
    if (width <= 0 || height <= 0) {
      return null;
    }
    return (width: width, height: height);
  }

  static int _readUint32(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }
}
