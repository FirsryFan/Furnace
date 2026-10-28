/// 认知画像导出 JSON（设计文档 v1.0 §10.2；纯逻辑）。
///
/// 把本机聚合出的能力估计与认知参数估计打包成一份可导出的 JSON。
/// 设计约束：
///
/// * 不含题干、答题原文、聊天记录、账号或设备标识，只有聚合估计；
/// * 时间由调用方注入（[buildCogProfile] 的 `exportedAt`），函数不读时钟；
/// * 输出键序固定，便于 diff 与快照测试；
/// * 数值做净化：mean 非有限 → 0，uncertainty/value 夹 0–1，n_measurements 负数 → 0。
library;

import 'dart:convert';

import 'assessment_models.dart';

/// 认知画像 JSON 的格式版本（与设计文档 §10.2 对齐）。
const String kCogProfileFormatVersion = '1.0';

/// 默认隐私声明（中文，写入 `privacy` 字段）。
const String kCogProfilePrivacyZh = '本文件只包含本机聚合出的能力估计与认知参数，不含题干原文、答题原文、'
    '聊天记录、账号或设备标识；是否分享由你自行决定。';

/// 生成认知画像 JSON 对象；键序固定为
/// `format_version / exported_at / design_version / mapping_version /
/// abilities / cognitive_params / privacy`。
///
/// * `abilities` 按 [AbilityIds.all] 排序，未知 id 排后面（字典序）；
/// * `cognitive_params` 按 [CognitiveParamIds.all] 排序，未知 id 排后面（字典序）；
/// * 同 id 出现多次时取**最后一条**（与「后写覆盖先写」的存储语义一致）。
Map<String, Object?> buildCogProfile({
  required List<AbilityEstimate> abilities,
  required List<ParamEstimate> cognitiveParams,
  required DateTime exportedAt,
  String designVersion = kAssessmentDesignVersion,
  String mappingVersion = kAssessmentMappingVersion,
  String privacy = kCogProfilePrivacyZh,
}) {
  final abilityById = <String, AbilityEstimate>{};
  for (final ability in abilities) {
    final id = ability.abilityId.trim();
    if (id.isEmpty) continue;
    abilityById[id] = ability;
  }
  final orderedAbilityIds = _orderedIds(
    abilityById.keys,
    AbilityIds.all,
  );
  final abilityEntries = <Map<String, Object?>>[];
  for (final id in orderedAbilityIds) {
    final ability = abilityById[id]!;
    abilityEntries.add(<String, Object?>{
      'ability_id': id,
      'mean': _finiteOr(ability.mean, 0.0),
      'uncertainty': _clamp01(ability.uncertainty, 1.0),
      'n_measurements': ability.nMeasurements < 0 ? 0 : ability.nMeasurements,
      'source': _normalizedSource(ability.source),
    });
  }
  final paramById = <String, ParamEstimate>{};
  for (final param in cognitiveParams) {
    final id = param.paramId.trim();
    if (id.isEmpty) continue;
    paramById[id] = param;
  }
  final orderedParamIds = _orderedIds(
    paramById.keys,
    CognitiveParamIds.all,
  );
  final paramEntries = <Map<String, Object?>>[];
  for (final id in orderedParamIds) {
    final param = paramById[id]!;
    paramEntries.add(<String, Object?>{
      'param_id': id,
      'value': _clamp01(param.value, 0.5),
      'uncertainty': _clamp01(param.uncertainty, 1.0),
      'source': _normalizedSource(param.source),
    });
  }
  return <String, Object?>{
    'format_version': kCogProfileFormatVersion,
    'exported_at': exportedAt.toUtc().toIso8601String(),
    'design_version': designVersion,
    'mapping_version': mappingVersion,
    'abilities': List<Map<String, Object?>>.unmodifiable(abilityEntries),
    'cognitive_params': List<Map<String, Object?>>.unmodifiable(paramEntries),
    'privacy': privacy,
  };
}

/// 把 [buildCogProfile] 的结果编码成 JSON 文本；`pretty` 为真时两空格缩进。
String encodeCogProfile(Map<String, Object?> profile, {bool pretty = true}) {
  if (!pretty) return jsonEncode(profile);
  return const JsonEncoder.withIndent('  ').convert(profile);
}

/// 已知 id 按 [knownOrder] 排序，未知 id 排后面按字典序。
List<String> _orderedIds(Iterable<String> ids, List<String> knownOrder) {
  final all = ids.toList();
  final ordered = <String>[];
  for (final id in knownOrder) {
    if (all.contains(id)) ordered.add(id);
  }
  final extras = all.where((id) => !knownOrder.contains(id)).toList()..sort();
  ordered.addAll(extras);
  return ordered;
}

double _finiteOr(double value, double fallback) {
  return value.isFinite ? value : fallback;
}

double _clamp01(double value, double fallback) {
  if (!value.isFinite) return fallback;
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}

String _normalizedSource(String source) {
  final trimmed = source.trim();
  return trimmed.isEmpty ? EstimateSources.defaultPrior : trimmed;
}
