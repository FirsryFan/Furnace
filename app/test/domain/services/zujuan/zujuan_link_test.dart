import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/zujuan/zujuan_keywords.dart';
import 'package:furnace/domain/services/zujuan/zujuan_link.dart';

// 真实风格题干（物理/化学/语文各 2 例 + 生物 1 例含拉丁缩写 + 2 个负例）。
// Dart raw string：$ 与反斜杠原样保留，与候选子串断言逐字对应。
const String chemStem1 =
    r'某同学探究$Fe^{3+}$与$I^-$的反应，向$0.1\ \mathrm{mol/L}$的$FeCl_3$溶液中加入过量铁粉，充分反应后过滤。取滤液滴加KSCN溶液，观察颜色变化。〔加点〕结论〔/加点〕如下图所示：![装置图](https://img.xkw.com/dksih/QBM/editorImg/2024/abc.jpg)下列说法正确的是';
const String chemStem2 =
    r'工业上用$H_2$和$N_2$合成氨，反应在$500\ ^\circ\mathrm{C}$、$20\ \mathrm{MPa}$条件下进行。下列关于化学平衡移动的说法正确的是';
const String physStem1 =
    r'2024年某同学用如图甲所示的装置探究加速度与力的关系，小车质量$M$保持不变，砂桶和砂的总质量$m$远小于$M$。打点计时器所用交流电频率为$50\ \mathrm{Hz}$，得到一条点迹清晰的纸带。下列说法正确的是';
const String physStem2 =
    r'如图所示，质量为$m$的物体在水平面上向右运动，物体与水平面间的动摩擦因数为$\mu$。若物体受到一个水平向左的拉力$F$，则物体所受摩擦力的大小为';
const String chineseStem1 =
    r'阅读下面的文字，完成下列小题。戏剧的魅力在于它把一个时代的矛盾浓缩在方寸舞台之上，借人物的行动与台词把看不见的社会关系变成可以感知的冲突。〔波浪线〕舞台上的每一个动作都可能是伏笔〔/波浪线〕，而观众在剧场里经历的，正是这种被压缩了的时间。文中画波浪线的句子有何含意？';
const String chineseStem2 =
    r'材料一：近年来，数字技术深刻改变了人们的阅读方式。有学者认为，碎片化阅读削弱了深度思考的能力；也有学者指出，新的媒介形式正在催生新的表达。请结合材料，谈谈你的看法。';
const String bioStem1 =
    r'用$^{32}P$标记的DNA探针与待测样品进行杂交，通过检测放射性强度来判断基因表达水平。某同学测得菌液的OD值为0.8，下列叙述正确的是';
const String pureFormulaStem = r'$\frac{a}{b}+\sqrt{c}=0$';
const String shortStem = '下列正确的是';

const List<String> linkStems = <String>[
  chemStem1,
  chemStem2,
  physStem1,
  physStem2,
  chineseStem1,
  chineseStem2,
  bioStem1,
];

/// 组卷网链接/检索词候选（纯逻辑）的验收点：
///
///  * 文本搜题 URL：UTF-8 → **标准 base64** → 百分号编码（+ → %2B、/ → %2F、
///    = → %3D），intent 必须 question。期望值由 skill 源码
///    scripts/bridge.mjs:148-151 的真实表达式生成（node 实跑，非手算），
///    每个用例注释里给出中间 base64 便于复核；
///  * 题目/试卷详情页：/<bankid>q<id>.html、/<bankid>p<id>.html；缺 id /
///    非纯数字 → null（不猜；skill 侧同样要求 id 存在才拼，extract.mjs:156）；
///  * 检索词候选：入口在 zujuan_keywords.dart。用户 2026-10-25 反馈旧算法只给
///    5–14 字，新口径理科 15–30 字 / 文科 20–40 字且严格短于题干；本文件只钉
///    链接层的责任——band 透传、候选与 URL 配对、负例为空、确定性。
///    抽词算法与长度带细节见 zujuan_keywords_test.dart；
///  * 确定性：同输入同输出。
void main() {
  group('zujuanSearchUrl：文本搜题链接（编码证据 bridge.mjs:148-151）', () {
    test('纯中文：UTF-8 标准 base64（node: 光合作用 → 5YWJ5ZCI5L2c55So）', () {
      expect(
        zujuanSearchUrl('光合作用'),
        'https://zujuan.xkw.com/quessearch?keyword=5YWJ5ZCI5L2c55So'
        '&intent=question&b=0&urlSource=0',
      );
    });

    test('含空格：base64 尾部 = 被百分号编码为 %3D', () {
      // node: Buffer.from('光 合作用','utf8').toString('base64') === '5YWJIOWQiOS9nOeUqA=='
      expect(
        zujuanSearchUrl('光 合作用'),
        'https://zujuan.xkw.com/quessearch?keyword=5YWJIOWQiOS9nOeUqA%3D%3D'
        '&intent=question&b=0&urlSource=0',
      );
    });

    test('base64 含 +：编码为 %2B（不是 URL-safe base64）', () {
      // node: 基因突变 → 5Z+65Zug56qB5Y+Y
      expect(
        zujuanSearchUrl('基因突变'),
        'https://zujuan.xkw.com/quessearch?keyword=5Z%2B65Zug56qB5Y%2BY'
        '&intent=question&b=0&urlSource=0',
      );
    });

    test('base64 同时含 + 与 /：%2B / %2F 各就各位（不换成 - 与 _）', () {
      // node: 匀变速直线运动 → 5YyA5Y+Y6YCf55u057q/6L+Q5Yqo
      expect(
        zujuanSearchUrl('匀变速直线运动'),
        'https://zujuan.xkw.com/quessearch?keyword='
        '5YyA5Y%2BY6YCf55u057q%2F6L%2BQ5Yqo'
        '&intent=question&b=0&urlSource=0',
      );
    });

    test('拉丁字母+数字混排：pH / DNA扩增 原样参与 base64', () {
      // node: pH → cEg=；DNA扩增 → RE5B5omp5aKe
      expect(
        zujuanSearchUrl('pH'),
        'https://zujuan.xkw.com/quessearch?keyword=cEg%3D'
        '&intent=question&b=0&urlSource=0',
      );
      expect(
        zujuanSearchUrl('DNA扩增'),
        'https://zujuan.xkw.com/quessearch?keyword=RE5B5omp5aKe'
        '&intent=question&b=0&urlSource=0',
      );
    });

    test('intent 必须是 question，b/urlSource 固定（SKILL.md:256）', () {
      final url = Uri.parse(zujuanSearchUrl('下列叙述错误的是'));
      expect(url.scheme, 'https');
      expect(url.host, 'zujuan.xkw.com');
      expect(url.path, '/quessearch');
      expect(url.queryParameters['intent'], 'question');
      expect(url.queryParameters['b'], '0');
      expect(url.queryParameters['urlSource'], '0');
    });
  });

  group('zujuanQuestionDetailUrl：题目详情页（extract.mjs:156）', () {
    test('合法纯数字 id 拼出绝对链接', () {
      expect(
        zujuanQuestionDetailUrl(bankId: '10', questionId: '35583902'),
        'https://zujuan.xkw.com/10q35583902.html',
      );
      expect(
        zujuanQuestionDetailUrl(bankId: '11', questionId: '35414092'),
        'https://zujuan.xkw.com/11q35414092.html',
      );
    });

    test('缺任一 id → null（不猜，skill 侧同样要求 id 存在）', () {
      expect(zujuanQuestionDetailUrl(questionId: '35583902'), isNull);
      expect(zujuanQuestionDetailUrl(bankId: '10'), isNull);
      expect(zujuanQuestionDetailUrl(), isNull);
    });

    test('空串/纯空白/非纯数字 → null', () {
      expect(zujuanQuestionDetailUrl(bankId: '', questionId: '1'), isNull);
      expect(zujuanQuestionDetailUrl(bankId: '  ', questionId: '  '), isNull);
      expect(zujuanQuestionDetailUrl(bankId: 'abc', questionId: '1'), isNull);
      expect(zujuanQuestionDetailUrl(bankId: '10', questionId: '35a'), isNull);
      expect(zujuanQuestionDetailUrl(bankId: '10', questionId: '-1'), isNull);
    });

    test('首尾空白先 trim 再用（容错，但仍要求纯数字）', () {
      expect(
        zujuanQuestionDetailUrl(bankId: ' 10 ', questionId: ' 35583902 '),
        'https://zujuan.xkw.com/10q35583902.html',
      );
    });
  });

  group('zujuanPaperDetailUrl：试卷详情页（paper.mjs:10、SKILL.md:140）', () {
    test('合法 id 拼出绝对链接（实例 /10p3076310.html）', () {
      expect(
        zujuanPaperDetailUrl(paperId: '3076310', bankId: '10'),
        'https://zujuan.xkw.com/10p3076310.html',
      );
    });

    test('缺 paperId → null；缺 bankId 也 → null（skill 无默认 bankid，不猜）', () {
      expect(zujuanPaperDetailUrl(bankId: '10'), isNull);
      expect(zujuanPaperDetailUrl(paperId: '3076310'), isNull);
      expect(zujuanPaperDetailUrl(), isNull);
    });

    test('空串/非纯数字 id → null', () {
      expect(zujuanPaperDetailUrl(paperId: '', bankId: '10'), isNull);
      expect(zujuanPaperDetailUrl(paperId: 'p3076310', bankId: '10'), isNull);
      expect(zujuanPaperDetailUrl(paperId: '3076310', bankId: '十'), isNull);
    });
  });

  group('zujuanKeywordCandidates：band 透传与链接层不变量', () {
    test('默认 band = science：与显式 science、与 extractZujuanKeywords 一致', () {
      for (final stem in linkStems) {
        expect(
          zujuanKeywordCandidates(stem),
          zujuanKeywordCandidates(stem, band: ZujuanSubjectBand.science),
          reason: stem,
        );
        expect(zujuanKeywordCandidates(stem), extractZujuanKeywords(stem),
            reason: stem);
      }
    });

    test('旧题干：候选仍是清洗后文本层真实子串、去重、互不为子串、条数 ≤ maxCandidates', () {
      final banned = RegExp(
        r'[\s$〔〕]|!\[|\]\(|http|，|。|、|；|：|？|！|（|）|\(|\)|《|》|【|】|,',
      );
      for (final stem in linkStems) {
        final candidates = zujuanKeywordCandidates(stem);
        expect(candidates.length, inInclusiveRange(1, 8), reason: stem);
        expect(candidates.toSet().length, candidates.length, reason: stem);
        for (final candidate in candidates) {
          expect(
            candidate.length,
            inInclusiveRange(4, kZujuanScienceMaxLength),
            reason: candidate,
          );
          expect(stem.contains(candidate), isTrue, reason: candidate);
          expect(
            banned.hasMatch(candidate),
            isFalse,
            reason: '候选 $candidate 含跨句读/公式/空白字符',
          );
        }
        for (var i = 0; i < candidates.length; i++) {
          for (var j = i + 1; j < candidates.length; j++) {
            final first = candidates[i];
            final second = candidates[j];
            expect(
              first.contains(second) || second.contains(first),
              isFalse,
              reason: '互为子串: $first / $second',
            );
          }
        }
      }
    });

    test('band: humanities 透传：与 extractZujuanKeywords 同 band 一致，每条严格短于题干', () {
      final candidates = zujuanKeywordCandidates(
        chineseStem1,
        band: ZujuanSubjectBand.humanities,
      );
      expect(
        candidates,
        extractZujuanKeywords(chineseStem1, band: ZujuanSubjectBand.humanities),
      );
      expect(candidates, isNotEmpty);
      for (final candidate in candidates) {
        expect(
          candidate.length,
          lessThan(chineseStem1.trim().length),
          reason: candidate,
        );
        expect(
          candidate.length,
          lessThanOrEqualTo(kZujuanHumanitiesMaxLength),
          reason: candidate,
        );
      }
      // 该题干首句够长：文科口径下至少有一条进入 20–40 区间。
      expect(
        candidates.any(
          (candidate) => candidate.length >= kZujuanHumanitiesMinLength,
        ),
        isTrue,
      );
    });

    test('maxCandidates 0/1/2 生效（截断在排序去重之后）', () {
      final full = zujuanKeywordCandidates(chemStem1);
      expect(full.length, greaterThanOrEqualTo(2));
      expect(zujuanKeywordCandidates(chemStem1, maxCandidates: 0), isEmpty);
      expect(zujuanKeywordCandidates(chemStem1, maxCandidates: -3), isEmpty);
      expect(
        zujuanKeywordCandidates(chemStem1, maxCandidates: 1),
        <String>[full.first],
      );
      expect(
        zujuanKeywordCandidates(chemStem1, maxCandidates: 2),
        full.take(2).toList(),
      );
    });

    test('负例：纯公式/空串/纯空白 → 空；短套话题干按新口径回退为非空', () {
      expect(zujuanKeywordCandidates(pureFormulaStem), isEmpty);
      expect(zujuanKeywordCandidates(''), isEmpty);
      expect(zujuanKeywordCandidates('   '), isEmpty);
      final short = zujuanKeywordCandidates(shortStem);
      expect(short, isNotEmpty);
      for (final candidate in short) {
        expect(
          candidate.length,
          inInclusiveRange(4, shortStem.length),
          reason: candidate,
        );
      }
    });

    test('确定性：同输入连续两次结果一致', () {
      for (final stem in linkStems) {
        expect(zujuanKeywordCandidates(stem), zujuanKeywordCandidates(stem),
            reason: stem);
        expect(zujuanSearchCandidates(stem), zujuanSearchCandidates(stem),
            reason: stem);
      }
    });
  });

  group('zujuanSearchCandidates：检索词 + URL 配对', () {
    test('每条候选的 url 就是 zujuanSearchUrl(keyword)，顺序与关键词一致', () {
      final keywords = zujuanKeywordCandidates(chemStem1);
      final candidates = zujuanSearchCandidates(chemStem1);
      expect(
          candidates.map((candidate) => candidate.keyword).toList(), keywords);
      for (final candidate in candidates) {
        expect(candidate.url, zujuanSearchUrl(candidate.keyword));
        expect(candidate.url, contains('intent=question'));
      }
    });

    test('band: humanities 透传，且 url 的 keyword 参数能解码回候选原文', () {
      final candidates = zujuanSearchCandidates(
        chineseStem1,
        band: ZujuanSubjectBand.humanities,
      );
      expect(
        candidates.map((candidate) => candidate.keyword).toList(),
        zujuanKeywordCandidates(
          chineseStem1,
          band: ZujuanSubjectBand.humanities,
        ),
      );
      expect(candidates, isNotEmpty);
      for (final candidate in candidates) {
        final encoded = Uri.parse(candidate.url).queryParameters['keyword'];
        expect(encoded, isNotNull, reason: candidate.keyword);
        expect(utf8.decode(base64Decode(encoded!)), candidate.keyword);
      }
    });

    test('简单题干：单条候选（光合作用）', () {
      final candidates = zujuanSearchCandidates('光合作用');
      expect(candidates.length, 1);
      expect(candidates.single.keyword, '光合作用');
      expect(candidates.single.url, zujuanSearchUrl('光合作用'));
      expect(candidates.single.toJson(), <String, String>{
        'keyword': '光合作用',
        'url': zujuanSearchUrl('光合作用'),
      });
    });

    test('空题干 / 纯公式 → 空候选（UI 应据此隐藏复制入口）', () {
      expect(zujuanSearchCandidates(''), isEmpty);
      expect(zujuanSearchCandidates(pureFormulaStem), isEmpty);
    });
  });
}
