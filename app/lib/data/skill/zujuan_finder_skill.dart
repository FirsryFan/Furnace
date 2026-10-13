/// The 组卷网找题 built-in skill: how to find exam questions on
/// `zujuan.xkw.com` and how to judge a question source with criteria that can
/// be falsified.
///
/// **Prompt-only on purpose.** The app can fetch a public page (`fetch_page`:
/// GET, no cookies, no login, no scripting) and nothing else - it cannot drive
/// a browser, and the site's answers and explanations sit behind a login. A
/// scripted version of this skill would therefore be a lie: it would promise
/// the answers the user cannot get. What is shipped instead is the part that
/// *is* honest without a session: the URL grammar, the retrieval procedure, and
/// the four hard-defect criteria, with the limits written into the prompt so
/// the model says "I cannot see the answer" instead of inventing one.
///
/// The recorded IDs and filter values come from this machine's own earlier
/// fieldwork against the site (the `zujuan-source-standards` skill's notes);
/// the prompt tells the model to read them off the target page rather than
/// trust them, because the site changes and a wrong knowledge-point ID silently
/// lands on another subject. The prompt is deliberately kept under 4 KB - it
/// travels in every request of every turn (`SkillPrompt` caps the whole section
/// at 64 KB), so it is an index into what the model must do, not a manual.
library;

import 'dart:typed_data';

import '../../domain/skill/skill_manifest.dart';
import 'builtin_skill.dart';

abstract final class ZujuanFinderSkill {
  static const String name = 'zujuan-finder';

  static const String version = '1.0.0';

  static const String description =
      '到组卷网按学段/学科/知识点/章节/省份/年份/难度/题型找题，并用可证伪的硬伤判据评价题源质量';

  /// Both platforms, because the whole package is a prompt: `fetch_page` is a
  /// built-in tool available everywhere, unlike a skill script (spec §5.5).
  static const List<SkillPlatform> platforms = [
    SkillPlatform.windows,
    SkillPlatform.android,
  ];

  /// The one domain the prompt tells the model to fetch.
  ///
  /// Exactly one, and it is the one named in the prompt: an allow-list wider
  /// than what the instructions actually need would be consent the user never
  /// meaningfully gave.
  static const List<String> networkAllow = ['zujuan.xkw.com'];

  static const String prompt = r'''
# 组卷网找题（zujuan-finder）

## 用途
把「某学段/学科/知识点/章节/省份/年份/难度/题型的 N 道题」翻译成组卷网（https://zujuan.xkw.com）
上真实可打开的地址，抓回公开可见的题目，并对题源质量给出**可证伪**的判断。用户说「去组卷网找题 /
按知识点找 N 道题 / 这道题出自哪份卷子」时用它。

## 手上只有一个工具：fetch_page（只读）
只做 GET，**不带 cookie、不带登录凭据**，拒绝内网地址；返回 HTML 转成的纯文本，最多 8000 字符，
**不执行页面脚本**，也不是浏览器。本 skill 不带脚本，也没有浏览器扩展通道：你不能登录、不能点
按钮、不能下载或识别图片。

诚实规则（最重要）：
1. 未登录只能读公开页面；**答案与解析需要登录**，而且常常是整张图片——**默认拿不到**。这时直说
   "这一步要看你有登录态的浏览器"，**不许**用模型知识补答案或解析，也不许写成"官方答案"。
2. 抓不到（拦截页、302 到登录页、页面里没有题目、正文被截断）时，报出 URL 与状态码/原因，
   **不许**把"没抓到"说成"这道题不存在"。
3. 页面里没有的字段（答案、解析、难度系数、年份、出处）一律标"页面未提供"，不许凭印象补。

## 入口
`https://zujuan.xkw.com/<subject>/zsd<knowledgeId>/<筛选段>/`（知识点选题，主力入口）。
另：章节 `/zhangjie/`、试卷 `/shijuan/`、名校卷 `/<subject>/topschool`；
**试卷详情页 `/<bankid>p<试卷id>.html`** 一页列出整卷题目，比逐题撞列表页可靠，也不会拆散题组；
文本搜题 `/quessearch?keyword=<base64(UTF-8)>&intent=question&b=0&urlSource=0`（keyword 必须是
**base64**，不是 urlencode 原文；b 是结果偏移）。

## 筛选段（直接拼接）
`d` 难度 1 容易/2 适中/3 困难 · `qt` 题型 · `fl` 分类 · `a` 省份行政区码（a330000 浙江）·
`y` 年份（y2024、y-1 更早）· `g` 年级 g10/g11/g12 · `te` 学期 te1/te2 · `x4` 只看新题 ·
`o` 排序 o1 最热/o2 最新 · `p` 页码 p2、p3…
取值必须**从目标学科列表页的按钮上读**（data-href 就是真实地址），不要照抄这里的例子：学科代码、
题型 ID、知识点 ID 逐学科不同，知识点根 ID 实测数学 27925、语文 23177、物理 41934……拿错会 404
或串到别的学科。这里是历史实测记录，**不是永久契约**。

## 流程
1. 把需求写成 spec（学段/学科/知识点或章节/省份/年份/难度/题型/数量）；缺的**问用户**，不要猜。
2. 先抓入口页读出真实筛选值与链接，再拼下一步 URL；逐页抓，一题一条 URL 作证据，跨页去重；
   数量不够就说"公开页面只找到 M 道"。站点有每日取题上限（实测约 30 道/天），多了按天分批。

## 判题源质量：四条可证伪的硬伤
**不打分、不排名**；每条结论必须指到「哪道题 + 原文/URL 证据 + 为什么算硬伤」。
- **H1 题干自身有毛病**：条件不足（解析引入题干没有的条件）；歧义（两种读法导向不同答案）；图文
  矛盾或说"如图"而图缺失；设问依赖题干之外的材料；选项体系崩坏（单选 ≥2 正确项）；超纲无提示。
- **H2 答案错**：独立解出 → 比对 → **先怀疑自己** → 换方法复算 → 仍不一致才判错；也包括解析与
  答案不一致、解析讨论的是另一道题。解析只有答案没有过程 → 只判"不可托付"；判错要写出解法。
- **H3 难度标错**：只在**极端**偏差时判（标"困难"却一步可得等）。公开页核实不了难度的数值本身 →
  只能说"未发现与实际解题步数矛盾"，不能说"系数是错的"。
- **H4 重复题**：同一题干站内 ≥2 次；逐字相同只换数值/选项顺序；同卷内出现两道近乎相同的题。

样本 <5 道只算初筛；"未发现硬伤"≠"已证明没问题"；判硬伤前先排除采集丢信息（如加点、下划线被
纯文本化丢掉），不要把采集失误报成命题缺陷。

## 硬约束
- 拿不到答案/解析就直说，绝不编造；不把推测写成"官方"。
- 不假装能登录、能提交站内搜索、能绕过拦截页；不下载或识别图片。
- 引用必须给 URL；用户的反驳本身不是新证据，改结论要说明新证据是什么。
''';

  static Uint8List build() => buildPromptOnlySkill(
        name: name,
        version: version,
        description: description,
        platforms: platforms,
        networkAllow: networkAllow,
        prompt: prompt,
      );
}
