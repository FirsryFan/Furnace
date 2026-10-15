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
| **控制层 17 条指令库 + 反事实规划器** `V(π)=ΔR/cost`（分 `retention`/`reachability` 两种度量、克隆参数隔离、峰值驱动、曾点亮又回落单列） | MATH §7 | 输出"今天该做的练习清单"，按收益/成本排序 |
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
- **缺**：① INGEST 的 `mindnet.material/1`（材料 → 节点/边/记忆记录）；② `knowledge` 动作（新知识点、新连接）；
  ③ TRANSCRIBE 的"照片 → `run/1`"（含出处/置信度）；④ 资料与卡片的关联类型（线索边 vs 包含边，MEMORY_RECORD §3.5 已澄清语义差异）。
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
| 5 | **控制层指令库 + 反事实规划器排序** | 从"诊断"升级到"今天做这几件事" | 每月/每日计划输出按 `V(π)` 排序的练习清单，含 `retention/reachability` 度量标注 —— **`reachability` 侧已进入找题排序（轮次五十六：`evaluate_problem_fit` 的次序在同分档内按 `V(π)` 排，输出 `counterfactual{metric,instruction,value,why}` 与理由行"为什么排这里"）；`retention` 侧的记忆层与生产探针已就位（轮次五十七：`memory.dsr` 按需装进 `FastEngine`，`dsrRetentionProbe()` 读 `node.m['memory_dsr']`，默认不装所以轮次数值不变），并已传进 `FastPlanner.plan`（轮次五十八）**；还没做的是"今天做这几件事"的清单本身（把题目与闪存卡合成一个按 `V(π)` 排的日计划）** |
| 6 | **材料摄取（INGEST/TRANSCRIBE）** | 补资料→进图，照片→run/1 | 一份材料生成节点/边 + `evidence`；照片流程产出合法 `run/1` 并过 `io_check` 类校验 |
| 7 | **标定（CALIBRATION 六实验）+ 反馈微调（FEEDBACK）** | 个性化真正的来源，但要 1–6 的数据积累 | 6 个实验各自可跑、产出参数与置信说明；反馈更新律有界且可回滚 |
| 8 | **机制插件化（PLUGIN_ARCHITECTURE）** | 覆盖全面的长期结构 | 至少一个机制实现为可开关模块，用户侧有开关/滑块，验收契约可跑 |

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

