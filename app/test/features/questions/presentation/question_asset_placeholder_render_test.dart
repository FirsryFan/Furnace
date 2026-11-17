import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/presentation/question_stem_markdown_view.dart';
import 'package:furnace/l10n/app_localizations.dart';

import 'support/question_media_fakes.dart';

/// 题面里整卷源格式 `{{asset:NAME}}` 的显示契约：
///  * 有同名附件（含 WMF→同名 PNG 的转换图）→ 真的渲染成图；
///  * 没有附件 / `.wmf` 不支持 → 明确的「图片缺失」文字；
///  * **任何情况下都不把 `{{asset:...}}` 原样显示给用户**。
void main() {
  late AppDatabase db;
  late FakeQuestionMediaStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = FakeQuestionMediaStore(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpStem(
    WidgetTester tester,
    String text, {
    required String questionId,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          questionMediaStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: QuestionMarkdownTextWithImages(
              questionId: questionId,
              text: text,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('没有附件：源占位变成「图片缺失」，不出现原始占位符', (tester) async {
    await pumpStem(
      tester,
      '利用铁基、钙基物质的化学循环（{{asset:q14_img01.wmf}}'
      '{{asset:q14_img02.png}}）可从高炉煤气中分离出气体',
      questionId: 'q-asset-missing',
    );

    expect(find.textContaining('{{asset:', findRichText: true), findsNothing);
    expect(find.textContaining('q14_img01.wmf', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('WMF 格式不支持', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('有同名 PNG（WMF 转换产物）：渲染成图，不显示缺失提示', (tester) async {
    store.seed(
      questionId: 'q-asset-resolved',
      fileName: 'q14_img01.png',
      bytes: tinyPngBytes,
    );
    await pumpStem(
      tester,
      '如图{{asset:q14_img01.wmf}}所示',
      questionId: 'q-asset-resolved',
    );

    expect(
      find.byKey(const ValueKey<String>('question-inline-image-0')),
      findsOneWidget,
    );
    expect(find.textContaining('{{asset:', findRichText: true), findsNothing);
    expect(find.textContaining('图片缺失', findRichText: true), findsNothing);
  });

  testWidgets('同名 PNG 附件：按附件顺序渲染对应图', (tester) async {
    store.seed(
      questionId: 'q-asset-multi',
      fileName: 'fig-a.png',
      bytes: tinyPngBytes,
    );
    store.seed(
      questionId: 'q-asset-multi',
      fileName: 'fig-b.png',
      bytes: tinyPngBytes,
    );
    await pumpStem(
      tester,
      '甲{{asset:fig-a.png}}乙{{asset:fig-b.png}}丙',
      questionId: 'q-asset-multi',
    );

    expect(
      find.byKey(const ValueKey<String>('question-inline-image-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('question-inline-image-1')),
      findsOneWidget,
    );
    expect(find.textContaining('{{asset:', findRichText: true), findsNothing);
  });

  testWidgets('只有未知名字的占位：显示缺失提示而不是空图', (tester) async {
    store.seed(
      questionId: 'q-asset-unknown',
      fileName: 'some-other.png',
      bytes: tinyPngBytes,
    );
    await pumpStem(
      tester,
      '图{{asset:not-in-db.png}}',
      questionId: 'q-asset-unknown',
    );

    expect(find.textContaining('not-in-db.png', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('{{asset:', findRichText: true), findsNothing);
  });
}
