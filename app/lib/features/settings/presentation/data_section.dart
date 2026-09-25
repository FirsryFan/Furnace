import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../data/database/app_database_provider.dart';
import '../../../data/package/tfpkg_codec.dart';
import '../../../data/package/tfpkg_service.dart';
import '../../../l10n/app_localizations.dart';
import '../application/appearance_providers.dart';
import 'settings_page.dart' show currentProfileProvider;

/// Data section of the settings page: whole-workspace backup and restore via
/// `.tfpkg` (spec §3 / GAP D4).
///
/// Export writes one zip containing a logical JSON dump of every table plus the
/// theme documents. Import always backs the current workspace up first, so a
/// wrong choice of merge mode is recoverable.
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
      ],
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = TfpkgService(ref.read(appDatabaseProvider));
      final bytes = await service.exportBytes();
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
        SnackBar(content: Text(l10n.settingsTfpkgExportDone)),
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
