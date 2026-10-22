import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';

/// 题目自定义题名的写入口径（`docs/QUESTION_BANK_DESIGN.md` / 轮次一百三十九）：
/// 仓库只做存储归一（trim、空白 → NULL），长度与去重留给域层纯逻辑。
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

  test('写题名并读回：两端空白归一', () async {
    final ingested = await repo.ingest(const QuestionDraft(stem: '题名要能写'));

    expect(
        await repo.setQuestionTitle(ingested.question.id, '  传送带模型  '), isTrue);
    expect((await repo.byId(ingested.question.id))!.title, '传送带模型');
  });

  test('空串与全空白把题名清成 null', () async {
    final ingested = await repo.ingest(
      const QuestionDraft(stem: '题名要能清掉', sourceUrl: 'https://example.com'),
    );
    await repo.setQuestionTitle(ingested.question.id, '先起个名字');

    expect(await repo.setQuestionTitle(ingested.question.id, ''), isTrue);
    expect((await repo.byId(ingested.question.id))!.title, isNull);

    await repo.setQuestionTitle(ingested.question.id, '再起一个');
    expect(await repo.setQuestionTitle(ingested.question.id, '   '), isTrue);
    expect((await repo.byId(ingested.question.id))!.title, isNull);
  });

  test('不存在的题目返回 false，不抛', () async {
    expect(await repo.setQuestionTitle('q-nope', '幽灵题名'), isFalse);
    expect(await repo.setQuestionTitles(<String, String?>{'q-nope': 'x'}), 0);
  });

  test('updatedAt 由调用方给的时刻驱动', () async {
    final ingested = await repo.ingest(
      const QuestionDraft(stem: '改题名要动 updatedAt'),
      now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    await repo.setQuestionTitle(
      ingested.question.id,
      '新题名',
      now: DateTime.fromMillisecondsSinceEpoch(1700000005000),
    );
    expect((await repo.byId(ingested.question.id))!.updatedAt, 1700000005000);
  });

  test('题名与题干指纹去重互不影响', () async {
    final first = await repo.ingest(const QuestionDraft(stem: '同一道题'));
    await repo.setQuestionTitle(first.question.id, '甲名');
    final again = await repo.ingest(const QuestionDraft(stem: '同一道题'));
    expect(again.created, isFalse, reason: '去重只看题干指纹，不看题名');
    expect((await repo.byId(first.question.id))!.title, '甲名');
  });
}
