/// 题库包（.tqb）的 zip 容器：打包与解包（数据层）。
///
/// 包内固定三样东西：`manifest.json`（清单）、`questions.json`（题目记录）、
/// `media/...`（配图字节）。容器层只做「zip ↔ 三样东西」的映射与结构校验：
/// 清单/记录字段的校验在 domain 层（question_pack_manifest.dart /
/// question_pack_record.dart），这里不重复写一遍规则。
///
/// 两个刻意的口径：
///  - **缺媒体文件就整包失败**：记录里写了 `pack_path` 但包里没有这个条目，说明
///    包被改坏了；导入时静默少几张图比报错更难查。
///  - **多余条目忽略**：包里多出来的文件不参与导入，也不报错（给以后加文件留余地）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../domain/services/package/question_pack_manifest.dart';
import '../../domain/services/package/question_pack_record.dart';

/// 包内清单文件名。
const String kQuestionPackManifestEntry = 'manifest.json';

/// 包内题目文件名。
const String kQuestionPackQuestionsEntry = 'questions.json';

/// 解包后的题库包。
class QuestionPackArchive {
  const QuestionPackArchive({
    required this.manifest,
    required this.records,
    required this.mediaBytes,
  });

  /// 包清单。
  final QuestionPackManifest manifest;

  /// 题目记录（顺序与 `questions.json` 一致，媒体路径里的「题序」按这个顺序数）。
  final List<QuestionPackRecord> records;

  /// 包内媒体路径 → 字节；键与 [QuestionPackMedia.packPath] 对应。
  final Map<String, Uint8List> mediaBytes;

  /// 实际解出来的媒体文件数（可能与清单里的计数不同，见 [QuestionPackManifest.mediaCount]）。
  int get mediaCount => mediaBytes.length;

  bool get isEmpty => records.isEmpty;
}

/// 把清单 / 题目 / 媒体打成 zip 字节。
Uint8List encodeQuestionPackArchive({
  required QuestionPackManifest manifest,
  required List<QuestionPackRecord> records,
  required Map<String, Uint8List> mediaBytes,
}) {
  final archive = Archive();
  final manifestBytes = utf8.encode(encodeQuestionPackManifest(manifest));
  archive.addFile(ArchiveFile(
    kQuestionPackManifestEntry,
    manifestBytes.length,
    manifestBytes,
  ));
  final recordsBytes = utf8.encode(encodeQuestionPackRecords(records));
  archive.addFile(ArchiveFile(
    kQuestionPackQuestionsEntry,
    recordsBytes.length,
    recordsBytes,
  ));
  final paths = mediaBytes.keys.toList()..sort();
  for (final path in paths) {
    final bytes = mediaBytes[path]!;
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw const QuestionPackException('打包失败：zip 编码器没有返回字节');
  }
  return Uint8List.fromList(encoded);
}

/// 只读包清单（不解题目与媒体）。
QuestionPackManifest readQuestionPackManifest(Uint8List bytes) {
  final archive = _decodeZip(bytes);
  final manifestFile = _fileNamed(archive, kQuestionPackManifestEntry);
  if (manifestFile == null) {
    throw const QuestionPackException(
      '不是题库包：缺 manifest.json',
      path: kQuestionPackManifestEntry,
    );
  }
  return decodeQuestionPackManifest(
    _decodeJsonBytes(manifestFile, kQuestionPackManifestEntry),
    path: kQuestionPackManifestEntry,
  );
}

/// 解开整个题库包：清单、题目记录、媒体字节。
QuestionPackArchive decodeQuestionPackArchive(Uint8List bytes) {
  final archive = _decodeZip(bytes);
  final manifestFile = _fileNamed(archive, kQuestionPackManifestEntry);
  if (manifestFile == null) {
    throw const QuestionPackException(
      '不是题库包：缺 manifest.json',
      path: kQuestionPackManifestEntry,
    );
  }
  final questionsFile = _fileNamed(archive, kQuestionPackQuestionsEntry);
  if (questionsFile == null) {
    throw const QuestionPackException(
      '不是题库包：缺 questions.json',
      path: kQuestionPackQuestionsEntry,
    );
  }
  final manifest = decodeQuestionPackManifest(
    _decodeJsonBytes(manifestFile, kQuestionPackManifestEntry),
    path: kQuestionPackManifestEntry,
  );
  final records = decodeQuestionPackRecords(
    _decodeJsonBytes(questionsFile, kQuestionPackQuestionsEntry),
    path: kQuestionPackQuestionsEntry,
  );

  final mediaBytes = <String, Uint8List>{};
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final name = _normalizeEntryName(file.name);
    if (name == kQuestionPackManifestEntry ||
        name == kQuestionPackQuestionsEntry) {
      continue;
    }
    mediaBytes[name] = Uint8List.fromList(file.content as List<int>);
  }

  for (final record in records) {
    for (final media in record.media) {
      if (!mediaBytes.containsKey(media.packPath)) {
        throw QuestionPackException(
          '包不完整：缺媒体文件 ${media.packPath}',
          path: media.packPath,
        );
      }
    }
  }

  return QuestionPackArchive(
    manifest: manifest,
    records: records,
    mediaBytes: mediaBytes,
  );
}

Archive _decodeZip(Uint8List bytes) {
  try {
    return ZipDecoder().decodeBytes(bytes);
  } on Object catch (error) {
    throw QuestionPackException('读不了这个题库包（zip 解析失败）：$error');
  }
}

ArchiveFile? _fileNamed(Archive archive, String name) {
  for (final file in archive.files) {
    if (!file.isFile) continue;
    if (_normalizeEntryName(file.name) == name) return file;
  }
  return null;
}

String _normalizeEntryName(String raw) {
  var name = raw.replaceAll('\\', '/');
  while (name.startsWith('/')) {
    name = name.substring(1);
  }
  return name;
}

Object? _decodeJsonBytes(ArchiveFile file, String path) {
  final text = _decodeUtf8(file, path);
  try {
    return jsonDecode(text);
  } on FormatException catch (error) {
    throw QuestionPackException('$path 不是合法 JSON：${error.message}', path: path);
  }
}

String _decodeUtf8(ArchiveFile file, String path) {
  final content = file.content as List<int>;
  try {
    return utf8.decode(content);
  } on FormatException catch (error) {
    throw QuestionPackException('$path 不是 UTF-8 文本：${error.message}',
        path: path);
  }
}
