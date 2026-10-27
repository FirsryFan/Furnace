import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';
import 'package:furnace/features/ai/presentation/widgets/run_timeline.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// The chat page's live step timeline, in isolation.
///
/// These assertions are about what the *loop's state* turns into on screen:
/// which rows exist, which phase a model round advertises, the status of a
/// waiting/failed/cancelled call, the ticking elapsed readout, and the auto
/// fold once the turn ends. The loop side of the contract (when a step is
/// appended, updated or closed) is covered by agent_loop_steps_test.dart; this
/// file never drives the loop, so a failure here points at drawing.
void main() {
  final base = DateTime.utc(2026, 10, 27, 12);

  AgentStep modelStep({
    int id = 1,
    int round = 1,
    AgentStepStatus status = AgentStepStatus.running,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) =>
      AgentStep(
        id: id,
        kind: AgentStepKind.model,
        round: round,
        startedAt: startedAt ?? base,
        status: status,
        finishedAt: finishedAt,
      );

  AgentStep toolStep({
    int id = 2,
    int round = 1,
    String toolName = 'read_question',
    String detail = '第 3 题',
    String? summary,
    AgentStepStatus status = AgentStepStatus.running,
    bool? ok,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) =>
      AgentStep(
        id: id,
        kind: AgentStepKind.tool,
        round: round,
        toolName: toolName,
        detail: detail,
        summary: summary,
        ok: ok,
        status: status,
        startedAt: startedAt ?? base,
        finishedAt: finishedAt,
      );

  Future<void> pumpTimeline(
    WidgetTester tester,
    AgentTurnState state, {
    DateTime Function()? now,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => RunTimeline(
              state: state,
              l10n: AppLocalizations.of(context),
              now: now,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Takes the widget down so a running ticker cannot outlive its test.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('没有步骤时整块不显示', (tester) async {
    await pumpTimeline(tester, const AgentTurnState());
    expect(find.byKey(runTimelineKey), findsNothing);
  });

  testWidgets('运行中的模型轮显示轮次、思考阶段与秒表', (tester) async {
    final now = base.add(const Duration(seconds: 3));
    await pumpTimeline(
      tester,
      AgentTurnState(
        generating: true,
        reasoningText: '先想一下',
        steps: [modelStep(startedAt: base)],
      ),
      now: () => now,
    );
    expect(find.byKey(runTimelineKey), findsOneWidget);
    expect(find.textContaining('第 1 轮'), findsOneWidget);
    expect(find.textContaining('思考中'), findsOneWidget);
    expect(find.text('用时 3 秒'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('回答正文开始出现后阶段变成生成回答中', (tester) async {
    await pumpTimeline(
      tester,
      AgentTurnState(
        generating: true,
        streamingText: '答案是 4',
        steps: [modelStep()],
      ),
    );
    expect(find.textContaining('生成回答中'), findsOneWidget);
    expect(find.textContaining('思考中'), findsNothing);
    await unmount(tester);
  });

  testWidgets('工具调用行显示工具名与参数摘要', (tester) async {
    await pumpTimeline(
      tester,
      AgentTurnState(generating: true, steps: [toolStep()]),
      now: () => base,
    );
    expect(find.text('调用工具：read_question'), findsOneWidget);
    expect(find.text('第 3 题'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('运行中的耗时每秒刷新', (tester) async {
    var current = base;
    await pumpTimeline(
      tester,
      AgentTurnState(generating: true, steps: [modelStep(startedAt: base)]),
      now: () => current,
    );
    expect(find.text('用时 0 秒'), findsOneWidget);
    current = base.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('用时 2 秒'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('等待审批的工具行显示等待与沙漏', (tester) async {
    await pumpTimeline(
      tester,
      AgentTurnState(
        generating: true,
        steps: [toolStep(status: AgentStepStatus.waiting)],
      ),
    );
    expect(find.text('等待你确认'), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('失败与取消各有图标、状态字与结果摘要', (tester) async {
    final steps = [
      toolStep(
        id: 2,
        detail: 'delete_content',
        status: AgentStepStatus.failed,
        ok: false,
        summary: '这道题不存在',
        finishedAt: base.add(const Duration(seconds: 1)),
      ),
      toolStep(
        id: 3,
        detail: 'manage_task',
        status: AgentStepStatus.cancelled,
        finishedAt: base.add(const Duration(seconds: 2)),
      ),
    ];
    await pumpTimeline(
      tester,
      AgentTurnState(generating: true, steps: steps),
    );
    expect(find.byIcon(Icons.error), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget);
    expect(find.text('失败'), findsOneWidget);
    expect(find.text('已取消'), findsOneWidget);
    expect(find.text('这道题不存在'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('已结束步骤显示实测耗时', (tester) async {
    await pumpTimeline(
      tester,
      AgentTurnState(
        generating: true,
        steps: [
          modelStep(
            status: AgentStepStatus.done,
            finishedAt: base.add(const Duration(seconds: 2)),
          ),
        ],
      ),
    );
    expect(find.text('用时 2 秒'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('本轮结束后自动折叠成一行摘要，点开可看全部步骤', (tester) async {
    final steps = [
      modelStep(
        id: 1,
        status: AgentStepStatus.done,
        finishedAt: base.add(const Duration(seconds: 1)),
      ),
      toolStep(
        id: 2,
        status: AgentStepStatus.done,
        ok: true,
        finishedAt: base.add(const Duration(seconds: 2)),
      ),
    ];
    await pumpTimeline(
      tester,
      AgentTurnState(generating: true, steps: steps),
    );
    expect(find.text('运行步骤'), findsOneWidget);
    expect(find.byKey(runTimelineSummaryKey), findsNothing);

    // The turn ends: the panel folds by itself.
    await pumpTimeline(tester, AgentTurnState(steps: steps));
    expect(find.byKey(runTimelineSummaryKey), findsOneWidget);
    expect(find.text('本轮 2 步'), findsOneWidget);
    expect(find.text('调用工具：read_question'), findsNothing);

    // A tap opens it again for review.
    await tester.tap(find.byKey(runTimelineHeaderKey));
    await tester.pump();
    expect(find.text('运行步骤'), findsOneWidget);
    expect(find.text('调用工具：read_question'), findsOneWidget);
  });
}
