/// The engine setups this app actually builds, in one place.
///
/// Why this file exists: the panel that answers "引擎里装了哪些机制、每个参数是多少、
/// 哪些还没标定" must not be a second copy of the call sites — a second copy drifts,
/// and then the panel lies about the engine. `library_diagnosis.dart` and
/// `problem_evaluator.dart` take their id list and their overrides from here, and
/// a test pins the values, so the panel and the two engines cannot disagree.
///
/// Not everything in the mechanism vocabulary is an engine setup: `rhythm.gate`
/// only lives inside the rhythm reading (`StudyRhythm.read` builds a `RhythmGate`
/// directly) and is never installed into an engine. The catalog says that instead
/// of counting it as installed.
library;

import 'fast_engine.dart';

/// One engine setup: the mechanism ids it installs, and its parameter overrides.
class MechanismSetup {
  const MechanismSetup({
    required this.id,
    required this.installedIds,
    required this.overrides,
  });

  /// Stable id (`library_diagnosis` / `problem_evaluator`).
  final String id;

  /// Mechanism ids handed to `FastMechanisms.fromModuleDefaults`, in order.
  final List<String> installedIds;

  /// Path → value overrides, handed to both the parameter set and the engine.
  final Map<String, Object?> overrides;
}

/// The app's engine setups and the mechanism vocabulary, as data.
abstract final class MechanismCatalog {
  /// 库诊断那一跑（`LibraryDiagnosisRunner.run`）。
  static const String libraryDiagnosis = 'library_diagnosis';

  /// 题目定价那一跑（`ProblemEvaluator`）。
  static const String problemEvaluator = 'problem_evaluator';

  /// 点火阈值退化成硬阈值（D3）：不掷随机数，才和一致性向量逐位可比。
  static const Map<String, Object?> transcribedIgnition = <String, Object?>{
    'attention.ignition.T_ign': 0,
  };

  static const List<String> libraryDiagnosisIds = <String>[
    FastMechanisms.shunting,
    FastMechanisms.capacity,
    FastMechanisms.ignition,
    FastMechanisms.goal,
  ];

  /// 比库诊断多一层记忆：它不注册 `round.*` 钩子，逐轮数值不变。
  static const List<String> problemEvaluatorIds = <String>[
    FastMechanisms.shunting,
    FastMechanisms.capacity,
    FastMechanisms.ignition,
    FastMechanisms.goal,
    FastMechanisms.memory,
  ];

  static const List<MechanismSetup> setups = <MechanismSetup>[
    MechanismSetup(
      id: libraryDiagnosis,
      installedIds: libraryDiagnosisIds,
      overrides: transcribedIgnition,
    ),
    MechanismSetup(
      id: problemEvaluator,
      installedIds: problemEvaluatorIds,
      overrides: transcribedIgnition,
    ),
  ];

  /// 引擎之外的机制：`rhythm.gate` 只活在节律读数里。
  static const String rhythmOutsideEngines = FastMechanisms.rhythm;

  /// 机制词汇表的顺序（面板按这个顺序列，每次跑都长一样）。
  static const List<String> allIds = <String>[
    FastMechanisms.shunting,
    FastMechanisms.capacity,
    FastMechanisms.ignition,
    FastMechanisms.goal,
    FastMechanisms.rhythm,
    FastMechanisms.memory,
  ];

  /// 装了这个机制的那几处装配（空 = 只在引擎之外活着）。
  static List<String> setupsInstalling(String mechanismId) => <String>[
        for (final setup in setups)
          if (setup.installedIds.contains(mechanismId)) setup.id,
      ];
}
