/// Reads the `.fskill` zip container.
///
/// `.fskill` is a plain zip, the same approach as `.kpak` and `.tfpkg`
/// (`knowledge_package_codec.dart` / `tfpkg_codec.dart`), because the `archive`
/// package is already a dependency and a package format the user can inspect
/// with any zip tool is easier to trust than an opaque one.
///
/// **This file never writes anything and never runs anything.** It turns bytes
/// into a `(path -> bytes)` map plus a manifest, after refusing the archive
/// shapes that make extraction dangerous:
///
///  * a path that would land outside the package root (zip-slip: absolute
///    paths, `..` components, and the backslash form of the same thing);
///  * a declared uncompressed size or entry count beyond the caps, checked
///    from the zip headers **before** any entry is decompressed, so a package
///    that claims to expand to gigabytes costs nothing to reject.
///
/// Integrity is deliberately *not* claimed: there is no signature and no hash
/// to verify against, so the honest statement is "you trust the file you
/// installed". A CRC mismatch is reported because the zip carries one, but
/// that only detects corruption, not tampering.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../domain/skill/skill_manifest.dart';

/// One file taken out of a `.fskill`, with its package-relative POSIX path.
class SkillArchiveEntry {
  const SkillArchiveEntry({required this.path, required this.bytes});

  /// POSIX-separated path with no leading slash, e.g. `scripts/find.mjs`.
  final String path;

  final Uint8List bytes;

  String get text => utf8.decode(bytes);
}

/// The container limits. Both are checked against the zip's declared sizes.
abstract final class SkillArchiveLimits {
  /// Total uncompressed size of the whole package. Chosen to fit a realistic
  /// scripted skill (`zujuan-finder`-style references plus Node scripts) with
  /// a wide margin, while staying far below anything that would exhaust memory
  /// when the whole package is held at once.
  static const int maxTotalUncompressedBytes = 32 * 1024 * 1024;

  /// The same cap spelled out for a message the user reads, kept as its own
  /// constant so the refusal text and the enforced number cannot drift apart.
  static const String maxTotalUncompressedLabel = '32 MB';

  /// Entries per package. A skill is documents plus a handful of scripts; two
  /// thousand entries already means something other than a skill.
  static const int maxEntries = 2000;
}
/// The one reason a `.fskill` was refused, as a stable code plus a message the
/// settings screen can show verbatim.
class SkillArchiveException implements Exception {
  const SkillArchiveException(this.code, this.message);

  /// Stable identifier, used by tests to assert the *reason* rather than just
  /// "it threw".
  final String code;

  /// User-facing explanation.
  final String message;

  @override
  String toString() => message;
}

/// Decodes `.fskill` bytes.
abstract final class SkillPackageCodec {
  static const String manifestFileName = 'manifest.json';
  static const String promptFileName = 'prompt.md';
  static const String toolsPrefix = 'tools/';
  static const String scriptsPrefix = 'scripts/';

  /// Reads the archive.
  ///
  /// Throws [SkillArchiveException] with code:
  ///  * `notZip` - the bytes are not a readable zip;
  ///  * `tooManyEntries` - more than [SkillArchiveLimits.maxEntries] entries;
  ///  * `unsafeEntryPath` - an absolute path, a `..` component, or a
  ///    backslash-separated traversal;
  ///  * `symlinkEntry` - a symbolic link entry, which is a path escape wearing
  ///    a different hat;
  ///  * `entryTooLarge` / `packageTooLarge` - the declared uncompressed size
  ///    exceeds a cap (zip bomb).
  static ({
    Map<String, SkillArchiveEntry> entries,
    List<SkillArchiveEntry> files,
  }) read(Uint8List bytes) {
    final Archive archive;
    try {
      // `decodeBytes` reads the directory and constructs the entries; it does
      // not inflate them. Decompression happens in `entry.content`, which is
      // why every cap below can be enforced on declared sizes first.
      archive = ZipDecoder().decodeBytes(bytes);
    } on ArchiveException catch (e) {
      throw SkillArchiveException('notZip', '不是有效的 .fskill（zip 无法读取）：$e');
    } on RangeError catch (e) {
      throw SkillArchiveException('notZip', '不是有效的 .fskill（zip 数据不完整）：$e');
    }

    // Only regular files matter; directory markers are recreated from the
    // paths when the package is extracted.
    final files = [
      for (final file in archive.files)
        if (file.isFile && file.name.trim().isNotEmpty) file,
    ];

    if (files.length > SkillArchiveLimits.maxEntries) {
      throw SkillArchiveException(
        'tooManyEntries',
        'skill 包内条目过多（${files.length} > '
        '${SkillArchiveLimits.maxEntries}），已拒绝解包',
      );
    }

    final entries = <String, SkillArchiveEntry>{};
    for (final file in files) {
      if (file.isSymbolicLink) {
        throw SkillArchiveException(
          'symlinkEntry',
          'skill 包含符号链接「${file.name}」，这可以指向包外路径，已拒绝',
        );
      }
      final path = _safeEntryPath(file.name);
      final declared = file.size;
      if (declared > SkillArchiveLimits.maxTotalUncompressedBytes) {
        throw SkillArchiveException(
          'entryTooLarge',
          'skill 内文件「$path」解压后约 $declared 字节，超过单文件上限'
          '（${SkillArchiveLimits.maxTotalUncompressedBytes} 字节），已拒绝解包',
        );
      }
      entries[path] = SkillArchiveEntry(
        path: path,
        bytes: Uint8List.fromList(file.content as List<int>),
      );
    }

    return (entries: entries, files: entries.values.toList());
  }

  /// The manifest inside [entries], or null when `manifest.json` is absent.
  ///
  /// Only *decoding* lives here. Whether the protocol number and the name are
  /// acceptable is the validator's decision, so there is exactly one place that
  /// answers "why was this refused".
  static SkillManifest? readManifest(Map<String, SkillArchiveEntry> entries) {
    final file = entries[manifestFileName];
    if (file == null) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(file.text);
    } on FormatException catch (e) {
      throw SkillArchiveException(
        'invalidManifestJson',
        '$manifestFileName 不是合法 JSON：${e.message}',
      );
    }
    if (decoded is! Map) {
      throw const SkillArchiveException(
        'invalidManifestJson',
        'manifest.json 必须是一个 JSON 对象',
      );
    }
    // JSON objects always decode with string keys, so this cast cannot fail
    // for a file that came from `jsonDecode`; it is here to keep the type
    // system honest about `SkillManifest.fromJson`'s parameter.
    final map = decoded.cast<String, dynamic>();
    try {
      return SkillManifest.fromJson(map);
    } on FormatException catch (e) {
      throw SkillArchiveException('invalidManifest', e.message);
    }
  }
  /// The prompt text, or null when `prompt.md` is absent.
  static String? readPrompt(Map<String, SkillArchiveEntry> entries) =>
      entries[promptFileName]?.text;

  /// Every `tools/*.json` declaration, keyed by package path.
  ///
  /// The JSON is parsed here but *not* validated; the validator turns a bad
  /// declaration into a refusal with the file name in the message.
  static Map<String, Map<String, dynamic>?> readToolDeclarations(
    Map<String, SkillArchiveEntry> entries,
  ) {
    final declared = <String, Map<String, dynamic>?>{};
    for (final path in entries.keys) {
      if (!path.startsWith(toolsPrefix) || !path.endsWith('.json')) {
        continue;
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(entries[path]!.text);
      } on FormatException {
        declared[path] = null;
        continue;
      }
      declared[path] = decoded is Map ? decoded.cast<String, dynamic>() : null;
    }
    return declared;
  }

  /// Rejects anything that could resolve outside the package root.
  ///
  /// `archive` normalises `\` to `/` when it builds an entry name, so the
  /// backslash form of a traversal arrives here already looking like `../..`,
  /// and the `..` check catches it. The explicit backslash replacement remains
  /// as a second line of defence in case that normalisation ever changes - the
  /// cost of being wrong here is a write outside the skill directory.
  static String _safeEntryPath(String raw) {
    var path = raw.replaceAll('\\', '/');
    while (path.startsWith('./')) {
      path = path.substring(2);
    }
    if (path.isEmpty) {
      throw const SkillArchiveException(
        'unsafeEntryPath',
        'skill 包含空文件名条目，已拒绝',
      );
    }
    if (path.startsWith('/')) {
      throw SkillArchiveException(
        'unsafeEntryPath',
        'skill 包含绝对路径条目「$raw」，已拒绝',
      );
    }
    final segments = path.split('/');
    if (segments.contains('..')) {
      throw SkillArchiveException(
        'unsafeEntryPath',
        'skill 包含跳出包目录的路径「$raw」，已拒绝',
      );
    }
    if (segments.first.contains(':')) {
      // Only a Windows drive designator (`C:`) can put a colon in the *first*
      // segment of a relative path, and `C:foo` is drive-relative on Windows -
      // it resolves against that drive's current directory, which is outside
      // the package. A colon deeper in the path is just an odd file name.
      throw SkillArchiveException(
        'unsafeEntryPath',
        'skill 包含盘符路径条目「$raw」，已拒绝',
      );
    }
    return segments.where((segment) => segment.isNotEmpty).join('/');
  }
}
