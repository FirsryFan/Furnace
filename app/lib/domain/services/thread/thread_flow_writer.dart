/// ThreadFlow 的唯一状态写口（schema v47，2026-11-15）。
///
/// 契约：`INTEGRATION-CONTRACT-2026-11-15.md` §3.4。为什么要有它：任务状态原先
/// 有三个分散写点（Thread 页完成、AI 工具 start/complete、任务页 toggle），
/// 谁都能直接 `UPDATE tasks.status`，于是「完成/提交/卡住/跳过」这件事永远没有
/// 统一的事实记录。v47 起，状态迁移 + 事件追加 + 完成快照三件事绑在一个事务里，
/// 只从这个类走（迁移与测试夹具是例外；`task-90` 起 `reopen` 也走这里，
/// `TaskRepository.updateTask(status:)` 不再直接写 `tasks.status`）。
///
/// 三条设计约束：
///
///  1. **不建第二调度器**：本类只写事实，不排序、不选槽位、不创建时间块。
///     排序入口仍然只有 `ThreadRankService.build()`。
///  2. **完成 ≠ 提交**：`completed` 才写 `completion_logs` 快照；`submitted` /
///     `stuck` / `skipped` / `reopened` 只写 `thread_events`，不写完成历史、
///     不写正确性。`reopened` 会把 `tasks.completed_at` 清空，但**不删**
///     `completion_logs`（历史即事实）。
///  3. **幂等靠 `source_key`**：同一 `(taskId, kind, sourceKey)` 只写一次；创建
///     节点用 `tasks.source_key` 做物化幂等（跑两次只一行）。不给 sourceKey 时
///     每次调用都追加一行（append-only 的默认语义）。
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import '../../../data/ids.dart';
import '../time/actual_time.dart';
import 'thread_event_kind.dart';
import 'thread_node_kind.dart';
import 'thread_status.dart';

/// 一次迁移的结果。
///
/// [applied] = false 表示命中幂等（同一 sourceKey 已写过），**没有**新写事件；
/// 调用方据此可以安全重试，而不会把同一件事记两遍。
class ThreadTransitionResult {
  const ThreadTransitionResult({
    required this.applied,
    required this.task,
    this.event,
    this.completionLog,
  });

  final bool applied;
  final Task task;
  final ThreadEventRow? event;
  final CompletionLog? completionLog;
}

/// Thread 节点的唯一写口（创建/排期/开始/提交/卡住/跳过/重开/完成）。
class ThreadFlowWriter {
  ThreadFlowWriter(this._db);

  final AppDatabase _db;

  /// 事件 payload 的硬上限（契约 R4：payload 限 4 KB）。
  static const int maxPayloadBytes = 4096;

  /// 按 `tasks.source_key` 幂等创建节点。
  ///
  /// 查 `source_key` → 存在就复用（不再插行、不再写 created 事件），不存在才
  /// 插入并追一条 `created`。物化器必须走这里，**绝不无条件 insert**：周/日计划
  /// 重复生成最多变成一次 no-op。
  ///
  /// 复用时会比对 [kind]：同一个 source_key 被拿去建另一种节点属于调用方 bug，
  /// 直接抛错比悄悄返回一个种类不对的任务好。
  Future<Task> ensureTask({
    required String title,
    ThreadNodeKind kind = ThreadNodeKind.task,
    String? sourceKey,
    String? parentId,
    String description = '',
    String status = 'todo',
    int priority = 1,
    int? estimateMinutes,
    int? dueAt,
    int? remindAt,
    int? expectedAt,
    int? energyRequired,
    int? startedAt,
    DateTime? at,
  }) async {
    final nowMs = (at ?? DateTime.now()).millisecondsSinceEpoch;
    return _db.transaction(() async {
      if (sourceKey != null) {
        final existing = await (_db.select(_db.tasks)
              ..where((t) => t.sourceKey.equals(sourceKey)))
            .getSingleOrNull();
        if (existing != null) {
          if (existing.kind != null && existing.kind != kind.id) {
            throw StateError(
              'source_key "$sourceKey" already belongs to kind '
              '"${existing.kind}", not "${kind.id}"',
            );
          }
          return existing;
        }
      }
      final id = Ids.next('task');
      await _db.into(_db.tasks).insert(
            TasksCompanion.insert(
              id: id,
              parentId: Value(parentId),
              title: title,
              description: Value(description),
              status: Value(status),
              kind: Value(kind.id),
              sourceKey: Value(sourceKey),
              priority: Value(priority),
              estimateMinutes: Value(estimateMinutes),
              dueAt: Value(dueAt),
              remindAt: Value(remindAt),
              expectedAt: Value(expectedAt),
              energyRequired: Value(energyRequired),
              startedAt: Value(startedAt),
              createdAt: nowMs,
              updatedAt: nowMs,
            ),
          );
      final result = await _applyTransition(
        taskId: id,
        kind: ThreadEventKind.created,
        occurredAtMs: nowMs,
        payload: sourceKey == null
            ? const <String, Object?>{}
            : <String, Object?>{'source_key': sourceKey},
        sourceKey: sourceKey == null ? null : '$sourceKey:created',
        dueAt: dueAt,
        expectedAt: expectedAt,
        remindAt: remindAt,
        estimateMinutes: estimateMinutes,
        energyRequired: energyRequired,
      );
      return result.task;
    });
  }

  /// 唯一状态迁移入口：一次事务内「1 次状态更新 + 1 条事件（+ 完成快照）」。
  ///
  /// [sourceKey] 非空时做幂等：同一 `(taskId, kind, sourceKey)` 已存在就返回
  /// `applied: false`，不写第二行。`planned` 可带调度字段（dueAt/expectedAt/
  /// remindAt/estimateMinutes/energyRequired）；`completed` 可带完成快照输入
  /// （tagIds/tagPaths/title/useActualTime）。
  ///
  /// 非法迁移（例如 `skipped → completed`）抛 [StateError]：状态机宁可直接失败，
  /// 也不要把「卡住过/跳过过」抹成一个假完成。
  Future<ThreadTransitionResult> transition(
    String taskId,
    ThreadEventKind kind, {
    DateTime? at,
    Map<String, Object?> payload = const <String, Object?>{},
    String? sourceKey,
    int? dueAt,
    int? expectedAt,
    int? remindAt,
    int? estimateMinutes,
    int? energyRequired,
    List<String>? tagIds,
    List<String>? tagPaths,
    String? title,
    bool useActualTime = true,
  }) {
    final atMs = (at ?? DateTime.now()).millisecondsSinceEpoch;
    return _db.transaction(
      () => _applyTransition(
        taskId: taskId,
        kind: kind,
        occurredAtMs: atMs,
        payload: payload,
        sourceKey: sourceKey,
        dueAt: dueAt,
        expectedAt: expectedAt,
        remindAt: remindAt,
        estimateMinutes: estimateMinutes,
        energyRequired: energyRequired,
        tagIds: tagIds,
        tagPaths: tagPaths,
        title: title,
        useActualTime: useActualTime,
      ),
    );
  }

  /// 开始做（todo/doing/blocked → doing，stamp `started_at`）。
  Future<ThreadTransitionResult> start(
    String taskId, {
    DateTime? at,
    String? sourceKey,
  }) =>
      transition(taskId, ThreadEventKind.started, at: at, sourceKey: sourceKey);

  /// 排期（不改状态；写 dueAt/expectedAt/estimate/energy 并追 `planned`）。
  Future<ThreadTransitionResult> plan(
    String taskId, {
    DateTime? at,
    int? dueAt,
    int? expectedAt,
    int? remindAt,
    int? estimateMinutes,
    int? energyRequired,
    Map<String, Object?> payload = const <String, Object?>{},
    String? sourceKey,
  }) =>
      transition(
        taskId,
        ThreadEventKind.planned,
        at: at,
        dueAt: dueAt,
        expectedAt: expectedAt,
        remindAt: remindAt,
        estimateMinutes: estimateMinutes,
        energyRequired: energyRequired,
        payload: payload,
        sourceKey: sourceKey,
      );

  /// 提交答案/交卷（状态不变；payload 里放 verdict / attempt_ids 等流程事实）。
  Future<ThreadTransitionResult> submit(
    String taskId, {
    DateTime? at,
    Map<String, Object?> payload = const <String, Object?>{},
    String? sourceKey,
  }) =>
      transition(
        taskId,
        ThreadEventKind.submitted,
        at: at,
        payload: payload,
        sourceKey: sourceKey,
      );

  /// 卡住（todo/doing → blocked；payload 里放 reason，不写正确性）。
  Future<ThreadTransitionResult> markStuck(
    String taskId, {
    String? reason,
    DateTime? at,
    Map<String, Object?> payload = const <String, Object?>{},
    String? sourceKey,
  }) =>
      transition(
        taskId,
        ThreadEventKind.stuck,
        at: at,
        payload: _withReason(payload, reason),
        sourceKey: sourceKey,
      );

  /// 跳过（todo/doing/blocked → skipped；行与引用都保留）。
  Future<ThreadTransitionResult> skip(
    String taskId, {
    String? reason,
    DateTime? at,
    Map<String, Object?> payload = const <String, Object?>{},
    String? sourceKey,
  }) =>
      transition(
        taskId,
        ThreadEventKind.skipped,
        at: at,
        payload: _withReason(payload, reason),
        sourceKey: sourceKey,
      );

  /// 重开/恢复（blocked/skipped/done → todo；清 `completed_at`，不写完成历史）。
  ///
  /// [reason] 进 payload（例如"误点跳过"），是流程事实，不是判分。完成历史
  /// （`completion_logs`）**不回滚**：重开只让任务回到待办，不撤销"做过"这件事。
  /// `tasks.started_at` 按契约 §3.4 保持原样（重开只清 `completed_at`）；因此
  /// 重开后若不重新开始就直接完成，时长会从旧的 `started_at` 推、被判为可疑并
  /// 默认不进模型——这是既有"可疑记录"口径，不是新规则。
  Future<ThreadTransitionResult> reopen(
    String taskId, {
    String? reason,
    DateTime? at,
    Map<String, Object?> payload = const <String, Object?>{},
    String? sourceKey,
  }) =>
      transition(
        taskId,
        ThreadEventKind.reopened,
        at: at,
        payload: _withReason(payload, reason),
        sourceKey: sourceKey,
      );

  /// 完成（todo/doing → done；**只有它**写 `completion_logs` 快照）。
  ///
  /// [estimateMinutes] / [energyRequired] 是完成快照的覆盖值（沿用
  /// `TaskRepository.completeTask` 的旧口径：调用方显式传入的估时/精力优先于
  /// 任务行上的值）；它们只影响快照与可疑判定，不改任务行。
  Future<ThreadTransitionResult> complete(
    String taskId, {
    DateTime? at,
    List<String>? tagIds,
    List<String>? tagPaths,
    String? title,
    int? estimateMinutes,
    int? energyRequired,
    bool useActualTime = true,
    Map<String, Object?> payload = const <String, Object?>{},
    String? sourceKey,
  }) =>
      transition(
        taskId,
        ThreadEventKind.completed,
        at: at,
        tagIds: tagIds,
        tagPaths: tagPaths,
        title: title,
        estimateMinutes: estimateMinutes,
        energyRequired: energyRequired,
        useActualTime: useActualTime,
        payload: payload,
        sourceKey: sourceKey,
      );

  /// 一个节点的事件流，按发生时刻（同刻按 id）升序。
  Future<List<ThreadEventRow>> eventsFor(String taskId) {
    return (_db.select(_db.threadEvents)
          ..where((e) => e.taskId.equals(taskId))
          ..orderBy([
            (e) => OrderingTerm.asc(e.occurredAt),
            (e) => OrderingTerm.asc(e.id),
          ]))
        .get();
  }

  // -------------------------------------------------------------------------
  // internals
  // -------------------------------------------------------------------------

  /// 迁移的事务体。调用方负责包事务（[transition] / [ensureTask]）。
  Future<ThreadTransitionResult> _applyTransition({
    required String taskId,
    required ThreadEventKind kind,
    required int occurredAtMs,
    Map<String, Object?> payload = const <String, Object?>{},
    String? sourceKey,
    int? dueAt,
    int? expectedAt,
    int? remindAt,
    int? estimateMinutes,
    int? energyRequired,
    List<String>? tagIds,
    List<String>? tagPaths,
    String? title,
    bool useActualTime = true,
  }) async {
    final task = await (_db.select(_db.tasks)
          ..where((t) => t.id.equals(taskId)))
        .getSingleOrNull();
    if (task == null) {
      throw StateError('task not found: $taskId');
    }

    // 幂等：同一 (taskId, kind, sourceKey) 只写一次。
    if (sourceKey != null) {
      final existing = await (_db.select(_db.threadEvents)
            ..where(
              (e) =>
                  e.taskId.equals(taskId) &
                  e.kind.equals(kind.id) &
                  e.sourceKey.equals(sourceKey),
            ))
          .getSingleOrNull();
      if (existing != null) {
        return ThreadTransitionResult(
          applied: false,
          task: task,
          event: existing,
        );
      }
    }

    final current = ThreadStatus.fromStorage(task.status);
    final allowedFrom = kind.allowedFrom;
    if (allowedFrom.isNotEmpty && !allowedFrom.contains(current)) {
      throw StateError(
        'illegal transition: ${kind.id} from "${current.id}" (task $taskId)',
      );
    }

    final payloadJson = _encodePayload(payload);
    final target = kind.targetStatus;

    final companion = TasksCompanion(
      status: target == null ? const Value.absent() : Value(target.id),
      startedAt: kind == ThreadEventKind.started
          ? Value<int?>(occurredAtMs)
          : const Value.absent(),
      completedAt: kind == ThreadEventKind.completed
          ? Value<int?>(occurredAtMs)
          : kind == ThreadEventKind.reopened
              // 契约 §3.4「重开」：`status=todo`、`completedAt=null`。只清这一列，
              // `completion_logs` 与 `started_at` 都不动（历史即事实）。
              ? const Value<int?>(null)
              : const Value.absent(),
      dueAt: kind == ThreadEventKind.planned && dueAt != null
          ? Value<int?>(dueAt)
          : const Value.absent(),
      expectedAt: kind == ThreadEventKind.planned && expectedAt != null
          ? Value<int?>(expectedAt)
          : const Value.absent(),
      remindAt: kind == ThreadEventKind.planned && remindAt != null
          ? Value<int?>(remindAt)
          : const Value.absent(),
      estimateMinutes: kind == ThreadEventKind.planned &&
              estimateMinutes != null
          ? Value<int?>(estimateMinutes)
          : const Value.absent(),
      energyRequired: kind == ThreadEventKind.planned && energyRequired != null
          ? Value<int?>(energyRequired)
          : const Value.absent(),
      updatedAt: Value(occurredAtMs),
    );
    await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId)))
        .write(companion);

    CompletionLog? completionLog;
    if (kind.writesCompletionLog) {
      completionLog = await _insertCompletionLog(
        task: task,
        occurredAtMs: occurredAtMs,
        tagIds: tagIds,
        tagPaths: tagPaths,
        title: title,
        estimateMinutes: estimateMinutes,
        energyRequired: energyRequired,
        useActualTime: useActualTime,
      );
    }

    final eventId = Ids.next('te');
    await _db.into(_db.threadEvents).insert(
          ThreadEventsCompanion.insert(
            id: eventId,
            taskId: taskId,
            kind: kind.id,
            payloadJson: Value(payloadJson),
            occurredAt: occurredAtMs,
            sourceKey: Value(sourceKey),
          ),
        );
    final updated = (await (_db.select(_db.tasks)
          ..where((t) => t.id.equals(taskId)))
        .getSingle());
    final event = await (_db.select(_db.threadEvents)
          ..where((e) => e.id.equals(eventId)))
        .getSingle();
    return ThreadTransitionResult(
      applied: true,
      task: updated,
      event: event,
      completionLog: completionLog,
    );
  }

  /// 完成快照：与 `TaskRepository.completeTask` 同一口径（actualMinutes =
  /// 完成时刻 - 开始时刻，没有任何后台计时器；可疑记录默认不进模型但仍可见）。
  Future<CompletionLog> _insertCompletionLog({
    required Task task,
    required int occurredAtMs,
    List<String>? tagIds,
    List<String>? tagPaths,
    String? title,
    int? estimateMinutes,
    int? energyRequired,
    bool useActualTime = true,
  }) async {
    final estimate = estimateMinutes ?? task.estimateMinutes;
    final startedAt = task.startedAt;
    ActualTimeRecord? actual;
    if (startedAt != null) {
      actual = ActualTime.compute(
        startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt),
        completedAt: DateTime.fromMillisecondsSinceEpoch(occurredAtMs),
        estimateMinutes: estimate,
      );
    }
    final logId = Ids.next('cl');
    await _db.into(_db.completionLogs).insert(
          CompletionLogsCompanion.insert(
            id: logId,
            taskId: task.id,
            title: title ?? task.title,
            tagIds: Value(_encodeList(tagIds)),
            tagPaths: Value(_encodeList(tagPaths)),
            estimateMinutes: Value(estimate),
            energyRequired: Value(energyRequired ?? task.energyRequired),
            completedAt: occurredAtMs,
            actualMinutes: Value(actual?.actualMinutes),
            includeInModel:
                Value(useActualTime && (actual?.includeInModel ?? true)),
            durationSuspicious: Value(actual?.suspicious ?? false),
            createdAt: occurredAtMs,
          ),
        );
    return (_db.select(_db.completionLogs)
          ..where((c) => c.id.equals(logId)))
        .getSingle();
  }

  static Map<String, Object?> _withReason(
    Map<String, Object?> payload,
    String? reason,
  ) {
    if (reason == null) {
      return payload;
    }
    return <String, Object?>{...payload, 'reason': reason};
  }

  /// 事件 payload 落库前的规范化：空 map → NULL，超 4 KB → 直接拒绝。
  static String? _encodePayload(Map<String, Object?> payload) {
    if (payload.isEmpty) {
      return null;
    }
    final encoded = jsonEncode(payload);
    if (utf8.encode(encoded).length > maxPayloadBytes) {
      throw ArgumentError(
        'thread event payload exceeds $maxPayloadBytes bytes '
        '(${utf8.encode(encoded).length})',
      );
    }
    return encoded;
  }

  static String? _encodeList(List<String>? values) {
    if (values == null || values.isEmpty) {
      return null;
    }
    return values.join('\u0001');
  }
}
