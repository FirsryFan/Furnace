import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:furnace/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/database.dart';
import '../../../data/package/knowledge_package_codec.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../tags/presentation/tag_tree_page.dart';

/// One row of the library: the package record plus what it brought in.
class PackageLibraryEntry {
  const PackageLibraryEntry({required this.row, required this.counts});

  final KnowledgePackage row;

  /// `package_items.object_type` -> how many objects of that type were created.
  final Map<String, int> counts;

  int get knowledgePoints => counts['knowledge_point'] ?? 0;
  int get cardTemplates => counts['card_template'] ?? 0;
  int get tags => counts['tag'] ?? 0;
  int get mindMaps => counts['mind_map'] ?? 0;
}

/// Everything this app imported, newest first.
///
/// Reads through the data revision, so an import made from anywhere (this page,
/// the settings page, a re-import) shows up without refreshing by hand.
final packageLibraryProvider =
    FutureProvider<List<PackageLibraryEntry>>((ref) async {
  ref.watchDatabaseRevision();
  final packages = ref.watch(packageRepositoryProvider);
  final rows = await packages.getAllPackages();
  final counts = await packages.itemCountsByPackage();
  return [
    for (final row in rows)
      PackageLibraryEntry(
          row: row, counts: counts[row.id] ?? const <String, int>{}),
  ];
});

/// The knowledge library (`.kpak`): import a shared package, and export one.
///
/// Export scope exists because "share my whole library" is only one of the two
/// things people want; the other is "share exactly the chapter we just did".
class PackagesPage extends ConsumerWidget {
  const PackagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final library = ref.watch(packageLibraryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navPackages),
        actions: [
          IconButton(
            tooltip: l10n.packagesExport,
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: () => _exportPackage(context, ref),
          ),
          IconButton(
            tooltip: l10n.packagesImport,
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => _importPackage(context, ref),
          ),
        ],
      ),
      body: switch (library) {
        AsyncData(:final value) => value.isEmpty
            ? _EmptyLibrary(onImport: () => _importPackage(context, ref))
            : _LibraryList(entries: value),
        AsyncError(:final error) => Center(child: Text('$error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Future<void> _exportPackage(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nameController =
        TextEditingController(text: l10n.packagesDefaultName);
    final authorController =
        TextEditingController(text: l10n.packagesDefaultAuthor);
    final versionController = TextEditingController(text: '1.0.0');
    // `allTagsProvider` is the same tag list the tag page shows; reading it is
    // what lets the dialog offer the same tag names.
    final tags = await ref.read(allTagsProvider.future);
    if (!context.mounted) {
      return;
    }
    var byTag = false;
    final selectedTags = <String>{};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.packagesExport),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration:
                        InputDecoration(labelText: l10n.packagesExportName),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: authorController,
                    decoration:
                        InputDecoration(labelText: l10n.packagesExportAuthor),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: versionController,
                    decoration: InputDecoration(
                      labelText: l10n.packagesVersion,
                      hintText: l10n.packagesVersionHint,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.packagesScopeLabel,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(l10n.packagesScopeAll),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(l10n.packagesScopeByTag),
                      ),
                    ],
                    selected: {byTag},
                    onSelectionChanged: (selection) =>
                        setDialogState(() => byTag = selection.first),
                  ),
                  if (byTag) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.packagesScopeHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    if (tags.isEmpty)
                      Text(l10n.packagesNoTags)
                    else ...[
                      Text(
                        l10n.packagesSelectTags,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tag in tags)
                            FilterChip(
                              label: Text(tag.name),
                              selected: selectedTags.contains(tag.id),
                              onSelected: (selected) => setDialogState(() {
                                if (selected) {
                                  selectedTags.add(tag.id);
                                } else {
                                  selectedTags.remove(tag.id);
                                }
                              }),
                            ),
                        ],
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  Text(
                    l10n.privacyExportNote,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              // Nothing selected means nothing to export; the button says so
              // instead of writing an empty package.
              onPressed: byTag && selectedTags.isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    final version = versionController.text.trim();
    try {
      final manifest =
          await ref.read(packageExportServiceProvider).buildManifest(
                name: nameController.text.trim().isEmpty
                    ? l10n.packagesDefaultName
                    : nameController.text.trim(),
                author: authorController.text.trim().isEmpty
                    ? l10n.packagesDefaultAuthor
                    : authorController.text.trim(),
                version: version.isEmpty ? '1.0.0' : version,
                tagIds: byTag ? selectedTags : const <String>{},
              );
      final bytes = KnowledgePackageCodec.encode(manifest: manifest);

      // file_picker 12: `saveFile` is a static method that takes the bytes and
      // returns the chosen location as a Uri (it used to return a path).
      final target = await FilePicker.saveFile(
        dialogTitle: l10n.packagesExport,
        fileName: '${manifest.name}.kpak',
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['kpak'],
      );
      if (target == null) {
        return;
      }
      await File(target.toFilePath()).writeAsBytes(bytes);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.packagesExport}: ${target.toFilePath()} '
            '(${manifest.knowledgePoints.length} ${l10n.navAnki})',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.packagesExport}: $error')),
      );
    }
  }

  Future<void> _importPackage(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // file_picker 12: `pickFiles` is static, returns the files directly (it
    // used to return a FilePickerResult wrapper), and the bytes come from an
    // async `readAsBytes()` instead of a `bytes` property.
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['kpak'],
    );
    if (picked.isEmpty) {
      return;
    }

    final file = picked.first;
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.packagesImport}: $error')),
      );
      return;
    }

    try {
      final manifest = KnowledgePackageCodec.decodeManifest(
        Uint8List.fromList(bytes),
      );
      final existingPackage = await ref
          .read(packageRepositoryProvider)
          .getPackageById(manifest.packageId);
      if (!context.mounted) {
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.packagesPreviewTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${l10n.commonName}: ${manifest.name}'),
              Text('${l10n.packagesVersion}: ${manifest.version}'),
              if (existingPackage != null &&
                  existingPackage.version != manifest.version)
                Text(
                  '${l10n.packagesUpgrade}: '
                  '${existingPackage.version} → ${manifest.version}',
                ),
              Text('${l10n.packagesExportAuthor}: ${manifest.author}'),
              Text(
                '${l10n.navAnki}: ${manifest.knowledgePoints.length}'
                ' / ${l10n.navMindMap}: ${manifest.mindMaps.length}',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.packagesImportConfirm),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
      if (!context.mounted) {
        return;
      }

      final summary =
          await ref.read(packageImportServiceProvider).importManifest(manifest);

      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.packagesImported}: '
            '${summary.knowledgePointsCreated} KP / '
            '${summary.templatesCreated} cards',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.packagesImport}: $error')),
      );
    }
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(l10n.packagesEmpty),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.file_download_outlined),
            label: Text(l10n.packagesImport),
          ),
        ],
      ),
    );
  }
}

class _LibraryList extends StatelessWidget {
  const _LibraryList({required this.entries});

  final List<PackageLibraryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length + 1,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Text(
              l10n.packagesInstalledTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          );
        }
        return _PackageTile(entry: entries[index - 1]);
      },
    );
  }
}

class _PackageTile extends ConsumerWidget {
  const _PackageTile({required this.entry});

  final PackageLibraryEntry entry;

  /// `package_items` 行数 = 这条导入记录拥有的条目数，卸载对话框里给用户看。
  /// 直接用列表已经加载的计数，不再查一次库。
  int get _itemCount =>
      entry.counts.values.fold(0, (sum, value) => sum + value);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final row = entry.row;
    final enabled = ref.watch(packageRepositoryProvider).isPackageEnabled(row);
    // 禁用行弱化：文字/图标走主题的 disabledColor，控件仍保持可操作性。
    final muted = enabled ? null : TextStyle(color: theme.disabledColor);
    final parts = <String>[
      '${l10n.navAnki} ${entry.knowledgePoints}',
      if (entry.cardTemplates > 0)
        '${l10n.packagesCardTemplates} ${entry.cardTemplates}',
      if (entry.tags > 0) '${l10n.navTags} ${entry.tags}',
      if (entry.mindMaps > 0) '${l10n.navMindMap} ${entry.mindMaps}',
    ];
    final summary = '${l10n.packagesImportedAt}: ${_stamp(row.importedAt)} · '
        '${l10n.packagesItemsCount} ${parts.join(' · ')}';

    return ListTile(
      leading: Icon(
        Icons.inventory_2_outlined,
        color: enabled ? null : theme.disabledColor,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              row.name,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'v${row.version}',
            style: theme.textTheme.labelSmall?.merge(muted),
          ),
          if (!enabled) ...[
            const SizedBox(width: 8),
            _DisabledBadge(label: l10n.packagesDisabled),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${l10n.packagesExportAuthor}: ${row.author}', style: muted),
          Text(summary, style: muted),
        ],
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // NULL 读作启用（v42 之前导入的包没有这一列），所以这里直接问 repository。
          Switch(
            value: enabled,
            onChanged: (value) async {
              await ref
                  .read(packageRepositoryProvider)
                  .setPackageEnabled(row.id, value);
            },
          ),
          IconButton(
            tooltip: l10n.packagesUninstall,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _uninstall(context, ref),
          ),
        ],
      ),
    );
  }

  /// 卸载只删「导入记录」：`package_items` 映射 + `knowledge_packages` 行；
  /// 由它导入的知识点/闪存卡/标签保留（repository 契约，对话框文案已说明）。
  Future<void> _uninstall(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.packagesUninstallTitle),
        content:
            Text(l10n.packagesUninstallConfirm(entry.row.name, _itemCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.packagesUninstall),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(packageRepositoryProvider).deletePackage(entry.row.id);
    // 真机上写库会经 DbWriteInterceptor 触发 data revision、provider 自己重跑；
    // 这里显式失效一次，让没有拦截器的 widget test 也立刻看到列表变化。
    ref.invalidate(packageLibraryProvider);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.packagesUninstallDone(entry.row.name))),
    );
  }

  static String _stamp(int millis) {
    final at = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
  }
}

/// 已禁用的行尾徽标。用主题色而非写死颜色，深浅色主题都成立。
class _DisabledBadge extends StatelessWidget {
  const _DisabledBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
