// 能力动作词表编辑页（task-29）的 UI 测试。
//
// 页面把 domain 层的词表编辑逻辑（capability_action_overlay_editor.dart）接到
// UI 上：内置动作只读、自定义动作可增删改/排序/粘贴导入，保存落 local_settings。
// 数据源用真实的内存 SQLite（AppDatabase.forTesting）；只有「保存失败 / 加载失败」
// 两个用例用仓储替身注入异常。
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/domain/services/reasoning/capability_action.dart';
import 'package:furnace/domain/services/reasoning/capability_action_overlay.dart';
import 'package:furnace/features/questions/application/capability_vocabulary_store.dart';
import 'package:furnace/features/settings/presentation/capability_vocabulary_page.dart';
import 'package:furnace/features/settings/presentation/settings_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settingsRepository;
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settingsRepository = SettingsRepository(db);
  });

  tearDown(() => db.close());

  CustomCapabilityAction action(String key, String labelZh) =>
      CustomCapabilityAction(key: key, labelZh: labelZh);

  Future<void> seedOverlay(List<CustomCapabilityAction> actions) async {
    await settingsRepository.ensureSettings();
    await settingsRepository.updateCapabilityActionOverlayJson(
      jsonEncode(CapabilityActionOverlay(customActions: actions).toJson()),
    );
  }

  /// 页面是一长列卡片 + 底部固定操作条：视口给足，省得按钮被滚出屏幕。
  void useLargeView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget wrap(Widget home, {List<Override> overrides = const <Override>[]}) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db), ...overrides],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    List<Override> overrides = const <Override>[],
  }) async {
    useLargeView(tester);
    await tester.pumpWidget(
      wrap(const CapabilityVocabularyPage(), overrides: overrides),
    );
    await tester.pumpAndSettle();
  }

  /// 等异步动作落地（保存/删除要等数据库 future），比 pumpAndSettle 稳。
  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    int maxPumps = 80,
  }) async {
    for (var i = 0; i < maxPumps; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (finder.evaluate().isNotEmpty) {
        return;
      }
    }
  }

  bool saveEnabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.byKey(capabilityVocabularySaveButtonKey))
          .onPressed !=
      null;

  Future<void> addAction(
    WidgetTester tester, {
    required String key,
    required String labelZh,
  }) async {
    await tester.tap(find.byKey(capabilityVocabularyAddButtonKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(capabilityVocabularyKeyFieldKey), key);
    await tester.enterText(
      find.byKey(capabilityVocabularyLabelZhFieldKey),
      labelZh,
    );
    await tester.tap(find.byKey(capabilityVocabularyDialogSaveKey));
    await tester.pumpAndSettle();
  }

  testWidgets('内置动作只读分组 + 空自定义态', (tester) async {
    await pumpPage(tester);

    expect(
      find.text(
        zh.capabilityVocabularyBuiltInSection(CapabilityAction.catalog.length),
      ),
      findsOneWidget,
    );
    expect(find.text(zh.capabilityVocabularyCustomSection(0)), findsOneWidget);
    expect(find.text(zh.capabilityVocabularyCustomEmpty), findsOneWidget);
    expect(find.text(zh.capabilityVocabularyBuiltInNote), findsOneWidget);
    expect(saveEnabled(tester), isFalse);

    // 默认收起；点开能看到内置动作的中文名。
    await tester.tap(find.byKey(capabilityVocabularyBuiltInTileKey));
    await tester.pumpAndSettle();
    expect(find.text(CapabilityAction.catalog.first.labelZh), findsOneWidget);
  });

  testWidgets('种子自定义动作渲染；未改动时保存/放弃都禁用', (tester) async {
    await seedOverlay([action('alpha', '甲动作'), action('beta', '乙动作')]);
    await pumpPage(tester);

    expect(
      find.byKey(capabilityVocabularyCustomRowKey('alpha')),
      findsOneWidget,
    );
    expect(find.text('甲动作'), findsOneWidget);
    expect(find.text('乙动作'), findsOneWidget);
    expect(find.text(zh.capabilityVocabularyCustomSection(2)), findsOneWidget);
    expect(find.text(zh.capabilityVocabularyDirty), findsNothing);
    expect(saveEnabled(tester), isFalse);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(capabilityVocabularyRevertButtonKey),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('新增动作：填 key 与中文名后出现在列表，保存按钮变可用', (tester) async {
    await pumpPage(tester);
    await addAction(tester, key: 'force_diagram_analysis', labelZh: '画图分析');

    expect(
      find.byKey(capabilityVocabularyCustomRowKey('force_diagram_analysis')),
      findsOneWidget,
    );
    expect(find.text('画图分析'), findsOneWidget);
    expect(find.text(zh.capabilityVocabularyCustomSection(1)), findsOneWidget);
    expect(find.text(zh.capabilityVocabularyDirty), findsOneWidget);
    expect(saveEnabled(tester), isTrue);
  });

  testWidgets('编辑动作：改中文名后列表更新并进入未保存态', (tester) async {
    await seedOverlay([action('alpha', '甲动作')]);
    await pumpPage(tester);

    await tester.tap(find.byKey(capabilityVocabularyEditKey('alpha')));
    await tester.pumpAndSettle();
    expect(find.text(zh.capabilityVocabularyEditTitle), findsOneWidget);
    await tester.enterText(
      find.byKey(capabilityVocabularyLabelZhFieldKey),
      '甲动作（改）',
    );
    await tester.tap(find.byKey(capabilityVocabularyDialogSaveKey));
    await tester.pumpAndSettle();

    expect(find.text('甲动作（改）'), findsOneWidget);
    expect(find.text('甲动作'), findsNothing);
    expect(find.text(zh.capabilityVocabularyDirty), findsOneWidget);
    expect(saveEnabled(tester), isTrue);
  });

  testWidgets('删除动作：列表回到空态并进入未保存态', (tester) async {
    await seedOverlay([action('alpha', '甲动作')]);
    await pumpPage(tester);

    await tester.tap(find.byKey(capabilityVocabularyDeleteKey('alpha')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(capabilityVocabularyCustomRowKey('alpha')),
      findsNothing,
    );
    expect(find.text(zh.capabilityVocabularyCustomEmpty), findsOneWidget);
    expect(find.text(zh.capabilityVocabularyDirty), findsOneWidget);
  });

  testWidgets('上移/下移改变列表顺序', (tester) async {
    await seedOverlay([action('alpha', '甲动作'), action('beta', '乙动作')]);
    await pumpPage(tester);

    double dy(String key) =>
        tester.getTopLeft(find.byKey(capabilityVocabularyCustomRowKey(key))).dy;
    expect(dy('alpha'), lessThan(dy('beta')));

    await tester.tap(find.byKey(capabilityVocabularyMoveDownKey('alpha')));
    await tester.pumpAndSettle();
    expect(dy('alpha'), greaterThan(dy('beta')));

    await tester.tap(find.byKey(capabilityVocabularyMoveUpKey('alpha')));
    await tester.pumpAndSettle();
    expect(dy('alpha'), lessThan(dy('beta')));
  });

  testWidgets('粘贴 JSON：语法错误给出解析失败提示', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(capabilityVocabularyImportButtonKey));
    await tester.pumpAndSettle();
    expect(find.text(zh.capabilityVocabularyImportTitle), findsOneWidget);
    await tester.enterText(
      find.byKey(capabilityVocabularyImportFieldKey),
      '{oops',
    );
    await tester.tap(find.byKey(capabilityVocabularyImportConfirmKey));
    await tester.pumpAndSettle();

    expect(find.textContaining('JSON 解析失败'), findsOneWidget);
  });

  testWidgets('粘贴 JSON：语义非法条目进 issues 卡片，不写入列表', (tester) async {
    await pumpPage(tester);

    final raw = jsonEncode({
      'customActions': [
        {'key': 'Bad-Key', 'labelZh': '坏条目'},
      ],
    });
    await tester.tap(find.byKey(capabilityVocabularyImportButtonKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(capabilityVocabularyImportFieldKey), raw);
    await tester.tap(find.byKey(capabilityVocabularyImportConfirmKey));
    await tester.pumpAndSettle();

    expect(find.text(zh.capabilityVocabularyIssuesTitle(1)), findsOneWidget);
    expect(find.textContaining('Bad-Key'), findsOneWidget);
    expect(
      find.byKey(capabilityVocabularyCustomRowKey('Bad-Key')),
      findsNothing,
    );
    expect(find.text(zh.capabilityVocabularyCustomSection(0)), findsOneWidget);
  });

  testWidgets('保存：写入 local_settings，提示已保存，按钮回到禁用', (tester) async {
    await pumpPage(tester);
    await addAction(tester, key: 'draw_diagram', labelZh: '画图');
    await tester.tap(find.byKey(capabilityVocabularySaveButtonKey));

    await pumpUntil(tester, find.text(zh.capabilityVocabularySaved));
    expect(find.text(zh.capabilityVocabularySaved), findsOneWidget);

    final settings = await settingsRepository.getSettings();
    expect(settings?.capabilityActionOverlayJson, contains('draw_diagram'));
    expect(saveEnabled(tester), isFalse);
    expect(find.text(zh.capabilityVocabularyDirty), findsNothing);
  });

  testWidgets('保存失败：提示错误并保留未保存态', (tester) async {
    await pumpPage(
      tester,
      overrides: [
        capabilityVocabularyStoreProvider.overrideWithValue(
          _ThrowingSaveStore(settingsRepository),
        ),
      ],
    );
    await addAction(tester, key: 'draw_diagram', labelZh: '画图');
    await tester.tap(find.byKey(capabilityVocabularySaveButtonKey));

    await pumpUntil(tester, find.textContaining('保存失败'));
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.textContaining('disk full'), findsOneWidget);
    expect(find.text(zh.capabilityVocabularyDirty), findsOneWidget);
    expect(saveEnabled(tester), isTrue);
  });

  testWidgets('加载失败：页面显示读词表失败的原文', (tester) async {
    await pumpPage(
      tester,
      overrides: [
        capabilityVocabularyStoreProvider.overrideWithValue(
          _ThrowingLoadStore(settingsRepository),
        ),
      ],
    );

    expect(find.textContaining('读词表失败'), findsOneWidget);
    expect(find.textContaining('db broken'), findsOneWidget);
    expect(find.byKey(capabilityVocabularyAddButtonKey), findsNothing);
  });

  testWidgets('设置页有词表入口，点进去就是编辑页', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(const SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text(zh.capabilityVocabularySettingsTitle), findsOneWidget);
    expect(find.text(zh.capabilityVocabularySettingsHint), findsOneWidget);

    await tester.tap(find.text(zh.capabilityVocabularySettingsTitle));
    await tester.pumpAndSettle();
    expect(find.byType(CapabilityVocabularyPage), findsOneWidget);
  });

  testWidgets('退出未保存改动：先确认再离开', (tester) async {
    useLargeView(tester);
    await tester.pumpWidget(wrap(const _OpenVocabularyButton()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(find.byType(CapabilityVocabularyPage), findsOneWidget);

    await addAction(tester, key: 'draw_diagram', labelZh: '画图');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    // 底部「有未保存的修改」提示和对话框标题是同一句，断言要限定在对话框里。
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(zh.capabilityVocabularyLeaveTitle),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(zh.capabilityVocabularyLeaveBody),
      ),
      findsOneWidget,
    );

    // 「留下」：页面还在。
    await tester.tap(find.text(zh.capabilityVocabularyLeaveStay));
    await tester.pumpAndSettle();
    expect(find.byType(CapabilityVocabularyPage), findsOneWidget);

    // 再退一次，这回「放弃并离开」。
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.capabilityVocabularyLeaveDiscard));
    await tester.pumpAndSettle();
    expect(find.byType(CapabilityVocabularyPage), findsNothing);
    expect(find.byType(ElevatedButton), findsOneWidget);
  });
}

/// 用来从根路由 push 词表编辑页：这样 AppBar 才有返回按钮，能测退出确认。
class _OpenVocabularyButton extends StatelessWidget {
  const _OpenVocabularyButton();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const CapabilityVocabularyPage(),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

/// 保存时抛错的替身：读走真实仓储（页面能正常渲染），只在 save 上报错。
class _ThrowingSaveStore extends CapabilityVocabularyStore {
  // 父类构造参数名是私有的，没法写成 super parameter。
  // ignore: use_super_parameters
  _ThrowingSaveStore(SettingsRepository settings) : super(settings);

  @override
  Future<void> save(CapabilityActionOverlay overlay) async {
    throw StateError('disk full');
  }
}

/// 读词表就抛错的替身：验证页面进入错误态而不是白屏。
class _ThrowingLoadStore extends CapabilityVocabularyStore {
  // ignore: use_super_parameters
  _ThrowingLoadStore(SettingsRepository settings) : super(settings);

  @override
  Future<CapabilityActionOverlay> load() async {
    throw StateError('db broken');
  }
}
