// 算法竞赛学科（algorithm）的接线守卫测试。
//
// 覆盖四处会按 subjectKey 分派/筛选的地方：
//  - CapabilityAction 学科轨道词表（收题页/能力词表/组卷过滤都读它）；
//  - 题名建议的学科中文名；
//  - .tqb 题目记录按 algorithm 筛选；
//  - .tqb 编解码往返（算法题是 markdown + 难度值，不能因为没有配图被卡住）。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/package/question_pack_codec.dart';
import 'package:furnace/domain/services/package/question_pack_manifest.dart';
import 'package:furnace/domain/services/package/question_pack_record.dart';
import 'package:furnace/domain/services/package/question_pack_selection.dart';
import 'package:furnace/domain/services/questions/question_title_suggestion.dart';
import 'package:furnace/domain/services/reasoning/capability_action.dart';

void main() {
  group('学科轨道', () {
    test('algorithm 已登记，且中文名是「算法竞赛」', () {
      expect(CapabilityAction.subjectKeys, contains('algorithm'));
      expect(CapabilityAction.subjectLabelsZh['algorithm'], '算法竞赛');
      // 文化课轨道不能被这次新增挤掉。
      for (final key in <String>[
        'math',
        'physics',
        'chemistry',
        'biology',
        'chinese',
        'english',
      ]) {
        // english 不在 CapabilityAction 轨道里（历史口径），但题库/组卷仍用它。
        if (key == 'english') continue;
        expect(CapabilityAction.subjectKeys, contains(key));
      }
    });
  });

  group('题名建议', () {
    test('algorithm 的题名会带「算法竞赛 · 」前缀', () {
      final suggestion = suggestQuestionTitle(
        stem: 'P2467 [SDOI2010] 地精部落\n\n题目描述……',
        subjectKey: 'algorithm',
      );
      expect(suggestion.subjectLabel, '算法竞赛');
      expect(suggestion.title, startsWith('算法竞赛 · '));
    });
  });

  group('题库筛选', () {
    QuestionPackRecord record({String subject = 'algorithm'}) =>
        QuestionPackRecord(
          stem: 'P2467 [SDOI2010] 地精部落',
          answer: '见解析',
          solution: '参考实现已通过样例。',
          subjectKey: subject,
          questionType: 'solution',
          difficulty: 8,
          difficultySource: 'manual',
          sourceLabel: '洛谷 P2467（提高+/省选-）',
          sourceUrl: 'https://www.luogu.com.cn/problem/P2467',
          textFormat: 'markdown',
          capability: const <String>['A4'],
          tagPaths: const <String>['算法竞赛', '算法竞赛/专题/动态规划'],
        );

    test('按 algorithm 学科筛选能命中，按 math 不命中', () {
      expect(
        questionPackRecordMatchesSelection(
          record(),
          const QuestionPackSelection(subjectKeys: <String>{'algorithm'}),
        ),
        isTrue,
      );
      expect(
        questionPackRecordMatchesSelection(
          record(),
          const QuestionPackSelection(subjectKeys: <String>{'math'}),
        ),
        isFalse,
      );
    });

    test('按标签路径筛选能命中算法竞赛专题', () {
      expect(
        questionPackRecordMatchesSelection(
          record(),
          const QuestionPackSelection(tagPaths: <String>{'算法竞赛/专题/动态规划'}),
        ),
        isTrue,
      );
    });
  });

  group('.tqb 编解码', () {
    test('algorithm 记录能编码/解码往返，题型与 markdown 格式保留', () {
      const source = QuestionPackRecord(
        stem: 'P2467 [SDOI2010] 地精部落\n\n## 题目描述\n求交替排列数。',
        answer: '见解析',
        solution: 'dp[i][j] = dp[i][j-1] + dp[i-1][i-j]。',
        subjectKey: 'algorithm',
        questionType: 'solution',
        difficulty: 8,
        difficultySource: 'manual',
        sourceLabel: '洛谷 P2467（提高+/省选-）',
        sourceUrl: 'https://www.luogu.com.cn/problem/P2467',
        textFormat: 'markdown',
        capability: <String>['A4', 'A5'],
        tagPaths: <String>['算法竞赛', '算法竞赛/专题/动态规划'],
      );
      final bytes = encodeQuestionPackArchive(
        manifest: QuestionPackManifest(
          exportedAt: DateTime.utc(2026, 11, 6),
          appVersion: 'test',
          questionCount: 1,
          mediaCount: 0,
          generatedBy: 'algorithm_subject_test',
        ),
        records: <QuestionPackRecord>[source],
        mediaBytes: const <String, Uint8List>{},
      );
      final archive = decodeQuestionPackArchive(bytes);
      expect(archive.records, hasLength(1));
      final decoded = archive.records.single;
      expect(decoded.subjectKey, 'algorithm');
      expect(decoded.textFormat, 'markdown');
      expect(decoded.difficulty, 8);
      expect(decoded.capability, orderedEquals(<String>['A4', 'A5']));
      expect(
        decoded.tagPaths,
        containsAll(<String>['算法竞赛', '算法竞赛/专题/动态规划']),
      );
    });
  });
}
