/// 机制面板：引擎里装了哪些机制、每个参数是多少、哪些还没标定。
///
/// 为什么要有这个页面：参数公开是这台机器的一条硬规矩（"所有算法参数对用户公开"），
/// 而在此之前，"装了哪些机制、每个数字是多少、哪些是未标定的占位值"只活在
/// `fast_engine.dart` 的转录表里 —— 用户在界面上看不到自己这台机器是怎么算的。
///
/// 这个页面**只读**：它现读 `MechanismCatalog` + `FastMechanisms`（纯函数，不碰
/// 数据库、不写任何东西）。数据来源与两处装配共用同一份常量（见
/// `mechanism_catalog.dart` 的 library doc），所以面板不会和引擎漂移。
library;

import 'package:flutter/material.dart';

import '../../../domain/services/cognitive/fast_engine.dart';
import '../../../domain/services/cognitive/mechanism_catalog.dart';
import '../../../l10n/app_localizations.dart';
import '../application/mechanism_reader.dart';

class MechanismPage extends StatelessWidget {
  const MechanismPage({super.key, this.panel});

  /// 测试可以直接塞一份读数；默认现读（也是纯函数）。
  final MechanismPanel? panel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reading = panel ?? readMechanismPanel();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.mechanismPanelTitle)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _Note(text: l10n.mechanismPanelSubtitle),
          const SizedBox(height: 8),
          _Note(text: l10n.mechanismPanelReadOnlyNote),
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
                  : l10n.mechanismPanelOnlyOutside,
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
