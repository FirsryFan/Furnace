# Furnace Agent Team 设计（同步 DSH 能力）

目标：题库生产不再依赖一次性 subagent；Furnace 原生支持 teammate、任务板、会话事件流、实时指导与审计。

## 为什么

题库生产是多角色长流程：找题、解题、画 DAG、审题、去重。一次性 subagent 只能等最终消息，不能中途纠偏，最终稿看不到真实试错，长期积累大量一次性 session。

## 数据模型（schema v44）

- ai_agent_sessions：id, parent_id, kind, label, status, provider, model, preset, cwd, created_at, updated_at
- ai_agent_events：id, session_id, seq, type, payload, created_at；type 包含 reasoning / text / tool_call / tool_result / step_start / step_end
- ai_agent_tasks：id, title, description, status, owner_session_id, blocked_by, write_scopes, revision
- ai_agent_messages：id, from_session_id, to_session_id, content, status, created_at

关键：reasoning 也落库，不只存最终回答。

## 运行时

- TeamRuntime：spawnTeammate / sendMessage / waitAgent / listAgents / interruptAgent；默认只允许 Lead spawn，teammate 深度上限 1。
- AgentTraceRecorder：在 AgentLoop 的每个事件点同步写入 reasoning、文本、工具参数、工具结果、step 边界。
- TraceReader：按 session 回放、过滤、导出；给 UI 和 reviewer agent 用。
- TaskBoard：claim / complete / edit / set_dependencies / reassign，revision CAS，write scopes 只警告不锁。

## 模型工具

- spawn_teammate
- send_message
- wait_agent
- list_agents
- interrupt_agent
- team_task_create / get / list / update

不再默认暴露一次性 subagent。

## UI

AI 页 Team 面板：成员状态、任务、当前步骤、trace 抽屉；任务板显示 blocked_by 和写入范围。

## 题库工作流

1. Lead 建 task：科目、题数、来源、输出路径、write scope。
2. source agent 找题 + 答案。
3. solver agent 写答案 + 轨迹，DAG agent 生成图。
4. reviewer agent 读轨迹 + 最终稿，找缺环/错图/错答案。
5. duplicate/QA agent 跑指纹与相似题。
6. Lead 只做集成与验收。
7. 每阶段事件进 ai_agent_events，可回放。

## DSH 能力对照（只列需要的）

- 多 provider、tool loop、skills：已有。
- teammate 会话、send_message、wait_agent：P0。
- 任务板 + write scopes：P0。
- reasoning/tool 事件流落库 + trace 回放：P0。
- 一次性 subagent：P1，仅显式开启。
- worktree 隔离：P1，题库暂不需要。
- 定时任务：P2。
- 审批策略：P2。

## 实施顺序

Phase 1：trace foundation（schema v44、Recorder、Reader、测试）。
Phase 2：teammate minimal（TeamRuntime、Lead 工具、任务板，两个 agent 协作测试）。
Phase 3：UI + 题库接入（Team 面板、Trace 抽屉、reviewer 读轨迹）。
Phase 4：可靠性（超时恢复、写入冲突、trace 导出、续跑）。

## 验收

- 能列出全部 teammate 与当前步骤。
- 任意历史 turn 能回放 reasoning + tool call + result。
- Lead 能中途给 teammate 发消息并看到生效。
- 题库生产不依赖一次性 subagent。
- 每个最终 DAG 都能追溯到 solver 的真实轨迹。
