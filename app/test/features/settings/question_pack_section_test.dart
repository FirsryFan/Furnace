/// 设置页题库包（`.tqb`）小节：导出/导入两条通路、取消、坏包、结果对话框、
/// 防重入，以及新增文案的占位符是否真的插值。
///
/// 真服务要 DB、图片目录与标签仓库，这里只测 UI 契约，所以用
/// `support/question_pack_fakes.dart` 里的接口替身；文件选择器的平台实例必须
/// 换掉，否则 `FilePicker.saveFile` 在测试环境直接 `UnimplementedError`。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/questions/application/question_pack_service.dart';
import 'package:furnace/features/settings/presentation/data_section.dart';
import 'package:furnace/features/settings/presentation/settings_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

import 'support/question_pack_fakes.dart';

void main() {
  late AppDatabase db;
  late AppLocalizations zh;
  late AppLocalizations en;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pumpSettings(
    WidgetTester tester, {
    required FakeQuestionPackService service,
    FakeQuestionPackPicker? picker,
  }) async {
    final filePicker = picker ?? FakeQuestionPackPicker();
    final previous = FilePickerPlatform.instance;
    FilePickerPlatform.instance = filePicker;
    addTearDown(() => FilePickerPlatform.instance = previous);

    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          questionPackServiceProvider.overrideWithValue(service),
        ],
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

  ListTile tile(WidgetTester tester, String text) =>
      tester.widget<ListTile>(find.widgetWithText(ListTile, text));

  testWidgets('设置页有题库包区块和导出/导入两条入口', (tester) async {
    final service = FakeQuestionPackService();
    await pumpSettings(tester, service: service);

    expect(find.text(zh.settingsQuestionPackSection), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackExport), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackExportHint), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackImport), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackImportHint), findsOneWidget);
    expect(service.exportCalls, 0);
  });

  testWidgets('导出：保存 furnace-*.tqb 并提示题数、图片数、大小', (tester) async {
    final service = FakeQuestionPackService();
    final picker = FakeQuestionPackPicker();
    await pumpSettings(tester, service: service, picker: picker);

    await tester.tap(find.text(zh.settingsQuestionPackExport));
    await tester.pumpAndSettle();

    expect(service.exportCalls, 1);
    expect(picker.saveCalls, 1);
    expect(picker.savedFileName, startsWith('furnace-'));
    expect(picker.savedFileName, endsWith('.tqb'));
    expect(picker.savedBytes, service.exportResult.bytes);
    expect(picker.savedMimeType, 'application/octet-stream');
    expect(
      find.text(
        zh.settingsQuestionPackExportDone(
          service.exportResult.questionCount,
          service.exportResult.mediaCount,
          questionPackSizeText(service.exportResult.bytes.length),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('导出：用户在保存框取消时不提示成功', (tester) async {
    final service = FakeQuestionPackService();
    final picker = FakeQuestionPackPicker()..cancelSave = true;
    await pumpSettings(tester, service: service, picker: picker);

    await tester.tap(find.text(zh.settingsQuestionPackExport));
    await tester.pumpAndSettle();

    expect(picker.saveCalls, 1);
    expect(
      find.text(zh.settingsQuestionPackExportDone(2, 1, '4 B')),
      findsNothing,
    );
  });

  testWidgets('导出：空题库不弹保存框，只提示没有可导出的内容', (tester) async {
    final service = FakeQuestionPackService()
      ..exportResult = QuestionPackExportResult(
        bytes: Uint8List(0),
        questionCount: 0,
        mediaCount: 0,
      );
    final picker = FakeQuestionPackPicker();
    await pumpSettings(tester, service: service, picker: picker);

    await tester.tap(find.text(zh.settingsQuestionPackExport));
    await tester.pumpAndSettle();

    expect(service.exportCalls, 1);
    expect(picker.saveCalls, 0);
    expect(find.text(zh.settingsQuestionPackExportEmpty), findsOneWidget);
  });

  testWidgets('导出：服务抛错时提示前缀和错误', (tester) async {
    final service = FakeQuestionPackService()
      ..exportError = StateError('no database');
    await pumpSettings(tester, service: service);

    await tester.tap(find.text(zh.settingsQuestionPackExport));
    await tester.pumpAndSettle();

    expect(find.textContaining('no database'), findsOneWidget);
  });

  testWidgets('导入：选文件对话框只收 .tqb；取消后不读也不导入', (tester) async {
    final service = FakeQuestionPackService();
    final picker = FakeQuestionPackPicker(picked: <PlatformFile>[]);
    await pumpSettings(tester, service: service, picker: picker);

    await tester.tap(find.text(zh.settingsQuestionPackImport));
    await tester.pumpAndSettle();

    expect(picker.pickCalls, 1);
    expect(picker.pickedAllowedExtensions, const <String>['tqb']);
    expect(service.peekCalls, 0);
    expect(service.importCalls, 0);
  });

  testWidgets('导入：坏包只提示无效，不进入预览也不写入', (tester) async {
    final service = FakeQuestionPackService()
      ..previewError = const FormatException('not a package');
    final picker = FakeQuestionPackPicker(
      picked: [
        FakeQuestionPackFile('bad.tqb', Uint8List.fromList(<int>[1, 2])),
      ],
    );
    await pumpSettings(tester, service: service, picker: picker);

    await tester.tap(find.text(zh.settingsQuestionPackImport));
    await tester.pumpAndSettle();

    expect(service.peekCalls, 1);
    expect(service.importCalls, 0);
    expect(find.text(zh.settingsQuestionPackInvalid), findsOneWidget);
  });

  testWidgets('导入：预览确认后写入，结果对话框显示新建/跳过/图片与告警', (tester) async {
    final service = FakeQuestionPackService()
      ..preview = const QuestionPackPreview(questionCount: 3, mediaCount: 2)
      ..importReport = const QuestionPackImportReport(
        createdCount: 1,
        skippedCount: 2,
        mediaCount: 2,
        warnings: <String>['unknown tag kb: lost'],
        failures: <String>[],
      );
    final picker = FakeQuestionPackPicker(
      picked: [
        FakeQuestionPackFile('bank.tqb', Uint8List.fromList(<int>[9, 9])),
      ],
    );
    await pumpSettings(tester, service: service, picker: picker);

    await tester.tap(find.text(zh.settingsQuestionPackImport));
    await tester.pumpAndSettle();

    expect(service.peekCalls, 1);
    expect(
        find.text(zh.settingsQuestionPackImportPreview(3, 2)), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackImportConfirm), findsOneWidget);

    await tester
        .tap(find.widgetWithText(FilledButton, zh.settingsQuestionPackImport));
    await tester.pumpAndSettle();

    expect(service.importCalls, 1);
    expect(service.importedBytes.single, <int>[9, 9]);
    expect(
        find.text(zh.settingsQuestionPackImportDone(1, 2, 2)), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackWarnings(1)), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackFailures(1)), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, zh.commonClose));
    await tester.pumpAndSettle();
    expect(find.text(zh.settingsQuestionPackImportDone(1, 2, 2)), findsNothing);
  });

  testWidgets('导入：服务抛错时提示错误，不弹结果对话框', (tester) async {
    final service = FakeQuestionPackService()
      ..importError = StateError('disk full');
    final picker = FakeQuestionPackPicker(
      picked: [
        FakeQuestionPackFile('bank.tqb', Uint8List.fromList(<int>[1])),
      ],
    );
    await pumpSettings(tester, service: service, picker: picker);

    await tester.tap(find.text(zh.settingsQuestionPackImport));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(FilledButton, zh.settingsQuestionPackImport));
    await tester.pumpAndSettle();

    expect(service.importCalls, 1);
    expect(find.textContaining('disk full'), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackImportDone(2, 1, 1)), findsNothing);
  });

  testWidgets('导出进行中两行入口都禁用，重复点击不会再调服务', (tester) async {
    final service = FakeQuestionPackService()..exportGate = Completer<void>();
    final picker = FakeQuestionPackPicker();
    await pumpSettings(tester, service: service, picker: picker);

    await tester.tap(find.text(zh.settingsQuestionPackExport));
    await tester.pump();

    expect(service.exportCalls, 1);
    expect(tile(tester, zh.settingsQuestionPackExport).enabled, isFalse);
    expect(tile(tester, zh.settingsQuestionPackExport).onTap, isNull);
    expect(tile(tester, zh.settingsQuestionPackImport).onTap, isNull);

    await tester.tap(find.text(zh.settingsQuestionPackExport),
        warnIfMissed: false);
    await tester.pump();
    expect(service.exportCalls, 1);

    service.exportGate!.complete();
    await tester.pumpAndSettle();
    expect(picker.saveCalls, 1);
    expect(tile(tester, zh.settingsQuestionPackExport).onTap, isNotNull);
  });

  test('题库包新增文案中英文齐全，占位符真的插值', () {
    expect(zh.settingsQuestionPackSection, isNotEmpty);
    expect(zh.settingsQuestionPackExport, isNotEmpty);
    expect(zh.settingsQuestionPackExportHint, isNotEmpty);
    expect(zh.settingsQuestionPackExportEmpty, isNotEmpty);
    expect(zh.settingsQuestionPackImport, isNotEmpty);
    expect(zh.settingsQuestionPackImportHint, isNotEmpty);
    expect(zh.settingsQuestionPackImportConfirm, isNotEmpty);
    expect(zh.settingsQuestionPackInvalid, isNotEmpty);

    expect(
      zh.settingsQuestionPackExportDone(7, 3, '1.5 KB'),
      allOf(contains('7'), contains('3'), contains('1.5 KB')),
    );
    expect(
      zh.settingsQuestionPackImportPreview(7, 3),
      allOf(contains('7'), contains('3')),
    );
    expect(
      zh.settingsQuestionPackImportDone(1, 2, 3),
      allOf(contains('1'), contains('2'), contains('3')),
    );
    expect(zh.settingsQuestionPackWarnings(5), contains('5'));
    expect(zh.settingsQuestionPackFailures(5), contains('5'));

    expect(en.settingsQuestionPackSection, isNotEmpty);
    expect(en.settingsQuestionPackExportDone(7, 3, '1.5 KB'), contains('7'));
    expect(en.settingsQuestionPackImportPreview(7, 3), contains('7'));
    expect(en.settingsQuestionPackImportDone(1, 2, 3), contains('1'));
    expect(en.settingsQuestionPackWarnings(5), contains('5'));
    expect(en.settingsQuestionPackFailures(5), contains('5'));
  });

  test('questionPackSizeText 按 B/KB/MB 显示', () {
    expect(questionPackSizeText(0), '0 B');
    expect(questionPackSizeText(512), '512 B');
    expect(questionPackSizeText(1024), '1.0 KB');
    expect(questionPackSizeText(1536), '1.5 KB');
    expect(questionPackSizeText(1024 * 1024), '1.0 MB');
    expect(questionPackSizeText(2 * 1024 * 1024), '2.0 MB');
  });
}
