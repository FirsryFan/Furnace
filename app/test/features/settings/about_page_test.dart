// Settings -> About.
//
// The page is deliberately small now: the version, the open-source licence and
// the links a user may want. Two kinds of assertion matter here, and they are
// different failures:
//  * the facts a user needs are actually on screen (version, MIT, the two URLs);
//  * the developer material that used to live here is gone - not hidden, gone -
//    so the page cannot quietly grow back into a build report.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/core/app_info.dart';
import 'package:furnace/features/settings/presentation/about_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPage(
    WidgetTester tester, {
    Locale locale = const Locale('zh'),
  }) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AboutPage(),
      ),
    );
  }

  List<MethodCall> captureClipboard(WidgetTester tester) {
    final calls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    return calls;
  }

  String? copiedText(List<MethodCall> calls) {
    final setData = calls
        .where((call) => call.method == 'Clipboard.setData')
        .toList(growable: false);
    if (setData.isEmpty) return null;
    final arguments = setData.last.arguments;
    if (arguments is! Map) return null;
    final text = arguments['text'];
    return text is String ? text : null;
  }

  testWidgets('a user sees the version, the licence and the two links',
      (tester) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();

    // The version itself, without the build number (that is an internal ID).
    expect(find.text(kAppVersion), findsOneWidget);
    expect(find.text('版本'), findsOneWidget);
    // Open source, in plain words, plus the licence name.
    expect(find.text('开源与许可'), findsOneWidget);
    expect(find.textContaining('MIT 许可'), findsOneWidget);
    // Links are on screen, not just copyable: the user can read the URL.
    expect(find.text(kAppRepoUrl), findsOneWidget);
    expect(find.text(kAppIssuesUrl), findsOneWidget);
    expect(find.text('源代码'), findsOneWidget);
    expect(find.text('反馈问题'), findsOneWidget);
    expect(find.text('第三方开源许可'), findsOneWidget);
  });

  testWidgets('the developer material that used to be here is gone',
      (tester) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();

    // Data directory, network egress and the "known gaps" backlog all ended by
    // pointing at the developer docs; none of that belongs on About.
    expect(find.textContaining('出网范围'), findsNothing);
    expect(find.textContaining('已知未做'), findsNothing);
    expect(find.textContaining('应用数据目录'), findsNothing);
    expect(find.textContaining('furnace.db'), findsNothing);
    expect(find.textContaining('开发文档'), findsNothing);
    // The build number is an internal ID, not something a user needs.
    expect(find.textContaining('构建'), findsNothing);
  });

  testWidgets('tapping a link copies it and says so', (tester) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();
    final calls = captureClipboard(tester);

    await tester.tap(find.text('源代码'));
    await tester.pumpAndSettle();

    expect(copiedText(calls), kAppRepoUrl);
    expect(find.text('链接已复制'), findsOneWidget);
  });

  testWidgets('tapping the licence row opens the licence list', (tester) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('第三方开源许可'));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('the English page shows the same facts', (tester) async {
    await pumpPage(tester, locale: const Locale('en'));
    await tester.pumpAndSettle();

    expect(find.text(kAppVersion), findsOneWidget);
    expect(find.text('Open source and license'), findsOneWidget);
    expect(find.textContaining('MIT license'), findsOneWidget);
    expect(find.text(kAppRepoUrl), findsOneWidget);
    expect(find.text(kAppIssuesUrl), findsOneWidget);
    expect(find.text('Known gaps'), findsNothing);
    expect(find.text('Network egress'), findsNothing);
  });
}
