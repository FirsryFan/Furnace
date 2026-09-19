/// Knowledge point domain entity.
library;

import 'card_template.dart';

class KnowledgePoint {
  const KnowledgePoint({
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
  final List<CardTemplate> templates;
}
