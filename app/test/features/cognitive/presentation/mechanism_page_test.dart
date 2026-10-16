/// 机制面板这一页（roadmap 切片 6 的下一步（十九）：参数公开；（二十二）：目标机制开关；
/// （二十六）：第一个滑块）。
///
/// 页面只做展示：读数由 `readMechanismPanel()` 现算（纯函数），所以这些用例
/// 把读数直接注入进去。会写库的是目标机制那个开关和那一根滑块 —— 它们各写一行设置
/// （`local_settings.goal_mechanism_enabled` / `local_settings.goal_beta`），
/// 那两条单独用真库钉。
///
/// 这里钉的是"用户看得见"的那几条：三处装配、六个机制、点火阈值那行写清"被覆盖 +
/// 转录默认值"、记忆层那段如实说"没有号参数"、节律闸门那段如实说"不装进引擎"、
/// 末尾那句总数、开关翻过去之后面板跟着改口，以及滑块拖过/回到出厂值的改口。
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
  Future<void> Function(double? beta)? onGoalBetaChanged,
  bool goalMechanismEnabled = true,
  double? goalBeta,
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
                goalBeta: goalBeta,
              ),
          onGoalMechanismChanged: onGoalMechanismChanged,
          onGoalBetaChanged: onGoalBetaChanged,
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

  group('目标机制的第一个滑块（roadmap §3 第 8 行第一个用户侧滑块）', () {
    Slider sliderOf(WidgetTester tester) =>
        tester.widget<Slider>(find.byType(Slider));

    testWidgets('默认画成"出厂值"：位置就是转录默认值，两端来自参数表', (final tester) async {
      bigSurface(tester);
      await tester.pumpWidget(harness());
      final l10n = l10nOf(tester);

      expect(find.byType(Slider), findsOneWidget);
      expect(find.text(l10n.mechanismGoalBetaTitle), findsOneWidget);
      expect(find.text(l10n.mechanismGoalBetaBody), findsOneWidget);
      // "这一个数谁会读"必须写出来：题目定价那一跑也走同一条折法。
      expect(find.text(l10n.mechanismGoalBetaApplies), findsOneWidget);
      expect(find.text(l10n.mechanismGoalBetaShipped), findsOneWidget);
      expect(find.text(l10n.mechanismGoalBetaFromSetting), findsNothing);
      expect(find.text(l10n.mechanismGoalBetaReset), findsNothing);

      final slider = sliderOf(tester);
      expect(slider.value, 0.3, reason: '没调过就是转录默认值');
      expect(slider.min, 0);
      expect(slider.max, 3);
      expect(slider.onChanged, isNotNull);
      // 出厂值这一句与参数行上的值都在，所以至少两处写着 0.3。
      expect(find.text('0.3'), findsWidgets);
    });

    testWidgets('调过之后：位置跟着走，标"你调的"，还给一个"回到出厂值"', (final tester) async {
      bigSurface(tester);
      await tester.pumpWidget(harness(goalBeta: 1.2));
      final l10n = l10nOf(tester);

      expect(sliderOf(tester).value, 1.2);
      expect(find.text(l10n.mechanismGoalBetaFromSetting), findsWidgets);
      expect(find.text(l10n.mechanismGoalBetaShipped), findsNothing);
      expect(find.text(l10n.mechanismGoalBetaReset), findsOneWidget);
      expect(find.text('1.2'), findsWidgets);
      // 转录默认值那行还在（滑块不改转录默认值）。
      expect(
        find.text('${l10n.mechanismPanelTranscribed} 0.3'),
        findsWidgets,
      );
    });

    testWidgets('拖一下：回调收到新值，页面当场按新值画（不等写库往返）', (final tester) async {
      bigSurface(tester);
      final picked = <double?>[];
      await tester.pumpWidget(
        harness(
          onGoalBetaChanged: (final beta) async {
            picked.add(beta);
          },
        ),
      );
      final l10n = l10nOf(tester);
      expect(sliderOf(tester).value, 0.3);

      final finder = find.byType(Slider);
      await tester.tapAt(tester.getCenter(finder) + const Offset(80, 0));
      await tester.pumpAndSettle();

      expect(picked, hasLength(1), reason: '拖完才回调一次（onChangeEnd）');
      expect(picked.single, greaterThan(0.3));
      expect(sliderOf(tester).value, picked.single,
          reason: '注入的读数没变，但用户刚拖过就要先画出来');
      expect(find.text(l10n.mechanismGoalBetaFromSetting), findsWidgets);
      expect(find.text(l10n.mechanismGoalBetaReset), findsOneWidget);
    });

    testWidgets('点"回到出厂值"：回调收到 null（不是 0.3）', (final tester) async {
      bigSurface(tester);
      final picked = <double?>[];
      await tester.pumpWidget(
        harness(
          goalBeta: 1.2,
          onGoalBetaChanged: (final beta) async {
            picked.add(beta);
          },
        ),
      );
      final l10n = l10nOf(tester);

      await tester.tap(find.text(l10n.mechanismGoalBetaReset));
      await tester.pumpAndSettle();

      expect(picked, <double?>[null]);
      expect(sliderOf(tester).value, 0.3);
      expect(find.text(l10n.mechanismGoalBetaShipped), findsOneWidget);
      expect(find.text(l10n.mechanismGoalBetaReset), findsNothing);
    });

    testWidgets('机制被关掉时滑块禁用，并说清"关的是装不装，不是值"', (final tester) async {
      bigSurface(tester);
      await tester
          .pumpWidget(harness(goalMechanismEnabled: false, goalBeta: 1.2));
      final l10n = l10nOf(tester);

      expect(sliderOf(tester).value, 1.2, reason: '关掉机制不等于把用户调的值抹掉');
      expect(sliderOf(tester).onChanged, isNull);
      expect(find.text(l10n.mechanismGoalBetaOffNote), findsOneWidget);
      expect(find.text(l10n.mechanismSwitchGoalTitle), findsOneWidget);
    });

    testWidgets('拖了真的落库；点"回到出厂值"写回 NULL，重画后面板跟着改口', (final tester) async {
      bigSurface(tester);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = SettingsRepository(db);
      await settings.ensureSettings(language: 'zh');
      await settings.updateGoalBeta(1.2);

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
      expect(sliderOf(tester).value, 1.2);
      expect(find.text(l10n.mechanismGoalBetaFromSetting), findsWidgets);

      // 拖一下：库里落的是回调收到的那一个值。
      final finder = find.byType(Slider);
      await tester.tapAt(tester.getCenter(finder) + const Offset(80, 0));
      await tester.pumpAndSettle();
      final stored = (await settings.getSettings())!.goalBeta;
      expect(stored, isNotNull);
      expect(stored, greaterThan(1.2));
      expect(sliderOf(tester).value, stored);

      // 回到出厂值：写回 NULL，面板重读后没有"你调的"了。
      await tester.tap(find.text(l10n.mechanismGoalBetaReset));
      await tester.pumpAndSettle();
      expect((await settings.getSettings())!.goalBeta, isNull);
      expect(find.text(l10n.mechanismGoalBetaShipped), findsOneWidget);
      expect(find.text(l10n.mechanismGoalBetaFromSetting), findsNothing);
    });
  });
}
