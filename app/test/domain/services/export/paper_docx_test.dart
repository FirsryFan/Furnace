import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/export/paper_docx.dart';
import 'package:furnace/domain/services/paper/paper_composer.dart';

/// 题目卷装配：页首、题干/选项/配图、卷末答案与组卷说明、缺口与导出提示，
/// 以及"编译不了/缺内容时如实报告，而不是静默省略"。
void main() {
  group('页首与题干区', () {
    test('标题、题数口径、题号与组卷元信息都写进卷面', () {
      final result = buildPaperDocx(
        plan: samplePlan(),
        questions: sampleQuestions(),
        knowledgePointNames: const {'kp1': '函数单调性'},
        footerText: 'THREADRIPPER · 2026-10-18',
        generatedAt: DateTime(2026, 10, 18, 22, 5),
      );
      final document = _documentXml(result);
      expect(document, contains('组卷卷面'));
      expect(document, contains('想要 2 道，凑到 2 道'));
      expect(document, contains('导出时间：2026-10-18 22:05'));
      expect(document, contains('1.  TR-00001'));
      expect(document, contains('数学'));
      expect(document, contains('高考真题'));
      expect(document, contains('危险区'));
      expect(document, contains('知识点：函数单调性'));
      expect(document, contains('2026 年'));
      expect(document, contains('江苏'));
    });

    test('题干与选项按行写，公式交给注入的编译器', () {
      final result = buildPaperDocx(
        plan: samplePlan(),
        questions: sampleQuestions(),
        knowledgePointNames: const {'kp1': '函数单调性'},
        mathCompiler: fakeMath,
      );
      final document = _documentXml(result);
      expect(document, contains('已知函数'));
      expect(document,
          contains('<m:oMath><m:r><m:t>f(x)=x^2</m:t></m:r></m:oMath>'));
      expect(document, contains('A. 增区间 (0,+∞)'));
      expect(document, contains('B. 减区间 (0,+∞)'));
      expect(result.formulaCount, 2); // 题干 1 + 解析 1
      expect(result.formulaFailureCount, 0);
    });

    test('题干换行拆成多个段落', () {
      final questions = <String, PaperDocxQuestion>{
        'q1': const PaperDocxQuestion(
          questionId: 'q1',
          stem: '第一行\n第二行',
        ),
      };
      final document = _documentXml(
        buildPaperDocx(
          plan: samplePlan(items: [paperItem('q1')]),
          questions: questions,
          knowledgePointNames: const {'kp1': '函数单调性'},
        ),
      );
      expect(document, contains('第一行'));
      expect(document, contains('第二行'));
      expect(
          '<w:t xml:space="preserve">\n'.allMatches(document).isEmpty, isTrue);
    });

    test('题干为空时写占位句并计数', () {
      final result = buildPaperDocx(
        plan: samplePlan(items: [paperItem('q1')]),
        questions: <String, PaperDocxQuestion>{
          'q1': const PaperDocxQuestion(questionId: 'q1', stem: '   '),
        },
        knowledgePointNames: const {'kp1': '函数单调性'},
      );
      expect(_documentXml(result), contains('题干为空'));
      expect(result.missingStemCount, 1);
      expect(result.hasWarnings, isTrue);
    });

    test('没挂知识点的题写「未标知识点」而不是空白', () {
      final document = _documentXml(
        buildPaperDocx(
          plan: samplePlan(items: [paperItem('q1', kpId: 'unknown-kp')]),
          questions: sampleQuestions(),
          knowledgePointNames: const {},
        ),
      );
      expect(document, contains('未标知识点'));
    });
  });

  group('卷末答案 / 解析 / 组卷说明', () {
    test('答案、解析、理由、提升点、背景都出现在卷末', () {
      final document = _documentXml(
        buildPaperDocx(
          plan: samplePlan(),
          questions: sampleQuestions(),
          knowledgePointNames: const {'kp1': '函数单调性'},
        ),
      );
      expect(document, contains('参考答案与解析'));
      expect(document, contains('答案：'));
      expect(document, contains('>B</w:t>'));
      expect(document, contains('解析：'));
      expect(document, contains('由 '));
      // 标签与正文是两个 run（标签加粗灰色），所以按 run 分别断言。
      expect(document, contains('理由：'));
      expect(document, contains('危险区，优先补'));
      expect(document, contains('提升点：'));
      expect(document, contains('注意定义域'));
      expect(document, contains('背景：'));
      expect(document, contains('函数 › 单调性'));
    });

    test('没有答案文本时从正确选项字母推导，不算缺失', () {
      final result = buildPaperDocx(
        plan: samplePlan(items: [paperItem('q1')]),
        questions: <String, PaperDocxQuestion>{
          'q1': const PaperDocxQuestion(
            questionId: 'q1',
            serialNo: 'TR-00007',
            stem: '选一个',
            options: [
              PaperDocxOption(label: 'A', content: '错'),
              PaperDocxOption(label: 'C', content: '对', isCorrect: true),
            ],
          ),
        },
        knowledgePointNames: const {'kp1': '函数单调性'},
      );
      expect(_documentXml(result), contains('答案：'));
      expect(_documentXml(result), contains('>C</w:t>'));
      expect(result.missingAnswerCount, 0);
    });

    test('答案与解析都没有时写占位句并计数', () {
      final result = buildPaperDocx(
        plan: samplePlan(items: [paperItem('q1')]),
        questions: <String, PaperDocxQuestion>{
          'q1': const PaperDocxQuestion(questionId: 'q1', stem: '题干'),
        },
        knowledgePointNames: const {'kp1': '函数单调性'},
      );
      final document = _documentXml(result);
      expect(document, contains('（无答案）'));
      expect(document, contains('（无解析）'));
      expect(result.missingAnswerCount, 1);
      expect(result.missingSolutionCount, 1);
    });

    test('开关可以整段关掉答案/解析/说明/缺口', () {
      final document = _documentXml(
        buildPaperDocx(
          plan: samplePlan(),
          questions: sampleQuestions(),
          knowledgePointNames: const {'kp1': '函数单调性'},
          includeAnswers: false,
          includeSolutions: false,
          includeReasons: false,
          includeGaps: false,
        ),
      );
      expect(document, isNot(contains('答案：')));
      expect(document, isNot(contains('解析：')));
      expect(document, isNot(contains('理由：')));
      expect(document, isNot(contains('未覆盖的知识点')));
    });
  });

  group('缺口与内容缺失', () {
    test('未覆盖/被上限挡下的知识点如实列进附录', () {
      final document = _documentXml(
        buildPaperDocx(
          plan: samplePlan(
            uncoveredIds: const ['kp-missing'],
            deferredIds: const ['kp-capped'],
          ),
          questions: sampleQuestions(),
          knowledgePointNames: const {
            'kp1': '函数单调性',
            'kp-missing': '数列求和',
            'kp-capped': '立体几何',
          },
        ),
      );
      expect(document, contains('未覆盖的知识点'));
      expect(document, contains('数列求和'));
      expect(document, contains('被上限挡下的知识点'));
      expect(document, contains('立体几何'));
    });

    test('题目内容缺失不炸导出，而是计数 + 标注', () {
      final result = buildPaperDocx(
        plan: samplePlan(),
        questions: <String, PaperDocxQuestion>{
          'q1': sampleQuestions()['q1']!,
        },
        knowledgePointNames: const {'kp1': '函数单调性'},
      );
      final document = _documentXml(result);
      expect(document, contains('题库中找不到这道题的内容'));
      expect(result.missingQuestionCount, 1);
      expect(result.missingQuestionLabels, ['第 2 题（q2）']);
    });
  });

  group('公式编译失败不丢公式', () {
    test('编译器抛错时保留 LaTeX 原文、计数并写导出提示', () {
      final result = buildPaperDocx(
        plan: samplePlan(items: [paperItem('q1')]),
        questions: <String, PaperDocxQuestion>{
          'q1': const PaperDocxQuestion(
            questionId: 'q1',
            stem: '求 \$\\unknowncmd{x}\$ 的值',
            answer: '1',
          ),
        },
        knowledgePointNames: const {'kp1': '函数单调性'},
        mathCompiler: (tex, {int? sizeHalfPt}) =>
            throw StateError('unknown command'),
      );
      final document = _documentXml(result);
      expect(document, contains('\\unknowncmd{x}'));
      expect(document, contains('公式未能编译（已保留 LaTeX 原文）'));
      expect(result.formulaFailureCount, 1);
      expect(result.formulaFailures.single, contains('unknowncmd'));
    });

    test('不传编译器时公式按原文保留，不算失败', () {
      final result = buildPaperDocx(
        plan: samplePlan(items: [paperItem('q1')]),
        questions: <String, PaperDocxQuestion>{
          'q1': const PaperDocxQuestion(
            questionId: 'q1',
            stem: '已知 \$x^2\$',
            answer: '1',
          ),
        },
        knowledgePointNames: const {'kp1': '函数单调性'},
      );
      expect(_documentXml(result), contains(r'$x^2$'));
      expect(result.formulaCount, 0);
      expect(result.formulaFailureCount, 0);
    });
  });

  group('配图', () {
    test('合法规格的图进 media；尺寸缺失/格式不支持的跳过并报告', () {
      final result = buildPaperDocx(
        plan: samplePlan(items: [paperItem('q1')]),
        questions: <String, PaperDocxQuestion>{
          'q1': PaperDocxQuestion(
            questionId: 'q1',
            stem: '看图作答',
            answer: 'A',
            images: [
              PaperDocxImage(
                bytes: Uint8List.fromList([9, 9, 9]),
                extension: 'png',
                pixelWidth: 320,
                pixelHeight: 200,
                fileName: 'stem.png',
              ),
              PaperDocxImage(
                bytes: Uint8List(0),
                extension: 'png',
                pixelWidth: 0,
                pixelHeight: 0,
                fileName: 'empty.png',
              ),
              PaperDocxImage(
                bytes: Uint8List.fromList([7]),
                extension: 'heic',
                pixelWidth: 100,
                pixelHeight: 100,
                fileName: 'photo.heic',
              ),
            ],
          ),
        },
        knowledgePointNames: const {'kp1': '函数单调性'},
      );
      final entries = unzipText(result.bytes);
      expect(entries.keys, contains('word/media/image1.png'));
      expect(result.imageCount, 1);
      expect(result.imageSkippedCount, 2);
      expect(result.imageSkippedNotes.length, 2);
      final document = entries['word/document.xml']!;
      expect(document, contains('<wp:inline'));
      expect(document, contains('导出提示'));
      expect(document, contains('empty.png'));
      expect(document, contains('photo.heic'));
    });
  });

  group('统计与定制', () {
    test('题数/段落数/字节数成对可查', () {
      final result = buildPaperDocx(
        plan: samplePlan(),
        questions: sampleQuestions(),
        knowledgePointNames: const {'kp1': '函数单调性'},
      );
      expect(result.questionCount, 2);
      expect(result.paragraphCount, greaterThan(4));
      expect(result.bytes, isNotEmpty);
      expect(result.hasWarnings, isTrue); // q2 缺内容
    });

    test('请求 3 道只凑到 2 道时页首如实写', () {
      final document = _documentXml(
        buildPaperDocx(
          plan: samplePlan(requestedCount: 3),
          questions: sampleQuestions(),
          knowledgePointNames: const {'kp1': '函数单调性'},
        ),
      );
      expect(document, contains('想要 3 道，凑到 2 道'));
    });

    test('labels 可以整体替换成英文/自定义文案', () {
      final document = _documentXml(
        buildPaperDocx(
          plan: samplePlan(items: [paperItem('q1')], requestedCount: 1),
          questions: sampleQuestions(),
          knowledgePointNames: const {'kp1': 'Function monotonicity'},
          labels: const PaperDocxLabels(
            title: 'Test Paper',
            headlineBuilder: _englishHeadline,
            answerSectionTitle: 'Answers',
            subjectLabel: _englishSubject,
            sourceLevelLabel: _englishSourceLevel,
            knowledgePointPrefix: 'Topic: ',
          ),
        ),
      );
      expect(document, contains('Test Paper'));
      expect(document, contains('Want 1, got 1'));
      expect(document, contains('Answers'));
      expect(document, contains('Math'));
      expect(document, contains('Gaokao'));
      expect(document, contains('Topic: Function monotonicity'));
    });

    test('页脚带导出方标记与页码域', () {
      final result = buildPaperDocx(
        plan: samplePlan(),
        questions: sampleQuestions(),
        knowledgePointNames: const {'kp1': '函数单调性'},
        footerText: 'THREADRIPPER · 2026-10-18',
      );
      final footer = unzipText(result.bytes)['word/footer1.xml']!;
      expect(footer, contains('THREADRIPPER · 2026-10-18'));
      expect(footer, contains(' PAGE '));
      expect(footer, contains('NUMPAGES'));
    });

    test('serialNo 为空时题号行只写序号', () {
      final document = _documentXml(
        buildPaperDocx(
          plan: samplePlan(items: [paperItem('q1')]),
          questions: <String, PaperDocxQuestion>{
            'q1': const PaperDocxQuestion(
              questionId: 'q1',
              stem: '没有编号的题',
              answer: '1',
            ),
          },
          knowledgePointNames: const {'kp1': '函数单调性'},
        ),
      );
      expect(document, contains('>1.</w:t>'));
    });
  });

  group('附录分页', () {
    test('只有附录第一个标题另起一页，缺口小节顺排', () {
      final result = buildPaperDocx(
        plan: samplePlan(),
        questions: sampleQuestions(),
        knowledgePointNames: const {'kp1': '函数单调性'},
      );
      final document = _documentXml(result);
      // 夹具：答案区 + 未覆盖 + 被上限挡下。
      expect(document, contains('未覆盖的知识点'));
      expect(document, contains('被上限挡下的知识点'));
      final breaks = '<w:pageBreakBefore/>'.allMatches(document).length;
      expect(breaks, 1);
      // 唯一那次分页落在附录第一个标题（答案区）上，缺口小节顺排在其后。
      final breakIndex = document.indexOf('<w:pageBreakBefore/>');
      final answerIndex = document.indexOf('参考答案与解析');
      expect(breakIndex, greaterThan(0));
      expect(breakIndex, lessThan(answerIndex));
      expect(document.indexOf('未覆盖的知识点'), greaterThan(answerIndex));
      expect(document.indexOf('被上限挡下的知识点'), greaterThan(answerIndex));
    });
  });
}

// ---------------------------------------------------------------------------
// 测试夹具
// ---------------------------------------------------------------------------

String fakeMath(String tex, {int? sizeHalfPt}) =>
    '<m:oMath><m:r><m:t>$tex</m:t></m:r></m:oMath>';

String _englishHeadline(int want, int got) => 'Want $want, got $got';
String _englishSubject(String key) => key == 'math' ? 'Math' : key;
String _englishSourceLevel(String level) =>
    level == 'gaokao' ? 'Gaokao' : level;

PaperItem paperItem(
  String id, {
  String? kpId,
  PaperZone zone = PaperZone.danger,
  String subjectKey = 'math',
  String sourceLevel = 'gaokao',
}) =>
    PaperItem(
      questionId: id,
      subjectKey: subjectKey,
      sourceLevel: sourceLevel,
      questionType: 'solution',
      knowledgePointId: kpId ?? 'kp1',
      matchedKnowledgePointIds: <String>[kpId ?? 'kp1'],
      zone: zone,
      need: 1.0,
      quality: 0.8,
      score: 0.9,
      reasonZh: '危险区，优先补',
      improvementNote: '注意定义域',
      backgroundZh: '函数 › 单调性',
    );

PaperPlan samplePlan({
  List<PaperItem>? items,
  int requestedCount = 2,
  List<String> uncoveredIds = const <String>['kp-missing'],
  List<String> deferredIds = const <String>['kp-deferred'],
}) =>
    PaperPlan(
      items: items ?? <PaperItem>[paperItem('q1'), paperItem('q2')],
      uncoveredKnowledgePointIds: uncoveredIds,
      deferredKnowledgePointIds: deferredIds,
      byKnowledgePoint: const <String, int>{'kp1': 2},
      candidateCount: 9,
      requestedCount: requestedCount,
      overallNeed: 1.0,
      weights: const PaperWeights(),
    );

/// q1 内容完整（含公式/选项/解析/一张配图），q2 故意缺内容。
Map<String, PaperDocxQuestion> sampleQuestions() => <String, PaperDocxQuestion>{
      'q1': PaperDocxQuestion(
        questionId: 'q1',
        serialNo: 'TR-00001',
        stem: '已知函数 \$f(x)=x^2\$，求单调区间。',
        subjectKey: 'math',
        sourceLevel: 'gaokao',
        sourceLabel: '2026 届高三上期末',
        year: 2026,
        region: '江苏',
        options: const [
          PaperDocxOption(label: 'A', content: '增区间 (0,+∞)'),
          PaperDocxOption(label: 'B', content: '减区间 (0,+∞)', isCorrect: true),
        ],
        answer: 'B',
        solution: "由 \$f'(x)=2x\$ 可知……",
        images: [
          PaperDocxImage(
            bytes: Uint8List.fromList([1, 2, 3, 4]),
            extension: 'png',
            pixelWidth: 400,
            pixelHeight: 240,
            fileName: 'q1.png',
          ),
        ],
      ),
    };

Map<String, String> unzipText(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final result = <String, String>{};
  for (final file in archive) {
    if (!file.isFile) continue;
    result[file.name] = utf8.decode(file.content as List<int>);
  }
  return result;
}

String _documentXml(PaperDocxBuildResult result) =>
    unzipText(result.bytes)['word/document.xml']!;
