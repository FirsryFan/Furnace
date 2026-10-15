# 开发进度

> 记录每一轮自动/手动迭代的进展，作为持续开发的“长期记忆”。

---

## 2026-10-16 轮次四十二：组卷页「复制卷面」——卷面变成可打印纯文本（Q20，teammate `question-intake`）+ 修一处反序真 bug

**做了什么**
- `app/lib/features/questions/presentation/question_paper_page.dart`：卷面头部加「复制卷面」
  `TextButton.icon`（空卷面**禁用**）；新增顶层纯函数 `renderPaperText({l10n, plan, knowledgePointNames})`
  —— 首行「想要 N 道，凑到 M 道」，每题 `序号. [学科] [来源] [档位]` + 知识点名 + `理由：<reasonZh>`
  （`improvementNote` / `backgroundZh` 非空才各加一行），末尾按 `uncoveredKnowledgePointIds` /
  `deferredKnowledgePointIds` 列缺口（查不到名字就原样显示 id）。
- `app/lib/l10n/app_zh.arb` + `app_en.arb` 各 +7 键（`questionPaperCopy` / `CopyDone` / `CopyReasonLabel` /
  `CopyImprovementLabel` / `CopyBackgroundLabel` / `CopyUncoveredHeading` / `CopyDeferredHeading`），
  带占位符的配了 `@key.placeholders`；`flutter gen-l10n` 生成物随之更新。
- `app/test/features/questions/presentation/question_paper_page_test.dart` +5 条 testWidgets
  （剪贴板内容逐段、短卷如实写"凑到几道"、缺口两段、空卷面禁用且不写剪贴板、文本里不放题面与答案），
  文件共 20 条；用 `SystemChannels.platform` 的 mock handler 截住 `Clipboard.setData`。

**为什么不这么做**
- **空卷面禁用按钮而不是点完弹提示**：空文本粘进 Word 会把用户剪贴板里原来的东西清掉，而卡片里
  已经写明是哪种空；禁用比再弹一条提示更安静。
- **不放题面与答案**：卷面是"打印出来拿纸做"的底稿，把答案糊进去等于毁掉它；题面归收题页/详情页。
- **不重排、不复算分数**：顺序与 `score` 都是 `PaperPlan` 算好的，`renderPaperText` 只做排版。
- **只做剪贴板，不加 PDF/打印依赖**：`app/pubspec.yaml` 里没有 share/pdf 包，为这一片引依赖不值。

**顺手修掉的一处真 bug（不是本片目标，但撞上了）**
- `questionPaperHeadline(int want, int got)`（`app_zh.arb:1018`「想要 {want} 道，凑到 {got} 道」）
  从 Q10a 起被调用成 `(plan.items.length, plan.requestedCount)`——**参数反了**：用户要 10 道、
  只凑到 2 道时页面写「想要 2 道，凑到 10 道」。
- 之所以一直全绿：旧测试把反序值当期望（`question_paper_page_test.dart` 9 处
  `expect(find.text(zh.questionPaperHeadline(2, 10)), findsOneWidget)`），
  所以断言和实现一起错了。现已改成 `(plan.requestedCount, plan.items.length)`，
  并新增一条回归断言：文本里**不能**出现 `questionPaperHeadline(2, 10)` 这种反序读法。

**验收**
- `dart format --output=none --set-exit-if-changed`（页面 + 测试）→ `Formatted 2 files (0 changed)`。
- `flutter gen-l10n` 后 `git diff app/lib/l10n` 与生成前**逐字相同** → 生成物与 ARB 一致。
- `dart analyze lib test` → `94 issues found.`（0 error / 0 warning）。
- `flutter test test/features/questions --concurrency=1` → **`+104 All tests passed!`**
  （Q17 后基线 +90；+9 是轮次四十一 Q19 在同一测试树里新增的仓储/服务层用例）。

**已知缺口**
- 只有剪贴板，没有打印/PDF；复制出去的文本按契约**不含题干**，所以不能独立标识"这是哪道题"。
- `Clipboard.setData` 平台抛错这条路径没有测试（实现里写成功才提示）。
- 题头的标签分隔符是全角冒号硬编码（en 语言下也是全角）。
- 目标题数下拉的 items 只有 5/10/15/20，而 `setTargetCount` 钳 1..200——本轮 UI 不可达，
  但"恢复上次 spec/导入配置"这类路径一旦写进 1..4 会触发 Flutter 断言（详见下一轮）。

---

## 2026-10-16 轮次四十一：拍照整理的待确认清单落地（schema v13）——重启不丢，确认状态按内容保留（Q19，Lead）

**做了什么**
- `app/lib/data/database/tables.dart` 加两张表：`handwriting_intake_runs`（`source_ref` PK /
  `analyzed_at` / `raw_reply?` / `created_at`，**零提案也留一行**）、`handwriting_proposals`
  （`id = <source_ref>#<proposal_id>` PK / `source_ref` / `proposal_id` / `sort_index` /
  `kind` / `payload_json` / `applied_at?` / `created_at` / `updated_at`）。
- `app/lib/data/database/database.dart`：`schemaVersion => 13`、`onUpgrade` 加 `_upgradeV12ToV13()`，
  并在 `_ensureColumns()` 的表自愈块里补这两张表（文件已被盖成 v13 但表缺失时，读取会报
  `no such table`，看起来像"从来没整理过"）。
- 新仓储 `app/lib/data/repositories/handwriting_proposal_repository.dart`：`saveRun`（事务内删旧写新，
  **`payload_json` 逐字相同的那几条保留 `applied_at`**）、`runs()` / `runOf()`、`markApplied`
  （只更新 `applied_at IS NULL` 的行）、`deleteRun` / `deleteAll`（只删记录，**照片不动**）。
- 领域层 `app/lib/domain/services/intake/handwriting_proposals.dart` 加 `fromJson`（提案/集合/卡片草稿），
  解析模型回复与从库还原走**同一个严格口径**；JSON 契约只留 `toJson`/`fromJson` 一份。
- 应用层 `app/lib/features/questions/application/handwriting_proposal_service.dart`：
  `handwritingProposalRepositoryProvider`；`refresh()` 读磁盘清单 + 从库恢复（照片不在磁盘上的记录顺手清掉）；
  `analyze()` 成功写库；`_finishApply` 对每条成功 outcome 落 `applied_at`；`forget()` 变成异步删记录。

**为什么不这么做**
- **按 `payload_json` 逐字相同保留 `applied_at`**：重新整理得到的新提案里，内容逐字没变的那条就是
  用户确认过的同一条，清掉会让用户再确认一次、写出第二份标签/知识点；内容变了的是**新版本**，
  用户没确认过它，确认状态必须清。
- **两张表只存提案与确认状态，不碰学习数据**："确认前不写库"约束的是学习数据（标签/知识点/闪存卡），
  不是"待确认清单"本身——否则重启一次整理就白做。
- **`saveRun` 用 `sort_index` 而不是 id 排序**：按 id 排会按字典序把三类产物打散，用户看到的顺序
  会和确认时不一致。
- **不做"提案内容变了也保住已确认"**：那等于把用户没确认过的东西标成已写库。

**验收**
- `dart format --set-exit-if-changed`（改动的 6 个文件）→ 0 changed。
- `dart analyze lib test` → `94 issues found.`，error / warning **0**（与 Q18 基线一致）。
- `flutter test test/features/questions test/domain/services/intake test/data/database --concurrency=1`
  → **`+171 All tests passed!`**（含新增 `v13_migration_test.dart` 2 例、
  `handwriting_proposal_repository_test.dart` 5 例、领域 `fromJson` 4 例、服务层 4 例）。
- **本机环境教训**：`build_runner` 默认 AOT 编译在本仓库失败（`Unable to write file:
  ...一THREADRIPPER一....dart_tool\build\entrypoint\build.dart.aot`）——隔离验证后确认
  **AOT 快照写不进含中文的路径**（同一命令写 `C:\tmp\...` 成功、写仓库内路径失败），
  不是磁盘空间/缓存损坏；改用 `dart run build_runner build --delete-conflicting-outputs --force-jit` 成功
  （`Built with build_runner/jit in 99s; wrote 651 outputs.`）。

---

## 2026-10-16 轮次四十：组卷页补三个 spec 控件——目标难度 / 每知识点上限 / 重置（Q17，teammate `question-intake`）

**做了什么**
- `app/lib/features/questions/presentation/question_paper_page.dart` 控制区补三控件：
  目标难度 = 19 档下拉（1.0–10.0 步长 0.5）+「不限」→ `setTargetDifficulty`（不限 → null）；
  每知识点上限 =「自动」+ 1–5 → `setPerKnowledgePointCap`；重置 = `OutlinedButton.icon(Icons.restart_alt)`
  → `reset()`（目标题数/学科/来源下限/难度/上限一起回默认）。冻结接口是 `paperSpecProvider`，领域层未动。
- `app/lib/l10n/app_zh.arb` + `app_en.arb` 各 +8 键（`questionPaperDifficultyLabel`/`Any`/`Option(String)`/`Hint`、
  `questionPaperCapLabel`/`Auto`/`Option(int)`、`questionPaperReset`），zh/en 对称，带占位符的都有
  `@key.placeholders`；`flutter gen-l10n` exit 0。
- `app/test/features/questions/presentation/question_paper_page_test.dart` +5 条 testWidgets
  （难度设置与回显、难度参与挑题、上限=1 时同知识点只进一道、重置回默认且回显同步、空题库不崩），
  并修一处被新控件撞坏的旧断言（`DropdownButtonFormField<int>` 现在命中 2 个）。

**为什么不这么做**
- **界面 hint 明写"难度是偏好不是硬筛"**：`PaperComposer._difficultyFit` 在题没填难度时给 0.5（不是排除），
  所以设了目标难度之后没填难度的题只是排后面、不会消失。不写清楚的话，用户会以为自己在筛题。
- **用下拉而不是滑块**：19 档下拉更好点、也好断言；滑块在窄屏上难精确落档。
- **「上限」只暴露到 5**：notifier 本身不限，但组卷的实际用途是"别让一个知识点刷屏"，
  1–5 已经覆盖；需要更大值时再放开（不预先暴露没人调的旋钮）。
- **测试不去读 `find.text` 判断选中项**：`DropdownButton` 把所有 items 挂进 `IndexedStack`，
  「不限难度」永远在树上 → 改读 `FormField.initialValue`。

**验收**
- `dart format --output=none --set-exit-if-changed` 该 2 个 dart 文件 → `Formatted 2 files (0 changed)`；
- `dart analyze lib test` → `94 issues found.`（0 error / 0 warning）；
- `flutter test test/features/questions --concurrency=1` → `+90 All tests passed!`（基线 +85 + 5）。
- Lead 独立复跑以上三条（不是只看 teammate 的原始输出），并确认页面只打 `paperSpecProvider`、
  没有新增读库或复算分数。

**下一步**
- 拍照整理的提案仍只存在内存里（重启丢一次整理）；找相似题区块与拍照队列页还差折叠/缩略图等交互；
  threadflow 与组卷的 `reasonZh` l10n。

---



**做了什么**
- `app/lib/domain/services/cognitive/learning_metrics.dart`（只加不改）：
  - 新 `class KnowledgePointRetention{knowledgePointId?, samples, recalled, retention, standardError, toJson()}`；
  - 新 `LearningMetrics.retentionByKnowledgePoint({samples, minSamples = kMinKnowledgePointRetentionSamples})`：
    按 `RetentionSample.knowledgePointId` 分组，**低于阈值的分组如实省略**（不补 0、不拿全局留存率冒充）；
    排序 = 留存率升序 → 样本数降序 → 知识点 id 升序；`minSamples < 1` 抛 `ArgumentError`；
  - 新常量 `kMinKnowledgePointRetentionSamples = 20`。
- `app/lib/features/cognitive/application/calibration_reader.dart`：`CalibrationReading` 增加
  `knowledgePointRetention`，与留存/Brier/ECE/偏置**共用同一次** `retentionSamples`（不多查一次库）。
- `app/lib/features/ai/tools/metrics_tools.dart`：`review_metrics` 增参 `knowledge_point_retention`
  （默认 false）；开启后 `modelResult` 带逐点留存（含 `knowledge_point_title`，用
  `db.select(db.knowledgePoints)` 只读补齐），摘要最多点名 3 个样本够的最差点，其余只说数量。
- 文档：`docs/ASSESSMENT_DESIGN.md` M6 的"未做"清单划掉「按知识点聚合的留存率」并写清口径；
  `docs/CALIBRATION.md` §6/§7/§8 相应更新。

**为什么不这么做**
- **门槛 20 条、更薄的组如实省略**：`p = 0.5` 时 20 条的标准误约 0.11；再薄就分不清"在漏"和"运气"。
  "复习了两次全错"不是"这个知识点在漏"，所以宁可不说，也不点名。
- **不补 0、不借全局留存率冒充**：省略就是省略。补 0 会把"没测过"读成"全忘了"，借全局值会抹掉个体差异。
- **归不到知识点的复习单独一组、永远排最后**：`card_states` 已删的日志（`LEFT JOIN` 刻意保留）和
  **v1 模板卡**（`getOrCreateCardState` 刻意不写 `knowledge_point_id`，见 `review_service.dart:415-425`）
  都会落进来；把它们排在"最差"第一位会被读成"这个知识点在漏"，所以摘要里**不算**它们，
  只单独说明有多少条归不到知识点。
- **仍不做逐点标定**：逐点留存只需要复习结果；逐点偏置/斜率切完样本普遍不足 30 条，切了只有"样本不足"。
- **只给 `standardError`，不宣称谁显著更差**：区间比较是另一件事，没做就不说。

**验收**
- 新增 `app/test/domain/services/cognitive/learning_metrics_test.dart` 逐点留存 7 例（分组与阈值省略、最差在前 +
  样本数/id 兜底、阈值可配且含边界、归不到知识点的组永远最后、标准误、空输入与非法阈值、`toJson` 键与舍入）。
- `app/test/features/ai/metrics_tools_test.dart` +5 例（开启后有键且带标题并点名；默认关闭无键；
  样本不够时明说"看不出结论"且不点名；最多点 3 个、其余只说数量；归不到知识点时明说且不当作最差点）。
- `flutter test test/domain/services/cognitive test/features/ai test/features/cognitive --concurrency=1`
  → `+581 All tests passed!`；`dart analyze lib test` → `94 issues found.`（0 error / 0 warning）；
  `dart format` 0 变更。

**下一步**
- 攒够 20 条以上复习后再看逐点留存，才知道"哪些知识点在漏"值不值得做成计划；
- 组卷页控件（Q17，见轮次四十）、threadflow 与组卷的 `reasonZh` l10n；D 抓取登录态需要用户明确授权。

---



**做了什么**
- 新 `app/lib/domain/services/cognitive/calibration.dart`（纯逻辑）：对 `review_logs.predicted_r`
  做二参数 logistic 重标定 `p = σ(a·logit(R) + b)`，给出**全局偏置** `b`（低估自己 / 过度自信）、
  **离散度斜率** `a`（预测太平 / 太极端）、两者标准误与显著性 `z`（95% 口径 1.96），全部用解析梯度
  求解；起始点固定 `(1, 0)`，无随机 → 同输入必得同输出。
- 五种结局 `CalibrationVerdict{noSamples, tooFewSamples, singleClass, notConverged, ok}`：门槛
  `kMinCalibrationSamples = 30`、斜率可读门槛 `kMinSlopeSamplesForTrust = 200`（截距 30 条就有意义，
  但要区分"太平/太极端"需要更多样本），拒绝时把**中文理由**带出来（`refusalReasonZh`）。
- 新 `app/lib/features/cognitive/application/calibration_reader.dart`：**一次** `retentionSamples`
  同时喂 M6 的留存/Brier/ECE 与本片的重标定——两半讲的是同一批复习。
- 新 `app/lib/features/ai/tools/metrics_tools.dart`：只读工具 `review_metrics`（整体留存、最多 4 个
  有样本的间隔桶、Brier/ECE、`report.summaryZh`），注册进 `tool_registry.dart`。
- 文档：新 `docs/CALIBRATION.md`（把 `docs/REASONING_LAYER_DESIGN.md:236` 引用已久、但一直不存在的
  本地协议补上）；`docs/ASSESSMENT_DESIGN.md` M6 的"未做"清单相应改写。

**为什么不这么做**
- **只检验、不写回**：`cognitive_priors.calibrated` 仍然写 0。模型参数改不改是显式动作，不能因为跑了一次
  拟合就悄悄改掉；这一层是**全 app 唯一一条外部检查**（诊断读模型自己的状态，标定只读 `review_logs`）。
- **"不算"是正当结论**：样本不足、只有一类结果、拟合不收敛时**拒绝给系数**，并把理由原样送到摘要、
  `toJson().refusal` 与 AI 工具。硬报一个数比拒绝更坏。
- **不给假精确**：数据"几乎可分"时最大似然估计不存在，系数与标准误一起冲到几十上百 → 量级守卫
  （10.0）拒绝，而不是报 `b = 27 ± 15000`。
- **`kLogitEpsilon = 1e-3`**：夹到 `1e-6` 会把 logit 推到 ±13.8、样本权重掉到 `1e-12`，信息矩阵退化 →
  等于用实现细节否掉真实样本。"完全确定"读成 99.9% / 0.1% 是记忆预测该有的口径。
- **不做逐知识点标定**（切完普遍不足 30 条）、**不给工具"建议改什么参数"**（需要先有结论，且改参数必须显式）。
- 六个 MindNet 实验**不在本仓库做**：那批数据在外部只读文档 `E:\Document\MindNet\docs\CALIBRATION.md`。

**验收**
- 新增 `app/test/domain/services/cognitive/calibration_test.dart`（17 例：四种"不算"、过度自信/低估/
  校准良好、斜率门槛、边界 0/1、确定性、`toJson` 契约）+
  `app/test/features/ai/metrics_tools_test.dart`（12 例：只读两条证明、空库、无预测、样本不足、过度自信、
  分桶、间隔分桶、时间窗、`limit`、非法参数、注册与 schema）。
- 回归 `flutter test test/domain/services/cognitive test/features/ai test/features/cognitive --concurrency=1`
  → `+569 All tests passed!`；`dart analyze lib test` → `94 issues found.`（0 error / 0 warning）。
- 修掉三处真 bug（都写进文档）：梯度判据 1e-10 让已收敛的拟合**误报"没收敛"**；纯牛顿步在两端聚集的
  数据上来回过冲（改为带回溯）；`kLogitEpsilon` 过小导致信息矩阵退化。

**下一步**
- 攒够带预测的样本（≥30 条）后跑一次 `review_metrics`，看偏置是否显著；
- 组卷页缺的控件（目标难度 / 每知识点上限 / 重置）、threadflow 与组卷的 `reasonZh` l10n；D 抓取登录态。

---

## 2026-10-16 轮次三十七：拍照整理的待确认队列页（Q15 UI，teammate `question-intake`）

**做了什么**
- 新 `app/lib/features/questions/presentation/handwriting_queue_page.dart`（515 行）：照片 `ChoiceChip`
  清单 → 「整理」+ 进度 → 失败原因 → 三类提案卡（标签 / 知识点 / 闪存卡）→ 逐条确认 + 全部确认 →
  `detailZh` / `lastReport` 汇总 → `forget` → 空态给「去收题」入口。
- 入口两处：收题页每张照片的「整理」动作、`settings_page.dart` 第二条 `ListTile`。
- `app_zh.arb` / `app_en.arb` 各 +24 键（`handwritingQueue*` / `handwritingProposal*`），`flutter gen-l10n`
  生成物一并提交。
- 新 `app/test/features/questions/presentation/handwriting_queue_page_test.dart`（8 条 testWidgets）；
  `FakeIntakeStore` 补**同步** `readBytes`（基类 `await file.readAsBytes()` 在 testWidgets 假时钟里
  等不到回调，队列页会挂）。

**为什么不这么做**
- **不显示百分比**：`confidence` 只显示档位（≥0.75「较确定」/ ≥0.5「拿不准」/ <0.5「不太确定」）——
  「0.83」会被读成「83% 正确」，而它其实是模型自评。
- **页面不碰库**：只经 `handwritingQueueProvider` 的 notifier 走读（`refresh` / `analyze` /
  `applyProposal` / `applyAll` / `forget`），不 import 任何仓储、不复算分数；`rationaleZh` /
  `failureReason` / `detailZh` 全部原样展示。
- **失败时不显示旧提案**（否则会让人以为整理成功了）；**已确认的提案不再渲染确认按钮**，避免写第二份。

**验收**
- `dart analyze lib test` → `94 issues found.`（0 error / 0 warning）；
  `flutter test test/features/questions --concurrency=1` → `+85 All tests passed!`；
  `dart format --set-exit-if-changed` → 0 changed（Lead 独立复跑）。
- 基线修正：这条命令此前记的 `+88` 是错的（88 = 该套件 77 + `test/features/ai/question_tools_test.dart`
  的 11），**今后用 +85**。
- 提交 `63e04f0`（10 files changed +1356/-13），已推送 `0ef0fa0..63e04f0`。

**下一步**
- 折叠/展开与照片缩略图、「无待确认时禁用全部确认」的断言、settings 入口的 widget test；
- 服务层 `rawReply` 是否要在页面上露出（目前只存 `failureReason`）。

---

## 2026-10-16 轮次三十六：拍照 → 三类待确认产物——整理只出提案，确认才写库（Q13 领域层+应用层，Lead）

**做了什么**
- 新 `app/lib/domain/services/intake/handwriting_proposals.dart`（纯 Dart，唯一外部依赖 `ChatMessage`）：
  三类产物的提案模型（`HandwritingProposalKind{tag, knowledgePoint, flashcard}`、`HandwritingProposal` /
  `HandwritingCardDraft` / `HandwritingProposalSet`）、提示词构造 `handwritingProposalMessages(...)`
  （system 写铁律 + JSON 契约 + 已有标签路径/知识点标题，各最多 60 条）、严格解析
  `parseHandwritingProposals(raw, {sourceRef})`。
- 新 `app/lib/features/questions/application/handwriting_proposal_service.dart`：
  `HandwritingProposalService.proposeFor(relPath)`（读照片 → 认格式 → 调模型 → 解析；四态失败全部
  返回结果对象，**从不抛异常**）、`applyAll(set, {onlyIds})`（三类产物各按既有领域规矩写库）、
  内存队列 `HandwritingQueueState` / `HandwritingQueueNotifier`（`refresh` / `analyze` /
  `applyProposal` / `applyAll` / `forget`）与两个 provider。
- 把 `handwritingIntakeStoreProvider` / `questionIntakeSupportDirectoryProvider` 从 presentation
  下移到应用层（整理服务与收题页共用同一个 store），presentation 用 `export` 保住原 import 路径。
- 文档：新 `docs/HANDWRITING_INTAKE_DESIGN.md`（做什么/不做什么、契约、三类产物的写库规矩、已知缺口、验收）；
  `docs/QUESTION_BANK_DESIGN.md` §7 补落地状态、§9 切片表把 Q13 标为已完成并新增 Q15（UI 切片）。

**为什么不这么做**
- **不在整理阶段写库**：§7.4 的口径是"确认前不写库"，`proposeFor` 只读磁盘与库——测试用写库计数证明。
- **提案解析是严格的，不做静默降级**：少写一条而用户以为整理完了，比直接报错更糟；坏回复一律
  报"回复不符合契约"并把原文带出来。
- **不自己造标签树**：父路径不存在 → 只报这一条（标签树是几个系统共用的语言，凭空加一层会让别人失效）；
  知识点则相反——`tag_path` 不存在时点照建、只是没挂边，因为点是用户确认过的内容，比一条边重要。
- **闪存卡建模板后必须建卡状态**（`getOrCreateCardState`）：没有卡状态的模板在复习队列里不存在。
- **本轮提案只存在内存里**：重启丢一次整理结果、照片还在磁盘可重跑；要持久化"待确认"本身得加
  schema v13 的表，而"待确认清单"本身就是一种写库，与本片口径冲突。

**验收**
- 新增 `app/test/domain/services/intake/handwriting_proposals_test.dart`（11 例）+
  `app/test/features/questions/application/handwriting_proposal_service_test.dart`（15 例）；
  两个文件 `flutter test ... --concurrency=1` → `+26 All tests passed!`。
- 回归 `flutter test test/domain/services/intake test/features/questions --concurrency=1` → `+88 All tests passed!`
  （provider 下移没有破坏收题页/组卷页/详情页/找相似题区块）。
- `dart analyze lib test` → `94 issues found.`（0 error / 0 warning，与基线同数）。

**下一步**
- Q15：拍照整理的待确认队列 UI（交给 teammate `question-intake`，消费本片冻结的 provider 面）；
- 提案持久化（schema v13）与多图连拍；标定协议；threadflow/paper 的 `reasonZh` l10n。

---

## 2026-10-16 轮次三十五：认知快层抽成非 Riverpod 读取 + `compose_paper` 工具（Lead）

**做了什么**
- 新 `app/lib/features/cognitive/application/library_diagnosis_reader.dart`（纯 Dart：无 Flutter、无 Riverpod，
  只吃 `AppDatabase`）：`readCognitiveObservationInputs(db)` / `readKnowledgePointTagIds(db)` /
  `readLibraryDiagnosis(db, {required model, now, inputs})` —— 把认知页那三个 provider 的读表主体**原样**搬出来
  （活卡判定、孤儿行丢弃、`isNew`、标签只数知识点、starts 取最近复习 5 个、targets = `forced || dueAt <= now`
  等语义一字未改）。`CognitiveObservedUnit` / `CognitiveObservationInputs` / `cognitiveStartNodeLimit` 随之下移，
  页面继续 `export` 它们（既有 importer 路径不变），三个 provider 变成瘦包装（名字与 identity 不变）。
  `inputs` 参数可选：页面把自己已经 watch 的那份传进来，避免同一个页面读两遍表。
- `question_corpus_reader.dart` 新增 `readPaperReadings(db, {required coveredKnowledgePointIds, required diagnosis})`：
  `fastLayerRan == false` → 空；否则取 `覆盖的点 ∪ 诊断出 danger/weak 的点` 的测评先验，过
  `CognitiveReadingsAdapter`，再按"只有 danger/weak 才算结论"过滤。`paper_plan_provider.dart` 的 `_readingsFor`
  改为调它 —— **组卷页与 AI 工具读的是同一份读数**。
- 新 `app/lib/features/ai/tools/paper_tools.dart` 的 `ComposePaperTool`（`name == 'compose_paper'`，
  注册进 `ToolRegistry.forApp`）：入参 `target_count`（默认 10，钳 1..50）/ `subject_keys` /
  `min_source_level` / `per_knowledge_point_cap` / `target_difficulty`；内部
  `readPaperCorpus` + `readLibraryDiagnosis` + `readPaperReadings` + `PaperComposer.compose`。
- `docs/QUESTION_BANK_DESIGN.md` §9 补上工具面切片（记作 Q14，避免与"拍照整理队列（Q13）"撞号）。

**为什么不这么做**
- **先抽读取层，再做工具**：不抽就没法在 Riverpod 之外喂读数；不喂读数，"缺口"清单永远是空的
  （"没跑不等于健康"），那是让工具撒谎。抽完之后工具与页面共用同一份诊断，不可能出现两套结论。
- **越界参数一律失败并说清楚**：来源分级不在 `kSourceLevelPriority` 里 → 列出可用值；难度不在 1..10、
  配额 < 1 → 各自报错；只有题量越界才钳位，且把真实生效值放进 `requested_count` 让模型看得见。
- **没凑够就直说**：`is_short` / `uncovered_knowledge_point_ids` / `deferred_knowledge_point_ids` / `by_knowledge_point`
  全部回给模型，摘要里明说"题库不够、缺口去收题页补，我不会自己出题"；`diagnosis_ran == false` 时明说
  "所有知识点都按没有读数处理——**不是**健康"。

**验收**
- `app/test/features/ai/paper_tools_test.dart` **12 例全绿**（只读构造：任何权限模式都不逐条询问 + 调用前后**整库指纹相同**；
  空库/脏行/学科筛空都"说实话"；无诊断结论 → `zone == unknown` 且摘要含"不是"；来源下限、`target_count` 钳位；
  三个越界参数各自报错；注册与 schema）。`app/test/features/cognitive/application/library_diagnosis_reader_test.dart`
  **4 例全绿**，其中一条是 **parity**：同一个内存库上直接调 `readXxx` 与读
  `cognitiveObservationInputsProvider` / `knowledgePointTagIdsProvider` / `cognitiveLibraryDiagnosisProvider`
  的结果逐字段一致 —— 这就是"抽出去没有改变页面所见"的证据。
- 回归 `flutter test test/features/ai test/features/questions test/features/cognitive --concurrency=1` → **+430 全绿**。
- `dart analyze lib test` → **94 info / 0 error / 0 warning**（= 基线）；`dart format` 后无未格式化文件。

**下一步**
- 标定协议（组卷与找相似题的权重、阈值仍是显式但未标定的取值）。
- 切片表 §9 里唯一还没开工的：拍照整理的"三类待确认产物"队列（§7.4）。

---

## 2026-10-16 轮次三十四：AI 工具面——agent 能"找题"，不能"编题"（Q12 工具面，Lead）

**做了什么**
- 新 `app/lib/features/questions/application/question_corpus_reader.dart`（纯 Dart、无 Riverpod）：
  把所有读表主体从 provider 里抽出来 —— `readPaperCorpus(db)`（题库快照：候选 + 知识点名 + 知识点标签路径）、
  `readChainActionTypes(db)`（每题最新一条链的动作序列）、`readQuestionStems(db, ids:)`（题号 → 题干）。
  `PaperCorpus` 类随之下移；`paper_plan_provider.dart` 仍然 `export` 这些符号，**调用方公开路径不变**，
  两个 provider 变成瘦包装（仍各自 `ref.watchDatabaseRevision()`）。
- 新 `app/lib/features/ai/tools/question_tools.dart` 的 `FindSimilarQuestionsTool`：入参
  `question_id`（基准题）/ `knowledge_point_ids` / `action_types` / `subject_key` / `question_type` /
  `difficulty` / `limit`（默认 5，钳 1..20）；否则**至少要给一个基准**，一个都没有就失败并说明怎么给。
  走的就是 Q12 的 `SimilarQuestionFinder.rank`，题干用 `readQuestionStems` 读回并**截断到 120 字**。
  注册进 `ToolRegistry.forApp`（`app/lib/features/ai/domain/tool_registry.dart`）。
- `docs/SIMILAR_QUESTIONS_DESIGN.md` 新增 §6「AI 工具面」并补齐 §5 验收。

**为什么不这么做**
- **工具只找题、不编题**：题库里没有就是没有，摘要里明说"我不会自己出题，要么去收题页补题，要么放宽条件"；
  不生成题干、不加"看着像"的题。
- **`compose_paper` 工具本轮不做**：组卷要喂认知读数，而读数目前只能从 Riverpod 的
  `cognitiveLibraryDiagnosisProvider` 拿；不喂读数就组卷，"缺口"清单会永远是空的（"没跑不等于健康"），
  等于让工具撒谎。抽一个非 Riverpod 的诊断读取是单独一个 slice。
- 读表逻辑只有一份：AI 工具、组卷页、详情页读的是同一个 `readPaperCorpus`，不各写一套。

**验收**
- `app/test/features/ai/question_tools_test.dart` **11 例全绿**：只读构造（两种权限模式都不逐条询问 +
  调用前后**整库指纹相同**）；按 `question_id` 找到并给出题干摘要/理由/中文动作名/四个分量；长题干截断；
  id 不存在 → `ok:false`；题干为空的脏行当基准 → 0 条；只给条件（知识点 + 动作）能找到；无基准 → 失败；
  题库空 → ok + 0 条；`limit` 默认 5 且钳 1..20；注册与 schema 键齐全。
- 回归：`flutter test test/domain/services/paper test/features/questions/application test/features/ai`
  → **+385 全绿**（读表重构没有破坏组卷/找相似题 provider 与任何 AI 工具测试）。
- `dart analyze lib test` → **94 info / 0 error / 0 warning**（= 基线）；`dart format` 后无未格式化文件。

**下一步**
- Q12 的 UI（题目详情页「找相似题」区块，task-12，teammate 进行中）交回 Lead 独立验收后提交。
- `compose_paper` 工具：先抽非 Riverpod 的诊断读取，再接工具。

---

## 2026-10-16 轮次三十三：找相似题——AI 不出题，只找相似题（Q12，Lead）

**做了什么**
- 新 `app/lib/domain/services/paper/similar_questions.dart`（纯逻辑，无 IO）：`SimilarityFocus` /
  `SimilarityCandidate` / `SimilarityWeights`（知识点 0.50、同型动作 0.30、学科 0.10、难度 0.10，
  `normalized()`）/ `SimilarQuestion`（含四个 `components` 分量与 `toJson`）/ `SimilarQuestionFinder`
  （`rank`、`knowledgePointOverlap`、`actionSequenceOverlap`），阈值 `kMinSimilarityScore = 0.25`。
  四个信号各自归一到 [0,1]，**缺失取中性 0.5**（"不知道"不扣分）；动作比的是**最长公共子序列**
  （顺序不同就是不同解法），链长上限 50；排序 score → 共用知识点 → 同型动作 → 来源分级 → 题号，
  同输入必同输出（与候选顺序无关）。
- 新 `app/lib/features/questions/application/similar_question_provider.dart`：`chainActionTypesProvider`
  （`reasoning_chains` + `reasoning_steps` 各查一次，每题只认**最新一条链**的步骤动作序列）、
  `similarCandidatesProvider`（复用 Q11 的 `paperCandidatesProvider`）、`similarQuestionFocusProvider(id)`
  （候选里找不到就回落到直接读行）、`similarQuestionsProvider(id)`（接 Q11 的知识点标签桥 + 知识点名字）。
- `reasonZh` 确定性中文模板：共用知识点（有名字用名字，最多列 2 个）→ 同型步骤（用词表中文标签，
  词表外的 key **原样显示**不隐藏）→ 跨学科迁移 → 难度 → 来源分级；弱信号时兜底成
  "同学科、难度接近，但还没有可对照的知识点或思维链"。
- 新 `docs/SIMILAR_QUESTIONS_DESIGN.md`（冻结契约 §1–§5）；`docs/QUESTION_BANK_DESIGN.md` 切片表更新
  （Q9/Q10/Q11 标已完成 + Q12 本轮 + Q13 拍照整理"三类待确认产物"队列）。

**为什么不这么做**
- 不出题：候选为空就返回空列表（`uncoveredKnowledgePointIds` 只报缺口、不补），模型不生成。
- 不引向量库 / 不调模型：只用库里已有的结构化信号，可离线、可复现、可解释；题库量级（每天约 30 道）
  远不够触发性能问题，先线性扫描，要快先加索引/缓存。
- 相似结果不落库：它是读数不是事实（与 Q5 卡点评估同一规矩）。

**验收**
- `app/test/domain/services/paper/similar_questions_test.dart` **14 例全绿**：共用知识点排序与分量；
  自己不推荐自己；跨学科同型 → 迁移标记；LCS 顺序（逆序分更低、空序列 0）；缺学科/缺难度取中性；
  难度差越大分越低；弱信号不过阈值（阈值调低才进）；`limit` 语义；调权改变排序；tie-break 与输入顺序无关；
  `reasonZh` 各段（含未知动作原样显示与兜底句）；输入清洗（空白/重复）；`toJson`；空候选不抛。
- `app/test/features/questions/application/similar_question_provider_test.dart` **6 例全绿**：共享知识点 +
  同型动作入榜且理由讲同型步骤；跨学科 → 迁移候选；没链时只用结构信号；**多条链只认最新**（旧链不算数，
  两道结构分相同的题因此分出高下）；题干为空的脏行不进候选但仍能当基准题（回落读行）；不与自己配对 /
  库内无相似题 / 不存在的题都返回空列表。
- `dart analyze lib test` → **94 info / 0 error / 0 warning**（= 基线，无新增）；`dart format` 后
  `flutter test test/domain/services/paper test/features/questions` → **+88 全绿**；全量 `flutter test`
  → **+1351 ~2 全绿**（跑在格式化前的等价代码上，格式化只改空白）。

**下一步**
- Q12 的 UI（题目详情页「找相似题」区块）待做：只展示 `reasonZh`，空结果给收题入口，不拿"看着像"的题凑数。
- 推送上轮遗留的 `d85e55b`（Q11）与本轮 commit。

---

## 2026-10-16 轮次三十二：组卷 provider——题库接进组卷器（Q11，Lead）

**做了什么**
- 新 `app/lib/features/questions/application/paper_plan_provider.dart`（本层唯一的 IO 点）：
  `paperCorpusProvider`（一次读 `Questions` + `KnowledgePoints` + `Tags` + `ObjectTags`，题干为空的题不进卷）
  → `paperCandidatesProvider` / `paperKnowledgePointLabelsProvider` / `paperSubjectOptionsProvider`
  → `paperSpecProvider`（`PaperSpecNotifier`）→ `paperPlanProvider`（`PaperComposer.compose`）。
- 题目→知识点走**共享标签**：`TaskKnowledgePointResolver.resolveFromTagLinks(links, sourceObjectType: kQuestionObjectType)`。
- 诊断复用认知页那一次（`cognitiveLibraryDiagnosisProvider`，D2）；键空间已由轮次三十在
  `LibraryDiagnosisRunner.run` 边界统一，这里不再翻译。
- 读数的一处刻意取舍：**只有诊断结论（`danger` / `weak`）才进打分读数**。`CognitiveReadingsAdapter`
  会为"只有测评先验"的点也产出读数，而组卷器把"不是危险区也不是发展区"读成 `healthy`
  （need 0.15，**低于**未知的 0.35）——直接喂进去等于把"没测过"当成"学得好"。先验仍作为已诊断点的
  `R0≈…` 后缀出现在理由行。除 `danger`/`weak` 外的结论（`empty`/`slow`/…）本轮也落"未知"档，属保守取值。
- 读数覆盖**两类**点：有候选的（打分用）+ 诊断出危险/发展区但库里没候选的（`uncoveredKnowledgePointIds`
  = "该去收题"清单；只喂有候选的点会让这个清单永远为空）。

**测试**
- `app/test/features/questions/application/paper_plan_provider_test.dart` → **9 例全绿**（内存库 + 真实仓储造
  题目/标签/知识点/`object_tags`/`cognitive_priors`）：空库给空卷；共享标签 → 危险区进卷且理由行念名字
  （断言不含 `kp-`）；诊断没跑 → 未知而非健康；没挂点的题也进卷；**只有先验的点不当作健康**（附一条对照
  断言：适配器确实产出了读数、组卷器确实会把它读成 healthy）；学科/题量/来源下限真的进卷；目标难度生效；
  危险区无候选 → 进"该去收题"清单；`PaperSpecNotifier` 的钳位/清空/二次点击取消/`reset()`。
- 写测试时抓到并修掉一个真 bug：`setMinSourceLevel` / `setTargetDifficulty` / `setPerKnowledgePointCap`
  原本**无条件**清空可空字段（`clearX: true` 恒真）→ 三个 setter 都只会把值设成 `null`；
  测试先失败（来源下限不生效、目标难度不生效），改成分支后转绿。

**文档**
- `docs/PAPER_COMPOSER_DESIGN.md` 追加 §7 接线（provider 表 + 三条纪律 + 保守取值）与 §8 验收记录；
  §4 的"调用方没做"改成"输入拼装已完成（§7），页面只剩渲染"。

**边界与偏差**
- 只动了 `features/questions/application/**` 与两个测试/文档文件；`features/questions/presentation/**` 与
  `lib/l10n/**` 留给 teammate `question-intake` 的 task-10（同轮并行，互不重叠）。
- 偏差：task-11 原写"三个 provider 各读一次表"，实际落成一个 `paperCorpusProvider` + 三个投影；
  另外多给了 `setTargetDifficulty` / `setPerKnowledgePointCap` / `clearSubjects` / `reset()` 四个 setter。

**证据**
- `dart analyze lib test` → 0 error / 0 warning / **94 info**（= 基线）。
- 本片测试 `flutter test test/features/questions/application/paper_plan_provider_test.dart --concurrency=1` → `+9 All tests passed!`。
- 全量 `flutter test --concurrency=1` → **`+1321 ~2 All tests passed!`**（上一轮基线 `+1312 ~2`，差额 9 = 本片新增用例；
  跑在这一轮的树上，teammate 的 task-10 UI 测试尚未进入）。

---

## 2026-10-16 轮次三十一：题目详情页验收 + 组卷器纯逻辑（Q7 验收 / Q9，Lead）

**Q7 验收（teammate `question-intake` 交付，Lead 独立跑过）**
- 新增 `app/lib/features/questions/presentation/question_detail_page.dart`、`question_detail_providers.dart`、
  `question_vocab_labels.dart` 与 `app/test/features/questions/presentation/question_detail_page_test.dart`；
  `question_intake_page.dart` 加进入口；两份 ARB 新增所需键（`flutter gen-l10n` 已跑）。
- 这一片把 Q4 管道与 Q5 卡点评估**接出 UI**：题目信息 → 「AI 解题 · 拆思维链」→ 步骤/能力动作/依据/
  检验方式 → 叠加 `fusedRisk`/`suggestion`/整体风险/证据覆盖率/未匹配 hint（未匹配 = "没有你的读数"）。
- Lead 独立验收：`dart analyze lib test` → 0 error / 0 warning / 94 info；
  `flutter test --concurrency=1` → `+1296 ~2 All tests passed!`（交付前基线 `+1265 ~2`）。
- 如实记未做：公式/手写 OCR、`rawReply` 的富文本展示（目前纯文本）、"找相似题"入口。

**Q9 组卷器（纯逻辑，Lead）**
- 新 `app/lib/domain/services/paper/paper_composer.dart` + `app/test/domain/services/paper/paper_composer_test.dart`（16 例全绿）。
- 三步：过滤（学科白名单 / 来源分级下限）→ 打分（`need / quality / difficultyFit` 归一化）→
  按知识点配额的贪心（缺省 caps = `ceil(targetCount / 有候选的知识点数)`，下限 1；一道题挂多点时每个点都算配额，
  全部到顶才跳过）。`items` 的顺序就是贪心选择顺序，**界面不许按 `score` 重排**。
- 读数口径复用 `KnowledgePointReading`（threadflow 的）：危险区 `1.0` > 发展区 `0.6` >
  **没有读数 `0.35`** > 已知健康 `0.15`——"不知道"排在"已知健康"之前，与 D2「缺数据不许冒充好数据」一致。
- 每题给"为什么是它"：`reasonZh`（危险区/发展区/健康/未知四档，有先验就带 `R0≈…、置信度 …` 后缀）、
  `improvementNote`（含 `trapNote` 时附上已知坑）、`backgroundZh`（标签路径 → 知识点名 → 知识点 id → "未标注知识点"）。
- **AI 不出题**：凑不出题的危险/发展区知识点进 `uncoveredKnowledgePointIds`（这就是"该去收题"的清单），
  被数量/配额挤掉的进 `deferredKnowledgePointIds`。
- 来源分级表 `kSourceLevelPriority` 与仓储 `kSourceLevelWeight` **同序**，单测把两张表钉在一起。
- 文档：`docs/PAPER_COMPOSER_DESIGN.md`（新）+ `docs/QUESTION_BANK_DESIGN.md` §9 切片表补 Q7–Q10。
- 刻意未标定：`PaperWeights(.55/.25/.20)`、来源档位间距、`kUnknownNeed = 0.35` 都是显式先验，等真实读数回填；
  组卷页 UI、"找相似题"、拍照整理待确认队列仍是 Q10。
- 证据：`dart analyze lib test` → 0 error / 0 warning / 94 info（= 基线）；
  `flutter test --concurrency=1` → `+1312 ~2 All tests passed!`。
- 偏差留痕：task-9 描述里的文档名写的是 `PAPER_COMPOSITION_DESIGN.md`，实际落成 `PAPER_COMPOSER_DESIGN.md`。

**提交**
- Q7 一个提交（teammate 的详情页 + 收题页入口 + ARB + 测试），Q9 一个提交（组卷器 + 测试 + 两份文档）；
  均由 Lead 推送（teammate 从不提交）。

---

## 2026-10-16 轮次三十：观察层键空间统一（Q8，Lead）

接轮次二十九发现的缺陷：快层的图节点是**标签**，而页面/题目手里是**知识点**。上一轮只在
threadflow 一条路上绕开，这一轮把桥挪进领域入口 —— 另外两条路（认知页、卡点评估）同样中招。

- **桥**（新）：`app/lib/domain/services/cognitive/knowledge_point_tag_bridge.dart`
  —— `tagIdsByKnowledgePoint` / `tagIdsOf` / `tagIdsOfAll` / `expandKeys` /
  `verdictsByKnowledgePoint`（一个知识点挂多个标签时取**有结论且 id 最小**的那个，与 Q6 同规则；
  纯函数、无 IO、结果与输入顺序无关）。
- **领域入口收口**：`LibraryDiagnosisRunner.run`（`lib/domain/services/cognitive/library_diagnosis.dart`）
  与 `ProblemEvaluator.evaluate`（`lib/domain/services/cognitive/problem_evaluator.dart`）各加一个
  可选参数 `tagIdsByKnowledgePoint`：传了就先把行/起点/目标展开成标签键再进图，出图时把标签键的
  结论**翻回知识点键**。不传 = 旧行为，所以既有的 168 个认知用例（fixture 两边用同一个字符串）
  一字未改、全绿。
- **三条调用路径统一**：`cognitive_model_page.dart` 的 `cognitiveLibraryDiagnosisProvider`
  （新增 `knowledgePointTagIdsProvider` 只负责读 `ObjectTags`）与 `cognitiveReadingsProvider`
  直接吃已是 kp 键的结论；`thread_balance_provider.dart` 删掉自己做的那份翻译；
  `cognitive_tools.dart`（AI 工具）走同一个参数。
- **契约定为**：进出口都是**知识点 id**，标签只是快层内部的图节点。这样"一个数字一个来源"
  （D2）不需要每个消费者各自记得翻译。
- **证据（实测）**：新增 `test/domain/services/cognitive/knowledge_point_tag_bridge_test.dart`
  （15）+ `test/features/cognitive/knowledge_point_key_space_test.dart`（4，用真实仓储建出**不同**的
  `kp-…`/`tag-…`）→ `+19 All tests passed!`；其中哨兵用例**不传映射时断言 `fastLayerRan == false`**
  （把缺陷本身钉成测试），传了之后断言 `true` 且结论键里没有一个 `tag-…` 漏出来。
  `flutter test test/features/ai/cognitive_tools_test.dart test/domain/services/cognitive`
  → `+168 All tests passed!`（Q8 后回归）。
- **旧测试为什么没抓到**：`library_diagnosis_test.dart:50-51` 用 `kp-1` 同时当标签 id 与知识点 id，
  两套键空间在 fixture 里被压成了一套。教训写进 `docs/THREADFLOW_TWO_SEGMENT.md` §8.5。
- **未做**：`reasonZh` 的 l10n（中文串仍在领域层）；AE 权重标定；把卡点/度量接进 AI 工具。

---

## 2026-10-15 轮次二十九：ThreadFlow 两段式接进 App + 发现观察层键空间缺陷（Q6，Lead）

- **段 B 接线的四层**：纯数据 `app/lib/domain/services/scheduling/thread_balance_inputs.dart`
  （`ObjectTagLink` + `TaskKnowledgePointResolver`：任务与知识点挂在**同一个标签**上才算
  "这个任务在练这个点"）；纯投影 `app/lib/domain/services/scheduling/cognitive_readings.dart`
  （`danger`→危险区、`weak`→发展区、先验→`priorR0`；没有任何信号的点**不产出**读数）；
  唯一 IO 点 `app/lib/features/thread/application/thread_balance_provider.dart`（读 `Tags`/
  `ObjectTags`/`KnowledgePoints` + 认知页**自己的**诊断 provider + 测评先验，D2 一个数字一个来源）；
  编排 `app/lib/features/thread/application/thread_rank_service.dart`（`build()` 同时拿段 A 与段 B，
  `ThreadFeed.balanced` / `reasonFor(taskId)`）。
- **边界纪律**：`ThreadFeed.ranked` 仍是 `ThreadRanker.rank` 的输出，`readyTasks` 只在段 B 有结果时
  改用段 B 顺序（缺人时按段 A 补齐，绝不丢任务）⇒ 既有的 5 个 `thread_rank_service_test.dart`
  用例一字未改。段 B 永远跑，空输入退化成中性排序。
- **UI**：`app/lib/features/thread/presentation/thread_page.dart` 每张卡下面一行 `reasonZh`
  （灯泡图标 + 两行截断），**没有新 ARB 键**（本轮 `app_zh.arb`/`app_en.arb` 归 task-4，
  避免文件级冲突）。已知缺口：`reasonZh` 目前只有中文，l10n 化留到下一轮。
- **发现并实测了一条上游缺陷（观察层键空间）**：`KnowledgePoints.id` 是 `kp-…`
  （`anki_repository.dart:25`），`Tags.id` 是 `tag-…`（`tag_repository.dart:27`），而快层的图节点
  是**标签**（`cognitive_graph.dart:105` 直接取 `row.id`）、诊断也按 `tag.id` 查
  `rowsByKnowledgePoint`（`library_diagnosis.dart:147-157`）。但
  `cognitive_model_page.dart:768-810` 传进去的 `rowsByKnowledgePoint`/`starts`/`targets`
  全是**知识点 id**，于是真实数据上三者全被"不在图里的 id 直接丢掉"，页面永远显示"没诊断"。
  实测（临时探针：真实仓储建 `tag-…` + `kp-…` + 一行 `card_states`，跑页面那条 provider）：
  `page fastLayerRan=false byKnowledgePoint={} starts=[] targets=[]`；同一份数据只把键换成标签 id
  → `fastLayerRan=true byKnowledgePoint={tag-…: empty, tag-…: empty}`。**病因是键，不是数据**。
  `library_diagnosis_test.dart:50-51` 用 `kp-1` 同时当标签 id 与知识点 id，所以既有测试没抓到。
  Q6 只在自己的 provider 里做 `kp → tags` 翻译（取 id 最小且**有结论**的标签），理由行的名字另走
  `KnowledgePoints.title`（`domain_balance.dart` 的 `knowledgePointNames`，UI 上不出现裸 id）；
  **上游观察层没动**——它需要一条独立切片（同一份桥 + D2 口径），不能混在 Q6 里静默改掉。
  详见 `docs/THREADFLOW_TWO_SEGMENT.md` §8.3。
- **证据**：`dart analyze lib test` → `error=0 warning=0 info=94`（基线）；
  `flutter test test/features/thread test/domain/services/scheduling` → `+81 All tests passed!`
  （段 A/B 71 + Thread 服务 7 + 新增 provider 3）。
- **未做**：`reasonZh` 的 l10n；观测层键空间修复（上游）；AE 权重标定（§3 的数是显式选定，非拟合）。

---

## 2026-10-15 轮次二十八：推理管道接真模型 + 沿链卡点评估（Q4+Q5，Lead）

- **Q4 管道**（`app/lib/features/questions/application/question_reasoning_service.dart`）：
  `QuestionReasoningService` 的两个依赖（`QuestionRepository` + `ModelAdapter?`）都是注入的，测试塞
  `FakeModelAdapter` 即可、不需要网络与 provider override。`solveAndDecompose(questionId, {modelId,
  save = true})` 的固定顺序：`byId` → `optionsOf` → `solveThenDecompose(题干**原文直传**)` →
  `adapter.runTurn(messages: …, tools: [])`（空工具表：这一步不需要工具）→ `parseChain` →
  `saveChain(source: 'ai', model: modelId)`（同时把 `question.state` 置 `processed`）。
  四种失败态（离线 / `ModelFailure` / `ReasoningParseException` / 题目不存在）一律返回
  `ReasoningRunResult` 并带 `failureReason`，模型侧与解析失败都尽量带 `rawReply` 原文片段——**不抛异常**，
  否则每个 UI 调用点都要写 try/catch，而且容易把栈直接显示给学生。
- **Q5 卡点评估**（`app/lib/domain/services/reasoning/stuck_point_evaluator.dart`，纯逻辑：无 DB/时钟/
  Flutter，`nowHours` 由调用方传入，与 `dsr_memory.dart` 同一约定）：`modelRisk`（模型的**群体**先验）
  与 `stateRisk`（由 `DsrState` 算出的**个体**读数）分开存、分开暴露，`hasStateEvidence` 明说这一步
  有没有个体证据；融合 `fusedRisk = 0.5·modelRisk + 0.5·stateRisk`（**0.5 是刻意的**：标定协议还没跑过，
  偏向任一边都是无依据调参）；状态风险 `0.6·(1−R) + 0.4·(D−1)/9`（「忘」与「难」的干预手段不同，
  所以两项都留）；`knowledgeHints` 两侧 trim 后**精确**匹配，查不到的进 `unmatchedHints` 并原样保留，
  **绝不当成正面证据**。报告给出 `mostLikely`（平手取靠前步）、`byRisk`（排「先补哪一步」）、
  `evidenceCoverage`（这份诊断有多少依据）；建议分档 `≥0.6` 先停下补 / `≥0.35` 自检 / 其余快过，
  且**没有个体证据时每一档都追加「（暂无你的状态数据）」**。
- 测试：新增 `app/test/domain/services/reasoning/stuck_point_evaluator_test.dart`（9 例）+
  `app/test/features/questions/application/question_reasoning_service_test.dart`（7 例）= **+16**；
  管道测试用内存 drift（`AppDatabase.forTesting(NativeDatabase.memory())`）+ `FakeModelAdapter`，
  覆盖成功落库、`save:false`、离线、模型报错、回复不合契约、题目不存在、题干/选项原样进提示词。
- 文档：`docs/REASONING_LAYER_DESIGN.md` 新增 §10（管道 Q4）与 §11（卡点评估 Q5）。
- 证据：`dart analyze lib/domain/services/reasoning lib/features/questions/application
  test/domain/services/reasoning test/features/questions/application` → `No issues found!`；
  `flutter test test/domain/services/reasoning/stuck_point_evaluator_test.dart
  test/features/questions/application/question_reasoning_service_test.dart` → `+16 All tests passed!`。
- 过程中的三次修正（留痕）：① 「忘光了 + 高难度 → 高卡点」最初用 `stuckRisk 0.3` 断言融合 ≥ 0.6，
  实测 **0.569** —— 是参数不够极端而不是逻辑错，改用 0.9 并补一条「状态证据会把低先验往上拉」的断言；
  ② 「暂无你的状态数据」原本只加在高风险档，导致中等风险档的测试失败，改成**每档都追加**；
  ③ `ChatMessage` 只有 `content`（`String?`）没有 `text`，测试按错字段写会编译失败。
- 未做：Q2 收题页 B + Q3 拍照/选图入口已交给 teammate `question-intake`（task-4，进行中）；
  Q6 threadflow 两段式接进 UI 仍未开始。
- push 状态：commit `7c8a254` 之后 `git push` 连续两次失败（`curl 35 schannel: server closed abruptly`
  与 `Recv failure: Connection was reset`），本地 `main` 领先 `origin/main` **1 个提交**，待网络恢复重试。

---

## 2026-10-15 轮次二十七：题库地基 + 推理层 + threadflow 两段式（schema v12，三线并行）

用户口径（本轮起点，历史记录）：认知模型是引擎，flashcard / threadflow / 组卷搜题是**同等重要**的应用领域；
agent 是让"高个性化"不带来时间成本、让纸质工作与智能管理同步的工具；标签系统是三者的共同语言。
方向由用户给定：价值在**选择题与加工题**而非来源数量（高价值来源 = 高考真题、部分名校测试、部分强省强市
诊断的高质量模拟）；AI **不出题**，只解题并交出自述思维链，思维链拆成能力动作后喂给 MindNet 跑，
看学生会在哪一步卡住；顺序我定，用 Agent Teams 并行。契约写在 `docs/QUESTION_BANK_DESIGN.md`。

- **schema v12（Lead 单写者）**：`tables.dart` 追加 `questions`（题干/答案/解析/学科/题型/来源分级
  `gaokao|provincial_diagnostic|elite_school|school|personal|unknown`/年份/地区/难度+难度来源/题干指纹/
  易错点/加工状态 `raw|structured|processed`/AI 质量+理由/来源 `manual|ai_scan|furnace`）、`question_options`、
  `reasoning_chains`、`reasoning_steps`（含 `action_type` 存词表**原串**、`stuck_risk` 0–1、
  `knowledge_hints` JSON）。`database.dart`：`schemaVersion` 11→12、`_upgradeV11ToV12()` 建四张空表、
  `_ensureColumns()` 登记"版本号已最新但表缺失"的自愈。`dart run build_runner build
  --delete-conflicting-outputs --force-jit` → `Built with build_runner/jit in 190s; wrote 353 outputs.`
- **`QuestionRepository`**（`lib/data/repositories/question_repository.dart` + provider）：纯 Dart FNV-1a
  64 位题干指纹（去空白+标点归一+小写）挡"完全同一道题"，同指纹入库返回既有题目（`created == false`）；
  检索排序 = 来源权重 → `ai_quality`（NULL 最后）→ 时间 → id，**低价值题只压后不删**；加工只写
  `state`/`trap_note`/`difficulty`/`ai_quality`（题干只追加）；删除显式清选项、标签边、链、步骤
  （本项目生成的 schema 实测无外键，v10 同一条教训）。
- **推理核心（teammate `reasoning-core`，task-2）**：`domain/services/reasoning/capability_action.dart`
  ——跨学科能力动作词表 27 条（key 稳定不本地化、`byKey` 未知返回 null 绝不抛）；`reasoning_prompt.dart`
  ——`solveThenDecompose(...)` 生成"亲自解题并交出自述思维链"的消息、`parseChain(...)` 容错解析
  （markdown 围栏/前后散文、未知 `actionType` 保留原串并标 `knownAction=false`、结构错误抛
  `ReasoningParseException`）。文档 `docs/REASONING_LAYER_DESIGN.md`。**未验证**：没有真实模型输出跑过解析器
  （本机离线），解析器只有手工构造的 JSON 用例覆盖。
- **threadflow 两段式（teammate `threadflow-engine`，task-3）**：`domain/services/scheduling/domain_balance.dart`
  ——段 A 仍是既有 `ThreadRanker.rank`（未改一行，直通入口 `DomainBalanceRanker.feasible` 有逐桶比对测试），
  段 B 在可行域内按有效性（MindNet）与**学科配额**排序：权重 effectiveness 0.50 / urgency 0.25 / goal 0.10 /
  balance 0.15 归一化，`overQuotaPenalty = 1.00` 故意留在归一化之外（配额内必然排在配额外之前）；
  领域键 = 顶级标签祖先，配额 `max(1, ceil(windowSlots/domainCount))`；有效性
  `clamp(0.5 + danger·0.35 + dev·0.20 + 0.30·(1−R0)·conf, 0, 1)`，无读数保持中性。文档
  `docs/THREADFLOW_TWO_SEGMENT.md`。**未验证**：权重与整定值是显式但未标定的取值；DB→`DomainTag/
  TaskTagLink/KnowledgePointReading` 的适配仍留给 UI/service 层。
- 证据：`dart analyze lib test` → 0 error / 0 warning / 94 info（与基线同数）；`flutter test
  test/domain/services/reasoning` → `+46`；`flutter test test/domain/services/scheduling` → `+50`（新 23 +
  既有 27）；`flutter test test/data/database/v12_migration_test.dart
  test/data/repositories/question_repository_test.dart` → `+9`；全量 `flutter test --concurrency=1` →
  `+1207 ~2 All tests passed!`（基线 1131）。
- 并行跑全量时观测到 **1 次偶发失败**（`review_service_test.dart` 的"a miss followed by the solution"，
  断言两次写入的 `dueAt` 差 < 2000 ms；默认并发下负载把两次 `grade()` 拉开），该文件单独跑与
  `--concurrency=1` 全量均为绿——按证据纪律记为"并发负载下的时间窗口偶发"，不是功能回归。
- 未做（下一片）：Q2 收题页 B（应用内收题，用户要求"题库积累要尽早开始"）、Q3 拍照手写整理 →
  补标签/闪存卡/MindNet 节点的任务、Q4 推理管道接 `ModelAdapter.runTurn`（把解析结果落库）、
  Q5 沿链跑学生状态的卡点评估、Q6 threadflow 两段式接进 UI。

---

## 2026-10-15 轮次二十六：M6 学习效果度量——留存率立刻可算，校准曲线从这一版开始积累

用户：milestone ②「链接认知模型和 flashcard，我实际操作发现记忆效果好」。这句话在模型自己有度量之前只是感觉，
本轮把复习日志变成两个能摆出来的量：**留存率**（按"距上次复习多久"分桶）与**校准**（模型判分前给的预测 vs 真实结果）。

- 新的纯逻辑层 `app/lib/domain/services/cognitive/learning_metrics.dart`（无数据库、无 Flutter、无时钟）：
  `recalledFromReview`（客观判分 > FSRS 评分 ≥3 > v1 旧评分 ≥2；`fuzzy`/`Hard` 都**不算**记得——校准要的是
  "能不能取出来"，含印象分会把留存率整体抬高）、`RetentionSample`/`RetentionBucket`/`CalibrationBin`/
  `LearningMetrics.read`（Brier = mean((R−实际)²)，ECE = Σ(n_b/N)·|预测均值−实际|）、`withIntervals`（按
  `(cardStateId, reviewedAtMs)` 推进出间隔；同一毫秒的两次是间隔 0）。默认间隔边界 0/1/3/7/30/∞，默认 5 个校准箱。
  桶与箱**始终完整**：没有样本的桶也画出来，"这周没复习"本身就是要看见的信息。
- **schema v11**：`review_logs.predicted_r`（可空）。为什么必须新增列而不是事后重算——`docs/ASSESSMENT_DESIGN.md`
  §7 的 M6 写清：预测必须在**判分之前**落库，事后按复习后的状态重算等于用已知答案给自己打分。老行一律 NULL
  （"没有预测"和"预测 0.5"是两件事），所以校准曲线**从这一版开始积累，历史不补算**。迁移 `_upgradeV10ToV11`
  只加列；`_ensureColumns` 同步登记，防"版本号跑在列前面"。
- 写入点：`review_service.dart` 在 D2 那段之前算 `predictedR = cognitiveModel.modelReadingOf(state, nowHours:
  modelHoursOf(moment)).r`（`state` 是复习前的行、`moment` 是展示答案的时刻），advisor 抛异常就是 NULL，
  绝不因为顾问失灵把一次已经记好的复习报成失败。`addReviewLog` 新增 `predictedR` 参数，且**从不自己推导**它。
- 读取：`AnkiRepository.retentionSamples({sinceMillis, limit})`——LEFT JOIN `card_states`（导入碎片里卡没了的
  日志仍算一次真实复习，只是没有知识点），读到 `predicted_r` 后交给 `withIntervals`。
- 读数页新卡片 `_LearningMetricsSection`（provider `learningMetricsProvider`）：整体留存率、每个**有样本**的间隔桶、
  以及校准（有样本才显示 Brier/ECE，否则明说"校准曲线还没有样本"）。这一块是整页唯一**不看模型自己读数**的卡片，
  数字全来自复习日志——它是模型的考官，不是模型的自我介绍。
- 开发中踩到的两个坑（都已修，留在测试里）：`Variable.withInt` 不接受 `int?`，`sinceMillis` 的过滤条件因此改成
  拼接 SQL；`_pumpPage` 里除了先验之外还要默认 override 新的 metrics provider，否则"纯 widget"测试又会去开真实数据库。
- 证据：`dart analyze lib test` → 0 error / 0 warning / 94 info（与基线同数）；
  `flutter test test/domain/services/cognitive/learning_metrics_test.dart` → `+16 All tests passed!`；
  `flutter test test/data/database/v11_migration_test.dart` → `+2`；
  `flutter test test/data/repositories/anki_repository_test.dart` → `+7`（原 4 + 3）；
  `flutter test test/features/anki/review_service_test.dart` → `+14`（原 12 + 2）；
  `flutter test test/features/cognitive/cognitive_model_page_test.dart` → `+15`（原 12 + 3）；
  全量 `flutter test --concurrency=1` → `+1131 ~2 All tests passed!`（1105 = 轮次二十五基线，+26 = 本轮）。
- 未做（下一片）：把留存率/校准接进 AI 工具（让 AI 能引用"你这批卡 3–7 天桶只有 62%"）；按知识点聚合的留存
  （现在只按间隔分桶）；板块化 instrument 与标定协议（`calibrated` 仍全部为 false）。

---

## 2026-10-14 轮次二十五：测评层 M1d——先验与观测在读数页合并，并且分得清谁是谁

用户：milestone ①「用户测评来初始化认知模型」继续（口径同前：自评起步、测抽象参数、不从卡片出题）。

- 合并规则（这一片的核心，写在 `docs/ASSESSMENT_DESIGN.md` §7 的 M1d 条目里）：**先验只改一张"还没有
  自己复习史"的卡的起点 `R0`**（`repetitions == 0 && lastReviewedAt == null`）。卡片一旦真的复习过，
  观测接管、先验不再说话——先验是起点，不是替代品，否则"复习校正"这件事就失去意义。
- `cognitive_model_page.dart`：`CognitiveCardReading` 新增 `prior` / `hasObservation` / `r0FromPrior` /
  `displayedR0`，并在 `toJson` 里带上 `prior` 与 `r0FromPrior`；`assembleCognitiveReadings` 新增
  `priorByKnowledgePoint`；`CognitiveReadings` 新增同名字段与 `priorCount`。卡片的 R0 chip 在先验生效时
  显示 `R0 0.90（测评先验）`（新键 `cognitiveEncodingPrior`），备注区新增一行"测评先验"：
  要么"{n} 张卡的起点现在来自测评先验（未标定）"，要么"还没有测评先验"。两种说法都刻意保留，
  因为"零个"本身就是用户在读数页需要知道的事实。
- 读取路径：新 provider `cognitivePriorsProvider`（`assessment_priors` 只在这里被读），
  经 `AssessmentRepository.priorEstimatesFor`（新增批量版）取先验；逐个先验的 `priorFor` 与批量版共用
  同一个 `_mergePriors`，来源优先级不会在两处漂移。
- 一个必须记的副作用：读数 provider 现在会碰数据库，于是 8 条"纯 widget"页面测试（它们 override 观测输入
  与模型、不接数据库）会去开真实的 `AppDatabase`——**测试当场红了 6 条**。修法不是 try/catch 吞掉，
  而是在 `_pumpPage` 里把 `cognitivePriorsProvider` 默认 override 成 `{}`（调用方自己的 override 排在后面，
  按 Riverpod 的"后者胜"仍可覆盖），既保住测试的纯净，也不改变生产路径。
- 先验**不写回** `card_states`、也**不参与** `ReviewAdvisory` 排序：排序仍由 D4/D5 的规则决定，
  本轮只改"展示的起点"。
- 证据：`dart analyze lib test` → 0 error / 0 warning / 94 info（与基线同数）；
  `flutter test test/features/cognitive/cognitive_model_page_test.dart` → `+12 All tests passed!`（原 10 条 + 2 条 M1d）；
  `flutter test test/data/repositories/assessment_repository_test.dart` → `+5 All tests passed!`（原 4 条 + 批量先验 1 条）；
  全量 `flutter test --concurrency=1` → `+1105 ~2 All tests passed!`（1102 = 轮次二十四基线，+3 = 本轮）。
- 文档：`ASSESSMENT_DESIGN.md` §7 的 M1d 由"待做"改为"已完成"并写清合并口径；
  `MINDNET_ROADMAP.md` §0 的"已接入"补上测评层，新增"切片 4：测评层（M1a–M1d）"记录动机与未做项。
- 未做（下一片）：M6 度量——留存率 + 校准曲线，用来验证 milestone ②"记忆效果好"到底成不成立；
  以及板块化 instrument（物理/语文各一套题目形态）与标定协议。

---

## 2026-10-14 轮次二十四：测评层 M1c——第一次能用界面给模型一个起点

用户：milestone ①「用户测评来初始化认知模型」；口径不变——**先自评起步、客观抽检逐步**，测**抽象参数**，
**不从卡片出题**，instrument 按板块设计。M1a（先验纯逻辑）与 M1b（schema v10）之后，本轮把这条链子接上界面。

- 新页面 `app/lib/features/assessment/presentation/assessment_page.dart`（四步）：
  - **①选范围**：标签多选，选中即连**后代**一起算。范围存 tag **id**、展开靠 `parentId` 而不是 `path` 前缀
    （`path` 可空，且改名会重写后代路径）。
  - **②自评**：每个知识点 0–5 的 JOL，再点一次同一枚 chip 就是"跳过"。跳过的点是**不写**，不是写 0——
    "我不知道"不是"我什么都不会"，先验层平均的是它拿到的东西。
  - **③复述抽检**：取范围的**两端与中间**各一个，**确定性**。随机会让两轮不可比；挑"最弱的卡"会把测评
    悄悄变成另一种刷卡——用户明确否掉了这条路（`不建议从卡片出题`）。提示词是知识点本身，不是卡面。
  - **④读数**：这一轮写了多少步证据、重算了几个点的先验、平均 R0 与平均置信度，并把"全部未标定"的
    免责声明摆在正文（设计文档 §2 要求）。
- 两条刻意的不变量：**最后一步之前一个字节都不写**（中途退出不留半截会话），以及**空的一轮仍然记一条
  session**（它是一次测量事件）但**不产生先验**，界面上直说"一步证据都没写"。
- 入口：读数页 `cognitive_model_page.dart:786-812` 新增一节 + `FilledButton.tonalIcon`，`push` 到测评页——
  读数页正是用户发现"模型没有关于我的数据"的地方。
- 测试 `app/test/features/assessment/assessment_page_test.dart`（4 条）：两条驱动完整流程后**查表**——`assessment_sessions`
  一条（`scope_tag_ids` = `["t-root"]`、`finished_at` 非空）、`assessment_responses` 四条（两条 `self_report` +
  两条 `recall`，`judged_by` 全是 `self`）、`cognitive_priors` 三条（只有被评过的 `kp-a/b/e`）；一条从读数页
  入口推页（顺带验证同一数据库被接上）；一条 `recallPicks` 纯逻辑。评分 chip 带
  `ValueKey('self-<kp>-4')` / `ValueKey('recall-<kp>-4')`——一屏有 6×5 枚同名 chip，"第二个 4"不是测试。
- 顺手修：结果步原本拿 `assessmentFinish`（按钮同一句话）当提示，新增 `assessmentResultPending`（zh/en）。
- 记录一个坑：本页刻意**不 import drift**（Flutter 与 drift 都导出 `Column`），因此 `Expression<bool>` 的 `&`
  不可用（`dart analyze` → `undefined_operator`）。改成 SQL 只过滤 `object_type`、tag 侧在 Dart 里用集合过滤，
  代码注释写明这个取舍。
- 证据：`dart analyze lib test` → 0 error / 0 warning / 94 info（与基线同数）；
  `flutter test test/features/assessment/assessment_page_test.dart` → `+4 All tests passed!`；
  全量 `flutter test --concurrency=1` → `+1102 ~2 All tests passed!`（1098 = 轮次二十三基线，+4 = 本轮）。
- 未做（下一片）：M1d 把测评先验与复习观测在读数页合并展示并标注"先验/观测"；M6 度量（留存率 + 校准曲线）。

---

## 2026-10-14 轮次二十三：测评层 M1b——schema v10 三张表 + 仓储 + 迁移单测

用户：milestone ①「用户测评来初始化认知模型」；口径是**先自评起步、客观抽检逐步**，测的是
**抽象参数**（不是"从卡片出题"），instrument 按板块设计；同步不做实时，等 Windows 出可发布
release 时同步一次。

- 承 M1a 的纯逻辑先验层（`app/lib/domain/services/cognitive/assessment_prior.dart`，10 条单测），
  本轮把它落进数据库，按 `docs/ASSESSMENT_DESIGN.md` §5 建三张表：
  - `assessment_sessions`：一次**测量事件**（`subject_key` / `scope_tag_ids` JSON / `started_at` /
    `finished_at` / `budget` / `note`）。范围存 tag **id** 不存路径（改名会重写后代路径）。
  - `assessment_responses`：**只追加**的步骤。`step_kind` = `self_report` / `recall` / `objective`；
    客观的 `correct` 与主观的 `self_rating` 是**两个列**——先验层正是靠两者之差算校准偏置，
    压成一个"分数"列就把这个区别丢了。
  - `cognitive_priors`：**派生**的先验，主键 `(knowledge_point_id, source)`；`d` / `fluency` 可空
    （没抽检就没有难度，没自评就没有流畅度），`calibrated` 默认 0（设计文档 §2：全部未标定）。
- `schemaVersion` 9 → 10：`_upgradeV9ToV10()` 建成空表（不开测评界面的安装读到的行为与之前完全
  一致），`_ensureColumns()` 追加"版本号已是最新但表缺失"的自愈（Drift 在 `user_version` 已等于
  当前版本时会**完全跳过** `onUpgrade`，v5–v9 的列都是这么修的，v10 的表同理）。
- 仓储 `app/lib/data/repositories/assessment_repository.dart`：开/关一轮、记步、
  `evidenceFor` / `evidenceSince`（折成先验层能吃的 `AssessmentEvidence`，同一知识点的自评取
  最后一次、抽检逐题累积）、`rebuildPriors()`（**先清空再写**——先验是派生的，证据变了几行先验就
  必须消失）、`priorFor()` 合并多来源（blended > objective > self）。两道校验写死：自评步骤必须带
  `selfRating`、客观步骤必须带 `correct`、两者都没有的步骤当场 `ArgumentError`（写进去只会让读数
  多一个空洞样本）。
- 本轮实测到一个项目事实：**本项目的生成 schema 不带任何外键约束**——`PRAGMA foreign_key_list`
  在 `review_logs`、`card_templates` 以及三张新表上**全为空**（连 v2 就有的表也没有），
  `references(...)` 只是意图声明。因此 `deleteSession` 的显式级联不是"额外一道保险"，而是唯一的
  一道；`v10_migration_test.dart` 用断言把这条钉住，表定义注释也改成"不指望数据库"。
- 证据：`dart analyze lib test` → 0 error / 0 warning / 94 info；
  `flutter test test/data/database/v10_migration_test.dart test/data/repositories/assessment_repository_test.dart`
  → `+7 All tests passed!`；全量 `flutter test --concurrency=1` → `+1098 ~2 All tests passed!`
  （1081 = 轮次二十二基线，+10 = M1a 先验层，+7 = 本轮）。
- 未做（下一片）：M1c 最小 UI（选范围 → 自评 → 3 题复述抽检 → 结果页）、M1d 接进读数页
  （先验 vs 观测的合并展示）、M6 度量（留存率 + 校准曲线）。

---

## 2026-10-14 轮次二十二：危险区排前——写完了，量出来了，撤回了

用户：正常任务完成后把认知模型全量接入，并丰富它的应用场景（brainstorm → 筛选 → 实施）。

- 上一轮把「危险」算出来了，但它只活在读数页。本轮本来要把它变成**排序规则**：某个知识点的卡片处在危险区，
  这道题就排到最前（`ProblemEvaluator` 的 danger-first），AI 工具同步报 `danger_knowledge_point_ids`。
  代码写完、单测写完，探针一跑发现规则的前提是错的，于是撤回，并把原因钉在代码里。
- 错在哪（`fast_engine.dart:1580-1592` 自己的注释就是答案）：**`context.goal` 故意把目标节点排除在 drive 之外**
  （"给目标本身加偏置会让它在第一轮就亮起来"）。而 `evaluate_problem_fit` 里每道题的扩散**目标正是这道题自己的知识点**
  ⇒ 目标永不 `CONSCIOUS`。探针实测：`targets=[p1]` 时 `p1=SUBCONSCIOUS@0.269`，而它的兄弟 `a,b,c=CONSCIOUS@0.316`。
  也就是说，按"只看这道题自己的知识点"过滤后，`dangerKnowledgePointIds` **必然是空的**（新单测的期望值 `[]` 不是 bug，
  是这层的定义在说话）。
- 放宽过滤也不行，而且更糟：六组夹具（`test/scratch_danger_probe_test.dart`，用完即删）显示亮起来的集合由**标签插入顺序 + 容量**
  决定，与卡片是否变旧无关——A 组只把 `a,b` 弄旧、B 组只把 `p2,p3` 弄旧，亮起来的都是同样的 `a,b,c`；
  目标在首位的 D/F 组一个都不亮，把顺序倒过来的 E 组亮最后三个。按这个排序 = 按标签顺序排序，不是按"学生忘了什么"排序。
- 因此本轮的实际交付是**一个被否掉的假设 + 一条边界**：
  - `problem_evaluator.dart` 撤回 danger-first 排序、`dangerKnowledgePointIds` 字段、`_diagnose` 里的元认知读取
    （回到"只返回 complaints"），文件头写清为什么这里**不该**有危险区排序；
  - `cognitive_tools.dart` 撤回 `danger_ranked` / `danger_needs_starts` / `danger_knowledge_point_ids` 与 schema 里那段说明；
  - `library_diagnosis.dart` 的 `readMetacognition` 退回私有 `_readMetacognition`，并注明"这是**关于一次运行**的读数，
    不是一道题的属性"；
  - 危险区仍然活在它本来就有意义的地方：读数页、（复习页的）对照说明，以及喂给 `FastDiagnosis.bottlenecks` 的 `dangerRows`。
- 证据：`dart analyze lib test` → 0 error / 0 warning / 94 info；认知相关三个测试文件
  （`problem_evaluator_test.dart`、`library_diagnosis_test.dart`、`cognitive_tools_test.dart`）一起跑 → `+31 All tests passed!`；
  全量 `flutter test --concurrency=1` → `+1081 ~2 All tests passed!`（与 v0.4.2 相同：本轮加了 2 条危险区用例又随功能一起删掉）。

---

## 2026-10-14 轮次二十一：元认知层——「危险（自信但记不住）」第一次算得出来

用户：正常任务完成后把认知模型全量接入，并丰富它的应用场景（brainstorm → 筛选 → 实施）。

- 读数页与复习页都写着「危险」需要一个本应用不存的量，所以它永远不出现——这句话把"没做"说成了"设计"。
  MindNet 第三层（`mechanisms/metacognition.belief.js`）说明缺的是哪个量：信念
  `b_v = sigmoid(b0 + w_fluency·fluency + w_encoding·Σ + w_recency·recency(Δt))`，与卡片真实可回忆的 `R` 相减；
  差 > `delta` 是危险区，差 < −`delta` 是焦虑区，`mean |差|` 是校准度。
- 新增 `lib/domain/services/cognitive/metacognition.dart`：纯逻辑、无 IO、无时钟。
  `MetacognitionParams`（`wFluency 1.5` / `wEncoding 0.8` / `wRecency 0.8` / `tauRecencyHours 6` / `b0 1.5` / `delta 0.2`，**未标定**）、
  `MetacognitionObservation` / `MetacognitionRow` / `MetacognitionReading`、`Metacognition.read`。
  起点不参与判断（JS 同样跳过 `isStart`）："刚复习过"不能证明自己知道。
- **recency 用混合时钟**：`state == conscious` 记 0 小时，否则取距上次复习的小时数，没复习过取 +∞。
  第一版直接取"距上次复习"，结果 recency 与 `R` 一起衰减、差被抵掉（探针实测：4 标签夹具在 nowHours=10000 时差 −0.2668 ⇒ 误判焦虑）；
  换混合时钟后同一夹具 `belief 0.6397` vs `R 0.5062`（差 +0.1335），把时钟推到 100000 就越过 0.2（`danger=[a,b]`）。
  探针 `test/scratch_meta_probe_test.dart` 用完即删，仓库不留探针。
- `library_diagnosis.dart`：`LibraryDiagnosis` 增 `metacognition` 并进 `toJson()`；元认知的危险行同时喂给
  `FastDiagnosis.bottlenecks(dangerRows:)`（同一节点只报一次）。节点 `R` 取代表卡的 `modelReadingOf(row).r`，
  `r0`/Σ 缺失就不参与，不发明默认值。
- 页面：`cognitive_model_page.dart` 摘要下新增"模型怎么看你"卡片——校准度（三位小数）、危险名单、低估名单；
  跑过但一个节点都判不了就明说"这次没有一个知识点能被判断"，有行但没越过 `0.2` 就明说阈值。
  只在 `fastLayerRan` 时渲染：危险/低估是**关于这一次运行**的陈述，没跑就没有可比的，空列表会被读成"没问题"。
  原说明 `cognitiveNoDangerNote`（"本应用不存这些数据，所以它不会出现"）已改写为 `cognitiveDangerNote`。
- 测试：新增 `metacognition_test.dart` 14 条（sigmoid 数值、belief 钉死 0.522484 / 0.784147 / 0.832019 / 0.665967 / 0.476181、
  校准度 0.413851、跳过起点、`r0` 缺省 0.5、阈值两侧）；`library_diagnosis_test.dart` 10 条（"危险永不出现"改成
  "危险来自远时钟下的元认知"，改用 `staleHours = 100000`）；读数页 +4 条（没跑 ⇒ 不渲染；有危险/低估 ⇒ 名单；
  跑过但判不了 ⇒ 明说；没越过阈值 ⇒ 明说阈值）。
- 证据：`dart analyze lib test` → 0 error / 0 warning / 90 info；全量 `flutter test --concurrency=1` → `+1081 ~2 All tests passed!`
  （轮次二十记的是 `+1061`，多出的 20 条 = 元认知 14 + `library_diagnosis_test` 8→10 + 读数页 4）。

---

## 2026-10-14 轮次二十：复习时看得见模型怎么读这张卡

用户：正常任务完成后把认知模型全量接入，并丰富它的应用场景（brainstorm → 筛选 → 实施）。

- 轮次十九之后，快层诊断只活在读数页与 AI 工具里：正在做题的人看不到模型对**这块**的判断，
  "全量接入"缺了最该出现的那一处。
- `review_page.dart` 现在读 `cognitiveReadingsProvider`（**同一份读数**，不是重算一遍），
  取 `zoneByKnowledgePoint[item.knowledgePointId]`：有真卡点时才在标题下显示一枚小 chip
  （`reviewZoneChip`："模型看这块：空（进不去）"）。`healthy` 与 `unavailable` 都不显示——
  两者都是"这张卡上没什么可说的"，每张卡都挂一枚就等于教会用户忽略它；两者的区别仍由读数页解释。
  chip 是文本，不是控件：复习流程里的决定仍然只有"答案"和"评分"两个。
- 词汇只留一份：`bandLabel`/`zoneLabel` 从 `cognitive_model_page.dart` 移到
  `lib/features/cognitive/presentation/zone_labels.dart`，页面 `export` 它（既有 `zoneLabel` 导入方不受影响），
  复习页直接导入。两个界面说同一个 `ReviewZone` 必须是同一个词。
- 队列**仍然**不传诊断（`ReviewAdvisory.order` 的 zone map 不参与排序，传了也没有可观察效果）：
  这是刻意的，写进了 `MINDNET_ROADMAP.md` §4。
- 顺手修掉 `review_page.dart` 注释里的一处乱码（"蹇樺嵈" → "忘记"）。
- 测试：`review_page_test.dart` 新增 2 条（诊断出卡点 ⇒ chip 可见且不写日志；`healthy` 与 `unavailable` ⇒ 无 chip）。
  全量 `flutter test --concurrency=1` → `+1061 ~2 All tests passed!`；`dart analyze lib test` → 0 error / 0 warning / 90 info。

---

## 2026-10-11 轮次十九：读数页真的跑 tierB（`LibraryDiagnosisRunner`）

用户：正常任务完成后把认知模型全量接入，并丰富它的应用场景（brainstorm → 筛选 → 实施）。

- 此前只有 AI 工具 `evaluate_problem_fit` 跑快层，读数页在文件头声明"不跑 tierB ⇒ 每张卡的 zone 恒为 unavailable"。
  用户的"发展区/死角"列因此永远是一句"不可用"，看着像缺陷而不是设计。
- 新增 `lib/domain/services/cognitive/library_diagnosis.dart`：
  - `representativeCardRow(List<CardState>)`（`repetitions` 降序、同则 `id` 升序）——这条规则原先在 `cognitive_tools.dart`
    里独立存在，现在读数页与工具**共用一份定义**，两边不可能再选出不同的代表行。
  - `LibraryDiagnosisRunner.run(...)` 复用 `ProblemEvaluator._diagnose` 的同一配方（`FastGraph.fromSpec` +
    `attention.ignition.T_ign = 0` 覆盖 + `startDiffusion` + `runRounds(4)` + `FastDiagnosis.bottlenecks`）；
    ms 只取 `modelReadingOf(row).r0` 且必须 `isFinite && > 0 && <= 1`，否则进 `nodesWithoutMs`（**不套用 MindNet 的 0.8 默认**）。
  - 三条产品规则写在文件头（`starts` = 最近复习的点，`targets` = 今天到期的集合，`rounds = 4` 未标定）；
    `danger` 永不出现，因为它只可能来自元认知信念行，而本应用不存。
- `cognitive_model_page.dart`：新增 `cognitiveLibraryDiagnosisProvider`（`starts` 取最近复习的 5 个，
  `cognitiveStartNodeLimit = 5`；`targets` = `forced == 1 || dueAt <= now`），`CognitiveReadings.fastLayerRan` 随读数带出。
  `diagnosisByKnowledgePoint` 传 `null`（没跑）或非空 map（跑了）——两者不可合并：`null` ⇒ `unavailable`，
  空 map ⇒ `healthy`（"查过，没问题"）。
- 页面说明从三条增到五条：新增"这次跑没跑（含起点/目标口径）"与"危险需要自信度，本应用不存所以不会出现"；
  `unavailable` 的含义从"本页不跑"改成"这次没做诊断"。使用文档 `docCognitiveBody` 同步改写。
- 尚未做：复习队列（`ReviewAdvisory.order` 的实时调用方）仍不传诊断，队列里的 zone 依旧恒为 `unavailable`。
- 测试：`library_diagnosis_test.dart` 8 条（没有图不跑 / 没有起点与目标不跑 / 孤立节点 = `empty/no_entry` /
  缺卡行报 `nodesWithoutMs` / 非法 R0 当成没提供 / danger 永不出现 / JSON 握手），读数页新增 1 条
  "诊断让 zone 变真、空 map 是 healthy"并给既有两条补 `LibraryDiagnosis.notRun` 覆盖。

---

## 2026-10-11 轮次十八：做错之后"对过答案"是另一个事件（schema v9）

用户：正常任务完成后，把认知模型全量接入并丰富它的应用场景（`docs/MINDNET_ROADMAP.md` 的落地顺序）。

- 起因是 MindNet 文档里一条被我们丢掉的语义（`IO_PROTOCOL.md:81`、`MODEL_v2_MATH.md:418/527`）：
  `wrong` + `reviewed_solution: true` 是 `retrieval_failure_feedback`（不是 `lapse`），closeness 越接近 1（差点想起来）增益越大。
  参考实现里两条分支差 25 倍（`mechanisms/memory.dsr.js:226-243` 的 `LAPSE` 分支 vs `S * inc` 分支）——
  我们此前把所有 `rating <= 1` 都当成 `lapse`，也就是"做错后对过答案"被当成"彻底没想起来"。
- 事件层：`DsrCardState.eventFor(rating, reread, reviewedSolution, closeness)`——只有 `rating <= 1 && reviewedSolution` 才走
  `retrievalFailureFeedback`，默认参数下**逐位不变**（43 条 tierA 与 B01 对拍不受影响）；`applyReview` 与
  `CognitiveModel.modelStateAfterReview` 同步透传。两个锚点常量 `closenessDefault = 0.5`（IO_PROTOCOL §2.3 默认）、
  `closenessNearMiss = 0.6`（MODEL_v2_MATH §3 弱线索带）——**只用文档已定义的锚点，不发明中间刻度**。
- 存储：schema v9，`review_logs.reviewed_solution`（可空 bool）与 `review_logs.closeness`（可空 real）。
  NULL = 没问/不适用，写 `false` 等于替历史数据编造"对过答案"，所以旧行保持 NULL。
- UI：判错后**先不写库**，问一句「差点想起来」（0.6）还是「还是不会」（0.5），未回答时"下一张"禁用——
  两个答案是两个模型事件，事后补写等于对同一次复习应用两次模型列。
- 机制（实测）：`failure_feedback` 的 S 上升、`lapse` 的 S 崩落（同一 ripe 行 20.31 vs 0.49）；
  但本应用自有的两列里 R0 两条路径都不动（只有成功检索抬 R0），Σ 因 `effort = (1-R) + (1-closeness)`
  反而在 closeness 大时增量更小。**新卡 R≈0 时 effort 被钳到 1.0，两条路径的 Σ 完全相同**，
  所以测试必须建在"足够熟"的行上（这是一次真实教训，已写进测试注释）。
- 新增测试：`dsr_card_state_test` 6 条（映射、钳制、两路径 S 走向、closeness 单调、关掉开关时与旧输出逐字段一致）、
  `review_service_test` 2 条（日志两列 + FSRS 完全不变、答对两列都是 NULL）、
  `review_page_test` 4 条（判错先问且不能跳过、两种回答落库、答对不提问）、
  **`v9_migration_test` 4 条**（真实 v8 文件升级、旧日志两列为 NULL、版本号已 9 但缺列时自愈、NULL ≠ 存 false）。
- 顺带修掉一个会在真机升级时炸掉的缺陷：`_tableFor('review_logs')` 缺失，
  `_ensureColumns` 一旦检查 `review_logs` 就抛 `Invalid argument(s): unknown table review_logs`——
  也就是**任何真实 v8 库升到 v9 都会打不开**。被新写的迁移测试当场抓到（不是猜的）。

---

## 2026-10-11 轮次十七：桌面端 AI 细化 + 闪存卡与复习计划 + 设置「关于」

用户四条：①agent loop 调用工具次数要能设置；②文本框允许拉伸和换行；③侧边栏允许折叠；④加"组卷网找题""议论文写作"skill；
并指出认知模型远不止已接入的那些（→ `docs/MINDNET_ROADMAP.md`）。

- AI 设置：schema v7 加 `local_settings.ai_max_rounds`；`AiConfig.maxRounds`（`defaultMaxRounds = 8`，NULL 解析为默认）
  在设置页可改；消息框按行拉伸（1–12 行、默认 3 行，`minLines == maxLines` + 拖拽手柄）；
  会话侧栏可折叠（`_sidebarOpen`；窄于 `_sidebarBreakpoint = 900` 时连按钮都不给——按不动等于没有）。
- 用量遥测：新增 `presentation/widgets/turn_usage_panel.dart`（轮数/步数/总 token/tokens-per-second/缓存命中率/上下文占用率；
  缓存缺失显示 `—` 而不是 0%；上下文窗口是**按常量估算**并如实标注），`AgentLoop` 产出 `TurnUsage`；
  面板放在消息列表里（随内容滚动，滚到底部时正好在输入框上方可见）。
- 文档工具：第 11 个工具 `create_document`——把正文写成 `<appSupport>/documents/*.md|.txt`，
  512 KiB 上限、文件名消毒（Windows 非法字符/`..`/保留名）、不覆盖同名；**明确不做 DOCX/PDF**。
- 内置 skill 两个（`.fskill` 容器见轮次十五）：`zujuan-finder`（`networkAllow: ["zujuan.xkw.com"]`）与
  `argumentative-writing`（纯提示词），设置页一键安装。
- 闪存卡 UX：提示按钮（用户触发才显示）、三种判分 `strict|lenient|self`、题型偏好
  `mixed|fill_blank|mcq|essay|fill_blank_lenient`（v7 两列，NULL = 用户没选）、mcq/essay 进队列。
- 复习计划：schema v8 新表 `review_group_plans`（卡组=标签子树，new/review 每日上限，**没有行 = 不限**，
  `isReviewCapped` 规定目标 ≤ 0 视为不限）+ `review_plan_page.dart`；
  `ReviewService.buildQueue` 在配额耗尽时只压制"从未见过"的单元，**强制重来（答错的卡）不受配额影响**。
- 设置页：新增「关于」（版本、数据目录、出网只有两处、已知未做六条）与使用文档四段（AI/复习/知识库/认知模型）；
  `core/app_info.dart` 成为版本号与 User-Agent 的单一来源，并有与 `pubspec.yaml` 对照的测试兜底。

---

## 2026-10-02 轮次十六：AI 能处理标签树（create_tags）

用户：AI 要能对标签树也进行处理：添加、删除。

- 删除早就有（`delete_content` kind=tag：整棵子树、逐条确认、可撤销）；缺的是**添加**。
- 新增工具 `create_tags`（第 10 个）：一次 1–20 个，每个可给 `parent_id` 或 `parent_path`（如 `物理/力学`）。
  父标签**显式解析**：id 找不到、路径不存在 ⇒ 拒绝执行并在理由里说清，**绝不默默建到顶层**——
  建错父标签得到的是另一个标签（`物理/力学` ≠ `力学`）。
- 普通可撤销写入（risk=`write`：自动模式直接执行、按计划模式本轮汇总确认）；撤销＝删除本次创建的标签（连同子树）。
- 同名兄弟自动加后缀（`力学-2`），重名不会失败；名字含 `/` 被拒（层级只由 parent 决定）。
- 系统提示词补一句：新增标签用 `create_tags`，父标签 id/路径先 `query_content` 查。

测试 +9：顶层/按路径/按 id 建、父标签不存在拒绝且不落库、批量、重名后缀、撤销只删本次所建、
空与超量拒绝、名字含 `/` 拒绝、注册与风险分级。

---
## 2026-10-02 轮次十五：skill 功能收口（§3 脚本容器 + 工具可调用 + 参考文件进提示词 + 示例 skill）

> 用户问"skill 功能有什么没做到的吗？请完善"，并要求尽快出 release 供安卓日常使用。

### 1. 补齐的缺口（逐条对 `docs/SKILL_FORMAT.md`）

| 缺口 | 现状 |
| --- | --- |
| §3 脚本执行容器：`scripts/**` 从不执行 | ✅ `data/skill/skill_runner.dart`。Windows 专用；子进程一次一调用，`cwd` = skill 私有目录；**环境变量只取固定白名单**（`PATH/SystemRoot/windir/TEMP/TMP/PATHEXT/ComSpec/NUMBER_OF_PROCESSORS`）且 `includeParentEnvironment: false`，**API key 不可能进去**；默认 60 s / 上限 300 s 超时并**杀整棵进程树**（`taskkill /f /t`）；stdout+stderr 共享 256 KB 上限；退出码非 0 作为失败并带 stderr；每次执行落 `ai_actions` 台账 |
| §2.1/§6 `tools/*.json` 只展示、不可调用 | ✅ `domain/skill/skill_tool.dart` + `agent_loop` 每轮读取启用 skill 并注入工具（名字 `<skill>_<tool>`）。**参数双向校验**：Schema 里有而声明里没有 ⇒ 拒绝；声明里有而 Schema 没描述 ⇒ 也拒绝；一个值一个 argv 元素、不经 shell |
| §5.1 审批 | ✅ 风险 `write` + **不可撤销** ⇒ 两种权限模式下**每次调用逐条确认**（走既有引擎，无第二道闸门）；拒绝的调用也写台账，子进程一律不起 |
| §3 联网默认拒绝 | ✅ `networkAllow` 非空必须先由用户在该 skill 卡片上允许一次（记进 `state.json` 的 `networkAllowed`），否则拒绝执行并列出域名。注释写明这是**声明式**而非操作系统级沙箱 |
| §4 宿主能力 | ✅ 只提供 `filesystem_write`；`browser_bridge` 之类在调用时**点名拒绝**，不假装支持 |
| §5.5 平台门控 | ✅ 脚本工具只在 Windows 现身（注入平台以便测试；安卓上提示词仍生效、工具不存在） |
| prompt 只注入 `prompt.md` | ✅ `SkillPrompt` 现在把 `references/**` 也注入（路径统一 `/`），三层上限：单文件 16 KB / 单 skill 48 KB / 整段 64 KB，超限截断标注，**基础规则永不被截断** |
| A7「至少一个自带示例 skill」 | ✅ `data/skill/sample_skill.dart` + 卡片上的「安装示例 skill」按钮：内存里生成 `furnace-demo`（prompt + `scripts/echo.mjs` + `tools/run_echo.json`），脚本回显 argv 与它看得到的环境变量名——**用户能亲手验证"脚本真的跑了、key 真的没进去"**，不必先自己写一个包 |
| 文档过期声明 | ✅ `SKILL_FORMAT.md` 状态头/§7、`AI_DESIGN.md` §5.2/A7、`FEATURE_MATRIX.md`、`skill_manifest.dart`/`skill_store.dart` 里"容器未实现/只展示不注册"的说法全部按事实改写；`skillsIntro` 中英文案同步（"包里的东西不会被执行"已不成立） |

### 2. 仍未做（如实）

- `browser_bridge`：需要配套 MV3 浏览器扩展，本容器不提供（调用时点名拒绝）。
- `.fskill` **无签名/哈希校验**：现状是"你信任你装的那个文件"，只保留 zip 自带的 CRC（能发现损坏，不能发现篡改）。
- 安卓上没有 Node 运行时 ⇒ 脚本型 skill 只在 Windows 可执行（提示词型两边都可用）。

### 3. 验证快照（本会话实跑）

- 新增测试：`skill_runner_test` 21、`skill_tool_test` 11、`skill_tools_loop_test` 6、`sample_skill_test` 4、
  `skill_reference_prompt_test` 6；`test/data/skill + test/domain/skill + test/features/ai` 一起 **+341 全绿**（本机有 Node v24.19.0，没有跳过任何进程测试）
- 全量 `flutter test --concurrency=1` 与两平台 release：见下方提交与 `dist/`
- `dart analyze lib test` → **0 error / 0 warning**（87 info，与基线同数）

---

## 2026-10-02 轮次十四：AI 自主权（能查才能删）+ 安卓端落地（通知权限 / skill 选择器）

> 用户反馈两条：①桌面端 AI 有删除工具却删不掉——**因为不知道 id**；
> ②"内置 agent 应该有权修改一切，这个权力是否被允许使用由用户的选项决定"。

### 1. 根因：能删，但看不见

`delete_content` 早就支持按 id / name / question / title 定位，但：

- 模型**没有列清单的工具**——标签、闪存卡、卡片的 id 只能靠用户在对话里说出来，凭记忆猜名字，
  猜错一个字就得到"找不到…"，没有下一步；
- 按计划（plan）模式下**连查询都要申请**：只读工具只是"声明成 `write` 但什么都不写"，
  而 `ApprovalEngine` 只看 risk ⇒ 查询落在"本轮汇总确认"里，模型连看一眼都得先问。

### 2. 修法

- **`AiTool.readOnly`（新）**：默认 `false`，七个只读工具声明 `true`；`ApprovalEngine` 见到它直接
  `executeNow`，**两种模式下"看"都不需要确认**。这条是 D12 表里本来就写的"只读查询＝自动"，
  现在由代码保证而不是靠约定。判断原则：**agent 有权碰用户的全部数据；需不需要问由权限模式决定，而"看"不是"动"。**
- **`query_content`（新工具，第 9 个）**：`kind = tag | flashcard | card`，返回 id 与足够定位的上下文
  （标签的 path/parent/关联数、闪存卡标题/来源/卡片数、卡片题目与所属闪存卡），支持关键词过滤与 limit。
  与 `delete_content` 成对使用：**先看，再拿 id 动手**。
- **删除定位加一层"唯一部分匹配"**：先精确匹配；没有精确命中时退回包含匹配，**唯一命中才采用**
  （安全前提是删除永远逐条确认、确认框里显示的就是要删的那一条），多命中仍然拒绝并列出候选（含 id）。
  精确命中优先于更长的部分匹配。

### 3. 安卓端

- **通知权限（真 bug）**：Android 13（API 33）起 `POST_NOTIFICATIONS` 是运行时权限，清单声明不够；
  此前代码从不申请 ⇒ **手机上的任务提醒会被系统静默丢弃**。现在在设置提醒时申请一次，
  被拒就明确告诉用户（新增 `tasksReminderPermissionDenied`，中英双语）。
- **`.fskill` 选择器**：Android 走系统文档 UI、按 MIME 过滤，`.fskill` 没有 MIME ⇒ 用户自己的文件选不中。
  安卓改用"任意文件"（包本身随后就要过严格校验），桌面端保持扩展名过滤。
- 提醒的时间点写了一条测试钉住：`TZDateTime.from` 保持**时刻**不变，
  所以"没调用 `setLocalLocation`"不是 bug——免得下一个人去"修"它。

### 4. 验证快照（本会话实跑）

- 新增测试：`content_query_tools_test.dart` 12 条（列清单/过滤/limit/未知 kind、只读免确认 vs 删除必确认、
  query→delete 端到端、唯一部分匹配可用而多命中拒绝、精确优先）、`reminder_instant_test.dart` 2 条
- `test/features/ai` → **`+226 All tests passed!`**
- 全量 `flutter test --concurrency=1` → **`+810 ~2 All tests passed!`**（轮次十三为 +796：本轮 +12 查询/审批 +2 提醒时刻）
- 两平台 release 已重构建，产物见 `dist/`
- `dart analyze lib test` → **87 info，0 error / 0 warning**

---

## 2026-10-02 轮次十三：AI 对话渲染 markdown/LaTeX + AI 删除标签与卡片 + 术语统一为「闪存卡」

> 用户三条诉求：①对话界面要能渲染 markdown 与 LaTeX；②给 AI 加上标签与卡片的删除能力；③「知识点」改名为「闪存卡」。

### 1. 对话正文：markdown + LaTeX

依赖选择（有据）：**`gpt_markdown` 1.3.2**。实测 `dart pub add --dry-run` 在 Dart 3.13.2 / Flutter 3.47.2 下可解，
只带 4 个**纯 Dart** 传递依赖（`val_latex` / `val_latex_flutter` / `val_highlight` / `val_highlight_flutter`，都没有 `plugin:` 段）；
pub.dev 评分 160/160、327 likes、30 天 16.2 万次下载、标签含 `latex`/`streaming`。
备选方案 `flutter_markdown_plus + flutter_math_fork` 要带 11 个依赖，未采用。

实现：`features/ai/presentation/ai_message_markup.dart`（新增）——`AiMessageBody` 负责"谁来渲染"，`aiMessageRendersAsMarkdown` 负责"能不能渲染"；
`ai_chat_page.dart` 只改一行（`SelectableText` → `AiMessageBody`）。

三条规则（都写进注释）：

- **用户消息永远是纯文本**：用户打的字是数据，按 markdown 解析会悄悄改变他看到的内容（`*`、`$` 必须原样）。
- **助手消息在"结构完整"时才按 markdown 渲染**：流式半成品里一个未闭合的 ``` 或 `$$` 会吞掉后面整段，
  所以这类构造没闭合时按纯文本显示，闭合那一刻自动切换。判据只看内容，不看"是否在流式中"——
  已成型的内容边流边渲染才是用户预期的效果。
  - 检查项只有两类：围栏行数（``` 与 ~~~ 各自）奇偶，以及 `$`/`$$` 的配对（`\$` 视为字面量；`$` 后接空白视为普通文本，
    闭 `$` 前接空白同样不算闭）。强调、列表、表格、链接、行内代码**故意不检查**——它们出错只会变成难看的字面量，
    不会曲解整段，若纳入检查则一个落单的 `*` 就会把整条回答降级成纯文本。
- **颜色只取 `Theme.of(context)`**：链接色显式覆写（包默认是硬编码蓝），代码块/表格底色由 `ColorScheme` 推出，
  亮/暗主题都不写死黑白；`MediaQuery.textScaler`（`lib/app/app.dart`）自然继承。

验证：`test/features/ai/ai_markdown_test.dart` **19 条**（markdown 结构、行内/展示公式、`\(...\)`/`\[...\]`、用户文本原样、
流式守卫 6 条单测 + 端到端"经真实 `AiChatPage` 边流边切换"、主题不写死颜色、文字缩放）。
另做了**敏感性实验**（改完即还原）确认断言不是空跑：关掉 `useDollarSignsForLatex` ⇒ 数学断言 2→0 失败；
把守卫强改为恒真 ⇒ 5 条失败。

### 2. AI 删除标签 / 卡片 / 闪存卡

新增 `features/ai/tools/deletion_tools.dart`，一个工具 `delete_content`（`kind = tag | card | flashcard`），已注册（工具总数 8）。

- **破坏性、逐条确认**：`riskFor` 对所有 kind 返回 `destructive`；审批引擎既有断言"没有任何模式下破坏性调用会静默执行"。
- **可撤销**：删除前把原始行（SQL 列名）读入 `before_json`，撤销走 `.tfpkg` 同一套 `restoreTable`。
  删标签的快照含**整棵子树 + 全部 `object_tags` 关联**；删闪存卡含其卡片、`card_states` 与 `review_logs`
  （**学习历史也会还回来**）。
- **绝不猜**：按 id 或按 `name`/`question`/`title` 精确匹配；**匹配到多条即拒绝并列出候选（含 id）**。
- 级联委托仓储（`deleteTag` / `deleteTemplate` / `deleteKnowledgePoint`），AI 与界面不会有两种"删除"语义。

验证：`test/features/ai/deletion_tools_test.dart` **11 条**（注册与风险分级、子树+关联删与撤销、卡片的状态与日志回滚、
闪存卡全量回滚、歧义拒绝、目标不存在拒绝、未知 kind 拒绝）。

### 3. 术语统一：知识点 / 词条 → **闪存卡**

改名范围＝**用户可见文案**（原来界面里同时存在「知识点」与「词条」两种叫法，本身就是不一致）：

| 位置 | 改后 |
| --- | --- |
| 导航 `navAnki` | 闪存卡 / Flashcards |
| `ankiNewKnowledgePoint` / `ankiNoDueCards` | 新建闪存卡 / 没有到期的闪存卡 |
| `knowledgeBoosted` / `knowledgeInsightBoost` | …相关闪存卡 |
| `tagsDeleteBody` / `settingsDemoDataHint` / `packagesScopeHint` / `cognitiveEmpty` | 闪存卡 |
| 模型可见文案（`knowledge_tools.dart`、`cognitive_tools.dart`、`problem_evaluator.dart`）、`demo_data_service.dart` 硬编码串 | 闪存卡 |

**代码标识符、数据库列、MindNet 契约里的 `knowledgePoint`/`KP` 一律不动**——这是没有用户可见收益的迁移。
映射记在 `app_en.arb` 的 `@navAnki` 描述里；顺带删掉从未被引用的重复键 `navKnowledge`。

### 4. 验证快照（本会话实跑）

- 全量 `flutter test --concurrency=1` → **`+796 ~2 All tests passed!`**（轮次十二为 +766：本轮 +11 删除 +19 markdown）
- `dart analyze lib test` → **0 error / 0 warning**，info 数与基线持平
- Windows / Android release：本轮重构建（新依赖必须重出产物），产物事实见下方§5

### 5. 仍未验证 / 已知取舍（如实）

- **没有像素级验证**：所有断言都在 widget 树上（TextSpan 样式、控件类型、装饰色），没有截图/golden/真机。
- **链接渲染但点不动**：`onLinkTap` 留空——应用没有打开外部 URL 的能力，而为此引入 `url_launcher` 属越界。
- **窄屏 + 宽表格未验证**：包默认表格横向滚动，套在最大 560 宽的气泡里，与页面纵向列表的嵌套手势没在真机上试过。
- 守卫的已知误判：整段里出现孤立的 `$`（如「花了 $5」）会让该条降级为纯文本；代码围栏里的 `$` 也参与扫描；
  仅表头、未闭合粗体/反引号/`[label](` 这类半成品按"字面量"处理（已验证不抛异常、文本不丢），
  但"刚到达一半的 `\(`"没测。

---

## 2026-10-02 轮次十二：写库即刷新（响应式）+ 知识库可用 + AI 三件（图片造卡 / 联网抓取 / skill 安装）

> 用户四条诉求：①让 AI 能上传图片并制作背诵卡片；②"最大的问题是状态更新——现在还要重启才能更新日程、任务等界面"；
> ③知识库的三点（命名、已导入包列表、选择性导出）；④让 AI 能浏览网页抓取元素，并安装 skill。
> 四条全部落地；下文的数字都来自本会话实跑。

### 1. ② 响应式：根因与机制

根因不是热重载：界面数据来自**非 autoDispose 的 `FutureProvider`**，页面 `ref.watch` 到的是**缓存值**；
而写库只发生在动作所在的那个页面里，跨来源的写入（AI 造卡、导入知识包、复习评分）**没有任何人通知其他页面**，
于是只有重启（或该页面自己的 `invalidate`）才更新。

新机制是一条链、四个文件：写语句 → drift `QueryExecutor` → `DbWriteInterceptor`
（`insert/update/delete/custom/batch`）→ `DataChangeBus.recordChange()`（微任务合并）→
`dataRevisionProvider` → 19 个 `ref.watchDatabaseRevision()` 的 provider 重新取数 → 页面重建。

- **拦截点在执行器层，不在仓储层**：新增仓储、新增 AI 工具在结构上不可能"忘记通知"。
- **前台恢复也算一次变化**（`home_shell.dart` 的 `WidgetsBindingObserver`）：到期卡、今天的日程、
  "N 分钟前排序"都是时钟派生，后台放一夜没有任何写。
- 复习页在**答题中途不刷新队列**（不丢进度）；Thread 在已有排序结果时自动 `sort()`（排序器纯读，不会自激）。
- 设计文档（新增）：`docs/REACTIVITY_DESIGN.md`——不变量、覆盖清单、刻意不覆盖、验证方式。
- 关键验证：`test/features/reactivity_live_page_test.dart` 挂**真实标签页** + 外部写 ⇒ 新数据出现；
  **对照组**把 revision 冻结成常量（复现改动前行为）⇒ 同样的写不可见。两条一起才说明测的是这条链。

### 2. 顺带修掉的真 bug：Android release 根本没有 `INTERNET`

`app/android/app/src/main/AndroidManifest.xml` 此前只有 debug/profile 清单带 `INTERNET`
（Flutter 默认如此）⇒ **AI 在 Android 正式包里从来连不上网**。已补上，并按事实改写
`docs/PRIVACY.md`（"默认无网络权限"这条承诺不再成立，改为"AI 未配置 key 时没有任何网络调用"）。

### 3. ③ 知识库

- 中文导航 `navAnki` 由未翻译的 "Knowledge" 改为「知识点」，与「知识库」（`.kpak` 导入导出）区分；
- 知识库页现在**列出已导入的知识包**（名称/版本/作者/导入时间/条目计数），随 revision 自动刷新；
- 导出对话框新增**版本号**与**导出范围**（全部内容 / 按标签筛选）：按标签导出只带所选标签及其知识点，
  **不含思维导图**（半张导图是坏树，不是小树）。

### 4. ① 图片 → 背诵卡片

- `vision_payload.dart`：`dart:ui` 解码 + 降采样（长边 1280、`allowUpscaling:false`）+ 4 MB 上限，超限**拒发**；
- `model_adapter.dart`：`ChatImagePart` / `ChatMessage.images` / `contentParts`——**无图时仍是纯字符串**，
  文本链路逐字节不变；
- `ai_attachment_store.dart` + `ai_repository.addAttachment`：图片落 `<appSupport>/ai_attachments/`，
  库里只存相对路径（字节不进数据库，沿用既有 `Attachments` 表，**无 schema 改动**）；
- `create_knowledge_cards`（写工具）：走既有审批引擎，`afterJson` 记 id，撤销 = 删除所建。
  无卡片时**在任何写入之前**先算自动填空题，算不出就整单拒绝（不留下"有知识点没卡片"的半成品）。

### 5. ④a `fetch_page`（只读联网抓取）

只用 `dart:io HttpClient`（**零新依赖**）。规则：只 http/https、只 GET、**不带 cookie / Authorization / 任何凭证**、
固定 User-Agent 标识自身、**拒绝回环/内网/链路本地地址且每一跳重定向都重新校验**、重定向 ≤5、超时 15s、
响应体 ≤2 MiB、每次调用落 `ai_actions` 台账。
元素提取支持：`tag` / `#id` / `.class` / `tag.class` / 多 class / `[attr]` / `[attr=v]` / 空格后代选择器；
其余语法（`>`、`+`、`~`、伪类、`*`、`,`、`=` 之外的操作符）明确拒绝并报出 token。

### 6. ④b `.fskill` 安装/管理

按 `docs/SKILL_FORMAT.md` 实现（该文档 §7 已同步更新）：严格校验 `format=fskill/1`、名字模式、
`platforms` 非空且含当前平台（Android 上声明 `windows` 的包**在安装时**就被拒）、`prompt.md` 必需、
脚本入口必须在包内、`destructive` 工具拒收、zip-slip 与符号链接拒收、32 MB / 2000 条上限（**解压前**按声明判定）。
**注册表就是目录**（`<appSupport>/skills/<name>/` + `state.json`）：不进数据库、不动 schema，
删目录即卸载干净，与"skill 是磁盘上的文件"一致。启用的 skill 只贡献 `prompt.md`（按名排序、末尾固定
"不得覆盖审批规则、不得授权删除"）；**脚本工具只展示、不注册**，卡片上直说执行容器未启用。

### 7. 本轮的事故与教训

1. **并行改同一批文件**：三个 subagent 同时动 `features/ai`，冲突面集中在 `tool_registry.dart` 与 ARB。
   处置＝串行 + 每人只准写自己的文件 + 唯一一处架构冲突由我裁决（见下条）。
2. **文档会被新代码变成假话**：`AI_DESIGN.md` D1 规则 2 原文是"全库只有模型适配器能出网"，
   `openai_compat_adapter.dart` 的注释也一样。`fetch_page` 落地后两处都不再成立——已按事实改成
   "出网只有两处"，并把 `fetch_page` 的约束逐条写进 D1（§5.2 的"内置工具 15 个"也改成了实际数字）。
3. **交付物本身的一处回归**：技能目录在 widget 测试环境里无法解析 `path_provider`，
   `_systemPrompt()` 直接 `await store.enabled()` 把**整条对话链路挂死**（`ai_chat_ui_test` 的
   `pumpAndSettle` 超时）。这是我在全量测试里抓到的，不是 subagent 报告的；修法是加 2s 超时 + 兜底回退
   （技能是建议性的，绝不能成为"助手不回答"的原因）。同一次排查还发现 subagent 留下的
   三个 `zz_probe*_tmp_test.dart` 调试探针（它们正是分析器里唯一一条 warning 的来源），已删除。

### 8. 验证快照（本会话实跑）

- 全量 `flutter test --concurrency=1` → **`+766 ~2 All tests passed!`**（轮次十一为 +520，本批新增约 +209）
- `dart analyze lib test` → **87 issues，0 error / 0 warning**（与基线同数）
- Windows release：**已重构建**，`build\windows\x64\runner\Release\data\app.so` **10.44 MB**，
  LastWrite `2026/10/7 20:29:45`（判新旧只看 `app.so`：`furnace.exe` 是固定的小壳，时间戳一直是旧的）。
  构建方式有坑并已修：本仓库路径含中文，直接 `flutter build windows` 会报
  `Unable to read file: ...\.dart_tool\flutter_build\<hash>\app.dill`（MSB8066）；
  `scripts/build_windows.ps1` 已改为与 Android 脚本同样的做法——准备步骤在真实目录做，
  release 构建从纯 ASCII junction（`E:\Document\furnace-build`）跑，并在构建前清 `flutter_build` 缓存。
- Android release：**已重构建**，`build\app\outputs\flutter-apk\app-release.apk` **65.66 MB**，
  LastWrite `2026/10/7 20:37:12`，签名 `CN=Threadflow`，SHA-256 `57de8b8f…2db2`
  （与上一版同一把签名 ⇒ 覆盖安装保留数据）。构建走 `scripts/build_android.ps1`（ASCII junction + 阿里云镜像）。

### 9. 仍未解决（如实列出）

- `fetch_page` **不做 DNS 解析**，因此"解析到内网地址的域名"不受私网守卫保护（DNS rebinding 洞）；
  代码里写明，要堵住需 resolve-then-pin + SNI，本轮未做。
- 2 MiB 上限与 15s 超时只有**常量断言**，没有真发一个 2 MiB 流或真等 15s（截断路径用注入上限验证）。
- skill 的**脚本执行容器**未实现：能装、能启停、提示词会生效，但 `scripts/**` 不会被执行；
  `.fskill` 也**没有签名/哈希校验**，完整性现状是"你信任你装的那个文件"。
- **没有真机验证**：Android 的选图路径、正式包的联网、以及任何真实模型对 `image_url` 的接受程度，
  都需要你上手实测（默认模型仍是 `deepseek-chat`，不支持图片时错误会由适配器原样透出）。

---

## 2026-10-01 轮次十一：MindNet 认知模型**真正接入**（tierB + 顾问式排序 + 用途 1 + 只读观测）

> 本轮把上一轮的 tierA 移植**接进了复习流程与 AI 工具**，并把协议冻结进代码。
> 协议正文：`docs/MINDNET_CONTRACT.md` §9；集成地图 + 证据台账：`docs/MINDNET_INTEGRATION.md`（新增）。
> 本节所有数字都来自本会话实跑，命令与结果原文在 `MINDNET_INTEGRATION.md` §0。

### 1. tierB 快层移植 + 对拍

`app/lib/domain/services/cognitive/fast_engine.dart`（`dynamics.shunting` 精确积分 / `attention.capacity` /
`attention.ignition` / `context.goal` + `v2/engine.js` 的 `step` 管线）与 `fast_diagnosis.dart`
（7 类瓶颈 + 反事实可达性 + 处方）。随机源按契约 §6.1 掐掉：`T_ign = 0`、不装 `rhythm.gate`（`availability ≡ 1`）。
未移植：`rhythm.gate` / `mulberry32` / `attention.inhibition` / `legacy_v1` / `metacognition.belief`。

对拍：4 个测试文件一起跑 → `All tests passed! (+46)`。**B01 的区分力边界必须记住**：
`mindnet_vectors.json` 的 tierB 只有 1 条用例且 **5 个快照完全相同**（本会话实测 `distinct=1`、`round=[1,1,1,1,1]`），
所以它只证明"第 1 轮全字段逐位一致 + 停止语义"；多轮演化由诊断 fixture 的
`scenarios.multiround_progression`（6 轮互异）补强。

### 2. 标签树 → 认知图投影

`cognitive_graph.dart`：`CognitiveTag` / `CognitiveNode` / `CognitiveEdge` / `CognitiveGraph`；
`fromTags` 的 `ms` 是**必填**（忘传编译不过），父子边 `ls = 0.7`、兄弟边 `ls = 0.4`（**都标未标定**）。
两处刻意的诚实设计：节点缺 `ms` 条目 ⇒ 不写该键 + 进 `nodesWithoutMs`（**不等于** MindNet 的 0.8）；
MindNet 的兜底只以具名常量 `mindNetDefaultMs` 存在，绝不隐式套用。
起因是一次真实的静默分歧：MindNet 对缺省 `ms` 用 0.8（`src/model.js:50`）而把它读作 `R0`
（`mechanisms/memory.dsr.js:90`），与"有 stability、`encoding_strength` 为 NULL 读作 1.0"（D2）冲突——
现在有**三条路径同值**的测试钉住（行读 / 读数接口 / 投影后的 JSON 都必须是 1.0）。

### 3. 可替换接口（`cognitive_model.dart`）

`CognitiveModel{id, retrievabilityOf, expectedGain, orderAdvisory, modelReadingOf, modelStateAfterReview}`
+ `modelHoursOf`（唯一时钟换算）+ `cognitiveModelProvider`（唯一替换点）。
`orderAdvisory` 是**全系统唯一排序原语**：目标集命中 → 增益 ↓ → `dueAt` ↑（`null` 排最后）→ 知识点 id ↑ → 卡 id ↑，
纯函数（有一条"把数据库 close 掉仍能排序"的证伪测试）。
`modelStateAfterReview` 只**算**复习后的 `(R0′, Σ′)`，不落库——复习流程用窄写
`AnkiRepository.updateModelState` 只写这两列（**不碰 `updatedAt`**），且包在 `try` 里（模型坏了不阻断复习）。

### 4. 复习流程接入（段序）

`ReviewAdvisory`：`forced → boosted → model → unseen`。`model` 段顺序直接调 `orderAdvisory`，
**不自己写比较器**；`boosted` 仍是 DiffusionBoost 的启发式（已标注"非模型量"、不与诊断同屏）；
`unseen` 不给新卡打分（D4）。段与组内键用 `cardStateId` 而非 `unitKey`——
无空可挖时 `unitKey` 一律回落 `'essay'`（`review_service.dart:233-235`），多知识点会撞键。
zone 词表 9 值（t2 的 7 类 + `unavailable` + `healthy`）；`healthy`（跑了、无卡点）与
`unavailable`（没跑模型）**必须区分**。

### 5. 用途 1（题目质量/难度评估）

`problem_evaluator.dart`：标签树投影（`ms` 取 `modelReadingOf(row).r0`，即编码上限）→ `FastGraph.fromSpec`
→ 引擎 4 机制 + `T_ign=0` → `FastDiagnosis.bottlenecks` → 6 种判定
（`too_easy` / `zpd` / `too_hard` / `out_of_scope` / `redundant` / `high_value`）+ 排序键；
`difficulty_hint` **只作无历史时的先验**，绝不当模型的 `D`；`starts`/`targets` 必须先过滤成图内 id。
AI 工具 `evaluate_problem_fit`（`cognitive_tools.dart:24`）注册在 `ToolRegistry.forApp`
（`tool_registry.dart:11/43-55`），provider 经 `ToolRegistry.forApp(..., model: …)` 接线——运行时可达。
**一条建模约束**：图节点 id 来自**标签**、记忆行来自**知识点**，是两个 id 空间；不对齐时工具按只读降级为仅 tierA 判定。

### 6. 只读观测面

`app/tool/mindnet_probe.dart`（纯 Dart）+ Flutter 宿主（`test/tool/mindnet_probe_test.dart`）+
报告入口（`test/tool/mindnet_probe_report_test.dart`）：**为什么需要宿主**——`database.dart` →
`path_provider` → `package:flutter` → `dart:ui`，纯 Dart VM 没有 `dart:ui`。
探针先复制库（含 `-wal`/`-shm`）到临时目录、**只打开副本**，原库只被 `stat`；真实库实测运行前后 SHA256 一致。
页面：设置页 →「认知模型」读数页，只读，顶部标注"顾问模式、不改到期时间""`ls` 等边权未标定"。

### 7. 协议冻结与两个守卫

`mindnet_protocol.dart` 把协议串、**冻结 commit `ace605d`**、容差（`rel 1e-12 / abs 1e-15 / round6`）与
`must_be_exact` 名单固化成常量；`mindnet_protocol_guard_test.dart` 读 fixture 比对，漂移即失败
（已做证伪实验：改 commit → 失败并打印两侧值；还原后 SHA256 回到原值）。
**`--check` 不守我们这份**：它比的是 MindNet 实现 vs MindNet 自己的文件，且归一化掉 commit
（`tools/conformance.js:284`）。

### 8. 本轮的事故与教训（都写进文档了）

1. **任务登记结构性失败**：`inScope` 写成工作区外形式 ⇒ `changedPaths` 的两个条件互斥，任务永远登记不了；
   处置是取消原任务并以仓库相对形式重新入账（映射见 `MINDNET_INTEGRATION.md` §8）。
2. **验证任务不能带 failed 验收完成**：`t18`/`t25` 因此以 `failed` 收口、未登记，但报告仍在盘上
   （`docs/VERIFICATION_MINDNET.md`、`docs/VERIFICATION_PROTOCOL.md`）；它们唯一的失败项是
   "MindNet porcelain 为空"，属**先前遗留**。
3. **MindNet 被写脏的根因（实测定位）**：MindNet 的 conformance 测试在用例内执行 `--write`
   （`E:\Document\MindNet\test\conformance.test.js:123-129`），而 `npm test` 就是跑它 ⇒ **跑一次 `npm test` 必然重戳
   `conformance/mindnet_vectors.json` 的 commit**。铁律：MindNet 侧只允许 `--check`；连 `--check`
   打印的"顺手跑一次 `--write`"提示也不得照做；"零写入"核验必须排在整轮动作最后；还原需仓库所有者授权。
4. **中途一次编译级阻塞**（t19 的在改文件 `#517` 括号化级联被推断成 `void`）曾让 `features/ai` 与全量在
   compile 阶段变红；定位、交叉告警、修复后复跑（`features/ai` +105、`dart analyze lib` 0 error）。

### 9. 本轮验证快照（本会话实跑）

- `flutter test --concurrency=1` → **`All tests passed! (+520 ~2)`**（跳过 2 条：探针宿主入口在无 `--dart-define` 时 inert）
- `dart analyze lib test` → **0 error / 0 warning / 87 info**
- 对拍与守卫 → **+46**
- Windows release：exit 0，产物 `app/build/windows/x64/runner/Release/data/app.so` LastWrite `2026-10-01 14:03:09`
- MindNet：` M conformance/mindnet_vectors.json`（先前遗留、等授权还原；本侧未写入未回滚）

### 10. 本轮**没有**解决的（如实列出）

可达性判断因 `ms = R0` 而**偏乐观**（设计取向，非缺陷）；**两个 id 空间**未打通（需要 kp→标签的桥）；
读数页 zone 恒 `unavailable`（页面不跑 tierB）；`ls` / `W_*` / `β_goal` 等**未标定**。
（2026-10-02 更正：本段原有的"Android 未重构建；`.fskill` 容器与 Thread 事件流刷新仍是历史遗留"三条，
前两条已不成立——Thread 事件流刷新已由响应式机制解决（`docs/REACTIVITY_DESIGN.md`）、Android 已在轮次十二重构建；
`.fskill` 的**安装/管理**也已实现（`docs/SKILL_FORMAT.md` §7），仍未实现的只有**脚本执行容器**本身。）

---

## 2026-09-26 轮次十：MindNet 认知模型接入（tierA 记忆层 + 数据统一）

用户离场，授权我自主推进，要求"认知模型载入 Furnace，保证使用流畅性与数据统一性"。

### 0. 关于"拉进同一个 agent team"

**做不到，原因不是不愿意**：AgentTeams 只能把**新的 subagent** 加为成员，我没有任何通道
去联系用户那边独立开发的 MindNet agent 会话；而且本会话审批提示是关闭的，两步审批建队
流程也走不通。所以改用**既有的文件契约**——`docs/MINDNET_CONTRACT.md` §6/§8 双方回应
已在仓库里，信息是齐的，不需要再协商一轮。

### 1. 移植：Dart 版 DSR 记忆层

`lib/domain/services/srs/dsr_memory.dart`：把 MindNet `mechanisms/memory.dsr.js` 的
tierA 记忆层移植为纯 Dart（无数据库、无时钟、无 Flutter，`nowHours` 一律显式传入，
与 JS 的 `u` 一致）。

放在 `domain/services/srs/` 而**不是** `features/ai/`：它是复习调度算法，跟
`fsrs_scheduler.dart` 并列；塞进 AI 模块会让两个模块无谓耦合。

### 2. 对拍：43 个公开值全部复现

`test/fixtures/mindnet_vectors.json` 是把 MindNet 的 `conformance/mindnet_vectors.json`
**拷进仓库**（契约要求钉快照，不要跟 HEAD）。`mindnet_dsr_conformance_test.dart` 逐字段比对：

| 组 | 覆盖 |
| --- | --- |
| A01 | `curveC` 与出厂常量（kappa/beta/eta） |
| A02/A03 | 幂律与指数两种曲线的 psi 网格（13 个点） |
| A04 | 可提取度 R（6 个 t） |
| A05 | 排程反解（6 个目标留存率） |
| A06/A07/A08 | 五种复习事件的 before/after、四档难度、储蓄效应（17 个用例） |

**过程中我自己写错了一次比较方式**：样例的期望值是生成器 `round6` 之后的数，我却拿未
round 的完整精度去比 `rel <= 1e-12`，于是差 5e-7 被误报为"实现不一致"。正确做法是
**先按同样规则 round6，再比容差**——样例的 `tolerances.note` 正是这么说的。

### 3. 数据统一：不引入第二份真相

`lib/domain/services/srs/dsr_card_state.dart` 是 `card_states` 行与模型状态之间的桥接。
关键决定：**一张卡只有一条记忆状态**。

`R0 / S / Σ / D` 恰好落在**已经存在**的四个列上（`encoding_strength` / `stability` /
`savings` / `difficulty`），所以接入认知模型**不需要新表、不需要新列、不需要迁移**。
两边读写的是同一行，因此**结构上不可能不同步**——这不是靠约定，是靠没有第二份数据。

两个载重决定写在这里，避免以后被"顺手改掉"：

- **没记录的 R0 读作 1.0，而不是 0.8**。FSRS 的曲线没有上限，`R0 = 1` 时两条曲线完全
  相同（已验证：`t = S` 时都精确给出 0.9）。把"没记录"读成 0.8 会让一个已经记得很牢的
  条目在模型眼里变成半生不熟。
- **`lapses` 不转换成模型的 `F`**。前者是终身计数，后者是**会衰减的证据**，从计数反推
  衰减历史等于编造数据。模型的失败证据从真实失败重新积累。

### 4. 抓到一个会静默失效的 bug（本轮最值得记的一条）

我原本把"没有复习记录"读作 `lastReview = 当前时间`，看着很合理。结果是 `dt` **永远是 0**、
`R` 永远是 1、稳定度增长永远是 1.0——**模型完全不工作，而且不报错**。

去读 JS 才发现真实语义：MindNet 的时钟是从纪元起算的小时数，而 `ensureState` 里
`lastReview: node.last_review_time || now` 的 `now` 默认 **0**。所以"没有复习记录"意味着
**从纪元开始就在遗忘**，不是"刚刚学过"。

更值得记的是：**我把这个 bug 写进了测试**——当时断言"没复习过的卡应该 R=1"，它通过了，
因为实现和断言犯的是同一个错误。**测试通过不等于行为正确**，当成对的错误出现在实现和
断言里时，绿灯毫无意义。发现后我把那条测试反过来钉住真实语义，并写清为什么反直觉。

### 5. 本轮实测结论

- `flutter test --concurrency=1` → **353/353 通过**（轮次九后 323，本轮 +30）
- `dart analyze lib test` → **0 error / 0 warning**
- 对拍：43/43 个 MindNet 公开值在 `rel <= 1e-12` 内（round6 后逐位相等）

### 6. 仍未做

- **tierB 快层**（状态机，约 400–600 行）：不急，且契约建议 tierA 稳了再上。
- **模型尚未接入复习流程本身**：现在是一套经过对拍验证、且能与现有数据互读的实现，
  但 `AnkiRepository` / 复习界面还没改成调用它。这是下一步，且需要先定"默认用 FSRS 还是
  模型"。
- **图投影（标签树 → 认知图）**：用途 1 的胶水，未开始。

---

## 2026-09-25 轮次九：AI 集成落地（schema v6 + agent loop + 对话界面）

设计见 [AI_DESIGN.md](AI_DESIGN.md)（20 条决策），skill 格式见
[SKILL_FORMAT.md](SKILL_FORMAT.md)。本轮实现的是 A1–A5 的**最小可用闭环**：
能对话、能审批、能改数据、主界面跟着变。

### 1. schema v5 → v6（一次迁移干三件事）

刻意合并成一次迁移，避免两次升级风险：

| 内容 | 明细 |
| --- | --- |
| AI 会话存储 | `ai_conversations` / `ai_messages` / `ai_actions` 三张新表 |
| AI 配置列 | `local_settings` 增 `ai_enabled` / `ai_api_key` / `ai_base_url` / `ai_model` / `ai_permission_mode` |
| 认知模型前置字段 | `card_states` 增 `encoding_strength`（MindNet `R0`）与 `savings`（`Σ`） |

第三项**不是 AI 功能**，是 MindNet 移植的前置缺口：Furnace 原先只持久化
`stability`/`difficulty`，而 MindNet 的曲线是 `R = R0·Ψ(t/S)`，缺 `R0` 时两边在
`R0 < 1` 会静默不一致（见 MINDNET_CONTRACT §8.3）。顺路补上，省一次迁移。

**真实库验证**（不是构造场景）：`%APPDATA%\FirsryFan\Furnace\furnace.db`
迁移前 `user_version=5`、26 表、9 行 → 迁移后 `user_version=6`、**31 表**、
`rows=9`，3 个时间块（早读/睡觉/午自习）一条没少。

`_tableFor` 同步登记了新表 —— 它是自愈路径（`_ensureColumns`）与 `.tfpkg`
转储的表名映射，漏登记会让自愈直接抛 `unknown table`。

### 2. 模型适配层（全应用唯一出网点）

- `ModelAdapter` 抽象 + `OpenAiCompatAdapter`（真实调用）+ `FakeModelAdapter`（测试）
- 协议按 OpenAI 兼容实现（DeepSeek 官方即此格式），换端点只改 base URL
- **不开 `strict` 模式**：它要求每个 object 的所有属性都必填，会逼着把参数改成
  `anyOf` 联合，反而更难懂。改为在 Dart 侧校验，并把错误作为工具结果回灌给模型
- SSE 重组抽成独立的 `StreamAssembler`（纯逻辑、无 socket），**23 项测试**专门
  盯着最容易静默出错的地方：分片 `arguments` 按 `index` 拼接、`id`/`name` 只在
  首片出现却被重复发送时不能拼接、无 `index` 时的退化处理、参数不是合法 JSON 时
  报错而不抛异常

### 3. 工具层（现有 Repository 的薄包装）

- `AiTool` / `ToolRisk` / `ToolArgs` / `ToolResult` 基类
- `query_tasks` / `manage_task`（6 个 action）/ `query_schedule` / `manage_time_block`
- **工具不写 SQL**，全部经 Repository：这样 AI 改了数据，Thread 页经 Riverpod
  自己就刷新了，不需要任何"通知界面刷新"的代码；业务规则也只有一份实现
- 工具按模块聚合而非按仓库方法铺开：60 多个仓库方法铺成工具会让模型在**选工具**
  这一步就开始犯错
- 只读工具返回摘要 + `total_matching` + `truncated`，默认 20 条上限（可调到 200），
  避免把整表塞进上下文

**写测试时抓到一个真 bug**：`restoreTask` 只恢复了 `depends_on`（它依赖谁），
漏了 `depended_on_by`（谁依赖它）。撤销一个被依赖的任务会静默丢掉"A 等 B"这条边。
已修并加了针对性测试。

### 4. 审批引擎（把用户的规则变成可测的裁决）

用户口径：**除删除外都可全自动**；删除永远逐条确认。据此把风险压成两级
（`write` / `destructive`），模式压成两档（`plan` / `auto`，默认 `auto`）。

我另加了一条用户没提但必要的约束（D13b）：**凡是撤不回来的操作也强制逐条确认**。
因为"敢让它全自动"的前提是"出事能撤回"，撤不回来的操作自动执行等于把这个前提
挖空。这条正好覆盖 skill 跑脚本（可能有外部副作用）。

`ApprovalEngine` 是纯函数（风险、可逆性、模式 → 裁决），**11 项测试**含两条
穷举：任何模式下 `destructive` 都不是 `executeNow`；只有 `auto` + `write` +
可逆才允许静默执行。

### 5. Agent loop

实现 AI_DESIGN §10 已定的约束：单 agent、轮次上限 8、工具结果只追加到末尾
（Chat Completion API 不允许中段插入工具调用）、**被拒绝的调用也要回灌给模型**
（否则它会反复提同样的请求）。

历史每轮从数据库重建而非留在内存：数据库是唯一真相，中途重启不丢，循环也不会
和用户看到的不一致。**24 项测试**覆盖：自动执行真的落库、按计划模式先攒后确认、
删除在 auto 模式下仍然停下、拒绝无副作用且告知模型、未知工具/坏参数/校验失败
都以工具结果回灌而非崩溃、达到轮次上限时**明确告知用户**而不是静默截断、
创建与更新的撤销都能真正回滚。

### 6. 界面

- 对话页：消息流 + 工具调用结果卡（带撤销）+ **审批清单卡**（本轮操作一次确认）
- AI 设置页：key / base URL / model / 权限模式，另列出本机可用工具与平台差异
- **导航门控**：`aiEnabledProvider` 为假时对话入口根本不存在 —— 实测无 key 时
  `ai_enabled=0`、三张表 0 行、应用行为与加这个功能之前完全一致
- 快捷键：Ctrl+0 跳设置（设置页索引会因 AI 页有无而位移，所以不能复用 Ctrl+1..4）

### 7. 本轮实测结论

- `flutter test --concurrency=1` → **308/308 通过**（轮次八结束时 196，本轮 +112）
- `dart analyze lib test` → **0 error / 0 warning**（54 info 全为既有风格项，
  `features/ai` 下 0 条）
- `flutter build windows --release` → 成功；启动后窗口标题 `Furnace`、
  工作集 267 MB、数据库 `user_version=6`、AI 仍未启用、3 个时间块完好

### 8. 本轮之后仍未做的

- **`.fskill` 执行容器**（A7）：格式已在 SKILL_FORMAT.md 定稿；**2026-10-02 更新**：安装/启用/删除已实现
  （`app/lib/data/skill/`，见 `SKILL_FORMAT.md` §7），**脚本执行容器本身仍未实现**。
  它需要先确定 skill 脚本的运行细节（超时/输出上限/不注入 API key/首次联网确认），且只在 Windows 上有意义。
- **真实 API 调用未实测**：需要用户提供 key。所有 provider 交互都经
  `FakeModelAdapter` 测过，但真机真实响应（尤其 SSE 分片的实际形状）尚未跑过。
- **Android 构建未重做**：Dart 层改动与平台无关，但本轮没重跑 Android 构建。
- MindNet tierA 移植：接口已协商完（MINDNET_CONTRACT §8），未开始写代码。

### 9. 界面层验证（同日补做）

前两轮分别验了"逻辑层（假模型）"和"协议层（真实 API）"，但都没**驱动真实控件**。
补了 `test/features/ai/ai_chat_ui_test.dart`：用**真实 `FurnaceApp`**（不是手搭
MaterialApp，否则本地化取不到会静默变成英文/崩溃）、**真实数据库**（内存库，配置从
真实库只读复制）、只替换模型适配器为脚本化的假模型 —— 这样不烧额度且可复现。

三项通过：

1. **完整聊天链路**：点 AI 标签 → 输入 → 发送 → **审批面板出现且此时库里没有任务**
   （证明 plan 模式确实拦住了）→ 点"全部执行" → 任务真的落库 → 通过 Repository 重读
   能看到它（即 Thread 页的数据源）。
2. **无 key 时 AI 标签根本不存在**（门控），且其余导航不受影响。
3. **填入 key 后标签立即出现、无需重启** —— 这条验证的是"写入路径有没有 invalidate
   读取路径"，漏了的话用户会以为保存失败。

**过程中一个值得记下的结论**：我一度断言"排序后 Thread 页应显示 AI 建的任务"，测试失败。
做了对照实验 —— **完全不经 AI、直接建任务再走同样的界面排序，任务同样不显示** ——
所以那是 Thread 页在 widget 测试环境下的既有行为，与 AI 功能无关。**我没有去改那个页面**，
而是把断言换成能证明集成成立的东西（AI 写的数据对同一 Repository 的新读取可见）。
留下这个记录是为了避免以后有人（包括我）再把它当成 AI 的 bug 重新查一遍。

---

## 2026-09-25 轮次九之后：真实 API 实测 —— 抓到一个会让对话永久报废的 bug

轮次九结束时我说"真实链路未实测"。用户提供 key 后我实测了，**发现了单测抓不到的
严重缺陷**，已修复并验证。

### 1. 怎么测的

两个真实的（非构造）验证：

1. **适配器探针**：直接用真实 DeepSeek 端点跑四件事 —— 错误 key 的报错文本、
   纯文本流式、工具调用分片重组、回灌工具结果后模型能否收尾。
2. **agent loop harness**：`app/live/agent_loop_live_test.dart`。它从真实数据库
   **只读**取 key，用**内存数据库**跑真实的 loop + 真实工具 + 真实审批 + 真实模型。
   必须显式设置 `FURNACE_LIVE_AI=1` 才运行，且放在 `test/` 之外 —— 它花钱，绝不能进 CI。

适配器探针结果（全部通过）：错误 key 得到
`401 ... Your api key: ****-000 is invalid` 加上我加的中文提示；
纯文本流式输出正确；**真实分片的工具调用被正确重组**
（`{"action": "create", "title": "真实接口测试"}` → 解析成功、`parseError=null`）；
回灌工具结果后模型正常收尾。**这一层原本风险最高，实测无问题。**

### 2. 抓到的 bug：`400 An assistant message with 'tool_calls' must be followed by tool messages`

真实链路第一步就炸了。原因：

我原本在**模型返回工具调用的那一刻**就把 assistant 消息（带 `tool_calls`）写进数据库，
而工具的回应要等用户批准才写。于是"待确认"期间的对话历史里存在
**有 tool_call 却没有回应**的悬空状态，provider 在**下一次请求**时直接 400。
后果不是"这一次失败"，而是**整个对话从此报废**。

为什么单测抓不到：单测里我的 `FakeModelAdapter` 不校验历史结构，而真实 provider 校验。
**这正是"用真实 API 测一次"不可替代的原因。**

### 3. 修复：把 turn 变成显式的原子单元

新增 `TurnGroup`：一轮模型输出若带工具调用，就把"assistant 消息 + 每个调用一条 tool
回应"作为一个**整体**，只有全部回应齐了才写库；未完成的一轮只存在于内存，`ai_actions`
台账仍然记录每一个提案（可审计）。

顺带修掉同一根因的**第二条路径**：`rejectPending` 原来会写 tool 回应却不写 assistant
消息 —— **孤儿 tool 消息**，同样被 provider 拒绝。这是我在写"数据库历史结构"断言时才
暴露出来的。

还加了一条防御：`sendUserMessage` 在有未决 turn 时直接返回，因为驱动新一轮会让上一轮
的调用永远得不到回应。UI 本来就禁用了输入，但这下不变量对所有调用者都成立。

### 4. 验证（两层，缺一不可）

**新增 5 项单测**，断言的不是"我重建出了什么"，而是**数据库里存的历史结构**必须满足
provider 的要求（每个 tool_call 有回应、每个 tool 回应属于已提交的 turn）。并用 git
临时回退代码确认新测试**确实会失败** —— 否则测试只是装饰。

**真实 API 重跑**（内存库）：

| 步骤 | 结果 |
| --- | --- |
| 只读查询 | 正确返回 2 个任务，无需批准 |
| 建任务 | `已创建任务「真实链路测试」`，库里 3 个 |
| **撤销** | 撤销后回到 2 个 —— 撤销真的生效 |
| **删除** | `individualApproval — 删除类操作永远逐条确认`，任务仍在 |
| 拒绝删除 | 任务数不变，回灌内容正确 |
| 每一步的历史结构 | **5/5 有效 ✔** |

全量回归：**313/313 通过**，`dart analyze lib test` 0 error / 0 warning。

### 5. 教训（写给以后的自己）

**假适配器测不出协议违规。** `FakeModelAdapter` 让 loop 的逻辑可测，但它对
provider 的约束一无所知。凡是"客户端生成的、会被服务端校验的结构"（消息顺序、
必填字段配对、tool_call 配对），都必须有**至少一次真实调用**或者一个**显式模拟
该约束的守卫**。我这次两个都补了。

---

## 2026-09-25 轮次八：全局改名 Furnace + 改名引发的数据丢失修复

### 1. 全局改名（KnowFlow → Threadflow → **Furnace**）

改名范围（每项都有实测证据，不是"应该改完了"）：

| 层 | 改动 | 验证 |
| --- | --- | --- |
| Dart 包名 | `pubspec.yaml` `name: knowflow` → `furnace`；39 个文件 `package:knowflow/` → `package:furnace/` | `dart analyze` 0 error |
| 类名 | `ThreadflowApp` / `ThreadflowDefaults` → `FurnaceApp` / `FurnaceDefaults`（10 文件）；`threadflow_defaults.dart` → `furnace_defaults.dart` | 同上 |
| 测试文件 | `threadflow_v2/v3_repository_test.dart` → `furnace_v2/v3_...` | 196 项全绿 |
| Android | `namespace` / `applicationId` → `com.furnace.app`；`MainActivity.kt` 迁到 `kotlin/com/furnace/app/`；manifest `android:label="Furnace"` | 三处一致（已核） |
| Windows | `windows/CMakeLists.txt` `project(furnace ...)`；`Runner.rc` 产品名/文件名/公司名 | release 构建产出 `furnace.exe` |
| 通知 | `appName: 'Furnace'`、AppUserModelId `com.furnace.app` | — |
| 文档 | 16 个 md；定稿 `THREADFLOW_SPEC.md` → **`FURNACE_SPEC.md`**，12 个文档里的 20 处引用同步更新 | 全仓扫描 0 残留 |
| 脚本/配置 | IDE 模块名、签名密钥 `furnace-release.jks`、Gradle 镜像 `furnace-google-cdn.gradle`、ASCII 构建路径 `E:\Document\furnace-build` | 3 个 ps1 语法 0 错误 |

保留的旧名（**故意不改**）：数据库文件回退链 `threadflow.db` / `knowflow.db`、`FURNACE_SPEC.md` 顶部的改名说明、`database.dart` 里记录历史名的那段注释。工作目录 `class-productivity/` 未改名。

### 2. 🔴 改名引发的**真实数据丢失风险**（本轮最重要的发现）

**触发链条**：`getApplicationSupportDirectory()` 的路径在 Windows 上来自 exe 的公司/产品元数据，在 Android 上来自 applicationId。改名把这两者都改了，于是：

```
旧：%APPDATA%\com.example\knowflow\threadflow.db      ← 真实数据在这里（9 行，含 3 个时间块）
新：%APPDATA%\FirsryFan\Furnace\furnace.db            ← 改名后新建，只有 4 行种子数据
```

原有代码只在**同一个目录内**回退文件名，覆盖不到"整个目录换了"的情况。实测证据：

- 用改名前的 exe 跑一次 → 新目录出现 4 行的 `furnace.db`，旧库 9 行**无人问津**；
- 两张库对比：`user_version=5` / 28 表都相同，差别只在 `time_blocks=3`、`thread_rank_settings=1`、`time_view_settings=1` —— 也就是用户真正录进去的日程。

**修复**（`database.dart` 新增 `_adoptLegacyDatabase` + `_firstLegacyDirectoryOutside`）：

- 先按老顺序找同名目录里的 `furnace.db` / `threadflow.db` / `knowflow.db`；
- 再找改名前的目录（`%APPDATA%\com.example\knowflow`、`%APPDATA%\FirsryFan\Furnace`、以及当前目录的兄弟 `knowflow/`）；
- 找到就**复制**到新路径（不是移动）：复制失败时退回继续用原文件，绝不因为 I/O 问题丢数据；
- 只有真的存在数据库文件（且非空）才算候选，空目录不会劫持全新安装。

**实测验证**（真机数据，非构造场景）：

1. 删掉新库 → 启动新 exe → 新库出现，SHA256 与旧库**完全一致**（`E5313D87CF004430...`）；
2. Dart 直接读该库：`rows=9`、3 个时间块（早读 / 睡觉 / 午自习）、2 个主题全部在；
3. 旧库哈希前后不变 —— 复制是只读的。

**回归测试**：新增 `test/data/database/legacy_database_adoption_test.dart`（6 项），覆盖同名旧文件、跨目录复制、原文件不被改、空目录不劫持、已有库优先。为了让路径可注入，加了 `resolveDatabaseFileForTest` 测试缝。

### 3. 本轮顺手修掉的真问题

- `bootstrap.ps1` / `build_windows.ps1` 头部注释符 `#` 与另一行注释被早前的批量替换**吃掉**，脚本直接语法错误 → 已补回，并用 `Parser::ParseFile` 复检 0 错误。
- `build_android.ps1` 缺 UTF-8 BOM，PowerShell 5.1 按 ANSI 解码导致中文注释吞掉引号 → 语法错误 9 个。补 BOM 后 0 错误（含中文的 .ps1 必须带 BOM）。
- `fsrs_scheduler.dart` 一处多余 `!`（warning）、`tfpkg_test.dart` 一处未使用变量（warning）→ 清零，`dart analyze` 现为 **0 error / 0 warning**（余 83 info 为 `prefer_const` 等风格项）。
- `DEPLOY.md` 写的 release 证书是 `CN=Furnace`，`keytool` 实测是 `CN=Threadflow, OU=Personal, O=Threadflow` → 按实测更正。
- `GAP_ANALYSIS.md` / `OPEN_QUESTIONS.md` 记的"`pubspec.name` 改为 `threadflow`"与最终代码不符（实际 `furnace`）→ 就地更正并注明中间名。
- `docs/README.md` 是全仓库唯一含 **114 处 U+FFFD 替换字符**的损坏文件（早前 GBK 误写所致），内容已被 `PROGRESS.md` 完全覆盖且无任何文档引用 → 删除；删后全仓扫描已无损坏文件。

### 4. 本轮实测结论

- `flutter test --concurrency=1` → **196/196 通过**；
- `dart analyze lib test` → **0 error / 0 warning**（83 info）；
- `flutter build windows --release`（经 `E:\Document\furnace-build` junction）→ 成功产出 `furnace.exe`，实际启动并完成上述数据库接管验证；
- 3 个构建脚本 `Parser::ParseFile` → 0 语法错误。

### 4.1 发版后补修：Windows 窗口标题仍显示 `knowflow`

v0.2.0 发布后实际启动程序读窗口标题，发现 **`MainWindowTitle = 'knowflow'`** ——
`app/windows/runner/main.cpp` 里有一处硬编码的 `window.Create(L"knowflow", ...)`。

**这是一个扫描漏洞**：先前的"全仓残留扫描"按扩展名白名单过滤，`.cpp` 不在其中，所以
这一处从头到尾没被扫到。教训：改名类任务的残留扫描不能只列扩展名，要按"排除构建产物"
做全类型扫描。改用全类型扫描后复查，`knowflow` / `threadflow` 只剩数据库中必须保留的
旧文件名、密钥别名，以及历史文档记录。

已修复为 `L"Furnace"` 并重新构建，**实测启动后窗口标题为 `Furnace`**，数据未受影响
（哈希仍为 `E5313D87CF004430…`）。版本号随之 0.2.0 → **0.2.1**，重新出包并发布。

### 5. 本轮之后仍未开始的两项新需求（用户 2026-09-25 提出）

这两项**没有开始实现**，因为需要先定方案；事实与待决策项已写入
[OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) 的 **Q3 / Q4** 两节：

- **Q3 AI 接入**：用 API 接 agent loop + skill + 工具（复刻 deepseek harness 的思路，
  但明确不要 cordis 扩展结构）。已核实：现有代码零 LLM/网络依赖，且"不联网"是当前
  产品的核心承诺 —— 动手前需要先定「AI 用来做什么 / 哪家 API / Key 怎么存 / 工具是否可写」。
- **Q4 MindNet 认知模型接入**（**只读，禁止写入该仓库**）：已只读核实 —— 它是零 npm
  依赖的 Node 包（`src/` 3712 行），同一份代码能在浏览器直接跑，但它**不是 Dart 包**，
  且 Android 上没有 Node 运行时，所以"直接调用"在手机端不可用；是否移植到 Dart、
  移植哪一部分、与已有的 `DiffusionBoost` 如何分工，都需要先定。

---

## 2026-09-19 轮次七：清理剩余问题 + v0.1.0 发版

### 1. 补齐批次 5 的两块（此前只有模型/库层，没接 UI）

**主题系统（spec §4）**

- 新增 `data/repositories/theme_repository.dart`：内置深浅主题的**幂等播种**、当前主题
  （存 `LocalSettings.active_theme_id`）、保存/导入/导出/删除。
  关键语义：**编辑内置主题会另存为副本**，出厂默认永不被就地覆盖；删除当前主题会自动回落到"跟随系统"，
  不会留下悬空引用；损坏的 payload 解析失败时回退内置深色而不是抛异常。
- 新增 `features/settings/application/appearance_providers.dart`：把"当前主题"解析为
  `ActiveAppearance`（主题文档 + 旧的 system/light/dark 回退），供 app 与设置页共用。
- 新增 `features/settings/presentation/appearance_section.dart`：外观区 —— 跟随系统 + 主题列表
  （色卡预览、编辑、导出、删除）+ 导入。
- 新增 `features/settings/presentation/theme_editor_page.dart`：明暗、主色、背景色与透明度、
  页面缩放 80%–150%、动画开关、字体族。
- `app/app.dart` 重写：`MaterialApp` 的主题由**主题文档**驱动，不再用硬编码的 `AppTheme`
  （该文件已删除）；页面缩放与动画开关在 `builder` 里对整棵树生效。

**`.tfpkg` 工作区打包（spec §3）**

- 新增 `features/settings/presentation/data_section.dart`：设置页「数据」区。
  - 导出：写入带时间戳的 `.tfpkg`。
  - 导入：先读 manifest 显示**预览**（多少行/多少表/多少主题）并让用户选**追加或覆盖**，
    然后**自动备份**当前工作区（`pre-import-<时间戳>.tfpkg`）再导入；完成后刷新相关 provider
    并报告写入行数、以及被跳过的未来版本表。
- 修正 `TfpkgService.importDump` 的覆盖语义：现在只清空**包内出现过的表**。
  原实现"覆盖=清空整库"，会把包里根本没带的表一起抹掉。

**顺带修掉的真 bug**

- 通知服务的 Windows 标识仍是 `Furnace` / `com.knowflow.app`，与产品名不一致 → 改为
  `Furnace` / `com.threadflow.app`，并换了一个不再像占位符的 GUID（附注：AppUserModelId
  必须跨版本稳定，改动会让 Windows 丢弃已排期的提醒）。

### 2. 剩余问题清单（本轮结束时的真实状态）

已完成：主题系统全链路、`.tfpkg` 导出/导入 UI、通知品牌、覆盖语义修正。
**仍未做**（已写入 `docs/DEPLOY.md` §5）：

- 字体**文件**导入（只能填字体族名称）；"正文/编辑器字体"与界面字体目前共用同一套字体族，
  要独立生效需在阅读视图再包一层 `DefaultTextStyle`。
- 日程块的拖拽移动/拉伸边缘改时长。
- 真机运行验证（用户有 Android 手机，待测）。

### 3. Windows release 在本工作区也需要 ASCII 路径（新发现）

`flutter build windows --release` **失败**，报错与 Android release 同源：
`Unable to read file ...\.dart_tool\flutter_build\<hash>\app.dill` → `MSB8066`。
debug 走 JIT 不受影响。解法同样是 junction：

```powershell
cmd /c mklink /J E:\threadflow-android "<真实路径>"
cd E:\threadflow-android; flutter build windows --release
```

已实测：Windows release 产物打包 **35.66 MB**，`knowflow.exe` 启动后窗口正常、占用 255 MB。

### 4. v0.1.0 产物（本轮实测）

| 产物 | 大小 | 验证 |
| --- | --- | --- |
| `dist/Furnace-0.1.0-android.apk` | 62.07 MB | `apksigner`：`CN=Furnace`；`aapt2`：包名 `com.furnace.app`、targetSdk 36、三套 `libsqlite3.so` |
| `dist/Furnace-0.1.0-windows-x64.zip` | 35.66 MB | 启动实测：进程存活、有窗口句柄、255 MB |
| 测试 | — | **190/190 全绿**（上一轮 172，本轮 +18 项主题仓库测试） |
| 静态检查 | — | `dart analyze` **0 error** |

---

## 2026-09-19 轮次六之二：源码已上传 GitHub（公开仓库 Furnace）

仓库：**https://github.com/FirsryFan/Furnace**（公开，MIT）

### 上传过程与最终状态

- 远端起始只有 `LICENSE` + `README.md`（1 个提交 `a397880`）。把它的 `.git` 接入本地工作目录以**保留历史**，
  然后分两次提交推送：
  - `620cc8e9` — `feat: Furnace 首个可运行版本（Windows + Android）`（179 个文件，1.84 MB）
  - `fdb0b212` — `chore: 固化行尾策略（.gitattributes）`
- 远端核对（GitHub API）：两个提交都在 `main` 上；公开 tree 共 **180 个 blob**、`truncated=false`。

### 忽略策略（两个关键取舍）

1. **`lib/data/database/database.g.dart` 故意提交** —— Drift 生成的 schema 代码。不提交的话，
   全新 clone 必须先跑 `build_runner` 才能编译；提交它也让 schema 变更在 diff 里可审。
   因此给 `app/.gitignore` 里的 `lib/**/*.g.dart` 加了 `!` 例外。
2. **构建产物全部排除** —— `app/build/` **1324 MB**、`app/windows/` **311 MB**（几乎全是
   `ephemeral/` 等 CMake 生成物）、`.dart_tool/` 284 MB。最终入库仅 **1.84 MB**。
3. `gradle-wrapper.jar` / `gradlew` 也保留入库（Flutter 模板默认排除），clone 后 `./gradlew`
   即可用，无需额外 bootstrap。

### 安全处理（**重要**）

用户在本轮中途把仓库从私有改为**公开**（实测 `private=False, visibility=public`）。签名密钥必须随之排除：

- 生成过 `app/android/threadflow-release.jks` 与 `key.properties`（开发口令）。
  **已确认没有任何提交包含它们**（`git log --all -- <jks>` 为空），并已加入 `.gitignore`，
  因此公开仓库的**全历史**里都没有密钥。
- 全历史审计（遍历所有提交的所有文件名，共 181 个）：无 `.jks`/`.keystore`/`key.properties`/
  `*.db`/`*.apk`/`*.aab`/口令类文件。
- `app/build.gradle.kts` 在 `key.properties` 缺失时**回退使用 debug 证书**，所以别人 clone 后
  `flutter build apk` 仍能出包（可装机自测，不适合分发）。keystore 保留在本地，
  **这台机器仍能产出正式签名包**。

### 行尾策略（新增 `.gitattributes`）

`core.autocrlf` 依赖机器设置，已经造成过一次 `LICENSE` 整文件假差异，并让 `gradlew.bat` 在索引里存成 LF。
现用 `.gitattributes` 明确规则，并用 `git ls-files --eol` 核对：`gradlew` 保持 LF
（否则 macOS/Linux 报 bad interpreter）、批处理/PowerShell 用 CRLF、二进制（jar/jks/图片/字体/apk/db）
不做转换、生成文件标记 `linguist-generated`。

### 文档

根 `README.md` 重写为仓库门面：模块表、当前状态与已知未完成项、目录结构、Windows/Android 构建命令、
**签名注意事项**、文档索引。构建 Android 前指向 `docs/DEPLOY.md`（其中记录了 6 个必须避开的坑）。

### 下一步

- 用户在 **Android 真机**上安装 `dist/Furnace-0.1.0-release.apk` 验证运行。
- 之后可做：主题与 `.tfpkg` 接入设置页 UI、字体导入、页面缩放、日程块拖拽。

---

## 2026-09-19 轮次六：Android 落地（从零装工具链 → 产出已签名 release APK）

> 用户要求：“把没有做的做完，尽早完成 Android 版本，这是我大部分的适用场景。”
> 结果：**release APK 已产出并用正式 keystore 签名**，`dist/Furnace-0.1.0-release.apk`（61.72 MB）。

### 1. 起点：这台机器完全没有 Android 工具链

`flutter doctor` 报 `✗ Unable to locate Android SDK`；`ANDROID_HOME` 为空、常见 SDK 路径都不存在、`java` 不在 PATH。
所以“Android 做不了”一直是**环境缺失**，不是代码问题。全部按**用户级、无管理员**方式装好：

| 组件 | 位置 | 方式 |
| --- | --- | --- |
| JDK 21 | `C:\Program Files\Microsoft\jdk-21.0.12.101-hotspot` | `winget install --id Microsoft.OpenJDK.21` |
| Android SDK | `C:\AndroidDev\sdk` | cmdline-tools 解包 + `sdkmanager` 装组件 |
| NDK 28.2.13676358 | `C:\AndroidDev\sdk\ndk\...`（2172 MB） | 腾讯镜像下载后**核对官方 size/sha1 一致** |
| Gradle 9.3.1-all（224MB） | `~\.gradle\wrapper\dists\...` | 腾讯镜像 + 核对官方 sha256 一致，手动放进 wrapper 缓存 |

用户级环境变量 `ANDROID_HOME` / `ANDROID_SDK_ROOT` / `JAVA_HOME` 已写入；`flutter config --android-sdk` 已设置。
`flutter doctor` 现在显示 `[✓] Android toolchain - Android SDK version 36.0.0`。

### 2. 踩到并解决的 6 个环境/依赖坑（每个都有明确报错）

1. **Gradle 发行包下载失败**：wrapper 的下载是纯 Java、无重试，先被连接超时打死，后又被
   GitHub CDN 的连接重置打断（下到 101MB 处）。→ 改从腾讯镜像取，**核对官方 sha256 完全一致**
   （`17f277867f6914d61b1aa02efab1ba7bb439ad652ca485cd8ca6842fccec6e43`），手动放入 wrapper 缓存并写 `.ok`。
2. **`maven.google.com` 不可达**：`dl.google.com` 的 CDN 路径可通但只有 ~60KB/s 并 `Read timed out`。
   实测同一 jar 传 8 秒：CDN 501KB vs **阿里云 12389KB**。→ 写 `google-cdn.init.gradle` 重写仓库 URL。
   - 第一版只钩 root build，**Flutter 插件的 included build 仍在慢源上超时**；改用
     `beforeSettings`（对每个 settings 生效）+ `gradle.beforeProject` + `allprojects` 三层覆盖。
   - 也不能靠 hosts：**无管理员权限，hosts 不可写**。
3. **AGP 拒绝非 ASCII 路径**：`Your project path contains non-ASCII characters` → `android.overridePathCheck=true`。
4. **Kotlin 增量缓存写失败**：`Could not close incremental caches ... class-fq-name-to-source.tab` → `kotlin.incremental=false`。
5. **`flutter_local_notifications` 要求 core library desugaring** → 打开 `isCoreLibraryDesugaringEnabled`
   并加 `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")`。
6. **插件 compileSdk 冲突**：`file_picker` 8.3.7 硬编码 `compileSdk 34`，而
   `flutter_plugin_android_lifecycle` 要求消费方编译到 36 → 构建失败。
   - 我先试了三种 Gradle 钩子（`subprojects{afterEvaluate}`、`gradle.projectsEvaluated`、`beforeEvaluate`），
     分别报 “Cannot run Project.afterEvaluate when the project is already evaluated” 和
     “It is too late to set compileSdk / It has already been read”。**这是在猜生命周期，不对。**
   - 最终用**干净解法**：把 `file_picker` 升到 **12.3.0**。升级后 `flutter_plugin_android_lifecycle`
     不再在依赖树里，冲突根源消失；同时按 12.x 新 API 改了 3 处调用
     （静态 `FilePicker.pickFiles/saveFile`、`saveFile` 需要 bytes 且返回 `Uri?`、
     `PlatformFile.bytes` → `await readAsBytes()`）。

### 3. 最后一个坑：release 的 AOT 编译要求 ASCII 路径

debug 能构建（JIT），release 失败：
`Error: Unable to read file ...\flutter_build\<hash>\app.dill` → `Target android_aot_release_android-arm64 failed`。
根因同样是路径里的 `一THREADRIPPER一`（Flutter→Gradle 传参被 ANSI 破坏）。
→ 用**目录 junction** 造一条纯 ASCII 路径（无需管理员）：
`mklink /J E:\threadflow-android <真实 app 路径>`，再从该路径构建。已固化进 `scripts/build_android.ps1`。

### 4. 交付验证（全部是对真实产物的读取，不是推测）

- `flutter build apk --debug` → **成功**，`app-debug.apk` 161.72 MB。
- `flutter build apk --release` → **成功**，`app-release.apk` 61.72 MB。
- `aapt2 dump badging`：包名 `com.furnace.app`、versionName 0.1.0、
  应用名 **Furnace**、`compileSdkVersion='36'`、`targetSdkVersion:'36'`、
  `native-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'`。
- 权限：`POST_NOTIFICATIONS`、`RECEIVE_BOOT_COMPLETED`、`VIBRATE`（+ 插件自带的一条）。
- APK 内 `lib/{arm64-v8a,armeabi-v7a,x86_64}/libsqlite3.so` **三套齐全**。
- `apksigner verify --print-certs`：`CN=Furnace, OU=Personal, O=Furnace, C=CN`
  （不再是 `CN=Android Debug`）→ 已生成 `android/threadflow-release.jks` 并接线（缺 keystore 时回退 debug，
  保证全新 clone 也能构建）。
- `flutter test --concurrency=1` → **172/172 全绿**；`dart analyze` → **0 error**。
- 产物已放到 `dist/`：`Furnace-0.1.0-release.apk` + `dist/windows/`（Windows debug 运行目录 19 个文件）。

### 5. 未验证 / 待你处理

- **没有真机或模拟器**（`adb devices` 为空），所以**未在任何 Android 设备上安装运行过**——
  能构建、能签名、清单与 native 库正确，但**实际运行效果未经确认**。
- 正式 keystore 的口令是开发用值并明文放在 `android/key.properties`（已在 `.gitignore` 内）。
  **对外发布前请重新生成并妥善保管**：换 keystore 会导致已安装用户无法覆盖升级。
- 仍属批次 5 未做的部分：主题 JSON 的**接入**（模型与测试已完成，见下）、字体导入、页面缩放。
  `.tfpkg` 编解码与服务层已完成并有 8 项测试，但**尚未接入设置页 UI**。
- 界面仍未经肉眼检阅。

### 6. 本轮顺带完成（批次 5 的两块，纯代码 + 测试）

- `core/theme/theme_profile.dart`：主题 JSON 文档模型（颜色/背景/透明度/背景图/字体/缩放 0.8–1.5/动画开关、
  内置深浅主题、宽容解析、`toThemeData()`），14 项测试。
- `data/package/tfpkg_codec.dart` + `data/package/tfpkg_service.dart`：`.tfpkg` 全量逻辑转储
  （**通用遍历 sqlite_master 导出所有用户表**，不为 28 张表手写序列化；BLOB 用 base64 标记往返；
  附件与主题随包；覆盖/追加两种合并；未知表与未知列容错），8 项测试。
- 修掉一个真 bug：设置页“备份数据”读的是 `knowflow.db`，而实际库是 `threadflow.db`
  ——旧写法在全新安装上永远报 not found。

---

## 2026-09-08 轮次五：日视图不按小时分 + 日视图宽度（用户 2 条）

### 1. 不要默认按小时来分（schema 4 → 5）

- **默认行高 60 → 30 分钟**：`TimeViewSettings.minutesPerRow` 默认改为 30，`_CalendarPageState._minutesPerRow` 同步改 30。
- **次小时行**：新增 `rowLabel(row, minutesPerRow)`（显示真实时间 `HH:MM`）与 `isMajorTick`（整点画重分隔线，次小时画淡线且不写字）。日视图与周视图都改用这两个函数。
- **记录“用户自己选过”**：新增列 `minutes_per_row_chosen`。`_setMinutesPerRow` 在选择时写 `chosen: true`，以后再改默认值也不会覆盖用户刻意的选择。
- 迁移 `_upgradeV4ToV5`：给缺列的表补上该列，然后把 `chosen = 0` 的行从旧的 60 改成 30（刻意选过 60/15 的保持不动）。

### 2. 日视图要有宽度

- `_DayGrid` 改用 `LayoutBuilder` 约束宽度：**最小 340、最大 760**，宽屏居中而不是拉满，窄屏横向滚动而不是压扁。
- 周视图同样加下限 **560**：不足时横向滚动，7 列不再被挤成细条。

### 3. 踩到并修掉一个真实的“版本号撒谎”问题

- **现象**：实测真实库 `user_version = 5`，但 `time_view_settings` **没有** `minutes_per_row_chosen` 列。
- **根因**：Drift 只在 `user_version < schemaVersion` 时才跑 `onUpgrade`。这份开发库在前一版（迁移实现有缺陷时）就被打上了 5，于是修复版的迁移**永远不会执行**；而 Drift 生成的 mapper 对该列做非空读取 → 读到该表就抛异常。这是**真实存在的潜在崩溃**，不是测试造假。
- **修法（两层）**：
  1. `_upgradeV4ToV5` 先补列、再改值；
  2. `beforeOpen` 新增 `_ensureColumns()` **自愈**：每次打开都按当前 schema 探测并补齐缺失列（`tasks.started_at`、`completion_logs` 三列、`time_view_settings.minutes_per_row_chosen`）。健康库在这里什么都不做。
- 同时补上 `_tableFor` 的 switch（原先只认 tasks / completion_logs，补列时报 `unknown table time_view_settings`）。
- **开发库处理**：那份被跳过迁移的旧库备份为 `threadflow-v4-stale-*.db.bak`，并重建干净的 v5 库（28 表）。自愈只补列、不重解释旧值，所以旧库里的 60 不会自动变 30——重置是为了让新默认值真正生效。

### 4. 我自己造过一个不真实的测试场景

- 我一度写下“v4 库没有 `minutes_per_row_chosen` 列”的测试并断言迁移会补列，但它失败在 Drift mapper 上。
- 事实是：v3→v4 用**当时的 schema** 建表，v4 发布版的表**本来就带这一列**（只是值恒为 60）。真正缺列的来源是第 3 条那种“版本号撒谎”的库。已改为两个真实场景：① 表带列但值 60 → 迁移改 30；② 版本号谎报 5、表缺列 → `beforeOpen` 自愈。

### 5. 本轮验证（实测）

- `flutter test -r expanded --concurrency=1` → **150/150 全绿**（上一轮 138，本轮 +12）。
- `dart analyze` → **0 error**。
- `flutter build windows --debug` → **成功**；启动实测进程存活、有窗口句柄。
- **真实库实测**：自愈前 `cols` 缺 `minutes_per_row_chosen`；启动一次后该列出现（值 0）→ **自愈在真实文件上生效**。随后重置开发库，新库 `user_version=5`、28 表。

---

## 2026-09-08 轮次四：反馈(3) 日历/时间轴重构完成 + 反馈(2) 收尾

> 本轮按默认值推进了两处此前的歧义（用户未答复）：月视图主交互＝**点选该日 + 下方详情面板**（双击进日视图）；周序号＝**全年连续 ISO 周号**，不做逐月重置。

### 1. 数据层：schema 3 → 4（纯加表，幂等迁移）

- `TimeTemplates`（`time_templates`）：日/周模板。`payload` 为 JSON 的 `{blocks:[...]}`，每个块含 `title/start/end/available/repeatRule/dows/monthDay/color`；`start`/`end` 是**从本地午夜起的分钟数**（与时区无关）。
- `TimeViewSettings`（`time_view_settings`，单行）：`timelineSpanDays`(默认 730)、`timelinePxPerDay`(6)、`timelineCollapsed`(false)、`minutesPerRow`(60)。
- 迁移 `_upgradeV3ToV4` 用存在性探测保证 v1→v4 / v2→v4 / v3→v4 三条路径都不重复建表（沿用上一轮的幂等做法）。
- 新仓库：`TimeTemplateRepository`（含 `applyToDays` 物化、`blocksOf` 解析）、`TimeViewRepository`；已装配进 `repository_providers`。
- 新测试：`v4_migration_test`（真实 v3 库文件就地升级）、`time_template_repository_test`（9 项）、`calendar_support_test`（8 项）。

### 2. 日历重写（`features/timeboard/presentation/calendar_page.dart`）

四种视图：**日 / 周 / 月 / 时间轴**。

- **多年时间轴**：跨度 30–3650 天（滑条，用户自定义）、缩放（1–40 px/天，缩放按钮）、**折叠开关**——不折叠＝单条横向滚动，折叠＝按窗口宽度自动分行、纵向滚动。左侧显示该行起始年月，每月 1 日画主干线；块按真实起止时间定位（同一天内的块在时间轴上按分钟比例摆放）。
- **周视图**：左侧 **ISO 周号列**（`W38`）；表头整行与每个日列都能右键/长按出菜单；右侧 7 列时间网格。
- **月视图**：每行左侧 **ISO 周号**；每个格子显示该日的彩色块卡片（最多 3 个 + `+N`）；**单击选中该日**，下方**详情面板**显示该日全部日程块的起止时间并可编辑/删除，面板顶栏有「新建 / 进日视图 / 进周视图」三个 icon 按钮；双击格子直接进日视图；右键/长按弹菜单。
- **右键菜单**（桌面右键、触屏长按，同一套）：日格 → 新建块 / 套用模板 / 打开日视图 / 打开周视图；周行 → 打开周视图 / 套用日模板 / 套用周模板 / 新建块。
- **日程块**：起止时间**任意到分钟**（时间选择器 + ±5 分钟微调），**不做重叠避让**；显示为**半透明彩色卡片**（8 色稳定配色 + 按 id 哈希，忙碌块更不透明、开放块更淡），忙碌/开放语义（D6）靠透明度继续可见。
- **模板**：`showTemplatesSheet` 支持「日/周」范围切换、列出模板（显示块数）、一键套用到目标日或整周、删除模板，以及**把当前周/日保存为模板**（从日历里已有的块反向生成）。

### 3. 反馈(2) 收尾：右键菜单 + 全局快捷键

- **标签树**：三点菜单保留为触屏兜底，但**整行右键/长按**现在直接弹上下文菜单（新建子标签/重命名/删除，带图标）；单击有子节点的行＝展开/折叠。
- **全局快捷键**（`home_shell.dart`，`Shortcuts` + `Actions`）：`Ctrl+R` 重新排序（若不在 Thread 页会先切过去）、`Ctrl+1..4` 跳转前四个模块。
- 各输入框 `Enter` 提交（上一轮已做，本轮补到日历建块/编辑与模板命名）。

### 4. 踩坑记录

- **`IsoWeek.number` 差一位**：我最初写 `(diff ~/ 7) + 2`，测试实测 2026-01-01 得到第 2 周（应为第 1 周）。根因是把“距第一个周四的周数”与“周号”差了个 1（第一个周四本身就在第 1 周）。改为 `+ 1` 后 8 项 ISO 测试全过。**这是该算法最经典的 off-by-one，测试直接抓到了。**
- 我为了消一个 “unused import” 警告删掉了 `time_template_repository.dart` 的 import，结果 `TemplateBlock` 变成未定义类型——**analyze 的警告不能盲从，要看它是否真的未被使用**。

### 5. 本轮验证（实测）

- `flutter test -r expanded --concurrency=1` → **138/138 全绿**（上一轮 120，本轮 +18）。
- `dart analyze` → **0 error**（1 warning、其余 info）。
- `flutter build windows --debug` → **成功**；启动实测 12 秒后进程存活、窗口句柄 `hwnd=1508716`、内存 444MB。
- **真实库升级实测**：直接读 `%APPDATA%\com.example\knowflow\threadflow.db` → `user_version = 4`、**28 张表**、`time_templates` 与 `time_view_settings` 均存在。
- ⚠️ 仍未做：界面肉眼检阅（无法截图）、Android、批次 5（主题/.tfpkg）。**块尚未支持拖拽移动/拉伸边缘改时长**（改时间目前走对话框）。

---

## 2026-09-08 轮次三：用户 4 条反馈（1、2、4 完成；3 未动）

> 用户反馈要点：(1) 排序参数说明集中到 设置→使用文档；(2) 交互细节需打磨，例：标签加子标签不该用三点菜单，要用 Enter 等快捷键，并要求我主动发现更多问题；(3) 新增多年时间轴视图 + 月/周/日联动 + 周模板日模板 + 块随意起止不避重叠 + 透明彩色卡片 + 右键菜单；(4) Thread 事件不能删除、状态色用错了、权重计算有问题。

### 1. 反馈(1) 完成：参数说明集中

- 新增 `features/settings/presentation/usage_doc_page.dart`：总分公式、五个分量的现实意义、**当前权重 vs 出厂值对照表**、事件条四色含义。
- 设置页新增「使用文档」入口；属性页与权重对话框各加 help 图标直达该页。
- 属性页**移除全部内联小字说明**，只保留参数名与实时数值——按用户要求统一放到使用文档。

### 2. 反馈(4) 完成：删除、状态色条、权重修正

- **事件删除**：左滑（Dismissible + 二次确认）+ 三点菜单里的删除项；已归档条目同样支持。此前确实**没有任何删除入口**。
- **状态色条**：新增 `features/thread/presentation/widgets/thread_status_edge.dart`，事件条左边缘 5px 圆角色条：
  绿＝已完成 / 蓝＝等待中 / 黄＝已过期期望时刻 / 红＝已过截止时刻；**截止优先于期望**（两者都过 → 红）。
- **权重计算修正**（两个实测缺陷）：
  1. 五个权重相加 = **1.05**（`wExpected=0.05` 是加在定稿四权重之上的），总分被放大 5% 且可能 >1 → 新增 `RankWeights.sum` / `normalized()`，排序器统一用归一化权重，总分恒定 [0,1]。
  2. 缺失值被当成“半匹配”：精力未设置时 `energyFit=0.5`、无预估用时时 `windowFit=0.5`，各自把分数压低一截 → 改为返回 `null`（`RankScore.energyFit/windowFit` 现可空），`fit` 只对有数据的分量取平均，两边都无数据才用中性值。
  - 取证：写临时 `dart run` 探针打印权重与分量实测值（探针已删）。新测试：「total cannot exceed 1」「缺失值不再算半匹配」。

### 3. 反馈(2) 部分完成：交互打磨 + 一个会丢数据的真 bug

- **修复 ID 撞车（严重）**：8 个仓库的 ID 生成器都是
  `'$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'`，
  **同一微秒内连续插入生成重复主键** → `UNIQUE constraint failed: time_blocks.id / diffusion_logs.id`。
  - 影响场景：示例数据装载、批量导入、任何紧凑循环插入。
  - 修复：新增 `data/ids.dart`（`Ids.next(prefix)` / `Ids.uuid()`，uuid v4），8 个仓库全部改用；新增 `test/data/ids_test.dart`（5000 次连续生成必须唯一）。
  - **发现路径值得记住**：全量测试串行跑报出两处 UNIQUE 冲突，而单独跑同一文件却通过——「单独过、全量崩」正是共享状态或时间随机性的信号。
- **Enter 提交**：标签树（新建/重命名）、新建事件、属性页预估用时补 `onSubmitted`，此前按 Enter 无反应。

### 4. 反馈(3) 未完成：日历/时间轴重构（下一轮主体）

动手前需明确两处交互歧义（**已向用户提问，未答复前不擅自定案**）：

- 月视图单元格的**主交互**：点一下选中该日（旁边出详情面板做增删改）还是弹层打开当日详情？
- 周序号列的**呈现**：每月内独立编号（第 1..5 周）还是全年连续 ISO 周号（第 1..53 周）？

已确定要做：多年可定义长度时间轴（缩放 + 折叠：不折叠左右滚动 / 折叠则上下滚动）、月视图选中整周或某日切换周/日视图、周模板与日模板一键套用、日程块起止任意（不避重叠）、块改半透明彩色卡片、日/周视图右键菜单 + 左侧周序号。

### 5. 本轮验证（实测）

- `flutter test -r expanded --concurrency=1` → **120/120 全绿**（上一轮 116，新增 3 项 ID 唯一性 + 1 项权重归一化）。
- `dart analyze` → **0 error**（1 条 warning、其余 info 级）。
- `flutter build windows --debug` → **成功**；启动实测 12 秒后进程存活且有窗口句柄（`hwnd=1376420`）。
- ⚠️ 仍未做：界面肉眼检阅（无法截图）、Android、批次 5（主题/.tfpkg）。

---

## 2026-09-08 轮次二：图形界面全部落地 + 真机可运行（Windows）

> 用户要求：“把图形化界面也落地，我直接检阅 flutter 的完整软件成果”。
> 本轮把蓝图 v2 里除批次 5（主题/.tfpkg）外的界面全部做完并接线。

### 1. 新界面（全部新增文件，未覆盖旧实现）

| 模块 | 文件 | 内容 |
| --- | --- | --- |
| Thread | `features/thread/presentation/thread_page.dart` | 事件流 + 已归档 两个并列视图；新建事件可设精力 |
| Thread | `.../event_properties_page.dart` | **属性页**：每个参数一张卡、卡底一行“现实意义”小字；算法区展示 5 个分量的 值×权重=贡献；权重可编辑、可一键恢复默认 |
| Thread | `.../widgets/energy_bar.dart` | 红→绿渐变数字条按钮；点开是带节点滑条 + 现实语义小字 |
| Thread | `.../widgets/thread_status_bar.dart` | 可折叠顶栏；目标只显示标题、点击进完整编辑；过期确认后立即排序 |
| Knowledge | `features/anki/presentation/knowledge_page.dart` | 模块外壳：复习 / 管理 两个 tab |
| Knowledge | `.../review_page.dart` | 心流复习页：一题一个空、提交判分、三键评分 + 生成任务；顶部显示剩余张数与待清数 |
| Knowledge | `.../knowledge_insight_page.dart` | **独立复盘页**：按天显示“答错的 / 被提权的相关词条（距离 + 倍数）” |
| Knowledge | `features/anki/application/review_service.dart` | 复习引擎：自由挖空抽卡、FSRS 调度、错题 active 绑定、标签树扩散、按天台账、Knowledge→Thread 生成事件 |
| Time | `features/timeboard/presentation/calendar_page.dart` | 日/周/月三视图；**纵轴缩放 15/30/60 分钟每格**；忙碌块实心、开放块描边；点空白建块、点块改块 |
| Time | `.../time_page.dart` | Time 模块外壳：日历 / 日程块列表 两个 tab |
| 标签 | `features/tags/presentation/tag_tree_page.dart` | **Mindnet 并入标签**后的树形编辑：递归树、展开折叠、建子标签、改名、删除、面包屑显示完整路径 |

导航壳改为：标签 / Thread / Time / Knowledge / 知识库 / 设置（Mindnet 页不再挂在导航上，数据与代码保留）。

### 2. 关键语义修正（本轮发现问题，均已修 + 有测试）

1. **图谱扩散的“图”换成标签树**：Mindnet 取消后，`DiffusionBoost` 的节点图已不存在。新增 `domain/services/cloze/tag_diffusion.dart`，用标签路径树算距离，**保持定稿语义**：距离 1＝父子/兄弟 → ×1.8；距离 2＝隔代 → ×1.3；表兄弟（同祖父、各两层）实测为 4，不触发提权。
   - ⚠️ 过程记录：我第一次把“堂表兄弟”断言成距离 2，**实测打印距离矩阵**后发现是实现正确、断言错误——改的是测试不是实现。
2. **未复习过的新词条曾整条排不进队列**：`buildQueue` 只在“已存在 card_state”时才产出题目，新词条永远不出现。已修：无状态即视为到期，真正需要时才创建单元状态（不再产生空 `unit_key` 占位状态）。
3. **事务嵌套**：`DiffusionLogRepository.appendAll` 在事务里又调用带事务的 `append`，Drift 不允许。已拆成 `_append`（调用方持有事务）。
4. **`upsertBoost` 支持指定剩余周期**（抽卡时消耗一次 boost）；`addClozeHistory` 的 `correct` 参数与表结构（INTEGER）对齐。

### 3. 本地化

- 中英 ARB 各新增约 90 条。
- ⚠️ **重大踩坑**：我用 PowerShell 的 `Get-Content/Set-Content` 批量改 ARB 占位符类型，导致**中文被 GBK 往返写成乱码**（`"鏃?"`），`gen-l10n` 报 “value is not a string”。
  - 这正是本文件 2026-09-07 轮次已记录的教训，本轮**自己违反了**。
  - 补救：用 `write` 工具整份重建两个 ARB；并把 `calendarWeekdays` 数组拆成 `calendarWeekday1..7`（ARB 不支持数组值）。
  - **规则强化：含中文的文件只用 read/write/edit 工具改，永不走 PowerShell 文本往返。**

### 4. 验证（本轮实测）

- `flutter test` → **116/116 全绿**（上一轮 105，本轮新增 1 项复习引擎 + 10 项复习引擎/扩散测试）。
- `dart analyze` → **0 error**（68 条 info/warning 级）。
- `flutter build windows --debug` → **成功**，产物 `app/build/windows/x64/runner/Debug/knowflow.exe`。
- **启动实测**：`Start-Process` 后 12 秒进程仍存活、有真实窗口句柄（`MainWindowHandle=1901812`）、内存约 434MB → **不闪退**。
- **建库实测**（用 `sqlite3` Dart 包直接读真实库文件）：`threadflow.db` 的 `user_version = 3`、**26 张表**，`completion_logs` 12 列（含 `actual_minutes` / `include_in_model` / `duration_suspicious`）、`tasks` 含 `started_at` → 当前代码的全新建库路径正确。
  - 附带发现并清理：`%APPDATA%\com.example\knowflow\knowflow.db`（**v2 时代的遗留文件**，`user_version=2`、18 表、缺 `completion_logs`）是一次非原子中断留下的残骸。
  - ⚠️ 注意：app 优先使用 `threadflow.db`，仅当它不存在且 `knowflow.db` 存在时才回退到后者。因此这份残骸从未被当前 app 使用，已删除。

### 4.1 运行方式（Windows）

```powershell
cd "E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity\app"
flutter run -d windows        # 开发调试（支持热重载）
# 或直接用已构建产物（免编译）：
.\build\windows\x64\runner\Debug\knowflow.exe
```

首次打开是**空工作区**。建议顺序：**设置 → 载入示例数据**（会生成 8 个标签、4 个词条、6 个事件、3 个日程块，并预置精力 7 / 目标“数学”），然后按 **Thread → Time → Knowledge → 标签** 依次查看。
数据库位置：`%APPDATA%\com.example\knowflow\threadflow.db`。

### 5. 未完成 / 未验证

- **批次 5 未做**：主题 JSON 与外观系统、`.tfpkg` 全量打包、字体导入、缩放 0.8–1.5。
- **`.kpak` 词条级 Markdown/JSON 导入导出**未做。
- **标签拖拽改层级**未做（当前靠“新建子标签”建层级；改名/删除已有）。
- **Android 未做**：`app/android` 目录不存在，需 `flutter create --platforms=android .`；`flutter doctor` 显示 Android toolchain ✗。
- **Time 冲突弹窗与“只挪期望时刻”一键调整**未接入 UI（`TimeWindowEngine.isBusyAt` 已具备）。
- 界面**未经肉眼检阅**：本会话只能确认“能编译、能启动、进程存活、有窗口”，**布局与交互手感需用户实机确认**。

---

## 2026-09-08 轮次：R3 核心算法结案 + 第一批次 Thread UI（蓝图 v2 落地）

> 依据：`docs/DESIGN_BLUEPRINT.md` v2（用户 13 条批注修订版）。用户选择：主力平台 Windows + Android 手机版；优先模块 Thread；构思先讨论再直接写 Flutter。

### 0. 先纠正上一轮记录的失真（重要）

上一轮（2026-09-07）本文写“R3 未开始”、`FEATURE_MATRIX.md` 把 ThreadRanker/FSRS/自由挖空/图谱扩散全标 🔴——**与代码实际不符**。本轮实测：

- 这些算法**早已写入代码**（`thread_ranker.dart`、`time_window_engine.dart`、`fsrs_scheduler.dart`(FSRS-6)、`cloze_engine.dart`+`ForcedMachine`、`diffusion_boost.dart`）。
- 本轮开工前基线：`flutter test` **78/78 全绿**。
- 教训：文档的“未实现”标记必须与源码核对后再写。

### 1. 本轮环境结论（实测）

- `flutter pub outdated` 成功 → **pub.dev 可达**（V1 结案）：`flutter_quill`/`cryptography`/`table_calendar` 等可选型，不必全手写。
- `app/android` **不存在**（`Test-Path` = False）→ 打安卓包前需先 `flutter create --platforms=android .`（V3 结案）。
- `dart test` **不可用**（未依赖 `package:test`），一律用 `flutter test`。
- 项目目录**不是 git 仓库**，无版本历史可回滚。

### 2. 算法层：按用户 13 条批注改写 `ThreadRanker`

- **deadline 与 expected_time 解耦**（用户 16）：红标（`insufficient`）**只看 deadline**；`deadline < now` 单独进 `overdue` 桶；`expected_time` 临近/已过只产生**黄标 + `expectedPressure` 提权**，永不触发红标。
- **新增可调权重** `RankWeights`（urgency/goal/fit/fatigue/**expected**），可被 UI 编辑；新增 `RankScore.expectedPressure/energyFit/windowFit` 与各分量**贡献值**，供属性页展示。
- **目标匹配简化**（用户 7）：只用自由文本关键词命中（节点分支保留但不再使用）。
- **黄标窗口** `expectedNearWindowMinutes = 120`：窗口内渐升，过点仍饱和，之后按 `expectedSoftHalfLifeMinutes` 衰减回 0。
- 新增 `domain/services/time/actual_time.dart`（用户 14）：**不跑计时器**，实际用时＝完成时刻−开始时刻；默认异常规则 `actual > estimate×3 且 actual > 30min` → 默认不计入模型，可逐条改。
- 测试：`thread_ranker_test` 扩到 21 项、新增 `actual_time_test` 9 项。

### 3. 数据层：Drift schema **2 → 3**（纯增量，幂等迁移）

- `Tasks.started_at`；`CompletionLogs.actual_minutes / include_in_model / duration_suspicious`。
- 新表 `ThreadRankSettings`（单行：5 个权重 + 顶栏折叠 + 实际用时总开关）、`DiffusionLogs`（按天留痕，供独立复盘界面，用户 19）。
- 新仓库 `ThreadRankRepository`、`DiffusionLogRepository`，并在 `repository_providers` 装配。
- `TaskRepository`：新增 `startTask` / `setCompletionInModel` / `getModelCompletionLogs` / `getDurationCalibration`；`completeTask` 改为计算并落盘实际用时。
- ⚠️ **踩坑记录**：`Migrator.createTable` 永远按**当前** schema 建表，所以 v1→v2 路径建出的 `completion_logs` 已含 v3 列，v2→v3 再 `addColumn` 会 `duplicate column name`。修法：`_upgradeV2ToV3` 全部改为**先探测再改**（`_tableExists` / `_columnExists`），使迁移幂等。
- 新测试 `v3_migration_test`、`threadflow_v3_repository_test`。

### 4. UI 层：Thread 第一批次（用户 1–13 条）

- `features/thread/` 新模块：`thread_rank_service.dart`（组装排序）、`thread_page.dart`（**事件流 / 已归档 两个并列视图**，用户 5+11）、`event_properties_page.dart`（**属性页**，用户 6+13）、`widgets/energy_colors.dart`、`widgets/energy_bar.dart`、`widgets/thread_status_bar.dart`。
- 顶栏（用户 2/3/8）：**可折叠**、目标只给标题+🎯 按钮进详情、精力是**红→绿渐变的数字条按钮**（只显示数字，无 `/10`），点开是**带节点的水平滑条 + 现实语义小字**；排序是 **icon 按钮**。
- 属性页（用户 6/13）：**所有参数可编辑，每个参数卡底部都有解释现实意义的小字**；含**算法区分量拆解**（紧急度/目标匹配/状态适配/期望压力/疲劳惩罚，各自 值×权重=贡献）与**权重编辑对话框**（全局生效，可一键恢复默认）。列表本身**不显示任何理由**（不做 L1）。
- 导航：`tasks` 页在 Thread 模块替换为 `ThreadPage`，新增导航词条 `navThread`。
- 本地化：新增 ~50 条中英词条，`flutter gen-l10n` 重生成。

### 5. 验证结果（本轮实测）

- `flutter test` → **105/105 全绿**（基线 78 + 本轮新增 27）。
- `dart analyze` → **0 error**（65 条 info/warning 级，含既有 `withOpacity` 弃用、`await_only_futures` 等历史项）。
- ⚠️ **未验证**：UI 没有在真实窗口跑过（本会话没有执行 `flutter run`），所以**布局与手感未经肉眼确认**；Windows/Android 构建也**未实测**。

### 6. 下一步

1. 用户确认蓝图中剩余 5 条待定（Q2.1 归档是否拆两个界面、Q2.4 权重是否事件级、Q2.7 新增事件是否标“未参与排序”、Q4.1 active 插入间隔、Q4.2 复盘是否要历史趋势）。
2. 批次 1 收尾：Thread 事件卡片补标签末级展示、开始/完成按钮与"未参与排序"标记；跑一次 `flutter run` 做双端手感确认。
3. 批次 2：Time 日历（日/周/月 + 纵轴缩放 15/30/60）+ 冲突只挪 `expected_at`。
4. 批次 3：Knowledge 新复习流（FSRS + 自由挖空 + active 当日队列集中重现 + 严格逐字符判分）+ 图谱扩散独立复盘界面（用 `DiffusionLogs`）。
5. 批次 4：标签体系合并 Mindnet + OPML/.mm 导入导出。
6. 批次 5：主题系统 + `.tfpkg` + 字体/缩放 + `flutter create --platforms=android .` 后做安卓构建冒烟。

---

## 2026-09-07 轮次：Furnace 定稿对齐（R0–R1 文档阶段完成，R2 进行中）

> 项目定稿更名为 **Furnace**（权威规范：docs/FURNACE_SPEC.md；差距与迁移：docs/GAP_ANALYSIS.md）。

- [x] R0：全量备份 `class-productivity` → `_backup/2026-09-07/`（630 文件）
- [x] 定稿存档：`docs/FURNACE_SPEC.md`（逐字权威版）
- [x] 差距清单：`docs/GAP_ANALYSIS.md`（D1–D13 决策、逐条差距矩阵、常量缺省表、.tfpkg 草案、R0–R6 路线）
- [x] `docs/DATA_MODEL.md` 重写为 v2（树形标签 path、Tasks+expected_at/energy_required、ThreadStates、CompletionLogs、TaskTemplates、ClozeSlots/ClozeHistory、CardStates 呈现单元+FSRS 字段、BoostEntries、Themes、Attachments；schema 1→2 迁移步骤）
- [x] `docs/ARCHITECTURE.md` 对齐（命名映射 D2、ThreadRanker/FSRS/ClozeEngine/DiffusionBoost/TimeWindowEngine 分层、闭环流程、常量收口）
- [x] 环境结案：本机 Flutter 3.47.2 / Dart 3.13.2 可用；pub.dev 可达（O1 关闭）；TimeBlock.available 语义确认同向无需翻转（O2 关闭）
- [x] 文档对齐完成：PRD 取代标记、README 更名、OPEN_QUESTIONS 结案、KNOWLEDGE_PACKAGE +.tfpkg 节、PRIVACY 双轨、MILESTONES R0–R6、FEATURE_MATRIX 重建
- [x] R2 起点：Drift schema v2 全部表/列已入 `tables.dart` 并生成 `database.g.dart`（build_runner --force-jit 规避沙箱 AOT 写盘限制）；`dart analyze` 定位 16 错误（Theme 类名冲突×12 待 @DataClassName、anki 仓库 Value 包裹×2、anki_page 空安全×1）
- [x] R2 完成：@DataClassName('ThemeProfile') 消冲突；Repository v2 扩展——TaskRepository(+expected_at/energy_required/完成→CompletionLogs 快照)、TagRepository 树形（parent_id/path 级联改名/移动/子树删除/导入系）、AnkiRepository（呈现单元 unitKey、槽位/挖空历史、图谱扩散 BoostEntries、ReviewLogs v2 扩展）、ThreadStateRepository（单行精力/目标/2h 过期判定）、repository_providers 装配
- [x] R2 验证：真实 v1 SQLite 文件就地迁移 v2 单测通过（含标签 path 回填去重、card_states 回填 knowledge_point_id/unit_key='preset:…'、review_logs 扩展列）；v2 仓库行为 14 项全绿；**全量 35/35 测试通过；dart analyze 0 错误 0 警告**
- [ ] R3：纯 Dart 核心算法（ThreadRanker/FSRS/ClozeEngine/图谱扩散/TimeWindow/TagTree 服务/模板/批改）

> ⚠️ 编码教训（写入本文件备忘）：pwsh 的 Get-Content/Set-Content 文本往返在中文环境下按 GBK 解码会损坏 UTF-8 文档——文档一律用 read/edit/write 工具或 .NET UTF8 API 操作；build_runner 必须带 `--force-jit`（AOT 快照写盘被沙箱拦截）；`flutter analyze` 的 LSP 通道在沙箱下崩溃，验证用 `dart analyze`。

---

## 已完成

### 需求与设计
- [x] 需求沟通（团队、Windows 优先、离线优先、隐私、知识包分享、中英双语）
- [x] PRD、架构、数据模型、知识包格式、隐私设计、里程碑文档
- [x] 待确认问题清单与默认决定

### M1：Flutter 项目骨架（源码）
- [x] `app/pubspec.yaml`、`analysis_options.yaml`、`l10n.yaml`
- [x] 中英文 ARB 文案
- [x] 应用入口 `main.dart`、根组件 `FurnaceApp`
- [x] 桌面/移动自适应导航壳 `HomeShell`
- [x] 设置页（语言/主题切换，内存态）
- [x] 五大模块占位页（思维导图/任务/时间/背诵/设置）
- [x] 开发环境文档 `docs/DEV_SETUP.md`
- [x] 引导脚本 `scripts/bootstrap.ps1`

### 核心算法原型（纯 Dart，待有 Flutter 环境后跑测试）
- [x] SM-2 间隔重复调度 `Sm2Scheduler`
- [x] 任务自动编排引擎 `TaskScheduler`
- [x] 自动挖空生成器 `ClozeGenerator`
- [x] 领域实体：Task、TimeBlock、KnowledgePoint、CardTemplate、SrsState
- [x] 对应单元测试文件

### M2：数据层（源码）
- [x] Drift 表结构：Profile、LocalSettings、Tag、ObjectTag、MindMap、MindNode、Task、TaskDependency、TimeBlock、TaskTimeBlock、KnowledgePoint、CardTemplate、CardState、ReviewLog、KnowledgePackage、PackageItem
- [x] `AppDatabase` + 连接 + 外键
- [x] Repository：Settings、Tag、Task、TimeBlock、Anki、MindMap
- [x] Riverpod providers 装配数据库与 Repository
- [x] AnkiService（Repository + SM-2 调度）
- [x] TaskSchedulerService（Repository + 调度引擎）

### 知识包（部分源码）
- [x] `KnowledgePackageManifest` JSON 模型
- [x] `.kpak` zip 编解码器 `KnowledgePackageCodec`
- [x] `PackageRepository` 与 `PackageImportService`（导入标签/知识点/模板/思维导图，去重并保留复习进度）
- [x] 对应单元测试

---

### M3-M6：基础 UI（源码）
- [x] 导航壳加入“知识库”页（共 6 个模块）
- [x] 思维导图页：新建导图、节点树、添加节点、重命名、删除节点、节点转标签
- [x] 任务页：新建任务、优先级/预估、完成切换、删除、查看自动建议
- [x] 任务详情页：子任务、依赖、提醒设置、本地通知调度
- [x] 时间板块页：新建/删除时间块、时间选择
- [x] Anki 页：加载到期卡片、三种题型呈现、显示答案、忘记/模糊/记得评分
- [x] Anki 管理页：新建知识点、新建选择题/填空题/大题模板
- [x] 知识库页：导入预览确认、文件选择导入 `.kpak`，调用 `PackageImportService`
- [x] 知识库页：导出 `.kpak`（`PackageExportService` + 文件保存）
- [x] `PackageExportService`：从本地标签/知识点/模板/思维导图生成 manifest
- [x] `NotificationService`：本地提醒通知（Windows/Android 预留）
- [x] 设置持久化：启动加载 Profile/Settings，语言/主题切换写入数据库
- [x] 任务建议“一键采纳”：把建议任务链接到对应时间块
- [x] Anki 填空判分：提交后判断正确/错误，选择题显示正确/错误反馈
- [x] Anki 管理页统计：知识点数、模板数、到期卡片数、7天复习次数
- [x] 时间块可用状态切换（影响任务调度建议）
- [x] 时间块显示已关联任务
- [x] 标签管理页（新增/删除标签）
- [x] 设置页支持修改作者/姓名
- [x] Anki 模板/知识点删除
- [x] Anki 模板编辑（题型/题目/答案/选项）
- [x] 任务编辑（标题/优先级/预估时间/截止时间，可清除截止时间）
- [x] 知识点编辑（标题/内容）
- [x] 时间块编辑（标题/开始/结束/可用状态）
- [x] 自动挖空：管理页一键生成填空模板
- [x] 自动挖空：导入知识包时，无模板的知识点自动生成填空模板
- [x] 任务列表支持点击圆圈快速完成/恢复
- [x] 思维导图节点支持折叠/展开
- [x] 任务列表显示截止时间
- [x] 新增测试：任务调度 timeBlockId、知识包导入自动挖空/去重、设置档案持久化
- [x] 思维导图节点“转为任务”（可同时带上标签）
- [x] 时间块支持精力/适合类型属性（创建/编辑）
- [x] 时间板块“今日安排”汇总视图（按时间块展示已关联任务）
- [x] 导出知识包时显示隐私说明（不包含任务/时间/复习进度）
- [x] 知识包导入预览显示“升级”提示（旧版本 → 新版本）
- [x] 时间块支持标签关联（编辑弹窗中添加/移除标签）
- [x] 任务调度引擎：优先选择“适合类型”匹配任务标签的时间块
- [x] Anki 管理页新增 7 天复习柱状图
- [x] 知识点支持来源字段（创建/编辑）
- [x] 思维导图节点支持备注编辑/显示/清除
- [x] 新增 `docs/FEATURE_MATRIX.md` 需求-实现功能矩阵
- [x] 思维导图节点支持同级上移/下移排序
- [x] 本地化补全：导出默认名称/作者、任务空态文案
- [x] 修复 Flutter 实机问题：本地化 import、Drift 列定义、通知库 v22 API、build_runner --force-jit
- [x] Anki 选择题选项随机打乱（每次复习顺序不同）
- [x] 设置页支持本地数据库备份（保存 .db 文件）
- [x] 标签关联：任务详情页可添加/移除标签
- [x] 标签关联：知识点详情弹窗可添加/移除标签
- [x] Windows 构建脚本 `scripts/build_windows.ps1` 与发布文档 `docs/DEPLOY.md`

---

## 下一步（R2–R6，详见 docs/GAP_ANALYSIS.md §6）

1. R2 收尾：修复 dart analyze 16 错误（@DataClassName 等）；Repository 扩展（ThreadStates/TaskTemplates/CompletionLogs/树形 Tag/复习单元 API）；schema 迁移与 CRUD 单测（`flutter test`）；db 文件迁移到 `threadflow.db`（已实现兼容回退）。
2. R3：纯 Dart 核心 —— `ThreadRanker`（加权公式+硬约束+疲劳惩罚，常量 `FurnaceDefaults`）、Dart FSRS 替换 SM-2、`ClozeEngine`（自由挖空/出题/错题绑定状态机）、`DiffusionBoost`（图谱距离 BFS+衰减）、`TimeWindowEngine`（重复规则展开/占用/空闲窗口）、TagTree/Template/BatchEdit 服务。
3. R4：`.tfpkg` 编解码（逻辑全量转储+附件+主题，可选 AES-GCM）+ 覆盖/追加合并器；主题 JSON 与外观系统（缩放/字体/背景）。
4. R5：UI 迁移与联动：Furnace 词表、Thread 顶栏+更新排序、硬约束红标、日/周/月日历+冲突一键调整、Knowledge 新复习流+生成任务、Mindnet 系导入/设目标/.mm-OPML。
5. R6：拖拽 re-parent、双语补全、FEATURE_MATRIX/PROGRESS 回写、Windows build 冒烟、pubspec 更名 threadflow。

---

## 环境（2026-09-07 更新）

- 本机已装 Flutter 3.47.2（stable）/ Dart 3.13.2；pub.dev 可达；build_runner 需 `--force-jit`（沙箱限制 AOT 快照写盘）；`dart analyze` 可用（`flutter analyze` 的 LSP 通道在沙箱下截断崩溃，用 `dart analyze` 替代）。
- 注：早期轮次的“当前机器未安装 Flutter/Dart”限制已解除（见上轮“M6 基础 UI”）。
