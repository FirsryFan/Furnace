import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/time_block_repository.dart';
import '../domain/ai_tool.dart';

/// Calendar operations exposed to the model.
///
/// Same shape as the task tools (AI_DESIGN D6): one read tool, one manage tool,
/// every call a thin wrapper over [TimeBlockRepository] so the Time screen
/// refreshes on its own and the interval rules stay in one place (D2).
class QueryScheduleTool extends AiTool {
  QueryScheduleTool(this._blocks);

  final TimeBlockRepository _blocks;

  static const int defaultLimit = 30;

  @override
  String get name => 'query_schedule';

  @override
  String get description =>
      '查询用户日程里的时间块（上课、自习等固定安排）。'
      '用于安排任务前先看有哪些时间被占用，或回答"我这周有什么安排"。'
      '只读。时间用 ISO-8601 字符串或毫秒时间戳。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'from': {'type': 'string', 'description': '只返回开始于此时刻之后的时间块'},
          'to': {'type': 'string', 'description': '只返回结束于此时刻之前的时间块'},
          'available_only': {
            'type': 'boolean',
            'description': '只返回可用于安排任务的空档（available = true）',
          },
          'limit': {
            'type': 'integer',
            'description': '最多返回几条，默认 $defaultLimit',
          },
        },
        'required': <String>[],
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
    final from = args.optEpochMs('from');
    final to = args.optEpochMs('to');
    final availableOnly = args.optBool('available_only') ?? false;
    final limit = (args.optInt('limit') ?? defaultLimit).clamp(1, 500);

    final all = await _blocks.getTimeBlocks(onlyAvailable: availableOnly);
    final filtered = all.where((block) {
      if (from != null && block.endAt < from) {
        return false;
      }
      if (to != null && block.startAt > to) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));

    final page = filtered.take(limit).toList();
    return ToolResult(
      ok: true,
      summary: filtered.isEmpty
          ? '该时间段没有日程'
          : '找到 ${filtered.length} 个时间块，返回前 ${page.length} 个',
      modelResult: {
        'total_matching': filtered.length,
        'returned': page.length,
        'truncated': filtered.length > page.length,
        'blocks': [for (final b in page) blockToJson(b)],
      },
    );
  }
}

/// Create / update / delete time blocks.
class ManageTimeBlockTool extends AiTool {
  ManageTimeBlockTool(this._blocks, this._db);

  final TimeBlockRepository _blocks;
  final AppDatabase _db;

  static const Set<String> actions = {'create', 'update', 'delete'};

  @override
  String get name => 'manage_time_block';

  @override
  String get description =>
      '新建、修改或删除日程时间块。create 需要 title、start_at、end_at；'
      'update/delete 需要 id。时间用 ISO-8601 字符串或毫秒时间戳。'
      '时间块允许重叠（不强制排他）。删除是破坏性操作，需逐条确认。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': actions.toList(),
            'description': '要执行的操作',
          },
          'id': {'type': 'string', 'description': '时间块 id（update/delete 必填）'},
          'title': {'type': 'string', 'description': '标题（create 必填）'},
          'start_at': {'type': 'string', 'description': '开始时刻（create 必填）'},
          'end_at': {'type': 'string', 'description': '结束时刻（create 必填）'},
          'available': {
            'type': 'boolean',
            'description': '是否可用于安排任务，默认 true',
          },
          'energy': {'type': 'string', 'description': '这段时间的精力水平标签'},
          'suitable_for': {'type': 'string', 'description': '适合做什么'},
          'repeat_rule': {'type': 'string', 'description': '重复规则（可选）'},
        },
        'required': ['action'],
      };

  @override
  ToolRisk riskFor(String action) =>
      action == 'delete' ? ToolRisk.destructive : ToolRisk.write;

  @override
  bool reversibleFor(String action) => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    final args = ToolArgs(invocation.arguments);
    try {
      final action = args.requireAction(actions);
      return switch (action) {
        'create' => await _create(args),
        'update' => await _update(args),
        'delete' => await _delete(args),
        _ => ToolResult.failure('不支持的 action: $action'),
      };
    } on ToolArgError catch (e) {
      return ToolResult.failure(e.message);
    }
  }

  Future<ToolResult> _create(ToolArgs args) async {
    final title = args.requireString('title');
    final startAt = args.optEpochMs('start_at');
    final endAt = args.optEpochMs('end_at');
    if (startAt == null || endAt == null) {
      return const ToolResult.failure('create 需要 start_at 与 end_at');
    }
    if (endAt <= startAt) {
      return const ToolResult.failure('end_at 必须晚于 start_at');
    }
    final block = await _blocks.createTimeBlock(
      title: title,
      startAt: startAt,
      endAt: endAt,
      available: args.optBool('available') ?? true,
      energy: args.optString('energy'),
      suitableFor: args.optString('suitable_for'),
      repeatRule: args.optString('repeat_rule'),
    );
    return ToolResult(
      ok: true,
      summary: '已新建日程「${block.title}」',
      modelResult: {'id': block.id},
      afterJson: jsonEncode(await snapshotTimeBlock(_db, block.id)),
    );
  }

  Future<ToolResult> _update(ToolArgs args) async {
    final id = args.requireString('id');
    final before = await snapshotTimeBlock(_db, id);
    if (before == null) {
      return const ToolResult.failure('找不到该时间块');
    }
    final startAt = args.optEpochMs('start_at');
    final endAt = args.optEpochMs('end_at');
    final existingStart = before['start_at'] as int;
    final existingEnd = before['end_at'] as int;
    if ((endAt ?? existingEnd) <= (startAt ?? existingStart)) {
      return const ToolResult.failure('end_at 必须晚于 start_at');
    }
    final title = args.optString('title');
    if (title == null &&
        startAt == null &&
        endAt == null &&
        args.optBool('available') == null &&
        args.optString('energy') == null &&
        args.optString('suitable_for') == null &&
        args.optString('repeat_rule') == null) {
      return const ToolResult.failure('update 至少要给一个要改的字段');
    }
    await _blocks.updateTimeBlock(
      id,
      title: title,
      startAt: startAt,
      endAt: endAt,
      available: args.optBool('available'),
      energy: args.optString('energy'),
      suitableFor: args.optString('suitable_for'),
      repeatRule: args.optString('repeat_rule'),
    );
    return ToolResult(
      ok: true,
      summary: '已更新日程「${before['title']}」',
      modelResult: {'id': id},
      beforeJson: jsonEncode(before),
      afterJson: jsonEncode(await snapshotTimeBlock(_db, id)),
    );
  }

  Future<ToolResult> _delete(ToolArgs args) async {
    final id = args.requireString('id');
    final before = await snapshotTimeBlock(_db, id);
    if (before == null) {
      return const ToolResult.failure('找不到该时间块');
    }
    await _blocks.deleteTimeBlock(id);
    return ToolResult(
      ok: true,
      summary: '已删除日程「${before['title']}」',
      modelResult: {'id': id, 'deleted': true},
      beforeJson: jsonEncode(before),
    );
  }
}

/// The model-facing shape of a time block. Times are sent as **both** epoch
/// millis and ISO text: the model reasons in dates but echoes ids and numbers,
/// and giving it both removes a whole class of conversion mistakes.
Map<String, Object?> blockToJson(TimeBlock block) {
  final start = DateTime.fromMillisecondsSinceEpoch(block.startAt);
  final end = DateTime.fromMillisecondsSinceEpoch(block.endAt);
  return {
    'id': block.id,
    'title': block.title,
    'start_at_ms': block.startAt,
    'end_at_ms': block.endAt,
    'start_at': start.toIso8601String(),
    'end_at': end.toIso8601String(),
    'available': block.available,
    if (block.energy != null) 'energy': block.energy,
    if (block.suitableFor != null) 'suitable_for': block.suitableFor,
    if (block.repeatRule != null) 'repeat_rule': block.repeatRule,
  };
}

/// Reads a time block in the flat shape undo needs.
Future<Map<String, Object?>?> snapshotTimeBlock(
    AppDatabase db, String id) async {
  final rows = await (db.select(db.timeBlocks)..where((t) => t.id.equals(id)))
      .get();
  if (rows.isEmpty) {
    return null;
  }
  final block = rows.first;
  return {
    'id': block.id,
    'title': block.title,
    'start_at': block.startAt,
    'end_at': block.endAt,
    'available': block.available,
    'energy': block.energy,
    'suitable_for': block.suitableFor,
    'repeat_rule': block.repeatRule,
    'created_at': block.createdAt,
    'updated_at': block.updatedAt,
  };
}

/// Puts a snapshotted time block back, used by undo.
Future<void> restoreTimeBlock(
    AppDatabase db, Map<String, Object?> snapshot) async {
  await db.into(db.timeBlocks).insert(
        TimeBlocksCompanion.insert(
          id: snapshot['id'] as String,
          title: snapshot['title'] as String,
          startAt: snapshot['start_at'] as int,
          endAt: snapshot['end_at'] as int,
          available: Value(snapshot['available'] as bool? ?? true),
          energy: Value(snapshot['energy'] as String?),
          suitableFor: Value(snapshot['suitable_for'] as String?),
          repeatRule: Value(snapshot['repeat_rule'] as String?),
          createdAt: snapshot['created_at'] as int,
          updatedAt: snapshot['updated_at'] as int,
        ),
        mode: InsertMode.insertOrReplace,
      );
}
