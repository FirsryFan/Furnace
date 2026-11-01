# Furnace 交接文档（完整版）

> 撰写时间：2026-10-29。读者：下一个接手这个仓库的人或 agent。
> 目标：不读完整对话历史，也能安全接上开发、测试、构建与发布。
> 基线事实（本文撰写时实测）：仓库 `E:/Projects/class-productivity`，分支 `main`，HEAD `14f8d8a`（与 `origin/main` 一致），工作树干净；最新 tag `v0.6.12`；app 版本 `0.6.12+31`；schema `v41`。
> 逐轮细节在 [PROGRESS.md](PROGRESS.md)（758 KB，按时间倒序、每轮一节）；功能是否交付以 [FEATURE_MATRIX.md](FEATURE_MATRIX.md) 顶部增补表为准；数据表语义以 [DATA_MODEL.md](DATA_MODEL.md) 为准。

---

## 0. 先读这几句

1. **这是用户自己的本地优先应用**，不是通用产品：Windows + Android 同一套 Flutter 代码，数据全在本机（Drift/SQLite），不联网也能用；联网只用于用户自己配置的 AI API、组卷网取题、网页抓取。
2. **纪律优先于速度**：动 schema、动 l10n、动 git 前先看第 5、10、12、13 节；本仓库已经因为「read→write 截断 ARB」「迁移后版本号被盖高却缺列」「测试跑着改 lib 源码」各出过一次事故。
3. **用户的工作方式**（历史记录）：直接指出问题，期望先去取证、不辩解；优先做「功能设计」，其次「外观」，代码实现要熟练但不应为了重构而重构；不要拿琐碎问题反复问他；以 Android 手机为主、Windows 为辅；重要方向先讨论清楚再动手。
4. 用户长期反馈（据 PROGRESS 记录）：**「不要过度审查，大胆去做；实际上的功能可能比你想得简单直接，尤其避免简单任务复杂化。」**

---

## 1. 当前状态速览

| 项 | 值 | 证据 |
| --- | --- | --- |
| 仓库 / 分支 | `E:/Projects/class-productivity` / `main` | `git status -sb` |
| HEAD / 远端 | `14f8d8a` / `origin/main=14f8d8a` | 实测 |
| 最新 tag | `v0.6.12`（tag 列表 v0.6.0–v0.6.12） | `git tag` |
| app 版本 | `0.6.12+31` | `app/pubspec.yaml:4`、`app/lib/core/app_info.dart:11/15` |
| DB schema | `v41`（Drift） | `app/lib/data/database/database.dart:171` |
| 数据表 | 57 张 `class X extends Table` | `app/lib/data/database/tables.dart` 实测 |
| 代码规模 | `app/lib` 388 个 .dart；`app/test` 408 个 *_test.dart | 实测 |
| 文档 | `docs/` 43 份 | 实测 |
| 静态门禁 | `dart analyze lib test` = 88 issues / 0 error / 0 warning | 轮次 186 记录（与 v0.6.12 基线持平） |
| 全量测试 | `+6817 ~2: All tests passed`，14:43，TEST_EXIT=0 | `E:/dsh-tmp-aot/test-186-full.txt` |
| v0.6.12 产物 | zip 20,432,656 B；apk 98,728,918 B（SHA 见 §13） | `dist/`（gitignore） |
| AI 工具 | 29 个（`ToolRegistry.forApp`） | `app/lib/features/ai/domain/tool_registry.dart` |
| l10n | zh ARB 3728 行 / en ARB 3821 行 | 实测 |

**最后一条已发布的包是 v0.6.12**；之后轮次 185–186 做了「用户评测板块 v1.0（schema v41）+ P2/P3」，**未 bump 版本、未出包**（用户没要求）。所以 `main` 比最新 tag 多两个提交的历史改动，但 `app_info.dart` / `pubspec.yaml` 仍是 0.6.12+31。

---

## 2. 这个项目是什么

Furnace 是一个本地优先的**学习 + 生产力应用**，核心闭环：

- **Thread（线程/任务）**：任务有优先级、依赖、下次动作、状态；有排序与推荐。
- **Time（时间）**：日历/日视图/周视图、时间块、模板、任务占时间、安排列表（全部/今天）。
- **Knowledge（知识/闪存卡）**：知识点、卡模板、FSRS 复习、每日新卡/复习额度、卡组（标签树）、复习提醒（本地通知）。
- **题库（Questions）**：题目实体（题号、题干、选项、答案、解析、图片、标签、题源、能力点、扩展关系）；自测判分与作答记录；错题本；搜索/筛选/排序/批量；题库包 `.tqb` 导入导出（含按组卷网题号更新已有题）。
- **题源与组卷（Zujuan / Paper）**：组卷网按知识点/章节/试卷取题、整卷取题、答案与解析截图；内部组卷器按约束组卷、复制卷面、导出 Word。
- **AI「智能化」**：内置 agent（多轮工具调用）负责收题、找题、组卷、排计划、管理任务/时间/标签、造卡、提前复习（focus_review）、写文档；所有写操作有审批/撤销。
- **评测板块**：本地认知/能力评测（10 个任务、19 个统计量、10 项能力、9 个认知参数），给 Thread 权重建议、可导出 `.cogprofile`。
- **标签**：一棵标签树；可限定用途边界（time/question/knowledge/task/flashcard）并向下继承。

用户是**学生**，目标不是「记笔记」，而是把「题目 → 能力 → 复习 → 计划」串成闭环。所以题库、组卷网、闪存卡、AI 收题是这个应用的重心；主题/外观是第二优先级。

---

## 3. 仓库与环境

### 3.1 目录结构

```text
class-productivity/
├─ app/                     # Flutter 工程（所有命令都在这里跑）
│  ├─ lib/
│  │  ├─ app/               # app.dart、shell/home_shell.dart（导航目的地）
│  │  ├─ core/              # app_info.dart、theme/（design_tokens、theme_profile）
│  │  ├─ data/              # database/（tables、database、database.g.dart）、repositories/
│  │  ├─ domain/services/   # 纯逻辑：srs/、questions/、package/、cognitive/、tags/、...
│  │  ├─ features/          # 12 个功能域（见 §4.2）
│  │  └─ l10n/              # app_zh.arb / app_en.arb + 生成的 app_localizations*.dart
│  ├─ test/                 # 408 个 *_test.dart（镜像 lib 目录）
│  ├─ android/  windows/    # 平台工程（图标、权限、签名）
│  └─ tool/                 # tqb_verify.dart 等开发工具
├─ docs/                    # 43 份设计与进度文档（见 §17）
├─ scripts/                 # bootstrap.ps1 / build_windows.ps1 / build_android.ps1
└─ dist/                    # 发布产物（gitignore，不进 git/不推远端）
```

### 3.2 环境（记录值，本次未逐项复验）

- Flutter **3.47.2 stable**（本次 `flutter --version` 已确认）。
- 旧交接文档记录：Dart 3.13.2；Android SDK `E:\Document\AndroidDev\sdk`、gradle-home `E:\Document\AndroidDev\gradle-home`；JDK `C:\Program Files\Microsoft\jdk-21.0.12.101-hotspot`；aapt2 在 `E:\Document\AndroidDev\sdk\build-tools\36.0.0`。
- **构建必须从 ASCII junction 出发**：`E:\Document\furnace-build`（中文路径会让 AOT/打包失败）。产物实际在 `E:\Document\furnace-build\build\windows\x64\runner\Release`。
- Android 签名证书 SHA-256 `57de8b8f…f32e2db2`（与历史发布件一致；历史记录，本次未重新打印）。

### 3.3 常用命令（都在 `app/` 下）

```powershell
flutter pub get
flutter gen-l10n                                  # 改完 ARB 必跑
dart run build_runner build --delete-conflicting-outputs   # 改表/drift 必跑
dart format <本轮改动的 dart 文件>                 # 只 format 改动文件！
dart analyze lib test                             # 必须带上 test
flutter test --concurrency=1                      # 全量门禁（约 14–16 分钟）
flutter test test/features/xxx_test.dart          # 单跑
```

构建/发布（在仓库根跑）：

```powershell
powershell -File scripts/build_windows.ps1
powershell -File scripts/build_android.ps1
```

### 3.4 网络与 git

- 本机 **github.com HTTPS 被阻断**（TLS reset），`git push` 不可用。
- 推送改走 GitHub REST（git data API）：`E:/dsh-tmp-aot/rest-push.ps1`（代理 `127.0.0.1:7890`，必须 `pwsh -NoProfile -File` 运行）。日志里的 `BLOB_MISMATCH` 是 7 位短 sha 噪音，以 `REF_UPDATED` / `REMOTE_VERIFY equals_local=True` 为准。
- tag 同样走 REST：`E:/dsh-tmp-aot/rest-tag-0xx.ps1`（POST /git/tags + /git/refs，用 API GET /git/tags 复核 TAG_TARGET）。
- 远端：`https://github.com/FirsryFan/Furnace`（公开仓库）。

---

## 4. 架构总览

### 4.1 分层

- **data**：Drift 数据库 + repositories。所有写库入口在 repository；UI 通过 Riverpod provider 读，写操作后自增 `databaseRevision` 触发响应式刷新。
- **domain/services**：纯 Dart 逻辑（SRS/FSRS、题目渲染计划、题库包编解码、组卷、认知排序、tag 用途、评测指标…）。纯函数优先，便于单测。
- **features/<域>**：`application/`（服务、provider 接线）、`domain/`（该域模型）、`presentation/`（页面与组件）。
- **app/**：`app.dart`（主题/缩放/l10n 外壳）、`shell/home_shell.dart`（顶层导航：任务/时间/知识/题库/智能化/设置等，`shellDestinations()` 定义目的地）。
- 状态管理：**Riverpod**（大量 `Provider / AsyncNotifier`）；不需要第二套状态方案。

### 4.2 features 目录（12 个域）

`ai`（内置 agent）、`anki`（闪存卡/复习）、`assessment`（用户评测板块，新的正式版）、`cognitive`（知识网络图、能力画像、旧四项小测）、`mindmap`（思维导图）、`packages`（知识包）、`questions`（题库/收题/详情/组卷）、`settings`（设置页）、`tags`（标签树）、`tasks`（任务）、`thread`（线程/排序）、`timeboard`（时间/日历）。

注意：**旧「能力测评 MVP」（v38 `ability_scores`）与新「评测板块 v1.0」（v41 `cog_*` 八表）两套并存**；设置页入口已是新的「评测与认知档案」，旧页面与旧表保留但无入口。

---

## 5. 数据层（schema v41）

### 5.1 57 张表分组

- **基础/设置/标签**：`Profiles`、`LocalSettings`、`Tags`、`ObjectTags`、`Themes`、`Attachments`
- **任务/时间**：`Tasks`、`TaskDependencies`、`TimeBlocks`、`TaskTimeBlocks`、`TaskTemplates`、`CompletionLogs`、`TimeTemplates`、`TimeViewSettings`
- **知识/闪存卡**：`KnowledgePoints`、`CardTemplates`、`CardStates`、`ReviewLogs`、`ExposureLogs`、`KnowledgePackages`、`PackageItems`、`ClozeSlots`、`ClozeHistory`、`BoostEntries`、`ReviewGroupPlans`
- **Thread/认知**：`ThreadStates`、`ThreadRankSettings`、`DiffusionLogs`、`KnowledgeEdges`、`CognitivePriors`
- **题库/题源**：`Questions`、`QuestionOptions`、`QuestionAttempts`、`QuestionSerialCounters`、`ReasoningChains`、`ReasoningSteps`、`HandwritingIntakeRuns`、`HandwritingProposals`、`MaterialIntakeBatches`、`MaterialIntakeProposals`、`MaterialIntakeUndoLogs`
- **AI**：`AiConversations`、`AiMessages`、`AiActions`
- **旧测评（v10）**：`AssessmentSessions`、`AssessmentResponses`
- **旧能力小测（v38）**：`AbilityScores`
- **评测 v1.0（v41，cog_ 前缀）**：`CogAssessmentTasks`、`CogAssessmentSessions`、`CogAssessmentTrials`、`CogAssessmentMetrics`、`CogAbilityEstimates`、`CogCognitiveParams`、`CogTaskAbilityMappings`、`CogAbilityParamMappings`
- **思维导图**：`MindMaps`、`MindNodes`

### 5.2 schema 版本与迁移惯例

`database.dart` 的 `schemaVersion` 当前 **41**；迁移链 `_upgradeV5ToV6` … `_upgradeV40ToV41` 完整存在。**新增列/表的固定流程**：

1. `tables.dart` 加可空列或新表类（新列尽量可空，NULL 有明确语义）。
2. `database.dart`：`schemaVersion` + 1；新增 `_upgradeVnToVn+1()`（只加列/建表，**不回填**）；在 `_ensureColumns` 的表→期望列清单里同步（用于「版本号被盖高却缺列」的自愈）。建新表也要在 `_ensureColumns` 里能建（`_tableExists` 探测；避免在早期迁移阶段引用尚不存在的表）。
3. `dart run build_runner build --delete-conflicting-outputs`，**提交 `database.g.dart`**（本项目把生成代码入库）。
4. 加迁移测试（如 `v41_migration_test.dart`）。
5. 更新 `docs/DATA_MODEL.md` 新章节。
6. 跑 scoped 测试 + `dart analyze lib test`。

**坑**：迁移测试里 `_tableFor` 需要显式 case；v37 加 `tags.usage_codes` 时首跑就报 `Invalid argument(s): unknown table tags`。旧表名冲突要用前缀规避（v41 用 `cog_` 避开 v10 的 `assessment_*` 与 v38 `ability_scores`）。

### 5.3 数据安全

- 题库包导入前自动备份：`question_pack_backups/题库备份-yyyyMMdd-HHmmss-SSS.tqb`；保留策略 prune(10)。
- 一键恢复、清空「学习数据」在设置页；删除类操作有确认。
- 备份/导出文件都落在本机；`.tqb` 是 zip（题目 JSON + media），`.cogprofile` 是 JSON。

---

## 6. 功能地图（按域）

> 详细逐条状态见 [FEATURE_MATRIX.md](FEATURE_MATRIX.md) 顶部增补表；这里给「有什么 + 关键代码位置」。轮次号可用于查 PROGRESS。

### 6.1 Thread / 任务

- 任务实体：优先级、状态、截止、下次动作、依赖、标签、时间估计；`tasks` 表 + `features/tasks`。
- Thread 排序：认知排序档位、反事实 `V(π)`、留存探针、注意力可用性 `α(τ)`、节律层（轮次 44–58）；`thread` 域 + `ThreadRankSettings`。
- 今日计划：`plan_today` AI 工具 + 任务页「今日安排」；顺延/冲突警告（轮次 46/48）。
- 任务详情可加标签（受 `TagUsage.task` 边界约束）。

### 6.2 Time

- 日历/日视图/周视图、时间块拖拽、任务占时间、时间模板（轮次 2/4/5 起）。
- 行高可拖拽自由缩放（8 档 detents，22–264 px；`calendar_page.dart`、schema v36 `time_view_settings.hour_height`）。
- 「安排」页支持全部/今天过滤（`time_board_page.dart`）。
- 时间块标签选择器按用途 `TagUsage.time` 过滤。

### 6.3 知识 / 闪存卡

- 知识点、卡模板、FSRS 复习（唯一到期日权威）、自由挖空、错题强制绑定（轮次 49/67）。
- 每日新卡/复习额度：`ReviewGroupPlans`（标签树即卡组）；`review_service.dart` 构建队列时应用额度。
- **卡组主界面（v0.6.12，轮次 184）**：`knowledge_page.dart` 第一 Tab = `deck_list_page.dart`——第一行「全部」+ 每个卡组一行（新卡 done/target、复习 done/target 或「不限」、进度条、今日达成徽标）+「未分组」行 + 空态；点行进该卡组的背诵界面（`ReviewPage(scopeTagId/scopeTitle/onlyUngrouped)`）。纯逻辑 `app/lib/features/anki/application/deck_progress.dart`（`deckProgressFor(ReviewGroupLoad)`）。
- 复习节奏：新卡每 5 张复习插 1（`review_pacing.dart`，`paceNewCards`）、重插上限、跳过/结束（轮次 169）。
- 复习间隔三挡：`review_retention`（longer .80 / standard .85 默认 / shorter .90），注入 `FsrsParameters(requestRetention:)`（v36）。
- 卡组复习：一次复习可见全文、卡组设置页、未分组一键归组。
- 本地复习提醒（v28 `review_reminder_service.dart`）。

### 6.4 题库

- 题目实体：`Questions` 表（v12 起，v24 题号+图片，v26 题源，v30 title，v40 text_format/extension_of/capability）；`question_repository.dart` 的 `ingest` 负责指纹去重与题号高水位分配。
- 题号：`question_serial_counters` + 高水位（v33）；列表/详情/复制/搜索/组卷都带题号；详情页可「上一题/下一题」翻页（v0.6.8）。
- 图片：`question_media_store.dart`（role = stem/answer/solution；排序；删除）；整卡快照判定 `question_stem_image_plan.dart`（B1 已知尺寸 ≥1000×≥400、B2 占位次数、v40 新增 B0 `fullcard_` 前缀直接判 snapshot）。
- 渲染：`question_media_view.dart` 的 `QuestionRichText`（旧，只认行内 `$…$`）；v0.6.12 新增 `question_markdown_view.dart` 的 `MarkdownQuestionText`（整段 Markdown+LaTeX；代码栅栏/美元符不配对时退回纯文本；`text_format=markdown` 时启用）。
- 自测：详情页选择题客观判分（v0.6.4）+ 作答记录 `question_attempts`（v32）；错题本筛选与「错 N 次」徽标（v0.6.5）；自测整页防剧透（v0.6.8）。
- 列表：搜索、标签筛选、可读摘要（v0.6.1）；排序偏好落盘 `settings.questionLibrarySortMode`（v34）；多选批量打标签/导出选中/批量删除（v0.6.1）。
- 题库包 `.tqb`：导出/导入（轮次 136–137）、导入预检、选择性导出、按组卷网题号**更新**已有题目（轮次 145）；格式定义在 `question_pack_record.dart`（严格校验、未知键忽略、最多 5000 题）。
- 收题：**只剩内置 agent 一条路**（v0.6.12 移除题库页「收题/拍照整理」入口与详情页「去收题」）；`create_questions` 工具一次 ≤100 题、重复题返回已有题号、撤销只删本次新建。旧 `QuestionIntakePage` / `HandwritingQueuePage` 代码保留但无界面入口。

### 6.5 题源与组卷 / Word

- 组卷网（zujuan.xkw.com）：按学段/学科/知识点/章节/试卷/省份/年份/难度/题型检索；整卷取题；通过本地扩展桥读答案与解析（图片形态）；默认用 `ReadZujuanPaperTool` / `ComposePaperTool`。
- 检索词分学科长度（v0.6.11）：理科 15–30 字、文科 20–40 字（`zujuan_keywords.dart`；标准侧 `keywords.mjs --band`）。
- 能力动作找题：`QuestionCapability` A1–A10 + `capability_stats`（v40）；AI 工具 `find_questions_by_capability`；详情页能力点 chips 与扩展题/母题入口（v40）。
- 组卷器：按约束（学科、知识点、难度、题数、每知识点上限）组卷、开始说明、复制卷面、缺口解释；题源链接可改。
- Word 导出：docx 生成题目卷（轮次 122；设计见 DOCX_EXPORT_DESIGN.md）；外部 `paper-composer` 技能也可排版。

### 6.6 AI「智能化」

详见第 7 节。要点：29 个工具、审批 + 撤销、思考（reasoning）可见/落库/可中断、运行时间线、图片附件（拍照收题）、skill 容器、focus_review 提前复习。

### 6.7 标签

- 标签树：父子、排序（v29 落盘）、颜色/图标；`tag_tree_page.dart`。
- 用途边界（v37）：`tags.usage_codes`（逗号分隔 5 种用途；NULL 继承父级；整链无声明 = 不限制）；`TagUsageResolver`（domain/services/tags/tag_usage.dart）+ `tag_usage_scope.dart` 提供统一的选择器过滤与空态。
- 已接边界的选择器：时间块、闪卡卡组/加标签、题库批量打标签、任务详情、认知测评选择范围；**未接**的还有 AI 建议标签、组卷选标签、知识网络入口、题库包标签路径（见 §16）。

### 6.8 评测板块（v41，正式版）

详见第 9 节。旧四项小测（v38）仍保留代码与 `ability_scores` 表，但入口已被新的「评测与认知档案」取代。

### 6.9 外观

- 主题：ThemeProfiles、亮/暗、配色；设置页可切换。
- 新应用图标（v0.6.11）：Android `mipmap-*/ic_launcher*.png` + `mipmap-anydpi-v26/ic_launcher.xml` + `res/values/colors.xml`、Windows `windows/runner/resources/app_icon.ico`（炉膛 + 火焰，深绿底）。
- 页面缩放（v0.6.10）：`app/lib/app/page_zoom.dart` 的 `PageZoom`（整体缩放：反算逻辑尺寸 + 除以 scale + ClipRect/OverflowBox/Transform.scale），设置页可调。
- 设计 token 基础层：`app/lib/core/theme/design_tokens.dart` —— `AppSpacing`（4pt 栅格）、`AppRadius`（control6/card10/sheet14/pill999）、`AppTokens extends ThemeExtension`；`theme_profile.toThemeData` 装入扩展并让 `cardTheme/dialogTheme` 使用统一圆角。**页面级 token 迁移尚未做**（§16）。

### 6.10 数据安全 / 权限 / 通知

- 备份/恢复/保留策略/清空学习数据（§5.3）。
- Android 通知权限、本地复习提醒；Android minSdk 24 / targetSdk 36 / compileSdk 36。
- 无云同步（明确不做，见 PRIVACY.md）。

---

## 7. AI 子系统（内置 agent）

### 7.1 入口与调用链

`ai_chat_page.dart`（对话页）→ `AgentLoop`（features/ai/domain/agent_loop.dart，约 1600 行）→ `ModelAdapter`（openai 兼容 SSE）→ 工具注册表 `ToolRegistry.forApp(db, tags)` → 工具执行 → 写库/撤销记录。

- Provider 配置在设置页（base URL / model / API key / 温度 / max rounds）；API key 未填时**不得发任何网络请求**（硬约束）。
- SSE 解析：`sse_assembler.dart` 只取 usage/content/tool_calls，**reasoning 已单独解析**（v0.6.11 起支持 `reasoning_content|reasoning|thinking`）；事件有 `ModelTextDelta / ModelReasoningDelta / ModelToolCall / ModelTurnDone / ModelTurnCancelled / ModelFailure`。
- 可取消：`CancellableModelAdapter.cancelActiveTurn` + `AgentLoop.cancel()`；partial 文本保留落库；停止按钮 key `aiStopButtonKey`。
- 工具调用必须**原子**：同一轮的多个 tool_calls 与结果要作为 `TurnGroup` 成组写库对齐，否则真实 API 会因 history 缺 tool 消息返回 400（轮次 9 后的真实事故）。
- 轮数：`AiConfig.defaultMaxRounds=30`、`maxMaxRounds=60`、`minMaxRounds=1`（v0.6.12 从 8/20 提高，用户要求；设置页 Slider 自动跟随常量）。
- 上下文：`TurnUsage`（prompt/completion/cache 命中、生成耗时、in-flight 字数/耗时、contextWindowTokens）；`turn_usage_panel.dart` 实时显示。

### 7.2 运行时间线（v0.6.12）

- `AgentTurnState.steps`（`List<AgentStep>`）：`AgentStepKind{model,tool}`；每个模型轮、每次工具调用各有开始/结束状态（pending/executing/done/failed/cancelled、等待批准），字段含 `startedAt/finishedAt`、`toolName/title/detail/summary/ok`。
- UI：`app/lib/features/ai/presentation/widgets/run_timeline.dart` —— 运行中展开、每秒刷新当前行耗时、结束折叠「本轮 N 步」、可展开/收起；接在思考面板与流式回答之间（`ai_chat_page.dart` 约 :658）。
- **只在内存**，重开对话不留步骤历史（未做落库）。

### 7.3 工具清单（29 个，注册顺序）

`fetch_page`、`query_tasks`、`manage_task`、`query_schedule`、`manage_time_block`、`evaluate_problem_fit`、`plan_today`、`ingest_material`、`apply_material_intake`、`check_transcribe_run`、`find_similar_questions`、`find_questions_by_capability`、`read_question`、`read_questions_by_serials`、`read_zujuan_paper`、`compose_paper`、`audit_question_intake`、`get_learning_advice`、`recommend_practice`、`review_metrics`、`create_knowledge_cards`、`create_questions`、`link_card_tags`、`manage_review_plan`、`focus_review`、`delete_content`、`query_content`、`create_tags`、`create_document`。

- 注册表是**静态列表**（无插件/运行时扩展），平台门控用 `tool.availableOnCurrentPlatform`；每轮按平台发 `modelSpecs`。
- 工具文件在 `app/lib/features/ai/tools/`（21 个文件，按域拆分）。

### 7.4 审批、撤销与写操作纪律

- 写操作走审批（`_ApprovalPanel`）；每个写工具实现 `riskFor / reversibleFor / beforeJson`，撤销按 `AiActions` + `agent_loop` 的 undo case 执行。
- 撤销必须在「什么都不做」时明确返回 null（`focus_review` 的空计划 beforeJson 返回 null，否则撤销会显示成功）。
- 删除类工具逐条/批量都要求确认；`create_questions` 撤销只删 `created_ids`。
- AI 不允许「凭空出题」：题源必须来自拍照/粘贴/组卷网包；提示词口径统一为「我不凭空出题；把题目拍照或粘贴发给我，我誊写进题库」。

### 7.5 图片 / vision / skill

- `vision_payload.dart`：长边降采样、maxBytes 重编码；`ai_attachment_store.dart` 存取附件；对话页支持拍照/选图（微信聊天记录拖入照片也支持）。
- skill：设置页安装/选择；skill 进提示词、可被工具调用；格式见 SKILL_FORMAT.md。

---

## 8. 题库包与采集管线（handoff M1–M4）

外部采集 agent 在会话外交接：`E:/Workspaces/Furnace/10-projects/furnace-pipeline/`（只读、无凭据、未进仓库）；App 侧按 `FURNACE-PIPELINE-SPEC-v1.md` 接入（轮次 182），状态见 [HANDOFF_PIPELINE.md](HANDOFF_PIPELINE.md)：

| 片 | 内容 | 状态 |
| --- | --- | --- |
| M1 | 题目区整段 Markdown + LaTeX（`text_format`）；短题卡 `fullcard_` 前缀判整卡，不再只看尺寸 | 已做（`MarkdownQuestionText`、schema v40） |
| M2 | `extension_of`（扩展题/母题）、`capability`（A1–A10）；详情页 chips/扩展入口 | 部分：字段与 UI 已做；材料容器与材料练习记录**未做** |
| M3 | 复习联动（`focus_review` 提前复习） | 已由轮次 181 覆盖，规范已回写 |
| M4 | 契约测试 | `app/tool/tqb_verify.dart` 已落地；无 CI，作为发布前手动门禁 |

`.tqb` 包结构：zip，题目记录 JSON（`question_pack_record.dart` 严格校验）+ `media/` 文件；整卡命名 `media/stem_<bankId>-<qid>.png`，解析图 `media/answer_<bankId>-<qid>_<n>.<ext>`；未知键向后兼容忽略；`pack_path` 必须是相对 POSIX 路径。

---

## 9. 评测板块 v1.0（v41）

四层：**项目 Task → 评测数据 → 能力指标 → 认知模型参数**。本地优先、不联网、不做防作弊、不给人群百分位；每个估计带 `uncertainty`，个体内基线；用户可覆盖（`user_override` 永远信任）。

- **数据**：`cog_assessment_tasks / sessions / trials / metrics`、`cog_ability_estimates`、`cog_cognitive_params`、`cog_task_ability_mapping`、`cog_ability_param_mapping`（v41 八表）；`cognitive_profile_repository.dart`（792 行，`AssessmentStore` 实现）。
- **任务**：10 个（含 2-back、Stroop、任务切换、疲劳块、决策疲劳等；`task_registry.dart`；`design_version` 可幂等重写任务注册表）；`stimulus_generators.dart` 用 `math.Random(seed)` 生成确定性刺激。
- **指标**：19 个统计量（`assessment_session_service.dart` 的 `computeSessionMetrics`：rt_median / rt_iqr / accuracy / hit_rate / false_alarm_rate / d_prime / rt_cost / stable_span / max_span / rt_slope / variance_drift / decision_drift / switch_cost / switch_rt / repeat_rt / conflict_cost / congruent_rt / fish_trial_accuracy / lapse_slope / default_choice_rate）。
- **能力/参数**：10 项能力、9 个参数；映射可配置（`assessment_mapping.dart`、seed 只在表空时灌）；质量标记**只上调 uncertainty（每项 +0.1）**，不删数据。
- **会话**：`completeSession` 串「指标 → 质量标记 → 能力合并（uncertainty 加权中位数）→ 参数推导 → 落库 → 读回」；中途退出落 `aborted`、不进估计。
- **导出**：`.cogprofile`（format_version 1.0 + 10 能力 + 9 参数 + exported_at + privacy）；档案页 AppBar 导出按钮，`FilePicker.saveFile` + provider seam；文件名 `furnace-cogprofile-yyyyMMdd-HHmm.cogprofile`。
- **Thread 接口**：`cognitive_params_provider.dart`（`CognitiveParamsProvider` / `ThreadWeightSuggestion` / `threadWeightSuggestions`；`kThreadParamMaxUncertainty=0.4`，缺估计/高不确定回退默认、`user_override` 信任；25 例）；Riverpod 接线 `cognitiveParamsProvider` / `threadWeightSuggestionsProvider`，**消费侧（ThreadFlow 实际采纳）未接**。
- 未做：stale 自动扫描（`design_version` 升级后旧测量标 `stale` 只留列与读侧约定）、`decision_fatigue` 默认关闭（provisional）、`too_slow` 用 3000ms 绝对占位、真机跑通十个任务。

---

## 10. l10n 与文案

- **只有 Lead 写 l10n**；队友不要改 ARB。
- ARB 只能 `tools.edit`（追加/精确替换），**禁止 read→write 整文件覆盖**（`tools.read` 默认 limit 2000 会截断 3728/3821 行的 ARB，已出过一次事故，用 git checkout 恢复）。
- 改完跑 `flutter gen-l10n`；缺逗号会 `FormatException`。
- 新增 key 要带 `@metadata`；中英同步；注意 key 冲突（历史上 `assessmentResultTitle` 已存在，新增前先 grep）。
- 当前规模：`app_zh.arb` 3728 行、`app_en.arb` 3821 行；生成文件 `app_localizations.dart/_en/_zh`。
- 用户明确的叫法：「智能化」（不是「AI 对话」）、「安排」、闪存卡（不叫「记忆卡」）。

---

## 11. 团队协作模式（本项目的开发方式）

- 历史配置：Lead + 3 个长期 teammate：
  - **reasoning-core**：跨学科能力动作词表/思维链提示与解析、纯 Dart 逻辑（如 `deck_progress.dart`、`capability_stats.dart`、评测 domain 指标）。
  - **threadflow-engine**：threadflow 两段式（可行域过滤 + MindNet 有效性排序与领域配额）、设置/组卷/复习 UI 接线。
  - **question-intake**：收题页/拍照整理/题目详情/题库/组卷 UI。
- **坑**：`spawn_teammate` 对同名成员报 `teammate name "..." was already used in this Team`（上一会话的成员在本 Team 里仍在册）。此时 `list_agents` 会显示三人 inactive，**用 `send_message` 复活并派新任务**，不要新建同名成员。
- 任务板：`team_task_create` 建任务（写清作用域、验收标准、依赖）→ 队友 claim → complete；Lead 用 `team_task_list/get` 跟踪。
- **写作用域互斥**：每个任务只写自己的文件/目录；l10n、schema 生成文件、git 提交都归 Lead。
- 队友不碰 git、不碰 ARB、不跑发布；改完自测（format/analyze/scoped）后报告，由 Lead 统一跑全量门禁、更新文档、提交、推送。

---

## 12. 门禁与质量流程

### 12.1 每轮固定门禁

1. `dart format` 只格式化本轮改动的 dart 文件（全仓 format 会改 140+ 个历史文件）。
2. `dart analyze lib test`：基线 **88 issues / 0 error / 0 warning**（只能降或持平）。**必须带 test**：`invalid_override` 只在 test 里出现。
3. 全量 `flutter test --concurrency=1`：基线 **+6817 ~2 通过**，约 14–16 分钟；日志写 `E:/dsh-tmp-aot/`；期望 `TEST_EXIT=0`。
4. 用户可见的行为变化补进 `docs/PROGRESS.md`（新轮次节）、`docs/FEATURE_MATRIX.md`（增补表）、必要时 USER_GUIDE / DATA_MODEL / 设计文档。
5. Lead 统一 commit（分片提交，消息用 `feat(...)/fix(...)/docs(...)/chore(release)`），再 REST 推送。

### 12.2 测试纪律 / 已知陷阱

- **全量测试跑的时候不要改 `lib/` 被测源码**（轮次 169/178 两次假失败/死锁教训）。
- 改公开方法签名后，**所有测试替身/fake 都要同步**（`deleteForQuestion` 曾漏改导致 analyze 报 invalid_override）。
- 组件测试用 `pump/pumpAndSettle` 要防死锁：页面 dispose 时 cancel 写库可与 `tearDown` 的 `await db.close()` 撞死（flutter test 卡 17 分钟，`--timeout` 不触发）。
- 不要依赖同毫秒写多行的排序：id 是 uuid（非单调），测试要显式递增 `now`。
- `Set` 字面量重复元素会触发 `equal_elements_in_set`，用 `Set.of`。
- 假 `ModelAdapter` 不校验 history 结构，真实 API 会 400 → 涉及 tool call 的改动最好有真实 API 冒烟（至少手工）。
- 测试里工具总数断言（现 29）随工具注册变化，新增工具要同步。
- 像素级/截图测试不稳定，别用它证明「能用」；真机未手测的功能要在文档里如实标「未验证」。

---

## 13. 发布流程（双端）

标准顺序（v0.6.12 实测走通）：

1. **bump**：`app/pubspec.yaml` version: 0.6.x+N；`app/lib/core/app_info.dart` kAppVersion/kAppBuildNumber；`test/core/app_info_test.dart` 会比对两者。
2. **文档**：`docs/PROGRESS.md` 新轮次节 + `docs/FEATURE_MATRIX.md` + `dist/RELEASE-vX.md`（dist 被 gitignore，不入库）。
3. **构建**：`scripts/build_windows.ps1` → `scripts/build_android.ps1`；Windows 打包前删 `Release\data\flutter_assets\kernel_blob.bin`（约 110 MB）。
4. **打包 Windows zip**：从 ASCII junction 暂存，用
   `[IO.Compression.ZipFile]::CreateFromDirectory($stage,$zipPath,Optimal,$false)`
   得到 **28 entries / 0 目录条目 / 0 kernel_blob**。**不要用 `Compress-Archive`**（会多写 7 个目录条目）。
5. **校验**：`furnace.exe` VersionInfo.FileVersion == 0.6.x+N；`data/app.so` 时间戳新于构建开始；`aapt2 badging`：versionCode/versionName/minSdk 24/targetSdk 36/label Furnace；`apksigner` 证书 SHA-256 与历史一致；zip entries=28、kernel_blob=0、解压大小；SHA-256。
6. **提交**：`chore(release): vX`（只含 `app/pubspec.yaml`、`app/lib/core/app_info.dart`、`docs/PROGRESS.md`；dist 三件绝不进 git）。
7. **打 tag**：`git tag -a vX -m ...`，复制 `rest-tag-0xx.ps1` 改 `$tagName` 后运行；API 复核 `TAG_TARGET`。
8. **推送**：`rest-push.ps1`，看 `REF_UPDATED` 与 `REMOTE_VERIFY equals_local=True`。

### v0.6.12 产物（实测）

| 文件 | 大小 | SHA-256 |
| --- | --- | --- |
| `dist/Furnace-0.6.12-windows-x64.zip` | 20,432,656 B（28 entries，解压 46,939,139 B） | `BF0A11B1A98DFA4FF33B206FD52298330BCDD10B5CE2D19216F7CA41F60EF6F4` |
| `dist/Furnace-0.6.12-android.apk` | 98,728,918 B（versionCode 31） | `0CF69B56D68F45FDF33B4ECD62F98E1244F26F43F5CCE287DE487D36301E687A` |

构建耗时（v0.6.12 重建）：Windows 183.7s / Android 125.3s；`data/app.so` 21,283,720 B。

---

## 14. 版本历史

### 14.1 早期（0.1–0.5，按 PROGRESS 记录）

- 轮次 1–7（2026-09）：蓝图 v2 的 Thread UI、图形界面、Android 工具链落地、**v0.1.0 发版**；轮次 6 源码上传 GitHub（公开仓库 Furnace）。
- 轮次 9：AI 集成（schema v6 + AgentLoop + 对话界面）。
- 轮次 10–11：MindNet 认知模型接入（tierA 记忆层、tierB 顾问式排序 + 只读观测）。
- 轮次 12–17：AI 工具面（图片造卡/联网抓取/skill 安装/删除）、闪存卡复习计划、桌面端细化。
- 轮次 18–26：事件模型 v9、测评层 v10 三表、校准曲线、M6 学习效果度量。
- 轮次 27：**题库地基 + 推理层 + threadflow 两段式（schema v12，三线并行）**。
- 轮次 28–35：推理管道接真模型、ThreadFlow 接 App、观察层键空间、组卷器、`compose_paper` 工具。
- 轮次 36–49：拍照整理提案（v13）、日程冲突、自由挖空、认知排序档位、节律 `α(τ)`。
- 轮次 50–68：反事实 V(π)、留存探针、材料摄取（v14）、线索边（v15）、SM-2→FSRS 单一权威、材料入库。
- 轮次 69–100：材料入库 UI、手写边、`run/1` 演练、待确认清单编辑、撤回流水、照片报告。
- 轮次 101–119：题库五片验收、能力动作画像、组卷网找题、题号+图片（v24）、Word 导出、闪存卡每日额度。
- 轮次 112–121：v0.5.0–v0.5.3 发布、入口重设计（题库成顶层目的地）、知识网络图、组合查询。
- 轮次 122–138：题源链接、能力动作词表（v25）、题库包 `.tqb`（v26/v27）、复习提醒（v28）、标签排序（v29）。

### 14.2 v0.6.x 发布线（tag 与 schema 已实测）

| 版本 | 日期 | schema | 主要内容 |
| --- | --- | --- | --- |
| v0.6.0 | 2026-10-23 | 30 | 题库总览、`questions.title`、详情页图文混排+LaTeX、AI 对话修复、闪存卡聚焦 |
| v0.6.1 | 2026-10-23 | 30 | 批量标签、搜索筛选、整卡快照降级、按题号更新 |
| v0.6.2 | 2026-10-23 | 31 | 多图/多页一次整理、队列批量、导入前备份 |
| v0.6.3 | 2026-10-24 | 31 | 备份一键恢复、保留策略、多图卡编辑保存 |
| v0.6.4 | 2026-10-24 | 32 | 详情页自测判分 + 作答记录 |
| v0.6.5 | 2026-10-24 | 32 | 错题本筛选/徽标/作答明细与清除 |
| v0.6.6 | 2026-10-24 | 32 | 学习数据清空、自测统计行、明细逐条删 |
| v0.6.7 | 2026-10-24 | 33 | 题号高水位、多段题号搜索、组卷缺口解释 |
| v0.6.8 | 2026-10-24 | 33 | 自测防剧透、题库排序、详情页翻页 |
| v0.6.9 | 2026-10-25 | 34 | 排序偏好落盘、做题进度/跳题号、复习节奏修复 |
| v0.6.10 | 2026-10-25 | 35 | 页面缩放整体化、persona、docx 可复现 |
| v0.6.11 | 2026-10-26 | 39 | 改名「智能化」、新图标、思维链+停止、Time 行高、安排过滤、闪卡全文、复习间隔、知识图、检索词、标签边界、能力测评 |
| v0.6.12 | 2026-10-27 | 40 | 卡组分卡组复习、收题并入 agent、运行时间线、轮数上限 30/60、Markdown+LaTeX、schema v40 三字段、focus_review、tqb_verify |
| （未发） | 2026-10-29 | 41 | 评测板块 v1.0（八表）、P2 Thread 参数接口、P3 `.cogprofile` 导出 |

---

## 15. 踩坑与教训（按类别）

**数据库/迁移**

1. 版本号 +1、迁移函数、`_ensureColumns` 自愈、`build_runner`、`database.g.dart` 入库，五件事缺一不可；`_ensureColumns` 漏加列会在「版本号被盖高」的设备上崩。
2. 迁移测试会暴露 `_tableFor` 缺 case（如 tags）；新表名要避开旧表（`cog_` 前缀）。
3. 旧数据一律保留、不回填；NULL 必须有语义。

**l10n**

4. 不整文件重写 ARB（会截断）；只 edit/append，改完 gen-l10n。
5. 新 key 先检查冲突；中英同步；`@metadata` 必填。

**测试**

6. 全量测试期间不改 lib；改签名同步所有 fake；`dart analyze lib test` 才抓 test 里的 invalid_override。
7. 页面 dispose 写库与 `db.close()` 可能死锁；排序测试别依赖同毫秒。
8. 工具数断言随注册表变化（现 29）。

**构建/发布**

9. 构建走 ASCII junction；Windows 包删 `kernel_blob.bin`；zip 用 `ZipFile::CreateFromDirectory`（28 entries、0 目录条目）。
10. GitHub HTTPS 被阻断 → REST push；`BLOB_MISMATCH` 是短 sha 噪音；tag 用 REST API 复核。
11. dist 被 gitignore，绝不提交；发布提交只含版本文件 + PROGRESS。

**PowerShell / 工具**

12. 中文 `.ps1` 要 UTF-8 BOM；PS 5.1 与 pwsh 行为差异；长中文文本写临时文件，别直接塞命令行（弯引号会被吞）。
13. `run_code` 长任务必须显式 `timeoutMs`（≤600000），否则 120s 超时；脚本里 Dart/PowerShell 的美元符号会互相插值，复杂脚本用数组 join 或转义。
14. `tools.read` 按行号 offset 在 edit 之后会错位，批量改文件用「读全文 → 一次 write」或内容锚点。

**产品/验证**

15. AOT 产物里搜中文找不到属正常（UTF-16/本地化资源）。
16. 别用「能渲染」证明「能用」；双端真机未逐屏手测的功能要在文档里标「未验证」。
17. 真实 API 的 tool call 历史必须原子成组，否则 400；fake adapter 不会替你发现。
18. 撤销的 before 状态为空时要返回 null，不能让用户看到「成功撤销」但其实什么都没做。

---

## 16. 未完成、风险与下一步

### 16.1 明确未做（按优先级）

1. **双端真机逐屏手测**（v0.6.12 的卡组页/时间线/拍照收题链路、评测十任务、FilePicker 导出都只有组件/集成测试与构建层验证）。
2. **handoff M2 剩余**：材料容器与材料练习记录（用时/错因/岔路/重做历史）。
3. **能力点录入与 T×A 报表页**；题库列表/组卷/Word 导出尚未展示能力点与扩展关系。
4. **REVIEW_FEEDBACK 剩余**：§3 页面级设计 token 迁移（等用户定「更紧凑还是更松弛」）、§10 其余标签选择器（AI 建议标签/组卷选标签/知识网络入口/题库包路径）、§9 组卷网真实站点 A/B。
5. 评测：P2 的 Thread 消费侧接线、`design_version` 升级后 stale 自动扫描、`decision_fatigue` 标定。
6. 运行时间线落库（现在只在内存）；旧 `QuestionIntakePage/HandwritingQueuePage` 与旧 `ability_scores` 页面代码未删（无入口）。
7. 6:2:2 复习配额、错题按能力点自动建卡组、任务侧批量提前、无云同步（后者明确不做）。

### 16.2 风险

- 评测任务的计时精度、真机切后台/锁屏行为未验证；`too_slow` 用 3000ms 占位。
- 题库包按题号更新依赖组卷网题号；外部包缺题号时只能新增不能更新。
- AI 真实模型/供应商差异（SSE 字段、tool_calls 格式、上下文窗口）只有部分冒烟。
- 仓库外依赖：`E:/dsh-tmp-aot/*.ps1`（推送/tag 脚本）、技能目录 `D:/dsh-data/skills/` 不在仓库内，换机器要重建。

### 16.3 下一步建议

1. 先做一轮真机验收（Android 优先），把发现的问题记进 PROGRESS / FEATURE_MATRIX。
2. 若继续开发：优先 M2 材料容器 + 练习记录（用户明确的设计缺口），其次能力点录入/T×A 报表。
3. UI 方向等用户拍板后，再做页面级 token 迁移（`AppTokens` 已就绪）。
4. 下一版发布按 §13 走；当前 `app_info` 仍是 0.6.12+31，若发新版要先 bump + 全量门禁 + 文档。
5. 任何新会话接手：先 `git status` / `git log --oneline -5` / `list_agents`，再读本文档 §1、§12、§13。

---

## 17. 文档索引（43 份）

**总览/流程**：PROGRESS（逐轮记录，758 KB，最权威的历史）、FEATURE_MATRIX（功能矩阵 + 实测增补表）、HANDOFF（本文）、HANDOFF_PIPELINE（采集管线 M1–M4）、USER_GUIDE（用户使用指南）、ARCHITECTURE、FURNACE_SPEC、PRD、MILESTONES、GAP_ANALYSIS、OPEN_DECISIONS、OPEN_QUESTIONS、PRIVACY、DEV_SETUP、DEPLOY、VERIFICATION_PROTOCOL、REVIEW_FEEDBACK。

**数据/领域**：DATA_MODEL（表语义 + v3→v41 全部章节）、KNOWLEDGE_PACKAGE、REACTIVITY_DESIGN、TAG_TREE_SORT_DESIGN、CALIBRATION、THREADFLOW_TWO_SEGMENT。

**AI/推理**：AI_DESIGN、REASONING_LAYER_DESIGN、MINDNET_CONTRACT、MINDNET_INTEGRATION、MINDNET_ROADMAP、SIMILAR_QUESTIONS_DESIGN、PERSONA_DESIGN、SKILL_FORMAT。

**题库/收题/题源/组卷**：QUESTION_BANK_DESIGN、QUESTION_INTAKE_AUDIT_DESIGN、HANDWRITING_INTAKE_DESIGN、ZUJUAN_LINKS_DESIGN、PAPER_COMPOSER_DESIGN、DOCX_EXPORT_DESIGN。

**外观/提醒/评测**：APPEARANCE_DESIGN、DESIGN_BLUEPRINT、REVIEW_REMINDER_DESIGN、ASSESSMENT_DESIGN。

**验证记录**：VERIFICATION_MINDNET、VERIFICATION_MINDNET_ROUND2。

> 注：DESIGN_BLUEPRINT / PRD / GAP_ANALYSIS 等为早期设计文档，部分内容已被后续实现取代；以 PROGRESS + FEATURE_MATRIX 为准。

---

## 18. 冷启动检查清单

1. `cd E:/Projects/class-productivity/app`；`git status -sb` 应干净、HEAD=origin/main。
2. 读 §1 表格 + PROGRESS 顶部 3 节，确认当前版本/schema/最后一轮。
3. `flutter pub get`；`flutter gen-l10n`（若 ARB 有改动）。
4. 跑 `dart analyze lib test` 与单点测试确认环境；需要时再跑全量（14–16 分钟）。
5. 团队：`list_agents`；若成员 inactive → `send_message` 派活；不要 `spawn_teammate` 同名成员。
6. 动 schema/l10n/git 前回读 §5、§10、§13。
7. 每轮结束：format → analyze → 全量 test → 文档 → Lead 分片提交 → REST push（需要发布再走 §13 并打 tag）。

---

*本文档只记录本会话中实际读到/跑到的内容；标注「记录值/历史记录」的条目来自旧交接文档或 PROGRESS，未在本次复验。发现与代码不符时，以代码与 PROGRESS 的实测记录为准，并顺手更新本文档。*
