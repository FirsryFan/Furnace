import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:knowflow/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/package/knowledge_package_codec.dart';
import '../../../data/repositories/repository_providers.dart';

/// Knowledge library page: import and (later) export `.kpak` packages.
class PackagesPage extends ConsumerWidget {
  const PackagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
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
      body: Center(
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
              onPressed: () => _importPackage(context, ref),
              icon: const Icon(Icons.file_download_outlined),
              label: Text(l10n.packagesImport),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportPackage(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nameController =
        TextEditingController(text: l10n.packagesDefaultName);
    final authorController =
        TextEditingController(text: l10n.packagesDefaultAuthor);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.packagesExport),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.packagesExportName),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: authorController,
              decoration: InputDecoration(labelText: l10n.packagesExportAuthor),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.privacyExportNote,
              style: Theme.of(context).textTheme.bodySmall,
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
            child: Text(l10n.commonSave),
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

    try {
      final manifest = await ref
          .read(packageExportServiceProvider)
          .buildManifest(
            name: nameController.text.trim().isEmpty
                ? l10n.packagesDefaultName
                : nameController.text.trim(),
            author: authorController.text.trim().isEmpty
                ? l10n.packagesDefaultAuthor
                : authorController.text.trim(),
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
        SnackBar(content: Text('${l10n.packagesExport}: ${target.toFilePath()}')),
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

      final summary = await ref
          .read(packageImportServiceProvider)
          .importManifest(manifest);

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
