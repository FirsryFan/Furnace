import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_source.dart';
import 'package:furnace/domain/services/zujuan/zujuan_link.dart';

/// 组卷网题目详情页样本链接（bankId=10，questionId=35583902）。
const String _zujuanQuestionUrl = 'https://zujuan.xkw.com/10q35583902.html';

QuestionSourceRef? _fromStored(String? url) =>
    questionSourceFor(sourceUrl: url);

void main() {
  group('QuestionSourceRef 值语义', () {
    const ref = QuestionSourceRef(
      url: 'https://zujuan.xkw.com/10q35583902.html',
      host: 'zujuan.xkw.com',
      fromStoredUrl: true,
      isZujuan: true,
    );

    test('toJson 输出 url / host / from_stored_url / is_zujuan 四个键', () {
      expect(ref.toJson(), <String, Object?>{
        'url': 'https://zujuan.xkw.com/10q35583902.html',
        'host': 'zujuan.xkw.com',
        'from_stored_url': true,
        'is_zujuan': true,
      });
    });

    test('四个字段全相同则相等且 hashCode 相同', () {
      const same = QuestionSourceRef(
        url: 'https://zujuan.xkw.com/10q35583902.html',
        host: 'zujuan.xkw.com',
        fromStoredUrl: true,
        isZujuan: true,
      );
      expect(ref, same);
      expect(ref.hashCode, same.hashCode);
    });

    test('任一字段不同就不相等', () {
      const variants = <QuestionSourceRef>[
        QuestionSourceRef(
          url: 'https://zujuan.xkw.com/other.html',
          host: 'zujuan.xkw.com',
          fromStoredUrl: true,
          isZujuan: true,
        ),
        QuestionSourceRef(
          url: 'https://zujuan.xkw.com/10q35583902.html',
          host: 'example.com',
          fromStoredUrl: true,
          isZujuan: true,
        ),
        QuestionSourceRef(
          url: 'https://zujuan.xkw.com/10q35583902.html',
          host: 'zujuan.xkw.com',
          fromStoredUrl: false,
          isZujuan: true,
        ),
        QuestionSourceRef(
          url: 'https://zujuan.xkw.com/10q35583902.html',
          host: 'zujuan.xkw.com',
          fromStoredUrl: true,
          isZujuan: false,
        ),
      ];
      for (final variant in variants) {
        expect(variant == ref, isFalse);
      }
    });

    test('toString 带出四个字段', () {
      expect(
        ref.toString(),
        'QuestionSourceRef(url: https://zujuan.xkw.com/10q35583902.html, '
        'host: zujuan.xkw.com, fromStoredUrl: true, isZujuan: true)',
      );
    });
  });

  group('库存链接规范化', () {
    test('存库 https 链接原样采用', () {
      final ref = _fromStored(_zujuanQuestionUrl);
      expect(ref, isNotNull);
      expect(ref!.url, _zujuanQuestionUrl);
      expect(ref.host, 'zujuan.xkw.com');
      expect(ref.fromStoredUrl, isTrue);
      expect(ref.isZujuan, isTrue);
    });

    test('scheme 与 host 大写被小写化', () {
      final ref = _fromStored('HTTPS://ZUJUAN.XKW.COM/10q35583902.html');
      expect(ref, isNotNull);
      expect(ref!.url, _zujuanQuestionUrl);
      expect(ref.host, 'zujuan.xkw.com');
    });

    test('去掉 fragment', () {
      final ref = _fromStored('$_zujuanQuestionUrl#section-answer');
      expect(ref, isNotNull);
      expect(ref!.url, _zujuanQuestionUrl);
    });

    test('http 保留不升级为 https', () {
      final ref = _fromStored('http://zujuan.xkw.com/10q1.html');
      expect(ref, isNotNull);
      expect(ref!.url, 'http://zujuan.xkw.com/10q1.html');
      expect(ref.isZujuan, isTrue);
      expect(ref.fromStoredUrl, isTrue);
    });

    test('https 默认端口 443 去掉', () {
      final ref = _fromStored('https://zujuan.xkw.com:443/10q1.html');
      expect(ref, isNotNull);
      expect(ref!.url, 'https://zujuan.xkw.com/10q1.html');
    });

    test('http 默认端口 80 去掉', () {
      final ref = _fromStored('http://zujuan.xkw.com:80/10q1.html');
      expect(ref, isNotNull);
      expect(ref!.url, 'http://zujuan.xkw.com/10q1.html');
    });

    test('非默认端口保留', () {
      final ref = _fromStored('https://example.com:8443/q/1.html');
      expect(ref, isNotNull);
      expect(ref!.url, 'https://example.com:8443/q/1.html');
      expect(ref.host, 'example.com');
      expect(ref.isZujuan, isFalse);
    });

    test('query 逐字节保留（含百分比编码与与号）', () {
      const input =
          'https://zujuan.xkw.com/quessearch?keyword=YWI%3D&intent=question#top';
      final ref = _fromStored(input);
      expect(ref, isNotNull);
      expect(
        ref!.url,
        'https://zujuan.xkw.com/quessearch?keyword=YWI%3D&intent=question',
      );
    });

    test('path 多段与编码逐字节保留，不补尾斜杠', () {
      final ref = _fromStored('https://zujuan.xkw.com/q/10q1%2F2.html');
      expect(ref, isNotNull);
      expect(ref!.url, 'https://zujuan.xkw.com/q/10q1%2F2.html');
      final noPath = _fromStored('https://example.com');
      expect(noPath, isNotNull);
      expect(noPath!.url, 'https://example.com');
    });

    test('两侧空白被 trim', () {
      final ref = _fromStored('  $_zujuanQuestionUrl  ');
      expect(ref, isNotNull);
      expect(ref!.url, _zujuanQuestionUrl);
    });

    test('host 字段不含端口', () {
      final ref = _fromStored('https://example.com:8443/q');
      expect(ref, isNotNull);
      expect(ref!.host, 'example.com');
    });

    test('IPv6 字面量 host 保留方括号且端口不丢', () {
      final ref = _fromStored('https://[::1]:8080/a');
      expect(ref, isNotNull);
      expect(ref!.url, 'https://[::1]:8080/a');
      expect(ref.host, '::1');
      expect(ref.isZujuan, isFalse);
    });
  });

  group('组卷网 host 判定', () {
    test('主站 zujuan.xkw.com 命中', () {
      final ref = _fromStored(_zujuanQuestionUrl);
      expect(ref!.isZujuan, isTrue);
    });

    test('子域 *.zujuan.xkw.com 命中', () {
      final ref = _fromStored('https://st.zujuan.xkw.com/10q1.html');
      expect(ref, isNotNull);
      expect(ref!.isZujuan, isTrue);
      expect(ref.host, 'st.zujuan.xkw.com');
    });

    test('其它站点 isZujuan=false', () {
      final ref = _fromStored('https://www.example.com/q/1');
      expect(ref, isNotNull);
      expect(ref!.isZujuan, isFalse);
      expect(ref.fromStoredUrl, isTrue);
    });

    test('伪装域名 zujuan.xkw.com.evil.com 不算组卷网', () {
      final ref = _fromStored('https://zujuan.xkw.com.evil.com/10q1.html');
      expect(ref, isNotNull);
      expect(ref!.isZujuan, isFalse);
    });

    test('相似域名 notzujuan.xkw.com 不算组卷网', () {
      final ref = _fromStored('https://notzujuan.xkw.com/10q1.html');
      expect(ref, isNotNull);
      expect(ref!.isZujuan, isFalse);
    });
  });

  group('不可信 / 非法输入返回 null', () {
    test('javascript: 拒绝', () {
      expect(_fromStored('javascript:alert(1)'), isNull);
    });

    test('data: 拒绝', () {
      expect(_fromStored('data:text/html,<b>x</b>'), isNull);
    });

    test('file: 拒绝', () {
      expect(_fromStored('file:///C:/tmp/x.html'), isNull);
    });

    test('mailto: 拒绝', () {
      expect(_fromStored('mailto:a@b.com'), isNull);
    });

    test('绝对路径 /questions/1 拒绝', () {
      expect(_fromStored('/questions/1'), isNull);
    });

    test('相对路径 questions/1 拒绝', () {
      expect(_fromStored('questions/1'), isNull);
    });

    test('协议相对 //example.com/a 拒绝', () {
      expect(_fromStored('//example.com/a'), isNull);
    });

    test('ftp: 拒绝', () {
      expect(_fromStored('ftp://example.com/a'), isNull);
    });

    test('http:// 空 host 拒绝', () {
      expect(_fromStored('http://'), isNull);
    });

    test('https:///path 空 host 拒绝', () {
      expect(_fromStored('https:///path'), isNull);
    });

    test('只有端口没有 host 拒绝', () {
      expect(_fromStored('http://:8080/a'), isNull);
    });

    test('纯空白字符串拒绝', () {
      expect(_fromStored('   '), isNull);
    });

    test('null 拒绝', () {
      expect(_fromStored(null), isNull);
    });
  });

  group('用组卷网题目 id 重建链接', () {
    test('全空返回 null', () {
      expect(questionSourceFor(), isNull);
    });

    test('sourceUrl 空白且无 id 返回 null', () {
      expect(questionSourceFor(sourceUrl: '   '), isNull);
    });

    test('只有 questionId 缺 bankId 返回 null', () {
      expect(questionSourceFor(zujuanQuestionId: '35583902'), isNull);
    });

    test('只有 bankId 缺 questionId 返回 null', () {
      expect(questionSourceFor(zujuanBankId: '10'), isNull);
    });

    test('两个 id 完整时重建成功且字段口径正确', () {
      final ref = questionSourceFor(
        zujuanQuestionId: '35583902',
        zujuanBankId: '10',
      );
      expect(ref, isNotNull);
      expect(
          ref!.url,
          zujuanQuestionDetailUrl(
            bankId: '10',
            questionId: '35583902',
          ));
      expect(ref.host, 'zujuan.xkw.com');
      expect(ref.fromStoredUrl, isFalse);
      expect(ref.isZujuan, isTrue);
    });

    test('id 两端空白由既有 helper trim 后仍能重建', () {
      final ref = questionSourceFor(
        zujuanQuestionId: ' 35583902 ',
        zujuanBankId: ' 10 ',
      );
      expect(ref, isNotNull);
      expect(
          ref!.url,
          zujuanQuestionDetailUrl(
            bankId: ' 10 ',
            questionId: ' 35583902 ',
          ));
    });

    test('questionId 非纯数字返回 null', () {
      expect(
        questionSourceFor(
          zujuanQuestionId: '35583902a',
          zujuanBankId: '10',
        ),
        isNull,
      );
    });

    test('id 内部空白返回 null', () {
      expect(
        questionSourceFor(
          zujuanQuestionId: '3558 3902',
          zujuanBankId: '10',
        ),
        isNull,
      );
    });

    test('sourceUrl 不可信时回退到 id 重建', () {
      final ref = questionSourceFor(
        sourceUrl: 'javascript:alert(1)',
        zujuanQuestionId: '35583902',
        zujuanBankId: '10',
      );
      expect(ref, isNotNull);
      expect(ref!.fromStoredUrl, isFalse);
      expect(
          ref.url,
          zujuanQuestionDetailUrl(
            bankId: '10',
            questionId: '35583902',
          ));
    });

    test('合法 sourceUrl 优先于 id 重建', () {
      final ref = questionSourceFor(
        sourceUrl: 'https://example.com/q/1',
        zujuanQuestionId: '35583902',
        zujuanBankId: '10',
      );
      expect(ref, isNotNull);
      expect(ref!.url, 'https://example.com/q/1');
      expect(ref.fromStoredUrl, isTrue);
      expect(ref.isZujuan, isFalse);
    });

    test('存库组卷网链接优先于 id 重建', () {
      final ref = questionSourceFor(
        sourceUrl: 'https://zujuan.xkw.com/99q111.html',
        zujuanQuestionId: '35583902',
        zujuanBankId: '10',
      );
      expect(ref, isNotNull);
      expect(ref!.url, 'https://zujuan.xkw.com/99q111.html');
      expect(ref.fromStoredUrl, isTrue);
    });

    test('非法 sourceUrl 且 id 不全时返回 null', () {
      expect(
        questionSourceFor(
          sourceUrl: 'data:text/plain,x',
          zujuanQuestionId: '35583902',
        ),
        isNull,
      );
    });
  });
}
