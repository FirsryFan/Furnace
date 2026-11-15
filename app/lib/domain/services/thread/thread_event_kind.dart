/// ThreadFlow 事件种类（schema v47，2026-11-15）。
///
/// 契约：`INTEGRATION-CONTRACT-2026-11-15.md` §3.4；任务书 `task-62` 规定底座
/// 只落七种事件：`created` / `planned` / `started` / `submitted` / `stuck` /
/// `skipped` / `completed`。`task-90`（B7）按契约 §3.4 的「重开」一行补上
/// `reopened`，词表变八种；`thread_events.kind` 本来就是 TEXT，**不加列、不迁移**。
///
/// 说明一处命名差异（必须写下来）：契约里卡住事件叫 `blocked`，任务书叫
/// `stuck`。本版按任务书的 `stuck` 落库；它驱动的**状态**仍是
/// `ThreadStatus.blocked`。两者是同一个事实，不要同时写两种字符串。
///
/// 三条硬规则（契约 §3.4 / §7.1）：
///  * **完成 ≠ 提交**：完成是人说做完了；提交是有可核对的答案产物。
///  * **卡住不是失败**：不写正确性、不降能力，只记流程事实。
///  * **跳过不是删除**：行保留、内容引用保留，只是退出 ready 列表。
library;

import 'thread_status.dart';

enum ThreadEventKind {
  /// 节点被创建（物化/手动建任务的第一步）。
  created('created'),

  /// 节点被排期（dueAt/expectedAt/estimate/energy 等调度字段落库）。
  planned('planned'),

  /// 开始做（todo/blocked → doing，stamp `started_at`）。
  started('started'),

  /// 提交答案/交卷（状态不变；payload 带 verdict/attempt_ids 等）。
  submitted('submitted'),

  /// 卡住（todo/doing → blocked；payload 带 reason）。
  stuck('stuck'),

  /// 跳过（todo/doing/blocked → skipped）。
  skipped('skipped'),

  /// 完成（todo/doing → done；写 `completion_logs` 快照）。
  completed('completed'),

  /// 重开/恢复（blocked/skipped/done → todo；清 `completed_at`，**不回滚**
  /// `completion_logs`——历史即事实）。
  ///
  /// 契约 §3.4 的「重开」一行只写 `done/skipped→todo`；本版把 `blocked` 也加进
  /// 允许来源，因为 UI/AI 需要一个"误点卡住/跳过之后回到待办"的入口，而
  /// `blocked` 同样不是终态、没有任何完成事实要被回滚。
  reopened('reopened');

  const ThreadEventKind(this.id);

  /// 落库用的稳定值（`thread_events.kind`）。
  final String id;

  /// 这个事件会把任务迁到哪个状态；`null` = 不改状态（created/planned/
  /// submitted 只记事实）。
  ThreadStatus? get targetStatus => switch (this) {
        ThreadEventKind.created => null,
        ThreadEventKind.planned => null,
        ThreadEventKind.started => ThreadStatus.doing,
        ThreadEventKind.submitted => null,
        ThreadEventKind.stuck => ThreadStatus.blocked,
        ThreadEventKind.skipped => ThreadStatus.skipped,
        ThreadEventKind.completed => ThreadStatus.done,
        ThreadEventKind.reopened => ThreadStatus.todo,
      };

  /// 只有完成写完成快照；提交/卡住/跳过/重开都不写（契约 §3.4）。
  bool get writesCompletionLog => this == ThreadEventKind.completed;

  /// 允许从哪些状态触发。空集 = 不限制（created/planned/submitted 只追加事实）。
  ///
  /// 完成只允许 `todo|doing`：卡住的任务必须先恢复再做，否则「blocked → done」
  /// 会把"卡住过"这段流程事实从状态里抹掉。
  ///
  /// 重开只允许 `blocked|skipped|done`：它们是"离开待办"的三种状态
  /// （`doing → todo` 不是恢复，是倒退，故意不开放）；从 `done` 重开只清
  /// `completed_at`，不删也不能删 `completion_logs`。
  Set<ThreadStatus> get allowedFrom => switch (this) {
        ThreadEventKind.created => const <ThreadStatus>{},
        ThreadEventKind.planned => const <ThreadStatus>{},
        ThreadEventKind.started => const <ThreadStatus>{
            ThreadStatus.todo,
            ThreadStatus.doing,
            ThreadStatus.blocked,
          },
        ThreadEventKind.submitted => const <ThreadStatus>{
            ThreadStatus.todo,
            ThreadStatus.doing,
          },
        ThreadEventKind.stuck => const <ThreadStatus>{
            ThreadStatus.todo,
            ThreadStatus.doing,
          },
        ThreadEventKind.skipped => const <ThreadStatus>{
            ThreadStatus.todo,
            ThreadStatus.doing,
            ThreadStatus.blocked,
          },
        ThreadEventKind.completed => const <ThreadStatus>{
            ThreadStatus.todo,
            ThreadStatus.doing,
          },
        ThreadEventKind.reopened => const <ThreadStatus>{
            ThreadStatus.blocked,
            ThreadStatus.skipped,
            ThreadStatus.done,
          },
      };

  /// 读取 `thread_events.kind`；未知值返回 `null`（读侧只跳过，不崩）。
  static ThreadEventKind? fromId(String? id) {
    for (final kind in values) {
      if (kind.id == id) {
        return kind;
      }
    }
    return null;
  }
}
