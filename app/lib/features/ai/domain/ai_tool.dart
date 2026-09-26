/// The AI tool layer.
///
/// Design rules from docs/AI_DESIGN.md that this file enforces:
///
///  * **Thin wrappers** (D2): a tool calls an existing repository method. No
///    tool writes SQL. That is what makes the main UI refresh by itself - the
///    repositories are Riverpod providers, so the AI and the screens share one
///    instance and one change stream.
///  * **Two risk levels only** (D12 v2): `write` and `destructive`. There is no
///    "read-only tool", because reading is simply not a risk.
///  * **Reversibility decides automation** (D13b): a tool that cannot produce a
///    reliable before-snapshot is never executed automatically, whatever the
///    permission mode says. This turns "you can always undo it" from a promise
///    into a property the engine can check.
library;

/// How dangerous a tool call is.
enum ToolRisk {
  /// Creates, updates, completes, exports. Reversible when [AiTool.reversible].
  write('write'),

  /// Deletes something. **Never** automatic, in any permission mode.
  destructive('destructive');

  const ToolRisk(this.id);

  /// Stable value persisted in `ai_actions.risk`.
  final String id;

  static ToolRisk fromId(String id) =>
      id == 'destructive' ? ToolRisk.destructive : ToolRisk.write;
}

/// What the model asked for, already decoded, plus the engine's decision.
class ToolInvocation {
  const ToolInvocation({
    required this.toolName,
    required this.action,
    required this.arguments,
    this.callId,
  });

  final String toolName;

  /// The `action` argument, or the tool name when it has no actions.
  final String action;

  final Map<String, Object?> arguments;
  final String? callId;
}

/// The outcome of one tool call.
///
/// [modelResult] is what the model sees; [summary] is what the user reads. They
/// differ on purpose: the model benefits from ids and raw rows, while the user
/// wants a sentence.
class ToolResult {
  const ToolResult({
    required this.ok,
    required this.summary,
    this.modelResult,
    this.beforeJson,
    this.afterJson,
    this.error,
  });

  const ToolResult.failure(String error, {String? summary})
      : ok = false,
        summary = summary ?? error,
        error = error,
        modelResult = null,
        beforeJson = null,
        afterJson = null;

  final bool ok;

  /// One line the conversation shows, e.g. `已创建任务「写作业」`.
  final String summary;

  /// JSON-able payload returned to the model.
  final Object? modelResult;

  /// Row(s) before the change, for undo.
  final String? beforeJson;

  /// Row(s) after the change.
  final String? afterJson;

  final String? error;

  /// Whether undo is possible for this particular execution. A create is undone
  /// by deleting; an update needs [beforeJson]; a delete needs both.
  bool get isUndoable => ok && (beforeJson != null || afterJson != null);

  Map<String, Object?> toModelJson() => {
        'ok': ok,
        if (error != null) 'error': error,
        'summary': summary,
        if (modelResult != null) 'result': modelResult,
      };
}

/// Arguments passed in by the model, with typed, validated access.
///
/// Validation lives here rather than in the provider schema so that a bad call
/// produces a *readable tool result the model can act on* instead of an
/// exception. The provider's `strict` mode was deliberately not used (D4):
/// its "every property must be required" rule forces artificial unions, and a
/// local check is easier to test and to explain in an error message.
class ToolArgs {
  ToolArgs(this.raw);

  final Map<String, Object?> raw;

  String? optString(String key) {
    final value = raw[key];
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  String requireString(String key) {
    final value = optString(key);
    if (value == null) {
      throw ToolArgError('缺少必填参数 `$key`');
    }
    return value;
  }

  int? optInt(String key) {
    final value = raw[key];
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString().trim());
  }

  int requireInt(String key) {
    final value = optInt(key);
    if (value == null) {
      throw ToolArgError('缺少必填参数 `$key`（或不是整数）');
    }
    return value;
  }

  double? optDouble(String key) {
    final value = raw[key];
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString().trim());
  }

  bool? optBool(String key) {
    final value = raw[key];
    if (value == null) {
      return null;
    }
    if (value is bool) {
      return value;
    }
    final text = value.toString().trim().toLowerCase();
    if (text == 'true' || text == '1') {
      return true;
    }
    if (text == 'false' || text == '0') {
      return false;
    }
    return null;
  }

  List<String>? optStringList(String key) {
    final value = raw[key];
    if (value == null) {
      return null;
    }
    if (value is List) {
      final items = value
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
      return items.isEmpty ? null : items;
    }
    final single = optString(key);
    return single == null ? null : [single];
  }

  /// Milliseconds from either an epoch integer or an ISO-8601 string.
  ///
  /// Both forms are accepted because a model asked for "下周三" naturally emits
  /// ISO text while a model echoing a query result emits epoch millis.
  int? optEpochMs(String key) {
    final value = raw[key];
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    final text = value.toString().trim();
    if (text.isEmpty) {
      return null;
    }
    final direct = int.tryParse(text);
    if (direct != null) {
      return direct;
    }
    return DateTime.tryParse(text)?.millisecondsSinceEpoch;
  }

  /// Reads the `action` argument, rejecting a missing or unknown value with the
  /// list of what is allowed - which is the single most useful thing to tell a
  /// model that guessed wrong.
  String requireAction(Set<String> allowed) {
    final action = optString('action');
    if (action == null) {
      throw ToolArgError('缺少 `action`。可用：${allowed.join(' / ')}');
    }
    if (!allowed.contains(action)) {
      throw ToolArgError('未知的 `action: $action`。可用：${allowed.join(' / ')}');
    }
    return action;
  }
}

/// A validation failure caused by the model, not by the app.
class ToolArgError implements Exception {
  ToolArgError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One tool the agent loop may offer to the model.
abstract class AiTool {
  const AiTool();

  /// Stable identifier sent to the provider. Never localised.
  String get name;

  /// What the model reads when deciding whether to call this. Written for the
  /// model: it says *when* to use the tool, not just what it does.
  String get description;

  /// JSON Schema for the arguments (an object schema).
  Map<String, Object?> get parameters;

  /// Risk of this call, given the requested action. Split per action because
  /// `manage_task(delete)` is destructive while `manage_task(create)` is not.
  ToolRisk riskFor(String action);

  /// Whether this call can produce a reliable before-snapshot. A `false` here
  /// forces one-by-one confirmation regardless of permission mode (D13b).
  bool reversibleFor(String action);

  /// Which platforms may offer this tool.
  bool get availableOnCurrentPlatform;

  /// Runs the call. Implementations should throw [ToolArgError] for bad model
  /// input and let real failures propagate as exceptions the engine records.
  Future<ToolResult> run(ToolInvocation invocation);

  /// Reads the action without validating it, for risk lookup before execution.
  String actionOf(Map<String, Object?> arguments) {
    final raw = arguments['action'];
    if (raw == null) {
      return name;
    }
    return raw.toString().trim();
  }
}
