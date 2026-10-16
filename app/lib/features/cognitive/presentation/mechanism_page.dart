/// 机制面板：引擎里装了哪些机制、每个参数是多少、哪些还没标定。
///
/// 为什么要有这个页面：参数公开是这台机器的一条硬规矩（"所有算法参数对用户公开"），
/// 而在此之前，"装了哪些机制、每个数字是多少、哪些是未标定的占位值"只活在
/// `fast_engine.dart` 的转录表里 —— 用户在界面上看不到自己这台机器是怎么算的。
///
/// 装配与参数现读 `MechanismCatalog` + `FastMechanisms`（纯函数），数据来源与两处
/// 装配共用同一份常量（见 `mechanism_catalog.dart` 的 library doc），所以面板不会和
/// 引擎漂移。
///
/// 这个页面**只写一个设置**（`local_settings.goal_mechanism_enabled`，roadmap §3
/// 第 8 行"用户侧开关"的第一个）：库诊断那一跑装不装目标机制。别的都不写。
/// 页面上的读数跟着这个开关变 —— 用户关掉之后，面板不能还声称装了它。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/cognitive/fast_engine.dart';
import '../../../domain/services/cognitive/mechanism_catalog.dart';
import '../../../l10n/app_localizations.dart';
import '../application/mechanism_reader.dart';

/// 当前设置下的面板读数：装配按 `MechanismCatalog`，参数按 `FastMechanisms`。
///
/// 开关一翻就 invalidate 它，面板当场重画 —— 与线程页那个注意力读数开关
/// （`studyRhythmProvider`）同一个做法。
final mechanismPanelProvider = FutureProvider<MechanismPanel>((ref) async {
  final settings = await ref.watch(settingsRepositoryProvider).getSettings();
  return readMechanismPanel(
    goalMechanismEnabled: settings?.goalMechanismEnabled ?? true,
  );
});

/// 那个开关当前的值。列为 NULL（用户从没选过）读作"装"：那是这个开关出现之前
/// 所有版本的行为，升级不能替用户改掉。
final goalMechanismEnabledProvider = FutureProvider<bool>((ref) async {
  final settings = await ref.watch(settingsRepositoryProvider).getSettings();
  return settings?.goalMechanismEnabled ?? true;
});

class MechanismPage extends ConsumerStatefulWidget {
  const MechanismPage({
    super.key,
    this.panel,
    this.onGoalMechanismChanged,
  });

  /// 测试可以直接塞一份读数；默认现读（`mechanismPanelProvider`）。
  final MechanismPanel? panel;

  /// 测试钩子：给了就不写库，只回调（注入的读数由调用方决定怎么变）。
  final Future<void> Function(bool enabled)? onGoalMechanismChanged;

  @override
  ConsumerState<MechanismPage> createState() => _MechanismPageState();
}

class _MechanismPageState extends ConsumerState<MechanismPage> {
  /// 用户刚翻的那个值。写库是异步的、读回来还要一次往返，先把它画出来，
  /// 免得开关自己弹回去；写入失败也不静默 —— 库里没落值，下一次读还是旧值。
  bool? _picked;

  Future<void> _setGoalMechanismEnabled(bool enabled) async {
    setState(() => _picked = enabled);
    final hook = widget.onGoalMechanismChanged;
    if (hook != null) {
      await hook(enabled);
      return;
    }
    if (widget.panel != null) {
      // 注入了读数 = 这份读数由调用方负责；页面不去写库。
      return;
    }
    await ref
        .read(settingsRepositoryProvider)
        .updateGoalMechanismEnabled(enabled);
    ref.invalidate(goalMechanismEnabledProvider);
    ref.invalidate(mechanismPanelProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final injected = widget.panel;
    if (injected != null) {
      return _scaffold(
        l10n,
        injected,
        _picked ?? injected.goalMechanismEnabled,
      );
    }
    final async = ref.watch(mechanismPanelProvider);
    final reading = async.valueOrNull;
    if (reading == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.mechanismPanelTitle)),
        body: Center(
          child: async.hasError
              ? Text('${async.error}')
              : const CircularProgressIndicator(),
        ),
      );
    }
    return _scaffold(l10n, reading, _picked ?? reading.goalMechanismEnabled);
  }

  Widget _scaffold(
    AppLocalizations l10n,
    MechanismPanel reading,
    bool goalEnabled,
  ) {
    return Scaffold(
      appBar: AppBar(title: Text(l10n.mechanismPanelTitle)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _Note(text: l10n.mechanismPanelSubtitle),
          const SizedBox(height: 8),
          _Note(text: l10n.mechanismPanelReadOnlyNote),
          const SizedBox(height: 12),
          _GoalSwitch(
            l10n: l10n,
            enabled: goalEnabled,
            onChanged: _setGoalMechanismEnabled,
          ),
          const SizedBox(height: 12),
          _SectionTitle(text: l10n.mechanismPanelSetupsHeader),
          for (final setup in reading.setups)
            _SetupCard(l10n: l10n, setup: setup),
          const SizedBox(height: 12),
          _SectionTitle(text: l10n.mechanismPanelMechanismsHeader),
          for (final row in reading.mechanisms)
            _MechanismCard(l10n: l10n, row: row),
          const SizedBox(height: 12),
          _Note(
            text: l10n.mechanismPanelSummary(
              reading.paramCount,
              reading.uncalibratedCount,
            ),
          ),
        ],
      ),
    );
  }
}

/// 那个开关：装不装目标机制。文案必须说清关掉之后会变什么，否则这个开关
/// 就只是"一个可以乱按的东西"。
class _GoalSwitch extends StatelessWidget {
  const _GoalSwitch({
    required this.l10n,
    required this.enabled,
    required this.onChanged,
  });

  final AppLocalizations l10n;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: SwitchListTile(
        value: enabled,
        onChanged: onChanged,
        title: Text(l10n.mechanismSwitchGoalTitle),
        subtitle: Text(
          l10n.mechanismSwitchGoalBody,
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.bodySmall);
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.l10n, required this.setup});

  final AppLocalizations l10n;
  final MechanismSetup setup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = <String>[
      for (final id in setup.installedIds) mechanismName(l10n, id),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              setupName(l10n, setup.id),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.mechanismPanelSetupCount(setup.installedIds.length),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(
              names.join(l10n.mechanismPanelNameSeparator),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            if (setup.overrides.isEmpty)
              _Note(text: l10n.mechanismPanelNoOverrides)
            else ...[
              _Note(text: l10n.mechanismPanelOverridesHeader),
              for (final entry in setup.overrides.entries)
                Text(
                  '${entry.key} = ${_num(entry.value)}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MechanismCard extends StatelessWidget {
  const _MechanismCard({required this.l10n, required this.row});

  final AppLocalizations l10n;
  final MechanismRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installedIn = <String>[
      for (final id in row.installedIn) setupName(l10n, id),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mechanismName(l10n, row.id),
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(row.id, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            _Note(
              text: row.installed
                  ? '${l10n.mechanismPanelInstalledIn}'
                      '${installedIn.join(l10n.mechanismPanelNameSeparator)}'
                  : row.disabledBySetting
                      ? l10n.mechanismDisabledBySetting
                      : l10n.mechanismPanelOnlyOutside,
            ),
            // 「还装在某几处」和「在另一处被关掉了」可以同时为真（目标机制就是：
            // 题目定价那一跑仍然要用它）。两句话都要说，否则用户翻开关时看不到
            // 这一处到底被拿掉了什么。
            if (row.installed && row.disabledBySetting)
              _Note(
                text: '${l10n.mechanismDisabledBySetting}'
                    '${l10n.mechanismPanelNameSeparator}'
                    '${row.disabledIn.map((final id) => setupName(l10n, id)).join(l10n.mechanismPanelNameSeparator)}',
              ),
            const SizedBox(height: 8),
            if (row.params.isEmpty)
              _Note(text: l10n.mechanismPanelNoParams)
            else
              for (final param in row.params)
                _ParamTile(l10n: l10n, param: param),
          ],
        ),
      ),
    );
  }
}

class _ParamTile extends StatelessWidget {
  const _ParamTile({required this.l10n, required this.param});

  final AppLocalizations l10n;
  final MechanismParamRow param;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(param.path, style: theme.textTheme.bodyMedium),
              ),
              Text(param.valueText, style: theme.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Badge(
                text: param.calibrated
                    ? l10n.mechanismPanelCalibrated
                    : l10n.mechanismPanelUncalibrated,
                tone: param.calibrated ? _Tone.ok : _Tone.warn,
              ),
              if (param.overridden)
                _Badge(
                  text: l10n.mechanismPanelOverridden,
                  tone: _Tone.info,
                ),
              if (param.overridden)
                Text(
                  '${l10n.mechanismPanelTranscribed} ${param.transcribedText}',
                  style: theme.textTheme.bodySmall,
                ),
              Text(
                '${l10n.mechanismPanelRange} ${param.rangeText}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          if (param.desc.isNotEmpty)
            Text(param.desc, style: theme.textTheme.bodySmall),
          if (param.evidence.isNotEmpty)
            Text(
              param.evidence,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
        ],
      ),
    );
  }
}

enum _Tone { ok, warn, info }

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.tone});

  final String text;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (tone) {
      _Tone.ok => theme.colorScheme.primary,
      _Tone.warn => theme.colorScheme.error,
      _Tone.info => theme.colorScheme.tertiary,
    };
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(color: color),
    );
  }
}

/// 机制 id → 界面上的名字（id 是内核的，名字是给人看的）。
String mechanismName(AppLocalizations l10n, String id) => switch (id) {
      FastMechanisms.shunting => l10n.mechanismNameShunting,
      FastMechanisms.capacity => l10n.mechanismNameCapacity,
      FastMechanisms.ignition => l10n.mechanismNameIgnition,
      FastMechanisms.goal => l10n.mechanismNameGoal,
      FastMechanisms.rhythm => l10n.mechanismNameRhythm,
      FastMechanisms.memory => l10n.mechanismNameMemory,
      _ => id,
    };

/// 装配 id → 界面上的名字。
String setupName(AppLocalizations l10n, String id) => switch (id) {
      MechanismCatalog.libraryDiagnosis => l10n.mechanismSetupLibraryDiagnosis,
      MechanismCatalog.problemEvaluator => l10n.mechanismSetupProblemEvaluator,
      MechanismCatalog.runRehearsal => l10n.mechanismSetupRunRehearsal,
      _ => id,
    };

String _num(Object? value) {
  if (value is! num) {
    return '$value';
  }
  final asDouble = value.toDouble();
  return asDouble == asDouble.roundToDouble()
      ? asDouble.toStringAsFixed(0)
      : '$asDouble';
}
