/// Manifest model for `.kpak` knowledge packages.
///
/// The package itself is a zip archive containing `manifest.json` and optional
/// `assets/`. This file only models the JSON manifest.
library;

class KnowledgePackageManifest {
  const KnowledgePackageManifest({
    required this.formatVersion,
    required this.packageId,
    required this.name,
    required this.version,
    required this.author,
    required this.exportedAt,
    this.description,
    this.tags = const [],
    this.knowledgePoints = const [],
    this.mindMaps = const [],
  });

  final int formatVersion;
  final String packageId;
  final String name;
  final String version;
  final String author;
  final DateTime exportedAt;
  final String? description;
  final List<PackageTag> tags;
  final List<PackageKnowledgePoint> knowledgePoints;
  final List<PackageMindMap> mindMaps;

  factory KnowledgePackageManifest.fromJson(Map<String, dynamic> json) {
    return KnowledgePackageManifest(
      formatVersion: json['formatVersion'] as int,
      packageId: json['packageId'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      author: json['author'] as String,
      exportedAt: DateTime.parse(json['exportedAt'] as String),
      description: json['description'] as String?,
      tags: [
        for (final item in (json['tags'] as List? ?? const []))
          PackageTag.fromJson(item as Map<String, dynamic>),
      ],
      knowledgePoints: [
        for (final item in (json['knowledgePoints'] as List? ?? const []))
          PackageKnowledgePoint.fromJson(item as Map<String, dynamic>),
      ],
      mindMaps: [
        for (final item in (json['mindMaps'] as List? ?? const []))
          PackageMindMap.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'formatVersion': formatVersion,
      'packageId': packageId,
      'name': name,
      'version': version,
      'author': author,
      'exportedAt': exportedAt.toIso8601String(),
      if (description != null) 'description': description,
      'tags': [for (final tag in tags) tag.toJson()],
      'knowledgePoints': [
        for (final kp in knowledgePoints) kp.toJson(),
      ],
      'mindMaps': [for (final map in mindMaps) map.toJson()],
    };
  }
}

class PackageTag {
  const PackageTag({
    required this.id,
    required this.name,
    this.color,
    this.description,
  });

  final String id;
  final String name;
  final int? color;
  final String? description;

  factory PackageTag.fromJson(Map<String, dynamic> json) {
    return PackageTag(
      id: json['id'] as String,
      name: json['name'] as String,
      color: json['color'] as int?,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (color != null) 'color': color,
      if (description != null) 'description': description,
    };
  }
}

class PackageKnowledgePoint {
  const PackageKnowledgePoint({
    required this.id,
    required this.title,
    required this.content,
    this.source,
    this.tags = const [],
    this.templates = const [],
  });

  final String id;
  final String title;
  final String content;
  final String? source;
  final List<String> tags;
  final List<PackageCardTemplate> templates;

  factory PackageKnowledgePoint.fromJson(Map<String, dynamic> json) {
    return PackageKnowledgePoint(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      source: json['source'] as String?,
      tags: [for (final tag in (json['tags'] as List? ?? const [])) tag as String],
      templates: [
        for (final item in (json['templates'] as List? ?? const []))
          PackageCardTemplate.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      if (source != null) 'source': source,
      'tags': tags,
      'templates': [for (final t in templates) t.toJson()],
    };
  }
}

class PackageCardTemplate {
  const PackageCardTemplate({
    required this.id,
    required this.type,
    required this.question,
    required this.answer,
    this.options = const [],
    this.clozeTemplate,
    this.hint,
  });

  final String id;
  final String type;
  final String question;
  final String answer;
  final List<String> options;
  final String? clozeTemplate;
  final String? hint;

  factory PackageCardTemplate.fromJson(Map<String, dynamic> json) {
    return PackageCardTemplate(
      id: json['id'] as String,
      type: json['type'] as String,
      question: json['question'] as String,
      answer: json['answer'] as String,
      options: [
        for (final option in (json['options'] as List? ?? const []))
          option as String,
      ],
      clozeTemplate: json['clozeTemplate'] as String?,
      hint: json['hint'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'question': question,
      'answer': answer,
      if (options.isNotEmpty) 'options': options,
      if (clozeTemplate != null) 'clozeTemplate': clozeTemplate,
      if (hint != null) 'hint': hint,
    };
  }
}

class PackageMindMap {
  const PackageMindMap({
    required this.id,
    required this.title,
    this.nodes = const [],
  });

  final String id;
  final String title;
  final List<PackageMindNode> nodes;

  factory PackageMindMap.fromJson(Map<String, dynamic> json) {
    return PackageMindMap(
      id: json['id'] as String,
      title: json['title'] as String,
      nodes: [
        for (final item in (json['nodes'] as List? ?? const []))
          PackageMindNode.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'nodes': [for (final node in nodes) node.toJson()],
    };
  }
}

class PackageMindNode {
  const PackageMindNode({
    required this.id,
    this.parentId,
    required this.text,
    this.notes,
    this.isTag = false,
    this.tagId,
    this.children = const [],
  });

  final String id;
  final String? parentId;
  final String text;
  final String? notes;
  final bool isTag;
  final String? tagId;
  final List<PackageMindNode> children;

  factory PackageMindNode.fromJson(Map<String, dynamic> json) {
    return PackageMindNode(
      id: json['id'] as String,
      parentId: json['parentId'] as String?,
      text: json['text'] as String,
      notes: json['notes'] as String?,
      isTag: json['isTag'] as bool? ?? false,
      tagId: json['tagId'] as String?,
      children: [
        for (final item in (json['children'] as List? ?? const []))
          PackageMindNode.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (parentId != null) 'parentId': parentId,
      'text': text,
      if (notes != null) 'notes': notes,
      'isTag': isTag,
      if (tagId != null) 'tagId': tagId,
      'children': [for (final child in children) child.toJson()],
    };
  }
}
