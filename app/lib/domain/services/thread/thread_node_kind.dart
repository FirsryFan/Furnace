/// ThreadFlow 节点种类（schema v47，2026-11-15）。
///
/// 契约：`INTEGRATION-CONTRACT-2026-11-15.md` §3.2。一个「可坐下完成的单元」=
/// 一个可调度节点；组卷/周/日/复习只是同一张 `tasks` 表里的节点，**不是**第二张
/// 计划表。调度入口仍然只有 `ThreadRankService`。
///
/// 落库口径：`tasks.kind` 可空，NULL 读作 [task]（老库每一行语义不变）。
library;

enum ThreadNodeKind {
  /// 普通任务/练习节点（默认；老库 NULL 行也是它）。
  task('task'),

  /// 一套卷（组卷结果物化成的节点）。
  paper('paper'),

  /// 周容器。
  week('week'),

  /// 日容器（parent = week 节点）。
  day('day'),

  /// 复习到期卡容器（payload 里只放 card_state_ids，不逐卡建节点）。
  review('review');

  const ThreadNodeKind(this.id);

  /// 落库用的稳定值（`tasks.kind`）。
  final String id;

  /// 容器节点不参与段 A 排序/红名单（契约 R9）。
  bool get isContainer => this == week || this == day;

  /// 读取 `tasks.kind`：NULL/未知值读作 [task]。
  ///
  /// 不抛错是刻意的：这一列是 v47 才加的，任何老行都是 NULL；未知值也只可能
  /// 来自被改坏的文件，把它当普通任务显示比让整个 Thread 页崩掉好。
  static ThreadNodeKind fromStorage(String? value) {
    for (final kind in values) {
      if (kind.id == value) {
        return kind;
      }
    }
    return ThreadNodeKind.task;
  }
}
