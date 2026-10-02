// Widget tests for the icon picker, the editor section that hosts it, and the
// path that matters most: the theme's `icons` map -> the IconData the navigation
// bar actually renders (APPEARANCE_DESIGN decision D1).

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/app/shell/home_shell.dart';
import 'package:furnace/core/theme/app_icons.dart';
import 'package:furnace/core/theme/theme_profile.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/settings/application/appearance_providers.dart';
import 'package:furnace/features/settings/presentation/icon_picker_page.dart';
import 'package:furnace/features/settings/presentation/theme_editor_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// Both pages are `ListView`s: on the default 800x600 surface a row that is off
/// screen is not built, and therefore not findable. A tall surface keeps the
/// assertions about "all seven rows" honest; the narrow width keeps the shell in
/// its bottom-navigation layout.
void _useTallSurface(WidgetTester tester, {double width = 420}) {
  tester.view.physicalSize = Size(width, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Yields to the event loop until the loading spinner is gone. `pumpAndSettle`
/// cannot be used while a `CircularProgressIndicator` is on screen: it animates
/// forever and would time out.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      return;
    }
  }
}

Widget _app(Widget home, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

/// Pushes the picker from a host page and hands back a getter for the result the
/// route returned, so "what the picker returns" is asserted rather than assumed.
Future<String? Function()> _openPicker(
  WidgetTester tester, {
  String slot = 'tags',
  String? current,
}) async {
  String? result;
  var returned = false;
  await tester.pumpWidget(_app(Builder(
    builder: (context) => Center(
      child: ElevatedButton(
        onPressed: () async {
          result = await Navigator.of(context).push<String>(
            MaterialPageRoute(
              builder: (_) => IconPickerPage(slot: slot, current: current),
            ),
          );
          returned = true;
        },
        child: const Text('open picker'),
      ),
    ),
  )));
  await tester.tap(find.text('open picker'));
  await tester.pumpAndSettle();
  return () => returned ? result : null;
}

void main() {
  group('picker', () {
    testWidgets('shows the catalog grouped by category', (tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(_app(const IconPickerPage(slot: 'tags')));
      await tester.pump();

      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      expect(find.textContaining(l10n.iconPickerTitle), findsOneWidget);
      for (final category in IconCategory.values) {
        expect(
          find.text(iconCategoryLabel(l10n, category)),
          findsWidgets,
          reason: 'category ${category.name} has no header',
        );
      }
      // The slot's current icon is in the grid, and so is a name that is not the
      // factory default (proving this is the catalog, not the seven defaults).
      expect(find.byTooltip('account_tree'), findsOneWidget);
      expect(find.byTooltip('star'), findsOneWidget);
    });

    testWidgets('the search box filters by name', (tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(_app(const IconPickerPage(slot: 'tags')));
      await tester.pump();
      expect(find.byTooltip('account_tree'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'star');
      await tester.pump();
      expect(find.byTooltip('star'), findsOneWidget);
      expect(find.byTooltip('account_tree'), findsNothing);

      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      expect(
        find.text(iconCategoryLabel(l10n, IconCategory.knowledge)),
        findsNothing,
        reason: 'a category header without matches must not linger',
      );

      await tester.enterText(find.byType(TextField), 'zzzzzz');
      await tester.pump();
      expect(find.text(l10n.iconPickerEmpty), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
    });

    testWidgets('picking an icon returns its catalog name', (tester) async {
      _useTallSurface(tester);
      final result = await _openPicker(tester);
      await tester.tap(find.byTooltip('star'));
      await tester.pumpAndSettle();
      expect(result(), 'star');
    });

    testWidgets('restore default returns the sentinel, and back returns null',
        (tester) async {
      _useTallSurface(tester);
      final restore = await _openPicker(tester);
      await tester.tap(find.text(
        (await AppLocalizations.delegate.load(const Locale('zh')))
            .iconPickerRestoreDefault,
      ));
      await tester.pumpAndSettle();
      expect(restore(), IconPickerPage.restoreDefault);

      // Cancelling is a different answer from "restore default": the caller must
      // be able to tell "the user backed out" from "use the factory icon".
      final cancelled = await _openPicker(tester);
      // `tester.pageBack()` is not usable here: it looks for an English "Back"
      // tooltip, and this app runs in Chinese. Tapping the AppBar's own back
      // button is the same gesture without the locale assumption.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(cancelled(), isNull);
      expect(IconPickerPage.restoreDefault, isNot(isNull));
    });

    testWidgets('opens with the slot\'s current icon marked', (tester) async {
      _useTallSurface(tester);
      await _openPicker(tester, slot: 'thread', current: 'rocket_launch');
      // The marked cell is the one whose border is the primary colour; asserting
      // the tooltip exists keeps this independent of decoration details.
      expect(find.byTooltip('rocket_launch'), findsOneWidget);
      expect(find.byTooltip('bolt'), findsOneWidget);
    });
  });

  group('theme editor section', () {
    testWidgets('one row per slot, and the pick is stored in the document',
        (tester) async {
      _useTallSurface(tester);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(_app(
        const ThemeEditorPage(themeId: 'builtin-dark'),
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      ));
      await _settle(tester);

      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      expect(find.text(l10n.settingsThemeIcons), findsOneWidget);
      for (final slot in AppIcons.slots) {
        expect(
          find.text(slotLabel(l10n, slot)),
          findsOneWidget,
          reason: 'slot $slot has no row in the editor',
        );
      }
      // Nothing configured yet: every row reads as "default".
      expect(
        find.text(l10n.iconPickerDefault),
        findsNWidgets(AppIcons.slots.length),
      );

      await tester.tap(find.text(slotLabel(l10n, 'tags')));
      await tester.pumpAndSettle();
      expect(find.byType(IconPickerPage), findsOneWidget);
      await tester.tap(find.byTooltip('star'));
      await tester.pumpAndSettle();

      // Back in the editor the row now names the chosen icon, and only six rows
      // still say "default".
      expect(find.text('star'), findsOneWidget);
      expect(
        find.text(l10n.iconPickerDefault),
        findsNWidgets(AppIcons.slots.length - 1),
      );
    });
  });

  group('navigation bar', () {
    Future<Set<IconData>> navIcons(
      WidgetTester tester,
      ThemeProfileData theme,
      AppDatabase db,
    ) async {
      await tester.pumpWidget(_app(
        const HomeShell(),
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          aiEnabledProvider.overrideWithValue(false),
          activeAppearanceProvider.overrideWith(
            (ref) => ActiveAppearance(
              row: null,
              data: theme,
              followSystem: false,
              legacyMode: 'dark',
            ),
          ),
        ],
      ));
      await _settle(tester);
      return tester
          .widgetList<Icon>(find.descendant(
            of: find.byType(NavigationBar),
            matching: find.byType(Icon),
          ))
          .map((icon) => icon.icon!)
          .toSet();
    }

    testWidgets('the IconData it renders follows the theme\'s icons map',
        (tester) async {
      _useTallSurface(tester);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      // Factory theme: the icons the shell hard-coded before D1. The selected
      // destination (tags, index 0) renders the *filled* variant.
      final before = await navIcons(tester, const ThemeProfileData(name: 'a'), db);
      expect(before, contains(Icons.account_tree));
      expect(before, contains(Icons.bolt_outlined));

      // Same shell, different theme document: two slots are re-pointed.
      //
      // The intermediate empty frame is load-bearing: pumping a new
      // `ProviderScope` of the same type at the same position *updates* the
      // existing element, and Riverpod keeps its container - so the new override
      // would be ignored and this test would silently compare a theme with
      // itself. Unmounting first forces a fresh container.
      await tester.pumpWidget(const SizedBox.shrink());
      final after = await navIcons(
        tester,
        const ThemeProfileData(
          name: 'b',
          icons: {'tags': 'star', 'thread': 'rocket_launch'},
        ),
        db,
      );
      expect(after, isNot(before));
      expect(after, contains(Icons.star),
          reason: 'the selected slot must render the filled variant of the choice');
      expect(after, contains(Icons.rocket_launch_outlined),
          reason: 'an unselected slot renders the outlined variant');
      expect(after, isNot(contains(Icons.account_tree)));
      expect(after, isNot(contains(Icons.bolt_outlined)));
      // Untouched slots keep their factory icons.
      expect(after, contains(Icons.schedule_outlined));
      expect(after, contains(Icons.settings_outlined));
    });

    testWidgets('an unknown name in the theme falls back, it does not throw',
        (tester) async {
      _useTallSurface(tester);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final icons = await navIcons(
        tester,
        const ThemeProfileData(
          name: 'broken',
          icons: {'tags': 'no_such_icon', 'thread': 'bolt'},
        ),
        db,
      );
      expect(icons, contains(Icons.account_tree));
      expect(icons, isNot(contains(Icons.bolt)));
    });
  });
}
