import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';

/// Red -> green energy ramp (blueprint 2.2, user annotation 3).
///
/// The user asked for a colour bar that matches the number, so the ramp is
/// shared by the status-bar chip and the editor slider. Hue goes 0deg (red) at
/// energy 1 to 120deg (green) at energy 10; saturation/value are fixed so the
/// chip keeps enough contrast for the white number it carries.
abstract final class EnergyColors {
  static const int min = 1;
  static const int max = 10;

  /// Ramp colour for [energy] (clamped to 1..10).
  static Color of(int energy) {
    final clamped = energy.clamp(min, max);
    final t = (clamped - min) / (max - min);
    final hue = 120.0 * t;
    return HSVColor.fromAHSV(1, hue, 0.72, 0.82).toColor();
  }

  /// A darker variant used for the number's shadow ring on light colours.
  static Color borderOf(int energy) => of(energy).withValues(alpha: 0.85);

  /// Colour for a fractional value in [0,1] (used by the parameter meters).
  static Color ofRatio(double ratio) {
    final t = ratio.clamp(0.0, 1.0);
    return HSVColor.fromAHSV(1, 120.0 * t, 0.72, 0.82).toColor();
  }
}

/// Semantics of each energy level, shown under the editor slider. The number
/// is authoritative; this text only helps the user pick it.
String energyDescription(int energy) {
  if (energy <= 2) {
    return 'energy1';
  }
  if (energy <= 4) {
    return 'energy3';
  }
  if (energy <= 6) {
    return 'energy5';
  }
  if (energy <= 8) {
    return 'energy7';
  }
  return 'energy9';
}

/// The localized plain-language meaning of [energy] (1..10).
String energyDescriptionText(AppLocalizations l10n, int energy) {
  switch (energyDescription(energy)) {
    case 'energy1':
      return l10n.threadEnergy1;
    case 'energy3':
      return l10n.threadEnergy3;
    case 'energy5':
      return l10n.threadEnergy5;
    case 'energy7':
      return l10n.threadEnergy7;
    default:
      return l10n.threadEnergy9;
  }
}
