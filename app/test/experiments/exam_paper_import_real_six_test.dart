import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/content_ref_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/domain/services/content/content_ref_vocab.dart';
import 'package:furnace/features/questions/application/exam_paper_question_importer.dart';
import 'package:furnace/features/questions/data/question_media_store.dart';

/// 六科整卷在真实 `paper.json` 上的导入冒烟（task-89，2026-11-15）。
///
/// 这是**实验/验收**测试：直接读工作区里的六份卷目录；文件不在本机时整组
/// skip（与 `test/experiments/` 其它用例同口径）。纯规则单测在
/// `test/features/questions/application/exam_paper_question_importer_test.dart`。
///
/// 锁住的事实（本轮真实运行输出，见 `EXAM-PAPER-IMPORT-SIX-2026-11-15.md`）：
///  * 六科合计 166 题 / 471 选项 / 504 图 / 166 条引用，blocked=0；
///    math 19/44/14、chinese 23/36/3、chemistry 20/64/281、
///    physics 15/40/195、biology 22/72/11、english 67/215/0；
///    （图数按「题干图 + 选项图按路径去重」计，等于实际落盘附件数）
///  * 二次导入 created=0 / reused=166，题/选项/图/引用都不翻倍；
///  * 语文 `material_ids` 材料并入题干；化学/物理公式图进附件并标
///    `formula_image_not_latex`；生物模块卷 `exam_scope=non_gaokao`；
///    英语听力 `audio_available=false`、作文 `answer_non_unique=true`；
///  * 全程 `NativeDatabase.memory()` + 临时目录，不打开用户真实库。
void main() {
  const workspaceRoot = r'E:\Workspaces\agent-control';
  const projectRoot =
      r'E:\Workspaces\agent-control\10-projects\agent-control-plane';

  const paperDirs = <String, String>{
    'math': '$projectRoot\\exam-papers\\2025-math-national1',
    'chinese': '$projectRoot\\exam-papers\\2025-chinese-national1',
    'english': '$workspaceRoot\\exam-papers\\2026-english-national-1',
    'chemistry': '$workspaceRoot\\exam-papers\\2024-chem-guangdong',
    'physics': '$workspaceRoot\\exam-papers\\2024-physics-guangdong',
    'biology': '$workspaceRoot\\exam-papers\\2025-bio-module-1',
  };

  final missing = <String>[
    for (final entry in paperDirs.entries)
      if (!File('${entry.value}\\paper.json').existsSync())
        '${entry.key}: ${entry.value}',
  ];
  if (missing.isNotEmpty) {
    test('六科卷不在本机，跳过导入冒烟', () {}, skip: missing.join('; '));
    return;
  }

  late Directory supportDir;
  late AppDatabase db;
  late QuestionRepository questions;
  late ContentRefRepository contentRefs;

  setUp(() {
    supportDir = Directory.systemTemp.createTempSync('exam_paper_six_media_');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    questions = QuestionRepository(db);
    contentRefs = ContentRefRepository(db);
  });

  tearDown(() async {
    await db.close();
    if (supportDir.existsSync()) {
      supportDir.deleteSync(recursive: true);
    }
  });

  QuestionMediaStore newMediaStore() => QuestionMediaStore(
        database: db,
        supportDirectory: () async => supportDir,
      );

  ExamPaperQuestionImporter newImporter({QuestionMediaStore? mediaStore}) =>
      ExamPaperQuestionImporter(
        db,
        questions: questions,
        contentRefs: contentRefs,
        mediaStore: mediaStore,
        now: DateTime.utc(2026, 11, 15, 12),
      );

  Future<List<ExamPaperImportResult>> importAll(
    ExamPaperQuestionImporter importer,
  ) async {
    final results = <ExamPaperImportResult>[];
    for (final entry in paperDirs.entries) {
      results.add(await importer.importPaper(
        ExamPaperDocument.loadDirectory(entry.value),
      ));
    }
    return results;
  }

  test('六科卷：166 题 / 471 选项 / 504 图 / 166 引用全部落库，0 拦截', () async {
    final results =
        await importAll(newImporter(mediaStore: newMediaStore()));
    final byKey = <String, ExamPaperImportResult>{
      for (final result in results) result.paperKey: result,
    };

    const expected = <String, List<int>>{
      // paperKey: [题, 选项, 图, 引用]
      '2025-math-national1': <int>[19, 44, 14, 19],
      '2025-chinese-national-1': <int>[23, 36, 3, 23],
      '2024-chem-guangdong': <int>[20, 64, 281, 20],
      '2024-physics-guangdong': <int>[15, 40, 195, 15],
      '2025-bio-module-1': <int>[22, 72, 11, 22],
      '2026-english-national-1': <int>[67, 215, 0, 67],
    };
    for (final entry in expected.entries) {
      final result = byKey[entry.key]!;
      expect(result.questionCount, entry.value[0], reason: entry.key);
      expect(result.optionCount, entry.value[1], reason: entry.key);
      expect(result.figureCount, entry.value[2], reason: entry.key);
      expect(result.contentRefCount, entry.value[3], reason: entry.key);
      expect(result.blockedCount, 0, reason: '${entry.key} 不应有拦截');
      expect(result.status, ExamPaperImportStatus.importedWithSkips);
    }

    // 合计与产品表计数。
    expect(await _count(db, 'questions'), 166);
    expect(await _count(db, 'question_options'), 471);
    expect(await _count(db, 'content_refs'), 166);
    expect(await _count(db, 'attachments'), 504);
    expect(await _count(db, 'knowledge_points'), 0, reason: '不写知识点');
    expect(await _count(db, 'tags'), 0, reason: '不写标签');
    expect(await _count(db, 'object_tags'), 0, reason: '不写标签');

    // 每科题数/来源分级。
    final rows = await questions.all(limit: 500);
    expect(rows, hasLength(166));
    final bySubject = <String, int>{};
    for (final row in rows) {
      bySubject.update(row.subjectKey, (value) => value + 1, ifAbsent: () => 1);
    }
    expect(bySubject, <String, int>{
      'math': 19,
      'chinese': 23,
      'chemistry': 20,
      'physics': 15,
      'biology': 22,
      'english': 67,
    });
    for (final row in rows) {
      expect(row.capability, isNull, reason: '不写能力点');
      expect(row.difficulty, isNull, reason: '不写难度');
      expect(row.origin, 'exam_paper');
      expect(row.textFormat, 'markdown');
    }
  });

  test('二次导入六科：created=0 / reused=166，题/选项/图/引用都不翻倍', () async {
    final importer = newImporter(mediaStore: newMediaStore());
    final first = await importAll(importer);
    expect(first.fold<int>(0, (sum, r) => sum + r.createdCount), 166);

    final second = await importAll(importer);
    expect(second.fold<int>(0, (sum, r) => sum + r.createdCount), 0);
    expect(second.fold<int>(0, (sum, r) => sum + r.reusedCount), 166);
    expect(second.fold<int>(0, (sum, r) => sum + r.figuresImported), 0);

    expect(await _count(db, 'questions'), 166);
    expect(await _count(db, 'question_options'), 471);
    expect(await _count(db, 'content_refs'), 166);
    expect(await _count(db, 'attachments'), 504);
  });

  test('结构 spot check：材料 / 公式图 / 模块卷 / 英语非唯一答案', () async {
    await importAll(newImporter(mediaStore: newMediaStore()));

    // ---- 语文：material_ids 材料并入题干，metadata 只留 id ----
    final chinese = (await questions.byId(
      await _questionId(db, '2025-chinese-national-1#Q1'),
    ))!;
    expect(chinese.stem, startsWith('【材料 S1-M1】'));
    expect(chinese.stem, contains('【题目】'));
    expect(chinese.stem.length, greaterThan(1000));
    final chineseMeta = await _refMetadata(db, '2025-chinese-national-1#Q1');
    expect(chineseMeta['material_ids'], <String>['S1-M1']);
    expect(chineseMeta['material_inlined'], isTrue);
    expect(chineseMeta['original_question_type'], '单项选择题');
    // 作文没有官方答案：答案空，不生成。
    final writing = (await questions.byId(
      await _questionId(db, '2025-chinese-national-1#Q23'),
    ))!;
    expect(writing.answer?.trim() ?? '', isEmpty);
    final writingMeta = await _refMetadata(db, '2025-chinese-national-1#Q23');
    expect(writingMeta['answer_no_official_source'], isTrue);
    expect(writingMeta['answer_non_unique'], isTrue);

    // ---- 化学：题干 block 重建 + 选项配图 + 答案公式图 ----
    final chem = (await questions.byId(
      await _questionId(db, '2024-chem-guangdong#Q1'),
    ))!;
    expect(chem.stem, contains('【选项配图】'));
    expect(chem.stem, contains('［图1］'));
    final chemOptions = await questions.optionsOf(chem.id);
    expect(chemOptions, hasLength(4));
    for (final option in chemOptions) {
      expect(option.content, contains('（选项配图见［图'));
      expect(option.content, isNot(startsWith('［图1］')),
          reason: '选项正文不能残留局部图号');
    }
    final chemMeta = await _refMetadata(db, '2024-chem-guangdong#Q1');
    expect(chemMeta['option_figure_count'], 4);
    expect(chemMeta['exam_scope'], 'gaokao');
    expect(chemMeta['source_stage'], '高考');
    final chemFormulaMeta =
        await _refMetadata(db, '2024-chem-guangdong#Q18');
    expect(chemFormulaMeta['formula_image_not_latex'], isTrue);
    expect(chemFormulaMeta['formula_image_count'], isA<int>());
    final chemAnswer = (await questions.byId(
      await _questionId(db, '2024-chem-guangdong#Q18'),
    ))!;
    expect(chemAnswer.answer, contains('［图'));

    // ---- 物理：公式图不是 LaTeX，题干/答案用占位 ----
    final physics = (await questions.byId(
      await _questionId(db, '2024-physics-guangdong#Q1'),
    ))!;
    expect(physics.stem, contains('［图1］'));
    expect(physics.stem, contains('【选项配图】'));
    final physicsMeta = await _refMetadata(db, '2024-physics-guangdong#Q1');
    expect(physicsMeta['formula_image_not_latex'], isTrue);
    expect(physicsMeta['formula_image_count'], 11);
    expect(physicsMeta['original_question_type'], isNot('single_choice'));
    final physicsAnswer = (await questions.byId(
      await _questionId(db, '2024-physics-guangdong#Q14'),
    ))!;
    expect(physicsAnswer.answer, contains('［图'));
    expect(physicsAnswer.solution, contains('［图'));

    // ---- 生物：模块卷 non_gaokao；字符串图路径真的落盘 ----
    final bio = (await questions.byId(
      await _questionId(db, '2025-bio-module-1#Q2'),
    ))!;
    expect(bio.sourceLevel, 'school');
    expect(bio.stem, contains('如图'));
    final bioMeta = await _refMetadata(db, '2025-bio-module-1#Q2');
    expect(bioMeta['exam_scope'], 'non_gaokao');
    expect(bioMeta['source_stage'], contains('非高考'));
    final bioImages = await newMediaStore().list(
      bio.id,
      role: QuestionImageRole.stem,
    );
    expect(bioImages, hasLength(1));
    expect(File(bioImages.single.absolutePath).existsSync(), isTrue);

    // ---- 英语：听力原文并入题干、音频不可用；作文参考样例非唯一 ----
    final listening = (await questions.byId(
      await _questionId(db, '2026-english-national-1#Q1'),
    ))!;
    expect(listening.stem, contains('【听力原文】'));
    expect(listening.stem, contains('【题目】'));
    final listeningMeta =
        await _refMetadata(db, '2026-english-national-1#Q1');
    expect(listeningMeta['audio_available'], isFalse);
    expect(listeningMeta['material_inlined'], isTrue);

    final seven = (await questions.byId(
      await _questionId(db, '2026-english-national-1#Q36'),
    ))!;
    expect(seven.stem, contains('【短文】'));
    expect(await questions.optionsOf(seven.id), hasLength(7),
        reason: '七选五共享 A–G 七个选项');

    final cloze = (await questions.byId(
      await _questionId(db, '2026-english-national-1#Q41'),
    ))!;
    expect(cloze.stem, contains('（第41空）'), reason: '同句多空题干必须可区分');
    expect(await questions.optionsOf(cloze.id), hasLength(4));

    final writing66 = (await questions.byId(
      await _questionId(db, '2026-english-national-1#Q66'),
    ))!;
    expect(writing66.questionType, 'open');
    expect(writing66.answer, isNotEmpty, reason: '参考样例原样保存');
    final englishWritingMeta =
        await _refMetadata(db, '2026-english-national-1#Q66');
    expect(englishWritingMeta['answer_non_unique'], isTrue);
  });

  test('没有 QuestionMediaStore：公式/图题被拦截，英语（无图）全导', () async {
    final results = await importAll(newImporter());
    final byKey = <String, ExamPaperImportResult>{
      for (final result in results) result.paperKey: result,
    };

    int blockedQuestions(ExamPaperImportResult result) => result.blocked
        .map((issue) => issue.questionNumber)
        .whereType<int>()
        .toSet()
        .length;

    expect(byKey['2026-english-national-1']!.blockedCount, 0);
    expect(byKey['2026-english-national-1']!.questionCount, 67);
    expect(blockedQuestions(byKey['2024-physics-guangdong']!), 15);
    // 化学 20 题里 Q4 没有公式图/插图（纯文字），其余 19 题被拦截。
    expect(blockedQuestions(byKey['2024-chem-guangdong']!), 19);
    expect(byKey['2024-chem-guangdong']!.questionCount, 1);
    // 语文只有 Q17/Q21 带图；数学只有 Q6/Q17；生物 11 题带图。
    expect(blockedQuestions(byKey['2025-chinese-national-1']!), 2);
    expect(byKey['2025-chinese-national-1']!.questionCount, 21);
    expect(blockedQuestions(byKey['2025-math-national1']!), 2);
    expect(blockedQuestions(byKey['2025-bio-module-1']!), 11);

    // 没有 media store 时不裸挂本地图，也不落任何附件。
    expect(await _count(db, 'attachments'), 0);
    final rows = await questions.all(limit: 500);
    for (final row in rows) {
      expect(row.stem, isNot(contains('question_images/')),
          reason: '题干不能内嵌本地图路径');
    }
  });
}

Future<String> _questionId(AppDatabase db, String contentId) async {
  final refs = await ContentRefRepository(db).listByContentId(contentId);
  final ref = refs.singleWhere(
    (row) =>
        row.objectType == ContentObjectType.question &&
        row.role == ContentRefRole.sourcePackage,
  );
  return ref.objectId;
}

Future<Map<String, Object?>> _refMetadata(
  AppDatabase db,
  String contentId,
) async {
  final refs = await ContentRefRepository(db).listByContentId(contentId);
  final ref = refs.singleWhere(
    (row) =>
        row.objectType == ContentObjectType.question &&
        row.role == ContentRefRole.sourcePackage,
  );
  return jsonDecode(ref.metadataJson!) as Map<String, Object?>;
}

Future<int> _count(AppDatabase db, String table) async {
  final rows = await db.customSelect('SELECT COUNT(*) AS c FROM "$table"').get();
  return rows.first.read<int>('c');
}
