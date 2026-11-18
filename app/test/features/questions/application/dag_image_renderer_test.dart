/// DAG 图片渲染器的单元测试（2026-11-19）。
///
/// 钉住四件事：
///  1. 真的产出一张 PNG（签名、尺寸、步数/箭头计数）；
///  2. 图的高度随步骤数增长——不是"把文字画进白底"的固定高度图；
///  3. 空链抛可读异常，不生成只有标题的白图；
///  4. 内置字体不可用时仍能出图（退回默认字体），字体问题不升级成整图失败。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/reasoning/capability_action.dart';
import 'package:furnace/domain/services/reasoning/reasoning_prompt.dart';
import 'package:furnace/features/questions/application/dag_image_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('真的画出 PNG：节点=步数、箭头=步数-1', () async {
    final result = await DagImageRenderer().render(
      _chain(stepCount: 4),
      title: '思维 DAG',
    );

    expect(result.isPng, isTrue, reason: '输出必须是 PNG');
    expect(result.width, DagImageRenderer.imageWidth.round());
    expect(result.height, greaterThan(300));
    expect(result.nodeCount, 4);
    expect(result.edgeCount, 3);
    expect(result.bytes.length, greaterThan(10 * 1024),
        reason: '包含节点/箭头/文字的真实图片不会只有几 KB');
  });

  test('图随步骤数变高：有分层节点，不是"整段文字 + 白底"', () async {
    final one = await DagImageRenderer().render(_chain(stepCount: 1));
    final five = await DagImageRenderer().render(_chain(stepCount: 5));

    expect(five.height, greaterThan(one.height + 200),
        reason: '每一步都应该占一层，图高随步数增长');
    expect(five.bytes.length, greaterThan(one.bytes.length));
  });

  test('空链：抛可读原因，不生成只有标题的白图', () async {
    await expectLater(
      DagImageRenderer().render(const ParsedChain(summary: '', steps: [])),
      throwsA(
        isA<DagImageRenderException>().having(
          (error) => error.message,
          'message',
          contains('没有步骤'),
        ),
      ),
    );
  });

  test('内置字体不可用：仍能生成图片（退回默认字体），不把字体问题变成整图失败',
      () async {
    final renderer = DagImageRenderer(
      loadAsset: (path) async => throw StateError('asset missing: $path'),
    );

    final result = await renderer.render(_chain(stepCount: 2));

    expect(result.isPng, isTrue);
    expect(result.nodeCount, 2);
    expect(result.edgeCount, 1);
  });
}

/// 造一条步数可控、动作都在内置词表里的链。
ParsedChain _chain({required int stepCount}) {
  const actionKeys = <String>[
    'first_principles',
    'case_split',
    'sanity_check',
    'reduction',
    'analogy_transfer',
  ];
  return ParsedChain(
    summary: '先用换元法把条件整理成方程，再按动作逐步推进，最后回代检验。',
    steps: <ParsedStep>[
      for (var i = 0; i < stepCount; i++)
        ParsedStep(
          index: i + 1,
          goal: '第 ${i + 1} 步：把这一步要做的事情写清楚，长度足够触发换行，'
              '让节点里真的有正文而不是一行占位。',
          actionType: actionKeys[i % actionKeys.length],
          action: CapabilityAction.byKey(actionKeys[i % actionKeys.length]),
          justification: '',
          checkMethod: '',
          stuckRisk: (i % 3) * 0.4,
          knowledgeHints: const <String>[],
        ),
    ],
  );
}
