# 协议件独立复核（t25）

> 复核对象：`app/lib/domain/services/cognitive/mindnet_protocol.dart`、
> `app/test/domain/services/cognitive/mindnet_protocol_guard_test.dart`、
> `docs/MINDNET_CONTRACT.md` §9。
> 执行者：tierb-dev（t25）。日期：2026-10-01。
> 本报告只写**本会话实际读到 / 实际跑到**的内容；关键断言带证据标签与来源（路径:行号 / 命令输出）。
> 基线与环境：Furnace 仓库 `E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity`；
> MindNet 只读参考 `E:\Document\MindNet`，HEAD = `f4eec9bae16e6e303c19177e7fbfcf7a756f6629`（本会话 `git log -1` 读数）。

---

## 1. 已确认：协议常量与 fixture 逐条一致（7/7）[跑]

命令见 §6.1。输出原文（machine check）：

```
MATCH  protocol
    fixture: "mindnet.conformance/1"
    constant: "mindnet.conformance/1"
MATCH  generated_from.commit
    fixture: "ace605d9778e8641957c570c1e58049ca82e4a01"
    constant: "ace605d9778e8641957c570c1e58049ca82e4a01"
MATCH  generated_from.package_version
    fixture: "2.0.0-alpha.1"
    constant: "2.0.0-alpha.1"
MATCH  tolerances.rel
    fixture: 1e-12
    constant: 1e-12
MATCH  tolerances.abs
    fixture: 1e-15
    constant: 1e-15
MATCH  tolerances.rounded_decimals
    fixture: 6
    constant: 6
MATCH  tolerances.must_be_exact (order included)
    fixture:  ["admitted","focus","outcompeted","conscious","subconscious","states[].state_after","kind"]
    constant: ["admitted","focus","outcompeted","conscious","subconscious","states[].state_after","kind"]
CONSTANT CHECK: all 7 items match
```

- fixture 侧来源：[读] `app/test/fixtures/mindnet_vectors.json`（`protocol`、`generated_from`、`tolerances`；commit 在该文件只出现一次，在第 5 行）。
- 常量侧来源：[读] `app/lib/domain/services/cognitive/mindnet_protocol.dart:23,30,34,37,40,43,46-54`。
- 一处过程说明：我的第一版比对脚本用正则抓 `mustBeExact`，被 `states[].state_after` 里的 `]` 截断，报了 1 处 MISMATCH；改成按行解析后 7/7 MATCH。**结论以修正后的解析为准**（脚本见 §6.1，可复跑）。

## 2. 已确认：§9 的每条具体断言都有来源

### 2.1 数据所有权（§9.1）

| §9.1 的断言 | 本会话取证 | 结论 |
| --- | --- | --- |
| 模型只写 `encoding_strength` / `savings`，经窄写方法 `AnkiRepository.updateModelState` | [读] `app/lib/data/repositories/anki_repository.dart:388-404`：`updateModelState` 只构造 `encodingStrength` / `savings` 两个 `Value`，两参皆 `null` 时 `return`（L393-395） | 成立 |
| 窄写方法**不写 `updatedAt`** | [读] 同上 L396-403 的 `CardStatesCompanion` 只含上面两列；方法文档 L371-374 明写 "`updatedAt` is not bumped here" | 成立 |
| **禁止**复习流程调用 `DsrCardState.write()` / `applyReview()` | [读] `app/lib/domain/services/srs/dsr_card_state.dart:88-120` 的 `write()` 确实会写 `stability` / `difficulty` / `encodingStrength` / `savings` / `intervalDays` / `dueAt` / `lastReviewedAt` / `updatedAt` / `repetitions` / `ease`；[读+grep] 在 `app/lib/features` 全目录搜 `DsrCardState\.|applyReview\(` → **0 命中**（搜索范围：`app/lib/features` 下全部文件，模式见 §6.2） | 成立 |
| 复习流程里模型写入失败不阻断复习 | [读] `app/lib/features/anki/application/review_service.dart:462-477`：`modelStateAfterReview` + `updateModelState` 包在 `try` 中，`catch (_)` 注释写明"advisor 坏了不能让已记录的复习失败" | 成立 |

### 2.2 单位换算唯一换算点（§9.2）

- [读] `app/lib/domain/services/srs/dsr_card_state.dart:26`：`static const double hoursPerDay = 24;`（§9.2 引的是 L26，正确）。
- [读] 该常量在库内的使用点：`dsr_card_state.dart:68`（`s: (s ?? 0) * hoursPerDay`）、`:100`（`stability: Value(state.s / hoursPerDay)`）、`:104`（`intervalDays: Value(intervalHours / hoursPerDay)`）、以及 `app/lib/domain/services/cognitive/cognitive_model.dart:467`（`elapsedHours / DsrCardState.hoursPerDay`）——**换算一律经这个常量**，成立。
- 但 §9.2 的"全系统唯一"应补一句限定（见 §4.3）。

### 2.3 `ms` = `R0`（§9.7 的三条依据）

| §9.7 引的依据 | 本会话取证 | 结论 |
| --- | --- | --- |
| `E:\Document\MindNet\src\model.js` 的 `this.ms = f.ms === undefined ? 0.8 : f.ms` | [读] `E:\Document\MindNet\src\model.js:50` 原文即此行 | 成立 |
| `E:\Document\MindNet\mechanisms\memory.dsr.js` 的 `ensureState` 把 `ms` 读作 `R0 = min(1, ms)` | [读] `E:\Document\MindNet\mechanisms\memory.dsr.js:90`：`const R0 = typeof node.ms === 'number' && node.ms > 0 ? Math.min(1, node.ms) : 0.8;` | 成立 |
| `E:\Document\MindNet\src\io\run.js` 的状态导出写的是 `ms: bag.R0` | [读] `E:\Document\MindNet\src\io\run.js:387`：`id: node.id, ms: bag.R0, weight: node.weight, last_review_time: bag.lastReview,` | 成立 |

### 2.4 `--check` 的能力边界（§9.8）

- [读] `E:\Document\MindNet\tools\conformance.js`：`main()` 的 `--check` 分支是 L270-299，且 L284 原文 `if (copy && copy.generated_from) copy.generated_from.commit = null;` —— 比对时**归一化掉 commit**，与 §9.8 的描述一致。
- [跑] 本会话实测 `node E:\Document\MindNet\tools\conformance.js --check` → `样例数值一致（只是 commit 变了：107ab12 → f4eec9b）`（当时磁盘上是 107ab12 版），以及最近一次 → `样例一致：43 条 tierA + 1 条 tierB`（磁盘上已是 f4eec9b 版，见 §5）。
- 结论：该命令比较的是 **MindNet 实现 vs MindNet 自己的 conformance 文件**；它**不能**证明 Furnace 那份拷贝没过期，§9.8 的分工表述正确。Furnace 那份的新鲜度另有两个证据：reviewer 的逐字节比对（两份文件只有 `generated_from.commit` 两段不同）与 verifier 的独立复算脚本（读的是 Furnace fixture）。

### 2.5 §9.8 / §9.7 本轮**新增**的两条断言，我另外独立验过

队长在修订 §9 时新加了两条可判定的断言，本轮复核用只读方式复核（脚本 §6.7）：

1. §9.8（L658-661）："用 `node tools/conformance.js --check` 实测，样例数值与 MindNet HEAD `f4eec9b` 完全一致……且 Furnace 那份拷贝与 MindNet 仓库里的文件逐字节只差 `generated_from.commit` 一处（两边各 36812 B、tierA/tierB 数值全同）"。
   [跑] 我把两份文件都按 UTF-8 读入、把 `"commit": "<40 hex>"` 统一掩码后逐字符比较：
   ```
   Furnace fixture bytes: 36812 | MindNet working-file bytes: 36812
   identical after masking generated_from.commit: true
   Furnace commit:  "commit": "ace605d9778e8641957c570c1e58049ca82e4a01"
   MindNet working commit: "commit": "f4eec9bae16e6e303c19177e7fbfcf7a756f6629"
   ```
   → **成立**（字节数一致、掩码后完全相同、差异只在 commit）。
2. §9.7（L647-649）："因为 `R ≤ R0`，把 `R0` 当 `ms` 喂进快层，会让模型把节点当成'比此刻实际更可达'，于是**可达性/发展区判断偏乐观**"。
   [跑] 用冻结曲线常数复算：`c = 0.9^(-1/0.1542) - 1`，`ψ(0)=1`、`ψ(1)=0.900000000`、`ψ(10)=0.692826635`，且 `ψ(z) ≤ 1` 对 `z ≥ 0` 成立（`R = R0·ψ(t/S)`，见 `app/lib/domain/services/srs/dsr_memory.dart:342-350` 与 `:362-370`）
   → **成立**：`R ≤ R0`，故喂 `R0` 确实偏乐观。这是口径说明，不是缺陷。

## 3. 已确认：证伪实验（§9.8 声称"已做"，本任务重做一遍）

**实验步骤**（Node 改写 + 字节备份，未用 PowerShell 改写 UTF-8；见 §6.3）：

1. 备份并取实验前 SHA256：
   `pre-experiment SHA256: dbb2e33e36f56970a1c98413cb4f36596173e049167afc624480bad9ca4fa64a`
2. 把 `app/test/fixtures/mindnet_vectors.json` 里唯一一处 frozen commit 改成 `deadbeefdeadbeefdeadbeefdeadbeefdeadbeef`（`String.replace` 单次替换；该 hash 在文件里只出现 1 次）。之后 `mutated SHA256: 1d3c0d7ea56cc7463f9d0ed3774070236e1f8e7abed18e8e1a55aefa58bdf201`。
3. 跑守卫测试（**期望失败**），原文：

```
00:00 +2: frozen snapshot generated_from.commit matches the pinned commit
00:00 +2 -1: frozen snapshot generated_from.commit matches the pinned commit [E]
  Expected: 'ace605d9778e8641957c570c1e58049ca82e4a01'
    Actual: 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
     Which: is different.
            Expected: ace605d977 ...
              Actual: deadbeefde ...
                      ^
             Differ at offset 0
  snapshot drift: fixture was generated from deadbeefdeadbeefdeadbeefdeadbeefdeadbeef, MindNetProtocol pins ace605d9778e8641957c570c1e58049ca82e4a01. Re-run the tierA/tierB conformance tests before updating the constant.
  ...
00:00 +4 -1: Some tests failed.
```

4. 用备份**字节还原**并复核：
   `restored SHA256: dbb2e33e36f56970a1c98413cb4f36596173e049167afc624480bad9ca4fa64a`、
   `byte-identical to pre-experiment backup: true`、
   `git -C "...class-productivity" diff --stat -- app/test/fixtures/mindnet_vectors.json` → **无输出**（文件回到已提交状态）。
5. 再跑守卫测试（**期望通过**）：`00:00 +5: All tests passed!`

结论：§9.8 关于"改 commit → 守卫失败并打印两侧值 → 还原后一致"的描述**属实**，且失败信息里的两侧值确实会打印出来（见上面 `Expected`/`Actual` 与 `snapshot drift:` 一行）。

## 4. §9 的具体意见（验收 #4）

> 本节分两部分：**4.1–4.4 是本轮复核提出的 4 条修正意见及其现文状态**（队长已按复核意见修订 §9，逐条给出修订后的现文行号与原文）；
> **4.5 是一条针对本轮"说明文字"本身的新发现**（与实测数字不符，须以实测为准）；**4.6 是我对 `--allow` 处置的意见**（队长要求写进本节）。

### 4.1 §9.3 曾引用一个不存在的类名 —— **已修订**
- 复核时原文（`docs/MINDNET_CONTRACT.md` 当时的 L562）："…`fast_engine.dart` 的 `FastParamRegistry`"。
- 取证：[grep] 全仓库搜 `FastParamRegistry` → **当时只有这一行文档命中**；[读] `app/lib/domain/services/cognitive/fast_engine.dart:195` 是 `class FastMechanisms {`，工厂在 `:204` `factory FastMechanisms.fromModuleDefaults(`。
- 现文（L568）："`fast_engine.dart` 的 `FastMechanisms`（工厂在 `:204`）；**注意不是 `FastParamRegistry`——该符号不存在**，t25 复核指出" → **已按复核修订，且保留了纠错说明**。本条结案。

### 4.2 §9.1 的"禁止清单"曾漏 `updatedAt` —— **已修订**
- 复核时原文（当时的 L541-543）列的是 `stability` / `difficulty` / `dueAt` / `intervalDays` / `lastReviewedAt` / `repetitions` / `ease`，未含 `updatedAt`。
- 取证：[读] `app/lib/domain/services/srs/dsr_card_state.dart:113` 的 `write()` 会写 `updatedAt: Value(now)`；而窄写方法的文档 `app/lib/data/repositories/anki_repository.dart:371-374` 明确说"**不 bump `updatedAt`**，否则这一列会有第二个写者"。
- 现文（L541-545）：清单已含 **`updatedAt`**，并新增一整句"其中 **`updatedAt` 尤其要盯住**：它正是 `updateModelState` 的文档明确声明"不得二次写入"的那一列（`anki_repository.dart` L371–374 附近）" → **已修订**。本条结案。

### 4.3 §9.2 的"全系统唯一换算点"曾未点名另外两个 24 —— **已修订**
- 复核时原文（当时的 L548）："`DsrCardState.hoursPerDay = 24` 是**全系统唯一**的天↔小时换算点"。
- 取证：[grep] `app/lib` 下 24 值常量还有两处：[读] `app/lib/domain/services/srs/dsr_memory.dart:45`（`this.legacyK = 24`，镜像 `E:\Document\MindNet\mechanisms\memory.dsr.js` 的 `legacy_k`，单位小时，用于 `S = k·R0`，见 `:76`、`:167`）与 [读] `app/lib/domain/services/cognitive/fast_engine.dart:91`/`:110`（`forgettingK = 24.0`）。
- 现文（L553-556）：新增"**另外两个同值 24 不是换算点，别拿它们当换算用**（t25 复核建议点名）：`DsrParams.legacyK = 24`（`dsr_memory.dart` L45/L76…）与 `FastConfig.forgettingK = 24.0`（`fast_engine.dart` L91/L110…）" → **已修订**。本条结案。

### 4.4 §9.7 曾缺"导出侧 `ms` 口径不一致"的警告 —— **已修订**
- 复核时原文（当时的 L621-622）只写了"`ms` = 节点的 `R0`（编码上限）…只在初始化时被读一次"。
- 取证：[读] `E:\Document\MindNet\src\io\run.js:387` 导出 `ms: bag.R0`；同文件 `:602-603` 另一处导出是 `ms: round6(node.ms)` **外加** `R0: …` —— 那里 `ms` 是**当前值**；而 [读] `E:\Document\MindNet\mechanisms\memory.dsr.js:114`（`synced()` 内）`node.ms = R;` 会把 `node.ms` 改写成**当前可提取度**。
- 现文（L638-641）：新增"**导出侧还有一处口径不一致，必须写死**（t25 复核）：… 所以**导出的 `ms` 不等于输入语义的 `R0`，绝不能回喂** —— 回喂会让"编码上限"被当前可提取度覆盖，且不会报错" → **已修订**。本条结案。

### 4.5 新发现：本轮说明里对**闸门数字**的描述与实测不符（须以实测为准）
- 说明原文（队长本轮写信给复核者的口径）："不带 allowlist 时对整份文档报 **3 BLOCKER**，全部落在既有 §1–§8（L134/L397/L398），**我新写的 §9 零新增**"。
- 我实测（同一文件、同一 workspace、两次）：**裸命令对 `docs/MINDNET_CONTRACT.md` 报 `BLOCKER 60`（本轮早些时候）→ `BLOCKER 61`（队长修订 §9 之后）· WARN 21 · REVIEW 6**，与"3 BLOCKER"不符；
  而且 **§9 自己就有 8 条裸模式 BLOCKER**（不是零新增），逐条如下：
  - L634 / L635 / L636 / L638 / L639 —— 审计器打印的缺失路径依次是 `E:\Document\MindNet\src\model.js`、`E:\Document\MindNet\mechanisms\memory.dsr.js`、`E:\Document\MindNet\src\io\run.js`、`E:\Document\MindNet\src\io\run.js`、`E:\Document\MindNet\mechanisms\memory.dsr.js`（工具输出里以仓库相对形式打印），即 **§9.7 自己引用的三条 MindNet 依据**（L634-636）与导出侧不一致那条（L638-639）；
  - L658 / L665 / L666 —— `E:\Document\MindNet\tools\conformance.js`，出现在 §9.8/§9.9 的叙述里。
- 结论与建议：**"§9 零新增"不成立**，但 `--allow` 的处置本身仍然正确（见 4.6）。建议把说明改成"裸模式报 61 条，其中 §9 占 8 条（全是 MindNet 相对路径引用）；用 `--allow` 放行后 0 条"——数字必须来自实测，否则下一个人会以为 §9 天然免检。
- 复现命令与完整分布：见 §6.7。

### 4.6 我对 `--allow` 处置的意见：**同意**（队长要求写进本节）
- 那些被放行的路径（`src/`、`mechanisms/`、`tools/`、`conformance/`…）**属于 MindNet 仓库**，不在 Furnace 工作区内；审计器只认识工作区内的路径，故报 `MISSING_PATH`。
- 技能自身的规则原文就是："若它属于别的仓库、外部项目或未安装的源码布局，用 `--allow <子串>` 放行后重跑。**不要为了通过闸门而删掉正确的引用**——闸门是辅助，不是目的。"
- 本仓库已有先例：`docs/MINDNET_CONTRACT.md` 的 t25 verify 第 3 条（以及我这份报告的 §6.5）都是这么处理的。所以这不是"逃闸门"，而是把**外部路径的误报**与**真正的内容缺失**区分开；真正的缺失仍会以 BLOCKER 形式出现（例如 §4.5 就是靠裸模式与逐行分布才看出来的）。

### 4.7 建议 §9.8 增补一行"MindNet 侧禁止跑生成路径"的操作规程（队长要求提出；**只提意见，未改 §9**）
- 现文 §9.8（`docs/MINDNET_CONTRACT.md` L651-668）写的是"两个守卫的分工"（`--check` 守 MindNet 实现不过期 / Dart 守卫守 Furnace 快照不漂移），**没有写操作规程** —— 谁都不该在 MindNet 里跑会写盘的生成路径。
- 取证：[读] `E:\Document\MindNet\package.json` 的 `"conformance": "node tools/conformance.js"` **不带 `--check`**，而该脚本的默认分支就是写文件（只有 `--check` 才只校验）；`--write` 同样写。两者都会把 `generated_from.commit` 重戳成当前 HEAD —— 本次脏文件的成因。更隐蔽的一条：[读] `E:\Document\MindNet\test\conformance.test.js:123-129` 的测试在 L126 跑 `--write`，所以**连 `npm test` 都会写**。
- 建议增补（作为 §9.8 收尾的**一行**；具体措辞由队长定）：
  > **操作规程（MindNet 侧）**：核验新鲜度只允许 `node tools/conformance.js --check` 与 `git` 只读命令；
  > **禁止** `npm run conformance`、`node tools/conformance.js`（不带 `--check`）、`--write`；
  > 注意 `npm test` 内含一次 `--write` 断言（`E:\Document\MindNet\test\conformance.test.js:123-129`），会重戳该 fixture 的 commit 与 mtime，
  > 因此**任何"零写入"核验都必须排在所有 `npm test` 之后**。
- 与 §5.3 的关系：这条建议正是从本次脏文件事故（一个先前遗留的 ` M conformance/mindnet_vectors.json`，非本任务写入）里得出的；写进 §9.8 可让下一个人不必再踩一遍。
- **最容易踩的一条（reviewer 补充，我已独立复核原文）**：**看到 `--check` 提示 `--write` 也不得照做**。取证：[读] `E:\Document\MindNet\tools\conformance.js:294-298` ——
  当 `--check` 判定"数值一致、只有 commit 变了"时会打印：

  ```
  样例数值一致（只是 commit 变了：107ab12 → f4eec9b）
  提示：改动实现时顺手跑一次 node tools/conformance.js --write，让文件里的 commit 跟上
  ```

  （L297 原文即上面第二行；另外 L291 与 L301 的两条错误路径也建议"重跑 `--write`"。）
  也就是说：**只读的核验命令会主动劝你去写**——照做就破坏了"MindNet 零写入"。这比"禁止 `--write`"更隐蔽，建议一并写进 §9.8 的操作规程，措辞例如
  "`--check` 的提示里可能出现 `--write`（`tools/conformance.js:297`），那是给 **MindNet 自己**的维护建议，**Furnace 侧不得照做**"。
- **采纳情况（本轮复核时确认）**：队长已把本节建议落成 `docs/MINDNET_CONTRACT.md:670-682` 的 **§9.8b「MindNet 侧操作规程（铁律，实测得出）」**，五条与本节一致（只允许 `--check`；`npm test` 也会写盘；白名单式禁令；零写入核验排最后；还原需所有者授权）。
  我复核了 §9.8b 引用的两处取证并确认成立：落盘点 `E:\Document\MindNet\tools\conformance.js:304-305`（`fs.mkdirSync(...)` + `fs.writeFileSync(OUT, text, 'utf8')`，L306 打印"已写入"），以及"该文件里唯一的只读分支是 `--check`"。

## 5. 验收 #5 的处置（队长修订版口径）

**队长本轮把 #5 的口径改为**：贴出实际输出 + `git diff` 全文 + mtime，写明这是**先前遗留**的脏文件、**我未写入也未回滚**，并给出运行前后 status 的对比证明我没有新增。下面按这个口径给全证据。

### 5.1 实际输出（原样）

```
$ git -C "E:\Document\MindNet" status --porcelain
 M conformance/mindnet_vectors.json

$ git -C "E:\Document\MindNet" log -1 --format=%H
f4eec9bae16e6e303c19177e7fbfcf7a756f6629

$ git -C "E:\Document\MindNet" diff -- conformance/mindnet_vectors.json
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

文件属性：`E:\Document\MindNet\conformance\mindnet_vectors.json` —— mtime `2026/10/01 13:53:35.485`、大小 `36812 B`、SHA256 `C62F55F412727507E09517A1DC0C7A0B078C4DC087096CE9DB1C1C658F3C6A71`
（与 Furnace 侧同名 fixture 的 `DBB2E33E…A64A` 不同，差异只在 commit 字符串，见 §2.5 的掩码比对）。

### 5.2 运行前后的对比（证明我没有新增写入）

我在**只跑允许命令**的前后各取一次快照（快照 A → 跑 `node tools/conformance.js --check` → 快照 B）：

| 观测量 | 快照 A（运行前） | 快照 B（运行后） |
| --- | --- | --- |
| `git status --porcelain` | ` M conformance/mindnet_vectors.json` | ` M conformance/mindnet_vectors.json`（同一条） |
| mtime | `2026/10/01 13:53:35.485` | `2026/10/01 13:53:35.485`（毫秒级相同） |
| 大小 | `36812 B` | `36812 B` |
| SHA256 | `C62F55F4…F3C6A71` | `C62F55F4…F3C6A71`（相同） |
| `--check` 输出 | —— | `样例一致：43 条 tierA + 1 条 tierB`，exit 0 |

四项全部相同 ⇒ **我在 MindNet 里跑的 `--check` 没有产生任何写入**（与 §2.4/§6.4 的结论一致）。

### 5.3 结论与责任边界

- 这是**先前遗留**的脏文件：mtime `13:53:35` 早于我本轮的任何一次 MindNet 命令（本会话当时的本机时间已是 14:0x–14:2x）。
- **我没有写入它，也没有回滚它**（回滚同样是写；处置权在用户/队长）。本任务对 MindNet 只做过三类动作：`--check`、只读 `require`/`read`/`grep`、以及 §5.2 的 git 只读快照。
  本轮**没有**在 MindNet 里跑 `npm run conformance`、`node tools/conformance.js`（不带 `--check`）或 `--write`；也没有跑 `npm test`（原因见下）。
- 成因（已定位，非推测）：[读] `E:\Document\MindNet\test\conformance.test.js:123-129` 的测试在 L126 执行
  `execFileSync(process.execPath, [script, '--write'], { stdio: 'pipe' })`（`script` = `E:\Document\MindNet\tools\conformance.js`），
  因此 **`npm test` 自己就会重写该 fixture**（把戳记重戳成当前 HEAD）。旁证：verifier 的 t18 结论同样写着该脏状态"是被任务自身要求的 `npm test` 弄脏的"。
- ⚠️ **对"允许跑 `npm test`"的一处实测补充**：队长本轮允许的命令清单里含 `npm test`，但由上面这条可知 **`npm test` 会写盘**（至少更新 mtime；内容在当前场景下恰好相同）。
  所以我**没有**在本轮跑它——一旦跑了，§5.2 那张"毫秒级相同"的表就不再成立，"我没新增写入"的证明会随之失效。
  建议操作规程写成：**MindNet 侧禁止跑会写盘的生成路径**（`--write` / 不带 `--check` / `npm run conformance`），
  且**任何"零写入"核验必须排在所有 `npm test` 之后**；只想核验新鲜度就用 `--check`（本会话实测只读）。这条建议已按队长要求作为 §4.7 提出（**只提意见，未改 §9**）。
- 历史记录：t25 的 attempt 3 曾按**旧口径**（要求 porcelain 为空）以 `failed` 收口；本文件是其交付物。按队长修订后的 #5 口径，本节证据即为通过态。
- **未能确认（原因）**：该脏文件**是否/何时、由谁还原** —— 还原同样是写 MindNet，决定权在**仓库所有者（用户）**，本任务**未执行**；
  截至本报告定稿，MindNet 仍为 ` M conformance/mindnet_vectors.json`（mtime `2026/10/01 13:53:35.485`，HEAD `f4eec9b…`）。
  在得到授权前，本报告不对"还原"作任何承诺，也不建议任何人在 Furnace 任务里代跑还原命令。

## 6. 如何查证 / 复现（命令原文）

### 6.1 常量比对（验收 #1）
```powershell
cd "E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity"
node %TEMP%\t25-constants2.cjs   # 读 app/test/fixtures/mindnet_vectors.json 与 mindnet_protocol.dart 逐项比对，打印 7/7 MATCH
```
（脚本逻辑：`JSON.parse` fixture，正则取 `.dart` 常量；`mustBeExact` 按行解析，避免 `states[]` 里的 `]` 截断。）

### 6.2 禁止清单的 grep（验收 #2）
```powershell
cd "E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity\app"
# 复习流程有没有碰 DsrCardState / applyReview：
rg -n "DsrCardState\.|applyReview\(" lib/features      # 本会话等价 grep → 0 命中
# 类名核对：
rg -n "FastParamRegistry|class FastMechanisms|factory FastMechanisms.fromModuleDefaults" lib
# 24 值常量：
rg -n "hoursPerDay|\* 24|/ 24|24\.0|this\.legacyK" lib
```

### 6.3 证伪实验（验收 #3；**禁 PowerShell 改写 UTF-8**）
```powershell
cd "E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity"
# 1) 备份 + 取 SHA256 + 单次替换 commit（Node）
node -e "const fs=require('fs'),c=require('crypto');const P='app/test/fixtures/mindnet_vectors.json';const o=fs.readFileSync(P);fs.writeFileSync(process.env.TEMP+'/mindnet_vectors.backup.json',o);console.log('pre',c.createHash('sha256').update(o).digest('hex'));const t=o.toString('utf8').replace('ace605d9778e8641957c570c1e58049ca82e4a01','deadbeefdeadbeefdeadbeefdeadbeefdeadbeef');fs.writeFileSync(P,Buffer.from(t,'utf8'));"
# 2) 期望失败
cd app; flutter test test/domain/services/cognitive/mindnet_protocol_guard_test.dart --concurrency=1
# 3) 字节还原 + 复核
cd ..; node -e "const fs=require('fs');fs.copyFileSync(process.env.TEMP+'/mindnet_vectors.backup.json','app/test/fixtures/mindnet_vectors.json');"
git diff --stat -- app/test/fixtures/mindnet_vectors.json    # 期望：无输出
# 4) 期望通过
cd app; flutter test test/domain/services/cognitive/mindnet_protocol_guard_test.dart --concurrency=1
```

### 6.4 MindNet 零写入（验收 #5）
```powershell
git -C "E:\Document\MindNet" status --porcelain          # 期望：无输出
node E:\Document\MindNet\tools\conformance.js --check     # 只读；期望 exit 0
```
**顺序很重要**：`npm test`（= `node --test test/*.test.js`）**会写**这份 fixture（`E:\Document\MindNet\test\conformance.test.js:123-129` 的 `--write` 断言，见 §5），
所以任何"零写入"核验都必须**最后做**；只读核验新鲜度请只用 `--check`。

### 6.5 机械闸门（验收 #6）

原样命令（不含 `--allow`）：

```powershell
node "D:\dsh-data\skills\anti-hallucination\scripts\audit-claims.mjs" `
  "E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity\docs\VERIFICATION_PROTOCOL.md" `
  --workspace "E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity"
# 结果：BLOCKER 12 · WARN 0 · REVIEW 29 —— 12 条全是同一类误报：
#   （数字随报告正文引用的 git pathspec / package.json 脚本值条数变化；本文件最终修订态为 12 条）
#   本报告为了可复现必须引用 MindNet 的**仓库相对**路径（git 的 pathspec 与被引的
#   package.json 脚本值就是 "conformance/mindnet_vectors.json" / "node tools/conformance.js"），
#   而审计器只认识工作区内的路径。
```

按技能自身的处置规则（"若它属于别的仓库/外部项目……用 `--allow` 放行后重跑；**不要为了通过闸门而删掉正确的引用**"）加放行后重跑：

```powershell
node "D:\dsh-data\skills\anti-hallucination\scripts\audit-claims.mjs" `
  "E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity\docs\VERIFICATION_PROTOCOL.md" `
  --workspace "E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity" `
  --allow "conformance/" --allow "tools/"
# 结果：BLOCKER 0 · WARN 0（见 §1/§2/§3 各项的行号锚点回显校验）
```

与本仓库既有约定一致：`docs/MINDNET_CONTRACT.md` 的 t25 verify 第 3 条也是用一串 `--allow`（`src/`、`mechanisms/`、`tools/`、`conformance/`…）给同一批 MindNet 路径放行。

同一闸门对 `docs/MINDNET_CONTRACT.md` 本身（t25 verify 第 3 条，带契约给定的整串 `--allow`）：

```
计数：BLOCKER 0 · WARN 20 · REVIEW 7
结论：PASS（无 BLOCKER）
```

20 条 WARN 是"裸文件名位置歧义 / 绝对化措辞"类提示（比本轮早些时候多 1 条，因为队长按要求新加了 §9.8b），不影响 §9 的断言成立性（§2/§4 已逐条取证）。

### 6.6 交叉复算：verifier 的独立脚本（只读、工作区外）

除了本报告 §1-§3 的自证，B01 的期望值还被一条**不是我写的**脚本独立复算过，供后续复核直接复用：

```powershell
# 脚本路径（工作区之外，只读；由 verifier 提供）
C:\Users\Public\mindnet-verify\recompute_b01.cjs
# 调用方式
node "C:\Users\Public\mindnet-verify\recompute_b01.cjs"
# 本会话观察到的输出（exit 0）
#   module_defaults drift entries: 0
#   checks: floats=130 exact=200
#   worst float rel=0 at
#   B01 RECOMPUTE: all fields match within fixture tolerances (rel<=1e-12, abs<=1e-15)
```

它与本侧 Dart 对拍是两条独立路径：该脚本直接 `require` `E:\Document\MindNet\src\index.js` + `E:\Document\MindNet\src\v2\engine.js`，**不经过** `E:\Document\MindNet\tools\conformance.js` 的 `tierB()`，
读的是 Furnace 那份 fixture 的 `input`，用 fixture 自己的容差（rel 1e-12 / abs 1e-15）判等。它管"期望值与真实实现一致"，
本侧 Dart 测试管"移植与期望值一致"——两边都过，才说明这条对拍不是自证循环。

### 6.7 §4.5 的复现命令（裸模式 BLOCKER 分布）与 §2.5 的两条断言

```powershell
# 裸模式（不带 --allow）：整份文档 61 条 BLOCKER，其中 §9 占 8 条（L634-639 / L658 / L665 / L666）
node "D:\dsh-data\skills\anti-hallucination\scripts\audit-claims.mjs" `
  "E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity\docs\MINDNET_CONTRACT.md" `
  --workspace "E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity"
# 逐行分布（脚本见下）：把 BLOCKER 行号取出、按 >=518（§9 起始行）过滤即可看到那 8 条
```

```powershell
# §2.5 的两条断言：①两份 fixture 掩码 commit 后是否逐字节相同 ②ψ(z) <= 1 ⇒ R <= R0
node "C:\Users\firsr\AppData\Local\Temp\t25-check-claims.cjs"
# 实测输出：Furnace fixture bytes: 36812 | MindNet working-file bytes: 36812
#           identical after masking generated_from.commit: true
#           psi(0)=1 psi(1)=0.900000000 psi(10)=0.692826635 => psi <= 1 for z>=0: true
```

---

## 附：三态小结（收口用）

**已确认（附证据）**：§1 常量 7/7；§2 §9.1/§9.2/§9.7/§9.8 四组断言的来源逐条成立（含 §2.5 对队长新加两条断言的独立复核）；§3 证伪实验可复现（失败信息含两侧值，还原后 SHA256 = `DBB2E33E…`、守卫转绿）。
**需修正（非阻塞）**：§4.1–§4.4 的 4 条（不存在的类名 `FastParamRegistry`；禁止清单漏 `updatedAt`；"唯一换算点"未点名另外两个 24；`ms` 导出侧口径不一致未警告）——**现文均已按复核修订**；
§4.5 一条**尚存**：本轮说明里"裸闸门 3 BLOCKER / §9 零新增"与实测（61 条、§9 占 8 条）不符；§4.7 建议 §9.8 增补"MindNet 侧禁止跑生成路径"的操作规程（**只提意见，未改 §9**）。
**未能确认 / 阻塞**：§5 —— MindNet 工作区存在 1 处**先前遗留**的非本任务改动（`E:\Document\MindNet\conformance\mindnet_vectors.json` 的 `generated_from.commit`；mtime `13:53:35.485` 未被再次改写）。
按队长修订后的 #5 口径（贴输出 + diff + mtime + 证明未写入未回滚 + 运行前后对比），§5.1–§5.2 的完整证据即满足该条；我既未写入也未回滚，处置权在用户/队长。注意：§5.3 指出 `npm test` 本身会写盘（`E:\Document\MindNet\test\conformance.test.js:123-129`），所以本轮我**没有**跑它。
**本轮新增的可执行结论**（§4.5/§6.7）：裸闸门对 `docs/MINDNET_CONTRACT.md` 报 61 条 BLOCKER、其中 §9 占 8 条 —— 说明"§9 零新增"不成立，闸门数字须以实测为准；放行那批 MindNet 相对路径仍应用 `--allow`（§4.6）。
**要交给文档收口的操作规程**（§4.7 建议；**队长已采纳并写入 `docs/MINDNET_CONTRACT.md:670-682` 的 §9.8b**）：
1. MindNet 侧只允许 `node tools/conformance.js --check` 与 git 只读命令核验新鲜度；禁止 `npm run conformance` / 不带 `--check` 的生成器 / `--write`；
2. `npm test` 内含一次 `--write`（`E:\Document\MindNet\test\conformance.test.js:123-129`）⇒ 零写入核验必须排在所有 `npm test` 之后；
3. **看到 `--check` 提示 `--write`（`E:\Document\MindNet\tools\conformance.js:297`）也不得照做** —— 那是给 MindNet 自己的维护建议。
