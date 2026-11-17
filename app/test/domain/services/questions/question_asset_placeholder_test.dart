import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_asset_placeholder.dart';

/// 整卷源格式 `{{asset:NAME}}` 占位的识别与显示口径（纯逻辑）。
///
/// 真实来源：`E:\Workspaces\agent-control\10-projects\agent-control-plane\exam-papers\`
/// 下的 `paper.json` 把图写成 `{{asset:q14_img01.png}}`；历史上一批题原样入库，
/// 题库卡片把占位符当正文显示（2024 英语卷 45 道题）。这些测试钉住两件事：
///  * 有同名附件 → 换成 `［图N］`（交给既有图文混排管线）；
///  * 没有附件 / `.wmf` → 换成明确的「图片缺失」文字，**绝不把原始占位符留给用户**。
void main() {
  group('识别', () {
    test('识别单个占位并给出文件名', () {
      const text = '已知{{asset:q02_img01.png}}成立';
      final refs = parseQuestionAssetReferences(text);
      expect(refs, hasLength(1));
      expect(refs.single.name, 'q02_img01.png');
      // 占位从「已知」之后开始，到两层花括号结束（含 `}}`）。
      expect(refs.single.start, 2);
      expect(refs.single.end, text.indexOf('}}') + 2);
      expect(refs.single.ownLine, isFalse);
    });

    test('允许花括号/冒号/名字两侧空白', () {
      final refs = parseQuestionAssetReferences('{{ asset : q02_img01.png }}');
      expect(refs.single.name, 'q02_img01.png');
    });

    test('连续多个占位按出现顺序解析', () {
      final refs = parseQuestionAssetReferences(
        '{{asset:q14_img01.wmf}}{{asset:q14_img02.png}}',
      );
      expect(refs.map((r) => r.name), <String>['q14_img01.wmf', 'q14_img02.png']);
      expect(refs.first.isWmf, isTrue);
      expect(refs.last.isWmf, isFalse);
    });

    test('独立成行的占位标 ownLine', () {
      final refs = parseQuestionAssetReferences('题干\n{{asset:a.png}}\n后文');
      expect(refs.single.ownLine, isTrue);
    });

    test('不是 asset 形状的模板保持不认', () {
      expect(containsQuestionAssetPlaceholder('{{other:a.png}}'), isFalse);
      expect(containsQuestionAssetPlaceholder('{asset:a.png}'), isFalse);
      expect(containsQuestionAssetPlaceholder(''), isFalse);
    });

    test('wmf 给出同名 png 的转换候选', () {
      final refs = parseQuestionAssetReferences('{{asset:q1_img01.wmf}}');
      expect(refs.single.convertedPngName, 'q1_img01.png');
      final pngs = parseQuestionAssetReferences('{{asset:q1_img01.png}}');
      expect(pngs.single.convertedPngName, isNull);
    });
  });

  group('替换为可渲染文本', () {
    test('同名附件 → ［图N］（N 为附件下标 + 1）', () {
      final result = renderQuestionAssetPlaceholders(
        '已知{{asset:q02_img01.png}}成立',
        attachmentNames: const <String>['a.png', 'q02_img01.png'],
      );
      expect(result.text, '已知［图2］成立');
      expect(result.resolved, 1);
      expect(result.missing, 0);
      expect(result.wmfUnsupported, 0);
    });

    test('没有附件 → 明确的图片缺失提示', () {
      final result = renderQuestionAssetPlaceholders(
        '如图{{asset:q14_img01.png}}所示',
        attachmentNames: const <String>[],
      );
      expect(result.text, '如图［图片缺失：q14_img01.png］所示');
      expect(result.text.contains('{{asset:'), isFalse);
      expect(result.missing, 1);
    });

    test('wmf 没有转换图 → 标注 WMF 格式不支持', () {
      final result = renderQuestionAssetPlaceholders(
        '{{asset:q14_img01.wmf}}',
        attachmentNames: const <String>[],
      );
      expect(result.text, '［图片缺失：q14_img01.wmf（WMF 格式不支持）］');
      expect(result.wmfUnsupported, 1);
      expect(result.missing, 0);
    });

    test('wmf 有同名 png（导入时转换过）→ 用转换后的图', () {
      final result = renderQuestionAssetPlaceholders(
        '{{asset:q14_img01.wmf}}',
        attachmentNames: const <String>['q14_img01.png'],
      );
      expect(result.text, '［图1］');
      expect(result.resolved, 1);
      expect(result.wmfUnsupported, 0);
    });

    test('附件清单还没读出来（pending）→ 中性［图］，不闪“缺失”', () {
      final result = renderQuestionAssetPlaceholders(
        '{{asset:q02_img01.png}}',
        attachmentNames: const <String>[],
        pending: true,
      );
      expect(result.text, '［图］');
      expect(result.hasMissingMedia, isFalse);
    });

    test('混合：一个能解析、一个缺失、一个 wmf', () {
      final result = renderQuestionAssetPlaceholders(
        'A{{asset:a.png}}B{{asset:b.png}}C{{asset:c.wmf}}',
        attachmentNames: const <String>['a.png'],
      );
      expect(
        result.text,
        'A［图1］B［图片缺失：b.png］C［图片缺失：c.wmf（WMF 格式不支持）］',
      );
      expect(result.resolved, 1);
      expect(result.missing, 1);
      expect(result.wmfUnsupported, 1);
    });

    test('没有占位时原样返回', () {
      final result = renderQuestionAssetPlaceholders(
        '普通题干',
        attachmentNames: const <String>['a.png'],
      );
      expect(result.text, '普通题干');
      expect(result.hasReferences, isFalse);
    });

    test('列表摘要折叠：所有占位换成中性［图］', () {
      expect(
        collapseQuestionAssetPlaceholders(
          '如图{{asset:q1_img01.wmf}}{{asset:q1_img02.png}}所示',
        ),
        '如图［图］［图］所示',
      );
    });
  });
}
