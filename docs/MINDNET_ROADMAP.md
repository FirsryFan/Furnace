# MindNet × Furnace 扩展路线图（2026-10-11）

> 起因：用户指出"认知模型的功能完全不止这一点点"，要求 Furnace 覆盖更广——
> 找题时有用、闪存卡时有用、给题目补资料时有用、给事件排序（Thread）时也有用。
> 本文件把 **MindNet 文档里已经存在** 的能力与 **Furnace 已接入** 的部分逐条对齐，给出缺口与落地顺序。
> MindNet 侧依据（只读）：`E:\Document\MindNet\docs\{IO_PROTOCOL,MODEL_v2_MATH,CALIBRATION,FEEDBACK,INGEST}.md`、
> `docs\archive\TRANSCRIBE.md`、`docs\PLUGIN_ARCHITECTURE.md`、`MEMORY_RECORD.md §3.5`。

## 0. 一句话现状

我们接进去的是：**tierA 记忆层（R/R0/Σ/S/D）+ tierB 快层（shunting/capacity/ignition/goal）+
卡点诊断与反事实可达性 + 顾问式排序（bands）+ 只读读数页/探针 + 用途 1 工具**。
没接进去的是：**`run/1` 会话协议的五类动作、节律层 α(τ)、元认知层（危险区/焦虑区/校准度）、
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
- **缺**：① 元认知**危险区优先**（把"以为会其实不会"的题排前面）；② 控制层 `expected_gain`/反事实 `V(π)` 真正参与排序（现在只到判定）；
  ③ 节律 α(τ) 决定"现在适合做难还是易"；④ 题目来源（组卷网 skill）与题源质量判据。
- **落点**：`problem_evaluator.dart` 增加危险区/焦虑区输入与 `retention|reachability` 双度量排序；AI 工具输出里带上"为什么排这里"。

### B. 闪存卡复习（趋势：把"评分"升级成"事件流"）

- **已有**：tierA 全量 + tierB 快层 + 四段 bands + forced 重来 + 顾问式排序（不改到期日）。
- **缺**：① `exposure`（看了没测）——读书/看补充资料也该进模型；② `wrong+reviewed_solution`/`closeness`/`grade` 的细分语义（现在只写 R0/Σ）；
  ③ `run/1` 的幂等与存档回退；④ FEEDBACK 微调；⑤ 参数标定。
- **落点**：`ReviewService.grade()` 改成构造一条 `review` 动作（含 reviewed_solution/closeness），新增"读过"入口发 `exposure`；
  两张表之外的写入仍然只有 `encoding_strength`/`savings` 两列（D2 不变）。

### C. 给题目/知识点补充资料（趋势：资料进图，而不是只当附件）

- **已有**：附件、知识包导入、AI 图片→闪存卡、markdown/LaTeX 渲染。
- **缺**：① INGEST 的 `mindnet.material/1`（材料 → 节点/边/记忆记录）；② `knowledge` 动作（新知识点、新连接）；
  ③ TRANSCRIBE 的"照片 → `run/1`"（含出处/置信度）；④ 资料与卡片的关联类型（线索边 vs 包含边，MEMORY_RECORD §3.5 已澄清语义差异）。
- **落点**：新增"添加资料"入口 → 生成 `knowledge` 动作 +（可选）新卡片；把出处写到 `evidence`，进 `change_log`。

### D. Thread 事件排序（趋势：用注意力与目标可达性排序，而不是只加权求和）

- **已有**：`ThreadRanker` 加权公式（紧迫度/目标匹配/状态适配/期望压力/同类疲劳）+ 硬约束 + 疲劳惩罚。
- **缺**：① **节律层 α(τ)**：警觉衰减、负荷自适应周期（`T_cycle`）、flow 带 → "现在该做难还是易、要不要切换/休息"；
  ② `goal` 动作的**目标扩散**：目标集可达性排序（与 MindNet 的 `start_diffusion(starts, targets)` 对齐）；
  ③ 把"当前脑子里的东西"（刚复习/刚做错的节点）作为 `starts` 注入。
- **落点**：`thread_rank_service.dart` 增加一个"认知排序"档位（与现有加权排序并存，可开关），输入 = 目标节点 + 刚活动节点 + α(τ)；
  权重未标定处一律标注（沿用现有"未标定"标注纪律）。

## 3. 落地顺序（按"用户可见收益 / 风险"排）

| 序 | 切片 | 为什么先做 | 验收 |
| --- | --- | --- | --- |
| 1 | **`run/1` 会话协议（tierA+B 全字段）+ 存档回退** | 它是其余一切的地基：没有事件流就没有元认知/标定/反馈 | 一次复习会话产出一份 `result`：`applied[]` 每条含前后值、`trace.rounds[]` 有轮次快照；`run_id` 幂等；回滚后 state_hash 复原 |
| 2 | **`exposure`（看了没测）+ `wrong+reviewed_solution`/`closeness`** | 直接改变 R/S 走势（实测 25 倍差距），且给"补充资料"提供入口 | 读一次资料后 R/S 轨迹与只做错不同；两条路径有测试钉住 |
| 3 | **元认知层（危险区/焦虑区/校准度）** | 用户能直接看懂、直接指导复习与找题 | 读数页新增危险区/焦虑区清单与 κ；`evaluate_problem_fit` 把危险区排前 |
| 4 | **节律层 α(τ)（含负荷自适应周期与 flow 带）** | Thread 排序与"何时休息/切换"需要它 | 线程页出现"当前注意力可用性"与建议（做难/做易/休息），有开关可关 |
| 5 | **控制层指令库 + 反事实规划器排序** | 从"诊断"升级到"今天做这几件事" | 每月/每日计划输出按 `V(π)` 排序的练习清单，含 `retention/reachability` 度量标注 |
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
- 尚未做（切片 2 的另一半）：`exposure`（看了没测）入口——读书/看补充资料目前仍不进模型。

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
  - `danger` 永不出现：它只可能来自 `FastDangerRow`，而元认知信念本应用不存；`LibraryDiagnosis.toJson()` 走 `mindnet.library/1` 握手，便于日后对拍。
- `lib/features/cognitive/presentation/cognitive_model_page.dart`：
  - 新增 `cognitiveLibraryDiagnosisProvider`（tierB 跑一次；`starts` 取最近复习的 `cognitiveStartNodeLimit = 5` 个，`targets` 取 `forced == 1 || dueAt <= now`），
    与 `cognitiveObservationInputsProvider` 一起喂给 `assembleCognitiveReadings`。
  - `diagnosisByKnowledgePoint` 传的是 **`null`（没跑）或非空 map（跑了）**，两者不可合并：`null` ⇒ `unavailable`，空 map ⇒ `healthy`。
  - `CognitiveReadings.fastLayerRan` 随读数带出，页面多两条说明：这次跑没跑（含起点/目标口径）、以及"危险需要自信度、本应用不存所以不会出现"。
  - `unavailable` 不再等于"本页不跑"，而是"这次没做诊断"。
- 仍未做：复习队列（`ReviewAdvisory.order` 的实时调用方）**不传诊断**，队列里的 zone 依旧恒为 `unavailable`——这是下一步（把它接到同一个 runner，注意别让排序变成阻塞）。
- 测试：`test/domain/services/cognitive/library_diagnosis_test.dart`（8 条：没有图不跑、只有图没有起点/目标不跑、孤立节点 = `empty/no_entry`、缺卡行 = `nodesWithoutMs`、非法 R0 当成没提供、danger 永不出现、JSON 握手）+ 读数页新增"诊断让 zone 变真 / 空 map 是 healthy"与"两条说明"用例。

