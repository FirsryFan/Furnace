/// 能力动作画像的读法：库里的全部解题步骤 → `CapabilityProfile.of`。
///
/// 只有一处 IO（读 `reasoning_steps`），聚合和排序全在
/// `domain/services/reasoning/capability_profile.dart` 里（纯逻辑、可离线测）。
/// `watchDatabaseRevision` 让"刚解完一题"就能在画像里看到新样本。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/reasoning/capability_profile.dart';

/// 按"最该练"排好序的能力动作读数；一条链都没有时是空列表（不编"暂无异常"）。
final capabilityProfileProvider =
    FutureProvider.autoDispose<List<CapabilityReading>>((ref) async {
  ref.watchDatabaseRevision();
  final repository = ref.watch(questionRepositoryProvider);
  final steps = await repository.allReasoningSteps();
  return CapabilityProfile.of(<CapabilityStepSample>[
    for (final step in steps)
      CapabilityStepSample(
        actionType: step.actionType,
        stuckRisk: step.stuckRisk,
      ),
  ]);
});
