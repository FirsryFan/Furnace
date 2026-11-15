import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/content/content_package_reader.dart';
import 'package:furnace/domain/services/content/content_package.dart';

/// `ContentPackageReader`（task-80）：把内容包目录读成 `ContentPackage`。
///
/// 三条：
///  * `question.json` + `boards/<subject>-board.json` 都在时，DAG/错因也解析；
///  * board 缺失不致命：`question.json` 仍可读，只是没有 DAG/错因，并给 warning；
///  * 缺 `question.json` / JSON 坏了抛错，不返回半个包。
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('content-package-reader-');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test('读目录：question.json + 学科板都解析', () {
    _writePackage(root, withBoard: true);

    final read = const ContentPackageReader().readDirectory(root.path);
    expect(read.package.contentId, 'Q-READ0001');
    expect(read.package.subject, 'physics');
    expect(read.package.answerParts, hasLength(1));
    expect(read.package.formattedAnswer, 'B');
    expect(read.package.dagNodes, hasLength(1));
    expect(read.package.dagNodes.single.id, 'N-R-01');
    expect(read.package.errorCauses, hasLength(1));
    expect(read.package.errorCauses.single.code, 'EC-R-01');
    expect(read.boardPath, isNotNull);
    expect(read.warnings, isEmpty);
  });

  test('缺学科板：包仍可读，记 warning，不给假 DAG', () {
    _writePackage(root, withBoard: false);

    final read = const ContentPackageReader().readDirectory(root.path);
    expect(read.package.contentId, 'Q-READ0001');
    expect(read.package.dagNodes, isEmpty);
    expect(read.package.errorCauses, isEmpty);
    expect(read.boardPath, isNull);
    expect(read.warnings, isNotEmpty);
  });

  test('缺 question.json：抛错，不返回半包', () {
    expect(
      () => const ContentPackageReader().readDirectory(root.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(const ContentPackageReader().readDirectoryOrNull(root.path), isNull);
  });

  test('board 的 question_id 与 question 不一致：拒绝解析', () {
    _writePackage(root, withBoard: true);
    final boardFile = File('${root.path}/boards/physics-board.json');
    final board =
        jsonDecode(boardFile.readAsStringSync()) as Map<String, Object?>;
    board['question_id'] = 'Q-OTHER';
    boardFile.writeAsStringSync(jsonEncode(board));

    expect(
      () => const ContentPackageReader().readDirectory(root.path),
      throwsFormatException,
    );
  });
}

void _writePackage(Directory root, {required bool withBoard}) {
  File('${root.path}/question.json').writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schema_version': kContentPackageBaseQuestionSchema,
      'id': 'Q-READ0001',
      'subject': 'physics',
      'title': <String, Object?>{'suggested': '读目录测试题'},
      'stem': <String, Object?>{'format': 'markdown+latex', 'text': '读目录测试题干'},
      'answer': <String, Object?>{
        'parts': <Map<String, Object?>>[
          <String, Object?>{'part': 'all', 'value': 'B', 'format': 'selection'},
        ],
        'official_trust': 'B_independently_verified',
        'answer_source': <String, Object?>{'id': 'E-SRC-R-ANS'},
      },
      'solutions': const <Object?>[],
      'figures': const <Object?>[],
      'scoring': <String, Object?>{
        'anchors': const <Object?>[],
        'source': 'none'
      },
      'classification': <String, Object?>{
        'content_type': <String, Object?>{'paper_form': 'single_choice'},
        'knowledge': <Map<String, Object?>>[
          <String, Object?>{
            'node_id': 'kp-r-primary',
            'label': '读目录知识点',
            'role': 'primary',
            'source': 'extracted',
          },
        ],
        'capability': <Map<String, Object?>>[
          <String, Object?>{'code': 'A4'},
        ],
        'subquestions': <Map<String, Object?>>[
          <String, Object?>{'id': 'all', 'points': null},
        ],
      },
      'meta': <String, Object?>{
        'source_level': 'gaokao',
        'source_label': '读目录测试来源',
        'year': 2023,
        'difficulty': <String, Object?>{'value': 2, 'source': 'ai'},
      },
      'panels': <String, Object?>{
        'board_refs': <String, Object?>{
          'physics': <String, Object?>{
            'version': 1,
            'content_hash': 'd' * 64,
            'path': 'boards/physics-board.json',
          },
        },
      },
      'provenance': <String, Object?>{
        'version': 1,
        'content_hash': 'e' * 64,
      },
      'review': <String, Object?>{'status': 'pending'},
      'analysis_render_policy': <String, Object?>{
        'reasoning_carrier': 'thinking_dag',
        'source_analysis_visible': false,
      },
    }),
  );
  if (!withBoard) {
    return;
  }
  Directory('${root.path}/boards').createSync();
  File('${root.path}/boards/physics-board.json').writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schema_version': 'furnace.content.physics-board/1',
      'subject': 'physics',
      'question_id': 'Q-READ0001',
      'meta': <String, Object?>{'board_version': 1},
      'thinking_dag': <String, Object?>{
        'nodes': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'N-R-01',
            'kind': 'conclusion',
            'role': 'conclude',
            'label': '结论',
            'body': '读目录测试 DAG 节点。',
            'formulas': const <Object?>[],
            'key_quantities': const <Object?>[],
            'result': '答案 B',
          },
        ],
        'edges': const <Object?>[],
      },
      'error_causes': <String, Object?>{
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'code': 'EC-R-01',
            'category': 'knowledge_gap',
            'symptom': '读目录测试错因',
            'root_cause': '根因',
            'remediation': '改法',
          },
        ],
      },
    }),
  );
}
