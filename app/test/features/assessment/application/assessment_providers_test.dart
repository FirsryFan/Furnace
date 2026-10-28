import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:furnace/features/assessment/application/assessment_providers.dart';
import 'package:furnace/features/assessment/application/cognitive_params_provider.dart';
import 'package:furnace/features/assessment/domain/assessment_models.dart';

AssessmentProfileSnapshot _snapshot(List<ParamEstimate> params) {
  return AssessmentProfileSnapshot(
    abilities: const <AbilityEstimate>[],
    params: params,
    sessions: const <AssessmentSessionSummary>[],
  );
}

ParamEstimate _param(
  String id, {
  required double value,
  required double uncertainty,
  String source = EstimateSources.assessment,
}) {
  return ParamEstimate(
    paramId: id,
    value: value,
    uncertainty: uncertainty,
    source: source,
  );
}

void main() {
  test('档案为空时九项建议全部回退默认先验', () async {
    final container = ProviderContainer(
      overrides: [
        assessmentProfileProvider.overrideWith(
          (ref) async => _snapshot(const <ParamEstimate>[]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(assessmentProfileProvider.future);

    final suggestions = container.read(threadWeightSuggestionsProvider);
    expect(suggestions, hasLength(kThreadRelevantParamIds.length));
    expect(
      suggestions.map((s) => s.paramId).toList(),
      kThreadRelevantParamIds,
    );
    expect(suggestions.every((s) => s.usedDefault), isTrue);
    expect(
      suggestions.every((s) => s.source == EstimateSources.defaultPrior),
      isTrue,
    );
  });

  test('低不确定性参数被采纳，高不确定性参数回退默认', () async {
    final container = ProviderContainer(
      overrides: [
        assessmentProfileProvider.overrideWith(
          (ref) async => _snapshot(<ParamEstimate>[
            _param(
              CognitiveParamIds.taskDurationEstimate,
              value: 0.9,
              uncertainty: 0.2,
            ),
            _param(
              CognitiveParamIds.switchPenalty,
              value: 0.1,
              uncertainty: 0.35,
            ),
            _param(
              CognitiveParamIds.interruptionCost,
              value: 0.2,
              uncertainty: 0.9,
            ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(assessmentProfileProvider.future);

    final provider = container.read(cognitiveParamsProvider);
    final adopted = provider.estimateFor(
      CognitiveParamIds.taskDurationEstimate,
    );
    expect(adopted.value, 0.9);
    expect(adopted.source, EstimateSources.assessment);

    final hinted = provider.estimateFor(CognitiveParamIds.switchPenalty);
    expect(hinted.value, 0.1);
    expect(hinted.source, EstimateSources.assessment);

    final fallback = provider.estimateFor(
      CognitiveParamIds.interruptionCost,
    );
    expect(fallback.source, EstimateSources.defaultPrior);
    final spec = kCognitiveParamSpecs.firstWhere(
      (spec) => spec.id == CognitiveParamIds.interruptionCost,
    );
    expect(fallback.value, spec.defaultValue);
  });

  test('user_override 不确定性高也保留用户值', () async {
    final container = ProviderContainer(
      overrides: [
        assessmentProfileProvider.overrideWith(
          (ref) async => _snapshot(<ParamEstimate>[
            _param(
              CognitiveParamIds.expectedPressure,
              value: 0.05,
              uncertainty: 0.95,
              source: EstimateSources.userOverride,
            ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(assessmentProfileProvider.future);

    final suggestion = container
        .read(threadWeightSuggestionsProvider)
        .firstWhere((s) => s.paramId == CognitiveParamIds.expectedPressure);
    expect(suggestion.suggestedValue, 0.05);
    expect(suggestion.source, EstimateSources.userOverride);
    expect(suggestion.usedDefault, isFalse);
  });
}
