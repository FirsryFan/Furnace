# 功能矩阵

> ⚠️ **本矩阵的 2026-09-07 版曾把已实现的算法标为「未实现」，与源码不符。**
> 实测基线（2026-09-08）：算法层代码早已存在，`flutter test` 105/105 全绿。本表状态列已按 **2026-09-08 实测** 更新；逐条经过说明见 [PROGRESS.md](PROGRESS.md) 同日轮次。
> 本轮设计依据：[DESIGN_BLUEPRINT.md](DESIGN_BLUEPRINT.md) v2（用户 13 条批注）。

> 对齐：Furnace 定稿（[FURNACE_SPEC.md](FURNACE_SPEC.md)，存档 2026-09-07）
> 状态与阶段来源：[GAP_ANALYSIS.md](GAP_ANALYSIS.md) §2 逐条差距矩阵（每行状态与该表一致，禁止夸大）；阶段定义见 GAP §6 与本仓库 [MILESTONES.md](MILESTONES.md) §2
> 术语：按定稿词表（事件/日程块/词条/节点/系/主题…）；代码内部模块名（tasks/timeboard/anki/mindmap）对照见 ARCHITECTURE.md（D2）
> 代码位置均相对 `app/lib/`，与 GAP 现状列核对过的实际文件

## 2026-10-02 实测状态修正（下表多处 R4/R5 行已过期，以本块为准）

> 下表是 R 阶段规划当时的快照，此后多轮已落地但表格未逐行维护。
> 与代码不符时，以 [PROGRESS.md](PROGRESS.md) 的轮次记录（尤其轮次十一、十二）与本块为准。

| 能力 | 2026-09-08 表 | 2026-10-02 实测 |
| --- | --- | --- |
| AI 助手（对话 / 工具调用 / 审批 / 台账） | 表内无此节 | ✅ 已实现（`features/ai/`，内置工具 10 个，见 [AI_DESIGN.md](AI_DESIGN.md)） |
| AI 对话正文渲染 markdown / LaTeX | 表内无此节 | ✅ 2026-10-02 新增（`gpt_markdown`；见 PROGRESS 轮次十三） |
| 用户自我描述 persona（进 AI 系统提示） | 表内无此节 | ✅ 2026-10-25 新增（轮次一百七十二）：schema v35 `local_settings.user_persona`（NULL=没写过，不回填）、设置页入口 + 认知模型页顶部卡片、AI 对话系统提示注入（日期之后规则之前；空 persona 提示逐字节不变）。解题/整理/组卷不读。见 [PERSONA_DESIGN.md](PERSONA_DESIGN.md) |
| 「AI 对话」更名为「智能化」 | 表内无此节 | ✅ 2026-10-25（轮次一百七十五，用户反馈第 1 条）：`aiTitle`「智能化」/ `navAi`「智能」（en: Intelligence / AI），persona 的编辑提示与清除确认文案同步改口径；代码内部仍叫 AI（`features/ai/`、`AiSettingsPage`），只有用户可见文案换了 |
| 应用图标（桌面/启动器） | 表内无此节 | ✅ 2026-10-25（轮次一百七十五，用户反馈第 2 条）：换成「炉膛 + 火焰」新图标（深绿底 + 琥珀拱门），Android 五档 mipmap + `mipmap-anydpi-v26` 自适应（含 monochrome）+ Windows `.ico`；不再用 Flutter 默认 logo。见 [APPEARANCE_DESIGN.md](APPEARANCE_DESIGN.md) §5 |
| 复习间隔可调（目标记忆保持率） | 表内无此节 | ✅ 2026-10-25（轮次一百七十五，用户反馈第 14 条）：schema v36 `local_settings.review_retention`（NULL=出厂 0.85，不回填）；复习计划页三挡「更长/标准/更短」对应 0.80/0.85/0.90，每次判分读一次注入 `FsrsParameters`；只影响之后排期，已有到期时间不变。见 [DATA_MODEL.md](DATA_MODEL.md) §25 |
| AI 处理标签树（create_tags 添加 / delete_content 删除） | 表内无此节 | ✅ 2026-10-02 新增：按父标签 id 或路径建标签（找不到就拒绝，不默默建到顶层），删除含整棵子树且逐条确认 |
| AI 删除标签 / 卡片 / 闪存卡 | 表内无此节 | ✅ 2026-10-02 新增（`features/ai/tools/deletion_tools.dart`）：破坏性工具，逐条确认 + 快照可撤销 |
| 术语：知识点 / 词条 | — | ✅ 2026-10-02 统一为用户可见词 **闪存卡**（`navAnki` 等；代码与数据库仍是 `knowledgePoint`，见 `app_en.arb` 的 `@navAnki` 说明） |
| AI 图片输入 → 自动生成背诵卡片 | 表内无此节 | ✅ 新增（`features/ai/domain/vision_payload.dart`、`features/ai/tools/knowledge_tools.dart`） |
| AI 只读联网抓取 `fetch_page` | 表内无此节 | ✅ 新增（`features/ai/tools/web_tools.dart` + `domain/services/web/`）；**不做 DNS 解析**，见 [AI_DESIGN.md](AI_DESIGN.md) D1 |
| `.fskill` 安装 / 启停 / 删除 / **脚本执行容器** | 表内无此节（[SKILL_FORMAT.md](SKILL_FORMAT.md) 原标注"容器未实现"） | ✅ 全部实现（`domain/skill/` + `data/skill/`：§3 容器 `skill_runner.dart`、工具包装 `skill_tool.dart`）；脚本仅 Windows 可执行，`browser_bridge` 未实现 |
| 跨页状态更新需要重启 | 表内无此节 | ✅ 已修复（2026-10-02 写库即刷新，[REACTIVITY_DESIGN.md](REACTIVITY_DESIGN.md)） |
| `.tfpkg` 导出/导入（全量逻辑转储） | 🔴 R4 | ✅ 已实现（`data/package/tfpkg_service.dart`、设置页「数据」小节） |
| 题目卷 → Word（.docx）导出 | 表内无此节 | ✅ 2026-10-18 新增（轮次一百二十二）：`domain/services/export/` 纯 Dart 拼 OOXML + `archive` 打包，卷末答案与解析、图片随文、行内公式转 Word 原生公式；组卷页「导出 Word」按钮；Word 16.0 真开 2 页 / 29 个公式。见 [DOCX_EXPORT_DESIGN.md](DOCX_EXPORT_DESIGN.md) |
| 题干 → 组卷网检索词与链接 | 表内无此节 | ✅ 2026-10-18 新增（轮次一百二十二）：`domain/services/zujuan/` 移植 zujuan-source-standards 的 URL 与检索词规则（纯逻辑、不联网、不新增依赖）；题目详情页「去组卷网搜这道题」入口，底部表复制检索词 / 搜索页链接。见 [ZUJUAN_LINKS_DESIGN.md](ZUJUAN_LINKS_DESIGN.md) |
| 主题 JSON（主/辅色、背景、动画） | 🔴 R4 | ✅ 已实现（`Themes` 表、`core/theme/theme_profile.dart`、主题编辑器；**图标槽位**为 2026-10-02 新增） |
| 日/周/月/时间线日历 | 🔴 R5 | ✅ 已实现（`features/timeboard/presentation/calendar_page.dart`，`CalendarView{day,week,month,timeline}`） |
| Time 日/周网格行高自由拖拽 + 挡位吸附 | 表内无此节 | ✅ 2026-10-25（轮次一百七十五，用户反馈第 6 条）：拖行分界线连续缩放每小时像素（12–400），松手吸附 8 挡并落库（v36 `time_view_settings.hour_height`，NULL=旧公式）；`minutesPerRow` 15/30/60 仍决定标签粒度，与像素行高解耦；菜单补「恢复默认」。见 [DESIGN_BLUEPRINT.md](DESIGN_BLUEPRINT.md) §3.1 |
| 页面缩放 80%–150% | 🔴 R4 | ✅ 2026-10-25 已实现**整体缩放**（`app/lib/app/page_zoom.dart`）：布局按 窗口/scale 放大后再缩放绘制，文字/控件/间距/图片一起变；主题编辑器滑杆 0.8–1.5。旧行写「检索均无命中」是审计遗漏——当时由 `MediaQuery.textScaler` 承担，只缩放文字。见 PROGRESS 轮次一百七十一 |
| Android 适配 / 正式包联网 | 🔴 v0.3 / — | ✅ 已重构建（2026-10-02）；并修掉"release 清单缺 `INTERNET`、AI 在 Android 正式包上完全连不上网" |
| 知识网络图：分簇布局 + 缩放平移 | 表内无此节 | ✅ 2026-10-25（轮次一百七十六，用户反馈第 7 条）：布局 v2 按标签分簇（扇区角度按成员数加权、簇内黄金角螺旋 `r=26*sqrt(k)`、最小间距 26、无标签放中心、确定性），画布边长 `clamp(840*sqrt(n/15), 840, 2400)`；页面换 `InteractiveViewer`（0.4×–4×、首帧自适应缩放居中、AppBar 重置视图、缩放 <0.8 隐藏文字）。期 3 已补（轮次一百七十九：搜索 / 标签筛选 / 详情 sheet / 列表兜底）。见 [REVIEW_FEEDBACK.md](REVIEW_FEEDBACK.md) §7 |
| 组卷网检索词长度按学科带 | 表内无此节 | ✅ 2026-10-25（轮次一百七十六，用户反馈第 9 条）：`ZujuanSubjectBand{science,humanities}`，理科候选 15–30 字、文科 20–40 字且严格短于题干（短题干回退尽量长、≥4 字），去掉旧 5–16 字偏好；详情页检索词面板每条显示「N 字」+ 长度口径提示。标准侧 `keywords.mjs`/`SKILL.md` 已在轮次一百七十九同步成同一口径（CLI 加 `--band`） |
| 标签用途边界（tag usage） | 表内无此节 | ✅ 2026-10-25（轮次一百七十六，用户反馈第 10/11 条）：schema v37 `tags.usage_codes`（逗号分隔 time/question/knowledge/task/flashcard，NULL=不声明、按 parentId 向上继承、整链无声明=不限制）；标签树页每行「用途边界」多选对话框 + 已声明徽标；时间块标签选择器只列 usage 含 `time` 的标签并给三种空态提示。轮次一百七十九再把题库批量打标签 / 任务详情 / 认知测评三域接上 `tag_usage_scope`；其余选择器仍读全树 |
| Time 安排列表「全部 / 今天」过滤 | 表内无此节 | ✅ 2026-10-25（轮次一百七十六，用户反馈第 12B 条）：`TimeBoardPage` 顶部 ChoiceChip（blocks 非空才显示），「今天」= 本地时区当天半开区间与块区间有交集（跨午夜算今天、恰 00:00 结束不算），日程卡同步过滤，今天无块给专门空态 |
| 能力测评（四项本地小测 + 能力画像） | 表内无此节 | ✅ 2026-10-26（轮次一百七十七，用户反馈第 8 条）：与知识点测评**分开**的能力画像——schema v38 `ability_scores`（只追加，不参与先验/FSRS 排期），领域纯函数把四项（反应速度/工作记忆/模式识别/注意稳定性）换算成 0–100，测评页可重测单项、返回即放弃，画像页显示最近一次分数/次数/时间（没测过显示「还没测过」），设置页两个入口。趋势纯逻辑已做（`ability_trend.dart`，轮次一百七十九）；趋势图 UI、`metrics` 展示、保存事务化、与 MindNet 映射未做。见 [ASSESSMENT_DESIGN.md](ASSESSMENT_DESIGN.md) §9 |
| 设计 token（间距/圆角/语义文字） | 表内无此节 | ✅ 2026-10-26（轮次一百七十八，用户反馈第 3 条，**基础层**）：`app/lib/core/theme/design_tokens.dart` 新增 `AppSpacing`（4pt 栅格 2/4/8/12/16/24/32/48 + `snap`）、`AppRadius`（control=6/card=10/sheet=14/pill=999）、`AppTokens extends ThemeExtension`（间距 8 字段 + 三半径 + pageTitle 20/sectionTitle 16/body 14/caption 12）；`theme_profile.dart` 的 `toThemeData()` 把 token 装进 `ThemeData.extensions`，`cardTheme`/`dialogTheme` 圆角改用 token（原来 Material 默认 12/28 与各页手写 2–18 混用）。**页面级迁移未做**（125 种 EdgeInsets / 11 种圆角），等你定「自然」方向。见 REVIEW_FEEDBACK §3 |
| AI 思考过程落库（历史可折叠查看） | 表内无此节 | ✅ 2026-10-26（轮次一百七十八，用户反馈第 4a 条补完）：schema v39 `ai_messages.reasoning`（可空、不回填）；`SseAssembler` 解析 `reasoning_content`/`reasoning`/thinking parts 已在 v0.6.11 起显示，本版把文本落库——`AgentLoop` 六条写库路径（部分输出/回答/TurnGroup/_commitTurn/取消/无）都带 reasoning，`_reasoningOrNull` 统一「没思考=NULL」；历史消息折叠块读 `row.reasoning`。上下文回传不带 reasoning，默认模型仍 `deepseek-chat` |
| 知识网络图期 3（搜索 / 标签筛选 / 详情 / 列表） | 表内无此节 | ✅ 2026-10-26（轮次一百七十九，用户反馈第 7 条补完）：搜索知识点标题或任一标签标题（大小写不敏感、显示匹配数、可清除、无命中空态）、详情 sheet（认知区域 / 关联卡数 / 平均 R / 标签 chip 一键转筛选）、列表视图按主标签分组（未挂标签最后、点行回图谱并居中选中）。新增纯函数 `cognitiveGraphPrimaryTagId` / `filterCognitiveGraphPoints` / `groupCognitiveGraphPointsByPrimaryTag`。搜索与筛选是内存态（关页即清）。见 [REVIEW_FEEDBACK.md](REVIEW_FEEDBACK.md) §7 |
| 组卷网检索词长度（标准侧同步） | 表内无此节 | ✅ 2026-10-26（轮次一百七十九，用户反馈第 9 条补完）：`D:/dsh-data/skills/zujuan-source-standards/scripts/keywords.mjs` 与 `SKILL.md` §6.2 改同理科 15–30 / 文科 20–40 且严格短于题干，CLI 加 `--band humanities`；文科分段保留全角逗号（候选可能含逗号，站点容错未实测）。App 侧 `zujuan_keywords.dart` 文件头改为「已同步」。真实站点命中率人工 A/B 未做 |
| 标签用途域：三个选择器接入 | 表内无此节 | ✅ 2026-10-26（轮次一百七十九，用户反馈第 10/11 条补完）：`app/lib/features/tags/application/tag_usage_scope.dart` 统一「按用途过滤 + 提示 + 两种空态」；题库批量打标签对话框、任务详情「加标签」、认知测评选择范围（`TagUsage.knowledge`）三处改用 `TagUsageScope`；l10n 加 `tagUsageScopeHintNamed` / `tagUsageScopeEmptyNamed`。AI 建议标签 / 组卷选标签 / 知识网络入口 / 题库包路径选择器仍读全树 |
| 能力趋势（纯逻辑） | 表内无此节 | ✅ 2026-10-26（轮次一百七十九，用户反馈第 8 条后续）：`app/lib/domain/services/cognitive/ability_trend.dart` 把「最近 N 次能力测量」整理成旧→新序列（按 `capturedAt` 稳定排序、最多 30 点）、`delta`/平均/最好/最差、方向（阈值 2.0 分判变好/持平/变差）、0–1 归一化坐标；29 例测试。画像页趋势图 UI 未接。见 [ASSESSMENT_DESIGN.md](ASSESSMENT_DESIGN.md) §9 |
| 能力画像趋势折线（UI） | 表内无此节 | ✅ 2026-10-26（轮次一百八十，用户反馈第 8 条后续）：`abilityTrendProvider` 读最近 30 次，画像页每张能力卡在分数/次数下画 `CustomPaint` 迷你折线（高 36、宽撑满、线宽 2 primary、每点 2px 圆点，y = 1 − 归一化分数）；不足 2 点显示「至少测两次」，≥2 点显示「最近 N 次」+ 方向词（变好/持平/变差，阈值 2 分，色 primary/onSurfaceVariant/error），读库失败只坏那张卡。`ability_profile_page_test.dart` 6→12 例。未做：坐标轴/时间标签、真机视觉验证。见 [ASSESSMENT_DESIGN.md](ASSESSMENT_DESIGN.md) §9 |
| 标签用途域：题库包标签路径 + 手写整理提示词 | 表内无此节 | ✅ 2026-10-26（轮次一百八十，用户反馈第 10/11 条补完）：设置页「题库包导出 → 标签路径」用 `questionPackTagPathScopeProvider` 按 `TagUsage.question` 过滤（纯函数签名不动；对话框给范围提示、用途边界空态、整树无声明时全列）；手写整理的 `existingTagPaths` 与 `previewFor` 已有标签集合也只认「纳入题库」标签。picker 10→13 例、手写服务 +2 例。已知取舍：`applyAll` 写库仍走全量 `getTagByPath`。 |
| AI 工具 focus_review（考前把卡片提前进复习） | 表内无此节 | ✅ 2026-10-26（轮次一百八十一，用户 m19724）：`app/lib/features/ai/tools/review_focus_tool.dart` + `app/lib/domain/services/srs/review_focus.dart`；参数 `days`(0–90 默认 7)/`limit`(1–2000 默认 500)/`tag`/`dry_run`(默认 true)；只拉「未来 N 天内到期、非新卡、未到期」的卡，按原 due 近→远、超 limit 截断，改 `due_at` 不动 repetitions；`beforeJson` 空计划为 null（空快照不让撤销变成假操作），undo 逐张还原；riskFor=write、reversibleFor=true；系统提示规则 4 已加一句触发口径；16 例纯逻辑 + 12 例工具测试 |
| 使用指南文档 | 表内无此节 | ✅ 2026-10-26（轮次一百八十一）：新建 `docs/USER_GUIDE.md`（三个常用入口 / AI 能做不能做 / 高频指令模板 / 学习闭环六步 / 考前 focus_review / 任务与题目推送同机制现状 / persona / 数据安全 / FAQ） |
| 采集管线 M1：题目区整段 Markdown + LaTeX（`.tqb` `text_format`） | 表内无此节 | ✅ 2026-10-27（轮次一百八十二，handoff SPEC §7 M1）：新 `features/questions/presentation/question_markdown_view.dart` 的 `MarkdownQuestionText`（`questionTextFormatIsMarkdown` 判格式、结构不完整退回 `SelectableText`），题干/选项/答案/解析/理由在详情页统一接线；`.tqb` 可选 `text_format`（plain 缺省 / markdown）→ `QuestionPackRecord.textFormat` → schema v40 `questions.textFormat`（NULL=plain）；导出侧回写。旧包与 plain 题行为不变 |
| 采集管线 M1：`fullcard_` 前缀优先判整卡快照 | 表内无此节 | ✅ 2026-10-27（轮次一百八十二，handoff SPEC §4.6/§7 M1）：`question_stem_image_plan.dart` 的 `planQuestionStemRender(..., hasFullcardImage:)` 新增 B0 分支——媒体文件名（小写）以 `fullcard_` 开头直接 snapshot，不再依赖尺寸；详情页按 `images.any(fileName.startsWith('fullcard_'))` 传入 |
| 采集管线 M2：扩展题 `extension_of` + 能力 `capability` | 表内无此节 | 🟡 2026-10-27（轮次一百八十二，handoff SPEC §7 M2）：**已完成** `.tqb` 可选字段 → `QuestionPackRecord` → schema v40 `questions.extensionOf`/`capability`（JSON 数组串）→ 导入/更新/导出双向映射；纯逻辑 `question_extension.dart`（母子索引、防自指/互指/悬空）、`question_capability.dart`（A1–A10 词表）、`capability_stats.dart`（T×A 统计口径）、`review_deck_key.dart`（卡组键）；详情页能力点 chips + 扩展题/母题入口。**未做**：材料容器（`materials/<subject>/*.md` + `assets/`）、材料练习记录（用时/错因/岔路/重做历史）、capability 手工录入与 T×A 报表页 |
| 采集管线 M4：`.tqb` 契约工具 | 表内无此节 | ✅ 2026-10-27（轮次一百八十二，handoff SPEC §7 M4）：`app/tool/tqb_verify.dart`（用 App 自己的解码器验证包）+ 交接侧 `tools/zip_check.py`；真实包实测通过（30 题 / 60 媒体，`decoded records=30`、`OK`）。本仓库无 CI，列为发布前手动门禁，命令见 [HANDOFF_PIPELINE.md](HANDOFF_PIPELINE.md) |
| 采集管线交接实现映射文档 | 表内无此节 | ✅ 2026-10-27（轮次一百八十二）：新建 [HANDOFF_PIPELINE.md](HANDOFF_PIPELINE.md)——M1–M4 状态、字段/文件/函数位置、未做项、契约验证命令；规范原文在 `E:/FirsryOS/THREADRIPPER/handoff/2026-10-26-furnace-pipeline/`（已回写 SPEC v1.2） |
| 闪存卡卡组主界面与分组复习 | 表内无此节 | ✅ 2026-10-27（轮次一百八十四，用户 m20816）：卡组 = 已配的标签组（沿用 `ReviewGroupPlans` 每日上限），复习 Tab 第一屏改成 `DeckListPage`——「全部」+ 每卡组一行（新卡/复习 done/target、进度条、达成徽标）+「未分组」行（真有这类卡才出现）+ 空态新建；点行进 `ReviewPage(scopeTagId:)` 只复习这一组（`ReviewService.buildQueue(onlyPaths:/onlyUngrouped:)`，空的卡组 = 空队列，不回退全库）；进度数字只来自 `deck_progress.dart`（14 例纯逻辑），卡组页与计划页同源 |
| AI 收题 `create_questions`（拍照/粘贴进题库，替代手动收题页） | 表内无此节 | ✅ 2026-10-27（轮次一百八十四，用户 m20816）：新 `app/lib/features/ai/tools/question_write_tools.dart`——内置 agent 直接把用户拍的题/粘贴的题誊写进题库（一次 ≤100、题号或题干指纹重复时返回已有题、撤销只删本次新建的 `created_ids`）；工具总数 28→29；题库页删掉「收题」「拍照整理」两个手动入口（保留组卷、材料入库），空态与文档口径改成「拍照或粘贴发给「智能」」；25+2 例工具/撤销测试、2 例页面集成测试 |
| 单消息工具调用上限 8→30（可设到 60） | 表内无此节 | ✅ 2026-10-27（轮次一百八十四，用户 m20816「增大内置 agent 单消息工具调用次数上限」）：`AiConfig.defaultMaxRounds` 8→30、`maxMaxRounds` 20→60、`minMaxRounds` 1；设置页滑块跟随常量、提示文案中英同步；3 个既有测试改期望。上限仍是硬上限，到顶后本轮结束并提示 |
| AI 运行时间线（每一步正在运行可见） | 表内无此节 | ✅ 2026-10-27（轮次一百八十四，用户 m20924）：`AgentTurnState.steps`（`AgentStepKind{model,tool}` + `AgentStep`）记录每轮模型调用与每次工具调用的开始/结束（运行中/等待批准/成功/失败/取消、耗时）；新 `run_timeline.dart` 运行中展开、每秒刷新耗时、结束折叠「本轮 N 步」、点开可回看；接在思考面板与流式回答之间。9 例组件 + 9 例循环 + 2 例页面集成测试。步骤不落库（重开对话不留时间线） |
| 用户评测板块 v1.0（能力评测与认知档案） | 表内无此节（v38 的四项 MVP 见 §9，已被本板块取代入口） | ✅ 2026-10-29（轮次一百八十五，用户 m21578 设计文档 v1.0）：schema v41 八张 `cog_*` 表（tasks/sessions/trials/metrics/ability_estimates/cognitive_params/两张 mapping，`cog_` 前缀避开 v10 旧 `assessment_sessions`/`assessment_responses`）；`features/assessment/` 分四层——`domain/`（19 统计指标、加权中位数合并、`deriveParams`、`.cogprofile` 组装）、`application/`（十任务注册 + 可播种刺激生成 + 会话引擎 + 会话服务 + providers）、`presentation/`（评测中心/全屏任务/本次结果/能力档案四页，档案可覆盖/清除覆盖）；默认 uncertainty 0.7（decision_fatigue 0.9、cross_language_cost 0.8）、多次测量合并最低 0.15、质量标记只上调 uncertainty 不删数据、`user_override` 停止自动更新；设置页两旧入口换单入口「评测与认知档案」。**未做**：P2 Thread 权重建议接口（`getParamsForThread()`）、P3 `.cogprofile` 导出接界面、决策疲劳与副本 III 默认关闭、stale 自动扫描 |

---

## 2026-09-08 实测状态修正（覆盖下表的 R3 行）

| 能力 | 2026-09-07 表 | 2026-09-08 实测 |
| --- | --- | --- |
| `ThreadRanker` 加权排序 + 硬约束 | 🔴 R3 | ✅ 已实现（`domain/services/scheduling/thread_ranker.dart`，21 项测试） |
| `TimeWindowEngine` 重复展开/占用/空闲窗口 | 🟡 | ✅ 已实现（含 8 项测试） |
| FSRS 间隔重复（定稿 D9） | 🔴 R3 | ✅ 已实现（`domain/services/srs/fsrs_scheduler.dart`，FSRS-6，9 项测试） |
| 自由挖空 + 错题强制绑定状态机 | 🔴 R3 | ✅ 已实现并接入复习 UI（轮次四十九：`domain/services/cloze/cloze_engine.dart` 算法 + `cloze_layout.dart` 就地呈现 + `review_page.dart` 会话内强制闭环；纯逻辑 `forced_loop.dart` 12 例 + `cloze_layout.dart` 6 例 + 页面 3 例；**轮次一百二十一改节奏**：答错重插到「当前之后隔 `relearnGapCards`(=3) 张、不早于 2 张」的位置，队列末尾不足才接队尾下一轮马上重现；刚答错那一次不套 10 分钟门，10 分钟门只在「答对一次但仍绑定」的第二次重现生效） |
| Mindnet 图谱扩散提权 | 🔴 R3 | ✅ 算法已实现（`domain/services/cloze/diffusion_boost.dart`）；**独立复盘界面仍未做** |
| `CompletionLogs` 完成历史 | 🔴 R3 | ✅ 已实现（含 v3 实际用时字段） |
| 树形 Tag（parent_id + path） | 🔴 R3 | ✅ 已实现 |
| **Thread 排序 UI（顶栏 + 排序 + 属性页）** | —（新） | ✅ 2026-09-08 新增（`features/thread/`，用户批注 1–13 落地） |

状态图例：

- ✅ 已实现（＝GAP「🟢 已满足」，源码层面/实机可用）
- 🟡 部分（注明缺口与目标阶段；＝GAP「🟡 部分满足」）
- 🔴 未实现（规划中，标注目标阶段 R\* 与预计位置；＝GAP「🔴 缺失」）

---

## 核心模块

### Mindnet（思维导图）——对应 GAP 2.4

| 需求 | 状态 | 实现位置 / 缺口 |
| --- | --- | --- |
| 导图新建/切换；节点增删改、父子关系、折叠/展开（1.4.1） | ✅ | `features/mindmap/presentation/mind_map_page.dart` |
| 节点同级上移/下移、备注编辑/显示/清除（1.4.1） | ✅ | 同上 |
| 节点拖拽移动（跨父级 re-parent）（1.4.1 后置项） | 🔴 R6 | 树形操作已具备，拖拽留 R6 打磨（mindmap 模块） |
| 导入/导出 OPML、FreeMind（.mm）（1.4.2） | 🔴 R5 | 现仅 `.kpak` 内含导图；R5 实现 xml 编解码＋UI 入口（`features/mindmap/…`） |
| 节点转标签（单节点） | ✅ | `mind_map_page.dart`（现状为单节点、无子树批量） |
| 节点选为「系」→ 整棵子树导入 Thread 树形标签（1.4.3，D3） | 🔴 R5 | 规划中 · mindmap＋tags 模块；标签树形数据层先行（R3） |
| 节点设为「当前目标」（1.4.3） | 🔴 R5 | 规划中 · 写 `ThreadStates.goal_node_id`（表在 R2/R3）＋Thread 顶栏联动 |

> 模块联动（定稿 §2）：Mindnet→Thread 见上两行；Knowledge→Thread 见 Knowledge 节「生成任务」行。

### Thread（任务事件流）——对应 GAP 2.1

| 需求 | 状态 | 实现位置 / 缺口 |
| --- | --- | --- |
| 事件固定字段与 CRUD：id/title/期望用时/截止（1.1.1） | 🟡 缺口：缺 `expected_at`（期望时刻）与 `energy_required`（精力要求 1–10，null=忽略），缺省即算法忽略语义待写入引擎 → R3 | 现为 Task(id,title,estimate_minutes,due_at)：`data/database/tables.dart`、`domain/entities/task.dart`；CRUD/编辑 UI：`features/tasks/presentation/tasks_page.dart`、`task_detail_page.dart` |
| 标签＝完整树形路径（parent_id＋path 缓存），UI 默认末级＋悬停/点击展开（1.1.1 tags，D3） | 🔴 R3/R5 | 现为扁平 Tag＋ObjectTags 关联（`features/tags/presentation/tags_page.dart`、`data/repositories/tag_repository.dart`）；R3 建树数据、R5 折叠展示组件 |
| 标签：手动创建/删除、关联事件/词条/日程块（1.1.2 前半） | ✅ | `tags_page.dart`＋`TagRepository`＋各详情页（任务/词条/时间块弹窗均支持增删标签） |
| Mindnet「系」导入标签（1.1.2 后半） | 🔴 R5 | 见 Mindnet 节「系导入」行（保留完整层级路径） |
| 顶栏：左＝当前目标＋精力水平、右＝「更新与排序」唯一重排入口（1.1.3；交互 §6 / GAP 2.8） | 🔴 R5 | 规划中 · `features/tasks/…`（顶栏常驻）；现状无自动轮询，符合「仅手动触发」精神 |
| 状态输入持久化：`ThreadStates`（energy 1–10、goal_text、goal_node_id、updated_at）（1.1.3） | 🔴 R3 | 新表（GAP §3）；顶栏 UI 在 R5 |
| 加权综合排序 ThreadRanker：0.4/0.3/0.2/−0.1，每事件分解得分可解释（1.1.3） | 🔴 R3 | 新纯 Dart 实现（常量表 GAP §4.1）；现 TaskScheduler 规则型引擎保留为显式建议（下下行） |
| 硬性约束：实际可用＝(deadline−now)−区间忙碌块总时长（忙碌块按 D6 语义计占用）；超时标红置底、提示「需 X 分钟，可用 Y 分钟」（1.1.3；GAP 2.8 红标签） | 🔴 R3/R5 | 计算引擎 R3（依赖 Time 供数接口）；红标 UI R5（tasks 列表/卡片） |
| 任务模板：名称＋时长＋标签＋精力，创建时套用（1.1.4） | 🔴 R3/R5 | `TaskTemplates` 表 R3；套用 UI R5 |
| 按标签筛选后批量修改数值字段（1.1.4） | 🔴 R5 | 规划中 · service＋UI（tasks 模块） |
| 完成任务写完成记录 `CompletionLogs`（标签快照＋时刻，供疲劳惩罚/Knowledge 上下文）（D7，联动 Thread→History） | 🔴 R3 | 新表（GAP §3）；挂在任务完成动作上 |
| 子任务、依赖、提醒（本地通知）（保留项，GAP 2.1 末行 🟢） | ✅ | `task_detail_page.dart`＋`core/notifications/notification_service.dart` |
| 调度建议清单＋一键采纳（D8：保留为创建时/显式辅助建议，不触碰列表顺序） | ✅ | `features/tasks/application/task_scheduler_service.dart`、`tasks_page.dart`；引擎 `domain/services/scheduling/task_scheduler.dart` |

> 交互细节（定稿 §6 / GAP 2.8：顶栏、>2h 过期确认弹窗、「时间不足」红标签）均已并入上表 1.1.3 对应行，不重复列。

### Time（时间/日程）——对应 GAP 2.2

| 需求 | 状态 | 实现位置 / 缺口 |
| --- | --- | --- |
| 日程块 CRUD：标题/开始/结束/重复规则字段、标签挂载（1.2.1） | ✅ | `features/timeboard/presentation/time_board_page.dart`（创建/编辑弹窗、可用状态切换、标签经 ObjectTags） |
| 日程块重复规则展开（none/daily/weekly+dow…）（1.2.1） | 🔴 R3/R5 | `repeatRule` 列已在 `data/database/tables.dart`；解析/区间展开引擎 R3、UI 呈现 R5 |
| 忙碌/开放语义与软性匹配推荐（D6：available=false＝忙碌硬块，计 Thread 硬约束占用、参与冲突检测、不可被建议采纳；available=true＝开放软块，供软性匹配与建议采纳，不计占用） | 🟡 缺口：语义并入 D6、软块推荐保留 → R3（O2 已结案 2026-09-07：available=true 本就是任务可排入的开放块，与 D6 同向，存量不翻转） | 引擎现按「适合类型」匹配（TaskScheduler 调度链路）；D6 解释已记入 ARCHITECTURE 4.1 |
| 事件落在日程块内的冲突弹窗警告＋「移至该日程块之前/之后」一键调整（1.2.3） | 🟡 R5 | 两侧都已接：`domain/services/scheduling/schedule_conflict.dart`（半开区间、±1 分钟探测沿用 `TimeWindowEngine` 口径）＋`features/tasks/presentation/widgets/schedule_conflict_dialog.dart`（同一个弹窗两侧共用）——任务侧 `task_detail_page.dart` 改**截止时刻**时警告（轮次四十六），事件侧 `features/thread/presentation/event_properties_page.dart` 改**期望时刻**时警告并「移到这块之前/之后」（轮次四十八，蓝图 2.4 / 用户 16：冲突时只挪期望位、不动 deadline）；缺口：期望用时可放进空闲区的联动未做 |
| 向 Thread 确定性供数：当前时刻 / [t1,t2] 忙碌占用总时长 / 下一空闲窗口（1.2.3；联动 Time→Thread） | 🟡 缺口：现仅部分查询，需接口化 → R3 | `data/repositories/time_block_repository.dart`（消费方：ThreadRanker，R3） |
| 今日安排汇总（含时间块已关联任务显示）（v0.1 保留能力） | ✅ | `time_board_page.dart` |

> 日历视图（日/周/月）见「平台与体验」节对应行（定稿 1.2.2 / GAP 2.2）。

### Knowledge（记忆/复习）——对应 GAP 2.3（代码 anki 模块）

| 需求 | 状态 | 实现位置 / 缺口 |
| --- | --- | --- |
| 词条 CRUD、来源字段；卡模板管理（1.3.1 基础） | ✅ | `features/anki/presentation/anki_manage_page.dart` |
| 词条正文 Markdown/富文本＋content_format＋内置编辑器（1.3.1，D5） | 🟡 缺口：content 现为纯文本（`domain/entities/knowledge_point.dart`）；升级 R3，编辑器取舍按 O1 | 管理页编辑器（现纯文本编辑） |
| 结构化挖空位记录＋复习日志（1.3.1） | 🟡 缺口：挖空为模板 `clozeTemplate`「___」手写、无槽位记录；ReviewLogs 缺 FSRS 字段 → R3 | `domain/entities/card_template.dart`、ReviewLogs（`data/database/tables.dart`） |
| 词条级 Markdown/JSON 导入导出（1.3.1） | 🔴 R5 | 现仅 `.kpak` 整体包；词条级编解码 R5（`features/packages/…` codec 扩展） |
| 自由挖空运行时机制：概率决定创造新空位、历史未出现、无空位打标记转历史抽取（1.3.2） | 🟡 缺口：现为一次性自动挖空（管理页一键/导入时生成 fill_blank）→ 改造 R3 | `domain/services/cloze/cloze_generator.dart`（首批槽位推导沿用其逻辑增强，GAP §7 兼容） |
| 五种题目形式：单选/填空/简答已有，补多选、有序多选与严格/非严格双模式（1.3.2） | 🟡 | 现有复习流 `features/anki/presentation/review_page.dart`（v0.1 的 `anki_page.dart` 已在轮次六十七删除：无入口）；题型扩展核心 R3、UI R5（判分规则见 O5） |
| 错题强制绑定：答错后空 2–3 张再重现→约 10 分钟短间隔再出现→连续两次正确解除（1.3.2，D11；节奏口径轮次一百二十一修订） | 🔴 R3/R5 | ✅ 已实现并接入复习流（`domain/services/cloze/forced_loop.dart` 决定会话内重插位置与解除条件、`review_page.dart` 就地挖空 + 未到下限时的等待态；重插间隔沿用 `ReviewService.relearnGapCards = 3`，`kMinForcedRedoGapCards = 2` 兜底下限；10 分钟下限取自 `ForcedStep.nextDueAt`，只套「答对一次但仍绑定」的第二次重现；**轮次一百六十九加会话上限**：同一绑定一轮最多插回 2 次（`ForcedLoop.mayReinsert` / `kMaxForcedReinsertsPerSession`），超限不插回本轮但库里 `forced = 1` 不动；复习页另有跳过本张与等待态「结束本轮」；测试 `test/domain/services/cloze` +49） |
| FSRS 间隔重复：完全本地、按历史复习动态调整（1.3.3，D9） | 🔴 R3 | ✅ 已接入 v2 复习流（`domain/services/srs/fsrs_scheduler.dart` + `features/anki/application/review_service.dart` 的 `grade()`/`updateUnitCardState`，评分 忘记/模糊/记得 → Again/Hard/Good；**遗留已在轮次六十七清掉**：旧入口 `features/anki/application/anki_service.dart:23`（被 `anki_page.dart:273` 调用）连同 `ankiServiceProvider` 一起删除，`sm2_scheduler.dart` 按 D9 留成存档，`app/test/domain/services/srs/single_scheduler_authority_test.dart` 钉住"不再被调用"） |
| Mindnet 图谱扩散提权：答错词条取关联节点，距离 1 ×1.8 / 距离 2 ×1.3，3 次抽卡周期衰减（1.3.4，D12） | 🔴 R3 | `BoostEntries` 表（GAP §3）；提权并入抽卡/挖空队列权重 |
| 复习队列与三种评分 UI（v0.1 能力，评分映射 FSRS 于 R3） | ✅ | `features/anki/presentation/review_page.dart`＋`features/anki/application/review_service.dart`（v0.1 的 `anki_page.dart`＋`anki_service.dart` 已在轮次六十七删除：入口早已换人）；**轮次一百六十九改展示节奏**：新卡按每 5 张复习卡插 1 张（`features/anki/application/review_pacing.dart`，`ReviewService.buildQueue` 接线）、底栏可跳过本张（不写日志、不动排期）、等待态可结束本轮 |
| 复习统计 / 7 天柱状图（GAP §7 保留，统计口径适配 FSRS） | ✅ | `features/anki/application/anki_stats_service.dart`＋`anki_manage_page.dart` |
| 联动：复习中「生成任务」按钮 → 建 Thread 事件（标题＝词条标题，带上下文/同标签）（GAP 2.3 末行 / 2.5 Knowledge→Thread） | 🔴 R5 | 规划中 · anki 复习结果页 → `features/tasks/…` 创建入口 |

---

## 分享与隐私

> 双轨：`.kpak`（班级分享子集）保留 ✅；`.tfpkg`（定稿全量工作区打包）新增 🔴 R4（D4）。

| 需求 | 状态 | 实现位置 / 缺口 |
| --- | --- | --- |
| `.kpak` 导出：班级分享子集（词条/模板/标签/导图），不含个人任务/进度（D4） | ✅ | `features/packages/application/package_export_service.dart`＋`KnowledgePackageCodec`（`data/package/…`） |
| `.kpak` 导入：预览/去重/升级/保留复习进度；导入自动挖空 | ✅ | `package_import_service.dart`＋`features/packages/presentation/packages_page.dart` |
| 知识库（`.kpak`）入口降级为次级入口（D4） | 🔴 R5 | 现仍为导航一级页；随 R5 导航/词表调整落实 |
| `.tfpkg` 导出/导入：全量逻辑转储（JSON manifest＋附件＋主题）→ zip，合并策略提供覆盖/追加；覆盖前自动备份当前库（定稿 §3，D4） | 🔴 R4 | 规划中 · package 模块 codec 扩展（格式要点见 GAP §5） |
| `.tfpkg` 加密：可选密码 AES-GCM（GAP 2.6 加密/压缩行） | 🟡 缺口：zip（archive）编解码已有（`.kpak` 在用），加密未实现 → R4 | 依赖可用性 O1：pub.dev 不可用则先留接口＋文档 |
| 本地数据默认不联网（本地优先） | ✅ | 架构设计＋`docs/PRIVACY.md` |

---

## 平台与体验

| 需求 | 状态 | 实现位置 / 缺口 |
| --- | --- | --- |
| Windows 10/11 优先 | ✅ | Flutter 项目（`app/windows`）＋`scripts/build_windows.ps1`（R6 DoD 冒烟） |
| Android 8+ 适配 | 🔴 v0.3 | 同一套 Flutter 代码，见 MILESTONES §4 发布节奏（不在 R 阶段内） |
| 中英双语（ARB zh/en） | ✅（词表待 R6 更新） | `lib/l10n/app_*.arb`（词表全量按 D1/D2 更新＋扩展 ARB 目录预留 → R6，GAP 2.7） |
| 本地通知提醒 | ✅ | `core/notifications/notification_service.dart` |
| 隐私文档 | ✅ | `docs/PRIVACY.md` |
| 主题自定义：主/辅色、背景色、透明度、背景图片、动画开关（定稿 §4.1） | 🔴 R4 | 现为 ThemeMode system/light/dark（`core/theme/app_theme.dart`、设置页）；R4 主题 JSON 模型＋`Themes` 表 |
| 主题文件导入导出＋内置默认深/浅主题（定稿 §4.2） | 🔴 R4 | 规划中 · settings 模块（背景图导入复制进内部目录） |
| UI 字体与编辑器正文字体分设、本地字体文件导入（定稿 §4.1） | 🔴 R4 | 规划中 · FontLoader 运行时加载（settings 模块） |
| 页面缩放 80%–150%（整体缩放）（定稿 §4.1） | ✅ 2026-10-25 | 常量 0.8–1.5（GAP §4.3）；`app/lib/app/page_zoom.dart` 在 `_AppearanceScope` 内做整体缩放（此前只有文字） |
| 日/周/月日历视图：切换、点击空白/时间块弹浮窗创建或编辑（定稿 1.2.2 / GAP 2.2） | 🔴 R5 | 现为列表＋今日安排汇总（`time_board_page.dart`）；日历网格 R5（table_calendar 或手写，O1） |
| 本地存储：SQLite＋本地文件，附件/背景图文件管理（定稿 §3） | 🟡 缺口：附件目录规范化、背景图/主题文件入内部目录 → R4 | Drift SQLite ✅（`data/database/`）；附件/背景文件管理未做 |

---

## 说明

- ✅/🟡/🔴 与 [GAP_ANALYSIS.md](GAP_ANALYSIS.md) §2 的状态列（🟢/🟡/🔴）逐行一致：🟡 均注明缺口，🔴 均标注目标阶段（R\* 定义见 GAP §6 / MILESTONES §2；Android 适配为 v0.3 发布节奏目标，不在 R 阶段内）。未实现的 🔴 行只写模块级预计位置，不预写不存在的文件细节。
- 产品定稿（2026-09-07）未推翻既有闭环；「v0.1 保留能力」行源自 PROGRESS.md 实现记录，未在 GAP §2 单独占行。
- 环境：本机已装 **Flutter 3.47.2 / Dart 3.13.2**（Windows 实机可用）。
- 验证手段：`dart analyze`（0 error）＋ `flutter test`（全绿）；Windows 构建冒烟：`scripts/build_windows.ps1`（R6 DoD）。
