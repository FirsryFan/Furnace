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
}
