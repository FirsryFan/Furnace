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

QuestionPackRecord _record({
  String stem = '题干',
  String? answer,
  String? solution,
  String? zujuanQuestionId = 'qid-1',
  String? zujuanBankId = '13',
  String questionType = 'solution',
  String subjectKey = 'physics',
  List<QuestionPackOption> options = const <QuestionPackOption>[],
  List<QuestionPackMedia> media = const <QuestionPackMedia>[],
  List<String> tagPaths = const <String>[],
}) {
  final String qid = zujuanQuestionId ?? '';
  return QuestionPackRecord(
    stem: stem,
    answer: answer,
    solution: solution,
    subjectKey: subjectKey,
    questionType: questionType,
    sourceLevel: 'gaokao',
    sourceLabel: '2025 湖南高考模拟',
    year: 2025,
    region: '湖南',
    difficulty: 8.1,
    difficultySource: 'computed',
    origin: 'ai_scan',
    state: 'structured',
    sourceUrl:
        zujuanQuestionId == null ? null : 'https://zujuan.xkw.com/13q$qid.html',
    zujuanQuestionId: zujuanQuestionId,
    zujuanBankId: zujuanBankId,
    options: options,
    tagPaths: tagPaths,
    media: media,
  );
}

QuestionPackMedia _media(
  String packPath,
  String role, {
  int sortOrder = 0,
}) =>
    QuestionPackMedia(
      packPath: packPath,
      fileName: packPath.split('/').last,
      mime: role == 'answer' ? 'image/jpeg' : 'image/png',
      role: role,
      sortOrder: sortOrder,
    );

Uint8List _bytes(int seed) =>
    Uint8List.fromList(<int>[seed, 0x89, 0x50, 0x4E, 0x47, seed + 1, 0x0A]);

Uint8List _pack(
  List<QuestionPackRecord> records, {
  Map<String, Uint8List> media = const <String, Uint8List>{},
}) =>
    encodeQuestionPackArchive(
      manifest: QuestionPackManifest(
        exportedAt: DateTime(2026, 10, 22, 16, 3),
        appVersion: '0.6.0+19',
        questionCount: records.length,
        mediaCount: media.length,
        generatedBy: 'zujuan-harvest',
      ),
      records: records,
      mediaBytes: media,
    );

void main() {
  group('按组卷网题号更新已有题目（轮次一百四十五）', () {
    test('同一个包导两次：第二次 0 新建、全部按题号更新，题号与题数不变', () async {
      final _Harness harness = await _Harness.create();
      addTearDown(harness.dispose);
      final Uint8List pack = _pack(<QuestionPackRecord>[
        _record(stem: '第一题', zujuanQuestionId: '27596881'),
        _record(stem: '第二题', zujuanQuestionId: '27596882'),
        _record(stem: '第三题', zujuanQuestionId: '27596883'),
      ]);

      final QuestionPackImportReport first =
          await harness.service.importPack(pack);
      expect(first.createdCount, 3);
      expect(first.updatedCount, 0);
      expect(first.skippedCount, 0);

      final List<Question> before = await harness.questions.all();
      final Map<String, int?> serialByStem = <String, int?>{
        for (final Question question in before)
          question.stem: question.serialNo,
      };

      final QuestionPackImportReport second =
          await harness.service.importPack(pack);
      expect(second.createdCount, 0);
      expect(second.updatedCount, 3);
      expect(second.skippedCount, 0);

      final List<Question> after = await harness.questions.all();
      expect(after.length, 3);
      for (final Question question in after) {
        expect(question.serialNo, serialByStem[question.stem]);
      }
    });

    test('第二次带答案与解析：文字被覆盖，题干同步更新', () async {
      final _Harness harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.service.importPack(_pack(<QuestionPackRecord>[
        _record(stem: '求木块速度', zujuanQuestionId: '27596882'),
      ]));
      final Question created = (await harness.questions.all()).single;
      expect(created.answer, isNull);

      final QuestionPackImportReport report = await harness.service.importPack(
        _pack(<QuestionPackRecord>[
          _record(
            stem: '求木块速度（修正版）',
            zujuanQuestionId: '27596882',
            answer: 'B',
            solution: '由动量守恒可得。',
          ),
        ]),
      );
      expect(report.updatedCount, 1);
      expect(report.createdCount, 0);

      final Question updated = (await harness.questions.byId(created.id))!;
      expect(updated.answer, 'B');
      expect(updated.solution, '由动量守恒可得。');
      expect(updated.stem, '求木块速度（修正版）');
    });

    test('只带答案图的升级包：题干图保留，答案图整体替换', () async {
      final _Harness harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.service.importPack(
        _pack(
          <QuestionPackRecord>[
            _record(
              stem: '题一',
              zujuanQuestionId: '27596882',
              media: <QuestionPackMedia>[
                _media('media/stem_1.png', 'stem'),
                _media('media/answer_1.jpg', 'answer'),
              ],
            ),
          ],
          media: <String, Uint8List>{
            'media/stem_1.png': _bytes(1),
            'media/answer_1.jpg': _bytes(2),
          },
        ),
      );
      final Question question = (await harness.questions.all()).single;
      expect((await harness.store.list(question.id, role: 'stem')).length, 1);
      expect((await harness.store.list(question.id, role: 'answer')).length, 1);

      await harness.service.importPack(
        _pack(
          <QuestionPackRecord>[
            _record(
              stem: '题一',
              zujuanQuestionId: '27596882',
              media: <QuestionPackMedia>[
                _media('media/answer_2.jpg', 'answer'),
              ],
            ),
          ],
          media: <String, Uint8List>{'media/answer_2.jpg': _bytes(9)},
        ),
      );

      final List<QuestionImage> stemImages =
          await harness.store.list(question.id, role: 'stem');
      final List<QuestionImage> answerImages =
          await harness.store.list(question.id, role: 'answer');
      expect(stemImages.length, 1);
      expect(stemImages.single.fileName, 'stem_1.png');
      expect(answerImages.length, 1);
      expect(answerImages.single.fileName, 'answer_2.jpg');
    });

    test('升级包没有配图时一张都不删', () async {
      final _Harness harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.service.importPack(
        _pack(
          <QuestionPackRecord>[
            _record(
              stem: '题一',
              zujuanQuestionId: '27596882',
              media: <QuestionPackMedia>[
                _media('media/stem_1.png', 'stem'),
                _media('media/answer_1.jpg', 'answer'),
              ],
            ),
          ],
          media: <String, Uint8List>{
            'media/stem_1.png': _bytes(1),
            'media/answer_1.jpg': _bytes(2),
          },
        ),
      );
      final Question question = (await harness.questions.all()).single;

      final QuestionPackImportReport report =
          await harness.service.importPack(_pack(<QuestionPackRecord>[
        _record(
          stem: '题一',
          zujuanQuestionId: '27596882',
          answer: 'C',
        ),
      ]));
      expect(report.updatedCount, 1);
      expect(report.mediaCount, 0);
      expect((await harness.store.list(question.id, role: 'stem')).length, 1);
      expect((await harness.store.list(question.id, role: 'answer')).length, 1);
    });

    test('题名与题号不覆盖：用户起的名字留给用户', () async {
      final _Harness harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.service.importPack(_pack(<QuestionPackRecord>[
        _record(stem: '原题干', zujuanQuestionId: '27596882'),
      ]));
      final Question created = (await harness.questions.all()).single;
      await harness.questions.setQuestionTitle(created.id, '我自己的题名');

      await harness.service.importPack(_pack(<QuestionPackRecord>[
        _record(stem: '新题干', zujuanQuestionId: '27596882'),
      ]));

      final Question updated = (await harness.questions.byId(created.id))!;
      expect(updated.title, '我自己的题名');
      expect(updated.serialNo, created.serialNo);
      expect(updated.stem, '新题干');
    });

    test('没有组卷网题号时仍按题干指纹跳过', () async {
      final _Harness harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.service.importPack(_pack(<QuestionPackRecord>[
        _record(stem: '同一道题', zujuanQuestionId: null),
      ]));
      final QuestionPackImportReport report = await harness.service.importPack(
        _pack(<QuestionPackRecord>[
          _record(stem: '同一道题', zujuanQuestionId: null),
        ]),
      );
      expect(report.createdCount, 0);
      expect(report.updatedCount, 0);
      expect(report.skippedCount, 1);
      expect((await harness.questions.all()).length, 1);
    });

    test('planImport 的 updateCount 与实际导入一致', () async {
      final _Harness harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.service.importPack(_pack(<QuestionPackRecord>[
        _record(stem: '题一', zujuanQuestionId: '27596882'),
        _record(stem: '题二', zujuanQuestionId: '27596883'),
      ]));
      final Uint8List upgrade = _pack(<QuestionPackRecord>[
        _record(stem: '题一', zujuanQuestionId: '27596882', answer: 'A'),
        _record(stem: '题二', zujuanQuestionId: '27596883', answer: 'B'),
      ]);

      final preview = await harness.service.planImport(upgrade);
      expect(preview.updateCount, 2);
      expect(preview.createCount, 0);
      expect(preview.skipCount, 0);
      expect(preview.hasUpdates, isTrue);
      expect(preview.summaryZh[1], contains('更新已有 2 道'));

      final QuestionPackImportReport report =
          await harness.service.importPack(upgrade);
      expect(report.updatedCount, preview.updateCount);
    });

    test('选项非空时整体替换，空时不删旧选项', () async {
      final _Harness harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.service.importPack(_pack(<QuestionPackRecord>[
        _record(
          stem: '选择题',
          zujuanQuestionId: '27596882',
          questionType: 'single_choice',
          options: <QuestionPackOption>[
            const QuestionPackOption(label: 'A', content: '甲', sortOrder: 0),
            const QuestionPackOption(
                label: 'B', content: '乙', isCorrect: true, sortOrder: 1),
          ],
        ),
      ]));
      final Question question = (await harness.questions.all()).single;

      await harness.service.importPack(_pack(<QuestionPackRecord>[
        _record(
          stem: '选择题',
          zujuanQuestionId: '27596882',
          questionType: 'single_choice',
          options: <QuestionPackOption>[
            const QuestionPackOption(label: 'A', content: '甲改', sortOrder: 0),
            const QuestionPackOption(label: 'C', content: '丙', sortOrder: 1),
          ],
        ),
      ]));
      final List<QuestionOption> options =
          await harness.questions.optionsOf(question.id);
      expect(options.map((QuestionOption option) => option.label),
          <String>['A', 'C']);
      expect(options.first.content, '甲改');
      expect(options.any((QuestionOption option) => option.isCorrect), isFalse);

      await harness.service.importPack(_pack(<QuestionPackRecord>[
        _record(
          stem: '选择题',
          zujuanQuestionId: '27596882',
          questionType: 'single_choice',
        ),
      ]));
      expect((await harness.questions.optionsOf(question.id)).length, 2);
    });

    test('标签只补挂不删旧：升级包新增的标签路径挂上，旧标签保留', () async {
      final _Harness harness = await _Harness.create();
      addTearDown(harness.dispose);
      final Tag root = await harness.tags.createTag(name: '生物');
      final Tag gene = await harness.tags.createTag(
        name: '基因工程',
        parentId: root.id,
      );
      await harness.service.importPack(_pack(<QuestionPackRecord>[
        _record(
          stem: '题一',
          zujuanQuestionId: '27596882',
          tagPaths: <String>[gene.path ?? ''],
        ),
      ]));
      final Question question = (await harness.questions.all()).single;

      final Tag extra = await harness.tags.createTag(
        name: '新标签',
        parentId: root.id,
      );
      await harness.service.importPack(_pack(<QuestionPackRecord>[
        _record(
          stem: '题一',
          zujuanQuestionId: '27596882',
          tagPaths: <String>[gene.path ?? '', extra.path ?? ''],
        ),
      ]));

      final List<Tag> tags = await harness.tags.tagsForObject(
        objectType: 'question',
        objectId: question.id,
      );
      expect(
        tags.map((Tag tag) => tag.path).toSet(),
        <String?>{gene.path, extra.path},
      );
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
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
    final Directory support =
        Directory.systemTemp.createTempSync('furnace_pack_update_');
    final QuestionMediaStore store = QuestionMediaStore(
      database: db,
      supportDirectory: () async => support,
    );
    final QuestionRepository questions = QuestionRepository(db);
    final TagRepository tags = TagRepository(db);
    final QuestionPackService service = QuestionPackService(
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
