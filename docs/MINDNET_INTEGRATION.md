# MindNet 认知模型接入 Furnace（集成地图 + 证据台账）

> **权威划分**：协议正文是 `docs/MINDNET_CONTRACT.md` **§9**（数据所有权 / 单位换算 / 参数标定状态 /
> 降级规则 / 复习段序 / `ms` 口径 / 快照与两个守卫 / MindNet 操作规程 / 真实数据观察协议）。
> 本文是**接入地图 + 证据台账**：接入点在哪些文件的哪些行、本轮实测到了什么、还剩什么风险。
> 两文冲突时以 §9 为准；本文只补充**位置与证据**。
>
> **数字纪律**：本文每个数字都附来源（命令原文 或 `文件:行`）。没有来源的推测一律不写；
> 无法确认的写「未能确认（原因）」。
>
> **基线**：Furnace 工作树 `E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity`（本轮改动尚未提交）；
> MindNet 只读参考 `E:\Document\MindNet`，`git log -1 --format=%H` = `f4eec9bae16e6e303c19177e7fbfcf7a756f6629`。
> 本文列出的命令均在 2026-10-01 本会话实跑。

---

## 0. 本轮验证快照（全部本会话实跑）

| 项 | 命令 | 结果 |
| --- | --- | --- |
| 全量测试 | `cd app; flutter test --concurrency=1` | `All tests passed! (+520 ~2)`，exit 0（跳过 2 条：探针宿主入口无 `--dart-define` 时的既定 inert） |
| 静态分析 | `cd app; dart analyze lib test` | `ERROR=0 WARNING=0 INFO=87`，exit 0 |
| 对拍与守卫 | `cd app; flutter test test/domain/services/srs/mindnet_dsr_conformance_test.dart test/domain/services/cognitive/mindnet_fast_conformance_test.dart test/domain/services/cognitive/fast_diagnosis_conformance_test.dart test/domain/services/cognitive/mindnet_protocol_guard_test.dart --concurrency=1` | `All tests passed! (+46)`，exit 0 |
| fixture 计数与容差 | `node -e "const j=require('app/test/fixtures/mindnet_vectors.json'); …"` | `tierA=43 tierB=1`；`commit=ace605d9778e8641957c570c1e58049ca82e4a01`；`rel=1e-12 abs=1e-15 rounded_decimals=6` |
| fixture 摘要 | `Get-FileHash <file> -Algorithm SHA256` | `mindnet_vectors.json` = `DBB2E33E36F56970A1C98413CB4F36596173E049167AFC624480BAD9CA4FA64A`（36812 B）；`mindnet_tierb_diagnosis.json` = `81905021D04166F209F6D7183D8933612E33C8ADD309C50A45D622503C8234F9`（112991 B） |
| B01 区分力 | `node -e`（读 `tierB[0].expected.rounds`） | `rounds=5 distinct=1 roundsField=[1,1,1,1,1]`（见 §3.4） |
| 多轮场景 | `node -e`（读 diagnosis fixture 的 `scenarios.multiround_progression`） | `rounds=6 distinct=6 roundNumbers=[1,2,3,4,5,6]` |
| 诊断分类用例 | `node -e`（读 `classify` 的键） | 20 条（键 `0`–`19`） |
| MindNet 零写入 | `git -C E:\Document\MindNet status --porcelain` | ` M conformance/mindnet_vectors.json`（**先前遗留**；本侧未写入、未回滚，见 §9） |
| Windows release | 见 `docs/VERIFICATION_MINDNET.md`（t18 报告） | `flutter build windows --release` exit 0；产物 `app/build/windows/x64/runner/Release/data/app.so` 本会话实测存在：LastWrite `2026-10-01 14:03:09`、10404744 B |

---

## 1. 接入点清单（文件:行）

> 行号取自本会话读取结果；只列**接入面**。

### 1.1 可替换接口（支架层）

| 接入点 | 位置 | 说明 |
| --- | --- | --- |
| `CognitiveModel` 接口 | `app/lib/domain/services/cognitive/cognitive_model.dart:46` | `id` / `retrievabilityOf:54` / `expectedGain:65` / `orderAdvisory:99` / `modelReadingOf:127` / `modelStateAfterReview:144` |
| 排序候选 | 同上 `:162` | `AdvisorCandidate`（只有 `knowledgePointId` + `row`；无 zone 字段） |
| 模型实现 | 同上 `:249`（`MindNetCognitiveModel`）、`:346`（`HeuristicCognitiveModel`） | 均只转发 tierA，不复制算法 |
| provider（唯一替换点） | 同上 `:485` | `cognitiveModelProvider`，可 `overrideWithValue` |
| 时钟换算 | 同上 `:241` | `modelHoursOf(DateTime)`：纪元毫秒 → 小时 |

### 1.2 标签树 → 认知图投影

| 接入点 | 位置 | 说明 |
| --- | --- | --- |
| 投影输入 | `app/lib/domain/services/cognitive/cognitive_graph.dart:90` | `CognitiveTag`（`CognitiveTag.fromTag` 适配 drift 行） |
| 节点 / 边 / 图 | 同上 `:128` / `:197` / `:230` | `CognitiveNode` / `CognitiveEdge` / `CognitiveGraph`（`toJson` = MindNet 输入格式） |
| 边权默认 | 同上 `:238` / `:242` | 父子 `0.7` / 兄弟 `0.4`（**未标定**，见 §6） |
| MindNet 兜底常量 | 同上 `:259` | `mindNetDefaultMs = 0.8`（具名，**绝不隐式套用**） |
| 未提供 `ms` 的节点 | 同上 `:266` | `nodesWithoutMs`（可观察、可断言） |
| 投影函数 | 同上 `:315` | `fromTags({required tags, required ms, …})` |

### 1.3 tierB 快层与诊断

| 接入点 | 位置 | 说明 |
| --- | --- | --- |
| 引擎 | `app/lib/domain/services/cognitive/fast_engine.dart:1041` | `FastEngine`（`clone:2043`） |
| 图读入 | 同上 `:502` | `FastGraph.fromSpec(...)` |
| 机制参数 | 同上 `:195` | `FastMechanisms`（工厂 `:204`）——**不是** `FastParamRegistry`（该符号不存在，t25 复核） |
| 驱动求和 | 同上 `:1790-1791` | `final contribution = au * strength * edge.ls; drive[edge.to] += contribution;` |
| 诊断事实 | 同上 `:1984-2008` | `diagnosticFacts()`；`:2008` `r: round6(node.ms)` |
| 诊断分类 | `app/lib/domain/services/cognitive/fast_diagnosis.dart:243` | `FastDiagnosis`；7 类 `BottleneckType:76`；分类分支 `:262`(overload) `:287`(weak) `:317`(deadEnd) |
| 反事实克隆 | 同上 `:843` | `final clone = engine.clone();` |
| 处方 | 同上 `:573` | `FastPlanner`（`RetentionProbe:566`） |

### 1.4 复习流程接入（t16）

| 接入点 | 位置 | 说明 |
| --- | --- | --- |
| 段定义 | `app/lib/features/anki/application/review_advisory.dart:49` | `enum ReviewBand { forced, boosted, model, unseen }` |
| 词表 | 同上 `:77` | `enum ReviewZone`（9 值，见 §5.2） |
| 编排 | 同上 `:178` | `abstract final class ReviewAdvisory` |
| 模型段排序 | 同上 `:263` | `model.orderAdvisory(...)`——**全系统唯一排序原语**，本文件不写比较器 |
| 复习写回 | `app/lib/features/anki/application/review_service.dart:463-468` | `modelStateAfterReview(...)` → `ankiRepository.updateModelState(...)`（包在 `try` 内） |
| 时钟 | 同上 `:197` / `:466` | `modelHoursOf(moment)` |
| 窄写方法 | `app/lib/data/repositories/anki_repository.dart:388` | `updateModelState(id, {encodingStrength, savings})`，只构造这两个 `Value` |

### 1.5 用途 1（题目质量/难度评估）

| 接入点 | 位置 | 说明 |
| --- | --- | --- |
| 判定枚举 | `app/lib/domain/services/cognitive/problem_evaluator.dart:38` | 6 种判定（见 §4） |
| 评估器 | 同上 `:186` | `ProblemEvaluator` |
| `ms` 取值 | 同上 `:225` | `model.modelReadingOf(row, …).r0`（= 编码上限，见 §3.6） |
| 建图 | 同上 `:231` | `CognitiveGraph.fromTags(...)` |
| AI 工具 | `app/lib/features/ai/tools/cognitive_tools.dart:24` | `EvaluateProblemFitTool`（只读、无 SQL） |
| 工具注册 | `app/lib/features/ai/domain/tool_registry.dart:11` / `:43-55` | `import '../tools/cognitive_tools.dart';` + `ToolRegistry.forApp` 静态清单（`EvaluateProblemFitTool` 在 `:49`） |
| provider 接线 | `app/lib/features/ai/application/ai_providers.dart:36-48` | `toolRegistryProvider` → `ToolRegistry.forApp(…, model: ref.watch(cognitiveModelProvider))` |

### 1.6 只读观测面（t19）

| 接入点 | 位置 | 说明 |
| --- | --- | --- |
| 探针（纯 Dart） | `app/tool/mindnet_probe.dart` | `:18-38` 记录"为什么要 Flutter 宿主"；宿主 = `test/tool/mindnet_probe_test.dart`（`:29-30`）；报告入口 = `test/tool/mindnet_probe_report_test.dart`（`:32`）；`:424` "Runs the host under `flutter test`" |
| 读数组装 | `app/lib/features/cognitive/presentation/cognitive_model_page.dart:376` | `assembleCognitiveReadings(...)`；只用 `model.*`（`:418` `modelReadingOf`、`:425` `expectedGain`）+ `ReviewAdvisory` |

### 1.7 tierA（既有，只被接入）

| 接入点 | 位置 | 说明 |
| --- | --- | --- |
| 记忆层 | `app/lib/domain/services/srs/dsr_memory.dart` | `legacyK = 24`（`:45`）；lapse 分支 `:470-479`；`R0` 只在成功复习时上调 `:484-487` |
| 行桥接 | `app/lib/domain/services/srs/dsr_card_state.dart:20` | `read:46` / `write:88`（**禁止**用于复习落库）/ `hoursPerDay:26` |
| 协议常量 | `app/lib/domain/services/cognitive/mindnet_protocol.dart:19` | 协议串 `:23`、冻结 commit `:30-31`、容差 `:37/:40/:43`、`must_be_exact:46-54`、时钟单位 `:59` |

---

## 2. 数据所有权与写路径（D2）

### 2.1 一列一个写者

| 列（`card_states`） | 写者 | 读法 |
| --- | --- | --- |
| `stability` / `difficulty` / `dueAt` / `intervalDays` / `lastReviewedAt` / `state` / `repetitions` / `lapses` / `forced` / `forcedStreak` | **FSRS 复习流程** | 模型只读（`stability` 天 → 小时经 `DsrCardState.hoursPerDay`） |
| `encoding_strength`（`R0`） | **认知模型** | 经 `anki_repository.dart:388` 的窄写 |
| `savings`（`Σ`） | **认知模型** | 同上 |

### 2.2 写路径的两条铁律（都有取证）

1. **不允许**复习流程调用 `DsrCardState.write()` / `applyReview()` 落库：`dsr_card_state.dart:88-120` 的 companion 会一并写
   `stability` / `difficulty` / `encodingStrength` / `savings` / `intervalDays` / `dueAt` / `lastReviewedAt` / **`updatedAt`** / `repetitions` / `ease`。
   取证：t25 报告（`docs/VERIFICATION_PROTOCOL.md` §2.1）在 `app/lib/features` 全目录 grep `DsrCardState\.|applyReview\(` → **0 命中**。
2. **`updatedAt` 不得二次写入**：窄写方法的文档 `anki_repository.dart:371-374` 明确声明；其 companion（`:396-403`）只含两列，两参皆 `null` 时直接返回（`:393-395`）。

### 2.3 为什么不加表 / 列 / 迁移

`R0 / Σ / S / D` 落在 v6 **已存在**的列上（`app/lib/data/database/database.dart` 的 `schemaVersion = 6`；列定义见 `tables.dart` 的 `CardStates`），
所以接入不产生第二份数据真相：两边读写同一行。依据：`MINDNET_CONTRACT.md` §9.1。

---

## 3. 移植范围与对拍证据

### 3.1 移植了什么 / 没移植什么

| 层 | 内容 | 位置 |
| --- | --- | --- |
| tierA | `memory.dsr.js` 的记忆层（曲线 / 可提取度 / 排程反解 / 五种事件 / 难度 / 储蓄效应 / 失败证据） | `srs/dsr_memory.dart` |
| tierB | `dynamics.shunting`（精确积分）/ `attention.capacity` / `attention.ignition` / `context.goal` + `v2/engine.js` 的 `step` 管线 | `cognitive/fast_engine.dart` |
| 诊断/处方 | `diagnosis.bottleneck` 的 7 类卡点 + 反事实可达性（`clone()`） | `cognitive/fast_diagnosis.dart` |
| **未移植** | `rhythm.gate` / `mulberry32` RNG / `attention.inhibition` / `legacy_v1` / `metacognition.belief` | 契约 §6.1 的可移植性矩阵 + 队内 D3 |
| 随机源处理 | `T_ign = 0`（硬阈值，不消耗随机数）、不装 `rhythm.gate`（`availability ≡ 1`） | 契约 §6.1 |

### 3.2 对拍命令与结果（本会话实跑）

```powershell
cd app
flutter test test/domain/services/srs/mindnet_dsr_conformance_test.dart `
  test/domain/services/cognitive/mindnet_fast_conformance_test.dart `
  test/domain/services/cognitive/fast_diagnosis_conformance_test.dart `
  test/domain/services/cognitive/mindnet_protocol_guard_test.dart --concurrency=1
# → All tests passed! (+46)，exit 0
```

fixture 自身计数（`node -e` 读文件，见 §0）：**tierA 43 条 + tierB 1 条**。

### 3.3 容差与"必须完全相等"字段

- 浮点：`rel ≤ 1e-12`（绝对值兜底 `1e-15`），另以 `round6`（6 位、half-away-from-zero）作人读复核 —— 来源：fixture 的 `tolerances`（本会话 `node -e` 读出）。
- 集合与枚举逐位相等：`admitted` / `focus` / `outcompeted` / `conscious` / `subconscious` / `states[].state_after` / `kind` —— 同上；已固化为常量 `mindnet_protocol.dart:46-54`（t25 报告 §1 给出与 fixture 的 7/7 MATCH 输出）。

### 3.4 B01 的区分力边界（必写）

tierB 在 `mindnet_vectors.json` 里只有 **1 条**用例，其 `expected.rounds` 是 **5 个完全相同**的快照
（本会话实测 `rounds=5 distinct=1 roundsField=[1,1,1,1,1]`）。

- 成因（t15/t2 记录）：第 1 轮目标即被点亮 → 引擎按"全部目标可达"停止，之后快照重复最后一次。
- 因此 B01 **只证明**：第 1 轮全字段逐位一致 + 停止语义正确；**不能**用它声明"逐轮演化正确"。
- 补强证据：`mindnet_tierb_diagnosis.json` 的 `scenarios.multiround_progression` —— **6 轮、6 个互异快照**
  （本会话实测 `rounds=6 distinct=6 roundNumbers=[1,2,3,4,5,6]`），由 `fast_diagnosis_conformance_test.dart` 对拍。

### 3.5 快照与两个守卫（必写）

- **冻结快照**：`generated_from.commit = ace605d9778e8641957c570c1e58049ca82e4a01`（fixture 第 5 行；常量在 `mindnet_protocol.dart:30-31`）。
  §8 的写作基准写的是 `c624884`，两者不同，**以文件为准**；§8 作为历史留档不改写。
- **与 HEAD 的关系**：MindNet HEAD = `f4eec9b…`；t25 报告 §2.5 的掩码比对（两份均 36812 B，掩码 `generated_from.commit` 后逐字符相同）证明**数值零差异**。
- **两个守卫分工**：
  - MindNet 侧 `node tools/conformance.js --check`：比的是 **MindNet 实现 vs MindNet 自己的 conformance 文件**，且 `tools/conformance.js:284` 在比对时**归一化掉 commit**（本会话实读该行）。它**不能**证明 Furnace 这份拷贝没过期。
  - Furnace 侧 `test/domain/services/cognitive/mindnet_protocol_guard_test.dart`：读**我们的** fixture 比对常量，不一致即失败。
    证伪实验（t25 报告 §3）：把 fixture 的 commit 改成 `deadbeef…` → 守卫失败并打印两侧值；字节还原后 SHA256 回到 `dbb2e33e…`、重新通过。

### 3.6 `ms` = `R0` 的口径（必写）

- MindNet 三条依据（本会话实读）：`src/model.js:50`（缺省 0.8）、`mechanisms/memory.dsr.js:90`（读作 `R0 = min(1, ms)`）、`src/io/run.js:387`（导出 `ms: bag.R0`）。
- 本侧因此传 **`modelReadingOf(row).r0`**（编码上限），**不是**当前 `R`：`problem_evaluator.dart:225`。
- 导出侧另有一处不一致（t25 复核）：`src/io/run.js:602` 导出的是当前 `ms` 且另给 `R0`；`mechanisms/memory.dsr.js:114` 会把 `node.ms` 改写成当前 `R` ⇒ **导出的 `ms` 不能回喂**。
- 语义后果（reviewer 裁定；t25 报告 §2.5 用冻结曲线常数复算：`ψ(0)=1`、`ψ(1)=0.900000000`、`ψ(10)=0.692826635`）：`R ≤ R0` ⇒ 用 `R0` 当 `ms` 会使可达性判断**偏乐观**。这是设计取向，不是缺陷。
- 投影侧强制：`fromTags(ms:)` 为必填；缺条目 → 不写该键 + 进 `nodesWithoutMs`；MindNet 的 0.8 只以 `mindNetDefaultMs` 具名存在（`cognitive_graph.dart:259/266/315`）。

### 3.7 D6 的实证更正（必写）

**lapse 不抬 `R0`，只有成功复习才抬。** 取证：`dsr_memory.dart:470-479`（lapse 分支只改 `S` 与失败记录）、`:484-487`（`retrievalSuccess` 才执行 `state.r0 = min(1.0, state.r0 + cR0·(1−R0))`）。
本轮**未加任何护栏**（保持与 JS 逐位一致）；行为由测试钉住（t16 登记 output：lapse 后 `R0` 保持 0.3、`stability` 崩落、`savings` 不减，两列与 `DsrCardState.applyReview` 逐位相等）。

---

## 4. 用途 1：题目质量/难度评估（契约 §6.3 配方落地）

### 4.1 链路（全部在 Furnace 侧）

```
候选题（id / 题干 / knowledge_point_ids / difficulty_hint）
  → CognitiveGraph.fromTags(tags, ms: {tagId: R0})      # problem_evaluator.dart:231
  → FastGraph.fromSpec(graph.toJson())                   # fast_engine.dart:502
  → FastEngine(4 机制 + T_ign=0) → startDiffusion(starts, targets) → runRounds(3~5)
  → FastDiagnosis.bottlenecks(...)                       # fast_diagnosis.dart:243
  → 判定 ∈ {too_easy, zpd, too_hard, out_of_scope, redundant, high_value} + 排序键
                                                          # problem_evaluator.dart:38
```

### 4.2 六种判定

判定枚举与位置：`problem_evaluator.dart:38`（6 值）。下表每行是对该文件判定分支的一句话概括；
**阈值与边界以代码为准**，其中 `out_of_scope` 的锚点是 `:355-358`（`BottleneckType.empty` 或 `deadEnd` → 超纲/死角），`weak`（差点想起来）在 `:355`。

| 判定 | 含义 |
| --- | --- |
| `too_easy` | 模型认为该知识点已掌握（`R` 处于高位） |
| `zpd` | 落在发展区：模型的证据显示"可及但未牢" |
| `too_hard` | `R` 过低且线索不足 |
| `out_of_scope` | 诊断为空或死角（`empty` / `deadEnd`） |
| `redundant` | 该题的知识点被同批另一题覆盖 |
| `high_value` | 目标节点的最高价值命中（排序键最高） |

### 4.3 两条必须遵守的输入规则

1. **`starts` / `targets` 必须先过滤成图内存在的 id**：图外 id 会让 tierB 侧抛 `ArgumentError`，而"题目引用了投影里没有的标签"是正常情况。
2. **`difficulty_hint` 只作无历史时的排序先验**，**不得**作为模型的 `D` 传入（模型的 `D` 由表现档位与 `R` 更新，契约 §6.3）。

### 4.4 一条必须写明的建模约束（t20 观察）

**认知图的节点 id 来自标签（tags），记忆行来自知识点（knowledge points）：这是两个 id 空间。**
扩散只能对"同时存在于两个空间"的候选发言；不对齐时工具按只读降级，给出仅 tierA 判定（`fast_layer_ran=false`，已有测试）。
tierB 端到端链路是用"同一 id 既是 tag 又是 kp"的对齐构造跑通的。**若要让真实数据的判定更靠前，需要一座 kp → 标签的桥（本轮未做）。**

---

## 5. band 与 zone 语义

### 5.1 段序（D1 / D4）

```
forced → boosted → model → unseen
```

- `forced`：答错绑定，当天必须回来；沿用既有 `_interleave` 的落位规则（一行未改）。
- `boosted`：`DiffusionBoost` 的启发式加权，**已标注"启发式、非模型量"**，且不与模型诊断同屏（契约 §6.5 的短期分工）。
- `model`：顺序**唯一**由 `CognitiveModel.orderAdvisory` 给出（`review_advisory.dart:263`）。全序键：
  目标集命中 → 增益 ↓ → `dueAt` ↑（**`null` 排最后**，不当 1970）→ 知识点 id ↑ → 卡 id ↑（`cognitive_model.dart:99` 的文档 + `_orderAdvisory` 实现）。
- `unseen`：**新卡不交给模型打分**（无历史），顺序确定、不伪造 `lastReviewedAt`。
- 段与组内排序键用 **`cardStateId`**，不用 `unitKey`：无空可挖时 `unitKey` 一律回落 `'essay'`（`review_service.dart:233-235`），多个知识点会撞键并静默覆盖。

### 5.2 zone 词表（9 值）

`review_advisory.dart:77` 的 `ReviewZone` 共 **9 值**：t2 的 7 类瓶颈（`weak` / `empty` / `deadEnd` / `slow` / `overload` / `offGoal` / `danger`）+ `unavailable` + `healthy`。

| 情形 | zone |
| --- | --- |
| 诊断层不在场（tierB 未跑） | `unavailable`（"没跑模型"），排序照常 |
| 诊断跑了、该知识点不在结果里 | `healthy`（"跑了、无卡点"） |
| 诊断给出卡点 | 与 7 类一一映射 |

**`healthy` 与 `unavailable` 必须区分**：把"没跑模型"显示成"健康"或"未知"都会骗用户（§9.4）。
**已知边界（t19 如实标注）**：读数页当前的 zone 列恒为 `unavailable`（页面不跑 tierB），这是如实反映"诊断层不在场"。

---

## 6. 参数标定状态

### 6.1 已标定（有出处）

| 参数 | 值 | 出处 |
| --- | --- | --- |
| `attention.capacity.W_DAR` | 4 | Cowan / Oberauer（工作记忆容量） |
| `attention.capacity.W_FA` | 1 | 焦点唯一 |

### 6.2 未标定（代码内带 `calibrated: false` / "未标定"字样）

父子边权 `ls` = 0.7 / 兄弟 `ls` = 0.4 · `alpha_a` = 0.5 · `lambda_a` = 0.2 · `eta_q` = 0.5 · `lambda_q` = 0.3 ·
`beta_goal` = 0.3 · `kappa_reach` = 0.5 · `fan_k` = 0（关闭 fan-out 稀释）· `T_ign` = 0（接入用；机制默认 0.05）·
`memory.dsr.legacy_k` = 24 h（**MindNet 声明的默认值**）。完整表见 `MINDNET_CONTRACT.md` §9.3。

**本轮未移植因而也没有标定的**：`rhythm.gate` 的走神率 / 占空比 / 警觉衰减、`mulberry32` 随机源、`attention.inhibition`、`legacy_v1`、`metacognition.belief`。

### 6.3 `fast_diagnosis.dart:775` 的 `4` **不是** §6.6 违规（必写）

`fast_diagnosis.dart:773-775` 的 `offload_working_memory` 处方里有一行 `engine.numberParam(key, 4)` —— 那个 `4` 是 **`W_DAR` 的兜底默认值**，
而 `W_DAR = 4` 是**已标定**的（Cowan / Oberauer，§6.1）。§6.6 针对的是**未标定的 MindNet 默认参数值**（不得写死进 Dart）；
把这一行写成"§6.6 违规"是错的。

### 6.4 t2 的 5 处参数尖锐点 + 两条机理（必写）

| # | 尖锐点 | 代码锚点（本会话读取） |
| --- | --- | --- |
| 1 | 反事实处方克隆引擎时，`mechanisms` 必须一并带过去（否则克隆体回落默认机制，预测失真） | `fast_diagnosis.dart:843`；`fast_engine.dart:2040-2043`（`clone()` 与其注释） |
| 2 | 目标存在时 `dead_end` 可能**不可达**（目标被点亮会改变可达性判定） | `fast_diagnosis.dart:317`（deadEnd 分支）；`:133`（其处方 `add_out_edges`） |
| 3 | `diagnostic_facts` 里的 `r` 已经过 `round6`，而分类器用**原始值**比较——两者不可混用 | `fast_engine.dart:2008`（`r: round6(node.ms)`）vs `fast_diagnosis.dart:251` 起的事实消费 |
| 4 | 参数边界上 `weak` 会**漂移成** `overload`（分类阈值相邻） | `fast_diagnosis.dart:287`（weak）/ `:262`（overload） |
| 5 | `slow` 只能靠 `add_initial_nodes` 的 `late` 干预实现（`slow_target` 场景） | `docs/VERIFICATION_MINDNET.md:233`（"第 5 轮补边 + `add_initial_nodes`"的 `late` 干预；补上后 25 项逐位相同） |

**两条机理**（解释驱动为什么这样动）：

1. **节点的 `ms` 只缩放它自己的出边贡献**：`fast_engine.dart:1790-1791` 的 `au * strength * edge.ls` 中 `strength` 取**源节点**的 `ms` ⇒ 一条边的贡献随"源"而不是"目标"变化。
2. **"延后点亮"靠入边 `ls`**：一轮内的驱动只来自入边（同上），所以一个节点晚点亮，是因为指向它的边的 `ls`（与源的 `ms`）累积得慢——这也是多轮场景（`multiround_progression`，6 轮互异）能区分实现的机理。

---

## 7. 剩余风险与未做项

| 项 | 状态 | 依据 |
| --- | --- | --- |
| 可达性判断**偏乐观** | 已登记、设计取向 | `ms = R0` 的语义后果，§3.6（t25 复算 `R ≤ R0`） |
| **两个 id 空间**（标签 vs 知识点） | 未解决 | §4.4；不对齐时工具降级为仅 tierA（有测试） |
| 新卡不参与模型打分 | 设计（D4） | §5.1 的 `unseen` 段 |
| 读数页 zone 恒 `unavailable` | 如实标注 | §5.2（t19 边界） |
| `ls` / `W_DAR` / `β_goal` 等未标定 | 已标注 | §6.2 |
| DiffusionBoost 仍在 | 短期分工（D5） | §5.1 |
| ~~Android 未重构建 / `.fskill` 容器 / Thread 事件流刷新~~ **已更新（2026-10-02）** | Android 已重构建；Thread 事件流刷新已实现（`docs/REACTIVITY_DESIGN.md`）；`.fskill` **安装/管理**已实现、**脚本执行容器**仍未实现（`docs/SKILL_FORMAT.md` §7） | `docs/HANDOFF.md` |
| ~~**MindNet 工作树有一处先前遗留的脏文件**~~ **已判定：保留（2026-10-02）** | 工作区戳 `f4eec9b` **等于该仓库 HEAD**，已提交的 `107ab12` 才是过期值，回退等于换回过期值；以后核验口径＝"diff 只允许出现 `generated_from.commit` 一行" | `MINDNET_CONTRACT.md` §9.8b 第 5/6 条 |
| 全量测试有 2 条 skip | 正常 | §0（探针宿主入口无 `--dart-define` 时 inert） |

---

## 8. 登记形态事故与重建映射（必写）

本轮发生过一次**任务无法登记**的结构性事故（与代码无关）：

- 原因：任务的 `inScope` 写成工作区外形式，而登记校验要求 `changedPaths` 既是**工作区内的相对路径**、又要与 `inScope` 匹配 ⇒ 两个条件互斥，任务永远登记不了。
- 处置：队长**取消**原任务，并以"仓库相对 `inScope`"重新入账。

**重建映射**（原任务 → 重入账任务）：

| 原 | 重 | 说明 |
| --- | --- | --- |
| `t1` | `t14` | 认知图投影 + `CognitiveModel` 接口（含 A2 追加项） |
| `t2` | `t15` | tierB 移植 + 对拍 + 诊断 fixture |
| `t3`–`t12` | `t16`–`t25`、`t30` | 接入 / 工具 / 探针 / 协议件 / 登记补录等 |

**另一条必须写明的教训（必写 ⑭）**：**验证任务不能带着 failed 的验收项完成**——工具会拒绝
（`verification completion requires passed acceptanceResults for every acceptance item`）。
因此 `t18`（第一轮独立验证）与 `t25`（协议件复核）都以 `failed` 收口、**未登记**，但**报告仍在盘上可直接引用**：
`docs/VERIFICATION_MINDNET.md`、`docs/VERIFICATION_PROTOCOL.md`。
它们失败的唯一验收项是"MindNet porcelain 为空"（成因见 §9，属先前遗留）；产物层面的读数见 §0（本会话实跑）与上述两份报告。

---

## 9. MindNet 侧操作规程（铁律，必写 ⑬）

> 这一节的每条都是本轮踩出来的。**违反它的代价是一次真实的"参考仓库被写脏"事故。**

1. **只允许 `--check`**：核验新鲜度只用 `node tools/conformance.js --check`（实测只读：运行前后 porcelain / mtime / size / SHA256 四项全同，t25 报告 §5.2）。
2. **`npm test` 也会写盘**：MindNet 的 conformance 测试在用例内无条件执行 `--write`——原文（本会话实读）
   `E:\Document\MindNet\test\conformance.test.js:123-129`：
   ```js
   test('样例 · 生成器可被工具调用（--write 后 --check 必须通过）', () => {
     const script = path.join(__dirname, '..', 'tools', 'conformance.js');
     execFileSync(process.execPath, [script, '--write'], { stdio: 'pipe' });
   ```
   而 MindNet 的 `test` 脚本就是逐个跑它的 conformance 测试文件（本会话实读 `E:\Document\MindNet\package.json`：
   `"test": "node --test test/*.test.js"`、`"conformance": "node tools/conformance.js"`）⇒ **跑一次 `npm test` 会重戳 `conformance/mindnet_vectors.json` 的 `generated_from.commit`**（依据：上引 `E:\Document\MindNet\test\conformance.test.js:123-129` 的 `--write` 调用）。
   落盘点（本会话实读）：`tools/conformance.js:304-305`（`fs.mkdirSync` + `fs.writeFileSync(OUT, text, 'utf8')`）；该文件里唯一的只读分支是 `--check`（`:270` 起；`:284` 归一化 commit）。
3. **看到 `--check` 提示 `--write` 也不得照做**：`tools/conformance.js:296-297` 在"只是 commit 变了"时会打印
   `样例数值一致（只是 commit 变了：…）` + `提示：…顺手跑一次 node tools/conformance.js --write…`。
   那是给 **MindNet 自己**的维护建议，**Furnace 侧不得照做**。
4. **"零写入"核验必须排在整轮动作的最后**：中途跑过任何写盘路径，早前的读数就作废。
5. **还原也只能由仓库所有者授权后做**：回滚同样是写操作。本轮那处脏文件（` M conformance/mindnet_vectors.json`，mtime `2026/10/01 13:53:35`，仅 commit 戳记一行）**本侧未写入、未回滚**，处置权在用户 / 队长。

---

## 10. 真实数据自测路径（照做即可，必写 ⑮）

### 10.1 为什么需要一个 Flutter 宿主（必写 ⑫）

`database.dart` → `path_provider` → `package:flutter` → `dart:ui`，**纯 Dart VM 没有 `dart:ui`**，所以"直接 `dart run` 读模型"不可用；
探针把这件事拆成"纯 Dart CLI + Flutter 宿主"，`dart run` 只作为启动器转交宿主（`app/tool/mindnet_probe.dart:18-38`、`:424`）。

### 10.2 命令

```powershell
cd E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity\app

# 宿主式探针（默认读 %APPDATA%\FirsryFan\Furnace\furnace.db 的副本）
flutter test test/tool/mindnet_probe_report_test.dart `
  --dart-define=PROBE_DB="$env:APPDATA\FirsryFan\Furnace\furnace.db"
# 可选：--dart-define=PROBE_JSON=1、--dart-define=PROBE_LIMIT=20
```

零写入保证：先把库（连同 `-wal` / `-shm`）复制到临时目录、**只打开副本**，原库只被 `stat`；
t19 登记 output 记录的真实库实测：运行前后 SHA256 同为 `8c58a610…4615ec6`，结论行『原库未被修改: 是』。

### 10.3 看什么、什么算异常

| 指标 | 判读 |
| --- | --- |
| `R` 低 + 增益高 | 模型认为"快忘了、现在复习最值" |
| `R` 高 | 还记着 |
| `band` 分布 | `forced` / `boosted` / `model` / `unseen` 各几张；全是 `unseen` 说明数据里没有历史 |
| `zone` 全 `unavailable` | **预期**（页面 / 探针不跑 tierB）；若出现 `healthy` 说明诊断层跑过 |
| `nodesWithoutMs` 非空 | 有标签没有任何卡片的编码上限——检查是否两个 id 空间未对齐（§4.4） |
| 原库 SHA256 / mtime 变化 | **异常**（探针只读副本）；立即停止并报告 |

### 10.4 页面入口

设置页 →「认知模型」读数页（`app/lib/features/cognitive/presentation/cognitive_model_page.dart`）；
页面顶部标注『顾问模式：不改到期时间』与『`ls` 等边权未标定』；页面**只读**（t19 登记 output 记录了写入 API 搜索证据）。

---

## 11. 已证伪的两条（留档，必写 ②）

| 曾疑似缺陷 | 结论 | 依据 |
| --- | --- | --- |
| 全新卡的 `R0 = 0.8` | **不是缺陷**：这是**另一个分支**（`stability` 与 `difficulty` 都为 NULL 时的 tierA 初始化），与 `mechanisms/memory.dsr.js:90` 的 `ensureState` 对齐，已有测试钉住 | `dsr_memory.dart` 的 `DsrState.initial`；`MINDNET_CONTRACT.md` §9.4 |
| `legacy_k = 24` 是"编造的常数" | **不是**：它是 MindNet **声明的默认值**（`mechanisms/memory.dsr.js` 的 `default: 24`），单位是**小时** | `dsr_memory.dart:45`；`MINDNET_CONTRACT.md` §9.3 |

---

## 12. 必写清单 → 定位（自查表）

| # | 必写项 | 在本文的位置 |
| --- | --- | --- |
| ① | B01 区分力边界（5 快照同值；补强 `multiround_progression` 6 轮互异） | §3.4 |
| ② | 已证伪两条留档 | §11 |
| ③ | 快照 commit 统一 `ace605d`（与 HEAD `f4eec9b` 数值一致；§8 不改写） | §3.5 |
| ④ | `--check` 与 Dart 守卫分工 | §3.5 |
| ⑤ | `fast_diagnosis.dart:775` 不得写成 §6.6 违规 | §6.3 |
| ⑥ | t2 的 5 处尖锐点 + 两条机理 | §6.4 |
| ⑦ | `ms = R0` 口径 | §3.6 |
| ⑧ | D6 实证更正（lapse 不抬 `R0`） | §3.7 |
| ⑨ | `unitKey` 非全局唯一 → 排序键用 `cardStateId` | §5.1 |
| ⑩ | fixture SHA256（`mindnet_vectors.json` = `DBB2E33E…`；`mindnet_tierb_diagnosis.json` = `81905021…`） | §0 |
| ⑪ | 登记形态事故与重建映射 | §8 |
| ⑫ | 探针必须用 `flutter test` 托管（`dart:ui` 不可用） | §10.1 |
| ⑬ | MindNet 操作铁律 | §9 |
| ⑭ | 验证任务不能带 failed 验收完成（t18/t25 未登记，报告可引） | §8 |
| ⑮ | 真实数据自测路径 | §10 |

---

## 13. 跨实现互校脚本（仓库外、只读）

> 本节为**补记**：这两条脚本此前只存在于验证报告与聊天记录里，不随仓库分发。它们的作用是让下一位接手者**不依赖聊天记录**就能分头复跑"第二条验证路径"。本节只新增，不改 §1–§12 的任何结论与数字。

### 13.1 两条脚本与分工

| 脚本 | 路径（仓库外） | 证明什么 |
| --- | --- | --- |
| JS ↔ 夹具 | `C:\Users\Public\mindnet-verify\recompute_b01.cjs` | 夹具的 `input` 经 **MindNet 真实引擎**能重放出夹具自己的 `expected` —— 它直接 `require` MindNet 的 `src/index.js` + `src/v2/engine.js`，**不经过** `tools/conformance.js` 的 `tierB()`；顺带核对 `module_defaults` 是否仍等于四个机制的实时 `DEFAULTS` |
| Dart 端口 ↔ 夹具 | `C:\Users\Public\mindnet-verify\tierb_b01_check.dart` | **本仓库移植**（`package:furnace` 的 `fast_engine.dart`）与**同一份** `expected` 逐位一致 |

两者互补：前者管"期望值与**真实实现**一致"，后者管"**移植**与同一期望值一致"。仓内测试只覆盖后者这一侧，所以两条都过才说明这条对拍不是自证循环。

### 13.2 调用方式与本会话实测输出

```powershell
# 1) JS 侧：无参数，路径硬编码在脚本内部
node "C:\Users\Public\mindnet-verify\recompute_b01.cjs"
# 实测输出（本会话，exit 0）：
#   module_defaults drift entries: 0
#   checks: floats=130 exact=200
#   worst float rel=0 at
#   B01 RECOMPUTE: all fields match within fixture tolerances (rel<=1e-12, abs<=1e-15)

# 2) Dart 侧：--packages 指向 app 的包配置；第二个参数是夹具路径
dart --packages="E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity\app\.dart_tool\package_config.json" `
  "C:\Users\Public\mindnet-verify\tierb_b01_check.dart" `
  "E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity\app\test\fixtures\mindnet_vectors.json"
# 实测输出（本会话，exit 0）：
#   vector          : B01-fast-layer-chain-5-rounds
#   rounds expected : 5
#   rounds produced : 5
#   float comparisons : 135
#   exact comparisons : 215
#   worst rel diff    : 0.0 at
#   B01 DART CHECK: PASS — sets/enums exact, floats within rel<=1e-12/abs<=1e-15
```

输出与当时夹具绑定：`mindnet_vectors.json` = `DBB2E33E36F56970A1C98413CB4F36596173E049167AFC624480BAD9CA4FA64A`（36812 B，见 §0）。引用这两条输出时**带时点并附夹具哈希**。

### 13.3 Dart 那条为什么更能覆盖风险（读法）

它刻意**不复用**本仓库的比对助手，因此能看见"实现自己的助手看不见"的差异：

- 自己实现 half-away-from-zero 的 `round6`（不调用被检查方的舍入工具）；
- 读端口的 **raw 字段**，**不经 `toJson()`** —— 否则实现的序列化/舍入会把差异抹平，测试就失去区分力；
- 按生成器的实际策略区分"生成器舍入过的字段"（`availability`、`drive`、`scores`、`a`、`q`）与"按原值写出的字段"（`dar_used`、`drive_edges.{ls,al,ms,contribution}`、`states[].al`）—— 后者若按舍入值比会产生 ~1.3e-7 的假不等；
- 集合/枚举类字段按集合相等判（含键集合，防字段漂移），浮点按 `rel<=1e-12 / abs<=1e-15`。

### 13.4 不可移植性与生命周期（重要）

- 两条脚本都把 **`E:/Document/MindNet`** 与**夹具绝对路径**硬编码在源码里：它们是**取证记录，不是产品工具**。换机器 / 换安装目录后直接跑会失败 —— 必须改写这两处常量，或按 `docs/VERIFICATION_PROTOCOL.md` §6.1–§6.5 的命令自建等价检查。
- 它们是**仓库外**产物（`C:\Users\Public\mindnet-verify\`）、**只读**、**不随仓库分发**：`git status` 里看不到它们，清理临时目录即消失。若目录被清理，按 `docs/VERIFICATION_PROTOCOL.md` §3/§6 的命令重建（§6.6 记录了其中一条的用法）。
- 只读性质：JS 侧只 `require` MindNet 源码并读夹具；Dart 侧只读夹具、只编译本仓库端口。两者都不写 MindNet 仓库（对照 §9 的铁律）。

### 13.5 闸门口径提醒

- 本文档过机械闸门时**必须带允许清单**（MindNet 仓库相对的 `src/`、`mechanisms/`、`tools/`、`conformance/`、`memory.dsr.js`、`engine.js`），否则这些**正确的**外部/相对引用会被判成"路径不存在"的误报 —— 按反幻觉技能自身的规则，应放行而不是删引用。
- **不要把契约的裸闸门计数当结论引用**：那个数字带时点、本轮已漂移两次（同一命令同一文件，不同时刻数字不同）。确需引用时，写"**带时点**的实测值"并当场复测，不要照抄任何转述。
