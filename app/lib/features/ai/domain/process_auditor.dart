/// ProcessAuditor：读 solver 的 reasoning 原文，判断**过程**有没有打转。
///
/// 这是《STUDENT-MODE-AND-AGENT-LOOP-DESIGN-2026-11-14》§7.4 的第二个角色：
///
///  * `ContentVerifier`（`verifier.dart`）看题目 + 答案卡 + claim 摘要，**不读**
///    原始 CoT，判内容对不对；
///  * `ProcessAuditor`（本文件）**必须读** CoT，查循环、重复怀疑、无进展，产出
///    [ProcessReport]；它**不判答案对错**。
///
/// 为什么必须拆开：内容验证不看 CoT 是为了不被 solver 的错误推理带偏；但「反复
/// 怀疑」「在已 settled 的分支上重开」只能从过程里看出来。把两件事塞进一个
/// verdict，要么让验证器被 CoT 污染，要么让循环永远看不见。
///
/// 本文件只做**确定性文本启发式**：无 embedding、无网络、无模型调用，所以同一段
/// reasoning 永远得到同一份报告，测试可以逐条断言。启发式的边界写在
/// [ProcessAuditorConfig] 的注释里——它给的是「值得停下来看看」的信号，不是
/// 「这段推理错了」的判决。
library;

// `Claim` / `ClaimSummary` 是 claim 模块的共享词表（`claim.dart` 的文件头写明
// 它的三个消费者就是 ProcessAuditor / ClaimLedger / Verifier）。过程审计只负责
// **抽取** claim，不重复定义一套 claim 类型：同一份摘要交给 verifier 时，
// 两边看到的是同一个对象，不用再做一次转换。
import 'claim.dart';

/// ProcessAuditor 的阈值。默认值是「学生一题 20k reasoning」量级下调出来的，
/// 不是普适定律；调用方可以按 preset 覆盖。
class ProcessAuditorConfig {
  const ProcessAuditorConfig({
    this.repeatedSentenceLimit = 3,
    this.maxSentenceCyclePeriod = 4,
    this.maxActionCyclePeriod = 4,
    this.selfDoubtLimit = 3,
    this.selfDoubtPer1000Chars = 1.5,
    this.minCharsForDensityCheck = 600,
    this.restartLimit = 3,
    this.minSentencesForStagnation = 8,
    this.minUniqueSentenceRatio = 0.55,
    this.minCharsForTailCheck = 800,
    this.maxClaims = 12,
  })  : assert(repeatedSentenceLimit >= 2),
        assert(maxSentenceCyclePeriod >= 2),
        assert(maxActionCyclePeriod >= 2),
        assert(selfDoubtLimit >= 1),
        assert(minSentencesForStagnation >= 2),
        assert(minUniqueSentenceRatio > 0 && minUniqueSentenceRatio <= 1),
        assert(maxClaims >= 1);

  /// 同一句（规范化后）出现多少次算循环。
  final int repeatedSentenceLimit;

  /// 句子级周期检测的最大周期（ABAB 的 2、ABCABC 的 3）。
  final int maxSentenceCyclePeriod;

  /// 动作序列周期检测的最大周期。
  final int maxActionCyclePeriod;

  /// 自我怀疑短语出现多少次直接记 `self_doubt` 标记。
  final int selfDoubtLimit;

  /// 每 1000 字符的自我怀疑密度阈值（长文本用密度判，避免长文里 2-3 次正常
  /// 措辞就报警）。
  final double selfDoubtPer1000Chars;

  /// 密度检查的最小文本长度。
  final int minCharsForDensityCheck;

  /// 「重开分支」短语出现多少次算在已 settled 的分支上重开。
  final int restartLimit;

  /// 判断「整段没推进」需要的最少句数。
  final int minSentencesForStagnation;

  /// 唯一句占比低于此值 + 句数够多 -> 停滞。
  final double minUniqueSentenceRatio;

  /// 尾部新增内容检查的最小文本长度。
  final int minCharsForTailCheck;

  /// 一次审计最多抽多少条 claim（报告要小，只放摘要）。
  final int maxClaims;
}

/// 一次过程审计的报告（设计文档 §7.4 的 `ProcessReport`）。
///
/// 报告进入 StepGuard（决定 forceAnswer/repair/stop）、ClaimLedger（登记
/// claim）、ContextAssembler（只给下一轮摘要）与 `agent_verifications`
/// （`kind = process` 那条记录）。
class ProcessReport {
  const ProcessReport({
    required this.loopDetected,
    required this.stagnation,
    required this.repeatedClaimCount,
    required this.selfDoubtCount,
    required this.flags,
    required this.extractedClaims,
    this.reasoningChars = 0,
    this.sentenceCount = 0,
    this.uniqueSentenceCount = 0,
  });

  /// 没有问题的空报告。
  static const ProcessReport clean = ProcessReport(
    loopDetected: false,
    stagnation: false,
    repeatedClaimCount: 0,
    selfDoubtCount: 0,
    flags: [],
    extractedClaims: [],
  );

  final bool loopDetected;
  final bool stagnation;
  final int repeatedClaimCount;
  final int selfDoubtCount;

  /// 人可读的标记列表：`repeated_sentence` / `sentence_cycle` /
  /// `action_cycle` / `self_doubt` / `restart_detected` /
  /// `repetitive_reasoning` / `no_new_content_in_tail` / `state_unchanged` /
  /// `no_progress_vs_previous`。
  final List<String> flags;

  /// 过程审计抽出的 claim（claim 模块的 [Claim] 类型）。
  final List<Claim> extractedClaims;

  final int reasoningChars;
  final int sentenceCount;
  final int uniqueSentenceCount;

  /// 过程层面是否有问题（循环 / 停滞 / 任何标记）。
  bool get hasProblems => loopDetected || stagnation || flags.isNotEmpty;

  /// 是否建议走一次 repair（有循环或停滞，或出现了「重开分支」）。
  bool get suggestsRepair =>
      loopDetected || stagnation || flags.contains('branch_reopened');

  /// 交给 ContentVerifier 的结构化摘要（不含 raw CoT）。
  ///
  /// 用 claim 模块的 [ClaimSummary.of] 排序/截断，所以 verifier 拿到的就是
  /// ClaimLedger 同一套摘要形状：`verified/given` 在前，`refuted/open` 在后。
  ClaimSummary get claimSummary => ClaimSummary.of(extractedClaims);

  Map<String, Object?> toJson() => {
        'loop_detected': loopDetected,
        'stagnation': stagnation,
        'repeated_claim_count': repeatedClaimCount,
        'self_doubt_count': selfDoubtCount,
        'flags': flags,
        'claims': [for (final claim in extractedClaims) claim.toJson()],
        'reasoning_chars': reasoningChars,
        'sentence_count': sentenceCount,
        'unique_sentence_count': uniqueSentenceCount,
      };

  /// 宽松解析：坏 JSON/缺字段都退化成空报告，绝不因为一条过程记录解析失败
  /// 而挡住主流程（与 `capability_action_overlay` 的宽容解析同一个契约）。
  factory ProcessReport.fromJson(Object? json) {
    if (json is! Map) {
      return ProcessReport.clean;
    }
    final claims = <Claim>[];
    final rawClaims = json['claims'];
    if (rawClaims is List) {
      for (final item in rawClaims) {
        final claim = Claim.fromJson(item);
        if (claim != null) {
          claims.add(claim);
        }
      }
    }
    return ProcessReport(
      loopDetected: json['loop_detected'] == true,
      stagnation: json['stagnation'] == true,
      repeatedClaimCount:
          json['repeated_claim_count'] is int ? json['repeated_claim_count'] as int : 0,
      selfDoubtCount:
          json['self_doubt_count'] is int ? json['self_doubt_count'] as int : 0,
      flags: [
        if (json['flags'] is List)
          for (final flag in json['flags'] as List)
            if (flag is String) flag,
      ],
      extractedClaims: claims,
      reasoningChars:
          json['reasoning_chars'] is int ? json['reasoning_chars'] as int : 0,
      sentenceCount:
          json['sentence_count'] is int ? json['sentence_count'] as int : 0,
      uniqueSentenceCount: json['unique_sentence_count'] is int
          ? json['unique_sentence_count'] as int
          : 0,
    );
  }

  @override
  String toString() => 'ProcessReport(loop: $loopDetected, '
      'stagnation: $stagnation, repeatedClaims: $repeatedClaimCount, '
      'selfDoubt: $selfDoubtCount, flags: $flags)';
}

/// 读 reasoning 原文、产出 [ProcessReport] 的确定性审计器。
class ProcessAuditor {
  ProcessAuditor({this.config = const ProcessAuditorConfig()});

  final ProcessAuditorConfig config;

  /// 「自我怀疑」短语。只收**多字且明确**的措辞：数学文本里「可能」本身是
  /// 正常用词，收进来会天天误报；这些短语出现在学生推理里才真说明在反复怀疑。
  static const List<String> selfDoubtPhrases = [
    '我可能错了',
    '可能错了',
    '我错了',
    '也许',
    '或许',
    '再检查一遍',
    '重新检查',
    '另一种理解',
    '另一种可能',
    '另一种解法',
    '换个思路',
    '重新考虑',
    '不太确定',
    '我怀疑',
    '重新算',
    '再算一遍',
    '回头检查',
    '似乎不对',
    '可能不对',
    '让我再想想',
    '再确认一下',
  ];

  /// 「在已 settled 的分支上重开」的措辞。
  static const List<String> restartPhrases = [
    '重新来',
    '从头开始',
    '从头再',
    '回到题目',
    '回到最初',
    '回到前面',
    '重新设',
    '重新列式',
    '换一种方法',
    '换个方法',
    '重做一遍',
  ];

  /// 一句话像不像 claim。
  static const List<String> _claimMarkers = [
    '所以',
    '因此',
    '于是',
    '由此',
    '可知',
    '即可',
    '结论',
    '答案',
    '等于',
    '大于',
    '小于',
    '为零',
    '解得',
    '代入',
    '化简',
    '取',
    '设',
    '得',
  ];

  /// 规范化时要从 claim 开头剥掉的引导词（让「所以 t=2」与「t=2」合并）。
  static const List<String> _claimLeadIns = [
    '所以',
    '因此',
    '于是',
    '由此',
    '即可知',
    '可知',
    '即可得',
    '可得',
    '解得',
    '得到',
    '则',
    '即',
    '故',
    '得',
  ];

  /// 审计一段 reasoning。
  ///
  /// [previousReasoning] 是上一次/上一阶段的 reasoning，用来判断「这一段有没有
  /// 带来新内容」；[actionSequence] 是调用方已经算好的动作键序列（工具 + 参数
  /// 或 step 种类），用于动作级周期检测；[stateFingerprint] 与
  /// [previousStateFingerprint] 相等时记 `state_unchanged`。
  ProcessReport audit({
    required String reasoning,
    String? previousReasoning,
    List<String> actionSequence = const [],
    String? stateFingerprint,
    String? previousStateFingerprint,
  }) {
    final text = reasoning.trim();
    final flags = <String>[];
    var loopDetected = false;
    var stagnation = false;

    final sentences = _splitSentences(text);
    final normalized = [
      for (final sentence in sentences)
        if (_normalizeForCompare(sentence).isNotEmpty)
          _normalizeForCompare(sentence),
    ];
    final uniqueSentences = normalized.toSet();

    // --- 1. 循环：同一句重复 ------------------------------------------------
    final sentenceCounts = <String, int>{};
    for (final sentence in normalized) {
      sentenceCounts.update(sentence, (count) => count + 1, ifAbsent: () => 1);
    }
    final maxSentenceRepeat = sentenceCounts.values.fold<int>(
      0,
      (max, count) => count > max ? count : max,
    );
    if (maxSentenceRepeat >= config.repeatedSentenceLimit) {
      loopDetected = true;
      flags.add('repeated_sentence');
    }

    // --- 2. 循环：句子 n-gram 周期（ABAB / ABCABC）--------------------------
    if (_hasConsecutiveCycle(normalized, config.maxSentenceCyclePeriod)) {
      loopDetected = true;
      flags.add('sentence_cycle');
    }

    // --- 3. 循环：动作序列周期 ---------------------------------------------
    if (actionSequence.length >= 4 &&
        _hasConsecutiveCycle(actionSequence, config.maxActionCyclePeriod)) {
      loopDetected = true;
      flags.add('action_cycle');
    }

    // --- 4. 反复自我怀疑 ----------------------------------------------------
    final selfDoubtCount = _countPhrases(text, selfDoubtPhrases);
    final density = text.isEmpty
        ? 0.0
        : selfDoubtCount / (text.length / 1000.0);
    final selfDoubtByCount = selfDoubtCount >= config.selfDoubtLimit;
    final selfDoubtByDensity = text.length >= config.minCharsForDensityCheck &&
        density >= config.selfDoubtPer1000Chars;
    if (selfDoubtByCount || selfDoubtByDensity) {
      flags.add('self_doubt');
    }

    // --- 5. 在已 settled 的分支上重开 --------------------------------------
    final restartCount = _countPhrases(text, restartPhrases);
    if (restartCount >= config.restartLimit) {
      flags.add('branch_reopened');
    }

    // --- 6. 无进展：整段重复 ----------------------------------------------
    if (normalized.length >= config.minSentencesForStagnation) {
      final ratio = uniqueSentences.length / normalized.length;
      if (ratio < config.minUniqueSentenceRatio) {
        stagnation = true;
        flags.add('repetitive_reasoning');
      }
    }

    // --- 7. 无进展：尾部没有新内容 ----------------------------------------
    if (text.length >= config.minCharsForTailCheck &&
        _tailAddsNothing(sentences, text)) {
      stagnation = true;
      flags.add('no_new_content_in_tail');
    }

    // --- 8. 无进展：与上一段相比没有新句子 ---------------------------------
    if (previousReasoning != null && previousReasoning.trim().isNotEmpty) {
      final previousSentences = {
        for (final sentence in _splitSentences(previousReasoning))
          _normalizeForCompare(sentence),
      }..removeWhere((sentence) => sentence.isEmpty);
      final newSentences =
          uniqueSentences.difference(previousSentences);
      if (previousSentences.isNotEmpty && newSentences.isEmpty) {
        stagnation = true;
        flags.add('no_progress_vs_previous');
      }
    }

    // --- 9. 状态指纹没变 ----------------------------------------------------
    if (stateFingerprint != null &&
        previousStateFingerprint != null &&
        stateFingerprint == previousStateFingerprint) {
      stagnation = true;
      flags.add('state_unchanged');
    }

    // --- 10. 抽取 claim 摘要 ----------------------------------------------
    final extraction = _extractClaims(sentences);
    final claims = extraction.claims;
    final repeatedClaimCount = extraction.repeatedCount;
    if (repeatedClaimCount > 0) {
      flags.add('repeated_claim');
    }

    return ProcessReport(
      loopDetected: loopDetected,
      stagnation: stagnation,
      repeatedClaimCount: repeatedClaimCount,
      selfDoubtCount: selfDoubtCount,
      flags: flags,
      extractedClaims: claims,
      reasoningChars: text.length,
      sentenceCount: normalized.length,
      uniqueSentenceCount: uniqueSentences.length,
    );
  }

  /// 把 reasoning 切成句子（按换行与中英文句末标点）。
  List<String> _splitSentences(String text) {
    final unified = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final parts = unified.split(RegExp(r'[\n。！？!?；;]+'));
    return [
      for (final part in parts)
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  /// 比较用的规范化：去空白/标点、统一全角半角、ASCII 转小写。
  ///
  /// 保留数字与运算符：`t=2` 和 `t=3` 是两条 claim，不能归一成同一条。
  String _normalizeForCompare(String text) {
    var value = text.toLowerCase();
    value = value.replaceAll(RegExp(r'\s+'), '');
    value = value.replaceAll(
      RegExp(r'''[，。！？、：；“”‘’（）()\[\]【】{}<>《》,.!?:;"`~]'''),
      '',
    );
    const replacements = <String, String>{
      '＝': '=',
      '≈': '=',
      '≤': '<=',
      '≥': '>=',
      '＋': '+',
      '－': '-',
      '×': '*',
      '÷': '/',
      '％': '%',
    };
    replacements.forEach((from, to) {
      value = value.replaceAll(from, to);
    });
    const fullWidthDigits = '０１２３４５６７８９';
    for (var digit = 0; digit < 10; digit++) {
      value = value.replaceAll(fullWidthDigits[digit], '$digit');
    }
    return value;
  }

  /// claim 的 canonical：比较用的规范化 + 剥掉句首引导词。
  String _canonicalClaim(String sentence) {
    var value = _normalizeForCompare(sentence);
    for (final leadIn in _claimLeadIns) {
      if (value.startsWith(leadIn) && value.length > leadIn.length + 2) {
        value = value.substring(leadIn.length);
        break;
      }
    }
    return value;
  }

  /// 这句话像不像一条 claim（等式/不等式/数学关系/结论句）。
  bool _looksLikeClaim(String sentence) {
    if (sentence.length < 4) {
      return false;
    }
    if (RegExp(r'[=＝≈≤≥<>]').hasMatch(sentence)) {
      return true;
    }
    if (RegExp(r'[-+*/×÷]\s*-?\d').hasMatch(sentence)) {
      return true;
    }
    for (final marker in _claimMarkers) {
      if (sentence.contains(marker)) {
        return true;
      }
    }
    return false;
  }

  /// 抽 claim：按 canonical 去重、记出现次数（放 evidence），最多
  /// [ProcessAuditorConfig.maxClaims] 条。
  ///
  /// id 用 `claim-<canonicalHash>`（claim 模块的稳定 hash），所以同一段 reasoning
  /// 抽出的 claim 在两次审计里 id 相同——重复检测与缓存都能对上。
  ///
  /// 返回值带 [repeatedCount]（`sum(occurrences - 1)`）：`Claim` 本身不带出现
  /// 次数，报告里的 `repeatedClaimCount` 只能在这一趟算出来。
  ({List<Claim> claims, int repeatedCount}) _extractClaims(
    List<String> sentences,
  ) {
    final occurrences = <String, int>{};
    final statements = <String, String>{};
    final order = <String>[];
    for (final sentence in sentences) {
      if (!_looksLikeClaim(sentence)) {
        continue;
      }
      final canonical = _canonicalClaim(sentence);
      if (canonical.isEmpty) {
        continue;
      }
      if (!occurrences.containsKey(canonical)) {
        order.add(canonical);
        statements[canonical] =
            sentence.length > 240 ? sentence.substring(0, 240) : sentence;
        occurrences[canonical] = 1;
      } else {
        occurrences[canonical] = occurrences[canonical]! + 1;
      }
    }
    var repeatedCount = 0;
    for (final count in occurrences.values) {
      if (count > 1) {
        repeatedCount += count - 1;
      }
    }
    final claims = <Claim>[
      for (final canonical in order.take(config.maxClaims))
        Claim(
          id: 'claim-${stableClaimHash(canonical)}',
          kind: _claimKindOf(canonical, statements[canonical]!),
          canonical: canonical,
          statement: statements[canonical]!,
          status: ClaimStatus.proposed,
          evidence: occurrences[canonical]! > 1
              ? '在 reasoning 里出现 ${occurrences[canonical]} 次'
              : null,
          createdAtMs: 0,
        ),
    ];
    return (claims: claims, repeatedCount: repeatedCount);
  }

  /// 粗分类：等式 -> equation，结论句 -> decision，其余 -> assumption。
  ///
  /// 过程审计不假装能细分 claim 种类；`given`（题目条件）与依赖 DAG 是
  /// ClaimLedger 的职责，这里不抢。
  ClaimKind _claimKindOf(String canonical, String statement) {
    if (canonical.contains('=')) {
      return ClaimKind.equation;
    }
    if (statement.contains('结论') ||
        statement.contains('答案') ||
        statement.contains('所以') ||
        statement.contains('因此')) {
      return ClaimKind.decision;
    }
    return ClaimKind.assumption;
  }

  /// 最近 2*period 步里是否出现两段连续的相同序列。
  bool _hasConsecutiveCycle(List<String> sequence, int maxPeriod) {
    final length = sequence.length;
    final max = length ~/ 2 < maxPeriod ? length ~/ 2 : maxPeriod;
    for (var period = 2; period <= max; period++) {
      final start = length - 2 * period;
      var equal = true;
      for (var index = 0; index < period; index++) {
        if (sequence[start + index] != sequence[start + period + index]) {
          equal = false;
          break;
        }
      }
      if (equal) {
        return true;
      }
    }
    return false;
  }

  /// 统计 [phrases] 在 [text] 里出现的总次数（允许重叠位置各自计数）。
  int _countPhrases(String text, List<String> phrases) {
    var count = 0;
    for (final phrase in phrases) {
      var index = text.indexOf(phrase);
      while (index >= 0) {
        count += 1;
        index = text.indexOf(phrase, index + phrase.length);
      }
    }
    return count;
  }

  /// 文本后半段有没有带来新的「数字 / 等式结论」。
  ///
  /// 学生推理的常见失败不是逐字重复，而是「一直在算同一批数」；如果后半段既没有
  /// 新数字、也没有新 claim，就算内容不重复也该算无进展。文本太短时不做这个判断
  /// （[ProcessAuditorConfig.minCharsForTailCheck]）。
  bool _tailAddsNothing(List<String> sentences, String text) {
    final prefixLength = (text.length * 0.6).floor();
    final prefix = text.substring(0, prefixLength);
    final suffix = text.substring(prefixLength);
    final prefixNumbers = _numbersIn(prefix);
    final suffixNumbers = _numbersIn(suffix);
    if (suffixNumbers.difference(prefixNumbers).isNotEmpty) {
      return false;
    }
    final prefixClaims = {
      for (final claim in _extractClaims(_splitSentences(prefix)).claims)
        claim.canonical,
    };
    final suffixClaims = {
      for (final claim in _extractClaims(_splitSentences(suffix)).claims)
        claim.canonical,
    };
    if (suffixClaims.difference(prefixClaims).isNotEmpty) {
      return false;
    }
    // 后半段完全没有数字/claim 时，也不该被当成"有推进"——但太短的尾句可能只是
    // 一句结论，所以要求尾段本身有实质长度。
    return suffix.trim().length >= 20;
  }

  Set<String> _numbersIn(String text) {
    return {
      for (final match in RegExp(r'\d+(?:\.\d+)?').allMatches(text))
        match.group(0)!,
    };
  }
}
