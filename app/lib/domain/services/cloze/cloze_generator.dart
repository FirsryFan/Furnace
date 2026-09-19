/// Lightweight auto-blank generator for knowledge points.
///
/// It is intentionally simple: it only creates `fill_blank` templates.
/// Authors can always provide explicit templates in a knowledge package.
library;

import '../../entities/card_template.dart';
import '../../entities/knowledge_point.dart';

abstract final class ClozeGenerator {
  static const String blankMarker = '___';

  /// Generates a fill-blank template from [point] if a suitable blank can be
  /// found. Returns `null` when no confident blank is available.
  static CardTemplate? generateFillBlank(KnowledgePoint point) {
    final content = point.content.trim();
    if (content.isEmpty) {
      return null;
    }

    String? answer;
    String? question;

    // 1. Replace an explicit keyword if provided.
    for (final keyword in _extractKeywords(point)) {
      final trimmed = keyword.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final index = content.indexOf(trimmed);
      if (index >= 0) {
        answer = trimmed;
        question = content.replaceFirst(trimmed, blankMarker);
        break;
      }
    }

    // 2. Blank after "是" or "为" (common Chinese definition pattern).
    for (final marker in ['是', '为']) {
      if (question != null) {
        break;
      }
      final extracted = _blankAfterMarker(content, marker);
      if (extracted != null) {
        answer = extracted.answer;
        question = extracted.question;
      }
    }

    // 3. Blank after "：" or ":".
    if (question == null) {
      for (final separator in ['：', ':']) {
        final index = content.indexOf(separator);
        if (index >= 0 && index < content.length - 1) {
          final tail = content.substring(index + 1).trim();
          if (tail.isNotEmpty) {
            answer = tail;
            question = content.replaceFirst(tail, blankMarker);
            break;
          }
        }
      }
    }

    // 4. Blank a number if present.
    if (question == null) {
      final numberMatch = RegExp(r'\d+(\.\d+)?').firstMatch(content);
      if (numberMatch != null) {
        answer = numberMatch.group(0);
        question = content.replaceFirst(answer!, blankMarker);
      }
    }

    if (question == null || answer == null || answer.isEmpty) {
      return null;
    }

    return CardTemplate(
      id: 'auto-${point.id}-1',
      knowledgePointId: point.id,
      type: CardTemplateType.fillBlank,
      question: question,
      answer: answer,
      clozeTemplate: question,
    );
  }

  static List<String> _extractKeywords(KnowledgePoint point) {
    return [
      ...point.tags,
      if (point.title.isNotEmpty) point.title,
    ];
  }

  static ({String question, String answer})? _blankAfterMarker(
    String content,
    String marker,
  ) {
    final index = content.indexOf(marker);
    if (index < 0 || index == content.length - 1) {
      return null;
    }
    var answer = content.substring(index + 1).trim();
    answer = answer.replaceFirst(RegExp(r'[。！？!?；;，,]+$'), '');
    if (answer.isEmpty) {
      return null;
    }
    return (
      question: content.replaceFirst(answer, blankMarker),
      answer: answer,
    );
  }
}
