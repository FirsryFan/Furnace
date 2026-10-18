import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/reasoning/capability_action.dart';
import 'package:furnace/domain/services/reasoning/capability_action_overlay.dart';
import 'package:furnace/domain/services/reasoning/capability_vocabulary_codec.dart';

CustomCapabilityAction _action({
  String key = 'force_diagram',
  String labelZh = '画受力图',
  String labelEn = 'Free-body diagram',
  String descriptionZh = '把研究对象独立出来，按性质逐个画力。',
  List<String> subjectHints = const <String>['physics', 'math'],
}) {
  return CustomCapabilityAction(
    key: key,
    labelZh: labelZh,
    labelEn: labelEn,
    descriptionZh: descriptionZh,
    subjectHints: subjectHints,
  );
}

CapabilityActionOverlay _overlayOf(List<CustomCapabilityAction> actions) {
  return CapabilityActionOverlay(customActions: actions);
}

/// 带 version 的对象形状。
Map<String, Object?> _objectDoc({
  Object? version = 1,
  Object? customActions,
  bool includeVersion = true,
}) {
  return <String, Object?>{
    if (includeVersion) 'version': version,
    'customActions': customActions,
  };
}

/// 条目形状；subjectHints 传 null 时不写这个字段。
Map<String, Object?> _entry(
  String key, {
  String labelZh = '测试动作',
  Object? subjectHints,
}) {
  return <String, Object?>{
    'key': key,
    'labelZh': labelZh,
    if (subjectHints != null) 'subjectHints': subjectHints,
  };
}

const String _bom = '\uFEFF';

String _docWith(Object? customActions) {
  return jsonEncode(_objectDoc(customActions: customActions));
}

void main() {
  group('编码：形状与稳定性', () {
    test('空 overlay 的 pretty 输出逐字节固定', () {
      expect(
        encodeCapabilityVocabularyJson(CapabilityActionOverlay.empty),
        '{\n  "version": 1,\n  "customActions": []\n}\n',
      );
    });

    test('空 overlay 的 compact 输出逐字节固定', () {
      expect(
        encodeCapabilityVocabularyJson(
          CapabilityActionOverlay.empty,
          pretty: false,
        ),
        '{"version":1,"customActions":[]}',
      );
    });

    test('pretty 以换行结尾且两空格缩进', () {
      final encoded = encodeCapabilityVocabularyJson(
          _overlayOf(<CustomCapabilityAction>[_action()]));
      expect(encoded.endsWith('\n'), isTrue);
      expect(encoded.contains('\n  "version": 1'), isTrue);
      expect(encoded.contains('\n      "key": "force_diagram"'), isTrue);
    });

    test('compact 不含换行与多余空白', () {
      final compact = encodeCapabilityVocabularyJson(
        CapabilityActionOverlay.empty,
        pretty: false,
      );
      expect(compact.contains('\n'), isFalse);
      expect(compact.contains(' '), isFalse);
    });

    test('顶层键顺序 version 在 customActions 之前', () {
      final encoded = encodeCapabilityVocabularyJson(
          _overlayOf(<CustomCapabilityAction>[_action()]));
      expect(encoded.indexOf('"version"'),
          lessThan(encoded.indexOf('"customActions"')));
    });

    test('条目字段顺序固定', () {
      final encoded = encodeCapabilityVocabularyJson(
          _overlayOf(<CustomCapabilityAction>[_action()]));
      final fields = <String>[
        '"key"',
        '"labelZh"',
        '"labelEn"',
        '"descriptionZh"',
        '"subjectHints"',
      ];
      var previous = -1;
      for (final field in fields) {
        final at = encoded.indexOf(field);
        expect(at, greaterThan(previous), reason: '字段顺序错：$field');
        previous = at;
      }
    });

    test('同一输入两次 pretty 编码逐字节相同', () {
      final overlay = _overlayOf(<CustomCapabilityAction>[_action()]);
      expect(
        encodeCapabilityVocabularyJson(overlay),
        encodeCapabilityVocabularyJson(overlay),
      );
    });

    test('同一输入两次 compact 编码逐字节相同', () {
      final overlay = _overlayOf(<CustomCapabilityAction>[_action()]);
      expect(
        encodeCapabilityVocabularyJson(overlay, pretty: false),
        encodeCapabilityVocabularyJson(overlay, pretty: false),
      );
    });

    test('单条目输出可解码为预期结构', () {
      final expected = <String, Object?>{
        'version': 1,
        'customActions': <Object?>[_action().toJson()],
      };
      expect(
        jsonDecode(encodeCapabilityVocabularyJson(
            _overlayOf(<CustomCapabilityAction>[_action()]))),
        expected,
      );
    });
  });

  group('往返：字段保真', () {
    test('单条目全字段往返保真', () {
      final original = _overlayOf(<CustomCapabilityAction>[_action()]);
      final decoded = decodeCapabilityVocabularyText(
          encodeCapabilityVocabularyJson(original));
      expect(decoded.overlay.toJson(), original.toJson());
    });

    test('多条动作顺序保真', () {
      final original = _overlayOf(<CustomCapabilityAction>[
        _action(),
        _action(
          key: 'energy_ledger',
          labelZh: '能量记账',
          labelEn: 'Energy ledger',
          descriptionZh: '把每一步的能量收支记清楚。',
          subjectHints: const <String>['physics', 'chemistry'],
        ),
      ]);
      final decoded = decodeCapabilityVocabularyText(
          encodeCapabilityVocabularyJson(original));
      expect(decoded.overlay.toJson(), original.toJson());
      expect(
          decoded.overlay.customActions.map((action) => action.key).toList(),
          <String>[
            'force_diagram',
            'energy_ledger',
          ]);
    });

    test('中文与 emoji 保真', () {
      final original = _overlayOf(<CustomCapabilityAction>[
        _action(
          labelZh: '画受力图 🧲',
          descriptionZh: '把对象孤立出来 🧲 按性质逐个画力。',
        ),
      ]);
      final decoded = decodeCapabilityVocabularyText(
          encodeCapabilityVocabularyJson(original));
      expect(decoded.overlay.customActions.single.labelZh, '画受力图 🧲');
      expect(
          decoded.overlay.customActions.single.descriptionZh, contains('🧲'));
    });

    test('subjectHints 往返保真且保序', () {
      final original = _overlayOf(<CustomCapabilityAction>[
        _action(subjectHints: const <String>['physics', 'math', 'informatics']),
      ]);
      final decoded = decodeCapabilityVocabularyText(
          encodeCapabilityVocabularyJson(original));
      expect(decoded.overlay.customActions.single.subjectHints, <String>[
        'physics',
        'math',
        'informatics',
      ]);
    });

    test('labelEn 与 descriptionZh 为空时往返保真', () {
      final original = _overlayOf(<CustomCapabilityAction>[
        _action(labelEn: '', descriptionZh: ''),
      ]);
      final decoded = decodeCapabilityVocabularyText(
          encodeCapabilityVocabularyJson(original));
      expect(decoded.overlay.toJson(), original.toJson());
      expect(decoded.overlay.customActions.single.labelEn, '');
    });

    test('pretty 与 compact 解码结果一致', () {
      final overlay = _overlayOf(<CustomCapabilityAction>[_action()]);
      final pretty = decodeCapabilityVocabularyText(
          encodeCapabilityVocabularyJson(overlay));
      final compact = decodeCapabilityVocabularyText(
        encodeCapabilityVocabularyJson(overlay, pretty: false),
      );
      expect(compact.overlay.toJson(), pretty.overlay.toJson());
    });

    test('往返解码无 issue 且版本为 1', () {
      final decoded = decodeCapabilityVocabularyText(
        encodeCapabilityVocabularyJson(
            _overlayOf(<CustomCapabilityAction>[_action()])),
      );
      expect(decoded.issues, isEmpty);
      expect(decoded.version, 1);
      expect(decoded.hasFatal, isFalse);
    });

    test('非法条目也原样往返（编码不做语义校验）', () {
      final original =
          _overlayOf(<CustomCapabilityAction>[_action(key: 'Bad_Key')]);
      final encoded = encodeCapabilityVocabularyJson(original);
      expect(encoded, contains('"Bad_Key"'));
      final decoded = decodeCapabilityVocabularyText(encoded);
      expect(decoded.overlay.toJson(), original.toJson());
      expect(decoded.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.entryRejected);
    });

    test('非法学科提示保留在 overlay 但不进合并词表', () {
      final original = _overlayOf(<CustomCapabilityAction>[
        _action(subjectHints: const <String>['astrology']),
      ]);
      final decoded = decodeCapabilityVocabularyText(
          encodeCapabilityVocabularyJson(original));
      expect(decoded.overlay.customActions.single.subjectHints,
          <String>['astrology']);
      expect(
          decoded.overlay.catalog.customActions.single.subjectHints, isEmpty);
    });
  });

  group('BOM、CRLF、空白与字节数', () {
    test('剥掉 BOM 且 hadBom 为 true', () {
      final text = '$_bom${_docWith(<Object?>[_entry('force_diagram')])}';
      final result = decodeCapabilityVocabularyText(text);
      expect(result.hadBom, isTrue);
      expect(result.version, 1);
      expect(result.overlay.customActions.single.key, 'force_diagram');
    });

    test('无 BOM 时 hadBom 为 false', () {
      final result = decodeCapabilityVocabularyText(_docWith(<Object?>[]));
      expect(result.hadBom, isFalse);
    });

    test('首尾空白与换行被忽略', () {
      final text = '  \n\t${_docWith(<Object?>[_entry('force_diagram')])}\n  ';
      final result = decodeCapabilityVocabularyText(text);
      expect(result.overlay.customActions, hasLength(1));
    });

    test('CRLF 文档可解析', () {
      const text = '{'
          '\r\n  "version": 1,'
          '\r\n  "customActions": []'
          '\r\n}';
      final result = decodeCapabilityVocabularyText(text);
      expect(result.version, 1);
      expect(result.issues, isEmpty);
    });

    test('BOM 加 CRLF 加首尾空白组合可解析', () {
      final text =
          '$_bom \r\n${_docWith(<Object?>[_entry('force_diagram')])}\r\n ';
      final result = decodeCapabilityVocabularyText(text);
      expect(result.hadBom, isTrue);
      expect(result.overlay.customActions, hasLength(1));
    });

    test('纯空白文档是 emptyDocument', () {
      final result = decodeCapabilityVocabularyText(' \n\t\r\n ');
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.emptyDocument);
      expect(result.issues.single.fatal, isTrue);
      expect(result.hadBom, isFalse);
    });

    test('只有 BOM 的文档是 emptyDocument', () {
      final result = decodeCapabilityVocabularyText('\uFEFF');
      expect(result.hadBom, isTrue);
      expect(result.byteLength, 3);
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.emptyDocument);
    });
  });

  group('顶层形状与版本', () {
    test('显式 version 1', () {
      final result = decodeCapabilityVocabularyText(
        jsonEncode(
            _objectDoc(customActions: <Object?>[_entry('force_diagram')])),
      );
      expect(result.version, 1);
      expect(result.issues, isEmpty);
    });

    test('version 缺省按 1', () {
      final result = decodeCapabilityVocabularyText(
        jsonEncode(
            _objectDoc(includeVersion: false, customActions: <Object?>[])),
      );
      expect(result.version, 1);
      expect(result.issues, isEmpty);
    });

    test('裸条目数组按 version 1', () {
      final result = decodeCapabilityVocabularyText(
        jsonEncode(<Object?>[_entry('force_diagram')]),
      );
      expect(result.version, 1);
      expect(result.issues, isEmpty);
      expect(result.overlay.customActions, hasLength(1));
    });

    test('version 2 报 unsupportedVersion 但继续解析', () {
      final result = decodeCapabilityVocabularyText(
        jsonEncode(_objectDoc(
            version: 2, customActions: <Object?>[_entry('force_diagram')])),
      );
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.unsupportedVersion);
      expect(result.version, 2);
      expect(result.overlay.customActions, hasLength(1));
    });

    test('version 0 报 invalidVersion 且 version 为 null', () {
      final result = decodeCapabilityVocabularyText(
        jsonEncode(_objectDoc(
            version: 0, customActions: <Object?>[_entry('force_diagram')])),
      );
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.invalidVersion);
      expect(result.version, isNull);
      expect(result.overlay.customActions, hasLength(1));
    });

    test('version 字符串报 versionNotInteger', () {
      final result = decodeCapabilityVocabularyText(
        jsonEncode(_objectDoc(version: '1', customActions: <Object?>[])),
      );
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.versionNotInteger);
      expect(result.version, isNull);
    });

    test('version null 报 versionNotInteger', () {
      final result = decodeCapabilityVocabularyText(
        jsonEncode(_objectDoc(version: null, customActions: <Object?>[])),
      );
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.versionNotInteger);
      expect(result.version, isNull);
    });

    test('version 1.5 报 versionNotInteger', () {
      final result = decodeCapabilityVocabularyText(
        jsonEncode(_objectDoc(version: 1.5, customActions: <Object?>[])),
      );
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.versionNotInteger);
    });

    test('version true 报 versionNotInteger', () {
      final result = decodeCapabilityVocabularyText(
        jsonEncode(_objectDoc(version: true, customActions: <Object?>[])),
      );
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.versionNotInteger);
    });

    test('未知顶层键被记录且按 key 排序', () {
      final doc = _objectDoc(customActions: <Object?>[])
        ..['zeta'] = 1
        ..['alpha'] = 2;
      final result = decodeCapabilityVocabularyText(jsonEncode(doc));
      expect(result.issues, hasLength(2));
      expect(
        result.issues.map((issue) => issue.code).toList(),
        <CapabilityVocabularyDecodeIssueCode>[
          CapabilityVocabularyDecodeIssueCode.unknownTopLevelKey,
          CapabilityVocabularyDecodeIssueCode.unknownTopLevelKey,
        ],
      );
      expect(result.issues.map((issue) => issue.key).toList(),
          <String>['alpha', 'zeta']);
      expect(result.overlay.customActions, isEmpty);
    });

    test('customActions 缺失时报 customActionsNotList', () {
      final result = decodeCapabilityVocabularyText(
        jsonEncode(<String, Object?>{'version': 1}),
      );
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.customActionsNotList);
      expect(result.overlay.isEmpty, isTrue);
      expect(result.version, 1);
    });

    test('customActions 不是数组时报 customActionsNotList', () {
      final result = decodeCapabilityVocabularyText(
        jsonEncode(_objectDoc(customActions: 'oops')),
      );
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.customActionsNotList);
      expect(result.overlay.isEmpty, isTrue);
    });

    test('空对象 {} 版本缺省且报 customActionsNotList', () {
      final result = decodeCapabilityVocabularyText('{}');
      expect(result.version, 1);
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.customActionsNotList);
    });

    test('版本问题排在未知顶层键之前', () {
      final doc = _objectDoc(version: 2, customActions: <Object?>[])
        ..['zzz'] = 1;
      final result = decodeCapabilityVocabularyText(jsonEncode(doc));
      expect(
        result.issues.map((issue) => issue.code).toList(),
        <CapabilityVocabularyDecodeIssueCode>[
          CapabilityVocabularyDecodeIssueCode.unsupportedVersion,
          CapabilityVocabularyDecodeIssueCode.unknownTopLevelKey,
        ],
      );
    });

    test('version 2 文档只要有条目仍 isUsable', () {
      final result = decodeCapabilityVocabularyText(
        jsonEncode(_objectDoc(
            version: 2, customActions: <Object?>[_entry('force_diagram')])),
      );
      expect(result.hasFatal, isFalse);
      expect(result.isUsable, isTrue);
    });
  });

  group('fatal：整体不可用的文档', () {
    test('空文本是 emptyDocument', () {
      final result = decodeCapabilityVocabularyText('');
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.emptyDocument);
      expect(result.issues.single.fatal, isTrue);
      expect(result.overlay.isEmpty, isTrue);
      expect(result.byteLength, 0);
    });

    test('纯空白是 emptyDocument', () {
      final result = decodeCapabilityVocabularyText('   \n\t');
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.emptyDocument);
    });

    test('JSON 缺右括号是 invalidJson', () {
      final result = decodeCapabilityVocabularyText('{"version": 1');
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.invalidJson);
      expect(result.issues.single.fatal, isTrue);
    });

    test('非 JSON 文本是 invalidJson', () {
      final result = decodeCapabilityVocabularyText('not json');
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.invalidJson);
    });

    test('顶层字符串是 invalidTopLevel', () {
      final result = decodeCapabilityVocabularyText(jsonEncode('hello'));
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.invalidTopLevel);
      expect(result.issues.single.message, contains('顶层'));
    });

    test('顶层数字是 invalidTopLevel', () {
      final result = decodeCapabilityVocabularyText('42');
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.invalidTopLevel);
    });

    test('顶层 null 是 invalidTopLevel', () {
      final result = decodeCapabilityVocabularyText('null');
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.invalidTopLevel);
    });

    test('顶层布尔是 invalidTopLevel', () {
      final result = decodeCapabilityVocabularyText('true');
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.invalidTopLevel);
    });

    test('超过 64KB 的文档只报 documentTooLarge', () {
      final oversized = jsonEncode(
        _objectDoc(
          customActions: <Object?>[],
        )..['note'] = 'x' * (64 * 1024),
      );
      final result = decodeCapabilityVocabularyText(oversized);
      expect(result.issues, hasLength(1));
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.documentTooLarge);
      expect(result.issues.single.fatal, isTrue);
      expect(result.issues.single.message, contains('超过上限'));
    });

    test('超长且非法 JSON 仍先报 documentTooLarge', () {
      final result = decodeCapabilityVocabularyText('{${'x' * (64 * 1024)}');
      expect(result.issues.single.code,
          CapabilityVocabularyDecodeIssueCode.documentTooLarge);
    });
  });

  group('条目级结构问题', () {
    test('非对象条目逐一记账且 index 正确', () {
      final doc = _objectDoc(
        customActions: <Object?>[
          null,
          42,
          <String, Object?>{'labelZh': '缺 key'},
          <String, Object?>{'key': null, 'labelZh': 'x'},
          <String, Object?>{'key': '   ', 'labelZh': 'x'},
          <String, Object?>{'key': 7, 'labelZh': 'x'},
          <String, Object?>{
            'key': <Object?>[],
            'labelZh': 'x',
          },
        ],
      );
      final result = decodeCapabilityVocabularyText(jsonEncode(doc));
      expect(result.issues, hasLength(7));
      expect(result.issues.map((issue) => issue.index).toList(),
          <int>[0, 1, 2, 3, 4, 5, 6]);
      expect(
        result.issues.map((issue) => issue.code).toList(),
        <CapabilityVocabularyDecodeIssueCode>[
          CapabilityVocabularyDecodeIssueCode.entryNotObject,
          CapabilityVocabularyDecodeIssueCode.entryNotObject,
          CapabilityVocabularyDecodeIssueCode.entryMissingKey,
          CapabilityVocabularyDecodeIssueCode.entryMissingKey,
          CapabilityVocabularyDecodeIssueCode.entryMissingKey,
          CapabilityVocabularyDecodeIssueCode.entryKeyNotString,
          CapabilityVocabularyDecodeIssueCode.entryKeyNotString,
        ],
      );
      expect(result.overlay.isEmpty, isTrue);
      expect(result.isUsable, isFalse);
    });

    test('坏条目之间的好条目仍导入且 index 不偏移', () {
      final doc = _objectDoc(
        customActions: <Object?>[
          42,
          _entry('good_one'),
          null,
          _entry('good_two'),
        ],
      );
      final result = decodeCapabilityVocabularyText(jsonEncode(doc));
      expect(
          result.overlay.customActions.map((action) => action.key).toList(),
          <String>[
            'good_one',
            'good_two',
          ]);
      expect(result.issues.map((issue) => issue.index).toList(), <int>[0, 2]);
    });

    test('末尾坏条目的 index 是原始下标', () {
      final doc = _objectDoc(
        customActions: <Object?>[_entry('good_one'), 7, null],
      );
      final result = decodeCapabilityVocabularyText(jsonEncode(doc));
      expect(result.issues.map((issue) => issue.index).toList(), <int>[1, 2]);
      expect(result.overlay.customActions, hasLength(1));
    });

    test('空 customActions 数组合法但 isUsable 为 false', () {
      final result = decodeCapabilityVocabularyText(_docWith(<Object?>[]));
      expect(result.issues, isEmpty);
      expect(result.version, 1);
      expect(result.overlay.isEmpty, isTrue);
      expect(result.isUsable, isFalse);
    });

    test('条目未知字段被忽略', () {
      final entry = _entry('force_diagram', labelZh: '画受力图')
        ..['unknown'] = true
        ..['sortOrder'] = 99;
      final result = decodeCapabilityVocabularyText(
        jsonEncode(_objectDoc(customActions: <Object?>[entry])),
      );
      expect(result.issues, isEmpty);
      final action = result.overlay.customActions.single;
      expect(action.key, 'force_diagram');
      expect(action.descriptionZh, '');
    });

    test('结构问题都是条目级', () {
      final result = decodeCapabilityVocabularyText(
        jsonEncode(_objectDoc(customActions: <Object?>[null])),
      );
      expect(result.issues.single.isEntryLevel, isTrue);
    });

    test('结构问题按 index 升序', () {
      final doc = _objectDoc(
        customActions: <Object?>[
          42,
          <String, Object?>{'labelZh': 'x'},
          <String, Object?>{'key': 7}
        ],
      );
      final result = decodeCapabilityVocabularyText(jsonEncode(doc));
      expect(
        result.issues.map((issue) => issue.code).toList(),
        <CapabilityVocabularyDecodeIssueCode>[
          CapabilityVocabularyDecodeIssueCode.entryNotObject,
          CapabilityVocabularyDecodeIssueCode.entryMissingKey,
          CapabilityVocabularyDecodeIssueCode.entryKeyNotString,
        ],
      );
      expect(
          result.issues.map((issue) => issue.index).toList(), <int>[0, 1, 2]);
    });
  });

  group('语义校验合并', () {
    test('非蛇形 key 被拒绝并带原因', () {
      final result = decodeCapabilityVocabularyText(
        _docWith(<Object?>[_entry('Bad_Key', labelZh: '坏 key')]),
      );
      final issue = result.issues.single;
      expect(issue.code, CapabilityVocabularyDecodeIssueCode.entryRejected);
      expect(issue.overlayReason,
          CapabilityActionOverlayIssueReason.keyNotSnakeCase);
      expect(issue.index, 0);
      expect(issue.key, 'Bad_Key');
    });

    test('内置 key 被拒绝', () {
      final result = decodeCapabilityVocabularyText(
        _docWith(<Object?>[_entry('case_split', labelZh: '分类')]),
      );
      expect(
        result.issues.single.overlayReason,
        CapabilityActionOverlayIssueReason.keyReserved,
      );
    });

    test('缺 labelZh 被拒绝', () {
      final result = decodeCapabilityVocabularyText(
        _docWith(<Object?>[_entry('force_diagram', labelZh: '   ')]),
      );
      expect(
        result.issues.single.overlayReason,
        CapabilityActionOverlayIssueReason.missingLabelZh,
      );
    });

    test('超长 key 被拒绝', () {
      final result = decodeCapabilityVocabularyText(
        _docWith(<Object?>[_entry('a' * 49)]),
      );
      expect(
        result.issues.single.overlayReason,
        CapabilityActionOverlayIssueReason.keyTooLong,
      );
    });

    test('重复 key 先到先得且 issue index 为 null', () {
      final result = decodeCapabilityVocabularyText(
        _docWith(<Object?>[
          _entry('dup_action', labelZh: '甲'),
          _entry('dup_action', labelZh: '乙')
        ]),
      );
      final issue = result.issues.single;
      expect(issue.code, CapabilityVocabularyDecodeIssueCode.entryRejected);
      expect(
          issue.overlayReason, CapabilityActionOverlayIssueReason.duplicateKey);
      expect(issue.index, isNull);
      expect(result.overlay.catalog.customActions, hasLength(1));
    });

    test('合并消息与 catalog issue 完全一致', () {
      final result = decodeCapabilityVocabularyText(
        _docWith(<Object?>[_entry('Bad_Key', labelZh: '坏 key')]),
      );
      expect(result.issues.single.message,
          result.overlay.catalog.issues.single.message);
    });

    test('合法自定义动作进入合并词表', () {
      final result = decodeCapabilityVocabularyText(
        _docWith(<Object?>[
          _entry('force_diagram',
              labelZh: '画受力图', subjectHints: <Object?>['physics'])
        ]),
      );
      expect(result.issues, isEmpty);
      expect(result.overlay.catalog.customActions, hasLength(1));
      expect(result.overlay.catalog.customActions.single.key, 'force_diagram');
      expect(result.overlay.catalog.actions,
          hasLength(CapabilityAction.catalog.length + 1));
    });

    test('被语义拒绝的条目仍在 overlay.customActions（结构性接收）', () {
      final result = decodeCapabilityVocabularyText(
        _docWith(<Object?>[_entry('Bad_Key', labelZh: '坏 key')]),
      );
      expect(result.overlay.customActions, hasLength(1));
      expect(result.overlay.catalog.customActions, isEmpty);
      expect(result.isUsable, isTrue);
    });

    test('条目级排序：index 0 的拒绝排在 index 1 的结构问题前', () {
      final result = decodeCapabilityVocabularyText(
        _docWith(<Object?>[_entry('Bad_Key', labelZh: '坏 key'), 42]),
      );
      expect(
        result.issues.map((issue) => issue.code).toList(),
        <CapabilityVocabularyDecodeIssueCode>[
          CapabilityVocabularyDecodeIssueCode.entryRejected,
          CapabilityVocabularyDecodeIssueCode.entryNotObject,
        ],
      );
      expect(result.issues.map((issue) => issue.index).toList(), <int>[0, 1]);
    });

    test('非法学科提示不导致拒绝且被 catalog 清掉', () {
      final result = decodeCapabilityVocabularyText(
        _docWith(<Object?>[
          _entry('force_diagram',
              labelZh: '画受力图', subjectHints: <Object?>['astrology'])
        ]),
      );
      expect(result.issues, isEmpty);
      expect(result.overlay.customActions.single.subjectHints,
          <String>['astrology']);
      expect(result.overlay.catalog.customActions.single.subjectHints, isEmpty);
    });
  });

  group('结果元数据、toJson 与分享', () {
    test('格式常量', () {
      expect(CapabilityVocabularyDecodeResult.formatVersion, 1);
      expect(CapabilityVocabularyDecodeResult.maxDocumentBytes, 65536);
    });

    test('有效文档的元数据', () {
      final result = decodeCapabilityVocabularyText(
        _docWith(<Object?>[_entry('force_diagram')]),
      );
      expect(result.hasFatal, isFalse);
      expect(result.isUsable, isTrue);
      expect(result.version, 1);
    });

    test('空词表文档 isUsable 为 false 但不是 fatal', () {
      final result = decodeCapabilityVocabularyText(_docWith(<Object?>[]));
      expect(result.hasFatal, isFalse);
      expect(result.isUsable, isFalse);
    });

    test('fatal 文档 isUsable 为 false', () {
      final result = decodeCapabilityVocabularyText('not json');
      expect(result.hasFatal, isTrue);
      expect(result.isUsable, isFalse);
      expect(result.overlay.isEmpty, isTrue);
      expect(result.version, isNull);
    });

    test('byteLength 等于原始 UTF-8 字节数', () {
      final text = '$_bom${_docWith(<Object?>[_entry('force_diagram')])}';
      final result = decodeCapabilityVocabularyText(text);
      expect(result.byteLength, utf8.encode(text).length);
      expect(result.byteLength, greaterThan(3));
    });

    test('fatal issue 的 toJson', () {
      final issue = decodeCapabilityVocabularyText('not json').issues.single;
      final json = issue.toJson();
      expect(json['code'], 'invalidJson');
      expect(json['fatal'], isTrue);
      expect(json['index'], isNull);
      expect(json['key'], isNull);
      expect(json['overlay_reason'], isNull);
      expect(json['message'], isA<String>());
    });

    test('条目级 issue 的 toJson 带 overlay_reason', () {
      final issue = decodeCapabilityVocabularyText(
        _docWith(<Object?>[_entry('Bad_Key', labelZh: '坏 key')]),
      ).issues.single;
      final json = issue.toJson();
      expect(json['code'], 'entryRejected');
      expect(json['fatal'], isFalse);
      expect(json['index'], 0);
      expect(json['key'], 'Bad_Key');
      expect(json['overlay_reason'], 'keyNotSnakeCase');
    });

    test('issue toString 含 code、index、key 与消息', () {
      final issue = decodeCapabilityVocabularyText(
        _docWith(<Object?>[_entry('Bad_Key', labelZh: '坏 key')]),
      ).issues.single;
      final text = issue.toString();
      expect(text, contains('entryRejected'));
      expect(text, contains('index: 0'));
      expect(text, contains('Bad_Key'));
      expect(text, contains(issue.message));
    });

    test('issues 列表不可修改', () {
      final result = decodeCapabilityVocabularyText(_docWith(<Object?>[]));
      expect(
        () => result.issues.add(
          const CapabilityVocabularyDecodeIssue(
            code: CapabilityVocabularyDecodeIssueCode.emptyDocument,
            message: 'x',
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('overlay.customActions 不可修改', () {
      final result = decodeCapabilityVocabularyText(
        _docWith(<Object?>[_entry('force_diagram')]),
      );
      expect(
        () => result.overlay.customActions.add(_action()),
        throwsUnsupportedError,
      );
    });

    test('tryEncodeOverlayForSharing 对空 overlay 返回 null', () {
      expect(tryEncodeOverlayForSharing(CapabilityActionOverlay.empty), isNull);
    });

    test('tryEncodeOverlayForSharing 与非空编码一致', () {
      final overlay = _overlayOf(<CustomCapabilityAction>[_action()]);
      expect(
        tryEncodeOverlayForSharing(overlay),
        encodeCapabilityVocabularyJson(overlay),
      );
      expect(
        tryEncodeOverlayForSharing(overlay, pretty: false),
        encodeCapabilityVocabularyJson(overlay, pretty: false),
      );
    });

    test('tryEncodeOverlayForSharing 的 compact 产物可往返', () {
      final overlay = _overlayOf(<CustomCapabilityAction>[_action()]);
      final shared = tryEncodeOverlayForSharing(overlay, pretty: false);
      expect(shared, isNotNull);
      final decoded = decodeCapabilityVocabularyText(shared!);
      expect(decoded.overlay.toJson(), overlay.toJson());
    });
  });
}
