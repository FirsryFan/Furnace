/// The AI's write path into the Knowledge module: "make me 背诵卡片 from this".
///
/// This is what closes the loop for the photo flow. A model can already *look*
/// at an attached image; without this tool the answer would be a chat message
/// the user then has to retype into the Knowledge screen by hand. Here the model
/// decides what the knowledge point is and what each question/answer card says,
/// and the tool writes them through [AnkiRepository] - the same calls
/// `package_import_service.dart` makes when it imports a package, so an AI-made
/// card is indistinguishable from an imported one and the Knowledge screens
/// refresh by themselves (AI_DESIGN D2).
///
/// It is a **write** tool that carries a real undo: the created ids go into
/// `ai_actions.after_json` and [deleteCreatedKnowledgeCards] removes them. That
/// is what lets it be adjudicated by the existing [ApprovalEngine] (batch
/// confirmation in plan mode, automatic plus one-click undo in auto mode)
/// instead of needing a second gate of its own.
library;

import 'dart:convert';

import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../domain/entities/card_template.dart' as domain;
import '../../../domain/entities/knowledge_point.dart' as domain;
import '../../../domain/services/cloze/cloze_generator.dart';
import '../domain/ai_tool.dart';

/// One card the model asked for, after validation.
class _RequestedCard {
  const _RequestedCard({
    required this.question,
    required this.answer,
    required this.type,
    this.hint,
  });

  final String question;
  final String answer;
  final String type;
  final String? hint;
}

/// Creates a knowledge point plus one card template per requested card.
class CreateKnowledgeCardsTool extends AiTool {
  CreateKnowledgeCardsTool(this._anki);

  final AnkiRepository _anki;

  /// The name the provider sees. The agent loop recognises it for undo.
  static const String toolName = 'create_knowledge_cards';

  /// The only card types Furnace stores. Verified against the Knowledge UI's own
  /// picker and the `ankiTypeMcq` / `ankiTypeFillBlank` / `ankiTypeEssay` keys.
  static const Set<String> cardTypes = {'fill_blank', 'mcq', 'essay'};

  /// A question/answer pair is a 大题 in this app's taxonomy; `fill_blank` needs
  /// a cloze and `mcq` needs options, so neither can be the silent default.
  static const String defaultCardType = 'essay';

  @override
  String get name => toolName;

  @override
  String get description =>
      '创建一个闪存卡，并为它生成背诵卡片（问题/答案）。'
      '**用户发来课本/笔记的照片、或粘贴一段内容，并要求"做成背诵卡片 / 记忆卡片 / 帮我记住"时，用这个工具**：'
      '先读懂内容，把关键信息整理成 content，再自己出题填 cards。'
      '题目与答案必须与原文同一种语言（原文是中文就用中文，是英文就用英文），一道题只问一个点，'
      '答案要能在不看照片时独立读懂（不要写"如上图"）。'
      'cards 每题给 question 与 answer，type 可选：fill_blank 填空 / mcq 选择 / essay 大题（默认）。'
      '不给 cards 时会自动从 content 生成一张填空题（content 里需要一个可挖空的关键信息）。'
      '创建完成后可以在这条对话里一键撤销。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'title': {
            'type': 'string',
            'description': '闪存卡标题（必填）：一句话说清这个点是什么，会成为复习列表里的一行',
          },
          'content': {
            'type': 'string',
            'description': '闪存卡正文（必填）：把照片/原文里的关键内容整理成一段可以直接复习的文字；'
                '它既是以后挖空的依据，也是用户点开闪存卡时看到的内容',
          },
          'source': {
            'type': 'string',
            'description': '来源说明，例如「课本 P32 第 3 段」或照片的文件名',
          },
          'cards': {
            'type': 'array',
            'description': '卡片列表，一道题一条。留空时会自动生成一张填空题。',
            'items': {
              'type': 'object',
              'properties': {
                'question': {'type': 'string', 'description': '问题（必填）'},
                'answer': {'type': 'string', 'description': '答案（必填）'},
                'type': {
                  'type': 'string',
                  'enum': cardTypes.toList(),
                  'description': '题型，默认 $defaultCardType',
                },
                'hint': {'type': 'string', 'description': '提示（可选）'},
              },
              'required': <String>['question', 'answer'],
            },
          },
        },
        'required': <String>['title', 'content'],
      };

  /// A single-purpose tool: there is no `action` argument, so the risk is the
  /// tool's and not a switch over actions.
  @override
  ToolRisk riskFor(String action) => ToolRisk.write;

  /// Every call can snapshot exactly what it created (ids of the point, the
  /// templates and their card states), which is the D13b precondition for
  /// automatic execution being safe to offer.
  @override
  bool reversibleFor(String action) => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    final args = ToolArgs(invocation.arguments);
    try {
      final title = args.requireString('title');
      final content = args.requireString('content');
      final source = args.optString('source');
      final requested = _parseCards(invocation.arguments['cards']);

      // The fallback card is computed BEFORE anything is written: a knowledge
      // point with no card can never be reviewed, so a request that yields no
      // card at all has to be refused with an empty database rather than a
      // half-made one.
      domain.CardTemplate? auto;
      if (requested.isEmpty) {
        // The generator only reads the title and the content; the id it is
        // given never reaches the database, because the template it returns is
        // re-created through the repository below.
        auto = ClozeGenerator.generateFillBlank(domain.KnowledgePoint(
          id: 'unsaved',
          title: title,
          content: content,
          source: source,
        ));
        if (auto == null) {
          return const ToolResult.failure(
            '没有可用的卡片：请在 cards 里给出 question/answer；'
            '或者在 content 里写一个能挖空的关键信息（例如"…是…"的句子）',
          );
        }
      }

      final point = await _anki.createKnowledgePoint(
        title: title,
        content: content,
        source: source,
      );

      final created = <Map<String, Object?>>[];
      for (final card in requested) {
        created.add(await _writeCard(
          knowledgePointId: point.id,
          question: card.question,
          answer: card.answer,
          type: card.type,
          clozeTemplate: card.type == 'fill_blank' ? card.question : null,
          hint: card.hint,
        ));
      }
      if (auto != null) {
        // Same three calls the package importer makes for an auto-generated
        // blank, so the two paths cannot drift.
        created.add(await _writeCard(
          knowledgePointId: point.id,
          question: auto.question,
          answer: auto.answer,
          type: 'fill_blank',
          clozeTemplate: auto.clozeTemplate,
        ));
      }

      return ToolResult(
        ok: true,
        summary: '已创建闪存卡「${point.title}」，含 ${created.length} 张卡片'
            '${auto != null ? '（自动生成填空题）' : ''}',
        modelResult: {
          'knowledge_point_id': point.id,
          'title': point.title,
          'card_count': created.length,
          'auto_generated_card': auto != null,
          'cards': created,
        },
        // Ids only: that is everything undo needs, and keeping the snapshot
        // small keeps the ledger readable.
        afterJson: jsonEncode({
          'knowledge_point_id': point.id,
          'template_ids': [for (final card in created) card['id']],
        }),
      );
    } on ToolArgError catch (e) {
      // Caused by the model, so it becomes a result it can read and correct.
      return ToolResult.failure(e.message);
    }
  }

  /// Writes one card and its review state, and reports what the model may refer
  /// to later.
  Future<Map<String, Object?>> _writeCard({
    required String knowledgePointId,
    required String question,
    required String answer,
    required String type,
    String? clozeTemplate,
    String? hint,
  }) async {
    final template = await _anki.createTemplate(
      knowledgePointId: knowledgePointId,
      type: type,
      question: question,
      answer: answer,
      clozeTemplate: clozeTemplate,
      hint: hint,
    );
    // Without a card state the card is invisible to the review queue, which is
    // the whole point of creating it.
    await _anki.getOrCreateCardState(template.id);
    return {
      'id': template.id,
      'type': template.type,
      'question': template.question,
    };
  }

  /// Validates the `cards` array.
  ///
  /// Strict on purpose: a card missing its question or answer cannot be
  /// reviewed, and silently dropping it would tell the user "3 cards created"
  /// when only 2 exist.
  static List<_RequestedCard> _parseCards(Object? raw) {
    if (raw == null) {
      return const [];
    }
    if (raw is! List) {
      throw ToolArgError('`cards` 必须是数组（每一项是 {question, answer, type?}）');
    }
    final cards = <_RequestedCard>[];
    for (var i = 0; i < raw.length; i++) {
      final entry = raw[i];
      if (entry is! Map) {
        throw ToolArgError('`cards[$i]` 不是对象');
      }
      final question = entry['question']?.toString().trim() ?? '';
      final answer = entry['answer']?.toString().trim() ?? '';
      if (question.isEmpty || answer.isEmpty) {
        throw ToolArgError('`cards[$i]` 缺少 question 或 answer');
      }
      final type =
          (entry['type']?.toString().trim().isNotEmpty ?? false)
              ? entry['type'].toString().trim()
              : defaultCardType;
      if (!cardTypes.contains(type)) {
        throw ToolArgError(
          '`cards[$i].type` 未知：$type。可用：${cardTypes.join(' / ')}',
        );
      }
      final hint = entry['hint']?.toString().trim();
      cards.add(_RequestedCard(
        question: question,
        answer: answer,
        type: type,
        hint: (hint == null || hint.isEmpty) ? null : hint,
      ));
    }
    return cards;
  }
}

/// Removes everything a `create_knowledge_cards` call produced.
///
/// Top-level and drift-only, like `snapshotTask` / `restoreTask`: the agent
/// loop's undo path holds the database rather than the repositories, and an
/// undo that could not reach the rows it created would leave a knowledge point
/// with no cards behind.
///
/// Returns false when the snapshot has no knowledge point id, i.e. there is
/// nothing this function can be trusted to delete.
Future<bool> deleteCreatedKnowledgeCards(
  AppDatabase db,
  Map<String, Object?> snapshot,
) async {
  final pointId = snapshot['knowledge_point_id'] as String?;
  if (pointId == null) {
    return false;
  }
  final templateIds = [
    for (final raw in (snapshot['template_ids'] as List?) ?? const [])
      if (raw is String) raw,
  ];

  await db.transaction(() async {
    if (templateIds.isNotEmpty) {
      // Review logs first: they reference the card state, which references the
      // template.
      await (db.delete(db.reviewLogs)
            ..where((t) => t.cardTemplateId.isIn(templateIds)))
          .go();
      await (db.delete(db.cardStates)
            ..where((t) => t.cardTemplateId.isIn(templateIds)))
          .go();
      await (db.delete(db.cardTemplates)..where((t) => t.id.isIn(templateIds)))
          .go();
    }
    await (db.delete(db.knowledgePoints)..where((t) => t.id.equals(pointId)))
        .go();
  });
  return true;
}
