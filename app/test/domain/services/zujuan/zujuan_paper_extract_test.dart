import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/zujuan/zujuan_paper_extract.dart';

ZujuanPaperExtract _parse(String raw) => parseZujuanPaperText(raw);

/// 生成 [count] 道题的整卷文本（带试卷链接与 10 bank 前缀）。
String _paperWithQuestions(int count) {
  final buffer = StringBuffer('/10p3076310.html ');
  for (var i = 1; i <= count; i++) {
    buffer.write('<a href="/10q$i.html">第$i题</a> ');
  }
  return buffer.toString();
}

void main() {
  group('空输入与无链接', () {
    test('空字符串返回空结果且不抛', () {
      final extract = _parse('');
      expect(extract.isEmpty, isTrue);
      expect(extract.questionCount, 0);
      expect(extract.paperId, isNull);
      expect(extract.bankId, isNull);
      expect(extract.title, isNull);
      expect(extract.questionIds, isEmpty);
      expect(extract.questionLinks, isEmpty);
      expect(extract.truncated, isFalse);
      expect(extract.warnings, <String>[
        '没有找到试卷编号（形如 /10p3076310.html）',
        '没有找到题目链接',
      ]);
    });

    test('纯空白文本返回空结果', () {
      final extract = _parse(' \n\t　 ');
      expect(extract.isEmpty, isTrue);
      expect(extract.questionIds, isEmpty);
    });

    test('普通文本没有链接时 isEmpty 为 true', () {
      final extract = _parse('这是一段试卷说明，没有任何链接。');
      expect(extract.isEmpty, isTrue);
      expect(extract.warnings, contains('没有找到题目链接'));
    });

    test('只有试卷 URL 没有题目链接', () {
      final extract = _parse('https://zujuan.xkw.com/10p3076310.html');
      expect(extract.isEmpty, isFalse);
      expect(extract.paperId, '3076310');
      expect(extract.bankId, '10');
      expect(extract.questionCount, 0);
      expect(extract.questionLinks, isEmpty);
      expect(extract.warnings, <String>['没有找到题目链接']);
    });

    test('只有 p 链接缺 bank 时 bankId 为 null', () {
      final extract = _parse('/p3076310.html');
      expect(extract.paperId, '3076310');
      expect(extract.bankId, isNull);
      expect(extract.isEmpty, isFalse);
      expect(extract.warnings, <String>['没有找到题目链接']);
    });
  });

  group('试卷标识抽取', () {
    test('HTML 相对链接解析出 bankId 与 paperId', () {
      final extract = _parse('<a href="/10p3076310.html">整卷</a>');
      expect(extract.bankId, '10');
      expect(extract.paperId, '3076310');
    });

    test('绝对 URL 的试卷链接也能识别', () {
      final extract = _parse('https://zujuan.xkw.com/10p3076310.html');
      expect(extract.paperId, '3076310');
      expect(extract.bankId, '10');
    });

    test('多个试卷链接取第一个', () {
      final extract = _parse('/10p111.html 与 /10p222.html');
      expect(extract.paperId, '111');
    });

    test('大写 P 也能识别', () {
      final extract = _parse('/10P3076310.html');
      expect(extract.paperId, '3076310');
      expect(extract.bankId, '10');
    });

    test('非数字 bank 的伪试卷链接不误认', () {
      final extract = _parse('https://evil.example.com/abcp3076310.html');
      expect(extract.paperId, isNull);
      expect(extract.bankId, isNull);
      expect(extract.warnings, contains('没有找到试卷编号（形如 /10p3076310.html）'));
    });

    test('缺少 .html 后缀不识别为试卷', () {
      final extract = _parse('/10p3076310');
      expect(extract.paperId, isNull);
    });
  });

  group('题号抽取与链接生成', () {
    test('单个带 bank 前缀的题号生成详情页链接', () {
      final extract = _parse(
        '/10p3076310.html <a href="/10q35583902.html">第1题</a>',
      );
      expect(extract.questionIds, <int>[35583902]);
      expect(
        extract.questionLinks,
        <String>['https://zujuan.xkw.com/10q35583902.html'],
      );
      expect(extract.warnings, <String>['找到 1 个题目链接']);
    });

    test('多个题号按页面出现顺序保留', () {
      final extract = _parse('/10p5.html /10q1.html /10q2.html /10q3.html');
      expect(extract.questionIds, <int>[1, 2, 3]);
      expect(extract.questionLinks, <String>[
        'https://zujuan.xkw.com/10q1.html',
        'https://zujuan.xkw.com/10q2.html',
        'https://zujuan.xkw.com/10q3.html',
      ]);
      expect(extract.warnings, <String>['找到 3 个题目链接']);
    });

    test('重复题号去重保序并告警', () {
      final extract = _parse(
        '/10p5.html /10q1.html /10q2.html /10q1.html',
      );
      expect(extract.questionIds, <int>[1, 2]);
      expect(extract.questionLinks, hasLength(2));
      expect(extract.warnings, <String>[
        '重复题号已去重',
        '找到 2 个题目链接',
      ]);
    });

    test('裸 q 链接借用页面 bankId 生成链接', () {
      final extract = _parse('/10p5.html /q35583902.html');
      expect(extract.questionIds, <int>[35583902]);
      expect(
        extract.questionLinks,
        <String>['https://zujuan.xkw.com/10q35583902.html'],
      );
    });

    test('裸 q 链接且无页面 bankId 时不生成链接并告警', () {
      final extract = _parse('/q123.html');
      expect(extract.questionIds, <int>[123]);
      expect(extract.questionLinks, isEmpty);
      expect(extract.warnings, <String>[
        '没有找到试卷编号（形如 /10p3076310.html）',
        '有 1 个题号缺少 bankId，未生成链接',
        '找到 1 个题目链接',
      ]);
    });

    test('题号自带 bank 前缀优先于页面 bankId', () {
      final extract = _parse('/10p5.html /10q1.html /11q2.html');
      expect(extract.questionIds, <int>[1, 2]);
      expect(extract.questionLinks, <String>[
        'https://zujuan.xkw.com/10q1.html',
        'https://zujuan.xkw.com/11q2.html',
      ]);
    });

    test('q 链接带 query 与 fragment 仍能识别', () {
      final extract = _parse('/10p5.html /10q1.html?from=list#answer');
      expect(extract.questionIds, <int>[1]);
      expect(
        extract.questionLinks,
        <String>['https://zujuan.xkw.com/10q1.html'],
      );
    });

    test('相对与绝对 q 链接混用都能识别', () {
      final extract = _parse(
        '/10p5.html q1.html https://zujuan.xkw.com/10q2.html',
      );
      expect(extract.questionIds, <int>[1, 2]);
      expect(extract.questionLinks, <String>[
        'https://zujuan.xkw.com/10q1.html',
        'https://zujuan.xkw.com/10q2.html',
      ]);
    });

    test('非数字 bank 的伪题号链接不误认', () {
      final extract = _parse('/abcq123.html');
      expect(extract.questionIds, isEmpty);
      expect(extract.warnings, contains('没有找到题目链接'));
    });

    test('非数字题号不识别', () {
      final extract = _parse('/10qabc.html');
      expect(extract.questionIds, isEmpty);
    });

    test('缺少 .html 后缀的题号不识别', () {
      final extract = _parse('/10q123');
      expect(extract.questionIds, isEmpty);
    });

    test('起始位置裸 q 链接也识别', () {
      final extract = _parse('q123456.html');
      expect(extract.questionIds, <int>[123456]);
      expect(extract.questionLinks, isEmpty);
      expect(extract.warnings, <String>[
        '没有找到试卷编号（形如 /10p3076310.html）',
        '有 1 个题号缺少 bankId，未生成链接',
        '找到 1 个题目链接',
      ]);
    });

    test('重复题号去重后链接数量与 ids 一致', () {
      final extract = _parse('/10p5.html /10q5.html /10q5.html');
      expect(extract.questionIds, <int>[5]);
      expect(extract.questionLinks, hasLength(1));
    });

    test('部分题号缺 bank 时链接是 ids 的同序子集', () {
      final extract = _parse('/p1.html /10q1.html /q2.html');
      expect(extract.questionIds, <int>[1, 2]);
      expect(
        extract.questionLinks,
        <String>['https://zujuan.xkw.com/10q1.html'],
      );
      expect(extract.warnings, <String>[
        '有 1 个题号缺少 bankId，未生成链接',
        '找到 2 个题目链接',
      ]);
    });
  });

  group('上限与截断', () {
    test('恰好 200 个题号不截断', () {
      final extract = _parse(_paperWithQuestions(200));
      expect(extract.truncated, isFalse);
      expect(extract.questionCount, 200);
      expect(extract.questionLinks, hasLength(200));
      expect(extract.questionIds.first, 1);
      expect(extract.questionIds.last, 200);
      expect(extract.warnings, <String>['找到 200 个题目链接']);
    });

    test('超过 200 个题号截断且给出 warning', () {
      final extract = _parse(_paperWithQuestions(205));
      expect(extract.truncated, isTrue);
      expect(extract.questionCount, 200);
      expect(extract.questionIds.last, 200);
      expect(extract.questionLinks, hasLength(200));
      expect(extract.warnings, <String>[
        '超过 200 道，只取前 200 道',
        '找到 200 个题目链接',
      ]);
    });

    test('截断与重复告警可同时出现且顺序稳定', () {
      final raw = '${_paperWithQuestions(201)} /10q1.html';
      final extract = _parse(raw);
      expect(extract.truncated, isTrue);
      expect(extract.questionCount, 200);
      expect(extract.warnings, <String>[
        '重复题号已去重',
        '超过 200 道，只取前 200 道',
        '找到 200 个题目链接',
      ]);
    });
  });

  group('标题抽取', () {
    test('<title> 优先于 <h1>', () {
      final extract = _parse(
        '<title>整卷标题</title><h1>另一标题</h1>/10p1.html',
      );
      expect(extract.title, '整卷标题');
    });

    test('title 多行与连续空白折叠为单空格', () {
      final extract = _parse('<title>\n  2026届   高三  </title>');
      expect(extract.title, '2026届 高三');
    });

    test('title 解常见 HTML 实体', () {
      final extract = _parse(
        '<title>A&amp;B &#20320;&#x597D; &nbsp; 卷</title>',
      );
      expect(extract.title, 'A&B 你好 卷');
    });

    test('title 为空时回退 h1', () {
      final extract = _parse('<title>   </title><h1>备用标题</h1>');
      expect(extract.title, '备用标题');
    });

    test('没有 title 时用 h1 并剥掉内嵌标签', () {
      final extract = _parse(
        '<h1 class="paper"><span>2026</span> 模拟卷</h1>',
      );
      expect(extract.title, '2026 模拟卷');
    });

    test('没有 title/h1 时 title 为 null（不猜）', () {
      final extract = _parse('<h2>疑似试卷</h2>/10p1.html');
      expect(extract.title, isNull);
    });

    test('大写 TITLE 标签也识别', () {
      final extract = _parse('<TITLE>整卷</TITLE>');
      expect(extract.title, '整卷');
    });

    test('title 只出现空 h1 时仍为 null', () {
      final extract = _parse('<h1>   </h1>');
      expect(extract.title, isNull);
    });
  });

  group('序列化与值语义', () {
    test('toJson 键名与字段对应', () {
      final extract = _parse(
        '<title>整卷</title><h1>标题</h1>/10p3076310.html /10q1.html',
      );
      final json = extract.toJson();
      expect(json.keys.toList(), <String>[
        'paper_id',
        'bank_id',
        'title',
        'question_ids',
        'question_links',
        'warnings',
        'truncated',
      ]);
      expect(json['paper_id'], '3076310');
      expect(json['bank_id'], '10');
      expect(json['title'], '整卷');
      expect(json['question_ids'], <int>[1]);
      expect(json['question_links'], <String>[
        'https://zujuan.xkw.com/10q1.html',
      ]);
      expect(json['warnings'], <String>['找到 1 个题目链接']);
      expect(json['truncated'], isFalse);
    });

    test('相同输入两次解析结果相等且 hashCode 相同', () {
      const raw = '/10p5.html <title>整卷</title> /10q1.html /10q2.html';
      final first = _parse(raw);
      final second = _parse(raw);
      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('题号不同则两个结果不相等', () {
      final first = _parse('/10p5.html /10q1.html');
      final second = _parse('/10p5.html /10q2.html');
      expect(first == second, isFalse);
    });

    test('toString 带出关键字段', () {
      final extract = _parse('/10p5.html /10q1.html');
      expect(extract.toString(), contains('paperId: 5'));
      expect(extract.toString(), contains('questionIds: [1]'));
      expect(extract.toString(), contains('truncated: false'));
    });

    test('questionCount 与 isEmpty 语义', () {
      final onlyTitle = _parse('<title>只有标题</title>');
      expect(onlyTitle.isEmpty, isFalse);
      expect(onlyTitle.questionCount, 0);
      final onlyPaper = _parse('/10p1.html');
      expect(onlyPaper.isEmpty, isFalse);
      expect(onlyPaper.questionCount, 0);
      final onlyQuestion = _parse('/10q1.html');
      expect(onlyQuestion.isEmpty, isFalse);
      expect(onlyQuestion.questionCount, 1);
    });

    test('解析结果列表不可变', () {
      final extract = _parse('/10p5.html /10q1.html');
      expect(() => extract.questionIds.add(9), throwsUnsupportedError);
      expect(() => extract.questionLinks.add('x'), throwsUnsupportedError);
      expect(() => extract.warnings.add('x'), throwsUnsupportedError);
    });

    test('全角空白与换行包裹的脏文本也能解析', () {
      final extract = _parse(
        '　<a href="/10p3076310.html">整卷</a>\n\n'
        '<a href="/10q7.html">第7题</a>　',
      );
      expect(extract.paperId, '3076310');
      expect(extract.questionIds, <int>[7]);
      expect(extract.questionLinks, <String>[
        'https://zujuan.xkw.com/10q7.html',
      ]);
    });

    test('同一页面重复解析结果稳定（确定性）', () {
      final raw = '${_paperWithQuestions(3)} <title>整卷</title>';
      expect(_parse(raw), _parse(raw));
    });
  });
}
