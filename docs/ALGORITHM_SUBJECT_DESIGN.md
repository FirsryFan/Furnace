# 算法竞赛学科（algorithm）接入设计（2026-11-06）

> 状态：**已落数据**（真实库 17 题 + 25 个标签，导入 0 失败 0 遗漏）；代码接线完成；
> **不接在线评测**。本文所有数字都来自本机真实命令输出，证据文件见 §10。

## 0. 一句话

Furnace 题库新增学科 `subject_key = algorithm`（中文名「算法竞赛」），题源为洛谷公开题目页
（https://www.luogu.com.cn/），难度范围「提高 ~ 省选/NOI-」。首批落 **17 道真实 OI 题**
（题意 / 输入输出 / 样例 / 解析要点 / 本项目自写并样例自测的 C++17 参考代码），
并建 **算法竞赛 / 专题 + 能力 + 难度** 标签树（25 个标签）。OI 题整题**不适合**做闪存卡，
适合拆成「算法模板 / 复杂度 / 边界 / 常见错误 / 小技巧」卡片；题目本体进题库与题单。

## 1. 学科定义与边界

| 项 | 值 |
| --- | --- |
| 学科 key | `algorithm`（稳定、ASCII，落库到 questions.subject_key） |
| 中文名 | 算法竞赛（显示名映射见 §7） |
| 题源 | 洛谷 www.luogu.com.cn（公开题目页；保留题号、链接、难度、算法标签） |
| 难度范围 | 洛谷难度 5（提高+/省选-）~ 6（省选/NOI-）为主，另含 2 道 4（提高）作为热身；换算到题库 1–10 刻度见 §3 |
| 数据形式 | `.tqb` 题库包（Furnace 现有契约，text_format=markdown） |
| 在线评测 | **不接**：不登录、不提交、不抓提交记录/榜单；只取题面与元数据 |
| 参考代码 | 本项目自写 C++17，用 MSVC 19.44 编译并对洛谷公开样例逐条比对；**未在洛谷提交** |

题面版权归原出题方与洛谷所有：本数据仅供用户本机个人学习使用，**不做二次分发**；
`.tqb` 里保留每题洛谷链接作为出处。参考代码为自写，不是从题解区复制的。

## 2. 首批题目（17 道，全部真实抓取）

抓取时间：2026-11-06（Asia/Shanghai）；方式：DSH `web_fetch` 逐题请求洛谷题目页，
解析页面内 SSR JSON（script#lentille-context）中的题面/难度/算法标签/样例；
共 17 个题目页，17 次请求（低频、无并发压站）。

| # | 洛谷题号 | 题目 | 洛谷难度 | 主专题 | 能力点 | 参考代码 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | P1120 | [CERC 1995] 小木棍 | 提高+ | 搜索 | A3/A4/A10 | solutions/P1120.cpp |
| 2 | P1494 | [国家集训队] 小 Z 的袜子 | 提高+ | 数据结构 | A4/A5 | solutions/P1494.cpp |
| 3 | P1967 | [NOIP 2013 提高组] 货车运输 | 提高+ | 图论 | A3/A4/A5 | solutions/P1967.cpp |
| 4 | P2261 | [CQOI2007] 余数求和 | 提高 | 数学 | A5 | solutions/P2261.cpp |
| 5 | P2324 | [SCOI2005] 骑士精神 | 提高+ | 搜索 | A3/A4/A10 | solutions/P2324.cpp |
| 6 | P2467 | [SDOI2010] 地精部落 | 提高+ | 动态规划 | A4/A5/A10 | solutions/P2467.cpp |
| 7 | P2572 | [SCOI2010] 序列操作 | 提高+ | 数据结构 | A4/A5/A10 | solutions/P2572.cpp |
| 8 | P2746 | [IOI 1996 / USACO5.3] 校园网 | 提高 | 图论 | A3/A4 | solutions/P2746.cpp |
| 9 | P3225 | [ICPC 2011 WF / HNOI2012] 矿场搭建 | 提高+ | 图论 | A3/A4/A10 | solutions/P3225.cpp |
| 10 | P3287 | [SCOI2014] 方伯伯的玉米田 | 省选+ | 动态规划/数据结构 | A3/A4/A5 | solutions/P3287.cpp |
| 11 | P3369 | 【模板】普通平衡树 | 省选+ | 数据结构 | A4/A5/A10 | solutions/P3369.cpp |
| 12 | P3808 | AC 自动机（简单版） | 省选+ | 字符串 | A4/A5/A10 | solutions/P3808.cpp |
| 13 | P3868 | [TJOI2009] 猜数字 | 提高+ | 数学 | A3/A5 | solutions/P3868.cpp |
| 14 | P4053 | [JSOI2007] 建筑抢修 | 提高+ | 贪心 | A3/A10 | solutions/P4053.cpp |
| 15 | P4170 | [CQOI2007] 涂色 | 省选+ | 动态规划 | A4/A5/A10 | solutions/P4170.cpp |
| 16 | P5022 | [NOIP 2018 提高组] 旅行 | 提高+ | 图论/搜索 | A3/A4 | solutions/P5022.cpp |
| 17 | P5410 | 【模板】扩展 KMP / exKMP（Z 函数） | 省选+ | 字符串 | A4/A5 | solutions/P5410.cpp |

覆盖：动态规划 3、图论 4、数据结构 3、数学 2、字符串 2、搜索 2、贪心 1。
**构造专题本批 0 题，标注「待补」**（没有拿难度不符的题凑数；下一批按洛谷难度 5–6 + 构造标签补 2–3 题）。

## 3. 难度映射

| 洛谷 difficulty | 洛谷文案 | 题库 difficulty（1–10） | 标签树「难度」节点 |
| --- | --- | --- | --- |
| 4 | 普及+/提高 | 7 | 算法竞赛/难度/提高 |
| 5 | 提高+/省选- | 8 | 算法竞赛/难度/提高+ |
| 6 | 省选/NOI- | 9 | 算法竞赛/难度/省选+ |

本批分布：7 分 2 道、8 分 10 道、9 分 5 道（真实库回读值见 §10）。
`difficulty_source = manual`，`source_label` 保留「洛谷 Pxxxx（原始难度文案）」，可人工核对。

## 4. 标签树设计

```text
算法竞赛
├── 专题
│   ├── 动态规划   ├── 图论      ├── 数据结构   ├── 数学
│   ├── 字符串     ├── 搜索      ├── 贪心      └── 构造（待补）
├── 能力
│   ├── 语言解码（A1）      ├── 信息定位与提取（A2）  ├── 逻辑与论证（A3）
│   ├── 结构化建模（A4）    ├── 计算与估算（A5）      ├── 图表与图像（A6）
│   ├── 转化与等价（A7）    ├── 实验与证据设计（A8）  ├── 表达与压缩（A9）
│   └── 自我监控（A10）
└── 难度
    ├── 提高   ├── 提高+   └── 省选+
```

- 落库方式：`test/live/algorithm_subject_seed_live_test.dart` 读 `data/algorithm-tags.json`，用 `TagRepository.createTag` 按路径幂等创建（已存在则复用），再导入 `.tqb`。
- 与现有标签树的关系：**只新增根标签「算法竞赛」**，不修改文化课根（化学/数学/物理/生物/英语/语文/能力）和既有 416 个标签；真实库标签 416 → 441（+25），见 §10 回读。
- 卡片归组：闪存卡系统里「卡组 = 标签子树」，所以以后算法竞赛的闪卡直接挂 `算法竞赛/专题/...` 即可；题目与知识点也复用同一棵标签树（object_tags）。

## 5. 数据格式（.tqb 记录字段）

每道题在 `questions.json` 里是一条现有契约的 `QuestionPackRecord`（与其它学科完全同构）：

| 字段 | 本批取值 |
| --- | --- |
| `stem` | Markdown：题号+题目名 / 来源行（洛谷链接、难度、算法标签）/ 题目背景 / 题目描述 / 输入格式 / 输出格式 / 样例 / 说明提示；离线不可加载的题面图片替换为「（图见洛谷原题页面）」 |
| `answer` | 「本题为编程题：完整参考实现、复杂度与常见错误见解析。」（OI 题没有唯一文字答案） |
| `solution` | 解析要点（思路/关键点/复杂度/边界与常见错误）+ C++17 参考代码 + 样例自测声明 |
| `subject_key` | `algorithm` |
| `question_type` | `solution`（编程题按大题处理） |
| `source_level` | `unknown`（现有来源词表没有「竞赛真题」档；见 §11 剩余问题） |
| `source_label` | 「洛谷 Pxxxx 题名（洛谷难度）」 |
| `source_url` | 真实洛谷题目链接 |
| `difficulty` / `difficulty_source` | 7–9 / `manual` |
| `trap_note` | 每题一条真实易错点（从参考实现与题面推导） |
| `origin` / `state` | `furnace` / `structured` |
| `text_format` | `markdown` |
| `capability` | A1–A10 子集（JSON 数组） |
| `tag_paths` | 算法竞赛 + 专题 + 难度 + 能力路径（如 `算法竞赛/专题/动态规划`） |
| `media` | 空（算法题无配图；不伪造图片） |
| `title` | 包内不携带；导入后由 seed 脚本用 `suggestQuestionTitle` 回填默认名 |

包清单：`format=furnace-question-bank, version=1, question_count=17, media_count=0, app_version=0.6.16+36, generated_by=Furnace-algorithm-seed/1.0`。

## 6. OI 题是否适合做闪存卡？——结论与设计

**结论（与 Lead 判断一致）：完整 OI 题不适合直接做闪存卡；适合拆成原子卡片，题本体进题库/题单。**

理由（5 个维度）：

1. **原子性差**：一道 OI 题包含读题、建模、选择算法、实现、调边界多个阶段，一张卡塞不下；复习时无法判断「我是哪一步不会」。
2. **可判定性低**：闪存卡的回收依赖「对/错」可判定；OI 题的正确性只由完整程序在隐藏数据上体现，卡片上写「会/不会」是主观的，无法形成可靠复习信号。
3. **单次复习成本高**：提高+/省选- 题平均需要 30 分钟以上，而闪存卡的设计前提是几秒到几十秒一次；整题进复习队列会拖垮每日节奏。
4. **记忆目标不同**：闪存卡适合记「模板 / 结论 / 边界 / 易错点」这类稳定、可复述的知识；OI 题练的是「在陌生题面下组合这些知识」的迁移能力，应通过「做题 + 对照单」训练。
5. **干扰成本**：整题卡片会稀释卡组里的模板卡与边界卡，让真正该背的原子知识被淹没。

**推荐拆分（每类给 1 个真实例子，均来自本批题）：**

| 卡片类型 | 内容形态 | 本批例子 |
| --- | --- | --- |
| 算法模板卡 | 填空/选择：模板关键式子或适用条件 | 树状数组 lowbit / Treap split 的期望复杂度（P3369） |
| 复杂度卡 | 选择：时间/空间复杂度与数据范围匹配 | P3808：AC 自动机 O(总模式串长 + 文本长 + 26×节点数) |
| 边界卡 | 填空：特殊输入/取模/多测清空/溢出 | P3868：输入顺序是 a 后 b；a 可能为负要先归一 |
| 常见错误卡 | 选择：错因判断 | P3225：割点标记必须在 Tarjan 全部结束后再统计 BCC 的割点数 |
| 小技巧卡 | 填空：可迁移的动作 | P1494：莫队按左端点分块、块内右端点奇偶排序；P3287：二维前缀最大值用二维树状数组 |

**接入方式（现有系统，不新增表结构）**：闪存卡没有 `subjectKey` 字段，卡组由标签树决定；本批已把「算法竞赛/专题/…」标签树落库，因此：
- 以后用 `create_knowledge_cards`（AI）或手动建卡时，把卡的标签路径设为 `算法竞赛/专题/动态规划` 等即可进入对应卡组；
- 题目的 `tag_paths` 与之相同，题目/知识点/卡片三者共用一棵树（`object_tags`）；
- 卡片 `references` 建议写洛谷题号（如「洛谷 P3868 参考解的边界部分」），保持「一张卡一个可核对来源」；
- 本轮**没有批量生成**算法闪卡（避免 AI 无来源编造模板细节）；建议后续由用户/AI 按上表逐批生成，并用真实题目的参考代码校对。

## 7. 代码改动清单（只动算法学科相关文件）

| 文件 | 改动 |
| --- | --- |
| app/lib/domain/services/reasoning/capability_action.dart | `CapabilityAction.subjectKeys` 追加 `algorithm`，`subjectLabelsZh` 追加「算法竞赛」；注释从「八个轨道」更新为「九个轨道」。该词表同时被收题页学科下拉、能力词表页、题库包导出筛选、组卷学科过滤使用，这一处即接通多条入口。 |
| app/lib/domain/services/questions/question_title_suggestion.dart | 题名建议的学科中文名表补 `algorithm → 算法竞赛`（题库自动命名会生成「算法竞赛 · Pxxxx …」）。 |
| app/lib/features/ai/tools/question_write_tools.dart | `create_questions` 工具的 `subject_key` 说明补 `algorithm（算法竞赛）`，让 AI 收题时能把算法题标进新学科（不填仍回退 other）。 |
| app/lib/domain/services/zujuan/zujuan_query.dart | 文件头说明补充：`algorithm` 在组卷网没有对应学科，解析返回 null；算法竞赛不走组卷网。 |
| app/lib/features/questions/application/paper_generator_service.dart | 类注释补充「算法竞赛不进入 AI 题单生成器」的原因（该生成器要求题干截图+答案截图；算法题无图；见 §11）。组卷 PaperComposer 按 `subjectKey` 动态过滤，自动支持 algorithm。 |
| app/test/live/algorithm_subject_seed_live_test.dart（新增） | 真实库落库脚本（幂等）：备份整库 → 建标签树 → 导入 .tqb → 回填默认题名 → 回读校验。默认 flutter test 时跳过。 |
| app/test/domain/services/questions/algorithm_subject_test.dart（新增） | 学科轨道/题名/题包筛选/编解码往返的守卫测试（4 个 test）。 |
| docs/ALGORITHM_SUBJECT_DESIGN.md（新增） | 本文。 |

**没有改动**：题单内容渲染器（`paper_docx.dart` / `paper_composer.dart` / markdown 渲染）、l10n/ARB、schema 生成文件（database.g.dart 等）、其它学科的题库数据。

## 8. 兼容性

- `subjectKeys` 是追加，既有动作的 `subjectHints` 与 `transferable` 完全未改（`capability_action_test` 的 20 个种子动作与排序规则测试继续通过）。
- 真实库回读：导入前后文化课题数完全不变（math 354 / physics 132 / chinese 96 / english 21 / chemistry 21 / biology 11 / 空学科 1），只有 algorithm +17、tags +25。
- `.tqb` 契约未改：还是 zip + manifest.json + questions.json + media；算法题只是 `subject_key` 不同、`media` 为空、`text_format=markdown`。

## 9. 使用方式

```bash
# 1) 复跑参考代码样例（MSVC）
python 10-projects/algorithm-subject/scripts/run_samples.py

# 2) 重建数据与包
python 10-projects/algorithm-subject/scripts/build_dataset.py
python 10-projects/algorithm-subject/scripts/build_pack.py

# 3) 校验包
cd E:/Projects/Furnace/app
dart run tool/tqb_verify.dart "E:/Workspaces/Furnace/10-projects/algorithm-subject/packages/Furnace-algorithm-2026-11-06.tqb"
dart run tool/question_pack_probe.dart "E:/Workspaces/Furnace/10-projects/algorithm-subject/packages/Furnace-algorithm-2026-11-06.tqb"

# 4) 导入真实库（幂等；会先备份整库与现有题库）
RUN_ALGORITHM_SEED=1 flutter test test/live/algorithm_subject_seed_live_test.dart
```

在 App 里：题库页学科筛选会出现「算法竞赛」；收题页学科下拉可选「算法竞赛」；标签页有「算法竞赛」根标签（专题/能力/难度三层）；导出/组卷的学科过滤同样可见该学科。
**注意**：AI 题单生成器（6 题题单）不会选到算法题（见 §11）。

## 10. 验证命令与真实输出（2026-11-06）

```text
# 参考代码：MSVC 编译 + 官方样例比对
$ python scripts/run_samples.py
TOTAL 17 PASS 17 FAIL 0

# 包解码（产品仓库 tool/tqb_verify.dart）
manifest format=furnace-question-bank version=1 questions=17 media=0 app=0.6.16+36
decoded records=17 mediaBytes=0
[17 条均为 subject=algorithm question_type=solution]
OK

# 包探针（tool/question_pack_probe.dart）
actual_question_count=17, subjects={"algorithm":17}, source_levels={"unknown":17},
with_source_url=17, with_difficulty=17, with_solution_text=17, with_trap_note=17,
duplicate_stem_groups=0, alerts=[], reencode_record_equal=true

# 真实库导入（第一次）
DB_BACKUP=E:\Workspaces\Furnace\00-inbox\algorithm-subject\backup\furnace-before-algorithm-2026-11-06T010239-640580.db
TAGS created=25 existing=0 under_algorithm=25
PACK questions=17 media=0
IMPORT created=17 updated=0 skipped=0 media=0 warnings= failures=
BANK_BACKUP=E:/Furnace/data\documents\question_pack_backups\题库备份-20261106-010240-170.tqb
VERIFY algorithm_questions=17 algorithm_tags=25
00:46 +1: All tests passed!

# 真实库再次导入（幂等验证）
TAGS created=0 existing=25
IMPORT created=0 updated=0 skipped=17
TITLE_BACKFILL updated=17
VERIFY titles=[算法竞赛 · P1120 [CERC 1995] 小木棍, 算法竞赛 · P1494 [国家集训队] 小 Z 的袜子, ...]
00:30 +1: All tests passed!

# 真实库回读（只读副本，verify-after-import.json）
subjects: math354 / physics132 / chinese96 / english21 / chemistry21 / algorithm17 / biology11 / 空1
total_questions=653, total_tags=441
algorithm difficulty: 7→2, 8→10, 9→5；text_format=markdown 17/17；source_url 洛谷 17/17
question_tag_links=96（17 道题与算法竞赛子树标签的 object_tags 行数）

# 单测（flutter test，5 个文件）
algorithm_subject_test + capability_action_test + question_title_suggestion_test
+ question_pack_selection_test + question_pack_codec_test
→ +145: All tests passed!

# 静态检查
dart format <改动文件> → 0 changed
dart analyze <改动文件> → No issues found!
```

## 11. 剩余问题与未做项

1. **不接在线评测**（本任务明确范围）：没有提交、判题、榜单、提交记录同步；以后若要接，需另立安全与网络边界。
2. **构造专题待补**：本批没有难度 5–6 的构造题，标签树节点保留为「待补」，不拿难度不符的题凑数。
3. **来源等级词表**：现有 `source_level` 词表（gaokao / provincial_diagnostic / elite_school / school / personal / unknown）没有「竞赛真题」档，本批用 `unknown` 并在 source_label 写洛谷难度；建议后续加 `oi_problem` 档并补 UI 文案（会涉及题库筛选/质量报告，本轮未改）。
4. **AI 题单生成器不含 algorithm**：`paper_generator_service.dart` 的 4 科是「视觉+题图」路径，每道题要求题干截图与答案截图（`_pickQuestions` 跳过没有配图的题）；算法题无图，若加入该列表会直接报「题库里可用的题不足」。算法题走题库筛选 / PaperComposer 组卷 / .tqb 导出。
5. **算法闪卡未批量生成**：按 §6 的卡片规范由用户/AI 后续逐批生成并挂到 `算法竞赛/专题/...` 卡组；本轮只落标签树与题库，不产生没有来源的模板卡。
6. **抓取依赖洛谷页面结构**：解析的是 SSR 里的 lentille-context JSON；洛谷改版需重跑抓取并核对（`data/luogu-problems-raw.json` 是本次快照）。抓取频率保持低频，未登录、未提交、未采集用户数据。
7. **标题**：.tqb 不带 title（现有契约无该字段），seed 脚本导入后用 `suggestQuestionTitle` 回填「算法竞赛 · Pxxxx …」；用户可在题库里逐题改名。
8. **题目难度是人工换算值**（7/8/9），不是组卷网/洛谷的测量值；source_label 保留原始洛谷文案可核对。

## 12. 文件清单

- 产品仓库：`docs/ALGORITHM_SUBJECT_DESIGN.md`；改动见 §7；新增两个测试/落库文件。
- 工作区 `10-projects/algorithm-subject/`：
  - `data/luogu-problems-raw.json`（17 题原始抓取快照）、`data/luogu-tags-map.json`（洛谷标签 id→名）
  - `data/algorithm-questions.json`（17 条 .tqb 记录）、`data/algorithm-tags.json`（标签树）
  - `data/pack-probe-report.json`、`verify-after-import.json`（验证证据）
  - `packages/Furnace-algorithm-2026-11-06.tqb`（可直接导入的题库包）
  - `solutions/P*.cpp`（17 份参考代码）、`scripts/*.py`（抓取后处理/构建/样例测试/校验）
  - `README.md`（数据清单与复现命令）
- 真实库备份：`00-inbox/algorithm-subject/backup/furnace-before-algorithm-*.db`；题库自动备份在 `E:/Furnace/data/documents/question_pack_backups/`。