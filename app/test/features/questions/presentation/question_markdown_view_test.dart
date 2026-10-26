import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/presentation/question_detail_page.dart';
import 'package:furnace/features/questions/presentation/question_markdown_view.dart';
import 'package:furnace/features/questions/presentation/question_media_view.dart';
import 'package:furnace/l10n/app_localizations.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import 'support/question_media_fakes.dart';

void main() {
  group('questionTextFormatIsMarkdown', () {
    test('只有 markdown 才切到整段 Markdown 口径', () {
      expect(questionTextFormatIsMarkdown('markdown'), isTrue);
      expect(questionTextFormatIsMarkdown(' Markdown '), isTrue);
      expect(questionTextFormatIsMarkdown('MARKDOWN'), isTrue);
      expect(questionTextFormatIsMarkdown(null), isFalse);
      expect(questionTextFormatIsMarkdown(''), isFalse);
      expect(questionTextFormatIsMarkdown('   '), isFalse);
      expect(questionTextFormatIsMarkdown('plain'), isFalse);
      expect(questionTextFormatIsMarkdown('markdownish'), isFalse);
    });
  });

  group('questionMarkdownRendersAsMarkdown', () {
    test('完整文档（标题/列表/表格/代码块/公式）可以渲染', () {
      const text = '# 题目\n\n'
          r'已知 $x^2-5x+6=0$，求两根。'
          '\n\n> 提示：先因式分解\n\n'
          '- 列表一\n'
          '- 列表二\n\n'
          '| 项 | 值 |\n'
          '| --- | --- |\n'
          '| 和 | 5 |\n\n'
          '```dart\n'
          'final x = 1;\n'
          '```\n\n'
          r'$$t_2t_3<4$$';
      expect(questionMarkdownRendersAsMarkdown(text), isTrue);
    });

    test('未闭合的代码栅栏退回纯文本', () {
      expect(
        questionMarkdownRendersAsMarkdown('解析：\n\n```dart\nfinal x = 1;'),
        isFalse,
      );
      expect(
        questionMarkdownRendersAsMarkdown('解析：\n\n~~~\nfinal x = 1;'),
        isFalse,
      );
      // ``` 与 ~~~ 各自计数，不能互相闭合。
      expect(questionMarkdownRendersAsMarkdown('```\n~~~\n'), isFalse);
    });

    test('未闭合的公式定界符退回纯文本', () {
      expect(
        questionMarkdownRendersAsMarkdown('计算：\n\n'
            r'$$'
            '\n'
            'E=mc^2'),
        isFalse,
      );
      expect(questionMarkdownRendersAsMarkdown(r'求 $x+1'), isFalse);
      expect(questionMarkdownRendersAsMarkdown(r'求 $x+1 的值'), isFalse);
      expect(questionMarkdownRendersAsMarkdown(r'花费 5 元$'), isFalse);
      expect(questionMarkdownRendersAsMarkdown(r'$'), isFalse);
    });

    test('闭合公式、转义美元与金额里的 \$ 判断正确', () {
      expect(questionMarkdownRendersAsMarkdown(r'已知 $x^2=4$，求 x。'), isTrue);
      expect(questionMarkdownRendersAsMarkdown(r'$$\frac{1}{2}$$'), isTrue);
      expect(questionMarkdownRendersAsMarkdown(r'价格是 \$5，不是公式'), isTrue);
      expect(questionMarkdownRendersAsMarkdown(r'单价 $ 5 元，共 $ 10 元'), isTrue);
      expect(questionMarkdownRendersAsMarkdown(r'花了 $5 到 $9。'), isFalse);
    });

    test('只写一半的强调/列表/行内代码不算不完整', () {
      expect(questionMarkdownRendersAsMarkdown('**加粗'), isTrue);
      expect(questionMarkdownRendersAsMarkdown('- 第一项\n- 第二项'), isTrue);
      expect(questionMarkdownRendersAsMarkdown('`code'), isTrue);
      expect(questionMarkdownRendersAsMarkdown(''), isTrue);
    });
  });

  group('MarkdownQuestionText', () {
    testWidgets('markdown=false 与 QuestionRichText 一致', (tester) async {
      const text = '已知 x^2-5x+6=0，求两根之和。';
      await pumpQuestionText(tester, const MarkdownQuestionText(text: text));
      expect(find.byType(QuestionRichText), findsOneWidget);
      expect(find.byType(GptMarkdown), findsNothing);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(renderedText(tester), contains(text));
    });

    testWidgets('markdown=false 不解析 Markdown 标记', (tester) async {
      const text = '# 不是标题，*也不是强调*';
      await pumpQuestionText(tester, const MarkdownQuestionText(text: text));
      expect(find.byType(GptMarkdown), findsNothing);
      expect(renderedText(tester), contains('# 不是标题，*也不是强调*'));
    });

    testWidgets('markdown=false 的行内公式仍交给渲染器', (tester) async {
      await pumpQuestionText(
        tester,
        const MarkdownQuestionText(text: r'已知 $x^2=4$，求 x。'),
      );
      expect(find.byType(QuestionRichText), findsOneWidget);
      expect(find.byType(GptMarkdown), findsOneWidget);
      expect(renderedText(tester), isNot(contains(r'$')));
      expect(mathWidgetCount(tester), 1);
    });

    testWidgets('markdown=false 透传样式与对齐', (tester) async {
      const style = TextStyle(fontSize: 18);
      await pumpQuestionText(
        tester,
        const MarkdownQuestionText(
          text: '纯文本',
          style: style,
          textAlign: TextAlign.end,
        ),
      );
      final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(selectable.data, '纯文本');
      expect(selectable.style, style);
      expect(selectable.textAlign, TextAlign.end);
    });

    testWidgets('markdown=true 渲染标题、列表与公式', (tester) async {
      const text = '# 题目\n\n'
          r'已知 $x^2=4$，求 $x$。'
          '\n\n1. 移项\n2. 开方\n\n'
          r'$$'
          '\n'
          't_2t_3<4'
          '\n'
          r'$$'
          '\n\n- 检验\n- 回代';
      await pumpQuestionText(
        tester,
        const MarkdownQuestionText(text: text, markdown: true),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(GptMarkdown), findsOneWidget);
      expect(find.byType(SelectionArea), findsWidgets);
      final plain = renderedText(tester);
      expect(plain, contains('题目'));
      expect(plain, contains('移项'));
      expect(plain, contains('开方'));
      expect(plain, contains('检验'));
      expect(plain, contains('回代'));
      expect(plain, isNot(contains('#')));
      expect(plain, isNot(contains(r'$')));
      expect(mathWidgetCount(tester), 3);
    });

    testWidgets('markdown=true 透传样式与对齐并打开美元公式', (tester) async {
      const style = TextStyle(fontSize: 18);
      await pumpQuestionText(
        tester,
        const MarkdownQuestionText(
          text: '## 标题',
          markdown: true,
          style: style,
          textAlign: TextAlign.center,
        ),
      );
      final markdown = tester.widget<GptMarkdown>(find.byType(GptMarkdown));
      expect(markdown.data, '## 标题');
      expect(markdown.style, style);
      expect(markdown.textAlign, TextAlign.center);
      expect(markdown.useDollarSignsForLatex, isTrue);
      expect(markdown.styleSheet?.link?.color, isNotNull);
    });

    testWidgets('markdown=true 在未闭合代码栅栏时退回可选中的原文', (tester) async {
      const text = '解析：\n\n```dart\nfinal x = 1;';
      await pumpQuestionText(
        tester,
        const MarkdownQuestionText(text: text, markdown: true),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(GptMarkdown), findsNothing);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        text,
      );
    });

    testWidgets('markdown=true 在未闭合 \$\$ 时退回可选中的原文', (tester) async {
      const text = '计算：\n\n'
          r'$$'
          '\n'
          'E=mc^2';
      await pumpQuestionText(
        tester,
        const MarkdownQuestionText(text: text, markdown: true),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(GptMarkdown), findsNothing);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        text,
      );
    });

    testWidgets('markdown=true 空题干渲染不崩', (tester) async {
      await pumpQuestionText(
        tester,
        const MarkdownQuestionText(text: '', markdown: true),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(GptMarkdown), findsOneWidget);
    });
  });

  group('题目详情页接线（textFormat）', () {
    testWidgets('markdown 题：题干、选项、答案都整段渲染', (tester) async {
      final database = _newMarkdownDatabase();
      final question = await _seedMarkdownQuestion(
        database,
        stem: '# 已知条件\n\n'
            r'已知 $x^2-5x+6=0$，求两根之和。'
            '\n\n- 提示一\n- 提示二',
        answer: r'两根之和为 $5$。',
        solution: '1. 因式分解\n2. 求和',
        textFormat: 'markdown',
        options: const <QuestionOptionDraft>[
          QuestionOptionDraft(label: 'A', content: '**3**', sortOrder: 0),
          QuestionOptionDraft(
            label: 'B',
            content: r'$5$',
            isCorrect: true,
            sortOrder: 1,
          ),
        ],
      );
      await _pumpDetailPage(tester, database, question.id);
      expect(find.byType(GptMarkdown), findsWidgets);
      final stemText = tester.widget<MarkdownQuestionText>(
        find.descendant(
          of: find.byKey(questionStemImagesKey),
          matching: find.byType(MarkdownQuestionText),
        ),
      );
      expect(stemText.markdown, isTrue);
      expect(stemText.text, contains(r'$x^2-5x+6=0$'));
      final stemRendered = _renderedWithin(
        tester,
        find.byKey(questionStemImagesKey),
      );
      expect(stemRendered, contains('已知条件'));
      expect(stemRendered, contains('提示一'));
      // 标记与公式定界符都被渲染掉，不能以源码形式留在题干里。
      expect(stemRendered, isNot(contains('#')));
      expect(stemRendered, isNot(contains(r'$')));
      final pageRendered = renderedText(tester);
      expect(pageRendered, contains('因式分解'));
      expect(pageRendered, contains('两根之和为'));
      expect(pageRendered, isNot(contains('**3**')));
      expect(mathWidgetCount(tester), greaterThanOrEqualTo(2));
    });

    testWidgets('plain 题（缺省）：Markdown 标记按原样显示', (tester) async {
      final database = _newMarkdownDatabase();
      final question = await _seedMarkdownQuestion(
        database,
        stem: '# 不是标题\n\n**加粗** 与 x^2',
        answer: '5',
        textFormat: 'plain',
      );
      await _pumpDetailPage(tester, database, question.id);
      expect(find.byType(GptMarkdown), findsNothing);
      final stemText = tester.widget<MarkdownQuestionText>(
        find.descendant(
          of: find.byKey(questionStemImagesKey),
          matching: find.byType(MarkdownQuestionText),
        ),
      );
      expect(stemText.markdown, isFalse);
      final stemRendered = _renderedWithin(
        tester,
        find.byKey(questionStemImagesKey),
      );
      expect(stemRendered, contains('# 不是标题'));
      expect(stemRendered, contains('**加粗**'));
    });
  });

  group('整卡截图（fullcard_ 前缀）', () {
    testWidgets('fullcard_ 前缀：不看尺寸直接按整卡截图排版', (tester) async {
      final database = _newMarkdownDatabase();
      final question = await _seedMarkdownQuestion(
        database,
        stem: '如图所示。［图1］请写出过程。',
        answer: '5',
      );
      final mediaStore = FakeQuestionMediaStore(database: database);
      mediaStore.seed(
        questionId: question.id,
        fileName: 'fullcard_10-123456.png',
        bytes: tinyPngBytes,
      );
      await _pumpDetailPage(
        tester,
        database,
        question.id,
        mediaStore: mediaStore,
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(QuestionDetailPage)),
      );
      final title = find.text(l10n.questionDetailOriginalCardImage);
      final imageFinder = find.descendant(
        of: find.byKey(questionStemImagesKey),
        matching: find.byType(QuestionInlineImage),
      );
      // 图片清单走异步 provider，要等它解析完再断言。
      await _waitForCount(tester, imageFinder, 1);
      expect(title, findsOneWidget);
      expect(
        tester.getTopLeft(title).dy,
        lessThan(tester.getTopLeft(imageFinder).dy),
      );
      final stemRendered = _renderedWithin(
        tester,
        find.byKey(questionStemImagesKey),
      );
      expect(stemRendered, contains('如图所示'));
      expect(stemRendered, contains('…'));
      expect(stemRendered, isNot(contains('［图1］')));
    });

    testWidgets('普通前缀 + 小图：仍按占位内联，不出现原题整图标题', (tester) async {
      final database = _newMarkdownDatabase();
      final question = await _seedMarkdownQuestion(
        database,
        stem: '如图所示。［图1］请写出过程。',
        answer: '5',
      );
      final mediaStore = FakeQuestionMediaStore(database: database);
      mediaStore.seed(
        questionId: question.id,
        fileName: 'stem_10-123456.png',
        bytes: tinyPngBytes,
      );
      await _pumpDetailPage(
        tester,
        database,
        question.id,
        mediaStore: mediaStore,
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(QuestionDetailPage)),
      );
      expect(find.text(l10n.questionDetailOriginalCardImage), findsNothing);
      final imageFinder = find.descendant(
        of: find.byKey(questionStemImagesKey),
        matching: find.byType(QuestionInlineImage),
      );
      await _waitForCount(tester, imageFinder, 1);
      final stemRendered = _renderedWithin(
        tester,
        find.byKey(questionStemImagesKey),
      );
      expect(stemRendered, contains('如图所示'));
      expect(stemRendered, contains('请写出过程'));
      expect(stemRendered, isNot(contains('［图1］')));
    });
  });
}

Future<void> pumpQuestionText(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 把树里所有文字（Text/EditableText/RichText）拼起来，用于断言渲染后的正文。
String renderedText(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final widget in tester.allWidgets) {
    if (widget is Text) {
      buffer.writeln(widget.data ?? widget.textSpan?.toPlainText() ?? '');
    } else if (widget is EditableText) {
      buffer.writeln(widget.controller.text);
    } else if (widget is RichText) {
      buffer.writeln(widget.text.toPlainText(includePlaceholders: false));
    }
  }
  return buffer.toString();
}

/// val_latex_flutter 的公式 widget（传递依赖，不直接 import 其包）。
int mathWidgetCount(WidgetTester tester) => tester
    .widgetList(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'Math',
        skipOffstage: false,
      ),
    )
    .length;

/// 每个用例自己建一个内存库并关掉。
AppDatabase _newMarkdownDatabase() {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  return database;
}

Future<Question> _seedMarkdownQuestion(
  AppDatabase database, {
  required String stem,
  String? answer,
  String? solution,
  String textFormat = 'plain',
  List<QuestionOptionDraft> options = const <QuestionOptionDraft>[
    QuestionOptionDraft(label: 'A', content: '3', sortOrder: 0),
    QuestionOptionDraft(
      label: 'B',
      content: '5',
      isCorrect: true,
      sortOrder: 1,
    ),
  ],
}) async {
  final result = await QuestionRepository(database).ingest(
    QuestionDraft(
      stem: stem,
      answer: answer,
      solution: solution,
      subjectKey: 'math',
      questionType: 'single_choice',
      sourceLevel: 'gaokao',
      year: 2024,
      region: '江苏',
      difficulty: 4,
      textFormat: textFormat,
      options: options,
    ),
  );
  return result.question;
}

Future<void> _pumpDetailPage(
  WidgetTester tester,
  AppDatabase database,
  String questionId, {
  FakeQuestionMediaStore? mediaStore,
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        modelAdapterProvider.overrideWithValue(null),
        questionMediaStoreProvider.overrideWithValue(
          mediaStore ?? FakeQuestionMediaStore(database: database),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: QuestionDetailPage(questionId: questionId),
      ),
    ),
  );
  // 页面里有不定值转圈动画，不能用 pumpAndSettle；推进到没有进度条为止。
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    final spinning =
        find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
            find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    if (!spinning) {
      break;
    }
  }
}

/// 等某个 finder 命中指定数量（图片清单/字节都是异步 provider）。
Future<void> _waitForCount(
  WidgetTester tester,
  Finder finder,
  int count, {
  int rounds = 60,
}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().length == count) {
      return;
    }
  }
  fail('等了 6 秒也没等到 $count 个 $finder');
}

/// 把某个子树里的文字拼起来（题干段落是 RichText，不能只用 find.text）。
String _renderedWithin(WidgetTester tester, Finder finder) {
  final buffer = StringBuffer();
  void collect(Element element) {
    final widget = element.widget;
    if (widget is Text) {
      buffer.writeln(widget.data ?? widget.textSpan?.toPlainText() ?? '');
    } else if (widget is EditableText) {
      // plain 分支是 SelectableText，正文在 EditableText 的 controller 里。
      buffer.writeln(widget.controller.text);
    } else if (widget is RichText) {
      buffer.writeln(widget.text.toPlainText(includePlaceholders: false));
    }
    element.visitChildren(collect);
  }

  for (final element in finder.evaluate()) {
    collect(element);
  }
  return buffer.toString();
}
