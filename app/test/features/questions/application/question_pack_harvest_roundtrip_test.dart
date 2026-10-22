/// 抓题包 .tqb 端到端回归：外部抓题 agent 的合成包 → 导入 → 再导出解码。
///
/// 外部 agent 产出的包长这样：题干里有 LaTeX（美元符号包起来）与「［图N］」
/// 占位，配图分 role=stem 与 role=answer 两张（答案截图是 JPEG），来源三字段
/// （sourceUrl / zujuanQuestionId / zujuanBankId）与 tagPaths 一起写进
/// questions.json。这里不用「先建库再导出」造包，而是直接 encode 一个合成包，
/// 钉住真实管线：encodeQuestionPackArchive → QuestionPackService.importPack →
/// exportBytes → decodeQuestionPackArchive。不改生产代码。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/package/question_pack_codec.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/services/package/question_pack_manifest.dart';
import 'package:furnace/domain/services/package/question_pack_record.dart';
import 'package:furnace/features/questions/application/question_pack_service.dart';
import 'package:furnace/features/questions/data/question_media_store.dart';

/// 抓题 agent 包里的题干一：3 处 LaTeX + ［图1］ 占位。
const String _firstStem = r'阅读图文材料，若 $f(x)=x^{2}$ 在 $(0,+\infty)$ 上单调递增，'
    r'且 $\frac{1}{2}$ 为定义域内的值，结合 ［图1］ 判断下列说法。';

/// 第二道题：2 处 LaTeX + ［图2］ 占位，没有配图。
const String _secondStem = r'已知 $\sin x$ 的最小正周期为 $2\pi$，求 ［图2］ 中阴影部分的面积。';

const String _firstSolution =
    r'由 $f(x)=x^{2}$ 的单调性可知，区间 $(0,+\infty)$ 上恒增，故选 B。';

const String _tagPath = '文化课/生物/基因工程';
const String _sourceUrl = 'https://zujuan.xkw.com/10q35583902.html';
const String _zujuanQuestionId = '35583902';
const String _zujuanBankId = '10';

/// 极简 PNG 头 + 一个种子字节：只要求字节往返一致，不要求真能解码。
final Uint8List _stemPng = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x01,
]);

/// 极简 JPEG 头（JFIF）+ 填充：答案截图在真实包里就是 JPEG。
final Uint8List _answerJpeg = Uint8List.fromList(<int>[
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
  0x4A,
  0x46,
  0x49,
  0x46,
  0x00,
]);

final DateTime _importNow = DateTime.utc(2026, 10, 18, 12, 30);
final DateTime _exportNow = DateTime.utc(2026, 10, 18, 13, 0);

void main() {
  late _Harness target;

  setUp(() async {
    target = await _Harness.create();
  });

  tearDown(() async {
    await target.dispose();
  });

  test('合成抓题包自检：清单计数、公式与图占位、来源三字段、媒体角色', () {
    final archive = decodeQuestionPackArchive(_harvestPack().bytes);

    expect(archive.manifest.questionCount, 2);
    expect(archive.manifest.mediaCount, 2);
    expect(archive.mediaCount, 2);
    expect(archive.records, hasLength(2));

    final first = archive.records[0];
    expect(first.stem, _firstStem);
    expect(first.stem, contains(r'$f(x)=x^{2}$'));
    expect(first.stem, contains(r'$\frac{1}{2}$'));
    expect(first.stem, contains('［图1］'));
    expect(first.options, hasLength(4));
    expect(
      first.options
          .where((option) => option.isCorrect)
          .map((option) => option.label)
          .toList(),
      <String>['B'],
    );
    expect(first.sourceUrl, _sourceUrl);
    expect(first.zujuanQuestionId, _zujuanQuestionId);
    expect(first.zujuanBankId, _zujuanBankId);
    expect(first.tagPaths, <String>[_tagPath]);
    expect(first.media.map((item) => item.role).toList(),
        <String>['stem', 'answer']);
    expect(first.media.map((item) => item.sortOrder).toList(), <int>[0, 1]);
    expect(first.media.map((item) => item.mime).toList(),
        <String>['image/png', 'image/jpeg']);
    expect(archive.mediaBytes['media/q1/0.png'], equals(_stemPng));
    expect(archive.mediaBytes['media/q1/1.jpg'], equals(_answerJpeg));

    final second = archive.records[1];
    expect(second.stem, _secondStem);
    expect(second.stem, contains('［图2］'));
    expect(second.media, isEmpty);
  });

  test('导入空库：题号从 1 重新分配，题干里的公式与图占位原样保留', () async {
    final report = await target.service.importPack(
      _harvestPack().bytes,
      now: _importNow,
    );
    expect(report.createdCount, 2);
    expect(report.skippedCount, 0);
    expect(report.failures, isEmpty);

    final rows = await _questionsBySerial(target);
    expect(rows, hasLength(2));
    // 包里的 serial_no 是 99 / 42，导入不沿用，按本地题库重新分配。
    expect(rows.map((row) => row.serialNo).toList(), <int?>[1, 2]);
    expect(rows[0].stem, _firstStem);
    expect(rows[0].stem, contains('［图1］'));
    expect(rows[1].stem, _secondStem);
    expect(rows[1].stem, contains('［图2］'));
    expect(rows[0].questionType, 'single_choice');
    expect(rows[0].origin, 'ai_scan');
    expect(rows[0].state, 'raw');
  });

  test('导入保留组卷网来源三字段、年份地区与选项', () async {
    await target.service.importPack(_harvestPack().bytes, now: _importNow);
    final first = (await _questionsBySerial(target)).first;

    expect(first.sourceUrl, _sourceUrl);
    expect(first.zujuanQuestionId, _zujuanQuestionId);
    expect(first.zujuanBankId, _zujuanBankId);
    expect(first.sourceLevel, 'provincial_diagnostic');
    expect(first.sourceLabel, '2024 湖南师大附中月考');
    expect(first.year, 2024);
    expect(first.region, '湖南');
    expect(first.subjectKey, 'biology');
    expect(first.difficulty, 6.5);
    expect(first.solution, _firstSolution);

    final options = await target.questions.optionsOf(first.id);
    expect(options.map((option) => option.label).toList(),
        <String>['A', 'B', 'C', 'D']);
    expect(options[1].content, '单调递增');
    expect(
      options
          .where((option) => option.isCorrect)
          .map((option) => option.label)
          .toList(),
      <String>['B'],
    );
  });

  test('答案截图与题干配图落盘：role、sortOrder、MIME 与字节都保真', () async {
    await target.service.importPack(_harvestPack().bytes, now: _importNow);
    final rows = await _questionsBySerial(target);

    final images = await target.store.list(rows[0].id);
    expect(images, hasLength(2));
    expect(
        images.map((image) => image.role).toList(), <String>['stem', 'answer']);
    expect(images.map((image) => image.sortOrder).toList(), <int>[0, 1]);
    expect(images.map((image) => image.mime).toList(),
        <String>['image/png', 'image/jpeg']);
    expect(File(images[0].absolutePath).existsSync(), isTrue);
    expect(File(images[1].absolutePath).existsSync(), isTrue);
    expect(await target.store.readBytes(images[0].relPath), equals(_stemPng));
    expect(
        await target.store.readBytes(images[1].relPath), equals(_answerJpeg));

    expect(await target.store.list(rows[1].id), isEmpty);
  });

  test('tagPaths 落成标签并挂到 object_tags（目标库已有同一路径标签树）', () async {
    final leaf = await _createTagTree(target);
    expect(leaf.path, _tagPath);

    final report = await target.service.importPack(
      _harvestPack().bytes,
      now: _importNow,
    );
    expect(report.createdCount, 2);
    expect(report.warnings, isEmpty);

    final rows = await _questionsBySerial(target);
    for (final row in rows) {
      expect(await target.questions.tagIdsOf(row.id), contains(leaf.id));
    }
    final links = await (target.db.select(target.db.objectTags)
          ..where((t) => t.tagId.equals(leaf.id))
          ..where((t) => t.objectType.equals('question')))
        .get();
    expect(links, hasLength(2));
  });

  test('目标库没有该标签路径时只告警：题照建，不挂边', () async {
    final report = await target.service.importPack(
      _harvestPack().bytes,
      now: _importNow,
    );
    expect(report.createdCount, 2);
    expect(
        report.warnings.any((warning) => warning.contains(_tagPath)), isTrue);

    final rows = await _questionsBySerial(target);
    for (final row in rows) {
      expect(await target.questions.tagIdsOf(row.id), isEmpty);
    }
    expect(await target.db.select(target.db.objectTags).get(), isEmpty);
  });

  test('再导出并解码：题干、来源三字段、选项、媒体角色与字节都往返一致', () async {
    await _createTagTree(target);
    await target.service.importPack(_harvestPack().bytes, now: _importNow);

    final exported = await target.service.exportBytes(now: _exportNow);
    expect(exported.questionCount, 2);
    expect(exported.mediaCount, 2);
    expect(exported.warnings, isEmpty);

    final archive = decodeQuestionPackArchive(exported.bytes);
    expect(archive.manifest.questionCount, 2);
    expect(archive.manifest.mediaCount, 2);
    expect(archive.records, hasLength(2));

    final first = archive.records[0];
    expect(first.serialNo, 1);
    expect(first.stem, _firstStem);
    expect(first.sourceUrl, _sourceUrl);
    expect(first.zujuanQuestionId, _zujuanQuestionId);
    expect(first.zujuanBankId, _zujuanBankId);
    expect(first.tagPaths, <String>[_tagPath]);
    expect(first.options, hasLength(4));
    expect(first.options[1].isCorrect, isTrue);
    expect(first.media.map((item) => item.role).toList(),
        <String>['stem', 'answer']);
    expect(first.media.map((item) => item.mime).toList(),
        <String>['image/png', 'image/jpeg']);
    expect(archive.mediaBytes[first.media[0].packPath], equals(_stemPng));
    expect(archive.mediaBytes[first.media[1].packPath], equals(_answerJpeg));
  });

  test('第二次导入同一包：0 新增 / 2 跳过，题目、选项、配图都不重复', () async {
    final bytes = _harvestPack().bytes;
    final first = await target.service.importPack(bytes, now: _importNow);
    expect(first.createdCount, 2);
    expect(first.mediaCount, 2);

    final second = await target.service.importPack(bytes, now: _importNow);
    expect(second.createdCount, 0);
    expect(second.skippedCount, 2);
    expect(second.mediaCount, 0);
    expect(second.failures, isEmpty);
    expect(second.warnings, isNotEmpty);

    final rows = await _questionsBySerial(target);
    expect(rows, hasLength(2));
    expect(
        await target.db.select(target.db.questionOptions).get(), hasLength(4));
    expect(await target.db.select(target.db.attachments).get(), hasLength(2));
    expect(await target.store.list(rows[0].id), hasLength(2));
  });

  test('导入已有题库：题号接在最大号之后，已有题不被覆盖', () async {
    for (var index = 1; index <= 3; index++) {
      await target.questions.ingest(QuestionDraft(stem: '已有题 $index。'));
    }

    final report = await target.service.importPack(
      _harvestPack().bytes,
      now: _importNow,
    );
    expect(report.createdCount, 2);

    final rows = await _questionsBySerial(target);
    expect(rows, hasLength(5));
    expect(rows.map((row) => row.serialNo).toList(), <int?>[1, 2, 3, 4, 5]);
    expect(rows[3].stem, _firstStem);
    expect(rows[4].stem, _secondStem);
  });

  test('planImport 预检与实际导入口径一致：先 2 新增，后 2 跳过', () async {
    final pack = _harvestPack();
    final before = await target.service.planImport(pack.bytes);
    expect(before.recordCount, 2);
    expect(before.manifestQuestionCount, 2);
    expect(before.manifestMediaCount, 2);
    expect(before.mediaCount, 2);
    expect(before.createCount, 2);
    expect(before.skipCount, 0);
    expect(before.missingTagPaths, <String>[_tagPath]);
    expect(before.missingTagCount, 1);

    await target.service.importPack(pack.bytes, now: _importNow);

    final after = await target.service.planImport(pack.bytes);
    expect(after.createCount, 0);
    expect(after.skipCount, 2);
    expect(after.missingTagCount, 1);
  });
}

/// 一份「外部抓题 agent 产出」的合成包：2 道题、2 张图（题干 PNG + 答案 JPEG）。
_HarvestPack _harvestPack() {
  final records = <QuestionPackRecord>[
    const QuestionPackRecord(
      stem: _firstStem,
      answer: 'B',
      solution: _firstSolution,
      subjectKey: 'biology',
      questionType: 'single_choice',
      sourceLevel: 'provincial_diagnostic',
      sourceLabel: '2024 湖南师大附中月考',
      year: 2024,
      region: '湖南',
      difficulty: 6.5,
      difficultySource: 'manual',
      origin: 'ai_scan',
      state: 'raw',
      serialNo: 99,
      sourceUrl: _sourceUrl,
      zujuanQuestionId: _zujuanQuestionId,
      zujuanBankId: _zujuanBankId,
      options: <QuestionPackOption>[
        QuestionPackOption(label: 'A', content: '单调递减', sortOrder: 0),
        QuestionPackOption(
            label: 'B', content: '单调递增', isCorrect: true, sortOrder: 1),
        QuestionPackOption(label: 'C', content: '先减后增', sortOrder: 2),
        QuestionPackOption(label: 'D', content: '无法判断', sortOrder: 3),
      ],
      tagPaths: <String>[_tagPath],
      media: <QuestionPackMedia>[
        QuestionPackMedia(
          packPath: 'media/q1/0.png',
          fileName: 'stem-1.png',
          mime: 'image/png',
          role: 'stem',
          sortOrder: 0,
        ),
        QuestionPackMedia(
          packPath: 'media/q1/1.jpg',
          fileName: 'answer-1.jpg',
          mime: 'image/jpeg',
          role: 'answer',
          sortOrder: 1,
        ),
      ],
    ),
    const QuestionPackRecord(
      stem: _secondStem,
      answer: 'A',
      solution: r'由 $T=2\pi$ 得最小正周期为 $2\pi$。',
      subjectKey: 'math',
      questionType: 'solution',
      sourceLevel: 'school',
      sourceLabel: '2024 湖南师大附中月考',
      year: 2024,
      region: '湖南',
      difficulty: 5,
      difficultySource: 'manual',
      origin: 'ai_scan',
      state: 'raw',
      serialNo: 42,
      tagPaths: <String>[_tagPath],
      media: <QuestionPackMedia>[],
    ),
  ];
  final manifest = QuestionPackManifest(
    exportedAt: DateTime.utc(2026, 10, 18, 12, 0),
    appVersion: '0.5.20-harvest',
    questionCount: records.length,
    mediaCount: 2,
    generatedBy: 'harvest-agent',
  );
  final bytes = encodeQuestionPackArchive(
    manifest: manifest,
    records: records,
    mediaBytes: <String, Uint8List>{
      'media/q1/0.png': _stemPng,
      'media/q1/1.jpg': _answerJpeg,
    },
  );
  return _HarvestPack(bytes: bytes, records: records);
}

/// 目标库里建好 文化课/生物/基因工程 这棵树，返回叶子标签。
Future<Tag> _createTagTree(_Harness harness) async {
  final top = await harness.tags.createTag(name: '文化课');
  final middle = await harness.tags.createTag(name: '生物', parentId: top.id);
  return harness.tags.createTag(name: '基因工程', parentId: middle.id);
}

/// 按题号升序取出题目行（导入分配 1..N）。
Future<List<Question>> _questionsBySerial(_Harness harness) async {
  final rows = await harness.db.select(harness.db.questions).get();
  rows.sort(
      (left, right) => (left.serialNo ?? 0).compareTo(right.serialNo ?? 0));
  return rows;
}

/// 一个合成包：zip 字节 + 造包用的记录（便于断言「导出的就是进去的」）。
class _HarvestPack {
  const _HarvestPack({required this.bytes, required this.records});

  final Uint8List bytes;
  final List<QuestionPackRecord> records;
}

/// 数据库 + 临时 media 目录 + 三个仓库 + service（与 question_pack_service_test 同构）。
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
        Directory.systemTemp.createTempSync('furnace_harvest_roundtrip_');
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
