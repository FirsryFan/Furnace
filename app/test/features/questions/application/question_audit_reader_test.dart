/// 题库体检的读表口径：一次读全库，拼成 `QuestionAuditRow`，交给纯逻辑判据。
///
/// 断的是「读表有没有改变事实」：字段一一对应、选项顺序、知识点推导、
/// 配图计数口径、全量不截断、空题干不被偷偷滤掉、学科键集合、空指纹交给体检层。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/domain/services/questions/question_intake_audit.dart';
import 'package:furnace/features/questions/application/question_audit_reader.dart';

void main() {
  late AppDatabase db;
  late QuestionRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = QuestionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Question> ingest({
    required String stem,
    String? answer,
    String? solution,
    String subjectKey = '',
    String questionType = 'solution',
    String sourceLevel = 'unknown',
    String sourceLabel = '',
    int? year,
    String? region,
    double? difficulty,
    double? aiQuality,
    String state = 'structured',
    List<QuestionOptionDraft> options = const <QuestionOptionDraft>[],
  }) async {
    final result = await repo.ingest(
      QuestionDraft(
        stem: stem,
        answer: answer,
        solution: solution,
        subjectKey: subjectKey,
        questionType: questionType,
        sourceLevel: sourceLevel,
        sourceLabel: sourceLabel,
        year: year,
        region: region,
        difficulty: difficulty,
        aiQuality: aiQuality,
        state: state,
        options: options,
      ),
      now: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    return result.question;
  }

  /// 直接落一行题：绕开仓储的「题干非空」校验，用来造体检要抓的脏数据。
  Future<void> rawQuestion({
    required String id,
    String stem = '题干',
    String subjectKey = '',
    String sourceLevel = 'unknown',
    String stemFingerprint = '',
    int? serialNo,
    double? aiQuality,
    int createdAt = 1,
  }) async {
    await db.into(db.questions).insert(
          QuestionsCompanion.insert(
            id: id,
            stem: stem,
            createdAt: createdAt,
            updatedAt: createdAt,
            subjectKey: Value(subjectKey),
            sourceLevel: Value(sourceLevel),
            stemFingerprint: Value(stemFingerprint),
            serialNo: Value(serialNo),
            aiQuality: Value(aiQuality),
          ),
        );
  }

  Future<void> seedAttachment({
    required String id,
    required String ownerType,
    required String ownerId,
  }) async {
    await db.into(db.attachments).insert(
          AttachmentsCompanion.insert(
            id: id,
            ownerType: ownerType,
            ownerId: ownerId,
            relPath: 'question_images/$ownerId/$id/a.png',
            createdAt: 1,
          ),
        );
  }

  Future<void> seedTagLink({
    required String id,
    required String tagId,
    required String objectType,
    required String objectId,
  }) async {
    await db.into(db.objectTags).insert(
          ObjectTagsCompanion.insert(
            id: id,
            tagId: tagId,
            objectType: objectType,
            objectId: objectId,
            createdAt: 1,
          ),
        );
  }

  QuestionAuditRow rowOf(QuestionAuditCorpus corpus, String questionId) =>
      corpus.rows.singleWhere((row) => row.questionId == questionId);

  test('字段一一映射：题号/题干/答案/解析/学科/来源/年份/地区/难度/状态/选项', () async {
    final question = await ingest(
      stem: r'已知 $f(x)=x^2$，求导。',
      answer: '2x',
      solution: '用幂函数求导法则。',
      subjectKey: 'math',
      questionType: 'single_choice',
      sourceLevel: 'gaokao',
      sourceLabel: '2026 届高三上期末',
      year: 2026,
      region: '江苏',
      difficulty: 6.5,
      aiQuality: 0.8,
      state: 'processed',
      options: const <QuestionOptionDraft>[
        QuestionOptionDraft(label: 'A', content: 'x'),
        QuestionOptionDraft(label: 'B', content: '2x', isCorrect: true),
      ],
    );

    final corpus = await readQuestionAuditCorpus(db);

    expect(corpus.rows, hasLength(1));
    expect(corpus.isEmpty, isFalse);
    final row = corpus.rows.single;
    expect(row.questionId, question.id);
    expect(row.serialNo, question.serialNo);
    expect(row.stem, r'已知 $f(x)=x^2$，求导。');
    expect(row.answer, '2x');
    expect(row.solution, '用幂函数求导法则。');
    expect(row.subjectKey, 'math');
    expect(row.questionType, 'single_choice');
    expect(row.sourceLevel, 'gaokao');
    expect(row.sourceLabel, '2026 届高三上期末');
    expect(row.year, 2026);
    expect(row.region, '江苏');
    expect(row.difficulty, 6.5);
    expect(row.aiQuality, 0.8);
    expect(row.state, 'processed');
    expect(row.stemFingerprint, isNotNull);
    expect(row.imageCount, 0);
    expect(row.knowledgePointIds, isEmpty);
    expect(row.options.map((option) => option.label), <String>['A', 'B']);
    expect(row.options[1].content, '2x');
    expect(row.options[1].isCorrect, isTrue);
    expect(corpus.knownSubjectKeys, <String>{'math'});
  });

  test('选项按 sortOrder 升序、平手按 label（与仓储 optionsOf 同口径）', () async {
    final question = await ingest(
      stem: '把选项打乱的题',
      options: const <QuestionOptionDraft>[
        QuestionOptionDraft(label: 'C', content: '丙', sortOrder: 2),
        QuestionOptionDraft(label: 'A', content: '甲', sortOrder: 0),
        QuestionOptionDraft(label: 'B', content: '乙', sortOrder: 1),
      ],
    );

    final row = rowOf(await readQuestionAuditCorpus(db), question.id);

    expect(row.options.map((option) => option.label), <String>['A', 'B', 'C']);
    expect(
        row.options.map((option) => option.content), <String>['甲', '乙', '丙']);
  });

  test('配图数只数 attachments 里 ownerType==question 的行', () async {
    final a = await ingest(stem: '带两张图的题');
    final b = await ingest(stem: '没图的题');

    await seedAttachment(
      id: 'att-1',
      ownerType: 'question',
      ownerId: a.id,
    );
    await seedAttachment(
      id: 'att-2',
      ownerType: 'question',
      ownerId: a.id,
    );
    // 同一 ownerId 但主人类型不同：不是题目配图（例如 AI 消息里的图）。
    await seedAttachment(
      id: 'att-3',
      ownerType: 'ai_message',
      ownerId: a.id,
    );
    await seedAttachment(
      id: 'att-4',
      ownerType: 'question',
      ownerId: b.id,
    );

    final corpus = await readQuestionAuditCorpus(db);

    expect(rowOf(corpus, a.id).imageCount, 2);
    expect(rowOf(corpus, b.id).imageCount, 1);
  });

  test('知识点：同一标签既挂题又挂知识点才算覆盖（同一标签推并集）', () async {
    await rawQuestion(id: 'q-shared');
    await rawQuestion(id: 'q-alone');
    await seedTagLink(
      id: 'link-1',
      tagId: 'tag-t1',
      objectType: 'question',
      objectId: 'q-shared',
    );
    await seedTagLink(
      id: 'link-2',
      tagId: 'tag-t1',
      objectType: 'knowledge_point',
      objectId: 'kp-1',
    );
    await seedTagLink(
      id: 'link-3',
      tagId: 'tag-t2',
      objectType: 'question',
      objectId: 'q-alone',
    );
    // q-alone 挂的标签没有任何知识点也挂 → 推不出覆盖点。
    await seedTagLink(
      id: 'link-4',
      tagId: 'tag-t3',
      objectType: 'knowledge_point',
      objectId: 'kp-2',
    );

    final corpus = await readQuestionAuditCorpus(db);

    expect(rowOf(corpus, 'q-shared').knowledgePointIds, <String>['kp-1']);
    expect(rowOf(corpus, 'q-alone').knowledgePointIds, isEmpty);
  });

  test('全量读取：250 道题都读出来（仓储 all() 的 200 条上限挡不住体检）', () async {
    for (var i = 0; i < 250; i++) {
      await rawQuestion(
        id: 'q-bulk-${i.toString().padLeft(3, '0')}',
        stem: '批量题 $i',
        createdAt: i + 1,
      );
    }

    final corpus = await readQuestionAuditCorpus(db);

    expect(corpus.rows, hasLength(250));
    expect(corpus.rows.first.questionId, 'q-bulk-000');
    expect(corpus.rows.last.questionId, 'q-bulk-249');
  });

  test('空题干不被读表滤掉：体检层才能报 h1_stem_empty', () async {
    await rawQuestion(id: 'q-empty', stem: '');

    final corpus = await readQuestionAuditCorpus(db);
    expect(corpus.rows.single.stem, '');

    final report =
        const QuestionIntakeAudit(currentYear: 2026).audit(corpus.rows);
    expect(
      report.findingsFor('q-empty').map((finding) => finding.code),
      contains(QuestionAuditCodes.h1StemEmpty),
    );
  });

  test('knownSubjectKeys：去空、去重、排序', () async {
    await rawQuestion(id: 'q-1', subjectKey: 'math');
    await rawQuestion(id: 'q-2', subjectKey: ' physics ');
    await rawQuestion(id: 'q-3', subjectKey: '');
    await rawQuestion(id: 'q-4', subjectKey: 'physics');

    final corpus = await readQuestionAuditCorpus(db);

    expect(corpus.knownSubjectKeys.toList(), <String>['math', 'physics']);
  });

  test('空指纹给它 null（交给体检层回退归一化题干），非空指纹原样透传', () async {
    await rawQuestion(id: 'q-no-fp', stem: '指纹为空的题', stemFingerprint: '');
    await rawQuestion(
      id: 'q-with-fp',
      stem: '指纹存在的题',
      stemFingerprint: '0123456789abcdef',
    );

    final corpus = await readQuestionAuditCorpus(db);

    expect(rowOf(corpus, 'q-no-fp').stemFingerprint, isNull);
    expect(
      rowOf(corpus, 'q-with-fp').stemFingerprint,
      '0123456789abcdef',
    );
  });

  test('读表顺序稳定：按题目 id 排序，不依赖 SQLite 返回顺序', () async {
    await rawQuestion(id: 'q-c', createdAt: 3);
    await rawQuestion(id: 'q-a', createdAt: 1);
    await rawQuestion(id: 'q-b', createdAt: 2);

    final corpus = await readQuestionAuditCorpus(db);

    expect(
      corpus.rows.map((row) => row.questionId),
      <String>['q-a', 'q-b', 'q-c'],
    );
  });

  test('provider：整库报告按题库现有学科与系统年份体检', () async {
    await rawQuestion(id: 'q-empty-report', stem: '');
    final container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);

    final corpus = await container.read(questionAuditCorpusProvider.future);
    expect(corpus.rows, hasLength(1));

    final report = await container.read(questionAuditReportProvider.future);
    expect(
      report.findingsFor('q-empty-report').map((finding) => finding.code),
      contains(QuestionAuditCodes.h1StemEmpty),
    );
    expect(report.errorCount, greaterThanOrEqualTo(1));
  });

  test('空库：不抛异常，行与学科都为空', () async {
    final corpus = await readQuestionAuditCorpus(db);

    expect(corpus.isEmpty, isTrue);
    expect(corpus.rows, isEmpty);
    expect(corpus.knownSubjectKeys, isEmpty);
  });
}
