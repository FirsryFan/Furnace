/// 应用层导出装配的测试：库里的题（题干/选项/答案/解析/配图）→ 一份 .docx 字节。
///
/// 断的是**装配完整性**，不是 OOXML 细节（那是 docx_writer_test 的事）：
/// 题目错号没有、配图有没有进 zip、缺图/坏图有没有告警、公式有没有交给编译器。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/domain/services/export/omml/omml.dart';
import 'package:furnace/domain/services/paper/paper_composer.dart';
import 'package:furnace/domain/services/paper/paper_quality_report.dart';
import 'package:furnace/domain/services/questions/question_number.dart';
import 'package:furnace/features/questions/application/paper_docx_export.dart';
import 'package:furnace/features/questions/application/question_corpus_reader.dart';
import 'package:furnace/features/questions/data/question_media_store.dart';

void main() {
  late AppDatabase db;
  late Directory support;
  late QuestionMediaStore mediaStore;
  late QuestionRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    support = Directory.systemTemp.createTempSync('furnace_paper_docx_');
    mediaStore = QuestionMediaStore(
      database: db,
      supportDirectory: () async => support,
    );
    repo = QuestionRepository(db);
  });

  tearDown(() async {
    await db.close();
    if (support.existsSync()) {
      support.deleteSync(recursive: true);
    }
  });

  /// 24 字节的 PNG 文件头（签名 + IHDR + 宽高）：`image_size.dart` 只读文件头，
  /// 不需要真的像素数据。
  Uint8List tinyPng({int width = 4, int height = 3}) {
    final builder = BytesBuilder();
    builder.add(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    builder.add(<int>[0, 0, 0, 13]);
    builder.add('IHDR'.codeUnits);
    for (final value in <int>[width, height]) {
      builder.add(<int>[
        (value >> 24) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ]);
    }
    return builder.toBytes();
  }

  PaperPlan planOf(List<String> ids) {
    return PaperPlan(
      items: <PaperItem>[
        for (var index = 0; index < ids.length; index++)
          PaperItem(
            questionId: ids[index],
            subjectKey: 'math',
            sourceLevel: 'gaokao',
            questionType: 'single_choice',
            knowledgePointId: 'kp1',
            matchedKnowledgePointIds: const <String>['kp1'],
            zone: PaperZone.danger,
            need: 1,
            quality: 0.7,
            score: 0.8,
            reasonZh: '危险区，优先补',
            improvementNote: '练完能稳定拿分',
            backgroundZh: '文化课/学科/数学',
          ),
      ],
      uncoveredKnowledgePointIds: const <String>[],
      deferredKnowledgePointIds: const <String>[],
      byKnowledgePoint: const <String, int>{'kp1': 2},
      candidateCount: 3,
      requestedCount: ids.length,
      overallNeed: 1,
      weights: const PaperWeights(),
    );
  }

  String documentXml(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final file = archive.files.firstWhere((f) => f.name == 'word/document.xml');
    return utf8.decode(file.content as List<int>);
  }

  List<String> zipNames(Uint8List bytes) => <String>[
        for (final file in ZipDecoder().decodeBytes(bytes).files) file.name,
      ];

  test('全链路：题干/题号/选项/答案/解析进卷面，配图进 zip', () async {
    final ingested = await repo.ingest(
      const QuestionDraft(
        stem: '已知函数 f(x)=x^2，求单调区间。',
        answer: 'B',
        solution: '求导后看符号。',
        subjectKey: 'math',
        sourceLevel: 'gaokao',
        sourceLabel: '2026 届高三上期末',
        year: 2026,
        region: '江苏',
        questionType: 'single_choice',
        options: <QuestionOptionDraft>[
          QuestionOptionDraft(label: 'A', content: '甲选项'),
          QuestionOptionDraft(label: 'B', content: '乙选项', isCorrect: true),
        ],
      ),
    );
    await mediaStore.save(
      questionId: ingested.question.id,
      fileName: 'stem.png',
      bytes: tinyPng(width: 40, height: 30),
    );

    final result = await buildPaperDocxExport(
      db: db,
      mediaStore: mediaStore,
      plan: planOf(<String>[ingested.question.id]),
      generatedAt: DateTime(2026, 10, 19, 5, 0),
    );

    expect(result.bytes, isNotEmpty);
    expect(result.suggestedFileName, 'furnace-paper-20261019-0500.docx');
    expect(result.report.questionCount, 1);
    expect(result.report.imageCount, 1);
    expect(result.report.formulaCount, 0);
    expect(result.imageLoadNotes, isEmpty);

    final xml = documentXml(result.bytes);
    expect(xml, contains('组卷卷面'));
    expect(xml, contains('已知函数 f(x)=x^2'));
    expect(
      xml,
      contains(formatQuestionSerial(ingested.question.serialNo!)),
    );
    expect(xml, contains('甲选项'));
    expect(xml, contains('乙选项'));
    expect(xml, contains('参考答案与解析'));
    expect(xml, contains('答案：'));
    expect(xml, contains('解析：'));
    expect(zipNames(result.bytes), contains('word/media/image1.png'));
  });

  test('题不在库里：missingQuestionCount 记一笔，卷面不静默少一道', () async {
    final result = await buildPaperDocxExport(
      db: db,
      mediaStore: mediaStore,
      plan: planOf(<String>['q-missing']),
    );

    expect(result.report.missingQuestionCount, 1);
    expect(result.report.missingQuestionLabels, hasLength(1));
    expect(result.report.hasWarnings, isTrue);
    expect(documentXml(result.bytes), contains('题库中找不到这道题'));
  });

  test('配图文件被外部删掉：不嵌但记告警', () async {
    final ingested = await repo.ingest(const QuestionDraft(stem: '带图题'));
    final image = await mediaStore.save(
      questionId: ingested.question.id,
      fileName: 'page.png',
      bytes: tinyPng(),
    );
    File(image.absolutePath).deleteSync();

    final result = await buildPaperDocxExport(
      db: db,
      mediaStore: mediaStore,
      plan: planOf(<String>[ingested.question.id]),
    );

    expect(result.report.imageCount, 0);
    expect(result.imageLoadNotes, hasLength(1));
    expect(result.imageLoadNotes.single, contains('page.png'));
    expect(result.imageLoadNotes.single, contains('文件缺失'));
    expect(result.hasWarnings, isTrue);
    expect(zipNames(result.bytes), isNot(contains('word/media/image1.png')));
  });

  test('配图字节认不出格式：不嵌但记告警', () async {
    final ingested = await repo.ingest(const QuestionDraft(stem: '坏图题'));
    await mediaStore.save(
      questionId: ingested.question.id,
      fileName: 'broken.png',
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
    );

    final result = await buildPaperDocxExport(
      db: db,
      mediaStore: mediaStore,
      plan: planOf(<String>[ingested.question.id]),
    );

    expect(result.report.imageCount, 0);
    expect(result.imageLoadNotes.single, contains('认不出图片格式'));
  });

  test('图片格式按魔数判定，不按扩展名（.jpg 里装 PNG → 媒体名 image1.png）', () async {
    final ingested = await repo.ingest(const QuestionDraft(stem: '错扩展名题'));
    await mediaStore.save(
      questionId: ingested.question.id,
      fileName: 'actually_png.jpg',
      bytes: tinyPng(),
    );

    final result = await buildPaperDocxExport(
      db: db,
      mediaStore: mediaStore,
      plan: planOf(<String>[ingested.question.id]),
    );

    expect(result.report.imageCount, 1);
    final names = zipNames(result.bytes);
    expect(names, contains('word/media/image1.png'));
    expect(names, isNot(contains('word/media/image1.jpeg')));
  });

  test('公式交给注入的编译器；编译器片段原样进 document.xml', () async {
    final ingested = await repo.ingest(
      const QuestionDraft(stem: r'求 $f(x)=x^2$ 的单调区间。'),
    );
    final calls = <String>[];

    final result = await buildPaperDocxExport(
      db: db,
      mediaStore: mediaStore,
      plan: planOf(<String>[ingested.question.id]),
      mathCompiler: (tex, {int? sizeHalfPt}) {
        calls.add(tex);
        return '<m:oMath><m:r><m:t>$tex</m:t></m:r></m:oMath>';
      },
    );

    expect(calls, <String>['f(x)=x^2']);
    expect(result.report.formulaCount, 1);
    expect(result.report.formulaFailureCount, 0);
    expect(documentXml(result.bytes), contains('<m:oMath>'));
  });

  test('不传编译器：LaTeX 原文保留，不计数', () async {
    final ingested = await repo.ingest(
      const QuestionDraft(stem: r'求 $f(x)=x^2$ 的单调区间。'),
    );
    final result = await buildPaperDocxExport(
      db: db,
      mediaStore: mediaStore,
      plan: planOf(<String>[ingested.question.id]),
    );

    expect(result.report.formulaCount, 0);
    expect(documentXml(result.bytes), contains('f(x)=x^2'));
  });

  test('空题干如实计入 missingStemCount', () async {
    await db.into(db.questions).insert(
          QuestionsCompanion.insert(
            id: 'q-empty',
            stem: '   ',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    final result = await buildPaperDocxExport(
      db: db,
      mediaStore: mediaStore,
      plan: planOf(<String>['q-empty']),
    );

    expect(result.report.missingStemCount, 1);
    expect(result.report.hasWarnings, isTrue);
  });

  test('选项按 sortOrder 排，乱序插入也按 A→B 落到卷面', () async {
    final ingested = await repo.ingest(
      const QuestionDraft(
        stem: '选项乱序题',
        options: <QuestionOptionDraft>[
          QuestionOptionDraft(label: 'B', content: '乙内容', sortOrder: 2),
          QuestionOptionDraft(label: 'A', content: '甲内容', sortOrder: 0),
        ],
      ),
    );
    final result = await buildPaperDocxExport(
      db: db,
      mediaStore: mediaStore,
      plan: planOf(<String>[ingested.question.id]),
    );
    final xml = documentXml(result.bytes);
    expect(xml.indexOf('甲内容'), lessThan(xml.indexOf('乙内容')));
  });

  test('答案/解析/理由/缺口可关：关掉后附录不出现', () async {
    final ingested = await repo.ingest(
      const QuestionDraft(stem: '关闭附录题', answer: 'B', solution: '解析内容'),
    );
    final result = await buildPaperDocxExport(
      db: db,
      mediaStore: mediaStore,
      plan: planOf(<String>[ingested.question.id]),
      includeAnswers: false,
      includeSolutions: false,
      includeReasons: false,
      includeGaps: false,
    );
    final xml = documentXml(result.bytes);
    expect(xml, isNot(contains('参考答案与解析')));
    expect(xml, isNot(contains('解析内容')));
  });

  test('空卷子：不崩、有标题、questionCount 0', () async {
    final result = await buildPaperDocxExport(
      db: db,
      mediaStore: mediaStore,
      plan: planOf(const <String>[]),
    );
    expect(result.report.questionCount, 0);
    expect(result.bytes, isNotEmpty);
    expect(documentXml(result.bytes), contains('组卷卷面'));
  });

  test('readQuestionDocxRows：给 ids 只读这些题，空题干也保留', () async {
    final first = await repo.ingest(const QuestionDraft(stem: '第一题'));
    final second = await repo.ingest(const QuestionDraft(stem: '第二题'));
    await db.into(db.questions).insert(
          QuestionsCompanion.insert(
            id: 'q-blank',
            stem: '',
            createdAt: 2,
            updatedAt: 2,
          ),
        );

    final rows = await readQuestionDocxRows(
      db,
      ids: <String>[first.question.id, 'q-blank'],
    );
    expect(rows.keys, containsAll(<String>[first.question.id, 'q-blank']));
    expect(rows.keys, isNot(contains(second.question.id)));
    expect(rows['q-blank']!.stem, '');
    expect(rows[first.question.id]!.toPaperDocxQuestion().questionId,
        first.question.id);
  });

  test('readQuestionDocxRows：ids 全空 → 空表，不扫全库', () async {
    final rows = await readQuestionDocxRows(db, ids: const <String>['  ']);
    expect(rows, isEmpty);
  });

  test('readKnowledgePointNames：只读标题非空的点', () async {
    await db.into(db.knowledgePoints).insert(
          KnowledgePointsCompanion.insert(
            id: 'kp1',
            title: ' 二次函数 ',
            content: '',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    final names = await readKnowledgePointNames(db);
    expect(names, <String, String>{'kp1': '二次函数'});
  });

  test('生产接线：传 compileLatexToOmml，公式变成原生 OMML 对象', () async {
    final ingested = await repo.ingest(
      const QuestionDraft(stem: r'求 $f(x)=\frac{x}{2}$ 在 $[0,3]$ 上的最值。'),
    );

    final result = await buildPaperDocxExport(
      db: db,
      mediaStore: mediaStore,
      plan: planOf(<String>[ingested.question.id]),
      mathCompiler: compileLatexToOmml,
    );

    expect(result.report.formulaCount, 2);
    expect(result.report.formulaFailureCount, 0);
    final xml = documentXml(result.bytes);
    expect(xml, contains('<m:oMath>'));
    expect(xml, contains('<m:f>'));
  });

  test('生产接线：编译不了的公式不崩，计入失败并保留 LaTeX 原文', () async {
    final ingested = await repo.ingest(
      const QuestionDraft(stem: r'求 $\notARealCommand{x}$ 的值。'),
    );

    final result = await buildPaperDocxExport(
      db: db,
      mediaStore: mediaStore,
      plan: planOf(<String>[ingested.question.id]),
      mathCompiler: compileLatexToOmml,
    );

    expect(result.report.formulaFailureCount, 1);
    expect(result.report.formulaFailures.single, contains('notARealCommand'));
    expect(documentXml(result.bytes), contains(r'\notARealCommand{x}'));
  });
  test('建议文件名与页脚：ASCII、可排序、按本地时间', () {
    final time = DateTime(2026, 1, 2, 3, 4);
    expect(paperDocxFileName(time), 'furnace-paper-20260102-0304.docx');
    expect(defaultPaperDocxFooter(time), 'Furnace · 2026-01-02');
  });

  group('组卷质量体检透传（轮次一百二十五）', () {
    test('不传报告：卷面没有组卷质量节（与旧版一致）', () async {
      final ingested = await repo.ingest(const QuestionDraft(stem: '没有质量节的题。'));
      final plan = planOf(<String>[ingested.question.id]);

      final result = await buildPaperDocxExport(
        db: db,
        mediaStore: mediaStore,
        plan: plan,
      );

      final xml = documentXml(result.bytes);
      expect(xml, isNot(contains('组卷质量')));
    });

    test('传报告：组卷说明末尾出现质量节（总览 + 判据）', () async {
      final ingested = await repo.ingest(const QuestionDraft(stem: '带质量节的题。'));
      final plan = planOf(<String>[ingested.question.id]);
      final quality = PaperQualityReport.build(
        plan: plan,
        subjectNames: const <String, String>{'math': '数学'},
        knowledgePointNames: const <String, String>{'kp1': '函数'},
      );

      final result = await buildPaperDocxExport(
        db: db,
        mediaStore: mediaStore,
        plan: plan,
        qualityReport: quality,
      );

      final xml = documentXml(result.bytes);
      expect(xml, contains('组卷质量'));
      expect(xml, contains('判据'));
      expect(xml, contains('卷面'));
      expect(
        xml,
        contains('填充率'),
        reason: '质量节总览应带填充率，证明报告真的透传到了纯逻辑层',
      );
    });
  });
}
