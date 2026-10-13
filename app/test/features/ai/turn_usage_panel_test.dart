// The turn/usage panel itself.
//
// The point of these tests is the contract the panel makes to the user: six
// figures, and whenever a figure was not measured it is a dash rather than a
// number that looks measured. Labels are found by key, not by text, so the
// assertions survive a translation change.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';
import 'package:furnace/features/ai/presentation/widgets/turn_usage_panel.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// Everything the provider can report, at values chosen so each figure has a
/// distinct, checkable answer.
const _fullFixture = TurnUsage(
  rounds: 3,
  maxRounds: 8,
  roundsWithUsage: 3,
  promptTokens: 2200,
  completionTokens: 100,
  cacheHitPromptTokens: 1900,
  cacheMissPromptTokens: 300,
  generationTime: Duration(seconds: 4),
  lastPromptTokens: 16384,
  contextWindowTokens: 65536,
  toolCallsExecuted: 2,
  toolCallsPending: 1,
  toolCallsRejected: 1,
);

Future<void> pumpPanel(WidgetTester tester, TurnUsageView view) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        // A fresh key per pump: the panel's notifier is created by the harness
        // state, and reusing the state would keep the first scenario's reading.
        body: SingleChildScrollView(
          child: _Harness(key: UniqueKey(), view: view),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Mirrors the integration: a notifier drives the panel through a
/// [ValueListenableBuilder], exactly as [TurnUsageSection] does in the page.
class _Harness extends StatefulWidget {
  const _Harness({super.key, required this.view});

  final TurnUsageView view;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late final TurnUsageNotifier _notifier = TurnUsageNotifier(
    initial: AgentTurnState(
      generating: widget.view.generating,
      usage: widget.view.usage ?? const TurnUsage(),
    ),
  );

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TurnUsageSection(notifier: _notifier);
}

String valueOf(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

void main() {
  testWidgets('renders all six figures from a fixture state', (tester) async {
    await pumpPanel(
      tester,
      const TurnUsageView(usage: _fullFixture),
    );

    // 1. rounds, against the configured cap.
    expect(valueOf(tester, TurnUsagePanel.roundsKey), '3 / 8');
    // 2. steps, with the pending and rejected counts spelled out beside it.
    expect(valueOf(tester, TurnUsagePanel.stepsKey), '2');
    expect(find.text('1 待确认 · 1 已拒绝'), findsOneWidget);
    // 3. total tokens, with the prompt/completion split as its note.
    expect(valueOf(tester, TurnUsagePanel.totalTokensKey), '2300');
    expect(find.text('输入 2200 + 输出 100'), findsOneWidget);
    // 4. tokens/s: 100 completion tokens over 4 s of generation.
    expect(valueOf(tester, TurnUsagePanel.rateKey), '25.0');
    // 5. cache hit rate: 1900 hits of 2200 prompt tokens.
    expect(valueOf(tester, TurnUsagePanel.cacheKey), '86.4%');
    // 6. context occupancy: 16384 of a 65536-token window, labelled an estimate.
    expect(valueOf(tester, TurnUsagePanel.contextKey), '25.0%');
    expect(find.textContaining('65536'), findsOneWidget);
    expect(find.textContaining('估算'), findsOneWidget,
        reason: 'the window is a configured value, so the figure is an estimate '
            'and the panel has to say so');

    // The six figures are labelled in the user's language.
    for (final label in [
      '轮数',
      '步数',
      '总 token',
      'tokens/s',
      '缓存命中率',
      '上下文占用',
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'label "$label"');
    }
  });

  testWidgets('shows dashes - not zeros - when the endpoint reports no usage',
      (tester) async {
    await pumpPanel(
      tester,
      const TurnUsageView(
        usage: TurnUsage(rounds: 2, maxRounds: 8, toolCallsExecuted: 1),
      ),
    );

    // The two figures the loop measures by itself are still real.
    expect(valueOf(tester, TurnUsagePanel.roundsKey), '2 / 8');
    expect(valueOf(tester, TurnUsagePanel.stepsKey), '1');
    // The four that depend on the provider are dashes.
    for (final key in [
      TurnUsagePanel.totalTokensKey,
      TurnUsagePanel.rateKey,
      TurnUsagePanel.cacheKey,
      TurnUsagePanel.contextKey,
    ]) {
      expect(valueOf(tester, key), '—', reason: 'key $key');
    }
    expect(find.text('本轮没有返回 token 用量。'), findsOneWidget);
    expect(find.text('该服务未返回缓存命中数据。'), findsOneWidget);
  });

  testWidgets('marks the live rate as an estimate and the frozen one as not',
      (tester) async {
    // Mid-round: no usage reported yet, 50 characters streamed in 1 s.
    await pumpPanel(
      tester,
      const TurnUsageView(
        generating: true,
        usage: TurnUsage(
          rounds: 1,
          maxRounds: 8,
          inFlightChars: 50,
          inFlightElapsed: Duration(seconds: 1),
        ),
      ),
    );
    final live = valueOf(tester, TurnUsagePanel.rateKey);
    expect(live, startsWith('≈'));
    expect(live, '≈20.0', reason: '50 chars / 2.5 per token over 1 s');
    expect(find.text('本轮'), findsOneWidget);

    // Finished: the provider's own count, no estimate marker.
    await pumpPanel(
      tester,
      const TurnUsageView(
        usage: TurnUsage(
          rounds: 1,
          maxRounds: 8,
          roundsWithUsage: 1,
          promptTokens: 500,
          completionTokens: 40,
          generationTime: Duration(seconds: 2),
        ),
      ),
    );
    expect(valueOf(tester, TurnUsagePanel.rateKey), '20.0');
    expect(find.text('最近一轮'), findsOneWidget);
  });

  testWidgets('paints nothing at all for a turn nothing was measured for',
      (tester) async {
    await pumpPanel(tester, TurnUsageView.empty);
    expect(find.byType(TurnUsagePanel), findsOneWidget);
    expect(find.byType(Card), findsNothing,
        reason: 'an untouched turn must not leave an empty card on screen');
    expect(find.byKey(TurnUsagePanel.roundsKey), findsNothing);
  });

  testWidgets('is collapsible without losing the two headline figures',
      (tester) async {
    await pumpPanel(tester, const TurnUsageView(usage: _fullFixture));

    // Tapping the header (not the tile's centre, which when expanded sits over
    // a child row) is what the user does to fold it away.
    await tester.tap(find.text('最近一轮'));
    await tester.pumpAndSettle();

    expect(find.byKey(TurnUsagePanel.totalTokensKey), findsNothing);
    // The subtitle still carries rounds and rate, so folding it away hides
    // detail rather than information.
    expect(find.textContaining('3 / 8'), findsOneWidget);
    expect(find.textContaining('25.0'), findsOneWidget);
  });

  group('TurnUsageNotifier', () {
    test('keeps the last finished turn on screen while a new one starts',
        () async {
      final controller = StreamController<AgentTurnState>.broadcast();
      final notifier = TurnUsageNotifier(states: controller.stream);
      addTearDown(() {
        notifier.dispose();
        controller.close();
      });

      controller.add(const AgentTurnState(
        generating: true,
        rounds: 1,
        usage: TurnUsage(rounds: 1, maxRounds: 8),
      ));
      // The stream is asynchronous, so the event has to be delivered before the
      // notifier can be asked what it holds.
      await Future<void>.delayed(Duration.zero);
      expect(notifier.value.generating, isTrue);
      expect(notifier.value.usage!.rounds, 1);

      controller.add(const AgentTurnState(
        rounds: 2,
        usage: TurnUsage(rounds: 2, maxRounds: 8, completionTokens: 7),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(notifier.value.generating, isFalse);
      expect(notifier.value.usage!.completionTokens, 7);

      // The loop resets for a new user message: the summary stays rather than
      // blanking, and it is not claimed to be live.
      controller.add(const AgentTurnState(generating: true, rounds: 1));
      await Future<void>.delayed(Duration.zero);
      expect(notifier.value.usage!.completionTokens, 7);
      expect(notifier.value.generating, isFalse);
    });

    test('seeds from the state the loop is already in', () {
      final notifier = TurnUsageNotifier(
        initial: const AgentTurnState(
          usage: TurnUsage(rounds: 4, maxRounds: 8),
        ),
      );
      addTearDown(notifier.dispose);
      expect(notifier.value.usage!.rounds, 4);
      expect(notifier.value.hasData, isTrue);
    });
  });
}
