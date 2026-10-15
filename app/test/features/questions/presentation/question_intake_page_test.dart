/// 收题页的行为测试：`docs/QUESTION_BANK_DESIGN.md` §6 收题入口 B（粘贴 → 校对表 →
/// 入库）+ §7 拍照手写整理入口的第 1 步（图片先落盘）。
///
/// 这一组测试盯着三件靠读代码看不出来的事：
///
///  1. 按「入库」之前什么都没有写进 `questions`（题干为空、难度非法时尤其如此）；
///  2. 写进去的字段是设计文档要的那几个（`origin`/`state`/选项标签与排序）；
///  3. 写库之后列表自己会刷新——这一页没有手动 invalidate，靠的是
///     `DbWriteInterceptor` → `DataChangeBus`，所以数据库要用 `instrumentWrites`
///     搭出来，否则测的就不是生产那条路径了。
///
/// **store 与选择器是替身**（见 `../support/picked_file_fakes.dart` 的说明）：真
/// store 走 `dart:io` 的异步文件 API，在 `testWidgets` 的假时钟里等不到回调。真
/// store 的文件语义由 `../data/handwriting_intake_store_test.dart` 在真实时钟下
/// 覆盖，这里只证明页面把该调的调了、该看的状态看对了。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/core/state/data_change_bus.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/features/questions/data/handwriting_intake_store.dart';
import 'package:furnace/features/questions/presentation/question_intake_page.dart';
import 'package:furnace/features/questions/presentation/question_intake_providers.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../support/picked_file_fakes.dart';

void main() {
  late AppDatabase db;
  late QuestionRepository repository;
  late FakeIntakeStore store;
  late Directory supportRoot;

  setUp(() {
    DataChangeBus.instance.debugReset();
    db = AppDatabase.forTesting(instrumentWrites(NativeDatabase.memory()));
    repository = QuestionRepository(db);
    supportRoot = Directory.systemTemp.createTempSync('furnace_intake_support_');
    store = FakeIntakeStore(database: db, root: supportRoot);
  });

  tearDown(() async {
    await db.close();
    if (supportRoot.existsSync()) {
      supportRoot.deleteSync(recursive: true);
    }
  });

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(QuestionIntakePage)));

  /// 带 [label] 的输入框。表单里每个字段都是 `InputDecoration.labelText`，
  /// 所以从 label 往上找到 `TextField` 比按顺序数第几个输入框稳。
  Finder field(String label) => find
      .ancestor(of: find.text(label), matching: find.byType(TextField))
      .first;

  /// 页面自己空闲下来：两个异步 provider 和按钮上的进度圈都消失。
  ///
  /// 不能用 `pumpAndSettle`：`LinearProgressIndicator` 是无限动画，加载中调用它
  /// 只会超时。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        return;
      }
    }
  }

  /// 等一段文字出现。
  ///
  /// `ScaffoldMessenger` 的 SnackBar 会排队：上一条要显示满 4 秒才轮到下一条，所
  /// 以不能"点完立刻断言"，得给它时间。
  Future<void> expectTextEventually(WidgetTester tester, String text) async {
    for (var i = 0; i < 120; i++) {
      if (find.text(text).evaluate().isNotEmpty) {
        return;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    fail('等了 12 秒也没等到这段文字：$text');
  }

  /// 一个高一点的视口：页面是 `ListView`，没被 build 出来的卡片是找不到的。
  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          handwritingIntakeStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: QuestionIntakePage(),
        ),
      ),
    );
    await settle(tester);
  }

  /// 按「入库」并等它落库。
  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.text(l10n(tester).questionIntakeSubmit));
    await settle(tester);
  }

  /// 按「拍照 / 选图」并等页面处理完。
  Future<FakeFilePicker> pickImages(WidgetTester tester) async {
    final picker = FilePickerPlatform.instance;
    await tester.tap(find.text(l10n(tester).questionIntakePickImages));
    await settle(tester);
    return picker as FakeFilePicker;
  }

  testWidgets('粘贴题干 → 入库为 manual/structured，列表自己刷新', (tester) async {
    await pumpPage(tester);
    final strings = l10n(tester);

    // 两边的空白要被裁掉：题干是去重的依据，前后空格不该算另一道题。
    await tester.enterText(field(strings.questionIntakeStemLabel), '  求 x²+1 的最小值  ');
    await tester.pump();
    await submit(tester);

    final rows = await repository.all();
    expect(rows, hasLength(1));
    expect(rows.single.stem, '求 x²+1 的最小值');
    expect(rows.single.origin, 'manual');
    expect(rows.single.state, 'structured');
    // 指纹在入库时就算好，去重那条路（`findByFingerprint`）才成立。
    expect(rows.single.stemFingerprint, hasLength(16));

    // 列表跟着写库自己刷新了（这一页没有手动 invalidate）。
    expect(find.text('求 x²+1 的最小值'), findsOneWidget);
    await expectTextEventually(
      tester,
      strings.questionIntakeSaved('求 x²+1 的最小值'),
    );
  });

  testWidgets('同一道题干再收一次：不新增，提示已存在', (tester) async {
    await pumpPage(tester);
    final strings = l10n(tester);

    await tester.enterText(field(strings.questionIntakeStemLabel), '牛顿第二定律');
    await tester.pump();
    await submit(tester);
    await expectTextEventually(tester, strings.questionIntakeSaved('牛顿第二定律'));

    await tester.enterText(field(strings.questionIntakeStemLabel), '牛顿第二定律');
    await tester.pump();
    await submit(tester);

    expect(await repository.all(), hasLength(1));
    await expectTextEventually(
      tester,
      strings.questionIntakeDuplicate('牛顿第二定律'),
    );
  });

  testWidgets('题干为空：只说一句，不写库', (tester) async {
    await pumpPage(tester);
    final strings = l10n(tester);

    await submit(tester);

    expect(find.text(strings.questionIntakeStemRequired), findsOneWidget);
    expect(await repository.all(), isEmpty);
  });

  testWidgets('难度超出 1–10：只说一句，不写库', (tester) async {
    await pumpPage(tester);
    final strings = l10n(tester);

    await tester.enterText(field(strings.questionIntakeStemLabel), '一道题');
    await tester.enterText(field(strings.questionIntakeDifficultyLabel), '99');
    await tester.pump();
    await submit(tester);

    expect(find.text(strings.questionIntakeDifficultyInvalid), findsOneWidget);
    expect(await repository.all(), isEmpty);
  });

  testWidgets('单选题：空白选项不入库，标签重新编号，选项顺序照填的来', (tester) async {
    await pumpPage(tester);
    final strings = l10n(tester);

    // 从「解答题」切到「单选题」，选项编辑器才会出现。
    await tester.tap(find.text(strings.questionIntakeTypeSolution));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.questionIntakeTypeSingleChoice).last);
    await tester.pumpAndSettle();

    await tester.enterText(field(strings.questionIntakeStemLabel), '2+2 等于几？');
    await tester.enterText(field(strings.questionIntakeOptionLabel('A')), '  3  ');
    await tester.enterText(field(strings.questionIntakeOptionLabel('B')), '4');
    // 第三个选项留着不填：它不该进库，也不该在标签里留个「C」的空档。
    await tester.tap(find.text(strings.questionIntakeAddOption));
    await tester.pumpAndSettle();
    // 勾 A 正确（第一个复选框）。
    await tester.tap(find.byTooltip(strings.questionIntakeCorrectTooltip).first);
    await tester.pump();

    await submit(tester);

    final question = (await repository.all()).single;
    expect(question.questionType, 'single_choice');
    final options = await repository.optionsOf(question.id);
    expect(options.map((option) => option.label), ['A', 'B']);
    expect(options.map((option) => option.content), ['3', '4']);
    expect(options.map((option) => option.sortOrder), [0, 1]);
    expect(options.first.isCorrect, isTrue);
    expect(options.last.isCorrect, isFalse);
  });

  testWidgets('选图：附件落盘 + 建一条 raw/ai_scan 题 + 待整理清单认得出文件名',
      (tester) async {
    FilePickerPlatform.instance =
        FakeFilePicker([FakePickedFile('page1.png', Uint8List.fromList([1, 2, 3, 4]))]);

    await pumpPage(tester);
    final strings = l10n(tester);
    final picker = await pickImages(tester);

    // 只让用户选图片：白名单里得有常见图片扩展名。
    expect(picker.allowedExtensionsCalls, hasLength(1));
    expect(picker.allowedExtensionsCalls.single, contains('png'));

    // 附件：一行，owner_type 是本页自己的，路径在 store 自己的目录下。
    final attachments = await db.select(db.attachments).get();
    expect(attachments, hasLength(1));
    expect(attachments.single.ownerType, HandwritingIntakeStore.ownerType);
    expect(
      attachments.single.relPath,
      startsWith('${HandwritingIntakeStore.directoryName}/'),
    );
    expect(attachments.single.relPath, endsWith('page1.png'));
    final absolute = await store.absolutePath(attachments.single.relPath);
    expect(File(absolute).existsSync(), isTrue);
    expect(absolute, startsWith(supportRoot.path));

    // 题目：只是占位，等 OCR。所以是 ai_scan + raw（不是 structured）。
    final rows = await repository.all();
    expect(rows, hasLength(1));
    expect(rows.single.origin, 'ai_scan');
    expect(rows.single.state, 'raw');
    expect(rows.single.stem, strings.questionIntakePhotoStem('page1.png'));

    // 待整理清单里认得出是哪张照片。
    expect(find.text('page1.png'), findsOneWidget);
    await expectTextEventually(tester, strings.questionIntakePhotoAdded(1));
  });

  testWidgets('从待整理清单删掉一张图：行和文件一起消失', (tester) async {
    FilePickerPlatform.instance =
        FakeFilePicker([FakePickedFile('trash.png', Uint8List.fromList([9]))]);

    await pumpPage(tester);
    final strings = l10n(tester);
    await pickImages(tester);

    final relPath = (await db.select(db.attachments).get()).single.relPath;
    final absolute = await store.absolutePath(relPath);
    expect(File(absolute).existsSync(), isTrue);

    await tester.tap(find.byTooltip(strings.questionIntakeRemovePhoto));
    await settle(tester);

    expect(await db.select(db.attachments).get(), isEmpty);
    expect(File(absolute).existsSync(), isFalse);
    expect(find.text('trash.png'), findsNothing);
  });

  testWidgets('搜索框按题干筛（走仓储的 search，不是本地过滤）', (tester) async {
    await repository.ingest(const QuestionDraft(stem: '光合作用的意义'));
    await repository.ingest(const QuestionDraft(stem: '牛顿第二定律'));

    await pumpPage(tester);
    final strings = l10n(tester);
    expect(find.text('光合作用的意义'), findsOneWidget);
    expect(find.text('牛顿第二定律'), findsOneWidget);

    await tester.enterText(field(strings.questionIntakeSearchHint), '牛顿');
    await settle(tester);

    expect(find.text('牛顿第二定律'), findsOneWidget);
    expect(find.text('光合作用的意义'), findsNothing);
  });

  testWidgets('删题要确认：确认前库里还在，确认后消失并提示', (tester) async {
    await repository.ingest(const QuestionDraft(stem: '待删除的题'));

    await pumpPage(tester);
    final strings = l10n(tester);

    await tester.tap(find.byTooltip(strings.questionIntakeDelete));
    await tester.pumpAndSettle();
    expect(find.text(strings.questionIntakeDeleteConfirm), findsOneWidget);

    // 先点「取消」：什么都不该发生。
    await tester.tap(find.text(strings.questionIntakeCancel));
    await tester.pumpAndSettle();
    expect(await repository.all(), hasLength(1));

    await tester.tap(find.byTooltip(strings.questionIntakeDelete));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.questionIntakeDelete));
    await settle(tester);

    expect(await repository.all(), isEmpty);
    await expectTextEventually(tester, strings.questionIntakeDeleted('待删除的题'));
  });
}
