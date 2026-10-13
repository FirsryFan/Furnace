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
}
