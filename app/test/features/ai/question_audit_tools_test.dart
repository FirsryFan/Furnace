/// 题库体检 AI 工具：只读、只报不改，参数校验与摘要口径。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/questions/question_intake_audit.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/tools/question_audit_tools.dart';

void main() {
  late AppDatabase db;
  late AuditQuestionIntakeTool tool;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tool = AuditQuestionIntakeTool(
      db: db,
      clock: () => DateTime(2026, 5, 1),
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// 直接落一行题：绕开仓储的「题干非空」校验，用来造体检要抓的脏数据。
  Future<void> rawQuestion({
    required String id,
    String stem = '干净题干：下列说法正确的是哪一个？',
    String? answer = 'A',
    String? solution = '因为 A 项符合题意。',
    String subjectKey = 'math',
    String questionType = 'solution',
    String sourceLevel = 'unknown',
    int? serialNo = 1,
    int? year,
    double? difficulty,
    double? aiQuality,
  }) async {
    await db.into(db.questions).insert(
          QuestionsCompanion.insert(
            id: id,
            stem: stem,
            createdAt: 1,
            updatedAt: 1,
            answer: Value(answer),
            solution: Value(solution),
            subjectKey: Value(subjectKey),
            questionType: Value(questionType),
            sourceLevel: Value(sourceLevel),
            serialNo: Value(serialNo),
            year: Value(year),
            difficulty: Value(difficulty),
            aiQuality: Value(aiQuality),
          ),
        );
  }

  /// 同一标签既挂题目、又挂知识点，体检才认为这道题挂了知识点。
  Future<void> linkKnowledgePoint(String questionId, String tagId) async {
    for (final entry in <List<String>>[
      <String>['question', questionId],
      <String>['knowledge_point', 'kp-$tagId'],
    ]) {
      await db.into(db.objectTags).insert(
            ObjectTagsCompanion.insert(
              id: 'ot-${entry[0]}-${entry[1]}',
              tagId: tagId,
              objectType: entry[0],
              objectId: entry[1],
              createdAt: 1,
            ),
          );
    }
  }

  ToolInvocation call(Map<String, Object?> arguments) => ToolInvocation(
        toolName: tool.name,
        action: tool.name,
        arguments: arguments,
      );

  Map<String, Object?> mapOf(ToolResult result) =>
      result.modelResult! as Map<String, Object?>;

  List<Map<String, Object?>> findingsOf(ToolResult result) =>
      (mapOf(result)['findings']! as List).cast<Map<String, Object?>>();

  Map<String, Object?> summaryOf(ToolResult result) =>
      (mapOf(result)['summary']! as Map).cast<String, Object?>();

  List<Map<String, Object?>> offendersOf(ToolResult result) =>
      (summaryOf(result)['top_offenders']! as List)
          .cast<Map<String, Object?>>();

  test('空库：不抛、报告干净、摘要如实说没题目', () async {
    final result = await tool.run(call(const <String, Object?>{}));

    expect(result.ok, isTrue);
    final report = mapOf(result);
    expect(report['questions_checked'], 0);
    expect(report['findings_total'], 0);
    expect(report['is_clean'], isTrue);
    expect(findingsOf(result), isEmpty);
    expect(result.summary, contains('还没有题目'));
  });

  test('干净题：挂了知识点、有答案解析与编号 → 一条结论都没有', () async {
    await rawQuestion(id: 'q-clean', serialNo: 1);
    await linkKnowledgePoint('q-clean', 't-clean');

    final result = await tool.run(call(const <String, Object?>{}));

    final report = mapOf(result);
    expect(report['questions_checked'], 1);
    expect(report['findings_total'], 0, reason: '干净题不该被任何判据命中');
    expect(report['is_clean'], isTrue);
    expect(result.summary, contains('没发现硬伤'));
  });

  test('脏数据：H1/H2 命中并按 (code, severity) 计数', () async {
    await rawQuestion(
      id: 'q-empty',
      stem: '',
      answer: null,
      solution: null,
      serialNo: 1,
    );
    await rawQuestion(
      id: 'q-figure',
      stem: '如图，求图中阴影部分面积。',
      answer: null,
      solution: null,
      serialNo: 2,
    );

    final result = await tool.run(call(const <String, Object?>{}));

    final report = mapOf(result);
    expect(report['questions_checked'], 2);
    final total = report['findings_total']! as int;
    expect(total, greaterThanOrEqualTo(2));
    final counts = (report['counts']! as Map).cast<String, int>();
    expect(counts['error'], greaterThanOrEqualTo(1));
    expect(counts['warning'], greaterThanOrEqualTo(2));

    final byCode = (report['by_code']! as List).cast<Map<String, Object?>>();
    final codes = byCode.map((entry) => entry['code']).toSet();
    expect(codes, contains(QuestionAuditCodes.h1StemEmpty));
    expect(codes, contains(QuestionAuditCodes.h1FigureMissing));
    expect(codes, contains(QuestionAuditCodes.h2AnswerMissing));
    // by_code 的计数之和 == findings_total（同一份结论的两种切法）。
    final sum =
        byCode.fold<int>(0, (acc, entry) => acc + (entry['count']! as int));
    expect(sum, total);
    expect(result.summary, contains('个错误'));
    expect(result.summary, contains('只报不改'));
  });

  test('severity 过滤：findings 只剩该严重度，counts 仍是全量', () async {
    await rawQuestion(id: 'q-empty', stem: '', answer: null, solution: null);
    await rawQuestion(id: 'q-figure', stem: '如图，求面积。');

    final result =
        await tool.run(call(const <String, Object?>{'severity': 'error'}));

    final report = mapOf(result);
    final findings = findingsOf(result);
    expect(findings, isNotEmpty);
    expect(findings.every((row) => row['severity'] == 'error'), isTrue);
    expect(report['findings_total'], findings.length);
    final counts = (report['counts']! as Map).cast<String, int>();
    expect(counts['error'], findings.length);
    expect(counts['warning'], greaterThan(0), reason: 'counts 是全量计数，不随过滤变');
    expect(result.summary, contains('严重度 error'));
  });

  test('subject_key 过滤：只体检该学科，计数也只看该学科', () async {
    await rawQuestion(
        id: 'q-math',
        stem: '',
        answer: null,
        solution: null,
        subjectKey: 'math');
    await rawQuestion(
        id: 'q-physics',
        stem: '',
        answer: null,
        solution: null,
        subjectKey: 'physics');

    final result =
        await tool.run(call(const <String, Object?>{'subject_key': 'PHYSICS'}));

    final report = mapOf(result);
    expect(report['questions_checked'], 1);
    final findings = findingsOf(result);
    expect(findings.map((row) => row['question_id']).toSet(),
        <String>{'q-physics'});

    final summary = summaryOf(result);
    expect(summary['question_count'], 1, reason: 'summary 只统计学科过滤后的范围');
    expect(summary['dirty_question_count'], 1);
    expect(offendersOf(result).single['question_id'], 'q-physics');
  });

  test('limit 截断：findings 只给前 limit 条，truncated 如实报', () async {
    for (var i = 0; i < 5; i++) {
      await rawQuestion(
        id: 'q-dirty-$i',
        stem: '',
        answer: null,
        solution: null,
        serialNo: i + 1,
      );
    }

    final result = await tool.run(call(const <String, Object?>{'limit': 2}));

    final report = mapOf(result);
    expect(findingsOf(result), hasLength(2));
    expect(report['findings_total']! as int, greaterThan(2));
    expect(report['truncated'], isTrue);
    expect(result.summary, contains('这里列出前 2 条'));
  });

  test('limit 超过上限按 100 钳制，不报错', () async {
    final result = await tool.run(call(const <String, Object?>{'limit': 500}));
    expect((mapOf(result)['limit']! as int), 100);
  });

  test('非法参数：未知 severity / limit<=0 都抛 ToolArgError', () async {
    await expectLater(
      tool.run(call(const <String, Object?>{'severity': 'fatal'})),
      throwsA(isA<ToolArgError>().having(
        (error) => error.message,
        'message',
        contains('未知的 severity'),
      )),
    );
    await expectLater(
      tool.run(call(const <String, Object?>{'limit': 0})),
      throwsA(isA<ToolArgError>().having(
        (error) => error.message,
        'message',
        contains('limit 必须是正整数'),
      )),
    );
  });

  test('工具声明：名称稳定、只读、无平台差异、schema 三个参数', () async {
    expect(tool.name, 'audit_question_intake');
    expect(tool.readOnly, isTrue);
    expect(tool.availableOnCurrentPlatform, isTrue);
    expect(tool.reversibleFor(tool.name), isTrue);
    final schema = tool.parameters;
    expect(schema['type'], 'object');
    final properties = (schema['properties']! as Map).cast<String, Object?>();
    expect(properties.keys,
        containsAll(<String>['severity', 'subject_key', 'limit']));
  });

  test('只读：跑完题库行数不变', () async {
    await rawQuestion(id: 'q1', stem: '');
    final before = await db.select(db.questions).get();
    await tool.run(call(const <String, Object?>{}));
    final after = await db.select(db.questions).get();
    expect(after.length, before.length);
  });
  test('summary：题数、干净比例、top_offenders 优先级分数与 toJson 键序', () async {
    await rawQuestion(
      id: 'q-clean-a',
      stem: '干净题干甲：下列说法正确的是哪一个？',
      serialNo: 1,
    );
    await linkKnowledgePoint('q-clean-a', 't-clean-a');
    await rawQuestion(
      id: 'q-clean-b',
      stem: '干净题干乙：下列说法正确的是哪一个？',
      serialNo: 2,
    );
    await linkKnowledgePoint('q-clean-b', 't-clean-b');
    await rawQuestion(id: 'q-dirty', stem: '', serialNo: 3);

    final result = await tool.run(call(const <String, Object?>{}));
    final summary = summaryOf(result);

    expect(
      summary.keys.toList(),
      <String>[
        'question_count',
        'clean_question_count',
        'dirty_question_count',
        'clean_ratio',
        'findings_by_severity',
        'code_counts',
        'top_offenders',
        'truncated_offender_count',
        'is_empty',
        'is_clean',
      ],
    );
    expect(summary['question_count'], 3);
    expect(summary['clean_question_count'], 2);
    expect(summary['dirty_question_count'], 1);
    expect((summary['clean_ratio']! as num).toDouble(), closeTo(2 / 3, 1e-6));
    expect(summary['is_empty'], isFalse);
    expect(summary['is_clean'], isFalse);
    final bySeverity =
        (summary['findings_by_severity']! as Map).cast<String, int>();
    expect(bySeverity['error'], greaterThanOrEqualTo(1));

    final offenders = offendersOf(result);
    expect(offenders, hasLength(1));
    final offender = offenders.single;
    expect(offender['question_id'], 'q-dirty');
    final errors = offender['error_count']! as int;
    final warnings = offender['warning_count']! as int;
    final infos = offender['info_count']! as int;
    expect(offender['priority_score'], errors * 10 + warnings * 3 + infos * 1,
        reason: '优先级分数 = 错误*10 + 警告*3 + 提示*1（未标定，仅相对排序）');
    expect((offender['codes']! as List), isNotEmpty);

    expect(mapOf(result)['priority_note'], contains('未标定'));
    expect(result.summary, contains('干净题 2 道（67%）'));
    expect(result.summary, contains('优先修：TR-00003'));
    expect(result.summary, contains('只报不改'));
  });

  test('summary：severity 过滤后只统计过滤范围', () async {
    await rawQuestion(id: 'q-error', stem: '', serialNo: 1);
    await rawQuestion(
      id: 'q-warning',
      stem: '如图，求图中阴影部分面积。',
      serialNo: 2,
    );
    await linkKnowledgePoint('q-warning', 't-warning');

    final result =
        await tool.run(call(const <String, Object?>{'severity': 'error'}));
    final summary = summaryOf(result);

    expect(summary['question_count'], 2);
    expect(summary['clean_question_count'], 1,
        reason: '只有 warning 的题在 error 范围内算干净');
    final bySeverity =
        (summary['findings_by_severity']! as Map).cast<String, int>();
    expect(bySeverity['error'], findingsOf(result).length);
    expect(bySeverity['warning'], 0);
    expect(bySeverity['info'], 0);
    final codeCounts =
        (summary['code_counts']! as List).cast<Map<String, Object?>>();
    expect(codeCounts.every((entry) => entry['severity'] == 'error'), isTrue);
    expect(
      offendersOf(result).map((entry) => entry['question_id']),
      <String>['q-error'],
    );
  });

  test('summary：空库返回空报告且比例记 0', () async {
    final result = await tool.run(call(const <String, Object?>{}));
    final summary = summaryOf(result);

    expect(summary['question_count'], 0);
    expect(summary['clean_question_count'], 0);
    expect(summary['truncated_offender_count'], 0);
    expect((summary['clean_ratio']! as num).toDouble(), 0);
    expect(summary['top_offenders'], isEmpty);
    expect(summary['is_empty'], isTrue);
    expect(summary['is_clean'], isTrue);
    expect(result.summary, contains('还没有题目'));
  });

  test('summary：全干净库 clean_ratio=1、摘要带 100%', () async {
    await rawQuestion(
      id: 'q-a',
      stem: '干净题干甲：下列说法正确的是哪一个？',
      serialNo: 1,
    );
    await linkKnowledgePoint('q-a', 't-a');
    await rawQuestion(
      id: 'q-b',
      stem: '干净题干乙：下列说法正确的是哪一个？',
      serialNo: 2,
    );
    await linkKnowledgePoint('q-b', 't-b');

    final result = await tool.run(call(const <String, Object?>{}));
    final summary = summaryOf(result);

    expect(summary['question_count'], 2);
    expect(summary['clean_question_count'], 2);
    expect(summary['dirty_question_count'], 0);
    expect((summary['clean_ratio']! as num).toDouble(), 1);
    expect(summary['top_offenders'], isEmpty);
    expect(summary['is_clean'], isTrue);
    expect(result.summary, contains('干净题 2 道（100%）'));
  });

  test('summary：top_offenders 按优先级排序并截断到 10 道', () async {
    for (var i = 0; i < 3; i++) {
      await rawQuestion(id: 'q-error-$i', stem: '', serialNo: i + 1);
    }
    for (var i = 0; i < 9; i++) {
      final id = 'q-warn-$i';
      await rawQuestion(
        id: id,
        stem: '如图，第 $i 个图形中阴影部分面积是多少。',
        serialNo: i + 4,
      );
      await linkKnowledgePoint(id, 't-warn-$i');
    }

    final result = await tool.run(call(const <String, Object?>{'limit': 1}));
    final summary = summaryOf(result);
    final offenders = offendersOf(result);

    expect(summary['dirty_question_count'], 12);
    expect(offenders, hasLength(10));
    expect(summary['truncated_offender_count'], 2);
    expect(
      offenders.map((entry) => entry['question_id']).toList(),
      <String>[
        'q-error-0',
        'q-error-1',
        'q-error-2',
        'q-warn-0',
        'q-warn-1',
        'q-warn-2',
        'q-warn-3',
        'q-warn-4',
        'q-warn-5',
        'q-warn-6',
      ],
    );
  });
}
