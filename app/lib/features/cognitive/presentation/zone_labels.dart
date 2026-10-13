/// The two words this app uses for a reading: the band a card sits in and the
/// zone its knowledge point is in.
///
/// This vocabulary lives in one file because two surfaces show it - the
/// "认知模型" readings page and the review screen (which shows the zone of the
/// card being reviewed). Two copies would drift, and a drifted label is a lie:
/// the same `ReviewZone.deadEnd` must read the same on both screens.
///
/// Both switches are exhaustive on purpose. A new band or zone in
/// `ReviewAdvisory` stops compiling here instead of silently rendering nothing.
library;

import '../../../l10n/app_localizations.dart';
import '../../anki/application/review_advisory.dart';

/// Band vocabulary, exhaustive on purpose: a fifth band in `ReviewAdvisory`
/// stops compiling here instead of silently rendering nothing.
String bandLabel(AppLocalizations l10n, ReviewBand band) => switch (band) {
      ReviewBand.forced => l10n.cognitiveBandForced,
      ReviewBand.boosted => l10n.cognitiveBandBoosted,
      ReviewBand.model => l10n.cognitiveBandModel,
      ReviewBand.unseen => l10n.cognitiveBandUnseen,
    };

/// Zone vocabulary, exhaustive on purpose (all nine `ReviewZone` values are
/// named, including [ReviewZone.unavailable] and [ReviewZone.healthy]).
String zoneLabel(AppLocalizations l10n, ReviewZone zone) => switch (zone) {
      ReviewZone.proximal => l10n.cognitiveZoneProximal,
      ReviewZone.empty => l10n.cognitiveZoneEmpty,
      ReviewZone.deadEnd => l10n.cognitiveZoneDeadEnd,
      ReviewZone.slow => l10n.cognitiveZoneSlow,
      ReviewZone.overload => l10n.cognitiveZoneOverload,
      ReviewZone.offGoal => l10n.cognitiveZoneOffGoal,
      ReviewZone.danger => l10n.cognitiveZoneDanger,
      ReviewZone.healthy => l10n.cognitiveZoneHealthy,
      ReviewZone.unavailable => l10n.cognitiveZoneUnavailable,
    };
