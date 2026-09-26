import 'package:drift/drift.dart';

import '../database/database.dart';
import '../ids.dart';

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
  });

  /// The master switch. When false the rest is ignored and the app must make
  /// no network call at all.
  final bool enabled;

  final String? apiKey;
  final String? baseUrl;
  final String? model;
  final AiPermissionMode permissionMode;

  /// DeepSeek's OpenAI-compatible endpoint. Kept here rather than in the
  /// adapter so the default is visible next to the setting it belongs to.
  static const String defaultBaseUrl = 'https://api.deepseek.com';
  static const String defaultModel = 'deepseek-chat';

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

  AiConfig copyWith({
    bool? enabled,
    String? apiKey,
    String? baseUrl,
    String? model,
    AiPermissionMode? permissionMode,
  }) =>
      AiConfig(
        enabled: enabled ?? this.enabled,
        apiKey: apiKey ?? this.apiKey,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        permissionMode: permissionMode ?? this.permissionMode,
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
    );
  }

  /// Writes the AI configuration.
  ///
  /// Only the AI columns are touched. The settings row is shared with language,
  /// theme and profile, so writing it from the AI screen must not reset any of
  /// those - a save here is not a save of the whole settings row.
  ///
  /// [fallbackLanguage] is used only when the row has to be created from
  /// scratch (a database that predates the settings row entirely).
  Future<void> saveConfig(AiConfig config, {required String fallbackLanguage}) async {
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

  /// Creates a conversation, or returns the most recent one when the caller
  /// has no preference - which is what the UI does on first open.
  Future<AiConversation> createConversation({String? title}) async {
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
          ),
        );
    return (await getConversation(id))!;
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

  /// Deletes a conversation and everything under it.
  ///
  /// Foreign keys are ON, but the child rows are removed explicitly so the
  /// behaviour does not depend on cascade configuration.
  Future<void> deleteConversation(String id) async {
    await _db.transaction(() async {
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
            createdAt: now,
          ),
        );
    await _touch(conversationId, now);
    return (await (_db.select(_db.aiMessages)..where((t) => t.id.equals(id)))
        .getSingle());
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
  Future<List<AiActionRecord>> listCommittedActions(String conversationId) async {
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
