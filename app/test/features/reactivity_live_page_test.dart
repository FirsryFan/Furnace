import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/core/state/data_revision.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/features/tags/presentation/tag_tree_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// A revision that never moves - the pre-change behaviour, kept as the control
/// group for the test below.
class _FrozenRevision extends DataRevision {
  @override
  int build() => 0;
}

/// The user-visible half of the promise: a real page, mounted, showing new data
/// that was written by somebody else - here by a repository call that the page
/// knows nothing about (this is the shape of every AI-driven write).
///
/// Before this change the page kept its cached value until the app restarted.
void main() {
  Future<void> pumpTagPage(
    WidgetTester tester,
    AppDatabase db, {
    List<Override> extraOverrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ...extraOverrides,
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TagTreePage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('a mounted page shows a write it did not perform', (tester) async {
    final db = AppDatabase.forTesting(instrumentWrites(NativeDatabase.memory()));
    addTearDown(db.close);

    await pumpTagPage(tester, db);
    expect(find.text('化学'), findsNothing);

    await TagRepository(db).createTag(name: '化学');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('化学'), findsOneWidget);
  });

  testWidgets('frozen revision: the very same write stays invisible',
      (tester) async {
    // The control group. Freezing the revision reproduces exactly the old
    // behaviour (cached value until restart), which is what proves the revision
    // channel - not something else - is what the first test is measuring.
    final db = AppDatabase.forTesting(instrumentWrites(NativeDatabase.memory()));
    addTearDown(db.close);

    await pumpTagPage(
      tester,
      db,
      extraOverrides: [dataRevisionProvider.overrideWith(_FrozenRevision.new)],
    );
    await TagRepository(db).createTag(name: '化学');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('化学'), findsNothing);
  });
}
