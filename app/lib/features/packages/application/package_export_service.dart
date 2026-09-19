import 'package:uuid/uuid.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/mind_map_repository.dart';
import '../../../data/repositories/tag_repository.dart';
import '../../../domain/package/knowledge_package_manifest.dart';

/// Builds a [KnowledgePackageManifest] from local data for export.
class PackageExportService {
  PackageExportService({
    required TagRepository tagRepository,
    required AnkiRepository ankiRepository,
    required MindMapRepository mindMapRepository,
  })  : _tags = tagRepository,
        _anki = ankiRepository,
        _mindMaps = mindMapRepository;

  final TagRepository _tags;
  final AnkiRepository _anki;
  final MindMapRepository _mindMaps;

  Future<KnowledgePackageManifest> buildManifest({
    String name = 'My Library',
    String version = '1.0.0',
    String author = 'Me',
  }) async {
    final tags = await _tags.getAllTags();
    final knowledgePoints = await _anki.getKnowledgePoints();
    final mindMaps = await _mindMaps.getMindMaps();

    final tagById = {for (final tag in tags) tag.id: tag};

    final packageTags = [
      for (final tag in tags)
        PackageTag(
          id: tag.id,
          name: tag.name,
          color: tag.color,
          description: tag.description,
        ),
    ];

    final packageKnowledgePoints = <PackageKnowledgePoint>[];
    for (final kp in knowledgePoints) {
      final templates = await _anki.getTemplatesForKnowledgePoint(kp.id);
      final objectTagLinks = await _tags.tagsForObject(
        objectType: 'knowledge_point',
        objectId: kp.id,
      );
      packageKnowledgePoints.add(
        PackageKnowledgePoint(
          id: kp.id,
          title: kp.title,
          content: kp.content,
          source: kp.source,
          tags: [
            for (final tag in objectTagLinks)
              if (tagById.containsKey(tag.id)) tag.id,
          ],
          templates: [
            for (final template in templates)
              PackageCardTemplate(
                id: template.id,
                type: template.type,
                question: template.question,
                answer: template.answer,
                options: template.options == null
                    ? const []
                    : template.options!.split('\u0001'),
                clozeTemplate: template.clozeTemplate,
                hint: template.hint,
              ),
          ],
        ),
      );
    }

    final packageMindMaps = <PackageMindMap>[];
    for (final map in mindMaps) {
      final nodes = await _mindMaps.getNodesForMap(map.id);
      packageMindMaps.add(
        PackageMindMap(
          id: map.id,
          title: map.title,
          nodes: _buildNodeTree(nodes),
        ),
      );
    }

    return KnowledgePackageManifest(
      formatVersion: 1,
      packageId: Uuid().v4(),
      name: name,
      version: version,
      author: author,
      exportedAt: DateTime.now().toUtc(),
      tags: packageTags,
      knowledgePoints: packageKnowledgePoints,
      mindMaps: packageMindMaps,
    );
  }

  List<PackageMindNode> _buildNodeTree(List<MindNode> nodes) {
    final byParent = <String?, List<MindNode>>{};
    for (final node in nodes) {
      byParent.putIfAbsent(node.parentId, () => []).add(node);
    }
    List<PackageMindNode> build(String? parentId) {
      return [
        for (final node in byParent[parentId] ?? const <MindNode>[])
          PackageMindNode(
            id: node.id,
            parentId: node.parentId,
            text: node.nodeText,
            notes: node.notes,
            isTag: node.isTag,
            tagId: node.tagId,
            children: build(node.id),
          ),
      ];
    }

    return build(null);
  }
}
