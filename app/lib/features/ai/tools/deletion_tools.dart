/// The AI's delete path: tags, single cards, and whole flashcards.
///
/// Deletion is the one thing the design never lets run without the user
/// (AI_DESIGN D12: `destructive` is never `executeNow`, in any permission
/// mode), so this tool is built around two properties rather than around the
/// delete call itself:
///
///  * **every call is reversible.** The rows are read *before* anything is
///    removed and the exact set goes into `ai_actions.before_json`; undo writes
///    them back with the same `restoreTable` the `.tfpkg` import uses. A delete
///    the user regrets is a click, not a lost study history.
///  * **the model never guesses which thing to delete.** It may address a
///    target by id, or by name/question/title; an exact match on more than one
///    row is refused with the candidate list instead of picking one. Deleting
///    the wrong tag silently would take its whole subtree with it.
///
/// The cascade itself is delegated to the repositories (`TagRepository.deleteTag`,
/// `AnkiRepository.deleteTemplate` / `deleteKnowledgePoint`) so the AI path and
/// the UI path cannot disagree about what "delete" means.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/tag_repository.dart';
import '../domain/ai_tool.dart';

/// Deletes one tag, one card, or one whole flashcard, undoably.
class DeleteContentTool extends AiTool {
  DeleteContentTool({
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
  static const String toolName = 'delete_content';

  static const String kindTag = 'tag';
  static const String kindCard = 'card';
  static const String kindFlashcard = 'flashcard';

  static const Set<String> kinds = {kindTag, kindCard, kindFlashcard};

  @override
  String get name => toolName;

  @override
  String get description =>
      '删除标签、单张卡片，或整张闪存卡。'
      '**这是破坏性操作：无论权限模式如何，每一条都需要用户单独确认**，所以只在用户明确要求删除时才调用。'
      'kind=tag 删除标签（连同它的全部子标签和关联）；'
      'kind=card 删除一张卡片；'
      'kind=flashcard 删除一张闪存卡（连同它的全部卡片与复习状态）。'
      '定位目标优先用 id（可从之前的工具结果里拿）；也可以用 name（标签名）/question（卡片的题目）/'
      'title（闪存卡标题）做精确匹配——如果匹配到多条，会拒绝执行并列出候选，让你改用 id。'
      '删错了可以让用户在这条对话里一键撤销。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'kind': {
            'type': 'string',
            'enum': kinds.toList(),
            'description': '要删除什么',
          },
          'id': {
            'type': 'string',
            'description': '目标 id（优先用它；三种 kind 都支持）',
          },
          'name': {
            'type': 'string',
            'description': 'kind=tag 时可代替 id：标签名（精确匹配）',
          },
          'question': {
            'type': 'string',
            'description': 'kind=card 时可代替 id：卡片题目（精确匹配，需与库里完全一致）',
          },
          'title': {
            'type': 'string',
            'description': 'kind=flashcard 时可代替 id：闪存卡标题（精确匹配）',
          },
        },
        'required': <String>['kind'],
      };

  /// Everything this tool does is destructive; there is no safe subset.
  @override
  ToolRisk riskFor(String action) => ToolRisk.destructive;

  /// True because the before-snapshot restores the exact deleted rows. This is
  /// what the ledger needs in order to offer the user an undo at all.
  @override
  bool reversibleFor(String action) => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    final args = ToolArgs(invocation.arguments);
    try {
      final kind = args.requireString('kind');
      return switch (kind) {
        kindTag => await _deleteTag(args),
        kindCard => await _deleteCard(args),
        kindFlashcard => await _deleteFlashcard(args),
        _ => ToolResult.failure(
            '不支持的 kind: $kind（只允许 ${kinds.join(' / ')}）',
          ),
      };
    } on ToolArgError catch (e) {
      // Caused by the model, so it becomes something it can read and correct.
      return ToolResult.failure(e.message);
    }
  }

  // --- tags ---------------------------------------------------------------

  Future<ToolResult> _deleteTag(ToolArgs args) async {
    final tag = await _resolveTag(args);
    // `deleteTag` removes the whole subtree, so the snapshot has to hold the
    // subtree too - restoring only the root would leave its children gone.
    final subtree = await _subtreeIds(tag.id);
    final tagsTable = _db.tags.actualTableName;
    final linksTable = _db.objectTags.actualTableName;

    final snapshot = <String, List<Map<String, dynamic>>>{
      tagsTable: await _rowsWhere(
        tagsTable,
        'id IN (${_placeholders(subtree.length)})',
        [for (final id in subtree) Variable.withString(id)],
      ),
      linksTable: await _rowsWhere(
        linksTable,
        'tag_id IN (${_placeholders(subtree.length)})',
        [for (final id in subtree) Variable.withString(id)],
      ),
    };

    await _tags.deleteTag(tag.id);

    final children = subtree.length - 1;
    return ToolResult(
      ok: true,
      summary: '已删除标签「${tag.name}」'
          '${children > 0 ? '（含 $children 个子标签）' : ''}',
      modelResult: {
        'kind': kindTag,
        'deleted_tag_id': tag.id,
        'deleted_name': tag.name,
        'deleted_tag_count': subtree.length,
      },
      beforeJson: _encodeSnapshot(snapshot),
    );
  }

  /// The tag itself plus every descendant, parents first.
  ///
  /// Walked in Dart from `parent_id` rather than through a recursive SQL query:
  /// the tag tree is small, and this keeps the subtree definition identical to
  /// the one `TagRepository.deleteTag` uses.
  Future<List<String>> _subtreeIds(String rootId) async {
    final all = await _db.select(_db.tags).get();
    final byParent = <String?, List<String>>{};
    for (final tag in all) {
      byParent.putIfAbsent(tag.parentId, () => []).add(tag.id);
    }
    final ordered = <String>[rootId];
    final seen = <String>{rootId};
    for (var i = 0; i < ordered.length; i++) {
      for (final child in byParent[ordered[i]] ?? const <String>[]) {
        if (seen.add(child)) {
          ordered.add(child);
        }
      }
    }
    return ordered;
  }

  Future<Tag> _resolveTag(ToolArgs args) async {
    final id = args.optString('id');
    if (id != null) {
      final tag = await _tags.getTagById(id);
      if (tag == null) {
        throw ToolArgError('找不到 id 为 `$id` 的标签');
      }
      return tag;
    }
    final name = args.optString('name');
    if (name == null) {
      throw ToolArgError('kind=tag 需要 id 或 name');
    }
    final matches = [
      for (final tag in await _tags.getAllTags())
        if (tag.name == name.trim()) tag,
    ];
    if (matches.isEmpty) {
      throw ToolArgError('找不到名字为「$name」的标签');
    }
    if (matches.length > 1) {
      final where = [
        for (final tag in matches)
          '${tag.path ?? tag.name}（id=${tag.id}）',
      ].join('、');
      throw ToolArgError(
        '「$name」匹配到 ${matches.length} 个标签：$where —— 请改用 id 指定要删哪一个',
      );
    }
    return matches.single;
  }

  // --- cards --------------------------------------------------------------

  Future<ToolResult> _deleteCard(ToolArgs args) async {
    final card = await _resolveCard(args);
    final templatesTable = _db.cardTemplates.actualTableName;
    final statesTable = _db.cardStates.actualTableName;
    final logsTable = _db.reviewLogs.actualTableName;

    final snapshot = <String, List<Map<String, dynamic>>>{
      templatesTable: await _rowsWhere(
        templatesTable,
        'id = ?',
        [Variable.withString(card.id)],
      ),
      statesTable: await _rowsWhere(
        statesTable,
        'card_template_id = ?',
        [Variable.withString(card.id)],
      ),
      logsTable: await _rowsWhere(
        logsTable,
        'card_template_id = ?',
        [Variable.withString(card.id)],
      ),
    };

    await _anki.deleteTemplate(card.id);

    return ToolResult(
      ok: true,
      summary: '已删除卡片「${_shorten(card.question)}」',
      modelResult: {
        'kind': kindCard,
        'deleted_card_id': card.id,
        'deleted_question': card.question,
      },
      beforeJson: _encodeSnapshot(snapshot),
    );
  }

  Future<CardTemplate> _resolveCard(ToolArgs args) async {
    final id = args.optString('id');
    if (id != null) {
      final card = await _anki.getCardTemplateById(id);
      if (card == null) {
        throw ToolArgError('找不到 id 为 `$id` 的卡片');
      }
      return card;
    }
    final question = args.optString('question');
    if (question == null) {
      throw ToolArgError('kind=card 需要 id 或 question');
    }
    // Exact match on purpose: the model's paraphrase of a question is not the
    // question, and "close enough" is how the wrong card gets deleted.
    final query = _db.select(_db.cardTemplates)
      ..where((t) => t.question.equals(question.trim()));
    final matches = await query.get();
    if (matches.isEmpty) {
      throw ToolArgError('找不到题目为「$question」的卡片（需要与库里的题目完全一致）');
    }
    if (matches.length > 1) {
      final where = [
        for (final card in matches) '${_shorten(card.question)}（id=${card.id}）',
      ].join('、');
      throw ToolArgError(
        '这个题目匹配到 ${matches.length} 张卡片：$where —— 请改用 id 指定要删哪一张',
      );
    }
    return matches.single;
  }

  // --- flashcards ---------------------------------------------------------

  Future<ToolResult> _deleteFlashcard(ToolArgs args) async {
    final point = await _resolveFlashcard(args);
    final templates = await _anki.getTemplatesForKnowledgePoint(point.id);
    final templateIds = [for (final template in templates) template.id];

    final pointsTable = _db.knowledgePoints.actualTableName;
    final templatesTable = _db.cardTemplates.actualTableName;
    final statesTable = _db.cardStates.actualTableName;
    final logsTable = _db.reviewLogs.actualTableName;

    // Parents before children: `restoreTable` inserts row by row, and the
    // flashcard has to exist again before rows that reference it can.
    final snapshot = <String, List<Map<String, dynamic>>>{
      pointsTable: await _rowsWhere(
        pointsTable,
        'id = ?',
        [Variable.withString(point.id)],
      ),
      templatesTable: await _rowsWhere(
        templatesTable,
        'knowledge_point_id = ?',
        [Variable.withString(point.id)],
      ),
      if (templateIds.isNotEmpty) ...{
        statesTable: await _rowsWhere(
          statesTable,
          'card_template_id IN (${_placeholders(templateIds.length)})',
          [for (final id in templateIds) Variable.withString(id)],
        ),
        logsTable: await _rowsWhere(
          logsTable,
          'card_template_id IN (${_placeholders(templateIds.length)})',
          [for (final id in templateIds) Variable.withString(id)],
        ),
      },
    };

    await _anki.deleteKnowledgePoint(point.id);

    return ToolResult(
      ok: true,
      summary: '已删除闪存卡「${_shorten(point.title)}」'
          '${templates.isNotEmpty ? '（含 ${templates.length} 张卡片）' : ''}',
      modelResult: {
        'kind': kindFlashcard,
        'deleted_flashcard_id': point.id,
        'deleted_title': point.title,
        'deleted_card_count': templates.length,
      },
      beforeJson: _encodeSnapshot(snapshot),
    );
  }

  Future<KnowledgePoint> _resolveFlashcard(ToolArgs args) async {
    final id = args.optString('id');
    if (id != null) {
      final point = await _anki.getKnowledgePointById(id);
      if (point == null) {
        throw ToolArgError('找不到 id 为 `$id` 的闪存卡');
      }
      return point;
    }
    final title = args.optString('title');
    if (title == null) {
      throw ToolArgError('kind=flashcard 需要 id 或 title');
    }
    final query = _db.select(_db.knowledgePoints)
      ..where((t) => t.title.equals(title.trim()));
    final matches = await query.get();
    if (matches.isEmpty) {
      throw ToolArgError('找不到标题为「$title」的闪存卡（需要与库里的标题完全一致）');
    }
    if (matches.length > 1) {
      final where = [
        for (final point in matches) '${_shorten(point.title)}（id=${point.id}）',
      ].join('、');
      throw ToolArgError(
        '这个标题匹配到 ${matches.length} 张闪存卡：$where —— 请改用 id 指定要删哪一张',
      );
    }
    return matches.single;
  }

  // --- snapshot plumbing --------------------------------------------------

  static String _placeholders(int count) =>
      List.filled(count, '?').join(', ');

  /// Raw rows with SQL column names, i.e. exactly what `restoreTable` consumes.
  ///
  /// Raw SQL rather than drift's generated `toJson()` on purpose: that one emits
  /// *property* names (`parentId`), while the restore path matches *column*
  /// names (`parent_id`). Every table read here is text/int only, so no BLOB
  /// conversion is involved.
  Future<List<Map<String, dynamic>>> _rowsWhere(
    String table,
    String where,
    List<Variable<Object>> variables,
  ) async {
    final rows = await _db
        .customSelect('SELECT * FROM $table WHERE $where', variables: variables)
        .get();
    return [
      for (final row in rows) Map<String, dynamic>.from(row.data),
    ];
  }

  static String _encodeSnapshot(
    Map<String, List<Map<String, dynamic>>> tables,
  ) =>
      jsonEncode({
        'version': 1,
        'tables': tables,
      });

  static String _shorten(String text, {int max = 24}) {
    final flat = text.replaceAll('\n', ' ').trim();
    return flat.length <= max ? flat : '${flat.substring(0, max)}…';
  }
}

/// Writes back what one [DeleteContentTool] call removed.
///
/// Returns false when the snapshot has no recognisable shape, which is how the
/// loop tells "this action cannot be undone" from "undo failed".
Future<bool> restoreDeletedContent(
  AppDatabase db,
  Map<String, Object?> snapshot,
) async {
  final tables = snapshot['tables'];
  if (tables is! Map) {
    return false;
  }
  await db.transaction(() async {
    // Insertion order is the snapshot's own order, and the snapshot is built
    // parents-first so a row's parents exist again before it is written.
    for (final entry in tables.entries) {
      final raw = entry.value;
      if (raw is! List) {
        continue;
      }
      final rows = [
        for (final row in raw)
          if (row is Map) row.cast<String, dynamic>(),
      ];
      if (rows.isEmpty) {
        continue;
      }
      // `insert` mode skips rows whose primary key exists again (the user may
      // have recreated one by hand in the meantime) instead of failing the undo.
      await db.restoreTable(entry.key as String, rows);
    }
  });
  return true;
}
