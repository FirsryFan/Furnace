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
- 题库没有来源 id 字段，详情页/试卷页链接暂时用不上；也不保存"我是否已在组卷网找到这道题"。
- 不联网校验链接（避免依赖网络与登录态）；URL 规则以 skill 实测为准。
- 领域词表只有生物学科（见 §4）；跨学科候选质量不均匀。
- 站点改版/编码规则变化时，本文件与 zujuan_keywords.dart 需要按 skill 重新对齐（升级标准时同步）。
