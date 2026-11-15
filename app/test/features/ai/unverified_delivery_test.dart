import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/checker_report.dart';
import 'package:furnace/features/ai/domain/unverified_delivery.dart';

/// UnverifiedDelivery / TeachingExtension / LearningRecord（设计 §7.5 / §9）。
///
/// 锁住：两轮不过的交付带教学延伸 + 学习记录；延伸/学习记录是确定性模板
/// （不是 LLM 总结）；verified 不需要延伸。
void main() {
  const issue = CheckIssue(
    id: 'i1',
    stepId: 's3',
    category: CheckIssueCategory.missingCase,
    severity: CheckSeverity.fatal,
    evidence: '分支表只覆盖 k<=1',
    violated: '定义域 k>0 未被覆盖',
    minimalFix: '补 m2/m1=7 分支并重推',
  );

  TeachingExtension buildExtension() => TeachingExtension.fromIssue(issue);

  LearningRecord buildRecord() => LearningRecord.fromIssue(
        cluster: 'student_exam',
        issue: issue,
        provenanceRunId: 'run-1',
      );

  test('DeliveryStatus：verified 不需要教学延伸，未知值不冒充 verified', () {
    expect(DeliveryStatus.verified.needsTeachingExtension, isFalse);
    expect(DeliveryStatus.unverified.needsTeachingExtension, isTrue);
    expect(DeliveryStatus.humanRequired.needsTeachingExtension, isTrue);

    expect(DeliveryStatus.fromId('verified'), DeliveryStatus.verified);
    expect(DeliveryStatus.fromId('unverified'), DeliveryStatus.unverified);
    expect(DeliveryStatus.fromId('whatever'), DeliveryStatus.humanRequired);
    expect(DeliveryStatus.fromId(null), DeliveryStatus.humanRequired);
  });

  test('TeachingExtension 从结构化 issue 确定性生成，不抄 issue 原文了事', () {
    final extension = buildExtension();

    expect(extension.title, contains('漏掉'));
    expect(extension.hiddenIssue, contains(issue.violated));
    expect(extension.hiddenIssue, contains(issue.evidence));
    expect(extension.hiddenIssue, contains(issue.minimalFix));
    expect(extension.userPrompts, isNotEmpty);
    expect(extension.expectedReasoning, contains(issue.minimalFix));

    // 不同 issue 类别给出不同的延伸标题与问题（模板按类别固定）。
    const unitIssue = CheckIssue(
      id: 'i2',
      stepId: 's4',
      category: CheckIssueCategory.unit,
      severity: CheckSeverity.major,
      evidence: '答案没写单位',
      violated: '最终量缺单位',
      minimalFix: '补上单位并在答案卡里保留',
    );
    final unitExtension = TeachingExtension.fromIssue(unitIssue);
    expect(unitExtension.title, isNot(extension.title));
    expect(unitExtension.userPrompts, isNot(extension.userPrompts));
    expect(unitExtension.hiddenIssue, contains('最终量缺单位'));
  });

  test('TeachingExtension.generic 在 uncheckable 时也可用', () {
    final generic = TeachingExtension.generic();
    expect(generic.title, isNotEmpty);
    expect(generic.hiddenIssue, isNotEmpty);
    expect(generic.userPrompts, isNotEmpty);
    expect(generic.expectedReasoning, isNotEmpty);
    expect(generic.toJson()['user_prompts'], isNotEmpty);
  });

  test('LearningRecord 记录 cluster/类别/证据/架构提示/provenance', () {
    final record = buildRecord();

    expect(record.cluster, 'student_exam');
    expect(record.issueCategory, CheckIssueCategory.missingCase);
    expect(record.evidence, contains(issue.violated));
    expect(record.architectureHint, isNotEmpty);
    expect(record.architectureHint, contains('分支'));
    expect(record.provenanceRunId, 'run-1');

    final json = record.toJson();
    expect(json['cluster'], 'student_exam');
    expect(json['issue_category'], 'missing_case');
    expect(json['provenance_run_id'], 'run-1');

    // 不同类别 -> 不同架构提示（学习资料要有区分度）。
    final unitRecord = LearningRecord.fromIssue(
      cluster: 'student_exam',
      issue: const CheckIssue(
        id: 'u1',
        stepId: 's5',
        category: CheckIssueCategory.unit,
        severity: CheckSeverity.major,
        evidence: '缺单位',
        violated: '单位不匹配',
        minimalFix: '补单位',
      ),
      provenanceRunId: 'run-1',
    );
    expect(unitRecord.architectureHint, isNot(record.architectureHint));
  });

  test('LearningRecord 必须带 cluster 与来源 run', () {
    expect(
      () => LearningRecord.fromCategory(
        cluster: ' ',
        issueCategory: CheckIssueCategory.other,
        evidence: 'e',
        provenanceRunId: 'run-1',
      ),
      throwsArgumentError,
    );
    expect(
      () => LearningRecord.fromCategory(
        cluster: 'student_exam',
        issueCategory: CheckIssueCategory.other,
        evidence: 'e',
        provenanceRunId: ' ',
      ),
      throwsArgumentError,
    );
  });

  test('UnverifiedDelivery：两轮不过 = unverified + 延伸 + 学习记录', () {
    final delivery = UnverifiedDelivery.fromCheckerFailure(
      reason: 'Checker 连续 2 轮过程审查未通过',
      answer: '（2）m2/m1=7',
      extension: buildExtension(),
      learningRecord: buildRecord(),
    );

    expect(delivery.status, DeliveryStatus.unverified);
    expect(delivery.isVerified, isFalse);
    expect(delivery.reason, isNotEmpty);
    expect(delivery.answer, contains('m2/m1=7'));
    expect(delivery.extension.userPrompts, isNotEmpty);
    expect(delivery.learningRecord.provenanceRunId, 'run-1');

    final json = delivery.toJson();
    expect(json['status'], 'unverified');
    expect(json['extension'], isA<Map<String, Object?>>());
    expect(json['learning_record'], isA<Map<String, Object?>>());
  });

  test('UnverifiedDelivery：无法判断时转人工', () {
    final delivery = UnverifiedDelivery.humanRequired(
      reason: 'Checker uncheckable，转人工复核',
      answer: '（3）17/2<=E<=12',
      extension: TeachingExtension.generic(),
      learningRecord: LearningRecord.fromCategory(
        cluster: 'student_exam',
        issueCategory: CheckIssueCategory.other,
        evidence: 'checker uncheckable',
        provenanceRunId: 'run-1',
      ),
    );
    expect(delivery.status, DeliveryStatus.humanRequired);
    expect(delivery.extension.title, isNotEmpty);
  });

  test('UnverifiedDelivery 必须带原因与答案', () {
    expect(
      () => UnverifiedDelivery.fromCheckerFailure(
        reason: ' ',
        answer: 'a',
        extension: buildExtension(),
        learningRecord: buildRecord(),
      ),
      throwsArgumentError,
    );
    expect(
      () => UnverifiedDelivery.fromCheckerFailure(
        reason: 'r',
        answer: ' ',
        extension: buildExtension(),
        learningRecord: buildRecord(),
      ),
      throwsArgumentError,
    );
  });
}
