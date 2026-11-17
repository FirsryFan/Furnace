// Does the assistant's text actually appear while it is still arriving?
//
// The loop emits one state per text delta, so "streaming" is only real if the
// page paints from that state on every delta instead of waiting for the turn to
// end. That is a property of the widget tree, not of the loop, so this test
// drives the real chat page with a model whose second half is held back by a
// gate and looks at what is on screen in between.
//
// The page is used through its public API only; this file does not own it.
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/skill/skill_store.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/presentation/ai_chat_page.dart';
import 'package:furnace/features/ai/presentation/ai_message_markup.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// A model that answers in two pieces, with the second released by the test.
class _GatedAdapter implements ModelAdapter {
  final Completer<void> gate = Completer<void>();

  @override
  Stream<ModelEvent> runTurn({
    required List<ChatMessage> messages,
    required List<ModelToolSpec> tools,
  }) async* {
    yield const ModelTextDelta('前半段答案');
    await gate.future;
    yield const ModelTextDelta('，后半段答案。');
    yield const ModelTurnDone(
      finishReason: 'stop',
      promptTokens: 120,
      completionTokens: 30,
      cacheHitPromptTokens: 100,
      cacheMissPromptTokens: 20,
      generationDuration: Duration(seconds: 1),
    );
  }
}

/// A skill store with nothing installed, answering from memory: the real one
/// reads the app support directory, which the loop would otherwise wait on
/// before every turn.
class _NoSkills extends SkillStore {
  @override
  Future<List<InstalledSkill>> enabled() async => const [];
}

/// Everything the widget tree is painting, concatenated.
///
/// Every way Flutter paints text has to be covered - `Text`, rich text spans,
/// the editable field and the raw `RichText` layer - because the chat renders a
/// partial reply through more than one of them. Reading the rendered text is
/// what makes "the user can see it" a statement about pixels rather than about
/// what a widget holds.
String renderedText(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final widget in tester.allWidgets) {
    switch (widget) {
      case Text(:final data) when data != null:
        buffer.writeln(data);
      case Text(:final textSpan) when textSpan != null:
        buffer.writeln(textSpan.toPlainText(includePlaceholders: false));
      case EditableText(:final controller):
        buffer.writeln(controller.text);
      case RichText(:final text):
        buffer.writeln(text.toPlainText(includePlaceholders: false));
    }
  }
  return buffer.toString();
}

/// A model whose events the test emits one at a time.
///
/// [FakeModelAdapter] replays a finished list inside one microtask chain, so the
/// page only ever sees its last state - useless for "did each delta reach the
/// screen?". This one lets the test look at the page *between* two events.
class _StepwiseAdapter implements CancellableModelAdapter {
  final StreamController<ModelEvent> _controller =
      StreamController<ModelEvent>();

  /// Completes when the loop has actually started the model call.
  final Completer<void> started = Completer<void>();

  @override
  Stream<ModelEvent> runTurn({
    required List<ChatMessage> messages,
    required List<ModelToolSpec> tools,
  }) {
    if (!started.isCompleted) {
      started.complete();
    }
    return _controller.stream;
  }

  @override
  void cancelActiveTurn() {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(const ModelTurnCancelled());
    unawaited(_controller.close());
  }

  void emit(ModelEvent event) => _controller.add(event);

  Future<void> close() => _controller.close();
}

/// Pumps until [condition] holds; fails with [reason] instead of hanging.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
}) async {
  for (var i = 0; i < 400; i++) {
    if (condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('$reason（等待超时）');
}

/// How many rendered message bodies contain [needle].
///
/// Counting bodies rather than raw painted text: one markdown reply legitimately
/// paints through more than one text widget, so a raw occurrence count cannot
/// tell "the same answer twice" from "one answer, two text layers". One
/// [AiMessageBody] is one bubble, which is what "only one copy" means to a user.
int bodiesContaining(WidgetTester tester, String needle) => tester
    .widgetList<AiMessageBody>(find.byType(AiMessageBody))
    .where((body) => body.text.contains(needle))
    .length;

void main() {
  testWidgets('a streamed reply is painted before the turn completes',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = AiRepository(db);
    await repository.saveConfig(
      const AiConfig(
        enabled: true,
        apiKey: 'sk-test-key',
        model: 'deepseek-chat',
      ),
      fallbackLanguage: 'zh',
    );
    await repository.createConversation();

    final adapter = _GatedAdapter();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          modelAdapterProvider.overrideWithValue(adapter),
          skillStoreProvider.overrideWithValue(_NoSkills()),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AiChatPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '回答我');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.send));

    // `pumpAndSettle` cannot be used while the turn runs: the indeterminate
    // progress bar under the conversation never settles.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // ------------------------------------------- while the second half is held
    expect(renderedText(tester), contains('前半段答案'),
        reason: 'the first delta must be on screen before the turn ends');
    expect(renderedText(tester), isNot(contains('后半段答案')),
        reason: 'the second half has not been sent yet');
    expect(find.byType(LinearProgressIndicator), findsOneWidget,
        reason: 'the turn is still running at this point');

    // ------------------------------------------------------------- and after
    adapter.gate.complete();
    await tester.pumpAndSettle();

    expect(renderedText(tester), contains('前半段答案'));
    expect(renderedText(tester), contains('后半段答案'));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);

    await db.close();
  });

  testWidgets('发送后立刻看到用户消息，思考与正文逐段上屏，结束时各只有一份',
      (tester) async {
    // 2026-11-17 用户反馈：发完话对话区没有反应，等 agent 思考结束开始输出时，
    // 用户消息和思维链才一起出现。两件事都要在这里钉住：
    //   1. 用户消息在模型吐第一个 token 之前就已经在屏幕上（它甚至先于模型调用
    //      落库，页面靠 loop 状态里的 userMessageId 立刻重读）；
    //   2. reasoning 与正文各自按流事件逐段出现，而不是整轮结束一次性出现；
    //   3. 结束时用户消息、正文、思考都只有一份（不重复、不回退）。
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = AiRepository(db);
    await repository.saveConfig(
      const AiConfig(
        enabled: true,
        apiKey: 'sk-test-key',
        model: 'deepseek-chat',
      ),
      fallbackLanguage: 'zh',
    );
    await repository.createConversation();

    final adapter = _StepwiseAdapter();
    // 窄窗口：左栏（会自动用首条消息当标题）不存在，消息正文是屏幕上唯一可能
    // 出现这段话的地方——否则「找得到用户消息」这个断言会被左栏标题假阳性通过。
    tester.view.physicalSize = const Size(820, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          modelAdapterProvider.overrideWithValue(adapter),
          skillStoreProvider.overrideWithValue(_NoSkills()),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AiChatPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const userText = '你好，流式测试';
    const thinkingFirst = '先算动量';
    const thinkingRest = '，再算能量';
    const answerFirst = '答案是';
    const answerRest = ' 42。';

    await tester.enterText(find.byType(TextField).last, userText);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.send));

    // 模型调用已经被订阅（说明请求路径真的走起来了），但还没有任何流事件。
    await pumpUntil(
      tester,
      () => adapter.started.isCompleted,
      reason: '模型调用未开始',
    );
    expect(adapter.started.isCompleted, isTrue, reason: '模型调用未开始');

    // (1) 用户消息在第一个模型 token 之前就可见，而且只出现一次。
    await pumpUntil(
      tester,
      () => renderedText(tester).contains(userText),
      reason: '发送后用户消息没有立刻出现在对话里',
    );
    expect(renderedText(tester), isNot(contains(thinkingFirst)),
        reason: '模型还没有发出任何 thinking token');
    expect(renderedText(tester), isNot(contains(answerFirst)),
        reason: '模型还没有发出任何正文 token');
    expect(find.byType(LinearProgressIndicator), findsOneWidget,
        reason: '本轮仍在进行');
    expect(bodiesContaining(tester, userText), 1,
        reason: '用户消息只应出现一次（重读已存消息不能和本地状态重复）');

    // (2) 思考按流事件逐段出现：先第一段，第二段到达后接在后面。
    adapter.emit(const ModelReasoningDelta(thinkingFirst));
    await pumpUntil(
      tester,
      () => renderedText(tester).contains(thinkingFirst),
      reason: '思考第一段没有在流事件到达后立刻上屏',
    );
    expect(renderedText(tester), isNot(contains(thinkingRest)),
        reason: '第二段思考还没到');
    adapter.emit(const ModelReasoningDelta(thinkingRest));
    await pumpUntil(
      tester,
      () => renderedText(tester).contains('$thinkingFirst$thinkingRest'),
      reason: '思考第二段没有接在已有思考后面',
    );

    // (3) 正文同样逐段出现，并且不覆盖思考面板。
    adapter.emit(const ModelTextDelta(answerFirst));
    await pumpUntil(
      tester,
      () => renderedText(tester).contains(answerFirst),
      reason: '正文第一段没有在流事件到达后立刻上屏',
    );
    expect(renderedText(tester), isNot(contains('42')),
        reason: '正文第二段还没到');
    expect(renderedText(tester), contains('$thinkingFirst$thinkingRest'),
        reason: '正文上屏不能把已经显示的思考抹掉');
    adapter.emit(const ModelTextDelta(answerRest));
    await pumpUntil(
      tester,
      () => renderedText(tester).contains('$answerFirst$answerRest'),
      reason: '正文第二段没有接在已有正文后面',
    );

    // (4) 结束：最终答案与用户消息都只有一份，思考交给历史折叠块。
    adapter.emit(const ModelTurnDone(finishReason: 'stop'));
    await adapter.close();
    await pumpUntil(
      tester,
      () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      reason: '回合没有结束',
    );
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    final text = renderedText(tester);
    expect(text, contains('$answerFirst$answerRest'));
    expect(bodiesContaining(tester, userText), 1,
        reason: '结束时用户消息不能重复出现');
    expect(bodiesContaining(tester, '$answerFirst$answerRest'), 1,
        reason: '最终答案只能有一份（流式气泡不能和落库行同时留着）');
    expect(bodiesContaining(tester, '$thinkingFirst$thinkingRest'), 0,
        reason: '思考已收进历史折叠块（默认收起），不能同时留在流式面板里');
    expect(find.byKey(aiReasoningPanelKey), findsNothing,
        reason: '思考已随助手消息落库，流式面板让位给历史折叠块，不重复显示');
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);

    await db.close();
  });
}
