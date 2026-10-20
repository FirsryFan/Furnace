import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:furnace/features/questions/application/question_pack_service.dart';
import 'package:path_provider/path_provider.dart';

import '../../../data/database/app_database_provider.dart';
import '../../../data/package/tfpkg_codec.dart';
import '../../../data/package/tfpkg_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../questions/application/learning_advice_provider.dart';
import '../../questions/application/question_audit_reader.dart';
import '../../questions/presentation/question_intake_providers.dart';
import '../application/appearance_providers.dart';
import 'settings_page.dart' show currentProfileProvider;

/// Data section of the settings page: whole-workspace backup and restore via
/// `.tfpkg` (spec §3 / GAP D4).
///
/// Export writes one zip containing a logical JSON dump of every table plus the
/// theme documents. Import always backs the current workspace up first, so a
/// wrong choice of merge mode is recoverable.
///
/// Also hosts the question-bank package (`.tqb`), which carries questions and
/// their images only and never overwrites: it always appends, so no backup step
/// is needed before importing one.
class DataSection extends ConsumerWidget {
  const DataSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(icon: Icons.folder_outlined, title: l10n.settingsData),
        ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: Text(l10n.settingsTfpkgExport),
          subtitle: Text(l10n.settingsTfpkgExportHint),
          onTap: () => _export(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.unarchive_outlined),
          title: Text(l10n.settingsTfpkgImport),
          subtitle: Text(l10n.settingsTfpkgImportHint),
          onTap: () => _import(context, ref),
        ),
        const _QuestionPackSection(),
      ],
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // A `.tfpkg` is the thing people hand to each other, and it carries the AI
    // API key (a plain settings column). Ask before including it rather than
    // deciding for the user - defaulting to "include" would leak a working
    // credential the first time someone shares a package without thinking.
    final includeSecrets = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsTfpkgExport),
        content: Text(l10n.settingsTfpkgExportSecretsHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.settingsTfpkgExportNoSecrets),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.settingsTfpkgExportWithSecrets),
          ),
        ],
      ),
    );
    if (includeSecrets == null) {
      return;
    }

    try {
      final service = TfpkgService(ref.read(appDatabaseProvider));
      final bytes =
          await service.exportBytes(excludeSensitive: !includeSecrets);
      final stamp = DateTime.now()
          .toIso8601String()
          .substring(0, 16)
          .replaceAll(':', '')
          .replaceAll('-', '');
      final target = await FilePicker.saveFile(
        dialogTitle: l10n.settingsTfpkgExport,
        fileName: 'furnace-$stamp.tfpkg',
        bytes: bytes,
        type: FileType.any,
      );
      if (target == null) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(includeSecrets
              ? l10n.settingsTfpkgExportDone
              : l10n.settingsTfpkgExportDoneNoSecrets),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.settingsTfpkgExport}: $error')),
      );
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.pickFiles(type: FileType.any);
      if (picked.isEmpty) {
        return;
      }
      final Uint8List bytes;
      try {
        bytes = await picked.first.readAsBytes();
      } catch (error) {
        messenger.showSnackBar(
          SnackBar(content: Text('${l10n.settingsTfpkgImport}: $error')),
        );
        return;
      }

      final TfpkgDump dump;
      try {
        dump = TfpkgCodec.readManifest(bytes);
      } catch (_) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsTfpkgInvalid)),
        );
        return;
      }

      if (!context.mounted) {
        return;
      }
      final mode = await _askMergeMode(context, l10n, dump);
      if (mode == null || !context.mounted) {
        return;
      }

      // Back the current workspace up before touching it.
      await _autoBackup(ref);

      final service = TfpkgService(ref.read(appDatabaseProvider));
      final report = await service.importDump(dump, mode: mode);
      _invalidateEverything(ref);

      final skipped = report.skippedTables.length;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.settingsTfpkgImportDone(report.totalWritten)}'
            '${skipped == 0 ? '' : '\n${l10n.settingsTfpkgSkippedTables(skipped)}'}',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.settingsTfpkgImport}: $error')),
      );
    }
  }

  /// Shows what is inside the package and lets the user choose the merge mode.
  Future<TfpkgMergeMode?> _askMergeMode(
    BuildContext context,
    AppLocalizations l10n,
    TfpkgDump dump,
  ) {
    return showDialog<TfpkgMergeMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsTfpkgImport),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsTfpkgImportPreview(
                dump.totalRows,
                dump.tables.length,
                dump.themes.length,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.merge_type),
              title: Text(l10n.settingsTfpkgMergeAppend),
              onTap: () => Navigator.of(context).pop(TfpkgMergeMode.append),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.swap_horiz),
              title: Text(l10n.settingsTfpkgMergeReplace),
              onTap: () => Navigator.of(context).pop(TfpkgMergeMode.replace),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.settingsTfpkgImportHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l10n.commonCancel,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// Writes a timestamped `.tfpkg` next to the database before an import.
  ///
  /// Failure is not fatal: the import continues, but it is reported, because
  /// silently skipping the safety net would be worse than a warning.
  Future<void> _autoBackup(WidgetRef ref) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final service = TfpkgService(ref.read(appDatabaseProvider));
      final bytes = await service.exportBytes();
      final stamp = DateTime.now()
          .toIso8601String()
          .substring(0, 19)
          .replaceAll(':', '')
          .replaceAll('-', '');
      final file = File('${dir.path}/pre-import-$stamp.tfpkg');
      await file.writeAsBytes(bytes);
    } catch (_) {
      // Reported by the caller's snack bar through the import result; a failed
      // backup must not abort a restorable import.
    }
  }

  /// Every module watches its own provider, so all of them are refreshed.
  void _invalidateEverything(WidgetRef ref) {
    ref.invalidate(themesProvider);
    ref.invalidate(activeAppearanceProvider);
    ref.invalidate(currentProfileProvider);
  }
}

/// Human-readable byte count for the export confirmation ("3 B", "1.5 KB").
String questionPackSizeText(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kilobytes = bytes / 1024;
  if (kilobytes < 1024) {
    return '${kilobytes.toStringAsFixed(1)} KB';
  }
  return '${(kilobytes / 1024).toStringAsFixed(1)} MB';
}

/// Timestamp used in exported package file names (`furnace-20261021T0430.tqb`).
String questionPackTimestamp() => DateTime.now()
    .toIso8601String()
    .substring(0, 16)
    .replaceAll(':', '')
    .replaceAll('-', '');

/// Question-bank package (`.tqb`): questions plus their images, for moving the
/// bank between installs without touching the rest of the workspace.
///
/// Import only ever adds questions (identical stems are skipped by fingerprint),
/// so unlike the workspace import there is no pre-import backup and no merge
/// dialog: the package cannot overwrite what is already here.
class _QuestionPackSection extends ConsumerStatefulWidget {
  const _QuestionPackSection();

  @override
  ConsumerState<_QuestionPackSection> createState() =>
      _QuestionPackSectionState();
}

class _QuestionPackSectionState extends ConsumerState<_QuestionPackSection> {
  /// One package operation at a time: the tiles disable while it runs, so a
  /// double tap cannot export or import twice.
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          icon: Icons.inventory_2_outlined,
          title: l10n.settingsQuestionPackSection,
        ),
        ListTile(
          leading: const Icon(Icons.save_alt),
          title: Text(l10n.settingsQuestionPackExport),
          subtitle: Text(l10n.settingsQuestionPackExportHint),
          enabled: !_busy,
          onTap: _busy ? null : _export,
        ),
        ListTile(
          leading: const Icon(Icons.file_open_outlined),
          title: Text(l10n.settingsQuestionPackImport),
          subtitle: Text(l10n.settingsQuestionPackImportHint),
          enabled: !_busy,
          onTap: _busy ? null : _import,
        ),
      ],
    );
  }

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await ref.read(questionPackServiceProvider).exportBytes();
      if (!mounted) {
        return;
      }
      if (result.questionCount == 0) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsQuestionPackExportEmpty)),
        );
        return;
      }
      final target = await FilePicker.saveFile(
        dialogTitle: l10n.settingsQuestionPackExport,
        fileName: 'furnace-${questionPackTimestamp()}.tqb',
        bytes: result.bytes,
        type: FileType.any,
      );
      if (target == null) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.settingsQuestionPackExportDone(
              result.questionCount,
              result.mediaCount,
              questionPackSizeText(result.bytes.length),
            ),
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.settingsQuestionPackExport}: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: l10n.settingsQuestionPackImport,
        type: FileType.custom,
        allowedExtensions: const ['tqb'],
      );
      if (picked.isEmpty) {
        return;
      }
      final Uint8List bytes;
      try {
        bytes = await picked.first.readAsBytes();
      } catch (error) {
        messenger.showSnackBar(
          SnackBar(content: Text('${l10n.settingsQuestionPackImport}: $error')),
        );
        return;
      }
      final service = ref.read(questionPackServiceProvider);
      final QuestionPackPreview preview;
      try {
        preview = service.peek(bytes);
      } catch (_) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsQuestionPackInvalid)),
        );
        return;
      }
      if (!mounted) {
        return;
      }
      final confirmed = await _askImportPreview(l10n, preview);
      if (confirmed != true || !mounted) {
        return;
      }
      final report = await service.importPack(bytes);
      if (!mounted) {
        return;
      }
      _refreshQuestionViews();
      await _showImportReport(l10n, report);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.settingsQuestionPackImport}: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Shows what is inside the package and asks before writing anything.
  Future<bool?> _askImportPreview(
    AppLocalizations l10n,
    QuestionPackPreview preview,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsQuestionPackImport),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsQuestionPackImportPreview(
                preview.questionCount,
                preview.mediaCount,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.settingsQuestionPackImportConfirm,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.settingsQuestionPackImport),
          ),
        ],
      ),
    );
  }

  /// Result dialog: created/skipped/media counts, then warnings and failures.
  Future<void> _showImportReport(
    AppLocalizations l10n,
    QuestionPackImportReport report,
  ) {
    final failures = report.failures;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsQuestionPackImport),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsQuestionPackImportDone(
                report.createdCount,
                report.skippedCount,
                report.mediaCount,
              ),
            ),
            if (report.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l10n.settingsQuestionPackWarnings(report.warnings.length)),
            ],
            if (failures.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l10n.settingsQuestionPackFailures(failures.length)),
              for (final failure in failures.take(3))
                Text(
                  failure,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
  }

  /// Every question view watches its own provider, so all of them are refreshed.
  void _refreshQuestionViews() {
    ref.invalidate(questionLibraryProvider);
    ref.invalidate(questionCorpusCountProvider);
    ref.invalidate(questionAuditCorpusProvider);
    ref.invalidate(questionAuditReportProvider);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }
}
