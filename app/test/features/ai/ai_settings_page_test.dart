import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/skill/skill_store.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/ai/presentation/ai_settings_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// The rounds setting as the user meets it: a slider showing the stored budget,
/// and a save that writes what the slider shows.
///
/// The repository tests prove the value round-trips; this one proves the screen
/// is wired to it. Those are different failures - a slider that moves but is
/// never read in `_save` looks fine there and is broken here.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await AiRepository(db).saveConfig(
      const AiConfig(enabled: true, apiKey: 'sk-test'),
      fallbackLanguage: 'zh',
    );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('the slider shows the stored budget and saves a new one',
      (tester) async {
    // Tall enough that the whole form is laid out: the settings page is a
    // ListView, so an off-screen slider would not be built at all.
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          // The skills card is not what this test is about, and its loading
          // spinner is indeterminate - which means a `pumpAndSettle` here would
          // never settle. An empty installed list is the state a fresh install
          // is in, so nothing is faked that the app cannot really show.
          installedSkillsProvider
              .overrideWith((ref) => const <InstalledSkill>[]),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AiSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Nothing was ever chosen, so the shipped default is what is shown.
    expect(AiConfig.defaultMaxRounds, 8);
    expect(find.text('8 轮'), findsOneWidget);

    // Drag the thumb to the far right: the top of the offered range.
    await tester.drag(find.byType(Slider), const Offset(1000, 0));
    await tester.pumpAndSettle();
    expect(find.text('20 轮'), findsOneWidget,
        reason: 'the value next to the slider follows the thumb');

    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(
        (await AiRepository(db).getConfig()).maxRounds, AiConfig.maxMaxRounds,
        reason: 'the saved budget is the one the slider showed');
  });
}
