# MindNet 一等用户模型引擎设计（撤销「并入标签」之后）

> 状态：**设计稿，待评审；本文件只做设计，不改代码、不改 schema**。
> 决策依据：`docs/DECISIONS-2026-11.md` 是当前唯一决策登记处，与旧文档冲突时以它为准（`DECISIONS-2026-11.md:4-5`）。
> 本文件落实的决策：D03（MindNet 一等用户模型引擎，撤销并入标签，`:38-55`）、D05（题库四层成熟度，`:69-85`）、D06（全量记录、阈值结论，`:87-95`）、D09（精力由 MindNet 预测，`:118-122`）。
> 用户原话（转引自 `DECISIONS-2026-11.md:45`）："MindNet 并入标签是极大的错误"；"用户状态全权由 MindNet 处理。如果 MindNet 不够，就让 MindNet 扩展，收纳更多功能"。
> 写法纪律：**现状**一律标 `文件:行号`；**目标**标「设计」；读不到/没验证的标「未确认」。本文不跑测试（无代码改动）。

## 0. 一句话结论

MindNet 从「标签树的一部分」恢复为 **Furnace 的用户模型引擎**：事件层全量记录用户行为 → 引擎维护用户状态（记忆/思维/判断）→ 所有个性化消费（找题、改题、扩题、Thread 排序、任务安排、闪卡推送、精力预测、评测、persona）统一从同一份用户状态取数。当前的真正缺口不是算法移植，而是**引擎的运行形态**——仓库里 tierA/tierB 已经接上，但 `run/1` 事件流没有持久化入口、没有幂等 `run_id`、没有存档回退、没有统一读数 API（`MINDNET_ROADMAP.md:14-18` 自述根因："我们把 MindNet 当成给每张卡算两个数的函数用，而它设计成一次运行 = 一批事件 → 一份报告的引擎"）。

## 1. 决策变更：撤销「MindNet 并入标签」

### 1.1 撤销的原文与影响面

| 条目 | 原文位置 | 撤销后的处理 |
| --- | --- | --- |
| "Mindnet 不再作为独立模块：它就是一个树形标签体系，全部并入标签管理" | `DESIGN_BLUEPRINT.md:128-136` | 作废；已在原处加撤销标记（`:130`）。MindNet 重新成为独立顶层模块（`DECISIONS-2026-11.md:50,54`） |
| 决策索引 2.8「Mindnet 并入标签体系」 | `DESIGN_BLUEPRINT.md:262` | 作废，保留作历史 |
| 批次 4「标签体系（合并 Mindnet）」 | `DESIGN_BLUEPRINT.md:226` | 改为标签体系独立，MindNet 单独立项 |
| 目标匹配"节点路径分支不再使用（Mindnet 已并入标签）" | `DESIGN_BLUEPRINT.md:105-109` | 该**依据**失效；但代码可暂不动：`ThreadRanker._goalMatch` 仍同时支持 path 与自由文本（`app/lib/domain/services/scheduling/thread_ranker.dart:416-464`）。是否恢复 path 分支另案评审，本文不擅自改 |
| "Mindnet 并入标签后的树形编辑" | `PROGRESS.md:7799` | 历史记录不改写；引用时需注明已失效 |
| "图就是标签树？" | `OPEN_QUESTIONS.md:77` | 已失效：MindNet 的图 = 标签树投影 ∪ 知识点/线索边等其它节点来源（见 §1.3） |

### 1.2 新分工（谁是用户状态的权威）

| 模块 | 职责 | 不做什么 |
| --- | --- | --- |
| **MindNet** | 用户模型引擎：记忆、思维、判断；维护用户状态；产出个性化决策（找题/改题/扩题、排序、推送、精力） | 不做标签管理；不直接改 FSRS 排期（`MINDNET_CONTRACT.md:530-546` 一列一个写者不变） |
| **标签** | 组织与检索体系（内容域、筛选、卡组范围） | 不承载模型参数、不当用户模型的存储 |
| **AI（AgentLoop）** | 操作代理：调工具读写用户数据；可读 MindNet 结论 | 不直接改 MindNet 状态、不自造用户模型（`docs/AI_DESIGN.md:418-435` 的接口先留空原则） |
| **设置** | 开关、参数、隐私 | 不成为第二套读数面板 |
| **题库** | 内容域：题目/答案/解析/来源/成熟度 | 不定义用户状态（题目质量评估调 MindNet，见 D05） |

### 1.3 旧数据与旧载体的处置

- **`MindMaps` / `MindNodes` 表保留不删**：`app/lib/data/database/tables.dart:244,255`；仓储仍在（`app/lib/data/repositories/mind_map_repository.dart:7`）。原决策就写了"保留不动、UI 下线"（`DESIGN_BLUEPRINT.md:134`）；D03 进一步允许把它们作为 MindNet 图数据的载体复用（`DECISIONS-2026-11.md:53`）。本轮**不迁移、不删除**。
- **`.kpak` 的 mind_map**：`KNOWLEDGE_PACKAGE.md:285` 说思维导图按 external/package id 走既有升级去重；但本仓库 `app/lib/data/package` 下 grep `mind_map` / `MindMap` **无命中**（未确认包内是否真有 mind_map 条目，需查 codec 实际解析路径）。
- **标签树→图投影保留**：`CognitiveGraph` / `CognitiveTag` / `CognitiveNode` / `CognitiveEdge` 仍在（`app/lib/domain/services/cognitive/cognitive_graph.dart:90,128,197,230`；投影入口 `:315`），`ms` 必填、缺条目进 `nodesWithoutMs`。**它只是 MindNet 图的一个来源**，不是"MindNet=标签"的复活。
- **认知图页**：`cognitive_graph_page.dart` 如实画"知识点挂哪些标签"，并声明线索边另有页面（`app/lib/features/cognitive/presentation/cognitive_graph_page.dart:1-28`）。

## 2. 现状盘点（代码为准，文档为证）

### 2.1 已接（已落到代码、有测试/文档台账）

| # | 能力 | 落点（文件:行） |
| --- | --- | --- |
| 1 | tierA 记忆层（R/R0/Σ/S/D） | `app/lib/domain/services/srs/dsr_memory.dart`；行桥接 `dsr_card_state.dart:61`（read）/ `:103`（write）——**本次实读**；窄写 `anki_repository.dart:761`（只写 `encoding_strength`/`savings`，`MINDNET_CONTRACT.md:530-546`） |
| 2 | 可替换接口（模型接缝） | `CognitiveModel` 接口 `app/lib/domain/services/cognitive/cognitive_model.dart:46-154`；`MindNetCognitiveModel` `:252`；`cognitiveModelProvider` `:491` |
| 3 | tierB 快层 + 诊断 + 反事实 | `fast_engine.dart`（`FastMechanisms` `:208`，机制 id `:248-269`）、`fast_diagnosis.dart`（`FastDiagnosis`、`FastPlanner` `:578`，指令库 `:581`，**实读 21 条 = 17 application + 4 executive**） |
| 4 | 元认知（危险区/焦虑区/校准度） | `metacognition.dart:185`；库诊断计算 danger（`library_diagnosis.dart:24-37`） |
| 5 | 节律层 α(τ) 读数与建议 | `rhythm_gate.dart:123`、`study_rhythm.dart:101`；UI 在线程页顶栏（`MINDNET_ROADMAP.md:92-94`） |
| 6 | 控制层 V(π) → 今日计划 | 纯逻辑 `today_plan.dart:1-22`；页面 `features/cognitive/presentation/today_plan_page.dart`；AI 工具 `plan_today` |
| 7 | 材料摄取 / 转写 / 线索边 | `material_ingest.dart`、`material_intake_plan.dart`、`transcribe_run.dart`、`knowledge_edges` 表（`tables.dart:1626-1665`）、界面 `material_intake_page.dart` |
| 8 | `run/1` 执行内核（内存态） | `run_executor.dart:208` `executeRun`；**只动内存图，不写库**（`run_executor.dart:1-25`） |
| 9 | 演练（唯一调用者） | `run_rehearsal.dart:108` `rehearseRun` → `executeRun`（`:233`）；只装 `memory.dsr`、只跑不落库（`:1-23`） |
| 10 | 题目评估（用途 1） | `problem_evaluator.dart` + AI 工具 `evaluate_problem_fit`（`MINDNET_INTEGRATION.md:84-95`） |
| 11 | 顾问式复习排序（bands/zones） | `review_advisory.dart:49,77,178`；段序 `forced→boosted→model→unseen`（`MINDNET_CONTRACT.md:597-608`） |
| 12 | Thread 认知排序档位 | `cognitive_rank.dart:1-39`（全部未标定）；服务接线 `thread_rank_service.dart:161,183,327`；开关 `thread_rank_settings.cognitive_rank_enabled`（`tables.dart:669`） |
| 13 | 机制面板（装了什么/参数/未标定） | `mechanism_catalog.dart:36-45`、`mechanism_reader.dart:1-16`、`mechanism_page.dart`；装配点只有 3 个 setup |
| 14 | 推理层（能力动作/卡点） | `reasoning_prompt.dart`、`capability_action.dart:107`（20 动作）、`stuck_point_evaluator.dart`；落 `reasoning_chains/steps`（`DATA_MODEL.md:450-451`） |
| 15 | 评测板块（v41） | 八张 `cog_*` 表（`DATA_MODEL.md:1390-1411`）；`assessment_center_page.dart`；Thread 参数接口（`ASSESSMENT_DESIGN.md:241-257`） |
| 16 | 顶层入口（本轮已接） | `features/cognitive/presentation/mindnet_page.dart:10-55`（5 个子页导航）；`home_shell.dart:150-159`、`:41-52` |

### 2.2 未接（缺口按"引擎形态"归组）

| 缺口 | 现状证据 | 影响 |
| --- | --- | --- |
| `run/1` 事件流的持久化入口 | 只有校验（`transcribe_run.dart`）+ 内存执行（`run_executor.dart:1-25`）+ 演练（`run_rehearsal.dart:18-19`）；`MINDNET_ROADMAP.md:24` 要求的五类动作没有落库路径 | 事件不能回放、不能重放、不能作为诊断证据 |
| 幂等 `run_id` | `MINDNET_ROADMAP.md:28`；当前幂等只存在于材料批 `batch_id` 与边 id（`tables.dart:1630-1633`），不是 run 级 | 同一批事件重放会重复生效 |
| 存档与回退 | `MINDNET_ROADMAP.md:27`；`features/cognitive` 下 grep 存档/回滚/快照 **0 命中** | 模型状态错了不能回滚，只能靠事前拦截 |
| `result/1` 完整报告 | `RunExecutionReport` 只回给演练页面（`run_rehearsal.dart:49-59`），不落库；`applied/assumptions/trace/diagnosis/metacognition/kc` 未持久化（`MINDNET_ROADMAP.md:26`） | "一次运行 = 一份报告"不成立 |
| 17 条指令库的**完整排序** | 指令已转录 21 条（`fast_diagnosis.dart:581`），但大量 `simulatable: false` 只能给"规则映射"（`:461-463`、`:538-541`）；今日计划只搬运可模拟项（`today_plan.dart:15-19`） | "今天做这几件事"只覆盖可模拟的干预 |
| 参数标定（六实验） | `MINDNET_ROADMAP.md:32`；`MINDNET_CONTRACT.md:559-584`；本仓库 `CALIBRATION.md` 只做"预测 vs 结果"的检验，不写回参数（`CALIBRATION.md:6-7`） | 个性化仍建立在未标定默认值上 |
| 反馈微调（FEEDBACK） | `MINDNET_ROADMAP.md:33` | 用着不会变准 |
| 机制插件化 | 机制清单是编译期数据（`mechanism_catalog.dart:36-45`），用户只有少数开关/滑块：`rhythm_hints_enabled`（`tables.dart:91`）、`goal_mechanism_enabled`（`:103`）、`cognitive_rank_enabled`（`:669`）、`beta_goal` 滑块（`mechanism_catalog.dart:52-80`）；不是 PLUGIN_ARCHITECTURE 的插件架构（`MINDNET_ROADMAP.md:36`） | 扩展机制要改代码发版 |
| 用户级状态存档/时间序列 | 模型状态只落在 `card_states` 两列（`MINDNET_CONTRACT.md:530-546`）；`thread_states` 只有 `energy`/`goal_*`（`tables.dart:590-601`） | 用户状态没有"快照"这一层，消费面各自现算 |
| 精力预测 | 决策已下（`DECISIONS-2026-11.md:118-122`），纯逻辑本轮并行开发；Thread UI 未接 | 精力仍靠手填（`thread_states.energy`，`tables.dart:592`） |
| 闪卡推送 | 只有本地通知（`REVIEW_REMINDER_DESIGN.md:5-15`），"哪天推哪张"与 MindNet 无关 | 推送不个性化 |
| 题目推荐/改题/扩题 | 题库成熟度管线设计未落盘（`docs/` 下无 `QUESTION_MATURITY_PIPELINE.md`）；D05 待办（`DECISIONS-2026-11.md:84-85`） | 消费面缺"题目侧" |
| 评测/persona 并入 | 评测参数只给 Thread 建议、消费侧未接（`ASSESSMENT_DESIGN.md:241-243`）；persona 只进 AI 系统提示、不进模型（`PERSONA_DESIGN.md:100-103`） | 两套用户相关信息并行 |
| 文档/文案滞后 | App 自带说明仍写"run/1 会话协议、元认知层、节律层还没接"（`app/lib/l10n/app_localizations_zh.dart:1785`），实际元认知/节律已接 | 以代码为准，旧文案需回写 |

## 3. 目标架构

### 3.1 三层（设计）

```
[事件层] 全量、追加写、幂等 run_id、可回放
  review / exposure / completion / question_attempt / knowledge(节点·边) / goal / energy(手动) / assessment / persona 编辑
        │  (append-only 事件 + 每次运行的 before/after 状态哈希)
        ▼
[MindNet 引擎] 用户状态权威
  机制：memory.dsr / attention.capacity / attention.ignition / dynamics.shunting / context.goal / rhythm.gate / metacognition.belief
  参数：带 calibrated/未标定 标志；用户开关与滑块可覆盖
  输出：UserStateSnapshot（能力/精力/注意力/危险区/焦虑区/目标可达性/画像）+ 报告(result/1)
        │
        ▼
[消费面] 统一从快照取数，不各自发明代理
  找题·改题·扩题 | Thread 排序 | 今日计划/任务安排 | 闪卡推送 | 精力预测 | 评测档案 | persona 上下文 | AI 工具
```

### 3.2 事件层（设计）

- **两张新表（只设计，不实现）**：`mindnet_events`（append-only：`id` / `occurred_at` / `kind` / `subject_id` / `payload_json` / `source_table` / `source_row_id` / `run_id` 可空 / `created_at`）+ `mindnet_runs`（`run_id` 主键做幂等 / `request_json` / `result_json` / `state_before_hash` / `state_after_hash` / `status` / 起止时间）。
- **事件源映射（现有表即证据）**：`review_logs`（`tables.dart:447-509`）、`exposure_logs`（`:525`）、`completion_logs`（`:619-645`）、`question_attempts`（`:1676`）、`knowledge_edges`（`:1626`）、`thread_states`（`:590-601`，goal/energy）、`cog_assessment_*`（`DATA_MODEL.md:1402-1405`）、`local_settings.user_persona`（`tables.dart:177`）。
- **两条硬口径**：① 全量记录、阈值结论——记录阶段不过滤孤立单题错（D06，`DECISIONS-2026-11.md:87-95`）；② 事件层先做**影子双写**（不改现有读路径），用回放结果与现有派生读数对账后才切主路径。

### 3.3 引擎层（设计）

- **状态**：`MindNetState` = 节点 bag（`memory.dsr` 的 R/R0/Σ/S/D）+ 用户级参数（机制参数的个人值）+ 时间锚点 + 版本号。存档即 `state_hash`；回退 = 用 `state_before_hash` 恢复。
- **读数 API（目标，区别于现有零散函数）**：
  `predict(events, graph, params, persona/priors, at) → UserStateSnapshot`；
  `rank(candidates, snapshot)` / `judge(question, snapshot)` / `recommend(surface, snapshot)` / `explain(state)`。
  现有 `CognitiveModel`（`cognitive_model.dart:46-154`）保留为"单卡接缝"，但**上层消费不再绕过快照**：精力、注意力、危险区从同一份 `UserStateSnapshot` 取。
- **参数纪律**：未标定参数一律外显（`MINDNET_CONTRACT.md:559-584`）；融合权重与阈值不进"测量"叙事（如 `stuck_point_evaluator` 的 0.5 先验，`REASONING_LAYER_DESIGN.md:341-346`）。

### 3.4 消费面（用户点名的四处 + 新增）

| 消费面 | 输入（快照字段） | 现状 |
| --- | --- | --- |
| 找题/改题/扩题 | 能力动作画像、卡点、题目评估、目标可达性 | 找题已接（`find_questions_by_capability`、`compose_paper`）；改题/扩题未接（D05 管线） |
| Thread 排序 / 任务安排 | 注意力 α、精力、目标可达性、学科均衡 | 段 A/B + 认知排序档位已接；精力未接 |
| 闪卡推送 | 到期集合 + 记忆状态 + 节律 | 仅本地定时通知 |
| 精力预测 | completion/review 历史 + 近时负荷 + 节律 | 纯逻辑本轮并行；UI 未接（D09） |
| 评测档案 | 10 能力 / 9 参数 | 已有 `cog_*`，但只作为独立板块 |
| persona | 用户自述（目标/偏好/约束） | 只进 AI 系统提示 |

### 3.5 评测与 persona 如何并入（而不是并行）

| 现有物 | 现状 | 并入方式（设计） |
| --- | --- | --- |
| 评测 10 项能力（`assessment_models.dart:74-98`） | 独立板块；参数只作为 Thread "建议值"、消费侧未接（`ASSESSMENT_DESIGN.md:241-243`） | 作为 MindNet 用户状态的**能力维度观测**（带 uncertainty 与 source），写进快照；不进 `card_states`（`ASSESSMENT_DESIGN.md:151-157` 的"先验≠观测"不破） |
| 评测 9 个认知参数（`assessment_models.dart:152-173`） | 同上 | 作为机制参数的**个人先验**：只改"未标定默认值的起点"，不覆盖用户显式设置；报告里可追溯到源测量 |
| `.cogprofile`（`assessment_cog_profile.dart:17-87`） | 可导出 JSON | 升级为用户模型快照的一种导出格式（保留 `format_version`）；未来可带 `state_hash` 与事件范围 |
| persona（`user_persona.dart:21`、`PERSONA_DESIGN.md:11-16`） | 只注入 AI system prompt，不改参数/不注入解题 | 作为引擎的**定性输入**：目标与偏好的背景，进入 `goal` 上下文与消费面解释文案；**仍然只读**（用户原话是"背景"，不是指令） |
| 能力画像/学习洞察（`chain_insights.dart`、`learning_advice.dart`） | 派生计算，不落库 | 保留为快照的"解释层"，但读数统一从快照取，避免同一概念两份算法 |

原则：**评测是观测源，persona 是背景输入，MindNet 是用户状态的唯一权威**；三者不并行维护同一份"用户画像"。

## 4. 模块与入口设计

### 4.1 现状（本轮已接）

- 顶层导航 8 项：标签 / Thread / Time / 知识 / 题库 / **MindNet** / AI / 设置（`home_shell.dart:150-159`；目的地清单 `:41-52`）。知识库已从顶层下沉到设置（D07，`home_shell.dart:47-48`）。
- `MindNetPage` 只做导航、不复制读数，5 个子页：认知模型 → 知识网络 → 今日清单 → 机制参数 → 评测中心（`mindnet_page.dart:10-55`）。

### 4.2 目标信息架构（设计）

- **看板（首屏）**：今日状态摘要（精力/注意力/危险区/焦虑区/目标可达性）+ "今天做这几件事"。当前子页是分散入口，看板需要一层只读聚合（新增，不是复制计算）。
- **知识图**：标签投影 + 知识点/线索边（`cognitive_graph_page.dart` 的现有画法可继续用；未来并入 knowledge_edges 的展示）。
- **机制**：机制面板（`mechanism_page.dart`）+ 用户开关/滑块；插件化后再扩。
- **今日清单**：`today_plan_page.dart`。
- **评测档案**：`assessment_center_page.dart`；评测并入 MindNet 后**建议合并为一个板块**（`DECISIONS-2026-11.md:130` 待用户确认项 3）。
- **精力预测**（D09）：作为看板与 Thread 顶栏的数据源，不单独开页。

### 4.3 边界

| 边界 | 规则 |
| --- | --- |
| 标签 vs MindNet | 标签只负责组织/检索；MindNet 图可由标签投影，但反向不成立（不把模型状态塞进标签） |
| 设置 vs MindNet | 设置放开关/参数/隐私；MindNet 页放读数与决策；参数编辑入口可互链但不重复实现 |
| AI vs MindNet | AI 可调只读工具读快照、可调写工具改用户数据；**不直接改 MindNet 状态**，模型状态只由事件驱动 |
| 题库 vs MindNet | 题库是内容域；题目成熟度管线（D05）负责内容加工，MindNet 只打分/排序 |
| FSRS vs MindNet | `card_states` 的排期列仍由 FSRS 独占（`MINDNET_CONTRACT.md:530-546`） |

## 5. 分阶段落地（按依赖，不按时间承诺）

| 阶段 | 内容 | 前置 | 验收标准 |
| --- | --- | --- | --- |
| **P0 事件层** | `mindnet_events`/`mindnet_runs` 影子双写；`run_id` 幂等；回放对账 | 无 | 同一批事件重放不重复生效；事件数与既有表行数对账一致；现有复习/排序行为逐字段不变；无事件时消费面行为与今天一致 |
| **P1 状态存档 + 回退** | `state_hash`、存档/回退、只读快照 API | P0 | 回退后哈希复原；缺状态时降级为"无快照"而不是编默认值（沿用 `MINDNET_CONTRACT.md:586-595` 的降级纪律） |
| **P2 统一消费面（第一批）** | 精力预测接 Thread（D09）、Thread 认知排序与今日计划改从快照取数 | P1 | 同一输入确定输出；未标定标注不丢；手动精力覆盖优先 |
| **P3 评测/persona 并入** | 评测作为能力/参数观测源写入快照；persona 作为只读背景输入 | P2 | 评测只影响先验、不覆盖用户设置；persona 不改数值；两者在快照里可追溯 source |
| **P4 `run/1` 持久执行** | run 落库、`result/1` 报告落库、报告页、存档回退 | P1 | `run_id` 幂等；报告含 `applied/assumptions/trace`；回退可复原；与演练读数一致 |
| **P5 题目侧 + 推送** | 找/改/扩题（依赖 D05 成熟度管线）、闪卡推送、题目推荐 | P2 + D05 | 推荐理由可追溯到快照字段；未标定加成显式标注 |
| **P6 标定与插件化** | 六实验标定、反馈微调、机制插件化 | P4/P5 数据积累 | 每个参数有 `calibrated` 标志与出处；插件可开关且不破坏确定性 |

## 6. 风险与未标定纪律

1. **未标定是默认状态**：现有消费面大量使用未标定代理（`cognitive_rank.dart:21-32` 的距离加成/注意力强度；`today_plan.dart:15` 的 `uncalibrated` 恒真；`stuck_point_evaluator` 的 0.5 融合）。并入 MindNet 后必须继续外显，不得因为"统一了 API"就把代理值包装成测量。
2. **不伪造状态**：没有事件就没有快照字段，降级要明说（"诊断没跑"≠"健康"，`MINDNET_CONTRACT.md:594-595`）；缺 `ms` 不编 0.8（`run_rehearsal.dart:10-12` 的做法沿用）。
3. **两个 id 空间**（标签 vs 知识点）未解决（`MINDNET_INTEGRATION.md:346`；`THREADFLOW_TWO_SEGMENT.md:221-253`）。事件层必须显式声明 id 空间，否则"同一概念两套 id"会在回放时变成静默错配。
4. **写所有权不变**：`encoding_strength`/`savings` 仍只由认知模型窄写；`stability/difficulty/due_at` 仍归 FSRS（`MINDNET_CONTRACT.md:530-546`）。事件层是"追加日志"，不是"第二写者"。
5. **性能**：事件全量回放 + 一次读全库（`daily_study_plan_reader.dart:11-12` 已承认"一次读全库、行数万级以内"）在数据变大后要增量投影；设计上优先"快照 + 增量事件"而不是每次全量重跑。
6. **文档滞后**：已有文案/文档与现实不符（`app_localizations_zh.dart:1785`）；每阶段结束必须回写 `MINDNET_ROADMAP`/`MINDNET_INTEGRATION` 状态，否则下一轮又以旧文为准。
7. **明确不做**：不做云同步/账号（`DECISIONS-2026-11.md:20`）；不把 MindNet 做成标签树；本轮只出设计，不动 schema（D03 待办见 `DECISIONS-2026-11.md:55`）。

## 7. 证据缺口 / 未确认

- 本文**未读 MindNet 仓库源码**（仓库外 `E:\Document\MindNet`），对 `run/1`、`result/1`、`存档回退`、`17 指令`、`KC v2`、`PLUGIN_ARCHITECTURE` 的描述全部来自仓库内二手转述（`MINDNET_ROADMAP.md:5-7`、`MINDNET_CONTRACT.md`、`MINDNET_INTEGRATION.md`）。
- `MINDNET_INTEGRATION.md` 的部分行号是 2026-10-01 实测快照（如 `fast_engine.dart:1041`），与本次并行改动后的行号可能漂移；本文正文引用代码行号以**本次实读**为准，二手行号已尽量替换。
- `.kpak` 是否携带 mind_map 条目**未确认**（`app/lib/data/package` 下 grep 无 `mind_map`/`MindMap` 命中；`KNOWLEDGE_PACKAGE.md:285` 只说明升级去重规则）。
- 精力预测的纯逻辑由并行任务实现中（D09），本文只给接口目标，未引用其最终 API。
- 题库成熟度管线设计（D05）落盘与否未确认（`docs/` 下无 `QUESTION_MATURITY_PIPELINE.md`）。
- 未运行任何测试/构建（本文无代码改动）；`MindNetPage` 与其 shell 接线是 2026-11-01 并行改动，本文只按当前代码读了结构与导航清单。
