/// The agent preset a top-level conversation runs, and the preset a subagent
/// session is started with.
///
/// This mirrors the DSH semantics Furnace needs (docs/AI_PRESETS.md):
///
///  * a preset is selected only while the session is **blank** - it has no
///    messages and no run yet;
///  * the id is recorded on the session at creation/selection time and is
///    immutable from the first run on;
///  * there is no persisted definition snapshot, version or hash: restoring a
///    session after a restart uses the current definition with the same id;
///  * a preset is a composition (tools + prompt + persona), not a database row.
///
/// The student solver preset is the only non-chat preset today: selecting it
/// means the session answers through [StudentSolver] directly and never starts
/// the main agent loop.
library;

/// The preset a top-level conversation runs.
///
/// The stored [id] is the stable value written to the database; never
/// localise it.
enum AgentPreset {
  /// The normal conversational agent (agent loop + the built-in tool registry).
  assistant('assistant', '主对话'),

  /// Direct student mode: the isolated solver answers, the main loop is not
  /// part of this session at all.
  studentSolver('student_solver', '学生模式');

  const AgentPreset(this.id, this.label);

  final String id;
  final String label;

  /// Whether this preset runs the main [AgentLoop].
  bool get runsMainAgent => this == AgentPreset.assistant;

  /// Resolves a stored id, defaulting to [assistant].
  ///
  /// NULL (rows written before presets existed) and unknown ids both read as the
  /// shipped default, for the same reason every other nullable preference in
  /// this app does: an upgraded database must keep behaving as it did.
  static AgentPreset fromId(String? id) => switch (id) {
        'student_solver' => AgentPreset.studentSolver,
        _ => AgentPreset.assistant,
      };

  static AgentPreset? fromLabel(String? label) {
    for (final preset in AgentPreset.values) {
      if (preset.label == label) {
        return preset;
      }
    }
    return null;
  }
}

/// The preset a subagent session is started with.
///
/// Nullable in storage: absent means "inherit the parent session's preset",
/// which is why [inherit] is the resolution for a NULL column rather than a
/// value that has to be written.
enum SubagentPreset {
  /// Use the parent session's composition (the DSH default for a subagent).
  inherit('inherit', '继承上级'),

  /// Start the subagent directly on the student solver.
  studentSolver('student_solver', '学生模式');

  const SubagentPreset(this.id, this.label);

  final String id;
  final String label;

  static SubagentPreset fromId(String? id) => switch (id) {
        'student_solver' => SubagentPreset.studentSolver,
        _ => SubagentPreset.inherit,
      };
}

/// The preset state of one conversation.
///
/// [locked] is **derived**, not stored: a session locks the moment it stops
/// being blank (its first message or first run). There is deliberately no
/// `locked_at`, `preset_version` or `preset_hash` column - the same session id
/// always resolves against the current preset definition, exactly like DSH.
class ConversationPresetState {
  const ConversationPresetState({
    required this.agent,
    required this.subagent,
    required this.locked,
  });

  final AgentPreset agent;
  final SubagentPreset subagent;
  final bool locked;

  bool get isStudentMode => agent == AgentPreset.studentSolver;

  ConversationPresetState copyWith({
    AgentPreset? agent,
    SubagentPreset? subagent,
    bool? locked,
  }) {
    return ConversationPresetState(
      agent: agent ?? this.agent,
      subagent: subagent ?? this.subagent,
      locked: locked ?? this.locked,
    );
  }

  @override
  String toString() => 'ConversationPresetState(agent: ${agent.id}, '
      'subagent: ${subagent.id}, locked: $locked)';
}
