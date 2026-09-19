import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../domain/package/knowledge_package_manifest.dart';

/// Encodes and decodes `.kpak` packages (zip archives with `manifest.json`).
abstract final class KnowledgePackageCodec {
  static const manifestFileName = 'manifest.json';

  /// Builds a `.kpak` byte array from [manifest] and optional [assets].
  static Uint8List encode({
    required KnowledgePackageManifest manifest,
    Map<String, Uint8List> assets = const {},
  }) {
    final archive = Archive();
    final manifestJson = jsonEncode(manifest.toJson());
    archive.addFile(
      ArchiveFile(manifestFileName, manifestJson.length, manifestJson),
    );
    for (final entry in assets.entries) {
      archive.addFile(
        ArchiveFile(entry.key, entry.value.length, entry.value),
      );
    }
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  /// Extracts [KnowledgePackageManifest] from a `.kpak` byte array.
  static KnowledgePackageManifest decodeManifest(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final file = archive.findFile(manifestFileName);
    if (file == null) {
      throw const FormatException('Missing manifest.json in knowledge package');
    }
    final content = utf8.decode(file.content as List<int>);
    final json = jsonDecode(content) as Map<String, dynamic>;
    return KnowledgePackageManifest.fromJson(json);
  }

  /// Returns asset file names (excluding `manifest.json`).
  static List<String> assetFileNames(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    return [
      for (final file in archive.files)
        if (file.isFile && file.name != manifestFileName) file.name,
    ];
  }
}
