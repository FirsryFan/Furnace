/// 生成题目详情页的学生视图 / 开发者信息页截图（1280×720 主验收图）。
///
/// 运行方式（在工作区 Furnace app 目录下）：
///
///   flutter test tool/student_ui_screenshot.dart
///
/// 与普通 widget 测试不同，这个脚本的真实职责是**落盘 PNG**：把真实的
/// `QuestionDetailPage` / `QuestionDeveloperPage` 用真实中文字体（Noto Sans SC，
/// 见 `assets/fonts/`）渲染出来，写到工作区 `.work/student-ui-clean-2026-11-15/`。
/// 不是 CI 用例：它依赖 Windows 本机字体缓存里的 MaterialIcons（Flutter SDK
/// 自带），跑不到就跳过图标字体而不是失败。
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
import 'package:furnace/domain/services/questions/question_intake_audit.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/questions/application/question_audit_reader.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/presentation/question_developer_page.dart';
import 'package:furnace/features/questions/presentation/question_detail_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../test/features/questions/presentation/support/question_media_fakes.dart';

const String _outDir =
    r'E:\Workspaces\agent-control\10-projects\agent-control-plane\.work\student-ui-clean-2026-11-15';

const String _stem =
    '15．为研究某疾病与超声波检查结果的关系，从做过超声波检查的人群中随机调查了1000人，得到如下列联表：\n\n'
    '| 超声波检查结果组别 | 正常 | 不正常 | 合计 |\n'
    '| --- | --- | --- | --- |\n'
    '| 患该疾病 | 20 | 180 | 200 |\n'
    '| 未患该疾病 | 780 | 20 | 800 |\n'
    '| 合计 | 800 | 200 | 1000 |\n\n'
    r'(1)记超声波检查结果不正常者患该疾病的概率为p，求p的估计值；' '\n\n'
    r'(2)根据小概率值$\alpha=0.001$的独立性检验，分析超声波检查结果是否与患该疾病有关.' '\n\n'
    r'附${\chi}^{2}=\frac{n{(ad-bc)}^{2}}{(a+b)(c+d)(a+c)(b+d)}$，' '\n\n'
    r'| $P\left( {\chi}^{2}\ge k \right)$ | 0.050 | 0.010 | 0.001 |' '\n'
    '| --- | --- | --- | --- |\n'
    r'| $k$ | 3.841 | 6.635 | 10.828 |';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadFonts();
  final zh = await AppLocalizations.delegate.load(const Locale('zh'));

  testWidgets('学生视图 1280×720', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final question = await _seedQuestion(database);
    await _pumpPage(
      tester,
      size: const Size(1280, 720),
      home: QuestionDetailPage(questionId: question.id),
      database: database,
    );
    await _settle(tester);
    await _capture(tester, 'student-detail-1280x720.png');
  });

  testWidgets('学生视图整页 1280×1900', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final question = await _seedQuestion(database);
    await _pumpPage(
      tester,
      size: const Size(1280, 1900),
      home: QuestionDetailPage(questionId: question.id),
      database: database,
    );
    await _settle(tester);
    await _capture(tester, 'student-detail-full-1280x1900.png');
  });

  testWidgets('学生视图窄屏 640×720', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final question = await _seedQuestion(database);
    await _pumpPage(
      tester,
      size: const Size(640, 720),
      home: QuestionDetailPage(questionId: question.id),
      database: database,
    );
    await _settle(tester);
    await _capture(tester, 'student-detail-640x720.png');
  });

  testWidgets('开发者信息页 1280×1000', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final question = await _seedQuestion(database);
    await _pumpPage(
      tester,
      size: const Size(1280, 1000),
      home: QuestionDeveloperPage(questionId: question.id),
      database: database,
    );
    await _settle(tester);
    await _capture(tester, 'question-developer-1280x1000.png');
    expect(zh.questionDeveloperEntry, '开发者信息');
  });
}

final GlobalKey _captureKey = GlobalKey();

Future<void> _loadFonts() async {
  // 中文字体：仓库自带，保证截图里的题干/表格/按钮不是豆腐块。
  final noto = File(r'E:\Projects\Furnace\app\assets\fonts\noto-sans-sc-regular.ttf');
  if (noto.existsSync()) {
    final bytes = await noto.readAsBytes();
    final loader = FontLoader('Noto Sans SC')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
  // 图标字体：用本机 Flutter SDK 自带的 MaterialIcons；找不到就算了。
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
    seedColor: const Color(0xFF2F6F4F),
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

Future<void> _pumpPage(
  WidgetTester tester, {
  required Size size,
  required Widget home,
  required AppDatabase database,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        modelAdapterProvider.overrideWithValue(null),
        questionMediaStoreProvider.overrideWithValue(
          FakeQuestionMediaStore(database: database),
        ),
        questionAuditReportProvider.overrideWith(
          (ref) async => const QuestionAuditReport(findings: []),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: _theme(),
        home: RepaintBoundary(key: _captureKey, child: home),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 推进几帧吃掉异步 provider 的首轮加载。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
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

/// 真实题库里的一道题（TR-00655 的题面，来源/状态按开发数据填满）。
Future<Question> _seedQuestion(AppDatabase database) async {
  final repository = QuestionRepository(database);
  final result = await repository.ingest(
    const QuestionDraft(
      stem: _stem,
      answer: '(1) \\frac{9}{10}\n(2) 有关',
      solution: r'先读列联表，再代 $\chi^2$ 公式。',
      subjectKey: 'math',
      questionType: 'single_choice',
      sourceLevel: 'gaokao',
      sourceLabel: '2025 高考全国一卷',
      year: 2025,
      region: '全国一卷',
      textFormat: 'markdown',
      origin: 'content_package',
      state: 'structured',
      aiQuality: 0.42,
      difficulty: 3,
      options: <QuestionOptionDraft>[
        QuestionOptionDraft(label: 'A', content: '有关', isCorrect: true),
        QuestionOptionDraft(label: 'B', content: '无关'),
        QuestionOptionDraft(label: 'C', content: '无法判断'),
        QuestionOptionDraft(label: 'D', content: '以上都不对'),
      ],
    ),
  );
  await (database.update(database.questions)
        ..where((row) => row.id.equals(result.question.id)))
      .write(const QuestionsCompanion(
    serialNo: Value<int?>(655),
    title: Value<String>('列联表独立性检验'),
  ));
  return (await repository.byId(result.question.id))!;
}
