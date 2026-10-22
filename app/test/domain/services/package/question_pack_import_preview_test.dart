import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/package/question_pack_import_preview.dart';
import 'package:furnace/domain/services/package/question_pack_manifest.dart';
import 'package:furnace/domain/services/package/question_pack_plan.dart';
import 'package:furnace/domain/services/package/question_pack_record.dart';

QuestionPackManifest _manifest({
  required int questionCount,
  required int mediaCount,
  DateTime? exportedAt,
  String appVersion = '0.5.8+137',
}) =>
    QuestionPackManifest(
      exportedAt: exportedAt ?? DateTime(2026, 10, 21, 4, 40),
      appVersion: appVersion,
      questionCount: questionCount,
      mediaCount: mediaCount,
    );

QuestionPackRecord _record({String stem = '题干', int mediaCount = 0}) =>
    QuestionPackRecord(
      stem: stem,
      media: <QuestionPackMedia>[
        for (var index = 0; index < mediaCount; index++)
          QuestionPackMedia(packPath: 'media/q$index.png'),
      ],
    );

/// 一道「整卡快照」题：题干末尾追加 [placeholderCount] 处「［图N］」占位，
/// 媒体里放 [stemMedia] 张题干图（role 默认 stem）与 [answerMedia] 张答案截图。
QuestionPackRecord _stemSnapshotRecord({
  int placeholderCount = 2,
  int stemMedia = 1,
  int answerMedia = 0,
  String stemPrefix = '读图作答：',
}) {
  final StringBuffer buffer = StringBuffer(stemPrefix);
  for (var index = 1; index <= placeholderCount; index++) {
    buffer.write('［图$index］');
  }
  return QuestionPackRecord(
    stem: buffer.toString(),
    media: <QuestionPackMedia>[
      for (var index = 0; index < stemMedia; index++)
        QuestionPackMedia(packPath: 'media/stem-$index.png'),
      for (var index = 0; index < answerMedia; index++)
        QuestionPackMedia(
          packPath: 'media/answer-$index.jpg',
          role: 'answer',
        ),
    ],
  );
}

QuestionPackImportPlan _plan({
  int create = 0,
  int skip = 0,
  List<String> warnings = const <String>[],
  List<String> missingTagPaths = const <String>[],
}) =>
    QuestionPackImportPlan(
      decisions: <QuestionPackDecision>[
        for (var index = 0; index < create + skip; index++)
          QuestionPackDecision(
            index: index,
            action: index < create
                ? QuestionPackAction.create
                : QuestionPackAction.skipDuplicate,
            stemPreview: '第 $index 道',
            skipReason: index < create ? null : '题库里已经有同一道题（题干指纹相同）',
          ),
      ],
      warnings: warnings,
      missingTagPaths: missingTagPaths,
    );

QuestionPackImportPreview _previewOf({
  required QuestionPackManifest manifest,
  required List<QuestionPackRecord> records,
  required QuestionPackImportPlan plan,
}) =>
    buildQuestionPackImportPreview(
      manifest: manifest,
      records: records,
      plan: plan,
    );

QuestionPackImportPreview _direct({
  int manifestQuestionCount = 1,
  int manifestMediaCount = 0,
  int recordCount = 1,
  int mediaCount = 0,
  String appVersion = '0.5.8+137',
  DateTime? exportedAt,
  int createCount = 1,
  int skipCount = 0,
  int? missingTagCount,
  List<String> warnings = const <String>[],
  List<String> missingTagPaths = const <String>[],
  int snapshotLikeCount = 0,
}) =>
    QuestionPackImportPreview(
      manifestQuestionCount: manifestQuestionCount,
      manifestMediaCount: manifestMediaCount,
      recordCount: recordCount,
      mediaCount: mediaCount,
      appVersion: appVersion,
      exportedAt: exportedAt,
      createCount: createCount,
      skipCount: skipCount,
      missingTagCount: missingTagCount ?? missingTagPaths.length,
      warnings: warnings,
      missingTagPaths: missingTagPaths,
      snapshotLikeCount: snapshotLikeCount,
    );

void main() {
  group('buildQuestionPackImportPreview：计数', () {
    test('全新增包：题数、媒体数、新增数都来自各自输入', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 2, mediaCount: 3),
        records: <QuestionPackRecord>[
          _record(mediaCount: 2),
          _record(mediaCount: 1),
        ],
        plan: _plan(create: 2),
      );
      expect(preview.manifestQuestionCount, 2);
      expect(preview.manifestMediaCount, 3);
      expect(preview.recordCount, 2);
      expect(preview.mediaCount, 3);
      expect(preview.createCount, 2);
      expect(preview.skipCount, 0);
      expect(preview.missingTagCount, 0);
      expect(preview.appVersion, '0.5.8+137');
      expect(preview.exportedAt, DateTime(2026, 10, 21, 4, 40));
    });

    test('部分跳过：createCount 与 skipCount 直接取计划', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 3, mediaCount: 0),
        records: <QuestionPackRecord>[_record(), _record(), _record()],
        plan: _plan(create: 1, skip: 2),
      );
      expect(preview.recordCount, 3);
      expect(preview.createCount, 1);
      expect(preview.skipCount, 2);
    });

    test('全跳过：一道也不新建', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 2, mediaCount: 0),
        records: <QuestionPackRecord>[_record(), _record()],
        plan: _plan(skip: 2),
      );
      expect(preview.createCount, 0);
      expect(preview.skipCount, 2);
      expect(preview.isFullyNew, isFalse);
    });

    test('空包：记录、媒体、计数都为 0', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 0, mediaCount: 0),
        records: const <QuestionPackRecord>[],
        plan: _plan(),
      );
      expect(preview.recordCount, 0);
      expect(preview.mediaCount, 0);
      expect(preview.isEmpty, isTrue);
      expect(preview.isFullyNew, isFalse);
      expect(preview.warnings, isEmpty);
      expect(preview.missingTagPaths, isEmpty);
    });

    test('missingTagCount 与 missingTagPaths 都来自计划', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 0),
        records: <QuestionPackRecord>[_record()],
        plan: _plan(
          create: 1,
          missingTagPaths: <String>['数学/函数', '物理/力学'],
        ),
      );
      expect(preview.missingTagCount, 2);
      expect(preview.missingTagPaths, <String>['数学/函数', '物理/力学']);
    });
  });

  group('清单对账', () {
    test('题数与媒体数都对得上时没有清单层警告', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 2, mediaCount: 2),
        records: <QuestionPackRecord>[
          _record(mediaCount: 1),
          _record(mediaCount: 1)
        ],
        plan: _plan(create: 2),
      );
      expect(preview.hasManifestMismatch, isFalse);
      expect(preview.warnings, isEmpty);
    });

    test('题数对不上时按口径给出警告', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 3, mediaCount: 0),
        records: <QuestionPackRecord>[_record(), _record()],
        plan: _plan(create: 2),
      );
      expect(preview.hasManifestMismatch, isTrue);
      expect(preview.warnings, <String>['包清单写着 3 道题，实际读到 2 道']);
    });

    test('媒体数对不上时按口径给出警告', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 2, mediaCount: 5),
        records: <QuestionPackRecord>[
          _record(mediaCount: 1),
          _record(mediaCount: 1)
        ],
        plan: _plan(create: 2),
      );
      expect(preview.hasManifestMismatch, isTrue);
      expect(preview.warnings, <String>['包清单写着 5 张配图，实际读到 2 张']);
    });

    test('两处都不一致时先题数后媒体数', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 9, mediaCount: 4),
        records: <QuestionPackRecord>[_record(mediaCount: 1)],
        plan: _plan(create: 1),
      );
      expect(preview.hasManifestMismatch, isTrue);
      expect(preview.warnings, <String>[
        '包清单写着 9 道题，实际读到 1 道',
        '包清单写着 4 张配图，实际读到 1 张',
      ]);
    });

    test('只有计划警告、清单一致时不算清单不一致', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 0),
        records: <QuestionPackRecord>[_record()],
        plan: _plan(create: 1, warnings: <String>['计划提示']),
      );
      expect(preview.hasManifestMismatch, isFalse);
      expect(preview.warnings, <String>['计划提示']);
    });
  });

  group('warnings 合并与去重', () {
    test('清单层警告在前，计划警告保持原顺序', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 2, mediaCount: 0),
        records: <QuestionPackRecord>[_record()],
        plan: _plan(create: 1, warnings: <String>['甲', '乙']),
      );
      expect(preview.warnings, <String>['包清单写着 2 道题，实际读到 1 道', '甲', '乙']);
    });

    test('完全相同的字符串去重且保留第一次出现', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 0),
        records: <QuestionPackRecord>[_record()],
        plan: _plan(create: 1, warnings: <String>['重复提示', '其它', '重复提示']),
      );
      expect(preview.warnings, <String>['重复提示', '其它']);
    });

    test('计划警告与清单层文案相同时只保留清单层那一条', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 2, mediaCount: 0),
        records: <QuestionPackRecord>[_record()],
        plan: _plan(
          create: 1,
          warnings: <String>['包清单写着 2 道题，实际读到 1 道'],
        ),
      );
      expect(preview.warnings, <String>['包清单写着 2 道题，实际读到 1 道']);
    });

    test('不修改传入的计划警告列表', () {
      final List<String> planWarnings = <String>['计划提示'];
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 0),
        records: <QuestionPackRecord>[_record()],
        plan: _plan(create: 1, warnings: planWarnings),
      );
      expect(preview.warnings, <String>['计划提示']);
      expect(planWarnings, <String>['计划提示']);
    });

    test('合并后的 warnings 是不可变列表', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 0),
        records: <QuestionPackRecord>[_record()],
        plan: _plan(create: 1),
      );
      expect(() => preview.warnings.add('x'), throwsUnsupportedError);
      expect(() => preview.missingTagPaths.add('x'), throwsUnsupportedError);
    });

    test('空包但清单写着有题时两条不一致都报', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 3, mediaCount: 2),
        records: const <QuestionPackRecord>[],
        plan: _plan(),
      );
      expect(preview.warnings, <String>[
        '包清单写着 3 道题，实际读到 0 道',
        '包清单写着 2 张配图，实际读到 0 张',
      ]);
    });
  });

  group('状态 getter', () {
    test('isFullyNew 三态：全新增真、部分跳过假、全跳过假', () {
      final QuestionPackImportPreview allNew = _previewOf(
        manifest: _manifest(questionCount: 2, mediaCount: 0),
        records: <QuestionPackRecord>[_record(), _record()],
        plan: _plan(create: 2),
      );
      final QuestionPackImportPreview partial = _previewOf(
        manifest: _manifest(questionCount: 2, mediaCount: 0),
        records: <QuestionPackRecord>[_record(), _record()],
        plan: _plan(create: 1, skip: 1),
      );
      final QuestionPackImportPreview allSkipped = _previewOf(
        manifest: _manifest(questionCount: 2, mediaCount: 0),
        records: <QuestionPackRecord>[_record(), _record()],
        plan: _plan(skip: 2),
      );
      expect(allNew.isFullyNew, isTrue);
      expect(partial.isFullyNew, isFalse);
      expect(allSkipped.isFullyNew, isFalse);
    });

    test('isEmpty 只看题目条数', () {
      expect(_direct(recordCount: 0, createCount: 0).isEmpty, isTrue);
      expect(_direct(recordCount: 1).isEmpty, isFalse);
    });

    test('hasWarnings 跟随合并后的提示', () {
      expect(_direct(warnings: const <String>['提示']).hasWarnings, isTrue);
      expect(_direct(warnings: const <String>[]).hasWarnings, isFalse);
    });

    test('hasManifestMismatch 只在计数对不上时为真', () {
      expect(_direct().hasManifestMismatch, isFalse);
      expect(_direct(manifestMediaCount: 2).hasManifestMismatch, isTrue);
    });
  });

  group('summaryZh', () {
    test('全新增：第一行带 App 版本与导出时间，第二行新增数', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 2, mediaCount: 1),
        records: <QuestionPackRecord>[_record(mediaCount: 1), _record()],
        plan: _plan(create: 2),
      );
      expect(preview.summaryZh, <String>[
        '包里共 2 道题、1 张配图（导出自 App 0.5.8+137，2026-10-21 04:40）',
        '导入后新增 2 道',
      ]);
    });

    test('部分跳过：第二行同时给出新增与跳过', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 3, mediaCount: 0),
        records: <QuestionPackRecord>[_record(), _record(), _record()],
        plan: _plan(create: 1, skip: 2),
      );
      expect(preview.summaryZh[1], '导入后新增 1 道，跳过 2 道（题库里已有同一道题，或包里重复）');
    });

    test('全跳过：第二行只有跳过', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 2, mediaCount: 0),
        records: <QuestionPackRecord>[_record(), _record()],
        plan: _plan(skip: 2),
      );
      expect(preview.summaryZh[1], '跳过 2 道（题库里已有同一道题，或包里重复）');
    });

    test('一道也导不进去时第二行是固定文案', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 2, mediaCount: 0),
        records: <QuestionPackRecord>[_record(), _record()],
        plan: _plan(),
      );
      expect(preview.summaryZh[1], '包里没有可以导入的新题');
    });

    test('缺失标签非 0 时第三行', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 0),
        records: <QuestionPackRecord>[_record()],
        plan: _plan(
          create: 1,
          missingTagPaths: <String>['数学/函数', '物理/力学', '化学/有机'],
        ),
      );
      expect(preview.summaryZh, <String>[
        '包里共 1 道题、0 张配图（导出自 App 0.5.8+137，2026-10-21 04:40）',
        '导入后新增 1 道',
        '有 3 个标签在本题库里不存在，相关题导入后不挂这些标签',
      ]);
    });

    test('有提示时最后一行给条数', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 2, mediaCount: 0),
        records: <QuestionPackRecord>[_record()],
        plan: _plan(create: 1, warnings: <String>['计划提示一', '计划提示二']),
      );
      expect(preview.warnings.length, 3);
      expect(preview.summaryZh, <String>[
        '包里共 1 道题、0 张配图（导出自 App 0.5.8+137，2026-10-21 04:40）',
        '导入后新增 1 道',
        '另有 3 条提示（见下）',
      ]);
    });

    test('exportedAt 为空时省略括号内时间', () {
      final QuestionPackImportPreview preview = _direct(exportedAt: null);
      expect(
        preview.summaryZh.first,
        '包里共 1 道题、0 张配图（导出自 App 0.5.8+137）',
      );
    });

    test('appVersion 为空白时只留时间，两者都空时没有括号', () {
      final QuestionPackImportPreview withTime = _direct(
        appVersion: '  ',
        exportedAt: DateTime(2026, 1, 2, 3, 4),
      );
      expect(withTime.summaryZh.first, '包里共 1 道题、0 张配图（2026-01-02 03:04）');

      final QuestionPackImportPreview noDetails = _direct(
        appVersion: '',
        exportedAt: null,
      );
      expect(noDetails.summaryZh.first, '包里共 1 道题、0 张配图');
    });

    test('summaryZh 至少两行、确定性且不可变', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 0),
        records: <QuestionPackRecord>[_record()],
        plan: _plan(create: 1),
      );
      final List<String> first = preview.summaryZh;
      final List<String> second = preview.summaryZh;
      expect(first.length, greaterThanOrEqualTo(2));
      expect(first, second);
      expect(() => first.add('x'), throwsUnsupportedError);
    });
  });

  group('toJson 与值语义', () {
    test('toJson 键序固定、导出时间是 ISO-8601', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 1),
        records: <QuestionPackRecord>[_record(mediaCount: 1)],
        plan: _plan(create: 1, missingTagPaths: <String>['数学/函数']),
      );
      final Map<String, Object?> json = preview.toJson();
      expect(json.keys.toList(), <String>[
        'manifest_question_count',
        'manifest_media_count',
        'record_count',
        'media_count',
        'app_version',
        'exported_at',
        'create_count',
        'skip_count',
        'missing_tag_count',
        'snapshot_like_count',
        'warnings',
        'missing_tag_paths',
      ]);
      expect(json['exported_at'], '2026-10-21T04:40:00.000');
      expect(json['record_count'], 1);
      expect(json['media_count'], 1);
      expect(json['create_count'], 1);
      expect(json['missing_tag_count'], 1);
    });

    test('exportedAt 为空时 exported_at 输出 null', () {
      final Map<String, Object?> json = _direct(exportedAt: null).toJson();
      expect(json.containsKey('exported_at'), isTrue);
      expect(json['exported_at'], isNull);
    });

    test('toJson 输出的列表是拷贝，改动不影响预检对象', () {
      final QuestionPackImportPreview preview = _direct(
        warnings: const <String>['提示'],
        missingTagPaths: const <String>['数学/函数'],
      );
      final Map<String, Object?> json = preview.toJson();
      (json['warnings']! as List<String>).add('x');
      (json['missing_tag_paths']! as List<String>).add('y');
      expect(preview.warnings, <String>['提示']);
      expect(preview.missingTagPaths, <String>['数学/函数']);
    });

    test('== 与 hashCode 按全部字段与列表内容比较', () {
      final QuestionPackImportPreview left = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 0),
        records: <QuestionPackRecord>[_record()],
        plan: _plan(create: 1, warnings: <String>['提示']),
      );
      final QuestionPackImportPreview right = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 0),
        records: <QuestionPackRecord>[_record()],
        plan: _plan(create: 1, warnings: <String>['提示']),
      );
      expect(left, right);
      expect(left.hashCode, right.hashCode);
      expect(left == _direct(appVersion: '别的版本'), isFalse);
      expect(
        _direct(warnings: const <String>['a', 'b']) ==
            _direct(warnings: const <String>['b', 'a']),
        isFalse,
      );
    });

    test('toString 带主要计数', () {
      final String text =
          _direct(recordCount: 2, createCount: 1, skipCount: 1).toString();
      expect(text, contains('recordCount: 2'));
      expect(text, contains('createCount: 1'));
      expect(text, contains('skipCount: 1'));
    });
  });

  group('整卡快照（题干只有一张整题截图）', () {
    const String snapshotWarning = '这个包是整卡快照包：1 道题的题干只有一张整题截图，'
        '公式以「［图N］」占位显示；详情页会按原题整图展示。';

    test('两处占位 + 一张题干图：命中计数并给告警', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 1),
        records: <QuestionPackRecord>[_stemSnapshotRecord()],
        plan: _plan(create: 1),
      );
      expect(preview.snapshotLikeCount, 1);
      expect(preview.warnings, <String>[snapshotWarning]);
      expect(preview.hasWarnings, isTrue);
    });

    test('只出现一处占位不算快照', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 1),
        records: <QuestionPackRecord>[
          _stemSnapshotRecord(placeholderCount: 1),
        ],
        plan: _plan(create: 1),
      );
      expect(preview.snapshotLikeCount, 0);
      expect(preview.warnings, isEmpty);
    });

    test('题干图两张不算快照（不是一张整题截图）', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 2),
        records: <QuestionPackRecord>[
          _stemSnapshotRecord(placeholderCount: 5, stemMedia: 2),
        ],
        plan: _plan(create: 1),
      );
      expect(preview.snapshotLikeCount, 0);
      expect(preview.warnings, isEmpty);
    });

    test('没有题干图（只有答案截图）不算快照', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 1),
        records: <QuestionPackRecord>[
          _stemSnapshotRecord(
            placeholderCount: 3,
            stemMedia: 0,
            answerMedia: 1,
          ),
        ],
        plan: _plan(create: 1),
      );
      expect(preview.snapshotLikeCount, 0);
      expect(preview.warnings, isEmpty);
    });

    test('多道题命中时按题计数、告警只一条', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 3, mediaCount: 3),
        records: <QuestionPackRecord>[
          _stemSnapshotRecord(),
          _stemSnapshotRecord(placeholderCount: 1),
          _stemSnapshotRecord(placeholderCount: 4),
        ],
        plan: _plan(create: 3),
      );
      expect(preview.snapshotLikeCount, 2);
      expect(preview.warnings, <String>[
        '这个包是整卡快照包：2 道题的题干只有一张整题截图，'
            '公式以「［图N］」占位显示；详情页会按原题整图展示。',
      ]);
    });

    test('全角/半角/【】与全角数字都计入占位次数', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 1),
        records: <QuestionPackRecord>[
          const QuestionPackRecord(
            stem: '读图：［图1］[图 2]【图３】',
            media: <QuestionPackMedia>[
              QuestionPackMedia(packPath: 'media/stem.png'),
            ],
          ),
        ],
        plan: _plan(create: 1),
      );
      expect(preview.snapshotLikeCount, 1);
    });

    test('answer 与 solution 截图不算题干图', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 3),
        records: <QuestionPackRecord>[
          _stemSnapshotRecord(answerMedia: 2),
        ],
        plan: _plan(create: 1),
      );
      // _stemSnapshotRecord 默认 1 张题干图 + 2 张答案截图 = 3 张媒体。
      expect(preview.mediaCount, 3);
      expect(preview.snapshotLikeCount, 1);
    });

    test('warnings 顺序：清单层 → 快照提示 → 计划警告', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 3, mediaCount: 1),
        records: <QuestionPackRecord>[_stemSnapshotRecord()],
        plan: _plan(create: 1, warnings: <String>['甲', '乙']),
      );
      expect(preview.warnings, <String>[
        '包清单写着 3 道题，实际读到 1 道',
        snapshotWarning,
        '甲',
        '乙',
      ]);
    });

    test('计划警告与快照提示文案相同时只保留快照那一条', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 1),
        records: <QuestionPackRecord>[_stemSnapshotRecord()],
        plan: _plan(create: 1, warnings: <String>[snapshotWarning]),
      );
      expect(preview.warnings, <String>[snapshotWarning]);
    });

    test('summaryZh 快照行在包内容行之后、新增行之前', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 1),
        records: <QuestionPackRecord>[_stemSnapshotRecord()],
        plan: _plan(create: 1),
      );
      expect(preview.summaryZh, <String>[
        '包里共 1 道题、1 张配图（导出自 App 0.5.8+137，2026-10-21 04:40）',
        '整卡快照：1 道题（公式在整图里）',
        '导入后新增 1 道',
        '另有 1 条提示（见下）',
      ]);
    });

    test('不命中时 summaryZh 不出现快照行', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 1),
        records: <QuestionPackRecord>[
          _stemSnapshotRecord(placeholderCount: 1),
        ],
        plan: _plan(create: 1),
      );
      expect(preview.summaryZh, hasLength(2));
      expect(
        preview.summaryZh.any((String line) => line.contains('整卡快照')),
        isFalse,
      );
    });

    test('toJson 的 snapshot_like_count 紧跟 missing_tag_count', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 1, mediaCount: 1),
        records: <QuestionPackRecord>[_stemSnapshotRecord()],
        plan: _plan(create: 1, missingTagPaths: <String>['数学/函数']),
      );
      final Map<String, Object?> json = preview.toJson();
      final List<String> keys = json.keys.toList();
      expect(
        keys.indexOf('snapshot_like_count'),
        keys.indexOf('missing_tag_count') + 1,
      );
      expect(json['snapshot_like_count'], 1);
    });

    test('直接构造时 snapshotLikeCount 默认 0，也可显式传入', () {
      expect(_direct().snapshotLikeCount, 0);
      expect(_direct().toJson()['snapshot_like_count'], 0);

      final QuestionPackImportPreview explicit = _direct(snapshotLikeCount: 3);
      expect(explicit.snapshotLikeCount, 3);
      expect(explicit.toJson()['snapshot_like_count'], 3);
      expect(explicit == _direct(snapshotLikeCount: 3), isTrue);
      expect(explicit == _direct(), isFalse);
    });

    test('空包不产生快照告警', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 0, mediaCount: 0),
        records: const <QuestionPackRecord>[],
        plan: _plan(),
      );
      expect(preview.snapshotLikeCount, 0);
      expect(preview.warnings, isEmpty);
      expect(preview.summaryZh, hasLength(2));
    });

    test('命中时既有计数与清单对账不受影响', () {
      final QuestionPackImportPreview preview = _previewOf(
        manifest: _manifest(questionCount: 2, mediaCount: 2),
        records: <QuestionPackRecord>[
          _stemSnapshotRecord(),
          _record(mediaCount: 1),
        ],
        plan: _plan(create: 2),
      );
      expect(preview.recordCount, 2);
      expect(preview.mediaCount, 2);
      expect(preview.createCount, 2);
      expect(preview.skipCount, 0);
      expect(preview.manifestQuestionCount, 2);
      expect(preview.hasManifestMismatch, isFalse);
      expect(preview.snapshotLikeCount, 1);
    });
  });
}
