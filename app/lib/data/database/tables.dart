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
  TextColumn get knowledgePointId =>
      text().references(KnowledgePoints, #id)();
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
  TextColumn get cardTemplateId => text().references(CardTemplates, #id).nullable()();

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

  IntColumn get reviewedAt => integer()();
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
// v2 tables (Threadflow): added in schema 1 -> 2.
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
  BoolColumn get useActualTime =>
      boolean().withDefault(const Constant(true))();

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
  TextColumn get knowledgePointId =>
      text().references(KnowledgePoints, #id)();
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
  TextColumn get knowledgePointId =>
      text().references(KnowledgePoints, #id)();
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
  TextColumn get knowledgePointId =>
      text().references(KnowledgePoints, #id)();
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
  IntColumn get timelineSpanDays => integer().withDefault(const Constant(730))();

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
