import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../../core/app_info.dart';
import '../../../data/database/database.dart';
import '../../../data/package/tfpkg_codec.dart';
import '../../../data/package/tfpkg_service.dart';

/// `diag.json` 里的格式标识：诊断包格式变了就换这里，读的人靠它判断。
const String kDiagnosticsFormat = 'furnace-diagnostics/1';

/// zip 内的固定文件名。测试与 README 都引用这三个常量，避免拼写漂移。
const String kDiagnosticsJsonEntry = 'diag.json';
const String kDiagnosticsReadmeEntry = 'README.txt';
const String kDiagnosticsTfpkgEntry = 'workspace.tfpkg';

/// 诊断包导出失败。
///
/// 目前只有一类：**检测到凭据**。这类失败必须明确抛出而不是静默少写一块内容，
/// 因为"看起来导出成功、实际带着 key"是最糟的结果。
class DiagnosticsBundleException implements Exception {
  const DiagnosticsBundleException(this.message);

  /// 给人看的中文说明，UI 直接塞进 `settingsDiagnosticFailed`。
  final String message;

  @override
  String toString() => 'DiagnosticsBundleException: $message';
}

/// 一份组装好的诊断包：字节 + 建议文件名 + 包内清单。
class DiagnosticsBundle {
  const DiagnosticsBundle({
    required this.bytes,
    required this.fileName,
    required this.entries,
    required this.includesContent,
  });

  final Uint8List bytes;
  final String fileName;
  final List<String> entries;
  final bool includesContent;
}

/// 生成 `.tfpkg` 字节的接缝。
///
/// 生产默认用 [TfpkgService]；测试注入一个"故意带 key 的坏包"来验证本服务会
/// 拦截（见 `diagnostics_bundle_test.dart`）。注意参数名固定为
/// `excludeSensitive`，因为安全契约就压在这个参数上。
typedef DiagnosticsTfpkgExport = Future<Uint8List> Function({
  required bool excludeSensitive,
});

/// 端到端问题反馈用的诊断包组装器。
///
/// 包内三块：
///  - `diag.json`：版本/build/schema/平台/生成时间、设置摘要（**key 脱敏**）、
///    题库与 AI 的行数统计、最近 N 条 AI 会话摘要、错误信息；
///  - `README.txt`：包里有什么、哪些东西永远不在里面、怎么回传；
///  - `workspace.tfpkg`（可选）：完整工作区逻辑转储，题目原文与 AI 聊天内容
///    都在这里。开关关闭时这一块不生成。
///
/// ## 安全契约
///
/// **任何分支都不会把 API key 写进包**。三道闸：
///  1. `diag.json` 的设置摘要里 `ai_api_key` 有值时一律写成 `***`；
///  2. `workspace.tfpkg` 用 `excludeSensitive: true` 生成（TfpkgService 把
///     `local_settings.ai_api_key` 置 null）；
///  3. 打包前把 tfpkg 解回逻辑转储，逐表逐行扫描字符串值；命中库里的真实 key
///     就抛 [DiagnosticsBundleException] 中止导出。即使第 2 道闸失效，也不会
///     静默泄漏。
///
/// 已知边界：tfpkg 里附件的二进制内容不做逐字节扫描（逻辑转储已覆盖文本；
/// 附件是背景图/导入字体这类用户自己选的文件）。
class DiagnosticsBundleService {
  DiagnosticsBundleService({
    required AppDatabase database,
    DiagnosticsTfpkgExport? tfpkgExport,
    DateTime Function()? now,
    String? appVersion,
    int? appBuildNumber,
    String? platform,
    List<String> errors = const <String>[],
    int questionSampleLimit = 10,
    int conversationLimit = 5,
  })  : _database = database,
        _now = now ?? DateTime.now,
        _appVersion = appVersion ?? kAppVersion,
        _appBuildNumber = appBuildNumber ?? kAppBuildNumber,
        _platform = platform ??
            '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        _errors = errors,
        _questionSampleLimit =
            questionSampleLimit < 0 ? 0 : questionSampleLimit,
        _conversationLimit = conversationLimit < 0 ? 0 : conversationLimit,
        _tfpkgExport = tfpkgExport ??
            (({required bool excludeSensitive}) =>
                TfpkgService(database).exportBytes(
                  appVersion: appVersion ?? kAppVersion,
                  excludeSensitive: excludeSensitive,
                ));

  final AppDatabase _database;
  final DateTime Function() _now;
  final String _appVersion;
  final int _appBuildNumber;
  final String _platform;
  final List<String> _errors;
  final int _questionSampleLimit;
  final int _conversationLimit;
  final DiagnosticsTfpkgExport _tfpkgExport;

  /// 设置里唯一已知的凭据列。新增凭据列时同时改这里与
  /// [TfpkgService.sensitiveColumns]。
  static const Set<String> secretColumns = {'ai_api_key'};

  /// 组装诊断包。[includeContent] = 是否包含题目样本与 `workspace.tfpkg`。
  Future<DiagnosticsBundle> build({required bool includeContent}) async {
    final now = _now();
    final softErrors = <String>[];
    final secrets = await _secrets(softErrors);
    final settings = await _settingsSummary(softErrors);
    final tableCounts = await _tableRowCounts(softErrors);
    final conversations = await _conversationSummaries(softErrors);
    final samples =
        includeContent ? await _questionSamples(softErrors) : const [];

    final diag = <String, Object?>{
      'format': kDiagnosticsFormat,
      'generated_at': now.toUtc().toIso8601String(),
      'content_included': includeContent,
      'app': <String, Object?>{
        'version': _appVersion,
        'build': _appBuildNumber,
        'schema_version': _database.schemaVersion,
        'platform': _platform,
      },
      'settings_summary': settings,
      'question_bank': <String, Object?>{
        'questions': tableCounts['questions'] ?? 0,
        'options': tableCounts['question_options'] ?? 0,
        'attempts': tableCounts['question_attempts'] ?? 0,
      },
      'ai': <String, Object?>{
        'conversations': tableCounts['ai_conversations'] ?? 0,
        'messages': tableCounts['ai_messages'] ?? 0,
        'actions': tableCounts['ai_actions'] ?? 0,
        'key_configured': secrets.isNotEmpty,
      },
      'knowledge': <String, Object?>{
        'knowledge_points': tableCounts['knowledge_points'] ?? 0,
        'card_states': tableCounts['card_states'] ?? 0,
        'review_logs': tableCounts['review_logs'] ?? 0,
        'tags': tableCounts['tags'] ?? 0,
      },
      'table_row_counts': tableCounts,
      'ai_conversations': conversations,
      if (includeContent) 'question_samples': samples,
      'errors': <String>[..._errors, ...softErrors],
    };

    final diagBytes =
        utf8.encode(const JsonEncoder.withIndent('  ').convert(diag));
    final readmeBytes = utf8.encode(_readme(includeContent));
    _rejectSecretBytes(kDiagnosticsJsonEntry, diagBytes, secrets);
    _rejectSecretBytes(kDiagnosticsReadmeEntry, readmeBytes, secrets);

    Uint8List? tfpkgBytes;
    if (includeContent) {
      tfpkgBytes = await _tfpkgExport(excludeSensitive: true);
      _rejectSecretsInTfpkg(tfpkgBytes, secrets);
    }

    final archive = Archive()
      ..addFile(ArchiveFile(
        kDiagnosticsJsonEntry,
        diagBytes.length,
        diagBytes,
      ))
      ..addFile(ArchiveFile(
        kDiagnosticsReadmeEntry,
        readmeBytes.length,
        readmeBytes,
      ));
    if (tfpkgBytes != null) {
      archive.addFile(ArchiveFile(
        kDiagnosticsTfpkgEntry,
        tfpkgBytes.length,
        tfpkgBytes,
      ));
    }

    final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
    return DiagnosticsBundle(
      bytes: bytes,
      fileName: 'furnace-diagnostics-${_stamp(now)}.zip',
      entries: <String>[
        kDiagnosticsJsonEntry,
        kDiagnosticsReadmeEntry,
        if (tfpkgBytes != null) kDiagnosticsTfpkgEntry,
      ],
      includesContent: tfpkgBytes != null,
    );
  }

  /// 库里的真实凭据值（用于"包里绝不允许出现这些字符串"的校验）。
  Future<List<String>> _secrets(List<String> softErrors) async {
    try {
      final rows = await _database.dumpTable('local_settings');
      return <String>[
        for (final row in rows)
          for (final column in secretColumns)
            if (row[column] case final String value
                when value.trim().isNotEmpty)
              value,
      ];
    } on Object catch (error) {
      softErrors.add('读取设置里的凭据失败：$error');
      return const <String>[];
    }
  }

  /// 设置摘要：整行保留，只把凭据列替换成 `***`（有值时）或 null。
  Future<Map<String, Object?>> _settingsSummary(List<String> softErrors) async {
    try {
      final rows = await _database.dumpTable('local_settings');
      if (rows.isEmpty) {
        return <String, Object?>{'row_present': false};
      }
      final row = rows.first;
      return <String, Object?>{
        'row_present': true,
        for (final entry in row.entries)
          entry.key: secretColumns.contains(entry.key) && entry.value != null
              ? '***'
              : entry.value,
      };
    } on Object catch (error) {
      softErrors.add('读取设置摘要失败：$error');
      return <String, Object?>{'row_present': false, 'available': false};
    }
  }

  /// 每张用户表的行数。单表失败只记 soft error，不让整个诊断包失败。
  Future<Map<String, int>> _tableRowCounts(List<String> softErrors) async {
    final counts = <String, int>{};
    try {
      for (final table in await _database.userTables()) {
        try {
          final row = await _database
              .customSelect('SELECT COUNT(*) AS c FROM "$table"')
              .getSingle();
          counts[table] = row.read<int>('c');
        } on Object catch (error) {
          softErrors.add('统计 $table 行数失败：$error');
        }
      }
    } on Object catch (error) {
      softErrors.add('枚举表失败：$error');
    }
    return counts;
  }

  /// 最近 N 条 AI 会话的摘要（标题 + 起止时间 + 消息条数），不含正文。
  Future<List<Map<String, Object?>>> _conversationSummaries(
    List<String> softErrors,
  ) async {
    try {
      final rows = await _database
          .customSelect(
            'SELECT c.id AS id, c.title AS title, c.created_at AS created_at, '
            'c.updated_at AS updated_at, '
            '(SELECT COUNT(*) FROM ai_messages m '
            'WHERE m.conversation_id = c.id) AS message_count '
            'FROM ai_conversations c '
            'ORDER BY c.updated_at DESC LIMIT $_conversationLimit',
          )
          .get();
      return <Map<String, Object?>>[
        for (final row in rows)
          <String, Object?>{
            'id': row.read<String>('id'),
            'title': row.read<String>('title'),
            'created_at': row.read<int>('created_at'),
            'updated_at': row.read<int>('updated_at'),
            'message_count': row.read<int>('message_count'),
          },
      ];
    } on Object catch (error) {
      softErrors.add('读取 AI 会话摘要失败：$error');
      return const <Map<String, Object?>>[];
    }
  }

  /// 最近 N 道题的样本：题干截断到 [_stemLimit] 字，答案/解析不单独展开
  /// （它们都在随包附带的 `workspace.tfpkg` 里）。
  Future<List<Map<String, Object?>>> _questionSamples(
    List<String> softErrors,
  ) async {
    try {
      final rows = await _database
          .customSelect(
            'SELECT id, serial_no, title, stem, subject_key, state, created_at '
            'FROM questions ORDER BY created_at DESC LIMIT $_questionSampleLimit',
          )
          .get();
      return <Map<String, Object?>>[
        for (final row in rows)
          <String, Object?>{
            'id': row.read<String>('id'),
            'serial_no': row.readNullable<int>('serial_no'),
            'title': row.readNullable<String>('title'),
            'subject_key': row.read<String>('subject_key'),
            'state': row.read<String>('state'),
            'created_at': row.read<int>('created_at'),
            'stem': _truncate(row.read<String>('stem')),
          },
      ];
    } on Object catch (error) {
      softErrors.add('读取题目样本失败：$error');
      return const <Map<String, Object?>>[];
    }
  }

  static const int _stemLimit = 2000;

  static String _truncate(String value) => value.length <= _stemLimit
      ? value
      : '${value.substring(0, _stemLimit)}…（已截断）';

  /// 第三道闸：把 tfpkg 解回逻辑转储，扫凭据。
  void _rejectSecretsInTfpkg(Uint8List bytes, List<String> secrets) {
    final TfpkgDump dump;
    try {
      dump = TfpkgCodec.decode(bytes).dump;
    } on Object catch (error) {
      throw DiagnosticsBundleException(
        'workspace.tfpkg 无法解码，无法确认不含凭据，已中止导出：$error',
      );
    }

    for (final row in dump.tables['local_settings']?.rows ??
        const <Map<String, dynamic>>[]) {
      final value = row['ai_api_key'];
      if (value is String && value.isNotEmpty) {
        throw const DiagnosticsBundleException(
          'workspace.tfpkg 仍含 API key，已中止导出（未生成任何文件）',
        );
      }
    }

    for (final table in dump.tables.entries) {
      for (final row in table.value.rows) {
        for (final value in row.values) {
          if (value is! String || value.isEmpty) {
            continue;
          }
          for (final secret in secrets) {
            if (value.contains(secret)) {
              throw DiagnosticsBundleException(
                'workspace.tfpkg 的 ${table.key} 表含 API key，已中止导出',
              );
            }
          }
        }
      }
    }
    for (final theme in dump.themes) {
      for (final secret in secrets) {
        if (theme.contains(secret)) {
          throw const DiagnosticsBundleException(
            'workspace.tfpkg 的主题文档含 API key，已中止导出',
          );
        }
      }
    }
  }

  /// 自己写的文本块同样要过一遍：防止未来改设置摘要时把 key 又加回来。
  void _rejectSecretBytes(String label, List<int> bytes, List<String> secrets) {
    if (secrets.isEmpty) {
      return;
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    for (final secret in secrets) {
      if (text.contains(secret)) {
        throw DiagnosticsBundleException('$label 含 API key，已中止导出');
      }
    }
  }

  /// 包内 README。故意用英文纯文本：这是给"回传者/开发者"看的文件，不是 UI，
  /// 不进 ARB、不依赖语言设置。
  String _readme(bool includeContent) {
    final contentSection = includeContent
        ? '''

$kDiagnosticsTfpkgEntry
  A logical dump of the whole workspace in the .tfpkg format: every table,
  including the user's questions (stems, answers, solutions) and AI
  conversations. Generated with excludeSensitive=true and re-verified by this
  exporter, so it never carries the API key.
'''
        : '''

(No workspace dump in this bundle: "include questions and AI content" was off.
 Re-export with that switch on if the report needs the original text.)
''';
    return '''
Furnace diagnostics bundle
==========================

What is inside
--------------
$kDiagnosticsJsonEntry
  Application version and build number, database schema version, platform,
  generation time, a settings summary (the API key is redacted as "***"),
  row counts for the question bank / AI / knowledge tables, summaries of the
  most recent AI conversations (title + message count, no message bodies), and
  any errors reported while building this bundle.
$contentSection
$kDiagnosticsReadmeEntry
  This file.

What is NOT inside
------------------
The API key, or any other credential. Settings are redacted and the workspace
dump is scanned for the stored key before the zip is written.

How to use it
-------------
Attach this .zip to the bug report or send it back to the developer together
with what went wrong and when. The bundle is generated locally; nothing is
uploaded by the app.
''';
  }

  /// 文件名时间戳（本地时间，到分钟）：`20261101T2236`。
  static String _stamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}'
        'T${two(time.hour)}${two(time.minute)}';
  }
}
