/// 主 `AgentLoop`（普通对话）的运行记录写入端（设计文档 §7.1）。
///
/// 为什么单独一个接口，而不是复用学生模式的 `StudentRunRecorder`：主对话只需要
/// 「run + step」这两件事；学生 recorder 还带过程审计、内容验证与 claim 落库，
/// 那些类型（`ProcessReport` / `Verification` / `Claim`）属于学生 composition，
/// 不该出现在普通对话的依赖里。分开也让主 loop 的测试只需要一个假 sink。
///
/// 依赖方向：domain 定义接口；infrastructure 的 `AgentRunStore` 由应用层
/// （`ai_providers.dart` 的 `AgentRunStoreSink`）适配进来，`agent_loop.dart`
/// 永远不认识数据库表。
///
/// 两个方法都可能在一次用户回合里被调用多次：`saveRun` 在创建、每一步之后和
/// 终态时各写一次（upsert）；`appendStep` 在每个模型回合后追加一条。
library;

import 'agent_run.dart';

/// run / step 的持久化接口。
///
/// 实现方（`AgentRunStore`）只把 [AgentRunState] / [AgentStep] 原样落库：接口
/// 里没有 reasoning 原文的位置，所以「raw CoT 不进数据库」这条约束（设计文档
/// §5.6）在类型层面就成立。
abstract interface class AgentRunSink {
  /// 写入/更新一次运行（同一 id 重复调用是 upsert）。
  Future<void> saveRun(AgentRunState run);

  /// 追加一步。
  ///
  /// [AgentStep.runId] + [AgentStep.seq] 唯一标识一步：调用方负责给出在同一个
  /// run 内单调递增的 seq，重放同一 run 时撞唯一约束正是想要的失败。
  Future<void> appendStep(AgentStep step);
}
