import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/claim.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/student_answer_sheet.dart';
import 'package:furnace/features/ai/domain/verifier.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/ai/infrastructure/student_verifier.dart';

/// 学生内容验证器（设计文档 §7.3 / §9.3）。
///
/// 用 fake adapter 驱动，覆盖四态与两种失败输入；并锁住两条边界：
///
///  * 输入只有题目 + 答案卡 + claim 摘要（没有 reasoning 参数可传）；
///  * 解析失败 / 模型失败都落 `error`，绝不落 `pass`。
void main() {
  const question = '求 (2) 物块与斜面间的动摩擦因数';
  const answer = StudentAnswerSheet(
    kind: StudentQuestionKind.solution,
    raw: '原始答案文本',
    result: '(1) a=g sinθ；(2) μ=0.5',
    process: '由牛顿第二定律得 a=g sinθ',
    structured: true,
  );

  ClaimSummary claimsWith(String statement) => ClaimSummary(claims: [
        Claim(
          id: 'claim-1',
          kind: ClaimKind.equation,
          canonical: statement,
          statement: statement,
          status: ClaimStatus.verified,
          checkedVersion: 1,
          createdAtMs: 0,
        ),
      ]);

  StudentVerifier buildVerifier(FakeModelAdapter adapter) =>
      StudentVerifier(adapter: adapter);

  List<ModelEvent> verdictTurn(String json) => [
        ModelTextDelta(json),
        const ModelTurnDone(
          finishReason: 'stop',
          promptTokens: 300,
          completionTokens: 40,
        ),
      ];

  Future<Verification> verify(
    StudentVerifier verifier, {
    ClaimSummary claims = const ClaimSummary.empty(),
    List<ChatImagePart> images = const [],
  }) {
    return verifier.verify(
      question: question,
      answer: answer,
      images: images,
      claims: claims,
    );
  }

  group('四态', () {
    test('pass', () async {
      final adapter = FakeModelAdapter([
        verdictTurn(
            '{"verdict":"pass","issues":[],"evidence":{"checked":true},"confidence":0.9}'),
      ]);
      final verification = await verify(buildVerifier(adapter));

      expect(verification.verdict, Verdict.pass);
      expect(verification.allowsFinalize, isTrue);
      expect(verification.isPass, isTrue);
      expect(verification.independent, isTrue);
      expect(verification.confidence, closeTo(0.9, 1e-9));
      expect(verification.evidence['source'], 'model');
      expect(verification.promptTokens, 300);
      expect(verification.completionTokens, 40);
    });

    test('fail 带 failure_type / issues / evidence', () async {
      final adapter = FakeModelAdapter([
        verdictTurn(
          '{"verdict":"fail","failure_type":"missing_answer",'
          '"issues":["第 (3) 问没有答案"],'
          '"evidence":{"detail":"缺少第(3)问","confidence":0.2},"confidence":0.2}',
        ),
      ]);
      final verification = await verify(buildVerifier(adapter));

      expect(verification.verdict, Verdict.fail);
      expect(verification.failureType, FailureType.missingAnswer);
      expect(verification.issues, ['第 (3) 问没有答案']);
      expect(verification.evidence['model_detail'], '缺少第(3)问');
      expect(verification.allowsFinalize, isFalse);
      expect(verification.verdict.triggersRepair, isTrue);
    });

    test('fail 没给 failure_type 时退化为 other（仍是 fail）', () async {
      final adapter = FakeModelAdapter([
        verdictTurn('{"verdict":"fail","issues":["过程不自洽"]}'),
      ]);
      final verification = await verify(buildVerifier(adapter));

      expect(verification.verdict, Verdict.fail);
      expect(verification.failureType, FailureType.other);
    });

    test('unknown 不是 pass，也不触发 repair', () async {
      final adapter = FakeModelAdapter([
        verdictTurn('{"verdict":"unknown","issues":["题干不清"]}'),
      ]);
      final verification = await verify(buildVerifier(adapter));

      expect(verification.verdict, Verdict.unknown);
      expect(verification.allowsFinalize, isFalse);
      expect(verification.verdict.triggersRepair, isFalse);
    });

    test('模型给了无法识别的 verdict 时落 unknown，不落 pass', () async {
      final adapter = FakeModelAdapter([
        verdictTurn('{"verdict":"probably fine"}'),
      ]);
      final verification = await verify(buildVerifier(adapter));

      expect(verification.verdict, Verdict.unknown);
      expect(verification.allowsFinalize, isFalse);
    });

    test('error：模型调用失败记 verifier_error', () async {
      final adapter = FakeModelAdapter([
        FakeModelAdapter.failure('network down'),
      ]);
      final verification = await verify(buildVerifier(adapter));

      expect(verification.verdict, Verdict.error);
      expect(verification.failureType, FailureType.verifierError);
      expect(verification.allowsFinalize, isFalse);
      expect(verification.independent, isTrue);
    });
  });

  group('输出解析', () {
    test('容忍 ```json 围栏和前后解释文字', () async {
      final adapter = FakeModelAdapter([
        verdictTurn(
          '检查结果如下：\n```json\n{"verdict":"pass","issues":[]}\n```\n以上。',
        ),
      ]);
      final verification = await verify(buildVerifier(adapter));
      expect(verification.verdict, Verdict.pass);
      expect(verification.evidence['raw_verdict'], 'pass');
    });

    test('非 JSON 输出是 error，不是 pass', () async {
      final adapter = FakeModelAdapter([verdictTurn('看起来没问题')]);
      final verification = await verify(buildVerifier(adapter));

      expect(verification.verdict, Verdict.error);
      expect(verification.failureType, FailureType.verifierError);
      expect(verification.evidence['output_chars'], isA<int>());
    });

    test('空输出是 error，不是 pass', () async {
      final adapter = FakeModelAdapter([
        [const ModelTurnDone(finishReason: 'stop')],
      ]);
      final verification = await verify(buildVerifier(adapter));
      expect(verification.verdict, Verdict.error);
    });
  });

  group('输入边界（内容验证不读 CoT）', () {
    test('只看题目 + 答案卡 + claim 摘要，不带工具', () async {
      final adapter = FakeModelAdapter([verdictTurn('{"verdict":"pass"}')]);
      final verifier = buildVerifier(adapter);
      const image = ChatImagePart(mime: 'image/png', base64: 'aW1n');

      await verify(
        verifier,
        claims: claimsWith('m_2/m_1 = 7'),
        images: const [image],
      );

      final request = adapter.requests.single;
      expect(request.tools, isEmpty);
      expect(request.messages.first.role, 'system');
      expect(request.messages.first.content,
          StudentVerifier.verificationSystemPrompt);
      final input = request.messages.last.content!;
      expect(input, contains(question));
      expect(input, contains(answer.toPlainText()));
      expect(input, contains('m_2/m_1 = 7'));
      // claim 摘要来自 ClaimSummary.toPromptText，不带 reasoning 原文。
      expect(input, contains('claim 摘要'));
      // 题图随 user 消息一起送进验证回合。
      expect(request.messages.last.images, hasLength(1));
      expect(request.messages.last.images.single.base64, 'aW1n');
    });

    test('verifier 实现不读文件、不 import dart:io', () {
      final source =
          File('lib/features/ai/infrastructure/student_verifier.dart')
              .readAsStringSync();
      expect(source.contains("import 'dart:io'"), isFalse);
      expect(source.contains('File('), isFalse);
      expect(source.contains('answer.md'), isFalse);
      expect(source.contains('answer_sheet.json'), isFalse);
      expect(source.contains('record'), isFalse);
    });

    test('验证器身份与类别是稳定值', () {
      final verifier = buildVerifier(FakeModelAdapter([verdictTurn('{}')]));
      expect(verifier.id, 'student_independent_v1');
      expect(verifier.kind, VerifierKind.content);
    });
  });

  group('标准答案 oracle', () {
    test('有 oracle 时完全跳过模型，确定性返回', () async {
      final adapter = FakeModelAdapter([]);
      final verifier = StudentVerifier(
        adapter: adapter,
        oracle: _AlwaysPassOracle(),
      );
      final result = await verify(verifier);
      expect(result.verdict, Verdict.pass);
      expect(result.independent, isTrue);
      expect(adapter.requests, isEmpty);
    });
  });
}

class _AlwaysPassOracle implements AnswerOracle {
  @override
  String get id => 'test_oracle';

  @override
  Future<Verification> check({
    required String question,
    required StudentAnswerSheet answer,
  }) async =>
      Verification.pass();
}
