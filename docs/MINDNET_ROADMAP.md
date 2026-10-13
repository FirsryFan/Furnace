# MindNet × Furnace 扩展路线图（2026-10-11）

> 起因：用户指出"认知模型的功能完全不止这一点点"，要求 Furnace 覆盖更广——
> 找题时有用、闪存卡时有用、给题目补资料时有用、给事件排序（Thread）时也有用。
> 本文件把 **MindNet 文档里已经存在** 的能力与 **Furnace 已接入** 的部分逐条对齐，给出缺口与落地顺序。
> MindNet 侧依据（只读）：`E:\Document\MindNet\docs\{IO_PROTOCOL,MODEL_v2_MATH,CALIBRATION,FEEDBACK,INGEST}.md`、
> `docs\archive\TRANSCRIBE.md`、`docs\PLUGIN_ARCHITECTURE.md`、`MEMORY_RECORD.md §3.5`。

## 0. 一句话现状

我们接进去的是：**tierA 记忆层（R/R0/Σ/S/D）+ tierB 快层（shunting/capacity/ignition/goal）+
卡点诊断与反事实可达性 + 顾问式排序（bands）+ 只读读数页/探针 + 用途 1 工具 + 元认知层（危险区/焦虑区/校准度，轮次二十一）**。
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
- **缺**：① 控制层 `expected_gain`/反事实 `V(π)` 真正参与排序（现在只到判定）；
  ② 节律 α(τ) 决定"现在适合做难还是易"；③ 题目来源（组卷网 skill）与题源质量判据。
  （原列的"元认知危险区优先"已在轮次二十二实测后撤回：见下方"切片 3 的追加"。）
- **落点**：`problem_evaluator.dart` 增加 `retention|reachability` 双度量排序；AI 工具输出里带上"为什么排这里"。

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
| 3 | **元认知层（危险区/焦虑区/校准度）** | 用户能直接看懂、直接指导复习与找题 | 读数页新增危险区/焦虑区清单与 κ（已完成轮次二十一）；`evaluate_problem_fit` 把危险区排前——**试过，实测不成立，已撤回**（轮次二十二） |
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

