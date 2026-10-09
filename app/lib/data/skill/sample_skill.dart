/// A skill that ships with the app, so the container can be tried immediately.
///
/// Why this exists: everything else about `.fskill` is something the user has to
/// *bring* - a file they wrote or someone sent them. Without one, the honest
/// question "does the script container actually work on my machine?" can only be
/// answered by writing a package first, which is a poor first experience and a
/// worse way to test a release.
///
/// It is deliberately small and honest about itself: a prompt that explains what
/// it is, and one script that echoes back the arguments it was given (and the
/// names of the environment variables it can see, which is how the "no API key
/// in the child process" rule becomes something the user can check rather than
/// something the docs assert).
///
/// The package is built in memory from these strings rather than shipped as a
/// binary asset: a zip in the repository is unreviewable, and a `git diff`
/// cannot tell you what changed inside it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../domain/skill/skill_manifest.dart';

abstract final class SampleSkill {
  static const String name = 'furnace-demo';

  /// The one tool the sample declares, and the script behind it.
  static const String toolName = 'run_echo';

  /// The file name the settings card offers, if the user wants to keep the
  /// package around: `<name>.fskill`.
  static String get fileName => '$name.fskill';

  /// Builds the `.fskill` bytes.
  ///
  /// `platforms` lists both, because the *prompt* half works everywhere: on
  /// Android the skill installs, contributes its prompt, and simply has no
  /// runnable script tools (the container is Windows-only, §3/§5.5).
  static Uint8List build() {
    final manifest = jsonEncode({
      'format': SkillManifest.currentFormat,
      'name': name,
      'version': '1.0.0',
      'description': '示例 skill：验证脚本容器真的能跑，并回显它收到的参数与环境变量名',
      'platforms': const ['windows', 'android'],
      'networkAllow': const <String>[],
      'permissions': const <String>[],
      'scripts': const [
        {
          'name': toolName,
          'entry': 'scripts/echo.mjs',
          'args': ['--message'],
        },
      ],
    });

    final tool = jsonEncode({
      'name': toolName,
      'description': '把 message 交给 skill 目录里的脚本，回显脚本收到的参数与环境变量名',
      'risk': 'write',
      'reversible': false,
      'parameters': {
        'type': 'object',
        'properties': {
          'message': {
            'type': 'string',
            'description': '要回显的文本',
          },
        },
        'required': ['message'],
      },
    });

    const prompt = '''
这是一个随应用附带的示例 skill（furnace-demo）。它存在的唯一目的，是让用户能立刻验证
"skill 脚本容器"在本机确实工作：

- 在 Windows 上，它声明了一个工具 `run_echo`，会把 message 参数交给 skill 私有目录里的
  scripts/echo.mjs，回显脚本真正收到的 argv 与它能看到的环境变量名。
- 在其它平台上它只有这段提示词，没有任何可调用的工具。

用户想验证脚本能不能跑、或者怀疑自己的 API key 是否会被脚本看到时，用 run_echo 演示给他看。
不要用它做任何别的事。
''';

    const script = r'''
// The sample skill's only script. It deliberately prints its own argv and the
// names of the environment variables it can see: the first shows that the
// container passes one argv element per value (no shell), the second shows that
// the environment is a fixed whitelist rather than the parent's - which is how
// "the model API key is never handed to a skill" becomes checkable.
const args = process.argv.slice(2);
console.log(JSON.stringify({
  argv: args,
  envNames: Object.keys(process.env).sort(),
  cwd: process.cwd(),
}, null, 2));
''';

    final archive = Archive();
    void add(String path, String text) {
      final bytes = utf8.encode(text);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    add('manifest.json', manifest);
    add('prompt.md', prompt.trim());
    add('tools/run_echo.json', tool);
    add('scripts/echo.mjs', script.trim());
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }
}
