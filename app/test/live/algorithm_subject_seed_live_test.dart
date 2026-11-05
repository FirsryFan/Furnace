// 算法竞赛学科落库：标签树 + 题库包 → 真实数据库（先自动备份）。
//
// 为什么放在 test/live：它要写真实库（E:\Furnace\data\furnace.db），并且需要
// 显式的环境变量才运行；正常运行 flutter test 时保持 skip，不会碰用户数据。
//
//   cd E:/Projects/Furnace/app
//   RUN_ALGORITHM_SEED=1 flutter test test/live/algorithm_subject_seed_live_test.dart
//
// 可用环境变量覆盖默认路径：FURNACE_DB / PACK_PATH / TAGS_PATH。
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/features/questions/application/question_pack_service.dart';
import 'package:furnace/features/questions/data/question_media_store.dart';
import 'package:furnace/domain/services/questions/question_title_suggestion.dart';

const String _runFlag = 'RUN_ALGORITHM_SEED';
const String _defaultDb = r'E:\Furnace\data\furnace.db';
const String _defaultPack =
    r'E:\Workspaces\Furnace\10-projects\algorithm-subject\packages\Furnace-algorithm-2026-11-06.tqb';
const String _defaultTags =
    r'E:\Workspaces\Furnace\10-projects\algorithm-subject\data\algorithm-tags.json';
const String _backupDir =
    r'E:\Workspaces\Furnace\00-inbox\algorithm-subject\backup';

Future<String> _ensureTag(
  TagRepository tags,
  String name,
  String? parentId,
  String parentPath,
  void Function(bool created) onCreated,
) async {
  final path = parentPath.isEmpty ? name : '$parentPath/$name';
  final existing = await tags.getTagByPath(path);
  if (existing != null) {
    onCreated(false);
    return existing.id;
  }
  final created = await tags.createTag(name: name, parentId: parentId);
  onCreated(true);
  return created.id;
}

Future<void> _ensureTree(
  TagRepository tags,
  Map<String, Object?> node,
  String? parentId,
  String parentPath,
  void Function(bool created) onCreated,
) async {
  final name = (node['name'] as String?)?.trim() ?? '';
  if (name.isEmpty) {
    return;
  }
  final id = await _ensureTag(tags, name, parentId, parentPath, onCreated);
  final fullPath = parentPath.isEmpty ? name : '$parentPath/$name';
  final children = node['children'];
  if (children is List) {
    for (final child in children) {
      if (child is Map) {
        await _ensureTree(
          tags,
          child.cast<String, Object?>(),
          id,
          fullPath,
          onCreated,
        );
      }
    }
  }
}

void main() {
  test('算法竞赛：标签树 + 题库包落真实库（导入前备份）', () async {
    final dbFile = File(Platform.environment['FURNACE_DB'] ?? _defaultDb);
    final packFile = File(Platform.environment['PACK_PATH'] ?? _defaultPack);
    final tagsFile = File(Platform.environment['TAGS_PATH'] ?? _defaultTags);
    expect(dbFile.existsSync(), isTrue, reason: '真实库不存在：${dbFile.path}');
    expect(packFile.existsSync(), isTrue, reason: '题库包不存在：${packFile.path}');
    expect(tagsFile.existsSync(), isTrue, reason: '标签树不存在：${tagsFile.path}');

    // 先做整库文件级备份（QuestionPackService 还会备份现有题库为 .tqb，两层保险）。
    final backupRoot = Directory(_backupDir);
    await backupRoot.create(recursive: true);
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '-');
    final backup = await dbFile.copy(
      '${backupRoot.path}\\furnace-before-algorithm-$stamp.db',
    );
    // ignore: avoid_print
    print('DB_BACKUP=${backup.path}');

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    final tags = TagRepository(db);
    final questions = QuestionRepository(db);
    final service = QuestionPackService(
      database: db,
      questions: questions,
      mediaStore: QuestionMediaStore(
        database: db,
        supportDirectory: () async => dbFile.parent,
      ),
      tags: tags,
      documentsDirectory: () async =>
          Directory('${dbFile.parent.path}\\documents'),
    );

    // 1) 标签树：算法竞赛 / 专题 + 能力 + 难度
    final tree = jsonDecode(await tagsFile.readAsString());
    var createdTags = 0;
    var existingTags = 0;
    if (tree is Map<String, Object?>) {
      final rootMap = <String, Object?>{
        'name': tree['root'],
        'children': tree['children'],
      };
      await _ensureTree(tags, rootMap, null, '', (created) {
        if (created) {
          createdTags += 1;
        } else {
          existingTags += 1;
        }
      });
    }
    final algorithmTags = await tags.getTagsUnderPath('算法竞赛');
    // ignore: avoid_print
    print('TAGS created=$createdTags existing=$existingTags '
        'under_algorithm=${algorithmTags.length}');

    // 2) 题库包导入（只新增；重复题按题干指纹跳过）
    final bytes = await packFile.readAsBytes();
    final peek = service.peek(bytes);
    final preview = await service.planImport(bytes);
    // ignore: avoid_print
    print('PACK questions=${peek.questionCount} media=${peek.mediaCount} '
        'preview=${preview.summaryZh.join(" | ")}');
    final report = await service.importPack(bytes);
    // ignore: avoid_print
    print('IMPORT created=${report.createdCount} '
        'updated=${report.updatedCount} skipped=${report.skippedCount} '
        'media=${report.mediaCount} '
        'warnings=${report.warnings.join(" | ")} '
        'failures=${report.failures.join(" | ")}');
    if (report.backupPath != null) {
      // ignore: avoid_print
      print('BANK_BACKUP=${report.backupPath}');
    }
    if (report.hasFailures) {
      // ignore: avoid_print
      print('IMPORT_FAILURES=${report.failures}');
    }

    // 3) 给 algorithm 题回填默认题名（只在 title 为空时写；可重入）。
    final allRows = await db.select(db.questions).get();
    final usedTitles = <String>[
      for (final row in allRows)
        if ((row.title ?? '').trim().isNotEmpty) row.title!.trim(),
    ];
    final pending = <String, String?>{};
    for (final row in allRows) {
      if (row.subjectKey != 'algorithm') continue;
      if ((row.title ?? '').trim().isNotEmpty) continue;
      final suggestion = suggestQuestionTitle(
        stem: row.stem,
        subjectKey: row.subjectKey,
        questionType: row.questionType,
        existingTitles: usedTitles,
      );
      pending[row.id] = suggestion.title;
      usedTitles.add(suggestion.title);
    }
    if (pending.isNotEmpty) {
      final named = await questions.setQuestionTitles(pending);
      // ignore: avoid_print
      print('TITLE_BACKFILL updated=$named');
    }

    // 3) 回读验证
    final rows = await (db.select(db.questions)
          ..where((t) => t.subjectKey.equals('algorithm')))
        .get();
    final linked = await tags.getTagsUnderPath('算法竞赛');
    // ignore: avoid_print
    print('VERIFY algorithm_questions=${rows.length} '
        'algorithm_tags=${linked.length}');
    final titles =
        rows.map((q) => q.title ?? q.stem.split('\n').first).toList();
    // ignore: avoid_print
    print('VERIFY titles=${titles.take(5).toList()}');
    await db.close();

    expect(createdTags + existingTags, greaterThan(0));
    expect(algorithmTags.length, greaterThan(10));
    expect(rows.length, greaterThanOrEqualTo(17));
    expect(report.failures, isEmpty);
  },
      timeout: const Timeout(Duration(minutes: 10)),
      skip: Platform.environment[_runFlag] != '1');
}
