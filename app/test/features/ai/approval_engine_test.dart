import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';

/// The user's rule is "everything except deletion may run automatically". These
/// tests exist to prove the rule holds for the two cases where it is easy to get
/// wrong: deletion, and operations that cannot be undone.
void main() {
  const plan = ApprovalEngine(mode: AiPermissionMode.plan);
  const auto = ApprovalEngine(mode: AiPermissionMode.auto);

  ApprovalDecision decide(
    ApprovalEngine engine, {
    ToolRisk risk = ToolRisk.write,
    bool reversible = true,
    String name = 'manage_task',
  }) =>
      engine.adjudicate(toolName: name, risk: risk, reversible: reversible);

  group('write + reversible', () {
    test('plan mode batches it into one confirmation', () {
      final decision = decide(plan);
      expect(decision.disposition, ToolDisposition.batchApproval);
      expect(decision.runsWithoutAsking, isFalse);
    });

    test('auto mode runs it without asking', () {
      final decision = decide(auto);
      expect(decision.disposition, ToolDisposition.executeNow);
      expect(decision.runsWithoutAsking, isTrue);
      // The reason is shown to the user, so it must name the safety net.
      expect(decision.reason, contains('撤回'));
    });
  });

  group('destructive', () {
    test('plan mode asks about each one, not as a batch', () {
      // Bundling deletions into one "approve all" would collapse the user's
      // explicit "deletion always asks" into a single click.
      final decision = decide(plan, risk: ToolRisk.destructive);
      expect(decision.disposition, ToolDisposition.individualApproval);
      expect(decision.reason, contains('删除'));
    });

    test('auto mode still asks about each one', () {
      final decision = decide(auto, risk: ToolRisk.destructive);
      expect(decision.disposition, ToolDisposition.individualApproval);
      expect(decision.runsWithoutAsking, isFalse);
    });

    test('even a reversible delete is never automatic', () {
      // The whole point of the rule: the user said deletion is where they want
      // to be asked, so being able to undo it does not buy silence.
      expect(decide(auto, risk: ToolRisk.destructive, reversible: true).runsWithoutAsking,
          isFalse);
    });
  });

  group('not reversible', () {
    test('auto mode refuses to run it silently', () {
      // A skill script can leave effects outside the database; "undo" is not a
      // real option there, so the safety net that justifies auto mode is gone.
      final decision = decide(auto, reversible: false, name: 'run_skill');
      expect(decision.disposition, ToolDisposition.individualApproval);
      expect(decision.reason, contains('无法撤销'));
    });

    test('plan mode also asks individually rather than batching', () {
      final decision = decide(plan, reversible: false, name: 'run_skill');
      expect(decision.disposition, ToolDisposition.individualApproval);
    });
  });

  group('no mode agrees to everything', () {
    test('there is no mode where a destructive call executes silently', () {
      // Exhaustive over the enum on purpose: if a third mode is ever added,
      // this test forces whoever adds it to think about deletion.
      for (final mode in AiPermissionMode.values) {
        final engine = ApprovalEngine(mode: mode);
        expect(
          engine
              .adjudicate(
                toolName: 'manage_task',
                risk: ToolRisk.destructive,
                reversible: true,
              )
              .disposition,
          ToolDisposition.individualApproval,
          reason: 'mode ${mode.id} must still ask about deletion',
        );
      }
    });

    test('auto is only more permissive for reversible writes', () {
      for (final mode in AiPermissionMode.values) {
        for (final reversible in [true, false]) {
          for (final risk in ToolRisk.values) {
            final decision = ApprovalEngine(mode: mode).adjudicate(
              toolName: 'x',
              risk: risk,
              reversible: reversible,
            );
            if (decision.runsWithoutAsking) {
              expect(mode, AiPermissionMode.auto);
              expect(risk, ToolRisk.write);
              expect(reversible, isTrue);
            }
          }
        }
      }
    });
  });

  group('forInvocation', () {
    test('it reads the risk of the requested action, not of the tool', () {
      // `manage_task` is a safe tool that can also delete. Judging the tool
      // rather than the call would let `delete` ride in on `create`'s risk.
      final tool = _FakeTool();
      expect(
        auto.forInvocation(tool, {'action': 'create'}).disposition,
        ToolDisposition.executeNow,
      );
      expect(
        auto.forInvocation(tool, {'action': 'delete'}).disposition,
        ToolDisposition.individualApproval,
      );
    });

    test('a tool without an action is judged by the tool itself', () {
      final tool = _FakeTool();
      expect(auto.forInvocation(tool, const {}).disposition,
          ToolDisposition.executeNow);
    });
  });
}

/// Minimal tool whose risk depends on the action, which is the real-world shape.
class _FakeTool extends AiTool {
  @override
  String get name => 'manage_task';

  @override
  String get description => 'test';

  @override
  Map<String, Object?> get parameters => const {'type': 'object'};

  @override
  ToolRisk riskFor(String action) =>
      action == 'delete' ? ToolRisk.destructive : ToolRisk.write;

  @override
  bool reversibleFor(String action) => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async =>
      const ToolResult(ok: true, summary: 'noop');
}
