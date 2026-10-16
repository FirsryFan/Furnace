import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/ingest/material_ingest.dart';
import 'package:furnace/domain/services/ingest/transcribe_run.dart';

/// 一条动作的 JSON（默认带 `at` 与 evidence，故意缺什么就删什么）。
Map<String, Object?> action(
  String kind, {
  Map<String, Object?>? extra,
  Map<String, Object?>? at,
  bool withAt = true,
  Object? evidence = const <String, Object?>{
    'source': 'page-1.jpg',
    'region': '第 3 题',
    'quote': 'x = 2',
  },
  Object? confidence = 0.8,
}) {
  return <String, Object?>{
    'kind': kind,
    if (withAt) 'at': at ?? const <String, Object?>{'model_hours': 480},
    if (evidence != null) 'evidence': evidence,
    if (confidence != null) 'confidence': confidence,
    ...?extra,
  };
}

Map<String, Object?> requestJson({
  Object? protocol = 'mindnet.run/1',
  Object? runId = 'run-1',
  List<Object?>? actions,
  Object? time = const <String, Object?>{'model_hours': 480},
  bool includeTime = true,
  Object? steps,
  bool includeSteps = false,
}) {
  return <String, Object?>{
    'protocol': protocol,
    'run_id': runId,
    if (includeTime) 'time': time,
    if (includeSteps) 'steps': steps,
    'actions': actions ??
        <Object?>[
          action('review',
              extra: <String, Object?>{'node': 'kp', 'outcome': 'correct'})
        ],
  };
}

MaterialRunRequest decodeRequest(Map<String, Object?> json) =>
    decodeRunRequest(json);

TranscribeReport review(
  Map<String, Object?> json, {
  Set<String> existingNodeIds = const <String>{'kp'},
  Set<String> existingEdgeIds = const <String>{},
}) =>
    reviewTranscribedRun(
      decodeRequest(json),
      existingNodeIds: existingNodeIds,
      existingEdgeIds: existingEdgeIds,
    );

void main() {
  group('decodeRunRequest', () {
    test('对象与 JSON 文本等价', () {
      final json = requestJson();
      final fromObject = decodeRunRequest(json);
      final fromText = decodeRunRequest(jsonEncode(json));
      expect(fromText.toJson(), fromObject.toJson());
      expect(fromText.runId, 'run-1');
      expect(fromText.actions, hasLength(1));
    });

    test('空串给的是"贴进来"的人话', () {
      expect(
        () => decodeRunRequest('   '),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('请求是空的'),
          ),
        ),
      );
    });

    test('不是 JSON 文本', () {
      expect(
        () => decodeRunRequest('{不是 json'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('不是合法的 JSON 文本'),
          ),
        ),
      );
    });

    test('别的类型', () {
      expect(
        () => decodeRunRequest(42),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('必须是对象或 JSON 文本'),
          ),
        ),
      );
    });
  });

  group('硬错（整份拒绝）', () {
    test('协议不对', () {
      final report = review(requestJson(protocol: 'mindnet.material/1'));
      expect(report.ok, isFalse);
      expect(report.errors.single, contains('protocol 必须是 "mindnet.run/1"'));
    });

    test('缺 run_id（幂等键）', () {
      final report = review(requestJson(runId: ''));
      expect(report.ok, isFalse);
      expect(report.errors.single, contains('缺少 run_id'));
    });

    test('actions 不是数组', () {
      final report = review(
        <String, Object?>{
          'protocol': 'mindnet.run/1',
          'run_id': 'run-1',
          'actions': 'nope',
        },
      );
      expect(report.ok, isFalse);
      expect(report.errors.single, contains('actions 必须是数组'));
    });

    test('steps 必须是 ≥0 的整数', () {
      for (final bad in <Object?>[1.5, -1, 'three']) {
        final report = review(requestJson(includeSteps: true, steps: bad));
        expect(report.ok, isFalse, reason: 'steps=$bad');
        expect(report.errors.single, contains('steps 必须是 ≥0 的整数'));
      }
      expect(review(requestJson(includeSteps: true, steps: 2)).ok, isTrue);
    });

    test('time 块可整体不写；写了才校验里面的值', () {
      final without = review(requestJson(includeTime: false));
      expect(without.ok, isTrue, reason: '每条动作自带 at 就够');
      final report = review(
        requestJson(time: const <String, Object?>{'model_hours': 'noon'}),
      );
      expect(report.ok, isFalse);
      expect(report.errors, contains('run 请求的 time.model_hours 必须是数字'));
    });

    test('time.wall 不可解析', () {
      final report = review(
        requestJson(
          time: const <String, Object?>{
            'model_hours': 480,
            'wall': '昨天下午',
          },
        ),
      );
      expect(report.ok, isFalse);
      expect(report.errors.single, contains('time.wall 不可解析'));
    });

    test('缺时间基', () {
      final report = review(
        requestJson(
          actions: <Object?>[
            action('review',
                withAt: false,
                extra: <String, Object?>{'node': 'kp', 'outcome': 'correct'}),
          ],
        ),
      );
      expect(report.ok, isFalse);
      expect(report.errors.single, contains('缺少时间基'));
      expect(report.errors.single, contains('elapsed_hours'));
    });

    test('未知 kind', () {
      final report = review(
        requestJson(actions: <Object?>[action('teleport')]),
      );
      expect(report.ok, isFalse);
      expect(report.errors.single, contains('kind 必须是'));
    });

    test('outcome 白名单', () {
      final report = review(
        requestJson(
          actions: <Object?>[
            action('review',
                extra: <String, Object?>{'node': 'kp', 'outcome': 'maybe'}),
          ],
        ),
      );
      expect(report.ok, isFalse);
      expect(
        report.errors.single,
        contains('outcome 必须是 correct / wrong / blank，实际 maybe'),
      );
    });

    test('同一节点两个矛盾结论 → 整份拒绝', () {
      final report = review(
        requestJson(
          actions: <Object?>[
            action('review',
                extra: <String, Object?>{'node': 'kp', 'outcome': 'wrong'}),
            action('review',
                extra: <String, Object?>{'node': 'kp', 'outcome': 'correct'}),
          ],
        ),
      );
      expect(report.ok, isFalse);
      expect(
        report.errors.single,
        contains('同时出现了 "wrong" 与 "correct"'),
      );
    });

    test('指向图里不存在的节点', () {
      final report = review(
        requestJson(
          actions: <Object?>[
            action('exposure', extra: <String, Object?>{'node': 'ghost'}),
          ],
        ),
      );
      expect(report.ok, isFalse);
      expect(report.errors.single, contains('指向不存在的节点 "ghost"'));
    });

    test('knowledge：幂等与影子图', () {
      final exists = review(
        requestJson(
          actions: <Object?>[
            action(
              'knowledge',
              extra: <String, Object?>{
                'node': const <String, Object?>{
                  'id': 'kp',
                  'type': 'knowledge'
                },
              },
            ),
          ],
        ),
      );
      expect(exists.ok, isFalse);
      expect(exists.errors.single, contains('已经存在'));

      // 同一份请求里先建节点、再引用它 —— 影子图必须认。
      final batch = review(
        requestJson(
          actions: <Object?>[
            action(
              'knowledge',
              extra: <String, Object?>{
                'node': const <String, Object?>{
                  'id': 'new',
                  'type': 'knowledge'
                },
              },
            ),
            action('review',
                extra: <String, Object?>{'node': 'new', 'outcome': 'correct'}),
          ],
        ),
      );
      expect(batch.ok, isTrue, reason: batch.errors.join('；'));

      final dangling = review(
        requestJson(
          actions: <Object?>[
            action(
              'knowledge',
              extra: <String, Object?>{
                'edge': const <String, Object?>{
                  'id': 'e1',
                  'from': 'kp',
                  'to': 'nowhere',
                  'ls': 0.6,
                },
              },
            ),
          ],
        ),
      );
      expect(dangling.ok, isFalse);
      expect(dangling.errors.single, contains('边终点 "nowhere" 不在图里'));
    });

    test('goal 必须给非空 targets，且都在图里', () {
      final empty = review(
        requestJson(
          actions: <Object?>[
            action('goal', extra: <String, Object?>{'targets': <String>[]}),
          ],
        ),
      );
      expect(empty.ok, isFalse);
      expect(empty.errors.single, contains('必须给非空的 targets'));

      final ghost = review(
        requestJson(
          actions: <Object?>[
            action('goal', extra: <String, Object?>{
              'targets': <String>['kp', 'ghost']
            }),
          ],
        ),
      );
      expect(ghost.ok, isFalse);
      expect(ghost.errors.single, contains('目标 "ghost" 不在图里'));
    });

    test('time 的 elapsed_hours 必须非负', () {
      final report = review(
        requestJson(
          actions: <Object?>[
            action('time',
                withAt: false, extra: <String, Object?>{'elapsed_hours': -2}),
          ],
        ),
      );
      expect(report.ok, isFalse);
      expect(report.errors.single, contains('elapsed_hours 必须是非负数'));
    });

    test('空 actions 合法', () {
      final report = review(requestJson(actions: <Object?>[]));
      expect(report.ok, isTrue);
      expect(report.actionCount, 0);
      expect(report.evidenceCount, 0);
      expect(report.previews, isEmpty);
    });
  });

  group('建议（不拦）', () {
    test('缺 evidence / 缺 confidence / 越界 confidence', () {
      final report = review(
        requestJson(
          actions: <Object?>[
            action('review',
                evidence: null,
                confidence: null,
                extra: <String, Object?>{'node': 'kp', 'outcome': 'correct'}),
            action('review',
                confidence: 1.5,
                extra: <String, Object?>{'node': 'kp', 'outcome': 'correct'}),
          ],
        ),
      );
      expect(report.ok, isTrue);
      expect(report.evidenceCount, 1);
      expect(report.warnings, hasLength(3));
      expect(report.warnings[0], contains('第 1 条（review）：没有 evidence'));
      expect(report.warnings[1], contains('没写 confidence'));
      expect(report.warnings[2], contains('confidence 必须是 0–1，实际 1.5'));
    });

    test('review 的 quote 不能空', () {
      final report = review(
        requestJson(
          actions: <Object?>[
            action(
              'review',
              evidence: const <String, Object?>{
                'source': 'page-1.jpg',
                'region': '第 3 题',
                'quote': '  ',
              },
              extra: <String, Object?>{'node': 'kp', 'outcome': 'correct'},
            ),
          ],
        ),
      );
      expect(report.ok, isTrue);
      expect(report.warnings.single, contains('evidence.quote 是空的'));
    });

    test('reviewed_solution 只对 wrong 有意义', () {
      final report = review(
        requestJson(
          actions: <Object?>[
            action('review', extra: <String, Object?>{
              'node': 'kp',
              'outcome': 'correct',
              'reviewed_solution': true,
            }),
          ],
        ),
      );
      expect(report.ok, isTrue);
      expect(report.warnings.single, contains('"看到订正"只对 wrong 有意义'));
    });

    test('全带 evidence + confidence 的好请求没有建议', () {
      final report = review(
        requestJson(
          actions: <Object?>[
            action('review',
                extra: <String, Object?>{'node': 'kp', 'outcome': 'correct'}),
            action('exposure', extra: <String, Object?>{'node': 'kp'}),
          ],
        ),
      );
      expect(report.ok, isTrue);
      expect(report.warnings, isEmpty);
      expect(report.evidenceCount, 2);
    });
  });

  group('previews（这份请求会做什么）', () {
    test('review 的机制路径：wrong + 看到订正走学习路径', () {
      final report = review(
        requestJson(
          actions: <Object?>[
            action('review', extra: <String, Object?>{
              'node': 'kp',
              'outcome': 'wrong',
              'reviewed_solution': true,
            }),
            action('review',
                extra: <String, Object?>{'node': 'kp2', 'outcome': 'blank'}),
          ],
        ),
        existingNodeIds: const <String>{'kp', 'kp2'},
      );
      expect(report.ok, isTrue, reason: report.errors.join('；'));
      expect(
        report.previews[0],
        '第 1 条 action [review] kp → retrieval_failure_feedback（S 由机制改）',
      );
      expect(report.previews[1], '第 2 条 action [review] kp2 → lapse（S 由机制改）');
    });

    test('五种动作的预告文案', () {
      final report = review(
        requestJson(
          actions: <Object?>[
            action('exposure', extra: <String, Object?>{'node': 'kp'}),
            action(
              'knowledge',
              extra: <String, Object?>{
                'node': const <String, Object?>{
                  'id': 'new',
                  'type': 'knowledge'
                },
              },
            ),
            action(
              'knowledge',
              extra: <String, Object?>{
                'edge': const <String, Object?>{
                  'id': 'e1',
                  'from': 'kp',
                  'to': 'new',
                  'ls': 0.6,
                },
              },
            ),
            action('goal', extra: <String, Object?>{
              'targets': <String>['kp', 'new']
            }),
            action('time',
                withAt: false, extra: <String, Object?>{'elapsed_hours': 3}),
          ],
        ),
      );
      expect(report.ok, isTrue, reason: report.errors.join('；'));
      expect(report.previews, <String>[
        '第 1 条 action [exposure] kp → reread（只算再读增益）',
        '第 2 条 action [knowledge] 新增节点 new',
        '第 3 条 action [knowledge] 新增边 kp → new',
        '第 4 条 action [goal] 目标 kp、new',
        '第 5 条 action [time] 时间前进 3.0 小时（同步所有节点的可提取度）',
      ]);
    });

    test('time 只给 at 时是"时间设为"', () {
      final report = review(
        requestJson(
          actions: <Object?>[action('time')],
        ),
      );
      expect(report.ok, isTrue, reason: report.errors.join('；'));
      expect(report.previews.single, '第 1 条 action [time] 时间设为 480.0');
    });
  });

  group('report.text / toJson', () {
    test('合法请求的打印对齐 io_check', () {
      final report = review(requestJson());
      expect(report.text, startsWith('✓ 请求合法：run-1 · 1 条动作'));
      expect(
        report.text,
        contains('出处：1/1 条带 evidence（建议全带 —— 出问题时才查得回去）'),
      );
      expect(report.toJson()['ok'], isTrue);
      expect(report.toJson()['run_id'], 'run-1');
      expect(report.toJson()['actions'], 1);
      expect(report.toJson()['evidence_count'], 1);
      expect(report.toJson()['previews'], hasLength(1));
    });

    test('不合法请求只报硬错，正文以 ✗ 开头', () {
      final report = review(requestJson(protocol: 'nope'));
      expect(report.text, startsWith('✗ 请求不合法：'));
      expect(report.text, isNot(contains('出处：')));
    });

    test('建议块只在不拦的问题上出现', () {
      final report = review(
        requestJson(
          actions: <Object?>[
            action('exposure',
                evidence: null, extra: <String, Object?>{'node': 'kp'}),
          ],
        ),
      );
      expect(report.text, contains('建议（不拦）：'));
      expect(report.text, contains('· 第 1 条（exposure）：没有 evidence'));
    });
  });

  group('buildTranscribePrompt', () {
    test('把图清单逐行写进提示词', () {
      final prompt = buildTranscribePrompt(
        inventory: const <TranscribeInventoryEntry>[
          (id: 'en::w::rely-on', name: 'rely on'),
          (id: 'en::s::1a2b3c4d', name: 'I relied on him.'),
        ],
        graphName: '我的英语图',
      );
      expect(prompt, contains('mindnet.run/1'));
      expect(prompt, contains('【图清单】'));
      expect(prompt, contains('图：我的英语图'));
      expect(prompt, contains('en::w::rely-on → rely on'));
      expect(prompt, contains('en::s::1a2b3c4d → I relied on him.'));
      expect(prompt, contains('reviewed_solution'));
      expect(prompt, contains('绝对不许'));
      expect(prompt, isNot(contains('清单是空的')));
    });

    test('空清单明说新知识点先走 knowledge', () {
      final prompt = buildTranscribePrompt(inventory: const []);
      expect(prompt, contains('清单是空的'));
      expect(prompt, contains('knowledge'));
    });

    test('补充说明追加在末尾', () {
      final prompt = buildTranscribePrompt(
        inventory: const [],
        note: '这是物理卷，公式要保留',
      );
      expect(prompt, contains('【补充说明】'));
      expect(prompt, contains('这是物理卷，公式要保留'));
    });
  });
}
