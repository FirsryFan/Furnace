/// Card template domain entity.
library;

enum CardTemplateType { mcq, fillBlank, essay }

class CardTemplate {
  const CardTemplate({
    required this.id,
    required this.knowledgePointId,
    required this.type,
    required this.question,
    required this.answer,
    this.options = const [],
    this.clozeTemplate,
    this.hint,
  });

  final String id;
  final String knowledgePointId;
  final CardTemplateType type;
  final String question;
  final String answer;
  final List<String> options;
  final String? clozeTemplate;
  final String? hint;
}
