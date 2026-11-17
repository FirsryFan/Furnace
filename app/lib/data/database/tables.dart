import 'package:drift/drift.dart';

/// Local user profile (author identity only, no login).
class Profiles extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text().withLength(min: 1, max: 200)();
  IntColumn get avatarColor => integer().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Single-row local settings.
class LocalSettings extends Table {
  IntColumn get id => integer()();
  TextColumn get language => text().withDefault(const Constant('system'))();
  TextColumn get themeMode => text().withDefault(const Constant('system'))();
  TextColumn get profileId => text().nullable()();

  /// v2: active appearance theme; NULL = follow built-in defaults.
  TextColumn get activeThemeId => text().nullable()();

  // --- v6: AI configuration (single-row settings, see docs/AI_DESIGN.md) ---

  /// Master switch. NULL / false means the AI surface does not exist at all and
  /// the app makes no network call of any kind - which is what keeps the
  /// "offline by default" promise true rather than aspirational.
  BoolColumn get aiEnabled => boolean().withDefault(const Constant(false))();

  /// Provider API key, stored in plain text on purpose (single-user app, see
  /// AI_DESIGN D18 and the requirement that key handling stay convenient).
  /// It is exported inside `.tfpkg`; the export UI says so.
  TextColumn get aiApiKey => text().nullable()();

  /// OpenAI-compatible endpoint. Defaults to DeepSeek when NULL.
  TextColumn get aiBaseUrl => text().nullable()();

  /// Model name. Defaults to `deepseek-chat` when NULL.
  TextColumn get aiModel => text().nullable()();

  /// `plan` | `auto` (see AI_DESIGN D12 v2).
  TextColumn get aiPermissionMode => text().nullable()();

  /// v7: ceiling on model round-trips per user message - the agent loop's
  /// tool-call budget.
  ///
  /// NULL means "the user never chose", which the app reads as its shipped
  /// default rather than writing a value during the migration: an upgraded row
  /// must keep the behaviour it had before this setting existed.
  IntColumn get aiMaxRounds => integer().nullable()();

  // --- v46: model-parameter layer (2026-11-15, MODEL-CONFIG-2026-11-15.md) ---
  //
  // Same contract as every nullable preference above: NULL means "the user
  // never chose", which the app resolves to the value the code shipped before
  // this layer existed. The migration writes no value, because writing today's
  // default into every existing install would freeze it there and make a later
  // change of that default unreachable for those users.

  /// v46: thinking effort for the student solver's reasoning turn
  /// (`low` | `high` | `max`). NULL = send no `reasoning_effort` at all.
  ///
  /// Stored as the wire value; parsing lives in `ReasoningEffort.fromId`.
  TextColumn get aiReasoningEffort => text().nullable()();

  /// v46: temperature for the reasoning/solve turn. NULL = shipped 0.6.
  ///
  /// DeepSeek documents that temperature has **no effect** in thinking mode
  /// (it is accepted but ignored), so this column only has an effect when the
  /// model runs without thinking - see MODEL-CONFIG-2026-11-15.md.
  RealColumn get aiTemperature => real().nullable()();

  /// v46: temperature for the answer-scribe ("finalizer") turn. NULL = 0.2.
  RealColumn get aiAnswerTemperature => real().nullable()();

  /// v46: temperature for the independent content verifier turn. NULL = 0.2.
  RealColumn get aiVerifierTemperature => real().nullable()();

  /// v46: `max_tokens` for the reasoning turn. NULL = 20 000.
  ///
  /// The reasoning turn needs a large output budget or the chain of thought
  /// eats it and `content` comes back empty with `finish_reason = length`.
  IntColumn get aiMaxReasoningTokens => integer().nullable()();

  /// v46: `max_tokens` for the answer-scribe and verifier turns. NULL = 3 000.
  ///
  /// The answer reserve: the second, cheap turn that only writes the answer
  /// sheet after reasoning consumed its budget.
  IntColumn get aiAnswerReserveTokens => integer().nullable()();

  /// v46: model name for the verifier turn. NULL = the solver's model.
  ///
  /// Stored even before there is UI for it, so an experiment can point the
  /// verifier at a different model without a second migration later.
  TextColumn get aiVerifierModel => text().nullable()();

  /// v46: thinking effort for the verifier turn (`low` | `high` | `max`).
  ///
  /// NULL = send no `reasoning_effort`; deliberately **not** inherited from
  /// [aiReasoningEffort], because the verifier was a fresh, parameterless turn
  /// before this column existed and that is the behaviour an empty config must
  /// keep.
  TextColumn get aiVerifierEffort => text().nullable()();

  // --- v7: review preferences (user request "提出题型方式的喜好") ---
  //
  // Both columns are nullable and read as NULL on every upgraded row, because
  // NULL is carrying a real meaning here: "the user never chose", which the app
  // resolves to the shipped default. Writing a value during the migration would
  // instead freeze today's default into every install and make a later change of
  // that default unreachable for existing users.

  /// Default judging mode for a new answer: `strict` | `lenient` | `self`.
  ///
  /// These are the same words the practice screen's per-answer control uses, and
  /// the value only decides what that control starts as - the user can still
  /// judge any single answer differently while answering.
  ///
  /// NULL means [JudgeModePreference.strict], i.e. exact character comparison,
  /// which is the behaviour this app had before the setting existed.
  TextColumn get ankiJudgeMode => text().nullable()();

  /// Card type the automatic generation paths should write:
  /// `mixed` | `fill_blank` | `mcq` | `essay`.
  ///
  /// NULL means `mixed`, which resolves to the fill-blank fallback: exactly the
  /// card every generator produced before the preference existed.
  TextColumn get ankiCardTypePreference => text().nullable()();

  // --- v15: attention-availability hints on the thread status bar ---
  //
  // Same contract as the two v7 columns above: NULL means "the user never
  // chose", which the app reads as the shipped default. Writing `true` during
  // the migration would freeze today's default into every existing install and
  // make a later change of that default unreachable for them.

  /// Whether the thread status bar shows the attention-availability reading
  /// derived from the study log (`docs/MINDNET_ROADMAP.md` §3 row 4).
  ///
  /// NULL reads as visible: the reading is informational, it says out loud that
  /// its parameter is uncalibrated, and it can be hidden again in one tap - so a
  /// fresh install shows it until the user says otherwise.
  BoolColumn get rhythmHintsEnabled => boolean().nullable()();

  /// v21: whether the library-diagnosis run installs the goal mechanism
  /// (`context.goal`) - the first user-side switch of
  /// `docs/MINDNET_ROADMAP.md` §3 row 8.
  ///
  /// NULL reads as **installed**: a fresh install and an upgraded row keep the
  /// behaviour they had before this switch existed, and the app never writes a
  /// default on the user's behalf - the same rule as [rhythmHintsEnabled].
  /// Turning it off is a real behaviour change (the diffusion no longer has
  /// starts/targets to pull towards), so the panel states that next to the
  /// switch instead of presenting the two states as equal.
  BoolColumn get goalMechanismEnabled => boolean().nullable()();

  // --- v22: 目标机制的连续参数（第一个滑块）---
  //
  // 与上面两个"装不装"的开关同一个契约：列可空、NULL 读作出厂值，应用绝不替用户
  // 写默认值 —— 否则今天的出厂值会被冻进每一台已有安装，以后改出厂值就达不到了。

  /// v22: 用户给 `context.goal` 的目标偏置强度（`beta_goal`）调的值 ——
  /// roadmap §3 第 8 行的第一个滑块（"装不装"是本表上面那个开关，"牵引多强"是这一列）。
  ///
  /// NULL 读作转录表里的值（今天 0.3，`calibrated: false`，即未标定的占位值）。
  /// 用户能调的范围由内核的参数表给（`FastParamSpec.min/max`），页面不另编一套。
  RealColumn get goalBeta => real().nullable()();

  // --- v25: 能力动作词表 overlay（用户自定义动作的持久化，轮次一百二十三）---
  //
  // 与上面两列同一个契约：列可空、NULL 读作"用户没改过"，即空 overlay（出厂词表）。
  // 迁移绝不写默认值 —— 否则今天的空 JSON 会被冻进每一台已有安装，以后想换出厂
  // 词表或换存储格式就达不到了。

  /// v25: 用户自定义能力动作（`CapabilityActionOverlay` 的 JSON 原文）。
  ///
  /// NULL / 空串 / 解析失败都读作空 overlay：推理链路退回内置种子词表，与这一列
  /// 存在之前的行为逐字节相同。坏 JSON 不抛错、不阻塞任何一次解题——词表是锦上
  /// 添花的东西，不能让它挡住主流程（见 `capability_action_overlay.dart` 的宽容
  /// 解析与 `docs/REASONING_LAYER_DESIGN.md` §4）。
  TextColumn get capabilityActionOverlayJson => text().nullable()();

  // --- v28: 复习提醒（轮次一百三十五）---
  //
  // 与上面几列同一个契约：列可空、NULL 读作"用户没选过"——也就是提醒关闭、
  // 时刻用出厂 20:00。迁移绝不写默认值，否则今天的时间会被冻进每一台已有安装，
  // 以后改出厂时刻就达不到了（见 `docs/DATA_MODEL.md` §14）。

  /// v28: 是否每天用系统通知提醒还有到期卡片要复习。
  ///
  /// NULL（旧行 / 用户没选过）读作 **false**：提醒是会弹系统通知的东西，升级不应
  /// 替用户把它打开。仓库/域层负责把 NULL 翻成 false，界面不自己做这套翻译。
  BoolColumn get reviewReminderEnabled => boolean().nullable()();

  /// v28: 复习提醒时刻（本地时间的当天第几分钟，0..1439；1200 = 20:00）。
  ///
  /// NULL 读作域层的出厂值 `kDefaultReviewReminderMinutesOfDay`（今天 20:00），
  /// 但表定义不 import 域层——读侧负责这个翻译。写入校验 0..1439，越界由
  /// `SettingsRepository` 抛 ArgumentError，库里不存非法时刻。
  IntColumn get reviewReminderMinutes => integer().nullable()();

  /// v29: 标签树的排序方式（域层 `TagTreeSortMode.code`：
  /// `alphabetical` / `by_object_count` / `by_created_at`）。
  ///
  /// NULL 读作出厂「字典序」（用户从没选过），写侧也允许写 NULL 表示「恢复
  /// 出厂排序」。表定义不 import 域层——读侧用 `tagTreeSortModeFromStorage`
  /// 把 NULL / 未知值翻成出厂档位；库里只存域层的稳定 code，不存中文标签，
  /// 否则改文案会把已存值变成读不懂的字符串。
  TextColumn get tagTreeSortMode => text().nullable()();

  /// v48（2026-11-17）：标签树的展开状态（JSON 字符串数组，存**展开**的标签 id）。
  ///
  /// 用户要求标签页默认完全折叠：NULL 读作"用户没保存过" = 全折叠；空数组
  /// `[]` 读作"用户明确把全部收起"。读侧用 `tagTreeExpandedIdsFromStorage`
  /// 宽容解析（NULL / 坏 JSON 一律当空集合），写侧用
  /// `tagTreeExpandedIdsToStorage`。存展开而不是折叠，是因为新标签默认也该是
  /// 折叠的——历史折叠集合里不会出现新 id，会让新节点意外展开。
  ///
  /// 表定义不 import 域层；迁移只补列、不回填（回填会把"全折叠"冻成一次用户
  /// 的明确选择，以后改出厂默认就达不到了，与 [tagTreeSortMode] 同一个契约）。
  TextColumn get tagTreeExpandedIds => text().nullable()();

  /// v34（轮次一百六十八）：题库列表的排序方式（`QuestionLibrarySort` 的稳定
  /// code：`newest` / `serial` / `wrong_first`）。
  ///
  /// 与 [tagTreeSortMode] 同一个契约：列可空、NULL 读作"用户没选过"，也就是
  /// 出厂「最新在前」；写侧写 NULL 表示恢复出厂。表定义不 import 域层——读侧用
  /// `questionLibrarySortFromStorage` 把 NULL / 未知值翻成出厂档位；库里只存
  /// code，不存中文标签，否则改文案会把已存值变成读不懂的字符串。
  TextColumn get questionLibrarySortMode => text().nullable()();

  /// v35（轮次一百七十二）：用户对自己的自由描述（persona）。
  ///
  /// 语义是"用户写的原话"，不是结构化档案：列可空、空白归一化成 NULL（没写 = 没写），
  /// 迁移绝不回填。AI 的系统提示在读侧把它拼进去（见
  /// `docs/PERSONA_DESIGN.md`）；表定义不 import 域层，读写口径由
  /// `user_persona.dart`（归一化/长度上限/prompt 段落）统一。
  ///
  /// 存原话而不是摘要：摘要一旦写进库就成了不可逆的有损变换，用户改一个字就得
  /// 重写整段。长度上限由域层常量挡（超限不落库、由编辑页提示），不靠列宽。
  TextColumn get userPersona => text().nullable()();

  /// v36（轮次一百七十五）：复习间隔的目标记忆保持率（FSRS `requestRetention`）。
  ///
  /// NULL 读作域层出厂值（`kDefaultReviewRetention`，0.85 —— 比 FSRS 默认 0.9
  /// 更稀疏，因为用户反馈「间隔太短」）。取值范围由 `FsrsParameters` 的契约约束
  /// （(0,1)），读侧还要夹到 `kReviewRetentionMin..kReviewRetentionMax`；越界/坏值
  /// 一律回落出厂，不抛错、不阻塞复习。迁移绝不回填——回填会把今天的出厂值冻进
  /// 每一台已有安装。
  RealColumn get reviewRetention => real().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Tags can be created standalone or promoted from a mind map node.
///
/// v2: tags form a tree (`parentId`); `path` is the authoritative full tree
/// path string (e.g. `Culture/Subject/Chinese/Composition`), maintained in cascade on
/// rename/move. UI collapses parent prefixes by default.
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get parentId => text().nullable().references(Tags, #id)();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get path => text().nullable()();
  IntColumn get color => integer().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get sourceNodeId => text().nullable()();

  /// 标签用途声明（v37，轮次一百七十六）：逗号分隔的稳定 code
  /// (time / question / knowledge / task / flashcard)。
  /// NULL = 这一级没有声明，用途从祖先继承；整棵树都没有声明 = 不限制。
  /// 存 code 不存中文（与 tagTreeSortMode / questionLibrarySortMode 同一个契约）。
  TextColumn get usageCodes => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {path},
      ];
}

/// Polymorphic tag-object links.
class ObjectTags extends Table {
  TextColumn get id => text()();
  TextColumn get tagId => text().references(Tags, #id)();
  TextColumn get objectType => text()();
  TextColumn get objectId => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {tagId, objectType, objectId},
      ];
}

class MindMaps extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 300)();
  TextColumn get rootNodeId => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class MindNodes extends Table {
  TextColumn get id => text()();
  TextColumn get mapId => text().references(MindMaps, #id)();
  TextColumn get parentId => text().nullable()();
  TextColumn get nodeText => text().named('text')();
  TextColumn get notes => text().nullable()();
  BoolColumn get isTag => boolean().withDefault(const Constant(false))();
  TextColumn get tagId => text().nullable().references(Tags, #id)();
  RealColumn get positionX => real().nullable()();
  RealColumn get positionY => real().nullable()();
  BoolColumn get collapsed => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get parentId => text().nullable().references(Tasks, #id)();
  TextColumn get title => text().withLength(min: 1, max: 300)();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('todo'))();
  IntColumn get priority => integer().withDefault(const Constant(1))();
  IntColumn get estimateMinutes => integer().nullable()();
  IntColumn get dueAt => integer().nullable()();
  IntColumn get remindAt => integer().nullable()();

  /// v2 (Thread events): expected time, soft constraint.
  IntColumn get expectedAt => integer().nullable()();

  /// v3: moment the user actually started this event. Together with
  /// `completed_at` it yields the actual duration - no ticking timer is ever
  /// run (blueprint 2.6).
  IntColumn get startedAt => integer().nullable()();

  /// v2 (Thread events): required energy 1-10; NULL = algorithm ignores it.
  IntColumn get energyRequired => integer().nullable()();

  /// v2: completion moment (convenience; authority is CompletionLogs).
  IntColumn get completedAt => integer().nullable()();

  /// v47（2026-11-15，ThreadFlow 整合底座）：节点种类。
  ///
  /// 词表 `task` / `paper` / `week` / `day` / `review`（域层
  /// `ThreadNodeKind`）。可空、**迁移不回填**：NULL 读作 `task`，所以老库的
  /// 每一行语义不变；物化器新建计划节点时才需要显式写 `paper`/`week`/`day`/
  /// `review`。调度入口仍然只有 `ThreadRankService`，这张列只用来区分节点，
  /// 不新建第二张计划表。
  TextColumn get kind => text().nullable()();

  /// v47（2026-11-15）：物化幂等键（`paper:{QSET id}` / `week:2026-W47` /
  /// `day:2026-11-15` / `practice:{Q id}:2026-11-15` …）。
  ///
  /// 可空、**迁移不回填**：老库全部 NULL（SQLite 唯一索引允许多个 NULL）。
  /// 唯一索引 `idx_tasks_source_key` 由 database.dart 建（不是 Drift 的
  /// `uniqueKeys`：ALTER TABLE 无法给已存在的表补表级约束，必须建独立索引，
  /// 这样迁移、onCreate、beforeOpen 自愈三条路都走同一句
  /// `CREATE UNIQUE INDEX IF NOT EXISTS`）。物化器必须"查 source_key → 复用/
  /// 更新，不存在才插入"，绝不无条件 insert。
  TextColumn get sourceKey => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class TaskDependencies extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text().references(Tasks, #id)();
  TextColumn get dependsOnTaskId => text().references(Tasks, #id)();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {taskId, dependsOnTaskId},
      ];
}

class TimeBlocks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 300)();
  IntColumn get startAt => integer()();
  IntColumn get endAt => integer()();
  TextColumn get repeatRule => text().nullable()();
  BoolColumn get available => boolean().withDefault(const Constant(true))();
  TextColumn get energy => text().nullable()();
  TextColumn get suitableFor => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class TaskTimeBlocks extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text().references(Tasks, #id)();
  TextColumn get timeBlockId => text().references(TimeBlocks, #id)();
  BoolColumn get isSuggestion => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {taskId, timeBlockId},
      ];
}

class KnowledgePoints extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 300)();
  TextColumn get content => text()();

  /// v2: `plain` / `markdown` (NULL legacy rows read as plain).
  TextColumn get contentFormat => text().nullable()();

  TextColumn get source => text().nullable()();
  TextColumn get externalId => text().nullable()();
  TextColumn get packageId => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CardTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get knowledgePointId => text().references(KnowledgePoints, #id)();
  TextColumn get type => text()();
  TextColumn get question => text()();
  TextColumn get answer => text()();
  TextColumn get options => text().nullable()();
  TextColumn get clozeTemplate => text().nullable()();
  TextColumn get hint => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get externalId => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CardStates extends Table {
  TextColumn get id => text()();
  TextColumn get cardTemplateId =>
      text().references(CardTemplates, #id).nullable()();
  IntColumn get dueAt => integer().nullable()();
  RealColumn get intervalDays => real().withDefault(const Constant(0))();
  RealColumn get ease => real().withDefault(const Constant(2.5))();
  IntColumn get repetitions => integer().withDefault(const Constant(0))();
  IntColumn get lapses => integer().withDefault(const Constant(0))();
  TextColumn get state => text().withDefault(const Constant('new'))();
  IntColumn get lastReviewedAt => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  // --- v2: presentation unit + FSRS + forced-binding fields ---

  /// v2: owning knowledge point (backfilled from card template in v1 to v2
  /// migration; code always writes non-null for new rows).
  TextColumn get knowledgePointId =>
      text().references(KnowledgePoints, #id).nullable()();

  /// v2: presentation unit key unique within a knowledge point:
  /// `preset:{templateId}` | `cloze:{slotId}` | `essay:{kpId}`.
  TextColumn get unitKey => text().nullable()();

  /// v2 FSRS state.
  RealColumn get stability => real().nullable()();
  RealColumn get difficulty => real().nullable()();

  /// v6: encoding strength / encoding ceiling (MindNet `R0`).
  ///
  /// FSRS as implemented here has no separate ceiling: its curve returns an
  /// absolute retrievability, while MindNet's is `R = R0 * Psi(t/S)`. Porting
  /// the cognitive model therefore needs R0 stored, otherwise the two curves
  /// silently disagree once `R0 < 1` (see docs/MINDNET_CONTRACT.md 8.1).
  /// Nullable: NULL means "never set", not 1.0, so legacy rows stay honest.
  RealColumn get encodingStrength => real().nullable()();

  /// v6: savings effect (MindNet `Sigma`), used by the stability-increase term.
  /// Nullable for the same reason as [encodingStrength].
  RealColumn get savings => real().nullable()();

  /// v2 forced-binding state (wrong-answer rule): 1 while a short-interval
  /// (10 min) relearning loop with the same unit is active.
  IntColumn get forced => integer().withDefault(const Constant(0))();

  /// v2: consecutive correct answers while forced; releases at 2.
  IntColumn get forcedStreak => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {cardTemplateId},
      ];
}

class ReviewLogs extends Table {
  TextColumn get id => text()();
  TextColumn get cardStateId => text().references(CardStates, #id)();
  TextColumn get cardTemplateId =>
      text().references(CardTemplates, #id).nullable()();

  /// v2: unit key snapshot at review time.
  TextColumn get unitKey => text().nullable()();

  /// v1 legacy rating: 0=forgot 1=fuzzy 2=remembered.
  IntColumn get rating => integer()();

  /// v2 FSRS rating: 1=Again 2=Hard 3=Good 4=Easy.
  IntColumn get ratingFsrs => integer().nullable()();

  /// v2: auto-graded correctness 0/1 (nullable for self-judged attempts).
  IntColumn get correct => integer().nullable()();

  /// v2 judging mode: `auto` (strict char comparison) / `self`.
  TextColumn get judgeMode => text().nullable()();

  /// v2 presented form: mcq / mcq_multi / ordered_multi / fill / essay.
  TextColumn get format => text().nullable()();

  /// v2 answer time in ms.
  IntColumn get msTaken => integer().nullable()();

  /// v9: did the user read the expected answer/solution after a failed recall?
  ///
  /// This is MindNet's `reviewed_solution` (`docs/IO_PROTOCOL.md` §2.3): the
  /// same wrong answer is two different events depending on it - a bare miss
  /// (`lapse`, S drops) or a learning event (`retrieval_failure_feedback`,
  /// whose S gain grows with [closeness]). NULL means "not asked or not
  /// applicable" (every right answer, and rows written before v9), never
  /// "false by default": the two paths must stay distinguishable after the
  /// fact instead of being silently flattened into one.
  BoolColumn get reviewedSolution => boolean().nullable()();

  /// v9: how close the failed recall was, in `(0, 1)`, when
  /// [reviewedSolution] is true.
  ///
  /// MindNet's `closeness = x_v / C_v` (`docs/MODEL_v2_MATH.md` §3): the
  /// stability gain of a failure-feedback event is multiplied by exactly this
  /// number, so it is stored verbatim rather than folded into a boolean.
  /// NULL whenever the event was not a failure-feedback one.
  RealColumn get closeness => real().nullable()();

  /// v11: the model's `R` for this card **at the moment of the review, before
  /// the grade existed**.
  ///
  /// This is what makes the calibration curve honest: a prediction recomputed
  /// after the fact from the post-review state would be grading the model on an
  /// answer it already knew (`docs/ASSESSMENT_DESIGN.md` §7 M6). NULL for every
  /// row written before v11 and for reviews where the advisor was unavailable -
  /// "no prediction" and "predicted 0.5" are different facts.
  RealColumn get predictedR => real().nullable()();

  IntColumn get reviewedAt => integer()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// v14: one "I read it, but I did not test myself" event - MindNet's `exposure`.
///
/// `docs/IO_PROTOCOL.md` §2.2 lists five actions, and this is the only one the
/// app had no way to produce: reading an answer is **not** a retrieval attempt,
/// so the model must not be told that it was. MindNet records it as
/// `kernel.review(node, {type: 'reread'})` - its own event type whose stability
/// gain is scaled by `kappa_reread_ratio` (0.1 by default, "再读只有十分之一的
/// 增益") and which leaves `R0` alone, unlike `retrieval_success`.
///
/// It is a **separate table on purpose**: `review_logs` is the *test* record,
/// and the retention buckets and the calibration curve are computed from it
/// (`docs/ASSESSMENT_DESIGN.md` §7 M6). An exposure has no grade and no
/// outcome, so storing it there would need a fabricated `rating` (the column is
/// NOT NULL) and would let "看了没测" count as a successful recall.
class ExposureLogs extends Table {
  TextColumn get id => text()();

  TextColumn get cardStateId => text().references(CardStates, #id)();

  /// Where the reading happened. `answer_reveal` is the review screen's
  /// "读过，没测自己" press (the only producer today).
  ///
  /// It is required, not nullable: a row whose origin is unknown cannot be
  /// re-read years later, and the roadmap's material intake (INGEST /
  /// TRANSCRIBE) will write its own values here.
  TextColumn get source => text()();

  /// Wall-clock moment of the reading, ms since epoch - the same clock
  /// `review_logs.reviewed_at` uses, so the two tables can be read together.
  IntColumn get exposedAt => integer()();

  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class KnowledgePackages extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 300)();
  TextColumn get version => text().withLength(min: 1, max: 50)();
  TextColumn get author => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().nullable()();
  IntColumn get importedAt => integer()();
  TextColumn get fileHash => text().nullable()();

  /// v42（2026-11-01）：知识包启用/禁用位。可空、NULL 读作「启用」；
  /// 只有知识库管理页会写它，已经导入的内容行不受影响。
  BoolColumn get enabled => boolean().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PackageItems extends Table {
  TextColumn get id => text()();
  TextColumn get packageId => text().references(KnowledgePackages, #id)();
  TextColumn get objectType => text()();
  TextColumn get objectId => text()();
  TextColumn get externalId => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {packageId, objectType, objectId},
      ];
}

// ============================================================================
// v2 tables: added in schema 1 -> 2.
// ============================================================================

/// Single-row Thread status bar state: current energy & main goal
/// (spec 1.1.3). Row id is always 1.
class ThreadStates extends Table {
  IntColumn get id => integer()();
  IntColumn get energy => integer().nullable()();
  TextColumn get goalText => text().nullable()();
  TextColumn get goalNodeId => text().nullable()();
  TextColumn get goalPath => text().nullable()();
  IntColumn get updatedAt => integer().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Reusable event creation templates (spec 1.1.4): default duration, energy
/// requirement and (via ObjectTags `task_template`) default tags.
class TaskTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  IntColumn get estimateMinutes => integer().nullable()();
  IntColumn get energyRequired => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Completion history (spec 2 Thread-to-History loop): snapshot written whenever a
/// task is completed. Powers the fatigue penalty and Knowledge context.
class CompletionLogs extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text().references(Tasks, #id)();
  TextColumn get title => text().withLength(min: 1, max: 300)();
  TextColumn get tagIds => text().nullable()();
  TextColumn get tagPaths => text().nullable()();
  IntColumn get estimateMinutes => integer().nullable()();
  IntColumn get energyRequired => integer().nullable()();
  IntColumn get completedAt => integer()();

  /// v3 (blueprint 2.6): completion moment - start moment, whole minutes.
  IntColumn get actualMinutes => integer().nullable()();

  /// v3: whether the user lets this record feed the duration model. A record
  /// that looks interrupted defaults to false but stays switchable.
  BoolColumn get includeInModel =>
      boolean().withDefault(const Constant(true))();

  /// v3: set when the anomaly rule flagged the record (kept for transparency).
  BoolColumn get durationSuspicious =>
      boolean().withDefault(const Constant(false))();

  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Single-row Thread ranking parameters (blueprint P5: no hidden parameters).
/// Every weight is user-visible and editable from the event property page.
class ThreadRankSettings extends Table {
  IntColumn get id => integer()();
  RealColumn get wUrgency => real().withDefault(const Constant(0.4))();
  RealColumn get wGoal => real().withDefault(const Constant(0.3))();
  RealColumn get wFit => real().withDefault(const Constant(0.2))();
  RealColumn get wFatigue => real().withDefault(const Constant(0.1))();
  RealColumn get wExpected => real().withDefault(const Constant(0.05))();

  /// Whether the Thread status bar is collapsed (blueprint 2.2).
  BoolColumn get headerCollapsed =>
      boolean().withDefault(const Constant(false))();

  /// Global switch: may actual durations update the duration model?
  BoolColumn get useActualTime => boolean().withDefault(const Constant(true))();

  /// v16: 认知排序档位开关（`docs/MINDNET_ROADMAP.md` §2-D）。
  ///
  /// 默认**关**：现有加权排序的权重分是用户自己在事件属性页上定的，而认知排序的
  /// 距离/精力加成全部 `[未标定]`；一个还没标定的次序不该默认替掉用户已经看惯的列表。
  /// 打开之后次序里会带 `uncalibrated`，UI 必须如实标出来。
  BoolColumn get cognitiveRankEnabled =>
      boolean().withDefault(const Constant(false))();

  IntColumn get updatedAt => integer().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One line of the daily "what went wrong today" study ledger shown in the
/// separate review-insight screen (blueprint 4.4, user annotation 19).
///
/// The review screen itself stays free of any statistics so the user can reach
/// flow; everything analytical lands here, keyed by local day.
class DiffusionLogs extends Table {
  TextColumn get id => text()();
  TextColumn get ownerType => text()();

  /// `event` | `knowledge`.
  TextColumn get ownerId => text().nullable()();
  TextColumn get ownerTitle => text().nullable()();

  /// `wrong` (a blank/event went wrong) | `boost` (a related item got lifted)
  /// | `release` (a boost expired).
  TextColumn get kind => text()();

  /// Related knowledge point, when this line is about graph diffusion.
  TextColumn get knowledgePointId => text().nullable()();
  TextColumn get knowledgePointTitle => text().nullable()();

  /// Graph distance from the item that went wrong (1 or 2).
  IntColumn get distance => integer().nullable()();

  /// Boost factor applied (1.8 / 1.3), when [kind] == 'boost'.
  RealColumn get factor => real().nullable()();

  /// The text that was blanked / the correct answer, for the ledger.
  TextColumn get detail => text().nullable()();

  /// Local day key `yyyy-MM-dd` so the ledger can be grouped by day without
  /// timezone ambiguity.
  TextColumn get dayKey => text()();

  IntColumn get occurredAt => integer()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Structured cloze position within a knowledge point's content
/// (spec 1.3.1/1.3.2). `definition` is JSON locating the blankable span.
class ClozeSlots extends Table {
  TextColumn get id => text()();
  TextColumn get knowledgePointId => text().references(KnowledgePoints, #id)();
  TextColumn get slotKey => text()();
  TextColumn get definition => text()();
  IntColumn get exhausted => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {knowledgePointId, slotKey},
      ];
}

/// Cloze usage history: which slot was drawn and whether the answer was
/// correct. "New blank = never drawn before" is decided against this table.
class ClozeHistory extends Table {
  TextColumn get id => text()();
  TextColumn get knowledgePointId => text().references(KnowledgePoints, #id)();
  TextColumn get slotKey => text()();
  IntColumn get correct => integer().withDefault(const Constant(0))();
  IntColumn get usedAt => integer()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Mindnet graph-diffusion boost entries (spec 1.3.3): written when a card is
/// answered wrong; decays after `remainingCycles` draw cycles.
class BoostEntries extends Table {
  TextColumn get id => text()();
  TextColumn get knowledgePointId => text().references(KnowledgePoints, #id)();
  RealColumn get factor => real()();
  IntColumn get remainingCycles => integer().withDefault(const Constant(3))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {knowledgePointId},
      ];
}

/// Appearance themes (spec 4). `payload` is JSON; built-in rows are sealed.
///
/// Data class is named `ThemeProfile` (not `Theme`) to avoid clashing with
/// Flutter's material Theme widget.
@DataClassName('ThemeProfile')
class Themes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  IntColumn get isBuiltin => integer().withDefault(const Constant(0))();
  TextColumn get payload => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Attachments stored under the internal app directory (rich-text images,
/// background images, theme files). Referenced by .tfpkg export.
class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get ownerType => text()();
  TextColumn get ownerId => text()();
  TextColumn get relPath => text()();
  TextColumn get mime => text().nullable()();

  /// 同一个主人（`ownerType` + `ownerId`）下的显示顺序，0 起。
  ///
  /// v24（轮次一百二十一）加的：一道题可以有多张图（拍照、截图、印刷页），
  /// 列表要按用户添加的先后展示，不能靠 `createdAt` 撞毫秒。其它 owner
  /// （AI 消息、拍照整理）不写这一列，落默认 0，语义与以前一致。
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// 这张图在题目里是什么角色（v27，轮次一百三十四）。
  ///
  /// - NULL：v27 之前写下的旧行，或其它 owner 的附件；读侧一律按
  ///   [QuestionImageRole.stem]（题干配图）处理，旧题库看起来不变。
  /// - 'stem'：题干配图（拍照的题干、印刷页截图）。
  /// - 'answer'：答案/解析截图。组卷网登录后才看得到的答案是一整张 JPEG，
  ///   用户截图/拍照存进来，导出 Word 时渲染在解析之后。
  /// - 'solution'：预留给以后的「独立解析截图」，本轮没有写入方。
  ///
  /// 只有题目（`ownerType = 'question'`）用这一列；其它 owner 不写，落 NULL。
  TextColumn get role => text().nullable()();

  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ============================================================================
// v4 tables: Time module views (user feedback item 3).
// ============================================================================

/// Weekly / daily schedule templates, so a whole week or day of blocks can be
/// laid down in one action (user feedback 3: "周模板日模板快速完成日程块设置").
///
/// `payload` is JSON so the block shape can grow without another migration:
///   {"blocks":[{"title":"早读","start":"07:00","end":"07:40",
///               "available":false,"color":3,"repeatRule":"{\"type\":\"daily\"}"}]}
/// For [kind] == 'week' each block may also carry `"dows":[1,2,3,4,5]`.
@DataClassName('TimeTemplate')
class TimeTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();

  /// `day` | `week`.
  TextColumn get kind => text()();
  TextColumn get payload => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Single-row Time module view preferences: how long the long-range timeline
/// spans and how it is zoomed / folded (user feedback 3).
class TimeViewSettings extends Table {
  IntColumn get id => integer()();

  /// Total length of the multi-year timeline, in days.
  IntColumn get timelineSpanDays =>
      integer().withDefault(const Constant(730))();

  /// Horizontal zoom of the timeline: pixels per day.
  RealColumn get timelinePxPerDay => real().withDefault(const Constant(6))();

  /// Folded = the timeline wraps and scrolls vertically; unfolded = one row
  /// that scrolls horizontally.
  BoolColumn get timelineCollapsed =>
      boolean().withDefault(const Constant(false))();

  /// Last used minutes-per-row for the day/week grids (15 / 30 / 60).
  ///
  /// Defaults to 30: a whole-hour grid hides half-hour boundaries, so the
  /// finer grid is the default and the user zooms out when they want to.
  IntColumn get minutesPerRow => integer().withDefault(const Constant(30))();

  /// True once the user picked a row size themselves. Only used so the
  /// v4 -> v5 migration can move everyone who never chose off the old
  /// 60-minute default without touching a deliberate choice.
  BoolColumn get minutesPerRowChosen =>
      boolean().withDefault(const Constant(false))();

  /// v36（轮次一百七十五）：日/周网格每小时的像素高度（连续缩放后的自由行高）。
  ///
  /// NULL 读作「用户没拖过」——行高由 [minutesPerRow] 按旧公式推出来，行为与这一列
  /// 存在之前逐字节相同。一旦用户拖动过分界线就写入具体值，所有档位共用同一个
  /// 每小时高度。迁移绝不回填。
  RealColumn get hourHeight => real().nullable()();

  IntColumn get updatedAt => integer().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// v6: AI integration (see docs/AI_DESIGN.md)
//
// The conversation is the primary AI surface, so it is stored like any other
// user data - which also means `.tfpkg` already carries it (the package dumps
// every table found in sqlite_master, no extra work).
//
// The API key lives in LocalSettings, NOT here: it is a single-row setting,
// matching how the active theme id is stored. Note that it therefore travels
// inside `.tfpkg` too; the export UI warns about that.
// ---------------------------------------------------------------------------

/// One AI conversation. Title is generated from the first user message.
class AiConversations extends Table {
  TextColumn get id => text()();

  /// Human label shown in the conversation list. Never empty: falls back to a
  /// timestamp when the first message is empty.
  TextColumn get title => text().withLength(min: 1, max: 200)();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  /// The agent preset chosen while this conversation was blank.
  ///
  /// NULL on rows created before presets existed; the read side resolves NULL
  /// to `assistant`, so an upgraded database keeps the old behaviour. The value
  /// is immutable once the conversation has a message (see
  /// `AiRepository.setConversationPresets`); there is deliberately no
  /// `preset_version` / `preset_hash` / `locked_at` column - the preset is a
  /// live definition resolved by id, exactly like DSH.
  TextColumn get agentPresetId => text().nullable()();

  /// The preset a subagent session is started with.
  ///
  /// NULL means "inherit the parent session's preset".
  TextColumn get subagentPresetId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One message in a conversation.
///
/// `role` is the provider-facing role (`user` | `assistant` | `tool` | `system`).
/// Tool *calls* are not stored as their own rows here: the model's request and
/// the local execution are two different things (a request can be rejected), so
/// the execution side lives in [AiActions] where it can carry a status.
class AiMessages extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text().references(AiConversations, #id)();

  /// `user` | `assistant` | `tool` | `system`.
  TextColumn get role => text()();

  /// Message body. For `tool` rows this is the JSON result handed back to the
  /// model; for `assistant` rows it may be empty when the turn was pure tool
  /// calls.
  TextColumn get content => text().nullable()();

  /// Provider tool-call id, only set on `tool` rows. Needed because the Chat
  /// Completion API rejects a tool result whose id does not match the request
  /// that produced it.
  TextColumn get toolCallId => text().nullable()();

  /// The model's chain of thought for this message, when the provider streams
  /// one (`reasoning_content` / `reasoning` / thinking parts). Only `assistant`
  /// rows carry it; NULL = 这次生成没有思考文本（老库的行也是 NULL）。
  /// docs/REVIEW_FEEDBACK.md §4a：思考过程要留在历史里折起来看，而不是只活在
  /// 生成中的那几秒。
  TextColumn get reasoning => text().nullable()();

  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Audit + approval ledger for every tool call the model proposed.
///
/// Why this is separate from [AiMessages]: the approval engine needs a durable
/// record that survives a rejected or failed call, and the undo feature needs
/// the before/after snapshots. A tool whose snapshot cannot be taken reliably
/// is marked `reversible = false` and is never auto-executed (AI_DESIGN D13b).
class AiActions extends Table {
  TextColumn get id => text()();

  /// The assistant message whose turn proposed this call.
  TextColumn get messageId => text().nullable()();

  TextColumn get conversationId => text().references(AiConversations, #id)();

  /// Provider-side call id, so a result can be matched back.
  TextColumn get toolCallId => text().nullable()();

  TextColumn get toolName => text()();

  /// Raw JSON arguments exactly as the model produced them. Kept verbatim so a
  /// failed validation can be shown to the user and replayed.
  TextColumn get argsJson => text()();

  /// `write` | `destructive` (mirrors ToolRisk).
  TextColumn get risk => text()();

  /// `pending` | `approved` | `rejected` | `executed` | `failed`.
  TextColumn get status => text()();

  /// Row(s) as they were before the call, JSON. Enables undo.
  TextColumn get beforeJson => text().nullable()();

  /// Row(s) as they became, JSON.
  TextColumn get afterJson => text().nullable()();

  /// Failure reason, or the human-readable result summary.
  TextColumn get resultJson => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ============================================================================
// v8: per-group daily review plan ("每天各个卡组的任务量").
// ============================================================================

/// One card group's daily target.
///
/// A "卡组" is a **tag**: the tag tree is the app's only grouping of knowledge
/// points (`ObjectTags` links `knowledge_point` objects to tags, and
/// `tag_repository.getTagsUnderPath` already treats `a/b` as covering its whole
/// path prefix). A group therefore means "this tag and, because the plan is
/// about a subject rather than one leaf, every tag under it" - the same
/// subtree reading `TagDiffusion` and `getTagsUnderPath` already use.
///
/// One row per tag, created only when the user actually sets a target: an empty
/// table is what "nothing is configured" looks like, and that state must leave
/// today's behaviour (no cap at all) untouched. A tag with no row has no limit.
@DataClassName('ReviewGroupPlan')
class ReviewGroupPlans extends Table {
  TextColumn get id => text()();

  /// The group's tag. Keyed by tag *id*, never by path: `TagRepository` rewrites
  /// every descendant's `path` in cascade on rename/move, so a plan keyed by
  /// path would silently point at a different (or no) group after a rename.
  /// `deleteTag` removes the whole subtree, so the cascade here is what keeps
  /// plans from outliving their group.
  TextColumn get tagId => text().references(Tags, #id)();

  /// New cards allowed per day. 0 means "no new cards from this group today".
  ///
  /// The column is NOT NULL with a 0 default so a freshly created row always has
  /// a number to enforce; "never configured" is the absence of the row, not a
  /// NULL inside it.
  IntColumn get newCardsPerDay => integer().withDefault(const Constant(0))();

  /// Reviews allowed per day. 0 means unlimited - see
  /// `ReviewGroupPlan.isReviewCapped`, which also spells out why 0 cannot mean
  /// "no reviews" in this schema.
  IntColumn get reviewCardsPerDay => integer().withDefault(const Constant(0))();

  /// v43（2026-11-02）：这个卡组（标签子树）的判分方式。
  ///
  /// 可空、NULL = 跟随全局默认（自判）。目前只认 "strict"（自动判分）；
  /// 其它值由读侧按默认处理，不回填。
  TextColumn get judgeMode => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {tagId},
      ];
}

/// 一轮测评的会话。`docs/ASSESSMENT_DESIGN.md` §5 的 M1b。
///
/// 一次测评是一个**测量事件**：用户开始做某个 instrument 时开一条，做完关一条。
/// 这一行本身不带分数——每一步的证据在 `assessment_responses` 里，因为一轮里
/// 每步的证据强弱不同（自评是主观的，抽检是客观的），压成一行就把区别丢了。
@DataClassName('AssessmentSession')
class AssessmentSessions extends Table {
  TextColumn get id => text()();

  /// 科目键（`physics` / `chinese` / …），空串表示不分科。
  ///
  /// 分板块是用户定下的口径：物理和语文不能用同一套 instrument，所以"这轮测的
  /// 是哪个板块"必须落进数据，否则以后无法按板块回看和校准。
  TextColumn get subjectKey => text().withDefault(const Constant(''))();

  /// 本轮覆盖的标签范围（JSON 数组，tag id）。空数组表示整库。
  ///
  /// 存 id 而不是路径：`TagRepository` 改名会重写所有后代的 `path`，路径在这里
  /// 会像 `review_group_plans` 的旧设计一样指到别人身上。
  TextColumn get scopeTagIds => text().withDefault(const Constant('[]'))();

  IntColumn get startedAt => integer()();

  /// 结束时间；NULL 表示这一轮还没做完（中途退出）。
  IntColumn get finishedAt => integer().nullable()();

  /// 预算（JSON：题数 / 分钟）。NULL 表示没设预算。
  TextColumn get budget => text().nullable()();

  TextColumn get note => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 测评里的一步、以及这一步留下的证据。
///
/// 追加型日志（同步三分类里的"只追加"）：写进去就不再改。自评的 `self_rating`
/// 与抽检的 `correct` 是两个列而不是一个"分数"列，因为"我觉得我会"和"我真的
/// 答对了"是两种证据，`AssessmentPrior` 正是靠它们之差算校准偏置。
@DataClassName('AssessmentResponse')
class AssessmentResponses extends Table {
  TextColumn get id => text()();

  /// 所属会话。会话删了，它的步骤就没有意义，所以级联删除是这里的正确语义。
  ///
  /// 但**不能指望数据库**：本项目的生成 schema 不带外键约束（实测，连 v2 就有的
  /// `review_logs` 也没有），`references(...)` 只是意图声明。清理由
  /// `AssessmentRepository.deleteSession` 显式完成。
  TextColumn get sessionId => text().references(AssessmentSessions, #id)();

  /// 这一步针对的知识点；NULL 表示不属于任何点（整卷性提示之类）。
  ///
  /// 可空是有意的：一轮测评可以包含不落在某个知识点上的步骤，把这类步骤硬塞
  /// 一个知识点会让先验估计多出无中生有的样本。
  TextColumn get knowledgePointId =>
      text().nullable().references(KnowledgePoints, #id)();

  /// 步骤类型：`self_report` / `recall` / `objective`。
  TextColumn get stepKind => text()();

  TextColumn get prompt => text().nullable()();
  TextColumn get answer => text().nullable()();

  /// 客观对错的判分；NULL 表示这一步没有客观判分（自评就没有）。
  BoolColumn get correct => boolean().nullable()();

  /// 自评：0–5 的 JOL（"你觉得自己会多少"）。NULL 表示没问。
  IntColumn get selfRating => integer().nullable()();

  /// 作答时的把握程度 0–5，与 `selfRating` 分开：一个问"会多少"，一个问
  /// "多确定"。首版两个都收，先只把 `selfRating` 喂给先验层。
  IntColumn get confidence => integer().nullable()();

  IntColumn get elapsedMs => integer().nullable()();

  /// 谁判的：`self` / `ai` / `auto`。首版全部是 `self`（用户口径①自评起步）。
  TextColumn get judgedBy => text().withDefault(const Constant('self'))();

  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 测评产出的**先验**，与复习观测分离（设计文档 §5、§8）。
///
/// 不写进 `card_states`：那里只放复习行为长出来的状态，先验只是"还没复习时的
/// 起点"。合并规则是读模型时"有观测用观测、无观测用先验"，所以整张表都可以随时
/// 重算——它也是同步三分类里的"派生（可重算）"，不参与跨设备合并。
///
/// 主键是 `(knowledge_point_id, source)` 而不是自增 id：同一知识点来自不同信号
/// （自评 / 抽检）的先验是两行，谁也不能覆盖谁；重算同源先验则是一次 upsert。
@DataClassName('CognitivePrior')
class CognitivePriors extends Table {
  TextColumn get knowledgePointId => text().references(KnowledgePoints, #id)();

  /// 先验来源，形如 `assessment:self` / `assessment:objective` /
  /// `assessment:blended`。
  TextColumn get source => text()();

  /// 编码强度上限先验（MindNet `R0`）。
  RealColumn get r0 => real()();

  /// 难度先验（MindNet `D`，FSRS 量纲 1–10）。只有客观抽检能给，否则 NULL。
  RealColumn get d => real().nullable()();

  /// 主观流畅度先验（元认知信念的输入 `f`），0–1。没自评时为 NULL。
  RealColumn get fluency => real().nullable()();

  /// 样本数（抽检题数 + 有自评则 1）。
  IntColumn get n => integer().withDefault(const Constant(0))();

  /// 是否经过真实数据标定。设计文档 §2 的口径是"全部未标定"，所以默认 0；
  /// 写 1 意味着这个数不再是显式选定的粗映射。
  IntColumn get calibrated => integer().withDefault(const Constant(0))();

  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {knowledgePointId, source};
}

/// 题库里的题目实体（`docs/QUESTION_BANK_DESIGN.md` §1）。
///
/// 来源的价值在**选择与加工**，不在数量：能进来的只有高价值题（高考真题 /
/// 强省强市诊断 / 名校测试），每条带来源分级，排序时低价值题只压后、不删。
///
/// `state` 是加工进度（raw → structured → processed），不是质量评价；质量在
/// `aiQuality`。题目入库后只追加：id 稳定、不原地改语义（同步三分类的"只追加"）。
@DataClassName('Question')
class Questions extends Table {
  TextColumn get id => text()();

  /// 人可读的题目编号（v24，轮次一百二十一）：**跨学科一个序列**，1 起分配，
  /// 显示成 `TR-00001`（见 `domain/services/questions/question_number.dart`）。
  ///
  /// 为什么不拿 [id] 当编号：id 是 `q-<uuid>`，给人看太长、背不住、写不上纸。
  /// 编号要短、要稳、要能在错题本上抄。可空是为了兼容三件事：老文件升级
  /// （迁移里回填）、v23 及更早的 `.tfpkg` 包（导入后
  /// `AppDatabase.backfillQuestionSerialNumbers` 补）、以及 append 导入。
  /// NULL 的含义是"还没编号"，界面上显示占位，不是 0 号。
  IntColumn get serialNo => integer().nullable()();

  /// 题名（v30，轮次一百三十九）：用户自己起的名字，或域层自动生成的短名。
  ///
  /// 为什么不从题干现算：题库总览要按名字扫读、还要能重命名——题干前 20 字
  /// 常常是同一种题型的相同开头（"已知函数 f(x)…"），扫读时全是重影。
  /// 列存下来才有“稳定、可改、可去重”的语义；自动生成只是**填空**，
  /// 填过之后用户改过就不再自动覆盖。可空表示“还没名字”，界面回落题干摘要。
  /// 长度与合法性由域层纯逻辑 `question_title_suggestion.dart` 把关，
  /// 仓库只 trim、空串写 NULL（与 `source_url` 同一契约），不在这里做长度截断。
  TextColumn get title => text().nullable()();

  /// 题干（纯文本；公式保留 LaTeX 原样）。
  TextColumn get stem => text()();

  /// 参考答案。可空：收题时可以只存题干，答案后补。
  TextColumn get answer => text().nullable()();

  /// 解析文本。AI 解题产出的**思维链**另存 `reasoning_chains`，不挤在这一列。
  TextColumn get solution => text().nullable()();

  /// 学科，例如 `physics` / `chinese`。自由字符串，界面用标签树展示。
  TextColumn get subjectKey => text().withDefault(const Constant(''))();

  /// `single_choice` / `multi_choice` / `fill_blank` / `solution` / `open`。
  TextColumn get questionType =>
      text().withDefault(const Constant('solution'))();

  /// 来源分级（决定排序权重与去重保留优先级）：`gaokao` 高考真题 /
  /// `provincial_diagnostic` 强省强市诊断 / `elite_school` 名校测试 /
  /// `school` 学校题 / `personal` 自建 / `unknown` 未标注。
  TextColumn get sourceLevel => text().withDefault(const Constant('unknown'))();

  /// 人可读来源，例如"2024 湖南师大附中月考"。
  TextColumn get sourceLabel => text().withDefault(const Constant(''))();

  IntColumn get year => integer().nullable()();
  TextColumn get region => text().nullable()();

  /// 题目在外部站点（现在只有组卷网）的来源页链接（v26，轮次一百二十九）。
  ///
  /// 为什么要存 URL 而不只存人读的来源文字：定点找题是「链接去、题回来」，
  /// 回来以后人还得能点回去核对原题与答案图；`sourceLabel` 写的是出处文字
  /// （"2024 湖南师大附中月考"），它可能抄错，URL 是唯一可复查的锚点。
  /// 可空：手写收题、拍照识别、自建题都没有外部来源。
  TextColumn get sourceUrl => text().nullable()();

  /// 组卷网的题目 id（URL 里 `<bankid>q<questionid>.html` 的 questionid）。
  ///
  /// 留着它就能**重建**详情页/答案页链接，也能按 qid 去重——比题干指纹更硬
  /// （同一道题换排版、题干少一个字都可能换指纹）。可空：非组卷网来源。
  TextColumn get zujuanQuestionId => text().nullable()();

  /// 组卷网的学科 bankid（URL 里 `<bankid>q<questionid>.html` 的 bankid）。
  ///
  /// bankid 决定站点按哪个学科解释链接，缺了它拼出来的链接会落到别的学科
  /// （站点按 bankId 静默过滤，错学科 0 条）。所以宁可两列都存、也不从
  /// questionid 猜。可空同上。
  TextColumn get zujuanBankId => text().nullable()();

  /// 题干/答案/解析的文本格式（v40，轮次一百八十二，handoff 管线 v1 §7 M1）。
  ///
  /// 值只有两个：`plain` 与 `markdown`；NULL 读作 `plain`（历史题目全走这条）。
  /// 为什么存一列而不是「检测到 `$` 就自动切」：渲染方式决定**整个题目区**的
  /// 排版（表格、列表、代码块、双美元块公式），靠启发式猜会把普通文本里的
  /// 美元符号误判成公式，也会让同一道题在两次打开时排版不一致。入库时定死，
  /// 渲染器只读这一列。`.tqb` 里的 `text_format` 字段与它同名同语义。
  TextColumn get textFormat => text().nullable()();

  /// 扩展题挂靠的母题组卷网题目 id（v40，handoff §7 M2）。
  ///
  /// 语义只是「指向某道母题的 `zujuan_question_id`」：不建外键、不要求母题在
  /// 同一个包里，悬空引用由域层 `question_extension.dart` 忽略并计数，不阻断
  /// 导入。为什么不用内部 `questions.id`：题库包在别的机器上解出来时本地 id
  /// 全变了，只有组卷网题号能跨设备对应。可空 = 不是扩展题。
  TextColumn get extensionOf => text().nullable()();

  /// 能力点代码数组（v40，handoff §7 M2）：`A1`…`A10`，存 JSON 数组字符串
  /// 例如 `["A3","A7"]`。
  ///
  /// 为什么不像标签那样单独建关联表：能力点是**题目的固有属性**（由题干+解析
  /// 就能判定），数量少（≤10）、需要整组读写（T×A 统计一次要全量），单独建表
  /// 只会多一层 join；JSON 列在这里是合适的（与 `settings` 的用法一致）。NULL
  /// 读作空数组 = 未标注，不回填：宁可显示「未标注」也不猜。
  TextColumn get capability => text().nullable()();

  /// 难度 1–10，可空。优先写认知模型的难度先验，否则写 AI 估计。
  RealColumn get difficulty => real().nullable()();

  /// 上面那个难度是谁给的：`prior` / `ai` / `manual`。没有难度时 NULL。
  TextColumn get difficultySource => text().nullable()();

  /// 题干指纹（去空白 + 标点归一的 FNV-1a 64 位十六进制，纯 Dart 实现）。
  /// 只挡"完全同一道题"；近似重复留给后续按考点链找相似题。
  TextColumn get stemFingerprint => text().withDefault(const Constant(''))();

  /// 易错点/常见错因（加工产物，可空）。
  TextColumn get trapNote => text().nullable()();

  /// `raw` 刚收进来 / `structured` 已结构化 / `processed` 已拆链并标注错因。
  TextColumn get state => text().withDefault(const Constant('raw'))();

  /// AI 预评分 0–1（来源等级、年份、考点覆盖、题干完整度）。不删低分题，只压后。
  RealColumn get aiQuality => real().nullable()();

  /// `aiQuality` 的理由，一行中文。
  TextColumn get aiQualityNote => text().nullable()();

  /// `manual` / `ai_scan`（拍照或文本扫描）/ `furnace`（App 内自建）。
  TextColumn get origin => text().withDefault(const Constant('manual'))();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 选择题选项。`questions.answer` 仍写正确答案（判分只读那一列）。
@DataClassName('QuestionOption')
class QuestionOptions extends Table {
  TextColumn get id => text()();
  TextColumn get questionId => text().references(Questions, #id)();
  TextColumn get label => text()();
  TextColumn get content => text()();
  BoolColumn get isCorrect => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 一条思维链 = 一次"AI 亲自解题"的产物（`docs/QUESTION_BANK_DESIGN.md` §3）。
///
/// 同一道题可以有多条链（不同解法、不同模型），彼此不覆盖；链是**派生数据**，
/// 可以随时由 AI 重跑，所以不参与跨设备合并。
@DataClassName('ReasoningChain')
class ReasoningChains extends Table {
  TextColumn get id => text()();
  TextColumn get questionId => text().references(Questions, #id)();

  /// `ai` 模型产出 / `user` 手写录入。
  TextColumn get source => text().withDefault(const Constant('ai'))();

  /// 哪个模型解的（可空：模型名会变，链本身才是数据）。
  TextColumn get model => text().nullable()();

  /// 整条思路的一句话概括。
  TextColumn get summary => text().withDefault(const Constant(''))();

  /// 步骤数，冗余一份便于列表页不 JOIN。
  IntColumn get stepCount => integer().withDefault(const Constant(0))();

  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 思维链里的一步。
///
/// `actionType` 是跨学科的**能力动作** key（见
/// `domain/services/reasoning/capability_action.dart` 的词表），刻意不进标签树：
/// 推理层的动作词表和应用层的标签体系是两套东西，混在一起检索会变糊。
@DataClassName('ReasoningStep')
class ReasoningSteps extends Table {
  TextColumn get id => text()();
  TextColumn get chainId => text().references(ReasoningChains, #id)();

  /// 链内序号，从 0 起。
  IntColumn get idx => integer()();

  /// 这一步要达成什么。
  TextColumn get goal => text()();

  /// 能力动作 key（词表里的稳定标识，不本地化）。
  TextColumn get actionType => text().withDefault(const Constant('unknown'))();

  /// 为什么这样走。
  TextColumn get justification => text().withDefault(const Constant(''))();

  /// 怎么检验这一步（回代、量纲、极端值……）。
  TextColumn get checkMethod => text().withDefault(const Constant(''))();

  /// AI 判断的卡点风险 0–1：这一步最容易让人掉队的地方。
  RealColumn get stuckRisk => real().nullable()();

  /// 相关知识点 id 的 JSON 数组（文本，避免为多对多加连接表）。
  TextColumn get knowledgeHints => text().withDefault(const Constant('[]'))();

  /// 用户/评估留下的备注。
  TextColumn get note => text().nullable()();

  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 一次「拍照整理」的运行记录（`docs/HANDWRITING_INTAKE_DESIGN.md` §4）。
///
/// 一行 = 一张照片整理过一次。**零提案也要留这一行**：否则"整理过，但照片里没有
/// 可整理的东西"在重启后会退回"还没整理"，用户会白跑一次模型，而且看到的状态是错的。
@DataClassName('HandwritingIntakeRun')
class HandwritingIntakeRuns extends Table {
  @override
  String get tableName => 'handwriting_intake_runs';

  /// 照片的相对路径（`handwriting_intake/<id>/<原文件名>`）。
  TextColumn get sourceRef => text()();

  /// 整理完成的时刻（epoch ms）。
  IntColumn get analyzedAt => integer()();

  /// 模型这一轮的原始回复。可空：老行没有，离线失败也没有。
  ///
  /// 留着是为了事后能回答"当时模型到底说了什么"——提案是严格解析过的，
  /// 但被拒收的那一轮回复只有这里才有。
  TextColumn get rawReply => text().nullable()();

  IntColumn get createdAt => integer()();

  /// 多图/多页整理涉及的照片相对路径（JSON 数组）。NULL/空 = 单图整理，
  /// 来源就是 [sourceRef] 那条照片路径；非空时 [sourceRef] 是 `multi:<id>`。
  TextColumn get sourcePhotos => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {sourceRef};
}

/// 一条待确认产物（`docs/QUESTION_BANK_DESIGN.md` §7.3 的三类之一）。
///
/// 提案是**待确认的用户数据**，不是可再生的缓存：`appliedAt` 记住用户已经确认过，
/// 重启后不该让他再确认一遍，更不该重复写一次库（同一张闪存卡写两遍就是两张卡）。
@DataClassName('HandwritingProposalRow')
class HandwritingProposals extends Table {
  @override
  String get tableName => 'handwriting_proposals';

  /// `<sourceRef>#<proposalId>`：同一张照片重新整理时按来源整批替换，
  /// 不同照片的同名提案（都叫 `tag-0`）不会互相覆盖。
  TextColumn get id => text()();

  /// 来源照片的相对路径，与 [HandwritingIntakeRuns] 的 `source_ref` 对应。
  TextColumn get sourceRef => text()();

  /// 领域层的提案 id（`tag-0` / `knowledge_point-1` / …），由 kind + 序号决定。
  TextColumn get proposalId => text()();

  /// 提案在那次整理结果里的次序。
  ///
  /// 不按 id 排序：id 以 kind 开头，字典序会把三类产物打散（flashcard 排到
  /// tag 前面），用户看到的顺序就和他确认时的不一样了。
  IntColumn get sortIndex => integer()();

  /// `tag` / `knowledge_point` / `flashcard`。与 payload 冗余，便于按类统计与排查。
  TextColumn get kind => text()();

  /// 提案本体（`HandwritingProposal.toJson()`）。契约只留一份：还原走领域层
  /// `HandwritingProposal.fromJson`，这里不另写一套反序列化。
  TextColumn get payloadJson => text()();

  /// 用户确认写库的时刻（epoch ms）。NULL = 还没确认。
  IntColumn get appliedAt => integer().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 一次「材料摄取」的运行记录（`docs/MINDNET_ROADMAP.md` §2-C ①，轮次六十四）。
///
/// 一行 = 一份材料信封被算过一次。主键就是信封里的 `batch_id` —— 它是 INGEST
/// 契约的**幂等键**（`mindnet.material/1` 的 `batch_id`），所以同一份材料重算
/// 只会覆盖这一行，不会长出第二批提案。**零提案也留行**：否则"算过，但材料里
/// 没有能进图的东西"在重启后会退回"还没算"，用户会白跑一次模型。
@DataClassName('MaterialIntakeBatchRow')
class MaterialIntakeBatches extends Table {
  @override
  String get tableName => 'material_intake_batches';

  /// 信封的 `batch_id`：既是主键，也是幂等键。
  TextColumn get batchId => text()();

  /// 材料的主题（信封的 `topic`），主题 hub 的 id 就是从它算出来的。
  TextColumn get topic => text().nullable()();

  /// 出处：信封 `source.material`（人类可读的材料名/路径）。
  TextColumn get sourceRef => text().nullable()();

  /// 信封 `source.kind`（`page` / `book` / …），原样留着便于排查。
  TextColumn get sourceKind => text().nullable()();

  /// 信封 `source.captured_at`（epoch ms）。可空：材料没有拍照时间。
  IntColumn get capturedAt => integer().nullable()();

  /// 算出来的时刻（epoch ms）。
  IntColumn get analyzedAt => integer()();

  /// 转化汇总的一句话（`MaterialSummary.text`），界面直接显示。
  TextColumn get summaryText => text()();

  /// 不进图的条目与主题分组的跳过原因（`MaterialIntakeSkip` 的 JSON 数组）。
  ///
  /// 单独一列而不是散进提案行：这些**不是**待确认产物，是"为什么没动它"的
  /// 说明，数量随材料而变，塞进提案行会让"待确认清单"里混进一堆不可确认项。
  TextColumn get skippedJson => text()();

  /// 这批提案的条数（含连接），冗余一列便于列表页不读 payload。
  IntColumn get proposalCount => integer()();

  /// **这一跑到底做了什么**（人话，纯文本；schema v23）。
  ///
  /// 只有 `run/1` 那条路会写：每一条动作一句"引擎原话 + 它回报的读数"（`traceReadingOf`），
  /// 落成提案时一起存下来 —— 演练本身不落库，但"我对这一跑点头的时候，它当时做了什么"
  /// 这句话得留得住，重启之后还看得见。材料信封那条路没有这个（它不是"跑"出来的）。
  TextColumn get detailText => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {batchId};
}

/// 一条待确认的材料摄取提案（知识点或连接）。
///
/// 与 `handwriting_proposals` 同一套纪律：提案是**待确认的用户数据**，不是可再生
/// 的缓存 —— `appliedAt` 记住用户已经确认过，重启后不该再确认一遍，更不该重复写
/// 一次库（同一个知识点写两遍就是两个节点）。
@DataClassName('MaterialIntakeProposalRow')
class MaterialIntakeProposals extends Table {
  @override
  String get tableName => 'material_intake_proposals';

  /// `<batchId>#<proposalId>`：同一批重算时按批整批替换，不同批的同名提案
  ///（都叫 `kp:en::w::rely-on`）不会互相覆盖。
  TextColumn get id => text()();

  /// 所属批次，与 [MaterialIntakeBatches.batchId] 对应。
  TextColumn get batchId => text()();

  /// 领域层的提案 id（`kp:<nodeId>` / `edge:<edgeId>`），复用的是 INGEST 算出来的
  /// 确定性 id —— 以后它就是知识点的 `external_id`。
  TextColumn get proposalId => text()();

  /// 提案在这一批里的次序。
  ///
  /// 不按 id 排序：id 以 kind 开头，字典序会把知识点和连接打散，用户看到的顺序
  /// 就和他确认时的不一样了。
  IntColumn get sortIndex => integer()();

  /// `knowledge_point` / `connection`。与 payload 冗余，便于按类统计与排查。
  TextColumn get kind => text()();

  /// 提案本体（`MaterialIntakeProposal.toJson()`）。契约只留一份：还原走领域层
  /// `MaterialIntakeProposal.fromJson`，这里不另写一套反序列化。
  TextColumn get payloadJson => text()();

  /// 用户确认并处理完的时刻（epoch ms）。NULL = 还没处理。
  ///
  /// 知识点与连接都会被标上：连接现在是**线索边**，落在 `knowledge_edges` 里
  ///（roadmap §2-C ④，轮次六十八定了这个口径）。
  IntColumn get appliedAt => integer().nullable()();

  /// 确认时"它是不是本来就在库里"（NULL = 还没确认）。
  ///
  /// 成绩单（`MaterialApplyOutcome.existing`）只活在那一次调用里，重启就没了 ——
  /// 可"已经确认完的历史"要说清每一行是**这次新建的**还是**本来就有的（没重复建）**，
  /// 所以这句话得跟着提案本身落库（轮次七十五）。
  BoolColumn get alreadyExisted => boolean().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 一次「撤回这一批」的记账：`docs/MINDNET_ROADMAP.md` §2-C ⑦，轮次八十二。
///
/// 为什么要有它：撤回会把点/边**删掉**——那些行是唯一的物证，删完就再没有别的
/// 记录说"这里曾经建过什么、什么时候又撤了"。这张表是 append-only 的流水：每次
/// 调用 `undoBatch` 都留一行（撤成的、被拦住的都留），删掉的行以 JSON 原样抄下来，
/// 以后要做"撤错了再放回去"靠的就是这两格。
///
/// 它不是状态列：某个批次现在是不是"待确认"仍然只看 `material_intake_proposals.applied_at`
/// （一张表的一列只有一个写者，D1–D6）。
@DataClassName('MaterialIntakeUndoLogRow')
class MaterialIntakeUndoLogs extends Table {
  @override
  String get tableName => 'material_intake_undo_logs';

  IntColumn get id => integer().autoIncrement()();

  /// 撤的是哪一批（`material_intake_batches.batch_id`）。
  TextColumn get batchId => text()();

  /// 这次撤回请求发生的时刻（epoch ms）。
  IntColumn get requestedAt => integer()();

  /// true = 真的撤了；false = 被拦住了，库里的行一个字没动。
  BoolColumn get undone => boolean()();

  /// 真的删掉的知识点 / 线索边（`MaterialAppliedPoint` / `MaterialAppliedEdge`
  /// 的 JSON 数组）。撤成的那些行只活在这一格和这次调用的返回值里。
  TextColumn get removedPointsJson => text()();
  TextColumn get removedEdgesJson => text()();

  /// 退回"待确认"的提案条数（`applied_at` 被清空的行数）。
  IntColumn get restoredCount => integer()();

  /// 拦路的原因条数（`undone == false` 时大于 0）。
  IntColumn get blockedCount => integer()();

  /// 第一句拦路的理由（人话，照原样显示，不用再算一遍）。
  TextColumn get blockedReason => text().nullable()();
}

///
/// 为什么要单独一张表：MindNet 的边是**线索**语义（严格有向、权重 `ls`、不自动反向），
/// 而应用里标签树的父子边是**包含**语义（`tags.parent_id`，父子是层级）。
/// `E:\Document\MindNet\docs\MEMORY_RECORD.md` §3.5 把这两件事分开写明了，
/// 所以资料里的 `contains`（句 → 词）与 `produce`（词 → 句）进来时**都**是线索边：
/// `origin` 只负责记住它是材料里的哪种关系，包含语义仍然只有标签树那一处。
@DataClassName('KnowledgeEdgeRow')
class KnowledgeEdges extends Table {
  @override
  String get tableName => 'knowledge_edges';

  /// 边的确定性 id（INGEST 算出来的 `e_<from>__<to>`，或手写边自己的 id）。
  ///
  /// 它同时是**幂等键**：同一份材料确认两次，不会长出第二条边。
  TextColumn get id => text()();

  /// 起点 / 终点的节点 id（材料节点的 id 同时是 `knowledge_points.external_id`）。
  TextColumn get fromId => text()();
  TextColumn get toId => text()();

  /// 这条边是从哪种材料关系来的：`contains` / `produce` / `topic`（材料里写的关系），
  /// 手写边记 `manual`，材料没写清关系时记 `material`。
  ///
  /// 只是出处，不是权重：线的方向与含义由 [fromId] → [toId] 定，反过来要另建一条。
  TextColumn get origin => text()();

  /// 线索强度 `ls`。可空：没有来源的边不许编一个数。
  RealColumn get ls => real().nullable()();

  /// `ls` 有没有标定来源（`MEMORY_RECORD.md` §3.5：边权 `ls` 目前**没有**标定来源）。
  ///
  /// 默认 false —— 于是"未标定"是库里的事实，不是文档里的口号；
  /// 界面/工具要显示权重时必须把它一起显示出来。
  BoolColumn get lsCalibrated => boolean().withDefault(const Constant(false))();

  /// 这一批材料（`material_intake_batches.batch_id`）。手写的边为空。
  TextColumn get batchId => text().nullable()();

  /// 出处那一行（与 `knowledge_points.source` 同一套文案）。
  TextColumn get source => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 一次「自测作答」的记录（schema v32，轮次一百五十五）。
///
/// 一行 = 一次**判分成功**的提交。空选、非客观题这类"没有可判"的提交根本不落库，
/// 否则"做过几次"会被误触的次数污染。同一道题可以有很多行：历史是追加的，
/// 后面再改答案也不会改写已经发生的作答。
///
/// 与 `review_logs` 分开：那是闪存卡的复习测试记录（参与调度），这里是题库里
/// 点开一道题、自己先做一遍的记录（学习痕迹，不参与调度）。
@DataClassName('QuestionAttempt')
class QuestionAttempts extends Table {
  @override
  String get tableName => 'question_attempts';

  TextColumn get id => text()();

  /// 作答的是哪道题。
  TextColumn get questionId => text().references(Questions, #id)();

  /// 勾选的选项 label（JSON 数组，已归一化：trim → 大写 → 去空 → 去重 → 升序）。
  /// 单选用一个元素，多选用多个；填空/解答题现在不判分，不会写到这里。
  TextColumn get selectedLabels => text().withDefault(const Constant('[]'))();

  /// 这次判对了吗。只存判分成功的作答，所以这一列不允许 NULL。
  BoolColumn get isCorrect => boolean()();

  /// 提交作答的时刻（epoch ms）。
  IntColumn get attemptedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 题目编号的高水位（schema v33，轮次一百六十三）。
///
/// 只有一行（`id = 1`），`last_issued` 是这个库**发出去过的最大题号**。编号的
/// 分配规则是 `max(现存最大号, last_issued) + 1`（域层
/// `allocateQuestionSerial`），所以删掉最大号那道题以后，号不会被下一道题接手
/// —— `docs/QUESTION_BANK_DESIGN.md` §11 要求的「发出即永久保留」。
///
/// 为什么单独一张表、而不是塞进 `local_settings`：这一行只被题库写入
/// （`ingest` 的事务里），与设置项没有语义关系；而"没有这一行"在这里正好表达
/// "老库还没记过高水位"——此时分配器退回「现存最大号 + 1」的旧行为。
@DataClassName('QuestionSerialCounterRow')
class QuestionSerialCounters extends Table {
  @override
  String get tableName => 'question_serial_counters';

  /// 固定 1（单行表）。
  IntColumn get id => integer()();

  /// 发出去的最大题号（>= 1）。
  IntColumn get lastIssued => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 一次能力测评的单项得分（schema v38，轮次一百七十七）。
///
/// 一行 = 某一项能力（[abilityKey]）的一次测量结果，0–100 分。与
/// `assessment_sessions` / `cognitive_priors` 分开：那是**知识点**维度的
/// 自评/复述先验（`docs/ASSESSMENT_DESIGN.md`），这里是**能力**维度的小测
/// 指标（`docs/REVIEW_FEEDBACK.md` §8：用户要的是 humanbenchmark 式的
/// 能力测试，不是选标签自评）。两者互不写入，也不互相推导。
///
/// 只追加：同一天测两次就是两行，画像页按能力取最新一行。
@DataClassName('AbilityScoreRow')
class AbilityScores extends Table {
  @override
  String get tableName => 'ability_scores';

  TextColumn get id => text()();

  /// 能力项稳定 code：`reaction_speed` / `working_memory` /
  /// `pattern_recognition` / `attention_stability`（域层 `AbilityKey.code`）。
  TextColumn get abilityKey => text()();

  /// 0–100 的分数（域层 clamp 后写入；REAL 保留小数）。
  RealColumn get score => real()();

  /// 小测原始指标（JSON 对象文本：反应毫秒样本、最长记忆长度、答对数等）。
  /// 可空：没有可存指标时写 NULL，不要编一个空对象。
  TextColumn get metricsJson => text().nullable()();

  /// 测量时刻（epoch ms）。
  IntColumn get capturedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// 评测板块（schema v41，2026-10-29，《Furnace 用户评测板块设计文档》v1.0 §4/§5/§6/§7）
//
// 四层框架：评测任务 → 评测数据（session/trial/metric）→ 能力指标 →
// 认知模型参数。后两层与任务是多对多，映射本身也存表（可配置、可换版本）。
//
// 为什么表名前面都带 `cog_` 前缀：v10 的认知先验层已经占用了
// `assessment_sessions` / `assessment_responses` / `cognitive_priors` 三个表名，
// 那是**知识点**维度的自评（docs/ASSESSMENT_DESIGN.md），语义与这里的
// **能力**评测不同。改前缀而不是改旧表名，老用户的数据一行都不用搬家。
//
// 所有表都是新增的：v40 及更早的库没有任何一行需要回填。
// ---------------------------------------------------------------------------

/// 评测任务注册表。
///
/// 一行 = 一个可运行任务（`fast_simple_task_i`、`go_nogo`…）。`config_json`
/// 存设计文档 §4.1 的完整配置（试次数、ISI、刺激集合、默认映射…）；
/// `design_version` 升版后，旧测量不参与合并（标记 stale）。
/// `enabled=false` 的任务不出现在评测中心（v1 里 fast_simple_task_iii 与
/// decision_fatigue 是暂定/副本，默认关闭）。
@DataClassName('CogAssessmentTaskRow')
class CogAssessmentTasks extends Table {
  @override
  String get tableName => 'cog_assessment_tasks';

  /// 稳定任务 id（域层 [AssessmentTaskConfig.id]）。
  TextColumn get id => text()();

  /// 展示名兜底（正常由 l10n 按 task id 渲染）。
  TextColumn get displayName => text()();

  /// 任务类型 code：`fast_simple` / `go_nogo` / `digit_span` / …
  TextColumn get taskType => text()();

  /// 设计版本（如 `assessment_v1`）。
  TextColumn get designVersion => text()();

  /// §4.1 的任务配置 JSON 文本。
  TextColumn get configJson => text()();

  /// 是否在评测中心可选。
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// 注册时刻（epoch ms）。
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 一次评测会话。
///
/// `status` = completed / incomplete / aborted（§4.1 状态机）。未完成的会话
/// 保留原始 trial，不产出能力估计；`quality_flags_json` 是 §9 的标记数组
/// （标记只上调 uncertainty，不删数据）。
@DataClassName('CogAssessmentSessionRow')
class CogAssessmentSessions extends Table {
  @override
  String get tableName => 'cog_assessment_sessions';

  TextColumn get id => text()();

  /// 指向 [CogAssessmentTasks.id]（不建外键：任务注册表重建时不希望级联丢测量）。
  TextColumn get taskId => text()();

  TextColumn get designVersion => text()();

  /// 设备标识（`windows` / `android`，§4.1 `device_baseline` 维度）。
  TextColumn get device => text()();

  /// 开始/完成时刻（epoch ms）。`completed_at` 为空 = 没有正常做完。
  IntColumn get startedAt => integer()();
  IntColumn get completedAt => integer().nullable()();

  /// completed / incomplete / aborted。
  TextColumn get status => text()();

  /// §9 质量标记 JSON 数组；NULL = 无标记。
  TextColumn get qualityFlagsJson => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 单次试次（§3 trial）。
///
/// 只追加：一次会话几十上百行。`rt_ms` 为空 = 漏答/超时；`correct` 为空 =
/// 该试次没有对错（如疲劳块的持续按键）。`is_practice=true` 的试次不参与
/// 指标计算但仍保留（§9 的 practice_block 标记也依赖它）。
@DataClassName('CogAssessmentTrialRow')
class CogAssessmentTrials extends Table {
  @override
  String get tableName => 'cog_assessment_trials';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get sessionId => text()();

  /// 会话内从 0 开始的试次序号。
  IntColumn get trialIndex => integer()();

  /// 所属 block（疲劳块按段、digit span 按长度层）。
  IntColumn get blockIndex => integer()();

  /// 刺激与正确响应/条件的 JSON（`stimulus_json`，构造时冻结）。
  TextColumn get stimulusJson => text()();

  /// 用户的原始响应 JSON；NULL = 没有响应。
  TextColumn get responseJson => text().nullable()();

  /// 反应时（毫秒）；NULL = 漏答/超时。
  IntColumn get rtMs => integer().nullable()();

  /// 是否正确；NULL = 该试次不判对错。
  BoolColumn get correct => boolean().nullable()();

  BoolColumn get isPractice => boolean().withDefault(const Constant(false))();

  /// 试次记录时刻（epoch ms）。
  IntColumn get timestamp => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 会话级统计指标（§3 的 rt_median / d_prime / stable_span …）。
///
/// 一行 = 一个指标的一次计算。`n_trials` 记参与计算的试次数（审计用：
/// 样本变少时 uncertainty 要上调）。重新计算就追加新行，不覆盖历史。
@DataClassName('CogAssessmentMetricRow')
class CogAssessmentMetrics extends Table {
  @override
  String get tableName => 'cog_assessment_metrics';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get sessionId => text()();

  /// 指标名（域层 [MetricNames]，如 `rt_median`）。
  TextColumn get metricName => text()();

  RealColumn get value => real()();

  IntColumn get nTrials => integer()();

  /// 该指标层级的质量标记 JSON 数组；NULL = 无。
  TextColumn get qualityFlagsJson => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 能力指标的个人档案（§5，10 项能力）。
///
/// 一行 = 一项能力的当前估计（合并后的结果，不是每次测量的流水）。
/// `source`：default（出厂值，非人群常模）/ assessment_v1（实测合并）/
/// user_override（用户手改，**此后不再自动更新**）。
/// `uncertainty` 越低越可信，最低 0.15；`stale=true` 表示设计版本升级后
/// 旧测量不再参与合并。
@DataClassName('CogAbilityEstimateRow')
class CogAbilityEstimates extends Table {
  @override
  String get tableName => 'cog_ability_estimates';

  /// 能力 id（[AbilityIds]）。
  TextColumn get abilityId => text()();

  /// z-score 量纲的估计值（0 = 该用户典型水平，个体内基线，非常模）。
  RealColumn get mean => real()();

  RealColumn get uncertainty => real()();

  /// 参与合并的测量次数。
  IntColumn get nMeasurements => integer()();

  /// default / assessment_v1 / user_override。
  TextColumn get source => text()();

  TextColumn get designVersion => text()();

  TextColumn get mappingVersion => text()();

  /// 个人基线（首次测量冻结的设备/试剂条件），JSON；NULL = 未建立。
  TextColumn get personalBaselineJson => text().nullable()();

  TextColumn get device => text().nullable()();

  IntColumn get updatedAt => integer()();

  BoolColumn get stale => boolean().withDefault(const Constant(false))();

  /// 每次测量的贡献明细 JSON 数组（审计「这个数怎么来的」）。
  TextColumn get contributionsJson => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {abilityId};
}

/// 认知模型参数（§6，9 项）。
///
/// 一行 = 一个参数（task_duration_estimate、chunking_threshold…）。
/// `source`：default / derived（由能力指标经 §7.2 映射推出）/ user_override。
/// `derived_from_json` 记推导来源（能力 id + 权重 + 方向），便于回溯。
@DataClassName('CogCognitiveParamRow')
class CogCognitiveParams extends Table {
  @override
  String get tableName => 'cog_cognitive_params';

  TextColumn get paramId => text()();

  RealColumn get value => real()();

  RealColumn get uncertainty => real()();

  /// default / derived / user_override。
  TextColumn get source => text()();

  TextColumn get derivedFromJson => text().nullable()();

  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {paramId};
}

/// 任务 → 能力 的映射（§7.1）。
///
/// 一行 = 一条映射；`metric_source` 指定用哪个统计指标喂这个能力。
/// 存表而不是写死在代码里，是为了不改代码就能调权重、换指标（§7 明确要求）。
@DataClassName('CogTaskAbilityMappingRow')
class CogTaskAbilityMappings extends Table {
  @override
  String get tableName => 'cog_task_ability_mapping';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get taskId => text()();

  TextColumn get abilityId => text()();

  /// 0–1；同一任务的多条权重之和应为 1（软约束，不建 DB 检查）。
  RealColumn get weight => real()();

  /// 使用的统计指标名（[MetricNames]）。
  TextColumn get metricSource => text()();

  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  TextColumn get mappingVersion => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 能力 → 参数 的映射（§7.2）。
///
/// `direction` = positive / negative：能力值升高时参数变大还是变小。
/// 参数值按映射加权合成后 clamp 到参数自身的合法区间。
@DataClassName('CogAbilityParamMappingRow')
class CogAbilityParamMappings extends Table {
  @override
  String get tableName => 'cog_ability_param_mapping';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get abilityId => text()();

  TextColumn get paramId => text()();

  /// 0–1 权重。
  RealColumn get weight => real()();

  /// positive / negative。
  TextColumn get direction => text()();

  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  TextColumn get mappingVersion => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// v45（2026-11-14）：全局 agent run 的持久化（《STUDENT-MODE-AND-AGENT-LOOP-
// DESIGN-2026-11-14》§5）。
//
// 五张表都是**纯新增**：v44 及更早的库没有任何一行需要回填。它们记录的是
// "一次运行发生了什么"，不是可再生的缓存——但是它们**不存 raw CoT**：
// reasoning 全文留在 `<appSupport>/student_solver_traces/` 的 trace 文件里，
// 库里只留 `reasoning_chars`（长度）和结构化摘要。同一条纪律与
// `docs/REVIEW_FEEDBACK.md` §4a 的 `ai_messages.reasoning` 不同：那条是用户要
// 在历史里折叠查看的正文，而这里的 CoT 是过程审计的原料，读它的只有
// ProcessAuditor，塞进库只会让一次运行的存储涨 20k token 而没有任何读侧。
// ---------------------------------------------------------------------------

/// 一次 agent 运行（schema v45，设计文档 §5.1）。
///
/// 一行 = 一次 `AgentRun`：普通对话的一轮、或学生模式的一次 solve→answer→
/// verify→repair。`status` 是运行级终态，`verifier_verdict` 是 run 级摘要
/// （详细证据在 [AgentVerifications]）。
///
/// 不存 raw CoT 是这一张表的核心约束：[answerSheetJson] 只放结构化答案，
/// [reasoningChars] 只放长度；要读原文请顺着 [tracePath] 去 trace 文件。
@DataClassName('AgentRunRow')
class AgentRuns extends Table {
  @override
  String get tableName => 'agent_runs';

  TextColumn get id => text()();

  /// 所属会话（`ai_conversations.id`）。不建外键：运行记录是审计流水，删会话
  /// 不该把它一起抹掉（这也是本项目「生成 schema 不带外键」的既有口径）。
  TextColumn get conversationId => text()();

  /// 这次运行解析到的 preset id（`assistant` / `student_solver`）。只存 id，
  /// 不存定义/版本/hash —— 与 `ai_conversations.agent_preset_id` 同一个契约。
  TextColumn get presetId => text()();

  /// `chat` / `student`（域层 `AgentMode.id`）。
  TextColumn get mode => text()();

  /// `solve` / `answer` / `verify` / `repair` / `present`（域层
  /// `AgentPhase.id`），运行中会被推进。
  TextColumn get phase => text()();

  /// `running` / `answered` / `failed` / `stopped`（域层 `AgentRunStatus.id`）。
  TextColumn get status => text()();

  /// 终态原因（域层 `StopReason.id`）；NULL = 还在跑或正常结束。
  TextColumn get stopReason => text().nullable()();

  /// 已执行的模型/工具步数（= [AgentSteps] 的行数，冗余一列便于不读明细）。
  IntColumn get steps => integer().withDefault(const Constant(0))();

  IntColumn get promptTokens => integer().withDefault(const Constant(0))();
  IntColumn get completionTokens => integer().withDefault(const Constant(0))();

  /// provider 报告的 reasoning token 数；NULL = provider 没报（不是 0）。
  IntColumn get reasoningTokens => integer().nullable()();

  /// reasoning 的字符数。**不是全文**：长度足以比较「这一跑想了多少」，
  /// 原文留在 trace 文件里。
  IntColumn get reasoningChars => integer().withDefault(const Constant(0))();

  IntColumn get elapsedMs => integer().nullable()();

  /// 结构化答案卡（域层 `StudentAnswerSheet.toJson()` 的 JSON 文本）。
  /// 只放题型/答案/过程这些答案本身，不放 CoT。
  TextColumn get answerSheetJson => text().nullable()();

  /// 原始 trace 文件路径（`<appSupport>/student_solver_traces/<stamp>.json`）。
  TextColumn get tracePath => text().nullable()();

  /// run 级验证结论摘要（`pass` / `fail` / `unknown` / `error`）；明细在
  /// [AgentVerifications]。
  TextColumn get verifierVerdict => text().nullable()();

  /// ProcessAuditor 的过程报告（`ProcessReport.toJson()`）；NULL = 没跑过程审计。
  TextColumn get processReportJson => text().nullable()();

  IntColumn get startedAt => integer()();
  IntColumn get endedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 一次运行里的一步（schema v45，设计文档 §5.2）。
///
/// 每次模型调用、每次答案落盘、每次验证都追加一行；`UNIQUE(run_id, seq)` 让
/// 同一序号不可能写两次（重放同一 run 时是幂等冲突而不是悄悄长出重复步）。
///
/// [stateFingerprint] 是 StepGuard/ProcessAuditor 判断"状态连续不变"的依据，
/// [claimHash] 是 claim 级循环检测的锚点（claim 正文不在这里，见
/// [AgentClaims]）。[summary] 只放一句人话，**不放 raw CoT**。
@DataClassName('AgentStepRow')
class AgentSteps extends Table {
  @override
  String get tableName => 'agent_steps';

  TextColumn get id => text()();

  TextColumn get runId => text()();

  /// 运行内从 0 开始（或从 1 开始，由写入方统一）的步序号。
  IntColumn get seq => integer()();

  /// 这一步处于哪个 phase（`AgentPhase.id`）。
  TextColumn get phase => text()();

  /// `model` / `answer` / `verify` / `repair` / `persist`。
  TextColumn get kind => text()();

  /// 工具名（只有 `kind` 为工具步时非空）。
  TextColumn get toolName => text().nullable()();

  /// 规范化的参数 hash（`StepGuard.actionKey` 的 hash 部分）。
  TextColumn get argsHash => text().nullable()();

  /// 这一步之后的状态指纹（`StepGuard.stateFingerprint`）。
  TextColumn get stateFingerprint => text().nullable()();

  /// 这一步涉及的 claim canonical hash（可选）。
  TextColumn get claimHash => text().nullable()();

  /// `ok` / `failed` / `skipped`。
  TextColumn get status => text()();

  /// 这一步消耗的 token 数（provider 报告时才有意义；NULL = 不知道）。
  IntColumn get tokens => integer().nullable()();

  /// 一句人话摘要（例如「模型返回答案卡」「验证 fail: missing_answer」）。
  TextColumn get summary => text().nullable()();

  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {runId, seq},
      ];
}

/// 一次验证/审计的结论（schema v45，设计文档 §5.3）。
///
/// ContentVerifier 与 ProcessAuditor **分开记**（`kind` = `content` / `process`），
/// 因为两者的输入和独立性不同：内容验证不看 solver 的 raw CoT
/// （[independent] = true），过程审计必须读 CoT（[processReportJson]）。
/// 合成一行会把「答案对不对」和「过程有没有打转」两件事混成一个 verdict。
@DataClassName('AgentVerificationRow')
class AgentVerifications extends Table {
  @override
  String get tableName => 'agent_verifications';

  TextColumn get id => text()();

  TextColumn get runId => text()();

  /// 验证者标识：`student_independent_v1` / `process_auditor` / …
  TextColumn get verifier => text()();

  /// `content` / `process`。
  TextColumn get kind => text().withDefault(const Constant('content'))();

  /// `pass` / `fail` / `unknown` / `error`（域层 `Verdict.id`）。
  TextColumn get verdict => text()();

  /// `missing_answer` / `wrong_branch` / `loop` / `self_doubt` / …（域层
  /// `FailureType.id`）；NULL = 没有可归类的失败。
  TextColumn get failureType => text().nullable()();

  /// 这次验证是不是**独立**于 solver 的（内容验证 true；过程审计 false）。
  BoolColumn get independent => boolean().withDefault(const Constant(true))();

  /// 验证证据（`Verification.toJson()`）：issues/evidence/confidence 等。
  TextColumn get evidenceJson => text().nullable()();

  /// 过程审计报告（`ProcessReport.toJson()`）；`kind = process` 时才有。
  TextColumn get processReportJson => text().nullable()();

  IntColumn get promptTokens => integer().nullable()();
  IntColumn get completionTokens => integer().nullable()();

  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 一条 claim（schema v45，设计文档 §5.4）。
///
/// 全局可选模块，学生 v1 不写；v45 先把表建好，ClaimLedger 接进来时不用再改
/// schema。`canonical` 是规范化后的命题文本（不是 hash：hash 做去重键，正文
/// 做可读证据）；`deps_json` 存依赖 claim 的 `[{id, version}]`，依赖版本没变
/// 时同一 ClaimKey 命中检查缓存，不重复判。
@DataClassName('AgentClaimRow')
class AgentClaims extends Table {
  @override
  String get tableName => 'agent_claims';

  TextColumn get id => text()();

  TextColumn get runId => text()();

  /// `given` / `equation` / `decision` / `assumption` / `open`。
  TextColumn get kind => text()();

  /// 规范化后的命题文本（用于匹配/展示；不存中文以外的本地化标签）。
  TextColumn get canonical => text()();

  /// 命题原文（模型/审计器抽出来的那句话）。
  TextColumn get statement => text()();

  /// 依赖列表 JSON：`[{"id": "...", "version": 1}]`；NULL = 无依赖。
  TextColumn get depsJson => text().nullable()();

  /// `proposed` / `verified` / `refuted` / `open`。
  TextColumn get status => text()();

  /// `deterministic` / `symbolic` / `nli` / `judge`；NULL = 还没检查过。
  TextColumn get checkMethod => text().nullable()();

  /// 这个 claim 被检查时依赖的版本号（依赖变了就要重查）。
  IntColumn get checkedVersion => integer().withDefault(const Constant(0))();

  TextColumn get evidence => text().nullable()();

  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 一条验证后经验（schema v45，设计文档 §5.5，P1）。
///
/// 只写「已经过验证」的经验，不写模型的自我评价；[revokedAt] 非空 = 这条经验
/// 已被撤销，不再参与复用。学生 v1 不启用，表先建好。
@DataClassName('AgentExperienceRow')
class AgentExperiences extends Table {
  @override
  String get tableName => 'agent_experiences';

  TextColumn get id => text()();

  /// 经验聚类键（同一类问题的经验放一起）。
  TextColumn get cluster => text()();

  /// 状态键（`StepGuard` 的 state fingerprint / claim 状态摘要）。
  TextColumn get stateKey => text()();

  /// 动作键（`StepGuard.actionKey`）。
  TextColumn get action => text()();

  /// 奖励（验证后的收益/代价，可负）。
  RealColumn get reward => real()();

  /// provenance：这条经验来自哪次 run / 哪条验证（可空，撤销时要有据可查）。
  TextColumn get provenanceRunId => text().nullable()();
  TextColumn get provenanceVerifierId => text().nullable()();

  IntColumn get version => integer().withDefault(const Constant(1))();

  /// NULL = 有效；非空 = 撤销时刻（epoch ms），保留行而不是删除。
  IntColumn get revokedAt => integer().nullable()();

  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// v47（2026-11-15）：ThreadFlow 内容整合底座
// 契约：`INTEGRATION-CONTRACT-2026-11-15.md` §2.2 / §3.1 / §3.4。
// 两张新表 + `tasks.kind` / `tasks.source_key` 两列；调度器仍只有
// `ThreadRankService`，不新增 papers / weekly_plans / daily_plans / thread_nodes。
// ---------------------------------------------------------------------------

/// 内容对象 ↔ 产品对象的 ID 桥（schema v47，契约 §2.2）。
///
/// 一行 = 一条引用：C 层内容 id（`Q-PH0001` / `QSET-20261115-01` / 内容知识节点
/// `kp-*`）指向一个产品对象（`task` / `question` / `knowledge_point` /
/// `card_template`），用 [role] 区分同一对象上的不同来源。
///
/// **只引用、不复制正文**：这张表没有任何题干/答案/解析/DAG 正文字段。内容正文
/// 的唯一存放处是产品 `questions`/`knowledge_points` 与工作区内容包；
/// `metadata_json` 只放"怎么引用"的摘要（node_id / board / trust / source_mode
/// 等），不放正文。
///
/// 唯一键 `(content_id, object_type, object_id, role)`：内容换版（`content_hash`
/// 变）时**原地更新**这一行，不新建第二张版本表（避免第三套历史）；需要审计时
/// 把旧 hash 写进 `metadata_json.previous_hash`。
@DataClassName('ContentRefRow')
class ContentRefs extends Table {
  @override
  String get tableName => 'content_refs';

  TextColumn get id => text()();

  /// C 层 id：`Q-<SUBJ><NNNN>` / `QSET-<yyyyMMdd>-<n>` / 内容知识节点
  /// `kp-<slug>`。永不复用、永不改名：修订 = 版本 + hash 变化，新题 = 新 id。
  TextColumn get contentId => text()();

  /// 内容包 `provenance.version`（整数、单调 +1）或 board 版本；NULL = 引用方
  /// 没记录版本。**version 与 hash 要么同时给、要么都不给**，只给一个是脏数据
  /// —— 见 `ContentRefRepository` 的成对校验。
  IntColumn get contentVersion => integer().nullable()();

  /// sha256（question 或 board 的 `content_hash`）。注意它与产品
  /// `questions.stem_fingerprint`（FNV-1a 64）同名不同算法，**禁止互比**
  /// （契约 §2.3 第 3 条）。
  TextColumn get contentHash => text().nullable()();

  /// 过滤用（physics / math / chinese），不参与 join 语义。
  TextColumn get subject => text().nullable()();

  /// 产品对象类型：`task` / `question` / `knowledge_point` / `card_template`
  /// （域层 `ContentObjectType`）。自由 TEXT 与 `object_tags.object_type` 同一
  /// 纪律：新增值要改常量并做一次全库审计。
  TextColumn get objectType => text()();

  /// 产品对象 id（`task-<uuid>` / `q-<uuid>` / `kp-<uuid>` / `tpl-<uuid>`）。
  /// **本地 id 不是跨设备锚点**：禁止把它写回内容包。
  TextColumn get objectId => text()();

  /// `source_package` / `paper_item` / `node` / `dag_node` / `card_seed` /
  /// `analysis_ref`（域层 `ContentRefRole`）。词表固定，新增要改常量 + 迁移审计。
  TextColumn get role => text()();

  /// 引用摘要（node_id / board / trust / source_mode / previous_hash …）；
  /// 不存正文。
  TextColumn get metadataJson => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {contentId, objectType, objectId, role},
      ];
}

/// ThreadFlow 状态事件流（schema v47，契约 §3.1/§3.4）。
///
/// **append-only**：每次状态迁移追加一行，不更新（删 task 时随节点删 —— 事件
/// 属于该节点的调度历史；`completion_logs` 是学习历史、保留）。唯一写口是
/// `ThreadFlowWriter`。
///
/// 事件种类 `created` / `planned` / `started` / `submitted` / `stuck` /
/// `skipped` / `completed` / `reopened`（域层 `ThreadEventKind`；`reopened`
/// 是 task-90 按契约 §3.4「重开」补的第 8 种，**只加值不加列**）。词表与
/// 任务书一致；状态 `blocked` 由 `stuck` 事件驱动（契约里该事件叫 `blocked`，
/// 这里按任务书的 `stuck` 落地，两者是同一个事实）。
///
/// 幂等：`UNIQUE(task_id, kind, source_key)`。`source_key` 为 NULL 时 SQLite
/// 允许多行，所以普通"每次迁移都追加"不受影响；调用方要重试幂等时给
/// `source_key`（例如 `QSET-20261115-01:completed`），重复写同一事实会命中
/// 唯一键而不是悄悄长出第二行。
///
/// **不存正文**：`payload_json` 只放流程事实（reason / verdict / attempt_ids /
/// agent_run_id / card_state_ids 数量等），不放题干/答案/解析，也**不是**复习
/// 记录或作答记录 —— 那两件事分别归 `review_logs` / `question_attempts`。
@DataClassName('ThreadEventRow')
class ThreadEvents extends Table {
  @override
  String get tableName => 'thread_events';

  TextColumn get id => text()();

  TextColumn get taskId => text()();

  /// `created` / `planned` / `started` / `submitted` / `stuck` / `skipped` /
  /// `completed` / `reopened`（域层 `ThreadEventKind.id`）。
  TextColumn get kind => text()();

  /// 事件事实 JSON；NULL = 这个事件没有附加事实。限 4 KB（契约 R4）。
  TextColumn get payloadJson => text().nullable()();

  /// 事件发生时刻（epoch ms，与全库同一个时钟）。
  IntColumn get occurredAt => integer()();

  /// 幂等键；NULL = 不参与幂等（每次调用都追加）。
  TextColumn get sourceKey => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {taskId, kind, sourceKey},
      ];
}
