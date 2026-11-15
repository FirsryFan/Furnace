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

/// 真实数学卷 19 题导入冒烟（task-87，2026-11-15）。
///
/// 这是**实验/验收**测试，不是纯单元测试：直接读工作区
/// `10-projects/agent-control-plane/exam-papers/2025-math-national1` 的绝对
/// 路径；文件不在本机时整组 skip（与 `test/experiments/` 其它用例同口径）。
/// 纯规则单测在 `test/features/questions/application/exam_paper_question_importer_test.dart`。
///
/// 锁住的事实（[读] 2025-math-national1/paper.json + manifest.json）：
///  * 19 题、44 个选项（8 单选×4 + 3 多选×4）；题型 8/3/3/5；
///  * 分值按 `external_template_web_2025_n1` 写进引用摘要，合计 150；
///    卷面 stated total=150；产品 `questions` 没有分值列；
///  * 题干图 2 张（Q6/Q17）、解析图 12 张，共 14 张落 `attachments`；
///    Q6/Q17 题干正文里的 Markdown 图换成「［图1］」；解析正文不再内嵌图；
///  * 19 条 `content_refs`：`2025-math-national1#Q1..#Q19` ↔ question；
///  * 二次导入不新建题/选项/配图；不建知识点/标签/能力点；
///  * 全程 `NativeDatabase.memory()` + 临时目录，不打开用户真实库。
void main() {
  const repositoryRoot =
      r'E:\Workspaces\agent-control\10-projects\agent-control-plane';
  const paperDir = '$repositoryRoot\\exam-papers\\2025-math-national1';

  if (!Directory(paperDir).existsSync() ||
      !File('$paperDir\\paper.json').existsSync()) {
    test(
      '真实数学卷不在本机，跳过导入冒烟',
      () {},
      skip: 'not found: $paperDir',
    );
    return;
  }

  late Directory supportDir;
  late AppDatabase db;
  late QuestionRepository questions;
  late ContentRefRepository contentRefs;

  setUp(() {
    supportDir = Directory.systemTemp.createTempSync('exam_paper_math_media_');
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

  test('数学 2025 全国一卷：19 题/选项/答案/分值/来源/图/引用全部落库', () async {
    final paper = ExamPaperDocument.loadDirectory(paperDir);
    expect(paper.paperKey, '2025-math-national1');
    expect(paper.questions, hasLength(19));
    expect(paper.subjectKey, 'math');
    expect(paper.year, 2025);
    expect(paper.region, 'national1');
    expect(paper.scoreTotalStated, 150);

    final result =
        await newImporter(mediaStore: newMediaStore()).importPaper(paper);

    expect(result.status, ExamPaperImportStatus.importedWithSkips);
    expect(result.subjectKey, 'math');
    expect(result.year, 2025);
    expect(result.region, 'national1');
    expect(result.sourceLevel, 'gaokao');
    expect(result.sourceLevelBasis, 'inferred_from_title');
    expect(result.questionCount, 19);
    expect(result.createdCount, 19);
    expect(result.reusedCount, 0);
    expect(result.blockedCount, 0);
    expect(result.optionCount, 44);
    expect(result.figureCount, 14);
    expect(result.figuresImported, 14);
    expect(result.contentRefCount, 19);
    expect(result.scoreSumFromQuestions, 150);
    expect(result.scoreTotalStated, 150);

    // 表计数：19 题 / 44 选项 / 19 引用 / 14 张图 / 0 知识点 / 0 标签。
    expect(await _count(db, 'questions'), 19);
    expect(await _count(db, 'question_options'), 44);
    expect(await _count(db, 'content_refs'), 19);
    expect(await _count(db, 'attachments'), 14);
    expect(await _count(db, 'knowledge_points'), 0);
    expect(await _count(db, 'tags'), 0);
    expect(await _count(db, 'object_tags'), 0);

    // 题型分布。
    final rows = await questions.all(limit: 100);
    expect(
      rows.groupBy((row) => row.questionType).map(
            (type, group) => MapEntry(type, group.length),
          ),
      <String, int>{
        'single_choice': 8,
        'multiple_choice': 3,
        'fill_in': 3,
        'solution': 5,
      },
    );
    for (final row in rows) {
      expect(row.subjectKey, 'math');
      expect(row.year, 2025);
      expect(row.region, 'national1');
      expect(row.sourceLevel, 'gaokao');
      expect(row.textFormat, 'markdown');
      expect(row.origin, 'exam_paper');
      expect(row.state, 'structured');
      expect(row.capability, isNull, reason: 'AI 初标能力点不写');
      expect(row.difficulty, isNull, reason: 'AI 初标难度不写');
      expect(row.answer, isNotNull);
      expect(row.solution, isNotNull);
      expect(row.solution, isNot(contains('![')),
          reason: '解析里的图引用已去掉（图进答案图库）');
      expect(row.solution, isNot(contains('[IMG:')));
    }
    expect(
      rows.map((row) => row.serialNo).whereType<int>().toList()..sort(),
      List<int>.generate(19, (index) => index + 1),
      reason: '产品题号 1..19 连续分配',
    );

    // 客观题答案与 paper.json 的 answer_key_table 一致。
    final answerKey = <int, String>{
      1: 'C',
      2: 'C',
      3: 'D',
      4: 'B',
      5: 'A',
      6: 'A',
      7: 'B',
      8: 'B',
      9: 'BD',
      10: 'ACD',
      11: 'ABC',
    };
    for (final entry in answerKey.entries) {
      final question = await _questionByNumber(questions, entry.key);
      expect(question.answer, entry.value, reason: '第 ${entry.key} 题答案');
    }
    expect((await _questionByNumber(questions, 12)).answer, r'$4$');
    expect((await _questionByNumber(questions, 13)).answer, r'$2$');
    expect(
      (await _questionByNumber(questions, 14)).answer,
      r'$\frac{61}{25}$/$2.44$',
    );
    for (final number in const <int>[15, 16, 17, 18, 19]) {
      expect(
        (await _questionByNumber(questions, number)).answer,
        startsWith('(1)'),
        reason: '第 $number 题解答题答案带分问',
      );
    }

    // 选项：单选每题 4 个、只有一个正确；多选每题 4 个、正确项来自答案。
    for (var number = 1; number <= 8; number++) {
      final question = await _questionByNumber(questions, number);
      final options = await questions.optionsOf(question.id);
      expect(options, hasLength(4), reason: '第 $number 题');
      expect(
        options.where((option) => option.isCorrect).map((o) => o.label),
        <String?>[question.answer],
        reason: '第 $number 题正确项',
      );
    }
    for (final number in const <int>[9, 10, 11]) {
      final question = await _questionByNumber(questions, number);
      final options = await questions.optionsOf(question.id);
      expect(options, hasLength(4));
      expect(
        options.where((option) => option.isCorrect).map((o) => o.label).toSet(),
        question.answer!.split('').toSet(),
        reason: '第 $number 题多选正确项',
      );
    }
    for (final number in const <int>[12, 13, 14, 15, 16, 17, 18, 19]) {
      final question = await _questionByNumber(questions, number);
      expect(await questions.optionsOf(question.id), isEmpty,
          reason: '第 $number 题无选项');
    }

    // 题干图：Q6/Q17 的 Markdown 图引用换成「［图1］」，图落 role=stem。
    final store = newMediaStore();
    for (final number in const <int>[6, 17]) {
      final question = await _questionByNumber(questions, number);
      expect(question.stem, contains('［图1］'), reason: '第 $number 题题干占位');
      expect(question.stem, isNot(contains('images/')), reason: '第 $number 题');
      final images =
          await store.list(question.id, role: QuestionImageRole.stem);
      expect(images, hasLength(1), reason: '第 $number 题题干图');
      expect(File(images.single.absolutePath).existsSync(), isTrue);
    }
    // Q17 解析图 4 张落 role=answer。
    final q17 = await _questionByNumber(questions, 17);
    final q17AnswerImages =
        await store.list(q17.id, role: QuestionImageRole.answer);
    expect(q17AnswerImages, hasLength(4));

    // 引用：<paperKey>#Q<number> ↔ question，role=sourcePackage；metadata 只有摘要。
    var scoreSum = 0;
    for (var number = 1; number <= 19; number++) {
      final contentId = '2025-math-national1#Q$number';
      final question = await _questionByNumber(questions, number);
      final ref = await contentRefs.findOne(
        contentId: contentId,
        objectType: ContentObjectType.question,
        objectId: question.id,
        role: ContentRefRole.sourcePackage,
      );
      expect(ref, isNotNull, reason: '第 $number 题引用');
      expect(ref!.subject, 'math');
      final metadata = jsonDecode(ref.metadataJson!) as Map<String, Object?>;
      expect(metadata['paper_id'], '2025-math-national1');
      expect(metadata['question_number'], number);
      expect(metadata['source_level'], 'gaokao');
      expect(metadata['year'], 2025);
      expect(metadata['region'], 'national1');
      final scoring = metadata['scoring'] as Map<String, Object?>;
      expect(scoring['source'], 'external_template_web_2025_n1');
      expect(scoring['confirmed_in_source'], isFalse);
      scoreSum += (scoring['points'] as num).toInt();
      expect(ref.metadataJson, isNot(contains('【详解】')),
          reason: '引用摘要不存解析正文');
      expect(ref.metadataJson, isNot(contains('虚部')), reason: '不存题干正文');
    }
    expect(scoreSum, 150);
    expect(
      result.skipped.map((issue) => issue.code),
      containsAll(<String>[
        ExamPaperSkipReason.aiLabelsIgnored,
        ExamPaperSkipReason.figureReferenceRemovedFromText,
      ]),
    );
  });

  test('二次导入同一卷：19 题/44 选项/14 图/19 引用都不翻倍', () async {
    final paper = ExamPaperDocument.loadDirectory(paperDir);
    final importer = newImporter(mediaStore: newMediaStore());
    final first = await importer.importPaper(paper);
    expect(first.createdCount, 19);

    final second = await importer.importPaper(paper);
    expect(second.questionCount, 19);
    expect(second.createdCount, 0);
    expect(second.reusedCount, 19);
    expect(second.optionCount, 44);
    expect(second.figuresImported, 0, reason: '已有题的图不重复落');
    expect(second.blockedCount, 0);
    expect(await _count(db, 'questions'), 19);
    expect(await _count(db, 'question_options'), 44);
    expect(await _count(db, 'attachments'), 14);
    expect(await _count(db, 'content_refs'), 19);
  });

  test('从卷目录副本导入：不依赖原始工作区路径', () async {
    final copyDir = Directory.systemTemp.createTempSync('exam_paper_math_copy_');
    try {
      for (final name in const <String>['paper.json', 'manifest.json']) {
        final source = File('$paperDir\\$name');
        if (source.existsSync()) {
          source.copySync('${copyDir.path}\\$name');
        }
      }
      final sourceImages = Directory('$paperDir\\images');
      if (sourceImages.existsSync()) {
        for (final entity in sourceImages.listSync(recursive: true)) {
          if (entity is! File) {
            continue;
          }
          final relative = entity.path.substring(sourceImages.path.length + 1);
          final target = File('${copyDir.path}\\images\\$relative');
          target.parent.createSync(recursive: true);
          entity.copySync(target.path);
        }
      }

      final paper = ExamPaperDocument.loadDirectory(copyDir.path);
      expect(paper.directoryPath, copyDir.absolute.path);
      final result =
          await newImporter(mediaStore: newMediaStore()).importPaper(paper);
      expect(result.questionCount, 19);
      expect(result.figureCount, 14);
      expect(result.figuresImported, 14);
      expect(await _count(db, 'questions'), 19);
      expect(await _count(db, 'attachments'), 14);
    } finally {
      if (copyDir.existsSync()) {
        copyDir.deleteSync(recursive: true);
      }
    }
  });

  test('没有 QuestionMediaStore：Q6/Q17 blocked，其余 17 题导入且不裸挂图', () async {
    final paper = ExamPaperDocument.loadDirectory(paperDir);
    final result = await newImporter().importPaper(paper);
    expect(result.questionCount, 17);
    expect(result.blockedCount, 2);
    expect(
      result.blocked.map((issue) => issue.questionNumber).toSet(),
      <int>{6, 17},
    );
    expect(
      result.blocked.map((issue) => issue.code).toSet(),
      <String>{ExamPaperBlockReason.figureNotImportable},
    );
    expect(await _count(db, 'questions'), 17);
    expect(await _count(db, 'attachments'), 0);
    expect(
      result.skipped.map((issue) => issue.code),
      contains(ExamPaperSkipReason.figureNotImported),
    );
  });
}

Future<Question> _questionByNumber(
  QuestionRepository questions,
  int serialNo,
) async {
  final question = await questions.findBySerialNo(serialNo);
  expect(question, isNotNull, reason: '题号 $serialNo 应存在');
  return question!;
}

Future<int> _count(AppDatabase db, String table) async {
  final rows = await db.customSelect('SELECT COUNT(*) AS c FROM "$table"').get();
  return rows.first.read<int>('c');
}

extension<T> on List<T> {
  Map<K, List<T>> groupBy<K>(K Function(T item) keyOf) {
    final result = <K, List<T>>{};
    for (final item in this) {
      result.putIfAbsent(keyOf(item), () => <T>[]).add(item);
    }
    return result;
  }
}
