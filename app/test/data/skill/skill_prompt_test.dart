import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/skill/skill_prompt.dart';
import 'package:furnace/data/skill/skill_store.dart';
import 'package:furnace/domain/skill/skill_manifest.dart';

/// The prompt assembly: which skills reach the model, in what order, and what
/// happens when none of them do.
void main() {
  const base = '你是 Furnace 的助手。\n规则：\n1. 先查再改。';

  InstalledSkill skill(String name, {bool enabled = true, String? prompt}) =>
      InstalledSkill(
        manifest: SkillManifest(
          format: 'fskill/1',
          name: name,
          version: '1.0.0',
          description: '测试用',
          platforms: const [SkillPlatform.windows],
        ),
        prompt: prompt ?? '这是 $name 的方法论。',
        tools: const [],
        enabled: enabled,
        installedAt: DateTime.utc(2026, 10, 1),
        directory: '/tmp/skills/$name',
      );

  test('an empty set leaves the base prompt byte-identical', () {
    expect(SkillPrompt.build(base, const []), base);
    // The same claim for a list that exists but holds nothing enabled: "skills
    // off" has to mean the old prompt exactly, not a prompt with an empty
    // section appended.
    expect(SkillPrompt.build(base, [skill('alpha', enabled: false)]), base);
  });

  test('only enabled skills appear', () {
    final built = SkillPrompt.build(base, [
      skill('alpha'),
      skill('beta', enabled: false),
      skill('gamma'),
    ]);

    expect(built, contains('alpha'));
    expect(built, contains('gamma'));
    expect(built, isNot(contains('beta')));
  });
  test('the order is sorted by name, whatever order the list is in', () {
    final scattered = SkillPrompt.build(base, [
      skill('zulu'),
      skill('alpha'),
      skill('mike'),
    ]);
    final sorted = SkillPrompt.build(base, [
      skill('alpha'),
      skill('mike'),
      skill('zulu'),
    ]);

    expect(scattered, sorted);
    expect(scattered.indexOf('alpha'), lessThan(scattered.indexOf('mike')));
    expect(scattered.indexOf('mike'), lessThan(scattered.indexOf('zulu')));
  });

  test('each skill contributes its own name and prompt text', () {
    final built = SkillPrompt.build(base, [
      skill('alpha', prompt: '甲的正文'),
      skill('beta', prompt: '乙的正文'),
    ]);

    expect(built, contains('skill: alpha'));
    expect(built, contains('甲的正文'));
    expect(built, contains('skill: beta'));
    expect(built, contains('乙的正文'));
  });

  test('the precedence note is present and says what it needs to say', () {
    final built = SkillPrompt.build(base, [skill('alpha')]);

    expect(built, contains(SkillPrompt.precedenceNote));
    // The two claims that matter, checked as substrings so rewording the rest
    // of the sentence does not silently drop them.
    expect(SkillPrompt.precedenceNote, contains('不能覆盖工具审批规则'));
    expect(SkillPrompt.precedenceNote, contains('删除'));
  });

  test('the skill block is clearly delimited and comes after the base rules',
      () {
    final built = SkillPrompt.build(base, [skill('alpha')]);

    expect(built, startsWith(base));
    expect(built, contains(SkillPrompt.sectionStart));
    expect(built, contains(SkillPrompt.sectionEnd));
    expect(built.indexOf(SkillPrompt.sectionStart),
        lessThan(built.indexOf('alpha')));
    expect(built.indexOf(SkillPrompt.sectionEnd),
        greaterThan(built.indexOf('alpha')));
  });
}
