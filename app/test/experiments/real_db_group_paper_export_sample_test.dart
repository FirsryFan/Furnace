/// 真实题库样例：语文「材料 + 5 小问」题组的卷面导出（人工验收用，不是单测）。
///
/// 目的：用 `E:\Furnace\data\furnace.db` 里真实存在的语文题组（S1-M1「种植入门
/// 问答」，serialNo 708–712）导出一份 docx，证明：
/// * 卷面题数 = 1（按题组计）；
/// * 材料只出现一次；
/// * 5 个小问按（1）–（5）连续排进卷面；
/// * 答案区仍是题号 + 答案（小问只加（i）标号）。
///
/// 运行：
/// ```
/// flutter test test/experiments/real_db_group_paper_export_sample_test.dart
/// ```
/// 产物目录可用 `FURNACE_GROUP_SAMPLE_OUT` 覆盖（默认写到打印工作区的样例目录）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/paper/paper_composer.dart';
import 'package:furnace/features/questions/application/paper_docx_export.dart';
import 'package:furnace/features/questions/application/question_corpus_reader.dart';
import 'package:furnace/features/questions/data/question_media_store.dart';

void main() {
  test('real db: 语文题组（材料 + 5 小问）导出卷面并写证据 JSON', () async {
    final dbFile = File(r'E:\Furnace\data\furnace.db');
    if (!dbFile.existsSync()) {
      // 没有真实库就跳过（CI/别的机器上不失败），但不静默当通过。
      // ignore: avoid_print
      print('SKIP: real db not found at ${dbFile.path}');
      return;
    }
    final outDir = Directory(
      Platform.environment['FURNACE_GROUP_SAMPLE_OUT'] ??
          r'E:\Workspaces\agent-control\10-projects\agent-control-plane\full-generation\print\SAMPLE-GROUP-2026-11-18',
    );
    outDir.createSync(recursive: true);
    final work = Directory.systemTemp.createTempSync('furnace_group_sample_');
    final copy = dbFile.copySync('${work.path}/furnace.db');
    final db = AppDatabase.forTesting(NativeDatabase(copy));
    final mediaStore = QuestionMediaStore(
      database: db,
      supportDirectory: () async => work,
    );
    addTearDown(() async {
      await db.close();
      if (work.existsSync()) work.deleteSync(recursive: true);
    });

    final corpus = await readPaperCorpus(db);
    final groups = corpus.candidates
        .where((candidate) => candidate.groupQuestionIds.length > 1)
        .toList();
    expect(groups, isNotEmpty, reason: '真实库里应有题组（2026-11-18 实测 6 组）');

    // 选「种植入门问答」的 5 小问组：材料开头固定，可机械认。
    final stemsById = await readQuestionStems(
      db,
      ids: <String>{
        for (final group in groups) ...group.groupQuestionIds,
      },
    );
    PaperCandidate? picked;
    for (final group in groups) {
      final firstStem = stemsById[group.groupQuestionIds.first] ?? '';
      if (group.groupQuestionIds.length == 5 && firstStem.contains('种植入门问答')) {
        picked = group;
        break;
      }
    }
    expect(picked != null, isTrue, reason: '没找到「种植入门问答」5 小问组');
    final candidate = picked!;

    final plan = PaperComposer.compose(
      candidates: <PaperCandidate>[candidate],
      spec: const PaperSpec(targetCount: 1),
    );
    expect(plan.items.length, 1, reason: '题目数按题组计：1 道');
    expect(plan.items.single.groupQuestionIds.length, 5);

    final result = await buildPaperDocxExport(
      db: db,
      mediaStore: mediaStore,
      plan: plan,
      generatedAt: DateTime(2026, 11, 18, 6, 40),
      title: '组卷卷面 · 语文题组样例',
      subtitle: '材料 + 5 小问 = 1 道题（题数按题组计）',
    );
    expect(result.report.questionCount, 1);
    expect(result.report.expandedGroupCount, 1);
    expect(result.report.expandedSubQuestionCount, 5);

    final docxPath = '${outDir.path}/paper-group-chinese.docx';
    File(docxPath).writeAsBytesSync(result.bytes);

    final archive = ZipDecoder().decodeBytes(result.bytes);
    final documentFile =
        archive.files.firstWhere((file) => file.name == 'word/document.xml');
    final xml = utf8.decode(documentFile.content as List<int>);

    final memberQuestions = <String>[
      for (final id in candidate.groupQuestionIds) stemsById[id] ?? '',
    ];
    int countOf(String text, String needle) {
      var count = 0;
      var index = text.indexOf(needle);
      while (index >= 0) {
        count++;
        index = text.indexOf(needle, index + needle.length);
      }
      return count;
    }

    // 每个小问的题干（去掉材料与【题目】分隔）都应在卷面出现；材料只出现 1 次。
    final subQuestionStems = <String>[];
    final subQuestionAnswers = <String>[];
    final serials = <String>[];
    for (final id in candidate.groupQuestionIds) {
      final row = await (db.select(db.questions)..where((t) => t.id.equals(id)))
          .getSingle();
      serials.add(row.serialNo?.toString() ?? '');
      subQuestionAnswers.add(row.answer ?? '');
      final stem = (stemsById[id] ?? '').trim();
      final marker = RegExp(r'\n[ \t]*【题目】[ \t]*\n').firstMatch(stem);
      subQuestionStems.add(
        marker == null ? stem : stem.substring(marker.end).trim(),
      );
    }

    final evidence = <String, Object?>{
      'generated_at': '2026-11-18T06:40:00+08:00',
      'db': dbFile.path,
      'group_representative_id': candidate.questionId,
      'group_serials': serials,
      'group_size': candidate.groupQuestionIds.length,
      'plan_item_count': plan.items.length,
      'report_question_count': result.report.questionCount,
      'report_expanded_group_count': result.report.expandedGroupCount,
      'report_expanded_sub_question_count':
          result.report.expandedSubQuestionCount,
      'material_occurrences_in_docx_xml': countOf(xml, '种植入门问答'),
      'sub_question_texts': subQuestionStems,
      'sub_question_answers': subQuestionAnswers,
      'sub_question_occurrences': <String, int>{
        for (var index = 0; index < subQuestionStems.length; index++)
          '（${index + 1}）': countOf(xml, '（${index + 1}）'),
      },
      'sub_question_all_present': <bool>[
        for (final text in subQuestionStems) xml.contains(text),
      ],
      'docx_path': docxPath,
      'docx_bytes': result.bytes.length,
      'image_load_notes': result.imageLoadNotes,
      'export_warnings': result.hasWarnings,
    };
    File('${outDir.path}/paper-group-chinese-evidence.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(evidence));
    // ignore: avoid_print
    print('SAMPLE docx: $docxPath');
    // ignore: avoid_print
    print('SAMPLE evidence: ${outDir.path}/paper-group-chinese-evidence.json');
  });
}
