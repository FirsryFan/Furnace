import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/mind_map_repository.dart';
import '../../../data/repositories/package_repository.dart';
import '../../../data/repositories/tag_repository.dart';
import '../../../domain/entities/knowledge_point.dart' as domain;
import '../../../domain/package/knowledge_package_manifest.dart';
import '../../../domain/services/cloze/cloze_generator.dart';

/// Summary returned after importing a knowledge package.
class PackageImportSummary {
  const PackageImportSummary({
    required this.tagsCreated,
    required this.knowledgePointsCreated,
    required this.templatesCreated,
    required this.mindMapsCreated,
  });

  final int tagsCreated;
  final int knowledgePointsCreated;
  final int templatesCreated;
  final int mindMapsCreated;
}

/// Imports a [KnowledgePackageManifest] into the local database.
class PackageImportService {
  PackageImportService({
    required PackageRepository packageRepository,
    required TagRepository tagRepository,
    required AnkiRepository ankiRepository,
    required MindMapRepository mindMapRepository,
  })  : _packages = packageRepository,
        _tags = tagRepository,
        _anki = ankiRepository,
        _mindMaps = mindMapRepository;

  final PackageRepository _packages;
  final TagRepository _tags;
  final AnkiRepository _anki;
  final MindMapRepository _mindMaps;

  Future<PackageImportSummary> importManifest(
    KnowledgePackageManifest manifest,
  ) async {
    await _packages.upsertPackage(manifest);

    var tagsCreated = 0;
    var knowledgePointsCreated = 0;
    var templatesCreated = 0;
    var mindMapsCreated = 0;

    // Tags
    final localTagIds = <String, String>{};
    for (final tag in manifest.tags) {
      final existing = await _packages.findPackageItem(
        packageId: manifest.packageId,
        objectType: 'tag',
        externalId: tag.id,
      );
      if (existing != null) {
        localTagIds[tag.id] = existing.objectId;
        continue;
      }
      final created = await _tags.createTag(
        name: tag.name,
        color: tag.color,
        description: tag.description,
      );
      await _packages.addPackageItem(
        packageId: manifest.packageId,
        objectType: 'tag',
        objectId: created.id,
        externalId: tag.id,
      );
      localTagIds[tag.id] = created.id;
      tagsCreated++;
    }

    // Knowledge points and templates
    for (final kp in manifest.knowledgePoints) {
      final existingKp = await _findOrCreateKnowledgePoint(manifest, kp);
      final localKpId = existingKp ??
          await (() async {
            final created = await _anki.createKnowledgePoint(
              title: kp.title,
              content: kp.content,
              source: kp.source,
              externalId: kp.id,
              packageId: manifest.packageId,
            );
            await _packages.addPackageItem(
              packageId: manifest.packageId,
              objectType: 'knowledge_point',
              objectId: created.id,
              externalId: kp.id,
            );
            knowledgePointsCreated++;
            return created.id;
          })();

      for (final template in kp.templates) {
        final existing = await _packages.findPackageItem(
          packageId: manifest.packageId,
          objectType: 'card_template',
          externalId: template.id,
        );
        if (existing != null) {
          continue;
        }
        final created = await _anki.createTemplate(
          knowledgePointId: localKpId,
          type: template.type,
          question: template.question,
          answer: template.answer,
          options: template.options,
          clozeTemplate: template.clozeTemplate,
          hint: template.hint,
          externalId: template.id,
        );
        await _anki.getOrCreateCardState(created.id);
        await _packages.addPackageItem(
          packageId: manifest.packageId,
          objectType: 'card_template',
          objectId: created.id,
          externalId: template.id,
        );
        templatesCreated++;
      }

      // Auto-generate a fill-blank template when the package does not provide
      // any templates for this knowledge point.
      if (kp.templates.isEmpty) {
        final autoExternalId = 'auto-${kp.id}';
        final existingAuto = await _packages.findPackageItem(
          packageId: manifest.packageId,
          objectType: 'card_template',
          externalId: autoExternalId,
        );
        if (existingAuto == null) {
          final domainKp = domain.KnowledgePoint(
            id: kp.id,
            title: kp.title,
            content: kp.content,
            source: kp.source,
          );
          final auto = ClozeGenerator.generateFillBlank(domainKp);
          if (auto != null) {
            final created = await _anki.createTemplate(
              knowledgePointId: localKpId,
              type: 'fill_blank',
              question: auto.question,
              answer: auto.answer,
              clozeTemplate: auto.clozeTemplate,
              externalId: autoExternalId,
            );
            await _anki.getOrCreateCardState(created.id);
            await _packages.addPackageItem(
              packageId: manifest.packageId,
              objectType: 'card_template',
              objectId: created.id,
              externalId: autoExternalId,
            );
            templatesCreated++;
          }
        }
      }

      // Attach tags to the knowledge point.
      for (final tagExternalId in kp.tags) {
        final localTagId = localTagIds[tagExternalId];
        if (localTagId != null) {
          await _tags.addTagToObject(
            tagId: localTagId,
            objectType: 'knowledge_point',
            objectId: localKpId,
          );
        }
      }
    }

    // Mind maps
    for (final map in manifest.mindMaps) {
      final existing = await _packages.findPackageItem(
        packageId: manifest.packageId,
        objectType: 'mind_map',
        externalId: map.id,
      );
      if (existing != null) {
        continue;
      }
      final created = await _mindMaps.createMindMap(map.title);
      final localNodeIds = <String, String>{};
      for (final node in map.nodes) {
        await _createNodeRecursively(
          mapId: created.id,
          node: node,
          localNodeIds: localNodeIds,
          localTagIds: localTagIds,
        );
      }
      await _packages.addPackageItem(
        packageId: manifest.packageId,
        objectType: 'mind_map',
        objectId: created.id,
        externalId: map.id,
      );
      mindMapsCreated++;
    }

    return PackageImportSummary(
      tagsCreated: tagsCreated,
      knowledgePointsCreated: knowledgePointsCreated,
      templatesCreated: templatesCreated,
      mindMapsCreated: mindMapsCreated,
    );
  }

  Future<String?> _findOrCreateKnowledgePoint(
    KnowledgePackageManifest manifest,
    PackageKnowledgePoint kp,
  ) async {
    final existing = await _packages.findPackageItem(
      packageId: manifest.packageId,
      objectType: 'knowledge_point',
      externalId: kp.id,
    );
    if (existing == null) {
      return null;
    }
    // Update content on re-import so fixes from the author propagate.
    await _anki.updateKnowledgePoint(
      existing.objectId,
      title: kp.title,
      content: kp.content,
      source: kp.source,
    );
    return existing.objectId;
  }

  Future<void> _createNodeRecursively({
    required String mapId,
    required PackageMindNode node,
    required Map<String, String> localNodeIds,
    required Map<String, String> localTagIds,
  }) async {
    final created = await _mindMaps.addNode(
      mapId: mapId,
      parentId: node.parentId == null ? null : localNodeIds[node.parentId],
      text: node.text,
      notes: node.notes,
      isTag: node.isTag,
      tagId: node.tagId == null ? null : localTagIds[node.tagId],
    );
    localNodeIds[node.id] = created.id;
    for (final child in node.children) {
      await _createNodeRecursively(
        mapId: mapId,
        node: child,
        localNodeIds: localNodeIds,
        localTagIds: localTagIds,
      );
    }
  }
}
