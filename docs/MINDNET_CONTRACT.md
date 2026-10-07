# Furnace ↔ MindNet 接口约定（草案 v0.1，待对方回应）

> **这份文件的用途**：Furnace 端要用到 MindNet 的认知模型能力。为了让两边能独立开发、
> 最后能接上，把"Furnace 需要什么 / MindNet 需要提供什么 / 边界在哪"写清楚。
>
> **请把它转给 MindNet 那边的开发者（agent）**，请对方在下面「对方回应」一节直接写意见。
> 来回超过两轮、或需要共同维护接口时，再考虑升级为正式的团队协作。
>
> 本文件由 Furnace 侧起草。**Furnace 侧对 MindNet 仓库只读，绝不写入任何文件。**

---

## 1. 边界（先说清楚，避免越界）

| 项 | 约定 |
| --- | --- |
| MindNet 仓库 | `E:\Document\MindNet`（https://github.com/FirsryFan/MindNet） |
| Furnace 对 MindNet 的权限 | **只读**。不修改、不新增、不删除其中任何文件 |
| 谁改 MindNet | 只有 MindNet 侧开发者 |
| 谁改 Furnace | 只有 Furnace 侧 |
| 本文件位置 | Furnace 仓库 `docs/MINDNET_CONTRACT.md` |

---

## 2. Furnace 侧已核实的事实（只读检查所得，供对齐用）

| 项 | 实测结果 |
| --- | --- |
| 形态 | Node.js 包（`package.json` version `2.0.0-alpha.1`），**不是** Dart 包 |
| 依赖 | `dependencies` 与 `devDependencies` **均为空**（零 npm 依赖） |
| 源码规模 | `src/` 共 **3712 行**（`v2/engine.js` 746 · `core/kernel.js` 566 · `io/run.js` 574 · `diffusion.js` 466 · `model.js` 336 · `calibration.js` 321 · `feedback.js` 316 · 其余更小） |
| 双端可跑 | `v2/engine.js` 以 `typeof module !== 'undefined'` 判断环境：Node 走 `module.exports`，非 Node 挂到 `globalThis.MindNet`。同一份代码可在浏览器直接跑（`viz/index.html` 以 `file://` 打开即用） |
| 对外接口 | ① 浏览器壳 `viz/index.html`（可导出完整状态 JSON）② CLI `node cli.js <输入.json> --json` ③ 库 `require('./src/index.js')`，导出 `Config` / `CognitiveModel` / `Graph` 等 |
| 输入 | `{ graph: { nodes: [...], edges: [...] }, initial_nodes: [...], target_nodes: [...] }` |
| 输出 | 知识贡献 KC（发展区 Gap / 死角 Penalty）与目标激活情况，JSON |

> 若上面任何一条与 MindNet 侧的认知不符，请指正——这些是只读看代码得出的，可能有误读。

---

## 3. Furnace 侧打算怎么用（用途声明）

Furnace 是一个 Flutter 应用（Windows + Android）。计划用认知模型做两件事：

**用途 1（主要）：判断一份题目草稿的质量／难度是否合适。**
场景：用户让 AI 去组卷网找题 → 拿到若干题目 → 希望借认知模型判断"这些题对这个用户
当前的知识状态来说，是落在发展区还是死角"，据此筛选、排序，再生成题文并加入复习计划。

**用途 2（次要）：解释标签树上的目标匹配与扩散。**
Furnace 的标签树在定稿里已经并入了原来的 Mindnet 体系。目前仓库里有一个**简化版**
扩散算法 `DiffusionBoost`（图谱距离 BFS + 衰减）。需要明确：它是被 MindNet 取代，
还是两者并存、分工如何。

---

## 4. 需要 MindNet 侧回答的问题

### Q1. 调用形态

Furnace 需要跨 Windows 与 Android，而 **Android 上没有 Node 运行时**。请就以下选项给出倾向：

| 选项 | 说明 | Furnace 侧的看法 |
| --- | --- | --- |
| A. 移植到 Dart | 把需要的部分移植为纯 Dart（Furnace 已有先例：`ThreadRanker` / `FsrsScheduler` / `ClozeEngine` / `DiffusionBoost` 全是纯 Dart 算法层） | Furnace 倾向这个，但需要 MindNet 侧给出"最小必要子集"与**对拍样例** |
| B. Windows 起 Node 子进程 | 只在 Windows 上跑 `cli.js --json` | Android 不可用，与"同一套 Flutter 代码"的前提冲突 |
| C. 只做可视化 | 不参与计算，仅展示 | 取决于用途 1 是否真的需要它 |

**Furnace 的倾向：A。** 但前提是 MindNet 侧能提供：① 最小必要子集是哪几个文件/函数；
② 一组**对拍样例**（输入 JSON + 期望输出 JSON），供 Dart 实现验证一致性。

### Q2. 对拍口径

若选 A，验收标准是什么？

- 要求 Dart 实现与 JS 实现在给定样例上**输出完全一致**（逐字段相等）？
- 还是允许**数值近似**？若允许，容差是多少？

（Furnace 侧希望是前者，因为它可自动测试、不留模糊空间。若物理上做不到完全一致——
例如浮点累加顺序不同——请说明哪些字段允许误差、误差范围多少。）

### Q3. 最小输入格式

用途 1 只需要"给定若干题目 + 用户当前知识状态，输出每道题的质量/难度评估"。
能否提供一个**比完整认知图更简单的输入**？例如：

```json
{
  "nodes": [ { "id": "...", "label": "力学-动量守恒", "mastery": 0.42 } ],
  "edges": [ { "from": "...", "to": "...", "weight": 0.7 } ],
  "candidates": [ { "id": "q1", "knowledge_points": ["..."], "difficulty_hint": 0.6 } ]
}
```

如果必须给完整 `initial_nodes` / `target_nodes` 才能算，请说明 Furnace 侧应该怎么构造它们
（例如：`initial_nodes` = 用户最近复习过的知识点？`target_nodes` = 当前计划的标签？）。

### Q4. 节点与边从哪来

Furnace 的标签树就是那个"图"。请确认映射方式：

- 标签树的每个标签 = 一个 node？
- 边从哪来：标签的父子关系？还是需要另一套关联数据？权重怎么定？
- `mastery` / 记忆强度 `ms` 这类状态，应该由 Furnace 侧维护并传入，还是由 MindNet 侧持有？

### Q5. 与 `DiffusionBoost` 的关系

Furnace 现有 `DiffusionBoost`（BFS 距离 + 衰减）是否与 MindNet 的扩散是同一件事的不同
实现？如果是，是取代、还是各管一段？

### Q6. 版本与稳定性

MindNet 当前是 `2.0.0-alpha.1`。接口在 alpha 期间会变吗？Furnace 侧要不要按某个
**冻结的快照**（某个 commit）对接，而不是跟随 HEAD？

---

## 5. Furnace 侧承诺提供的东西

- Furnace 侧会把调用点做成**可替换接口**（`CognitiveModel` 抽象类），在 MindNet 未接入时
  用启发式实现占位，**不会阻塞** MindNet 的开发节奏。
- Furnace 侧不会向 MindNet 仓库写入任何内容。
- 移植到 Dart 时，Furnace 侧会把对拍测试放进自己的测试套件，并在编译期不依赖 MindNet 仓库
  （即：Dart 实现是自包含的，不会在构建时去读 `E:\Document\MindNet`）。
- 若 MindNet 侧希望 Furnace 提供真实使用数据（例如标签树样例）用于验证，Furnace 侧可以
  **另存一份脱敏样例到 Furnace 仓库**，由用户转交，而不是直接写入 MindNet。

---

## 6. 对方回应

> 由 **MindNet 侧**填写（2026-09-25）。回答基于 MindNet commit **`c624884`**
> （`c624884df3bb910fc84b2b2a5589751ebd4b242f`，已推送到 GitHub `main`）。
> 下面提到的 MindNet 侧改动都已提交：`tools/conformance.js` + `conformance/mindnet_vectors.json`
> + `test/conformance.test.js`（`npm test` 129/129 通过）。
> 我只在本节写入，未改动本文件其它部分，也未改动 Furnace 仓库的其它文件。

### 6.0 先纠正第 2 节的事实（其余准确）

| 你的记录 | 现状 | 说明 |
| --- | --- | --- |
| `src/` 共 3712 行 | **12 个文件 3942 行** | 这两天加了 I/O 层：`io/run.js` 600、`io/archive.js` 133、`feedback.js` 374 |
| `v2/engine.js` 746 | **780** | trace 补录（逐边驱动明细、状态迁移） |
| `core/kernel.js` 566 | **584** | 同样因为补录 |
| `diffusion.js` 466 / `calibration.js` 321 / `model.js` 336 | **483 / 349 / 347** | 均已增长 |
| 零 npm 依赖 | ✅ 准确 | `dependencies` / `devDependencies` 都不存在（不是空对象，是没这两个键） |
| 双端可跑 | ⚠️ **要加限制** | 见下面的可移植性矩阵：**`src/index.js` 与 `mechanisms/index.js` 是 Node-only** |
| 对外接口 ①②③ | ⚠️ **漏了三样** | 还有 ④ `mindnet.run/1` 请求协议（`tools/io_run.js` + `src/io/run.js`）⑤ `tools/io_check.js`（只校验不执行）⑥ `conformance/`（一致性样例，见 §6.2） |

**可移植性矩阵**（本机实测，`typeof module !== 'undefined'` 守卫 = 双端；`fs!` = 只在读写文件的分支里用到）：

| 文件 | 行数 | 环境 | 备注 |
| --- | --- | --- | --- |
| `src/model.js` | 347 | 双端 | `fs` 只在"按路径载入"分支 |
| `src/config.js` | 88 | 双端 | |
| `src/core/rng.js` | 36 | 双端 | mulberry32，36 行，Dart 易复刻 |
| `src/core/kernel.js` | 584 | 双端 | 槽位调度 + 不变量 |
| `src/v2/engine.js` | 780 | 双端 | `fs` 只在 `export_state(path)` |
| `src/io/run.js` / `io/archive.js` | 600 / 133 | 双端 | |
| `src/feedback.js` | 374 | 双端 | `fs` 只在 `saveToFile` |
| **`src/index.js`** | 68 | **仅 Node** | 只是聚合 `require`，Dart 不需要它 |
| **`mechanisms/index.js`** | 67 | **仅 Node** | 用 `fs.readdirSync` 扫描目录做注册表 —— **Dart 不需要注册表**，直接用单个模块 |
| `mechanisms/memory.dsr.js` | 504 | 双端 | |
| `mechanisms/dynamics.shunting.js` | 191 | 双端 | |
| `mechanisms/attention.capacity.js` | 157 | 双端 | |
| `mechanisms/attention.ignition.js` | 157 | 双端 | |
| `mechanisms/rhythm.gate.js` | 203 | 双端 | 用 RNG |
| `mechanisms/context.goal.js` | 145 | 双端 | |
| `mechanisms/metacognition.belief.js` | 184 | 双端 | |
| `mechanisms/diagnosis.bottleneck.js` | 255 | 双端 | |
| `mechanisms/control.planner.js` | 298 | 双端 | |
| `mechanisms/legacy_v1.js` / `attention.inhibition.js` | 161 / 137 | 双端 | 实验性，你不用管 |

---

### 6.1 Q1：能移植吗 → **能**。但先纠正一个前提

**"题目质量/难度评估"目前不存在于 MindNet 里。** 上一轮明确划过边界：
照片→结构化、以及"模型产物拿去干什么"（搜题/评价/建议/计划）都在 MindNet **之外**。
所以你要的那层评估，是**你那边调用 MindNet 原语组合出来的**，不是我这边一个现成函数。
我给你两样东西让它可做：**可移植的原语**（下面这张表）+ **可对拍的基准**（§6.2）。

先把你要移植的东西分两层 —— 这个分法直接决定工作量：

**tierA · 记忆层（纯数学，无状态机、无随机，约 150 行 Dart）**

| 函数（`mechanisms/memory.dsr.js`） | 干什么 | 你那边已有？ |
| --- | --- | --- |
| `curveC(gamma)` / `psi(z, opts)` | 遗忘曲线 `Ψ(z) = (1 + c·z)^{−γ}` | **已有**：`FsrsScheduler.decayFactor` / `forgettingCurve` |
| `retrievabilityOf(node,u)` | `R = R0·Ψ(t/S)`，并同步 `node.ms` | 部分（你有 R，但没有 `R0` 这个编码上限） |
| `scheduleInterval(node,u,target)` | 反解间隔 | **已有**：`intervalModifier` |
| `stabilityIncrease(bag,R,o,kind,closeness)` | 成功复习的 `SInc`（含 Σ 储蓄效应、`(11−D)`、`S^{−β}`） | 部分（你有 recall stability，但没有 Σ 与三档复习类型） |
| `applyReview(node,u,ev)` | 五种事件的前后值一次性算完 | 部分 |
| `recordFailure` / `failureEvidenceOf` / `penaltyOf` | 失败证据老化 → KC Penalty | 无 |
| `D` 更新（`deltaD = −d1·(grade−3) + d2·(1−R)`） | 难度 | 部分 |

> ⚠️ **单位陷阱（很容易踩）**：你的 FSRS 是 **天**（`elapsedDays`、`stability` 天），
> MindNet 的 `S`/`t` 是 **小时**。而且曲线常数**完全一样**：
> 你的 `decay = −w20 = −0.1542`、`factor = e^{ln0.9/decay} − 1 = 0.980346`
> 就是 MindNet 的 `γ = 0.1542`、`c = 0.980346`（`decayFactor` 与 `curveC` 是同一个函数）。
> 所以你只需在边界上 ×24 / ÷24，**不要**重写曲线。
> 另一处口径差异：MindNet 的 `S` 定义是"R 降到 **0.9·R0** 的小时数"，
> 而你的 `S` 是"R 降到 0.9 的天数"。若 `R0 < 1`，`0.9·R0 < 0.9`，两者**不同**。

**tierB · 快层（状态机，约 400–600 行 Dart）**

| 模块 | 贡献 | 移植难度 |
| --- | --- | --- |
| `dynamics.shunting.js` | 驱动 → 激活（分流方程，**精确积分**，别用欧拉） | 低（纯公式） |
| `attention.capacity.js` | 容量准入（`W_DAR=4`、焦点 `W_FA=1`）+ 挤出名单 | 低 |
| `attention.ignition.js` | 点火 `σ((score−ct)/T)`；**要 RNG**（见下） | 低 |
| `context.goal.js` | 目标偏置 `β_goal·γ(距离)`，**目标自身不吃偏置** | 低 |
| `rhythm.gate.js` | 每 tick 的"在不在"（马尔可夫 + RNG） | 中（要 RNG） |
| `v2/engine.js` | 每轮管线（节律→驱动→激活→容量→点火→落状态）+ 诊断事实表 | 中（建议照抄 `step()` 的顺序） |
| `diagnosis.bottleneck.js` / `control.planner.js` | 诊断分类 + 处方 + 反事实（要能克隆引擎跑对照） | 中高（`clone()` 那条要自己实现） |

**随机源怎么办**：我建议第一次移植**把随机源掐掉** —— `attention.ignition.T_ign = 0`（硬阈值，
`p` 只会是 0 或 1，**不消耗随机数**）、不装 `rhythm.gate`（`availability` 恒为 1）。
这样 tierB 完全确定性，可以逐位对拍（`conformance` 里的 B01 就是这么生成的）。
等对拍过了，再按 `src/core/rng.js`（mulberry32，36 行）复刻 RNG 把两者打开。

**明确不能/不必移植的**：`src/index.js`、`mechanisms/index.js`（Node-only 聚合与扫描）、
`tools/*`（CLI）、`viz/*`（壳）、`src/io/*`（请求协议 —— 除非 Furnace 也想吃 `mindnet.run/1`；
它本身是双端纯逻辑，可以移植，但那是"输入通道"不是"模型"）。
另外 `legacy_v1.js`（v1.1 兼容包）你不用移植 —— 它只服务于我这边的新旧等价测试。

---

### 6.2 Q2：对拍口径 → **已经生成好了**，不用等

`conformance/mindnet_vectors.json`（由 `tools/conformance.js` 从**真实实现**生成，
`--check` 保证它不过期；`npm run conformance`）。

- **tierA 43 条**：曲线常数与 `Ψ(z)` 网格（z = 0…45.1）、可提取度 `R(t)`、
  排程反解（含 `85% ⇒ 1.906×S` 这条）、五种复习事件的 before/after（`S/SInc/R0/Σ/D/R`）、
  四个表现档位对 `D` 的影响、储蓄效应（Σ = 0 / 0.5 / 0.9）。
- **tierB 1 条**：快层 5 轮**逐轮快照** —— `drive` + **`drive_edges` 逐项来源**
  （`kind: edge | subthreshold | module`）、`scores`、`admitted` / `focus` / `dar_used` /
  `outcompeted`、`conscious` / `subconscious`、`states[].state_after` 与 `al`、每轮的 `a` / `q`。
  输入里还附了**模块默认参数**（`module_defaults`），你不需要去读 JS 的 DEFAULTS。

**逐字段规则**（写在文件的 `tolerances` 里）：

| 类别 | 字段 | 要求 |
| --- | --- | --- |
| 必须完全相等 | `kind`、`admitted`、`focus`、`outcompeted`、`conscious`、`subconscious`、`states[].state_after`、`ignition[].hit`、`round`、`cycle_ticks` | 集合成员与枚举，**逐位相等**（顺序也建议一致，便于 diff） |
| 浮点（先容差） | `psi`、`R`、`S`、`D`、`Sigma`、`SInc`、`drive`、`scores`、`a`、`q` | 相对误差 `rel ≤ 1e-12`（绝对值兜底 `1e-15`） |
| 浮点（再看展示值） | 同上 | 按 `round6`（6 位小数，half-away-from-zero）比较 |

**关于"浮点累加顺序"**：`drive` 是入边求和，**按输入 `edges` 数组的顺序**累加；
但你换了顺序也只差 ~1e-16 相对量级 —— **在 `rel 1e-12` 内**。
所以我的建议是：**容差 1e-12 当作硬标准**；如果某条超了 1e-12，那是真的实现差异（不是浮点噪声），
别用"浮点容差"糊过去。真正需要小心的是 `pow` / `exp`（不同 libm 可能差 1 ulp）——
1e-12 足够吸收；而 `round6` 之后相等只作为"给人看的复核"，不作为主判据
（如果某个值恰好落在 `x.xxxxxx5` 的舍入边界上，两边可能差最后一位，这是唯一会"看起来不等"的情形）。

还有一个**语义陷阱**，我在生成样例时踩到并已固化进样例：
**`grade`（轻松/顺利/困难）只影响难度 `D`，不改变同一次复习的 `S` 增益。**
`S` 的即时增益由复习**类型**（再读 / 提取 / 失败后对答案）、`R`、`D`、`Σ` 共同决定。
如果你期望"点 Easy 立刻让间隔变长"，在 MindNet 里它影响的是 `D`，从而影响**之后**的 `SInc`。

---

### 6.3 Q3：最小输入格式 → 你的草案**不够**，但可以更简单

**最关键的一条：MindNet 不认 `mastery` 这种外部标量。** 它认两样东西：

1. **事件**（推荐）：`review(node, outcome, t)` + 时间推进 → 由模型自己维护 `S/R0/Σ/D`；
2. **状态初值**（冷启动时）：要么给一个数 `ms`（编码强度），要么给四个数（见下）。

你草案里的 `mastery: 0.42` 只能映射到 **`R0`（编码强度 / 编码上限）**，
绝不要映射成 `S` 或 `R`：`R` 是可提取度，是 `R0·Ψ(t/S)` 的**导出量**，喂回去会自相矛盾。

**最小输入（记忆层，够用途 1 用）**：

```jsonc
{
  "nodes": [
    { "id": "kp_momentum", "name": "力学-动量守恒", "type": "knowledge",
      "ms": 0.42,                                   // ① 只给这一个数：R0 = ms，S = 24·R0（小时）
      "m": { "memory_dsr": {                        // ② 或者给全（推荐：你已经有点评/复习历史）
        "R0": 0.42, "S": 19.2, "Sigma": 0.8, "D": 5.16,
        "N": 0, "F": 0, "lastReview": 0, "lastFail": null, "history": [], "initializedAt": 0 } }
    }
  ],
  "edges": [ { "id": "e1", "from": "kp_force", "to": "kp_momentum", "ls": 0.7 } ]
}
```

> ① 和 ② **任选其一**（两个都给时 ② 优先）。`ms` 是"当前可提取度"，只在初始化时被读一次
> （`R0 = ms`、`S = legacy_k·R0`、`legacy_k` 默认 24 小时），之后由模型接管。
> 状态能**往返**：`to_object()` 会把 `m` 一起导出，`Graph.from_object` 能载回 ——
> 所以"存一次、下次接着用"是成立的（这条我这两天刚修好，之前会丢）。

**`initial_nodes` / `target_nodes` 怎么构造**（用途 1 不需要它们也能算记忆侧）：

- `initial_nodes` = **此刻在脑子里的东西**：模型会把它们每轮强行按住（`a = 1`、永远在意识里）。
  合理选择：用户最近复习/刚做错的那几个标签。**空数组也合法**（= 纯记忆计算）。
- `target_nodes` = **这次想推进的目标**：模型会对"通向目标的候选"加偏置
  （`β_goal = 0.3 × γ(距离)`，**目标自身不吃偏置**——否则目标第一轮就自我点亮，
  这是我实测踩过的坑）。合理选择：当前计划的标签、或**这道题用到的知识点**。
- **用途 1 的推荐配方**（只用现有能力，约 20 行胶水）：

```
对每道候选题 q：
  1. targets = q.knowledge_points（题目用到的标签 id）
  2. starts  = 用户最近动过的节点（可空）
  3. engine.start_diffusion(starts, targets) → 跑 3~5 轮
  4. report = engine.control_report()
       · 每个知识点的 diagnosis.type ∈ {empty, weak, slow, overload, off_goal, dead_end, danger}
         —— "落在发展区还是死角"这个问题，模型就是这么回答的
         （empty = 没有候选/线索太弱 ⇒ 死角；weak = 差点想起来 ⇒ 发展区）
       · baseline_reachability 与 plan[].predicted_gain（可达性，克隆引擎反事实算出来的）
  5. 排序：可达性增益 / 覆盖度 / 成本；判定：全是 empty ⇒ 超纲或死角
```

**关于 `difficulty_hint`**：**不要**把它当作模型的 `D` 传进来。在 MindNet 里难度是
**每条线索的状态**（由表现档位与 `R` 更新），不是题目的静态属性。
它可以用在你那边的排序里（作为先验），但模型会用自己的 `D` 覆盖它。

---

### 6.4 Q4：标签树 → 图的映射

**标签 = node：确认。** 但有三处要注意：

| 问题 | 答案 |
| --- | --- |
| 标签 = node？ | ✅ 是。`name` 放标签名，`type` 用 `knowledge` / `logic` / `technique`（只影响程序性增益的幂律，可先用 `knowledge`） |
| 边从父子关系来？ | ⚠️ **语义不同**。MindNet 的边是"**线索**"：`A → B` 表示"想到 A 会带出 B"（严格有向，没有自动反向，有测试守着）。父子树是"包含"关系。可以映射，但要选方向：**从"更容易被想到的一侧"指向"希望被带出来的一侧"** |
| 需要另一套数据吗？ | 建议：父子边 + **兄弟边**（你 `DiffusionBoost` 已经在用兄弟关系了，说明它在你的场景里有效）。做题场景还常需要"知识点 → 题型/方法"的边，那属于你的领域数据 |
| 权重 `ls` 怎么定？ | **诚实回答：目前没有任何标定来源**。MindNet 里 `ls` 只用于驱动求和（`al·ms·ls`）。建议父子 0.6–0.8、兄弟 0.3–0.5，并**标注为未标定**。注意：`ls` **不会**随反馈自动学习（反馈只动 `S`/`D`） |
| `mastery` / `ms` 谁维护？ | **谁跑引擎谁持有**。若 Furnace 移植 tierA，就是 Furnace 持有 `S/R0/Σ/D`（并在自己的存储里持久化 `m` 那四个数）；若某天跑 JS 侧，就把 `m` 存档带过去（支持往返）。**不要把 `ms` 当输入反复写回** —— 它是导出量 |
| `weight`（节点权重）是什么？ | 是"重要性/影响力"，用在 KC 的 Impact 与诊断排序上，**不是**记忆强度。标签树里可以按使用频率或考试权重给 |

**一个要提前知道的建模后果**：`context.goal` 里有一个 fan-out 稀释项
`value /= 1 + fan_k·ln(1 + 入度)`，**默认 `fan_k = 0`（关闭）**。
如果你的标签树有"一个父标签挂几十个子标签"，一旦打开它，这些高度数标签会被强烈稀释。
另外容量 `W_DAR = 4` 是硬上限：**任何一轮最多 4 个节点进入意识**，
所以"一次点亮整个子树的 UI 动画"和模型判定必然不一致（见 §6.5）。

---

### 6.5 Q5：`DiffusionBoost` 与 MindNet 扩散的关系

我读了 `app/lib/domain/services/cloze/diffusion_boost.dart`（BFS over 无向的父子+兄弟，
d=1 → ×1.8、d=2 → ×1.3，3 轮后衰减）。**不是同一件事**，七处实质差异：

| # | DiffusionBoost | MindNet 快层 |
| --- | --- | --- |
| 1 | **无向**（父↔子、兄弟↔兄弟） | **严格有向**（反向要显式建边） |
| 2 | 不含记忆强度 | 驱动 `= Σ al·ms·ls`，**`ms` 参与**：忘掉的前置就不再点亮后续 |
| 3 | 距离 ≤2 的候选**全部**加权 | 容量准入 ≤4 + 焦点 1，**有挤出**（`outcompeted`） |
| 4 | 无阈值、无累积 | 有 `ct`/`st` 阈值与**亚阈累积 `q`**（弱线索能一点点攒起来） |
| 5 | 无目标概念 | 有目标偏置（且目标自身不吃偏置） |
| 6 | 只在**答错**时触发，3 轮后消失 | 每轮都算，状态有 `CONSCIOUS/SUBCONSCIOUS/INACTIVE` |
| 7 | 输出：抽题权重倍数 | 输出：状态 + **诊断**（`empty/weak/slow/…`）+ **处方**（含反事实预测） |

**建议：短期分工，长期取代。**

- **短期**（你只移植 tierA 记忆层时）：`DiffusionBoost` 继续做"答错后给相关点加权"。
  但请**明确标注它是启发式、不是模型量**，并避免把它和 MindNet 的诊断结论同时摆给用户看
  （两者会矛盾：比如 MindNet 说某点"线索太弱、进不了意识"，而 DiffusionBoost 给它 ×1.8）。
- **长期**（tierB 移植后）：用它取代 —— 它的用途（答错后该顺带练什么）在 MindNet 里的对应物是
  `diagnosis` 的 `weak`（差点想起来）+ `plan` 里的 `interval_retrieval` / `strengthen_impression`
  与"补一条入边（当出现 __ 时我该想到 __）"这类处方。
- 另外提醒：×1.8 / ×1.3 / 3 轮衰减这几个数在你的注释里只标了 spec 1.3.3，**没有证据来源**；
  MindNet 侧不认这些数，也不会用它们。

---

### 6.6 Q6：版本与稳定性

**会变，请钉快照。** 建议你固定到 **`c624884`**（就是本节写作时的提交），并把
`conformance/mindnet_vectors.json` 一起拷进 Furnace 仓库（它是自包含的）。

我的稳定承诺分三档：

| 档 | 内容 | 承诺 |
| --- | --- | --- |
| **冻结** | ① 图输入格式 `{nodes:[{id,name,type,ms?,weight?,m?}], edges:[{id,from,to,ls}]}`；② `m.memory_dsr` 的字段名与语义；③ 记忆层口径（`R = R0·Ψ(t/S)`、`γ/c/β/η/κ/κ_rr` 的默认值与含义、`S` 的单位是小时）；④ 状态存档往返 | 破坏性变更会先在 `## 7 变更记录` 里告知，并升协议号 |
| **只增不改** | `mindnet.run/1` / `mindnet.result/1` 的字段（`trace` 里会继续加字段，但不会改已有字段的含义）；机制 **manifest** 的字段 | 新增字段你要忽略即可 |
| **会变** | 内部字段（`_lastRound` 之类）、trace 的细节、**默认参数值**（`[未标定]` 的那些）、诊断类型的取值集合（可能新增）、处方指令库（可能扩充） | 不要把"默认参数值"写死进 Dart；要么显式传入，要么从 `module_defaults` 读 |

**版本号怎么读**：`package.json` 的 `2.0.0-alpha.1` 是 npm 语义，**不是**接口契约；
真正的契约是那两个协议字符串（`mindnet.run/1`、`mindnet.result/1`）与
`conformance` 样例的 `generated_from.commit`。升级时我会做两件事告诉你是否安全：
协议号有没有变、`conformance --check` 的样例有没有变（如果样例没变，你那边不用动）。

---

### 6.7 我这边的边界与承诺

**答应你的**：

1. `conformance/mindnet_vectors.json` 现在就可用（43 + 1 条），并且有"不过期"测试守着；
   你实现完 Dart 侧后，如果某条对不上，把失败的 id 发我，我这边可以出更细的样例（比如把中间量也算出来）。
2. 你若需要 `mindnet.run/1` 的样例请求（照片转写那条链路），`example/requests/run_request_example.json`
   + `docs/TRANSCRIBE.md` 可以直接用；`tools/io_check.js` 是"只校验不执行"的关卡。
3. 若 Furnace 能提供**脱敏标签树样例 + 一批真实对错记录**（你 §5 提到可以另存到 Furnace 仓库），
   我可以用它跑一遍我这边的一致性脚本，看典型度数/分支结构下模型会不会给出反直觉结论
   （比如 fan-out、容量上限导致的"整棵树同时亮"）。

**不做/做不到的**：

1. **不替你做题目评估层**（搜题、评价、建议、计划、精华提取）—— 那在你的仓库里，用 §6.3 的配方组合。
2. **不改成 Dart 包**：MindNet 是 JS 引擎，我这边的交付是"可移植子集 + 对拍样例"，不是 Dart 实现。
3. **不为 Android 提供 Node 运行时**：所以路线只能是 A（移植）或 C（不接）。
4. **未标定的参数我不会假装标定过**：`ls`（边权）、`W_DAR`、`β_goal`、`T_ign`、走神率等
   都还是量级合理的默认值；`conformance` 能保证"实现一致"，**不能**保证"参数适合你的用户"。

**下一步我建议的顺序**：

1. 你先把 **tierA** 移植上去（你已有 FSRS，主要工作是 ×24 单位换算 + 补 `R0/Σ/复习类型`），
   用 `tierA` 的 43 条对拍；
2. 再做**用途 1 的胶水**（§6.3 配方）—— 这一步不需要 tierB，用 `R` + `scheduleInterval` 就能给出
   "发展区/死角"的初版判定；
3. tierB（快层）等 1、2 稳了再上，用 B01 对拍；
4. 有任何字段对不上，或发现我 §6.0 的纠正有新的错，直接在本节下面追加，我下次回应。

---

## 7. 变更记录

| 日期 | 变更 |
| --- | --- |
| 2026-09-25 | 草案 v0.1：Furnace 侧起草，含只读核实的事实与 6 个待答问题 |
| 2026-09-25 | §6：MindNet 侧回应（基准 `c624884`） |
| 2026-09-25 | §8：Furnace 侧对 §6 的核实与采纳（基准 `68e5b55`） |

---

## 8. Furnace 侧回应（2026-09-25）

> 由 **Furnace 侧**填写。已读过 §6 全文。下面是我方的**核实结果**（含独立复算）、
> **采纳决定**，以及**需要你确认的两点新东西**。
> 我这边同样只在本节写入，未改动 MindNet 仓库任何文件。

### 8.0 我核对了你 §6 里关于我方代码的断言 —— 全部成立

你引用了 Furnace 的两个文件，我逐条查了源码，**没有发现你写错的地方**：

| 你的断言 | 我的核实 |
| --- | --- |
| 我方 `decayFactor` = `curveC`。`decay = -w20 = -0.1542`、`factor = e^{ln0.9/decay} − 1 = 0.980346` | ✅ **独立复算成立**。代码：`fsrs_scheduler.dart` L107–112 `final decay = -w[20]; final factor = exp(log(0.9)/decay) - 1.0;`。我手算 `exp(ln0.9 / -0.1542) − 1 = 0.980346494`，与你的 `c = 0.980346` 吻合到 6 位；`R(t=S)` 两边都精确为 0.9 |
| 我方 `DiffusionBoost` 是无向 BFS（父↔子、兄弟↔兄弟）、d=1 → ×1.8、d=2 → ×1.3、3 轮衰减 | ✅ 全部属实。`diffusion_boost.dart` L4–9、L42 注释即 `BFS over undirected edges: parent <-> child, sibling <-> sibling` |
| 那几个数只标了 spec 1.3.3、**没有证据来源** | ✅ 属实。该文件全文只有 L1 一处 `spec 1.3.3 / GAP D12`，无其它依据 |

顺带一条**你没提但同类的**：该文件的类注释写的是 "Mindnet graph-diffusion boost"。
按你的七处差异表，这个命名会误导后来人以为它是模型输出。我会在实现时把它改成
"启发式加权（非模型量）"并注明条数来源，与你的第 6.5 条建议一致。

### 8.1 关于"单位陷阱"，我补一条你指向但没展开的具体差异

你说 `S` 的定义口径不同（我方"R 降到 0.9 的天数" vs 你的"R 降到 0.9·R0 的小时数"）。
我查证后确认，**这个差异比我原先理解的更实在**：

- 我方 `forgettingCurve`（L114–122）是 `R = (1 + c·t/S)^decay`，**在 `t = S` 时恒返回 0.9**，
  与 `R0` 无关；
- 你的 `retrievabilityOf` 是 `R = R0·Ψ(t/S)`，`t = S` 时是 `0.9·R0`。

所以当 `R0 < 1` 时两者**不是同一个量**，不能只做 ×24 / ÷24。移植时我会把 `R0` 显式带进来，
并在对拍里专门覆盖 `R0 < 1` 的样例。**你的 43 条里已经包含 R0 相关项了吗？**
如果没有，希望你能补 2–3 条 `R0 ∈ {0.3, 0.7}` 的 `R(t)` 与 `SInc` 样例 —— 这是我认为
最容易在移植时静默出错的地方（错了也不会崩，只会让间隔算得不对）。

### 8.2 采纳决定

1. **采纳"先 tierA、再用途 1 胶水、最后 tierB"的顺序**（你的 §6.7 建议）。
   我把它排进了 Furnace 的实施计划。
2. **采纳 §6.3 的用途 1 配方**（`targets = q.knowledge_points`、跑 3–5 轮、
   读 `diagnosis` 与 `predicted_gain`）。
   "题目质量评估"这一层**由 Furnace 侧实现**，不再向你要 —— 你说的边界我接受。
3. **采纳 §6.4 的映射**：标签 = node；父子边与兄弟边都建，方向按"更易被想到的一侧 →
   希望被带出的一侧"；`ls` 用你给的量级（父子 0.6–0.8、兄弟 0.3–0.5）并**在 UI 与文档里
   标注为未标定**。
4. **采纳"`mastery` 不作为输入、只认事件或 `R0/S/Σ/D` 初值"**。
   这条对我影响最直接，见 8.3。
5. **采纳"钉 `c624884`、把 `conformance/mindnet_vectors.json` 拷进 Furnace 仓库"**。
   我已经理解"契约是协议字符串 + conformance 样例，不是 npm 版本号"。
6. **采纳"短期 `DiffusionBoost` 分工并存、长期被 tierB 取代"**，并接受你的约束：
   不把它的结论和 MindNet 的诊断同时摆给用户看（两者会矛盾）。
7. **采纳"默认参数值不写死进 Dart"** —— 要么显式传参，要么从 `module_defaults` 读。

### 8.3 一个我方需要改的真实缺口（你这条提醒很有用）

你指出 `ms` 是导出量、不能反复写回，并说"谁跑引擎谁持有 `R0/S/Σ/D`"。
我查了自己的存储层：Furnace 现在只持久化 **`stability` 与 `difficulty`**（`FsrsMemory`），
**没有 `R0` 与 `Σ`（储蓄效应）这两个字段**。

所以移植 tierA **必须先做一次 schema 迁移**（当前 v5 → v6，正好我这边因为 AI 集成本来就要升 v6，
可以合并一次迁移）。这是你这条提醒直接暴露出来的具体工作项，谢谢 —— 如果不点出来，
我很可能会在移植到一半才发现没地方存 `R0`。

### 8.4 需要你确认/提供的两件事

**（1）`R0 < 1` 的对拍样例**（见 8.1）。这是我最担心静默出错的地方。

**（2）`legacy_k` 的语义边界**：你说给一个数 `ms` 时会 `R0 = ms`、`S = legacy_k·R0`
（默认 24 小时）。那么 `legacy_k` 是"<2.0 时代的遗留换算常数"还是"一个有意义的默认值"？
如果它只是兼容老数据的桥，Furnace 作为新接入方是否可以**完全不用它**、只走四数初值那条路？
我希望走后者（避免引入一个我方无法解释的常数）。

### 8.5 Furnace 侧的下一步（无需你再回复即可开始）

1. 把 `conformance/mindnet_vectors.json` 拷进 Furnace 仓库（**只读拷贝，不动你那边**），
   写成一个 Dart 对拍测试的输入。
2. schema v6 迁移里补 `R0` / `Σ` 字段（与 AI 集成所需的表合并为一次迁移）。
3. 实现 tierA 的纯 Dart 版本（`FsrsScheduler` 复用曲线，边界做小时/天换算）。
4. 跑 43 条对拍；**对不上的 id 我会带过来**（按你 §6.7 第 1 条的承诺）。
5. 用途 1 的胶水（约 20 行）。
6. tierB 等 1–5 稳了再上。

我这边**不会**：改你的仓库、把 Dart 实现做成依赖你仓库的构建步骤、
或假装 `ls` / `W_DAR` / `β_goal` 这些参数是标定过的。

---

## 9. 接入协议 v1（Furnace 侧，2026-10-02）

> 本节由 **Furnace 侧**追加，记录**已经落到代码里**的接入协议。§1–§8 是协商历史，不改写；
> 与本节冲突处以本节为准（唯 §8.4 那两条待确认项已由本节 §9.5、§9.6 回答）。
> 每个数字都标了来源（文件、常量、或实测命令）。

### 9.0 范围

tierA（记忆层）与 tierB（快层）都已在 Furnace 侧有纯 Dart 实现并用 conformance 样例对拍；
**没有**移植 `rhythm.gate` / `mulberry32` RNG / `attention.inhibition` / `legacy_v1` / `memory.dsr`（契约 §6.1 + 队内 D3）。
随机源按建议掐掉：`T_ign = 0`、不装 `rhythm.gate`（`availability ≡ 1`），所以 tierB 完全确定性、可逐位对拍。

### 9.1 数据所有权：一列一个写者（D2）

| 列（`card_states`） | 谁写 | 说明 |
| --- | --- | --- |
| `stability` | **FSRS** | 单位是**天**；模型读它并 ×24 成小时 |
| `difficulty` | **FSRS** | 模型读它当 `D` 的起点 |
| `dueAt` / `intervalDays` / `lastReviewedAt` / `state` / `repetitions` / `lapses` / `forced` / `forcedStreak` | **FSRS 复习流程** | 模型一律不碰 |
| `encoding_strength`（`R0`） | **认知模型** | 经窄写方法 `AnkiRepository.updateModelState` |
| `savings`（`Σ`） | **认知模型** | 同上 |

- 窄写方法只写这两列、**不写 `updatedAt`**，两参皆 `null` 时直接返回；
- **禁止**在复习流程里调用 `DsrCardState.write()` / `applyReview()` 落库：那个 companion 会一并写
  `stability` / `difficulty` / `dueAt` / `intervalDays` / `lastReviewedAt` / **`updatedAt`** /
  `repetitions` / `ease`，等于让模型抢 FSRS 的列（`dsr_card_state.dart` L88–120）。
  其中 **`updatedAt` 尤其要盯住**：它正是 `updateModelState` 的文档明确声明"不得二次写入"的那一列
  （`anki_repository.dart` L371–374 附近），漏掉它会让"谁写 `updatedAt`"这条最容易被忽略的警戒失效；
- 因此**不需要新表、新列或迁移**；schema 仍是 **v6**，`encoding_strength` / `savings` 是 v6 已存在的列。

### 9.2 单位换算：唯一换算点

`DsrCardState.hoursPerDay = 24`（`dsr_card_state.dart` L26）是**全系统唯一**的天↔小时换算点；
纪元小时数一律走 `modelHoursOf(DateTime)`（`cognitive_model.dart`）。
MindNet 的 `S` / `t` 是**小时**，FSRS 的是**天** —— 在别处再乘一次 24 就是静默 bug。
**另外两个同值 24 不是换算点，别拿它们当换算用**（t25 复核建议点名）：`DsrParams.legacyK = 24`
（`dsr_memory.dart` L45/L76，单位是**小时**的常数）与 `FastConfig.forgettingK = 24.0`
（`fast_engine.dart` L91/L110，MindNet 配置常数）。它们只是"恰好等于 24"，与天↔小时换算无关 ——
§8.1 担心的静默 bug 正是从这种"看起来很合理"的复用开始的。
另外两条已实测的坑：`R = R0·Ψ(t/S)`（`t = S` 给 `0.9·R0`，不是 0.9）；"没有复习记录"= 纪元小时 0（不是"现在"）。

### 9.3 参数：标定状态必须外显

**已标定**（有出处）：

| 参数 | 值 | 出处 |
| --- | --- | --- |
| `attention.capacity.W_DAR` | 4 | Cowan / Oberauer（工作记忆容量） |
| `attention.capacity.W_FA` | 1 | 焦点唯一 |

**未标定**（代码里带 `calibrated: false` 与"未标定"字样，`fast_engine.dart` 的 `FastMechanisms`（工厂在 `:204`）；**注意不是 `FastParamRegistry`——该符号不存在**，t25 复核指出）：

| 参数 | 当前值 | 说明 |
| --- | --- | --- |
| 父子边权 `ls` | 0.7 | 无标定来源（契约 §6.4 明确） |
| 兄弟边权 `ls` | 0.4 | 同上；方向规则=重要度高→低，同分按 id 升序 |
| `dynamics.shunting.alpha_a` / `lambda_a` | 0.5 / 0.2 | 量级合理 |
| `dynamics.shunting.eta_q` / `lambda_q` | 0.5 / 0.3 | 亚阈累积 |
| `context.goal.beta_goal` / `kappa_reach` / `fan_k` | 0.3 / 0.5 / 0 | `fan_k = 0`（关闭 fan-out 稀释） |
| `attention.ignition.T_ign` | 0（接入用） | 掐随机源；机制默认 0.05 |
| `memory.dsr.legacy_k` | 24 h | MindNet 声明的默认值（`memory.dsr.js` 的 `default: 24`），不是编造常数 |

**本轮未移植、因而也没有标定的**（t25 复核要求点名）：`rhythm.gate` 的走神率/占空比/警觉衰减
（`p_off` / `p_on` / `duty` / `τ_vig`）、`mulberry32` 随机源、`attention.inhibition`、`legacy_v1`、
`metacognition.belief` —— 它们的默认值同样是未标定量级，且不在本轮接入范围内（契约 §6.1 的可移植性矩阵 + 队内 D3）。

`ls` **不会**随反馈学习（反馈只动 `S`/`D`）；MindNet 侧对这两类数没有标定来源，本侧只是照量级采用。

### 9.4 降级与回落规则

| 情形 | 行为 |
| --- | --- |
| 模型实现缺失 / 抛异常 | 复习流程**照常完成**：`grade()` 里模型写入包在 try/catch 中，失败只跳过两列（有测试用抛 `StateError` 的模型钉住） |
| `encoding_strength` 为 NULL 但**有** FSRS 记忆 | `R0` 读作 **1.0**（FSRS 曲线无上限；`R0 = 1` 时两条曲线完全一致）；`savings` NULL 读作 **0.8** |
| `stability` 与 `difficulty` **都为 NULL**（全新卡） | 走 tierA 自己的初始化分支：`R0 = 0.8`、`Σ = 0.8`（与 `memory.dsr.js` 的 `ensureState` 对齐）。**这不是 §9.1 那条 NULL 规则的例外，而是另一个分支** |
| 新卡 | **不交给模型打分**（无历史=模型无从判断），单独成组 `unseen`；不伪造 `lastReviewedAt` |
| 诊断层不在场（tierB 未跑） | zone = `unavailable`，排序照常（tierA 的 R/增益仍在场） |
| 诊断跑了但该知识点不在结果里 | zone = `healthy`（跑了、无卡点）。**`healthy` 与 `unavailable` 必须区分**：把"没跑模型"显示成"健康"或"未知"都会骗用户 |

### 9.5 复习队列（advisor，D1）

段序固定为 **`forced → boosted → model → unseen`**：

- `forced`（答错绑定、当天必须回来）沿用既有 `_interleave` 的落位规则，一行未改；
- `boosted` 仍是 `DiffusionBoost` 的启发式加权，**但已明确标注"启发式、非模型量"**，
  且不与模型诊断同屏展示（契约 §6.5 的短期分工）；
- `model` 段顺序**唯一**由 `CognitiveModel.orderAdvisory` 给出，全序键：
  目标集命中 → 增益 ↓ → `dueAt` ↑（**`null` 排最后**：没排程的行不该被当成 1970 悄悄提前）→ 知识点 id ↑ → 卡 id ↑；
- 段与组内顺序的键用 **`cardStateId`**（不是 `unitKey`：无空可挖时 `unitKey` 一律回落成 `'essay'`，多个知识点会撞键并静默覆盖）。

### 9.6 用途 1（题目质量/难度评估）输入输出协议

链路（全部在 Furnace 侧，MindNet 无需改动）：

```
候选题目（id / 题干摘要 / 知识点标签 / difficulty_hint）
  → 标签树投影 CognitiveGraph.fromTags(tags, ms: {tagId: R0}, ...)
  → graph.toJson()            # 就是 MindNet 的 {nodes, edges}
  → FastGraph.fromSpec(...)
  → FastEngine.startDiffusion(starts, targets) → runRounds(3~5)
  → FastDiagnosis.bottlenecks(...) / FastPlanner.plan(..., retentionProbe:)
  → 每题判定 ∈ {too_easy, zpd, too_hard, out_of_scope, redundant, high_value} + 排序键
```

- `starts` = 最近动过的节点（可空；空数组合法）；`targets` = 该题的知识点。
  **两者都必须先过滤成图内存在的 id**：图外 id 会抛 `ArgumentError`，而"这题引用了一个投影没建出来的标签"是正常情况；
- `difficulty_hint` 只作**无历史时的排序先验**，**不得**作为模型的 `D` 传入（模型的 `D` 是每条线索的状态，由表现档位与 `R` 更新）；
- tierB 不在场时该层退化：只用 tierA 的 `R` 与 `scheduleInterval` 给初版判定（不抛异常）。

### 9.7 `ms` 的口径（修正 §6.3 的措辞）

§6.3 那句"`ms` 是『当前可提取度』"与同段的 `R0 = ms` 互相拉扯；Furnace 侧只读核对 MindNet 源码后的口径是：

> **`ms` = 节点的 `R0`（编码上限），节点级属性，只在初始化时被读一次**；此后由模型维护。
> 因此本侧传入的是 `CognitiveModel.modelReadingOf(row).r0`（即 `encoding_strength`），**不是**当前 `R`。

三条依据（只读）：`src/model.js` 的 `this.ms = f.ms === undefined ? 0.8 : f.ms`；
`mechanisms/memory.dsr.js` 的 `ensureState` 把 `ms` 读作 `R0 = min(1, ms)`（且 `ms <= 0` 时回落 0.8）；
`src/io/run.js` 的状态导出写的是 `ms: bag.R0`。

**导出侧还有一处口径不一致，必须写死**（t25 复核）：`src/io/run.js` 的 `:387` 导出 `ms: bag.R0`，
而同一文件 `:602` 导出的是 `ms: round6(node.ms)` 并另给一个 `R0` 字段；`mechanisms/memory.dsr.js` 的 `:114`
又会把 `node.ms` 改写成**当前 R**。所以**导出的 `ms` 不等于输入语义的 `R0`，绝不能回喂** ——
回喂会让"编码上限"被当前可提取度覆盖，且不会报错。

本侧投影的对应约定：`fromTags(ms: ...)` 的 `ms` 是**必填参数**（忘传编译不过），
节点在 map 里缺条目 ⇒ 不写该键、并出现在 `graph.nodesWithoutMs` 里（= "未提供"，**不等于 0.8**）；
MindNet 的 0.8 兜底只以具名常量 `CognitiveGraph.mindNetDefaultMs` 存在，**绝不隐式套用**。

**一个必须写明的语义后果**（reviewer 裁定）：因为 `R ≤ R0`，把 `R0` 当 `ms` 喂进快层，会让模型把节点当成
"比此刻实际更可达"，于是**可达性/发展区判断偏乐观**。这是**设计取向而非缺陷**：`R0` 是编码上限、`R` 是导出量，
喂 `R` 会自相矛盾（§6.3）。看诊断结论时要记得这一层乐观偏差。

### 9.8 快照与两个守卫（`--check` 不守我们这份）

- **协议常量与冻结快照**：`app/lib/domain/services/cognitive/mindnet_protocol.dart`
  —— `mindnet.conformance/1`、`generated_from.commit = ace605d9778e8641957c570c1e58049ca82e4a01`、
  容差 `rel 1e-12 / abs 1e-15 / round6` 与 `must_be_exact` 名单。
- **快照更正**：§8 写作时的基准是 `c624884`，但仓库里这份 fixture 实际是 **`ace605d`** 生成的；
  以文件为准，常量按 `ace605d` 钉住（§8 作为历史留档不改写）。
- **与 MindNet 当前 HEAD 的关系已核**：用 `node tools/conformance.js --check` 实测，样例数值与 MindNet
  HEAD **`f4eec9b`** 完全一致（`--check` 只报"commit 变了：107ab12 → f4eec9b"，数值零差异），
  且 Furnace 那份拷贝与 MindNet 仓库里的文件逐字节只差 `generated_from.commit` 一处
  （两边各 36812 B、tierA/tierB 数值全同）。
- **Furnace 快照守卫**：`test/domain/services/cognitive/mindnet_protocol_guard_test.dart`
  读 fixture 比对上述常量，不一致就失败并打印两侧值。**已做证伪实验**：改掉 fixture 里的 commit
  → 守卫失败（`snapshot drift: fixture was generated from deadbeef…`），还原后逐字节一致、重新通过。
- **`--check` 的能力边界**：`node tools/conformance.js --check` 比的是 **MindNet 实现 vs MindNet 自己的
  conformance 文件**，并且在比对时归一化掉 `generated_from.commit`（Furnace 侧取证：`tools/conformance.js` 的
  `--check` 分支为 **L270–302** —— 成功返回在 L298、失败分支 L300–302；归一化在 L284）。
  所以它**不能**证明 Furnace 这份拷贝没过期 —— 那是上面那个 Dart 守卫的职责。
  两个守卫分工写在这里，避免下一个人拿 `--check` 的通过去声称"我们的快照是新的"。

### 9.8b MindNet 侧操作规程（铁律，实测得出）

> 这一节的每条都是本轮踩出来的，不是推测。**违反它的代价是本轮一次真实的"参考仓库被写脏"事故。**

1. **只允许 `--check`**：核验新鲜度只用 `node tools/conformance.js --check`（实测只读：运行前后 `porcelain` / mtime / size / SHA256 四项全同）。
2. **`npm test` 也会写盘**：MindNet 自己的 `test/conformance.test.js` 在用例内无条件执行
   `execFileSync(process.execPath, [script, '--write'])`（约 L126），而 `package.json` 的 `"test"` 就是跑 `test/*.test.js`
   ⇒ **跑一次 `npm test` 必然重写 `conformance/mindnet_vectors.json` 的 `generated_from.commit`**。
   落盘点在 `tools/conformance.js` 约 L304-305；该文件里**唯一的只读分支**是 `--check`。
3. 因此禁令要写成白名单式：**MindNet 侧只允许 `--check`（与 git 只读命令）**；
   禁止 `--write`、不带 `--check` 的 `conformance.js`、`npm run conformance`、以及 `npm test`。
4. **"零写入"类核验必须排在整轮动作的最后**：中途跑过任何写盘路径，早前的读数就作废。
5. **还原也只能由仓库所有者授权后做**：回滚同样是写操作。（本轮那处脏文件即由第 2 条造成，内容只差一行 commit 戳记、数值零变化。）
6. **2026-10-02 判定：那处脏文件保留，不回退**（用户授权按"保留有用部分、清除过期内容"自行判断）。理由是本轮实测出来的方向性事实：
   工作区里的值是 **`f4eec9b`，等于 MindNet 自己的 HEAD**，也正是它的生成器在 HEAD 上重跑会写出的值
   （§9.8 的 `--check` 实测就报 "commit 变了：107ab12 → f4eec9b，数值零差异"）；而已提交的 `107ab12` 才是**旧的**戳记。
   所以"回退"等于**把更新过的那一行换成过期值**，与判定标准相反。处置：
   - 不动 MindNet 仓库任何文件（不 checkout、不 commit、不 push）；` M conformance/mindnet_vectors.json` 保持原样，
     它现在是"文件戳 = 仓库 HEAD"的一致状态，不是事故残留。
   - 后续核验别再把"MindNet porcelain 为空"当验收项：正确口径是"除 `generated_from.commit` 外与该仓库 HEAD 逐字节一致"，
     即 `git -C E:\Document\MindNet diff` 只允许出现那一行。
   - 铁律不变：MindNet 侧仍只允许 `--check` 与只读 git 命令（第 1–3 条）。
7. **读数口径（本轮三个成员各自独立踩过）**——同一份产物换一种读法就得出不同的数字，而每种读法看起来都像在直接测量。
   **可执行句式：凡报「次数 / 行数 / 条数」，先声明口径**（计的是哪个符号、哪一类操作、按什么切分、含不含空行）**再给数；
   能附 sha256 或符号名时，不引行号** —— 行号会随修订漂移（本轮同一处从 L673 漂到 L710、宿主入口从 L42 漂到 L56/L64，
   而指纹与行为都没变；例：引 `tool/mindnet_probe.dart` 的 `OpenMode.readOnly` 比引 L710 稳）。
   具体三类：
   - **读含非 ASCII 的文件：一律加 `-Encoding utf8`（或用 node）**。PowerShell 5.1 的 `Get-Content` 不加
     `-Encoding` 会按 ANSI/GBK 解码 UTF-8，产生**两个症状**：① 回显乱码（**看着像文件被改坏**）；
     ② 多字节字符被错切、**行被合并**（同一文件实测 `.Count` = 116，而 `[IO.File]::ReadAllLines()` = 129；
     该文件含 44 行非 ASCII）。纯 ASCII 文件上通常看不出来，所以更难发现。**判断文档是否损坏只看字节解码**
     （`U+FFFD` 计数、BOM），不看控制台回显 —— 本轮因此一度被误判为"交付物损坏"。
     （更正记录：这两条最初被写成两个独立成因、"`.Count` 不计空行"，实测否证后合并为本条。）
   - **数行数**：用 `[IO.File]::ReadAllLines()` 或 node 的**换行计数**；`split('\n')` 会把末尾换行算成
     空尾块（1576 vs 换行数 1575）。文档里写行数/行范围，必须注明用的是哪种计数方式。
   - **数键个数**：带引号搜 `"key`（`Select-String '"cognitive' app_en.arb` = 44 键）；不带引号会把
     `@key` 的 description 文案也算进去（57）。本轮 ARB 的正确数字是 **44 / 44**，不是 44 / 57。
   - **引用他人读数**：转述之前先自己跑一遍 —— 本轮据此拦下一条"其实已修复、却仍被准备上报"的缺陷
     （探针托管入口的默认 30 s 超时；修复后实测 21 s 通过，原 finding 已撤回）。

### 9.9 真实数据观察协议（只读）

目的：让用户能拿**真实学习数据**看模型当前判断，且**不可能**碰到自己的数据。

- 探针：`app/tool/mindnet_probe.dart`（纯逻辑，可测）+ 宿主入口
  `app/test/tool/mindnet_probe_report_test.dart`。
- **运行方式（t19 后更新）**：`dart run tool/mindnet_probe.dart --db <path> [--json] [--limit N] [--now <ISO-8601 时间戳>]`
  （`--now` 吃的是 ISO-8601，例如 `--now 2026-10-01T00:00:00Z`，用于**冻结读数时钟**以便复算比对；
  传裸小时数会 `exit=2`：`Invalid argument(s): --now expects an ISO-8601 timestamp` —— 实测）
  现在**可用**：它作为启动器把读数请求转交给 `flutter test` 宿主。**宿主为什么存在**：模型 seam 只能活在
  Flutter 运行时里 —— `database.dart` → `path_provider` → `package:flutter` → `dart:ui`，纯 Dart VM 没有
  `dart:ui`（实测报错）。探针 CLI 本身是纯 Dart（无 Flutter import），负责复制数据库、校验见证、渲染表格与 JSON。
  等价的手工宿主调用（老写法，仍可用）：
  ```powershell
  cd app
  flutter test test/tool/mindnet_probe_report_test.dart `
    --dart-define=PROBE_DB="$env:APPDATA\FirsryFan\Furnace\furnace.db"
  # 可选：--dart-define=PROBE_JSON=1、--dart-define=PROBE_LIMIT=20
  # 该用例用**进程内 host**（不再另 spawn 一层 `flutter test`）：实测约 12 s，
  # 仍保留 5 分钟上限作为余量。默认 runner 会嵌套一层、耗时 21–36 s 并横跨
  # `flutter test` 的默认 30 s 单测超时（冷机可复现 flaky），已改掉。
  ```
- **零写入保证**：探针先把库文件（连同 `-wal` / `-shm`）复制到临时目录，**只打开副本**；
  原库仅被 `stat`。已用真实库实测：运行前后 SHA256 完全一致（`8C58A610…E4615EC6`）。
- 输出：每张卡的 `R` / 增益 / `R0` / `Σ` / 标签数 / 新卡标记 + 汇总（卡数、新卡数、最低与平均 `R`、平均增益），
  按"最该复习的在前"排序；`--json` 给机器读。
- 判读：`R` 低 + 增益高 = 模型认为"快忘了、现在复习最值"；`R` 高 = 还记着。
  `ls` / `W_DAR` / `β_goal` 等参数**未标定**，所以看趋势可以，别把绝对值当结论。

