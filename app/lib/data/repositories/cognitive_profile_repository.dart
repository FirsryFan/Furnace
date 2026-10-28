import 'dart:convert';

import 'package:drift/drift.dart';

import '../../features/assessment/application/task_registry.dart';
import '../../features/assessment/domain/assessment_models.dart';
import '../database/database.dart';
import '../ids.dart';

/// 评测板块的数据层（schema v41，2026-10-29，《Furnace 用户评测板块设计文档》v1.0）。
///
/// 实现 [AssessmentStore]：界面与运行引擎只认这个抽象，不直接碰 Drift。
/// 八张 `cog_*` 表在这里各有一个读/写入口，映射与任务注册的**出厂内容**来自
/// `features/assessment/application/task_registry.dart`（纯常量，无 IO）：
///
/// * 任务表：按 `design_version` 幂等 seed（升版时整行重写；用户只读）；
/// * 任务→能力、能力→参数映射：**只在表为空时** seed，之后不覆盖（设计文档
///   §7「映射存表可配置」——用户/后续版本改过的权重不能被开机 seed 冲掉）；
/// * 能力估计与认知参数：缺行补默认值（`source: default`，uncertainty 按
///   [kAbilitySpecs] / [kCognitiveParamSpecs]），这样画像页在没测过时也有 10+9
///   行可画，且默认值不被冒充成测量值。
///
/// 纪律（§8.3 / §9）：只更新 [EstimateSources.userOverride] 之外的行由
/// [writeEstimates] 负责；质量标记只上调 uncertainty；本仓库不删任何测量。
class CognitiveProfileRepository implements AssessmentStore {
  CognitiveProfileRepository(
    this._db, {
    List<AssessmentTaskConfig>? defaultTasks,
    List<TaskAbilityMapping>? defaultTaskMappings,
    List<AbilityParamMapping>? defaultAbilityParamMappings,
  })  : _defaultTasks = defaultTasks ?? kDefaultAssessmentTasks,
        _defaultTaskMappings =
            defaultTaskMappings ?? kDefaultTaskAbilityMappings,
        _defaultAbilityParamMappings =
            defaultAbilityParamMappings ?? kDefaultAbilityParamMappings;

  final AppDatabase _db;
  final List<AssessmentTaskConfig> _defaultTasks;
  final List<TaskAbilityMapping> _defaultTaskMappings;
  final List<AbilityParamMapping> _defaultAbilityParamMappings;

  // -------------------------------------------------------------------------
  // seed
  // -------------------------------------------------------------------------

  @override
  Future<void> ensureSeeded({DateTime? now}) async {
    final millis = (now ?? DateTime.now()).millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _seedTasks(millis);
      await _seedMappings();
      await _seedDefaultEstimates(millis);
    });
  }

  Future<void> _seedTasks(int millis) async {
    final existing = await _db.select(_db.cogAssessmentTasks).get();
    final byId = <String, CogAssessmentTaskRow>{
      for (final row in existing) row.id: row,
    };
    for (final task in _defaultTasks) {
      final row = byId[task.taskId];
      final data = CogAssessmentTasksCompanion.insert(
        id: task.taskId,
        displayName: task.displayName,
        taskType: task.taskType.code,
        designVersion: task.designVersion,
        configJson: jsonEncode(<String, Object?>{
          ...task.config,
          'estimated_duration_sec': task.estimatedDurationSeconds,
          'produced_metrics': task.producedMetrics,
          'quality_checks': task.qualityChecks,
          'provisional': task.provisional,
        }),
        enabled: Value(task.enabled),
        createdAt: millis,
      );
      if (row == null) {
        await _db.into(_db.cogAssessmentTasks).insert(data);
        continue;
      }
      // 设计版本变了才重写；版本相同就别每次开机都 UPDATE 一遍。
      if (row.designVersion == task.designVersion) {
        continue;
      }
      await (_db.update(_db.cogAssessmentTasks)
            ..where((t) => t.id.equals(task.taskId)))
          .write(data);
    }
  }

  Future<void> _seedMappings() async {
    final taskCount = await _count(_db.cogTaskAbilityMappings);
    if (taskCount == 0) {
      await _db.batch((batch) {
        batch.insertAll(
            _db.cogTaskAbilityMappings, <CogTaskAbilityMappingsCompanion>[
          for (final mapping in _defaultTaskMappings)
            CogTaskAbilityMappingsCompanion.insert(
              taskId: mapping.taskId,
              abilityId: mapping.abilityId,
              weight: mapping.weight,
              metricSource: mapping.metricSource,
              enabled: Value(mapping.enabled),
              mappingVersion: mapping.mappingVersion,
            ),
        ]);
      });
    }
    final paramCount = await _count(_db.cogAbilityParamMappings);
    if (paramCount == 0) {
      await _db.batch((batch) {
        batch.insertAll(
            _db.cogAbilityParamMappings, <CogAbilityParamMappingsCompanion>[
          for (final mapping in _defaultAbilityParamMappings)
            CogAbilityParamMappingsCompanion.insert(
              abilityId: mapping.abilityId,
              paramId: mapping.paramId,
              weight: mapping.weight,
              direction: mapping.direction,
              enabled: Value(mapping.enabled),
              mappingVersion: mapping.mappingVersion,
            ),
        ]);
      });
    }
  }

  Future<void> _seedDefaultEstimates(int millis) async {
    final abilityRows = await _db.select(_db.cogAbilityEstimates).get();
    final haveAbilities = <String>{
      for (final row in abilityRows) row.abilityId
    };
    for (final spec in kAbilitySpecs) {
      if (haveAbilities.contains(spec.id)) continue;
      await _db.into(_db.cogAbilityEstimates).insert(
            CogAbilityEstimatesCompanion.insert(
              abilityId: spec.id,
              mean: spec.defaultMean,
              uncertainty: spec.defaultUncertainty,
              nMeasurements: 0,
              source: EstimateSources.defaultPrior,
              designVersion: kAssessmentDesignVersion,
              mappingVersion: kAssessmentMappingVersion,
              updatedAt: millis,
            ),
          );
    }
    final paramRows = await _db.select(_db.cogCognitiveParams).get();
    final haveParams = <String>{for (final row in paramRows) row.paramId};
    for (final spec in kCognitiveParamSpecs) {
      if (haveParams.contains(spec.id)) continue;
      await _db.into(_db.cogCognitiveParams).insert(
            CogCognitiveParamsCompanion.insert(
              paramId: spec.id,
              value: spec.defaultValue,
              uncertainty: spec.defaultUncertainty,
              source: EstimateSources.defaultPrior,
              updatedAt: millis,
            ),
          );
    }
  }

  // -------------------------------------------------------------------------
  // 任务
  // -------------------------------------------------------------------------

  @override
  Future<List<AssessmentTaskConfig>> listTasks(
      {bool enabledOnly = true}) async {
    final query = _db.select(_db.cogAssessmentTasks);
    if (enabledOnly) {
      query.where((t) => t.enabled.equals(true));
    }
    final rows = await query.get();
    final order = <String, int>{
      for (var i = 0; i < _defaultTasks.length; i++) _defaultTasks[i].taskId: i,
    };
    rows.sort((a, b) {
      final left = order[a.id] ?? 1 << 20;
      final right = order[b.id] ?? 1 << 20;
      return left != right ? left - right : a.id.compareTo(b.id);
    });
    return <AssessmentTaskConfig>[for (final row in rows) _taskOf(row)];
  }

  AssessmentTaskConfig _taskOf(CogAssessmentTaskRow row) {
    final config = _decodeMap(row.configJson) ?? const <String, Object?>{};
    final type = AssessmentTaskType.fromCode(row.taskType);
    return AssessmentTaskConfig(
      taskId: row.id,
      displayName: row.displayName,
      // 未知类型不猜：回落到 choice_reaction（引擎会按配置字段运行）；
      // 正常库里不会出现，只有手改库才会。
      taskType: type ?? AssessmentTaskType.choiceReaction,
      estimatedDurationSeconds:
          _readInt(config['estimated_duration_sec']) ?? 180,
      designVersion: row.designVersion,
      config: config,
      producedMetrics: _readStringList(config['produced_metrics']),
      qualityChecks: _readStringList(config['quality_checks']),
      enabled: row.enabled,
      provisional: config['provisional'] == true,
    );
  }

  // -------------------------------------------------------------------------
  // 会话
  // -------------------------------------------------------------------------

  @override
  Future<String> recordSession({
    required String taskId,
    required String designVersion,
    required String device,
    required DateTime startedAt,
    required DateTime completedAt,
    required String status,
    required List<TrialResult> trials,
    required List<MetricSample> metrics,
    List<String> qualityFlags = const <String>[],
  }) async {
    final sessionId = Ids.next('cog');
    await _db.transaction(() async {
      await _db.into(_db.cogAssessmentSessions).insert(
            CogAssessmentSessionsCompanion.insert(
              id: sessionId,
              taskId: taskId,
              designVersion: designVersion,
              device: device,
              startedAt: startedAt.millisecondsSinceEpoch,
              completedAt: Value(completedAt.millisecondsSinceEpoch),
              status: status,
              qualityFlagsJson: Value(_encodeStringList(qualityFlags)),
            ),
          );
      if (trials.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAll(
            _db.cogAssessmentTrials,
            <CogAssessmentTrialsCompanion>[
              for (final trial in trials)
                CogAssessmentTrialsCompanion.insert(
                  sessionId: sessionId,
                  trialIndex: trial.trialIndex,
                  blockIndex: trial.blockIndex,
                  stimulusJson: jsonEncode(trial.stimulus),
                  responseJson: Value(jsonEncode(trial.response)),
                  rtMs: Value(trial.rtMs),
                  correct: Value(trial.correct),
                  isPractice: Value(trial.isPractice),
                  timestamp:
                      (trial.timestamp ?? completedAt).millisecondsSinceEpoch,
                ),
            ],
          );
        });
      }
      if (metrics.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAll(
            _db.cogAssessmentMetrics,
            <CogAssessmentMetricsCompanion>[
              for (final metric in metrics)
                CogAssessmentMetricsCompanion.insert(
                  sessionId: sessionId,
                  metricName: metric.name,
                  value: metric.value,
                  nTrials: metric.nTrials,
                  qualityFlagsJson: Value(
                    _encodeStringList(metric.qualityFlags),
                  ),
                ),
            ],
          );
        });
      }
    });
    return sessionId;
  }

  @override
  Future<List<AssessmentSessionSummary>> readSessions({int limit = 20}) async {
    if (limit <= 0) {
      return const <AssessmentSessionSummary>[];
    }
    final rows = await (_db.select(_db.cogAssessmentSessions)
          ..orderBy([
            (t) => OrderingTerm.desc(t.startedAt),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(limit))
        .get();
    if (rows.isEmpty) {
      return const <AssessmentSessionSummary>[];
    }
    final metrics = await _metricsFor(rows.map((row) => row.id).toList());
    return <AssessmentSessionSummary>[
      for (final row in rows) _summaryOf(row, metrics[row.id] ?? const []),
    ];
  }

  @override
  Future<AssessmentSessionSummary?> readSession(String sessionId) async {
    final row = await (_db.select(_db.cogAssessmentSessions)
          ..where((t) => t.id.equals(sessionId)))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    final metrics = await _metricsFor(<String>[sessionId]);
    return _summaryOf(row, metrics[sessionId] ?? const <MetricSample>[]);
  }

  Future<Map<String, List<MetricSample>>> _metricsFor(
    List<String> sessionIds,
  ) async {
    if (sessionIds.isEmpty) {
      return const <String, List<MetricSample>>{};
    }
    final rows = await (_db.select(_db.cogAssessmentMetrics)
          ..where((t) => t.sessionId.isIn(sessionIds)))
        .get();
    final grouped = <String, List<MetricSample>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.sessionId, () => <MetricSample>[]).add(
            MetricSample(
              name: row.metricName,
              value: row.value,
              nTrials: row.nTrials,
              qualityFlags: _decodeStringList(row.qualityFlagsJson),
            ),
          );
    }
    return grouped;
  }

  AssessmentSessionSummary _summaryOf(
    CogAssessmentSessionRow row,
    List<MetricSample> metrics,
  ) {
    return AssessmentSessionSummary(
      sessionId: row.id,
      taskId: row.taskId,
      designVersion: row.designVersion,
      device: row.device,
      startedAt: DateTime.fromMillisecondsSinceEpoch(row.startedAt),
      completedAt: row.completedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.completedAt!),
      status: row.status,
      qualityFlags: _decodeStringList(row.qualityFlagsJson),
      metrics: metrics,
    );
  }

  // -------------------------------------------------------------------------
  // 能力估计 / 认知参数
  // -------------------------------------------------------------------------

  @override
  Future<List<AbilityEstimate>> readAbilities() async {
    final rows = await _db.select(_db.cogAbilityEstimates).get();
    final byId = <String, CogAbilityEstimateRow>{
      for (final row in rows) row.abilityId: row,
    };
    return <AbilityEstimate>[
      for (final spec in kAbilitySpecs)
        byId[spec.id] == null
            ? AbilityEstimate(
                abilityId: spec.id,
                mean: spec.defaultMean,
                uncertainty: spec.defaultUncertainty,
                nMeasurements: 0,
                source: EstimateSources.defaultPrior,
              )
            : _abilityOf(byId[spec.id]!),
    ];
  }

  AbilityEstimate _abilityOf(CogAbilityEstimateRow row) {
    return AbilityEstimate(
      abilityId: row.abilityId,
      mean: row.mean,
      uncertainty: row.uncertainty,
      nMeasurements: row.nMeasurements,
      source: row.source,
      designVersion: row.designVersion,
      mappingVersion: row.mappingVersion,
      personalBaseline:
          _decodeMap(row.personalBaselineJson) ?? const <String, Object?>{},
      device: row.device ?? AssessmentDevices.unknown,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
      stale: row.stale,
      contributions: _decodeContributions(row.contributionsJson),
    );
  }

  @override
  Future<List<ParamEstimate>> readCognitiveParams() async {
    final rows = await _db.select(_db.cogCognitiveParams).get();
    final byId = <String, CogCognitiveParamRow>{
      for (final row in rows) row.paramId: row,
    };
    return <ParamEstimate>[
      for (final spec in kCognitiveParamSpecs)
        byId[spec.id] == null
            ? ParamEstimate(
                paramId: spec.id,
                value: spec.defaultValue,
                uncertainty: spec.defaultUncertainty,
                source: EstimateSources.defaultPrior,
              )
            : _paramOf(byId[spec.id]!),
    ];
  }

  ParamEstimate _paramOf(CogCognitiveParamRow row) {
    return ParamEstimate(
      paramId: row.paramId,
      value: row.value,
      uncertainty: row.uncertainty,
      source: row.source,
      derivedFrom: _decodeDerivedFrom(row.derivedFromJson),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
    );
  }

  @override
  Future<void> writeEstimates({
    List<AbilityEstimate> abilities = const <AbilityEstimate>[],
    List<ParamEstimate> params = const <ParamEstimate>[],
  }) async {
    if (abilities.isEmpty && params.isEmpty) {
      return;
    }
    await _db.transaction(() async {
      for (final ability in abilities) {
        final existing = await (_db.select(_db.cogAbilityEstimates)
              ..where((t) => t.abilityId.equals(ability.abilityId)))
            .getSingleOrNull();
        if (existing != null &&
            existing.source == EstimateSources.userOverride) {
          // 用户手动覆盖过：自动合并到此为止（设计文档 §5「用户可覆盖」）。
          continue;
        }
        await _db.into(_db.cogAbilityEstimates).insertOnConflictUpdate(
              CogAbilityEstimatesCompanion.insert(
                abilityId: ability.abilityId,
                mean: ability.mean,
                uncertainty: ability.uncertainty,
                nMeasurements: ability.nMeasurements,
                source: ability.source,
                designVersion: ability.designVersion,
                mappingVersion: ability.mappingVersion,
                personalBaselineJson: Value(
                  ability.personalBaseline.isEmpty
                      ? null
                      : jsonEncode(ability.personalBaseline),
                ),
                device: Value(
                  ability.device == AssessmentDevices.unknown
                      ? null
                      : ability.device,
                ),
                updatedAt: (ability.updatedAt ?? DateTime.now())
                    .millisecondsSinceEpoch,
                stale: Value(ability.stale),
                contributionsJson: Value(
                  ability.contributions.isEmpty
                      ? null
                      : jsonEncode(<Object?>[
                          for (final contribution in ability.contributions)
                            <String, Object?>{
                              'task_id': contribution.taskId,
                              'weight': contribution.weight,
                              'metric': contribution.metric,
                            },
                        ]),
                ),
              ),
            );
      }
      for (final param in params) {
        final existing = await (_db.select(_db.cogCognitiveParams)
              ..where((t) => t.paramId.equals(param.paramId)))
            .getSingleOrNull();
        if (existing != null &&
            existing.source == EstimateSources.userOverride) {
          continue;
        }
        await _db.into(_db.cogCognitiveParams).insertOnConflictUpdate(
              CogCognitiveParamsCompanion.insert(
                paramId: param.paramId,
                value: param.value,
                uncertainty: param.uncertainty,
                source: param.source,
                derivedFromJson: Value(
                  param.derivedFrom.isEmpty
                      ? null
                      : jsonEncode(<Object?>[
                          for (final source in param.derivedFrom)
                            <String, Object?>{
                              'ability_id': source.abilityId,
                              'weight': source.weight,
                            },
                        ]),
                ),
                updatedAt:
                    (param.updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
              ),
            );
      }
    });
  }

  // -------------------------------------------------------------------------
  // 用户覆盖
  // -------------------------------------------------------------------------

  @override
  Future<void> setAbilityUserOverride({
    required String abilityId,
    required double mean,
  }) async {
    final spec = _abilitySpecFor(abilityId);
    final existing = await (_db.select(_db.cogAbilityEstimates)
          ..where((t) => t.abilityId.equals(abilityId)))
        .getSingleOrNull();
    final millis = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.cogAbilityEstimates).insertOnConflictUpdate(
          CogAbilityEstimatesCompanion.insert(
            abilityId: abilityId,
            // 能力是 z-score 量纲：界面限 -5..5，存储侧再夹一次。
            mean: mean.clamp(-5.0, 5.0).toDouble(),
            uncertainty: existing?.uncertainty ??
                spec?.defaultUncertainty ??
                kDefaultAbilityUncertainty,
            nMeasurements: existing?.nMeasurements ?? 0,
            source: EstimateSources.userOverride,
            designVersion: existing?.designVersion ?? kAssessmentDesignVersion,
            mappingVersion:
                existing?.mappingVersion ?? kAssessmentMappingVersion,
            personalBaselineJson: Value(existing?.personalBaselineJson),
            device: Value(existing?.device),
            updatedAt: millis,
            stale: Value(existing?.stale ?? false),
            contributionsJson: Value(existing?.contributionsJson),
          ),
        );
  }

  @override
  Future<void> setParamUserOverride({
    required String paramId,
    required double value,
  }) async {
    final existing = await (_db.select(_db.cogCognitiveParams)
          ..where((t) => t.paramId.equals(paramId)))
        .getSingleOrNull();
    final millis = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.cogCognitiveParams).insertOnConflictUpdate(
          CogCognitiveParamsCompanion.insert(
            paramId: paramId,
            // 参数是 0..1 的模型内变量：界面校验之外再夹一次。
            value: value.clamp(0.0, 1.0).toDouble(),
            uncertainty: existing?.uncertainty ??
                _paramSpecFor(paramId)?.defaultUncertainty ??
                kDefaultAbilityUncertainty,
            source: EstimateSources.userOverride,
            derivedFromJson: Value(existing?.derivedFromJson),
            updatedAt: millis,
          ),
        );
  }

  @override
  Future<void> clearAbilityUserOverride({required String abilityId}) async {
    final existing = await (_db.select(_db.cogAbilityEstimates)
          ..where((t) => t.abilityId.equals(abilityId)))
        .getSingleOrNull();
    if (existing == null || existing.source != EstimateSources.userOverride) {
      return;
    }
    final nextSource = existing.nMeasurements > 0
        ? EstimateSources.assessment
        : EstimateSources.defaultPrior;
    await (_db.update(_db.cogAbilityEstimates)
          ..where((t) => t.abilityId.equals(abilityId)))
        .write(
      CogAbilityEstimatesCompanion(
        source: Value(nextSource),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  @override
  Future<void> clearParamUserOverride({required String paramId}) async {
    final existing = await (_db.select(_db.cogCognitiveParams)
          ..where((t) => t.paramId.equals(paramId)))
        .getSingleOrNull();
    if (existing == null || existing.source != EstimateSources.userOverride) {
      return;
    }
    final nextSource = existing.derivedFromJson == null
        ? EstimateSources.defaultPrior
        : EstimateSources.derived;
    await (_db.update(_db.cogCognitiveParams)
          ..where((t) => t.paramId.equals(paramId)))
        .write(
      CogCognitiveParamsCompanion(
        source: Value(nextSource),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 映射
  // -------------------------------------------------------------------------

  @override
  Future<List<TaskAbilityMapping>> readTaskAbilityMappings({
    bool enabledOnly = true,
  }) async {
    final query = _db.select(_db.cogTaskAbilityMappings);
    if (enabledOnly) {
      query.where((t) => t.enabled.equals(true));
    }
    final rows = await (query..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    return <TaskAbilityMapping>[
      for (final row in rows)
        TaskAbilityMapping(
          taskId: row.taskId,
          abilityId: row.abilityId,
          weight: row.weight,
          metricSource: row.metricSource,
          enabled: row.enabled,
          mappingVersion: row.mappingVersion,
        ),
    ];
  }

  @override
  Future<List<AbilityParamMapping>> readAbilityParamMappings({
    bool enabledOnly = true,
  }) async {
    final query = _db.select(_db.cogAbilityParamMappings);
    if (enabledOnly) {
      query.where((t) => t.enabled.equals(true));
    }
    final rows = await (query..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    return <AbilityParamMapping>[
      for (final row in rows)
        AbilityParamMapping(
          abilityId: row.abilityId,
          paramId: row.paramId,
          weight: row.weight,
          direction: row.direction,
          enabled: row.enabled,
          mappingVersion: row.mappingVersion,
        ),
    ];
  }

  // -------------------------------------------------------------------------
  // 小工具
  // -------------------------------------------------------------------------

  Future<int> _count(TableInfo<Table, dynamic> table) async {
    final count = _db.selectOnly(table)
      ..addColumns([const Constant(1).count()]);
    return count
        .map((row) => row.read(const Constant(1).count()) ?? 0)
        .getSingle();
  }

  AbilitySpec? _abilitySpecFor(String abilityId) {
    for (final spec in kAbilitySpecs) {
      if (spec.id == abilityId) return spec;
    }
    return null;
  }

  CognitiveParamSpec? _paramSpecFor(String paramId) {
    for (final spec in kCognitiveParamSpecs) {
      if (spec.id == paramId) return spec;
    }
    return null;
  }

  static Map<String, Object?>? _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return <String, Object?>{
          for (final entry in decoded.entries) '${entry.key}': entry.value,
        };
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static List<String> _decodeStringList(String? raw) {
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return <String>[
          for (final item in decoded)
            if (item is String && item.trim().isNotEmpty) item,
        ];
      }
    } on FormatException {
      return const <String>[];
    }
    return const <String>[];
  }

  static String? _encodeStringList(List<String> values) {
    final cleaned = <String>[
      for (final value in values)
        if (value.trim().isNotEmpty) value,
    ];
    return cleaned.isEmpty ? null : jsonEncode(cleaned);
  }

  static List<AbilityContribution> _decodeContributions(String? raw) {
    if (raw == null || raw.isEmpty) return const <AbilityContribution>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return <AbilityContribution>[
          for (final item in decoded)
            if (item is Map && item['task_id'] is String)
              AbilityContribution(
                taskId: '${item['task_id']}',
                weight: _readDouble(item['weight']) ?? 0,
                metric: '${item['metric'] ?? ''}',
              ),
        ];
      }
    } on FormatException {
      return const <AbilityContribution>[];
    }
    return const <AbilityContribution>[];
  }

  static List<ParamSourceWeight> _decodeDerivedFrom(String? raw) {
    if (raw == null || raw.isEmpty) return const <ParamSourceWeight>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return <ParamSourceWeight>[
          for (final item in decoded)
            if (item is Map && item['ability_id'] is String)
              ParamSourceWeight(
                abilityId: '${item['ability_id']}',
                weight: _readDouble(item['weight']) ?? 0,
              ),
        ];
      }
    } on FormatException {
      return const <ParamSourceWeight>[];
    }
    return const <ParamSourceWeight>[];
  }

  static double? _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static List<String> _readStringList(Object? value) {
    if (value is List) {
      return <String>[
        for (final item in value)
          if (item is String && item.trim().isNotEmpty) item,
      ];
    }
    return const <String>[];
  }
}
