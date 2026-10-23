/// 题库包导出/导入服务的测试：用内存库 + 临时目录真实走一遍
/// 「读题库 → 打 zip → 解 zip → 再入库 → 存配图」。
///
/// 验收重点（`docs/QUESTION_BANK_DESIGN.md` §20）：
///  - 导出覆盖题目/选项/标签路径/配图（角色和顺序不丢）；
///  - 导入只新增：重复题跳过、已有题号不覆盖、缺标签只告警不阻断；
///  - 答案截图（role=answer）能随题往返；
///  - 坏包抛异常，不会悄悄导入半个包。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/package/question_pack_codec.dart';
import 'package:furnace/domain/services/package/question_pack_manifest.dart';
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

  test('空题库导出：0 题 0 媒体，peek 能读清单', () async {
    final result = await source.service.exportBytes(
      now: DateTime.utc(2026, 10, 21, 4, 30),
    );
    expect(result.questionCount, 0);
    expect(result.mediaCount, 0);
    expect(result.warnings, isEmpty);
    expect(result.bytes, isNotEmpty);

    final preview = source.service.peek(result.bytes);
    expect(preview.questionCount, 0);
    expect(preview.mediaCount, 0);
    expect(preview.appVersion, isNotEmpty);
    expect(preview.exportedAt, DateTime.utc(2026, 10, 21, 4, 30));
  });

  test('导出题目：题号顺序、选项、来源字段都在包里', () async {
    final first = await _seedQuestion(
      source,
      stem: r'已知函数 $f(x)=x^2$，求单调区间。',
      options: const <QuestionOptionDraft>[
        QuestionOptionDraft(label: 'A', content: '递增', sortOrder: 0),
        QuestionOptionDraft(
          label: 'B',
          content: '先减后增',
          isCorrect: true,
          sortOrder: 1,
        ),
      ],
      sourceUrl: 'https://zujuan.xkw.com/10q35583902.html',
      difficulty: 6.5,
      year: 2024,
      region: '湖南',
    );
    await _seedQuestion(source, stem: '第二题：求导。');

    final result = await source.service.exportBytes();
    expect(result.questionCount, 2);
    expect(first.serialNo, 1);

    final archive = decodeQuestionPackArchive(result.bytes);
    expect(archive.records, hasLength(2));
    expect(archive.records[0].serialNo, 1);
    expect(archive.records[1].serialNo, 2);
    final record = archive.records[0];
    expect(record.options, hasLength(2));
    expect(record.options[1].isCorrect, isTrue);
    expect(record.difficulty, 6.5);
    expect(record.sourceUrl, 'https://zujuan.xkw.com/10q35583902.html');
  });

  test('导出配图：按题序生成包内路径，角色与顺序保留', () async {
    final first = await _seedQuestion(source, stem: '第一题：带两张图。');
    await _seedQuestion(source, stem: '第二题：带一张图。');

    await source.store.save(
      questionId: first.id,
      fileName: 'stem.png',
      bytes: pngBytes(1),
      role: QuestionImageRole.stem,
    );
    await source.store.save(
      questionId: first.id,
      fileName: 'answer.png',
      bytes: pngBytes(2),
      role: QuestionImageRole.answer,
    );

    final result = await source.service.exportBytes();
    expect(result.mediaCount, 2);
    expect(result.warnings, isEmpty);

    final archive = decodeQuestionPackArchive(result.bytes);
    expect(archive.records, hasLength(2));
    final media = archive.records[0].media;
    expect(media, hasLength(2));
    expect(
      media.map((item) => item.packPath),
      <String>['media/q1/0.png', 'media/q1/1.png'],
    );
    expect(media.map((item) => item.role), <String>['stem', 'answer']);
    expect(archive.mediaBytes['media/q1/0.png'], equals(pngBytes(1)));
    expect(archive.mediaBytes['media/q1/1.png'], equals(pngBytes(2)));
  });

  test('导出：扩展名不认识的配图只告警，不阻断整包', () async {
    final question = await _seedQuestion(source, stem: '第一题。');
    await source.db.into(source.db.attachments).insert(
          AttachmentsCompanion.insert(
            id: 'att-unknown',
            ownerType: QuestionMediaStore.ownerType,
            ownerId: question.id,
            relPath: 'question_images/${question.id}/x/page.tiff',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );

    final result = await source.service.exportBytes();
    expect(result.questionCount, 1);
    expect(result.mediaCount, 0);
    expect(result.warnings, hasLength(1));
    expect(result.warnings.single, contains('扩展名不认识'));
  });

  test('导出：媒体文件从磁盘丢了只告警，不阻断整包', () async {
    final question = await _seedQuestion(source, stem: '第一题。');
    final image = await source.store.save(
      questionId: question.id,
      fileName: 'page.png',
      bytes: pngBytes(3),
    );
    File(image.absolutePath).deleteSync();

    final result = await source.service.exportBytes();
    expect(result.questionCount, 1);
    expect(result.mediaCount, 0);
    expect(result.warnings.single, contains('读不到字节'));
  });

  test('往返导入空库：题目、选项、标签、配图都过去', () async {
    final tag = await source.tags.createTag(name: '数学');
    final question = await _seedQuestion(
      source,
      stem: r'往返题：$\sin x$ 的周期是多少？',
      options: const <QuestionOptionDraft>[
        QuestionOptionDraft(label: 'A', content: 'π', sortOrder: 0),
        QuestionOptionDraft(
          label: 'B',
          content: '2π',
          isCorrect: true,
          sortOrder: 1,
        ),
      ],
      tagIds: <String>{tag.id},
      sourceUrl: 'https://zujuan.xkw.com/10q35583902.html',
      difficulty: 7.5,
      year: 2024,
      region: '湖南',
    );
    await source.store.save(
      questionId: question.id,
      fileName: 'answer.png',
      bytes: pngBytes(7),
      role: QuestionImageRole.answer,
    );
    final pack = await source.service.exportBytes();

    final target = await _Harness.create();
    addTearDown(target.dispose);
    final targetTag = await target.tags.createTag(name: '数学');

    final report = await target.service.importPack(pack.bytes);
    expect(report.createdCount, 1);
    expect(report.skippedCount, 0);
    expect(report.mediaCount, 1);
    expect(report.failures, isEmpty);

    final imported = (await target.db.select(target.db.questions).get()).single;
    expect(imported.stem, r'往返题：$\sin x$ 的周期是多少？');
    expect(imported.serialNo, 1);
    expect(imported.difficulty, 7.5);
    expect(imported.sourceUrl, 'https://zujuan.xkw.com/10q35583902.html');
    expect(imported.subjectKey, 'math');

    final options = await target.questions.optionsOf(imported.id);
    expect(options, hasLength(2));
    expect(options[1].isCorrect, isTrue);
    expect(
      await target.questions.tagIdsOf(imported.id),
      contains(targetTag.id),
    );

    final images = await target.store.list(imported.id);
    expect(images, hasLength(1));
    expect(images.single.role, QuestionImageRole.answer);
    expect(File(images.single.absolutePath).existsSync(), isTrue);
    expect(await target.store.readBytes(images.single.relPath),
        equals(pngBytes(7)));
  });

  test('重复导入：第二次全部跳过，题库不新增', () async {
    await _seedQuestion(source, stem: '重复题一。');
    await _seedQuestion(source, stem: '重复题二。');
    final pack = await source.service.exportBytes();

    final target = await _Harness.create();
    addTearDown(target.dispose);
    final first = await target.service.importPack(pack.bytes);
    expect(first.createdCount, 2);

    final second = await target.service.importPack(pack.bytes);
    expect(second.createdCount, 0);
    expect(second.skippedCount, 2);
    expect(second.warnings, isNotEmpty);
    expect(await target.db.select(target.db.questions).get(), hasLength(2));
  });

  test('导入：目标库已有其中一道题时只新建另一道', () async {
    await _seedQuestion(source, stem: '题一。');
    await _seedQuestion(source, stem: '题二。');
    final pack = await source.service.exportBytes();

    final target = await _Harness.create();
    addTearDown(target.dispose);
    await _seedQuestion(target, stem: '题二。');

    final report = await target.service.importPack(pack.bytes);
    expect(report.createdCount, 1);
    expect(report.skippedCount, 1);
    expect(await target.db.select(target.db.questions).get(), hasLength(2));
  });

  test('导入：标签路径不存在时照建题，只告警不挂边', () async {
    final tag = await source.tags.createTag(name: '数学');
    await _seedQuestion(
      source,
      stem: '挂标签的题。',
      tagIds: <String>{tag.id},
    );
    final pack = await source.service.exportBytes();

    final target = await _Harness.create();
    addTearDown(target.dispose);
    final report = await target.service.importPack(pack.bytes);
    expect(report.createdCount, 1);
    expect(
      report.warnings.any((warning) => warning.contains('标签 数学 在题库里不存在')),
      isTrue,
    );

    final imported = (await target.db.select(target.db.questions).get()).single;
    expect(await target.questions.tagIdsOf(imported.id), isEmpty);
  });

  test('导入不改已有题号：新题接在目标库最大号之后', () async {
    for (var i = 1; i <= 3; i++) {
      await _seedQuestion(source, stem: '来源题 $i。');
    }
    final pack = await source.service.exportBytes();

    final target = await _Harness.create();
    addTearDown(target.dispose);
    for (var i = 1; i <= 3; i++) {
      await _seedQuestion(target, stem: '目标已有题 $i。');
    }
    final report = await target.service.importPack(pack.bytes);
    expect(report.createdCount, 3);

    final serials = <int?>[
      for (final question in await target.db.select(target.db.questions).get())
        question.serialNo,
    ]..sort();
    expect(serials, <int?>[1, 2, 3, 4, 5, 6]);
  });

  test('导入保留加工来源字段（origin/state/trapNote/solution）', () async {
    await _seedQuestion(
      source,
      stem: '来源字段题。',
      difficulty: 8,
      year: 2023,
      region: '江苏',
      origin: 'ai_scan',
      state: 'raw',
      trapNote: '容易漏端点',
    );
    final pack = await source.service.exportBytes();

    final target = await _Harness.create();
    addTearDown(target.dispose);
    await target.service.importPack(pack.bytes);
    final imported = (await target.db.select(target.db.questions).get()).single;
    expect(imported.origin, 'ai_scan');
    expect(imported.state, 'raw');
    expect(imported.trapNote, '容易漏端点');
    expect(imported.year, 2023);
    expect(imported.region, '江苏');
    expect(imported.solution, isNotNull);
  });

  test('peek 坏包与 importPack 坏包都抛 QuestionPackException', () async {
    final bad = Uint8List.fromList(<int>[1, 2, 3, 4]);
    expect(
      () => source.service.peek(bad),
      throwsA(isA<QuestionPackException>()),
    );
    expect(
      () => source.service.importPack(bad),
      throwsA(isA<QuestionPackException>()),
    );
  });

  group('导入前自动备份', () {
    test('已有题目：先备份现有题库，路径在 documents 下且字节能读回', () async {
      await _seedQuestion(source, stem: '来源题一。');
      await _seedQuestion(source, stem: '来源题二。');
      final pack = await source.service.exportBytes();

      final target = await _Harness.create();
      addTearDown(target.dispose);
      await _seedQuestion(target, stem: '目标已有题。');

      final report = await target.service.importPack(pack.bytes);
      expect(report.createdCount, 2);
      expect(report.hasBackup, isTrue);
      expect(report.backupError, isNull);

      final backupPath = report.backupPath!;
      expect(p.isAbsolute(backupPath), isTrue);
      expect(
        p.dirname(backupPath),
        p.join(target.support.path, kQuestionPackBackupFolderName),
      );
      expect(p.basename(backupPath), startsWith('题库备份-'));
      expect(p.basename(backupPath), endsWith('.tqb'));

      final backupFile = File(backupPath);
      expect(backupFile.existsSync(), isTrue);
      final backupBytes = backupFile.readAsBytesSync();
      final archive = decodeQuestionPackArchive(backupBytes);
      // 备份的是「导入前」的题库，不含本次新导入的两道题。
      expect(archive.records, hasLength(1));
      expect(archive.records.single.stem, '目标已有题。');
      final preview = await target.service.planImport(backupBytes);
      expect(preview.recordCount, 1);
    });

    test('空库导入：不生成备份，backupPath 与 backupError 都是 null', () async {
      await _seedQuestion(source, stem: '空库导入题。');
      final pack = await source.service.exportBytes();

      final target = await _Harness.create();
      addTearDown(target.dispose);

      final report = await target.service.importPack(pack.bytes);
      expect(report.createdCount, 1);
      expect(report.backupPath, isNull);
      expect(report.backupError, isNull);
      expect(report.hasBackup, isFalse);
      expect(
        Directory(
          p.join(target.support.path, kQuestionPackBackupFolderName),
        ).existsSync(),
        isFalse,
      );
    });

    test('备份失败不阻断导入：backupError 记原因，题照常入库', () async {
      await _seedQuestion(source, stem: '要导入的题。');
      final pack = await source.service.exportBytes();

      final target = await _Harness.create(
        documentsDirectory: () async =>
            throw const FileSystemException('备份目录不可写（测试注入）'),
      );
      addTearDown(target.dispose);
      await _seedQuestion(target, stem: '目标已有题。');

      final report = await target.service.importPack(pack.bytes);
      expect(report.createdCount, 1);
      expect(report.backupPath, isNull);
      expect(report.backupError, isNotNull);
      expect(report.backupError, contains('备份目录不可写'));

      final stems = <String>[
        for (final row in await target.db.select(target.db.questions).get())
          row.stem,
      ];
      expect(stems, hasLength(2));
      expect(stems, containsAll(<String>['目标已有题。', '要导入的题。']));
    });

    test('同一时间戳连续导入：两份备份，文件名用计数后缀避免覆盖', () async {
      await _seedQuestion(source, stem: '待导入题。');
      final pack = await source.service.exportBytes();

      final target = await _Harness.create();
      addTearDown(target.dispose);
      await _seedQuestion(target, stem: '目标已有题。');
      final now = DateTime.utc(2026, 10, 23, 6, 8, 10, 123);

      final first = await target.service.importPack(pack.bytes, now: now);
      final second = await target.service.importPack(pack.bytes, now: now);
      expect(first.createdCount, 1);
      expect(second.createdCount, 0);
      expect(second.skippedCount, 1);
      expect(first.backupPath, isNotNull);
      expect(second.backupPath, isNotNull);
      expect(first.backupPath, isNot(second.backupPath));
      expect(
        p.basename(first.backupPath!),
        '题库备份-20261023-060810-123.tqb',
      );
      expect(
        p.basename(second.backupPath!),
        '题库备份-20261023-060810-123-2.tqb',
      );

      final backupDirectory = Directory(
        p.join(target.support.path, kQuestionPackBackupFolderName),
      );
      final saved = backupDirectory.listSync().whereType<File>().toList();
      expect(saved, hasLength(2));
      final firstBackup = decodeQuestionPackArchive(
        File(first.backupPath!).readAsBytesSync(),
      );
      expect(firstBackup.records, hasLength(1));
      final secondBackup = decodeQuestionPackArchive(
        File(second.backupPath!).readAsBytesSync(),
      );
      expect(secondBackup.records, hasLength(2));
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

  static Future<_Harness> create({
    Future<Directory> Function()? documentsDirectory,
  }) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final support =
        Directory.systemTemp.createTempSync('furnace_question_pack_');
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
      // 备份要落到 documents 目录：默认注入本测试的临时目录，避免碰真实
      // path_provider（测试环境没有插件）。
      documentsDirectory: documentsDirectory ?? () async => support,
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

Future<Question> _seedQuestion(
  _Harness harness, {
  required String stem,
  List<QuestionOptionDraft> options = const <QuestionOptionDraft>[],
  Set<String> tagIds = const <String>{},
  String? sourceUrl,
  double? difficulty,
  int? year,
  String region = '',
  String origin = 'manual',
  String state = 'structured',
  String? trapNote,
}) async {
  final result = await harness.questions.ingest(QuestionDraft(
    stem: stem,
    answer: 'B',
    solution: '解析文字。',
    subjectKey: 'math',
    questionType: options.isEmpty ? 'solution' : 'single_choice',
    sourceLevel: 'gaokao',
    sourceLabel: '2024 湖南师大附中月考',
    year: year,
    region: region,
    sourceUrl: sourceUrl,
    difficulty: difficulty,
    difficultySource: difficulty == null ? null : 'manual',
    trapNote: trapNote,
    origin: origin,
    state: state,
    options: options,
    tagIds: tagIds,
  ));
  return result.question;
}
