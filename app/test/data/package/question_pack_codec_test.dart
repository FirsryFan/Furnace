/// 题库包（.tqb）zip 容器层的测试：打包 / 解包 / 结构校验。
///
/// 验收重点不是「能 roundtrip」，而是**坏包必须报错**：缺 manifest、缺
/// questions.json、questions.json 不是 JSON、记录引用的媒体文件不存在、
/// 根本不是 zip——每一种都要抛 [QuestionPackException] 而不是返回半个包。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/package/question_pack_codec.dart';
import 'package:furnace/domain/services/package/question_pack_manifest.dart';
import 'package:furnace/domain/services/package/question_pack_record.dart';

void main() {
  final exportedAt = DateTime.utc(2026, 10, 21, 12, 30);

  QuestionPackManifest manifestOf({
    int questionCount = 1,
    int mediaCount = 0,
  }) {
    return QuestionPackManifest(
      exportedAt: exportedAt,
      appVersion: '0.5.8',
      questionCount: questionCount,
      mediaCount: mediaCount,
    );
  }

  QuestionPackRecord sampleRecord({
    String stem = r'已知函数 $f(x)=x^2$，求单调区间。',
    List<QuestionPackMedia> media = const <QuestionPackMedia>[],
  }) {
    return QuestionPackRecord(
      stem: stem,
      answer: 'B',
      solution: '求导后判断符号。',
      subjectKey: 'math',
      questionType: 'single_choice',
      sourceLevel: 'gaokao',
      sourceLabel: '2024 湖南师大附中月考',
      year: 2024,
      region: '湖南',
      difficulty: 6.5,
      difficultySource: 'manual',
      trapNote: '端点是否取到',
      serialNo: 42,
      sourceUrl: 'https://zujuan.xkw.com/10q35583902.html',
      zujuanQuestionId: '35583902',
      zujuanBankId: '10',
      options: const <QuestionPackOption>[
        QuestionPackOption(label: 'A', content: '递增', sortOrder: 0),
        QuestionPackOption(
          label: 'B',
          content: '先减后增',
          isCorrect: true,
          sortOrder: 1,
        ),
      ],
      tagPaths: const <String>['数学', '数学/函数'],
      media: media,
    );
  }

  Uint8List zipOf(Map<String, List<int>> entries) {
    final archive = Archive();
    entries.forEach((name, bytes) {
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded!);
  }

  Map<String, List<int>> manifestAndQuestions({
    required QuestionPackManifest manifest,
    required List<QuestionPackRecord> records,
  }) {
    return <String, List<int>>{
      kQuestionPackManifestEntry:
          utf8.encode(encodeQuestionPackManifest(manifest)),
      kQuestionPackQuestionsEntry:
          utf8.encode(encodeQuestionPackRecords(records)),
    };
  }

  test('encode → decode：清单、题目、媒体字节都能原样回来', () {
    final media = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
    final bytes = encodeQuestionPackArchive(
      manifest: manifestOf(mediaCount: 1),
      records: <QuestionPackRecord>[
        sampleRecord(media: const <QuestionPackMedia>[
          QuestionPackMedia(
            packPath: 'media/q1/0.png',
            fileName: 'IMG_2043.png',
            mime: 'image/png',
            role: 'stem',
          ),
        ]),
      ],
      mediaBytes: <String, Uint8List>{'media/q1/0.png': media},
    );

    final archive = decodeQuestionPackArchive(bytes);
    expect(archive.manifest, manifestOf(mediaCount: 1));
    expect(archive.records, hasLength(1));
    final record = archive.records.single;
    expect(record.stem, r'已知函数 $f(x)=x^2$，求单调区间。');
    expect(record.answer, 'B');
    expect(record.subjectKey, 'math');
    expect(record.questionType, 'single_choice');
    expect(record.sourceLevel, 'gaokao');
    expect(record.year, 2024);
    expect(record.region, '湖南');
    expect(record.difficulty, 6.5);
    expect(record.serialNo, 42);
    expect(record.sourceUrl, 'https://zujuan.xkw.com/10q35583902.html');
    expect(record.zujuanQuestionId, '35583902');
    expect(record.zujuanBankId, '10');
    expect(record.options, hasLength(2));
    expect(record.options[1].label, 'B');
    expect(record.options[1].isCorrect, isTrue);
    expect(record.tagPaths, <String>['数学', '数学/函数']);
    expect(record.media.single.packPath, 'media/q1/0.png');
    expect(record.media.single.fileName, 'IMG_2043.png');
    expect(record.media.single.role, 'stem');
    expect(archive.mediaBytes['media/q1/0.png'], equals(media));
  });

  test('encode：zip 里有 manifest.json / questions.json / media 三个条目', () {
    final bytes = encodeQuestionPackArchive(
      manifest: manifestOf(mediaCount: 1),
      records: <QuestionPackRecord>[sampleRecord()],
      mediaBytes: <String, Uint8List>{
        'media/q1/0.png': Uint8List.fromList(<int>[1, 2, 3]),
      },
    );
    final names = <String>[
      for (final file in ZipDecoder().decodeBytes(bytes).files) file.name,
    ];
    expect(names, contains(kQuestionPackManifestEntry));
    expect(names, contains(kQuestionPackQuestionsEntry));
    expect(names, contains('media/q1/0.png'));
  });

  test('readQuestionPackManifest：只读清单，不要求 questions.json', () {
    final bytes = zipOf(<String, List<int>>{
      kQuestionPackManifestEntry:
          utf8.encode(encodeQuestionPackManifest(manifestOf(questionCount: 3))),
    });
    final manifest = readQuestionPackManifest(bytes);
    expect(manifest.questionCount, 3);
    expect(manifest.appVersion, '0.5.8');
    expect(manifest.exportedAt, exportedAt);
    // 整个包解不开：缺 questions.json。
    expect(
      () => decodeQuestionPackArchive(bytes),
      throwsA(isA<QuestionPackException>()),
    );
  });

  test('缺 manifest.json：抛 QuestionPackException 并指出路径', () {
    final bytes = zipOf(<String, List<int>>{
      kQuestionPackQuestionsEntry: utf8.encode('[]'),
    });
    expect(
      () => decodeQuestionPackArchive(bytes),
      throwsA(isA<QuestionPackException>().having(
        (error) => error.path,
        'path',
        kQuestionPackManifestEntry,
      )),
    );
  });

  test('缺 questions.json：抛 QuestionPackException 并指出路径', () {
    final bytes = zipOf(<String, List<int>>{
      kQuestionPackManifestEntry:
          utf8.encode(encodeQuestionPackManifest(manifestOf())),
    });
    expect(
      () => decodeQuestionPackArchive(bytes),
      throwsA(isA<QuestionPackException>().having(
        (error) => error.path,
        'path',
        kQuestionPackQuestionsEntry,
      )),
    );
  });

  test('根本不是 zip：抛 QuestionPackException（消息说明 zip 解析失败）', () {
    expect(
      () => decodeQuestionPackArchive(Uint8List.fromList(<int>[1, 2, 3, 4])),
      throwsA(isA<QuestionPackException>().having(
        (error) => error.message,
        'message',
        contains('zip 解析失败'),
      )),
    );
  });

  test('manifest 不是题库包格式：抛 QuestionPackException', () {
    final bytes = zipOf(<String, List<int>>{
      kQuestionPackManifestEntry: utf8.encode(jsonEncode(<String, Object?>{
        'format': 'something-else',
        'version': 1,
        'exported_at': exportedAt.toIso8601String(),
        'question_count': 0,
        'media_count': 0,
      })),
      kQuestionPackQuestionsEntry: utf8.encode('[]'),
    });
    expect(
      () => decodeQuestionPackArchive(bytes),
      throwsA(isA<QuestionPackException>()),
    );
  });

  test('questions.json 不是合法 JSON：抛 QuestionPackException', () {
    final entries = manifestAndQuestions(
      manifest: manifestOf(),
      records: <QuestionPackRecord>[sampleRecord()],
    );
    entries[kQuestionPackQuestionsEntry] = utf8.encode('not json');
    expect(
      () => decodeQuestionPackArchive(zipOf(entries)),
      throwsA(isA<QuestionPackException>().having(
        (error) => error.message,
        'message',
        contains('不是合法 JSON'),
      )),
    );
  });

  test('记录引用的媒体文件不在包里：整包失败并指出 pack_path', () {
    const media = QuestionPackMedia(
      packPath: 'media/q1/0.png',
      fileName: 'page.png',
    );
    final entries = manifestAndQuestions(
      manifest: manifestOf(mediaCount: 1),
      records: <QuestionPackRecord>[
        sampleRecord(media: <QuestionPackMedia>[media])
      ],
    );
    expect(
      () => decodeQuestionPackArchive(zipOf(entries)),
      throwsA(isA<QuestionPackException>().having(
        (error) => error.path,
        'path',
        'media/q1/0.png',
      )),
    );
  });

  test('包里多余的媒体条目被忽略：不报错，也不进记录', () {
    final entries = manifestAndQuestions(
      manifest: manifestOf(),
      records: <QuestionPackRecord>[sampleRecord()],
    );
    entries['media/q1/0.png'] = <int>[9, 9, 9];
    entries['notes.txt'] = utf8.encode('hello');
    final archive = decodeQuestionPackArchive(zipOf(entries));
    expect(archive.records.single.media, isEmpty);
    expect(archive.mediaBytes.keys, contains('media/q1/0.png'));
    expect(archive.mediaBytes.keys, contains('notes.txt'));
  });

  test('空题库包：0 题 0 媒体也能打包与解包', () {
    final bytes = encodeQuestionPackArchive(
      manifest: manifestOf(questionCount: 0),
      records: const <QuestionPackRecord>[],
      mediaBytes: const <String, Uint8List>{},
    );
    final archive = decodeQuestionPackArchive(bytes);
    expect(archive.isEmpty, isTrue);
    expect(archive.records, isEmpty);
    expect(archive.mediaCount, 0);
  });

  test('媒体角色 answer / solution 原样往返', () {
    final bytes = encodeQuestionPackArchive(
      manifest: manifestOf(mediaCount: 2),
      records: <QuestionPackRecord>[
        sampleRecord(media: const <QuestionPackMedia>[
          QuestionPackMedia(packPath: 'media/q1/0.jpg', role: 'answer'),
          QuestionPackMedia(packPath: 'media/q1/1.jpg', role: 'solution'),
        ]),
      ],
      mediaBytes: <String, Uint8List>{
        'media/q1/0.jpg': Uint8List.fromList(<int>[1]),
        'media/q1/1.jpg': Uint8List.fromList(<int>[2]),
      },
    );
    final record = decodeQuestionPackArchive(bytes).records.single;
    expect(record.media.map((media) => media.role), <String>[
      'answer',
      'solution',
    ]);
  });

  test('超过 kQuestionPackMaxRecords 的包解码失败', () {
    final records = <QuestionPackRecord>[
      for (var i = 0; i < kQuestionPackMaxRecords + 1; i++)
        QuestionPackRecord(stem: '第 $i 题'),
    ];
    final entries = manifestAndQuestions(
      manifest: manifestOf(questionCount: records.length),
      records: records,
    );
    expect(
      () => decodeQuestionPackArchive(zipOf(entries)),
      throwsA(isA<QuestionPackException>()),
    );
  });
}
