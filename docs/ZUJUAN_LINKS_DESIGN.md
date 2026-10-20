# 组卷网链接设计（找同类题的入口）

> 轮次一百二十二。用户指令（m00726）：**「docx 文档的构建和组卷网的链接可以借鉴 dsh skill」**。
> 借鉴对象：`D:\dsh-data\skills\zujuan-source-standards`（SKILL.md、references/url-grammar.md、
> scripts/bridge.mjs、scripts/keywords.mjs、scripts/lib/extract.mjs、scripts/paper.mjs）。
> 本文只讲「把题目变成可打开的组卷网链接 / 检索词候选」；docx 导出见 `docs/DOCX_EXPORT_DESIGN.md`。

## 1. 目标

题干在本地结构化存着，但组卷网（zujuan.xkw.com）是找同类题、看答案的来源。App 不做爬虫、
不联网抓取（答案需登录且是图片、每日 30 道上限），只做**最轻的一步**：从题干算出站点能搜的检索词，
拼成链接，复制到浏览器里搜。适用于「这道题没见过 / 想要更多同类题」的场景。

纪律：

1. **纯逻辑、不联网、不读 DB、不碰 UI**：`lib/domain/services/zujuan/**`。
2. URL 形状与编码**来自 skill 实测**，不凭记忆猜；每处规则在代码注释里注明 skill 文件 + 行号。
3. 缺信息返回 `null`，**不猜**（猜错会拼出别的学科，站点静默 0 条，用户还以为"没这题"）。
4. 学科提醒：搜索按站点当前学科（bankId cookie）过滤，链接只能跳转，**学科要用户自己确认**。

## 2. 文件与 API

| 文件 | 内容 |
| --- | --- |
| `lib/domain/services/zujuan/zujuan_link.dart` | URL 拼接 + 候选配对；`zujuanBaseUrl` |
| `lib/domain/services/zujuan/zujuan_keywords.dart` | 题干 → 检索词候选（`extractZujuanKeywords`） |
| `test/domain/services/zujuan/zujuan_link_test.dart` | +25 例（本机真实输出，见 §6） |

冻结的公开 API：

```dart
const String zujuanBaseUrl = 'https://zujuan.xkw.com';

String zujuanSearchUrl(String keyword);
String? zujuanQuestionDetailUrl({String? bankId, String? questionId});
String? zujuanPaperDetailUrl({String? paperId, String? bankId});
List<String> zujuanKeywordCandidates(String stem, {int maxCandidates = 8});
List<ZujuanSearchCandidate> zujuanSearchCandidates(String stem, {int maxCandidates = 8});

class ZujuanSearchCandidate {
  final String keyword; // 从题干切出的、站点文本层真实存在的连续片段
  final String url;     // = zujuanSearchUrl(keyword)
  Map<String, String> toJson();
}
```

## 3. URL 规则（含编码顺序，最易错）

### 3.1 文本搜题（唯一文本入口）

```
https://zujuan.xkw.com/quessearch?keyword=<base64>&intent=question&b=0&urlSource=0
```

- `keyword` = **UTF-8 → 标准 base64（不是 URL-safe）→ 整体百分号编码**。
  源码证据 `scripts/bridge.mjs:148-151`：
  `const b64 = Buffer.from(String(query),'utf8').toString('base64')` 然后
  `...?keyword=${encodeURIComponent(b64)}&intent=question&b=${offset}&urlSource=0`。
  ⇒ `+`→`%2B`、`/`→`%2F`、`=`→`%3D`；顺序不能反（先 base64 再 urlencode）。
  直接 urlencode 原文、或用 URL-safe base64 都会搜不到。
- `intent` **必须是 `question`**（`SKILL.md:256`）；别的值会取回别的题型。
- `b` 是偏移（分页/换页用，本实现固定 0）；`urlSource` 固定 0。

### 3.2 题目详情页

`https://zujuan.xkw.com/<bankId>q<questionId>.html`

- 来源 `references/url-grammar.md:16`；skill 拼法 `scripts/lib/extract.mjs:156`。
- 实例：`/10q35583902.html`（bankId=10）。
- 缺 `bankId` 或 `questionId`、或不是纯数字 → `null`（不猜）。

### 3.3 试卷详情页

`https://zujuan.xkw.com/<bankId>p<paperId>.html`

- 来源 `references/url-grammar.md:15`；实例 `/10p3076310.html`（`SKILL.md:140`）。
- skill 里试卷链接是从卡片 `a.ques-src` 的 href **原样取得**（`scripts/paper.mjs:10`），没有默认 bankid
  ⇒ 本实现缺 `bankId` 也返回 `null`。

## 4. 检索词候选（`zujuan_keywords.dart`，移植 `scripts/keywords.mjs`）

为什么不能拿整段题干去搜（`SKILL.md` §6.2:213-242、`references/url-grammar.md:219-221`）：

- 组卷网是**字符串匹配**不是语义检索；行内公式/结构式在站点是 SVG 图片，文本层里没有这些字符。
  实测：含化学式 → 相似度 0.13~0.68、某题 0 条；只放中文 → 0.67~0.91、10 条。
- 两三个字去搜又太泛。
- 所以只取「文本层真实存在」的连续片段，按内容词密度排序，一条不中换下一条；每题 5~8 条候选。

规则（与 `keywords.mjs` 逐条对齐）：

1. **剔除** `$...$` 行内公式、`![](...)` Markdown 图片、`〔...〕` 自定义标记（站点是图片/标记）。
2. **保留**拉丁字母与数字（DNA/TdR/OD、年份在站点是正文文本）；剥掉会把相邻中文接成站点上不存在的串。
3. 标点当**分隔符**（候选不跨句读）；候选长度 4–28；首尾停用字裁掉。
4. 领域词锚定向两侧扩展；没有锚点时退回与 skill 一致的 `diverseWindows` 兜底窗口（多条滑动窗口按密度排序）。
5. 去重、互为子串只留一条、条数 ≤ `maxCandidates`（默认 8，0/负数返回空）。

保留的已知局限（**原样移植，不擅自扩展**）：`_domainWords` 只覆盖生物学科（`keywords.mjs:33-34` 注释
「其它学科可直接补词表」）。物理/化学/语文题干没有领域词锚点时走兜底窗口，候选质量依赖题干本身。
要提升非生物学科命中率，应先在标准侧扩词表，再同步本文件。

## 5. UI 接线（task-11，**已交付**，依赖 task-10 的应用层）

已落盘：`app/lib/features/questions/presentation/question_zujuan_search.dart`（204 行）+ 题目详情页插入点。

- 入口：`question_detail_page.dart:142` 在题面/配图下方渲染 `QuestionZujuanSearchButton(stem: …)`；
  key = `question-zujuan-search`；`question_zujuan_search.dart:32` 的 `questionZujuanCandidatesProvider`
  同步调 `zujuanSearchCandidates(stem)`，**候选为空时整个 widget 渲染 `SizedBox.shrink`**，不占版面。
- 底部表（`:78` `showQuestionZujuanSheet`，`showDragHandle`）列出候选关键词，只显示前 5 条
  （`questionZujuanVisibleCandidateLimit = 5`，域层最多给 8 条）。
- 每条候选两个动作：**复制检索词**（key `question-zujuan-copy-<index>`）与**打开搜索页**
  （key `question-zujuan-open-<index>`）。两者都是「写剪贴板 → 关表 → SnackBar」：
  表开着时 SnackBar 会被挡在下面，所以先关。
- **不新增依赖**（不做 url_launcher）：打开搜索页 = 把该候选的 URL 复制到剪贴板，提示去浏览器粘贴。
- 表头固定提示「组卷网按当前学科过滤：先在网站上切到对应学科，否则会搜不到」
  （`SKILL.md` 记录的实测事故：连搜 19 条全部 0 条，其实是学科不对）。
- 本仓库 `questions` 表**没有** `bankId/questionId/paperId/sourceUrl` 字段 ⇒ 现阶段 UI 只能用文本搜题链接；
  详情/试卷链接 API 已备好，等将来收题时记录来源 id 再接。

## 6. 验收证据

`flutter test test/domain/services/zujuan` → **+25 All tests passed**（exit 0，本机真实输出）。

覆盖：

- 编码：纯中文（`光合作用` → `5YWJ5ZCI5L2c55So`，与 skill 的 Node 输出逐字一致）、含空格（尾部 `=`→`%3D`）、
  base64 含 `+`→`%2B`、同时含 `+`/`/` 各就各位（不换 `-`/`_`）、拉丁数字混排、`intent=question` 与固定参数。
- 详情/试卷链接：合法纯数字 id 拼接；缺任一 id → null；空串/纯空白/非纯数字 → null；首尾空白先 trim。
- 检索词：化学/物理/语文/生物（含 DNA/OD）真实风格题干各若干例，候选与 skill CLI 输出逐条一致；
  剔除公式/图片/标记；保留拉丁字母与数字；不跨句读；长度 4–28；去重；子串折叠；截断；
  纯公式/短套话/空串 → 空；确定性（同输入同输出）。
- 候选配对：每条 `url == zujuanSearchUrl(keyword)`，顺序一致。
- UI：`flutter test test/features/questions/presentation` → **+133 All tests passed**，其中
  `question_detail_page_test.dart` 22 例覆盖「候选空不渲染 / 点开出列表 / 只显示前 5 / 复制检索词 /
  复制搜索页 URL」；`dart analyze lib test` → 92 issues 全 info、0 error 0 warning（基线）。

## 7. 未做 / 已知限制

- UI 已接线（题目详情页入口 + 底部候选表），但**真机剪贴板与浏览器粘贴未手测**；widget test 用 mock
  平台通道断言 `Clipboard.setData` 收到的内容。
- 题库原来没有来源 id 字段，详情页/试卷页链接用不上；**v26 已补**（`source_url` /
  `zujuan_question_id` / `zujuan_bank_id`），定点找题的链接与来源见 §8。仍不保存"我是否已在组卷网
  找到这道题"的人工状态。
- 不联网校验链接（避免依赖网络与登录态）；URL 规则以 skill 实测为准。
- 领域词表只有生物学科（见 §4）；跨学科候选质量不均匀。
- 站点改版/编码规则变化时，本文件与 zujuan_keywords.dart 需要按 skill 重新对齐（升级标准时同步）。
## 8. 定点找题：筛选链接 + 粘贴题面入库（轮次一百二十八）

§1–§7 做的是"从题干算检索词、给出搜索入口"。用户 m05080 问的是**定点**找题——按学科/知识点/难度/
年份/省份把范围收窄，再到站点里取题。本节记录这一轮的实现与一个硬约束：**App 不抓页面**。

### 8.1 为什么不内置抓取（实测，不是推测）

2026-10-19 本机对 `https://zujuan.xkw.com/quessearch?...` 直接发 GET（Chrome UA）：**HTTP 200，但
返回 23,670 字节的阿里云 WAF JS 挑战页**——`<textarea id="renderData">{"l1":"var arg1='5dfa5802…';"}</textarea>`、
meta `aliyun_waf_aa`、混淆脚本算出 cookie `acw_sc__v2` 后 reload。纯 HTTP 客户端（Dart `HttpClient`、
App 内 `fetch_page`）拿不到真页面；Flutter 没有 JS 引擎，桌面端也没有内置 webview。
skill 侧同样写明：HeadlessChrome 被阻断、请求过密触发 IP 级阻断、robots.txt 本身返回挑战页，
必须复用本机真实浏览器（Playwright/扩展桥）才通。再加上**答案与解析需登录、是整张 JPEG、免费账号
每日 30 道**，把抓取塞进 App 既脆弱又高成本。

⇒ 分工：**App 负责"把范围定准、把链接给对、把用户带回来的题面收进来"**；抓取与登录态留给浏览器
（现有 `zujuan-finder` 内置 skill / 扩展桥是那条路线的工具）。

**用户本人登录是完全可行的**：在浏览器里人工登录组卷网账号后，答案与解析（整张 JPEG）正常可见，
每日限额约 30 道。App 不做的是替用户维持登录态、代登录、批量下载；用户在浏览器看过之后，
把题面/答案/解析的文字粘回 App 即可入库（答案以图片形式随题保存留到后续版本）。
所以文案不要写成"拿不到答案"，要写成"答案要你自己登录看一眼"。

### 8.2 定点筛选链接：`zujuan_query.dart`

```dart
enum ZujuanSubject { chinese, math, english, physics, chemistry, biology }
ZujuanSubject? zujuanSubjectFor(String raw);        // 六英文键 / 六站点 path；其余 → null

enum ZujuanDifficulty { easy, medium, hard }        // d1 / d2 / d3
enum ZujuanSort { comprehensive, hottest, newest }  // o0 / o1 / o2

class ZujuanQuerySpec { /* subject required + 知识点/难度/题型/分类/新题/年份/省份/年级/学期/排序/页码 */ }

String zujuanFiltersOf(ZujuanQuerySpec spec);       // d→qt→fl→x→y→a→g→te→o→p
String zujuanFilteredSearchUrl(ZujuanQuerySpec spec);
String? zujuanKnowledgePointUrl({required ZujuanSubject subject, String? knowledgePointId});
```

- 学科表带三样东西：站点 path（语文 `gzyw`、数学 `gzsx`、英语 `gzyy`、物理 `gzwl`、化学 `gzhx`、
  生物 `gzsw`）、知识点**根节点 id**（23177 / 27925 / 29978 / 41934 / 43452 / 44886）、以及该学科
  自己的题型 id 表（逐学科不同，见 §3 与 skill `references/url-grammar.md`）。
- 筛选段顺序与页码位置按 skill 实测：**页码 `p` 紧跟排序段、不加斜杠**（`/a370000o1p2/`；写成
  `/a370000o1/p2/` 实测 404），第 1 页省略；非法值忽略而不是拼出坏链接；知识点 id 非法回退学科根节点。
- 省份码只收 skill 列过的 8 个（山东 370000 / 广东 440000 / 四川 510000 / 浙江 330000 / 陕西 610000 /
  北京 110000 / 重庆 500000 / 上海 310000）。**链接未联网实测**（WAF 挡着），规则来源是 skill 文档，
  接线时人工抽查一次。

验收：`flutter test test/domain/services/zujuan` 中 `zujuan_query_test.dart` 50 例（学科映射、筛选顺序、
页码、非法值回退、省份表、spec 值对象）。

### 8.3 粘贴题面解析：`zujuan_paste.dart`（纯逻辑，永不抛）

用户在浏览器复制列表卡片/详情正文，粘进 App：

```dart
List<ZujuanPastedQuestion> parseZujuanPaste(String raw);   // 空/空白 → const []
String normalizeZujuanMarkers(String raw);                  // 〔加点〕/〔波浪线〕/〔着重号〕去标记留字
```

`ZujuanPastedQuestion`：`ordinal / stem / options / answer / solution / sourceLabel / year / region /
knowledgePoints / zujuanQuestionId / zujuanBankId / sourceUrl / warnings / isPartial`。

口径：强序号（`1.`、`1、`）切题，弱序号（`(1)`）要所在段有选项/元数据等强信号且序号 ≥2 严格 +1
连续才切，否则回退空行分段（解答题小问与解析里的步骤编号不拆）；选项 A–H、必须从 A 连续、跨行续写
并入上一项（防把"A、B两点"当选项）；`【答案】【解析】【详解】【知识点】【出处】` 与 "答案：" 行内标签；
答案/解析可同行切分、多行保留；来源/年份/地区从题首括号、题干首行末尾括号、出处行三处抽，不猜；
题目 id 从 URL、`(d{1,4})q(d{3,})`、`qid=/bankid=` 三路抽，缺一个就**不拼链接**并给固定告警；
识别不出结构时整段作单题草稿（`stem`=原文、`isPartial=true`、warning 说明），**不静默丢内容**。
难度/题型只识别不落字段（当前契约没有这两个字段）。

验收：47 例 7 组。**真实卡片样本未取得**（WAF 挡着），用例形态依据 skill 的 cardText 文档；
接线后需用一张真实粘贴文本人工复核一次切分口径。

#### 8.3.1 真实页面形态加固（轮次一百二十九，task-76）

按 skill 文档里的真实页面结构（板块标题 / 试卷标题 / 题号 / 分值 / 答案 / 解析 / 图片占位 / 多选写法）
又加固了一轮，`parseZujuanPaste` 签名不变，调用方无需改：

- 新增字段 `ZujuanPastedQuestion.score`（`double?`）：只认题首/题尾括号里的「N 分」，`null` = 未识别，
  **不猜**；
- 题号新增「第 N 题」形态；选项分隔符扩到 `A.` `A．` `A、` `A：` `A)` `A）`（字母仍 A–H）；
- **切题前导合并**：`_mergePreambleBlocks`（`zujuan_paste.dart:494`）只在「首块每一行都是前导」
  （板块标题 / 试卷标题 / 考试说明 / 裸来源 / 整行括号来源）时才把它并进下一题，避免把板块标题
  当成一道题；
- **题首剥离**：`_consumeLeadingQuestionInfo`（:1049）循环剥 题号 → 整行括号来源 → 裸来源 →
  行首来源括号 → 行首分值；来源进 `sourceLabel/year/region`，分值进 `score`；
- **答案标记**：`_tryConsumeSelectedAnswer`（:1102）——题干/选项区只认**整行**的「故选：B」，
  解析区任意位置都能抽答案且解析原文保留；「故选」与 `【答案】` 冲突、`【答案】`/`【解析】` 为空
  都给中文告警；`【点睛】` 加入标签；
- **选项编号异常**（不从 A 起 / 缺号 / 重复 / 内容为空）：整行跳过 + 中文 warning + `isPartial=true`，
  不静默丢；
- 图片占位只提示不改变 `isPartial`（图片本来就要用户自己配）；
- 与旧行为差异（调用方可见）：①`【答案】` 后紧跟 `【解析】` 时旧版把解析当答案，现在答案留空 + 告警；
  ②解析区「故选」现在会填 `answer`；③板块标题/试卷标题/裸来源/题首分值不再进题干；
  ④选项编号异常行不再混进题干；⑤识别不出结构仍整段单题兜底 + 「未识别题目结构」告警（不变）。

验收：`zujuan_paste_real_samples_test.dart` **46 例 11 组**（题号 / 选项布局 / 答案解析 / 多选 /
分值 / 板块标题 / 裸来源 / 图片 / 公式 / 选项异常 / 混合长样本）；
`flutter test test/domain/services/zujuan` → `+168 All tests passed`；
`zujuan_paste_dialog_test.dart` → `+10`；
`dart analyze lib/domain/services/zujuan test/domain/services/zujuan` → `No issues found!`。
**仍未验证**：没有用真实扩展桥复制的页面原文跑过（样本按 skill 的页面结构改写）；化学式、表格、
图片 OCR 未覆盖。

### 8.4 入库装配：`zujuan_paste_import.dart` + v26 来源字段

`zujuanDraftFromPasted` / `zujuanDraftsFromPaste` 把解析结果转成 `QuestionDraft`：
`origin='zujuan'`、`state='raw'`、题干 trim 空则拒绝（批量跳过）、选项 `isCorrect=false`、
`sourceUrl` 优先用原文里的链接、没有就用 bank+question id 拼、答案/解析空白转 null；三列来源字段
随 v26 落库（见 `docs/DATA_MODEL.md` §15）。15 例测试。

### 8.5 收题页 UI（task-66，question-intake，已交付）

两个等宽入口按钮在收题表单标题行下（`question_intake_page.dart:703/:712`）：

| 入口 | 文件 | 做什么 |
|---|---|---|
| 定点找题 | `app/lib/features/questions/presentation/zujuan_pick_panel.dart` | 底部表：学科 / 知识点 id / 难度 / 年份 / 省份 / 年级 / 排序 → **实时拼 URL**（`zujuanPickUrlFor`）→ SelectableText 显示 → 「复制链接」写剪贴板、关表、SnackBar |
| 粘贴组卷网题面 | `app/lib/features/questions/presentation/zujuan_paste_dialog.dart` | 粘贴文本 → `parseZujuanPaste` → 可改题干、可取消勾选 → 逐条 `ingest` → 汇总 saved / duplicates / failed；单条异常不中断 |

- 面板的学科默认值取题库当前学科（`zujuanPickDefaultSubject`），学科不对时回退数学；
  知识点 id、省份码非法时**不拼坏链接**，字段留空即不加筛选段。
- 文案按 §8.1 口径：面板明写"App 不抓页面；要看答案与解析，得你自己在浏览器登录组卷网
  （免费账号每天约 30 道），把看到的题面/答案解析粘回来"；粘贴对话框还有一行同样的登录提示小字
  （`zujuanPickNoScrapeHint` / `zujuanPickLoginHint` / `zujuanPasteLoginHint`）。
- l10n 五文件手改（未跑 gen-l10n）：`zujuanPick*` 21 个 + `zujuanPaste*` 18 个 = 39 个 key。
- 粘贴对话框里 `ingest` 返回 `created:false` 计为"重复"（题干指纹命中），不计失败。

测试：`zujuan_pick_panel_test.dart` 11 例（6 纯逻辑 + 5 交互，含剪贴板平台通道断言）、
`zujuan_paste_dialog_test.dart` 10 例（1 纯逻辑 + 9 widget：取消勾选 / 改题干 / 重复 / partial /
异常不中断 / 关闭不写库）、收题页入口 2 例。

### 8.6 这一轮的验收证据

- `flutter test test/domain/services/zujuan` → +122 All tests passed（link 19 + query 50 + paste 47 等）；
- `flutter test test/features/questions/application/zujuan_paste_import_test.dart` → +15；
- `flutter test test/data/database/v26_migration_test.dart` → +3；
- `flutter test --concurrency=1 test/features/questions/presentation` → +272 All tests passed
  （基线 249 + 定点面板/粘贴对话框/入口 23）；
- `dart analyze lib test` → 92 issues / 0 error / 0 warning。

### 8.7 未做 / 已知限制

- 真实粘贴样本、筛选链接的联网可达性都未人工验证（WAF）；答案与解析（JPEG）不自动下载，
  需要用户自己登录查看后把文字补进来（后续版本可加"答案截图随题保存"）。
- 知识点列表只解析、不入库（`QuestionDraft` 没有知识点字段，题目与知识点目前靠标签/相似题，不靠外键）。
- 难度、题型、专题字段解析后丢弃；若要保留需先扩`ZujuanPastedQuestion` 契约与表列。
- 不保存"是否已在组卷网找到这道题"的人工状态；不做答案图片下载、不做登录态。

## 9. 整卷页对照题库（轮次一百三十三）

用户场景：浏览器里打开组卷网一套卷的详情页（`/<bank>p<paper>.html`，例 `/10p3076310.html`），
想知道"这页里哪几道我题库里还没有"。这一轮把"整卷页 → 题号清单 → 与题库对照 → 缺题链接"
接起来，纯本地、纯只读：不联网、不抓页面、不写库。

### 9.1 抽取（已有，轮次一百三十二）

NaN``
lib/domain/services/zujuan/zujuan_paper_extract.dart
NaN``

的 `parseZujuanPaperText(raw)`：粘整页 HTML 或纯文本都能认（`/<bank>q<id>.html` 与 `/q<id>.html`
两种形状），抽出 `paperId`/`bankId`/`title`/按出现顺序去重后的 `questionIds`（上限 200，超出
NaNtruncated=true` 并给 warning）/`questionLinks`（可能比 ids 短：没有 bankId 时生成不出）。
永不抛异常；空输入返回空结果。这一层已在轮次一百三十二交付，本轮只消费它。

### 9.2 数据层：按组卷网 questionid 批量查题

NaNQuestionRepository.byZujuanQuestionIds(Set<String>)`：

- 输入空集合、或全部 trim 后为空 → 空 map，不查库；
- `where zujuan_question_id IN (...)`；同一组卷网 id 可能有多行（历史重复入库，库上
  没有唯一约束），顺序固定为 **`updatedAt` 降序、`id` 升序**，调用方取第一行当"最新一行"；
- 匹配口径是 trim 后**精确相等**，不做大小写/前导零归一——归一属于解析层，数据层只认
  库里存的字符串。

### 9.3 应用层：loadZujuanPaperProgress

NaN``dart
Future<ZujuanPaperProgress> loadZujuanPaperProgress({
  required QuestionRepository repository,
  required ZujuanPaperExtract extract,
});
NaN``

- 位置：`lib/features/questions/application/zujuan_paper_progress.dart`。
- 抽取为空（一个题号都没抽到）→ 直接返回空结果，**不查库**；界面因此能区分"没认出"
  与"认出了但全缺"。
- 命中顺序 = 试卷页题目出现顺序（不按题号、不按入库时间）；同一题号多行只保留最新一行。
- `ZujuanPaperMatchedQuestion{zujuanQuestionId, questionId, serialLabel, stemPreview, sourceUrl}`：
  `serialLabel` = `TR-00001`，没编号时 `TR-未编号`；`stemPreview` = 题干压空白后前 60 个
  Unicode 码点，截断时末尾带省略号。
- `ZujuanPaperProgress`：`matched` / `missingQuestionIds` / `missingLinks`（用 `extract.bankId`
  逐 id 调 `zujuanQuestionDetailUrl` 生成；没有 bankId 时为空列表，长度可小于缺题数）/
  `questionCount` / `matchedCount` / `missingCount` / `isEmpty` / `hasMissingLinks` /
  `missingLinksText`（一行一个，可直接进剪贴板）/ `warnings` / `truncated` 透传。
- 这一层不联网、不写库；为什么不在 UI 里拼：缺题清单还要给 AI 工具
  `read_zujuan_paper` 用，两处口径必须一致。

### 9.4 验收证据（本轮已完成部分）

- `flutter test test/data/repositories/question_repository_zujuan_ids_test.dart test/features/questions/application/zujuan_paper_progress_test.dart --concurrency=1`
  → **+20 All tests passed**（仓库 8 例 + 应用层 12 例）；

### 9.5 未做（本轮或后续）

- 组卷网页面本身不抓取（WAF，见 §8.1）：整页内容要用户自己复制粘进来。
- 缺题链接只给"去打开"的 URL，不在 App 内打开浏览器（没有 url_launcher）。
- 答案/解析图片不自动下载，仍要用户登录后自己看（见 §8.1 结尾口径）。

## 10. 题源链接的输入解析（轮次一百三十三，task-89）

给「题目详情页改原题链接」用的域层解析：`parseZujuanSourceInput(String raw)` →
NaNZujuanSourceInput{sourceUrl?, zujuanQuestionId?, zujuanBankId?, isEmpty, toJson}`；认不出返回 null，永不抛。
位置：`lib/domain/services/zujuan/zujuan_source_input.dart`。

接受的输入形态（口径与拒绝理由）：

1. **完整 http(s) URL**：先交给 `questionSourceFor`（`question_source.dart`）规范化——去 fragment、
   去默认端口、scheme/host 小写、path/query 逐字节保留、不升降级、拒绝 `javascript:`/`data:` 等。
   规范化后再看 path 是否命中 `(?<![0-9A-Za-z_])(?:([0-9]{1,6}))?q([0-9]{1,12})\.html`。
   **只有 host 命中组卷网**（`zujuan.xkw.com` 或 `*.zujuan.xkw.com`，口径同 `question_source.dart` 的
   `isZujuan`）才抽两个 id；别的站一律只收 `sourceUrl`、id 留 null——`zujuanQuestionId` 的语义
   是"组卷网原题 id"，在别站路径里捡到 `10q5.html` 就填进去等于猜。
2. **裸路径/文件名**：`/10q35583902.html`、`10q35583902.html`、`q35583902.html`（大小写不敏感）——
   用 `zujuanQuestionDetailUrl` 重建标准链接；缺 bank 时 `sourceUrl=null`、只填题号。
3. **别的站的绝对 URL**：只给 `sourceUrl`（链接可信但不知道组卷网 id）。
4. 纯数字、只有 bank、`javascript:`/`data:`/`file:`/`mailto:`/`ftp:`、相对普通路径、随机文字 → **null**（不猜）。

已知边界（都有测试固定）：

- 裸路径只认"整串就是文件名/路径形状"；`/foo/10q123.html`、`10q35583902.html?x=1`、末尾多一段的都不认。
  从浏览器地址栏粘来的带目录路径目前认不出，属已知限制。
- id 位数字段原样保留：不剥前导零、不补零（`0042` 就是 `0042`，与数据层精确匹配口径一致）。
- path 不做百分号解码：`/%31%30q5.html` 会在字面串上命中而得到 bank=`30`、qid=`5`；
  这是"不改写用户粘贴的 URL"的直接结果，真实场景罕见，暂不处理。
- URL 里的 query 保留（有的站用 query 记来源），fragment 去掉。

验收：`flutter test test/domain/services/zujuan --concurrency=1` → **+252 All tests passed**
（既有 212 + 本层 40：完整 URL 10 / 路径形状 11 / 别的站 5 / 拒绝 3 / 值对象 7 / 不抛与确定性 4）；
`dart analyze lib/domain/services/zujuan test/domain/services/zujuan` → No issues found。

## 11. 整卷对照的界面与 AI 工具（轮次一百三十三，task-90 / task-91）

§9 的数据/应用层被两条入口直接消费，口径完全一致（同一个 `loadZujuanPaperProgress`）：

- **AI 工具 `read_zujuan_paper`**（第 27 个工具）：参数 `text` + `max_count`（默认 50、上限 200），
  只读、不联网；结果 `rule='library_only'`、count 三件、`truncated`、`warnings`、
  `matched`（4 键，无 source_url）、`missing`（逐 id 重算 link）、`missing_omitted`。
  摘要明确「只读题库，不会去组卷网抓页面」——这条是刻意的能力边界说明，模型不应暗示能上网补题。
- **收题页「整卷对照」对话框**：第三个入口 → 粘贴 → 统计行 + 已收录 + 缺题 + 复制缺题链接；
  空白/认不出只显示空态且不查库；无 `bankId` 时缺题行标「（无链接）」并说明原因、复制禁用。
  l10n 18 个 `zujuanPaper*` key（zh/en）。测试 +11 + 1 入口，presentation 目录 +310 全绿。

- **详情页「原题链接」编辑**（§10 的解析器在这里落地，task-92）：来源行「改原题链接」/ 无来源时的「添加原题链接」→
  对话框三字段实时预览 → 保存 `updateSourceLinks`（null=不动，别站 URL 不冲掉旧 id）→ 清空需二次确认。

未做：批量补录缺失题（仍逐题走粘贴题面 / 定点找题）、真实整页文本端到端手测、窄屏三按钮换行、真机软键盘遮挡未验。

