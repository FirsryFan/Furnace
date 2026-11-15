import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/content/content_package_reader.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/content_ref_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/domain/services/content/content_package.dart';
import 'package:furnace/domain/services/content/content_package_import_service.dart';
import 'package:furnace/domain/services/content/content_ref_vocab.dart';
import 'package:furnace/domain/services/content/dag_flashcard_generator.dart';

/// 真实内容包三题导入冒烟（task-80，2026-11-15）。
///
/// 这是**实验/验收**测试，不是纯单元测试：直接读工作区三个内容包的绝对路径，
/// 文件不在本机时整组 skip（与 `test/experiments/` 其它用例同口径）。纯规则
/// 单测在 `test/domain/services/content/content_package_import_service_test.dart`。
///
/// 锁住的事实（2026-11-15 的三个包）：
///  * 三包各导入一次：3 道产品题、3 条题目 `source_package` 引用；
///  * 13 个内容知识节点 → 13 个产品知识点 + 13 条 `node` 引用；
///  * 答案逐字来自 Source：物理 `B`、数学 `(1) 9/10 / (2) 有关`、语文踩分点原文；
///  * 解析按内容包渲染策略：物理/数学被抑制（null），语文《高考试题分析》
///    原文写入；AI 补写不出现；
///  * 二次导入不新增题目/知识点/引用（幂等）；
///  * 物理 DAG 卡 dry run = 6 wouldCreate / 2 skipped；apply 落 6 张模板 +
///    6 条 card_seed 引用，`card_states` / `review_logs` 仍为 0；再 apply 幂等；
///  * 全程 `NativeDatabase.memory()`，不打开用户真实库。
void main() {
  const repositoryRoot =
      r'E:\Workspaces\agent-control\10-projects\agent-control-plane';
  const packageDirs = <String>[
    '$repositoryRoot\\content-store\\physics\\Q-PH0001',
    '$repositoryRoot\\content-store\\math\\Q-MA0001',
    '$repositoryRoot\\content-store\\chinese\\Q-CH0001',
  ];

  final missing = <String>[
    for (final dir in packageDirs)
      if (!Directory(dir).existsSync()) dir,
  ];
  if (missing.isNotEmpty) {
    test(
      '三个真实内容包不在本机，跳过导入冒烟',
      () {},
      skip: 'not found: ${missing.join(', ')}',
    );
    return;
  }

  late AppDatabase db;
  late ContentPackageImportService service;
  late QuestionRepository questions;
  late ContentRefRepository contentRefs;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    questions = QuestionRepository(db);
    contentRefs = ContentRefRepository(db);
    service = ContentPackageImportService(
      db,
      questions: questions,
      contentRefs: contentRefs,
    );
  });

  tearDown(() async {
    await db.close();
  });

  List<ContentPackage> readPackages() => <ContentPackage>[
        for (final dir in packageDirs)
          const ContentPackageReader().readDirectory(dir).package,
      ];

  test('三包导入：3 题 / 13 知识点 / 答案与解析来源正确 / 二次幂等', () async {
    final packages = readPackages();
    expect(
      packages.map((package) => package.contentId).toList(),
      <String>['Q-PH0001', 'Q-MA0001', 'Q-CH0001'],
    );

    final results = <String, ContentPackageImportResult>{};
    for (final package in packages) {
      final result = await service.importPackage(package);
      results[package.contentId] = result;
      expect(result.questionId, isNotNull, reason: package.contentId);
      expect(result.status, ContentPackageImportStatus.importedWithSkips);
      // 空标签库：学科 1 + 题型 1 + 每个知识节点 1 条候选全部 missing（不建标签）。
      expect(
        result.missingTags,
        hasLength(package.knowledge.length + 2),
        reason: package.contentId,
      );
    }

    // --- 题库：3 道题 ---
    final storedQuestions = await db.select(db.questions).get();
    expect(storedQuestions, hasLength(3));
    final byContentId = <String, Question>{
      for (final package in packages)
        package.contentId: (await questions.byId(
          results[package.contentId]!.questionId!,
        ))!,
    };

    // 答案逐字来自 Source（不是 AI 补写）。
    expect(byContentId['Q-PH0001']!.answer, 'B');
    expect(byContentId['Q-MA0001']!.answer, contains(r'\frac{9}{10}'));
    expect(byContentId['Q-MA0001']!.answer, contains('有关'));
    expect(byContentId['Q-CH0001']!.answer, contains('以砚喻人'));
    expect(byContentId['Q-CH0001']!.answer, contains('坚贞'));

    // 解析：物理/数学内容包声明不渲染来源解析 → 产品 solution 留空；
    // 语文《高考试题分析》原文允许渲染 → 写入 SOL-CH-02 原文。
    expect(byContentId['Q-PH0001']!.solution, isNull);
    expect(byContentId['Q-MA0001']!.solution, isNull);
    expect(byContentId['Q-CH0001']!.solution, isNotNull);
    expect(byContentId['Q-CH0001']!.solution, contains('尾联'));
    expect(
      results['Q-PH0001']!.skipped.map((skip) => skip.code),
      contains(ContentPackageSkipReason.solutionSuppressed),
    );

    // 学科/来源/年份/难度/能力映射。
    expect(byContentId['Q-PH0001']!.subjectKey, 'physics');
    expect(byContentId['Q-MA0001']!.subjectKey, 'math');
    expect(byContentId['Q-CH0001']!.subjectKey, 'chinese');
    for (final question in byContentId.values) {
      expect(question.sourceLevel, 'gaokao');
    }
    expect(byContentId['Q-PH0001']!.year, 2023);
    expect(byContentId['Q-MA0001']!.year, 2025);
    expect(byContentId['Q-CH0001']!.year, 2025);

    // 问答题型映射：物理单选 / 数学解答 / 语文解答。
    expect(byContentId['Q-PH0001']!.questionType, 'single_choice');
    expect(byContentId['Q-MA0001']!.questionType, 'solution');
    expect(byContentId['Q-CH0001']!.questionType, 'solution');

    // --- 知识点：13 个内容节点全部映射 ---
    final expectedPoints = packages.fold<int>(
      0,
      (sum, package) => sum + package.knowledge.length,
    );
    expect(expectedPoints, 13);
    expect(await db.select(db.knowledgePoints).get(), hasLength(13));
    final allRefs = await db.select(db.contentRefs).get();
    expect(
      allRefs
          .where((ref) => ref.objectType == ContentObjectType.question)
          .length,
      3,
    );
    expect(
      allRefs
          .where((ref) => ref.objectType == ContentObjectType.knowledgePoint)
          .length,
      13,
    );
    for (final package in packages) {
      final questionRef = await contentRefs.findOne(
        contentId: package.contentId,
        objectType: ContentObjectType.question,
        objectId: results[package.contentId]!.questionId!,
        role: ContentRefRole.sourcePackage,
      );
      expect(questionRef, isNotNull);
      expect(questionRef!.contentVersion, package.version);
      expect(questionRef.contentHash, package.contentHash);
      expect(questionRef.subject, package.subject);
      // 引用摘要不复制正文：不出现题干全文。
      expect(questionRef.metadataJson, isNot(contains(package.stem)));
    }

    // --- 二次导入幂等 ---
    for (final package in packages) {
      final again = await service.importPackage(package);
      expect(again.questionCreated, isFalse, reason: package.contentId);
      expect(again.questionId, results[package.contentId]!.questionId);
    }
    expect(await db.select(db.questions).get(), hasLength(3));
    expect(await db.select(db.knowledgePoints).get(), hasLength(13));
    expect(await db.select(db.contentRefs).get(), hasLength(16));
  });

  test('物理 DAG 卡：dry run 6/2；apply 6 模板 + 6 引用；不复制 FSRS', () async {
    final physics =
        const ContentPackageReader().readDirectory(packageDirs.first).package;
    final dry = await service.importPackage(
      physics,
      options: const ContentPackageImportOptions(generateCards: true),
    );
    expect(dry.cardPlan, isNotNull);
    expect(dry.cardPlan!.dryRun, isTrue);
    expect(dry.cardPlan!.wouldCreate, 6, reason: '公式 1 + 判断 2 + 结论 1 + 错因 2');
    expect(dry.cardPlan!.skipped, 2, reason: '审题 N-Q1-01 + 纯爆算 N-Q1-05');
    expect(dry.cardPlan!.blocked, 0);
    expect(await db.select(db.cardTemplates).get(), isEmpty);

    final applied = await service.importPackage(
      physics,
      options: const ContentPackageImportOptions(
        generateCards: true,
        cardsDryRun: false,
      ),
    );
    expect(applied.cardPlan!.created, 6);
    final templates = await db.select(db.cardTemplates).get();
    expect(templates, hasLength(6));
    for (final template in templates) {
      expect(template.externalId, startsWith('content:Q-PH0001#'));
      expect(template.hint, startsWith('【AI】'));
    }
    expect(
      (await contentRefs.listByContentId('Q-PH0001'))
          .where((ref) => ref.role == ContentRefRole.cardSeed),
      hasLength(6),
    );
    // 不复制 FSRS：生成不建卡状态/复习记录。
    expect(await db.select(db.cardStates).get(), isEmpty);
    expect(await db.select(db.reviewLogs).get(), isEmpty);

    final again = await service.importPackage(
      physics,
      options: const ContentPackageImportOptions(
        generateCards: true,
        cardsDryRun: false,
      ),
    );
    expect(again.cardPlan!.created, 0);
    expect(
      again.cardPlan!.skippedReasons[DagCardSkipReason.alreadyExists],
      6,
    );
    expect(await db.select(db.cardTemplates).get(), hasLength(6));
  });
}
