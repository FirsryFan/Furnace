/// 机制面板这一页（roadmap 切片 6 的下一步（十九）：参数公开）。
///
/// 页面只做展示：读数由 `readMechanismPanel()` 现算（纯函数）。这里钉的是
/// "用户看得见"的那几条：三处装配、六个机制、点火阈值那行写清"被覆盖 + 转录默认值"、
/// 记忆层那段如实说"没有号参数"、节律闸门那段如实说"不装进引擎"、末尾那句总数。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

Widget harness() => const MaterialApp(
      locale: Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MechanismPage(),
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
}
