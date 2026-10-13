// The usage guide is the app's own documentation, so the failure mode worth
// pinning is silence: a section whose ARB key exists but was never wired into
// the page, leaving a page that still claims to be complete. Each of the four
// new sections is asserted by its title and by one phrase from its body.
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
    tester.view.physicalSize = const Size(1200, 6000);
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

  testWidgets('the guide covers AI, review, knowledge and the cognitive model',
      (tester) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();

    expect(find.text('AI 助手能做什么、什么要你确认'), findsOneWidget);
    expect(find.text('复习与闪存卡'), findsOneWidget);
    expect(find.text('知识库与标签'), findsOneWidget);
    expect(find.text('认知模型读数怎么理解'), findsOneWidget);
    // Bodies, not just headings: one distinctive claim from each.
    expect(find.textContaining('query_content'), findsOneWidget);
    expect(find.textContaining('FSRS'), findsOneWidget);
    expect(find.textContaining('整棵子树'), findsWidgets);
    expect(find.textContaining('evaluate_problem_fit'), findsWidgets);
    // The ranking section it grew out of is still there.
    expect(find.text('总分怎么算'), findsOneWidget);
  });

  testWidgets('the English guide covers the same ground', (tester) async {
    await pumpPage(tester, locale: const Locale('en'));
    await tester.pumpAndSettle();

    expect(find.text('Review and flashcards'), findsOneWidget);
    expect(
      find.text('What the assistant can do, and what waits for your consent'),
      findsOneWidget,
    );
    expect(find.text('How the score is computed'), findsOneWidget);
    expect(find.textContaining('FSRS'), findsWidgets);
  });
}
