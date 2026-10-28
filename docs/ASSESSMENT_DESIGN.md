# 测评层设计（抽象参数 × 板块化 instrument）

> 状态：设计定稿，代码开始落地（轮次二十三起）。
> 上游：用户 2026-10-14 的三条口径——① **自评起步、客观抽检逐步**；② **不从卡片出题，要测"抽象参数"，且物理和语文不能用同一套方法**；③ **同步不做实时，Windows 出一个可发布 release 版本时同步**。
> 相关：[MINDNET_ROADMAP.md](MINDNET_ROADMAP.md)（认知模型切片）、[MINDNET_CONTRACT.md](MINDNET_CONTRACT.md)（参数语义）、[MILESTONES.md](MILESTONES.md)（产品里程碑）、[DATA_MODEL.md](DATA_MODEL.md)。

---

## 0. 这份文档回答什么

三件事，别的不管（UI 细节留给实现轮次）：

1. 认知模型真正消费的**抽象参数**有哪些，现在各自从哪来；
2. 每个参数**能不能用测评直接测**，用什么信号测；
3. 测出来的数**怎么进模型**（先验 + 不确定度，而不是伪装成观测）。

---

## 1. 为什么必须测抽象参数

`app/lib/domain/services/srs/dsr_card_state.dart:6-13` 已经写死了一件事：认知模型的记忆状态就是 `card_states` 的那四列——`encoding_strength`(R0) / `stability`(S) / `savings`(Σ) / `difficulty`(D)。四列**现在只有一种来源：真实复习行为**（`ReviewLogs` → `DsrMemory`）。

后果是两条，都在本会话被实测到：

- **冷启动没有输入**。新用户（或新知识点）在第一次复习之前，R0/S/Σ/D 全是 NULL，模型只能按默认值转，读数页给出的"发展区/危险区"因此没有个体信息。
- **主观量与客观量分不开**。元认知层的 `fluency` 是信念公式的输入（`w_fluency·f`），但 App 里没有 f 的真实来源，实现时只能用 `encodingStrength` 当代理；于是"自信但记不住（危险）"这件事无法真正成立——危险的定义需要"主观流畅 − 客观可提取"两个独立来源，只有一个来源时它必然退化成同一个数。

**测评层的职责**：在复习行为之外，提供 `fluency`（主观）、`R0`/`D`（客观先验）这两类信号的**独立来源**，并显式标注不确定度。

---

## 2. 抽象参数清单

| # | 参数 | 符号 | 模型里的位置 | 现状来源 | 测评能否直接测 | 首版怎么给 |
|---|---|---|---|---|---|---|
| 1 | 编码强度/可提取上限 | `R0` | `card_states.encoding_strength` | 复习行为（无→NULL） | 部分（要靠客观抽检） | 自评 → 先验区间 |
| 2 | 记忆稳定性 | `S` | `card_states.stability` | 复习行为 | 不能（需时间跨度） | 自评 → 先验，靠复习校正 |
| 3 | 节省效应 | `Σ` | `card_states.savings` | 复习行为（重学增益） | 不能 | 不给先验（保持 NULL） |
| 4 | 难度 | `D` | `card_states.difficulty` | 复习行为 | 可以（错题率） | 抽检错误率 → 先验 |
| 5 | **主观流畅度** | `fluency` | 元认知信念 `b_v` | **没有**（曾用 R0 代理） | **可以（自评/即时判断）** | 自评 0–5 直接映射 |
| 6 | 校准偏置 | `belief − R` | 危险区/焦虑区判据（`delta=0.2`） | 元认知层推 | 可以（自评 vs 抽检差） | 每轮测评累计 |
| 7 | 事件"接近度" | `closeness` | 复习事件参数 | 复习 UI（差点想起） | 不适用 | 不动 |
| 8 | 注意力/可用性 | `α(τ)` | 节律层（未实现） | 没有 | 可以（时点问卷） | 后续切片 |
| 9 | 作答速度 | — | 尚无消费方 | 没有 | 可以（计时） | 先记录，不建模 |

**纪律**：所有测评产出的参数一律带 `calibrated: false` 与样本数 `n`；`Σ` 明确**不**给先验——宁可保持 NULL（`tables.dart:311-313` 的既定态度："NULL 表示从未设置，不是 0"）。

---

## 3. 三种信号（自评起步的顺序就是它们的代价顺序）

| 信号 | 测什么 | 噪声 | 代价 | 何时可用 |
|---|---|---|---|---|
| **自评**（JOL："这个点你会多少" 0–5） | `fluency` 本体、`R0` 的弱先验 | 系统性高估（overconfidence） | 零成本、离线 | **首版** |
| **复述抽检**（"用一句话说出它"） | `R0`/`D` 的客观锚点 | 判分噪声（AI 或人工） | 每题十几秒 | 首版（可关） |
| **板块客观题**（辨析/条件判断/层级阅读） | `D`、概念区分度、边界知识 | 依赖题源质量 | 高（要题源） | 逐步 |

关键点：**自评单独存在时会系统性高估**，所以"自评起步"必须配一个校准动作——否则 `fluency` 只是把用户的乐观编码进了模型，危险区会假阳性。首版的校准动作是**小样本抽检**（3–5 题），它的作用不是给每个点精确的 R0，而是给这一轮的 `fluency` 一个**偏置修正**。

---

## 4. 分板块 instrument

用户口径：物理和语文不能用同一套方法。所以 instrument 是**可插拔的板块适配器**，共享参数 schema、落库与 UI。

```dart
abstract class AssessmentInstrument {
  String get subjectKey;                    // 'physics' | 'chinese' | 'generic' ...
  AssessmentScope defaultScope(...);
  List<AssessmentStep> plan(AssessmentScope scope, AssessmentBudget budget);
  AssessmentObservation judge(AssessmentStep step, AssessmentResponse response);
}
```

| 板块 | 测的抽象参数 | 题型形态（该板块独有） | 判分 | 现状可行性 |
|---|---|---|---|---|
| 通用（任何板块先能用） | `fluency`、校准偏置 | 范围自评 + 复述抽检 | 自评 + 复述（AI 判分可选） | **可做**：离线、无题源 |
| 物理 | `D`、概念区分度、适用条件 | 概念辨析（速度/速率/加速度）、公式成立条件、量纲/极限情形、多步推断 | 客观 | 需题源：AI 生成或用户带回 |
| 数学 | `D`、关系推理、表征转换 | 条件判断、反例构造、多表征互译 | 客观 | 同上 |
| 化学/生物 | `D`、分类与过程 | 归属判定、结构与功能对应、过程排序 | 客观 | 同上 |
| 语文 | 表征层级（字面/推断/评价）、文体修辞意识 | 分层阅读（同一文本三级提问）、表达任务 | rubric/自评 | 判分噪声大，先只做层级诊断 |
| 历史/政治 | 时序、因果、论据 | 时序排列、因果链补全、论点—论据配对 | 客观 | 同上 |

**题源纪律（已核过的事实）**：`app/lib/data/skill/zujuan_finder_skill.dart:5-12` 写明组卷网 skill 是 prompt-only——答案与解析在登录墙后，App 只有 `fetch_page`（GET、无 cookie、无 JS）。所以**"组卷网直接供题"今天不成立**；板块客观题的首个来源是 **AI 生成 + 用户从组卷网带回**，两者都要求题目带来源与判据（沿用 zujuan skill 的四条硬伤判据）。

---

## 5. 数据模型（首版）

新表（schema v10，全部只加不删；命名沿用既有单复数风格）：

- `AssessmentSessions`：`id` / `subjectKey` / `scopeTagIds`(JSON) / `startedAt` / `finishedAt` / `budget`(JSON) / `note`
- `AssessmentResponses`：`id` / `sessionId` / `knowledgePointId` / `stepKind`(`self_report`|`recall`|`objective`) / `prompt` / `answer` / `correct`(nullable) / `selfRating`(nullable 0–5) / `confidence`(nullable 0–5) / `elapsedMs` / `judgedBy`(`self`|`ai`|`auto`) / `createdAt`
- `CognitivePriors`：`knowledgePointId` / `source`(`assessment:…`) / `r0` / `d` / `fluency` / `n` / `calibrated`(0) / `createdAt`（**先验与观测分离**：不写进 `card_states`，读模型时按"有观测用观测、无观测用先验"合并）

## 6. 同步分类（用户口径 ③）

同步不做实时；**Windows 出一个可发布 release 时同步一次**。为了让那一天的合并不做数据手术，新表从第一天就标好三类：

| 类 | 表 | 合并规则 |
|---|---|---|
| 只追加（日志） | `AssessmentResponses`、`ReviewLogs`、`CompletionLogs`、`DiffusionLogs` | 并集 + 按 id 去重 |
| 可合并（状态） | `AssessmentSessions`（按 `finishedAt` 取完整的一轮）、`CardStates`、`Tasks` | 字段级 last-write-wins + 冲突留痕 |
| 派生（可重算） | `CognitivePriors` | 不参与同步，导入后本地重算 |

现有 `.tfpkg` 导出/导入（`app/lib/features/settings/presentation/data_section.dart:16-21`）是这条路的现成载体：release 节点同步＝导出/导入 + 上表规则，不引入 CRDT。

---

## 7. 首版切片与验收

- **M1a（本轮起）**：纯逻辑先验层 `app/lib/domain/services/cognitive/assessment_prior.dart`——输入自评与抽检结果，输出每知识点 `r0`/`d`/`fluency` 先验 + 全局校准偏置 + 置信度。单测覆盖：高自评×全错（应压低 R0、偏置为正）、低自评×全对（应抬高、偏置为负）、无抽检（低置信、只给自评先验）、边界钳制。
- **M1b**：schema v10 三张表 + 仓储 + 迁移单测；同步三分类写进 `DATA_MODEL.md`。
- **M1c（已完成，轮次二十四）**：最小 UI——选范围 → 自评 → 3 题复述抽检 → 结果页，写 `PROGRESS.md`。
  实现落在 `app/lib/features/assessment/presentation/assessment_page.dart`，入口在读数页。两处与本文原稿不同，
  理由记在这里：①结果页不展示"先验 vs 未测评的差异"（那需要 M1d 的观测合并，本片只报本轮写了几步证据、
  重算了几个点、平均 R0/置信度）；②复述抽检取范围的两端 + 中间（确定性），不抽"最弱卡"——那会变成另一种刷卡。
- **M1d（已完成，轮次二十五）**：接进读数页（测评先验与复习观测的合并展示，标注"先验/观测"）。
  实现口径（本节即验收）：先验只改**这张卡展示的起点 R0**，且只在这张卡还没有自己的复习史
  （`repetitions == 0 && lastReviewedAt == null`）时生效；一旦复习过，观测接管、先验不再说话，
  值旁边带"（测评先验）"字样，读数页的备注行报"几张卡正在用先验"。先验**不写回** `card_states`，
  也不参与 `ReviewAdvisory` 的排序（排序仍由 D4/D5 的规则决定）。读取走
  `AssessmentRepository.priorEstimatesFor`（批量版），与逐点的 `priorFor` 用同一套来源优先级，
  避免两处各写一份合并规则。
- **M6（已完成，轮次二十六）**：留存率 + 校准曲线，用来验证 M2"记忆效果好"到底成不成立。
  口径（本节即验收）：①**留存率**按"距上次复习同一条卡多少天"分桶（默认 0/1/3/7/30/∞），只用复习结果判定
  "记得"——客观判分 > FSRS ≥Good > v1 旧评分 ≥"记住了"；`fuzzy`/`Hard` 都不算，因为校准要的是"能不能取出来"。
  历史数据立刻可算，不需要任何预测。②**校准**要求预测在判分**之前**落库（`review_logs.predicted_r`，v11），
  事后重算不算预测；老行 NULL、**历史不补算**，所以曲线从 v11 开始积累。指标为
  `Brier = mean((R−实际)²)` 与 `ECE = Σ(n_b/N)·|预测均值−实际|`，预测 `R` 按 `[0,1]` 等宽分 5 箱
  （最后一箱闭合到 1.0）。③纯逻辑在 `app/lib/domain/services/cognitive/learning_metrics.dart`，
  读数页的"学习效果"卡片是**唯一不读模型自己读数**的块（数字全来自 `review_logs`），
  没有预测样本时明说"校准曲线还没有样本"而不是画一条假设的曲线。
  未做：把 `calibrated` 从 false 变 true（**需要真实标定数据**，协议见
  `docs/CALIBRATION.md`）。
  已补（轮次三十七，Q16 标定协议 v1）：**把度量接进 AI 工具**（只读工具 `review_metrics`），
  以及本地那一条协议的估计量——`app/lib/domain/services/cognitive/calibration.dart` 的二参数
  logistic 重标定（全局偏置 `b` + 斜率 `a` + 标准误），带"样本不足/只有一类结果/拟合不收敛时
  **拒绝给系数**"的诚实规则；读取层 `calibration_reader.dart` 与 AI 工具共用同一批
  `retentionSamples`。`cognitive_priors.calibrated` 仍然写 0：这一层只*检验*预测，不把任何参数
  写回模型。
  已补（轮次三十九，Q18 按知识点聚合）：④**逐知识点留存**——`LearningMetrics.retentionByKnowledgePoint`
  按 `RetentionSample.knowledgePointId` 分组，阈值 `kMinKnowledgePointRetentionSamples = 20`
  （20 条时 `p = 0.5` 的标准误约 0.11，更薄的分组点名"最差"就是把噪声当结论），
  **低于阈值的分组如实省略**、不补 0；排序 = 留存率升序 → 样本数降序 → id；
  每组附 `standardError`。归不到知识点的复习（`card_states` 已删，或 v1 模板卡本来就没写
  `knowledge_point_id`——见 `review_service.dart:415-425`）单独成 `null` 组、永远排最后，
  摘要里**不算**"最差的知识点"。AI 工具 `review_metrics` 增参 `knowledge_point_retention`
  （默认 false），开启后摘要最多点名 3 个样本够的最差点，其余只说数量。

## 8. 明确不做

- 不从卡片出题（用户口径 ②）；
- 不给 `Σ`/`S` 造先验（模型会自己长出来）；
- 不把先验写进 `card_states`（先验≠观测，混写会让"复习校正"失去意义）；
- 不在首版做实时同步/账号系统。

---

## 9. 能力测评（与知识先验解耦，2026-10-25 轮次一百七十七）

用户反馈第 8 条：认知测评要测**能力**，不是选标签测知识点。现有 M1c 页面（`assessment_page.dart`）测的是
知识点自评 + 复述抽检，产出 `cognitive_priors.r0`——那是**知识域的观测**；能力测评是另一个测量对象，
不能靠改文案混在一起。本节记新增的独立模块口径（实现见 `docs/DATA_MODEL.md` §27 与
`docs/REVIEW_FEEDBACK.md` §8）。

- **四项能力（MVP，纯本地确定性小测，合计约 3–4 分钟）**：
  1. 反应速度 `reaction_speed`：5 试次，随机等待 800–2000ms 后点目标，取中位反应时（ms）；
  2. 工作记忆 `working_memory`：5 试次，数字串跨度 4,5,6,7,8 依次出现，记最长答对跨度；
  3. 模式识别 `pattern_recognition`：10 试次，图案 A 先出 900ms、再出 B（50% 相同/换 1 个符号），答相同/不同，
     记正确数与中位反应时；
  4. 注意稳定性 `attention_stability`：30 试次（20 字母目标 + 10 数字非目标，洗牌），800ms 窗口内对字母点「是」=hit，
     超时或点「否」=miss，对数字点任何键=false alarm，取灵敏度与特异度。
- **评分口径**（`app/lib/domain/services/cognitive/ability_assessment.dart`，全部纯 Dart、可单测）：
  - 反应速度：中位 ≤250ms→100、≥800ms→0、中间线性（没有非负有效样本→0，避免 `median=0` 误给满分）；
  - 工作记忆：跳度 ≤3→0、≥9→100、中间线性（所以最长跨度 8 = 83 分，不是 100）；
  - 模式识别：正确率 ×70 + 速度 ×30（中位 ≤1500ms→满分速度、≥6000ms→0）；
  - 注意稳定性：(灵敏度 + 特异度)/2 ×100；`misses` 只进读数不进公式（灵敏度已由 hits/targets 表达）。
  - 分数一律 clamp 到 0–100，并带 `metrics`（原始读数，便于以后换公式时回溯）。
- **落库**：新表 `ability_scores`（schema v38：id / ability_key / score / metrics_json / captured_at），
  **只追加**，与 `assessment_sessions`/`assessment_responses`/`cognitive_priors` 完全分开；不参与
  `rebuildPriors()`，也不影响 FSRS 排期或 ReviewAdvisory 排序——第一版**不接** MindNet。
- **页面**：`app/lib/features/cognitive/presentation/ability_assessment_page.dart`（介绍 → 四项 → 汇总 → 保存，
  可重测单项、返回即放弃）；`ability_profile_page.dart`（只读画像：四项最近一次分数 + 测过几次 + 最近时间，
  没测过显示「还没测过」而不是 0 分）；设置页两个入口「能力测评」「能力画像」并列。
- **边界**：这类短测信度有限，定位是「看自己的相对变化趋势」，不是绝对智商；不联网、不调 AI、题目本地静态 +
  可播种随机数；保存是逐项写、非事务（中途失败可能留下前几项）；没有趋势图/历史列表/删除单条（下一步再做）。

### 9.1 能力趋势的纯逻辑（2026-10-26 轮次一百七十九）

画像页当前只显示最近一次分数，趋势小图需要「旧 → 新」的序列、方向与归一化坐标。这些整理放在
`app/lib/domain/services/cognitive/ability_trend.dart`（180 行，纯 Dart、不读库、不 import Flutter），数据来源是
`AbilityScoreRepository.historyFor`（已是新 → 旧）：

- `AbilityTrendPoint{capturedAt, score}`；`AbilityTrendSeries` 构造时按 `capturedAt` **稳定升序**排序（同一时刻保持传入顺序），
  `fromNewestFirst(..., {max = kAbilityTrendMaxPoints})` 先反转再 `capped(max)`，`kAbilityTrendMaxPoints = 30`（超出只留最新）；
- 读数：`delta`（最新 − 最早；空序列 null、单点 0.0）、`averageScore`、`bestScore`、`worstScore`、`earliest`/`latest`；
- 方向：`kAbilityTrendFlatEpsilon = 2.0`，`|delta| < 2` 记 flat（恰为 2.0 算有方向），单点/空序列 flat，NaN 差按 flat；
- 画图：`progress01`（最近一次 /100 夹到 0–1）、`normalizedScores`（每个点 /100 夹 0–1、NaN 记 0）、
  `normalizedPositions`（n=1 → [0]；n≥2 → `i/(n-1)`，首 0 末 1）。

全部确定性、不读时钟、不随机；29 例单测（`app/test/domain/services/cognitive/ability_trend_test.dart`）钉住排序/截断/方向阈值/夹取/空序列。
**画像页趋势图 UI 仍未接**，本轮只交付可单测的数据层。

---

## 10. 用户评测板块 v1.0（2026-10-29 轮次一百八十五）

用户 2026-10-29 给的《Furnace 用户评测板块设计文档》v1.0 是这一层的**设计定稿**（原文存 `E:/dsh-tmp-aot/b295-full.txt`，180,814 字符；仓库外）。本节只记**实现映射与偏差**，口径冲突以用户文档为准。与 §9 的关系：§9 的四项小测是 v38 的 MVP（`ability_scores`，只给相对变化）；**本节是正式版**（`cog_*` 八表，带 uncertainty、个体内基线、可配置映射，并给 Thread 侧参数），两套并存，旧入口在设置页已让位。

### 10.1 四层与对应代码

| 层 | 设计文档 | 代码 |
| --- | --- | --- |
| 项目 Task | §4.1/§4.2 十个任务 | `app/lib/features/assessment/application/task_registry.dart`（`kDefaultAssessmentTasks`、`kDefaultTaskAbilityMappings`、`kDefaultAbilityParamMappings`，纯常量） |
| 评测数据 | §3 session/trial/metric | `application/assessment_engine.dart`（跑一个会话）、`stimulus_generators.dart`（可播种确定性刺激）、`application/assessment_session_service.dart`（指标→标记→合并→推导） |
| 能力指标 | §3.2 19 个统计量 + §5 10 项能力 | `domain/assessment_metrics.dart`、`domain/assessment_mapping.dart`、`domain/assessment_estimates.dart` |
| 认知模型参数 | §6 9 个参数 + §7 映射 | `domain/assessment_estimates.dart` 的 `deriveParams`、`domain/assessment_cog_profile.dart`（`.cogprofile` 组装） |
| 落库 | §10 schema | `data/repositories/cognitive_profile_repository.dart`（实现 `AssessmentStore`）、`data/database/tables.dart` 八张 `cog_*`（见 [DATA_MODEL.md](DATA_MODEL.md) §30） |
| UI | §10.3 | `presentation/assessment_center_page.dart`（任务列表/历史）、`assessment_run_page.dart`（全屏任务）、`assessment_result_page.dart`（本次结果）、`assessment_profile_page.dart`（能力与参数档案，可覆盖）、`assessment_display.dart`（读数格式化共用的纯函数） |

### 10.2 十个任务（§4.2）

`fast_simple_task_i` / `ii` / `iii`（快速分类，`rt_median` + `accuracy` → processing_speed）；`go_nogo`（70/30，d′ → inhibitory_control）；`digit_span_backward`（从 3 递增、连续两次失败停，`stable_span` → working_memory_capacity）；`n_back_2`（60 trial、匹配 30–40%，d′ → working_memory_update_speed）；`stroop_crosslang`（40–60 trial、钓鱼 20–30%，`conflict_cost` → distraction_resistance，可选 processing_speed / cross_language_cost）；`task_switching`（60–80 trial 50/50，`switch_cost` → switch_cost_ability）；`fatigue_block`（3 段 × 60s，`rt_slope`/`variance_drift` → fatigue_slope/stability_drift）；`decision_fatigue`（50–100 次，`decision_drift`，**provisional**）。`fast_simple_task_iii` 与 `decision_fatigue` 在 v1 里 `enabled=false`（副本/暂定，不出现在评测中心）。

### 10.3 统计与估计口径（§5/§8.3/§9）

- 默认 uncertainty **0.7**（`decision_fatigue` 0.9、`cross_language_cost` 0.8），source=`default`，**不代表人群常模**，只是「还不知道」。
- 多次测量按 uncertainty **加权中位数**合并；新 uncertainty = `max(0.15, 1/sqrt(n+1))`（第一次测量 ≈0.707）——n 越多越低，最低 0.15。
- 质量标记（§9 八种）**只上调 uncertainty（每项 +0.1）**，不删数据、不判作弊：既压低这条新证据的权重（`uncertaintyWithQualityFlags`），也把合并后估计的不确定性抬高同等幅度。`practice_block` 由指标层排除练习自动成立、不单独产出；`background_switch` 由运行页在切后台时补报（`completeSession(extraQualityFlags:)`），属环境级标记、不受任务 `quality_checks` 限制。
- 中途退出：运行页落一条 `aborted` 会话（历史可见、不进能力估计），确认框文案与行为一致（「只留一条未完成记录」）。
- 指标只统计有效 trial（`isPractice=false`）；`rt_ms` 为 NULL 的试次算漏答，不是 0ms；`correct` 为 NULL 表示该试次不判对错（如疲劳块的持续按键）。
- 引擎把刺激与条件合并进 `trial.stimulus`（`_recordedStimulus`：`{...stimulus, ...condition}`，同名字段取 stimulus），指标层才能按 `switched` / `kind`（congruent/conflict/fish）分组——否则 stroop/切换类指标只能返回 null。
- `user_override` 后**停止自动更新**（引擎合并时跳过），用户可清除覆盖回到自动（数值保留，下次评测继续合并）。
- `design_version` 升级后旧测量标 `stale`、不参与合并（数据层留列与读侧约定；自动升级扫描尚未接）。

### 10.4 本轮范围与状态（2026-10-29）

- **P0 完成**：八张表 + schema v41 + 迁移/自愈 + 仓储（seed 幂等、默认行、override 语义）+ 十个任务注册 + 默认映射 + 引擎（十个任务共用一套声明式引擎）+ Fast I / Go-No-Go / 倒序 Digit Span 全流程 UI。
- **P1 完成**：2-back / Stroop / 任务切换 / 疲劳块的注册与引擎路径、指标计算、增量更新（合并/参数推导）与能力估计；离线纯逻辑与组件测试见 `app/test/features/assessment/`。
- **P2 完成**（2026-10-29 轮次一百八十六，`reasoning-core`）：Thread 侧参数接口——`app/lib/features/assessment/application/cognitive_params_provider.dart` 的 `CognitiveParamsProvider` / `ThreadWeightSuggestion` / `threadWeightSuggestions`（九项参数、`usedDefault` 标记；缺估计或来源=default 用默认先验，`uncertainty > kThreadParamMaxUncertainty(0.4)` 回退默认、等于阈值保留，`user_override` 永远信任，NaN/±inf 视为不可用回退，未知 id 用中性兜底 0.5/0.7；25 例）；Riverpod 接线见 `assessment_providers.dart` 的 `cognitiveParamsProvider` / `threadWeightSuggestionsProvider`（Lead，3 例）。
- **P3 部分完成**：`.cogprofile` 导出已接认知档案页——`assessment_cog_profile_export.dart`（`saveCogProfileWithFilePicker` / `cogProfileFileSaverProvider` / `cogProfileFileName` / `buildCogProfileBytes`）+ 档案页 AppBar 导出按钮（加载中/失败禁用、取消静默、成功/失败 SnackBar；7 例）。文件名 `furnace-cogprofile-yyyyMMdd-HHmm.cogprofile`，内容=§10.2 契约（`format_version` 1.0 + 10 能力 + 9 参数 + `exported_at` + privacy）。
- **仍未接**：ThreadFlow 实际采纳建议值（接口与 provider 已提供，消费侧未接）；疲劳块/参数映射的模型侧消费；决策疲劳与副本 III 仍默认关闭（provisional）；`.cogprofile` 平台保存通道只有组件测试、未真机验证。
- 设置页：原「能力测评」「能力画像」两个入口换成一个「评测与认知档案」（`settingsAssessmentTileKey` → `AssessmentCenterPage`）；旧 `ability_scores` 表/页面保留、无入口。

### 10.5 明确不做（与 §8 一致，重申）

- 不联网、不调 AI、不上传任何数据；所有任务本地静态刺激 + 可播种随机数。
- 不做防作弊/反虚拟机：只做质量标记并上调 uncertainty。
- 不给「绝对智商」或人群百分位：能力值是**个体内 z-score**（0 = 自己的典型水平）。
- 不把评测结果写进 `card_states`/FSRS 排期；P2 接口与 provider 已提供（轮次一百八十六），ThreadFlow 侧实际采纳仍待接。

### 10.6 Thread 参数接口与 `.cogprofile` 导出（2026-10-29 轮次一百八十六）

- **接口契约**（`app/lib/features/assessment/application/cognitive_params_provider.dart`，纯 Dart）：`CognitiveParamsProvider.fromEstimates(params)` 归一化（id trim、丢空、重复后写覆盖、只读视图）；`getParamsForThread({paramIds})` 默认返回 `kThreadRelevantParamIds` 九项（已知 id 固定顺序、未知 id 字典序）；`estimateFor(id)`；`suggestions()` / 顶层 `threadWeightSuggestions()` 返回 `ThreadWeightSuggestion(paramId, defaultValue, suggestedValue, uncertainty, source, usedDefault)`，可 `toJson()`。
- **回退规则**：无估计 / 来源=default → `kCognitiveParamSpecs` 默认先验；`uncertainty > 0.4` 回退默认；`== 0.4` 保留；`user_override` 永远信任（不受阈值影响）；NaN/±inf 视为不可用；未登记 id 兜底 0.5 / 0.7。`usedDefault = (最终 source == default)`。
- **Riverpod 接线**：`cognitiveParamsProvider` 从 `assessmentProfileProvider` 的已加载快照构造（加载中/失败退化为全默认，Thread 永远拿到可用值）；`threadWeightSuggestionsProvider` 给出九项建议。只给建议，不写库、不覆盖用户设置。
- **导出**：`assessment_cog_profile_export.dart` 的 `buildCogProfileBytes` 走域层 `buildCogProfile` + `encodeCogProfile`；`cogProfileFileName` 用设备本地时间；档案页导出按钮在数据未就绪时禁用，保存返回 null（用户取消）不提示，异常提示错误原文。
- **测试**：`cognitive_params_provider_test.dart` 25 例；`assessment_providers_test.dart` 3 例（空档案九项默认、低不确定性采纳+高不确定性回退、user_override 保留）；`assessment_profile_export_test.dart` 7 例（字节/文件名/成功/取消/失败/禁用/纯函数）。
- **未验证**：真实 `FilePicker.saveFile` 平台通道（组件测试走 provider seam）；真机窄屏布局。

