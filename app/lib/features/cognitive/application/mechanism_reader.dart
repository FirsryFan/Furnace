/// 机制面板要显示的读数：引擎的装配 + 每个机制的参数 + 未标定的那些。
///
/// 为什么要有这个文件：页面不该自己拼 `FastMechanisms` —— 怎么拼就是"装了哪些机制"，
/// 页面另写一份就会和引擎漂移。这里只做一件事：把 `MechanismCatalog`（装配的事实）
/// 和 `FastMechanisms`（参数的转录表）变成可以直接画的行，页面不做任何判断。
///
/// 值的口径：`value` 是这一跑实际用的值（覆盖 > `module_defaults` > 转录默认值），
/// `transcribed` 是转录来的那一份（用空 `module_defaults` 单独读一遍，因为
/// `fromModuleDefaults` 会把传进来的默认值写进 `FastParamSpec.defaultValue`），
/// `overridden` 是 `FastMechanisms.overrides` 里写了这个路径 —— 应用只有一处覆盖：
/// `attention.ignition.T_ign = 0`（D3 去随机源）。`fromSetting` 是另一回事：用户自己
/// 在滑块上调过的值（`local_settings.goal_beta`），它走 `module_defaults` 进来。
library;

import '../../../domain/services/cognitive/fast_engine.dart';
import '../../../domain/services/cognitive/mechanism_catalog.dart';

/// 一个参数在面板上的一行。
class MechanismParamRow {
  const MechanismParamRow({
    required this.path,
    required this.key,
    required this.value,
    required this.transcribed,
    required this.overridden,
    required this.calibrated,
    required this.unit,
    required this.desc,
    required this.evidence,
    this.fromSetting = false,
    this.min,
    this.max,
  });

  /// 内核的参数路径，如 `attention.capacity.W_DAR`。
  final String path;
  final String key;

  /// 这一跑实际用的值（有覆盖就是覆盖值）。
  final double value;

  /// 转录来的默认值（`FastParamSpec.defaultValue`）。
  final double transcribed;

  final bool overridden;

  /// `true` = 这个值是**用户自己调的**（`local_settings.goal_beta`），不是转录来的
  /// 默认值。和 [overridden] 分开：覆盖是应用为 D3 钉的死值，这个是用户的滑块。
  final bool fromSetting;

  /// `false` = **未标定**：没有标定来源，是量级合理的占位值。
  final bool calibrated;

  final String unit;
  final double? min;
  final double? max;
  final String desc;
  final String evidence;

  String get valueText => _withUnit(value);

  String get transcribedText => _withUnit(transcribed);

  String get rangeText {
    if (min == null && max == null) {
      return '—';
    }
    final low = min == null ? '—' : _num(min!);
    final high = max == null ? '—' : _num(max!);
    return '$low ~ $high';
  }

  /// 没有量纲的参数（`unit == '-'`）只写数字，不拖一个空单位的尾巴。
  String _withUnit(double raw) =>
      unit == '-' ? _num(raw) : '${_num(raw)} $unit';
}

/// 一个机制在面板上的一段。
class MechanismRow {
  const MechanismRow({
    required this.id,
    required this.params,
    required this.installedIn,
    this.disabledIn = const <String>[],
  });

  /// 机制 id，如 `memory.dsr`。
  final String id;

  /// 它声明的参数（`memory.dsr` 一个都没有 —— 它只维护状态袋）。
  final List<MechanismParamRow> params;

  /// 装了它的装配 id（空 = 不装进任何引擎）。
  final List<String> installedIn;

  /// 出厂会装、但**被用户开关关掉**的装配 id。它不在 [installedIn] 里，
  /// 两个清单分开列，面板才能把"你关掉了"和"本来就没装"分开说。
  final List<String> disabledIn;

  bool get installed => installedIn.isNotEmpty;

  /// 用户把这个机制关掉了（出厂会装，现在不装）。
  bool get disabledBySetting => disabledIn.isNotEmpty;

  int get uncalibratedCount =>
      params.where((final param) => !param.calibrated).length;

  int get overriddenCount =>
      params.where((final param) => param.overridden).length;
}

/// 面板的全部读数。
class MechanismPanel {
  const MechanismPanel({
    required this.setups,
    required this.mechanisms,
    required this.moduleDefaults,
    this.goalMechanismEnabled = true,
    this.goalBeta,
  });

  final List<MechanismSetup> setups;
  final List<MechanismRow> mechanisms;

  /// 这一跑用的 `module_defaults`（应用传空表；用户调过滑块时里面只有
  /// `context.goal.beta_goal` 一个键）。
  final Map<String, Object?> moduleDefaults;

  /// 读这一份面板时生效的开关值（`local_settings.goal_mechanism_enabled`
  /// 的 NULL 已在读取处折成 true）。面板自己把它画出来，页面不再猜。
  final bool goalMechanismEnabled;

  /// 读这一份面板时生效的滑块值（`local_settings.goal_beta`）。
  ///
  /// `null` = 用户从没调过，这一跑用的是转录表里的出厂值（[MechanismParamRow.transcribed]）。
  /// 页面据此画滑块的位置和"出厂 / 你调的"两种状态，不去反推。
  final double? goalBeta;

  int get paramCount =>
      mechanisms.fold(0, (sum, row) => sum + row.params.length);

  int get uncalibratedCount =>
      mechanisms.fold(0, (sum, row) => sum + row.uncalibratedCount);

  int get overriddenCount =>
      mechanisms.fold(0, (sum, row) => sum + row.overriddenCount);
}

/// 读一次面板：装配按 `MechanismCatalog`，参数按 `FastMechanisms` 的转录表。
///
/// [goalMechanismEnabled] 就是 `local_settings.goal_mechanism_enabled` 折成
/// 布尔之后的值（NULL → true）。它只改一件事：库诊断那一跑装不装目标机制。
/// 读数必须跟着它变，否则用户关掉之后面板还在说"装了"。
///
/// [goalBeta] 是另一个设置（`local_settings.goal_beta`，NULL = 出厂值）。它不改变
/// 装了什么，只改 `context.goal.beta_goal` 的数字，所以它折进 [moduleDefaults]
/// 之后再走同一个参数表 —— 页面上的 `value` 就是引擎真的会用的那个值。
MechanismPanel readMechanismPanel({
  Map<String, Object?> moduleDefaults = const <String, Object?>{},
  bool goalMechanismEnabled = true,
  double? goalBeta,
}) {
  final effectiveDefaults = MechanismCatalog.libraryDiagnosisDefaults(
    moduleDefaults: moduleDefaults,
    goalBeta: goalBeta,
  );
  final mechanisms = FastMechanisms.fromModuleDefaults(
    effectiveDefaults,
    ids: MechanismCatalog.allIds,
    overrides: MechanismCatalog.transcribedIgnition,
  );
  // 转录默认值必须单独读一份：`fromModuleDefaults` 会把传进来的 `module_defaults`
  // 写进 `defaultValue`，那一份读到的已经不是"转录"了。
  final transcribed = FastMechanisms.fromModuleDefaults(
    const <String, Object?>{},
    ids: MechanismCatalog.allIds,
  );
  return MechanismPanel(
    setups: MechanismCatalog.setupsWith(
      goalMechanismEnabled: goalMechanismEnabled,
    ),
    goalMechanismEnabled: goalMechanismEnabled,
    goalBeta: goalBeta,
    mechanisms: <MechanismRow>[
      for (final id in MechanismCatalog.allIds)
        MechanismRow(
          id: id,
          installedIn: MechanismCatalog.setupsInstalling(
            id,
            goalMechanismEnabled: goalMechanismEnabled,
          ),
          disabledIn: MechanismCatalog.setupsDisabledBySetting(
            id,
            goalMechanismEnabled: goalMechanismEnabled,
          ),
          params: <MechanismParamRow>[
            for (final spec in mechanisms.specs)
              if (spec.mechanism == id)
                MechanismParamRow(
                  path: spec.path,
                  key: spec.key,
                  value: _overrideValue(mechanisms.overrides, spec),
                  transcribed: transcribed.specOf(spec.path)?.defaultValue ??
                      spec.defaultValue,
                  overridden: mechanisms.overrides.containsKey(spec.path),
                  fromSetting: goalBeta != null &&
                      spec.path == MechanismCatalog.goalBetaPath,
                  calibrated: spec.calibrated,
                  unit: spec.unit,
                  min: spec.min,
                  max: spec.max,
                  desc: spec.desc,
                  evidence: spec.evidence,
                ),
          ],
        ),
    ],
    moduleDefaults: effectiveDefaults,
  );
}

double _overrideValue(Map<String, Object?> overrides, FastParamSpec spec) {
  final raw = overrides[spec.path];
  return raw is num ? raw.toDouble() : spec.defaultValue;
}

/// 面板上的数字写法：整数不带小数点，其余照写（0.05 就写 0.05）。
String _num(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';
