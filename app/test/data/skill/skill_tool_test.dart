/// The runtime tool wrapper: what the provider is offered, and the two
/// properties that decide how a call is approved.
///
/// These are the acceptance points that do not need a process: the derived name,
/// the platform gate (§5.5), the fixed risk/reversibility pair (§5.1 rule 2) and
/// what the approval engine does with that pair (§6). The engine is used as it
/// is - `ApprovalEngine(mode: ...).forInvocation(...)` - because "do not add a
/// second gate" is the requirement, and a test that re-implemented the rule
/// would not be able to tell.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/skill/skill_store.dart';
import 'package:furnace/domain/skill/skill_manifest.dart';
import 'package:furnace/domain/skill/skill_tool.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';

void main() {
  InstalledSkill skill({
    String name = 'demo-skill',
    List<String> platforms = const ['windows'],
    List<String> networkAllow = const [],
    List<String> permissions = const [],
    bool networkAllowed = false,
    List<Map<String, dynamic>> scripts = const [],
    List<SkillToolDeclaration> tools = const [],
  }) =>
      InstalledSkill(
        manifest: SkillManifest(
          format: 'fskill/1',
          name: name,
          version: '1.0.0',
          description: '测试用',
          platforms: [
            for (final id in platforms) SkillPlatform.fromId(id)!,
          ],
          networkAllow: networkAllow,
          permissions: permissions,
          scripts: [
            for (final json in scripts)
              SkillScriptDeclaration.fromJson(json),
          ],
        ),
        prompt: '# $name\n',
        tools: tools,
        enabled: true,
        installedAt: DateTime.utc(2026, 10, 2),
        directory: r'C:\appdata\skills\demo-skill',
      );

  /// The one declaration these tests use.
  SkillToolDeclaration declaration({String name = 'find_questions'}) =>
      SkillToolDeclaration(
        name: name,
        description: '按条件检索题目',
        parameters: const {
          'type': 'object',
          'properties': {
            'subject': {'type': 'string'},
          },
        },
        risk: 'write',
        reversible: false,
        source: 'tools/find.json',
      );

  SkillTool tool({
    InstalledSkill? forSkill,
    SkillToolDeclaration? forDeclaration,
    SkillScriptDeclaration? script,
    SkillPlatform platform = SkillPlatform.windows,
  }) =>
      SkillTool(
        skill: forSkill ?? skill(),
        declaration: forDeclaration ?? declaration(),
        script: script,
        platform: platform,
      );

  group('the provider-facing name', () {
    test('is <skill-name>_<tool-name>', () {
      expect(skillToolName('demo-skill', 'find_questions'),
          'demo-skill_find_questions');
      expect(tool().name, 'demo-skill_find_questions');
    });

    test('is unique per skill and per tool', () {
      final a = tool(
        forSkill: skill(name: 'alpha'),
        forDeclaration: declaration(name: 'find'),
      );
      final b = tool(
        forSkill: skill(name: 'beta'),
        forDeclaration: declaration(name: 'find'),
      );
      final c = tool(
        forSkill: skill(name: 'alpha'),
        forDeclaration: declaration(name: 'count'),
      );
      expect({a.name, b.name, c.name}, hasLength(3));
    });

    test('replaces anything outside [a-zA-Z0-9_-] with an underscore', () {
      expect(skillToolName('demo.skill', 'find questions'),
          'demo_skill_find_questions');
      expect(
        skillToolName('a', 'b:c/d\\e'),
        'a_b_c_d_e',
      );
      // Whatever the input, the result is a legal provider identifier.
      final derived = skillToolName('skill.name', 'tool/name');
      expect(RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(derived), isTrue);
    });
  });

  group('platform gating (spec §5.5)', () {
    test('is offered on Windows, and only when the package declares it', () {
      expect(tool(platform: SkillPlatform.windows).availableOnCurrentPlatform,
          isTrue);
      expect(
        tool(
          forSkill: skill(platforms: const ['android']),
          platform: SkillPlatform.windows,
        ).availableOnCurrentPlatform,
        isFalse,
        reason: 'a package that does not declare this platform is not offered',
      );
    });

    test('is absent on Android, not failing at call time', () {
      expect(tool(platform: SkillPlatform.android).availableOnCurrentPlatform,
          isFalse);
      expect(tool(platform: SkillPlatform.linux).availableOnCurrentPlatform,
          isFalse);
      expect(tool(platform: SkillPlatform.macos).availableOnCurrentPlatform,
          isFalse);
    });

    test('the store and the tool agree about runnability', () {
      // The card shows `isRunnableOn` and the loop asks the tool; if those two
      // could disagree, the card would be describing a different app.
      for (final platform in SkillPlatform.values) {
        expect(
          skill(platforms: const ['windows']).isRunnableOn(platform),
          tool(platform: platform).availableOnCurrentPlatform,
          reason: 'disagreement on ${platform.id}',
        );
      }
    });
  });

  group('risk and reversibility (spec §5.1 rule 2)', () {
    test('is always write and never reversible', () {
      final subject = tool();
      expect(subject.riskFor('find_questions'), ToolRisk.write);
      expect(subject.reversibleFor('find_questions'), isFalse);
      expect(subject.readOnly, isFalse);
      // The declaration cannot talk it up: a `write` tool stays write, and a
      // declared action name - which a skill tool does not have - changes
      // nothing either.
      expect(subject.riskFor('anything-at-all'), ToolRisk.write);
      expect(subject.reversibleFor('anything-at-all'), isFalse);
    });

    test('every call is individualApproval, in both permission modes', () {
      final subject = tool();
      for (final mode in AiPermissionMode.values) {
        final decision =
            ApprovalEngine(mode: mode).forInvocation(subject, const {});
        expect(
          decision.disposition,
          ToolDisposition.individualApproval,
          reason: 'mode ${mode.id} must still ask per call',
        );
        expect(decision.runsWithoutAsking, isFalse);
        expect(decision.reversible, isFalse);
        expect(decision.toolName, subject.name);
      }
    });
  });

  group('what the model is told', () {
    test('the description names the script that will run', () {
      final subject = tool(
        script: const SkillScriptDeclaration(
          name: 'find_questions',
          entry: 'scripts/find.mjs',
          args: ['--subject'],
        ),
      );
      expect(subject.description, contains('按条件检索题目'));
      expect(subject.description, contains('scripts/find.mjs'));
      expect(subject.description, contains('demo-skill'));
    });

    test('a declaration with no scripts[] entry says the call will be refused',
        () {
      expect(tool().description, contains('拒绝'));
    });

    test('the JSON Schema is passed through untouched', () {
      final subject = tool();
      expect(subject.parameters, declaration().parameters);
      expect(subject.parameters['properties'], isA<Map>());
    });

    test('risk is looked up by the tool name, not by an action argument', () {
      final subject = tool();
      expect(subject.actionOf(const {'action': 'delete'}), 'find_questions');
    });
  });
}
