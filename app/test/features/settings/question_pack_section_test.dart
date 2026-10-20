/// 设置页题库包（`.tqb`）小节：先筛选再导出、导入前预检、取消、坏包、
/// 结果对话框、防重入，以及新增文案的占位符是否真的插值。
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
import 'package:furnace/domain/services/package/question_pack_import_preview.dart';
import 'package:furnace/domain/services/package/question_pack_selection.dart';
import 'package:furnace/features/questions/application/question_pack_service.dart';
import 'package:furnace/features/questions/presentation/question_paper_page.dart'
    show subjectLabelOf;
import 'package:furnace/features/questions/presentation/question_vocab_labels.dart'
    show sourceLevelLabel;
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

  /// 点导出入口，等「导出范围」对话框出来。
  Future<void> openExportFilter(WidgetTester tester) async {
    await tester.tap(find.text(zh.settingsQuestionPackExport));
    await tester.pumpAndSettle();
  }

  /// 在「导出范围」对话框里点「导出」（默认全不选=全部导出）。
  Future<void> confirmExportFilter(WidgetTester tester) async {
    await tester.tap(
      find.widgetWithText(FilledButton, zh.settingsQuestionPackFilterExport),
    );
    await tester.pumpAndSettle();
  }

  /// 点导入入口（文件选择器替身会返回预设文件）。
  Future<void> pickImportFile(WidgetTester tester) async {
    await tester.tap(find.text(zh.settingsQuestionPackImport));
    await tester.pumpAndSettle();
  }

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

  testWidgets('导出：先弹筛选框，默认全不选=全部导出', (tester) async {
    final service = FakeQuestionPackService();
    final picker = FakeQuestionPackPicker();
    await pumpSettings(tester, service: service, picker: picker);

    await openExportFilter(tester);
    expect(find.text(zh.settingsQuestionPackFilterTitle), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackFilterSubjects), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackFilterSources), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackFilterSerialRange), findsOneWidget);

    await confirmExportFilter(tester);

    expect(service.exportCalls, 1);
    expect(service.lastSelection!.isEmpty, isTrue);
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

  testWidgets('导出：按学科/来源/题号筛选后服务收到对应 selection', (tester) async {
    final service = FakeQuestionPackService();
    final picker = FakeQuestionPackPicker();
    await pumpSettings(tester, service: service, picker: picker);

    await openExportFilter(tester);
    await tester.tap(
      find.widgetWithText(FilterChip, subjectLabelOf(zh, 'math')),
    );
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilterChip, sourceLevelLabel(zh, 'gaokao')),
    );
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, zh.settingsQuestionPackFilterSerialFrom),
      '0012',
    );
    await tester.enterText(
      find.widgetWithText(TextField, zh.settingsQuestionPackFilterSerialTo),
      '30',
    );
    await tester.pumpAndSettle();
    await confirmExportFilter(tester);

    expect(service.exportCalls, 1);
    final QuestionPackSelection selection = service.lastSelection!;
    expect(selection.subjectKeys, unorderedEquals(<String>{'math'}));
    expect(selection.sourceLevels, unorderedEquals(<String>{'gaokao'}));
    expect(selection.serialFrom, 12);
    expect(selection.serialTo, 30);
    expect(selection.isEmpty, isFalse);
  });

  testWidgets('导出：题号非数字时内联报错且导出按钮禁用', (tester) async {
    final service = FakeQuestionPackService();
    await pumpSettings(tester, service: service);

    await openExportFilter(tester);
    await tester.enterText(
      find.widgetWithText(TextField, zh.settingsQuestionPackFilterSerialFrom),
      'abc',
    );
    await tester.pump();

    expect(
        find.text(zh.settingsQuestionPackFilterSerialInvalid), findsOneWidget);
    final FilledButton exportButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, zh.settingsQuestionPackFilterExport),
    );
    expect(exportButton.onPressed, isNull);
    expect(service.exportCalls, 0);

    await tester.enterText(
      find.widgetWithText(TextField, zh.settingsQuestionPackFilterSerialFrom),
      '5',
    );
    await tester.pump();
    expect(find.text(zh.settingsQuestionPackFilterSerialInvalid), findsNothing);
    await confirmExportFilter(tester);
    expect(service.lastSelection!.serialFrom, 5);
  });

  testWidgets('导出：起始题号大于结束题号时内联报错且导出按钮禁用', (tester) async {
    final service = FakeQuestionPackService();
    await pumpSettings(tester, service: service);

    await openExportFilter(tester);
    await tester.enterText(
      find.widgetWithText(TextField, zh.settingsQuestionPackFilterSerialFrom),
      '9',
    );
    await tester.enterText(
      find.widgetWithText(TextField, zh.settingsQuestionPackFilterSerialTo),
      '3',
    );
    await tester.pump();

    expect(
      find.text(zh.settingsQuestionPackFilterSerialReversed),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(
              FilledButton,
              zh.settingsQuestionPackFilterExport,
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('导出：取消筛选框不调服务、不弹保存框', (tester) async {
    final service = FakeQuestionPackService();
    final picker = FakeQuestionPackPicker();
    await pumpSettings(tester, service: service, picker: picker);

    await openExportFilter(tester);
    await tester.tap(find.widgetWithText(TextButton, zh.commonCancel));
    await tester.pumpAndSettle();

    expect(service.exportCalls, 0);
    expect(picker.saveCalls, 0);
  });

  testWidgets('导出：用户在保存框取消时不提示成功', (tester) async {
    final service = FakeQuestionPackService();
    final picker = FakeQuestionPackPicker()..cancelSave = true;
    await pumpSettings(tester, service: service, picker: picker);

    await openExportFilter(tester);
    await confirmExportFilter(tester);

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

    await openExportFilter(tester);
    await confirmExportFilter(tester);

    expect(service.exportCalls, 1);
    expect(picker.saveCalls, 0);
    expect(find.text(zh.settingsQuestionPackExportEmpty), findsOneWidget);
  });

  testWidgets('导出：筛选后 0 题提示放宽筛选，不弹保存框', (tester) async {
    final service = FakeQuestionPackService()
      ..exportResult = QuestionPackExportResult(
        bytes: Uint8List(0),
        questionCount: 0,
        mediaCount: 0,
      );
    final picker = FakeQuestionPackPicker();
    await pumpSettings(tester, service: service, picker: picker);

    await openExportFilter(tester);
    await tester.tap(
      find.widgetWithText(FilterChip, subjectLabelOf(zh, 'math')),
    );
    await tester.pump();
    await confirmExportFilter(tester);

    expect(
        service.lastSelection!.subjectKeys, unorderedEquals(<String>{'math'}));
    expect(picker.saveCalls, 0);
    expect(find.text(zh.settingsQuestionPackFilterEmpty), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackExportEmpty), findsNothing);
  });

  testWidgets('导出：有告警时弹「导出提示」并列出告警', (tester) async {
    final service = FakeQuestionPackService()
      ..exportResult = QuestionPackExportResult(
        bytes: Uint8List.fromList(<int>[1, 2]),
        questionCount: 1,
        mediaCount: 0,
        warnings: const <String>['配图 3.png 的扩展名不认识，没有导出'],
      );
    final picker = FakeQuestionPackPicker();
    await pumpSettings(tester, service: service, picker: picker);

    await openExportFilter(tester);
    await confirmExportFilter(tester);

    expect(picker.saveCalls, 1);
    expect(
        find.text(zh.settingsQuestionPackExportWarningsTitle), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackWarnings(1)), findsOneWidget);
    expect(find.text('配图 3.png 的扩展名不认识，没有导出'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, zh.commonClose));
    await tester.pumpAndSettle();
    expect(find.text(zh.settingsQuestionPackExportWarningsTitle), findsNothing);
  });

  testWidgets('导出：服务抛错时提示前缀和错误', (tester) async {
    final service = FakeQuestionPackService()
      ..exportError = StateError('no database');
    await pumpSettings(tester, service: service);

    await openExportFilter(tester);
    await confirmExportFilter(tester);

    expect(find.textContaining('no database'), findsOneWidget);
  });

  testWidgets('导入：选文件对话框只收 .tqb；取消后不预检也不导入', (tester) async {
    final service = FakeQuestionPackService();
    final picker = FakeQuestionPackPicker(picked: <PlatformFile>[]);
    await pumpSettings(tester, service: service, picker: picker);

    await pickImportFile(tester);

    expect(picker.pickCalls, 1);
    expect(picker.pickedAllowedExtensions, const <String>['tqb']);
    expect(service.planCalls, 0);
    expect(service.importCalls, 0);
  });

  testWidgets('导入：坏包只提示无效，不进入预览也不写入', (tester) async {
    final service = FakeQuestionPackService()
      ..planError = const FormatException('not a package');
    final picker = FakeQuestionPackPicker(
      picked: [
        FakeQuestionPackFile('bad.tqb', Uint8List.fromList(<int>[1, 2])),
      ],
    );
    await pumpSettings(tester, service: service, picker: picker);

    await pickImportFile(tester);

    expect(service.planCalls, 1);
    expect(service.importCalls, 0);
    expect(find.text(zh.settingsQuestionPackInvalid), findsOneWidget);
  });

  testWidgets('导入：预览显示新增/跳过/缺标签/告警，确认后写入并刷新', (tester) async {
    final service = FakeQuestionPackService()
      ..importPreview = const QuestionPackImportPreview(
        manifestQuestionCount: 3,
        manifestMediaCount: 2,
        recordCount: 3,
        mediaCount: 2,
        appVersion: '0.5.3',
        exportedAt: null,
        createCount: 2,
        skipCount: 1,
        missingTagCount: 2,
        warnings: <String>['第 1 道题的配图丢了'],
        missingTagPaths: <String>['kb: lost', 'kb: gone'],
      )
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

    await pickImportFile(tester);

    expect(service.planCalls, 1);
    expect(service.plannedBytes.single, <int>[9, 9]);
    expect(
      find.text(zh.settingsQuestionPackImportPreview(3, 2)),
      findsOneWidget,
    );
    expect(find.text(zh.settingsQuestionPackPreviewCreate(2)), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackPreviewSkip(1)), findsOneWidget);
    expect(
      find.text(zh.settingsQuestionPackPreviewMissingTags(2)),
      findsOneWidget,
    );
    expect(find.text(zh.settingsQuestionPackWarnings(1)), findsOneWidget);
    expect(find.text('第 1 道题的配图丢了'), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackImportConfirm), findsOneWidget);

    await tester.tap(
      find.widgetWithText(FilledButton, zh.settingsQuestionPackImport),
    );
    await tester.pumpAndSettle();

    expect(service.importCalls, 1);
    expect(service.importedBytes.single, <int>[9, 9]);
    expect(
      find.text(zh.settingsQuestionPackImportDone(1, 2, 2)),
      findsOneWidget,
    );
    expect(find.text(zh.settingsQuestionPackWarnings(1)), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackFailures(1)), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, zh.commonClose));
    await tester.pumpAndSettle();
    expect(find.text(zh.settingsQuestionPackImportDone(1, 2, 2)), findsNothing);
  });

  testWidgets('导入：预览里没有可新增的题时提示没有新题', (tester) async {
    final service = FakeQuestionPackService()
      ..importPreview = const QuestionPackImportPreview(
        manifestQuestionCount: 3,
        manifestMediaCount: 0,
        recordCount: 3,
        mediaCount: 0,
        appVersion: '0.5.3',
        exportedAt: null,
        createCount: 0,
        skipCount: 3,
        missingTagCount: 0,
        warnings: <String>[],
        missingTagPaths: <String>[],
      );
    final picker = FakeQuestionPackPicker(
      picked: [
        FakeQuestionPackFile('bank.tqb', Uint8List.fromList(<int>[1])),
      ],
    );
    await pumpSettings(tester, service: service, picker: picker);

    await pickImportFile(tester);

    expect(find.text(zh.settingsQuestionPackPreviewNoNew), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackPreviewCreate(0)), findsNothing);
    expect(find.text(zh.settingsQuestionPackPreviewSkip(3)), findsOneWidget);
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

    await pickImportFile(tester);
    await tester.tap(
      find.widgetWithText(FilledButton, zh.settingsQuestionPackImport),
    );
    await tester.pumpAndSettle();

    expect(service.importCalls, 1);
    expect(find.textContaining('disk full'), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackImportDone(2, 1, 1)), findsNothing);
  });

  testWidgets('导出进行中两行入口都禁用，重复点击不会再调服务', (tester) async {
    final service = FakeQuestionPackService()..exportGate = Completer<void>();
    final picker = FakeQuestionPackPicker();
    await pumpSettings(tester, service: service, picker: picker);

    await openExportFilter(tester);
    await tester.tap(
      find.widgetWithText(FilledButton, zh.settingsQuestionPackFilterExport),
    );
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

    expect(zh.settingsQuestionPackFilterTitle, isNotEmpty);
    expect(zh.settingsQuestionPackFilterSubjects, isNotEmpty);
    expect(zh.settingsQuestionPackFilterSources, isNotEmpty);
    expect(zh.settingsQuestionPackFilterSerialRange, isNotEmpty);
    expect(zh.settingsQuestionPackFilterSerialHint, isNotEmpty);
    expect(zh.settingsQuestionPackFilterSerialFrom, isNotEmpty);
    expect(zh.settingsQuestionPackFilterSerialTo, isNotEmpty);
    expect(zh.settingsQuestionPackFilterSerialInvalid, isNotEmpty);
    expect(zh.settingsQuestionPackFilterSerialReversed, isNotEmpty);
    expect(zh.settingsQuestionPackFilterExport, isNotEmpty);
    expect(zh.settingsQuestionPackFilterEmpty, isNotEmpty);
    expect(zh.settingsQuestionPackExportWarningsTitle, isNotEmpty);
    expect(zh.settingsQuestionPackPreviewNoNew, isNotEmpty);
    expect(
      zh.settingsQuestionPackPreviewCreate(7),
      allOf(contains('7'), isNot(contains('{count}'))),
    );
    expect(
      zh.settingsQuestionPackPreviewSkip(8),
      allOf(contains('8'), isNot(contains('{count}'))),
    );
    expect(
      zh.settingsQuestionPackPreviewMissingTags(9),
      allOf(contains('9'), isNot(contains('{count}'))),
    );

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
    expect(en.settingsQuestionPackFilterTitle, isNotEmpty);
    expect(en.settingsQuestionPackExportWarningsTitle, isNotEmpty);
    expect(en.settingsQuestionPackPreviewNoNew, isNotEmpty);
    expect(en.settingsQuestionPackPreviewCreate(7), contains('7'));
    expect(en.settingsQuestionPackPreviewSkip(8), contains('8'));
    expect(en.settingsQuestionPackPreviewMissingTags(9), contains('9'));
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
