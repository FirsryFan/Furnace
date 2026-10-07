/// The read half of the content tools: what tags, flashcards and cards exist.
///
/// Why this exists at all: the model cannot delete (or safely update) what it
/// cannot name. Before this tool the only way to address a tag or a flashcard
/// was to guess its exact name from the conversation, and a guess that missed by
/// one character ended in "找不到…" with no way forward - the tool was there but
/// unreachable in practice.
///
/// It pairs with `delete_content`: **look, then act on the id that came back.**
/// The tool is read-only ([readOnly] is true), so no permission mode asks about
/// it - looking at the user's own data is not a change to it.
library;

import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/tag_repository.dart';
import '../domain/ai_tool.dart';

/// Lists tags, flashcards, or cards, with the ids the other tools need.
class QueryContentTool extends AiTool {
  QueryContentTool({
    required AppDatabase db,
    required AnkiRepository anki,
    required TagRepository tags,
  })  : _db = db,
        _anki = anki,
        _tags = tags;

  final AppDatabase _db;
  final AnkiRepository _anki;
  final TagRepository _tags;

  /// The name the provider sees.
  static const String toolName = 'query_content';

  static const String kindTag = 'tag';
  static const String kindFlashcard = 'flashcard';
  static const String kindCard = 'card';

  static const Set<String> kinds = {kindTag, kindFlashcard, kindCard};

  static const int defaultLimit = 20;
  static const int maxLimit = 50;

  @override
  String get name => toolName;

  @override
  String get description =>
      '查看现有的标签 / 闪存卡 / 卡片，拿到它们的 id。'
      '**要删除或修改某个标签、闪存卡、卡片时，先用这个工具找到它**，不要凭记忆猜名字：'
      'kind=tag 列标签（含完整路径与父子关系）；kind=flashcard 列闪存卡（含卡片数与来源）；'
      'kind=card 列卡片（含题目、所属闪存卡）。'
      'filter 是可选的关键词（对名称/标题/题目做不区分大小写的包含匹配），limit 默认 $defaultLimit、上限 $maxLimit。'
      '返回里的 id 可以直接喂给 delete_content。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'kind': {
            'type': 'string',
            'enum': kinds.toList(),
            'description': '要查什么',
          },
          'filter': {
            'type': 'string',
            'description': '可选关键词：按名称/标题/题目做包含匹配',
          },
          'limit': {
            'type': 'integer',
            'description': '最多返回几条，默认 $defaultLimit，上限 $maxLimit',
          },
        },
        'required': <String>['kind'],
      };

  /// Neutral risk: this tool has no actions and never writes.
  @override
  ToolRisk riskFor(String action) => ToolRisk.write; // unused: no actions

  @override
  bool reversibleFor(String action) => true;

  /// Reading is not acting, so no mode asks about it (see [AiTool.readOnly]).
  @override
  bool get readOnly => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    final args = ToolArgs(invocation.arguments);
    try {
      final kind = args.requireString('kind');
      if (!kinds.contains(kind)) {
        return ToolResult.failure(
          '不支持的 kind: $kind（只允许 ${kinds.join(' / ')}）',
        );
      }
      final filter = args.optString('filter')?.trim().toLowerCase();
      final limit = _limitOf(args);

      final items = switch (kind) {
        kindTag => await _tagRows(filter),
        kindFlashcard => await _flashcardRows(filter),
        _ => await _cardRows(filter),
      };
      final shown = items.take(limit).toList();

      return ToolResult(
        ok: true,
        summary: shown.isEmpty
            ? '没有找到符合条件的${_label(kind)}'
            : '找到 ${items.length} 个${_label(kind)}'
                '${items.length > shown.length ? '（先给前 ${shown.length} 个）' : ''}',
        modelResult: {
          'kind': kind,
          'count': items.length,
          'returned': shown.length,
          'items': shown,
        },
      );
    } on ToolArgError catch (e) {
      // Caused by the model, so it becomes something it can read and correct.
      return ToolResult.failure(e.message);
    }
  }

  int _limitOf(ToolArgs args) {
    final raw = args.optInt('limit') ?? defaultLimit;
    if (raw < 1) {
      return defaultLimit;
    }
    return raw > maxLimit ? maxLimit : raw;
  }

  static String _label(String kind) => switch (kind) {
        kindTag => '标签',
        kindFlashcard => '闪存卡',
        _ => '卡片',
      };

  /// Tags with their path, parent and how many objects hang off them.
  Future<List<Map<String, Object?>>> _tagRows(String? filter) async {
    final all = await _tags.getAllTags();
    final links = await _db.select(_db.objectTags).get();
    final linkCount = <String, int>{};
    for (final link in links) {
      linkCount[link.tagId] = (linkCount[link.tagId] ?? 0) + 1;
    }
    final rows = [
      for (final tag in all)
        if (filter == null ||
            tag.name.toLowerCase().contains(filter) ||
            (tag.path ?? '').toLowerCase().contains(filter))
          {
            'id': tag.id,
            'name': tag.name,
            'path': tag.path ?? tag.name,
            'parent_id': tag.parentId,
            'linked_objects': linkCount[tag.id] ?? 0,
          },
    ];
    // Paths sort the tree into reading order: 物理 / 物理/力学 / 物理/力学/牛顿.
    rows.sort((a, b) =>
        (a['path']! as String).compareTo(b['path']! as String));
    return rows;
  }

  /// Flashcards with how many cards each one owns.
  Future<List<Map<String, Object?>>> _flashcardRows(String? filter) async {
    final points = await _anki.getKnowledgePoints();
    final rows = <Map<String, Object?>>[];
    for (final point in points) {
      if (filter != null && !point.title.toLowerCase().contains(filter)) {
        continue;
      }
      final templates = await _anki.getTemplatesForKnowledgePoint(point.id);
      rows.add({
        'id': point.id,
        'title': point.title,
        'source': point.source,
        'card_count': templates.length,
      });
    }
    return rows;
  }

  /// Cards with the flashcard they belong to, so a delete is unambiguous.
  Future<List<Map<String, Object?>>> _cardRows(String? filter) async {
    final points = await _anki.getKnowledgePoints();
    final titleById = {for (final point in points) point.id: point.title};
    final rows = await _db.select(_db.cardTemplates).get();
    final items = <Map<String, Object?>>[];
    for (final row in rows) {
      if (filter != null && !row.question.toLowerCase().contains(filter)) {
        continue;
      }
      items.add({
        'id': row.id,
        'flashcard_id': row.knowledgePointId,
        'flashcard_title': titleById[row.knowledgePointId] ?? '',
        'type': row.type,
        'question': row.question,
      });
    }
    return items;
  }
}
