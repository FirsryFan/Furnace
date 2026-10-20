import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/zujuan/zujuan_link.dart'
    show zujuanBaseUrl;
import 'package:furnace/domain/services/zujuan/zujuan_query.dart';

/// 组卷网列表页「定点找题」链接（纯逻辑）的验收点：
///
///  * 链接形状与筛选段顺序抄自权威文档
///    D:/dsh-data/skills/zujuan-source-standards/references/url-grammar.md
///    §2（结构/页码拼法）、§3（题型 ID 与知识点根节点）、§4（省份码）；
///  * 每个期望 URL 都在注释里给出文档出处或文档里的实测样例，
///    不是凭记忆拼的；
///  * 非法/未知取值忽略该段（不抛异常、不拼坏链接），知识点 id 非法时
///    回退学科根节点；
///  * 确定性：同输入同输出；纯函数不读 IO。
void main() {
  ZujuanQuerySpec spec({
    ZujuanSubject subject = ZujuanSubject.math,
    String? knowledgePointId,
    ZujuanDifficulty? difficulty,
    int? questionTypeId,
    int? classificationId,
    bool onlyNew = false,
    int? year,
    String? provinceCode,
    int? grade,
    int? semester,
    ZujuanSort? sort,
    int page = 1,
  }) {
    return ZujuanQuerySpec(
      subject: subject,
      knowledgePointId: knowledgePointId,
      difficulty: difficulty,
      questionTypeId: questionTypeId,
      classificationId: classificationId,
      onlyNew: onlyNew,
      year: year,
      provinceCode: provinceCode,
      grade: grade,
      semester: semester,
      sort: sort,
      page: page,
    );
  }

  group('zujuanSubjectFor：仓库学科键与站点 path 都认', () {
    test('六科英文键（大小写不敏感、两端空白先 trim）', () {
      expect(zujuanSubjectFor('math'), ZujuanSubject.math);
      expect(zujuanSubjectFor('physics'), ZujuanSubject.physics);
      expect(zujuanSubjectFor('chemistry'), ZujuanSubject.chemistry);
      expect(zujuanSubjectFor('biology'), ZujuanSubject.biology);
      expect(zujuanSubjectFor('chinese'), ZujuanSubject.chinese);
      expect(zujuanSubjectFor('english'), ZujuanSubject.english);
      expect(zujuanSubjectFor('MATH'), ZujuanSubject.math);
      expect(zujuanSubjectFor('  Physics  '), ZujuanSubject.physics);
    });

    test('六科站点 path（gzsx 等，url-grammar.md:79-99）', () {
      expect(zujuanSubjectFor('gzsx'), ZujuanSubject.math);
      expect(zujuanSubjectFor('gzwl'), ZujuanSubject.physics);
      expect(zujuanSubjectFor('gzhx'), ZujuanSubject.chemistry);
      expect(zujuanSubjectFor('gzsw'), ZujuanSubject.biology);
      expect(zujuanSubjectFor('gzyw'), ZujuanSubject.chinese);
      expect(zujuanSubjectFor('gzyy'), ZujuanSubject.english);
      expect(zujuanSubjectFor(' GZSW '), ZujuanSubject.biology);
    });

    test('认不出返回 null，不猜', () {
      expect(zujuanSubjectFor(''), isNull);
      expect(zujuanSubjectFor('   '), isNull);
      expect(zujuanSubjectFor('history'), isNull);
      expect(zujuanSubjectFor('informatics'), isNull);
      expect(zujuanSubjectFor('qiangji'), isNull);
      expect(zujuanSubjectFor('数学'), isNull);
      expect(zujuanSubjectFor('gzsx/'), isNull);
      expect(zujuanSubjectFor('gzsx '), ZujuanSubject.math);
    });
  });

  group('ZujuanSubject：path / 根节点 / 题型词表（url-grammar.md §3）', () {
    test('枚举顺序与契约一致', () {
      expect(
        ZujuanSubject.values.map((subject) => subject.name).toList(),
        <String>[
          'chinese',
          'math',
          'english',
          'physics',
          'chemistry',
          'biology',
        ],
      );
    });

    test('语文：gzyw / 根节点 23177 / 8 种题型', () {
      const subject = ZujuanSubject.chinese;
      expect(subject.path, 'gzyw');
      expect(subject.rootKnowledgePointId, '23177');
      expect(subject.questionTypeIds.length, 8);
      expect(subject.questionTypeIds[2602], '现代文阅读');
      expect(subject.questionTypeIds[2613], '判断题');
    });

    test('数学：gzsx / 根节点 27925 / 6 种题型', () {
      const subject = ZujuanSubject.math;
      expect(subject.path, 'gzsx');
      expect(subject.rootKnowledgePointId, '27925');
      expect(subject.questionTypeIds.length, 6);
      expect(subject.questionTypeIds[2701], '单选');
      expect(subject.questionTypeIds[2707], '概念填空');
    });

    test('英语：gzyy / 根节点 29978 / 14 种题型', () {
      const subject = ZujuanSubject.english;
      expect(subject.path, 'gzyy');
      expect(subject.rootKnowledgePointId, '29978');
      expect(subject.questionTypeIds.length, 14);
      expect(subject.questionTypeIds[2823], '书信写作');
      expect(subject.questionTypeIds[2801], '听力选择');
    });

    test('物理：gzwl / 根节点 41934 / 9 种题型', () {
      const subject = ZujuanSubject.physics;
      expect(subject.path, 'gzwl');
      expect(subject.rootKnowledgePointId, '41934');
      expect(subject.questionTypeIds.length, 9);
      expect(subject.questionTypeIds[2905], '作图');
    });

    test('化学：gzhx / 根节点 43452 / 7 种题型', () {
      const subject = ZujuanSubject.chemistry;
      expect(subject.path, 'gzhx');
      expect(subject.rootKnowledgePointId, '43452');
      expect(subject.questionTypeIds.length, 7);
      expect(subject.questionTypeIds[3013], '综合');
    });

    test('生物：gzsw / 根节点 44886 / 6 种题型（含 3107 实验）', () {
      const subject = ZujuanSubject.biology;
      expect(subject.path, 'gzsw');
      expect(subject.rootKnowledgePointId, '44886');
      expect(subject.questionTypeIds.length, 6);
      expect(subject.questionTypeIds[310101], '单选');
      expect(subject.questionTypeIds[3107], '实验');
    });

    test('题型 id 跨学科不撞（照抄别科会静默 0 条）', () {
      final ids = <int>[];
      for (final subject in ZujuanSubject.values) {
        ids.addAll(subject.questionTypeIds.keys);
      }
      expect(ids.length, ids.toSet().length);
    });

    test('根节点 id 六科互不相同', () {
      final roots = ZujuanSubject.values
          .map((subject) => subject.rootKnowledgePointId)
          .toList();
      expect(roots.toSet().length, roots.length);
    });

    test('每科题型词表非空、id 为正、中文名非空', () {
      for (final subject in ZujuanSubject.values) {
        expect(subject.questionTypeIds, isNotEmpty);
        for (final entry in subject.questionTypeIds.entries) {
          expect(entry.key, greaterThan(0));
          expect(entry.value.trim(), isNotEmpty);
        }
      }
    });
  });

  group('省份表与枚举段（url-grammar.md:41/49/118-131）', () {
    test('实测八省行政区码', () {
      expect(zujuanProvinceCodes, <String, int>{
        '山东': 370000,
        '广东': 440000,
        '四川': 510000,
        '浙江': 330000,
        '陕西': 610000,
        '北京': 110000,
        '重庆': 500000,
        '上海': 310000,
      });
    });

    test('省份名列表与码表同序同键', () {
      expect(
        zujuanProvinceNames,
        zujuanProvinceCodes.keys.toList(growable: false),
      );
      expect(zujuanProvinceNames.length, 8);
      expect(zujuanProvinceNames.toSet().length, 8);
    });

    test('难度段：d1/d2/d3', () {
      expect(
        ZujuanDifficulty.values.map((value) => value.code).toList(),
        <String>['d1', 'd2', 'd3'],
      );
      expect(ZujuanDifficulty.easy.labelZh, '容易');
      expect(ZujuanDifficulty.medium.labelZh, '适中');
      expect(ZujuanDifficulty.hard.labelZh, '困难');
    });

    test('排序段：o0/o1/o2（最热推荐）', () {
      expect(
        ZujuanSort.values.map((value) => value.code).toList(),
        <String>['o0', 'o1', 'o2'],
      );
      expect(ZujuanSort.comprehensive.labelZh, '综合');
      expect(ZujuanSort.hot.labelZh, contains('最热'));
      expect(ZujuanSort.latest.labelZh, '最新');
    });
  });

  group('zujuanKnowledgePointUrl：只到知识点页、不带筛选', () {
    test('合法知识点 id：/<path>/zsd<id>/', () {
      expect(
        zujuanKnowledgePointUrl(
          subject: ZujuanSubject.math,
          knowledgePointId: '27925',
        ),
        'https://zujuan.xkw.com/gzsx/zsd27925/',
      );
    });

    test('知识点 id 两端空白先 trim', () {
      expect(
        zujuanKnowledgePointUrl(
          subject: ZujuanSubject.biology,
          knowledgePointId: ' 44886 ',
        ),
        'https://zujuan.xkw.com/gzsw/zsd44886/',
      );
    });

    test('缺知识点 id 回退该学科根节点（url-grammar.md:90-99）', () {
      expect(
        zujuanKnowledgePointUrl(subject: ZujuanSubject.physics),
        'https://zujuan.xkw.com/gzwl/zsd41934/',
      );
      expect(
        zujuanKnowledgePointUrl(
          subject: ZujuanSubject.chemistry,
          knowledgePointId: '   ',
        ),
        'https://zujuan.xkw.com/gzhx/zsd43452/',
      );
    });

    test('非法知识点 id 回退根节点，不拼坏路径', () {
      for (final raw in <String>['abc', '12a', '-1', '0', '0.5']) {
        expect(
          zujuanKnowledgePointUrl(
            subject: ZujuanSubject.chinese,
            knowledgePointId: raw,
          ),
          'https://zujuan.xkw.com/gzyw/zsd23177/',
          reason: '知识点 id $raw 应回退根节点',
        );
      }
    });

    test('前导零归一（027925 → 27925）', () {
      expect(
        zujuanKnowledgePointUrl(
          subject: ZujuanSubject.math,
          knowledgePointId: '027925',
        ),
        'https://zujuan.xkw.com/gzsx/zsd27925/',
      );
    });

    test('返回值永不为 null（有学科就拼得出）', () {
      expect(
        zujuanKnowledgePointUrl(
          subject: ZujuanSubject.chinese,
          knowledgePointId: null,
        ),
        isNotNull,
      );
    });
  });

  group('zujuanFiltersOf：筛选段顺序 d→qt→fl→x→y→a→g→te→o→p', () {
    test('空条件：空串', () {
      expect(zujuanFiltersOf(spec()), '');
    });

    test('难度段', () {
      expect(zujuanFiltersOf(spec(difficulty: ZujuanDifficulty.easy)), 'd1');
      expect(zujuanFiltersOf(spec(difficulty: ZujuanDifficulty.medium)), 'd2');
      expect(zujuanFiltersOf(spec(difficulty: ZujuanDifficulty.hard)), 'd3');
    });

    test('题型段只认本学科 id', () {
      expect(zujuanFiltersOf(spec(questionTypeId: 2701)), 'qt2701');
      expect(
        zujuanFiltersOf(
          spec(subject: ZujuanSubject.biology, questionTypeId: 310101),
        ),
        'qt310101',
      );
      // 2701 是数学的题型；传给生物必须忽略（跨科 id 站点静默 0 条）。
      expect(
        zujuanFiltersOf(
          spec(subject: ZujuanSubject.biology, questionTypeId: 2701),
        ),
        '',
      );
    });

    test('分类段 fl（典型题 4081）', () {
      expect(zujuanFiltersOf(spec(classificationId: 4081)), 'fl4081');
      expect(zujuanFiltersOf(spec(classificationId: 3)), 'fl3');
      expect(zujuanFiltersOf(spec(classificationId: 0)), '');
      expect(zujuanFiltersOf(spec(classificationId: -5)), '');
    });

    test('只看新题 x4', () {
      expect(zujuanFiltersOf(spec(onlyNew: true)), 'x4');
    });

    test('年份段：y2025 / y-1 / 防呆区间', () {
      expect(zujuanFiltersOf(spec(year: 2025)), 'y2025');
      expect(zujuanFiltersOf(spec(year: -1)), 'y-1');
      expect(zujuanFiltersOf(spec(year: 1899)), '');
      expect(zujuanFiltersOf(spec(year: 3000)), '');
    });

    test('省份段：6 位数字才拼', () {
      expect(zujuanFiltersOf(spec(provinceCode: '370000')), 'a370000');
      expect(zujuanFiltersOf(spec(provinceCode: ' 440000 ')), 'a440000');
      expect(zujuanFiltersOf(spec(provinceCode: '37000')), '');
      expect(zujuanFiltersOf(spec(provinceCode: '3700000')), '');
      expect(zujuanFiltersOf(spec(provinceCode: 'abcdef')), '');
    });

    test('年级段：g10/g11/g12', () {
      expect(zujuanFiltersOf(spec(grade: 10)), 'g10');
      expect(zujuanFiltersOf(spec(grade: 11)), 'g11');
      expect(zujuanFiltersOf(spec(grade: 12)), 'g12');
      expect(zujuanFiltersOf(spec(grade: 9)), '');
      expect(zujuanFiltersOf(spec(grade: 13)), '');
    });

    test('学期段：te1/te2', () {
      expect(zujuanFiltersOf(spec(semester: 1)), 'te1');
      expect(zujuanFiltersOf(spec(semester: 2)), 'te2');
      expect(zujuanFiltersOf(spec(semester: 3)), '');
    });

    test('排序段 o0/o1/o2', () {
      expect(
        zujuanFiltersOf(spec(sort: ZujuanSort.comprehensive)),
        'o0',
      );
      expect(zujuanFiltersOf(spec(sort: ZujuanSort.hot)), 'o1');
      expect(zujuanFiltersOf(spec(sort: ZujuanSort.latest)), 'o2');
    });

    test('页码段紧跟排序段、第 1 页省略（url-grammar.md:52-61）', () {
      expect(zujuanFiltersOf(spec(sort: ZujuanSort.hot, page: 2)), 'o1p2');
      expect(zujuanFiltersOf(spec(sort: ZujuanSort.hot, page: 1)), 'o1');
      expect(zujuanFiltersOf(spec(page: 0)), '');
      expect(zujuanFiltersOf(spec(page: -3)), '');
      expect(zujuanFiltersOf(spec(page: 2)), 'p2');
    });

    test('全条件顺序与文档一致（编译示例 compile.mjs:5）', () {
      final filters = zujuanFiltersOf(
        spec(
          difficulty: ZujuanDifficulty.medium,
          questionTypeId: 2703,
          classificationId: 4081,
          onlyNew: true,
          year: 2025,
          provinceCode: '370000',
          grade: 12,
          semester: 2,
          sort: ZujuanSort.hot,
          page: 2,
        ),
      );
      expect(filters, 'd2qt2703fl4081x4y2025a370000g12te2o1p2');
    });
  });

  group('zujuanFilteredSearchUrl：完整链接', () {
    test('没有筛选段：只到根节点页', () {
      expect(
        zujuanFilteredSearchUrl(spec()),
        'https://zujuan.xkw.com/gzsx/zsd27925/',
      );
    });

    test('六科无知识点都回退各自根节点', () {
      const expected = <ZujuanSubject, String>{
        ZujuanSubject.chinese: 'https://zujuan.xkw.com/gzyw/zsd23177/',
        ZujuanSubject.math: 'https://zujuan.xkw.com/gzsx/zsd27925/',
        ZujuanSubject.english: 'https://zujuan.xkw.com/gzyy/zsd29978/',
        ZujuanSubject.physics: 'https://zujuan.xkw.com/gzwl/zsd41934/',
        ZujuanSubject.chemistry: 'https://zujuan.xkw.com/gzhx/zsd43452/',
        ZujuanSubject.biology: 'https://zujuan.xkw.com/gzsw/zsd44886/',
      };
      for (final entry in expected.entries) {
        expect(
          zujuanFilteredSearchUrl(spec(subject: entry.key)),
          entry.value,
        );
      }
    });

    test('全条件链接（compile.mjs:45 模板 + 文档 §2 顺序）', () {
      final url = zujuanFilteredSearchUrl(
        spec(
          knowledgePointId: '27925',
          difficulty: ZujuanDifficulty.medium,
          questionTypeId: 2703,
          classificationId: 4081,
          onlyNew: true,
          year: 2025,
          provinceCode: '370000',
          grade: 12,
          semester: 2,
          sort: ZujuanSort.hot,
          page: 2,
        ),
      );
      expect(
        url,
        'https://zujuan.xkw.com/gzsx/zsd27925/'
        'd2qt2703fl4081x4y2025a370000g12te2o1p2/',
      );
    });

    test('与站点翻页按钮实例同段集合，顺序归一到文档 §2（d→qt）', () {
      final url = zujuanFilteredSearchUrl(
        spec(
          subject: ZujuanSubject.chemistry,
          knowledgePointId: '43452',
          difficulty: ZujuanDifficulty.medium,
          questionTypeId: 3011,
          sort: ZujuanSort.latest,
          page: 2,
        ),
      );
      // 文档 §2 末尾的站点按钮实例是点击顺序 /gzhx/zsd43452/qt3011d2o2p2/
      // （qt 在 d 前）；生成侧按文档 §2 + compile.mjs:5 的实测 data-href 顺序
      // 统一成 d2qt3011o2p2。
      expect(
        url,
        'https://zujuan.xkw.com/gzhx/zsd43452/d2qt3011o2p2/',
      );
    });

    test('文档里的正确页码样例：/gzyw/zsd23177/a370000o1p2/', () {
      final url = zujuanFilteredSearchUrl(
        spec(
          subject: ZujuanSubject.chinese,
          knowledgePointId: '23177',
          provinceCode: '370000',
          sort: ZujuanSort.hot,
          page: 2,
        ),
      );
      expect(url, 'https://zujuan.xkw.com/gzyw/zsd23177/a370000o1p2/');
      // 错误写法（/a370000o1/p2/）实测 404，绝不能生成。
      expect(url.contains('/o1/p2/'), isFalse);
      expect(url.contains('/a370000o1/p2/'), isFalse);
    });

    test('第 1 页省略 p 段（即使有其它筛选段）', () {
      final url = zujuanFilteredSearchUrl(
        spec(difficulty: ZujuanDifficulty.hard, page: 1),
      );
      expect(url, 'https://zujuan.xkw.com/gzsx/zsd27925/d3/');
      expect(url.contains('/p1'), isFalse);
    });

    test('页码段无其它筛选时也紧跟知识点段', () {
      expect(
        zujuanFilteredSearchUrl(spec(page: 2)),
        'https://zujuan.xkw.com/gzsx/zsd27925/p2/',
      );
    });

    test('非法知识点 id 回退根节点后仍带筛选段', () {
      final url = zujuanFilteredSearchUrl(
        spec(
            knowledgePointId: 'not-a-number',
            difficulty: ZujuanDifficulty.easy),
      );
      expect(url, 'https://zujuan.xkw.com/gzsx/zsd27925/d1/');
    });

    test('前导零知识点 id 归一后进链接', () {
      expect(
        zujuanFilteredSearchUrl(
          spec(
            subject: ZujuanSubject.biology,
            knowledgePointId: '044886',
            sort: ZujuanSort.hot,
          ),
        ),
        'https://zujuan.xkw.com/gzsw/zsd44886/o1/',
      );
    });

    test('链接总是以 / 结尾、主机后没有多余斜杠', () {
      final urls = <String>[
        zujuanFilteredSearchUrl(spec()),
        zujuanFilteredSearchUrl(spec(page: 3)),
        zujuanFilteredSearchUrl(
          spec(difficulty: ZujuanDifficulty.hard, sort: ZujuanSort.latest),
        ),
      ];
      for (final url in urls) {
        expect(url, startsWith('$zujuanBaseUrl/'));
        expect(url, endsWith('/'));
        final afterHost = url.substring(zujuanBaseUrl.length);
        expect(afterHost.contains('//'), isFalse);
      }
    });
  });

  group('ZujuanQuerySpec：默认值与值语义', () {
    test('默认值：page = 1，其余筛选可空/关闭', () {
      const query = ZujuanQuerySpec(subject: ZujuanSubject.math);
      expect(query.page, 1);
      expect(query.onlyNew, isFalse);
      expect(query.knowledgePointId, isNull);
      expect(query.difficulty, isNull);
      expect(query.questionTypeId, isNull);
      expect(query.classificationId, isNull);
      expect(query.year, isNull);
      expect(query.provinceCode, isNull);
      expect(query.grade, isNull);
      expect(query.semester, isNull);
      expect(query.sort, isNull);
    });

    test('值相等：同字段相等、hashCode 一致', () {
      final a = spec(difficulty: ZujuanDifficulty.hard, page: 2);
      final b = spec(difficulty: ZujuanDifficulty.hard, page: 2);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(
          a, isNot(equals(spec(difficulty: ZujuanDifficulty.hard, page: 3))));
      expect(
          a, isNot(equals(spec(difficulty: ZujuanDifficulty.easy, page: 2))));
    });

    test('toString 带学科与页码（排查用）', () {
      final text = spec(page: 2, difficulty: ZujuanDifficulty.hard).toString();
      expect(text, contains('subject: ZujuanSubject.math'));
      expect(text, contains('page: 2'));
      expect(text, contains('difficulty: ZujuanDifficulty.hard'));
    });
  });

  group('确定性', () {
    test('同输入两次调用逐字符相同', () {
      final query = spec(
        knowledgePointId: '41934',
        difficulty: ZujuanDifficulty.medium,
        onlyNew: true,
        provinceCode: '440000',
        sort: ZujuanSort.hot,
        page: 4,
      );
      expect(zujuanFilteredSearchUrl(query), zujuanFilteredSearchUrl(query));
      expect(zujuanFiltersOf(query), zujuanFiltersOf(query));
    });

    test('不同学科生成不同链接', () {
      final math = zujuanFilteredSearchUrl(spec());
      final physics = zujuanFilteredSearchUrl(
        spec(subject: ZujuanSubject.physics),
      );
      expect(math, isNot(physics));
      expect(math, contains('/gzsx/'));
      expect(physics, contains('/gzwl/'));
    });
  });
}
