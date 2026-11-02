/// 手机宽度下的外壳布局：5 个主入口 + 「更多」面板，低频入口不挤底部导航。
///
/// 用户反馈（m29307）"UI 布局有很多可以提升的地方"：这一轮 AI 入口改为常驻
/// （轮次一百八十八），知识库下沉设置、MindNet 成为顶层模块，目的地仍是 8 个。
/// 桌面是 NavigationRail（全标签），手机是 NavigationBar
/// （`labelBehavior: onlyShowSelected`）——**这个文件守的就是"窄屏不溢出、题库
/// 点得到"**：布局回归在 Flutter 里不会抛异常，只会画出黄黑条或压缩文字，
/// 所以要看的是渲染与路由，不是"没崩"。
library;

import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/app/shell/home_shell.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/questions/presentation/question_bank_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  testWidgets('窄屏：底部导航能渲染八个目的地，题库可点开', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          aiEnabledProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bar = find.byType(NavigationBar);
    expect(bar, findsOneWidget);
    expect(
      find.descendant(of: bar, matching: find.byType(NavigationDestination)),
      findsNWidgets(5),
      reason: '手机只放 Thread、复习、题库、MindNet、更多 5 个入口',
    );

    // 未选中的目的地只画图标，所以按图标点「题库」。
    await tester.tap(
      find.descendant(
        of: bar,
        matching: find.byIcon(Icons.quiz_outlined),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(QuestionBankPage), findsOneWidget);

    // 「更多」面板里能到设置（低频入口不占主 Tab，但一步可达）。
    await tester.tap(
      find.descendant(of: bar, matching: find.byIcon(Icons.more_horiz)),
    );
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsWidgets);
  });
}
