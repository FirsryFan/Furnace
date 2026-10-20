import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/export/paper_docx.dart';
import 'package:furnace/domain/services/paper/domain_quota.dart';
import 'package:furnace/domain/services/paper/paper_composer.dart';
import 'package:furnace/domain/services/paper/subject_quota.dart';

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

  group('组卷说明（配额 / 手工指定 / 保底缺口）', () {
    String build(PaperPlan plan, {PaperDocxLabels? labels}) {
      final result = buildPaperDocx(
        plan: plan,
        questions: sampleQuestions(),
        knowledgePointNames: const {'kp1': '函数单调性'},
        labels: labels ?? const PaperDocxLabels(),
      );
      return _documentXml(result);
    }

    bool hasSection(String document) => document.contains('组卷说明');

    test('默认 plan 不渲染组卷说明，附录仍只分页一次', () {
      final result = buildPaperDocx(
        plan: samplePlan(),
        questions: sampleQuestions(),
        knowledgePointNames: const {'kp1': '函数单调性'},
      );
      final document = _documentXml(result);
      expect(document, isNot(contains('组卷说明')));
      expect(document, isNot(contains('学科分布')));
      expect('<w:pageBreakBefore/>'.allMatches(document).length, 1);
    });

    test('默认 plan 的 includeCompositionNotes 开关不改变任何输出内容', () {
      final on = buildPaperDocx(
        plan: samplePlan(),
        questions: sampleQuestions(),
        knowledgePointNames: const {'kp1': '函数单调性'},
      );
      final off = buildPaperDocx(
        plan: samplePlan(),
        questions: sampleQuestions(),
        knowledgePointNames: const {'kp1': '函数单调性'},
        includeCompositionNotes: false,
      );
      expect(unzipText(off.bytes), equals(unzipText(on.bytes)));
    });

    test('学科分布按 bySubject 渲染，学科名走 subjectName 回调', () {
      final document = build(
        compositionPlan(
            bySubject: const <String, int>{'math': 2, 'physics': 1}),
      );
      expect(hasSection(document), isTrue);
      expect(document, contains('学科分布'));
      expect(document, contains('数学：2 道'));
      expect(document, contains('物理：1 道'));
    });

    test('领域分布渲染 byDomain，未覆盖领域单独列出', () {
      final document = build(
        compositionPlan(
          byDomain: const <String, int>{'物理': 1},
          domainShortfalls: const <DomainQuotaShortfall>[
            DomainQuotaShortfall(
              domain: '化学',
              minimumCount: 1,
              selectedCount: 0,
              availableCount: 0,
            ),
          ],
        ),
      );
      expect(document, contains('领域分布'));
      expect(document, contains('物理：1 道'));
      expect(document, contains('未覆盖'));
      expect(
        document.indexOf('未覆盖'),
        greaterThan(document.indexOf('领域分布')),
      );
    });

    test('手工指定渲染进卷数与三类名单', () {
      final document = build(
        compositionPlan(
          manualSelectionEnabled: true,
          manualIncludedCount: 2,
          manualMissing: const <String>['q-x'],
          manualSkipped: const <String>['q-y'],
          manualConflict: const <String>['q-z'],
        ),
      );
      expect(document, contains('手工指定'));
      expect(document, contains('进卷 2 道'));
      expect(document, contains('题库里找不到：q-x'));
      expect(document, contains('target_count 装不下：q-y'));
      expect(document, contains('与排除冲突（按排除处理）：q-z'));
    });

    test('手工指定名单为空时写「无」占位', () {
      final document = build(
        compositionPlan(
          manualSelectionEnabled: true,
          manualIncludedCount: 1,
        ),
      );
      expect(document, contains('题库里找不到：无'));
      expect(document, contains('target_count 装不下：无'));
      expect(document, contains('与排除冲突（按排除处理）：无'));
    });

    test('手工开关打开但没有数据时不渲染组卷说明', () {
      final document = build(compositionPlan(manualSelectionEnabled: true));
      expect(hasSection(document), isFalse);
    });

    test('配额挡下按学科聚合计数并按字典序输出', () {
      final document = build(
        compositionPlan(
          blockedQuestions: const <QuotaBlockedQuestion>[
            QuotaBlockedQuestion(
              questionId: 'b1',
              subjectKey: 'math',
              subjectLimit: 1,
            ),
            QuotaBlockedQuestion(
              questionId: 'b2',
              subjectKey: 'physics',
              subjectLimit: 1,
            ),
            QuotaBlockedQuestion(
              questionId: 'b3',
              subjectKey: 'math',
              subjectLimit: 1,
            ),
          ],
        ),
      );
      expect(document, contains('配额'));
      expect(document, contains('被学科上限挡下：数学 2 道、物理 1 道'));
    });

    test('配额挡下按领域聚合计数', () {
      final document = build(
        compositionPlan(
          blockedDomains: const <DomainQuotaBlockedQuestion>[
            DomainQuotaBlockedQuestion(
              questionId: 'b1',
              domain: '化学',
              domainLimit: 1,
            ),
            DomainQuotaBlockedQuestion(
              questionId: 'b2',
              domain: '化学',
              domainLimit: 1,
            ),
            DomainQuotaBlockedQuestion(
              questionId: 'b3',
              domain: '物理',
              domainLimit: 1,
            ),
          ],
        ),
      );
      expect(document, contains('被领域上限挡下：化学 2 道、物理 1 道'));
    });

    test('学科保底缺口写差几道、保底与可用候选', () {
      final document = build(
        compositionPlan(
          subjectShortfalls: const <SubjectQuotaShortfall>[
            SubjectQuotaShortfall(
              subjectKey: 'math',
              minimumCount: 3,
              selectedCount: 1,
              availableCount: 2,
            ),
          ],
        ),
      );
      expect(document, contains('保底缺口'));
      expect(
        document,
        contains('数学：差 2 道（保底 3 道，已排 1 道；可用候选 2 道）'),
      );
    });

    test('学科保底没凑到写题库里没有可用题', () {
      final document = build(
        compositionPlan(
          subjectShortfalls: const <SubjectQuotaShortfall>[
            SubjectQuotaShortfall(
              subjectKey: 'math',
              minimumCount: 2,
              selectedCount: 0,
              availableCount: 0,
            ),
          ],
        ),
      );
      expect(document, contains('数学：题库里没有可用题（保底 2 道）'));
    });

    test('领域保底缺口与未覆盖领域都如实写', () {
      final document = build(
        compositionPlan(
          domainShortfalls: const <DomainQuotaShortfall>[
            DomainQuotaShortfall(
              domain: '化学',
              minimumCount: 1,
              selectedCount: 0,
              availableCount: 0,
            ),
            DomainQuotaShortfall(
              domain: '物理',
              minimumCount: 3,
              selectedCount: 2,
              availableCount: 1,
            ),
          ],
        ),
      );
      expect(document, contains('化学：题库里没有可用题（保底 1 道）'));
      expect(
        document,
        contains('物理：差 1 道（保底 3 道，已排 2 道；可用候选 1 道）'),
      );
    });

    test('子块顺序固定：学科→领域→手工→配额→保底', () {
      final result = buildPaperDocx(
        plan: compositionPlan(
          bySubject: const <String, int>{'math': 1},
          byDomain: const <String, int>{'物理': 1},
          manualSelectionEnabled: true,
          manualIncludedCount: 1,
          blockedQuestions: const <QuotaBlockedQuestion>[
            QuotaBlockedQuestion(
              questionId: 'b1',
              subjectKey: 'math',
              subjectLimit: 1,
            ),
          ],
          subjectShortfalls: const <SubjectQuotaShortfall>[
            SubjectQuotaShortfall(
              subjectKey: 'math',
              minimumCount: 2,
              selectedCount: 1,
              availableCount: 1,
            ),
          ],
        ),
        questions: sampleQuestions(),
        knowledgePointNames: const {'kp1': '函数单调性'},
        includeGaps: false,
      );
      final document = _documentXml(result);
      final answer = document.indexOf('参考答案与解析');
      final section = document.indexOf('组卷说明');
      final subjects = document.indexOf('学科分布');
      final domains = document.indexOf('领域分布');
      final manual = document.indexOf('手工指定');
      final quota = document.indexOf('配额');
      final shortfall = document.indexOf('保底缺口');
      expect(answer, greaterThan(0));
      expect(section, greaterThan(answer));
      expect(subjects, greaterThan(section));
      expect(domains, greaterThan(subjects));
      expect(manual, greaterThan(domains));
      expect(quota, greaterThan(manual));
      expect(shortfall, greaterThan(quota));
    });

    test('有组卷说明时整文档仍只分页一次，分页落在答案区', () {
      final result = buildPaperDocx(
        plan: compositionPlan(bySubject: const <String, int>{'math': 1}),
        questions: sampleQuestions(),
        knowledgePointNames: const {'kp1': '函数单调性'},
      );
      final document = _documentXml(result);
      expect('<w:pageBreakBefore/>'.allMatches(document).length, 1);
      final breakIndex = document.indexOf('<w:pageBreakBefore/>');
      final answerIndex = document.indexOf('参考答案与解析');
      final sectionIndex = document.indexOf('组卷说明');
      expect(breakIndex, greaterThan(0));
      expect(breakIndex, lessThan(answerIndex));
      expect(sectionIndex, greaterThan(answerIndex));
    });

    test('答案区关闭时由组卷说明承担唯一分页', () {
      final result = buildPaperDocx(
        plan: compositionPlan(bySubject: const <String, int>{'math': 1}),
        questions: sampleQuestions(),
        knowledgePointNames: const {'kp1': '函数单调性'},
        includeAnswers: false,
        includeSolutions: false,
        includeReasons: false,
        includeGaps: false,
      );
      final document = _documentXml(result);
      expect(document, isNot(contains('参考答案与解析')));
      expect('<w:pageBreakBefore/>'.allMatches(document).length, 1);
      expect(
        document.indexOf('<w:pageBreakBefore/>'),
        lessThan(document.indexOf('组卷说明')),
      );
    });

    test('includeCompositionNotes=false 时不渲染组卷说明（即使 plan 带配额数据）', () {
      final result = buildPaperDocx(
        plan: compositionPlan(bySubject: const <String, int>{'math': 1}),
        questions: sampleQuestions(),
        knowledgePointNames: const {'kp1': '函数单调性'},
        includeCompositionNotes: false,
      );
      final document = _documentXml(result);
      expect(hasSection(document), isFalse);
      expect(document, isNot(contains('学科分布')));
      expect('<w:pageBreakBefore/>'.allMatches(document).length, 1);
    });

    test('仅学科分布数据也渲染组卷说明', () {
      final document = build(
        compositionPlan(bySubject: const <String, int>{'physics': 2}),
      );
      expect(hasSection(document), isTrue);
      expect(document, contains('学科分布'));
      expect(document, contains('物理：2 道'));
    });

    test('仅配额挡下数据也渲染组卷说明', () {
      final document = build(
        compositionPlan(
          blockedQuestions: const <QuotaBlockedQuestion>[
            QuotaBlockedQuestion(
              questionId: 'b1',
              subjectKey: 'math',
              subjectLimit: 1,
            ),
          ],
        ),
      );
      expect(hasSection(document), isTrue);
      expect(document, contains('配额'));
      expect(document, contains('被学科上限挡下：数学 1 道'));
    });

    test('仅领域未覆盖数据也渲染组卷说明', () {
      final document = build(
        compositionPlan(
          domainShortfalls: const <DomainQuotaShortfall>[
            DomainQuotaShortfall(
              domain: '化学',
              minimumCount: 1,
              selectedCount: 0,
              availableCount: 0,
            ),
          ],
        ),
      );
      expect(hasSection(document), isTrue);
      expect(document, contains('领域分布'));
      expect(document, contains('未覆盖'));
    });

    test('英文 labels 覆盖组卷说明的全部新标题', () {
      const labels = PaperDocxLabels(
        sectionHeading: 'Composition Notes',
        bySubjectHeading: 'Subjects',
        byDomainHeading: 'Domains',
        manualHeading: 'Manual Selection',
        quotaHeading: 'Quota Limits',
        shortfallHeading: 'Shortfalls',
        uncoveredHeading: 'Uncovered',
        nonePlaceholder: 'None',
        subjectLabel: _englishSubject,
      );
      final result = buildPaperDocx(
        plan: compositionPlan(
          bySubject: const <String, int>{'math': 2},
          byDomain: const <String, int>{'物理': 1},
          manualSelectionEnabled: true,
          manualIncludedCount: 1,
          blockedQuestions: const <QuotaBlockedQuestion>[
            QuotaBlockedQuestion(
              questionId: 'b1',
              subjectKey: 'math',
              subjectLimit: 1,
            ),
          ],
          subjectShortfalls: const <SubjectQuotaShortfall>[
            SubjectQuotaShortfall(
              subjectKey: 'math',
              minimumCount: 2,
              selectedCount: 1,
              availableCount: 1,
            ),
          ],
          domainShortfalls: const <DomainQuotaShortfall>[
            DomainQuotaShortfall(
              domain: '物理',
              minimumCount: 1,
              selectedCount: 0,
              availableCount: 0,
            ),
          ],
        ),
        questions: sampleQuestions(),
        knowledgePointNames: const {'kp1': '函数单调性'},
        labels: labels,
      );
      final document = _documentXml(result);
      expect(document, contains('Composition Notes'));
      expect(document, contains('Subjects'));
      expect(document, contains('Domains'));
      expect(document, contains('Uncovered'));
      expect(document, contains('Manual Selection'));
      expect(document, contains('Quota Limits'));
      expect(document, contains('Shortfalls'));
      expect(document, contains('Math：2 道'));
      expect(document, contains('题库里找不到：None'));
      expect(document, isNot(contains('组卷说明')));
    });

    test('学科分布只按 bySubject 写，不按题目反推', () {
      final document = build(
        compositionPlan(bySubject: const <String, int>{'physics': 5}),
      );
      expect(document, contains('物理：5 道'));
      expect(document, isNot(contains('物理：1 道')));
    });

    test('领域分布按 plan 计数书写，不按题数截断', () {
      final document = build(
        compositionPlan(byDomain: const <String, int>{'物理': 2}),
      );
      expect(document, contains('物理：2 道'));
    });
  });

  group('答案与解析截图', () {
    PaperDocxImage shot(
      String fileName, {
      String extension = 'png',
      int width = 480,
      int height = 320,
      List<int> bytes = const <int>[3, 1, 4, 1, 5],
    }) =>
        PaperDocxImage(
          bytes: Uint8List.fromList(bytes),
          extension: extension,
          pixelWidth: width,
          pixelHeight: height,
          fileName: fileName,
        );

    Map<String, PaperDocxQuestion> oneQuestion({
      List<PaperDocxImage> images = const <PaperDocxImage>[],
      List<PaperDocxImage> answerImages = const <PaperDocxImage>[],
    }) =>
        <String, PaperDocxQuestion>{
          'q1': PaperDocxQuestion(
            questionId: 'q1',
            serialNo: 'TR-00001',
            stem: '求单调区间。',
            answer: 'B',
            solution: '由定义可知……',
            images: images,
            answerImages: answerImages,
          ),
        };

    PaperDocxBuildResult buildOne({
      List<PaperDocxImage> images = const <PaperDocxImage>[],
      List<PaperDocxImage> answerImages = const <PaperDocxImage>[],
      PaperDocxLabels labels = const PaperDocxLabels(),
      bool includeAnswers = true,
      bool includeSolutions = true,
      bool includeReasons = true,
    }) =>
        buildPaperDocx(
          plan: samplePlan(
            items: <PaperItem>[paperItem('q1')],
            requestedCount: 1,
          ),
          questions: oneQuestion(images: images, answerImages: answerImages),
          knowledgePointNames: const {'kp1': '函数单调性'},
          labels: labels,
          includeAnswers: includeAnswers,
          includeSolutions: includeSolutions,
          includeReasons: includeReasons,
        );

    List<String> mediaKeys(PaperDocxBuildResult result) {
      final keys = unzipText(result.bytes)
          .keys
          .where((key) => key.startsWith('word/media/'))
          .toList()
        ..sort();
      return keys;
    }

    test('单张答案截图进 media，answerImageCount 与 imageCount 分开', () {
      final result = buildOne(
        answerImages: <PaperDocxImage>[shot('answer.png')],
      );
      final entries = unzipText(result.bytes);
      expect(entries.keys, contains('word/media/image1.png'));
      expect(result.answerImageCount, 1);
      expect(result.imageCount, 0);
      expect(result.imageSkippedCount, 0);
      final document = entries['word/document.xml']!;
      expect(document, contains('答案与解析截图'));
      expect(document, contains('<wp:inline'));
      expect(document, contains('<wp:extent'));
    });

    test('题干配图与答案截图同存：媒体两张，正文图在前、截图在附录', () {
      final result = buildOne(
        images: <PaperDocxImage>[shot('stem.png')],
        answerImages: <PaperDocxImage>[shot('answer.png')],
      );
      expect(result.imageCount, 1);
      expect(result.answerImageCount, 1);
      expect(result.imageSkippedCount, 0);
      expect(mediaKeys(result), <String>[
        'word/media/image1.png',
        'word/media/image2.png',
      ]);
      final document = _documentXml(result);
      final stemImage = document.indexOf('r:embed="rIdImg0"');
      final answerImage = document.indexOf('r:embed="rIdImg1"');
      expect(stemImage, greaterThanOrEqualTo(0));
      expect(answerImage, greaterThan(stemImage));
      expect(stemImage, lessThan(document.indexOf('参考答案与解析')));
      expect(
        document.indexOf('参考答案与解析'),
        lessThan(document.indexOf('答案与解析截图')),
      );
    });

    test('两张答案截图按参数顺序放入附录', () {
      final result = buildOne(
        answerImages: <PaperDocxImage>[
          shot('first.png'),
          shot('second.png', extension: 'jpeg'),
        ],
      );
      expect(result.answerImageCount, 2);
      expect(mediaKeys(result), <String>[
        'word/media/image1.png',
        'word/media/image2.jpeg',
      ]);
      final document = _documentXml(result);
      expect(
        document.indexOf('r:embed="rIdImg0"'),
        lessThan(document.indexOf('r:embed="rIdImg1"')),
      );
    });

    test('heic 答案截图跳过，note 带「答案截图」与文件名', () {
      final result = buildOne(
        answerImages: <PaperDocxImage>[shot('scan.heic', extension: 'heic')],
      );
      expect(result.answerImageCount, 0);
      expect(result.imageSkippedCount, 1);
      expect(result.imageSkippedNotes.length, 1);
      expect(result.imageSkippedNotes.single, contains('第 1 题答案截图'));
      expect(result.imageSkippedNotes.single, contains('scan.heic'));
      expect(result.imageSkippedNotes.single, contains('格式 heic 不支持嵌入'));
      expect(result.hasWarnings, isTrue);
      final document = _documentXml(result);
      expect(document, contains('答案与解析截图'));
      expect(mediaKeys(result), isEmpty);
    });

    test('0×0 像素的答案截图跳过并区分来源', () {
      final result = buildOne(
        answerImages: <PaperDocxImage>[
          shot('blank.png', width: 0, height: 0),
        ],
      );
      expect(result.answerImageCount, 0);
      expect(result.imageSkippedCount, 1);
      expect(result.imageSkippedNotes.single, contains('第 1 题答案截图'));
      expect(result.imageSkippedNotes.single, contains('图片字节或尺寸信息缺失'));
    });

    test('无 answerImages 时不渲染标签，输出与旧版一致', () {
      final result = buildOne();
      final document = _documentXml(result);
      expect(result.answerImageCount, 0);
      expect(result.imageCount, 0);
      expect(result.imageSkippedCount, 0);
      expect(result.hasWarnings, isFalse);
      expect(document, isNot(contains('答案与解析截图')));
    });

    test('默认构造与显式空列表的答案截图输出一致', () {
      final implicit = buildPaperDocx(
        plan: samplePlan(
          items: <PaperItem>[paperItem('q1')],
          requestedCount: 1,
        ),
        questions: <String, PaperDocxQuestion>{
          'q1': const PaperDocxQuestion(
            questionId: 'q1',
            serialNo: 'TR-00001',
            stem: '求单调区间。',
            answer: 'B',
            solution: '由定义可知……',
          ),
        },
        knowledgePointNames: const {'kp1': '函数单调性'},
      );
      final explicit = buildOne(
        answerImages: const <PaperDocxImage>[],
      );
      expect(_documentXml(implicit), _documentXml(explicit));
      expect(implicit.paragraphCount, explicit.paragraphCount);
      expect(implicit.answerImageCount, explicit.answerImageCount);
    });

    test('答案截图不改动正文（答案区之前的内容逐字相同）', () {
      final without = buildOne(images: <PaperDocxImage>[shot('stem.png')]);
      final withShot = buildOne(
        images: <PaperDocxImage>[shot('stem.png')],
        answerImages: <PaperDocxImage>[shot('answer.png')],
      );
      String bodyOf(PaperDocxBuildResult result) {
        final document = _documentXml(result);
        return document.substring(0, document.indexOf('参考答案与解析'));
      }

      expect(bodyOf(withShot), bodyOf(without));
      expect(withShot.questionCount, without.questionCount);
      expect(withShot.paragraphCount, greaterThan(without.paragraphCount));
    });

    test('答案截图标签在解析与理由之后', () {
      final result = buildOne(
        answerImages: <PaperDocxImage>[shot('answer.png')],
      );
      final document = _documentXml(result);
      expect(document.indexOf('解析：'), greaterThanOrEqualTo(0));
      expect(document.indexOf('理由：'), greaterThanOrEqualTo(0));
      expect(
        document.indexOf('解析：'),
        lessThan(document.indexOf('答案与解析截图')),
      );
      expect(
        document.indexOf('理由：'),
        lessThan(document.indexOf('答案与解析截图')),
      );
    });

    test('答案区整体关闭时答案截图也不渲染', () {
      final result = buildOne(
        answerImages: <PaperDocxImage>[shot('answer.png')],
        includeAnswers: false,
        includeSolutions: false,
        includeReasons: false,
      );
      expect(result.answerImageCount, 0);
      expect(mediaKeys(result), isEmpty);
      expect(_documentXml(result), isNot(contains('答案与解析截图')));
    });

    test('标签行可被 labels 覆盖（英文）', () {
      final result = buildOne(
        answerImages: <PaperDocxImage>[shot('answer.png')],
        labels: const PaperDocxLabels(answerImagesLabel: 'Answer Screenshots'),
      );
      final document = _documentXml(result);
      expect(document, contains('Answer Screenshots'));
      expect(document, isNot(contains('答案与解析截图')));
    });

    test('题干配图与答案截图同时被跳过时 note 能区分来源', () {
      final result = buildOne(
        images: <PaperDocxImage>[shot('stem.heic', extension: 'heic')],
        answerImages: <PaperDocxImage>[shot('scan.heic', extension: 'heic')],
      );
      expect(result.imageSkippedCount, 2);
      expect(result.imageCount, 0);
      expect(result.answerImageCount, 0);
      expect(
        result.imageSkippedNotes
            .any((note) => note.contains('第 1 题（stem.heic）')),
        isTrue,
      );
      expect(
        result.imageSkippedNotes.any(
          (note) => note.contains('第 1 题答案截图（scan.heic）'),
        ),
        isTrue,
      );
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

/// 只带组卷说明数据的 plan：题目固定 1 道（q1 内容完整），配额/手工数据按参数给。
PaperPlan compositionPlan({
  Map<String, int> bySubject = const <String, int>{},
  Map<String, int> byDomain = const <String, int>{},
  List<QuotaBlockedQuestion> blockedQuestions = const <QuotaBlockedQuestion>[],
  List<DomainQuotaBlockedQuestion> blockedDomains =
      const <DomainQuotaBlockedQuestion>[],
  List<SubjectQuotaShortfall> subjectShortfalls =
      const <SubjectQuotaShortfall>[],
  List<DomainQuotaShortfall> domainShortfalls = const <DomainQuotaShortfall>[],
  bool manualSelectionEnabled = false,
  int manualIncludedCount = 0,
  List<String> manualMissing = const <String>[],
  List<String> manualSkipped = const <String>[],
  List<String> manualConflict = const <String>[],
}) =>
    PaperPlan(
      items: <PaperItem>[paperItem('q1')],
      uncoveredKnowledgePointIds: const <String>[],
      deferredKnowledgePointIds: const <String>[],
      byKnowledgePoint: const <String, int>{'kp1': 1},
      candidateCount: 3,
      requestedCount: 1,
      overallNeed: 1.0,
      weights: const PaperWeights(),
      bySubject: bySubject,
      quotaBlockedQuestions: blockedQuestions,
      subjectShortfalls: subjectShortfalls,
      byDomain: byDomain,
      quotaBlockedByDomain: blockedDomains,
      domainShortfalls: domainShortfalls,
      manualSelectionEnabled: manualSelectionEnabled,
      manualIncludedCount: manualIncludedCount,
      manualMissingQuestionIds: manualMissing,
      manualSkippedQuestionIds: manualSkipped,
      manualConflictQuestionIds: manualConflict,
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
