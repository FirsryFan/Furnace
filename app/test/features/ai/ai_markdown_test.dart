// Markdown and LaTeX rendering for the AI chat.
//
// The chat is the one place in the app where text arrives from somewhere else
// and is shown to the user verbatim, so it has two failure modes that no unit
// test of the parser would catch: a streamed fragment can be interpreted as the
// start of a construct that never closes, and a user's own message can be
// reinterpreted as markup they did not write. Both are asserted here by looking
// at what the widget tree actually paints.
//
// Assertions read the *rendered* text rather than a screenshot: `renderedText`
// gathers the characters of every text-painting widget in the tree, so
// "the `**` are gone" is a statement about the pixels the user would see.
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/core/theme/theme_profile.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/skill/skill_store.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/presentation/ai_chat_page.dart';
import 'package:furnace/features/ai/presentation/ai_message_markup.dart';
import 'package:furnace/l10n/app_localizations.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// A reply that uses every construct the chat is expected to render: headings,
/// bold and italic, both list kinds, a link, a blockquote, a table, a fenced
/// code block, inline code and a horizontal rule.
const _richReply = '''
# 标题一

这是 **加粗** 与 *斜体* 的段落。

## 二级标题

- 第一项
- 第二项

1. 有序一
2. 有序二

> 引用的一段话

[链接文本](https://example.com/page)

| 名字 | 分数 |
| --- | --- |
| 甲 | 90 |
| 乙 | 85 |

---

```dart
final x = 1;
```

行内代码 `a*b*c` 结束。
''';

/// Every character the current tree would paint, gathered from the widgets that
/// carry text.
///
/// `Text` contributes both its `data` and the `RichText` it builds, so a string
/// can be counted twice; the assertions below only ask whether something is
/// present or absent, which duplication cannot change.
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

/// Whether any run of text painted with a bold weight contains [word].
///
/// Marker absence alone would also pass if the parser had simply dropped the
/// `**`: this asks for the weight that makes the word bold.
bool hasBoldRun(WidgetTester tester, String word) {
  var found = false;
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    richText.text.visitChildren((span) {
      if (span is TextSpan &&
          (span.style?.fontWeight?.value ?? 0) >= 600 &&
          (span.text ?? '').contains(word)) {
        found = true;
      }
      return true;
    });
  }
  return found;
}

/// Whether any run of text painted in italic contains [word].
bool hasItalicRun(WidgetTester tester, String word) {
  var found = false;
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    richText.text.visitChildren((span) {
      if (span is TextSpan &&
          span.style?.fontStyle == FontStyle.italic &&
          (span.text ?? '').contains(word)) {
        found = true;
      }
      return true;
    });
  }
  return found;
}

/// How many formula widgets from `val_latex_flutter` the tree holds.
///
/// Matched by type name on purpose: `val_latex_flutter` is a transitive
/// dependency, and importing it here would add a
/// `depend_on_referenced_packages` analyzer diagnostic for a check that only
/// needs to know the widget exists.
int mathWidgetCount(WidgetTester tester) => tester
    .widgetList(
        find.byWidgetPredicate((w) => w.runtimeType.toString() == 'Math'))
    .length;

/// Mounts one message body, scrolled so a long reply cannot overflow the test
/// surface, and framed by a theme when one is given.
Future<void> pumpBody(
  WidgetTester tester,
  String text, {
  bool isUser = false,
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: SingleChildScrollView(
              child: AiMessageBody(text: text, isUser: isUser),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // --------------------------------------------------------------- the guard
  //
  // The guard is a pure function so the rule can be stated and tested without a
  // widget: which fragments are complete enough to be parsed as markdown.
  group('aiMessageRendersAsMarkdown', () {
    test('a complete document is renderable', () {
      expect(aiMessageRendersAsMarkdown(_richReply), isTrue);
      expect(aiMessageRendersAsMarkdown('普通的一段话'), isTrue);
      expect(aiMessageRendersAsMarkdown('公式 \$E=mc^2\$ 与 \$\$a+b\$\$'), isTrue);
      expect(aiMessageRendersAsMarkdown('\\\$ 是转义的美元符号'), isTrue);
    });

    test('an unclosed fence is not renderable', () {
      expect(aiMessageRendersAsMarkdown('看这段代码：\n\n```dart\nfinal x = 1;'),
          isFalse);
      expect(aiMessageRendersAsMarkdown('```\ncode\n~~~'), isFalse,
          reason: 'the two fence characters cannot close each other');
    });

    test('unterminated math is not renderable', () {
      expect(aiMessageRendersAsMarkdown('结果是 \$\$E=mc^2'), isFalse,
          reason: 'an unterminated display block would swallow the rest');
      expect(aiMessageRendersAsMarkdown('结果是 \$E=mc^2'), isFalse,
          reason: 'an odd number of unescaped \$ is an unfinished formula');
      expect(aiMessageRendersAsMarkdown('结果是 \$'), isFalse);
    });

    test('an escaped dollar neither opens nor closes a formula', () {
      expect(aiMessageRendersAsMarkdown('价格是 \\\$5'), isTrue);
      expect(aiMessageRendersAsMarkdown('公式 \$x\$ 与 \\\$5'), isTrue);
    });

    test('currency prose is not mistaken for a formula', () {
      // The strict spacing rule is what keeps this out: without it the two
      // amounts would pair up and the renderer would turn prose into a formula.
      expect(aiMessageRendersAsMarkdown('花了 \$5 到 \$9'), isFalse);
      expect(aiMessageRendersAsMarkdown('花了 \$ 5'), isTrue,
          reason: 'a dollar followed by a space opens nothing, so it is prose');
    });

    test('markdown that degrades to literal text is still renderable', () {
      // Emphasis, lists, tables and an unclosed inline-code span do not
      // reinterpret what follows, so they must not force the whole reply to
      // plain text.
      expect(aiMessageRendersAsMarkdown('**加粗** 和 *斜体*'), isTrue);
      expect(aiMessageRendersAsMarkdown('- 一\n- 二'), isTrue);
      expect(aiMessageRendersAsMarkdown('| 甲 | 乙 |'), isTrue);
      expect(aiMessageRendersAsMarkdown('一个反引号 ` 而已'), isTrue);
    });
  });

  // ------------------------------------------------------------- markdown
  testWidgets('a model reply renders headings, bold, lists and a table',
      (tester) async {
    await pumpBody(tester, _richReply);

    final rendered = renderedText(tester);
    // The words are there...
    for (final word in [
      '标题一',
      '二级标题',
      '加粗',
      '斜体',
      '第一项',
      '第二项',
      '有序一',
      '有序二',
      '引用的一段话',
      '链接文本',
      '甲',
      '90',
      '乙',
      '85',
      'final x = 1;',
    ]) {
      expect(rendered, contains(word), reason: '$word must survive the render');
    }
    // ...and the markup that produced them is gone.
    expect(rendered, isNot(contains('**')), reason: 'bold markers must not show');
    expect(rendered, isNot(contains('# ')), reason: 'heading markers must not show');
    expect(rendered, isNot(contains('](')), reason: 'link syntax must not show');
    expect(rendered, isNot(contains('---')), reason: 'rules and table delimiters must not show');
    expect(rendered, isNot(contains('```')), reason: 'fence markers must not show');

    // Bold is not merely marker-free: it is painted bold.
    expect(hasBoldRun(tester, '加粗'), isTrue);
    expect(hasItalicRun(tester, '斜体'), isTrue);
  });

  // ----------------------------------------------------------------- math
  testWidgets('inline and display formulas render as math, not as text',
      (tester) async {
    await pumpBody(tester, '质量能量关系 \$E=mc^2\$ 与\n\n\$\$\n\\int_0^1 x^2 dx\n\$\$');

    final rendered = renderedText(tester);
    expect(rendered, contains('质量能量关系'), reason: 'the prose must survive');
    expect(mathWidgetCount(tester), 2,
        reason: 'one formula widget per delimiter pair, inline and display');
    expect(rendered, isNot(contains(r'$')), reason: 'no raw dollar may be left');
    expect(rendered, isNot(contains('E=mc^2')),
        reason: 'a formula rendered as math is not painted as its source');
    expect(rendered, isNot(contains(r'\int')), reason: 'no raw LaTeX may be left');
  });

  testWidgets('parenthesised and bracketed delimiters are math too',
      (tester) async {
    await pumpBody(tester, r'行内 \(a+b\) 与展示 \[c+d\] 都要渲染');

    expect(mathWidgetCount(tester), 2);
    expect(renderedText(tester), contains('都要渲染'));
  });

  // ------------------------------------------------------------ streaming
  testWidgets('a partial reply stays literal, keeps its text, and never throws',
      (tester) async {
    const partialMath = '正在计算：\n\n\$\$\nE=mc^2';
    await pumpBody(tester, partialMath);

    expect(find.byType(GptMarkdown), findsNothing,
        reason: 'an unfinished display block must not be parsed');
    expect(find.byType(SelectableText), findsOneWidget);
    final rendered = renderedText(tester);
    expect(rendered, contains('E=mc^2'), reason: 'the arrived text must be kept');
    expect(rendered, contains(r'$$'), reason: 'the fragment is shown as written');
    expect(tester.takeException(), isNull);

    const partialFence = '看代码：\n\n```dart\nfinal x = 1;';
    await pumpBody(tester, partialFence);
    expect(find.byType(GptMarkdown), findsNothing,
        reason: 'an unclosed fence must not swallow the rest as code');
    expect(renderedText(tester), contains('final x = 1;'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a half-written table renders without throwing and keeps its text',
      (tester) async {
    await pumpBody(tester, '| 名字 | 分数 |\n| 甲 | 90');

    expect(tester.takeException(), isNull);
    // Rendering mode is deliberately not asserted: a header-only table is not a
    // construct that reinterprets the rest of the message, so the guard lets it
    // through and the parser shows the rows literally. What must hold is that
    // the user can still read what arrived.
    expect(renderedText(tester), contains('甲'));
  });

  testWidgets('a half-typed span the guard lets through still shows its text',
      (tester) async {
    await pumpBody(tester, '一个反引号 ` 与半截 **加粗');

    expect(tester.takeException(), isNull);
    final rendered = renderedText(tester);
    expect(rendered, contains('一个反引号'));
    expect(rendered, contains('半截'));
  });

  testWidgets('a reply switches to markdown as soon as the construct closes',
      (tester) async {
    await pumpBody(tester, '正在计算：\n\n\$\$\nE=mc^2\n\$\$');

    expect(find.byType(GptMarkdown), findsOneWidget);
    expect(mathWidgetCount(tester), 1);
    expect(tester.takeException(), isNull);
  });

  // ------------------------------------------------- user text is literal
  testWidgets('a user message keeps its asterisks and dollars', (tester) async {
    await pumpBody(tester, r'**不加粗** 与 $x$ 与 `a*b*c`', isUser: true);

    expect(find.byType(GptMarkdown), findsNothing,
        reason: "the user's own text must never be parsed as markup");
    final rendered = renderedText(tester);
    expect(rendered, contains('**不加粗**'));
    expect(rendered, contains(r'$x$'));
    expect(rendered, contains('`a*b*c`'));
    expect(hasBoldRun(tester, '不加粗'), isFalse);
  });

  // ------------------------------------------------------------ inline code
  testWidgets('inline code is not parsed as emphasis', (tester) async {
    await pumpBody(tester, '行内 `a*b*c` 保持原样');

    expect(renderedText(tester), contains('a*b*c'),
        reason: 'the literal span must survive intact');
    expect(hasItalicRun(tester, 'b'), isFalse,
        reason: 'the asterisks inside code must not italicise');
  });

  // ---------------------------------------------------------------- theme
  group('theme', () {
    // The app's own theme builder, not a stand-in: this is the ThemeData the
    // chat page is actually rendered inside.
    final profiles = {
      Brightness.dark: ThemeProfileData.builtinDark.toThemeData(),
      Brightness.light: ThemeProfileData.builtinLight.toThemeData(),
    };

    for (final entry in profiles.entries) {
      final brightness = entry.key;
      testWidgets('markdown follows the ${brightness.name} theme',
          (tester) async {
        final theme = entry.value;
        await pumpBody(tester, _richReply, theme: theme);

        expect(renderedText(tester), contains('标题一'));

        final backgrounds = <Color>{
          for (final box in tester.widgetList<DecoratedBox>(
            find.byType(DecoratedBox),
          ))
            if (box.decoration is BoxDecoration &&
                (box.decoration as BoxDecoration).color != null)
              (box.decoration as BoxDecoration).color!,
          for (final container in tester.widgetList<Container>(
            find.byType(Container),
          ))
            if (container.color != null)
              container.color!
            else if (container.decoration is BoxDecoration &&
                (container.decoration as BoxDecoration).color != null)
              (container.decoration as BoxDecoration).color!,
        };
        // The requirement is that panels come from the scheme, not from a
        // hard-coded fill that only works on one of the two themes.
        expect(backgrounds, isNot(contains(Colors.white)));
        expect(backgrounds, isNot(contains(Colors.black)));
        expect(backgrounds, contains(theme.colorScheme.surfaceContainer),
            reason: 'the code panel is filled from the ambient ColorScheme');
      });
    }

    testWidgets('markdown follows the app text scale', (tester) async {
      await pumpBody(tester, _richReply);
      final unscaled = tester.getSize(find.byType(GptMarkdown)).height;

      await pumpBody(
        tester,
        _richReply,
        textScaler: const TextScaler.linear(1.5),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(GptMarkdown)).height,
          greaterThan(unscaled),
          reason: 'the same reply must take more room at a larger text scale');
    });
  });

  // -------------------------------------------------- the streaming chat
  testWidgets('the chat page itself shows a streamed reply literally and then '
      'as markdown', (tester) async {
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

    // Two pieces with a gate between them: the screen can be inspected while
    // the second half is still in flight, which is what "streaming" means here.
    final adapter = _GatedAdapter(
      first: '正在计算：\n\n\$\$\nE=mc^2',
      rest: '\n\$\$',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          modelAdapterProvider.overrideWithValue(adapter),
          // The installed-skill directory is on the real filesystem and the loop
          // reads it before every turn. Stubbing it out keeps the test about the
          // rendering, and keeps the turn off the disk.
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

    await tester.enterText(find.byType(TextField).last, '算一下');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.send));

    // `pumpAndSettle` is unusable while the turn runs: the progress bar under
    // the conversation is an indeterminate animation and never settles.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // ------------------------------- while the display block is still open
    expect(find.byType(GptMarkdown), findsNothing,
        reason: 'the half-arrived reply must not be parsed');
    final midStream = renderedText(tester);
    expect(midStream, contains('E=mc^2'), reason: 'the partial text is visible');
    expect(midStream, contains(r'$$'));
    expect(tester.takeException(), isNull);

    // ------------------------------------------- and once the block closes
    adapter.gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(GptMarkdown), findsOneWidget,
        reason: 'the finished reply is markdown');
    expect(mathWidgetCount(tester), 1);
    expect(renderedText(tester), isNot(contains('E=mc^2')),
        reason: 'the formula is painted, not written out');
    // The user's message is still there, literally.
    expect(renderedText(tester), contains('算一下'));

    await db.close();
  });
}

/// A model whose reply is released in two pieces, with a gate the test opens.
class _GatedAdapter implements ModelAdapter {
  _GatedAdapter({required this.first, required this.rest});

  final String first;
  final String rest;

  /// Completed by the test to release the second half of the answer.
  final Completer<void> gate = Completer<void>();

  @override
  Stream<ModelEvent> runTurn({
    required List<ChatMessage> messages,
    required List<ModelToolSpec> tools,
  }) async* {
    yield ModelTextDelta(first);
    await gate.future;
    yield ModelTextDelta(rest);
    yield const ModelTurnDone(finishReason: 'stop');
  }
}

/// A skill store with nothing installed, answering from memory.
///
/// The real store reads the app support directory, which the agent loop would
/// otherwise have to wait on before it ever reaches the model.
class _NoSkills extends SkillStore {
  @override
  Future<List<InstalledSkill>> enabled() async => const [];
}
