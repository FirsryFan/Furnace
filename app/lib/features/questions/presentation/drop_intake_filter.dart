/// 拖拽添加照片的纯逻辑：文件分类（图片 / 非图片 / 读不出来 / 文件夹）、
/// 扩展名与魔数双保险、同一批拖拽去重、跳过数量聚合。
///
/// 这里**不 import `dart:io`、不碰 desktop_drop / Flutter**：输入是调用方已经取回来
/// 的文件信息（路径、文件名、前 12 字节），输出是「收哪几张、跳过几张」的计划。真正
/// 的磁盘读取在 `drop_intake_reader.dart`；页面只消费计划和字节。
///
/// 为什么要这么小心：微信聊天记录拖出来的图片是**临时文件路径**——中文名、空格、
/// 系统临时目录都出现过，而且 Windows 端 `desktop_drop` 只给路径（没有 name /
/// mimeType），所以文件名一律从 path 自己算；类型先认扩展名，认不出再拿前 12 字节
/// 的魔数兜底（微信有时给的文件名没有扩展名）。
library;

import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// 扩展名 → MIME。与 `HandwritingIntakeStore.mimeForName` 的表一致（data 层由
/// Lead 维护，这里是 presentation 侧的镜像，只用来判断「是不是图片」）。
///
/// 比 `_pickImages` 的 file_picker 白名单多一个 `gif`：文件选择器不给选 gif，但
/// 拖拽时 gif 用魔数就能认出，落盘后 `mimeForName` 也认，没有理由跳掉。
const Map<String, String> dropIntakeMimeByExtension = <String, String>{
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'bmp': 'image/bmp',
};

/// 读文件头时的字节数：上面这些格式的签名都在前 12 字节里
/// （webp 的 `WEBP` 在第 8 字节，heic 的 `ftyp` 品牌在第 8 字节）。
const int dropIntakeHeadByteCount = 12;

/// 从文件名取图片 MIME；不认识的扩展名（含没有扩展名）返回 `null`。
///
/// 大小写不敏感：微信/相机导出的 `IMG_0001.JPG` 也要认。
String? dropIntakeMimeForName(String fileName) {
  final extension = p.extension(fileName);
  if (extension.isEmpty) {
    return null;
  }
  return dropIntakeMimeByExtension[extension.substring(1).toLowerCase()];
}

/// 从完整路径取文件名。用宿主平台的规则切（Windows 下临时路径是反斜杠）。
String dropIntakeFileName(String path) => p.basename(path);

/// 用文件头的 [dropIntakeHeadByteCount] 字节认图片格式；认不出返回 `null`。
///
/// 只认签名，不做完整解码：这是「扩展名不可信时的第二保险」，不是图片校验器。
String? dropIntakeSniffMime(Uint8List head) {
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (_startsWith(
      head, const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  // JPEG: FF D8 FF
  if (head.length >= 3 &&
      head[0] == 0xFF &&
      head[1] == 0xD8 &&
      head[2] == 0xFF) {
    return 'image/jpeg';
  }
  // GIF: "GIF8"
  if (_startsWith(head, const <int>[0x47, 0x49, 0x46, 0x38])) {
    return 'image/gif';
  }
  // WebP: "RIFF" …… "WEBP"（第 8 字节起）
  if (_startsWith(head, const <int>[0x52, 0x49, 0x46, 0x46]) &&
      _asciiAt(head, 8, 'WEBP')) {
    return 'image/webp';
  }
  // BMP: "BM"
  if (_startsWith(head, const <int>[0x42, 0x4D])) {
    return 'image/bmp';
  }
  // HEIC/HEIF: 第 4 字节起 "ftyp"，第 8 字节起是品牌。
  if (_asciiAt(head, 4, 'ftyp')) {
    for (final brand in const <String>[
      'heic',
      'heix',
      'hevc',
      'hevx',
      'mif1',
      'msf1',
      'heif',
      'heis',
      'heim',
      'hevm',
      'hevs',
    ]) {
      if (_asciiAt(head, 8, brand)) {
        return 'image/heic';
      }
    }
  }
  return null;
}

/// 一个被拖进来的文件「已经取回来的信息」。
///
/// [head] 是文件前 [dropIntakeHeadByteCount] 字节；读取失败时是 null，原因记在
/// [readError]。[isDirectory] 对应把文件夹拖进窗口：Windows 的通道只给路径，
/// 类型要读取方自己判。
class DropIntakeCandidate {
  const DropIntakeCandidate({
    required this.path,
    required this.fileName,
    this.head,
    this.readError,
    this.isDirectory = false,
  });

  final String path;
  final String fileName;
  final Uint8List? head;
  final Object? readError;
  final bool isDirectory;
}

/// 一个候选文件的分类结果。
enum DropIntakeStatus { image, nonImage, unreadable, directory }

/// 分类后的文件：页面只关心 [image] 的那几个，其余只用来数数量、提示用户。
class DropIntakeDecision {
  const DropIntakeDecision({
    required this.path,
    required this.fileName,
    required this.status,
    this.mime,
    this.errorReason,
  });

  final String path;
  final String fileName;
  final DropIntakeStatus status;

  /// 图片格式的 MIME；只有 [DropIntakeStatus.image] 才有值。
  final String? mime;

  /// 读不出来时的内部原因（给日志/汇报用，不直接展示给用户）。
  final String? errorReason;

  /// 扩展名（小写、不带点）；没有扩展名时是 null。
  String? get extension {
    final extension = p.extension(fileName);
    if (extension.isEmpty) {
      return null;
    }
    return extension.substring(1).toLowerCase();
  }
}

/// 分类一个候选文件。
///
/// 判定顺序（双保险）：
///  1. 文件夹 → [DropIntakeStatus.directory]；
///  2. 读取失败 / 空文件 → [DropIntakeStatus.unreadable]；
///  3. 扩展名认识 → 图片（MIME 按扩展名，与 store 落库时记的一致）；
///  4. 扩展名不认识但文件头魔数是图片 → 图片（MIME 按魔数，救没有扩展名的临时文件）；
///  5. 其余 → [DropIntakeStatus.nonImage]。
DropIntakeDecision classifyDropIntakeCandidate(DropIntakeCandidate candidate) {
  if (candidate.isDirectory) {
    return DropIntakeDecision(
      path: candidate.path,
      fileName: candidate.fileName,
      status: DropIntakeStatus.directory,
    );
  }
  final readError = candidate.readError;
  if (readError != null) {
    return DropIntakeDecision(
      path: candidate.path,
      fileName: candidate.fileName,
      status: DropIntakeStatus.unreadable,
      errorReason: '$readError',
    );
  }
  final head = candidate.head;
  if (head != null && head.isEmpty) {
    return DropIntakeDecision(
      path: candidate.path,
      fileName: candidate.fileName,
      status: DropIntakeStatus.unreadable,
      errorReason: 'empty file',
    );
  }
  final byName = dropIntakeMimeForName(candidate.fileName);
  if (byName != null) {
    return DropIntakeDecision(
      path: candidate.path,
      fileName: candidate.fileName,
      status: DropIntakeStatus.image,
      mime: byName,
    );
  }
  final byMagic = head == null ? null : dropIntakeSniffMime(head);
  if (byMagic != null) {
    return DropIntakeDecision(
      path: candidate.path,
      fileName: candidate.fileName,
      status: DropIntakeStatus.image,
      mime: byMagic,
    );
  }
  return DropIntakeDecision(
    path: candidate.path,
    fileName: candidate.fileName,
    status: DropIntakeStatus.nonImage,
  );
}

/// 去重用的 key：规范化路径；[ignoreCase] 在 Windows / macOS 上传 true
/// （同一个临时文件大小写不同，不该收两遍）。Linux 路径大小写敏感，传 false。
String dropIntakeDedupKey(String path, {bool ignoreCase = false}) {
  final normalized = p.normalize(path);
  return ignoreCase ? normalized.toLowerCase() : normalized;
}

/// 一批拖拽的处理计划。
class DropIntakePlan {
  const DropIntakePlan({
    required this.images,
    required this.unreadable,
    this.nonImageCount = 0,
    this.duplicateCount = 0,
    this.directoryCount = 0,
  });

  /// 图片，顺序 = 拖入顺序；页面按这个顺序落盘。
  final List<DropIntakeDecision> images;

  /// 读不出来 / 空文件的那些（页面把它们并进「跳过」数量，并留第一条原因）。
  final List<DropIntakeDecision> unreadable;

  final int nonImageCount;
  final int duplicateCount;
  final int directoryCount;

  /// 这一批实际看了几个路径（去重前）。
  int get consideredCount =>
      images.length +
      unreadable.length +
      nonImageCount +
      duplicateCount +
      directoryCount;

  /// 第一条读取错误，给「这次失败了：…」的提示用；没有就 null。
  String? get firstError {
    for (final decision in unreadable) {
      final reason = decision.errorReason;
      if (reason != null && reason.isNotEmpty) {
        return reason;
      }
    }
    return null;
  }
}

/// 把候选文件排成计划：同一批里同一个路径只收一次，其余分桶计数。
DropIntakePlan planDropIntake(
  List<DropIntakeCandidate> candidates, {
  bool ignorePathCase = false,
}) {
  final seen = <String>{};
  final images = <DropIntakeDecision>[];
  final unreadable = <DropIntakeDecision>[];
  var nonImage = 0;
  var duplicates = 0;
  var directories = 0;
  for (final candidate in candidates) {
    final key = dropIntakeDedupKey(
      candidate.path,
      ignoreCase: ignorePathCase,
    );
    if (!seen.add(key)) {
      duplicates++;
      continue;
    }
    final decision = classifyDropIntakeCandidate(candidate);
    switch (decision.status) {
      case DropIntakeStatus.image:
        images.add(decision);
      case DropIntakeStatus.nonImage:
        nonImage++;
      case DropIntakeStatus.unreadable:
        unreadable.add(decision);
      case DropIntakeStatus.directory:
        directories++;
    }
  }
  return DropIntakePlan(
    images: images,
    unreadable: unreadable,
    nonImageCount: nonImage,
    duplicateCount: duplicates,
    directoryCount: directories,
  );
}

bool _startsWith(Uint8List bytes, List<int> signature) {
  if (bytes.length < signature.length) {
    return false;
  }
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) {
      return false;
    }
  }
  return true;
}

bool _asciiAt(Uint8List bytes, int offset, String text) {
  if (bytes.length < offset + text.length) {
    return false;
  }
  for (var i = 0; i < text.length; i++) {
    if (bytes[offset + i] != text.codeUnitAt(i)) {
      return false;
    }
  }
  return true;
}
