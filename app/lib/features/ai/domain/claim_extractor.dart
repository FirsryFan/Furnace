/// 确定性 ClaimExtractor：纯规则/语法模式从 trace step 抽结构化 claim。
///
/// 不调用模型、不编造：无法归类的数学句标成 [ExtractedClaimKind.unclassified]，
/// 完全不像 claim 的句子直接跳过。抽取内容包括：
///
///  * 类别：equation / inequality / condition / decision / result / unclassified；
///  * 变量（含下标，如 `m_1`）、已知单位（如 `J`、`m/s^2`）、实体（只认调用方
///    给出的词表，不凭空发明）、分支关键词（若/当/情形/①/临界/需/所以…）。
///
/// 每个 claim 都记录来源 step id、句子序号（evidenceRef）与 normalized hash，可
/// 回溯到 trace。
library;

import 'claim.dart';
import 'normalizer.dart';

/// 确定性抽取的 claim 类别（不复用 solver 的 `ClaimKind`，两者语义不同）。
enum ExtractedClaimKind {
  equation('equation'),
  inequality('inequality'),
  condition('condition'),
  decision('decision'),
  result('result'),
  unclassified('unclassified');

  const ExtractedClaimKind(this.id);

  final String id;
}

/// 一条从 trace step 机械抽取的 claim。
class ExtractedClaim {
  const ExtractedClaim({
    required this.id,
    required this.kind,
    required this.text,
    required this.normalized,
    required this.stepId,
    required this.sourceHash,
    required this.evidenceRef,
    this.variables = const <String>[],
    this.units = const <String>[],
    this.branchKeywords = const <String>[],
    this.entities = const <String>[],
  });

  /// 稳定 id（step + 句子序号 + normalized hash）。
  final String id;

  final ExtractedClaimKind kind;

  /// solver 原文句子（未改写）。
  final String text;

  /// 归一化文本（匹配用）。
  final String normalized;

  /// 来源 step id。
  final String stepId;

  /// 该 claim 的稳定 hash（基于 normalized）。
  final String sourceHash;

  /// 证据引用：`trace:<stepId>#s<句子序号>`。
  final String evidenceRef;

  final List<String> variables;
  final List<String> units;
  final List<String> branchKeywords;
  final List<String> entities;

  bool get isUnclassified => kind == ExtractedClaimKind.unclassified;

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.id,
        'text': text,
        'normalized': normalized,
        'step_id': stepId,
        'source_hash': sourceHash,
        'evidence_ref': evidenceRef,
        'variables': variables,
        'units': units,
        'branch_keywords': branchKeywords,
        'entities': entities,
      };

  @override
  String toString() => 'ExtractedClaim(${kind.id} $stepId "$text")';
}

/// 纯规则 claim 抽取器。
class ClaimExtractor {
  const ClaimExtractor();

  /// 分支/条件/结论关键词（lead 设计：若/当/情形/①/临界/需/所以）。
  static const List<String> branchKeywords = <String>[
    '若',
    '如果',
    '当',
    '情形',
    '情况',
    '分支',
    '分类',
    '临界',
    '①',
    '②',
    '③',
    '④',
    '⑤',
    '⑥',
    '⑦',
    '⑧',
    '⑨',
    '⑩',
    '需',
    '所以',
    '因此',
    '故',
    '设',
    '已知',
    '假设',
  ];

  static const List<String> _decisionKeywords = <String>[
    '情形',
    '情况',
    '分支',
    '分类',
    '①',
    '②',
    '③',
    '④',
    '⑤',
    '⑥',
    '⑦',
    '⑧',
    '⑨',
    '⑩',
    '选',
    '两支',
    '取舍',
  ];

  static const List<String> _conditionKeywords = <String>[
    '若',
    '如果',
    '当',
    '设',
    '已知',
    '假设',
    '条件',
    '前提',
    '需',
    '要求',
    '临界',
    '定义域',
  ];

  static const List<String> _resultKeywords = <String>[
    '所以',
    '因此',
    '故',
    '可得',
    '得到',
    '得出',
    '结论',
    '综上',
  ];

  static const List<String> _functionNames = <String>[
    'sin',
    'cos',
    'tan',
    'ln',
    'log',
    'max',
    'min',
    'sqrt',
    'inf',
    'sum',
    'int',
  ];

  /// 多字母变量名（LaTeX 归一化后的希腊字母等），其余多字母词视为普通单词。
  static const List<String> _namedVariables = <String>[
    'theta',
    'alpha',
    'beta',
    'gamma',
    'lambda',
    'mu',
    'omega',
    'Delta',
    'delta',
    'rho',
    'phi',
    'varphi',
    'epsilon',
    'varepsilon',
    'pi',
  ];

  static final RegExp _inequalityPattern =
      RegExp(r'<=|>=|!=|(?<![<>=!])<(?![<=])|(?<![<>=!])>(?![>=])');
  static final RegExp _equalityPattern = RegExp(r'(?<![<>=!])=(?![=])');
  static final RegExp _mathHintPattern =
      RegExp(r'[0-9]|[A-Za-z](?:_[0-9A-Za-z]+)?|\^|/|\*|~=');
  static final RegExp _variablePattern = RegExp(r'[A-Za-z]+(?:_[0-9A-Za-z]+)?');

  /// 抽取一步里的全部 claim。
  List<ExtractedClaim> extract(
    NormalizedStep step, {
    List<String> entityVocabulary = const <String>[],
  }) {
    final sentences = <String>[
      for (final piece in step.traceStep.rawText.split(RegExp(r'[\n。；;]+')))
        if (piece.trim().isNotEmpty) piece.trim(),
    ];
    final claims = <ExtractedClaim>[];
    for (var index = 0; index < sentences.length; index++) {
      final text = sentences[index];
      final normalized = const Normalizer().normalize(text);
      final kind = _classify(normalized);
      if (kind == null) {
        continue;
      }
      final units = Normalizer.unitsIn(normalized);
      claims.add(ExtractedClaim(
        id: stableClaimHash('${step.stepId}|$index|$normalized'),
        kind: kind,
        text: text,
        normalized: normalized,
        stepId: step.stepId,
        sourceHash: stableClaimHash(normalized),
        evidenceRef: 'trace:${step.stepId}#s$index',
        variables: _variablesIn(normalized),
        units: units,
        branchKeywords: <String>[
          for (final keyword in branchKeywords)
            if (normalized.contains(keyword)) keyword,
        ],
        entities: <String>[
          for (final entity in entityVocabulary)
            if (entity.trim().isNotEmpty &&
                normalized.contains(const Normalizer().normalize(entity)))
              entity,
        ],
      ));
    }
    return claims;
  }

  /// 句子类别；null = 不像 claim，跳过（不编造）。
  ExtractedClaimKind? _classify(String normalized) {
    if (normalized.isEmpty) {
      return null;
    }
    if (_inequalityPattern.hasMatch(normalized)) {
      return ExtractedClaimKind.inequality;
    }
    if (_equalityPattern.hasMatch(normalized)) {
      return ExtractedClaimKind.equation;
    }
    if (_decisionKeywords.any(normalized.contains)) {
      return ExtractedClaimKind.decision;
    }
    if (_conditionKeywords.any(normalized.contains)) {
      return ExtractedClaimKind.condition;
    }
    if (_resultKeywords.any(normalized.contains)) {
      return ExtractedClaimKind.result;
    }
    if (_mathHintPattern.hasMatch(normalized)) {
      // 像数学但归不了类：标 unclassified，不强行编造。
      return ExtractedClaimKind.unclassified;
    }
    return null;
  }

  static List<String> _variablesIn(String normalized) {
    final found = <String>{};
    for (final match in _variablePattern.allMatches(normalized)) {
      final token = match.group(0);
      if (token == null || token.isEmpty) {
        continue;
      }
      final isNamed = _namedVariables.contains(token);
      final hasSubscript = token.contains('_');
      if (!isNamed && !hasSubscript && token.length > 1) {
        // 普通英文单词（sin/速度等）不是变量。
        continue;
      }
      if (_functionNames.contains(token) ||
          Normalizer.knownUnits.contains(token)) {
        continue;
      }
      found.add(token);
    }
    return found.toList();
  }
}
