import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/features/anki/presentation/review_card_media.dart';
import 'package:furnace/features/anki/presentation/review_page.dart';
import 'package:furnace/features/anki/presentation/review_question_text.dart';
import 'package:furnace/l10n/app_localizations.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// 2×2 合法 PNG：让 `Image.memory` 真的解码。
final Uint8List tinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGO8pKHBwMDAxAAGAA5sASaNUVj9AAAAAElFTkSuQmCC',
);

/// task-101：闪存卡复习页的题干与答案都支持 Markdown / LaTeX / 图片；
/// 旧纯文本卡逐字不回归。
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> waitForFinder(
    WidgetTester tester,
    Finder finder, {
    int rounds = 50,
  }) async {
    for (var i = 0; i < rounds; i++) {
      if (finder.evaluate().isNotEmpty) {
        return;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    fail('等了 5 秒也没等到：$finder');
  }

  Future<void> pumpReview(
    WidgetTester tester,
    AppDatabase db, {
    List<Override> extra = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ...extra,
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ReviewPage()),
        ),
      ),
    );
    await settle(tester);
  }

  Future<(AppDatabase, AnkiRepository)> openDatabase() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    return (db, AnkiRepository(db));
  }

  Future<CardTemplate> addCard(
    AnkiRepository anki, {
    required String question,
    required String answer,
    String type = 'fill_blank',
    List<String> options = const [],
  }) async {
    final point = await anki.createKnowledgePoint(
      title: '反应原理',
      content: '反应焓变与生成物总能量有关。',
    );
    final template = await anki.createTemplate(
      knowledgePointId: point.id,
      type: type,
      question: question,
      answer: answer,
      options: options,
    );
    await anki.getOrCreateCardState(template.id);
    return template;
  }

  /// 页面里所有文字（含 RichText）拼起来，用来断言语法字符没有被原样漏出。
  String allRenderedText(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
      .join('\n');

  group('题干', () {
    testWidgets('标题/列表按 Markdown 渲染，不留下 # 与列表符号', (tester) async {
      final (db, anki) = await openDatabase();
      await addCard(
        anki,
        question: '# 反应原理\n\n- 甲\n- 乙',
        answer: '无关',
      );

      await pumpReview(tester, db);

      expect(find.byType(GptMarkdown), findsWidgets);
      expect(find.textContaining('# 反应原理', findRichText: true), findsNothing);
      expect(find.textContaining('- 甲', findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('加粗与 LaTeX 被排出来，不留下 ** 与 \$', (tester) async {
      final (db, anki) = await openDatabase();
      await addCard(
        anki,
        question: r'**重点**：$\Delta H$ 是焓变。',
        answer: '无关',
      );

      await pumpReview(tester, db);

      expect(find.byType(GptMarkdown), findsWidgets);
      final text = allRenderedText(tester);
      expect(text, isNot(contains('**')));
      expect(text, isNot(contains(r'$')));
    });

    testWidgets('旧纯文本题干的渲染不变：仍是可选择的纯文本', (tester) async {
      final (db, anki) = await openDatabase();
      await addCard(
        anki,
        question: '光合作用的场所是？',
        answer: '叶绿体',
      );

      await pumpReview(tester, db);

      expect(find.byType(GptMarkdown), findsNothing);
      expect(find.text('光合作用的场所是？'), findsOneWidget);
    });
  });

  group('答案', () {
    testWidgets('Markdown 答案走富文本，标签「答案：」保留', (tester) async {
      final (db, anki) = await openDatabase();
      await addCard(
        anki,
        question: '普通题干',
        answer: '## 结论\n\n' r'**答案**是 $x=1$。',
      );

      await pumpReview(tester, db);
      await tester.tap(find.byTooltip('显示答案'));
      await settle(tester);

      expect(find.text('答案: '), findsOneWidget);
      expect(find.byType(GptMarkdown), findsWidgets);
      final text = allRenderedText(tester);
      expect(text, isNot(contains('**')));
      expect(text, isNot(contains(r'$')));
      expect(find.textContaining('结论', findRichText: true), findsOneWidget);
    });

    testWidgets('旧纯文本答案仍是单行 Text，逐字与改造前一致', (tester) async {
      final (db, anki) = await openDatabase();
      await addCard(
        anki,
        question: '光合作用的场所是？',
        answer: '叶绿体',
      );

      await pumpReview(tester, db);
      await tester.tap(find.byTooltip('显示答案'));
      await settle(tester);

      expect(find.text('答案: 叶绿体'), findsOneWidget);
    });
  });

  group('图片', () {
    testWidgets('题干里的本地图片路径能显示图片，路径本身不再出现', (tester) async {
      final (db, anki) = await openDatabase();
      const path = 'E:/imgs/a.png';
      await addCard(
        anki,
        question: '如图 ![示意图]($path) 所示。',
        answer: '无关',
      );

      await pumpReview(
        tester,
        db,
        extra: [
          reviewCardImageBytesProvider.overrideWith(
            (ref, text) async => text.contains(path)
                ? <String, ReviewQuestionImage>{
                    path: ReviewQuestionImage(bytes: tinyPngBytes),
                  }
                : const <String, ReviewQuestionImage>{},
          ),
        ],
      );

      await waitForFinder(tester, find.byKey(reviewQuestionImageKey(0)));
      expect(find.byKey(reviewQuestionImageKey(0)), findsOneWidget);
      expect(find.textContaining('![示意图]'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('答案里的本地图片路径也能显示', (tester) async {
      final (db, anki) = await openDatabase();
      const path = 'E:/imgs/b.png';
      await addCard(
        anki,
        question: '普通题干',
        answer: '见图 ![答案图]($path) 处。',
      );

      await pumpReview(
        tester,
        db,
        extra: [
          reviewCardImageBytesProvider.overrideWith(
            (ref, text) async => text.contains(path)
                ? <String, ReviewQuestionImage>{
                    path: ReviewQuestionImage(bytes: tinyPngBytes),
                  }
                : const <String, ReviewQuestionImage>{},
          ),
        ],
      );

      await tester.tap(find.byTooltip('显示答案'));
      await settle(tester);
      await waitForFinder(tester, find.byKey(reviewQuestionImageKey(0)));
      expect(find.byKey(reviewQuestionImageKey(0)), findsOneWidget);
    });

    testWidgets('图片读不到时正常降级：保留字面文本、不崩、不联网', (tester) async {
      final (db, anki) = await openDatabase();
      await addCard(
        anki,
        question: '见图 ![示意图](E:/missing/a.png) 处。',
        answer: '无关',
      );

      await pumpReview(
        tester,
        db,
        extra: [
          reviewCardImageBytesProvider.overrideWith(
            (ref, text) async => const <String, ReviewQuestionImage>{},
          ),
        ],
      );

      expect(find.byType(Image), findsNothing);
      expect(
        find.textContaining('E:/missing/a.png', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
