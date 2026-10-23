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

  /// 一份假备份（路径在假 documents 目录下；删除只需要 path）。
  QuestionPackBackup backupOf(
    String name, {
    int sizeBytes = 2048,
    DateTime? modifiedAt,
  }) =>
      QuestionPackBackup(
        path: '/fake/question_pack_backups/$name',
        name: name,
        sizeBytes: sizeBytes,
        modifiedAt: modifiedAt ?? DateTime(2026, 10, 23, 6, 8),
      );

  /// 点「导入前备份」入口，等清单对话框出来。
  Future<void> openBackups(WidgetTester tester) async {
    await tester.tap(find.text(zh.settingsQuestionPackBackupsTitle));
    await tester.pumpAndSettle();
  }

  Finder inDialog(Finder matching) =>
      find.descendant(of: find.byType(AlertDialog), matching: matching);

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

  testWidgets('导入：预检显示会更新已有题目和覆盖说明', (tester) async {
    final service = FakeQuestionPackService()
      ..importPreview = const QuestionPackImportPreview(
        manifestQuestionCount: 6,
        manifestMediaCount: 2,
        recordCount: 6,
        mediaCount: 2,
        appVersion: '0.5.3',
        exportedAt: null,
        createCount: 2,
        skipCount: 1,
        updateCount: 3,
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

    expect(find.text(zh.settingsQuestionPackPreviewCreate(2)), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackPreviewUpdate(3)), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackPreviewSkip(1)), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackImportUpdateNote), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackImportConfirm), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackPreviewNoNew), findsNothing);
  });

  testWidgets('导入：零新增但有更新时不提示没有新题', (tester) async {
    final service = FakeQuestionPackService()
      ..importPreview = const QuestionPackImportPreview(
        manifestQuestionCount: 5,
        manifestMediaCount: 0,
        recordCount: 5,
        mediaCount: 0,
        appVersion: '0.5.3',
        exportedAt: null,
        createCount: 0,
        skipCount: 1,
        updateCount: 4,
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

    expect(find.text(zh.settingsQuestionPackPreviewNoNew), findsNothing);
    expect(find.text(zh.settingsQuestionPackPreviewUpdate(4)), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackPreviewCreate(0)), findsNothing);
    expect(find.text(zh.settingsQuestionPackImportUpdateNote), findsOneWidget);
  });

  testWidgets('导入：结果对话框显示更新了几道已有题目', (tester) async {
    final service = FakeQuestionPackService()
      ..importReport = const QuestionPackImportReport(
        createdCount: 0,
        updatedCount: 3,
        skippedCount: 1,
        mediaCount: 2,
        warnings: <String>[],
        failures: <String>[],
      );
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

    expect(find.text(zh.settingsQuestionPackImportUpdated(3)), findsOneWidget);
    expect(
        find.text(zh.settingsQuestionPackImportDone(0, 1, 2)), findsOneWidget);
  });

  testWidgets('导入：纯新增包不显示更新行和覆盖说明', (tester) async {
    final service = FakeQuestionPackService();
    final picker = FakeQuestionPackPicker(
      picked: [
        FakeQuestionPackFile('bank.tqb', Uint8List.fromList(<int>[7])),
      ],
    );
    await pumpSettings(tester, service: service, picker: picker);

    await pickImportFile(tester);

    expect(find.text(zh.settingsQuestionPackPreviewUpdate(0)), findsNothing);
    expect(find.text(zh.settingsQuestionPackImportUpdateNote), findsNothing);

    await tester.tap(
      find.widgetWithText(FilledButton, zh.settingsQuestionPackImport),
    );
    await tester.pumpAndSettle();

    expect(find.text(zh.settingsQuestionPackImportUpdated(0)), findsNothing);
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
    expect(
      tile(tester, zh.settingsQuestionPackBackupsTitle).onTap,
      isNull,
    );

    await tester.tap(find.text(zh.settingsQuestionPackExport),
        warnIfMissed: false);
    await tester.pump();
    expect(service.exportCalls, 1);

    service.exportGate!.complete();
    await tester.pumpAndSettle();
    expect(picker.saveCalls, 1);
    expect(tile(tester, zh.settingsQuestionPackExport).onTap, isNotNull);
    expect(
      tile(tester, zh.settingsQuestionPackBackupsTitle).onTap,
      isNotNull,
    );
  });

  testWidgets('备份：入口常驻，没有备份时显示空态，对话框里也是空态', (tester) async {
    final service = FakeQuestionPackService();
    await pumpSettings(tester, service: service);

    expect(find.text(zh.settingsQuestionPackBackupsTitle), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackBackupsEmpty), findsOneWidget);
    expect(tile(tester, zh.settingsQuestionPackBackupsTitle).enabled, isTrue);
    expect(service.listBackupsCalls, 1);

    await openBackups(tester);

    expect(
      inDialog(find.text(zh.settingsQuestionPackBackupsEmpty)),
      findsOneWidget,
    );
    expect(service.listBackupsCalls, greaterThanOrEqualTo(2));
  });

  testWidgets('备份：入口副标题显示份数与总大小，对话框列出文件名、大小和日期', (tester) async {
    final newer = backupOf(
      '题库备份-20261023-060810-123.tqb',
      sizeBytes: 4096,
      modifiedAt: DateTime(2026, 10, 23, 6, 8),
    );
    final older = backupOf(
      '题库备份-20261022-231500-000.tqb',
      sizeBytes: 1024,
      modifiedAt: DateTime(2026, 10, 22, 23, 15),
    );
    final service = FakeQuestionPackService()
      ..backups = <QuestionPackBackup>[newer, older];
    await pumpSettings(tester, service: service);

    final row = tile(tester, zh.settingsQuestionPackBackupsTitle);
    final subtitle = (row.subtitle! as Text).data!;
    expect(subtitle, contains('2 份'));
    expect(subtitle, contains('5.0 KB'));

    await openBackups(tester);

    expect(inDialog(find.text(newer.name)), findsOneWidget);
    expect(inDialog(find.text(older.name)), findsOneWidget);
    expect(find.textContaining('4.0 KB · 2026-10-23 06:08'), findsOneWidget);
    expect(find.textContaining('1.0 KB · 2026-10-22 23:15'), findsOneWidget);
  });

  testWidgets('备份：删除先确认，成功后提示并刷新列表', (tester) async {
    final newer = backupOf('题库备份-20261023-060810-123.tqb');
    final older = backupOf('题库备份-20261022-231500-000.tqb');
    final service = FakeQuestionPackService()
      ..backups = <QuestionPackBackup>[newer, older];
    await pumpSettings(tester, service: service);
    await openBackups(tester);

    await tester.tap(inDialog(find.byIcon(Icons.delete_outline)).first);
    await tester.pumpAndSettle();
    expect(
      find.text(zh.settingsQuestionPackBackupDeleteConfirm(newer.name)),
      findsOneWidget,
    );

    await tester.tap(
      find.widgetWithText(
        FilledButton,
        zh.settingsQuestionPackBackupDeleteTooltip,
      ),
    );
    await tester.pumpAndSettle();

    expect(service.deletedBackupPaths, <String>[newer.path]);
    expect(find.text(zh.settingsQuestionPackBackupDeleteDone), findsOneWidget);
    expect(inDialog(find.text(newer.name)), findsNothing);
    expect(inDialog(find.text(older.name)), findsOneWidget);
  });

  testWidgets('备份：删除失败时提示原因，备份仍在列表里', (tester) async {
    final only = backupOf('题库备份-20261023-060810-123.tqb');
    final service = FakeQuestionPackService()
      ..backups = <QuestionPackBackup>[only]
      ..deleteBackupError = StateError('disk full');
    await pumpSettings(tester, service: service);
    await openBackups(tester);

    await tester.tap(inDialog(find.byIcon(Icons.delete_outline)).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        FilledButton,
        zh.settingsQuestionPackBackupDeleteTooltip,
      ),
    );
    await tester.pumpAndSettle();

    expect(service.deletedBackupPaths, <String>[only.path]);
    expect(find.textContaining('disk full'), findsOneWidget);
    expect(service.backups, hasLength(1));
    expect(inDialog(find.text(only.name)), findsOneWidget);
  });

  testWidgets('备份：清单读取失败不挡入口，只显示说明', (tester) async {
    final service = FakeQuestionPackService()
      ..listBackupsError = StateError('denied');
    await pumpSettings(tester, service: service);

    expect(find.text(zh.settingsQuestionPackBackupsHint), findsOneWidget);
    expect(find.text(zh.settingsQuestionPackBackupsEmpty), findsNothing);
    expect(tile(tester, zh.settingsQuestionPackBackupsTitle).enabled, isTrue);

    await openBackups(tester);

    expect(find.textContaining('denied'), findsOneWidget);
  });

  testWidgets('备份：每份都能恢复，确认后读字节→预检→导入并重读列表', (tester) async {
    final only = backupOf('题库备份-20261023-060810-123.tqb');
    final service = FakeQuestionPackService()
      ..backups = <QuestionPackBackup>[only];
    await pumpSettings(tester, service: service);
    await openBackups(tester);

    expect(
      inDialog(find.widgetWithIcon(IconButton, Icons.restore)),
      findsOneWidget,
    );

    await tester.tap(inDialog(find.byIcon(Icons.restore)).first);
    await tester.pumpAndSettle();
    expect(
      find.text(zh.settingsQuestionPackRestoreConfirm(only.name)),
      findsOneWidget,
    );
    expect(
      find.text(zh.settingsQuestionPackRestoreConfirmBody),
      findsOneWidget,
    );

    // 恢复进行中两个按钮一起禁用，防重复触发。
    for (final icon in <IconData>[Icons.restore, Icons.delete_outline]) {
      final button = tester.widget<IconButton>(
        inDialog(find.widgetWithIcon(IconButton, icon)),
      );
      expect(button.onPressed, isNull);
    }

    final listCallsBefore = service.listBackupsCalls;
    await tester.tap(
      find.widgetWithText(FilledButton, zh.settingsQuestionPackRestoreAction),
    );
    await tester.pumpAndSettle();

    expect(service.readBackupBytesPaths, <String>[only.path]);
    expect(service.plannedBytes, hasLength(1));
    expect(service.plannedBytes.single, service.backupBytes);

    await tester.tap(
      find.widgetWithText(FilledButton, zh.settingsQuestionPackImport),
    );
    await tester.pumpAndSettle();

    expect(service.importCalls, 1);
    expect(service.importedBytes.single, service.backupBytes);
    expect(
      find.text(zh.settingsQuestionPackImportDone(2, 1, 1)),
      findsOneWidget,
    );
    expect(service.deletedBackupPaths, isEmpty);

    final reportDialog = find.ancestor(
      of: find.text(zh.settingsQuestionPackImportDone(2, 1, 1)),
      matching: find.byType(AlertDialog),
    );
    await tester.tap(
      find.descendant(
        of: reportDialog,
        matching: find.widgetWithText(TextButton, zh.commonClose),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.listBackupsCalls, greaterThan(listCallsBefore));
    expect(inDialog(find.text(only.name)), findsOneWidget);
    final restoreButton = tester.widget<IconButton>(
      inDialog(find.widgetWithIcon(IconButton, Icons.restore)),
    );
    expect(restoreButton.onPressed, isNotNull);
  });

  testWidgets('备份：恢复确认时取消，不读字节也不导入', (tester) async {
    final only = backupOf('题库备份-20261023-060810-123.tqb');
    final service = FakeQuestionPackService()
      ..backups = <QuestionPackBackup>[only];
    await pumpSettings(tester, service: service);
    await openBackups(tester);

    await tester.tap(inDialog(find.byIcon(Icons.restore)).first);
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.text(zh.commonCancel)));
    await tester.pumpAndSettle();

    expect(service.readBackupBytesCalls, 0);
    expect(service.planCalls, 0);
    expect(service.importCalls, 0);
    expect(inDialog(find.text(only.name)), findsOneWidget);
  });

  testWidgets('备份：读取失败时提示恢复失败，对话框与备份都还在', (tester) async {
    final only = backupOf('题库备份-20261023-060810-123.tqb');
    final service = FakeQuestionPackService()
      ..backups = <QuestionPackBackup>[only]
      ..readBackupBytesError = StateError('disk gone');
    await pumpSettings(tester, service: service);
    await openBackups(tester);

    await tester.tap(inDialog(find.byIcon(Icons.restore)).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, zh.settingsQuestionPackRestoreAction),
    );
    await tester.pumpAndSettle();

    expect(service.readBackupBytesCalls, 1);
    expect(service.planCalls, 0);
    expect(
      find.text(zh.settingsQuestionPackRestoreFailed('Bad state: disk gone')),
      findsOneWidget,
    );
    expect(inDialog(find.text(only.name)), findsOneWidget);
    final restoreButton = tester.widget<IconButton>(
      inDialog(find.widgetWithIcon(IconButton, Icons.restore)),
    );
    expect(restoreButton.onPressed, isNotNull);
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
    expect(zh.settingsQuestionPackFilterTags, isNotEmpty);
    expect(zh.settingsQuestionPackFilterTagSelect, isNotEmpty);
    expect(zh.settingsQuestionPackTagPickerTitle, isNotEmpty);
    expect(zh.settingsQuestionPackTagPickerSearch, isNotEmpty);
    expect(zh.settingsQuestionPackTagPickerEmpty, isNotEmpty);
    expect(zh.settingsQuestionPackTagPickerNoMatch, isNotEmpty);
    expect(
      zh.settingsQuestionPackFilterTagsSelected(3),
      allOf(contains('3'), isNot(contains('{count}'))),
    );
    expect(
      zh.settingsQuestionPackTagQuestionCount(4),
      allOf(contains('4'), isNot(contains('{count}'))),
    );
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
      zh.settingsQuestionPackPreviewUpdate(6),
      allOf(contains('6'), isNot(contains('{count}'))),
    );
    expect(
      zh.settingsQuestionPackImportUpdated(6),
      allOf(contains('6'), isNot(contains('{count}'))),
    );
    expect(zh.settingsQuestionPackImportUpdateNote, isNotEmpty);

    expect(zh.settingsQuestionPackBackupsTitle, isNotEmpty);
    expect(zh.settingsQuestionPackBackupsEmpty, isNotEmpty);
    expect(zh.settingsQuestionPackBackupsHint, isNotEmpty);
    expect(zh.settingsQuestionPackBackupDeleteTooltip, isNotEmpty);
    expect(zh.settingsQuestionPackBackupDeleteDone, isNotEmpty);
    expect(
      zh.settingsQuestionPackBackupDeleteConfirm('a.tqb'),
      allOf(contains('a.tqb'), isNot(contains('{name}'))),
    );
    expect(
      zh.settingsQuestionPackBackupDeleteFailed('disk full'),
      allOf(contains('disk full'), isNot(contains('{error}'))),
    );

    expect(zh.settingsQuestionPackRestoreTooltip, isNotEmpty);
    expect(zh.settingsQuestionPackRestoreAction, isNotEmpty);
    expect(zh.settingsQuestionPackRestoreConfirmBody, isNotEmpty);
    expect(
      zh.settingsQuestionPackRestoreConfirm('a.tqb'),
      allOf(contains('a.tqb'), isNot(contains('{name}'))),
    );
    expect(
      zh.settingsQuestionPackRestoreFailed('disk full'),
      allOf(contains('disk full'), isNot(contains('{error}'))),
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
    expect(en.settingsQuestionPackFilterTags, isNotEmpty);
    expect(en.settingsQuestionPackFilterTagSelect, isNotEmpty);
    expect(en.settingsQuestionPackTagPickerTitle, isNotEmpty);
    expect(en.settingsQuestionPackTagPickerSearch, isNotEmpty);
    expect(en.settingsQuestionPackTagPickerEmpty, isNotEmpty);
    expect(en.settingsQuestionPackTagPickerNoMatch, isNotEmpty);
    expect(en.settingsQuestionPackFilterTagsSelected(3), contains('3'));
    expect(en.settingsQuestionPackTagQuestionCount(4), contains('4'));
    expect(en.settingsQuestionPackPreviewCreate(7), contains('7'));
    expect(en.settingsQuestionPackPreviewSkip(8), contains('8'));
    expect(en.settingsQuestionPackPreviewMissingTags(9), contains('9'));
    expect(en.settingsQuestionPackPreviewUpdate(6), contains('6'));
    expect(en.settingsQuestionPackImportUpdated(6), contains('6'));
    expect(en.settingsQuestionPackImportUpdateNote, isNotEmpty);
    expect(en.settingsQuestionPackExportDone(7, 3, '1.5 KB'), contains('7'));
    expect(en.settingsQuestionPackImportPreview(7, 3), contains('7'));
    expect(en.settingsQuestionPackImportDone(1, 2, 3), contains('1'));
    expect(en.settingsQuestionPackWarnings(5), contains('5'));
    expect(en.settingsQuestionPackFailures(5), contains('5'));
    expect(en.settingsQuestionPackRestoreTooltip, isNotEmpty);
    expect(en.settingsQuestionPackRestoreAction, isNotEmpty);
    expect(en.settingsQuestionPackRestoreConfirmBody, isNotEmpty);
    expect(en.settingsQuestionPackRestoreConfirm('a.tqb'), contains('a.tqb'));
    expect(
      en.settingsQuestionPackRestoreFailed('disk full'),
      contains('disk full'),
    );
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
