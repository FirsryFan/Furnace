# MindNet 接入 · 第二轮独立验证报告（t33）

- **任务**：t33（软 MindNet 口径的补充独立验证，替代"因 MindNet 脏文件永远无法登记"的 t26）
- **验证者**：verifier（独立于 t19/t20/t30 的实现者）
- **报告时间**：2026-10-01 15:02–15:07（本机时钟）
- **被测仓库**：Furnace `E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity`（HEAD `ee0a6e1`，本轮产物仍未提交）
- **三态约定**：§1–§7 为「已确认」（附命令原文与关键输出）；§8 为「未能确认 / 如何查证」。
- **纪律（本报告遵循）**：跑门窗口内若 `app/lib`+`app/test` 的 `*.dart` 最新 mtime 变动，则读数标为"不可归因"。

---

## 1. 证伪实验（**必做项**，含原始输出）

**步骤与原始输出**（fixture：`app/test/fixtures/mindnet_vectors.json`）

```
STEP 0  sha256 = DBB2E33E36F56970A1C98413CB4F36596173E049167AFC624480BAD9CA4FA64A
        matches contract baseline: True          （备份 36812 bytes 到 %TEMP%）
STEP 1  mutated: commit ace605d -> 107ab12       （字面替换 40 字符 → 40 字符，其余字节不动）
STEP 2  flutter test test/domain/services/cognitive/mindnet_protocol_guard_test.dart
        frozen snapshot generated_from.commit matches the pinned commit [E]
          Expected: 'ace605d9778e8641957c570c1e58049ca82e4a01'
            Actual: '107ab12db7d9fd278a6f451dfc1260eacf57dc8a'
          snapshot drift: fixture was generated from 107ab12…, MindNetProtocol pins ace605d…
        00:00 +4 -1: Some tests failed.        → GUARD EXIT = 1     ✅ 守卫按预期变红
STEP 3  restore from backup
        sha256 after restore = DBB2E33E36F56970A1C98413CB4F36596173E049167AFC624480BAD9CA4FA64A
        restored to baseline: True
        git diff --stat -- app/test/fixtures/mindnet_vectors.json → （空），diff 行数 = 0   ✅
STEP 4  flutter test …mindnet_protocol_guard_test.dart → 00:00 +5: All tests passed!  EXIT = 0  ✅ 还原后守卫恢复通过
```

- **结论**：①改坏 frozen commit → 守卫**确实 fail**（不是装饰）；②还原后 `git diff` 为空且 SHA256 逐字符回到基线；③还原后守卫恢复通过。未修改任何产品代码，fixture 已按 nonGoals 还原。

## 2. 真实库零写入 + 探针在副本上实跑

- 目标库：`C:\Users\firsr\AppData\Roaming\FirsryFan\Furnace\furnace.db`
- [跑] 前后对比（本会话共 11 次读数，跨 13:52:53 → 15:07）：
  `size = 290816`、`mtime = 2026-09-29 23:56:48`、
  `sha256 = 8C58A610A757B2DFD2489F72CBCE79FCC785D504C5558D23966BAEA9E4615EC6`（与任务基线逐字符相同）—— **全部一致，零写入**。
- [跑] 探针实跑（**只在副本上**）：`dart run tool/mindnet_probe.dart --db <真实库> --json`。**脱敏片段**（去掉卡片标题等用户内容，只留 id 摘要与数值）：
  ```json
  "modelId": "mindnet-tierA",
  "nowHours": 497454.9783786111,
  "summary": { "cards": 4, "meanR": 0.7584139962031732, "minR": 0.5171989430984133,
               "meanGain": 12.713817045888545, "bandCounts": { "forced": 1, "model": 3 },
               "zoneCounts": { "unavailable": 4 } },
  "source": { "bytes": 290816,
              "sha256_before": "8c58a610…5ec6", "sha256_after": "8c58a610…5ec6",
              "modified_before": "2026-09-29T23:56:48.343534",
              "modified_after":  "2026-09-29T23:56:48.343534",
              "unchanged": true },
  "copy": { "directory": "C:\\Users\\firsr\\AppData\\Local\\Temp\\mindnet_probe_9eb83cd2", "files": ["furnace.db"] }
  ```
- [读] 只读机制（源码）：`tool/mindnet_probe.dart` 把库连同 `-wal`/`-shm` 复制到临时目录（L624/L631），只打开副本；原库仅被 `statSync`（L613/L667）；写入只发生在自己的临时目录（L205/L643）与清理（L383）。探针把 `sha256_before/after`、`modified_before/after`、`unchanged` 作为**返回值**输出（L850-857），使这次断言可被外部复核——与我的外部读数一致。

## 3. 独立复算真实库 4 卡数字（此前未完成项）

**协议**：探针用 JSON 取全精度 `nowHours` → 用**同一个 now** 跑独立复算 → **逐卡比全精度 R/增益**（不比展示值）。

- [跑] 探针（应用侧，Dart）：`nowHours = 497454.9783786111`，4 卡。
- [跑] **我的独立路径**：`node:sqlite` 以 `{readOnly:true}` 打开**副本** + **MindNet 参考实现** `mechanisms/memory.dsr.js`（`retrievabilityOf` / `stabilityIncrease`）+ 我自己的列映射（`R0 = encoding_strength ?? 1.0`、`S_hours = stability × 24`、`Σ = savings ?? 0.8`、`D = difficulty`、`lastReview = last_reviewed_at / 3.6e6`），**同一个 now**：

| 卡（id 摘要） | R（探针） | R（我） | \|dR\| | gain（探针） | gain（我） | \|dG\| |
| --- | --- | --- | --- | --- | --- | --- |
| kp-6f201136… | 0.517160668 | 0.517160668 | **0.000e+0** | 16.117715122 | 16.117715122 | **0.000e+0** |
| kp-92728def… | 0.838829595 | 0.838829595 | **0.000e+0** | 11.579339669 | 11.579339669 | 1.421e-14 |
| kp-aaff3ff3… | 0.838830674 | 0.838830674 | **0.000e+0** | 11.579262656 | 11.579262656 | **0.000e+0** |
| kp-2d76e863… | 0.838835047 | 0.838835047 | **0.000e+0** | 11.578950736 | 11.578950736 | 1.243e-14 |
| **均值** | 0.7584139962031732 | 0.7584139962031733 | 1.110e-16 | 12.713817045888545 | 12.713817045888552 | 7.105e-15 |

→ `CARD-BY-CARD: MATCH (R within 1e-9, gain within 1e-6)`，exit 0。**增益也是独立复算的**（不是展示值）。

### 3.1 补强：**从零实现** `stabilityIncrease`（不调用参考实现的那个函数）
> 说明（如实披露）：上表的 gain 是**调用 MindNet 参考实现** `memory.dsr.js:149` 的 `stabilityIncrease` 得到的；队长 t33 协议第 3 条要求"自己实现一遍"。补做如下：`ψ(z)` 与 `gain` 的**公式本身**都由我手写（只从参考读**常量** γ/β/η/κ/κ_savings —— 它们是被标定的参数，不是算法），依据 `memory.dsr.js:140-160` 照写：
> `c = 0.9^(−1/γ) − 1`；`Ψ(z) = (1+c·z)^(−γ)`；`mu = 1 + κ_savings·Σ`；`dt = 11 − clamp(D,1,10)`；`sat = e^{η(1−R)} − 1`；`inc = 1 + κ·ratio·mu·dt·S^(−β)·sat`；`gain = max(1, inc)`（`ratio=1`，即 `retrieval_success`）。

```
constants from reference: gamma=0.1542 beta=0.1367 eta=1.0461 kappa=8.01921 kappa_savings=0.5
kp-2d76e863…  gain(mine)=11.578950735715  gain(reference fn)=11.578950735715  |mine-ref|=0.000e+0
kp-6f201136…  gain(mine)=16.117715121906  gain(reference fn)=16.117715121906  |mine-ref|=0.000e+0
kp-92728def…  gain(mine)=11.579339669443  gain(reference fn)=11.579339669443  |mine-ref|=0.000e+0
kp-aaff3ff3…  gain(mine)=11.579262656490  gain(reference fn)=11.579262656490  |mine-ref|=0.000e+0
mean gain(mine) = 12.713817045889
vs probe:  worst |dR| = 0.000e+0   worst |dG| = 1.421e-14   mean gain diff = 7.105e-15
FROM-SCRATCH GAIN: MATCH (my ψ + my stabilityIncrease reproduce the probe)     exit 0
```
即：**三条路径**（应用侧探针 / 我的映射+参考公式 / 我的映射+自写公式）在同一个 `nowHours` 上一致到 `R` 逐位相等、`gain` ≤1.4e-14。原库 sha256 本项前后仍为 `8C58A610…5EC6`。

### 3.2 补强（16:14，observability-dev 提示后）：**冻结时钟下的确定性复算 —— R 与 gain 双双逐位相同**
> 新信息：探针支持 `--now <iso8601>` 冻结模型时钟（模型时钟 = 小时自 epoch）。这消掉了 §3 里唯一的解释性余量（"差异来自 now 时间差"），把对拍变成**确定性**的。

```
$ dart run tool/mindnet_probe.dart --db "<真实库>" --now 2026-10-01T00:00:00Z --json
  nowHours = 497448      meanR = 0.7635219362788948      meanGain = 12.38753837830366      unchanged = true

我的独立复算（同一 nowHours=497448，node:sqlite 只读副本 + 自写映射）：
  kp-6f201136…  R probe=0.521890373 mine=0.521890373 |dR|=0.000e+0   gain probe=15.929559379 mine=15.929559379 |dG|=0.000e+0
  kp-92728def…  R probe=0.844063509 mine=0.844063509 |dR|=0.000e+0   gain probe=11.207026541 mine=11.207026541 |dG|=0.000e+0
  kp-aaff3ff3…  R probe=0.844064640 mine=0.844064640 |dR|=0.000e+0   gain probe=11.206946298 mine=11.206946298 |dG|=0.000e+0
  kp-2d76e863…  R probe=0.844069222 mine=0.844069222 |dR|=0.000e+0   gain probe=11.206621295 mine=11.206621295 |dG|=0.000e+0
  mean_r: |diff| = 1.110e-16      mean_gain: |diff| = 0.000e+0
  CARD-BY-CARD: MATCH      exit 0
```
- **`R` 与 `gain` 的 |dR|、|dG| 全为 `0.000e+0`**（比 §3 更强：§3 里 gain 还有 1.4e-14 的余量，那是两次读数之间时钟推进造成的）。
- observability-dev 独立报的冻结读数（`0.522/15.93`、`0.844/11.21`×3、`meanR=0.7635219362788948`）与我的**逐位一致**（meanR 连末位都相同）—— 这是同一条结论的**第四方**复现。
- 原库 sha256 前后仍为 `8C58A610…5EC6`；窗口 mtime 全程冻结 `16:08:55`。
- **复现注意（我实测，16:16）**：`--now` **只接受 ISO-8601**，传裸小时数会 `exit 2` —— stderr 原文 `Invalid argument(s): --now expects an ISO-8601 timestamp, got 497448`；`--help` 里的用法行是 `--now <iso8601> freeze the reading clock (default: now)`。用 ISO 形式（如上）则正常得到 `nowHours = 497448.0`、`meanR = 0.7635219362788948`。契约 §9.9 已按此措辞更新（`docs/MINDNET_CONTRACT.md` §9.9「真实数据观察协议（只读）」—— **16:41 复核**时用法行在 **L704**、"传裸小时数会 exit=2"在 **L706**；该文件在本次验证期间被改动多次，**行号会漂移，引用时以原文为准**）。全程原库 sha256 未变。
- **JSON 键名（我复核自己保存的输出，16:2x）**：顶层键是 `modelId, nowHours, nowUtc, summary, cards, bandByCardStateId, scoreByCardStateId, zoneByKnowledgePoint, readings_schema, schema, generated_at, source, copy, knowledge_points, units, host` —— **是驼峰 `nowHours`，没有 `now_hours` 这个键**（更早草稿的 snake_case 命名已废弃）。全精度数值在 `cards[].r` / `cards[].gain` / `summary.meanR`；`cards[]` 每项 25 键（`cardStateId, knowledgePointId, knowledgePointTitle, unitKey, rank, r, gain, r0, sigma, band, zone, isNew, scoreUsedForOrdering, boostFactor, tagCount, dueAt, lastReviewedAt, intervalDays, suggestedIntervalDays, repetitions, lapses, stability, difficulty, forced, forcedStreak`）。
- **join 口径（按队长要求改为 `cards[].cardStateId`）**：本节上表最初按 `knowledgePointId` join（本库里 4 张卡的 `knowledgePointId` 与 `cardStateId` 都是 4 个互不相同的值、1:1，所以两种 join 等价）。为对齐口径我已**改用 `cardStateId` join 复跑**：
  ```
  cs-c6a88444… [join=cardStateId]  R 0.521890373/0.521890373 |dR|=0.000e+0   gain 15.929559379/15.929559379 |dG|=0.000e+0
  cs-fd0f9043… [join=cardStateId]  R 0.844063509/0.844063509 |dR|=0.000e+0   gain 11.207026541/11.207026541 |dG|=0.000e+0
  cs-3670262c… [join=cardStateId]  R 0.844064640/0.844064640 |dR|=0.000e+0   gain 11.206946298/11.206946298 |dG|=0.000e+0
  cs-0399c2fc… [join=cardStateId]  R 0.844069222/0.844069222 |dR|=0.000e+0   gain 11.206621295/11.206621295 |dG|=0.000e+0
  mean_r |diff|=1.110e-16    mean_gain |diff|=0.000e+0    → CARD-BY-CARD: MATCH   exit 0
  ```
  与按 KP join 的结果**完全相同**；原库 sha256 仍为 `8C58A610…5EC6`。
- 与任务基线（议论文结构 R 0.518 / 增益 16.08；其余三张 R 0.840 / 增益 11.50；均值 0.759）为**同一批量**：差异全部由 `now` 的时间差解释（`R` 随时间下降、增益随时间上升，方向自洽）。
- [跑] 原库 sha256 在本项前后仍为 `8C58A610…5EC6`；临时副本用完即删。

## 4. 观测面只读性（写入 API 搜索：范围 / 关键词 / 结果）

- **范围**：`app/lib/features/cognitive/**`（读数页）与 `app/tool/mindnet_probe.dart`。
- **关键词**：`insert`、`update`、`delete`、`write`、`customStatement`、`customUpdate`、`customInsert`、`customDelete`、`customSelect`、`transaction`、`batch(`、`execute(`（探针另查 `copySync`/`statSync`/`openSync`）。
- **结果**：
  - `app/lib/features/cognitive/**`：命中 **3 处，全部非写调用** —— L13 是文档注释（"…and writes nothing"）、L75 `updatedAt: _jsonInt(row['updatedAt'])`、L118 `'updatedAt': row.updatedAt`（都是**列名/映射**，不是写 API）。**没有任何 insert/update/delete/custom* 调用**。
  - `app/tool/mindnet_probe.dart`：写操作仅出现在**自己的临时副本与清理**（`openSync` L205、`writeAsStringSync` L643、`deleteSync` L383）与**复制到副本**（`copySync` L624/L631）；对原库只有 `statSync`（L613/L667），**无 SQL 写、无仓库写**。
- **测试钉住**：[跑] `flutter test test/features/cognitive/cognitive_model_page_test.dart …` 含用例 **`writes nothing to the database it reads`**（通过）。
- 结论：**观测面只读**，且"只读"不是靠注释而是靠搜索穷举 + 用例钉住。

### 4.1 逐行取证（我独立复核 observability-dev / tierb-dev 给的两条"机械可证伪"锚点）
**文件指纹（我实测）**：`app/tool/mindnet_probe.dart` = **937 行 / 32214 B / mtime 2026-10-01 14:40:38**，
sha256 = `C365AA4FA30BA8DD1850CA7547652E1A5AB61312964DEE6F0607729733DF75B0`（行号会随修订漂移，引用请带该指纹或直接用符号名）。
   **旁证（tierb-dev 复测，署名引用、我未重跑）**：同一份 `docs/MINDNET_CONTRACT.md` 从 50469 B（16:19:29）长到 50779 B（16:39:40）时，**裸闸门总数不变**（BLOCKER 65 · WARN 23 · REVIEW 7）、**"§9 占几条"也不变**（12），但 **§9.8b 那 4 条行锚整体 +1**（`674,675,677,678` → `675,676,678,679`，因为 L665-666 的改写扩成三行把后面顶下去一行）。⇒ **计数稳、行锚飘**：交接文字写"总数 + 时点"，行号只在必要时并带时点写。

**(a) 唯一 DB 句柄在副本上、且只读 —— 成立**
`sqlite3.open` 全文**只出现一次**：
```
L710: final db = sqlite3.open(copyPath, mode: OpenMode.readOnly);   // copyPath = 临时目录里的副本（L709 的函数入参）
```
`OpenMode.*` 全文只出现两处：L14（头部注释）与 L710；**没有任何 `OpenMode.readWrite*`**。

**(b) 原库路径上只有 存在性检查 / stat / 流式哈希 / 复制 —— 成立（但锚点的"10 处 `options.dbPath`"说法不准确）**
- 对原库的**全部**文件级操作（**7 行**；我做的是"对 `File source` 句柄/哈希函数的调用"，不是字面量 `options.dbPath`）：
  `L608 source.existsSync()`（存在性检查）、`L613`/`L667 source.statSync()`（运行前后见证）、`L614`/`L668 sha256HexOfFile(source)`（运行前后哈希见证，函数定义在 L203）、`L624 source.copySync(copy.path)`（**从原库读、写副本**）、`L631 sidecar.copySync('${copy.path}$suffix')`（`-wal`/`-shm` 同样只写副本）。
  **两类而已**：①纯读（existsSync / statSync / sha256HexOfFile）②"读原库 → 写副本"（copySync）。**没有任何写回原库方向的操作。**
- 哈希见证 `sha256HexOfFile`（L203-212）用 `file.openSync()`（**L205 无 mode 参数 ⇒ Dart 默认 `FileMode.read`**）+ `readIntoSync(buffer)` 循环 —— 纯读。
- **写操作全部落在临时目录**：`L624`/`L631`（副本与副本的 sidecar）、`L642-643 units.json`（`p.join(tempDir.path, 'units.json')`）、`L645` readings.json、`L383 dir.deleteSync(recursive: true)`（finally 清理）。
- **更正**：字面量 `options.dbPath` 在当前文件里共 **5 处**（L607/609/619/629/679），不是对方消息里说的"10 处"；那串行号（608/613/614/624/631/667/668）实际是 `source.*` 调用及其相邻行，且**行号会随修订后移**（对方自己也更正过一次 L673 → L710）。**结论不变**：原库上没有写 API。

**(c) 交叉印证**：`dart analyze tool` → **`No issues found!`**，exit 0；import 块只有 4 行（`dart:convert`、`dart:io`、`package:path/path.dart`、`package:sqlite3/sqlite3.dart`），与"纯 Dart、无 Flutter import"一致；`dart run tool/mindnet_probe.dart --help` exit 0。

## 5. AI 工具只读性（`evaluate_problem_fit`）

- **ApprovalEngine 分类**（[读] `app/lib/features/ai/tools/cognitive_tools.dart:106-115`）：
  `riskFor(...) => ToolRisk.write`（无 action，故枚举只有一个值）、`reversibleFor(...) => true`；
  源码注释写明这是**为了让 `ApprovalEngine` 永不逐条询问**（risk=write + reversible=true ⇒ auto 模式直接执行、plan 模式批量确认），而"只读"由**结构**保证（L7-8："writes nothing anywhere (no SQL, no repository write method, no `update*` call)"）。
- **测试输出**（[跑] `flutter test test/features/ai/cognitive_tools_test.dart test/features/ai/approval_engine_test.dart`）→ **`00:01 +22: All tests passed!`**，exit 0，含：
  - `read-only by construction a call leaves every table untouched`
  - `output contract difficulty_hint is a prior, never the model difficulty`
  - `output contract verdicts use the contract wire names and carry a reason`
  - `boundaries tags outside the graph do not crash the diffusion`
  - `registration the tool is in the app tool list, with its schema`
- **三项口径核对**：
  1. **`ms = R0`**：模型层 `dsr_card_state.dart:57 ms: row.encodingStrength`（读那张行时把 `encoding_strength` 当 `R0` 用）；投影层 `cognitive_graph.dart:62` 明说"状态导出写回 `ms: bag.R0`"。**注意区分**：图投影对**没有 ms** 的节点用 `mindNetDefaultMs = 0.8`（`cognitive_graph.dart:259`），而**模型**读空的 `encoding_strength` 用 **1.0**（`dsr_card_state.dart:67` 有注释说明）——两层默认值不同是**有意**的，不是矛盾。
     - 关于那个 0.8 的来源，`cognitive_graph.dart:304` 的注释称它对应 MindNet 侧 `src/model.js` 的 ms 兜底 —— **此条我未直接读该 JS 文件**（属转引 Dart 注释，已标注为未验证）。
  2. **`difficulty_hint` 不作模型 `D`**：`cognitive_tools_test.dart:213` 与 `problem_evaluator_test.dart:118` **两条测试钉住**（"a prior, never the model difficulty" / "only a prior when there is no history"）。
  3. **starts/targets 过滤**：`problem_evaluator_test.dart:186`（`ids outside the graph are dropped instead of throwing`）与 `cognitive_tools_test.dart:238`（`tags outside the graph do not crash the diffusion`）钉住；另 `fast_diagnosis_conformance_test.dart:381` 钉住"无 targets 时报死角"。

## 6. 独立跑全量测试与静态分析（**窗口干净，可完整归因**）

```
A 起跑前 mtime = 15:02:40 (15:04:34)
  cd app; flutter test --concurrency=1
  → 01:30 +525 ~2: All tests passed!      exit = 0     失败标记 = 0
B 套件后 mtime = 15:02:40 (15:06:16)   ← 窗口内无写入
  cd app; dart analyze lib test
  → exit = 0，末行 `87 issues found.`，error = 0 · warning = 0 · info = 87
C 分析后 mtime = 15:02:40 (15:06:26)   ← 窗口内无写入
```
- 与基线对比：**360 → 525 通过 / +2 跳过**。（任务文本里的"当前 +519 ~1"是更早的树。计数差的算术已双人核清：`app/test/domain/services/cognitive/heuristic_model_divergence_test.dart` = **171 行 / 7342 B / mtime 2026-10-01 15:02:40**，内含 **5** 个 `test(...)`（0 个 `testWidgets`，我自数；observability-dev 独立同数）⇒ **520 + 5 = 525**，所以 `+520` 与 `+525` **两个数字都对，只是树的时间点不同**，引用时标明时点即可。两条 skip 分别是 `mindnet_probe_report_test.dart` 的 `PROBE_DB` 开关与 `mindnet_probe_test.dart` 里标着 `Skip: driven by tool/mindnet_probe.dart` 的那条。）
- 附：`git -C <Furnace> status --porcelain` → **32 行**（本轮全部产物尚未提交，属预期）。

## 7. MindNet 相关项（软化口径：**如实记录并归因**，不以 porcelain 为空为通过条件）

- [跑] `git -C "E:\Document\MindNet" status --porcelain` → ` M conformance/mindnet_vectors.json`
- [跑] `git diff` 全文：**只有一行** —— `- "commit": "107ab12db7d9fd278a6f451dfc1260eacf57dc8a"` / `+ "commit": "f4eec9bae16e6e303c19177e7fbfcf7a756f6629"`（`git diff --stat` = 1 file changed, 1 insertion, 1 deletion）。
- [跑] 文件 mtime = **2026-10-01 13:53:35**（自该时刻起未再变化）；size 仍 36812 B。
- **根因（[读] 源码）**：MindNet 自带测试 `test/conformance.test.js:123-129` 的用例里 **L126** 执行 `execFileSync(node, [script, '--write'])`（L129 = `});`，全文共 129 行），而 `npm test` = `node --test test/*.test.js`（`package.json:8`）⇒ **跑 MindNet 的 `npm test` 必然重写它自己的 conformance 文件**（写盘在 `tools/conformance.js:304-305`；`--check` 只读分支是 L270-302）。
- **归因**：由 t18 验收④要求的 `npm test` **间接触发**的一次自动写盘（13:53:35，执行者为 verifier）。本轮（t33）我**未写入、未回滚、未新增**：多次读数里该文件 mtime/sha256 全程冻结。
- 正确禁令（已与队长对齐）：**MindNet 侧只允许 `--check` 与只读 `require`**；`npm test` 同样禁用（它是间接 `--write`）；任何无 `--check` 的 `conformance.js` 调用（含 `npm run conformance`，`package.json:16` 不带参数）都会写盘。

## 8. 未能确认 / 如何查证

| 项 | 状态 | 原因 | 怎么查 |
| --- | --- | --- | --- |
| MindNet 脏文件的最终处置 | **未能确认** | 回滚也是写操作，处置权在用户/队长；按指令我不动它 | 授权后 `git -C E:\Document\MindNet checkout -- conformance/mindnet_vectors.json` |
| `app.so` 是否为当前树的最新 AOT 产物 | **未能确认（本轮未构建）** | 本轮契约的 verify 不含构建；且树在 15:02:40 仍有写入 | 在写入停止后 `cd E:\Document\furnace-build; flutter build windows --release`，判据 = `app.so` mtime 晚于 `app/lib` 最后改动 **且** exit 0。该判据在第一轮实测过：`flutter build windows --release` → exit 0、`Building Windows application... 145.7s`、`✓ Built …furnace.exe`，`app.so` 10355592 B @10:36:24 → **10404744 B @14:03:09**，AOT stamp 同步刷新（见第一轮报告 §6） |
| 探针托管入口在**默认 30 s 超时**下的可用性 | **已闭环：风险由结构消除**（非"贴着超时"）—— 现入口 `host: _hostInProcess`（L64，不再 spawn 第二层）+ 显式 `timeout: 5 min`（L84）；我连测两次 **10 s / 9 s**、exit 0 | 15:0x 时该入口是"默认 runner spawn 第二层 + 无显式 timeout"，36 s 故失败；**16:18:38 的改动（作者 = captain，登记后补丁）**把两者都去掉了 | 若日后改动去掉显式 timeout 或退回默认 runner，该风险会重新引入 —— 保留在发现清单里作为回归关注点 |

## 9. 证据台账（命令 → 关键输出 → 时刻）

| 命令（原文） | 关键输出 | 时刻 |
| --- | --- | --- |
| fixture sha256 → 改 commit → `flutter test …/mindnet_protocol_guard_test.dart` → 还原 → 再跑 | 基线 `DBB2E33E…`；改坏后 **+4 -1 / exit 1**（Expected ace605d…, Actual 107ab12…）；还原后 sha256 回基线、git diff 0 行；再跑 `+5 All tests passed!` | 15:03–15:05 |
| `dart run tool/mindnet_probe.dart --db <真实库> --json` | nowHours=497454.9783786111、meanR=0.7584139962031732、meanGain=12.713817045888545、`unchanged: true` | 15:05 |
| `node db_independent.cjs <副本> --now-hours 497454.9783786111 --json <probe.json>` | R 四项 \|dR\|=0.000e+0、gain ≤1.421e-14、均值差 1.1e-16 → `CARD-BY-CARD: MATCH` | 15:05 |
| `flutter test test/features/cognitive/cognitive_model_page_test.dart test/features/ai/cognitive_tools_test.dart test/tool/mindnet_probe_test.dart` | `+36 ~1: All tests passed!`（含 `writes nothing to the database it reads`） | 14:59 |
| `flutter test test/features/ai/cognitive_tools_test.dart test/features/ai/approval_engine_test.dart` | `+22: All tests passed!` | 15:03 |
| `cd app; flutter test --concurrency=1` | `01:30 +525 ~2: All tests passed!`，exit 0，窗口干净（mtime 冻结 15:02:40） | 15:04:34–15:06:16 |
| `cd app; dart analyze lib test` | exit 0，`87 issues found.`，0 error / 0 warning / 87 info，窗口干净 | 15:06:16–15:06:26 |
| `git -C <Furnace> status --porcelain` | 32 行（产物未提交，预期） | 15:03 |
| `git -C "E:\Document\MindNet" status --porcelain` + `git diff` | ` M conformance/mindnet_vectors.json`；diff 仅 commit 一行；mtime 13:53:35 | 15:07 |

**复算脚本（均在两个仓库之外，只读）**：`C:\Users\Public\mindnet-verify\` 下
`guard_falsify.dart`、`db_independent.cjs`、`gain_scratch.cjs`、`db_r_prelim.cjs`、`sqlite_probe.cjs`、`check_probe_keys.cjs`、`tierA_43_check.dart`、`tierb_b01_check.dart`、`tierA_probe.dart`、`cmp_vectors.mjs`、`recompute_b01.cjs`、`b01_discrimination.cjs`、`probe_gen.cjs`、`tierb_diag_redrive.cjs`、`tierA_redrive.cjs`。

**调用与单位提醒（复用时最容易踩）**：**同一个冻结时刻在两侧单位不同** —— 探针吃 `--now <ISO-8601>`（例 `2026-10-01T00:00:00Z` ⇔ `nowHours = 497448.0`），而 `db_independent.cjs` / `gain_scratch.cjs` 吃 **`--now-hours <小时数>`**（例 `497448`）。**喂错会响亮失败、不会静默算错**（我实测：ISO 串喂给 `--now-hours` → **exit 2** + usage；`497448` 喂给探针 `--now` → **exit 2** + `Invalid argument(s): --now expects an ISO-8601 timestamp`）。（这条按 observability-dev 的建议把两侧都写清。）`db_independent.cjs` 同时兼容 `nowHours`/`now_hours` 与 `cards`/`cards_detail`，并按 `cards[].cardStateId` join。

**机械闸门**（本文件，实际执行的完整命令）：
```
cd "E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity"
node "D:\dsh-data\skills\anti-hallucination\scripts\audit-claims.mjs" "docs\VERIFICATION_MINDNET_ROUND2.md" \
  --workspace "." \
  --allow "conformance/mindnet_vectors.json" --allow "conformance.js" --allow "package.json" \
  --allow "memory.dsr.js" --allow "src/index.js" --allow "src/v2/engine.js" --allow "furnace.db" \
  --allow "audit-claims.mjs" --allow "guard_falsify.dart" --allow "db_independent.cjs" \
  --allow "db_r_prelim.cjs" --allow "sqlite_probe.cjs" --allow "tierA_43_check.dart" \
  --allow "tierb_b01_check.dart" --allow "tierA_probe.dart" --allow "cmp_vectors.mjs" \
  --allow "recompute_b01.cjs" --allow "b01_discrimination.cjs" --allow "probe_gen.cjs" \
  --allow "tierb_diag_redrive.cjs" --allow "tierA_redrive.cjs"
```
**结果**：`计数：BLOCKER 0 · WARN 0 · REVIEW 15`，`结论：PASS（无 BLOCKER）`，exit 0。
→ 注意：闸门只查机械项，**不等于内容为真**。

---

## 10. 发现（供 t35 评审 / t28 收口）

1. **T33-F1（medium）—— ⚠ 已于 16:13 复测为「已解决」，此条作废**（原始观测保留在下方，供对账）：
   - **原观测（15:0x，修复前的树）**：`test/tool/mindnet_probe_report_test.dart` 在**默认 30 s 超时下会失败** —— `flutter test test/tool/mindnet_probe_report_test.dart --dart-define=PROBE_DB=<真实库>` → `exit 1`，`TimeoutException after 0:00:30.000000: Test timed out after 30 seconds`；加 `--timeout=5m` → `00:36 +1: All tests passed!`。
   - **复测（16:13:57 起跑，当前树）**：同一命令**不加 `--timeout`** → **`00:21 +1: All tests passed!`**，exit 0（`host.exit_code=0`，JSON 完整，`source.unchanged=true`）。21 s < 默认 30 s ⇒ **不再触发超时**。
   - **结论（16:40 复核后定稿）**：**当前树上该风险已由结构消除，不是"贴着超时"** —— 文件指纹 `test/tool/mindnet_probe_report_test.dart` = **85 行 / 3752 B / mtime 2026-10-01 16:18:38**，sha256 `768D959FEFE5C971060291D3734A679BCEE8C0C41BA8A3415295F0EB3EB6F1FE`；**该次改动的作者 = captain**（登记后补丁、未随任务入账；**不是** observability-dev，也不在 t19 的 inScope 六条里 —— 见 §10 第 5 条）：
     ① **L40 定义、L64 传入 `host: _hostInProcess`** ⇒ 该入口**不再 spawn 第二层 `flutter test`**（默认 runner `runFlutterHost`，见 `tool/mindnet_probe.dart:430`，已被绕开）；
     ② **L84 `}, timeout: const Timeout(Duration(minutes: 5)));`** ⇒ 显式超时，**默认 30 s 不再适用于该用例**；
     ③ 我连测两次（同一命令、不加 `--timeout`）：**elapsed 10 s / 9 s**，`+1: All tests passed!`，exit 0；observability-dev 用同一命令**独立复测 = 11.7 s**、exit 0（他此前在修复前测得 26.2 s）⇒ **两方三次数都落在 9–12 s，距默认 30 s 有 ~2.5× 余量**。
     ⇒ 先前记录的 21 s / 26 s / 36 s 都是 **16:18:38 这次改动之前**的读数；即使冷缓存把耗时拉到 30 s 以上，显式 timeout 也使其**不再触发**默认超时。**风险类别（热路径上 spawn 子进程）已被根治**，而不是"暂时变快"。
2. **口径统一（observation）**：MindNet 写盘用例应统一写成"**`test/conformance.test.js:123-129` 的用例（L129 = `});`），写盘调用在 L126**"（我此前在同一批文档里出现过 `123-126` / `123-128` / `123-129` 三种范围，现已统一为 123-129；权威范围由三路计数互证：node 换行 129、`ReadAllLines` 129、`read` 工具报 `total 129 lines`）。
   **行数口径提醒（reviewer 提示 + 我实测）**：本环境 **`Get-Content .Count` 在含非 ASCII 的文件上不可靠**（`test/conformance.test.js`：**116** vs `ReadAllLines`/node **129**，差 13；根因见第 4 条 —— 与"乱码"**同源**，都是没指定 UTF-8），**纯 ASCII 文件上通常看不出来（更难发现）**。所以写进报告的行数一律用 `[IO.File]::ReadAllLines()` 或 node 换行计数复核。
3. **正面结论**：真实库 4 卡数字经**另一条独立路径**（不同语言/驱动 + 参考实现）在**同一 now** 下逐卡复现，R 完全相等、增益差 ≤1.4e-14；基线（0.518 / 0.840 ×3 / 均值 0.759）随之被证实为**可独立复现的量**，而非账外数字。
4. **工具口径陷阱：中文文档被判成"损坏"的触发条件与避免**（我实测复现；reviewer 独立复核并给出根因；建议照此写进文档纪律）
   - **触发**：本机 PowerShell **5.1.26100.9502**，`[Console]::OutputEncoding` = `utf-8`；**`Get-Content <file>` 不带 `-Encoding` 时按 ANSI/GBK 解码 UTF-8** →
     `Get-Content docs\VERIFICATION_MINDNET_ROUND2.md -TotalCount 3` → `# MindNet 鎺ュ叆 路 绗簩杞嫭绔嬮獙璇佹姤鍛婏紙t33锛?`（看着像文件损坏；我据此**差点误报**"交付物被第三方改坏"）。
   - **判真伪（可复现的否证手法）**：① 同一命令加 `-Encoding utf8` → `# MindNet 接入 · 第二轮独立验证报告（t33）` 正常；② `node -e "readFileSync(p,'utf8')"` → 中文正常、**U+FFFD 计数 0**、无 BOM。
     结论：本文件**完好**（当时那版 19115 B / 189 换行 / 190 个 `split('\n')` 块；现已增长）。
   - **避免**：读中文文档一律 `Get-Content -Encoding utf8`（或直接用 read 工具 / node）；**不要凭控制台回显判断文件是否损坏**。
   - **一句话总规则**：**PS 5.1 读任何含非 ASCII 的文件，一律加 `-Encoding utf8`**。
   - **同一根因的第二个症状（行数少算）**：`Get-Content <file>` **不带 `-Encoding`** 时，同一个错误解码还会把多字节字符**错切成合并行** ⇒ 行数少算，看着像**文件被截断**。实测（`test/conformance.test.js`，file size 6868 B）：
     `Get-Content $f` = **116** / `Get-Content $f -Encoding utf8` = **129** / `Get-Content $f -Encoding byte -ReadCount 0` = **6868**（= 字节数）/ `ReadAllLines` = **129**；该文件含 **44 行非 ASCII**。
     ⇒ **含非 ASCII 的文件上不可靠；纯 ASCII 文件上通常看不出来（于是更难发现）**。`mindnet_vectors.json` 在错误解码下恰好仍切出 1575 行属**巧合**，不能据此认为 `Get-Content` 可用。
     ⇒ **行数一律用 `[IO.File]::ReadAllLines()` 或 node 换行计数复核**；**给数字前先说清"按什么口径数的"**。
   - **同族但根因不同的一条**：`split('\n').length` 把末尾换行算成**空尾块**（1576 vs 换行数 1575，我自己抓到并订正）—— 这条与编码无关，任何文件都只多不少。
5. **归属更正（审计链，我自己的推测错误）**：`test/tool/mindnet_probe_report_test.dart` 的 **16:18:38** 改动**作者 = captain**（不是 observability-dev，也不在 t19 的 inScope 六条里；observability-dev 对该文件的最后一次写入是把 captain 的草稿**恢复成 64 行 / 2324 B** 原样，此后未改）。内容 = 方案 3 根治（`_hostInProcess` + 把 `host:` 传给 `collectProbe`）＋ 保留显式 5 分钟 timeout；指纹 85 行 / 3752 B / sha256 `768D959F…B6F1FE`。性质 = **登记后补丁、未随任务入账**（本轮四项之一）。
   - **我在过程消息里曾推测"很可能就是 observability-dev 自己改的"——该推测错误，特此更正。** 报告正文从未写入该推测（当时写的是匿名的"16:18:38 的改动"），但这不能免除更正责任：推测出自我，且我未在当时标注"作者未知"。**教训**：**断言"某处改动是谁做的"需要写入者证据；只有时间线证据时应写"由未知一方在 X 时刻改动"**。
