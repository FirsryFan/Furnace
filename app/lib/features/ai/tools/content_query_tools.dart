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
import '../../../data/repositories/review_plan_repository.dart';
import '../../../data/repositories/tag_repository.dart';
import '../domain/ai_tool.dart';

/// Lists tags, flashcards, cards or card-group plans, with the ids the other
/// tools need.
class QueryContentTool extends AiTool {
  QueryContentTool({
    required AppDatabase db,
    required AnkiRepository anki,
    required TagRepository tags,
    required ReviewPlanRepository plans,
  })  : _db = db,
        _anki = anki,
        _tags = tags,
        _plans = plans;

  final AppDatabase _db;
  final AnkiRepository _anki;
  final TagRepository _tags;
  final ReviewPlanRepository _plans;

  /// The name the provider sees.
  static const String toolName = 'query_content';

  static const String kindTag = 'tag';
  static const String kindFlashcard = 'flashcard';
  static const String kindCard = 'card';
  static const String kindReviewPlan = 'review_plan';

  static const Set<String> kinds = {
    kindTag,
    kindFlashcard,
    kindCard,
    kindReviewPlan,
  };

  static const int defaultLimit = 20;
  static const int maxLimit = 50;

  @override
  String get name => toolName;

  @override
  String get description => '查看现有的标签 / 闪存卡 / 卡片 / 卡组计划，拿到它们的 id 与归属。'
      '**要删除或修改某个标签、闪存卡、卡片时，先用这个工具找到它**，不要凭记忆猜名字：'
      'kind=tag 列标签（含完整路径、父子关系、挂了几张闪存卡）；'
      'kind=flashcard 列闪存卡（含卡片数、来源、**已挂的标签 tags 与 untagged**）；'
      'kind=card 列卡片（含题目、所属闪存卡）；'
      'kind=review_plan 列已设的卡组每日任务量，以及还有多少张卡没挂进任何卡组。'
      'filter 是可选的关键词（对名称/标题/题目/路径做不区分大小写的包含匹配），'
      'limit 默认 $defaultLimit、上限 $maxLimit。'
      '返回里的 id 可以直接喂给 delete_content、link_card_tags、manage_review_plan。';

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
        kindTag => _Rows(await _tagRows(filter)),
        kindFlashcard => _Rows(await _flashcardRows(filter)),
        kindReviewPlan => await _reviewPlanRows(filter),
        _ => _Rows(await _cardRows(filter)),
      };
      final shown = items.items.take(limit).toList();

      return ToolResult(
        ok: true,
        summary: shown.isEmpty
            ? '没有找到符合条件的${_label(kind)}'
            : '找到 ${items.items.length} 个${_label(kind)}'
                '${items.items.length > shown.length ? '（先给前 ${shown.length} 个）' : ''}',
        modelResult: {
          'kind': kind,
          'count': items.items.length,
          'returned': shown.length,
          'items': shown,
          ...items.extra,
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
        kindReviewPlan => '卡组计划',
        _ => '卡片',
      };

  /// Tags with their path, parent, and how many objects - flashcards
  /// specifically - hang off them.
  Future<List<Map<String, Object?>>> _tagRows(String? filter) async {
    final all = await _tags.getAllTags();
    final links = await _db.select(_db.objectTags).get();
    final linkCount = <String, int>{};
    final flashcardCount = <String, int>{};
    for (final link in links) {
      linkCount[link.tagId] = (linkCount[link.tagId] ?? 0) + 1;
      // Same object_type the Knowledge screen writes; a tag that "has 0
      // flashcards" is a whole card group with nothing in it.
      if (link.objectType == 'knowledge_point') {
        flashcardCount[link.tagId] = (flashcardCount[link.tagId] ?? 0) + 1;
      }
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
            'linked_flashcards': flashcardCount[tag.id] ?? 0,
          },
    ];
    // Paths sort the tree into reading order: 物理 / 物理/力学 / 物理/力学/牛顿.
    rows.sort((a, b) => (a['path']! as String).compareTo(b['path']! as String));
    return rows;
  }

  /// Flashcards with the tags they belong to (their card groups).
  ///
  /// Before this the answer was "id / title / source / card_count" only, so a
  /// model asked to "把这些卡归进卡组" could neither tell which cards were
  /// already grouped nor address the groups - it had to guess, and a guess is
  /// exactly what produced 269 ungrouped cards.
  Future<List<Map<String, Object?>>> _flashcardRows(String? filter) async {
    final points = await _anki.getKnowledgePoints();
    final tagById = {for (final tag in await _tags.getAllTags()) tag.id: tag};
    final links = await _db.select(_db.objectTags).get();
    final tagsByPoint = <String, List<Map<String, Object?>>>{};
    for (final link in links) {
      if (link.objectType != 'knowledge_point') {
        continue;
      }
      final tag = tagById[link.tagId];
      if (tag == null) {
        continue;
      }
      tagsByPoint.putIfAbsent(link.objectId, () => []).add({
        'id': tag.id,
        'name': tag.name,
        'path': tag.path ?? tag.name,
      });
    }
    final rows = <Map<String, Object?>>[];
    for (final point in points) {
      if (filter != null && !point.title.toLowerCase().contains(filter)) {
        continue;
      }
      final templates = await _anki.getTemplatesForKnowledgePoint(point.id);
      final pointTags = tagsByPoint[point.id] ?? const <Map<String, Object?>>[];
      rows.add({
        'id': point.id,
        'title': point.title,
        'source': point.source,
        'card_count': templates.length,
        'tags': pointTags,
        'tag_count': pointTags.length,
        'untagged': pointTags.isEmpty,
      });
    }
    return rows;
  }

  /// The configured daily targets, plus the number of cards no target can reach.
  Future<_Rows> _reviewPlanRows(String? filter) async {
    final plans = await _plans.groupPlans();
    final rows = [
      for (final plan in plans)
        if (filter == null || plan.tagPath.toLowerCase().contains(filter))
          {
            'tag_id': plan.tagId,
            'tag_path': plan.tagPath,
            'new_cards_per_day': plan.newCardsPerDay,
            'review_cards_per_day': plan.reviewCardsPerDay,
          },
    ];
    final ungrouped = await _tags.countKnowledgePointsWithoutTags();
    final total = (await _anki.getKnowledgePoints()).length;
    return _Rows(
      rows,
      extra: {
        'total_flashcards': total,
        'ungrouped_flashcards': ungrouped,
        'note': '未设每日计划的卡组不限量；new_cards_per_day=0 表示不学新卡，'
            'review_cards_per_day=0 表示旧卡不限量。设置用 manage_review_plan，'
            '把卡挂进卡组用 link_card_tags。',
      },
    );
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

/// One kind's rows plus the extra top-level fields that kind adds.
///
/// Most kinds are just a list; `review_plan` also reports how many cards no
/// target can reach, and keeping that next to the rows is what makes the answer
/// to "为什么设了每日计划还是学不到这些卡" one call away.
class _Rows {
  const _Rows(this.items, {this.extra = const {}});

  final List<Map<String, Object?>> items;
  final Map<String, Object?> extra;
}
