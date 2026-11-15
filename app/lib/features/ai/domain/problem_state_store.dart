/// Problem State Store 的持久化接口与内存实现。
///
/// 这是 `problem_state.dart` 的配套存储层，用来证明「problem node 可以被独立
/// 保存、读取、追加、撤销」。它**不碰数据库**：接口按异步方法设计，后续可以
/// 换成 drift 实现而不改调用方；[InMemoryProblemStateStore] 只在一个 map 里
/// 保存快照，供测试与最小产品接入使用。
///
/// 三条语义：
///
///  * [load] / [save] 交接的是快照（[ProblemState.copy] 的深拷贝），调用方
///    修改 load 出来的对象不会污染 store，store 也不会把内部引用泄漏出去。
///  * [append] 只追加历史事件，不改变事实/假设/决策/未知分栏；条目变更走
///    [ProblemState] 的 addXxx。版本随事件单调递增。
///  * [revoke] 只把节点标成 revoked，**历史一条不删**；revoked 之后
///    [append] / [attachTask] / [markUnknownResolved] 都拒绝写入，但
///    [load] 仍能读到完整历史。
library;

import 'problem_state.dart';

/// problem 状态的持久化接口。
///
/// 目前只有内存实现（[InMemoryProblemStateStore]）。方法都是异步的，是为了
/// 让将来的数据库实现可以直接替换而不改调用方签名。
abstract interface class ProblemStateStore {
  /// 保存/覆盖一个 problem 状态。
  Future<void> save(ProblemState state);

  /// 按 id 读取；不存在返回 NULL（不要编一个空状态）。
  Future<ProblemState?> load(String problemId);

  /// 追加一条**不改变条目分栏**的历史事件，返回追加后的状态快照。
  Future<ProblemState> append({
    required String problemId,
    required ProblemEventKind kind,
    String? refId,
    String? summary,
    Map<String, Object?>? payload,
    int? nowMs,
  });

  /// 把 task 挂到 problem 上；[problemId] 必须非空且存在。
  Future<ProblemTaskLink> attachTask({
    required String problemId,
    required String taskId,
    String? title,
    int? nowMs,
  });

  /// 把一条未知标记为已解决，返回更新后的未知。
  Future<ProblemUnknown> markUnknownResolved({
    required String problemId,
    required String unknownId,
    String? resolution,
    int? nowMs,
  });

  /// 撤销 problem（保留全部历史），返回撤销后的状态快照。
  Future<ProblemState> revoke({
    required String problemId,
    String? reason,
    int? nowMs,
  });

  /// 所有已保存的 problem 快照（测试/审计用）。
  Future<List<ProblemState>> all();
}

/// 内存实现：进程内 map，不写 DB、不落盘。
///
/// 只用于测试与最小接入；进程结束数据就没了，这不是缺陷而是边界。
class InMemoryProblemStateStore implements ProblemStateStore {
  /// [initial] 是预置状态；构造时会各存一份深拷贝，调用方后续修改原对象不会
  /// 影响 store。
  InMemoryProblemStateStore([
    Iterable<ProblemState> initial = const <ProblemState>[],
  ]) {
    for (final state in initial) {
      _problems[state.node.id] = state.copy();
    }
  }

  final Map<String, ProblemState> _problems = <String, ProblemState>{};

  @override
  Future<void> save(ProblemState state) async {
    _problems[state.node.id] = state.copy();
  }

  @override
  Future<ProblemState?> load(String problemId) async {
    return _problems[problemId]?.copy();
  }

  @override
  Future<ProblemState> append({
    required String problemId,
    required ProblemEventKind kind,
    String? refId,
    String? summary,
    Map<String, Object?>? payload,
    int? nowMs,
  }) async {
    _requireProblemId(problemId, 'append');
    final state = _require(problemId);
    state.recordEvent(
      kind,
      refId: refId,
      summary: summary,
      payload: payload ?? const <String, Object?>{},
      nowMs: nowMs,
    );
    _problems[problemId] = state;
    return state.copy();
  }

  @override
  Future<ProblemTaskLink> attachTask({
    required String problemId,
    required String taskId,
    String? title,
    int? nowMs,
  }) async {
    // task 必须引用 problemId：空 id 在这里就拒，不等到落库才炸。
    if (problemId.trim().isEmpty) {
      throw ArgumentError.value(
        problemId,
        'problemId',
        'task 必须引用 problemId，不能独立存在',
      );
    }
    final state = _require(problemId);
    final link = state.attachTask(
      taskId: taskId,
      problemId: problemId,
      title: title ?? '',
      nowMs: nowMs,
    );
    _problems[problemId] = state;
    return link;
  }

  @override
  Future<ProblemUnknown> markUnknownResolved({
    required String problemId,
    required String unknownId,
    String? resolution,
    int? nowMs,
  }) async {
    _requireProblemId(problemId, 'markUnknownResolved');
    final state = _require(problemId);
    final resolved = state.markUnknownResolved(
      unknownId,
      resolution: resolution,
      nowMs: nowMs,
    );
    _problems[problemId] = state;
    return resolved;
  }

  @override
  Future<ProblemState> revoke({
    required String problemId,
    String? reason,
    int? nowMs,
  }) async {
    _requireProblemId(problemId, 'revoke');
    final state = _require(problemId);
    state.revoke(reason: reason, nowMs: nowMs);
    _problems[problemId] = state;
    return state.copy();
  }

  @override
  Future<List<ProblemState>> all() async {
    return [for (final state in _problems.values) state.copy()];
  }

  /// 读取内部快照的深拷贝；不存在的 problem 抛 [StateError]。
  ProblemState _require(String problemId) {
    final state = _problems[problemId];
    if (state == null) {
      throw StateError('没有 problem $problemId；不能对不存在的 problem 写入');
    }
    return state.copy();
  }

  void _requireProblemId(String problemId, String action) {
    if (problemId.trim().isEmpty) {
      throw ArgumentError.value(problemId, 'problemId', '$action 需要 problemId');
    }
  }
}
