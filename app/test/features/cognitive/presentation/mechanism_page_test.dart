/// 机制面板这一页（roadmap 切片 6 的下一步（十九）：参数公开；（二十二）：目标机制开关）。
///
/// 页面只做展示：读数由 `readMechanismPanel()` 现算（纯函数），所以这些用例
/// 把读数直接注入进去。唯一会写库的是目标机制那个开关 —— 它写一行设置
/// （`local_settings.goal_mechanism_enabled`），那一条单独用真库钉。
///
/// 这里钉的是"用户看得见"的那几条：三处装配、六个机制、点火阈值那行写清"被覆盖 +
/// 转录默认值"、记忆层那段如实说"没有号参数"、节律闸门那段如实说"不装进引擎"、
/// 末尾那句总数，以及开关翻过去之后面板跟着改口。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/domain/services/cognitive/fast_engine.dart';
import 'package:furnace/features/cognitive/application/mechanism_reader.dart';
import 'package:furnace/features/cognitive/presentation/mechanism_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// 这一页很长：给一块够高的画布，免得断言要滚半天。
void bigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget harness({
  MechanismPanel? panel,
  Future<void> Function(bool enabled)? onGoalMechanismChanged,
  bool goalMechanismEnabled = true,
}) =>
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MechanismPage(
          // 读数注入进来：这一页只做展示，不为了看一次渲染去开数据库。
          panel: panel ??
              readMechanismPanel(
                goalMechanismEnabled: goalMechanismEnabled,
              ),
          onGoalMechanismChanged: onGoalMechanismChanged,
        ),
      ),
    );

AppLocalizations l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(MechanismPage)));

void main() {
  testWidgets('页面把三处装配和六个机制都写出来', (final tester) async {
    bigSurface(tester);
    await tester.pumpWidget(harness());
    final l10n = l10nOf(tester);
    expect(find.text(l10n.mechanismPanelSetupsHeader), findsOneWidget);
    expect(find.text(l10n.mechanismPanelMechanismsHeader), findsOneWidget);
    expect(find.text(l10n.mechanismSetupLibraryDiagnosis), findsOneWidget);
    expect(find.text(l10n.mechanismSetupProblemEvaluator), findsOneWidget);
    expect(find.text(l10n.mechanismSetupRunRehearsal), findsOneWidget);
    for (final name in <String>[
      l10n.mechanismNameShunting,
      l10n.mechanismNameCapacity,
      l10n.mechanismNameIgnition,
      l10n.mechanismNameGoal,
      l10n.mechanismNameRhythm,
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    // 记忆层这一条会出现两次：机制卡片一次，演练那一跑只装了它一个，那行名字就是它
    // 自己（另两处装配的名字是拼在一起的，所以整串匹配只会命中机制卡片）。
    expect(find.text(l10n.mechanismNameMemory), findsNWidgets(2));
    // 三处装配各一行"装了 N 个机制"。
    expect(find.text(l10n.mechanismPanelSetupCount(4)), findsOneWidget);
    expect(find.text(l10n.mechanismPanelSetupCount(5)), findsOneWidget);
    expect(find.text(l10n.mechanismPanelSetupCount(1)), findsOneWidget);
  });

  testWidgets('点火阈值那行：写清被覆盖、值 0、转录默认值 0.05', (final tester) async {
    bigSurface(tester);
    await tester.pumpWidget(harness());
    final l10n = l10nOf(tester);
    expect(find.text('attention.ignition.T_ign'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    expect(find.text(l10n.mechanismPanelOverridden), findsWidgets);
    expect(
      find.text('${l10n.mechanismPanelTranscribed} 0.05'),
      findsWidgets,
    );
    // 覆盖只此一处：装配卡片上的覆盖清单里也写着它（三处装配都用同一份覆盖）。
    expect(find.text(l10n.mechanismPanelOverridesHeader), findsNWidgets(3));
  });

  testWidgets('记忆层那段如实说：没有号参数', (final tester) async {
    bigSurface(tester);
    await tester.pumpWidget(harness());
    final l10n = l10nOf(tester);
    expect(find.text('memory.dsr'), findsOneWidget);
    expect(find.text(l10n.mechanismPanelNoParams), findsOneWidget);
  });

  testWidgets('节律闸门那段如实说：不装进引擎', (final tester) async {
    bigSurface(tester);
    await tester.pumpWidget(harness());
    final l10n = l10nOf(tester);
    expect(find.text('rhythm.gate'), findsOneWidget);
    expect(find.text(l10n.mechanismPanelOnlyOutside), findsOneWidget);
  });

  testWidgets('末尾那句总数与读数一致', (final tester) async {
    bigSurface(tester);
    await tester.pumpWidget(harness());
    final l10n = l10nOf(tester);
    final panel = readMechanismPanel();
    expect(
      find.text(
        l10n.mechanismPanelSummary(panel.paramCount, panel.uncalibratedCount),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.mechanismPanelUncalibrated), findsWidgets);
  });

  testWidgets('未标定与已标定都要出现：不是所有数字都没出处', (final tester) async {
    bigSurface(tester);
    await tester.pumpWidget(harness());
    final l10n = l10nOf(tester);
    expect(find.text(l10n.mechanismPanelCalibrated), findsWidgets);
    expect(find.text(l10n.mechanismPanelUncalibrated), findsWidgets);
  });

  testWidgets('机制 id 用的是内核的写法，页面不自己起名', (final tester) async {
    bigSurface(tester);
    await tester.pumpWidget(harness());
    expect(find.text(FastMechanisms.capacity), findsOneWidget);
    expect(find.text(FastMechanisms.shunting), findsOneWidget);
  });

  group('目标机制开关（roadmap §3 第 8 行第一个用户侧开关）', () {
    bool switchValue(WidgetTester tester) =>
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value;

    testWidgets('默认画成"装"，并写清关掉之后会变什么', (final tester) async {
      bigSurface(tester);
      await tester.pumpWidget(harness());
      final l10n = l10nOf(tester);

      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(switchValue(tester), isTrue);
      expect(find.text(l10n.mechanismSwitchGoalTitle), findsOneWidget);
      expect(find.text(l10n.mechanismSwitchGoalBody), findsOneWidget);
      expect(find.text(l10n.mechanismDisabledBySetting), findsNothing);
      expect(find.text(l10n.mechanismPanelSetupCount(4)), findsOneWidget);
    });

    testWidgets('关掉之后：那一跑只写 3 个机制，目标机制那张卡片说"你关掉了"', (final tester) async {
      bigSurface(tester);
      await tester.pumpWidget(harness(goalMechanismEnabled: false));
      final l10n = l10nOf(tester);

      expect(switchValue(tester), isFalse);
      expect(find.text(l10n.mechanismPanelSetupCount(3)), findsOneWidget);
      expect(find.text(l10n.mechanismPanelSetupCount(4)), findsNothing);
      // 全页只有一张卡片挂这句：目标机制那一张，且要说清关的是哪一处。
      expect(
          find.textContaining(l10n.mechanismDisabledBySetting), findsOneWidget);
      expect(
        find.textContaining(l10n.mechanismSetupLibraryDiagnosis),
        findsWidgets,
      );
      // 题目定价那一跑仍然装着它 —— 关的是一处，不是全部。
      expect(find.textContaining(l10n.mechanismPanelInstalledIn), findsWidgets);
    });

    testWidgets('翻一下开关：回调收到新值，页面当场按新值画（不等写库往返）', (final tester) async {
      bigSurface(tester);
      final picked = <bool>[];
      await tester.pumpWidget(
        harness(onGoalMechanismChanged: (final enabled) async {
          picked.add(enabled);
        }),
      );

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(picked, <bool>[false]);
      expect(switchValue(tester), isFalse, reason: '注入的读数没变，但用户刚翻过就要先画出来');

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(picked, <bool>[false, true]);
      expect(switchValue(tester), isTrue);
    });

    testWidgets('翻开关真的落库：写进 local_settings，重画后那一跑只剩 3 个机制',
        (final tester) async {
      bigSurface(tester);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = SettingsRepository(db);
      await settings.ensureSettings(language: 'zh');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MechanismPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = l10nOf(tester);
      expect(find.text(l10n.mechanismPanelSetupCount(4)), findsOneWidget);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      // 库里的值：NULL -> false（用户真的选过了，不是"没选过"）。
      expect((await settings.getSettings())!.goalMechanismEnabled, isFalse);
      // 面板自己重读了一遍：那一跑少装了一个。
      expect(find.text(l10n.mechanismPanelSetupCount(3)), findsOneWidget);
      expect(find.text(l10n.mechanismPanelSetupCount(4)), findsNothing);
      expect(
        find.textContaining(l10n.mechanismDisabledBySetting),
        findsOneWidget,
      );
    });
  });
}
