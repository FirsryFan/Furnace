# 题库四层成熟度管线（原始数据 → 未加工题 → 已加工题 → 成熟题单）

- 状态：**设计稿，未实现任何代码**（2026-11-01）
- 读者：Lead / Furnace 开发组 / 内测审核小组
- 依据：用户四层口径（见 §1.1「用户原话要点」，来自 task-9 任务转述）；仓库代码与规范逐条标注 `文件:行号`
- 标记约定：【现状】= 仓库里已有；【新增】= 本文设计、尚未实现；【未确认】= 需 Lead/用户定夺
- 边界：本文只给设计，不动 `tables.dart`/`database.dart`/`database.g.dart`；改 schema 前先读 `docs/DATA_MODEL.md` §29/§30 的迁移惯例

## 0. 一句话结论

四层**不是四张新表**，而是一条由「证据是否齐」决定的阶梯：原始数据是附件；未加工题是 `questions.state='raw'` 的行；已加工题是「有解题链 + 有标签 + 通过入库体检」的 `processed`；成熟题是**题单级产物**（PaperPlan + 材料容器），不是更靠后的单题状态。
落地的最小改动 = **2 个新列 + 4 张新表 + 1 个事件表**，其余全部复用现有实体与工具。
「整的步骤 AI 自完成」的可行性**已经具备**：现有审批纪律是「除删除外自动执行 + 全量台账 + 可撤销」（`docs/AI_DESIGN.md:296-315`），但 App **没有后台周期任务**（§1.4），所以「定期从组卷网收集」必须留在外部 CLI。
真正的缺口不在状态位，而在**证据**：`question_attempts` 只有 4 列（§3.1），没有用时/错因/重做，无法回答「哪个能力在变好」。

## 1. 四层定义、状态机与转换

### 1.1 四层对象

| 层 | 用户原话要点 | 数据落点【现状】 | 必须字段/产物 | 退出条件（判定） |
| --- | --- | --- | --- | --- |
| L1 原始数据 | 「用户拍照图片等原始数据」 | 附件：`attachments`（`ownerType` = `question`/`handwriting_intake`/`ai_message`）；照片清单 `handwriting_intake_runs.source_photos` | 文件相对路径 + mime + 来源（照片/粘贴/包）；**尚未有题行** | 结构化出题干（`stem` 非空）→ 建 L2 行 |
| L2 未加工题 | 「AI 据图去组卷网找题，或定期任务从组卷网收集，保存题目/答案/解析原文」 | `questions` 行，`state='raw'`；`origin='ai_scan'/'zujuan'`；`source_url`/`zujuan_question_id`/`zujuan_bank_id`；`attachments.role='answer'` | 题干原文、答案原文、解析原文（可空）、来源锚点（URL/qid） | 有链 + 有标签 + 通过体检 → L3 |
| L3 已加工题 | 「经 MindNet 等完整评价、标签流程、题目分析、扩展设计，深度融入 Furnace」 | `state='processed'`；`reasoning_chains/steps`、`capability`、`trap_note`、`difficulty/difficulty_source`、`extension_of`、`object_tags` | 至少 1 条链、A1–A10 能力、≥1 知识点标签、体检无 error | 进入选题池；被选入题单并完成"扩展/精简/组织" → L4 |
| L4 成熟题单 | 「AI 制作题单时进一步扩展链接、内容精简加工、多题组织设计，形成成熟题目供学习」 | `PaperPlan`（内存计算结果，**不落库**）；`docs/PAPER_COMPOSER_DESIGN.md` §5；材料容器【未做】 | 题单：选题理由、顺序、缺口、质量体检、版式（docx）；材料：题目/解析/扩展三块 | 审核通过 + 导出/发布 |

关键设计判断：**L4 的成熟度属于"题单/材料"，不属于"单题"**。用户在 L4 描述的动作（扩展链接、内容精简、多题组织）都是集合级操作；单题在 L4 只体现为"被成熟题单选用过的证据"。若把 L4 写成 `questions.maturity='mature'`，会退化成人工标记位，无法解释"哪份题单让它成熟"。

### 1.2 单题状态机：现状三值 + 设计新增一列

【现状】`questions.state` 的注释定义三值：`raw` 刚收进来 / `structured` 已结构化 / `processed` 已拆链并标注错因（`app/lib/data/database/tables.dart:1296-1297`）。
真正写入点：
- `structured`：`QuestionDraft` 默认值（`app/lib/data/repositories/question_repository.dart:95`）；`.tqb` 记录默认值（`app/lib/domain/services/package/question_pack_record.dart:217,383`）
- `raw`：整卷页粘贴导入（`app/lib/features/questions/application/zujuan_paste_import.dart:65`）
- `processed`：存链时自动写（`question_repository.dart:983-987` 方法注释「存一条思维链（含步骤），并把题目标成已加工」，写入在 `:1030`）
- 手工改：`QuestionRepository.updateProcessing`（`question_repository.dart:563-590`）；UI 筛选枚举 `['raw','structured','processed']`（`app/lib/features/questions/presentation/question_intake_page.dart:1246`）

【现状】两个硬约束（决定"回滚"怎么设计）：
1. **只追加**：「题干/选项一旦入库不再原地改写；加工只写 `state`/`trapNote`/`difficulty`/`aiQuality` 这几个加工列」（`question_repository.dart:216-217`）→ L2→L3 的转换绝不能改题干。
2. `.tqb` 再导入是**补丁语义**：空值=不动（答案不会被空串冲掉）（`question_repository.dart:705-722`）。

【新增】`questions.maturity`（TEXT，可空）四值 `raw`/`unprocessed`/`processed`/`mature`（仅当被成熟题单采用过；**不建议**作为 L4 主键，理由见 §1.1）。迁移期 `NULL` = 读侧按现有 `state` 派生（沿用 `serialNo` 可空 + 读侧回退的惯例，`tables.dart:1193-1197`），避免一次性回填。
单题转移表（触发者见 §1.4）：

| 转移 | 前置判定（全部满足才转） | 写什么 | 失败/回滚 |
| --- | --- | --- | --- |
| L1→L2 | 解析出非空 `stem`；指纹未命中已有题（否则返回既有题，`ingest` 返回 `created=false`，`question_repository.dart:235-239`） | 插 `questions` + `question_options` + 附件 role；题号在事务内分配（:243-304） | 解析失败：L1 附件不动；题号不复用（高水位，:248-268） |
| L2→L2+ | 答案/解析原文补齐、来源锚点回填 | `updateFromPack`/`updateProcessing`（只写加工列） | 补丁空值=不动，旧答案保留（:705-722） |
| L2→L3 | 有链（`saveChain` 自动置 `processed`）+ 能力点 + 知识点标签 + `audit_question_intake` 无 error | `reasoning_chains/steps`、`capability`、`trap_note`、`difficulty` | 不满足：停在 L2/L3 之间，**不降级**已有产物；审核不通过走 §4.4 |
| L3→L4 | 被 `compose_paper` 选入题单且质量体检通过（17 条判据，`PAPER_COMPOSER_DESIGN.md:475-515`） | 题单（PaperPlan）+ 质量报告；单题只写"被采用"引用 | 题单可整体重算；导出失败不破坏题库（导出只读，§2.4） |

### 1.3 题单（L4）状态机【新增】

`draft`（AI 组卷出 Plan）→ `annotated`（扩展链接/精简/多题组织已补）→ `reviewed`（人工审核通过）→ `published`（导出 docx/材料包）；任一步可 `discarded`（不删原始题，只废弃题单）。
【现状】PaperPlan 是纯计算值对象（`app/lib/domain/services/paper/paper_composer.dart:365-391` 构造与字段，`:495` 的 `toJson`），**未找到任何持久化表**（`tables.dart` 的 Table 类清单中无 paper 相关；`paper_plan_provider.dart`/`question_paper_page.dart` 无写库调用，本次 grep 确认）→ 所以 L4 必须新表，否则"成熟题单"无处存。

### 1.4 「AI 自主触发」能到哪一档（关键约束）

现有权限纪律（用户 2026-09-25 定）：**「除了删除，我认为都可以全自动」**；风险只分 `destructive`/`write` 两级，默认模式 `write` **自动执行**、`destructive` **逐条确认**（`docs/AI_DESIGN.md:296-315` D12；实现 `app/lib/features/ai/domain/approval_engine.dart:38-66`）。
D13b 是自动化门槛：**无法可靠保存 before 快照的工具，一律降级为逐条确认**（`AI_DESIGN.md:315`）。撤销依赖 `ai_actions.before_json/after_json`（`AI_DESIGN.md:313`；表定义 `tables.dart:962-999`）。

因此「整的步骤 AI 自完成」分三档：

| 档 | 条件 | 适用步骤 |
| --- | --- | --- |
| **自动** | `write` + 可逆（有 before 快照） | 建 L2 行、补答案/来源、写链、写能力点、重组题单、导出 docx |
| **需确认** | `destructive` 或 `reversible=false` | 删重复题、删错建的行、覆盖既有链 |
| **不可在 App 内** | 需要联网浏览器 | 组卷网取题/取答案（登录态必须在用户浏览器里；`FURNACE-PIPELINE-SPEC-v1.md:26-34`） |

**没有后台周期任务**：本次 grep `Timer.periodic|WorkManager|backgroundFetch|scheduledTask`（`app/lib`）只命中运行时间线秒表 `app/lib/features/ai/presentation/widgets/run_timeline.dart:106`；本地通知只有一次性提醒（`app/lib/core/notifications/reminder_notifier.dart:1-30`）。所以用户的「定期任务从组卷网收集」只能：①外部 CLI 跑完 → `.tqb` 导入（`HANDOFF_PIPELINE.md:92-95` 的真实包验证）；②给用户排一条提醒，由他一键开一轮对话。**不要**在 App 里假装有定时采集。

### 1.5 失败与回滚

| 失败 | 现状可用的机制 | 缺口/要求 |
| --- | --- | --- |
| 模型解析错（切题错、选项缺） | `ai_actions` 记 `before/after`，撤销按工具 case 执行（`agent_loop.dart:1014-1016`；`create_questions` 撤销只删本次新建，`HANDOFF.md:275`） | L2→L3 的"加工提案"也要有 before 快照 |
| 重复入库 | 题干指纹（FNV-1a 64 位，`tables.dart:1289-1291`）+ 组卷网题号优先（判定顺序 ①按题号 update→②指纹 skip→③包内同号→④包内同指纹→⑤create，`question_pack_plan.dart:20-35`） | 近似重复仍未做（`QUESTION_INTAKE_AUDIT_DESIGN.md:235`） |
| 批量失败 | 事务：`ingest` 一个事务内完成题+选项+标签（`question_repository.dart:243-304`） | 长流程需要 `pipeline_runs` 记每步状态（§4.2） |
| 删错了 | 删除逐条确认 + 撤销台账；删题显式级联（`question_repository.dart:952-980`） | 删除链路是唯一不许自动的（`AI_DESIGN.md:301`） |

## 2. 映射现有实体 / 字段 / 表 / 工具

### 2.1 L1 原始数据

| 对象 | 位置 | 说明 |
| --- | --- | --- |
| `attachments` | `tables.dart:791-815` | 通用附件表；`ownerType`+`ownerId`；只有题目用 `role`（`stem`/`answer`/`solution`） |
| 拍照收题图 | `app/lib/features/questions/data/handwriting_intake_store.dart:1-14` | `ownerType='handwriting_intake'`；**保留原始分辨率**（不为 OCR 压缩） |
| 对话附件 | `app/lib/data/repositories/ai_repository.dart:193` | `ownerType='ai_message'`；图片先属于消息，收题后另存 |
| 多图/多页清单 | `tables.dart:1420-1422` | `handwriting_intake_runs.source_photos`（JSON 数组） |

### 2.2 L2 未加工题

| 能力 | 现状 | 位置 |
| --- | --- | --- |
| 写入（AI 收题） | `create_questions`，一次 ≤100 题；只誊写不改写；重复返回既有题（`created=false`） | `app/lib/features/ai/tools/question_write_tools.dart:32-53` |
| 写入（整卷粘贴） | 解析组卷网整页 → `state='raw'` 草稿 → `ingest` | `zujuan_paste_import.dart:65` |
| 写入（外部包） | `.tqb` 导入 create/update/skip；`text_format`/`extension_of`/`capability` 可带 | `question_pack_plan.dart:20-35`；`question_pack_service.dart:630-650` |
| 找题/对照 | `read_zujuan_paper` **只读**：解析整页并对照题库报"缺哪几道"，不联网不抓页 | `app/lib/features/ai/tools/zujuan_paper_tool.dart:36-40` |
| 来源锚点 | `source_url` / `zujuan_question_id` / `zujuan_bank_id`（可重建详情页；比指纹硬） | `tables.dart:1236-1255` |
| 原文保存 | `answer`/`solution` 可空（先收题干后补答案）；答案截图作 `attachments.role='answer'` | `tables.dart:1212-1216,805-815` |

### 2.3 L3 已加工题

| 能力 | 现状 | 位置 |
| --- | --- | --- |
| 解题链 | `reasoning_chains`（可多条，不覆盖）+ `reasoning_steps`（`actionType` 能力动作词表、`justification`、`checkMethod`、`stuckRisk` 0–1、`knowledgeHints`） | `tables.dart:1330-1395` |
| 链=派生、可重跑 | 不参与跨设备合并；错因写题目级 `trap_note` + 步骤级 `stuckRisk/note` | `docs/QUESTION_BANK_DESIGN.md:79-81,84-85` |
| 能力 A1–A10 | `capability` JSON 列（`["A3","A7"]`），词表 `QuestionCapability`；校验正则 `^A(10|[1-9])$` | `tables.dart:1274-1281`；`domain/services/questions/question_capability.dart:12-41`；`question_pack_record.dart:34` |
| 难度 | `difficulty` + `difficulty_source`（`prior/ai/manual`） | `tables.dart:1283-1287` |
| 扩展关系 | `extension_of` = 母题的组卷网题号（不建外键，悬空忽略） | `tables.dart:1266-1272`；`domain/services/questions/question_extension.dart` |
| MindNet 评价 | `ProblemEvaluator`：6 种判词 `tooEasy/zpd/tooHard/outOfScope/redundant/highValue`；阈值**全部未标定** | `app/lib/domain/services/cognitive/problem_evaluator.dart:68-94,123-127` |
| AI 工具面 | `evaluate_problem_fit`（只读）；`find_questions_by_capability`（只读，按能力动作找题，只认最新一条链） | `app/lib/features/ai/tools/cognitive_tools.dart:59`；`question_tools.dart:353-375` |
| 入库体检 | `audit_question_intake`：H1 题干/H2 答案/H3 元数据/H4 重复 26 条判据，**只报不改** | `app/lib/features/ai/tools/question_audit_tools.dart:18-45`；`question_intake_audit.dart:55-94` |

### 2.4 L4 成熟题单

| 能力 | 现状 | 位置 |
| --- | --- | --- |
| 组卷 | `compose_paper`（只读、不凭空出题；按危险/发展区 + 来源 + 难度 + 学科/领域配额贪心），报 `uncoveredKnowledgePointIds` 等缺口 | `app/lib/features/ai/tools/paper_tools.dart:31-58`；`paper_composer.dart:365-391` |
| 质量体检 | 17 条确定性判据（题数/学科集中/来源单一/难度/缺口/zone 失衡/配额缺口），**全部未标定** | `PAPER_COMPOSER_DESIGN.md:450-515` |
| 题单落库 | **无表**（见 §1.3 grep 结论） | — |
| 导出 docx | 卷面→docx 字节（含 OMML 公式、配图策略、质量节） | `app/lib/features/questions/application/paper_docx_export.dart:1-45`；`docs/DOCX_EXPORT_DESIGN.md` |
| 导出 md/txt | `create_document` **只能写 md/txt**，不产 docx（明确拒绝伪装扩展名） | `app/lib/features/ai/tools/document_tools.dart:23-56` |
| 外部排版 | `paper-composer` skill：Word 真测 + 逐题页码 + 验收报告；页脚时期代号（`Senior 3-1 Week 6`） | 工作区 `10-projects/paper-composer/papers/.../排版验收报告.md:1-19` |
| 材料包（M2-c）与练习记录（M2-d） | **未做**（无表、无载体）；规范已定目录/字段 | `docs/HANDOFF_PIPELINE.md:17-18,70-72`；`FURNACE-PIPELINE-SPEC-v1.md` §5.1/§5.9 |

### 2.5 .tqb 导入/更新语义（L4 导出必须复用的既有契约）

- 包 = zip（`manifest.json` + `questions.json` + `media/`），`format='furnace-question-bank'`、`version=1`（`app/lib/domain/services/package/question_pack_manifest.dart:14-17`）
- 合并判定：①按组卷网题号命中→`update`；②题库已有指纹→`skip_duplicate`；③包内前面已有同题号；④包内前面已有同指纹；⑤否则 `create`；`updateExisting=false` 时整体走旧语义（不认题号）（`question_pack_plan.dart:20-35`）
- 单包上限 5000 题（`question_pack_record.dart:17`）；未知键忽略所以**新字段可先行写入**（`FURNACE-PIPELINE-SPEC-v1.md:671-676`）

## 3. 「全量记录、阈值结论」事件层要求

### 3.1 现状缺口

`question_attempts` 只有 4 列：题 id、勾选 label（JSON）、是否正确、作答时刻（`tables.dart:1676-1697`）。**没有**用时、错因、岔路、重做历史、链/能力快照；填空/解答题现在不判分、不写记录（:1685-1690）。`QuestionAttemptStats` 只从「判分成功的条数」派生正确率（`app/lib/domain/services/questions/attempt_stats.dart:1-12`）。

### 3.2 现有阈值先例（照抄口径，不另造）

- 能力统计：样本少于 `kCapabilityMinSamplesForConclusion = 3` 时照样给数字，但 `hasEnoughSamples=false`「别硬下结论」（`capability_stats.dart:21-26`）
- 入库体检：样本 <5 道只算初筛；「未发现硬伤」≠「已证明没问题」（`question_intake_audit.dart:5`）
- 组卷读数：缺数据 = 未知 0.35，排在"已知健康"之前（"缺数据不许冒充好数据"，`PAPER_COMPOSER_DESIGN.md:37-40`）

### 3.3 事件层设计要求【新增】

1. **每次事件都记**：作答、错因选择、开始/结束时间、限时与实际用时、重做（1/3/7/21 天轮次）、是否完成产出物、是否孤立单题错。孤立错**不得过滤**——过滤就失去"噪音 vs 缺陷"的判断依据（`FURNACE-PIPELINE-SPEC-v1.md` §5.6 双标签诊断：孤立单题错=噪音不处理，但前提是先有记录）。
2. **结论必须带 n 与口径**：任何"最弱能力""该练动作""成熟度升级"的结论输出 `sample_n`、`min_samples`、`口径版本`；不足门槛只展示"数据不足"，不给排序。
3. **结论是派生、不落库**（与链、卡点报告同一纪律，`QUESTION_BANK_DESIGN.md:79-81,84-85`）：只有"发布"（题单/材料）才落一行快照。
4. **字段对齐规范**：`material_id/question_id、subject、question_type(T)、capability(A[])、time_limit/time_spent、result(对/错/部分对)、error_cause(知识缺口/方法缺失/计算/审题/时间)、detour、output_done、redo_history`（`FURNACE-PIPELINE-SPEC-v1.md` §5.9 记录字段表）。

## 4. 需要新增的 schema（只设计，不实现）

> 迁移惯例：新增列走 `_ensureColumns()` 自愈 + 版本号同步（`HANDOFF_PIPELINE.md:31-34` 是 v40 三列的做法）；新表要 seed 幂等、脏数据不抛。目标 **schema v42**，分三步上（先列、再表、再回填）。

### 4.1 `questions` 两列
- `maturity` TEXT 可空（`raw/unprocessed/processed/mature`；NULL=读侧由 `state` 派生）
- `raw_provenance` TEXT 可空（JSON：`{photo:[relPath], paste:bool, pack:'<name>@<ver>', source:'ai_scan|zujuan|manual|pack'}`）。为什么不塞 `origin`：`origin` 是三值闭集（`tables.dart:1305-1306`），加值会破坏既有展示与包契约；provenance 是自由 JSON，未知键安全。

### 4.2 `pipeline_runs`（一次"整"的全过程）
`id` / `kind`（`ingest_from_photo|import_pack|process_chain|compose_collection|export`）/ `input_ref` / `status`（`running|succeeded|failed|cancelled`）/ `counts_json`（created/updated/skipped/failed）/ `detail_text` / `started_at, finished_at` / `subject_kind, subject_id`（可空）/ `ai_action_ids`（JSON，关联台账行）。
理由：现有 `ai_actions` 是**工具调用级**台账（`tables.dart:962-999`），一次"整"跨多个工具调用，需要一个运行级容器才能回答"这一轮到底做成没有"。

### 4.3 `question_events`（append-only 事件层）
`id` / `question_id`（可空：材料题可只有 material_item_id）/ `material_item_id`（可空）/ `kind`（`attempt|error_cause|time_spent|redo|produce|skip`）/ `result` / `error_cause` / `time_limit_sec, time_spent_sec` / `redo_round` / `detail_json`（岔路、选项、信心自评）/ `occurred_at` / `pipeline_run_id`。
纪律：只追加、不更新；删除题目时显式级联（项目无外键，参考 `deleteQuestion` 的做法，`question_repository.dart:952-980`）。

### 4.4 `review_decisions`（内测审核，§5）
`id` / `item_kind`（`question|collection|material|pack`）/ `item_id` / `reviewer`（`profiles.id`，本机多 profile 即可）/ `decision`（`approve|request_fix|reject`）/ `reason` / `checklist_json` / `snapshot_json`（送审时的关键字段副本）/ `created_at`。

### 4.5 材料容器（M2-c）与练习记录（M2-d）
- `materials`：`id, kind(topic_sheet|wrong_book|exam), title, subject_key, source_ref, status, published_at`
- `material_items`：`id, material_id, question_id(可空), sort_order, section(题目/解析/扩展), asset_ref`（题目可空是为了"同材料自命题"这种无题卡材料，参见 SPEC §5.1 的概要写作）
- 练习记录直接落 `question_events`（`material_item_id` 维度），不另建表
- 答案可见性：题目页/解析页分离是硬要求（`FURNACE-PIPELINE-SPEC-v1.md:372-374`）

### 4.6 兼容与导出
- 新增字段一律**可空 + 读侧回退**；`.tqb` v1 解码**忽略未知键**（`FURNACE-PIPELINE-SPEC-v1.md:673`），所以 v2 字段可先写后升版
- `.tqb v2` 建议只加 `maturity`（可选，导出侧声明）+ 保留现有 `text_format/extension_of/capability`
- **成熟题单不建议塞进 `.tqb`**：`.tqb` 语义是"题库包"（一题一条记录），题单是"组织 + 版式"；建议新容器（名字待定：`待确认`），内含 `manifest.json`（题单元信息 + 引用的 `zujuan_question_id` 列表）+ 每题 `extended_notes` + `docx` 附件；导入语义复用 `create/update/skip_duplicate` 判定顺序

## 5. 与内测小组内容审核的接口

### 5.1 三个审核点（只审"AI 加工"，不审"用户私库"）

| 审核点 | 触发 | 机器初审（免费、确定性） | 人工只处理 |
| --- | --- | --- | --- |
| A. L2→L3 加工提案 | AI 跑完链/能力/标签，写库前 | `QuestionIntakeAudit` H1–H4 26 条（error 阻断、warning 提示） | `needsReview` 的题（答案/解析缺失、题干说"如图"无图） |
| B. L3→L4 题单发布 | 组卷 + 质量体检后，导出前 | `PaperQualityReport` 17 条判据 + 缺口清单 | 判据命中项 + 审核理由 |
| C. 外部包导入 | `.tqb` 预检后 | 导入预检计数（manifest vs 实际、新增/跳过/缺标签） | 缺标签、未知来源、批量更新的题 |

### 5.2 记录什么（每条审核一条 `review_decisions` 行）
审核人、时间、审的是哪一项（item_kind+item_id+内容快照 hash）、结论（通过/退回/拒绝）、理由（人话）、清单逐项（checklist JSON，对应机器初审 code 列表）、**送审版本**（`snapshot_json`：题干/答案/能力/标签/链的摘要）。理由：现有所有"待确认"模式（`handwriting_proposals.applied_at`、`material_intake_proposals.applied_at`，`tables.dart:1461,1563`）只记"确认过没有"，不记"谁为什么放行"，内测需要可追溯的审核结论。

### 5.3 与现有机制的分工（不重复造）
- **审核 ≠ 审批**：`ApprovalEngine` 管"这个工具调用要不要现在执行"（`approval_engine.dart:38-45`）；审核管"这条内容能不能算成熟/能不能发给别的学生"
- 待确认清单的 UI 模式直接复用：提案 + 预检 verdict（`ready/needsReview/blocked`）+ 批量确认按钮（`app/lib/domain/services/intake/handwriting_proposal_preview.dart`，设计见 `QUESTION_BANK_DESIGN.md:491-503`）
- 内测多身份：本机 `profiles` 表已存在（`tables.dart:4`），但没有跨设备账号（PRD 明确"不做公网云同步/账号登录"，`docs/PRD.md:30`）→ 审核人字段只能记本机 profile；**【未确认】**内测组是共用一台设备还是各自设备回传，影响是否要导入/导出审核记录

## 6. 开放问题

1. **L4 归属**：成熟题单算"题目属性"还是"题单属性"？（本文按题单；若用户要单题也能标成熟，需要定义"成熟"的判定口径）
2. **成熟 = 谁说了算**：机器判据全绿 + 内测抽检通过，还是必须人工 100% 过？决定是否允许"自动发布"。
3. **「内容精简加工」的边界**：允许改写题干吗？现行纪律是"只追加、不改题干"（`question_repository.dart:216-217`），若要精简必须改成"派生视图"（原题保留 + 精简版另存），需要用户拍板。
4. **外部采集与 App 的边界**：定期从组卷网收集要不要做成"外部 CLI + 每日提醒 + 一键导入"？（App 无后台任务，§1.4）
5. **审核记录的流转**：内测组的审核结论要不要能导出/合并（把题给别人审会碰"不做账号/不云同步"红线）。
6. **事件层粒度**：`question_events` 每道单独记，还是按"一次练习"聚合？要支持 1/3/7/21 天重做追踪，建议事件 + `redo_round`，需确认存储量。
7. **`.tqb v2` 还是新格式**：成熟题单要不要进 `.tqb`？（本文建议新容器，名字待定）
8. **未标定阈值**：`kCapabilityMinSamplesForConclusion=3` 与 PaperQuality 17 条判据都是产品默认值（`capability_stats.dart:21-24`；`PAPER_COMPOSER_DESIGN.md:475`），内测阶段是否允许"先用默认、跑够样本再标定"？
9. **重做自动建卡组**：M3-b 已部分实现卡组键（`docs/HANDOFF_PIPELINE.md:20`），6:2:2 配额未做——成熟题单是否要直接生成复习卡组？
10. **拍照原件保留期**：L1 照片保留多久、审核后能否删（附件无回收站机制）。

## 附：证据索引（本次实际读到）

- 用户四层口径：task-9 任务转述（Lead 2026-11-01）
- 审批纪律：`docs/AI_DESIGN.md:296-315`；`app/lib/features/ai/domain/approval_engine.dart:38-66`
- 题目实体：`app/lib/data/database/tables.dart:1186-1313`；`docs/QUESTION_BANK_DESIGN.md:26-60`
- 状态写入：`app/lib/data/repositories/question_repository.dart:95,216-217,235-304,563-590,705-722,983-987,1030`；`zujuan_paste_import.dart:65`
- 链/步骤：`tables.dart:1330-1395`；`docs/QUESTION_BANK_DESIGN.md:69-86`
- 能力 A1–A10：`domain/services/questions/question_capability.dart:12-41`；`capability_stats.dart:21-26`；`question_pack_record.dart:34`
- 附件：`tables.dart:791-821`；`handwriting_intake_store.dart:1-14`；`ai_repository.dart:193`
- 材料摄取（知识点向，不是题目材料）：`tables.dart:1470-1617`（`kind` 只有 `knowledge_point`/`connection`，:1552）
- AI 工具：`question_write_tools.dart:32-53`、`question_tools.dart:353-375`、`zujuan_paper_tool.dart:36-40`、`paper_tools.dart:31-58`、`document_tools.dart:23-56`、`question_audit_tools.dart:18-45`
- `.tqb`：`question_pack_manifest.dart:14-17`、`question_pack_plan.dart:20-35`、`question_pack_record.dart:17,217,383`
- 组卷/导出：`paper_composer.dart:365-391,495`、`paper_docx_export.dart:1-45`、`PAPER_COMPOSER_DESIGN.md:20-94,450-515`、`DOCX_EXPORT_DESIGN.md`
- M2-c/M2-d 缺口：`docs/HANDOFF_PIPELINE.md:17-18,70-78`；`FURNACE-PIPELINE-SPEC-v1.md` §5.1/§5.9/§6

## 附：本次验证（真实命令与输出，2026-11-01）

本文只新增 1 个 Markdown 文件，**没有 Dart 源码改动**，所以 `dart format` / `dart analyze` 对本次变更没有适用对象（未运行；跑了也只是验证既有代码）。
为确认文中映射的契约仍然成立，在 `E:/Projects/Furnace/app` 下真实运行了相关测试：

```
$ /d/flutter/flutter/bin/flutter test test/domain/services/package test/domain/services/questions
01:00 +1117: All tests passed!
```

（exit code 0；覆盖 `.tqb` 清单/记录/合并计划/预检、能力 A1–A10 词表、能力统计、自测统计、入库体检、扩展关系、卡组键等本文引用的纯逻辑契约。）
