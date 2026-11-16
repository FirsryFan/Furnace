import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';
import 'package:furnace/features/questions/presentation/question_paper_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// GUI-level smoke against a **copy** of the real 170-question database.
///
/// It does not click the 题库→组卷 button; it mounts the page the button opens
/// and lets the real providers read the real tag/KP graph. That is the part the
/// user-reported crash reaches.
void main() {
  testWidgets('real database paper page mounts without throwing', (tester) async {
    final source = File(r'E:\Furnace\data\furnace.db');
    if (!source.existsSync()) {
      markTestSkipped('real database not present');
      return;
    }
    final tmp = Directory.systemTemp.createTempSync('furnace-real-paper-');
    final copied = File('${tmp.path}/furnace.db');
    source.copySync(copied.path);
    final db = AppDatabase.forTesting(NativeDatabase(copied));
    addTearDown(() async {
      await db.close();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          cognitiveLibraryDiagnosisProvider
              .overrideWith((ref) async => LibraryDiagnosis.notRun),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: QuestionPaperPage(),
        ),
      ),
    );
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      final busy = find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      if (!busy && i >= 2) break;
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(QuestionPaperPage), findsOneWidget);
  });
}
