import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/domain/services/zujuan/zujuan_link.dart';
import 'package:furnace/domain/services/zujuan/zujuan_paste.dart';
import 'package:furnace/features/questions/application/zujuan_paste_import.dart';

/// 粘贴组卷网题面 → 题库草稿装配层（v26 来源字段的写入口径）。
///
/// 这里不重复测解析器（`test/domain/services/zujuan/zujuan_paste_test.dart` 已
/// 覆盖），只锁"解析结果 → QuestionDraft"这段翻译的契约：来源字段落库、状态
/// 是 raw、题干为空不写库、选项顺序与不猜对错。
void main() {
  ZujuanPastedQuestion pasted({
    int? ordinal,
    String stem = '下列关于光合作用的说法正确的是（ ）',
    List<ZujuanPastedOption> options = const <ZujuanPastedOption>[],
    String? answer,
    String? solution,
    String? sourceLabel,
    int? year,
    String? region,
    List<String> knowledgePoints = const <String>[],
    String? zujuanQuestionId,
    String? zujuanBankId,
    String? sourceUrl,
    List<String> warnings = const <String>[],
  }) =>
      ZujuanPastedQuestion(
        ordinal: ordinal,
        stem: stem,
        options: options,
        answer: answer,
        solution: solution,
        sourceLabel: sourceLabel,
        year: year,
        region: region,
        knowledgePoints: knowledgePoints,
        zujuanQuestionId: zujuanQuestionId,
        zujuanBankId: zujuanBankId,
        sourceUrl: sourceUrl,
        warnings: warnings,
      );

  group('单条：字段搬运', () {
    test('全字段：来源三列落进草稿，状态 raw、origin zujuan', () {
      final draft = zujuanDraftFromPasted(
        pasted(
          ordinal: 3,
          answer: ' A ',
          solution: ' 【解析】由光反应可知… ',
          sourceLabel: '2024届湖南省长沙市雅礼中学高三一模',
          year: 2024,
          region: '湖南',
          knowledgePoints: const <String>['光合作用'],
          zujuanQuestionId: '123456',
          zujuanBankId: '11',
          sourceUrl: 'https://zujuan.xkw.com/11q123456.html',
        ),
        subjectKey: 'biology',
      );

      expect(draft.stem, '下列关于光合作用的说法正确的是（ ）');
      expect(draft.answer, 'A', reason: '答案外侧空白要 trim');
      expect(draft.solution, '【解析】由光反应可知…');
      expect(draft.subjectKey, 'biology');
      expect(draft.sourceLevel, 'school', reason: '粘贴来的题默认学校题');
      expect(draft.sourceLabel, '2024届湖南省长沙市雅礼中学高三一模');
      expect(draft.year, 2024);
      expect(draft.region, '湖南');
      expect(draft.sourceUrl, 'https://zujuan.xkw.com/11q123456.html');
      expect(draft.zujuanQuestionId, '123456');
      expect(draft.zujuanBankId, '11');
      expect(draft.origin, 'zujuan');
      expect(draft.state, 'raw');
      expect(draft.questionType, 'solution');
      expect(draft.difficulty, isNull);
      expect(draft.tagIds, isEmpty);
    });

    test('选项按原顺序编号，isCorrect 一律 false（不猜对错）', () {
      final draft = zujuanDraftFromPasted(
        pasted(
          options: const <ZujuanPastedOption>[
            ZujuanPastedOption(label: 'A', content: '只在叶绿体中进行'),
            ZujuanPastedOption(label: 'B', content: '需要光'),
            ZujuanPastedOption(label: 'C', content: '产生 ATP'),
          ],
          answer: 'B',
        ),
        subjectKey: 'biology',
      );

      expect(draft.options, hasLength(3));
      expect(
        [for (final o in draft.options) '${o.label}:${o.sortOrder}'],
        <String>['A:0', 'B:1', 'C:2'],
      );
      expect([for (final o in draft.options) o.content], <String>[
        '只在叶绿体中进行',
        '需要光',
        '产生 ATP',
      ]);
      expect(
        [for (final o in draft.options) o.isCorrect],
        <bool>[false, false, false],
        reason: '答案文本可能分小问，自动标正确选项会错标',
      );
    });

    test('stemOverride 优先，且两侧空白被 trim', () {
      final draft = zujuanDraftFromPasted(
        pasted(stem: '把题面改成这句'),
        subjectKey: 'biology',
        stemOverride: '  人工改过的题干  ',
      );
      expect(draft.stem, '人工改过的题干');
    });

    test('题干为空（含只输空白）抛 ArgumentError，不写空题', () {
      expect(
        () => zujuanDraftFromPasted(pasted(stem: '   '), subjectKey: 'biology'),
        throwsArgumentError,
      );
      expect(
        () => zujuanDraftFromPasted(
          pasted(stem: '原文'),
          subjectKey: 'biology',
          stemOverride: '   ',
        ),
        throwsArgumentError,
        reason: '改过的题干为空同样是空题',
      );
    });

    test('空答案/空解析/空白地区 → null；缺 sourceLabel → 空串', () {
      final draft = zujuanDraftFromPasted(
        pasted(answer: '  ', solution: '', region: '   '),
        subjectKey: 'biology',
      );
      expect(draft.answer, isNull);
      expect(draft.solution, isNull);
      expect(draft.region, isNull);
      expect(draft.sourceLabel, '');
      expect(draft.year, isNull);
    });

    test('自定义来源档位与学科直接透传', () {
      final draft = zujuanDraftFromPasted(
        pasted(),
        subjectKey: 'math',
        defaultSourceLevel: 'gaokao',
      );
      expect(draft.subjectKey, 'math');
      expect(draft.sourceLevel, 'gaokao');
    });
  });

  group('单条：来源链接', () {
    test('没有原链接时用 bankId + questionId 拼详情页链接', () {
      final draft = zujuanDraftFromPasted(
        pasted(zujuanQuestionId: '123456', zujuanBankId: '11'),
        subjectKey: 'biology',
      );
      expect(draft.sourceUrl, 'https://zujuan.xkw.com/11q123456.html');
      expect(
        draft.sourceUrl,
        zujuanQuestionDetailUrl(bankId: '11', questionId: '123456'),
        reason: '链接由既有构造器生成，口径只有一处',
      );
    });

    test('原链接优先于拼出来的链接', () {
      final draft = zujuanDraftFromPasted(
        pasted(
          zujuanQuestionId: '123456',
          zujuanBankId: '11',
          sourceUrl: 'https://zujuan.xkw.com/gzsw/11q123456.html#comment',
        ),
        subjectKey: 'biology',
      );
      expect(
        draft.sourceUrl,
        'https://zujuan.xkw.com/gzsw/11q123456.html#comment',
      );
    });

    test('只有 questionId 缺 bankId：认题 id 保留，但不猜链接', () {
      final draft = zujuanDraftFromPasted(
        pasted(zujuanQuestionId: '123456'),
        subjectKey: 'biology',
      );
      expect(draft.zujuanQuestionId, '123456');
      expect(draft.zujuanBankId, isNull);
      expect(draft.sourceUrl, isNull);
    });

    test('id 是空白串时按没有处理', () {
      final draft = zujuanDraftFromPasted(
        pasted(zujuanQuestionId: '  ', zujuanBankId: ' '),
        subjectKey: 'biology',
      );
      expect(draft.zujuanQuestionId, isNull);
      expect(draft.zujuanBankId, isNull);
      expect(draft.sourceUrl, isNull);
    });
  });

  group('批量：粘贴文本 → 草稿列表', () {
    const twoQuestions = '''
1. 下列关于光合作用的说法正确的是（ ）
A. 只在叶绿体中进行
B. 需要光
【答案】B
【解析】略
2. 有氧呼吸的主要场所是（ ）
A. 线粒体
B. 细胞质基质
【答案】A
''';

    test('两题按原顺序生成两条草稿', () {
      final drafts = zujuanDraftsFromPaste(twoQuestions, subjectKey: 'biology');
      expect(drafts, hasLength(2));
      expect(drafts[0].stem, contains('光合作用'));
      expect(drafts[0].options, hasLength(2));
      expect([for (final o in drafts[0].options) o.label], <String>['A', 'B']);
      expect(drafts[0].answer, 'B');
      expect(drafts[1].stem, contains('有氧呼吸'));
      expect(drafts[1].answer, 'A');
      for (final draft in drafts) {
        expect(draft.origin, 'zujuan');
        expect(draft.state, 'raw');
        expect(draft.subjectKey, 'biology');
        expect(draft.sourceLevel, 'school');
      }
    });

    test('空文本 / 纯空白 → 空列表', () {
      expect(zujuanDraftsFromPaste('', subjectKey: 'biology'), isEmpty);
      expect(
        zujuanDraftsFromPaste('   \n\t ', subjectKey: 'biology'),
        isEmpty,
      );
    });

    test('只有元数据没有题干：按兜底草稿保留，不静默丢内容', () {
      // 解析器对"认不出题面"的输入给 stem=原文 的兜底草稿（isPartial=true），
      // 题干非空所以批量不跳过——是否入库由确认界面的勾选与题干编辑把关。
      final drafts = zujuanDraftsFromPaste('【答案】B', subjectKey: 'biology');
      expect(drafts, hasLength(1));
      expect(drafts.single.stem, '【答案】B');
    });

    test('批量也补链接：只看到 id 时草稿带详情页链接', () {
      final drafts = zujuanDraftsFromPaste(
        '1. 含链接的题\n来源：https://zujuan.xkw.com/10q420.html\n【答案】A',
        subjectKey: 'biology',
      );
      expect(drafts, isNotEmpty);
      expect(drafts.first.sourceUrl, contains('/10q420.html'));
      expect(drafts.first.zujuanQuestionId, '420');
      expect(drafts.first.zujuanBankId, '10');
    });

    test('默认来源档位可改，批量逐条透传', () {
      final drafts = zujuanDraftsFromPaste(
        twoQuestions,
        subjectKey: 'biology',
        defaultSourceLevel: 'provincial_diagnostic',
      );
      expect(drafts, hasLength(2));
      for (final draft in drafts) {
        expect(draft.sourceLevel, 'provincial_diagnostic');
      }
    });
  });
}
