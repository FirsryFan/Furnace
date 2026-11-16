import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/application/paper_plan_provider.dart';
import 'package:furnace/features/questions/data/question_media_store.dart';
import 'package:furnace/features/questions/presentation/question_bank_page.dart';
import 'package:furnace/features/questions/presentation/question_paper_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// GUI-level smoke against a copy of the real DB: tap 题库→组卷 and ensure the
/// paper page is reached rather than the app throwing.
void main() {
  testWidgets('real database 题库→组卷 reaches paper page', (tester) async {
    final source = File(r'E:\Furnace\data\furnace.db');
    if (!source.existsSync()) {
      markTestSkipped('real database not present');
      return;
    }
    final tmp = Directory.systemTemp.createTempSync('furnace-real-bank-');
    final copied = File('${tmp.path}/furnace.db');
    source.copySync(copied.path);
    final db = AppDatabase.forTesting(NativeDatabase(copied));
    addTearDown(() async {
      await db.close();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    tester.view.physicalSize = const Size(1400, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          cognitiveLibraryDiagnosisProvider
              .overrideWith((ref) async => LibraryDiagnosis.notRun),
          questionMediaStoreProvider.overrideWithValue(
            QuestionMediaStore(
              database: db,
              supportDirectory: () async => tmp,
            ),
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
    expect(tester.takeException(), isNull);

    // 组卷入口显示，点击后进入 QuestionPaperPage。
    expect(find.text('组卷'), findsWidgets);
    await tester.tap(find.text('组卷').first);
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      final busy = find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      if (!busy && i >= 2) break;
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(QuestionPaperPage), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(QuestionPaperPage)),
    );
    final plan = await container.read(paperPlanProvider.future);
    expect(plan.items, isNotEmpty);
    expect(
      plan.items.any((item) => item.matchedKnowledgePointIds.isNotEmpty),
      isTrue,
      reason: '真实库修复后应至少有一道题匹配到知识点标签',
    );
  });
}
