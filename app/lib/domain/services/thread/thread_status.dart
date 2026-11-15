/// Thread 节点状态词表（schema v47，2026-11-15）。
///
/// 契约：`INTEGRATION-CONTRACT-2026-11-15.md` §3.4。`tasks.status` 一直是自由
/// TEXT（默认 `todo`），v47 只把语义补全成五值：**列不迁移**，`blocked` /
/// `skipped` 是"加值不加列"。
///
/// 读侧注意：v47 之前所有过滤都是 `!= done`，会把 `blocked` / `skipped` 当成
/// 待办。新代码请用 [isSchedulable]（显式 `todo|doing`），窗口投影可以用
/// [appearsInWindow]（额外包含 `blocked`）。
library;

enum ThreadStatus {
  todo('todo'),
  doing('doing'),
  done('done'),

  /// 卡住：不是失败、不降能力，只记流程事实（`thread_events.stuck`）。
  blocked('blocked'),

  /// 跳过：不是删除，行与标签/内容引用都保留，只是退出 ready 列表。
  skipped('skipped');

  const ThreadStatus(this.id);

  /// 落库用的稳定值（`tasks.status`）。
  final String id;

  /// 会不会进入段 A 的可行集（ready 列表）：只有 `todo|doing`。
  bool get isSchedulable => this == todo || this == doing;

  /// 会不会出现在「本周/本日」窗口投影里（契约 §3.5：含 `blocked`）。
  bool get appearsInWindow => this != done && this != skipped;

  /// 是否终态（done/skipped 归归档）。
  bool get isTerminal => this == done || this == skipped;

  /// 读取 `tasks.status`：NULL/未知值读作 [todo]（列默认值就是 todo）。
  static ThreadStatus fromStorage(String? value) {
    for (final status in values) {
      if (status.id == value) {
        return status;
      }
    }
    return ThreadStatus.todo;
  }
}
