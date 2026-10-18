/// The AI's write path into **card groups** (*卡组*): "put these cards into 第1节".
///
/// Why this file exists: a 卡组 *is* a tag (docs/PROGRESS 轮次十七), so the review
/// plan can only give a daily target to cards that carry a tag. The app has had
/// tags, cards and card-group plans for a long time - but the model could create
/// a flashcard, and could not say **which group it belongs to**. On a real
/// database that gap looked like this: 269 flashcards, 114 tags, and
/// `object_tags` empty - every card sat outside every group, so no daily target
/// could ever reach one of them (`query_content` could not even show the gap).
///
/// Two write tools close it:
///
///  * [LinkCardTagsTool] attaches flashcards to tags. It has a bulk mode that
///    reads the tag path out of the flashcard's own `source` text (the importer
///    already wrote `…｜生物/高中生物/必修1 分子与细胞/第1章 走近细胞/第1节 …`),
///    so 269 cards can be grouped by one call instead of 269 screen round-trips.
///    `dry_run` defaults to true: a wrong guess must cost a preview, not a mess.
///  * [ManageReviewPlanTool] sets/clears a group's daily target, which is what
///    makes "一天多少个卡" answerable at all.
///
/// Both are ordinary reversible writes (undo = remove what they made / put the
/// plan row back), so they go through the same [ApprovalEngine] as
/// `create_tags` instead of needing a gate of their own.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/review_plan_repository.dart';
import '../../../data/repositories/tag_repository.dart';
import '../domain/ai_tool.dart';

/// The `object_type` used for a knowledge point in `object_tags`.
///
/// Same value as the Knowledge screen and `TagRepository`'s untagged queries;
/// spelled once here instead of four times.
const String kKnowledgePointObjectType = 'knowledge_point';

/// Separators the importers put between a `source` label and the tag path:
/// the full-width vertical bar used by the Chinese corpus, and ASCII `|` for
/// sources that were written by hand.
const List<String> _sourceSeparators = ['｜', '|'];

/// One tag the model may have named by id, by full path, or by a unique name.
class _TagMatch {
  const _TagMatch(this.tag,
      {required this.score, this.ambiguousWith = const []});

  final Tag tag;

  /// How specific the match is: the number of path segments that lined up, so
  /// `…/第1节` beats `…/第1章` for the same card.
  final int score;

  /// Other tags that matched equally well. Non-empty means "do not guess".
  final List<Tag> ambiguousWith;
}

/// Links flashcards to tags (card groups).
class LinkCardTagsTool extends AiTool {
  LinkCardTagsTool({
    required AppDatabase db,
    required AnkiRepository anki,
    required TagRepository tags,
  })  : _db = db,
        _anki = anki,
        _tags = tags;

  final AppDatabase _db;
  final AnkiRepository _anki;
  final TagRepository _tags;

  /// The name the provider sees and the agent loop recognises for undo.
  static const String toolName = 'link_card_tags';

  /// How many cards one call may touch. The import that motivated this tool had
  /// 269 ungrouped cards; a cap of 200 would have forced two calls for no reason,
  /// so the ceiling is 500 and the *default* stays a preview-sized 50.
  static const int defaultLimit = 50;
  static const int maxLimit = 500;

  /// How many sample rows the result shows per category.
  static const int sampleSize = 20;

  @override
  String get name => toolName;

  @override
  String get description => '把闪存卡挂到卡组（标签）上。卡组就是标签：没有标签的卡不属于任何卡组，'
      '任何每日新卡/复习计划都管不到它。两种用法：'
      '① 显式：给 tag（标签 id 或完整路径，先 query_content(kind: tag) 查）'
      '和 card_ids（闪存卡 id，先 query_content(kind: flashcard) 查），逐张挂；'
      '② 批量：from_source_paths=true，工具会读每张**未分组**闪存卡的 source，'
      '取最后一个「｜」后面的完整路径，与现有标签路径做“尾部相等”匹配：'
      '标签路径是源路径的结尾（源写全了）或源路径是标签路径的结尾（源只写到某一级）'
      '都能匹配；前者取最长者，后者若有多条同样说得通就报歧义、不猜。'
      '批量模式默认 dry_run=true，只返回会挂哪些、哪些匹配不到；确认后传 dry_run=false 才写。'
      '返回 linked / already / unmatched / ambiguous 与样例。挂错了可以在这条对话里撤销。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'tag': {
            'type': 'string',
            'description': '标签 id 或完整路径（显式模式必填；批量模式忽略）',
          },
          'card_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '要挂的闪存卡 id 列表（显式模式必填）',
          },
          'from_source_paths': {
            'type': 'boolean',
            'description': 'true 时批量扫描未分组的卡，从 source 里的标签路径自动匹配',
          },
          'dry_run': {
            'type': 'boolean',
            'description': '批量模式默认 true：只预览并报告，不写库；传 false 才真的挂',
          },
          'limit': {
            'type': 'integer',
            'description': '最多处理多少张卡，默认 $defaultLimit，上限 $maxLimit',
          },
        },
        'required': <String>[],
      };

  /// A reversible write: undo removes exactly the links it made.
  @override
  ToolRisk riskFor(String action) => ToolRisk.write;

  @override
  bool reversibleFor(String action) => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    final args = ToolArgs(invocation.arguments);
    try {
      final fromSource = args.optBool('from_source_paths') ?? false;
      final dryRun = args.optBool('dry_run') ?? true;
      final limit = _limitOf(args);
      if (fromSource) {
        return await _linkFromSourcePaths(dryRun: dryRun, limit: limit);
      }
      return await _linkExplicit(args);
    } on ToolArgError catch (e) {
      // Caused by the model, so it becomes a result it can read and correct.
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

  /// `tag` + `card_ids`: one deliberate link per card, all or nothing.
  Future<ToolResult> _linkExplicit(ToolArgs args) async {
    final tagRaw = args.optString('tag');
    if (tagRaw == null) {
      throw ToolArgError(
        '显式挂卡需要 `tag`（标签 id 或完整路径）；'
        '批量从 source 路径匹配请传 from_source_paths: true',
      );
    }
    final cardIds = args.optStringList('card_ids');
    if (cardIds == null) {
      throw ToolArgError(
          '显式挂卡需要 `card_ids`（先用 query_content(kind: flashcard) 查 id）');
    }
    final tag = await resolveTagForTool(_tags, tagRaw);

    // Every id must exist before the first write: a call that links 3 of 5 cards
    // is a half-done state the model then has to detect and repair.
    final points = await _anki.getKnowledgePoints();
    final known = {for (final point in points) point.id: point};
    final unknown = [
      for (final id in cardIds)
        if (!known.containsKey(id)) id
    ];
    if (unknown.isNotEmpty) {
      throw ToolArgError(
        '这些 id 不是库里的闪存卡：${unknown.join('、')}'
        '（用 query_content(kind: flashcard, filter: ...) 拿真实 id）',
      );
    }

    final existing = await _existingLinks(
      tagId: tag.id,
      objectIds: cardIds,
    );
    final added = <Map<String, Object?>>[];
    for (final id in cardIds) {
      if (existing.contains(id)) {
        continue;
      }
      await _tags.addTagToObject(
        tagId: tag.id,
        objectType: kKnowledgePointObjectType,
        objectId: id,
      );
      added.add({
        'tag_id': tag.id,
        'object_type': kKnowledgePointObjectType,
        'object_id': id
      });
    }

    return ToolResult(
      ok: true,
      summary: added.isEmpty
          ? '这些卡本来就在卡组「${tag.path ?? tag.name}」里，没有新增'
          : '已把 ${added.length} 张卡挂到卡组「${tag.path ?? tag.name}」'
              '${existing.isNotEmpty ? '（${existing.length} 张之前就在里面）' : ''}',
      modelResult: {
        'mode': 'explicit',
        'tag': {'id': tag.id, 'path': tag.path ?? tag.name},
        'linked': added.length,
        'already': existing.length,
        'cards': [
          for (final id in cardIds.take(sampleSize))
            {'id': id, 'title': known[id]!.title},
        ],
      },
      afterJson: jsonEncode({
        'version': 1,
        'links': added,
      }),
    );
  }

  /// Bulk mode: every ungrouped card whose `source` names a known tag path.
  Future<ToolResult> _linkFromSourcePaths({
    required bool dryRun,
    required int limit,
  }) async {
    final tags = await _tags.getAllTags();
    if (tags.isEmpty) {
      throw ToolArgError(
        '库里还没有标签，卡组就是标签：先用 create_tags 建标签树，再回来挂卡',
      );
    }
    final allLinks = await _db.select(_db.objectTags).get();
    final grouped = {
      for (final link in allLinks)
        if (link.objectType == kKnowledgePointObjectType) link.objectId,
    };
    final points = [
      for (final point in await _anki.getKnowledgePoints())
        if (!grouped.contains(point.id)) point,
    ];
    final scanned = points.take(limit).toList();

    final matches = <Map<String, Object?>>[];
    final ambiguous = <Map<String, Object?>>[];
    final unmatched = <Map<String, Object?>>[];
    final pendingLinks = <Map<String, Object?>>[];

    for (final point in scanned) {
      final derived = _pathFromSource(point.source);
      if (derived == null) {
        unmatched.add({
          'card_id': point.id,
          'title': point.title,
          'reason': 'source 里没有「｜」分隔的标签路径',
        });
        continue;
      }
      final match = _matchTagPath(tags, derived);
      if (match == null) {
        unmatched.add({
          'card_id': point.id,
          'title': point.title,
          'derived_path': derived,
          'reason': '没有路径相同或前缀（尾部）相同的标签',
        });
        continue;
      }
      if (match.ambiguousWith.isNotEmpty) {
        ambiguous.add({
          'card_id': point.id,
          'title': point.title,
          'derived_path': derived,
          'candidates': [
            for (final candidate in match.ambiguousWith)
              candidate.path ?? candidate.name,
          ],
        });
        continue;
      }
      final tag = match.tag;
      matches.add({
        'card_id': point.id,
        'title': point.title,
        'derived_path': derived,
        'tag_id': tag.id,
        'tag_path': tag.path ?? tag.name,
      });
      pendingLinks.add({
        'tag_id': tag.id,
        'object_type': kKnowledgePointObjectType,
        'object_id': point.id,
      });
    }

    if (!dryRun) {
      for (final link in pendingLinks) {
        await _tags.addTagToObject(
          tagId: link['tag_id']! as String,
          objectType: kKnowledgePointObjectType,
          objectId: link['object_id']! as String,
        );
      }
    }

    final remaining = points.length - scanned.length;
    return ToolResult(
      ok: true,
      summary: dryRun
          ? '预览：扫到 ${scanned.length} 张未分组的卡，'
              '${matches.length} 张可以按 source 路径挂进卡组，'
              '${ambiguous.length} 张有歧义、${unmatched.length} 张匹配不到'
              '${remaining > 0 ? '（还有 $remaining 张没扫，可加大 limit）' : ''}。'
              '确认后传 dry_run=false 才写库。'
          : '已按 source 路径把 ${matches.length} 张卡挂进卡组'
              '${ambiguous.isNotEmpty ? '，${ambiguous.length} 张因歧义没动' : ''}'
              '${unmatched.isNotEmpty ? '，${unmatched.length} 张匹配不到' : ''}',
      modelResult: {
        'mode': 'source_paths',
        'dry_run': dryRun,
        'scanned': scanned.length,
        'remaining': remaining,
        'matched': matches.length,
        'linked': dryRun ? 0 : matches.length,
        'ambiguous': ambiguous.length,
        'unmatched': unmatched.length,
        'matches': matches.take(sampleSize).toList(),
        'ambiguous_samples': ambiguous.take(sampleSize).toList(),
        'unmatched_samples': unmatched.take(sampleSize).toList(),
      },
      // Preview writes nothing, so there is nothing to undo.
      afterJson: dryRun || matches.isEmpty
          ? null
          : jsonEncode({'version': 1, 'links': pendingLinks}),
    );
  }

  /// The ids of [objectIds] that already point at [tagId].
  Future<Set<String>> _existingLinks({
    required String tagId,
    required Iterable<String> objectIds,
  }) async {
    final ids = objectIds.toSet().toList();
    if (ids.isEmpty) {
      return const {};
    }
    final rows = await (_db.select(_db.objectTags)
          ..where(
            (t) =>
                t.tagId.equals(tagId) &
                t.objectType.equals(kKnowledgePointObjectType) &
                t.objectId.isIn(ids),
          ))
        .get();
    return {for (final row in rows) row.objectId};
  }
}

/// Sets or clears one card group's daily target.
class ManageReviewPlanTool extends AiTool {
  ManageReviewPlanTool({
    required TagRepository tags,
    required ReviewPlanRepository plans,
  })  : _tags = tags,
        _plans = plans;

  final TagRepository _tags;
  final ReviewPlanRepository _plans;

  /// The name the provider sees and the agent loop recognises for undo.
  static const String toolName = 'manage_review_plan';

  static const String actionSet = 'set';
  static const String actionClear = 'clear';

  static const Set<String> actions = {actionSet, actionClear};

  @override
  String get name => toolName;

  @override
  String get description => '给一个卡组（标签）设或清每天的任务量：新卡多少张、旧卡复习多少张。'
      '这是「一天多少个卡」的唯一设置口——没设的卡组不限量，设 0 有特殊含义：'
      'new_cards_per_day=0 表示这个卡组今天不学新卡，review_cards_per_day=0 表示旧卡不限量。'
      'tag 用 id 或完整路径（先 query_content(kind: tag) 查）。'
      '看现有设置用 query_content(kind: review_plan)；设完可以在这条对话里撤销。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': actions.toList(),
            'description': 'set=设置/覆盖，clear=清掉（回到不限量）',
          },
          'tag': {
            'type': 'string',
            'description':
                '卡组（标签）id 或完整路径，例如 `生物/高中生物/必修1 分子与细胞/第1章 走近细胞/第1节 细胞是生命活动的基本单位`',
          },
          'new_cards_per_day': {
            'type': 'integer',
            'description': '每天新卡上限（set 必填，>=0；0=不学新卡）',
          },
          'review_cards_per_day': {
            'type': 'integer',
            'description': '每天复习上限（set 必填，>=0；0=不限量）',
          },
        },
        'required': <String>['action', 'tag'],
      };

  @override
  ToolRisk riskFor(String action) => ToolRisk.write;

  @override
  bool reversibleFor(String action) => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    final args = ToolArgs(invocation.arguments);
    try {
      final action = args.requireAction(actions);
      final tagRaw = args.requireString('tag');
      final tag = await resolveTagForTool(_tags, tagRaw);
      final tagPath = tag.path ?? tag.name;
      final before = await _planSnapshot(tag.id);

      if (action == actionClear) {
        await _plans.clearGroupPlan(tag.id);
        return ToolResult(
          ok: true,
          summary: '已清掉卡组「$tagPath」的每日任务量（回到不限量）',
          modelResult: {
            'action': action,
            'tag': {'id': tag.id, 'path': tagPath},
            'plan': null,
          },
          beforeJson: jsonEncode(before),
        );
      }

      final newCards = args.requireInt('new_cards_per_day');
      final reviewCards = args.requireInt('review_cards_per_day');
      if (newCards < 0 || reviewCards < 0) {
        throw ToolArgError(
          '`new_cards_per_day` 与 `review_cards_per_day` 不能是负数'
          '（不想学新卡用 0，不要用 -1）',
        );
      }
      await _plans.setGroupPlan(
        tagId: tag.id,
        newCardsPerDay: newCards,
        reviewCardsPerDay: reviewCards,
      );
      return ToolResult(
        ok: true,
        summary: '已设置卡组「$tagPath」：每天新卡 $newCards 张、复习 $reviewCards 张'
            '${reviewCards == 0 ? '（0=旧卡不限量）' : ''}',
        modelResult: {
          'action': action,
          'tag': {'id': tag.id, 'path': tagPath},
          'plan': {
            'new_cards_per_day': newCards,
            'review_cards_per_day': reviewCards,
          },
        },
        // The old row is what undo puts back (or, for a first-time set, removes).
        beforeJson: jsonEncode(before),
      );
    } on ToolArgError catch (e) {
      return ToolResult.failure(e.message);
    }
  }

  /// What is stored for [tagId] right now, in the shape [restoreReviewPlan]
  /// expects: `{'tag_id': ..., 'plan': null | {new_cards_per_day, ...}}`.
  Future<Map<String, Object?>> _planSnapshot(String tagId) async {
    final plans = await _plans.groupPlans();
    for (final plan in plans) {
      if (plan.tagId == tagId) {
        return {
          'tag_id': tagId,
          'plan': {
            'new_cards_per_day': plan.newCardsPerDay,
            'review_cards_per_day': plan.reviewCardsPerDay,
          },
        };
      }
    }
    return {'tag_id': tagId, 'plan': null};
  }
}

/// Resolves a tag the model named by id, path, or unique name.
///
/// Shared by both tools above so "id first, then path, then name" is spelled
/// once: a call that resolves differently in the two tools would be able to set a
/// plan on one tag and link cards to another.
Future<Tag> resolveTagForTool(TagRepository tags, String raw) async {
  final text = raw.trim();
  if (text.isEmpty) {
    throw ToolArgError('`tag` 不能为空');
  }
  final byId = await tags.getTagById(text);
  if (byId != null) {
    return byId;
  }
  final byPath = await tags.getTagByPath(text);
  if (byPath != null) {
    return byPath;
  }
  final all = await tags.getAllTags();
  final exact = [
    for (final tag in all)
      if (tag.name == text) tag
  ];
  if (exact.length == 1) {
    return exact.single;
  }
  final folded = [
    for (final tag in all)
      if (tag.name.toLowerCase() == text.toLowerCase()) tag,
  ];
  if (folded.length == 1) {
    return folded.single;
  }
  final candidates = exact.length > 1 ? exact : folded;
  if (candidates.length > 1) {
    throw ToolArgError(
      '标签名「$text」对应多个标签，请改用完整路径：'
      '${[for (final tag in candidates) tag.path ?? tag.name].join(' / ')}',
    );
  }
  throw ToolArgError(
    '找不到标签「$text」（可用 query_content(kind: tag) 查看现有路径）',
  );
}

/// The tag path written at the end of a `source` string, or null when there is
/// none.
///
/// The corpus importers write `课本 P32｜生物/高中生物/必修1 分子与细胞/…`; everything
/// after the last separator is the path. Only the path is used - the label in
/// front of it ("课本 P32") is free text and must not affect matching.
String? _pathFromSource(String? source) {
  if (source == null) {
    return null;
  }
  final text = source.trim();
  if (text.isEmpty) {
    return null;
  }
  var cut = -1;
  for (final separator in _sourceSeparators) {
    final index = text.lastIndexOf(separator);
    if (index > cut) {
      cut = index;
    }
  }
  if (cut < 0) {
    return null;
  }
  return _cleanPath(text.substring(cut + 1));
}

String? _cleanPath(String raw) {
  final text = raw
      .trim()
      .replaceAll('「', '')
      .replaceAll('」', '')
      .replaceAll('"', '')
      .replaceAll("'", '')
      .trim()
      .replaceAll(RegExp(r'/+$'), '');
  return text.isEmpty ? null : text;
}

List<String> _segments(String path) => [
      for (final part in path.split('/'))
        if (part.trim().isNotEmpty) part.trim(),
    ];

/// Finds the tag that best explains [derived].
///
/// Two directions, because the corpus is not consistent about depth:
/// * the tag path is the end of the derived path (source writes the full path) -
///   the longest such tag wins;
/// * the derived path is the end of the tag path (source stopped at a level, e.g.
///   only `第1节 细胞是生命活动的基本单位` while the tag tree goes deeper) - a
///   single such tag is used, two or more are reported as ambiguous because the
///   source alone cannot tell them apart.
///
/// Returns null when nothing matches. Guessing an ambiguity would attach 40 cards
/// to the wrong group in one call, so it never guesses.
_TagMatch? _matchTagPath(List<Tag> tags, String derived) {
  final wanted = _segments(derived);
  if (wanted.isEmpty) {
    return null;
  }

  // Exact full path first: only one tag can own a path, so there is no ambiguity.
  for (final tag in tags) {
    final path = _cleanPath(tag.path ?? tag.name);
    if (path != null && path == derived) {
      return _TagMatch(tag, score: wanted.length);
    }
  }

  // The tag is a suffix of the source path: most specific tag wins. Two tags of
  // the same length cannot both be suffixes of the same path unless they are the
  // same path, so this pass has no tie to report.
  Tag? deepest;
  var bestScore = 0;
  for (final tag in tags) {
    final path = _cleanPath(tag.path ?? tag.name);
    if (path == null) {
      continue;
    }
    final candidate = _segments(path);
    if (candidate.isEmpty || candidate.length > wanted.length) {
      continue;
    }
    if (!_sameTail(wanted, candidate)) {
      continue;
    }
    if (candidate.length > bestScore) {
      deepest = tag;
      bestScore = candidate.length;
    }
  }
  if (deepest != null) {
    return _TagMatch(deepest, score: bestScore);
  }

  // The source path is a suffix of deeper tag paths: usable only when it names
  // exactly one tag.
  final containing = <Tag>[];
  for (final tag in tags) {
    final path = _cleanPath(tag.path ?? tag.name);
    if (path == null) {
      continue;
    }
    final candidate = _segments(path);
    if (candidate.length <= wanted.length) {
      continue;
    }
    if (_sameTail(candidate, wanted)) {
      containing.add(tag);
    }
  }
  if (containing.isEmpty) {
    return null;
  }
  return _TagMatch(
    containing.first,
    score: wanted.length,
    ambiguousWith: containing.length > 1 ? containing : const [],
  );
}

/// True when [shorter] is the last segments of [longer].
bool _sameTail(List<String> longer, List<String> shorter) {
  if (shorter.length > longer.length) {
    return false;
  }
  var i = longer.length - shorter.length;
  var j = 0;
  while (i < longer.length) {
    if (longer[i] != shorter[j]) {
      return false;
    }
    i++;
    j++;
  }
  return true;
}

/// Undo for one [LinkCardTagsTool] call: removes exactly the links it made.
Future<bool> unlinkCardTags(
  AppDatabase db,
  Map<String, Object?> snapshot,
) async {
  final raw = snapshot['links'];
  if (raw is! List) {
    return false;
  }
  await db.transaction(() async {
    for (final entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final tagId = entry['tag_id']?.toString();
      final objectType = entry['object_type']?.toString();
      final objectId = entry['object_id']?.toString();
      if (tagId == null || objectType == null || objectId == null) {
        continue;
      }
      await (db.delete(db.objectTags)
            ..where(
              (t) =>
                  t.tagId.equals(tagId) &
                  t.objectType.equals(objectType) &
                  t.objectId.equals(objectId),
            ))
          .go();
    }
  });
  return true;
}

/// Undo for one [ManageReviewPlanTool] call: puts the previous row back.
///
/// A first-time `set` has no old row, so undo clears the plan instead of writing
/// a plan that never existed.
Future<bool> restoreReviewPlan(
  AppDatabase db,
  Map<String, Object?> snapshot,
) async {
  final tagId = snapshot['tag_id']?.toString();
  if (tagId == null) {
    return false;
  }
  final repository = ReviewPlanRepository(db, AnkiRepository(db));
  final plan = snapshot['plan'];
  if (plan is! Map) {
    await repository.clearGroupPlan(tagId);
    return true;
  }
  final newCards = plan['new_cards_per_day'];
  final reviewCards = plan['review_cards_per_day'];
  if (newCards is! int || reviewCards is! int) {
    return false;
  }
  await repository.setGroupPlan(
    tagId: tagId,
    newCardsPerDay: newCards,
    reviewCardsPerDay: reviewCards,
  );
  return true;
}
