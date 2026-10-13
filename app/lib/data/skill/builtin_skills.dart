/// The skills that ship *inside* the app, as one list.
///
/// Two of them are real jobs the app's AI is expected to do - finding exam
/// questions on 组卷网 and coaching 议论文 writing - and the third is
/// `sample_skill.dart`, the echo tool that exists so the script container can be
/// verified on the user's machine.
///
/// They are packages rather than hard-coded prompt fragments because that is
/// what the `.fskill` format is for: installing one is an ordinary install, it
/// can be switched off or removed like any other set of files, and the card
/// shows exactly what was installed. Nothing here bypasses `SkillStore`.
library;

import 'argumentative_writing_skill.dart';
import 'builtin_skill.dart';
import 'sample_skill.dart';
import 'zujuan_finder_skill.dart';

abstract final class BuiltinSkills {
  /// The sample skill. It keeps the card's own dedicated button rather than
  /// appearing in [cardEntries], because its point is "does the container work
  /// here at all" rather than "here is a job you can now do".
  static const BuiltinSkill sample = BuiltinSkill(
    name: SampleSkill.name,
    title: '示例 skill',
    summary: SampleSkill.description,
    build: SampleSkill.build,
  );

  /// The built-ins the card lists with one install button each, in show order.
  static const List<BuiltinSkill> cardEntries = [
    BuiltinSkill(
      name: ZujuanFinderSkill.name,
      title: '组卷网找题',
      summary: ZujuanFinderSkill.description,
      build: ZujuanFinderSkill.build,
    ),
    BuiltinSkill(
      name: ArgumentativeWritingSkill.name,
      title: '议论文写作',
      summary: ArgumentativeWritingSkill.description,
      build: ArgumentativeWritingSkill.build,
    ),
  ];

  /// Every package that ships with the app.
  static const List<BuiltinSkill> all = [sample, ...cardEntries];
}
