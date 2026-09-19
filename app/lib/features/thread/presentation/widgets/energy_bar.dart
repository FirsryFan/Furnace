import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import 'energy_colors.dart';

/// The energy chip in the Thread status bar (blueprint 2.2, user annotation 3).
///
/// It is a BUTTON, not a readout: the shape shows the number only (never
/// "/10") on a red-to-green fill, and tapping it opens the editor with a
/// noded horizontal slider plus a plain-language description of what that
/// level means.
class EnergyBar extends StatelessWidget {
  const EnergyBar({
    super.key,
    required this.energy,
    required this.onChanged,
    this.compact = false,
  });

  /// Current energy 1..10, or null when not set.
  final int? energy;

  /// Called with the new value when the user confirms in the editor.
  final ValueChanged<int> onChanged;

  /// Compact layout for the collapsed status bar.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = energy;
    final label = value == null
        ? l10n.threadEnergyEmpty
        : '${l10n.threadEnergy} $value';
    final size = compact ? const Size(56, 30) : const Size(68, 36);

    return Tooltip(
      message: value == null
          ? l10n.threadEnergy
          : '${l10n.threadEnergy} · ${energyDescriptionText(l10n, value)}',
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Material(
          color: value == null
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : EnergyColors.of(value),
          borderRadius: BorderRadius.circular(size.height / 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(size.height / 2),
            onTap: () =>
                showEnergyEditor(context, energy: value, onChanged: onChanged),
            child: Center(
              child: Text(
                value == null ? '—' : '$value',
                semanticsLabel: label,
                style: TextStyle(
                  color: value == null
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 15 : 17,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the energy editor: a noded horizontal slider whose active colour
/// follows the red-to-green ramp, with the meaning of the current level below.
Future<int?> showEnergyEditor(
  BuildContext context, {
  required int? energy,
  required ValueChanged<int> onChanged,
}) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (context) => _EnergyEditorSheet(
      initial: energy ?? 5,
      onChanged: onChanged,
    ),
  );
}

class _EnergyEditorSheet extends StatefulWidget {
  const _EnergyEditorSheet({required this.initial, required this.onChanged});

  final int initial;
  final ValueChanged<int> onChanged;

  @override
  State<_EnergyEditorSheet> createState() => _EnergyEditorSheetState();
}

class _EnergyEditorSheetState extends State<_EnergyEditorSheet> {
  late int _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = EnergyColors.of(_value);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, color: color),
                const SizedBox(width: 8),
                Text(l10n.threadEnergy,
                    style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: l10n.commonClose,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                IconButton.filled(
                  tooltip: l10n.commonConfirm,
                  icon: const Icon(Icons.check),
                  onPressed: () {
                    widget.onChanged(_value);
                    Navigator.of(context).pop(_value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 46,
                  child: Text(
                    '$_value',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: color,
                      thumbColor: color,
                      inactiveTrackColor:
                          theme.colorScheme.surfaceContainerHighest,
                      trackHeight: 6,
                      showValueIndicator: ShowValueIndicator.onDrag,
                    ),
                    child: Slider(
                      value: _value.toDouble(),
                      min: EnergyColors.min.toDouble(),
                      max: EnergyColors.max.toDouble(),
                      divisions: EnergyColors.max - EnergyColors.min,
                      label: '$_value',
                      onChanged: (v) => setState(() => _value = v.round()),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              energyDescriptionText(l10n, _value),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
