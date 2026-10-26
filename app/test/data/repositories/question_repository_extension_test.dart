import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';

/// 扩展题关联的数据层契约（handoff §7 M2 的 `extension_of`，轮次一百八十二）。
///
/// 锁三件事：
///  * [QuestionRepository.byZujuanQuestionId]：按组卷网题号取最新一行；
///  * [QuestionRepository.questionsByExtensionOf]：母题挂着的扩展题，题号升序、未编号最后；
///  * ingest 落库后 `extension_of` / `capability` / `text_format` 读回来不失真。
/// 母题→子题的防环/自指判定在纯逻辑 `question_extension.dart`，这里只管取数。
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
    String? extensionOf,
    List<String> capability = const <String>[],
    String textFormat = 'plain',
    DateTime? now,
  }) async {
    final result = await repo.ingest(
      QuestionDraft(
        stem: stem,
        zujuanQuestionId: zujuanQuestionId,
        extensionOf: extensionOf,
        capability: capability,
        textFormat: textFormat,
      ),
      now: now,
    );
    return result.question;
  }

  group('byZujuanQuestionId', () {
    test('题号 trim 后为空 → null（不查库）', () async {
      await seed('有 id 的题', zujuanQuestionId: '35583902');

      expect(await repo.byZujuanQuestionId(''), isNull);
      expect(await repo.byZujuanQuestionId('   '), isNull);
    });

    test('匹配 trim 后精确相等，没有这行 → null', () async {
      final question = await seed('有 id 的题', zujuanQuestionId: '35583902');
      await seed('手写题，没有组卷网 id');

      final found = await repo.byZujuanQuestionId(' 35583902 ');

      expect(found?.id, question.id);
      expect(await repo.byZujuanQuestionId('99999999'), isNull);
    });

    test('同一题号多行时取 updatedAt 最新的一行', () async {
      final older = await seed(
        '第一次入库的同题',
        zujuanQuestionId: '200',
        now: DateTime(2026, 10, 1, 8),
      );
      final newer = await seed(
        '第二次入库的同题（不同题干，绕开指纹去重）',
        zujuanQuestionId: '200',
        now: DateTime(2026, 10, 2, 8),
      );

      final found = await repo.byZujuanQuestionId('200');

      expect(found?.id, newer.id);
      expect(found?.id, isNot(older.id));
    });
  });

  group('questionsByExtensionOf', () {
    test('母题题号 trim 后为空 → 空列表（不查库）', () async {
      await seed('扩展题', zujuanQuestionId: '300', extensionOf: '100');

      expect(await repo.questionsByExtensionOf(''), isEmpty);
      expect(await repo.questionsByExtensionOf('   '), isEmpty);
    });

    test('只返回 extension_of 精确相等的题，母题自己不在列表里', () async {
      final parent = await seed('母题', zujuanQuestionId: '100');
      final childA = await seed(
        '扩展题 A',
        zujuanQuestionId: '301',
        extensionOf: '100',
      );
      await seed('无关题', zujuanQuestionId: '400');

      final children = await repo.questionsByExtensionOf('100');

      expect(children.map((row) => row.id).toList(), <String>[childA.id]);
      expect(children.any((row) => row.id == parent.id), isFalse);
    });

    test('题号升序；未编号的排最后；同号按 id 升序稳定', () async {
      final childB =
          await seed('扩展题 B', zujuanQuestionId: '302', extensionOf: '100');
      final childA =
          await seed('扩展题 A', zujuanQuestionId: '301', extensionOf: '100');
      final unnumbered = await seed('扩展题没有题号', extensionOf: '100');
      // ingest 会自动发号；这一行手动清掉题号，模拟"导入后又被清空"的老数据。
      await (db.update(db.questions)..where((t) => t.id.equals(unnumbered.id)))
          .write(const QuestionsCompanion(serialNo: Value<int?>(null)));

      final children = await repo.questionsByExtensionOf('100');

      expect(
        children.map((row) => row.id).toList(),
        // childB 先入库（题号更小），childA 后入库；未编号的手动清号排最后。
        <String>[childB.id, childA.id, unnumbered.id],
      );
    });
  });

  group('ingest 落库与读回', () {
    test('text_format / extension_of / capability 读回不失真', () async {
      final question = await seed(
        '整段 Markdown 的扩展题',
        zujuanQuestionId: '305',
        extensionOf: ' 100 ',
        capability: const <String>['A10', 'A2', 'A2'],
        textFormat: 'markdown',
      );

      final row = await repo.byId(question.id);

      expect(row?.textFormat, 'markdown');
      expect(row?.extensionOf, '100');
      expect(decodeQuestionCapability(row?.capability), <String>['A2', 'A10']);
    });

    test('plain 与未标能力点时落 NULL，而不是空串/空数组', () async {
      final question = await seed('普通题', zujuanQuestionId: '306');

      final row = await repo.byId(question.id);

      expect(row?.textFormat, isNull);
      expect(row?.extensionOf, isNull);
      expect(row?.capability, isNull);
    });
  });
}
