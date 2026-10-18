import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db_write_interceptor.dart';
import 'tables.dart';

part 'database.g.dart';

/// The single local SQLite database for Furnace.
@DriftDatabase(
  tables: [
    Profiles,
    LocalSettings,
    Tags,
    ObjectTags,
    MindMaps,
    MindNodes,
    Tasks,
    TaskDependencies,
    TimeBlocks,
    TaskTimeBlocks,
    KnowledgePoints,
    CardTemplates,
    CardStates,
    ReviewLogs,
    KnowledgePackages,
    PackageItems,
    // v2 (Threadflow, historical name)
    ThreadStates,
    TaskTemplates,
    CompletionLogs,
    ClozeSlots,
    ClozeHistory,
    BoostEntries,
    Themes,
    Attachments,
    // v3 (blueprint v2, user annotations 2026-09-08)
    ThreadRankSettings,
    DiffusionLogs,
    // v4 (Time module, user feedback item 3)
    TimeTemplates,
    TimeViewSettings,
    // v6 (AI integration + MindNet port prerequisites)
    AiConversations,
    AiMessages,
    AiActions,
    // v8 (per-group daily review plan)
    ReviewGroupPlans,
    // v10 (assessment layer, docs/ASSESSMENT_DESIGN.md §5)
    AssessmentSessions,
    AssessmentResponses,
    CognitivePriors,
    // v12 (question bank + reasoning layer, docs/QUESTION_BANK_DESIGN.md)
    Questions,
    QuestionOptions,
    ReasoningChains,
    ReasoningSteps,
    // v13 (handwriting intake proposals, docs/HANDWRITING_INTAKE_DESIGN.md §4)
    HandwritingIntakeRuns,
    HandwritingProposals,
    // v14 (exposure log, docs/MINDNET_ROADMAP.md §2 / docs/DATA_MODEL.md)
    ExposureLogs,
    // v17 (material intake proposals, docs/MINDNET_ROADMAP.md §2-C ①)
    MaterialIntakeBatches,
    MaterialIntakeProposals,
    // v18 (clue edges, docs/MINDNET_ROADMAP.md §2-C ④)
    KnowledgeEdges,
    // v20 (undo ledger for material intake batches, §2-C ⑦)
    MaterialIntakeUndoLogs,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Creates an in-memory/testing database from an existing [executor].
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  /// v7 is the unshipped release that added `local_settings.ai_max_rounds`
  /// plus the two review-preference columns; v8 adds the per-group daily plan
  /// table; v9 adds the two failure-feedback columns on `review_logs`; v10 adds
  /// the three assessment tables (`docs/ASSESSMENT_DESIGN.md` §5); v11 adds the
  /// pre-review prediction column on `review_logs` (M6 calibration); v12 adds
  /// the question bank and the reasoning-chain tables
  /// (`docs/QUESTION_BANK_DESIGN.md` §1/§3); v13 adds the two handwriting-intake
  /// tables that keep "整理过但还没确认" alive across a restart
  /// (`docs/HANDWRITING_INTAKE_DESIGN.md` §4); v14 adds `exposure_logs`, the one
  /// table for MindNet's `exposure` action ("读了但没测", the last of the five
  /// `mindnet.run/1` actions the app could not express). v15 adds the
  /// attention-hint switch on `local_settings` (`docs/MINDNET_ROADMAP.md` §3
  /// row 4). v16 adds the cognitive-rank switch on `thread_rank_settings`
  /// (roadmap §2-D). v17 adds the two material-intake tables that keep
  /// "算过但还没确认" alive across a restart and make applying a batch idempotent
  /// (`docs/MINDNET_ROADMAP.md` §2-C ①). v18 adds `knowledge_edges`: the material
  /// connections that used to be deferred now land as **clue edges** (strictly
  /// directed, `ls` kept but flagged uncalibrated), which is the §2-C ④ decision
  /// (`E:\Document\MindNet\docs\MEMORY_RECORD.md` §3.5 keeps containment in the
  /// tag tree and clues in the graph). See [_upgradeV6ToV7] /
  /// [_upgradeV7ToV8] / [_upgradeV8ToV9] / [_upgradeV9ToV10] /
  /// [_upgradeV10ToV11] / [_upgradeV11ToV12] / [_upgradeV12ToV13] /
  /// [_upgradeV13ToV14] / [_upgradeV14ToV15] / [_upgradeV15ToV16] /
  /// [_upgradeV16ToV17] / [_upgradeV17ToV18] / [_upgradeV18ToV19] /
  /// [_upgradeV19ToV20] / [_upgradeV20ToV21] / [_upgradeV21ToV22] / [_upgradeV22ToV23] /
  /// [_upgradeV23ToV24].
  @override
  int get schemaVersion => 24;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
      },
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          await _upgradeV1ToV2();
        }
        if (from < 3) {
          await _upgradeV2ToV3();
        }
        if (from < 4) {
          await _upgradeV3ToV4();
        }
        if (from < 5) {
          await _upgradeV4ToV5();
        }
        if (from < 6) {
          await _upgradeV5ToV6();
        }
        if (from < 7) {
          await _upgradeV6ToV7();
        }
        if (from < 8) {
          await _upgradeV7ToV8();
        }
        if (from < 9) {
          await _upgradeV8ToV9();
        }
        if (from < 10) {
          await _upgradeV9ToV10();
        }
        if (from < 11) {
          await _upgradeV10ToV11();
        }
        if (from < 12) {
          await _upgradeV11ToV12();
        }
        if (from < 13) {
          await _upgradeV12ToV13();
        }
        if (from < 14) {
          await _upgradeV13ToV14();
        }
        if (from < 15) {
          await _upgradeV14ToV15();
        }
        if (from < 16) {
          await _upgradeV15ToV16();
        }
        if (from < 17) {
          await _upgradeV16ToV17();
        }
        if (from < 18) {
          await _upgradeV17ToV18();
        }
        if (from < 19) {
          await _upgradeV18ToV19();
        }
        if (from < 20) {
          await _upgradeV19ToV20();
        }
        if (from < 21) {
          await _upgradeV20ToV21();
        }
        if (from < 22) {
          await _upgradeV21ToV22();
        }
        if (from < 23) {
          await _upgradeV22ToV23();
        }
        if (from < 24) {
          await _upgradeV23ToV24();
        }
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
        // Self-heal a version number that claims more than the file actually
        // has. Drift only runs `onUpgrade` when the stored user_version is
        // BELOW the schema version, so a file stamped v5 without every v5
        // column never gets repaired - and Drift's generated mapper then
        // throws on a non-null read (observed on a real development database
        // whose time_view_settings had no minutes_per_row_chosen column while
        // user_version already read 5).
        await _ensureColumns();
      },
    );
  }

  /// Adds any column the current schema expects but the file lacks.
  ///
  /// Safe to run on every open: each entry is probed first, so a healthy
  /// database does nothing here.
  Future<void> _ensureColumns() async {
    final expected = <String, List<GeneratedColumn<Object>>>{
      'tasks': [tasks.startedAt],
      'completion_logs': [
        completionLogs.actualMinutes,
        completionLogs.includeInModel,
        completionLogs.durationSuspicious,
      ],
      'time_view_settings': [timeViewSettings.minutesPerRowChosen],
      // v6: without these the generated mappers throw on existing rows when a
      // file is stamped v6 but was written by an older build.
      // v7: same reasoning for the agent loop's round cap and the two review
      // preferences (judging mode, card type preference). v15: same reasoning
      // again for the attention-hint switch.
      'local_settings': [
        localSettings.aiEnabled,
        localSettings.aiApiKey,
        localSettings.aiBaseUrl,
        localSettings.aiModel,
        localSettings.aiPermissionMode,
        localSettings.aiMaxRounds,
        localSettings.ankiJudgeMode,
        localSettings.ankiCardTypePreference,
        localSettings.rhythmHintsEnabled,
        // v21: 机制面板上那个"装目标机制"的开关。老文件被盖成 v21 却没有这一列
        // 时，Drift 会跳过 onUpgrade，映射器会在第一次读设置时抛错 —— 与上面
        // 那批列同一个失败模式。
        localSettings.goalMechanismEnabled,
        // v22: 第一个滑块（目标机制的 `beta_goal`）。同一个失败模式：老文件被盖成
        // v22 却没有这一列时，Drift 跳过 onUpgrade，映射器第一次读设置就抛错。
        localSettings.goalBeta,
      ],
      // v16: 认知排序档位的开关（非空、默认 false）。
      'thread_rank_settings': [threadRankSettings.cognitiveRankEnabled],
      'card_states': [
        cardStates.encodingStrength,
        cardStates.savings,
      ],
      // v9: the failure-feedback pair. A file stamped v9 whose review_logs
      // predates the columns would otherwise make the generated mapper throw on
      // the first history read (the same failure mode as the v6 columns above).
      // v11: the pre-review prediction, healed for the same reason.
      'review_logs': [
        reviewLogs.reviewedSolution,
        reviewLogs.closeness,
        reviewLogs.predictedR,
      ],
      // v19: "这条提案确认时是不是本来就有的"。 A file stamped v19 whose
      // proposals table predates the column would make the history dialog throw
      // on the first read - the same failure mode as the columns above.
      // v23: 同一批次的"这一跑做了什么"（`detail_text`）也heal一下：老文件被盖成
      // v23 却没有这一列时，Drift 跳过 onUpgrade，读批次列表就会抛错。
      'material_intake_proposals': [
        materialIntakeProposals.alreadyExisted,
      ],
      'material_intake_batches': [
        materialIntakeBatches.detailText,
      ],
    };
    final m = Migrator(this);
    for (final entry in expected.entries) {
      if (!await _tableExists(entry.key)) {
        continue;
      }
      for (final column in entry.value) {
        await _addColumnIfMissing(m, entry.key, column);
      }
    }
    // v24（轮次一百二十一）：题目编号 + 附件排序。同一个失败模式——老文件被盖成
    // v24 却没有这两列时，Drift 跳过 onUpgrade，读题目/配图的映射器直接抛错。
    // 编号列光补列还不够：不回填的话用户会看见一整屏「TR-未编号」。
    if (await _tableExists('questions') &&
        await _addColumnIfMissing(m, 'questions', questions.serialNo)) {
      await backfillQuestionSerialNumbers();
    }
    if (await _tableExists('attachments')) {
      await _addColumnIfMissing(m, 'attachments', attachments.sortOrder);
    }
    // v8 tables are healed the same way for the same reason. A missing *table*
    // is not a mapper crash but a silent "your plan is gone", which is why this
    // check belongs here next to the column one. v10's three assessment tables
    // heal the same way: a file stamped v10 whose tables are missing (an
    // interrupted migration, or a package import that predates them) would
    // otherwise fail every read with "no such table".
    if (!await _tableExists('review_group_plans')) {
      await m.createTable(reviewGroupPlans);
    }
    if (!await _tableExists('assessment_sessions')) {
      await m.createTable(assessmentSessions);
    }
    if (!await _tableExists('assessment_responses')) {
      await m.createTable(assessmentResponses);
    }
    if (!await _tableExists('cognitive_priors')) {
      await m.createTable(cognitivePriors);
    }
    // v12's four tables heal the same way. A file stamped v12 whose tables are
    // missing would fail every 组卷/推理 read with "no such table".
    if (!await _tableExists('questions')) {
      await m.createTable(questions);
    }
    if (!await _tableExists('question_options')) {
      await m.createTable(questionOptions);
    }
    if (!await _tableExists('reasoning_chains')) {
      await m.createTable(reasoningChains);
    }
    if (!await _tableExists('reasoning_steps')) {
      await m.createTable(reasoningSteps);
    }
    // v13's two tables heal the same way: a file stamped v13 whose tables are
    // missing (interrupted migration) would fail every 拍照整理 read with
    // "no such table" - and the queue would look like "我从来没整理过".
    if (!await _tableExists('handwriting_intake_runs')) {
      await m.createTable(handwritingIntakeRuns);
    }
    if (!await _tableExists('handwriting_proposals')) {
      await m.createTable(handwritingProposals);
    }
    // v14's table heals the same way. `exposure_logs` is small, but a file
    // stamped v14 without it would fail every "读过没测" write with
    // "no such table" - and the reading would look like it was never recorded.
    if (!await _tableExists('exposure_logs')) {
      await m.createTable(exposureLogs);
    }
    // v17's two tables heal the same way: a file stamped v17 whose tables are
    // missing (interrupted migration) would fail every 材料摄取 read with
    // "no such table" - and a confirmed batch would look like it never happened.
    if (!await _tableExists('material_intake_batches')) {
      await m.createTable(materialIntakeBatches);
    }
    if (!await _tableExists('material_intake_proposals')) {
      await m.createTable(materialIntakeProposals);
    }
    // v18's clue-edge table heals the same way: a file stamped v18 without it
    // would fail every material connection write with "no such table" - and a
    // confirmed connection would look like it was never made.
    if (!await _tableExists('knowledge_edges')) {
      await m.createTable(knowledgeEdges);
    }
  }

  /// v4 -> v5: the day/week grid no longer defaults to whole-hour rows.
  ///
  /// The old shipped default was 60 minutes per row. Everyone who never chose
  /// a row size themselves is moved to the new 30-minute default, while a
  /// deliberate 15/30/60 choice is preserved (that is what
  /// `minutes_per_row_chosen` records).
  /// v5 -> v6: AI conversation storage, AI settings columns, and the two
  /// cognitive-model fields.
  ///
  /// Three separate things land here on purpose, as ONE migration:
  ///
  ///  1. `ai_conversations` / `ai_messages` / `ai_actions` - the conversation is
  ///     the AI surface, so it is ordinary user data (docs/AI_DESIGN.md).
  ///  2. `local_settings` gains the AI configuration columns. Everything is
  ///     nullable/defaulted so an existing row means "AI is off" without a
  ///     rewrite - the app must behave exactly as before until a key is set.
  ///  3. `card_states` gains `encoding_strength` (MindNet `R0`) and `savings`
  ///     (`Sigma`). These are prerequisites for porting the cognitive model:
  ///     without R0 the FSRS curve and MindNet's `R = R0*Psi(t/S)` disagree
  ///     once `R0 < 1`, and without Sigma the stability-increase term is
  ///     incomplete (docs/MINDNET_CONTRACT.md 8.3).
  ///
  /// Additive only, and idempotent: `Migrator.createTable` always emits the
  /// current schema, so a database arriving from v1 already has these tables
  /// after [_upgradeV1ToV2] and every step is existence-probed first.
  Future<void> _upgradeV5ToV6() async {
    final m = Migrator(this);

    if (!await _tableExists('ai_conversations')) {
      await m.createTable(aiConversations);
    }
    if (!await _tableExists('ai_messages')) {
      await m.createTable(aiMessages);
    }
    if (!await _tableExists('ai_actions')) {
      await m.createTable(aiActions);
    }

    if (await _tableExists('local_settings')) {
      for (final column in [
        localSettings.aiEnabled,
        localSettings.aiApiKey,
        localSettings.aiBaseUrl,
        localSettings.aiModel,
        localSettings.aiPermissionMode,
      ]) {
        await _addColumnIfMissing(m, 'local_settings', column);
      }
    }

    if (await _tableExists('card_states')) {
      for (final column in [
        cardStates.encodingStrength,
        cardStates.savings,
      ]) {
        await _addColumnIfMissing(m, 'card_states', column);
      }
    }
  }

  /// v6 -> v7: the agent loop's tool-call budget and the two review preferences
  /// (default judging mode, card type preference) become user settings.
  ///
  /// Additive and deliberately NULL on every existing row: NULL reads as "the
  /// user never chose", which `AiConfig` / `JudgeModePreference` /
  /// `CardTypePreference` resolve to the shipped default. That keeps an upgraded
  /// install behaving exactly as it did before the setting existed, instead of
  /// the migration silently picking a new budget, a new judging mode or a new
  /// card type for it.
  ///
  /// Three unrelated-looking columns land in one migration on purpose: they are
  /// the same class of change (a nullable `local_settings` preference whose
  /// absence means "keep the old behaviour"), and v7 has not shipped yet, so
  /// splitting them would buy a second version number and nothing else.
  Future<void> _upgradeV6ToV7() async {
    if (!await _tableExists('local_settings')) {
      return;
    }
    final m = Migrator(this);
    for (final column in [
      localSettings.aiMaxRounds,
      localSettings.ankiJudgeMode,
      localSettings.ankiCardTypePreference,
    ]) {
      await _addColumnIfMissing(m, 'local_settings', column);
    }
  }

  /// v7 -> v8: the per-group daily review plan table.
  ///
  /// Purely additive and created empty: no row means no configured target, and
  /// an install that never opens the plan UI therefore keeps drawing exactly the
  /// cards it drew before this release. Writing default rows for existing tags
  /// would instead cap every group on upgrade day, which is precisely the
  /// silent card loss this design avoids.
  Future<void> _upgradeV7ToV8() async {
    if (!await _tableExists('review_group_plans')) {
      await Migrator(this).createTable(reviewGroupPlans);
    }
  }

  /// v8 -> v9: the two failure-feedback columns on `review_logs`.
  ///
  /// Both are nullable and stay NULL for every existing row, which is exactly
  /// right: a review written before this version was never asked "did you read
  /// the answer?", and inventing `false` for those rows would claim every past
  /// miss was a bare lapse. The model's own two columns
  /// (`card_states.encoding_strength` / `savings`) are untouched - the event
  /// this migration records is one the review flow already had to ask for, not
  /// a recomputation of history.
  Future<void> _upgradeV8ToV9() async {
    if (!await _tableExists('review_logs')) {
      return;
    }
    final m = Migrator(this);
    for (final column in [
      reviewLogs.reviewedSolution,
      reviewLogs.closeness,
    ]) {
      await _addColumnIfMissing(m, 'review_logs', column);
    }
  }

  /// v9 -> v10: the three assessment tables (`docs/ASSESSMENT_DESIGN.md` §5).
  ///
  /// Purely additive and created **empty**, for the same reason as v8: no
  /// session means nothing has been measured, and an install that never opens
  /// the assessment surface must keep reading exactly the priors-absent
  /// behaviour it had before. Every table is probed first so a file that
  /// already carries them (an interrupted migration, or a database created
  /// from the v10 schema but stamped lower) upgrades without a duplicate-table
  /// error.
  Future<void> _upgradeV9ToV10() async {
    final m = Migrator(this);
    if (!await _tableExists('assessment_sessions')) {
      await m.createTable(assessmentSessions);
    }
    if (!await _tableExists('assessment_responses')) {
      await m.createTable(assessmentResponses);
    }
    if (!await _tableExists('cognitive_priors')) {
      await m.createTable(cognitivePriors);
    }
  }

  /// v10 -> v11: the pre-review prediction on `review_logs` (M6 calibration).
  ///
  /// Additive and NULL for every existing row, which is the only honest value:
  /// the prediction was never recorded, and recomputing one now would be
  /// inventing a prediction that did not exist when the user answered. The
  /// calibration curve therefore starts empty and fills up from here.
  Future<void> _upgradeV10ToV11() async {
    if (!await _tableExists('review_logs')) {
      return;
    }
    await _addColumnIfMissing(
        Migrator(this), 'review_logs', reviewLogs.predictedR);
  }

  /// v11 -> v12: the question bank and the reasoning layer
  /// (`docs/QUESTION_BANK_DESIGN.md`).
  ///
  /// Four new tables, nothing touched on existing ones: questions and their
  /// options are append-only user data, the chains and steps are derived data
  /// that the AI can regenerate. Existence-probed so the v1 -> v12 path (where
  /// `createAll` already emitted the current schema) is a no-op.
  Future<void> _upgradeV11ToV12() async {
    final m = Migrator(this);
    if (!await _tableExists('questions')) {
      await m.createTable(questions);
    }
    if (!await _tableExists('question_options')) {
      await m.createTable(questionOptions);
    }
    if (!await _tableExists('reasoning_chains')) {
      await m.createTable(reasoningChains);
    }
    if (!await _tableExists('reasoning_steps')) {
      await m.createTable(reasoningSteps);
    }
  }

  /// v12 -> v13: the handwriting-intake proposal tables
  /// (`docs/HANDWRITING_INTAKE_DESIGN.md` §4).
  ///
  /// Two new tables, nothing touched on existing ones. Proposals used to live in
  /// memory only: photograph three pages, sort them, restart the app - and the
  /// twelve proposals were gone while the photos stayed on disk. They are
  /// pending *user data*, not a cache: whether a row was already applied decides
  /// whether confirming it again would write a second flashcard. Existence-
  /// probed so the v12 (createAll) path is a no-op.
  Future<void> _upgradeV12ToV13() async {
    final m = Migrator(this);
    if (!await _tableExists('handwriting_intake_runs')) {
      await m.createTable(handwritingIntakeRuns);
    }
    if (!await _tableExists('handwriting_proposals')) {
      await m.createTable(handwritingProposals);
    }
  }

  /// v13 -> v14: the exposure log (`docs/MINDNET_ROADMAP.md` §2).
  ///
  /// One new table, nothing touched on existing ones. `exposure_logs` records
  /// "我读了，但没测自己" - MindNet's `exposure` action, the last of the five
  /// `mindnet.run/1` actions the app could not produce. It is deliberately not a
  /// `review_logs` row: that table is the test record the retention buckets and
  /// the calibration curve are computed from, and a reading is not a recall test.
  /// Existence-probed so the v13 (createAll) path is a no-op.
  Future<void> _upgradeV13ToV14() async {
    final m = Migrator(this);
    if (!await _tableExists('exposure_logs')) {
      await m.createTable(exposureLogs);
    }
  }

  /// v14 -> v15: the attention-hint switch on `local_settings`
  /// (`docs/MINDNET_ROADMAP.md` §3 row 4).
  ///
  /// One nullable column, nothing else touched. NULL carries a real meaning
  /// here - "the user never chose" - which the app resolves to the shipped
  /// default (show the reading). The migration therefore writes no value at all:
  /// an upgraded row keeps reading as "never chose" instead of being frozen to
  /// today's default. Probed through [_addColumnIfMissing] so the v14
  /// (createAll) path is a no-op.
  Future<void> _upgradeV14ToV15() async {
    if (!await _tableExists('local_settings')) {
      return;
    }
    final m = Migrator(this);
    await _addColumnIfMissing(
        m, 'local_settings', localSettings.rhythmHintsEnabled);
  }

  /// v15 -> v16：`thread_rank_settings.cognitive_rank_enabled`（认知排序档位的开关，
  /// `docs/MINDNET_ROADMAP.md` §2-D）。
  ///
  /// 与 v15 那一列不同，这一列**非空且带默认 false**：迁移不能替用户打开一个还没
  /// 标定的排序档位，老文件升级后读到的必须还是原来的加权次序。
  Future<void> _upgradeV15ToV16() async {
    if (!await _tableExists('thread_rank_settings')) {
      return;
    }
    final m = Migrator(this);
    await _addColumnIfMissing(
        m, 'thread_rank_settings', threadRankSettings.cognitiveRankEnabled);
  }

  /// v16 -> v17：两张「材料摄取」表（`docs/MINDNET_ROADMAP.md` §2-C ①，轮次六十四）。
  ///
  /// 两张表都是纯新增，老行不动：`material_intake_batches` 的主键就是信封的
  /// `batch_id`（INGEST 契约的幂等键），`material_intake_proposals` 记每条待确认
  /// 提案与它的 `applied_at`。存在性探测让 v17 的 createAll 路径成为 no-op。
  Future<void> _upgradeV16ToV17() async {
    final m = Migrator(this);
    if (!await _tableExists('material_intake_batches')) {
      await m.createTable(materialIntakeBatches);
    }
    if (!await _tableExists('material_intake_proposals')) {
      await m.createTable(materialIntakeProposals);
    }
  }

  /// v17 -> v18：线索边表（`docs/MINDNET_ROADMAP.md` §2-C ④，轮次六十八）。
  ///
  /// 纯新增，老行不动。在此之前资料的连接一律只报 `deferred`（没有落点）；
  /// 这张表定了口径：材料的连接是**线索边**（严格有向、`ls` 带未标定标记），
  /// 包含语义仍然只有标签树父子边那一处（`MEMORY_RECORD.md` §3.5）。
  Future<void> _upgradeV17ToV18() async {
    final m = Migrator(this);
    if (!await _tableExists('knowledge_edges')) {
      await m.createTable(knowledgeEdges);
    }
  }

  /// v18 -> v19：`material_intake_proposals.already_existed`（轮次七十五）。
  ///
  /// 纯新增一列，老行不动。它让"已经确认完的历史"能说清每一行是这次新建的、
  /// 还是确认时库里就有的（原来的成绩单只活在那一次调用里，重启就没了）。
  Future<void> _upgradeV18ToV19() async {
    if (!await _tableExists('material_intake_proposals')) {
      return;
    }
    final m = Migrator(this);
    await _addColumnIfMissing(
        m, 'material_intake_proposals', materialIntakeProposals.alreadyExisted);
  }

  /// v19 -> v20：撤回流水（`material_intake_undo_logs`，轮次八十二）。
  ///
  /// 纯新增表，老行不动。撤回会**删掉**点/边，删完就再没有别的物证说"这里曾经
  /// 建过什么、什么时候撤的"——这张 append-only 的表把每次撤回请求（撤成的、
  /// 被拦住的）连同删掉的行一起记下来。
  Future<void> _upgradeV19ToV20() async {
    final m = Migrator(this);
    if (!await _tableExists('material_intake_undo_logs')) {
      await m.createTable(materialIntakeUndoLogs);
    }
  }

  /// v20 -> v21：`local_settings.goal_mechanism_enabled`（轮次八十六）。
  ///
  /// 纯新增一列，老行不动。这是 roadmap §3 第 8 行"用户侧开关"的第一个：
  /// 库诊断那一跑要不要装目标机制（`context.goal`）。列可空、NULL 读作"装"，
  /// 所以升级过来的库行为**一个字不变**，直到用户自己关掉。
  Future<void> _upgradeV20ToV21() async {
    final m = Migrator(this);
    await _addColumnIfMissing(
        m, 'local_settings', localSettings.goalMechanismEnabled);
  }

  /// v21 -> v22：`local_settings.goal_beta`（轮次八十九）。
  ///
  /// 纯新增一列，老行不动。这是 roadmap §3 第 8 行"用户侧滑块"的第一个：目标机制
  /// 的牵引强度（`context.goal.beta_goal`）。列可空、NULL 读作转录表里的出厂值，
  /// 所以升级过来的库那一跑用的数字**一个都不变**，直到用户自己拖动滑块。
  Future<void> _upgradeV21ToV22() async {
    final m = Migrator(this);
    await _addColumnIfMissing(m, 'local_settings', localSettings.goalBeta);
  }

  /// v22 -> v23：`material_intake_batches.detail_text`（轮次一百）。
  ///
  /// 纯新增一列，老行不动。`run/1` 那条路落提案时把"这一跑到底做了什么"（每条动作的
  /// 引擎原话 + 它回报的读数）一起存下来 —— 演练本身不落库，但这句话要留得住：
  /// 人过几天回来点头时，还看得见当时跑的是什么。材料信封那条路不写这一列（NULL）。
  Future<void> _upgradeV22ToV23() async {
    // 被盖成 v23 却没有这两张表的老文件（v17 那种"表还没建"的状态）会走到这里：
    // 没有表就什么都别加 —— 建表是 `_ensureColumns` 自愈那一步的事，在这里碰它会让
    // Drift 的映射器抛 `unknown table`（`_upgradeV4ToV5` 同一个道理）。
    if (!await _tableExists('material_intake_batches')) {
      return;
    }
    final m = Migrator(this);
    await _addColumnIfMissing(
        m, 'material_intake_batches', materialIntakeBatches.detailText);
  }

  /// v23 -> v24：题目编号 `questions.serial_no` + 附件排序
  /// `attachments.sort_order`（轮次一百二十一）。
  ///
  /// 两列都是纯新增，但编号列补完必须回填：用户已有的题不能升级完一片
  /// 「TR-未编号」。回填按 `(created_at, id)`——先入库的号小，id 兜底让同一毫秒
  /// 内的顺序也是确定的（见 [backfillQuestionSerialNumbers]）。
  ///
  /// 表不存在就跳过：被盖成 v24 的空文件由 `_ensureColumns` 建表自愈，
  /// 在这里建表会让 Drift 映射器抛 unknown table（[_upgradeV22ToV23] 同一个道理）。
  Future<void> _upgradeV23ToV24() async {
    final m = Migrator(this);
    if (await _tableExists('questions')) {
      await _addColumnIfMissing(m, 'questions', questions.serialNo);
    }
    if (await _tableExists('attachments')) {
      await _addColumnIfMissing(m, 'attachments', attachments.sortOrder);
    }
    await backfillQuestionSerialNumbers();
  }

  Future<void> _upgradeV4ToV5() async {
    if (!await _tableExists('time_view_settings')) {
      return;
    }
    // A database whose time_view_settings was created from the pre-v5 schema
    // has no `minutes_per_row_chosen` column, and Drift cannot map its rows
    // without it (the generated mapper does a non-null read). Add it first;
    // that also records "no deliberate choice" for every existing row, which
    // is exactly the state the UPDATE below needs.
    final m = Migrator(this);
    await _addColumnIfMissing(
        m, 'time_view_settings', timeViewSettings.minutesPerRowChosen);
    await customStatement(
      'UPDATE time_view_settings SET minutes_per_row = 30 '
      'WHERE minutes_per_row_chosen = 0',
    );
  }

  /// v3 -> v4 (Time module, user feedback item 3): weekly/daily schedule
  /// templates and the single-row view preferences for the long-range
  /// timeline. Additive only; guarded by existence probes so the v1 -> v4 and
  /// v2 -> v4 paths (where `createTable` already emitted the current schema)
  /// do not fail.
  Future<void> _upgradeV3ToV4() async {
    final m = Migrator(this);
    if (!await _tableExists('time_templates')) {
      await m.createTable(timeTemplates);
    }
    if (!await _tableExists('time_view_settings')) {
      await m.createTable(timeViewSettings);
    }
  }

  /// v2 -> v3 (blueprint v2 / user annotations 2026-09-08):
  /// - Tasks.started_at: the moment the user started the event.
  /// - CompletionLogs.actual_minutes / include_in_model / duration_suspicious:
  ///   actual duration recorded from two stamps, plus the anomaly guard.
  /// - New tables: thread_rank_settings (public, editable ranking parameters)
  ///   and diffusion_logs (daily study ledger for the review-insight screen).
  ///
  /// Purely additive: no existing column is rewritten, so legacy rows keep
  /// working (they read as NULL / defaulted).
  ///
  /// Idempotent on purpose: `Migrator.createTable` always emits the CURRENT
  /// schema, so a database coming from v1 already has the v3 columns (and the
  /// v3 tables) after [_upgradeV1ToV2] ran. Everything here is therefore
  /// guarded by an existence probe so the v1 -> v3 path does not double-add.
  Future<void> _upgradeV2ToV3() async {
    final m = Migrator(this);

    if (!await _tableExists('thread_rank_settings')) {
      await m.createTable(threadRankSettings);
    }
    if (!await _tableExists('diffusion_logs')) {
      await m.createTable(diffusionLogs);
    }

    await _addColumnIfMissing(m, 'tasks', tasks.startedAt);
    await _addColumnIfMissing(
        m, 'completion_logs', completionLogs.actualMinutes);
    await _addColumnIfMissing(
        m, 'completion_logs', completionLogs.includeInModel);
    await _addColumnIfMissing(
        m, 'completion_logs', completionLogs.durationSuspicious);
  }

  /// 补一列；返回**是否真的补了**。
  ///
  /// 返回值是给需要"补完还要办事"的迁移用的：v24 的题目编号光加一列不够，老行
  /// 得回填（见 [_upgradeV23ToV24] 与 [backfillQuestionSerialNumbers]）。返回
  /// `false` 表示列已经在了——也可能是上一次补完但事务没收尾，所以调用方只该
  /// 用这个值决定"要不要多做一步"，不该拿它当"第一次到这里"的凭据。
  Future<bool> _addColumnIfMissing(
    Migrator m,
    String table,
    GeneratedColumn<Object> column,
  ) async {
    if (await _columnExists(table, column.name)) {
      return false;
    }
    await m.addColumn(_tableFor(table), column);
    return true;
  }

  // --- logical dump support (.tfpkg) ---------------------------------------

  /// Every user table in the database, in dependency-friendly order.
  ///
  /// Excludes SQLite's own bookkeeping and Drift's migration metadata. Reading
  /// the list instead of hard-coding it means a new table is exported
  /// automatically and can never be forgotten in a backup.
  Future<List<String>> userTables() async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ).get();
    return [for (final row in rows) row.read<String>('name')];
  }

  /// The column names of [table].
  Future<List<String>> columnsOf(String table) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return [for (final row in rows) row.read<String>('name')];
  }

  /// Reads a whole table as JSON-safe maps.
  Future<List<Map<String, dynamic>>> dumpTable(String table) async {
    final rows = await customSelect('SELECT * FROM $table').get();
    return [
      for (final row in rows)
        {
          for (final name in row.data.keys) name: _toJsonSafe(row.data[name]),
        },
    ];
  }

  /// Writes rows into [table], inserting only the columns that both the file
  /// and the current schema know about.
  ///
  /// [mode] `replace` empties the table first (used by the overwrite import),
  /// `insert` leaves existing rows alone and skips primary-key clashes (used
  /// by the append import).
  Future<int> restoreTable(
    String table,
    List<Map<String, dynamic>> rows, {
    String mode = 'insert',
  }) async {
    if (rows.isEmpty) {
      return 0;
    }
    final known = (await columnsOf(table)).toSet();
    if (mode == 'replace') {
      await customStatement('DELETE FROM $table');
    }
    var written = 0;
    for (final row in rows) {
      final entries = [
        for (final entry in row.entries)
          if (known.contains(entry.key)) entry,
      ];
      if (entries.isEmpty) {
        continue;
      }
      final columns = entries.map((e) => e.key).join(', ');
      final placeholders = List.filled(entries.length, '?').join(', ');
      final verb = mode == 'replace' ? 'INSERT' : 'INSERT OR IGNORE';
      await customStatement(
        '$verb INTO $table ($columns) VALUES ($placeholders)',
        [for (final entry in entries) _fromJsonSafe(entry.value)],
      );
      written++;
    }
    return written;
  }

  /// Turns a stored value into something `jsonEncode` accepts.
  ///
  /// BLOBs are the only awkward case: they are base64-tagged so a round trip
  /// through JSON stays byte-exact instead of turning into a list of numbers.
  static Object? _toJsonSafe(Object? value) {
    if (value is Uint8List) {
      return {'__blob__': base64Encode(value)};
    }
    return value;
  }

  /// Reverses [_toJsonSafe].
  static Object? _fromJsonSafe(Object? value) {
    if (value is Map && value.containsKey('__blob__')) {
      return base64Decode(value['__blob__'] as String);
    }
    return value;
  }

  /// The generated table object for a SQL table name.
  ///
  /// Used by the `_ensureColumns` self-heal pass and by the `.tfpkg` dump /
  /// restore path, so every table those two touch must appear here.
  TableInfo<Table, dynamic> _tableFor(String name) {
    switch (name) {
      case 'tasks':
        return tasks;
      case 'completion_logs':
        return completionLogs;
      case 'time_view_settings':
        return timeViewSettings;
      case 'time_templates':
        return timeTemplates;
      // v6: the self-heal pass adds columns to these two, and the package
      // dump/restore path resolves every user table by name.
      case 'local_settings':
        return localSettings;
      case 'card_states':
        return cardStates;
      case 'ai_conversations':
        return aiConversations;
      case 'ai_messages':
        return aiMessages;
      case 'ai_actions':
        return aiActions;
      // v8: the self-heal pass creates it when a file claims v8 without it, and
      // the package dump/restore path resolves every user table by name.
      case 'review_group_plans':
        return reviewGroupPlans;
      // v9: the self-heal pass adds the two review-log columns, so opening a
      // file that claims v9 must be able to resolve the table by name.
      case 'review_logs':
        return reviewLogs;
      // v16: the self-heal pass adds the cognitive-ranking switch, and the
      // package dump/restore path resolves every user table by name.
      case 'thread_rank_settings':
        return threadRankSettings;
      // v19: the self-heal pass adds the "was it already there" column, so a
      // file claiming v19 must be able to resolve the table by name.
      case 'material_intake_proposals':
        return materialIntakeProposals;
      // v23: 自愈那一趟要给批次表补 `detail_text`（"这一跑做了什么"），所以一个
      // 声称 v23 的文件必须能按名字解析到这张表 —— 否则自愈会抛 unknown table。
      case 'material_intake_batches':
        return materialIntakeBatches;
      // v24（轮次一百二十一）：自愈那一趟要给题目补编号、给附件补排序，所以一个
      // 声称 v24 的文件必须能按名字解析到这两张表 —— 否则自愈会抛 unknown table。
      case 'questions':
        return questions;
      case 'attachments':
        return attachments;
      default:
        throw ArgumentError('unknown table $name');
    }
  }

  Future<bool> _tableExists(String name) async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(name)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> _columnExists(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    for (final row in rows) {
      if (row.read<String>('name') == column) {
        return true;
      }
    }
    return false;
  }

  /// 给还没有编号的题补上编号（v24 迁移、版本号自愈、v23 及更早的包导入之后
  /// 都会走到这里）。返回补了多少行。
  ///
  /// 规则：
  /// - 已经有号的题一律不动——用户见过的号不能变；
  /// - 没有号（NULL）的按 `(created_at, id)` 从前往后，接着当前最大号往下排；
  /// - 删题不回收号，所以号只增不减。
  ///
  /// 刻意逐行 UPDATE 而不用窗口函数：这条路径要跑在三种 SQLite 上（Flutter 自带
  /// 的、测试里的 dart:ffi、用户升级上来的老文件），逐行语义在哪儿都一样；量级
  /// 只是"题库里有多少道题"，一次性迁移慢不到哪去。
  Future<int> backfillQuestionSerialNumbers() async {
    if (!await _tableExists('questions') ||
        !await _columnExists('questions', 'serial_no')) {
      return 0;
    }
    final maxRow = await customSelect(
      'SELECT COALESCE(MAX(serial_no), 0) AS max_serial FROM questions',
    ).getSingle();
    var next = maxRow.read<int>('max_serial');
    final pending = await customSelect(
      'SELECT id FROM questions WHERE serial_no IS NULL ORDER BY created_at, id',
    ).get();
    if (pending.isEmpty) {
      return 0;
    }
    for (final row in pending) {
      next += 1;
      await customStatement(
        'UPDATE questions SET serial_no = ? WHERE id = ?',
        [next, row.read<String>('id')],
      );
    }
    return pending.length;
  }

  /// v1 -> v2: new tables, new columns, relaxed card_state /
  /// review_log FKs and backfills. See docs/DATA_MODEL.md §7.
  ///
  /// The rebuilds (card_states, review_logs) run while foreign keys are still
  /// OFF (they are only enabled in beforeOpen), so dropping/renaming parent
  /// tables mid-migration cannot trip FK enforcement.
  Future<void> _upgradeV1ToV2() async {
    final m = Migrator(this);

    // 1. New tables.
    await m.createTable(threadStates);
    await m.createTable(taskTemplates);
    await m.createTable(completionLogs);
    await m.createTable(clozeSlots);
    await m.createTable(clozeHistory);
    await m.createTable(boostEntries);
    await m.createTable(themes);
    await m.createTable(attachments);

    // 2. Plain ADD COLUMN on existing tables.
    await m.addColumn(tasks, tasks.expectedAt);
    await m.addColumn(tasks, tasks.energyRequired);
    await m.addColumn(tasks, tasks.completedAt);
    await m.addColumn(localSettings, localSettings.activeThemeId);
    await m.addColumn(knowledgePoints, knowledgePoints.contentFormat);
    await m.addColumn(tags, tags.parentId);
    await m.addColumn(tags, tags.path);

    // 3. Rebuild card_states with nullable card_template_id + v2 fields.
    await customStatement('''
CREATE TABLE card_states_new (
  id TEXT NOT NULL PRIMARY KEY,
  card_template_id TEXT REFERENCES card_templates(id),
  due_at INTEGER,
  interval_days REAL NOT NULL DEFAULT 0,
  ease REAL NOT NULL DEFAULT 2.5,
  repetitions INTEGER NOT NULL DEFAULT 0,
  lapses INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL DEFAULT 'new',
  last_reviewed_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  knowledge_point_id TEXT REFERENCES knowledge_points(id),
  unit_key TEXT,
  stability REAL,
  difficulty REAL,
  forced INTEGER NOT NULL DEFAULT 0,
  forced_streak INTEGER NOT NULL DEFAULT 0
)''');
    await customStatement('''
INSERT INTO card_states_new (
  id, card_template_id, due_at, interval_days, ease, repetitions, lapses,
  state, last_reviewed_at, created_at, updated_at
)
SELECT id, card_template_id, due_at, interval_days, ease, repetitions, lapses,
       state, last_reviewed_at, created_at, updated_at
FROM card_states''');
    await customStatement('DROP TABLE card_states');
    await customStatement('ALTER TABLE card_states_new RENAME TO card_states');

    // 4. Backfill presentation-unit fields for legacy preset cards.
    await customStatement('''
UPDATE card_states
SET knowledge_point_id = (
      SELECT knowledge_point_id FROM card_templates t
      WHERE t.id = card_states.card_template_id
    ),
    unit_key = 'preset:' || card_template_id
WHERE card_template_id IS NOT NULL''');

    // 5. Rebuild review_logs with nullable card_template_id + v2 fields.
    await customStatement('''
CREATE TABLE review_logs_new (
  id TEXT NOT NULL PRIMARY KEY,
  card_state_id TEXT REFERENCES card_states(id),
  card_template_id TEXT REFERENCES card_templates(id),
  unit_key TEXT,
  rating INTEGER NOT NULL,
  rating_fsrs INTEGER,
  correct INTEGER,
  judge_mode TEXT,
  format TEXT,
  ms_taken INTEGER,
  reviewed_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
)''');
    await customStatement('''
INSERT INTO review_logs_new (
  id, card_state_id, card_template_id, rating, reviewed_at, created_at
)
SELECT id, card_state_id, card_template_id, rating, reviewed_at, created_at
FROM review_logs''');
    await customStatement('DROP TABLE review_logs');
    await customStatement('ALTER TABLE review_logs_new RENAME TO review_logs');

    // 6. Tags: backfill authoritative path, de-duplicate same-name top tags
    // (keep the oldest id plain, suffix the rest).
    await customStatement("UPDATE tags SET path = name WHERE path IS NULL");
    await customStatement('''
UPDATE tags
SET path = name || '-' || rn
FROM (
  SELECT id, ROW_NUMBER() OVER (PARTITION BY name ORDER BY id) AS rn
  FROM tags
) x
WHERE tags.id = x.id AND x.rn > 1''');
    await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_path ON tags(path)');

    // 7. v2 indexes.
    await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_card_states_unit '
        'ON card_states(knowledge_point_id, unit_key)');
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final target = File(p.join(dir.path, 'furnace.db'));

    // Database file resolution, newest name first.
    //
    // The app has been renamed twice, and each name used to own the database
    // file. An existing install must keep its data, so the legacy names are
    // still served - the schema migration runs in place on open, exactly as it
    // did when the file was current.
    //
    //   furnace.db      (current)
    //   threadflow.db   (previous name)
    //   knowflow.db     (original name)
    final active = _adoptLegacyDatabase(dir, target);
    return instrumentWrites(NativeDatabase(active));
  });
}

/// Wraps a raw executor so that every committed write reaches the
/// [DataChangeBus] (see `db_write_interceptor.dart`).
///
/// Kept public and separate from [_openConnection] so a test can install the
/// exact same instrumentation on an in-memory database and prove that a write
/// through a repository is observable.
QueryExecutor instrumentWrites(QueryExecutor inner) {
  return inner.interceptWith(DbWriteInterceptor());
}

/// Resolves the file that actually holds this install's data.
///
/// Two kinds of legacy layout have to keep working:
///
///  1. **Same directory, older file name.** `furnace.db` / `threadflow.db` /
///     `knowflow.db` inside the current app-support directory.
///  2. **Older directory.** `getApplicationSupportDirectory()` is derived from
///     the executable's company/product metadata on Windows and from the
///     application id on Android. Renaming the app changed both, so a
///     pre-rename install keeps its data under a *different* directory. That
///     case cannot be handled by file-name fallback alone, which is exactly how
///     the rename could have silently started the user on an empty database.
///
/// When a legacy database is found in another directory it is **copied** to
/// [target] and the copy wins from then on. The copy is deliberate, not a move:
/// if it fails, the original is left untouched and the app keeps using it.
///
/// Verified on this machine: renaming the Windows metadata moved the directory
/// from `%APPDATA%\com.example\knowflow` to `%APPDATA%\FirsryFan\Furnace`, and
/// the legacy file there held the real rows (time blocks) while the freshly
/// created `furnace.db` held only seed data. After the fix, the copy landed at
/// the new path with an identical file hash and the original was untouched.
///
/// [applicationDataDir] overrides the roaming-app-data root and exists for
/// tests; production always reads the environment.
File _adoptLegacyDatabase(
  Directory dir,
  File target, {
  String? applicationDataDir,
}) {
  if (target.existsSync()) return target;

  for (final name in const ['threadflow.db', 'knowflow.db']) {
    final sibling = File(p.join(dir.path, name));
    if (sibling.existsSync()) return sibling;
  }

  final missed = _firstLegacyDirectoryOutside(dir, applicationDataDir);
  if (missed != null) {
    try {
      missed.copySync(target.path);
      return target;
    } on FileSystemException {
      // Read-only or full disk: never lose the data, keep using the original.
      return missed;
    }
  }

  return target;
}

/// Test seam for [_adoptLegacyDatabase]: the file-name/directory resolution that
/// decides which database an install actually opens.
///
/// Exposed because the failure it guards against is invisible in normal use -
/// a wrong answer is not an exception, it is an empty-looking app.
File resolveDatabaseFileForTest(
  String currentDirectory,
  File target, {
  String? applicationDataDir,
}) =>
    _adoptLegacyDatabase(
      Directory(currentDirectory),
      target,
      applicationDataDir: applicationDataDir,
    );

/// Looks in the directories this install used before the rename.
///
/// A candidate only counts when it actually holds a database, so an empty
/// leftover directory never hijacks a fresh install.
File? _firstLegacyDirectoryOutside(Directory current,
    [String? applicationDataDir]) {
  final appData = applicationDataDir ?? Platform.environment['APPDATA'];
  final candidates = <String>[
    if (appData != null && appData.isNotEmpty)
      p.join(appData, 'com.example', 'knowflow'),
    if (appData != null && appData.isNotEmpty)
      p.join(appData, 'FirsryFan', 'Furnace'),
    p.join(p.dirname(current.path), 'knowflow'),
  ];

  for (final candidate in candidates) {
    if (p.equals(candidate, current.path)) continue;
    for (final name in const ['furnace.db', 'threadflow.db', 'knowflow.db']) {
      final file = File(p.join(candidate, name));
      if (file.existsSync() && file.lengthSync() > 0) return file;
    }
  }
  return null;
}
