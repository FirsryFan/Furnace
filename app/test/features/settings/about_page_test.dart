// Settings -> About.
//
// The page exists so four facts are readable in the app: the build, where the
// data is, which code paths reach the network, and what this build does not do.
// The version is the interesting one to pin, because it is a hand-maintained
// constant (see app_info_test.dart for the comparison against pubspec.yaml);
// here the point is that the page actually shows it and the directory, rather
// than a placeholder.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/core/app_info.dart';
import 'package:furnace/features/settings/presentation/about_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');

  late Directory supportDir;

  setUp(() {
    supportDir = Directory.systemTemp.createTempSync('furnace_about_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'getApplicationSupportDirectory'
          ? supportDir.path
          : null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (supportDir.existsSync()) {
      supportDir.deleteSync(recursive: true);
    }
  });

  Future<void> pumpPage(WidgetTester tester, {Locale locale = const Locale('zh')}) {
    // The four cards are taller than the default 800x600 viewport, and a
    // ListView does not build what is far off-screen: without this the "known
    // gaps" card simply would not exist in the tree.
    tester.view.physicalSize = const Size(1200, 4000);
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

  testWidgets('shows the build, the data directory, egress and the gaps',
      (tester) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();

    expect(find.text('$kAppVersion（构建 $kAppBuildNumber）'), findsOneWidget);
    expect(find.text('出网范围'), findsOneWidget);
    expect(find.text('已知未做'), findsOneWidget);
    // The directory is resolved at runtime, not a constant.
    expect(find.text(supportDir.path), findsOneWidget);
    // The gaps list has to name the two things most likely to be assumed.
    expect(find.textContaining('DOCX'), findsOneWidget);
    expect(find.textContaining('networkAllow'), findsOneWidget);
  });

  testWidgets('the English page still shows the real version', (tester) async {
    await pumpPage(tester, locale: const Locale('en'));
    await tester.pumpAndSettle();

    expect(
      find.text('$kAppVersion (build $kAppBuildNumber)'),
      findsOneWidget,
    );
    expect(find.text('Known gaps'), findsOneWidget);
    expect(find.text(supportDir.path), findsOneWidget);
  });
}
