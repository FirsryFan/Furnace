import 'package:drift/drift.dart';

import '../../features/ai/domain/agent_preset.dart';
import '../../features/ai/domain/conversation_title.dart';
import '../../features/ai/domain/model_adapter.dart' show ReasoningEffort;
import '../database/database.dart';
import '../ids.dart';

/// Thrown when a caller tries to change a conversation's preset after the
/// conversation has started.
///
/// DSH semantics: a preset is selected on a **blank** session and is immutable
/// from its first message/run. This is a programming/wiring error, not a user
/// action, so it is an exception rather than a silently ignored write.
class ConversationPresetsLockedException implements Exception {
  const ConversationPresetsLockedException(this.conversationId);

  final String conversationId;

  @override
  String toString() =>
      'conversation $conversationId has started; its preset is immutable';
}

/// How much the AI is allowed to do without asking (see docs/AI_DESIGN.md
/// §6.1 D12 v2).
///
/// Deliberately only two values. The user's decision was "everything except
/// deletion may run automatically", so a third "read-only" mode would be an
/// option nobody asked for, and a "full auto" mode is excluded by design:
/// deletion is never automatic, in any mode.
enum AiPermissionMode {
  /// Every write from one turn is collected into a single list the user
  /// approves once. Deletion is still asked one by one.
  plan('plan', '按计划'),

  /// Non-destructive writes run immediately and are recorded in the action
  /// ledger so they can be undone. Deletion still asks one by one.
  auto('auto', '自动');

  const AiPermissionMode(this.id, this.label);

  /// Stable value stored in the database. Never localise this.
  final String id;

  /// Display label (Chinese UI is the primary locale here).
  final String label;

  static AiPermissionMode fromId(String? id) => switch (id) {
        'plan' => AiPermissionMode.plan,
        'auto' => AiPermissionMode.auto,
        // Anything unreadable (including NULL on an upgraded database) means
        // the safer of the two.
        _ => AiPermissionMode.plan,
      };
}

/// Everything needed to talk to a model provider.
class AiConfig {
  const AiConfig({
    required this.enabled,
    this.apiKey,
    this.baseUrl,
    this.model,
    this.permissionMode = AiPermissionMode.plan,
    this.maxRounds = defaultMaxRounds,
    this.reasoningEffort,
    this.temperature,
    this.answerTemperature,
    this.verifierTemperature,
    this.maxReasoningTokens,
    this.answerReserveTokens,
    this.verifierModel,
    this.verifierEffort,
  });

  /// The master switch. When false the rest is ignored and the app must make
  /// no network call at all.
  final bool enabled;

  final String? apiKey;
  final String? baseUrl;
  final String? model;
  final AiPermissionMode permissionMode;

  /// How many model round-trips one user message may spend: the agent loop's
  /// tool-call budget (`AgentLoop.maxRounds`).
  ///
  /// A paid call per round, so this is a user setting rather than a constant:
  /// "look something up, then act on it, then confirm" fits in the default,
  /// while a longer multi-step task may need more than the default allows.
  final int maxRounds;

  // --- model-parameter layer (v46, 2026-11-15) -----------------------------
  //
  // Every field below is nullable, and NULL keeps its documented meaning
  // everywhere: "the user never chose". The `effective*` getters resolve that
  // to the shipped default, which is exactly the value the code used before
  // this layer existed - so an install that never touches these settings keeps
  // the old wire requests byte for byte.

  /// Thinking effort for the student solver's reasoning turn. NULL = do not
  /// send `reasoning_effort`.
  final ReasoningEffort? reasoningEffort;

  /// Temperature of the reasoning/solve turn. NULL = [defaultTemperature].
  final double? temperature;

  /// Temperature of the answer-scribe turn. NULL = [defaultAnswerTemperature].
  final double? answerTemperature;

  /// Temperature of the verifier turn. NULL = [defaultVerifierTemperature].
  final double? verifierTemperature;

  /// `max_tokens` of the reasoning turn. NULL = [defaultMaxReasoningTokens].
  final int? maxReasoningTokens;

  /// `max_tokens` of the answer-scribe and verifier turns.
  /// NULL = [defaultAnswerReserveTokens].
  final int? answerReserveTokens;

  /// Model for the verifier turn. Blank/NULL = the solver's model.
  final String? verifierModel;

  /// Thinking effort for the verifier turn. NULL = do not send
  /// `reasoning_effort` (deliberately not inherited from [reasoningEffort]).
  final ReasoningEffort? verifierEffort;

  /// DeepSeek's OpenAI-compatible endpoint. Kept here rather than in the
  /// adapter so the default is visible next to the setting it belongs to.
  static const String defaultBaseUrl = 'https://api.deepseek.com';
  static const String defaultModel = 'deepseek-chat';

  /// The shipped reasoning-turn temperature. 0.6 was the literal in
  /// `ai_providers.dart` before the parameter layer existed.
  static const double defaultTemperature = 0.6;

  /// The shipped answer-scribe temperature (old literal: 0.2).
  static const double defaultAnswerTemperature = 0.2;

  /// The shipped verifier temperature (old behaviour: the verifier reused the
  /// answer adapter, so 0.2).
  static const double defaultVerifierTemperature = 0.2;

  /// The shipped reasoning-turn output budget (old literal: 20 000).
  static const int defaultMaxReasoningTokens = 20000;

  /// The shipped answer-scribe / verifier output budget (old literal: 3 000).
  static const int defaultAnswerReserveTokens = 3000;

  /// DeepSeek's documented `temperature` range (0..2). Anything stored outside
  /// it is clamped on the way out, so a hand-edited file cannot send a request
  /// the API rejects.
  static const double minTemperature = 0;
  static const double maxTemperature = 2;

  /// DeepSeek's documented `max_tokens` upper bound for Chat Completions
  /// (393 216 = 384K, checked 2026-11-15). Lower bound 1.
  static const int maxOutputTokens = 393216;
  static const int minOutputTokens = 1;

  /// [stored] as a usable temperature: [fallback] when nothing was chosen,
  /// clamped into [minTemperature]..[maxTemperature] otherwise. A NaN (which
  /// SQLite can hold) also falls back rather than poisoning the request body.
  static double resolveTemperature(double? stored, double fallback) {
    if (stored == null || stored.isNaN || stored.isInfinite) {
      return fallback;
    }
    return stored.clamp(minTemperature, maxTemperature).toDouble();
  }

  /// [stored] as a usable output budget, clamped into
  /// [minOutputTokens]..[maxOutputTokens].
  static int resolveOutputTokens(int? stored, int fallback) {
    if (stored == null) {
      return fallback;
    }
    return stored.clamp(minOutputTokens, maxOutputTokens);
  }

  double get effectiveTemperature =>
      resolveTemperature(temperature, defaultTemperature);

  double get effectiveAnswerTemperature =>
      resolveTemperature(answerTemperature, defaultAnswerTemperature);

  double get effectiveVerifierTemperature =>
      resolveTemperature(verifierTemperature, defaultVerifierTemperature);

  int get effectiveMaxReasoningTokens =>
      resolveOutputTokens(maxReasoningTokens, defaultMaxReasoningTokens);

  int get effectiveAnswerReserveTokens =>
      resolveOutputTokens(answerReserveTokens, defaultAnswerReserveTokens);

  /// The verifier's model name, falling back to the solver's model when unset
  /// or blank - the verifier shipped as "same model, independent call".
  String get effectiveVerifierModel {
    final raw = verifierModel?.trim();
    return (raw == null || raw.isEmpty) ? effectiveModel : raw;
  }

  /// The shipped round budget, used when the user has never chosen one (a NULL
  /// `local_settings.ai_max_rounds`, which is every row on an upgraded file).
  ///
  /// Raised from 8 to 30 (2026-10-27, user m20816): the assistant now takes over
  /// question intake — transcribe a photo of several questions, look up tags,
  /// then write each question — which routinely needs more than a dozen
  /// round-trips for one message. The setting stays user-editable.
  static const int defaultMaxRounds = 200;

  /// The range the setting offers, and the range any stored value is resolved
  /// into. Bounded on purpose: a hand-edited or future-written
  /// `ai_max_rounds` must not be able to make one message spend an unbounded
  /// number of paid calls, and zero rounds would answer nothing at all.
  static const int minMaxRounds = 1;
  static const int maxMaxRounds = 200;

  /// [stored] as a usable budget: the default when nothing was chosen, clamped
  /// into [minMaxRounds]..[maxMaxRounds] otherwise. Applied on the way in *and*
  /// on the way out, so the number the loop runs with is always in range even
  /// if the file holds something else.
  static int resolveMaxRounds(int? stored) {
    if (stored == null) {
      return defaultMaxRounds;
    }
    return stored.clamp(minMaxRounds, maxMaxRounds);
  }

  /// True when the user has actually completed the setup, i.e. the AI surface
  /// should exist at all.
  bool get isUsable => enabled && (apiKey?.trim().isNotEmpty ?? false);

  String get effectiveBaseUrl {
    final raw = baseUrl?.trim();
    if (raw == null || raw.isEmpty) {
      return defaultBaseUrl;
    }
    // Tolerate a trailing slash: users paste both forms, and building
    // '/chat/completions' onto a doubled slash is a 404.
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  String get effectiveModel {
    final raw = model?.trim();
    return (raw == null || raw.isEmpty) ? defaultModel : raw;
  }

  /// A copy with only the chat turn's thinking effort replaced.
  ///
  /// Unlike [copyWith], passing `null` here **clears** the effort: `copyWith`
  /// cannot express "no effort chosen" (null means "keep the current value"), and
  /// the chat page's effort control has a real "默认 / Default" option that must
  /// write NULL back. Every other field is carried over unchanged.
  AiConfig withReasoningEffort(ReasoningEffort? effort) => AiConfig(
        enabled: enabled,
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
        permissionMode: permissionMode,
        maxRounds: maxRounds,
        reasoningEffort: effort,
        temperature: temperature,
        answerTemperature: answerTemperature,
        verifierTemperature: verifierTemperature,
        maxReasoningTokens: maxReasoningTokens,
        answerReserveTokens: answerReserveTokens,
        verifierModel: verifierModel,
        verifierEffort: verifierEffort,
      );

  AiConfig copyWith({
    bool? enabled,
    String? apiKey,
    String? baseUrl,
    String? model,
    AiPermissionMode? permissionMode,
    int? maxRounds,
    ReasoningEffort? reasoningEffort,
    double? temperature,
    double? answerTemperature,
    double? verifierTemperature,
    int? maxReasoningTokens,
    int? answerReserveTokens,
    String? verifierModel,
    ReasoningEffort? verifierEffort,
  }) =>
      AiConfig(
        enabled: enabled ?? this.enabled,
        apiKey: apiKey ?? this.apiKey,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        permissionMode: permissionMode ?? this.permissionMode,
        maxRounds: maxRounds ?? this.maxRounds,
        reasoningEffort: reasoningEffort ?? this.reasoningEffort,
        temperature: temperature ?? this.temperature,
        answerTemperature: answerTemperature ?? this.answerTemperature,
        verifierTemperature: verifierTemperature ?? this.verifierTemperature,
        maxReasoningTokens: maxReasoningTokens ?? this.maxReasoningTokens,
        answerReserveTokens: answerReserveTokens ?? this.answerReserveTokens,
        verifierModel: verifierModel ?? this.verifierModel,
        verifierEffort: verifierEffort ?? this.verifierEffort,
      );
}

/// One executed (or proposed) tool call, as the UI needs it.
class AiActionRecord {
  const AiActionRecord({
    required this.id,
    required this.conversationId,
    required this.toolName,
    required this.risk,
    required this.status,
    required this.createdAt,
    this.messageId,
    this.toolCallId,
    this.argsJson,
    this.beforeJson,
    this.afterJson,
    this.resultJson,
  });

  final String id;
  final String conversationId;
  final String? messageId;
  final String? toolCallId;
  final String toolName;
  final String risk;
  final String status;
  final String? argsJson;
  final String? beforeJson;
  final String? afterJson;
  final String? resultJson;
  final int createdAt;
}

/// Conversation, message and tool-action storage for the AI surface.
///
/// Kept separate from [SettingsRepository] because it is ordinary user data
/// (conversations are exported inside `.tfpkg` like everything else), while the
/// API key is a single-row setting.
class AiRepository {
  AiRepository(this._db);

  final AppDatabase _db;

  static const String roleUser = 'user';
  static const String roleAssistant = 'assistant';
  static const String roleTool = 'tool';
  static const String roleSystem = 'system';

  static const String statusPending = 'pending';
  static const String statusApproved = 'approved';
  static const String statusRejected = 'rejected';
  static const String statusExecuted = 'executed';
  static const String statusFailed = 'failed';

  /// `attachments.owner_type` for an image attached to an AI message.
  ///
  /// The `attachments` table is shared with rich-text and theme images, so the
  /// owner type is what keeps an AI photo from being picked up by another
  /// feature's file cleanup.
  static const String attachmentOwnerType = 'ai_message';

  // --- configuration -------------------------------------------------------

  /// Reads the AI configuration. Never creates a settings row: a missing row
  /// simply means "AI is off", which is the correct default for a database
  /// that predates this feature.
  Future<AiConfig> getConfig() async {
    final rows = await _db.select(_db.localSettings).get();
    if (rows.isEmpty) {
      return const AiConfig(enabled: false);
    }
    final row = rows.first;
    return AiConfig(
      enabled: row.aiEnabled,
      apiKey: row.aiApiKey,
      baseUrl: row.aiBaseUrl,
      model: row.aiModel,
      permissionMode: AiPermissionMode.fromId(row.aiPermissionMode),
      // NULL means "never chosen" - see [AiConfig.resolveMaxRounds] - so an
      // upgraded install keeps the behaviour it had before the setting existed.
      maxRounds: AiConfig.resolveMaxRounds(row.aiMaxRounds),
      // v46 model-parameter layer: read raw and leave NULL alone. Range
      // clamping happens in the `effective*` getters, so the file keeps the
      // distinction between "never chose" and "chose the default value".
      reasoningEffort: ReasoningEffort.fromId(row.aiReasoningEffort),
      temperature: row.aiTemperature,
      answerTemperature: row.aiAnswerTemperature,
      verifierTemperature: row.aiVerifierTemperature,
      maxReasoningTokens: row.aiMaxReasoningTokens,
      answerReserveTokens: row.aiAnswerReserveTokens,
      verifierModel: row.aiVerifierModel,
      verifierEffort: ReasoningEffort.fromId(row.aiVerifierEffort),
    );
  }

  /// Writes the AI configuration.
  ///
  /// Only the AI columns are touched. The settings row is shared with language,
  /// theme and profile, so writing it from the AI screen must not reset any of
  /// those - a save here is not a save of the whole settings row.
  ///
  /// The v46 model parameters are written **raw but clamped**: NULL stays NULL
  /// (never chosen), a chosen number is stored inside its documented range so
  /// a hand-edited value cannot reach the wire later.
  ///
  /// [fallbackLanguage] is used only when the row has to be created from
  /// scratch (a database that predates the settings row entirely).
  Future<void> saveConfig(AiConfig config,
      {required String fallbackLanguage}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await _db.select(_db.localSettings).get();
    if (existing.isEmpty) {
      await _db.into(_db.localSettings).insert(
            LocalSettingsCompanion.insert(
              id: const Value(1),
              language: Value(fallbackLanguage),
              themeMode: const Value('system'),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    await (_db.update(_db.localSettings)..where((t) => t.id.equals(1))).write(
      LocalSettingsCompanion(
        aiEnabled: Value(config.enabled),
        aiApiKey: Value(config.apiKey),
        aiBaseUrl: Value(config.baseUrl),
        aiModel: Value(config.model),
        aiPermissionMode: Value(config.permissionMode.id),
        // Resolved rather than stored verbatim, so the file can never hold a
        // budget outside the range the UI offers.
        aiMaxRounds: Value(AiConfig.resolveMaxRounds(config.maxRounds)),
        aiReasoningEffort: Value(config.reasoningEffort?.wireValue),
        aiTemperature: Value(config.temperature == null
            ? null
            : AiConfig.resolveTemperature(
                config.temperature, AiConfig.defaultTemperature)),
        aiAnswerTemperature: Value(config.answerTemperature == null
            ? null
            : AiConfig.resolveTemperature(
                config.answerTemperature, AiConfig.defaultAnswerTemperature)),
        aiVerifierTemperature: Value(config.verifierTemperature == null
            ? null
            : AiConfig.resolveTemperature(config.verifierTemperature,
                AiConfig.defaultVerifierTemperature)),
        aiMaxReasoningTokens: Value(config.maxReasoningTokens == null
            ? null
            : AiConfig.resolveOutputTokens(config.maxReasoningTokens,
                AiConfig.defaultMaxReasoningTokens)),
        aiAnswerReserveTokens: Value(config.answerReserveTokens == null
            ? null
            : AiConfig.resolveOutputTokens(config.answerReserveTokens,
                AiConfig.defaultAnswerReserveTokens)),
        aiVerifierModel: Value(config.verifierModel),
        aiVerifierEffort: Value(config.verifierEffort?.wireValue),
        updatedAt: Value(now),
      ),
    );
  }

  /// The language stored in the settings row, if there is one.
  ///
  /// Read separately from [getConfig] because the AI screen has no business
  /// editing it; it only needs to avoid clobbering it.
  Future<String?> currentLanguage() async {
    final rows = await _db.select(_db.localSettings).get();
    return rows.isEmpty ? null : rows.first.language;
  }

  // --- conversations -------------------------------------------------------

  Future<List<AiConversation>> listConversations({int limit = 100}) {
    final query = _db.select(_db.aiConversations)
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
      ..limit(limit);
    return query.get();
  }

  Future<AiConversation?> getConversation(String id) async {
    final rows = await (_db.select(_db.aiConversations)
          ..where((t) => t.id.equals(id)))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// Creates a conversation with the preset selected while it is still blank.
  ///
  /// A preset is a composition (tools + prompt + persona), not a stored
  /// definition: the row keeps only its stable id, and every read resolves the
  /// id against the current definition. [subagentPreset] is the preset a
  /// subagent session started from this conversation is created with; null
  /// means "inherit the parent".
  Future<AiConversation> createConversation({
    String? title,
    AgentPreset agentPreset = AgentPreset.assistant,
    SubagentPreset? subagentPreset,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = Ids.next('conv');
    await _db.into(_db.aiConversations).insert(
          AiConversationsCompanion.insert(
            id: id,
            title: (title == null || title.trim().isEmpty)
                ? _defaultTitle(now)
                : title.trim(),
            createdAt: now,
            updatedAt: now,
            agentPresetId: Value(agentPreset.id),
            subagentPresetId: Value(subagentPreset?.id),
          ),
        );
    return (await getConversation(id))!;
  }

  /// The preset state of [conversationId], or null when it does not exist.
  ///
  /// [ConversationPresetState.locked] is derived from the message list rather
  /// than stored: a session is blank until it has its first message, and every
  /// run writes one. There is deliberately no persisted preset version/hash -
  /// the same session resolves the current definition of its id, as in DSH.
  Future<ConversationPresetState?> presetStateFor(String conversationId) async {
    final row = await getConversation(conversationId);
    if (row == null) {
      return null;
    }
    final messages = await listMessages(conversationId);
    return ConversationPresetState(
      agent: row.agentPresetChoice,
      subagent: row.subagentPresetChoice,
      locked: messages.isNotEmpty,
    );
  }

  /// Selects the preset of a conversation that has not started yet.
  ///
  /// Only a blank session may be re-composed; after the first message this
  /// throws [ConversationPresetsLockedException]. Passing null for either
  /// preset leaves that column unchanged, so a caller can change one without
  /// clearing the other.
  Future<void> setConversationPresets({
    required String conversationId,
    AgentPreset? agentPreset,
    SubagentPreset? subagentPreset,
  }) async {
    if (agentPreset == null && subagentPreset == null) {
      return;
    }
    final row = await getConversation(conversationId);
    if (row == null) {
      throw ArgumentError.value(
        conversationId,
        'conversationId',
        'unknown conversation',
      );
    }
    if ((await listMessages(conversationId)).isNotEmpty) {
      throw ConversationPresetsLockedException(conversationId);
    }
    await (_db.update(_db.aiConversations)
          ..where((t) => t.id.equals(conversationId)))
        .write(AiConversationsCompanion(
      agentPresetId:
          agentPreset == null ? const Value.absent() : Value(agentPreset.id),
      subagentPresetId: subagentPreset == null
          ? const Value.absent()
          : Value(subagentPreset.id),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  Future<void> renameConversation(String id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await (_db.update(_db.aiConversations)..where((t) => t.id.equals(id)))
        .write(AiConversationsCompanion(
      title: Value(trimmed),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  /// 用第一条用户消息给会话自动取名。
  ///
  /// 只在标题还是 [createConversation] 生成的占位符（`对话 MM-DD HH:mm`）时改名：
  /// 用户自己改过的标题、调用方显式传入的标题都算「已有」，一律复用，不覆盖
  /// （用户 2026-11-15 第 5 点）。占位符由 [createdAt] 唯一确定，所以不需要额外
  /// 标记列，也不需要改 schema。
  ///
  /// 返回是否真的改了名，供调用方/测试判断；改名失败不算错误——它只是显示层
  /// 的便利，不该让一条已经花过模型预算的消息失败。
  Future<bool> autoTitleFromFirstMessage({
    required String conversationId,
    required String text,
    int maxLength = defaultConversationTitleLength,
  }) async {
    final row = await getConversation(conversationId);
    if (row == null) {
      return false;
    }
    if (row.title != _defaultTitle(row.createdAt)) {
      // A title that is not the placeholder is either the user's or the
      // caller's; treat it as deliberate and keep it.
      return false;
    }
    final title = autoConversationTitle(text, maxLength: maxLength);
    if (title == null || title == row.title) {
      return false;
    }
    await renameConversation(conversationId, title);
    return true;
  }

  /// Deletes a conversation and everything under it.
  ///
  /// Foreign keys are ON, but the child rows are removed explicitly so the
  /// behaviour does not depend on cascade configuration.
  Future<void> deleteConversation(String id) async {
    final messageIds = [for (final row in await listMessages(id)) row.id];
    await _db.transaction(() async {
      if (messageIds.isNotEmpty) {
        await (_db.delete(_db.attachments)
              ..where((t) =>
                  t.ownerType.equals(attachmentOwnerType) &
                  t.ownerId.isIn(messageIds)))
            .go();
      }
      await (_db.delete(_db.aiActions)
            ..where((t) => t.conversationId.equals(id)))
          .go();
      await (_db.delete(_db.aiMessages)
            ..where((t) => t.conversationId.equals(id)))
          .go();
      await (_db.delete(_db.aiConversations)..where((t) => t.id.equals(id)))
          .go();
    });
  }

  // --- messages ------------------------------------------------------------

  Future<List<AiMessage>> listMessages(String conversationId) {
    final query = _db.select(_db.aiMessages)
      ..where((t) => t.conversationId.equals(conversationId))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.get();
  }

  Future<AiMessage> addMessage({
    required String conversationId,
    required String role,
    String? content,
    String? toolCallId,
    String? reasoning,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = Ids.next('msg');
    await _db.into(_db.aiMessages).insert(
          AiMessagesCompanion.insert(
            id: id,
            conversationId: conversationId,
            role: role,
            content: Value(content),
            toolCallId: Value(toolCallId),
            reasoning: Value(reasoning),
            createdAt: now,
          ),
        );
    await _touch(conversationId, now);
    return (await (_db.select(_db.aiMessages)..where((t) => t.id.equals(id)))
        .getSingle());
  }

  // --- attachments ---------------------------------------------------------

  /// Registers one image file with the message it belongs to.
  ///
  /// The bytes are deliberately **not** here: `attachments` stores a path under
  /// the app support directory. That keeps a multi-megabyte photo out of the
  /// database (and out of the row data a `.tfpkg` dump carries), and it is the
  /// existing table, so no schema change was needed for images at all.
  Future<void> addAttachment({
    required String messageId,
    required String relPath,
    String? mime,
  }) async {
    await _db.into(_db.attachments).insert(
          AttachmentsCompanion.insert(
            id: Ids.next('att'),
            ownerType: attachmentOwnerType,
            ownerId: messageId,
            relPath: relPath,
            mime: Value(mime),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  /// The images attached to one message, oldest first.
  Future<List<Attachment>> listMessageAttachments(String messageId) {
    final query = _db.select(_db.attachments)
      ..where((t) =>
          t.ownerType.equals(attachmentOwnerType) & t.ownerId.equals(messageId))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.get();
  }

  /// Every image attached to any message of a conversation.
  ///
  /// Used to clean the files up when the conversation is deleted: the rows are
  /// removed with the conversation, but the files are not, and leaving them
  /// behind would leak a photo per deleted conversation.
  Future<List<Attachment>> listConversationAttachments(
    String conversationId,
  ) async {
    final messageIds = [
      for (final row in await listMessages(conversationId)) row.id
    ];
    if (messageIds.isEmpty) {
      return const [];
    }
    final query = _db.select(_db.attachments)
      ..where((t) =>
          t.ownerType.equals(attachmentOwnerType) & t.ownerId.isIn(messageIds))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.get();
  }

  // --- tool actions --------------------------------------------------------

  Future<List<AiActionRecord>> listActions(String conversationId) async {
    final rows = await (_db.select(_db.aiActions)
          ..where((t) => t.conversationId.equals(conversationId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    return rows.map(_toRecord).toList();
  }

  /// Records a proposed call. Called for **every** proposal, including ones the
  /// user is about to reject: the ledger is the audit trail, not a log of
  /// successes.
  Future<AiActionRecord> recordAction({
    required String conversationId,
    required String toolName,
    required String risk,
    required String argsJson,
    String? messageId,
    String? toolCallId,
    String status = statusPending,
    String? beforeJson,
    String? afterJson,
    String? resultJson,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = Ids.next('act');
    await _db.into(_db.aiActions).insert(
          AiActionsCompanion.insert(
            id: id,
            conversationId: conversationId,
            messageId: Value(messageId),
            toolCallId: Value(toolCallId),
            toolName: toolName,
            argsJson: argsJson,
            risk: risk,
            status: status,
            beforeJson: Value(beforeJson),
            afterJson: Value(afterJson),
            resultJson: Value(resultJson),
            createdAt: now,
          ),
        );
    final row = await (_db.select(_db.aiActions)..where((t) => t.id.equals(id)))
        .getSingle();
    return _toRecord(row);
  }

  /// Links a recorded action to the assistant message whose turn proposed it.
  ///
  /// The link is made after the fact because the message is only written once
  /// the whole turn is complete - see [AgentLoop] for why an incomplete turn
  /// must never reach the conversation history.
  Future<void> attachMessageId({
    required String conversationId,
    required String toolCallId,
    required String messageId,
  }) async {
    await (_db.update(_db.aiActions)
          ..where((t) =>
              t.conversationId.equals(conversationId) &
              t.toolCallId.equals(toolCallId)))
        .write(AiActionsCompanion(messageId: Value(messageId)));
  }

  /// Actions whose turn has already been written into the conversation.
  ///
  /// Used to rebuild history: an action with no [AiActionRecord.messageId] has
  /// not been committed as part of a turn yet.
  Future<List<AiActionRecord>> listCommittedActions(
      String conversationId) async {
    final rows = await (_db.select(_db.aiActions)
          ..where((t) =>
              t.conversationId.equals(conversationId) & t.messageId.isNotNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    return rows.map(_toRecord).toList();
  }

  Future<void> updateActionStatus(
    String id, {
    required String status,
    String? beforeJson,
    String? afterJson,
    String? resultJson,
  }) async {
    await (_db.update(_db.aiActions)..where((t) => t.id.equals(id))).write(
      AiActionsCompanion(
        status: Value(status),
        beforeJson: Value(beforeJson),
        afterJson: Value(afterJson),
        resultJson: Value(resultJson),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Actions that were executed automatically and carry a snapshot, i.e. the
  /// ones the user can still undo.
  Future<List<AiActionRecord>> undoableActions(String conversationId) async {
    final rows = await (_db.select(_db.aiActions)
          ..where((t) =>
              t.conversationId.equals(conversationId) &
              t.status.equals(statusExecuted) &
              t.beforeJson.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return rows.map(_toRecord).toList();
  }

  // --- helpers -------------------------------------------------------------

  Future<void> _touch(String conversationId, int now) async {
    await (_db.update(_db.aiConversations)
          ..where((t) => t.id.equals(conversationId)))
        .write(AiConversationsCompanion(updatedAt: Value(now)));
  }

  String _defaultTitle(int now) {
    final at = DateTime.fromMillisecondsSinceEpoch(now);
    final mm = at.month.toString().padLeft(2, '0');
    final dd = at.day.toString().padLeft(2, '0');
    final hh = at.hour.toString().padLeft(2, '0');
    final mi = at.minute.toString().padLeft(2, '0');
    return '对话 $mm-$dd $hh:$mi';
  }

  AiActionRecord _toRecord(AiAction row) => AiActionRecord(
        id: row.id,
        conversationId: row.conversationId,
        messageId: row.messageId,
        toolCallId: row.toolCallId,
        toolName: row.toolName,
        risk: row.risk,
        status: row.status,
        argsJson: row.argsJson,
        beforeJson: row.beforeJson,
        afterJson: row.afterJson,
        resultJson: row.resultJson,
        createdAt: row.createdAt,
      );
}

/// Preset view of a stored conversation row.
///
/// The database keeps only ids (and NULL for rows written before presets
/// existed); resolving them here keeps every caller on the same fallback:
/// NULL/unknown means the shipped `assistant` / `inherit` behaviour.
extension AiConversationPresets on AiConversation {
  AgentPreset get agentPresetChoice => AgentPreset.fromId(agentPresetId);

  SubagentPreset get subagentPresetChoice =>
      SubagentPreset.fromId(subagentPresetId);

  /// Whether this preset runs the main agent loop. Student mode does not.
  bool get runsMainAgent => agentPresetChoice.runsMainAgent;
}
