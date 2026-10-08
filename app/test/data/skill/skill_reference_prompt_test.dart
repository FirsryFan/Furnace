import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/skill/skill_prompt.dart';
import 'package:furnace/data/skill/skill_store.dart';
import 'package:furnace/domain/skill/skill_manifest.dart';
import 'package:path/path.dart' as p;

/// A skill's `references/**` files, and the caps that keep them affordable.
///
/// The prompt of a real skill is an index into its references ("见
/// references/url-syntax.md"), so a container that injects only `prompt.md`
/// leaves the model with pointers it cannot follow. These tests pin down that
/// the files arrive - and that they cannot arrive unbounded, because this text
/// is prepended to every request of every turn.
void main() {
  const base = '你是 Furnace 的助手。\n规则：\n1. 先查再改。';
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fskill_prompt_');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  InstalledSkill skill(
    String name, {
    bool enabled = true,
    required String directory,
  }) =>
      InstalledSkill(
        manifest: SkillManifest(
          format: 'fskill/1',
          name: name,
          version: '1.0.0',
          description: '测试用',
          platforms: const [SkillPlatform.windows],
        ),
        prompt: '这是 $name 的方法论。',
        tools: const [],
        enabled: enabled,
        installedAt: DateTime.utc(2026, 10, 1),
        directory: directory,
      );

  /// Writes a skill directory with the given references (path -> content).
  String skillDir(String name, Map<String, String> references) {
    final dir = Directory(p.join(root.path, name))..createSync(recursive: true);
    for (final entry in references.entries) {
      final file = File(p.join(dir.path, entry.key));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
    return dir.path;
  }

  test('reference files are injected with their paths, sorted', () {
    final directory = skillDir('alpha', {
      'references/b-second.md': '第二份参考',
      'references/a-first.md': '第一份参考',
      'references/nested/c-third.md': '第三份参考',
      'prompt.md': '不在 references 里，不该被重复注入',
    });

    final built = SkillPrompt.build(base, [skill('alpha', directory: directory)]);

    expect(built, contains('references/a-first.md'));
    expect(built, contains('第一份参考'));
    expect(built, contains('references/b-second.md'));
    expect(built, contains('references/nested/c-third.md'));
    expect(
      built.indexOf('references/a-first.md'),
      lessThan(built.indexOf('references/b-second.md')),
      reason: 'stable order keeps the prompt byte-identical between turns',
    );
    expect(
      built,
      isNot(contains('不在 references 里')),
      reason: 'only the references directory is inlined; prompt.md is already in',
    );
  });

  test('a skill without references adds nothing and does not throw', () {
    final dir = Directory(p.join(root.path, 'plain'))..createSync(recursive: true);

    final built = SkillPrompt.build(base, [skill('plain', directory: dir.path)]);

    expect(built, contains('这是 plain 的方法论。'));
    expect(built, isNot(contains('参考文件')));
  });

  test('an unreadable references directory is skipped, not fatal', () {
    final built = SkillPrompt.build(base, [
      skill('ghost', directory: p.join(root.path, 'does-not-exist')),
    ]);

    expect(built, contains('这是 ghost 的方法论。'));
  });

  test('one huge reference file is cut, with a marker', () {
    final directory = skillDir('big', {
      'references/huge.md': 'x' * (SkillPrompt.maxReferenceBytes + 5000),
    });

    final built = SkillPrompt.build(base, [skill('big', directory: directory)]);

    expect(built, contains('已截断：单文件上限'));
    expect(
      built.length,
      lessThan(base.length + SkillPrompt.maxSectionBytes + 4096),
    );
  });

  test('many references in one skill stop at the per-skill cap', () {
    final references = <String, String>{
      for (var i = 0; i < 8; i++)
        'references/file$i.md': 'y' * SkillPrompt.maxReferenceBytes,
    };
    final directory = skillDir('heavy', references);

    final built = SkillPrompt.build(base, [skill('heavy', directory: directory)]);

    expect(built, contains('参考内容超过'));
  });

  test('the whole section is capped and the base rules survive', () {
    final skills = <InstalledSkill>[];
    for (var i = 0; i < 6; i++) {
      skills.add(skill(
        'skill$i',
        directory: skillDir('skill$i', {
          'references/doc.md': 'z' * SkillPrompt.maxReferenceBytes,
        }),
      ));
    }

    final built = SkillPrompt.build(base, skills);

    expect(built.startsWith(base), isTrue,
        reason: 'the assistant rules must never be the part that gets cut');
    expect(built, contains('skill 指令已截断：总量上限'));
    expect(
      built.length,
      lessThan(base.length + SkillPrompt.maxSectionBytes + 4096),
    );
  });
}
