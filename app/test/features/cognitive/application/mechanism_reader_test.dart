/// 机制面板的读数（roadmap 切片 6 的下一步（十九）：参数公开）。
///
/// 这一份读数存在的理由只有一个：**面板说的必须就是引擎正在用的那一份**。所以这里
/// 钉的不是"页面长什么样"，而是两条对齐：① 面板列出的机制/参数 = `FastMechanisms`
/// 的转录表；② 面板列出的装配 = `library_diagnosis` / `problem_evaluator` 真正传给
/// `fromModuleDefaults` 的 id 清单（两者共用 `MechanismCatalog`，这些断言就是防它被
/// 谁改坏）。另外钉住两条"如实说"：`rhythm.gate` 不装进任何引擎、`memory.dsr` 没有号参数。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cognitive/fast_engine.dart';
import 'package:furnace/domain/services/cognitive/mechanism_catalog.dart';
import 'package:furnace/features/cognitive/application/mechanism_reader.dart';

void main() {
  test('六个机制按固定顺序列出，一个不多一个不少', () {
    final panel = readMechanismPanel();
    expect(
      [for (final row in panel.mechanisms) row.id],
      MechanismCatalog.allIds,
    );
    expect(MechanismCatalog.allIds, hasLength(6));
  });

  test('面板的参数 = FastMechanisms 转录表里的那几条（路径逐条对齐）', () {
    final mechanisms = FastMechanisms.fromModuleDefaults(
      const <String, Object?>{},
      ids: MechanismCatalog.allIds,
    );
    final panel = readMechanismPanel();
    final fromPanel = <String>[
      for (final row in panel.mechanisms)
        for (final param in row.params) param.path,
    ];
    expect(fromPanel, [for (final spec in mechanisms.specs) spec.path]);
    expect(panel.paramCount, mechanisms.specs.length);
  });

  test('未标定的个数与引擎侧同一个口径', () {
    final mechanisms = FastMechanisms.fromModuleDefaults(
      const <String, Object?>{},
      ids: MechanismCatalog.allIds,
    );
    final panel = readMechanismPanel();
    expect(panel.uncalibratedCount, mechanisms.uncalibrated.length);
    expect(panel.uncalibratedCount, greaterThan(0));
  });

  test('三处装配装的东西：库诊断四个、题目定价多一层记忆、演练只装记忆', () {
    final panel = readMechanismPanel();
    final byId = <String, MechanismRow>{
      for (final row in panel.mechanisms) row.id: row,
    };
    expect(
      byId[FastMechanisms.memory]!.installedIn,
      <String>[
        MechanismCatalog.problemEvaluator,
        MechanismCatalog.runRehearsal,
      ],
    );
    expect(
      byId[FastMechanisms.goal]!.installedIn,
      <String>[
        MechanismCatalog.libraryDiagnosis,
        MechanismCatalog.problemEvaluator,
      ],
    );
  });

  test('点火阈值被覆盖成 0：值是 0，转录默认值仍是 0.05', () {
    final panel = readMechanismPanel();
    final ignition = panel.mechanisms
        .singleWhere((final row) => row.id == FastMechanisms.ignition);
    final tIgn =
        ignition.params.singleWhere((final param) => param.key == 'T_ign');
    expect(tIgn.value, 0);
    expect(tIgn.transcribed, 0.05);
    expect(tIgn.overridden, isTrue);
    expect(
      MechanismCatalog.transcribedIgnition,
      <String, Object?>{tIgn.path: 0},
    );
  });

  test('别的参数没有被覆盖：值就是转录默认值', () {
    final panel = readMechanismPanel();
    final capacity = panel.mechanisms
        .singleWhere((final row) => row.id == FastMechanisms.capacity);
    final wDar =
        capacity.params.singleWhere((final param) => param.key == 'W_DAR');
    expect(wDar.overridden, isFalse);
    expect(wDar.value, wDar.transcribed);
    expect(wDar.calibrated, isTrue, reason: 'Cowan/Oberauer 有出处');
  });

  test('如实说：节律闸门不装进任何引擎', () {
    final panel = readMechanismPanel();
    final rhythm = panel.mechanisms
        .singleWhere((final row) => row.id == FastMechanisms.rhythm);
    expect(rhythm.installed, isFalse);
    expect(rhythm.installedIn, isEmpty);
    expect(MechanismCatalog.rhythmOutsideEngines, FastMechanisms.rhythm);
  });

  test('如实说：记忆层没有号参数，只有状态袋', () {
    final panel = readMechanismPanel();
    final memory = panel.mechanisms
        .singleWhere((final row) => row.id == FastMechanisms.memory);
    expect(memory.params, isEmpty);
    expect(memory.installed, isTrue);
  });

  test('module_defaults 传了值：实际值变，转录默认值不变', () {
    final panel = readMechanismPanel(
      moduleDefaults: <String, Object?>{
        FastMechanisms.capacity: <String, Object?>{'W_DAR': 7.0},
      },
    );
    final capacity = panel.mechanisms
        .singleWhere((final row) => row.id == FastMechanisms.capacity);
    final wDar =
        capacity.params.singleWhere((final param) => param.key == 'W_DAR');
    expect(wDar.value, 7.0);
    expect(wDar.transcribed, 4.0);
    expect(wDar.overridden, isFalse, reason: '不是 overrides 覆盖的，是 defaults');
  });

  test('每次读都长一样（面板不依赖时间/随机）', () {
    final first = readMechanismPanel();
    final second = readMechanismPanel();
    expect(
      [for (final row in first.mechanisms) row.id],
      [for (final row in second.mechanisms) row.id],
    );
    expect(first.paramCount, second.paramCount);
  });
}
