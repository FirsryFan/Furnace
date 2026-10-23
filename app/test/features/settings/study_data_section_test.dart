/// 设置页「学习数据」小节：作答记录条数三态 + 清空全部（确认/取消/失败）。
///
/// 真仓储要 DB；这里只测 UI 契约，用 `_FakeAttemptRepository` 记录 countAll/
/// deleteAll 调用次数并可注入错误。清空后题库页徽标靠 databaseRevision 自动重算，
/// 不在本文件范围（那条链路由题库页测试覆盖）。
library;

import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_attempt_repository.dart';
import 'package:furnace/data/repositories/repository_providers.dart';
import 'package:furnace/features/questions/application/question_pack_service.dart';
import 'package:furnace/features/settings/presentation/data_section.dart';
import 'package:furnace/l10n/app_localizations.dart';

import 'support/question_pack_fakes.dart';

void main() {
  late AppDatabase db;
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pumpDataSection(
    WidgetTester tester,
    _FakeAttemptRepository attempts,
  ) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          questionPackServiceProvider.overrideWithValue(
            FakeQuestionPackService(),
          ),
          questionAttemptRepositoryProvider.overrideWithValue(attempts),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(child: DataSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ListTile tile(WidgetTester tester) =>
      tester.widget<ListTile>(find.byKey(settingsClearAttemptsTileKey));

  testWidgets('有 3 条记录：显示「学习数据」小节与共 3 次，行可用', (tester) async {
    final attempts = _FakeAttemptRepository(db)..count = 3;
    await pumpDataSection(tester, attempts);

    expect(find.text(zh.settingsStudyDataTitle), findsOneWidget);
    expect(find.text(zh.settingsClearAttemptsTitle), findsOneWidget);
    expect(find.text(zh.settingsClearAttemptsSubtitle(3)), findsOneWidget);
    expect(tile(tester).enabled, isTrue);
    expect(attempts.countAllCalls, 1);
  });

  testWidgets('0 条：副标题显示空态，点行不弹确认框也不调 deleteAll', (tester) async {
    final attempts = _FakeAttemptRepository(db);
    await pumpDataSection(tester, attempts);

    expect(find.text(zh.settingsClearAttemptsEmpty), findsOneWidget);
    expect(tile(tester).enabled, isFalse);

    await tester.tap(find.byKey(settingsClearAttemptsTileKey));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(attempts.deleteAllCalls, 0);
  });

  testWidgets('点行弹确认框（标题/正文带条数），取消不删', (tester) async {
    final attempts = _FakeAttemptRepository(db)..count = 3;
    await pumpDataSection(tester, attempts);

    await tester.tap(find.byKey(settingsClearAttemptsTileKey));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(zh.settingsClearAttemptsConfirmTitle), findsOneWidget);
    expect(find.text(zh.settingsClearAttemptsConfirmBody(3)), findsOneWidget);

    await tester.tap(find.text(zh.commonCancel));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(attempts.deleteAllCalls, 0);
    expect(find.text(zh.settingsClearAttemptsSubtitle(3)), findsOneWidget);
  });

  testWidgets('确认后 deleteAll 一次、SnackBar 报已清空 3 条、重读变空态', (tester) async {
    final attempts = _FakeAttemptRepository(db)..count = 3;
    await pumpDataSection(tester, attempts);

    await tester.tap(find.byKey(settingsClearAttemptsTileKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, zh.settingsClearAttemptsAction),
    );
    await tester.pumpAndSettle();

    expect(attempts.deleteAllCalls, 1);
    expect(find.text(zh.settingsClearAttemptsDone(3)), findsOneWidget);
    expect(find.text(zh.settingsClearAttemptsEmpty), findsOneWidget);
    // 进入页面读一次、清空后重读一次。
    expect(attempts.countAllCalls, 2);
    expect(tile(tester).enabled, isFalse);
  });

  testWidgets('countAll 抛错：副标题给读取失败，行禁用', (tester) async {
    final attempts = _FakeAttemptRepository(db)
      ..countAllError = Exception('read failed');
    await pumpDataSection(tester, attempts);

    expect(find.text(zh.settingsClearAttemptsReadFailed), findsOneWidget);
    expect(tile(tester).enabled, isFalse);

    await tester.tap(find.byKey(settingsClearAttemptsTileKey));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(attempts.deleteAllCalls, 0);
  });

  testWidgets('deleteAll 抛错：SnackBar 报清空失败，条数不变、行仍可用', (tester) async {
    final attempts = _FakeAttemptRepository(db)
      ..count = 3
      ..deleteAllError = Exception('delete failed');
    await pumpDataSection(tester, attempts);

    await tester.tap(find.byKey(settingsClearAttemptsTileKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, zh.settingsClearAttemptsAction),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(zh.settingsClearAttemptsFailed('Exception: delete failed')),
      findsOneWidget,
    );
    expect(find.text(zh.settingsClearAttemptsSubtitle(3)), findsOneWidget);
    expect(tile(tester).enabled, isTrue);
    expect(attempts.deleteAllCalls, 1);
    expect(attempts.countAllCalls, 2);
  });
}

/// 作答记录仓储替身：条数/清空可控，记录调用次数，可注入抛错。
///
/// 只实现设置页用到的两个方法；其余继承真实仓储（这些测试不会走到 DB）。
class _FakeAttemptRepository extends QuestionAttemptRepository {
  _FakeAttemptRepository(super._db);

  int count = 0;
  Object? countAllError;
  Object? deleteAllError;
  int countAllCalls = 0;
  int deleteAllCalls = 0;

  @override
  Future<int> countAll() async {
    countAllCalls++;
    final error = countAllError;
    if (error != null) {
      throw error;
    }
    return count;
  }

  @override
  Future<int> deleteAll() async {
    deleteAllCalls++;
    final error = deleteAllError;
    if (error != null) {
      throw error;
    }
    final removed = count;
    count = 0;
    return removed;
  }
}
