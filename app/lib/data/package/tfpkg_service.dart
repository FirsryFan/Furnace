import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../domain/package/tfpkg_dump_service.dart';
import '../database/database.dart';
import 'tfpkg_codec.dart';

/// Export/import of the whole workspace as a single `.tfpkg` file
/// (spec §3 / GAP D4).
///
/// Export is a generic logical dump: every user table is read as JSON rather
/// than copying the SQLite file, so the package stays auditable, merges are
/// possible, and a file written by another schema version can still be read.
class TfpkgService implements TfpkgDumpSource {
  TfpkgService(this._db);

  final AppDatabase _db;

  /// Themes are exported as raw JSON documents.
  static const String themesTable = 'themes';

  @override
  Future<TfpkgDump> exportDump({String? appVersion}) async {
    final tables = <String, TableDump>{};
    for (final table in await _db.userTables()) {
      final rows = await _db.dumpTable(table);
      tables[table] = TableDump(rows: rows);
    }
    final themes = <String>[
      for (final row in tables[themesTable]?.rows ?? const <Map<String, dynamic>>[])
        if (row['payload'] is String) row['payload'] as String,
    ];
    return TfpkgDump(
      appName: 'Threadflow',
      appVersion: appVersion,
      exportedAt: DateTime.now(),
      tables: tables,
      themes: themes,
    );
  }

  /// Encodes the current workspace into `.tfpkg` bytes.
  Future<Uint8List> exportBytes({
    String? appVersion,
    List<AttachmentBlob> attachments = const [],
  }) async {
    final dump = await exportDump(appVersion: appVersion);
    return TfpkgCodec.encode(TfpkgDump(
      formatVersion: dump.formatVersion,
      appName: dump.appName,
      appVersion: dump.appVersion,
      exportedAt: dump.exportedAt,
      tables: dump.tables,
      themes: dump.themes,
      attachments: attachments,
    ));
  }

  /// Imports [dump].
  ///
  /// - [TfpkgMergeMode.replace] empties every table in the package first, so
  ///   the workspace ends up exactly as the file describes.
  /// - [TfpkgMergeMode.append] keeps local rows and skips id clashes.
  ///
  /// Foreign keys are switched off for the duration: the package is a set of
  /// tables, not a topologically ordered script, so inserting parents first
  /// cannot be guaranteed.
  Future<TfpkgImportReport> importDump(
    TfpkgDump dump, {
    TfpkgMergeMode mode = TfpkgMergeMode.append,
  }) async {
    final known = (await _db.userTables()).toSet();
    final written = <String, int>{};
    final skipped = <String>[];

    await _db.customStatement('PRAGMA foreign_keys = OFF');
    try {
      await _db.transaction(() async {
        for (final entry in dump.tables.entries) {
          if (!known.contains(entry.key)) {
            // A table this build does not know (exported by a newer version):
            // report it instead of failing the whole import.
            skipped.add(entry.key);
            continue;
          }
          final count = await _db.restoreTable(
            entry.key,
            entry.value.rows,
            mode: mode == TfpkgMergeMode.replace ? 'replace' : 'insert',
          );
          written[entry.key] = count;
        }
      });
    } finally {
      await _db.customStatement('PRAGMA foreign_keys = ON');
    }

    return TfpkgImportReport(
      mode: mode,
      written: written,
      skippedTables: skipped,
    );
  }
}

/// How an import combines with existing data.
enum TfpkgMergeMode {
  /// Replace the local tables with the package content.
  replace,

  /// Keep local rows and add only the ones that do not clash.
  append,
}

/// What an import actually did.
class TfpkgImportReport {
  const TfpkgImportReport({
    required this.mode,
    required this.written,
    required this.skippedTables,
  });

  final TfpkgMergeMode mode;

  /// Rows written per table (append mode counts only the new ones).
  final Map<String, int> written;

  /// Tables present in the file but unknown to this build.
  final List<String> skippedTables;

  int get totalWritten =>
      written.values.fold(0, (sum, value) => sum + value);
}
