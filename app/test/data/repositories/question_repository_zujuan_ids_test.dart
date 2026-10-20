import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';

/// 按组卷网 questionid 批量查题（整卷页对照的数据层，轮次一百三十三 task-88）。
///
/// 只锁数据层契约：空集不查库、trim 后精确匹配、同 id 多行按 updatedAt 降序 /
/// id 升序、没有组卷网 id 的行不出现。对照结果怎么拼是应用层的事
/// （test/features/questions/application/zujuan_paper_progress_test.dart）。
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

  Future<Question> seed(
    String stem, {
    String? zujuanQuestionId,
    String? zujuanBankId,
    String? sourceUrl,
    DateTime? now,
  }) async {
    final result = await repo.ingest(
      QuestionDraft(
        stem: stem,
        zujuanQuestionId: zujuanQuestionId,
        zujuanBankId: zujuanBankId,
        sourceUrl: sourceUrl,
      ),
      now: now,
    );
    return result.question;
  }

  test('空集合与全空白集合返回空 map（不命中任何行）', () async {
    await seed('有 id 的题', zujuanQuestionId: '35583902');

    expect(await repo.byZujuanQuestionIds(const <String>{}), isEmpty);
    expect(await repo.byZujuanQuestionIds(<String>{'', '   ', '\t'}), isEmpty);
  });

  test('只返回有组卷网 id 的行，输入 trim 后精确相等', () async {
    final withId = await seed('有 id 的题', zujuanQuestionId: '35583902');
    await seed('手写题，没有组卷网 id');

    final map = await repo.byZujuanQuestionIds(
      <String>{' 35583902 ', '99999999'},
    );

    expect(map.keys.toList(), <String>['35583902']);
    expect(map['35583902']!.single.id, withId.id);
  });

  test('不做大小写/前导零归一：题库里存什么就只匹配什么', () async {
    await seed('带前导零的 id', zujuanQuestionId: '0042');

    final zeroPadded = await repo.byZujuanQuestionIds(<String>{'0042'});
    final plain = await repo.byZujuanQuestionIds(<String>{'42'});

    expect(zeroPadded.keys.toList(), <String>['0042']);
    expect(plain, isEmpty);
  });

  test('不同组卷网 id 分组返回，组内顺序稳定', () async {
    final a = await seed('A 题', zujuanQuestionId: '100');
    final b = await seed('B 题', zujuanQuestionId: '200');
    final c = await seed('C 题', zujuanQuestionId: '200');

    final map = await repo.byZujuanQuestionIds(<String>{'100', '200', '300'});

    expect(map.keys.toSet(), <String>{'100', '200'});
    expect(map['100']!.single.id, a.id);
    expect(
      map['200']!.map((row) => row.id).toSet(),
      <String>{b.id, c.id},
    );
  });

  test('同一组卷网 id 多行：updatedAt 降序（最新一行在最前）', () async {
    final older = await seed(
      '同 id 的旧行',
      zujuanQuestionId: '777',
      now: DateTime(2026, 10, 1, 8),
    );
    final newer = await seed(
      '同 id 的新行',
      zujuanQuestionId: '777',
      now: DateTime(2026, 10, 2, 8),
    );

    final map = await repo.byZujuanQuestionIds(<String>{'777'});

    expect(map['777']!.map((row) => row.id).toList(), <String>[
      newer.id,
      older.id,
    ]);
  });

  test('updatedAt 相同时按 id 升序（结果仍确定）', () async {
    final sameMoment = DateTime(2026, 10, 3, 8);
    final first = await seed(
      '同一时刻的第一行',
      zujuanQuestionId: '888',
      now: sameMoment,
    );
    final second = await seed(
      '同一时刻的第二行',
      zujuanQuestionId: '888',
      now: sameMoment,
    );

    final expected = <String>[first.id, second.id]..sort();
    final map = await repo.byZujuanQuestionIds(<String>{'888'});

    expect(map['888']!.map((row) => row.id).toList(), expected);
  });

  test('没有组卷网 id 的题任何集合都查不到', () async {
    await seed('普通题');
    await seed('普通题二', zujuanBankId: '10');

    expect(await repo.byZujuanQuestionIds(<String>{'10', '', ' '}), isEmpty);
  });

  test('查到的行保留题源三列（链接与两个 id）', () async {
    final question = await seed(
      '链接齐全的题',
      zujuanQuestionId: '35583902',
      zujuanBankId: '10',
      sourceUrl: 'https://zujuan.xkw.com/10q35583902.html',
    );

    final map = await repo.byZujuanQuestionIds(<String>{'35583902'});
    final row = map['35583902']!.single;

    expect(row.id, question.id);
    expect(row.zujuanQuestionId, '35583902');
    expect(row.zujuanBankId, '10');
    expect(row.sourceUrl, 'https://zujuan.xkw.com/10q35583902.html');
  });
}
