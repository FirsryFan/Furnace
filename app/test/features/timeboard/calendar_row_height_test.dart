import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/data/repositories/time_template_repository.dart';
import 'package:furnace/features/timeboard/presentation/calendar_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// v36 day/week grid: the user can grab any row divider and drag it to resize
/// the rows freely; on release the height snaps to a detent and is stored.
/// Without a stored height the legacy formula must stay byte-identical.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<AppDatabase> openDatabase() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    return db;
  }

  Future<void> pumpCalendar(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CalendarPage(),
        ),
      ),
    );
    await settle(tester);
  }

  /// Grabs the given row divider and drags it [dy] pixels in four steps.
  Future<void> dragDivider(WidgetTester tester, int row, double dy) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(calendarRowDividerKey(row))),
    );
    const steps = 4;
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(0, dy / steps));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester);
  }

  test('snapping picks the nearest detent and clamps to the safety range', () {
    expect(kCalendarHourHeightDetents, [22, 33, 44, 66, 88, 132, 176, 264]);
    expect(snapCalendarHourHeight(100), 88);
    expect(snapCalendarHourHeight(120), 132);
    expect(snapCalendarHourHeight(70), 66);
    expect(snapCalendarHourHeight(12), 22);
    expect(snapCalendarHourHeight(400), 264);
    expect(snapCalendarHourHeight(5000), 264);
    expect(snapCalendarHourHeight(-20), 22);
    expect(
      snapCalendarHourHeight(27.5),
      22,
      reason: 'a tie keeps the smaller detent',
    );
  });

  testWidgets('without a stored height the rows keep the legacy formula',
      (tester) async {
    final db = await openDatabase();
    await pumpCalendar(tester, db);

    final grid = find.byKey(calendarDayGridKey);
    expect(grid, findsOneWidget);
    // 24 hours at 30 minutes = 48 rows; 44 * (60 / 30) = 88 px per row.
    expect(tester.getSize(grid).height, 48 * 88);
    expect((await TimeViewRepository(db).get())?.hourHeight, isNull);
  });

  testWidgets('dragging a divider down grows the rows and stores a detent',
      (tester) async {
    final db = await openDatabase();
    await pumpCalendar(tester, db);

    await dragDivider(tester, 1, 400);

    final stored = (await TimeViewRepository(db).get())?.hourHeight;
    expect(stored, 264);
    expect(kCalendarHourHeightDetents, contains(stored));
    // 264 px per hour at 30-minute rows = 132 px per row, 48 rows.
    expect(tester.getSize(find.byKey(calendarDayGridKey)).height, 48 * 132);
  });

  testWidgets('dragging up snaps to a smaller detent', (tester) async {
    final db = await openDatabase();
    await pumpCalendar(tester, db);

    await dragDivider(tester, 1, -40);

    final stored = (await TimeViewRepository(db).get())?.hourHeight;
    expect(stored, anyOf(88, 132));
    expect(stored, lessThan(176));
    final rowHeight = stored! / 2;
    expect(
      tester.getSize(find.byKey(calendarDayGridKey)).height,
      48 * rowHeight,
    );
  });

  testWidgets('the reset item clears the stored height', (tester) async {
    final db = await openDatabase();
    await TimeViewRepository(db).update(hourHeight: 264);
    await pumpCalendar(tester, db);
    expect(tester.getSize(find.byKey(calendarDayGridKey)).height, 48 * 132);

    await tester.tap(find.byIcon(Icons.height));
    await tester.pumpAndSettle();
    // The menu keeps the three legacy zoom levels, then the reset item.
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l10n.calendarZoom15), findsOneWidget);
    expect(find.text(l10n.calendarZoom30), findsOneWidget);
    expect(find.text(l10n.calendarZoom60), findsOneWidget);
    expect(find.text(l10n.calendarRowHeightReset), findsOneWidget);
    expect(
      tester
          .widgetList<CheckedPopupMenuItem<Object>>(
            find.byType(CheckedPopupMenuItem<Object>),
          )
          .singleWhere((item) => item.checked)
          .value,
      30,
      reason: 'the default 30-minute zoom stays checked',
    );
    expect(find.byKey(calendarRowHeightResetKey), findsOneWidget);
    await tester.tap(find.byKey(calendarRowHeightResetKey));
    await tester.pumpAndSettle();
    await settle(tester);

    expect((await TimeViewRepository(db).get())?.hourHeight, isNull);
    expect(tester.getSize(find.byKey(calendarDayGridKey)).height, 48 * 88);
  });

  testWidgets('a stored hour height is restored on open', (tester) async {
    final db = await openDatabase();
    await TimeViewRepository(db).update(minutesPerRow: 60, hourHeight: 132);
    await pumpCalendar(tester, db);

    // 24 rows, 132 px per hour with whole-hour rows = 132 px per row.
    expect(tester.getSize(find.byKey(calendarDayGridKey)).height, 24 * 132);
  });

  testWidgets('an out-of-range stored height is clamped on open',
      (tester) async {
    final db = await openDatabase();
    await TimeViewRepository(db).update(hourHeight: 1000);
    await pumpCalendar(tester, db);

    // Clamped to 400 px per hour: 400 * (60 / 30) = 200 px per row.
    expect(tester.getSize(find.byKey(calendarDayGridKey)).height, 48 * 200);
  });

  testWidgets('week view dividers are draggable too', (tester) async {
    final db = await openDatabase();
    await pumpCalendar(tester, db);

    await tester.tap(find.byIcon(Icons.view_week_outlined));
    await settle(tester);
    final grid = find.byKey(calendarWeekGridKey);
    expect(grid, findsOneWidget);

    await dragDivider(tester, 1, 400);

    expect((await TimeViewRepository(db).get())?.hourHeight, 264);
    expect(tester.getSize(grid).height, 48 * 132);
  });

  testWidgets('tapping an hour label still opens the add-block dialog',
      (tester) async {
    final db = await openDatabase();
    await pumpCalendar(tester, db);

    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    await tester.tap(find.text('00:30'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(l10n.calendarAddBlock), findsOneWidget);
    // A tap must not be mistaken for a drag; nothing got stored.
    expect((await TimeViewRepository(db).get())?.hourHeight, isNull);

    await tester.tap(find.byTooltip(l10n.commonCancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('the divider hit bands do not swallow block taps',
      (tester) async {
    final db = await openDatabase();
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    await TimeBlockRepository(db).createTimeBlock(
      title: '早读',
      startAt: day.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
      endAt: day.add(const Duration(minutes: 90)).millisecondsSinceEpoch,
    );
    await pumpCalendar(tester, db);

    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text('早读'), findsOneWidget);
    await tester.tap(find.text('早读'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(l10n.commonEdit), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.commonCancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsNothing);
  });
}
