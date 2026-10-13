import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
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
  late FakeModelAdapter adapter;

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

      // Down two lines (24 logical pixels per line).
      await tester.drag(handle, const Offset(0, 48));
      await tester.pumpAndSettle();
      final taller = tester.getSize(input).height;
      expect(taller, greaterThan(start));

      // Far past the maximum: the box stops at the limit instead of following
      // the pointer, and dragging further changes nothing.
      await tester.drag(handle, const Offset(0, 2000));
      await tester.pumpAndSettle();
      final capped = tester.getSize(input).height;
      expect(capped, greaterThan(taller));
      await tester.drag(handle, const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(tester.getSize(input).height, capped,
          reason: 'the maximum is a real limit');

      // And back down to the minimum.
      await tester.drag(handle, const Offset(0, -4000));
      await tester.pumpAndSettle();
      final smallest = tester.getSize(input).height;
      expect(smallest, lessThan(start));
      expect(smallest, greaterThan(0));
      await tester.drag(handle, const Offset(0, -400));
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
      final before = tester.widget<ListView>(list.first).controller?.offset ?? 0;

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
}
