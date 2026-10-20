import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';

/// 题源链接写入/清除（`docs/QUESTION_BANK_DESIGN.md` §13）：
/// 链接是外部字符串，与封闭词表的来源分级分开写；`null` 不动、空串清空。
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

  test('写入题源链接三个字段，外部空白被归一', () async {
    final ingested = await repo.ingest(const QuestionDraft(stem: '有原题链接的题'));

    final changed = await repo.updateSourceLinks(
      ingested.question.id,
      sourceUrl: '  https://zujuan.xkw.com/10q35583902.html  ',
      zujuanQuestionId: ' 35583902 ',
      zujuanBankId: ' 10 ',
    );

    expect(changed, isTrue);
    final after = (await repo.byId(ingested.question.id))!;
    expect(after.sourceUrl, 'https://zujuan.xkw.com/10q35583902.html');
    expect(after.zujuanQuestionId, '35583902');
    expect(after.zujuanBankId, '10');
  });

  test('空串与全空白把对应列清空成 null', () async {
    final ingested = await repo.ingest(
      const QuestionDraft(
        stem: '链接要能删掉',
        sourceUrl: 'https://example.com/p/1',
        zujuanQuestionId: '111',
        zujuanBankId: '10',
      ),
    );

    final changed = await repo.updateSourceLinks(
      ingested.question.id,
      sourceUrl: '',
      zujuanQuestionId: '   ',
      zujuanBankId: '',
    );

    expect(changed, isTrue);
    final after = (await repo.byId(ingested.question.id))!;
    expect(after.sourceUrl, isNull);
    expect(after.zujuanQuestionId, isNull);
    expect(after.zujuanBankId, isNull);
  });

  test('只改一个链接字段时另外两个保持原样', () async {
    final ingested = await repo.ingest(
      const QuestionDraft(
        stem: '只改一个',
        sourceUrl: 'https://example.com/p/1',
        zujuanQuestionId: '111',
        zujuanBankId: '10',
      ),
    );

    await repo.updateSourceLinks(
      ingested.question.id,
      zujuanQuestionId: '222',
    );

    final after = (await repo.byId(ingested.question.id))!;
    expect(after.sourceUrl, 'https://example.com/p/1');
    expect(after.zujuanQuestionId, '222');
    expect(after.zujuanBankId, '10');
  });

  test('不传任何字段时只更新 updatedAt，链接与其它列都不动', () async {
    final ingested = await repo.ingest(
      const QuestionDraft(
        stem: '什么都不改',
        answer: 'B',
        sourceUrl: 'https://example.com/p/1',
        sourceLevel: 'gaokao',
        sourceLabel: '2024 某卷',
        year: 2024,
        region: '湖南',
      ),
      now: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final before = (await repo.byId(ingested.question.id))!;

    final changed = await repo.updateSourceLinks(
      ingested.question.id,
      now: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    expect(changed, isTrue);
    final after = (await repo.byId(ingested.question.id))!;
    expect(after.sourceUrl, before.sourceUrl);
    expect(after.sourceLevel, before.sourceLevel);
    expect(after.sourceLabel, before.sourceLabel);
    expect(after.year, before.year);
    expect(after.region, before.region);
    expect(after.stem, before.stem);
    expect(after.answer, before.answer);
    expect(after.updatedAt, 2000);
  });

  test('不存在的 id 返回 false，不抛异常', () async {
    final changed = await repo.updateSourceLinks(
      'q-not-exist',
      sourceUrl: 'https://example.com/p/1',
    );

    expect(changed, isFalse);
    expect(await repo.all(), isEmpty);
  });

  test('改链接不碰来源分级，也不碰题干答案与加工列', () async {
    final ingested = await repo.ingest(
      const QuestionDraft(
        stem: '链接与来源元信息互不影响',
        answer: 'C',
        solution: '解析文本',
        sourceLevel: 'elite_school',
        sourceLabel: '某校联考',
        year: 2023,
        region: '湖北',
      ),
    );
    await repo.updateProcessing(ingested.question.id, state: 'processed');
    final before = (await repo.byId(ingested.question.id))!;

    await repo.updateSourceLinks(
      ingested.question.id,
      sourceUrl: 'https://zujuan.xkw.com/10q35583902.html',
      zujuanQuestionId: '35583902',
      zujuanBankId: '10',
    );

    final after = (await repo.byId(ingested.question.id))!;
    expect(after.sourceUrl, 'https://zujuan.xkw.com/10q35583902.html');
    expect(after.sourceLevel, before.sourceLevel);
    expect(after.sourceLabel, before.sourceLabel);
    expect(after.year, before.year);
    expect(after.region, before.region);
    expect(after.stem, before.stem);
    expect(after.answer, before.answer);
    expect(after.solution, before.solution);
    expect(after.state, before.state);
  });

  test('三字段可同时写入、也可同时清空（往返）', () async {
    final ingested = await repo.ingest(const QuestionDraft(stem: '往返写清'));

    await repo.updateSourceLinks(
      ingested.question.id,
      sourceUrl: 'https://zujuan.xkw.com/10q35583902.html',
      zujuanQuestionId: '35583902',
      zujuanBankId: '10',
    );
    var after = (await repo.byId(ingested.question.id))!;
    expect(after.sourceUrl, isNotNull);
    expect(after.zujuanQuestionId, '35583902');

    await repo.updateSourceLinks(
      ingested.question.id,
      sourceUrl: '',
      zujuanQuestionId: '',
      zujuanBankId: '',
    );
    after = (await repo.byId(ingested.question.id))!;
    expect(after.sourceUrl, isNull);
    expect(after.zujuanQuestionId, isNull);
    expect(after.zujuanBankId, isNull);
  });

  test('入库时带的链接不需要再写一遍（ingest 原样保存）', () async {
    final ingested = await repo.ingest(
      const QuestionDraft(
        stem: '入库就有链接',
        sourceUrl: 'https://example.com/p/9',
        zujuanQuestionId: '900',
        zujuanBankId: '10',
      ),
    );

    final question = (await repo.byId(ingested.question.id))!;
    expect(question.sourceUrl, 'https://example.com/p/9');
    expect(question.zujuanQuestionId, '900');
    expect(question.zujuanBankId, '10');
  });
}
