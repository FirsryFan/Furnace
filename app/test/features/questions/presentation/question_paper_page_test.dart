/// 组卷页（Q10a）的界面契约：页面只排版，不另写措辞。
///
/// 三条纪律：
/// 1. 理由 / 提升点 / 知识背景与档位标签**原样**来自领域层（`PaperPlan` →
///    `PaperItem` / `PaperZone.labelZh`）。这里断言的就是领域层那几句原文——
///    改域层文案时这些断言应该跟着红，而不是被页面"顺手改好"。
/// 2. 缺口不是错误：没有候选（去收题）与这轮被挤掉（调大题数）是两句话；
///    空题库与条件太窄也是两句话。
/// 3. `cognitiveLibraryDiagnosisProvider` 一律注入：真实实现即使在空库上也会先读
///    `cognitiveModelProvider`。"快层没跑"用 `LibraryDiagnosis.notRun` 表示，
///    它和"跑过但没报告"不是一回事。
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/fast_diagnosis.dart';
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';
import 'package:furnace/features/questions/application/paper_plan_provider.dart';
import 'package:furnace/features/questions/presentation/question_intake_page.dart';
import 'package:furnace/features/questions/presentation/question_intake_providers.dart';
import 'package:furnace/features/questions/presentation/question_paper_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../support/picked_file_fakes.dart';

/// 固定时间戳：让"最近"这种排序在测试里也是确定的。
const int _ts = 1700000000000;

void main() {
  late AppDatabase db;
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('题库为空时给出可读空态，而不是错误', (tester) async {
    await _pumpPaperPage(tester, db: db);

    expect(find.text(zh.questionPaperEmptyBank), findsOneWidget);
    expect(find.text(zh.questionPaperEmptyPlan), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // 控制区也在，学科没有可选项时说"不限学科"。
    expect(find.text(zh.questionPaperSubjectAny), findsOneWidget);
    expect(find.text(zh.questionPaperTargetCountLabel), findsOneWidget);
  });

  testWidgets('有候选时展示序号、档位 chip 与领域层给的三段原文', (tester) async {
    await _seedKnowledgePoint(
      db,
      id: 'kp-quadratic',
      title: '二次函数',
      tagId: 'tag-quadratic',
    );
    await _seedQuestion(
      db,
      id: 'q-1',
      stem: '求二次函数的最小值',
      subjectKey: 'math',
      sourceLevel: 'gaokao',
      trapNote: '别忘了定义域',
    );
    await _linkQuestionToTag(db, questionId: 'q-1', tagId: 'tag-quadratic');

    await _pumpPaperPage(tester, db: db);

    expect(find.text(zh.questionPaperItemIndex(1)), findsOneWidget);
    // 没有读数 = zone unknown，chip 文案来自 PaperZone.labelZh。
    expect(find.text('没有读数'), findsOneWidget);
    expect(find.text('${zh.questionPaperKnowledgePointLabel}：二次函数'),
        findsOneWidget);
    // reasonZh 原文（未知档那一句）。
    expect(
      find.text('知识点「二次函数」还没有你的读数，按未知处理（未知不当作健康）。'),
      findsOneWidget,
    );
    // improvementNote 原文 + trapNote 附在末尾。
    expect(
      find.text('先做一遍并把结果记进系统，下一轮才知道它属于哪一档。 这题的已知坑：别忘了定义域'),
      findsOneWidget,
    );
    // 三个标签都在（背景那段也渲染出来了）。
    expect(find.text(zh.questionPaperItemReasonLabel), findsOneWidget);
    expect(find.text(zh.questionPaperItemImprovementLabel), findsOneWidget);
    expect(find.text(zh.questionPaperItemBackgroundLabel), findsOneWidget);
    expect(find.text('二次函数'), findsWidgets);
  });

  testWidgets('凑不够时头部说明"题库不够"，并给出两位小数的整体该练程度', (tester) async {
    await _seedQuestion(db, id: 'q-1', stem: '第一题', subjectKey: 'math');
    await _seedQuestion(db, id: 'q-2', stem: '第二题', subjectKey: 'math');

    await _pumpPaperPage(tester, db: db);

    expect(find.text(zh.questionPaperHeadline(10, 2)), findsOneWidget);
    expect(
      find.text(
        '${zh.questionPaperCandidateCount(2)} · ${zh.questionPaperOverallNeed('0.35')}',
      ),
      findsOneWidget,
    );
    expect(find.text(zh.questionPaperShortNotice), findsOneWidget);
    expect(find.text(zh.questionPaperEmptyBank), findsNothing);
  });

  testWidgets('切换目标题数后卷子题数跟着变', (tester) async {
    for (var i = 1; i <= 6; i++) {
      await _seedQuestion(db, id: 'q-$i', stem: '第 $i 题', subjectKey: 'math');
    }

    await _pumpPaperPage(tester, db: db);
    expect(find.text(zh.questionPaperHeadline(10, 6)), findsOneWidget);

    // 真实交互：打开目标题数下拉，选 5 道。
    // 页面上有两个 `DropdownButtonFormField<int>`（目标题数 / 每个知识点上限），
    // 所以按"当前显示的文案"定位这个下拉，而不是按类型（按类型会匹配到两个）。
    await tester.tap(
      find.widgetWithText(
        DropdownButtonFormField<int>,
        zh.questionPaperCountOption(10),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(zh.questionPaperCountOption(5)).last);
    await _settle(tester);

    expect(find.text(zh.questionPaperHeadline(5, 5)), findsOneWidget);
    expect(find.text(zh.questionPaperShortNotice), findsNothing);
    expect(find.text(zh.questionPaperItemIndex(6)), findsNothing);
  });

  testWidgets('来源下限把低来源的候选挡在外面', (tester) async {
    await _seedQuestion(
      db,
      id: 'q-g1',
      stem: '高考题一',
      subjectKey: 'math',
      sourceLevel: 'gaokao',
    );
    await _seedQuestion(
      db,
      id: 'q-g2',
      stem: '高考题二',
      subjectKey: 'math',
      sourceLevel: 'gaokao',
    );
    await _seedQuestion(
      db,
      id: 'q-p1',
      stem: '自建题一',
      subjectKey: 'math',
      sourceLevel: 'personal',
    );
    await _seedQuestion(
      db,
      id: 'q-p2',
      stem: '自建题二',
      subjectKey: 'math',
      sourceLevel: 'personal',
    );

    await _pumpPaperPage(tester, db: db);
    expect(find.text(zh.questionPaperHeadline(10, 4)), findsOneWidget);

    final container = _container(tester);
    container.read(paperSpecProvider.notifier).setMinSourceLevel('gaokao');
    await _settle(tester);

    expect(find.text(zh.questionPaperHeadline(10, 2)), findsOneWidget);
    expect(find.text(zh.questionPaperShortNotice), findsOneWidget);
  });

  testWidgets('学科 chip 只留下选中的学科', (tester) async {
    await _seedQuestion(db, id: 'q-m', stem: '数学题', subjectKey: 'math');
    await _seedQuestion(db, id: 'q-p', stem: '物理题', subjectKey: 'physics');

    await _pumpPaperPage(tester, db: db);
    expect(find.text(zh.questionPaperHeadline(10, 2)), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '数学'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '物理'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '数学'));
    await _settle(tester);

    expect(find.text(zh.questionPaperHeadline(10, 1)), findsOneWidget);
  });

  testWidgets('注入的危险区/发展区结论决定档位 chip 与理由原文', (tester) async {
    await _seedKnowledgePoint(db, id: 'kp-a', title: 'Alpha', tagId: 'tag-a');
    await _seedKnowledgePoint(db, id: 'kp-b', title: 'Beta', tagId: 'tag-b');
    await _seedQuestion(db, id: 'q-a', stem: 'Alpha 题', subjectKey: 'math');
    await _seedQuestion(db, id: 'q-b', stem: 'Beta 题', subjectKey: 'math');
    await _linkQuestionToTag(db, questionId: 'q-a', tagId: 'tag-a');
    await _linkQuestionToTag(db, questionId: 'q-b', tagId: 'tag-b');

    await _pumpPaperPage(
      tester,
      db: db,
      diagnosis: const LibraryDiagnosis(
        byKnowledgePoint: {
          'kp-a': BottleneckType.danger,
          'kp-b': BottleneckType.weak
        },
        fastLayerRan: true,
        rounds: 3,
      ),
    );

    expect(find.text('危险区'), findsOneWidget);
    expect(find.text('发展区'), findsOneWidget);
    expect(find.text('没有读数'), findsNothing);
    expect(
      find.text('知识点「Alpha」在危险区（自信高、实际提取不出来），这份卷先练它。'),
      findsOneWidget,
    );
    expect(
      find.text('知识点「Beta」在发展区（有读数但还偏弱），现在练收益最大。'),
      findsOneWidget,
    );
    // 危险区的提升点原文也来自域层。
    expect(find.text('别整套刷：只把关键那一步慢速重做一遍，并写出每一步的依据。'), findsOneWidget);
  });

  testWidgets('危险区但题库里没有候选 → 如实列出"去收题"，不当成没问题', (tester) async {
    await _seedKnowledgePoint(db, id: 'kp-a', title: 'Alpha', tagId: 'tag-a');
    await _seedKnowledgePoint(db, id: 'kp-e', title: 'Epsilon', tagId: 'tag-e');
    await _seedQuestion(
      db,
      id: 'q-a',
      stem: 'Alpha 高考题',
      subjectKey: 'math',
      sourceLevel: 'gaokao',
    );
    await _seedQuestion(
      db,
      id: 'q-e',
      stem: 'Epsilon 自建题',
      subjectKey: 'math',
      sourceLevel: 'personal',
    );
    await _linkQuestionToTag(db, questionId: 'q-a', tagId: 'tag-a');
    await _linkQuestionToTag(db, questionId: 'q-e', tagId: 'tag-e');

    await _pumpPaperPage(
      tester,
      db: db,
      diagnosis: const LibraryDiagnosis(
        byKnowledgePoint: {
          'kp-a': BottleneckType.danger,
          'kp-e': BottleneckType.danger
        },
        fastLayerRan: true,
        rounds: 3,
      ),
    );

    // 把来源下限提到高考真题：Epsilon 只剩自建题 → 一道候选都没有。
    _container(tester)
        .read(paperSpecProvider.notifier)
        .setMinSourceLevel('gaokao');
    await _settle(tester);

    expect(find.text(zh.questionPaperUncoveredTitle), findsOneWidget);
    expect(find.text(zh.questionPaperUncoveredBody), findsOneWidget);
    expect(find.text('• Epsilon'), findsOneWidget);
    expect(find.text(zh.questionPaperDeferredTitle), findsNothing);
    expect(find.text(zh.questionPaperHeadline(10, 1)), findsOneWidget);
  });

  testWidgets('有候选但被配额挤掉 → 列进"这轮被挤掉"，不是"没有候选"', (tester) async {
    for (final point in ['a', 'b', 'c', 'd']) {
      await _seedKnowledgePoint(
        db,
        id: 'kp-$point',
        title: point.toUpperCase(),
        tagId: 'tag-$point',
      );
    }
    for (final point in ['a', 'b', 'c']) {
      for (var i = 1; i <= 2; i++) {
        final id = 'q-$point$i';
        await _seedQuestion(
          db,
          id: id,
          stem: '$point$i',
          subjectKey: 'math',
          sourceLevel: 'gaokao',
        );
        await _linkQuestionToTag(db, questionId: id, tagId: 'tag-$point');
      }
    }
    for (var i = 1; i <= 2; i++) {
      final id = 'q-d$i';
      await _seedQuestion(
        db,
        id: id,
        stem: 'd$i',
        subjectKey: 'math',
        sourceLevel: 'personal',
      );
      await _linkQuestionToTag(db, questionId: id, tagId: 'tag-d');
    }

    await _pumpPaperPage(
      tester,
      db: db,
      diagnosis: const LibraryDiagnosis(
        byKnowledgePoint: {
          'kp-a': BottleneckType.danger,
          'kp-b': BottleneckType.danger,
          'kp-c': BottleneckType.danger,
          'kp-d': BottleneckType.danger,
        },
        fastLayerRan: true,
        rounds: 3,
      ),
    );

    // 目标 5 道、4 个知识点 → 每个点默认上限 ceil(5/4)=2 → 只有三个点进得来。
    _container(tester).read(paperSpecProvider.notifier).setTargetCount(5);
    await _settle(tester);

    expect(find.text(zh.questionPaperHeadline(5, 5)), findsOneWidget);
    expect(find.text(zh.questionPaperDeferredTitle), findsOneWidget);
    expect(find.text(zh.questionPaperDeferredBody), findsOneWidget);
    expect(find.text('• D'), findsOneWidget);
    expect(find.text(zh.questionPaperUncoveredTitle), findsNothing);
  });

  testWidgets('收题页 AppBar 有进组卷页的入口', (tester) async {
    final supportRoot =
        Directory.systemTemp.createTempSync('furnace_paper_entry_');
    addTearDown(() {
      if (supportRoot.existsSync()) {
        supportRoot.deleteSync(recursive: true);
      }
    });

    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          handwritingIntakeStoreProvider.overrideWithValue(
            FakeIntakeStore(database: db, root: supportRoot),
          ),
          cognitiveLibraryDiagnosisProvider.overrideWith(
            (ref) async => LibraryDiagnosis.notRun,
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: QuestionIntakePage(),
        ),
      ),
    );
    await _settle(tester);

    expect(find.byIcon(Icons.playlist_add_check), findsOneWidget);
    await tester.tap(find.byTooltip(zh.questionPaperTitle));
    await _settle(tester);

    expect(find.byType(QuestionPaperPage), findsOneWidget);
    expect(find.text(zh.questionPaperSubtitle), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // spec 控件（Q17）：目标难度 / 每个知识点上限 / 重置
  // -------------------------------------------------------------------------

  testWidgets('目标难度：下拉选一个值后 spec 与页面回显都跟着变，也能选回"不限"', (tester) async {
    await _seedQuestion(db, id: 'q-1', stem: '第一题', subjectKey: 'math');
    await _seedQuestion(db, id: 'q-2', stem: '第二题', subjectKey: 'math');

    await _pumpPaperPage(tester, db: db);
    final container = _container(tester);

    // 默认"不限难度"。
    expect(container.read(paperSpecProvider).targetDifficulty, isNull);
    expect(_difficultyDropdownValue(), isNull);

    await tester.tap(
      find.widgetWithText(
        DropdownButtonFormField<double>,
        zh.questionPaperDifficultyAny,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(zh.questionPaperDifficultyOption('5.5')).last);
    // 菜单路由的退场动画要跑完：否则菜单项与输入框回显会同时命中同一段文字。
    await tester.pump(const Duration(milliseconds: 600));
    await _settle(tester);

    expect(container.read(paperSpecProvider).targetDifficulty, 5.5);
    // "不限难度"这一项始终在 DropdownButton 的 IndexedStack 里，不能靠文字判断选中，
    // 只能看这个下拉当前的值。
    expect(_difficultyDropdownValue(), 5.5);

    // 选回"不限"：null 与"没改过"要靠下拉的取值区分开。
    await tester.tap(
      find.widgetWithText(
        DropdownButtonFormField<double>,
        zh.questionPaperDifficultyOption('5.5'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(zh.questionPaperDifficultyAny).last);
    await tester.pump(const Duration(milliseconds: 600));
    await _settle(tester);

    expect(container.read(paperSpecProvider).targetDifficulty, isNull);
    expect(_difficultyDropdownValue(), isNull);
  });

  testWidgets('目标难度参与挑题：设了目标后，填了难度的候选排到没填难度的前面', (tester) async {
    // 两条候选只有"填没填难度"不同（同一来源、无知识点、无 AI 质量分），
    // 所以分数差异只可能来自难度贴合度：1.0 vs 0.5（没填难度＝半贴合，不排除）。
    await _seedQuestion(db, id: 'q-1', stem: '没填难度', subjectKey: 'math');
    await _seedQuestion(
      db,
      id: 'q-2',
      stem: '难度刚好 5.0',
      subjectKey: 'math',
      difficulty: 5.0,
    );

    await _pumpPaperPage(tester, db: db);
    final container = _container(tester);

    container.read(paperSpecProvider.notifier).setTargetDifficulty(5.0);
    await _settle(tester);
    await tester.pump();

    final plan = container.read(paperPlanProvider).value!;
    expect(plan.items.length, 2);
    expect(plan.items.first.questionId, 'q-2');
    expect(plan.items.last.questionId, 'q-1');
  });

  testWidgets('每个知识点上限：设成 1 后同一个知识点只进一道', (tester) async {
    await _seedKnowledgePoint(db, id: 'kp-a', title: '知识点甲', tagId: 'tag-a');
    for (var i = 1; i <= 2; i++) {
      await _seedQuestion(
        db,
        id: 'q-$i',
        stem: '第 $i 题',
        subjectKey: 'math',
        sourceLevel: 'gaokao',
      );
      await _linkQuestionToTag(db, questionId: 'q-$i', tagId: 'tag-a');
    }

    await _pumpPaperPage(tester, db: db);
    // 自动配额下两道都进卷。
    expect(find.text(zh.questionPaperHeadline(10, 2)), findsOneWidget);

    final container = _container(tester);
    container.read(paperSpecProvider.notifier).setPerKnowledgePointCap(1);
    await _settle(tester);

    expect(container.read(paperSpecProvider).perKnowledgePointCap, 1);
    expect(find.text(zh.questionPaperHeadline(10, 1)), findsOneWidget);
    expect(find.text(zh.questionPaperItemIndex(2)), findsNothing);
  });

  testWidgets('重置：目标题数/学科/来源下限/难度/上限一起回到默认', (tester) async {
    await _seedQuestion(
      db,
      id: 'q-1',
      stem: '第一题',
      subjectKey: 'math',
      sourceLevel: 'gaokao',
    );
    await _seedQuestion(
      db,
      id: 'q-2',
      stem: '第二题',
      subjectKey: 'physics',
      sourceLevel: 'personal',
    );

    await _pumpPaperPage(tester, db: db);
    final container = _container(tester);
    final notifier = container.read(paperSpecProvider.notifier);

    // 五个条件全改掉：目标题数 / 学科 / 来源下限 / 难度 / 每点上限。
    notifier.setTargetCount(5);
    notifier.toggleSubject('math');
    notifier.setMinSourceLevel('gaokao');
    notifier.setTargetDifficulty(8.5);
    notifier.setPerKnowledgePointCap(3);
    await _settle(tester);

    var spec = container.read(paperSpecProvider);
    expect(spec.targetCount, 5);
    expect(spec.subjectKeys, <String>{'math'});
    expect(spec.minSourceLevel, 'gaokao');
    expect(spec.targetDifficulty, 8.5);
    expect(spec.perKnowledgePointCap, 3);
    // 页面回显的也是改后的值。
    expect(find.text(zh.questionPaperCountOption(5)), findsOneWidget);
    expect(find.text(zh.questionPaperDifficultyOption('8.5')), findsOneWidget);
    expect(find.text(zh.questionPaperCapOption(3)), findsOneWidget);

    // 用户按「重置组卷条件」。
    await tester.tap(find.text(zh.questionPaperReset));
    await _settle(tester);

    spec = container.read(paperSpecProvider);
    expect(spec.targetCount, 10);
    expect(spec.subjectKeys, isEmpty);
    expect(spec.minSourceLevel, isNull);
    expect(spec.targetDifficulty, isNull);
    expect(spec.perKnowledgePointCap, isNull);
    // 页面上显示的 spec 与默认一致。
    expect(find.text(zh.questionPaperCountOption(10)), findsOneWidget);
    expect(find.text(zh.questionPaperDifficultyAny), findsOneWidget);
    expect(find.text(zh.questionPaperCapAuto), findsOneWidget);
    expect(find.text(zh.questionPaperSourceLevelAny), findsOneWidget);
  });

  testWidgets('空题库：难度/上限/重置三个控件照常显示，改条件与重置都不崩', (tester) async {
    await _pumpPaperPage(tester, db: db);

    expect(find.text(zh.questionPaperDifficultyLabel), findsOneWidget);
    expect(find.text(zh.questionPaperDifficultyAny), findsOneWidget);
    expect(find.text(zh.questionPaperCapLabel), findsOneWidget);
    expect(find.text(zh.questionPaperCapAuto), findsOneWidget);
    expect(find.text(zh.questionPaperReset), findsOneWidget);
    expect(find.text(zh.questionPaperEmptyBank), findsOneWidget);

    final container = _container(tester);
    container.read(paperSpecProvider.notifier).setTargetDifficulty(3.0);
    container.read(paperSpecProvider.notifier).setPerKnowledgePointCap(2);
    await _settle(tester);

    // 空库上改条件：还是那句空态，不抛异常。
    expect(find.text(zh.questionPaperEmptyBank), findsOneWidget);
    expect(find.text(zh.questionPaperDifficultyOption('3.0')), findsOneWidget);

    await tester.tap(find.text(zh.questionPaperReset));
    await _settle(tester);
    expect(container.read(paperSpecProvider).targetDifficulty, isNull);
    expect(container.read(paperSpecProvider).perKnowledgePointCap, isNull);
    expect(find.text(zh.questionPaperDifficultyAny), findsOneWidget);
  });

  testWidgets('目标题数不在预设档位里也不崩：当前值补进下拉（"恢复上次 spec"的防线）', (tester) async {
    await _pumpPaperPage(tester, db: db);

    // 不走下拉、直接改 spec —— 模拟"恢复上次 spec / 导入配置"这类路径。
    // 预设档位只有 5/10/15/20，而 setTargetCount 收 1..200：值不在 items 里时
    // DropdownButton 会直接断言崩溃（There should be exactly one item ...）。
    _container(tester).read(paperSpecProvider.notifier).setTargetCount(3);
    await _settle(tester);
    expect(tester.takeException(), isNull);

    // 当前值以"多出来的一档"出现在下拉里（关闭态只渲染选中项，所以只看 3）。
    expect(find.text(zh.questionPaperCountOption(3)), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.widgetWithText(
              DropdownButtonFormField<int>,
              zh.questionPaperCountOption(3),
            ),
          )
          .initialValue,
      3,
    );

    // 选项列表本身：预设档位一个不少，当前值插进来且仍是有序的。
    expect(targetCountOptionsFor(3), <int>[3, 5, 10, 15, 20]);
    expect(targetCountOptionsFor(10), paperTargetCountOptions);
    expect(targetCountOptionsFor(200), <int>[5, 10, 15, 20, 200]);
    // 0 / 负数不是合法题数（setTargetCount 钳 1..200），不额外造一档。
    expect(targetCountOptionsFor(0), paperTargetCountOptions);
  });

  testWidgets('能力动作画像：有开关与说明，关掉后加成消失、说明行也消失', (tester) async {
    // 两道条件完全相同的题，差别只在"有没有链、链里是什么动作"。
    await _seedQuestion(db,
        id: 'q-no-chain', stem: '没有链的题', subjectKey: 'math');
    await _seedQuestion(db,
        id: 'q-with-chain', stem: '有链的题', subjectKey: 'math');
    await _seedChain(db, questionId: 'q-with-chain');

    final container = await _pumpPaperPage(tester, db: db);

    // 未标定的排序加成必须显式标注、能关：开关 + 说明 + "这一卷按什么排过"。
    expect(find.text(zh.questionPaperActionProfileLabel), findsOneWidget);
    expect(find.text(zh.questionPaperActionProfileHint), findsOneWidget);
    expect(
      find.text(zh.questionPaperActionProfileNote('分类讨论')),
      findsOneWidget,
    );
    final on = container.read(paperPlanProvider).value!;
    expect(on.preferredActionTypes, <String>['case_split']);
    expect(on.items.first.questionId, 'q-with-chain');

    // 关掉：加成没了、说明行消失，次序回到"没有画像"的样子（按 id 兜底）。
    container
        .read(paperSpecProvider.notifier)
        .setPreferCapabilityActions(false);
    await _settle(tester);

    expect(
      find.text(zh.questionPaperActionProfileNote('分类讨论')),
      findsNothing,
    );
    final off = container.read(paperPlanProvider).value!;
    expect(off.preferredActionTypes, isEmpty);
    expect(off.items.first.questionId, 'q-no-chain');
    expect(container.read(paperSpecProvider).preferCapabilityActions, isFalse);

    // 重置把开关也带回默认。
    await tester.tap(find.text(zh.questionPaperReset));
    await _settle(tester);
    expect(container.read(paperSpecProvider).preferCapabilityActions, isTrue);
  });

  // -------------------------------------------------------------------------
  // 「复制卷面」（Q20）：卷面变成可打印纯文本
  // -------------------------------------------------------------------------

  testWidgets('复制卷面：剪贴板里是逐题的序号/学科来源档位/理由，复制后有提示', (tester) async {
    await _seedKnowledgePoint(db, id: 'kp-a', title: '二次函数', tagId: 'tag-a');
    await _seedQuestion(
      db,
      id: 'q-1',
      stem: '第一题',
      subjectKey: 'math',
      sourceLevel: 'gaokao',
    );
    await _linkQuestionToTag(db, questionId: 'q-1', tagId: 'tag-a');

    await _pumpPaperPage(tester, db: db);
    final clipboard = _captureClipboard(tester);

    await tester.tap(_copyPaperButton());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final text = _copiedText(clipboard);
    expect(text, isNotNull, reason: '点了复制就应该往剪贴板写东西');
    // 第一行：想凑 10 道、凑到 1 道（顺序不能反）。
    expect(text, contains(zh.questionPaperHeadline(10, 1)));
    // 逐题一段：序号 + [学科] [来源] [档位]。
    expect(text, contains('1. [数学] [高考真题] [没有读数]'));
    // 知识点名单独一行。
    expect(text, contains('二次函数'));
    // 理由行是领域层原文，不在这里重写。
    expect(text, contains('${zh.questionPaperCopyReasonLabel}：'));
    expect(text, contains('还没有你的读数'));
    // 复制成功有提示。
    expect(find.text(zh.questionPaperCopyDone), findsOneWidget);
  });

  testWidgets('短卷：文本与页面都如实写"凑到几道"，不假装凑满', (tester) async {
    await _seedQuestion(db, id: 'q-1', stem: '第一题', subjectKey: 'math');
    await _seedQuestion(db, id: 'q-2', stem: '第二题', subjectKey: 'math');

    await _pumpPaperPage(tester, db: db);
    final clipboard = _captureClipboard(tester);
    await tester.tap(_copyPaperButton());
    await tester.pump();

    final text = _copiedText(clipboard)!;
    expect(text, contains(zh.questionPaperHeadline(10, 2)));
    // 明确挡住"想要 2 道，凑到 10 道"这种反过来的读法（回归防线）。
    expect(text.contains(zh.questionPaperHeadline(2, 10)), isFalse);
    expect(find.text(zh.questionPaperHeadline(10, 2)), findsOneWidget);
  });

  testWidgets('缺口：文本末尾如实列出未覆盖与这轮被挡下的知识点', (tester) async {
    // 四个危险区知识点，各有 2 道 gaokao 候选；第五个危险区知识点一道候选都没有。
    for (final suffix in <String>['a', 'b', 'c', 'd']) {
      final title = _gapPointTitle(suffix);
      await _seedKnowledgePoint(
        db,
        id: 'kp-$suffix',
        title: title,
        tagId: 'tag-$suffix',
      );
      for (final n in <int>[1, 2]) {
        await _seedQuestion(
          db,
          id: 'q-$suffix-$n',
          stem: '$title 第 $n 题',
          subjectKey: 'math',
          sourceLevel: 'gaokao',
        );
        await _linkQuestionToTag(
          db,
          questionId: 'q-$suffix-$n',
          tagId: 'tag-$suffix',
        );
      }
    }
    await _seedKnowledgePoint(db, id: 'kp-e', title: '知识点戊', tagId: 'tag-e');

    await _pumpPaperPage(
      tester,
      db: db,
      diagnosis: const LibraryDiagnosis(
        byKnowledgePoint: <String, BottleneckType>{
          'kp-a': BottleneckType.danger,
          'kp-b': BottleneckType.danger,
          'kp-c': BottleneckType.danger,
          'kp-d': BottleneckType.danger,
          'kp-e': BottleneckType.danger,
        },
        fastLayerRan: true,
        rounds: 2,
      ),
    );
    // 目标 5 道、四个点 → 每点上限 ceil(5/4)=2：前三个点 2+2+1 填满，
    // 第四个点的候选全被挡下（deferred）；戊点没候选（uncovered）。
    _container(tester).read(paperSpecProvider.notifier).setTargetCount(5);
    await _settle(tester);

    final clipboard = _captureClipboard(tester);
    await tester.tap(_copyPaperButton());
    await tester.pump();

    final text = _copiedText(clipboard)!;
    expect(text, contains('${zh.questionPaperCopyUncoveredHeading}：'));
    expect(text, contains('知识点戊'));
    expect(text, contains('${zh.questionPaperCopyDeferredHeading}：'));
    expect(text, contains('知识点丁'));
    // 进卷的知识点会在正文里；缺口段与正文两处都得如实出现名字。
    expect(text.contains('知识点甲'), isTrue);
    expect(text.contains('知识点乙'), isTrue);
  });

  testWidgets('空卷面：复制按钮禁用，点了不写剪贴板也不弹提示', (tester) async {
    await _pumpPaperPage(tester, db: db);
    final clipboard = _captureClipboard(tester);

    expect(
      _copyPaperButtonWidget(tester).onPressed,
      isNull,
      reason: '空卷面应该禁用复制，而不是复制出一个空壳',
    );

    await tester.tap(_copyPaperButton(), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_copiedText(clipboard), isNull);
    expect(find.text(zh.questionPaperCopyDone), findsNothing);
    // 空态文案还在（空卷是正常状态，不是错误）。
    expect(find.text(zh.questionPaperEmptyBank), findsOneWidget);
  });

  testWidgets('文本里不放题面与答案：卷面是给人做的，不是答案页', (tester) async {
    await _seedQuestion(
      db,
      id: 'q-1',
      stem: '独一无二的题干：求二次函数的最小值',
      subjectKey: 'math',
      answer: '独一无二的答案：最小值 -1',
    );

    await _pumpPaperPage(tester, db: db);
    final clipboard = _captureClipboard(tester);
    await tester.tap(_copyPaperButton());
    await tester.pump();

    final text = _copiedText(clipboard)!;
    expect(text.contains('独一无二的题干'), isFalse);
    expect(text.contains('独一无二的答案'), isFalse);
    // 但"为什么排它"这段领域层文案要在。
    expect(text, contains('${zh.questionPaperCopyReasonLabel}：'));
  });
}

/// 缺口用例里的知识点名：`a` → 知识点甲、`b` → 知识点乙……
String _gapPointTitle(String suffix) {
  const titles = <String, String>{
    'a': '知识点甲',
    'b': '知识点乙',
    'c': '知识点丙',
    'd': '知识点丁',
  };
  return titles[suffix]!;
}

/// 页面上的「复制卷面」按钮：卷面页只有这一个 `TextButton`。
Finder _copyPaperButton() {
  return find.byWidgetPredicate((widget) => widget is TextButton);
}

/// 取「复制卷面」按钮本体（用来断言"禁用"）。
TextButton _copyPaperButtonWidget(WidgetTester tester) {
  final finder = _copyPaperButton();
  expect(finder, findsOneWidget, reason: '卷面页应该只有一个「复制卷面」按钮');
  return tester.widget<TextButton>(finder);
}

/// 截住平台通道，收集写剪贴板的调用（`Clipboard.setData`）。
List<MethodCall> _captureClipboard(WidgetTester tester) {
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

/// 最近一次写进剪贴板的文本；一次都没写过（或写的不是文本）返回 null。
String? _copiedText(List<MethodCall> calls) {
  final setData = calls
      .where((call) => call.method == 'Clipboard.setData')
      .toList(growable: false);
  if (setData.isEmpty) return null;
  final arguments = setData.last.arguments;
  if (arguments is! Map) return null;
  final text = arguments['text'];
  return text is String ? text : null;
}

// ---------------------------------------------------------------------------
// 装置
// ---------------------------------------------------------------------------

Future<ProviderContainer> _pumpPaperPage(
  WidgetTester tester, {
  required AppDatabase db,
  LibraryDiagnosis diagnosis = LibraryDiagnosis.notRun,
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        cognitiveLibraryDiagnosisProvider
            .overrideWith((ref) async => diagnosis),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: QuestionPaperPage(),
      ),
    ),
  );
  await _settle(tester);
  return _container(tester);
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(QuestionPaperPage)));

/// 等 provider 落定：进度条消失后再多推两帧。
///
/// 不能用 `pumpAndSettle`——数据还没到时页面上是无限动画的进度条，会超时。
Future<void> _settle(WidgetTester tester, {int rounds = 80}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    final busy = find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    if (!busy && i >= 2) {
      return;
    }
  }
}

Future<void> _seedQuestion(
  AppDatabase db, {
  required String id,
  required String stem,
  String subjectKey = '',
  String sourceLevel = 'unknown',
  String? trapNote,
  double? difficulty,
  String? answer,
}) {
  return db.into(db.questions).insert(
        QuestionsCompanion.insert(
          id: id,
          stem: stem,
          createdAt: _ts,
          updatedAt: _ts,
          subjectKey: Value(subjectKey),
          sourceLevel: Value(sourceLevel),
          trapNote: Value(trapNote),
          difficulty: Value(difficulty),
          answer: Value(answer),
        ),
      );
}

/// 给一道题落一条链：链上两步都是 `case_split`（平均风险 0.85，过 0.6 的线）。
Future<void> _seedChain(
  AppDatabase db, {
  required String questionId,
}) async {
  await db.into(db.reasoningChains).insert(
        ReasoningChainsCompanion.insert(
          id: 'chain-$questionId',
          questionId: questionId,
          createdAt: _ts,
          summary: const Value('两步'),
          stepCount: const Value(2),
        ),
      );
  for (var i = 0; i < 2; i++) {
    await db.into(db.reasoningSteps).insert(
          ReasoningStepsCompanion.insert(
            id: 'step-$questionId-$i',
            chainId: 'chain-$questionId',
            idx: i,
            goal: '第 $i 步',
            actionType: const Value('case_split'),
            stuckRisk: const Value(0.85),
            createdAt: _ts,
          ),
        );
  }
}

Future<void> _seedKnowledgePoint(
  AppDatabase db, {
  required String id,
  required String title,
  required String tagId,
}) async {
  await db.into(db.knowledgePoints).insert(
        KnowledgePointsCompanion.insert(
          id: id,
          title: title,
          content: '',
          createdAt: _ts,
          updatedAt: _ts,
        ),
      );
  await db.into(db.tags).insert(
        TagsCompanion.insert(
          id: tagId,
          name: title,
          createdAt: _ts,
          updatedAt: _ts,
        ),
      );
  await db.into(db.objectTags).insert(
        ObjectTagsCompanion.insert(
          id: 'ot-$tagId-$id',
          tagId: tagId,
          objectType: 'knowledge_point',
          objectId: id,
          createdAt: _ts,
        ),
      );
}

/// 题目与知识点共享同一个标签 → 组卷器才认得出这道题挂在哪。
Future<void> _linkQuestionToTag(
  AppDatabase db, {
  required String questionId,
  required String tagId,
}) {
  return db.into(db.objectTags).insert(
        ObjectTagsCompanion.insert(
          id: 'ot-$tagId-$questionId',
          tagId: tagId,
          objectType: 'question',
          objectId: questionId,
          createdAt: _ts,
        ),
      );
}

/// "目标难度"下拉当前的值（`null` = 不限）。
///
/// `DropdownButton` 会把所有 items 都挂进 `IndexedStack`，"不限难度"这一项永远在树上，
/// 所以不能用 `find.text` 判断"选中了哪一项"；只能读表单字段当前的值。
double? _difficultyDropdownValue() {
  final fields = find
      .byWidgetPredicate((widget) => widget is DropdownButtonFormField<double>)
      .evaluate()
      .map((element) => element.widget as DropdownButtonFormField<double>)
      .toList();
  expect(fields, hasLength(1), reason: '页面上应该只有一个"目标难度"下拉');
  return fields.single.initialValue;
}
