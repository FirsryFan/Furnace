import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/content_ref_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/services/content/content_package.dart';
import 'package:furnace/domain/services/content/content_package_import_service.dart';
import 'package:furnace/domain/services/content/content_ref_vocab.dart';
import 'package:furnace/domain/services/content/dag_flashcard_generator.dart';

/// `ContentPackageImportService`（task-80，2026-11-15）：内容包 → 产品题库。
///
/// 要锁的行为（每条能单独失败）：
///
///  * 字段映射：题干/答案/题型/学科/来源/年份/地区/难度/能力/文本格式/题名；
///  * **答案只来自 Source**：`answer.parts` 原值；AI 生成解析不进
///    `questions.solution`；来源解析是否写入取决于内容包渲染策略；
///  * **幂等**：同 `content_id` 二次导入不建第二道题/第二条引用；
///  * **换版**：version/hash 原地更新（旧 hash 进 metadata）；题干变了才新建题，
///    旧 `source_package` 引用改指向新题；
///  * `content_refs`：题目 `source_package` + 知识节点 `node`，**不含正文**；
///  * 知识点：内容节点幂等映射/创建产品知识点，显式映射不新建；
///  * 标签：只引用已有 `tags`，缺失记 `missing_tag`，**不自动造标签**；
///  * `scoring` 只进引用摘要（产品 questions 没有分值列），不伪造分值；
///  * 可选 DAG 卡：dry run 默认不写；apply 只建模板 + `card_seed` 引用，
///    不建 `card_states` / `review_logs`；二次 apply 幂等；
///  * **失败可回滚**：导入中途抛错时题目/知识点/引用全部回滚；
///  * 所有用例只用 `NativeDatabase.memory()`，不碰用户真实库。
void main() {
  late AppDatabase db;
  late QuestionRepository questions;
  late TagRepository tags;
  late ContentRefRepository contentRefs;
  late AnkiRepository anki;
  late ContentPackageImportService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    questions = QuestionRepository(db);
    tags = TagRepository(db);
    contentRefs = ContentRefRepository(db);
    anki = AnkiRepository(db);
    service = ContentPackageImportService(
      db,
      questions: questions,
      tags: tags,
      contentRefs: contentRefs,
      anki: anki,
    );
  });

  tearDown(() async {
    await db.close();
  });

  // ---------------------------------------------------------------------------
  // 1. 字段映射 + 引用 + 知识点
  // ---------------------------------------------------------------------------

  test('导入一包：题目字段/答案/引用/知识点/标签全部按映射落库', () async {
    final tagCountBefore = (await tags.getAllTags()).length;
    await _seedConventionTags(tags);

    final package = _package(
      knowledge: <Map<String, Object?>>[
        _knowledge(nodeId: 'kp-test-primary', label: '测试主知识点', role: 'primary'),
      ],
    );
    final result = await service.importPackage(package);

    expect(result.status, ContentPackageImportStatus.importedWithSkips);
    expect(result.questionCreated, isTrue);
    expect(result.questionId, startsWith('q-'));
    expect(result.serialNo, isNotNull);
    expect(result.questionRefId, startsWith('cref-'));
    expect(result.contentVersion, 1);
    expect(result.contentHash, _hashA);
    expect(result.knowledgePoints, hasLength(1));
    final point = result.knowledgePoints.single;
    expect(point.created, isTrue);
    expect(point.productKnowledgePointId, startsWith('kp-'));
    expect(point.contentNodeId, 'kp-test-primary');

    final question = (await questions.byId(result.questionId!))!;
    expect(question.stem, _defaultStem);
    expect(question.answer, 'B');
    expect(question.solution, isNull, reason: '内容包不渲染来源解析 → DAG 承担解析');
    expect(question.subjectKey, 'physics');
    expect(question.questionType, 'single_choice');
    expect(question.sourceLevel, 'gaokao');
    expect(question.sourceLabel, '2023 全国甲卷测试来源');
    expect(question.year, 2023);
    expect(question.region, '全国甲卷');
    expect(question.difficulty, 2);
    expect(question.difficultySource, 'ai');
    expect(question.textFormat, 'markdown');
    expect(question.capability, contains('A4'));
    expect(question.title, '测试题名', reason: '内容包建议名只填空，不覆盖已有题名');
    expect(question.origin, 'content_package');
    expect(question.state, 'structured');

    // 题目引用：id/版本/hash/学科；metadata 只有摘要，没有题干/答案正文。
    final questionRef = await contentRefs.findOne(
      contentId: 'Q-TEST0001',
      objectType: ContentObjectType.question,
      objectId: result.questionId!,
      role: ContentRefRole.sourcePackage,
    );
    expect(questionRef, isNotNull);
    expect(questionRef!.contentVersion, 1);
    expect(questionRef.contentHash, _hashA);
    expect(questionRef.subject, 'physics');
    final metadata =
        jsonDecode(questionRef.metadataJson!) as Map<String, Object?>;
    expect(metadata['answer_trust'], 'B_independently_verified');
    expect(metadata['answer_source_id'], 'E-SRC-TEST-ANS');
    expect(metadata['scoring'], <String, Object?>{'source': 'none'});
    expect(questionRef.metadataJson, isNot(contains(_defaultStem)));
    expect(questionRef.metadataJson, isNot(contains('B. 乙')));

    // 知识点引用：内容节点 id ↔ 产品 kp id。
    final pointRef = await contentRefs.findOne(
      contentId: 'kp-test-primary',
      objectType: ContentObjectType.knowledgePoint,
      objectId: point.productKnowledgePointId,
      role: ContentRefRole.node,
    );
    expect(pointRef, isNotNull);
    expect(pointRef!.subject, 'physics');

    final storedPoint = (await anki.getKnowledgePointById(
      point.productKnowledgePointId,
    ))!;
    expect(storedPoint.title, '测试主知识点');
    expect(storedPoint.source, 'content_package');

    // 标签：两条候选命中；知识点标签候选缺（不建）；标签总数不变。
    final questionTags = await tags.tagsForObject(
      objectType: 'question',
      objectId: result.questionId!,
    );
    expect(
      questionTags.map((tag) => tag.path).toSet(),
      <String>{'文化课/学科/物理', '文化课/题型/单选题'},
    );
    expect(result.missingTags, hasLength(1));
    expect(
      result.missingTags.single.requested,
      '文化课/学科/物理/测试主知识点',
    );
    expect(
      (await tags.getAllTags()).length,
      tagCountBefore + 5,
      reason: '只创建了测试自己种的 5 个标签，导入本身没有建标签',
    );
  });

  test('幂等：同 content_id 二次导入不建第二道题/第二条引用', () async {
    final package = _package(
      knowledge: <Map<String, Object?>>[
        _knowledge(nodeId: 'kp-test-primary', label: '测试主知识点', role: 'primary'),
      ],
    );
    final first = await service.importPackage(package);
    final second = await service.importPackage(package);

    expect(first.questionCreated, isTrue);
    expect(second.questionCreated, isFalse);
    expect(second.questionId, first.questionId);
    expect(await db.select(db.questions).get(), hasLength(1));
    expect(await db.select(db.knowledgePoints).get(), hasLength(1));
    expect(await db.select(db.contentRefs).get(), hasLength(2));
    expect(await db.select(db.objectTags).get(), isEmpty);

    final refs = await contentRefs.listByContentId('Q-TEST0001');
    expect(refs, hasLength(1));
    expect(refs.single.contentHash, _hashA);
  });

  // ---------------------------------------------------------------------------
  // 2. 换版
  // ---------------------------------------------------------------------------

  test('换版（题干不变）：引用原地更新版本/hash，旧值进 metadata', () async {
    final first = await service.importPackage(_package());
    final firstRef = (await contentRefs.listByContentId('Q-TEST0001')).single;

    final second = await service.importPackage(
      _package(version: 2, contentHash: _hashB),
    );

    expect(second.questionCreated, isFalse);
    expect(second.questionId, first.questionId);
    expect(await db.select(db.questions).get(), hasLength(1));
    final refs = await contentRefs.listByContentId('Q-TEST0001');
    expect(refs, hasLength(1));
    expect(refs.single.id, firstRef.id, reason: '同一条引用原地更新');
    expect(refs.single.contentVersion, 2);
    expect(refs.single.contentHash, _hashB);
    final metadata =
        jsonDecode(refs.single.metadataJson!) as Map<String, Object?>;
    expect(metadata['previous_hash'], _hashA);
    expect(metadata['previous_version'], 1);
    expect(second.contentVersion, 2);
  });

  test('换版但答案变了：产品题不原地改，显式记 questionBodyNotUpdated', () async {
    await service.importPackage(_package(answerValue: 'B'));
    final second = await service.importPackage(
      _package(version: 2, contentHash: _hashB, answerValue: 'C'),
    );

    expect(second.questionCreated, isFalse);
    final stored = (await questions.byId(second.questionId!))!;
    expect(stored.answer, 'B', reason: '产品题只追加，不原地改写答案');
    expect(
      second.skipped.map((skip) => skip.code),
      contains(ContentPackageSkipReason.questionBodyNotUpdated),
    );
  });

  test('换版（题干变了）：新建产品题，旧 source_package 引用改指向新题', () async {
    final first = await service.importPackage(_package());
    final second = await service.importPackage(
      _package(
        version: 2,
        contentHash: _hashB,
        stem: '$_defaultStem\n\n（题干修订）',
      ),
    );

    expect(second.questionCreated, isTrue);
    expect(second.questionId, isNot(first.questionId));
    expect(await db.select(db.questions).get(), hasLength(2));
    final refs = await contentRefs.listByContentId('Q-TEST0001');
    final questionRefs = <ContentRefRow>[
      for (final ref in refs)
        if (ref.objectType == ContentObjectType.question) ref,
    ];
    expect(questionRefs, hasLength(1), reason: '换版改引用，不并存两条题目引用');
    expect(questionRefs.single.objectId, second.questionId);
    expect(
      second.skipped.map((skip) => skip.code),
      contains(ContentPackageSkipReason.staleQuestionRefRemoved),
    );
    // 旧题仍留在题库里（只追加），只是不再被该 content_id 引用。
    expect(await questions.byId(first.questionId!), isNotNull);
  });

  // ---------------------------------------------------------------------------
  // 3. 标签只引用、缺失跳过
  // ---------------------------------------------------------------------------

  test('标签缺失：只记录 skipped，绝不自动建标签', () async {
    final result = await service.importPackage(_package());

    expect(result.questionId, isNotNull);
    expect(await db.select(db.tags).get(), isEmpty);
    expect(await db.select(db.objectTags).get(), isEmpty);
    expect(result.missingTags, isNotEmpty);
    expect(
      result.skipped.map((skip) => skip.code),
      contains(ContentPackageSkipReason.missingTag),
    );
  });

  // ---------------------------------------------------------------------------
  // 4. 解析/答案来源
  // ---------------------------------------------------------------------------

  test('来源解析按内容包策略写入：render_student_analysis=true 才进 solution', () async {
    final result = await service.importPackage(
      _package(
        renderAnalysis: true,
        sourceSolutionRender: true,
        sourceSolutionBody: '《高考试题分析》来源解析原文。',
      ),
    );
    final question = (await questions.byId(result.questionId!))!;
    expect(question.solution, '《高考试题分析》来源解析原文。');
    expect(
      result.skipped.map((skip) => skip.code),
      isNot(contains(ContentPackageSkipReason.solutionSuppressed)),
    );
  });

  test('AI 生成解析不进产品 solution；来源解析被抑制时也不写', () async {
    final result = await service.importPackage(
      _package(
        includeAiSolution: true,
        sourceSolutionRender: false,
      ),
    );
    final question = (await questions.byId(result.questionId!))!;
    expect(question.solution, isNull);
    final skipCodes = result.skipped.map((skip) => skip.code).toList();
    expect(skipCodes, contains(ContentPackageSkipReason.solutionNotSource));
    expect(skipCodes, contains(ContentPackageSkipReason.solutionSuppressed));
  });

  test('分值只进引用摘要：产品 questions 没有 points 列，不伪造分值', () async {
    await service.importPackage(
      _package(
        scoringTotalPoints: 6,
        scoringSource: 'official',
        subquestions: <Map<String, Object?>>[
          <String, Object?>{'part': '(1)', 'points': 3},
          <String, Object?>{'part': '(2)', 'points': null},
        ],
      ),
    );
    final ref = (await contentRefs.listByContentId('Q-TEST0001')).single;
    final metadata = jsonDecode(ref.metadataJson!) as Map<String, Object?>;
    expect(metadata['scoring'], <String, Object?>{
      'total_points': 6,
      'source': 'official',
    });
    final subquestions = metadata['subquestions'] as List<Object?>;
    expect(subquestions, hasLength(2));
    expect(
      (subquestions.first! as Map<String, Object?>)['points'],
      3,
    );
    expect(
      (subquestions.last! as Map<String, Object?>).containsKey('points'),
      isFalse,
      reason: 'Source 未给第 (2) 问分值 → metadata 里不出现，不填 0',
    );

    final questionColumns = await db.columnsOf('questions');
    expect(questionColumns, isNot(contains('points')));
    expect(questionColumns, isNot(contains('score')));
  });

  // ---------------------------------------------------------------------------
  // 5. 知识点：显式映射 / 不自动创建
  // ---------------------------------------------------------------------------

  test('知识点显式映射：复用产品 kp，不新建；createKnowledgePoints=false 时缺映射跳过', () async {
    final existing = await anki.createKnowledgePoint(
      title: '用户已有的知识点',
      content: '用户自己的内容。',
    );
    final mapped = await service.importPackage(
      _package(
        knowledge: <Map<String, Object?>>[
          _knowledge(
              nodeId: 'kp-test-primary', label: '测试主知识点', role: 'primary'),
        ],
      ),
      options: ContentPackageImportOptions(
        createKnowledgePoints: false,
        knowledgePointIdByNodeId: <String, String>{
          'kp-test-primary': existing.id,
        },
      ),
    );
    expect(mapped.knowledgePoints.single.mapped, isTrue);
    expect(mapped.knowledgePoints.single.created, isFalse);
    expect(
      mapped.knowledgePoints.single.productKnowledgePointId,
      existing.id,
    );
    expect(await db.select(db.knowledgePoints).get(), hasLength(1));

    final skipped = await service.importPackage(
      _package(
        contentId: 'Q-TEST0002',
        knowledge: <Map<String, Object?>>[
          _knowledge(nodeId: 'kp-other', label: '另一个知识点', role: 'related'),
        ],
      ),
      options: const ContentPackageImportOptions(createKnowledgePoints: false),
    );
    expect(skipped.knowledgePoints, isEmpty);
    expect(
      skipped.skipped.map((skip) => skip.code),
      contains(ContentPackageSkipReason.knowledgePointUnmapped),
    );
    expect(await db.select(db.knowledgePoints).get(), hasLength(1));
  });

  // ---------------------------------------------------------------------------
  // 6. 事务回滚
  // ---------------------------------------------------------------------------

  test('中途失败整批回滚：题目/知识点/引用一行不留', () async {
    final throwing = ContentPackageImportService(
      db,
      questions: _ThrowingQuestionRepository(db),
      tags: tags,
      contentRefs: contentRefs,
      anki: anki,
    );
    await expectLater(
      throwing.importPackage(
        _package(
          knowledge: <Map<String, Object?>>[
            _knowledge(
              nodeId: 'kp-test-primary',
              label: '测试主知识点',
              role: 'primary',
            ),
          ],
        ),
      ),
      throwsA(isA<StateError>()),
    );

    expect(await db.select(db.questions).get(), isEmpty);
    expect(await db.select(db.knowledgePoints).get(), isEmpty);
    expect(await db.select(db.contentRefs).get(), isEmpty);
    expect(await db.select(db.objectTags).get(), isEmpty);
  });

  // ---------------------------------------------------------------------------
  // 7. 可选 DAG 卡
  // ---------------------------------------------------------------------------

  test('DAG 卡 dry run：只计划不写；apply 只建模板 + card_seed，不复制 FSRS', () async {
    final package = _package(
      knowledge: <Map<String, Object?>>[
        _knowledge(nodeId: 'kp-test-primary', label: '测试主知识点', role: 'primary'),
      ],
      board: _board(
        nodes: <Map<String, Object?>>[
          _node(
            id: 'N-T-01',
            kind: 'condition',
            role: 'read_question',
            label: '审题',
            body: '读题。',
            result: '待判 A/B。',
          ),
          _node(
            id: 'N-T-02',
            kind: 'formula_or_model',
            role: 'construct',
            label: '建模：写出公式',
            body: '把过程写成公式。',
            formulas: <String>['v=v_0+at'],
            result: 'v=v_0+at',
          ),
          _node(
            id: 'N-T-03',
            kind: 'computation',
            role: 'compute',
            label: '纯爆算',
            body: '算一遍。',
            formulas: <String>['1+1=2'],
            result: '2',
          ),
          _node(
            id: 'N-T-04',
            kind: 'conclusion',
            role: 'conclude',
            label: '结论',
            body: '收口。',
            result: '答案 B',
          ),
        ],
        causes: <Map<String, Object?>>[
          _cause(code: 'EC-T-01', symptom: '把分速度当合速度'),
        ],
      ),
    );

    final dry = await service.importPackage(
      package,
      options: const ContentPackageImportOptions(generateCards: true),
    );
    expect(dry.cardPlan, isNotNull);
    expect(dry.cardPlan!.dryRun, isTrue);
    expect(dry.cardPlan!.wouldCreate, 3, reason: '公式 + 结论 + 错因');
    expect(dry.cardPlan!.skipped, 2, reason: '审题节点 + 纯爆算节点');
    expect(dry.cardPlan!.blocked, 0);
    expect(await anki.getAllTemplates(), isEmpty);
    expect(
      (await contentRefs.listByContentId('Q-TEST0001'))
          .where((ref) => ref.role == ContentRefRole.cardSeed),
      isEmpty,
    );

    final applied = await service.importPackage(
      package,
      options: const ContentPackageImportOptions(
        generateCards: true,
        cardsDryRun: false,
      ),
    );
    expect(applied.cardPlan!.created, 3);
    final templates = await anki.getAllTemplates();
    expect(templates, hasLength(3));
    for (final template in templates) {
      expect(template.externalId, startsWith('content:Q-TEST0001#'));
      expect(template.hint, startsWith('【AI】'));
    }
    final refs = await contentRefs.listByContentId('Q-TEST0001');
    expect(
      refs.where((ref) => ref.role == ContentRefRole.cardSeed),
      hasLength(3),
    );
    expect(await db.select(db.cardStates).get(), isEmpty);
    expect(await db.select(db.reviewLogs).get(), isEmpty);

    final again = await service.importPackage(
      package,
      options: const ContentPackageImportOptions(
        generateCards: true,
        cardsDryRun: false,
      ),
    );
    expect(again.cardPlan!.created, 0);
    expect(
      again.cardPlan!.skippedReasons[DagCardSkipReason.alreadyExists],
      3,
    );
    expect(await anki.getAllTemplates(), hasLength(3));
  });

  test('生成卡但缺产品知识点：不伪造 KP，整批卡片跳过并记原因', () async {
    final result = await service.importPackage(
      _package(
        board: _board(
          nodes: <Map<String, Object?>>[
            _node(
              id: 'N-T-04',
              kind: 'conclusion',
              role: 'conclude',
              label: '结论',
              body: '收口。',
              result: '答案 B',
            ),
          ],
        ),
      ),
      options: const ContentPackageImportOptions(
        createKnowledgePoints: false,
        generateCards: true,
      ),
    );
    expect(result.cardPlan, isNull);
    expect(
      result.skipped.map((skip) => skip.code),
      contains(ContentPackageSkipReason.cardMissingKnowledgePoint),
    );
    expect(await anki.getAllTemplates(), isEmpty);
  });

  // ---------------------------------------------------------------------------
  // 8. 阻断：非法内容 id 不写一行
  // ---------------------------------------------------------------------------

  test('非法内容 id 直接 blocked，不写任何一行', () async {
    final result =
        await service.importPackage(_package(contentId: 'QSET-20261115-01'));

    expect(result.status, ContentPackageImportStatus.blocked);
    expect(result.questionId, isNull);
    expect(result.blocked, isNotEmpty);
    expect(await db.select(db.questions).get(), isEmpty);
    expect(await db.select(db.contentRefs).get(), isEmpty);
    expect(await db.select(db.knowledgePoints).get(), isEmpty);
  });

  // ---------------------------------------------------------------------------
  // 9. 解析目录入口（L1 + 学科板）
  // ---------------------------------------------------------------------------

  test('ContentPackage.fromJson：缺 id / schema 不认识时抛 FormatException', () {
    expect(
      () => ContentPackage.fromJson(
        _questionJson()..['schema_version'] = 'furnace.content.base-question/9',
      ),
      throwsFormatException,
    );
    expect(
      () => ContentPackage.fromJson(_questionJson()..remove('id')),
      throwsFormatException,
    );
    expect(
      () => ContentPackage.fromJson(
        _questionJson()..['stem'] = <String, Object?>{'text': '  '},
      ),
      throwsFormatException,
    );
  });
}

// -----------------------------------------------------------------------------
// fixtures
// -----------------------------------------------------------------------------

final String _hashA = 'a' * 64;
final String _hashB = 'b' * 64;
final String _hashC = 'c' * 64;
const String _defaultStem = '测试题干：下列说法正确的是（    ）\n\nA. 甲\nB. 乙';

ContentPackage _package({
  String contentId = 'Q-TEST0001',
  int version = 1,
  String? contentHash,
  String stem = _defaultStem,
  bool renderAnalysis = false,
  bool sourceSolutionRender = false,
  String sourceSolutionBody = '来源解析正文（测试）。',
  bool includeAiSolution = false,
  List<Map<String, Object?>>? knowledge,
  Map<String, Object?>? board,
  double? scoringTotalPoints,
  String scoringSource = 'none',
  List<Map<String, Object?>>? subquestions,
  String answerValue = 'B',
}) {
  final question = _questionJson(
    contentId: contentId,
    version: version,
    contentHash: contentHash ?? _hashA,
    stem: stem,
    answerValue: answerValue,
    renderAnalysis: renderAnalysis,
    sourceSolutionRender: sourceSolutionRender,
    sourceSolutionBody: sourceSolutionBody,
    includeAiSolution: includeAiSolution,
    knowledge: knowledge ??
        <Map<String, Object?>>[
          _knowledge(
            nodeId: 'kp-test-primary',
            label: '测试主知识点',
            role: 'primary',
          ),
        ],
    scoringTotalPoints: scoringTotalPoints,
    scoringSource: scoringSource,
    subquestions: subquestions,
  );
  return ContentPackage.fromJson(question, board: board);
}

Map<String, Object?> _questionJson({
  String contentId = 'Q-TEST0001',
  String subject = 'physics',
  int version = 1,
  String contentHash = '',
  String stem = _defaultStem,
  bool renderAnalysis = false,
  bool sourceSolutionRender = false,
  String sourceSolutionBody = '来源解析正文（测试）。',
  bool includeAiSolution = false,
  List<Map<String, Object?>>? knowledge,
  double? scoringTotalPoints,
  String scoringSource = 'none',
  List<Map<String, Object?>>? subquestions,
  String answerValue = 'B',
}) {
  return <String, Object?>{
    'schema_version': kContentPackageBaseQuestionSchema,
    'id': contentId,
    'subject': subject,
    'title': <String, Object?>{
      'suggested': '测试题名',
      'source': 'ai',
      'rationale': '测试标题',
      'evidence_refs': <String>['E-SRC-TEST-STEM'],
    },
    'stem': <String, Object?>{
      'format': 'markdown+latex',
      'text': stem,
      'segments': const <Object?>[],
      'completeness': <String, Object?>{
        'has_all_subparts': true,
        'figure_placeholders_resolved': true,
        'source_fidelity': 'normalized_layout_only',
        'missing': const <Object?>[],
      },
    },
    'figures': const <Object?>[],
    'answer': <String, Object?>{
      'parts': <Map<String, Object?>>[
        <String, Object?>{
          'part': 'all',
          'value': answerValue,
          'format': 'selection',
          'evidence_refs': <String>['E-SRC-TEST-ANS'],
        },
      ],
      'official_trust': 'B_independently_verified',
      'answer_source': <String, Object?>{
        'id': 'E-SRC-TEST-ANS',
        'claim': '测试答案',
        'source': <String, Object?>{'type': 'source_file'},
      },
    },
    'solutions': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'SOL-T-01',
        'kind': 'official_source',
        'method_name': '来源解析',
        'trust': 'B_independently_verified',
        'body_md': sourceSolutionBody,
        'use_policy': 'source_reference_only',
        'evidence_refs': <String>['E-SRC-TEST-JX'],
        'source_kind': 'gaokao_analysis_book',
        'render_student_analysis': sourceSolutionRender,
        'render_position': sourceSolutionRender ? 'below_dag' : 'suppressed',
      },
      if (includeAiSolution)
        <String, Object?>{
          'id': 'SOL-T-AI',
          'kind': 'ai_generated',
          'method_name': 'AI 生成解析',
          'trust': 'C_ai_generated',
          'body_md': 'AI 生成的解析不应进产品题。',
          'use_policy': 'source_reference_only',
          'evidence_refs': <String>['E-DER-TEST-AI'],
          'source_kind': 'ai',
          'render_student_analysis': false,
          'render_position': 'suppressed',
        },
    ],
    'scoring': <String, Object?>{
      'anchors': const <Object?>[],
      if (scoringTotalPoints != null) 'total_points': scoringTotalPoints,
      'source': scoringSource,
    },
    'classification': <String, Object?>{
      'content_type': <String, Object?>{
        'code': 'PH-TEST',
        'label': '测试题型',
        'axes': <String, Object?>{
          'carrier': 'mechanics',
          'task': 'explain',
          'thinking': <String>['forward'],
          'scope': 'single_point',
        },
        'paper_form': 'single_choice',
        'rationale': '测试',
        'evidence_refs': <String>['E-DER-TEST-FIVE'],
      },
      'knowledge': knowledge ??
          <Map<String, Object?>>[
            _knowledge(
              nodeId: 'kp-test-primary',
              label: '测试主知识点',
              role: 'primary',
            ),
          ],
      'capability': <Map<String, Object?>>[
        <String, Object?>{
          'code': 'A4',
          'label': '结构化建模',
          'weight': 0.5,
          'evidence_refs': <String>['E-SRC-TEST-JX'],
        },
      ],
      'subject_skills': const <Object?>[],
      'subquestions': subquestions ??
          <Map<String, Object?>>[
            <String, Object?>{'id': 'all', 'points': null},
          ],
    },
    'meta': <String, Object?>{
      'source_level': 'gaokao',
      'source_label': '2023 全国甲卷测试来源',
      'year': 2023,
      'region': '全国甲卷',
      'source_url': null,
      'difficulty': <String, Object?>{
        'value': 2,
        'source': 'ai',
        'confidence': 0.35,
        'evidence_refs': <String>['E-DER-TEST-DIFFICULTY'],
      },
    },
    'panels': <String, Object?>{
      'board_refs': <String, Object?>{
        subject: <String, Object?>{
          'schema': 'furnace.content.physics-board/1',
          'version': 1,
          'path': 'boards/$subject-board.json',
          'content_hash': _hashC,
        },
      },
    },
    'relations': <String, Object?>{},
    'provenance': <String, Object?>{
      'version': version,
      'content_hash': contentHash.isEmpty ? _hashA : contentHash,
    },
    'review': <String, Object?>{'status': 'pending'},
    'evidence_refs': <String>['E-SRC-TEST-STEM'],
    'status': 'panel_generated',
    'analysis_render_policy': <String, Object?>{
      'reasoning_carrier': 'thinking_dag',
      'source_analysis_visible': renderAnalysis,
    },
  };
}

Map<String, Object?> _board({
  String questionId = 'Q-TEST0001',
  List<Map<String, Object?>>? nodes,
  List<Map<String, Object?>>? causes,
}) {
  return <String, Object?>{
    'schema_version': 'furnace.content.physics-board/1',
    'subject': 'physics',
    'question_id': questionId,
    'meta': <String, Object?>{'board_version': 1},
    'thinking_dag': <String, Object?>{
      'nodes': nodes ?? const <Object?>[],
      'edges': const <Object?>[],
    },
    'error_causes': <String, Object?>{
      'items': causes ?? const <Object?>[],
    },
  };
}

Map<String, Object?> _knowledge({
  required String nodeId,
  required String label,
  required String role,
}) =>
    <String, Object?>{
      'node_id': nodeId,
      'label': label,
      'role': role,
      'source': 'extracted',
      'confidence': 0.9,
      'evidence_refs': <String>['E-SRC-TEST-STEM'],
    };

Map<String, Object?> _node({
  required String id,
  required String kind,
  String role = '',
  String label = '',
  String body = '',
  List<String> formulas = const <String>[],
  List<String> keyQuantities = const <String>[],
  String result = '',
}) =>
    <String, Object?>{
      'id': id,
      'kind': kind,
      'role': role,
      'label': label,
      'body': body,
      'step_type': 'thinking',
      'evidence_refs': <String>['E-DER-TEST-STRAT'],
      'formulas': formulas,
      'key_quantities': keyQuantities,
      'result': result,
      'outputs': <String>[if (result.isNotEmpty) result],
    };

Map<String, Object?> _cause({
  required String code,
  required String symptom,
}) =>
    <String, Object?>{
      'code': code,
      'category': 'knowledge_gap',
      'symptom': symptom,
      'root_cause': '根因（测试）。',
      'diagnostic_question': '自问（测试）。',
      'remediation': '改法（测试）。',
      'locate_node': 'N-T-04',
      'prevalence_source': 'expert_judgment',
      'evidence_refs': <String>['E-DER-TEST-TRAP'],
    };

/// 建出 `文化课/学科/物理` 与 `文化课/题型/单选题` 两条真实路径。
Future<void> _seedConventionTags(TagRepository tags) async {
  final culture = await tags.createTag(name: '文化课');
  final subject = await tags.createTag(name: '学科', parentId: culture.id);
  await tags.createTag(name: '物理', parentId: subject.id);
  final type = await tags.createTag(name: '题型', parentId: culture.id);
  await tags.createTag(name: '单选题', parentId: type.id);
}

/// 在 `super.ingest` 成功写入后抛错，用于验证外层事务回滚。
class _ThrowingQuestionRepository extends QuestionRepository {
  _ThrowingQuestionRepository(super.db);

  @override
  Future<({Question question, bool created})> ingest(
    QuestionDraft draft, {
    DateTime? now,
  }) async {
    await super.ingest(draft, now: now);
    throw StateError('测试注入失败：事务应整体回滚');
  }
}
