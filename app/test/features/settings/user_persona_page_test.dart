// 「自我描述」编辑页 + 两处入口（设置页 / 认知模型页）的页面测试。
//
// 这段文字会作为背景进入 AI 对话的系统提示，所以这里钉住三件事：
// 1) 空态不假装有内容，也不给「清除」这个无意义的按钮；
// 2) 保存/清除确实写进数据库（不是只改页面状态）；
// 3) 清除必须经过确认，取消时库里一个字节都不变。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/repository_providers.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/domain/services/cognitive/user_persona.dart';
import 'package:furnace/features/settings/presentation/settings_page.dart';
import 'package:furnace/features/settings/presentation/user_persona_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// 等 provider 的第一次读库结束（加载时是转圈）。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0;
        i < 100 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ...overrides,
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: UserPersonaPage(),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('没写过时：显示占位与字数，没有「清除」按钮', (tester) async {
    await pumpPage(tester);

    expect(find.text(zh.personaEditorHint), findsOneWidget);
    expect(find.text(zh.personaEditorPlaceholder), findsOneWidget);
    expect(find.text(zh.personaPrivacyNote), findsOneWidget);
    expect(find.text('0 / $kUserPersonaMaxChars'), findsOneWidget);
    expect(find.byKey(userPersonaClearKey), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byKey(userPersonaSaveKey)).onPressed,
      isNotNull,
    );
  });

  testWidgets('保存写进数据库（去掉首尾空白），并给出提示', (tester) async {
    await pumpPage(tester);

    await tester.enterText(
      find.byKey(userPersonaFieldKey),
      '  我是高三学生，数学想冲 120  ',
    );
    await tester.pump();
    await tester.tap(find.byKey(userPersonaSaveKey));
    await tester.pumpAndSettle();

    expect(
      await SettingsRepository(db).getUserPersona(),
      '我是高三学生，数学想冲 120',
    );
    expect(find.text(zh.personaSaveDone), findsOneWidget);
    // 保存之后「清除」才有意义，应该立刻出现，不必等 provider 重读。
    expect(find.byKey(userPersonaClearKey), findsOneWidget);
  });

  testWidgets('保存失败：显示失败原因，页面不崩', (tester) async {
    await pumpPage(
      tester,
      overrides: [
        settingsRepositoryProvider
            .overrideWithValue(_FailingSettingsRepository(db)),
      ],
    );

    await tester.enterText(find.byKey(userPersonaFieldKey), '我是初三学生');
    await tester.pump();
    await tester.tap(find.byKey(userPersonaSaveKey));
    await tester.pumpAndSettle();

    expect(find.textContaining('磁盘满了'), findsOneWidget);
    expect(find.byType(UserPersonaPage), findsOneWidget);
    expect(await SettingsRepository(db).getUserPersona(), isNull);
  });

  testWidgets('超过 8000 字：禁用保存并显示上限提示', (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byKey(userPersonaFieldKey), 'a' * 8001);
    await tester.pump();

    expect(
      tester.widget<FilledButton>(find.byKey(userPersonaSaveKey)).onPressed,
      isNull,
    );
    expect(find.text(zh.personaTooLong(kUserPersonaMaxChars)), findsOneWidget);
    expect(find.text('8001 / $kUserPersonaMaxChars'), findsOneWidget);
    expect(await SettingsRepository(db).getUserPersona(), isNull);
  });

  testWidgets('已有内容：确认后清除，库里变 null 且输入框清空', (tester) async {
    await SettingsRepository(db).updateUserPersona('我是复读生，想把理综提到 260');
    await pumpPage(tester);

    expect(find.byKey(userPersonaClearKey), findsOneWidget);
    await tester.tap(find.byKey(userPersonaClearKey));
    await tester.pumpAndSettle();

    expect(find.text(zh.personaClearConfirmTitle), findsOneWidget);
    expect(find.text(zh.personaClearConfirmBody), findsOneWidget);
    await tester.tap(find.byKey(userPersonaClearConfirmKey));
    await tester.pumpAndSettle();

    expect(await SettingsRepository(db).getUserPersona(), isNull);
    expect(find.text(zh.personaClearDone), findsOneWidget);
    expect(find.byKey(userPersonaClearKey), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(userPersonaFieldKey))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('取消清除：库里内容不变', (tester) async {
    const persona = '我是高三学生，喜欢先看解析';
    await SettingsRepository(db).updateUserPersona(persona);
    await pumpPage(tester);

    await tester.tap(find.byKey(userPersonaClearKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.commonCancel));
    await tester.pumpAndSettle();

    expect(await SettingsRepository(db).getUserPersona(), persona);
    expect(find.byKey(userPersonaClearKey), findsOneWidget);
  });

  testWidgets('设置页入口：在认知模型之后，空态给说明，点进去是编辑页', (tester) async {
    await pumpSettings(tester);

    expect(find.byKey(settingsUserPersonaTileKey), findsOneWidget);
    expect(find.text(zh.personaSettingsSubtitle), findsOneWidget);
    // 顺序：认知模型入口在上，自我描述紧随其后（用户不必猜它在哪）。
    expect(
      tester.getTopLeft(find.text(zh.cognitiveModelTitle)).dy,
      lessThan(tester.getTopLeft(find.text(zh.personaTitle)).dy),
    );

    await tester.tap(find.byKey(settingsUserPersonaTileKey));
    await tester.pumpAndSettle();

    expect(find.byType(UserPersonaPage), findsOneWidget);
  });

  testWidgets('设置页入口：写过时副标题是 40 字以内预览', (tester) async {
    final persona = '我是高三学生，数学想冲 120 分。' * 3;
    await SettingsRepository(db).updateUserPersona(persona);
    await pumpSettings(tester);

    expect(
      find.text(userPersonaPreview(persona, maxChars: 40)),
      findsOneWidget,
    );
    expect(find.text(zh.personaSettingsSubtitle), findsNothing);
  });
}

/// [updateUserPersona] 一定失败的替身：页面的失败分支必须被真的走一遍。
class _FailingSettingsRepository extends SettingsRepository {
  _FailingSettingsRepository(super.db);

  @override
  Future<void> updateUserPersona(String? text) async {
    throw StateError('磁盘满了');
  }
}
