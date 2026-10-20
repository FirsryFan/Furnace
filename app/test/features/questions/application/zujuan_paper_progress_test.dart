import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/domain/services/questions/question_number.dart'
    show kUnnumberedQuestionLabel;
import 'package:furnace/domain/services/zujuan/zujuan_paper_extract.dart';
import 'package:furnace/features/questions/application/zujuan_paper_progress.dart';

/// 整卷页对照（轮次一百三十三 task-88）：把试卷页抽取结果和题库对上。
///
/// 这里用**手工构造的 ZujuanPaperExtract**（解析器本身由
/// test/domain/services/zujuan/zujuan_paper_extract_test.dart 覆盖），只锁对照
/// 口径：顺序跟试卷页、多行取最新、未编号的显示、缺题链接的生成与缺失。
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

  ZujuanPaperExtract extract({
    String? paperId = '3076310',
    String? bankId = '10',
    String? title = '2026 届高三上期末',
    List<int> questionIds = const <int>[],
    List<String> warnings = const <String>[],
    bool truncated = false,
  }) =>
      ZujuanPaperExtract(
        paperId: paperId,
        bankId: bankId,
        title: title,
        questionIds: questionIds,
        warnings: warnings,
        truncated: truncated,
      );

  Future<Question> seed(
    String stem, {
    String? zujuanQuestionId,
    String? sourceUrl,
    DateTime? now,
  }) async {
    final result = await repo.ingest(
      QuestionDraft(
        stem: stem,
        zujuanQuestionId: zujuanQuestionId,
        sourceUrl: sourceUrl,
      ),
      now: now,
    );
    return result.question;
  }

  test('空抽取（无标题无题号）→ 空结果，计数全 0', () async {
    final progress = await loadZujuanPaperProgress(
      repository: repo,
      extract: extract(paperId: null, bankId: null, title: null),
    );

    expect(progress.isEmpty, isTrue);
    expect(progress.questionCount, 0);
    expect(progress.matchedCount, 0);
    expect(progress.missingCount, 0);
    expect(progress.matched, isEmpty);
    expect(progress.missingQuestionIds, isEmpty);
    expect(progress.missingLinks, isEmpty);
    expect(progress.hasMissingLinks, isFalse);
  });

  test('只有标题没有题号 → 不算空抽取，但也没有可对照的题', () async {
    final progress = await loadZujuanPaperProgress(
      repository: repo,
      extract: extract(paperId: null, bankId: null),
    );

    expect(progress.isEmpty, isFalse);
    expect(progress.title, '2026 届高三上期末');
    expect(progress.questionCount, 0);
    expect(progress.matched, isEmpty);
    expect(progress.missingQuestionIds, isEmpty);
  });

  test('全缺：缺题按试卷页顺序、链接用 bankId 生成', () async {
    final progress = await loadZujuanPaperProgress(
      repository: repo,
      extract: extract(questionIds: <int>[35583902, 35583903, 35583904]),
    );

    expect(progress.isEmpty, isFalse);
    expect(progress.questionCount, 3);
    expect(progress.matchedCount, 0);
    expect(progress.missingCount, 3);
    expect(progress.missingQuestionIds, <String>[
      '35583902',
      '35583903',
      '35583904',
    ]);
    expect(progress.missingLinks, <String>[
      'https://zujuan.xkw.com/10q35583902.html',
      'https://zujuan.xkw.com/10q35583903.html',
      'https://zujuan.xkw.com/10q35583904.html',
    ]);
    expect(progress.hasMissingLinks, isTrue);
  });

  test('缺题但没 bankId：链接给不出来，hasMissingLinks 为 false', () async {
    final progress = await loadZujuanPaperProgress(
      repository: repo,
      extract: extract(bankId: null, questionIds: <int>[100, 200]),
    );

    expect(progress.missingCount, 2);
    expect(progress.missingQuestionIds, <String>['100', '200']);
    expect(progress.missingLinks, isEmpty);
    expect(progress.hasMissingLinks, isFalse);
    expect(progress.missingLinksText, '');
  });

  test('部分命中：命中行带题号 / 题干预览 / 题源链接，缺的进缺题清单', () async {
    await seed(
      '已知函数 f(x)=x^2，求单调区间。',
      zujuanQuestionId: '200',
      sourceUrl: 'https://zujuan.xkw.com/10q200.html',
    );

    final progress = await loadZujuanPaperProgress(
      repository: repo,
      extract: extract(questionIds: <int>[100, 200, 300]),
    );

    expect(progress.matchedCount, 1);
    expect(progress.matched.single.zujuanQuestionId, '200');
    expect(progress.matched.single.serialLabel, 'TR-00001');
    expect(progress.matched.single.stemPreview, '已知函数 f(x)=x^2，求单调区间。');
    expect(progress.matched.single.sourceUrl,
        'https://zujuan.xkw.com/10q200.html');
    expect(progress.missingQuestionIds, <String>['100', '300']);
    expect(progress.missingLinks, <String>[
      'https://zujuan.xkw.com/10q100.html',
      'https://zujuan.xkw.com/10q300.html',
    ]);
  });

  test('命中顺序跟试卷页走，不按题号或入库时间排', () async {
    final third = await seed('试卷页第 1 道的题', zujuanQuestionId: '300');
    final first = await seed('试卷页第 3 道的题', zujuanQuestionId: '100');

    final progress = await loadZujuanPaperProgress(
      repository: repo,
      extract: extract(questionIds: <int>[300, 999, 100]),
    );

    expect(progress.matched.map((item) => item.questionId).toList(), <String>[
      third.id,
      first.id,
    ]);
    expect(progress.missingQuestionIds, <String>['999']);
  });

  test('同一组卷网 id 多行：命中取 updatedAt 最新那行', () async {
    await seed(
      '同 id 旧行',
      zujuanQuestionId: '777',
      now: DateTime(2026, 10, 1, 8),
    );
    final newer = await seed(
      '同 id 新行',
      zujuanQuestionId: '777',
      now: DateTime(2026, 10, 2, 8),
    );

    final progress = await loadZujuanPaperProgress(
      repository: repo,
      extract: extract(questionIds: <int>[777]),
    );

    expect(progress.matched.single.questionId, newer.id);
    expect(progress.missingQuestionIds, isEmpty);
  });

  test('题干预览压空白后截断到 60 字，末尾带省略号', () async {
    final longStem = '第一行\n第二行   有   很多空白${'甲' * 60}';
    await seed(longStem, zujuanQuestionId: '555');

    final progress = await loadZujuanPaperProgress(
      repository: repo,
      extract: extract(questionIds: <int>[555]),
    );

    final preview = progress.matched.single.stemPreview;
    expect(preview.contains('\n'), isFalse);
    expect(preview.contains('  '), isFalse);
    expect(preview.endsWith('…'), isTrue);
    expect(preview.runes.length, kZujuanPaperStemPreviewLength + 1);
    expect(preview.startsWith('第一行 第二行 有 很多空白'), isTrue);
  });

  test('没编号的题目显示占位而不是崩', () async {
    final ms = DateTime(2026, 10, 5, 8).millisecondsSinceEpoch;
    await db.into(db.questions).insert(
          QuestionsCompanion.insert(
            id: 'q-manual-unnumbered',
            stem: '导入时没带编号的题',
            zujuanQuestionId: const Value<String?>('900'),
            createdAt: ms,
            updatedAt: ms,
          ),
        );

    final progress = await loadZujuanPaperProgress(
      repository: repo,
      extract: extract(questionIds: <int>[900]),
    );

    expect(progress.matched.single.serialLabel, kUnnumberedQuestionLabel);
    expect(progress.matched.single.questionId, 'q-manual-unnumbered');
  });

  test('缺题链接文本一行一个，可直接进剪贴板', () async {
    final progress = await loadZujuanPaperProgress(
      repository: repo,
      extract: extract(questionIds: <int>[11, 22]),
    );

    expect(
      progress.missingLinksText,
      'https://zujuan.xkw.com/10q11.html\n'
      'https://zujuan.xkw.com/10q22.html',
    );
  });

  test('标题 / bankId / warnings / truncated 原样透传', () async {
    final progress = await loadZujuanPaperProgress(
      repository: repo,
      extract: extract(
        title: '某校 2026 高三一模',
        bankId: '12',
        questionIds: <int>[1],
        warnings: <String>['重复题号已去重'],
        truncated: true,
      ),
    );

    expect(progress.title, '某校 2026 高三一模');
    expect(progress.bankId, '12');
    expect(progress.warnings, <String>['重复题号已去重']);
    expect(progress.truncated, isTrue);
  });

  test('toJson 给 UI/工具用的键齐全', () async {
    await seed('命中的题', zujuanQuestionId: '1');
    final progress = await loadZujuanPaperProgress(
      repository: repo,
      extract: extract(questionIds: <int>[1, 2]),
    );

    final json = progress.toJson();

    expect(json['question_count'], 2);
    expect(json['matched_count'], 1);
    expect(json['missing_count'], 1);
    expect(json['is_empty'], isFalse);
    expect((json['matched'] as List).length, 1);
    expect(
      (json['matched'] as List).single,
      containsPair('zujuan_question_id', '1'),
    );
    expect(json['missing_question_ids'], <String>['2']);
  });
}
