import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/package/question_pack_manifest.dart';

QuestionPackManifest sampleManifest() => QuestionPackManifest(
      exportedAt: DateTime.utc(2026, 10, 21, 4, 40),
      appVersion: '0.5.8+136',
      questionCount: 42,
      mediaCount: 7,
      generatedBy: 'Furnace',
    );

QuestionPackException captureException(void Function() body) {
  try {
    body();
  } on QuestionPackException catch (error) {
    return error;
  }
  fail('应当抛 QuestionPackException，但没有抛');
}

void main() {
  group('QuestionPackManifest 往返与序列化', () {
    test('往返保持全部字段', () {
      final QuestionPackManifest decoded = decodeQuestionPackManifest(
        jsonDecode(encodeQuestionPackManifest(sampleManifest())),
      );
      expect(decoded, sampleManifest());
      expect(decoded.exportedAt, DateTime.utc(2026, 10, 21, 4, 40));
      expect(decoded.appVersion, '0.5.8+136');
      expect(decoded.questionCount, 42);
      expect(decoded.mediaCount, 7);
      expect(decoded.generatedBy, 'Furnace');
    });

    test('toJson 键名与字段顺序恒定', () {
      expect(
        sampleManifest().toJson().keys.toList(),
        <String>[
          'format',
          'version',
          'exported_at',
          'app_version',
          'question_count',
          'media_count',
          'generated_by',
        ],
      );
    });

    test('toJson 值符合格式约定', () {
      final Map<String, Object?> json = sampleManifest().toJson();
      expect(json['format'], 'furnace-question-bank');
      expect(json['version'], 1);
      expect(json['exported_at'], '2026-10-21T04:40:00.000Z');
      expect(json['app_version'], '0.5.8+136');
      expect(json['question_count'], 42);
      expect(json['media_count'], 7);
      expect(json['generated_by'], 'Furnace');
    });

    test('format 与 version getter 是固定值', () {
      final QuestionPackManifest manifest = sampleManifest();
      expect(manifest.format, kQuestionPackFormat);
      expect(manifest.version, kQuestionPackVersion);
      expect(kQuestionPackFormat, 'furnace-question-bank');
      expect(kQuestionPackVersion, 1);
    });

    test('未知字段被忽略', () {
      final Map<String, Object?> json = <String, Object?>{
        'format': 'furnace-question-bank',
        'version': 1,
        'exported_at': '2026-10-21T04:40:00.000Z',
        'question_count': 1,
        'media_count': 0,
        'future_field': <String, Object?>{'nested': true},
      };
      final QuestionPackManifest decoded = decodeQuestionPackManifest(json);
      expect(decoded.questionCount, 1);
      expect(decoded.mediaCount, 0);
    });

    test('== 与 hashCode 按字段比较', () {
      expect(sampleManifest(), sampleManifest());
      expect(sampleManifest().hashCode, sampleManifest().hashCode);
      final QuestionPackManifest other = QuestionPackManifest(
        exportedAt: DateTime.utc(2026, 10, 21, 4, 40),
        appVersion: '0.5.8+136',
        questionCount: 43,
        mediaCount: 7,
        generatedBy: 'Furnace',
      );
      expect(sampleManifest() == other, isFalse);
      expect(sampleManifest().hashCode == other.hashCode, isFalse);
    });

    test('toString 带上关键字段', () {
      final String text = sampleManifest().toString();
      expect(text, contains('QuestionPackManifest'));
      expect(text, contains('42'));
      expect(text, contains('Furnace'));
    });
  });

  group('QuestionPackManifest 校验', () {
    test('缺 format 报不是题库包', () {
      final QuestionPackException error = captureException(() {
        decodeQuestionPackManifest(<String, Object?>{
          'version': 1,
          'exported_at': '2026-10-21T04:40:00.000Z',
          'question_count': 1,
          'media_count': 0,
        });
      });
      expect(error.message, contains('不是题库包'));
      expect(error.path, 'manifest.json.format');
    });

    test('format 值不对报不是题库包', () {
      final QuestionPackException error = captureException(() {
        decodeQuestionPackManifest(<String, Object?>{
          'format': 'furnace-question-bank-v2',
          'version': 1,
          'exported_at': '2026-10-21T04:40:00.000Z',
          'question_count': 1,
          'media_count': 0,
        });
      });
      expect(error.message, contains('不是题库包'));
    });

    test('version 2 报不认识版本且带实际值', () {
      final QuestionPackException error = captureException(() {
        decodeQuestionPackManifest(<String, Object?>{
          'format': 'furnace-question-bank',
          'version': 2,
          'exported_at': '2026-10-21T04:40:00.000Z',
          'question_count': 1,
          'media_count': 0,
        });
      });
      expect(error.message, contains('不认识的题库包版本'));
      expect(error.message, contains('2'));
      expect(error.path, 'manifest.json.version');
    });

    test('version 缺失报不认识版本', () {
      final QuestionPackException error = captureException(() {
        decodeQuestionPackManifest(<String, Object?>{
          'format': 'furnace-question-bank',
          'exported_at': '2026-10-21T04:40:00.000Z',
          'question_count': 1,
          'media_count': 0,
        });
      });
      expect(error.message, contains('不认识的题库包版本'));
      expect(error.message, contains('null'));
    });

    test('version 是字符串 1 也报不认识版本', () {
      final QuestionPackException error = captureException(() {
        decodeQuestionPackManifest(<String, Object?>{
          'format': 'furnace-question-bank',
          'version': '1',
          'exported_at': '2026-10-21T04:40:00.000Z',
          'question_count': 1,
          'media_count': 0,
        });
      });
      expect(error.message, contains('不认识的题库包版本'));
      expect(error.message, contains('「1」'));
    });

    test('question_count 缺失报非负整数', () {
      final QuestionPackException error = captureException(() {
        decodeQuestionPackManifest(<String, Object?>{
          'format': 'furnace-question-bank',
          'version': 1,
          'exported_at': '2026-10-21T04:40:00.000Z',
          'media_count': 0,
        });
      });
      expect(error.message, contains('question_count'));
      expect(error.message, contains('非负整数'));
      expect(error.path, 'manifest.json.question_count');
    });

    test('question_count 负数报不能为负数', () {
      final QuestionPackException error = captureException(() {
        decodeQuestionPackManifest(<String, Object?>{
          'format': 'furnace-question-bank',
          'version': 1,
          'exported_at': '2026-10-21T04:40:00.000Z',
          'question_count': -3,
          'media_count': 0,
        });
      });
      expect(error.message, contains('不能为负数'));
      expect(error.message, contains('-3'));
    });

    test('question_count 是小数报非负整数', () {
      final QuestionPackException error = captureException(() {
        decodeQuestionPackManifest(<String, Object?>{
          'format': 'furnace-question-bank',
          'version': 1,
          'exported_at': '2026-10-21T04:40:00.000Z',
          'question_count': 1.5,
          'media_count': 0,
        });
      });
      expect(error.message, contains('非负整数'));
    });

    test('media_count 负数报不能为负数', () {
      final QuestionPackException error = captureException(() {
        decodeQuestionPackManifest(<String, Object?>{
          'format': 'furnace-question-bank',
          'version': 1,
          'exported_at': '2026-10-21T04:40:00.000Z',
          'question_count': 0,
          'media_count': -1,
        });
      });
      expect(error.message, contains('media_count'));
      expect(error.message, contains('不能为负数'));
      expect(error.path, 'manifest.json.media_count');
    });

    test('exported_at 不是 ISO 时间报错', () {
      final QuestionPackException error = captureException(() {
        decodeQuestionPackManifest(<String, Object?>{
          'format': 'furnace-question-bank',
          'version': 1,
          'exported_at': '昨天下午',
          'question_count': 0,
          'media_count': 0,
        });
      });
      expect(error.message, contains('ISO-8601'));
      expect(error.path, 'manifest.json.exported_at');
    });

    test('exported_at 缺失报错', () {
      final QuestionPackException error = captureException(() {
        decodeQuestionPackManifest(<String, Object?>{
          'format': 'furnace-question-bank',
          'version': 1,
          'question_count': 0,
          'media_count': 0,
        });
      });
      expect(error.message, contains('ISO-8601'));
    });

    test('app_version 不是字符串报错', () {
      final QuestionPackException error = captureException(() {
        decodeQuestionPackManifest(<String, Object?>{
          'format': 'furnace-question-bank',
          'version': 1,
          'exported_at': '2026-10-21T04:40:00.000Z',
          'question_count': 0,
          'media_count': 0,
          'app_version': 136,
        });
      });
      expect(error.message, contains('字符串'));
      expect(error.path, 'manifest.json.app_version');
    });
  });

  group('decodeQuestionPackManifest 入参与容错', () {
    test('入参不是 Map 抛异常', () {
      for (final Object? input in <Object?>[null, <Object?>[], 'text']) {
        final QuestionPackException error = captureException(() {
          decodeQuestionPackManifest(input);
        });
        expect(error.message, contains('JSON 对象'));
      }
    });

    test('传 JSON 文本没有先 jsonDecode 会抛异常', () {
      final QuestionPackException error = captureException(() {
        decodeQuestionPackManifest(
          encodeQuestionPackManifest(sampleManifest()),
        );
      });
      expect(error.message, contains('JSON 对象'));
    });

    test('自定义 path 出现在错误路径里', () {
      final QuestionPackException error = captureException(() {
        decodeQuestionPackManifest(
          <String, Object?>{'format': 'furnace-question-bank'},
          path: 'custom/pack/manifest.json',
        );
      });
      expect(error.path, 'custom/pack/manifest.json.version');
    });

    test('app_version 与 generated_by 缺省为空串', () {
      final QuestionPackManifest decoded = decodeQuestionPackManifest(
        <String, Object?>{
          'format': 'furnace-question-bank',
          'version': 1,
          'exported_at': '2026-10-21T04:40:00.000Z',
          'question_count': 0,
          'media_count': 0,
        },
      );
      expect(decoded.appVersion, '');
      expect(decoded.generatedBy, '');
    });

    test('fromJson 直接调用也做同样校验', () {
      final QuestionPackException error = captureException(() {
        QuestionPackManifest.fromJson(<String, Object?>{'format': 'x'});
      });
      expect(error.message, contains('不是题库包'));
      expect(error.path, 'manifest.json.format');
    });

    test('空对象报不是题库包', () {
      final QuestionPackException error = captureException(() {
        decodeQuestionPackManifest(const <String, Object?>{});
      });
      expect(error.message, contains('不是题库包'));
    });

    test('QuestionPackException.toString 带路径', () {
      const QuestionPackException withPath = QuestionPackException(
        '坏了',
        path: 'manifest.version',
      );
      expect(withPath.toString(), contains('坏了'));
      expect(withPath.toString(), contains('manifest.version'));
      const QuestionPackException withoutPath = QuestionPackException('坏了');
      expect(withoutPath.toString(), 'QuestionPackException: 坏了');
    });
  });
}
