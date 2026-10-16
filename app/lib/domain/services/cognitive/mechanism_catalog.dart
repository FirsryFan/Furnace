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

  /// 请求演练那一跑（`rehearseRun` → `executeRun`）：把一份 `mindnet.run/1`
  /// 请求真的 apply 进引擎。
  static const String runRehearsal = 'run_rehearsal';

  /// 点火阈值退化成硬阈值（D3）：不掷随机数，才和一致性向量逐位可比。
  static const Map<String, Object?> transcribedIgnition = <String, Object?>{
    'attention.ignition.T_ign': 0,
  };

  /// 目标机制里那个"牵引多强"的参数（`context.goal.beta_goal`）—— roadmap §3
  /// 第 8 行的**第一个滑块**。
  ///
  /// Q57 那个开关说的是"装不装这个机制"，这个滑块说的是"装的话牵引多强"：
  /// 0 = 完全不牵引，0.3 是转录表里的值（`calibrated: false`，即未标定的占位值）。
  static const String goalBetaKey = 'beta_goal';

  /// 参数全路径（内核按 `机制.key` 寻值）。
  static const String goalBetaPath = '${FastMechanisms.goal}.$goalBetaKey';

  /// 用户滑块上的值要不要进这一跑的 `module_defaults`。
  ///
  /// [installedIds] 是这一跑**实际**要装的机制清单：只有装了 `context.goal`
  /// 的跑才谈得上"牵引多强"（演练那一跑只装记忆层，给它这个键就是撒谎）。
  ///
  /// [goalBeta] 为 null = 用户从没调过，原样返回 [moduleDefaults]（出厂行为一个字
  /// 不变）。有值就只补这一个键：别的机制没有滑块，也不该在这里被悄悄改掉。
  ///
  /// 走 `module_defaults` 而不是 `overrides`：覆盖那一层是**应用自己**为 D3
  /// （去随机源）钉的死值，面板把"应用覆盖"和"用户调的"分开说，混在一起就再也
  /// 分不出一个值是谁定的。
  static Map<String, Object?> goalBetaDefaults({
    required List<String> installedIds,
    Map<String, Object?> moduleDefaults = const <String, Object?>{},
    double? goalBeta,
  }) {
    if (goalBeta == null || !installedIds.contains(FastMechanisms.goal)) {
      return moduleDefaults;
    }
    final goal = (moduleDefaults[FastMechanisms.goal] as Map?)
            ?.cast<String, Object?>() ??
        const <String, Object?>{};
    return <String, Object?>{
      ...moduleDefaults,
      FastMechanisms.goal: <String, Object?>{...goal, goalBetaKey: goalBeta},
    };
  }

  /// 题目定价那一跑（`ProblemEvaluator`）用的 `module_defaults`：按它**实际**装的
  /// 清单（[problemEvaluatorIds]，里面有 `context.goal`）折一遍 —— 与库诊断那一跑
  /// **同一条**规则（[goalBetaDefaults]），不是各写一份。
  static Map<String, Object?> problemEvaluatorDefaults({
    Map<String, Object?> moduleDefaults = const <String, Object?>{},
    double? goalBeta,
  }) =>
      goalBetaDefaults(
        installedIds: problemEvaluatorIds,
        moduleDefaults: moduleDefaults,
        goalBeta: goalBeta,
      );

  static const List<String> libraryDiagnosisIds = <String>[
    FastMechanisms.shunting,
    FastMechanisms.capacity,
    FastMechanisms.ignition,
    FastMechanisms.goal,
  ];

  /// 库诊断那一跑**实际**会装的 id —— 目标机制那一个是用户可关的
  /// （`local_settings.goal_mechanism_enabled`，roadmap §3 第 8 行的第一个用户侧开关）。
  ///
  /// [goalEnabled] 为 false 时只去掉 `context.goal` 一个：别的机制没开关，
  /// 也不该在这里悄悄跟着变。
  static List<String> libraryDiagnosisIdsFor({required bool goalEnabled}) =>
      goalEnabled
          ? libraryDiagnosisIds
          : <String>[
              for (final id in libraryDiagnosisIds)
                if (id != FastMechanisms.goal) id,
            ];

  /// 比库诊断多一层记忆：它不注册 `round.*` 钩子，逐轮数值不变。
  static const List<String> problemEvaluatorIds = <String>[
    FastMechanisms.shunting,
    FastMechanisms.capacity,
    FastMechanisms.ignition,
    FastMechanisms.goal,
    FastMechanisms.memory,
  ];

  /// 请求演练只 **apply** 动作、不跑轮次（`executeRun` 不调 `runRounds`），所以
  /// 四个逐轮机制在这里一个也用不上：只有复习/再读要动记忆袋，所以只装记忆层。
  static const List<String> runRehearsalIds = <String>[
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
    MechanismSetup(
      id: runRehearsal,
      installedIds: runRehearsalIds,
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
  ///
  /// [goalMechanismEnabled] 是**当前设置**：库诊断那一跑装不装目标机制由用户
  /// 说了算，所以"面板说装在哪几处"和"引擎真的装了哪几个"必须用同一个入参，
  /// 否则面板会在用户关掉之后继续声称装了它。
  static List<String> setupsInstalling(
    String mechanismId, {
    bool goalMechanismEnabled = true,
  }) =>
      <String>[
        for (final setup
            in setupsWith(goalMechanismEnabled: goalMechanismEnabled))
          if (setup.installedIds.contains(mechanismId)) setup.id,
      ];

  /// 出厂会装、但被**当前设置**关掉的那几处装配（用来在面板上把"你关掉了"和
  /// "本来就没装"分开说 —— 两者结论一样、原因不一样）。
  ///
  /// 它说的是**此刻**的差别：开关打开时这份清单是空的（用户没有关掉任何东西，
  /// 面板就不该再挂着"你关掉了"）。所以入参必须传当前设置，不能默认成"关"。
  static List<String> setupsDisabledBySetting(
    String mechanismId, {
    bool goalMechanismEnabled = true,
  }) {
    final shipped = setupsInstalling(mechanismId);
    final current = setupsInstalling(
      mechanismId,
      goalMechanismEnabled: goalMechanismEnabled,
    );
    return <String>[
      for (final id in shipped)
        if (!current.contains(id)) id,
    ];
  }

  /// 当前设置下的三处装配。今天只有库诊断那一跑会变，别的原样返回。
  static List<MechanismSetup> setupsWith({
    required bool goalMechanismEnabled,
  }) {
    if (goalMechanismEnabled) {
      return setups;
    }
    return <MechanismSetup>[
      for (final setup in setups)
        if (setup.id != libraryDiagnosis)
          setup
        else
          MechanismSetup(
            id: setup.id,
            installedIds: libraryDiagnosisIdsFor(goalEnabled: false),
            overrides: setup.overrides,
          ),
    ];
  }
}
