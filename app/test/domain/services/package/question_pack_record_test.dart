import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/package/question_pack_manifest.dart';
import 'package:furnace/domain/services/package/question_pack_record.dart';

QuestionPackException captureException(void Function() body) {
  try {
    body();
  } on QuestionPackException catch (error) {
    return error;
  }
  fail('应当抛 QuestionPackException，但没有抛');
}

QuestionPackRecord fullRecord() => const QuestionPackRecord(
      stem: r'求 $x$ 的值：已知 a，b。第二行 🚀',
      answer: 'B',
      solution: '解：由题意\nx = 1',
      subjectKey: 'math',
      questionType: 'choice',
      sourceLevel: 'exam',
      sourceLabel: '2024 湖南师大附中月考',
      year: 2024,
      region: '湖南',
      difficulty: 3.5,
      difficultySource: 'ai',
      trapNote: '别忘定义域',
      origin: 'ai_scan',
      state: 'processed',
      serialNo: 12,
      sourceUrl: 'https://zujuan.xkw.com/10q123456.html',
      zujuanQuestionId: '123456',
      zujuanBankId: '10',
      options: <QuestionPackOption>[
        QuestionPackOption(label: 'A', content: '甲'),
        QuestionPackOption(
          label: 'B',
          content: '乙',
          isCorrect: true,
          sortOrder: 1,
        ),
        QuestionPackOption(label: 'C', content: '丙', sortOrder: 2),
      ],
      tagPaths: <String>['数学', '函数', '单调性'],
      media: <QuestionPackMedia>[
        QuestionPackMedia(
          packPath: 'media/q-0012-stem-0.png',
          fileName: 'IMG_001.png',
          mime: 'image/png',
        ),
        QuestionPackMedia(
          packPath: 'media/q-0012-answer-0.png',
          role: 'answer',
          sortOrder: 1,
        ),
      ],
    );

void main() {
  group('QuestionPackRecord 序列化', () {
    test('完整记录往返保持全部字段', () {
      final List<QuestionPackRecord> decoded = decodeQuestionPackRecords(
        jsonDecode(
            encodeQuestionPackRecords(<QuestionPackRecord>[fullRecord()])),
      );
      expect(decoded, hasLength(1));
      expect(decoded.single, fullRecord());
      expect(decoded.single.stem, r'求 $x$ 的值：已知 a，b。第二行 🚀');
      expect(decoded.single.solution, '解：由题意\nx = 1');
      expect(decoded.single.difficulty, 3.5);
      expect(decoded.single.tagPaths, <String>['数学', '函数', '单调性']);
    });

    test('toJson 键名与字段顺序恒定', () {
      expect(
        fullRecord().toJson().keys.toList(),
        <String>[
          'stem',
          'answer',
          'solution',
          'subject_key',
          'question_type',
          'source_level',
          'source_label',
          'year',
          'region',
          'difficulty',
          'difficulty_source',
          'trap_note',
          'origin',
          'state',
          'serial_no',
          'source_url',
          'zujuan_question_id',
          'zujuan_bank_id',
          'options',
          'tag_paths',
          'media',
        ],
      );
    });

    test('最小记录只写必要字段与默认值', () {
      const QuestionPackRecord record = QuestionPackRecord(stem: '只给题干');
      expect(
        record.toJson().keys.toList(),
        <String>[
          'stem',
          'subject_key',
          'question_type',
          'source_level',
          'source_label',
          'origin',
          'state',
          'options',
          'tag_paths',
          'media',
        ],
      );
      final Map<String, Object?> json = record.toJson();
      expect(json['subject_key'], '');
      expect(json['question_type'], 'solution');
      expect(json['source_level'], 'unknown');
      expect(json['source_label'], '');
      expect(json['origin'], 'manual');
      expect(json['state'], 'structured');
      expect(json['options'], isEmpty);
      expect(json['tag_paths'], isEmpty);
      expect(json['media'], isEmpty);
    });

    test('值为 null 的可选字段不写进 toJson', () {
      final Map<String, Object?> json =
          const QuestionPackRecord(stem: '只给题干').toJson();
      for (final String key in <String>[
        'answer',
        'solution',
        'year',
        'region',
        'difficulty',
        'difficulty_source',
        'trap_note',
        'serial_no',
        'source_url',
        'zujuan_question_id',
        'zujuan_bank_id',
      ]) {
        expect(json.containsKey(key), isFalse, reason: key);
      }
    });

    test('解码时忽略未知字段', () {
      final QuestionPackRecord record = QuestionPackRecord.fromJson(
        <String, Object?>{
          'stem': '题干',
          'serial_no': 3,
          'future_field': <String, Object?>{'nested': true},
        },
      );
      expect(record.stem, '题干');
      expect(record.serialNo, 3);
    });

    test('解码缺失的可选字段用默认值', () {
      final QuestionPackRecord record = QuestionPackRecord.fromJson(
        <String, Object?>{'stem': '只给题干'},
      );
      expect(record, const QuestionPackRecord(stem: '只给题干'));
      expect(record.answer, isNull);
      expect(record.solution, isNull);
      expect(record.year, isNull);
      expect(record.serialNo, isNull);
      expect(record.options, isEmpty);
      expect(record.tagPaths, isEmpty);
      expect(record.media, isEmpty);
    });

    test('选项顺序按给定顺序保留', () {
      final QuestionPackRecord record = QuestionPackRecord.fromJson(
        <String, Object?>{
          'stem': '选项题',
          'options': <Object?>[
            <String, Object?>{'label': 'C', 'content': '丙'},
            <String, Object?>{'label': 'A', 'content': '甲'},
            <String, Object?>{
              'label': 'B',
              'content': '乙',
              'is_correct': true,
              'sort_order': 2,
            },
          ],
        },
      );
      expect(
        record.options
            .map((QuestionPackOption option) => option.label)
            .toList(),
        <String>['C', 'A', 'B'],
      );
      expect(record.options[2].isCorrect, isTrue);
      expect(record.options[2].sortOrder, 2);
    });

    test('编码结果可被 jsonDecode 且是数组', () {
      final Object? decoded = jsonDecode(
          encodeQuestionPackRecords(<QuestionPackRecord>[fullRecord()]));
      expect(decoded, isA<List<Object?>>());
      expect(decoded as List<Object?>, hasLength(1));
    });
  });

  group('QuestionPackRecord 校验', () {
    test('题干为空白报题干为空', () {
      final QuestionPackException error = captureException(() {
        QuestionPackRecord.fromJson(<String, Object?>{'stem': '   '});
      });
      expect(error.message, contains('题干为空'));
      expect(error.path, 'questions[].stem');
    });

    test('题干缺失报题干为空', () {
      final QuestionPackException error = captureException(() {
        QuestionPackRecord.fromJson(const <String, Object?>{});
      });
      expect(error.message, contains('题干为空'));
    });

    test('year 越界报错', () {
      for (final int year in <int>[1899, 2101]) {
        final QuestionPackException error = captureException(() {
          QuestionPackRecord.fromJson(
            <String, Object?>{'stem': '题干', 'year': year},
          );
        });
        expect(error.message, contains('1900..2100'));
        expect(error.path, 'questions[].year');
      }
    });

    test('year 非整数报错', () {
      final QuestionPackException error = captureException(() {
        QuestionPackRecord.fromJson(
          <String, Object?>{'stem': '题干', 'year': '2024'},
        );
      });
      expect(error.message, contains('1900..2100'));
    });

    test('year 边界值 1900 与 2100 允许', () {
      expect(
        QuestionPackRecord.fromJson(
          <String, Object?>{'stem': '题干', 'year': 1900},
        ).year,
        1900,
      );
      expect(
        QuestionPackRecord.fromJson(
          <String, Object?>{'stem': '题干', 'year': 2100},
        ).year,
        2100,
      );
    });

    test('serial_no 为 0 报错', () {
      final QuestionPackException error = captureException(() {
        QuestionPackRecord.fromJson(
          <String, Object?>{'stem': '题干', 'serial_no': 0},
        );
      });
      expect(error.message, contains('>= 1'));
      expect(error.path, 'questions[].serial_no');
    });

    test('serial_no 负数与非整数报错', () {
      for (final Object? serial in <Object?>[-3, '12', 1.5]) {
        final QuestionPackException error = captureException(() {
          QuestionPackRecord.fromJson(
            <String, Object?>{'stem': '题干', 'serial_no': serial},
          );
        });
        expect(error.message, contains('serial_no'));
      }
    });

    test('difficulty 接受整数并转成 double', () {
      final QuestionPackRecord record = QuestionPackRecord.fromJson(
        <String, Object?>{'stem': '题干', 'difficulty': 4},
      );
      expect(record.difficulty, 4.0);
    });

    test('difficulty 非数字报错', () {
      final QuestionPackException error = captureException(() {
        QuestionPackRecord.fromJson(
          <String, Object?>{'stem': '题干', 'difficulty': '3.5'},
        );
      });
      expect(error.message, contains('difficulty'));
    });

    test('difficulty 非有限数报错', () {
      for (final double value in <double>[double.nan, double.infinity]) {
        final QuestionPackException error = captureException(() {
          QuestionPackRecord.fromJson(
            <String, Object?>{'stem': '题干', 'difficulty': value},
          );
        });
        expect(error.message, contains('有限数字'));
      }
    });

    test('错误 path 指认出错的题号', () {
      final QuestionPackException error = captureException(() {
        QuestionPackRecord.fromJson(
          <String, Object?>{'stem': ''},
          path: 'questions[7]',
        );
      });
      expect(error.path, 'questions[7].stem');
    });

    test('选项 label 重复报错并指到具体选项', () {
      final QuestionPackException error = captureException(() {
        QuestionPackRecord.fromJson(
          <String, Object?>{
            'stem': '题干',
            'options': <Object?>[
              <String, Object?>{'label': 'A', 'content': '甲'},
              <String, Object?>{'label': 'a', 'content': '乙'},
            ],
          },
          path: 'questions[0]',
        );
      });
      expect(error.message, contains('选项 label 重复'));
      expect(error.path, 'questions[0].options[1].label');
    });
  });

  group('QuestionPackOption', () {
    test('label 小写解码后统一成大写', () {
      final QuestionPackOption option = QuestionPackOption.fromJson(
        <String, Object?>{'label': ' b ', 'content': '乙'},
      );
      expect(option.label, 'B');
      expect(option.content, '乙');
    });

    test('label AB 被拒绝', () {
      final QuestionPackException error = captureException(() {
        QuestionPackOption.fromJson(
          <String, Object?>{'label': 'AB', 'content': '甲'},
        );
      });
      expect(error.message, contains('单个字母'));
      expect(error.path, 'options[].label');
    });

    test('label 非字母或缺失被拒绝', () {
      for (final Object? label in <Object?>[null, 1, '1', '#']) {
        final QuestionPackException error = captureException(() {
          QuestionPackOption.fromJson(
            <String, Object?>{'label': label, 'content': '甲'},
          );
        });
        expect(error.message, contains('单个字母'), reason: 'label=$label');
      }
    });

    test('content 空白被拒绝', () {
      final QuestionPackException error = captureException(() {
        QuestionPackOption.fromJson(
          <String, Object?>{'label': 'A', 'content': '  '},
        );
      });
      expect(error.message, contains('选项内容不能为空'));
      expect(error.path, 'options[].content');
    });

    test('sort_order 负数被拒绝', () {
      final QuestionPackException error = captureException(() {
        QuestionPackOption.fromJson(
          <String, Object?>{'label': 'A', 'content': '甲', 'sort_order': -1},
        );
      });
      expect(error.message, contains('sort_order'));
      expect(error.message, contains('不能为负数'));
    });

    test('toJson 键序与往返', () {
      const QuestionPackOption option = QuestionPackOption(
        label: 'B',
        content: '乙',
        isCorrect: true,
        sortOrder: 2,
      );
      expect(
        option.toJson().keys.toList(),
        <String>['label', 'content', 'is_correct', 'sort_order'],
      );
      expect(
        QuestionPackOption.fromJson(option.toJson()),
        option,
      );
    });
  });

  group('QuestionPackMedia', () {
    test('pack_path 合法路径保留并 trim', () {
      final QuestionPackMedia media = QuestionPackMedia.fromJson(
        <String, Object?>{'pack_path': ' media/q-0001-stem-0.png '},
      );
      expect(media.packPath, 'media/q-0001-stem-0.png');
      expect(media.role, 'stem');
      expect(media.sortOrder, 0);
      expect(media.fileName, isNull);
      expect(media.mime, isNull);
    });

    test('pack_path 为 .. 路径段被拒绝', () {
      for (final String bad in <String>[
        '../x',
        'media/../x',
        './x',
      ]) {
        final QuestionPackException error = captureException(() {
          QuestionPackMedia.fromJson(<String, Object?>{'pack_path': bad});
        });
        expect(error.message, contains('..'), reason: bad);
      }
    });

    test('pack_path 以 / 开头被拒绝', () {
      final QuestionPackException error = captureException(() {
        QuestionPackMedia.fromJson(
          <String, Object?>{'pack_path': '/abs/a.png'},
        );
      });
      expect(error.message, contains('不能以 / 开头'));
      expect(error.path, 'media[].pack_path');
    });

    test('pack_path 含空路径段被拒绝', () {
      final QuestionPackException error = captureException(() {
        QuestionPackMedia.fromJson(<String, Object?>{'pack_path': 'a//b'});
      });
      expect(error.message, contains('空路径段'));
    });

    test('pack_path 含反斜杠被拒绝', () {
      final QuestionPackException error = captureException(() {
        QuestionPackMedia.fromJson(<String, Object?>{'pack_path': r'a\b'});
      });
      expect(error.message, contains('反斜杠'));
    });

    test('pack_path 为空被拒绝', () {
      for (final Object? bad in <Object?>[null, '', '   ', 1]) {
        final QuestionPackException error = captureException(() {
          QuestionPackMedia.fromJson(<String, Object?>{'pack_path': bad});
        });
        expect(error.message, contains('pack_path'), reason: 'packPath=$bad');
      }
    });

    test('role 非法被拒绝', () {
      final QuestionPackException error = captureException(() {
        QuestionPackMedia.fromJson(
          <String, Object?>{'pack_path': 'media/a.png', 'role': 'foo'},
        );
      });
      expect(error.message, contains('role 必须是'));
    });

    test('sort_order 负数被拒绝', () {
      final QuestionPackException error = captureException(() {
        QuestionPackMedia.fromJson(
          <String, Object?>{'pack_path': 'media/a.png', 'sort_order': -2},
        );
      });
      expect(error.message, contains('sort_order'));
      expect(error.message, contains('不能为负数'));
    });

    test('file_name 含路径分隔符被拒绝', () {
      for (final String bad in <String>['a/b.png', r'a\b.png']) {
        final QuestionPackException error = captureException(() {
          QuestionPackMedia.fromJson(
            <String, Object?>{'pack_path': 'media/a.png', 'file_name': bad},
          );
        });
        expect(error.message, contains('路径分隔符'), reason: bad);
      }
    });

    test('file_name 与 mime 的空串被拒绝', () {
      for (final Map<String, Object?> json in <Map<String, Object?>>[
        <String, Object?>{'pack_path': 'media/a.png', 'file_name': '   '},
        <String, Object?>{'pack_path': 'media/a.png', 'mime': '  '},
      ]) {
        final QuestionPackException error = captureException(() {
          QuestionPackMedia.fromJson(json);
        });
        expect(error.message, contains('不能为空字符串'));
      }
    });

    test('toJson 省略空的可选字段且键序恒定', () {
      const QuestionPackMedia media = QuestionPackMedia(
        packPath: 'media/a.png',
        fileName: 'IMG_1.png',
        mime: 'image/png',
        role: 'answer',
        sortOrder: 3,
      );
      expect(
        media.toJson().keys.toList(),
        <String>['pack_path', 'file_name', 'mime', 'role', 'sort_order'],
      );
      final Map<String, Object?> bare =
          const QuestionPackMedia(packPath: 'media/a.png').toJson();
      expect(bare.containsKey('file_name'), isFalse);
      expect(bare.containsKey('mime'), isFalse);
      expect(QuestionPackMedia.fromJson(media.toJson()), media);
    });
  });

  group('标签路径与列表字段', () {
    test('tag_paths 每项 trim 后保存', () {
      final QuestionPackRecord record = QuestionPackRecord.fromJson(
        <String, Object?>{
          'stem': '题干',
          'tag_paths': <Object?>[' 数学 ', '函数'],
        },
      );
      expect(record.tagPaths, <String>['数学', '函数']);
    });

    test('tag_paths trim 后重复被拒绝', () {
      final QuestionPackException error = captureException(() {
        QuestionPackRecord.fromJson(
          <String, Object?>{
            'stem': '题干',
            'tag_paths': <Object?>['数学', ' 数学 '],
          },
          path: 'questions[0]',
        );
      });
      expect(error.message, contains('标签路径重复'));
      expect(error.path, 'questions[0].tag_paths[1]');
    });

    test('tag_paths 空白项被拒绝', () {
      final QuestionPackException error = captureException(() {
        QuestionPackRecord.fromJson(
          <String, Object?>{
            'stem': '题干',
            'tag_paths': <Object?>['数学', '   '],
          },
        );
      });
      expect(error.message, contains('标签路径不能为空'));
    });

    test('tag_paths 不是数组被拒绝', () {
      final QuestionPackException error = captureException(() {
        QuestionPackRecord.fromJson(
          <String, Object?>{'stem': '题干', 'tag_paths': '数学'},
        );
      });
      expect(error.message, contains('tag_paths 必须是数组'));
    });

    test('options 与 media 不是数组被拒绝', () {
      for (final String key in <String>['options', 'media']) {
        final QuestionPackException error = captureException(() {
          QuestionPackRecord.fromJson(
            <String, Object?>{'stem': '题干', key: '不是数组'},
          );
        });
        expect(error.message, contains('必须是数组'), reason: key);
      }
    });
  });

  group('decodeQuestionPackRecords', () {
    test('空数组允许并返回空列表', () {
      expect(decodeQuestionPackRecords(const <Object?>[]), isEmpty);
      expect(decodeQuestionPackRecords(jsonDecode('[]')), isEmpty);
    });

    test('入参不是数组抛异常', () {
      for (final Object? input in <Object?>[
        null,
        'questions.json',
        <String, Object?>{'stem': '题干'},
      ]) {
        final QuestionPackException error = captureException(() {
          decodeQuestionPackRecords(input);
        });
        expect(error.message, contains('JSON 数组'));
      }
    });

    test('传 JSON 文本没有先 jsonDecode 会抛异常', () {
      final QuestionPackException error = captureException(() {
        decodeQuestionPackRecords(
          encodeQuestionPackRecords(<QuestionPackRecord>[fullRecord()]),
        );
      });
      expect(error.message, contains('JSON 数组'));
    });

    test('非对象项报第几条', () {
      final QuestionPackException error = captureException(() {
        decodeQuestionPackRecords(<Object?>[null]);
      });
      expect(error.message, contains('第 1 条'));
      expect(error.path, 'questions[0]');
    });

    test('一条坏记录让整包失败', () {
      final QuestionPackException error = captureException(() {
        decodeQuestionPackRecords(<Object?>[
          <String, Object?>{'stem': '好题'},
          <String, Object?>{'stem': '   '},
        ]);
      });
      expect(error.message, contains('题干为空'));
      expect(error.path, 'questions[1].stem');
    });

    test('超过 5000 条报题目太多', () {
      final List<Map<String, Object?>> tooMany =
          List<Map<String, Object?>>.generate(
        kQuestionPackMaxRecords + 1,
        (int index) => <String, Object?>{'stem': '题 $index'},
      );
      final QuestionPackException error = captureException(() {
        decodeQuestionPackRecords(tooMany);
      });
      expect(error.message, contains('题目太多'));
      expect(error.message, contains('${kQuestionPackMaxRecords + 1}'));
    });

    test('恰好 5000 条允许', () {
      final List<Map<String, Object?>> many =
          List<Map<String, Object?>>.generate(
        kQuestionPackMaxRecords,
        (int index) => <String, Object?>{'stem': '题 $index'},
      );
      expect(
        decodeQuestionPackRecords(many),
        hasLength(kQuestionPackMaxRecords),
      );
    });

    test('空列表编码为 []', () {
      expect(encodeQuestionPackRecords(const <QuestionPackRecord>[]), '[]');
    });

    test('自定义 path 用于顶层错误', () {
      final QuestionPackException error = captureException(() {
        decodeQuestionPackRecords('x', path: 'pack/questions.json');
      });
      expect(error.path, 'pack/questions.json');
    });
  });

  group('相等、hashCode 与 toString', () {
    test('相同记录相等且 hashCode 相同', () {
      expect(fullRecord(), fullRecord());
      expect(fullRecord().hashCode, fullRecord().hashCode);
    });

    test('字段不同则记录不相等', () {
      const QuestionPackRecord base = QuestionPackRecord(stem: '题干');
      const QuestionPackRecord otherStem = QuestionPackRecord(stem: '另一道题');
      expect(base == otherStem, isFalse);
      const QuestionPackRecord withOption = QuestionPackRecord(
        stem: '题干',
        options: <QuestionPackOption>[
          QuestionPackOption(label: 'A', content: '甲'),
        ],
      );
      expect(base == withOption, isFalse);
    });

    test('toJson 键序与解码后再编码一致', () {
      final Map<String, Object?> first = fullRecord().toJson();
      final QuestionPackRecord decoded = QuestionPackRecord.fromJson(first);
      expect(decoded.toJson().keys.toList(), first.keys.toList());
    });

    test('toString 带上题干与计数', () {
      final String text = fullRecord().toString();
      expect(text, contains('QuestionPackRecord'));
      expect(text, contains('options: 3'));
      expect(text, contains('tagPaths: 3'));
      expect(text, contains('media: 2'));
    });
  });

  group('text_format（handoff 管线 v1 §7 M1）', () {
    test('缺省是 plain，显式 plain / markdown 都能解', () {
      expect(const QuestionPackRecord(stem: '题干').textFormat, 'plain');
      expect(
        QuestionPackRecord.fromJson(<String, Object?>{'stem': '题干'}).textFormat,
        'plain',
      );
      final QuestionPackRecord markdown = QuestionPackRecord.fromJson(
        <String, Object?>{'stem': '题干', 'text_format': 'markdown'},
      );
      expect(markdown.textFormat, 'markdown');
      expect(
        QuestionPackRecord.fromJson(
          <String, Object?>{'stem': '题干', 'text_format': 'plain'},
        ).textFormat,
        'plain',
      );
    });

    test('非法 text_format 整包失败，路径指到字段', () {
      final QuestionPackException error = captureException(
        () => QuestionPackRecord.fromJson(
          <String, Object?>{'stem': '题干', 'text_format': 'latex'},
          path: 'questions[2]',
        ),
      );
      expect(error.path, 'questions[2].text_format');
      expect(error.message, contains('plain'));
    });

    test('toJson：plain 不落键（历史包逐字节不变），markdown 落键', () {
      expect(
        const QuestionPackRecord(stem: '题干')
            .toJson()
            .containsKey('text_format'),
        isFalse,
      );
      expect(
        const QuestionPackRecord(stem: '题干', textFormat: 'markdown')
            .toJson()['text_format'],
        'markdown',
      );
    });
  });

  group('extension_of / capability（handoff 管线 v1 §7 M2）', () {
    test('extension_of 去空白后保留；空串 / 非字符串失败', () {
      final QuestionPackRecord record = QuestionPackRecord.fromJson(
        <String, Object?>{'stem': '题干', 'extension_of': ' 123456 '},
      );
      expect(record.extensionOf, '123456');
      expect(record.toJson()['extension_of'], '123456');
      expect(
        const QuestionPackRecord(stem: '题干')
            .toJson()
            .containsKey('extension_of'),
        isFalse,
      );
      final QuestionPackException blank = captureException(
        () => QuestionPackRecord.fromJson(
          <String, Object?>{'stem': '题干', 'extension_of': '   '},
          path: 'questions[0]',
        ),
      );
      expect(blank.path, 'questions[0].extension_of');
      final QuestionPackException badType = captureException(
        () => QuestionPackRecord.fromJson(
          <String, Object?>{'stem': '题干', 'extension_of': 123456},
          path: 'questions[0]',
        ),
      );
      expect(badType.path, 'questions[0].extension_of');
    });

    test('capability 只收 A1…A10，去重并按数字升序', () {
      final QuestionPackRecord record = QuestionPackRecord.fromJson(
        <String, Object?>{
          'stem': '题干',
          'capability': <Object?>['A10', 'A2', 'A2', 'A3'],
        },
      );
      expect(record.capability, <String>['A2', 'A3', 'A10'],
          reason: 'A10 不能排到 A2 前面（按数字排，不按字典序）');
      expect(record.toJson()['capability'], <String>['A2', 'A3', 'A10']);
      expect(
        const QuestionPackRecord(stem: '题干').toJson().containsKey('capability'),
        isFalse,
        reason: '空数组不落键',
      );
    });

    test('非法 capability 项 / 非数组整包失败', () {
      for (final Object? bad in <Object?>['A0', 'A11', 'a1', 'B2', '', 3]) {
        final QuestionPackException error = captureException(
          () => QuestionPackRecord.fromJson(
            <String, Object?>{
              'stem': '题干',
              'capability': <Object?>[bad],
            },
            path: 'questions[1]',
          ),
        );
        expect(error.path, 'questions[1].capability[0]', reason: '坏项是 $bad');
      }
      final QuestionPackException notList = captureException(
        () => QuestionPackRecord.fromJson(
          <String, Object?>{'stem': '题干', 'capability': 'A3'},
          path: 'questions[1]',
        ),
      );
      expect(notList.path, 'questions[1].capability');
    });

    test('三个新字段参与相等与 hashCode', () {
      const QuestionPackRecord base = QuestionPackRecord(stem: '题干');
      expect(
        base == const QuestionPackRecord(stem: '题干', textFormat: 'markdown'),
        isFalse,
      );
      expect(
        base == const QuestionPackRecord(stem: '题干', extensionOf: '123456'),
        isFalse,
      );
      expect(
        base ==
            const QuestionPackRecord(stem: '题干', capability: <String>['A1']),
        isFalse,
      );
      expect(
        const QuestionPackRecord(
          stem: '题干',
          textFormat: 'markdown',
          extensionOf: '123456',
          capability: <String>['A1', 'A10'],
        ).hashCode,
        const QuestionPackRecord(
          stem: '题干',
          textFormat: 'markdown',
          extensionOf: '123456',
          capability: <String>['A1', 'A10'],
        ).hashCode,
      );
    });
  });
}
