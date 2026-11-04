import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/tag_repository.dart';

void main() {
  test('给新导入资料补标签', () async {
    final db = AppDatabase.forTesting(
        NativeDatabase(File(r'E:\Furnace\data\furnace.db')));
    final tags = TagRepository(db);
    Future<Tag> ensure(String path) async {
      final existing = await (db.select(db.tags)
            ..where((t) => t.path.equals(path)))
          .getSingleOrNull();
      if (existing != null) return existing;
      final parts = path.split('/');
      String? parent;
      Tag? tag;
      for (var i = 0; i < parts.length; i++) {
        final p = parts.sublist(0, i + 1).join('/');
        final found = await (db.select(db.tags)..where((t) => t.path.equals(p)))
            .getSingleOrNull();
        if (found != null) {
          tag = found;
          parent = found.id;
          continue;
        }
        tag = await tags.createTag(name: parts[i], parentId: parent);
        parent = tag.id;
      }
      return tag!;
    }

    final dsn = await ensure('数学/DSN');
    final mathAnalysis = await ensure('数学/高考分析');
    final mathBooks = await ensure('数学/高考分析原书');
    final chineseAnalysis = await ensure('语文/高考分析');
    final chineseBooks = await ensure('语文/高考分析原书');
    final physicsQuestions = await ensure('物理/题目');
    final all = await (db.select(db.questions)).get();
    var n = 0;
    for (final q in all) {
      final label = q.sourceLabel;
      String? tagId;
      if (label.startsWith('DSN 妙妙资料'))
        tagId = dsn.id;
      else if (label.startsWith('数学真题分析'))
        tagId = mathAnalysis.id;
      else if (label.contains('高考') && q.subjectKey == 'math')
        tagId = mathBooks.id;
      else if (label.contains('语文试题分析'))
        tagId = chineseAnalysis.id;
      else if (label.contains('高考') && q.subjectKey == 'chinese')
        tagId = chineseBooks.id;
      else if (label.startsWith('物理讲义')) tagId = physicsQuestions.id;
      if (tagId != null) {
        await tags.addTagToObject(
            tagId: tagId, objectType: 'question', objectId: q.id);
        n++;
      }
    }
    await db.close();
    // ignore: avoid_print
    print('TAGGED=' + n.toString());
  },
      timeout: const Timeout(Duration(minutes: 10)),
      skip: Platform.environment['RUN_TAG_IMPORT'] != '1');
}
