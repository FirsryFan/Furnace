/// 题库批量打标签应用层测试：内存库 + 真实 TagRepository，真正走一遍 object_tags。
///
/// 覆盖：新增计数、已挂跳过、缺失路径、重复调用、空输入、去空白去重、
/// 单路径写入失败不拖垮整批、路径大小写、标签 path 为 NULL 时回落 name。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/features/questions/application/question_bulk_tagging.dart';

void main() {
  late AppDatabase db;
  late TagRepository tags;
  late QuestionRepository questions;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tags = TagRepository(db);
    questions = QuestionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Question> seed(String stem) async {
    final result = await questions.ingest(QuestionDraft(stem: stem));
    return result.question;
  }

  Future<String> makeTag(String name) async {
    final tag = await tags.createTag(name: name);
    return tag.path ?? tag.name;
  }

  Future<int> linkCount() async =>
      (await db.select(db.objectTags).get()).length;

  group('tagQuestions', () {
    test('挂两个标签到三道题：新增 6 条链接、影响 3 题', () async {
      final biology = await makeTag('生物');
      final genetics = await makeTag('遗传');
      final a = await seed('第一题。');
      final b = await seed('第二题。');
      final c = await seed('第三题。');

      final report = await tagQuestions(
        tags: tags,
        questionIds: <String>[a.id, b.id, c.id],
        tagPaths: <String>[biology, genetics],
      );

      expect(report.addedLinks, 6);
      expect(report.skippedLinks, 0);
      expect(report.affectedQuestionCount, 3);
      expect(report.missingTagPaths, isEmpty);
      expect(report.failedTagPaths, isEmpty);
      expect(report.isEmpty, isFalse);
      expect(await linkCount(), 6);
      for (final question in <Question>[a, b, c]) {
        final linked = await tags.tagsForObject(
          objectType: kQuestionBulkTagObjectType,
          objectId: question.id,
        );
        expect(
            linked.map((tag) => tag.path),
            unorderedEquals(<String>[
              biology,
              genetics,
            ]));
      }
    });

    test('部分题已挂过：已挂的跳过，只补缺的', () async {
      final all = await makeTag('全部');
      final extra = await makeTag('再加');
      final a = await seed('第一题。');
      final b = await seed('第二题。');
      final c = await seed('第三题。');
      final allTag = (await tags.getTagByPath(all))!;
      await tags.addTagToObject(
        tagId: allTag.id,
        objectType: kQuestionBulkTagObjectType,
        objectId: a.id,
      );

      final report = await tagQuestions(
        tags: tags,
        questionIds: <String>[a.id, b.id, c.id],
        tagPaths: <String>[all, extra],
      );

      expect(report.addedLinks, 5);
      expect(report.skippedLinks, 1);
      expect(report.affectedQuestionCount, 3);
      expect(await linkCount(), 6);
    });

    test('词表里没有的路径进 missing，不写行', () async {
      final known = await makeTag('已知');
      final a = await seed('第一题。');

      final report = await tagQuestions(
        tags: tags,
        questionIds: <String>[a.id],
        tagPaths: <String>[known, '不存在/路径'],
      );

      expect(report.addedLinks, 1);
      expect(report.missingTagPaths, <String>['不存在/路径']);
      expect(report.affectedQuestionCount, 1);
      expect(report.hasMissingTagPaths, isTrue);
      expect(await linkCount(), 1);
    });

    test('重复调用第二次新增 0：全部算跳过', () async {
      final tag = await makeTag('标签');
      final a = await seed('第一题。');
      final b = await seed('第二题。');

      final first = await tagQuestions(
        tags: tags,
        questionIds: <String>[a.id, b.id],
        tagPaths: <String>[tag],
      );
      final second = await tagQuestions(
        tags: tags,
        questionIds: <String>[a.id, b.id],
        tagPaths: <String>[tag],
      );

      expect(first.addedLinks, 2);
      expect(second.addedLinks, 0);
      expect(second.skippedLinks, 2);
      expect(second.affectedQuestionCount, 0);
      // 有「跳过」也算有结果可报，所以不是 isEmpty。
      expect(second.isEmpty, isFalse);
      expect(await linkCount(), 2);
    });

    test('空题目 / 空标签路径：空报告且不碰库', () async {
      final tag = await makeTag('标签');
      final a = await seed('第一题。');

      final noQuestions = await tagQuestions(
        tags: tags,
        questionIds: const <String>[],
        tagPaths: <String>[tag],
      );
      final noTags = await tagQuestions(
        tags: tags,
        questionIds: <String>[a.id],
        tagPaths: const <String>['  ', ''],
      );

      expect(noQuestions.isEmpty, isTrue);
      expect(noTags.isEmpty, isTrue);
      expect(await linkCount(), 0);
    });

    test('题 id 与路径都去空白去重后写入', () async {
      final tagA = await makeTag('甲');
      final tagB = await makeTag('乙');
      final a = await seed('甲题。');
      final b = await seed('乙题。');

      final report = await tagQuestions(
        tags: tags,
        questionIds: <String>[' ${a.id} ', a.id, b.id],
        tagPaths: <String>['  $tagA  ', tagA, tagB],
      );

      expect(report.addedLinks, 4);
      expect(report.affectedQuestionCount, 2);
      expect(report.missingTagPaths, isEmpty);
      expect(await linkCount(), 4);
    });

    test('某条路径写入抛错只记失败，其它路径照写', () async {
      final good = await makeTag('好标签');
      final bad = await makeTag('坏标签');
      final badTag = (await tags.getTagByPath(bad))!;
      final flaky = _FailOnTagRepository(db, failingTagId: badTag.id);
      final a = await seed('第一题。');
      final b = await seed('第二题。');

      final report = await tagQuestions(
        tags: flaky,
        questionIds: <String>[a.id, b.id],
        tagPaths: <String>[good, bad],
      );

      expect(report.addedLinks, 2);
      expect(report.failedTagPaths, <String>[bad]);
      expect(report.affectedQuestionCount, 2);
      expect(report.hasFailures, isTrue);
      final linkedA = await tags.tagsForObject(
        objectType: kQuestionBulkTagObjectType,
        objectId: a.id,
      );
      expect(linkedA.map((tag) => tag.path), <String>[good]);
    });

    test('路径大小写敏感：TagA 与 taga 不是同一条', () async {
      await makeTag('TagA');
      final a = await seed('第一题。');

      final report = await tagQuestions(
        tags: tags,
        questionIds: <String>[a.id],
        tagPaths: const <String>['taga'],
      );

      expect(report.missingTagPaths, <String>['taga']);
      expect(report.addedLinks, 0);
      expect(await linkCount(), 0);
    });

    test('标签 path 为 NULL 时回落 name 也能挂', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.into(db.tags).insert(TagsCompanion.insert(
            id: 'tag-raw',
            name: '裸标签',
            createdAt: now,
            updatedAt: now,
          ));
      final a = await seed('第一题。');

      final report = await tagQuestions(
        tags: tags,
        questionIds: <String>[a.id],
        tagPaths: const <String>['裸标签'],
      );

      expect(report.addedLinks, 1);
      expect(report.missingTagPaths, isEmpty);
      final linked = await tags.tagsForObject(
        objectType: kQuestionBulkTagObjectType,
        objectId: a.id,
      );
      expect(linked.single.id, 'tag-raw');
    });
  });
}

/// 指定 tagId 的批量写入一律抛错，用来验证「一条路径失败不拖垮整批」。
class _FailOnTagRepository extends TagRepository {
  _FailOnTagRepository(super.db, {required this.failingTagId});

  final String failingTagId;

  @override
  Future<int> addTagToObjects({
    required String tagId,
    required Iterable<String> objectIds,
    String objectType = 'question',
  }) {
    if (tagId == failingTagId) {
      throw StateError('模拟写入失败');
    }
    return super.addTagToObjects(
      tagId: tagId,
      objectIds: objectIds,
      objectType: objectType,
    );
  }
}
