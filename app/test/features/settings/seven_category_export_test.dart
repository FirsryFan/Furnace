import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/settings/application/seven_category_export.dart';

void main() {
  test('7 类导出：manifest + categories + other_tables，技能插件如实不可用', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.tags).insert(
          TagsCompanion.insert(
            id: 'tag-1',
            name: '函数',
            color: const Value(0xFFFFFFFF),
            createdAt: 0,
            updatedAt: 0,
          ),
        );
    final bytes = await SevenCategoryExport(db).buildBytes();
    expect(bytes, isNotEmpty);
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toSet();
    for (final category in SevenCategoryExport.categories.keys) {
      expect(names, contains('$category.json'));
    }
    expect(names, contains('manifest.json'));
    expect(names, contains('other_tables.json'));

    final manifestFile = archive.files.firstWhere((f) => f.name == 'manifest.json');
    final manifest = jsonDecode(
      utf8.decode(manifestFile.content as List<int>),
    ) as Map<String, dynamic>;
    expect(manifest['format'], 'furnace.export/7');
    expect(manifest['skills_plugins_available'], isFalse);
    final categories = manifest['categories'] as Map<String, dynamic>;
    expect(categories.keys, containsAll(SevenCategoryExport.categories.keys));

    final tagsFile = archive.files.firstWhere((f) => f.name == 'tags.json');
    final tags = jsonDecode(utf8.decode(tagsFile.content as List<int>));
    expect((tags['tags']['rows'] as List), hasLength(1));
  });

  test('7 类导出：类别表名不重复（除 review/exposure 共享外）', () {
    final seen = <String, String>{};
    for (final entry in SevenCategoryExport.categories.entries) {
      for (final table in entry.value) {
        if (table == 'review_logs' || table == 'exposure_logs') continue;
        seen.putIfAbsent(table, () => entry.key);
      }
    }
    expect(seen.length, greaterThan(10));
  });
}
