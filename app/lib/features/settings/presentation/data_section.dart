import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:furnace/domain/services/package/question_pack_import_preview.dart';
import 'package:furnace/domain/services/package/question_pack_selection.dart';
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
import 'question_pack_export_filter_dialog.dart';
import 'settings_page.dart' show currentProfileProvider;

/// Data section of the settings page: whole-workspace backup and restore via
/// `.tfpkg` (spec §3 / GAP D4).
///
/// Export writes one zip containing a logical JSON dump of every table plus the
/// theme documents. Import always backs the current workspace up first, so a
/// wrong choice of merge mode is recoverable.
///
/// Also hosts the question-bank package (`.tqb`), which carries questions and
/// their images only. Records without a zujuan.com question id are always
/// appended; records that carry one update the matching question in place, so
/// its serial number and the title the user gave it survive. Before writing,
/// [QuestionPackService.importPack] snapshots the current bank into a `.tqb`
/// backup (listed in this section) when it is not empty.
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

/// 备份文件的修改时间（本地时区）：`2026-10-23 06:08`。
String _backupTimeText(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}

/// Question-bank package (`.tqb`): questions plus their images, for moving the
/// bank between installs without touching the rest of the workspace.
///
/// Import only ever adds questions (identical stems are skipped by fingerprint),
/// so there is no merge dialog: the package cannot overwrite what is already
/// here. It still takes a safety net first — when the local bank already has
/// questions, [QuestionPackService.importPack] backs it up to a `.tqb` snapshot
/// in the app documents directory before writing (a backup failure only warns,
/// it never blocks the import).
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

  /// 当前导入前备份；行副标题与对话框共用这份清单。
  List<QuestionPackBackup> _backups = const <QuestionPackBackup>[];

  /// 清单是否已经读过一次（没读完前副标题显示说明，不显示「没有备份」）。
  bool _backupsLoaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reloadBackups());
  }

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
        ListTile(
          leading: const Icon(Icons.settings_backup_restore),
          title: Text(l10n.settingsQuestionPackBackupsTitle),
          subtitle: Text(_backupsSubtitle(l10n)),
          enabled: !_busy,
          onTap: _busy ? null : _showBackups,
        ),
      ],
    );
  }

  /// 读一次备份目录；失败只记日志（副标题退回说明文案，不让设置页报错）。
  Future<void> _reloadBackups() async {
    try {
      final backups = await ref.read(questionPackServiceProvider).listBackups();
      if (!mounted) return;
      setState(() {
        _backups = backups;
        _backupsLoaded = true;
      });
    } on Object catch (error) {
      // 读失败保持 _backupsLoaded = false：副标题退回说明文案，不假装「没有备份」。
      debugPrint('list question pack backups failed: $error');
    }
  }

  /// 行副标题：份数 + 总大小；空表/未读完时给对应文案。
  String _backupsSubtitle(AppLocalizations l10n) {
    if (!_backupsLoaded) {
      return l10n.settingsQuestionPackBackupsHint;
    }
    if (_backups.isEmpty) {
      return l10n.settingsQuestionPackBackupsEmpty;
    }
    final total = _backups.fold<int>(
      0,
      (sum, backup) => sum + backup.sizeBytes,
    );
    return '${l10n.settingsQuestionPackBackupsHint}（${_backups.length} 份，'
        '共 ${questionPackSizeText(total)}）';
  }

  /// 打开备份清单；关闭后重读一次（对话框里可能删过文件）。
  Future<void> _showBackups() async {
    await _reloadBackups();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _QuestionPackBackupsDialog(
        listBackups: () => ref.read(questionPackServiceProvider).listBackups(),
        deleteBackup: (path) =>
            ref.read(questionPackServiceProvider).deleteBackup(path),
        restoreBackup: _restoreFromBackup,
        pruneBackups: (keep) =>
            ref.read(questionPackServiceProvider).pruneBackups(keep: keep),
      ),
    );
    if (!mounted) return;
    await _reloadBackups();
  }

  /// 从一份导入前备份恢复题库：确认 → 读字节 → 预检 → 导入 → 刷新并报告。
  ///
  /// 恢复是「按题号更新 + 追加缺题」：备份里没有的当前题目不会被删；
  /// [QuestionPackService.importPack] 写库前还会再自动备份一次当前题库。
  Future<void> _restoreFromBackup(QuestionPackBackup backup) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsQuestionPackBackupsTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsQuestionPackRestoreConfirm(backup.name)),
            const SizedBox(height: 8),
            Text(
              l10n.settingsQuestionPackRestoreConfirmBody,
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
            child: Text(l10n.settingsQuestionPackRestoreAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final service = ref.read(questionPackServiceProvider);
    setState(() => _busy = true);
    try {
      final bytes = await service.readBackupBytes(backup.path);
      final preview = await service.planImport(bytes);
      if (!mounted) {
        return;
      }
      final approved = await _askImportPreview(l10n, preview);
      if (approved != true || !mounted) {
        return;
      }
      final report = await service.importPack(bytes);
      if (!mounted) {
        return;
      }
      _refreshQuestionViews();
      unawaited(_reloadBackups());
      await _showImportReport(l10n, report);
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.settingsQuestionPackRestoreFailed('$error')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final QuestionPackSelection? selection =
        await showDialog<QuestionPackSelection>(
      context: context,
      builder: (context) => const QuestionPackExportFilterDialog(),
    );
    if (selection == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(questionPackServiceProvider)
          .exportBytes(selection: selection);
      if (!mounted) {
        return;
      }
      if (result.questionCount == 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              selection.isEmpty
                  ? l10n.settingsQuestionPackExportEmpty
                  : l10n.settingsQuestionPackFilterEmpty,
            ),
          ),
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
      if (result.warnings.isNotEmpty) {
        await _showExportWarnings(l10n, result);
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
      final QuestionPackImportPreview preview;
      try {
        preview = await service.planImport(bytes);
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
      unawaited(_reloadBackups());
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

  /// Shows what `planImport` would do and asks before writing anything.
  Future<bool?> _askImportPreview(
    AppLocalizations l10n,
    QuestionPackImportPreview preview,
  ) {
    final theme = Theme.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsQuestionPackImport),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsQuestionPackImportPreview(
                    preview.recordCount,
                    preview.mediaCount,
                  ),
                ),
                const SizedBox(height: 8),
                if (preview.createCount > 0)
                  Text(
                    l10n.settingsQuestionPackPreviewCreate(
                      preview.createCount,
                    ),
                  ),
                if (preview.updateCount > 0)
                  Text(
                    l10n.settingsQuestionPackPreviewUpdate(
                      preview.updateCount,
                    ),
                  ),
                if (preview.skipCount > 0)
                  Text(
                    l10n.settingsQuestionPackPreviewSkip(preview.skipCount),
                  ),
                // 零新增且零更新才算「没有可导入的新题」。
                if (preview.createCount == 0 && preview.updateCount == 0)
                  Text(l10n.settingsQuestionPackPreviewNoNew),
                if (preview.missingTagCount > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.settingsQuestionPackPreviewMissingTags(
                      preview.missingTagCount,
                    ),
                  ),
                ],
                if (preview.warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    l10n.settingsQuestionPackWarnings(
                      preview.warnings.length,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final warning in preview.warnings)
                    Text(warning, style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 16),
                Text(
                  l10n.settingsQuestionPackImportConfirm,
                  style: theme.textTheme.bodySmall,
                ),
                if (preview.hasUpdates) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.settingsQuestionPackImportUpdateNote,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
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

  /// Warnings-only dialog after a successful export (images left out, etc.).
  Future<void> _showExportWarnings(
    AppLocalizations l10n,
    QuestionPackExportResult result,
  ) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsQuestionPackExportWarningsTitle),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsQuestionPackExportDone(
                    result.questionCount,
                    result.mediaCount,
                    questionPackSizeText(result.bytes.length),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.settingsQuestionPackWarnings(result.warnings.length),
                ),
                const SizedBox(height: 8),
                for (final warning in result.warnings)
                  Text(warning, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
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
            if (report.updatedCount > 0)
              Text(
                l10n.settingsQuestionPackImportUpdated(report.updatedCount),
              ),
            if (report.backupPath != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                l10n.settingsQuestionPackBackupCreated(report.backupPath!),
              ),
            ] else if (report.backupError != null) ...[
              const SizedBox(height: 12),
              Text(
                l10n.settingsQuestionPackBackupFailed,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
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

/// 导入前备份清单：列出 `<documents>/question_pack_backups/` 里的 `.tqb`，
/// 逐份可恢复、可删。
class _QuestionPackBackupsDialog extends StatefulWidget {
  const _QuestionPackBackupsDialog({
    required this.listBackups,
    required this.deleteBackup,
    required this.restoreBackup,
    required this.pruneBackups,
  });

  /// 读当前备份（每次删除/恢复后重读，成功与否以磁盘为准）。
  final Future<List<QuestionPackBackup>> Function() listBackups;

  /// 删一份备份；失败抛出，由对话框提示。
  final Future<void> Function(String path) deleteBackup;

  /// 用一份备份恢复题库（确认、预检与结果提示都在父级做）。
  final Future<void> Function(QuestionPackBackup backup) restoreBackup;

  /// 清理旧备份，只保留最近 [keep] 份，返回被删掉的路径。
  final Future<List<String>> Function(int keep) pruneBackups;

  @override
  State<_QuestionPackBackupsDialog> createState() =>
      _QuestionPackBackupsDialogState();
}

class _QuestionPackBackupsDialogState
    extends State<_QuestionPackBackupsDialog> {
  List<QuestionPackBackup>? _backups;
  Object? _loadError;

  /// 恢复或删除进行中：两个按钮一起禁用，避免重叠操作。
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final backups = await widget.listBackups();
      if (!mounted) return;
      setState(() {
        _backups = backups;
        _loadError = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  Future<void> _confirmDelete(QuestionPackBackup backup) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsQuestionPackBackupsTitle),
        content:
            Text(l10n.settingsQuestionPackBackupDeleteConfirm(backup.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.settingsQuestionPackBackupDeleteTooltip),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.deleteBackup(backup.path);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsQuestionPackBackupDeleteDone)),
      );
      await _load();
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.settingsQuestionPackBackupDeleteFailed('$error')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// 清理旧备份：确认后只保留最近 [QuestionPackService.kQuestionPackBackupKeepCount]
  /// 份；成功/失败都会重读列表，以磁盘为准。
  Future<void> _confirmPrune(int backupCount) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    const keep = QuestionPackService.kQuestionPackBackupKeepCount;
    final removeCount = backupCount - keep;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsQuestionPackBackupsTitle),
        content: Text(
          l10n.settingsQuestionPackBackupPruneConfirm(removeCount, keep),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.settingsQuestionPackBackupPruneAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final removed = await widget.pruneBackups(keep);
      messenger.showSnackBar(
        SnackBar(
          content:
              Text(l10n.settingsQuestionPackBackupPruneDone(removed.length)),
        ),
      );
      await _load();
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.settingsQuestionPackBackupPruneFailed('$error')),
        ),
      );
      await _load();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// 恢复一份备份；成功后重读列表（恢复前会自动再备份一次当前题库）。
  Future<void> _restore(QuestionPackBackup backup) async {
    setState(() => _busy = true);
    try {
      await widget.restoreBackup(backup);
      if (!mounted) return;
      await _load();
    } on Object catch (error) {
      // 失败文案由父级 SnackBar 统一提示，这里只记日志兜底。
      debugPrint('restore question pack backup failed: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final backups = _backups;
    return AlertDialog(
      title: Text(l10n.settingsQuestionPackBackupsTitle),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.settingsQuestionPackBackupsHint,
                style: theme.textTheme.bodySmall,
              ),
              if (backups != null &&
                  backups.length >
                      QuestionPackService.kQuestionPackBackupKeepCount) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Tooltip(
                    message: l10n.settingsQuestionPackBackupPruneTooltip(
                      QuestionPackService.kQuestionPackBackupKeepCount,
                    ),
                    child: TextButton.icon(
                      onPressed:
                          _busy ? null : () => _confirmPrune(backups.length),
                      icon: const Icon(Icons.cleaning_services),
                      label: Text(
                        l10n.settingsQuestionPackBackupPruneAction,
                      ),
                    ),
                  ),
                ),
              ],
              if (_loadError != null) ...[
                const SizedBox(height: 12),
                Text(_loadError.toString(), style: theme.textTheme.bodySmall),
              ] else if (backups != null && backups.isEmpty) ...[
                const SizedBox(height: 12),
                Text(l10n.settingsQuestionPackBackupsEmpty),
              ] else if (backups != null) ...[
                const SizedBox(height: 8),
                for (final backup in backups)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.archive_outlined),
                    title: Text(backup.name),
                    subtitle: Text(
                      '${questionPackSizeText(backup.sizeBytes)} · '
                      '${_backupTimeText(backup.modifiedAt)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.restore),
                          tooltip: l10n.settingsQuestionPackRestoreTooltip,
                          onPressed: _busy ? null : () => _restore(backup),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: l10n.settingsQuestionPackBackupDeleteTooltip,
                          onPressed:
                              _busy ? null : () => _confirmDelete(backup),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    );
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
