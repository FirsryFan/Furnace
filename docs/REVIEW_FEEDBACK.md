# 评审反馈汇总与对策（REVIEW_FEEDBACK）

> 来源：用户 2026-10-25 反馈（12 条）。本文档只做**问题记录、取证与对策设计**，不改任何代码。
> 取证基线：`class-productivity` HEAD `3032663`（v0.6.10 发布提交），工作树干净。
> 取证方式：只读检索与读文件（grep / read）。凡是没实际跑过或没看到的，文中标「未验证」。
> 每条格式：现象（用户原话）→ 现状取证 → 根因 → 对策与取舍 → 影响面 → 优先级与工作量。

## 0. 总览

| # | 主题 | 类型 | 根因状态 | 优先级 | 粗估工作量 |
| --- | --- | --- | --- | --- | --- |
| 1 | 「AI 对话」改名「智能化」 | 文案/信息架构 | 已取证 | P0 | 0.2 片（Lead 单人） |
| 2 | 换应用图标（现为 Flutter 默认） | 资源/品牌 | 已取证（看过 PNG） | P0 | 0.5 片 |
| 3 | UI 风格「不自然」 | 设计系统 | 已量化取证，但「自然」需定义 | P1 | 2–3 片 |
| 4a | 思维链接收与展示（thinking 被丢） | 协议解析 + 模型策略 | 已取证 | P1 | 1–1.5 片 |
| 4b | 生成中可中断（现在只能等） | 适配器取消 + 状态机 + UI | 已取证，取消原语已验证 | P0 | 1 片 |
| 5 | 动画「干脆利落」（正面反馈） | — | — | 仅记录 | 0 |
| 6 | Time 行高不能自由缩放/拖分界线 | 交互 + 视觉 | 已取证 | P0 | 1–1.5 片 |
| 7 | 知识网络图没有可用性 | 布局算法 + 交互 | 已取证 | P2 | 3 片以上 |
| 8 | 认知测评应测「能力」而非知识点 | 新模块 | 已取证（现为知识点自评） | P2 | 3 片以上 |
| 9 | 组卷网检索词过短 | 纯逻辑 + 标准同步 | 已取证 | P1 | 1 片 + 人工验证 |
| 10 | 标签系统无边界（到处都是） | 数据模型 + 全系统选择器 | 已取证 | P1 | 2–3 片 |
| 11 | 时间只能用「纳入时间表」标签树 | 依赖 10 | 已取证 | P1 | 含在 10 里 |
| 12 | 「今日安排」其实是所有安排 | 文案 + 数据口径 | 已取证 | P0 | 0.2 片 |

**一句话结论**：P0 五项（1、2、4b、6、12）都是小改动、高感知，建议一轮内打包；3、7、8 是「重定义产品形态」的大改，需要先定标准再动手；10/11 是数据模型改动（标签加「用途域」），会和后续所有选择器相关，最好一次设计对。

---

## 1. 不要叫「AI 对话」，叫「智能化」

**现象**：用户原话「不要叫"AI对话"，叫"智能化"」。

**现状取证**
- 文案：`app/lib/l10n/app_zh.arb:955` `"aiTitle": "AI 对话"`；`app/lib/l10n/app_zh.arb:954` `"navAi": "对话"`。英文对应 `app_en.arb:951-952`（"Chat" / "AI chat"）。
- 使用点：`app/lib/features/ai/presentation/ai_chat_page.dart:440`（桌面侧栏标题）、`:795`（窄屏 AppBar）；导航目的地标签在 `app/lib/app/shell/home_shell.dart:50` `destination('ai', l10n.navAi)`，图标选择页 `icon_picker_page.dart:203` 也复用 `navAi`。
- 附带：persona 文案两处提到「AI 对话」：`app_zh.arb:3026`（personaEditorHint）、`:3063`（personaClearConfirmBody）。
- 文档层：全 docs 中出现 "AI 对话|AI chat" 共 17 次 / 6 个文件（DATA_MODEL 1、FEATURE_MATRIX 2、PERSONA_DESIGN 1、PROGRESS 9、QUESTION_INTAKE_AUDIT_DESIGN 1、REASONING_LAYER_DESIGN 3）。

**根因**：命名停留在「界面形态」（对话），用户要的是「能力定位」（智能化）。这不是翻译问题，是入口语义问题。

**对策与取舍**
- 推荐：中文 `aiTitle` →「智能化」，`navAi` →「智能」（导航栏放不下四个字）；英文 `aiTitle` → "Intelligence"，`navAi` → "Intelligence" 或 "Smart"（**待用户拍板**）。同步改 persona 两处「AI 对话」措辞（如改为「智能化」）。
- 备选：只改标题不改导航（不一致，不推荐）。
- 取舍：改名会牵动 6 份文档的既有描述；建议一次性替换 + 在 FEATURE_MATRIX 标注「同一功能的旧称」避免检索断链。
- 注意：`navAi` 同时是主题图标槽位标签（icon_picker_page），改名后主题编辑器里那一格的显示名也会变，这是预期的。

**影响面**：2 个 ARB + gen-l10n 生成的 3 个文件、`ai_chat_page.dart`（不一定要改代码，只改 l10n）、`home_shell.dart:50`（通过 l10n 生效）、`icon_picker_page.dart:203`；docs 6 份。

**优先级**：P0（0.2 片，Lead 单独完成即可）。

---

## 2. 给软件一个新图标

**现象**：用户原话「给软件一个新的图标」。

**现状取证（已实际查看 PNG）**
- `app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png` 是 **192×192 的蓝色 Flutter 默认 logo**（就是 Flutter 官方标志，不是 Furnace 自己的）。五档 mipmap 体积 442/544/721/1031/1443 B。
- **没有自适应图标**：不存在 `mipmap-anydpi-v26/`，`AndroidManifest.xml` 直接 `android:icon="@mipmap/ic_launcher"`、`android:label="Furnace"`。
- Windows：`app/windows/runner/resources/app_icon.ico` 33,772 B（大概率也是默认图标，未逐像素比对 → **未验证**）。
- 工程只有 `android` 与 `windows` 两个平台目录（`app/` 下实测），没有 iOS/macOS/Linux，故只需出 Android 五档 + 自适应图标 + Windows .ico。
- `pubspec.yaml` 无 `flutter_launcher_icons` 依赖/配置。

**根因**：从模板工程起就一直沿用 Flutter 默认启动图标，从未做过品牌资源。

**对策与取舍**
- 设计方向（建议二选一，**待用户拍板**）：
  - A「炉膛」：深色圆角方块 + 简化炉口/火焰负形，与产品名 Furnace 呼应，缩到 48px 仍可辨。
  - B「字母 F」：几何切割的 F，沿用量化/学习工具的冷静感，与现有墨绿主色 #2F6F4F 搭配。
- 生产：用 Pillow（环境已带 Python/Pillow）生成 512 母版 → 导出 48/72/96/144/192 五档 + 自适应前景/背景（108dp 安全区）+ 多尺寸 .ico；或引入 `flutter_launcher_icons` 作为 dev 依赖（会多一个依赖 + 需要 pub get，网络受限时可能失败，**偏手动生成**）。
- 取舍：图标是品牌事项，算法生成只能做「可用的几何图形」，视觉打磨建议用户给参考图或选方向；先出 1–2 版预览图给用户看，确认后再落到各密度。
- 另：`app/android/app/src/main/res/drawable*/launch_background.xml` 是白底启动图，换图标后启动页可顺带统一背景色（可选）。

**影响面**：`app/android/app/src/main/res/mipmap-*/ic_launcher.png`（+ 新增 anydpi-v26 两个 xml/png）、`app/windows/runner/resources/app_icon.ico`、`AndroidManifest.xml`（若加 roundIcon）、可选 launch_background。

**优先级**：P0（0.5 片；需要用户选方向）。

---

## 3. UI 风格「不是很自然」

**现象**：用户原话「UI 风格不是很自然」。

**现状取证（量化）**
- `app/lib` 下 346 个 dart 文件统计：`Card(` 90 处；`EdgeInsets.*` **125 种不同写法**；`BorderRadius.circular` **11 种半径**（2/3/4/6/8/10/12/18/999/height÷2/width÷2）；手写 `fontSize` 只有 9/10/11/12/13 五档但散落各处。
- 主题层没有设计 token：`app/lib/core/theme/theme_profile.dart:231-238` builtinLight 只有 4 个色值；`toThemeData()`（:247-317）只设置 colorScheme / 背景透明度 / cardTheme / dialogTheme / fontFamily / editorFont，**没有间距、圆角、阴影、字号层级**。
- Material 3 + `ColorScheme.fromSeed`（`app/lib/app/app.dart:41-54`）与大量手写 `Padding/Row/Container` 混用。

**根因**：没有「设计 token 层」。每个页面各写各的间距/圆角/字号 → 页面之间密度、留白、层级不一致，观感「不自然」。这是系统性原因，不是某页没调好。

**对策与取舍**
- 推荐分两步：
  1. **定规则**（写进 `docs/APPEARANCE_DESIGN.md`）：间距 4pt 栅格（4/8/12/16/24/32）；圆角三档（8 小控件 / 12 卡片 / 16 对话框 / 999 pill）；字号只用 textTheme 语义档（bodySmall/bodyMedium/titleMedium…），禁止手写 9–11px；卡片只在「可点整体」时用，列表页用留白+分隔线代替层层 Card；颜色只用 colorScheme 语义色。
  2. **落地 token**：给 ThemeData 加 ThemeExtension（`AppSpace` / `AppRadius`），先扫 6 个高频页面（首页壳 / 智能化 / 题库 / 题目详情 / Time / 设置），不追求 346 个文件全改。
- 取舍：全量重写风格风险极高（视觉回归、用户已满意动画）；token + 6 页的「定点改善」性价比最高。**「自然」是主观词：需要用户至少给一个偏好方向**（更紧凑/更松弛、更少卡片/更多分区、字体更小/更大、圆角更小/更大），否则做出来仍可能不对味。
- 需要用户答复的问题（见 §14-Q2）。

**影响面**：`core/theme/theme_profile.dart`、`app/app.dart`、6 个页面文件；`docs/APPEARANCE_DESIGN.md`、`FEATURE_MATRIX.md`。

**优先级**：P1（2–3 片；先定方向再动手）。

---

## 4. AI：思维链没提取 + 生成不能中断

### 4a 思维链（reasoning）被丢弃

**现象**：用户原话「AI 思维链没有提取过来」。

**现状取证**
- SSE 解析层只取三样：`usage`、`choices[].delta.content`、`choices[].delta.tool_calls`（`app/lib/features/ai/infrastructure/sse_assembler.dart:36-93`，分别 :39-57 / :71-75 / :77-90）。推理模型的 `reasoning_content`（DeepSeek）或 `reasoning`（OpenRouter 系）字段**完全不解析、不显示、不落库**。
- 事件模型没有 reasoning 事件：`app/lib/features/ai/domain/model_adapter.dart:295-301` 的 `runTurn` 只产出 :214-288 定义的 sealed 事件（ModelTextDelta / ModelToolCall / ModelTurnDone / ModelFailure）。
- 落库也没有列：`app/lib/data/database/tables.dart:899-920` `AiMessages` 只有 id/conversationId/role/content/toolCallId/createdAt。
- 模型本身可配置：设置页有 `settingsAiModel` 输入框（`app/lib/features/ai/presentation/ai_settings_page.dart:141-148`），用户可以填 `deepseek-reasoner`；`app/lib/features/ai/application/ai_providers.dart:60-64` 用它构造适配器 → **现在即使用 reasoner，思考也会被静默丢掉**。
- 与既有决策冲突：`docs/AI_DESIGN.md:111-112` 决策 D5「默认不用 deepseek-reasoner（工具调用更易偏离格式、更贵更慢）」。

**根因**：协议解析层按「chat 模型」写死，只认 content/tool_calls；产品决策 D5 又主动回避 reasoner。两层叠加 → 思考字段从未进入系统。

**对策与取舍**
- 协议层：`ModelEvent` 新增 `ModelReasoningDelta`（字段 text）；SSE assembler 兼容三种形状：`delta.reasoning_content`（DeepSeek）、`delta.reasoning`（OpenRouter 等）、`delta.content` 数组里 `type=="reasoning|thinking"` 的 part（部分 OpenAI 兼容网关）。
- 展示层：assistant 消息气泡下方加「思考过程」折叠区（默认收起，流式时显示字数/秒表），生成结束后可展开；不打断正文流。
- 落库：schema v36 给 `ai_messages` 加 nullable `reasoning` TEXT（与正文分开存，避免混进 content 影响后续轮上下文）。**建议必做**：否则重启后思考消失。
- 模型策略：默认模型仍 `deepseek-chat`（D5 不变，工具调用稳定）；用户手动填 reasoner 时自动显示思考，并在设置页加一句提示「推理模型更慢、更贵、工具调用可能偏离格式」。要不要在 UI 里给「推理强度/思考开关」做成显式选项，**待用户拍板**。
- 取舍：思考 token 计费但默认收起不影响阅读；若某些网关把思考混在 content 里则无法区分（按 content 处理，标注「未验证」）。

**影响面**：`sse_assembler.dart`、`model_adapter.dart`、`openai_compat_adapter.dart`、`agent_loop.dart`（事件透传）、`ai_chat_page.dart`（渲染 + 折叠）、`ai_repository.dart`/`tables.dart`/`database.dart`（v36）、l10n、`docs/AI_DESIGN.md`（D5 需补一条「reasoning 字段处理」决策）。

**优先级**：P1（1–1.5 片）。

### 4b 生成不能中断

**现象**：用户原话「同时不能中断 AI 的生成」。

**现状取证**
- 适配器没有取消入口：`openai_compat_adapter.dart`（205 行）`runTurn` 是 async*（:50），request/response 都是局部变量，**无法从外部中止**；只有 `void close() => _client.close(force: true);`（:204）能关整个 HttpClient（会波及所有请求）。
- 循环没有取消路径：`agent_loop.dart:702` `while (_metrics.rounds < maxRounds)`，:729 `await for (final event in adapter.runTurn(...))`，中途无检查点；`:535` `dispose()` 只关状态流。失败路径会保留已生成文本并落库（:765-774），说明「半截回答」概念已存在。
- UI 没有停止按钮：`ai_chat_page.dart:719-727` 生成中只是把发送按钮 disabled；`_subscription` 只在 `dispose`(:134) 与 `_attach`(:149) 取消。
- 取消原语已验证存在：Dart SDK `D:\flutter\flutter\bin\cache\dart-sdk\lib\_http\http.dart:1869-1880` 有 `HttpClientRequest.abort()`（文档 "Aborts the client connection"）。

**根因**：适配器 API 契约（`Stream<ModelEvent> runTurn`）没有任何「取消」信号；上层循环与 UI 也就没有可接的钩子。

**对策与取舍**
- 适配器：改为「可取消的流」——内部持有当前 `HttpClientRequest`/`HttpClientResponse`，暴露 `void cancelActiveTurn()`（abort + 关订阅）；`runTurn` 被 abort 后以 `ModelFailure(cancelled)` 或新事件 `ModelTurnCancelled` 结束（推荐新事件，别混进失败）。
- Loop：`AgentLoop` 加 `cancel()`：置 `_cancelled` → 取消订阅 → 不执行后续工具调用 → 已生成文本照现有失败路径落库，消息标记「已停止」。
- UI：生成中把发送按钮换成停止（Icons.stop），点击 → `loop.cancel()` → 气泡尾部显示「已停止」+ 可「继续」（把已生成文本作为 assistant 前缀让模型续写，可选）。
- 取舍：
  - 半截回答是否入库：建议入库（否则用户丢失已生成内容），但状态标 interrupted，不让它进入后续上下文？——建议仍进入上下文（用户要继续写），标注清楚即可。
  - 工具调用进行中停止：已有执行的工具结果保留，后续不再执行新工具。
  - 手写整理（`handwriting_proposal_service`）也用同一 adapter，但那是另一条调用路径；cancel 只作用于当前 turn，不要做全局 close。

**影响面**：`openai_compat_adapter.dart`、`model_adapter.dart`、`agent_loop.dart`、`ai_chat_page.dart`、`ai_repository.dart`（interrupted 标记，可能复用现有列或 v36 加一列）、l10n。

**优先级**：P0（1 片；用户最直接的痛点之一）。

---

## 5. 动画效果「很不错，干脆利落」

**现象**：用户原话「动画效果其实很不错，干脆利落，很好」。

**处理**：不改。作为**回归红线**记录：后续任何 UI 重构（尤其 §3 的 token 化）不得改现有页面切换/列表动画的时长与曲线；`docs/PROGRESS.md` 与 `docs/APPEARANCE_DESIGN.md` 应加一行「动画已验证，改动需保持」。

---

## 6. Time 长度标尺：行高应可自由缩放 / 分界线可拖动

**现象**：用户原话「Time 部分的可视化做的很不好。长度标尺不要给限定的，最好让用户可以拖动进行自由缩放；如果不好写，你可以让拖动给一些挡位。拖动的意思是区分两行有分界线，分界线可以拖动。」

**现状取证**
- 纵轴只有三挡：`calendar_page.dart` AppBar 缩放菜单 15/30/60（:104-125）；`_minutesPerRow=30`（:52）、`_rowBaseHeight=44`（:55）、`_rowHeight => 44*(60/_minutesPerRow)`（:57）→ 行高是行数的**从属变量**，不能单独调。
- 分界线不可拖：整个 `app/lib/features/timeboard` 目录 grep `onVerticalDrag|onHorizontalDrag|InteractiveViewer` = **0 命中**。
- 偏好持久化：`timeViewRepository.update(minutesPerRow, chosen:true)`（:77-84）；表 `TimeViewSettings`（`tables.dart:832`）已有 `minutesPerRow`（:851）与 `minutesPerRowChosen`（:856）。
- 规格来源：`docs/DESIGN_BLUEPRINT.md:143`『纵轴缩放必须有【用户15】档位 15/30/60；手机默认 60，仅日视图可 30』→ 现状是**忠实实现了旧规格**；用户现在的新要求是规格变更。

**根因**：设计把「时间粒度（minutesPerRow）」与「像素密度（行高）」绑成一个量，且只允许三档枚举 → 无法连续缩放，也没有拖拽交互。

**对策与取舍**
- 推荐：**解耦 + 拖拽**。
  1. 数据：`TimeViewSettings` 新增 nullable `rowHeight`（REAL/INT，像素，v36 迁移）；`minutesPerRow` 降级为「标签/格线粒度」，继续用 15/30/60。
  2. 交互：`_DayGrid` 中每个行分界线加 10–14px 命中带，`onVerticalDragUpdate` 连续调整局部行高（clamp 18–200px），拖动时显示浮动读数（如「30 分钟 · 66 px」）与高亮线；松手落库。
  3. 挡位：保留 15/30/60 菜单作为「一键吸附」（用户说「如果不好写可以给挡位」，我们给自由拖 + 挡位吸附两全）；可选在拖拽松手时吸附到最近挡位（做成开关，默认自由）。
  4. 可用性：行高变化时自动滚动保持视口中心时间不变；min/max 之外视觉回弹。
- 取舍：
  - 极端行高（<18 或 >200）没有意义，clamp 保护；
  - 连续缩放后 `_DayGrid` 高度 = rows×rowHeight 会变得很大/很小，需要「整日 24h 可滚」行为不回归（现在就是滚动容器，风险低）；
  - 若不想加 DB 列：可把 rowHeight 存进现有 settings JSON（如 `local_settings` 某列），但独立表列更干净，且 `TimeViewSettings` 本来就是放这个的。

**影响面**：`calendar_page.dart`（缩放菜单、_DayGrid、rowLabel/isMajorTick、分隔线绘制）、`time_view_repository.dart`、`tables.dart`/`database.dart`（v36）、`time_view_settings` 相关 provider、测试（calendar 现有测试需补拖拽用例）、`docs/DESIGN_BLUEPRINT.md:143` 规格改写。

**优先级**：P0（1–1.5 片；用户明确点名的可视化问题）。

---

## 7. 知识网络图「完全没有可用性」

**现象**：用户原话「知识网络图依旧完全没有可用性」。

**现状取证**
- 布局（`app/lib/features/cognitive/presentation/cognitive_graph_layout.dart:135-220`）：知识点按 tag 名+标题排序后**均匀排在同一个外环**（outerRadius = shortestSide/2×0.72，:162；角度 2πi/n，:167-180）；标签圆落在内环（innerRadius = outer×0.42，:163；按 circular mean，:192-205）；节点半径 `5+min(cardCount,8)*1.6`（:177）。布局确定性 O(n)，无聚类、无迭代。
- 页面（`cognitive_graph_page.dart`，588 行）：画布边 `kCognitiveGraphMaxSide=840`（:34）；`_GraphBody.build` :236-322，side=min(可用宽,高,840)（:270-273），画布内**只有 `GestureDetector(onTapUp)`**（:283-291）+ `CustomPaint`（:292-299）→ **无缩放、无平移、无搜索、无筛选、无分组**。
- Painter（:419-588）：参考双环、连线、标签方块（宽 `26+min(memberCount,8)*6`，高 20）、标题截断 6 字、知识点标题沿径向截断 8 字。字号固定 10–11。

**根因**：单一环状布局把所有节点塞进「一个环 + 一层标签环」，节点数一多必然重叠；画布钉死 840px 且不可缩放平移 → 读不了、点不准。**这是布局算法 + 交互双缺失**，不是配色问题。

**对策与取舍（建议分三期，每期都可独立上线）**
- 期 1（可用性急救，1 片）：`InteractiveViewer`（0.4×–4×，双指/滚轮缩放 + 拖拽平移）+ 初始自适应缩放 + 「重置视图」按钮；缩放 < 0.8 时隐藏文字、只画点/连线。这一步就能让大图从「不可读」变成「能读」。
- 期 2（布局 v2，1–2 片）：按标签分簇——每个标签一个扇区（角度按成员数加权），知识点围绕所属标签中心做黄金角散点（golden-angle spiral），同一知识点只挂主标签；无标签节点放中心簇；标签名放簇外侧、按象限对齐。
- 期 3（交互补全，1 片）：点节点弹底部详情（标题/标签/卡数/跳转），不再常驻长标签；顶部搜索框定位并高亮；图例 + 「只看某标签」筛选；列表视图切换作为兜底（按标签分组的可展开列表）。
- 取舍：力导向布局好看但不确定、难测试、性能不稳（节点多时抖）——**不建议**；黄金角+分簇是确定性的，可写布局单测。做全量重写前，先在 50/200/500 节点三个规模下验收点/标签重叠率与可点击率。

**影响面**：`cognitive_graph_layout.dart`（重写）、`cognitive_graph_page.dart`（InteractiveViewer、搜索、详情 sheet、列表兜底）、布局单测、`docs/APPEARANCE_DESIGN.md`/`MINDNET_INTEGRATION.md` 若有图示描述需同步。

**优先级**：P2（3 片以上；但期 1 可先做，1 片见效）。

---

## 8. 认知测评：应测能力（humanbenchmark 式），不是选标签测知识点

**现象**：用户原话「认知模型的用户测评不在于知识点而是能力，所以不是选择标签然后测，而是有一些指标，类似 humanbenchmark 一样，测试能力」。

**现状取证**
- 文档本来就有能力参数蓝图：`docs/ASSESSMENT_DESIGN.md:34-44` 列了 R0/S/Σ/D/fluency/校准偏置/closeness/α(τ)/作答速度；:52-56 三种信号（自评 / 复述抽检 / 板块客观题）；:66-73 定义了 `AssessmentInstrument` 抽象（subjectKey / defaultScope / plan / judge）；但 :114 记 M1c **只做了通用 instrument（自评+复述）**。
- 落库表：`AssessmentSessions`（tables.dart:1024-1054，subjectKey :1031、scopeTagIds :1037）；`AssessmentResponses`（:1062-1104，stepKind `self_report|recall|objective` :1079、correct :1086、selfRating :1089、confidence :1093、judgedBy :1098）。
- 页面（`assessment_page.dart`）：四步（选范围/自评/复述/读数，:150-152），字段 `_tagIds/_selfRatings/_recallAnswers/_recallRatings`（:153-156），`_finish`（:184-258）逐知识点写 `selfReportStep/recallStep` → `finishSession` → `rebuildPriors`；结果只显示 mean R0 / mean confidence（:241-242）。
- 即：现有测评**完全是知识点域**（先选 tag → 对每个知识点自评/复述 → 更新知识先验），没有一项测「能力」。

**根因**：M1c 是知识先验（R0）的采集工具；用户要的是**能力画像**（反应/记忆/识别/推理速度这类可量化指标），两者是不同测量对象，不能靠改文案解决。

**对策与取舍（新模块，与知识先验解耦）**
- 能力维度（MVP 4 项，每项 1–2 分钟，纯本地确定性小测）：
  1. 反应速度：随机延迟后目标出现，点击测中位反应时（ms）；
  2. 工作记忆：数字/空间序列回忆，测最长正确跨度；
  3. 模式识别：数列/图形规律 4 选 1，测正确率 + 平均用时；
  4. 注意稳定性：go/no-go 持续任务，测错误率与反应时波动。
- 结果：新表 `ability_scores`（v36：id / dimension / score / rawMetricsJson / takenAt），结果页做条形/雷达 + 历史趋势；后续可选映射到能力动作词表（`capability_action.dart` 已有）与 MindNet 的 fluency 参数，但**第一版不接**，避免耦合。
- 与现有测评的关系：保留知识点测评（它是 R0 先验来源），在认知模型页并列两个入口：「知识测评」「能力测评」；文案讲清楚测的是什么。
- 取舍：这类短测信度有限，定位必须是「看自己的相对变化趋势」而非绝对智商；不联网、不接 AI；题目用本地静态数据 + 固定随机种子，可复现、可测试。

**影响面**：新 `features/assessment` 子模块（page/controller/data）、`ability_scores` 表 + v36 迁移、`cognitive_model_page.dart` 入口、l10n、`docs/ASSESSMENT_DESIGN.md` 新增一节。

**优先级**：P2（3 片以上；新特性，建议在 P0/P1 之后）。

---

## 9. 组卷网检索词过短

**现象**：用户原话「组卷网检索词过短，理科 15 - 30 个字比较合适，文科可以多一点，但文科题干 > 文章」。

**现状取证**
- app 侧抽词（`app/lib/domain/services/zujuan/zujuan_keywords.dart`，295 行）：候选一律限制 **4–28 字**（:125）；学科术语锚点窗口左右各扩 ≤10 字、只收 4–24（:231）；无锚点时用 `_diverseWindows` 从 12 字降到 5 字（:241），每段取 3 条；打分 `_keywordScore`（:281-294）对 **5–16 字加分、>20 字扣分**（+3 / -2）→ 天然偏好短词。领域词表只覆盖生物（:22-25 已注明局限、:33-84 词表）→ 理科其他科目没有锚点。候选去重后最多 8 条（:158-168）。
- UI（`question_zujuan_search.dart`）：只展示前 5 条（`questionZujuanVisibleCandidateLimit=5` :25），每条只有「复制检索词 / 复制链接」（:156-203），**不显示字数**，没有长度档位。
- 标准侧（app 是逐条移植自 skill）：`D:/dsh-data/skills/zujuan-source-standards/scripts/keywords.mjs` 同一套常量（:68 段长≥4；:113 4–24；:127 窗口 5–14 加分；:147 >20 扣分；:162 4–28），`SKILL.md:237` 要求「只取题干里站点文本层真实存在的片段，切成若干条连续候选串」，`:253` 要求「每题 5~8 条候选按内容词密度排序」。`SKILL.md:86-87` 只有学科代码表（gzyw/gzsx/gzyy/gzwl/gzhx/gzsw），**没有文/理科长度口径**。
- 结论：用户看到的「检索词过短」是**设计如此**（打分偏好 5–16 字），不是 bug。

**根因**：候选生成按「短窗口 + 内容词比例」设计，没有按学科设定目标长度；标准文档也没有这条要求。

**对策与取舍**
- 推荐规则：
  - 理科（数学/物理/化学/生物）：候选目标 **15–30 字**，优先「一个完整设问句或含条件+设问的连续片段」，至少含 1 个学科术语/条件词（求/证/判断/计算/取值范围…）。
  - 文科（语文/英语/历史/政治/地理）：候选可到 **20–40 字**，但必须 **短于题干/材料本身**（用户原话「文科题干 > 文章」，含义**待确认**：我理解为检索词长度要小于题干/材料，不能整段照搬；见 §14-Q5）。
  - 生成算法：按标点切分句 → 过滤含术语/条件词的完整分句 → 长度落在目标区间直接用；不足则合并相邻分句；超长则按术语锚点截断到区间上界。打分改为「区间内为正、区间外递增扣分」，去掉 5–16 字偏好。
  - UI：每条候选显示字数（如「23 字」），可展开查看全部候选；默认选第一条。
  - 标准同步：同时改 `keywords.mjs` 与 `SKILL.md`（加「按学科长度口径」一节），app 与 skill 保持同源，否则下一轮又会漂移。
- 取舍：长检索词在组卷网全文检索里**命中率可能下降**（未验证）→ 建议同时保留短候选，UI 分「标准长度 / 短候选」两组；先拿 10 道真实题做人工 A/B（长短各搜一次记命中），再定默认策略。
- 风险：生物词表之外的学科仍缺术语锚点；可先用「设问词 + 条件词」通用锚点兜底，后续再补词表。

**影响面**：`zujuan_keywords.dart` + 单测、`question_zujuan_search.dart`、`D:/dsh-data/skills/zujuan-source-standards/scripts/keywords.mjs`、`SKILL.md`、`docs/ZUJUAN_LINKS_DESIGN.md`。

**优先级**：P1（1 片 + 人工验证）。

---

## 10. 标签系统「到处都是」，没有边界处理

**现象**：用户原话「标签系统仅仅是到处都是，没有边界处理」。

**现状取证**
- 表结构：`Tags`（`tables.dart:191-209`）只有 id/parentId/name/path/color/description/sourceNodeId/createdAt/updatedAt，path 唯一；**没有任何 scope/domain/kind 列** → 全局一棵树。
- 多态挂载：`ObjectTags`（:212-226）tagId + objectType + objectId 唯一三元组；lib 中实际用到的 objectType 至少 4 类：`time_block`（time_board_page.dart:332/451/473）、`knowledge_point`（tag_repository.dart:369、review_plan_repository.dart:37/237、anki_manage_page.dart:657/707/729、review_service.dart:297/581/1327）、`question`（tag_repository.dart:214/269、question_repository.dart:319）、`task`（task_detail_page.dart:438/447、task_scheduler_service.dart:33、thread_page.dart:379、thread_rank_service.dart:205、mind_map_page.dart:348）。
- 选择器全部拉全树：`getAllTags()` 在 lib 中有 **23 处调用**，典型：time_board_page.dart:425、task_detail_page.dart:413、question_bulk_tag_dialog.dart:59、assessment_page.dart:45、anki_manage_page.dart:683、review_plan_page.dart:474、handwriting_proposal_service.dart:318/417/696（AI 建议标签也用全树）、content_query_tools.dart:164/203、deletion_tools.dart:207、cognitive_tools.dart:255。
- 没有「用途/域」概念：docs 中 grep「纳入时间表 / 时间表标签 / 标签树边界」= **0 命中**（唯一相关是 TAG_TREE_SORT_DESIGN.md 讲排序）。
- AI 侧同样：手写整理提示词把「已有标签路径」全量喂给模型（handwriting_proposal_service.dart:318 附近），模型可以在任何地方建议任何标签。

**根因**：标签是**全局单树 + 多态挂载**，没有「这棵树属于哪个域」的声明 → 每个选择器都显示全部标签，语义边界不存在。

**对策与取舍（与 §11 是同一底层机制）**
- 引入「标签用途 / 域」（tag usage）：枚举 `time | question | knowledge | task | flashcard | mindmap`；**在子树根上声明**，整棵子树继承。
- 存储方案对比：
  - **A（推荐）**：schema v36 给 `local_settings` 加 nullable `tagUsageJson` TEXT，存 `{"<rootTagId>": ["time","question"]}`；查询用 path 前缀展开子树（path 是权威路径，:195）；新增 Repository 方法 `tagsUnderRoots(Set<String> roots)` / `usagesForTagPath(path)`。
  - B：`Tags` 加 `usageMask` 列——每节点存 per-usage 位，继承父级；数据更自洽、查询更简单，但迁移 + 全量写入 + 树移动更新逻辑更重。
  - C：新建 `TagDomains` 表（rootTagId + usage 唯一）——规范化，但多一张表 + join，收益与 A 接近。
  - 取舍：A 最省、可逆、不污染 Tags 表；代价是树移动/删除要清理 JSON（在 tag 重命名/移动/删除服务里同步），以及「未声明 = 什么行为」需定默认。
- 默认策略（重要）：**未声明用途的标签树，在所有选择器里仍可见**（向后兼容，不突然清空老用户标签）；只有声明过的树才按域过滤。时间域例外见 §11。
- 设置入口：标签树页（`tag_tree_page.dart`）节点长按/菜单 →「用途」多选对话框；标签详情抽屉也放一份。
- 分步落地：先做机制 + 时间域（§11）→ 再逐域收紧（题目/任务/知识/闪存卡选择器）。
- 取舍：全系统域限制会改变现有操作习惯（比如题库里看不到时间表的标签），必须给「显示全部」的逃生阀，否则用户会找不到标签。

**影响面**：`tables.dart`/`database.dart`（v36）、`settings_repository.dart` 或新 `tag_usage_repository.dart`、`tag_repository.dart`（新查询）、`tag_tree_page.dart`（用途设置 UI）、各选择器（time/task/question/anki/assessment/AI tools 建议标签）、l10n、`docs/DATA_MODEL.md` + 新设计文档（可并入 TAG_TREE_SORT_DESIGN 或新建 TAG_SCOPE_DESIGN.md）。

**优先级**：P1（2–3 片；建议先机制 + 时间域，其他域后续按需）。

---

## 11. 时间接入标签系统：只允许「纳入时间表」的标签树

**现象**：用户原话「时间接入标签系统，应该是标签系统中有设置为"纳入时间表"的标签树，然后时间表内标签都限于那棵树里的标签」。

**现状取证**
- 时间块打标签：编辑对话框 `time_board_page.dart:415-461`——点「+」→ `tagRepository.getAllTags()`（:423-425）→ 排除已选 → **全库所有标签**列表；`addTagToObject(objectType:'time_block')`（:447-453）。
- 日历视图对标签零使用：`app/lib/features/timeboard` 目录 grep tag = 只在 time_board_page 出现（时间块编辑与标签列表），CalendarPage 不用标签。
- 时间块另有 `energy` / `suitableFor` 两个专用列（编辑对话框 :372-411），标签是附加物。

**根因**：时间块挂标签时没有「哪些标签允许用于时间」的概念，直接读全局树。

**对策（依赖 §10 的 tag usage 机制）**
- 标签树页给任意子树根开关「纳入时间表」（即写入 usage `time`）。
- 时间块标签选择器：只列出 usage 含 `time` 的树的子树标签；支持多棵树同时纳入。
- 空状态：如果全库没有任何树被纳入 → 选择器显示提示「还没有标签树被设置为"纳入时间表"」+「去设置」按钮（跳标签页），**同时**给一个「显示全部标签」的临时入口（避免功能不可用）；或默认按「未声明 = 可用」的全局默认路径（见 §10 默认策略），两者取一，**建议后者**（零配置可用，用户显式声明后自动收紧）。
- 可选增强（不在本轮）：时间块标签驱动日历着色/筛选；日历里按标签过滤日程。

**影响面**：`tag_tree_page.dart`（用途开关）、`time_board_page.dart:415-461`（选择器过滤 + 空状态）、`tag_repository.dart`、l10n。

**优先级**：P1（含在 §10 里，约 +0.5 片）。

---

## 12. 「今日安排」其实是所有安排

**现象**：用户原话「"今日安排"其实是所有安排」。

**现状取证**
- 文案：`app_zh.arb:64` `"timeTodaySchedule": "今日安排"`（en `app_en.arb:70` "Today's schedule"）。
- 使用点：Time 模块第二个 tab 的标签 `time_page.dart:46`；`time_board_page.dart:103` 的卡片标题。
- 数据口径：
  - `timeBlocksProvider`（time_board_page.dart:10-13）→ `timeBlockRepository.getTimeBlocks()`（`time_block_repository.dart:41`，签名只有 `{bool onlyAvailable = false}`，**没有日期过滤**）→ 列表渲染**全部时间块**（:122-164）。
  - 标题卡片 `timeBlockScheduleProvider`（:28-40）取全部块 + 每块的任务，按 startAt 排序，**同样不限今天**。
- 故「今日安排」这个标题下确实展示的是所有安排（跨天全部）。

**根因**：文案来自旧「今日摘要」概念，页面后来演化成「全部日程块列表」，但没有日期过滤也没改名。

**对策与取舍**
- A 改名（0.2 片，必做）：tab →「安排」（或「日程」），卡片标题 →「有任务的安排」/「按任务关联」；英文 "Schedule" / "Blocks"。
- B 日期过滤（+0.5 片）：tab 内加分段控件「今天 / 本周 / 全部」，默认「今天」；列表按日期分组。calendar 已有日视图，board 的定位若是「批量编辑」则「全部」更有用。
- C 两者都做（推荐）：改名为「安排」+ 默认「今天」、可切「全部」；既不撒谎，也保留批量操作。
- 取舍：这会改变 Time 第二 tab 的默认内容（从全部→今天），对「跨天批量编辑」习惯有影响；默认「全部」+改名也可接受（更小改动，不改变现有行为）。**待用户拍板默认值**（§14-Q6）。

**影响面**：`app_zh.arb`/`app_en.arb` + 生成文件、`time_page.dart:46`、`time_board_page.dart:103`、`timeBlocksProvider`/`getTimeBlocks`（若加日期参数）、`docs/DESIGN_BLUEPRINT.md`（Time 模块描述）。

**优先级**：P0（改名 0.2 片；过滤 +0.5 片）。

---

## 13. 实施批次建议（按性价比排序）

| 批次 | 内容 | schema | 依赖 | 预估 |
| --- | --- | --- | --- | --- |
| A（先做） | §1 改名、§12 改名（先只改文案）、§2 图标方向稿 | 无 | 用户选图标方向/英文名 | 0.7 片 |
| B | §4b 停止生成 + §6 Time 拖拽缩放（+ §12 日期过滤） | v36（time_view_settings.row_height；AI interrupted 标记可选） | 无 | 2–2.5 片 |
| C | §4a 思维链（解析/展示/落库）+ §9 检索词长度（含 skill 同步） | v36（ai_messages.reasoning） | 真实题人工 A/B | 2–2.5 片 |
| D | §10/§11 标签用途域 + 时间标签树 | v36（local_settings.tag_usage_json） | 无 | 2–3 片 |
| E | §3 UI token 化 + 6 页面扫一遍 | 无 | 用户给「自然」方向 | 2–3 片 |
| F | §7 知识网络图（期 1 急救 → v2 → 交互） | 无 | 无 | 3 片以上 |
| G | §8 能力测评新模块 | v36+（ability_scores 表） | 用户确认能力维度 | 3 片以上 |

**建议把 v36 做成一次迁移**（如果 A–D 在同一发布周期内完成）：`time_view_settings.row_height`、`ai_messages.reasoning`、`local_settings.tag_usage_json`、`ability_scores`（若 G 先做）都走同一版 nullable 加列/建表，避免 v36/v37/v38 连发迁移。若分批发布，则每次只加自己需要的列（项目惯例：新列一律 nullable、无回填）。

---

## 14. 需要用户拍板的问题

1. **Q1（改名）**：「智能化」的英文用哪个？"Intelligence" / "Smart" / "Assistant"；导航栏中文用「智能」还是「智能化」？
2. **Q2（UI 自然感）**：你觉得「不自然」主要指哪类？（a 间距/留白不统一 b 卡片太多、层次乱 c 字号偏小/偏大 d 圆角/阴影不统一 e 其他，可配图）——定了方向才能动手改，否则会白做。
3. **Q3（图标）**：选「炉膛」还是「字母 F」方向？有参考图/草图最好。
4. **Q4（思维链）**：思考过程默认展开还是默认收起？要不要在设置里加「推理模型」显式开关（而不是让你手填模型名）？
5. **Q5（检索词）**：「文科题干 > 文章」这句我的理解是「检索词长度要小于题干/材料，不能把整段材料当检索词」——对吗？另外长检索词若命中率下降，是否接受「标准长度 + 短候选」两组并排？
6. **Q6（Time 安排）**：第二个 tab 默认显示「今天」还是「全部」？
7. **Q7（能力测评）**：§8 的四项能力（反应速度/工作记忆/模式识别/注意稳定性）是否认可？还是你心里有其他指标（比如空间旋转、语言流畅性、计算速度）？
8. **Q8（标签边界）**：§10 的默认策略选哪个——未声明用途的标签树「所有域可见」（兼容老数据、零配置）还是「任何域都不可见直到显式声明」（严格但可能让老用户找不到标签）？

---

## 15. 与既有设计文档的关系（改动时要同步的规格）

| 文档 | 现状 | 本反馈带来的改动 |
| --- | --- | --- |
| `docs/DESIGN_BLUEPRINT.md:143` | 纵轴缩放只有 15/30/60 三档 | §6 改为「自由拖拽 + 挡位吸附」规格 |
| `docs/AI_DESIGN.md:111-112`（D5） | 默认不用 reasoner | §4a 补「reasoning 字段解析/展示/落库」决策，默认模型仍 chat |
| `docs/ASSESSMENT_DESIGN.md:114` | M1c 只做自评+复述 | §8 新增「能力测评」章节与 `ability_scores` |
| `docs/APPEARANCE_DESIGN.md:39-65` | 「图标」指导航语义槽位 | §2 应用图标是新增项；§3 设计 token 写进本文档 |
| `docs/FEATURE_MATRIX.md` | 有「AI 对话」等旧称 | §1 改名同步；§5 动画标回归红线 |
| `docs/TAG_TREE_SORT_DESIGN.md` / `docs/DATA_MODEL.md` | 标签只有树与排序 | §10/11 新增「标签用途/域」，DATA_MODEL 加 v36 表列 |
| `docs/ZUJUAN_LINKS_DESIGN.md` | 检索词生成无学科长度口径 | §9 同步学科长度规则 + skill 标准 |
| `docs/PROGRESS.md` | 记录到轮次一百七十三 | 每条落地后补条目；§1 改名要标注旧称 |

---

## 16. 附录：本次取证的边界（未验证项）

- 所有 UI 观感判断（「自然」「可用性」）来自代码结构与用户反馈，**没有真机截图对比**；实际视觉需要真机确认。
- Windows `app_icon.ico` 只看了文件大小，未逐像素确认是否默认图标。
- §4a 的「部分网关把思考混进 content」未逐家验证；SSE 兼容形状按公开协议推断（DeepSeek/OpenRouter/OpenAI 兼容字段）。
- §6 的拖拽方案未做原型，手势与滚动容器的冲突（竖直拖 vs 列表滚动）需真机验证；备选是「长按后进入缩放模式再拖」。
- §9 长检索词在组卷网的实际命中率未验证（需要真实浏览器登录环境）；长短候选 A/B 需人工。
- §7 的黄金角+分簇布局未实现，重叠率与性能数字未测。
- §8 的能力小测没有做信度/效度论证，定位仅是「相对自己变化的趋势」。
- 附带发现（非用户反馈）：`app/${tempDir.path}/` 目录下有 `fake28.db`、`v27.db` 两个 438,272 B 的散落数据库文件（疑为某测试/迁移脚本用了未展开的字符串路径），被 git 忽略、不影响运行，建议清理并修脚本（低优先级）。

---

*本文档由 Lead 整理；所有行号取自 HEAD 3032663 的当前代码，后续改动后可能漂移。*
