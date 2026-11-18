import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/settings/application/seven_category_export.dart';

void main() {
  test('7 类导出：真实库 ZIP 可解码，manifest 分类齐全', () async {
    final source = File(r'E:\Furnace\data\furnace.db');
    final tmp = await Directory.systemTemp.createTemp('furnace-seven-real');
    final copy = await source.copy('${tmp.path}/furnace.db');
    final db = AppDatabase.forTesting(NativeDatabase(copy));
    addTearDown(() async {
      await db.close();
      await tmp.delete(recursive: true);
    });
    final bytes = await SevenCategoryExport(db).buildBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toSet();
    for (final category in SevenCategoryExport.categories.keys) {
      expect(names, contains('$category.json'));
    }
    final manifestFile = archive.files.firstWhere((f) => f.name == 'manifest.json');
    final manifest = jsonDecode(
      utf8.decode(manifestFile.content as List<int>),
    ) as Map<String, dynamic>;
    expect(manifest['format'], 'furnace.export/7');
    final tagsFile = archive.files.firstWhere((f) => f.name == 'tags.json');
    final tags = jsonDecode(utf8.decode(tagsFile.content as List<int>));
    // 真实库至少有标签表；行数允许为 0，但不能缺表。
    expect(tags, isA<Map<String, dynamic>>());
    expect(tags.containsKey('tags'), isTrue);
    expect(tags.containsKey('object_tags'), isTrue);
  });
}
