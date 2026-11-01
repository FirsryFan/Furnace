/// The user's default way of judging a new answer, and the value the practice
/// screen's per-answer control starts from.
///
/// Two different things live in this file and must not be confused:
///
///  * [AnswerMode] is the *practice screen's* vocabulary: strict auto, lenient
///    auto, or self. It is what the segmented control shows and what the screen
///    switches between **per answer**.
///  * [JudgeModePreference] is the *persisted* preference: which of those three
///    a freshly opened review starts in. It never overrides the control - a
///    preference that forced a judging mode onto an individual answer would take
///    away the one thing the control exists for.
///
/// The wire values are the same three words (`strict` / `lenient` / `self`) and
/// are written verbatim to `local_settings.anki_judge_mode`. They are explicitly
/// spelled out rather than taken from `Enum.name`, so a later rename of a Dart
/// identifier cannot silently change what an already-written setting means.
///
/// A NULL (or unparsable) stored value resolves to [JudgeModePreference.self].
/// 用户 2026-11-02 的口径是「永远默认用户自判」：老库的 NULL 不回填，读侧回退
/// 到自判；只有用户明确选过严格/宽松的库才保留原值。列仍然可空——「没选过」
/// 与「选了自判」在数据层保持可区分。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/config/furnace_defaults.dart' show TagPath;

/// How one answer is judged, as the practice screen's control offers it.
enum AnswerMode {
  /// The app compares characters exactly (Chinese dictation, English spelling).
  strict,

  /// The app compares tolerantly (`ReviewService.lenientMatch`).
  lenient,

  /// The user judges their own answer after seeing the expected one.
  self,
}

/// The three values of `local_settings.anki_judge_mode`.
enum JudgeModePreference {
  /// Exact comparison. The default, and therefore today's behaviour.
  strict('strict'),

  /// Tolerant comparison.
  lenient('lenient'),

  /// Self-judged: the app shows the answer instead of comparing.
  self('self');

  const JudgeModePreference(this.storageValue);

  /// The exact string stored in the database, and the string the UI writes.
  final String storageValue;

  /// The practice screen's arm of this preference.
  AnswerMode get answerMode => switch (this) {
        JudgeModePreference.strict => AnswerMode.strict,
        JudgeModePreference.lenient => AnswerMode.lenient,
        JudgeModePreference.self => AnswerMode.self,
      };

  /// Reads a stored value back.
  ///
  /// An unknown string (a setting written by a build that knew a fourth mode) or
  /// a NULL (never chosen) both mean [JudgeModePreference.self]: 永远默认用户
  /// 自判。老库不回填，所以升级后的文件不会因为「没写过」而突然变成自动判分。
  static JudgeModePreference fromStorage(String? value) {
    for (final preference in JudgeModePreference.values) {
      if (preference.storageValue == value) {
        return preference;
      }
    }
    return JudgeModePreference.self;
  }
}

/// The app's view of the persisted default judging mode.
///
/// Asynchronous because the value lives in SQLite. The screen reads it once, when
/// it builds the queue; the per-answer control then owns the mode for the rest of
/// the session, so a late-arriving read can never change an answer in progress.
class JudgeModePreferenceController extends AsyncNotifier<JudgeModePreference> {
  @override
  Future<JudgeModePreference> build() =>
      ref.watch(reviewPlanRepositoryProvider).getJudgeModePreference();

  /// Persists the choice and reflects it immediately.
  Future<void> select(JudgeModePreference preference) async {
    state = AsyncData(preference);
    await ref
        .read(reviewPlanRepositoryProvider)
        .setJudgeModePreference(preference);
  }
}

final judgeModePreferenceProvider =
    AsyncNotifierProvider<JudgeModePreferenceController, JudgeModePreference>(
  JudgeModePreferenceController.new,
);

/// The default mode for a queue that is being built **right now**.
///
/// `read` is deliberate, not a shortcut: the practice screen calls this from an
/// event handler (`_load`), and a `watch` there would rebuild the screen - and
/// rebuild the text field under the user's fingers - every time the settings row
/// changes.
///
/// An extension on `WidgetRef` rather than a free function taking `Ref`:
/// `WidgetRef` is not a subtype of `Ref` in this Riverpod version, so a single
/// free function could not serve both a widget and a provider.
extension JudgeModePreferenceRef on WidgetRef {
  /// The persisted default judging mode, or [JudgeModePreference.self] while
  /// the (asynchronous, local) read is still in flight.
  ///
  /// The fallback matches the product default (user self-judging): a queue that
  /// started before the setting arrived must behave like a fresh install, not
  /// like a build that forced automatic grading on everyone.
  JudgeModePreference get judgeModePreference => read(
        judgeModePreferenceProvider,
      ).maybeWhen(
        data: (preference) => preference,
        orElse: () => JudgeModePreference.self,
      );

  /// The mode the practice screen's control starts in.
  AnswerMode get initialAnswerMode => judgeModePreference.answerMode;
}

/// 一个卡组的判分方式覆盖规则：`tags.path` + 该组显式设过的方式。
///
/// 只在 `review_group_plans.judge_mode` 非 NULL 时存在；NULL 表示「跟随全局」，
/// 不产生规则。
class GroupJudgeModeRule {
  const GroupJudgeModeRule({required this.tagPath, required this.mode});

  /// 卡组标签的完整路径（`文化课/数学`）——组覆盖整棵子树。
  final String tagPath;

  /// 这个组显式指定的方式（目前只有 自判 / 严格 两种写法）。
  final JudgeModePreference mode;
}

/// 按卡组覆盖解析一张卡该怎么判。
///
/// 输入是这道卡所属知识点直挂的标签路径，以及所有「显式设过」的卡组规则。
/// 规则：**最深匹配的卡组赢**（`数学/函数` 压过 `数学`）；同深度按路径字典序
/// 取第一条，保证与数据库返回顺序无关。没有任何覆盖 ⇒ null = 跟随全局。
///
/// 纯函数：不读库、不读设置，页面与测试共用同一份口径。
JudgeModePreference? resolveGroupJudgeMode({
  required Iterable<String> knowledgePointTagPaths,
  required Iterable<GroupJudgeModeRule> rules,
}) {
  GroupJudgeModeRule? best;
  for (final rule in rules) {
    final groupPath = rule.tagPath.trim();
    if (groupPath.isEmpty) {
      continue;
    }
    final matches = knowledgePointTagPaths.any(
      (candidate) => TagPath.isSameOrUnder(
        path: groupPath,
        candidate: candidate,
      ),
    );
    if (!matches) {
      continue;
    }
    if (best == null || _isMoreSpecific(rule, best)) {
      best = rule;
    }
  }
  return best?.mode;
}

bool _isMoreSpecific(GroupJudgeModeRule candidate, GroupJudgeModeRule current) {
  final candidatePath = candidate.tagPath.trim();
  final currentPath = current.tagPath.trim();
  if (candidatePath.length != currentPath.length) {
    return candidatePath.length > currentPath.length;
  }
  return candidatePath.compareTo(currentPath) < 0;
}
