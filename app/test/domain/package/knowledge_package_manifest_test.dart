import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/package/knowledge_package_manifest.dart';

void main() {
  group('KnowledgePackageManifest', () {
    test('round-trips JSON', () {
      final manifest = KnowledgePackageManifest(
        formatVersion: 1,
        packageId: 'pkg-1',
        name: '光合作用',
        version: '1.0.0',
        author: '张三',
        exportedAt: DateTime.utc(2026, 8, 19),
        tags: const [
          PackageTag(id: 'tag-1', name: '光合作用', color: 123),
        ],
        knowledgePoints: const [
          PackageKnowledgePoint(
            id: 'kp-1',
            title: '场所',
            content: '叶绿体',
            tags: ['tag-1'],
            templates: [
              PackageCardTemplate(
                id: 'tpl-1',
                type: 'fill_blank',
                question: '场所是___',
                answer: '叶绿体',
              ),
            ],
          ),
        ],
      );

      final json = manifest.toJson();
      final decoded = KnowledgePackageManifest.fromJson(json);

      expect(decoded.packageId, 'pkg-1');
      expect(decoded.name, '光合作用');
      expect(decoded.knowledgePoints.single.templates.single.type,
          'fill_blank');
      expect(decoded.toJson(), json);
    });
  });
}
