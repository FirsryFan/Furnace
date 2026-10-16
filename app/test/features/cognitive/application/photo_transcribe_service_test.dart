/// 「照片 → run/1」这一段（`docs/MINDNET_ROADMAP.md` §2-C ③ 的那一半）的验收。
///
/// 这一组测试盯着的是**失败也要说人话**：没模型 / 图不能用 / 模型没走完 /
/// 回话读不成请求 —— 四态全部返回结果对象、不抛异常，而且**没到发图那一步就
/// 一个请求都不发**。模型用 `FakeModelAdapter`，照片用 `dart:ui` 现画
/// （`test/features/ai/image_fixture.dart`），都不需要网络。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/ingest/transcribe_run.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/vision_payload.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/cognitive/application/photo_transcribe_service.dart';

import '../../ai/image_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 一份合法的 `mindnet.run/1`（默认那条 review 指向图里已有的 `kp`）。
  Map<String, Object?> runJson({
    Object? protocol = 'mindnet.run/1',
    Object? confidence = 0.8,
    Object? evidence = const <String, Object?>{
      'source': 'page-1.jpg',
      'region': '第 3 题',
      'quote': 'x = 2',
    },
  }) =>
      <String, Object?>{
        'protocol': protocol,
        'run_id': 'run-1',
        'time': const <String, Object?>{'model_hours': 480},
        'actions': <Object?>[
          <String, Object?>{
            'kind': 'review',
            'at': const <String, Object?>{'model_hours': 480},
            if (evidence != null) 'evidence': evidence,
            if (confidence != null) 'confidence': confidence,
            'node': 'kp',
            'outcome': 'correct',
          },
        ],
      };

  Future<Uint8List> photo() => paintPng(24, 12);

  const inventory = <TranscribeInventoryEntry>[
    (id: 'kp', name: 'I relied on him.'),
  ];

  Future<PhotoTranscribeResult> transcribe(
    ModelAdapter? adapter, {
    Uint8List? image,
    VisionImageEncoder encoder = const VisionImageEncoder(),
    Set<String> existingNodeIds = const <String>{'kp'},
  }) async =>
      transcribePhoto(
        adapter: adapter,
        image: image ?? await photo(),
        inventory: inventory,
        existingNodeIds: existingNodeIds,
        encoder: encoder,
      );

  test('没配模型：照片发不出去，也不假装读到了', () async {
    final result = await transcribe(null);

    final failure = result as PhotoTranscribeFailure;
    expect(failure.problem, PhotoTranscribeProblem.notConfigured);
    expect(failure.message, contains('设置'), reason: '要告诉用户去哪儿配模型');
    expect(failure.rawText, isNull);
  });

  test('图读不了：说人话，不抛异常，也不发请求', () async {
    final adapter = FakeModelAdapter(const <List<ModelEvent>>[]);
    final result = await transcribe(
      adapter,
      image: Uint8List.fromList(<int>[1, 2, 3, 4]),
    );

    expect(
      (result as PhotoTranscribeFailure).problem,
      PhotoTranscribeProblem.imageUnreadable,
    );
    expect(adapter.requests, isEmpty, reason: '图都没过编码，不该有请求出去');
  });

  test('压过之后还是超过上限：不把半张图发出去', () async {
    final adapter = FakeModelAdapter(const <List<ModelEvent>>[]);
    final result = await transcribe(
      adapter,
      image: await paintPng(64, 64),
      encoder: const VisionImageEncoder(longSide: 16, maxBytes: 64),
    );

    expect(
      (result as PhotoTranscribeFailure).problem,
      PhotoTranscribeProblem.imageTooLarge,
    );
    expect(adapter.requests, isEmpty);
  });

  test('照片 + 提示词一起发出去，回话读成一份请求', () async {
    final fenced = '好的，这是结果：\n```json\n${jsonEncode(runJson())}\n```';
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      FakeModelAdapter.answer(fenced),
    ]);

    final result = await transcribe(adapter);

    final ok = result as PhotoTranscribeReport;
    expect(ok.report.ok, isTrue, reason: ok.report.errors.join('；'));
    expect(ok.report.runId, 'run-1');
    expect(ok.report.actionCount, 1);
    expect(ok.rawText, fenced.trim(), reason: '模型原话留全文，用户能自己核对');
    expect(ok.width, 24);
    expect(ok.height, 12);
    // 报告里带着解码出来的原件：界面要拿它去试跑，不该把原话再解一遍。
    expect(ok.request.runId, 'run-1');
    expect(ok.request.actions, hasLength(1));

    final request = adapter.requests.single;
    expect(request.tools, isEmpty, reason: '这一步只让模型说话，不给它工具');
    final message = request.messages.single;
    expect(
      message.content,
      contains('kp → I relied on him.'),
      reason: '图清单要填进提示词（不许发明节点 id）',
    );
    expect(message.images, hasLength(1));
    expect(message.images.single.mime, 'image/png');
    expect(message.images.single.base64, isNotEmpty);
  });

  test('模型这一轮没走完：失败原因照实说，半句回话也留着', () async {
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      <ModelEvent>[
        const ModelTextDelta('我看看这张图'),
        const ModelFailure('HTTP 500'),
      ],
    ]);

    final failure = await transcribe(adapter) as PhotoTranscribeFailure;
    expect(failure.problem, PhotoTranscribeProblem.modelFailed);
    expect(failure.message, contains('HTTP 500'));
    expect(failure.rawText, '我看看这张图');
  });

  test('模型什么都没写', () async {
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      FakeModelAdapter.answer('   '),
    ]);

    final failure = await transcribe(adapter) as PhotoTranscribeFailure;
    expect(failure.problem, PhotoTranscribeProblem.emptyAnswer);
    expect(failure.rawText, isNull);
  });

  test('回话里没有能读的对象：原话留着，错误用解码器那句人话', () async {
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      FakeModelAdapter.answer('这张照片我看不清。'),
    ]);

    final failure = await transcribe(adapter) as PhotoTranscribeFailure;
    expect(failure.problem, PhotoTranscribeProblem.unreadableAnswer);
    expect(failure.rawText, '这张照片我看不清。');
    expect(failure.message, contains('读不成一份 run 请求'));
  });

  test('读出来了但请求不合法：ok 是 false，硬错照实列出来', () async {
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      FakeModelAdapter.answer(jsonEncode(runJson(protocol: 'mindnet.run/2'))),
    ]);

    final ok = await transcribe(adapter) as PhotoTranscribeReport;
    expect(ok.report.ok, isFalse);
    expect(ok.report.errors, isNotEmpty);
  });

  test('建议也一起带出来：没写 confidence / 没有 evidence', () async {
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      FakeModelAdapter.answer(
        jsonEncode(runJson(confidence: null, evidence: null)),
      ),
    ]);

    final ok = await transcribe(adapter) as PhotoTranscribeReport;
    expect(ok.report.ok, isTrue);
    expect(
      ok.report.warnings.join('\n'),
      allOf(contains('没写 confidence'), contains('没有 evidence')),
    );
  });

  group('extractJsonObject', () {
    test('整段就是对象：原样', () {
      expect(extractJsonObject('{"a": 1}'), '{"a": 1}');
    });

    test('围栏 + 前后说明：取出那个对象', () {
      expect(
        extractJsonObject('结果如下：\n```json\n{"a": {"b": 2}}\n```\n完。'),
        '{"a": {"b": 2}}',
      );
    });

    test('一个花括号都没有：原样交给解码器去说人话', () {
      expect(extractJsonObject('我看不清'), '我看不清');
    });
  });
}
