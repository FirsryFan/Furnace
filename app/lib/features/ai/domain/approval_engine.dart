import '../../../data/repositories/ai_repository.dart';
import 'ai_tool.dart';

/// What the engine decided to do with one proposed call.
enum ToolDisposition {
  /// Run it now, record it, and let the user undo it.
  executeNow,

  /// Collect it into the turn's approval list: one confirmation for the batch.
  batchApproval,

  /// Ask about this call on its own, regardless of the mode.
  individualApproval,
}

/// The verdict for one proposed tool call.
class ApprovalDecision {
  const ApprovalDecision({
    required this.toolName,
    required this.risk,
    required this.reversible,
    required this.disposition,
    required this.reason,
  });

  final String toolName;
  final ToolRisk risk;
  final bool reversible;
  final ToolDisposition disposition;

  /// Why this disposition was chosen, in words the UI can show. Explaining the
  /// decision is what makes "why did it just do that?" answerable.
  final String reason;

  bool get runsWithoutAsking => disposition == ToolDisposition.executeNow;
}

/// Decides what needs confirmation, and why.
///
/// This is where the user's rule lives: **everything except deletion may run
/// automatically, and deletion always asks one by one** (docs/AI_DESIGN.md
/// §6.1 D12 v2). It is deliberately a pure function of (risk, reversibility,
/// mode) with no I/O, because the promise "you can always undo it" has to hold
/// for every path - including ones nobody thought about when the rule was
/// written.
///
/// Two invariants, each with a test:
///
///  * A `destructive` call is **never** `executeNow`, in any mode.
///  * A call whose snapshot cannot be taken reliably (`reversible == false`) is
///    also never `executeNow`, because auto-execution is only offered on the
///    strength of undo (D13b).
class ApprovalEngine {
  const ApprovalEngine({required this.mode});

  final AiPermissionMode mode;

  ApprovalDecision adjudicate({
    required String toolName,
    required ToolRisk risk,
    required bool reversible,
  }) {
    // Deletion first: it outranks the mode and the reversibility claim. A
    // "reversible" delete is still a delete, and the user asked to be asked.
    if (risk == ToolRisk.destructive) {
      return ApprovalDecision(
        toolName: toolName,
        risk: risk,
        reversible: reversible,
        disposition: ToolDisposition.individualApproval,
        reason: '删除类操作永远逐条确认',
      );
    }

    // Anything that cannot be undone must be agreed to explicitly. This is the
    // rule that keeps "auto" honest for tools with outside effects (skill
    // scripts, for instance).
    if (!reversible) {
      return ApprovalDecision(
        toolName: toolName,
        risk: risk,
        reversible: reversible,
        disposition: ToolDisposition.individualApproval,
        reason: '该操作无法撤销，需要单独确认',
      );
    }

    return switch (mode) {
      AiPermissionMode.plan => ApprovalDecision(
          toolName: toolName,
          risk: risk,
          reversible: reversible,
          disposition: ToolDisposition.batchApproval,
          reason: '按计划模式：本轮操作汇总后一次确认',
        ),
      AiPermissionMode.auto => ApprovalDecision(
          toolName: toolName,
          risk: risk,
          reversible: reversible,
          disposition: ToolDisposition.executeNow,
          reason: '自动模式：可撤销的操作直接执行，可在对话里撤回',
        ),
    };
  }

  /// Convenience: adjudicate straight from a tool and its arguments.
  ApprovalDecision forInvocation(AiTool tool, Map<String, Object?> arguments) {
    final action = tool.actionOf(arguments);
    return adjudicate(
      toolName: tool.name,
      risk: tool.riskFor(action),
      reversible: tool.reversibleFor(action),
    );
  }
}
