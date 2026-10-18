# 入库体检设计（QuestionIntakeAudit：把硬伤判据本地化）

> 轮次一百二十三（task-15）。用户长期目标是「题库 + 推理层 + 三应用领域」；AI 不出题，只解题/拆题/找相似题。
> 题目从组卷网、拍照、文件导入进来，**采集会丢信息**（公式是图片、加点/下划线被纯文本化丢掉），
> 入库前需要一层确定性体检：把题源标准里「可证伪的硬伤」变成代码判据，只报不改、不联网、不调模型。
> 判据来源：`app/lib/data/skill/zujuan_finder_skill.dart:92-98`（组卷网 skill 的 H1–H4 九条判据）。
> 本文只讲体检；题库模型见 `docs/QUESTION_BANK_DESIGN.md`，相似题见 `docs/SIMILAR_QUESTIONS_DESIGN.md`。

## 1. 目标与边界

**要解决的问题**：题库里「答案算得对不对」只能靠独立解题判断，代价高且不可自动化；
但「选项体系崩坏 / 答案与正确标记矛盾 / 题干说"如图"却没有图 / 同批重复 / 编号冲突」
这类**结构性硬伤**可以从数据本身机械判定。先清掉这些，人工复核和 AI 解题才不会被脏数据带偏。

**纪律（与 skill 一致，代码注释里也写了）**：

1. **只报不改**：输出结论 + 证据，不修改任何题目行；删/改/合并由人决定。
2. **可证伪**：每条结论必须能在 `QuestionAuditFinding.evidence` 里指出「凭什么」。
3. **确定性**：不联网、不读 DB、不调模型、不隐式读 `DateTime.now()`（当前年份由调用方注入，默认 2026）。
4. **纯 Dart**：`lib/domain/services/questions/question_intake_audit.dart` 不 import drift / Flutter / dart:io，
   可在纯 Dart 测试里跑；UI 与 DB 拼装留给调用方（下一轮接线见 §10）。
5. **不误伤**：说明不了的判据不做（知识正确性、条件不足、歧义、超纲都不在本轮）。

「未发现硬伤」≠「已证明没问题」：`QuestionAuditReport.isClean` 的注释与本文档都按这个口径写，
报告只是初筛（对应 skill「样本 <5 道只算初筛」的纪律）。

## 2. 文件与公开 API

| 文件 | 内容 |
| --- | --- |
| `app/lib/domain/services/questions/question_intake_audit.dart` | 1050 行；26 条判据 + 输入/输出模型 + 排序 |
| `app/test/domain/services/questions/question_intake_audit_test.dart` | 989 行；8 组 53 例（+10 例既有 `question_number_test`） |
| `docs/QUESTION_INTAKE_AUDIT_DESIGN.md` | 本文 |

冻结的公开 API（行号为当前文件）：

```dart
// 逐行体检（不含跨行重复）
class QuestionIntakeAudit {
  const QuestionIntakeAudit({
    int currentYear = kQuestionAuditDefaultCurrentYear, // 2026
    Set<String> knownSubjectKeys = const {},            // 空集 = 跳过 unknown 检查
    Set<String> knownSourceLevels = const {},           // 空集 = 跳过检查
    double minDifficulty = 1.0,
    double maxDifficulty = 10.0,
  });

  QuestionAuditReport audit(Iterable<QuestionAuditRow> rows); // 行内 + 跨行 + 排序
  List<QuestionAuditFinding> auditRow(QuestionAuditRow row);  // 单题详情页用
}

QuestionAuditReport auditQuestionIntake(
  Iterable<QuestionAuditRow> rows, {
  int currentYear = 2026,
  Set<String> knownSubjectKeys = const {},
  Set<String> knownSourceLevels = const {},
  double minDifficulty = 1.0,
  double maxDifficulty = 10.0,
});

// 报告：findings 已排序且不可变；UI 直接消费
class QuestionAuditReport {
  final List<QuestionAuditFinding> findings;
  int get errorCount; int get warningCount; int get infoCount;
  bool get isClean;
  Map<QuestionAuditSeverity, int> get counts;
  List<QuestionAuditFinding> findingsFor(String questionId);
  List<QuestionAuditFinding> bySeverity(QuestionAuditSeverity severity);
}
```

位置：`QuestionAuditCodes` :55（`all` :97）、阈值常量 :127-172、
`QuestionAuditRow` :201、`QuestionAuditFinding` :279、`QuestionAuditReport` :320、
`QuestionIntakeAudit` :367（`audit` :395、`auditRow` :406）、顶层入口 :991。
判据实现：行内 :413、选项 :589、答案 :716、重复题干 :843、重复编号 :909、排序 :967。

一行模型 `QuestionAuditRow` 的默认值：`questionType='solution'`、`subjectKey=''`、
`sourceLevel='unknown'`、`knowledgePointIds=[]`、`imageCount=0`、`state='raw'`；
其余可空字段为空即「不知道」，不按 0 计（难度/年份/aiQuality 都是 `double?/int?`）。

## 3. 输入模型与 DB 字段对应

`QuestionAuditRow` 是 DB 行的**投影**，不是实体：调用方从 questions + question_options
（+ 知识点关联、附件计数）拼出来。字段来源（`app/lib/data/database/tables.dart`）：

| QuestionAuditRow 字段 | DB 来源 | 说明 |
| --- | --- | --- |
| `questionId` | `questions.id` :1093 | `q-<uuid>` |
| `serialNo` | `questions.serialNo` :1103 | 可空；跨学科一个序列，显示 `TR-00001`（`domain/services/questions/question_number.dart`） |
| `stem` | `questions.stem` :1106 | 纯文本，公式保留 LaTeX |
| `answer` | `questions.answer` :1109 | 可空：允许先存题干后补答案 |
| `solution` | `questions.solution` :1112 | 可空 |
| `questionType` | `questions.questionType` :1117-1119 | `single_choice` / `multi_choice` / `fill_blank` / `solution` / `open` |
| `subjectKey` | `questions.subjectKey` :1115 | 自由字符串，默认 `''` |
| `sourceLevel` | `questions.sourceLevel` :1124 | 默认 `unknown`；词表见 `kQuestionAuditKnownSourceLevels` |
| `sourceLabel` | `questions.sourceLabel` :1127 | 人可读来源 |
| `year` | `questions.year` :1129 | 可空 |
| `region` | `questions.region` :1130 | **本轮不判**，留给后续 |
| `difficulty` | `questions.difficulty` :1132-1133 | **1–10**，可空 |
| `aiQuality` | `questions.aiQuality` :1148-1149 | **0–1**，可空 |
| `stemFingerprint` | `questions.stemFingerprint` :1140 | FNV-1a 64 位十六进制；空则按归一化题干比较 |
| `state` | `questions.state` :1145-1146 | `raw/structured/processed`；**本轮不判**，留给 UI 过滤 |
| `options` | `question_options` :1164-1172（`label/content/isCorrect/sortOrder`） | 选择题按顺序给 |
| `knowledgePointIds` | 知识点关联表 | 调用方拼；空 → info |
| `imageCount` | 附件/图片表 | 调用方统计；0 表示无图 |

**输入模型的一处偏离（必须知道）**：任务书写行模型时漏了 `aiQuality`，但 H3 明确要查
`aiQuality` 越界 ⇒ 行模型加了 `double? aiQuality`（字段注释说明原因）。除此之外与任务书一致。

## 4. 判据表（26 条，`QuestionAuditCodes.all` 同序）

严重度口径：**error** = 按当前数据会判不了/判错/不可用；**warning** = 可能丢了信息或规范问题，人工看一眼；
**info** = 能继续用，但缺口已知。

### 4.1 H1 题干/选项体系（10 条）

| code | 严重度 | 触发条件（代码位置 :413-713） | 为什么算硬伤 |
| --- | --- | --- | --- |
| `h1_stem_empty` | error | `stem.trim()` 为空 | 没有题干无从解题/展示 |
| `h1_stem_too_short` | warning | 去空白后可见字符 < `kQuestionAuditMinStemChars`（6） | 像拍照切题残留/题干截断（「如图」「第3题」）；阈值故意压低，宁漏勿误 |
| `h1_choice_options_too_few` | error | 选择题 `options.length < 2` | 不足两个选项不可能有唯一答案 |
| `h1_option_label_duplicate` | error | 归一化（trim+大写）后标签重复 | 答案「A」指向哪个选项不唯一，判分错位 |
| `h1_option_label_not_sequential` | warning | 标签不是 A/B/C…（选项数 ≤26 时检查） | 判分/展示错位可疑；自定义标签（①②、AB）可能合法，故 warning |
| `h1_option_content_empty` | warning | 选项 `content.trim()` 空 | 采集丢了选项正文，该选项无法判 |
| `h1_single_choice_no_correct` | error | `single_choice` 且无 `isCorrect` | 没有正确选项无法判分 |
| `h1_single_choice_multiple_correct` | error | `single_choice` 且正确选项 >1 | 单选出现多答案，题目/数据必有一错 |
| `h1_multi_choice_no_correct` | error | `multi_choice` 且无 `isCorrect` | 同上，多选无答案无法判分 |
| `h1_figure_missing` | warning | 题干匹配 `如图|见图|下图|上图` 且 `imageCount <= 0` | 图文矛盾/「说如图」图缺失（skill H1 的图文矛盾子集） |

### 4.2 H2 答案/解析（6 条，代码位置 :716-835）

| code | 严重度 | 触发条件 | 为什么算硬伤 |
| --- | --- | --- | --- |
| `h2_answer_missing` | warning | answer 空/全空白 | 题目可存但不可判；题库允许后补，故 warning |
| `h2_solution_missing` | warning | solution 空/全空白 | 只有答案无过程 → 不可托付（skill 口径） |
| `h2_solution_equals_answer` | warning | 去空白后 solution == answer | 解析只有答案没有过程，等同没有解析 |
| `h2_answer_not_in_options` | error | 选择题 answer 提取不到 A-Z 字母，或字母不在选项标签里 | 判分只读 answer 列 → 必判错/判不了 |
| `h2_answer_conflicts_correct_mark` | error | 答案字母 ≠ 正确标记集合（多选还查「标记有、答案漏」） | 答案与选项标记必有一错 |
| `h2_answer_without_correct_mark` | warning | 有答案、选项未标任何正确 | 答案无法在选项上核验 |

答案字母提取：answer 里所有 A-Z/a-z → 大写集合（「A」「A、B」「AB」等价）；选择题答案列按约定应只写答案，
写成整段解析会提取出多余字母（见 §6 误报边界）。

### 4.3 H3 元信息（6 条，代码位置 :460-556）

| code | 严重度 | 触发条件 | 为什么算硬伤 |
| --- | --- | --- | --- |
| `h3_difficulty_out_of_range` | warning | difficulty 非空且（NaN 或 < `minDifficulty` 或 > `maxDifficulty`） | 默认区间 1–10；越界是脏数据，组卷排序/难度统计会失真 |
| `h3_year_out_of_range` | warning | year < `kQuestionAuditMinYear`（1900）或 > currentYear + `kQuestionAuditFutureYearSlack`（1） | 0/占位符/未来年份都是脏数据；留一年余量给次年模拟卷 |
| `h3_subject_missing` | warning | subjectKey 空 | 无法按学科检索/统计，也无法路由到对应解题器 |
| `h3_subject_unknown` | warning | 注入的 knownSubjectKeys 非空且不含该学科 | 学科 key 拼错/新学科未登记；空集=跳过（调用方没给词表就不判） |
| `h3_source_level_unknown` | warning | 注入的 knownSourceLevels 非空、分级不在其中、且 sourceLabel 空 | 追不到出处；有 sourceLabel 就降级为可追溯，不报 |
| `h3_ai_quality_out_of_range` | warning | aiQuality 非空且（NaN 或 <0 或 >1） | 预评分数据脏，排序会被带偏 |

### 4.4 H4 重复/编号 + 本地点（4 条，代码位置 :843-944、:413-585）

| code | 严重度 | 触发条件 | 为什么算硬伤 |
| --- | --- | --- | --- |
| `h4_duplicate_stem` | error | 同批（一次 audit 的行集合内）：归一化题干相同（非空）、或非空 stemFingerprint 相同；两组命中合并成一条，evidence `matched_by` = `stem/fingerprint/both` | 同一道题在库里存两份，复习/组卷会重复 |
| `h4_duplicate_serial` | error | 同批 serialNo（只比 ≥1 的正整数）重复 | 编号唯一性被破坏，错题本/文件导出会指错题 |
| `h4_serial_missing` | info | serialNo 为 null 或 <1 | 还没编号；界面显示 `TR-未编号`，可后补 |
| `local_no_knowledge_points` | info | 关联知识点（去空白后）为空 | 不影响判分，只影响按考点检索/相似题召回 |

**重复题两边都报**：每道重复题各出一条 `h4_duplicate_stem`，evidence 的
`other_question_ids` 列出同组其他题的 questionId（逗号分隔，按行序）；
三道同题干时每行 evidence 列另外两道。空题干不参与重复分组（它已经有 `h1_stem_empty`）。

## 5. 阈值与常量（全部可注入的只有 4 个构造参数，其余是产品常量）

| 常量 | 默认 | 理由 / 备注 |
| --- | --- | --- |
| `kQuestionAuditDefaultCurrentYear` | 2026 | 不隐式读 `DateTime.now()`：结果可复现、可测；真实年份由调用方注入 |
| `kQuestionAuditMinStemChars` | 6 | 最短完整单选设问也有 8 字；<6 基本是切题残留。故意压低阈值减少误报 |
| `kQuestionAuditMinYear` | 1900 | 更早的年份在高考/教材语境下基本是脏数据 |
| `kQuestionAuditFutureYearSlack` | 1 | 当年卷子/次年模拟卷可能标成未来年 |
| `kQuestionAuditMinDifficulty` / `MaxDifficulty` | 1.0 / 10.0 | 跟 `questions.difficulty` 1–10 口径（`tables.dart:1132`）；见 §7 偏离说明 |
| `kQuestionAuditMinAiQuality` / `MaxAiQuality` | 0.0 / 1.0 | 跟 `questions.aiQuality` 0–1 口径（`tables.dart:1148-1149`） |
| `kQuestionAuditChoiceTypes` | `{single_choice, multi_choice}` | `questions.questionType` 词表（`tables.dart:1117-1119`） |
| `kQuestionAuditKnownSourceLevels` | `{gaokao, provincial_diagnostic, elite_school, school, personal, unknown}` | 镜像 `question_repository.dart:15-22` 的 `kSourceLevelWeight` keys（不能 import：仓储 import drift） |

构造参数 `currentYear`/`knownSubjectKeys`/`knownSourceLevels`/`minDifficulty`/`maxDifficulty`
决定「这一次体检」的口径；同一次 audit 的所有行共享同一套阈值。

## 6. 可证伪性与误报边界（写清楚，免得把结论当真理）

- `h1_stem_too_short`：真·超短题（判断题只有「对/错」）会误报 → warning；人工扫一眼即可。
- `h1_figure_missing`：题干文字里有「如图」但图片以 Markdown/LaTeX 内嵌在 stem 文本里、
  或 imageCount 统计口径不含内嵌图 → 误报。它给出的是「图可能丢了」的可疑清单，不是判决。
- `h1_option_label_not_sequential`：非字母标签（①②③、A/B/AB 组合）会误报 → warning。
- `h2_answer_not_in_options`：answer 列若被写成整段解析（含英文单词/公式字母），
  字母提取会抓到多余字母 → 误报 error。约定是 answer 只写答案；采集脏数据会触发，需人工确认。
- `h2_solution_equals_answer`：解析确实只写答案（简答题常见）→ 误报 warning。
- `h3_subject_unknown`：新学科没加进注入词表 → 误报；空集时跳过。
- `h3_source_level_unknown`：有 sourceLabel 就不报，避免把「分级没填但有出处」当硬伤。
- `h4_duplicate_stem`：同一材料下多问（「根据材料回答(1)(2)」拆成多题）文本相同但设问不同，
  会误报重复；整行 stem 归一化无法区分设问编号，需人工确认。近似重复（只换数值/选项顺序）**不报**。
- 跨行判据只在**同一次 audit 的行集合**内；不跨批、不跨库。要查全库重复，一次把全库行传进来。
- 报告只回答「这批行里存在哪些可机械判定的硬伤」，不回答「题目对不对/答案算得对不对」。

## 7. 与任务书的两处偏离 + 两条补充判据

1. **行模型加了 `aiQuality`**：任务书输入模型漏写，但 H3 要求查 aiQuality 越界
   （`questions.aiQuality` 0–1，`tables.dart:1148-1149`）。已在字段注释注明。
2. **difficulty 默认区间 1–10，而非任务书写的 [0,1]**：仓库权威口径是 1–10 ——
   `tables.dart:1132`、`docs/QUESTION_BANK_DESIGN.md:41`「1–10，可空」、
   `question_intake_page.dart:128` 手动校验 `<1 || >10`、
   `paper_plan_provider.dart:126` `clamp(1.0, 10.0)`。
   若将来某数据源真是 0–1，构造时传 `minDifficulty: 0, maxDifficulty: 1` 即可（测试已覆盖该注入）。
3. **两条补充判据**（skill 原文可确定判定，故本地化）：
   - `h1_figure_missing`：H1「图文矛盾或说"如图"而图缺失」（`zujuan_finder_skill.dart:92`）；
   - `h2_solution_equals_answer`：H2「解析只有答案没有过程 → 只判不可托付」（`:94`）。

## 8. 与组卷网 skill H1–H4 的对应关系

skill 九条判据（`app/lib/data/skill/zujuan_finder_skill.dart:92-98`）→ 本轮本地化情况：

| skill 判据 | 本轮 | 说明 |
| --- | --- | --- |
| H1 条件不足 / 歧义 / 设问依赖题干外材料 / 超纲 | **未做** | 需要解题与语义判断，不是确定性数据检查 |
| H1 图文矛盾或「如图」图缺失 | **部分**：`h1_figure_missing` | 只做「文字提到图 + imageCount≤0」这一可证伪子集 |
| H1 选项体系崩坏（单选 ≥2 正确项等） | **已做**：10 条 H1 判据 | 选项数/标签/内容/正确标记全覆盖 |
| H2 答案错（独立解出→换方法复算→仍不一致） | **未做** | 需要真的会解题；本轮不冒充 |
| H2 解析与答案不一致 / 解析讨论另一道题 | **未做** | 语义判断 |
| H2 解析只有答案没有过程 → 不可托付 | **已做**：`h2_solution_equals_answer` | 仅当解析与答案完全相同；更隐晦的「没有过程」不判 |
| H3 难度标错（极端偏差） | **未做真实难度判断** | 只做区间越界；真实难度需认知模型与标定 |
| H3 来源/年份/学科元信息 | **已做**（4 条 H3） | 年份/学科/来源分级/aiQuality |
| H4 同一题干站内 ≥2 次 | **已做**：`h4_duplicate_stem` | 同批内归一化题干/指纹 |
| H4 逐字相同只换数值/选项顺序；同卷近乎相同 | **未做** | 近似重复需要相似度阈值与语料标定，等相似题检索的阈值成熟后再做 |
| 「样本 <5 只算初筛」「未发现硬伤 ≠ 已证明没问题」 | **口径一致** | `isClean` 注释与 §1 都按初筛写 |

## 9. 未做清单（明确留给后续）

- 知识正确性（答案算错、解析算错）、条件不足、歧义、超纲、设问依赖外部材料 —— 需解题/语义。
- 难度真实值是否标错 —— 只查区间；真实难度需要认知模型先验 + 标定。
- 近似重复（只换数值/选项顺序、同卷内两道近乎相同）—— 需阈值标定与语料。
- 来源可信度打分（`kSourceLevelWeight` 只是分级权重，不是质量分）；`region` / `state` /
  `imageCount < 0`（不可能值）/ `origin` 未判。
- 跨批/跨库重复；题簇/题组关系。
- DB 拼装、迁移、UI 徽标、自动修复 —— 下一轮接线（§10），本轮不碰。
- 文案未进 l10n：`messageZh` 是中文硬编码，域层不依赖 Flutter；UI 若要英文，按 `code` 映射即可。

## 10. 下一轮 UI / 数据接线计划

1. **拼行**（Repository 层，Lead 接线）：一次查询 questions + question_options（按 sortOrder）
   + 知识点关联 id + 图片数，投影成 `QuestionAuditRow`。
   - `imageCount` 口径 = 该题附件/图片行数；题干 Markdown 内嵌图不算（这正是 h1_figure_missing 的检测对象）。
   - `stemFingerprint` 用仓储已有的 `stemFingerprint()`（`question_repository.dart:28-38`；空则体检内部回退归一化题干）。
2. **体检**：`auditQuestionIntake(rows, knownSubjectKeys: ..., knownSourceLevels: kQuestionAuditKnownSourceLevels, currentYear: ...)`。
   - `knownSubjectKeys` 建议取题库已有学科 key（distinct `subjectKey`）或设置页学科表；空集自动跳过。
   - `currentYear` 由设置/系统注入；默认 2026 仅方便测试与复现。
3. **展示**：题库列表用 `errorCount/warningCount` 做徽标；题目详情页用 `findingsFor(questionId)`
   展开证据（code + messageZh + evidence），单题场景可直接调 `auditRow` 避免整批。
4. **交互边界**：只提示，不自动改题/不自动删重复题/不自动补编号（skill 纪律「只报不改」）。
5. **性能**：纯内存 O(n log n) 排序；万级行可接受；若题库继续增大，UI 侧按学科/state 分批体检。

## 11. 验收证据（本机真实输出）

| 命令（工作目录 `E:\dsh-app`） | 真实输出 |
| --- | --- |
| `dart format test/domain/services/questions/question_intake_audit_test.dart` | `Formatted 1 file (1 changed)` |
| `dart analyze lib/domain/services/questions test/domain/services/questions` | `No issues found!` |
| `flutter test test/domain/services/questions` | `00:04 +63: All tests passed!` |
| `dart analyze lib test` | `92 issues found`（0 error / 0 warning；全部既有 info，与门禁基线 92 一致；新文件 0 issue） |

测试覆盖（8 组 53 例）：干净题零 finding / 顶层函数等价 / `auditRow` 不算跨行；
H1 题干与选项 12 组（空、5 vs 6 字边界、如图、1/0 个选项、重复/非连续/小写标签、空内容、
单选无/多正确、多选无正确、非选择题不套判据）；
H2 8 组（答案/解析缺失、解析=答案、非字母答案、矛盾、多选漏标、小写一致、多选一致）；
H3 9 组（难度 0/1/10/10.1、注入 0–1、NaN、年份 1899/1900/2027/2028、注入 currentYear、
学科空/未知/跳过、来源分级三态、aiQuality 边界）；
H4 7 组（同题干不同标点、指纹、both、三道同题干、空题干不参与、重复编号证据、编号缺失三态）；
本地点 1 组；报告结构 5 组（计数、精确排序、确定性、不可修改、toJson/labelZh）；
最后 28 行构造覆盖全部 26 条 code（断言 `QuestionAuditCodes.all` 长度/去重/全覆盖）。

## 12. 后续可做（按价值排序）

1. 近似重复：对已有 `similar_questions.dart` 的四分量做「同批去重」阈值实验，成熟后再引入。
2. 选项顺序一致性：多选答案字母序 vs 选项实际标签序（本轮只查集合，不查顺序）。
3. 与「解题/拆题」结果联动：AI 独立解出的答案与 `answer` 不一致 → 新 code，但那是推理层的事，不在本轮。
4. UI 接线（§10）与 l10n 映射（按 code → 本地化文案）。

