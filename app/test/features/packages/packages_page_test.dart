import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/mind_map_repository.dart';
import 'package:furnace/data/repositories/package_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/package/knowledge_package_manifest.dart';
import 'package:furnace/features/packages/application/package_import_service.dart';
import 'package:furnace/features/packages/presentation/packages_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// The library page: it must actually list what was imported, not just say
/// "no packages yet" over a database that has one.
void main() {
  Future<void> pumpLibrary(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PackagesPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<AppDatabase> importOne() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await PackageImportService(
      packageRepository: PackageRepository(db),
      tagRepository: TagRepository(db),
      ankiRepository: AnkiRepository(db),
      mindMapRepository: MindMapRepository(db),
    ).importManifest(
      KnowledgePackageManifest(
        formatVersion: 1,
        packageId: 'pkg-page',
        name: '光合作用',
        version: '1.2.0',
        author: '张三',
        exportedAt: DateTime.utc(2026, 10, 2),
        knowledgePoints: const [
          PackageKnowledgePoint(
            id: 'kp-1',
            title: '场所',
            content: '主要场所是叶绿体。',
            templates: [],
          ),
        ],
      ),
    );
    return db;
  }

  testWidgets('an imported package is listed with its version and counts',
      (tester) async {
    final db = await importOne();
    addTearDown(db.close);

    await pumpLibrary(tester, db);

    expect(find.text('光合作用'), findsOneWidget);
    expect(find.text('v1.2.0'), findsOneWidget);
    expect(find.textContaining('张三'), findsOneWidget);
    expect(
      find.textContaining('知识点 1'),
      findsOneWidget,
      reason: 'the tile reports how many knowledge points the package brought in',
    );
  });

  testWidgets('an empty database still shows the empty state', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await pumpLibrary(tester, db);

    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l10n.packagesEmpty), findsOneWidget);
  });
}
