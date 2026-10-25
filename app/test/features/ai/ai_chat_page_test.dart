import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/ai/presentation/ai_chat_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// The three things about the chat screen that only a widget test can check:
///
///  * the message box takes an explicit newline and can be resized by dragging
///    its handle, without the conversation list stealing the drag;
///  * Enter sends while Shift+Enter breaks the line (the page implements that
///    combination itself, so it needs a test that presses the keys);
///  * the conversation list collapses, and stays collapsed across a rebuild.
///
/// It drives the real page against an in-memory database and a scripted model,
/// so no API key, no file system and no network are involved - and nothing here
/// skips itself.
void main() {
  late AppDatabase db;
  late ModelAdapter adapter;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    adapter = FakeModelAdapter([FakeModelAdapter.answer('好的')]);
    // A usable configuration: without a key the page shows the "not set up"
    // screen instead of the chat, and every assertion below would be testing
    // the wrong widget.
    await AiRepository(db).saveConfig(
      const AiConfig(enabled: true, apiKey: 'sk-test'),
      fallbackLanguage: 'zh',
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// Pumps the page on its own, with localisations, at [size].
  ///
  /// 1400 logical pixels is above the sidebar breakpoint, which is what the
  /// narrow-window test changes on purpose.
  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(1400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          modelAdapterProvider.overrideWithValue(adapter),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AiChatPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final input = find.byType(TextField);
  final handle = find.byKey(AiChatPage.inputResizeHandleKey);

  TextEditingController controllerOf(WidgetTester tester) =>
      tester.widget<TextField>(input).controller!;

  /// Pumps a bounded number of frames.
  ///
  /// Never [WidgetTester.pumpAndSettle] for these: while a turn is generating
  /// the page shows an indeterminate progress bar, which animates forever.
  Future<void> pumpFrames(WidgetTester tester, [int frames = 10]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Pumps until [condition] holds, failing after three simulated seconds.
  Future<void> waitFor(
    WidgetTester tester,
    bool Function() condition, {
    required String reason,
  }) async {
    for (var i = 0; i < 150; i++) {
      if (condition()) {
        return;
      }
      await tester.pump(const Duration(milliseconds: 20));
    }
    fail('$reason 在 3 秒模拟时间内未满足');
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(AiChatPage)));

  /// Sends [text] and waits until the loop is actually reading the adapter.
  Future<void> startTurn(
    WidgetTester tester,
    _ControlledAdapter controlled,
    String text,
  ) async {
    await tester.enterText(input, text);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await waitFor(tester, () => controlled.started.isCompleted,
        reason: '模型调用未开始');
    await pumpFrames(tester);
  }

  group('the message box', () {
    testWidgets('accepts a newline and keeps it', (tester) async {
      await AiRepository(db).createConversation();
      await pumpPage(tester);

      await tester.enterText(input, '第一行\n第二行');
      await tester.pumpAndSettle();

      expect(controllerOf(tester).text, '第一行\n第二行');
      expect(controllerOf(tester).text.contains('\n'), isTrue,
          reason: 'the box must be able to hold more than one line');
    });

    testWidgets('Enter sends, Shift+Enter breaks the line', (tester) async {
      final conversation = await AiRepository(db).createConversation();
      await pumpPage(tester);

      // Focus the field the way a user would, so the page's key handler is on
      // the focus chain.
      await tester.tap(input);
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(controllerOf(tester).text, '\n',
          reason: 'Shift+Enter inserts a line break instead of sending');

      // Enter alone sends: the box is cleared and the message reached the loop.
      await tester.enterText(input, '你好');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(controllerOf(tester).text, isEmpty);
      final messages = await AiRepository(db).listMessages(conversation.id);
      expect(messages.map((m) => m.content), contains('你好'));
    });

    testWidgets('the send button still sends', (tester) async {
      // The requirement keeps the existing send reachable by button; Enter is
      // an addition, not a replacement.
      final conversation = await AiRepository(db).createConversation();
      await pumpPage(tester);

      await tester.enterText(input, '按钮发送');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(controllerOf(tester).text, isEmpty);
      final messages = await AiRepository(db).listMessages(conversation.id);
      expect(messages.map((m) => m.content), contains('按钮发送'));
    });

    testWidgets('dragging the handle resizes it, bounded at both ends',
        (tester) async {
      await AiRepository(db).createConversation();
      await pumpPage(tester);

      final start = tester.getSize(input).height;

      // Up two lines (24 logical pixels per line). The handle sits under the
      // box, so dragging it up makes the box taller.
      await tester.drag(handle, const Offset(0, -48));
      await tester.pumpAndSettle();
      final taller = tester.getSize(input).height;
      expect(taller, greaterThan(start));

      // Far past the maximum: the box stops at the limit instead of following
      // the pointer, and dragging further changes nothing.
      await tester.drag(handle, const Offset(0, -2000));
      await tester.pumpAndSettle();
      final capped = tester.getSize(input).height;
      expect(capped, greaterThan(taller));
      await tester.drag(handle, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.getSize(input).height, capped,
          reason: 'the maximum is a real limit');

      // And back down to the minimum.
      await tester.drag(handle, const Offset(0, 4000));
      await tester.pumpAndSettle();
      final smallest = tester.getSize(input).height;
      expect(smallest, lessThan(start));
      expect(smallest, greaterThan(0));
      await tester.drag(handle, const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(tester.getSize(input).height, smallest,
          reason: 'the minimum is a real limit');

      // Text that needs more room scrolls inside the box rather than growing
      // it: the height the user chose is the height they keep.
      await tester.enterText(input, List.filled(30, '一行文字').join('\n'));
      await tester.pumpAndSettle();
      expect(tester.getSize(input).height, smallest);
    });

    testWidgets('the drag does not scroll the conversation behind it',
        (tester) async {
      final conversation = await AiRepository(db).createConversation();
      await AiRepository(db).addMessage(
        conversationId: conversation.id,
        role: AiRepository.roleUser,
        content: '历史消息',
      );
      await pumpPage(tester);

      final list = find.byType(ListView);
      final before =
          tester.widget<ListView>(list.first).controller?.offset ?? 0;

      await tester.drag(handle, const Offset(0, 96));
      await tester.pumpAndSettle();

      final after = tester.widget<ListView>(list.first).controller?.offset ?? 0;
      expect(after, before,
          reason: 'the handle owns the vertical drag where it sits');
    });
  });

  group('the conversation list', () {
    testWidgets('toggles and stays toggled across a rebuild', (tester) async {
      await AiRepository(db).createConversation(title: '第一个对话');
      await pumpPage(tester);

      expect(find.byKey(AiChatPage.sidebarKey), findsOneWidget,
          reason: 'a wide window opens with the list shown');

      await tester.tap(find.byKey(AiChatPage.sidebarToggleKey));
      await tester.pumpAndSettle();
      expect(find.byKey(AiChatPage.sidebarKey), findsNothing);

      // A rebuild driven by the data layer, not by the toggle: the collapsed
      // state has to survive the page building itself again.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AiChatPage)),
      );
      container.invalidate(conversationsProvider);
      await tester.pumpAndSettle();
      expect(find.byKey(AiChatPage.sidebarKey), findsNothing,
          reason: 'the state is page state, so a rebuild keeps it');

      await tester.tap(find.byKey(AiChatPage.sidebarToggleKey));
      await tester.pumpAndSettle();
      expect(find.byKey(AiChatPage.sidebarKey), findsOneWidget);
    });

    testWidgets('a narrow window offers neither the list nor a dead toggle',
        (tester) async {
      await AiRepository(db).createConversation(title: '第一个对话');
      await pumpPage(tester, size: const Size(700, 800));

      expect(find.byKey(AiChatPage.sidebarKey), findsNothing);
      expect(find.byKey(AiChatPage.sidebarToggleKey), findsNothing,
          reason: 'a toggle that cannot show anything is worse than none');
      // The thread and its input are still laid out, with nothing overflowing.
      expect(input, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the thread', () {
    testWidgets('opens at the newest message and does not jump back on rebuild',
        (tester) async {
      final repository = AiRepository(db);
      final conversation = await repository.createConversation(title: '长对话');
      for (var i = 0; i < 40; i++) {
        await repository.addMessage(
          conversationId: conversation.id,
          role: AiRepository.roleUser,
          content: '历史消息 $i',
        );
      }
      await pumpPage(tester);

      final list = find.byType(ListView).last;
      final controller = tester.widget<ListView>(list).controller!;
      expect(controller.position.maxScrollExtent, greaterThan(0),
          reason: 'the conversation has to be long enough to scroll');
      expect(controller.offset,
          moreOrLessEquals(controller.position.maxScrollExtent, epsilon: 1),
          reason: 'a reopened conversation starts at the newest message');

      // The user scrolls up to read history. An unrelated rebuild (the sidebar
      // toggle) must not yank them back down.
      await tester.drag(list, const Offset(0, 400));
      await tester.pumpAndSettle();
      final reading = controller.offset;
      expect(reading, lessThan(controller.position.maxScrollExtent));

      await tester.tap(find.byKey(AiChatPage.sidebarToggleKey));
      await tester.pumpAndSettle();
      expect(controller.offset, moreOrLessEquals(reading, epsilon: 1),
          reason: 'the initial scroll happens once, not on every rebuild');
    });
  });

  group('persisted tool results', () {
    /// Seeds a committed turn whose tool call is already in the database.
    Future<void> seedToolTurn({
      String toolCallId = 'call_seed',
      String? content,
      String status = AiRepository.statusExecuted,
      String? beforeJson,
      String? afterJson,
      bool recordAction = true,
    }) async {
      final repository = AiRepository(db);
      final conversation = await repository.createConversation();
      final assistant = await repository.addMessage(
        conversationId: conversation.id,
        role: AiRepository.roleAssistant,
        content: '我来处理。',
      );
      await repository.addMessage(
        conversationId: conversation.id,
        role: AiRepository.roleTool,
        toolCallId: toolCallId,
        content: content,
      );
      if (recordAction) {
        await repository.recordAction(
          conversationId: conversation.id,
          toolName: 'manage_task',
          risk: 'write',
          argsJson: '{}',
          toolCallId: toolCallId,
          status: status,
          beforeJson: beforeJson,
          afterJson: afterJson,
        );
        await repository.attachMessageId(
          conversationId: conversation.id,
          toolCallId: toolCallId,
          messageId: assistant.id,
        );
      }
    }

    testWidgets('shows a committed call again, with its result on demand',
        (tester) async {
      await seedToolTurn(
        content: jsonEncode({
          'ok': true,
          'summary': '已创建任务「写作业」',
          'result': {'marker': 'unique-result-marker'},
        }),
        beforeJson: '{}',
        afterJson: '{}',
      );

      await pumpPage(tester);

      // The row used to be dropped altogether; now its summary is the first
      // line, so reopening a conversation does not lose what the model did.
      expect(find.textContaining('已创建任务「写作业」'), findsOneWidget);
      expect(find.textContaining('unique-result-marker'), findsNothing,
          reason: 'the raw payload is available on request, not by default');

      await tester.tap(find.textContaining('已创建任务「写作业」'));
      await tester.pumpAndSettle();
      expect(find.textContaining('unique-result-marker'), findsOneWidget,
          reason: 'tapping the tile reveals the result');

      // Executed with a snapshot, so history can still undo it.
      expect(find.text('撤销'), findsOneWidget);
    });

    testWidgets('offers no undo when the call left no snapshot',
        (tester) async {
      await seedToolTurn(
        content: jsonEncode({'ok': true, 'summary': '只读查询完成'}),
        recordAction: false,
      );
      await pumpPage(tester);

      expect(find.textContaining('只读查询完成'), findsOneWidget);
      expect(find.text('撤销'), findsNothing,
          reason: 'an undo button with no snapshot would lie');
    });

    testWidgets('a failed call reads differently from a success',
        (tester) async {
      await seedToolTurn(
        content: jsonEncode({
          'ok': false,
          'summary': '执行失败：数据库锁',
          'error': '执行失败：数据库锁',
        }),
      );
      await pumpPage(tester);

      expect(find.textContaining('执行失败：数据库锁'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget,
          reason: 'a failure must not look like a success');
    });

    testWidgets('a call shown in memory is not also shown from the database',
        (tester) async {
      adapter = FakeModelAdapter([
        FakeModelAdapter.callTool(
          'manage_task',
          {'action': 'create', 'title': '去重用例'},
          id: 'call_dedupe',
        ),
        FakeModelAdapter.answer('加好了。'),
      ]);
      final repository = AiRepository(db);
      await repository.saveConfig(
        const AiConfig(
          enabled: true,
          apiKey: 'sk-test',
          permissionMode: AiPermissionMode.auto,
        ),
        fallbackLanguage: 'zh',
      );
      final conversation = await repository.createConversation();
      await pumpPage(tester);

      await tester.enterText(input, '建一个任务');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      final rows = await repository.listMessages(conversation.id);
      expect(
          rows.where((row) => row.role == AiRepository.roleTool), hasLength(1),
          reason:
              'the turn must have committed for this test to mean anything');
      expect(find.textContaining('已创建任务「去重用例」'), findsOneWidget,
          reason: 'the in-memory tile and the stored row are one call');
    });
  });

  group('reasoning and stopping a turn', () {
    testWidgets('shows the thinking, expanded, while the turn runs',
        (tester) async {
      final controlled = _ControlledAdapter();
      adapter = controlled;
      await AiRepository(db).createConversation();
      await pumpPage(tester);
      final l10n = l10nOf(tester);

      await startTurn(tester, controlled, '仔细想');
      controlled.emit(const ModelReasoningDelta('先算动量'));
      await waitFor(
          tester, () => find.byKey(aiReasoningPanelKey).evaluate().isNotEmpty,
          reason: '思考块未出现');

      final panel = find.byKey(aiReasoningPanelKey);
      expect(find.text(l10n.aiReasoningTitle), findsOneWidget);
      expect(find.text(l10n.aiReasoningGenerating), findsOneWidget);
      final body = find.descendant(
        of: panel,
        matching: find.byType(SelectableText),
      );
      expect(body, findsOneWidget, reason: '生成中的思考默认展开');
      expect(tester.widget<SelectableText>(body).data, '先算动量');

      expect(find.byKey(aiStopButtonKey), findsOneWidget);
      expect(find.byIcon(Icons.send), findsNothing, reason: '生成中发送键被停止键取代');
    });

    testWidgets('the stop button cancels the turn and becomes send again',
        (tester) async {
      final controlled = _ControlledAdapter();
      adapter = controlled;
      await AiRepository(db).createConversation();
      await pumpPage(tester);
      final l10n = l10nOf(tester);

      await startTurn(tester, controlled, '讲个故事');
      controlled.emit(const ModelTextDelta('从前'));
      await waitFor(tester, () => find.text('从前').evaluate().isNotEmpty,
          reason: '部分回答未出现');

      await tester.tap(find.byKey(aiStopButtonKey));
      await tester.pump();
      // The stop callback runs in the test binding's real zone: the cancellation
      // it hands the loop through the adapter's stream, and the write of the
      // partial answer that follows, are delivered on the real event loop.
      // `tester.pump` only drains the fake clock, so give real async one turn
      // before asserting; without it the loop stays `generating` forever.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await pumpFrames(tester, 30);

      expect(controlled.cancelCalls, 1);
      expect(find.byKey(aiStopButtonKey), findsNothing);
      expect(find.byIcon(Icons.send), findsOneWidget, reason: '停止后发送键回来');
      expect(find.text(l10n.aiCancelledLabel), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing,
          reason: '主动停止不是错误，不能出错误横幅');
    });

    testWidgets('stopping keeps the partial answer, exactly once',
        (tester) async {
      final controlled = _ControlledAdapter();
      adapter = controlled;
      final repository = AiRepository(db);
      final conversation = await repository.createConversation();
      await pumpPage(tester);

      await startTurn(tester, controlled, '讲个故事');
      controlled.emit(const ModelTextDelta('从前'));
      await waitFor(tester, () => find.text('从前').evaluate().isNotEmpty,
          reason: '部分回答未出现');
      await tester.tap(find.byKey(aiStopButtonKey));
      // Same real-zone hop as the stop test above: the cancel event reaches the
      // loop's `await for` on the real event loop, not the fake clock.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await waitFor(
          tester, () => find.byKey(aiCancelledLabelKey).evaluate().isNotEmpty,
          reason: '已停止标记未出现');
      // Let the reload triggered by the finished send land: the partial answer
      // is both the streaming bubble and a stored row, and must read as one.
      await pumpFrames(tester, 30);
      await waitFor(tester, () => find.text('从前').evaluate().length == 1,
          reason: '部分回答应只显示一次');

      final rows = await repository.listMessages(conversation.id);
      expect(
        rows
            .where((row) => row.role == AiRepository.roleAssistant)
            .map((row) => row.content),
        contains('从前'),
        reason: '停止前到达的文本是真实输出，必须落库',
      );
    });

    testWidgets('a finished turn folds the thinking and marks no cancellation',
        (tester) async {
      final controlled = _ControlledAdapter();
      adapter = controlled;
      await AiRepository(db).createConversation();
      await pumpPage(tester);
      final l10n = l10nOf(tester);

      await startTurn(tester, controlled, '在吗');
      controlled.emit(const ModelReasoningDelta('先想'));
      await waitFor(
          tester, () => find.byKey(aiReasoningPanelKey).evaluate().isNotEmpty,
          reason: '思考块未出现');
      controlled.emit(const ModelTextDelta('答案'));
      await waitFor(tester, () => find.text('答案').evaluate().isNotEmpty,
          reason: '回答未出现');
      controlled.emit(const ModelTurnDone(finishReason: 'stop'));
      await controlled.close();
      await waitFor(
          tester, () => find.byKey(aiStopButtonKey).evaluate().isEmpty,
          reason: '停止按钮未消失');
      await pumpFrames(tester, 30);

      expect(find.byKey(aiCancelledLabelKey), findsNothing);
      expect(find.byKey(aiStopButtonKey), findsNothing);
      expect(find.byIcon(Icons.send), findsOneWidget);
      expect(find.text(l10n.aiReasoningGenerating), findsNothing);

      final panel = find.byKey(aiReasoningPanelKey);
      expect(panel, findsOneWidget);
      final body = find.descendant(
        of: panel,
        matching: find.byType(SelectableText),
      );
      expect(body, findsNothing, reason: '回答到达后思考块默认收起');

      await tester.tap(find.text(l10n.aiReasoningTitle));
      await pumpFrames(tester);
      expect(body, findsOneWidget, reason: '收起后仍可手动展开');
      expect(tester.widget<SelectableText>(body).data, '先想');
    });
  });

  group('the stop button while waiting for approval', () {
    testWidgets('a pending turn can be dropped instead of approved',
        (tester) async {
      // The send button is disabled while a batch waits for approval, so the
      // stop button is the only way out; cancelling must not execute anything.
      final controlled = _ControlledAdapter();
      adapter = controlled;
      final repository = AiRepository(db);
      await repository.saveConfig(
        const AiConfig(
          enabled: true,
          apiKey: 'sk-test',
          permissionMode: AiPermissionMode.plan,
        ),
        fallbackLanguage: 'zh',
      );
      await repository.createConversation();
      await pumpPage(tester);
      final l10n = l10nOf(tester);

      await startTurn(tester, controlled, '建一个任务');
      controlled.emit(ModelToolCall(ToolCallRequest.fromJson({
        'id': 'call_pending',
        'function': {
          'name': 'manage_task',
          'arguments': jsonEncode({
            'action': 'create',
            'title': '待批准任务',
          }),
        },
      })));
      controlled.emit(const ModelTurnDone(finishReason: 'tool_calls'));
      await controlled.close();
      // The approval panel is the signal that the loop has really reached the
      // pending state, so the stop below lands on a pending turn.
      await waitFor(
          tester, () => find.text(l10n.aiPendingTitle).evaluate().isNotEmpty,
          reason: '审批面板未出现');
      expect(find.byKey(aiStopButtonKey), findsOneWidget, reason: '等待批准时仍应能停止');

      await tester.tap(find.byKey(aiStopButtonKey));
      await pumpFrames(tester, 30);

      expect(controlled.cancelCalls, 1);
      expect(find.byKey(aiStopButtonKey), findsNothing);
      expect(find.byIcon(Icons.send), findsOneWidget);
      expect(find.text(l10n.aiPendingTitle), findsNothing,
          reason: '整批被丢弃：审批面板关闭，没有执行任何调用');
    });
  });
}

/// A cancellable adapter whose events the test emits one by one, so a stop
/// can land at an exact point in the stream.
class _ControlledAdapter implements CancellableModelAdapter {
  final StreamController<ModelEvent> _controller =
      StreamController<ModelEvent>();

  /// Completes when the loop has actually subscribed to a turn.
  final Completer<void> started = Completer<void>();

  int runCalls = 0;
  int cancelCalls = 0;

  @override
  Stream<ModelEvent> runTurn({
    required List<ChatMessage> messages,
    required List<ModelToolSpec> tools,
  }) {
    runCalls++;
    if (!started.isCompleted) {
      started.complete();
    }
    return _controller.stream;
  }

  @override
  void cancelActiveTurn() {
    cancelCalls++;
    if (_controller.isClosed) {
      return;
    }
    _controller.add(const ModelTurnCancelled());
    unawaited(_controller.close());
  }

  void emit(ModelEvent event) {
    _controller.add(event);
  }

  Future<void> close() => _controller.close();
}
