import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/zujuan/zujuan_source_input.dart';

/// 断言能解析，并返回非空结果。
ZujuanSourceInput parseSingle(String input) {
  final result = parseZujuanSourceInput(input);
  expect(result, isNotNull, reason: '应能解析：${jsonEncode(input)}');
  return result!;
}

/// 断言认不出（null）。
void expectNull(String input) {
  expect(
    parseZujuanSourceInput(input),
    isNull,
    reason: '应认不出：${jsonEncode(input)}',
  );
}

void main() {
  group('完整题链 URL', () {
    test('组卷网题目详情页链接解析出链接与两个 id', () {
      final result = parseSingle('https://zujuan.xkw.com/10q35583902.html');
      expect(result.sourceUrl, 'https://zujuan.xkw.com/10q35583902.html');
      expect(result.zujuanBankId, '10');
      expect(result.zujuanQuestionId, '35583902');
      expect(result.isEmpty, isFalse);
    });

    test('query 保留、fragment 去掉', () {
      final withQuery = parseSingle(
        'https://zujuan.xkw.com/10q35583902.html?x=1',
      );
      expect(
        withQuery.sourceUrl,
        'https://zujuan.xkw.com/10q35583902.html?x=1',
      );
      expect(withQuery.zujuanBankId, '10');
      expect(withQuery.zujuanQuestionId, '35583902');

      final withFragment = parseSingle(
        'https://zujuan.xkw.com/10q35583902.html#frag',
      );
      expect(
        withFragment.sourceUrl,
        'https://zujuan.xkw.com/10q35583902.html',
      );
      expect(withFragment.zujuanQuestionId, '35583902');
    });

    test('大写 scheme 与 host 规范化、path 大小写保留', () {
      final result = parseSingle(
        'HTTPS://ZUJUAN.XKW.COM/10Q35583902.HTML',
      );
      expect(result.sourceUrl, 'https://zujuan.xkw.com/10Q35583902.HTML');
      expect(result.zujuanBankId, '10');
      expect(result.zujuanQuestionId, '35583902');
    });

    test('默认端口去掉、非默认端口保留', () {
      expect(
        parseSingle('http://zujuan.xkw.com:80/10q35583902.html').sourceUrl,
        'http://zujuan.xkw.com/10q35583902.html',
      );
      expect(
        parseSingle('https://zujuan.xkw.com:443/10q35583902.html').sourceUrl,
        'https://zujuan.xkw.com/10q35583902.html',
      );
      expect(
        parseSingle('https://zujuan.xkw.com:8443/10q35583902.html').sourceUrl,
        'https://zujuan.xkw.com:8443/10q35583902.html',
      );
    });

    test('组卷网子域也填两个 id', () {
      final www = parseSingle(
        'https://www.zujuan.xkw.com/10q35583902.html',
      );
      expect(www.zujuanBankId, '10');
      expect(www.zujuanQuestionId, '35583902');

      final deep = parseSingle(
        'https://a.b.zujuan.xkw.com/10q5.html',
      );
      expect(deep.zujuanBankId, '10');
      expect(deep.zujuanQuestionId, '5');
    });

    test('只有题号没有 bank 时只填题号、链接保留', () {
      final result = parseSingle(
        'https://zujuan.xkw.com/q35583902.html',
      );
      expect(result.sourceUrl, 'https://zujuan.xkw.com/q35583902.html');
      expect(result.zujuanBankId, isNull);
      expect(result.zujuanQuestionId, '35583902');
      expect(result.isEmpty, isFalse);
    });

    test('非数字的假 bank 不算题号（前导边界）', () {
      final result = parseSingle('https://zujuan.xkw.com/abcq123.html');
      expect(result.sourceUrl, 'https://zujuan.xkw.com/abcq123.html');
      expect(result.zujuanBankId, isNull);
      expect(result.zujuanQuestionId, isNull);
    });

    test('题号超过 12 位不认、bank 超过 6 位不认，只留链接', () {
      final longQid = parseSingle(
        'https://zujuan.xkw.com/10q1234567890123.html',
      );
      expect(longQid.zujuanQuestionId, isNull);
      expect(longQid.zujuanBankId, isNull);
      expect(longQid.sourceUrl, isNotNull);

      final longBank = parseSingle(
        'https://zujuan.xkw.com/1234567q1.html',
      );
      expect(longBank.zujuanQuestionId, isNull);
      expect(longBank.zujuanBankId, isNull);
    });

    test('6 位 bank 与 12 位题号都认', () {
      final result = parseSingle(
        'https://zujuan.xkw.com/123456q123456789012.html',
      );
      expect(result.zujuanBankId, '123456');
      expect(result.zujuanQuestionId, '123456789012');
    });

    test('组卷网非题页路径只留链接', () {
      for (final input in <String>[
        'https://zujuan.xkw.com/view/123',
        'https://zujuan.xkw.com/10p3076310.html',
        'https://zujuan.xkw.com',
        'https://zujuan.xkw.com/',
      ]) {
        final result = parseSingle(input);
        expect(result.sourceUrl, isNotNull);
        expect(result.zujuanBankId, isNull, reason: input);
        expect(result.zujuanQuestionId, isNull, reason: input);
      }
    });
  });

  group('路径与文件名形状', () {
    test('带 bank 的路径重建出组卷网链接', () {
      final result = parseSingle('/10q35583902.html');
      expect(result.sourceUrl, 'https://zujuan.xkw.com/10q35583902.html');
      expect(result.zujuanBankId, '10');
      expect(result.zujuanQuestionId, '35583902');
    });

    test('不带前导斜杠的文件名同样重建', () {
      final result = parseSingle('10q35583902.html');
      expect(result.sourceUrl, 'https://zujuan.xkw.com/10q35583902.html');
      expect(result.zujuanQuestionId, '35583902');
    });

    test('只有题号没有 bank 时不编链接，只填题号', () {
      for (final input in <String>['/q35583902.html', 'q35583902.html']) {
        final result = parseSingle(input);
        expect(result.sourceUrl, isNull, reason: input);
        expect(result.zujuanBankId, isNull, reason: input);
        expect(result.zujuanQuestionId, '35583902', reason: input);
        expect(result.isEmpty, isFalse);
      }
    });

    test('大小写不敏感，重建链接用小写规范形状', () {
      final result = parseSingle('/10Q35583902.HTML');
      expect(result.sourceUrl, 'https://zujuan.xkw.com/10q35583902.html');
      expect(result.zujuanBankId, '10');
      expect(result.zujuanQuestionId, '35583902');
    });

    test('两端空白先 trim', () {
      final result = parseSingle('  10q35583902.html  ');
      expect(result.sourceUrl, 'https://zujuan.xkw.com/10q35583902.html');
      expect(result.zujuanQuestionId, '35583902');
    });

    test('全角空格也当空白 trim', () {
      final result = parseSingle('\u3000/10q5.html\u3000');
      expect(result.sourceUrl, 'https://zujuan.xkw.com/10q5.html');
      expect(result.zujuanBankId, '10');
      expect(result.zujuanQuestionId, '5');
    });

    test('6 位 bank 的路径可重建', () {
      final result = parseSingle('123456q7.html');
      expect(result.sourceUrl, 'https://zujuan.xkw.com/123456q7.html');
      expect(result.zujuanBankId, '123456');
      expect(result.zujuanQuestionId, '7');
    });

    test('带目录的普通路径不算题链（认不出）', () {
      expectNull('/foo/10q123.html');
      expectNull('foo/10q123.html');
    });

    test('路径后面还带内容不算题链（整串锚定）', () {
      expectNull('10q35583902.html?x=1');
      expectNull('10q35583902.html/extra');
      expectNull('10q35583902.html 后面还有字');
    });

    test('bank 超过 6 位或题号超过 12 位的路径不认', () {
      expectNull('1234567q7.html');
      expectNull('10q1234567890123.html');
    });

    test('缺少数字或后缀的路径不认', () {
      expectNull('10q.html');
      expectNull('10qabc.html');
      expectNull('/10q35583902');
      expectNull('q.html');
    });
  });

  group('别的站与非组卷网链接', () {
    test('别的站的普通链接只收 sourceUrl、两个 id 为 null', () {
      final result = parseSingle('https://example.com/a.html');
      expect(result.sourceUrl, 'https://example.com/a.html');
      expect(result.zujuanBankId, isNull);
      expect(result.zujuanQuestionId, isNull);
      expect(result.isEmpty, isFalse);
    });

    test('别的站即使路径像题页也不猜组卷网 id', () {
      final result = parseSingle('https://example.com/10q35583902.html');
      expect(result.sourceUrl, 'https://example.com/10q35583902.html');
      expect(result.zujuanBankId, isNull);
      expect(result.zujuanQuestionId, isNull);
    });

    test('伪装成组卷网子域的外站不填 id', () {
      final result = parseSingle(
        'https://zujuan.xkw.com.evil.com/10q5.html',
      );
      expect(result.sourceUrl, 'https://zujuan.xkw.com.evil.com/10q5.html');
      expect(result.zujuanBankId, isNull);
      expect(result.zujuanQuestionId, isNull);
    });

    test('别的站链接里的中文不 decode、不改写', () {
      final result = parseSingle('https://example.com/题目.html');
      expect(result.sourceUrl, 'https://example.com/题目.html');
      expect(result.zujuanQuestionId, isNull);
    });

    test('其它协议的绝对链接一律 null', () {
      for (final input in <String>[
        'javascript:alert(1)',
        'data:text/html,hi',
        'file:///C:/x.html',
        'mailto:a@b.com',
        'ftp://zujuan.xkw.com/10q5.html',
        'http://',
        'https://',
      ]) {
        expectNull(input);
      }
    });
  });

  group('空输入、纯数字与相对路径', () {
    test('空串与纯空白返回 null', () {
      for (final input in <String>['', '   ', '\n\t', '\u3000\u3000']) {
        expectNull(input);
      }
    });

    test('纯数字串不猜（可能是题号也可能是 bank）', () {
      for (final input in <String>['35583902', '10', '0', '00042']) {
        expectNull(input);
      }
    });

    test('普通相对路径与随机文字认不出', () {
      for (final input in <String>[
        'foo.html',
        'abc',
        'q35583902',
        '10q35583902',
        '#frag',
        '?x=1',
      ]) {
        expectNull(input);
      }
    });
  });

  group('toJson、相等性与 isEmpty', () {
    test('toJson 键固定且完整结果写出三字段', () {
      final result = parseSingle('/10q5.html');
      final json = result.toJson();
      expect(json.keys.toList(), <String>[
        'source_url',
        'zujuan_question_id',
        'zujuan_bank_id',
      ]);
      expect(json, <String, Object?>{
        'source_url': 'https://zujuan.xkw.com/10q5.html',
        'zujuan_question_id': '5',
        'zujuan_bank_id': '10',
      });
    });

    test('toJson 对 null 也写出（缺 bank 场景）', () {
      final result = parseSingle('/q35583902.html');
      expect(result.toJson(), <String, Object?>{
        'source_url': null,
        'zujuan_question_id': '35583902',
        'zujuan_bank_id': null,
      });
    });

    test('const 空对象 isEmpty 且 toJson 三键全 null', () {
      const empty = ZujuanSourceInput();
      expect(empty.isEmpty, isTrue);
      expect(empty.toJson(), <String, Object?>{
        'source_url': null,
        'zujuan_question_id': null,
        'zujuan_bank_id': null,
      });
    });

    test('任意一个字段非空就不是 isEmpty', () {
      expect(const ZujuanSourceInput(sourceUrl: 'https://a.com/b').isEmpty,
          isFalse);
      expect(
        const ZujuanSourceInput(zujuanQuestionId: '5').isEmpty,
        isFalse,
      );
      expect(const ZujuanSourceInput(zujuanBankId: '10').isEmpty, isFalse);
    });

    test('相等性按三个字段，hashCode 一致', () {
      const a = ZujuanSourceInput(
        sourceUrl: 'https://zujuan.xkw.com/10q5.html',
        zujuanQuestionId: '5',
        zujuanBankId: '10',
      );
      const b = ZujuanSourceInput(
        sourceUrl: 'https://zujuan.xkw.com/10q5.html',
        zujuanQuestionId: '5',
        zujuanBankId: '10',
      );
      const c = ZujuanSourceInput(
        sourceUrl: 'https://zujuan.xkw.com/10q5.html',
        zujuanQuestionId: '6',
        zujuanBankId: '10',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('toString 带三个字段名与值', () {
      final text = parseSingle('/10q5.html').toString();
      expect(text, contains('ZujuanSourceInput'));
      expect(text, contains('sourceUrl'));
      expect(text, contains('zujuanQuestionId'));
      expect(text, contains('zujuanBankId'));
      expect(text, contains('https://zujuan.xkw.com/10q5.html'));
    });

    test('同一输入两次解析结果相等', () {
      final first = parseSingle('/10q35583902.html');
      final second = parseSingle('/10q35583902.html');
      expect(first, second);
      expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
    });
  });

  group('永不抛异常与确定性', () {
    test('脏字符串都不抛异常', () {
      final inputs = <String>[
        '(((',
        ']]]',
        '\n\n',
        String.fromCharCode(92),
        String.fromCharCode(0),
        '%',
        '%%%',
        'http://[::1',
        'https://zujuan.xkw.com/',
        '"quoted"',
        "'single'",
        'a b c',
        'https://zujuan.xkw.com/10q5.html#',
        '/q.html',
        '123456789012345678901234567890',
      ];
      for (final input in inputs) {
        expect(
          () => parseZujuanSourceInput(input),
          returnsNormally,
          reason: jsonEncode(input),
        );
      }
    });

    test('超长乱串与超长题链路径都不抛', () {
      final longGarbage = 'x' * 20000;
      expect(parseZujuanSourceInput(longGarbage), isNull);
      final longPath = '/${'a' * 5000}q1.html';
      expect(parseZujuanSourceInput(longPath), isNull);
      expect(
        () => parseZujuanSourceInput('https://zujuan.xkw.com/$longGarbage'),
        returnsNormally,
      );
    });

    test('空输入与纯空白永不抛且返回 null', () {
      for (final input in <String>['', ' ', '\t', '\n', ' \u3000 ']) {
        expect(
          () => parseZujuanSourceInput(input),
          returnsNormally,
          reason: jsonEncode(input),
        );
        expect(parseZujuanSourceInput(input), isNull);
      }
    });

    test('同一输入结果确定（不是靠随机/时间）', () {
      const input = 'https://zujuan.xkw.com/10q5.html?x=1';
      final first = parseZujuanSourceInput(input);
      final second = parseZujuanSourceInput(input);
      expect(first, second);
      expect(first?.toJson(), second?.toJson());
    });
  });
}
