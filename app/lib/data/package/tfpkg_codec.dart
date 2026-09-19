import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// One table's rows, keyed by column name.
class TableDump {
  const TableDump({required this.rows});

  final List<Map<String, dynamic>> rows;

  int get length => rows.length;

  Map<String, dynamic> toJson() => {'rows': rows};

  factory TableDump.fromJson(Map<String, dynamic> json) => TableDump(
        rows: [
          for (final row in (json['rows'] as List<dynamic>? ?? const []))
            Map<String, dynamic>.from(row as Map),
        ],
      );
}

/// A file carried inside the package (background images, fonts, ...).
class AttachmentBlob {
  const AttachmentBlob({required this.path, required this.bytes});

  /// Path inside the package, e.g. `attachments/themes/bg.png`.
  final String path;
  final Uint8List bytes;
}

/// The logical content of a `.tfpkg`: a JSON dump of every business table plus
/// optional attachments and theme snapshots.
///
/// A generic JSON dump (rather than copying the SQLite file) is deliberate:
/// merges can be implemented per entity, the content stays auditable, and a
/// package exported by a different schema version can still be read.
class TfpkgDump {
  const TfpkgDump({
    this.formatVersion = 1,
    this.appName = 'Threadflow',
    this.appVersion,
    this.exportedAt,
    this.tables = const {},
    this.themes = const [],
    this.attachments = const [],
  });

  final int formatVersion;
  final String appName;
  final String? appVersion;
  final DateTime? exportedAt;

  /// Table name -> rows. Insertion order is not significant.
  final Map<String, TableDump> tables;

  /// Raw theme documents (JSON strings), so themes travel with the workspace.
  final List<String> themes;

  final List<AttachmentBlob> attachments;

  int get totalRows =>
      tables.values.fold(0, (sum, table) => sum + table.length);

  Map<String, int> get counts => {
        for (final entry in tables.entries) entry.key: entry.value.length,
      };

  /// The manifest JSON that goes into `manifest.json` (without attachments).
  Map<String, dynamic> toManifestJson() => {
        'formatVersion': formatVersion,
        'appName': appName,
        if (appVersion != null) 'appVersion': appVersion,
        'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
        'counts': counts,
        'totalRows': totalRows,
        'tables': {
          for (final entry in tables.entries) entry.key: entry.value.toJson(),
        },
        'themes': themes,
      };

  static TfpkgDump fromManifestJson(Map<String, dynamic> json) {
    final rawTables = (json['tables'] as Map<String, dynamic>?) ?? const {};
    return TfpkgDump(
      formatVersion: (json['formatVersion'] as num?)?.toInt() ?? 1,
      appName: json['appName'] as String? ?? 'Threadflow',
      appVersion: json['appVersion'] as String?,
      exportedAt: DateTime.tryParse(json['exportedAt'] as String? ?? ''),
      tables: {
        for (final entry in rawTables.entries)
          entry.key: TableDump.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          ),
      },
      themes: [
        for (final theme in (json['themes'] as List<dynamic>? ?? const []))
          theme as String,
      ],
    );
  }
}

/// Reads and writes the `.tfpkg` container.
///
/// Layout inside the zip:
///   manifest.json      - format version + every table's rows + theme docs
///   attachments/*      - binary files (background images, imported fonts)
class TfpkgCodec {
  static const String manifestFileName = 'manifest.json';
  static const String attachmentPrefix = 'attachments/';

  static Uint8List encode(TfpkgDump dump) {
    final manifestJson = jsonEncode(dump.toManifestJson());
    final manifestBytes = utf8.encode(manifestJson);
    final archive = Archive()
      ..addFile(ArchiveFile(manifestFileName, manifestBytes.length, manifestBytes));
    for (final attachment in dump.attachments) {
      archive.addFile(
        ArchiveFile(
          attachment.path,
          attachment.bytes.length,
          attachment.bytes,
        ),
      );
    }
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  /// Decodes a package. Attachment bytes are returned separately so a caller
  /// that only wants the logical dump does not have to hold them.
  static ({TfpkgDump dump, List<AttachmentBlob> attachments}) decode(
    Uint8List bytes,
  ) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifestFile = archive.findFile(manifestFileName);
    if (manifestFile == null) {
      throw const FormatException('不是有效的 .tfpkg：缺少 manifest.json');
    }
    final manifestJson = utf8.decode(manifestFile.content as List<int>);
    final decoded = jsonDecode(manifestJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('不是有效的 .tfpkg：manifest.json 必须是对象');
    }
    final attachments = <AttachmentBlob>[];
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      if (file.name == manifestFileName) {
        continue;
      }
      attachments.add(AttachmentBlob(
        path: file.name,
        bytes: Uint8List.fromList(file.content as List<int>),
      ));
    }
    return (dump: TfpkgDump.fromManifestJson(decoded), attachments: attachments);
  }

  /// Just the manifest, for a preview before importing.
  static TfpkgDump readManifest(Uint8List bytes) => decode(bytes).dump;

  /// File names inside the package, without decoding attachments twice.
  static List<String> listEntries(Uint8List bytes) => [
        for (final file in ZipDecoder().decodeBytes(bytes).files)
          if (file.isFile) file.name,
      ];
}
