# MindNet 接入 · 独立验证报告（t18）

- **验证者**：verifier（独立于 t14/t15/t16/t17 的实现者）
- **报告时间**：2026-10-01 14:06（本机时钟；文中每个数字都带读数时刻）
- **被测仓库**：Furnace `E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity`
  - HEAD = `ee0a6e11803aca9865cda887ba18981d856423c9`（**本轮所有产物都还没提交**，见 §0.2 的 porcelain）
  - Flutter 3.47.2 / Dart 3.13.2（`dart --version`）
- **工具链**：所有复算脚本放在 `C:\Users\Public\mindnet-verify\`（**两个仓库之外**），见 §9。
- **三态约定**：§1–§7 是「已确认」（每条附命令原文与关键输出行）；§8 是「未能确认 / 如何查证」。

---

## 0. 结论速览

| # | 验收项 | 判定 | 关键数字 |
| --- | --- | --- | --- |
| 1 | 全量 `flutter test --concurrency=1` | **通过（最新读数见 §0.7）** | 14:45:20 起跑：`02:48 +520 ~2: All tests passed!`，exit 0，失败 0（窗口内有一次 l10n 生成写入，按纪律已标注；与队长独立实测 `+519 ~1` 一致）。早期快照：14:03:52 → `+503 ~1`；基线 ee0a6e1 = 360 → **+160 通过 / +2 跳过** |
| 2 | `dart analyze lib test` | **通过（窗口干净，见 §0.7）** | 14:44:21–14:45:20 窗口内 mtime 冻结在 14:44:03：**exit 0，0 error / 0 warning / 87 info**（与队长实测一致）。早期 14:06 快照为 88 info（+1 来自 t9 的 `cognitive_tools.dart:125:14`） |
| 3 | 对拍复算 tierA 43 + tierB B01 | **通过** | tierA 123 字段 0 跳过；B01 135 浮点 + 215 精确，**最坏 rel = 0**（逐位相同） |
| 4 | MindNet 核验（npm test / --check / 逐字节） | **通过（附一条重要发现）** | npm test 141/141 pass；`--check` exit 0；逐字节：两边都 36812 B，**唯一差异是 `generated_from.commit`**；**但 npm test 会改写 MindNet 的工作区**，见 §4.3 |
| 5 | 真实库（`furnace.db`）零写入 | **通过** | sha256 `8C58A610…5EC6`、290816 B、mtime `2026-09-29 23:56:48` 三次读数完全一致；**注意：本节只说用户真实库，不涉及 MindNet 仓库** |
| 6 | Windows release 构建 | **通过** | exit 0、145.7s；`app.so` mtime **14:03:09 > 本轮 app/lib 最后改动 13:58:48**，体积 10355592 → **10404744**（确实重编译），AOT stamp 同步刷新 |
| 7 | MindNet porcelain 为空 + t2 参数合规 | **前者：按队长指令改为「记录并归因」，不判通过；后者：合规** | 存在一处未提交改动 ` M conformance/mindnet_vectors.json`（mtime `13:53:35`、diff 仅 `generated_from.commit` 一行、数值未变）；**本轮我的运行未新增改动**（mtime/sha256 冻结），机制与逐字证据见 §4.3；`fast_diagnosis.dart:775` 的字面量是**不可达兜底**，不是 §6.6 违规（§7） |
| 9 | **（attempt 3 追加）** 协议守卫 + 证伪 | **通过** | 守卫断言在真实 fixture 上 7/7 成立；5 种变异（含把 commit 换回旧值）**全部被抓红** —— 见 §0.5 B |
| 8 | 三态 + 机械闸门 | **通过** | 本文件已过 `audit-claims.mjs`（BLOCKER 0 / WARN 0），命令见 §9 |

---

## 0.5 attempt 3 追加（14:12–14:19）：一条硬阻断 + 两项新验证

队长在本轮把范围扩到「协议守卫、真实库探针、§9、真实库报告数字」。逐项结果：

**(A) 硬阻断（状态更新：14:29 复测该硬错误已消失，但全量套件尚未复跑）—— 工作树在 14:15 时不编译，且有 10 条测试失败，全部落在 t19（`in_progress`）的在建文件里。**
- [跑] `dart analyze lib test` → **exit 3**，`88 issues found.`，其中 **error = 1**：
  ```
  error - lib\features\cognitive\presentation\cognitive_model_page.dart:517:25 - This expression has a type of 'void' so its value can't be used. - use_of_void_result
  ```
  单独 analyzer 该文件同样复现（`1 issue found.`）；文件 mtime `14:10:47`，长度 31636。
- [跑] 全量 `flutter test --concurrency=1`（14:16:34 起跑）→ **exit 1**，失败标记 10 条，全部是 t19 的新文件：
  - `test/features/cognitive/cognitive_model_page_test.dart`：`renders the injected model's numbers, bands and zones`、`the settings entry opens the page`（2 条 `[E]`，另有同名组的其它失败）；
  - `test/tool/mindnet_probe_test.dart`：`reads a read-only copy and leaves the original byte-for-byte alone`（**SqliteException(1): all VALUES must have the same number of terms**，来自 `test\tool\mindnet_probe_test.dart:109` 的 `_seedDatabase`——INSERT 的列数与某一行的值数不一致）、`a failing host is reported with its output…`、`exports the row facts the model seam cannot see by itself`，加尾部 `... and 5 more`。
- [跑] **而且这轮读数本身不可归因**：起跑时 `app` 下最新改动是 `14:16:15`，结束时是 `14:17:34` —— **运行期间仍有人在写**。所以 attempt 3 的这组数字只说明"当前树是红的"，不构成对任何已完成交付物的判决。
- 结论：**在 t19 落盘之前，t18 无法给出通过结论**（验收②明确要求 error/warning = 0/0；验收①要求全绿）。这也解释了我在 14:13 遇到的那次编译失败（`ProbeReport.originalUntouched` 未定义）：那是 `mindnet_probe.dart` 改名 `unchanged`（14:13:32）与旧 `mindnet_probe_report_test.dart`（13:28）之间的**在建中间态**，不是最终产物缺陷。
- **[14:29:04 状态更新] 该 analyzer 硬错误已被修复**：复跑 `dart analyze lib test` → **exit 0**，`87 issues found.`，**error = 0 / warning = 0 / info = 87**（该文件在 14:28:55 仍被编辑，说明修复刚落盘）。**全量套件尚未在修复后复跑**，所以验收①仍待复测；修好后应重跑 4 条 verify（并注意读数要落在树的两次写入之间才可归因）。
- 处置建议：等 `observability-dev`（t19）与 `integration-dev`（t20）落盘后再复跑本任务；我已把上面两条具体错误（analyzer 517:25、`_seedDatabase` 的 SQL 列/值数不匹配）直接发给 observability-dev。

**(B) 协议守卫：已确认通过（含独立证伪）。**
- [读] 守卫测试 `app/test/domain/services/cognitive/mindnet_protocol_guard_test.dart`；常量在 `app/lib/domain/services/cognitive/mindnet_protocol.dart`（`conformanceProtocol` L23、`frozenSnapshotCommit` L30-31 = `ace605d…`、`snapshotPackageVersion` L34、`floatRelTolerance` 1e-12 L37、`floatAbsTolerance` 1e-15 L40、`roundedDecimals` 6 L43、`mustBeExact` 7 项 L46-54）。
- [跑] 我不改仓库、在内存里复制 fixture 后逐条变异，用自写脚本 `guard_falsify.dart` 复现守卫的**断言逻辑**：
  ```
  [positive control] real fixture        -> passed=7 failed=0
  [falsification] commit replaced with an older one (the drift that matters) -> detected=YES
  [falsification] protocol string changed                                    -> detected=YES
  [falsification] package_version changed                                    -> detected=YES
  [falsification] tolerances.rel loosened                                    -> detected=YES
  [falsification] tolerances.must_be_exact loses an entry                    -> detected=YES
  mutations caught: 5 / 5
  GUARD VERDICT: PASS (holds on the real fixture, and every mutation is detected)
  ```
  即：**守卫不是装饰**——把 commit 换回旧值 `107ab12…` 会被抓红（这正是"拷贝漂移"的场景）。
- 过程诚实记录：第一次跑时"真实 fixture"报了 1 条假红 —— 那是**我脚本的比较器 bug**（用 `==` 比较 `List<String>` 与 `List<Object?>`，Dart 的 `==` 对 List 是同一性判断），不是守卫的问题；正向对照正是为此存在，已修正后为 7/7。
- 覆盖面声明：本项复现的是守卫的**断言逻辑**（对内存中的变异副本），**不是** flutter_test 的运行接线；接线那部分由套件里的守卫测试本身覆盖（它在 attempt 2 的 503 全绿里）。

**(C) 真实库探针 / 4 卡数字：未能验证（原因明确）。**
- [跑] `flutter test test/tool/mindnet_probe_report_test.dart "--dart-define=PROBE_DB=<真实库>"` → **exit 1**，编译失败：
  `test/tool/mindnet_probe_report_test.dart:59:19: Error: The getter 'originalUntouched' isn't defined for the type 'ProbeReport'.`
  （该文件当时是 13:28 版，而 `tool/mindnet_probe.dart` 已在 14:13:32 改成 `unchanged`。）
- [读] 探针的安全设计我读过了，可以确认其**只读机制**成立：`tool/mindnet_probe.dart:215-226` 把库连同 `-wal`/`-shm` **复制到临时目录**，只打开副本；原文件仅被 `stat`（L213/L269/L276-279），且 `report.originalUntouched`/`unchanged` 把"原库未被修改"变成返回值。
- [跑] 无论那次编译失败，我都做了真实库前后读数：`8C58A610…5EC6`（290816 B，mtime 2026-09-29 23:56:48）在探针尝试**前后完全一致** —— 探针没有碰到原库。
- **4 卡数字（R 0.518/0.840，均值 0.759）我没有独立复算成功**：入口当前编译不过 + 树在变，拿不到可信的探针输出。这正是 §8 里"未能确认"的那条。

---

## 0.1 队长紧急指令执行清单（2026-10-01 14:25）

| 要求 | 执行情况 |
| --- | --- |
| ① 只许跑 `npm test` / `node tools/conformance.js --check` / 只读 `node -e require(...)`；禁止 `npm run conformance`、裸 `conformance.js`、`--write`、任何写盘自建脚本 | **已遵守**。完整命令清单见 §4.6；三条禁用命令**从未执行**。需要更正一处机制：这次的写盘**不是**由裸生成路径造成的，而是 `npm test` 在 MindNet 自带测试内自动执行 `--write`（见 §4.3(d)） |
| ② 验收⑦ 改为「记录并归因」：贴 porcelain 输出 + `git diff` 全文 + mtime；写明是本轮开始前就存在的脏文件、未写入、未回滚；并给出我运行前后的 status 对比 | **已落地**：§4.3(a) 逐字输出、(b) 文件事实、(c) 前后对比表、(e) 未写入未回滚 |
| ③ 报告不得声称"MindNet 零写入 / porcelain 为空"；不可判定的按三态写"未能确认（原因）" | **已遵守**：全文搜过「零写入/为空/未被修改」，剩余出现处均已限定为**用户真实库**（§0 表第 5 行、§5 标题与范围声明、§4.6），MindNet 侧一律写"存在一处未提交改动 + 本轮未新增" |

---

## 0.6 t33 准备（**不是 t33 结论**）：4 卡数字的独立路径已验证可用

> 背景：队长指派 t33，要求用**另一条独立路径**（如 `node:sqlite` 只读打开副本）独立复算真实库 4 卡数字并与探针输出逐卡比对。t33 依赖 t19/t20/t30，尚未解锁。本节只记录**方法验证与预备读数**，不代替 t33。

**[跑] 方法验证（只读，原库未打开）**：把 `furnace.db` 复制到临时目录后用 `node:sqlite`（Node **v24.19.0**，`require('node:sqlite')` 可用）以 `{readOnly:true}` 打开**副本** → 成功读出 31 张表、`card_states` 19 列、**4 行**；原库 sha256 前后均为 `8C58A610…5EC6`、mtime 仍 `2026-09-29 23:56:48`，临时副本已删除。

**[跑] 预备复算（我自写的曲线实现 + 自写驱动，读数时刻 `2026-10-01T06:39:24Z` = 本机 14:39）**：
口径：`R = R0·Ψ(t/S_hours)`、`Ψ(z)=(1+c·z)^(−γ)`、`c=0.9^(−1/γ)−1`、`γ=0.1542`、`S_hours = stability×24`、`R0 = encoding_strength ?? 1.0`（四行的 `encoding_strength` 与 `savings` **均为 NULL**，故 R0 全取 1.0、Σ 全取 0.8）。
```
kp-2d76…  S=2.3065d -> 55.356h  t=119.714h  z=2.1626  R=0.839071  (3dp 0.839)
kp-6f20…  S=0.06908d -> 1.658h  t=119.708h  z=72.2007 R=0.517372  (3dp 0.517)
kp-9272…  S=2.3065d -> 55.356h  t=119.722h  z=2.1628  R=0.839065  (3dp 0.839)
kp-aaff…  S=2.3065d -> 55.356h  t=119.720h  z=2.1627  R=0.839067  (3dp 0.839)
mean R = 0.758644  (3dp 0.759)
```
与队长给的基线（议论文结构 R 0.518、其余三张 0.840、均值 0.759）**在同一量级且可解释地接近**：均值 0.759 完全一致；两张的第三位小数差 0.001，符合 `R` 随时间单调下降（约 −0.0008/h）——队长的探针比我这次复算早约 0.7 小时，故他的读数略高（0.840/0.518 vs 我的 0.839/0.517）。
**因此 t33 的判定口径必须写明**：探针与我的复算要在**同一个 `now` 附近背靠背跑**，容差按时间差折算（或把 `now` 固定后两边同传）。增益（16.08 / 11.50）我尚未独立复算，留到 t33。

---

## 0.7 独立复现（2026-10-01 14:44–14:48，应队长邀请、按新纪律记录 mtime）

> 纪律（§4.6 第三条）：跑门前先看 `app/lib`/`app/test` 最新 mtime；与运行窗口重叠就把读数标为"不可归因"。

**[跑] `dart analyze lib test` —— 窗口干净，读数可完整归因**
```
A. 起跑前 mtime = 2026-10-01 14:44:03   (14:44:21 读数)
B. 静置 45s 后   = 2026-10-01 14:44:03   (14:45:06 读数)   ← 期间无写入
   命令：dart analyze lib test   →   exit=0，末行 `87 issues found.`
   机械计数：error = 0 · warning = 0 · info = 87
C. 跑完后 mtime  = 2026-10-01 14:44:03   (14:45:20 读数)   ← 窗口内无写入
```

**[跑] 全量 `flutter test --concurrency=1` —— 结果全绿，但窗口内有一次生成文件写入（按纪律标注）**
```
起跑 14:45:20  →  `02:48 +520 ~2: All tests passed!`，exit=0，失败标记 0
D. 跑完后 mtime = 2026-10-01 14:48:06
   期间被写的文件（3 个，均为生成的本地化文件）：
     app/lib/l10n/app_localizations.dart
     app/lib/l10n/app_localizations_zh.dart
     app/lib/l10n/app_localizations_en.dart
```
- 按纪律，这条读数的**窗口不是干净的**（14:48:06 落在 14:45:20–14:48:23 之间）⇒ 行级细节不完全可归因；但**结论（全绿、0 失败）与队长独立实测一致**（他报 `+519 ~1`），两者互证。
- 计数差的解释（可查证）：`app/test/tool/mindnet_probe_test.dart` 在 **14:41:03** 被改过，新增了一条测试与一条 skip（日志里可见跳过原因 `Skip: driven by tool/mindnet_probe.dart`），因此 **520/~2** 对应的是更晚一点的树；队长读到的 519/~1 对应他跑的那一刻。
- 两条 skip 都能定位：①`test/tool/mindnet_probe_report_test.dart` 的 `PROBE_DB` 开关（无 key 时不跑真实库）；②`mindnet_probe_test.dart` 里标着 `Skip: driven by tool/mindnet_probe.dart` 的那条。

---

## 0.8 t33 独立验证（软 MindNet 口径）：守卫证伪 + 真实库 4 卡复算 + 观测面/工具只读性

> 判定协议（队长定稿，本节照此执行）：探针用 JSON 取全精度 `nowHours`（**驼峰**；`now_hours` 是已废弃的草稿名，JSON 里没有该键） → 用**同一个 now** 跑独立复算 → **逐卡比全精度 R/增益**（不比展示值）。软口径：MindNet 项只**如实记录并归因**，不以 porcelain 为空为通过条件。

### 0.8.1 真实库 4 卡：逐卡比对（**核心项**）
**[跑] 探针（应用侧）**：`dart run tool/mindnet_probe.dart --db "<真实库>" --json`
```
nowHours   = 497454.9783786111
cards      = 4      meanR = 0.7584139962031732      meanGain = 12.713817045888545
source.unchanged = true（sha256_before == sha256_after，modified_before == modified_after）
```
**[跑] 我的独立复算（另一条路径）**：`node:sqlite` 以 `{readOnly:true}` 打开**副本** + **MindNet 参考实现** `mechanisms/memory.dsr.js`（`retrievabilityOf` / `stabilityIncrease`）+ 我自己的列映射（`R0=encoding_strength??1.0`、`S_hours=stability×24`、`Σ=savings??0.8`、`D=difficulty`、`lastReview=last_reviewed_at/3.6e6`），**同一个 `nowHours`**：
```
kp-6f201136…（议论文结构） R probe=0.517160668 mine=0.517160668 |dR|=0.000e+0   gain probe=16.117715122 mine=16.117715122 |dG|=0.000e+0
kp-92728def…              R probe=0.838829595 mine=0.838829595 |dR|=0.000e+0   gain probe=11.579339669 mine=11.579339669 |dG|=1.421e-14
kp-aaff3ff3…              R probe=0.838830674 mine=0.838830674 |dR|=0.000e+0   gain probe=11.579262656 mine=11.579262656 |dG|=0.000e+0
kp-2d76e863…              R probe=0.838835047 mine=0.838835047 |dR|=0.000e+0   gain probe=11.578950736 mine=11.578950736 |dG|=1.243e-14
mean_r   probe=0.7584139962031732  mine=0.7584139962031733  |diff|=1.110e-16
mean_gain probe=12.713817045888545 mine=12.713817045888552 |diff|=7.105e-15
CARD-BY-CARD: MATCH (R within 1e-9, gain within 1e-6)      exit 0
```
- [跑] 原库 sha256 全程 `8C58A610…5EC6`、mtime `2026-09-29 23:56:48` 未变（探针自报 `unchanged=true` 与我的外部读数一致）。
- 与队长给的基线（0.518 / 0.840×3 / 均值 0.759，增益 16.08 / 11.50）：**同一批量**，差异全部由 `now` 的时间差解释（其探针早约 0.7 小时 → R 略高、gain 略低；`R` 随时间下降、gain 随时间上升，方向自洽）。

### 0.8.2 ⚠ 发现：托管入口 `test/tool/mindnet_probe_report_test.dart` 在**默认 30 s 超时**下会失败
- [跑] `flutter test test/tool/mindnet_probe_report_test.dart "--dart-define=PROBE_DB=<真实库>"` → **exit 1**：
  `TimeoutException after 0:00:30.000000: Test timed out after 30 seconds`（该次原库 sha256 未变）。
- [跑] 同一命令加 `--timeout=5m` → **`00:36 +1: All tests passed!`**，exit 0（耗时约 36 s，超过默认 30 s）。
- 影响：任何照文档原样跑这条命令的人都会看到失败。建议 t19/t34 给该用例显式 `timeout`（或提速），并在文档里写清"需要 `--timeout`"。**我没有改代码**（不在我的 inScope）。

### 0.8.3 守卫证伪（复跑，当前树）
- [跑] `guard_falsify.dart` → 真 fixture 断言 **7/7 成立**；5 种变异**全部抓红**：commit 换回 `107ab12…`、协议号、package_version、`tolerances.rel` 放宽、`must_be_exact` 少一项。`GUARD VERDICT: PASS`。
- 覆盖面：复现的是守卫**断言逻辑**（对内存变异副本），不是 flutter_test 接线。

### 0.8.4 观测面 / 工具只读性
- [跑] `flutter test test/features/cognitive/cognitive_model_page_test.dart test/features/ai/cognitive_tools_test.dart test/tool/mindnet_probe_test.dart` → **`+36 ~1: All tests passed!`**，其中包含页面用例 **`writes nothing to the database it reads`**、读数页九区四带用例、`collectProbe` 系列用例。
- [读] 探针的只读机制：复制副本（含 `-wal`/`-shm`）→ 只开副本 → 原库仅被 `stat`，并把 `sha256_before/after`、`modified_before/after`、`unchanged` 写进 JSON（本次 JSON 实测 `unchanged=true`）。

### 0.8.5 MindNet 状态（软口径：如实记录并归因）
- [跑] `git -C "E:\Document\MindNet" status --porcelain` → ` M conformance/mindnet_vectors.json`（**与 §4.3 同一条、mtime 仍 13:53:35、数值未变**）。本轮我**未写入、未回滚、未新增**；机制与证据链见 §4.3。

### 0.8.6 窗口纪律（按 §4.6 第三条如实标注）
- 本节各项检查的窗口为 14:52:54 → 14:59:34（`app/lib`+`app/test` 下 `*.dart` 最新 mtime 有变动），因此按纪律标注"**窗口内有一次写入**"；三项检查本身均 exit 0 / 全过，且与队长实测互为印证。我没有归因那次写入（未确认是哪个文件、谁的改动）。

---

## 1. 全量测试

### 1.1 基线（同一台机器、上一轮会话测得，供对比）
- [跑] 基线于 `ee0a6e1` 干净树：`flutter test --concurrency=1` → 末尾 `04:06 +360: All tests passed!`，exit 0。

### 1.2 本轮第 1 次（覆盖到 13:55 左右的树）
- [跑] 命令：在 `...\class-productivity\app` 执行 `flutter test --concurrency=1`
- [跑] 结果：`=== FULL TEST EXIT: 0 ===`；末尾 `02:10 +491 ~1: All tests passed!`；失败标记计数 0。
- 说明：这次读数（491 通过 / 1 跳过）**不是最终值** —— 跑完后 t9 的 `cognitive_tools.dart`（13:58:48）与 `tool_registry.dart`（14:03:22）才落盘。

### 1.3 本轮第 2 次（**本报告采用的口径**，树在整个运行期间没有变化）
- [跑] 起跑时刻 `14:03:52`，当时 `app/lib` 最新改动 = `ai_providers.dart` @ `14:03:47`；
- [跑] 结果：`=== RUN #2 EXIT: 0 ===`，末尾
  ```
  01:50 +503 ~1: E:/.../test/widget_test.dart: smoke test
  01:50 +503 ~1: All tests passed!
  ```
  失败标记（`[E]` / `Some tests failed` / `Failed to load`）计数 **0**。
- [跑] 结束时刻再读 `app/lib` 最新改动：**仍是 `ai_providers.dart` @ `14:03:47`** → 整个运行期间**没有任何源码写入**，这个 503 是可归因的快照。
- [跑] 与基线对比：**360 → 503（+143 通过）**，另新增 1 条「默认跳过」的用例（基线的 `~` 计数是 0）。

### 1.4 那 1 条跳过的用例是什么（不是失败）
- [跑] 日志中 `~1` 首次出现在加载 `test/tool/mindnet_probe_report_test.dart` 之后，并伴随打印
  `set --dart-define=PROBE_DB=<path> to run the probe`。
- [读] 该文件 `test/tool/mindnet_probe_report_test.dart:37`：
  `markTestSkipped('set --dart-define=PROBE_DB=<path> to run the probe');`
- 结论：这是**真实库只读探针的显式开关**（默认不跑，避免碰到用户真实数据）。它对 §5 的"**真实库**零写入"结论是**有利**证据：本轮没有任何用例去打开真实库。（注意区分：§5 讲的是用户真实库 `furnace.db`；**MindNet 仓库另有一处未提交改动**，见 §4.3。）

---

## 2. 静态分析

- [跑] 第 1 次：在 `app` 执行 `dart analyze lib test` → `exit=0`，末行 `87 issues found.`；机械计数 `error = 0`、`warning = 0`、`info = 87`。
- [跑] 第 2 次（与 §1.3 的 503 快照同一时刻，14:06 读数）：`exit=0`，末行 `88 issues found.`；`error = 0`、`warning = 0`、`info = 88`。
- [跑] 用 `Compare-Object` 逐行比对两份 analyze 输出，**唯一新增行**是：
  ```
  info - lib\features\ai\tools\cognitive_tools.dart:125:14 - Use 'const' with the constructor to improve performance. - prefer_const_constructors
  ```
- 结论：**error/warning 都是 0**（满足验收期望）；比基线多的那 1 条 info 出自 **t9 的新文件** `cognitive_tools.dart`（13:58:48 落盘），**不是** t14/t15/t16/t17 引入的。

---

## 3. 对拍复算（全部用我自己写的比较器，**不经过被测实现自带的 `round6`**）

### 3.1 tierA 43 条公开值
- [跑] 自写 Dart 比较器 `tierA_43_check.dart`（取整用我自己的 half-away-from-zero：`floor/ceil + 0.5`，不调用 `DsrMemory.round6`）：
  ```
  tierA vectors in file : 43
  vectors exercised     : 43
  vectors untouched     : (none)
  published fields      : 123 compared, 0 not produced by the port
  max |raw - published| : 4.966366304870462e-7 at A05-schedule-target0.5.hours
  43 PUBLISHED VALUES: PASS (verifier's own rounding, no field skipped)
  exit=0
  ```
- [跑] JS 侧重算（走 fixture 自己的 `input`，不调用 `tools/conformance.js` 的 `tierA()`）：`fields compared: 123`，`JS RE-DRIVE OF 43 PUBLISHED VALUES: PASS`。
- 读法：`expected` 是 round6 后的展示值，所以 `raw - published` 最大 ~5e-7 是**取整差**；两侧报出的最大偏差连末位都相同（`4.966366304870462e-7`，同一字段）。
- 字段对账：43 条共 **123 个公开字段全部产出、逐条比较，没有一条被跳过**（脚本内计数对账，不等则 exit 1）。
- 被测版本指纹：`dsr_memory.dart` sha256 = `1237B1FB5B35E5B1E56AD40DA6CBF16ECDCFE98F86FC1F64CEF0761A1AFB0E46`（mtime `2026-09-29 23:27:00`，本轮未变）。

### 3.2 tierA 115 条 raw 探针（契约 §8.4 点名最危险的 `R0 < 1` 区域）
- [跑] 我用 live JS 现场生成 115 条**不在公开 fixture 里**的探针（`R0∈{0.3,0.7,0.95,1.0}`、含 `target ≥ R0` 返回 0 的分支、五种复习事件），让 Dart 端口 **raw-vs-raw** 对拍：
  ```
  cases: 115  by kind: {retrievability: 60, scheduleInterval: 15, applyReview: 40}
  numeric comparisons: 1007
  worst rel diff: 6.201628572528707e-16  at P-review-R00.7-S240-failure_feedback-c0.9-t60.state.S
  PROBE RESULT: PASS — every raw value within rel<=1e-12 / abs<=1e-15
  ```
- 这条**强于**仓库自带测试：它不依赖被测实现自己的取整函数，且覆盖了公开 43 条里没有的 `R0∈{0.3,0.7}`。

### 3.3 tierB B01（集合/枚举逐位、浮点 rel ≤ 1e-12）
- [跑] 自写 Dart 比较器 `tierb_b01_check.dart`：从 fixture 的 `input` 自建引擎、**直接读端口的 raw 字段**（不用它的 `toJson()`）、按生成器的取整策略分字段比较（`availability/drive/scores/a/q` 先 round6；`dar_used`、`drive_edges.{ls,al,ms,contribution}`、`states[].al` 按 raw 比）：
  ```
  vector          : B01-fast-layer-chain-5-rounds
  rounds expected : 5
  rounds produced : 5
  float comparisons : 135
  exact comparisons : 215
  worst rel diff    : 0.0 at
  B01 DART CHECK: PASS — sets/enums exact, floats within rel<=1e-12/abs<=1e-15
  ```
  即：**350 项比较全部逐位相同**（最坏相对差 0.0），包括集合/枚举（`admitted`/`focus`/`outcompeted`/`conscious`/`subconscious`/`states[].state_after`）与每轮的键集合。
- [跑] JS 侧独立复算（绕过 MindNet 自己的生成器，直接 `require` `src/index.js` + `src/v2/engine.js` 驱动）：`floats=130 exact=200`、`worst float rel=0`、`module_defaults drift entries: 0` → 样例的输入与期望自洽。

### 3.4 一条必须写进结论的限定：**B01 的 5 个快照是同值，它不检验"逐轮推进"**
- [跑] 读 fixture 自身：`distinct rounds (whole-object): 1`（5 个快照字节级相同）；每轮 `round=1`、`cycle_ticks=1`。
- [跑] 读引擎：第 1 步后 `_stopped=true`、`_stop_reason="all_targets_reached"`、`_rounds=1`、`_max_rounds=100`；第 2–5 步 `sameObjectAsBefore=true`（复用同一个 `_lastRound`）。
- 因此 **B01 通过只证明**「第 1 轮逐字段正确」+「停止后 step 是 no-op」；**不能**证明状态机逐轮演化。把它当成"快层整体正确"的证据会过度解读。
- [跑] 补强证据我已独立复核：新 fixture `mindnet_tierb_diagnosis.json` 的 `scenarios.multiround_progression` 是 **6 个互不相同的快照**（`round_numbers=[1,2,3,4,5,6]`），目标第 1 轮不亮、第 6 轮才越阈：`a(t)` = `0 → 0.004447 → 0.012634 → 0.024235 → 0.039035 → 0.056621`，`target_lit_in_round_1=false`，`run.target_steps={"t":6}`、`stop_reason=all_targets_reached`（读 fixture 得到）。

### 3.5 新诊断 fixture 的输入↔期望自洽性（我自己驱动 live JS 复算）
- [跑] 用我自己的驱动脚本重跑 fixture 的 `input`，与 `expected` 比对（覆盖范围**明确列出**）：
  ```
  multiround_progression: MATCH
  engine_diagnosis: run+facts MATCH
  weak_node: run+facts MATCH
  slow_target: run+facts MATCH
  dead_end: run+facts MATCH
  numeric values compared: 584 (bit-identical: 584)
  TIERB DIAGNOSIS FIXTURE RE-DRIVE (covered subset): PASS — input reproduces expected
  ```
  （`slow_target` 必须实现"第 5 轮补边 + `add_initial_nodes`"的 `late` 干预才吻合——第一次我漏了这步，25 项不匹配；补上后**全部逐位相同**。这也顺带验证了 `late` 语义本身。）
- **未覆盖**（见 §8）：该 fixture 的 `diagnosis`、`baseline_reachability`、`plan`、`counterfactual`、`danger_rows` 我没有驱动复算。

---

## 4. MindNet 侧核验

### 4.1 `npm test`
- [跑] `cd E:\Document\MindNet; npm test` → `npm test exit=0`；TAP 汇总：
  ```
  ℹ tests 141
  ℹ pass 141
  ℹ fail 0
  ℹ duration_ms 2854.1421
  ```

### 4.2 `node tools/conformance.js --check` —— **口径必须写对**
- [跑] → `样例一致：43 条 tierA + 1 条 tierB`，`check exit=0`。
- [读] `tools/conformance.js:270-302` 是 `--check` 分支：只 `readFileSync` 磁盘文件、与"当前实现现算出来的文本"比较；比较时**先把 `generated_from.commit` 归一化掉**（L282-294：`strip()` 把 commit 置 null 后再比）。
- **因此 `--check` 只能证明：MindNet 当前实现 vs MindNet 自己的 `conformance/mindnet_vectors.json` 不过期。它不能证明 Furnace 里那份拷贝是新的**（commit 被归一化，拷贝漂移它看不见）。
- 这一点在 Furnace 侧已有对口守卫：`app/test/domain/services/cognitive/mindnet_protocol_guard_test.dart:1-9` 的注释明确写了同一句结论，并在 `:45-57` 断言 fixture 的 `generated_from.commit` == `MindNetProtocol.frozenSnapshotCommit`（`app/lib/domain/services/cognitive/mindnet_protocol.dart:30-31` = `ace605d9778e8641957c570c1e58049ca82e4a01`）。**Furnace 快照的新鲜度由这个 Dart 守卫负责，不由 `--check` 负责。**

### 4.3 MindNet 工作区的未提交改动：**记录与归因**（不判"通过"，也不回滚）

> 按队长 2026-10-01 紧急指令：验收⑦ 与 t26 的"porcelain 为空"已不可能满足，改为**记录并归因**。本节即为该记录。

**（a）命令原文与逐字输出**（读数时刻 2026-10-01 14:25:39）
```
$ git -C "E:\Document\MindNet" status --porcelain
 M conformance/mindnet_vectors.json

$ git -C "E:\Document\MindNet" diff --stat
 conformance/mindnet_vectors.json | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)

$ git -C "E:\Document\MindNet" diff          # 全文
diff --git a/conformance/mindnet_vectors.json b/conformance/mindnet_vectors.json
index 2d99151..8fb71e8 100644
--- a/conformance/mindnet_vectors.json
+++ b/conformance/mindnet_vectors.json
@@ -2,7 +2,7 @@
   "protocol": "mindnet.conformance/1",
   "generated_from": {
     "repo": "https://github.com/FirsryFan/MindNet",
-    "commit": "107ab12db7d9fd278a6f451dfc1260eacf57dc8a",
+    "commit": "f4eec9bae16e6e303c19177e7fbfcf7a756f6629",
     "package_version": "2.0.0-alpha.1",
     "generator": "tools/conformance.js"
   },
```
**（b）文件事实**：`conformance/mindnet_vectors.json` · size **36812 B**（未变）· mtime **2026-10-01 13:53:35** · sha256 `C62F55F412727507E09517A1DC0C7A0B078C4DC087096CE9DB1C1C658F3C6A71`；MindNet HEAD = `f4eec9b…`。改动**只有 `generated_from.commit` 这一行**，全部数值未变。

**（c）本轮我的运行前后对比（证明本轮未新增改动）**

| 时刻 | `git status --porcelain` | 文件 mtime | 说明 |
| --- | --- | --- | --- |
| 13:52:53 | **（空，0 行）** | 09-26 的旧时间 | 我开工时的读数 |
| 13:53（跑 `npm test` 后） | ` M conformance/mindnet_vectors.json` | **13:53:35** | 见 (d) 的机制 |
| 14:12:02 / 14:13 / 14:21:40 / 14:25:39 | 同上，**恒为同一行** | **仍 13:53:35** | attempt 3 的每一次读数，mtime 与 sha256 均**未变** |

结论：**本轮（attempt 3，14:12 之后）开始时它就已经是这个状态；本轮我跑的所有命令都没有新增或改动任何 MindNet 文件**（mtime/sha256 冻结在 13:53:35 / C62F55…）。

**（d）归因（写清机制，不用"某人跑了生成路径"含糊过去）**
- 直接原因**不是**任何 `--write`／`npm run conformance`／不带 `--check` 的 `conformance.js` 手动调用 —— **我从未执行过这三者**。
- 真正写盘的是 **MindNet 自己的测试**：`test/conformance.test.js:123-129` 的用例（**写盘调用在 L126**，L127 紧接着用 `--check` 自证；权威范围经三路计数互证），其中
  ```js
  123: test('样例 · 生成器可被工具调用（--write 后 --check 必须通过）', () => {
  124:   // 这是一条"幂等"断言：写一次、校验一次，保证生成器本身是确定性的
  125:   const script = path.join(__dirname, '..', 'tools', 'conformance.js');
  126:   execFileSync(process.execPath, [script, '--write'], { stdio: 'pipe' });
  127:   const out = execFileSync(process.execPath, [script, '--check'], { stdio: 'pipe' }).toString();
  ...
  ```
  即 **`npm test` 会在用例内部自动执行 `node tools/conformance.js --write`**（写盘位置：`tools/conformance.js:304-305` 的 `mkdirSync`/`writeFileSync`；`--check` 只读分支是 L270-302）。
- **交叉印证**：tierb-dev 独立把根因定位到同一段（`test/conformance.test.js:123-129` 的用例，**写盘调用在 L126**），并写进 `docs/VERIFICATION_PROTOCOL.md`（**登记在 t36（completed），32487 B**；早先同内容的 t25 因"porcelain 为空"这条环境前置条件未满足而以 failed 收口，属历史记录 —— 引用时以 t36 为准）。两人的行号与机制一致：**L126 是唯一的写盘调用，L127 紧接着用 `--check` 自证**。
- 触发者：**verifier（本报告作者）**，于 13:53 执行 t18 验收④明确要求的 `npm test` 时**间接**触发。这不是越界写 MindNet，但也不是"无人写入"——**准确说法是：由被任务要求的命令间接触发的一次自动写盘**。

**（e）我未写入、未回滚**
- 未写入：我从未直接调用任何写盘路径（见 §4.6 的命令白名单与禁用清单）；我的全部自建脚本都放在仓库外 `C:\Users\Public\mindnet-verify\`，且只读。
- 未回滚：用户约束是"绝不创建/修改/删除 MindNet 任何文件"，回滚同样是写操作，**我没有执行**。处置权在用户/队长（可选：`git -C E:\Document\MindNet checkout -- conformance/mindnet_vectors.json`，内容无损——只把 commit 标签退回 `107ab12`，数值一致性已由 `--check` 独立证明）。

**（f）验收口径修正**：验收⑦的"porcelain 为空"**不成立**，且按队长指令不得写成通过；本报告把它标为「**记录并归因**」（见 §0 表第 7 行）。同时提醒：**"跑 MindNet 的 `npm test`"与"porcelain 为空"天然互斥**——只要按原验收去跑 `npm test`，就必然产生这一行 diff。后续若还要跑 `npm test`，判据应写成"存在且仅存在这一处、且为本会话已知的自动写盘"。

### 4.6 我对 MindNet 执行的命令清单（自证合规）

- **跑过（全部只读）**：`npm test`（唯一一次会写盘的，且是被验收④要求、由 MindNet 自带测试间接触发）；`node tools/conformance.js --check`（多次）；`git status/diff/log/rev-parse/cat-file`；`node -e "require('E:/Document/MindNet/mechanisms/memory.dsr.js')"` 等只读 require（内存求值，不落盘）。
- **从未跑过**：`npm run conformance`、`node tools/conformance.js`（不带 `--check`）、`node tools/conformance.js --write`、任何以 MindNet 为输出目标的脚本。
- **禁令的正确写法（比逐条列举更稳，采纳自 reviewer 的独立发现，我已复核源码）**：**MindNet 侧只允许 `--check`**。理由：`tools/conformance.js:266-308` 整段里**唯一的只读分支**就是 `if (args.includes('--check'))`（L270）；**任何不带 `--check` 的调用都会落到 L304-305 的 `fs.writeFileSync`** —— 包括 `npm run conformance`（`package.json` 里它等价于**不带参数**的 `node tools/conformance.js`）。
- **自建脚本位置**：全部在 `C:\Users\Public\mindnet-verify\`（两个仓库之外），且只读；无任何脚本向 MindNet 写盘。
- **两条可复用的操作结论**（与 tierb-dev 登记在 **t36** 的 `docs/VERIFICATION_PROTOCOL.md` 一致）：
  1. **"MindNet 零写入"的核验要放在整轮动作的最后** —— 只要中途跑过 `npm test`，工作区就会再脏一次，早前的读数作废；
  2. **核验 MindNet 侧新鲜度只用 `node tools/conformance.js --check`**（实测它不改状态：跑完 `status` 仍是同一行 diff）。
- **第三条（来自队长 15:0x 的复盘，我采纳）**：**跑门之前先看 `app/lib` 与 `app/test` 的最新 mtime**；若最新 mtime 与本次运行的起跑/结束时间**重叠**，则该读数一律标为"**不可归因**"并重跑。本报告 §0.5(A) 那组 10 条失败正是这么产生的：14:16:34 起跑、最新改动 14:16:15→14:17:34，属 t19 写入期中间态（队长 15:0x 实测该树已全绿：`+519 ~1 All tests passed!`、analyze 87 info / 0 error / 0 warning）。

### 4.4 Furnace fixture vs MindNet 向量：逐字节比对
- [跑] 我的比对脚本同时做"字节级"和"字段级"两件事，当前结果：
  ```
  bytes Furnace: 36812  MindNet: 36812
  raw identical: false
  protocol  A: mindnet.conformance/1  B: mindnet.conformance/1
  commit    A: ace605d9778e8641957c570c1e58049ca82e4a01  B: f4eec9bae16e6e303c19177e7fbfcf7a756f6629
  tolerances equal: true
  tierA len  A: 43  B: 43
  tierA ids equal (same order): true
  tierB ids A: [ 'B01-fast-layer-chain-5-rounds' ]  B: [ 'B01-fast-layer-chain-5-rounds' ]
  --- tierA value diffs (ignoring generated_from) ---
  (none)
  --- tierB value diffs (ignoring generated_from) ---
  (none)
  ```
- 读法：**两个文件同为 36812 字节；逐字节不完全相同，差异被限定在 `generated_from.commit` 这一个字段**（40 字符 → 40 字符，长度不变）；其余所有数值、`tolerances`、条目数与顺序完全一致。这与 t17 守卫钉住的常量（`ace605d`）一致，也与 `docs/MINDNET_CONTRACT.md` §9 的「快照更正」一致 —— 该段原文：「§8 写作时的基准是 `c624884`，但仓库里这份 fixture 实际是 **`ace605d`** 生成的；以文件为准，常量按 `ace605d` 钉住（§8 作为历史留档不改写）」。⚠ 该段位置已随契约增补漂移（14:08 读数 L652-653 → **16:41 复核 L656-657**；文件本身在此期间多次被改，16:41 时为 50779 B / mtime 16:39:40），**引用时以原文为准，不要以行号为准**。

---

## 5. 真实库（`furnace.db`）零写入

> 范围声明：本节只讲**用户真实数据库** `C:\Users\firsr\AppData\Roaming\FirsryFan\Furnace\furnace.db`。**MindNet 仓库另有一处未提交改动**（§4.3），两者不是一回事，不要混读。

- 目标：`C:\Users\firsr\AppData\Roaming\FirsryFan\Furnace\furnace.db`
- [跑] 三次读数（验证活动**之前** / 跑完全量测试+release 构建**之后** / 第二次全量测试**之后**）：
  | 读数 | 时刻 | size | mtime | sha256 |
  | --- | --- | --- | --- | --- |
  | BEFORE | 13:52:53 | 290816 | 2026-09-29 23:56:48 | `8C58A610A757B2DFD2489F72CBCE79FCC785D504C5558D23966BAEA9E4615EC6` |
  | AFTER-1 | 14:03:30 | 290816 | 2026-09-29 23:56:48 | `8C58A610A757B2DFD2489F72CBCE79FCC785D504C5558D23966BAEA9E4615EC6` |
  | AFTER-2 | 14:06:22 | 290816 | 2026-09-29 23:56:48 | `8C58A610A757B2DFD2489F72CBCE79FCC785D504C5558D23966BAEA9E4615EC6` |
- 结论：**sha256、大小、mtime 三项完全一致**，且与验收里给出的基线 sha256 逐字符相同 → 全量测试、静态分析、对拍复算、MindNet 核验、release 构建**都没有写用户真实库**。
- 覆盖面声明（避免过度解读）：本轮全量测试中那条会去读真实库的探针用例**处于默认跳过状态**（§1.4），所以本证据同时说明"跑测试不会碰真实库"，但**没有**覆盖"显式打开真实库的探针路径"（那需要 `--dart-define=PROBE_DB=`）。

---

## 6. Windows release 构建（走 ASCII junction）

- [跑] 起跑 `14:00:45`，工作目录 `E:\Document\furnace-build`（junction → `...\class-productivity\app`）。
- [跑] 起跑时 `app/lib` 最新改动 = `cognitive_tools.dart` @ **13:58:48**。
- [跑] 命令 `flutter build windows --release` 输出：
  ```
  Building Windows application...                                   145.7s
  ✓ Built build\windows\x64\runner\Release\furnace.exe
  === BUILD EXIT: 0 ===
  ```
- [跑] 产物 `build\windows\x64\runner\Release\data\app.so`：
  | | 体积 | mtime | sha256 |
  | --- | --- | --- | --- |
  | 构建前 | 10355592 | 2026-10-01 **10:36:24** | — |
  | 构建后 | **10404744** | 2026-10-01 **14:03:09** | `673A05EF37EE0B7BAF65FD342A4518565BDAE2D403E04E4FB999316DED37F59A` |
- [跑] AOT 相关 stamp：`aot_elf_release.stamp = 14:03:09`、`windows_aot_bundle.stamp = 14:03:10`、`kernel_snapshot_program.stamp = 14:02:36`（全部刷新）。
- **判定**：`app.so` mtime `14:03:09` **晚于**本轮 `app/lib` 最后改动 `13:58:48`，且体积变化（10355592 → 10404744）证明是真的重新 AOT，不是旧产物；配合 exit 0 → **本项通过**。
- 顺带回答上一轮留下的备择解释：上一轮（无源码变更时）`app.so` 停在 10:36:24 而 `app.dill` 刷新，我当时的推断是"内容哈希未变 → AOT 目标被跳过"。这次有真实改动，AOT 正常重跑并刷新了 `app.so` 与两个 stamp —— **推断成立，"构建系统判定错误"这条备择解释可以排除**。
- [跑] `furnace.exe` 仍是 `91136` 字节 / `2026-09-25 21:15:45`（壳没重链接，与 HANDOFF §6 的说法一致：看 `app.so`，不要看这个壳）。
- ⚠ **归因限定**：构建结束后（`14:03:22`）`app/lib/features/ai/domain/tool_registry.dart` 又被改了一次，晚于 AOT 时刻 `14:03:09`。所以**这个 app.so 不包含 14:03:22 那次改动**；本项通过是"相对构建起跑时的树"成立。若要以当前树为准，需要再构建一次。

---

## 7. t2 参数合规复核（§6.6）

### 7.1 `fast_diagnosis.dart:775` 到底是什么（**不要误判成 §6.6 违规**）
- [读] `app/lib/domain/services/cognitive/fast_diagnosis.dart:773-779`（`offload_working_memory` 分支）：
  ```dart
  case 'offload_working_memory':
    const key = 'attention.capacity.W_DAR';
    final current = engine.numberParam(key, 4);
  ```
  这里的 `4` 是 `numberParam(path, [fallback])` 的**兜底值**，不是"把默认参数写死覆盖 `module_defaults`"。
- [读] 取值优先级（`fast_engine.dart:1139-1156`）：`overrides[path]` → 已安装机制的 spec（其 `defaultValue` 来自 `module_defaults`，缺失时回落到转录值）→ `fallback` → 抛错。
- [跑] 我写了个探针（`t2_param_probe.dart`）实测五种情形：
  ```
  A capacity installed, module_defaults W_DAR=7 -> 7.0
  B capacity installed, no module_defaults     -> 4.0
  C capacity not installed, fallback=4 given   -> 4.0
  D capacity not installed, no fallback        -> throws ArgumentError
  E override 9 beats module_defaults 7         -> 9.0
  ```
  - A 证明：**只要 `attention.capacity` 被安装，`module_defaults` 的值就赢**，字面量 `4` 根本不会被读到；
  - D 证明：C 走的是"这个引擎里根本没有这个参数"的兜底路径，不是"覆盖配置"；
  - E 证明：JS 内核的覆盖优先级被保留。
- 结论：**合规**。参数来源是 `FastMechanisms.fromModuleDefaults`（`fast_engine.dart:204-222`，从 `module_defaults` 读），转录的 spec 表（如 `W_DAR` `defaultValue: 4.0`、`calibrated: true`、带 `evidence` 字段，`fast_engine.dart:306-316`）是第二来源；`fast_diagnosis.dart:775` 的字面量只服务于"没装容量机制"这种退化引擎。

---

## 8. 未能确认 / 如何查证

| 项 | 状态 | 原因 | 怎么查 |
| --- | --- | --- | --- |
| `git -C E:\Document\MindNet status --porcelain` 为空 | **已改为「记录并归因」——不判通过、也不判失败**（按队长 2026-10-01 紧急指令） | 该验收**已不可能满足**：MindNet 工作区存在一处未提交改动（` M conformance/mindnet_vectors.json`，mtime 13:53:35，diff 仅 `generated_from.commit` 一行，数值未变）。机制：任务④要求的 `npm test` 会在其自带测试 `test/conformance.test.js:123-129`（写盘调用在 L126）内自动执行 `--write`。**本轮（attempt 3）我的运行未新增改动**：mtime/sha256 全程冻结在 13:53:35 / `C62F55…` | 逐字输出与前后对比见 §4.3(a)(c)；处置（还原与否）权在用户/队长，我不回滚 |
| 新诊断 fixture 的 `diagnosis` / `baseline_reachability` / `plan` / `counterfactual` / `danger_rows` 的输入↔期望自洽性 | **未能确认**（我只覆盖了 §3.5 列出的部分） | 这些字段需要把 `control_report()` / 反事实克隆的接线也复刻一遍，成本高于本轮范围 | 扩展 `tierb_diag_redrive.cjs`：在 `runRounds` 后调用 `engine.control_report()` 并按 fixture 的 `diagnosis_defaults`/`planner_defaults` 传入参数，再逐字段比；或用 Dart 侧同一口径复算 |
| 当前 `app.so` 是否包含 `14:03:22` 的 `tool_registry.dart` 改动 | **确认为不包含**（mtime 14:03:09 < 14:03:22） | 构建完成后树又被写了 | 需要时在写作停止后重跑 §6 的构建，并按同一条判据复核 |
| Android release 构建 | **未做** | 非本轮目标（用户说先不急） | `powershell -File scripts\build_android.ps1 -Mode release` |
| 真实库只读探针路径（`--dart-define=PROBE_DB=`） | **attempt 3 已尝试，未跑通** | 托管入口当前编译不过（`originalUntouched` 未定义，见 §0.5 C），随后工作树进入红状态 | t19 落盘后重跑 `flutter test test/tool/mindnet_probe_report_test.dart "--dart-define=PROBE_DB=$env:APPDATA\FirsryFan\Furnace\furnace.db"`，跑前后照 §5 对 sha256 |
| **（attempt 3）** 真实库 4 卡报告数字（R 0.518/0.840、均值 0.759）的独立复算 | **未能确认** | 探针入口编译失败 + 工作树在变动，拿不到可信输出 | 同上；拿到探针输出后，用我的独立脚本（不同语言/驱动，`node:sqlite` 只读打开）从库中重算 R 并逐卡比对 |
| **（attempt 3）** `dart analyze lib test` 期望 0 error / 0 warning | **已闭环：14:44–14:45 窗口干净地复测为 0/0（§0.7）** | 14:15 曾因 t19 的在建文件报 error=1（`cognitive_model_page.dart:517:25`）；该文件被修好后，我在 mtime 冻结的窗口内复跑 `dart analyze lib test` → `exit=0`、`87 issues found.`、error = 0 / warning = 0 / info = 87 | — |
| **（attempt 3）** 全量测试全绿 | **已闭环：14:45–14:48 复跑 `02:48 +520 ~2: All tests passed!`（exit 0、0 失败），但窗口内有一次 l10n 生成写入，按纪律标注（§0.7）** | 14:16:34 那次 10 条失败 + 运行期间写入 ⇒ 不可归因（t19 写入期中间态）；修复后复跑全绿，且与队长独立实测（`+519 ~1`）一致 | — |

---

## 9. 证据台账（命令 → 关键输出 → 时刻）

| 命令（原文） | 关键输出 | 时刻 |
| --- | --- | --- |
| `git -C ... rev-parse HEAD` / `status --porcelain` | `ee0a6e1…`；porcelain 非空（本轮产物未提交） | 13:52:53 |
| `Get-FileHash ...\furnace.db -Algorithm SHA256` | `8C58A610…5EC6`，290816 B | 13:52:53 / 14:03:30 / 14:06:22 |
| `flutter test --concurrency=1`（第 1 次） | `02:10 +491 ~1: All tests passed!`，exit 0 | 13:52–13:55 |
| `flutter test --concurrency=1`（第 2 次） | `01:50 +503 ~1: All tests passed!`，exit 0 | 14:03:52–14:05:4x |
| `dart analyze lib test`（第 1 / 第 2 次） | `87 issues found.` / `88 issues found.`，均 exit 0，error=0 warning=0 | 13:55 / 14:06 |
| `dart --packages=... tierA_43_check.dart ...` | 43 条 / 123 字段 / 0 跳过 / PASS，exit 0 | 14:0x |
| `dart --packages=... tierA_probe.dart ...` | 115 探针 / 1007 比较 / 最坏 rel 6.2016e-16 / PASS | 14:0x |
| `dart --packages=... tierb_b01_check.dart ...` | 135 浮点 + 215 精确 / 最坏 rel 0.0 / PASS | 14:0x |
| `node tools/conformance.js --check`（MindNet） | `样例一致：43 条 tierA + 1 条 tierB`，exit 0 | 13:53 |
| `npm test`（MindNet） | `tests 141 / pass 141 / fail 0`，exit 0；**并把 conformance 文件写脏** | 13:53 |
| `node cmp_vectors.mjs` | 两边 36812 B；`raw identical: false`；值与 tolerances 全等 | 13:54 / 14:0x |
| `flutter build windows --release`（junction） | `✓ Built …furnace.exe`，exit 0，145.7s | 14:00:45–14:03:14 |
| `dart --packages=... t2_param_probe.dart` | A=7.0 / B=4.0 / C=4.0 / D=throws / E=9.0 | 14:0x |

**复算脚本（都在两个仓库之外，只读）**：
`C:\Users\Public\mindnet-verify\` 下 `cmp_vectors.mjs`、`recompute_b01.cjs`、`b01_discrimination.cjs`、`probe_gen.cjs`、`tierA_probe.dart`、`tierA_43_check.dart`、`tierA_redrive.cjs`、`tierb_diag_redrive.cjs`、`tierb_b01_check.dart`、`t2_param_probe.dart`。

**机械闸门**（本文件，实际执行的完整命令 —— 14:30 最终一次运行）
```
cd "E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity"
node "D:\dsh-data\skills\anti-hallucination\scripts\audit-claims.mjs" "docs\VERIFICATION_MINDNET.md" \
  --workspace "." \
  --allow "conformance/mindnet_vectors.json" --allow "conformance.js" \
  --allow "src/index.js" --allow "src/v2/engine.js" --allow "test/conformance.test.js" \
  --allow "Release\data\app.so" --allow "furnace.exe" --allow "audit-claims.mjs" \
  --allow "cmp_vectors.mjs" --allow "recompute_b01.cjs" --allow "b01_discrimination.cjs" \
  --allow "probe_gen.cjs" --allow "tierA_redrive.cjs" --allow "tierb_diag_redrive.cjs" \
  --allow "guard_falsify.dart" --allow "mindnet_probe.dart"
```
→ 结果：`计数：BLOCKER 0 · WARN 0 · REVIEW 15`，`结论：PASS（无 BLOCKER）`，exit 0。
（`--allow` 放行的是两类**确实存在于别处**的引用：MindNet 仓库内的相对路径、以及放在 `C:\Users\Public\mindnet-verify\` 的复算脚本名。15 条 REVIEW 全是行号锚点回显，我逐条核对与正文引用一致。）
→ 注意：闸门只查机械项（引用路径是否存在、有没有无证据的「通过」措辞等），**不等于内容为真**。

---

## 10. 给下游（t19 评审 / t12 收口）的三条要点

1. **§4.3 是唯一一条必须由人决策的项**：MindNet 工作区存在一处未提交改动（仅 `commit` 标签一行，数值未变）。按队长指令，验收⑦已改为「记录并归因」——**不得写成"通过"，也不得写成"零写入"**；处置（是否还原）权在用户/队长，我不回滚。
2. **§3.4 是证据强度限定**：B01 的 5 个快照同值，别把它当作"快层逐轮正确"的证明；补强证据在 `scenarios.multiround_progression`（6 个互异快照），我已独立复算其自洽性。
3. **§6 的构建结论只覆盖到 14:02:36 的源码状态**（AOT 时刻 14:03:09），而树在 14:03:22 又被改过。
