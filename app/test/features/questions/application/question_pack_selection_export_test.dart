/// 题库包「选择性导出」与「导入前预检」的测试：用内存库 + 临时目录真实走一遍。
///
/// 验收重点（`docs/QUESTION_BANK_DESIGN.md` §20）：
///  - 筛选（学科/来源/题号范围/标签）只影响包内容与清单计数，不改库；
///  - 未选中的题不读配图文件，包内题序从 1 重新编号；
///  - planImport 只读：给出新增/跳过/缺标签的预检，不写题、不落图。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/package/question_pack_codec.dart';
import 'package:furnace/data/package/question_pack_source.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/services/package/question_pack_manifest.dart';
import 'package:furnace/domain/services/package/question_pack_selection.dart';
import 'package:furnace/features/questions/application/question_pack_service.dart';
import 'package:furnace/features/questions/data/question_media_store.dart';

void main() {
  late _Harness source;

  setUp(() async {
    source = await _Harness.create();
  });

  tearDown(() async {
    await source.dispose();
  });

  Uint8List pngBytes(int seed) => Uint8List.fromList(<int>[
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        seed,
      ]);

  group('选择性导出', () {
    test('空选择导出全部，与默认参数结果一致', () async {
      await _seed(source, stem: '第一题。');
      await _seed(source, stem: '第二题。', subjectKey: 'physics');

      final all = await source.service.exportBytes();
      final explicit = await source.service.exportBytes(
        selection: const QuestionPackSelection(),
      );
      expect(all.questionCount, 2);
      expect(explicit.questionCount, 2);
      // zip 条目带生成时间戳，字节不保证逐字节相同；比解出来的内容。
      expect(
        decodeQuestionPackArchive(all.bytes).records.map((r) => r.stem),
        decodeQuestionPackArchive(explicit.bytes).records.map((r) => r.stem),
      );
    });

    test('只导出所选学科', () async {
      await _seed(source, stem: '数学题。');
      await _seed(source, stem: '物理题。', subjectKey: 'physics');
      await _seed(source, stem: '化学题。', subjectKey: 'chemistry');

      final result = await source.service.exportBytes(
        selection: const QuestionPackSelection(subjectKeys: {'physics'}),
      );
      expect(result.questionCount, 1);
      final archive = decodeQuestionPackArchive(result.bytes);
      expect(archive.records.single.stem, '物理题。');
    });

    test('按来源档位筛选', () async {
      await _seed(source, stem: '高考题。', sourceLevel: 'gaokao');
      await _seed(source, stem: '学校题。', sourceLevel: 'school');

      final result = await source.service.exportBytes(
        selection: const QuestionPackSelection(sourceLevels: {'school'}),
      );
      expect(result.questionCount, 1);
      expect(
        decodeQuestionPackArchive(result.bytes).records.single.stem,
        '学校题。',
      );
    });

    test('题号范围含两端，单边开放', () async {
      final first = await _seed(source, stem: '第一题。');
      final second = await _seed(source, stem: '第二题。');
      await _seed(source, stem: '第三题。');
      expect(first.serialNo, 1);
      expect(second.serialNo, 2);

      final fromSecond = await source.service.exportBytes(
        selection: const QuestionPackSelection(serialFrom: 2),
      );
      expect(fromSecond.questionCount, 2);
      final upToFirst = await source.service.exportBytes(
        selection: const QuestionPackSelection(serialTo: 1),
      );
      expect(upToFirst.questionCount, 1);
    });

    test('题号区间反向时交换归一', () async {
      await _seed(source, stem: '第一题。');
      await _seed(source, stem: '第二题。');
      await _seed(source, stem: '第三题。');

      final result = await source.service.exportBytes(
        selection: const QuestionPackSelection(serialFrom: 3, serialTo: 2),
      );
      expect(result.questionCount, 2);
      final serials = decodeQuestionPackArchive(result.bytes)
          .records
          .map((record) => record.serialNo)
          .toList();
      expect(serials, <int>[2, 3]);
    });

    test('按标签路径筛选（直接挂的标签才命中）', () async {
      final root = await source.tags.createTag(name: '数学');
      final child = await source.tags.createTag(name: '函数', parentId: root.id);
      await _seed(source, stem: '带标签的题。', tagIds: <String>{child.id});
      await _seed(source, stem: '没标签的题。');

      final hit = await source.service.exportBytes(
        selection: const QuestionPackSelection(tagPaths: {'数学/函数'}),
      );
      expect(hit.questionCount, 1);
      expect(
        decodeQuestionPackArchive(hit.bytes).records.single.stem,
        '带标签的题。',
      );

      final miss = await source.service.exportBytes(
        selection: const QuestionPackSelection(tagPaths: {'数学'}),
      );
      expect(miss.questionCount, 0);
    });

    test('多条件 AND', () async {
      await _seed(source, stem: '数学一。', subjectKey: 'math');
      await _seed(source, stem: '数学二。', subjectKey: 'math');
      await _seed(source, stem: '物理一。', subjectKey: 'physics');

      final result = await source.service.exportBytes(
        selection: const QuestionPackSelection(
          subjectKeys: {'math'},
          serialFrom: 2,
        ),
      );
      expect(result.questionCount, 1);
      expect(
        decodeQuestionPackArchive(result.bytes).records.single.stem,
        '数学二。',
      );
    });

    test('筛选后包内题序从 1 重新编号', () async {
      await _seed(source, stem: '数学题。', subjectKey: 'math');
      final physics = await _seed(
        source,
        stem: '物理题。',
        subjectKey: 'physics',
      );
      await source.store.save(
        questionId: physics.id,
        fileName: 'p.png',
        bytes: pngBytes(3),
      );

      final result = await source.service.exportBytes(
        selection: const QuestionPackSelection(subjectKeys: {'physics'}),
      );
      final record = decodeQuestionPackArchive(result.bytes).records.single;
      expect(record.stem, '物理题。');
      expect(record.media.single.packPath, 'media/q1/0.png');
    });

    test('未选中的题不读配图字节', () async {
      final math = await _seed(source, stem: '数学题。', subjectKey: 'math');
      final physics = await _seed(
        source,
        stem: '物理题。',
        subjectKey: 'physics',
      );
      final mathImage = await source.store.save(
        questionId: math.id,
        fileName: 'm.png',
        bytes: pngBytes(4),
      );
      final physicsImage = await source.store.save(
        questionId: physics.id,
        fileName: 'p.png',
        bytes: pngBytes(5),
      );

      final read = <String>[];
      final snapshot = await readQuestionPackSource(
        database: source.db,
        readMedia: (relPath) async {
          read.add(relPath);
          return pngBytes(6);
        },
        selection: const QuestionPackSelection(subjectKeys: {'math'}),
      );
      expect(snapshot.questionCount, 1);
      expect(read, <String>[mathImage.relPath]);
      expect(read, isNot(contains(physicsImage.relPath)));
      expect(snapshot.mediaBytes, hasLength(1));
    });

    test('0 命中：空包可解码、清单 0 题', () async {
      await _seed(source, stem: '数学题。', subjectKey: 'math');

      final result = await source.service.exportBytes(
        selection: const QuestionPackSelection(subjectKeys: {'physics'}),
      );
      expect(result.questionCount, 0);
      expect(result.mediaCount, 0);
      final archive = decodeQuestionPackArchive(result.bytes);
      expect(archive.records, isEmpty);
      expect(archive.manifest.questionCount, 0);
    });

    test('清单计数按筛选后写', () async {
      final math = await _seed(source, stem: '数学题。', subjectKey: 'math');
      await _seed(source, stem: '物理题。', subjectKey: 'physics');
      await source.store.save(
        questionId: math.id,
        fileName: 'm.png',
        bytes: pngBytes(7),
      );

      final result = await source.service.exportBytes(
        selection: const QuestionPackSelection(subjectKeys: {'math'}),
      );
      final manifest = decodeQuestionPackArchive(result.bytes).manifest;
      expect(manifest.questionCount, 1);
      expect(manifest.mediaCount, 1);
    });

    test('筛选不改库：题目与配图行数不变', () async {
      await _seed(source, stem: '数学题。', subjectKey: 'math');
      await _seed(source, stem: '物理题。', subjectKey: 'physics');
      final beforeQuestions =
          (await source.db.select(source.db.questions).get()).length;
      final beforeAttachments =
          (await source.db.select(source.db.attachments).get()).length;

      await source.service.exportBytes(
        selection: const QuestionPackSelection(subjectKeys: {'math'}),
      );
      expect(
        (await source.db.select(source.db.questions).get()).length,
        beforeQuestions,
      );
      expect(
        (await source.db.select(source.db.attachments).get()).length,
        beforeAttachments,
      );
    });
  });

  group('按题目 id 集合导出（多选导出选中）', () {
    test('只导出选中 id，其余题不进包', () async {
      final first = await _seed(source, stem: '第一题。');
      await _seed(source, stem: '第二题。');
      final third = await _seed(source, stem: '第三题。');

      final result = await source.service.exportBytes(
        questionIds: <String>{first.id, third.id},
      );
      expect(result.questionCount, 2);
      final records = decodeQuestionPackArchive(result.bytes).records;
      expect(records.map((record) => record.stem), <String>['第一题。', '第三题。']);
      expect(records.map((record) => record.serialNo), <int>[1, 3]);
    });

    test('未知 id 与空白 id 被忽略，不报错', () async {
      await _seed(source, stem: '第一题。');

      final result = await source.service.exportBytes(
        questionIds: <String>{'no-such-question', '   ', ' '},
      );
      expect(result.questionCount, 0);
      expect(decodeQuestionPackArchive(result.bytes).records, isEmpty);
    });

    test('空集合等价于不按 id 约束（全量）', () async {
      await _seed(source, stem: '第一题。');
      await _seed(source, stem: '第二题。');

      final result = await source.service.exportBytes(
        questionIds: const <String>{},
      );
      expect(result.questionCount, 2);
    });

    test('与 selection 取交集', () async {
      await _seed(source, stem: '数学一。', subjectKey: 'math');
      final mathTwo = await _seed(source, stem: '数学二。', subjectKey: 'math');
      final physics = await _seed(source, stem: '物理一。', subjectKey: 'physics');

      final result = await source.service.exportBytes(
        selection: const QuestionPackSelection(subjectKeys: {'math'}),
        questionIds: <String>{mathTwo.id, physics.id},
      );
      expect(result.questionCount, 1);
      expect(
        decodeQuestionPackArchive(result.bytes).records.single.stem,
        '数学二。',
      );
    });

    test('筛选后包内题序从 1 重新编号', () async {
      await _seed(source, stem: '第一题。');
      final second = await _seed(source, stem: '第二题。');
      await _seed(source, stem: '第三题。');
      await source.store.save(
        questionId: second.id,
        fileName: 'b.png',
        bytes: pngBytes(8),
      );

      final result = await source.service.exportBytes(
        questionIds: <String>{second.id},
      );
      final record = decodeQuestionPackArchive(result.bytes).records.single;
      expect(record.stem, '第二题。');
      expect(record.media.single.packPath, 'media/q1/0.png');
    });

    test('未选中的题不读配图字节，只读选中题的', () async {
      final first = await _seed(source, stem: '第一题。');
      final second = await _seed(source, stem: '第二题。');
      await source.store.save(
        questionId: first.id,
        fileName: 'a.png',
        bytes: pngBytes(9),
      );
      final secondImage = await source.store.save(
        questionId: second.id,
        fileName: 'b.png',
        bytes: pngBytes(10),
      );

      final read = <String>[];
      final snapshot = await readQuestionPackSource(
        database: source.db,
        readMedia: (relPath) async {
          read.add(relPath);
          return pngBytes(11);
        },
        questionIds: <String>{second.id},
      );
      expect(snapshot.questionCount, 1);
      expect(read, <String>[secondImage.relPath]);
      expect(snapshot.mediaBytes, hasLength(1));
      expect(snapshot.records.single.stem, '第二题。');
    });

    test('清单计数按选中后的写', () async {
      final first = await _seed(source, stem: '第一题。');
      await _seed(source, stem: '第二题。');
      await source.store.save(
        questionId: first.id,
        fileName: 'a.png',
        bytes: pngBytes(12),
      );

      final result = await source.service.exportBytes(
        questionIds: <String>{first.id},
      );
      final manifest = decodeQuestionPackArchive(result.bytes).manifest;
      expect(manifest.questionCount, 1);
      expect(manifest.mediaCount, 1);
    });

    test('导出选中不改库：题目与配图行数不变', () async {
      final first = await _seed(source, stem: '第一题。');
      await _seed(source, stem: '第二题。');
      await source.store.save(
        questionId: first.id,
        fileName: 'a.png',
        bytes: pngBytes(13),
      );
      final beforeQuestions =
          (await source.db.select(source.db.questions).get()).length;
      final beforeAttachments =
          (await source.db.select(source.db.attachments).get()).length;

      await source.service.exportBytes(questionIds: <String>{first.id});
      expect(
        (await source.db.select(source.db.questions).get()).length,
        beforeQuestions,
      );
      expect(
        (await source.db.select(source.db.attachments).get()).length,
        beforeAttachments,
      );
    });
  });

  group('导入前预检 planImport', () {
    test('全新增：createCount 等于包内题数，目标库不被写', () async {
      await _seed(source, stem: '第一题。');
      await _seed(source, stem: '第二题。');
      final pack = await source.service.exportBytes();

      final target = await _Harness.create();
      addTearDown(target.dispose);
      final preview = await target.service.planImport(pack.bytes);
      expect(preview.recordCount, 2);
      expect(preview.createCount, 2);
      expect(preview.skipCount, 0);
      expect(preview.missingTagCount, 0);
      expect(preview.isFullyNew, isTrue);
      expect(preview.summaryZh, isNotEmpty);
      expect(
        (await target.db.select(target.db.questions).get()),
        isEmpty,
      );
      expect(
        Directory('${target.support.path}/question_images').existsSync(),
        isFalse,
      );
    });

    test('重复包：createCount 0、skipCount 全数，且不重复入库', () async {
      await _seed(source, stem: '第一题。');
      await _seed(source, stem: '第二题。');
      final pack = await source.service.exportBytes();

      final target = await _Harness.create();
      addTearDown(target.dispose);
      await target.service.importPack(pack.bytes);
      final before = (await target.db.select(target.db.questions).get()).length;

      final preview = await target.service.planImport(pack.bytes);
      expect(preview.createCount, 0);
      expect(preview.skipCount, 2);
      expect(preview.isFullyNew, isFalse);
      expect(
        (await target.db.select(target.db.questions).get()).length,
        before,
      );
    });

    test('缺标签：missingTagCount 报出来只告警不阻断', () async {
      final root = await source.tags.createTag(name: '数学');
      await _seed(source, stem: '带标签的题。', tagIds: <String>{root.id});
      final pack = await source.service.exportBytes();

      final target = await _Harness.create();
      addTearDown(target.dispose);
      final preview = await target.service.planImport(pack.bytes);
      expect(preview.missingTagCount, 1);
      expect(preview.hasWarnings, isTrue);
      expect(preview.isFullyNew, isTrue);
      expect(
        (await target.db.select(target.db.questions).get()),
        isEmpty,
      );
    });

    test('坏包抛 QuestionPackException', () async {
      final bad = Uint8List.fromList(<int>[1, 2, 3, 4]);
      await expectLater(
        source.service.planImport(bad),
        throwsA(isA<QuestionPackException>()),
      );
    });

    test('筛选导出包的预检：只报筛选后的题数', () async {
      await _seed(source, stem: '数学题。', subjectKey: 'math');
      await _seed(source, stem: '物理题。', subjectKey: 'physics');
      final pack = await source.service.exportBytes(
        selection: const QuestionPackSelection(subjectKeys: {'math'}),
      );

      final target = await _Harness.create();
      addTearDown(target.dispose);
      final preview = await target.service.planImport(pack.bytes);
      expect(preview.recordCount, 1);
      expect(preview.createCount, 1);
      expect(preview.manifestQuestionCount, 1);
    });

    test('预检不改目标库的题号与指纹', () async {
      await _seed(source, stem: '第一题。');
      final pack = await source.service.exportBytes();

      final target = await _Harness.create();
      addTearDown(target.dispose);
      await target.service.importPack(pack.bytes);
      final before = (await target.db.select(target.db.questions).get())
          .map((row) => '${row.id}:${row.serialNo}:${row.stemFingerprint}')
          .toList();

      await target.service.planImport(pack.bytes);
      final after = (await target.db.select(target.db.questions).get())
          .map((row) => '${row.id}:${row.serialNo}:${row.stemFingerprint}')
          .toList();
      expect(after, before);
    });

    test('预览字段：manifest 计数、版本、导出时间都在', () async {
      await _seed(source, stem: '第一题。');
      final now = DateTime.utc(2026, 10, 21, 6, 30);
      final pack = await source.service.exportBytes(now: now);

      final target = await _Harness.create();
      addTearDown(target.dispose);
      final preview = await target.service.planImport(pack.bytes);
      expect(preview.manifestQuestionCount, 1);
      expect(preview.appVersion, isNotEmpty);
      expect(preview.exportedAt, now);
      expect(preview.hasManifestMismatch, isFalse);
    });
  });
}

/// 一个「数据库 + 临时 support 目录 + 三个仓库 + service」的小环境。
class _Harness {
  _Harness({
    required this.db,
    required this.support,
    required this.questions,
    required this.tags,
    required this.store,
    required this.service,
  });

  final AppDatabase db;
  final Directory support;
  final QuestionRepository questions;
  final TagRepository tags;
  final QuestionMediaStore store;
  final QuestionPackService service;

  static Future<_Harness> create() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final support =
        Directory.systemTemp.createTempSync('furnace_question_pack_sel_');
    final store = QuestionMediaStore(
      database: db,
      supportDirectory: () async => support,
    );
    final questions = QuestionRepository(db);
    final tags = TagRepository(db);
    final service = QuestionPackService(
      database: db,
      questions: questions,
      mediaStore: store,
      tags: tags,
    );
    return _Harness(
      db: db,
      support: support,
      questions: questions,
      tags: tags,
      store: store,
      service: service,
    );
  }

  Future<void> dispose() async {
    await db.close();
    if (support.existsSync()) {
      support.deleteSync(recursive: true);
    }
  }
}

Future<Question> _seed(
  _Harness harness, {
  required String stem,
  String subjectKey = 'math',
  String sourceLevel = 'gaokao',
  Set<String> tagIds = const <String>{},
}) async {
  final result = await harness.questions.ingest(QuestionDraft(
    stem: stem,
    answer: 'B',
    solution: '解析文字。',
    subjectKey: subjectKey,
    questionType: 'solution',
    sourceLevel: sourceLevel,
    sourceLabel: '测试来源',
    tagIds: tagIds,
  ));
  return result.question;
}
