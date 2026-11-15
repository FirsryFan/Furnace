import 'design_board.dart';

/// 学生提问 → 按需组织回答（P0 B11）。
///
/// 用户口径（2026-11-15）：简单题不预置解析；学生先做题，卡住时把问题写下来，
/// 系统再根据**这道题已有的内容**组织回答——而不是把解析预先塞给学生。
///
/// 这是一个纯 domain、确定性的原型：
/// - 输入：学生问题、题干、DAG 节点（label/body/formulas/keyQuantities/result）、
///   错因条目、可选答案；
/// - 匹配：把问题拆成 CJK 字符 n-gram（2–4 字）与 ASCII token，按字段权重
///   （label > 公式/关键量 > 结论 > body）给每个节点打分；再叠加“选项字母”
///   （A/B/C/D 真/假）与问题意图对节点 role/kind 的偏好；
/// - 组织：复述问题 → 相关步骤/公式 → 结论 → 易错点 → 可继续问；
/// - 无命中：明确说“这题没有直接对应内容”，不补写任何内容；
/// - 边界：只看学生可见字段，输出再过一层开发者 token 清洗；不调用外部 LLM。
///
/// 已知限制（原型边界，不当作语义理解）：同义改写、零词重叠的问法不保证命中；
/// 该匹配器不是 LLM，判的是“问题里的字面线索”而不是“问题真正想什么”。

/// 问题意图，只用于给节点 role/kind 加权，不做语义判断。
enum FeedbackIntent {
  /// 公式/表达式/怎么算。
  formula,

  /// 易错点/陷阱/为什么错。
  mistake,

  /// 步骤/思路/从哪开始。
  steps,

  /// 直接问答案/选项。
  answer,

  /// 为什么/原因/区别/原理。
  concept,

  /// 无法归类；仍然按字面线索匹配内容。
  other,
}

/// 一次已完成的问答；UI 保留历史以支持追问。
class FeedbackExchange {
  const FeedbackExchange({required this.question, required this.answer});

  final String question;
  final FeedbackAnswer answer;
}

/// 回答里引用的一步 Thinking DAG（只保留学生可见的短节点字段）。
class FeedbackStep {
  const FeedbackStep({
    required this.label,
    required this.explanation,
    required this.formulas,
    required this.keyQuantities,
    required this.result,
  });

  final String label;

  /// 节点正文的节选（超长时截断），只在非空时显示。
  final String explanation;
  final List<String> formulas;
  final List<String> keyQuantities;
  final String result;
}

/// 一条错因（错因板块里 `现象；根因：…；补救：…` 的结构化形态）。
class FeedbackMistake {
  const FeedbackMistake({
    required this.title,
    required this.rootCause,
    required this.remedy,
  });

  final String title;
  final String rootCause;
  final String remedy;

  bool get isEmpty => title.isEmpty && rootCause.isEmpty && remedy.isEmpty;
}

/// 基于内容组织出来的回答。
///
/// 所有文本都已按学生口径清洗过；不含 trust/hash/evidence/source 这类开发者
/// 字段，也不含节点 id 或报告腔。
class FeedbackAnswer {
  const FeedbackAnswer({
    required this.question,
    required this.intent,
    required this.matched,
    required this.restatement,
    required this.steps,
    required this.conclusion,
    required this.mistakes,
    required this.noMatchMessage,
    required this.closing,
    this.contextQuestion = '',
  });

  /// 学生原始问题（已 trim）。
  final String question;
  final FeedbackIntent intent;

  /// false 表示这题内容里没有能直接回答的内容；此时 [steps] 一定为空。
  final bool matched;

  /// 复述后的问题，例如 `你问的是：“为什么 C 不对？”`。
  final String restatement;
  final List<FeedbackStep> steps;

  /// 结论：有答案且学生问答案时是答案；否则是最后一个相关节点的结论。
  final String? conclusion;
  final List<FeedbackMistake> mistakes;

  /// 无命中时的固定说明：明确说没有对应内容。
  final String? noMatchMessage;

  /// 末尾邀请学生继续追问。
  final String closing;

  /// 追问上下文（含本轮问题，供下一轮合并）；不渲染给学生。
  final String contextQuestion;

  /// 回答引到的公式集合（测试与调试用）。
  List<String> get formulas =>
      <String>[for (final step in steps) ...step.formulas];

  /// 回答引到的关键量集合（测试与调试用）。
  List<String> get keyQuantities =>
      <String>[for (final step in steps) ...step.keyQuantities];

  bool get isEmpty => steps.isEmpty && mistakes.isEmpty;

  /// 纯文本渲染，供测试逐字符串扫描（UI 本身渲染结构化控件）。
  String toPlainText() {
    final lines = <String>[restatement];
    if (matched) {
      if (steps.isNotEmpty) {
        lines.add('相关步骤与公式：');
        for (var i = 0; i < steps.length; i++) {
          final step = steps[i];
          lines.add('${i + 1}. ${step.label}');
          if (step.explanation.isNotEmpty) {
            lines.add('   说明：${step.explanation}');
          }
          if (step.formulas.isNotEmpty) {
            lines.add('   公式：${step.formulas.join('；')}');
          }
          if (step.keyQuantities.isNotEmpty) {
            lines.add('   关键量：${step.keyQuantities.join('；')}');
          }
          if (step.result.isNotEmpty) {
            lines.add('   结论：${step.result}');
          }
        }
      }
      final conclusion = this.conclusion;
      if (conclusion != null && conclusion.isNotEmpty) {
        lines.add('结论：$conclusion');
      }
      if (mistakes.isNotEmpty) {
        lines.add('易错点：');
        for (var i = 0; i < mistakes.length; i++) {
          final mistake = mistakes[i];
          lines.add('${i + 1}. ${mistake.title}');
          if (mistake.rootCause.isNotEmpty) {
            lines.add('   根因：${mistake.rootCause}');
          }
          if (mistake.remedy.isNotEmpty) {
            lines.add('   补救：${mistake.remedy}');
          }
        }
      }
      lines.add(closing);
    } else if (noMatchMessage != null) {
      lines.add(noMatchMessage!);
    }
    return lines.join('\n');
  }
}

/// 按问题组织回答；确定性、无网络、无 LLM。
class FeedbackAnswerComposer {
  const FeedbackAnswerComposer({
    this.minimumScore = 2.0,
    this.maxSteps = 3,
    this.maxMistakes = 3,
    this.maxExplanationChars = 220,
  });

  /// 节点进入回答的最低分；低于它视为“没有直接对应内容”。
  final double minimumScore;

  /// 最多引用几个相关节点（防止一次把整张 DAG 塞给学生）。
  final int maxSteps;

  /// 最多引用几条错因。
  final int maxMistakes;

  /// 节点正文节选上限；超过按句号截断。
  final int maxExplanationChars;

  /// 学生问题 → 回答。
  ///
  /// [nodes] 是 Thinking DAG 节点（可为空：简单题不预置 DAG 时要走“没有直接
  /// 对应内容”分支，而不是编造）。[errorCauses] 是错因板块的原始条目。
  /// [priorExchanges] 是本页已问过的问题，用来让“那为什么 / 再详细点”这类
  /// 短追问继承上文。
  FeedbackAnswer ask({
    required String question,
    required String stem,
    required List<DagNode> nodes,
    List<String> errorCauses = const <String>[],
    String? answer,
    List<FeedbackExchange> priorExchanges = const <FeedbackExchange>[],
  }) {
    final trimmed = question.trim();
    final restatement = trimmed.isEmpty ? '你还没有写下问题。' : '你问的是：“$trimmed”';
    const noMatchMessage = '这题没有直接对应内容。可以换个问法，或继续问这题的其他部分。';
    const closing = '仍不明白可以继续问。';

    if (trimmed.isEmpty) {
      return FeedbackAnswer(
        question: trimmed,
        intent: FeedbackIntent.other,
        matched: false,
        restatement: restatement,
        steps: const <FeedbackStep>[],
        conclusion: null,
        mistakes: const <FeedbackMistake>[],
        noMatchMessage: noMatchMessage,
        closing: closing,
        contextQuestion: trimmed,
      );
    }

    final previous = priorExchanges.isEmpty ? null : priorExchanges.last;
    final followUp = previous != null && _looksLikeFollowUp(trimmed);
    // 追问不只是继承上一句问题，还要继承上一轮回答引到的内容：学生先问
    // “这题有什么易错点”，再问“那为什么”时，线索在错因正文里。
    final contextQuestion = followUp
        ? ('${previous.answer.contextQuestion} '
                '${_excerpt(previous.answer.toPlainText(), 800)} $trimmed')
            .trim()
        : trimmed;
    final query = _buildQuery(trimmed, contextQuestion, stem);

    // 1) 找相关节点。
    final scored = <_ScoredNode>[];
    for (var i = 0; i < nodes.length; i++) {
      final score = _scoreNode(nodes[i], query);
      if (score.strong && score.score >= minimumScore) {
        scored.add(_ScoredNode(index: i, score: score.score, node: nodes[i]));
      }
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.index.compareTo(b.index);
    });
    final selected = scored.take(maxSteps).toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    final steps = <FeedbackStep>[
      for (final item in selected)
        FeedbackStep(
          label: _studentSafe(item.node.label),
          explanation: _explanation(item.node.body),
          formulas: <String>[
            for (final formula in item.node.formulas) _studentSafe(formula),
          ],
          keyQuantities: <String>[
            for (final quantity in item.node.keyQuantities)
              _studentSafe(quantity),
          ],
          result: _studentSafe(item.node.result),
        ),
    ];

    // 2) 结论：学生直接问答案时给答案；否则用最后一个相关节点的结论。
    final asksAnswer = query.intent == FeedbackIntent.answer &&
        answer != null &&
        answer.trim().isNotEmpty;
    String? conclusion;
    if (asksAnswer) {
      conclusion = '本题答案：${_studentSafe(answer.trim())}';
    } else {
      for (final item in selected.reversed) {
        final result = _studentSafe(item.node.result);
        if (result.isNotEmpty) {
          conclusion = result;
          break;
        }
      }
    }

    // 3) 错因：只挑与问题字面线索相关的；学生泛问“易错点”时给本题记录的条目。
    final mistakes = _selectMistakes(errorCauses, query);

    // 命中口径：有相关步骤；或学生直接问答案且题目有答案；或学生问易错点且
    // 这题记录了错因。三者都算“这题有对应内容”，其余明确说没有。
    final matched = steps.isNotEmpty || asksAnswer || mistakes.isNotEmpty;
    return FeedbackAnswer(
      question: trimmed,
      intent: query.intent,
      matched: matched,
      restatement: restatement,
      steps: steps,
      conclusion: matched ? conclusion : null,
      mistakes: matched ? mistakes : const <FeedbackMistake>[],
      noMatchMessage: matched ? null : noMatchMessage,
      closing: closing,
      contextQuestion: contextQuestion,
    );
  }

  // ---------------------------------------------------------------------------
  // 问题解析
  // ---------------------------------------------------------------------------

  /// 短追问（“那为什么”“再详细点”）继承上一轮的上文。
  ///
  /// 判据刻意保守：只有“很短的问题”或带明确追问词才继承上文。像
  /// “概率怎么算”（5 字但没有追问词）仍按独立问题处理，避免把上一题的
  /// 内容带进这一问。
  bool _looksLikeFollowUp(String question) {
    final cjkCount = RegExp(r'[\u4e00-\u9fff]').allMatches(question).length;
    if (cjkCount == 0) {
      return false;
    }
    if (cjkCount <= 4) {
      return true;
    }
    return _followUpMarkers.any(question.contains);
  }

  _Query _buildQuery(String question, String contextQuestion, String stem) {
    final cjkTerms = <String>{};
    final asciiTerms = <String>{};
    final optionLetters = <String>{};

    _collectTerms(question, cjkTerms, asciiTerms, optionLetters);
    if (contextQuestion != question) {
      _collectTerms(contextQuestion, cjkTerms, asciiTerms, optionLetters);
    }
    // 问题点到某个选项时，把题干里该选项的原文也当作线索：
    // “C 为什么不对” → 选项 C 的“速度大小保持不变” → 找到判 C 的节点/错因。
    for (final letter in optionLetters) {
      _collectCjkNgrams(_optionText(stem, letter), cjkTerms);
    }

    // 词越多越难控制；按长度优先保留最有区分度的长词。
    final sortedCjk = cjkTerms.toList()
      ..sort((a, b) => b.runes.length.compareTo(a.runes.length));
    return _Query(
      cjkTerms: sortedCjk.take(160).toList(growable: false),
      asciiTerms: asciiTerms.toList(growable: false),
      optionLetters: optionLetters.toList(growable: false),
      intent: _intentOf(question),
      shortQuery: RegExp(r'[\u4e00-\u9fff]').allMatches(question).length <= 4,
    );
  }

  void _collectTerms(
    String text,
    Set<String> cjkTerms,
    Set<String> asciiTerms,
    Set<String> optionLetters,
  ) {
    _collectCjkNgrams(text, cjkTerms);
    final normalized = _normalizeForMatch(text);
    for (final match in RegExp(r'[a-z][a-z0-9]*').allMatches(normalized)) {
      final token = match.group(0)!;
      if (_asciiStopWords.contains(token)) {
        continue;
      }
      if (token.length == 1 && !_mathSymbols.contains(token)) {
        continue;
      }
      asciiTerms.add(token);
    }
    for (final letter in _optionLetters(text)) {
      optionLetters.add(letter);
    }
  }

  void _collectCjkNgrams(String text, Set<String> cjkTerms) {
    for (final run in _cjkRuns(text)) {
      for (var length = 2; length <= 4; length++) {
        if (run.length < length) {
          continue;
        }
        for (var start = 0; start + length <= run.length; start++) {
          final term = run.substring(start, start + length);
          if (_genericTerms.contains(term)) {
            continue;
          }
          cjkTerms.add(term);
        }
      }
    }
  }

  /// 题干里某个选项的原文（例如 `C. 速度大小保持不变` 的后半段）。
  ///
  /// 选项标记识别 `A.` / `B、` / `C．` 这类写法；找不到就返回空串。
  String _optionText(String stem, String letter) {
    final markers = RegExp(r'([A-D])[．.、]\s*').allMatches(stem).toList();
    for (var i = 0; i < markers.length; i++) {
      if (markers[i].group(1) != letter) {
        continue;
      }
      final start = markers[i].end;
      final end = i + 1 < markers.length ? markers[i + 1].start : stem.length;
      if (start >= end) {
        return '';
      }
      return stem.substring(start, end);
    }
    return '';
  }

  FeedbackIntent _intentOf(String question) {
    final text = question;
    if (_containsAny(text, _formulaHints)) {
      return FeedbackIntent.formula;
    }
    if (_containsAny(text, _mistakeHints)) {
      return FeedbackIntent.mistake;
    }
    if (_containsAny(text, _stepsHints)) {
      return FeedbackIntent.steps;
    }
    if (_containsAny(text, _answerHints)) {
      return FeedbackIntent.answer;
    }
    if (_containsAny(text, _conceptHints)) {
      return FeedbackIntent.concept;
    }
    return FeedbackIntent.other;
  }

  // ---------------------------------------------------------------------------
  // 节点打分
  // ---------------------------------------------------------------------------

  _NodeScore _scoreNode(DagNode node, _Query query) {
    final label = _normalizeForMatch(node.label);
    final body = _normalizeForMatch(node.body);
    final result = _normalizeForMatch(node.result);
    final formulas = _normalizeForMatch(node.formulas.join(' '));
    final quantities = _normalizeForMatch(node.keyQuantities.join(' '));
    final labelTokens = _tokens(label);
    final bodyTokens = _tokens(body);
    final resultTokens = _tokens(result);
    final formulaTokens = _tokens(formulas);
    final quantityTokens = _tokens(quantities);

    var score = 0.0;
    var strong = false;
    var weakMatches = 0;

    for (final term in query.cjkTerms) {
      final length = term.runes.length;
      double field;
      var inLabel = false;
      if (label.contains(term)) {
        field = 3.0;
        inLabel = true;
      } else if (formulas.contains(term)) {
        field = 2.5;
      } else if (quantities.contains(term)) {
        field = 2.5;
      } else if (result.contains(term)) {
        field = 2.0;
      } else if (body.contains(term)) {
        field = 1.5;
      } else {
        continue;
      }
      score += length * field / 2;
      if (length >= 3 || inLabel) {
        strong = true;
      } else {
        weakMatches++;
      }
    }

    for (final term in query.asciiTerms) {
      double field = 0.0;
      if (labelTokens.contains(term)) {
        field = 3.0;
      } else if (formulaTokens.contains(term)) {
        field = 2.5;
      } else if (quantityTokens.contains(term)) {
        field = 2.5;
      } else if (resultTokens.contains(term)) {
        field = 2.0;
      } else if (bodyTokens.contains(term)) {
        field = 1.5;
      }
      if (field == 0) {
        continue;
      }
      score += field;
      strong = true; // ASCII 变量/符号命中按 token 边界算强命中。
    }

    for (final letter in query.optionLetters) {
      final lower = letter.toLowerCase();
      final mentioned = _optionMentioned(label, lower) ||
          _optionMentioned(result, lower) ||
          _optionMentioned(body, lower);
      if (!mentioned) {
        continue;
      }
      score += 6.0;
      strong = true;
    }

    if (weakMatches >= 2) {
      strong = true;
    }
    if (query.shortQuery && weakMatches >= 1) {
      strong = true;
    }
    // 问“公式/表达式”时，只要命中公式/计算节点里的字面线索就够：这类问题
    // 往往只说一个概念（“速度表达式是什么”），不要求出现长词。
    if (query.intent == FeedbackIntent.formula &&
        weakMatches >= 1 &&
        (node.kind == 'formula_or_model' || node.kind == 'computation')) {
      strong = true;
    }

    if (query.intent == FeedbackIntent.formula &&
        (node.kind == 'formula_or_model' || node.kind == 'computation')) {
      score += 2.0;
    }
    if (query.intent == FeedbackIntent.mistake && node.kind == 'check') {
      score += 1.0;
    }

    return _NodeScore(score: score, strong: strong);
  }

  // ---------------------------------------------------------------------------
  // 错因
  // ---------------------------------------------------------------------------

  List<FeedbackMistake> _selectMistakes(
      List<String> errorCauses, _Query query) {
    if (errorCauses.isEmpty) {
      return const <FeedbackMistake>[];
    }
    final scored = <_ScoredMistake>[];
    for (var i = 0; i < errorCauses.length; i++) {
      final score = _scoreMistake(errorCauses[i], query);
      if (score > 0) {
        scored.add(_ScoredMistake(index: i, score: score));
      }
    }
    if (scored.isEmpty) {
      if (query.intent != FeedbackIntent.mistake) {
        return const <FeedbackMistake>[];
      }
      // 学生泛问“这题有什么易错点”：给本题记录下来的条目，不补写。
      return <FeedbackMistake>[
        for (var i = 0; i < errorCauses.length && i < maxMistakes; i++)
          _parseMistake(errorCauses[i]),
      ];
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.index.compareTo(b.index);
    });
    final chosen = scored.take(maxMistakes).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return <FeedbackMistake>[
      for (final item in chosen) _parseMistake(errorCauses[item.index]),
    ];
  }

  double _scoreMistake(String cause, _Query query) {
    final text = _normalizeForMatch(cause);
    final tokens = _tokens(text);
    var score = 0.0;
    var strong = false;
    for (final term in query.cjkTerms) {
      if (!text.contains(term)) {
        continue;
      }
      final length = term.runes.length;
      score += length;
      if (length >= 3 || query.shortQuery) {
        strong = true;
      }
    }
    for (final letter in query.optionLetters) {
      if (_optionMentioned(text, letter.toLowerCase())) {
        score += 6.0;
        strong = true;
      }
    }
    for (final term in query.asciiTerms) {
      if (tokens.contains(term)) {
        score += 2.0;
        strong = true;
      }
    }
    return strong ? score : 0.0;
  }

  FeedbackMistake _parseMistake(String raw) {
    final parts = raw
        .split('；')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    var title = parts.isEmpty ? raw.trim() : parts.first;
    var rootCause = '';
    var remedy = '';
    for (final part in parts.skip(1)) {
      if (part.startsWith('根因：')) {
        rootCause = part.substring('根因：'.length).trim();
      } else if (part.startsWith('补救：')) {
        remedy = part.substring('补救：'.length).trim();
      }
    }
    if (title.endsWith('。')) {
      title = title.substring(0, title.length - 1);
    }
    return FeedbackMistake(
      title: _studentSafe(title),
      rootCause: _studentSafe(rootCause),
      remedy: _studentSafe(remedy),
    );
  }

  // ---------------------------------------------------------------------------
  // 文本工具
  // ---------------------------------------------------------------------------

  /// 节点正文节选：超过上限时按句末标点截断，并标 `…`，不静默截半句。
  String _explanation(String body) {
    final text = _studentSafe(body);
    if (text.isEmpty) {
      return '';
    }
    if (text.length <= maxExplanationChars) {
      return text;
    }
    final window = text.substring(0, maxExplanationChars);
    final cut = window.lastIndexOf(RegExp(r'[。；！？]'));
    final base =
        cut >= maxExplanationChars ~/ 2 ? window.substring(0, cut + 1) : window;
    return '$base…';
  }

  String _excerpt(String text, int maxChars) =>
      text.length <= maxChars ? text : text.substring(0, maxChars);

  /// 去掉开发者/证据/信任类 token，防止内容侧漏进学生回答。
  String _studentSafe(String text) {
    var output = text;
    for (final token in _developerTokens) {
      output = output.replaceAll(
        RegExp(RegExp.escape(token), caseSensitive: false),
        '',
      );
    }
    // 长十六进制串基本只可能是 hash/指纹，不属于学生可见内容。
    output = output.replaceAll(RegExp(r'\b[0-9a-f]{6,}\b'), '');
    return output.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  /// 提取问题里提到的选项字母：`A/B/C/D`（含“选c”“选项 D”写法）。
  List<String> _optionLetters(String question) {
    final letters = <String>{};
    for (final match
        in RegExp(r'(?<![A-Za-z])([A-D])(?![A-Za-z])').allMatches(question)) {
      letters.add(match.group(1)!);
    }
    for (final match
        in RegExp(r'(?:选项|选|项)\s*([A-Da-d])').allMatches(question)) {
      letters.add(match.group(1)!.toUpperCase());
    }
    final ordered = letters.toList()..sort();
    return ordered;
  }

  /// 选项字母在字段里作为“判断对象”出现（而不是公式里的变量 a=g）。
  bool _optionMentioned(String text, String letter) {
    final pattern =
        '(?<![a-z0-9])${RegExp.escape(letter)}(?![a-z0-9])(?!\\s*=)';
    return RegExp(pattern).hasMatch(text);
  }

  String _normalizeForMatch(String input) {
    var text = input.toLowerCase();
    text = text.replaceAll('\\', '');
    text = text.replaceAll(RegExp(r'[{}$]'), ' ');
    text = text.replaceAll(
      RegExp(
        '[，。！？、；：\u201c\u201d\u2018\u2019\u0022\u0027（）()\\[\\]'
        '《》【】…—]',
      ),
      ' ',
    );
    text = text.replaceAll(RegExp(r'[_^]'), '');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Set<String> _tokens(String text) => <String>{
        for (final match in RegExp(r'[a-z0-9]+').allMatches(text))
          match.group(0)!,
      };

  List<String> _cjkRuns(String text) => <String>[
        for (final match in RegExp(r'[\u4e00-\u9fff]+').allMatches(text))
          match.group(0)!,
      ];

  bool _containsAny(String text, List<String> keywords) =>
      keywords.any(text.contains);
}

// -----------------------------------------------------------------------------
// 内部数据
// -----------------------------------------------------------------------------

class _Query {
  const _Query({
    required this.cjkTerms,
    required this.asciiTerms,
    required this.optionLetters,
    required this.intent,
    required this.shortQuery,
  });

  final List<String> cjkTerms;
  final List<String> asciiTerms;
  final List<String> optionLetters;
  final FeedbackIntent intent;
  final bool shortQuery;
}

class _NodeScore {
  const _NodeScore({required this.score, required this.strong});

  final double score;
  final bool strong;
}

class _ScoredNode {
  const _ScoredNode({
    required this.index,
    required this.score,
    required this.node,
  });

  final int index;
  final double score;
  final DagNode node;
}

class _ScoredMistake {
  const _ScoredMistake({required this.index, required this.score});

  final int index;
  final double score;
}

// -----------------------------------------------------------------------------
// 词表
// -----------------------------------------------------------------------------

/// 问题里出现时说明是追问上一轮回答（短问题本身也会被当作追问）。
const List<String> _followUpMarkers = <String>[
  '再',
  '还',
  '继续',
  '详细',
  '多讲',
  '然后',
  '所以',
  '那',
  '它',
  '呢',
];

/// 高频功能词/泛问短语：出现在几乎所有回答里，不构成“这题讲了这一点”的证据。
const Set<String> _genericTerms = <String>{
  '什么',
  '为什',
  '怎么',
  '如何',
  '怎样',
  '怎么样',
  '哪些',
  '哪个',
  '哪里',
  '多少',
  '这道',
  '道题',
  '题考',
  '考什',
  '这个',
  '那个',
  '一下',
  '可以',
  '请问',
  '告诉',
  '解释',
  '意思',
  '是一',
  '是不',
  '不是',
  '还是',
  '的是',
  '需要',
  '应该',
  '能不',
  '不能',
  '有没',
  '没有',
  '一个',
  '这些',
  '那些',
  '这道题',
  '道题考',
  '考什么',
  '啥意思',
  '怎么回',
  '为什么',
  '什么意',
  '么意思',
  '有什',
  '有什么',
  '什么区',
  '区别是',
};

/// 问题里出现时按“问公式”处理。
const List<String> _formulaHints = <String>[
  '公式',
  '表达式',
  '怎么算',
  '怎么求',
  '怎么推',
  '方程',
  '代入',
  '求值',
  '式子',
  '列出',
  '写出来',
];

/// 问题里出现时按“问易错点”处理。
const List<String> _mistakeHints = <String>[
  '易错',
  '陷阱',
  '坑',
  '错因',
  '错在哪',
  '错在',
  '错选',
  '选错',
  '做错',
  '为什么错',
  '注意什么',
  '容易混',
  '混淆',
];

/// 问题里出现时按“问步骤/思路”处理。
const List<String> _stepsHints = <String>[
  '步骤',
  '思路',
  '从哪开始',
  '怎么开始',
  '怎么做',
  '下一步',
  '接下来',
  '先做',
  '先算',
  '第一步',
];

/// 问题里出现时按“直接问答案”处理。
const List<String> _answerHints = <String>[
  '答案',
  '选什么',
  '选哪',
  '是几',
  '正确选项',
  '哪个选项',
];

/// 问题里出现时按“问概念/原因”处理。
const List<String> _conceptHints = <String>[
  '为什么',
  '原因',
  '什么意思',
  '区别',
  '关系',
  '原理',
  '怎么理解',
  '含义',
  '对吗',
  '正确吗',
  '成立',
  '这样理解',
];

const Set<String> _asciiStopWords = <String>{
  'the',
  'a',
  'an',
  'is',
  'are',
  'was',
  'were',
  'be',
  'to',
  'of',
  'in',
  'on',
  'at',
  'and',
  'or',
  'not',
  'it',
  'this',
  'that',
  'why',
  'how',
  'what',
  'which',
  'do',
  'does',
  'did',
  'can',
  'could',
  'should',
  'would',
  'please',
  'explain',
  'ok',
  'yes',
  'no',
};

/// 单字母数学符号：只有这些才把单个 ASCII 字母当作有效线索。
const Set<String> _mathSymbols = <String>{
  'g',
  'v',
  'm',
  'p',
  't',
  'a',
  'e',
  'x',
  'y',
  'n',
  'k',
  's',
  'w',
  'f',
  'h',
};

/// 内容侧不允许出现在学生回答里的开发者/证据/信任 token。
const List<String> _developerTokens = <String>[
  'trust',
  'hash',
  'sha256',
  'evidence',
  'source',
  'expert_authored',
  'success_path',
  'official_trust',
  'independently_verified',
  'private_study_only',
  'provenance',
  'oracle',
  'blind',
  '盲解',
  '内容包',
  '未独立审核',
  '未经独立审核',
  '无语义校验',
  '没有语义校验',
  '报告腔',
];
