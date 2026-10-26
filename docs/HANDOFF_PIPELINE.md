# 采集管线交接（handoff M1–M4）落地映射

> 更新：2026-10-27（轮次一百八十二，开发中，尚未发版：已发布 v0.6.11+30 / schema v39，本轮为 schema v40）
> 交接来源：`E:\FirsryOS\THREADRIPPER\handoff\2026-10-26-furnace-pipeline\`
> 权威规范：[FURNACE-PIPELINE-SPEC-v1.md](E:/FirsryOS/THREADRIPPER/handoff/2026-10-26-furnace-pipeline/FURNACE-PIPELINE-SPEC-v1.md)（v1.2，已按 README §3 回写实现状态）
> 边界：采集/材料生产在 App 之外；Furnace 只做`.tqb` 消费、Markdown 渲染、题型×能力记录与复习挂接。

---

## 1. 状态总览

| 规范项 | 内容 | 状态 | 主要位置 |
| --- | --- | --- | --- |
| M1 | 题目区整段 Markdown + LaTeX、`text_format`、`fullcard_` 前缀判整卡 | **已实现** | `question_markdown_view.dart`、`question_detail_page.dart`、`question_pack_record.dart`、schema v40 |
| M2-a | 扩展题关联 `extension_of` | **已实现**（数据层 + 纯逻辑 + 详情页入口） | `question_extension.dart`、`question_detail_providers.dart` |
| M2-b | 能力标签 `capability`（A1–A10） | **数据层 + 词表 + 统计口径已实现**；录入入口、T×A 报表页未做 | `question_capability.dart`、`capability_stats.dart` |
| M2-c | 材料容器（`materials/<subject>/*.md` + `assets/`） | **未做** | — |
| M2-d | 材料练习记录（用时 / 错因 / 岔路 / 重做历史） | **未做**（无表、无载体） | — |
| M3-a | 考前调度 `focus_review` | **已实现并提交**（`8058c76`） | `review_focus_tool.dart`、`review_focus.dart` |
| M3-b | 错题/变式按「专题标签 + 能力 A」建卡组 | **部分**：卡组键纯逻辑已实现；6:2:2 配额与自动挂接未做 | `review_deck_key.dart` |
| M4 | `zip_check.py` / `tqb_verify.dart` 联合契约门禁 | **工具已就位并实测通过**；无 CI，列入发布前手动门禁 | `app/tool/tqb_verify.dart` |

## 2. M1：整段 Markdown + LaTeX

### 2.1 .tqb 可选字段

- `text_format`：`"plain"`（缺省）/ `"markdown"`；缺省或 plain 时保持旧渲染行为（历史包不受影响）。
- 解码：`app/lib/domain/services/package/question_pack_record.dart` 的 `QuestionPackRecord.textFormat`（常量 `kQuestionPackTextFormatPlain` / `kQuestionPackTextFormatMarkdown`），未知值报 `questions[i].text_format` 错误。
- 导出：`app/lib/data/package/question_pack_source.dart` 仅当 `textFormat == "markdown"` 时写回 `text_format`。

### 2.2 数据库（schema v40）

- `app/lib/data/database/tables.dart` 的 `Questions` 新列：`textFormat`（NULL = plain）、`extensionOf`、`capability`（JSON 数组字符串）。
- `app/lib/data/database/database.dart`：`schemaVersion = 40`、`_upgradeV39ToV40()`、`_ensureColumns()` 三列自愈探测；`database.g.dart` 由 build_runner 重新生成。

### 2.3 渲染组件与接线

- 组件：`app/lib/features/questions/presentation/question_markdown_view.dart`
  - `questionTextFormatIsMarkdown(String?)`：`null/`空/`plain`/`未知 → false；`markdown`（trim + 小写）→ true。
  - `questionMarkdownRendersAsMarkdown(String)`：代码栅栏与 `$ / $$` 是否配对，结构不完整返回 false（退回 `SelectableText`，不硬渲染）。
  - `MarkdownQuestionText`：`markdown=false` → 原 `QuestionRichText`；`markdown=true` → `SelectionArea` + `GptMarkdown(useDollarSignsForLatex: true)`。
- 接线：`app/lib/features/questions/presentation/question_detail_page.dart` 的题干、选项、答案、解析、理由统一走 `MarkdownQuestionText`（由 `question.textFormat` 决定）。
- 行内图片占位：仍由 `app/lib/domain/services/questions/question_stem_image_plan.dart` 解析 `［图N］` / `[图N]` / `【图N】`。

### 2.4 fullcard_ 整卡快照

- `planQuestionStemRender(..., hasFullcardImage:)` 新增可选入参；B0 规则：媒体文件名（小写）以 `fullcard_` 开头 → 直接 snapshot，不看图片尺寸，优先于 B1（尺寸 ≥1000×≥400）与 B2（单图 + 占位 ≥2 且尺寸未知）。
- 详情页传入：`images.any((image) => image.fileName.trim().toLowerCase().startsWith("fullcard_"))`。

## 3. M2：扩展题与能力标签

### 3.1 extension_of（扩展题挂母题）

- 值 = 母题的组卷网题号（`zujuan_question_id`），不建外键；母题未导入时只显示题号。
- 数据层：`QuestionPackRecord.extensionOf` → `QuestionDraft.extensionOf` / `updateFromPack(extensionOf:)` → `Questions.extensionOf` → 导出回写 `extension_of`。
- 查询：`app/lib/data/repositories/question_repository.dart` 的 `byZujuanQuestionId(String)`（同题号多行取 updatedAt 最新）与 `questionsByExtensionOf(String)`（题号升序，serialNo 为空排最后）。
- 纯逻辑：`app/lib/domain/services/questions/question_extension.dart`——`buildQuestionExtensionIndex` 建母子索引，防御自指/互指/悬空/重复；迭代父链不递归。
- UI：`question_detail_providers.dart` 的 `questionExtensionLinksProvider`（async family by questionId）→ `QuestionExtensionLinks`（parent / children / isExtension / isEmpty），详情页显示「扩展自 …」入口与子题列表。

### 3.2 capability（A1–A10）

- 值：`["A3","A7"]`，按 `^A(10|[1-9])$` 校验、去重、按数字升序（A2 < A10）。
- 数据层：`QuestionPackRecord.capability` → DB `Questions.capability`（JSON 字符串），仓储侧 `encodeQuestionCapability` / `decodeQuestionCapability` 负责编解码与脏数据容错。
- 词表：`app/lib/domain/services/questions/question_capability.dart`（`QuestionCapability` 枚举 A1–A10，code / labelZh / definitionZh / `fromCode`；`capabilityCodesFromJson` / `capabilityCodesToJson`；题型中文名）。
- 统计口径：`app/lib/domain/services/questions/capability_stats.dart`（`CapabilityAttempt`、`CapabilityStatsReport.of(...)`：单能力计数、题型×能力交叉表、最弱能力、样本不足标记 `kCapabilityMinSamplesForConclusion = 3`）。
- UI：详情页能力点 chips（文案 = code + 中文名，未知 code 原样显示）。

### 3.3 未做（明确列出）

- 材料容器：没有「学习材料包」导入/浏览入口，仍只有 `mindnet.material/1` 知识点信封。
- 练习记录：没有 material/题目练习记录表（time_spent / result / error_cause / detour / redo_history），因此 T×A 报表页也缺数据源。
- capability 录入入口（导入包可以带，手工编辑题时不能改）。

## 4. M3：复习联动

- `focus_review`（已提交 `8058c76`）：`days`（默认 7，上限 90）、`limit`（默认/上限见工具）、`dry_run` 默认 true；只改 `due_at`，不拉新卡/已到期/超 horizon；对话内可撤销。
- 卡组键：`app/lib/domain/services/questions/review_deck_key.dart`——`review_deck|<subjectKey>|<capabilityCode>|<tagPath>`，`reviewDeckKey` / `parseReviewDeckKey` / `sortedReviewDeckKeys`，脏数据返回 null 不抛。
- **未做**：新题:变式:错题重做 ≈ 6:2:2 的自动配额；错题按 1/3/7/21 天重做自动建卡。

## 5. M4：契约门禁

无 CI，发布前手动跑：

```powershell
# 包结构（Python 标准库）
& "<python>" E:/FirsryOS/THREADRIPPER/handoff/2026-10-26-furnace-pipeline/tools/zip_check.py "<包路径>.tqb"
# App 解码侧（App 仓库内）
cd app
dart run tool/tqb_verify.dart "<包路径>.tqb"
```

实测（2026-10-27，真实包 `furnace-zujuan-2026-10-26T13-36-19.tqb`，13,078,673 B）：

- `zip_check.py`：`OK 30 records, 60 media, 60 referenced, bytes 13078673`
- `tqb_verify.dart`：`format=furnace-question-bank version=1 questions=30 media=60` / `decoded records=30 mediaBytes=60` / `OK`

## 6. 本仓库里可对照的既有文档

- `docs/DATA_MODEL.md` §29：schema v40 三列（`text_format` / `extension_of` / `capability`）与导入语义。
- `docs/PROGRESS.md` 轮次一百八十二：本轮改动清单与验证数字。
- `docs/FEATURE_MATRIX.md`：顶部增补表新增行。
