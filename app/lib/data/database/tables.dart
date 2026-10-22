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
