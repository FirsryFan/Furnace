import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_profile.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/repositories/theme_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../application/appearance_providers.dart';
import 'theme_editor_page.dart';

/// Appearance section of the settings page (spec §4).
///
/// Keeps the legacy system/light/dark choice as the top entry and lists the
/// stored theme documents below it, with import / export / duplicate / delete.
class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final themesAsync = ref.watch(themesProvider);
    final activeAsync = ref.watch(activeAppearanceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          icon: Icons.palette_outlined,
          title: l10n.settingsAppearance,
        ),
        ListTile(
          leading: const Icon(Icons.brightness_auto),
          title: Text(l10n.settingsThemeSystemEntry),
          subtitle: Text(l10n.settingsThemeSystemHint),
          trailing: activeAsync.valueOrNull?.followSystem == true
              ? const Icon(Icons.check)
              : null,
          onTap: () => selectTheme(ref, null),
        ),
        themesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
          error: (error, stack) => ListTile(
            leading: const Icon(Icons.error_outline),
            title: Text('$error'),
          ),
          data: (themes) => Column(
            children: [
              for (final theme in themes)
                _ThemeTile(
                  theme: theme,
                  isActive: activeAsync.valueOrNull?.row?.id == theme.id,
                ),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.file_upload_outlined),
          title: Text(l10n.settingsThemeImport),
          subtitle: Text(l10n.settingsThemeImportHint),
          onTap: () => _importTheme(context, ref),
        ),
      ],
    );
  }

  Future<void> _importTheme(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (picked.isEmpty) {
        return;
      }
      final bytes = await picked.first.readAsBytes();
      final body = utf8.decode(bytes);
      if (!ThemeRepository.isValidThemeJson(body)) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsThemeImportInvalid)),
        );
        return;
      }
      final imported = await importTheme(ref, body);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsThemeImported(imported.name))),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.settingsThemeImport}: $error')),
      );
    }
  }
}

class _ThemeTile extends ConsumerWidget {
  const _ThemeTile({required this.theme, required this.isActive});

  final ThemeProfile theme;
  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(themeRepositoryProvider);
    final data = repo.dataOf(theme);
    final builtin = theme.isBuiltin == 1;

    return ListTile(
      leading: _ThemeSwatch(data: data),
      title: Text(theme.name),
      subtitle: Text(
        builtin ? l10n.settingsThemeBuiltin : l10n.settingsThemeCustom,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isActive) const Icon(Icons.check),
          IconButton(
            tooltip: l10n.commonEdit,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => ThemeEditorPage(themeId: theme.id),
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.settingsThemeExport,
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => _export(context, ref, theme),
          ),
          if (!builtin)
            IconButton(
              tooltip: l10n.commonDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final removed = await deleteTheme(ref, theme.id);
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(removed
                        ? l10n.settingsThemeDeleted
                        : l10n.settingsThemeBuiltinProtected),
                  ),
                );
              },
            ),
        ],
      ),
      onTap: () => selectTheme(ref, theme.id),
    );
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    ThemeProfile theme,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(themeRepositoryProvider);
      final json = repo.exportJson(theme);
      final name = repo.dataOf(theme).name;
      final target = await FilePicker.saveFile(
        dialogTitle: l10n.settingsThemeExport,
        fileName: '${name.isEmpty ? 'theme' : name}.json',
        bytes: utf8.encode(json),
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (target == null) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsThemeExported)),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.settingsThemeExport}: $error')),
      );
    }
  }
}

/// Two-colour preview of a theme: the primary colour plus the background.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.data});

  final ThemeProfileData data;

  @override
  Widget build(BuildContext context) {
    final primary = ThemeProfileData.colorOf(
      data.primary,
      fallback: const Color(0xFF3D8B63),
    );
    final background = ThemeProfileData.colorOf(
      data.background ?? (data.isDark ? '#101211' : '#FFFFFF'),
      fallback: data.isDark ? const Color(0xFF101211) : const Color(0xFFFFFFFF),
    );
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: primary, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: primary,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
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
