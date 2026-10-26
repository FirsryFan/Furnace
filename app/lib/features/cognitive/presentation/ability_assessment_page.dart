/// 能力测评页：四项本地小测（反应速度 / 工作记忆 / 模式识别 / 注意稳定性）。
///
/// 设计来源：`docs/REVIEW_FEEDBACK.md` §8（能力测评）。页面只负责「呈现小测、
/// 计时、把读数交给领域层换算」：分数换算全部走
/// `domain/services/cognitive/ability_assessment.dart` 的纯函数，页面不自己
/// 重算一个分；保存走 `AbilityScoreRepository.record`（schema v38，四项各写
/// 一行，只追加）。
///
/// 流程：介绍 → 逐项（说明 → 小测 → 单项得分，可重测）→ 汇总 → 完成并保存。
/// 返回箭头 = 放弃本次测评：不写库、不弹确认；所有计时器随 `dispose` 取消，
/// 免得测试挂起、也免得用户在等待中途离页后还有回调改状态。
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/cognitive/ability_assessment.dart';
import '../../../l10n/app_localizations.dart';

/// 测评流程按钮与关键控件的稳定 key：页面与测试共用同一套定位点。
const Key abilityStartKey = Key('ability-start');
const Key abilityStartItemKey = Key('ability-start-item');
const Key abilityNextKey = Key('ability-next');
const Key abilityRetryKey = Key('ability-retry');
const Key abilityFinishKey = Key('ability-finish');
const Key abilityReactionTargetKey = Key('ability-reaction-target');
const Key abilityReactionWaitKey = Key('ability-reaction-wait');
const Key abilityMemoryDigitsKey = Key('ability-memory-digits');
const Key abilityMemoryInputKey = Key('ability-memory-input');
const Key abilityMemorySubmitKey = Key('ability-memory-submit');
const Key abilityPatternAKey = Key('ability-pattern-a');
const Key abilityPatternBKey = Key('ability-pattern-b');
const Key abilityPatternSameKey = Key('ability-pattern-same');
const Key abilityPatternDifferentKey = Key('ability-pattern-different');
const Key abilityAttentionStimulusKey = Key('ability-attention-stimulus');
const Key abilityAttentionYesKey = Key('ability-attention-yes');
const Key abilityAttentionNoKey = Key('ability-attention-no');

/// 单项得分页上「这一项得了多少分」的定位点。
Key abilityItemScoreKey(AbilityKey key) =>
    ValueKey<String>('ability-item-score-${key.code}');

/// 汇总页上某一项的定位点。
Key abilitySummaryRowKey(AbilityKey key) =>
    ValueKey<String>('ability-summary-${key.code}');

/// 反应速度小测的试次与等待区间（ms）。
const int _reactionTrialCount = 5;
const int _reactionWaitMinMillis = 800;
const int _reactionWaitMaxMillis = 2000;

/// 工作记忆小测的跨度序列与数字展示时长（ms）。
const List<int> _memorySpanSequence = <int>[4, 5, 6, 7, 8];
const int _memoryShowMillis = 1200;

/// 模式识别小测的试次数、A 的展示时长（ms）与符号表。
const int _patternTrialCount = 10;
const int _patternShowMillis = 900;
const List<String> _patternSymbols = <String>['●', '■', '▲', '◆'];

/// 注意稳定性小测：目标 / 非目标数量与每试次窗口（ms）。
const int _attentionTargetTotal = 20;
const int _attentionNonTargetTotal = 10;
const int _attentionWindowMillis = 800;
const String _attentionLetters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

/// 一页内的流程阶段。
enum _Phase { intro, itemIntro, running, itemDone, summary }

/// 注意稳定性的一试次：该显示什么、算不算目标。
class _AttentionStimulus {
  const _AttentionStimulus(this.text, {required this.isTarget});

  final String text;
  final bool isTarget;
}

/// 四项本地能力小测页面。
///
/// [random] 只用于「等待多久、出什么数字、A/B 是否相同、30 个刺激怎么排」，
/// 测试传种子让它确定；分数换算不看随机源。
class AbilityAssessmentPage extends ConsumerStatefulWidget {
  const AbilityAssessmentPage({super.key, this.random});

  final Random? random;

  @override
  ConsumerState<AbilityAssessmentPage> createState() =>
      _AbilityAssessmentPageState();
}

class _AbilityAssessmentPageState extends ConsumerState<AbilityAssessmentPage> {
  late final Random _random;
  _Phase _phase = _Phase.intro;
  int _itemIndex = 0;
  final Map<AbilityKey, AbilityScore> _scores = <AbilityKey, AbilityScore>{};
  bool _saving = false;

  /// 反应速度：等待中的计时器、目标出现后的计时秒表、本轮样本。
  Timer? _reactionTimer;
  final Stopwatch _reactionWatch = Stopwatch();
  bool _reactionReady = false;
  final List<int> _reactionSamples = <int>[];

  /// 工作记忆：数字展示计时器、输入框控制器、当前试次与读数。
  Timer? _memoryTimer;
  final TextEditingController _memoryController = TextEditingController();
  int _memoryTrial = 0;
  String _memoryDigits = '';
  bool _memoryShowDigits = false;
  final List<int> _memoryCorrectLengths = <int>[];

  /// 模式识别：A 展示计时器、B 出现后的秒表、当前试次与读数。
  Timer? _patternTimer;
  final Stopwatch _patternWatch = Stopwatch();
  int _patternTrial = 0;
  List<String> _patternA = const <String>[];
  List<String> _patternB = const <String>[];
  bool _patternShowB = false;
  bool _patternSame = false;
  int _patternCorrect = 0;
  final List<int> _patternTimes = <int>[];

  /// 注意稳定性：每试次窗口计时器、排好的 30 试次与计数。
  Timer? _attentionTimer;
  List<_AttentionStimulus> _attentionSchedule = const <_AttentionStimulus>[];
  int _attentionTrial = 0;
  _AttentionStimulus? _attentionStimulus;
  int _attentionHits = 0;
  int _attentionMisses = 0;
  int _attentionFalseAlarms = 0;

  AbilityKey get _currentKey => AbilityKey.values[_itemIndex];

  @override
  void initState() {
    super.initState();
    _random = widget.random ?? Random();
  }

  @override
  void dispose() {
    _cancelTimers();
    _memoryController.dispose();
    super.dispose();
  }

  void _cancelTimers() {
    _reactionTimer?.cancel();
    _reactionTimer = null;
    _memoryTimer?.cancel();
    _memoryTimer = null;
    _patternTimer?.cancel();
    _patternTimer = null;
    _attentionTimer?.cancel();
    _attentionTimer = null;
    _reactionWatch.stop();
    _patternWatch.stop();
  }

  // ---------------------------------------------------------------------------
  // 流程控制
  // ---------------------------------------------------------------------------

  void _startAssessment() {
    setState(() {
      _itemIndex = 0;
      _scores.clear();
      _phase = _Phase.itemIntro;
    });
  }

  /// 开始当前项：重置该项读数、启动第一试次（或首个等待）。
  void _startItem() {
    _cancelTimers();
    switch (_currentKey) {
      case AbilityKey.reactionSpeed:
        _reactionSamples.clear();
        _reactionReady = false;
        _startReactionTrial();
      case AbilityKey.workingMemory:
        _memoryTrial = 0;
        _memoryCorrectLengths.clear();
        _startMemoryTrial();
      case AbilityKey.patternRecognition:
        _patternTrial = 0;
        _patternCorrect = 0;
        _patternTimes.clear();
        _patternShowB = false;
        _startPatternTrial();
      case AbilityKey.attentionStability:
        _attentionTrial = 0;
        _attentionHits = 0;
        _attentionMisses = 0;
        _attentionFalseAlarms = 0;
        _attentionSchedule = _buildAttentionSchedule();
        _startAttentionTrial();
    }
    setState(() => _phase = _Phase.running);
  }

  /// 重测当前项：丢掉这一项的旧分，直接再跑一遍。
  void _retryItem() {
    _scores.remove(_currentKey);
    _startItem();
  }

  /// 进入下一项；四项都完成后进汇总。
  void _nextItem() {
    if (_itemIndex >= AbilityKey.values.length - 1) {
      setState(() => _phase = _Phase.summary);
      return;
    }
    setState(() {
      _itemIndex += 1;
      _phase = _Phase.itemIntro;
    });
  }

  /// 记下单项分数并切到「单项得分」页。
  void _finishItem(AbilityScore score) {
    _cancelTimers();
    setState(() {
      _scores[score.key] = score;
      _phase = _Phase.itemDone;
    });
  }

  // ---------------------------------------------------------------------------
  // 小测一：反应速度
  // ---------------------------------------------------------------------------

  void _startReactionTrial() {
    _reactionTimer?.cancel();
    _reactionReady = false;
    final waitMillis = _reactionWaitMinMillis +
        _random.nextInt(_reactionWaitMaxMillis - _reactionWaitMinMillis + 1);
    _reactionTimer = Timer(Duration(milliseconds: waitMillis), _onReactionGo);
  }

  void _onReactionGo() {
    if (!mounted) return;
    _reactionWatch
      ..reset()
      ..start();
    setState(() => _reactionReady = true);
  }

  void _tapReactionTarget() {
    if (!_reactionReady) return;
    _reactionWatch.stop();
    _reactionSamples.add(_reactionWatch.elapsedMilliseconds);
    if (_reactionSamples.length >= _reactionTrialCount) {
      final samples = List<int>.unmodifiable(_reactionSamples);
      _finishItem(
        AbilityScore(
          key: AbilityKey.reactionSpeed,
          score: scoreReactionSpeed(samples),
          metrics: <String, Object?>{
            'samples_ms': samples,
            'median_ms': medianReactionMillis(samples),
          },
        ),
      );
      return;
    }
    setState(() => _reactionReady = false);
    _startReactionTrial();
  }

  // ---------------------------------------------------------------------------
  // 小测二：工作记忆
  // ---------------------------------------------------------------------------

  void _startMemoryTrial() {
    _memoryTimer?.cancel();
    final length = _memorySpanSequence[_memoryTrial];
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(_random.nextInt(10));
    }
    _memoryDigits = buffer.toString();
    _memoryController.clear();
    _memoryShowDigits = true;
    _memoryTimer = Timer(
      const Duration(milliseconds: _memoryShowMillis),
      () {
        if (!mounted) return;
        setState(() => _memoryShowDigits = false);
      },
    );
  }

  void _submitMemory() {
    final input = _memoryController.text.trim();
    if (input == _memoryDigits) {
      _memoryCorrectLengths.add(_memorySpanSequence[_memoryTrial]);
    }
    _memoryTrial += 1;
    if (_memoryTrial >= _memorySpanSequence.length) {
      final longest =
          _memoryCorrectLengths.isEmpty ? 0 : _memoryCorrectLengths.reduce(max);
      _finishItem(
        AbilityScore(
          key: AbilityKey.workingMemory,
          score: scoreWorkingMemory(longest),
          metrics: <String, Object?>{'longest_span': longest},
        ),
      );
      return;
    }
    setState(_startMemoryTrial);
  }

  // ---------------------------------------------------------------------------
  // 小测三：模式识别
  // ---------------------------------------------------------------------------

  void _startPatternTrial() {
    _patternTimer?.cancel();
    _patternShowB = false;
    final a = <String>[
      for (var i = 0; i < 4; i++)
        _patternSymbols[_random.nextInt(_patternSymbols.length)],
    ];
    final same = _random.nextBool();
    final b = List<String>.of(a);
    if (!same) {
      final position = _random.nextInt(b.length);
      final alternatives = <String>[
        for (final symbol in _patternSymbols)
          if (symbol != b[position]) symbol,
      ];
      b[position] = alternatives[_random.nextInt(alternatives.length)];
    }
    _patternA = List<String>.unmodifiable(a);
    _patternB = List<String>.unmodifiable(b);
    _patternSame = same;
    _patternTimer = Timer(
      const Duration(milliseconds: _patternShowMillis),
      () {
        if (!mounted) return;
        _patternWatch
          ..reset()
          ..start();
        setState(() => _patternShowB = true);
      },
    );
  }

  void _answerPattern({required bool samePressed}) {
    if (!_patternShowB) return;
    _patternTimer?.cancel();
    _patternWatch.stop();
    _patternTimes.add(_patternWatch.elapsedMilliseconds);
    if (samePressed == _patternSame) {
      _patternCorrect += 1;
    }
    _patternTrial += 1;
    if (_patternTrial >= _patternTrialCount) {
      final times = List<int>.unmodifiable(_patternTimes);
      _finishItem(
        AbilityScore(
          key: AbilityKey.patternRecognition,
          score: scorePatternRecognition(
            correct: _patternCorrect,
            total: _patternTrialCount,
            medianMillis: medianReactionMillis(times),
          ),
          metrics: <String, Object?>{
            'correct': _patternCorrect,
            'total': _patternTrialCount,
            'median_ms': medianReactionMillis(times),
          },
        ),
      );
      return;
    }
    setState(_startPatternTrial);
  }

  // ---------------------------------------------------------------------------
  // 小测四：注意稳定性
  // ---------------------------------------------------------------------------

  List<_AttentionStimulus> _buildAttentionSchedule() {
    final schedule = <_AttentionStimulus>[
      for (var i = 0; i < _attentionTargetTotal; i++)
        _AttentionStimulus(
          _attentionLetters[_random.nextInt(_attentionLetters.length)],
          isTarget: true,
        ),
      for (var i = 0; i < _attentionNonTargetTotal; i++)
        _AttentionStimulus('${_random.nextInt(10)}', isTarget: false),
    ];
    schedule.shuffle(_random);
    return schedule;
  }

  void _startAttentionTrial() {
    _attentionTimer?.cancel();
    if (_attentionTrial >= _attentionSchedule.length) {
      _finishAttention();
      return;
    }
    final stimulus = _attentionSchedule[_attentionTrial];
    _attentionStimulus = stimulus;
    _attentionTimer = Timer(
      const Duration(milliseconds: _attentionWindowMillis),
      () {
        if (!mounted) return;
        if (stimulus.isTarget) {
          _attentionMisses += 1;
        }
        _attentionTrial += 1;
        if (_attentionTrial >= _attentionSchedule.length) {
          _finishAttention();
          return;
        }
        setState(_startAttentionTrial);
      },
    );
  }

  void _answerAttention({required bool yes}) {
    final stimulus = _attentionStimulus;
    if (stimulus == null) return;
    _attentionTimer?.cancel();
    if (stimulus.isTarget) {
      if (yes) {
        _attentionHits += 1;
      } else {
        _attentionMisses += 1;
      }
    } else {
      _attentionFalseAlarms += 1;
    }
    _attentionTrial += 1;
    if (_attentionTrial >= _attentionSchedule.length) {
      _finishAttention();
      return;
    }
    setState(_startAttentionTrial);
  }

  void _finishAttention() {
    _finishItem(
      AbilityScore(
        key: AbilityKey.attentionStability,
        score: scoreAttentionStability(
          hits: _attentionHits,
          misses: _attentionMisses,
          falseAlarms: _attentionFalseAlarms,
          targets: _attentionTargetTotal,
          nonTargets: _attentionNonTargetTotal,
        ),
        metrics: <String, Object?>{
          'hits': _attentionHits,
          'misses': _attentionMisses,
          'false_alarms': _attentionFalseAlarms,
          'targets': _attentionTargetTotal,
          'non_targets': _attentionNonTargetTotal,
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 保存
  // ---------------------------------------------------------------------------

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final repository = ref.read(abilityScoreRepositoryProvider);
    setState(() => _saving = true);
    try {
      for (final key in AbilityKey.values) {
        final score = _scores[key];
        if (score == null) continue;
        await repository.record(
          key: score.key,
          score: score.score,
          metrics: score.metrics,
        );
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.abilityScoresSaved)),
      );
      navigator.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.abilitySaveFailed('$error'))),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 文案
  // ---------------------------------------------------------------------------

  String _itemTitle(AppLocalizations l10n, AbilityKey key) => switch (key) {
        AbilityKey.reactionSpeed => l10n.abilityReactionTitle,
        AbilityKey.workingMemory => l10n.abilityWorkingMemoryTitle,
        AbilityKey.patternRecognition => l10n.abilityPatternTitle,
        AbilityKey.attentionStability => l10n.abilityAttentionTitle,
      };

  String _itemHint(AppLocalizations l10n, AbilityKey key) => switch (key) {
        AbilityKey.reactionSpeed => l10n.abilityReactionHint,
        AbilityKey.workingMemory => l10n.abilityWorkingMemoryHint,
        AbilityKey.patternRecognition => l10n.abilityPatternHint,
        AbilityKey.attentionStability => l10n.abilityAttentionHint,
      };

  // ---------------------------------------------------------------------------
  // 渲染
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.abilityAssessmentTitle)),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.intro => _buildIntro(l10n),
          _Phase.itemIntro => _buildItemIntro(l10n),
          _Phase.running => _buildRunning(l10n),
          _Phase.itemDone => _buildItemDone(l10n),
          _Phase.summary => _buildSummary(l10n),
        },
      ),
    );
  }

  Widget _buildIntro(AppLocalizations l10n) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              l10n.abilityAssessmentIntro,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: abilityStartKey,
              onPressed: _startAssessment,
              child: Text(l10n.abilityStart),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemIntro(AppLocalizations l10n) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '${_itemIndex + 1} / ${AbilityKey.values.length}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _itemTitle(l10n, _currentKey),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              _itemHint(l10n, _currentKey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: abilityStartItemKey,
              onPressed: _startItem,
              child: Text(l10n.abilityStartItem),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRunning(AppLocalizations l10n) {
    return switch (_currentKey) {
      AbilityKey.reactionSpeed => _buildReaction(l10n),
      AbilityKey.workingMemory => _buildWorkingMemory(l10n),
      AbilityKey.patternRecognition => _buildPattern(l10n),
      AbilityKey.attentionStability => _buildAttention(l10n),
    };
  }

  Widget _buildReaction(AppLocalizations l10n) {
    final ready = _reactionReady;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: <Widget>[
          Text(
            _itemTitle(l10n, _currentKey),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(l10n.abilityReactionHint, textAlign: TextAlign.center),
          const SizedBox(height: 32),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: ready ? _tapReactionTarget : null,
            child: Container(
              key: ready ? abilityReactionTargetKey : abilityReactionWaitKey,
              width: 160,
              height: 160,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ready ? Colors.green : Colors.grey.shade400,
              ),
              child: Text(
                ready ? l10n.abilityReactionTap : l10n.abilityReactionWait,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('${_reactionSamples.length + 1} / $_reactionTrialCount'),
        ],
      ),
    );
  }

  Widget _buildWorkingMemory(AppLocalizations l10n) {
    final showDigits = _memoryShowDigits;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: <Widget>[
          Text(
            _itemTitle(l10n, _currentKey),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(l10n.abilityWorkingMemoryHint, textAlign: TextAlign.center),
          const SizedBox(height: 32),
          if (showDigits) ...<Widget>[
            Text(
              l10n.abilityWorkingMemoryPrompt,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _memoryDigits,
              key: abilityMemoryDigitsKey,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .displaySmall
                  ?.copyWith(letterSpacing: 8),
            ),
          ] else ...<Widget>[
            TextField(
              key: abilityMemoryInputKey,
              controller: _memoryController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.abilityWorkingMemoryInput,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: abilityMemorySubmitKey,
              onPressed: _submitMemory,
              child: Text(l10n.abilityWorkingMemoryCheck),
            ),
          ],
          const SizedBox(height: 24),
          Text('${_memoryTrial + 1} / ${_memorySpanSequence.length}'),
        ],
      ),
    );
  }

  Widget _buildPattern(AppLocalizations l10n) {
    final showB = _patternShowB;
    final symbols = (showB ? _patternB : _patternA).join('  ');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: <Widget>[
          Text(
            _itemTitle(l10n, _currentKey),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(l10n.abilityPatternHint, textAlign: TextAlign.center),
          const SizedBox(height: 32),
          Text(
            symbols,
            key: showB ? abilityPatternBKey : abilityPatternAKey,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displayMedium,
          ),
          const SizedBox(height: 32),
          if (showB)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                FilledButton(
                  key: abilityPatternSameKey,
                  onPressed: () => _answerPattern(samePressed: true),
                  child: Text(l10n.abilityPatternSame),
                ),
                const SizedBox(width: 16),
                OutlinedButton(
                  key: abilityPatternDifferentKey,
                  onPressed: () => _answerPattern(samePressed: false),
                  child: Text(l10n.abilityPatternDifferent),
                ),
              ],
            ),
          const SizedBox(height: 24),
          Text('${_patternTrial + 1} / $_patternTrialCount'),
        ],
      ),
    );
  }

  Widget _buildAttention(AppLocalizations l10n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: <Widget>[
          Text(
            _itemTitle(l10n, _currentKey),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(l10n.abilityAttentionHint, textAlign: TextAlign.center),
          const SizedBox(height: 32),
          Text(
            _attentionStimulus?.text ?? '',
            key: abilityAttentionStimulusKey,
            style: Theme.of(context).textTheme.displayLarge,
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              FilledButton(
                key: abilityAttentionYesKey,
                onPressed: () => _answerAttention(yes: true),
                child: Text(l10n.abilityAttentionYes),
              ),
              const SizedBox(width: 24),
              OutlinedButton(
                key: abilityAttentionNoKey,
                onPressed: () => _answerAttention(yes: false),
                child: Text(l10n.abilityAttentionNo),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('${_attentionTrial + 1} / ${_attentionSchedule.length}'),
        ],
      ),
    );
  }

  Widget _buildItemDone(AppLocalizations l10n) {
    final score = _scores[_currentKey];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _itemTitle(l10n, _currentKey),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.abilityScoreLabel((score?.score ?? 0).round()),
              key: abilityItemScoreKey(_currentKey),
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              alignment: WrapAlignment.center,
              children: <Widget>[
                OutlinedButton(
                  key: abilityRetryKey,
                  onPressed: _retryItem,
                  child: Text(l10n.abilityRetry),
                ),
                FilledButton(
                  key: abilityNextKey,
                  onPressed: _nextItem,
                  child: Text(l10n.abilityNext),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Text(
          l10n.abilitySummaryTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        for (final key in AbilityKey.values)
          ListTile(
            key: abilitySummaryRowKey(key),
            contentPadding: EdgeInsets.zero,
            title: Text(_itemTitle(l10n, key)),
            trailing: Text(
              l10n.abilityScoreLabel((_scores[key]?.score ?? 0).round()),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          key: abilityFinishKey,
          onPressed: _saving ? null : _save,
          child: Text(l10n.abilityFinish),
        ),
        if (_saving)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}
