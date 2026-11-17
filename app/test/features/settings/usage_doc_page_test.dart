// The usage guide is the app's own documentation, so two failure modes are worth
// pinning:
//  * silence: a section whose ARB key exists but was never wired into the page,
//    leaving a page that claims to be complete while missing a module;
//  * developer voice: internal vocabulary that a student cannot act on
//    ("subtree", "capability profile", "raw readings under developer info").
//
// The assertions are therefore pairs: a heading that must exist, and a phrase
// from the old internal wording that must not be back.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/settings/presentation/usage_doc_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pumpPage(
    WidgetTester tester, {
    Locale locale = const Locale('zh'),
  }) {
    // The guide is a long list; a viewport this tall keeps every entry built so
    // the assertions are about wiring, not about scroll position.
    tester.view.physicalSize = const Size(1200, 9000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const UsageDocPage(),
        ),
      ),
    );
  }

  testWidgets('starts with the three booklets and how to use them',
      (tester) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();

    expect(find.text('先看这里'), findsOneWidget);
    expect(find.text('三个册子是什么、怎么用'), findsOneWidget);
    // All three booklets are named, and the order to use them is spelled out.
    expect(find.textContaining('题目册'), findsWidgets);
    expect(find.textContaining('答案册'), findsWidgets);
    expect(find.textContaining('题解册'), findsWidgets);
    expect(find.textContaining('先做题目册'), findsOneWidget);
  });

  testWidgets('gives every module its own one-line entry', (tester) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();

    expect(find.text('每个模块干什么，一句话'), findsOneWidget);
    for (final title in <String>[
      '今日计划',
      '学习状态',
      '评测',
      '知识库',
      '标签树',
      '题库与组卷',
    ]) {
      expect(find.text(title), findsOneWidget, reason: 'missing module: $title');
    }
    // A distinctive claim from each entry, not just the heading.
    expect(find.textContaining('只有你点排序才会重排'), findsOneWidget);
    expect(find.textContaining('证据不足'), findsOneWidget);
    expect(find.textContaining('不联网'), findsWidgets);
    expect(find.textContaining('卸载只删导入记录'), findsOneWidget);
    expect(find.textContaining('卡组就是标签'), findsOneWidget);
    expect(find.textContaining('同一道题不会重复存'), findsOneWidget);
  });

  testWidgets('explains measured, preset and uncalibrated in plain words',
      (tester) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();

    expect(find.text('实测、预设、未标定'), findsOneWidget);
    // Each of the three words is defined, not just used.
    expect(find.textContaining('· 实测'), findsOneWidget);
    expect(find.textContaining('· 预设'), findsOneWidget);
    expect(find.textContaining('· 未标定'), findsOneWidget);
    expect(find.textContaining('只能当起点，不能当结论'), findsOneWidget);
  });

  testWidgets('the old developer wording is not shown to users', (tester) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();

    // Vocabulary that came from the implementation, not from studying.
    for (final old in <String>[
      '整棵子树',
      '能力动作画像',
      '四类待确认',
      '7 档',
      '开发者信息（只读）',
      '开发文档',
      '今天做什么、什么时候做',
      '学习状态读数怎么理解',
      '知识库与标签',
    ]) {
      expect(find.textContaining(old), findsNothing, reason: 'old copy: $old');
    }
  });

  testWidgets('the English guide covers the same ground', (tester) async {
    await pumpPage(tester, locale: const Locale('en'));
    await tester.pumpAndSettle();

    expect(find.text('The three booklets, and how to use them'), findsOneWidget);
    expect(find.textContaining('Question booklet'), findsOneWidget);
    expect(find.text('Measured, preset, uncalibrated'), findsOneWidget);
    expect(find.text("Today's plan"), findsOneWidget);
    expect(find.text('Learning status'), findsOneWidget);
    expect(find.text('Assessment'), findsOneWidget);
    expect(find.text('Tag tree'), findsOneWidget);
    expect(find.text('Question bank and paper assembly'), findsOneWidget);
    // The English page must not keep the old implementation vocabulary either.
    expect(find.textContaining('subtree'), findsNothing);
    expect(find.textContaining('Capability actions'), findsNothing);
  });
}
