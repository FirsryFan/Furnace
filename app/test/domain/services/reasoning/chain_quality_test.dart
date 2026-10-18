// 思维链质量体检 ChainQualityAudit 的纯逻辑测试：
// 每条判据的命中 / 不命中、边界、截断、排序与确定性。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/reasoning/capability_action_overlay.dart';
import 'package:furnace/domain/services/reasoning/chain_quality.dart';

ChainQualityStepInput step(
  String actionType, {
  int index = 0,
  double? risk,
  bool? knownAction,
  String? justification = '推导依据',
  String? checkMethod = '回代验证',
  List<String> hints = const <String>['kp'],
}) {
  return ChainQualityStepInput(
    actionType: actionType,
    index: index,
    stuckRisk: risk,
    knownAction: knownAction,
    justification: justification,
    checkMethod: checkMethod,
    knowledgeHints: hints,
  );
}

ChainQualityChainInput chain(
  String chainId, {
  String questionId = 'q1',
  List<ChainQualityStepInput> steps = const <ChainQualityStepInput>[],
}) {
  return ChainQualityChainInput(
    chainId: chainId,
    questionId: questionId,
    steps: steps,
  );
}

ChainQualityReport audit(
  List<ChainQualityChainInput> chains, {
  CapabilityActionCatalog? catalog,
  int minSteps = ChainQualityAudit.defaultMinSteps,
  double highRiskThreshold = ChainQualityAudit.defaultHighRiskThreshold,
  int maxFindingsPerCode = ChainQualityAudit.defaultMaxFindingsPerCode,
}) {
  return ChainQualityAudit.audit(
    chains,
    catalog: catalog,
    minSteps: minSteps,
    highRiskThreshold: highRiskThreshold,
    maxFindingsPerCode: maxFindingsPerCode,
  );
}

ChainQualityChainInput cleanChain({
  String chainId = 'c1',
  String questionId = 'q1',
}) {
  return chain(
    chainId,
    questionId: questionId,
    steps: <ChainQualityStepInput>[
      step('case_split', index: 0, risk: 0.1),
      step('induction', index: 1, risk: 0.2),
      step('symmetry', index: 2, risk: 0.3),
    ],
  );
}

List<String> codesOf(ChainQualityReport report) {
  return <String>[for (final finding in report.findings) finding.code];
}

void main() {
  group('严重级与 code 表', () {
    test('严重级中文名与枚举顺序', () {
      expect(
        ChainQualitySeverity.values,
        <ChainQualitySeverity>[
          ChainQualitySeverity.error,
          ChainQualitySeverity.warning,
          ChainQualitySeverity.info,
        ],
      );
      expect(ChainQualitySeverity.error.labelZh, '错误');
      expect(ChainQualitySeverity.warning.labelZh, '警告');
      expect(ChainQualitySeverity.info.labelZh, '提示');
    });

    test('code 表至少 12 条且互不重复', () {
      expect(ChainQualityCodes.all.length, greaterThanOrEqualTo(12));
      expect(
          ChainQualityCodes.all.toSet().length, ChainQualityCodes.all.length);
      for (final code in ChainQualityCodes.all) {
        expect(code.trim(), isNotEmpty);
      }
    });

    test('干净链没有任何 finding', () {
      final report = audit(<ChainQualityChainInput>[cleanChain()]);
      expect(report.chainCount, 1);
      expect(report.stepCount, 3);
      expect(report.findings, isEmpty);
      expect(report.isClean, isTrue);
      expect(report.isTruncated, isFalse);
      expect(report.totalFindingCount, 0);
      for (final severity in ChainQualitySeverity.values) {
        expect(report.countsBySeverity[severity], 0);
      }
    });

    test('finding 的 toJson 是 snake_case 且字段齐全', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step(
                'case_split',
                index: 0,
                risk: 0.9,
                justification: null,
              ),
            ],
          ),
        ],
        minSteps: 1,
      );
      final finding = report
          .findingsFor(ChainQualityCodes.highRiskMissingJustification)
          .single;
      final json = finding.toJson();
      expect(json.keys.toSet(), <String>{
        'code',
        'severity',
        'severity_label_zh',
        'message_zh',
        'question_id',
        'chain_id',
        'step_index',
        'evidence',
      });
      expect(json['code'], ChainQualityCodes.highRiskMissingJustification);
      expect(json['severity'], 'warning');
      expect(json['severity_label_zh'], '警告');
      expect(json['question_id'], 'q1');
      expect(json['chain_id'], 'c1');
      expect(json['step_index'], 0);
      expect(
        json['evidence'],
        <String, String>{'action_type': 'case_split', 'stuck_risk': '0.9'},
      );
    });
  });

  group('链级判据', () {
    test('空链只报 empty_chain', () {
      final report = audit(<ChainQualityChainInput>[chain('c1')]);
      expect(codesOf(report), <String>[ChainQualityCodes.emptyChain]);
      expect(report.stepCount, 0);
      final finding = report.findings.single;
      expect(finding.severity, ChainQualitySeverity.error);
      expect(finding.stepIndex, isNull);
    });

    test('步数过少命中 too_few_steps', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: 0.1),
              step('induction', index: 1, risk: 0.2),
            ],
          ),
        ],
      );
      expect(codesOf(report), <String>[ChainQualityCodes.tooFewSteps]);
      expect(
        report.findings.single.evidence,
        <String, String>{'step_count': '2', 'min_steps': '3'},
      );
    });

    test('步数正好等于 minSteps 不报 too_few_steps', () {
      final report = audit(
        <ChainQualityChainInput>[cleanChain()],
        minSteps: 3,
      );
      expect(report.findingsFor(ChainQualityCodes.tooFewSteps), isEmpty);
      expect(report.isClean, isTrue);
    });

    test('minSteps 小于 1 按 1 处理，单步链不报 too_few_steps', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: 0.1),
            ],
          ),
        ],
        minSteps: 0,
      );
      expect(report.findingsFor(ChainQualityCodes.tooFewSteps), isEmpty);
      expect(report.isClean, isTrue);
    });

    test('questionId 为空报 empty_question_id（去空白后判定）', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            '',
            questionId: '   ',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: 0.1),
            ],
          ),
        ],
        minSteps: 1,
      );
      final finding =
          report.findingsFor(ChainQualityCodes.emptyQuestionId).single;
      expect(finding.severity, ChainQualitySeverity.warning);
      expect(finding.questionId, '');
      expect(codesOf(report), contains(ChainQualityCodes.emptyQuestionId));
    });

    test('chainId 为空报 empty_chain_id 且严重级是 error', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            '',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: 0.1),
            ],
          ),
        ],
        minSteps: 1,
      );
      final finding = report.findingsFor(ChainQualityCodes.emptyChainId).single;
      expect(finding.severity, ChainQualitySeverity.error);
      expect(finding.chainId, '');
      expect(codesOf(report), <String>[ChainQualityCodes.emptyChainId]);
    });

    test('未知动作占比超过一半报 unknown_action_ratio_high', () {
      final report = audit(<ChainQualityChainInput>[
        chain(
          'c1',
          steps: <ChainQualityStepInput>[
            step('mystery_a', index: 0, risk: 0.1),
            step('mystery_b', index: 1, risk: 0.1),
            step('case_split', index: 2, risk: 0.1),
          ],
        ),
      ]);
      expect(
        codesOf(report),
        <String>[ChainQualityCodes.unknownActionRatioHigh],
      );
      expect(
        report.findings.single.evidence,
        <String, String>{
          'unknown_step_count': '2',
          'step_count': '3',
          'ratio': '0.67',
        },
      );
    });

    test('未知动作恰好一半不报 unknown_action_ratio_high', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('mystery_a', index: 0, risk: 0.1),
              step('case_split', index: 1, risk: 0.1),
            ],
          ),
        ],
        minSteps: 2,
      );
      expect(
        report.findingsFor(ChainQualityCodes.unknownActionRatioHigh),
        isEmpty,
      );
      expect(report.isClean, isTrue);
    });

    test('全部未知动作同时报 no_known_action 与比例过高', () {
      final report = audit(<ChainQualityChainInput>[
        chain(
          'c1',
          steps: <ChainQualityStepInput>[
            step('mystery_a', index: 0, risk: 0.1),
            step('mystery_b', index: 1, risk: 0.1),
            step('mystery_c', index: 2, risk: 0.1),
          ],
        ),
      ]);
      expect(
        codesOf(report),
        <String>[
          ChainQualityCodes.noKnownAction,
          ChainQualityCodes.unknownActionRatioHigh,
        ],
      );
    });

    test('catalog 为 null 时退回内置词表判未知', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('my_move', index: 0, risk: 0.1),
            ],
          ),
        ],
        minSteps: 1,
      );
      expect(
        report.findingsFor(ChainQualityCodes.unknownActionRatioHigh),
        isNotEmpty,
      );
      expect(report.findingsFor(ChainQualityCodes.noKnownAction), isNotEmpty);
      expect(report.findingsFor(ChainQualityCodes.emptyActionType), isEmpty);
    });

    test('传入 catalog 后自定义动作算已知，不再报未知判据', () {
      final catalog = CapabilityActionCatalog.merge(
        <CustomCapabilityAction>[
          const CustomCapabilityAction(key: 'my_move', labelZh: '自定义动作'),
        ],
      );
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('my_move', index: 0, risk: 0.1),
            ],
          ),
        ],
        catalog: catalog,
        minSteps: 1,
      );
      expect(report.findingsFor(ChainQualityCodes.noKnownAction), isEmpty);
      expect(
        report.findingsFor(ChainQualityCodes.unknownActionRatioHigh),
        isEmpty,
      );
      expect(report.isClean, isTrue);
    });

    test('动作单一报 single_action，相邻重复另计', () {
      final report = audit(<ChainQualityChainInput>[
        chain(
          'c1',
          steps: <ChainQualityStepInput>[
            step('case_split', index: 0, risk: 0.1),
            step('case_split', index: 1, risk: 0.1),
            step('case_split', index: 2, risk: 0.1),
          ],
        ),
      ]);
      expect(report.findingsFor(ChainQualityCodes.singleAction), hasLength(1));
      expect(
        report.findingsFor(ChainQualityCodes.consecutiveDuplicateAction),
        hasLength(2),
      );
    });

    test('相邻重复动作报 consecutive_duplicate_action', () {
      final report = audit(<ChainQualityChainInput>[
        chain(
          'c1',
          steps: <ChainQualityStepInput>[
            step('case_split', index: 0, risk: 0.1),
            step('case_split', index: 1, risk: 0.1),
            step('induction', index: 2, risk: 0.1),
          ],
        ),
      ]);
      final finding = report
          .findingsFor(ChainQualityCodes.consecutiveDuplicateAction)
          .single;
      expect(finding.stepIndex, 1);
      expect(finding.severity, ChainQualitySeverity.info);
      expect(finding.evidence['action_type'], 'case_split');
      expect(finding.evidence['previous_index'], '0');
    });

    test('缺知识点提示报 missing_knowledge_hints', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step(
                'case_split',
                index: 0,
                risk: 0.1,
                hints: const <String>[],
              ),
            ],
          ),
        ],
        minSteps: 1,
      );
      expect(
        codesOf(report),
        <String>[ChainQualityCodes.missingKnowledgeHints],
      );
      expect(report.findings.single.severity, ChainQualitySeverity.info);
    });

    test('全链没有任何卡点读数报 no_risk_reading', () {
      final report = audit(<ChainQualityChainInput>[
        chain(
          'c1',
          steps: <ChainQualityStepInput>[
            step('case_split', index: 0),
            step('induction', index: 1),
            step('symmetry', index: 2),
          ],
        ),
      ]);
      expect(codesOf(report), <String>[ChainQualityCodes.noRiskReading]);
    });

    test('动作 key 为空报 empty_action_type（显式，不静默）', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('', index: 0, risk: 0.1),
            ],
          ),
        ],
        minSteps: 1,
      );
      final finding =
          report.findingsFor(ChainQualityCodes.emptyActionType).single;
      expect(finding.severity, ChainQualitySeverity.error);
      expect(finding.stepIndex, 0);
      expect(report.findingsFor(ChainQualityCodes.noKnownAction), isNotEmpty);
    });
  });

  group('步级判据', () {
    test('高危步缺 justification 报 high_risk_missing_justification', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: 0.9, justification: null),
            ],
          ),
        ],
        minSteps: 1,
      );
      expect(
        codesOf(report),
        <String>[ChainQualityCodes.highRiskMissingJustification],
      );
      final finding = report.findings.single;
      expect(finding.severity, ChainQualitySeverity.warning);
      expect(finding.stepIndex, 0);
      expect(finding.evidence['stuck_risk'], '0.9');
    });

    test('高危步缺 checkMethod 报 high_risk_missing_check_method', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: 0.9, checkMethod: null),
            ],
          ),
        ],
        minSteps: 1,
      );
      expect(
        codesOf(report),
        <String>[ChainQualityCodes.highRiskMissingCheckMethod],
      );
    });

    test('高危步两个字段都齐时不报', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: 0.9),
            ],
          ),
        ],
        minSteps: 1,
      );
      expect(report.isClean, isTrue);
    });

    test('低危步缺 justification 不报（判据只查高危）', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: 0.3, justification: null),
            ],
          ),
        ],
        minSteps: 1,
      );
      expect(
        report.findingsFor(ChainQualityCodes.highRiskMissingJustification),
        isEmpty,
      );
      expect(report.isClean, isTrue);
    });

    test('步骤序号重复报 duplicate_step_index', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: 0.1),
              step('induction', index: 1, risk: 0.1),
              step('symmetry', index: 1, risk: 0.1),
            ],
          ),
        ],
        minSteps: 3,
      );
      final finding =
          report.findingsFor(ChainQualityCodes.duplicateStepIndex).single;
      expect(finding.severity, ChainQualitySeverity.error);
      expect(finding.stepIndex, 1);
      expect(finding.evidence['occurrence'], '2');
    });

    test('步骤序号为负数报 invalid_step_index', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('case_split', index: -1, risk: 0.1),
            ],
          ),
        ],
        minSteps: 1,
      );
      expect(
        codesOf(report),
        <String>[ChainQualityCodes.invalidStepIndex],
      );
    });

    test('步骤序号中间缺号报 non_contiguous_step_index', () {
      final report = audit(<ChainQualityChainInput>[
        chain(
          'c1',
          steps: <ChainQualityStepInput>[
            step('case_split', index: 0, risk: 0.1),
            step('induction', index: 2, risk: 0.1),
            step('symmetry', index: 3, risk: 0.1),
          ],
        ),
      ]);
      final finding =
          report.findingsFor(ChainQualityCodes.nonContiguousStepIndex).single;
      expect(finding.severity, ChainQualitySeverity.warning);
      expect(finding.evidence['missing_index'], '1');
    });

    test('序号从 1 起连续不报 non_contiguous_step_index', () {
      final report = audit(<ChainQualityChainInput>[
        chain(
          'c1',
          steps: <ChainQualityStepInput>[
            step('case_split', index: 1, risk: 0.1),
            step('induction', index: 2, risk: 0.1),
            step('symmetry', index: 3, risk: 0.1),
          ],
        ),
      ]);
      expect(
        report.findingsFor(ChainQualityCodes.nonContiguousStepIndex),
        isEmpty,
      );
      expect(report.isClean, isTrue);
    });

    test('NaN 卡点读数报 invalid_risk_reading 且不被当成高危', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: double.nan),
            ],
          ),
        ],
        minSteps: 1,
      );
      expect(
        report.findingsFor(ChainQualityCodes.invalidRiskReading),
        hasLength(1),
      );
      expect(
        report.findingsFor(ChainQualityCodes.highRiskMissingJustification),
        isEmpty,
      );
      expect(report.findingsFor(ChainQualityCodes.noRiskReading), hasLength(1));
    });

    test('无穷卡点读数报 invalid_risk_reading', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: double.infinity),
            ],
          ),
        ],
        minSteps: 1,
      );
      final finding =
          report.findingsFor(ChainQualityCodes.invalidRiskReading).single;
      expect(finding.evidence['stuck_risk'], 'Infinity');
    });

    test('读数大于 1 报 risk_out_of_range', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: 1.5),
            ],
          ),
        ],
        minSteps: 1,
      );
      final finding =
          report.findingsFor(ChainQualityCodes.riskOutOfRange).single;
      expect(finding.severity, ChainQualitySeverity.warning);
      expect(finding.evidence['stuck_risk'], '1.5');
    });

    test('读数小于 0 报 risk_out_of_range 且夹到 0 后不算高危', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step(
                'case_split',
                index: 0,
                risk: -0.5,
                justification: null,
              ),
            ],
          ),
        ],
        minSteps: 1,
      );
      expect(
        report.findingsFor(ChainQualityCodes.riskOutOfRange),
        hasLength(1),
      );
      expect(
        report.findingsFor(ChainQualityCodes.highRiskMissingJustification),
        isEmpty,
      );
    });

    test('越界读数夹到 1 后参与高危判定', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: 1.5, justification: null),
            ],
          ),
        ],
        minSteps: 1,
      );
      expect(
          report.findingsFor(ChainQualityCodes.riskOutOfRange), hasLength(1));
      expect(
        report.findingsFor(ChainQualityCodes.highRiskMissingJustification),
        hasLength(1),
      );
    });

    test('knownAction 快照与当前词表不一致报 stale_known_action_flag', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: 0.1, knownAction: false),
            ],
          ),
        ],
        minSteps: 1,
      );
      final finding =
          report.findingsFor(ChainQualityCodes.staleKnownActionFlag).single;
      expect(finding.severity, ChainQualitySeverity.info);
      expect(finding.evidence['snapshot_known'], 'false');
      expect(finding.evidence['current_known'], 'true');
    });
  });

  group('参数、截断与空报告', () {
    test('空输入返回空报告，toJson 字段齐全', () {
      final report = audit(const <ChainQualityChainInput>[]);
      expect(report.chainCount, 0);
      expect(report.stepCount, 0);
      expect(report.findings, isEmpty);
      expect(report.isClean, isTrue);
      expect(report.isTruncated, isFalse);
      expect(report.countsBySeverity.length, 3);
      final json = report.toJson();
      expect(json.keys.toSet(), <String>{
        'chain_count',
        'step_count',
        'finding_count',
        'total_finding_count',
        'is_clean',
        'is_truncated',
        'max_findings_per_code',
        'counts_by_severity',
        'counts_by_code',
        'truncated_counts',
        'findings',
      });
      expect(json['counts_by_severity'], <String, Object?>{
        'error': 0,
        'warning': 0,
        'info': 0,
      });
    });

    test('ChainQualityReport.empty 与空输入一致', () {
      final report = ChainQualityReport.empty();
      expect(report.chainCount, 0);
      expect(report.stepCount, 0);
      expect(report.findings, isEmpty);
      expect(report.maxFindingsPerCode,
          ChainQualityAudit.defaultMaxFindingsPerCode);
      expect(report.countsBySeverity.length, 3);
    });

    test('阈值为 NaN 时退回默认 0.6', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: 0.7, justification: null),
            ],
          ),
        ],
        minSteps: 1,
        highRiskThreshold: double.nan,
      );
      expect(
        report.findingsFor(ChainQualityCodes.highRiskMissingJustification),
        hasLength(1),
      );
    });

    test('阈值大于 1 夹到 1，0.9 不算高危', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: 0.9, justification: null),
            ],
          ),
        ],
        minSteps: 1,
        highRiskThreshold: 5,
      );
      expect(
        report.findingsFor(ChainQualityCodes.highRiskMissingJustification),
        isEmpty,
      );
    });

    test('阈值为 1 时读数 1.0 算高危', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: 1, justification: null),
            ],
          ),
        ],
        minSteps: 1,
        highRiskThreshold: 5,
      );
      expect(
        report.findingsFor(ChainQualityCodes.highRiskMissingJustification),
        hasLength(1),
      );
    });

    test('阈值为 0 时所有有限读数都算高危', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: 0.1, justification: null),
              step('induction', index: 1, risk: 0.1, justification: null),
              step('symmetry', index: 2, risk: 0.1, justification: null),
            ],
          ),
        ],
        highRiskThreshold: 0,
      );
      expect(
        report.findingsFor(ChainQualityCodes.highRiskMissingJustification),
        hasLength(3),
      );
    });

    test('maxFindingsPerCode 截断并记录 truncated 标记', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              for (var i = 0; i < 4; i++)
                step(
                  <String>[
                    'case_split',
                    'induction',
                    'symmetry',
                    'reduction'
                  ][i],
                  index: i,
                  risk: 0.1,
                  hints: const <String>[],
                ),
            ],
          ),
        ],
        maxFindingsPerCode: 2,
      );
      const code = ChainQualityCodes.missingKnowledgeHints;
      expect(report.findingsFor(code), hasLength(2));
      expect(report.truncatedCounts[code], 2);
      expect(report.countsByCode[code], 4);
      expect(report.countsBySeverity[ChainQualitySeverity.info], 4);
      expect(report.isTruncated, isTrue);
      expect(report.totalFindingCount, 4);
      expect(report.findings.length, 2);
      final json = report.toJson();
      expect(json['is_truncated'], isTrue);
      expect(json['truncated_counts'], <String, Object?>{code: 2});
    });

    test('maxFindingsPerCode 小于 1 按 1 处理', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              for (var i = 0; i < 4; i++)
                step(
                  <String>[
                    'case_split',
                    'induction',
                    'symmetry',
                    'reduction'
                  ][i],
                  index: i,
                  risk: 0.1,
                  hints: const <String>[],
                ),
            ],
          ),
        ],
        maxFindingsPerCode: 0,
      );
      expect(
        report.findingsFor(ChainQualityCodes.missingKnowledgeHints),
        hasLength(1),
      );
      expect(
        report.truncatedCounts[ChainQualityCodes.missingKnowledgeHints],
        3,
      );
    });

    test('report.findings 与 findingsFor 返回不可变列表', () {
      final report = audit(<ChainQualityChainInput>[cleanChain()]);
      final dummy = ChainQualityFinding(
        code: 'dummy_code',
        severity: ChainQualitySeverity.info,
        messageZh: 'dummy',
        questionId: 'q',
        chainId: 'c',
      );
      expect(() => report.findings.add(dummy), throwsUnsupportedError);
      expect(
        () => report.findingsFor(ChainQualityCodes.emptyChain).add(dummy),
        throwsUnsupportedError,
      );
    });
  });

  group('确定性与排序', () {
    test('同输入两次调用 JSON 逐字节相等', () {
      final chains = <ChainQualityChainInput>[
        chain(
          'c2',
          questionId: 'q2',
          steps: <ChainQualityStepInput>[
            step('mystery_a', index: 0, risk: 0.9, justification: null),
            step('induction', index: 1, risk: 0.2),
          ],
        ),
        chain('c1'),
      ];
      final first = audit(chains);
      final second = audit(chains);
      expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
    });

    test('输入链顺序颠倒不改变 JSON（排序归一）', () {
      final first = audit(<ChainQualityChainInput>[
        chain('c1'),
        cleanChain(chainId: 'c2', questionId: 'q2'),
      ]);
      final second = audit(<ChainQualityChainInput>[
        cleanChain(chainId: 'c2', questionId: 'q2'),
        chain('c1'),
      ]);
      expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
    });

    test('按 questionId → stepIndex 排序，链级 finding 的 null 在最后', () {
      final report = audit(<ChainQualityChainInput>[
        chain('c2', questionId: 'q2'),
        chain(
          'c1',
          questionId: 'q1',
          steps: <ChainQualityStepInput>[
            step('case_split', index: 0, risk: 0.9, justification: null),
            step('induction', index: 1, risk: 0.9, justification: null),
            step('symmetry', index: 2, risk: 0.9, justification: null),
          ],
        ),
      ]);
      expect(codesOf(report), <String>[
        ChainQualityCodes.highRiskMissingJustification,
        ChainQualityCodes.highRiskMissingJustification,
        ChainQualityCodes.highRiskMissingJustification,
        ChainQualityCodes.emptyChain,
      ]);
      expect(
        report.findings.map((finding) => finding.stepIndex).toList(),
        <int?>[0, 1, 2, null],
      );
    });

    test('同一步内按严重级排序：warning 在 info 前', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step(
                'case_split',
                index: 0,
                risk: 0.9,
                justification: null,
                hints: const <String>[],
              ),
            ],
          ),
        ],
        minSteps: 1,
      );
      expect(codesOf(report), <String>[
        ChainQualityCodes.highRiskMissingJustification,
        ChainQualityCodes.missingKnowledgeHints,
      ]);
    });

    test('同题目不同链按 chainId 升序', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c9',
            steps: <ChainQualityStepInput>[
              step('induction', index: 0, risk: 0.9, justification: null),
            ],
          ),
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: 0.9, justification: null),
            ],
          ),
        ],
        minSteps: 1,
      );
      expect(
        report
            .findingsFor(ChainQualityCodes.highRiskMissingJustification)
            .map((finding) => finding.chainId)
            .toList(),
        <String>['c1', 'c9'],
      );
    });

    test('countsBySeverity 三个键永远都在', () {
      final report = audit(<ChainQualityChainInput>[
        chain(
          'c1',
          steps: <ChainQualityStepInput>[
            step('case_split', index: 0, risk: 0.1),
          ],
        ),
      ]);
      expect(report.countsBySeverity.keys.toSet(), <ChainQualitySeverity>{
        ChainQualitySeverity.error,
        ChainQualitySeverity.warning,
        ChainQualitySeverity.info,
      });
      expect(report.countsBySeverity[ChainQualitySeverity.error], 0);
      expect(report.countsBySeverity[ChainQualitySeverity.warning], 1);
      expect(report.countsBySeverity[ChainQualitySeverity.info], 0);
    });

    test('finding.evidence 不可变', () {
      final report = audit(
        <ChainQualityChainInput>[
          chain(
            'c1',
            steps: <ChainQualityStepInput>[
              step('case_split', index: 0, risk: 0.9, justification: null),
            ],
          ),
        ],
        minSteps: 1,
      );
      final finding = report.findings.single;
      expect(() => finding.evidence['x'] = 'y', throwsUnsupportedError);
    });

    test('chainCount / stepCount 统计含坏链与坏步骤', () {
      final report = audit(<ChainQualityChainInput>[
        chain('c1'),
        chain(
          'c2',
          questionId: 'q2',
          steps: <ChainQualityStepInput>[
            step('case_split', index: 0, risk: 0.1),
            step('induction', index: 1, risk: 0.1),
          ],
        ),
      ]);
      expect(report.chainCount, 2);
      expect(report.stepCount, 2);
    });
  });
}
