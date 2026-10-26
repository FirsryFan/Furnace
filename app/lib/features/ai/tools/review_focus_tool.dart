/// 「考前把某些板块提前进复习」的 AI 写口（用户 2026-10-26 提出：下周要考试，
/// 某些板块的内容要进入复习，就提前进来）。
///
/// 为什么是工具而不是页面：用户希望**对着 AI 说一句**就能调推送——「下周考生物
/// 必修一，把这一章的卡提前」；模型先用 `query_content(kind: tag)` 找到标签，
/// 再调这里。标签就是卡组（轮次十七），所以一个标签子树正好覆盖「某一章/某个
/// 板块」。
///
/// 只改 `card_states.due_at`（把未来 N 天内到期的卡挪到今天），不动 FSRS 记忆
/// 状态；判定与排序在 `domain/services/srs/review_focus.dart` 的纯逻辑里，这个
/// 文件只做「查标签 → 查卡 → 写库 → 造 undo 快照」。
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/tag_repository.dart';
import '../../../domain/services/srs/review_focus.dart';
import '../domain/ai_tool.dart';
import 'card_group_tools.dart'
    show kKnowledgePointObjectType, resolveTagForTool;

/// 把某个卡组（标签子树）下未来 N 天内到期的闪存卡提前到今天。
class ReviewFocusTool extends AiTool {
  ReviewFocusTool({
    required AppDatabase db,
    required AnkiRepository anki,
    required TagRepository tags,
    DateTime Function()? clock,
  })  : _db = db,
        _anki = anki,
        _tags = tags,
        _clock = clock;

  final AppDatabase _db;
  final AnkiRepository _anki;
  final TagRepository _tags;

  /// 测试注入的「现在」；生产传 null 用真实时间。
  final DateTime Function()? _clock;

  /// The name the provider sees and the agent loop recognises for undo.
  static const String toolName = 'focus_review';

  /// 默认只拉未来 7 天内的卡（「下周考试」的默认口径）。
  static const int defaultHorizonDays = 7;
  static const int maxHorizonDays = 90;

  /// 单次最多拉多少张，防止一句「把整本生物提前」把几千张卡塞进今天。
  static const int defaultLimit = 500;
  static const int maxLimit = 2000;

  @override
  String get name => toolName;

  @override
  String get description => '考前突击：把一个卡组（标签及其子标签）下「未来 N 天内'
      '到期」的已学闪存卡提前到今天复习。例如「下周考生物必修一」→ tag 填'
      '「生物/高中生物/必修1 分子与细胞」，days 填 7。'
      '只动到期时间（due_at），不改记忆状态、不改每天上限；没学过的新卡不拉，'
      '已经到期的不动，更远的不动。tag 用 id 或完整路径（先 query_content'
      '(kind: tag) 查）。dry_run 默认 true 只预览，确认后传 dry_run=false；'
      '写库可以在本对话撤销。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'tag': {
            'type': 'string',
            'description': '卡组（标签）id 或完整路径，例如 '
                '`生物/高中生物/必修1 分子与细胞/第1章 走近细胞`',
          },
          'days': {
            'type': 'integer',
            'description': '把未来多少天内到期的卡提前（默认 $defaultHorizonDays，'
                '0–$maxHorizonDays；0 表示只处理本来就到期的，等于不拉）',
          },
          'limit': {
            'type': 'integer',
            'description': '单次最多拉多少张（默认 $defaultLimit，1–$maxLimit）',
          },
          'dry_run': {
            'type': 'boolean',
            'description': 'true（默认）= 只预览不写库，false = 真的写',
          },
        },
        'required': <String>['tag'],
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
      final tagRaw = args.requireString('tag');
      final days = args.optInt('days') ?? defaultHorizonDays;
      if (days < 0 || days > maxHorizonDays) {
        throw ToolArgError(
          '`days` 只能是 0–$maxHorizonDays 天（默认 $defaultHorizonDays）',
        );
      }
      final limit = args.optInt('limit') ?? defaultLimit;
      if (limit <= 0 || limit > maxLimit) {
        throw ToolArgError('`limit` 只能是 1–$maxLimit 张（默认 $defaultLimit）');
      }
      final dryRun = args.optBool('dry_run') ?? true;
      final tag = await resolveTagForTool(_tags, tagRaw);
      final tagPath = tag.path ?? tag.name;

      final subtree = tag.path == null
          ? <Tag>[tag]
          : await _tags.getTagsUnderPath(tag.path!);
      final tagIds = [for (final row in subtree) row.id];
      final points = await _knowledgePointIds(tagIds);
      if (points.isEmpty) {
        return ToolResult(
          ok: true,
          summary: '卡组「$tagPath」下没有挂任何知识点/闪存卡，没有可提前的卡。',
          modelResult: {
            'tag': {'id': tag.id, 'path': tagPath},
            'counts': {'total': 0, 'pull': 0},
          },
        );
      }

      final states = await _anki.cardStatesForKnowledgePoints(points);
      final plan = planReviewFocus(
        cards: [
          for (final state in states)
            ReviewFocusCard(
              cardStateId: state.id,
              knowledgePointId: state.knowledgePointId ?? '',
              dueAt: state.dueAt,
              repetitions: state.repetitions,
              state: state.state,
            ),
        ],
        now: _now(),
        horizon: Duration(days: days),
        limit: limit,
      );
      final cap = await _groupReviewCap(tagIds);
      final counts = <String, Object?>{
        'total': plan.total,
        'pull': plan.pulled.length,
        'already_due': plan.alreadyDue,
        'too_far': plan.tooFar,
        'new_cards': plan.newCards,
        'beyond_limit': plan.beyondLimit,
      };
      final samples = [
        for (final pull in plan.pulled.take(10))
          {
            'card_state_id': pull.cardStateId,
            'knowledge_point_id': pull.knowledgePointId,
            'due_at': pull.previousDueAt,
          },
      ];

      if (dryRun) {
        return ToolResult(
          ok: true,
          summary: _previewSummary(
            tagPath: tagPath,
            plan: plan,
            days: days,
            limit: limit,
            reviewCap: cap,
          ),
          modelResult: {
            'mode': 'focus_review',
            'dry_run': true,
            'tag': {'id': tag.id, 'path': tagPath},
            'days': days,
            'limit': limit,
            'counts': counts,
            'review_cap': cap,
            'cards': samples,
          },
        );
      }

      final nowMs = _now().millisecondsSinceEpoch;
      await _anki.setCardStateDueAts({
        for (final pull in plan.pulled) pull.cardStateId: nowMs,
      });
      // 一张都没拉 = 没有任何副作用，不留 undo 快照（空快照会让撤销"成功"
      // 却什么也没做，模型也会以为改过）。
      final beforeJson = plan.pulled.isEmpty
          ? null
          : jsonEncode({
              'version': 1,
              'due_at': [
                for (final pull in plan.pulled)
                  {'id': pull.cardStateId, 'due_at': pull.previousDueAt},
              ],
            });
      return ToolResult(
        ok: true,
        summary: _appliedSummary(
          tagPath: tagPath,
          plan: plan,
          days: days,
          reviewCap: cap,
        ),
        modelResult: {
          'mode': 'focus_review',
          'dry_run': false,
          'tag': {'id': tag.id, 'path': tagPath},
          'days': days,
          'counts': counts,
          'review_cap': cap,
          'pulled': samples,
        },
        // undo：把每张卡拉之前的 due_at 写回去（空时是 null，见上）。
        beforeJson: beforeJson,
      );
    } on ToolArgError catch (e) {
      return ToolResult.failure(e.message);
    }
  }

  DateTime _now() => _clock?.call() ?? DateTime.now();

  /// 标签子树下挂着的知识点 id（去重）。
  Future<List<String>> _knowledgePointIds(Iterable<String> tagIds) async {
    final ids = tagIds.toSet().toList();
    if (ids.isEmpty) {
      return const [];
    }
    final links = await (_db.select(_db.objectTags)
          ..where(
            (t) =>
                t.tagId.isIn(ids) &
                t.objectType.equals(kKnowledgePointObjectType),
          ))
        .get();
    return {for (final link in links) link.objectId}.toList();
  }

  /// 子树里任一卡组设了「每天复习上限」时返回它（0/没设 = null）。
  ///
  /// 提前的卡如果被上限挡住，用户会觉得「拉了却没出现」，所以应用到 summary
  /// 里说清，并让模型知道可以再用 `manage_review_plan` 调上限。
  Future<int?> _groupReviewCap(Iterable<String> tagIds) async {
    final ids = tagIds.toSet().toList();
    if (ids.isEmpty) {
      return null;
    }
    final rows = await (_db.select(_db.reviewGroupPlans)
          ..where((t) => t.tagId.isIn(ids)))
        .get();
    int? cap;
    for (final row in rows) {
      if (row.reviewCardsPerDay <= 0) {
        continue;
      }
      if (cap == null || row.reviewCardsPerDay > cap) {
        cap = row.reviewCardsPerDay;
      }
    }
    return cap;
  }

  String _previewSummary({
    required String tagPath,
    required ReviewFocusPlan plan,
    required int days,
    required int limit,
    required int? reviewCap,
  }) {
    final buffer = StringBuffer()
      ..write('预览（还没写库）：卡组「$tagPath」下共 ${plan.total} 张已学过的卡，')
      ..write(plan.pulled.isEmpty
          ? '未来 $days 天内没有要到期的卡，不用拉。'
          : '其中 ${plan.pulled.length} 张未来 $days 天内到期，确认后会提前到今天。')
      ..write('已经到期 ${plan.alreadyDue} 张（本来就在今天队列里，不动）；')
      ..write('更晚 ${plan.tooFar} 张（不动）；新卡 ${plan.newCards} 张（不拉）。');
    if (plan.beyondLimit > 0) {
      buffer.write('还有 ${plan.beyondLimit} 张超过单次上限 $limit 张没拉，可加大 limit。');
    }
    if (reviewCap != null) {
      buffer.write('注意：这个卡组设了每天复习上限 $reviewCap 张，'
          '今天可能只先放行一部分；要全部进今天，用 manage_review_plan 把'
          ' review_cards_per_day 调大或设 0。');
    }
    if (plan.pulled.isNotEmpty) {
      buffer.write('确认后传 dry_run=false 才写库。');
    }
    return buffer.toString();
  }

  String _appliedSummary({
    required String tagPath,
    required ReviewFocusPlan plan,
    required int days,
    required int? reviewCap,
  }) {
    final buffer = StringBuffer()
      ..write('已把卡组「$tagPath」下 ${plan.pulled.length} 张未来 $days 天内到期的卡'
          '提前到今天，现在打开闪存卡复习就会按模型顺序看到它们。')
      ..write('（已经到期 ${plan.alreadyDue} 张不用动；更晚 ${plan.tooFar} 张、'
          '新卡 ${plan.newCards} 张没拉。）');
    if (reviewCap != null) {
      buffer.write('这个卡组每天复习上限是 $reviewCap 张，今天可能只先放行一部分，'
          '要全部进今天可用 manage_review_plan 调整。');
    }
    buffer.write('这次改动可以在本对话撤销。');
    return buffer.toString();
  }
}

/// Undo for one [ReviewFocusTool] call: put each card's previous `due_at` back.
///
/// The snapshot is `{'version': 1, 'due_at': [{'id': ..., 'due_at': ...}]}`,
/// written only when [ReviewFocusTool] actually applied something.
Future<bool> restoreReviewFocus(
  AppDatabase db,
  Map<String, Object?> before,
) async {
  final rows = before['due_at'];
  if (rows is! List) {
    return false;
  }
  final restored = <String, int>{};
  for (final row in rows) {
    if (row is! Map) {
      continue;
    }
    final id = row['id'];
    final dueAt = row['due_at'];
    if (id is String && dueAt is int) {
      restored[id] = dueAt;
    }
  }
  if (restored.isEmpty) {
    return false;
  }
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.batch((batch) {
    for (final entry in restored.entries) {
      batch.update(
        db.cardStates,
        CardStatesCompanion(
          dueAt: Value(entry.value),
          updatedAt: Value(now),
        ),
        where: (t) => t.id.equals(entry.key),
      );
    }
  });
  return true;
}
