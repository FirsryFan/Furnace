/// The AI's write path into the tag tree: "add a tag under 物理/力学".
///
/// The tree is what makes this more than a name field: a tag created without a
/// parent lands at the top level, and one created under the wrong parent is a
/// *different* tag with a different path (`物理/力学` vs `力学`). So the parent is
/// addressed explicitly - by id or by full path - and never guessed: a name that
/// matches nothing, or a path that does not exist, is refused with the reason,
/// and the model can look the tree up first with `query_content(kind: tag)`.
///
/// Deletion lives in `delete_content` (`kind: tag`) because that is the tool
/// that needs per-item confirmation; creating a tag is an ordinary reversible
/// write (undo = remove what it made).
library;

import 'dart:convert';

import '../../../data/database/database.dart';
import '../../../data/repositories/tag_repository.dart';
import '../domain/ai_tool.dart';

/// One tag the model asked for, after validation.
class _RequestedTag {
  const _RequestedTag({
    required this.name,
    this.parentId,
    this.parentPath,
    this.color,
    this.description,
  });

  final String name;
  final String? parentId;
  final String? parentPath;
  final int? color;
  final String? description;
}

/// Creates one or more tags, optionally under an existing parent.
class CreateTagsTool extends AiTool {
  CreateTagsTool(this._tags);

  final TagRepository _tags;

  /// The name the provider sees and the agent loop recognises for undo.
  static const String toolName = 'create_tags';

  /// A single call may add a small batch (a chapter's sections at once); beyond
  /// that the model should be told to split the work rather than be handed an
  /// unbounded list whose failure mode is "half of them exist".
  static const int maxTagsPerCall = 20;

  @override
  String get name => toolName;

  @override
  String get description =>
      '创建一个或多个标签，用来搭/补充标签树。'
      '每个标签给 name；想建在某个父标签下就给 parent_id 或 parent_path（例如 `物理/力学`，'
      '路径先调 query_content(kind: tag) 查，不要猜）。父标签找不到会拒绝执行并说明，不会默默建到顶层。'
      '同名兄弟会被自动加后缀（`力学-2`），所以重名不会失败。'
      '删除标签用 delete_content(kind: tag)（需要用户逐条确认）；建标签是可撤销的普通写入。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'tags': {
            'type': 'array',
            'description': '要创建的标签，最多 $maxTagsPerCall 个',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string', 'description': '标签名（必填，不能含 /）'},
                'parent_id': {
                  'type': 'string',
                  'description': '父标签 id（可选；与 parent_path 二选一）',
                },
                'parent_path': {
                  'type': 'string',
                  'description': '父标签完整路径，如 `物理/力学`（可选）',
                },
                'color': {'type': 'integer', 'description': '颜色（可选，整数）'},
                'description': {'type': 'string', 'description': '备注（可选）'},
              },
              'required': <String>['name'],
            },
          },
        },
        'required': <String>['tags'],
      };

  /// Creating is an ordinary write: reversible, and never on its own destructive.
  @override
  ToolRisk riskFor(String action) => ToolRisk.write;

  @override
  bool reversibleFor(String action) => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    try {
      final requested = _parse(invocation.arguments['tags']);
      final created = <Map<String, Object?>>[];
      for (final tag in requested) {
        final parent = await _resolveParent(tag);
        final row = await _tags.createTag(
          name: tag.name,
          parentId: parent?.id,
          color: tag.color,
          description: tag.description,
        );
        created.add({
          'id': row.id,
          'name': row.name,
          'path': row.path ?? row.name,
        });
      }

      return ToolResult(
        ok: true,
        summary: created.length == 1
            ? '已创建标签「${created.single['path']}」'
            : '已创建 ${created.length} 个标签：'
                '${[for (final tag in created) tag['path']].join('、')}',
        modelResult: {'created': created},
        // Ids only: undo removes what this call made, and nothing else.
        afterJson: jsonEncode({
          'version': 1,
          'tag_ids': [for (final tag in created) tag['id']],
        }),
      );
    } on ToolArgError catch (e) {
      // Caused by the model, so it becomes something it can read and correct.
      return ToolResult.failure(e.message);
    }
  }

  /// Resolves the parent a tag is to be created under, or null for the root.
  ///
  /// Resolution is explicit (id, then path) and never a "close enough" match:
  /// the parent decides the tag's path, and a tag under the wrong parent is not
  /// the tag the user asked for.
  Future<Tag?> _resolveParent(_RequestedTag requested) async {
    final id = requested.parentId;
    if (id != null) {
      final parent = await _tags.getTagById(id);
      if (parent == null) {
        throw ToolArgError(
          '找不到 id 为 `$id` 的父标签（可用 query_content(kind: tag) 查看现有标签）',
        );
      }
      return parent;
    }
    final path = requested.parentPath;
    if (path != null) {
      final parent = await _tags.getTagByPath(path.trim());
      if (parent == null) {
        throw ToolArgError(
          '找不到路径为 `$path` 的父标签（可用 query_content(kind: tag) 查看现有路径）',
        );
      }
      return parent;
    }
    return null;
  }

  static List<_RequestedTag> _parse(Object? raw) {
    if (raw is! List || raw.isEmpty) {
      throw ToolArgError('`tags` 必须是非空数组');
    }
    if (raw.length > maxTagsPerCall) {
      throw ToolArgError(
        '一次最多创建 $maxTagsPerCall 个标签（收到 ${raw.length} 个），请分几次调用',
      );
    }
    final tags = <_RequestedTag>[];
    for (var i = 0; i < raw.length; i++) {
      final entry = raw[i];
      if (entry is! Map) {
        throw ToolArgError('`tags[$i]` 不是对象');
      }
      final name = entry['name']?.toString().trim() ?? '';
      if (name.isEmpty) {
        throw ToolArgError('`tags[$i].name` 不能为空');
      }
      if (name.contains('/')) {
        throw ToolArgError('`tags[$i].name` 不能含 /（层级由 parent 决定）');
      }
      tags.add(_RequestedTag(
        name: name,
        parentId: _optString(entry['parent_id']),
        parentPath: _optString(entry['parent_path']),
        color: entry['color'] is int ? entry['color'] as int : null,
        description: _optString(entry['description']),
      ));
    }
    return tags;
  }

  static String? _optString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

/// Undo for one [CreateTagsTool] call: removes the tags it created.
///
/// Deleting through [TagRepository] rather than by hand keeps a created tag's
/// subtree and object links behaving exactly like a tag the UI deleted - the
/// same reason every other undo path goes through a repository.
Future<bool> deleteCreatedTags(
  AppDatabase db,
  Map<String, Object?> snapshot,
) async {
  final ids = snapshot['tag_ids'];
  if (ids is! List) {
    return false;
  }
  final repository = TagRepository(db);
  for (final id in ids) {
    if (id is String && id.isNotEmpty) {
      await repository.deleteTag(id);
    }
  }
  return true;
}
