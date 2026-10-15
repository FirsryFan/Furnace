/// 题库页面共用的词汇表标签。
///
/// `sourceLevel` / `state` 这两组取值在收题页、详情页、筛选 chip 上都要显示成
/// 同一句中文，所以放在一个地方——两处各写一份 switch，改一处忘一处就会出现
/// 「同一道题在两个页面显示成两种状态」这种看不出来的错。
library;

import '../../../l10n/app_localizations.dart';

/// 来源分级的中文名。未知值**原样返回**而不是硬塞一个「未知」类别里：
/// 词汇表是会长的，看到没见过的字符串比被静默归类成 unknown 有用。
String sourceLevelLabel(AppLocalizations l10n, String level) => switch (level) {
      'gaokao' => l10n.questionIntakeSourceGaokao,
      'provincial_diagnostic' => l10n.questionIntakeSourceProvincialDiagnostic,
      'elite_school' => l10n.questionIntakeSourceEliteSchool,
      'school' => l10n.questionIntakeSourceSchool,
      'personal' => l10n.questionIntakeSourcePersonal,
      'unknown' => l10n.questionIntakeSourceUnknown,
      _ => level.isEmpty ? l10n.questionIntakeSourceUnknown : level,
    };

/// 加工状态的中文名。同样地，`raw` 是默认档，未知值原样返回。
String stateLabel(AppLocalizations l10n, String state) => switch (state) {
      'raw' => l10n.questionIntakeStateRaw,
      'structured' => l10n.questionIntakeStateStructured,
      'processed' => l10n.questionIntakeStateProcessed,
      _ => state.isEmpty ? l10n.questionIntakeStateRaw : state,
    };
