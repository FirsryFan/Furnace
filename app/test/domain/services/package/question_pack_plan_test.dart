import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/package/question_pack_plan.dart';
import 'package:furnace/domain/services/package/question_pack_record.dart';

QuestionPackRecord _record({
  required String stem,
  List<String> tagPaths = const <String>[],
  int? serialNo,
  String? zujuanQuestionId,
}) =>
    QuestionPackRecord(
      stem: stem,
      tagPaths: tagPaths,
      serialNo: serialNo,
      zujuanQuestionId: zujuanQuestionId,
    );

String _fingerprint(String stem) => 'fp:${stem.trim().toLowerCase()}';

Set<String> _existingFingerprintsOf(Iterable<String> stems) =>
    <String>{for (final String stem in stems) _fingerprint(stem)};

QuestionPackImportPlan _plan(
  List<QuestionPackRecord> records, {
  Iterable<String> existingStems = const <String>[],
  Set<String> existingTagPaths = const <String>{},
  String Function(String stem)? fingerprintOf,
  Map<String, String> existingQuestionIdByZujuanQuestionId =
      const <String, String>{},
  bool updateExisting = true,
}) =>
    planQuestionPackImport(
      records: records,
      fingerprintOf: fingerprintOf ?? _fingerprint,
      existingFingerprints: _existingFingerprintsOf(existingStems),
      existingTagPaths: existingTagPaths,
      existingQuestionIdByZujuanQuestionId:
          existingQuestionIdByZujuanQuestionId,
      updateExisting: updateExisting,
    );

void main() {
  group('QuestionPackAction', () {
    test('两个动作常量的机器可读值', () {
      expect(QuestionPackAction.create, 'create');
      expect(QuestionPackAction.skipDuplicate, 'skip_duplicate');
    });

    test('labelZh 新建', () {
      expect(QuestionPackAction.labelZh(QuestionPackAction.create), '新建');
    });

    test('labelZh 跳过重复', () {
      expect(
          QuestionPackAction.labelZh(QuestionPackAction.skipDuplicate), '跳过重复');
    });

    test('labelZh 未知动作原样返回', () {
      expect(QuestionPackAction.labelZh('merge'), 'merge');
      expect(QuestionPackAction.labelZh(''), '');
    });
  });

  group('planQuestionPackImport：空包与全新建', () {
    test('空记录返回空计划，永不抛异常', () {
      final QuestionPackImportPlan plan = _plan(const <QuestionPackRecord>[]);
      expect(plan.isEmpty, isTrue);
      expect(plan.decisions, isEmpty);
      expect(plan.createCount, 0);
      expect(plan.skipCount, 0);
      expect(plan.createIndexes, isEmpty);
      expect(plan.hasWarnings, isFalse);
      expect(plan.warnings, isEmpty);
      expect(plan.missingTagPaths, isEmpty);
      expect(plan.toJson(), <String, Object?>{
        'create_count': 0,
        'update_count': 0,
        'skip_count': 0,
        'decisions': <Object?>[],
        'warnings': <Object?>[],
        'missing_tag_paths': <Object?>[],
      });
    });

    test('全新建：决策与记录一一对应、index 从 0 起', () {
      final QuestionPackImportPlan plan = _plan(<QuestionPackRecord>[
        _record(stem: '第一题'),
        _record(stem: '第二题'),
        _record(stem: '第三题'),
      ]);
      expect(plan.decisions, hasLength(3));
      expect(plan.decisions.map((QuestionPackDecision d) => d.index),
          <int>[0, 1, 2]);
      expect(
        plan.decisions.map((QuestionPackDecision d) => d.action),
        <String>[
          QuestionPackAction.create,
          QuestionPackAction.create,
          QuestionPackAction.create,
        ],
      );
      expect(plan.createCount, 3);
      expect(plan.skipCount, 0);
      expect(plan.createIndexes, <int>[0, 1, 2]);
      expect(
        plan.decisions.every((QuestionPackDecision d) => d.skipReason == null),
        isTrue,
      );
    });

    test('serialNo 原样透传（有值与无值）', () {
      final QuestionPackImportPlan plan = _plan(<QuestionPackRecord>[
        _record(stem: '有编号', serialNo: 12),
        _record(stem: '没编号'),
      ]);
      expect(plan.decisions[0].serialNo, 12);
      expect(plan.decisions[1].serialNo, isNull);
    });

    test('新建决策的 toJson 省略 skip_reason 与空 serial_no', () {
      final QuestionPackImportPlan plan = _plan(<QuestionPackRecord>[
        _record(stem: '只有题干'),
      ]);
      expect(plan.decisions.single.toJson(), <String, Object?>{
        'index': 0,
        'action': QuestionPackAction.create,
        'stem_preview': '只有题干',
      });
    });
  });

  group('planQuestionPackImport：题库已有重复', () {
    test('命中题库已有指纹时记为跳过重复并给出原因', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[_record(stem: '老题')],
        existingStems: <String>['老题'],
      );
      final QuestionPackDecision decision = plan.decisions.single;
      expect(decision.index, 0);
      expect(decision.action, QuestionPackAction.skipDuplicate);
      expect(decision.skipReason, '题库里已经有同一道题（题干指纹相同）');
      expect(plan.createCount, 0);
      expect(plan.skipCount, 1);
      expect(plan.createIndexes, isEmpty);
    });

    test('新建与跳过混合时计数与下标正确', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '新题一'),
          _record(stem: '老题'),
          _record(stem: '新题二'),
        ],
        existingStems: <String>['老题'],
      );
      expect(
        plan.decisions.map((QuestionPackDecision d) => d.action),
        <String>[
          QuestionPackAction.create,
          QuestionPackAction.skipDuplicate,
          QuestionPackAction.create,
        ],
      );
      expect(plan.createCount, 2);
      expect(plan.skipCount, 1);
      expect(plan.createIndexes, <int>[0, 2]);
    });

    test('existingFingerprints 只读不写', () {
      final Set<String> existing = _existingFingerprintsOf(<String>['老题']);
      final Set<String> snapshot = Set<String>.of(existing);
      planQuestionPackImport(
        records: <QuestionPackRecord>[
          _record(stem: '老题'),
          _record(stem: '新题'),
        ],
        fingerprintOf: _fingerprint,
        existingFingerprints: existing,
        existingTagPaths: <String>{'已存在标签'},
      );
      expect(existing, snapshot);
      expect(existing, hasLength(1));
    });

    test('指纹函数对每道题恰好调用一次', () {
      var calls = 0;
      final QuestionPackImportPlan plan = planQuestionPackImport(
        records: <QuestionPackRecord>[
          _record(stem: '老题'),
          _record(stem: '老题'),
          _record(stem: '新题'),
        ],
        fingerprintOf: (String stem) {
          calls++;
          return _fingerprint(stem);
        },
        existingFingerprints: _existingFingerprintsOf(<String>['老题']),
        existingTagPaths: const <String>{},
      );
      expect(calls, 3);
      expect(plan.createCount, 1);
      expect(plan.skipCount, 2);
    });

    test('题库已有重复按题序产生简短告警', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '老题一'),
          _record(stem: '新题'),
          _record(stem: '老题二'),
        ],
        existingStems: <String>['老题一', '老题二'],
      );
      expect(plan.warnings, <String>[
        '第 1 道题与题库已有题目重复，导入时跳过',
        '第 3 道题与题库已有题目重复，导入时跳过',
      ]);
    });

    test('跳过决策也透传 serialNo', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[_record(stem: '老题', serialNo: 9)],
        existingStems: <String>['老题'],
      );
      expect(plan.decisions.single.serialNo, 9);
      expect(plan.decisions.single.toJson()['serial_no'], 9);
      expect(
          plan.decisions.single.toJson()['skip_reason'], '题库里已经有同一道题（题干指纹相同）');
    });
  });

  group('planQuestionPackImport：包内重复', () {
    test('两条相同题干：后一条跳过并引用第 1 道', () {
      final QuestionPackImportPlan plan = _plan(<QuestionPackRecord>[
        _record(stem: '同一道题'),
        _record(stem: '同一道题'),
      ]);
      expect(
        plan.decisions.map((QuestionPackDecision d) => d.action),
        <String>[QuestionPackAction.create, QuestionPackAction.skipDuplicate],
      );
      expect(plan.decisions[1].skipReason, '与包内第 1 道题重复（题干指纹相同）');
      expect(plan.warnings, <String>['包内第 2 道与第 1 道是同一道题，只导入前一道']);
      expect(plan.createCount, 1);
      expect(plan.skipCount, 1);
      expect(plan.createIndexes, <int>[0]);
    });

    test('三条相同题干：只有第一条新建，告警逐条给出', () {
      final QuestionPackImportPlan plan = _plan(<QuestionPackRecord>[
        _record(stem: '同一道题'),
        _record(stem: '同一道题'),
        _record(stem: '同一道题'),
      ]);
      expect(plan.createCount, 1);
      expect(plan.skipCount, 2);
      expect(plan.warnings, <String>[
        '包内第 2 道与第 1 道是同一道题，只导入前一道',
        '包内第 3 道与第 1 道是同一道题，只导入前一道',
      ]);
      expect(plan.decisions[1].skipReason, '与包内第 1 道题重复（题干指纹相同）');
      expect(plan.decisions[2].skipReason, '与包内第 1 道题重复（题干指纹相同）');
    });

    test('隔着别的题重复也按首次出现位置判定', () {
      final QuestionPackImportPlan plan = _plan(<QuestionPackRecord>[
        _record(stem: '甲'),
        _record(stem: '乙'),
        _record(stem: '甲'),
      ]);
      expect(
        plan.decisions.map((QuestionPackDecision d) => d.action),
        <String>[
          QuestionPackAction.create,
          QuestionPackAction.create,
          QuestionPackAction.skipDuplicate,
        ],
      );
      expect(plan.decisions[2].skipReason, '与包内第 1 道题重复（题干指纹相同）');
      expect(plan.warnings, <String>['包内第 3 道与第 1 道是同一道题，只导入前一道']);
    });

    test('包内重复时指纹函数仍对每道题调用一次', () {
      var calls = 0;
      _plan(
        <QuestionPackRecord>[
          _record(stem: '同一道题'),
          _record(stem: '同一道题'),
          _record(stem: '同一道题'),
        ],
        fingerprintOf: (String stem) {
          calls++;
          return _fingerprint(stem);
        },
      );
      expect(calls, 3);
    });

    test('首次出现已命中题库时，后一条按题库重复处理且不出包内告警', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '老题'),
          _record(stem: '老题'),
        ],
        existingStems: <String>['老题'],
      );
      expect(plan.createCount, 0);
      expect(plan.skipCount, 2);
      expect(plan.warnings, <String>[
        '第 1 道题与题库已有题目重复，导入时跳过',
        '第 2 道题与题库已有题目重复，导入时跳过',
      ]);
      expect(
        plan.warnings.every((String w) => !w.contains('包内')),
        isTrue,
      );
    });
  });

  group('planQuestionPackImport：warnings 口径', () {
    test('没有重复与缺失标签时 warnings 为空', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '新题', tagPaths: <String>['已有标签']),
        ],
        existingTagPaths: <String>{'已有标签'},
      );
      expect(plan.warnings, isEmpty);
      expect(plan.hasWarnings, isFalse);
    });

    test('跳过告警按题序排列，并排在缺失标签告警之前', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '新题', tagPaths: <String>['缺标签']),
          _record(stem: '老题一'),
          _record(stem: '老题二'),
        ],
        existingStems: <String>['老题一', '老题二'],
      );
      expect(plan.warnings, <String>[
        '第 2 道题与题库已有题目重复，导入时跳过',
        '第 3 道题与题库已有题目重复，导入时跳过',
        '标签 缺标签 在题库里不存在，导入后相关题不挂这个标签',
      ]);
    });

    test('只有缺失标签也算有告警', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '新题', tagPaths: <String>['缺标签']),
        ],
      );
      expect(plan.hasWarnings, isTrue);
      expect(plan.warnings, <String>[
        '标签 缺标签 在题库里不存在，导入后相关题不挂这个标签',
      ]);
    });
  });

  group('planQuestionPackImport：missingTagPaths', () {
    test('全部标签都在题库里时为空', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '题一', tagPaths: <String>['数学/函数', '数学/导数']),
        ],
        existingTagPaths: <String>{'数学/函数', '数学/导数'},
      );
      expect(plan.missingTagPaths, isEmpty);
    });

    test('记录侧与题库两侧都 trim 后比较', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '题一', tagPaths: <String>[' 数学/函数 ']),
          _record(stem: '题二', tagPaths: <String>['数学/导数']),
        ],
        existingTagPaths: <String>{'数学/函数', ' 数学/导数 '},
      );
      expect(plan.missingTagPaths, isEmpty);
    });

    test('去重后按字典序排序', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '题一', tagPaths: <String>['化学', '物理']),
          _record(stem: '题二', tagPaths: <String>['化学', '生物']),
        ],
      );
      expect(plan.missingTagPaths, <String>['化学', '物理', '生物']);
    });

    test('缺失标签告警文案逐字匹配', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '题一', tagPaths: <String>['化学']),
        ],
      );
      expect(plan.warnings, <String>[
        '标签 化学 在题库里不存在，导入后相关题不挂这个标签',
      ]);
    });

    test('超过 20 条标签缺失时截断并给剩余条数', () {
      final List<String> tags = List<String>.generate(
        25,
        (int i) => 'kp-${(i + 1).toString().padLeft(2, '0')}',
      );
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[_record(stem: '题一', tagPaths: tags)],
      );
      expect(plan.missingTagPaths, hasLength(25));
      expect(plan.missingTagPaths.first, 'kp-01');
      expect(plan.missingTagPaths.last, 'kp-25');
      expect(plan.warnings, hasLength(21));
      expect(plan.warnings[0], '标签 kp-01 在题库里不存在，导入后相关题不挂这个标签');
      expect(plan.warnings[19], '标签 kp-20 在题库里不存在，导入后相关题不挂这个标签');
      expect(plan.warnings[20], '还有 5 条标签缺失未列出');
    });

    test('恰好 20 条缺失不加截断说明', () {
      final List<String> tags = List<String>.generate(
        20,
        (int i) => 'kp-${(i + 1).toString().padLeft(2, '0')}',
      );
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[_record(stem: '题一', tagPaths: tags)],
      );
      expect(plan.missingTagPaths, hasLength(20));
      expect(plan.warnings, hasLength(20));
      expect(
        plan.warnings.any((String w) => w.contains('未列出')),
        isFalse,
      );
    });

    test('没有标签的记录不产生缺失', () {
      final QuestionPackImportPlan plan = _plan(<QuestionPackRecord>[
        _record(stem: '题一'),
      ]);
      expect(plan.missingTagPaths, isEmpty);
      expect(plan.warnings, isEmpty);
    });
  });

  group('stemPreview', () {
    test('连续空白压成一个空格并 trim', () {
      final QuestionPackImportPlan plan = _plan(<QuestionPackRecord>[
        _record(stem: '  第一行\n\n第二行\t 第三行  '),
      ]);
      expect(plan.decisions.single.stemPreview, '第一行 第二行 第三行');
    });

    test('不超长时原样保留（仅归一空白）', () {
      final QuestionPackImportPlan plan = _plan(<QuestionPackRecord>[
        _record(stem: ' 已知函数 ( f(x)=x^2 ) 求最小值 '),
      ]);
      expect(plan.decisions.single.stemPreview, '已知函数 ( f(x)=x^2 ) 求最小值');
    });

    test('正好 40 个字符不加省略号', () {
      final QuestionPackImportPlan plan = _plan(<QuestionPackRecord>[
        _record(stem: 'a' * 40),
      ]);
      expect(plan.decisions.single.stemPreview, 'a' * 40);
      expect(plan.decisions.single.stemPreview, hasLength(40));
    });

    test('超过 40 个字符截断加省略号', () {
      final QuestionPackImportPlan plan = _plan(<QuestionPackRecord>[
        _record(stem: 'a' * 41),
      ]);
      expect(plan.decisions.single.stemPreview, '${'a' * 40}…');
      expect(plan.decisions.single.stemPreview, hasLength(41));
    });

    test('中文题干也在 40 个字符处截断', () {
      final QuestionPackImportPlan plan = _plan(<QuestionPackRecord>[
        _record(stem: '数' * 45),
      ]);
      expect(plan.decisions.single.stemPreview, '${'数' * 40}…');
    });

    test('不在 emoji 代理对中间截断', () {
      final String emoji = String.fromCharCode(0x1F600);
      final QuestionPackImportPlan plan = _plan(<QuestionPackRecord>[
        _record(stem: '${'a' * 39}$emoji'),
      ]);
      expect(plan.decisions.single.stemPreview, '${'a' * 39}…');
    });
  });

  group('QuestionPackDecision', () {
    test('toJson 用 snake_case 并省略 null 键', () {
      const QuestionPackDecision decision = QuestionPackDecision(
        index: 2,
        action: QuestionPackAction.create,
        stemPreview: '题干',
      );
      expect(decision.toJson(), <String, Object?>{
        'index': 2,
        'action': 'create',
        'stem_preview': '题干',
      });
    });

    test('跳过决策的 toJson 带 serial_no 与 skip_reason', () {
      const QuestionPackDecision decision = QuestionPackDecision(
        index: 5,
        action: QuestionPackAction.skipDuplicate,
        stemPreview: '重复题',
        serialNo: 18,
        skipReason: '题库里已经有同一道题（题干指纹相同）',
      );
      expect(decision.toJson(), <String, Object?>{
        'index': 5,
        'action': 'skip_duplicate',
        'stem_preview': '重复题',
        'serial_no': 18,
        'skip_reason': '题库里已经有同一道题（题干指纹相同）',
      });
    });

    test('== / hashCode 按值比较', () {
      const QuestionPackDecision a = QuestionPackDecision(
        index: 1,
        action: QuestionPackAction.create,
        stemPreview: '题干',
        serialNo: 3,
      );
      const QuestionPackDecision b = QuestionPackDecision(
        index: 1,
        action: QuestionPackAction.create,
        stemPreview: '题干',
        serialNo: 3,
      );
      const QuestionPackDecision c = QuestionPackDecision(
        index: 2,
        action: QuestionPackAction.create,
        stemPreview: '题干',
        serialNo: 3,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('toString 包含主要字段', () {
      const QuestionPackDecision decision = QuestionPackDecision(
        index: 4,
        action: QuestionPackAction.skipDuplicate,
        stemPreview: '重复题',
        skipReason: '与包内第 1 道题重复（题干指纹相同）',
      );
      expect(decision.toString(), contains('index: 4'));
      expect(decision.toString(), contains('skip_duplicate'));
      expect(decision.toString(), contains('重复题'));
    });
  });

  group('QuestionPackImportPlan', () {
    test('createCount/skipCount/createIndexes 由 decisions 现算', () {
      const QuestionPackImportPlan plan = QuestionPackImportPlan(
        decisions: <QuestionPackDecision>[
          QuestionPackDecision(
            index: 0,
            action: QuestionPackAction.create,
            stemPreview: '甲',
          ),
          QuestionPackDecision(
            index: 1,
            action: QuestionPackAction.skipDuplicate,
            stemPreview: '乙',
            skipReason: '题库里已经有同一道题（题干指纹相同）',
          ),
          QuestionPackDecision(
            index: 2,
            action: QuestionPackAction.create,
            stemPreview: '丙',
          ),
        ],
        warnings: <String>['第 2 道题与题库已有题目重复，导入时跳过'],
        missingTagPaths: <String>['化学'],
      );
      expect(plan.isEmpty, isFalse);
      expect(plan.createCount, 2);
      expect(plan.skipCount, 1);
      expect(plan.createIndexes, <int>[0, 2]);
      expect(plan.hasWarnings, isTrue);
      expect(plan.missingTagPaths, <String>['化学']);
    });

    test('toJson 扁平给出计数、决策列表与告警', () {
      const QuestionPackImportPlan plan = QuestionPackImportPlan(
        decisions: <QuestionPackDecision>[
          QuestionPackDecision(
            index: 0,
            action: QuestionPackAction.create,
            stemPreview: '甲',
          ),
        ],
        warnings: <String>['第 1 道题与题库已有题目重复，导入时跳过'],
        missingTagPaths: <String>['化学'],
      );
      expect(plan.toJson(), <String, Object?>{
        'create_count': 1,
        'update_count': 0,
        'skip_count': 0,
        'decisions': <Map<String, Object?>>[
          <String, Object?>{
            'index': 0,
            'action': 'create',
            'stem_preview': '甲',
          },
        ],
        'warnings': <String>['第 1 道题与题库已有题目重复，导入时跳过'],
        'missing_tag_paths': <String>['化学'],
      });
    });
  });

  group('questionPackMediaPath', () {
    test('基本路径：题号从 1 起、媒体序号从 0 起', () {
      expect(
        questionPackMediaPath(
            questionIndex: 3, mediaIndex: 0, extension: 'png'),
        'media/q3/0.png',
      );
      expect(
        questionPackMediaPath(
            questionIndex: 1, mediaIndex: 0, extension: 'png'),
        'media/q1/0.png',
      );
    });

    test('扩展名前导点去掉并转小写', () {
      expect(
        questionPackMediaPath(
            questionIndex: 2, mediaIndex: 1, extension: '.PNG'),
        'media/q2/1.png',
      );
    });

    test('大写无点扩展名也归一', () {
      expect(
        questionPackMediaPath(
            questionIndex: 2, mediaIndex: 3, extension: 'JPG'),
        'media/q2/3.jpg',
      );
    });

    test('扩展名两侧空白被忽略', () {
      expect(
        questionPackMediaPath(
            questionIndex: 1, mediaIndex: 2, extension: ' .jpeg '),
        'media/q1/2.jpeg',
      );
    });

    test('多个前导点也全部去掉', () {
      expect(
        questionPackMediaPath(
            questionIndex: 1, mediaIndex: 0, extension: '..WEBP'),
        'media/q1/0.webp',
      );
    });

    test('所有支持的扩展名都能生成路径', () {
      const List<String> extensions = <String>[
        'png',
        'jpg',
        'jpeg',
        'gif',
        'webp',
        'bmp',
        'heic',
      ];
      for (final String ext in extensions) {
        expect(
          questionPackMediaPath(
              questionIndex: 7, mediaIndex: 4, extension: ext),
          'media/q7/4.$ext',
        );
      }
    });

    test('questionIndex 0 抛 ArgumentError', () {
      expect(
        () => questionPackMediaPath(
            questionIndex: 0, mediaIndex: 0, extension: 'png'),
        throwsArgumentError,
      );
    });

    test('questionIndex 负数抛 ArgumentError', () {
      expect(
        () => questionPackMediaPath(
            questionIndex: -2, mediaIndex: 0, extension: 'png'),
        throwsArgumentError,
      );
    });

    test('mediaIndex 负数抛 ArgumentError', () {
      expect(
        () => questionPackMediaPath(
            questionIndex: 1, mediaIndex: -1, extension: 'png'),
        throwsArgumentError,
      );
    });

    test('空扩展名抛 ArgumentError', () {
      expect(
        () => questionPackMediaPath(
            questionIndex: 1, mediaIndex: 0, extension: '   '),
        throwsArgumentError,
      );
    });

    test('不支持的扩展名抛 ArgumentError', () {
      expect(
        () => questionPackMediaPath(
            questionIndex: 1, mediaIndex: 0, extension: 'txt'),
        throwsArgumentError,
      );
    });

    test('带尾点的扩展名也算非法', () {
      expect(
        () => questionPackMediaPath(
            questionIndex: 1, mediaIndex: 0, extension: 'png.'),
        throwsArgumentError,
      );
    });
  });

  group('questionPackSourceKey', () {
    test('null 题号返回 null', () {
      expect(questionPackSourceKey(zujuanQuestionId: null), isNull);
    });

    test('空串返回 null', () {
      expect(questionPackSourceKey(zujuanQuestionId: ''), isNull);
    });

    test('只有空白返回 null（含制表、换行与全角空格）', () {
      expect(questionPackSourceKey(zujuanQuestionId: '   '), isNull);
      expect(questionPackSourceKey(zujuanQuestionId: '\t\n'), isNull);
      expect(questionPackSourceKey(zujuanQuestionId: '　'), isNull);
    });

    test('trim 两侧空白后返回题号', () {
      expect(questionPackSourceKey(zujuanQuestionId: ' 123456 '), '123456');
      expect(questionPackSourceKey(zujuanQuestionId: '\t7\n'), '7');
    });

    test('不校验格式，非数字题号原样保留', () {
      expect(questionPackSourceKey(zujuanQuestionId: ' q-abc '), 'q-abc');
      expect(
        questionPackSourceKey(zujuanQuestionId: '10q35583902'),
        '10q35583902',
      );
    });

    test('不改变大小写与内部字符', () {
      expect(questionPackSourceKey(zujuanQuestionId: ' AbC '), 'AbC');
      expect(questionPackSourceKey(zujuanQuestionId: 'a b'), 'a b');
    });

    test('bankId 不参与认题：同一题号得到同一个键', () {
      expect(
        questionPackSourceKey(zujuanQuestionId: '42'),
        questionPackSourceKey(zujuanQuestionId: ' 42 '),
      );
    });
  });

  group('QuestionPackAction 与 QuestionPackDecision：update 扩展', () {
    test('update 常量的机器可读值', () {
      expect(QuestionPackAction.update, 'update');
    });

    test('labelZh 更新', () {
      expect(QuestionPackAction.labelZh(QuestionPackAction.update), '更新');
    });

    test('更新决策的 toJson 带 existing_question_id，不带 skip_reason', () {
      const QuestionPackDecision decision = QuestionPackDecision(
        index: 3,
        action: QuestionPackAction.update,
        stemPreview: '改过公式的题',
        serialNo: 7,
        existingQuestionId: 'q-42',
      );
      expect(decision.toJson(), <String, Object?>{
        'index': 3,
        'action': 'update',
        'stem_preview': '改过公式的题',
        'serial_no': 7,
        'existing_question_id': 'q-42',
      });
    });

    test('新建/跳过决策省略 existing_question_id', () {
      const QuestionPackDecision create = QuestionPackDecision(
        index: 0,
        action: QuestionPackAction.create,
        stemPreview: '新题',
      );
      const QuestionPackDecision skip = QuestionPackDecision(
        index: 1,
        action: QuestionPackAction.skipDuplicate,
        stemPreview: '重复题',
        skipReason: '题库里已经有同一道题（题干指纹相同）',
      );
      expect(create.toJson().containsKey('existing_question_id'), isFalse);
      expect(skip.toJson().containsKey('existing_question_id'), isFalse);
    });

    test('值语义包含 existingQuestionId', () {
      const QuestionPackDecision a = QuestionPackDecision(
        index: 1,
        action: QuestionPackAction.update,
        stemPreview: '题干',
        existingQuestionId: 'q-1',
      );
      const QuestionPackDecision b = QuestionPackDecision(
        index: 1,
        action: QuestionPackAction.update,
        stemPreview: '题干',
        existingQuestionId: 'q-1',
      );
      const QuestionPackDecision c = QuestionPackDecision(
        index: 1,
        action: QuestionPackAction.update,
        stemPreview: '题干',
        existingQuestionId: 'q-2',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('toString 带 existingQuestionId', () {
      const QuestionPackDecision decision = QuestionPackDecision(
        index: 2,
        action: QuestionPackAction.update,
        stemPreview: '题干',
        existingQuestionId: 'q-9',
      );
      expect(decision.toString(), contains('existingQuestionId: q-9'));
    });
  });

  group('planQuestionPackImport：按组卷网题号更新', () {
    test('映射命中题号时更新，不新建也不跳过', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '老题（改了公式）', zujuanQuestionId: '999001'),
          _record(stem: '新题'),
        ],
        existingQuestionIdByZujuanQuestionId: <String, String>{'999001': 'q-1'},
      );
      expect(plan.decisions[0].action, QuestionPackAction.update);
      expect(plan.decisions[0].existingQuestionId, 'q-1');
      expect(plan.decisions[0].skipReason, isNull);
      expect(plan.decisions[1].action, QuestionPackAction.create);
      expect(plan.createCount, 1);
      expect(plan.updateCount, 1);
      expect(plan.skipCount, 0);
      expect(plan.createIndexes, <int>[1]);
      expect(plan.updatedIndexes, <int>[0]);
      expect(plan.warnings, isEmpty);
    });

    test('题号两侧空白按 trim 后查表', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '题', zujuanQuestionId: ' 126 '),
        ],
        existingQuestionIdByZujuanQuestionId: <String, String>{'126': 'q-126'},
      );
      expect(plan.decisions.single.action, QuestionPackAction.update);
      expect(plan.decisions.single.existingQuestionId, 'q-126');
    });

    test('映射值原样透传（不要求是数字 id）', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '题', zujuanQuestionId: '77'),
        ],
        existingQuestionIdByZujuanQuestionId: <String, String>{
          '77': 'local-42'
        },
      );
      expect(plan.decisions.single.existingQuestionId, 'local-42');
      expect(
          plan.decisions.single.toJson()['existing_question_id'], 'local-42');
    });

    test('update 优先于题库已有指纹跳过', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '老题', zujuanQuestionId: '888'),
        ],
        existingStems: <String>['老题'],
        existingQuestionIdByZujuanQuestionId: <String, String>{'888': 'q-8'},
      );
      expect(plan.decisions.single.action, QuestionPackAction.update);
      expect(plan.decisions.single.existingQuestionId, 'q-8');
      expect(plan.skipCount, 0);
      expect(plan.warnings, isEmpty);
    });

    test('update 不因包内同指纹被跳过', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '同一题干'),
          _record(stem: '同一题干', zujuanQuestionId: '777'),
        ],
        existingQuestionIdByZujuanQuestionId: <String, String>{'777': 'q-7'},
      );
      expect(
        plan.decisions.map((QuestionPackDecision d) => d.action),
        <String>[QuestionPackAction.create, QuestionPackAction.update],
      );
      expect(plan.updatedIndexes, <int>[1]);
      expect(plan.decisions[1].existingQuestionId, 'q-7');
    });

    test('更新决策透传 serialNo 与 stemPreview', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '  改过的   题干 ', serialNo: 15, zujuanQuestionId: '1'),
        ],
        existingQuestionIdByZujuanQuestionId: <String, String>{'1': 'q-1'},
      );
      final QuestionPackDecision decision = plan.decisions.single;
      expect(decision.action, QuestionPackAction.update);
      expect(decision.serialNo, 15);
      expect(decision.stemPreview, '改过的 题干');
      expect(decision.toJson()['serial_no'], 15);
    });

    test('多个更新时 updatedIndexes 升序且计数正确', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '甲', zujuanQuestionId: 'a'),
          _record(stem: '乙'),
          _record(stem: '丙', zujuanQuestionId: 'c'),
        ],
        existingQuestionIdByZujuanQuestionId: <String, String>{
          'a': 'q-a',
          'c': 'q-c',
        },
      );
      expect(plan.updateCount, 2);
      expect(plan.updatedIndexes, <int>[0, 2]);
      expect(plan.createCount, 1);
      expect(plan.createIndexes, <int>[1]);
      expect(plan.skipCount, 0);
    });

    test('更新、新建、跳过混合时三种计数相加等于决策数', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '甲', zujuanQuestionId: 'a'),
          _record(stem: '老题'),
          _record(stem: '丙'),
        ],
        existingStems: <String>['老题'],
        existingQuestionIdByZujuanQuestionId: <String, String>{'a': 'q-a'},
      );
      expect(plan.updateCount, 1);
      expect(plan.createCount, 1);
      expect(plan.skipCount, 1);
      expect(plan.decisions.length, 3);
    });

    test('包内同题号第二条跳过（映射命中场景）并给告警', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '题一（新公式）', zujuanQuestionId: 'X1'),
          _record(stem: '题一（又改了一次）', zujuanQuestionId: 'X1'),
        ],
        existingQuestionIdByZujuanQuestionId: <String, String>{'X1': 'q-1'},
      );
      expect(plan.decisions[0].action, QuestionPackAction.update);
      expect(plan.decisions[1].action, QuestionPackAction.skipDuplicate);
      expect(plan.decisions[1].skipReason, '与包内第 1 道题是同一个组卷网题号');
      expect(
        plan.warnings,
        <String>['包内第 2 道与第 1 道是同一个组卷网题号，只导入前一道'],
      );
      expect(plan.updateCount, 1);
      expect(plan.skipCount, 1);
      expect(plan.updatedIndexes, <int>[0]);
    });

    test('包内同题号第二条跳过（映射未命中，第一条新建）', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '甲', zujuanQuestionId: 'X2'),
          _record(stem: '乙', zujuanQuestionId: 'X2'),
        ],
      );
      expect(
        plan.decisions.map((QuestionPackDecision d) => d.action),
        <String>[QuestionPackAction.create, QuestionPackAction.skipDuplicate],
      );
      expect(plan.decisions[1].skipReason, '与包内第 1 道题是同一个组卷网题号');
      expect(
        plan.warnings,
        <String>['包内第 2 道与第 1 道是同一个组卷网题号，只导入前一道'],
      );
    });

    test('包内同题号第二条指纹也命中题库时按旧指纹原因跳过（指纹优先于包内题号）', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '甲', zujuanQuestionId: 'X3'),
          _record(stem: '老题干', zujuanQuestionId: 'X3'),
        ],
        existingStems: <String>['老题干'],
        existingQuestionIdByZujuanQuestionId: <String, String>{'X3': 'q-3'},
      );
      expect(plan.decisions[0].action, QuestionPackAction.update);
      expect(plan.decisions[1].action, QuestionPackAction.skipDuplicate);
      expect(
        plan.decisions[1].skipReason,
        '题库里已经有同一道题（题干指纹相同）',
      );
      expect(plan.warnings, <String>['第 2 道题与题库已有题目重复，导入时跳过']);
    });

    test('空题号不参与题号去重（旧行为：不同题干都新建）', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '甲', zujuanQuestionId: ''),
          _record(stem: '乙', zujuanQuestionId: '   '),
        ],
        existingQuestionIdByZujuanQuestionId: <String, String>{'': 'q-empty'},
      );
      expect(
        plan.decisions.map((QuestionPackDecision d) => d.action),
        <String>[QuestionPackAction.create, QuestionPackAction.create],
      );
      expect(plan.updateCount, 0);
      expect(plan.warnings, isEmpty);
    });

    test('空题号与真题号混排：只有真题号命中 update', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '甲', zujuanQuestionId: ' 42 '),
          _record(stem: '乙', zujuanQuestionId: '  '),
        ],
        existingQuestionIdByZujuanQuestionId: <String, String>{'42': 'q-42'},
      );
      expect(plan.decisions[0].action, QuestionPackAction.update);
      expect(plan.decisions[1].action, QuestionPackAction.create);
      expect(plan.updateCount, 1);
    });

    test('映射不含该题号时按指纹/新建判定', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '老题', zujuanQuestionId: 'X9'),
          _record(stem: '新题', zujuanQuestionId: 'Y9'),
        ],
        existingStems: <String>['老题'],
        existingQuestionIdByZujuanQuestionId: <String, String>{'其他': 'q-9'},
      );
      expect(plan.decisions[0].action, QuestionPackAction.skipDuplicate);
      expect(
        plan.decisions[0].skipReason,
        '题库里已经有同一道题（题干指纹相同）',
      );
      expect(plan.decisions[1].action, QuestionPackAction.create);
      expect(plan.updateCount, 0);
    });

    test('空映射不抛异常，全部按指纹/新建判定', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '甲', zujuanQuestionId: 'q1'),
        ],
        existingQuestionIdByZujuanQuestionId: const <String, String>{},
      );
      expect(plan.decisions.single.action, QuestionPackAction.create);
      expect(plan.updateCount, 0);
      expect(plan.updatedIndexes, isEmpty);
    });

    test('映射只读不写', () {
      final Map<String, String> existingById = <String, String>{'q1': 'id-1'};
      _plan(
        <QuestionPackRecord>[
          _record(stem: '甲', zujuanQuestionId: 'q1'),
        ],
        existingQuestionIdByZujuanQuestionId: existingById,
      );
      expect(existingById, <String, String>{'q1': 'id-1'});
    });

    test('指纹函数对每道题仍恰好调用一次（含 update 记录）', () {
      var calls = 0;
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '甲', zujuanQuestionId: 'a'),
          _record(stem: '乙'),
          _record(stem: '丙'),
        ],
        existingQuestionIdByZujuanQuestionId: <String, String>{'a': 'q-a'},
        fingerprintOf: (String stem) {
          calls++;
          return _fingerprint(stem);
        },
      );
      expect(calls, 3);
      expect(plan.updateCount, 1);
      expect(plan.createCount, 2);
    });

    test('更新记录也贡献缺失标签告警，且缺失标签告警排在跳过告警之后', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(
            stem: '甲',
            zujuanQuestionId: 'a',
            tagPaths: <String>['升级标签'],
          ),
          _record(stem: '老题'),
        ],
        existingStems: <String>['老题'],
        existingQuestionIdByZujuanQuestionId: <String, String>{'a': 'q-a'},
      );
      expect(plan.warnings, <String>[
        '第 2 道题与题库已有题目重复，导入时跳过',
        '标签 升级标签 在题库里不存在，导入后相关题不挂这个标签',
      ]);
      expect(plan.missingTagPaths, <String>['升级标签']);
    });

    test('全是更新时没有告警', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '甲', zujuanQuestionId: 'a'),
          _record(stem: '乙', zujuanQuestionId: 'b'),
        ],
        existingQuestionIdByZujuanQuestionId: <String, String>{
          'a': 'q-a',
          'b': 'q-b',
        },
      );
      expect(plan.updateCount, 2);
      expect(plan.hasWarnings, isFalse);
      expect(plan.warnings, isEmpty);
      expect(plan.missingTagPaths, isEmpty);
    });

    test('跳过告警按题序排列（包内题号跳过与题库指纹跳过混排）', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '甲', zujuanQuestionId: 'X5'),
          _record(stem: '乙', zujuanQuestionId: 'X5'),
          _record(stem: '老题'),
        ],
        existingStems: <String>['老题'],
      );
      expect(plan.warnings, <String>[
        '包内第 2 道与第 1 道是同一个组卷网题号，只导入前一道',
        '第 3 道题与题库已有题目重复，导入时跳过',
      ]);
    });

    test('同一个题号在包内出现三次：后续都按第 1 道跳过', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '甲', zujuanQuestionId: 'X6'),
          _record(stem: '乙', zujuanQuestionId: 'X6'),
          _record(stem: '丙', zujuanQuestionId: 'X6'),
        ],
        existingQuestionIdByZujuanQuestionId: <String, String>{'X6': 'q-6'},
      );
      expect(
        plan.decisions.map((QuestionPackDecision d) => d.action),
        <String>[
          QuestionPackAction.update,
          QuestionPackAction.skipDuplicate,
          QuestionPackAction.skipDuplicate,
        ],
      );
      expect(plan.decisions[1].skipReason, '与包内第 1 道题是同一个组卷网题号');
      expect(plan.decisions[2].skipReason, '与包内第 1 道题是同一个组卷网题号');
      expect(plan.warnings, <String>[
        '包内第 2 道与第 1 道是同一个组卷网题号，只导入前一道',
        '包内第 3 道与第 1 道是同一个组卷网题号，只导入前一道',
      ]);
    });

    test('更新记录也算包内已出现：后面同指纹记录按包内指纹跳过', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '同一题干', zujuanQuestionId: 'X7'),
          _record(stem: '同一题干'),
        ],
        existingQuestionIdByZujuanQuestionId: <String, String>{'X7': 'q-7'},
      );
      expect(plan.decisions[0].action, QuestionPackAction.update);
      expect(plan.decisions[1].action, QuestionPackAction.skipDuplicate);
      expect(plan.decisions[1].skipReason, '与包内第 1 道题重复（题干指纹相同）');
      expect(plan.warnings, <String>['包内第 2 道与第 1 道是同一道题，只导入前一道']);
    });

    test('plan.toJson 带 update_count 与决策里的 existing_question_id', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '甲', zujuanQuestionId: 'a'),
          _record(stem: '乙'),
        ],
        existingQuestionIdByZujuanQuestionId: <String, String>{'a': 'q-a'},
      );
      final Map<String, Object?> json = plan.toJson();
      expect(json.keys.toList(), <String>[
        'create_count',
        'update_count',
        'skip_count',
        'decisions',
        'warnings',
        'missing_tag_paths',
      ]);
      expect(json['create_count'], 1);
      expect(json['update_count'], 1);
      expect(json['skip_count'], 0);
      final List<Object?> decisions = json['decisions']! as List<Object?>;
      final Map<String, Object?> first = decisions[0]! as Map<String, Object?>;
      final Map<String, Object?> second = decisions[1]! as Map<String, Object?>;
      expect(first['action'], 'update');
      expect(first['existing_question_id'], 'q-a');
      expect(second.containsKey('existing_question_id'), isFalse);
    });

    test('空包 + 非空映射：空计划、updateCount 为 0', () {
      final QuestionPackImportPlan plan = _plan(
        const <QuestionPackRecord>[],
        existingQuestionIdByZujuanQuestionId: <String, String>{'a': 'q-a'},
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.updateCount, 0);
      expect(plan.updatedIndexes, isEmpty);
      expect(plan.toJson()['update_count'], 0);
    });
  });

  group('planQuestionPackImport：updateExisting=false 回退旧行为', () {
    test('映射命中也不更新，题库已有指纹仍跳过', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '老题', zujuanQuestionId: 'X7'),
        ],
        existingStems: <String>['老题'],
        existingQuestionIdByZujuanQuestionId: <String, String>{'X7': 'q-7'},
        updateExisting: false,
      );
      expect(plan.decisions.single.action, QuestionPackAction.skipDuplicate);
      expect(plan.decisions.single.existingQuestionId, isNull);
      expect(plan.updateCount, 0);
      expect(
        plan.decisions.single.skipReason,
        '题库里已经有同一道题（题干指纹相同）',
      );
    });

    test('同题号两条不同题干都新建（旧行为，不做题号去重）', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '甲', zujuanQuestionId: 'X8'),
          _record(stem: '乙', zujuanQuestionId: 'X8'),
        ],
        existingQuestionIdByZujuanQuestionId: <String, String>{'X8': 'q-8'},
        updateExisting: false,
      );
      expect(
        plan.decisions.map((QuestionPackDecision d) => d.action),
        <String>[QuestionPackAction.create, QuestionPackAction.create],
      );
      expect(plan.updateCount, 0);
      expect(plan.warnings, isEmpty);
    });

    test('输出与不带题号的旧调用逐字段一致', () {
      final QuestionPackImportPlan legacy = _plan(
        <QuestionPackRecord>[
          _record(stem: '甲'),
          _record(stem: '老题'),
        ],
        existingStems: <String>['老题'],
      );
      final QuestionPackImportPlan fallback = _plan(
        <QuestionPackRecord>[
          _record(stem: '甲', zujuanQuestionId: 'a'),
          _record(stem: '老题', zujuanQuestionId: 'b'),
        ],
        existingStems: <String>['老题'],
        existingQuestionIdByZujuanQuestionId: <String, String>{
          'a': 'q-a',
          'b': 'q-b',
        },
        updateExisting: false,
      );
      expect(fallback.toJson(), legacy.toJson());
      expect(fallback.warnings, legacy.warnings);
      expect(fallback.missingTagPaths, legacy.missingTagPaths);
    });

    test('updateExisting 缺省为 true（不传也会更新）', () {
      final QuestionPackImportPlan plan = _plan(
        <QuestionPackRecord>[
          _record(stem: '甲', zujuanQuestionId: 'a'),
        ],
        existingQuestionIdByZujuanQuestionId: <String, String>{'a': 'q-a'},
      );
      expect(plan.decisions.single.action, QuestionPackAction.update);
      expect(plan.updateCount, 1);
    });
  });
}
