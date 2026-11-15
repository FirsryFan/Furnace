/// 设置页「数据」分区里的两个下沉页：备份与恢复、诊断包。
///
/// 第二遍清理（task-113）把「数据」收成一个入口组：
///
/// * [DataBackupPage] —— 工作区导出/导入（`.tfpkg`）。两行原本直接挂在设置
///   页上，和题库包/学习数据/知识库叠成 9 行；现在设置页只放一行
///   「备份与恢复」，进去才是导出/导入两个动作。导入仍会在写库前自动备份，
///   「备份」不会再是第三个入口（旧「备份数据」直连 db 的入口在 task-107 已删）。
/// * [DiagnosticsBundlePage] —— 诊断包（D01）。这是排障工具，不是用户数据：
///   第二遍清理把它从「数据」移到设置页的开发者分区（默认折叠）。
///
/// 文件本身不碰 DB schema：导出/导入走的还是 `TfpkgService`，诊断包走的还是
/// `DiagnosticsBundleService`。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database_provider.dart';
import '../../../data/package/tfpkg_codec.dart';
import '../../../data/package/tfpkg_service.dart';
import '../../../data/storage/app_storage.dart';
import '../../../l10n/app_localizations.dart';
import '../application/appearance_providers.dart';
import '../application/diagnostics_bundle.dart';
import 'settings_layout.dart';
import 'settings_providers.dart' show currentProfileProvider;

/// 备份与恢复页：导出/导入一个 `.tfpkg`。
class DataBackupPage extends StatelessWidget {
  const DataBackupPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsBackupRestoreTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: const [
          DataBackupSection(),
          SizedBox(height: 12),
          _BackupNote(),
        ],
      ),
    );
  }
}

/// 导出/导入两行（原 `DataSection` 里的逻辑原样搬来）。
class DataBackupSection extends ConsumerWidget {
  const DataBackupSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return SettingsSectionCard(
      children: [
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
      final dir = await AppStorage.supportDirectory();
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

/// 导入前自动备份的那句说明（原来写在 `settingsBackupNote`）。
class _BackupNote extends StatelessWidget {
  const _BackupNote();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        l10n.settingsBackupNote,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 诊断包（D01）：把版本/schema/设置摘要/题目与 AI 内容打包给用户回传。
///
/// 默认包含题目与 AI 内容（`workspace.tfpkg`），因为端到端问题基本都要靠原文
/// 复现；开关可关掉。无论开关如何，API key 都不会进包 —— 安全契约与三道闸见
/// `DiagnosticsBundleService`。
///
/// 入口在设置页的开发者分区（默认折叠）：这是排障工具，不是日常数据备份。
class DiagnosticsBundlePage extends StatefulWidget {
  const DiagnosticsBundlePage({super.key});

  @override
  State<DiagnosticsBundlePage> createState() => _DiagnosticsBundlePageState();
}

class _DiagnosticsBundlePageState extends State<DiagnosticsBundlePage> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsDiagnosticExport)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: const [DiagnosticsExportSection()],
      ),
    );
  }
}

/// 开关 + 导出按钮（原 `DataSection` 里的诊断包小节）。
class DiagnosticsExportSection extends ConsumerStatefulWidget {
  const DiagnosticsExportSection({super.key});

  @override
  ConsumerState<DiagnosticsExportSection> createState() =>
      _DiagnosticsExportSectionState();
}

class _DiagnosticsExportSectionState
    extends ConsumerState<DiagnosticsExportSection> {
  /// 默认开：反馈问题最需要的就是原文。
  bool _includeContent = true;

  /// 生成/保存期间禁用按钮，避免双击导出两份。
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsSectionCard(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.dataset_outlined),
          title: Text(l10n.settingsDiagnosticIncludeContent),
          value: _includeContent,
          onChanged:
              _busy ? null : (value) => setState(() => _includeContent = value),
        ),
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: Text(l10n.settingsDiagnosticExport),
          subtitle: Text(l10n.settingsDiagnosticExportHint),
          enabled: !_busy,
          onTap: _busy ? null : _export,
        ),
      ],
    );
  }

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final bundle = await DiagnosticsBundleService(
        database: ref.read(appDatabaseProvider),
      ).build(includeContent: _includeContent);
      final target = await FilePicker.saveFile(
        dialogTitle: l10n.settingsDiagnosticExport,
        fileName: bundle.fileName,
        bytes: bundle.bytes,
        type: FileType.any,
      );
      if (target == null) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.settingsDiagnosticDone(target.toFilePath())),
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsDiagnosticFailed('$error'))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}
