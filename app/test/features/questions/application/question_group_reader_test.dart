import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_attempt_repository.dart';
import 'package:furnace/domain/services/paper/paper_composer.dart';
import 'package:furnace/domain/services/questions/question_group.dart';
import 'package:furnace/domain/services/questions/question_readiness.dart';
import 'package:furnace/features/questions/application/question_corpus_reader.dart';
import 'package:furnace/features/questions/application/question_library_filter.dart';
import 'package:furnace/features/questions/application/question_library_reader.dart';

/// 题组读表验收（P0，2026-11-18）：一篇文章 + 若干小问 = **一道题**。
///
/// 用户口径：
///  * 英语阅读 A 篇 = 文章 + 3 小问 = 1 道题；
///  * 语文现代文阅读 II = 文章 + 2 选择 + 2 解答 = 1 道题；
///  * 组卷的 3 精研 / 6 速刷按**合题**计数，不能按小问。
///
/// 造数用内存 Drift，按整卷导入的真实 stem 拼法
/// （`exam_paper_question_importer.dart` 的 `_assembleStem`）：
/// `【材料 S1-M1】\n…\n\n【题目】\n（N）小问`。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// 整卷导入的一行小问：材料原文 + `【题目】` + 小问题干。
  Future<void> seedGroupRow(
    String id, {
    required String material,
    required String question,
    String sourceLabel = '2025 全国 I 卷',
    String subjectKey = 'chinese',
    int serialNo = 0,
    int updatedAt = 0,
    String? answer = '参考答案',
    String? solution = '解析',
  }) {
    return db.into(db.questions).insert(
          QuestionsCompanion.insert(
            id: id,
            stem: '$material\n\n【题目】\n$question',
            subjectKey: Value(subjectKey),
            sourceLabel: Value(sourceLabel),
            serialNo: Value(serialNo),
            createdAt: updatedAt,
            updatedAt: updatedAt,
            answer: Value(answer),
            solution: Value(solution),
          ),
        );
  }

  /// 独立题：没有材料前缀，读表必须仍是一行一题。
  Future<void> seedStandalone(
    String id, {
    String stem = '求函数的最小值。',
    int updatedAt = 0,
    int? serialNo,
  }) {
    return db.into(db.questions).insert(
          QuestionsCompanion.insert(
            id: id,
            stem: stem,
            serialNo: Value(serialNo),
            createdAt: updatedAt,
            updatedAt: updatedAt,
            answer: const Value('A'),
            solution: const Value('解析'),
          ),
        );
  }

  /// 语文现代文阅读 II 的材料：4 个小问共用同一份材料。
  const chineseMaterial = '【材料 S1-M1】\n种植入门问答\n凡种植，先辨土性……';

  Future<void> seedChineseGroup({
    String sourceLabel = '2025 全国 I 卷',
    String material = chineseMaterial,
    int updatedAt = 100,
    int startSerial = 1,
  }) async {
    const questions = <String>[
      '（1）下列对材料相关内容的理解，正确的一项是（ ）',
      '（2）下列对材料相关内容的分析，不正确的一项是（ ）',
      '（3）请结合材料概括种植的三个步骤。',
      '（4）文章结尾有何作用？请简要分析。',
    ];
    for (var i = 0; i < questions.length; i++) {
      await seedGroupRow(
        'q-modern-${i + 1}',
        material: material,
        question: questions[i],
        sourceLabel: sourceLabel,
        serialNo: startSerial + i,
        updatedAt: updatedAt,
      );
    }
  }

  group('readQuestionLibrary：题库按题组折叠', () {
    test(
        '中文 4 行同 source_label + 【材料 S1-M1】 → 1 条题组（groupSize=4）；'
        '独立题 2 条 → 总 3', () async {
      await seedChineseGroup();
      await seedStandalone('q-alone-new', updatedAt: 300);
      await seedStandalone('q-alone-old', updatedAt: 50);

      final snapshot = await readQuestionLibrary(db);

      expect(snapshot.entries, hasLength(3), reason: '1 个题组 + 2 道独立题');
      expect(snapshot.totalCount, 3);
      expect(
        snapshot.entries.where((entry) => entry.isQuestionGroup).length,
        1,
      );
      // 排序不变：最新在前；题组代表 = 组内排序第一行。
      expect(
        snapshot.entries.map((entry) => entry.questionId).toList(),
        <String>['q-alone-new', 'q-modern-1', 'q-alone-old'],
      );

      final group =
          snapshot.entries.firstWhere((entry) => entry.isQuestionGroup);
      expect(group.groupSize, 4);
      expect(group.isQuestionGroup, isTrue);
      expect(
        group.groupQuestionIds,
        <String>['q-modern-1', 'q-modern-2', 'q-modern-3', 'q-modern-4'],
      );
      expect(group.groupKey, isNotNull);
      expect(group.groupLabel, '材料 S1-M1');
      expect(group.groupMaterial, contains('种植入门问答'));
      expect(group.groupMaterialPreview, contains('种植入门问答'));
      expect(
        group.groupMaterialPreview,
        isNot(contains('【材料')),
        reason: '材料标题单独由 groupLabel 显示，摘要里不重复标题行',
      );
      // 代表题就是组内第一行；它不是「丢了另外三道题」——id 全在。
      expect(group.questionId, 'q-modern-1');
      expect(group.stem, contains('（1）下列对材料相关内容的理解'));
    });

    test('英语阅读 A 篇：文章 + 3 小问 → 1 个候选，不是 3 个', () async {
      const material = '【材料 S1-M1】\nRead the passage and answer the questions.';
      for (var i = 1; i <= 3; i++) {
        await seedGroupRow(
          'q-english-$i',
          material: material,
          question: '($i) Question $i',
          subjectKey: 'english',
          serialNo: i,
          updatedAt: 100,
        );
      }

      final snapshot = await readQuestionLibrary(db);
      expect(snapshot.entries, hasLength(1));
      expect(snapshot.entries.single.groupSize, 3);
      expect(snapshot.totalCount, 1);
    });

    test('limit 先折叠再截断：不会把一组截成半组', () async {
      // 4 个题组、每组 4 行，行数（16）远多于题组数（4）。
      for (var groupIndex = 1; groupIndex <= 4; groupIndex++) {
        final material = '【材料 S1-M$groupIndex】\n第 $groupIndex 篇材料正文。';
        for (var row = 1; row <= 4; row++) {
          await seedGroupRow(
            'q-g$groupIndex-$row',
            material: material,
            question: '（$row）第 $groupIndex 组第 $row 小问',
            updatedAt: 100,
          );
        }
      }

      final limited = await readQuestionLibrary(
        db,
        limit: 3,
        policy: QuestionCompletenessPolicy.hidePending,
      );
      expect(limited.entries, hasLength(3));
      expect(limited.truncated, isTrue);
      expect(limited.totalCount, 4, reason: 'totalCount 按题组数，不是按行数');
      for (final entry in limited.entries) {
        expect(entry.groupSize, 4, reason: '截断后不能出现半组');
      }

      final all = await readQuestionLibrary(
        db,
        policy: QuestionCompletenessPolicy.hidePending,
      );
      expect(all.entries, hasLength(4));
      expect(all.truncated, isFalse);
      expect(all.totalCount, 4);
    });

    test('没有材料前缀的题保持独立，group 字段为空', () async {
      await seedStandalone('q-1');
      await seedStandalone('q-2');

      final snapshot = await readQuestionLibrary(db);
      expect(snapshot.entries, hasLength(2));
      for (final entry in snapshot.entries) {
        expect(entry.groupKey, isNull);
        expect(entry.groupQuestionIds, isEmpty);
        expect(entry.groupSize, 1);
        expect(entry.groupLabel, isNull);
        expect(entry.isQuestionGroup, isFalse);
      }
    });

    test('组键带 source_label 与材料正文：不同来源/不同材料不误并', () async {
      const material = '【材料 S1-M1】\n同一段材料。';
      await seedGroupRow('q-a-1',
          material: material,
          question: '（1）A1',
          sourceLabel: '卷 A',
          serialNo: 1);
      await seedGroupRow('q-a-2',
          material: material,
          question: '（2）A2',
          sourceLabel: '卷 A',
          serialNo: 2);
      // 同一材料标题、不同来源卷：不是一组。
      await seedGroupRow('q-b-1',
          material: material,
          question: '（1）B1',
          sourceLabel: '卷 B',
          serialNo: 3);
      // 同一来源、不同材料标题：不是一组。
      await seedGroupRow(
        'q-a-3',
        material: '【材料 S1-M2】\n另一段材料。',
        question: '（1）A3',
        sourceLabel: '卷 A',
        serialNo: 4,
      );

      final snapshot = await readQuestionLibrary(db);
      expect(snapshot.entries, hasLength(3), reason: '1 个题组 + 2 道独立题（含单行材料题）');
      final groups =
          snapshot.entries.where((entry) => entry.isQuestionGroup).toList();
      expect(groups, hasLength(1));
      expect(
        groups.single.groupQuestionIds,
        <String>['q-a-1', 'q-a-2'],
        reason: '不同来源卷的 S1-M1、同源不同材料标题都不是同一组',
      );
      expect(
        snapshot.entries.map((entry) => entry.questionId).toSet(),
        <String>{'q-a-1', 'q-b-1', 'q-a-3'},
      );
    });

    test('多材料（同一首标题、后续材料不同）用材料全文区分组', () async {
      // 语文常见形态：material_ids = [S1-M1, S1-M2]。两组的首标题相同，
      // 但第二份材料不同——只看首标题会把它们并成一组。
      const base = '【材料 S1-M1】\n阅读下面的文字。';
      await seedGroupRow(
        'q-multi-1',
        material: '$base\n\n【材料 S1-M2】\n第一份补充材料。',
        question: '（1）多材料第一组第 1 问',
        updatedAt: 100,
        serialNo: 1,
      );
      await seedGroupRow(
        'q-multi-2',
        material: '$base\n\n【材料 S1-M2】\n第一份补充材料。',
        question: '（2）多材料第一组第 2 问',
        updatedAt: 100,
        serialNo: 2,
      );
      await seedGroupRow(
        'q-multi-3',
        material: '$base\n\n【材料 S1-M3】\n第二份补充材料。',
        question: '（1）多材料第二组第 1 问',
        updatedAt: 100,
        serialNo: 3,
      );
      await seedGroupRow(
        'q-multi-4',
        material: '$base\n\n【材料 S1-M3】\n第二份补充材料。',
        question: '（2）多材料第二组第 2 问',
        updatedAt: 100,
        serialNo: 4,
      );

      final snapshot = await readQuestionLibrary(db);
      final groups =
          snapshot.entries.where((entry) => entry.isQuestionGroup).toList();
      expect(groups, hasLength(2));
      expect(
        groups.first.groupQuestionIds,
        <String>['q-multi-1', 'q-multi-2'],
        reason: '材料全文一致的两行才是同一组',
      );
      expect(
        groups.last.groupQuestionIds,
        <String>['q-multi-3', 'q-multi-4'],
        reason: '首标题相同但第二份材料不同 → 不是同一组',
      );
    });

    test('组内标签取并集、答错次数求和：筛错题本/标签不会漏掉组', () async {
      await seedChineseGroup();
      // 标签挂在第 2 小问、答错发生在第 3 小问。
      await db.into(db.tags).insert(
            TagsCompanion.insert(
              id: 'tag-reading',
              name: '现代文阅读',
              path: const Value('语文/现代文阅读'),
              createdAt: 0,
              updatedAt: 0,
            ),
          );
      await db.into(db.objectTags).insert(
            ObjectTagsCompanion.insert(
              id: 'ot-1',
              tagId: 'tag-reading',
              objectType: 'question',
              objectId: 'q-modern-2',
              createdAt: 0,
            ),
          );
      final attempts = QuestionAttemptRepository(db);
      for (var i = 0; i < 2; i++) {
        await attempts.record(
          questionId: 'q-modern-3',
          selectedLabels: const <String>['A'],
          isCorrect: false,
          now: DateTime.fromMillisecondsSinceEpoch(1000 + i),
        );
      }

      final snapshot = await readQuestionLibrary(db);
      final group = snapshot.entries.single;
      expect(group.tagPaths, <String>['语文/现代文阅读']);
      expect(group.wrongAttemptCount, 2);
      expect(group.hasWrongAttempt, isTrue);

      final wrongOnly = filterQuestionLibraryEntries(
        snapshot.entries,
        const QuestionLibraryFilter(onlyWrong: true),
      );
      expect(wrongOnly, hasLength(1), reason: '第 3 小问答错 → 整个题组进错题本');
    });
  });

  group('readPaperCorpus / 组卷：按合题计数、同组不重复选', () {
    test('readPaperCorpus 的候选按题组折叠（2 组 × 2 行 + 1 独立题 = 3 个候选）', () async {
      const materialA = '【材料 S1-M1】\n阅读下面的文字，完成下列小题。';
      const materialB = '【材料 S2-M1】\n另一篇阅读材料。';
      await seedGroupRow('q-c-a1',
          material: materialA,
          question: '（1）A 组第 1 问',
          sourceLabel: '卷 A',
          serialNo: 1);
      await seedGroupRow('q-c-a2',
          material: materialA,
          question: '（2）A 组第 2 问',
          sourceLabel: '卷 A',
          serialNo: 2);
      await seedGroupRow('q-c-b1',
          material: materialB,
          question: '（1）B 组第 1 问',
          sourceLabel: '卷 B',
          serialNo: 3);
      await seedGroupRow('q-c-b2',
          material: materialB,
          question: '（2）B 组第 2 问',
          sourceLabel: '卷 B',
          serialNo: 4);
      await seedStandalone('q-plain', updatedAt: 900);

      final corpus = await readPaperCorpus(db);
      expect(corpus.candidates, hasLength(3));
      expect(
        corpus.candidates.map((candidate) => candidate.questionId).toSet(),
        <String>{'q-c-a1', 'q-c-b1', 'q-plain'},
      );
    });

    test('PaperComposer：3 精研 / 6 速刷按题组数出题，同一组只选一次', () async {
      // 7 个题组、每组 2 行：按小问是 14 行，按合题只有 7 道题。
      for (var groupIndex = 1; groupIndex <= 7; groupIndex++) {
        final material = '【材料 S1-M$groupIndex】\n第 $groupIndex 篇材料。';
        for (var row = 1; row <= 2; row++) {
          await seedGroupRow(
            'q-p$groupIndex-$row',
            material: material,
            question: '（$row）第 $groupIndex 组小问 $row',
            serialNo: groupIndex * 10 + row,
            updatedAt: 100,
          );
        }
      }

      final corpus = await readPaperCorpus(db);
      expect(corpus.candidates, hasLength(7), reason: '候选按题组，不按小问');

      final three = PaperComposer.compose(
        candidates: corpus.candidates,
        spec: const PaperSpec(targetCount: 3),
      );
      expect(three.items, hasLength(3));
      expect(three.requestedCount, 3);
      expect(
        three.items.map((item) => item.questionId).toSet(),
        hasLength(3),
        reason: '同一组不会被选两次',
      );

      final six = PaperComposer.compose(
        candidates: corpus.candidates,
        spec: const PaperSpec(targetCount: 6),
      );
      expect(six.items, hasLength(6));
      expect(
        six.items.map((item) => item.questionId).toSet(),
        hasLength(6),
      );
      expect(
        six.items.every((item) => !item.questionId.endsWith('-2')),
        isTrue,
        reason: '入卷的是各组代表题（组内第一行），不是小问行',
      );
    });

    test('组内知识点取并集：知识点只挂在小问 2 上，题组仍覆盖它', () async {
      const material = '【材料 S1-M1】\n阅读下面的文字。';
      final point = (await db.into(db.knowledgePoints).insert(
            KnowledgePointsCompanion.insert(
              id: 'kp-test',
              title: '现代文阅读',
              content: '',
              createdAt: 0,
              updatedAt: 0,
            ),
          ));
      await db.into(db.tags).insert(
            TagsCompanion.insert(
              id: 'tag-kp',
              name: '现代文阅读',
              createdAt: 0,
              updatedAt: 0,
            ),
          );
      await db.into(db.objectTags).insert(
            ObjectTagsCompanion.insert(
              id: 'ot-q',
              tagId: 'tag-kp',
              objectType: 'question',
              objectId: 'q-kp-2',
              createdAt: 0,
            ),
          );
      await db.into(db.objectTags).insert(
            ObjectTagsCompanion.insert(
              id: 'ot-p',
              tagId: 'tag-kp',
              objectType: 'knowledge_point',
              objectId: 'kp-test',
              createdAt: 0,
            ),
          );
      await seedGroupRow('q-kp-1', material: material, question: '（1）问题一');
      await seedGroupRow('q-kp-2', material: material, question: '（2）问题二');

      final corpus = await readPaperCorpus(db);
      expect(corpus.candidates, hasLength(1));
      expect(
        corpus.candidates.single.matchedKnowledgePointIds,
        contains('kp-test'),
        reason: '组内任何小问挂的知识点都算这道题覆盖到',
      );
      expect(point, isNotNull);
    });
  });

  group('readQuestionGroupInfo：详情页「本组共 N 小问」', () {
    test('打开组内任意一题都能读到整组（代表题 + 全部小问 id）', () async {
      await seedChineseGroup();

      final info = await readQuestionGroupInfo(db, 'q-modern-3');
      expect(info, isNotNull);
      expect(info!.isGroup, isTrue);
      expect(info.size, 4);
      expect(info.representativeId, 'q-modern-1');
      expect(
        info.questionIds,
        <String>['q-modern-1', 'q-modern-2', 'q-modern-3', 'q-modern-4'],
      );
      expect(info.label, '材料 S1-M1');
      expect(info.material, contains('种植入门问答'));
    });

    test('独立题返回 null；单个材料行返回 size=1 且 isGroup=false', () async {
      await seedStandalone('q-alone');
      expect(await readQuestionGroupInfo(db, 'q-alone'), isNull);

      await seedGroupRow(
        'q-one',
        material: '【材料 S1-M1】\n只有一行材料的小题。',
        question: '（1）唯一小问',
      );
      final info = await readQuestionGroupInfo(db, 'q-one');
      expect(info, isNotNull);
      expect(info!.size, 1);
      expect(info.isGroup, isFalse);
    });
  });

  group('纯逻辑 questionGroupSignatureOf', () {
    test('有【题目】分隔：组键取材料正文；无分隔：退回首材料标题', () {
      final full = questionGroupSignatureOf(
        stem: '【材料 S1-M1】\n材料正文。\n\n【题目】\n（1）问题',
        sourceLabel: '卷 A',
      );
      final legacy = questionGroupSignatureOf(
        stem: '【材料 S1-M1】\n材料正文。\n\n（1）问题',
        sourceLabel: '卷 A',
      );
      expect(full, isNotNull);
      expect(legacy, isNotNull);
      expect(full!.material, '【材料 S1-M1】\n材料正文。');
      expect(legacy!.material, isNull);

      // 同卷同首标题、材料正文不同 → 只有「有【题目】」那条口径能区分。
      final other = questionGroupSignatureOf(
        stem: '【材料 S1-M1】\n另一段正文。\n\n【题目】\n（1）问题',
        sourceLabel: '卷 A',
      );
      expect(other!.groupKey, isNot(full.groupKey));
      // 同卷同首标题的旧数据只能按标题归组（文档里写明的退路）。
      expect(
        legacy.groupKey,
        questionGroupSignatureOf(
          stem: '【材料 S1-M1】\n别的内容。\n\n（2）另一问',
          sourceLabel: '卷 A',
        )!
            .groupKey,
      );
    });

    test('来源标签为空 / 无材料前缀 / 空题干：返回 null（不建组）', () {
      expect(
        questionGroupSignatureOf(
          stem: '【材料 S1-M1】\n材料。\n\n【题目】\n问题',
          sourceLabel: '   ',
        ),
        isNull,
      );
      expect(
        questionGroupSignatureOf(stem: '普通题干', sourceLabel: '卷 A'),
        isNull,
      );
      expect(
        questionGroupSignatureOf(stem: '', sourceLabel: '卷 A'),
        isNull,
      );
    });
  });
}
