/// 题库卡片化 + 化学 Q15 内容修复的验收截图（1280 / 2560 两档宽度）。
///
/// 运行方式（在 Furnace app 目录下）：
///
///   flutter test tool/question_bank_ui_screenshot.dart
///
/// 与普通 widget 测试不同，这个脚本的职责是**落盘 PNG**：用真实中文
/// 字体、真实的题库数据（`E:\Furnace\data\furnace.db` 的**副本**，只读）、
/// 真实题干图片目录渲染真实页面，写到工作区
/// `.work/question-bank-cards-2026-11-15/screenshots/`。
///
/// 两个刻意的做法：
///  * 数据库先复制到工作区再打开：截图过程绝不写真实题库；副本里再插一道
///    「填空 ______ + LaTeX」的样例题，只为截到填空下划线可见的效果（真实
///    题库当前没有填空题）；
///  * 图片字节从 `E:\Furnace\data` 只读读取（题干配图 18 张在库里，不在 DB
///    里），所以截图里化学 Q15 的公式图是真实图片。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/markdown/domain/markdown_render_theme.dart';
import 'package:furnace/features/markdown/presentation/markdown_renderer.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/presentation/question_bank_page.dart';
import 'package:furnace/features/questions/presentation/question_detail_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

const String _outDir =
    r'E:\Workspaces\agent-control\10-projects\agent-control-plane\.work\question-bank-cards-2026-11-15\screenshots';

const String _realDb = r'E:\Furnace\data\furnace.db';

const String _realMediaDir = r'E:\Furnace\data';

/// 化学 Q15（serial 661）与数学 19 题（serial 659）的 id 从库里读，不硬编码。
Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadFonts();
  final zh = await AppLocalizations.delegate.load(const Locale('zh'));

  late AppDatabase database;
  late String chemistryId;
  late String mathId;

  setUpAll(() async {
    database = await _openDatabaseCopy();
    final repo = QuestionRepository(database);
    chemistryId = (await repo.findBySerialNo(661))!.id;
    mathId = (await repo.findBySerialNo(659))!.id;
    // 只写副本：给「填空下划线 / 选项两列 / 选项单列」截真实渲染的图
    // （真实题库当前没有填空题，也没有长选项样例）。
    await _insertBlankSample(database);
    await _insertOptionSamples(database);
  });

  tearDownAll(() async {
    await database.close();
  });

  testWidgets('题库卡片 1280×2400', (tester) async {
    await _pumpBank(tester, database, size: const Size(1280, 2400));
    await _capture(tester, 'question-bank-1280x2400.png');
    expect(zh.navQuestions, isNotEmpty);
  });

  testWidgets('题库卡片 2560×2400', (tester) async {
    await _pumpBank(tester, database, size: const Size(2560, 2400));
    await _capture(tester, 'question-bank-2560x2400.png');
  });

  testWidgets('化学 Q15（serial 661）详情 1280×3000', (tester) async {
    await _pumpDetail(
      tester,
      database,
      chemistryId,
      size: const Size(1280, 3000),
    );
    await _capture(tester, 'question-chemistry-661-1280x3000.png');
  });

  testWidgets('化学 Q15（serial 661）详情 2560×3000', (tester) async {
    await _pumpDetail(
      tester,
      database,
      chemistryId,
      size: const Size(2560, 3000),
    );
    await _capture(tester, 'question-chemistry-661-2560x3000.png');
  });

  testWidgets('数学 19 题（serial 659）LaTeX 详情 1280×1800', (tester) async {
    await _pumpDetail(
      tester,
      database,
      mathId,
      size: const Size(1280, 1800),
    );
    await _capture(tester, 'question-math-659-1280x1800.png');
  });

  testWidgets('填空下划线样例 1280×1400', (tester) async {
    final sample = (await QuestionRepository(database)
        .findBySerialNo(_blankSampleSerial))!;
    await _pumpDetail(
      tester,
      database,
      sample.id,
      size: const Size(1280, 1400),
    );
    await _capture(tester, 'question-blank-sample-1280x1400.png');
  });

  testWidgets('填空下划线样例 2560×1400', (tester) async {
    final sample = (await QuestionRepository(database)
        .findBySerialNo(_blankSampleSerial))!;
    await _pumpDetail(
      tester,
      database,
      sample.id,
      size: const Size(2560, 1400),
    );
    await _capture(tester, 'question-blank-sample-2560x1400.png');
  });

  testWidgets('短选项两列样例 1280×1400', (tester) async {
    final sample = (await QuestionRepository(database)
        .findBySerialNo(_shortOptionsSampleSerial))!;
    await _pumpDetail(
      tester,
      database,
      sample.id,
      size: const Size(1280, 1400),
    );
    await _capture(tester, 'question-options-short-1280x1400.png');
  });

  testWidgets('短选项两列样例 2560×1400', (tester) async {
    final sample = (await QuestionRepository(database)
        .findBySerialNo(_shortOptionsSampleSerial))!;
    await _pumpDetail(
      tester,
      database,
      sample.id,
      size: const Size(2560, 1400),
    );
    await _capture(tester, 'question-options-short-2560x1400.png');
  });

  testWidgets('长选项单列样例 1280×1600', (tester) async {
    final sample = (await QuestionRepository(database)
        .findBySerialNo(_longOptionsSampleSerial))!;
    await _pumpDetail(
      tester,
      database,
      sample.id,
      size: const Size(1280, 1600),
    );
    await _capture(tester, 'question-options-long-1280x1600.png');
  });

  testWidgets('长选项单列样例 2560×1600', (tester) async {
    final sample = (await QuestionRepository(database)
        .findBySerialNo(_longOptionsSampleSerial))!;
    await _pumpDetail(
      tester,
      database,
      sample.id,
      size: const Size(2560, 1600),
    );
    await _capture(tester, 'question-options-long-2560x1600.png');
  });
}

/// 填空样例题的题号（副本里现分配，只用于定位）。
const int _blankSampleSerial = 663;

/// 短选项 / 长选项样例题的题号。
const int _shortOptionsSampleSerial = 664;
const int _longOptionsSampleSerial = 665;

Future<AppDatabase> _openDatabaseCopy() async {
  final dir = Directory('$_outDir\\db-copy');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  final target = File('${dir.path}\\furnace.db');
  final source = File(_realDb);
  if (!source.existsSync()) {
    throw StateError('真实题库不存在：$_realDb');
  }
  source.copySync(target.path);
  return AppDatabase.forTesting(NativeDatabase(target));
}

/// 复制出来的临时库里插一道「填空 + LaTeX」样例（不碰真实题库）。
Future<void> _insertBlankSample(AppDatabase database) async {
  final existing = await QuestionRepository(database).findBySerialNo(
    _blankSampleSerial,
  );
  if (existing != null) {
    return;
  }
  final result = await QuestionRepository(database).ingest(
    const QuestionDraft(
      stem: '已知反应 '
          r'$\Delta H=-57.3\,\mathrm{kJ\cdot mol^{-1}}$'
          '，该反应在常温下 ______。'
          '\n\n(1) 若升高温度，平衡 ______（填「正向移动」或「逆向移动」）。',
      answer: '自发；逆向移动',
      subjectKey: 'chemistry',
      questionType: 'fill_blank',
      sourceLevel: 'personal',
      year: 2026,
      region: '质检样例',
      textFormat: 'markdown',
      origin: 'manual',
      state: 'structured',
    ),
  );
  await (database.update(database.questions)
        ..where((row) => row.id.equals(result.question.id)))
      .write(
    const QuestionsCompanion(
      serialNo: Value<int?>(_blankSampleSerial),
      title: Value<String>('填空下划线样例（截图用）'),
    ),
  );
}

final GlobalKey _captureKey = GlobalKey();

/// 复制出来的临时库里插两道「选项排布」样例题（不碰真实题库）：
/// 一道四个短选项（应排两列），一道四个长选项（应保持单列）。
Future<void> _insertOptionSamples(AppDatabase database) async {
  final repo = QuestionRepository(database);
  if (await repo.findBySerialNo(_shortOptionsSampleSerial) == null) {
    final short = await repo.ingest(
      const QuestionDraft(
        stem: '一定条件下，增大压强后该反应的平衡转化率将（　　）',
        answer: 'B',
        subjectKey: 'chemistry',
        questionType: 'single_choice',
        sourceLevel: 'personal',
        year: 2026,
        region: '质检样例',
        textFormat: 'markdown',
        origin: 'manual',
        state: 'structured',
        options: <QuestionOptionDraft>[
          QuestionOptionDraft(label: 'A', content: '增大', sortOrder: 0),
          QuestionOptionDraft(
            label: 'B',
            content: '减小',
            isCorrect: true,
            sortOrder: 1,
          ),
          QuestionOptionDraft(label: 'C', content: '不变', sortOrder: 2),
          QuestionOptionDraft(label: 'D', content: '无法确定', sortOrder: 3),
        ],
      ),
    );
    await (database.update(database.questions)
          ..where((row) => row.id.equals(short.question.id)))
        .write(
      const QuestionsCompanion(
        serialNo: Value<int?>(_shortOptionsSampleSerial),
        title: Value<String>('短选项两列样例（截图用）'),
      ),
    );
  }
  if (await repo.findBySerialNo(_longOptionsSampleSerial) == null) {
    final long = await repo.ingest(
      const QuestionDraft(
        stem: '关于该实验现象，下列说法正确的是（　　）',
        answer: 'B',
        subjectKey: 'chemistry',
        questionType: 'single_choice',
        sourceLevel: 'personal',
        year: 2026,
        region: '质检样例',
        textFormat: 'markdown',
        origin: 'manual',
        state: 'structured',
        options: <QuestionOptionDraft>[
          QuestionOptionDraft(
            label: 'A',
            content: '常温下该反应可以自发进行，是因为生成物的总能量低于反应物',
            sortOrder: 0,
          ),
          QuestionOptionDraft(
            label: 'B',
            content: '升高温度会同时加快正逆反应速率，但平衡不发生移动',
            isCorrect: true,
            sortOrder: 1,
          ),
          QuestionOptionDraft(
            label: 'C',
            content: '加入催化剂只能改变反应速率，不能改变反应的焓变',
            sortOrder: 2,
          ),
          QuestionOptionDraft(
            label: 'D',
            content: '增大压强后平衡向气体分子数减小的方向移动，转化率提高',
            sortOrder: 3,
          ),
        ],
      ),
    );
    await (database.update(database.questions)
          ..where((row) => row.id.equals(long.question.id)))
        .write(
      const QuestionsCompanion(
        serialNo: Value<int?>(_longOptionsSampleSerial),
        title: Value<String>('长选项单列样例（截图用）'),
      ),
    );
  }
}

Future<void> _loadFonts() async {
  final noto =
      File(r'E:\Projects\Furnace\app\assets\fonts\noto-sans-sc-regular.ttf');
  if (noto.existsSync()) {
    final bytes = await noto.readAsBytes();
    final loader = FontLoader('Noto Sans SC')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
  final icons = File(
    r'D:\flutter\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
  );
  if (icons.existsSync()) {
    final bytes = await icons.readAsBytes();
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

ThemeData _theme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3D8B63),
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF101211),
    fontFamily: 'Noto Sans SC',
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1B1D1C),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
  );
}

List<Override> _overrides(AppDatabase database) => <Override>[
      appDatabaseProvider.overrideWithValue(database),
      modelAdapterProvider.overrideWithValue(null),
      questionMediaSupportDirectoryProvider.overrideWithValue(
        () async => Directory(_realMediaDir),
      ),
    ];

Future<void> _pumpBank(
  WidgetTester tester,
  AppDatabase database, {
  required Size size,
}) async {
  await _pump(
    tester,
    size: size,
    database: database,
    child: const QuestionBankPage(),
  );
}

Future<void> _pumpDetail(
  WidgetTester tester,
  AppDatabase database,
  String questionId, {
  required Size size,
}) async {
  await _pump(
    tester,
    size: size,
    database: database,
    child: QuestionDetailPage(questionId: questionId),
  );
  // 图片字节与图片解码都是**真实异步**（dart:io + 图片解码器）：
  // 先让真实事件循环跑几轮，再把完成后的状态 pump 出来，否则截图里是占位空白。
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required AppDatabase database,
  required Widget child,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(database),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: _theme(),
        // 真实应用在 FurnaceApp 根部挂了 MarkdownThemeScope；截图脚本没有经过
        // 那一层，这里补上并指定仓库自带的中文字体，否则 Markdown 正文会落到
        // 测试环境的默认字体（豆腐块），截图就不是真实观感。
        home: MarkdownThemeScope(
          theme: MarkdownRenderTheme.paper.copyWith(
            cjkFontFamily: 'Noto Sans SC',
            latinFontFamily: 'Noto Sans SC',
          ),
          child: RepaintBoundary(key: _captureKey, child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory(_outDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('$_outDir\\$name');
    file.writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('SCREENSHOT ${file.path} (${file.lengthSync()} bytes)');
    image.dispose();
  });
}
