/// 题库卡片化 + 题干富文本的验收测试（2026-11-15 用户反馈）。
///
/// 钉住四件事：
///  1. 题库是**设置页同款卡片**（Card + 圆角 16 + 0 高度 + surfaceContainerLow），
///     题干摘要就在卡片上；
///  2. 题干里的 `$…$` 由统一 `MarkdownRenderer` 排成真公式（卡片上不残留 `$`）；
///  3. 填空的 `______` 在卡片/详情页里**可见**，不会被 Markdown 吃掉；没有填空的
///     解答题也不会凭空多出下划线；
///  4. 题干/选项里的「［图N］」公式图在详情页渲染成行内图片，不残留占位文字
///     （化学 Q15 那类多图题）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/data/question_media_store.dart';
import 'package:furnace/features/questions/presentation/question_bank_page.dart';
import 'package:furnace/features/questions/presentation/question_blank_view.dart';
import 'package:furnace/features/questions/presentation/question_detail_page.dart';
import 'package:furnace/features/questions/presentation/question_media_view.dart';
import 'package:furnace/l10n/app_localizations.dart';

import 'support/question_media_fakes.dart';

/// 40×100 的合法 PNG：行内公式图的替身。
final Uint8List inlineFormulaPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAACgAAABkCAIAAAB7BuUtAAAAm0lEQVR4nO3QQQkDQQDF0Gm0'
  'jH9FK6bnXwFZKHkGAjnnJZ9zzvM8cvXey3kJhS1opR+FNXipVViDl1qFNXipVViDl1qFNXip'
  'VViDl1qFNXipVViDl1qFNXipVViDl1qFNXipVViDl1qFNXipVViDl1qFNXipVViDl1qFNXip'
  'VViDl1qFNXipVViDl1qF/3/1ecsXcf0DxJqX9yUAAAAASUVORK5CYII=',
);

/// 200×100 的合法 PNG：独立成行的插图替身。
final Uint8List figurePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAMgAAABkCAIAAABM5OhcAAABI0lEQVR4nO3SQQ2AQBAEwQUt'
  'yDm5yEEMKjoEqBIwmUfPQGCbmfM6i2l+ax1rf/oD3yQsEsIiISwSwiIhLBLCIiEsEsIiISwSwi'
  'IhLBLCIiEsEsIiISwSwiIhLBLCIiEsEsIiISwSwiIhLBLCIiEsEsIiISwSwiIhLBLCIiEsEsIi'
  'ISwSwiIhLBLCIiEsEsIiISwSwiIhLBLCIiEsEsIiISwSwiIhLBLCIiEsEsIiISwSwiIhLBLCIi'
  'EsEsIiISwSwiIhLBLCIiEsEsIiISwSwiIhLBLCIiEsEsIiISwSwiIhLBLCIiEsEsIiISwSwiIh'
  'LBLCIiEsEsIiISwSwiIhLBLCIiEsEsIiISwSwiIhLBLCIiEsEsIiISwSwiIhLBLCIiEsEsIiIS'
  'wSwiIhLBLCIiEsEsIiISwSwiIhLBLCIiEsEsIiISwSwiIhLBLCIiEsEsIiISwSwiIhLBLCIuY'
  '1bnNJA8S0rJA8AAAAAElFTkSuQmCC',
);

late AppLocalizations _zh;

void main() {
  setUpAll(() async {
    _zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  group('题库卡片', () {
    testWidgets('卡片是设置页同款，且题干摘要在卡片上（不是平文本）', (tester) async {
      final db = _newDatabase();
      await _seed(
        db,
        stem: r'求函数 $f(x)=x^2-5x+6$ 在区间 $[0,4]$ 上的最小值',
      );

      await _pumpBank(tester, db, size: const Size(1280, 900));

      expect(find.byType(Card), findsOneWidget);
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.elevation, questionBankCardElevation);
      expect(
        (card.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(questionBankCardRadius),
      );
      // 卡片上的题干摘要：公式真的排出来了（有 Math 控件），定界符不残留。
      expect(_mathWidgetCount(tester), 2);
      final cardText = _cardText(tester);
      expect(cardText, contains('求函数'));
      expect(cardText, isNot(contains(r'$')));
      expect(cardText, isNot(contains(r'\$')));
    });

    testWidgets('填空空位在卡片上是下划线组件（不是文字 ______）', (tester) async {
      final db = _newDatabase();
      await _seed(db, stem: r'宏观上 $\Delta H=$ ______。');

      await _pumpBank(tester, db);

      expect(find.byType(QuestionBlankUnderline), findsOneWidget);
      final cardText = _cardText(tester);
      expect(cardText, isNot(contains('______')));
      expect(cardText, isNot(contains(r'\_')));
      expect(_mathWidgetCount(tester), 1);
    });

    testWidgets('纯文本（非 Markdown）的填空空位也是下划线组件', (tester) async {
      final db = _newDatabase();
      await _seed(db, stem: '该反应在常温下 ______。', textFormat: 'plain');

      await _pumpBank(tester, db);

      expect(find.byType(QuestionBlankUnderline), findsOneWidget);
      expect(_cardText(tester), isNot(contains('______')));
    });

    testWidgets('解答题不凭空多出下划线', (tester) async {
      final db = _newDatabase();
      await _seed(
        db,
        stem: '请说明该反应速率随温度变化的趋势，并解释原因。',
        questionType: 'solution',
      );

      await _pumpBank(tester, db);

      final cardText = _cardText(tester);
      expect(cardText, contains('请说明该反应速率'));
      expect(cardText, isNot(contains('__')));
    });

    testWidgets('没有题名时卡片显示「未命名」+ 题干摘要', (tester) async {
      final db = _newDatabase();
      await _seed(db, stem: '求小球的加速度');

      await _pumpBank(tester, db);

      expect(find.text(_zh.questionTitleUntitled), findsOneWidget);
      expect(_cardText(tester), contains('求小球的加速度'));
    });

    testWidgets('空题库：没有卡片，只有空态与两个入口', (tester) async {
      final db = _newDatabase();
      await _pumpBank(tester, db);

      expect(find.byType(Card), findsNothing);
      expect(find.text(_zh.questionBankEmpty), findsOneWidget);
      expect(find.text(_zh.questionPaperTitle), findsOneWidget);
    });

    testWidgets('卡片上没有开发字段（content_package / 内部 id / 入库体检）',
        (tester) async {
      final db = _newDatabase();
      final question = await _seed(
        db,
        stem: '学生看到的题干',
        origin: 'content_package',
        state: 'structured',
      );

      await _pumpBank(tester, db);

      final cardText = _cardText(tester);
      for (final forbidden in <String>[
        'content_package',
        'structured',
        'ai_quality',
        question.id,
      ]) {
        expect(cardText, isNot(contains(forbidden)));
      }
    });
  });

  group('详情页：题干/选项里的图片占位', () {
    testWidgets('多图题：［图N］ 渲染为行内图片，不残留占位文字', (tester) async {
      final db = _newDatabase();
      final mediaStore = FakeQuestionMediaStore(database: db);
      final question = await _seed(
        db,
        stem: '加入［图1］溶液，结果如图。\n［图3］',
        options: const <QuestionOptionDraft>[
          QuestionOptionDraft(
            label: 'A',
            content: '丁线所示物种为［图2］',
            sortOrder: 0,
          ),
          QuestionOptionDraft(
            label: 'B',
            content: '调节［图1］时',
            isCorrect: true,
            sortOrder: 1,
          ),
        ],
      );
      await _seedImage(
        db,
        mediaStore,
        questionId: question.id,
        fileName: 'q_img01.png',
        bytes: inlineFormulaPng,
        sortOrder: 0,
      );
      await _seedImage(
        db,
        mediaStore,
        questionId: question.id,
        fileName: 'q_img02.png',
        bytes: inlineFormulaPng,
        sortOrder: 1,
      );
      await _seedImage(
        db,
        mediaStore,
        questionId: question.id,
        fileName: 'q_img03.png',
        bytes: figurePng,
        sortOrder: 2,
      );

      await _pumpDetail(tester, db, question.id, mediaStore: mediaStore);
      await _waitForImages(tester);

      // 题干 + 两个选项里的 4 处占位都变成了图片。
      expect(find.byType(Image), findsNWidgets(4));
      final pageText = _renderedText(tester);
      expect(pageText, isNot(contains('［图')));
      // 独立成行的插图（图3）比行内公式图（图1/图2）大。
      final stemImages = tester
          .widgetList<Image>(
            find.descendant(
              of: find.byKey(questionStemImagesKey),
              matching: find.byType(Image),
            ),
          )
          .toList(growable: false);
      expect(stemImages, hasLength(2));
      final figureHeight = tester
          .getSize(find.byKey(const ValueKey<String>('question-inline-image-2')))
          .height;
      // 图1 在题干和选项 B 里各出现一次：同一张图两处渲染。
      final inlineHeight = tester
          .getSize(
            find
                .byKey(const ValueKey<String>('question-inline-image-0'))
                .first,
          )
          .height;
      expect(figureHeight, greaterThan(inlineHeight));
      expect(inlineHeight, lessThan(40));
      expect(figureHeight, greaterThanOrEqualTo(100));
    });

    testWidgets('图片字节读不出来时不崩，占位不吞字', (tester) async {
      final db = _newDatabase();
      final mediaStore = FakeQuestionMediaStore(database: db);
      final question = await _seed(
        db,
        stem: '加入［图1］溶液。\n［图2］',
      );
      await _seedImage(
        db,
        mediaStore,
        questionId: question.id,
        fileName: 'q_img01.png',
        bytes: inlineFormulaPng,
      );
      await _seedImage(
        db,
        mediaStore,
        questionId: question.id,
        fileName: 'q_img02.png',
        bytes: figurePng,
      );
      // 第二张图的字节丢了：清单还在。
      mediaStore.removeBytes(
        (await mediaStore.list(question.id, role: QuestionImageRole.stem)).last,
      );

      await _pumpDetail(tester, db, question.id, mediaStore: mediaStore);
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(_renderedText(tester), contains('加入'));
      expect(_renderedText(tester), contains('溶液。'));
    });
  });

  group('详情页：选项排布', () {
    testWidgets('短选项排两列：A/B 同行、C/D 同行，答案标记与自测选择都在',
        (tester) async {
      final db = _newDatabase();
      final question = await _seed(
        db,
        stem: '下列说法正确的是（　　）',
        options: const <QuestionOptionDraft>[
          QuestionOptionDraft(label: 'A', content: '增大', sortOrder: 0),
          QuestionOptionDraft(
            label: 'B',
            content: '减小',
            isCorrect: true,
            sortOrder: 1,
          ),
          QuestionOptionDraft(label: 'C', content: '不变', sortOrder: 2),
          QuestionOptionDraft(label: 'D', content: '无法确定', sortOrder: 3),
        ],
      );

      await _pumpDetail(tester, db, question.id, size: const Size(1280, 1600));

      double dy(String label) => tester
          .getTopLeft(find.byKey(questionDetailOptionCellKey(label)))
          .dy;
      double dx(String label) => tester
          .getTopLeft(find.byKey(questionDetailOptionCellKey(label)))
          .dx;
      // 两列：A 与 B 同一行，C 与 D 同一行；C 在 A 下面。
      expect(dy('A'), dy('B'));
      expect(dy('C'), dy('D'));
      expect(dy('C'), greaterThan(dy('A')));
      expect(dx('A'), lessThan(dx('B')));
      // 正确答案标记没丢。
      expect(find.text(_zh.questionDetailCorrectOption), findsOneWidget);

      // 自测：切到勾选态后每个选项仍可点选，选中的是被点的那一个。
      await tester.tap(find.byKey(questionSelfTestToggleKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(questionSelfTestOptionKey('A')));
      await tester.pumpAndSettle();
      final checkbox = tester.widget<Checkbox>(
        find.descendant(
          of: find.byKey(questionSelfTestOptionKey('A')),
          matching: find.byType(Checkbox),
        ),
      );
      expect(checkbox.value, isTrue);
    });

    testWidgets('长选项保持单列：一行一个', (tester) async {
      final db = _newDatabase();
      final question = await _seed(
        db,
        stem: '关于该实验，下列说法正确的是（　　）',
        options: const <QuestionOptionDraft>[
          QuestionOptionDraft(
            label: 'A',
            content: '常温下该反应可以自发进行，是因为生成物的总能量低于反应物',
            sortOrder: 0,
          ),
          QuestionOptionDraft(
            label: 'B',
            content: '升高温度会同时加快正逆反应速率，平衡不发生移动',
            isCorrect: true,
            sortOrder: 1,
          ),
          QuestionOptionDraft(
            label: 'C',
            content: '加入催化剂只能改变反应速率，不能改变反应的焓变',
            sortOrder: 2,
          ),
          QuestionOptionDraft(
            label: 'D',
            content: '增大压强后平衡向气体分子数减小的方向移动，转化率提高',
            sortOrder: 3,
          ),
        ],
      );

      await _pumpDetail(tester, db, question.id, size: const Size(1280, 2000));

      double dy(String label) => tester
          .getTopLeft(find.byKey(questionDetailOptionCellKey(label)))
          .dy;
      expect(dy('A'), lessThan(dy('B')));
      expect(dy('B'), lessThan(dy('C')));
      expect(dy('C'), lessThan(dy('D')));
    });

    testWidgets('窄屏（640）退化单列，短选项也不并排', (tester) async {
      final db = _newDatabase();
      final question = await _seed(
        db,
        stem: '下列说法正确的是（　　）',
        options: const <QuestionOptionDraft>[
          QuestionOptionDraft(label: 'A', content: '增大', sortOrder: 0),
          QuestionOptionDraft(label: 'B', content: '减小', sortOrder: 1),
          QuestionOptionDraft(label: 'C', content: '不变', sortOrder: 2),
          QuestionOptionDraft(label: 'D', content: '无法确定', sortOrder: 3),
        ],
      );

      await _pumpDetail(tester, db, question.id, size: const Size(640, 2000));

      double dy(String label) => tester
          .getTopLeft(find.byKey(questionDetailOptionCellKey(label)))
          .dy;
      expect(dy('A'), lessThan(dy('B')));
      expect(dy('B'), lessThan(dy('C')));
      expect(dy('C'), lessThan(dy('D')));
    });
  });
}

// ---------------------------------------------------------------------------
// 工具
// ---------------------------------------------------------------------------

AppDatabase _newDatabase() {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  return database;
}

Future<Question> _seed(
  AppDatabase database, {
  required String stem,
  String textFormat = 'markdown',
  String questionType = 'single_choice',
  String? title,
  String origin = 'manual',
  String state = 'structured',
  List<QuestionOptionDraft> options = const <QuestionOptionDraft>[
    QuestionOptionDraft(label: 'A', content: '甲', sortOrder: 0),
    QuestionOptionDraft(label: 'B', content: '乙', isCorrect: true, sortOrder: 1),
  ],
}) async {
  final result = await QuestionRepository(database).ingest(
    QuestionDraft(
      stem: stem,
      answer: 'B',
      subjectKey: 'chemistry',
      questionType: questionType,
      sourceLevel: 'gaokao',
      year: 2026,
      region: '山东',
      textFormat: textFormat,
      origin: origin,
      state: state,
      options: options,
    ),
  );
  if (title != null) {
    await (database.update(database.questions)
          ..where((row) => row.id.equals(result.question.id)))
        .write(QuestionsCompanion(title: Value<String>(title)));
  }
  return (await QuestionRepository(database).byId(result.question.id))!;
}

Future<void> _seedImage(
  AppDatabase database,
  FakeQuestionMediaStore store, {
  required String questionId,
  required String fileName,
  required Uint8List bytes,
  int? sortOrder,
}) async {
  final image = store.seed(
    questionId: questionId,
    fileName: fileName,
    bytes: bytes,
  );
  await database.into(database.attachments).insert(
        AttachmentsCompanion.insert(
          id: image.attachmentId,
          ownerType: 'question',
          ownerId: questionId,
          relPath: image.relPath,
          mime: const Value<String>('image/png'),
          sortOrder:
              Value<int>(sortOrder ?? image.sortOrder),
          role: const Value<String>(QuestionImageRole.stem),
          createdAt: 1700000000000,
        ),
      );
}

Future<void> _pumpBank(
  WidgetTester tester,
  AppDatabase database, {
  Size size = const Size(1200, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        questionMediaStoreProvider.overrideWithValue(
          FakeQuestionMediaStore(database: database),
        ),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: QuestionBankPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDetail(
  WidgetTester tester,
  AppDatabase database,
  String questionId, {
  FakeQuestionMediaStore? mediaStore,
  Size size = const Size(1200, 3000),
}) async {
  final store = mediaStore ?? FakeQuestionMediaStore(database: database);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        modelAdapterProvider.overrideWithValue(null),
        questionMediaStoreProvider.overrideWithValue(store),
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

/// 等图片字节 provider 解析完（图片清单/字节都是异步 provider）。
Future<void> _waitForImages(WidgetTester tester, {int count = 4}) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(Image).evaluate().length >= count) {
      return;
    }
  }
  fail('等了 6 秒也没等到 $count 张图片');
}

/// 卡片上的文字（摘要可能是 Text / SelectableText / RichText）。
String _cardText(WidgetTester tester) {
  final buffer = StringBuffer();
  void collect(Element element) {
    final widget = element.widget;
    if (widget is Text) {
      buffer.writeln(widget.data ?? widget.textSpan?.toPlainText() ?? '');
    } else if (widget is EditableText) {
      buffer.writeln(widget.controller.text);
    } else if (widget is RichText) {
      buffer.writeln(widget.text.toPlainText(includePlaceholders: false));
    }
    element.visitChildren(collect);
  }

  for (final element in find.byType(Card).evaluate()) {
    collect(element);
  }
  return buffer.toString();
}

/// 整页文字（用于断言占位符/语法字符不残留）。
String _renderedText(WidgetTester tester) {
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

int _mathWidgetCount(WidgetTester tester) => tester
    .widgetList(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'Math',
        skipOffstage: false,
      ),
    )
    .length;
