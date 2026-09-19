import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow/data/package/knowledge_package_codec.dart';
import 'package:knowflow/domain/package/knowledge_package_manifest.dart';

void main() {
  group('KnowledgePackageCodec', () {
    test('encodes and decodes manifest', () {
      final manifest = KnowledgePackageManifest(
        formatVersion: 1,
        packageId: 'pkg-1',
        name: '测试包',
        version: '0.1.0',
        author: '张三',
        exportedAt: DateTime.utc(2026, 8, 19),
        knowledgePoints: const [
          PackageKnowledgePoint(
            id: 'kp-1',
            title: '测试',
            content: '内容',
          ),
        ],
      );

      final bytes = KnowledgePackageCodec.encode(manifest: manifest);
      final decoded = KnowledgePackageCodec.decodeManifest(bytes);

      expect(decoded.packageId, 'pkg-1');
      expect(decoded.name, '测试包');
      expect(decoded.knowledgePoints.single.title, '测试');
    });

    test('lists asset files', () {
      final manifest = KnowledgePackageManifest(
        formatVersion: 1,
        packageId: 'pkg-2',
        name: '带附件',
        version: '1.0.0',
        author: '李四',
        exportedAt: DateTime.utc(2026, 8, 19),
      );
      final bytes = KnowledgePackageCodec.encode(
        manifest: manifest,
        assets: {
          'assets/logo.png': Uint8List.fromList([1, 2, 3]),
        },
      );

      expect(KnowledgePackageCodec.assetFileNames(bytes),
          contains('assets/logo.png'));
    });
  });
}
