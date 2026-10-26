# 开发进度

> 记录每一轮自动/手动迭代的进展，作为持续开发的“长期记忆”。

## 2026-10-26 轮次一百八十一：AI 考前提前复习（focus_review）+ 使用指南

- 目标：用户 m19724——「给 AI 发消息手动调节闪存卡推送（下周要考试，某些板块提前进复习）」，并要一份「怎样用 Furnace 才能优化学习效率」的使用指导。
- 片 1（纯逻辑）：新 `app/lib/domain/services/srs/review_focus.dart`——`planReviewFocus(cards, now, horizon=7d, limit=500)` 输出 `ReviewFocusPlan{pulled, alreadyDue, newCards, tooFar, beyondLimit}`；只拉「未来 horizon 内到期、非新卡、未到期」的卡，按原 due 近→远排序、超 limit 截断并计 beyondLimit；limit 负数抛 ArgumentError。16 例测试。
- 片 2（工具）：新 `app/lib/features/ai/tools/review_focus_tool.dart`（toolName `focus_review`）：参数 `tag`（标签路径，子树）/ `days`(0–90，默认 7) / `limit`(1–2000，默认 500) / `dry_run`(默认 true)；只写 `due_at`（`AnkiRepository.setCardStateDueAts` + `cardStatesForKnowledgePoints`，顺手补 `anki_repository.dart` 两个方法），不动 repetitions/state；`beforeJson` 空计划返回 null（否则撤销会「成功」但什么也没做），撤销逐张还原；riskFor=write、reversibleFor=true；卡组设了每日上限会在 summary 提醒。tool_registry 注册、agent_loop 规则 4 加触发句。12 例工具测试。
- 片 3（文档）：新建 `docs/USER_GUIDE.md`（10 节：三个常用入口 / AI 能做与不能做 / 高频指令模板 / 学习闭环六步 / 考前 focus_review 用法与边界 / 任务与题目推送同机制现状与未做项 / persona / 数据安全 / FAQ / 版本）；README 文档表加一行；FEATURE_MATRIX 顶部增补表加 2 行。
- 验证：`dart format` 本轮 8 个 dart 文件 0 changed；`dart analyze lib test` **88 issues / 0 error / 0 warning**（日志 `E:/dsh-tmp-aot/analyze-181.txt`，基线 90→88）；全量 `flutter test --concurrency=1` **+6285 ~2 All tests passed，19:52，EXIT 0**（日志 `E:/dsh-tmp-aot/test-181b-full.txt`；v0.6.11 基线 +6257，本轮净增 28 = 16+12）。首次全量跑出 1 例失败：`test/features/ai/zujuan_paper_tool_test.dart` 断言「第 27 个工具」→ 工具总数变 28，已把断言与标题改成 28，单点修复后全量重跑全绿。
- 未做/风险：focus_review 只有单元/组件测试，未在真机上手动跑一遍「预览→确认→撤销」；只改到期时间不改熟练度是**有意取舍**（提前复习不应伪造复习记录），文档已写明；任务/题目侧的「批量提前」未做（USER_GUIDE §6 已如实说明并给了下一步建议：任务侧 plan_shift 优先级更高）；v0.6.12 未出包。
- 下一步：用户 m20048/m20049 指出外部 agent 已产出 `E:/FirsryOS/THREADRIPPER/handoff/2026-10-26-furnace-pipeline/`（FURNACE-PIPELINE-SPEC-v1.md 等），要求「没有更新后当作完工，拿来实现并装载进软件」→ 轮次一百八十二按该规范做 App 侧 M1–M4 接入（题目区整段 Markdown+LaTeX、短题卡 `fullcard_` 标识、`extension_of` 关联与复习联动等，落地前先核对规范与现有实现的差异）。

## 2026-10-26 轮次一百八十：v0.6.11 双端发布（思维链/中断 + 新图标 + Time 行高 + 标签边界 + 能力测评）

- 目标：把 v0.6.10 之后轮次 175–180 的改动打成双端安装包：改名「智能化」、新应用图标、思维链可见/落库/可中断、Time 行高拖拽、「安排」全部/今天、闪卡全文+复习间隔、设计 token 基础层、知识图重做、检索词分学科+标准侧同步、标签用途边界（8 处）、能力测评+画像+趋势、题库包/手写标签边界、任务详情 `context.mounted` 修复。
- 版本：`app/pubspec.yaml` `version: 0.6.11+30`；`app/lib/core/app_info.dart` `kAppVersion='0.6.11'`、`kAppBuildNumber=30`；`test/core/app_info_test.dart` +2 通过；**schema v35→v39**（v36 两列、v37 `tags.usage_codes`、v38 `ability_scores` 新表、v39 `ai_messages.reasoning`，全部只加列/加表、不回填）。
- 构建（同一后台 job，日志 `E:/dsh-tmp-aot/build-180b.log`）：`scripts/build_windows.ps1` WINDOWS_EXIT=0、`scripts/build_android.ps1` ANDROID_EXIT=0；Windows `data/app.so` 21,824,392 B @23:11:15、`furnace.exe` 版本资源 0.6.11+30；打包前删 `data/flutter_assets/kernel_blob.bin` 110,766,568 B；zip 从 ASCII junction `E:\Document\furnace-build\...\Release` 生成 28 entries / 20,657,089 B / 解压 47,480,279 B / kernel_blob 0 条 / SHA-256 `2937E1D8…C923954D`；Android APK 100,285,614 B / SHA-256 `C95B91A6…B43959EE30`，aapt2 versionCode 30、versionName 0.6.11、minSdk 24 / targetSdk 36 / compileSdk 36，Gradle assembleRelease 247.6s。
- 验证：`flutter test --concurrency=1` **+6257 ~2 All tests passed，14:54，EXIT 0**（日志 `E:/dsh-tmp-aot/test-180-full.txt`；v0.6.10 基线 +6246，净增 11：能力画像趋势 UI 6 例、题库包/手写标签边界 5 例）；`dart analyze lib test` 90 issues / **0 error / 0 warning**。
- dist/：`Furnace-0.6.11-windows-x64.zip`、`Furnace-0.6.11-android.apk`、`RELEASE-v0.6.11.md`（下载表/11 条功能/schema 提示/验证/已知未做/发布说明），dist 被 gitignore、不入库。
- 发布提交范围 v0.6.10..HEAD 共 35 个提交（含本轮 4 个功能提交 `cca7af1`/`5643be7`/`53c7916`/`d76ff89` 与本发布提交）；推送走 GitHub REST git data API（本机 github.com HTTPS 仍被阻断），并打 annotated tag v0.6.11，GitHub API 复核 TAG_TARGET=发布提交。
- 未做/风险：双端真机未逐屏手测（新图标、思考面板、趋势折线、标签用途对话框、Time 分隔线拖拽都只有 widget / 构建层验证，新图标资源第一次经构建验证）；§3 页面级 token 迁移仍在等「自然」方向；思考文本只落库展示、不回传上下文，`cancelled` 状态不落库；组卷网检索词真实站点命中率未做人工 A/B；能力测评信度有限；无云同步。
- 下一步：用户 m19724 提出「给 AI 发消息手动调节闪存卡推送（提前复习）」并要一份使用指导 → 轮次一百八十一做 AI `focus_review` 工具（按标签把未来 N 天内到期的闪存卡提前到今天）+ `docs/USER_GUIDE.md`。

## 2026-10-26 轮次一百七十九：知识图期 3 + 检索词标准侧同步 + 三域标签边界 + 能力趋势纯逻辑

- 目标：继续按 `docs/REVIEW_FEEDBACK.md` 收尾——§7 知识网络图**期 3**（搜索/标签筛选/详情/列表兜底）、§9 检索词的**标准侧**（`keywords.mjs` + `SKILL.md`）同步、§10 再把**题库批量打标签 / 任务详情 / 认知测评**三个域的选择器接上用途边界、§8 能力趋势的**纯逻辑**（画像页 UI 留后）。§3 页面级 token 迁移仍等用户给「自然」方向。本轮**无 schema 变更**（仍 v39）。
- 团队（沿用现有三名成员，`spawn_teammate` 仍报已存在，故一律 `send_message` 复用）：task-201 threadflow-engine（§7 期 3）、task-202 question-intake（§10 三域选择器）、task-203 reasoning-core（§8 趋势纯逻辑）；§9 标准侧由 Lead 做。
- l10n（Lead，12 个 key，`flutter gen-l10n` exit 0）：10 个 `cognitiveGraph*`（SearchHint/SearchCount/SearchEmpty/SearchClear/ViewList/ViewGraph/DetailTags/FilterTag/FilterClear/ListUntagged）+ `tagUsageScopeHintNamed` / `tagUsageScopeEmptyNamed`（带用途名的通用提示与空态）。
- 片 1（Lead，§9 标准侧同步）：`D:/dsh-data/skills/zujuan-source-standards/scripts/keywords.mjs`（约 324 行，`node --check` 通过）新增 `SCIENCE_MIN/MAX=15/30`、`HUMANITIES_MIN/MAX=20/40`、`ABS_MIN=4`、`HUMANITIES_KEYS`、`subjectBandFor`；`textLayerOnly`/`segments` 加 soft 模式（文科保留全角逗号/顿号，否则难凑 20–40 连续串）；新增滑窗 `bandWindows` 与带区间的 `score`；`keywordsFor(text,{top,band})` 长串优先、短串兜底；CLI 加 `--band humanities`，`--queries` 逐条按 `subjectKey` 选带。实测 `--file`：理科 106 字题 6 条（19/15 字 in-band + 短兜底）、文科 144 字题（21/20 字，含全角逗号）、短理科 31 字 2 条 4 字（诚实降级）。`SKILL.md` §6.2 重写为长度口径表 + 四条带 `--band` 的命令 + 风险段（候选可能含逗号、站点容错未实测、0 结果时手动去逗号）；App 侧 `zujuan_keywords.dart` 文件头注释改为「✅ 与标准侧已同步（2026-10-26）」。
- 片 2（threadflow-engine，task-201，§7 期 3）：`cognitive_graph_layout.dart` 新增纯函数 `cognitiveGraphPrimaryTagId` / `filterCognitiveGraphPoints` / `groupCognitiveGraphPointsByPrimaryTag` 与 `CognitiveGraphPointGroup`；`cognitive_graph_page.dart` 加搜索框（知识点标题或任一标签标题、大小写不敏感、匹配数/清除/空态）、按标签筛选（详情 sheet 里点标签 chip 转筛选，图上方可清除）、详情 sheet（认知区域/关联卡数/平均 R/标签）、列表视图（按主标签分组、未挂标签最后、点行回图谱并居中）。测试：布局 12→16 例、页面 5→12 例。修掉真实 bug：列表点行回图谱没真居中（底部详情卡让视口矮约 60px，改 postFrame 二次居中）。
- 片 3（question-intake，task-202，§10 三域）：新 `app/lib/features/tags/application/tag_usage_scope.dart`——`TagUsageScope`（`visibleTags`/`hasAnyDeclaration`/`isEmpty`、共享 `emptyDialogKey`）、`loadTagUsageScope(ref, usage)`、`tagUsageLabel`、`tagUsageScopeHint`/`tagUsageScopeEmptyText`、`showTagUsageScopeEmptyDialog`；接入题库批量打标签对话框、任务详情「加标签」、认知测评选择范围（`TagUsage.knowledge`）。测试：`tag_usage_scope_test.dart` 0→8 例、`question_bulk_tag_dialog_test.dart` 0→3 例、`task_detail_page_test.dart` 6→9 例、`assessment_page_test.dart` 4→7 例。
- 片 4（reasoning-core，task-203，§8 趋势纯逻辑）：新 `app/lib/domain/services/cognitive/ability_trend.dart`（180 行，纯 Dart）——`AbilityTrendPoint`/`AbilityTrendSeries` 按 `capturedAt` 稳定升序（同刻保序）、`fromNewestFirst` 反转后只留最新 `kAbilityTrendMaxPoints=30` 点、`delta`/`averageScore`/`bestScore`/`worstScore`、`direction`（阈值 `kAbilityTrendFlatEpsilon=2.0` 判变好/持平/变差）、`progress01`/`normalizedScores`/`normalizedPositions`（夹 0–1、NaN 记 0）；29 例测试。画像页趋势图 UI 未接。
- 门禁：15 个手写改动 dart 文件 + 全部新测试 `dart format --set-exit-if-changed` 0 changed；`dart analyze lib test` = **90 issues / 0 error / 0 warning**（基线 89，多出 1 条 info，均在改动前就存在的文件里）；scoped 合并测试（cognitive 两文件 + assessment + task_detail + bulk_tag_dialog + tag_usage_scope + ability_trend + `test/domain/services/zujuan` 全目录）`+364 All tests passed`；全量 `flutter test --concurrency=1` = **+6246 ~2 All tests passed，14:39，EXIT 0**（日志 `E:/dsh-tmp-aot/test-179-full.txt`；基线 +6189，净增 57）。
- 教训：①`tools.read` 取 `old_string` 再 `tools.edit` 后，**后续按行号的 read 会错位**，`keywords.mjs` 一度被替换坏（函数尾被吃、重复块）；批量改文件要用「先读全文→一次 write」或每次按**内容锚点**读；②pwsh 把中文弯引号当参数引号吃掉，长中文文本必须写临时文件再 `--file`；③`tools.glob` 对工作目录之外返回空，查仓库外文件用 pwsh `Get-ChildItem`。
- docs：`docs/REVIEW_FEEDBACK.md` 补「轮次一百七十九」总状态段 + §7 期 3 / §9 标准侧 / §10 三域 / §8 趋势各条实施状态 + §15 批次表一行 + header 四更新；`docs/FEATURE_MATRIX.md` 新增 4 行（图谱期 3、检索词标准侧、三域选择器、能力趋势）并改 4 处旧尾注；`docs/ASSESSMENT_DESIGN.md` 新增 §9.1（趋势纯逻辑口径）；本轮无 DATA_MODEL 变更（无 schema 改动）。
- 仍未做：§3 页面级 token 迁移（等用户定「自然」方向）；§8 画像页趋势图 UI；§10 其余选择器（AI 建议标签 / 组卷选标签 / 知识网络入口 / 题库包标签路径选择器）仍读全树；§9 真实站点上用手上题做新长度候选的命中率人工 A/B；真机未手测；**v0.6.11 未出包**（v0.6.10 之后已攒轮次 175–179 若干提交）。
- 下一步候选：A) 出 **v0.6.11** 双端发布件；B) §8 能力趋势图 UI（数据层已就绪）；C) §10 其余选择器。

## 2026-10-26 轮次一百七十八：设计 token 基础层 + AI 思考落库（schema v39）+ 闪卡标签边界

- 目标：继续按 `docs/REVIEW_FEEDBACK.md` 逐条改进，本轮做 §3（UI 设计 token 的**基础层**，页面级迁移等用户定方向）、§4a（思考过程落库 + 历史消息里折叠展示）、§10（闪卡域标签选择器按用途过滤）。
- 团队（沿用现有三名成员，`spawn_teammate` 仍报 `teammate name ... was already used in this Team`，故一律 `send_message` 复用）：task-199 threadflow-engine（§10 闪卡标签边界）、task-200 question-intake（§4a 历史思考折叠 UI）。task-200 的界面改动被 Lead 中途中断（排障，见教训），已落盘部分由 Lead 接管验收并 complete。
- l10n（Lead，3 个 key，`flutter gen-l10n` exit 0）：`tagUsageScopeHintFlashcard`、`tagUsageScopeEmptyFlashcard`、`tagUsageScopeDefaultHint`（§10 两种空态 + 常显提示）。
- 片 1（Lead，§3 基础层）：新 `app/lib/core/theme/design_tokens.dart` —— `AppSpacing`（4pt 栅格 xxs2/xs4/sm8/md12/lg16/xl24/xxl32/xxxl48 + `snap`）、`AppRadius`（control6/card10/sheet14/pill999 + `BorderRadius` 常量）、`AppTokens extends ThemeExtension<AppTokens>`（间距 8 字段 + 三半径 + 语义文字 pageTitle20/sectionTitle16/body14/caption12，`standard` 兜底、`fromTheme`、`of(context)`、`copyWith`、`lerp`）；`theme_profile.dart` 的 `toThemeData()` 在算完配色与字体后装入扩展，并让 `cardTheme`/`dialogTheme` 采用 `AppRadius.cardBorder`/`sheetBorder`（修掉「M3 默认 12/28 与各页手写 2–18 打架」）；测试 `design_tokens_test.dart` 8 例。**Flutter 3.47 坑**：`themed.extensions.values` 直接展开编译失败（CFE 当成 `ThemeExtension<ThemeExtension<dynamic>>`），必须 `Map<Object, ThemeExtension<dynamic>>.from(...)` 再 `.values.toList()` 传 `copyWith(extensions:)`。
- 片 2（Lead，§4a 落库，schema **v39**）：`ai_messages` 新增可空 `reasoning` TEXT（只有 assistant 行带、NULL=没思考文本、不写空串）；`_upgradeV38ToV39` 只补列不回填 + `_ensureColumns` 自愈；`build_runner` exit 0（73s / 876 outputs）；`ai_repository.addMessage` 加 `String? reasoning`；`agent_loop.dart` 六条写库路径全部带上思考（失败保留、无工具回答、TurnGroup 提交、`_commitTurn`、`_finishCancelled`、轮数上限 notice 不带），并新增 `_reasoningOrNull`。测试：`v39_migration_test` 3 例、`agent_loop_reasoning_persistence_test` 6 例。
- 片 3（question-intake + Lead）：`ai_chat_page.dart` +138 —— 历史 assistant 消息的思考在正文上方折叠显示（默认收起、每条消息各自记展开状态、`aiHistoryReasoningKey(messageId)`），并按文本相等判断「这段思考已落库」后不再重复画流式面板；`ai_chat_page_test.dart` 相应改 1 例，新 `ai_chat_history_reasoning_test.dart` 4 例。
- 片 4（threadflow-engine，task-199）：新 `app/lib/features/anki/application/flashcard_tag_scope.dart`（加载 → `tagUsageResolverProvider` → `visibleOf(..., TagUsage.flashcard)` → 保持顺序的过滤 + 两种空态对话框）；`anki_manage_page.dart` 卡组下拉/加标签对话框与 `review_plan_page.dart` 两个选择器全部改走它，并在标题下常显范围说明。测试：anki_manage 6→10、review_plan 3→6（共 16 例）。
- 门禁：`dart format` 17 个手写改动 dart 文件 0 changed；`dart analyze lib test` = **89 issues / 0 error / 0 warning**（基线 91，顺手删掉 4 条本轮新增 info lint，反而少 2）；scoped（v39 迁移 + persistence + ai_chat_page + history reasoning）`+27 All tests passed`；全量 `flutter test --concurrency=1` = **+6189 ~2 All tests passed，13:01，EXIT 0**（日志 `E:/dsh-tmp-aot/test-178-full.txt`；上轮基线 +6161，净增 28）。
- 教训（重要）：我先把 `_finishCancelled` 的条件从「partial 非空」放宽到「partial 或 reasoning 非空」，于是**用户在中途停止、只出过思考没出文字**时也写一条 content 为 NULL 的 assistant 行；`ai_chat_page_test` 第 13 例在页面 dispose → cancel → 写库，与 `tearDown` 的 `await db.close()` 撞成死锁（`flutter test` 卡死 17 分钟，`--timeout` 不触发）。定位靠 debugPrint 插桩 + `git stash` 二分（先排掉 QI 的页面，再定位到 `agent_loop.dart`）；修法是失败路径与取消路径都要求「有文字才写行」，正常完成路径仍允许 content 为 NULL 的纯思考行，并补 1 例测试钉住「停在第一个字之前不写空行」。**全量跑的时候不要改 lib 被测源码**（轮次 169 同款教训）。
- 仍未做：§3 页面级 token 迁移（125 种 `EdgeInsets`、11 种半径、9–13px 手写字号，等用户给「更紧凑还是更松弛」方向）；§9 标准侧 `keywords.mjs`/`SKILL.md` 与新长度口径同步；§10 其余域选择器（题库/知识网络/任务）；§7 知识图期 3（节点详情/搜索/列表兜底）；能力趋势图；v0.6.11 未出包。
- 下一步候选：A) 出 **v0.6.11** 双端发布件（v0.6.10 之后已攒轮次 176/177/178 共 27 个提交）；B) §10 其余域标签边界；C) §7 期 3。
## 2026-10-26 轮次一百七十七：能力测评 MVP（schema v38 + 四项本地小测 + 能力画像）

- 目标：按 `docs/REVIEW_FEEDBACK.md` 第 8 条落地 §8「认知测评要测能力、不是知识点」的 MVP——与知识先验完全分开的一组本地小测——并补能力画像页；§3（UI 设计 token）仍等用户定义「自然」方向，本轮不动。
- 团队（沿用现有三名成员，未新建同名成员）：task-196 reasoning-core（评分纯逻辑 `ability_assessment.dart`）、task-197 question-intake（四项小测页 `ability_assessment_page.dart`）、task-198 threadflow-engine（`ability_score_providers.dart` + 只读画像页 `ability_profile_page.dart`）；三人全部 completed，Lead 独立复跑各自 format/analyze/scoped 测试。
- 片 1（Lead，数据层）：schema **v38** 新表 `ability_scores`（id / ability_key / score / metrics_json / captured_at）；迁移 `_upgradeV37ToV38` 只建表不回填，`_ensureColumns` 也建表自愈（被盖成 v38 却缺表时画像页不能把「表不存在」当成「从没测过」）；`build_runner` 重生成 `database.g.dart`；新仓储 `ability_score_repository.dart`（`record` 写库前把 score clamp 到 0–100、`historyFor` 新→旧、`latestByAbility`、`countFor`）+ `repository_providers` 注册；`v38_migration_test` 3 例、`ability_score_repository_test` 6 例。
- 片 2（reasoning-core）：领域纯逻辑 `app/lib/domain/services/cognitive/ability_assessment.dart`——`AbilityKey`（reaction_speed / working_memory / pattern_recognition / attention_stability 稳定 code）、`AbilityScore`、`medianReactionMillis`、四个 `score*` 函数（反应中位 250ms→100 / 800ms→0；记忆跨度 3→0 / 9→100；模式 = 正确率×70 + 速度×30（1500ms→满、6000ms→0）；注意 = (灵敏度+特异度)/2），全部 clamp 0–100；测试 50 例。
- 片 3（question-intake）：`app/lib/features/cognitive/presentation/ability_assessment_page.dart`（866 行，介绍→四项小测→单项得分→汇总→保存；反应速度 5 试次 800–2000ms 随机等待、工作记忆 5 试次跨度 4..8 显示 1.2s 后输入、模式识别 10 试次 900ms 图案比对、注意稳定性 30 试次 800ms 窗口；可重测单项、返回即放弃、所有 Timer 随 dispose 取消；保存逐项写 4 条，成功 SnackBar + pop，失败不 pop）；测试 11 例。
- 片 4（threadflow-engine + Lead）：`ability_score_providers.dart`（`abilityLatestScoresProvider` / `abilityScoreCountsProvider`，均 watch `databaseRevision`）；`ability_profile_page.dart`（只读：四项各一卡显示最近一次分数/次数/时间，空态、读失败态）；测试 6 例。Lead 在设置页「学习洞察」之后加「能力测评」「能力画像」两个入口（`settingsAbilityAssessmentTileKey` / `settingsAbilityProfileTileKey`）+ 测试 2 例。
- l10n：Lead 写 36 个 key（`ability*` + `settingsAbility*`，zh/en 各一份），`flutter gen-l10n` exit 0。
- 门禁：format 本轮 16 个 dart 文件 0 changed；`dart analyze lib test` = **91 issues / 0 error / 0 warning**（与基线一致）；scoped 组合 +80 全绿；全量 `flutter test --concurrency=1` = **+6161 ~2 All tests passed，31:57，EXIT 0**（日志 `E:/dsh-tmp-aot/test-177-full.txt`；上轮基线 +6083，净增 78）。
- 教训：`ability_score_repository_test` 第一版有 1 例在组合跑时失败、单文件跑通过——原因是该用例 4 条 `record` 不传 `now`、同一毫秒写多行，而 `historyFor` 按 `captured_at DESC, id DESC` 排序，id 是 `Ids.next('ab')` 生成的 `ab-<uuid v4>` **非单调**，同毫秒 tie 次序随机 → flaky；改为显式递增 `now` 并在注释里写明不可依赖同毫秒 tie。
- 仍未做：§3 UI 设计 token（需用户定「自然」方向）；§4a 思考落库（`ai_messages.reasoning`，留 v39）；能力趋势图 / 历史列表（`historyFor` 已具备、UI 未用）、`metrics` 详情展示、保存事务化（逐项写、非事务）、与 MindNet/认知模型的参数映射、真机计时精度验证、英文母语化。
- 下一步候选：A) 出 **v0.6.11** 双端发布件（v0.6.10 之后已攒轮次 176/177 若干提交）；B) §3 UI 设计 token 基础层；C) §4a 思考落库（v39）。

## 2026-10-25 轮次一百七十六：REVIEW_FEEDBACK 第二批（知识图分簇+缩放、检索词按学科长度、标签用途边界 v37、安排过滤）

- 目标：继续按 `docs/REVIEW_FEEDBACK.md` 开工，本轮落地 §7（知识网络图）、§9（组卷网检索词长度）、§10/§11（标签用途边界）、§12B（安排列表过滤）；§3（UI 设计 token）与 §8（能力测评）留后续。
- 团队：用户 m00002 要求「重建三个成员」，但 `spawn_teammate(name='reasoning-core')` 报 `ToolCallError: teammate name "reasoning-core" was already used in this Team`——上一会话的成员在本 Team 里仍在册（`list_agents` 显示三人均 inactive/fresh）。故**改用 send_message 复用现有成员**派新任务，未新建同名成员。三任务：task-192 reasoning-core（§9 纯逻辑）、task-193 threadflow-engine（§7 知识图）、task-194/195 question-intake（§12B 过滤、§10/§11 UI）。
- l10n（Lead，17 个 key，`flutter gen-l10n` exit 0，两个 ARB 各 1547 个非 @ key）：`cognitiveGraphResetView`/`cognitiveGraphPanHint`、`questionZujuanKeywordLength(count)`/`questionZujuanLengthHint`、`tagUsageDialogTitle`/`tagUsageEntryTitle`/`tagUsageEntrySubtitle(count)`/`tagUsageTime`/`tagUsageQuestion`/`tagUsageKnowledge`/`tagUsageTask`/`tagUsageFlashcard`/`tagUsageInheritHint`、`timeBlockTagScopeHint`/`timeBlockTagScopeEmpty`/`timeBlockTagScopeDefaultHint`、`timeBoardFilterAll`/`timeBoardFilterToday`/`timeBoardTodayEmpty`。
- §10/§11 schema **v37**（Lead）：`tags` 新增可空 `usage_codes` TEXT（逗号分隔 time/question/knowledge/task/flashcard；NULL=本级不声明、按 parentId 向上继承、整链无声明=不限制，即 §16-Q8 选了「未声明全可见」）；`_upgradeV36ToV37` 只补列不回填、`_ensureColumns` 自愈，并补 `_tableFor` 的 `case 'tags'`（首跑迁移测试报 `Invalid argument(s): unknown table tags` 后修）；`dart run build_runner build --delete-conflicting-outputs` exit 0（89s / 904 outputs）。
- §10 领域层（Lead）：新 `app/lib/domain/services/tags/tag_usage.dart` —— `enum TagUsage`、`encodeTagUsageCodes`（空集→NULL、顺序=枚举声明序）、`decodeTagUsageCodes`（null/空/未知→null、容空格、大小写敏感）、`TagUsageNode`、`TagUsageResolver`（`declaredFor`/`effectiveFor`/`effectiveSourceTagId`/`hasAnyDeclaration`/`declaredTagCount`/`isVisibleFor`/`visibleTagIdsFor`/`visibleOf`，成环保护、未知 id 安全；非 null 空集按「无声明」处理）；仓储 `TagRepository.resolverFor`/`updateTagUsageCodes`；新 `features/tags/application/tag_usage_providers.dart`（`tagUsageResolverProvider` + `setTagUsages`）。
- §10/§11 UI（question-intake，task-195）：`tag_tree_page.dart` +131 行——行菜单「用途边界」、多选对话框（5 个 `CheckboxListTile` + 继承说明 + 已声明数）、已声明徽标、父子继承提示；`time_board_page.dart` 标签选择器按 `TagUsage.time` 过滤（`visibleOf` 保序、排除已选），三种空态（整树无声明→默认提示并全列；有声明但无 time 树→`time-block-tag-scope-empty` 空态；选择器标题下常显范围说明）。测试：`tag_tree_page_test.dart` 28 例、`time_board_page_test.dart` 12 例。
- §7 知识网络图（threadflow-engine，task-193）：`cognitive_graph_layout.dart` 重写 438 行——按标签分簇（扇区角度按成员数加权、最小角 0.22 rad、簇内黄金角螺旋 `r=26*sqrt(k)`、最小间距 26、无标签点放中心、坐标 clamp 边距 56、集合排序保确定性），画布边长 `clamp(840*sqrt(n/15), 840, 2400)`；`cognitive_graph_page.dart` 重写 745 行——`InteractiveViewer`（minScale 0.4 / maxScale 4 / 边界无限 / 首帧自适应缩放居中 / AppBar 重置视图 / 角落提示 / scale<0.8 隐藏文字），命中测试随缩放平移换算。测试：布局 12 例 + 页面 5 例。期 3（节点详情/搜索/筛选/列表兜底）未做。
- §9 检索词（reasoning-core，task-192 + Lead 接线）：`zujuan_keywords.dart` 重写 467 行——`enum ZujuanSubjectBand{science,humanities}`、常量 15/30 与 20/40、`zujuanSubjectBandFor`（语文/英语/历史/政治/地理→文科，其余含 null/未知→理科），候选改为按句滑窗/锚点扩窗到目标区间、文科严格短于题干（短题干回退尽量长且 ≥4）、去掉 5–16 字偏好，仍是清洗后原文连续子串、确定性、互为子串只留一条；`zujuan_link.dart` 两函数加 band 透传。UI（Lead）：`question_zujuan_search.dart` provider 改 `(stem, band)` 记录键、按钮收 `subjectKey`、候选行显示「N 字」、表头加长度口径；详情页传 `question.subjectKey`。测试：`zujuan_keywords_test.dart` 30 例、`zujuan_link_test.dart` 10 例、详情页 74 例。
- §12B（question-intake，task-194）：`time_board_page.dart` 顶部「全部/今天」ChoiceChip（blocks 非空才显示），今天=本地时区当天半开区间与块区间有交集（跨午夜算今天、恰 00:00 结束不算），日程卡同步过滤，今天无块给专门空态；8 例测试。
- 门禁：只 format 本轮 22 个改动 dart 文件（首次 3 个未格式化 → 已 format）；`dart analyze lib test` = **91 issues / 0 error / 0 warning**；scoped 测试 8 个文件/目录 `+434 All tests passed`（EXIT 0）；全量 `flutter test --concurrency=1` = **+6083 ~2 All tests passed**，14:20，EXIT 0（日志 `E:/dsh-tmp-aot/test-176-full.txt`；基线 +6006，净增 77）。
- docs：`docs/DATA_MODEL.md` 新增 §26（v37 一列、为何一列不是新表、迁移/自愈/_tableFor、领域契约、读写接口、测试、边界）；`docs/REVIEW_FEEDBACK.md` 补 §7/§9/§10/§11 的实施状态 + header/§0/§15 批次表 + v37 实际范围说明；`docs/FEATURE_MATRIX.md` 新增 4 行（知识图、检索词长度、标签用途、安排过滤）。
- 教训：①test 里 `{TagUsage.task, TagUsage.task, ...}` 这种字面量重复元素会被 analyzer 判 `equal_elements_in_set` **warning**（门禁要求 0 warning）→ 改 `Set.of([...])` 运行时去重；②`spawn_teammate` 不能复用上一会话的名字，同 Team 里已存在就直接 `send_message` 复用它；③自愈路径补列会走 `_tableFor`，新表/新列要同步补 case。
- 未做：§3 UI 设计 token（等用户定「自然」方向）、§8 能力测评（新模块）、§4a 思考落库（`ai_messages.reasoning` 留 v38）、§9 标准侧 `keywords.mjs`/`SKILL.md` 仍 4–28 未同步、§10 其余域选择器仍读全树（23 处 `getAllTags()`）、§7 期 3、真机未手测、v0.6.11 未出包。

## 2026-10-25 轮次一百七十五：REVIEW_FEEDBACK 第一批（改名/图标/思维链+中断/Time 行高/闪存卡全文/复习间隔）

- 目标：按 `docs/REVIEW_FEEDBACK.md` 的 14 条建议开工（用户 m17298「好的你可以开始改进了」）；本轮落地 §1 §2 §4a §4b §12 §13 §14，§3 §7 §8 §9 §10 §11 留下一轮。
- 改名（§1/§12，Lead）：`aiTitle`「AI 对话」→「智能化」、`navAi`「对话」→「智能」、`timeTodaySchedule`「今日安排」→「安排」（en Intelligence / AI / Schedule），persona 两条说明文案同步；新增 4 个 AI key `aiReasoningTitle/aiReasoningGenerating/aiStopTooltip/aiCancelledLabel`；`flutter gen-l10n` exit 0（5 个生成/ARB 文件）。
- §2 应用图标：新设计「炉膛+火焰」（深绿 #1A3A2D→#2F6F4F 底、琥珀 #F7C36A→#C47426 拱门），13 个文件 —— android 5 档 `ic_launcher.png` + 5 档 `ic_launcher_foreground.png` + `mipmap-anydpi-v26/ic_launcher.xml`（background/foreground/monochrome）+ `values/colors.xml` + `windows/runner/resources/app_icon.ico`（40,291 B）；**Android/Windows 构建链接验证留到出包轮**。
- §4a 思维链：`sse_assembler.dart` 解析 `reasoning_content`/`reasoning`（字符串或对象 text/content parts 中的 reasoning|thinking|thought）→ `ModelReasoningDelta`；`model_adapter.dart` `ModelEvent` 由 sealed 改 abstract（作用域外穷尽 switch 需要）并加 `ModelTurnCancelled`、`CancellableModelAdapter` + `ModelAdapterCancellation`（默认 no-op）；`agent_loop.dart` `AgentTurnState.reasoningText`。
- §4b 可中断：`openai_compat_adapter.dart` 持 `_activeRequest/_activeLines/_cancelRequested`，`cancelActiveTurn()` + 十余处取消检查点 + `HttpClientRequest.abort()`；`AgentTurnState.cancelled`、`AgentLoop.cancel()`（幂等；待审批期间取消丢弃整批）、`_finishCancelled()` 保留已生成 partial 为 assistant 消息、`dispose()` 先取消。测试：sse_assembler +10、新 `agent_loop_cancel_test.dart` 7、新 `openai_adapter_cancel_test.dart` 3（真实 loopback HttpServer）。
- §4 UI：`ai_chat_page.dart` 生成中/待审批时发送键换停止键（`aiStopButtonKey`）、`_ReasoningPanel`（生成中展开、结束自动折叠、可手开）、`_CancelledLabel` 中性标记；停止后 partial 已在流式文本，历史同文行用 cancelledEchoId 去重；测试 12→17。
- §6 Time 行高：`calendar_page.dart` 新增 `kCalendarHourHeightDetents=[22,33,44,66,88,132,176,264]`、`kCalendarMinHourHeight=12`/`kCalendarMaxHourHeight=400`、`snapCalendarHourHeight()`；分界线 14px 命中带可拖（日/周网格），松手吸附挡位；新增「恢复默认」；`hour_height` 存 `time_view_settings`（NULL = 旧公式 `44*(60/minutesPerRow)`，逐字节不变）；修掉真实 bug：命中带 `MouseRegion` 默认 opaque 吞卡片点击 → `HitTestBehavior.translucent` + `IgnorePointer` 视觉线。测试新 `calendar_row_height_test.dart` 10。
- §13 闪存卡全文：`anki_manage_page.dart` 列表行 subtitle maxLines 2 + 点行打开 `DraggableScrollableSheet`（0.4/0.75/0.95）完整 SelectableText + 标签 chips + 模板列表（`ankiKnowledgeContentKey`/`ankiKnowledgeDetailKeyFor`）；测试新 `anki_manage_page_test.dart` 6。
- §14 复习间隔：新 `review_retention.dart`（`kDefaultReviewRetention=0.85`、三挡 0.80/0.85/0.90、normalize clamp 0.75–0.95）+ `review_retention_provider.dart`；`review_service.grade()` 读设置注入 `FsrsParameters(requestRetention:)`（无仓储回落 0.85）；`review_plan_page` 复习偏好加第三段「复习间隔」SegmentedButton + hint。schema **v36**：`local_settings.review_retention` REAL 可空、`time_view_settings.hour_height` REAL 可空，`_upgradeV35ToV36` + `_ensureColumns` 自愈、不回填；`v36_migration_test.dart` 3 例。
- 门禁：只 format 本轮改动 dart 文件（0 changed）；`dart analyze lib test` = **91 issues / 0 error / 0 warning**（EXIT 0）；全量 `flutter test --concurrency=1` = **+6006 ~2 All tests passed** 11:57 EXIT=0（日志 `E:/dsh-tmp-aot/test-175-full2.txt`；v0.6.10 基线 +5951）。首跑曾 2 例回归：复习间隔段把「添加卡组任务量」挤出首屏（测试改 scrollUntilVisible）、`review_queue_test` 独立重算 FSRS 没传 retention（显式传 `kDefaultReviewRetention`），均按新语义改期望。
- docs：`docs/DATA_MODEL.md` §25（v36 两列 + 读写接口 + 迁移/自愈）；`docs/APPEARANCE_DESIGN.md` §5（应用图标设计/13 文件/待构建验证）；`docs/DESIGN_BLUEPRINT.md:143`（行高规格改为自由拖拽+吸附）；`docs/FEATURE_MATRIX.md` 4 行；`docs/REVIEW_FEEDBACK.md` 改为 14 条 + §13/§14 + 实施状态。
- 未做：§3 UI 设计 token、§7 知识网络图、§8 能力测评、§9 组卷网检索词长度、§10/§11 标签边界与「纳入时间表」；新图标未跑构建；真机未手测；v0.6.11 未出包。

## 2026-10-25 轮次一百七十三：v0.6.10 双端发布（页面缩放整体化 + persona schema v35 + docx 可复现）

- 版本：`app/pubspec.yaml` `version: 0.6.10+29`；`app/lib/core/app_info.dart` `kAppVersion='0.6.10'`、`kAppBuildNumber=29`；`test/core/app_info_test.dart` +2 通过；这一版含 **schema v34 → v35**（`local_settings.user_persona` 只加一列可空、不回填）。
- 提交范围：v0.6.9（93ffe23）之后 9 个提交 —— `5c5a995` 页面缩放改成整体缩放（PageZoom）+ `103dfd1` docs 轮次一百七十一 + persona 7 个（430737c l10n 13 key、6fb2008 领域、2afd9ad schema v35+仓储/provider、d9bf75f AI 注入、4416d5b 编辑页+入口+卡片、76a6d43 docx 固定时间戳、104240b docs）。
- Windows：`scripts/build_windows.ps1` exit=0；`data/app.so` 21,545,864 B（构建时间 13:22:16）；`furnace.exe` 版本资源 `0.6.10+29`；打包前删 `kernel_blob.bin` 110,766,568 B；zip **28 entries / 20,505,322 B / 解压 47,194,647 B**，顶层 exe + 6 个 dll，`data/app.so` 在包、`kernel_blob` 0 条；SHA-256 `0994D1B2C71CF6AB6546E1BFA1142F1E4246DF61DE650DE13329E0A51D34EF5B`。
- Android：`scripts/build_android.ps1` exit=0，Gradle assembleRelease **382.4s**；APK **99,461,550 B（94.9 MB）** SHA-256 `D7C5F5AB5CD994277626B73B1911889E993D9B667B5895FB735FEF6980A142AD`；aapt2 versionCode **29** / versionName **0.6.10** / minSdk 24 / targetSdk 36 / compileSdk 36；证书 `57de8b8f…f32e2db2`（与 v0.5.0–v0.6.9 同一把）。
- dist/：`Furnace-0.6.10-android.apk`、`Furnace-0.6.10-windows-x64.zip`、`RELEASE-v0.6.10.md`（5,290 B；下载表/A 页面缩放整体化/B persona/C docx 可复现/验证/已知未做/发布说明）；旧版 v0.5.8–v0.6.9 件仍在 dist/。
- 验证：全量 `flutter test --concurrency=1` = **+5951 ~2 All tests passed** 17:04 EXIT=0（日志 `E:/dsh-tmp-aot/test-172-full2.txt`，基线 +5898 → 净增 53）；`dart analyze lib test` = 91 issues / 0 error / 0 warning。
- 风险（未做）：页面缩放与 persona 的新界面**双端都未真机手测**；页面缩放不影响系统字体缩放、图片超采样未优化；persona 只整段替换、无导入导出/同步/逐对话开关，且只作用于 AI 对话；docx 固定时间戳后 zip 内部时间不再反映导出时间；微信拖拽仍未真机手测；英文未母语化；网络同步未做。
- 发布提交与 tag `v0.6.10` 用 GitHub REST git/data API 推送（github.com HTTPS 被阻断），提交 sha 与本地一致。

## 2026-10-25 轮次一百七十二：persona 用户自我描述（schema v35，Lead + reasoning-core + threadflow-engine）

**起点**：HEAD `103dfd1`（轮次一百七十一，已推送），工作树干净。用户消息（m16679）：「提供一个 persona 功能，可以放在认知模型内部或者外部，或者说是外部但是有相互作用。让用户自己描述自己。」

**片 1：schema v35 + 仓储 + provider（Lead）**
- `local_settings.user_persona` TEXT 可空（`app/lib/data/database/tables.dart:177`）：存**用户原话**，NULL = 没写过，空白写库前归一成 NULL；迁移只补列、**不回填**（回填会造出一行用户没写过的自述）。
- 迁移：`_upgradeV34ToV35()`（`app/lib/data/database/database.dart:1003-1010`，表不存在直接返回）、`_ensureColumns` 自愈 :310、`schemaVersion => 35` :129、onUpgrade :238；`build_runner` 重生成 database.g.dart（145s / 803 outputs）。
- 仓储：`getUserPersona()`（settings_repository.dart:296）、`updateUserPersona()`（:308，先 ensureSettings，trim 后空→NULL，**不截断长度**）；provider `userPersonaProvider`（settings/application/user_persona_provider.dart，FutureProvider.autoDispose + watchDatabaseRevision，归一化后空→NULL）。

**片 2：领域纯逻辑（reasoning-core，task-186）**
- `app/lib/domain/services/cognitive/user_persona.dart`（145 行）：`kUserPersonaMaxChars=8000`、`normalizeUserPersona`（CRLF/CR 归一、逐行去行尾空白含全角与不换行空格、中间空行与首行缩进保留）、`userPersonaForStorage`（空→null，不截断）、`userPersonaIsPresent`、`userPersonaTooLong`、`userPersonaPromptBlock`（空→''；非空=固定引导行+原文）、`userPersonaPreview`（折叠空白，省略号算在 maxChars 内）。
- 测试 29 例（app/test/domain/services/cognitive/user_persona_test.dart）。

**片 3：AI 注入（Lead）**
- `agent_loop.dart`：`_turnTools()` :1151 先取 persona 再拼提示；新 `_userPersonaBlock()`（:1185，读库异常一律回落 ''，绝不阻断一轮对话）；`_baseRules(String personaBlock)`（:1204）把 persona 插在「今天的日期」之后、「规则：」之前。
- 三条硬口径：**空 persona 提示逐字节不变**（无 persona 的用户行为与加功能前完全一致）、位置在日期后规则前（规则最后读，persona 是背景不是指令）、读失败不阻断。测试 3 例（agent_loop_test.dart 的 persona group）。

**片 4：UI（threadflow-engine，task-187）**
- 新 `app/lib/features/settings/presentation/user_persona_page.dart`：4 个 Key、8000 字计数、超长禁用保存并显示 `personaTooLong(8000)`、保存/失败 SnackBar、有存量才显示清除按钮且走确认框；**provider 读失败显示原始错误而不是空编辑框**（空框会让用户顺手覆盖已存内容）；保存/清除后的重读不盖掉正在编辑的文字。
- `settings_page.dart`：认知模型入口之后加「自我描述」入口（key `settingsUserPersonaTileKey` :39，:135-149），有值显示 40 字预览、无值显示说明。
- `cognitive_model_page.dart`：顶部 `_PersonaCard`（key `cognitiveModelPersonaCardKey` :80，插入 :667，类 :839-880）——空态「还没有写过」、有值前 160 字预览 + 编辑入口。persona 不是认知模型读数，但看认知模型时能一眼看到并就地改（对应用户「外部但相互作用」的要求）。
- 测试：user_persona_page_test 8 例；cognitive_model_page_test 18→20 例（新增默认 provider override 防测试误开真实磁盘库）。

**片 5：文档**
- 新 `docs/PERSONA_DESIGN.md`（一句话/为什么不是结构化档案/领域契约/schema v35/注入三口径/界面/隐私与作用范围/测试锁的事实/仍未做）；`docs/DATA_MODEL.md` 新增 §24（v35）；`docs/FEATURE_MATRIX.md` 在 AI 对话渲染行之后加 persona 行。

**顺手修掉一个既有 flake（Lead）**
- 第一轮全量在 `app/test/domain/services/export/paper_docx_quality_test.dart:59` 失败（`at location [10] is <0> instead of <253>`）：`archive` 包默认把 zip 每个条目的 `lastModTime` 设成 `DateTime.now()`（秒级），「同一输入两次导出字节相等」只在两次 build 恰在同一秒内才成立，机器慢/跨秒就飘。
- `app/lib/domain/services/export/docx_writer.dart` 的 `_archiveFile` 改为固定 `lastModTime = DateTime.utc(2000,1,1,12)/1000`（UTC 正午，任意时区换算后日期同一天），docx 导出**逐字节可复现**；scoped `flutter test test/domain/services/export --concurrency=1` = +174 全绿。
- 第一次全量跑（日志 test-172-full.txt）因此作废；修完重跑才算门禁。

**门禁（实跑，第二轮）**
- `dart format --set-exit-if-changed` 本轮改动 19 个 dart 文件 = **0 changed**（docx_writer 首跑 1 changed 已就地格式化）。
- `dart analyze lib test` = **91 issues / 0 error / 0 warning**（EXIT 0，基线不变）。
- scoped：persona 五文件（v35 迁移 + agent_loop + 领域 + 编辑页 + 认知模型页）= **+93 All tests passed**；export 目录 = +174。
- 全量 `flutter test --concurrency=1` = **+5951 ~2 All tests passed**，17:04，EXIT 0（日志 `E:/dsh-tmp-aot/test-172-full2.txt`；上轮基线 +5905，净增 46 = 迁移 4 + 注入 3 + 领域 29 + 编辑页 8 + 认知模型页 2）。
- 推送待做：`rest-push.ps1`（GitHub REST API，github.com HTTPS 仍被阻断）。

**风险 / 未做**
- 双端真机没手测：编辑页长文本滚动、超长提示、设置页/认知模型页卡片观感；
- persona 只进 **AI 助手对话**提示，解题思维链/拍照整理/组卷等流程不读（刻意的，理由见 PERSONA_DESIGN §7）；
- 没有导入导出/同步/逐对话开关，没有结构化字段（刻意的），编辑页没有「AI 润色」；
- 8000 字上限是拍的，不是标定值；
- l10n 13 个新 key 中文手写、英文直译，未母语化；`flutter gen-l10n` 期间网络 fetch tags 报 128 但生成成功（既有现象）。
- 下一步：v0.6.10 双端出包（persona + docx 可复现修复 + 页面缩放整体化已在 v0.6.9 之后积累）。

## 2026-10-25 轮次一百七十一：目标核验（五片已交付）+ 页面缩放改成整体缩放（Lead）

**起点**：轮次一百七十收尾（HEAD `93ffe23`，v0.6.9 已发布并推送，工作树干净）。
用户消息（m16589）：「你先看看这个目标是否已经完成，已经挂了很久很久了；页面缩放一直没有做；」

**片 1：目标核验（五片交付证据）**
- ① schema 题目实体：`app/lib/data/database/database.dart:125` `int get schemaVersion => 34;`（v12 起的四张题目表及后续 v30–v34 增量迁移都在）。
- ② 收题页：`app/lib/features/questions/presentation/question_intake_page.dart`（1324 行）。
- ③ 拍照手写整理：`question_intake_page.dart` 拖拽/选图 + `handwriting_queue_page.dart`（1523 行）+ `handwriting_proposal_service.dart`（1228 行，含多图整理）。
- ④ AI 解题思维链→步骤→能力动作→卡点评估：`question_reasoning_service.dart`（231 行）、`domain/services/reasoning/reasoning_prompt.dart`、`stuck_point_evaluator.dart`、能力动作词表（`capability_action.dart` + 设置页词表编辑页 + 按动作找题页）。
- ⑤ threadflow 两段式：`domain/services/scheduling/thread_ranker.dart`、`features/thread/application/thread_rank_service.dart`（437 行）、`thread_balance_inputs.dart`、`thread_balance_provider.dart`、`thread_rank_repository.dart`。
- 文档自认的剩余项都是**标定/真机验收**（组卷学科配额、SimilarityWeights.quality、kPreferredActionBoost、微信拖拽真机、板块化 instrument、标定协议），不是五片功能缺口。→ 本轮把该 goal 标为 complete。

**片 2：页面缩放（用户说「一直没有做」）**
- 根因：`app/lib/app/app.dart` 的 `_AppearanceScope` 只把主题 scale 喂给 `MediaQuery.textScaler`，**只缩放文字**；控件、间距、图片不变。主题编辑器滑杆文案却写「影响正文与控件尺寸」，所以用户看到的是「没做」。
- 新增 `app/lib/app/page_zoom.dart`：`PageZoom(scale:, child:)`——布局按 `窗口/scale` 放大成更大的逻辑区域（`LayoutBuilder` 取 `constraints.biggest`），`MediaQuery` 同步缩放 size/padding/viewPadding/viewInsets/systemGestureInsets，再 `ClipRect` + `OverflowBox(topLeft)` + `Transform.scale` + `SizedBox` 绘制回窗口；scale≈1 直接返回 child；保留系统 `textScaler` 不叠加（否则字号翻倍）。背景图（`Backdrop`）在缩放层之外，不随缩放变形。
- `app/lib/app/app.dart`：`_AppearanceScope` 改为 `Widget result = PageZoom(scale: scale, child: child);`，删掉 textScaler 写法，注释说明为什么这不是 ThemeData 缩放（会把字号算两次）。
- 测试 `app/test/app/page_zoom_test.dart` **7 例**：1.0 不动布局、1.5 逻辑尺寸/内边距/键盘 inset 按比例、0.8 逻辑区域变大、Transform 缩放因子与 ClipRect、点按命中跟随缩放、系统 textScaler 只乘一次、0/负数/NaN/∞ 一律忽略。
- 文档修正：`docs/FEATURE_MATRIX.md:33`（旧行写「检索 textScaleFactor/scaleFactor 均无命中」是审计遗漏，实际由 textScaler 承担）与 :154 改成 ✅；`docs/APPEARANCE_DESIGN.md:27` 页面缩放一行加「2026-10-25 补真」。

**门禁（实跑）**：`dart format` 本轮 3 个 dart 文件（含 app.dart）0 changed；`dart analyze lib test` = **91 issues / 0 error / 0 warning**（EXIT 0，基线不变）；`flutter test test/app/page_zoom_test.dart --concurrency=1` = **+7 All tests passed**；全量 `flutter test --concurrency=1` = **+5905 ~2 All tests passed**，15:20，EXIT 0（日志 `E:/dsh-tmp-aot/test-171-full.txt`；上轮基线 +5898，净增 7）。

**风险 / 未做**：双端真机没手测缩放观感（80% / 100% / 150% 下的文字清晰度与布局）；背景图不随缩放（有意）；缩放跟随主题文档，切主题会切缩放；系统级文字缩放仍独立生效；页面缩放没有独立于主题的快捷入口。
- 下一步（用户 m16679 新需求）：persona 自我描述功能（用户自己描述自己，存本地、进 AI 系统提示、在认知模型页可见）；随后 v0.6.10 出包。
## 2026-10-25 轮次一百七十：v0.6.9 双端发布（Lead）

**起点**：轮次一百六十九收尾（HEAD `ff35552`，工作树干净，origin/main 已同步）。

- 版本：`app/pubspec.yaml` `version: 0.6.9+28`；`app/lib/core/app_info.dart` `kAppVersion='0.6.9'`、`kAppBuildNumber=28`；`test/core/app_info_test.dart` +2 通过。**schema 无新迁移，仍 v34**（v33→v34 是上一轮 settings 加 `question_library_sort_mode`）。
- 范围：`git log --oneline v0.6.8..HEAD` = **11 个提交** —— 轮次168 排序偏好落盘（v34）/题库排序偏好/详情页第 N 共 M 题+跳题号/§44，轮次169 复习节奏修复（新卡每 5 张插 1 张、同一卡重插上限 2、跳过本张、等待态结束本轮）+ 模板卡行快照修复 + docs。
- 构建（同一后台 job，日志 `E:/dsh-tmp-aot/build-170.log`，exit 0）：`WINDOWS_EXIT=0`、`ANDROID_EXIT=0`；Gradle assembleRelease **272.8s**。
  - Windows：`data/app.so` **21,529,480 B @2026-10-25 11:12:07**；`furnace.exe` 版本资源 **0.6.9+28**；打包前删 `data/flutter_assets/kernel_blob.bin` **110,766,568 B**；从 ASCII junction `E:\Document\furnace-build\build\windows\x64\runner\Release` 打包。
  - Android：APK **99,445,170 B（94.8 MB）**；aapt2：versionCode **28** / versionName **0.6.9** / minSdk 24 / targetSdk 36 / compileSdk 36；证书 `57de8b8f…f32e2db2`（与 v0.5.0–v0.6.8 同一把）。
- dist 三件（gitignore，不入库）：`Furnace-0.6.9-windows-x64.zip` **20,503,544 B / 28 entries / 解压 47,178,263 B / SHA-256 FB0AFB4BDB90F70005E6DBB32921E21D823C130B14752094C37FC54597241FEC**；`Furnace-0.6.9-android.apk` **SHA-256 F9CB3487C70E1EA127069BE252715A5FAB916F8AC668484C1DABE0109E3DFB7A**；`RELEASE-v0.6.9.md` **6,171 B**（下载表、schema 提示、A–E 变更、验证、已知未做、发布说明）。
- 验证：全量 `flutter test --concurrency=1` = **+5898 ~2 All tests passed**，12:27，EXIT 0（上一轮已跑，日志 `E:/dsh-tmp-aot/test-169-full2.txt`）；发布提交只改版本号，复跑 `test/core/app_info_test.dart` +2 通过。相对 v0.6.8 的 +5844 净增 54（v34 迁移 4、排序 codec 3、题号进度 2、题库页 24→28、详情页 67→73、新卡节奏 19、`mayReinsert` +7、复习服务 17→22 含模板卡回归 1、复习页 15→19）。
- 发布：提交 `chore(release): v0.6.9`（app_info.dart / pubspec.yaml / PROGRESS.md）；tag `v0.6.9`（annotated）指向该发布提交；github.com HTTPS 仍被阻断，提交用 `E:/dsh-tmp-aot/rest-push.ps1`（GitHub REST git data API + 代理 127.0.0.1:7890）推送，tag 用 `rest-tag-069.ps1`（POST /git/tags + /git/refs）。
- 风险 / 未做：双端新行为都没真机手测（排序记忆、进度行、跳题号、跳过/结束本轮、模板卡修复）；跳过不持久化；新卡节奏 5 与重插上限 2 是常量不可配；新卡交错不改每日配额；题库排序切题号/错题优先仍读全库、耗时未测；偏好读到前首帧按「最新」排；跳题号只认题号、同号取第一道；题号无 UNIQUE；微信拖拽收题仍无真机证据；快照判定仍是启发式；英文未完整本地化；同步无网络层。
- 下一步候选：①真机逐屏验收 v0.6.9（排序记忆/进度/跳题号/跳过）②复习「跳过」持久化（本周不再出现）③题库排序读全库分页化 ④组卷配额/相似题权重标定 ⑤错题本统计扩展（按学科/标签正确率）。

## 2026-10-25 轮次一百六十九：复习节奏修复（新卡交错 / 重插上限 / 跳过 / 结束等待）+ 模板卡行快照（Lead + reasoning-core + threadflow-engine）

**起点**：轮次一百六十八收尾（HEAD `7c89b60`，v0.6.8 已发布并推送，工作树干净）。
用户反馈（m16094）：「闪存卡重复出现频率有点高；为了复习我可能难以推进新的卡片，我最近几次反反复复都是那几张卡」。
根因不在 band 排序而在展示层：`unseen` 段整段跟在所有复习卡后面（复习没做完就永远见不到新卡）；答错的卡每
`relearnGapCards`(=3) 张重插且无次数上限。另有一条服务层缺陷：模板卡在会话内重做时读不到刚写过的行（见片 4）。

**片 1：reasoning-core（task-183）—— 节奏纯逻辑**
- 新建 `app/lib/features/anki/application/review_pacing.dart`：`const int kNewCardEveryReviews = 5;`（:6）、
  `List<T> paceNewCards<T>({required List<T> reviews, required List<T> newCards, int every = kNewCardEveryReviews})`
  （:23-43；`every < 1` 抬到 1，每满 every 张复习卡插一张新卡，余下新卡接队尾，不改入参）。
- `app/lib/domain/services/cloze/forced_loop.dart`（150→168 行，已有行为零改动）：`static bool mayReinsert({required int reinsertsSoFar, int max = kMaxForcedReinsertsPerSession})`（:158-164，负数按 0）、
  `const int kMaxForcedReinsertsPerSession = 2;`（:168）。
- 测试：新 `app/test/features/anki/review_pacing_test.dart` **19 例**；`app/test/domain/services/cloze/forced_loop_test.dart` 22→**29**（`mayReinsert` +7）。

**片 2：Lead —— buildQueue 接线**
- `app/lib/features/anki/application/review_service.dart`：算完日配额后把 `keptDue` 按 band 拆成 reviewKept / newKept
  （`ordering.bandByCardStateId[...] == ReviewBand.unseen`），再 `_interleave(orderedForced, paceNewCards(reviews: reviewKept, newCards: newKept))`（:413-428）。
  **不改 band 内部顺序、不改日配额**，只改插入节奏。
- `app/test/features/anki/review_service_test.dart` 17→**22**：新 group「新卡交错」（12 复习卡 + 3 新卡 → 新卡位置 [5,11,14]；3+2 → [3,4]；0+3 → 全表；7+0 数量不变）+ 片 4 的模板卡行快照 1 例。

**片 3：threadflow-engine（task-184）—— 复习页 UI**
- `app/lib/features/anki/presentation/review_page.dart`（+129/-3）：`reviewSkipCardKey`（:23）、`reviewEndSessionKey`（:26）、
  `_finished`（:142，区分「库里没卡」与「主动收尾」）、`_reinsertCounts`（:154）、`_reinsertForced` 先 `ForcedLoop.mayReinsert` 判上限（:456-501）、
  `_skipCurrent`（:603：不写 review_logs、不动排期，`awaitingSolution`/提交中禁用）、`_endSession`（:647：游标推过队尾）、
  跳过按钮（feedback 两态 :1469/:1523）、等待态「结束本轮」（:1082）、完成态 `_FinishedState`。
- 测试 `app/test/features/anki/review_page_test.dart` 15→**19**：跳过→下一张且无 review_logs；单张跳过→完成态；等待态结束本轮→完成态；同一强制卡一轮最多插回 2 次。

**片 4：Lead —— 模板卡行快照（`refreshItem` 按行 id 读）**
- 缺陷：模板卡的 state 行 `knowledge_point_id` 是 NULL（`anki_repository.dart:190-211` 的 `getOrCreateCardState` 只按 `card_template_id` 键行），
  而 `refreshItem` 原用 `unitCardState(knowledgePointId, unitKey)` 重读 → 模板卡永远返回 null → 一直拿答题前的快照：
  `forcedBefore` 永远 0（一次答对就被当成从未绑定放掉，D11 的第二次连续答对永远数不到），FSRS 也按旧基线重复排期而让卡回得更频。
- 修法：`anki_repository.dart` 新增 `Future<CardState?> cardStateById(String id)`（:637）；`refreshItem`（`review_service.dart:1129-1137`）改用它。
- 测试：review_service_test 新增 1 例（答错→`refreshItem` 读到 `forced=1/forcedStreak=0`→答对仍绑定→再刷新后第二次答对才 `released`）。

**l10n**：Lead 手改两个 ARB（tools.edit 追加）+ `flutter gen-l10n` exit 0，3 key：`ankiSkipCard`、`ankiSkipCardDone`、`ankiForcedWaitEnd`。

**docs**：`docs/MINDNET_INTEGRATION.md` 新增 §5.3（展示层节奏）与 §5.4（模板卡行快照）；`docs/MINDNET_CONTRACT.md` §9.5 补展示层口径；
`docs/FEATURE_MATRIX.md` :118/:121 两行同步（会话重插上限、新卡交错与跳过）。

**门禁（Lead 实跑）**：只 format 本轮 9 个 dart 文件 → `Formatted 9 files (0 changed)`；`dart analyze lib test` =
**91 issues / 0 error / 0 warning**（与基线一致）；scoped：review_pacing +19、forced_loop +29、review_service +22、review_page +19；
全量 `flutter test --concurrency=1` = **`+5898 ~2: All tests passed`**（12:27，EXIT 0，日志 `E:/dsh-tmp-aot/test-169-full2.txt`；
基线 +5863，净增 35 = pacing 19 + forced_loop 7 + service 5 + page 4）。

**未做 / 风险**：跳过不持久化（不与明天同步、没有「本周不再出现」）；5 与 2 都是常量、不能在设置里改；
4 个 UI 行为与模板卡修复都没有真机手测；首跑全量曾在编辑途中读到混合源码出现 1 例假失败（`refreshItem` 旧实现 + 新测试），
停掉重跑后 +5898 全绿——教训：全量跑的时候不要再改 lib 里的被测源码。

## 2026-10-24 轮次一百六十八：排序偏好落盘（schema v34）+ 详情页做题进度与跳题号（Lead + question-intake + threadflow-engine）

**起点**：轮次一百六十七收尾（HEAD `4a2f44c`，v0.6.8 已发布并推送，工作树干净）。
选片理由：§42.3 与 §43.4 自己写明的两条边界——排序偏好只活在内存、重启回到「最新」；详情页
只有「上一题/下一题」没有进度与跳题号。三个小片都不调模型，只有排序落盘需要 schema v34。

**片 1：Lead 数据层（schema v34 + 偏好读写 + 题号定位）**
- `app/lib/data/database/tables.dart`：Settings 表加可空 `questionLibrarySortMode`（:164-166，存稳定 code，
  NULL = 出厂，表定义不 import 域层，照 v29 `tagTreeSortMode` 先例）。
- `app/lib/data/database/database.dart`：`schemaVersion => 34`（:125）、onUpgrade `if (from < 34)`（:231）、
  `_ensureColumns` 自愈补列（:299）、`_upgradeV33ToV34()`（:975-983：表不存在 return，否则 `_addColumnIfMissing(m, 'local_settings', localSettings.questionLibrarySortMode)`）；
  `database.g.dart` 重新 build_runner 生成（exit 0 / 824 outputs）。
- `app/lib/data/repositories/settings_repository.dart`：`:263` `getQuestionLibrarySortMode()`、`:276` `updateQuestionLibrarySortMode(String?)`
  （先 `ensureSettings()`，trim 空 → NULL，刷 `updatedAt`）。
- `app/lib/features/questions/application/question_library_sort.dart`：`:39` `questionLibrarySortCode`、
  `:52` `questionLibrarySortFromStorage`（NULL/空串/未知 → newest）；新 `question_library_sort_preference.dart:19`
  `questionLibrarySortPreferenceProvider`（watch `databaseRevision` + getter → fromStorage）。
- `app/lib/data/repositories/question_repository.dart`：`:194` `QuestionSerialPosition { index, total }`、
  `:407` `serialPosition(int)`（<1 → null；没有编号题 → null；index = 题号 <= 本题号的题数，同号共享）；
  provider `app/lib/features/questions/presentation/question_detail_providers.dart:85`。
- 测试：新 `app/test/data/database/v34_migration_test.dart` 4 例；sort 测试 17 → 20（+3 codec）；
  repository 测试 18 → 20（+2 serialPosition）；scoped 三文件 `+44: All tests passed!`。

**片 2：题库页排序落盘（question-intake，task-181）**
- `question_bank_page.dart`：`:175 _sortOverride`、`:178 _persistedSort`、`:184-185 get _sort`（手选优先，其次存档值）；
  `:289-301 _persistSort`（写库失败只 debugPrint）；`:679-683` build watch 偏好并同步 `_persistedSort`（不 setState，
  防写库触发的偏好重读顶掉本次手选）；`:753-758 onSelected 先 setState 再 `unawaited(_persistSort)`。
- 测试 24 → **28 例**（`group('排序偏好落盘')` :501，+4）：有存档值首帧就是该档、切换写库并保持、坏值回落最新、写库失败仍能切。

**片 3：详情页「第 N / 共 M 题」与跳题号（threadflow-engine，task-182）**
- `question_detail_page.dart`：`:108 questionDetailSerialPositionKey`、`:112 questionDetailJumpSerialKey`、
  `:232 _jumpToSerial`、`:263 _openNeighborSerial`（pushReplacement，不堆返回栈）、`:281` watch 进度、
  `:307-310` AppBar `IconButton(Icons.tag)`、`:318-326` 进度行、`:394-455 _JumpToSerialDialog`（认不出不关框写 errorText，
  认得出回 `QuestionNumberQuery`；找不到该题号 SnackBar 报号、页面不动；命中当前题 no-op）。
- 测试 67 → **73 例**（`group('题号进度行与跳题号')` :2138，+6）。

**l10n**：Lead 手改两个 ARB（tools.edit 追加）+ `flutter gen-l10n` exit 0，8 key：`questionDetailSerialPosition(index,total)`、
`questionDetailJumpSerialTooltip/Title/FieldLabel/Hint/Invalid/NotFound(serial)/Action`（getter `app/lib/l10n/app_localizations.dart:9057-9099`）。

**门禁（Lead 独立复跑）**：只 format 本轮 14 个 dart 文件 → `Formatted 14 files (0 changed)`；`dart analyze lib test` =
**91 issues / 0 error / 0 warning**（与基线一致）；scoped 五文件 → `+145: All tests passed!`；全量
`flutter test --concurrency=1` = **`+5863 ~2: All tests passed`**（10:41，EXIT 0，日志 `E:/dsh-tmp-aot/test-168-full2.txt`；
基线 +5844，净增 19 = v34 4 + sort 3 + repo 2 + bank 4 + detail 6）。

**全量首跑踩到的坑**：v32/v33 迁移测试里把「升到最新版」写死成 `expect(await userVersionOf(db), 33)`，schema 升 34 后
两文件 8 例报 `Expected:<33> Actual:<34>`；改成 `expect(await userVersionOf(db), db.schemaVersion)`（v32 4 处、v33 5 处）后
两文件 `+9` 全绿，且以后升版不再误报。教训：迁移测试断言「最新版」要用 `db.schemaVersion`，不要写字面量。

**未做 / 风险**：双端新行为（排序记忆、进度行、跳题号）未真机手测；偏好读到前首帧仍按「最新」排（异步读库间隙，无骨架）；
写库失败无单独用例（页面无注入 seam）；跳题号只认题号不认题名/id，同号多题取第一道；小屏 AppBar 三个 action 与标题挤压未真机验。

**下一步**：v0.6.9 出包（v0.6.8 之后累计本轮 5 提交）。

## 2026-10-24 轮次一百六十七：v0.6.8 双端发布（Lead，goal round 38）

**起点**：轮次一百六十六收尾（HEAD `5b9ee0a`，工作树干净，origin/main 同步）。
选片理由：v0.6.7 之后已攒两轮 9 个提交（轮次一百六十五自测防剧透、轮次一百六十六题库排序 + 详情页翻页），
都是用户打开就能看到的功能，直接出安装包。**无 schema 变更（仍 v33）、无新迁移、不调模型。**

**版本**：`app/pubspec.yaml` `version: 0.6.8+27`；`app/lib/core/app_info.dart`
`kAppVersion='0.6.8'`、`kAppBuildNumber=27`；`flutter test test/core/app_info_test.dart --concurrency=1`
→ `+2: All tests passed`。

**构建（scripts/build_windows.ps1 + scripts/build_android.ps1，同一后台 job，日志 E:/dsh-tmp-aot/build-167.log）**
- Windows：exit=0；`data/app.so` 21,513,096 B（@2026-10-24 05:52:41）、`furnace.exe` 版本资源 0.6.8+27；
  打包前删 `data/flutter_assets/kernel_blob.bin` 110,766,568 B。
- Android：exit=0；Gradle assembleRelease **100.3s**；APK 99,363,198 B；
  aapt2 badging：`versionCode 27` / `versionName 0.6.8` / minSdk 24 / targetSdk 36 / compileSdk 36；
  证书 SHA-256 `57de8b8fed7e4a44cb278ae83b147744dd3918124465634fd135e0bbf32e2db2`（与 v0.5.0–v0.6.7 同）。
- 发布件（dist/，gitignore）：
  - `Furnace-0.6.8-android.apk` 99,363,198 B，SHA-256 `C4E2D926B223F92D981B60CEC0956887562AD44143DBA46582FA4D4CBDF6D303`；
  - `Furnace-0.6.8-windows-x64.zip` 20,495,010 B / 28 entries / 解压 47,161,803 B（28 files）/
    顶层 `furnace.exe` + 6 dll / `data/app.so` 在包 / `kernel_blob` 0 条，
    SHA-256 `CF16169BB23D2D48405A7426422B2FFB2A9D5BAF27CA36B482F0AE0B946242A5`；
  - `RELEASE-v0.6.8.md`（下载表 / A 自测整页防剧透 / B 题库排序 / C 详情页翻页 / 验证 / 已知未做 / 发布说明）。

**发布提交与推送**
- `73efc82` chore(release): v0.6.8（`app/pubspec.yaml` + `app/lib/core/app_info.dart`）已用
  `E:/dsh-tmp-aot/rest-push.ps1`（GitHub REST git data API + 代理 127.0.0.1:7890）推送，
  REMOTE_VERIFY equals_local=True、ORIGIN_AHEAD 0；远端 main = `73efc82`。
- tag：本地 `v0.6.8` 为 annotated tag 对象 `4cde025`（tagger 2026-10-24T05:56:56+08:00），
  指向 `73efc82`；用 `E:/dsh-tmp-aot/rest-tag-068.ps1` 推送（POST /git/tags + POST /git/refs），
  远端 `refs/tags/v0.6.8` 对象 `9388491`（GitHub API 重建，sha 与本地不同属正常），
  API GET /git/tags/9388491 验证 `object.sha = 73efc82`、type=commit。

**打包教训（本轮踩到）**
- `[IO.Compression.ZipFile]::CreateFromDirectory` 在中文仓库路径上静默生成 22 B 空 zip（0 entries）；
  必须从 ASCII junction 路径 `E:\Document\furnace-build\build\windows\x64\runner\Release` 打包。
- `Copy-Item` 用变量拼目标路径曾静默没复制且不报错；改用绝对路径重复制并复核 `Length` 才可靠。

**门禁**：功能提交 `5b9ee0a` 上的全量 `flutter test --concurrency=1` = `+5844 ~2: All tests passed`
（10:47，EXIT 0，日志 `E:/dsh-tmp-aot/test-166-full.txt`，基线 +5818）；`dart analyze lib test` =
91 issues / 0 error / 0 warning；发布提交只改版本号，已复跑 `test/core/app_info_test.dart`（+2）。

**未做 / 风险**：双端新行为仍未真机手测（防剧透 / 排序 / 翻页）；排序偏好不持久化、题号与错题优先读全库；
翻页无「跳题号」与进度显示；题号无 UNIQUE 约束仍可能重号；微信拖拽收题仍无真机证据；英文未母语化；
无网络同步。**PROGRESS 本条。**

## 2026-10-24 轮次一百六十六：题库页排序 + 详情页按题号翻「上一题 / 下一题」（Lead + reasoning-core + question-intake + threadflow-engine）

**起点**：轮次一百六十五收尾（HEAD `9d83ada`，v0.6.7 已发布并推送，工作树干净）。
选片理由：题库页原来没有任何排序入口（只能按读表顺序看），题号与错题数都只显示不能用；
详情页看完一道只能退回列表再点下一道。两件都是「题库已有数据、缺一个入口」的缺口，
互补且都不需要 schema 迁移。**无 schema 变更（仍 v33）、不调模型、不写库。**

**片 1：题库排序纯函数（reasoning-core，task-178）**
- 新 `app/lib/features/questions/application/question_library_sort.dart`（88 行）：
  `enum QuestionLibrarySort { newest, serial, wrongFirst }` :22、
  `sortQuestionLibraryEntries(...)` :36-48；`_stableSorted` :50-64 用下标排序解决
  Dart `List.sort` 不稳定；`_compareSerial` :66-84（升序、null 最后、同号按 id）；
  `_compareWrongFirst` :86-88（降序、同次数保原序）；三种排序都返回不可变新列表。
- 新测试 292 行 **17 例**（空表/单条、newest 原样、serial、wrongFirst、不可变、30 条大表确定性）。

**片 2：题库页排序菜单（question-intake，task-179）**
- `question_bank_page.dart`：顶层 key `questionBankSortMenuKey` :75 / `questionBankSortMenuItemKey` :78；
  `_sort` :175；`_readsFullLibrary => _filter.isNotEmpty || _sort != newest` :217-218，
  5 处 provider 入参统一换成它（:274/:381/:416/:586/:654）；`_visibleEntries` :439-445
  先 filter 再 sort；AppBar 加 `PopupMenuButton<QuestionLibrarySort>` :719-742（当前档带勾选）。
- 测试 20 → **24 例**（`group('排序菜单')` :402，+4）：默认最新仍读 500 总览档、题号升序且改读全库档、
  错题优先降序、勾选跟随。

**片 3：题号邻居数据层与 provider（Lead）**
- `app/lib/data/repositories/question_repository.dart`：新 `QuestionSerialNeighbor` :164、
  `QuestionSerialNeighbors` :175（含 `empty/isEmpty/isNotEmpty`）、
  `serialNeighbors(int serialNo)` :349——previous 查 `<` 降序、next 查 `>` 升序，
  同号多题按 `created_at`/id 兜底；`serialNo < 1` 直接空邻居。
- `question_detail_providers.dart:69` `questionSerialNeighborsProvider`（无题号返回 null）。
- 测试 `question_repository_test.dart` 16 → **18 例**（+2：三题首尾各缺一头、跳号找最近 + 越界 + 0/负数空）。
- l10n 6 key（Lead 手改 ARB + `flutter gen-l10n` exit 0）：`questionLibrarySortTooltip/Newest/Serial/WrongFirst`、
  `questionDetailPreviousQuestion`、`questionDetailNextQuestion`（getter `app_localizations.dart:9027-9057`）。

**片 4：详情页 AppBar 翻页箭头（threadflow-engine，task-180）**
- `question_detail_page.dart`：key :97/:101；`_openNeighbor` :208 用 `pushReplacement`（不加深返回栈）；
  build 只 watch 一次 :221-222；AppBar actions :230-247。无题号 / loading / error → 两按钮禁用占位；
  该侧无邻居 → 该侧禁用。
- 测试 64 → **67 例**（新 group :2034，+3）：中间题双向翻页且无 BackButton、第一题上一个禁用、
  清空题号后两按钮都禁用仍占位。

**门禁（Lead 实跑）**：9 个改动的代码/测试 dart 文件 format 0 changed（3 个 l10n 生成文件由 gen-l10n 产出）；`dart analyze lib test` = **91 issues / 0 error /
0 warning**（EXIT 0）；scoped 全绿（排序 +17、题库页 +24、详情页 +67、仓储 +18）；全量
`flutter test --concurrency=1` = **`+5844 ~2: All tests passed`**（10:47，EXIT 0，日志
`E:/dsh-tmp-aot/test-166-full.txt`；基线 +5818，净增 26）。

**文档**：`docs/QUESTION_BANK_DESIGN.md` 新增 §42（题库页排序：42.1 纯函数 / 42.2 页面接线 / 42.3 测试门禁边界）
与 §43（详情页按题号翻页：43.1 数据层 / 43.2 provider / 43.3 UI / 43.4 测试门禁边界）；
`docs/DATA_MODEL.md` 不动（无迁移）。**PROGRESS 本条。**

**未做 / 风险**：排序偏好不持久化（重启回「最新」）；切到题号/错题优先会读全库，几千题时的读表耗时未测；
翻页没有跳题号输入框与「第 N / 共 M 题」进度；小屏极窄时 AppBar 两个 action 会挤压标题，真机未验；
自测中翻页会随新页面回到未自测状态（既有口径）；英文未母语化；真机未手测。



**起点**：轮次一百六十四收尾（HEAD `79a5e1f`，v0.6.7 已发布并推送，工作树干净）。
选片理由：`docs/QUESTION_BANK_DESIGN.md` §34.3 边界「自测中只藏答案/解析/答案截图；「AI 解题」区、
知识点 chip、相似题仍可见（它们可能剧透步骤）」+ §35.3 再次登记同一缺口（:1942）⇒ 自测未提交时整页防剧透。
**无 schema 变更（仍 v33）、不调模型、不写库。**

**片：详情页自测防剧透（Lead）**
- `app/lib/features/questions/presentation/question_detail_page.dart`（1897 → 1965 行）：
  - 新顶层 key `questionDetailSpoilerGuardHintKey` :64 / `questionDetailReasoningSectionKey` :68 /
    `questionDetailSimilarSectionKey` :72。
  - `_QuestionDetailPageState` 加 `_spoilersHidden` :111 与 `_onSelfTestChanged` :113（mounted + 同值早退）。
  - build :194-261：`QuestionZujuanSearchButton` 加 `detail != null && !_spoilersHidden` 条件 :225；
    `QuestionAuditSection` 保留 :228（只报缺项/重复，不剧透解法）；隐藏时显示一行提示 :231-241，
    同时收起 `_ReasoningSection` / `_SimilarQuestionsSection` :242-257。
  - `_QuestionBody` 加可选 `ValueChanged<bool>? onSelfTestChanged` :290；
    `_notifySelfTestChanged()` :323；`_toggleSelfTest()` :327 与 `_submit()` :347 在 setState 后各调一次。
  - `_ReasoningSection` / `_SimilarQuestionsSection` 构造函数补 `super.key`。
- l10n 1 key（Lead 手改 `app_zh.arb`/`app_en.arb` + `flutter gen-l10n` exit 0）：
  `questionDetailSelfTestSpoilerHidden`（getter `app/lib/l10n/app_localizations.dart:8859`）。
- 测试 `app/test/features/questions/presentation/question_detail_page_test.dart` 62 → **64 例**（+2）：
  ①开自测收起三块 + 提示出现，提交后三块回来；
  ②不提交直接结束自测，三块也恢复、入口文案回到「自测」。

**门禁（Lead 实跑）**：format 2 文件 0 changed；`dart analyze lib test` = 91 issues / 0 error / 0 warning
（EXIT 0）；scoped `flutter test ...question_detail_page_test.dart --concurrency=1` = `+64: All tests passed!`；
全量 `flutter test --concurrency=1` = **`+5818 ~2: All tests passed`**（10:53，EXIT 0，日志
`E:/dsh-tmp-aot/test-165-full.txt`；基线 +5816，净增 2）。

**未做 / 风险**：防剧透只在题目详情页（题库卡片/组卷预览仍显示题干摘要，不做全局遮罩）；
`_spoilersHidden` 是页面本地 State，切走再回来随重建重置（自测开关本身也不持久，既有口径）；
真机未手测；英文未母语化。

## 2026-10-24 轮次一百六十四：v0.6.7 双端发布（题号高水位 v33 + 多段题号搜索 + 组卷缺口原因）

**起点**：轮次一百六十三收尾（HEAD `fa54dc0`，schema v33，全量 +5816 全绿，工作树干净）。
v0.6.6 之后只有轮次一百六十三的 5 个提交，但含 **schema v32→v33 迁移**与三个用户点得到的界面变化，出一版安装包。

**版本**：`app/pubspec.yaml` `version: 0.6.7+26`；`app/lib/core/app_info.dart`
`kAppVersion='0.6.7'`、`kAppBuildNumber=26`；`test/core/app_info_test.dart` +2 通过。
**schema v33**（相对 v0.6.6 的 v32 有迁移：新表 `question_serial_counters`，不回填历史、只抬水位）。

**Windows**（`scripts/build_windows.ps1`，ASCII junction `E:\Document\furnace-build`）：exit=0；
`data/app.so` 21,496,712 B @04:58:24；`furnace.exe` 版本资源 `0.6.7+26`；
打包前删 `kernel_blob.bin` 110,766,568 B；zip **28 entries / 20,488,374 B / 解压 47,145,419 B**，
顶层 exe + 6 个 dll，`data/app.so` 在包、`kernel_blob` 0 条；
SHA-256 `AE107F2AFF542851E75BBCC313C4D4646DF49EE1D74B4AD4D3A111D01687D93B`。

**Android**（`scripts/build_android.ps1`）：exit=0，Gradle assembleRelease **119.2s**；
APK **99,346,814 B（94.7 MB）** SHA-256 `5ADD367296A183A1E4F92957EAA4B1B9532BF45AECE19AEB90C12D2F23E6C4A8`；
aapt2 `versionCode 26` / `versionName 0.6.7`、minSdk 24 / targetSdk 36 / compileSdk 36；
证书 `57de8b8f…f32e2db2`。

**dist/**（gitignore，未入库）：`Furnace-0.6.7-android.apk`、`Furnace-0.6.7-windows-x64.zip`、
`RELEASE-v0.6.7.md`（下载表 / A 题号高水位 / B 多段题号搜索 / C 组卷缺口原因 / 验证数字 / 已知未做 / 发布说明）。

**门禁沿用**：功能提交 `fa54dc0` 上全量 `flutter test --concurrency=1` = +5816 ~2 All tests passed
（10:23，EXIT 0，日志 `E:/dsh-tmp-aot/test-163-full2.txt`）；`dart analyze lib test` = 91 / 0 / 0；
发布提交只改版本号与本文档，已复跑 `test/core/app_info_test.dart` +2 通过。

**未做 / 风险**：双端新行为未真机手测；题号仍无 UNIQUE；迁移前删掉的号与外部改号高水位不知道；
多段题号只接题库搜索；`PaperGapNote.messageZh` 中文硬编码；英文未母语化；无网络同步。

## 2026-10-24 轮次一百六十三：编号高水位 v33 + 多段题号搜索 + 组卷缺口解释句（Lead + 3 teammate 并行）

**起点**：轮次一百六十二收尾（HEAD `f7220b7`，schema v32，v0.6.6 已发布，全量 +5777 全绿，工作树干净）。
选片理由：`docs/QUESTION_BANK_DESIGN.md` §11 诚实清单②「"发出即永久保留"未做到：删掉最大号那题后号会被
下一题接手」、§11「题号多段筛选仍未做」、§10 诚实清单「PaperGapNote 只在领域层与测试里，没有单独界面块」。
**schema v32 → v33（新增单行表 `question_serial_counters`），不调模型。**

**片 1：schema v33 编号高水位（Lead）**
- 表 `app/lib/data/database/tables.dart:1630`；`database.dart`：tables 列表 :78、v33 doc 链 :115-119、
  `schemaVersion => 33` :121、onUpgrade :224、自愈建表 :433、`_upgradeV32ToV33()` :946（建表后把高水位
  抬到现存最大号）、`_raiseQuestionSerialHighWaterToCurrentMax()` :1252。
- `question_repository.dart` :206-218：同一事务内读 `MAX(serial_no)` + 读高水位行 →
  `allocateQuestionSerial` → 插入 → `insertOnConflictUpdate(id:1,lastIssued:serialNo)`。
- 包导入：`backfillQuestionSerialNumbers()` :1219 两个出口都抬水位，带号包导入的号同样不回收。
- 测试：`v33_migration_test.dart` 新文件 **5 例**、仓储 15 → **16 例**（新增删最高号后不接手、
  老库无高水位行、并发 6 题、模拟带号导入后抬水位）。

**片 2：编号分配纯函数（reasoning-core/task-175）**
- `domain/services/questions/question_serial_allocator.dart`（54 行纯 Dart）：`kMaxAllocatableQuestionSerial
  = 999999999` :27、`allocateQuestionSerial({highestExisting,lastIssued})` :37（取合法候选最大 M，
  无候选→1，否则 M+1，达上限饱和不回绕）。测试 **21 例**。

**片 3：题库搜索支持多段题号（question-intake/task-177）**
- `application/question_library_filter.dart` :172-178：`_matchesText` 开头复用 `parseQuestionSerialBatch`
  （:26 import），批里无 rejected 段且题号命中 → true；原来的「单号 + 文本子串」回落未改。
- 测试 82 例（+8：`TR-1,3,5`、范围、混无效段、单号不误判、无号题、文本回落）。

**片 4：组卷缺口清单显示 PaperGapNote（threadflow-engine/task-176）**
- `presentation/question_paper_page.dart`：:98/:102 section keys、:105 `questionPaperGapNoteKeyFor(id)`、
  :472/:481 传 notes、:640 `_GapSection` 加 notes/sectionKey、:691 `_GapEntry` 有 note 两行
  （「• labelZh」+ messageZh）、无 note 回落旧「• 名称」、notes 空完全旧行为。
- 口径：保留「• 」前缀（labelZh=知识点名，与旧断言逐字一致，旧测试不改），Lead 已确认。
- 测试 27 → **29 例**（真实 provider 解释句、notes 空回落）。

**门禁（Lead 实跑）**：13 个改动 dart 文件 format 0 changed；`dart analyze lib test` = 91 issues /
0 error / 0 warning；scoped 五文件 **+151**（v33 5 + 仓储 16 + 分配器 21 + 题库筛选 82 + 组卷页 29），
另有 `v32_migration_test.dart` 4 例随 schema 升到 33 改 `user_version` 断言后全绿；
全量 `flutter test --concurrency=1` = +5816 ~2 All tests passed（10:23，EXIT 0；基线 +5777）（基线 +5777）。

**未做 / 风险**：编号仍无 UNIQUE（跨库合并可能同号）；高水位只保证「发过的号不再发」，不保证连续；
迁移前删掉的号与被外部工具改的号不知道；多段题号只接题库搜索；`PaperGapNote.messageZh` 仍中文硬编码
未接 l10n；空卷分支不渲染缺口小节（既有行为）；真机未手测。

## 2026-10-24 轮次一百六十二：v0.6.6 双端发布（清空全部作答记录 + 自测统计行 + 明细逐条删除）

**起点**：轮次一百六十一收尾（HEAD `834ae64`，schema v32，全量 +5777 全绿，工作树干净）。
v0.6.5 之后攒了两轮（10 个提交）：轮次一百六十的「设置页学习数据清空全部作答记录」、一百六十一的
「题库页自测统计行 + 自测明细逐条删除」。都是用户点得到的界面变化，出一版安装包。

**版本**：`app/pubspec.yaml` `version: 0.6.6+25`；`app/lib/core/app_info.dart`
`kAppVersion='0.6.6'`、`kAppBuildNumber=25`；`test/core/app_info_test.dart` +2 通过。
**无 schema 变更**（仍 v32，与 v0.6.4/v0.6.5 一致，覆盖安装不动数据）。

**Windows**（`scripts/build_windows.ps1`，ASCII junction `E:\Document\furnace-build`）：exit=0；
`data/app.so` 21,496,712 B @04:06:54；`furnace.exe` 版本资源 `0.6.6+25`；
打包前删 `kernel_blob.bin` 110,766,568 B；zip **28 entries / 20,482,750 B / 解压 47,145,419 B**，
顶层 exe + 6 个 dll，`data/app.so` 在包，`kernel_blob` 0 条；SHA-256
`7E5B34D967A34E66E32051FB43624ACC51D8D848CBDC3048B9FD7D7E51BDA45F`。

**Android**（`scripts/build_android.ps1`）：exit=0，Gradle assembleRelease；APK
`dist/Furnace-0.6.6-android.apk` **99,330,430 B**（94.7MB，与 v0.6.5 字节数巧合相同、sha 不同），
SHA-256 `0B8A02379AB4D08C86100009C4032FF1AC971A36AC1984E6E6DF4F6A8243FB8A`；
aapt2 `versionCode 25 / versionName 0.6.6`、minSdk 24 / targetSdk 36 / compileSdk 36；
证书 `57de8b8fed7e4a44cb278ae83b147744dd3918124465634fd135e0bbf32e2db2`（与 v0.5.0–v0.6.5 同）。

**发布件**：`dist/` 三件 = `Furnace-0.6.6-android.apk`、`Furnace-0.6.6-windows-x64.zip`、
`RELEASE-v0.6.6.md`（下载表 / A 学习数据清空 / B 自测统计行 / C 明细逐条删除 / 验证数字 /
已知未做 / 发布说明；已 present 给用户）。旧版 v0.5.8–v0.6.5 件仍在 `dist/`。

**推送**：发布提交用 `E:/dsh-tmp-aot/rest-push.ps1`（GitHub REST git/data API + 代理
127.0.0.1:7890，github.com HTTPS 仍被阻断）推送，提交 sha 与本地一致；
tag `v0.6.6`（annotated）用 `E:/dsh-tmp-aot/rest-tag-066.ps1` 经 `POST /git/tags` + `POST /git/refs` 推送，
API GET 校验目标 commit。

## 2026-10-24 轮次一百六十一：自测统计行 + 自测明细逐条删除（Lead + 3 teammate 并行）

**起点**：轮次一百六十收尾（HEAD `d23209b`，schema v32，v0.6.5 已发布，全量 +5756 全绿，工作树干净）。
选片理由：`docs/QUESTION_BANK_DESIGN.md` §38.3 与 §37.3 的边界里明写着两处缺口——「只能清**全部**作答
记录，不能删单条」与「没有正确率 / 学习统计」。本轮补两片界面：①题库页顶部一行「自测 N 次 · 答对 M 次（P%）」
**全库**统计 ②题目详情页自测明细每行一个删除按钮。**无 schema 变更（仍 v32）、不落新表、不调模型**。

**片 1：仓储 + 领域（Lead + reasoning-core/task-172）**
- `question_attempt_repository.dart`：新增 `deleteAttempt(id)`（:82-85，返删除行数，不存在返回 0）与
  `stats()`（:104-115，`customSelect` 一次读回 `COUNT(*) AS total` + `SUM(CASE WHEN is_correct = 1 …)`，
  `readsFrom: {questionAttempts}`；**空表 SUM 为 NULL**，必须 `read<int?>() ?? 0`，首版 `read<int>`
  在空表抛 type cast 错，已改）。
- 领域 `domain/services/questions/attempt_stats.dart`（40 行纯 Dart）：`QuestionAttemptStats`（const +
  三条 assert）、`empty`、`incorrect`、`isEmpty/isNotEmpty`、`percent = total==0 ? 0 : round(correct*100/total)`。
- 测试：仓储 8 → **10 例**（stats 空表/三行 2 对 1 错→67%；deleteAttempt 删一条/再删 0/不存在 0/其余仍在）；
  领域 **13 例**（percent 取整 2/3→67、1/8→13、199/200→100、1<<40 大数无溢出）。

**片 2：l10n（Lead）**
- 4 个 key（tools.edit 追加 ARB，未用 read→write）：`questionBankAttemptStats(total, correct, percent)`
  （「自测 {total} 次 · 答对 {correct} 次（{percent}%）」/ 英文 "Self-tests: …"）、
  `questionDetailAttemptEntryDeleteTooltip/DeleteDone/DeleteFailed(error)`；`flutter gen-l10n` exit 0。

**片 3：题库页统计行（threadflow-engine/task-173）**
- 新 `application/question_attempt_stats_provider.dart`（20 行）：autoDispose FutureProvider，watch
  `databaseRevision` + `repo.stats()`，写库自动重算。
- `question_bank_page.dart`：:81 顶层 key；:745 `valueOrNull`；:820-833 题数统计行之后插一行
  `bodySmall/onSurfaceVariant`；null（加载中/读失败）或 0 条整行不渲染、不占位。
- 测试 `question_bank_page_test.dart` 17 → **20 例**（3 条 2 对 1 错→「自测 3 次 · 答对 2 次（67%）」、
  0 条不渲染、1 对 1 错→50%；新增 `_addAttempt` helper）。

**片 4：详情页逐条删除（question-intake/task-174）**
- `question_detail_page.dart`：:77 key `questionAttemptEntryDeleteKeyFor(id)`；:740 `_deletingEntryId`
  （请求在飞整组禁用）；:803-833 `_deleteEntry`（`deleteAttempt` → 成功 `ref.invalidate(questionAttemptHistoryProvider)`
  + SnackBar Done；失败 SnackBar Failed 且行不动；各 await 后有 mounted 检查）；:917-928 行尾紧凑
  `Icons.delete_outline` IconButton；删最后一条整块历史行消失（既有 isEmpty 逻辑）。
- 测试 `question_detail_page_test.dart` 59 → **62 例**（按钮 key 对应/删一条统计 (3,2)→(2,1) 其余仍在/
  失败提示且行仍在；替身 `_FailingEntryDeleteAttemptRepository`）。

**门禁（Lead 实跑）**
- 9 个改动/新增 dart 文件 `dart format --set-exit-if-changed` → **0 changed**。
- `dart analyze lib test` → **91 issues / 0 error / 0 warning**，EXIT 0。
- scoped：仓储 +10、领域 +13、题库页 +20、详情页 +62 全绿（Lead 复跑三个 UI/仓储测试文件）。
- 全量 `flutter test --concurrency=1` → **+5777 ~2 All tests passed，10:39，EXIT 0**
  （日志 `E:/dsh-tmp-aot/test-161-full.txt`；上轮基线 +5756，净增 21 = 仓储 2 + 领域 13 + 题库页 3 + 详情页 3）。

**文档**：`docs/QUESTION_BANK_DESIGN.md` 新增 §39（39.1 仓储与领域 / 39.2 详情页逐条删除 / 39.3 题库页
统计行 / 39.4 l10n、测试、门禁与边界）；§37.3 与 §38.3 的四条相关边界（不能删单条、没有正确率统计、
只能清全部、没有学习统计）改为指向 §39。

**仍未做**：统计行是全库口径、不随筛选/学科过滤、不显示趋势；百分比只有整数；逐条删除不可撤销、
无回收站；明细上限 200 条且展开状态不持久；防连点是整组禁用（无每行独立 loading）；真机未手测；
英文未母语化。v0.6.6 未出包（v0.6.5 之后已攒轮次一百六十 + 一百六十一两轮）。

## 2026-10-24 轮次一百六十：设置页「学习数据」清空全部作答记录（Lead + threadflow-engine 并行）

**起点**：轮次一百五十九收尾（HEAD `e26c0e7`，v0.6.5 已发布，schema v32，全量 +5748 全绿，工作树干净）。
选片理由：轮次一百五十八的 §37 边界里明写着「没有『清空全部作答记录』的全局入口」——此前只能
整题清空（详情页历史行 / 题库行菜单），全库没有入口。本轮在设置页补「学习数据」小节：显示自测作答
记录总条数 + 一键清空（清空后题库「错题本」筛选与「错 N 次」徽标一起消失）。**无 schema 变更（仍 v32）、
不调模型、不动排序权重**；仍不做单条删除与正确率统计。

**片 1：仓储（Lead）**
- `app/lib/data/repositories/question_attempt_repository.dart`：新增 `countAll()`（:80，`selectOnly` +
  `id.count()`，空表 0）与 `deleteAll()`（:90，返回删除行数，只清 `question_attempts`）。
- 测试 6 → **8 例**（:192 countAll 空表 0 / 跨题累加 / 单题清空后减一；:218 deleteAll 返回行数、
  再调返回 0、两题题目仍在）。

**片 2：l10n（Lead）**
- `app_zh.arb`/`app_en.arb` 新增 10 个 key：`settingsClearAttemptsTitle/Subtitle(count)/Empty/Action/
  ConfirmTitle/ConfirmBody(count)/Done(count)/Failed(error)/ReadFailed` + `settingsStudyDataTitle`；
  `cd app && flutter gen-l10n` exit 0（5 个文件变更：ARB 各 +60 行、生成文件 +60/+39/+38 行）。
- 教训：**不要用 read→join→write 改 ARB**——`tools.read` 默认只读 2000 行，ARB 有 2844/2937 行，
  会截断文件（本轮发生过一次，已 `git checkout` 恢复后改用 `tools.edit` 锚点插入）。

**片 3：设置页「学习数据」UI（threadflow-engine，task-171）**
- `data_section.dart`：:15 import；:61 在 `_QuestionPackSection` 之后接 `const _StudyDataSection()`；
  :1069-1070 顶层 key；:1077-1207 组件（initState `unawaited(_load())`、副标题三态、0 条/读取失败/
  清空中整行禁用、确认框 → `deleteAll()` → SnackBar → 重读，`hideCurrentSnackBar` 防堆叠）。
- 新增 `test/features/settings/study_data_section_test.dart` **6 例**（有记录/0 条禁用/取消/确认删除/
  读失败/删失败）；`test/features/settings` 93 → **99 例**全绿。

**门禁（Lead 实跑）**
- 7 个改动 dart 文件 `dart format --set-exit-if-changed` → **0 changed**。
- `dart analyze lib test` → **91 issues / 0 error / 0 warning**，EXIT 0。
- scoped：question_attempt_repository_test +8、study_data_section_test +6、question_pack_section_test +34
  = **+48 全绿**。
- 全量 `flutter test --concurrency=1` → **+5756 ~2 All tests passed，10:14，EXIT 0**
  （日志 `E:/dsh-tmp-aot/test-160-full.txt`；上轮基线 +5748，净增 8 = 仓储 2 + 设置页 6）。

**文档**：`docs/QUESTION_BANK_DESIGN.md` 新增 §38（38.1 仓储 / 38.2 设置页 UI / 38.3 l10n、测试、门禁与边界）；
§37.3 的「没有清空全部作答记录的全局入口」一行改为指向 §38。

**仍未做**：不能删单条作答记录；清空不可撤销、无备份（`.tqb` 题库包不含作答记录）；没有正确率/学习统计；
跨页刷新依赖既有 DataChangeBus 但未加跨页 UI 断言；真机未手测；英文未母语化。

## 2026-10-24 轮次一百五十九：v0.6.5 双端发布（错题本筛选 + 作答明细与清除）

**起点**：轮次一百五十八收尾（HEAD `0a7ea8c`，schema v32，全量 +5748 全绿，工作树干净）。
v0.6.4 之后攒了两轮（8 个提交）：轮次一百五十七的「题库错题本筛选 + 行内错 N 次徽标」、
一百五十八的「作答明细展开 + 单题/行内清除记录」。两片都是用户点得到的界面变化，出一版安装包。

**版本**：`app/pubspec.yaml` `version: 0.6.5+24`；`app/lib/core/app_info.dart`
`kAppVersion='0.6.5'`、`kAppBuildNumber=24`；`test/core/app_info_test.dart` +2 通过。
**无 schema 变更**（仍 v32，与 v0.6.4 一致，覆盖安装不动数据）。

**Windows**（`scripts/build_windows.ps1`，ASCII junction `E:\Document\furnace-build`）：exit=0；
`data/app.so` 21,463,944 B @03:13:55；`furnace.exe` 版本资源 `0.6.5+24`；
打包前删 `kernel_blob.bin` 110,766,568 B；zip **28 entries / 20,471,786 B / 解压 47,112,651 B**，
顶层 exe + 6 个 dll，`kernel_blob` 0 条；SHA-256 `F93E72C5FBA71E3B3D939D4AF25C170B43E61DF0D2E0588D4AC47D8979349CE0`。

**Android**（`scripts/build_android.ps1`）：exit=0，Gradle assembleRelease 成功；
APK **99,330,430 B（94.7 MB）** SHA-256 `A887FF9E652181DBF195020A638153C7F51D023C18CC27216D0E29604E3D789A`；
aapt2 `versionCode 24` / `versionName 0.6.5` / minSdk 24 / targetSdk 36 / compileSdk 36；
证书同 v0.5.0–v0.6.4 `57de8b8fed7e4a44cb278ae83b147744dd3918124465634fd135e0bbf32e2db2`。

**dist/**（gitignore、不入库）：`Furnace-0.6.5-android.apk`、`Furnace-0.6.5-windows-x64.zip`、
`RELEASE-v0.6.5.md`（下载表 / A 错题本筛选与徽标 / B 作答明细与清除 / 验证数字 / 已知未做 / 发布说明）；
旧版 v0.5.8–v0.6.4 件仍在 `dist/`。

**推送**：发布提交与 tag `v0.6.5` 走 `E:/dsh-tmp-aot/rest-push.ps1` + `rest-tag`（GitHub REST API，
github.com HTTPS 仍被阻断）；提交 sha 与本地一致。

**未做 / 风险**：双端新界面（筛选片、徽标、明细、清除确认框）未真机手测；无独立错题本页与正确率；
不能删单条记录、无全局清空、不可撤销无备份、明细最多 200 条；微信拖拽收题仍无真机证据；英文未本地化。

## 2026-10-24 轮次一百五十八：错题记录的逐条明细与清除（Lead + question-intake + threadflow-engine 并行）

**起点**：轮次一百五十七收尾（HEAD `82044b2`，v0.6.4 已发布，schema v32，工作树干净）。
选片理由：§36 的错题本筛选把「答错过的题」筛出来了，但作答记录只追加、详情页只显示最近一次——
一道题只要错过一次就永远留在错题本里，哪怕之后连续答对；想看逐条记录也没有入口。本轮补
**展开逐条明细**与**清除这道题的作答记录**（清完「错 N 次」徽标随之消失）。仍无 schema 变更
（v32）、不调模型、不动排序权重。

**片 1：l10n（Lead）**
- `app/lib/l10n/app_zh.arb`/`app_en.arb` 新增 7 个 key：`questionDetailAttemptClearAction`、
  `…ClearConfirmTitle`、`…ClearConfirmBody`、`…ClearDone`、`…ClearFailed(error)`、
  `…DetailToggle(count)`、`…DetailHide`；`cd app && flutter gen-l10n` exit 0（5 个生成/ARB 文件）。

**片 2：详情页（question-intake，task-169）**
- `app/lib/features/questions/presentation/question_detail_page.dart`：`_AttemptHistoryLine` 改
  `ConsumerStatefulWidget`（:718），本地 `_expanded`；明细开关（:829）展开 `history.entries`
  逐条（时间 + 回答正确/错误，新→旧）；清除按钮（:838）→ 确认框 → `deleteForQuestion` → 成功
  `ref.invalidate(questionAttemptHistoryProvider)` + SnackBar，失败提示且历史行保留。
- 测试 54 → **59 例**（+5）。

**片 3：题库行菜单（threadflow-engine，task-170）**
- `app/lib/features/questions/presentation/question_bank_page.dart`：`_clearAttempts`（:291）确认框 →
  `deleteForQuestion` → 成功失效两个 library provider + SnackBar，失败提示不失效；行菜单项
  `_QuestionRowAction.clearAttempts`（:957）**仅 `entry.hasWrongAttempt`** 时出现（:1117-1124）。
- 测试 21 → **26 例**（+5），`question_bank_page_test` +17 无回归。

**门禁（Lead 实跑）**
- 4 个改动 dart 文件 `dart format --set-exit-if-changed` → 0 changed。
- `dart analyze lib test` → **91 issues / 0 error / 0 warning**，EXIT 0。
- scoped：question_detail_page_test +59、question_bank_filter_test +26、question_bank_page_test +17 全绿。
- 全量 `flutter test --concurrency=1` → **+5748 ~2 All tests passed，10:06，EXIT 0**
  （日志 `E:/dsh-tmp-aot/test-158-full.txt`；上轮基线 +5738，净增 10）。

**文档**：`docs/QUESTION_BANK_DESIGN.md` 新增 §37（37.1 详情页 / 37.2 题库菜单 / 37.3 l10n、测试、
门禁与边界）；§36 的「没有删除/重置入口」一行改为指向 §37。

**仍未做**：没有全局「清空全部作答记录」，不能删单条记录（只能整题清空），清除不可撤销无备份，
无正确率统计，明细展开状态不持久且最多 200 条，真机与英文排版未验证。

## 2026-10-24 轮次一百五十七：题库「错题本」筛选 + 行内错题徽标（Lead + 三个 teammate 并行）

**起点**：轮次一百五十六收尾（HEAD `5b2a725`，v0.6.4 已发布，schema v32，工作树干净）。
选片理由：上一轮把自测判分落进 `question_attempts`，但记录只在单题详情页可见——题库里
看不出哪道题错过、也没法只看错题。本轮把「作答记录」变成可用的筛选项，**无 schema 变更
（仍 v32）、不调模型、不改任何排序权重**。不做独立错题本页，也不做正确率统计页。

**片 1：数据与筛选（Lead）**
- `app/lib/features/questions/application/question_library_reader.dart`：`QuestionLibraryEntry`
  新增 `int wrongAttemptCount`（默认 0）与 `bool get hasWrongAttempt`；`readQuestionLibrary`
  在对象标签查询后新查 `db.questionAttempts`（`questionId.isIn(ids) & isCorrect.equals(false)`），
  按题计数填进投影。只数答错；limit 截断仍只查可见 ids（被截掉题的作答不影响可见行）；
  删题事务已连带删作答（轮次一百五十五），不留脏计数。
- `app/lib/features/questions/application/question_library_filter.dart`：`QuestionLibraryFilter`
  新增 `bool onlyWrong`（默认 false），进 `isEmpty/copyWith/==/hashCode/toString`；
  `questionLibraryEntryMatches` 在标签判定后加 `if (filter.onlyWrong && !entry.hasWrongAttempt) return false;`。
  错题本与搜索/标签/学科是**同时满足**（四层条件 AND）。

**片 2：筛选测试（task-166 reasoning-core）**
- `app/test/features/questions/application/question_library_filter_test.dart` 62 → **74 例**（+12，
  group「错题本」）：单独生效、与搜索/标签/学科 AND、`onlyWrong=false` 不影响结果、copyWith/==/hashCode、
  空结果不抛等；`_entry` helper 加 `wrongAttemptCount` 参数默认 0。

**片 3：读表测试（task-167 threadflow-engine）**
- `app/test/features/questions/application/question_library_reader_test.dart` 17 → **23 例**（+6）：
  2 错 + 1 对 → 2；只对 → 0；没做过 → 0；多题混合 `[2,0,1,0]`；limit=2 只按可见 id 查
  （被截掉的题 3 错不影响可见行，放开 limit 后显示 3）；删题后重读不抛且 `db.questionAttempts` 为空。

**片 4：筛选条与徽标 UI（task-168 question-intake）**
- `question_library_filter_bar.dart`：key `questionBankWrongOnlyKey = Key('question-bank-wrong-only')`（:22）；
  参数 `onlyWrong/onToggleWrongOnly`（:60-61）；搜索行下方 Tooltip + 「错题本」`FilterChip`
  （:140-153，avatar `Icons.error_outline` 18、`visualDensity.compact`）。
- `question_bank_page.dart`：key 工厂 `questionBankWrongBadgeKeyFor(id)`（:76）；FilterBar 接线
  （:734-737）；行内 `_WrongPill`（:999-1003 调用、:1144-1170 实现，errorContainer 背景 + error 前景、
  圆角 6）显示「错 N 次」；徽标不改点击行为，整行仍进详情页。
- 测试 `question_bank_filter_test.dart` 17 → **21 例**（+4：徽标只在答错题出现；开「错题本」只剩
  错题且 chip 选中；再点取消恢复；清除筛选把 onlyWrong 一起清），`question_bank_page_test.dart`
  17 例无回归；新增 `_wrongBadge` finder（:469）与 `_seedAttempt` 造数（:532）。

**l10n（Lead 手改 ARB + `flutter gen-l10n`，3 个 key）**：`questionBankWrongOnly`（错题本）、
`questionBankWrongOnlyTooltip`（只看自测答错过的题）、`questionBankWrongCount(count)`（错 {count} 次）。

**门禁**：10 个改动 dart 文件 `dart format --set-exit-if-changed` 0 changed；
`dart analyze lib test` = **91 issues / 0 error / 0 warning**；scoped 四文件全绿
（+74 / +23 / +21 / +17）；全量 `flutter test --concurrency=1` = **+5738 ~2，10:03，EXIT 0**
（上轮基线 +5716，净增 22；日志 `E:/dsh-tmp-aot/test-157-full.txt`）。

**未做 / 风险**：没有独立错题本页与正确率页；「错 N 次」只是计数，明细要点开详情页看最近一次；
作答记录不参与推荐/相似题/threadflow 权重；错题本与标签/学科组合只有 application 层单测覆盖，
没有单独 UI 用例；真机未手测。

## 2026-10-24 轮次一百五十六：v0.6.4 双端发布（自测判分 + 作答记录）

**起点**：轮次一百五十五收尾（HEAD `ad18da1`，schema v32 已落、全量 +5716 全绿、工作树干净）。
v0.6.3 之后攒了两轮（10 个提交）：轮次一百五十四的「详情页自测判分」、一百五十五的
「作答记录落库 + 历史行」。这两片都是用户直接点得到的界面变化，出一版安装包。

**版本**：`app/pubspec.yaml` `version: 0.6.4+23`；`app/lib/core/app_info.dart`
`kAppVersion='0.6.4'`、`kAppBuildNumber=23`；`test/core/app_info_test.dart` +2 通过。
**schema v31 → v32**（本版含新表 `question_attempts`，覆盖安装自动迁移，不回填旧表）。

**Windows**（`scripts/build_windows.ps1`，ASCII junction `E:\Document\furnace-build`）：exit=0；
`data/app.so` 21,447,560 B @02:16:33；`furnace.exe` 版本资源 `0.6.4+23`；
打包前删 `kernel_blob.bin` 110,766,568 B；zip **28 entries / 20,461,245 B / 解压 47,096,267 B**，
顶层 exe + 6 个 dll，`kernel_blob` 0 条；SHA-256 `20CF3F5B30336019FC4C98A5D35354EF519BC0C2E3689A7B16193E97FE2C3005`。

**Android**（`scripts/build_android.ps1`）：exit=0，Gradle assembleRelease 成功；
APK **99,232,126 B（94.6 MB）** SHA-256 `F33C19215954E8BC3B37ABA1F3A60818FCED12E64C740FD4154F383D48706D89`；
aapt2 `versionCode 23` / `versionName 0.6.4` / minSdk 24 / targetSdk 36 / compileSdk 36；
证书同 v0.5.0–v0.6.3 `57de8b8fed7e4a44cb278ae83b147744dd3918124465634fd135e0bbf32e2db2`。

**dist/**（gitignore、不入库）：`Furnace-0.6.4-android.apk`、`Furnace-0.6.4-windows-x64.zip`、
`RELEASE-v0.6.4.md`（下载表 / A 自测判分 / B 作答记录 / 验证数字 / 已知未做 / 发布说明）；
旧版 v0.5.8–v0.6.3 件仍在 `dist/`。

**推送**：发布提交与 tag `v0.6.4` 走 `E:/dsh-tmp-aot/rest-push.ps1` + `rest-tag`（GitHub REST API，
github.com HTTPS 仍被阻断）；提交 sha 与本地一致。

**未做 / 风险**：双端新界面未真机手测；没有错题本/正确率页/「做错过」筛选；写库失败用户无感；
自测中 AI 解题区仍可见；升级到 v32 后回退旧版看不到作答记录（旧版不崩）。

## 2026-10-24 轮次一百五十五：自测作答记录落库（schema v32）+ 详情页历史行（Lead + 两个 teammate 并行）

**起点**：轮次一百五十四收尾（HEAD `0743f91`，工作树干净）。选片理由：上一轮的「自测」判分
只活在 `_QuestionBodyState` 的内存里，关掉详情页就什么都不剩；把「判分成功」的提交落库后，
详情页能显示「自测几次 / 对几次 / 最近一次对错」，也为后面的错题本（题库「做错过」筛选）铺数据。
**新增一张表、schema v31 → v32**，仍然不调模型、不参与调度。

**片 1：domain 纯逻辑（task-163 reasoning-core）**
- 新 `app/lib/domain/services/questions/attempt_history.dart`（81 行、零 import）：
  `QuestionAttemptEntry`（id/questionId/isCorrect/attemptedAt）、`QuestionAttemptHistory.fromEntries`，
  排序 `attemptedAt` 降序 + 同毫秒 `id` 升序，派生 `isEmpty/total/correct/incorrect/latest/latestIsCorrect`。
- `app/test/domain/services/questions/attempt_history_test.dart` **16 例**。

**片 2：数据层（Lead）**
- schema v32：新表 `question_attempts`（`app/lib/data/database/tables.dart:1595`，id/key、question_id 引用
  questions、selected_labels JSON 默认 `'[]'`、is_correct、attempted_at epoch ms；只追加、只存判分成功的提交）；
  `database.dart` `schemaVersion => 32`（:115）、`onUpgrade` 的 `_upgradeV31ToV32()`（:215/:916）、
  `_ensureColumns()` 自愈（:419）；`database.g.dart` 用 build_runner 重生成（57 s、814 outputs）。
- 新仓储 `app/lib/data/repositories/question_attempt_repository.dart`：`record`（:22，归一化后 jsonEncode）、
  `historyFor`（:46，`ORDER BY attempted_at DESC, id ASC LIMIT`，limit<=0 直接空表）、
  `deleteForQuestion`（:73）、`encodeSelectedLabels`（:83，trim→大写→去空→去重→升序）。
- `question_repository.dart:764` 的 `deleteQuestion` 事务里显式删该题作答（本项目无外键级联）。
- provider：`questionAttemptRepositoryProvider`（`repository_providers.dart:102`）。

**片 3：详情页 UI（task-164 question-intake）**
- `app/lib/features/questions/presentation/question_detail_page.dart`（+89）：`questionAttemptHistoryKey`（:63）；
  `_submit` 判分后只在 `isCorrect || isIncorrect` 时 fire-and-forget 写库（`_recordAttempt` :295，
  try/catch + debugPrint，不阻断界面）；`_AttemptHistoryLine`（:704）放在选项后答案前（调用点 :583），
  loading/error/空历史整块 `SizedBox.shrink`，有历史显示「自测 N 次 · 答对 M 次」+「最近一次答对/答错：时间」；
  `_formatAttemptTime` → `yyyy-MM-dd HH:mm`。
- `question_detail_providers.dart:55` 新增 `questionAttemptHistoryProvider`（autoDispose.family +
  `ref.watchDatabaseRevision()`，写库自动重读）。
- l10n 3 key（Lead 手改 ARB + gen-l10n）：`questionDetailAttemptHistory(total,correct)`、
  `questionDetailAttemptLastCorrect(at)`、`questionDetailAttemptLastIncorrect(at)`。
- 测试 49 → **54 例**（+5：无记录不显示 / 种 3 条显示统计 / 答对落库并自动刷新 / 答错落库 /
  写库失败仍正常判分）。

**片 4：迁移与仓储测试（task-165 threadflow-engine）**
- `app/test/data/database/v32_migration_test.dart`（192 行、**4 例**）：真实 v31 文件升 32 后原题还在、
  作答可写可读且重开不丢；版本 32 但缺表靠自愈建表；v30 一路升 32（同遍迁移里 v30→v31 补列 +
  v31→v32 建表都生效）；健康 v32 重开不重建表。
- `app/test/data/repositories/question_attempt_repository_test.dart`（191 行、**6 例**）：record 落库与
  label 归一化（`[' b','a ','A','']` → `["A","B"]`）、新→旧排序、同毫秒 id 升序、limit、`deleteForQuestion`、
  `deleteQuestion` 连带清空该题作答且不碰别的题。

**门禁（本机实测）**
- format：本轮手写 4 个 dart 文件 + 数据层 7 文件均 `0 changed`；
  `dart analyze lib test` = **91 issues / 0 error / 0 warning**。
- scoped：`objective` 无改动；`question_detail_page_test` `+54`；`v32_migration_test` +
  `question_attempt_repository_test` `+10`。
- 全量 `flutter test --concurrency=1` → **+5716 ~2 All tests passed**（10:22，EXIT=0；
  日志 `E:/dsh-tmp-aot/test-155-full.txt`；基线 +5685，净增 31 = 16 + 4 + 6 + 5）。

**提交**：l10n 3 key → domain attempt_history → schema v32 数据层 → 详情页历史行 → v32 迁移/仓储测试 → 本条 docs。

**未做 / 风险**：只有作答记录、没有错题本（无「做错过」筛选、无正确率页、不参与推荐排序）；
同一道题重复自测每次各记一行（设计如此）；写库失败只 debugPrint、用户无感；自测时 AI 解题区
仍可见（§34.3 旧缺口）；真机未手测；历史行只有「最近一次」，没有明细列表页。

## 2026-10-24 轮次一百五十四：题目详情页自测——选择题客观判分（Lead + 两个 teammate 并行）

**起点**：轮次一百五十三收尾（HEAD `2cc1c2c`，v0.6.3 已推送、工作树干净）。选片理由：
`MINDNET_ROADMAP.md` 切片 4 的「仍未做」明列客观题自动判分；而题目详情页一进来就露答案
（推荐练习点进去也一样），先作答、判完再给答案是最直接的一补。**不加表、不迁移**（schema 仍 v31）、
判分不落库、不调模型。

**片 1：域层纯逻辑（task-161 reasoning-core）**
- 新 `app/lib/domain/services/questions/objective_answer.dart`（198 行、零 import）：
  `ObjectiveAttemptStatus`（notObjective/emptySelection/correct/incorrect）、`ObjectiveOption`、
  `ObjectiveAttemptResult`（status + selected/correct/missing/extra + isCorrect/isIncorrect）、
  `isObjectiveQuestionType`、`canScoreObjectiveQuestion`、`scoreObjectiveAnswer`。
- 口径：题型 trim+lower ∈ {single_choice, multi_choice}；没有任何 `isCorrect` 标记 → `notObjective`
  （不是全错）；标签 trim+upper、空标签剔除；判对=集合完全相等，漏选进 missing、多错进 extra；
  输出升序去重且 unmodifiable；不抛异常。
- `app/test/domain/services/questions/objective_answer_test.dart` 344 行 **25 例**。

**片 2：详情页 UI（task-162 question-intake）**
- `app/lib/features/questions/presentation/question_detail_page.dart`（+342/-46）：`_QuestionBody`
  改 Stateful 持 `_selfTest/_selectedLabels/_attempt`；`canScoreObjectiveQuestion` 为真才出现「自测」
  toggle；未提交时藏正确标记、答案段、解析段、答案截图并给提示；选项整行可点（Checkbox + 高亮）；
  提交按钮无选择时禁用；提交后 `_SelfTestResultBanner` 显示对错、答错才给正确答案；答案解析恢复并锁定；
  结束自测清空。
- 修掉一个真 bug：选项内容 `SelectableText` 吃掉点击，整行 `InkWell` 收不到 → 自测分支
  `IgnorePointer`（该文件首跑 `+45 -4` 因此暴露）。
- 测试 43 → **49 例**（+6）。
- l10n 7 key（Lead 手改 ARB + gen-l10n）：`questionDetailSelfTest/Exit/Submit/Correct/Incorrect/CorrectLabels(labels)/HiddenHint`。

**门禁（本机实测）**
- format：4 个手写文件 `0 changed`；`dart analyze lib test` = 91 issues / 0 error / 0 warning。
- scoped `objective_answer_test + question_detail_page_test` → `00:12 +74: All tests passed!`。
- 全量 `flutter test --concurrency=1` → **+5685 ~2 All tests passed**（10:49，EXIT=0；
  日志 `E:/dsh-tmp-aot/test-154-full.txt`；基线 +5654，净增 31 = 25 + 6）。

**提交**：`3031f18` l10n 7 key；`104556b` 域层 objective_answer；`5939fbd` 详情页自测 UI；本条 docs。

**文档**：`docs/QUESTION_BANK_DESIGN.md` 新增 §34（34.1 域层 API/口径/行号；34.2 UI key/行号/修 bug；
34.3 边界）；`docs/MINDNET_ROADMAP.md` 把「客观题自动判分」从未做清单改成已做选择题自测判分、
但点明判分不落库所以还不是 assessment 意义上的答题证据。

**未做 / 风险**：判分不落库 → 无作答历史/正确率/错题本自动收集；只覆盖单选多选（填空/解答无判分）；
选项是复选框、单选不强制互斥（靠判分兜底）；自测只藏答案/解析/答案截图，AI 解题区与知识点仍可见、
可能剧透；自测中选项文字不可复制；真机手动自测未验；英文未母语校对。

## 2026-10-24 轮次一百五十三：v0.6.3 双端发布件（轮次24–25 成果打包）

**起点**：轮次一百五十二收尾（HEAD `9cedd14`，已推送）。v0.6.2 之后攒了 2 轮 / 7 个提交
（备份一键恢复、多图整理卡编辑后保存、备份保留策略与清理入口），打成双端发布件。dist/ 属 gitignore，
不入库；本版只改版本号与文档，功能代码未动。

**版本与门禁**
- `app/pubspec.yaml` `version: 0.6.3+22`；`app/lib/core/app_info.dart` `kAppVersion='0.6.3'`、
  `kAppBuildNumber=22`；`test/core/app_info_test.dart` +2 通过。
- 全量 `flutter test --concurrency=1` 在功能提交 `9cedd14` 上 **+5654 ~2 All tests passed**
  （10:47，EXIT=0）；发布提交只改版本号，未重复跑全量。
- `dart analyze lib test` = 91 issues / 0 error / 0 warning；`dart format` 10 个改动文件 0 changed；
  schema 仍 v31（本版无新迁移）。

**双端构建（本机实测）**
- Windows：`scripts/build_windows.ps1` exit=0（build_runner + flutter build，从 ASCII junction 构建）；
  产物 `data/app.so` 21,398,408 B @01:15:21；`furnace.exe` 版本资源 `0.6.3+22`；打包前删
  `kernel_blob.bin` 110,766,568 B；zip 28 entries / 20,447,619 B / 解压 47,047,115 B，顶层
  exe + 6 个 dll，`data/app.so` 在包，`kernel_blob` 0 条。
- Android：`scripts/build_android.ps1` exit=0，Gradle assembleRelease **137.4s**；APK 99,051,902 B；
  apksigner 证书与 v0.5.0–v0.6.2 同一把 `57de8b8f…f32e2db2`；aapt2：`com.furnace.app`、
  versionCode 22、versionName 0.6.3、minSdk 24、target/compileSdk 36。

**发布件（dist/，gitignore，未入库）**
- `Furnace-0.6.3-android.apk`：99,051,902 B，SHA-256 `C86315EA…8CAACB222`。
- `Furnace-0.6.3-windows-x64.zip`：20,447,619 B，SHA-256 `ACB3120F…242D1B9AB0`。
- `RELEASE-v0.6.3.md`：下载表、A–C 行为变更、验证数字、已知未做。

**推送**：github.com HTTPS 仍被阻断，沿用轮次23 的 REST git data API 脚本推发布提交；
tag `v0.6.3` 用 rest-tag.ps1 经 refs API 推（blob/tree/commit sha 与本地一致）。

**未做 / 风险**：双端新界面均未真机手测（恢复链路、多图卡编辑入口、清理按钮）；备份无自动清理、
无分页、清理不可撤销；恢复中途失败不回滚（靠恢复前自动备份兜底）；多图卡不能重拍某页；
英文未母语校对；同步网络层仍未做。

## 2026-10-24 轮次一百五十二：多图卡片编辑后保存、备份保留策略（Lead + 两个 teammate 并行）

**起点**：轮次一百五十一收尾（HEAD `655f23e`，已推送）。本轮补上一轮明说留下的两个边界：
①多图整理卡片能逐条确认，但题目提案不能「编辑后保存」（单图卡片有）；②导入前备份只能看/删/恢复，
超过 10 份只能一份份点删除。纪律不变：teammate 只写自己的写作用域、不碰 git；l10n、docs 与提交由
Lead 统一做。先实查排除了三个伪缺口（题目配图添加/删除 UI、手动建题表单、题库搜索题号/题名都已存在）。

**一、多图卡片编辑后保存（task-159 question-intake）**
- `app/lib/features/questions/presentation/handwriting_queue_page.dart`：抽出顶层
  `editProposalForIntake(context, ref, sourceRef, proposal)`（:71-99）——`questionDraftForIntake` 拿草稿 →
  `Navigator.push(QuestionIntakePage(initialDraft, initialRelPath: sourceRef, initialProposalId: proposal.id))`；
  单图面板删掉私有 `_editForIntake` 改调它（sourceRef=照片相对路径）。
- 多图卡提案循环对 `kind == question` 传 `onEditForIntake`（sourceRef=`run.sourceRef`，即 `multi:<16hex>`），
  其它产物 null；收题页入库后按 `<sourceRef>#<proposalId>` 写回已确认，与队列 `isApplied` 键一致。
  `_MultiRunCard` 类注释改写为「整组展示不等于只能整组操作」。
- `handwriting_queue_page_test.dart` 28 → **31 例**（3 新例：入口只给题目提案；点编辑草稿预填收题页且
  不写库；编辑后入库题目进库、提案转已确认、编辑按钮禁用而 tag 提案确认仍可用）。

**二、备份保留策略 prune（task-160 threadflow-engine）**
- `app/lib/features/questions/application/question_pack_service.dart`：`kQuestionPackBackupKeepCount = 10`
  （:161-162）；`pruneBackups({int keep = kQuestionPackBackupKeepCount})`（:467-500）：`keep < 0` 先抛
  `ArgumentError`；`listBackups()` 按新→旧，不足/刚好 keep 份返回空表；否则 `sublist(keep)` 逐份
  `deleteBackup`，返回 `List.unmodifiable`。**非原子**：中途失败上抛、已删不回滚，调用方重读列表。
- `app/lib/features/settings/presentation/data_section.dart`：父级注入 `pruneBackups`（:403-404）；
  备份对话框构造新增 required `pruneBackups`（:820/:833）；`_confirmPrune`（:910-957）二次确认 →
  成功 `PruneDone(removed.length)`、失败 `PruneFailed('$error')`，两种情况都 `_load()`；
  仅 `backups.length > keep` 时显示「清理旧备份」按钮（:996-1012），`_busy` 时禁用。
- 测试：`question_pack_service_test.dart` 24 → **28 例**（12 份只删最旧 2 且路径钉住；不足/刚好 no-op；
  目录不存在返回空表；`keep: -1` 抛错不删）；`question_pack_section_test.dart` 31 → **34 例**
  （12 份出现按钮→确认→清理并重读；10 份无按钮；11 份 prune 抛 `StateError('locked')` 后提示且列表仍重读）；
  `support/question_pack_fakes.dart` 补 `pruneBackupsError`/`pruneCalls`/`pruneKeeps`/`prunedPaths`。

**l10n**（Lead 手改 ARB + `flutter gen-l10n`，5 个 key）：`settingsQuestionPackBackupPruneAction`、
`settingsQuestionPackBackupPruneTooltip(keep)`、`settingsQuestionPackBackupPruneConfirm(count, keep)`、
`settingsQuestionPackBackupPruneDone(count)`、`settingsQuestionPackBackupPruneFailed(error)`。

**测试与门禁**
- 三个 scoped 测试：`+93: All tests passed!`（00:33）。
- 全量 `flutter test --concurrency=1`：**+5654 ~2 All tests passed**（10:47，EXIT=0；基线 +5644，
  本轮净增 10，日志 `E:/dsh-tmp-aot/test-153-full.txt`）。
- `dart analyze lib test` = 91 issues / 0 error / 0 warning；`dart format` 10 个改动文件 0 changed。

**文档**：`docs/QUESTION_BANK_DESIGN.md` 新增 §33（33.1 多图卡片编辑后保存 / 33.2 备份保留策略 prune）；
`docs/HANDWRITING_INTAKE_DESIGN.md` §4 边界补「多图卡片也能编辑后保存」并追加轮次一百五十二条目。

**未做 / 风险**：真机多图卡编辑入口未手测；备份清理只有手动、无自动 prune；删除逐份 IO 无批量；
多图卡仍不能逐条重拍某页；v0.6.3 未出包（恢复/prune/多图编辑尚未进发布件）。

## 2026-10-24 轮次一百五十一：备份「一键恢复」（Lead + threadflow-engine）

**起点**：轮次一百五十（v0.6.2 发布，HEAD `73770d2`，已推送）。上一轮 §31.1 明确留的边界——导入前备份
只能看和删，恢复仍要走「导入题库包」再手动找文件。本轮把恢复做成一键：备份列表每行加恢复按钮，走与导入
完全相同的预检 + 报告链路。队友（threadflow-engine）只动服务层/设置页与其测试；l10n、文档、git 提交由
Lead 统一做。

**行为**：设置 → 数据 → 题库包 →「导入前备份」→ 每行新增恢复按钮 → 确认（说明恢复语义）→ 预检
（新增/更新/跳过/缺标签/警告，与导入一致）→ 导入 → 题库视图刷新、备份列表重读、导入报告。恢复 =
按题号更新已有题 + 追加备份里没有的题，**不删**当前题库里备份没有的题；恢复写库前 `importPack` 会再
自动备份一次当前题库，所以备份列表会多一份新备份（预期，不是 bug）。

**服务层**（`app/lib/features/questions/application/question_pack_service.dart`）
- 新增 `readBackupBytes(path)`（`:462`）：只读，不删不改备份；校验与删除共用新抽出的
  `_validatedBackupPath`（`:475`，父目录必须是备份目录、后缀 `.tqb`，否则 `ArgumentError`；
  不存在/读失败抛 `FileSystemException` 交给调用方）。
- `deleteBackup` 改用同一校验，错误文案与行为不变。

**设置页**（`app/lib/features/settings/presentation/data_section.dart`）
- `_restoreFromBackup`（`:413-476`）：确认框（语义说明）→ `readBackupBytes` → `planImport` →
  复用 `_askImportPreview` → `importPack` → `_refreshQuestionViews` + `_reloadBackups` +
  `_showImportReport`；任一步取消都不写库；失败 SnackBar `settingsQuestionPackRestoreFailed`。
- 备份对话框每行 trailing 改为 Row：`Icons.restore`（`:957-972`）+ 原删除按钮；共用一个 `_busy`
  互斥，任一进行中两个按钮都禁用；恢复完成后 `_load()` 重读列表。

**l10n**（Lead 手改 ARB + `flutter gen-l10n`，5 个 key）：`settingsQuestionPackRestoreTooltip`、
`settingsQuestionPackRestoreAction`、`settingsQuestionPackRestoreConfirm(name)`、
`settingsQuestionPackRestoreConfirmBody`、`settingsQuestionPackRestoreFailed(error)`。

**测试与门禁**
- `question_pack_service_test.dart` 21 → **24 例**；`question_pack_section_test.dart` 28 → **31 例**
  （本轮 +6）；`support/question_pack_fakes.dart` 补 `backupBytes`/`readBackupBytesError`/
  `readBackupBytesCalls`/`readBackupBytesPaths`。
- 两个 scoped 测试：`+55: All tests passed!`（00:17）。
- 全量 `flutter test --concurrency=1`：**+5644 ~2 All tests passed**（10:06，EXIT=0；基线 +5638，本轮净增 6，
  日志 `E:/dsh-tmp-aot/test-151-full.txt`）。
- `dart analyze lib test` = 91 issues / 0 error / 0 warning；`dart format` 5 个改动文件 0 changed。

**文档**：`docs/QUESTION_BANK_DESIGN.md` 新增 §32（服务层/设置页/语义/测试/未做）。

**未做 / 风险**：恢复没有进度指示（大题库仍是对话框转圈→完成报告）；恢复中途失败不回滚（已导入部分
保留，但恢复前自动备份的那份可在列表里再次恢复）；备份多时无分页；未真机验证 path_provider 文档目录；
恢复是「先确认语义、再在预检框确认一次」两步确认。

## 2026-10-23 轮次一百五十：v0.6.2 双端发布件（轮次147–149 成果打包）

**起点**：轮次一百四十九收尾（HEAD `0dccdf0`，已推送）。v0.6.1 之后攒了 3 轮 / 16 个提交
（队列批量整理、能力动作学科多选、题库筛选全库、多页照片一次整理 schema v31、导入前自动备份、
多图卡逐条确认、备份管理），打成双端发布件。dist/ 属 gitignore，不入库。

**版本与门禁**
- `app/pubspec.yaml` `version: 0.6.2+21`；`app/lib/core/app_info.dart` `kAppVersion='0.6.2'`、
  `kAppBuildNumber=21`；`test/core/app_info_test.dart` +2 通过。
- 全量 `flutter test --concurrency=1` 在功能提交 `0dccdf0` 上 **+5638 ~2 All tests passed**（11:34，EXIT=0），
  发布提交只改版本号，未重复跑全量；`dart analyze lib test` 保持 91 issues / 0 error / 0 warning。
- schema 仍 v31（轮次148 已迁移，本版无新迁移）。

**双端构建（本机实测）**
- Windows：`scripts/build_windows.ps1` exit=0（build_runner 119s + flutter build，产物 app.so
  21,382,024 B @00:16:59）；打包前删 `kernel_blob.bin` 110,766,568 B；zip 28 entries / 解压 47,030,459 B、
  20,443,012 B，顶层 exe+7 dll，`data/app.so` 在包，kernel_blob 0 条；`furnace.exe` 版本 `0.6.2+21`。
- Android：`scripts/build_android.ps1` exit=0，Gradle assembleRelease **269.5s**；APK 98,986,330 B；
  apksigner 证书与 v0.5.0–v0.6.1 同一把 `57de8b8f…f32e2db2`；aapt2：`com.furnace.app`、versionCode 21、
  versionName 0.6.2、minSdk 24、target/compileSdk 36。

**发布件（dist/，gitignore，未入库）**
- `Furnace-0.6.2-android.apk`：98,986,330 B，SHA-256 `6E23CF30…750B4C9E`。
- `Furnace-0.6.2-windows-x64.zip`：20,443,012 B，SHA-256 `774BFD37…A9C5CE`。
- `RELEASE-v0.6.2.md`：下载表、A–D 行为变更、验证数字、已知未做。

**推送**：github.com HTTPS 仍被阻断，沿用轮次23 的 REST git data API 脚本推发布提交；
tag `v0.6.2` 用 refs API 推（blob/tree/commit sha 与本地一致）。

**未做 / 风险**：双端新界面均未真机手测；多图卡不能逐条编辑、备份无一键恢复/自动清理；
筛选全库无分页；英文未母语校对；同步网络层未做。

## 2026-10-23 轮次一百四十九：多图卡逐条确认、导入前备份管理（Lead + 两个 teammate 并行）

**起点**：轮次一百四十八收尾（HEAD `80ee76e`，7 个提交在本地待推送——轮次148 结束时 github.com
被迫阻断）。本轮补两片上一轮明确留下的边界：①多图整理卡片只能整批确认，不能逐条确认；
②导入前自动备份只落盘、用户看不到也删不掉。纪律不变：teammate 只写自己的写作用域、不碰 git，
l10n、docs 与提交由 Lead 统一做。

**一、多图卡逐条确认（task-156 question-intake）**
- `app/lib/features/questions/presentation/handwriting_queue_page.dart`：`_MultiRunCard` 里每条提案
  从只读改成单独确认——`_ProposalCard.onApply` 由可空改必填 `VoidCallback`，多图卡传
  `() => notifier.applyProposal(sourceRef, proposal.id)`（复用单图已有的逐条确认路径），
  删掉“多图卡只读”的整个分支；已确认 / 确认中 / 预检 blocked 时按钮仍禁用；底部“全部确认”
  继续走 `applyAll(sourceRef)`，一次写全部。
- `handwriting_queue_page_test.dart` 25 → **28 例**：新增 `seededMultiRun` helper 与
  `_RecordingQueueNotifier.applyProposalCalls`，3 例钉住（逐条确认只调 `applyProposal` 且其余提案
  仍待确认、blocked 提案单条与整批都禁用且点击不写库、整批仍一次写全部）。

**二、导入前备份管理（task-157 threadflow-engine）**
- 服务层 `app/lib/features/questions/application/question_pack_service.dart`：`QuestionPackBackup`
  （path/name/sizeBytes/modifiedAt，:138）、`listBackups()`（:405，只收 .tqb、mtime 新→旧、同刻按
  文件名升序、目录不存在返回 `const []`、单个文件 stat 失败只跳过）、`deleteBackup(path)`（:444，
  normalize 后校验“后缀 .tqb + 父目录==备份目录”，目录外抛 `ArgumentError`，目录内不存在视为成功）。
- 设置页 `app/lib/features/settings/presentation/data_section.dart`：题库包分区第三行“导入前备份”
  （:352-355，副标题份数+总大小）；点开对话框（:741-870）列出文件名/大小/日期，删除前确认，
  成功/失败 SnackBar 后刷新；导入成功后自动重读份数（:518）。口径：清单读取失败显示提示而**不显示
  空态**（没读到 ≠ 没有备份）。
- 测试：`question_pack_service_test.dart` 16 → **21 例**、`question_pack_section_test.dart` 23 → **28 例**
  （空态、排序、删除、拒绝目录外路径、读取失败不挡入口等），`support/question_pack_fakes.dart`
  扩展备份替身。

**三、l10n 与 docs（Lead）**
- 新增 7 个 key 并 `flutter gen-l10n`：`settingsQuestionPackBackupsTitle/Empty/Hint`、
  `settingsQuestionPackBackupDeleteTooltip/DeleteConfirm(name)/DeleteDone/DeleteFailed(error)`。
- `docs/HANDWRITING_INTAKE_DESIGN.md`：§1 与 §4 的“多图只剩整批确认”边界改成“可逐条确认、也可整批
  确认/忘掉；逐条编辑仍走单图卡片与收题页”，文末追加“轮次一百四十九”条目。
- `docs/QUESTION_BANK_DESIGN.md` 新增 **§31 导入前备份的管理界面与多图卡逐条确认（轮次一百四十九）**：
  31.1 备份管理的服务层行号、口径、l10n、测试数与未做风险；31.2 多图卡逐条确认指向 HANDWRITING 文档。

**门禁（真实输出）**
- `dart format --set-exit-if-changed`（只格式化本轮 12 个改动 dart 文件）→ `0 changed`。
- `dart analyze lib test` → **91 issues / 0 error / 0 warning**（EXIT 0）。
- scoped：queue 页 `+28`、pack service `+21`、pack section `+28`、settings 目录 `+87`、bulk `+17` 全绿。
- 全量 `flutter test --concurrency=1` → **+5638 ~2 All tests passed**，11:34，EXIT 0
  （上轮基线 +5625，净增 13；日志 `E:/dsh-tmp-aot/test-149-full.txt`）。

**推送**：轮次148 结束时 github.com 的 HTTPS 被中间网络重置（直连与代理都在 TLS 阶段失败），
本轮改用 GitHub REST git data API 经代理推送：blob 原始字节 base64 → tree（base_tree）→ commit
（保留原 author/committer 与提交信息）→ 强推 ref，**7 个 commit sha 与本地逐字节一致**，
远端 main 已到 `80ee76e`；本轮新提交后重跑同一脚本即可（范围=远端 head..HEAD）。

**仍未做 / 风险**：多图卡没有逐条编辑入口（逐条编辑仍走单图卡片与收题页），也不能重拍某页；
备份没有自动清理策略、没有“一键恢复”、对话框未分页/虚拟化、未真机验证 path_provider 默认文档目录；
多图逐条确认与备份管理的真机手感未手测；英文文案未母语化。

## 2026-10-23 轮次一百四十八：多页照片一次整理（schema v31）、题库包导入前自动备份（Lead + 三个 teammate 并行）

**起点**：轮次一百四十七收尾（HEAD `e06c4b7`）。本轮补目标③拍照整理的最后一个明确缺口——
`docs/HANDWRITING_INTAKE_DESIGN.md` 一直写着"一次只整理一张照片，多页连拍/一次多图未做"；另并行两片：
把多图整理做成队列页可操作的能力，以及题库包导入前自动备份（v0.6.1 发布说明里的已知风险）。纪律不变：
Lead 统一提交、l10n 与 schema 生成文件只有 Lead 动、四个写作用域互斥。

**一、schema v31 与存储（Lead）**
- `app/lib/data/database/tables.dart`：`HandwritingIntakeRuns` 新列 `sourcePhotos`（TEXT 可空）；
  NULL/空 = 单图整理（`sourceRef` 就是照片路径），非空 = JSON 路径数组且 `sourceRef` 为 `multi:<id>`。
- `app/lib/data/database/database.dart`：schemaVersion 30→31；`onUpgrade` 新增 `if (from < 31) _upgradeV30ToV31()`；
  `_upgradeV30ToV31` 只补列不回填（表不存在直接 return，交给 `_ensureColumns` 自愈建表）；
  `_ensureColumns` 同时给 `handwriting_intake_runs` 补这一列（防"老文件被盖成 v31 却没列"）；`_tableFor` 登记该表
  （自愈按表名解析，否则抛 unknown table）。`database.g.dart` 用 build_runner 重生成。
- `app/lib/data/repositories/handwriting_proposal_repository.dart`：`HandwritingStoredRun.sourcePhotos/isMulti`；
  `saveRun(sourcePhotos:)` 空列表写 NULL、非空 `jsonEncode`；`runs()/runOf()` 读回时 `_decodeSourcePhotos` 容忍坏 JSON
  （降级成空=单图语义，不让一行坏数据把队列读崩）。
- `app/lib/features/questions/application/handwriting_proposal_service.dart`：`multiSourceRefFor(List<String>)`——
  照片路径先排序再 NUL 连接做 FNV-1a 63 位，返回 `multi:<16hex>`，**同一组照片与顺序无关**，重新整理是整批替换。
  提案行 id 沿用 `'$sourceRef#$proposalId'`，与单图同一套确认状态表。
- 新测试 `app/test/data/database/v31_migration_test.dart`（3 例）：v30 库加列后数据保留、表不存在跳过不崩、
  自愈能补列；`_tableFor` 的 unknown table 行为实测。

**二、多图提示词（reasoning-core）**
- `app/lib/domain/services/intake/handwriting_proposals.dart`（+148）：`HandwritingPhotoInput`（fileName/mime/base64）；
  `handwritingProposalMessagesForPhotos({required photos, existingTagPaths, existingKnowledgePointTitles})`——
  system 与 user 都写明"同一份材料的第 1 页到第 N 页、按顺序拍下"，user 消息按页序挂 N 张 `ChatImagePart`；
  新增页规则 7–9（页间接得上 / 跨页同一题合并成一条并写 rationale / 看不清写明第几页，不用别的页填空）。
- 铁律 1–6、标签与知识点清单、JSON 契约抽成共用 `_handwritingSystemMessage`，单图函数改为委托它——
  两套文案只换开头与额外规则，避免以后漂移。单图函数签名与行为不变。
- 测试：`handwriting_proposals_test.dart` +179 行、新增 5 例（多图两条消息/图片数=N/页序/共用铁律与契约/assert≥2）。

**三、多图服务与队列（Lead）**
- `HandwritingProposalService.proposeForMany(List<String> relPaths)`：读 N 张字节→base64→一次
  `adapter.runTurn`→按 `multi:<id>` 解析。失败一律如实报、不静默少给一张：<2 张直接拒、缺照片
  （"照片不在了：<路径>"，失败键仍是这一组的 `multi:` ref）、格式不认识、无适配器、模型失败、解析失败。
- `HandwritingMultiRun`（sourceRef/photoRelPaths/set/analyzedAt）；`HandwritingQueueState` 新增 `multiRuns`、
  `setFor(sourceRef)`、`multiRunOf`、`mergedPhotoPaths`；`batchCandidates` 排除已参与多图的照片；
  `refresh()` 读回多图 run，**参与照片缺一张就整批作废**（证据不全的整理结果不留），按 analyzedAt 倒序。
- `HandwritingQueueNotifier.analyzeMulti(relPaths)`：同一组照片先移除旧 run 再插到最前（整批替换），
  与单图共用 `analyzing/failures/appliedIds` 状态键；成功后 `saveRun(sourcePhotos:)` 并 `_syncApplied`。
  `previewFor/applyProposal/applyAll/markAppliedLocally/forget/_finishApply` 参数由 `relPath` 统一改名为
  `sourceRef`（单图传照片路径，多图传 `multi:`，行为不变）。
- 测试：`handwriting_proposal_service_test.dart` 新增 5 例、文件共 43 例（多图组覆盖：sourceRef 顺序无关、<2 张不调模型、
  两张一次调用且图片数=2、缺一张如实失败、队列入库/重启恢复/全部确认/忘掉不复活/缺照片整批清）。

**四、队列页多图 UI（question-intake）**
- `app/lib/features/questions/presentation/handwriting_queue_page.dart`（+720/-47）：
  - AppBar 新增「选择照片」进入合并模式（照片清单为空或正在整理/批量整理时禁用），底部换成 `_MergeActionBar`
    （张数规则、运行中、失败原因、「合并整理（N 张）」按钮，<2 张禁用）；照片条在合并模式变成可勾选
    `_MergePhotoChip`：已整理出提案、正在整理、已属于某次多图 run 的照片禁选（Tooltip 说明），已合并的带「已合并」徽标。
  - `_runMerge` 按**勾选顺序**调 `analyzeMulti`（页序=选择顺序）；成功退出合并模式并清选择，失败留在底部栏如实报。
  - `_MultiRunCard`：标题「多页整理（N 张照片）」、N 张缩略图（读字节，读不到给占位）、整组提案（只读，
    没有逐条确认）、确认前预检（复用 `previewFor`，失败降级为无预检）、「全部确认」（`applyAll(sourceRef)`，
    applying/已无剩余/预检 blocked 时禁用）、结果汇总、「忘掉」（`forget(sourceRef)`）。
  - 页面 keys 6 个（merge 模式/运行/照片 chip/结果卡/全部确认/忘掉）供测试与以后快捷键用。
- 测试：`handwriting_queue_page_test.dart` 17→25 例（+384 行，新增 8 条 testWidgets）：入口切换、已合并徽标与禁选、<2 张禁用、
  按勾选顺序调 analyzeMulti、多图卡渲染 N 缩略图+只读提案、全部确认写库、忘掉后卡片消失、失败如实报并可重试。

**五、题库包导入前自动备份（threadflow-engine）**
- `app/lib/features/questions/application/question_pack_service.dart`（+100）：
  `QuestionPackImportReport` 新增 `backupPath/backupError/hasBackup`；`importPack` 在写库前若本机已有题目，
  先把现有题库 `exportBytes` 成 `<documents>/question_pack_backups/题库备份-yyyyMMdd-HHmmss-SSS.tqb`；
  备份失败只记 `backupError`、**不阻断导入**；同毫秒重复导入用 `-2`、`-3` 后缀避免覆盖；
  documents 目录可注入（测试走临时目录，生产默认 path_provider）。
- `app/lib/features/settings/presentation/data_section.dart`：导入结果里显示备份路径（SelectableText）或
  备份失败提示（红色），并更新该段注释（不再说"没有 pre-import backup"）；
  l10n 2 个新 key `settingsQuestionPackBackupCreated(path)` / `settingsQuestionPackBackupFailed`。
- 测试：`question_pack_service_test.dart` 新增 4 例、文件共 16 例（已有题目先备份且字节能解码、空库不备份、备份失败不阻断入库、
  同时间戳连续导入两份备份且第二份含第一份导入的题）。

**门禁（Lead 实跑）**
- `dart analyze lib test`：**91 issues / 0 error / 0 warning**，EXIT=0（与基线同）。
- scoped 合跑：v31 迁移 **+3**、多图提示词 **+82**、多图服务/队列 **+43**、题库包 **+16**、队列页 **+25**，
  全部 All tests passed、EXIT=0。
- 全量 `flutter test --concurrency=1`：**+5625 ~2 All tests passed**，12:58，EXIT=0（基线 +5600，净增 25 例）。
- `dart format --set-exit-if-changed` 17 个改动 dart 文件：0 changed。
- schema 30→31（本轮唯一迁移；现有库升级只加一列、不回填）。

**提交**：按片 7 个提交（schema / 多图提示词 / 多图服务与队列 / l10n / 队列页 UI / 题库包备份 / docs 收尾），
Lead 统一提交（teammate 不写 git）。本地 HEAD `45e7fd2`（`e06c4b7..45e7fd2`）。

**推送**：未成功。23:43–23:44 三次 `git push origin main` 均失败：`schannel: server closed abruptly (missing close_notify)`
→ 加 `http.version=HTTP/1.1` 与重试后变成 `Recv failure: Connection was reset`；同时 `curl https://github.com`
经系统代理（`http://127.0.0.1:7890`，端口可达）与 `--noproxy '*' ` 直连都返回 HTTP 000，判定为当时本机到 GitHub
的网络不可达（非认证/仓库问题）。7 个提交都在本地 main，下轮网络恢复后直接 `git push origin main` 即可。

**本次仍未做**：多图整理真机未手测（模型对多页合并的实际表现、N 张图请求耗时未测）；多图卡片不能逐条确认/编辑、
也不能给某张照片单独重拍；选张数无上限、页面顺序不能拖动重排；备份文件只落盘，设置页没有"一键恢复/清理备份"
（用户要回滚得自己去 documents 目录找文件）；合并模式未做拖拽排序与跨 run 合并。

## 2026-10-23 轮次一百四十七：队列批量整理、能力动作找题学科多选、题库筛选全库（Lead + 三个 teammate 并行）

**起点**：轮次一百四十六收尾（HEAD `7efdb89`，v0.6.1 已推送）。本轮按"三片并行、Lead 统一审查/门禁/提交"推进：
①收题页队列批量整理（目标③一次整理多张照片的过渡能力）②能力动作找题学科多选（`docs/MINDNET_ROADMAP.md`
"仍未做"第⑥项）③题库筛选从"只筛前 500 题"改为"筛选生效时读全库"（v0.6.1 发布说明的已知限制）。
桌面逐屏冒烟（task-150）因本机会话锁屏降级为"启动链路验收"，未计入门禁。

**一、队列批量整理（question-intake）**
- `app/lib/features/questions/application/handwriting_proposal_service.dart`（+191）：
  `HandwritingBatchReport`（succeeded/failed/skipped/stopped/processedAt）、`HandwritingQueueState` 批次字段
  （`batchTotal`/`batchIndex`/`batchRunning`/`batchStopRequested`/`batchReport`）、`analyzeAll()`（防重入、
  候选快照、顺序 `proposeFor`、单张失败不中断、已整理/已失败跳过并计 skipped、结束写汇总）、`stopBatch()`
  （只置停止标志，当前张做完即停，不再发新请求）。
- `app/lib/features/questions/presentation/handwriting_queue_page.dart`（+108）：照片清单上方 `_BatchBar`
  （"整理全部（N 张待整理）"、进度条"正在整理 i/N"、停止/停止中、结束汇总"成功 X 张、失败 Y 张、跳过 Z 张"）。
- l10n 手改 5 个文件（未跑 gen-l10n，保持仓库 LF）：6 个新 key `handwritingQueueBatchAll(count)`、
  `handwritingQueueBatchProgress(current,total)`、`handwritingQueueBatchStop`、`handwritingQueueBatchStopping`、
  `handwritingQueueBatchReport(succeeded,failed,skipped)`、`handwritingQueueBatchStopped`。
- 测试：`handwriting_proposal_service_test.dart` 33→38 例（批次快照/停止/失败混合/幂等/报表），
  `handwriting_queue_page_test.dart` 15→17 例（按钮启用条件/进度/停止/汇总）。
- 未做风险：真机未手测；"停止"不打断已发出的网络请求；批次报表只存于页面状态，重建后不保留；一次只整理
  一张照片仍是 run 身份模型（多页/一次多图仍留待下一轮，见 `docs/HANDWRITING_INTAKE_DESIGN.md`）。

**二、能力动作找题学科多选（reasoning-core）**
- `app/lib/features/questions/application/question_corpus_reader.dart`：`CapabilityQuestionQuery.subjectKey`
  改为 `subjectKeys` 集合（trim/去空/去重/排序的 `normalized()`；`==`/`hashCode` 与顺序无关，可作
  Riverpod family 键）；`readQuestionsForCapabilities` 学科 IN 过滤（空集合=不限），`readQuestionsForAction` 不变。
- `app/lib/features/ai/tools/question_tools.dart`：`find_questions_by_capability` 参数新增
  `subject_keys`（array<string>），`subject_key` 保留为兼容别名；两者都给以 `subject_keys` 为准，结果如实回报
  实际学科。
- `app/lib/features/questions/presentation/capability_action_questions_page.dart`：学科 chip 改 `FilterChip`
  多选（"全部学科"取消选择恢复全量；chip 只列真实出现学科）；切换叠加动作/切 requireAll 清空选择。
- 测试：reader/page/tool 三文件均补用例全绿。未做风险：真实设备 chip 视觉与横向滚动未手测。

**三、题库筛选全库（threadflow-engine）**
- `app/lib/features/questions/application/question_library_provider.dart` 重写：读表限长改为
  `questionLibraryReadLimit({required bool filterActive}) => filterActive ? 0 : 500`；
  `questionLibraryOverviewProvider`（500 档）/ `questionLibraryFullProvider`（0=全库档）/
  `questionLibrarySnapshotProvider`（`autoDispose.family<bool>` 按是否筛选选档）。
- `app/lib/features/questions/presentation/question_bank_page.dart`：换档 loading 保留上一帧（搜索框不卸载、
  焦点不丢）；改名/批量命名/批量标签/批量删除统一失效两档；筛选为空仍走 500 档（横幅提示不变）。
- Lead 补缺口：`question_title_dialog.dart` 改名后原来只失效 500 档，Lead 补失效全库档（从详情页改名返回
  筛选态题库会留旧题名）。
- 测试：新建 `question_library_provider_test.dart` 8 例（两档 limit、换档、缓存/失效）；`question_bank_filter_test.dart`
  15→17 例（第 600 题可筛出、清筛选回 500 档、筛选态改名立刻显示新题名）。
- 未做风险：全库档在大库（万题级）的内存筛选与首帧耗时未测；筛选全库时无分页/虚拟列表。

**四、桌面冒烟（task-150，降级）**
- Release exe 启动/DB 打开/窗口响应/WM_CLOSE 后无残留进程已证实；但 PrintWindow 与 CopyFromScreen 均得到
  全白/静止品牌图，会话处于锁屏（LockApp/LogonUI 在前台）→ 逐屏视觉（主页/设置/题库/详情/队列/组卷/闪存卡）
  **全部未验证**。证据与脚本留在 `E:\dsh-tmp-aot\smoke-147\`；解锁后可重跑（约 5 分钟）。

**门禁（Lead 实跑）**
- `dart analyze lib test`：**91 issues / 0 error / 0 warning**，EXIT=0（与基线同）。
- 全量 `flutter test --concurrency=1`：**+5600 ~2 All tests passed**，11:37，EXIT=0（基线 +5580，净增 20 例）。
- 改动测试文件 scoped 合跑：**+47 All tests passed**，00:16，EXIT=0。
- `dart format --set-exit-if-changed` 18 个 dart 文件：0 changed。
- schema 无变化（仍 v30），本轮无迁移。

**提交**：按片 4 个提交（reasoning / intake / question-bank / docs），Lead 统一提交，teammate 不写 git。

**本次仍未做**：多页照片一次整理（需 run 身份模型改造）、批量整理失败重试、全库筛选分页、真实设备逐屏验收、
v0.6.1 真机手测（桌面冒烟仅启动链路）。

## 2026-10-23 轮次一百四十六：v0.6.1 双端发布件（Lead + 三个 teammate 的轮次140–145 成果打包）

**起点**：轮次一百四十五收尾（HEAD `7f29e4c`，v0.6.0-31）。v0.6.0 之后已攒 31 个提交 / 6 轮
（题库批量操作、搜索筛选、整卡快照包降级显示、抓题包按题号更新），用户手上没有能自己构建的环境，
发布件由 Lead 准备；dist/ 属 gitignore，不入库。

**版本与门禁**
- `app/pubspec.yaml` `version: 0.6.1+20`；`app/lib/core/app_info.dart` `kAppVersion='0.6.1'`、
  `kAppBuildNumber=20`。
- `dart analyze lib test` → **91 issues / 0 error / 0 warning**（基线）；`test/core/app_info_test.dart` +2。
- 全量 `flutter test --concurrency=1` → **+5580 ~2 All tests passed**，11 分 12 秒，EXIT=0
  （日志 `E:/dsh-tmp-aot/test-146-release-full.txt`）。
- schema 不变：`database.dart:111` `int get schemaVersion => 30;`，本版无新迁移（v0.6.0 已到 v30）。

**双端构建（本机实测）**
- Windows：`scripts/build_windows.ps1` exit=0，flutter build 83.0s；产物
  `E:/Document/furnace-build/build/windows/x64/runner/Release`（ASCII junction），28 文件 /
  46,931,803 B（打包前删 `kernel_blob.bin` 105,422,664 B），`data/app.so` 21,283,720 B，
  `furnace.exe` 版本资源 `0.6.1+20`；日志 `E:/dsh-tmp-aot/release-061-win.log`。
- Android：`scripts/build_android.ps1` exit=0，Gradle assembleRelease 215.1s；APK 98,724,042 B；
  apksigner 证书 `CN=Threadflow` SHA-256 `57de8b8f…f32e2db2`（与 v0.5.0–v0.6.0 同一把）；
  aapt2：`com.furnace.app`、versionCode 20、versionName 0.6.1、minSdk 24、target/compileSdk 36；
  日志 `E:/dsh-tmp-aot/release-061-android.log`。
- 构建期 `gen-l10n` 暴露轮次145 手改 ARB 后未重新生成：`app_localizations*.dart` 3 文件刷新
  （`settingsQuestionPackImportConfirm` zh/en 文案与 ARB 对齐），随本版提交。

**发布件（dist/，gitignore，未入库；已推送 GitHub 发布提交与 tag）**
- `Furnace-0.6.1-windows-x64.zip`：20,400,437 B，SHA-256
  `68BD690CD0A39CF16E372B4D31906412DBB5B776BA37E2C71B9CD2EBBB0DC0A6`，35 entries，
  顶层 furnace.exe + 7 个 dll，`data/app.so` 在包，`kernel_blob` 0 条。
- `Furnace-0.6.1-android.apk`：98,724,042 B，SHA-256
  `69C7270DDF409095F84C9EE27E0BB2E877D3D87147699EC987727F3D1489DC29`。
- `RELEASE-v0.6.1.md` 由 Lead 写在 dist/（不入库），列行为变更、验证数字与已知未做。

**未做 / 风险**：双端新功能均未真机手测（批量操作、筛选条、整卡快照版面、设置页更新对话框）；
题库包更新无回滚、无 UI 开关；筛选只作用于已加载的前 500 题；英文新文案未母语校对。

**推送**：`git push origin main` `a6a5869..8bb65a4`（快进 175 个提交，origin/main 原为轮次一百二十一的
`a6a5869`）；另补推此前远端缺失的 5 个 tag：`v0.5.4`、`v0.5.6`、`v0.5.8`、`v0.6.0`、`v0.6.1`（远端原有 15 个 tag）。

## 2026-10-23 轮次一百四十五：题库包按组卷网题号更新已有题目（Lead + 三个 teammate）

**起点**：轮次一百四十四收尾（HEAD `b15e04b`，v0.6.0-26）。此前重复导入同一个 `.tqb` 只会
「按题干指纹全部跳过」：抓题 agent 更新过答案、解析或配图的包，导回去什么都不会变；而真实抓题包
30/30 都带 `zujuan_question_id`。本轮把「题号相同 ⇒ 原地更新」做成默认行为，题名与题号仍归用户。

**五个切片（四个代码提交 + docs，git 由 Lead 统一提交）**
1. 合并计划（reasoning-core，task-144）：`QuestionPackAction.update`、
   `questionPackSourceKey`、`planQuestionPackImport` 的
   `existingQuestionIdByZujuanQuestionId` / `updateExisting` 入参、`updateCount` /
   `updatedIndexes`；判定顺序 update → 指纹跳过 → 包内同题号跳过 → 包内同指纹 → create；
   `updateExisting:false` 与旧版逐字段一致。测试 53 → 94 例。
2. 数据层（threadflow-engine，task-145）：`QuestionRepository.updateFromPack`（补丁语义、
   `options` 非空整体替换、标签只补挂、题名/题号/createdAt 不动）、
   `questionIdsByZujuanQuestionId()`、`QuestionMediaStore.deleteForQuestion(roles:)`
   （只删包里出现过的角色，没配图不删）。题库更新 12 例 + 媒体角色 5 例。
3. 服务层接线 + 预检模型（Lead，task-146）：`planImport`/`importPack` 同查题号映射并传入计划；
   update 分支只传包里非空字段（不用 create 默认值刷掉用户值）、失败计入 failures 不计数、
   成功后按角色删图再落图；`QuestionPackImportPreview.updateCount/hasUpdates`、
   `QuestionPackImportReport.updatedCount`、`summaryZh` 合并成「新增/更新/跳过」一行。
   预检 +3 例、更新流程 9 例。
4. 设置页（question-intake，task-147）：预检提示会更新几道、「没有可导入的新题」改为
   create+update 都为零、确认说明补覆盖范围、结果对话框显示更新数；3 个 l10n key；
   测试 19 → 23 例。
5. docs：`QUESTION_BANK_DESIGN.md` §29（合并计划 / 数据层 / 服务层 / 真实包验收 / 设置页与门禁）
   + 本条 PROGRESS。

**真实抓题包双导（本机临时测试，已删除测试文件）**：`furnace-zujuan-2026-10-22T16-03-02.tqb`
（19,444,730 B，30 题 / 60 媒体，题号 30/30 非空）。第一次 created=30；第二次
planImport update=30/create=0/skip=0，importPack **updated=30**（678 ms）；两轮后仍是 30 行，
题号不变、用户改过的题名保留、题干图与答案图张数不变。

**门禁**：`dart analyze lib test` → 91 issues / 0 error / 0 warning；全量
`flutter test --concurrency=1` → **+5580 ~2，10:38**（上一轮 +5506）；前一次全量暴露的
2 例失败（抓题包往返测试仍按「第二次全部跳过」断言）已按新语义修正。

**未做 / 风险**：Windows 真机上的预检结果对话框未做视觉验收；update 会用包里值覆盖题干/答案/
解析与对应角色配图，目前没有回滚；预检的「自动更新」没有 UI 开关（`updateExisting` 只在服务层）；
l10n 三文件手改未跑 gen-l10n。
## 2026-10-23 轮次一百四十四：其余「只有题干」的列表接上快照感知显示（Lead + 三个 teammate）

**起点**：轮次一百四十三收尾（HEAD `d5c7217`，v0.6.0-21）。上一轮只把整卡快照包在题库总览 / 详情页 /
Word / AI 读题四处做对，组卷候选、相似题、能力动作题、收题页题库列表仍直接显示原始题干（整卡包是
「…… ［图12］ ……」碎片、普通题的 `$…$` 也原样露美元符）。本轮把这四处统一接到同一个纯函数，判定仍复用
渲染计划的 B2，不新增第二套阈值。

**四个切片（四个代码提交 + docs）**
1. `question_stem_display.dart`（reasoning-core，127 行）：`QuestionStemDisplay` +
   `resolveQuestionStemDisplay({stem, imageCount, maxLength})`；内部只调 `summarizeQuestionStemSnapshot`
   （不传尺寸 → 只走 B2）；快照 text=摘录或标签、普通题 text=`questionStemPreview`；不抛。测试 32 例，
   `test/domain/services/questions` +581（基线 549）。
2. 读表 + provider（Lead）：`question_stem_display_reader.dart`（77 行）一次读 questions + attachments
   分组计数（`ownerType='question'`、role NULL 或 stem；答案截图不计），`questionIds` 可过滤；
   `question_stem_display_provider.dart`（25 行，autoDispose + `watchDatabaseRevision`）。测试 +11。
3. 组卷页三个 view（threadflow-engine）：手动名单 / 领域配额 / 学科配额改接 display；
   `questionStemsProvider` 仍只喂手动候选过滤（不缩召回）；徽标仅 `isSnapshot && hasExcerpt` 时摆，
   无摘录时 text 本身已是「整题截图 · N 处公式/图」。测试 manual +3 / domain +2 / subject +2。
4. 相似题 / 能力动作题 / 收题页列表（question-intake）：详情页 `_SimilarQuestionTile` 改 watch display
   provider（加载中 '…'、缺失回落既有文案、摘要+条件徽标）；能力动作页父级取 map 传参，行组件保持
   Stateless；收题页题库列表标题走 display。测试合计 +7，l10n 零新增。
5. docs：`QUESTION_BANK_DESIGN.md` §28、`PROGRESS.md` 本轮条目。

**门禁（真实输出）**
- `dart analyze lib test` → **91 issues / 0 error / 0 warning**（与上一轮同基线，无新增）。
- `test/domain/services/questions` **+581**（基线 549，+32）、reader 单文件 **+11**、
  `test/features/questions/presentation` **+405**（基线 391，两片合计 +14）。
- 全量 `flutter test --concurrency=1` → **+5506 ~2 All tests passed**，11 分 04 秒，EXIT=0
  （日志 `E:/dsh-tmp-aot/test-144-full.txt`；上轮 +5449，本轮 +57 = 32+11+7+7）。
- 两片 presentation 目录门禁由两位成员各自独立跑到 +405，结果一致；format 各片 0 changed。

**未做 / 未验证**
真机（Windows / Android）未手测组卷三 view 的徽标换行与收题页列表；provider 在数据版本变化后的重读
只靠 `watchDatabaseRevision`，本轮未单测；快照摘录保留字面 `$` 定界符（域层既有口径）；无摘录标签为
域层硬编码中文，en 界面仍显中文；provider 未就绪时先显示原文（含 ［图N］）有极短闪烁，未做骨架屏；
组卷三 view 各复制了一份私有 helper，合并成公共 widget 需另开任务。

## 2026-10-23 轮次一百四十三：整卡快照包的三处降级显示（Lead + 三个 teammate）

**起点**：轮次一百四十二收尾（HEAD `9766c3f`，v0.6.0-16）。上一轮把整卡快照包在详情页做对了，
但 Word 导出、AI 读题工具、题库列表三处仍显示原始「［图N］」占位，词不达意。本轮把这三处一起降级：
题干快照摘要纯逻辑 → docx 快照排版 → AI 工具标注 → 题库列表标题与 badge。

**五个切片（四个代码提交 + 一个 docs 提交）**
1. `question_snapshot_summary.dart`（reasoning-core，222 行）：`summarizeQuestionStemSnapshot`
   复用 `planQuestionStemRender` 判定 B1/B2；快照给 `neutralizedStem`/`labelZh`/`textExcerpt`，
   非快照等价 `questionStemPreview`。测试 34 例。
2. `paper_docx.dart`（Lead，+63 行）：`PaperDocxQuestion.stemIsSnapshot`、labels
   `snapshotStemNote`/`snapshotImageLabel`、`PaperDocxBuildResult.snapshotStemCount`；正文后加
   「本题题干是整题截图」小字、图片前加「原题整图」小标题。应用层用真实像素尺寸（`readImageInfo`）
   调摘要，`QuestionDocxRow.toPaperDocxQuestion` 加 `stemOverride/stemIsSnapshot` 透传。
   测试 domain +5 / app +2；真实 30 题包取前 3 题导出，Word COM 实测 5 页 / 1746 字 / 6 图 /
   含两处提示 / 无原始占位 / PDF 530,767 B。
3. `question_tools.dart`（threadflow-engine，+53/−3）：`read_question` 与
   `read_questions_by_serials` 的 modelResult 新增 `stem_is_snapshot`（恒出现）与
   `stem_snapshot_label`；摘要按快照追加说明；工具层只有图数量 → 只命中 B2。测试 +7 例，
   `test/features/ai` +587 零回归。
4. 题库总览（Lead + question-intake）：reader 新增 `isSnapshotStem/snapshotLabel/snapshotExcerpt`，
   `displayTitle` 改为 题名→摘录→标签→`stemPreview`→「（无题干）」；列表标题统一 `displayTitle`、
   题号行加 `questionBankSnapshotBadge`（badge 条件 = 快照且有摘录或题名，避免同屏两个「整题截图」）。
   reader +4 例、presentation +391（基线 388）、l10n 五文件仅 1 个无参 key。
5. docs 提交：`docs/QUESTION_BANK_DESIGN.md` §27、`docs/PROGRESS.md` 本轮条目。

**门禁（真实输出）**
- `dart analyze lib test` → **91 issues / 0 error / 0 warning**（与上一轮同基线，无新增）。
- 切片组合（export + domain/questions + application + ai）→ **+1695 All tests passed**。
- 全量 `flutter test --concurrency=1` → **+5449 ~2 All tests passed**，10 分 56 秒，EXIT=0
  （日志 `E:/dsh-tmp-aot/test-143-full.txt`；上轮 +5394，本轮 +55）。
- 只对改动文件 `dart format`（本轮 0~1 changed，生成物 `app_localizations_en.dart` 例外）。

**未做 / 未验证**
真机（Windows / Android）上「正文 + 整题截图」的版面与 badge 长中文换行未手测；44 处占位极限包
未单独验证；题库列表与 AI 工具都只有 B2 判定（读不到图片尺寸，`attachments` 行缺失时不出 badge /
不提快照）；`questionBankUntitled` 已无业务引用但未删 key；空题干题的列表标题从「题干没读到」
变为 reader 的「（无题干）」。
## 2026-10-23 轮次一百四十二：真实抓题包验收 + 整卡快照包降级（Lead + 两个 teammate）

**起点**：轮次一百四十一收尾（HEAD `7dd3a43`，v0.6.0-11）。外部抓题专属 agent 交付了第一个真实
`.tqb`（30 道物理/数学/化学题、19.4 MB、451 处「［图N］」占位）。本轮先验收再修渲染：整卡快照包
此前会把占位与第一张整题截图内联进题干，详情页看起来是「一堆方括号 + 插在句子中间的整图」。

**五个切片（四个代码提交 + 一个 docs 提交）**
1. `cae59af` 题库包探针（Lead）：新增 `app/tool/question_pack_probe.dart`（纯 Dart 只读）——
   体检题目/学科/来源/占位/题干图/答案图/媒体字节/清单一致性；修 `stemImageTotal` 从未累加的
   误报 bug；新增 `records_snapshot_like` 与整卡快照 alert。真实包：30 题 / 451 处占位 / 30 张
   题干图（全部宽 1640、高 400~3046）/ 28 道快照题 / 30 张答案截图，报告
   `E:/dsh-tmp-aot/probe-real-tqb-1603.json`。
2. `c7adb1e` 题干图片渲染计划（reasoning-core）：新 `question_stem_image_plan.dart`（343 行）——
   `none / inline / snapshot` 三模式；B1 任一已知尺寸宽≥1000 且高≥400 判快照，B2 尺寸未知 +
   1 图 + 占位≥2 兜底；snapshot 正文占位变「…」、全部图进 `trailingImageOrders`。测试 40 例。
3. `60caece` 导入预检识别整卡快照包（threadflow-engine）：`QuestionPackImportPreview` 新增
   `snapshotLikeCount` 与告警「这个包是整卡快照包：N 道题…」；summary 多一行「整卡快照」。
   既有 34 例零回归 + 新 15 例。
4. `d0fcd5d` 详情页接线（question-intake）：`_QuestionStemView` 逐图 `readImageSize` →
   `planQuestionStemRender`；inline 与旧行为逐段一致；snapshot 正文占位变「…」、整题截图挪到
   正文末尾并在第一张前显示「原题整图」；l10n 五文件手改 1 个 key；测试 +5 例。
5. docs 提交：`docs/QUESTION_BANK_DESIGN.md` §26（真实包画像 / 探针 / 渲染计划 / 详情页 /
   预检 / 门禁与未做），§25.4 的「真实 30 题包未导入对照」改为已验收；`docs/PROGRESS.md` 本轮条目。

**验收证据（真实包，临时测试跑完已删）**
- 包：`E:/FirsryOS/THREADRIPPER/zujuan-harvest/harvest/out/furnace-zujuan-2026-10-22T16-03-02.tqb`
  （19,444,730 B，manifest 30 题 / 60 媒体，`app_version=0.5.9+18`，`generated_by=zujuan-harvest/1.0`）。
- 内容：物理/数学/化学各 10；来源档位全 `gaokao`；`source_url`/`zujuan_question_id`/`zujuan_bank_id`
  30 题齐全；答案与解析文字 0 条（30 张 JPEG 截图，16 竖 14 横）；24 题无选项、6 题各 4 个选项且
  `is_correct` 全 false；题干 55…768 字符、`$` 定界符全配对、占位 451 处、每题 1 张题干图。
- 导入 → 再导出：`import_ms=839`、`export_ms=2255`、created 30 / skipped 0 / media 60 /
  warnings 0 / failures 0；题号 `1..30`；题干图 30 张全部宽 1640；答案图 16 竖 / 14 横；
  `export_bytes=18,128,543`；`preview_warnings=1`（快照告警）。
- 关键读数：题干图最小高度**正好 400**，尺寸规则 `>=400` 把 30 道题全部判成 snapshot，
  包括「只有 1 处占位」的两道（占位数量没有漏判）。

**门禁（真实输出）**
- `dart analyze lib test` → **91 issues / 0 error / 0 warning**（与上一轮同基线，无新增）。
- 全量 `flutter test --concurrency=1` → **+5394 ~2 All tests passed**，11 分 18 秒，EXIT=0
  （日志 `E:/dsh-tmp-aot/test-142-full.txt`；上一轮 +5334，本轮 +60 = 40 + 15 + 5）。
- 切片：`test/domain/services/package` +285、`test/features/questions/presentation` +388（基线 383）、
  `question_stem_image_plan_test` +40。只对改动文件 `dart format`。

**未做 / 未验证**
真机（Windows / Android）大图渲染与性能未手测；44 处占位极限包与大小图混合包未单独断言；
单图 + ≥2 占位、字节未回来时 B2 会先判快照、尺寸到达后若小则翻回 inline；**docx 导出**对整卡
快照包仍按旧逻辑导出（占位原文 + 随文截图），未做快照专用排版；题库总览/相似题/AI 读题工具仍
显示原始占位文本；真实 30 题包尚未在 App 真机上手工导入点一遍。

## 2026-10-23 轮次一百四十一：题库页搜索 + 标签筛选 + 可读摘要（Lead + 三个 teammate）

**起点**：轮次一百四十收尾（HEAD `68cf9c3`，v0.6.0-6）。外部抓题 agent 产出的 `.tqb` 题干是
给渲染层准备的（公式包在 `$…$` 里、图片只留「［图N］」占位），题库列表此前直接显示原文；
题库页也只有学科 chips，没有搜索、不能按标签找题。本轮把「看得懂、找得到」补齐：可读摘要
纯逻辑 → 筛选纯逻辑 → 抓题包回归 → 页面接线。

**五个切片（四个代码提交 + 一个 docs 提交）**
1. `76507ae` 题干可读摘要（Lead）：新 `question_stem_preview.dart`（公式去定界符留内容、
   图片占位统一成「［图］」、Markdown 清理、空白折叠、按 runes 截 60 字），题库读表的
   `stemPreview`/`displayTitle` 接上；25 例 + reader 补 1 例。
2. `7baea9d` 题库筛选纯逻辑（reasoning-core）：新 `question_library_filter.dart`（195 行）——
   学科精确、标签多选按子树 ANY、文字先题号解析再子串匹配，三层 AND；62 例。
3. `f090fd6` 抓题包 `.tqb` 端到端回归（threadflow-engine）：合成包（`$…$`、图占位、选项、
   来源三字段、题干图 + 答案截图）导入 → 导出 → 再解码，钉住题干原样、题号重排、来源回写、
   媒体 role/字节保真、重复导入不重复；10 例，生产代码零改动。
4. `9e993af` 题库页搜索 + 标签筛选（question-intake）：页面改 `QuestionLibraryFilter _filter` +
   `_visibleEntries`；新筛选条（搜索框/标签按钮/已选 chips/计数/清除）与可搜索标签多选对话框；
   无命中居中空态；自动命名与全选只作用筛出的题；l10n 7 新 key + 复用 2 个；15 例，
   `test/features/questions/presentation` +383（基线 368）；顺手修了 InputChip 自带 tooltip
   在无回调 chip 上不渲染的真实 bug。
5. docs：`docs/QUESTION_BANK_DESIGN.md` §25（25.1–25.4）+ 本轮 PROGRESS。

**门禁（真实输出）**
- `dart analyze lib test` → **91 issues / 0 error / 0 warning**（与上轮同一基线，无新增）。
- 全量 `flutter test --concurrency=1` → **+5334 ~2 All tests passed**，10 分 34 秒，EXIT=0
  （日志 `E:/dsh-tmp-aot/test-141-full.txt`；上轮基线 +5221，本轮 +113）。
- 切片：摘要/筛选/读表/抓题包四文件 **+110**；presentation **+383**；
  `dart format -o none --set-exit-if-changed` 检查本轮 11 个 Dart 文件 → 0 changed；
  l10n 五文件 zh/en key 对齐、7 个新 key 占位符与 `@meta` 一致。

**未做 / 未验证 / 下一批候选**
- 真机筛选条布局未手测；筛选只作用于已加载的 `limit: 500` 快照，题库超过 500 道时只能筛前
  500 道；多选态 + 筛到 0 道的同屏交互未覆盖。
- `question_intake_providers.dart` 的同名旧类 `QuestionLibraryFilter` 仍未改名（两文件不互相
  import 才没冲突）；旧 key `questionBankNoMatch` 已无 lib 引用但保留未删。
- 抓题包回归是合成包，外部 agent 产出的真实 30 题包尚未在 App 里手工导入对照。
- 下一批候选：真实 `.tqb` 导入验收与题干图片大图/全文；v0.6.1 双端包；quality 标定；
  五个应用领域的剩余接线。

## 2026-10-23 轮次一百四十：题库批量操作——多选、批量打标签、导出选中、批量删除（Lead + 三个 teammate）

**起点**：轮次一百三十九收尾（HEAD `455f36a`，v0.6.0）。这一轮来自用户 m09439 第 5 条反馈
「让鼠标移动尽量减少」：题库页此前没有给题目打标签的 UI 入口，处理一批题只能一道道点进详情
页；标签树也只能逐个点 ⋮ 菜单。本轮把「处理多道题」做成一条路径：多选 → 打标签 / 导出
选中 / 删除。

**五个切片（六个提交）**
1. `3531ca3` 按题目 id 集合导出（Lead）：`readQuestionPackSource` 加 `questionIds`，只保留
   选中题、未知 id 忽略、与筛选条件取交集；媒体字节仍在过滤后读，未选中的题一张图都不解码。
   `exportBytes` 透传该参数。测试 +8 例（含「未选中题不读配图字节」的读取计数断言）。
2. `725200b` TagRepository 批量挂载/摘除（threadflow-engine）：`addTagToObjects` /
   `removeTagFromObjects` 一次事务先查已有行、只插缺失、返回真实新增/删除数；重复调用返回 0
   不抛。测试 +11 例（该文件合计 27 例）。
3. `24392ad` 纯逻辑批量打标签计划（reasoning-core）：`question_bulk_tag_plan.dart` 的
   `planQuestionBulkTag` 只做纯计算（不查库、不判未知题），给出可用/缺失路径、每路径待挂题、
   链接数、受影响题数、已挂跳过数；任何输入不抛、结果不可变。测试 6 组 37 例。
4. `43f6f40` 应用层 `tagQuestions`（Lead）：读标签词表（path 优先回落 name）→ 逐题读已挂标签
   → 计划 → 逐路径写库；单路径失败只进 `failedTagPaths`，不拖垮整批；
   `affectedQuestionCount` 只数真正新增过链接的题。测试 9 例（内存库 + 真实 TagRepository）。
5. `97eb566` 题库页多选 UI（question-intake）：多选态 AppBar（已选 N 项/全选/清空/退出）、
   底部动作条（打标签/导出选中/删除，操作中禁用并显示进度条）、行首 Checkbox、长按进多选；
   全选只作用于当前学科筛选下的题；导出选中 0 题不弹保存框；删除先确认（前 3 个题名预览）、
   逐题清配图再删题、单题失败不中断整批。新对话框 `question_bulk_tag_dialog.dart`（标签路径
   可搜索多选）。l10n 五文件手改 21 个 key。测试 +17 例（该目录 +368，基线 351）。
6. `docs` 本条 + `QUESTION_BANK_DESIGN.md` §24（24.1–24.6）。

**门禁（提交前实测）**
- `dart analyze lib test` → **91 issues / 0 error / 0 warning**（基线 92；本轮修掉一条历史 info）。
- 全量 `flutter test --concurrency=1` → **+5221 ~2 All tests passed**，11 分 08 秒，EXIT=0
  （日志 `E:/dsh-tmp-aot/test-140-full.txt`；上一轮基线 +5139，本轮 +82）。
- 切片组合：`test/features/questions/application`+`test/features/settings` +384、
  `test/features/questions/presentation` +368（基线 351）、`tag_repository_test.dart` +27、
  `test/domain/services/questions` +450（基线 413）。
- l10n：zh/en ARB 各 1405 个 key 对齐，21 个新 key 占位符声明齐全（与 HEAD 相同的 29 条历史
  未声明键不是本轮引入）。

**未做 / 未验证**：真机 Windows 的 `FilePicker.saveFile`/`pickFiles` 未手测；多选态行尾「⋮」
菜单仍可打开（改名/自动命名/复制题号仍作用于单题）；导出 warnings 在批量路径未单独上屏；
批量打标签不提供摘标签入口（数据层 `removeTagFromObjects` 已就绪，界面未接）；一次选中数千题
的性能与确认框滚动未验证。

**发布**：未打新 tag、未出新包（用户没要求）；dist 最新仍是 v0.6.0 三件，未 push GitHub。

## 2026-10-23 轮次一百三十九：题库「读起来像题库」+ 三处交互修复（Lead + 三个 teammate）

**起点**：轮次一百三十八收尾（HEAD `0370a94`，v0.5.9）。这一轮来自用户 m09439 的七条界面反馈，
外加抓题 agent m09454 的公式方案（我方选 B：Furnace 侧渲染 `$…$` LaTeX，抓题侧继续把公式转
LaTeX、非公式图保留原图、整卡 PNG 兜底）。七条反馈里五条在这一轮落地：题目图片与文字排在一起、
去掉不必要的卡片底座、题库总览只留必要信息 + 命名、闪存卡答案框默认聚焦、AI 对话三处（拖拽方向/
新对话滚动/工具结果消失）；另外两条（编辑标签减少鼠标移动、AI 对话界面细节）分别由「标签树多选
批量」和对话三修覆盖。

**A. schema v30 题目自定义题名（task-115，Lead）**：`questions.title` TEXT nullable，NULL = 还没
名字、界面回落题干摘要；自动命名只填空不覆盖用户改名。`database.dart` 版本 29 -> 30 +
`_upgradeV29ToV30` + `_ensureColumns` 自愈，迁移不回填；`QuestionRepository.setQuestionTitle` /
`setQuestionTitles`（一次事务、空白写 NULL、返回命中行数）。`database.g.dart` 由 build_runner
重新生成。迁移与读写口径见 `docs/DATA_MODEL.md` §19；测试 `v30_migration_test` 3 例 +
`question_repository_title_test` 5 例。

**B. 题名生成与题干图片占位切分纯逻辑（task-116，reasoning-core；切分器 Lead）**：
`question_title_suggestion.dart`（538 行）首句 -> 去题号/来源括号 -> 去 `$` 定界符 -> 拼「知识点名 ·
核心短语」/「学科中文名 · 核心短语」，限长 32 runes，冲突加「（2）」，另给
`normalizeQuestionTitle` / `isValidQuestionTitle(80)` / `uniqueQuestionTitle`，55 例；
`question_stem_segments.dart` 把题干里的「［图N］」切成文字段与插图段（全角数字/括号不必配对，
越界与重复 N 原文保留不吞字，imageCount<=0 整段原样），33 例。

**C. 题库总览读表与 provider（task-120，Lead）**：`question_library_reader.dart` 一次读完
questions + attachments（role NULL 视作题干图）+ object_tags/tags，给出
`QuestionLibraryEntry`（serialLabel/displayTitle/stemPreview/coverImage/tagPaths）与
`QuestionLibrarySnapshot`（truncated/untitledCount/subjectKeys）；`questionLibraryOverviewProvider`
watch 库版本自动重读，12 例。

**D. 题库页与详情页重做（task-121 + task-118，question-intake）**：题库页（619 行）空态去卡片、
每行封面 128x96（按 DPR 解码缩略图）+ 题名/摘要 + 题号 + 学科 + 前 3 标签 + 体检徽标 + ⋮（改名/
自动命名/复制题号），AppBar 批量自动命名未命名题，14 例；新增 `question_title_dialog.dart`
（294 行，预填/自动生成/清除/80 上限校验/写库后 invalidate），8 例；详情页去 Card 底座，题干按占位
把大图插进文字流、未引用图接末尾，含 `$…$` 的段落用 `GptMarkdown(useDollarSignsForLatex: true)`
渲染，答案截图放答案段后，题名行可改名，+3 例。

**E. AI 对话三修 + 闪存卡聚焦（task-117，threadflow-engine）**：输入框拖拽 `_dragDistance -= dy`
（原 `+=` 方向反）；新对话/首次加载等消息加载完成再 postFrame 滚到 `maxScrollExtent`（用户主动
上滚查看历史时不抢滚动）；工具结果不再只剩空对话泡——消息列表以前跳过 `roleTool` 行、已执行面板
只来自内存，现在 `listCommittedActions` 与内存记录按 toolCallId 去重合并，`roleTool` 行渲染
`_ToolResultTile`（摘要 + 原文 + 失败/撤销标记 + 撤销入口）。`review_page` 答案框改显式 FocusNode，
换卡后自动聚焦（跳过选择题/已判分/时间门）。测试 ai_chat_page 12 例（+5）、review_page 15 例（+3）。
docs/AI_DESIGN.md §7.1。

**F. 标签树多选批量（task-119，threadflow-engine + Lead 接线）**：多选模式整行勾选、箭头仍只展开、
⋮ 让位；底部条「已选 N 项 / 全选·清空选择 / 批量移动 / 批量删除」；删除确认列前 5 名 + 子树级联
说明，移动目标排除被选自身与全部后代防环，逐个执行并汇总失败；`_batchBusy` 执行期锁入口。
24 例（原 13 + 11）。Lead 接线 13 个 tags l10n key + 通用动词 `commonMove` + `tagsSort`；docs/
TAG_TREE_SORT_DESIGN.md §8（并修正 §5 的「未接 l10n」口径）。

**G. l10n**：五文件共 41 个新 key（题名/题库 26 + tags 13 + `commonMove` + `tagsSort`），手改 ARB 后
跑 `flutter gen-l10n` 同步生成文件；13 个带参 getter 的占位符类型在 ARB 里声明齐全。

**H. 门禁与提交**：`dart analyze lib test` -> 92 issues / 0 error / 0 warning；全量
`flutter test --concurrency=1` -> +5139 ~2 All tests passed，11 分 22 秒，EXIT=0
（日志 `E:/dsh-tmp-aot/test-139-full.txt`；上一轮 +4991 ~2，本轮 +148）。提交按八片拆（schema v30 / 纯逻辑 /
总览读表 / 题库与详情页 UI / AI 对话 / 闪存卡聚焦 / 标签树批量 / docs），git 由 Lead 统一提交，
未 push GitHub；随后出 v0.6.0 双端发布件。

**未做 / 未验证**：大图从占位高度到真实高度的跳变、SVG 不支持、相似题等下方区块仍是 Card、平板
真机滚动手感与 500 条列表性能未测；闪存卡里仍不显示题号（cards 与 questions 无外键）；en 界面排序
模式名仍是中文；组卷网抓题仍由专属 agent 产出 .tqb，Furnace 只负责导入与显示。

## 2026-10-21 轮次一百三十八：标签树排序落盘 + 题库包按标签路径筛选（Lead + 两个 teammate）

**起点**：轮次一百三十七收尾（HEAD `4c61193`）。这一轮补的都是「上一轮只做了一半」的事：标签树的
三档排序上一轮只做了会话内切换、重启就回字典序；题库包导出上一轮能按学科/来源/题号筛，但纯逻辑
早就支持标签路径、界面没暴露。task-110（Lead，schema v29）、task-111（reasoning-core，标签路径选项
纯逻辑）、task-112（question-intake，排序偏好恢复 + 标签路径筛选 UI）、task-113（threadflow-engine，
v0.5.9 发布说明草稿）全部 completed。

**A. 标签树排序偏好落盘（task-110 + task-112，schema v29）**：`local_settings` 增
`tag_tree_sort_mode`（TEXT nullable，NULL=出厂字典序；存域层 code `alphabetical` / `object_count` /
`created_at`，不存中文），`database.dart` 版本 28 -> 29 + `_upgradeV28ToV29` + `_ensureColumns` 自愈；
`SettingsRepository.getTagTreeSortMode` / `updateTagTreeSortMode`（trim、空白写 NULL、null 恢复出厂、
未知 code 不拒绝且读侧降级为字典序）。`tag_tree_page.dart` 的 provider 改为 AsyncNotifier：启动读库
恢复、切换先改内存态再异步写库（写失败只 debugPrint），偏好加载期间按字典序渲染不空白。测试
`v29_migration_test.dart` 4 例 + settings_repository +3 例 + tag_tree +5 例。

**B. 题库包导出按标签路径筛选（task-111 + task-112）**：纯逻辑 `question_pack_tag_options.dart`
（157 行，路径归一/去重保序、题数降序 -> 路径升序、已选永久保留且可超上限、不可变、永不抛，43 例）；
设置页新增 `question_pack_tag_path_picker.dart`（221 行，搜索 + 复选的二级对话框，选项 = 标签树路径
+ `object_tags(object_type='question')` 计数，空库/无匹配分开提示，取消保留旧选择），导出筛选主对话框
多一个「标签路径」按钮（未选「选择标签路径」/已选「标签：已选 N 条」），`questionPackSelectionFromFilter`
增 `tagPaths` 并归一进 `QuestionPackSelection`。l10n 五文件各 +8 key（两个 `count:int`）手改未跑 gen-l10n。
测试 picker 10 例 + 导出筛选 +3 例 + section 8 键断言。

**C. v0.5.9 发布说明草稿（task-113）**：仓库外 `E:/FirsryOS/THREADRIPPER/release-059-draft.md` 103 行，
按 `git log v0.5.8..HEAD` 的提交面整理 A-F 六块 + 验证 5 条（数字留给 Lead 构建后回填）+ 已知未做 10 条；
同时点出「标签树排序」这一条必须真的接线（本轮已接）才能写进发布说明。

**D. 门禁与提交**：`dart analyze lib test` -> 92 issues / 0 error / 0 warning（基线）；组合测试
`test/data/database test/data/repositories/settings_repository_test.dart test/domain/services/package
test/features/tags test/features/settings` -> +459 All tests passed；全量 `flutter test --concurrency=1`
-> +4991 ~2 All tests passed，9 分 57 秒，EXIT=0（日志 `E:/dsh-tmp-aot/test-138-full.txt`；上一轮基线
+4923，本轮 +68）。提交拆 4 个切片（schema v29 / 标签树 UI / 标签路径筛选 / docs），git 由 Lead 统一
提交，未 push GitHub；随后准备 v0.5.9 双端发布件（提交与 tag 见发布记录）。

**未做 / 未验证**：标签树只有三档排序、没有手动拖拽排序；en 界面排序菜单项与标签路径按钮仍是中文；
标签路径筛选是平面多选、没有子树级联（选父不自动选子）；题号多段筛选仍未做；v0.5.9 双端构建与真机
验收见发布说明「已知未做」。
## 2026-10-21 轮次一百三十七：题库包选择性导出 + 导入预检 + 导出告警上屏（Lead + 三个 teammate）

**起点**：轮次一百三十六收尾（HEAD `4e6df91`）。上一轮把题库打成了 `.tqb`，但只能「整库导出」、
导入前只看到清单里的题数/图数，导出时被跳过的坏图也没有任何提示。这一轮补三件事：导出前按
**学科 / 来源档位 / 题号范围**筛选；导入前用**跟实际导入同一套合并计划**做预检（将新增几道、
跳过几道重复、缺几个标签）；导出后把 warnings（配图没进包的原因）上屏。task-106（reasoning-core）、
task-107（threadflow-engine）、task-108（Lead）、task-109（question-intake）全部 completed。

**A. 纯逻辑：筛选与预检（task-106 + task-107）**：`question_pack_selection.dart`（247 行，
`QuestionPackSelection` + 记录/字段两版匹配函数 + `normalizeSerialBound`；空选择=全部、集合空=不约束、
多维 AND、题号含两端、from>to 交换、<=0 视为未给、永不抛）；`question_pack_import_preview.dart`
（236 行，11 字段预检聚合 + `summaryZh` 给日志、UI 不用；warnings 按 manifest 层 -> 计划层顺序合并去重）。
测试 59 + 34 例，目录 +93。期间 Lead 的导出测试抓到 `_SerialRange.of` 单边题号 bug（只给 serialFrom
时区间退化成 `[from, from]`），改用无界哨兵并补 5 例回归。

**B. 数据/应用层（task-108，Lead）**：`question_pack_source.dart`（236 行）的 `readQuestionPackSource`
接受 `selection`，**先筛行再读配图字节**（未选中的题不进包、不读图）；`question_pack_service.dart`
（321 行）`exportBytes({now, selection})` + 新增 `planImport(bytes)`（解码 -> 对账清单 -> 合并计划 ->
预览，不写库不落图），预检与 `importPack` 共用同一套计划函数。新增 19 例（选择性导出 12 + 预检 7）。

**C. 设置页 UI（task-109，question-intake）**：新增 `question_pack_export_filter_dialog.dart`（235 行，
学科/来源六档 chips + 题号起止实时校验，默认全不选=全部）；`data_section.dart`（621 行）导出流程改成
「先弹筛选 -> 导出 -> 0 题按全部/筛选分文案 -> 保存框 -> warnings 非空弹导出提示」，导入流程用
`planImport` 取代 `peek`，预览对话框显示新增/跳过/无新题/缺标签/warnings 后才写库。l10n 五文件各
+16 key（13 无参 + 3 个 count:int）手改未跑 gen-l10n。测试 settings 19 例 + 筛选对话框 12 例，
settings 目录 65 全绿。

**D. 门禁与提交**：`dart analyze lib test` -> 92 issues / 0 error / 0 warning（基线）；
组合测试 `test/data/package test/domain/services/package test/features/settings
test/features/questions/application` -> +600 All tests passed；全量 `flutter test --concurrency=1` ->
+4923 ~2 All tests passed，9 分 54 秒，EXIT=0（日志 `E:/dsh-tmp-aot/test-137-full.txt`）。
提交拆 4 个切片（纯逻辑 / 数据应用层 / UI+l10n / docs），git 由 Lead 统一提交，未 push GitHub。

**未做 / 未验证**：真实 `.tqb` 跨设备/跨版本端到端仍未手测；真机 FilePicker 未手测；筛选对话框本轮
没暴露「按标签路径」条件（纯逻辑已支持）；en 界面学科 chip 仍显示中文词表名；导入不合并重复题的
图片/标签。
## 2026-10-21 轮次一百三十六：题库包（.tqb）导出/导入（Lead + 三个 teammate）

**起点**：轮次一百三十五（HEAD `299d142`）。轮次一百二十二把题目卷导成了 Word（给人看），这一轮补
「导入导出」的另一半：把**题目 + 选项 + 标签路径 + 配图/答案截图 + 组卷网来源链接**打成一个 zip
（.tqb），搬到另一台 Furnace 上。它和工作区备份（.tfpkg）刻意分工——.tfpkg 是整个工作区、replace、
导入前自动备份；.tqb 只含题库子集、**只追加不覆盖**，所以导入前不备份（没有东西会被改写）。
task-102（reasoning-core）、task-103（threadflow-engine）、task-104（Lead）、task-105（question-intake）
全部 completed。

**A. 纯逻辑：格式/记录/导入计划（task-102 + task-103）**：`question_pack_manifest.dart`（232 行，
`format='furnace-question-bank'` / `version=1` / 导出时间 / App 版本 / 题数 / 图数，格式与版本不符给
结构化错误）；`question_pack_record.dart`（732 行，21 字段题目记录，解码时逐字段校验并带 JSON 路径，
5000 条上限，坏数据整包拒绝）；`question_pack_plan.dart`（283 行，先比目标库题干指纹、再比包内前序
重复；缺标签只告警；媒体路径 `media/q<题序>/<图序>.<ext>`）。测试 81 + 53 例，目录 +134 全绿。

**B. 数据/应用层与 zip 容器（task-104，Lead）**：`question_pack_source.dart`（247 行，一次读出题库与
配图，按题号与 sort_order 排好，坏图只告警）；`question_pack_codec.dart`（194 行，manifest + questions +
media 三条目，`peek` 只解 manifest，缺媒体整包失败）；`question_pack_service.dart`（332 行，
`exportBytes` / `peek` / `importPack` + provider——导入只新增，题号按目标库最大号重新分配，标签只挂
目标库已存在的路径，媒体按 role 落盘，报告分开数 created/skipped/media/warnings/failures）。
测试 13 + 12 例，含内存库端到端 round-trip（题 + 选项 + 标签 + 答案截图真实落盘）。

**C. 设置页 UI（task-105，question-intake）**：设置 -> 数据区末尾新增「题库包（.tqb）」小节：导出走
保存对话框（空题库只提示）；导入只收 `.tqb`，先 peek 预览再确认，坏包只提示不写库；结果对话框给
created/skipped/media 与告警条数、前 3 条失败原因；操作期间两行禁用防重入；成功后 invalidate 题库
列表/计数/体检共四个 provider。l10n 13 个 key 五文件手改（未跑 gen-l10n），widget test 12 例。

**门禁（真实输出）**：`dart analyze lib test` -> 92 issues / 0 error / 0 warning（基线）；全量
`flutter test --concurrency=1` -> **+4792 ~2 All tests passed，9 分 43 秒，EXIT=0**
（日志 `E:/dsh-tmp-aot/test-136-full.txt`；轮次一百三十五基线 +4621 ~2，本轮新增 +171）。
切片：`test/domain/services/package` +134、`test/data/package` + service +43、settings 12、
settings + questions/presentation 两目录 +376。

**提交**：`86345a7` 纯逻辑（6 文件 +3059）、`475065b` zip 容器与数据/应用层（5 文件 +1513）、
`b979e3d` 设置页 UI + l10n（8 文件 +1033）、docs 提交。未 push（GitHub 由用户推）。

**未做 / 已知限制**：真机 FilePicker 保存/选择未手测；未用真实跨设备 `.tqb` 样本端到端；5000 题大包
的内存/耗时未测；导出 warnings 未上屏；重复题跳过不提供「合并图片/标签」；包内无知识点（只带标签
路径，知识点要在目标库自己映射）；不做加密/分卷/压缩级别选择。

## 2026-10-21 轮次一百三十五：复习提醒（本地通知）——「flashcard 推送」的推送半边（Lead + 三个 teammate）

**起点**：轮次一百三十四（HEAD `180b83d`）。上一轮把答案截图变成题目的一部分；这一轮补「五应用领域」里
唯一没有网络依赖的缺口——复习提醒：到点若还有到期卡就弹一条本地通知，让「今天该复习」离开 App 也成立。
task-97（Lead）、task-98（reasoning-core）、task-99（threadflow-engine）、task-100（question-intake）
全部 completed；Lead 另做启动与复习结束的重排接线、修掉一处核心通知服务的初始化缺陷、写 docs 与提交。
（同步半边仍缺网络层，这一轮不做；「闪存卡显示题号」需要卡片↔题目的创建路径，当前不存在，暂缓。）

**为什么只排「下一次」而不是每日重复**：`flutter_local_notifications` 的 repeating 在 fire 时读不到库，
到期数却在变；改成四个时机重排——启动首帧、`AppLifecycleState.resumed`、一轮复习做完、设置改动——
每次 cancel 旧 id 再排新的，复习完今晚全部卡片后能自动改到明天。

**A. schema v28：复习提醒的开关与时刻（task-97，Lead）**：`local_settings` 加可空
`review_reminder_enabled` / `review_reminder_minutes`（NULL = 用户没选过，读作关闭 / 出厂 20:00，
迁移不回填）；schemaVersion 27→28，`_upgradeV27ToV28` + `_ensureColumns` 同款自愈，`database.g.dart`
重生成；`SettingsRepository` 四个读写方法（分钟 0..1439 之外抛 ArgumentError，不 clamp；关开关不清时刻）、
`AnkiRepository.nextDueAtAfter`（下一次到点，没有则 null）。新增 11 例（v28 迁移 4 + settings 3 +
anki 4），三个文件一起跑 +20 例（含既有用例）。提交 `14f769d`。

**B. 纯逻辑 + 应用层 + 通知接口（task-98 reasoning-core / task-99 threadflow-engine）**：
`review_reminder_plan.dart`（纯 Dart 不读时钟）四态 dueNow / dueSoon / nothingDue / disabled；
时刻取严格晚于 now 的下一次 HH:mm（20:00:00.000 算明天、19:59:59.999 算今天），永不抛，66 例。
`ReminderNotifier` 接口 + `ReviewReminderService`（读设置 → 数到期 + 找下一次到点 → 规划 →
不排就 cancel、排就 cancel-then-schedule；时间来源统一走注入 clock；插件异常原样外抛），21 例。
**顺带修一处核心缺陷**：`NotificationService` 原构造函数里立即 `_plugin.initialize(...)`，widget test
没有平台实现，我加的启动首帧 refresh 让每个 pump HomeShell 的既有测试都抛 `LateInitializationError`；
改为惰性初始化（构造函数只 `initializeTimeZones()`，`_ensureInitialized()` 在真正排程/取消时才调插件），
行为不变，测试里只余被 catch 的一行 `debugPrint`。提交 `4a124ea`。

**C. 设置页「复习提醒」开关与时刻（task-100，question-intake）**：`review_reminder_section.dart`
（ListTile 入口、对话框开关 + 时间行、写库 → invalidate → refresh、权限被拒弹 SnackBar、取消时间选择不写库）、
`review_reminder_texts.dart`（把 l10n 映射成通知文案）、设置页 DataSection 后接线、12 个 l10n 键五文件手改
（不跑 gen-l10n）。6 例测试；`test/features/settings` 整目录 34 例全绿。提交 `17eb147`。

**D. 启动 / 回到前台 / 复习结束的重排（Lead）**：`home_shell.dart` 首帧后
`addPostFrameCallback` + resumed 时 refresh（`_reminderRefreshing` 防重入，失败只 `debugPrint`）；
`review_page.dart` 在 `_advance()` 走到队列末尾时 refresh 一次（`_reminderRefreshed` 每轮重置）。
接线测试 2 例：HomeShell 启动首帧 refresh 一次 + resumed 再 refresh；一张 essay 卡答完进结束态后 refresh 一次。
提交 `9ad76ca`。

**门禁（真实输出）**：`dart analyze lib test` → 92 issues / 0 error / 0 warning（基线）；
全量 `flutter test --concurrency=1` → **+4621 ~2 All tests passed，10 分 12 秒，EXIT=0**
（日志 `E:/dsh-tmp-aot/test-135-full.txt`）；切片：纯逻辑 +66、应用层 +21、settings 整目录 34、
wiring+narrow+settings 组合 +36、复习页两文件 +15。

**未做 / 已知限制**：真正的每日重复（App 连续多天不打开则不会提醒）；通知点击深链（点开只到首页）；
真机通知与 DST/时区未手测；Windows 点击回调与激活 ID 未接；服务端推送（同步半边）未做。

## 2026-10-21 轮次一百三十四：答案与解析截图随题保存（Lead + 三个 teammate）

**起点**：轮次一百三十三（HEAD `90ae17b`）。用户口径（m05424）：「注意用户可以人工登录组卷网账号
获取答案」——答案/解析要登录才看得到、且是一整张 JPEG；这轮把「用户自己截下来的答案图」变成题目的一部分：
随题保存（schema v27）、详情页可增删、导出 Word 进卷末附录、AI 读题时分开计数。
task-93（Lead）、task-94（reasoning-core）、task-95（question-intake）、task-96（threadflow-engine）全部 completed，
Lead 另做 docx 应用层接线 + Word 真机复测 + docs + git。

**A. schema v27：attachments.role（task-93，Lead）**：`attachments` 加可空 `role`（NULL/空 = 旧行与别处附件，
读作题干配图、**不回填**；stem / answer / solution 预留）。`QuestionMediaStore` 增 `QuestionImageRole` +
`effectiveQuestionImageRole`，`save(role:)` 按角色内排 `sort_order`，`list(role:)` 不传=全部、stem 兼容 NULL 旧行；
`deleteForQuestion` 两类一起清。迁移 `_upgradeV26ToV27` + `_ensureColumns` 同款自愈，`database.g.dart` 重生成。
+20 例（v27 迁移 3 + store 角色 7 + 既有回归）。提交 `7211858`。

**B. 组卷 Word 导出支持答案截图（task-94 reasoning-core + Lead 接线）**：`PaperDocxQuestion.answerImages`、
`answerImageCount`、`imageCount` 收窄为题干配图数、`answerImagesLabel`；附录解析之后渲染小标题 + 等比嵌图，
跳过规则与题干图一致（note 带「第 N 题答案截图」）；答案区三个开关全 false 时不渲染。应用层
`loadQuestionDocxAnswerImages` 只读 role=answer、与 stem 加载器共用参数化实现，`imageLoadNotes` 两类合并。
纯逻辑 +12 例（目录 +169）、应用层 +5 例（+24）。Word COM 真测：样张加 620×860 答案截图后
**2 页 / 553 字 / 3 图 / 29 OMath / PDF 208,132 B**，正文含「答案与解析截图」标签。提交 `9489fc6`。

**C. AI 读题工具分开计数（task-96，threadflow-engine）**：`read_question` / `read_questions_by_serials` 的
`image_count` 只数题干配图，新增 `answer_image_count`（answer/solution 同桶；未知 role 两桶都不计、每行两键恒在）；
摘要分别报「配图 N 张」「答案/解析截图 M 张」。分类 helper 不 import 带 dart:io 的 store。+5 例，两文件 +36。
提交 `a4f3646`。

**D. 详情页「答案与解析截图」区（task-95，question-intake）**：`QuestionImagesSection` 抽
`QuestionImagesSectionKind { stem, answer }`，按 kind 切 provider（新增 `questionAnswerImagesProvider`）、标题、
空态、按钮、删除确认与 key，写入 `save(role:)`；详情页在题干配图区之后插入答案截图区（无图只留一行入口，
不摆空相框）；逐文件跳过规则与题干配图一致；l10n 五文件手改 5 个 `questionAnswerImage*` key。
+7 例（`question_image_edit_test`），`flutter test test/features/questions` → **+600** 全绿。提交 `6ea122a`。

**门禁**：`dart analyze lib test` → **92 issues / 0 error / 0 warning**（基线）；全量
`flutter test --concurrency=1` → **+4515 ~2 All tests passed**，9 分 23 秒（EXIT=0；日志
`E:/dsh-tmp-aot/test-134-full.txt`）。

**docs**：`docs/DATA_MODEL.md` §16（v27 附件角色）、`docs/DOCX_EXPORT_DESIGN.md` §15（答案截图渲染 +
Word 真测）、`docs/QUESTION_BANK_DESIGN.md` §19（本轮四片）并回填 §11.2 / §16.1 / §16.4 的过时「未做」、
`docs/AI_DESIGN.md` 两个工具行、`docs/ZUJUAN_LINKS_DESIGN.md` §8.7。

**未做 / 未验证**：真机 FilePicker 选答案截图与真实磁盘落盘/删除未手测（widget test 用内存假 store）；
真实 v27 库 role 往返只由 store 测试覆盖；大图查看器不显示角色标签；小屏两区连续摆放版面未真机看；
英文文案未母语校对；答案 JPEG 仍不自动下载（不做 WAF/登录态代持），没有截图自动裁边/压缩。

## 2026-10-21 轮次一百三十三：整卷页对照题库、题源链接可改（Lead + 三个 teammate）

**起点**：轮次一百三十二（HEAD `abfab15`）。本轮把「手上有整页试卷，但不知道库里有没有」做成闭环：
粘贴整卷页 → 与题库按组卷网题号对照 → 已收录/缺题清单 → 复制缺题链接；并把「原题链接」从只读变成可改可清。
task-88（Lead）、task-89（reasoning-core）、task-90（threadflow-engine）、task-91/92（question-intake）全部 completed（rev3），
git 由 Lead 统一提交，成员只写各自作用域。

**A. 整卷对照的数据与应用层（task-88，Lead）**：`QuestionRepository.byZujuanQuestionIds(Set<String>)` 只查
`zujuan_question_id` 非空的题（updatedAt 降序 / id 升序，结果按 zujuan id 分组）；应用层
`features/questions/application/zujuan_paper_progress.dart` 的 `loadZujuanPaperProgress` 按试卷页题号顺序逐 id 取最新一行，
命中给 `serialLabel`（全仓一致口径，未编号显示 TR-未编号）与 `stemPreview`（压空白取前 60 rune + …），
缺题给 `missingQuestionIds` 与逐 id 重算的 `missingLinks`（缺 bankId 跳过）；extract 为空时不查库。+20 例（仓储 8 / 应用 12）。提交 `02313bf`。

**B. 题源链接输入解析（task-89，reasoning-core）**：`domain/services/zujuan/zujuan_source_input.dart` 的
`parseZujuanSourceInput(raw)` 认三类输入——完整 http(s) 组卷网题目页 URL（先 `questionSourceFor` 归一，
**只有 host 命中组卷网才抽两个 id**，别站只收 sourceUrl）、裸路径 `/10q<id>.html`（用 `zujuanQuestionDetailUrl` 重建链接）、
别的站 URL；纯数字 / 相对路径 / `javascript:` 等一律 null，永不抛。+40 例，zujuan 目录 **+252** 全绿。提交 `cd2d1e4`。

**C. AI 只读工具 `read_zujuan_paper`（task-90，threadflow-engine）**：第 27 个工具，参数 `text` + `max_count`
（默认 50、硬上限 200）；粘贴整卷页文本 → `parseZujuanPaperText` → `loadZujuanPaperProgress`，
返回 `rule='library_only'`、计数、warnings、matched（4 键）与 missing（逐 id 重算链接），摘要写明「只读题库，
不会去组卷网抓页面」。+17 例，`read_questions_by_serials` 无回归。提交 `bec8f88`。

**D. 收题页「整卷对照」对话框（task-91，question-intake）**：第三个入口 → 粘贴 → 「共 N 道 · 已收录 M 道 · 缺 K 道」+
已收录行 + 缺题行（有链接/无链接）+ 一键复制缺题链接；空白或认不出只显示空态且**不查库**；无 bankId 时说明原因并禁用复制。
l10n 18 个 `zujuanPaper*` key；+11 + 1 例，presentation 目录 **+310** 全绿。提交 `73e92a7`。

**E. 详情页可编辑原题链接（task-92，question-intake）**：来源行「复制」旁加「改原题链接」；没有来源行的题目在同一位置
显示低权重「添加原题链接」；对话框实时用 `parseZujuanSourceInput` 预览三个字段，保存走 `updateSourceLinks`
（null=该列不动，别站 URL 不冲掉旧 id），「清空链接」二次确认后三列清空；成功后 invalidate 详情 provider。
l10n 17 key；+10 + 3 例，presentation 目录 **+323** 全绿。提交 `86ab39d`。

**门禁**：`dart analyze lib test` → **92 issues / 0 error / 0 warning**（基线）；全量 `flutter test --concurrency=1` →
**+4476 ~2 All tests passed**，9 分 12 秒（EXIT=0；日志 `E:/dsh-tmp-aot/test-133-full.txt`）。

**未做**：整卷对照的「批量补录缺失题」（仍逐题走粘贴题面 / 定点找题）；真实组卷网整页文本与浏览器「保存页面」HTML 端到端手测；
三按钮同排的窄屏溢出未验证；真机软键盘遮挡编辑对话框未手测；英文文案未母语校对。
## 2026-10-21 轮次一百三十二：题库搜索、整卷页粘贴抽取、题源链接写入（Lead + 三个 teammate）

**起点**：轮次一百三十一（HEAD `6677a93`）。本轮继续把「少让用户手敲」往前推：搜索框一次贴多号/区间/
关键词、组卷网试卷页整段粘进来就能拿到整套题号清单、题源链接能改能清。task-84（reasoning-core）、
task-85（threadflow-engine）、task-86（question-intake）、task-87（Lead）全部 completed（rev3）；
git 由 Lead 统一提交，成员只写各自作用域。

**A. 搜索输入解析（task-84，reasoning-core）**：`domain/services/questions/question_search_plan.dart` 的
`parseQuestionSearchPlan(raw, {maxSerialCount = 200})` 返回 `QuestionSearchPlan{raw, stemContains,
serialNos, rejectedSegments, truncated}`：单号复用 `parseQuestionNumberQuery`（TR-00042 / tr-42 / #42 /
全角数字）、区间连接符 `..`→`~`→`—`→`-`（`-` 只当两端纯数字，支持 `1 - 5` 三段写法）、重叠/相邻区间
合并去重升序、超大区间按上限截断不真展开；认不出的文字按顺序拼进 `stemContains`，坏区间（`1..x` /
`1..` / `1..5..9`）整段进 `rejectedSegments`；纯号时 `stemContains=null`，没有题号时回退「整段输入当
题干」（旧搜索框行为）；永不抛。+81 例；`test/domain/services/questions` **+325** 全绿。提交 `235a2ee`。

**B. 组卷网整卷页粘贴抽取（task-85，threadflow-engine）**：`domain/services/zujuan/zujuan_paper_extract.dart`
的 `parseZujuanPaperText(raw)` 从粘贴的试卷页 URL/HTML 抽 `{paperId, bankId, title, questionIds,
questionLinks, warnings, truncated}`：只认 `/<bank>p<paper>.html` 与 `q<digits>.html`（前导边界防
`/abcq123` 误认）、顺序去重不重排、超 200 截断；`questionLinks` 复用 `zujuanQuestionDetailUrl`（缺 bank
跳过并汇总 warning）；`title` 只认 `<title>`→`<h1>`→null（不猜）；不联网、不解析答案、永不抛。+44 例；
`test/domain/services/zujuan` **+212** 全绿。提交 `48eb157`。

**C. 题源链接写入/清除数据层（task-87，Lead）**：`QuestionRepository.updateSourceLinks(id, {sourceUrl,
zujuanQuestionId, zujuanBankId, now})` 返回是否真改到行：`null` = 这一列不动、空串/全空白 = 清空（写回
null）、外层空白归一；不碰来源分级/题干/答案/加工列；不存在的 id 返回 false 不抛。与 `updateSource`
分开的原因写进 docs：来源分级是封闭词表、写错会弄歪排序，链接只是用户粘贴的外部字符串。+8 例。提交
`9cda7d9`。

**D. 收题页题库搜索接多题号（task-86，question-intake）**：`QuestionLibraryFilter.serialNo:int?` →
`serialNos:List<int>` + 新增 `serialFallbackStem`；`parseQuestionLibrarySearch` 纯转发 domain 解析器；
`questionLibraryProvider` 混合输入 = 题号查 + 题干查两次并集（题号命中在前、按 id 去重、各自保仓储序），
纯号 0 命中保留旧「回落题干」行为，清空搜索时题号与回落一起清；hint 改成「搜题干或题号（可多个：
TR-00001, 2-5）」（l10n 五文件手改，未跑 gen-l10n）。测试：providers 重写 15 例、页面 +5 例；
`test/features/questions/presentation` **+298** 全绿（基线 291）。提交 `25bdebb`。

**E. docs**：`QUESTION_BANK_DESIGN.md` 追加 §17（17.1 搜索输入 / 17.2 题源链接写入 / 17.3 整卷页粘贴
抽取 / 17.4 门禁），并回填 §11.2、§13、§16.1、§16.4 的在途口径；PROGRESS 补记轮次一百三十、一百三十一
（含门禁数字回填）与本条。docs 提交是轮次一百三十二的最后一条提交。

**门禁**：`dart analyze lib test` → **92 issues / 0 error / 0 warning**（基线）；全量
`flutter test --concurrency=1` → **+4374 ~2 All tests passed**，8 分 52 秒（EXIT=0；日志
`E:/dsh-tmp-aot/test-132-full.txt`）；四目录组合（domain/questions + domain/zujuan + data/repositories +
presentation）→ **+1005** 全绿（日志 `E:/dsh-tmp-aot/test-132-slices.txt`）。

**事故记录**：本轮第一次全量跑（日志 `E:/dsh-tmp-aot/test-131-full.txt`）在 `+3324 loading
review_page_test.dart` 处 CPU 冻结 5 分钟无进展，手动 kill；原因未核实，怀疑与 teammate 同时跑
`flutter test` 争用构建/工具锁。之后改为「同一工作区同一时刻只跑一个 flutter test」，重跑通过。

**未做 / 未验证**：整卷页粘贴的界面入口（预览 / 批量入库）与真实浏览器「保存页面」HTML 未端到端验证；
题源链接的「改原题链接」UI；搜索框多号结果的顺序只由代码顺序保证（测试断言命中与去重、不逐条断言）；
真机输入法 / 清空按钮未手测；英文文案未母语校对；缩略图磁盘缓存。

## 2026-10-21 轮次一百三十一：详情页来源入口与缩略图接线、整卷题号批量读题工具（Lead + question-intake）

**起点**：轮次一百三十（HEAD `26f92e1`）。本轮把上一轮铺路的纯逻辑接进界面，并给"按整卷题号
列题"补上 AI 侧入口。task-82（question-intake）与 task-83（Lead）completed（rev3）；git 由 Lead
统一提交，成员只写各自作用域。

**A. 题目详情页来源入口 + 缩略图解码尺寸接线（task-82，question-intake）**：详情页 meta 行与题干
之间加「题目来源」行（`question_detail_page.dart:768 _QuestionSourceLine`，:188 用
`questionSourceFor` 计算）：有链接显示「组卷网原题」或其它 host、按钮「复制原题链接」写规范化后的
`source.url` + SnackBar；只有 zujuan 两个 id 时由领域层重建 `https://zujuan.xkw.com/<bank>q<id>.html`；
无链接/非法/相对路径整块零高度，没有引入 url_launcher。缩略图（`question_media_view.dart:251`）改用
`thumbnailDecodeSpec(显示边长 × DPR)` 传 `cacheWidth/cacheHeight`（空 spec 传 null，解码阶段就缩图），
大图查看器保持不限制解码。l10n 五文件手改 3 key（`questionSourceCopyLink/CopyDone/Zujuan`，未跑
gen-l10n）。测试：详情页 +4 例（无链接不出现 / 普通站 host / 仅 id 重建 / 组卷网不显示 host）、
配图 +2 例（缩略图是 ResizeImage 且宽高等于 spec / 大图不是 ResizeImage）；`presentation` 目录
**+291** 全绿（基线 285）。提交 `6677a93`。

**B. AI 工具 read_questions_by_serials（task-83，Lead）**：`question_tools.dart` 新增只读工具，
参数 `serials`（复用 `parseQuestionSerialBatch` 的区间/分隔符/去重升序/截断）+ `max_count`（默认
50、上限 200）。一次查库返回每个号在不在库与摘要（题号/学科/来源/题干摘要/有无答案与解析/选项数/
配图数），缺号按补零写进 `missing`、坏段原样进 `rejected_segments`；整段没认出可题号返回可读的
`ToolArgError`。撞号按 `QuestionRepository.search` 价值序取第一条；只读声明（`readOnly` +
`reversibleFor`）与 `read_question` 同口径，注册后工具共 **26 个**。16 例测试（只读快照、清单口径、
摘要字段、缺号/坏段/截断、边界、注册与 schema）；`flutter test test/features/ai` **+553** 全绿。
docs：`AI_DESIGN.md` 工具清单 25→26；`QUESTION_BANK_DESIGN.md` 新增 §14.2（原 §14.2 组卷页手工
指定改为 §14.3）。提交 `d4102dc`。

**门禁**：`dart analyze lib test` → **92 issues / 0 error / 0 warning**（基线）。全量
`flutter test --concurrency=1` → **+4374 ~2 All tests passed**，8 分 52 秒（EXIT=0；第一次并发跑卡住，单独重跑见轮次一百三十二的事故记录；日志 `E:/dsh-tmp-aot/test-132-full.txt`）。

**docs 回填**：`QUESTION_BANK_DESIGN.md` §11.2（缩略图 UI）、§13（题源链接 UI）、§16.1/§16.4
（task-82 在途 → 已交付）四处过时口径改为已做；PROGRESS 补记轮次一百三十、一百三十一。

**未做 / 未验证**：题库列表搜索接多题号清单（现在仍按单号或题干 LIKE）；题源链接的写入/纠错 UI；
缩略图磁盘缓存；真机剪贴板/SnackBar 与系统文件选择器未手测；英文文案未母语校对。

## 2026-10-21 轮次一百三十：题源链接、缩略图解码尺寸、整卷题号清单三块纯逻辑（Lead + 两个 teammate）

**起点**：轮次一百二十九（HEAD `1fe2e7e`，v0.5.8 之后 6 个提交）。本轮无新用户指令，按 goal 把
三处长期缺的界面入口先铺成纯逻辑——「点回组卷网核对原题」「列表缩略图别解码整张照片」「按整卷
题号列题」。task-79（Lead）、task-80（threadflow-engine）、task-81（reasoning-core）completed（rev3）。

**A. 缩略图解码尺寸（task-79，Lead）**：`domain/services/media/thumbnail_spec.dart` 新增
`ThumbnailDecodeSpec thumbnailDecodeSpec({logicalWidth, logicalHeight, devicePixelRatio = 1.0,
maxDecodeSide = 1024})`——先乘 DPR 再向上取整，长边超上限按比例压且两边 ≥1（`capped=true`），
DPR 非有限/≤0 归一到 1.0、>16 钳到 16（防 int 溢出），逻辑尺寸任一边 ≤0 返回 0×0 空 spec
（`isEmpty`，调用方必须判空后再传 cache）。纯 Dart 不 import Flutter，+27 例。提交 `e432cb1`。

**B. 题源链接（task-80，threadflow-engine）**：`domain/services/questions/question_source.dart` 的
`questionSourceFor({sourceUrl, zujuanQuestionId, zujuanBankId})` 返回
`QuestionSourceRef{url, host, fromStoredUrl, isZujuan}`：只认绝对 http(s)（javascript:/data:/file:/
mailto:/相对路径一律 null），scheme/host 小写、去 fragment 与默认端口、path/query 逐字节保留；
库里有链接优先，否则只有两个 id 时走 `zujuanQuestionDetailUrl` 重建（`fromStoredUrl=false`），
组卷网判定 `zujuan.xkw.com` 与 `*.zujuan.xkw.com`。+46 例（同目录 +244 无回归）。提交 `283ca67`。

**C. 整卷题号清单（task-81，reasoning-core）**：`domain/services/questions/question_serial_batch.dart` 的
`parseQuestionSerialBatch(raw, {maxCount = 200})` 返回 `QuestionSerialBatch{serials, rejectedSegments,
truncated, isEmpty, count}`：先按逗号/顿号/分号（半全角）切块、块内按空白切 token，单 token 复用
`parseQuestionNumberQuery`；区间连接符按 `..`→`~`→`—`→`-` 顺序尝试（`-` 最后，避免把 `TR-42`
拆坏），两端都合法才展开、升降序统一按升序、重叠区间合并、去重升序；超 `maxCount` 保留最小若干个
并标 `truncated`，一端非法整段进 `rejectedSegments`，永不抛。+51 例。提交 `ba48356`。

**docs**：`QUESTION_BANK_DESIGN.md` 追加 §16（16.1 题源链接 / 16.2 缩略图解码尺寸 / 16.3 整卷题号
清单 / 16.4 门禁与在途），并补 §11.2、§13、§14.1 的未做口径。提交 `26f92e1`。

**门禁**：`flutter test test/domain/services/media test/domain/services/questions --concurrency=1` →
**+271 All tests passed**；`dart analyze lib test` → **92 issues / 0 error / 0 warning**（基线）。

**未做（当时）**：三块的 UI/DB 接线在 task-82（轮次一百三十一已交付）；题源链接写入/纠错 UI、
缩略图磁盘缓存、整卷题号批量读题 AI 工具留到后续（后两项中读题工具已在轮次一百三十一补上）。

## 2026-10-21 轮次一百二十九：题目配图增删、粘贴解析加固、内联选项、详细理由接线（Lead + 三个 teammate）

**起点**：轮次一百二十八（HEAD `2d63b16`，tag `v0.5.8`，双端发布件已备在 `dist/`、未推 GitHub）。
本轮无新的用户功能指令，按 goal 继续把上一轮的"未接 / 未做"补上：详细理由接页面、拍照整理的题目
能从题干里抽选项、组卷网粘贴解析扛真实页面形态、题目配图能在详情页增删。task-75..task-78 全部
completed（rev3）；成员只写各自作用域，git 由 Lead 统一提交。

**A. 详细理由接线（task-78，Lead）**：领域层上一轮已备好 `compose(detailedNotes: true)` /
`rank(detailedReasons: true)`，但两个开关没打开。本轮 `paperPlanProvider` →
`buildPaperPlan(detailedNotes: true)`、`similarQuestionsProvider` →
`rank(detailedReasons: true)`；`compose_paper` 等 AI 工具**有意保持短文案**（工具输出给模型看，
短文案省 token）。页面因此能回答"为什么排这道"：本卷第 N 题、需求 / 质量分 / 综合得分、排序权重，
以及"为知识点「X」…下一步"；缺口解释句 `PaperGapNote` 仍只在领域层（没有单独界面块）。
测试：`similar_question_provider_test` + `paper_plan_provider_test` **+33**（含详细文案断言），
组卷页 `question_paper_page_test` 27 例改按详细文案断言后全绿。docs：`REASONING_LAYER_DESIGN.md`
§32、`SIMILAR_QUESTIONS_DESIGN.md` §8。

**B. 拍照整理的题目自动抽内联选项（task-77，reasoning-core）**：`handwriting_proposals.dart`
新增纯函数 `extractInlineOptions` / `InlineOptionExtraction`，接进 `_proposalFrom`：模型没给
`options` 时从题干里确定性抽「A．… B．…」——只认行首（可缩进）或同一行已接受标记后的 A–H，
字母半角/全角、分隔符 `.` `．` `、` `)` `）` `:` `：`，必须 ≥2 项、从 A 起连续不重复，
否则失败返回中文原因且**零改动**；公式区间（`$...$` / `$$...$$` / `\(...\)` / `\[...\]`）
与 18 类答案/解析行整行掩掉，`A=1` / `B点` / `A、B两点` 不误伤。成功时 `fields.stem` 换成
剥离题面、原题面进 `stem_original`。存量提案读回也会补抽（确定性、幂等、往返逐字节相等；旧三类
输出不变）。42 例新测试，intake 域 **+119**。

**C. 组卷网粘贴解析加固（task-76，threadflow-engine）**：按 skill 里的真实页面结构补：「第 N 题」
题号、板块标题/试卷标题/裸来源前导合并、题首来源与分值剥离、新增
`ZujuanPastedQuestion.score`（只认括号「N 分」）、`故选：B` 抽答案（解析区任意位置、与
【答案】冲突告警）、`【点睛】` 进标签、选项编号异常（不从 A 起 / 缺号 / 重复 / 空内容）整行跳过 +
中文告警 + `isPartial`、图片占位只提示。`parseZujuanPaste` 签名不变。46 例新测试，域层 **+168**、
粘贴对话框 **+10**。**仍未用真实页面原文验证**（样本按页面结构改写）。

**D. 题目详情页配图增删（task-75，question-intake）**：`QuestionImagesSection` 加 `editable`
（默认 false，列表等只读调用不变），详情页传 true：FilePicker 多选 png/jpg/jpeg/webp/gif/bmp →
逐文件跳过 HEIC / 非图片 / 0 字节 / 读异常（单文件失败不整批失败）→ `store.save` → 手动
`invalidate(questionImagesProvider)` → SnackBar 汇总；删除走确认对话框 + `store.delete`。
空清单只读仍零占位，编辑模式留一行「添加图片」入口；l10n 12 key。6 例新 widget test（替身
FilePicker / store，不碰真实磁盘），详情页 22 例回归。

**门禁**：`dart analyze lib test` → **92 issues / 0 error / 0 warning**（基线）。全量
`flutter test --concurrency=1` → **+4088 ~2 All tests passed**（9 分 04 秒，日志 `E:\dsh-tmp-aot\test-129-full.txt`，EXIT=0）。`dart format` 只格式化本轮改动文件。

**docs 回填**：核对代码后，把 `QUESTION_BANK_DESIGN.md` 里三处过时的「未做（在途 task-70 / 74 / 73）」改成已交口径（编辑后带到收题页、预检结论渲染 + blocked 禁确认、排序选择器与内容量角标），§13 未做清单里「题库无 sourceUrl 字段」改为 v26 已加字段、只缺界面入口。

**未做 / 未验证**：真机系统文件选择器（Windows 对话框 / Android 选择器）与真实磁盘增删未手测；
组卷网粘贴仍未用真实页面原文跑（样本按 skill 文档结构改写）；内联选项抽取已知限制：题面与选项
同一行且首标记不在行首不抽、`（A）` 括号样式不认、`A．甲、B．乙` 无空白不认；详细文案仍中文
硬编码未接 l10n、`PaperGapNote` 无单独界面；拍照整理整条链路（真实模型回复）未端到端验证。

## 2026-10-21 轮次一百二十八：定点组卷网找题、拍照整理出题目、确认前预检、标签树三口径排序（Lead + 三个 teammate）

**起点**：轮次一百二十七（HEAD `529188d`，tag `v0.5.7`，双端发布件已备在 `dist/`、未推 GitHub）。
用户本轮诉求（m05023）：①拍照整理不能只产出标签/知识点/闪存卡，**要能直接存成题目**，题干可编辑；
②"确认逻辑与待确认描述"不明确；③标签树同层要能按字典序/内容量/添加时间排序。随后 m05115
「直接动手写代码」、m05424「用户可以人工登录组卷网账号获取答案」。本轮 12 个提交，
task-66..task-74 全部 completed（rev3）；成员只写各自作用域，git 由 Lead 统一提交。

**A. 定点组卷网找题（schema v26）**：先确认硬阻塞——组卷网对非浏览器请求返回阿里云 WAF JS
挑战页（纯 Dart HTTP 拿不到真页面），所以 App 不抓页面，做两条腿：**筛选链接**与**粘贴导入**。
筛选链接 = `zujuan_query.dart` / `zujuan_link.dart` 生成搜索页 URL（学科/知识点/难度/年份/
省份/年级/排序），`zujuan_pick_panel.dart` 底部表实时显示并可复制；粘贴导入 = `parseZujuanPaste`
支持**整卷多题**（题号切块、去〔加点〕〔波浪线〕〔着重号〕标记、答案/解析/知识点/来源/详情页 id，
永不抛异常），`zujuan_paste_import.dart` 转 `QuestionDraft`，`zujuan_paste_dialog.dart` 解析→
勾选→改题干→批量入库→汇总 saved/duplicates/failed。来源字段 v26（`sourceUrl/zujuanQuestionId/
zujuanBankId`）让详情页能回看题源。答案口径按用户 m05424：**用户自己登录浏览器看**（整张 JPEG、
每日约 30 道），App 不代持登录态；界面文案不写"拿不到答案"。测试 +122 domain、+15 粘贴导入、
+3 v26 迁移、+272 presentation。

**B. 拍照整理第四类产物「题目」+ 编辑入库**：领域层 `HandwritingProposalKind.question` 与
`options`（A–Z 连续、不重复）、`fields.stem` 必填、提示词铁律"只誊写不改写、不补全、不做题"；
应用层 `questionDraftForIntake`（只装配不写库）与 `_applyQuestion`（ingest、指纹去重、
标签不存在照建只提示、`markAppliedLocally`）。UI（task-70）：队列题目卡片展开题干/选项/答案/
解析摘要，「编辑后保存」把草稿回填收题页表单，保存后标已确认并 SnackBar 显示题号；收题页补多选
题型与草稿回填。测试 +20 域层、+10 应用层、+4 UI。

**C. 确认前预检（用户说的"确认逻辑有待提升"）**：`handwriting_proposal_preview.dart` 给每条
提案算 verdict（可以确认/确认前看一眼/不能确认）、目标路径、新建或复用、逐行中文预览、warnings、
blockers、同批重复；整批给三类计数与 `canApplyAll`。应用层 `previewFor` 读库里现有标签路径与
知识点标题（只读），队列页按签名缓存预检并上屏：blocked 条禁确认、整批有 blocked 禁"全部确认"、
顶部显示计数；预检失败只降级不崩。42 例域层 + 4 例应用层 + 3 例 UI。

**D. 标签树三口径排序**：纯逻辑 `tag_tree_sort.dart`（字典序 / 内容量降序 / 添加时间升序，
全序、不改入参）与 `tag_tree_view.dart`（孤儿/环兜底、path、子树计数、偏好编解码）；
数据源 `TagRepository.objectCountByTagId`（默认直接计数，子树累计显式开关）。UI（task-73）：
页面改接 `buildTagTreeView`，AppBar 三档选择器切换即重排，按内容量模式显示内容量角标，
计数异步未到按 0 不阻塞树。48 例纯逻辑 + 8 例 widget。**未接**：模式名暂用
`TagTreeSortMode.labelZh`、偏好仅会话内。

**门禁**：`dart analyze lib test` → **92 issues / 0 error / 0 warning**（基线）；各切片测试全绿
（zujuan +122、intake 域 +77、tags +86、presentation +279、迁移 +3 等）。全量
`flutter test --concurrency=1` → **3994 通过 / 2 跳过**（13 分 48 秒，v0.5.7 时 3667 / 2）。`dart format` 只格式化本轮改动文件。

**未做 / 未验证**：真实组卷网页面粘贴文本只用样例字符串模拟（未人工核对真实复制内容）；真机
整条链路（OS 拖拽微信图片、拍照整理→编辑→入库、预检异步、标签排序观感）未手测；英文文案未母语
校对；WAF 与官方开放平台未接（自动抓取仍不可行）；标签排序偏好未持久化、模式名未接 l10n；
内容量"直接计数 vs 子树累计"未做产品决定；题库删除清图片/图片增删入口/OCR 仍未做。

## 2026-10-20 轮次一百二十七：题号进复制与搜索、今日计划步骤可点、相似题与组卷理由更具体（Lead + 三个 teammate）

**起点**：轮次一百二十六（HEAD `87da95f`）把今日计划与题号检索纯逻辑铺完。本轮把它们接到界面、补上
「为什么排这里 / 缺什么」的可核实文案，并把题号真正带进组卷复制文本与题库搜索框。写作用域互斥，成员
全程不碰 git。task-58..task-61 全部 completed（rev3）。

**A. 题号进复制文本与搜索解析（task-58，question-intake）**：`renderPaperText` 新增可选
`Map<String, int?> serialNumbers`，每题在「序号.」后写 `formatQuestionSerial`；不传或没号不摆占位，
旧输出逐字不变。`_copyPaper` 复制前逐题 `ref.read(questionSerialProvider(id).future)` 取号，单题失败置 null 继续。
题库搜索框解析换新 `parseQuestionNumberQuery`（多认大小写 TR、全角数字、`#`/`＃`、可选全角连字符），
读不出回退旧 `tryParseQuestionSerial`（`00042`、长前导零仍可检索），题干原文始终保留以便 0 命中回落 LIKE。
测试 +6（组卷页 +4、搜索解析 +2），`test/features/questions/presentation` 249 例全绿。

**B. 今日计划步骤的跳转目标与页面接线（task-59 reasoning-core + task-60 question-intake）**：新增纯逻辑
`app/lib/domain/services/reasoning/daily_plan_step_destination.dart`——`destinationOf(DailyPlanStep)` 把六种步骤
映射成跳转目标，练习无题号 / 复习卡数 null·0·负数 / keepGoing / noData 不可导航，参数按种类收窄（不夹带
标题与分钟），43 例测试、reasoning 目录 +555 全绿。页面按目标给可导航卡加 InkWell + 箭头 + 目标文案 +
Semantics，不可导航保持静态；路由：练习/补链 → 题库页（无题号预筛，如实退回）、到期复习 → `ReviewPage`、
词表 → `CapabilityVocabularyPage`；新增 `todayStudyPlanPageBuilderProvider` seam。l10n 五文件手改 4 key。
测试 +8（共 21 例），`test/features/cognitive/presentation` +74 全绿。

**C. 相似题与组卷理由的「可核实依据」与缺口解释（task-61，threadflow-engine）**：相似题新增
`rank(detailedReasons: true)`，真有共用知识点 / 同型动作 / 两侧已知来源档位时在理由句尾追加「可核实依据：…」；
组卷新增 `compose(detailedNotes: true)`，每题写「本卷第 N 题」+ 需求/质量分/综合得分/权重依据（注明未标定）。
新增 `PaperGapNote` 与 `PaperPlan.uncoveredKnowledgePointNotes / deferredKnowledgePointNotes`：题库里没有候选
→ 先收题，有候选但被题数/配额挤掉 → 调大上限。来源六档中文表抽成 `source_level_labels.dart` 共用。
**两个开关默认关闭**：默认 JSON / 分数 / 理由逐字节不变（测试钉住）；新增 23 例，paper 目录 218 例全绿
（既有 195 例未改一字）。

**门禁**：`dart analyze lib test` → **92 issues / 0 error / 0 warning**（基线）；全量
`flutter test --concurrency=1` → **07:41 +3667 ~2 All tests passed**（exit 0；基线 3587 → 本轮 +80 例 = 43 + 23 +
4 + 2 + 8）。`dart format` 只格式化本轮改动的文件。

**未做 / 未验证**：详细文案开关还没接到 `paper_plan_builder` / `compose_paper` 工具 / 相似题 provider 与页面，
`PaperGapNote` 也还没有界面展示（默认关闭是有意为之，避免一次改掉所有既有文案）；练习步骤退回题库页不预筛
题号；`ReviewPage` / 词表页的加载态未被 widget 测试真实构造；真机复制剪贴板、返回栈、OS 拖拽均未手测；
闪存卡仍不显示题号（cards 与 questions 无外键，需另开 schema 片）。

### 发布 v0.5.7

- 双端构建（2026-10-20 00:22–00:24，从纯 ASCII junction `E:\Document\furnace-build` 构建）：
  Windows 157.0 s、Android 121.5 s，均 exit 0。
- Android：versionCode 16 / versionName 0.5.7，minSdk 24 / targetSdk 36，签名 `CN=Threadflow`（证书 SHA-256 `57de8b8f…`），
  APK **95,266,386 bytes（90.85 MB）**，SHA-256 `EB28FD3B27CF989C46979A34B0A20474390FBD111D46AA0A25F057EFE388694A`。
- Windows：`data/app.so` **20,071,304 bytes**，Release 目录清理调试产物（`kernel_blob.bin`，105,422,664 B）后
  **28 个文件 / 45,718,047 bytes**，zip **19,928,866 bytes（19.01 MB）**，
  SHA-256 `F02BFAA257931171B28BBC82792DFEE0A83FE25B70D3872E551F7ACAADA3C594`；`furnace.exe` 版本资源 `0.5.7+16`。
- **无数据库迁移**：schema 仍为 v25（与 v0.5.6 相同），可直接覆盖安装。
- 发布件放在 `dist/`（gitignore，不入库），**未推送 GitHub**，由用户自己上传。

## 2026-10-19 轮次一百二十六：今日计划上屏、plan_today 会说计划、题号检索有了纯逻辑（Lead + 三个 teammate）

**起点**：轮次一百二十五把「今日学习计划生成层 / 配题推荐 / 入库体检摘要」的纯逻辑铺完（v0.5.6 已出包，未推
GitHub）。本轮把它们真正接上真实数据、页面与 AI 工具，并补上题号检索的纯逻辑。写作用域互斥，成员全程不碰
git。本轮 task-53..task-57 全部 completed（rev3）。

**A. 今日计划数据层（task-54，Lead）**：新增 `app/lib/features/cognitive/application/daily_study_plan_reader.dart`——
`readDailyStudyPlan`（洞察 → 能力画像 → 学习建议 → 配题候选 → `DailyStudyPlan.build`，不重排不重算）、
`readDailyStudyPlanInsights`（词表走 `CapabilityVocabularyStore`，读取失败退回空 overlay、未知动作照实统计）、
`readDailyStudyPlanProfile`（`reasoning_steps` → `CapabilityStepSample` → `CapabilityProfile.of`）、
`readDailyStudyPlanQuestionCount`（全库题数，与 `questionCorpusCountProvider` 同口径），以及
`dailyStudyPlanProvider`（watch `dataRevision`；到期卡数用 `AnkiRepository.getDueCardStates(now)` 注入，时钟只此一处）。
测试 11 例。

**B. 页面「今天做什么」（task-55，question-intake）**：`today_plan_page.dart` 页顶新增独立区块消费
`dailyStudyPlanProvider`——总分钟、跳过条数、步骤卡（标题 / 约 N 分钟 / 理由，顺序照抄）、loading 只一行、
失败原文 + 重试、noData 步骤原样显示；旧复习清单保留不删不合并，两块各自加载各自失败；刷新按钮同时
invalidate 两个 provider；稳定 key 四个；l10n 五文件手改 7 个 `todayStudyPlan*` key（中英齐备）。测试 +6（共 13 例），
`test/features/cognitive/presentation` +66 全绿。

**C. `plan_today` 的 `study_plan`（task-56，reasoning-core）**：`today_tools.dart` 复用 `run()` 里同一 `moment` 的
到期读数调 reader，`modelResult` 新增 `study_plan`（`DailyStudyPlan.toJson()`，旧 6 键全部保留），摘要补「今天预计
N 分钟、M 步；先做：X，再做：Y」；读取失败只丢增量字段并说明，工具仍成功。测试 +4（共 12 例）。

**D. 入库体检摘要接进 AI 工具（task-53，threadflow-engine）**：`audit_question_intake` 用与 findings 同一份
（已按 severity 过滤）的结论按题分组构造 `QuestionAuditReport`，调 `QuestionAuditSummary.summarize` 后
`modelResult` 新增 `summary`（题数 / 干净比例 / 分档 / 判据计数 / topOffenders）与 `priority_note`（优先级分数未标定），
摘要句点名优先修题（TR 编号 + 分数）；空库与全干净库各有一句。测试 +5（共 15 例）。

**E. 题号检索纯逻辑（task-57，threadflow-engine）**：新增 `app/lib/domain/services/questions/question_number_query.dart`——
`parseQuestionNumberQuery`（`TR-00001` / `tr-12` / `#7` / `＃７` / 全角数字 / 前后空白都归一；位数上限 9；`0`、负数、
夹字符一律拒绝，失败返回 null 不抛异常）、`isQuestionNumberQuery`、`matchQuestionSerial`、值对象
`QuestionNumberQuery`（相等只按题号）；`QuestionNumberQuery.normalizedLabel` 用既有 `formatQuestionSerial` 补零。
测试 46 例 / 8 组。

**门禁**：`dart analyze lib test` → **92 issues / 0 error / 0 warning**（基线）；全量
`flutter test --concurrency=1` → **+3587 ~2 All tests passed**（09:29，exit 0，新增 72 例：5 + 11 + 6 + 4 + 46；
日志 `E:/dsh-tmp-aot/test-126-full.txt`）。docs：`REASONING_LAYER_DESIGN` §27（reader / provider 接线）、
§28（页面「今天做什么」）、§29（`plan_today` 的 `study_plan`）。

**未做 / 未验证**：题号检索纯逻辑还没接搜索框（界面仍用旧 `tryParseQuestionSerial` 解析）；页面步骤还不能点进
对应页面；`plan_today` 读取失败退化分支无单测；真机小屏滚动与真实大库下 plan_today 延迟未手测；v0.5.6 之后本轮
改动尚未出包。

## 2026-10-19 轮次一百二十五：词表能编辑了、体检与质量报告上屏、组卷开始会说话（Lead + 三个 teammate）

**起点**：轮次一百二十四把「体检 / 洞察 / 学习建议 / 组卷配额」的纯逻辑铺完，本轮把它们接到真实数据、界面
与 AI 工具：能力词表可以在设置页里编辑并导入导出、入库体检与学习建议成了模型能自查的两个工具、思维链有了
质量体检、组卷有了质量评价报告并在页面与 Word 里上屏、洞察页与配题推荐也落了地。写作用域互斥，成员全程不碰
git。本轮 task-25..task-47 全部 completed（rev3）。

### 收尾补记（任务板 task-49..task-52，commit `c9f4e96`、`4bedc9a`、`f1ffcf3`、`b033835`、`047bd88`）

05:00 收尾前落地的四个方向，代码与测试均完成，本轮一并入包（v0.5.6）：

- **题库入库体检摘要 QuestionAuditSummary（task-51）**：把 26 条判据的体检结果聚合成只读摘要
  （总题数 / 分档计数、按判据命中数、按严重度分布、截断与空库口径），供页面与工具共用；测试 38 例。
- **今日学习计划生成层 DailyStudyPlan（task-50）**：洞察 + 学习建议 + 配题推荐 + 到期卡片 → 确定性的
  「今天做什么」；固定优先级与预算（时长可注入）、未知动作不写练习步骤、无数据回单条 noData、
  放不下的步骤计入 skippedStepCount；纯逻辑，不读库 / 时钟 / 模型；测试 48 例。
- **洞察页「下一步练什么」（task-49）**：名次、题号徽章、理由折叠（最多 3 条）、命中动作中文名、
  skipped 计数、点击进题目详情；loading 安静、error 降级；l10n 五文件手改 16 key；测试 11 例。
- **`recommend_practice` 只读工具（task-52）**：把配题推荐暴露给模型（max_questions / subject_key /
  target_difficulty），返回题号、分数、理由与命中动作；不生成题目、不写库；工具总数 24 → 25；测试 14 例。

四套件新增 111 例（38 + 48 + 14 + 11），组合跑 +174 全绿；`dart analyze lib test` 仍 92 issues /
0 error / 0 warning。docs：REASONING_LAYER_DESIGN §24–§26、AI_DESIGN 工具清单 24 → 25、
QUESTION_INTAKE_AUDIT_DESIGN 补聚合层。

**A. 能力动作词表可编辑（commits `34823d6`、`d7b9230`、`4a7c004`，Lead + reasoning-core + question-intake）**：
application 层把 `CapabilityActionOverlayEditor` 的 add / update / remove / reorder / mergeImport 与
`CapabilityVocabularyStore` 接进 Riverpod（保存后失效 overlay provider，推理服务下一次解题就用新词表）；
新增纯逻辑 JSON 编解码（64 KB 上限、BOM/CRLF 与两种顶层形状兼容、version 四态、fatal 前置排序）；设置页
新增「能力动作词表」编辑页（内置词表只读 + 自定义动作增删改 / 导入 / 保存），l10n 五文件手改。测试：编辑页 13 例。

**B. 组卷配额与手工名单（commits `36d0ff3`、`b1fa82e`、`757b674`、`9f7f494`、`9606829`、`d0c24eb`、`2bdaffd`）**：
学科配额与领域配额分别接进 `PaperSpecNotifier` 与 `compose_paper` 工具（领域键 = 标签路径第一段，与学科键两套
命名空间）；组卷页两张配额卡（上限 / 保底编辑 + 被挡与缺口展示）；手工指定 / 排除纯逻辑（优先级：排除 > 必收
（绕过学科 / 来源 / 难度过滤与三类上限，只受 targetCount）> 学科保底 > 领域保底 > 填充；missing / skipped /
conflict 三类如实回报）接进 provider 与工具，页面加必收 / 排除两栏 + 选择题对话框 + 结果提示（18 个 l10n key、
15 例测试）。

**C. 两个模型可自查的 AI 工具（commits `77f205c`、`d03c93c`、`e2f9496`）**：`audit_question_intake` 把 26 条
入库体检判据暴露给模型（只报不改，不是 AI 自己判断）；`get_learning_advice` 把洞察 + 画像 + 题库题数拼成
确定性建议（练习只给真读数、未知动作不吸收、知识点最多 3 个）；学习建议同时接上真实读数 provider。测试各 10 例。

**D. 相似题接 MindNet 有效性（commit `02175d8`）**：`SimilarityWeights.quality` 成为第五个可选分量（默认 0
未标定），候选与聚焦题共用知识点时用 `questionQuality` 打分（无共用点 = 中性 0.5）；打开后有序性不变，但
归一化会让绝对分略抬（0.4 → 0.4333），已用测试钉住。

**E. 思维链洞察的交叉读数与学习洞察页（commits `06e0d1b`、`9db6873`、`dcbaca1`）**：聚合层新增「动作 ×
知识点」交叉桶（`highRiskByActionAndKnowledgePoint`），学习建议的练习卡据此填知识点；application 层
`learningInsightDataProvider`（洞察 + 建议 + 词表 + 知识点名，词表读失败退回空 overlay + fallback 标记）；
设置页新增「学习洞察」入口，洞察页 721 行只消费该 provider（汇总 / 建议卡 / 动作分布 / 未知动作块 / 未用过动作 /
卡点热区 / 交叉表），33 个 l10n key，测试 15 例。

**F. 读题工具 `read_question`（commit `e492ff6`）**：只读，按 `question_id` 或题号（TR-00042 / tr-42 / 00042 /
42）定位，缺参 / 坏号 / 查无都返回失败；返回题干、选项（按 sortOrder）、答案、解析、学科来源、知识点、最新
解题链动作与配图数。15 例测试，含「调用前后全库快照不变」的只读证明。

**G. 思维链质量体检（commits `7fcc7c2`、`80e6f9e`）**：纯逻辑 19 条判据（error 6 / warning 9 / info 4），
knownAction 按当前词表重判、NaN/±inf 读数单报 invalid_risk_reading、整链无读数报 no_risk_reading，排序与截断
确定性；application 层读表 + 三个 provider（含单题 family）。测试 51 + 11 例。

**H. 组卷质量评价（commits `518ca43`、`0ed156b`、`b39af7a`）**：纯逻辑 17 条判据（空卷 / 填充不足 / 学科集中 /
来源单一 / 知识点缺口 / 难度过平或偏离目标 / 保底未达 / 配额挡下 …）；provider 从原始候选回填逐题难度；
`compose_paper` 的 `model_result` 直接带 `quality`，摘要点名「最该看」的一条并注明另有几条。测试 37 + 9 + 4 例。

**I. 题目卷 Word：组卷说明与质量节（commits `dd94abd`、`aa3d065`、`a01df94`）**：「组卷说明」附录分节（学科与
领域分布、手工指定三类名单、配额挡下、保底缺口，只有数据非空才渲染，默认输出逐字节不变）；质量节（分布 + 判据，
版面折叠 6 行分布 / 同 code 3 条判据，折叠只写计数不静默丢内容）；export 层 `buildPaperDocxExport` 透传报告。
测试：组卷说明 20 → 42 例、质量节 16 例，export 目录 157 例。

**J. 组卷页质量体检卡（commit `6dcceb6`）**：`PaperQualitySection` 只读 `paperQualityReportProvider`（loading
安静、error 降级、data 按错误 → 警告 → 提示分组、evidence 可展开）；导出按钮用 `valueOrNull` 传报告（未就绪不
阻塞导出，传 null 与旧行为逐字节一致）；11 个 `paperQuality*` l10n key；测试 12 + 3 例，presentation 232 例全绿。

**K. 配题推荐（commit `fbd25f1`，reasoning-core）**：`PracticeRecommendationPlan`（518 行纯逻辑）——9 种理由、
权重全部 public const（命中动作 ×3、命中知识点 ×2、未知动作补习 1.5、难度贴近最多 2、缺解析 −1.5、缺答案 −1.0），
排序 score desc → 命中动作数 → serialNo（null 最后）→ questionId，截断显式进 skipped；45 例测试。

**L. 文档**：`REASONING_LAYER_DESIGN.md` §14.4 / §15 / §16 / §17 / §18 / §19 / §20 / §21 / §22；
`PAPER_COMPOSER_DESIGN.md` §13–§23；`SIMILAR_QUESTIONS_DESIGN.md` §7；`QUESTION_INTAKE_AUDIT_DESIGN.md` §13；
`DOCX_EXPORT_DESIGN.md` §13 / §14 / §14.6；`AI_DESIGN.md` 工具清单更新为 24 个；`QUESTION_BANK_DESIGN.md` §14；
`PROGRESS.md` 轮次一百二十三 / 一百二十四条目。

**M. 验收**：`dart analyze lib test` → **92 issues / 0 error / 0 warning**（= 基线）；各切片定向测试全绿
（词表编辑页 13、交叉读数 24、洞察页 15、read_question 15、链质量 51 + 11、组卷质量 37 + 9 + 4、Word 组卷说明
42、质量节 16、导出透传 19、质量卡 12 + 3、配题推荐 45、手工名单 15 + 8 + 3、领域配额 44、学科配额 33 + 8 + 3）；
reasoning 目录 464、paper 目录 195、export 目录 157、presentation 目录 232 全绿。全量 `flutter test --concurrency=1`
→ **+3392 ~2 All tests passed**（E:/dsh-tmp-aot/test-125-full.txt，9 分 44 秒；2 条 skip 为既有跳过）。

**N. 未做 / 已知限制**：词表编辑页、洞察页、质量卡均未真机手测（小屏滚动、长 evidence 换行）；英文文案未母语
校对，体检 / 质量 / 建议的 messageZh 仍是中文硬编码，evidence 字段标签走 Dart const map 不走 l10n；质量卡与
体检只报不改（没有「一键按建议调整」）；配题推荐只到纯逻辑，界面与详情页入口未接；相似题 quality 权重、所有
质量判据阈值都还是先验值未标定；带组卷说明与质量节的 docx 未在 Word 真机上重测页数与分页。

---

## 2026-10-19 轮次一百二十四：体检上屏、思维链会说话了、组卷开始按学科配额凑（Lead + 三个 teammate）

**起点**：轮次一百二十三把地基铺完（v25 词表 overlay 持久化、题号检索 API、体检纯逻辑、洞察聚合），
本轮把「纯逻辑」接到真实数据与界面上，并补上「看到读数之后该练什么」的建议层。task-17..task-24
全部 completed（rev3）；Lead（体检读表/洞察读表/学习建议 provider/配额接线/docs/git）、reasoning-core
（洞察聚合 + 学习建议纯逻辑）、threadflow-engine（组卷学科/领域配额纯逻辑）、question-intake（体检 UI）。

**A. 入库体检接真实题库（commit `91efd96`，11 例）**：新增 `question_audit_reader.dart`（约 230 行）——
一次读 questions / question_options / object_tags / attachments，投影成 `QuestionAuditRow` + 题库学科键
`knownSubjectKeys`；知识点推导复用 `TaskKnowledgePointResolver`（与组卷/相似题同一规则），选项按
`sortOrder` 升序平手比 label（与 `QuestionRepository.optionsOf` 同口径），`imageCount` 只数
`attachments.owner_type == question` 的行；**全量读**（不用 `all()` 的 200 条上限，H4 跨行重复必须看全）；
空题干保留（空题干本身就是 H1 硬伤）。两个 provider：`questionAuditCorpusProvider` 与
`questionAuditReportProvider`（`currentYear: DateTime.now().year`）。

**B. 体检上屏（commit `4a943f3`，question-intake，9 文件 +776/-1）**：新增 `question_audit_view.dart`
（284 行）——题库列表徽标 `QuestionAuditBadge`（Tooltip 分严重度）+ 题目详情页体检区
`QuestionAuditSection`（按严重度分组、evidence 展开、只报不改）；l10n 五文件手改 6 个 key；
`question_audit_ui_test.dart` 4 例；presentation 目录 157 例全绿。

**C. 思维链洞察聚合（commit `e5e9e57`，reasoning-core）**：新增 `chain_insights.dart`（约 660 行纯 Dart）——
`ChainInsightStep.fromParsedStep` / `ChainInsightChain.fromParsedChain` 把解析后的链投影成聚合输入，
`ChainInsights.aggregate` 出动作分布（步数/题数/链数/平均与最高卡点/最近出现/known+custom+unknown）、
高风险步（默认阈值 0.6）按题目与知识点分组、`neverUsedActions`（当前词表里从没出现过的动作）；
异常显式计数不静默（空 chainId/actionType、重复 chainId/index、NaN/±inf、越界风险夹 0..1）；
排序确定性（步数 → 题数 → 高风险步数 → 平均风险 → actionType）；测试 **58 例**，reasoning 目录 +216。

**D. 洞察与建议接上真实库（commits `cca2e23`、`8617202`、`e2f9496`）**：`chain_insights_reader.dart` 读
`reasoning_chains` + `reasoning_steps` 投影（链 createdAt/id、步骤 idx/id、坏 knowledgeHints 记非法数、
孤立步骤单列、knownAction 留空交给当前词表重判），配 `chainInsightCorpusProvider` / `chainInsightsProvider`
（词表读取失败退回内置词表）+12 例；`learning_advice.dart`（reasoning-core，429 行纯逻辑）把洞察 + 能力画像
变成确定性建议（练习/补链/看词表/继续/无数据五类，优先 100/200/300/400/500，只给真读数、未知动作永不进练习，
空输入不虚构「有题缺链」）**48 例**；`learning_advice_provider.dart` 接线——`questionCorpusCountProvider` 用
COUNT + `watchDatabaseRevision`，`learningAdviceProvider` 三输入，并补了洞察读表的库修订 watch（之前新链要重启
才出现）；文案诚实：0 链说「但当前还没有任何解题链」、部分覆盖写「只覆盖 X 道题，还有 Y 道没有链」；**10 例**。

**E. 组卷配额纯逻辑（commits `c5c924b`、`418face`）**：`subject_quota.dart`（191 行）按学科上限/保底，
`domain_quota.dart`（329 行）按标签路径第一段（领域）上限/保底；两者都归一化配置（trim/排序/负值与重复键抛
`ArgumentError`/同科 min>max 抬上限），`paper_composer.dart` 接入：targetCount 硬上限 > 学科保底 > 领域保底 >
填充（知识点上限 → 学科上限 → 主领域上限）；被挡题与保底缺口**全部回报不静默丢**；`null`/空表不启用时旧
`toJson` 十键逐字节不变。测试 `subject_quota_test` **33 例**、`domain_quota_test` **44 例**（paper 目录 +78/+122）。

**F. 学科配额接线（commit `36d0ff3`）**：`PaperSpecNotifier` 加 `setSubjectQuota` / `setSubjectMax` /
`setSubjectMin` / `clearSubjectQuota`（空表视同不启用、不留空壳），`compose_paper` 工具加 `subject_quota` 参数
（学科 -> {max,min}，形状/重复键/未知字段/负值全部 `ToolArgError`），启用时 `modelResult` 追加
`by_subject` / `quota_blocked_questions` / `subject_shortfalls` / `subject_quota`，摘要补学科分布、被挡 N 道、
保底缺口三句。工具测试 14→22、provider 测试 11→14。

**G. 文档**：`REASONING_LAYER_DESIGN.md` 追加 §14 洞察聚合、§15 学习建议、§16 接线；
`PAPER_COMPOSER_DESIGN.md` 追加 §13 学科配额、§14 领域配额（含「领域键是标签路径第一段、与学科键两套命名
空间」口径）；`MINDNET_ROADMAP.md` 未做清单更新；`QUESTION_INTAKE_AUDIT_DESIGN.md` 的接线计划改成已做。

**H. 验收**：`dart analyze lib test` → **92 issues / 0 error / 0 warning**（= 基线）；各切片定向测试全绿
（体检读表 11、洞察 58+12、学习建议 48+10、学科配额 33+8+3、领域配额 44）与 paper 122 例回归。

**I. 未做 / 已知限制**：洞察页与学习建议卡片还没有界面（数据与 provider 已就绪）；词表编辑页 UI 未做；
体检「自动修复」特意不做（只报不改）；配额数值仍未标定（默认不启用）；体检 `messageZh` 仍是中文硬编码。

---
## 2026-10-18 轮次一百二十三：词表能存下来了、题号能搜、体检有判据了（Lead + 三个 teammate）

**起点**：轮次一百二十二收尾后，按用户 m00340 的五个应用领域与「能力动作词表要可扩展」继续。本轮四切片
（task-12..task-16）全部 completed（rev3）：Lead（schema v25 + 推理接线 + 题号检索 API）、reasoning-core
（overlay 编辑操作层 + 未知动作发现）、threadflow-engine（入库体检纯逻辑）、question-intake（题号 UI +
删题清配图 + 题库搜索框按号）。写作用域互斥，成员全程没碰 git。

**A. 词表 overlay 持久化与接线（schema v25，commit `f03b396`，12 文件 +810/-8）**：`LocalSettings` 加可空列
`capability_action_overlay_json`（与既有可空偏好同契约：NULL = 用户没改过 = 出厂词表；迁移**不写**默认值；坏
JSON 读作空 overlay 不阻塞解题）；`_upgradeV24ToV25` 只 `addColumnIfMissing`，`_ensureColumns` 自愈；
`CapabilityVocabularyStore`（load 永不抛 / save 空 overlay 写 NULL / 非空写 `{"version":1,"customActions":[...]}`）+
两个 provider；`QuestionReasoningService` 加可选 `overlayLoader`，`solveAndDecompose` 每次跑取当前词表：
`solveThenDecompose(capabilityCatalog: catalog.actions)` 与 `parseChain(raw, lookup: catalog.byKey)` **同一份词表**，
读失败退回内置词表不阻塞；题号检索 API：`QuestionRepository.findBySerialNo` + `search(serialNos:)`（空集=无命中、
null=不过滤）。证据：v25 迁移 3、词表存储 12、题号检索 2、overlay 接线 3，共 **+40**；`DATA_MODEL.md` §14。

**B. 编辑操作层与未知动作发现（commit `bb84ad8`，reasoning-core，6 文件 +1674/-2）**：
`capability_action_overlay_editor.dart`（395 行）——`add` / `update` / `remove` / `reorder` / `mergeImport` 静态纯函数，
`maxCustomActions = 100`，失败返回原 overlay + 单条 issue 不抛；新增 issue code（keyNotFound / indexOutOfRange /
customActionLimitExceeded / importNotRecognized）；`capability_action_discovery.dart`（202 行）按频次统计步骤样本里
**不在词表里的动作**（步数/题数/高风险数/样本题目），为「把模型新造的动作加进词表」供数据；生产必须传
`overlay.catalog`（否则自定义动作被误报）。测试 **+59**（34+25）；`REASONING_LAYER_DESIGN.md` §4.1。

**C. 题号进界面、删题清配图（commit `129262d`，question-intake，14 文件 +290/-7）**：新增
`QuestionSerialBadgeById(questionId)`（异步读号，加载/失败不占位），接相似题候选行与组卷页题目首行；删题唯一入口
先 `QuestionMediaStore.deleteForQuestion(id)` 再 `deleteQuestion`（清理失败 debugPrint 不阻断），SnackBar 带清理张数；
l10n 五文件手改 `questionIntakeDeletedWithImages`；presentation +7 例；`QUESTION_BANK_DESIGN.md` §11.1/§11.2。

**D. 入库体检判据（commit `2f51914`，threadflow-engine，3 文件 +2320）**：新增
`question_intake_audit.dart`（1,050 行纯 Dart，只 import 题号工具）——26 条确定性判据：H1 题干/选项 10 条、
H2 答案/解析 6 条、H3 元数据 6 条、H4 重复/编号 3 条 + 本地点 1 条；严重度 error/warning/info，报告排序
questionId → severity → code，确定性；阈值常量集中公开（最少 6 字、年份 1900–今年+1、难度 1–10、aiQuality 0–1），
`currentYear` 必须注入不隐式读 now；测试 **53 例**（8 组），新文档 `QUESTION_INTAKE_AUDIT_DESIGN.md`（282 行）。

**E. 题库搜索框按题号（commit `4da1c5b`，question-intake，9 文件 +230/-17）**：`QuestionLibraryFilter` 加 `serialNo`，
`parseQuestionLibrarySearch` 先 `tryParseQuestionSerial`（认 TR-00042 / tr-42 / 00042 / 42），认得出就优先
`search(serialNos:)`、0 命中回落题干 LIKE；读不出号只按题干；纯空白不筛；l10n 提示改成「搜题干或题号」；
11 + 2 例测试；presentation +153。

**F. 验收**：`dart analyze lib test` → **92 issues / 0 error / 0 warning**（= 基线）；五个切片定向测试全绿
（+40 / +59 / +140 / +63 / +153）；docs 同步 DATA_MODEL §14、REASONING §4/§4.1、QUESTION_BANK §11.1/§11.2、
新体检设计文档。

**G. 未做 / 已知限制**：词表编辑 UI 与 l10n 未做（application 层下一轮补）；体检还没有上屏；题号还没进闪存卡、
组卷页纯文本复制不带题号；按号搜索未真机手测；体检 `messageZh` 中文硬编码、英文按 code 映射留待做。

---
---

## 2026-10-18 轮次一百二十二：题目卷导出成 Word、题干能拿去组卷网搜（Lead + 三个 teammate）

**起点（用户 m00726）**：「docx 文档的构建和组卷网的链接可以借鉴 dsh skill」。分别借鉴 `paper-composer`
（试卷排版：Word 真测、页面几何、字体字号、OMML 公式、图片随文、页脚域）与 `zujuan-source-standards`
（组卷网链接构造、检索词切法、答案与配额）。口径是「能生成文件」不算完成 —— 要 Word 真开、量页码与
公式数、链接编码逐字节对站点。本轮 task-7..task-11 全部 completed（rev3）；成员：Lead（docx 核心/装配/
发布/docs/git）、reasoning-core（LaTeX→OMML）、threadflow-engine（组卷网纯逻辑）、question-intake
（两个界面入口 + l10n）。写作用域互斥，成员全程没碰 git。

**A. 纯 Dart OOXML 层（commit `de1d979`，5 文件）**：新建 `lib/domain/services/export/docx_writer.dart`
（773 行）——`DocxBuilder` 拼 zip：`[Content_Types].xml`、`_rels/.rels`、`word/document.xml`（根声明
w/r/wp/a/pic 命名空间）、`word/_rels/document.xml.rels`、`word/styles.xml`、`word/settings.xml`、
`word/footer1.xml`、`word/media/imageN.*`；`_sect()` A4 `pgSz 11906×16838`、`pgMar` 左边 680 / 右 2268 /
上下 1020 twips；页脚用 `fldChar` PAGE / NUMPAGES 域 + 右对齐制表位（左时期代号右页码）+ pBdr 顶线；
文本 XML 转义、控制字符丢弃、`xml:space="preserve"`、换行→`<w:br/>`；图片先解析 PNG/JPEG/GIF/BMP/WEBP
像素尺寸（`lib/data/media/image_size.dart`，205 行）再等比缩放（0.62 栏宽 / 0.22 页高上限、1.5 倍放大封顶），
`wp:inline` 随文不跑位。`paper_docx.dart`（881 行）装配整卷：标题 30 半磅黑体 + meta 行 + 每题题号行
（12 半磅黑体 keepNext）、meta 行（学科/来源档位/sourceLabel/zone/知识点/年份/地区）、题干按换行拆段、
选项 `A. …`、配图、行内 `$...$` 交给注入的 `DocxMathCompiler`；附录「参考答案与解析」另起一页（只有
第一个附录标题带 `pageBreakBefore`，测试断言该元素出现恰好 1 次），答案缺省回退到正确选项字母；卷末
「导出提示」列出缺失题/空题干/缺答案/缺解析/跳图/公式失败，**不静默丢内容**。三组测试约 60 例。

**B. LaTeX→OMML 编译器（commit `a97b978`，reasoning-core）**：移植 paper-composer 的 `omml.py` →
`lib/domain/services/export/omml/omml.dart`（1,159 行），API `compileLatexToOmml(String tex,{int? sizeHalfPt})`
返回不带 xmlns 的 `<m:oMath>` 片段（命名空间由 document.xml 根声明），另有 `plainTextOfLatex`、
`supportedLatexCommands`、`LatexError{message,position,context}`；覆盖 frac/sqrt/根号/left-right/巨算符/
函数名/希腊字母/矩阵/cases/aligned/重音/上下划线/binom/直立 mathrm；未知控制序列必须抛错而不是丢反斜杠
静默退化（旧实现出过的事故）。单跑 `test/domain/services/export/omml` **+84**。

**C. 卷面装配到字节（commit `81cae64`，4 文件）**：`lib/features/questions/application/paper_docx_export.dart`
（187 行）把 `PaperPlan` + 题库装配成 `PaperDocxQuestion`（题号/题干/选项/答案/解析/配图字节）；
`question_corpus_reader.dart` 新增 `readQuestionDocxContents`（`serialNo`、选项、答案、解析、
`QuestionMediaStore` 图片与像素尺寸）；`tool/docx_probe.dart`（185 行）离线探针从真实库生成样张供 Word COM
验收；`paper_docx_export_test` 覆盖装配与降级。

**D. 组卷网链接纯逻辑（commit `9044989`，threadflow-engine，3 文件 759 行）**：
`lib/domain/services/zujuan/zujuan_link.dart`（130 行）——`zujuanSearchUrl`（先 UTF-8 标准 base64 再
`encodeURIComponent`，query 固定 `keyword=&intent=question&b=0&urlSource=0`）、`zujuanQuestionDetailUrl`
（`/<bankId>q<questionId>.html`）、`zujuanPaperDetailUrl`（`/<bankId>p<paperId>.html`），缺 id 返回 null 不猜；
`zujuan_keywords.dart`（295 行）——剔除 `$...$`、`![](...)`、`〔...〕`，保留拉丁字母与数字，标点当分隔，
长度 4–28，按内容词密度排序，`zujuanSearchCandidates` 最多 8 条（UI 取 5）。`zujuan_link_test.dart`（334 行）
**+25**，含中文/空格/`+` 号编码、公式图标记剔除、纯公式空结果。

**E. 两个界面入口（commit `a913513`，question-intake，11 文件 +1605/-6）**：
`paper_docx_export_button.dart`（331 行）——组卷页「复制卷面」旁「导出 Word」，FilePicker 另存为、
loading/防重入、成功/空卷/失败 SnackBar、告警明细对话框（每类最多 3 条 + hiddenCount，key
`paper-export-docx`）；`question_zujuan_search.dart`（203 行）——题目详情页「去组卷网找这道题」，底部表
最多 5 条候选，可复制检索词或搜索链接（先关表再 SnackBar，不新增 url_launcher）；l10n 五文件手改
17 + 7 个 key（未跑 gen-l10n，沿用既有手改方式）。测试：组卷页导出 +10（3 纯逻辑 + 7 widget）、详情页
+22（16 旧 + 6 新），presentation 目录 **+133**。

**F. 文档（commit `d802bf9` + `6416553`）**：新建 `docs/DOCX_EXPORT_DESIGN.md`（分层/版面参数/zip 条目/
契约/图片缩放公式/公式策略/卷面装配/验收证据/未做）、`docs/ZUJUAN_LINKS_DESIGN.md`（URL 规则/检索词规则/
API/UI 接线/验收/未做）；`docs/QUESTION_BANK_DESIGN.md` 追加 §12 Word 导出与 §13 组卷网链接；
`docs/FEATURE_MATRIX.md` 补两行；`app/android/.gitignore` 忽略 Gradle 的 `.kotlin/`。

**G. 验收（真实输出）**：`dart analyze lib test` → **92 issues / 0 error / 0 warning**（= 基线）；定向：
export + media + application/paper_docx_export_test **+158**、zujuan **+25**、presentation **+133**、版本测试 +4；
全量 `flutter test --concurrency=1` → **+2489 ~2 All tests passed（EXIT=0）**（上一轮基线 +2290）。
Word 真测（探针样张 + Word COM 打开→导出 PDF）：**2 页 / 546 字 / 29 个 OMath / 2 张内嵌图 / PDF 205,630 bytes**，
文件 6,566 bytes；公式可编辑、图片随文、附录另起一页。

**H. 发布 v0.5.4（含上一轮已合并但未发布的改动）**：`app/pubspec.yaml` `0.5.3+12 → 0.5.4+13`，
`kAppVersion='0.5.4'`、`kAppBuildNumber=13`。脚本 `E:\dsh-tmp-aot\release-054-build.ps1`（日志
`release-054-build.txt`）：Windows **163.7 s exit 0**，`furnace.exe` 91,648 bytes（版本资源 0.5.4+13）、
`data/app.so` **19,366,792 bytes**；删掉调试运行留在 Release 的 `kernel_blob.bin`（105,422,664 bytes）后
**28 files / 45,012,219 bytes**，zip **19,652,645 bytes**（SHA-256 `89D20BF8…`），解压冒烟 28 files 通过。
Android **387.6 s exit 0**，APK **93,397,838 bytes（89.1 MB）**、`versionCode 13` / `versionName 0.5.4`、
minSdk 24 / targetSdk 36、签名 `CN=Threadflow` 证书 SHA-256 `57de8b8f…`（与 v0.5.0–v0.5.3 同一把，可覆盖
安装），APK SHA-256 `BB9ABCD6…`。`dist/` 只留三件：APK、Windows zip、`RELEASE-v0.5.4.md`。
**没有推送 GitHub**（用户自己传）。

**I. 未做 / 已知限制**：真机 OS 拖拽（微信聊天记录临时路径）与 FilePicker「另存为」未手测；英文界面
导出的 docx 内部标签仍是中文（有意取舍）；docx 无 PDF 直出/表格/浮动图/页眉多栏，WPS/LibreOffice 兼容未验证；
题库表没有 `source_url`，不记录「已找到」；组卷网领域词表只有生物学科；相似题 MindNet quality 权重仍为 0
（未标定、provider 未接线）；登录/云同步/语音朗读/字体导入仍无。

**J. 下一轮计划**：①五个应用领域逐个接线（任务排序 / flashcard 推送与同步 / 纸质端上传同步 / 题目搜索
入库评价 / 智能组卷评价与资料补充）；②quality 标定并接 `knowledgePointReadings`；③题号进组卷页/相似题区/
闪存卡 + 按号搜索；④词表 overlay 持久化（表 + provider + 编辑页）；⑤真机验证微信拖拽与另存为；
⑥docx 图片纳入受控环绕与 PDF 直出（若确有需要）。

---

## 2026-10-18 轮次一百二十一：题库长出编号和图片、微信照片能拖进来、错题先空两张、找相似题看得见 MindNet（Lead + 三个 teammate）

**起点（用户 m00340，长消息）**：闪存卡别原地重复，答错后空 2–3 张再来（每日任务到最后没有空卡了
才连续出现）；「不调模型（确定性模板）」要的是确定性公式但**必须融合 MindNet** 做相似题质量评比；
题库的一个重要因素是**图片**；拖动添加照片**必须支持微信聊天记录**；导入导出要能简单生成 Word/docx；
五个应用领域必须包含（任务排序 / flashcard 推送与同步 / 纸质端数据上传同步 / 题目搜索入库评价 /
智能组卷评价与资料补充）；每道题给一个**跨学科整体编号**（SCP 式），可以形成"臭名昭著"的题号。
上一轮团队随旧会话失效，本轮先用 `spawn_teammate` 重建等价团队（新成员不继承旧记忆），再按片推进。

**A. 团队重建与任务板**：新成员 reasoning-core（跨学科能力动作词表/思维链提示与解析，纯逻辑）、
threadflow-engine（threadflow 两段式：可行域过滤 + MindNet 有效性排序与领域配额）、question-intake
（收题页/拍照手写整理/题目详情与组卷 UI）。新建 task-1..task-6，写作用域互斥：reasoning 只写
`lib/domain/services/reasoning/**` 与其测试；threadflow 写 `cloze/**`、`paper/similar_questions.dart`
与其测试；question-intake 写 `features/questions/presentation/**`、`lib/l10n/**` 与其测试；Lead 写
`data/**`、`domain/services/questions/**`、`features/questions/application/**`、docs、pubspec 并统一
提交 git。6 个 task 全部 completed（rev3），成员全程没碰 git。

**B. 题号 + 题目配图（schema v24，commit `5be9431`，19 文件）**：`questions.serial_no` 跨学科整体
编号（显示 `TR-00001`，`kQuestionSerialMinDigits=5`，超 5 位不截断）；`QuestionRepository.ingest`
同一事务里 `SELECT MAX(serial_no)` → `nextQuestionSerial` → 插入，`QuestionDraft` 不带编号（编号不是
调用方的事）；**不加 UNIQUE**（宁可重复也不丢题，append 导入撞号可接受）、号不回收（删最大号后下一题
接手）；v23→v24 迁移补两列并按 `(created_at,id)` 升序回填 1..N，`_ensureColumns` 同样自愈；
`tfpkg` 包内 `serial_no` 随包走，v23 旧包导入后事务外回填 1..N。`attachments.sort_order` 非空默认 0。
新增 `QuestionMediaStore`：磁盘 `<app support>/question_images/<questionId>/<attId>/<原文件名>`，
`rel_path` 存相对 app support 的 POSIX 路径；save 先写文件后插行、delete 先删行再删文件并收空目录；
`image_mime` 从字节魔数推 mime，拖拽与拍照两个入口共用。证据：v24_migration / question_number /
question_media_store / question_repository / tfpkg 五组测试，组合跑 6 文件 **+50**。

**C. 能力动作词表可扩展（commit `8680ec7`，4 文件）**：内置 20 个动作不变，新增
`capability_action_overlay.dart`——自定义动作 JSON 逐条校验（key 必须蛇形、trim 后非空、长度 ≤48、
不许撞内置 key、自定义之间重复"先到先得"、`labelZh` 必填）；**被拒条目不进 catalog 但保留在
overlay.customActions 里**（不静默丢用户数据）；`CapabilityActionCatalog.merge` 保证内置在前、对象
同一性、sortOrder=合并后下标、空 overlay 逐项 identical；展示兜底 `labelEn→key`、`descriptionZh→
labelZh`、`subjectHints` 只留合法 subjectKey 去重保序、`transferable`=合法 hints≥4。`parseChain` /
`ParsedChain.fromJson` 加可选 `lookup`（`CapabilityAction? Function(String)`）：注入 overlay 后自定义
动作是 `customAction`、未知动作是 `unknownActionTypes`，原始 `actionType` 永远保留；不传 lookup 与
旧版逐字节一致。结构错误文案改为「第 N 步（steps[position]，index=X）的字段」+ 实际值，`rawSnippet`
附整段 JSON，不再输出 `xxx.stuckRisk.stuckRisk` 这种重复路径。reasoning 测试 **99 例**（原基线 62）。
未做：DB 表 / provider / 编辑 UI / l10n。

**D. 错题先空 2–3 张再重现（commit `7d35bd5`，6 文件）**：用户口径「原地重复不太好」。公式
`insertIndex = clamp(currentIndex + 1 + max(gap, 2), 0, queueLength)`（`forced_loop.dart:101`
`reinsertAfter`，:112-121），gap 由调用方 `ReviewService.relearnGapCards=3` 传入
（`review_service.dart:244` 单一来源），ForcedLoop 自身不给默认值；0/1/负数一律抬到 2。队首答错
(0,5,gap3)→4、队中(1,6,3)→5、队尾不足(3,5,3)→7 夹到 5（**接队尾，下一轮马上重现**）；队列只有 1 张
连续重来；连续错两次每次至少隔 2 张。时间门语义未变：刚答错不套 10 分钟门，10 分钟门只在"答对一次
仍绑定"的第二次重现生效（`forcedRelearnMinutes` 默认 10）。cloze **+49**、anki **+110**。

**E. 找相似题融合 MindNet 有效性（commit `83fc43d`，4 文件）**：用户要「确定性模板 + 必须融合
MindNet」——不调模型，用 MindNet 读数走确定性公式。新增 `question_quality.dart`：中性 0.5 +
危险区加成 .35 + 发展区加成 .20 + `priorWeight .30 * (1-R0) * confidence`，与
`DomainBalanceRanker` 同口径（`EffectivenessTuning` 集中未标定默认值）；`SimilarQuestionFinder.rank`
加可选 `knowledgePointReadings` / `qualityTuning`，quality 只取**共用知识点**的最大值（跨学科纯动作
迁移没有共用点 → 中性，不拿无关弱点带偏榜单）；`SimilarityWeights.quality` 默认 0.0 = 显式关闭，
**默认时既有 14 例分数逐字节不变**；`components` 恒含第五键 `quality`，理由句只在权重>0 且 quality
≠0.5 时追加「MindNet 有效性 X.XX」。paper 测试 **+45**。未接线 provider（`similarQuestionsProvider`
未传 `CognitiveReadingsAdapter.readingsFor`），标定前权重保持 0。

**F. 拖拽收题 + 题号/配图 UI（commit `460ef91`，19 文件）**：`desktop_drop 0.8.4`（0.9.1 要求
Dart ^3.13.5，本机 3.13.2 装不上）。新增 `drop_intake_filter.dart`（322 行纯逻辑，不 import
dart:io）：扩展名白名单（png/jpg/jpeg/gif/webp/heic/bmp）→ 不认识看前 12 字节魔数（PNG/JPEG/GIF/
RIFF..WEBP/BMP/HEIC 品牌）→ 文件夹/0 字节/读失败/非图片各自状态；同批按 normalize 后路径去重
（Windows/macOS 忽略大小写）；非图片逐张跳过，不整批失败。`drop_intake_reader.dart` 用
`DropIntakeReader.examine(List<DropItem>)`（provider 可 override）与 `DropIntakePlatformFile`
（`xFile` 抛 UnsupportedError，避免 cross_file 依赖）。收题页整页被 `DropTarget` 包住，高亮层
「松手即可添加照片」，`_handleDrop` 有 `isCurrent` / `_picking` 防重入，读字节 → store.save →
`repository.ingest(ai_scan/raw)`，多文件合并提示（跳过非图片/重复/读不出）。**微信聊天记录**就是
OS 拖拽给的临时文件路径，app 只当普通 DropItem 读，不依赖微信 API。新增
`question_media_view.dart`：题号徽章（点击复制 + SnackBar，题库行用 `PaperCandidate` 无 serialNo 故
按 id 异步读）、首图 48×48 缩略图、点开 Dialog+InteractiveViewer 0.5–5 倍、空清单/读失败不占版面；
接入题目详情、题库列表、收题清单三处。l10n 13 个新 key 手改五文件（未跑 gen-l10n）。
presentation **117 例**（原 110 + 新 7，含拖拽 4 个 widget 用例）。

**G. 全量验证**：`dart analyze lib test` → **92 issues / 0 error / 0 warning**（= 基线）。
`flutter test --concurrency=1` 全量两遍：第一遍 **+2289 ~2 -1（07:11）**，唯一失败是
`test/features/ai/question_tools_test.dart` 断言 components 四个键，而 83fc43d 之后恒含 `quality`
（该工具没接读数、权重 0 → 恒 `kNeutralQuestionQuality`=0.5）；改断言为五键并显式检查 quality==0.5
（commit `b5ac0bf`）。第二遍（修过断言后）**+2290 ~2 All tests passed（06:45，EXIT=0）**，
全量从此以 +2290 为基线（上一轮 +2152，本轮新增 138 例）

**H. 未做 / 未验证**：真机 OS 拖拽（尤其微信聊天记录临时路径）、系统剪贴板、大图缩放均未手测；
Android 未注册 desktop_drop（桌面功能无碍）；图片只有只读展示、无增删入口，缩略图是解码整图后缩放
（未做缩略图生成）；题号未进组卷页/相似题区/闪存卡，按号搜索框未接；词表 overlay 没有 DB/provider/
编辑 UI；quality 未标定（权重 0、provider 未接线）；**导入导出生成 Word/docx 未做**（现有 `.tfpkg`
全库包与 `.kpak` 知识包，回答用户时已说明）；五个应用领域本轮未接线（下轮计划）。

**I. 下一轮计划**：①导入导出「简版 Word 卷 / 错题本」（复用 paper-composer 思路，内容取自题库 +
思维链，不调模型）；②五个应用领域逐个接线：任务排序（`thread_ranker`）、flashcard 推送/同步、纸质端
上传同步、题目搜索入库评价、智能组卷评价与资料补充；③quality 标定并接 `knowledgePointReadings`；
④题号搜索框 + 组卷页/相似题区显示题号；⑤overlay 持久化（表 + provider + 编辑页）；⑥真机验证微信拖拽。

---

## 2026-10-18 轮次一百二十：v0.5.3 发布件 —— 把「今天该做的卡」装进双端安装包（Lead）

**起点（用户指令 m30963）**：「不用了，还是建新包吧」——不要调试运行的做法，直接把上一轮
（轮次一百一十九，commit `80fc46a`）的卡组每日额度修复打成新的双端安装包。

**A. 版本**：`app/pubspec.yaml` `0.5.2+11 → 0.5.3+12`；`app/lib/core/app_info.dart` 的
`kAppVersion = '0.5.3'`、`kAppBuildNumber = 12`。patch 级：没有 schema 迁移，直接覆盖安装。

**B. 构建**（脚本 `E:\dsh-tmp-aot\release-053-build.ps1`，日志 `release-053-build.txt`）：
- 第一次尝试失败：包装脚本用 `powershell`（Windows PowerShell 5.1）跑，脚本本身是 UTF-8 无 BOM
  且含中文仓库路径，5.1 按 ANSI 读 → `Set-Location` 失败、`scripts\*.ps1` 找不到，
  两个子构建都是 `exit=-196608`（0.2s 空转）。改用 `pwsh` 并在同一进程里 `& scripts\build_windows.ps1`
  （绝对路径）后正常；同时修掉 wrapper 里 `pubspec` 空行（之前也是路径没进去的征兆）。
- Windows：`scripts/build_windows.ps1`（pub get --offline → gen-l10n → build_runner 44s/407 outputs →
  `flutter build windows --release`）**152.8s**，exit 0。产物 `furnace.exe` 91,136 bytes、
  `data\app.so` **18,924,424 bytes**（与 v0.5.2 同尺寸但 SHA-256 不同：`585F4F56…` vs `1554DA36…`，
  确认是真重建，不是缓存）。
- Android：`scripts/build_android.ps1` **207.3s**，exit 0。APK **92,151,606 bytes（87.9 MB）**；
  aapt2：`versionCode='12' versionName='0.5.3'`，minSdk 24 / targetSdk 36，label Furnace；
  apksigner：`CN=Threadflow`、证书 SHA-256 `57de8b8f…`（与 v0.5.0–v0.5.2 同一把，可覆盖安装）。

**C. 打包时发现并清掉一个调试残留**：`Release\data\flutter_assets\kernel_blob.bin`
（105,422,664 bytes）——是上一轮为了演示 `flutter run` 调试运行留在构建目录里的产物，
release 包运行不需要它。删掉后 Release 目录 27 个文件 / 44,475,882 bytes（v0.5.2 为 27 文件 /
44,377,262 bytes）。教训：同一 build 目录先跑过 `flutter run` 再打包，要检查
`data\flutter_assets\kernel_blob.bin` 是否被带进 Release。

**D. dist**：
- `dist/Furnace-0.5.3-android.apk`：92,151,606 bytes，SHA-256
  `8C9D8971FD07BA7F846C04D1A01519E161B301AE255FE55BAEA1519E099C059D`。
- `dist/Furnace-0.5.3-windows-x64.zip`：19,422,508 bytes（34 entries），SHA-256
  `6C46A7D22C5FB33AD8D9919ADA60DB3F701982490532B2C91550A8012CE12538`。
- 删掉 v0.5.2 三件（apk / zip / RELEASE-v0.5.2.md）与 dist 里误留的
  `Furnace-0.5.2-windows-x64` 解压目录；重写 `dist/RELEASE-v0.5.3.md`（下载表、额度修复说明、
  验证数字、已知未做）。
- 解压到 `E:\FirsryOS\THREADRIPPER\Furnace-0.5.3-windows-x64\` 并冒烟：`Start-Process furnace.exe`
  → pid 16484、标题 `Furnace`、Responding=True、WorkingSet 285.7 MB；exe 版本资源 `0.5.3+12`。
  顺手删掉旧的 0.5.0 / 0.5.1 / 0.5.2 解压目录，只留 0.5.3。

**E. 验证**：`flutter test test/core/app_info_test.dart` → +2 通过（版本常量与 pubspec 一致）；
`dart analyze lib test` → **92 issues（0 error / 0 warning）**；全量测试已在轮次一百一十九跑过
**+2152 ~2 All tests passed**，本轮只改版本常量（`app_info_test` 复核），未再重跑全量。

**F. 没做 / 限制**：Windows 仍无安装器、无代码签名；本轮不再重复构建之外的清理
（build 目录保留，方便下次增量构建）。


## 2026-10-18 轮次一百一十九：闪存卡只看「今天该做的卡」—— 卡组每日新卡/复习额度真正生效（Lead）

**起点（用户反馈）**：「我设置了卡组，但是闪存卡那里还是所有卡片放到一起背。应该只显示今日任务。」

**A. 先看真机数据（只读副本，不碰用户库）**：把
`C:\Users\firsr\AppData\Roaming\FirsryFan\Furnace\furnace.db` 复制到
`E:\dsh-tmp-aot\furnace-live2.db` 后查：`knowledge_points` 269、`tags` 133、
`object_tags` 269（0.5.2 的一键归组之后已全部挂上，未挂标签 0）、
`review_group_plans` 1 行（`生物/高中生物`，每天新卡 15、复习 15，覆盖全部 269 张）、
`review_logs` 21 条（今天 16）、`card_states` 913 条（repetitions 0 的 898 条、1 的 12 条、2 的 3 条，
`due_at` 全是 NULL）——也就是说 269 张卡全是「新卡」，队列自然把 269 张全端上来。

**B. 根因（旧行为）**：`newCardsPerDay` 从来没有参与队列；`reviewCardsPerDay` 只在
「复习额度用尽」时压制**从未见过**的单元（docs/PROGRESS.md:3970 轮次十七的原话，
旧 `test/features/anki/review_plan_cap_test.dart` 锁的就是这条）。所以设了 15/15 也等于没设。

**C. 新语义（今日任务=额度，逐项扣）**：
- `newRemaining = max(0, newCardsPerDay - 今天首次出现的知识点数)`，**0 就是今天不学新卡**；
- `remainingReviews = reviewCardsPerDay == 0 ? null（不限） : max(0, reviewCardsPerDay - 今天在「以前见过」的卡上的复习次数)`；
- 队列按模型优先级遍历到期项，每一项对**覆盖它的每个已配置卡组**扣对应额度，任一卡组该桶为 0 就剔除这一项；
  嵌套卡组必须都有余量才放行；
- 答错后的强制重来（annotation 17）不占额度、也不受限；
- 没有任何标签属于已配置卡组的卡、以及完全没有计划时，一律不限量（与以前一致）。

**D. 实现**：
- `app/lib/data/repositories/anki_repository.dart` 新增
  `knowledgePointsFirstReviewedSince(int sinceMillis, {Iterable<String>? knowledgePointIds})`
  → `Set<String>`（`MIN(reviewed_at) GROUP BY knowledge_point_id HAVING first_at >= ?`），
  用于区分「今天才第一次出现」和「以前见的」。
- `app/lib/data/repositories/review_plan_repository.dart`：`ReviewGroupLoad` 换成
  `newDoneToday / reviewDoneToday / newRemaining / remainingReviews`，`newCardsAllowed => newRemaining > 0`；
  `ReviewDayLoad.reviewExhaustedGroups` 改为 `remainingReviews == 0`；`loadDay` 用上面的 firstReviewed 拆分两次计数。
- `app/lib/features/anki/application/review_service.dart`：`buildQueue` 增加 `_GroupBudget`
  （`memberPaths / newRemaining / reviewRemaining?`）与 `_takeAllowance(..., {required bool isNew})`，
  删掉旧的 `_isUnseenDraw` 压制逻辑。「是不是新卡」按知识点是否已有过任何作答判断
  （`states.any((s) => s.repetitions > 0)`），不是看 `item.isNew`——自由填空会给旧卡新开一个空位，
  `item.isNew` 会是 true，按它扣会把复习当新卡。
- `app/lib/features/anki/presentation/review_plan_page.dart`：卡组卡显示「今天还剩新卡 N / 复习 N」，
  提示按三种状态给（新卡额度用完 / 复习额度用完 / 额度还没用完）。
- l10n（zh/en）：`reviewPlanZeroIsUnlimited` 改写（0 新卡=今天不学新卡；0 或空复习=不限；答错的卡仍会回来）、
  `reviewPlanNewCardsNormal` / `reviewPlanNewCardsStopped` 改写，新增 `reviewPlanReviewsStopped`、
  `reviewPlanNewRemaining(count)`；`flutter gen-l10n` exit 0。

**E. 测试**：`app/test/features/anki/review_plan_cap_test.dart` 重写成 6 例
（新卡额度 1 → 队列只有 1 张；复习额度 1 → 只放 1 张；新卡 0 → 一张新卡都不出现；
答错仍回来；不在任何卡组的卡不限；没有计划时队列与以前完全一致）；
`test/data/repositories/review_plan_repository_test.dart` 的计数断言改成新语义
（`newDoneToday` / `reviewDoneToday` / `newRemaining` / `remainingReviews`）；
`test/features/anki/review_plan_page_test.dart` 保持绿。
定向 `flutter test test/features/anki test/data/repositories test/features/settings test/features/questions`
→ **+396 全绿**；全量 `flutter test --concurrency=1` → **+2152 ~2 All tests passed**
（上一轮基线 +2150，差值 2 = `review_plan_cap_test` 从 4 例重写成 6 例；
日志 `E:\dsh-tmp-aot\fulltest-053.txt`）；`dart analyze lib test` → **92 issues（0 error / 0 warning）**，
与上一轮基线相同。

**F. 没做 / 副作用（诚实清单）**：
- 被额度挡下的卡在构造队列时仍会为它新开一个空白位（`unitKey: c0`）的 `card_states` 行
  （`due_at` 为 NULL）——不影响明天再抽，但确实多一行；没有为此重构队列的「先排序后建项」。
- 额度只在卡组维度生效：卡属于多个已配置卡组时每个卡组都要有余量（这是刻意的，避免嵌套卡组互相超发）。
- 答错的强制项绕开额度（annotation 17 设计不变），所以「0 新卡」的日子仍可能因错题回到队列。
- 本轮不构建 release 包（用户 m30529：「你不用每一次都构建完整的 release 包」）。


## 2026-10-18 轮次一百一十八：v0.5.2 发布件 —— 把卡组接口装进双端安装包（Lead）

**起点（用户指令）**：用户上一轮反馈工具面接不上卡组（269 张卡、133 个标签、`object_tags` 全空，
但每张卡的 `source` 里写着完整标签路径），轮次一百一十七（commit `b9320ef`）补了四个接口
（read 侧的 tags/untagged/linked_flashcards/kind=review_plan，write 侧的 `link_card_tags` /
`manage_review_plan` / `create_knowledge_cards.tags`），但那些改动只在源码里，用户装的是 v0.5.1。
本轮把它们装成 **v0.5.2**，dist 只留最新版。

**A. 版本**：`app/pubspec.yaml` `0.5.1+10 → 0.5.2+11`；`app/lib/core/app_info.dart` 的
`kAppVersion = '0.5.2'`、`kAppBuildNumber = 11`。patch 级：没有 schema 迁移，直接覆盖安装。

**B. 构建**（脚本 `E:\dsh-tmp-aot\release-052-build.ps1`，日志 `release-052-build.txt`）：
- 前置：`flutter pub get --offline` exit 0（16:22:35）；`flutter gen-l10n` exit 0；
  `dart run build_runner build --force-jit` exit 0（30s，223 outputs）。
- 预置 sqlite tarball（3,258,980 bytes，来自 `E:\knowflow\...` 缓存）到
  `build\windows\x64\_deps\sqlite3-subbuild\sqlite3-populate-prefix\src\`，见 `docs/DEPLOY.md` §4.1-A。
- **Windows**：这次不做手动 cmake configure（上一次的 110s 成功证明干净目录直接构建即可；
  手动 configure 在未生成 `windows\flutter\ephemeral\generated_config.cmake` 时会失败）。
  `flutter build windows --release` 16:23:14 → 16:24:35，**81s**，exit 0。
  产物 `furnace.exe` 91,136 bytes、`data\app.so` **18,924,424 bytes**。
- **Android**：`scripts/build_android.ps1`，16:24:35 → 16:26:28，**113s**，exit 0。
  APK 92,167,990 bytes（87.9 MB）；aapt2：`package com.furnace.app versionCode='11'
  versionName='0.5.2'`，minSdk 24 / targetSdk 36，label Furnace；apksigner：
  `CN=Threadflow`、证书 SHA-256 `57de8b8f…`（与 v0.5.0/v0.5.1 同一把，可覆盖安装、数据保留）。

**C. 打包与 dist**
- `dist/Furnace-0.5.2-android.apk`：SHA-256
  `B64A411C7FB8A656CAFE393D06C2FA705D4DD5025768D4389588628634B69C84`。
- `dist/Furnace-0.5.2-windows-x64.zip`：19,427,258 bytes（34 个条目，根目录含 `furnace.exe` 与
  `data/`），SHA-256 `271C220801DDA519228EC5FEC263631774817A7B3FC615FB3C1B1D322567E756`。
- 删掉 dist 里 0.5.1 三件（apk / zip / `RELEASE-v0.5.1.md`），dist 只留 0.5.2 两个安装包 +
  `RELEASE-v0.5.2.md`（约 106 MB）。旧版本在 GitHub Release 上仍然可下载（发布历史已核查过）。

**D. 验证**
- 全量 `flutter test --concurrency=1`（版本号改后重跑）：**+2150 ~2 All tests passed**，exit 0。
- `dart analyze lib test`：**92 issues，0 error / 0 warning**。
- `test/features/ai` 目录：**452 例全绿**（卡组接口的新测试都在里面）。
- Windows 冒烟：`Start-Process Release\furnace.exe` → pid 9768、标题 **Furnace**、
  Responding=True、工作集 302.1 MB，随后关闭。
- **在用户库副本上试算**（`E:\dsh-tmp-aot\match_trial.py`，只读复制 `furnace.db` 到
  `furnace-live.db`）：`knowledge_points=269`、`tags=133`、`object_tags(kp)=0`；按
  `from_source_paths` 的同一套匹配规则，**269 张全部唯一命中（exact），0 歧义、0 匹配不到，
  分布在 78 个卡组**。这说明用户升级后先 `dry_run` 预览、再 `dry_run: false` 一次即可归完，
  不需要逐张点。本轮**没有写用户的真实库**，批量归组应由应用里的 AI 对话执行。

**E. 没做 / 限制（诚实清单）**
- 这一版**没有新的归组界面**：批量归组、建卡组、设每日计划都只能在 AI 对话里完成；卡组设置页
  仍是上一版入口（设置 → 卡组设置）。
- 匹配只读 `source` 最后一个「｜」之后的文本；来源没写路径的卡只会进 `unmatched`，不猜。
- 归组后不会自动设每日目标（可再调 `manage_review_plan`，但设多少由用户决定）。
- Windows 仍无安装器 / 代码签名；APK 未上架应用商店。
## 2026-10-18 轮次一百一十七：AI 能自己把卡归组了 —— 补齐卡组/标签/每日计划接口（Lead）

**起点（用户现场反馈）**：用户实测「读这一侧 `query_content(kind: flashcard)` 的返回字段仍然只有
id / title / source / card_count，没有 tags；目标标签「第1节 细胞是生命活动的基本单位」的
`linked_objects` 仍然是 0；写这一侧 `create_knowledge_cards` 仍然只有标题/正文/来源/卡片四个参数，
没有标签；工具清单里也没有任何'给闪存卡挂标签 / 建卡组 / 设每日计划'的接口」。他的库里 **269 张
闪存卡、114 个标签、`object_tags` 0 行**，而每张卡的 `source` 里其实都写着完整标签路径
（如 `…｜生物/高中生物/必修1 分子与细胞/第1章 走近细胞/第1节 细胞是生命活动的基本单位`）——
归属信息在文本里，但没有任何工具能把两边接上。用户明确说「不会用猜的参数去试——被静默忽略就会往
库里再塞一批重复卡，反而要再删一遍」，所以这一轮不是解释现状，是把接口补到能一次调用批量归组。

**A. 读侧（`app/lib/features/ai/tools/content_query_tools.dart`）**
- `kind: flashcard` 每行新增 `tags`（`[{id, name, path}]`）、`tag_count`、`untagged`——模型终于能
  看到"这张卡属于哪些卡组"，也能一眼看出还有多少张散卡。
- `kind: tag` 新增 `linked_flashcards`：只数 `object_type = 'knowledge_point'` 的关联，不把题目、
  材料等其它对象算进卡组（卡组本来就是标签，但"标签挂了多少张卡"必须按对象类型分开数）。
- 新增 `kind: review_plan`：`items` 是已配卡组的每日目标（`tag_id` / `tag_path` /
  `new_cards_per_day` / `review_cards_per_day`），顶层另给 `total_flashcards`、
  `ungrouped_flashcards` 与一句 `note`（0 = 不限量）。模型设计划前先看现状，不用猜。
- 工具构造从 `QueryContentTool(db, anki, tags)` 变为 `QueryContentTool(db, anki, tags, plans)`，
  `plans` 是 `ReviewPlanRepository(db, anki)`。

**B. 写侧（新文件 `app/lib/features/ai/tools/card_group_tools.dart`，755 行）**
- `link_card_tags`：两种用法。① 显式 `tag` + `card_ids`（先校验每个 id 都存在，缺一个整单失败，
  不写一半）；② `from_source_paths: true` 扫描还没进任何卡组的卡，从 `source` 最后一个「｜」
  （或半角 `|`）之后的文本取路径，与已有标签路径做匹配。`dry_run` 默认 **true** 只预览，
  `dry_run: false` 才写库；`limit` 默认 50、上限 500，扫不完如实报 `remaining`。
- 匹配规则（`_matchTagPath`）三层，**顺序即优先级**：① 全路径精确相等；② 标签路径是来源路径的
  段级尾部（来源写得深、标签建得浅时命中，取段数最多者，同深才算歧义）；③ 来源路径是某个更深
  标签路径的段级尾部（来源只写某一级时，若只有**一个**标签能解释它就用，≥2 个如实报
  `ambiguous` 并列出候选，不猜）。匹配不到的单列 `unmatched` 带原因，不静默跳过。
- `manage_review_plan`：`action: set/clear`。`set` 要求 `new_cards_per_day` 与
  `review_cards_per_day` 都是 >= 0 的整数（负数报错），标签可用 id 或完整路径；`clear` 删掉该
  卡组的计划行。`before_json` 存旧计划（没有则 `plan: null`），撤销时恢复旧行或删掉本次首设。
- 撤销函数（导出给 `agent_loop`）：`unlinkCardTags(db, snapshot)` 按 `after_json.links` 删本次建的
  `object_tags` 行；`restoreReviewPlan(db, snapshot)` 恢复 `before_json` 里的计划。
- 公共解析函数 `resolveTagForTool(tags, raw)`：先 id、再完整路径、再名字精确、最后忽略大小写；
  重名时报错并列出各条完整路径（不替用户选）。
- `create_knowledge_cards`（`tools/knowledge_tools.dart`）新增 `tags` 参数（id 或完整路径，可多个）：
  **建任何东西之前先把所有标签解析完**，未知/歧义整单失败——这正是回应"参数被静默忽略"的顾虑；
  建完后逐张调 `addTagToObject(objectType: 'knowledge_point')`。撤销 `deleteCreatedKnowledgeCards`
  现在会先删 `object_tags` 再删知识点，否则撤销会留下指向不存在卡片的关联行。

**C. 接线（`domain/tool_registry.dart` / `domain/agent_loop.dart`）**
- `ToolRegistry.forApp`：新增 `final reviewPlans = ReviewPlanRepository(db, anki);`，
  注册 `LinkCardTagsTool`、`ManageReviewPlanTool`，`CreateKnowledgeCardsTool(anki, tags)`，
  `QueryContentTool(..., plans: reviewPlans)`。内置工具 **19 → 21 个**。
- `agent_loop`：`_isCreate` 认 `link_card_tags`（撤销走删除新建关联），`_deleteCreated` 加
  `unlinkCardTags`，`_undo` 加 `manage_review_plan → restoreReviewPlan`；系统提示规则 4 补一句
  "挂卡组/设每日计划用 `link_card_tags` 与 `manage_review_plan`，批量前先 `dry_run` 预览"。

**D. 证据**
- 新测试 `app/test/features/ai/card_group_tools_test.dart` 24 例：标签解析（id/路径/名字/重名/未知）、
  显式挂（计数、幂等、未知卡 id 整单失败）、source 批量（dry-run 不写、写入、二次只扫未分组、
  真正并列歧义被报出而不是猜、来源只写一级能唯一命中更深标签、limit 截断与 remaining、无标签报错
  并指向 `create_tags`）、撤销（`unlinkCardTags` 只删本次、`restoreReviewPlan` 恢复旧行/清掉首设）、
  设计划（set 快照"原本没有"、负数拒绝、clear、缺参数报错）、读侧新字段（tags/untagged/tag_count、
  review_plan 的 items + 顶层统计）。
- 新测试 `app/test/features/ai/card_group_loop_test.dart` 3 例：经 `AgentLoop` 执行 `link_card_tags`
  后 `undoExecuted` 真的把 `object_tags` 清空（验证 `_isCreate`/`_deleteCreated` 接线）、dry-run
  不产生撤销快照、`manage_review_plan` 经循环执行后撤销能把首次计划删干净。
- `test/features/ai/knowledge_tools_test.dart` 18 例：新增三例——建卡时挂标签并回报路径、未知标签
  在建卡前失败且库为空、`deleteCreatedKnowledgeCards` 同时清掉 `object_tags`。
- 定向：`flutter test test/features/ai` → **+452 全绿**。
- 全量：`flutter test --concurrency=1` → **+2150 ~2 All tests passed**（上一轮基线 +2120 ~2，
  差值 30 = 24 + 3 + 3，全部是本轮新增用例）。
- `dart analyze lib test` → **92 issues，0 error / 0 warning**（顺带清掉一条既有 info：
  `test/features/ai/ai_settings_page_test.dart` 的 `MaterialApp` 加 `const`）。
- 文档：`docs/AI_DESIGN.md` §4.1 工具表从"11 个（2026-10-12）"更新为 21 个并补一行只读数量
  （7 → 12），另加一段 2026-10-18 的缺口说明与四个接口的用法。

**E. 没做 / 限制（诚实清单）**
- 批量匹配只读 `source` 里最后一个「｜」之后的文本；如果某张卡的 source 根本没写路径，它只会进
  `unmatched`，不会被"猜"进任何卡组。
- 歧义一律不猜：同一路径能对上多个标签时，工具报告候选而不是替用户选（用户的库有 114 个标签，
  同名的父子层级很常见）。
- 本轮只补接口，**没有替用户跑他的 269 张卡**——`dry_run` 预览归组结果应由他在对话里确认后再写；
  也没有替他设每日计划（那是他的学习节奏）。
- `link_card_tags` 一次最多 500 张（`limit` 上限），超过要分次；卡组设置仍只在 `review_plan` 里
  可见，本轮没改 UI。
## 2026-10-18 轮次一百一十六：v0.5.1 发布件 —— 把卡组修复与入口重设计装进双端安装包（Lead）

**起点（用户指令）**：用户此前要求「删掉旧版本，同时生成新版本软件，我放 release」；轮次一百一十四
（旧卡归组 / 新建卡选卡组）与轮次一百一十五（题库入口重设计）的改动此前只在源码里，用户装的是
v0.5.0。本轮把它们装成 v0.5.1，dist 只留最新版。

**A. 版本**：`app/pubspec.yaml` `0.5.0+9 → 0.5.1+10`；`app/lib/core/app_info.dart` 的
`kAppVersion = '0.5.1'`、`kAppBuildNumber = 10`（`kAppUserAgent` 跟随）。patch 级：没有 schema
迁移，直接覆盖安装。

**B. 构建**（脚本 `E:\dsh-tmp-aot\release-051-build.ps1`，日志 `release-051-build.txt`）：
- 前置：`flutter pub get --offline` exit 0；`flutter gen-l10n` exit 0（轮次一百一十二修过 arb
  模板，生成器现在可跑）；`dart run build_runner build --force-jit` 79s / 854 outputs。
- Windows：先把 sqlite tarball（`sqlite-autoconf-3520000.tar.gz`，3,258,980 bytes，复用
  `E:\knowflow` 的同版本缓存）预置到
  `build\windows\x64\_deps\sqlite3-subbuild\sqlite3-populate-prefix\src\`。随后**手动 cmake
  configure 失败**：`CMake Error at flutter/CMakeLists.txt:7 (include): include could not find
  requested file: ...windows/flutter/ephemeral/generated_config.cmake` —— 该文件要 flutter 工具先
  prepare 才生成，手动 configure 拿不到；失败那次只把 generator 写进了缓存。改回
  `flutter build windows --release` 一次成功（110.0s），install 没有再往 `C:/Program Files` 写
  （轮次一百一十三那个 CMakeCache 坑在干净 build 目录下没有复现）。产物：`furnace.exe` 91,136；
  `data/app.so` **18,875,272 bytes**（v0.5.0 是 18,826,120）。
- Android：`scripts/build_android.ps1`，Gradle **150.5s**，APK **91,971,382 bytes（87.7MB）**，
  签名 `CN=Threadflow`、证书 SHA-256 `57de8b8f…`（与 v0.5.0 同一把钥匙，可覆盖安装）；aapt2：
  `com.furnace.app` versionCode **10** / versionName **0.5.1**，minSdk 24 / targetSdk 36，label
  Furnace。

**C. dist**：删除 0.5.0 的三件（apk / zip / `RELEASE-v0.5.0.md`；GitHub Release 上的 v0.5.0 仍在），
只留：
- `Furnace-0.5.1-android.apk` 87.71MB，SHA-256 `0DEAD6301A33A73427E8B1DF474BFA08C4FED661CB802817E3F3AC399A7417A1`
- `Furnace-0.5.1-windows-x64.zip` 18.51MB，SHA-256 `1BF3E8CEF7D63F8E638160B43207F70516955C05D5FC420840824C217010AC5D`
- `RELEASE-v0.5.1.md`（4,229 bytes：下载表 / 修了什么 / 验证 / 已知未做）

dist 3 文件 106.2MB。

**D. 验证**：全量 `flutter test --concurrency=1` → **+2120 ~2 All tests passed**（版本号改后重跑；
`app_info_test` 与 `about_page_test` 都在里面）；`dart analyze lib test` → **93 issues，0 error /
0 warning**；Windows 冒烟：dist zip 解压到 `E:\FirsryOS\THREADRIPPER\Furnace-0.5.1-windows-x64\`，
`Start-Process furnace.exe` → pid 15324、标题 `Furnace`、Responding、287MB。

**E. 没做的**：Windows 没有安装器与代码签名（SmartScreen 会拦一下），dist 只留最新版（旧版在
GitHub Release），没有自动更新。tag `v0.5.1`。

---

## 2026-10-18 轮次一百一十五：入口重设计 —— 题库成为顶层目的地、设置页收敛、知识页顶栏收进菜单（Lead）

**起点（用户指令）**：用户 m29290「还有很多功能，比如知识库、新建题目、题库总览之类的功能，请你重新设计其入口」；
用户 m29307「你的 UI 设计布局有很多可以提升的地方，请先简单修改，不要有显著问题即可」。

**A. 问题**：题库的四个入口（收题 / 组卷 / 拍照整理 / 材料入库）此前各占设置页一行，把设置页
撑成功能清单，而「题库总览」本身**没有页面**；知识页 AppBar 五个图标平铺、没有主次；底部导航
7 个项目在手机宽度下全标签会挤。

**B. 题库成为顶层目的地**：`home_shell.dart` 的 `shellDestinations` 在「闪存卡」之后插入
`destination('questions', l10n.navQuestions)`，`pages` 同步插入 `QuestionBankPage`；索引相关全改：
`_settingsIndex => aiConfigured ? 7 : 6`、Ctrl+0 的 `onInvoke` 同步、新增 `Ctrl+5 → _GoToTabIntent(4)`
（注释说明题库和 Ctrl+1..4 一样钉在固定位置）。手机 `NavigationBar` 增
`labelBehavior: onlyShowSelected`（8 项全标签挤不下；桌面 rail 仍全标签）。图标槽位加
`'questions'`（`app_icons.dart` 的 slots / slotDefaults `'quiz'` / objects 分类 / catalog、
`icon_picker_page.dart` 的 `slotLabel`），`test/core/theme/app_icons_test.dart` 的固定槽位表同步 +1。

**C. 新题库页** `app/lib/features/questions/presentation/question_bank_page.dart`（~330 行，只读）：
数据复用 `paperCorpusProvider` + 新增的 `questionStemsProvider`（`readQuestionStems` 读全表，
`watchDatabaseRevision`；AI 工具那条路仍只传 ids），**不新增第二套读表口径**。内容：四个加题入口
（收题 / 组卷 / 拍照整理 / 材料入库）→ 统计卡（`共 N 道题 · M 个学科`，空库时给引导）→ 学科
`ChoiceChip` 筛选 → 行（题干 + 学科 · 来源分级 · 知识点数）→ 点进 `QuestionDetailPage`；
下拉刷新 `invalidate` 两个 provider。

**D. 设置页收敛**：删掉收题 / 组卷 / 拍照整理 / 材料入库四个 `ListTile` 与四个 import，改成
一个「题库」条目（`settingsQuestionBankHint`）→ `QuestionBankPage`。

**E. 知识页顶栏**：五个 `IconButton` → 2 个常用（复习偏好、复习计划）+ `PopupMenuButton`
「更多」（线索边 / 洞察 / 今日清单，`enum _KnowledgeMoreAction`）。理由写在代码注释里：
"看数据"类不是复习流程每轮都要点的东西。

**F. l10n**：新增 `navQuestions`、`knowledgeMoreActions`、`settingsQuestionBankHint`、
`questionBankRefresh/Failed/Empty/EmptyHint/Intro/Summary/AllSubjects/NoMatch/Untitled/PointCount`
共 13 个 key（zh/en），`flutter gen-l10n` 重新生成三个 dart（不再手改生成文件）。

**G. 证据**：新增 `test/features/questions/presentation/question_bank_page_test.dart` 5 例
（空态四入口、列表/统计/学科筛选真的过滤、点行进详情、组卷入口、`shellDestinations` 纯函数
7 项且题库紧跟闪存卡）；`test/app/home_shell_narrow_test.dart` 1 例（390×844 底部导航渲染
7 个 `NavigationDestination`、点 quiz 图标进题库）；`test/core/theme/app_icons_test.dart` 槽位表 +1；
回归 settings / anki / app → 全绿；全量 `flutter test --concurrency=1` → **`+2120 ~2`**
（轮次一百一十三基线 +2107，差值 13 = 卡组 7 + 题库 5 + 窄屏 1）；`dart analyze lib test` →
**93 issues（0 error / 0 warning）**。

**H. 没做（诚实清单）**：① 知识库仍是导航一级页（`FEATURE_MATRIX.md` 的 D4/R5 未决，这一轮没动）；
② 手机端八项是现有信息架构的边界，没做"更多"折叠（那要先决定哪一项进折叠）；
③ 题库页只读——改题仍在题目详情页，页内不做编辑；④ 拍照整理的主入口仍是待整理队列页，
题库页只是多了一条路。

**I. 文档**：`docs/QUESTION_BANK_DESIGN.md` §6 补入口说明、§10 诚实清单第 4 条改为已解决。

---

## 2026-10-18 轮次一百一十四：旧卡没有卡组 —— 把"看不见的卡"补进卡组，新建卡时就能选卡组（Lead）

**起点（用户反馈）**：用户 m29052「现在软件里面有一些旧的 flashcard 没有设置『卡组』，可能是我现在
没看到『一天多少个卡』的设置的原因」。

**A. 先取证**：把活动库 `C:\Users\firsr\AppData\Roaming\FirsryFan\Furnace\furnace.db` 复制到
`E:\dsh-tmp-aot\furnace-copy.db` 后用脚本查：`knowledge_points` **269**、`card_templates` **644**、
`tags` **133**、**`object_tags` 0 行**、`review_group_plans` **0 行**。⇒ 269 张卡一张标签都没挂，
而卡组*就是*标签、每日任务量按卡组设 ⇒ 它们不属于任何卡组，计划页自然是空的，旧卡永远落在
任何每日配额之外（不是"不限量"，是"不在范围内"）。设计口径见轮次十七（`review_plan_page.dart`
与 `docs/FRONTEND.md` 的卡组说明）。

**B. 仓储**（`app/lib/data/repositories/tag_repository.dart`，object_tags 的写者仍只有这一个）：
`countKnowledgePointsWithoutTags()`、`knowledgePointIdsWithoutTags()`（共用
`NOT EXISTS` 子查询，注释说明为什么不用 `LEFT JOIN ... IS NULL` 的假重复）、
`tagKnowledgePointsWithoutTags(tagId)`（未知标签抛 `ArgumentError`；批量
`InsertMode.insertOrIgnore`，调两次不会重复、第二次返回 0）。

**C. 卡组设置页**（`review_plan_page.dart`）：新的 `ungroupedKnowledgePointsProvider`
（`watchDatabaseRevision`）与 `_UngroupedCardsCard`——「有 N 张卡还没有卡组」+「把它们归到一个
卡组」；归组后 snackbar 报数并**立刻打开**那个卡组的每日任务量编辑器（归组只是半个闭环，
设完任务量才算完）；计划为空的空态补一个「添加卡组任务量」按钮（此前只有一段文字）；抽
`_sortedTags` / `_pickTag` / `_tagLabel` 给两处选标签复用。

**D. 新建卡就能选卡组**（`anki_manage_page.dart`）：新建知识点弹窗加「卡组（标签）」下拉
（`DropdownButtonFormField(initialValue: ...)`，`''` = 「不设置（散卡）」），保存后若有选中
就 `addTagToObject`。

**E. l10n**：`reviewPlanUngroupedTitle(count)` / `Body` / `Action` / `Done(count,tag)`、
`ankiCardGroup` / `ankiCardGroupNone`；`docReviewBody`（使用文档）补上"没有挂标签的旧卡不属于
任何卡组、卡组设置页会给一键归组、新建卡时也能选"。

**F. 证据**：新增 `test/data/repositories/tag_repository_test.dart` 4 例（0/2 计数、归组后清零、
二次归组返回 0、未知标签抛错）；新增 `test/features/anki/review_plan_page_test.dart` 3 例
（未分组提示与空态按钮、一键归组后出现每日任务量编辑器且库里 1 行 plan / 2 行 object_tags、
无标签时提示先去建标签）；定向 settings+anki 回归全绿；全量 **`+2120 ~2`**；analyze **93 issues
（0 error / 0 warning）**。

**G. 没做（诚实清单）**：① 只支持"全部未分组卡归到同一个标签"，不提供逐张归组/多标签归组；
② 归组后不自动设每日目标（打开编辑器让用户自己填，默认仍是"不限"）；③ 已经手工挂过标签的卡
按"有卡组"算，不检查它挂的标签是否看起来像学科。

---

## 2026-10-18 轮次一百一十三：v0.5.0 发布件 —— 删旧版、双端重编、发布说明（Lead）

**起点（用户指令）**：「删掉旧版本，同时生成新版本软件，我放 release」。

**A. 版本号：0.4.2+8 → 0.5.0+9**

依据：v0.4.2 之后累计 **95 commits / 246 files / +94,852 −7,825**、88 个 feat；测试 1081 → **2107**；
schema **9 → 23**；AI 工具 **11 → 19** —— 按语义化版本升 minor。改动：`app/pubspec.yaml:4`
`version: 0.5.0+9`、`app/lib/core/app_info.dart:11/15` 的 `kAppVersion` / `kAppBuildNumber`（`app_info_test`
比对 pubspec 与 UA，全量里通过）。Windows 版本资源由 `windows/runner/Runner.rc` 的 FLUTTER_VERSION 宏从
pubspec 取，Android 的 versionCode/versionName 由 `android/app/build.gradle.kts` 从 flutter 读，都无需手改。

**B. Android：一次过**

`scripts/build_android.ps1`（ASCII junction + 镜像 init + apksigner 实测校验）：Gradle **413.6s**，
`app-release.apk` **91,774,654 bytes（87.5 MB）**，SHA-256 `8E3A0CFD595AA7606F74718BAA500B5553D606D68ADE5B9ED2A7A0F0D6AE8430`。
`aapt2 badging`：`com.furnace.app`，versionCode **9** / versionName **0.5.0**，minSdk 24 / targetSdk 36，
权限 INTERNET / POST_NOTIFICATIONS / RECEIVE_BOOT_COMPLETED / VIBRATE；`apksigner`：`CN=Threadflow`，
证书 SHA-256 `57de8b8f…`——与 v0.4.2 的 APK 同一把，**可覆盖安装、数据保留**。

**C. Windows：两个坑，修好后才拿到产物**

1. `sqlite3_flutter_libs` 的 FetchContent 下载 `sqlite.org/2026/sqlite-autoconf-3520000.tar.gz` 报
   `status_string: "Failure when receiving data from the peer"`。把同版本 tarball（**3,258,980 bytes**，
   来自 `E:\knowflow\app\build\windows\x64\_deps\...\sqlite3-populate-prefix\src\`）预置到 junction 的
   `build\windows\x64\_deps\sqlite3-subbuild\sqlite3-populate-prefix\src\` 后跳过下载
   （该 URL 没有 HASH 参数，CMake 见文件已存在就直接用）。
2. 编译通过，但 INSTALL 想写 `C:/Program Files/furnace`：`cmake_install.cmake:90 (file) file cannot create
   directory` → `MSB3073 ... INSTALL.vcxproj`。根因是 `build\windows\x64\CMakeCache.txt` 的
   `CMAKE_INSTALL_PREFIX` 停在默认值，而 `windows/CMakeLists.txt:65-70` 期望 `$<TARGET_FILE_DIR:furnace>`。
   删掉 CMakeCache 用 Flutter 同一组参数重新 configure 后 cache 正确，再 `flutter build windows --release`
   **18s** 完成 build + install。

产物：`furnace.exe` 91,136 bytes、`data\app.so` **18,826,120 bytes**（18.0 MB）、Release 目录共
**44,377,262 bytes（42.3 MB）**。启动冒烟（Start-Process → 10s）：进程存活、窗口标题 `Furnace`、
`Responding=True`、工作集约 287 MB。

顺手两处：`scripts/build_windows.ps1` 不再无条件 `flutter create`（只在 `windows\CMakeLists.txt` 缺失时跑），
否则每次构建都会改掉 `app/.metadata`；本次构建造成的 `.metadata` android→windows 漂移已回退。

**D. 打包与删旧版**

- `dist/Furnace-0.5.0-android.apk`（91,774,654 bytes）与 `dist/Furnace-0.5.0-windows-x64.zip`
  （19,381,974 bytes，zip 根就是 `furnace.exe` / `data/` / 各 dll）；zip SHA-256
  `6FA3CA763867BBF88542035A96586F69755D95EFAB634473EA09E9276BD3F2BB`
- 新写 `dist/RELEASE-v0.5.0.md`（照 v0.4.2 模板：下载表 / 这一版是什么 / 五个主题 / 验证 / 已知未做）
- 删掉 v0.3.1、v0.4.0、v0.4.1、v0.4.2 的 apk + zip 与 4 份旧 RELEASE md：**15 files / 507.5 MB → 3 files / 106.0 MB**
  （−401.5 MB）。GitHub Release 里 v0.1.0–v0.4.2 的 assets 都还在（API 核查过），本地删掉不丢历史。

**证据**：全量 `flutter test --concurrency=1` → **`+2107 ~2` All tests passed**（v0.4.2 基线 1081，本版多 1026 条）；
`dart analyze lib test` → **93 issues（0 error / 0 warning）**；`flutter test test/core/app_info_test.dart` → `+2` 绿；
APK 元数据/签名都是 `aapt2`/`apksigner` 从真实产物读出来的。本提交打 tag `v0.5.0`。

**诚实**：Windows 构建仍依赖网络（除非像这次一样预置 sqlite tarball）；CMakeCache 为何停在默认 prefix
没有完全定位，只是删 cache 重建解决了（已写进 `docs/DEPLOY.md` §4.1）；Windows 端没有安装器、没有代码签名；
exe 只做「能启动、窗口在、能响应」的冒烟，没有逐屏点过；`dist/` 是 gitignore 的本地发布素材，
发布说明也不进 git，需要手动传到 GitHub Release。

---

## 2026-10-18 轮次一百一十二：精简 —— 5.85 GB 可再生物归零、28 个死 key、组卷装配只留一份（Lead）

**起点（用户反馈）**：「精简一下项目代码，占用空间有点大，应该还有可以优化的逻辑等等」。

**A. 空间：先量再删**

清理前 `class-productivity` 全目录 **6,276.5 MB / 10,807 files**，源码只占 7.9 MB（`app/lib` 4.5 + `app/test` 2.2 +
`docs` 1.2）；其余是 `app/build` 5,184.6 MB、`app/.dart_tool` 368.1 MB、`app/windows/flutter`（ephemeral 生成物）
261.6 MB、`app/android/.gradle` 21.6 MB、`dist` 401.5 MB、`.git` 30.9 MB —— **大头全是可再生的构建产物**。

做的：`flutter clean`（build/.dart_tool/ephemeral/.flutter-plugins-dependencies）+ 删 `android/.gradle`；
`flutter pub get --offline` 重建 `.dart_tool`；删掉测试运行后重新生成的 `build/`；`git gc --prune=now`
（`git count-objects`：4033 个松对象 → in-pack 4021）。

结果：**423.7 MB / 612 files**，**-5,852.8 MB（-93.2%）**。分项：`build` 5,184.6→0（下次构建自动长回）、
`.dart_tool` 368.1→10.7、`windows/flutter` 261.6→0.0、`android/.gradle` 21.6→删、`.git` 30.9→**3.2 MB**。
清理后全量测试照跑（见下），说明仓库仍可编译/测试。`docs/DEV_SETUP.md` 新增 §7 记下这三条命令与
"删前想一下"的两处（`dist/` 旧发布件、`.git` 松对象）。

**B. 代码：28 个没人读的 l10n key，以及一条早就该修好的生成链**

扫描 999 个 key，28 个在 `lib`/`test` 手写 dart 中**零引用**（`navMindnet`、`settingsTheme`、
`settingsThemeSystem`、`timeMarkBusy/Open`、`ankiStartReview`、`packagesImportHint`、`threadEnergy2/4/6/8/10`、
`threadExpectedNear`、`threadSortHint`、`propTitleHint/DescriptionHint/EstimateHint/ExpectedHint/DeadlineHint/
EnergyHint/AlgorithmHint`、`propWeightsEditable`、`propTemplatesNote`、`aiThinking`、`skillsEnabled/Disabled`、
`assessmentSkip`、`assessmentRecallPrompt`），从两份 arb 删除后由生成器重写三个 dart。

**顺带修好 `flutter gen-l10n`**：它此前一直退出码 1（所以 l10n 生成文件是手工维护的）。根因只有一处：模板
`app_en.arb` 缺 `@materialIntakeCantLand` 的 placeholder 声明（zh 里是 `reason: String`，模板默认成 Object →
类型冲突）。给模板补 3 行后 gen-l10n **退出码 0**，以后不再手改生成文件。

**C. 逻辑：组卷装配原本复制在两处**

页面 `paperPlanProvider` 与 AI 工具 `compose_paper` 各自把"题库 + 挂载 + 诊断读数 + 每道题最新链的动作序列 +
能力动作画像"拼成 `PaperCandidate` 再调 `PaperComposer.compose`，两段几乎逐行相同；而同一份库必须排出同一份
卷子（D2：一个数字一个来源），复制两处迟早漂移。

抽出 `lib/features/questions/application/paper_plan_builder.dart`：`preferredActionTypesOf(profile)` +
`buildPaperPlan({db, corpus, spec, diagnosis, preferredActionTypes}) → PaperPlanBuild{plan, readingsUsed}`。
两边的 IO 差异保留：页面用已缓存的题库/页面那次诊断/画像 provider；工具用 `readPaperCorpus` +
`readLibraryDiagnosis(默认模型)` + 推理链样本（工具没有 `Ref`）。净效果：`paper_plan_provider.dart` 216→188 行、
`paper_tools.dart` 352→323 行，重复装配只剩一份（新文件 94 行，含注释）。

**D. 两处"能编译但是错的"顺手修掉**

- `event_properties_page.dart` 6 条相对 import 多写了一级（`../../../../data/...`），会越出 `lib` 根；Dart 会把
  越界的相对 import 悄悄 clamp 回 `lib` 根，所以一直没报错。改成真正的 `../../../`（presentation→thread→
  features→lib），并在文件头注释里记下这个坑（自查脚本：lib 内 escaping relative imports 6→0）。
- `data/database/database.dart` 删掉未用的 `dart:typed_data`。

**证据**：`dart analyze lib test` → **93 issues（0 error / 0 warning）**（此前 94，少的 1 条就是那条未用 import）；
全量 `flutter test --concurrency=1` → **`+2107 ~2` All tests passed**（与轮次一百一十一同数：本轮删代码/改装配、
没有新增行为用例；组卷两处改动由既有 provider 11 例 + tool 14 例覆盖，定向 25 例全绿）；`flutter gen-l10n`
退出码 0。

**还能量、但没动的（诚实清单）**：① `dist/` 旧发布件 0.3.1/0.4.0/0.4.1（apk+zip ≈300 MB）保留 —— 重建要
checkout 老 commit，留给用户决定；② `mind_map_page.dart`（443 行）与 `tasks_page.dart`/`task_detail_page.dart`
（280+601 行）在 App 里不可达，但 `DESIGN_BLUEPRINT.md:134` 明确 mindmap「保留不动、UI 下线」、
`FEATURE_MATRIX.md:89` 仍把 tasks 当交付物，故不删；③ analyze 仍有 93 条 info（`await_only_futures`、
`prefer_const_constructors`、deprecated 的 `TextFormField.value`、`use_build_context_synchronously` 等），
没批量改 —— 属于历史代码风格，不在本轮"精简"口径内。

---

## 2026-10-18 轮次一百一十一：认知模型的只读可视化 —— 知识网络图（Lead）

**起点（用户反馈）**：「认知模型我希望有一个只读的可视化界面」。此前读数页只有三块数字/列表
（知识点读数、标签读表、能力动作画像），看得见读数但看不见"结构"。

- **画什么、为什么这样画**：认知模型实际跑的快层图（`cognitive_graph.dart` 的标签扩散）节点是
  **标签**；而读数页手里是**知识点**。两者是两套 id，`knowledgePointTagIdsProvider` 存在的理由就是它们
  不同。所以可视化选「知识点 ↔ 标签」的二部网络：知识点摆在环上、标签按成员角的圆周均值摆在内环，
  一条连线 = 一个知识点挂了一个标签。**不发明知识点之间的边**（线索边另有 `knowledge_edge_page.dart`），
  也不把标签扩散分数硬塞进图里当长度——颜色只表示区域，大小只表示卡片数。
- **只读**：页面只 `watch` provider（上游 `cognitiveReadingsProvider` / `knowledgePointTagIdsProvider` /
  `allTagsProvider` 都是 select 出来的），整条链路没有一次写库调用；也没有"在图上拖动/编辑"的手势。
- **新文件**
  - `lib/features/cognitive/presentation/cognitive_graph_layout.dart`：纯布局，无 Flutter widget。
    `CognitiveGraphPointInput` / `CognitiveGraphTagInput` / `GraphPointNode` / `GraphTagNode` /
    `GraphLink` / `CognitiveGraphLayout`；`layoutCognitiveGraph({size, points, tags})` 按主标签标题→标题→id
    排序后均匀摆外环（半径 `shortestSide/2*0.72`），圆点半径 `5+min(cardCount,8)*1.6`；标签位置取成员
    角度的圆周均值（对称退化时取首角度），内环 = 外环 * 0.42；`hitTestCognitiveGraph` 先点（半径 + 14）
    再标签；`kGraphPointHitSlop = 14`。
  - `lib/features/cognitive/presentation/cognitive_graph_page.dart`：`buildCognitiveGraphData` 把
    `CognitiveCardReading` 按知识点分组，区域取**最坏**一个（danger > deadEnd > empty > overload > slow >
    offGoal > proximal > healthy > unavailable），meanR 取均值；`cognitiveGraphProvider` 组装数据；
    页面 = 画布（`CustomPaint`，参考环 / 连线 / 标签方块 / 知识点圆点，选中提亮）+ 图例（9 个区域词，
    复用读数页 `zoneLabel`）+ 只读详情卡（点知识点→区域/卡片数/平均 R；点标签→挂了多少知识点）；
    空数据有空态；画布最大边 840（`kCognitiveGraphMaxSide`）。
- **入口**：读数页 `_Notes` 之后加一张卡「知识网络图（只读）」→ `CognitiveGraphPage`。
- **使用文档**：`docCognitiveBody` 补一句读数页顶部的知识网络图入口（颜色=区域、大小=卡片数、点节点看读数）。

**证据**：新增 `app/test/features/cognitive/cognitive_graph_layout_test.dart` **6 例**（布局确定性、
外环/内环/连线数、卡片多半径大、空输入与 `Size.zero`、对称退化下圆周均值有限、命中测试含 +14 容差）；
`cognitive_graph_page_test.dart` **2 例**（标题/说明/摘要/图例/画布 + 点圆点看到详情；空数据→空态且无画布）；
`cognitive_model_page_test.dart` **+1 例**（读数页有入口，点进去是图、空态也不崩）。`dart analyze lib test`
→ 94 issues（0 error / 0 warning，与八十六～一百一十同基线）；定向
`flutter test test/features/cognitive test/features/settings` → **+177 全绿**；全量
`flutter test --concurrency=1` → **`+2107 ~2`**（轮次一百一十 `+2098 ~2`，差值 9 = 6+2+1 条新用例）。

**没做的**：① 图不能缩放/拖动，节点太多时外围标签会互相压（只做了截断与左/右对齐，没做避让）；
② 不画知识点之间的边（那属于线索边页，不在这张图里）；③ 代码/体积精简（用户第 4 条，下一轮）。

---

## 2026-10-18 轮次一百一十：卡组设置终于找得到 + 使用文档追上现在的 App（Lead）

**起点（用户反馈）**：「flashcard 的卡组设置我还没有找到在哪里」「很多遗留细碎内容，比如『设置 > 使用文档』需要简单更新」。

- **卡组设置为什么"找不到"**：这个 App 里**卡组就是标签**（标签树就是卡组），真正的设置在复习计划页
  （`review_plan_page.dart`：每个标签的每日新卡/复习上限 + 判分方式/卡片类型）；它此前只挂在复习页
  AppBar 的两个图标（`tune` / `event_available`）后面，没有任何文字入口 —— 等于藏起来。
- **补的路**：设置页新增一条明确入口「卡组设置」（`settingsCardGroups`），副标题直接说清楚
  "卡组就是标签树：给一个标签设每日新卡/复习上限，它整棵子树都算这个卡组；判分方式与卡片类型也在这里改"，
  点进去就是 `ReviewPlanPage`。没有改数据模型，也没有新页面 —— 缺的只是一条能被看见的路。
- **使用文档更新**（`usage_doc_page.dart` + l10n）：
  - 新增三节：「题库与组卷」（收题页不点入库不写库、题干指纹去重、组卷只从已有题凑、AI 不出题、复制卷面、
    能力动作画像可点开找题）、「拍照、资料与演练」（三类待确认产物、资料入库提案、撤回记录、
    照片→`run/1`、机制面板/演练只给读数）、「今天做什么、什么时候做」（今日清单、α(τ)、冲突顺延、
    认知排序档位只改顺序、V(π)/留存探针只影响顺序）。
  - 修正两处过时说法：① AI 读操作清单从 3 个工具扩到当前实际只读工具（含组卷/找相似题/按动作找题/
    今日计划/复习度量）；② 「危险」不再写"本应用不存自信度所以不会出现"——现在它由元认知行
    （自评把握 vs 实际表现）给出，样本不足才不出现；并补了能力动作画像的读法。
  - 「复习与闪存卡」一节补了卡组设置的入口位置；`settingsUsageDocHint` 同步扩成
    "AI、复习、知识库、题库、拍照/资料、认知模型与排序算法"。

**证据**：新增 `app/test/features/settings/settings_page_test.dart` **2 例**（中文/英文设置页都能找到
「卡组设置」并点进 `ReviewPlanPage`，副标题解释了卡组=标签树）；`usage_doc_page_test.dart` 2 例扩展
（新三节的标题 + 正文特征词：题干指纹 / 三类待确认产物 / 今日清单；英文页同步）。`dart analyze lib test`
→ 94 issues（0 error / 0 warning，与八十六～一百零九同基线）；本轮先跑定向测试
`flutter test test/features/settings` → **+15 全绿**；全量 `flutter test --concurrency=1` → **`+2098 ~2`**
（轮次一百零九 `+2096 ~2`，差值 2 = 新增的两条设置页用例）。

**没做的**：① 认知模型的可视化界面（用户第 1 条，下一轮做）；② 代码/体积精简（第 4 条，再下一轮）；
③ 卡组设置页本身还可以更"设置化"（现在它仍是一个混合了读数与编辑的页面，本轮只补入口，不重排页面）。

---

## 2026-10-18 轮次一百零九：组合查询第二步上屏 —— 工具能问的，页面也能问（Lead）

**做了什么**：轮次一百零七～一百零八把组合查询做进了读表、工具与页面学科筛选。但页面上还只能"入口那个
动作 + 一个学科"，而工具面已经能问"分类讨论**且**回代检验""分类讨论**或**回代检验"。这一轮把动作维度的
组合也接上界面：

- **「再叠加一个动作（可选）」下拉**：选项 = 词表里除入口动作外的所有 key（带中文名 + key 便于对照）；
  选一个后页面查询变成 `actionTypes: [入口动作, 第二个动作]`。
- **「两个动作都得出现在同一条链里」开关**：只在叠加了第二个动作时出现，对应查询的 `requireAll`
  （`match: all` / `any`）；清回「不叠加」时开关自动收起、`requireAll` 复位 —— 不留下"看不见的过滤条件"。
- **仍是同一份读表**：全部走 `questionsForCapabilitiesProvider` → `readQuestionsForCapabilities`，
  没有前端过滤；学科 chip 与动作筛选正交，可以同时生效（学科 × 第二个动作 × 任一/全部）。
- 至此**工具面 `find_questions_by_capability` 能问的组合查询，页面上都能问**（参数一一对应：
  下拉↔`action_types`/`action_type`、开关↔`match`、学科 chip↔`subject_key`）。

**顺带纠正文档口径**：目标 ② 写的是"收题页（App 内粘贴/拖拽，**B 优先**）"——B（粘贴 + `file_picker`
选图）早已完成（`question_intake_page.dart`），拖拽是 A 方案、需要引 `desktop_drop` 一类依赖。
已在 `docs/QUESTION_BANK_DESIGN.md` §9 与 `docs/MINDNET_ROADMAP.md` 里把 ② 标成"按 B 口径已完成"，
不再把它列成"待用户拍板才能算完成"的阻塞项；A 方案单独列为可选增强。

**证据**：`app/test/features/questions/presentation/capability_action_questions_page_test.dart` 3 → **4 例**
（新增：两道题一道"两个动作都用上"、一道"只用入口动作"；叠加第二个动作后默认 any 仍两道、打开
「都要出现」只剩一道；下拉清回「不叠加」后开关消失、两道都回来）。本轮 `dart format` 只格式化本轮改动的
5 个 Dart 文件（1 changed，复查 0 changed）；`dart analyze lib test` → `94 issues found`
（**0 error / 0 warning**，与八十六～一百零八同基线）；全量 `flutter test --concurrency=1` →
**+2096 ~2**（轮次一百零八 `+2095 ~2`，差值 1）。

**已知的没做**：① 收题页的"拖拽"（A 方案，可选；引依赖前需用户拍板）；② 能力动作词表用户可编辑
（设计留到 v13）；③ `kPreferredActionBoost = 0.15` 仍属未标定先验；④ 学科维度仍是单选
（动作维度已经能叠第二个 + 任一/全部）；⑤ 组卷/相似题措辞与配额打磨；⑥ 题库入口是否升顶层导航。

---

## 2026-10-18 轮次一百零八：组合查询上屏 —— 页面上也能按学科筛（Lead）

**做了什么**：轮次一百零七把组合查询做在了读表与工具面，页面上却还是"从画像点进来只看一个动作、
库里有什么摆什么"。这一轮把它接到界面：**「按能力动作找题」页可以按学科筛**，而且筛选**走读表**
（`questionsForCapabilitiesProvider` → `readQuestionsForCapabilities`），不是在前端把已加载的结果过滤
一下 —— 否则"页面上看到的"和"模型查到的"迟早分叉（D2：一个数字一个来源）。

- **查询变值对象**：`CapabilityQuestionQuery` 加 `==`/`hashCode`（按归一化后的动作集合 + 学科 +
  `requireAll` 比），可以直接当 Riverpod family 的键；页面重建时同一条查询不会重复读表。
- **provider**：新增 `questionsForCapabilitiesProvider`（family，带数据版本）；原来的
  `questionsForActionProvider` 保留（认知模型页那条入口还在用）。
- **页面**：学科 chip 只列**这个动作下真实出现过的学科**（没出现过的学科不摆出来骗点击）；"全部学科"
  chip 可切回；选中后列表只剩该学科的题，换学科即时重查。筛选后为空时仍用同一句空态（诚实说"还没有
  解过含这个动作的题"），不发明新文案。
- **砍掉一段死代码**：初版还带"这个学科里没有"的专用空态，但 chip 只来自真实出现过的学科，
  这条路径实际不可达 —— 与其留一句永远显示不出来的话，不如删掉（l10n key 同步移除，四个文件都删）。

**证据**：`app/test/features/questions/presentation/capability_action_questions_page_test.dart` 2 → **3 例**
（新增：两个学科的库 → chip 出现；点「物理」只剩物理那道；点「全部学科」两道都回来；
既有两例不回归）；`app/test/features/questions/application/capability_action_questions_reader_test.dart`
4 → **5 例**（新增：查询是值对象 —— 归一化后相等、`hashCode` 一致，学科/`requireAll` 不同不相等）。
本轮 `dart format` 只格式化本轮改动的 8 个 Dart 文件（0 changed）；`dart analyze lib test` →
`94 issues found`（**0 error / 0 warning**，与八十六～一百零七同基线）；全量
`flutter test --concurrency=1` → **+2095 ~2**（轮次一百零七 `+2093 ~2`，差值 2）。

**已知的没做**：① 收题页的"拖拽"（OS 级文件拖入没有 Flutter SDK API，需引依赖或只走"粘贴 + 选文件"，
待用户拍板）；② 能力动作词表用户可编辑（设计留到 v13）；③ `kPreferredActionBoost = 0.15` 仍属未标定
先验；④ 页面的学科筛选是**单选**（多动作 + `match` 的控件还没有，虽然工具面已经能问）；⑤ 组卷/相似题
措辞与配额打磨；⑥ 题库入口是否升顶层导航。

---

## 2026-10-18 轮次一百零七：组合查询 —— "分类讨论和回代检验都得用上的题"也能问（Lead）

**做了什么**：轮次一百零五～一百零六的"按能力动作找题"一次只能问**一个**动作。但真实问法是组合的：
"我一碰到分类讨论和回代检验就卡，给我两道两个都得用上的题""分类讨论类的物理题还剩几道"。这一轮把
读表与工具都扩成组合查询（纯逻辑，不碰 schema）：

- **查询对象**：`CapabilityQuestionQuery`（`question_corpus_reader.dart`）—— `actionTypes` 一组动作 +
  `requireAll`（任一 / 全部）+ `subjectKey`；`normalized()` 去空/去重/trim。
- **读表**：`readQuestionsForCapabilities(db, query)`；单动作的 `readQuestionsForAction` 变成它的简写
  （页面无需改动，口径仍然只有一份）。三条纪律：动作与学科**都空返回空表**（不把解过链的题库整个倒
  出来）、只认**最新一条链**、**命中项如实回报**（`CapabilityQuestionRow.matchedActionTypes` 与
  `actionTypes` 分开：前者是"为什么选中我"，后者是"这条链长什么样"）。
- **工具**：`find_questions_by_capability` 的入参升级为 `action_types`（数组）/ `action_type`（单个，
  向后兼容）/ `match`（`any`|`all`）/ `subject_key` / `limit`；两个条件都空 → 参数错；`match` 非法 →
  参数错；词表外 key（含数组里任意一个）→ 失败并列出可用值。`modelResult` 多了 `query`（归一化后的
  动作 + 中文名 + 学科 + match）和每行的 `matched_action_types` / `matched_actions_zh`；摘要按问法说
  人话（"最新链同时含「分类讨论」「回代检验」的题 3 道…" / "解过链的「数学」题 2 道…"）。
- **不越界**：仍然只从已有题库里找，AI 不出题；空结果如实说没有。

**证据**：`app/test/features/questions/application/capability_action_questions_reader_test.dart`
3 → **4 例**（新增组合查询：任一命中 3 道、`requireAll` 只剩 1 道、命中项如实回报、学科筛选、只按
学科、空条件返回空）；`app/test/features/ai/find_questions_by_capability_tool_test.dart` 7 → **8 例**
（新增组合查询：`match=all` / `any` 默认 / 动作+学科 / 只按学科 / 两个条件都空 → 参数错 / `match` 非法
→ 参数错）。既有 7 例的 payload 断言随 `modelResult` 结构更新（`action_type` → `query.action_types`）。
本轮 `dart format` 只格式化本轮改动的 5 个 Dart 文件；`dart analyze lib test` → `94 issues found`
（**0 error / 0 warning**，与八十六～一百零六同基线）；全量 `flutter test --concurrency=1` →
**+2093 ~2**（轮次一百零六 `+2091 ~2`，差值 2）。

**已知的没做**：① 收题页的"拖拽"（OS 级文件拖入没有 Flutter SDK API，需引依赖或只走"粘贴 + 选文件"，
待用户拍板）；② 能力动作词表用户可编辑（设计留到 v13）；③ `kPreferredActionBoost = 0.15` 仍属未标定
先验；④ **组合查询目前只在工具面**：页面上还是"从画像点进来只看一个动作"，没有"选多个动作 / 学科筛"
的控件；⑤ 组卷/相似题的措辞与配额打磨；⑥ 题库入口是否升顶层导航。

---

## 2026-10-18 轮次一百零六：同一个问法给模型 —— `find_questions_by_capability`（Lead）

**做了什么**：轮次一百零五给用户加了「按能力动作找题」页；但对话里的模型还问不到同一个问题 —— 它只能
"找相似题"或"组卷"，不能"按动作找题"。这一轮把这条路也开给模型：新增只读工具
`find_questions_by_capability`（`action_type` + `limit`），读的是**与页面同一份**读表函数
（`readQuestionsForAction`），所以"页面上查到的"与"模型查到的"不会分叉（D2：一个数字一个来源）。

- **口径一致**：只认每道题**最新一条**解题链的动作序列（与页面、组卷偏好、找相似题同一份
  `readChainActionTypes`）；`modelResult.rule` 明写 `latest_chain_only`，让模型知道这是"最新一次
  怎么解的"，不是"历史上解过的都算"。
- **不出题**：结果全是库里已有的题（题干摘要 + 学科 + 来源 + 链上全部动作 key/中文名）；没有命中时
  摘要明说"还没有解过含这个动作的题 —— 我不会自己出题；先去某道题详情页按一次「AI 解题」"。
- **参数纪律**：`action_type` 必填，词表外的 key 直接失败并列出可用值（`case_split`（分类讨论）…），
  不让模型拿猜的 key 去查；`limit` 默认 10、上限 50、0/负按默认。
- **只读**：`readOnly => true`、`riskFor` 用中性 `write` + `reversibleFor` true —— `ApprovalEngine`
  在两种权限模式下都不逐条询问；测试用整库指纹钉住"一次调用不改任何表"。

**证据**：新增 `app/test/features/ai/find_questions_by_capability_tool_test.dart` **7 例**（注册与审批不打扰、
未知动作列出可用 key、缺参/空串是硬错、命中时题干/学科/来源/动作中文名都对且旧链不算、空结果如实说
没有、`limit` 钳位、整库指纹只读）；`test/features/ai` 全目录 **421 例**全绿（注册表新增一个工具没有
打破任何既有断言）。本轮 `dart format` 3 个 Dart 文件 1 changed（复查 0 changed）；`dart analyze lib test`
→ `94 issues found`（**0 error / 0 warning**，与八十六～一百零五同基线）；全量
`flutter test --concurrency=1` → **+2091 ~2**（轮次一百零五 `+2084 ~2`，差值 7）。

**已知的没做**：① 收题页的"拖拽"（OS 级文件拖入没有 Flutter SDK API，需引依赖或只走"粘贴 + 选文件"，
待用户拍板）；② 能力动作词表用户可编辑（设计留到 v13）；③ `kPreferredActionBoost = 0.15` 仍属未标定
先验；④ 组卷/相似题的措辞与配额打磨；⑤ 题库入口是否升顶层导航；⑥ 这个工具只按单个动作查，
"按一组动作/按学科+动作"的组合查询还没有（页面与工具都没做）。

---

## 2026-10-18 轮次一百零五：按能力动作找题 —— 画像回答"该练哪个"，点开回答"练哪几道"（Lead）

**做了什么**：轮次一百零二～一百零四把"我卡在哪种动作上"算出来、接进组卷、还加了开关 —— 但用户看完
画像还是得自己回题库里翻：**没有"动作 → 题目"的路**。这一轮把它补上：认知模型页的能力动作画像每一行
现在点得开，进入「按能力动作找题」页，列出链上出现过这个动作的题（题干 + 学科/来源/链上动作），
点一行进题目详情页（那里有 AI 解题与卡点评估）。

- **读表（纯 Dart）**：`readQuestionsForAction(db, actionType)` —— 复用 `readChainActionTypes` 的
  **"只认最新一条链"**口径（与组卷的动作偏好、找相似题同一份判断，不会"按画面筛出来的题"和"组卷里算的
  命中"是两回事）；排序 = 来源分级高的在前、平手按题目 id；空动作 / 没命中返回空表。
  `CapabilityQuestionRow` 带题干（题库里 `stem` 非空的题才会出现）。
- **应用层**：`questionsForActionProvider`（family，带数据版本）。
- **页面**：`CapabilityActionQuestionsPage` —— 标题用词表 `labelZh`（词表外原样）；顶部一句"只认最新
  一条链、没解过链的题不会出现"；空态说"先去题目详情页按一次「AI 解题」"，不编"暂无异常"。只读。
- **入口**：画像行加 chevron 并 `Navigator.push` —— 画像回答"该练哪个动作"，点开回答"练哪几道题"。
- **不越界**：只从**已有题库**里找题，AI 不出题（用户口径）。

**证据**：新增 `app/test/features/questions/application/capability_action_questions_reader_test.dart` **3 例**
（命中/旧链里出现过但最新链没有就不算/排序与空动作空输入）；新增
`app/test/features/questions/presentation/capability_action_questions_page_test.dart` **2 例**（题干 + 元信息
"数学 · 高考真题 · 分类讨论、回代检验" + 点进 `QuestionDetailPage`；没有命中时的空态）；
`app/test/features/cognitive/cognitive_model_page_test.dart` 16 → **17 例**（画像行点得开 → 到那一页并显示
标题）。本轮 `dart format` 只格式化本轮改动的 10 个 Dart 文件（0 changed）；`dart analyze lib test` →
`94 issues found`（**0 error / 0 warning**，与八十六～一百零四同基线）；全量
`flutter test --concurrency=1` → **+2084 ~2**（轮次一百零四 `+2078 ~2`，差值 6）。

**已知的没做**：① 收题页的"拖拽"（OS 级文件拖入没有 Flutter SDK API，需引依赖或只走"粘贴 + 选文件"，
待用户拍板）；② 能力动作词表用户可编辑（设计留到 v13）；③ `kPreferredActionBoost = 0.15` 仍属未标定
先验；④ **这一页还没有 AI 工具面**（模型不能自己"按动作找题"，只能组卷/找相似题）；⑤ 页面上没有
"按学科/来源筛"的控件（数据量大了才需要）；⑥ 题库入口是否升顶层导航。

---

## 2026-10-18 轮次一百零四：让那条加成看得见、也关得掉 —— 未标定的先验不该偷偷生效（Lead）

**做了什么**：轮次一百零三的"按我最该练的动作排"是**自动生效**的：用户看不到这一卷被一条没标定的先验
排过，也没有开关 —— 这违反仓库对未标定参数的一贯纪律（显式标注、能关掉，见节律/认知排序那几个开关）。
这一轮补齐两件事：**看得见**、**关得掉**。

- **开关**：`PaperSpec.preferCapabilityActions`（默认 `true`）→ `paperSpecProvider.setPreferCapabilityActions`
  → 组卷页多一个 `SwitchListTile`「按能力动作画像排（未标定）」，副标题说明"命中「你最该练的动作」的题往前
  排一点；没有解题链时不起作用，可以关"。关掉时 provider 传空偏好列表，卷子与"没有画像"逐字段一致。
  「重置组卷条件」把开关也带回默认。
- **可见（说清用了什么）**：`PaperPlan.preferredActionTypes` 如实回报这一卷参考了哪些动作；页面只在非空时
  显示"这一卷按「分类讨论」这类动作排过（未标定，可关）"——空的时候不摆一行空话。动作 key 用词表的
  `labelZh` 说人话，词表外的原样显示。
- **工具同源**：`compose_paper` 多一个 `use_capability_profile`（默认 true），`modelResult` 里
  `preferred_action_types` 与 `capability_profile_used` 如实反映用没用；关掉时 payload 里连"命中字段"都不出现。
  `PaperPlan.toJson()` 也只在真的参考过时带 `preferred_action_types`。

**证据**：`app/test/features/questions/presentation/question_paper_page_test.dart` 21 → **22 例**（开关/说明/
说明行都在；关掉后说明行消失、次序回到"按 id 兜底"、`spec.preferCapabilityActions == false`；按重置后开关
回到 true）；`app/test/features/questions/application/paper_plan_provider_test.dart` 10 → **11 例**（关掉后
`preferredActionTypes` 空、所有 `matchedPreferredActions` 空、理由行不再提"能力动作画像"）；
`app/test/features/ai/paper_tools_test.dart` 13 → **14 例**（`use_capability_profile: false` →
`preferred_action_types` 空、`capability_profile_used == false`、items 里没有命中字段）。本轮 `dart format`
只格式化本轮 7 个 Dart 文件（1 changed，复查 0 changed）；`dart analyze lib test` → `94 issues found`
（**0 error / 0 warning**，与八十六～一百零三同基线）；全量 `flutter test --concurrency=1` → **+2078 ~2**
（轮次一百零三 `+2075 ~2`，差值 3）。

**已知的没做**：① 收题页的"拖拽"（OS 级文件拖入没有 Flutter SDK API，需引依赖或只走"粘贴 + 选文件"，
待用户拍板）；② 能力动作词表用户可编辑（设计留到 v13）；③ `kPreferredActionBoost = 0.15` 仍是未标定先验
（开关与标注有了，数值等标定）；④ 组卷页的"画像说明行"没有点开看详情（目前只有一行字，没有跳去认知模型页
的入口）；⑤ 题库入口是否升为顶层导航。

---

## 2026-10-18 轮次一百零三：把画像接进组卷 —— 「这份卷子练到我最该练的动作」（Lead）

**做了什么**：轮次一百零二把"我卡在哪种动作上"算出来了、摆在认知模型页上；但那是**读**，没有出口 ——
用户看完还是不知道该做哪几道题。这一轮把它接进组卷：候选题目带上自己**最新一条解题链的动作序列**，
组卷器拿到"我最该练的动作"（画像里平均风险 ≥ 0.6 的前 3 个）后，给命中的题一个**透明的分数加成**，
并在理由行里说出来（"这题会练到「分类讨论」这类动作"）。

- **领域层（纯逻辑）**：`PaperCandidate.actionTypes` + `compose(preferredActionTypes:)`；命中比例
  `actionFit = 命中数 / 偏好数`，总分乘 `1 + kPreferredActionBoost * actionFit`，`kPreferredActionBoost = 0.15`
  —— 刻意保守、**只加成不过滤**（当成过滤会把"没解过链的题"整体排除，那就不是练得准，而是只练解过的题）。
  命中动作写进 `PaperItem.matchedPreferredActions`（`toJson` 也有），理由行补一句人话（词表外的 key 原样显示）。
  没有偏好时乘数恒为 1 —— 历史行为逐字段不变。
- **页面**：`paperPlanProvider` 读能力动作画像 + `readChainActionTypes(db)` 给每个候选补动作序列，再一起
  交给 `compose`；画像为空（没解过链）时行为与之前完全一致。
- **AI 工具**：`compose_paper` 走同一份纯函数（`CapabilityProfile.of` + `readChainActionTypes`），
  `modelResult.preferred_action_types` 与 `items[].matched_preferred_actions` 如实带出 —— 页面与工具同源，
  同一份库挑出来的卷子一致（D2）。

**证据**：`app/test/domain/services/paper/paper_composer_test.dart` 16 → **18 例**（偏好只影响次序不过滤、
没偏好时同分且命中列表为空；命中两个动作 > 命中一个、理由行说人话且词表外 key 原样）；
`app/test/features/questions/application/paper_plan_provider_test.dart` 9 → **10 例**（真内存库：一道有链
`case_split`、一道没链，条件完全相同 → 有链的排第一、`matchedPreferredActions == ['case_split']`、理由含
"分类讨论"与"能力动作画像"；没链的照旧进卷且无命中项）；`app/test/features/ai/paper_tools_test.dart` 12 → **13 例**
（工具面同样出现 `preferred_action_types` 与 `matched_preferred_actions`，且整库指纹不变）。本轮 `dart format`
只格式化本轮 5 个 Dart 文件（2 changed，复查 0 changed）；`dart analyze lib test` → `94 issues found`
（**0 error / 0 warning**，与八十六～一百零二同基线）；全量 `flutter test --concurrency=1` → **+2075 ~2**
（轮次一百零二 `+2071 ~2`，差值 4）。

**已知的没做**：① 收题页的"拖拽"（OS 级文件拖入没有 Flutter SDK API，需引依赖或只走"粘贴 + 选文件"，
待用户拍板）；② 能力动作词表用户可编辑（设计留到 v13）；③ 画像还没有"按学科轨道/按题型"的切面，
也没有把"该练动作"做成组卷页上的可见开关（当前是自动生效，用户看不见"为什么这道排前面"以外的信息 ——
理由行里能看到，但没有开关）；④ 题库入口是否升为顶层导航；⑤ `kPreferredActionBoost = 0.15` 未标定。

---

## 2026-10-18 轮次一百零二：能力动作画像 —— 「我卡在哪种动作上」（Lead）

**做了什么**：轮次一百零一验收五片时记下的下一个口子：推理层已经有"这道题这一步他能不能走下去"
（`stuck_point_evaluator.dart`），但**没有跨题的读法** —— 同一类动作在多道题上反复高风险，才是
"这块肌肉没练出来"。这一轮把 `reasoning_steps` 按**跨学科能力动作**聚合，在认知模型页多一张
「能力动作画像」卡片：每个动作多少步、其中几步高风险、平均卡点风险，最该练的排在最上面。

- **一条纯函数**：`app/lib/domain/services/reasoning/capability_profile.dart` —— `CapabilityStepSample`
  → `CapabilityReading`（条数 / 高风险条数 / 平均风险 / 词表认不认识），排序 = 平均风险降序 → 高风险
  条数 → 条数 → 展示名。不碰库、不碰时钟、不碰 Flutter。
- **三条诚实规则**（与推理层其它读数同一口径）：① 只聚合真有的读数 —— `stuckRisk` 为 null 的步骤只算
  条数、**不进平均**（把"模型没判断"当 0 会把风险摊薄）；② 未知动作按原串显示并在界面上明说"那不是
  没问题，是这个词表还不认识它"；③ 空样本就说没有（"先去题目详情页按一次「AI 解题」"），不编"暂无异常"。
- **唯一 IO**：`app/lib/features/questions/application/capability_profile_provider.dart` 读
  `QuestionRepository.allReasoningSteps()`（新增，只读全表步骤），带 `watchDatabaseRevision` —— 解完
  一道题画像立刻能看到新样本。
- **结果不落库**：与卡点评估同一条口径（派生计算）—— 链一重跑，画像跟着变，不存在"画像过期了"。

**证据**：`app/test/domain/services/reasoning/capability_profile_test.dart` **7 例**（归并/只信真读数/
无读数垫底/排序/未知动作原样/空输入/`toJson`）；`app/test/features/cognitive/cognitive_model_page_test.dart`
新增 1 例（真内存库插两条 `case_split` 步骤 + 一条未知动作步骤 → 页面显示
"分类讨论：2 步，其中 1 步高风险，平均风险 0.50"，未知动作 `brand_new_move` 原样出现并带说明），
该文件 15 → 16 例全过。本轮 `dart format` 只格式化本轮改动的文件（**踩了一次 `dart format lib test`
的历史坑：它会把 150+ 个无关文件重排**，已全部 `git checkout` 回退；这条教训第九十五轮已写进 PROGRESS，
这次又验证了一遍）；`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**，与八十六～一百零一
同基线）；全量 `flutter test --concurrency=1` → **+2071 ~2**（轮次一百零一 `+2063 ~2`，差值 8）。

**已知的没做**：① 收题页的"拖拽"（OS 级文件拖入没有 Flutter SDK API，需引依赖或只走"粘贴 + 选文件"，
待用户拍板）；② 能力动作词表用户可编辑（设计留到 v13）；③ 组卷/相似题的措辞与配额打磨；④ 题库入口
是否升为顶层导航；⑤ 画像目前只按动作聚合，没有"按学科轨道/按题型"的切面，也没有跟组卷器联动
（"下一份卷子该多排哪类动作题"还没接）。

---

## 2026-10-18 轮次一百零一：题库五片验收 + 来源分级事后能改（Lead）

**做了什么**：这一轮按 `docs/QUESTION_BANK_DESIGN.md` 把「题库 + 推理层 + 三应用领域」的五片重新核了一遍
（Q1–Q20 的交付是否真的在、测试是否真的绿），补上验收路上唯一一处**用户看得见的断口**：题目的来源分级
在收题那一刻定了之后**再也改不了** —— 粘贴时没标来源、拍照读不出来的题永远停在"未标注"，而
`sourceLevel` 正是检索排序与 `aiQuality` 权重的一等输入。现在详情页多一个「改来源」：来源分级（词表下拉）
+ 来源说明 + 年份 + 地区，只写这四列，题干/答案/解析/加工列一个字不动。

- **仓储开一个窄口子**：`QuestionRepository.updateSource(id, {sourceLevel, sourceLabel, year, region})` ——
  与 `updateProcessing` 分工清楚：那个管加工列（state/trapNote/difficulty/aiQuality），这个管来源元信息；
  题干/选项仍然只追加。`sourceLevel` 走 `kSourceLevelWeight` 白名单，写错值当场抛 `ArgumentError`
  并列出可用值（不悄悄落成权重 0 把排序弄歪）。
- **界面上**：题目元信息那一行右边多一颗「改来源」；对话框是词表下拉 + 三个文本框，**留空 = 不改那一列**
  （想清空再定口径，这一轮不做半套）；年份写错（非整数 / 越界 1900–2200）停在对话框里报错，不写库。
  保存成功立刻 `invalidate(questionDetailProvider)` 重读 —— 不把"屏幕已经变了"寄望于全局写拦截器。
- **验收结论（五片都核实过）**：① schema v12 四表 + v13 两张拍照整理表在（`tables.dart:1070-1290`），
  `v12_migration_test`/`v13_migration_test` 在；② 收题页粘贴 + 文件选择 + 校对表 + 指纹去重在
  （`question_intake_page.dart`、`question_repository.dart`）；③ 拍照整理三类产物（标签/闪存卡/知识点）
  + 落盘队列（`handwriting_proposals.dart` + `handwriting_proposal_repository.dart`）在；④ 推理管道
  （`question_reasoning_service.dart`）、能力动作词表（`capability_action.dart`）、卡点评估
  （`stuck_point_evaluator.dart`）且已接进详情页；⑤ 两段式（`time_window_engine.dart` /
  `domain_balance.dart` / `thread_balance_inputs.dart` → `thread_rank_service.dart`）在。
  这一轮跑的片级测试：`v12/v13` 迁移、`question_repository`、`stuck_point_evaluator`、`time_window_engine`、
  `domain_balance`、`thread_balance_inputs`、`thread_balance_provider`、`question_tools`、`paper_tools`
  共 **85 例**；`test/features/questions` 全目录 **105 例**；拍照整理四件套 **46 例** —— 全绿。
- **仍未做（记在这里，下一轮从这儿挑）**：② 的"拖拽"仍然没有（OS 级文件拖入 Flutter 没有 SDK API，
  要么加 `desktop_drop` 一类依赖、要么就走"粘贴 + 选文件"这两条路 —— 需要用户拍板）；④ 的用户可编辑
  能力动作词表按设计留到 v13；组卷/相似题的措辞与配额打磨仍可继续。

**证据**：`app/test/data/repositories/question_repository_test.dart` +3 例（改四列且题干/答案/加工列不动、
来源分级写错当场拒绝且一列不改、只改来源分级时其余三列保持原样）；`app/test/features/questions/presentation/question_detail_page_test.dart`
+2 例（改来源存得住、页面自己刷新出"高考真题"与 2024 年；年份写错停在对话框、库里 year 仍为 null）。
本轮 `dart format` 6 个 Dart 文件 0 changed；`dart analyze lib test` → `94 issues found`（**0 error /
0 warning**，与八十六～一百同基线）；全量 `flutter test --concurrency=1` → **+2063 ~2**（轮次一百
`+2058 ~2`，差值 5）。

---

## 2026-10-17 轮次一百：这一跑到底做了什么 —— 演练的话跟着批次留下来了（Lead）

**做了什么**：轮次九十三让演练的每条动作有了读数、轮次九十八把它摆到了界面上 —— 可那些读数**只在当时
那一屏**：对话框一关、或者过两天从待确认清单里重新打开那一批，就只剩汇总的一句话（"这一跑跑了 N 条动作，
其中 M 样要新建"），"它当时到底做了哪几步、每步改了什么"全没了。于是每一轮的"已知的没做"里都躺着②
"演练读数仍然是现算的、不落库"。这一轮做它的前半段：**`run/1` 那条路落提案时，把"这一跑做了什么"一起
存下来**（schema v23 的 `material_intake_batches.detail_text`），并在清单上给一个只读入口。

- **存什么**：每条动作一行引擎原话（`RunActionTrace.text`），下面缩进一行它回报的读数（`traceReadingOf`）——
  就是轮次九十三在对话框里摆的那段话。`runDetailTextOf(report)` 一处生成，落提案时随批次写下去。
- **为什么不是只存在内存里**：待确认清单是"关掉页面也在"的东西（轮次六十九），人常常过一天才回来点头；
  那时候审批的仍是"这一跑要不要建这些东西"，"它当时跑成什么样"必须还看得见。
- **材料那条路没有这一列**（仍是 NULL）：它不是"跑"出来的，没有动作可讲 —— 不编一段空话。
- **界面上**：待确认清单的批次读数下面多一行「这一跑当时做了什么」，点开是只读对话框 —— 原样摆出那段人话，
  一个字不改。重记同一批（同一份 `run/1` 再来一次）时这一列跟着刷新，不会留着上一轮的旧话冒充。
- **怎么落库的**：`record(...)` 多一个可选的 `detailText`；`MaterialIntakeBatch` 带着它（`toJson` 里是
  `detail`）；schema v22 → v23 纯新增一列，老行不动；`_ensureColumns` 里也 heal 这一列（老文件被盖成 v23
  却没有它时，Drift 跳过 onUpgrade、读批次列表会抛错 —— 与 v19/v21/v22 那批同一个失败模式）。

**证据**：`db.select(db.materialIntakeBatches)` 的那一列由 `app/test/data/repositories/material_intake_repository_test.dart`
新增 1 例钉住（带 `detailText` 记进去、读得回来；材料那条路重记一次这一列回到 null，不留旧话）；
`app/test/features/cognitive/application/run_intake_test.dart` 扩了 3 条断言（批次上真有这段、逐条动作原话
逐字对上）；`app/test/features/cognitive/presentation/material_intake_page_test.dart` 那条"就地去那一批"扩了
一段（点开「这一跑当时做了什么」→ 只读对话框里出现 `1 [knowledge] 新增节点 en::w::a`，关掉就消失）；
新增 `app/test/data/database/v23_migration_test.dart` 2 例（真实 v22 文件升级后那一列能用、老批次还在；被盖成
v23 却没有这一列的文件靠自愈补上）。drift 代码用 `dart run build_runner build --delete-conflicting-outputs`
重新生成（只有 `database.g.dart` 变）。**写这两条迁移测试时逮到两个真 bug**：① `_upgradeV22ToV23` 在"表还没
建"的老文件（v17 那种）上会抛 `unknown table` —— 补了"没有表就返回"的守卫，`v17_migration_test` 因此复红；
② `_tableFor` 里没有 `material_intake_batches` 这个名字分支（自愈那一趟按名字解析表），补上之后两条测试才绿。
本轮 `dart format` 13 个 Dart 文件 0 changed；`dart analyze lib test` → `94 issues found`（**0 error / 0
warning**，与八十六～九十九同基线）；全量 `flutter test --concurrency=1` → **+2058 ~2**（轮次九十九
`+2055 ~2`，差值 3）。

**已知的没做**：① 谁来决定"这份请求可以执行了"（判断者仍缺）；② **本轮只做了前半段**：`detail_text` 是
一段人话、不是可查询的结构化记录（想按动作/机制查还不行），材料那条路没有，演练本身仍然不落库；③ `ls` 仍
没有标定来源；④ 其余 18 个参数还没有滑块；⑤ 连接的两端与 `ls` 仍然不能就地改；⑥ 边提案的 `ls` 照抄增量、
`lsCalibrated` 一律 false；⑦ run 那条路的提案只能在 `record` 的同一次调用里改。

---

## 2026-10-17 轮次九十九：AI 也能在点名前改（第二半）—— run 那条路的正文能补，提案 id 也摆出来了（Lead）

**做了什么**：轮次九十六让 AI 在材料那条路上能在点名前改标题（`apply_material_intake` 的 `renames`），
轮次九十八让界面能改正文 —— 可 `check_transcribe_run` 走 `record` 那条路还是只有"记成提案、告诉你去
点头"：提案 id 没摆出来（模型下一次想改都无从下手），正文那一半更没有（`run/1` 这条路的正文**本来
就是空的**，`why` 里明说"等你在清单上补"）。这一轮把这两件事一起补上。

- **提案 id 摆出来**：`record: true` 的 `modelResult` 多一个 `recorded_proposals`（每条的
  `proposal_id` / `kind` / `title`）—— 下一次要查/改/点头都靠它，不再让模型猜 id。
- **点头之前能改**：多一个 `edits`（提案 id → 改什么）：值给字符串就是只改标题，给对象可以
  `{title, body}`。调的是轮次九十七的 `MaterialIntakeRepository.editPointProposal` —— 与界面那颗铅笔
  **同一处规矩**（只改还没点头的、只改知识点提案、空标题挡住、`exists` 跟着现算）。
- **两条纪律**：`edits` 必须跟 `record: true`（先落成提案才谈得上改）；改失败时如实说"提案已经记下来了，
  但还没点头，所以一个知识点都没建" —— 不谎称"一个字都没写"。
- **改完看得见**：`modelResult.edited` 摆出改过哪几条，摘要里也有一行；`recorded_proposals` 里摆的就是
  **改过之后**的标题（模型下一步看到的与现实一致）。

**证据**：`app/test/features/ai/check_transcribe_run_tool_test.dart` 14 → 17 例 —— `record: true` 那条补上
"提案 id 摆出来了"（三条 id 都在）；新例 `record` + `edits` 改标题与正文（清单里那条的 `payload_json` 变了、
`recorded_proposals` 里是改过的标题、知识点一行都没建）；`edits` 指到一条连接 ⇒ "只有知识点提案能改"；
`edits` 没跟 `record` ⇒ 说清怎么用。本轮 `dart format` 2 个 Dart 文件 2 changed（复查 0 changed）；
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**，与八十六～九十八同基线）；全量
`flutter test --concurrency=1` → **+2055 ~2**（轮次九十八 `+2052 ~2`，差值 3）。

**已知的没做**：① 谁来决定"这份请求可以执行了"（判断者仍缺）；② 演练读数仍然是现算的、不落库——**轮次一百做了前半段**（`run/1` 那条路落提案时把"这一跑做了什么"存进批次 `detail_text`，重启后看得见；材料那条路没有，演练本身仍不落库）；③ `ls` 仍
没有标定来源；④ 其余 18 个参数还没有滑块；⑤ 连接的两端与 `ls` 仍然不能就地改；⑥ 边提案的 `ls` 照抄增量、
`lsCalibrated` 一律 false；⑦ run 那条路的提案仍然只能"在 `record` 的同一次调用里改"（没有单独一个"改一批
已记下的提案"的工具）。

---

## 2026-10-17 轮次九十八：连接的两端说人话 —— 顺手把一个会抖的断言改稳（Lead）

**做了什么**：待确认清单里，`run/1` 那条路读出来的**连接提案**标题一直是一串节点 id（`en::w::a → en::w::b`）
—— 因为计划层只拿得到 `from` / `to` 两个 id。可"这条边连的是谁"恰恰是人点头前最想知道的一件事，而两端
的名字明明有：这一跑自己建的节点带着名字（`trace.delta.node.name`），库里已有的节点也有标题
（`external_node_inventory`）。材料信封那条路早就用名字拼标题了，只有 `run/1` 这条路露着 id。

- **两级名字，最后才退回 id**：`planRunKnowledge` 多一个 `nodeLabels`（id → 名字，调用方给库里已有的那些），
  计划层自己再从这一跑的节点增量里收一遍（**这一跑建的名字优先**）—— 拼标题时 `labels[from] ?? from`，
  没有名字才退回 id。两端真身仍是 id（`from`/`to` 一个字没动），只有给人看的那行改了。
- **谁给的标签**：`recordRunKnowledge` 从 `externalNodeInventory()` 里取（id → 标题），一起交给计划层 ——
  所以界面「交给人确认」与 AI 工具 `check_transcribe_run` 的 `record` 两条路自动都变好，不用各改一遍。
- **顺手改稳一个会抖的断言**：全量套件第一次跑时 `app/test/features/anki/review_service_test.dart` 里
  "a miss followed by the solution ... leaves the FSRS schedule untouched" 红了一次 —— 它拿两次 `grade`
  之后的 `stability` 直接比相等，而两次调用隔几毫秒、FSRS 用"现在"算经过天数，浮点尾数会差 1e-8 量级
  （实测 `1.62332132` vs `1.62332135`）。这不是认知模型的分歧，是钟的分歧，所以改成容差（`< 1e-5`）并把
  道理写在测试里 —— 与本轮改动无关，但顺手钉住，免得它以后继续偶发地红。

**证据**：`app/test/domain/services/ingest/run_knowledge_plan_test.dart` 新增 2 例（这一跑自己建的节点用名字：
`alpha → beta`，两端真身仍是 id；这一跑没建的那一端用调用方给的标签：`en::w::a → beta（库里那张卡）`）；
`app/test/features/cognitive/presentation/material_intake_page_test.dart` 里那条"就地去那一批"的断言从
`en::w::a → en::w::b` 改成 `alpha → beta`（同一份演练数据，现在显示名字）。本轮 `dart format` 5 个 Dart 文件
0 changed；`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**，与八十六～九十七同基线）；
全量 `flutter test --concurrency=1` → **+2052 ~2**（轮次九十七 `+2050 ~2`，差值 2）。

**已知的没做**：① 谁来决定"这份请求可以执行了"（判断者仍缺）；② 演练读数仍然是现算的、不落库——**轮次一百做了前半段**（`run/1` 那条路落提案时把"这一跑做了什么"存进批次 `detail_text`，重启后看得见；材料那条路没有，演练本身仍不落库）；③ `ls` 仍
没有标定来源；④ 其余 18 个参数还没有滑块；⑤ 连接的两端与 `ls` 仍然不能就地改（标题改了，真身没改）；
⑥ 边提案的 `ls` 照抄增量、`lsCalibrated` 一律 false；⑦ `check_transcribe_run` 走 `record` 那条路仍然不能
改名/改正文（没有把提案 id 摆出来）。

---

## 2026-10-17 轮次九十七：点头之前能改（第二半）—— 正文也能补上，那颗铅笔成了一整个编辑框（Lead）

**做了什么**：轮次九十四让人在点头之前改命题的**标题**，可"读出来的东西不对"不止名字：材料里的正文
（释义/例句）机器常读不全，`run/1` 那条路干脆把正文留空（`why` 里明说"落库时内容留空、等你在清单上
补"）—— 可清单上根本没有"补"的地方。这一轮把铅笔扩成编辑框：**标题 + 正文**一起改，正文还是多行的。

- **仓储多开一个口子**：`MaterialIntakeRepository.editPointProposal({batchId, proposalId, title?, body?})`
  —— 与标题同一条规矩（只改还没点头的、只改知识点提案、空标题挡住、`exists` 跟着标题现算）；正文允许留空
  （有人就是想把不是正文的东西删掉），首尾空白剪掉；两个字段都不给就是没改什么，直接返回不写一行。
  `renamePointProposal` 变成它的窄口子（界面与 AI 工具都还用着，`renames` 那条路一个字都不用改）。
- **界面上**：`_RenameDialog` 换成 `_EditProposalDialog`（标题一个框、正文一个多行框，一进来都预填现值）；
  提案卡片上也多一行"正文：…" —— 改了什么不必等落库才看得见。
- **只开了这两个字段**：`MaterialIntakeProposal.copyWith({title, exists, body})` —— 其余字段（id、两端、
  `ls`、出处）仍是上游算出来的，让它们能被就地改就等于把"这条提案从哪来"改掉了。

**证据**：`app/test/data/repositories/material_intake_repository_test.dart` 新增 4 例（只改正文不动标题
+ 点头之后写进 `content` 的就是它 + 首尾空白剪掉；标题与正文一起改、`exists` 跟着现算；两个字段都不给
= 没改什么；改正文也守"已点头的不许改"）；`app/test/features/cognitive/presentation/material_intake_page_test.dart`
35 → 36 例（"点头之前连正文一起补上：清单上看得见，点头时写进 content"：正文框预填材料的正文、改成
"释义：依靠；搭配 rely on sb." 之后清单上立刻显示、点头之后知识点的 `content` 就是它）。既有两条改名用例
改用 `find.widgetWithText(TextField, …)` 定位（对话框现在有两个框）。本轮 `dart format` 9 个 Dart 文件
2 changed（复查 0 changed）；`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**，与
八十六～九十六同基线）；全量 `flutter test --concurrency=1` → **+2050 ~2**（轮次九十六 `+2045 ~2`，差值 5）。

**已知的没做**：① 谁来决定"这份请求可以执行了"（判断者仍缺）；② 演练读数仍然是现算的、不落库——**轮次一百做了前半段**（`run/1` 那条路落提案时把"这一跑做了什么"存进批次 `detail_text`，重启后看得见；材料那条路没有，演练本身仍不落库）；③ `ls` 仍
没有标定来源；④ 其余 18 个参数还没有滑块；⑤ **本轮补上的是正文那一半** —— 连接的两端与 `ls` 仍改不动；
⑥ 边提案的 `ls` 照抄增量、`lsCalibrated` 一律 false；⑦ `check_transcribe_run` 走 `record` 那条路仍然
不能改名/改正文（没有把提案 id 摆出来）。

---

## 2026-10-17 轮次九十六：界面与工具同一把尺子 —— AI 也能在点名前改一改标题（Lead）

**做了什么**：轮次九十四给待确认清单加了一颗铅笔（点头之前能改知识点提案的标题）。可那条路只有界面
走得到：AI 工具那条路（`ingest_material` 看清单 → `apply_material_intake` 点头）仍然只会"看 + 点头"，
同一个"标题读错了"的场景，人点得到、agent 点不到。这一轮把铅笔也接到工具上：
`apply_material_intake` 多一个 `renames`（提案 id → 新标题），**先改名字、再点头**，改的仍然是提案本身
（`payload_json`），知识点照样要等 `apply` 那一下才建。

- **同一把尺子**：改名字调的是轮次九十四的 `MaterialIntakeRepository.renamePointProposal` —— 界面与工具
  共用一处规矩（只改还没点头的、只改知识点提案、空标题挡住、`exists` 跟着现算）。工具这边只多做两件事：
  说清"改过哪几条"、改失败时把人话原样端出来。
- **失败不清空**：改标题那一步失败时，提案已经记下来了（`record` 在 `apply` 之前），所以摘要说的是
  "提案已经记下来了，但还没点头，所以一个知识点都没建" —— 不谎称"一个字都没写"。
- **参数纪律**：`renames` 必须是对象；键不能是空的；值首尾空白剪掉；不属于这一批的 id 照实报"没有这条
  提案"。
- **模型看得见**：`modelResult.renamed` 里摆出每一条"提案 id → 改成了什么"，摘要里也有一行 —— agent 下一
  步据此判断"要不要再改一条"。

**证据**：`app/test/features/ai/apply_material_intake_tool_test.dart` 8 → 13 例 —— `renames` 先把标题改了
再点头（库里那个知识点的标题就是改过的、原名字不再出现、`renamed` 与摘要都说清）；`renames` 指到一条连接
⇒ 失败且说清"只有知识点的标题能改"（这次失败没多建任何东西）；空标题 ⇒ "标题不能是空的"；不属于这一批的
id ⇒ "没有这条提案"；`renames` 不是对象 ⇒ 参数错。本轮 `dart format` 2 个 Dart 文件 2 changed（复查 0
changed）；`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**，与八十六～九十五同基线）；
全量 `flutter test --concurrency=1` → **+2045 ~2**（轮次九十五 `+2040 ~2`，差值 5）。

**已知的没做**：① 谁来决定"这份请求可以执行了"（判断者仍缺）；② 演练读数仍然是现算的、不落库——**轮次一百做了前半段**（`run/1` 那条路落提案时把"这一跑做了什么"存进批次 `detail_text`，重启后看得见；材料那条路没有，演练本身仍不落库）；③ `ls` 仍
没有标定来源；④ 其余 18 个参数还没有滑块；⑤ 提案能改的仍然只有标题（正文 `body`、连接的两端与 `ls`
改不动）—— **轮次九十七补上了正文那一半**（标题 + 正文都能改；连接的两端与 `ls` 仍改不动）；⑥ 边提案的 `ls` 照抄增量、`lsCalibrated` 一律 false；⑦ `check_transcribe_run` 走 `record` 那条
路仍然不能改名（没有把提案 id 摆出来给你改）。

---

## 2026-10-17 轮次九十五：交给人确认之后的闭环 —— 那一批就在这一页下面（Lead）

**做了什么**：轮次九十一把"一跑要建的东西"先落成待确认提案，用户在清单上点头才真的建。可这条路的
**两条出口都不通**：① 清单就在**这一页**（`MaterialIntakePage` 的待确认清单），对话框里那句提示却写着
"去「添加资料」那一页点头"，说的是用户正站着的地方；② 记完之后对话框里只说"已经记成一批
（`run-1`）"，用户得自己关掉对话框、在两张单子里找出那一批。

- **话先改对**：提示与"记成了"那句改成"**就在这一页下面的待确认清单里点头**" / "就在这一页下面" ——
  说清它落在哪，不指一个已经在脚下的一页。
- **给一个就地的入口**：记成之后多一颗「去看看这一批（N 条待确认）」—— 按一下把对话框关掉，页面
  **把那一批摆到清单上**（与「看提案」同一个视图：同样的提案卡片、同样的勾选、同样的"缺哪一端"）。
- **记完就刷单子**：交给人确认这一步由对话框按下，可"记成一批"是**这一页**的事 —— 记完立刻重读两张
  单子（待确认 / 已经确认完的）。就算用户直接按叉关掉对话框，那一批也已经挂在单子上了。
- **两种出口写成一个 sealed 家族**：照片报告那张对话框现在能反出两件事 —— `_EditAndRun`（改一改再跑，
  轮次九十二）与 `_OpenBatch`（去看那一批）。用 sealed class 而不是 `Object?`：页面拿到以后必须两种都
  处理，漏了一种编译器会说。

**证据**：`app/test/features/cognitive/presentation/material_intake_page_test.dart` 33 → 35 例 ——
"交给人确认之后就地去那一批：对话框关掉，清单已经摆在这一页上"（记完那句与提示都不再指"另一页"；按
「去看看这一批（3 条待确认）」之后 `AlertDialog` 一个不剩，`alpha` / `beta` / `en::w::a → en::w::b`
三条提案卡片与「确认这 3 条」都在页面上，知识点还是一个都没多）；
"照片报告那条路也走得通：两种出口（改一改再跑 / 去看那一批）都在"（照片那条路同时摆着两个出口，
按"去看那一批"也走同一条路）。本轮 `dart format` 5 个 Dart 文件 0 changed；`dart analyze lib test` →
`94 issues found`（**0 error / 0 warning**，与八十六～九十四同基线）；全量 `flutter test --concurrency=1`
→ **+2040 ~2**（轮次九十四 `+2038 ~2`，差值 2）。

**已知的没做**：① 谁来决定"这份请求可以执行了"（判断者仍缺）；② 演练读数仍然是现算的、不落库——**轮次一百做了前半段**（`run/1` 那条路落提案时把"这一跑做了什么"存进批次 `detail_text`，重启后看得见；材料那条路没有，演练本身仍不落库）；③ `ls` 仍
没有标定来源；④ 其余 18 个参数还没有滑块；⑤ 提案能改的仍然只有标题（正文 `body`、连接的两端与 `ls`
改不动）—— **轮次九十七补上了正文那一半**（标题 + 正文都能改；连接的两端与 `ls` 仍改不动）；⑥ 边提案的 `ls` 照抄增量、`lsCalibrated` 一律 false；⑦ AI 工具那条路仍然只会"看清单 + 点头"，
不能在点名之前替用户改一改标题（界面与工具暂时不同口径）。

**踩到的一个坑（写给后面的轮次）**：这一轮误把 `dart format --set-exit-if-changed lib test` 当成"只检查"
跑了 —— 它会**真的改写**（153 个与本次无关的文件被重排）。本仓库已提交的排版与本地这个版本的
`dart format` 口径不一致，所以**永远只格式化本次改动的文件**；已经被改写的那 153 个文件用
`git checkout -- <路径>`（去掉本次真正的改动）回退了，工作区只留下本轮该改的 7 个文件。

---

## 2026-10-17 轮次九十四：点头之前能改 —— 待确认清单里的名字改得动了（Lead）

**做了什么**：从轮次六十五起，"待确认清单"就是人与机器之间的那道闸 —— 提案摆出来、人看过、点头才落库。
可这道闸只开了"勾 / 不勾"：机器读出来的标题如果错一个字（多一个句号、大小写不对、句子被截断），用户手上
只有两条路 —— 点头认下这个错名字（它以后就是知识点的 `title`），或者整条不要。这一轮给清单补上"改一改"。

- **只改提案，不改知识点**：写的是 `material_intake_proposals.payload_json` 里那个标题（外加跟着重算的
  `exists`），`knowledge_points` 一个字不写 —— 知识点仍然要等点头那一下才建，改完名字点头建出来的就是
  改过的那个。
- **只改能改的**：① **已经点头过的不许改**（它是历史，要改得去改那个知识点本身）；② **只改知识点提案**
  —— 连接的标题是 `${from} → ${to}` 现算的，改它等于改一个"显示出来的东西"；③ **空标题挡住**（改成一个
  字都没有的名字，等于把这一条悄悄删掉）。
- **改完跟着重算的一句话**：`exists`（"库里已经有同名的了，不重复建"）是**现算**的 —— 改名之后按同一套
  归一（去空白、压空白、转小写）重新比一遍，所以改成库里已有的名字会自己标上"已存在"，改回去又消失。
- **规矩在仓储、人话在界面**：能不能改、空标题怎么办都在
  `MaterialIntakeRepository.renamePointProposal` 里说（`MaterialApplyException` 的 message 就是给用户看的
  那句）；页面只管弹一个框、把理由摆出来，并且**改完保住用户的勾选**（用户没取消勾，就不替他取消）。
- **只开两个字段的口子**：`MaterialIntakeProposal.copyWith({title, exists})` —— 其余字段都是上游算出来的
  （id、两端、`ls`、出处），让它们能被就地改，就等于把"这条提案从哪来"改掉了。

**证据**：`app/test/data/repositories/material_intake_repository_test.dart` 新增一组 5 例 —— 还没点头的改得动
（首尾空白剪掉、`exists` 跟着重算：改名到库里已有的 → `true`，改回没有的 → `false`，别的提案一个字没动，
库里知识点仍是 1 条）；已经点头过的不许改（消息含"已经点头过"，提案的标题与 `exists` 都不动）；连接不给改；
空标题挡住（原名还在）；这一批里没有这条提案。`app/test/features/cognitive/presentation/material_intake_page_test.dart`
31 → 33 例 —— "点头之前改一改名字：清单上就地改，点头时建的就是改过的那条"（两条知识点提案各有一个铅笔、
连接没有；框里预填原名；改成 `rely upon` 之后清单上是新名字、点头之后库里就是 `rely upon`）；
"改名字被挡下来时，理由摆在页面上"（空标题 → 页面出现"标题不能是空的"，原名还在）。本轮 `dart format`
8 个 Dart 文件 4 changed（改完复查 0 changed）；`dart analyze lib test` → `94 issues found`
（**0 error / 0 warning**，与八十六～九十三同基线）；全量 `flutter test --concurrency=1` → **+2038 ~2**
（轮次九十三 `+2031 ~2`，差值 7：+5 +2）。

**已知的没做**：① 谁来决定"这份请求可以执行了"（判断者仍缺）；② 演练读数仍然是现算的、不落库——**轮次一百做了前半段**（`run/1` 那条路落提案时把"这一跑做了什么"存进批次 `detail_text`，重启后看得见；材料那条路没有，演练本身仍不落库）；③ `ls` 仍
没有标定来源；④ 其余 18 个参数还没有滑块；⑤ **本轮补上的是"改标题"** —— 提案的正文（`body`）、连接的两端
与 `ls` 仍然改不动；⑥ 边提案的 `ls` 照抄增量、`lsCalibrated` 一律 false。

---

## 2026-10-17 轮次九十三：演练读数 —— 每一条动作到底改了什么（Lead）

**做了什么**：执行层从轮次七十八起就把每一条动作的后果回报进了 `RunActionTrace.delta` —— 记忆层是那段
`R/S/D` 变化（`R_at_review` / `R_after` / `S_after` / `S_increase` / `R0_after` / `Σ` / `D`），时间推进是
`synced_nodes` 与每个节点现在的可提取度 `ms`，新建是节点/边的形状，扩散是起点与目标。可这些读数一直
**没有出口**：`RunActionTrace.text` 只有一句 `summary`，界面与工具都只摆那一句。于是每一轮的"已知的没做"
里都躺着②"`review` / `goal` / `time` 的读数仍然没有出口"。这一轮给它们一个出口：把增量折成人话一行，
摆在那条动作的下面。

- **一个纯函数，两处调用**：新增 `app/lib/domain/services/ingest/run_reading.dart` 的
  `String traceReadingOf(RunActionTrace trace)` —— 认得出记忆层、新建节点/边、时间推进、扩散这几种形状，
  认不出来就把键值列出来（将来换机制时这条兜底就是出口）。
- **两条纪律**：① **只摆引擎真回报的东西** —— 这一条没跑成（`error != null`）或机制根本没装（空增量）
  时返回空串，**不编**一句"看起来像变化"的话；② 认不出来也要说，不吞。
- **界面上**：`_RehearsalReading` 里每条痕迹从 `ListTile`（只有 `text`）换成 `_TraceTile` —— 读数作为
  `subtitle` 摆在同一行下面；读数空的时候不摆第二行（`subtitle: null`）。两个对话框（照片报告、贴一份
  `run/1`）共用这一处，所以两条路一起有。
- **AI 工具上**：`check_transcribe_run` 的 `execute: true` 摘要里，每条痕迹那行下面缩进一行摆读数
  （`_traceLine`），与界面同一把尺子。
- **数字照人的读法**：留三位小数、去掉尾部零（`0.800` → `0.8`、`3.000` → `3`），节点多于 4 个时只列前
  几个再说出总数。

**证据**：新增 `app/test/domain/services/ingest/run_reading_test.dart` **12 例**全过（记忆层那段认得出前后、
缺 `R_at_review` 时说得出改成了什么、空增量与没跑成都返回空串、时间推进的读数与"多于 4 个只列前几个"、
扩散的起点/目标/轮次归零、新建节点/边、认不出来的形状兜底、小数位与去零）；`check_transcribe_run` 的
`execute: true` 那条钉上摘要里有"记忆层读数（"与 `R `；界面那条钉上演练读数里有"记忆层读数（"。
本轮 `dart format` 6 个 Dart 文件 1 changed（改完复查 0 changed）；`dart analyze lib test` →
`94 issues found`（**0 error / 0 warning**，与八十六～九十二同基线）；全量 `flutter test --concurrency=1` →
**+2031 ~2**（轮次九十二 `+2019 ~2`，差值 12）。

**已知的没做**：① 谁来决定"这份请求可以执行了"（判断者仍缺）；② 本轮补上的是**演练读数**（跑完看得见改了
什么），"这些读数**留下来**"仍没有（演练不落库、读数是现算的）；③ `ls` 仍没有标定来源；④ 其余 18 个参数
还没有滑块；⑤ 结构化编辑（改某一条动作的某个字段的专门控件）仍没有；⑥ 边提案的 `ls` 照抄增量、
`lsCalibrated` 一律 false。

---

## 2026-10-17 轮次九十二：照片报告里能就地改一改再跑 —— 同一张可编辑的对话框，两条路共用（Lead）

**做了什么**：轮次八十七让照片报告能试跑，轮次八十八让"贴一份 `run/1`"能校验 + 试跑。可这两条路对
**同一份请求**的处置并不对等：贴进来的那份在框里能改（改完重新校验、重新跑），照片读回来的那份只能看
—— 想动一个 id 得让模型再读一遍那张照片。于是每一轮的"已知的没做"里都躺着⑤"报告里不能就地改一改再跑"。
这一轮把照片报告接上同一张可编辑的对话框：报告里按「改一改再跑」，照片那张关上、可编辑的那张带着这份
请求**原文**打开，并且**一进来就校验过一遍**（用户看见的是"现在这份"，不是一张空白框）；改完照改的那样
重新校验、重新试跑。

- **一张对话框，两条来路**：`_RunRequestDialog` 多了 `initialText`，"贴一份 `run/1`"与照片报告那条路
  现在都走 `_openRunDialog({initialText})` —— "从哪来"只影响框里一开始有什么字。照片那张用
  `showDialog<String>` 把请求的 JSON 反出来（`jsonEncode(report.request.toJson())`），页面拿到就开那张
  可编辑的对话框。
- **默认那条路一个字没变**：不传 `initialText` 就不预填、不预校验（剪贴板那条路的经验照旧）。
- **只读没变**：改的只是框里的字；跑的还是 `rehearseRun`（一个字不写库），"交给人确认"那一下照旧只落
  待确认提案。改请求也不会再去读一遍照片（模型只被请求一次）。
- **标题分开说**：`materialIntakeRunDialogTitleEdited`（"改一改再跑（同一份 run/1）"）与"贴一份 `run/1`"
  分开，免得用户以为要从头再贴一遍。

**证据**：`app/test/features/cognitive/presentation/material_intake_page_test.dart` 30 → 31 例 —— 新例
"照片报告里『改一改再跑』：带着这份请求进可编辑的那张，跑的是改过的那份"：报告里按一下 → 可编辑那张打开、
框里就是这份请求（含 `run-1`）、**且已经校验过一遍**；把 `run_id` 改成 `run-2` → 校验 → 试跑，接住的就是
`run-2`；模型只被请求过一次；`knowledge_edges` / `material_intake_proposals` 一个字没写、
`knowledge_points` 仍只有原来那 1 条。本轮 `dart format` 2 个 Dart 文件 1 changed（改完复查 0 changed）；
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**，与八十六～九十一同基线）；全量
`flutter test --concurrency=1` → **+2019 ~2**（轮次九十一 `+2018 ~2`，差值 1）。

**已知的没做**：① 谁来决定"这份请求可以执行了"（判断者仍缺）；② `review` / `goal` / `time` 的读数仍然
没有出口 —— **轮次九十三补上了**（`traceReadingOf`）；③ `ls` 仍没有标定来源；④ 其余 18 个参数还没有滑块；⑤ **本轮补上的是"能改"，不是"结构化编辑"**
—— 动的仍是 JSON 文本，要改某一条动作的某个字段还没有专门的控件；⑥ 边提案的 `ls` 照抄增量、`lsCalibrated`
一律 false。

---

## 2026-10-17 轮次九十一：执行完怎么落库（第一半）—— 一跑要建的东西先交给人确认（Lead）

**做了什么**：轮次八十五起，`run/1` 请求能真的跑进引擎（`executeRun`）；轮次八十七、八十八把这件事摆到了
照片报告与"贴一份 `run/1`"两个入口上。可那一跑留下的 `knowledge` 增量（`added: node` / `added: edge`）
一直没有出口 —— 读数看得见，库里什么也没有，roadmap §2-C 的 ②「执行完怎么落库」就这么空着。这一轮只做
**前半段**：把一跑想建的东西落成**待确认提案**（走已有的 `material_intake_batches` /
`material_intake_proposals` 两张清单表），`knowledge_points` / `knowledge_edges` 一个字不写。判断者（①）
仍然缺，所以这一步的终点是"交到人手上"，不是自动确认。

- **领域层是纯函数**：`run_knowledge_plan.dart` 的
  `planRunKnowledge({report, existingNodeIds, existingTitles, sourceRef})` 只读一跑的 traces 与两张
  id/标题集合，产出 `MaterialIntakePlan` —— 节点 → `knowledge_point` 提案（`nodeId` + 标题 + 引用说清
  来自第几条动作）、边 → `connection` 提案（`from`/`to` + `ls`）；库里已有的 id/标题照旧标 `exists`；
  不是 knowledge 动作、动作没回报增量、以及**整份没跑完**（`stoppedAt != null`）都进 `skipped` 并说清
  原因。不碰库、不读设置。
- **应用层薄到只剩接缝**：`run_intake.dart` 的 `recordRunKnowledge({report, db, anki, now, sourceRef})`
  走仓库现成的 `record`（**幂等**：同一个 `run_id` 记两次还是那一批、还是那几条）；清单为空时抛人话
  异常，不编一批空提案出来。`RunIntakeRecorder` / `runIntakeRecorderProvider` 是界面与工具共用的那一个
  接缝。
- **界面：两条只读路都多一个「交给人确认」**：照片报告与"贴一份 `run/1`"两个对话框的演练读数下面，
  演练真的跑完时按得动，按完说清批次号与条数；按不动、失败都给人话（`_RehearsalReading` 从纯读数变成
  能按的读数）。**这一下仍然只写那两张清单表。**
- **工具同口径**：`check_transcribe_run` 多了 `record`（必须与 `execute: true` 一起，否则直接回人话
  `record 需要 execute: true`），读数里 `recorded_batch`（批次号 + 条数 + 来源）与 `record_problem`，
  摘要说清"这一跑要新建的 N 样东西落成了待确认提案"。AI 在对话里做的是同一件事。
- **后半段不用新界面**：确认那一下走的是材料入库页那条老路（待确认清单 + 「确认入库」→
  `MaterialIntakeRepository.apply`），而清单是按"还有欠账的批次"读的（`readPendingBatches`），所以这一轮
  记下的批次会自己出现在那张单子上 —— 演练 → 交给人确认 → 人点头 → 知识点与线索边真的建起来，这条路
  现在是通的。

**证据**：`app/test/domain/services/ingest/run_knowledge_plan_test.dart` 7 例（轮次九十已落）；
`app/test/features/cognitive/application/run_intake_test.dart` +5 例（真 sqlite：落成清单且知识点一行
没建 / 同一跑记两次还是那一批 / **清单上点头之后真的建出来** —— `created` 2 条、`createdEdges` 1 条、
`lsCalibrated` false；空清单说人话；没跑完整份不算）；`material_intake_page_test.dart` 28 → 30 例
（试跑完按"交给人确认" → 落成待确认清单、知识点一行都还没建 / 没跑完的一跑说人话、清单一行不落）；
`check_transcribe_run_tool_test.dart` 11 → 14 例。本轮 `dart format` 11 个 Dart 文件 3 changed（改完复查
0 changed）；`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**，与八十六～九十同基线）；
全量 `flutter test --concurrency=1` → **+2018 ~2**（轮次九十 `+2001 ~2`，差值 17：+7 +5 +2 +3）。

**已知的没做**：① 谁来决定"这份请求可以执行了"（判断者仍缺：现在"交给人确认"和"人点头"都还是人）；
② `review` / `goal` / `time` 的读数仍然没有出口（它们本来就不建东西）—— **轮次九十三补上了**（`traceReadingOf`
把引擎回报的增量折成人话一行，界面与 AI 工具都摆；读数是现算的，仍然不落库）；③ `ls` 仍没有标定来源；
④ 其余 18 个参数还没有滑块；⑤ 报告里不能"就地改一改再跑" —— **轮次九十二补上了**（照片报告里「改一改再跑」把这份请求带进可编辑的那张，改完照改的那样校验/试跑；动的仍是 JSON 文本，结构化编辑还没有）；⑥ 边提案的 `ls` 照抄增量，`lsCalibrated`
一律 false（"线索边的强度还没有来源"这件事没被这一轮掩盖）。

---

## 2026-10-17 轮次九十：用户拖的那个数，在装了目标机制的每一跑里算数（Lead）

**做了什么**：轮次八十九让用户能拖 `context.goal.beta_goal`，可那个数只走到库诊断那一跑。机制面板上
写着目标机制装在**两处**（库诊断 + 题目定价），卡片上又写着"你调的 1.2" —— 两句话同时成立就成了谎：
题目定价那一跑（`evaluate_problem_fit` / `plan_today` 背后的 `ProblemEvaluator`）仍在用出厂 0.3 算
`V(π)`。这一轮把用户调的值接到"装了它的每一跑"，并让读数说出这一跑用了什么。

- **一条规则**：`MechanismCatalog.goalBetaDefaults({installedIds, moduleDefaults, goalBeta})` ——
  只有 `installedIds` 里真有 `context.goal` 才补那一个键，否则原样返回。库诊断那一跑按
  `libraryDiagnosisIdsFor(goalEnabled:)` 折（开关管着），题目定价那一跑按 `problemEvaluatorIds` 折。
  原先那个 `libraryDiagnosisDefaults` 包装函数**删掉了** —— 它默认"目标机制一定装着"，正是这一轮要堵的谎。
- **工具层只有一处读设置**：`evaluateProblems`（两个 §2-A 工具共用的装配）自己读
  `SettingsRepository(database).getSettings()`、自己折；`EvaluateProblemFitTool` 与 `PlanTodayTool`
  的构造因此多了 `required AppDatabase database`（注册处传 `db`）。"一个用 0.3、一个用 1.2"在结构上不可能。
- **读数要能验收**：`ProblemEvaluationReport` 多了 `moduleDefaults`（空 = 转录默认值一个字没动），
  `evaluate_problem_fit` 的 `modelResult['module_defaults']` 直接带出去；摘要另加一句人话
  （`tunedParametersNote`，"这一跑用的是用户调过的参数：context.goal.beta_goal=1.2"）—— 数字一样要说清
  是谁定的，否则模型会把用户调过的定价当出厂值。`plan_today` 的计划协议（`toJson`）不动，那句人话照加。
- **关掉机制 ≠ 抹掉你调的值**：开关关掉后库诊断那一跑折出来的表是空的（没装的机制不该有参数），
  但数字还留在库里（滑块禁用、位置保留）。
- **面板补一句"这一个数谁会读"**（`mechanismGoalBetaApplies`）：库诊断那一跑与题目定价那一跑都读它，
  工具读数里的 `module_defaults` 就是它（没调过时是空的）。

**证据**：`app/test/features/ai/cognitive_tools_test.dart` +3 例（没调过 → `module_defaults` 为空、摘要
一个字不多说；调过 1.2 → 读数就是 `{'context.goal': {'beta_goal': 1.2}}` 且摘要写
`context.goal.beta_goal=1.2`；**拖到 0 也算"调过"**）；`today_tools_test.dart` +1 例（`plan_today` 的摘要
同口径）；`library_diagnosis_reader_test.dart` +1 例（机制关掉 + 拖过值 → 那一跑 `module_defaults` 为空、
`mechanism_ids` 里没有 `context.goal`，而库里的值还在）；`mechanism_page_test.dart` 的滑块用例多钉一句
"面板写着这一个数谁会读"；`library_diagnosis_test.dart` 两处改用 `goalBetaDefaults(installedIds: …)`。
本轮 `dart format` 16 个 Dart 文件 1 changed（改完复查 0 changed）；`dart analyze lib test` →
`94 issues found`（**0 error / 0 warning**，与八十六～八十九同一条基线）；全量 `flutter test --concurrency=1`
→ **+2001 ~2**（轮次八十九 `+1996 ~2`，差值 5：+3 +1 +1）。

**已知的没做**：① 谁来决定"这份请求可以执行了"（判断者仍缺）；② 执行完怎么落库；③ `ls` 仍没有标定来源；
④ 其余 18 个参数还没有滑块（而且不该铺开：19 个参数里只有 2 个写着"有出处"，先要的是标定，不是更多旋钮）；
⑤ 报告里不能"就地改一改再跑" —— **轮次九十二补上了**（照片报告里「改一改再跑」把这份请求带进可编辑的那张，改完照改的那样校验/试跑；动的仍是 JSON 文本，结构化编辑还没有）。

---

## 2026-10-17 轮次八十九：第一个滑块 —— 目标机制的牵引强度（Lead）

**做了什么**：轮次八十六给了用户一个开关（装不装目标机制），可"装"只有两个档：开或关。机制参数表里
那十九个数字，用户一个都碰不到 —— 面板只把"被覆盖/未标定"摆出来给人看。这一轮开了第一个**滑块**：
`context.goal.beta_goal`（目标偏置强度）可以由用户拖。与开关一样，只写一行设置、只在装配时生效，
**引擎真的读它**，读数里带得出来。

- **两端不是我们编的**：`FastParamSpec` 本来就带 `min`/`max`/`defaultValue`/`desc`/`evidence`。
  `beta_goal` 是默认 `0.3`、范围 `[0, 3]`、`desc: '目标偏置强度'`、`evidence: '未标定（Application_Protocol §15）'`
  —— 滑块的下界上界、出厂位置全部来自内核参数表（`MechanismCatalog.goalBetaPath` / `goalBetaKey` /
  `transcribedGoalBeta` 也都从这里来），页面不自己编一个"看起来合理"的区间。
- **NULL = 没调过**：`local_settings.goal_beta` 是可空的 REAL（schema v21 → **v22**），NULL 读作"用转录
  默认值"。`_upgradeV21ToV22` 走的是与 v21 那列同一条链（`_addColumnIfMissing` + `_ensureColumns`
  自愈），升级上来的老库不会因为多一列而丢设置。
- **进引擎走的是本来就有的那条通道**：机制装配一直有 `moduleDefaults`（`overrides > moduleDefaults >
  转录默认值`）。`MechanismCatalog.libraryDiagnosisDefaults(goalBeta: v)` 只有在调过的时候才给出
  `{context.goal: {beta_goal: v}}`；库诊断那一跑（`LibraryDiagnosisRunner.run(moduleDefaults: …)`）
  真拿它去装配，读数 `module_defaults` 照实带出来 —— 没调过的那次是空的（一个默认值都不传），
  没跑起来的那次也是空的（没用的东西不写进读数）。
- **面板同时说清三件事**：卡片上是"你调的 1.2"（还给一个「回到出厂值」写回 NULL）；参数行上的徽标是
  `fromSetting`（与 `overridden` 分开 —— 被装配覆盖和被你调不是一回事），转录默认值那行**不动**。
- **开关与滑块互不干扰**：把机制关掉不等于抹掉你拖的值 —— 滑块禁用但位置还在（`OffNote` 明说"关的是
  装不装，不是值"），关着的时候读数里照样是你调过的数。
- **只读边界没变**：这一轮加的是"引擎用哪个数字"，演练与诊断仍然一个字都不写库。

**证据**：`app/test/features/cognitive/presentation/mechanism_page_test.dart` 11 → **17 例**（出厂位置
0.3 / 两端 0/3 来自参数表；调过之后标"你调的"且转录默认值不变；拖一下只回调一次且页面当场按新值画；
「回到出厂值」回调收到 `null` 而不是 0.3；机制关掉时滑块禁用但位置保留；真库那条钉"拖了落库、写回
NULL"）；`mechanism_reader_test.dart` +4 例（`goalBeta` 进 `moduleDefaults` 且只多这一个键；转录默认值
不被设置改写；开关与滑块互不干扰；参数总数一个不少）；`test/domain/services/cognitive/library_diagnosis_test.dart`
+4 例（没调过不传默认值 / 调过只传那一个键且 `mechanism_ids` 不变 / 没跑起来时 `module_defaults` 为空）；
`test/features/cognitive/application/library_diagnosis_reader_test.dart` +3 例（NULL = 出厂值；调过之后
读数里就是那个值且机制清单不变；写回 NULL 之后键就没了）；新建
`app/test/data/database/v22_migration_test.dart` **2 例**（真 v21 文件升级后新列可用、老设置一行不少；
被盖成 v22 却没有这一列的文件靠自愈补上并能写进去）；6 个新 l10n 键（zh/en + 三个生成文件手改）。
本轮 `dart format` 17 个 Dart 文件 7 changed（改完 `--set-exit-if-changed` exit 0）；`dart analyze lib test` →
`94 issues found`（**0 error / 0 warning**，与轮次八十六/八十七/八十八同一条基线）；全量
`flutter test --concurrency=1` → **+1996 ~2**（轮次八十八 `+1977 ~2`，差值 19：+6 +4 +4 +3 +2）。

**已知的没做**：① 谁来决定"这份请求可以执行了"（判断者仍缺：现在按按钮的仍是人）；② 执行完怎么落库；
③ `ls` 仍没有标定来源（§3 第 7 行那六条实验，需要外部数据）；④ "用户侧开关/滑块"到此才各有一个
（目标机制），其余十八个参数还没有滑块 —— 而且滑块**不该**铺开：参数表里 17 个写着"未标定"，
给用户一个没出处的旋钮与"面板如实说"是同一件事的两面，先要的是标定，不是更多旋钮；⑤ 报告里不能
"就地改一改再跑"；⑥ 当时这个数**只在库诊断那一跑生效**，题目定价那一跑（`evaluate_problem_fit` /
`plan_today`）还没读设置 —— **已在轮次九十补上（同一处装配读同一份设置，读数带 `module_defaults`）**。

---

**做了什么**：轮次八十七把演练接进了照片那条路，可 `run/1` 请求不是照片的专属产物 —— AI 工具
`check_transcribe_run` 会产、别处的模型会话会产、用户自己也可能手写一份。这些请求在界面上没有落脚处：
"先校验，再试跑"藏在照相机后面。这一轮给材料摄取页加了第二条只读入口：**把一份 `mindnet.run/1` 贴进去**，
校验与试跑走的是与照片那条路同一套（`reviewTranscribedRun` / `rehearseRun`），一个字都不写库。

- **两个入口，一套判定**：`_RunRequestDialog`（`material_intake_page.dart`）只做三件事 —— 贴文本、按
  「校验这份请求」、合法就按「试跑一遍」。解码 `decodeRunRequest(extractJsonObject(text))`、自检
  `reviewTranscribedRun(request, existingNodeIds:, existingEdgeIds:)`，与照片那条路**同函数同口径**：
  两条路的差别只是"请求从哪来"，不是"怎么判"（`D2`）。
- **图清单照旧从库里现读**：按按钮时先读 `graphPoints()`/`all()` 拿"已有的节点/边 id"——"这条动作说的
  id 库里有没有"必须按真实的图判；读不出来就说人话（新键 `materialIntakeRunGraphFailed`）。
- **读不成 vs 不合法，分开说**：`FormatException` 是读不成（摆解码器那句人话、没有试跑按钮）；读得成
  但不合法是硬错（照摆 `errors`，也没有按钮）—— 先修它，别急着跑。
- **只读的按钮在不在，本身是读数**：与照片那条路一致，`report.ok` 才有「试跑一遍」；跑的是同一个
  `runRehearsalRunnerProvider` 接缝（测试注入真 `rehearseRun`：同一个库、同一个 `CognitiveModel`）。
- **一处改名**：`_notePhotoProblem` → `_noteIntakeProblem`（两条只读入口共用一行提示）。

**证据**：`app/test/features/cognitive/presentation/material_intake_page_test.dart` 25 → **28 例**
（贴一份合法请求 → 合法 + 会做什么 → 试跑真的进引擎且 `knowledge_edges`/`material_intake_proposals`
都空、`knowledge_points` 仍 1 条；贴"这不是信封" → 只说解码器那句、不给按钮；贴一份 `kind: unknown`
的请求 → 摆硬错、不给按钮）；6 个新 l10n 键（zh/en + 三个生成文件手改）。本轮 `dart format` 5 个 Dart
文件 0 changed；`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**，与轮次八十六/
八十七同一条基线）；全量 `flutter test --concurrency=1` → **+1977 ~2**（轮次八十七 `+1974 ~2`，
差值 3：页面 +3）。

**已知的没做**：① 谁来决定"这份请求可以执行了"（判断者仍缺：现在按按钮的仍是人）；② 执行完怎么落库；
③ `ls` 仍没有标定来源（§3 第 7 行那六条实验，需要外部数据）；④ "用户侧开关/滑块"只做了一个开关
（目标机制），滑块还没有设计；⑤ **报告里不能"就地改一改再跑"** —— 贴进来的这一条可以改文本再校验一次，
照片那条路只能回去改模型原话，没有结构化的字段级编辑入口。

---

## 2026-10-17 轮次八十七：照片报告里「试跑一遍」—— 演练从工具走到界面（Lead）

**做了什么**：演练层（轮次八十五）把"谁去装配引擎"答了，可从那天起它只有一个入口：AI 工具
`check_transcribe_run` 的 `execute` 参数。用户在界面上看不到 —— 读完一张照片，屏幕上只有"合不合法"，
"这份请求跑起来会怎样"仍然只在模型对话里才有。这一轮把两件事接起来：**合法的那一份，报告里按一下
就能真的走一遍**，走的还是那条只读的路。

- **原件随报告走**：`PhotoTranscribeReport`（`app/lib/features/cognitive/application/photo_transcribe_service.dart`）
  多了 `request` —— 解码出来的那份 `MaterialRunRequest`。带上它不是为了好看：界面要拿它去试跑，
  而唯一的正确来源是解码器；让界面把 `rawText` 再解一遍就是两处解析、两份真相。
- **怎么跑是一个接缝**：`runRehearsalRunnerProvider`（`material_intake_page.dart`，与
  `photoPickerProvider`/`visionEncoderProvider` 同一套做法）= "用哪个库、哪个模型"；真实现就是
  同一个 `AppDatabase`、同一个 `CognitiveModel` 调 `rehearseRun`，**只读、不落库**。
- **摆的是引擎的原话**：报告里就地展开，不另开对话框 —— 每条动作一行 `RunActionTrace.text`（"这一条
  实际做了什么/为什么停在这"），另加 `nodesWithoutMs`（库里读不出 `r0`、引擎按默认 0.8 算的节点）与
  `unknownNodeIds`（库里没有、也没动作去建的 id）各一行，最后一句"只读演练：不写知识点、不写边、
  不动复习记录"。
- **失败不带走报告**：试跑抛了就照实说人话（原话留着），自检结果仍在屏幕上、按钮还能再按 ——
  "这份请求合不合法"和"引擎跑不跑得完"是两件事。对话框为此从 `StatelessWidget` 变
  `StatefulWidget`（`_rehearsing`/`_rehearsal`/`_rehearsalProblem` 三个状态）。
- **不合法就不摆按钮**：自检没过的请求没有试跑入口（跑它没有意义）—— 于是"按钮在不在"本身也成了
  一条读数：在 = 这份请求在引擎眼里是活的。

**证据**：`app/test/features/cognitive/presentation/material_intake_page_test.dart` 22 → **25 例**
（真的跑进引擎且库一个字节都没变（`knowledge_edges`/`material_intake_proposals` 都空、
`knowledge_points` 仍只有那 1 条）、`kp` 没有卡片时"模型读数读不出来"要明说、试跑炸了报告还在且能再按、
不合法的那份不摆按钮且不许被拿去跑）；`app/test/features/cognitive/application/photo_transcribe_service_test.dart`
12 例不变，但"读成一份请求"那条多钉一句：报告里带着解码出来的 `request`。
本轮 `dart format` 7 个 Dart 文件 0 changed（`--set-exit-if-changed` 复查 exit 0）；`dart analyze lib test` →
`94 issues found`（**0 error / 0 warning**，与轮次八十六同一条基线）；全量
`flutter test --concurrency=1` → **+1974 ~2**（轮次八十六 `+1971 ~2`，差值 3：页面 +3）。

**已知的没做**：① 谁来决定"这份请求可以执行了"（判断者仍缺：现在按按钮的仍然是人）；② 执行完怎么
落库；③ `ls` 仍没有标定来源（§3 第 7 行那六条实验，需要外部数据）；④ "用户侧开关/滑块"只做了一个
开关（目标机制），滑块还没有设计；⑤ 演练只接进了**照片**这一条路 —— 贴信封那条路还看不到"这份信封
跑起来会怎样"，报告里也不能改一改再跑（要改就得回去改模型原话）。

---

## 2026-10-17 轮次八十六：机制开关 —— 用户说"不装目标机制"，引擎就真的不装（Lead）

**做了什么**：机制面板（轮次八十四）把"引擎装了哪些机制"公开了，但它是只读的 —— "可插拔"只有
一半。这一轮补上 §3 第 8 行要的另一半里的第一个开关：**库诊断那一跑装不装目标机制**
（`context.goal`）。选它是因为这一处关掉之后读数仍然是读数（起点/目标是用户给的，没有目标机制
只是"拉不过去"），而另外三个机制撑着那一跑本身，关掉就是让读数撒谎。开关只作用于**一处装配**：
题目定价那一跑仍然装它。

- **落库**：`local_settings.goal_mechanism_enabled`（可空 bool），schema **v21**。**NULL = 用户从
  没选过 = 装** —— 这个开关出现之前所有版本都这么跑，迁移不许替用户把引擎换掉（与
  `rhythm_hints_enabled` 同一条规矩）。`_upgradeV20ToV21` 只加列，`_ensureColumns` 负责
  "版本号跑在列前面"的自愈。面板文案也写明这一条："没选过 = 装"。
- **一个来源**：`MechanismCatalog.libraryDiagnosisIdsFor({required bool goalEnabled})` 是唯一的
  算法（关掉只去掉 `context.goal`）；`LibraryDiagnosisRunner.run()` 多了 `goalMechanismEnabled`，
  把**这一次真的装了哪几个**写进读数 `mechanismIds` 与 JSON `mechanism_ids`。没跑起来的那两次
  （没有图 / 没有可用起点）写空清单，不是"装了默认的"。
- **读数自己说得清**：`readLibraryDiagnosis` 自己读设置（页面 provider 与 AI 工具走同一条路，
  不会有人忘了传）；`readMechanismPanel(goalMechanismEnabled:)` 给每个机制行加了
  `disabledIn`/`disabledBySetting`，把"你关掉了（出厂会装）"和"本来就没装"分开说。**开关打开时
  这份清单必须是空的** —— 这条抓到一个真 bug：读数忘了把开关传给 `setupsDisabledBySetting`，
  于是开关开着时卡片仍然声称"你关掉了"。
- **面板能翻**：`mechanism_page.dart` 从无状态变 `ConsumerStatefulWidget`，读数走
  `mechanismPanelProvider`、开关值走 `goalMechanismEnabledProvider`；翻一下只写这一行设置，然后
  invalidate 两个 provider。用户刚翻的值先用 `_picked` 画出来（写库是一次往返，开关不能自己弹
  回去）。原来那句"面板只读"改成"面板只写这一个开关，不写别的表"。
- **两句话都要说**：目标机制仍然装在题目定价那一跑里，所以卡片既写"装在哪几处"，也另起一行写
  "你关掉了 · 库诊断那一跑" —— 只写前半句，用户翻开关时看不到自己拿掉了什么。

**证据**：`app/test/data/database/v21_migration_test.dart` **2 例**（真实 v20 文件升级后老设置一行
不少、新列落成 NULL，用户选了之后两个方向都写得进去；被盖成 v21 却缺列的文件靠 `beforeOpen`
自愈）；`app/test/domain/services/cognitive/library_diagnosis_test.dart` **+4 例**；
`app/test/features/cognitive/application/mechanism_reader_test.dart` 12 → **16 例**；
`app/test/features/cognitive/application/library_diagnosis_reader_test.dart` **+3 例**；
`app/test/features/cognitive/presentation/mechanism_page_test.dart` 7 → **11 例**（含**真 sqlite**
那条：翻开关把 `local_settings` 写成 false，面板重读后那一跑只剩 3 个机制）。
`dart format` 本轮 16 个 Dart 文件 2 changed（改完 0 changed）；`dart analyze lib test` →
`94 issues found`（**0 error / 0 warning**）；全量 `flutter test --concurrency=1` → **+1971 ~2**
（轮次八十五 `+1954 ~2`，差值 17：库诊断 +4、面板读数 +4、诊断读数 +3、面板页 +4、迁移 +2）。

**已知的没做**：① 谁来决定"这份请求可以执行了"（判断者仍缺）；② 执行完怎么落库；③ `ls` 仍没有
标定来源（§3 第 7 行那六条实验，需要外部数据）；④ "用户侧开关/滑块"只做了一个开关（目标机制），
别的机制还没有开关语义，滑块也还没有设计。

---

## 2026-10-17 轮次八十五：演练 —— 那份 `run/1` 请求真的跑进引擎（Lead）

**做了什么**：`run_executor.dart`（轮次七十八）把"请求 → 引擎"修到了头，可从那天起它**没有调用者**——
"谁来决定这份请求可以执行了"一直挂在"已知的没做"①上。这一轮不碰那个判断（那是设计问题），只回答
它下面那半句更小的：**谁去装配那个引擎**。答案用的是已经存在的只读工具 `check_transcribe_run`：
它原本只校验，现在多一个 `execute` 参数，给了就在校验通过之后顺手把请求真的跑一遍。

- **新层**（`app/lib/features/cognitive/application/run_rehearsal.dart`）：
  `rehearseRun({request, db, model, now, anchor})` → `RunRehearsal{report, seedNodeIds,
  seedEdgeIds, nodesWithoutMs, unknownNodeIds}`，`report` 就是 `executeRun` 的报告。
- **图先摆好**：请求提到的节点（`review`/`exposure` 的 node、`goal` 的 starts/targets、边提到的
  那两端）按请求自己的 id 空间摆进仿真图，节点 `ms` 用库里那张代表卡片的模型读数
  （`representativeCardRow` + `CognitiveModel.modelReadingOf(row, nowHours:).r0`）——与库诊断同一个
  来源；读不出来就**省略**（引擎按 0.8），并记进 `nodesWithoutMs`，不替它编一个数。请求自己会建的
  节点（`knowledge` 动作）**不先摆**：重复建同一个 id 会抛，那是真实行为，让执行报告如实报出来。
- **边也摆好**：`knowledge_edges` 里两端都已经进图的那些边才接过来（一端不在，那条边在演练里也走不通）。
- **只装记忆层**：`executeRun` 只 apply 动作、不跑轮次，逐轮那四个机制一个也用不上，所以
  `MechanismCatalog.runRehearsalIds = [memory.dsr]` —— 机制面板因此如实多列第三处装配。
- **只跑不落库**（刻意）：`knowledge_points` / `knowledge_edges` / `card_states` / 记忆态一个字都不动。
  把演练结果落库是另一件事（已知的没做②）。
- 诚实的边界写进 library doc：库里的复习历史**没有**变成记忆袋（仿真图上的袋子从默认状态起算，`ms`
  只决定节点自己的读数起点），所以演练回答的是"这份请求会落在哪条机制路径上、动到哪些数"，不是
  "你的真实进度会变成多少"。
- 工具那一侧（`app/lib/features/ai/tools/ingest_tools.dart` 的 `CheckTranscribeRunTool`）：`execute`
  缺省 `false`（结果里只有原来那份校验 + 一句"要真的跑一遍，给 `execute: true`"）；给了才跑，结果多
  一个 `rehearsal` 对象（`report` + 图里摆了什么 + 哪些节点没有 `ms` + 哪些节点库里没有），`ok` 跟
  执行报告的 `ok` 走，`error` 用停在的那条动作的原话（比如 `review` 没给 `at` 就是"缺少时间基…"）。
  `ToolRegistry.forApp` 把 `db`/`model`/`clock` 一起传进这个工具。

**测试钉住的纪律**：`app/test/features/cognitive/application/run_rehearsal_test.dart` **12 例**
（先建后复习时 `changedCount 2` 而 `touchedMechanisms 1`（建节点不算动机制）、没有卡片就省略 `ms`
并记进 `nodesWithoutMs`、边两端都在才接过来、请求自己的 `time.model_hours` 就是锚点、只给 `at.wall`
没有锚点就如实停在第一条、"没有模型读数"是校验层的事（执行层只活到第一条）、演练不写库）；
`app/test/features/ai/check_transcribe_run_tool_test.dart` 8 → **11 例**（不给 `execute` 就不会有
`rehearsal` 键、给了就真跑且库不动、空库时第一条就停在 `unknown_node_ids`）；
`app/test/features/cognitive/presentation/mechanism_page_test.dart` **7 例**（三处装配的 id 清单与名字）。
三个文件合跑 `+30`。写第一版时抓到一处名不副实：`touchedMechanisms` 原本按"增量非空"算，而建节点/
建边/推时钟都算增量 —— 改成只有增量里带着机制名（`mechanism: 'memory.dsr'`）才算"动了机制"，另加
`changedCount` 如实说"留下了增量"。

**证据**：`flutter test test/features/cognitive/application/run_rehearsal_test.dart
test/features/cognitive/presentation/mechanism_page_test.dart test/features/ai/check_transcribe_run_tool_test.dart`
→ `+30`；`dart format` 本轮 11 个 Dart 文件 2 changed（改完 0 changed）；`dart analyze lib test` →
`94 issues found`（**0 error / 0 warning**）；全量 `flutter test --concurrency=1` → `+1954 ~2`
（轮次八十四 `+1939 ~2`，差值 15）。

**已知的没做**：① 谁来决定"这份请求可以执行了"—— 现在**有调用者了，但不是判断者**：`execute` 是用户
在对话里给的参数，没有任何一层替用户下"这批复习可以执行"的结论；② 执行完怎么落库（演练刻意不写，
包括记忆袋）；③ `ls` 仍没有标定来源（§3 第 7 行那六条实验，需要外部数据）；④ 机制面板只有读，没有
"用户侧开关/滑块"（§3 第 8 行的另一半，要落库 + 验收契约）—— **已在轮次八十六补上第一个开关
（目标机制，落库 + 验收契约都在），"滑块"仍缺**。

## 2026-10-17 轮次八十四：机制面板 —— 引擎装了哪些机制、每个参数是多少、哪些还没标定（Lead）

**做了什么**：这台机器有一条硬规矩 —— **所有算法参数对用户公开**（`docs/DESIGN_BLUEPRINT.md` 的 P5，
也是 roadmap §3 第 8 行「机制插件化」里"用户侧"的那一半）。而在这一轮之前，"引擎装了哪些机制、
每个数字是多少、哪些是未标定的占位值"只活在 `app/lib/domain/services/cognitive/fast_engine.dart`
的转录表里：用户能看见"发展区/瓶颈"这些结论，看不见产生它们的那些数。这一轮把装法、参数、
未标定标记搬到界面上（**只读**）。

- **装配的事实收成一处**（`app/lib/domain/services/cognitive/mechanism_catalog.dart`）：
  `library_diagnosis` 装四个机制（`dynamics.shunting` / `attention.capacity` / `attention.ignition` /
  `context.goal`），`problem_evaluator` 多装一层 `memory.dsr`；两处唯一的覆盖是
  `attention.ignition.T_ign = 0`（D3 去随机源：点火退化成硬阈值，不掷随机数）。原先这两处各写一份
  id 清单 + 覆盖 map，现在都读这份常量 —— 面板**不可能**和引擎说的不一样（"面板"的老毛病就是抄一份
  然后漂移）。
- **读数纯函数**（`app/lib/features/cognitive/application/mechanism_reader.dart`）：
  `readMechanismPanel({moduleDefaults})` 不碰数据库；`value` = 覆盖 > `module_defaults` > 转录默认值，
  `transcribed` 必须用**空 defaults 单独读一遍** `FastMechanisms`（`fromModuleDefaults` 会把传进来的
  默认值写进 `FastParamSpec.defaultValue`，那一份读到的已经不是"转录"了 —— 写测试时才发现）。
- **页面**（`app/lib/features/cognitive/presentation/mechanism_page.dart`）：入口在
  `cognitive_model_page.dart` 的 AppBar（`Icons.tune`）。两段装配卡 + 六段机制卡：内核 id
  （`attention.capacity` 这种写法）+ 界面名 + "装在哪" + 每个参数一行（路径、值、
  「未标定」/「已标定」、被覆盖时另给转录默认值、范围、`desc` 与 `evidence` 原话），末尾一句总数
  "N 个参数，其中 M 个未标定"。
- **两条如实说**：`rhythm.gate` 只活在节律读数里（`StudyRhythm.read` 直接建 `RhythmGate`），
  **不装进任何引擎**，面板不说它"装了"；`memory.dsr` **一个号参数都没有**（只维护每个节点的状态袋
  `node.m['memory_dsr']`），面板不空着、也不编参数。
- **只读是刻意的**：这一页不写库、没有开关。"用户侧开关/滑块"（§3 第 8 行）要先把开关落库
  （settings 列 + schema 迁移）并配一条可跑的验收契约，是另一轮的事 —— **轮次八十六做了这件事：
  面板多了目标机制开关（schema v21 `local_settings.goal_mechanism_enabled`）**。

**测试钉住的纪律**：`app/test/features/cognitive/application/mechanism_reader_test.dart` **10 例**
（面板列出的机制与参数逐条等于 `FastMechanisms` 的转录表、未标定个数与引擎同口径、两处装配的 id
清单、`T_ign` 值 `0` 而转录 `0.05`、别的参数没被覆盖、`rhythm.gate` 不装进任何引擎、
`memory.dsr` 没有号参数、`module_defaults` 传值时实际值变而转录默认值不变）；
`app/test/features/cognitive/presentation/mechanism_page_test.dart` **7 例**（两处装配 + 六个机制名、
点火阈值那行、记忆层那段、节律闸门那段、末尾总数与读数一致、"已标定"也出现、id 用内核写法）。
写第一版时抓到两个真问题：读数没把覆盖传进 `FastMechanisms`（`T_ign` 显示成 `0.05`）、
`transcribed` 拿了被 defaults 改写过的那份。

**证据**：`flutter test test/domain/services/cognitive/ test/features/cognitive/` → `+337`；
`dart format` 本轮 11 个 Dart 文件 4 changed（改完 0 changed；`.arb` 不能喂 `dart format`）；
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）；全量
`flutter test --concurrency=1` → `+1939 ~2`（轮次八十三 `+1922 ~2`，差值 17 = 10 例读数 + 7 例页面）。

**已知的没做**：① 执行层（`run_executor.dart`）仍然**没有调用者**（轮次七十八 ①）—— **已在轮次八十五补上调用者（`check_transcribe_run` 的 `execute`），"判断者"仍缺**；**轮次八十七起这条演练在照片报告里也按得到（只读、仍不落库）**；② 执行完怎么
落库；③ `ls` 仍没有标定来源（§3 第 7 行那六条实验，需要外部数据）；④ 机制面板只有读，没有
"用户侧开关/滑块"（§3 第 8 行的另一半，要落库 + 验收契约）—— **已在轮次八十六补上第一个开关
（目标机制），"滑块"仍缺**。

## 2026-10-17 轮次八十三：撤回流水点得开 —— 那一次撤掉了什么、为什么没撤成（Lead）

**做了什么**：轮次八十二把"撤过"记成了流水，但界面上只有一行"这一批撤回过 N 次"—— 这行字说的是
**有**这回事，看不出**是哪回事**（轮次八十二把它记成「还没做 ③」）。而流水落库时记下的恰恰是那两样
东西。这一轮把那一行变成入口：点开一个只读对话框，把已经躺在库里的东西按倒序摆出来。
**不新增任何落库、不加任何写路径。**

- **撤成那次摆原件原话**：`· <知识点标题>`（`MaterialAppliedPoint.title`）与
  `· <fromId> → <toId>`（`MaterialAppliedEdge` 的两端）—— 都是撤回那一刻从库里读出来的行内容，
  所以"那次到底删了什么"不靠回忆；没有自己新建的行时照实说"这一批没有自己新建的行"。
- **没撤成那次摆"为什么"**：`没能撤：<第一条理由>（当时 N 条理由）`。只有第一条理由落库（轮次八十二
  的明确不做），`N` 也是那时数出来的 —— 所以这里说得出"当时一共几条"、说不出每一条；完整清单在
  下一次点撤回时照样逐条给。
- **流水不是回放**：对话框只读，关掉之后这一批仍然是"待确认"（`applied_at` 照旧为空），不会因为
  "看得见"就把行变回来。时刻是 `MM-dd HH:mm`，每行 `Icons.undo` / `Icons.block` 各对一半。
- **l10n 5 个新键**（zh/en 的 ARB + 手改三个生成文件，没跑 gen-l10n）：`materialIntakeUndoLogTitle`
  （撤回流水）、`materialIntakeUndoLogNote`（撤成记什么、没撤成记什么）、`materialIntakeUndoLogDone`
  （撤成了）、`materialIntakeUndoLogNotDone`（没撤成）、`materialIntakeUndoLogBlocked(reason, count)`。
- **明确不做**：不做"撤销的撤销"（看流水不改流水）、不把完整理由列表存进流水、不进 `review_logs`。

**测试钉住的纪律**（`app/test/features/cognitive/presentation/material_intake_page_test.dart`
21 → **22 例**）：① 撤回之后那行点开，看得见"删掉了什么"（2 个知识点 + 2 条线索边）与
`已撤回：…`一行；② 看完还是"没确认"（流水不是回放）；③ 清空再恢复，那行跟着回来（账在库里）；
④ 没撤成那次也点得开，看得见理由与"当时 N 条理由"，卡片挪走后再撤一次成功 —— 两次都在这批的
流水里。两个踩到的坑：新断言必须用 `find.descendant(of: find.byType(AlertDialog), …)` 收窄
（对话框背后还摆着同一份成绩单，`find.text` 会撞 2 个）；`materialIntakeUndoLogNote` 的正文里
含"撤成了/没撤成"，所以标题断言要写成 `' · ${l10n.materialIntakeUndoLogDone}'`。

**证据**：`dart format` 本轮文件 1 changed（改完 0 changed；`.arb` 不能喂 `dart format`）；`dart analyze
lib test` → `94 issues found`（**0 error / 0 warning**）；全量 `flutter test --concurrency=1` →
`+1922 ~2`（轮次八十二 `+1921 ~2`，差值 1）；页面测试单跑 `+22: All tests passed!`。

**已知的没做**：① 执行层（`run_executor.dart`）仍然**没有调用者**（轮次七十八 ①）—— **已在轮次八十五补上调用者（`check_transcribe_run` 的 `execute`），"判断者"仍缺**；**轮次八十七起这条演练在照片报告里也按得到（只读、仍不落库）**；② 执行完怎么
落库；③ `ls` 仍没有标定来源（§3 第 7 行那六条实验，需要外部数据）。

---

## 2026-10-17 轮次八十二：撤过就有痕迹 —— 撤回记账（Lead）

**做了什么**：轮次七十九的「撤销一次确认」把行删了、把 `applied_at` 清空 —— 这是它**唯一**留下的
痕迹。于是"这批怎么又回到待确认里了"在库里查不出来：可能压根没确认过，也可能确认过又反悔了，两种
情况的库长得一模一样（轮次七十九把它记成「还没做 ①撤销不记账」）。这一轮补上：schema **v20** 新表
`material_intake_undo_logs`，撤回**成与不成**都留一笔，页面在提案清单上面说清"这一批撤回过几次"。

- **撤成与没撤成都记一笔**：撤不掉时 `undone = false`、`removed*` 为空、`blockedCount` 与第一条
  理由留下 —— "点了撤回但库里一个字没动"也是发生过的事，只记成功那一半会让"为什么没变化"变成
  第二桩查不出来的事。
- **记成流水（一次一行），不记成状态列**：同一批可以撤很多次（撤了 → 再确认 → 再撤），状态列说不清
  次数；对比 `already_existed` —— 那句判断只在"上一次点头"那一刻成立，所以必须落库，而"撤过没有"
  是流水数得出来的派生量。
- **写的地方只有一个**：`MaterialIntakeRepository.undoBatch` 自己（删行与记账同一个事务；撤不掉那条
  路径在事务外补记一行），页面不写、只读 `undoLogs(batchId)`（按 `requestedAt` 升序、同毫秒按自增
  id —— 它是一条时间线）。
- **界面**：从清单恢复 / 刚预览一批时顺手读一次这一批的流水数，`> 0` 就在提案清单上面多一行
  `l10n.materialIntakeUndoLogLine(n)`（"这一批撤回过 N 次"）；撤回成功的那一次当场 +1。
- **明确不做**：`blocked` 每条理由都存（只存第一条）、不进 `review_logs`（撤回不是一次复习，混进去
  会把记忆层的读数带脏）、不做"撤销的撤销"。

**测试钉住的纪律**（`app/test/data/repositories/material_intake_repository_test.dart` 20 → **25 例**；
`app/test/features/cognitive/presentation/material_intake_page_test.dart` 20 → **21 例**）：① 撤成的把
删了什么记全；② 没撤成也记一笔、而且库一个字没动；③ 撤两次记两行；④ 没确认过的批次也留一行；
⑤ 同一毫秒按写入次序排（自增 id 兜底）；⑥ 页面：撤回之后那行出现、清空后消失、从清单恢复又跟着
回来（账落在库里，不看内存）。

**证据**：`dart format` 本轮文件 3 changed（改完 0 changed）；`dart analyze lib test` → `94 issues
found`（**0 error / 0 warning**）；全量 `flutter test --concurrency=1` → `+1921 ~2`（轮次八十一
`+1915 ~2`，差值 6）；两文件合跑 `+46: All tests passed!`。

**已知的没做**：① 执行层（`run_executor.dart`）仍然**没有调用者**（轮次七十八 ①）—— **已在轮次八十五补上调用者（`check_transcribe_run` 的 `execute`），"判断者"仍缺**；**轮次八十七起这条演练在照片报告里也按得到（只读、仍不落库）**；② 执行完怎么
落库；③ 撤回流水只有"撤过几次"这一行，还没有点开看"那次撤掉了什么、为什么没撤成"的入口
（**已在轮次八十三补上**）；④ `ls` 仍没有标定来源（§3 第 7 行那六条实验，需要外部数据）。

---

## 2026-10-17 轮次八十一：照片读完能原地再来一张 —— 报告里就有「换一张」（Lead）

**做了什么**：照片这条路从轮次七十七起就按得到了，但报告是**死胡同**：读成了想换一张、或者读不成
想再试一次，都只能先「关闭」，再回到页面上找那个「选一张照片」—— 轮次七十六 ② 那句"现在读不成只能
出去再按一次"说的就是它。这一轮把这一步挪进报告里：**读成了 →「换一张」；没读成 →「重试」**
（同一个按钮，两句话 —— 成功和失败时用户心里的词不一样）。按下去就关掉这个对话框、重新选照片、
重新读一遍，第二张的报告还摆在原来那个位置。

- **一个按钮，两句话**：`materialPhotoReportPickAnother`（"换一张"）/ `materialPhotoReportRetry`
  （"重试"），由报告是 `PhotoTranscribeReport` 还是 `PhotoTranscribeFailure` 决定；图标也跟着换。
- **"模型都没配好"这一种不摆这个按钮**（`PhotoTranscribeProblem.notConfigured`）：按一次还是同一句话
  （那张对话框里已经说了"先去 AI 设置里配好模型"），摆着只会让人白按一下。
- **对话框还是纯报告**：`_PhotoReportDialog(onAnother:)` —— 回调为空就没有这个按钮，"执行"仍然不是
  它的事；要执行得先把这份请求拿去走 `run/1`（轮次七十八 ① 那个"调用者"还没定）。
- **照片这条路仍然只读**：换十张也一样，不执行 `run/1`、不写库（测试里两次读完仍然是空的
  `knowledge_edges` / `material_intake_proposals`）。

**测试钉住的纪律**（`app/test/features/cognitive/presentation/material_intake_page_test.dart` 18 → **20 例**）：
① "换一张"按下之后真的再选、再发一次、报告换新（按两次 → `picks == 2`），两次都一个字没写库；
② "重试"从读不成到读成，算数的是**第二张**的结果（失败那句消失）；③ 另外把"没配模型"那一例钉住
`findsNothing`（没有重试按钮）。新测试第一版红在报告自己的话上：`结构上不合法：整份会被拒绝 ——
第 1 条 action（review）指向图里不存在的节点 "kp"` —— `runJson()` 里的 `review` 指向 `kp`，而我没先
种这个点（成功那一例一直是先 `anki.createKnowledgePoint(externalId: 'kp')` 的）。

**证据**：`dart format` 本轮文件 2 changed（改完 0 changed —— 顺带记下：`dart format` 不能喂 `.arb`，
那是 JSON，会被跳过并报 parse 警告；整树 `dart format lib test` 会重排 155 个无关文件，绝不能再来）；
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）；全量 `flutter test --concurrency=1`
→ `+1915 ~2: All tests passed!`（轮次八十 `+1913 ~2`，差值 2）。

**已知的没做**：① 谁来决定"这份请求（`run/1`）可以执行了" —— 执行层仍然没有调用者（轮次七十八 ①）—— **已在轮次八十五补上调用者，"判断者"仍缺**；**轮次八十七起这条演练在照片报告里也按得到（只读、仍不落库）**；
② 执行完怎么落库；③ 撤销不记账、也不进审计（轮次七十九 ①②）—— **已在轮次八十二补上**（撤回
流水 `material_intake_undo_logs`，撤成与没撤成都留一笔）；④ `ls` 仍没有标定来源（roadmap §3
第 7 行那六条实验，需要外部数据）；⑤ 本轮只在"照片 → 报告"这条路上做了，纸质流程的其它入口没动。

---

## 2026-10-17 轮次八十：落不了的连接看得见 —— 点头之前就知道（Lead）

**做了什么**：上一轮回答"点错了怎么办"，这一轮回答更早的那一步 —— **别白点**。"这条连接落不了"
（有一端不在图里）以前只有确认**之后**的成绩单才会说（"N 条连接落不了"），那时用户已经按过一次；
更别扭的是这种连接**永远不会进历史**（它没被写下去），所以"哪几条是这次落不了的"在界面上根本没有
地方看。这一轮把这句话放回它该在的地方：**待确认清单**上逐条标出来。

- **判据是一处，不是两处**：`MaterialIntakeRepository.missingEndpointNote(...)`（起点 / 终点 / 两端
  三种说法）与 `noEndpointsNote`（提案自己没带端点）放在仓储层，界面与成绩单**共用** —— 同一件事
  不许说成两句不同的话。
- 读数是**现算的派生量，不落库**（`app/lib/features/cognitive/application/material_intake_reader.dart`
  的 `pendingMissingEndpointsOf` / `readPendingMissingEndpoints`）：它是"现在这一刻库里的样子"的函数 ——
  缺的那一端后来补进图里（本批的点被确认、或用户手建一个），这条连接就该能落；存下来会变成一句
  过期的话（对比 `already_existed`：那句只在点头那一刻成立，所以它才必须落库）。
- **与确认时的判据逐条对齐**：① 两端都要在**影子图**里（库里已有的 `external_id` + 这一批的点提案
  将要送进去的 id —— 同一次 `apply` 先点后边）；② 边**已经在库里**的不算落不了（确认时会说"已存在"）；
  ③ 点提案里"同名已存在"（`exists`）的**不算数**（`_createPoint` 对它不写行，它的 `external_id`
  也就不会出现在库里）。三条不一致都会让界面说一句确认时不会应验的话。
- **跟着勾选变**：算的是"现在勾着的这些"，因为 `apply` 也只收到勾着的那些 —— 把一端取消勾选，
  连着的边**当场**喊缺（`_missingNow` 在勾选框变化时重算），不用等成绩单。
- 界面：提案卡片上多一行（`Icons.link_off` + "这条现在落不了：<缺哪一端>（先让缺的那一端进图）"）；
  确认之后这行还在（它说的事已经写在成绩单上了），直到那一端真的进图。

**证据**：新 `app/test/features/cognitive/application/material_intake_reader_test.dart` **14 例**
（10 例纯函数：三种缺法、"同名已存在"不算、没有 `nodeId` 不算、边已在库里也不算、提案自己缺端点、
知识点不在这张单子上、本批的点算数；4 例真写库：还没确认就读得到、确认之后那把话与成绩单一致、
缺的一端补进图里之后这句话**自己消失并且真的落得下去**、两端都在本批时确认前不喊缺且确认后真落下去）；
材料页 `app/test/features/cognitive/presentation/material_intake_page_test.dart` 17 → **18 例**
（新增"缺的那一端补进图里之后，这句话自己消失"，并在"确认一部分"那一例里钉住 `link_off` 0 → 2 → 2 个）；
`dart format` 本轮文件 0 changed（**只格式化本轮文件** —— 整树 `dart format lib test` 会重排 155 个
跟本轮无关的文件，这个仓库的基线在当前 formatter 下并不干净，别再来一次）；
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）；
全量 `flutter test --concurrency=1` → `+1913 ~2: All tests passed!`（轮次七十九是 `+1898 ~2`，差值 15
—— 正好是本轮新增的 14 + 1 例）。

**已知的没做**：① 谁来决定"这份请求（`run/1`）可以执行了"—— 执行层仍然**没有调用者**（轮次七十八 ①）—— **已在轮次八十五补上调用者，"判断者"仍缺**；**轮次八十七起这条演练在照片报告里也按得到（只读、仍不落库）**；
② 执行完怎么落库（`knowledge_points` / `knowledge_edges` 的写入路径）—— **已在轮次九十一做了前半段**：一跑要建的先落成待确认提案（`material_intake_batches` / `proposals`），人点头那一下走材料入库页那条老路（`apply`）；只读演练本身仍然一个字不写库；③ 撤销**不记账**、也不进审计
（轮次七十九 ①②）—— **已在轮次八十二补上自家的撤回流水，见轮次八十二那条**（`review_logs`
仍然不进）；④ `ls` 仍没有标定来源（roadmap §3 第 7 行那六条实验，需要外部数据）。

---

## 2026-10-17 轮次七十九：撤销一次确认 —— 反悔也能退（Lead）

**做了什么**：历史那张单子（"已经确认完的"）以前只能看、不能改 —— 点错了只能去知识点管理页手删，
那是**第三处删法**（漏删一条边、或误删掉"本来就有的"老行，界面上都不会有人拦）。这一轮给它一个反悔
的入口，但**写仍然只有一个写者**：撤销走确认那一层的
`MaterialIntakeRepository.undoBatch(batchId)`（`app/lib/data/repositories/material_intake_repository.dart`），
界面入口放在材料页「看看确认了什么」对话框里。

- **整批要么全撤、要么全不动**：先算完全部拦路项再动库 —— 只要有一条撤不干净，就一条也不删，
  把理由逐条摆出来（`MaterialUndoOutcome.blocked`），不给"那就撤一半吧"的选项。
- 拦路四种：点下面已经有卡片（`card_states` **或** `card_templates` —— 卡片模板也算卡片）、点已经打过
  标签（`object_tags`，`object_type = 'knowledge_point'`）、这个点上挂着**别的**线索边
  （`knowledge_edges.batch_id` 不等于本批）、提案没有内容 id（认不出它建的是哪一行）。
- 本批自己建的边跟着点一起撤；行**已经被手删**不算拦路 —— 没什么可删的，只退提案。
- 退提案时 `applied_at` 与 `already_existed` **一起清**：那句"它本来就有的"记的是上次点头那一刻的判断，
  撤回之后不再成立（`record` 下一轮重算 `exists`），留着会让再确认时读到一句过期的话。
- 界面：对话框多一个「撤回这一批」→ 先问一句（说清边界：本来就有的行 / 卡片 / 标签 / 别的边一个字不动）
  → 成绩单说清"删掉几个知识点、几条边、退回几条提案"；撤不了时整批没动、理由**照原样**摆出来。

**两条纪律由测试钉住**：① 撤了之后再确认，还是**同一条边**（边 id 就是提案 id 去掉前缀，幂等键没变）；
② 没确认过的一批，什么都不删、也什么都不退。

**证据**：`app/test/data/repositories/material_intake_repository_test.dart` 新增 **10 例**（10 → 20）；材料页
`app/test/features/cognitive/presentation/material_intake_page_test.dart` 新增 **2 例**（15 → 17，新增"撤掉
这次新建的"与"撤不掉时一条也不删"）；`dart format` 7 files 0 changed；`dart analyze lib test` →
`94 issues found`（**0 error / 0 warning**）；全量 `flutter test --concurrency=1` → `+1898 ~2: All tests passed!`
（轮次七十八是 `+1886 ~2`，差值 12 —— 正好是本轮新增的 10 + 2 例）。
另记一次**并行跑的 flake**（不是本轮改动的锅）：`flutter test`（默认并发）那一次 `test/features/anki/review_service_test.dart`
的 "a miss followed by the solution … leaves the FSRS schedule untouched" 失败，单跑该文件 17 例全绿、
串行全量也全绿 —— 本轮只碰了材料摄取仓储与材料页，没碰复习服务。

**已知的没做**：① 撤销**不记账**（库里没有"这批是什么时候撤的"，`applied_at` 清空是唯一痕迹）
—— **已在轮次八十二补上**（改记流水 `material_intake_undo_logs`：撤成与没撤成都留一笔）；
② 撤销不进审计（`review_logs` 之类），所以"确认过又反悔"这件事在历史里看不到 —— **已部分补上**
（轮次八十二：进了自家的撤回流水，仍不进 `review_logs`）；③ 执行层仍没有调用者 —— **已在轮次八十五补上调用者**
（谁决定"这份请求可以执行了"）；④ 历史里不显示"哪几条是这次落不了的" —— **已在轮次八十补上**（补的是**待确认那张单子**：
落不了的连接本来就不进历史，所以这句话该在它停留的地方逐条说清楚）；⑤ `ls` 仍没有标定来源
（roadmap §3 第 7 行）。

---

## 2026-10-17 轮次七十八：把 `run/1` 真的跑进引擎 —— 路修到头了（Lead）

**做了什么**：MindNet 的 `src/io/run.js` 有两半 —— `validateRequest`（这份请求合法吗）与
`applyOne`（真的改引擎）。应用侧此前只搬了前半（轮次六十六）与"把照片变成请求"（轮次七十六）。
这一轮补上后半：新文件 `app/lib/domain/services/ingest/run_executor.dart`，入口
`executeRun(MaterialRunRequest request, {required FastEngine engine, RunAnchor? anchor})`。

- 五种动作各自落到预告里那条机制路径：`time` → `hours.advance`（推进时钟 + 同步已有记忆态节点的
  `ms`）、`review` → `retrieval_success` / `lapse` / `retrieval_failure_feedback`、`exposure` →
  `reread`、`knowledge` → `graph.add_node` / `graph.add_edge`、`goal` → `start_diffusion`。
- `RunActionTrace` 记下每条的时间前后、机制路径、增量与人话；`RunExecutionReport` 记 `assumptions`
  / `stoppedAt` / `text` / `toJson`。
- **时间基**（`resolveAt`）：`at.model_hours` 优先；只给 `at.wall` 用锚点换算，并把换算记进
  `assumptions`；两个都没有就停在那一条 —— 不默默用"现在"。
- 失败不抛异常、已跑过的不撤销；没装记忆机制时说"没改状态"，`delta` 为空、不编假增量。
- 顺手修掉一个真 bug：`MaterialRunAction.modelHours` 少了 `containsKey` 守卫，而
  `numberOrNull(null) == 0` ⇒ "只给 `at.wall`"被当成"模型时刻 0"（时钟倒回纪元、复习时间戳错到 0）。

**三条刻意选择**：① 只动内存里的图与模拟时钟，不读写库、不调 AI（写库是别的层的事）；
② 执行层仍然再拦一次上游该拦的（缺时间基、节点不在图里、未知 kind）；
③ `time` 只同步已经有记忆态的节点，一个新节点也不替它编状态，并如实写"同步 N/M 个"。

**证据**：`app/test/domain/services/ingest/run_executor_test.dart` 新增 **12 例**（空请求；两条时间基
与锚点换算；没有锚点就停住；三条 outcome 各走各的机制与方向；`exposure` → `reread`；没装机制；
`knowledge` 先点后边、端点缺失；`goal`；未知动作；**预告与执行逐条对账**）；
`flutter test test/domain/services/ingest/` → `+113`；`dart analyze lib test` → `94 issues found`
（**0 error / 0 warning**）；全量 `flutter test --concurrency=1` → `+1886 ~2: All tests passed!`
（轮次七十七是 `+1874 ~2`，差值 12）。

**已知的没做**：① 执行层现在还没有调用者（谁决定"这份请求可以执行了"）—— **已在轮次八十五补上调用者，"判断者"仍缺**；**轮次八十七起这条演练在照片报告里也按得到（只读、仍不落库）**；② 执行完怎么落库；
③ 撤销一次确认；④ 历史里不显示"哪几条是这次落不了的" —— **已在轮次八十补上**（补的是**待确认那张单子**：
落不了的连接本来就不进历史，所以这句话该在它停留的地方逐条说清楚）；⑤ `ls` 仍没有标定来源（roadmap §3 第 7 行）。
（③ **已在轮次七十九补上**。）

---

## 2026-10-17 轮次七十七：照片的界面入口 —— "拍照那一步"现在按得到（Lead）

**做了什么**：轮次七十六把"照片 → `run/1`"的服务层做出来了（`transcribePhoto`），但应用里没有任何地方
调用它 —— 用户在材料页上按不到，那条链只活在测试里。这一轮只补入口：一个按钮、一个只读对话框。

- `app/lib/features/cognitive/presentation/material_intake_page.dart`：新增"**选一张照片**"按钮
  （`OutlinedButton.icon` + `Icons.photo_camera_outlined`）与 `_readPhoto()` —— 系统选图 → 图清单与
  "已有的节点/边 id"从库里现读 → `transcribePhoto(...)` → 报告对话框。
- `_PhotoReportDialog`：**合不合法**（`ok`）/ 真正发出去的图尺寸（压过的，不是原图）/ 动作与带出处条数 /
  硬错逐条 / "会做什么"逐条 / 建议逐条 / **模型原话**（`SelectableText`）。
- 两个注入点：`photoPickerProvider`（系统选图）与 `visionEncoderProvider`（压图重编码）。
- 新增 l10n 15 键（两个 ARB）：`materialIntakePickPhoto` / `materialIntakePhotoHint` /
  `materialIntakePhotoPickFailed` / `materialIntakePhotoReadFailed` / `materialPhotoReportTitle` /
  `…ReportValid` / `…ReportInvalid` / `…ReportSize` / `…ReportCounts` / `…ReportErrors` /
  `…ReportPreviews` / `…ReportWarnings` / `…ReportRaw` / `…ReportNoRaw` / `…ReportFailed`。

**三条刻意选择**：① **只读**：对话框里没有"执行"按钮 —— 照片这条路只回答"读成了什么"，
也不写库（知识点、边、提案都不写）；② 照片这条路出问题**只改那一行提示**，不清空已经贴好的信封；
③ 报告把"合不合法"与"模型答得好不好"分开说：`ok` 是结构自检，出处/置信度的提醒走"建议"。

**踩到的坑（记下来）**：widget 测试的假时钟走不完 `dart:ui` 的解码 —— 第一版照片 widget 测试直接
**10 分钟超时**（`toImage`/`pumpAndSettle` 都卡住）。因此新增 `visionEncoderProvider` 注入点；
测试里连 `paintPng` 都不能用（引擎驱动，假时钟下永不完成），picker 改成假字节 + 假编码器。
真编码仍在 `photo_transcribe_service_test.dart` 里用真图验。

**证据**：`app/test/features/cognitive/presentation/material_intake_page_test.dart` 13 → **15 例**
（"选一张照片：读成请求、摆出自检结果、一个字都不写库"断言对话框标题 / `结构上合法` / 发出去的图尺寸 /
模型原话 `run-1` / `adapter.requests` 只有一轮且提示词含 `kp → I relied on him.` /
`knowledge_edges` 与 `material_intake_proposals` 都空；"照片读不成请求（没配模型）：说人话，
还是一个字都不写"）；`dart format` 2 文件 `1 changed`；
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）；
全量 `flutter test --concurrency=1` → `+1874 ~2: All tests passed!`（轮次七十六是 `+1872 ~2`，差值 2）。

**已知的没做**：① 把 `run/1` 真的跑进引擎（应用侧仍然只校验、不执行）—— **已在轮次七十八补上**；
② 照片这条路上"换一张/重试" —— **已在轮次八十一补上**（报告对话框里就有）；
③ 历史里不显示"哪几条是这次落不了的" —— **已在轮次八十补上**（补的是**待确认那张单子**）；④ `ls` 仍没有标定来源（roadmap §3 第 7 行那六条实验，
需要外部数据）；⑤ 已确认完的批次不能撤销 —— **已在轮次七十九补上**。

---

## 2026-10-17 轮次七十六：照片 → `run/1` 的调模型那半段 —— 那张照片终于真的发出去了（Lead）

**做了什么**：轮次六十六做完了"照片 → `run/1`"这条链上除照片本身以外的全部（提示词由【图清单】生成、
请求照 MindNet 的 `validateRequest` 逐条校验、输出与 `tools/io_check.js` 同构），可那张照片从头到尾
没有任何一段代码碰过它：用户得自己把提示词复制到别的模型里，再把答案贴回来。这一轮补上"调模型"这一步。

- 新文件 `app/lib/features/cognitive/application/photo_transcribe_service.dart`：`transcribePhoto(...)`
  把四步串起来 —— ① 照片过 `VisionImageEncoder`（长边 1280、超 4 MiB 拒绝，宁可不发也不发半张）；
  ② `buildTranscribePrompt(inventory: ...)` 连同补充说明组成提示词；③ `ChatMessage.user(prompt,
  images: [ready.toPart()])` 交给 `ModelAdapter`（**工具列表为空**：这一步只让模型说话），累加
  `ModelTextDelta`；④ `extractJsonObject`（AI 常把 JSON 包在围栏里）→ `decodeRunRequest` →
  `reviewTranscribedRun`，出处与置信度的提醒走报告里的 `warnings`。
- 结果是 sealed 结果集：`PhotoTranscribeReport`（报告 + 模型原话 + 真正发出去的图尺寸）或
  `PhotoTranscribeFailure`（`notConfigured` / `imageTooLarge` / `imageUnreadable` / `modelFailed` /
  `emptyAnswer` / `unreadableAnswer`，每条一句人话）。**失败不抛异常**，`ModelFailure` 也变成人话。

**三条刻意选择**：① **只读** —— 不写库、不执行请求（把 `run/1` 真的跑进引擎是另一件事）；
② **没配模型就不发**：`adapter == null` 直接说"发不出去，先去设置里配"，绝不偷偷联网；
③ **模型原话留全文** —— 读不成请求时把原文一起留给用户，比只报"解析失败"有用。

**证据**：`app/test/features/cognitive/application/photo_transcribe_service_test.dart` 12 例（没模型 /
图读不了 / 压过还是太大 —— 三态都断言**一个请求都没发**；照片+提示词一起发出去（工具列表为空、
提示词含图清单行、`image/png` 部件在）；模型没走完但半句回话留着；什么都没写；回话里没有对象；
对象读出来但请求不合法 `ok false`；"没写 confidence""没有 evidence"两条建议都在；`extractJsonObject`
三例）；`dart format` 2 文件 `0 changed`；`dart analyze lib test` → `94 issues found`
（**0 error / 0 warning**）；全量 `flutter test --concurrency=1` → `+1872 ~2: All tests passed!`
（轮次七十五是 `+1860 ~2`，差值 12）。

**已知的没做**：① **当时**：**界面入口未做**（服务层能跑，但用户在应用里还按不到它）——
**已在轮次七十七补上，见上一节**；
② 把 `run/1` 真的跑进引擎（应用侧仍然只校验）；③ `ls` 仍没有标定来源（roadmap §3 第 7 行那六条实验，
需要外部数据）；④ 已确认完的批次不能撤销。

---

## 2026-10-17 轮次七十五：成绩单落进历史 —— "本来就有的"这句话存下来了（Lead）

**做了什么**：轮次七十三做出"已经确认完的历史"，但那份历史只会念"当初确认了什么"。成绩单上那句
"哪几条是本来就有的（没重复建）"只活在 `apply` 那一次调用里 —— 关掉页面、重启应用就没了；同一份
材料重贴两次，历史里两条长得一模一样，看不出"这条其实是上次就有的，系统没重复建"。这一轮把这句
**只有确认那一刻知道**的判断（`_createPoint`/`_createEdge` 刚刚查过库）随提案一起落库。

- `app/lib/data/database/tables.dart` + `database.dart`：新列 `material_intake_proposals.already_existed`
  （**v19**）—— `_upgradeV18ToV19` 走 `_addColumnIfMissing`，`_ensureColumns` 的 `expected` 里也补上
  （加的是列不是表，靠列自愈），`_tableFor` 补 `case 'material_intake_proposals'`（这个洞是第一次跑
  v19 迁移测试时红出来的：自愈路径解析不到表名，直接 `unknown table`）。
- `app/lib/data/repositories/material_intake_repository.dart`：新增 `MaterialAppliedProposal`
  （提案 + `alreadyExisted`）；`appliedProposals()` 改读这一对；`_markApplied` 多一个
  `alreadyExisted` 参数 —— **已经确认过的行不覆盖这句历史**（第一次点头的判断才是"我上次建了什么"
  的答案，幂等重放不该把它改写成"本来就有的"）。
- `app/lib/features/cognitive/application/material_intake_reader.dart`：`MaterialIntakeApplied.proposals`
  的类型跟着换成 `List<MaterialAppliedProposal>`（读者只有它一个）。
- `app/lib/features/cognitive/presentation/material_intake_page.dart`：历史对话框那一行多一句
  "**已存在，不重复建**"；`materialIntakeDoneNote` 两个 ARB 都改了，说清标了这句的那几条是确认时
  库里就有的、其余是这次才写下去的。

**三条刻意选择**：① 句子存在**提案行**上，不另建"成绩单"表 —— 它描述的就是那一条提案的那一次确认；
② 只记"是不是本来就有的"，不记时间戳/旧 id —— 历史要回答的是"我上次建了什么"，不是审计；
③ 没有 `applied_at` 的行（缺端的连接）一律不出现在历史里，所以"这句话"和"它确实进库了"永远同真。

**证据**：`app/test/data/database/v19_migration_test.dart` 2 例（真 v18 文件升级、被盖成 v19 缺列靠
自愈；造法是 `ALTER TABLE ... DROP COLUMN already_existed` 再把 `user_version` 压回 18）；
`app/test/data/repositories/material_intake_repository_test.dart` 两处补断言（"同名已存在"那条读得出
`alreadyExisted: true`、幂等重放后四行仍全是 `false`）；`app/test/features/cognitive/presentation/
material_intake_page_test.dart` 新增 1 例 widget（历史对话框里那一条被标出来）；`dart analyze lib test`
→ `94 issues found`（**0 error / 0 warning**）；全量 `flutter test --concurrency=1` →
`+1860 ~2: All tests passed!`（轮次七十四是 `+1857 ~2`，差值 3）。

**已知的没做**：① 已确认完的批次仍然只看得到、改不了（不能撤销/回滚一次确认）—— **已在轮次七十九补上**；② 历史里不显示
"哪几条是这次落不了的"（缺端的连接根本没进历史，只在待确认那张单子上）—— **已在轮次八十补上**（就在那张单子上逐条说清缺哪一端）；③ `ls` 仍没有标定来源
（roadmap §3 第 7 行那六条实验，需要外部数据）；④ TRANSCRIBE 的照片本身（§2-C ③）与把 `run/1`
真的跑进引擎。

---

## 2026-10-16 轮次七十四：顺着线索边走 —— 名字终于点得动（Lead）

**做了什么**：轮次七十/七十一/七十三把那批线索边显示出来了，可名字只是名字：看到
`rely on → I relied on him.` 想知道另一头还连着谁，只能自己回清单页里翻。这一轮让端点名字可点：
走到哪一端就看哪一端的边（只读），而且能在同一层里继续走下去 —— 线索边本来就是给人顺着走的。

- `app/lib/features/anki/presentation/knowledge_edge_page.dart`：新增 `KnowledgeEdgeEndpointRef`
  （图里的 id + 显示名）与 `showKnowledgeEdgeWalk(context, endpoint:)` —— 开一个只读对话框，
  里面就是那一端自己的 `KnowledgePointEdgesSection`，名字继续可点（内部递归），于是 A → B → C
  可以一层层翻；清单页每一行的两端换成可点的 `_EndpointLink`（`_EdgeTile` 把"点的是哪一端"交给
  页面回调）。缺端（`hasMissingEndpoint`）也能走：那一端在 `knowledge_points` 里没有行，可它的边
  还在 `knowledge_edges` 里，走过去看得到"这个 id 还连着谁"。
- `app/lib/features/anki/presentation/knowledge_point_edges.dart`：`KnowledgePointEdgesSection` 多一个
  可选 `onOpenPoint`；给了回调那行"它指向谁 / 谁指向它"就带下划线可点（`Tooltip` 说明走法），
  没给就还是纯文本。
- `app/lib/features/anki/presentation/anki_manage_page.dart`：知识点详情里那一段接上同一个回调 ——
  同一个走法两个入口。
- 两条 l10n 键（`knowledgeEdgeWalkTitle`/`knowledgeEdgeWalkHint`/`knowledgeEdgeWalkTooltip`）两个 ARB
  都加了，`flutter gen-l10n` 已重跑。

**三条刻意选择**：① 只读的对话框，不是新页面 —— 走法是"看"不是"管理"，在这里能建边删边就等于又搬来
一个写入口；② 回调给的是"另一端"的 id 与显示名 —— 走到哪一端，出边入边就站在那一端说方向，翻页时
方向不会串；③ 一层层接着走、不做"返回上一层"的历史栈 —— 关掉就回到原来那一页，想回上一个点再点
一次它的名字。

**证据**：`flutter test test/features/anki/knowledge_edge_page_test.dart`
`test/features/anki/knowledge_point_edges_test.dart` → `+16: All tests passed!`（新增 1 例 widget 走
A → B → C；详情那一段新增 2 例：端点给出的是另一端的 id 与显示名、没给回调时只是文本；清单页三处
标题断言改成"两端名字各自成立"）；`dart format` 5 文件 `0 changed`；`dart analyze lib test` →
`94 issues found`（**0 error / 0 warning**）；全量 `flutter test --concurrency=1` → `+1857 ~2: All tests passed!`
（轮次七十三 后是 `+1854 ~2`，差值 3）。

**已知的没做**：① 历史里只有"确认了什么"，没有"哪些是本来就有的"（`apply` 的 `existing` 没有落库）；
② `ls` 仍没有标定来源（§3 第 7 行那六条实验）；③ TRANSCRIBE 的照片本身（§2-C ③）与把 `run/1`
真的跑进引擎。

---

## 2026-10-16 轮次七十三：已经确认完的历史 —— 做过什么，页面上也看得见（Lead）

**做了什么**：轮次六十九让"关掉页面之后那批还在"，可那只解决了**欠账**那一半 —— 页面只认
"还没确认完"的批次，一旦点过头，这一批就从屏幕上消失了。于是"我上次到底建了什么"只剩库里
那几行可查：用户看不到自己做过的事，也没法判断某条边是哪次材料带进来的。这一轮把同一张单子的
**另一半**补上。

- `app/lib/data/repositories/material_intake_repository.dart`：`MaterialIntakeBatch` 多一个
  `appliedCount`（`_toBatch` 一次查询把两边都数出来，不再只数没确认的），`toJson` 带上
  `applied_count`；新增 `appliedProposals(batchId)` —— 读**已经写下去**的那些（`applied_at` 非空，
  按记录次序）。顺手把那段过期的类 doc 改掉（它还写着"连接现在不落库 / 关系还没定"，
  轮次六十八就已经落在 `knowledge_edges` 了）。
- `app/lib/features/cognitive/application/material_intake_reader.dart`：多两个入口 ——
  `readAppliedBatches()`（`!isEmpty && unappliedCount == 0`）与 `readAppliedBatch(batchId)`。
- `app/lib/features/cognitive/presentation/material_intake_page.dart`：多一段"已经确认完的（N 批）"，
  每批一行 `批次：N 条已确认` + 转化汇总那句话；点"看看确认了什么"开一个**只读**对话框
  （没有勾选框）：知识点与线索边各一行、带出处，底下写清"这些都进库了"。两张单子共用同一份批次读数，
  看提案/恢复/确认/清空之后一起刷。

**刻意选择**：① **判据是库里现在的数，不是"当初登记过多少条"** —— 还留着一条落不了的连接
（`unapplied_count > 0`）就不叫确认完，只能待在待确认清单里；否则同一批挂在两张单子上，用户以为
它做完了，其实还有一条没落地；② **历史只读、不给勾选框** —— 这几条已经在库里了，要改得去它们
落地的地方（知识点在管理页、线索边在知识点详情里），在这里再造一个"改"的入口就是第三处写者；
③ **历史读的是"已经写下去"的提案，不是"当初打算建"的那份** —— 后者在待确认清单里看。

**证据**：`flutter test test/features/cognitive/presentation/material_intake_page_test.dart` →
`+12: All tests passed!`（新增 1 例 widget：确认完之后这批从"待确认"挪到"已经确认完的"、点开只读
对话框看得见两类条目；"确认一部分"那例补上"还有欠账的批次不许同时挂在已确认那张单子上"；
一例普通测试钉住两张单子按库里现在的数分：登记后 applied 0 / pending 4，`apply` 之后 pending 空 /
applied 4 且 `readAppliedBatch` 读回的正是那 4 条）；
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）。

**全量回归**：`flutter test --concurrency=1` → `+1854 ~2: All tests passed!`（exit 0）。轮次七十二 后是 `+1853 ~2`，差值 1。

**已知没做**：① 点开一条边跳到另一端的知识点；② 历史里只有"确认了什么"，没有"哪些是本来就有的"
（`apply` 的 `existing` 没有落库）；③ `ls` 仍没有标定来源（roadmap §3 第 7 行那六条实验，需要外部数据）；
④ TRANSCRIBE 的照片本身（§2-C ③）与把 `run/1` 真的跑进引擎。

---

## 2026-10-16 轮次七十二：手写/删除边 —— 那条路现在也能自己走（Lead）

**做了什么**：清单页和知识点详情里都已经在**读** `knowledge_edges`，写它的却只有"材料确认"那一条路 ——
`manual`（"手写"）这个关系名早就会说人话，却没有任何界面能造出一条这样的边。可资料进图给的只是材料里
明写着的连接；用户自己看出来的那一条（"B 那句话其实是在解释 A"），以前只能等下一份材料顺带提到它。
这一轮把**第二个写者**补上：仓库给出手写边的 API，详情里能加能删，同时把"只能删自己写的"钉死。

- `app/lib/data/repositories/knowledge_edge_repository.dart`：类 doc 从"这一层不写（只读是刻意的）"
  改成"读法 + 唯一的第二个写者（`origin: 'manual'`）"，并写明分工：材料确认那条路 = 材料里写的连接，
  这里 = 用户自己看出来的连接。新增 `graphPoints()`（图里的点 = `external_id` 非空、去重、按标题再按 id 排）、
  `createManualEdge({fromId, toId, now})`、`deleteManualEdge(edgeId)`，以及
  `KnowledgeEdgeEndpoint` / `ManualEdgeOutcome`{created, alreadyExists, unknownEndpoint, samePoint} /
  `ManualEdgeResult` / `ManualEdgeDeleteOutcome`{deleted, notFound, notManual}。
- `app/lib/features/anki/presentation/knowledge_point_edges.dart`：线索边那一节末尾永远有"加一条线索边"
  （方向：它指向 / 指向它 + 另一端下拉，候选里剔除自己）；每一行只有 `origin == 'manual'` 时才出现
  删除按钮，删之前先问一次。`_refresh` 显式 invalidate 三个 provider（这个点的边、候选点、清单页）——
  这一段刚动过那张表，不等数据库 revision 兜一圈。
- `app/lib/features/anki/presentation/knowledge_edge_page.dart`：新增 `knowledgeEdgeEndpointsProvider`
  （候选点）—— 放这儿不放管理页，否则与 `anki_manage_page.dart` 成环。

**刻意选择**：① **"同一个方向只留一条"按方向判，不按作者判** —— 图说的是"这两点之间有一条线索"这个事实，
不是"谁写的那条线索"；再来一条会把同一个事实说两遍，所以报"已经有了（材料确认来的）"而不是偷偷加第二条；
② **写完自己重读** —— `AppDatabase.forTesting` 不带写拦截器（`DbWriteInterceptor` 只在
`database.dart:946` 那条连接里装），测试里 revision 本来就不会动；显式 invalidate 既让界面不多等一拍、
也让这条线在测试里能被钉住；③ **手写边一律不给 `ls`** —— 没有标定来源就不假装有，读法那边照旧显示"没有 ls"。

**证据**：`flutter test test/data/repositories/knowledge_edge_repository_test.dart
test/features/anki/knowledge_point_edges_test.dart` → `+20: All tests passed!`
（5 例新增仓库例：`graphPoints` 只收有 `external_id` 的点、手写边的形状（`manual:from->to`、`ls`/`source`/`batchId`
皆空、反向另算一条）、同方向已有材料边 ⇒ `alreadyExists` 且库里仍 1 行、缺端点与自连、删除三种 outcome；
6 例新增 widget：手写出边／入边各落对方向且界面立刻看得见、已有边不重复加、图里只有自己时确认钮不可按、
材料边没有删除按钮、手写边删除全流程）；
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**；方向选择改用 `RadioGroup<String>` 祖先后
回到基线，`RadioListTile.groupValue/onChanged` 那 4 条 deprecation info 不再出现）。

**全量回归**：`flutter test --concurrency=1` → `+1853 ~2: All tests passed!`（exit 0）。
轮次七十一 后是 `+1842 ~2`，差值 11 = 本轮新增的 5 例仓库 + 6 例 widget。

**已知没做**：① 点开一条边跳到另一端的知识点（现在只显示名字，不能跳）；② 已确认完的历史无处可看；
③ `ls` 仍没有标定来源（roadmap §3 第 7 行那六条实验，需要外部数据）；
④ TRANSCRIBE 的照片本身（§2-C ③）与把 `run/1` 真的跑进引擎。

---

## 2026-10-16 轮次七十一：按知识点看线索边 —— 详情里第一次看得见图（Lead）

**做了什么**：轮次七十给 `knowledge_edges` 配了清单页，回答"图里现在有什么线"；可用户真正会问的是
反过来的一句 —— **"这个词 / 这句话在图里连着谁？"** 清单页能翻，但它把方向冲淡了：同一条边在清单里
只是 `A → B`，站在某个点的详情里应当是两句话。这一轮把读法从"图的角度"补到"点的角度"。

- `app/lib/data/repositories/knowledge_edge_repository.dart`：新增 `forPoint(externalId)` —— 一个点的
  **出边和入边一起**读回来（`fromId == id | toId == id`），次序沿用清单页那一条（新的在前）。
  方向留给调用方判断："谁指向谁"是显示层的事，仓库不替它挑一边。`all()` 与 `forPoint()` 共用
  `_selectEdgeRows()` / `_viewsOf()`，两种读法的解名与次序不许分叉。
- `app/lib/features/anki/presentation/knowledge_point_edges.dart`（新 widget `KnowledgePointEdgesSection`）：
  标题行 + 每条边一行，站在**这个点**的角度说话 —— 出边 `它指向：X`、入边 `指向它：X`，各带自己的箭头，
  关系名复用清单页那套人话（`knowledgeEdgeOriginLabel` / `knowledgeEdgeEndpointLabel` 从页面私有提成
  公开顶层函数，两处读同一份口径）。
- `app/lib/features/anki/presentation/anki_manage_page.dart`：知识点详情对话框（点一个知识点打开的那个）
  的 ListView 末尾加三行接线 —— 材料确认过的连接落在这里，于是"资料进图"在详情里第一次看得见。
- **两种"没有"说两句话**：手写的知识点没有 `external_id`（`KnowledgePoints.externalId` 是 nullable 的）
  ⇒ 说"这个知识点不在材料图里（没有 external_id），所以没有边可看"；在图里但库里没有边 ⇒
  说"还没有线索边（材料里的连接确认之后才会有）"。拿一个空列表冒充"它没有边"，
  就是把"我从没进过图"说成"我查过了，确实没有"。

**刻意选择**：① **入口不往 tile 上加第 5 个图标** —— 管理页每个 tile 的 trailing 已经有四个
（autoBlank / edit / add_card / delete），再加一个会把"这个点是什么"和"它连着谁"挤在同一行；
对话框本来就是这个点的详情，加一段比加一个按钮更贴题；② **出边入边都算它自己的** —— 只看"它指向谁"
会漏掉"谁指向它"，而后者恰是"这句话为什么出现在这张卡上"的答案；③ **不在那个 804 行的大页里测新 UI** ——
新逻辑拆成独立 widget 单独测（那一页此前没有 widget 测试，也不为了这个补一整套）。

**证据**：`flutter test test/data/repositories/knowledge_edge_repository_test.dart
test/features/anki/knowledge_point_edges_test.dart` → `+9: All tests passed!`
（2 例新增读法：出边入边都算且别人的边不混进来、查无此点为空；3 例 widget：没有 `external_id` ⇒
说不在图里、在图里没边 ⇒ 说还没有、一出一入 ⇒ 方向与关系名都在）；
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）。

**全量回归**：`flutter test --concurrency=1` → `+1842 ~2: All tests passed!`（exit 0）。
轮次七十 后是 `+1837 ~2`，差值 5 = 本轮新增的 2 例读法 + 3 例 widget。

**已知没做**：① 点开一条边跳到另一端的知识点（现在只显示名字，不能跳）；② 手写/删除边的界面
（写入路径仍只有材料确认那一条）；③ 已确认完的历史无处可看；④ `ls` 仍没有标定来源
（roadmap §3 第 7 行那六条实验，需要外部数据）。

## 2026-10-16 轮次七十：线索边的读法 —— 那张表终于有人读它（Lead）

**做了什么**：轮次六十八让资料里的连接**能落库**（`knowledge_edges`），可那张表**一个读者都没有** ——
确认之后边进了库，界面上再也见不到。有写者没读者的表，等于把"资料进图"这件事藏进库里：
用户既看不到线，也没法判断它是空、是错、还是自己确认过的。这一轮补的是**读法**。

- `app/lib/data/repositories/knowledge_edge_repository.dart`（新）：只读快照 `KnowledgeEdgeView`
  （两端 id / 两端标题 / `origin` / `source` / `ls` / `lsCalibrated` / `createdAt`），
  `all()` 新的在前；两端标题按 `knowledge_points.external_id` 解出来，**那一端不在库里就是 null**，
  界面按 id 显示 —— 读法不替图编造节点。同一个 `external_id` 有多行时取第一个（读法要确定）。
- `app/lib/features/anki/presentation/knowledge_edge_page.dart`（新）+ 知识模块 AppBar 入口
  （`Icons.hub_outlined`，挨着"今日复盘"）：一条边一行，`A → B` + 关系人话 + 材料出处 +
  `ls 0.60（未标定）`；缺一端时另说一句；材料没给 `ls` 就说"没给"（不显示 0，也不假装有未标定权重）；
  空库明说"还没有线索边"，而不是摆一个空列表。
- 这一层**只读**：不建边、不删边、不改 `ls`。边的写者仍然只有材料摄取那一处（确认过的连接）。
- 顺手把 `KnowledgeEdges.origin` 的 doc 与实际写入对齐（材料关系 `contains`/`produce`/`topic`、
  手写边 `manual`、材料没写清时 `material`）。

**刻意选择**：① **先给全量，不按知识点分页** —— 这一页回答的是"图里现在有什么线"；按点筛选要先把入口
定在管理页哪一行，先做就等于先猜用户想从哪个点看；② **缺端照实显示 id** —— 编一个"未知知识点"看着体面，
却把"图不完整"藏起来了：缺端是数据状态，不是显示问题；③ **认不出的 `origin` 照实显示原文** ——
不硬塞进"材料"那一类，否则上游给了新关系也没人会发现。

**证据**：`flutter test test/data/repositories/knowledge_edge_repository_test.dart
test/features/anki/knowledge_edge_page_test.dart` → `+8: All tests passed!`
（4 例读法：两端解名与次序、缺端、`ls` 未给、空表；4 例页面：空说、整条、缺端、没给 `ls`）；
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）。

**全量回归**：`flutter test --concurrency=1` → `+1837 ~2: All tests passed!`（exit 0）。
轮次六十九 后是 `+1829 ~2`，差值 8 = 本轮新增的两个测试文件。

**已知没做**：① 按知识点看它自己的线索边（先要定入口放在管理页哪一行）；② 手写/删除边的界面
（写入路径仍只有材料确认那一条）；③ `ls` 仍没有标定来源（roadmap §3 第 7 行那六条实验，需要外部数据）；
④ TRANSCRIBE 的照片本身（§2-C ③）与把 `run/1` 真的跑进引擎。

---

## 2026-10-16 轮次六十九：从"待确认清单"恢复 —— 关掉页面之后那批还在（Lead）

**做了什么**：roadmap §2-C ① 遗留的最后一条"从待确认清单恢复的界面"。轮次六十五给这条路开了界面入口，
但入口只在"刚贴完那一批"上活着：仓储早就把"算过但还没点头"存住了（`material_intake_batches` +
`material_intake_proposals`，`applied_at` NULL），可关掉页面之后那批就没人能接着确认 ——
库里存着规矩、界面上看不见，等于把"确认前不写"做成了"确认前不写，除非你别关页面"。

- `app/lib/features/cognitive/application/material_intake_reader.dart` 多两个入口：
  `readPendingBatches({repository})`（`repository.batches()` 里只留 `unappliedCount > 0`，新的在前）与
  `readPendingBatch({repository, batchId})`（批次不存在给 `null`，否则读 `pendingProposals`）。
  **它们不重算**，只把当初登记的提案按原顺序读回来 —— 所以"接着看的就是当初那一份"不是承诺，是同一条记录。
- 页面（`app/lib/features/cognitive/presentation/material_intake_page.dart`）打开就刷清单，
  `_restore(batch)` 把那批读回来接着勾；状态从 `_draft` 换成"提案 + 跳过项 + 批次"三样，
  于是**贴信封与恢复共用同一条渲染与确认路径**。
- 确认之后同时刷**批次读数**与清单：落不了的连接照旧没确认（`deferred` 不标 `applied_at`），
  所以成绩单上的"还剩 N 条"与清单上的"待确认 N 条"是同一个数；都确认完了就不再念"待确认 0 条"。
- 顺手改掉两处过期文案：`app_zh.arb` / `app_en.arb` 的 `materialIntakeIntro`（原来写"连接先不动……
  还没定"，现在写"连接落成 `knowledge_edges` 的线索边，两端都在才落"）、
  `material_intake_repository.dart` 里 `unappliedCount` 的 doc。

**刻意选择**：① **恢复不重算** —— 重算意味着"看到的"可能已经不是"库里那份"，而这条纪律的全部价值就是两者一致；
② **清单只列有欠账的批次**（`unappliedCount > 0`）—— 一个"都是 0 的清单"没有信息量；
③ **入口不新增页面** —— 恢复是"看提案"的同一件事，多一个页面就多一处能走偏的渲染。

**证据**：`flutter test test/features/cognitive/presentation/material_intake_page_test.dart` →
`+11: All tests passed!`（原 8 例；新增"从待确认清单恢复：接着确认的就是当初那一份"——
预登记一批 → 新页面看到清单 → 恢复 → 确认 4 条后知识点 2 行、线索边 2 行、清单不再出现；
"确认一部分之后，清单里剩下的接着等着"——只确认 3 条时成绩单的"还剩 3 条"与清单读数一致；
`readPendingBatch` 对不存在的批次返回 `null` 一例）；`dart analyze lib test` → `94 issues found`
（**0 error / 0 warning**）。

**全量回归**：`flutter test --concurrency=1` → `+1829 ~2: All tests passed!`（exit 0）。
轮次六十八 后是 `+1826 ~2`，差值 3 = 本轮新增的三例。

**已知的没做**：① 清单只显示"还没确认完"的批次，**已确认完的历史**没有地方可看；
② TRANSCRIBE 的照片本身（§2-C ③）；③ 把 `run/1` 真的跑进引擎；④ 落下来的线索边还没有界面读它。

## 2026-10-16 轮次六十八：线索边落库 —— 资料与卡片的关联类型定案（Lead）

**做了什么**：roadmap §2-C ④「资料与卡片的关联类型（线索边 vs 包含边）+ 连接落点」。
在此之前材料里的连接一律**不能落**（`apply` 如实报 `deferred`，界面上的连接勾选框直接置灰），
因为"标签树的父子边"与"MindNet 的边"是两种语义。定案依据是
`E:\Document\MindNet\docs\MEMORY_RECORD.md` §3.5（`:102-103`）：**标签树的父子边是"包含"语义，
MindNet 的边是"线索"语义 —— 严格有向、不自动反向；边权 `ls` 目前没有标定来源**。
这一轮把"关联类型"与"连接落点"一起定下并落库（schema v18）。

- 新表 `knowledge_edges`（`app/lib/data/database/tables.dart`）：`id`(PK，就是 INGEST 那条边的
  id 去掉 `edge:` 前缀 ⇒ 幂等键) / `from_id` / `to_id` / `origin` / `ls`(可空) /
  `ls_calibrated`(默认 `false`) / `batch_id` / `source` / `created_at` / `updated_at`；
  `app/lib/data/database/database.dart` 侧是 `_upgradeV17ToV18`（加一张表）+ `_ensureColumns()` 自愈
  （Drift 在 `user_version` 等于当前版本时跳过 `onUpgrade`，那一刻没有自愈第一次写就会炸）。
- **两种语义各归各家**：包含语义仍然只有标签树父子边一处（`tags.parent_id`），线索边不复制它；
  线索边严格有向，`from → to` 与 `to → from` 是两条不同的边。
- **两端都在才落**（`MaterialIntakeRepository._createEdge`）：端点按 `knowledge_points.external_id`
  认（本批刚建的或库里已有的都算）；缺一端就 `deferred` + 人话原因（"起点/终点/两端还不在库里"），
  **不建边、不标 `applied_at`**，留在待办里等端点补齐 —— 与 MindNet `validateRequest` 的影子图规则同构。
- `apply` 先按 `kind.index` 排序（知识点在前）再逐条处理，于是"同一批里刚建的点"立刻能当端点；
  `MaterialApplyOutcome` 分成 `created` / `createdEdges` / `existing` / `existingEdges` / `deferred` /
  `remaining`，`toJson()` 给出 `created_edges` / `created_edge_count` / `existing_edges`。
- 落边的 `ls` 照抄提案，但 `ls_calibrated` 一律 `false`（§3.5 说它没有标定来源，就不假装有）；
  `origin` 记它来自材料里的哪种关系（`contains` / `produce` / `topic`，缺省 `material`）。
- 界面：连接不再置灰（`materialIntakeConnectionClue` 取代 `materialIntakeConnectionDeferred`），
  默认与知识点一起选中；成绩单把两类合计着说（"写入 N 条（知识点与线索边）…N 条连接落不了"）。
- 工具：`apply_material_intake` 的 summary 多了"建了连接 A → B（origin）"与"连接落不了（有一端还不在库里）"，
  `afterJson` 多了 `edge_ids`。

**刻意选择**：① **不建通用边表** —— 此前那 33 张表里没有通用边表（`ObjectTags` 是 tag↔object），
硬造一张"什么边都能装"的表正是 §3.5 警告的语义混淆；② **`origin` 存关系名而不是"材料 id"** ——
材料已经在 `batch_id`/`source` 里，`origin` 要回答"这条边凭什么存在"（含/产/主题），标定 `ls` 时用得上的就是它；
③ **缺端就 defer，绝不编边** —— 一条只有一端的边写进库比不写更糟，它会被后续图算法当成事实。

**证据**：`flutter test test/domain/services/ingest/material_intake_plan_test.dart
test/data/repositories/material_intake_repository_test.dart
test/features/ai/apply_material_intake_tool_test.dart
test/features/cognitive/presentation/material_intake_page_test.dart
test/data/database/v18_migration_test.dart` → `+41: All tests passed!`（新文件
`app/test/data/database/v18_migration_test.dart` 照 v17 那篇写：真 v17 文件升级、被盖成 v18 缺表靠自愈）；
`dart analyze lib test` → `94 issues found`（**0 error / 0 warning**）。

**全量回归**：`flutter test --concurrency=1` → `+1826 ~2: All tests passed!`（exit 0）。
轮次六十七 后是 `+1824 ~2`，差值 2 = 新的 v18 迁移测试两例。

**已知的没做**：① `ls` 仍**没有标定来源**（标定实验是 roadmap §3 第 7 行那六条，需要外部数据）；
② 落下来的边**还没有界面读它**（数据在库里，知识点页/图视图都还没画）；
③ TRANSCRIBE 的照片本身（§2-C ③）；④ 把 `run/1` 真的跑进引擎。

## 2026-10-16 轮次六十七：SM-2 只剩存档 —— 到期日真的只有一个权威（Lead）

**做了什么**：把 roadmap 第 3 节末尾那条纪律（"FSRS 仍是到期日唯一权威""一张表的一列只有一个写者"）
落到代码里。`docs/GAP_ANALYSIS.md` 的 D9 早就把 SM-2 定成"模块保留为存档文件、**不再被调用**"，
但旧入口 `features/anki/application/anki_service.dart:23`（被 `features/anki/presentation/anki_page.dart:273`
调用）仍走 `sm2_scheduler.dart`，`card_states.due_at` 因此一直有第二个写者。

- 删 `app/lib/features/anki/presentation/anki_page.dart`（333 行）与
  `app/lib/features/anki/application/anki_service.dart`（64 行），以及只服务于前者的
  `ankiServiceProvider`（`app/lib/data/repositories/repository_providers.dart`）。
  两个文件都**没有任何入口**：全仓引用只剩它们自己（`anki_page|AnkiPage` 的命中只有自身
  与三份文档），v2 复习流早就是 `knowledge_page.dart` → `review_page.dart` →
  `review_service.dart` 的 `FsrsScheduler.schedule`。
- `app/lib/domain/services/srs/sm2_scheduler.dart` **留着**（D9 要的是"存档"而不是删除），
  它的单测也照跑。
- 新守门测试 `app/test/domain/services/srs/single_scheduler_authority_test.dart`：扫 `lib/`，
  除存档文件本身外不许有任何 `.dart` 文件提到 `Sm2Scheduler` —— 于是"不再被调用"从文档承诺
  变成可执行事实（对 `Directory('lib')` 有 `existsSync` 断言，工作目录跑偏会给理由而不是静默通过）。

**刻意选择**：① **删调用点，而不是把旧页迁到 FSRS** —— 给一个没有入口的页面续命不是修问题，
"存在第二个写者"才是；② **存档文件保留** —— `docs/GAP_ANALYSIS.md` 与 `docs/MILESTONES.md`
都写明"模块保留、测试删/迁"，删它得先改文档；③ **守卫用源码扫描** —— 这条纪律是
"代码里不许出现某个调用"，领域测试证明不了它。

**证据**：`flutter test test/domain/services/srs/` → `+51: All tests passed!`（含新守卫与存档模块
自己的 3 例）；`dart analyze lib test` → `94 issues found`（删掉的文件少了 1 条既有 info，
**0 error / 0 warning**）。

**全量回归**：`flutter test --concurrency=1` → `+1824 ~2: All tests passed!`（exit 0）。
轮次六十六 后是 `+1823 ~2`，差值 1 = 本轮新增的守门测试。

**已知的没做**：① `home_shell.dart` 仍是 6 个旧页（`docs/DESIGN_BLUEPRINT.md` 记的 R4/R5 UI 接线）；
② `docs/PROGRESS.md` 里 v0.1 时代的 SM-2 / AnkiService 记录是历史，不改；
③ TRANSCRIBE 的照片本身与"把 `run/1` 真的跑进引擎"仍未做（§2-C ③）。

## 2026-10-16 轮次六十六：转写规程的确定性那一半（Lead）

**做了什么**：roadmap §2-C ③「TRANSCRIBE 的"照片 → `run/1`"（含出处/置信度）」的确定性那一半。
`docs/archive/TRANSCRIBE.md` 的规程一半是"上游 AI 看图写字"、另一半是确定性代码（校验、说人话、
预告机制路径）—— MindNet 里后者是 `tools/io_check.js`。这一轮把它补齐，并把给上游模型的提示词
（含【图清单】）一起生成出来，于是这条链上**除了照片本身**都已经能对着规程自检。

- `MaterialIngest.checkRunRequest`（`app/lib/domain/services/ingest/material_ingest.dart`）扩到与
  `src/io/run.js` 的 `validateRequest` 逐条对齐：协议 / `run_id` / `actions` 是否为数组 /
  `steps` 是否 ≥0 整数 / `time` 块可整体不写 / 每条动作的时间基 / `outcome` 白名单 /
  **同一节点两个矛盾结论** / 影子图端点（同一份请求里先建节点、再引用它算"已存在"）/
  `goal` 目标 / `time` 的 `elapsed_hours ≥ 0`；`previews` 全保真（不再需要引擎）。
- 新 `app/lib/domain/services/ingest/transcribe_run.dart`：`decodeRunRequest`（对象或 JSON 文本）→
  `reviewTranscribedRun`（硬错与建议分开；每条动作预告落到哪条机制路径）→
  `buildTranscribePrompt`（§6 提示词 + 【图清单】）。
- `MaterialIntakeRepository.externalNodeInventory()`：图清单来自 `knowledge_points.external_id`
  （`review`/`exposure`/`goal` 只能指向图里已有的节点，而"图"在应用侧的真实来源就是这一列）。
- 新只读工具 `check_transcribe_run`（`app/lib/features/ai/tools/ingest_tools.dart` + 注册表：
  与 `io_check` 同一件事 —— **只校验、不执行**）。

**顺手改掉的两处真保真问题**（都是"照文档写"抓不到的）：① `src/io/run.js` 对可选数字用的是
`!== undefined`（**键在不在**），而 Dart 的 `numberOrNull` 照 JS `Number()` 语义把 `null` 算 0 ——
`closeness` / `elapsed_hours` / `confidence` 因此改成按"键在不在"解析，否则 `time` 动作少写
`elapsed_hours` 会被预告成"时间前进 0 小时"（测试第一跑就抓到了这条）；② `time` 动作可以只用
`elapsed_hours`，其余动作必须有 `at`（决定"缺时间基"的判定，也决定 `time` 块可以整体不写）。

**刻意选择**：① **只校验、不执行** —— 应用侧暂时不跑引擎，所以只说"会做什么"，绝不说"已经做了"；
② **建议不拦** —— 规程说"建议全带"，但缺一条 `confidence` 不该让整份请求作废，只有硬错才整份拒绝；
③ **图清单从库里查** —— "不许发明节点 id"（§1 第 2 条）必须有真实依据，不能靠 AI 自觉。

**证据**：`app/test/domain/services/ingest/transcribe_run_test.dart` 32 例（解码 4 型 + 硬错族 15 例 +
建议族 4 类 + 五种动作的预告文案 + `report.text`/`toJson` 3 例 + 提示词 3 例）；
`app/test/features/ai/check_transcribe_run_tool_test.dart` 8 例（只读且注册表里拿得到、缺 `request`
与非法 JSON 都是参数错、好请求给机制路径与出处统计、节点不在图 → `ok false` 整份拒绝、
图清单默认来自库里 `external_id`、JSON 文本与对象等价、协议错也照给预览便于定位）。
分组跑绿：`flutter test test/domain/services/ingest/` → `+101`；
`flutter test test/features/ai/ test/domain/services/ingest/ test/data/repositories/` → `+599`。

**全量回归**：`flutter test --concurrency=1` → `+1823 ~2: All tests passed!`（exit 0）。
轮次六十五 后是 `+1783 ~2`，差值 40 = 本轮 32 + 8 例；`dart analyze lib test` 仍是
`95 issues found`（0 error / 0 warning）。

**已知的没做**：① 照片本身（视觉模型 → 信封/请求，含出处与置信度）；② 把 `run/1` 真的跑进引擎
（应用侧目前只校验）；③ 资料与卡片的关联类型（线索边 vs 包含边，§2-C ④）。

## 2026-10-16 轮次六十五：材料入库的界面入口（Lead）

**做了什么**：roadmap §2-C ① / §3 第 6 行「材料摄取」的第五步，也是这条链第一次离开 AI 工具。
轮次六十二～六十四 把机械部分都做好了（信封 → 标准清单/图补丁/`run/1` 请求 → 待确认提案 →
确认后写库），但能动它的入口只有模型。这一轮在设置页加「添加资料」：用户自己贴一份
`mindnet.material/1` 信封，看清要建哪些知识点与连接、每条出自哪一页哪一行，勾选之后才写库。

- 新 `app/lib/features/cognitive/application/material_intake_reader.dart`（纯逻辑，不写库）：
  `decodeMaterialEnvelope`（对象或 JSON 文本；空串/非 JSON/别的类型各给人话错误）+
  `readMaterialPlan`（解码 → `MaterialIngest.convert` → `MaterialIntakePlanner.plan`，
  `existingTitles` 取自仓储）+ `recordMaterialPlan`（把这一批落成"待确认"）。
  读法只有一处：页面与 AI 工具走的是同一段推导。
- 新 `app/lib/features/cognitive/presentation/material_intake_page.dart`：多行等宽输入框 →「看提案」
  （边看边记下这一批）→ 提案清单（知识点可勾、连接标"先不动"）→「确认」（只写选中的）。
  页面上同时显示 `N 条提案 · S 条留在清单外 · 已登记（U 条）`；`U` 取确认**之后**的批次读数。
- `repository_providers.dart` 新增 `materialIntakeRepositoryProvider`；`settings_page.dart` 新增入口
  （`Icons.library_add_outlined`，指向 roadmap §2-C ①）。
- l10n 两个 ARB 各加 22 个 `materialIntake*` 键并 `flutter gen-l10n`。

**刻意选择**：① **连接不给勾选框** —— 勾不动胜过点了没反应（连接落点未定，§2-C ④）；
② **"清单外"留在页面上** —— 疑问/已知/提醒不静默丢弃，条数与每条原因都在；
③ **这一步不做 AI 提取** —— 只吃信封；"从照片/文本产出信封"是 TRANSCRIBE 与提示词那一步的事。

**证据**：`app/test/features/cognitive/presentation/material_intake_page_test.dart` 8 例
（解码四种输入 4 例 + 页面 4 例：确认后知识点进库而连接勾不动、同名标"已存在"且只写 1 个、
协议错整份拒绝且一行不写、只有「问」的材料明说没有要动的东西）。
两个 widget 用例第一次红都不是逻辑错：一是页面把几个片段 join 成一个 `Text`（精确匹配找不到，
改 `textContaining`），二是 `ListView` 懒构建（默认画布下后面的卡片根本不 build，测试改用
1400×2600 画布）。

**全量回归**：`flutter test --concurrency=1` → `+1783 ~2: All tests passed!`（exit 0）。
轮次六十四 后是 `+1775 ~2`，差值 8 = 本轮 8 例；`dart analyze lib test` 仍是
`95 issues found`（0 error / 0 warning）。

**已知的没做**：① 从"待确认清单"恢复的界面（仓储已有 `batches()`/`pendingProposals()`，
页面只认刚贴的这一批）；② TRANSCRIBE 的"照片 → `run/1`"（§2-C ③）；
③ 资料与卡片的关联类型（线索边 vs 包含边，§2-C ④ —— 连接落点就等它）。

## 2026-10-16 轮次六十四：材料摄取落库（第四步：确认后才写，Lead）

**做了什么**：roadmap §2-C ① / §3 第 6 行「材料摄取」的第三步。上一轮（六十三）把信封摆成了
"要建哪些知识点/连接、每条出自哪一页"的待确认提案，工具还是只读的；这一轮把"用户点头之后写库"
这一段补上 —— 与拍照整理通路同一条纪律（提案表 + `applied_at` NULL = 还没确认）：

- schema **v17** 两张表（`app/lib/data/database/tables.dart`）：`material_intake_batches`
  （主键 `batchId` = 信封的 `batch_id`，INGEST 的幂等键；`skipped_json` 单独一列，因为"留在清单外"
  不是待确认产物）与 `material_intake_proposals`（主键 `<batchId>#<proposalId>`、`sortIndex` 保留
  材料顺序、`payloadJson` 只留一份契约、`appliedAt` NULL = 还没确认）。迁移 `_upgradeV16ToV17`
  是"加两张表"，并在 `_ensureColumns()` 里自愈（Drift 在 `user_version` 已等于当前版本时跳过
  `onUpgrade`，没有自愈的话第一次写就炸 —— v6/v7/v8… 那批踩过同一个坑）。
- 新增 `app/lib/data/repositories/material_intake_repository.dart`：`record`（幂等：同一批重算只替换
  **未确认**的行，已确认的一个字不动 —— 重算覆盖人工决定比丢数据更坏）、`batch`/`batches`/
  `pendingProposals`/`proposals`、`apply`（写 `knowledge_points`，两道去重：提案自带的 `exists`
  与 `external_id`）。
- 新增 `apply_material_intake` 工具（`app/lib/features/ai/tools/ingest_tools.dart`）：参数是**同一份信封**
  而不是"提案清单"—— 提案由信封确定性推导，所以"确认"只需说清确认哪一批、哪几条；`proposal_ids`
  越界直接拒绝；payload 里的批次取确认之后的样子（`unapplied_count` 能直接读出还剩几条）。
- 注册进 `tool_registry.dart`（在 `ingest_material` 之后），并把"信封 → 转化 → 提案"抽成共用函数
  `buildMaterialPlan(...)`：两个工具走的是同一条推导，保证"看到的"和"确认的"是同一份。

**刻意选择**：① **复核式确认** —— 工具重算一遍信封，`redo` 的路径就是"再跑一次同样的信封"；
② **连接宁可 deferred** —— 资料与卡片是"线索边"还是"包含边"未定（§2-C ④），没有落点的写入不假装
做完，它们如实进 `deferred` 并且**保持未确认**留在待办里；③ **认内容不认标题** —— 用户改过标题之后
同名判断就抓不住了，`external_id`（`en::w::…`，材料决定的内容 id）是第二道去重。

**证据**：20 例 —— `app/test/data/repositories/material_intake_repository_test.dart` 9 例（幂等记录、
重算不动已确认、apply 的 `external_id` 与出处文案"材料：词汇书（第 12 页）"、同名与改过标题两种去重、
确认两次幂等、`proposal_ids` 只处理选中项、未知批次报错、坏 payload 抛 `FormatException`）+
`app/test/features/ai/apply_material_intake_tool_test.dart` 8 例（非只读且注册表拿得到、空信封一行不写
且不留批次、信封不合规整份拒绝、好信封的 summary/payload/`afterJson`、确认两次幂等、`proposal_ids`
越界拒绝、JSON 文本等价）+ `app/test/data/database/v17_migration_test.dart` 2 例（真实 v16 文件升级后
两张表可用且老知识点还在、"被盖成 v17 却没有这两张表"靠自愈补上）。

**全量回归**：`flutter test --concurrency=1` → `+1775 ~2: All tests passed!`（exit 0）。轮次六十三 后是
`+1755 ~2`，差值 20 正好是本轮新增的 20 例；`dart analyze lib test` 仍是 95 issues（0 error / 0 warning，
都是既有的 `info`）；`dart run build_runner build --delete-conflicting-outputs` 重生成 drift 产物（513 → 466 outputs）。

**已知的没做**：① "添加资料"的界面入口（现在只有 AI 工具的路径：模型调用 `ingest_material` 看提案、
用户点头后调用 `apply_material_intake`）；② TRANSCRIBE 的"照片 → `run/1`"（§2-C ③）；③ 资料与卡片的
关联类型（§2-C ④，连接的落点就等它）。

---

## 2026-10-16 轮次六十三：材料信封 → 待确认提案（Lead）

**做了什么**：roadmap §2-C ① / §3 第 6 行「材料摄取」的第二步（第一步是轮次六十二的确定性转化）。
上一轮把信封变成了"节点/边/`run/1` 请求"，那是**图**的语言；应用侧真正要的是"AI 读完材料，告诉用户要建什么、
每条出自哪一页"，用户点头才写。这一轮把这一段做成纯逻辑 + 只读 AI 工具：

- 新增 `app/lib/domain/services/ingest/material_intake_plan.dart`（纯 Dart，只 import `material_ingest.dart`）：
  `MaterialIntakePlanner.plan(...)` 把 `MaterialConversion` 折成 `MaterialIntakePlan` —— 进图的条目变
  `kp:<nodeId>` 知识点提案、图补丁的边变 `edge:<edgeId>` 连接提案，不进图的角色与重复项原样进 `skipped`；
  每条提案带 `body`（释义/音标/原文/`出处：<材料>，第 N 页，页边：<margin_note>`）、`why`（人话）与 `evidence`。
  提案 id 复用上游的确定性 id ⇒ 同一个信封算两次得到同一份提案（以后落库时它就是 `external_id`）。
- 新增 `app/lib/features/ai/tools/ingest_tools.dart`：`ingest_material` 工具（`readOnly: true`）接受信封对象或
  JSON 文本，跑转化 + 提案，返回 `plan`/`material`/`warnings`/`run_request`/`run_check` 与一段人话 summary。
- `app/lib/features/ai/domain/tool_registry.dart` 注册（`PlanTodayTool` 之后）。

**刻意选择**：① **同名标 `exists` 而不是硬拒**：材料里常有大量旧知识，"不重复建"这件事要能**看见**
（`title` 与 `nodeId` 都留着，写库时才定按哪个认）；② **主题 hub 默认只报不建**：资料与卡片是"线索边"还是
"包含边"还没定（MEMORY_RECORD §3.5 / §2-C ④），这一层不偷偷定，要 `include_topic_hubs: true` 才带上；
③ **整份拒绝**：信封不合规就 `ToolResult.failure`，绝不产出半份提案（沿用上一轮的纪律）。

**证据**：`app/test/domain/services/ingest/material_intake_plan_test.dart` 13 例 +
`app/test/features/ai/ingest_tools_test.dart` 8 例 = 21 例全绿（三行小信封的提案数/跳过数、`kp:en::w::…` 的 id、
body 里的释义/原文/出处、同名 `'  Rely   ON '` 归一化后 `exists`、`includeTopicHubs` 的两种计数、
只含「问」时 `isEmpty`、工具侧 readOnly/缺参数/整份拒绝/同名不重复建/JSON 文本等价）。
踩到的一个坑：`produce` 反向边不由 `contains` 自动生成，前置条件是条目上 `produce: true`（见
`material_ingest.dart:1374-1399`）—— 测试 fixture 少了它就只有 contains 没有 produce。

**全量回归**：`flutter test --concurrency=1` → `+1755 ~2: All tests passed!`（exit 0）。轮次六十二 后是
`+1734 ~2`，差值 21 = 本轮的 21 例；`dart analyze lib test` 仍是 95 issues（0 error / 0 warning）。

**已知的没做**：① 提案落库（`knowledge_points` + `external_id` + 出处进 `evidence`）与"添加资料"界面入口；
② TRANSCRIBE 的"照片 → `run/1`"（§2-C ③）；③ 资料与卡片的关联类型（§2-C ④）。

## 2026-10-16 轮次六十二：材料摄取的确定性核心（INGEST 第③步 Dart 端口，Lead）

**做了什么**：roadmap §2-C / §3 第 6 行「材料摄取」的第一步 —— 契约把 INGEST 分成三步（记号由人在页边写、
AI 提取出 `mindnet.material/1` 清单、**格式转化是确定性代码**），这一轮把第三步原样移植进本仓库。

- **新文件** `app/lib/domain/services/ingest/material_ingest.dart`（约 1.7k 行，纯 Dart：不 import Flutter/drift、
  不读照片、不调模型）：一份材料信封进去，出来三样正产品 —— 标准清单（`MaterialStandardItem`：记号/角色/
  出处/含义/是否进图/节点 id）、图补丁（`MaterialGraphPatch`：先节点后边，边分 `contains`/`produce`/`topic`）、
  可直接交给 `mindnet.run/1` 的请求（`MaterialRunRequest`：先建节点、再建边、★ 设为目标，每条动作带
  `evidence{source, region, batch_id}`）。
- **确定性**：节点 id 与参考实现同规则（32 位 FNV-1a → `en::w::resilient` / `en::s::9ef4708d` /
  `en::t::9c90edeb` / `en::method::先抓连接词-再补细节`，主题 hub `en::topic::travel`）；`batch_id` 是幂等键，
  重复条目用 `duplicate_of` 复用节点。`checkRunRequest` 只做 `io_check` 那类结构校验（**影子图**：同一份
  请求里先建节点、再给它们设目标必须算合法）。
- **对拍**：`app/tool/` 留下三件式 harness（`ingest_parity_reference.cjs` 用 node 跑 MindNet `src/ingest.js`
  → `dart run tool/ingest_dump.dart` 跑这一层 → `ingest_parity_compare.cjs` 逐字段比较；需要外部
  `E:\Document\MindNet` 检出，可用 `MINDNET_SRC` 覆盖）。示例信封上 `PARITY OK`：6 节点 / 7 边 / 14 动作 /
  6 条标准条目，除五处有意差异外逐字段相同。
- **五处有意差异**（都写进 library doc 并被测试钉住）：① `evidence.quote` 真的带页边那一行（JS 的 `meta`
  没有 `margin_note`，恒 null）；② hub 的 region 写 `第 ? 页`（JS 插值出 `第 undefined 页`）；③ 不做 NFC
  归一化（标准库无此函数、`pubspec.yaml` 无此依赖）；④ `Number()` 语义里 `[]`/`{}` 算"不是数字"；
  ⑤ 汇总不报"几张卡"（卡片是 INGEST §4 的可选呈现层，这一层不产出）。

**刻意选择**：

1. **整份拒绝**：校验不过抛 `MaterialIngestException`（顺序与 `src/ingest.js` 一致、文案是人话 + 第几条），
   绝不让半份材料生效 —— 材料入库是"要么整批进、要么不进"。
2. **不进图 ≠ 丢弃**：疑问/已知/提醒进 `skipped` 并带原因；不认识的记号照收并给 `unknown-mark` 告警
   （INGEST §5 第三条不变量"不认识的输入不会被丢，只会被标待归类"）。
3. **对拍优先于"照文档写"**：第一次逐字段对拍就抓到动作里的边多带了一个 `why` 键（`mindnet.run/1` 的 Edge
   只有 `id/from/to/ls`），已改回去并加断言；页码那处也按 JS 的 `Number(undefined)=NaN` 与
   `Number(null)=0` 之分做了保真（键缺席 → 报"缺少 page"，显式 null → 0）。

**证据**：`app/test/domain/services/ingest/material_ingest_test.dart` 56 例全绿 —— 对拍值（3 个 hash、6 个节点
id/类型/名字、7 条边的顺序与权重、14 条动作与 `evidence`、汇总文案、幂等）、报错族 16 种、告警族 7 种、
角色优先级与 `duplicate_of`、`checkRunRequest` 正反例（含"空 actions 合法"与"要建的节点已存在就报错"）。
`dart analyze lib test` 仍是 95 issues（0 error / 0 warning，新文件 0 条）。

**全量回归**：`flutter test --concurrency=1` → `+1734 ~2: All tests passed!`（exit 0）。轮次六十一 后是
`+1678 ~2`，差值 56 = 这一层的 56 例。

**已知的没做**：这一层只是"信封 → 三样正产品"，还没有接线 —— ① "添加资料"入口（AI 产出信封 → 这一层
→ `knowledge` 动作，出处进 `evidence`/`change_log`）；② TRANSCRIBE 的"照片 → `run/1`"（含出处与置信度）；
③ 资料与卡片的关联类型（线索边 vs 包含边，MEMORY_RECORD §3.5）。`cards.json`/`tts.tsv`/`anki/` 这类
呈现层按契约属于"本步之外"，这一层不做。

---

## 2026-10-16 轮次六十一：界面上的今日清单（Q32c，Lead）

**做了什么**：roadmap §1 控制层验收 / §3 第 5 行的最后一段 —— 轮次五十九 排好了序、轮次六十 交给了模型，
这一轮把它摆到人面前。

- **读法** `app/lib/features/cognitive/application/today_plan_reader.dart`：`readTodayPlan({ankiRepository,
  moment, maxActions, horizonHours})` 只有一条路 —— `getDueCardStates(moment.millisecondsSinceEpoch)` +
  `getKnowledgePoints()` 的 id→标题 → `TodayPlanner.build(..., nowHours: modelHoursOf(moment))`；到期判断与
  `nowHours` 共用同一个 `moment`（否则同一张卡会在"到期"与"现在几点"之间被算到两个时刻）。一个
  `todayPlanProvider`（`FutureProvider<TodayPlan>`）`watchDatabaseRevision()`：答完一张卡，这一页跟着变。
- **页面** `app/lib/features/cognitive/presentation/today_plan_page.dart`：`TodayPlanPage`（AppBar = 标题 + 刷新）
  与公开的 `TodayActionCard`（kind 标签 + 标题 + 价格行 + planner 给的人话理由）。顶部一行"加成未标定：这份顺序是
  提示，不是测量。"，底部一行"候选题的价格来自模型（plan_today / evaluate_problem_fit）；这一页只列到期的卡。"。
- **入口**：复习页 `app/lib/features/anki/presentation/knowledge_page.dart` AppBar 第 4 个按钮
  （`Icons.checklist`，tooltip「今日清单」）。
- **l10n**：`app/lib/l10n/app_en.arb` / `app_zh.arb` 新增 12 个 `todayPlan*` 键（`todayPlanCount`/`todayPlanOmitted`/
  `todayPlanPrice`/`todayPlanFailed` 带占位符），`flutter gen-l10n` 重生成 3 个生成物。

**刻意选择**（三条，理由都在代码注释里）：

1. **没有价格的行不画价格行**：`TodayPlanner` 已经决定"零增益不是价格"，页面在这里补一个 `0.0` 就等于替它撒谎。
2. **页面不重排、不重算**：顺序就是 `plan.actions` 的顺序，`V`/`cost` 只做 `toFixed(3)`/`toFixed(1)`，两种度量各自
   带名字（`留存`/`可达性`）—— 不把两个数字当成同一个单位。
3. **只列复习侧，并如实说明**：候选题目录目前只有模型能提，所以读法传一份空报告（`kNoProblemCandidates`）；
   "没有题"与"题没有价格"是两件事，页末一行把这件事说明白。

**证据**：`app/test/features/cognitive/presentation/today_plan_page_test.dart` 7 例全绿 —— 真库四例（空的一天明说空、
到期卡进清单且带"留存 V="与理由、未到期的卡不进清单、刷新后新卡出现）+ 假清单三例（无价格不画价格行、两种度量
分名且顺序就是 planner 的顺序、`considered: 3` 时报"另有 2 件"）。假清单用 `todayPlanProvider.overrideWith` 而不是
造一堆卡：页面的契约是"照着 `TodayPlan` 排版"，价格算术归 `app/test/domain/services/scheduling/today_plan_test.dart` 管。

**全量回归**：`flutter test --concurrency=1` → `+1678 ~2: All tests passed!`（exit 0）。轮次六十 后是 `+1671 ~2`，
差值 7 = 这一页的 7 例；`dart analyze lib test` 仍是 95 issues（0 error / 0 warning）。

**已知的没做**：`plan_today` 与这一页都只排"现在到期的卡"，不排未来几天（`horizon_hours` 只用于 ΔR 的窗口）；
候选题在这页上永远缺席（要模型提）；清单页还没有"做完打勾"的回写 —— 那是复习页的事，这里只读。

---

## 2026-10-16 轮次六十：日计划接进 AI 工具（Q32b，Lead）

**做了什么**：roadmap §1 控制层验收 / §3 第 5 行的第二半 —— 轮次五十九 的纯逻辑核心有了调用方。

- 新工具 `app/lib/features/ai/tools/today_tools.dart`：`PlanTodayTool`（`name: 'plan_today'`）。
  参数：可选 `problems[]`（形状与 `evaluate_problem_fit` 相同）、`start_knowledge_point_ids`、
  `max_actions`（clamp 1–50）、`horizon_hours`（clamp 1–720）、`now`。`run` 的顺序是：先算题目的评估报告
  （没有候选题就用一份空报告，不假装跑过快层），再取 `AnkiRepository.getDueCardStates(now)`，
  再拿 `getKnowledgePoints()` 的 id→标题当人话标题，最后 `TodayPlanner.build(...)`。
  输出：摘要逐条 `'1. [复习|练习] {标题}，retention V=…：{理由}'`，结尾固定一行
  `'加成未标定：这份顺序是提示，不是测量。'`；`modelResult` 直接是 `TodayPlan.toJson()`。
  空的一天不是空壳：摘要明说"今天没有到期要复习的卡，也没有可排的题：清单是空的（这不是"没事做"，
  只是到期队列与候选题都空着）"。
- **重构（为了让两个工具给出同一个价格）**：`app/lib/features/ai/tools/cognitive_tools.dart` 把
  `EvaluateProblemFitTool.run` 里的装配抽成顶层 `evaluateProblems({ankiRepository, tagRepository, model,
  candidates, moment, startKnowledgePointIds})`（读标签树 → `CognitiveTag.fromTag`；每个知识点一条代表卡；
  kp→tag 桥 `KnowledgePointTagBridge`），两个工具共用；原先只服务一个工具的私有静态
  `_parseProblems/_stringList/_doubleOrNull/_representativeRow` 被顶层
  `parseProblemCandidates/stringListOf/doubleOrNullOf` 取代（否则 analyze 报 `unused_element`）。
- 注册：`app/lib/features/ai/domain/tool_registry.dart` 在 `EvaluateProblemFitTool(...)` 之后加
  `PlanTodayTool(ankiRepository: anki, tagRepository: tags, model: model, clock: clock)`，
  所以 `ToolRegistry.byName('plan_today')` 能取到。

**刻意选择**（三条，理由都在代码注释里）：

1. `readOnly: true` 而 `riskFor` 保持 `ToolRisk.write`：它不改任何数据，但它给的是"去做什么"，
   与"读一眼"不是一类。
2. `max_actions`/`horizon_hours` 有硬边界（1–50 / 1–720 小时），且摘要结尾永远带"加成未标定"——
   这份顺序是提示不是测量，不能因为多问几次就变成事实。
3. 空清单与"没有价格"分开说：前者是一天真没事，后者仍留在清单里只给理由（`TodayPlan.omitted`
   报出被 `max_actions` 裁掉几件）。

**证据**：`app/test/features/ai/today_tools_test.dart` 7 例全绿 —— 只读性（`AiPermissionMode` 下从不弹审批）、
注册表里真的能 `byName('plan_today')`、空白天、到期卡进清单且 `kind: review`/`metric: retention`/gain > 0、
未到期卡不进清单、候选题被 `reachability` 定价（`cost: 2.0`，`mixes_metrics: true`）、`max_actions: 1` 时
`considered: 2` 且摘要含"另有 1 件排在清单外"。这一条候选题用例要求 fixture 里有两个顶层标签
（`tag-a-island` < `tag-b-lit`，规则 4 的链方向由 id 决定）**并显式 `start_knowledge_point_ids: [litId]`**，
否则 `add_in_edges` 没有可连的点亮节点 ⇒ 题目不给价格（第一次就是这么红的，payload 里 `why` 写着
"诊断全是 empty/dead_end"）。

**全量回归**：`flutter test --concurrency=1` → `+1671 ~2: All tests passed!`（exit 0）。轮次五十九 后是
`+1655 ~2`，差值 16 = Q32a 的 9 例 + Q32b 的 7 例；`dart analyze lib test` 仍是 95 issues（0 error / 0 warning）。

**已知的没做**：UI 上的清单页（Q32c，已在轮次六十一补上）；`plan_today` 仍只会看"现在到期的卡"，不排未来几天的
（`horizon_hours` 只用于算 ΔR 的窗口，不用于挑卡）。

---

## 2026-10-16 轮次五十九：日计划的纯逻辑核心（Q32a，Lead）

**做了什么**：roadmap §1 控制层验收「输出"今天该做的练习清单"，按收益/成本排序」的第一半 ——
新增 `app/lib/domain/services/scheduling/today_plan.dart`，把两类已经在算价格的输入合成一份清单：

- 卡片侧：`DsrCardState.read(row)` + `DsrMemory.retrievability` 算"复习这张卡，到 24 小时后能多留下
  多少 R"（`retentionGainOf`：`before = R(now+24)`，`applyReview` 后 `after = R(now+24)`，价格 = ΔR / `costReview`）
  —— 与题目侧 `dsrRetentionProbe` 是同一个量、同一个窗口，不是第二套留存数学。
- 题目侧：直接取 `ProblemEvaluation.counterfactual*`；价格已经是 `V`，所以收益 = `V × 成本`
  （成本用 planner 自己的 `costLink` / `costRetrieval`），**不在这里重算引擎**。
- 排序是一条全序：价格降序（无价最后）→ kind（复习先于练习）→ 到期日升序（无日期最后）→ id 升序；
  `take(maxActions)`，`considered` / `omitted` 如实报出被丢掉的条数。

**三条刻意选择**：① 每项都带 `metric`（`retention` / `reachability`），因为两把尺子问的不是同一个问题，
`TodayPlan.mixesMetrics` 明说这份清单里两种都有；② 没有正价格的项目（撞到上限的卡、没有价格的题）
**不写 0.0**（沿用轮次五十八的规则：零增益不是价格），它们排在有价格之后，理由仍是人话；
③ `TodayPlan.uncalibrated` 恒 `true`，这一层只把已有的两个价格摆在一起，没有引入任何新常数 ——
日计划不是"第二个评分系统"，它只是把 driver 已有的读数搬到用户面前。

**验收**：`app/test/domain/services/scheduling/today_plan_test.dart` **9 例全绿**
（空计划也说明未标定 / 会忘的卡按留存定价且 `value == gain/cost` / 上限卡不报价格并回落 `unitKey` 当标题 /
`retentionGainOf` 在上限处 `before == after == 0.9`、`gain = 0.0` 精确（把轮次五十八的实测写成断言）/
题目侧保留 `metric` 且 `gain = V × 成本` / 无价题目只说理由 / 有价在前、无价按 kind 再到期日 /
cap 与 `omitted` / 输入顺序不影响输出）；`dart format` 2 文件（仅行宽）；`dart analyze lib test`
95 issues（与基线同数，仅既有 info，**0 error / 0 warning**）。

**还剩的另一半（Q32b）**：把这份清单接进 AI 工具（`plan_today` 一类，照 `EvaluateProblemFitTool` 的形状）
与 UI；在那之前它只是领域层的一个函数，用户还看不到"今天做这几件事"。

---

## 2026-10-16 轮次五十八：留存探针接进题目排序（Q31b，Lead）

**做了什么**：把轮次五十七做出的记忆层与探针接到找题的定价上（roadmap §2-A 缺① 的 `retention` 侧收尾）：

- `app/lib/domain/services/cognitive/problem_evaluator.dart`：`_runFastLayer` 的机制列表加上
  `FastMechanisms.memory`，`FastPlanner.plan(...)` 多传 `retentionProbe: dsrRetentionProbe(params: engine.memoryParams)`
  —— 常数取引擎自己那份 `DsrParams`，不在评估器里重写一份；文件头第 5 条边界补一句"记忆层不注册
  `round.*` 钩子，所以诊断逐位不变，变的只是留存指令能不能定价"。
- `app/lib/domain/services/cognitive/dsr_retention_probe.dart`：`dsrRetentionProbe` 的 `params` 改成
  可空（`{DsrParams? params}`，null = 引擎默认），这样调用方不必 import `srs/dsr_memory.dart`。
- `_bestPlanEntry` 的 doc 写明：现在两种度量（`reachability` 开一条边 / `retention` 复习一个节点）
  都会出现，`V` 对两者都是"增益/成本"，所以按 `value` 比，但问的问题不同 ⇒ 价格与 `metric` 一起上报
  （`counterfactualMetric`），永不并进 `rankKey`。

**一个诚实边界（实测）**：`ms = 1.0`（上限）时 `R0 = 1.0`、`S = legacy_k × R0 = 24`，在
`u = hours + 24` 处 `t/S = 1` ⇒ `psi = 0.9` 精确，而复习后的稳定性增益是 1.0（`R0` 已封顶）⇒
`gain = 0.0` **精确**。零增益**不是价格**：它永远不会改变任何次序，而写一个 `0.0` 出去像在测量
"这道题一文不值"，其实只是撞到上限。所以 `_bestPlanEntry` 只收 `value > 0` 的条目 —— 上限节点
和"没装记忆层"一样都不报价格；两者在 planner 的 `simulated` 上分得很清楚，那才是"这个问题
问过没有"的标记。（这一条是被测试逼出来的：`cognitive_tools_test.dart` 里"孤立节点不报价格"
那条断言在接线后先红，实测输出为 `{metric: retention, instruction: lower_threshold, value: 0.0,
why: …24 小时后的留存 0.9 → 0.9}`，于是把"零增益也算有价"改成"零增益不报"。）

**验收**：`app/test/domain/services/cognitive/problem_evaluator_test.dart` 15 例（新增 2 例：
"有入边但没动量 ⇒ `retention` 价格 > 0"，刻意用 `encodingStrength: 0.5`，因为 1.0 时增益恰好是 0；
"在上限 ⇒ 完全不报价格"）、`app/test/domain/services/cognitive/dsr_memory_layer_test.dart`
9 例（新增 2 例：给探针就模拟并报 `cost = costRetrieval`；不给探针就 `simulated: false` 且值不是 0），
全绿；`dart format` 5 文件 3 changed（仅行宽）；`dart analyze` 4 文件 `No issues found!`。

**顺手排掉的一个 fixture 偶发（根因已定位）**：三目录连跑时 `cognitive_tools_test.dart` 的
"a priced dead end…" 约 1/3 概率红（`Expected: not null / Actual: <null>`）。插桩定位到差别在
**图的入边**：`CognitiveGraph.fromTags` 规则 4 让每一对顶层 tag（互为兄弟）只连一条有向边，
方向 =（importance 降序，平手按 `id` 升序），而标签 id 由 `TagRepository` 生成为 `tag-<uuid>`
⇒ 两个顶层标签谁在链头每次运行都可能翻转，只有链头才是 in=0（被判 `empty`、有 `add_in_edges`
可定价），另一个是 in=1（被判 `weak`、无价）。排除过：点火随机（`T_ign` 固定 0，`_ignitionHit`
在 (0,1) 内直接抛 `UnsupportedError`）、墙钟/预算（工具只有注入的 `clock`，无 `Stopwatch`）、
`hashCode` 迭代序（两文件无此用法）。修法只动测试：给两个标签固定有序 id
（`tag-a-island` < `tag-b-lit`），让 fixture 自己声明拓扑。生产代码未动 —— 引擎给定 id 的输出
逐字节确定（文件 doc 也是这么写的），随机的是 fixture 生成的 uuid。

**还剩的另一半**："今天做这几件事"的日计划（把题目与闪存卡合成一份按 `V(π)` 排的清单，
roadmap §3 第 5 行验收）。

---

## 2026-10-16 轮次五十七：`memory.dsr` 装上快层 + 生产留存探针（Q31a，Lead）

**做了什么**：roadmap §2-A 缺① 的另一半 —— 反事实规划器里 `retention` 类指令
（`strengthen_impression` / `interval_retrieval` / `lower_threshold`）以前因为快层**没装记忆层**，
永远算不出"复习一次到明天能多留住多少"，只能报"未模拟"。现在：

- `app/lib/domain/services/cognitive/fast_engine.dart`：新增 `FastMechanisms.memory = 'memory.dsr'`，
  按需安装（模板照 `rhythm.gate`：构造里 `mechanisms.isEnabled(...)` 才建）。装后
  `FastEngine.review(nodeId, event)` 不再返回空钩子，而是走 DSR：`DsrState.fromJson`/`DsrState.initial`
  懒建状态 → `DsrMemory.applyReview` → 写回 `node.m['memory_dsr']`（新公开常量
  `FastEngine.memoryBagKey`）并同步 `node.ms` / `node.lastReviewTime`（参考实现的 `synced()`）。
  新增 `FastEngine.dsrStateOf` / `dsrBagOf` / `dsrRetrievabilityOf` 三个静态方法，
  `clone()` 复制 `_memoryParams`（bag 由 `graph.copy()` 深拷贝）。
- `app/lib/domain/services/cognitive/dsr_retention_probe.dart`（新文件）：
  `RetentionProbe dsrRetentionProbe({DsrParams params})` —— 图外节点返回 `null`（不是 0 增益），
  其余走 `FastEngine.dsrRetrievabilityOf`；另有 `seedDsrState(node, state)` 供"知道真实卡状态"的调用方
  先塞 bag。

**为什么默认不装**：conformance 向量是在没装的时候生成的，而参考实现的 `memory.dsr` 也**不注册任何
`round.*` 钩子**（它是 lazy `ensureState` + `synced()`），所以"装"对轮次数值是零改动 —— 它只改变
"能不能给一次复习定价"。同理，`review()` 在没装时仍然返回空列表，而不是假装复习过。

**诚实边界**：bag 目前是从 `node.ms` 懒建的（`R0 = min(1, ms)`、`S = legacy_k * R0`、`D` 取默认），
也就是**先验价格**，不是这张卡自己的价格；参数来自 `DsrParams`（移植的 `PARAMS`）而不是引擎的
`FastParamSpec` 表（那张表只吃数值路径，而记忆层有非数值参数 `decay_model`，镜像进表属于标定那一片）。

**验收**：`app/test/domain/services/cognitive/dsr_memory_layer_test.dart` 7 例全绿；
`dart format` 3 文件（1 changed）；`dart analyze` 三个文件 `No issues found!`。

**当时还剩的另一半（已在轮次五十八完成）**：把探针传进 `ProblemEvaluator`（`FastPlanner.plan(retentionProbe: ...)`，并把
`memory.dsr` 装进快层引擎），于是 `retention` 指令从"未模拟"变成有价格、`counterfactualMetric`
会出现 `'retention'`（工具输出的键 Q30 已经加了）；再往后才是"今天做这几件事"的清单。

---

## 2026-10-16 轮次五十六：反事实 `V(π)` 进入题目排序（Q30，Lead）

**做了什么**：roadmap §2-A 缺① —— 控制层那个反事实规划器以前只负责"判定"，现在它的价格也参与
找题的次序。改动全在两个文件：

- `app/lib/domain/services/cognitive/problem_evaluator.dart`：`ProblemEvaluation` 多四个可空字段
  （`counterfactualValue` / `counterfactualMetric` / `counterfactualInstruction` / `counterfactualWhy`）；
  `evaluate` 里 `_diagnose` 重构成 `_runFastLayer`，返回私有的 `_FastRun{diagnosis, plan}` ——
  **诊断与价格取自同一个引擎**，不可能描述两次不同的运行；
  `FastPlanner.plan(...)` 的 `List<FastPlanEntry>` 里只挑"模拟过、有 `metric`、节点就是本题目标"的那条
  （`_bestPlanEntry`，同 `value` 取目标序靠前者），价格随后进 `_judge` → `_evaluation`，
  理由行追加 `；反事实：<指令>（<度量> 增益 X / 成本 Y → V=Z；<为什么>）`（`_num` 三位小数）。
  新增公开静态 `ProblemEvaluator.compareByRank`：`rankKey` 降序 → `V(π)` 降序（`null` 最末）→
  `problemId` 升序；`_markRedundant` 重建条目时**复制**这四个字段（价格是题目自己那个节点的属性）。
- `app/lib/features/ai/tools/cognitive_tools.dart`：`evaluate_problem_fit` 每条题目多一个
  `counterfactual{metric,instruction,value,why}`；**不可模拟时整个键缺席**（不是 `value: 0`）。

**为什么 `V(π)` 只当 tie-break 与解释，不并进 `rankKey`**：增益来自未标定的机制常数，成本
1.0 / 2.0 / 0.2 同样是拍的；把它算进主键，等于让"提示"穿上"测量"的衣服。`FastPlanner` 对
`retention` 类指令在没有 `RetentionProbe` 时明确是"未模拟"（`simulated: false`），所以
"这道题没有价格"是合法状态，输出里就不该出现一个假的 0。同一原因，工具输出里的 `rank_key`
仍然是唯一主键。

**验收**：`dart format` 4 文件；`dart analyze lib test` → `95 issues found`，
`error`/`warning` 各 0（与改动前同数）；`flutter test
test/domain/services/cognitive/problem_evaluator_test.dart --concurrency=1` → `+13 All tests passed!`
（新增 3 例：有价格 / 关掉快层四个字段全空且理由没有"反事实" / 纯 tie-break 不越过 `rankKey`）；
`test/features/ai/cognitive_tools_test.dart --concurrency=1` → `+13 All tests passed!`
（新增 1 例 priced dead end；既有那条"没有别的节点可连"补了 `counterfactual` 键缺席的断言）；
全量 `flutter test --concurrency=1` → **`+1644 ~2: All tests passed!`**（上一片 `+1640 ~2`，+4 例）。

**还剩的另一半**：`retention` 侧要先把记忆模块的 `RetentionProbe` 接进 fast layer，否则只有
`reachability` 一种度量有价格；roadmap §3 第 5 行验收要的"今天做这几件事"的清单（把题目与闪存卡
合成一份按 `V(π)` 排的日计划）仍未做。

---

## 2026-10-16 轮次五十五：认知排序的开关与"未标定"标注上屏（Q29e，Lead）

**做了什么**：认知排序档位（roadmap §2-D）从"服务里能跑"变成"用户能开、开了看得懂"。

- `app/lib/features/thread/application/thread_rank_service.dart`：新增
  `cognitiveRankEnabledProvider`（`FutureProvider<bool>`，读 schema v16 的那一列），
  它和 `ThreadFeedNotifier` 读的是同一列，不存在第二个真相。
- `app/lib/features/thread/presentation/thread_page.dart`：AppBar 的 ⋮ 从 `_RhythmToggle`
  （只有一个复选项）重构成 `_ThreadMenu`（两项：注意力可用性读数、认知排序，`_ThreadMenuItem`
  枚举区分）。翻认知排序那一项会 `setCognitiveRankEnabled()` 落库 → invalidate 开关 provider →
  **当场 `sort()` 一次**：用户翻开关期待的是"现在"的次序就变，不是等下一次数据变化。
  开关打开时列表上方多一行说明（`Icons.psychology_outlined` + `threadCognitiveRankNote`）：
  "认知排序已打开：离当前目标或刚复习过的知识点近的任务排前面；**加成未标定，只是次序提示**"。
- ARB：`app/lib/l10n/app_zh.arb` / `app_en.arb` 各加 `threadCognitiveRankToggle`、
  `threadCognitiveRankNote`，跑 `flutter gen-l10n` 重生成三个 `app_localizations*.dart`。

**为什么把"未标定"直接写在列表上方**：这一档的距离加成（1.6 / 1.3 / 1.1）与精力强度（±0.25）
全部未标定，而它会让次序**真的变**；只说"打开了"而不说"凭什么是这个次序"，用户会把提示当成测量。
默认关（schema v16 的默认值）与这行说明是同一件事的两半。

**验收**：`dart format` 3 文件 → `0 changed`；`dart analyze lib test` → `95 issues found`，
`error`/`warning` 各 0（与改动前同数）；`flutter test
test/features/thread/presentation/thread_page_cognitive_test.dart --concurrency=1` →
`+1 All tests passed!`；全量 `flutter test --concurrency=1` → 见提交记录（上一片 `+1639 ~2`，
本片 +1）。

**还剩的另一半**：这一档加成常数的标定（外部，roadmap §4 末的六实验）；在那之前它默认关，
打开也只是提示。

---

## 2026-10-16 轮次五十四：认知排序档位接进排序服务（Q29d，Lead）

**做了什么**：`app/lib/features/thread/application/thread_rank_service.dart` 里三处改动——

- `ThreadRankService.build()` 多两个参数：`CognitiveRankSeed cognitiveSeed`、
  `bool cognitiveRankEnabled`。候选就是段落 B 的次序（`baseIndex` = 它在段落 B 里的位置），
  所以这一档**只重排、不重算可行域**，与段落 B 对段落 A 的关系一致。
- `ThreadFeed` 新增 `cognitiveRank`（`CognitiveRankOutput?`，null = 这一档没开）与
  `cognitiveFor()` / `cognitiveReasonFor()`；`readyTasks` 在开关打开时先走认知次序，再拼段落 B、
  最后段落 A 兜底——**永远不会丢任务**（实现拆成 `_balancedOrder()` + 认知前插两段）。
- `ThreadFeedNotifier.sort()` 读库里的开关（`ThreadRankRepository.getCognitiveRankEnabled()`）与
  素材（`cognitiveRankSeedReaderProvider`）：**开关读失败 = 保持关**（一次读失败不该把用户看惯的
  加权次序换成一个未标定的次序），**素材读失败 = 退化成"没有读数"**，两者都不让整个排序失败。

**难度代理定的口径**（`_difficultyFor`）：任务挂着的知识点里**最弱**的那块编码上限
（`1 − min(priorR0)`），且只看 `priorConfidence > 0` 的读数——置信度 0 表示"只是先验、不参与加权"，
一条没有信念的先验不该决定"这题难不难"。没有可用读数就返回 null（精力分量取中性 1.0）。

**验收**：`app/test/features/thread/thread_rank_service_cognitive_test.dart` 5 例
（关着完全不产出 / 开着但没有起点则一个都不动、理由行说「没有认知读数」/ 刚复习过的知识点
0 跳 ×1.6 把任务提到最前并标 `movedUp` / 离目标 1 跳 ×1.3、图外的知识点什么都不给 /
难度取最弱编码上限且 α=0 时把弱编码的任务换下去）→ `+5 All tests passed!`；
`app/test/features/thread/thread_feed_notifier_test.dart` 2 例（开关关着没有这一档、库里打开之后
排序结果真的带上它）→ `+2 All tests passed!`；`dart format` 3 文件 0 changed；
`dart analyze lib test` 95 issues（与改动前同数，0 error / 0 warning）。

**还剩的另一半**：UI 上的开关（线程页 AppBar 菜单 + ARB 文案 + widget 测试）与"这一档未标定"的
可见标注；加成常数的标定仍属外部实验。

---

## 2026-10-16 轮次五十三：认知排序档位的开关落库（Q29c，Lead）

**做了什么**：schema v16 给 `thread_rank_settings` 加一列 `cognitive_rank_enabled`
（`app/lib/data/database/tables.dart`），**非空、默认 false** —— 现有加权排序的权重分是用户自己
在事件属性页上定的，而认知排序的距离/精力加成全部 `[未标定]`；一个还没标定的次序不该默认替掉
用户已经看惯的列表。仓储侧新增 `ThreadRankRepository.getCognitiveRankEnabled()` /
`setCognitiveRankEnabled(bool)`（`app/lib/data/repositories/thread_rank_repository.dart`）。

**迁移**（`app/lib/data/database/database.dart`）：`schemaVersion => 16`、`onUpgrade` 加
`if (from < 16) await _upgradeV15ToV16();`、`_upgradeV15ToV16()` 走 `_addColumnIfMissing`、
`_ensureColumns()` 的 `expected` 表加 `'thread_rank_settings'` 一项。同一趟顺手补了一处真会炸的
漏洞：`_tableFor('thread_rank_settings')` 原本落到 `throw ArgumentError('unknown table ...')`，
而 `_ensureColumns()` 与 `.tfpkg` 恢复路径都要按 SQL 表名解析这张表——v16 的自愈第一次打开就会
踩到它，所以补了那个 case。

**验收**：`app/test/data/database/v16_migration_test.dart` 2 例（真实 v15 文件升级后老权重一个
不变、新开关读作默认关，且用户打开过才会落 true；被盖成 v16 却没有这一列的文件靠 `beforeOpen`
自愈并能写进去）→ `+2 All tests passed!`；`dart format` 4 文件 0 changed；`dart analyze` 三个改动
文件只剩 3 条**既有** info（`unnecessary_import` / `use_super_parameters` / `prefer_single_quotes`）。

**生成代码**：`database.g.dart` 由 `build_runner` 重新生成（新增 `cognitive_rank_enabled` 列与
Companion 字段，46 处引用）。本机 `dart compile aot-snapshot` 写不进含非 ASCII 的路径，
`build_runner` 因此直接退出（exit 78）；绕法是建一个 ASCII 目录联接（junction）指向 `app/`，从联接
路径跑 `dart run build_runner build`（日志：`Built with build_runner/aot in 69s; wrote 474 outputs`）。

---

## 2026-10-16 轮次五十二：认知排序素材的数据库读取（Q29b，Lead）

**做了什么**：新增 `app/lib/features/thread/application/cognitive_rank_reader.dart`，它是
"数据库 → 认知排序素材"之间唯一的一跳，把前两轮的纯逻辑接到真实库上：

- 目标节点 = `ThreadState.goalNodeId`；标签树 = `Tags.parentId` 投影成 `MindNodeInfo`
  （显式按 id 排序，不依赖插入顺序）。
- 刚活动 = `review_logs.reviewed_at` 与 `exposure_logs.exposed_at` 两侧各取最近 40 条、
  只看 12 小时窗口（两个常量都标了 `[未标定]`），按时间倒序合并（同一毫秒用卡状态 id 兜底，
  让同一份数据两次读出同一结果），再经 `card_states.knowledge_point_id` 落到知识点上，
  去重保留最近的那次。
- 知识点标签只认 `object_type = 'knowledge_point'`（任务自己的标签不是标签树上的节点）；
  名字来自 `AnkiRepository.getKnowledgePoints`；α 来自 `StudyRhythmReader`，
  **提示关掉时取中性 1**，不是 0 —— "没读数"和"注意力为零"是两件事。

**踩到并钉住的一条旧形状**：v1 的 `getOrCreateCardState(cardTemplateId)`
（`app/lib/data/repositories/anki_repository.dart:190-211`）只写 `card_template_id`、
`knowledge_point_id` 留空。这种卡状态上的复习日志**没有知识点可落**，读取器就什么都不说
（有一条用例专门造这种孤儿卡状态并断言活动列表为空）。写测试时第一版就是用这条路径写"正常复习"，
于是三条用例先红了——正好说明这个读取器不会替旧数据编一个节点。真出现大批 v1 日志时的补救是
回填 `knowledge_point_id` 或在迁移里解析模板，现在库里没有这种数据，机制也不依赖数据。

**验收**：`flutter test test/features/thread/application/cognitive_rank_reader_test.dart --concurrency=1`
→ `+9 All tests passed!`（空库中性 / 目标与树透传 / 复习日志的近因、去重与出窗 / 曝光合并 /
孤儿卡状态不说话 / 知识点标签的分类与排序 / 名字 / α 开关 / 端到端：目标 2 跳写 goal、
刚复习过写 activity）；`dart analyze` 两个新文件 `No issues found!`；全量 `flutter test` 见提交前一次跑。

**还剩的另一半**：`ThreadRankService.build()` 接受 seed 并按开关决定是否应用认知次序、
`ThreadFeed` 暴露次序与理由、开关落库（`ThreadRankSettings` 加列 = 一次 schema 迁移）+ UI。

## 2026-10-16 轮次五十一：认知排序档位的接线层（Q29a，Lead）

**做了什么**：新增 `app/lib/domain/services/scheduling/cognitive_rank_inputs.dart`（纯逻辑）。
上一轮只做了"给定 inputs 怎么排"，这一轮做"inputs 从哪来"里的**距离**那一半：

- `CognitiveRankSeed` = α + 标签树投影（`MindNodeInfo` 列表）+ `goalNodeId`（线程目标所在的标签）
  + 刚活动的知识点 id + 知识点→标签 + 知识点名字。全是"读好的事实"，没有一个是这里推断的。
- `CognitiveRankWiring.build(seed, candidates)` 在标签图上量候选任务挂着的知识点离起点的距离，
  产出 `CognitiveRankInputs`。只对候选真正挂着的知识点跑 BFS（不为库里每个知识点跑一遍），
  顺序全部显式排序。
- 三条规则写进代码与测试：超过 `kCognitiveRankMaxHops` 跳、图上不连通、知识点没有标签、
  标签图是空的 —— **一律不写 origin**（宁可什么都不说，也不猜一条近路）；
  同跳数"刚活动"优先于"目标"（刚做过的事比远处目标更该影响现在做什么）；
  候选挂多个标签时取最近的那个。

**证据**：`app/test/domain/services/scheduling/cognitive_rank_inputs_test.dart` 15 例
（手搭标签树 `phi─mech/mech2─sub─far`，覆盖 0/1/2/3 跳、空图、幽灵标签、无标签、
同跳数来源优先、多标签/多活动取最近、顺序无关的确定性、名字与 α 透传后排序真的会动）；
`flutter test test/domain/services/scheduling --concurrency=1` → `+125 All tests passed!`；
`dart analyze` 两个新文件 `No issues found!`；`dart format` 0 changed。

**写这一轮时踩的两条坑**（都改成规则了）：`DiffusionBoost.distance(x, x)` 对同一个字符串
直接返回 0，哪怕它不在图里 —— 所以空图必须显式短路，否则"两个一样的字符串"会被当成
"同一个节点"；理由行 0 跳那一档只说"刚活动过/就是当前目标"，`via` 的名字只出现在 1/2 跳
的句子里，所以"名字有没有传进去"要用 1 跳的用例断言，不能用排在最前面的那条。

**还剩的另一半**：从数据库读这几种素材（`review_logs` / `exposure_logs` → `card_states.
knowledge_point_id` 算"刚活动"、`Tags.parentId` 投影成图）、`ThreadRankService.build()`
接受 seed、开关落库（`ThreadRankSettings` 加列 = 一次 schema 迁移）+ UI。

## 2026-10-16 轮次五十：认知排序档位的算法核心（Q28，Lead）

**做了什么**：新增 `app/lib/domain/services/scheduling/cognitive_rank.dart`（纯逻辑，不碰数据库）。
它把 §2-D 落点要求的三个输入变成一种可选的排序：`availability`（α(τ)，来自 `StudyRhythm` 的读数）、
调用方算好的 `知识点 id → (跳数 0/1/2, 来源 activity/goal)`、以及每个候选的难度代理（0..1，可缺）。
`score = reachability × availabilityFactor`，距离 0/1/2 分别 ×1.6 / ×1.3 / ×1.1（超过 2 跳 = 1.0），
精力分量在 `1 ± 0.25` 内摆动；输出是重排后的次序 + 每个 hit 一条中文理由 + `uncalibrated: true`。
新增 `app/test/domain/services/scheduling/cognitive_rank_test.dart` 21 例。

**为什么这么切**：段落 A（`ThreadRanker` 硬约束）与段落 B（`DomainBalanceRanker`）都已经在跑，
这一层是**并存的可选档位**，不是替换。三个刻意的选择：

- 加成常数与 `diffusion_boost.dart` 里 D12 的 `1.8 / 1.3` **刻意分开**：那一组是"答错之后给
  关联卡片加抽卡权重"（`MINDNET_CONTRACT` §6.5 / D5），与"目标可达性"不是一回事，共用一组数
  会让人以为这里有测量；两组常量名字不同、文件 doc 写明。
- 难度读数缺失时候选**不消失**、精力分量取中性 1.0，理由行如实写"缺难度读数"；距离与难度
  **都缺**时直说"没有认知读数，按默认次序"——缺数据不等于低价值。
- 完全没有输入时 `score` 全为 1.0，次序**等于** `baseIndex` 次序：接线之后忘了喂输入，
  用户看到的仍是原来的列表，而不是一个悄悄乱掉的列表。这条有测试钉住。

**验收**：`flutter test test/domain/services/scheduling/cognitive_rank_test.dart --concurrency=1`
→ `+21 All tests passed!`；`dart format` 0 changed；`dart analyze` 两个新文件 `No issues found!`。

**还剩的另一半**：接线——`ThreadRankService.build()` 接受 `CognitiveRankInputs`、`ThreadFeed`
暴露认知次序与理由、开关落库（`ThreadRankSettings` 加列 = 一次 schema 迁移）、把"刚活动节点"与
目标节点的距离算出来（标签树 / `CognitiveGraph`）、UI 呈现。

## 2026-10-16 轮次四十九：自由挖空 + 错题强制绑定接进复习 UI（Q26，teammate threadflow-engine）

**结论（先 recon 再动手）**：算法/表/队列车道早已在——`app/lib/domain/services/cloze/cloze_engine.dart`
的 `ForcedMachine.grade`/`chooseSlot`/`discoverCandidates`、`CardStates.forced`/`forcedStreak`
（`app/lib/data/database/tables.dart:314-319`）、`app/lib/features/anki/application/review_service.dart:271-282`
的强制车道都实现且有测试。缺的确实是**用户路径**：句中 `______` 是死文本，
「今天之内再出现」只能等下一轮队列。

**做了什么**
- 新增纯逻辑 `app/lib/domain/services/cloze/forced_loop.dart`（会话内重做计划：答错 → 立即重做；
  答对一次 → 约 10 分钟后再现；连续两次答对 → 解除；重插间隔由调用方传入既有常量
  `ReviewService.relearnGapCards = 3`，不另立口径）与 `app/lib/domain/services/cloze/cloze_layout.dart`
  （把 `______` 拆成 prefix/blank/suffix，槽位下标缺失或与下划线错位时返回 null）。
- `ReviewOutcome` 增 `immediateRedo`（默认 false，只加不改语义）；新增 `ReviewService.refreshItem()`——
  `grade()` 的契约是「`item.cardState` 是本次作答之前的行」，会话内重做必须先读新行，
  否则 D11 的「连续两次答对」永远数不到第二次（反例已写进测试）。
- 复习页：挖空就地渲染（`ValueKey('cloze-sentence')` + `ClozeLayout`）、答案填回那个空、
  「新空」chip（`isNew`）、会话内闭环（`_reinsertForced` + `_skipGatedCards` + 与 `_queue` 平行的
  `_floors` + `_sessionForced`）、没到 10 分钟下限时的等待态（`_ForcedWaitState`，分钟数取
  `ForcedLoop.waitRemaining`）。模板卡 / 单选 / 自评三条路径行为未变（13 条既有 review_page 用例继续绿）。

**口径分歧的显式选择**：D11 写「答错立即重做 → 约 10 分钟短间隔再出现」，而 `buildQueue`
（`review_service.dart:271-282`）对强制卡只看位置、不看 `dueAt`——取「两个门都要过、取下限更晚者」，
并在 `forced_loop.dart` 的 doc 与测试注释里写明这是对既有口径差异的选择、不是新规则。

**验收**：`flutter test test/features/anki test/domain/services/cloze --concurrency=1` → `+128 All tests passed!`；
全量 `flutter test --concurrency=1` → `+1578 ~2 All tests passed!`；`dart format` 0 changed；
该切片 0 error / 0 warning（`dart format` 顺带重排 12 个既有文件，抽样确认为纯换行、无语义改动）。
本片 3 个 ARB 键（`knowledgeForcedWait`/`knowledgeForcedWaitCheck`/`knowledgeNewBlank`）随轮次四十八的
提交一起落库——ARB 与生成文件无法按 slice 切分。

**遗留**：10 分钟「到点放行」在 widget 测试里无法模拟（页面读真实时钟、没有可注入的钟），
由纯规则测试 + service 层 streak 测试覆盖。

## 2026-10-16 轮次四十八：事件侧期望时刻的冲突警告——Q23 的另一半（Q27，Lead）

**做了什么**
- `app/lib/features/thread/presentation/event_properties_page.dart`：`_pick` 拆成
  `_chooseMoment`（日期 + 时间两个选择器，取消返回 null）/ `_pickExpectedAt` / `_pickDeadline`；
  新增 `_resolveExpectedAtConflict(chosen)`（`ScheduleConflict.at` → `freeMomentBefore`/`freeMomentAfter`
  → 复用 Q23 的 `showScheduleConflictWarning`）与 `_scheduleBlocks()`
  （`timeBlockRepositoryProvider` → `ScheduleBlock`，与 `task_detail_page.dart:256-269` 同口径）。
- 新测试 `app/test/features/thread/presentation/event_properties_page_test.dart` 7 例（**先写先红**：
  实现前 4 条冲突用例失败、3 条「不撞 / 改截止时刻」通过，正好把缺口钉在「选完时刻到落库之间」）。

**为什么**
- `docs/DESIGN_BLUEPRINT.md:85`（用户 16）与 `docs/GAP_ANALYSIS.md:54` 的分工是 `expected_at` = 排程的
  期望位、`deadline` = 硬承诺，冲突时**只挪期望位**。轮次四十六接的是任务侧 `dueAt`，事件侧一直是空的。
- 不新造规则、不新增 l10n 键：判定与候选时刻全部来自 Q23 已交付的领域层与弹窗；
  `tasksDueAtConflict*` 的文案本身只讲「撞上了日程块」，与期望/截止无关。
- 读日程块失败不挡用户（冲突检查是提醒不是门禁）；点掉弹窗 = 放弃这次选择（期望时刻保持原值）；
  找不到空闲时刻的那个方向按钮禁用并说明——都是 Q23 已经钉住的口径，这里只做同样的接线。

**验收**
- `flutter test test/features/thread/presentation/event_properties_page_test.dart --concurrency=1`
  → `+7 All tests passed!`；`flutter test test/features/thread --concurrency=1` → `+27 All tests passed!`。
- `dart analyze`（两个改动文件）→ 仅 1 条既有 info（`event_properties_page.dart:337` 的
  `prefer_function_declarations_over_variables`，改动前就在）；`dart format` 第二次跑 0 变更。
- 事件侧**没有**动 deadline：第 7 条用例专门钉住「改截止时刻不弹警告、期望时刻不被碰」。

## 2026-10-16 轮次四十七：注意力可用性上屏——线程页顶部第一次给出 α(τ) 读数（Q25，Lead）

**做了什么**

- schema v15：`app/lib/data/database/tables.dart` 的 `LocalSettings` 加
  `BoolColumn get rhythmHintsEnabled => boolean().nullable()();`（**NULL = 用户从没选过**，
  读作"显示"；迁移绝不替用户写值——这条与 v6 起 AI 列的既有约定一致）。
  `app/lib/data/database/database.dart`：`schemaVersion` 14 → 15、
  `onUpgrade` 追加 `if (from < 15) await _upgradeV14ToV15();`、
  `_ensureColumns()` 的 `'local_settings'` 自愈列加这一列，新增 `_upgradeV14ToV15()`
  （`_tableExists` 探针 + `Migrator.addColumn`）。
  `app/lib/data/repositories/settings_repository.dart` 加
  `updateRhythmHintsEnabled(bool)`。
- 领域层 `app/lib/domain/services/cognitive/study_rhythm.dart`（轮次四十七之前的同一片）：
  把 `rhythm.gate` 的参数接到"这次坐多久"上——`G_vig = exp(-t_on/τ_vig)`、
  负荷自适应周期、duty 开窗都复用 `RhythmGate` 本身，不新造数学。
  `kStudySessionGap = 15 分钟` 是**未标定代理**（本应用没有会话计时器，动作时间只能从
  既有学习日志推导），所以它是一个命名常量 + 注释，而不是散在代码里的魔数。
  没有坐段时返回 `null`：**不假装 α = 1**。
- reader `app/lib/features/thread/application/study_rhythm_reader.dart`：`review_logs.reviewedAt`
  与 `exposure_logs.exposedAt` 各取尾部 500 条当"学习动作"（曝光也算——"读了没测"同样是坐在桌前），
  开关关掉时**不查库**直接返回 hidden。`load` 故意留 0：这屏没跑认知引擎，
  编一个负荷就是把猜测装成测量。
- UI：`app/lib/features/thread/presentation/widgets/thread_status_bar.dart` 里状态条由单行改为
  两行（折叠时仍是一行），新增 `_AttentionHint`（可用性百分比 + 已专注分钟 + 建议 +
  隐藏按钮 + "参数未标定"tooltip；加载中和开关关掉时整块 `SizedBox.shrink()`，
  避免数字闪动）；`app/lib/features/thread/presentation/thread_page.dart` 的 AppBar 加
  `_RhythmToggle` 菜单项（打勾 + 随时把提示请回来）。ARB zh/en 各 +8 键。

**为什么**

- 轮次四十五把 `rhythm.gate` 装进了引擎，但**没有一个界面读它**：`availability` 仍是
  "只有对拍向量和测试看得到"的量（`docs/MINDNET_ROADMAP.md` §2-D 当时剩的另一半）。
  这一片把读数送到用户眼前，并且**同时给建议**——只给一个百分比等于把解释责任推给用户。
- **为什么不给开关默认值**：设置列 NULL 就是"从没选过"，默认显示是出厂行为、不是写进库的值。
  写默认值会让"用户明确选择显示"与"用户从没管过"永远分不开（v6 起就守的规矩）。
- **为什么隐藏按钮和 AppBar 菜单都要有**：隐藏后需要一个**不在读数本身里**的入口把它请回来，
  否则用户一旦点掉就再也找不到（隐藏按钮自己就是那个入口的反例）。

**验收 / 证据**

- `flutter test test/domain/services/cognitive/study_rhythm_test.dart --concurrency=1` → `+17 All tests passed!`
- `flutter test test/features/thread/application/study_rhythm_reader_test.dart
  test/data/database/v15_migration_test.dart test/domain/services/cognitive/study_rhythm_test.dart --concurrency=1`
  → **`+25 All tests passed!`**
- `flutter test test/features/thread/presentation/thread_status_bar_test.dart --concurrency=1`
  → **`+4 All tests passed!`**（日志里有坐段就报数；没有坐段说"还没有足够记录"；
  点隐藏把开关落库且读数立刻消失、重进页面仍不显示；折叠后读数让位）
- codegen：`dart run build_runner build --delete-conflicting-outputs --force-jit`
  → `Built with build_runner/jit in 194s; wrote 467 outputs.`
- **本机教训（第二次撞到）**：codegen 必须 `--force-jit`——AOT 快照写不进含
  `一THREADRIPPER一` 的路径（`Unable to write file: …build.dart.aot`）。
- **l10n 教训**：`app_en.arb` 是 `l10n.yaml` 的 template，新键必须**先出现在 en**，
  否则生成物只缺 zh 的 getter（表现为一串 `undefined_getter`）。

---

## 2026-10-16 轮次四十六：日程冲突警告 + 一键顺延（任务侧）（Q23，teammate `question-intake`）

**做了什么**

- 新纯逻辑 `app/lib/domain/services/scheduling/schedule_conflict.dart`：
  `ScheduleConflict.at/freeMoment/freeMomentBefore/freeMomentAfter/rangeBefore/rangeAfter`，
  接上此前"只被自己的测试调用"的 `TimeWindowEngine.isBusyAt`（`time_window_engine.dart:202`）。
- 新弹窗 `app/lib/features/tasks/presentation/widgets/schedule_conflict_dialog.dart`
  （`ScheduleConflictChoice{before,after,keep}`），`task_detail_page.dart` 在改 `dueAt` 时接线
  （`_resolveDueAtConflict` :224、`_scheduleBlocks` :256、:364）。ARB zh/en 各 +6 键。
- 测试 17 条纯逻辑 + 6 条 UI（**先写、先红**：实现前 `Found 0 widgets with text "这段时间撞上了日程块"`）。

**为什么**

- 冲突判定用 `expand` 展开区间的真实边界，而**不用** `busyIntervals`——后者把区间裁到查询窗口，
  而"移到块前/后"需要的正是窗口之外的边界。半开 `[start,end)`；`available==true` 不算占用；
  ±1 分钟探测把 `ScheduleConflict.at` 与 `isBusyAt` 钉成逐点同真同假。
- 读库失败不挡用户；找不到空闲区就返回 null + 按钮禁用（不硬造时刻）；上限 64 跳。

**验收 / 证据（队友自报）**

- `flutter test test/domain/services/scheduling test/features/tasks --concurrency=1` → `+95 All tests passed!`
- 全量 `flutter test --concurrency=1` → `+1526 ~2: All tests passed!`（该次启动于轮次四十七改动之前）
- `dart format` 5 文件 `0 changed`；它 5 个文件 `dart analyze` 0 error / 0 warning。

**已知规格张力（Lead 裁决：按"哪一侧"拆，不算矛盾）**

- `docs/DESIGN_BLUEPRINT.md:85`（用户16）说一键调整**只挪 `expected_at`、不动 deadline`；
  `docs/FURNACE_SPEC.md:87` 说"仅弹窗警告"；`docs/GAP_ANALYSIS.md:54` 说"联动调整
  expected/deadline 并保证 estimate 可完整放入空闲区"。三处指向**不同侧**：
  本轮接的是**任务侧**（用户正在编辑的就是任务 `dueAt`，且由用户在弹窗里逐次选择，
  不是静默改写），事件侧的 `expected_at`（`app/lib/features/thread/presentation/event_properties_page.dart`）
  仍未接——这是本议题剩下的另一半，不是被推翻的决定。
- 顺带更正 `docs/PROGRESS.md` 里"Time 冲突弹窗与『只挪期望时刻』一键调整未接入 UI"这句：
  任务侧的弹窗与顺延**已接入**，事件侧仍未接。

---

## 2026-10-16 轮次四十五：节律层 α(τ) 的确定性核心接进 fast_engine（Q24，Lead）

**做了什么**

- 新文件 `app/lib/domain/services/cognitive/rhythm_gate.dart`：把 MindNet `mechanisms/rhythm.gate.js`
  的确定性核心移植成纯 Dart —— `G_duty`（占空比 `d`）与 `G_vig = exp(-t_on/τ_vig)`，
  外加 §5.3 的负荷自适应周期 `T_cycle = T0·(1 + λ_L·load/4)`（`referenceLoad = 4`，即 DAR 容量）。
  `RhythmGate` 自己持有 on-task 时钟（参考实现的 `store.onMinutes`），
  `beginRound(load:)`/`blockReasonFor(tick:)` 对应 `round.before` 与 `tick.gate`。
- `app/lib/domain/services/cognitive/fast_engine.dart`：新增 opt-in 机制
  `FastMechanisms.rhythm = 'rhythm.gate'`（**默认不装**，所以 43 条 tierA + B01 tierB 向量逐位不变），
  以及 `rhythm.gate.*` 七个参数（全部 `calibrated: false`）。`step()` 里 `round.before` 按
  「激活 ≥ 自身点火阈值的节点之和」算负荷、定周期，tick 循环逐个过门；`clone()` 复制节律时钟
  （反事实运行不该把警觉清零）。装的唯一条件就是 `mechanisms` 列表里有它。
- 测试 `app/test/domain/services/cognitive/rhythm_gate_test.dart`（15 例）：manifest 四条自检逐条移植，
  外加引擎侧五条——默认不装时 `availability` 恰好 1；装上后同一张图 `availability = 3/5` 且 B 的激活
  与不装时不同；`duty=1` 消融回到逐位相同；`duty=0` ⇒ `availability = 0`，
  `fast_engine.dart` 里原本**不可达**的「完全不在」分支真的被走到（`conscious` 为空）；
  `τ_vig` 调小后同一轮 `availability` 下降；克隆保住时钟。

**为什么**

- `docs/MINDNET_ROADMAP.md` §2-D 缺①：没有节律层，`fast_engine.dart` 的 `availability` 恒为 1，
  4.1 节那个 `e^(−k·α)` 的通道等于常开。这不是"少一个可选模块"，而是时间维度整个没进模型。
- **为什么默认关**：对拍向量是在没有这个门的情况下生成的（D3）。默认装上就会改写所有 tierB 读数，
  所以它必须是"可装的机制"，而不是"新的默认值"——`docs/MINDNET_ROADMAP.md` §3 第 8 行
  「至少一个机制可开关」的验收也正好落在这里。
- **为什么拒收 markov 与 theta**：markov 需要 `ctx.rng()`（mulberry32）做两态转移，
  与本 port 在 `T_ign > 0` 时抛错是同一条纪律；theta 只写在 §5.1 与 manifest 里，
  参考实现的 `openCountFor()` 实际只算 duty 与 markov（`mode === 'markov' ? cycle : round(duty*vig*cycle)`），
  把它当 duty 装进去就是"同名不同模型"。两种模式都在构造 `RhythmGate` 时抛 `UnsupportedError` 并写明理由。
- **α0 与 flow 带**：§5 的 `α(τ) = α0·G_duty·G_vig·G_flow` 里，参考实现的 hook 只乘了 duty 与 vig
  （`G_flow`、`α0` 没有出现在 `rhythm.gate.js` 里），所以这里也不发明它们：文档里写清"参考实现没接"，
  而不是补一个没人接的因子。

**验收 / 证据**

- `flutter test test/domain/services/cognitive/rhythm_gate_test.dart --concurrency=1` → `+15 All tests passed!`
- `dart analyze`（三个改动文件）→ `No issues found!`
- 回归（`flutter test test/domain/services/cognitive --concurrency=1`，含 `mindnet_fast_conformance_test.dart`
  的 43 条 tierA 向量与 `fast_diagnosis_conformance_test.dart` 的 B01 tierB）→ **`+211 All tests passed!`**：
  只要不把 `FastMechanisms.rhythm` 放进 `mechanisms`，`availability` 与向量仍逐位一致——
  这是"默认关"这次能成立的前提。（全量 `flutter test --concurrency=1` 本片跑过 `+1511 ~2`，但那次启动于本片改动之前，
  提交后另跑一次才算这条的正式证据。）
- 存档的一条**参考实现怪癖**（照抄不修）：`round.before` 用负荷定周期，而 `tick.gate`
  只用 `T0` 重算相位周期（`max(1, round(T0·1000/tick_ms))`），所以负荷大时长轮次里
  相位模式会自己重复；开口永远在周期开头。

---

## 2026-10-16 轮次四十四：`exposure`（读了没测）——mindnet 五类动作里最后一个接上（Q22，Lead）

**做了什么**
- 领域层**不需要**改：`CognitiveModel.modelStateAfterReview` 本来就带 `bool reread`，曝光直接复用
  （`rating: 3, reread: true` → `DsrEventType.reread`）；没有新增数学，tierA 的 A06 两条 reread 向量
  本来就在对拍里。
- schema v14 新表 `exposure_logs`（`app/lib/data/database/tables.dart` 的 `class ExposureLogs`：
  `id` / `card_state_id` / `source`（非空，唯一生产者 `kExposureSourceAnswerReveal = 'answer_reveal'`）/
  `exposed_at` / `created_at`）；`app/lib/data/database/database.dart`：`schemaVersion => 14`、
  `_upgradeV13ToV14()`、`_ensureColumns()` 里同款自愈。
- 写路径：`app/lib/data/repositories/anki_repository.dart` 新增 `addExposureLog(...)`；
  `app/lib/features/anki/application/review_service.dart` 新增
  `recordExposure({required ReviewItem item, DateTime? now, String source})`——只写模型两列
  （`updateModelState`）+ 一条曝光行，**不调 `updateUnitCardState`、不写 `review_logs`**。
- UI：`app/lib/features/anki/presentation/review_page.dart` 在"答案已揭示、等评分"那档
  （`_Feedback.awaitingSelfJudge`）加 `Icons.chrome_reader_mode`「读过，没测自己」，按下记曝光；
  SnackBar 明说"不算复习、到期日不变"（两个 ARB + 生成物）。
- 测试 4 处：`app/test/data/database/v14_migration_test.dart`（真实 v13 文件升级 + 自愈）、
  `app/test/domain/services/srs/dsr_card_state_test.dart`（同一行上 reread / retrieval_success / lapse 的
  S 与 R0 轨迹）、`app/test/features/anki/review_service_test.dart`、
  `app/test/features/anki/review_page_test.dart`（按下后 `exposure_logs` 有行、`review_logs` 空、
  `dueAt`/`repetitions`/`lastReviewedAt` 不变）。
- 文档：`docs/DATA_MODEL.md` 新增 §12（列清单 + 为什么单独一张表 + 模型路径 + 迁移/自愈 + 证据）；
  `docs/MINDNET_ROADMAP.md` §2-B"缺① exposure"与 §3 表第 2 行标 ✅（轮次四十四），§4 新增
  「切片 2 的另一半」整节。

**为什么**
- `docs/IO_PROTOCOL.md` §2.2 的五个动作（`time`/`review`/`exposure`/`knowledge`/`goal`）里，`exposure`
  是这个 app 唯一表达不出来的：读书、看答案在模型里是**独立事件类型** `reread`（S 增益 ×
  `kappa_reread_ratio` 0.1，`R0` 不动——只有 `retrieval_success` 才抬 R0），既不是"没发生"，
  也不能记成"一次成功回忆"。
- **为什么不塞进 `review_logs`**：那是*测试*记录——留存率分桶与 M6 标定曲线都从它算。曝光没有评分、
  没有对错，塞进去要给 NOT NULL 的 `rating` 编一个值，还会把"看了没测"算成一次成功回忆。
- 可核对到数字的验收口径：同一行上 `(sInc_reread − 1) / (sInc_success − 1) = 0.1`（实测
  `0.09999999026487426`，容差 1e-6——差的那点来自 `DsrReviewOutcome` 的 6 位四舍五入，不是模型偏差）。

**验收**
- `flutter test test/data/database/v14_migration_test.dart test/domain/services/srs/dsr_card_state_test.dart
  test/features/anki --concurrency=1` → **`+109 All tests passed!`**。
- `dart format`（9 个改动文件）→ 1 changed，再跑 0 changed；`dart analyze lib test` → `96 issues found.`
  （0 error / 0 warning；本片文件无新 finding，新增测试文件 0 条）。
- 一条自摆的坑：`DsrCardState.write` 把 stability 写回时**除以 24**（列的单位是*天*），而 `read` 乘回 24
  （`DsrState.s` 的单位是*小时*）。我第一版直接断言 `update.stability.value > before.s`，报
  `Expected: a value greater than <720.0> / Actual: <60.816243626859745>`。改成以存储列
  （`row.stability!`，单位天）为基准后通过——比较模型量之前先确认两边的单位。

---

## 2026-10-16 轮次四十三：目标题数下拉对任意合法值都不崩（Q20 带出的脆弱点，Lead）

**做了什么**
- `app/lib/features/questions/presentation/question_paper_page.dart`：新增顶层函数
  `targetCountOptionsFor(int current)`——`current < 1` 或已在预设档位里时返回 `paperTargetCountOptions`，
  否则返回「预设 + 当前值」并排序；下拉 items 改成 `for (final count in targetCountOptionsFor(spec.targetCount))`。
- `app/test/features/questions/presentation/question_paper_page_test.dart` +1 条 testWidgets
  （直接 `setTargetCount(3)` 后页面不抛异常、选中项显示 3、`initialValue == 3`；并断言
  `targetCountOptionsFor` 的 4 种取值），文件共 21 条。

**为什么**
- 这是 teammate 在 Q20 报告里点出的脆弱点，我复现确认：下拉 items 只有 `[5,10,15,20]`，
  而 `PaperSpecNotifier.setTargetCount` 收 **1..200**；值不在 items 里时 `DropdownButton`
  直接断言崩溃 `There should be exactly one item with [DropdownButton]'s value: 3`
  （`flutter/lib/src/material/dropdown.dart:1852`）→ 整页白屏。今天只有下拉能改题数，
  所以走不到；但"恢复上次 spec / 导入配置 / 深链"任何一条写进 1..4 就会崩。
- 宁可多列一档，也不让一个**合法的 spec 值**把页面打崩——这是个只有 3 行的硬化，
  比"记下来以后小心"可靠。
- **顺带纠正一条我自己的误判**：Q19 合并跑测试时那次单例失败（"缺口：文本末尾如实列出…"）
  我当时判成"编译期竞态"；真实原因是那时 teammate 的用例正调 `setTargetCount(1)`，
  撞的就是这个断言——不是竞态。

**验收**
- 修之前：`flutter test … --plain-name "目标题数不在预设档位里也不崩"` → `Failed assertion:
  line 1852 pos 10: 'items == null ||` + `There should be exactly one item with [DropdownButton]'s value: 3`。
- 修之后：同上命令 → 通过；`dart format --output=none --set-exit-if-changed`（2 个文件）→ 0 changed；
  `dart analyze lib test` → `94 issues found.`（0 error / 0 warning）；
  `flutter test test/features/questions --concurrency=1` → **`+105 All tests passed!`**（Q20 后 +104）。

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
- **Time 冲突弹窗与“只挪期望时刻”一键调整**：任务侧（改 `dueAt` 时弹窗警告 + 一键移到块前/后）
  已接入（轮次四十六）；**事件侧 `expected_at` 仍未接**（`event_properties_page.dart`）。
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
