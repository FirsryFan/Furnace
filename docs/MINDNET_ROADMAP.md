# MindNet × Furnace 扩展路线图（2026-10-11）

> 起因：用户指出"认知模型的功能完全不止这一点点"，要求 Furnace 覆盖更广——
> 找题时有用、闪存卡时有用、给题目补资料时有用、给事件排序（Thread）时也有用。
> 本文件把 **MindNet 文档里已经存在** 的能力与 **Furnace 已接入** 的部分逐条对齐，给出缺口与落地顺序。
> MindNet 侧依据（只读）：`E:\Document\MindNet\docs\{IO_PROTOCOL,MODEL_v2_MATH,CALIBRATION,FEEDBACK,INGEST}.md`、
> `docs\archive\TRANSCRIBE.md`、`docs\PLUGIN_ARCHITECTURE.md`、`MEMORY_RECORD.md §3.5`。

## 0. 一句话现状

我们接进去的是：**tierA 记忆层（R/R0/Σ/S/D）+ tierB 快层（shunting/capacity/ignition/goal）+
卡点诊断与反事实可达性 + 顾问式排序（bands）+ 只读读数页/探针 + 用途 1 工具 + 元认知层（危险区/焦虑区/校准度，轮次二十一）+
测评层（抽象参数先验 R0/D/fluency，轮次二十三～二十五）**。
没接进去的是：**`run/1` 会话协议的五类动作、节律层 α(τ)、
17 条指令库与反事实规划器的排序输出、KC v2 完整报告、参数标定、反馈微调、材料摄取（INGEST/TRANSCRIBE）、机制插件化**。

**根因**：我们把 MindNet 当成"给每张卡算两个数"的函数用，而它设计成"一次运行 = 一批事件 → 一份报告"的**引擎**。
`IO_PROTOCOL.md` §2/§4 才是它的正面接口。

## 1. MindNet 已提供、Furnace 尚未使用的能力

| MindNet 能力 | 出处 | 一句话 |
| --- | --- | --- |
| `mindnet.run/1` 五类动作：`time` / `review` / `exposure` / `knowledge` / `goal` | IO §2.2 | 模型吃的是**事件流**，不只是评分；`exposure`=看了没测、`knowledge`=加节点/边、`goal`=这次要推进什么 |
| `review` 的细分语义：`correct` / `wrong` / `wrong+reviewed_solution` / `blank`，可带 `grade`/`closeness`/`evidence`/`confidence` | IO §2.3 | "做错"与"做错后对过答案"是**两条不同机制路径**（实测 25 倍差距）；Furnace 现在只写 R0/Σ |
| `mindnet.result/1`：`applied[]`（每条动作的前后值）、`assumptions[]`、`trace.slow[]`/`rounds[]`、`result.diagnosis[]`、`metacognition`、`kc.gap/penalty/gap_parts/internalization` | IO §4、MATH §8 | 一次运行给一份**可解释报告**，而不是两个标量 |
| 存档与回退（"即时存档"） | IO §5 | 错了靠回滚，不靠事前拦截 |
| 幂等 `run_id` | IO §2.1 | 同一批事件重放不会重复生效 |
| **节律层 α(τ)**：占空比/两态马尔可夫/θ 采样 + 警觉衰减 `G_vig` + **负荷自适应周期** `T_cycle=T0(1+λ_L·L_DAR/W_DAR)` + flow 正反馈带 `[θ,1.2C]` | MATH §5 | "信息一多就转不动"可计算；太难劝退、太易走神 |
| **元认知层**：自信 `b_v`（只看流畅度/R0/近期曝光，**刻意不看 S**）→ **危险区**（以为会其实不会）/ **焦虑区**（会但不敢用）/ 校准度 κ | MATH §6 | 直接回答"该练什么、别再刷什么、我对自己认识准不准" |
| **控制层 17 条指令库 + 反事实规划器** `V(π)=ΔR/cost`（分 `retention`/`reachability` 两种度量、克隆参数隔离、峰值驱动、曾点亮又回落单列） | MATH §7 | 输出"今天该做的练习清单"，按收益/成本排序 —— **日计划的纯逻辑核心已完成（轮次五十九：`app/lib/domain/services/scheduling/today_plan.dart`，卡片侧 ΔR、题目侧 `V`、两种度量各自标出，9 例）；接进 AI 工具已完成（轮次六十：`plan_today`，日计划直接问得到，7 例）；界面上的清单页也已完成（轮次六十一：复习页 AppBar「今日清单」→ `app/lib/features/cognitive/presentation/today_plan_page.dart`，7 例）** |
| **参数标定协议**：6 个实验 → 把 `ls`/`W_DAR`/`β_goal`/`kappa_reach`/`T_ign` 等未标定参数标出来 | CALIBRATION §2 | 个性化真正的来源 |
| **反馈微调**：更新律（一道题 1 bit）+ 与其它模块的接口 | FEEDBACK §1/§2/§5 | 用着用着自己变准 |
| **材料摄取 INGEST**：`mindnet.material/1` 记号 → 提取 → 转化为节点/边/记忆记录 | INGEST §2–§4 | 资料进模型的正规入口 |
| **照片转写 TRANSCRIBE**：照片 → 判读决策树 → **直接生成 `run/1`**（出处/置信度必填） | TRANSCRIBE §2–§4 | 拍照即入库，不只是"生成卡片" |
| **机制插件架构**：槽位 + 清单 + **用户侧开关/滑块** + 验收契约 | PLUGIN_ARCHITECTURE §3/§5/§7 | "覆盖全面"的正规做法：机制可插拔，而不是继续硬编码 |

## 2. 按四个使用面拆（用户点名的四处）

### A. 找题（趋势：从"评价一道题"到"按我的状态排题"）

- **已有**：`evaluate_problem_fit`（只读工具）→ `ProblemEvaluator` + `CognitiveModel`，给 6 类判定 + 排序键 + 人话理由。
- **缺**：① ~~控制层 `expected_gain`/反事实 `V(π)` 真正参与排序（现在只到判定）~~ **已进排序（轮次五十六）**：`ProblemEvaluator` 把 `FastPlanner` 的 `V(π)=ΔR/cost` 用作**同分档的次序与解释**（`compareByRank`：`rankKey` → `V(π)` → `problemId`），理由行带上"为什么排这里"；它**没有**并进 `rankKey`（加成与成本全部未标定，混进主键会让提示看起来像测量），`retention` 侧没有 `RetentionProbe` 时仍是"未模拟"（不是 0 增益）；~~`retention` 侧缺探针~~ **`retention` 侧已完成（轮次五十七–五十八：`FastMechanisms.memory` 按需装 `memory.dsr`，`dsrRetentionProbe()` 读同一个 bag，`ProblemEvaluator` 已把探针传进 `FastPlanner.plan`）**；
  ② 节律 α(τ) 决定"现在适合做难还是易"（读数与建议已完成轮次四十七；认知排序的精力项已完成轮次五十四）；③ 题目来源（组卷网 skill）与题源质量判据。
  （原列的"元认知危险区优先"已在轮次二十二实测后撤回：见下方"切片 3 的追加"。）
- **落点**：`problem_evaluator.dart` 增加 `retention|reachability` 双度量排序；AI 工具输出里带上"为什么排这里" ✅ **`reachability` 侧已完成（轮次五十六）**，`retention` 侧的记忆层与探针已就位（轮次五十七：`memory.dsr` 可装进快层 + `dsrRetentionProbe()`），并已传进 `FastPlanner.plan`（轮次五十八）：`retention` 指令现在能给出真实价格（"复习能买回多少留存"），两种度量按 `V` 竞争、`metric` 随值一起上报。

### B. 闪存卡复习（趋势：把"评分"升级成"事件流"）

- **已有**：tierA 全量 + tierB 快层 + 四段 bands + forced 重来 + 顾问式排序（不改到期日）。
- **缺**：① ~~`exposure`（看了没测）——读书/看补充资料也该进模型~~ **已完成（轮次四十四）**：复习页"读过，没测自己" → `exposure_logs` + `reread` 事件；
  ② `wrong+reviewed_solution`/`closeness`/`grade` 的细分语义（现在只写 R0/Σ）；
  ③ `run/1` 的幂等与存档回退；④ FEEDBACK 微调；⑤ 参数标定。
- **落点**：`ReviewService.grade()` 改成构造一条 `review` 动作（含 reviewed_solution/closeness）✅ 已完成（轮次三十六），
  "读过"入口发 `exposure` ✅ 已完成（轮次四十四，`ReviewService.recordExposure`）；
  两张表之外的写入仍然只有 `encoding_strength`/`savings` 两列（D2 不变）——曝光也只写这两列，FSRS 一列不碰。

### C. 给题目/知识点补充资料（趋势：资料进图，而不是只当附件）

- **已有**：附件、知识包导入、AI 图片→闪存卡、markdown/LaTeX 渲染。
- **缺**：① INGEST 的 `mindnet.material/1`（材料 → 节点/边/记忆记录）—— **确定性转化已完成（轮次六十二：
  `app/lib/domain/services/ingest/material_ingest.dart`，与 MindNet `src/ingest.js` 逐字段对拍，56 例）；
  "信封 → 要建哪些知识点/连接、每条出处"的提案层与只读 AI 工具已完成（轮次六十三：
  `material_intake_plan.dart` + `ingest_material` 工具，21 例；同名知识点标"不重复建"、主题分组默认只报不建）；
  **落库与确认写入已完成（轮次六十四：schema v17 两张表（`material_intake_batches` /
  `material_intake_proposals`）+ `apply_material_intake` 工具，20 例；批次主键就是信封的 `batch_id`：
  同一条提案确认两次不会建出两个知识点，用户改过标题也认 `external_id`；连接没有落点，如实报 `deferred`
  并留在待办里 —— 落点已在轮次六十八定下（`knowledge_edges`，见后）)**；界面入口已完成（轮次六十五：设置页「添加资料」→ 贴信封 → 看提案 → 勾选确认，
  22 个 l10n 键 + `material_intake_reader.dart` + 页面，8 例）；**连接落点与关联类型已完成（轮次六十八：
  schema v18 的 `knowledge_edges` 线索边表，连接可勾、两端都在才落、缺端 `deferred`；包含语义仍只在
  标签树 `tags.parent_id`；全量 `+1826 ~2`）**；**关掉页面之后的入口已完成（轮次六十九：待确认清单 ——
  `readPendingBatches`/`readPendingBatch` 不重算、只把当初登记的提案读回来接着确认，页面 11 例）**）**；
  ② `knowledge` 动作（新知识点、新连接）；
  ③ TRANSCRIBE 的"照片 → `run/1`"（含出处/置信度）—— **确定性那一半已完成（轮次六十六：
  `app/lib/domain/services/ingest/transcribe_run.dart` + `check_transcribe_run` 只读工具，
  40 例；`checkRunRequest` 已与 MindNet `src/io/run.js` 的 `validateRequest` 逐条对齐，
  输出与 `tools/io_check.js` 同构：硬错整份拒绝、建议不拦、每条动作预告落到哪条机制路径；
  给上游模型的提示词（含【图清单】）由库里知识点的 `external_id` 生成 —— 所以模型不许发明
  节点 id。**调模型那半段也已完成（轮次七十六：
  `app/lib/features/cognitive/application/photo_transcribe_service.dart` —— 压缩重编码 → 提示词 →
  真的把照片发出去 → 回话解码 → 自检，12 例），界面入口与"把请求真的跑进引擎"未做）**；
  ④ 资料与卡片的关联类型（线索边 vs 包含边，MEMORY_RECORD §3.5 已澄清语义差异）
  —— **已完成（轮次六十八：schema v18 新表 `knowledge_edges` + `apply` 落边，`dart analyze` 0 error；
  两种语义各归各家：包含只在标签树 `tags.parent_id`，线索边严格有向、`ls` 存但标 `ls_calibrated: false`、
  `origin` 记材料里的关系；缺一端就 `deferred` 绝不编边；连接在界面上不再置灰）**。
- **落点**：新增"添加资料"入口 → 生成 `knowledge` 动作 +（可选）新卡片；把出处写到 `evidence`，进 `change_log`。

### D. Thread 事件排序（趋势：用注意力与目标可达性排序，而不是只加权求和）

- **已有**：`ThreadRanker` 加权公式（紧迫度/目标匹配/状态适配/期望压力/同类疲劳）+ 硬约束 + 疲劳惩罚。
- **缺**：① **节律层 α(τ)**：警觉衰减、负荷自适应周期（`T_cycle`）、flow 带 → "现在该做难还是易、要不要切换/休息"
  ——**机制侧已完成（轮次四十五：`rhythm.gate` 作为 opt-in 机制装进 `fast_engine.dart`，默认关）**；
  **读数与建议已完成（轮次四十七：线程页顶部给出可用性百分比 + 已专注分钟 + 做难/做易/休息建议，
  带隐藏按钮与 AppBar 菜单开关，schema v15 持久化；`t_on` 由既有学习日志推导，是未标定代理）**；
  仍缺的是把认知排序档位**接进** `thread_rank_service.dart`：**算法核心已完成（轮次五十，
  `app/lib/domain/services/scheduling/cognitive_rank.dart`，21 例；素材读取已完成（轮次五十二），
  开关已落库（轮次五十三：schema v16 的 `thread_rank_settings.cognitive_rank_enabled`，默认关）；
  服务接线已完成（轮次五十四：`ThreadRankService.build()` 吃 `CognitiveRankSeed` + 开关，
  `ThreadFeed` 暴露 `cognitiveRank` / `cognitiveFor` / `cognitiveReasonFor`，开关打开后
  `readyTasks` 的次序真的会变；**UI 开关与"未标定"标注也已完成（轮次五十五：线程页 AppBar
  菜单里多一项"认知排序（目标 + 刚复习过）"，打开后列表上方出现"加成未标定，只是次序提示"
  的说明行；`threadCognitiveRankToggle` / `threadCognitiveRankNote` 两个 ARB 键）**）**；
  ② `goal` 动作的**目标扩散**：目标集可达性排序（与 MindNet 的 `start_diffusion(starts, targets)` 对齐）；
  ③ 把"当前脑子里的东西"（刚复习/刚做错的节点）作为 `starts` 注入。
- **落点**：`thread_rank_service.dart` 增加一个"认知排序"档位（与现有加权排序并存，可开关），输入 = 目标节点 + 刚活动节点 + α(τ)；
  权重未标定处一律标注（沿用现有"未标定"标注纪律）。

## 3. 落地顺序（按"用户可见收益 / 风险"排）

| 序 | 切片 | 为什么先做 | 验收 |
| --- | --- | --- | --- |
| 1 | **`run/1` 会话协议（tierA+B 全字段）+ 存档回退** | 它是其余一切的地基：没有事件流就没有元认知/标定/反馈 | 一次复习会话产出一份 `result`：`applied[]` 每条含前后值、`trace.rounds[]` 有轮次快照；`run_id` 幂等；回滚后 state_hash 复原 |
| 2 | **`exposure`（看了没测）+ `wrong+reviewed_solution`/`closeness`** | 直接改变 R/S 走势（实测 25 倍差距），且给"补充资料"提供入口 | 读一次资料后 R/S 轨迹与只做错不同；两条路径有测试钉住 ✅ **已完成（轮次三十六 + 轮次四十四）** |
| 3 | **元认知层（危险区/焦虑区/校准度）** | 用户能直接看懂、直接指导复习与找题 | 读数页新增危险区/焦虑区清单与 κ（已完成轮次二十一）；`evaluate_problem_fit` 把危险区排前——**试过，实测不成立，已撤回**（轮次二十二） |
| 4 | **节律层 α(τ)（含负荷自适应周期与 flow 带）** | Thread 排序与"何时休息/切换"需要它 | 线程页出现"当前注意力可用性"与建议（做难/做易/休息），有开关可关 —— **机制侧已完成（轮次四十五：`FastMechanisms.rhythm` 可开关、默认关，装后 `availability` 真的 < 1）；读数与建议已完成（轮次四十七：线程页顶部读数 + `_RhythmToggle` 开关，schema v15 持久化，`app/test/features/thread/presentation/thread_status_bar_test.dart` 4 例钉住"开关关掉就不显示"）；**认知排序档位的算法核心已完成（轮次五十：`app/lib/domain/services/scheduling/cognitive_rank.dart`，21 例，纯逻辑；与 D12 的 1.8/1.3 刻意分成两组常量），素材读取（轮次五十二：`app/lib/features/thread/application/cognitive_rank_reader.dart`，9 例）与开关（轮次五十三：schema v16，默认关）已就位；服务接线已完成（轮次五十四：`ThreadRankService.build()` 吃 seed + 开关，`ThreadFeed` 暴露认知次序与理由，7 例钉住「关着完全不动 / 有读数才越位 / 难度只认置信度 > 0 的先验」）；UI 开关与"未标定"标注已完成（轮次五十五：AppBar 菜单开关 + 列表上方说明行，widget 测试钉住开关落库与标注出现/消失） |
| 5 | **控制层指令库 + 反事实规划器排序** | 从"诊断"升级到"今天做这几件事" | 每月/每日计划输出按 `V(π)` 排序的练习清单，含 `retention/reachability` 度量标注 —— **`reachability` 侧已进入找题排序（轮次五十六：`evaluate_problem_fit` 的次序在同分档内按 `V(π)` 排，输出 `counterfactual{metric,instruction,value,why}` 与理由行"为什么排这里"）；`retention` 侧的记忆层与生产探针已就位（轮次五十七：`memory.dsr` 按需装进 `FastEngine`，`dsrRetentionProbe()` 读 `node.m['memory_dsr']`，默认不装所以轮次数值不变），并已传进 `FastPlanner.plan`（轮次五十八）**；日计划的纯逻辑核心已完成（轮次五十九：`app/lib/domain/services/scheduling/today_plan.dart`，把到期卡与已定价的题目合成一份按 `V(π)` 排的清单，9 例）；接进 AI 工具已完成（轮次六十：`plan_today`，模型可直接问出这份清单，每条带 `metric`/`V`/人话理由，7 例）；界面上的清单页也已完成（轮次六十一：复习页 AppBar → `app/lib/features/cognitive/presentation/today_plan_page.dart` + 读法 `application/today_plan_reader.dart`，到期卡逐条给 `metric`/`V`/人话理由、没有价格的行不编 0.0、被上限挡住的件数如实报，7 例）** |
| 6 | **材料摄取（INGEST/TRANSCRIBE）** | 补资料→进图，照片→run/1 | 一份材料生成节点/边 + `evidence`；照片流程产出合法 `run/1` 并过 `io_check` 类校验 —— **一半已完成（轮次六十二：材料信封 → 标准清单 + 图补丁 + `mindnet.run/1` 请求的 Dart 端口，`PARITY OK`（6 节点 / 7 边 / 14 动作），56 例）；"信封 → 待确认提案（知识点/连接 + 每条出处）"的纯逻辑与只读 AI 工具已完成（轮次六十三：`material_intake_plan.dart` + `ingest_material` 工具，21 例；同名知识点标"不重复建"、主题分组默认只报不建）；**落库与确认写入已完成（轮次六十四：schema v17 + `apply_material_intake`，20 例；幂等键是信封的 `batch_id`，`external_id` 认得出改过标题的点，连接如实报 `deferred`）**；界面入口已完成（轮次六十五：设置页「添加资料」→ 贴信封 → 看提案（知识点/连接 + 出处）→ 勾选确认，确认前仍不写知识点，8 例）；**TRANSCRIBE 的确定性那一半已完成（轮次六十六：`app/lib/domain/services/ingest/transcribe_run.dart` + `check_transcribe_run` 只读工具，40 例；校验与 `src/io/run.js` 的 `validateRequest` 逐条对齐，输出与 `tools/io_check.js` 同构 —— 硬错整份拒绝、建议不拦、每条动作预告落到哪条机制路径；提示词含由库里 `external_id` 生成的【图清单】）**；**关联类型与连接落点已完成（轮次六十八：schema v18 的 `knowledge_edges` 线索边表 —— 严格有向、`ls` 带 `ls_calibrated: false` 未标定标记、`origin` 记关系；包含语义仍只在标签树 `tags.parent_id`；两端都在才落，缺端报 `deferred` 不编边；连接在界面上不再置灰；全量 `+1826 ~2`）**；**从"待确认清单"恢复已完成（轮次六十九：`readPendingBatches`/`readPendingBatch` 不重算、把那批还没点头的读回来接着确认，确认后"还剩 N 条"与清单读数一致，页面 11 例）**；**线索边的读法已完成（轮次七十：`KnowledgeEdgeRepository.all()` 按 `knowledge_points.external_id` 解出两端标题、缺端照实显示 id、`ls` 一律带"未标定"，知识模块 AppBar 进只读清单页，8 例）**；**按知识点看线索边已完成（轮次七十一：`KnowledgeEdgeRepository.forPoint()` 把出边入边一起读回来，`KnowledgePointEdgesSection` 站在这个点的角度说"它指向谁 / 谁指向它"，手写的点没有 `external_id` ⇒ 说"不在图里"而不是"没有边"，5 例新增）**；**手写/删除边已完成（轮次七十二：`KnowledgeEdgeRepository.createManualEdge`/`deleteManualEdge`/`graphPoints` —— 第二个写者，`origin: 'manual'`、`ls` 留空；两端都必须在图里、同一方向只留一条不管谁写的、只有手写边能这样删；详情里"加一条线索边"与仅对手写边出现的删除按钮，11 例新增）**；**已经确认完的历史已完成（轮次七十三：`MaterialIntakeBatch.appliedCount` + `appliedProposals()`，页面"已经确认完的（N 批）"只读对话框回答"我上次到底建了什么"；判据是库里现在的数 —— 还有落不了的连接就不叫确认完，1 例新增）**；**顺着线索边走已完成（轮次七十四：端点名字可点 —— `showKnowledgeEdgeWalk` 开一个只读对话框走到那一端，出边入边都站在那一端说方向，可一层层接着走；清单页与知识点详情两处同一走法，2 例新增）**；**成绩单落进历史已完成（轮次七十五：schema v19 的 `material_intake_proposals.already_existed` —— 确认那一刻"这条本来就有的"随提案落库，历史对话框里标"已存在，不重复建"，幂等重放不覆盖第一次的判断，2 例新增）**；**照片的调模型那半段已完成（轮次七十六：`app/lib/features/cognitive/application/photo_transcribe_service.dart` —— 压缩重编码 → 提示词 → 真的把照片发给视觉模型（工具列表为空）→ 回话解码 → 自检，失败六态全部返回人话结果对象、没到发图那一步一个请求都不发，12 例；界面入口未做）**；**照片的界面入口已完成（轮次七十七：材料页上"选一张照片"按钮 + 只读报告对话框 —— 合不合法 / 真正发出去的图尺寸 / 动作与带出处条数 / 硬错 / 会做什么 / 建议 / 模型原话；`photoPickerProvider` 与 `visionEncoderProvider` 两个注入点让测试既不弹系统对话框也不解码图片；照片这条路不执行请求、一个字都不写库，2 例新增）**；**把 `run/1` 真的跑进引擎已完成（轮次七十八：`app/lib/domain/services/ingest/run_executor.dart` 的 `executeRun` —— 五种动作各自落到预告里那条机制路径（`retrieval_success`/`lapse`/`retrieval_failure_feedback`/`reread`/`graph.add_node`/`graph.add_edge`/`start_diffusion`/`hours.advance`），痕迹与预告同构所以能直接对账；时间基 `at.model_hours` 优先，只给 `at.wall` 用锚点换算并把换算记进 `assumptions`，都没有就停在那一条 —— 不默默用"现在"；失败不抛异常、已跑过的不撤销；顺手修掉 `MaterialRunAction.modelHours` 把"只给 `at.wall`"当成"模型时刻 0"的真 bug，12 例新增）**；**撤销一次确认已完成（轮次七十九：`MaterialIntakeRepository.undoBatch(batchId)` —— 反悔也能退，撤的是"这一批自己写下的"知识点与线索边，"本来就有的"行 / 卡片（含模板）/ 标签 / 别的线索边任一存在就**整批不撤**并逐条说明理由；行已被手删不算拦路；退提案时 `applied_at` 与 `already_existed` 一起清，`record` 下一轮重算；入口在「看看确认了什么」对话框里，写者仍然只有确认那一层，10 例新增）**；**落不了的连接看得见已完成（轮次八十：待确认清单上每条还没落地的连接直接标出缺哪一端 —— `pendingMissingEndpointsOf` 现算、不落库，判据与确认时的成绩单逐条对齐（影子图 / 边已在库里不算 / "同名已存在"的点不算），勾选一变就重算，缺的那一端进图之后这句话自己消失；仓储层的 `missingEndpointNote` 是两处共用的同一句话，14 例读数 + 1 例页面）**；**照片读完能原地再来一张已完成（轮次八十一：报告对话框里多一个「换一张」（读成了）/「重试」（没读成）—— 不用先关掉对话框再出去找那个按钮；"模型都没配好"那一种不摆这个按钮，因为按了还是同一句话；照片这条路照旧一个字都不写库，2 例新增）**；**撤过就有痕迹（撤回记账）已完成（轮次八十二：schema v20 新表 `material_intake_undo_logs` —— 撤回**成与不成**都留一笔（没撤成记 `blockedCount` + 第一条理由，`undone = false`），记成流水而不是状态列（同一批可以撤很多次）；写者只有 `undoBatch` 自己（删行与记账同一事务），页面只读数出"这一批撤回过 N 次"；5 例仓储 + 1 例页面新增）**；**撤回流水点得开已完成（轮次八十三：把"这一批撤回过 N 次"那一行变成入口 —— 只读对话框按倒序列出每一次撤回（`MM-dd HH:mm` + 撤成了 / 没撤成），撤成那次摆出**原件原话**（删掉的知识点标题、线索边的"从 → 到"），没撤成那次摆出第一条理由与"当时 N 条理由"；只读、不回放（关掉仍是待确认），不新增任何落库，1 例新增）**；**机制面板（"参数公开"那一半）已完成（轮次八十四：`app/lib/domain/services/cognitive/mechanism_catalog.dart` 把两处引擎装配的 id 清单与唯一覆盖（`attention.ignition.T_ign = 0`）收成一份常量、`library_diagnosis.dart` 与 `problem_evaluator.dart` 两处调用点都读它（面板因此不可能和引擎漂移），`app/lib/features/cognitive/application/mechanism_reader.dart` 把转录表读成面板行（`transcribed` 用空 defaults 单独读一遍），设置页 → 认知模型页 AppBar「机制与参数」进只读页：六个机制各有多少参数、哪些**未标定**、哪个被覆盖（值 `0`、转录默认值 `0.05`）、`rhythm.gate` 如实说"只在节律读数里，不装进引擎"、`memory.dsr` 如实说"这一层没有号参数"、末尾给总数；10 例读数 + 7 例页面新增）**；**演练已完成（轮次八十五：`app/lib/features/cognitive/application/run_rehearsal.dart` 把"谁去装配引擎"这个问题答了 —— 请求提到的节点按 `knowledge_points.external_id` 摆进仿真图、`ms` 用代表卡片的 `modelReadingOf(row).r0`（读不出来就省略并如实列进 `nodesWithoutMs`，不编数）、两端都进图的 `knowledge_edges` 才接过来、请求自己的 `time.model_hours` 就是锚点、只装 `memory.dsr`（不跑轮次，逐轮那四个机制用不上）、**只跑不落库**；既有只读工具 `check_transcribe_run` 多一个 `execute` 参数（缺省 false），给了就在校验通过之后真的跑一遍，结果多一个 `rehearsal` 对象，`ok`/`error` 跟执行报告走 —— 执行层从轮次七十八起第一次有了调用者；机制面板因此如实多列第三处装配；12 例演练 + 4 例工具 + 页面例数不变）**；**照片报告里能直接试跑已完成（轮次八十七：读完一张照片、自检合法之后，报告里多一个「试跑一遍（不落库）」——`PhotoTranscribeReport` 自己带着解码出来的 `request`（界面不把模型原话再解一遍），按一下走 `rehearseRun`（只读、不落库），把引擎对每条动作的原话、读不出 `r0` 的节点、库里没有的 id 分三处摆出来；不合法的那一份不摆这个入口，试跑失败只说人话、不带走报告；3 例新增）**；**`run/1` 也能贴进来已完成（轮次八十八：材料摄取页第二条只读入口 —— 把一份 `mindnet.run/1` 贴进对话框，按「校验这份请求」走与照片那条路同一个 `reviewTranscribedRun`（id 白名单照旧从库里现读），合法才摆「试跑一遍」，跑的是同一个 `rehearseRun`；读不成（`FormatException`）与不合法分开说，两者都不给试跑入口；一个字都不写库；3 例新增）** |
| 7 | **标定（CALIBRATION 六实验）+ 反馈微调（FEEDBACK）** | 个性化真正的来源，但要 1–6 的数据积累 | 6 个实验各自可跑、产出参数与置信说明；反馈更新律有界且可回滚 |
| 8 | **机制插件化（PLUGIN_ARCHITECTURE）** | 覆盖全面的长期结构 | 至少一个机制实现为可开关模块，用户侧有开关/滑块，验收契约可跑 —— **"参数公开"那一半已完成（轮次八十四：只读的机制面板 —— 六个机制各有多少参数、哪些未标定、哪个被覆盖、`rhythm.gate` 不装进引擎、`memory.dsr` 没有号参数；装配与参数的来源收成 `mechanism_catalog.dart` 一处，面板不会和引擎漂移）。"用户侧开关/滑块"这一半仍未做：开关要落库（settings 列 + schema 迁移）并配可跑的验收契约；**轮次八十五又多了第三处装配（演练那一跑：只装 `memory.dsr`），面板已如实列出**；**第一个开关已完成（轮次八十六：库诊断那一跑装不装目标机制，schema v21 `local_settings.goal_mechanism_enabled`（NULL = 装），翻开关真的落库、那一跑真的少装 `context.goal`、读数与 JSON 都如实写 `mechanism_ids`**；**第一个滑块也已完成（轮次八十九：`context.goal.beta_goal`，schema v22 `local_settings.goal_beta`（可空 REAL，NULL = 用转录默认值 0.3），两端与出厂位置取自内核参数表 `[0, 3]`，用户调的值经 `moduleDefaults` 真的进装配、库诊断读数 `module_defaults` 如实带出，面板分开标"你调的"与"被覆盖"并给"回到出厂值"）**；**轮次九十把这个数接进"装了目标机制的每一跑"：题目定价那一跑（`evaluate_problem_fit` / `plan_today` 共用那一处装配）也读同一份设置，读数 `module_defaults` 如实带出来 —— 用户拖的值不再只在库诊断那一跑生效** —— 别的机制的开关语义、其余参数的滑块仍未做**）** |

> 纪律（沿用已定 D1–D6）：FSRS 仍是到期日唯一权威；一张表的一列只有一个写者；
> 未标定参数一律显式标注，不进默认值叙事；对拍与守卫（43 条 tierA + B01 tierB）不得放松。

## 4. 已落地（记录事实，便于下次接着做）

### 切片 2 的一半：`wrong + reviewed_solution` / `closeness`（已完成）

- 事件层：`DsrCardState.eventFor(rating, reread, reviewedSolution, closeness)`——`rating <= 1 && reviewedSolution`
  ⇒ `DsrEventType.retrievalFailureFeedback`（否则维持 `lapse`，**默认路径逐位不变**，43 条 tierA 与 B01 不受影响）；
  `applyReview(...)` 与 `CognitiveModel.modelStateAfterReview(...)` 透传同样两个参数。
- 两个锚点常量：`DsrCardState.closenessDefault = 0.5`（IO_PROTOCOL §2.3 默认）、
  `DsrCardState.closenessNearMiss = 0.6`（MODEL_v2_MATH §3 弱线索带 `closeness >= 0.6`）。
  UI 只提供这两个已定义锚点（「差点想起来」/「还是不会」），**不发明中间刻度**。
- 存储：schema v9，`review_logs.reviewed_solution`（bool，可空）与 `review_logs.closeness`（real，可空）。
  NULL = 没问/不适用，**不写 false**（写 false 等于替历史数据编造"对过答案"）；
  `addReviewLog(reviewedSolution:, closeness:)`，`_upgradeV8ToV9` + `_ensureColumns` + `_tableFor('review_logs')` 三处齐备。
- UI：判错后**不立即写库**（两个答案是两个模型事件，事后补写等于对一次复习应用两次模型列），
  先问「差点想起来/还是不会」，未答时"下一张"禁用。
- 机制要点（实测，见 `test/domain/services/srs/dsr_card_state_test.dart`）：`retrieval_failure_feedback` 的
  S 走 `stabilityIncrease`（ratio = closeness）故**上升**，`lapse` 走 `LAPSE` 分支故**崩落**
  （同一 ripe 行 stability 20.31 vs 0.49）；而本应用自有的两列里，Σ 的 `effort = (1-R) + (1-closeness)`
  使 closeness 越大 Σ 增量越小（0.85 → 0.84，lapse 0.85），R0 两条路径都不动
  （只有 `retrieval_success` 抬 R0）。**断言必须建在"足够熟"的行上**：新卡 R≈0 时 `effort` 被钳到 1.0，两条路径的 Σ 完全相同。
- 切片 2 的另一半（`exposure`，读了没测）见下一节：**已完成（轮次四十四）**。

### 切片 2 的另一半：`exposure`（读了没测，已完成 轮次四十四）

- **语义来源**：`IO_PROTOCOL.md` §2.2 的五类动作（`time`/`review`/`exposure`/`knowledge`/`goal`）里，
  `exposure` 是本应用此前唯一无法产生的一类；MindNet 把它翻译成 `kernel.review(node, {type:'reread'})`
  （`src/io/run.js:278`），`mechanisms/memory.dsr.js` 里 reread 默认 `grade = 3`、S 增益乘
  `kappa_reread_ratio`（0.1），且**只有 `retrieval_success` 抬 `R0`**。这两条向量
  （`A06-applyReview-reread-t5/-t30`）本来就在 tierA 对拍里，所以这一片不新增数学。
- **模型路径**：`ReviewService.recordExposure()` → `CognitiveModel.modelStateAfterReview(row,
  rating: 3, nowHours, reread: true)`（接口早就有 `reread` 参数，不需要改接口）→ 只写
  `card_states.encoding_strength/savings` 两列，**不调 `updateUnitCardState`**（到期日/streak 不动）、
  **不写 `review_logs`**。
- **存储**：schema v13 → v14，新表 `exposure_logs`（`id`/`card_state_id`/`source`/`exposed_at`/`created_at`）。
  为什么不复用 `review_logs`：那张表是*测试*记录，留存率桶与 M6 标定曲线都从它算，曝光没有评分也没有
  对错，塞进去要么给 `rating` 编值（NOT NULL），要么让"看了没测"被算成一次成功回忆。详见
  `docs/DATA_MODEL.md` §12。
- **UI**：`review_page.dart` 的 `_BottomBar` 在"答案已揭示、还没写库"（`_Feedback.awaitingSelfJudge`）
  那一档多一个 `Icons.chrome_reader_mode` 按钮（`l10n.ankiExposureTooltip`），按下 → 记一条曝光 →
  SnackBar 明说"这次不算复习，到期日不变" → 前移。到期日不变 ⇒ 本次会话不再出现，下次进复习页仍会出现。
- **测试**（4 条，验收口径"读一次资料后 R/S 轨迹与只做错不同"）：
  `dsr_card_state_test.dart` 的 `exposure: reading is not retrieval`（同一行上 reread 的 S 增益 < 成功、
  > 0（不是零收益）、lapse 砍 S；`R0` 只有成功才抬）、`review_service_test.dart` 的
  `exposure（读了但没测）`（`review_logs` 为空、FSRS 七列不变、模型两列写入且 R0 未抬）、
  `review_page_test.dart`（按钮只在揭示答案后出现；按下后写曝光、不动到期日）、
  `v14_migration_test.dart`（真实 v13 文件升级 + 老数据一行不少 + 自愈路径）。

### 切片 4 的一半：节律层 α(τ)——`rhythm.gate` 装进 fast_engine（已完成 轮次四十五）

**缺口**：`fast_engine.dart` 移植自 MindNet 快层时，D3 明确不移植 `rhythm.gate`，
于是 `payload.availability` 恒为 1、`cycleTicks` 恒为 1——§4.1 那条
`a₁ = a* + (a − a*)·e^(−k·α)` 里 α 的通道等于**常开**，时间维度整个没进模型。

**做了什么**：

- 新文件 `app/lib/domain/services/cognitive/rhythm_gate.dart`（纯 Dart，无 RNG）：
  占空比门 `G_duty`（`duty`，默认 0.5、`T0` 1 s）、警觉衰减 `G_vig = exp(-t_on/τ_vig)`
  （τ_vig 默认 20 分钟、半衰 ≈ 13.9 分钟）、负荷自适应周期 `T_cycle = T0·(1 + λ_L·load/4)`
  （λ_L 默认 1，参考负荷 4 = DAR 容量）。`beginRound(load:)` 对应 `round.before`，
  `blockReasonFor(tick:)` 对应 `tick.gate`（`off_phase` / `vigilance_low`）。
- `fast_engine.dart`：新机制常量 `FastMechanisms.rhythm = 'rhythm.gate'`（**opt-in，默认不装**）、
  七个 `calibrated: false` 参数、`step()` 的 round.before 按「激活 ≥ 自身阈值的节点之和」算负荷并定周期、
  tick 循环逐个过门、`clone()` 复制节律时钟（反事实运行不该把警觉清零）。

**为什么默认关**：对拍向量是在**没有**这个门的情况下生成的，默认装上就会改写所有 tierB 读数。
它必须是"可装的机制"而不是"新的默认值"——这同时兑现了 §3 第 8 行「至少一个机制可开关」。
不装时 `availability` 与 `cycleTicks` 与既有 43 条 tierA + B01 tierB 向量逐位一致。

**两条拒收**（写进构造函数的 `UnsupportedError`，不是静默降级）：

- `markov` 模式需要 `ctx.rng()`（mulberry32）做两态转移：PRNG 未移植，与本 port 在
  `T_ign > 0` 时抛错是同一条纪律。
- `theta` 模式只写在 `docs/MODEL_v2_MATH.md` §5.1 与 manifest 里，参考实现的
  `openCountFor()` 实际只算 duty 与 markov（`mode === 'markov' ? cycle : round(duty·vig·cycle)`）；
  按 duty 静默处理就是"同名不同模型"。

另外 `α0` 与 `G_flow` 带在参考 hook 里**没有落地**，所以这里也不发明它们——文档里写清"参考实现没接"，
而不是补一个没人接的因子。

**证据**：`app/test/domain/services/cognitive/rhythm_gate_test.dart`（15 例：manifest 四条自检逐条移植 +
引擎侧六条——不装时 `availability` 恰好 1、装上后 `availability = 3/5` 且 B 的激活不同、`duty=1` 消融逐位回到
不装、`duty=0` 走到原本不可达的「完全不在」分支、τ_vig 调小后同轮 `availability` 下降、克隆保住时钟）；
`flutter test test/domain/services/cognitive --concurrency=1` → `+211 All tests passed!`。

**这一片还剩的另一半**（见 §2-D）：线程页显示"当前注意力可用性"与做难/做易/休息建议（带开关）
——**已完成，见下一节**；以及 `thread_rank_service.dart` 的"认知排序"档位（输入 = 目标节点 + 刚活动节点 + α(τ)，
未标定权重显式标注）——仍未做。

### 切片 4 的另一半：α(τ) 读数与建议上屏（已完成 轮次四十七）

**缺口**：`rhythm.gate` 装进引擎之后，`availability` 只对测试和对拍向量可见——
没有一个界面把它读出来，用户看不到"现在还剩多少注意力"，也拿不到"做难/做易/休息"的建议。

**做了什么**：

- 领域层 `app/lib/domain/services/cognitive/study_rhythm.dart`：把 `rhythm.gate` 的参数接到
  "这次坐多久"上（`G_vig`、负荷自适应周期、duty 开窗全部复用 `RhythmGate` 本身，不新造数学）。
  `t_on` 由**既有学习日志**推导（`review_logs` + `exposure_logs` 的动作时间，间隔 > 15 分钟算新一段）——
  `kStudySessionGap = 15 分钟`被写成命名常量 + 注释，明说这是**未标定代理**（本应用没有会话计时器）。
  没有坐段时返回 `null`，**不假装 α = 1**。
- reader `app/lib/features/thread/application/study_rhythm_reader.dart`：取两侧日志尾部各 500 条；
  开关关掉时**不查库**直接返回 hidden。`load` 留 0，因为这一屏没有跑认知引擎——编一个负荷
  就是把猜测装成测量。
- UI：`thread_status_bar.dart` 的状态条由单行改为两行（折叠时仍一行），`_AttentionHint` 显示
  可用性百分比 + 已专注分钟 + 建议 + "参数未标定"tooltip + 隐藏按钮；`thread_page.dart` 的 AppBar
  加 `_RhythmToggle` 菜单项（关掉之后还能把提示请回来）。
- schema v15：`local_settings.rhythm_hints_enabled`（nullable = 用户从没选过 → 出厂默认显示；
  迁移不替用户写值）。

**证据**：`study_rhythm_test.dart`（17 例）、`study_rhythm_reader_test.dart`（6 例）、
`test/data/database/v15_migration_test.dart`（2 例）、`thread_status_bar_test.dart`（4 例：
有坐段就报数、没有坐段说"还没有足够记录"、点隐藏把开关落库且读数立刻消失、折叠后读数让位）。

### 切片 4 的追加：认知排序档位（已完成 轮次五十–五十五）

**缺口**：§2-D 的落点要求 Thread 排序用上"目标节点 + 刚活动节点 + α(τ)"。段落 A
（`ThreadRanker` 的硬约束加权）与段落 B（`DomainBalanceRanker` 的领域均衡 + 有效性）都在跑，
但两者都不看 α(τ)，也不看"刚复习/刚做错/刚读过"的节点和当前目标。

**做了什么**：`app/lib/domain/services/scheduling/cognitive_rank.dart`（纯逻辑，不碰数据库）。
输入 = `availability`（α(τ)，来自 `StudyRhythm` 的读数）+ 调用方算好的
`知识点 id → (跳数 0/1/2, 来源 activity/goal)` + 每个候选的难度代理（0..1，可缺）；
输出 = 重排后的次序 + 每个 hit 一条中文理由 + `uncalibrated: true`。
`score = reachability × availabilityFactor`：距离 0/1/2 分别 ×1.6 / ×1.3 / ×1.1（超过 2 跳 = 1.0），
精力分量在 `1 ± 0.25` 内摆动（注意力高给难的加分、低给容易的加分）。
平手按 `baseIndex` → 输入序 → `taskId`（`List.sort` 不保证稳定，所以显式写完）。

**三条刻意的选择**（都写在文件 doc 里）：

- 加成常数**不是** D12 的 `1.8 / 1.3`：那一组是"答错之后给关联卡片加抽卡权重"
  （§6.5 / D5），与"目标可达性"不是一回事，混用会让人以为这里有测量；两组常量名字刻意不同。
- 难度读数为 null 时候选**不消失**、精力分量取中性 1.0，理由行如实写"缺难度读数"；
  距离与难度**都缺**时理由行直说"没有认知读数，按默认次序"。
- 什么都不知道时 `score` 全为 1.0 ⇒ 次序 == `baseIndex` 次序：接线之后忘了喂输入，
  用户看到的仍是原来的列表，而不是一个悄悄乱掉的列表。这条由测试钉住。

**证据**：`app/test/domain/services/scheduling/cognitive_rank_test.dart`（21 例：没输入等于没开 /
距离加成 / 精力分量 / 越界与 NaN / 理由行与名字回退 / `toJson` 的 `uncalibrated`）。

**还剩的另一半**：把输入接起来——`ThreadRankService.build()` 接受 `CognitiveRankInputs`、
`ThreadFeed` 暴露认知次序与理由、开关落库（`ThreadRankSettings` 加列，需要一次 schema 迁移）、
"刚活动节点"与目标节点到知识点上的距离（标签树 / `CognitiveGraph`）、以及 UI 上的呈现。

**进展（轮次五十一）**：距离那一层已经做完 ——
`app/lib/domain/services/scheduling/cognitive_rank_inputs.dart` 给出
`CognitiveRankSeed`（α + 标签树投影 + `goal_node_id` + 刚活动的知识点 + 知识点→标签 + 名字）
与纯逻辑 `CognitiveRankWiring.build(seed, candidates) → CognitiveRankInputs`，
15 例测试用手搭的标签树钉住：0/1/2 跳、超过 2 跳或不连通一律不写 origin、
同跳数"刚活动"优先于"目标"、候选挂多个标签取最近、顺序无关。
还剩：`ThreadRankService.build()` 接受 seed、`ThreadFeed` 暴露次序与理由、
开关落库 + UI。

**进展（轮次五十二）**：从数据库读素材那一层也做完 ——
`app/lib/features/thread/application/cognitive_rank_reader.dart` 把 `ThreadState.goalNodeId`、
`Tags.parentId` 投影成的树、`review_logs` / `exposure_logs`（12 小时窗口、每侧最近 40 条）
经 `card_states.knowledge_point_id` 落成"刚活动知识点"、知识点标签与名字、以及
`StudyRhythmReader` 的 α，读成 `CognitiveRankSeed`；9 例测试钉住，其中包括
"卡状态没有知识点就不说话"（v1 的 `getOrCreateCardState` 不写知识点，那种日志在认知排序
眼里没有节点）。还剩：`ThreadRankService.build()` 接受 seed、`ThreadFeed` 暴露次序与理由、
开关（下一段）+ UI。

**进展（轮次五十三）**：开关也落库了 —— schema v16 给 `thread_rank_settings` 加一列
`cognitive_rank_enabled`（非空、**默认关**：权重分是用户自己定的，而认知排序的加成全部未标定，
不该默认替掉用户看惯的列表），`ThreadRankRepository.getCognitiveRankEnabled()` /
`setCognitiveRankEnabled()` 读写它；`app/test/data/database/v16_migration_test.dart` 2 例钉住
"真实 v15 文件升级后老权重不丢、新开关落成默认关"与"版本号跑在列前面靠 `beforeOpen` 自愈"。
还剩：`ThreadRankService.build()` 接受 seed、`ThreadFeed` 暴露次序与理由 + UI 开关。

**进展（轮次五十四）**：服务接线也做完了 —— `ThreadRankService.build()` 多两个参数
（`CognitiveRankSeed cognitiveSeed`、`bool cognitiveRankEnabled`），候选就是段落 B 的次序
（`baseIndex` = 它在段落 B 里的位置），所以这一档**只重排、不重算可行域**，与段落 B 对
段落 A 的关系一致；`ThreadFeed` 新增 `cognitiveRank` 与 `cognitiveFor()` /
`cognitiveReasonFor()`，`readyTasks` 在开关打开时先走认知次序、再拼段落 B、最后段落 A 兜底
（**永远不会丢任务**）。`ThreadFeedNotifier.sort()` 读库里的开关：开关读失败 = 保持关，
素材读失败 = 退化成"没有读数"，两者都不让整个排序失败。

难度代理这一处定了口径：**任务挂着的知识点里最弱的那块编码上限**（
`1 − min(priorR0)`），且只看 `priorConfidence > 0` 的读数 —— 置信度 0 表示"只是先验、
不参与加权"，一条没有信念的先验不该决定"这题难不难"。

**证据**：`app/test/features/thread/thread_rank_service_cognitive_test.dart`（5 例：开关关着
完全不产出 / 开着但没有起点则一个都不动且理由行说"没有认知读数" / 刚复习过的知识点 0 跳
×1.6 把任务提到最前并标 `movedUp` / 离目标 1 跳 ×1.3 且图外知识点什么都不给 /
难度取最弱编码上限并且 α=0 时把弱编码的任务换下去）+ `thread_feed_notifier_test.dart`
（2 例：开关关着没有这一档、库里打开之后排序结果真的带上它）。

**进展（轮次五十五）**：UI 也接完了 —— 线程页 AppBar 的那个 ⋮ 从"只有一个开关"变成
`_ThreadMenu`（两项：注意力可用性读数、认知排序），翻开关会调
`ThreadRankRepository.setCognitiveRankEnabled()` 落库、invalidate 开关 provider 并**当场重排
一次**（不等下一次数据变化）；开关打开时列表上方多一行说明："认知排序已打开：离当前目标或
刚复习过的知识点近的任务排前面；加成未标定，只是次序提示"——次序换了就得说清它是提示不是测量
（本切片的加成常数仍全部 `[未标定]`）。新增两个 ARB 键 `threadCognitiveRankToggle` /
`threadCognitiveRankNote`（zh + en，`flutter gen-l10n` 重生成）。

**证据**：`app/test/features/thread/presentation/thread_page_cognitive_test.dart`（1 例：
默认关且没有说明行 → 菜单里两项都在 → 点开开关，库里写 true、说明行出现 → 再点一次，
库里写回 false、说明行消失）。

**还剩的另一半**：加成常数的标定（外部，见 §4 末的标定实验）——在那之前这一档默认关，
打开也只是"提示"，不是"测量"。

### 切片 1 的一半：`LibraryDiagnosisRunner`（把 tierB 真正跑起来，已完成）

此前只有 AI 工具 `evaluate_problem_fit` 会跑快层，读数页自己声明"不跑 tierB ⇒ zone 恒为 unavailable"。
现在读数页与工具共用同一条装配路径：

- `lib/domain/services/cognitive/library_diagnosis.dart`：
  - `representativeCardRow(List<CardState>)`——同一知识点多张单元卡时选代表行（`repetitions` 降序、同则 `id` 升序）。
    这一条规则**只定义一次**，读数页与 `cognitive_tools.dart` 的 `_representativeRow` 都委托它，两边不可能再给出不同的代表行。
  - `LibraryDiagnosisRunner.run({tags, rowsByKnowledgePoint, model, nowHours, startKnowledgePointIds, targetKnowledgePointIds, moduleDefaults, rounds = 4})`：
    与 `ProblemEvaluator._diagnose` 同一配方（`FastGraph.fromSpec` + `attention.ignition.T_ign = 0` 覆盖 + `startDiffusion` + `runRounds(4)` + `FastDiagnosis.bottlenecks`）。
    ms 取 `model.modelReadingOf(row, nowHours).r0`，且要求 `isFinite && > 0 && <= 1`，否则该节点进 `nodesWithoutMs`（**不套用 MindNet 的 0.8 默认**）。
  - 三条产品规则写在文件头：`starts` = 最近复习的知识点、`targets` = 今天到期的集合（Furnace 没有 goal 实体）、`rounds = 4` **未标定**。
  - `danger` 由元认知层算出（轮次二十一之前它恒为空，因为信念 b_v 本应用不存）；`LibraryDiagnosis.toJson()` 走 `mindnet.library/1` 握手，便于日后对拍。
- `lib/features/cognitive/presentation/cognitive_model_page.dart`：
  - 新增 `cognitiveLibraryDiagnosisProvider`（tierB 跑一次；`starts` 取最近复习的 `cognitiveStartNodeLimit = 5` 个，`targets` 取 `forced == 1 || dueAt <= now`），
    与 `cognitiveObservationInputsProvider` 一起喂给 `assembleCognitiveReadings`。
  - `diagnosisByKnowledgePoint` 传的是 **`null`（没跑）或非空 map（跑了）**，两者不可合并：`null` ⇒ `unavailable`，空 map ⇒ `healthy`。
  - `CognitiveReadings.fastLayerRan` 随读数带出，页面多两条说明：这次跑没跑（含起点/目标口径）、以及危险从哪来（见下一条）。
  - `unavailable` 不再等于"本页不跑"，而是"这次没做诊断"。
- 仍未做：复习队列（`ReviewAdvisory.order` 的实时调用方）**不传诊断**，队列里的 zone 依旧恒为 `unavailable`。
  为什么刻意不接：zone map **不参与排序**（排序由 band 与 `expectedGain` 决定，见 `ReviewAdvisory.order`），
  把它传进 `buildQueue` 没有任何可观察效果，只会多一次 tierB 与多一处"传了但没人读"的假接线。
- 已完成（轮次二十）：正在做题的人**看得见**这条诊断——`review_page.dart` 读同一份 `cognitiveReadingsProvider`，
  取 `zoneByKnowledgePoint[当前知识点]`，只在有真卡点时显示一枚 chip（`reviewZoneChip`；`healthy`/`unavailable` 都不显示）。
  词汇因此抽到 `lib/features/cognitive/presentation/zone_labels.dart`（`bandLabel`/`zoneLabel` 单一定义，读数页 `export`，复习页导入）。
- 测试：`test/domain/services/cognitive/library_diagnosis_test.dart`（10 条：没有图不跑、只有图没有起点/目标不跑、孤立节点 = `empty/no_entry`、缺卡行 = `nodesWithoutMs`、非法 R0 当成没提供、belief 跳过起点只判其余、没有卡行的知识点不进元认知、danger 来自远时钟下的元认知、JSON 握手）+ 读数页新增"诊断让 zone 变真 / 空 map 是 healthy"与"两条说明"用例 + 复习页 2 条（有卡点 ⇒ chip、无卡点/未诊断 ⇒ 无 chip）。

### 切片 3：元认知层（危险区 / 焦虑区 / 校准度，已完成 轮次二十一）

MindNet 第三层（`mechanisms/metacognition.belief.js`）说明"危险"缺的是哪个量：信念
`b_v = sigmoid(b0 + w_fluency·fluency + w_encoding·Σ + w_recency·recency(Δt))`，与卡片真实可回忆的 `R` 相减。
差 > `delta` 判危险（以为会其实不会），差 < −`delta` 判焦虑（会但不敢用），`mean |差|` 是校准度 κ。
本应用现在自己算这个量，不再说"不存所以不出现"。

- `lib/domain/services/cognitive/metacognition.dart`：纯逻辑（无 IO、无时钟），只有 `MetacognitionParams`
  （`wFluency 1.5` / `wEncoding 0.8` / `wRecency 0.8` / `tauRecencyHours 6` / `b0 1.5` / `delta 0.2`，**未标定**，与 JS 默认值一致）、
  `MetacognitionObservation` / `MetacognitionRow` / `MetacognitionReading` 与 `Metacognition.read({observations, params})`。
  起点（`isStart`）不进结果——JS 同样跳过："刚复习过"不能用来证明自己知道。
- **recency 用混合时钟**：`state == conscious` 记 0 小时（这次在图上被点亮就是新鲜），否则取距上次复习的小时数，没复习过取 +∞。
  第一版直接取"距上次复习"，结果 recency 与 `R` 一起衰减、差被抵掉（同一夹具在 nowHours=10000 时差 −0.2668 ⇒ 误判焦虑）；
  换混合时钟后同一夹具 `belief 0.6397` vs `R 0.5062`（差 +0.1335），把时钟推到 100000 就越过 0.2（`danger=[a,b]`）。
  依据：`DsrMemory.retrievability` 衰减极慢（Δt 从 725h 到 9725h，`r` 只从 0.7106 降到 0.5062），
  所以"久没复习"必须由 recency 这一侧表达，而不是等 `R` 自己掉下来。
- `library_diagnosis.dart`：`LibraryDiagnosis` 增 `metacognition` 字段并进 `toJson()`；元认知的危险行同时喂给
  `FastDiagnosis.bottlenecks(dangerRows:)`（同一节点只报一次）。每节点的 `R` 取代表卡的 `modelReadingOf(row).r`；
  `r0`/Σ 缺失就不参与，不发明默认值。
- 页面 `cognitive_model_page.dart`：摘要下新增"模型怎么看你"卡片——校准度（三位小数，未标定）、危险名单、低估名单；
  跑过但一个节点都判不了时明说"这次没有一个知识点能被判断"，有行但没越过 `0.2` 时明说阈值。
  只在 `fastLayerRan` 时渲染：危险/低估是**关于这一次运行**的陈述，没跑就没有可比的，空列表会被读成"没问题"。
  `cognitiveNoDangerNote` 因此改写为 `cognitiveDangerNote`（原文"本应用不存这些数据"已不成立）。
- 仍未做：权重标定——κ 现在只是"两边差多少"，还不是"模型准不准"的可比数字。

### 切片 3 的追加：`evaluate_problem_fit` 危险区排前（写了、量了、撤回，轮次二十二）

结论先说：**这条路走不通，撤回后没有再实现**。危险区是"一次运行"的读数，不是一道题的属性，
把它做成按题排序的规则会得到一个由标签顺序决定的排序，而不是由"学生忘了什么"决定的排序。

- 机制（`fast_engine.dart:1580-1592` 的注释就是原因）：`context.goal` 的 drive **故意排除目标节点**
  （"给目标本身加偏置会让它在第一轮就亮起来"），而 `evaluate_problem_fit` 里每道题的扩散目标正是这道题自己的知识点
  ⇒ 目标永不 `CONSCIOUS` ⇒ 只看自己的知识点时 `danger` 必然为空。探针：`targets=[p1]` 时 `p1=SUBCONSCIOUS@0.269`，
  兄弟 `a,b,c=CONSCIOUS@0.316`。
- 放宽过滤更糟：六组夹具显示亮起的集合由**标签插入顺序 + 容量**决定，与卡片是否变旧无关
  （只弄旧 `a,b` 与只弄旧 `p2,p3`，亮起来的是同一批 `a,b,c`；目标排首位时一个都不亮）。
- 落地状态：`problem_evaluator.dart` 文件头留了这条边界说明；`cognitive_tools.dart` 不报 `danger_*` 字段；
  `library_diagnosis.dart` 的读数函数退回私有。危险区继续只出现在读数页/复习说明与
  `FastDiagnosis.bottlenecks(dangerRows:)`。详见 `docs/PROGRESS.md` 轮次二十二。
- 若日后要做"先做最危险的题"，需要的不是同一张图的扩散结果，而是**与问题无关的**判定：
  例如"这张卡的 `R` 低于阈值而自评/编码强度高"——那要先有 `fluency` 的真实来源（自评或作答历史），
  现在没有，所以不做。

**进展（轮次五十六）**：同一个工具的另一半做完了 —— `evaluate_problem_fit` 现在把控制层的反事实价格
`V(π)=ΔR/cost` 用在**同分档的次序与解释**上（`ProblemEvaluator.compareByRank`：`rankKey` 降序 →
`V(π)` 降序（`null` 最末）→ `problemId` 升序；理由行追加"反事实：<指令>（<度量> 增益 X / 成本 Y → V=Z；<为什么>）"；
工具输出多一个 `counterfactual{metric,instruction,value,why}`，**不可模拟时整键缺席**，不是 0）。
为什么**不**把它并进 `rankKey`：`V(π)` 的增益来自未标定的机制常数、成本 1.0/2.0/0.2 也是拍的，
混进主键等于把"提示"当"测量"；`FastPlanner` 的 `retention` 指令在没有 `RetentionProbe` 时明确是
"未模拟"（`simulated: false`），所以"没有价格"是合法状态。诊断与价格取自**同一个引擎**（`_FastRun`），
不可能描述两次不同的运行。证据：`problem_evaluator_test.dart` 13 例（含 3 例价格：有价格 / 关掉快层全空 /
纯 tie-break 不越 `rankKey`）、`cognitive_tools_test.dart` 13 例（含"没得连就没有价格键"与
"两个节点时给出 `reachability` 价格"）。`retention` 侧与"把题目和闪存卡合成一份按 `V(π)` 排的日计划"仍未做。

**进展（轮次五十七）**：`retention` 侧的记忆层装上了 —— `FastMechanisms.memory`（`memory.dsr`）
可以按需装进 `FastEngine`，装后 `FastEngine.review()` 真的会走 DSR（`srs/dsr_memory.dart` 那套移植），
状态存在 `node.m['memory_dsr']` 这个 bag 里（`FastEngine.memoryBagKey`），并同步 `node.ms` /
`node.lastReviewTime`（对应参考实现的 `synced()`）；生产探针 `dsrRetentionProbe()` 读的就是这个 bag
（`app/lib/domain/services/cognitive/dsr_retention_probe.dart`）。为什么默认**不装**：conformance
向量是没装的时候生成的，而参考实现的 `memory.dsr` 也不注册任何 `round.*` 钩子（它是 lazy 的
`ensureState`/`synced()`）——所以"装"这件事对轮次数值是零改动，只对"能不能给一次复习定价"有影响。
为什么参数来自 `DsrParams` 而不是 `FastParamSpec` 表：那张表只吃数值路径，而记忆层还有一个非数值参数
（`decay_model`）；把它镜像进参数表是标定那一片的事。诚实边界：bag 目前是从 `node.ms` 懒建的
（`R0 = min(1, ms)`，`S = legacy_k * R0`，`D` 取默认），也就是**先验价格**而不是这张卡自己的价格；
调用方知道真实卡状态时先 `seedDsrState()` 塞进去，探针就会读它。证据：
`app/test/domain/services/cognitive/dsr_memory_layer_test.dart` 7 例（不装就不记录任何东西 /
装上后 `N`、`R0`、`S`、`Sigma` 与 `synced()` 都对 / 二次成功 `S` 再涨而 lapse 掉 `S` 保 `Sigma` /
克隆各改各的 bag / 探针在同一 bag 上给出 `before < after` / 图外节点是 `null` 而不是 0 /
塞了真实状态就压过 `ms`）。`ProblemEvaluator` 还没把探针传进 `FastPlanner.plan`（Q31b），
"今天做这几件事"的清单仍未做。

**进展（轮次五十八）**：探针接上了 —— `ProblemEvaluator._runFastLayer` 现在把 `memory.dsr` 一起装进
快层（`FastMechanisms.memory`）并把 `dsrRetentionProbe(params: engine.memoryParams)` 交给
`FastPlanner.plan`，所以 `strengthen_impression` / `interval_retrieval` / `lower_threshold` 这三条
留存指令从"未模拟"变成"有价格"（"到明天能买回多少留存"）。常数来自引擎自己那份 `DsrParams`，
不在评估器里重写一份。为什么这不是把两把尺子当一把：`V` 对两种度量都是"增益/成本"，但问的问题不同，
所以价格与 `metric` 一起上报（`counterfactualMetric`），而且它**只当同分档的次序与解释**，
永不并进 `rankKey`。实测一个诚实边界：当 `ms = 1.0`（上限）时 `R0 = 1.0`、`S = legacy_k × R0 = 24`，
`u = hours + 24` 处 `t/S = 1` ⇒ `psi = 0.9` 精确，复习后的稳定性增益是 1.0（`R0` 已封顶）⇒
`gain = 0.0` **精确**。零增益**不是价格**（它永远不会改变任何次序，而写个 `0.0` 出去像在测量
"这道题一文不值"），所以 `_bestPlanEntry` 只收 `value > 0` 的条目：上限节点与"没装记忆层"一样
都不报价格。两种"没有价格"在 planner 的 `simulated` 上分得很清楚（那才是"这个问题问过没有"的标记）。
证据：`problem_evaluator_test.dart` 15 例（新增"有入边但没动量 ⇒ `retention` 价格 > 0"与
"在上限 ⇒ 完全不报价格"，前者刻意用 `encodingStrength: 0.5`，因为 1.0 时增益恰好是 0）；`dsr_memory_layer_test.dart` 9 例（新增"给探针就模拟，报价 `cost`
是 `costRetrieval`"与"不给探针就 `simulated: false`，永不是 0 增益"）。"今天做这几件事"的清单仍未做。

**进展（轮次五十九）**：日计划的**纯逻辑核心**——`app/lib/domain/services/scheduling/today_plan.dart`
（`TodayPlanner.build`），把两类输入合成一份清单：卡片侧用 `DsrCardState.read` + `DsrMemory` 算
"复习这张卡，到 24 小时后能多留下多少 R"（与题目侧探针同一个量、同一个窗口，价格 = ΔR / `costReview`）；
题目侧直接取 `ProblemEvaluation.counterfactual*`（价格已经是 V，收益 = V × 成本，成本用 planner 自己的
`costLink`/`costRetrieval`，不在这里重算引擎）。三条刻意选择：① 每项都带 `metric`，`retention` 与
`reachability` 问的不是同一个问题，`TodayPlan.mixesMetrics` 明说这份清单里两种都有；
② 没有正价格的项目（到达上限的卡、没有价格的题）**不写 0.0**，它们按 kind（复习先于练习）与到期日排在有价格之后，
理由仍是人话；③ `TodayPlan.uncalibrated` 恒 `true`、且排序只用"价格降序 → kind → 到期日 → id"这一条全序，
它只是把已有的两个价格摆在一起，没有引入任何新常数。证据：`today_plan_test.dart` 9 例（其中一条把 Q31
实测的"上限处 `gain = 0.0` 精确"写成断言，一条钉住"输入顺序不影响输出"）。**还没做**的是把它变成
`plan_today` 一类的 AI 工具与 UI 上的清单（Q32b）。

**进展（轮次六十）**：`plan_today` 工具（`app/lib/features/ai/tools/today_tools.dart`）把那份清单接到模型手上 ——
输入是到期卡（`AnkiRepository.getDueCardStates`）与可选的候选题，输出就是 `TodayPlan.toJson()`
（每条 `kind`/`title`/`metric`/`value`/`gain`/`cost`/人话 `why`），空的一天也明说"清单是空的"而不是返回空壳。
为了不出现"同一道题在两个工具里价格不同"，把 `EvaluateProblemFitTool` 里的装配（读标签树 + 每个知识点一条
代表卡 + kp→tag 桥）抽成共享的顶层 `evaluateProblems(...)`，两个工具走同一条评估路径；`node.why` 因此也
只写一处。三条刻意选择：① `readOnly: true` 但 `riskFor` 仍是 `write` —— 它不改数据，可它给的是"去做什么"；
② `max_actions` clamp 1–50、`horizon_hours` clamp 1–720，摘要结尾永远带"加成未标定：这份顺序是提示，不是测量"；
③ 空清单与"没有价格"分开说：前者是真的一天没事，后者仍列进清单只给理由（`TodayPlan.omitted` 报出被裁掉几件）。
证据：`today_tools_test.dart` 7 例（空白天、到期卡进清单且 priced in `retention`、未到期卡不进、候选题经评估被
`reachability` 定价、`max_actions` 报出"另有 N 件排在清单外"、`ToolRegistry.byName('plan_today')` 真的能取到）。
**还没做**的是 UI 上的清单页（Q32c）—— 已在轮次六十一补上，见下。

**进展（轮次六十一）**：界面上的清单页（`app/lib/features/cognitive/presentation/today_plan_page.dart`，读法在
`app/lib/features/cognitive/application/today_plan_reader.dart`）—— 从复习页 AppBar 的「今日清单」进入，把
`TodayPlan` 逐条摆出来：每条一个 `kind` 标签 + 标题 + `metric`/`V`/成本 + planner 给的人话 `why`。读法只有一处：
`readTodayPlan` 拿 `getDueCardStates(moment)` 与知识点名交给 `TodayPlanner.build`，`nowHours` 与到期判断共用同一个
`moment`（否则同一张卡会在"到期"与"现在几点"之间被算到两个时刻）；候选题暂时传一份空报告
（`kNoProblemCandidates`）—— 这一页只列复习侧，而"没有题"与"题没有价格"是两件事，末尾一行明说价格要模型给。
三条刻意选择：① 没有价格的行**不画价格行**（`TodayPlanner` 已经说零增益不是价格，页面不在这里补一个 `0.0`）；
② 页面不重排、不重算：顺序就是 `plan.actions` 的顺序，两种度量各自带名字（`留存`/`可达性`）；
③ `omitted > 0` 时才提上限，并且每页都带一行"加成未标定"。
证据：`app/test/features/cognitive/presentation/today_plan_page_test.dart` 7 例（真库：到期卡进清单且 priced in
`retention`、未到期的卡不进、空的一天明说空、刷新重读；假清单：无价格不画价格行、两种度量分名、被裁件数如实报），
全量回归 `flutter test --concurrency=1` → `+1678 ~2: All tests passed!`（轮次六十后是 `+1671 ~2`，差 7 = 这一页的 7 例）。

### 切片 6 的一半：材料摄取 INGEST 第 ③ 步（Dart 端口，已完成 轮次六十二）

为什么先做这一步：契约把材料摄取分成三步 —— 记号（人在页边写）、AI 提取（产出 `mindnet.material/1`
清单）、**格式转化（确定性代码）**。前两步靠人和模型，第三步是纯函数，可以在这里做完并且被逐位对拍。
`app/lib/domain/services/ingest/material_ingest.dart` 就是第三步：一份材料信封进去，出来三样正产品 ——
规范清单（`MaterialStandardItem`，每条带记号/角色/出处/含义/是否进图/节点 id）、图补丁
（`MaterialGraphPatch`，先节点后边）、以及可直接交给 `mindnet.run/1` 的请求（`MaterialRunRequest`：
先建节点、再建边、把 `★` 设为目标，每条动作都带 `evidence` 的出处与"哪一页"）。

确定性意味着可对拍：节点 id 走 32 位 FNV-1a（`en::w::resilient` / `en::s::9ef4708d` / `en::method::…`），
同一页拍两次得到同一批 id（幂等键 `batch_id`，重复条目用 `duplicate_of` 复用节点）。这一层不写库、
不发请求：`checkRunRequest` 只按 `io_check` 的语义在**影子图**上校验 —— 同一份请求里"先建节点、再给它们
设目标"必须算合法，否则材料批量入库的正常形态会被误判成"目标不在图里"。

对拍不是"照文档抄"：`app/tool/` 下留了一套三件式 harness（`ingest_parity_reference.cjs` 跑 MindNet 的
`src/ingest.js` → `dart run tool/ingest_dump.dart` 跑这一层 → `ingest_parity_compare.cjs` 逐字段比较；
需要外部 MindNet 检出与 node）。示例信封上的结果是 `PARITY OK`：6 节点 / 7 边 / 14 动作 / 6 条标准条目，
除五处**有意差异**外逐字段相同 —— 五处都写进了 library doc 并被测试钉住：① `evidence.quote` 真的带页边
那一行（JS 恒为 null）；② hub 的 region 写 `第 ? 页`（JS 会插值出 `第 undefined 页`）；③ 不做 NFC
归一化（Dart 标准库无此函数，`pubspec.yaml` 也无此依赖）；④ `Number()` 语义里 `[]`/`{}` 一律算
"不是数字"；⑤ 汇总不报"几张卡"（卡片是 INGEST §4 的可选呈现层，这一层不产出）。对拍第一次跑就抓到
一个真差异：动作里的边多带了一个 `why` 键（`mindnet.run/1` 的 Edge 只有 `id/from/to/ls`），已改回去
并加了断言 —— 这正是"照文档写"抓不到的那类错。

三条刻意选择：① **整份拒绝**：校验不过就抛 `MaterialIngestException`，绝不让半份材料生效（顺序与
`src/ingest.js` 一致，报错文案是人话 + 第几条）；② **不进图 ≠ 丢弃**：疑问/已知/提醒这些角色进 `skipped`
并带原因，不认识的记号按"未分类"收下并给 `unknown-mark` 告警（INGEST §5 第三条不变量）；③ **不猜**：
`meaning_source` 只认 `ai`/`user`，缺页边说明又用了省力通道就报错，材料元数据进节点 `meta`
（`Node.from_object` 不读这个键，所以不破坏模型状态）。

证据：`app/test/domain/services/ingest/material_ingest_test.dart` 56 例（对拍值：3 个 hash、6 个节点
id/类型/名字、7 条边的顺序与权重、14 条动作与 `evidence`、汇总文案、幂等；报错族 16 种；告警族 7 种；
角色优先级与 `duplicate_of`；`checkRunRequest` 正反例）。**还没做**的是把这一层接出去：
① "添加资料"入口（AI 产出信封 → 这一层 → `knowledge` 动作 + 出处进 `evidence`/`change_log`）；
② TRANSCRIBE 的"照片 → `run/1`"（含出处与置信度）；③ 资料与卡片的关联类型（线索边 vs 包含边）
—— **已在轮次六十八定案并落库（`knowledge_edges`，schema v18），见后面那一节**。

### 切片 6 的下一步：材料信封 → 待确认提案（轮次六十三）

为什么先做"提案"而不是直接写库：上一半（轮次六十二）已经把信封变成"节点/边/`run/1` 请求"，
但那是**图**的语言；应用侧真正的入口是"AI 读完材料，告诉用户要建什么、每条出自哪一页"，用户点头才写。
这个先例在拍照整理通路上已经立过（`handwriting_proposals.dart` + `HandwritingProposals.appliedAt` NULL = 还没确认），
认知侧照抄同一纪律：`material_intake_plan.dart` 只算提案，`ingest_material` 工具 `readOnly: true`，一行都不落库。

- `MaterialIntakePlanner.plan(...)` 吃 `MaterialConversion` + 信封 + 已有知识点标题集合：
  进图的条目 → `kp:<nodeId>` 知识点提案；图补丁的边 → `edge:<edgeId>` 连接提案；
  `question`/`known`/`note` 等不进图的角色与"与 X 重复"原样留在 `skipped`（带原因）。
  提案 id 直接复用上游的确定性 id，所以**同一个信封算两次得到同一份提案**（以后落库时它就是 `external_id`）。
- 同名知识点标 `exists: true` 而不是硬拒：材料里常有 90% 是旧知识，"不重复建"这件事要能**看见**；
  `title` 与 `nodeId` 都留着，写库时才需要决定按标题还是按 `external_id` 认。
- 主题 hub 默认**只报不建**：`why == 'topic'` 的边会把每个节点都连到同一个 hub，而"这批材料属于同一主题"
  看一眼标题就够了，所以默认不建（roadmap §2-C ④ 定案见轮次六十八；理由从"语义还没定"改成"默认没用"）；
  `include_topic_hubs: true` 才带上。
- 踩到的一个坑：`produce` 反向边不是由 `contains` 自动生成的，前置条件是条目上 `produce: true`（或
  `modified: ['produce']`，且 mark 不是 S/T）—— 见 `material_ingest.dart:1374-1399`；测试 fixture 少了它
  就只有 contains 没有 produce。

两条刻意选择：① **整份拒绝**照旧 —— 信封不合规就 `ToolResult.failure`，绝不产出半份提案；
② **不进图 ≠ 丢弃** —— `skipped` 一条不少地进 payload（条数还写进 summary）。

证据：`app/test/domain/services/ingest/material_intake_plan_test.dart` 13 例 +
`app/test/features/ai/ingest_tools_test.dart` 8 例 = 21 例（三行小信封的提案数/跳过数、`kp:en::w::…` 的 id、
body 里的释义/原文/出处、同名 `'  Rely   ON '` 归一化后 `exists`、`includeTopicHubs` 的两种计数、
只含「问」时 `isEmpty`、工具侧 readOnly/缺参数/整份拒绝/同名不重复建/JSON 文本等价）。

**还没做**：① 把提案落库 —— **已在轮次六十四补上**（见下一节）；"添加资料"的界面入口仍未做；
② TRANSCRIBE 的"照片 → `run/1`"；③ 资料与卡片的关联类型 —— **已在轮次六十八定案并落库（`knowledge_edges`），见后面那一节**。

### 切片 6 的下一步（二）：提案落库与确认写入（轮次六十四）

上一节把提案摆出来了，这一节把它**写下去**——但只在用户点头之后。写法照抄拍照整理通路：
先落一张"批次 + 提案"的表，确认过的行才有 `applied_at`。

- schema **v17** 两张表（`app/lib/data/database/tables.dart`）：`material_intake_batches`
  （主键 `batchId`，就是信封的 `batch_id` —— INGEST 契约里的幂等键；`skipped_json` 单独一列，
  因为"留在清单外"不是待确认产物）与 `material_intake_proposals`（主键 `<batchId>#<proposalId>`，
  `sortIndex` 保留材料顺序、`payloadJson` 只留一份契约、`appliedAt` NULL = 还没确认）。
  迁移是"加两张表"（`_upgradeV16ToV17`），并在 `_ensureColumns()` 里自愈 —— Drift 在
  `user_version` 等于当前版本时跳过 `onUpgrade`，那一刻没有自愈，第一次写就会炸。
- `MaterialIntakeRepository`（`app/lib/data/repositories/material_intake_repository.dart`）：
  `record` 幂等（同一批重算只替换**未确认**的行，已确认的一个字不动 —— 重算覆盖人工决定比丢数据更坏）；
  `apply` 把知识点写进 `knowledge_points`，两道去重：提案自己的 `exists`（同名）与 `external_id`
  （用户改过标题之后同名判断就抓不住了，而 `external_id` 是材料决定的内容 id）。
- `apply_material_intake` 工具（`app/lib/features/ai/tools/ingest_tools.dart`）：参数是**同一份信封**，
  不是"提案清单" —— 提案由信封确定性推导，所以"确认"只需说清确认哪一批、哪几条；`proposal_ids`
  越界直接拒绝（不许悄悄少写）。`redo` 的路径是"再跑一次同样的信封"。
- **连接不写**：`why == 'topic'`（以及所有连接提案）在当时没有落点（§2-C ④ 未定），写出来只能是编的；
  它们在结果里如实报 `deferred`，并且**保持未确认**留在待办里，等那个决定 ——
  **那个决定在轮次六十八下了（`knowledge_edges`），见后面那一节**。

三条刻意选择：① **复核式确认**：工具重算一遍信封而不是接收一份"提案清单"，因为确定性来自内容，
   这样"看到的"和"确认的"不可能不是同一份；② **连接宁可 deferred**：没有落点的写入不假装做完；
   ③ **payload 里的批次取确认之后的样子**（`unapplied_count` 要能直接读出还剩几条，而不是记录那一刻的旧值）。

证据：`app/test/data/repositories/material_intake_repository_test.dart` 9 例 +
`app/test/features/ai/apply_material_intake_tool_test.dart` 8 例 + `app/test/data/database/v17_migration_test.dart` 2 例
= 20 例（幂等记录/替换未确认/已确认不动、apply 的 external_id 与出处文案、同名与改过标题两种去重、
确认两次幂等、`proposal_ids` 只处理选中项与越界拒绝、连接 deferred 且仍待办、未知批次报错、
"被盖成 v17 却没有这两张表"的自愈）。

**还没做**：① "添加资料"界面入口（AI 产出信封 → 这两步 → 用户逐条确认；现在只有 AI 工具的路径）
—— 已在轮次六十五补上，见下一节；
② TRANSCRIBE 的"照片 → `run/1`"；③ 资料与卡片的关联类型（连接落点就等它）—— **轮次六十八定了：连接落成 `knowledge_edges` 线索边**，见后面那一节。

### 切片 6 的下一步（三）：界面上的"添加资料"（轮次六十五）

为什么要它：轮次六十二～六十四 把这条链的机械部分都做好了（信封 → 标准清单/图补丁/`run/1` 请求 →
待确认提案 → 确认后写库），但**只有一个能动它的入口是 AI 工具**。用户在"设置 → 添加资料"里能自己贴一份
信封、看清要建哪些知识点与连接、每条出自哪页哪行，勾选之后才写 —— 这才让"纸质工作和智能管理同步"这条
使用路径闭合，也让"确认前不写库"从纪律变成界面上看得见的事实。

界面上的三步与 AI 工具完全同构（读法只有一处：`app/lib/features/cognitive/application/material_intake_reader.dart`）：

- **贴信封**：`decodeMaterialEnvelope` 收对象或 JSON 文本（空串、非 JSON、别的类型各给人话错误）。
- **看提案**：`readMaterialPlan` = 解码 → `MaterialIngest.convert` → `MaterialIntakePlanner.plan`
  （`existingTitles: await repository.existingTitles()`，看提案和写提案用同一份标题）；
  页面**立刻** `recordMaterialPlan` 把这一批落成"待确认"，所以"看过了"这件事本身不留悬念。
- **勾选确认**：轮次六十五时只有知识点可勾（连接没有落点，勾不动，如实显示"先不动"）；
  **轮次六十八起连接也可勾**，落成 `knowledge_edges` 的线索边（缺端仍如实报 deferred）。
  `apply(batchId:, proposalIds:, appliedAt:)` 之后刷新批次读数 —— 因此 `unapplied_count` 是确认**之后**的值。

三条刻意选择：① **连接不给勾选框**（轮次六十五）：能点的控件就应该能做成，勾不动胜过点了没反应；
轮次六十八把落点定下来之后，这条就反过来变成"既然能做成，就没有理由不给勾"；
② **提案与批次读数都在同一页**（`N 条提案 · S 条留在清单外 · 已登记（U 条）`），
"清单外"不是悄悄丢掉；③ **不做 AI 提取**：这一步只吃 `mindnet.material/1` 信封，
"从照片/文本产出信封"是 TRANSCRIBE 与提示词那一步的事，界面不假装会。

证据：`app/test/features/cognitive/presentation/material_intake_page_test.dart` 8 例
（解码的四种输入 4 例 + 页面 4 例：看提案→确认后知识点进库而连接勾不动、同名标"已存在"且只写 1 个、
协议错整份拒绝且一行不写、只有「问」的材料明说没有要动的东西）。
（轮次六十八把连接接上之后，这 4 例里的两例改成"连接也进库"，见下一节。）

**还没做**（当时）：① 从"待确认清单"恢复的界面（仓储已有 `batches()`/`pendingProposals()`，页面目前只认刚贴的这一批）
—— **已在轮次六十九补上，见后面那一节**；
② TRANSCRIBE 的"照片 → `run/1`"（确定性那一半已在轮次六十六补上，见后；照片本身未做）；
③ 资料与卡片的关联类型（连接落点等它）—— **轮次六十八定了：连接落成 `knowledge_edges` 线索边**。

### 切片 6 的下一步（四）：转写规程的确定性那一半（轮次六十六）

为什么要它：`docs/archive/TRANSCRIBE.md` 的规程一半是"上游 AI 看图写字"，另一半是**确定性代码**
（校验、说人话、预告机制路径）—— MindNet 里那一半是 `tools/io_check.js`（在克隆引擎上试跑）。
应用侧在此之前只有一个 `MaterialIngest.checkRunRequest`（结构校验），既没对齐 `src/io/run.js` 的
全部规则，也不说"这份请求会做什么"。这一轮把那一半补齐，并把给上游模型的提示词（含【图清单】）
一起生成出来 —— 于是"照片 → `run/1`"这条链上，**除了照片本身**都已经能对着规程自检了。

三层，越往下越"我们说了算"（`app/lib/domain/services/ingest/transcribe_run.dart`）：

- `decodeRunRequest`：对象或 JSON 文本 → `MaterialRunRequest`（空/非 JSON/别的类型各给人话错误）。
- `reviewTranscribedRun`：**只校验、不执行**。硬错（整份拒绝）与建议（不拦）分开：
  硬错覆盖协议、`run_id`、`actions` 不是数组、`steps` 非 ≥0 整数、缺时间基、`outcome` 白名单、
  **同一节点两个矛盾结论**、图里没有这个节点、边端点缺失、`goal` 目标缺失；
  建议覆盖缺 `evidence`、`review` 的 `quote` 空、缺 `confidence`、`confidence` 不在 0–1、
  `reviewed_solution` 只对 `wrong` 有意义。每条动作还给一行机制路径预告
  （`correct→retrieval_success`、`wrong`/`blank→lapse`、`wrong + reviewed_solution→retrieval_failure_feedback`、
  `exposure→reread`、`knowledge→新增节点/边`、`goal→目标`、`time→时间前进/时间设为`）。
- `buildTranscribePrompt`：§6 的提示词全文，【图清单】由 `knowledge_points.external_id` 生成 ——
  "不许发明节点 id"这条约束因此有真实依据，而不是靠 AI 自觉。

这一轮顺带在两处**真保真问题**上改了代码（都是"照文档写"抓不到的那类）：① `src/io/run.js` 对可选数字
用的是 `!== undefined`（**键在不在**），而 Dart 的 `numberOrNull` 照 JS `Number()` 语义把 `null` 算 0 ——
`closeness` / `elapsed_hours` / `confidence` 因此改成按"键在不在"解析，否则 `time` 动作少写
`elapsed_hours` 会被预告成"时间前进 0 小时"；② `time` 动作可以只用 `elapsed_hours`，其余动作必须有 `at`
（这条决定了"缺时间基"的判定，也决定 `time` 块可以整体不写）。

三条刻意选择：① **只校验、不执行**：应用侧暂时不跑引擎，所以这里像 `io_check` 一样只说"会做什么"，
绝不说"已经做了"；② **建议不拦**：规程说"建议全带"，但缺一条 `confidence` 不该让整份请求作废 ——
只有硬错才整份拒绝；③ **图清单从库里查**：`review`/`exposure`/`goal` 只能指向图里已有的节点，
而"图"在应用侧的真实来源就是 `external_id` 这一列。

证据：`app/test/domain/services/ingest/transcribe_run_test.dart` 32 例（解码 4 型 + 硬错族 15 例 +
建议族 4 类 + 五种动作的预告文案 + `report.text`/`toJson` 3 例 + 提示词的图清单/空清单/补充说明）、
`app/test/features/ai/check_transcribe_run_tool_test.dart` 8 例（只读且注册表里拿得到、缺 `request`
与非法 JSON 都是参数错、好请求给机制路径与出处统计、节点不在图 → `ok false` 整份拒绝、
图清单默认来自库里 `external_id`、JSON 文本与对象等价、协议错也照给预览便于定位）。

**还没做**：① 照片本身（视觉模型 → 信封/请求，含出处与置信度）—— **调模型那半段已在轮次七十六
补上（`app/lib/features/cognitive/application/photo_transcribe_service.dart`），界面入口未做**；
② 把 `run/1` 真的跑进引擎
（应用侧目前只校验）；③ 资料与卡片的关联类型（§2-C ④）—— **轮次六十八已定案并落库**。

### 纪律落地：SM-2 只剩存档（轮次六十七）

第 3 节末尾那条纪律（"FSRS 仍是到期日唯一权威""一张表的一列只有一个写者"）在代码里一直差最后一步：
`docs/GAP_ANALYSIS.md` 的 D9 把 SM-2 定成"模块保留为存档文件、**不再被调用**"，
`docs/FEATURE_MATRIX.md` 也一直记着这条遗留 —— 旧入口 `features/anki/application/anki_service.dart:23`
被 `features/anki/presentation/anki_page.dart:273` 调用，仍然走 `sm2_scheduler.dart`。
这一轮把它清掉：

- 删掉 `app/lib/features/anki/presentation/anki_page.dart`（333 行）与
  `app/lib/features/anki/application/anki_service.dart`（64 行），以及只服务于前者的
  `ankiServiceProvider`（`app/lib/data/repositories/repository_providers.dart`）。
  两个文件都**没有任何入口**：全仓引用只剩它们自己（`ops_grep anki_page|AnkiPage` 的命中只有
  自身 + 三份文档），v2 复习流早就换成了 `knowledge_page.dart` → `review_page.dart` →
  `review_service.dart` 的 `FsrsScheduler.schedule`。
- `app/lib/domain/services/srs/sm2_scheduler.dart` **留着**（D9 要的是"存档"而不是删除），它的单测也照跑。
- 新守门测试 `app/test/domain/services/srs/single_scheduler_authority_test.dart`：扫 `lib/`，
  除存档文件本身外不许有任何 `.dart` 文件提到 `Sm2Scheduler` —— 于是"不再被调用"从文档承诺变成可执行事实。

三条刻意选择：① **删调用点而不是改算法** —— 把旧页也迁到 FSRS 等于给一个没有入口的页面续命，
真正的问题是"第二个写者存在"；② **存档文件保留** —— D9 与 `docs/MILESTONES.md` 都写明
"模块保留、测试删/迁"，删它得先改文档，所以留着并加守卫；③ **守卫用源码扫描** ——
这条纪律是"代码里不许出现某个调用"，领域测试证明不了它，只能扫源码（测试里对 `Directory('lib')`
有 `existsSync` 断言，工作目录跑偏时会给理由，而不是静默通过）。

证据：`flutter test test/domain/services/srs/` → `+51`（含新守卫与存档模块自己的 3 例）；
`dart analyze lib test` → `94 issues found`（删掉的文件少了 1 条既有 info，**0 error / 0 warning**）；
全量 `flutter test --concurrency=1` → `+1824 ~2: All tests passed!`。

**还没做**：① `docs/PROGRESS.md` 里 v0.1 时代的 SM-2/AnkiService 记录是历史，不改；
② `home_shell.dart` 仍是 6 个旧页（`docs/DESIGN_BLUEPRINT.md` 记的 R4/R5 UI 接线）；
③ 其余纪律项（未标定参数显式标注、43 条 tierA + B01 守卫）由各自的测试守着，不受本轮影响。

### 切片 6 的下一步（五）：线索边落库 —— 资料与卡片的关系定案（轮次六十八）

为什么要它：§2-C ④ 是 C（给题目/知识点补资料）里最后一条"还没定"。在此之前，材料里的连接一律
**不能落**：`apply` 如实报 `deferred`（宁可少写也不编），界面上的连接勾选框直接置灰。定案依据是
`E:\Document\MindNet\docs\MEMORY_RECORD.md` §3.5（`:102-103`）：**标签树的父子边是"包含"语义，
MindNet 的边是"线索"语义 —— 严格有向、不自动反向；边权 `ls` 目前没有标定来源**。于是这一轮把
"关联类型"与"连接落点"两件事一起定下来并落库（schema v18）。

- 新表 `knowledge_edges`（`app/lib/data/database/tables.dart`）：
  `id`(PK，就是 INGEST 那条边的 id，去掉 `edge:` 前缀 ⇒ 幂等键) / `from_id` / `to_id` / `origin`
  / `ls`(可空) / `ls_calibrated`(默认 `false`) / `batch_id` / `source` / `created_at` / `updated_at`。
- **两种语义各归各家**：包含语义仍然只有标签树父子边一处（`tags.parent_id`）——线索边**不**复制它；
  线索边严格有向，`from → to` 与 `to → from` 是两条不同的边，不自动补反向。
- **两端都在才落**（`app/lib/data/repositories/material_intake_repository.dart` 的 `_createEdge`）：
  端点按 `knowledge_points.external_id` 认（本批刚建的或库里已有的都算）；缺一端就报
  `deferred` + 人话原因（`起点 …(或终点/两端)还不在库里`），**不建边、也不标 `applied_at`**，
  它留在待办里等端点补齐 —— 与 MindNet `validateRequest` 的影子图规则同构。
- `apply` 先把待处理提案按 `kind.index` 排序（知识点在前），再逐条处理，于是"同一批里刚建的点"
  立刻就能当端点用；`MaterialApplyOutcome` 分成 `created`/`createdEdges`/`existing`/`existingEdges`/
  `deferred`/`remaining` 六个数，`toJson()` 给出 `created_edges` / `created_edge_count` / `existing_edges`。
- 落边的 `ls` 照抄提案，**但 `ls_calibrated` 一律 `false`** —— §3.5 说它没有标定来源，就不假装有；
  `origin` 记下它来自材料里的哪种关系（`contains` / `produce` / `topic`，缺省 `material`），
  这是以后要标定 `ls` 时唯一能用的线索。
- 界面：连接提案不再置灰（`materialIntakeConnectionClue` 取代了 `materialIntakeConnectionDeferred`），
  默认与知识点一起选中；确认后的成绩单把两类合计着说（"写入 N 条（知识点与线索边）…N 条连接落不了"）。
- 工具：`apply_material_intake` 的 summary 多了"建了连接 A → B（origin）"与"连接落不了（有一端还不在库里）"，
  `afterJson` 多了 `edge_ids`。

三条刻意选择：① **不建通用边表** —— 此前那 33 张表里本来就没有通用边表（`ObjectTags` 是 tag↔object），
硬造一张"什么边都能装"的表，正是 §3.5 警告的那种语义混淆；线索边就是线索边，一张专表；
② **`origin` 存关系名而不是"材料 id"** —— 材料已经在 `batch_id` / `source` 里了，`origin` 要回答的是
"这条边凭什么存在"（含 / 产 / 主题），标定 `ls` 时用得上的就是它；③ **缺端就 defer，绝不编边** ——
一条只有一端的边写进库，比不写更糟：它会被后续的图算法当成事实。

证据：`flutter test test/domain/services/ingest/material_intake_plan_test.dart
test/data/repositories/material_intake_repository_test.dart
test/features/ai/apply_material_intake_tool_test.dart
test/features/cognitive/presentation/material_intake_page_test.dart
test/data/database/v18_migration_test.dart` → `+41: All tests passed!`；
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）；
全量 `flutter test --concurrency=1` → `+1826 ~2: All tests passed!`（轮次六十七 后 `+1824 ~2`，
差值 2 = 新的 v18 迁移测试两例：真 v17 文件升级、被盖成 v18 缺表靠 `beforeOpen` 自愈）。

**还没做**：① `ls` 仍**没有标定来源**（标定实验是 §3 第 7 行那六条，需要外部数据，不是应用侧能自证的事）；
② 落下来的边**当时**还没有任何界面读它（数据在库里，知识点页/图视图都还没画它）—— **轮次七十给了它唯一的读法：只读清单页**；
③ TRANSCRIBE 的"照片 → `run/1`"里的照片本身；④ 把 `run/1` 真的跑进引擎。

### 切片 6 的下一步（六）：从"待确认清单"恢复（轮次六十九）

为什么要它：轮次六十五给这条路开了界面入口，但**入口只在"刚贴完那一批"上活着**。仓储其实早就把
"算过但还没点头"存住了（`material_intake_batches` + `material_intake_proposals`，`applied_at` NULL），
可关掉页面之后那批就没人能接着确认 —— 库里存着规矩，界面上看不见，等于把"确认前不写"这条纪律
做成了"确认前不写，除非你别关页面"。这一轮把第二个入口接上：**清单**。

- `app/lib/features/cognitive/application/material_intake_reader.dart` 多两个入口：
  `readPendingBatches({repository})`（`repository.batches()` 里只留 `unappliedCount > 0`，新的在前）
  与 `readPendingBatch({repository, batchId})`（批次不存在给 `null`，否则读 `pendingProposals`）。
  **它们不重算**，只是把当初登记的提案按原顺序读回来 —— 所以"接着看的就是当初那一份"不是承诺，是同一条记录。
- 页面（`material_intake_page.dart`）打开就刷清单，`_restore(batch)` 把那批读回来接着勾；状态从
  `_draft` 换成"提案 + 跳过项 + 批次"三样，于是**贴信封与恢复共用同一条渲染与确认路径**。
- 确认之后同时刷**批次读数**与清单：成功时落不了的连接照旧没确认（`deferred` 不标 `applied_at`），
  所以"还剩 N 条"与清单上的"待确认 N 条"是同一个数 —— 同一页上两个数字不许互相打脸。
  都确认完了就不再念"待确认 0 条"（欠账还清这件事由成绩单说）。
- 清单里每批给 `batchId`、待确认条数与转化汇总那句话；点了"接着确认"才展开提案（没点之前不占屏幕）。

三条刻意选择：① **恢复不重算**：重算意味着"看到的"可能已经不是"库里那份"，而这条纪律的全部价值就是
两者一致；② **清单只列有欠账的批次**（`unappliedCount > 0`）—— 一个"都是 0 的清单"没有信息量；
③ **入口不新增页面**：恢复是"看提案"的同一件事，多一个页面就多一处能走偏的渲染。

证据：`app/test/features/cognitive/presentation/material_intake_page_test.dart` 11 例（新增两例：
"从待确认清单恢复：接着确认的就是当初那一份"——预登记一批 → 新页面看到清单 → 恢复 → 确认 4 条后
知识点 2 行、线索边 2 行、清单不再出现；"确认一部分之后，清单里剩下的接着等着"——只确认 3 条时
成绩单的"还剩 3 条"与清单读数一致；另有 `readPendingBatch` 对不存在的批次返回 `null` 一例）。
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）。

**还没做**（当时）：① 清单只显示"还没确认完"的批次，**已确认完的历史**没有地方可看 ——
**轮次七十三补上，见后面那一节**；
② TRANSCRIBE 的照片本身（§2-C ③）；③ 把 `run/1` 真的跑进引擎；
④ 落下来的线索边还没有界面读它 —— **已在轮次七十补上，见下一节**。

### 切片 6 的下一步（七）：线索边的读法（轮次七十）

为什么要它：轮次六十八让连接**能落库**，可那张表**一个读者都没有** —— 资料里的连接确认之后进了
`knowledge_edges`，界面上再也见不到。有写者没读者的表，等于把"资料进图"这件事藏进库里：
用户既看不到线，也没法判断它是空、是错、还是自己确认过的。这一轮补的是**读法**。

- `app/lib/data/repositories/knowledge_edge_repository.dart`：只读快照 `KnowledgeEdgeView`
  （`fromId`/`toId`/两端标题/`origin`/`source`/`ls`/`lsCalibrated`/`createdAt`），`all()` 新的在前。
  两端的标题按 `knowledge_points.external_id` 解出来；**那一端不在库里就是 null**，界面按 id 显示 ——
  读法不替图编造节点。同一个 `external_id` 有多行时取第一个（读法要确定，不许每次刷新换个名字）。
- `app/lib/features/anki/presentation/knowledge_edge_page.dart` + 知识模块 AppBar 入口
  （`Icons.hub_outlined`，挨着"今日复盘"）：一条边一行，`A → B` + 关系人话 + 材料出处 +
  `ls 0.60（未标定）`；有一端缺失时另说一句；材料没给 `ls` 就说"没给"（不显示 0，也不假装有未标定权重）；
  空库明说"还没有线索边"，而不是摆一个空列表。
- 这一层**只读**：不建边、不删边、不改 `ls`。边的写者仍然只有材料摄取那一处（确认过的连接）。

三条刻意选择：① **先给全量，不按知识点分页** —— 这一页回答的是"图里现在有什么线"；
按点筛选要先把入口定在管理页的哪一行，先做就等于先猜用户想从哪个点看；
② **缺端照实显示 id** —— 编一个"未知知识点"看着体面，却把"图不完整"藏起来了：缺端是数据状态，不是显示问题；
③ **认不出的 `origin` 照实显示原文** —— 不硬塞进"材料"那一类，否则上游给了新关系也没人会发现。

证据：`flutter test test/data/repositories/knowledge_edge_repository_test.dart
test/features/anki/knowledge_edge_page_test.dart` → `+8: All tests passed!`
（4 例读法：两端解名与次序、缺端、`ls` 未给、空表；4 例页面：空说、整条、缺端、没给 `ls`）；
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）。

**还没做**：① 按知识点看它自己的线索边（先要定入口放在管理页哪一行）—— **轮次七十一补上，见下一节**；
② 手写/删除边的界面（写入路径仍只有材料确认那一条）—— **轮次七十二补上，见下两节**；
③ `ls` 仍没有标定来源（§3 第 7 行那六条实验）；
④ TRANSCRIBE 的照片本身（§2-C ③）与把 `run/1` 真的跑进引擎。

### 切片 6 的下一步（八）：按知识点看线索边（轮次七十一）

为什么要它：轮次七十有了清单页，回答的是"图里现在有什么线"；可用户真正会问的是反过来的一句 ——
**"这个词 / 这句话在图里连着谁？"** 清单页能翻，但它把方向冲淡了：同一条边在清单里只是 `A → B`，
站在某个点的详情里应当是两句话，"它指向谁"和"谁指向它"。这一轮把读法从"图的角度"补到"点的角度"，
入口就放在管理页里点开一个知识点的那张详情对话框 —— 那里已经有标签段和卡片模板段，它本来就是"这个点的详情"。

- `KnowledgeEdgeRepository.forPoint(externalId)`：一个点的**出边和入边一起**读回来
  （`fromId == id | toId == id`），次序沿用清单页那一条（新的在前）；方向留给调用方判断 ——
  "谁指向谁"是显示层的事，仓库不替它挑一边。
- `KnowledgePointEdgesSection`（新 widget，`app/lib/features/anki/presentation/knowledge_point_edges.dart`）：
  标题行 + 每条边一行，站在**这个点**的角度说话 —— 出边 `它指向：X`、入边 `指向它：X`，各带自己的箭头，
  关系名复用清单页那套人话（`knowledgeEdgeOriginLabel` 从页面私有提成公开顶层函数，两处读同一份口径）。
  管理页那边只是三行接线（`KnowledgePointEdgesSection(externalId: kp.externalId)` 加在对话框 ListView 末尾）：
  那个 804 行的页面不塞新逻辑，新 UI 拆成独立 widget 单独测（那一页此前没有 widget 测试，也不为了这个补一整套）。
- **手写的知识点没有 `external_id`**（`KnowledgePoints.externalId` 是 nullable 的）⇒ 这里必须分两种"没有"：
  不在图里 ⇒ "这个知识点不在材料图里（没有 external_id），所以没有边可看"；在图里但库里没有边 ⇒
  "还没有线索边（材料里的连接确认之后才会有）"。拿一个空列表冒充"它没有边"，
  就是把"我从没进过图"说成"我查过了，确实没有"。

三条刻意选择：① **入口不往 tile 上加第 5 个图标** —— 管理页每个 tile 的 trailing 已经有四个
（autoBlank / edit / add_card / delete），再加一个会把"这个点是什么"和"它连着谁"挤在同一行；
对话框本来就是这个点的详情，加一段比加一个按钮更贴题；② **出边入边都算它自己的** —— 只看"它指向谁"
会漏掉"谁指向它"，而后者恰恰常是"这句话为什么出现在这张卡上"的答案；方向在显示层说清楚就够；
③ **两种"没有"说两句话** —— 见上，`external_id` 缺失是数据状态，不是"没有边"。

证据：`flutter test test/data/repositories/knowledge_edge_repository_test.dart
test/features/anki/knowledge_point_edges_test.dart` → `+9: All tests passed!`
（2 例新增读法：出边入边都算且别人的边不混进来、查无此点为空；3 例 widget：没有 `external_id` ⇒ 说不在图里、
在图里没边 ⇒ 说还没有、一出一入 ⇒ 方向与关系名都在）；`dart analyze lib test` → `94 issues found`
（**0 error / 0 warning**）；全量 `flutter test --concurrency=1` → `+1842 ~2: All tests passed!`
（轮次七十后是 `+1837 ~2`，差值 5 = 本轮新增的两处）。

**还没做**：① 点开一条边跳到另一端的知识点（现在只显示名字，不能跳）；
② 手写/删除边的界面（写入路径仍只有材料确认那一条）—— **轮次七十二补上，见下一节**；③ 已确认完的历史无处可看；
④ `ls` 仍没有标定来源（§3 第 7 行那六条实验）。

### 切片 6 的下一步（九）：手写/删除边 —— 那条路现在也能自己走（轮次七十二）

为什么要它：清单页和详情里都还只在**读** `knowledge_edges`，写它的却只有"材料确认"那一条路 ——
于是 `manual`（"手写"）这个关系名虽然早就会说人话，却**没有任何界面能造出一条这样的边**。
可"资料进图"给的只是材料里明写着的连接；用户自己看出来的那一条（"B 那句话是在解释 A"），
以前只能等下一份材料顺带提到它。这一轮把第二个写者补上，同时把"只能删自己写的"钉死。

- `KnowledgeEdgeRepository`：新增 `graphPoints()`（图里的点 = `knowledge_points.external_id` 非空的那些，
  按 externalId 去重、按标题再按 id 排序）、`createManualEdge({fromId, toId, now})`、
  `deleteManualEdge(edgeId)`；三条硬约束写在仓库里，界面只负责说人话 ——
  ① 两端都必须在图里（缺一端 ⇒ `unknownEndpoint`，自己连自己 ⇒ `samePoint`）；
  ② 同一个方向只留一条边，**不管它是谁写的**（已有边 ⇒ `alreadyExists` 并把那条边的 origin 报回来）；
  ③ 只有 `origin == 'manual'` 的边能这样删（材料确认来的边要回材料那一步 ⇒ `notManual`）。
  手写边的 `id` 是 `manual:$fromId->$toId`，`ls` 不给（没有标定来源就不假装有），`source`/`batchId` 都为空。
- `KnowledgePointEdgesSection`：末尾永远有一个"加一条线索边"，点开是方向（它指向 / 指向它）+ 另一端
  的下拉；已有线索边的行只在 `origin == 'manual'` 时出现删除按钮，删之前先问一次。
  `knowledgeEdgeEndpointsProvider`（候选点）放在 `knowledge_edge_page.dart`，不放管理页 ——
  否则和 `anki_manage_page.dart` 成环。

三条刻意选择：① **"同一个方向只留一条"按方向判，不按作者判** —— 图是"这两点之间有一条线索"这个事实，
不是"谁写的那条线索"；再来一条会把同一个事实说两遍，所以报"已经有了（材料确认来的）"而不是偷偷加第二条；
② **写完自己重读，不等 revision** —— `_refresh` 显式 invalidate 三个 provider（这个点的边、候选点、清单页）：
这一段刚动过那张表，绕一圈数据库 revision 只是让界面晚一拍（顺带说明：`AppDatabase.forTesting`
不带写拦截器，测试里 revision 本来就不会动）；③ **`ls` 一律不给** —— 手写的边没有标定来源，
留空比编一个数字诚实，读法那边照旧显示"没有 ls"。

证据：`flutter test test/data/repositories/knowledge_edge_repository_test.dart
test/features/anki/knowledge_point_edges_test.dart` → `+20: All tests passed!`
（5 例新增仓库例：`graphPoints` 只收有 external_id 的点、手写边的形状与反向另算一条、
同方向已有材料边 ⇒ `alreadyExists` 且库里仍 1 行、缺端与自连、删除三种 outcome；
6 例新增 widget：手写出边／入边各落对方向且界面立刻看得见、已有边不重复加、
图里只有自己时确认钮不可按、材料边没有删除按钮、手写边删除全流程）；
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**；方向选择改用 `RadioGroup<String>`
祖先后回到基线，`RadioListTile.groupValue/onChanged` 那 4 条 deprecation info 不再出现）；
全量 `flutter test --concurrency=1` → `+1853 ~2: All tests passed!`（轮次七十一是 `+1842 ~2`，差值 11 = 本轮新增的 5 + 6）。

**还没做**：① 点开一条边跳到另一端的知识点；② 已确认完的历史无处可看 —— **轮次七十三补上，见下一节**；
③ `ls` 仍没有标定来源（§3 第 7 行那六条实验）；④ TRANSCRIBE 的照片本身（§2-C ③）与把 `run/1` 真的跑进引擎。

### 切片 6 的下一步（十）：已经确认完的历史（轮次七十三）

为什么要它：轮次六十九让"关掉页面之后那批还在"，可那只解决了**欠账**那一半 ——
页面只认"还没确认完"的批次，一旦点过头，这一批就从屏幕上消失了。于是"我上次到底建了什么"
只剩库里那几行可查：用户看不到自己做过的事，也就没法判断某条边是哪次材料带进来的。
这一轮把同一张单子的**另一半**补上：已经确认完的批次留在页面上，点开能看当初确认了哪几条。

- `MaterialIntakeBatch` 多了 `appliedCount`（`_toBatch` 一次查询把两边的数都数出来，不再只数没确认的），
  `toJson` 也带上 `applied_count`；`MaterialIntakeRepository.appliedProposals(batchId)` 读**已写下去**的那些
  （`applied_at` 非空，按记录次序）—— 缺端的连接根本没标 `applied_at`，所以这份名单里不会出现"其实没落"的条目。
- 读法（`material_intake_reader.dart`）多两个入口：`readAppliedBatches()`（`!batch.isEmpty && unappliedCount == 0`）
  与 `readAppliedBatch(batchId)`（批次读数 + 已确认的提案）。
- 页面（`material_intake_page.dart`）多一段"已经确认完的（N 批）"：每批一行 `批次：N 条已确认` + 转化汇总那句话，
  点"看看确认了什么"开一个**只读**对话框（没有勾选框）：知识点与线索边各一行，带各自的出处；
  底下说明"这些都进库了：知识点在 `knowledge_points`，连接是 `knowledge_edges` 里的线索边"。

三条刻意选择：① **判据是库里现在的数，不是"当初登记过多少条"** —— 还留着一条落不了的连接
（`unapplied_count > 0`）就不叫确认完，只能待在待确认清单里；否则同一批挂在两张单子上，
用户以为它做完了，其实还有一条没落地；② **历史只读、不给勾选框** —— 这几条已经在库里了，
要改得去它们落地的地方（知识点在管理页、线索边在知识点详情里），这里再造一个"改"的入口就是第三处写者；
③ **历史读的是"已经写下去"的提案，不是"当初打算建"的那份** —— 后者在待确认清单里看；
题目既然是"我上次建了什么"，答案就不能是"我上次想做多少"。

证据：`flutter test test/features/cognitive/presentation/material_intake_page_test.dart` → `+12: All tests passed!`
（新增 1 例 widget：确认完之后这批从"待确认"挪到"已经确认完的"、点开只读对话框看得见两类条目；
另把"确认一部分"那例补上"还有欠账的批次不许同时挂在已确认那张单子上"；
一例普通测试钉住两张单子按库里现在的数分：登记后 applied 0 / pending 4，`apply` 之后 pending 空 / applied 4
且 `readAppliedBatch` 读回的正是那 4 条）；`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）；
全量 `flutter test --concurrency=1` → `+1854 ~2: All tests passed!`（轮次七十二是 `+1853 ~2`，差值 1）。

**还没做**：① **当时**：点开一条边跳到另一端的知识点 —— **已在轮次七十四补上，见下一节**；
② 历史里只有"确认了什么"，没有"哪些是本来就有的"
（`apply` 的 `existing` 没有落库）；③ `ls` 仍没有标定来源（§3 第 7 行那六条实验）；
④ TRANSCRIBE 的照片本身（§2-C ③）与把 `run/1` 真的跑进引擎。

### 切片 6 的下一步（十一）：顺着线索边走（轮次七十四）

为什么要它：轮次七十三 把这一条留在"还没做"里 —— 边是显示出来了，可名字只是名字：
看到 `rely on → I relied on him.` 想知道另一头还连着谁，只能自己回清单页里翻。
线索边本来就是给人**顺着走**的：这一轮让端点名字可点，走到哪一端就看哪一端的边，
并且能在同一层里继续走下去。

- `knowledge_edge_page.dart` 多一个 `KnowledgeEdgeEndpointRef`（图里的 id + 显示名）与
  `showKnowledgeEdgeWalk(context, endpoint:)`：开一个**只读**对话框，摆出这一端自己的线索边
  （复用知识点详情里那一段 `KnowledgePointEdgesSection`），名字继续可点 ——
  于是 A → B → C 可以一层层翻。
- 清单页每一行的两端都成了可点的名字（`_EndpointLink`）：`_EdgeTile` 把"点的是哪一端"交给回调，
  页面把它交给 `showKnowledgeEdgeWalk`；知识点详情（管理页那个对话框）里那一段也接上同一个回调，
  于是同一个走法有两个入口。
- 缺端（`hasMissingEndpoint`）照样走：那一端在 `knowledge_points` 里没有行，但它的边还在
  `knowledge_edges` 里，走过去看得到"这个 id 还连着谁"——比禁掉它诚实。

三条刻意选择：① **只读的对话框，不是新的页面** —— 走法是"看"，不是"管理"：在这里能建边、删边
就等于又搬来一个写入口，改边的地方仍然是知识点详情那一段；② **回调给的是"另一端"的 id 与显示名** ——
走到哪一端，弹出来的就是哪一端的边（出边入边都站在那一端说方向），翻页时方向不会串；
③ **一层层接着走，不做"返回上一层"的历史栈** —— 关掉就回到原来那一页，想回上一个点再点一次它的名字
（图很小、可重入，不需要导航栈）。

证据：`flutter test test/features/anki/knowledge_edge_page_test.dart`
`test/features/anki/knowledge_point_edges_test.dart` → `+16: All tests passed!`
（新增 1 例 widget 走 A → B → C；知识点详情那一段新增 2 例：端点给出的是另一端的 id 与显示名、
没给回调时只是文本；清单页三处标题断言改成"两端名字各自成立"）；
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）；
全量 `flutter test --concurrency=1` → `+1857 ~2: All tests passed!`（轮次七十三是 `+1854 ~2`，差值 3）。

**还没做**：① **当时**：历史里只有"确认了什么"，没有"哪些是本来就有的"（`apply` 的 `existing`
没有落库）—— **已在轮次七十五补上，见下一节**；
② `ls` 仍没有标定来源（§3 第 7 行那六条实验）；③ TRANSCRIBE 的照片本身（§2-C ③）与把 `run/1` 真的跑进引擎。

### 切片 6 的下一步（十二）：成绩单落进历史 —— "本来就有的"这句话存下来了（轮次七十五）

为什么要它：轮次七十三 把"已经确认完的历史"做出来了，但那份历史只会念"当初确认了什么"。
成绩单上那句"哪几条是本来就有的（没重复建）"只活在 `apply` 那一次调用里 —— 关掉页面、重启应用
就没了；同一份材料重贴两次，历史里两条长得一模一样，看不出"这条其实是上次就有的，系统没重复建"。
这条判断**只有确认那一刻知道**（`_createPoint`/`_createEdge` 刚刚查过库），所以它必须随提案一起落库。

这一轮做了什么：

- 新列 `material_intake_proposals.already_existed`（**v19**，见 `_upgradeV18ToV19`）。
  `_createPoint`/`_createEdge` 的结论（`created` / 不是 `created`）在 `_markApplied` 时写进去。
- `appliedProposals()` 的返回从"提案列表"变成 `MaterialAppliedProposal`（提案 + `alreadyExisted`），
  历史对话框那一行因此能说"**已存在，不重复建**"。
- **已经确认过的行不覆盖这句历史**：第一次点头时的判断才是"我上次建了什么"的答案；
  再确认一次（幂等重放）不该把它改写成"本来就有的"。
- 自愈照旧：加的是列不是表，`_ensureColumns` 的 `expected` 里补上这一列；`_tableFor` 也要能认出
  `material_intake_proposals`（0 行也说不清，直接抛 `unknown table` —— 这是第一次跑 v19 迁移测试时
  红出来的洞）。

三条刻意选择：① 句子存在**提案行**上，不另建"成绩单"表（它描述的就是那一条提案的那一次确认）；
② 只记"是不是本来就有的"，不记时间戳/旧 id —— 历史要回答的是"我上次建了什么"，不是审计；
③ 没有 `applied_at` 的行（缺端的连接）一律不出现在历史里，所以"这句话"和"它确实进库了"永远同真。

证据：`app/test/data/database/v19_migration_test.dart`（真 v18 升级 + 被盖成 v19 缺列靠自愈，各 1 例；
造法是 `ALTER TABLE ... DROP COLUMN already_existed` 再把 `user_version` 压回 18）；
`app/test/data/repositories/material_intake_repository_test.dart` 两处补断言（"同名已存在"那条读得出
`alreadyExisted: true`；幂等重放后四行仍全是 `false`）；
`app/test/features/cognitive/presentation/material_intake_page_test.dart` 新增 1 例 widget
（历史对话框里那一条被标出来）；`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）；
全量 `flutter test --concurrency=1` → `+1860 ~2: All tests passed!`（轮次七十四是 `+1857 ~2`，差值 3）。

**还没做**：① **当时**：已确认完的批次仍然只看得到、改不了（不能撤销/回滚一次确认）
—— **已在轮次七十九补上，见切片 6 的下一步（十六）**；
② 历史里不显示"哪几条是这次落不了的"（缺端的连接根本没进历史，只在待确认那张单子上）
—— **已在轮次八十补上，见切片 6 的下一步（十七）**：补的正是**那张单子**（落不了本来就不进历史）；
③ `ls` 仍没有标定来源（§3 第 7 行那六条实验）；④ TRANSCRIBE 的照片本身（§2-C ③）——
**"把照片发出去"那半段已在轮次七十六补上，界面入口未做**；⑤ 把 `run/1` 真的跑进引擎。

### 切片 6 的下一步（十三）：照片 → `run/1` 的调模型那半段（轮次七十六）

为什么要它：轮次六十六 把"照片 → `run/1`"这条链上**除了照片本身**的部分全做完了 ——
提示词由【图清单】生成、请求用 Dart 端口照 MindNet 的 `validateRequest` 逐条校验、输出与
`tools/io_check.js` 同构。可是那张照片从头到尾没有任何一段代码碰过它：用户得自己把提示词
复制到别的模型里，再把答案贴回来 —— "拍照即入库"这句承诺里，**拍照那一步是空的**。

这一轮做了什么：`app/lib/features/cognitive/application/photo_transcribe_service.dart`，
一个函数 `transcribePhoto(...)` 把四步串起来：

- **能发的图**：照片先过 `VisionImageEncoder`（长边压到 1280 再重编码成 PNG，超过 4 MiB 就
  拒绝 —— 宁可说"换一张小的"，也不发半张、让模型自信地答它没看见的内容）。
- **提示词**：`buildTranscribePrompt(inventory: ...)`，图清单（节点 id → 人话名字）与补充说明
  原样填进去；`existingNodeIds`/`existingEdgeIds` 用来查"有没有发明 id"。
- **真的发出去**：`ChatMessage.user(prompt, images: [ready.toPart()])` 交给 `ModelAdapter`，
  **工具列表是空的**（这一步只让模型说话，它想调什么工具都无处可调），累加 `ModelTextDelta`；
  `ModelFailure` 也不抛异常，变成一条人话。
- **读回来**：`extractJsonObject`（AI 常把 JSON 包在代码围栏里）→ `decodeRunRequest` →
  `reviewTranscribedRun`，出错/建议都在报告里（出处、置信度的提醒走 `warnings`）。

结果是一个 sealed 结果集：`PhotoTranscribeReport`（`report` + 模型原话 + 真正发出去的图尺寸）
或 `PhotoTranscribeFailure`（`notConfigured` / `imageTooLarge` / `imageUnreadable` /
`modelFailed` / `emptyAnswer` / `unreadableAnswer`，每条一句人话）。

三条刻意选择：① **只读** —— 不写库、不执行请求（执行是另一件事，§2-C ② 第 79 行那条）；
② **没配模型就不发**：`adapter == null` 直接说"发不出去，先去设置里配"，绝不偷偷联网
（`docs/AI_DESIGN.md §3 D1` 的"唯一开 socket 的地方"照旧只有适配器）；
③ **模型原话留全文** —— 读不成请求时把原文一起留给用户，让他自己看出来模型跑偏在哪，
比只报"解析失败"有用。

证据：`app/test/features/cognitive/application/photo_transcribe_service_test.dart`（12 例：没模型 /
图读不了 / 压过还是太大（三态都断言**一个请求都没发**）/ 照片+提示词一起发出去（断言工具列表为空、
提示词含图清单行、`image/png` 部件在）/ 模型没走完但半句回话留着 / 什么都没写 / 回话里没有对象 /
对象读出来但请求不合法 `ok false` / 建议里"没写 confidence""没有 evidence"都在 /
`extractJsonObject` 三例）；`dart format` 2 文件 `0 changed`；`dart analyze lib test` →
`94 issues found`（**0 error / 0 warning**）；全量 `flutter test --concurrency=1` → `+1872 ~2`
（轮次七十五是 `+1860 ~2`，差值 12）。

**还没做**：① **当时**：**界面入口**（材料页上"选一张照片"按钮 + 报告对话框）—— 服务层已经能跑，
但用户在应用里还按不到它 —— **已在轮次七十七补上，见下一节**；
② 把 `run/1` 真的跑进引擎（应用侧仍然只校验）；
③ `ls` 仍没有标定来源（§3 第 7 行）；④ 已确认完的批次不能撤销 —— **已在轮次七十九补上，见切片 6 的下一步（十六）**。

### 切片 6 的下一步（十四）：照片的界面入口 —— "拍照那一步"现在按得到（轮次七十七）

为什么要它：轮次七十六 把"照片 → `run/1`"的服务层做出来了（`transcribePhoto`），但**应用里没有任何地方
调用它** —— 用户在材料页上按不到，那条链等于只活在测试里。这一轮只补入口：一个按钮、一个只读的对话框。

这一轮做了什么：

- `app/lib/features/cognitive/presentation/material_intake_page.dart` 上多一个"**选一张照片**"按钮
  （`OutlinedButton.icon` + `Icons.photo_camera_outlined`）与 `_readPhoto()`：系统选图 → 图清单与
  "已有的节点/边 id"**从库里现读** → `transcribePhoto(...)` → 弹出报告对话框。
- 报告对话框（`_PhotoReportDialog`）：**合不合法**（`ok`）/ 真正发出去的图尺寸（压过的，不是原图）/
  动作与带出处条数 / 硬错逐条 / "会做什么"逐条 / 建议逐条 / **模型原话**（`SelectableText`，能自己核对、
  也能复制去别处）。
- 两个注入点：`photoPickerProvider`（系统选图）与 `visionEncoderProvider`（压图重编码）。

三条刻意选择：① **只读**：对话框里没有"执行"按钮 —— 照片这条路到目前为止只回答"读成了什么"，
执行是另一件事（`run/1` 进引擎）；也一个字都不写库（零件、边、都不写）；② 照片这条路上出问题
**只改那一行提示**，不清空已经贴好的信封（两件事互不相干）；③ 报告把"合不合法"和"模型答得好不好"
分开说：`ok` 是结构自检，出处/置信度的提醒走"建议"，不混成一句"失败"。

踩到的坑（记下来）：widget 测试的假时钟走不完 `dart:ui` 的解码 —— 第一版照片 widget 测试直接
**10 分钟超时**（两次 `pumpAndSettle`/`toImage` 都卡住）。所以才有 `visionEncoderProvider` 这个注入点；
测试里连 `paintPng` 都不能用（引擎驱动，假时钟下永不完成），picker 改成假字节 + 假编码器。
真编码仍然在 `photo_transcribe_service_test.dart` 里用真图验。

证据：`app/test/features/cognitive/presentation/material_intake_page_test.dart` 13 → **15 例**
（"选一张照片：读成请求、摆出自检结果、一个字都不写库"：断言对话框标题/`结构上合法`/发出去的图尺寸/
模型原话 `run-1`、`adapter.requests` 只有一轮且提示词含 `kp → I relied on him.`、`knowledge_edges` 与
`material_intake_proposals` 都空；"照片读不成请求（没配模型）：说人话，还是一个字都不写"）；
`dart format` 2 文件 `1 changed`；`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）；
全量 `flutter test --concurrency=1` → `+1874 ~2: All tests passed!`（轮次七十六是 `+1872 ~2`，差值 2）。

**还没做**（当时）：① 把 `run/1` 真的跑进引擎（应用侧仍然只校验、不执行）
—— **已在轮次七十八补上，见下一节**；② 照片这条路上"换一张/重试"
（现在读不成只能出去再按一次）—— **已在轮次八十一补上，见切片 6 的下一步（十八）**；③ 历史里不显示"哪几条是这次落不了的"
—— **已在轮次八十补上，见切片 6 的下一步（十七）**；
④ `ls` 仍没有标定来源（§3 第 7 行）；⑤ 已确认完的批次不能撤销 —— **已在轮次七十九补上，见切片 6 的下一步（十六）**。

### 切片 6 的下一步（十五）：把 `run/1` 真的跑进引擎（轮次七十八）

为什么要它：到上一轮为止，应用侧关于 `run/1` 只有两种能力 —— **看**（`checkRunRequest` /
`reviewTranscribedRun`：这份请求合法吗、它会做什么）和**把照片变成请求**（`transcribePhoto`）。
MindNet 的参考实现里，`src/io/run.js` 的另一半是 `applyOne()`：真的改引擎。那一步一直没有对应的
Dart —— 所以"照片 → 图"永远差最后一脚，路修到一半。

这一轮做了什么（新文件 `app/lib/domain/services/ingest/run_executor.dart`）：

- `executeRun(MaterialRunRequest request, {required FastEngine engine, RunAnchor? anchor})`：
  按顺序执行 `time` / `review` / `exposure` / `knowledge` / `goal`，每条留一条 `RunActionTrace`。
- **痕迹与预告同构**：`trace.mechanism` 用的就是预告里那套名字（`retrieval_success` / `lapse` /
  `retrieval_failure_feedback` / `reread` / `graph.add_node` / `graph.add_edge` / `start_diffusion` /
  `hours.advance`），所以测试可以直接把 `reviewTranscribedRun` 的"会走这条"与执行痕迹对账。
- **时间基**（`resolveAt`）：`at.model_hours` 优先；只给 `at.wall` 时用锚点（上一次带 `wall` 的
  `time` 动作）换算出 model_hours，并把这次换算**记进 `assumptions`**（不假装是按小时写的）；
  两个都没有就**停在那一条**并说明原因 —— 绝不默默用"现在"，那正是时间戳漂移类 bug 的入口。
- 失败**不抛异常**：报告写清"第几条没跑成、为什么"，已经跑过的动作**不撤销**（引擎是内存态，
  原请求还在用户手里，重跑就是重放）。
- 没装记忆机制时，复习照样留痕迹，但如实说"没改状态"，`delta` 为空 —— **不编**一个假增量。

顺手抓到的真 bug：`app/lib/domain/services/ingest/material_ingest.dart` 的
`MaterialRunAction.modelHours` 用了 `MaterialIngest.numberOrNull` 而**没有 `containsKey` 守卫**，
而 `Number(null) == 0` ⇒ "只给了 `at.wall`"被当成"模型时刻 0"：时钟直接倒回纪元、复习的
`current_real_time` 错到 0（本条测试先红在这里）。修法与同文件里 `closeness` / `elapsed_hours`
一视同仁（键缺席必须是 null）。

三条刻意选择：① 只动**内存里的图**与那个模拟时钟 —— 不读写库、不调 AI，与 `transcribe_run.dart`
同一条纪律（写进 `knowledge_points`/`knowledge_edges` 是别的层的事）；② 执行层**仍然再拦一次**
上游该拦的（缺时间基、节点不在图里、未知 kind）—— 不默认"一定有人校验过"；③ `time` 只同步
**已经有记忆态**的节点的 `ms`（慢层的曲线推进，不改 `S`），一个新节点也不替它编状态，并如实
写出"同步 N/M 个"。

证据：`app/test/domain/services/ingest/run_executor_test.dart` 新增 **12 例**（空请求；`time` 的
elapsed 与 wall 两条时间基、跟着锚点换算的 `assumptions`、没有锚点就停住；三条 outcome 各走各的
机制与方向（R/S/Sigma）；`exposure` → `reread`；没装机制时说"没改状态"；`knowledge` 先点后边、
端点缺失就停；`goal` 起扩散；未知动作停下；**预告与执行逐条对账**）；`flutter test
test/domain/services/ingest/` → `+113`；`dart analyze lib test` → `94 issues found`（**0 error /
0 warning**）；全量 `flutter test --concurrency=1` → `+1886 ~2: All tests passed!`（轮次七十七是 `+1874 ~2`，
差值 12）。

**还没做**：① 谁来决定"这份请求可以执行了"—— 执行层现在**还没有调用者**（照片那条路已经从"只读到
报告为止"走到"报告里按一下就能试跑"，轮次八十七）—— **已在轮次八十五补上调用者：`check_transcribe_run` 的 `execute` 参数会装配引擎并真的
跑一遍（只读、不落库），但"判断者"仍缺 —— 见切片 6 的下一步（二十二）**；② 执行完怎么落库（`knowledge_points` / `knowledge_edges` 的写入路径）；③ **当时**：
撤销一次确认 —— **已在轮次七十九补上，见下一节**；④ `ls` 仍没有标定来源（§3 第 7 行）。

### 切片 6 的下一步（十六）：撤销一次确认 —— 反悔也能退（轮次七十九）

为什么要有它：历史那张单子（"已经确认完的"）以前只能看、不能改 —— 点错了只能去知识点管理页
手动删，那是**第三处删法**：漏删一条边、或者误删掉"本来就有的"老行，界面上都不会有人拦。

- 入口开在材料页「看看确认了什么」对话框里，但**写仍然只有一个写者**：撤销走的就是确认那一层的
  `MaterialIntakeRepository.undoBatch(batchId)`（`app/lib/data/repositories/material_intake_repository.dart`），
  不在知识点管理页新开一处删除路径。
- 语义是**整批要么全撤、要么全不动**：只要有一条撤不干净，就一条也不删，把拦路的理由逐条摆出来
  （`MaterialUndoOutcome.blocked`）。拦路的四种情形：知识点下面已经有卡片（`card_states` **或**
  `card_templates`，模板也算卡片）、知识点已经打过标签（`object_tags`，`object_type = 'knowledge_point'`）、
  这个点上挂着**别的**线索边（`knowledge_edges.batch_id` 不等于本批）、提案没有内容 id（认不出建的是哪一行）。
- 计划里的细节：本批自己建的边（`batch_id` 等于本批）跟着点一起撤；行**已经不在了**（被手删过）不算拦路，
  只退提案；每次 `undoBatch` 先算完所有拦路项再动库，所以"撤不了"时事务根本没开。
- 退回待确认是把 `applied_at` 清空、`already_existed` **也一起清** —— 那句"它本来就有的"记的是上次点头
  那一刻的判断，撤回之后不再成立，留着会让再确认时读到一句过期的话。
- 两条纪律由测试钉住：① 撤了之后再确认，还是**同一条边**（边 id 就是提案 id 去掉前缀，幂等键没变）；
  ② 没确认过的一批，什么都不删、也什么都不退。
- 界面：对话框多一个「撤回这一批」→ 先问一句（说清"本来就有的行 / 卡片 / 标签 / 别的边一个字不动"）
  → 成绩单说清"删掉几个知识点、几条边、退回几条提案"；撤不了时整批没动，理由**照原样**摆出来
  （"这个知识点下面已经有卡片了，撤掉会连卡片一起删"），不给"那就撤一半吧"的选项。
- 数字：`test/data/repositories/material_intake_repository_test.dart` 10 → 20 例；材料页
  `test/features/cognitive/presentation/material_intake_page_test.dart` 15 → 17 例（新增两条：
  撤掉这次新建的、撤不掉时一条也不删）；全量 `flutter test --concurrency=1` → `+1898 ~2: All tests passed!`
  （轮次七十八是 `+1886 ~2`，差值 12）。

**还没做**：① 撤销**不记账**——库里没有"这批是什么时候撤的"，`applied_at` 清空是唯一痕迹
—— **已在轮次八十二补上，见切片 6 的下一步（十九）**（改记流水：`material_intake_undo_logs`，
撤成与没撤成都留一笔）；② 撤销不进审计（`review_logs` 之类），所以"确认过又反悔"这件事在历史里
看不到 —— **已部分补上（轮次八十二：进了自家的撤回流水，仍不进 `review_logs`）**；③ 谁来决定
"这份请求（`run/1`）可以执行了"—— 执行层仍然**没有调用者**（上一节 ①）—— **已在轮次八十五补上调用者，仍缺"判断者"**；**轮次八十七起这条演练在照片报告里也按得到（只读、仍不落库）**；**轮次八十八起，贴一份 `run/1` 进来也能先校验、再试跑（同一个只读演练、同样不落库）**；④ `ls` 仍没有标定
来源（§3 第 7 行）。

### 切片 6 的下一步（十七）：落不了的连接看得见 —— 点头之前就知道（轮次八十）

为什么要有它：上一轮的"撤回"回答的是"点错了怎么办"，这一轮回答更早的那一步 —— **别白点**。
"这条连接落不了"（有一端不在图里）以前只有确认**之后**的成绩单才会说（"N 条连接落不了"），
那时用户已经按过一次；更别扭的是这种连接**永远不会进历史**（它没被写下去），所以"哪几条是这次
落不了的"在界面上根本没有地方看。这一轮把这句话放回它该在的地方：**待确认清单**上逐条标出来。

- **判据是一处，不是两处**：`MaterialIntakeRepository.missingEndpointNote(...)`（起点 / 终点 / 两端
  三种说法）与 `noEndpointsNote`（提案自己没带端点）放在仓储层，界面与成绩单**共用** —— 同一件事
  不许说成两句不同的话。
- 读数是**现算的派生量，不落库**（`app/lib/features/cognitive/application/material_intake_reader.dart`
  的 `pendingMissingEndpointsOf` / `readPendingMissingEndpoints`）：它是"现在这一刻库里的样子"的函数 ——
  缺的那一端后来补进图里（本批的点被确认、或用户手建一个），这条连接就该能落；存下来就会变成一句
  过期的话（对比 `already_existed`：那句只在点头那一刻成立，所以它才必须落库）。
- **与确认时的判据逐条对齐**：① 两端都要在**影子图**里（库里已有的 `external_id` + 这一批的点提案
  将要送进去的 id —— 同一次 `apply` 先点后边）；② 边**已经在库里**的不算落不了（确认时会说"已存在"）；
  ③ 点提案里"同名已存在"（`exists`）的**不算数**（`_createPoint` 对它不写行，它的 `external_id`
  也就不会出现在库里）。三条不一致都会让界面说一句确认时不会应验的话。
- **跟着勾选变**：算的是"现在勾着的这些"，因为 `apply` 也只收到勾着的那些 —— 把一端取消勾选，
  连着的边**当场**喊缺（`_missingNow` 在勾选框变化时重算），不用等成绩单。
- 界面：提案卡片上多一行（`Icons.link_off` + "这条现在落不了：<缺哪一端>（先让缺的那一端进图）"）；
  确认之后这行还在（它说的事已经写在成绩单上了），直到那一端真的进图。

证据：新 `app/test/features/cognitive/application/material_intake_reader_test.dart` **14 例**（10 例纯函数：
三种缺法、"同名已存在"不算、没有 `nodeId` 不算、边已在库里不算、提案自己缺端点、知识点不在这张单子上、
本批的点算数；4 例真写库：还没确认就读得到、确认之后那把话与成绩单一致、缺的一端补进图里之后这句话
**自己消失并且真的落得下去**、两端都在本批时确认前不喊缺且确认后真落下去）；材料页
`app/test/features/cognitive/presentation/material_intake_page_test.dart` 17 → **18 例**（新增"缺的那一端
补进图里之后，这句话自己消失"，并在"确认一部分"那一例里钉住 `link_off` 0 → 2 → 2 个）；
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）；
全量 `flutter test --concurrency=1` → `+1913 ~2: All tests passed!`（轮次七十九是 `+1898 ~2`，差值 15）。

**还没做**：① 谁来决定"这份请求（`run/1`）可以执行了"—— 执行层仍然**没有调用者**（轮次七十八 ①）—— **已在轮次八十五补上调用者（只读工具的 `execute`），"判断者"仍缺**；**轮次八十七起这条演练在照片报告里也按得到（只读、仍不落库）**；**轮次八十八起，贴一份 `run/1` 进来也能先校验、再试跑（同一个只读演练、同样不落库）**；
② 执行完怎么落库（`knowledge_points` / `knowledge_edges` 的写入路径）；③ 撤销**不记账**、也不进审计
（**已在轮次八十二补上自家的撤回流水，见切片 6 的下一步（十九）**；`review_logs` 仍然不进）
（轮次七十九 ①②）；④ `ls` 仍没有标定来源（§3 第 7 行那六条实验，需要外部数据）。

### 切片 6 的下一步（十八）：照片读完能原地再来一张 —— 报告里就有「换一张」（轮次八十一）

为什么要有它：照片这条路从轮次七十七起就有按钮和报告对话框了，可报告是**死胡同** —— 读不成、
或者读成了但用户想换一张，只能先「关闭」，再回到页面上找那个「选一张照片」（轮次七十六 ② 那句
"现在读不成只能出去再按一次"说的就是它）。这一轮把这一步挪进报告里。

- 报告对话框多一个动作：**读成了 →「换一张」；没读成 →「重试」**（同一个按钮，两句话 ——
  成功和失败时用户心里的词不一样）。按下去就关掉这个对话框、重新选照片、重新读一遍，
  第二张的报告还摆在原来那个位置。
- **"模型都没配好"这一种不摆这个按钮**（`PhotoTranscribeProblem.notConfigured`）：按一次还是
  同一句话（那张对话框里已经说了"先去 AI 设置里配好模型"），摆着只会让人白按一下。
- 照片这条路仍然**只读**：不执行 `run/1`、不写库 —— 换十张也一样（测试里两次读完仍然是空的
  `knowledge_edges` / `material_intake_proposals`）。
- 对话框本身还是纯报告（`onAnother` 为空时没有这个按钮），"执行"仍然不是它的事 —— 要执行得
  先把这份请求拿去走 `run/1`（轮次七十八 ① 那个"调用者"还没定）。

证据：`app/test/features/cognitive/presentation/material_intake_page_test.dart` 18 → **20 例**
（"换一张"按下之后真的再选、再发一次、报告换新，并且两次都一个字没写库；"重试"从读不成到读成的
第二次算数 —— 摆的是第二张的结果，失败那句消失）；另外把"没配模型"那一例钉住"没有重试按钮"。
`dart format` 本轮文件 2 changed（改完 0 changed）；`dart analyze lib test` → `94 issues found`
（**0 error / 0 warning**）；全量 `flutter test --concurrency=1` → `+1915 ~2: All tests passed!`
（轮次八十是 `+1913 ~2`，差值 2）。

**还没做**：① 谁来决定"这份请求（`run/1`）可以执行了"—— 执行层仍然**没有调用者**（轮次七十八 ①）—— **已在轮次八十五补上调用者（只读工具的 `execute`），"判断者"仍缺**；**轮次八十七起这条演练在照片报告里也按得到（只读、仍不落库）**；**轮次八十八起，贴一份 `run/1` 进来也能先校验、再试跑（同一个只读演练、同样不落库）**；
② 执行完怎么落库（`knowledge_points` / `knowledge_edges` 的写入路径）；③ 撤销**不记账**、也不进审计
（**已在轮次八十二补上自家的撤回流水，见切片 6 的下一步（十九）**；`review_logs` 仍然不进）
（轮次七十九 ①②）；④ `ls` 仍没有标定来源（§3 第 7 行那六条实验，需要外部数据）。

### 切片 6 的下一步（十九）：撤过就有痕迹 —— 撤回记账（轮次八十二）

为什么要有它：轮次七十九的「撤销一次确认」把行删了、把 `applied_at` 清空 —— 这是它**唯一**留下的
痕迹。于是"这批怎么又回到待确认里了"在库里查不出来：可能压根没确认过，也可能确认过又反悔了，
两种情况的库长得一模一样。轮次七十九把这件事记成了「还没做 ① 撤销不记账」，这一轮补上。

- schema **v20** 新表 `material_intake_undo_logs`（drift `MaterialIntakeUndoLogs`，
  `@DataClassName('MaterialIntakeUndoLogRow')`）：`id` 自增 / `batchId` / `requestedAt`（毫秒）/
  `undone`（撤成了没有）/ `removedPointsJson` / `removedEdgesJson` / `restoredCount` /
  `blockedCount` / `blockedReason`（可空）。迁移 `_upgradeV19ToV20` 与其余迁移同形：先
  `_tableExists` 再 `createTable`，重跑不炸。
- **撤成了记一笔，没撤成也记一笔**：撤不掉时 `undone = false`、`removed*` 为空、
  `blockedCount` 与第一条理由（`blocked.first.reason`）留下 —— "点了撤回但库里一个字没动"同样是
  发生过的事，只记成功那一半会让"为什么没变化"变成第二桩查不出来的事。
- **记成流水（一次一行），不记成状态列**：同一批可以撤很多次（撤了 → 再确认 → 再撤），状态列
  说不清次数；"这批撤过没有"要从流水数出来，而不是再养一个会过期的派生量（对比
  `already_existed`：那句判断只在"上一次点头"那一刻成立，所以必须落库）。
- 写的地方只有一个：`MaterialIntakeRepository.undoBatch` 自己（与删除同一个事务；撤不掉那条路径
  在事务外补记一行）—— 页面不写，只读。读接口 `undoLogs(batchId)` 按 `requestedAt` 升序、同毫秒
  再按自增 id 排，所以它是一条**时间线**。
- 界面：从清单恢复 / 刚预览一批 / 清空之后再恢复时都顺手读一次这一批的流水数，`> 0` 就在提案清单
  上面多一行（`l10n.materialIntakeUndoLogLine(n)`：「这一批撤回过 N 次」）；撤回成功的那一次当场
  +1（那批正开在屏幕上，不用出去再进来）。**这些行不进历史那张单子**（历史说的是"确认完的批次"），
  而是跟那一批的提案待在一起 —— 将来能接着确认，才需要知道"它被撤过"。
- 明确不做：`blocked` 的每条理由都存（只存第一条；完整的理由列表在下一次点撤回时照样会说）、
  不进 `review_logs`（撤回不是一次复习，混进去会把记忆层的读数带脏）、不做"撤销的撤销"。

证据：`app/test/data/repositories/material_intake_repository_test.dart` 20 → **25 例**（撤成的把删了
什么记全 / 没撤成也记一笔且库一个字没动 / 撤两次记两行 / 没确认过的批次也留一行 / 同一毫秒按写入
次序排）；`app/test/features/cognitive/presentation/material_intake_page_test.dart` 20 → **21 例**
（撤回之后那行出现、清空后消失、从清单恢复又跟着回来）。`dart format` 本轮文件 3 changed（改完
0 changed）；`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）；全量
`flutter test --concurrency=1` → `+1921 ~2`（轮次八十一 `+1915 ~2`，差值 6）。

**还没做**：① 谁来决定"这份请求（`run/1`）可以执行了"—— 执行层仍然**没有调用者**（轮次七十八 ①）—— **已在轮次八十五补上调用者（只读工具的 `execute`），"判断者"仍缺**；**轮次八十七起这条演练在照片报告里也按得到（只读、仍不落库）**；**轮次八十八起，贴一份 `run/1` 进来也能先校验、再试跑（同一个只读演练、同样不落库）**；
② 执行完怎么落库（`knowledge_points` / `knowledge_edges` 的写入路径）；③ 撤回流水只有"撤过几次"
这一行，还没有点开看"那次撤掉了什么、为什么没撤成"的入口（**已在轮次八十三补上，见切片 6 的
下一步（二十）**）；④ `ls` 仍没有标定来源（§3 第 7 行那六条实验，需要外部数据）。

### 切片 6 的下一步（二十）：撤回流水点得开 —— 那一次撤掉了什么、为什么没撤成（轮次八十三）

为什么要有它：轮次八十二把"撤过"记成了流水，但界面上只有一行"这一批撤回过 N 次"—— 这行字说的是
**有**这回事，看不出**是哪回事**。而流水落库时记下的恰恰是那两样东西：撤成的记了删掉哪些行，没撤成的
记了第一条理由。这一轮把那一行变成入口，把已经躺在库里的东西摆出来（**只读，不新增任何落库**）。

- 点那行开一个只读对话框（`_showUndoLogs()`，`app/lib/features/cognitive/presentation/material_intake_page.dart`）：
  每次撤回一张 `ListTile`，倒序（新的在上）、时刻 `MM-dd HH:mm` + 「撤成了」/「没撤成」，
  `Icons.undo` / `Icons.block` 各对一半。
- 撤成那次摆出**原件原话**：`· <知识点标题>`（`MaterialAppliedPoint.title`）与
  `· <fromId> → <toId>`（`MaterialAppliedEdge` 的两端）—— 都是撤回那一刻从库里读出来的行内容，
  所以"那次到底删了什么"不靠回忆；没有自己新建的行时照实说"这一批没有自己新建的行"。
- 没撤成那次摆"为什么"：`没能撤：<第一条理由>（当时 N 条理由）`。**只有第一条理由落库**（轮次八十二
  的明确不做），`N` 也是那时数出来的，所以这里说得出"当时一共几条"、说不出每一条 —— 完整清单在
  下一次点撤回时照样会逐条给。
- 流水**不是回放**：对话框只读，关掉之后这一批仍然是"待确认"（`applied_at` 照旧为空），
  不会因为"看得见"就把行变回来。
- l10n 5 个新键（zh/en 的 ARB + 手改三个生成文件）：`materialIntakeUndoLogTitle`
  （撤回流水）、`materialIntakeUndoLogNote`（说清撤成了记什么、没撤成记什么）、
  `materialIntakeUndoLogDone`（撤成了）、`materialIntakeUndoLogNotDone`（没撤成）、
  `materialIntakeUndoLogBlocked(reason, count)`。
- 明确不做：不做"撤销的撤销"（看流水不改流水）、不把完整理由列表存进流水、不进 `review_logs`。

证据：`app/test/features/cognitive/presentation/material_intake_page_test.dart` 21 → **22 例**
（撤过之后那行点开看得见"删掉了什么"（2 个知识点 + 2 条边）与`已撤回：…`一行、看完仍是待确认、
清空再恢复那行还在；没撤成那次点开看得见理由与"当时 N 条理由"，卡片挪走后再撤一次成功 ——
两次都在这批的流水里）；`dart format` 本轮文件 1 changed（改完 0 changed）；
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）；全量
`flutter test --concurrency=1` → `+1922 ~2`（轮次八十二 `+1921 ~2`，差值 1）。

**还没做**：① 执行层（`run_executor.dart`）仍然没有调用者 —— **已在轮次八十五补上调用者（`check_transcribe_run` 的 `execute`），"判断者"仍缺**；**轮次八十七起这条演练在照片报告里也按得到（只读、仍不落库）**；**轮次八十八起，贴一份 `run/1` 进来也能先校验、再试跑（同一个只读演练、同样不落库）**；② 执行完怎么落库；③ `ls` 仍没有标定来源
（§3 第 7 行那六条实验，需要外部数据）。

### 切片 6 的下一步（二十一）：机制面板 —— 引擎装了哪些机制、每个参数是多少、哪些还没标定（轮次八十四）

为什么要有它：这台机器有一条硬规矩 —— **所有算法参数对用户公开**（`docs/DESIGN_BLUEPRINT.md` 的
P5；也是 roadmap §3 第 8 行「机制插件化」里"用户侧"的那一半）。而在这一轮之前，"引擎装了哪些机制、
每个数字是多少、哪些是未标定的占位值"只活在 `app/lib/domain/services/cognitive/fast_engine.dart`
的转录表里：用户能看见"发展区/瓶颈"这些结论，却看不见产生它们的那些数。诚实是这台机器的立身之本，
看不见的诚实不算数。

- 装配的事实**收成一处**：`app/lib/domain/services/cognitive/mechanism_catalog.dart` ——
  `library_diagnosis` 装四个机制（`dynamics.shunting` / `attention.capacity` / `attention.ignition` /
  `context.goal`），`problem_evaluator` 多装一层 `memory.dsr`；两处唯一的覆盖是
  `attention.ignition.T_ign = 0`（D3 去随机源：点火退化成硬阈值，不掷随机数）。`library_diagnosis.dart`
  与 `problem_evaluator.dart` 原先各写一份 id 清单与覆盖 map，现在都读这份常量 —— 面板因此
  **不可能**和引擎说的不一样（"面板"这类页面的老毛病就是抄一份，然后漂移）。
- 读数：`app/lib/features/cognitive/application/mechanism_reader.dart` 的
  `readMechanismPanel({moduleDefaults})`，**纯函数、不碰数据库**。`value` = 覆盖 >
  `module_defaults` > 转录默认值；`transcribed` 必须用**空 defaults 单独读一遍** `FastMechanisms`
  （`fromModuleDefaults` 会把传进来的默认值写进 `FastParamSpec.defaultValue`，那一份读到的就已经
  不是"转录"了 —— 这是写测试时才发现的）。
- 页面：`app/lib/features/cognitive/presentation/mechanism_page.dart`，入口在
  `cognitive_model_page.dart` 的 AppBar（`Icons.tune`）。两段装配卡 + 六段机制卡：内核 id
  （`attention.capacity` 这种写法）+ 界面名 + "装在哪"（或"只在节律读数里"）+ 每个参数一行
  （路径、值、**未标定**/已标定、被覆盖时另给转录默认值、范围、`desc` 与 `evidence` 原话），
  末尾一句总数"`{params} 个参数，其中 {uncalibrated} 个未标定`"。
- 两条**如实说**（这一轮特意钉住的）：`rhythm.gate` 只活在节律读数里（`StudyRhythm.read` 直接建
  `RhythmGate`），**不装进任何引擎**，所以面板不说它"装了"；`memory.dsr` **一个号参数都没有**
  （它只维护每个节点的状态袋 `node.m['memory_dsr']`），面板不空着、也不编参数。
- **只读**这一轮是刻意的：这一页不写库、没有开关。"用户侧开关/滑块"（§3 第 8 行）要先把开关落库
  （settings 列 + schema 迁移）并配一条可跑的验收契约，是另一轮的事 —— **轮次八十六做了这件事：
  面板多了目标机制开关（schema v21 `local_settings.goal_mechanism_enabled`），于是这一页不再是
  纯只读的**。

证据：`app/test/features/cognitive/application/mechanism_reader_test.dart` 10 例（面板列出的机制与
参数逐条等于 `FastMechanisms` 的转录表、未标定个数与引擎同口径、两处装配的 id 清单、`T_ign` 值 `0`
而转录 `0.05`、别的参数没被覆盖、`rhythm.gate` 不装进任何引擎、`memory.dsr` 没有号参数、
`module_defaults` 传值时实际值变而转录默认值不变）；`app/test/features/cognitive/presentation/mechanism_page_test.dart`
7 例（两处装配 + 六个机制名、点火阈值那行、记忆层那段、节律闸门那段、末尾总数与读数一致、
"已标定"也出现、id 用内核写法）；`flutter test test/domain/services/cognitive/ test/features/cognitive/`
→ `+337`；`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）；`dart format` 本轮
11 个 Dart 文件 4 changed（改完 0 changed）；全量 `flutter test --concurrency=1` → `+1939 ~2`（轮次八十三 `+1922 ~2`，差值 17）。

**还没做**：① 执行层（`run_executor.dart`）仍然没有调用者 —— **已在轮次八十五补上调用者（`check_transcribe_run` 的 `execute`），"判断者"仍缺**；**轮次八十七起这条演练在照片报告里也按得到（只读、仍不落库）**；**轮次八十八起，贴一份 `run/1` 进来也能先校验、再试跑（同一个只读演练、同样不落库）**；② 执行完怎么落库；③ `ls` 仍没有标定
来源（§3 第 7 行那六条实验，需要外部数据）；④ 机制面板只有读，没有"用户侧开关/滑块"（§3 第 8 行
的另一半，要落库 + 验收契约）—— **已在轮次八十六补上第一个开关（目标机制，落库 + 验收契约都在），
并在轮次八十九补上第一个滑块（`context.goal.beta_goal`，schema v22，同样落库 + 验收契约）**。

### 切片 6 的下一步（二十二）：演练 —— 那份 `run/1` 请求真的跑进引擎（轮次八十五）

为什么要有它：`run_executor.dart`（轮次七十八）把"请求 → 引擎"这条路修到了头，但从那天起它
**没有调用者**——"谁来决定这份请求可以执行了"一直挂在"还没做"①上。这一轮不做那个判断（那是
设计问题），而是先回答它下面那半句更小的：**谁去装配那个引擎**。答案用的是已经存在的只读工具
`check_transcribe_run`：它原本只校验，现在多一个 `execute` 参数，给了就顺手把请求真的跑一遍。

- 新层 `app/lib/features/cognitive/application/run_rehearsal.dart`：
  `rehearseRun({request, db, model, now, anchor})` → `RunRehearsal{report, seedNodeIds,
  seedEdgeIds, nodesWithoutMs, unknownNodeIds}`，`report` 就是 `executeRun` 的报告。
- **图先摆好**：请求提到的节点（`review`/`exposure` 的 node、`goal` 的 starts/targets、边提到
  的那两端）按请求自己的 id 空间（`kp-…`/`en::s::…`）摆进仿真图，节点 `ms` 用库里那张代表卡片的
  模型读数（`representativeCardRow` + `CognitiveModel.modelReadingOf(row, nowHours:).r0`）——
  和库诊断同一个来源；读不出来就**省略**（引擎按 0.8），并记进 `nodesWithoutMs`，不替它编数。
  请求自己会建的节点（`knowledge` 动作）**不先摆**：重复建同一个 id 会抛，那是真实行为，让执行
  报告如实报出来，演练不去替它掩盖。
- **边也摆好**：`knowledge_edges` 里两端都已经进图的那些边才接过来（一端不在，那条边在演练里也
  走不通）。
- **只装记忆层**：`executeRun` 只 apply 动作、不跑轮次，逐轮那四个机制一个也用不上，所以
  `MechanismCatalog.runRehearsalIds = [memory.dsr]` —— 机制面板因此如实多列一处装配
  （三处：库诊断四个机制 / 测评五个 / 演练只装记忆层）。
- **只跑不落库**（刻意）：`knowledge_points` / `knowledge_edges` / `card_states` / 记忆态一个字都不
  动。把演练结果落库是另一件事（还没做②）。
- 诚实的边界写进 library doc：库里的复习历史**没有**变成记忆袋（仿真图上的袋子从默认状态起算，
  `ms` 只决定节点自己的读数起点），所以演练回答的是"这份请求会落在哪条机制路径上、动到哪些数"，
  不是"你的真实进度会变成多少"。
- 工具那一侧（`app/lib/features/ai/tools/ingest_tools.dart` 的 `CheckTranscribeRunTool`）：`execute`
  缺省 `false`（结果里只有原来那份校验 + 一句"要真的跑一遍，给 `execute: true`"）；给了才跑，结果
  多一个 `rehearsal` 对象（`report` + 图里摆了什么 + 哪些节点没有 `ms` + 哪些节点库里没有），
  `ok` 跟执行报告的 `ok` 走，`error` 用停在的那条动作的原话（比如 `review` 没给 `at`
  就是"缺少时间基…"）。工具因此从"校验器"变成"校验 + 演练"，仍然**只读**。
- 入口：`ToolRegistry.forApp` 把 `db`/`model`/`clock` 一起传进这个工具（`app/lib/features/ai/domain/tool_registry.dart`）。

证据：`app/test/features/cognitive/application/run_rehearsal_test.dart` **12 例**（先建后复习时
`changedCount 2` 而 `touchedMechanisms 1`、没有卡片就省略 `ms` 并记进 `nodesWithoutMs`、
边两端都在才接过来、请求自己的 `time.model_hours` 就是锚点、只给 `at.wall` 没有锚点就如实停在
第一条、"没有模型读数就当无效"（校验层的事，执行层只活到第一条）、演练不写库）；
`app/test/features/ai/check_transcribe_run_tool_test.dart` 8 → **11 例**（不给 `execute` 就不会有
`rehearsal` 键、给了就真跑且库不动、空库时第一条就停在 `unknown_node_ids`）；
`app/test/features/cognitive/presentation/mechanism_page_test.dart` **7 例**（三处装配的 id 清单与
名字）。三个文件合跑 `+30`；`dart format` 本轮 11 个 Dart 文件 2 changed（改完 0 changed）；
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）；全量
`flutter test --concurrency=1` → `+1954 ~2`（轮次八十四 `+1939 ~2`，差值 15）。

**还没做**：① 谁来决定"这份请求可以执行了"—— 现在有调用者了，但**不是判断者**：`execute` 是用户
在对话里给的参数，没有任何一层替用户下"这批复习可以执行"的结论；② 执行完怎么落库（演练刻意不写，
包括记忆袋）；③ `ls` 仍没有标定来源（§3 第 7 行那六条实验，需要外部数据）；④ 机制面板只有读，
没有"用户侧开关/滑块" —— **已在轮次八十六补上第一个开关（目标机制），轮次八十九补上第一个滑块
（`context.goal.beta_goal`）；别的机制的开关语义与其余参数的滑块仍没做**。

### 切片 6 的下一步（二十三）：机制开关 —— 用户说"不装目标机制"，引擎就真的不装（轮次八十六）

为什么要有它：机制面板（轮次八十四）把"引擎装了哪些机制"公开了，但它是**只读**的 ——
"可插拔"只有一半。§3 第 8 行要的另一半是"用户侧开关/滑块"。第一个开关选**库诊断那一跑装不装
目标机制**（`context.goal`），理由是这一处关掉之后读数仍然是读数：那一跑的起点和目标是用户给的，
没有目标机制就只是"拉不过去"，而不是把整份诊断变成假话。别的三个机制（分流/容量/点火）撑着那一
跑本身，关掉它们等于让读数撒谎 —— 那不是选择，是坏掉。所以这一轮只公开一个开关，且只作用于**一处
装配**：题目定价那一跑仍然装它（那一路要用起点/目标定价）。

- **落库**：`local_settings.goal_mechanism_enabled`（可空 bool），schema **v21**。**NULL = 用户
  从没选过 = 装** —— 这个开关出现之前所有版本都是这么跑的，升级不能顺着迁移替用户把引擎换掉。
  与 `rhythm_hints_enabled` 同一条规矩：`_upgradeV20ToV21` 只加列，`_ensureColumns` 负责
  "版本号跑在列前面"的自愈。
- **一个来源**：`MechanismCatalog.libraryDiagnosisIdsFor({required bool goalEnabled})` 是唯一
  的算法（开关关掉只去掉 `context.goal`，别的机制一个不动）；`LibraryDiagnosisRunner.run()` 多了
  `goalMechanismEnabled`，把**这一次真的装了哪几个**写进读数 `mechanismIds` 与 JSON 的
  `mechanism_ids`。没跑起来的那两次（没有图 / 没有可用起点）写**空清单**，不是"装了默认的"。
- **读数自己说得清**：`readLibraryDiagnosis` 自己读设置（页面 provider 与 AI 工具走同一条路，
  不会有人忘了传）；`readMechanismPanel(goalMechanismEnabled:)` 给每个机制行加了
  `disabledIn` / `disabledBySetting`，把"你关掉了（出厂会装）"和"本来就没装"分开说 ——
  开关打开时这份清单必须是**空的**（这一条抓到一个真 bug：读数忘了把开关传进
  `setupsDisabledBySetting`，于是开关开着时卡片仍然声称"你关掉了"）。
- **面板能翻**：`mechanism_page.dart` 从无状态变 `ConsumerStatefulWidget`，读数走
  `mechanismPanelProvider`、开关值走 `goalMechanismEnabledProvider`；翻一下只写这一行设置，
  然后 invalidate 两个 provider。用户刚翻的值先用 `_picked` 画出来（写库是一次往返，开关不能自己
  弹回去）。原来那句"面板只读"改成"面板只写这一个开关，不写别的表"。
- **两句话都要说**：目标机制仍然装在题目定价那一跑里，所以卡片既写"装在哪几处"，也另起一行写
  "你关掉了 · 库诊断那一跑" —— 只写前半句，用户翻开关时看不到自己拿掉了什么。

证据：`app/test/data/database/v21_migration_test.dart` **2 例**（真实 v20 文件升级后老设置一行不少、
新列落成 NULL，用户选了之后两个方向都写得进去；被盖成 v21 却缺列的文件靠 `beforeOpen` 自愈）；
`app/test/domain/services/cognitive/library_diagnosis_test.dart` **+4 例**（默认装、关掉后这次跑真的
没装、JSON 里也写着 `mechanism_ids`、没跑的两次是空清单）；
`app/test/features/cognitive/application/mechanism_reader_test.dart` 12 → **16 例**（关掉之后库诊断
那一跑少一个而别的装配一处不改、目标机制那一段只说库诊断那一处、没被关掉的不许乱标、参数一个不
少）；`app/test/features/cognitive/application/library_diagnosis_reader_test.dart` **+3 例**（NULL 读作
装、关掉之后同一次读里清单就变了、页面 provider 与工具逐字段一致）；
`app/test/features/cognitive/presentation/mechanism_page_test.dart` 7 → **11 例**（默认画成装并写清
关掉会变什么、关掉后那一跑只写 3 个机制且卡片说"你关掉了"、翻一下回调收到新值且当场按新值画、
**翻开关真的落库**（真 sqlite：`local_settings` 写成 false、面板重读后只剩 3 个机制））。
本轮 `dart format` 16 个 Dart 文件 2 changed（改完 0 changed）；`dart analyze lib test` →
`94 issues found`（**0 error / 0 warning**）；全量 `flutter test --concurrency=1` → **+1971 ~2**
（轮次八十五 `+1954 ~2`，差值 17）。

**还没做**：① 谁来决定"这份请求可以执行了"（同上一轮，判断者仍缺）；② 执行完怎么落库；③ `ls` 仍
没有标定来源（§3 第 7 行那六条实验，需要外部数据）；④ "用户侧开关/滑块"只做了**一个**开关（目标
机制）—— 别的机制还没有开关语义（分流/容量/点火撑着那一跑本身，关掉就是让读数撒谎），滑块
（连续参数的用户侧调节）当时也还没有设计 —— **这个缺口已在轮次八十九补上第一个滑块
（`context.goal.beta_goal`）**。

### 切片 6 的下一步（二十四）：照片报告里「试跑一遍」—— 演练从工具走到界面（轮次八十七）

为什么要有它：演练层（轮次八十五）把"谁去装配引擎"答了，可它只有**一个入口**：AI 工具
`check_transcribe_run` 的 `execute`。用户手上那份"刚拍下来的 `run/1`"反而看不到它会怎么跑 ——
界面上读完照片只看得到"合不合法"。这一轮把两件事接起来：**合法的那一份，报告里按一下就能真的
走一遍**，走的还是 `rehearseRun` 那条只读的路。

- **原件随报告走**：`PhotoTranscribeReport` 多了 `request`（解码出来的那份）。
  带上它不是为了好看：界面要拿它去试跑，而唯一的正确来源是解码器 —— 让界面把 `rawText`
  再解一遍就是两处解析、两份真相（`D2`）。
- **按一下只跑不写**：`runRehearsalRunnerProvider` 是"怎么跑"这件事的接缝（真实现 = 同一个库、
  同一个 `CognitiveModel`），报告里就地把读数摆开，不另开对话框：引擎对**每条动作的原话**
  （`RunActionTrace.text`）一行一条、`nodesWithoutMs`（库里读不出 `r0`、引擎按 0.8 算的节点）与
  `unknownNodeIds`（库里没有、也没动作去建的 id）各一行，外加一句"只读演练：不写知识点、不写边、
  不动复习记录"。
- **失败不带走报告**：试跑抛了就说人话（原话留着），自检结果照旧在屏幕上、按钮还能再按 ——
  "这份请求合不合法"和"引擎跑不跑得完"是两件事，前者不该被后者擦掉。
- **不合法就不摆按钮**：自检没过的请求没有试跑入口（跑它没有意义）。这也让"能按"本身成了一种
  读数：按钮在 = 这份请求在引擎眼里是活的。

证据：`app/test/features/cognitive/presentation/material_intake_page_test.dart` 22 → **25 例**
（真的跑进引擎且库一个字节都没变、模型读不出 `r0` 的节点要明说、试跑炸了报告还在、不合法的
那份不摆按钮）；`app/test/features/cognitive/application/photo_transcribe_service_test.dart`
（12 例不变）里"读成一份请求"那条多钉一句：报告里带着解码出来的 `request`。
本轮 `dart format` 7 个 Dart 文件 0 changed；`dart analyze lib test` → `94 issues found`
（**0 error / 0 warning**）；全量 `flutter test --concurrency=1` → **+1974 ~2**（轮次八十六
`+1971 ~2`，差值 3）。

**还没做**：① 谁来决定"这份请求可以执行了"（判断者仍缺：现在按按钮的仍是人）；② 执行完怎么落库；
③ `ls` 仍没有标定来源（§3 第 7 行那六条实验，需要外部数据）；④ "用户侧开关/滑块"只做了一个开关
（目标机制），滑块**已在轮次八十九补上第一个（`context.goal.beta_goal`）**；⑤ 演练只接进了**照片**
这一条路 —— 贴信封那条路还看不到"这份信封跑起来
会怎样"，报告里也还不能改一改再跑（要改就得回去改原话）。

### 切片 6 的下一步（二十五）：`run/1` 也能贴进来 —— 同一条只读路，第二个入口（轮次八十八）

为什么要有它：轮次八十七把演练接进了照片那条路，可 `run/1` 请求**不是照片的专属产物** —— AI 工具
`check_transcribe_run` 会产、别处的模型会话会产、用户自己也可能手写一份。这些请求在界面上没有落脚处：
"先校验，再试跑"藏在照相机后面。这一轮给材料摄取页加了第二条只读入口：**把一份 `mindnet.run/1`
贴进去**，校验与试跑走的还是同一套（`reviewTranscribedRun` / `rehearseRun`），一个字都不写库。

- **两个入口，一套判定**：`_RunRequestDialog`（`material_intake_page.dart`）只做三件事 —— 贴文本、
  按"校验这份请求"、合法就按"试跑一遍"。解码 `decodeRunRequest(extractJsonObject(text))`、自检
  `reviewTranscribedRun(request, existingNodeIds:, existingEdgeIds:)`，与照片那条路**同函数同口径**：
  两条路的差别只是"请求从哪来"，不是"怎么判"（`D2`）。
- **图清单照旧从库里现读**：按按钮时先读 `graphPoints()`/`all()` 拿"已有的节点/边 id"——"这条动作说的
  id 库里有没有"必须按真实的图判；读不出来就说人话（新键 `materialIntakeRunGraphFailed`）。
- **读不成 vs 不合法，分开说**：`FormatException` 是读不成（摆解码器那句人话、没有试跑按钮）；
  读得成但不合法是硬错（照摆 `errors`，也没有按钮）—— 先修它，别急着跑。
- **只读的按钮在不在，本身是读数**：与照片那条路一致，`report.ok` 才有"试跑一遍"；跑的是同一个
  `runRehearsalRunnerProvider` 接缝（测试注入真 `rehearseRun`）。
- **一处改名**：`_notePhotoProblem` → `_noteIntakeProblem`（两条只读入口共用一行提示）。

证据：`app/test/features/cognitive/presentation/material_intake_page_test.dart` 25 → **28 例**
（贴一份合法请求 → 合法 + 会做什么 → 试跑真的进引擎且 `knowledge_edges`/`material_intake_proposals`
都空、`knowledge_points` 仍 1 条；贴"这不是信封" → 只说解码器那句、不给按钮；贴一份 `kind: unknown`
的请求 → 摆硬错、不给按钮）；6 个新 l10n 键（zh/en + 三个生成文件手改）。本轮 `dart format` 5 个
Dart 文件 0 changed；`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）；全量
`flutter test --concurrency=1` → **+1977 ~2**（轮次八十七 `+1974 ~2`，差值 3）。

**还没做**：① 谁来决定"这份请求可以执行了"（判断者仍缺：现在按按钮的仍是人）；② 执行完怎么落库；
③ `ls` 仍没有标定来源（§3 第 7 行那六条实验，需要外部数据）；④ "用户侧开关/滑块"只做了一个开关
（目标机制），滑块**已在轮次八十九补上第一个（`context.goal.beta_goal`）**；⑤ **报告里不能"就地改一改再跑"**：贴进来的这一条可以改文本再校验一次，
照片那条路只能回去改模型原话 —— 没有结构化的字段级编辑入口。

### 切片 6 的下一步（二十六）：第一个滑块 —— 目标机制的牵引强度（轮次八十九）

为什么要有它：轮次八十六给了用户一个开关（装不装目标机制），可"装"只有两档。机制参数表里那 19 个
数字用户一个也碰不到 —— 面板只把"被覆盖/未标定"摆出来看。这一轮开了第一个**滑块**：
`context.goal.beta_goal`（目标偏置强度）用户可以拖；与开关一样只写一行设置、只在装配时生效，
**引擎真的读它**，读数里带得出来。

- **两端不是我们编的**：`FastParamSpec` 本来就带 `min`/`max`/`defaultValue`/`desc`/`evidence`。
  `beta_goal` = 默认 `0.3`、范围 `[0, 3]`、`desc: '目标偏置强度'`、`evidence: '未标定（Application_Protocol §15）'`
  —— 滑块的下界、上界、出厂位置全部来自内核参数表（`MechanismCatalog.goalBetaPath` / `goalBetaKey` /
  `transcribedGoalBeta`），页面不自己编一个"看起来合理"的区间。
- **NULL = 没调过**：`local_settings.goal_beta`（可空 REAL，schema v21 → **v22**）为 NULL 时读作"用转录
  默认值"。`_upgradeV21ToV22` 走与 v21 那列同一条链（`_addColumnIfMissing` + `_ensureColumns` 自愈）。
- **进引擎走本来就有的通道**：装配一直有 `moduleDefaults`（`overrides > moduleDefaults > 转录默认值`）。
  `MechanismCatalog.libraryDiagnosisDefaults(goalBeta: v)` 只在调过时给出 `{context.goal: {beta_goal: v}}`；
  库诊断那一跑（`LibraryDiagnosisRunner.run(moduleDefaults: …)`）真拿它装配，读数 `module_defaults`
  照实带出来（没调过、或那次没跑起来 → 空）。
- **面板说清三件事**：卡片上"你调的 1.2" + 「回到出厂值」（写回 NULL）；参数行徽标 `fromSetting`
  与 `overridden` **分开**（被装配覆盖 ≠ 被你调）；转录默认值那行不动。
- **开关与滑块互不干扰**：关掉机制 ≠ 抹掉你拖的值 —— 滑块禁用、位置保留，`OffNote` 明说"关的是装不装，
  不是值"。
- **只读边界没变**：这一轮加的是"引擎用哪个数字"，演练与诊断仍然一个字都不写库。

证据：`test/features/cognitive/presentation/mechanism_page_test.dart` 11 → **17 例**（出厂位置 0.3 / 两端
0 与 3 来自参数表；调过之后标"你调的"且转录默认值不变；拖一下只回调一次且页面当场按新值画；「回到
出厂值」回调收到 `null`；机制关掉时滑块禁用但位置保留；真库那条钉"拖了落库、写回 NULL"）；
`mechanism_reader_test.dart` +4；`test/domain/services/cognitive/library_diagnosis_test.dart` +4；
`test/features/cognitive/application/library_diagnosis_reader_test.dart` +3；新建
`app/test/data/database/v22_migration_test.dart` **2 例**（真 v21 文件升级后新列可用、老设置一行不少；
被盖成 v22 却没有这一列的文件靠自愈补上并能写进去）；6 个新 l10n 键（zh/en + 三个生成文件手改）。
`dart analyze lib test` → `94 issues found`（0 error / 0 warning）；全量 `flutter test --concurrency=1` →
**+1996 ~2**（轮次八十八 `+1977 ~2`，差值 19）。

**还没做**：① 谁来决定"这份请求可以执行了"（判断者仍缺）；② 执行完怎么落库；③ `ls` 仍没有标定来源
（§3 第 7 行那六条实验，需要外部数据）；④ 开关/滑块各只有一个（目标机制），其余 18 个参数还没有滑块
—— 而且滑块**不该**铺开：19 个参数里只有 2 个写着"有出处"，给用户一个没出处的旋钮与"面板如实说"
是同一件事的两面，先要的是标定；⑤ 报告里不能"就地改一改再跑"；⑥ 当时用户拖的这个数**只在库诊断那一跑
生效**，题目定价那一跑还没读设置 —— **已在轮次九十补上（一节之隔：27）**。

### 切片 6 的下一步（二十七）：用户拖的那个数，在装了目标机制的每一跑里都算数（轮次九十）

为什么要有它：轮次八十九把 `context.goal.beta_goal` 交给用户拖，可那个数只走到**库诊断那一跑**。
机制面板上明明写着目标机制装在**两处**（库诊断 + 题目定价），卡片上也写着"你调的 1.2" —— 于是同一页
上两句话同时成立就成了谎：题目定价那一跑（`evaluate_problem_fit` / `plan_today` 背后的
`ProblemEvaluator`）仍然用出厂 0.3 在算 `V(π)`。这一轮把"用户调的值"从一处接到"装了它的每一跑"，
并且让**读数**带出这一跑到底用了什么。

- **一条规则，不各写一份**：`MechanismCatalog.goalBetaDefaults({installedIds, moduleDefaults, goalBeta})`
  —— 只有 `installedIds` 里真的有 `context.goal` 时才补那一个键，否则原样返回。库诊断那一跑按
  `libraryDiagnosisIdsFor(goalEnabled:)`（开关管着）折；题目定价那一跑按 `problemEvaluatorIds` 折
  （它有开关以外的第二层意义：`Evaluator` 自己装什么由 `MechanismCatalog` 说了算）。**没有**给两个跑
  各留一个包装函数 —— 那正好是"同一件事两处实现"（`D2`）的老毛病。
- **工具层只有一处读设置**：`evaluateProblems`（`tools/cognitive_tools.dart`）是两个 §2-A 工具共用的
  装配，它自己 `SettingsRepository(database).getSettings()`、自己折，两个工具都把手上的 `AppDatabase`
  传进来（`EvaluateProblemFitTool` / `PlanTodayTool` 的构造多了 `required AppDatabase database`）。
  于是"一个用 0.3、一个用 1.2"这种漂移在结构上不可能。
- **读数要能验收**：`ProblemEvaluationReport` 多了 `moduleDefaults`（这一跑实际用的表，空 = 转录默认值
  一个字没动），`evaluate_problem_fit` 的 `modelResult['module_defaults']` 直接带出去；摘要里另加一句
  人话（`tunedParametersNote`）—— 数字一样要说清它是谁定的，否则模型会把用户调过的定价当出厂值。
  `plan_today` 的 `toJson` 是计划自己的协议，不动；那句人话照加。
- **关掉机制 = 这一跑连参数都没有**：用户把目标机制关掉后，库诊断那一跑折出来的表是空的（没装的机制
  不该有参数），但**用户拖的数字还留着**（设置没被抹掉，滑块禁用、位置保留）—— 两件事分开说。
- **面板上补一句"这一个数谁会读"**：`mechanismGoalBetaApplies` 写明库诊断那一跑与题目定价那一跑都读它、
  工具读数里的 `module_defaults` 就是它（没调过时是空的）。

**证据**：`app/test/features/ai/cognitive_tools_test.dart` +3 例（没调过 → `module_defaults` 为空且摘要
不多说一个字；调过 1.2 → 读数就是 `{'context.goal': {'beta_goal': 1.2}}` 且摘要写 `context.goal.beta_goal=1.2`；
**拖到 0 也算"调过"**，不算没调）；`app/test/features/ai/today_tools_test.dart` +1 例（`plan_today` 的摘要
也带出用户调过的参数）；`app/test/features/cognitive/application/library_diagnosis_reader_test.dart` +1 例
（机制关掉 + 拖过值 → 那一跑 `module_defaults` 为空、`mechanism_ids` 里没有 `context.goal`，而库里的值还在）；
`mechanism_page_test.dart` 那条滑块用例多钉一句"面板写着这一个数谁会读"；`library_diagnosis_test.dart`
两处改用 `goalBetaDefaults(installedIds: …)`（`libraryDiagnosisDefaults` 这个包装函数已删 —— 它默认
"目标机制一定装着"，正好是这一轮要堵的那种谎）。本轮 `dart format` 16 个 Dart 文件 1 changed；
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）；全量 `flutter test --concurrency=1` →
**+2001 ~2**（轮次八十九 `+1996 ~2`，差值 5：+3 +1 +1）。

**还没做**：① 谁来决定"这份请求可以执行了"（判断者仍缺：现在按按钮的仍是人）；② 执行完怎么落库；
③ `ls` 仍没有标定来源（§3 第 7 行那六条实验，需要外部数据）；④ 其余 18 个参数还没有滑块（而且滑块**不该**
铺开：19 个参数里只有 2 个写着"有出处"，先要的是标定，不是更多旋钮）；⑤ 报告里不能"就地改一改再跑"。

### 切片 4：测评层——抽象参数的先验来源（M1a–M1d，已完成 轮次二十三～二十五）

为什么要有它：MindNet 的 `R0`/`D` 在 Furnace 里一直只有两个来源——FSRS 存下来的观测值，或
`0.5` 的默认值；`fluency`（元认知信念的输入）**根本没有来源**（元认知层只好拿 `encodingStrength`
当代理，这正是切片 3 追加项失败的原因）。测评层给这三件事一个**用户自己产出的**起点。

- M1a（轮次二十三）：纯逻辑先验层 `assessment_prior.dart`——自评 + 答题结果 → 每知识点
  `R0`/`D`/`fluency` 先验 + 全局校准偏置 + 置信度。`calibrated: false` 一律保留。
- M1b（轮次二十三）：schema v10 三表（`assessment_sessions`/`assessment_responses`/`cognitive_priors`）
  + `AssessmentRepository` + v10 迁移单测。先验是**派生量**，`.tfpkg` 导入后按证据重算。
- M1c（轮次二十四）：最小 UI `app/lib/features/assessment/presentation/assessment_page.dart`——
  选范围 → 自评 → 复述抽检 → 读数；最后一步之前不写库，跳过＝不写行（不是写 0）。
- M1d（轮次二十五）：读数页合并展示——先验只改"还没复习过的卡"展示的起点 `R0`，旁边标"（测评先验）"；
  卡片一旦有自己的复习史，观测接管，先验不再说话。先验不写回 `card_states`、也不改 `ReviewAdvisory` 排序。
- 设计文档在 `docs/ASSESSMENT_DESIGN.md`（含分板块 instrument 表、同步三分类、明确不做清单）。
- 仍未做：板块化 instrument 的实现（物理/语文等各一套题目形态）、客观题的自动判分、
  以及用标定协议把这批先验的系数真正标出来（CALIBRATION §2）。

### 切片 4 的追加：M6 效果度量——"记忆效果好"从感觉变成两个数字（轮次二十六）

- 留存率（按距上次复习的间隔分桶）**对已有历史立刻可算**，不需要任何预测；判定"记得"只用复习结果，
  `fuzzy`/`Hard` 不算。
- 校准要求预测在判分之前落库：v11 给 `review_logs` 加 `predicted_r`（可空），复习流当场写，
  老行 NULL 且**历史不补算**——所以 Brier/ECE 从 v11 开始积累。这是"预测"与"事后重算"的分界线，
  也是这条路唯一能自证的地方：`review_service_test` 有一条断言钉住"预测与答对答错无关"。
- 读数页的"学习效果"卡片是全页唯一不读模型自己读数的块；没有预测样本时它说"还没有样本"，不画假设曲线。

