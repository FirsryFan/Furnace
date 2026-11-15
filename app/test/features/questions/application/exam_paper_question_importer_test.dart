import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/content_ref_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/domain/services/content/content_ref_vocab.dart';
import 'package:furnace/features/questions/application/exam_paper_question_importer.dart';
import 'package:furnace/features/questions/data/question_media_store.dart';

/// `ExamPaperQuestionImporter` 的规则单测（task-87，2026-11-15）。
///
/// 全部用 `NativeDatabase.memory()` + 临时目录，**不碰用户真实库**。真实数学卷
/// 19 题的冒烟在 `test/experiments/exam_paper_import_real_math_test.dart`。
///
/// 锁住的行为（每条能单独失败）：
///  * 字段映射：题干/选项/答案/解析/分值/来源/年份/地区/学科/图 → 产品表；
///  * 客观题选项 `is_correct` 由答案字母推出；主观题答案/解析逐字写；
///  * `content_refs.content_id = '<paperKey>#Q<number>'`，metadata 只放摘要；
///  * 幂等：同 content_id 二次导入不新建题/选项/配图；
///  * 缺分值：`scoring.points = null`，`score_source` 照记，不采用推断分值；
///  * 图：题干图落 role=stem 并把正文引用换成「［图N］」，解析图落 role=answer；
///    图缺失/题干图引用对不上/公式未转换 → 该题 blocked，不裸导入；
///  * 不建知识点/标签/能力点；AI 初标记为跳过；
///  * 事务：图落盘中途抛错 → 整卷回滚，题/引用/附件都不留。
void main() {
  late Directory workDir;
  late Directory supportDir;
  late AppDatabase db;
  late QuestionRepository questions;
  late ContentRefRepository contentRefs;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('exam_paper_import_test_');
    supportDir = Directory.systemTemp.createTempSync('exam_paper_media_test_');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    questions = QuestionRepository(db);
    contentRefs = ContentRefRepository(db);
  });

  tearDown(() async {
    await db.close();
    if (workDir.existsSync()) {
      workDir.deleteSync(recursive: true);
    }
    if (supportDir.existsSync()) {
      supportDir.deleteSync(recursive: true);
    }
  });

  QuestionMediaStore newMediaStore() => QuestionMediaStore(
        database: db,
        supportDirectory: () async => supportDir,
      );

  ExamPaperQuestionImporter newImporter({
    QuestionMediaStore? mediaStore,
    DateTime? now,
  }) =>
      ExamPaperQuestionImporter(
        db,
        questions: questions,
        contentRefs: contentRefs,
        mediaStore: mediaStore,
        now: now ?? DateTime.utc(2026, 11, 15, 12),
      );

  /// 在临时卷目录里放一张假 PNG（导入器只复制字节，不解码）。
  String writeFigure(String relativePath) {
    final file = File('${workDir.path}/$relativePath');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(_fakePng);
    return relativePath;
  }

  // -------------------------------------------------------------------------
  // 1. 完整字段映射
  // -------------------------------------------------------------------------

  test('导入一道选择题：题干/选项/答案/答案正确项/解析/分值/来源/图/引用全部落库',
      () async {
    final figurePath = writeFigure('images/q1.png');
    final paper = ExamPaperDocument.fromJson(
      _paperJson(<Map<String, Object?>>[
        _choiceQuestion(
          1,
          stem: '1．已知函数\$f(x)=x^2\$，则\$f(2)\$的值为（   ）\n\n'
              '![Source 图 q1.png]($figurePath)',
          options: const <Map<String, Object?>>[
            <String, Object?>{'label': 'A', 'text': r'$1$'},
            <String, Object?>{'label': 'B', 'text': r'$2$'},
            <String, Object?>{'label': 'C', 'text': r'$4$'},
            <String, Object?>{'label': 'D', 'text': r'$8$'},
          ],
          answer: <String, Object?>{
            'direct': 'C',
            'summary_md': '1．C',
            'source': 'answer_docx',
          },
          analysis: <String, Object?>{
            'source': 'answer_docx',
            'groups': <Map<String, Object?>>[
              <String, Object?>{'label': '知识点', 'text': '【知识点】函数求值'},
              <String, Object?>{
                'label': '详解',
                'text': '【详解】把\$x=2\$代入得\$4\$，故选：C.',
              },
            ],
          },
          images: <Map<String, Object?>>[
            <String, Object?>{'saved_as': figurePath, 'sha256': 'abc123'},
          ],
          knowledgePoints: const <String>['函数求值'],
        ),
      ]),
      directoryPath: workDir.path,
    );
    final result = await newImporter(mediaStore: newMediaStore())
        .importPaper(paper);

    expect(result.status, ExamPaperImportStatus.importedWithSkips);
    expect(result.questionCount, 1);
    expect(result.createdCount, 1);
    expect(result.reusedCount, 0);
    expect(result.blockedCount, 0);
    expect(result.optionCount, 4);
    expect(result.figureCount, 1);
    expect(result.figuresImported, 1);
    expect(result.scoreSumFromQuestions, 5);
    expect(result.scoreTotalStated, 150, reason: '卷面总分原样报告');
    expect(result.subjectKey, 'math');
    expect(result.year, 2025);
    expect(result.region, 'national1');
    expect(result.sourceLevel, 'gaokao');
    expect(result.sourceLevelBasis, isNotEmpty);
    expect(result.questions.single.score, 5);
    expect(result.questions.single.scoreSource, 'test_template');

    final question = (await questions.byId(
      result.questions.single.questionId,
    ))!;
    expect(question.serialNo, 1);
    expect(question.stem, contains('［图1］'));
    expect(question.stem, isNot(contains('images/q1.png')));
    expect(question.stem, contains(r'$f(x)=x^2$'));
    expect(question.answer, 'C');
    expect(question.solution, contains('【知识点】函数求值'));
    expect(question.solution, contains('故选：C'));
    expect(question.subjectKey, 'math');
    expect(question.questionType, 'single_choice');
    expect(question.sourceLevel, 'gaokao');
    expect(question.sourceLabel, contains('普通高等学校招生全国统一考试'));
    expect(question.year, 2025);
    expect(question.region, 'national1');
    expect(question.textFormat, 'markdown');
    expect(question.origin, 'exam_paper');
    expect(question.state, 'structured');
    expect(question.capability, isNull, reason: '不写 AI 能力点');
    expect(question.difficulty, isNull, reason: '不写 AI 难度');

    final options = await questions.optionsOf(question.id);
    expect(options.map((option) => option.label).toList(), <String>['A', 'B', 'C', 'D']);
    expect(options.singleWhere((option) => option.label == 'C').isCorrect, isTrue);
    expect(
      options.where((option) => option.isCorrect).map((option) => option.label),
      <String>['C'],
    );

    // 图：attachments 一行 role=stem，字节真的落盘。
    final stemImages =
        await newMediaStore().list(question.id, role: QuestionImageRole.stem);
    expect(stemImages, hasLength(1));
    expect(stemImages.single.fileName, 'q1.png');
    expect(File(stemImages.single.absolutePath).existsSync(), isTrue);

    // 引用：content_id = <paperKey>#Q<number>，metadata 只有摘要。
    final ref = await contentRefs.findOne(
      contentId: 'test-paper#Q1',
      objectType: ContentObjectType.question,
      objectId: question.id,
      role: ContentRefRole.sourcePackage,
    );
    expect(ref, isNotNull);
    expect(ref!.subject, 'math');
    final metadata = jsonDecode(ref.metadataJson!) as Map<String, Object?>;
    expect(metadata['paper_id'], 'test-paper');
    expect(metadata['question_number'], 1);
    expect(
      metadata['scoring'],
      <String, Object?>{
        'points': 5,
        'source': 'test_template',
        'confirmed_in_source': false,
      },
    );
    expect(metadata['source_level'], 'gaokao');
    expect((metadata['figures'] as List).single, containsPair('role', 'stem'));
    expect(ref.metadataJson, isNot(contains('f(x)=x^2')));
    expect(ref.metadataJson, isNot(contains('故选')));

    // 不伪造知识点/标签。
    final kpCount = await _count(db, 'knowledge_points');
    final tagCount = await _count(db, 'tags');
    final objectTagCount = await _count(db, 'object_tags');
    expect(kpCount, 0);
    expect(tagCount, 0);
    expect(objectTagCount, 0);

    // AI 初标与显式知识点只记跳过。
    expect(
      result.skipped.map((issue) => issue.code),
      containsAll(<String>[
        ExamPaperSkipReason.aiLabelsIgnored,
        ExamPaperSkipReason.knowledgePointsNotImported,
      ]),
    );
  });

  test('多选题答案 BD：选项 B、D 标正确；填空题没有选项', () async {
    final paper = ExamPaperDocument.fromJson(
      _paperJson(<Map<String, Object?>>[
        _choiceQuestion(
          9,
          type: 'multiple_choice',
          options: const <Map<String, Object?>>[
            <String, Object?>{'label': 'A', 'text': '甲'},
            <String, Object?>{'label': 'B', 'text': '乙'},
            <String, Object?>{'label': 'C', 'text': '丙'},
            <String, Object?>{'label': 'D', 'text': '丁'},
          ],
          answer: <String, Object?>{'summary_md': '9．BD'},
          analysis: const <String, Object?>{
            'groups': <Map<String, Object?>>[
              <String, Object?>{'text': '【详解】B、D 正确.'},
            ],
          },
        ),
        _choiceQuestion(
          12,
          type: 'fill_in',
          stem: r'12．若$a=2$，则$b=\underline{\quad}$．',
          options: const <Map<String, Object?>>[],
          answer: <String, Object?>{'summary_md': r'12．$4$'},
          analysis: const <String, Object?>{
            'groups': <Map<String, Object?>>[
              <String, Object?>{'text': '【详解】答案为\$4\$.'},
            ],
          },
        ),
      ]),
      directoryPath: workDir.path,
    );
    final result = await newImporter(mediaStore: newMediaStore())
        .importPaper(paper);
    expect(result.status, ExamPaperImportStatus.importedWithSkips);
    expect(result.questionCount, 2);

    final multi = (await questions.byId(result.questions[0].questionId))!;
    final multiOptions = await questions.optionsOf(multi.id);
    expect(
      multiOptions.where((option) => option.isCorrect).map((o) => o.label),
      <String>['B', 'D'],
    );
    expect(multi.answer, 'BD');

    final fill = (await questions.byId(result.questions[1].questionId))!;
    expect(fill.questionType, 'fill_in');
    expect(fill.answer, r'$4$');
    expect(await questions.optionsOf(fill.id), isEmpty);
  });

  test('解析图（role=answer）落盘，答案/解析正文里的图引用被去掉', () async {
    final answerFigure = writeFigure('images/a1.png');
    final paper = ExamPaperDocument.fromJson(
      _paperJson(<Map<String, Object?>>[
        _choiceQuestion(
          7,
          stem: '7．题干（   ）',
          answer: const <String, Object?>{'summary_md': '7．B'},
          analysis: <String, Object?>{
            'groups': <Map<String, Object?>>[
              <String, Object?>{
                'text': '【详解】如图\n\n![Source 图 a1.png]($answerFigure)\n\n故选：B.',
              },
              <String, Object?>{
                'text': '【分析】[IMG:image10.png]\$x=1\$',
              },
            ],
            'images': <Map<String, Object?>>[
              <String, Object?>{'saved_as': answerFigure, 'sha256': 'def456'},
            ],
          },
        ),
      ]),
      directoryPath: workDir.path,
    );
    final result = await newImporter(mediaStore: newMediaStore())
        .importPaper(paper);
    expect(result.questionCount, 1);
    expect(result.figuresImported, 1);
    final question = (await questions.byId(
      result.questions.single.questionId,
    ))!;
    expect(question.solution, isNot(contains('![')));
    expect(question.solution, isNot(contains('[IMG:')));
    expect(question.solution, contains('故选：B'));

    final store = newMediaStore();
    final answerImages =
        await store.list(question.id, role: QuestionImageRole.answer);
    expect(answerImages, hasLength(1));
    expect(File(answerImages.single.absolutePath).existsSync(), isTrue);
    expect(
      result.skipped.map((issue) => issue.code),
      contains(ExamPaperSkipReason.figureReferenceRemovedFromText),
    );
  });

  // -------------------------------------------------------------------------
  // 2. 幂等
  // -------------------------------------------------------------------------

  test('二次导入同一卷：不新建题/选项/配图，复用 content_id 引用', () async {
    final figurePath = writeFigure('images/q1.png');
    final paper = ExamPaperDocument.fromJson(
      _paperJson(<Map<String, Object?>>[
        _choiceQuestion(
          1,
          stem: '1．如图 ![x]($figurePath) ，求值（   ）',
          answer: const <String, Object?>{'summary_md': '1．A'},
          analysis: const <String, Object?>{
            'groups': <Map<String, Object?>>[
              <String, Object?>{'text': '【详解】选 A.'},
            ],
          },
          images: <Map<String, Object?>>[
            <String, Object?>{'saved_as': figurePath},
          ],
        ),
      ]),
      directoryPath: workDir.path,
    );
    final importer = newImporter(mediaStore: newMediaStore());
    final first = await importer.importPaper(paper);
    expect(first.createdCount, 1);

    final second = await importer.importPaper(paper);
    expect(second.createdCount, 0);
    expect(second.reusedCount, 1);
    expect(second.optionCount, 4);
    expect(second.figuresImported, 0);

    expect(await _count(db, 'questions'), 1);
    expect(await _count(db, 'question_options'), 4);
    expect(await _count(db, 'content_refs'), 1);
    expect(await _count(db, 'attachments'), 1, reason: '配图不翻倍');
    expect(second.contentRefCount, 1);

    final refs = await contentRefs.listByContentId('test-paper#Q1');
    expect(refs, hasLength(1));
  });

  // -------------------------------------------------------------------------
  // 3. 分值：缺分值/推断分值都不伪造
  // -------------------------------------------------------------------------

  test('缺分值：scoring.points 为 null，score_source 照记，不采用 score_inferred', () async {
    final paper = ExamPaperDocument.fromJson(
      _paperJson(<Map<String, Object?>>[
        _choiceQuestion(
          1,
          score: null,
          scoreSource: 'not_stated_in_source',
          scoreInferred: 5,
          answer: const <String, Object?>{'summary_md': '1．A'},
          analysis: const <String, Object?>{
            'groups': <Map<String, Object?>>[
              <String, Object?>{'text': '【详解】选 A.'},
            ],
          },
        ),
      ]),
      directoryPath: workDir.path,
    );
    final result = await newImporter(mediaStore: newMediaStore())
        .importPaper(paper);
    expect(result.questionCount, 1);
    expect(result.questions.single.score, isNull);
    expect(result.scoreSumFromQuestions, 0);

    final metadata = await _questionMetadata(db, 'test-paper#Q1');
    expect(
      metadata['scoring'],
      <String, Object?>{
        'points': null,
        'source': 'not_stated_in_source',
        'confirmed_in_source': false,
      },
      reason: '分值缺失写 null，不写推断的 5',
    );
    final codes = result.skipped.map((issue) => issue.code).toSet();
    expect(codes, contains(ExamPaperSkipReason.scoreMissing));
    expect(codes, contains(ExamPaperSkipReason.scoreInferredNotUsed));
  });

  // -------------------------------------------------------------------------
  // 4. 图缺失 / 公式未转换 / 引用对不上 → blocked
  // -------------------------------------------------------------------------

  test('题干图文件缺失：该题 blocked，不写题/引用/附件', () async {
    final paper = ExamPaperDocument.fromJson(
      _paperJson(<Map<String, Object?>>[
        _choiceQuestion(
          1,
          stem: '1．如图，求值（   ）\n\n![Source 图 missing.png](images/missing.png)',
          answer: const <String, Object?>{'summary_md': '1．A'},
          images: const <Map<String, Object?>>[
            <String, Object?>{'saved_as': 'images/missing.png'},
          ],
        ),
      ]),
      directoryPath: workDir.path,
    );
    final result = await newImporter(mediaStore: newMediaStore())
        .importPaper(paper);
    expect(result.status, ExamPaperImportStatus.blocked);
    expect(result.blockedCount, 1);
    expect(result.blocked.single.code, ExamPaperBlockReason.figureMissingStem);
    expect(await _count(db, 'questions'), 0);
    expect(await _count(db, 'content_refs'), 0);
    expect(await _count(db, 'attachments'), 0);
  });

  test('有题干图但没传 QuestionMediaStore：bad 题 blocked，无图题照常导入', () async {
    final figurePath = writeFigure('images/q2.png');
    final paper = ExamPaperDocument.fromJson(
      _paperJson(<Map<String, Object?>>[
        _choiceQuestion(
          1,
          answer: const <String, Object?>{'summary_md': '1．A'},
        ),
        _choiceQuestion(
          2,
          stem: '2．如图（   ）\n\n![x]($figurePath)',
          answer: const <String, Object?>{'summary_md': '2．B'},
          images: <Map<String, Object?>>[
            <String, Object?>{'saved_as': figurePath},
          ],
        ),
      ]),
      directoryPath: workDir.path,
    );
    final result = await newImporter().importPaper(paper);
    expect(result.questionCount, 1);
    expect(result.blockedCount, 1);
    expect(result.blocked.single.questionNumber, 2);
    expect(
      result.blocked.single.code,
      ExamPaperBlockReason.figureNotImportable,
    );
    expect(await _count(db, 'questions'), 1);
    expect(await _count(db, 'attachments'), 0);
  });

  test('公式未转换：unsupported_omml 非空 → 该题 blocked', () async {
    final paper = ExamPaperDocument.fromJson(
      _paperJson(<Map<String, Object?>>[
        _choiceQuestion(
          1,
          unsupportedOmml: <String, Object?>{'oMath': 2},
          answer: const <String, Object?>{'summary_md': '1．A'},
        ),
      ]),
      directoryPath: workDir.path,
    );
    final result = await newImporter(mediaStore: newMediaStore())
        .importPaper(paper);
    expect(result.status, ExamPaperImportStatus.blocked);
    expect(
      result.blocked.single.code,
      ExamPaperBlockReason.formulaUnsupported,
    );
    expect(await _count(db, 'questions'), 0);
  });

  test('题干图引用对不上任何 images 条目 → 该题 blocked，不猜图', () async {
    final figurePath = writeFigure('images/q1.png');
    final paper = ExamPaperDocument.fromJson(
      _paperJson(<Map<String, Object?>>[
        _choiceQuestion(
          1,
          stem: '1．![未知图](images/unknown.png)（   ）',
          answer: const <String, Object?>{'summary_md': '1．A'},
          images: <Map<String, Object?>>[
            <String, Object?>{'saved_as': figurePath},
          ],
        ),
      ]),
      directoryPath: workDir.path,
    );
    final result = await newImporter(mediaStore: newMediaStore())
        .importPaper(paper);
    expect(result.status, ExamPaperImportStatus.blocked);
    expect(
      result.blocked.single.code,
      ExamPaperBlockReason.figureReferenceUnresolved,
    );
    expect(await _count(db, 'questions'), 0);
  });

  // -------------------------------------------------------------------------
  // 5. 失败回滚
  // -------------------------------------------------------------------------

  test('图落盘中途抛错：整卷事务回滚，不留题/引用/附件', () async {
    final figurePath = writeFigure('images/q1.png');
    final paper = ExamPaperDocument.fromJson(
      _paperJson(<Map<String, Object?>>[
        _choiceQuestion(
          1,
          stem: '1．图（   ）\n\n![x]($figurePath)',
          answer: const <String, Object?>{'summary_md': '1．A'},
          images: <Map<String, Object?>>[
            <String, Object?>{'saved_as': figurePath},
          ],
        ),
        _choiceQuestion(
          2,
          stem: '2．图（   ）\n\n![x]($figurePath)',
          answer: const <String, Object?>{'summary_md': '2．B'},
          images: <Map<String, Object?>>[
            <String, Object?>{'saved_as': figurePath},
          ],
        ),
      ]),
      directoryPath: workDir.path,
    );
    final failing = _FailingMediaStore(
      database: db,
      supportDirectory: () async => supportDir,
      failAfter: 1,
    );
    final importer = newImporter(mediaStore: failing);

    await expectLater(
      importer.importPaper(paper),
      throwsA(isA<StateError>()),
    );
    expect(await _count(db, 'questions'), 0, reason: '第 2 题失败时第 1 题也要回滚');
    expect(await _count(db, 'content_refs'), 0);
    expect(await _count(db, 'attachments'), 0);
  });

  // -------------------------------------------------------------------------
  // 6. 六科结构（task-89）：block 形态 / 材料 / 英语 sections / 模块卷
  // -------------------------------------------------------------------------

  test('化学 block 形态：tokens/表格/选项图/答案公式图 → 占位 + 附件 + 元数据', () async {
    writeFigure('assets/image3.png');
    writeFigure('assets/image9.png');
    writeFigure('assets/image10.png');
    writeFigure('assets/image20.png');
    writeFigure('assets/image21.png');
    final paper = ExamPaperDocument.fromJson(
      _paper(
        paperId: 'chem-block',
        title: '2024年普通高中学业水平选择性考试（广东卷）化学',
        subject: 'chemistry',
        questions: <Map<String, Object?>>[
          <String, Object?>{
            'number': 1,
            'type': '单项选择题',
            'score': 2,
            'score_source': 'source:选择题说明',
            'stem': <Map<String, Object?>>[
              <String, Object?>{
                'kind': 'p',
                'tokens': <Map<String, Object?>>[
                  <String, Object?>{'k': 't', 'v': '1. 题干 '},
                  <String, Object?>{'k': 'eq', 'id': 'image3.png'},
                  <String, Object?>{'k': 't', 'v': ' 结束'},
                ],
              },
              <String, Object?>{
                'kind': 'table',
                'rows': <Object?>[
                  <Object?>[
                    <Map<String, Object?>>[
                      <String, Object?>{'k': 't', 'v': '序号'},
                    ],
                    <Map<String, Object?>>[
                      <String, Object?>{'k': 'eq', 'id': 'image9.png'},
                    ],
                  ],
                  <Object?>[
                    <Map<String, Object?>>[
                      <String, Object?>{'k': 't', 'v': 'a'},
                    ],
                    <Map<String, Object?>>[
                      <String, Object?>{'k': 'img', 'id': 'image10.png'},
                    ],
                  ],
                ],
              },
            ],
            'options': <Map<String, Object?>>[
              <String, Object?>{
                'label': 'A',
                'content': <Map<String, Object?>>[
                  <String, Object?>{'k': 'img', 'id': 'image10.png'},
                  <String, Object?>{'k': 't', 'v': '甲'},
                ],
              },
              <String, Object?>{
                'label': 'B',
                'content': <Map<String, Object?>>[
                  <String, Object?>{'k': 't', 'v': '乙'},
                ],
              },
            ],
            'answer': <String, Object?>{
              'letter': 'A',
              'blocks': <Map<String, Object?>>[
                <String, Object?>{
                  'kind': 'p',
                  'tokens': <Map<String, Object?>>[
                    <String, Object?>{'k': 't', 'v': '【答案】'},
                    <String, Object?>{'k': 'eq', 'id': 'image20.png'},
                  ],
                },
              ],
            },
            'explanation': <Map<String, Object?>>[
              <String, Object?>{
                'kind': 'p',
                'tokens': <Map<String, Object?>>[
                  <String, Object?>{'k': 't', 'v': '【解析】见图'},
                  <String, Object?>{'k': 'img', 'id': 'image21.png'},
                ],
              },
            ],
          },
        ],
      ),
      manifestJson: <String, Object?>{'stage': '高考'},
      directoryPath: workDir.path,
    );
    final result =
        await newImporter(mediaStore: newMediaStore()).importPaper(paper);
    expect(result.blockedCount, 0);
    expect(result.questionCount, 1);
    expect(result.optionCount, 2);
    // 题干 3 张（含表格/选项重复引用按路径去重）+ 答案/解析 2 张。
    expect(result.figureCount, 5);
    expect(result.figuresImported, 5);

    final question = (await questions.byId(
      result.questions.single.questionId,
    ))!;
    expect(question.stem, contains('1. 题干 ［图1］ 结束'));
    expect(question.stem, contains('【表格】'));
    expect(question.stem, contains('第1行：序号 | ［图2］'));
    expect(question.stem, contains('第2行：a | ［图3］'));
    expect(question.stem, contains('【选项配图】'));
    expect(question.stem, contains('A．［图3］'));
    expect(question.answer, 'A', reason: '客观题答案取 letter，不取 block 占位');
    final answerImages = await newMediaStore()
        .list(question.id, role: QuestionImageRole.answer);
    expect(answerImages, hasLength(2), reason: '答案/解析公式图落 role=answer');
    expect(question.solution, isNot(contains('⟦')));

    final options = await questions.optionsOf(question.id);
    expect(options[0].content, '甲（选项配图见［图3］）');
    expect(options[1].content, '乙');
    expect(
      options.where((option) => option.isCorrect).map((option) => option.label),
      <String>['A'],
    );

    final metadata = await _questionMetadata(db, 'chem-block#Q1');
    expect(metadata['formula_image_not_latex'], isTrue);
    expect(metadata['formula_image_count'], 3);
    expect(metadata['option_figure_count'], 1);
    expect(metadata['original_question_type'], '单项选择题');
    expect(metadata['source_stage'], '高考');
    expect(metadata['exam_scope'], 'gaokao');
    final codes = result.skipped.map((issue) => issue.code).toSet();
    expect(codes, contains(ExamPaperSkipReason.formulaImageNotLatex));
    expect(codes, contains(ExamPaperSkipReason.optionImageInlinedIntoStem));
  });

  test('物理 block 形态：stem_blocks/选项 blocks/答案/解析 公式图都是图，不假装文本', () async {
    for (final path in <String>[
      'assets/formulas/f1.png',
      'assets/figures/f2.png',
      'assets/formulas/f3.png',
      'assets/figures/f4.png',
      'assets/formulas/a1.png',
      'assets/formulas/a2.png',
      'assets/figures/a3.png',
    ]) {
      writeFigure(path);
    }
    final paper = ExamPaperDocument.fromJson(
      _paper(
        paperId: 'physics-block',
        title: '2024年普通高中学业水平选择性考试（广东卷）物理',
        subject: 'physics',
        questions: <Map<String, Object?>>[
          <String, Object?>{
            'number': 1,
            'type': 'single_choice',
            'score': 4,
            'score_source': 'section_header',
            'stem_blocks': <Map<String, Object?>>[
              <String, Object?>{'type': 'text', 'text': '1. 题干', 'paragraph': 1},
              <String, Object?>{
                'type': 'formula',
                'asset': 'assets/formulas/f1.png',
                'paragraph': 1,
              },
              <String, Object?>{'type': 'text', 'text': ' 结束', 'paragraph': 1},
              <String, Object?>{
                'type': 'figure',
                'asset': 'assets/figures/f2.png',
                'paragraph': 2,
              },
            ],
            'options': <Map<String, Object?>>[
              <String, Object?>{
                'label': 'A',
                'blocks': <Map<String, Object?>>[
                  <String, Object?>{'type': 'text', 'text': '甲'},
                  <String, Object?>{
                    'type': 'formula',
                    'asset': 'assets/formulas/f3.png',
                  },
                ],
              },
              <String, Object?>{
                'label': 'B',
                'blocks': <Map<String, Object?>>[
                  <String, Object?>{
                    'type': 'figure',
                    'asset': 'assets/figures/f4.png',
                  },
                ],
              },
            ],
            'answer_blocks': <Map<String, Object?>>[
              <String, Object?>{'type': 'text', 'text': '【答案】B'},
            ],
            'analysis_blocks': <Map<String, Object?>>[
              <String, Object?>{'type': 'text', 'text': '【解析】'},
              <String, Object?>{'type': 'text', 'text': '【详解】'},
              <String, Object?>{
                'type': 'formula',
                'asset': 'assets/formulas/a1.png',
              },
              <String, Object?>{'type': 'text', 'text': '故'},
              <String, Object?>{
                'type': 'formula',
                'asset': 'assets/formulas/a2.png',
              },
              <String, Object?>{
                'type': 'figure',
                'asset': 'assets/figures/a3.png',
              },
            ],
          },
        ],
      ),
      directoryPath: workDir.path,
    );
    final result =
        await newImporter(mediaStore: newMediaStore()).importPaper(paper);
    expect(result.blockedCount, 0);
    expect(result.figureCount, 7);
    expect(result.figuresImported, 7);

    final question = (await questions.byId(
      result.questions.single.questionId,
    ))!;
    expect(question.stem, contains('1. 题干［图1］ 结束'));
    expect(question.stem, contains('［图2］'));
    expect(question.stem, contains('【选项配图】'));
    expect(question.stem, contains('A．［图3］'));
    expect(question.stem, contains('B．［图4］'));
    final options = await questions.optionsOf(question.id);
    expect(options[0].content, '甲（选项配图见［图3］）');
    expect(options[1].content, '（选项配图见［图4］）');
    expect(question.answer, 'B');
    expect(question.solution, startsWith('【详解】'));
    expect(question.solution, contains('［图1］'));
    expect(question.solution, contains('［图3］'));

    final metadata = await _questionMetadata(db, 'physics-block#Q1');
    expect(metadata['formula_image_not_latex'], isTrue);
    expect(metadata['formula_image_count'], 4);
    expect(metadata['option_figure_count'], 2);
  });

  test('物理公式图文件缺失：该题 blocked（formula_image_missing_stem）', () async {
    final paper = ExamPaperDocument.fromJson(
      _paper(
        paperId: 'physics-missing',
        title: '2024年普通高中学业水平选择性考试（广东卷）物理',
        subject: 'physics',
        questions: <Map<String, Object?>>[
          <String, Object?>{
            'number': 1,
            'type': 'single_choice',
            'score': 4,
            'score_source': 'section_header',
            'stem_blocks': <Map<String, Object?>>[
              <String, Object?>{'type': 'text', 'text': '1. 题干'},
              <String, Object?>{
                'type': 'formula',
                'asset': 'assets/formulas/missing.png',
              },
            ],
            'answer': <String, Object?>{'text': 'A'},
          },
        ],
      ),
      directoryPath: workDir.path,
    );
    final result =
        await newImporter(mediaStore: newMediaStore()).importPaper(paper);
    expect(result.status, ExamPaperImportStatus.blocked);
    expect(
      result.blocked.single.code,
      ExamPaperBlockReason.formulaImageMissingStem,
    );
    expect(await _count(db, 'questions'), 0);
  });

  test('语文 material_ids：材料原文并入题干；材料缺失 → 该题 blocked', () async {
    final paper = ExamPaperDocument.fromJson(
      <String, Object?>{
        'paper_id': 'chinese-material',
        'title': '2025年普通高等学校招生全国统一考试 语文 全国一卷',
        'subject': 'chinese',
        'year': 2025,
        'sections': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'S1',
            'name': '现代文阅读Ⅰ',
            'materials': <Map<String, Object?>>[
              <String, Object?>{'id': 'S1-M1', 'text': '材料正文第一段'},
            ],
          },
        ],
        'questions': <Map<String, Object?>>[
          <String, Object?>{
            'number': 1,
            'type': '单项选择题',
            'score': 3,
            'score_source': 'question_stem_annotation',
            'stem': '下列理解正确的一项是（   ）',
            'options': <Map<String, Object?>>[
              <String, Object?>{'label': 'A', 'text': '甲'},
              <String, Object?>{'label': 'B', 'text': '乙'},
            ],
            'material_ids': <String>['S1-M1'],
            'answer': 'B',
            'analysis': '因为乙正确',
            'answer_non_unique': false,
          },
          <String, Object?>{
            'number': 2,
            'type': '单项选择题',
            'score': 3,
            'score_source': 'question_stem_annotation',
            'stem': '第二题',
            'options': <Map<String, Object?>>[
              <String, Object?>{'label': 'A', 'text': '甲'},
              <String, Object?>{'label': 'B', 'text': '乙'},
            ],
            'material_ids': <String>['S1-M9'],
            'answer': 'A',
            'analysis': '因为甲正确',
          },
        ],
      },
      directoryPath: workDir.path,
    );
    final result =
        await newImporter(mediaStore: newMediaStore()).importPaper(paper);
    expect(result.questionCount, 1);
    expect(result.blockedCount, 1);
    expect(result.blocked.single.code, ExamPaperBlockReason.materialMissing);
    expect(result.blocked.single.questionNumber, 2);

    final question = (await questions.byId(
      result.questions.single.questionId,
    ))!;
    expect(question.stem, startsWith('【材料 S1-M1】\n材料正文第一段'));
    expect(question.stem, contains('【题目】'));
    final metadata = await _questionMetadata(db, 'chinese-material#Q1');
    expect(metadata['material_ids'], <String>['S1-M1']);
    expect(metadata['material_inlined'], isTrue);
    expect(metadata['original_question_type'], '单项选择题');
    expect(
      result.skipped.map((issue) => issue.code),
      contains(ExamPaperSkipReason.materialInlinedIntoStem),
    );
  });

  test('英语 sections：听力/阅读/七选五/完形/语法/写作摊平成题，材料并入题干', () async {
    final paper = ExamPaperDocument.fromJson(
      <String, Object?>{
        'paper_id': 'english-sections',
        'title': '2026年普通高等学校招生全国统一考试（全国Ⅰ卷）英语',
        'subject': 'english',
        'year': 2026,
        'region': '全国I卷',
        'score_total': 150,
        'sections': <String, Object?>{
          'listening': <String, Object?>{
            'questions': <Map<String, Object?>>[
              <String, Object?>{
                'no': 1,
                'type': 'single_choice',
                'score': 1.5,
                'answer': 'C',
                'stem': 'Who is the man?',
                'options': <Map<String, Object?>>[
                  <String, Object?>{'label': 'A', 'text': 'a'},
                  <String, Object?>{'label': 'B', 'text': 'b'},
                  <String, Object?>{'label': 'C', 'text': 'c'},
                ],
                'audio_available': false,
                'script': 'M: hello',
              },
            ],
            'groups': <Object?>[],
          },
          'reading': <String, Object?>{
            'passages': <Map<String, Object?>>[
              <String, Object?>{
                'letter': 'A',
                'material': '阅读语篇 A 正文',
                'questions': <Map<String, Object?>>[
                  <String, Object?>{
                    'no': 21,
                    'type': 'single_choice',
                    'score': 2.5,
                    'answer': 'B',
                    'stem': 'Which?',
                    'options': <Map<String, Object?>>[
                      <String, Object?>{'label': 'A', 'text': 'a'},
                      <String, Object?>{'label': 'B', 'text': 'b'},
                      <String, Object?>{'label': 'C', 'text': 'c'},
                      <String, Object?>{'label': 'D', 'text': 'd'},
                    ],
                  },
                ],
              },
            ],
          },
          'seven_choose_five': <String, Object?>{
            'material': '七选五短文',
            'options': <Map<String, Object?>>[
              <String, Object?>{'label': 'A', 'text': 'A 项'},
              <String, Object?>{'label': 'B', 'text': 'B 项'},
              <String, Object?>{'label': 'C', 'text': 'C 项'},
              <String, Object?>{'label': 'D', 'text': 'D 项'},
              <String, Object?>{'label': 'E', 'text': 'E 项'},
              <String, Object?>{'label': 'F', 'text': 'F 项'},
              <String, Object?>{'label': 'G', 'text': 'G 项'},
            ],
            'questions': <Map<String, Object?>>[
              <String, Object?>{
                'no': 36,
                'type': 'seven_choose_five',
                'score': 2.5,
                'answer': 'C',
                'stem': '从短文后的 A–G 选项中选出最佳选项。',
                'blank_context': <String, Object?>{
                  'prev_sentence': '前一句',
                  'next_sentence': '后一句',
                },
                'explanation': '衔接题解析',
              },
            ],
          },
          'cloze': <String, Object?>{
            'material': '完形短文',
            'questions': <Map<String, Object?>>[
              <String, Object?>{
                'no': 41,
                'type': 'single_choice',
                'score': 1,
                'answer': 'A',
                'stem': 'The ____41____ sentence.',
                'options': <Map<String, Object?>>[
                  <String, Object?>{'label': 'A', 'text': 'a'},
                  <String, Object?>{'label': 'B', 'text': 'b'},
                  <String, Object?>{'label': 'C', 'text': 'c'},
                  <String, Object?>{'label': 'D', 'text': 'd'},
                ],
                'explanation': '完形解析',
              },
              <String, Object?>{
                'no': 42,
                'type': 'single_choice',
                'score': 1,
                'answer': 'B',
                'stem': 'The ____41____ sentence.',
                'options': <Map<String, Object?>>[
                  <String, Object?>{'label': 'A', 'text': 'a'},
                  <String, Object?>{'label': 'B', 'text': 'b'},
                  <String, Object?>{'label': 'C', 'text': 'c'},
                  <String, Object?>{'label': 'D', 'text': 'd'},
                ],
                'explanation': '完形解析',
              },
            ],
          },
          'grammar': <String, Object?>{
            'material': '语法语篇',
            'questions': <Map<String, Object?>>[
              <String, Object?>{
                'no': 56,
                'type': 'fill_in',
                'score': 1.5,
                'answer': 'to be',
                'stem': 'It is common ____56____ (hold).',
                'explanation': '语法解析',
              },
            ],
          },
          'writing': <Object?>[
            <String, Object?>{
              'no': 66,
              'type': 'applied_writing',
              'kind': 'applied_writing',
              'score': 15,
              'prompt': '写一篇短文',
              'answer': '参考样例正文',
              'answer_type': 'reference_sample',
              'explanation': '写作解析',
            },
          ],
        },
      },
      directoryPath: workDir.path,
    );
    final result =
        await newImporter(mediaStore: newMediaStore()).importPaper(paper);
    expect(result.blockedCount, 0);
    expect(result.questionCount, 7);
    expect(result.optionCount, 22);
    expect(result.figuresImported, 0);

    final listening = (await questions.byId(
      result.questions.first.questionId,
    ))!;
    expect(listening.stem, contains('【听力原文】'));
    expect(listening.stem, contains('M: hello'));
    final listeningMeta =
        await _questionMetadata(db, 'english-sections#Q1');
    expect(listeningMeta['audio_available'], isFalse);

    final seven = (await questions.byId(
      _questionIdByNumber(result, 36),
    ))!;
    expect(seven.stem, contains('【短文】\n七选五短文'));
    expect(seven.stem, contains('【空格上下文】'));
    expect(await questions.optionsOf(seven.id), hasLength(7));

    final cloze41 = (await questions.byId(
      _questionIdByNumber(result, 41),
    ))!;
    final cloze42 = (await questions.byId(
      _questionIdByNumber(result, 42),
    ))!;
    expect(cloze41.stem, contains('（第41空）'));
    expect(cloze42.stem, contains('（第42空）'));
    expect(cloze41.stem, isNot(cloze42.stem), reason: '同句多空不能撞题干指纹');

    final writing = (await questions.byId(
      _questionIdByNumber(result, 66),
    ))!;
    expect(writing.questionType, 'open');
    expect(writing.answer, '参考样例正文');
    final writingMeta =
        await _questionMetadata(db, 'english-sections#Q66');
    expect(writingMeta['answer_non_unique'], isTrue);
    expect(
      result.skipped.map((issue) => issue.code),
      contains(ExamPaperSkipReason.scoreSourceFromSectionNote),
    );
  });

  test('生物模块卷：字符串图路径/选项 map/explanation；stage 非高考 → non_gaokao', () async {
    writeFigure('assets/figures/q1.jpg');
    final paper = ExamPaperDocument.fromJson(
      _paper(
        paperId: 'bio-module',
        title: '周末练11 模块检测试卷(一)（生物·选择性必修3）',
        subject: 'biology',
        questions: <Map<String, Object?>>[
          <String, Object?>{
            'number': 1,
            'type': 'choice',
            'score': 3,
            'score_source': '选择题说明：每小题3分',
            'stem': '1．下列叙述正确的是()',
            'options': <String, Object?>{
              'A': '甲',
              'B': '乙',
              'C': '丙',
              'D': '丁',
            },
            'answer': 'C',
            'explanation': '丙正确',
            'figures': <String>['assets/figures/q1.jpg'],
          },
        ],
      ),
      manifestJson: <String, Object?>{'stage': '高二模块检测（非高考真题）'},
      directoryPath: workDir.path,
    );
    final result =
        await newImporter(mediaStore: newMediaStore()).importPaper(paper);
    expect(result.blockedCount, 0);
    expect(result.sourceLevel, 'school');
    expect(result.sourceLevelBasis, 'stage_non_gaokao');
    expect(result.figureCount, 1);
    expect(result.figuresImported, 1);
    expect(result.toJson()['exam_scope'], 'non_gaokao');

    final question = (await questions.byId(
      result.questions.single.questionId,
    ))!;
    expect(question.questionType, 'single_choice');
    final metadata = await _questionMetadata(db, 'bio-module#Q1');
    expect(metadata['exam_scope'], 'non_gaokao');
    expect(metadata['source_stage'], contains('非高考'));
    expect(metadata['original_question_type'], 'choice');
    final options = await questions.optionsOf(question.id);
    expect(options, hasLength(4));
    expect(
      options.where((option) => option.isCorrect).map((option) => option.label),
      <String>['C'],
    );
  });
}

/// 构造一份最小 `paper.json`（六科结构测试用）。
Map<String, Object?> _paper({
  required String paperId,
  required String title,
  required String subject,
  required List<Map<String, Object?>> questions,
}) =>
    <String, Object?>{
      'paper_id': paperId,
      'title': title,
      'subject': subject,
      'year': 2025,
      'score_total': 150,
      'questions': questions,
    };

String _questionIdByNumber(ExamPaperImportResult result, int number) {
  return result.questions
      .singleWhere((question) => question.number == number)
      .questionId;
}

// ---------------------------------------------------------------------------
// 测试数据
// ---------------------------------------------------------------------------

const List<int> _fakePng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89,
];

Map<String, Object?> _paperJson(
  List<Map<String, Object?>> questions, {
  String paperId = 'test-paper',
}) =>
    <String, Object?>{
      'paper_id': paperId,
      'title': '2025年普通高等学校招生全国统一考试（测试）数学',
      'subject': 'math',
      'year': 2025,
      'region': 'national1',
      'score_total': 150,
      'questions': questions,
    };

Map<String, Object?> _choiceQuestion(
  int number, {
  String type = 'single_choice',
  num? score = 5,
  String scoreSource = 'test_template',
  String stem = '1．测试题干（   ）',
  List<Map<String, Object?>>? options,
  Map<String, Object?>? answer,
  Map<String, Object?>? analysis,
  List<Map<String, Object?>>? images,
  List<String>? knowledgePoints,
  num? scoreInferred,
  Map<String, Object?>? unsupportedOmml,
}) =>
    <String, Object?>{
      'number': number,
      'question_type': type,
      'score': score,
      'score_source': scoreSource,
      'score_confirmed_in_source_docx': false,
      'stem_md': stem,
      'options': options ??
          const <Map<String, Object?>>[
            <String, Object?>{'label': 'A', 'text': '甲'},
            <String, Object?>{'label': 'B', 'text': '乙'},
            <String, Object?>{'label': 'C', 'text': '丙'},
            <String, Object?>{'label': 'D', 'text': '丁'},
          ],
      'answer': answer ??
          <String, Object?>{
            'summary_md': '$number．A',
            'source': 'answer_docx',
          },
      'analysis': analysis ??
          <String, Object?>{
            'source': 'answer_docx',
            'groups': <Map<String, Object?>>[
              <String, Object?>{'text': '【详解】测试解析.'},
            ],
          },
      'images': images ?? const <Map<String, Object?>>[],
      'ai_labels': <String, Object?>{
        'provenance': 'ai_initial_label',
        'verified': false,
      },
      if (knowledgePoints != null) 'knowledge_points': knowledgePoints,
      if (scoreInferred != null) 'score_inferred': scoreInferred,
      if (unsupportedOmml != null) 'unsupported_omml': unsupportedOmml,
    };

Future<Map<String, Object?>> _questionMetadata(
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

/// 第 [failAfter] 次以后 `save` 直接抛错，用来验证整卷事务回滚。
class _FailingMediaStore extends QuestionMediaStore {
  _FailingMediaStore({
    required super.database,
    super.supportDirectory,
    required this.failAfter,
  });

  final int failAfter;
  var _calls = 0;

  @override
  Future<QuestionImage> save({
    required String questionId,
    required String fileName,
    required Uint8List bytes,
    String? mime,
    int? sortOrder,
    String role = QuestionImageRole.stem,
    DateTime? now,
  }) async {
    _calls += 1;
    if (_calls > failAfter) {
      throw StateError('测试注入：第 $_calls 张图落盘失败');
    }
    return super.save(
      questionId: questionId,
      fileName: fileName,
      bytes: bytes,
      mime: mime,
      sortOrder: sortOrder,
      role: role,
      now: now,
    );
  }
}
