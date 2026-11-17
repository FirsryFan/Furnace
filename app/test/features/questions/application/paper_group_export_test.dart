/// 题组卷面展开的端到端测试：一篇文章 + N 个小问 = **1 道题**。
///
/// 钉住四件事（缺一条就会回到"只出现代表题"）：
/// 1. `readPaperCorpus` 折叠后候选带全组 id，且按小问顺序（serialNo 升序）；
/// 2. `PaperComposer` 把 groupQuestionIds 带进 `PaperItem`（题数仍按题组）；
/// 3. 卷面材料只出现一次、小问连续编号（1）（2）并各自带选项/答案；
/// 4. 答案区仍是「题号 + 答案」形状：题号只出一次，小问只加（i）标号。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/domain/services/paper/paper_composer.dart';
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
    support = Directory.systemTemp.createTempSync('furnace_group_paper_');
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

  const sourceLabel = '2026 届高三上期末·语文';

  Future<Question> seed({
    required String question,
    String? answer,
    String? solution,
    String questionType = 'open',
    List<QuestionOptionDraft> options = const <QuestionOptionDraft>[],
    String stemPrefix = '【材料 S1-M1】\n阅读下面的文字，完成下面小题。\n种植入门问答：凡种植一株树，须依法种植。',
    String label = sourceLabel,
  }) async {
    final ingested = await repo.ingest(
      QuestionDraft(
        stem: '$stemPrefix\n\n【题目】\n$question',
        answer: answer,
        solution: solution,
        subjectKey: 'chinese',
        sourceLevel: 'school',
        sourceLabel: label,
        questionType: questionType,
        options: options,
        state: 'structured',
      ),
    );
    return ingested.question;
  }

  String documentXml(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final file = archive.files.firstWhere((f) => f.name == 'word/document.xml');
    return utf8.decode(file.content as List<int>);
  }

  int countOf(String text, String needle) {
    var count = 0;
    var index = text.indexOf(needle);
    while (index >= 0) {
      count++;
      index = text.indexOf(needle, index + needle.length);
    }
    return count;
  }

  test('材料 + 2 小问：候选折 1 道、卷面材料出现 1 次、小问（1）（2）都在', () async {
    final first = await seed(
      question: '下列对材料相关内容的理解，正确的一项是（　）',
      answer: 'B',
      solution: '第一问解析。',
      questionType: 'single_choice',
      options: const <QuestionOptionDraft>[
        QuestionOptionDraft(label: 'A', content: '甲选项'),
        QuestionOptionDraft(label: 'B', content: '乙选项', isCorrect: true),
      ],
    );
    final second = await seed(
      question: '请结合材料谈谈你的看法。',
      answer: '第二小问答案',
      solution: '第二问解析。',
    );

    // 1) 题库读表：同材料两行 = 1 个候选，候选带全组 id（按 serialNo 升序）。
    final corpus = await readPaperCorpus(db);
    expect(corpus.candidates.length, 1);
    expect(corpus.candidates.single.groupQuestionIds, <String>[
      first.id,
      second.id,
    ]);

    // 2) 组卷：题数按题组计（1 道），item 带全组 id。
    final plan = PaperComposer.compose(
      candidates: corpus.candidates,
      spec: const PaperSpec(targetCount: 1),
    );
    expect(plan.items.length, 1);
    expect(plan.items.single.groupQuestionIds, <String>[
      first.id,
      second.id,
    ]);

    // 3) 导出卷面：题数 1、展开 1 组 2 小问；材料只出现一次、小问都在。
    final result = await buildPaperDocxExport(
      db: db,
      mediaStore: mediaStore,
      plan: plan,
      generatedAt: DateTime(2026, 11, 18, 6, 30),
    );
    expect(result.report.questionCount, 1, reason: '题数按题组计，不按小问计');
    expect(result.report.expandedGroupCount, 1);
    expect(result.report.expandedSubQuestionCount, 2);

    final xml = documentXml(result.bytes);
    expect(countOf(xml, '种植入门问答'), 1, reason: '材料只出现一次');
    expect(xml, contains('下列对材料相关内容的理解'));
    expect(xml, contains('请结合材料谈谈你的看法'));
    expect(xml, contains('（1）'));
    expect(xml, contains('（2）'));
    // 小问顺序 = 组内顺序（第 1 小问在前）。
    expect(
      xml.indexOf('下列对材料相关内容的理解') < xml.indexOf('请结合材料谈谈你的看法'),
      isTrue,
    );
    // 选项仍跟各自小问走。
    expect(xml, contains('甲选项'));
    expect(xml, contains('乙选项'));

    // 4) 答案区仍是「题号 + 答案」：小问标号各出现 3 次（卷面 / 答案 / 解析），
    //    答案区不重复材料、不搬题干。
    expect(countOf(xml, '（1）'), 3);
    expect(countOf(xml, '（2）'), 3);
    expect(countOf(xml, '第二小问答案'), 1);
    expect(countOf(xml, '种植入门问答'), 1);
  });

  test('旧数据缺【题目】分隔：不硬猜，回落单题并在导出提示里写明', () async {
    const oldMaterial = '【材料 S2-M1】\n旧数据材料正文：没有题目分隔行。';
    final first = await repo.ingest(
      QuestionDraft(
        stem: '$oldMaterial\n\n（1）旧数据小问一',
        answer: '一',
        subjectKey: 'chinese',
        sourceLevel: 'school',
        sourceLabel: sourceLabel,
        state: 'structured',
      ),
    );
    final second = await repo.ingest(
      QuestionDraft(
        stem: '$oldMaterial\n\n（2）旧数据小问二',
        answer: '二',
        subjectKey: 'chinese',
        sourceLevel: 'school',
        sourceLabel: sourceLabel,
        state: 'structured',
      ),
    );
    final corpus = await readPaperCorpus(db);
    expect(corpus.candidates.length, 1);
    expect(corpus.candidates.single.groupQuestionIds, <String>[
      first.question.id,
      second.question.id,
    ]);

    final plan = PaperComposer.compose(
      candidates: corpus.candidates,
      spec: const PaperSpec(targetCount: 1),
    );
    final result = await buildPaperDocxExport(
      db: db,
      mediaStore: mediaStore,
      plan: plan,
      generatedAt: DateTime(2026, 11, 18, 6, 30),
    );
    expect(result.report.questionCount, 1);
    expect(result.report.expandedGroupCount, 0, reason: '无法切分时不假装展开');
    final xml = documentXml(result.bytes);
    expect(xml, contains('题面缺少【题目】分隔行，题组未展开'));
  });
}
