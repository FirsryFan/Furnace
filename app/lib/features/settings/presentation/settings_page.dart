import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:knowflow/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/settings/settings_controller.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../tags/presentation/tag_tree_page.dart';
import '../../thread/application/thread_rank_service.dart';
import '../../timeboard/presentation/calendar_page.dart';
import '../../timeboard/presentation/time_board_page.dart';
import '../application/demo_data_service.dart';
import 'usage_doc_page.dart';

final currentProfileProvider = FutureProvider<Profile?>((ref) {
  return ref.watch(settingsRepositoryProvider).getProfile();
});

/// Settings page: language and theme (in-memory until M2).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final profileAsync = ref.watch(currentProfileProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(l10n.settingsProfileName),
            subtitle: Text(
              profileAsync.valueOrNull?.displayName ?? 'User',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editProfileName(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: Text(l10n.settingsBackup),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _backupData(context),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(l10n.settingsUsageDoc),
            subtitle: Text(l10n.settingsUsageDocHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const UsageDocPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: Text(l10n.settingsDemoData),
            subtitle: Text(l10n.settingsDemoDataHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _loadDemoData(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.sell_outlined),
            title: Text(l10n.tagsTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const TagTreePage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l10n.settingsLanguage),
            subtitle: Text(_languageLabel(l10n, settings.language)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickLanguage(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: Text(l10n.settingsTheme),
            subtitle: Text(_themeLabel(l10n, settings.themeMode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickTheme(context, ref),
          ),
        ],
      ),
    );
  }

  String _languageLabel(AppLocalizations l10n, AppLanguage language) {
    return switch (language) {
      AppLanguage.system => l10n.settingsLanguageSystem,
      AppLanguage.zh => l10n.settingsLanguageZh,
      AppLanguage.en => l10n.settingsLanguageEn,
    };
  }

  String _themeLabel(AppLocalizations l10n, AppThemeMode themeMode) {
    return switch (themeMode) {
      AppThemeMode.system => l10n.settingsThemeSystem,
      AppThemeMode.light => l10n.settingsThemeLight,
      AppThemeMode.dark => l10n.settingsThemeDark,
    };
  }

  Future<void> _backupData(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await getApplicationSupportDirectory();
      // The live database file is `threadflow.db`. The old name `knowflow.db`
      // only exists as a legacy fallback that gets migrated in place, so
      // backing it up would have saved a stale file (or reported "not found"
      // on every fresh install).
      final source = File('${dir.path}${Platform.pathSeparator}threadflow.db');
      if (!await source.exists()) {
        messenger.showSnackBar(
          SnackBar(content: Text('${l10n.settingsBackup}: not found')),
        );
        return;
      }
      final bytes = await source.readAsBytes();
      // file_picker 12: static method, takes the bytes, returns a Uri.
      final target = await FilePicker.saveFile(
        dialogTitle: l10n.settingsBackup,
        fileName: 'threadflow-backup.db',
        bytes: bytes,
        type: FileType.any,
      );
      if (target == null) {
        return;
      }
      await File(target.toFilePath()).writeAsBytes(bytes);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsBackupDone)),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.settingsBackup}: $error')),
      );
    }
  }

  /// One-shot demo workspace so the UI can be reviewed without manual typing.
  Future<void> _loadDemoData(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(demoDataServiceProvider);

    if (await service.hasExistingData()) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsDemoDataBlocked)),
      );
      return;
    }
    if (!context.mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsDemoData),
        content: Text(l10n.settingsDemoDataConfirm),
        actions: [
          IconButton(
            tooltip: l10n.commonCancel,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          IconButton.filled(
            tooltip: l10n.commonConfirm,
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await service.seed();
    // Every module reads its own provider, so refresh them all.
    ref.invalidate(allTagsProvider);
    ref.invalidate(timeBlocksProvider);
    ref.invalidate(calendarBlocksProvider);
    ref.invalidate(threadFeedProvider);
    ref.invalidate(threadStateProvider);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.settingsDemoDataDone)),
    );
  }

  Future<void> _editProfileName(BuildContext context, WidgetRef ref) async {    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(
      text: ref.read(currentProfileProvider).valueOrNull?.displayName ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsProfileName),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.commonName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) {
      return;
    }
    await ref.read(settingsRepositoryProvider).updateProfileName(name);
    ref.invalidate(currentProfileProvider);
  }

  Future<void> _pickLanguage(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showDialog<AppLanguage>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.settingsLanguage),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, AppLanguage.system),
            child: Text(l10n.settingsLanguageSystem),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, AppLanguage.zh),
            child: Text(l10n.settingsLanguageZh),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, AppLanguage.en),
            child: Text(l10n.settingsLanguageEn),
          ),
        ],
      ),
    );
    if (choice != null) {
      ref.read(settingsControllerProvider.notifier).setLanguage(choice);
    }
  }

  Future<void> _pickTheme(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showDialog<AppThemeMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.settingsTheme),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, AppThemeMode.system),
            child: Text(l10n.settingsThemeSystem),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, AppThemeMode.light),
            child: Text(l10n.settingsThemeLight),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, AppThemeMode.dark),
            child: Text(l10n.settingsThemeDark),
          ),
        ],
      ),
    );
    if (choice != null) {
      ref.read(settingsControllerProvider.notifier).setThemeMode(choice);
    }
  }
}
