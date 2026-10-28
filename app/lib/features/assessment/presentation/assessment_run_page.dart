import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../application/assessment_engine.dart';
import '../application/assessment_providers.dart';
import '../application/assessment_session_service.dart';
import '../application/stimulus_generators.dart';
import '../domain/assessment_models.dart';
import 'assessment_display.dart';
import 'assessment_result_page.dart';

/// 运行页进度（当前 trial / 总数）。
const Key assessmentRunProgressKey = Key('assessment-run-progress');

/// 练习阶段徽标（练习不计入测量）。
const Key assessmentRunPracticeBadgeKey = Key('assessment-run-practice-badge');

/// 退出按钮（右上角）。
const Key assessmentRunQuitButtonKey = Key('assessment-run-quit-button');

/// 退出确认对话框的「继续做」按钮。
const Key assessmentRunQuitCancelKey = Key('assessment-run-quit-cancel');

/// 退出确认对话框的「退出」按钮。
const Key assessmentRunQuitConfirmKey = Key('assessment-run-quit-confirm');

/// 任务说明页的开始按钮。
const Key assessmentRunStartKey = Key('assessment-run-start');

/// 通用刺激区（非选项、非点击目标的任务）。
const Key assessmentRunStimulusKey = Key('assessment-run-stimulus');

/// Go/No-Go 与疲劳块的点击目标。
const Key assessmentRunTapTargetKey = Key('assessment-run-tap-target');

/// 超时提示。
const Key assessmentRunTimeoutKey = Key('assessment-run-timeout');

/// 数字广度的数字展示。
const Key assessmentRunDigitDisplayKey = Key('assessment-run-digit-display');

/// 数字广度的倒序输入框。
const Key assessmentRunDigitInputKey = Key('assessment-run-digit-input');

/// 数字广度的确认按钮。
const Key assessmentRunDigitSubmitKey = Key('assessment-run-digit-submit');

/// 数字广度的清空按钮。
const Key assessmentRunDigitClearKey = Key('assessment-run-digit-clear');

/// 保存中的转圈。
const Key assessmentRunSavingKey = Key('assessment-run-saving');

/// 保存失败后的重试按钮。
const Key assessmentRunSaveRetryKey = Key('assessment-run-save-retry');

/// 二选一选项按钮（按选项码区分，例如 circle / red / same）。
Key assessmentRunOptionKey(String code) =>
    ValueKey<String>('assessment-run-option-$code');

/// 单个任务从说明到跑完的全屏流程页。
///
/// 状态机：说明 → 间隔（fixation）→ 刺激 →（响应 / 超时）→ 间隔 …
/// 数字广度是例外：数字展示 → 倒序输入（无响应窗口，等用户提交）。
/// 引擎（[AssessmentRunEngine]）负责出题与判分；本页只负责呈现、计时和把
/// 记录交给 [AssessmentSessionService]。
enum _RunPhase {
  intro,
  isi,
  stimulus,
  digitDisplay,
  digitInput,
  saving,
  saveFailed
}

class AssessmentRunPage extends ConsumerStatefulWidget {
  const AssessmentRunPage({super.key, required this.task});

  final AssessmentTaskConfig task;

  @override
  ConsumerState<AssessmentRunPage> createState() => _AssessmentRunPageState();
}

class _AssessmentRunPageState extends ConsumerState<AssessmentRunPage>
    with WidgetsBindingObserver {
  late final AssessmentRunEngine _engine;
  late final TaskRunParameters _params;
  final TextEditingController _digitInput = TextEditingController();
  Timer? _timer;
  _RunPhase _phase = _RunPhase.intro;
  bool _started = false;
  bool _timedOut = false;
  bool _finishing = false;
  int _backgroundSwitchCount = 0;
  Object? _saveError;

  @override
  void initState() {
    super.initState();
    _engine = AssessmentRunEngine(
      task: widget.task,
      seed: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      startedAt: DateTime.now(),
    );
    _params = TaskRunParameters.fromConfig(widget.task.config);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _digitInput.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 记录切后台次数：只在跑动中计数，用来给本次结果补 background_switch
  /// 质量标记（服务层当前不接收质量标记，见汇报）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused) {
      return;
    }
    if (!_started || _engine.isFinished) {
      return;
    }
    if (_phase == _RunPhase.saving || _phase == _RunPhase.saveFailed) {
      return;
    }
    _backgroundSwitchCount += 1;
  }

  // ---------------------------------------------------------------------------
  // 流程控制
  // ---------------------------------------------------------------------------

  void _start() {
    if (_started) {
      return;
    }
    setState(() {
      _started = true;
      _phase = _RunPhase.isi;
    });
    _scheduleNextTrial();
  }

  void _scheduleNextTrial() {
    _timer?.cancel();
    if (!mounted) {
      return;
    }
    if (_engine.isFinished) {
      unawaited(_finishSession());
      return;
    }
    _timer = Timer(Duration(milliseconds: _params.isiMinMs), _showCurrentTrial);
  }

  void _showCurrentTrial() {
    if (!mounted) {
      return;
    }
    final trial = _engine.current;
    if (trial == null) {
      unawaited(_finishSession());
      return;
    }
    if (!_engine.awaitingResponse) {
      _engine.markShown(DateTime.now());
    }
    final isDigitSpan = widget.task.taskType == AssessmentTaskType.digitSpan;
    setState(() {
      _timedOut = false;
      _phase = isDigitSpan ? _RunPhase.digitDisplay : _RunPhase.stimulus;
    });
    _timer?.cancel();
    if (isDigitSpan) {
      _timer = Timer(
        Duration(milliseconds: _params.digitSpanDisplayMs),
        _showDigitInput,
      );
      return;
    }
    _timer = Timer(
      Duration(milliseconds: _params.responseWindowMs),
      _handleTimeout,
    );
  }

  void _showDigitInput() {
    if (!mounted || _phase != _RunPhase.digitDisplay) {
      return;
    }
    setState(() => _phase = _RunPhase.digitInput);
  }

  void _handleTimeout() {
    if (!mounted || !_engine.awaitingResponse) {
      return;
    }
    _engine.submitTimeout(at: DateTime.now());
    _afterResponse(timedOut: true);
  }

  void _submitResponse(Object? response) {
    if (!_engine.awaitingResponse) {
      return;
    }
    _timer?.cancel();
    _engine.submit(response: response, at: DateTime.now());
    _afterResponse(timedOut: false);
  }

  void _afterResponse({required bool timedOut}) {
    _digitInput.clear();
    if (!mounted) {
      return;
    }
    setState(() {
      _timedOut = timedOut;
      _phase = _RunPhase.isi;
    });
    _scheduleNextTrial();
  }

  void _submitDigitInput() {
    if (_phase != _RunPhase.digitInput) {
      return;
    }
    _submitResponse(_digitInput.text.trim());
  }

  Future<void> _finishSession() async {
    if (_finishing) {
      return;
    }
    _finishing = true;
    _timer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _phase = _RunPhase.saving;
      _saveError = null;
    });
    try {
      final service = ref.read(assessmentSessionServiceProvider);
      final result = await service.completeSession(
        task: widget.task,
        trials: _engine.recorded,
        startedAt: _engine.startedAt,
        completedAt: DateTime.now(),
        device: currentAssessmentDevice(),
        extraQualityFlags: _backgroundSwitchCount > 0
            ? const <String>{QualityFlags.backgroundSwitch}
            : const <String>{},
      );
      if (!mounted) {
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => AssessmentResultPage(
            summary: result.summary,
            metrics: result.metrics,
            abilities: result.abilities,
            params: result.params,
            qualityFlags: result.qualityFlags,
          ),
        ),
      );
    } catch (error) {
      _finishing = false;
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _RunPhase.saveFailed;
        _saveError = error;
      });
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.assessmentRunSaveFailed('$error'))),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 退出
  // ---------------------------------------------------------------------------

  Future<void> _confirmQuit() async {
    if (_phase == _RunPhase.saving) {
      return;
    }
    if (!_started) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }
    final l10n = AppLocalizations.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.assessmentRunQuitConfirmTitle),
        content: Text(l10n.assessmentRunQuitConfirmBody),
        actions: [
          TextButton(
            key: assessmentRunQuitCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.assessmentRunCancel),
          ),
          FilledButton(
            key: assessmentRunQuitConfirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.assessmentRunQuitConfirm),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) {
      return;
    }
    await _recordAbortedAndPop();
  }

  Future<void> _recordAbortedAndPop() async {
    _timer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() => _phase = _RunPhase.saving);
    try {
      await ref.read(assessmentSessionServiceProvider).recordIncompleteSession(
            task: widget.task,
            trials: _engine.recorded,
            startedAt: _engine.startedAt,
            endedAt: DateTime.now(),
            device: currentAssessmentDevice(),
            status: AssessmentSessionStatuses.aborted,
          );
    } catch (error) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.assessmentRunSaveFailed('$error'))),
        );
      }
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  // ---------------------------------------------------------------------------
  // 渲染
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        unawaited(_confirmQuit());
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildHeader(l10n),
                const SizedBox(height: 8),
                Expanded(child: Center(child: _buildStage(l10n))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    final trial = _engine.current;
    final total = _engine.trials.length;
    final current = _engine.isFinished ? total : _engine.trialIndex + 1;
    final showRunning = _started && !_engine.isFinished;
    return Row(
      children: [
        if (showRunning)
          Text(
            l10n.assessmentRunProgress(current, total),
            key: assessmentRunProgressKey,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        if (showRunning && (trial?.isPractice ?? false)) ...[
          const SizedBox(width: 12),
          Chip(
            key: assessmentRunPracticeBadgeKey,
            label: Text(l10n.assessmentRunPracticeBadge),
          ),
        ],
        const Spacer(),
        TextButton.icon(
          key: assessmentRunQuitButtonKey,
          onPressed: _phase == _RunPhase.saving
              ? null
              : () => unawaited(_confirmQuit()),
          icon: const Icon(Icons.close, size: 18),
          label: Text(l10n.assessmentRunQuit),
        ),
      ],
    );
  }

  Widget _buildStage(AppLocalizations l10n) {
    switch (_phase) {
      case _RunPhase.intro:
        return _buildIntro(l10n);
      case _RunPhase.saving:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(key: assessmentRunSavingKey),
          ],
        );
      case _RunPhase.saveFailed:
        return _buildSaveFailed(l10n);
      case _RunPhase.isi:
        return _buildGap(l10n);
      case _RunPhase.digitDisplay:
        return _buildDigitDisplay(l10n);
      case _RunPhase.digitInput:
        return _buildDigitInput(l10n);
      case _RunPhase.stimulus:
        return _buildStimulus(l10n);
    }
  }

  Widget _buildIntro(AppLocalizations l10n) {
    final prompt = _stimulusPrompt(_engine.current);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          assessmentTaskName(l10n, widget.task),
          style: textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        if (prompt.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            prompt,
            style: textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          key: assessmentRunStartKey,
          onPressed: _start,
          child: Text(l10n.assessmentCenterStart),
        ),
      ],
    );
  }

  Widget _buildGap(AppLocalizations l10n) {
    final textTheme = Theme.of(context).textTheme;
    if (_timedOut) {
      return Text(
        l10n.assessmentRunTimeout,
        key: assessmentRunTimeoutKey,
        style: textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
      );
    }
    return Text('+', style: textTheme.headlineMedium);
  }

  Widget _buildStimulus(AppLocalizations l10n) {
    final trial = _engine.current;
    if (trial == null) {
      return const SizedBox.shrink();
    }
    final prompt = _stimulusPrompt(trial);
    final body = switch (widget.task.taskType) {
      AssessmentTaskType.goNogo => _buildTapTarget(l10n, trial),
      AssessmentTaskType.fatigue => _buildTapTarget(l10n, trial),
      AssessmentTaskType.digitSpan => const SizedBox.shrink(),
      _ => _buildChoiceStage(l10n, trial),
    };
    return Column(
      key: assessmentRunStimulusKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (prompt.isNotEmpty)
          Text(
            prompt,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 24),
        body,
      ],
    );
  }

  Widget _buildTapTarget(AppLocalizations l10n, PlannedTrial trial) {
    final shape = trial.stimulus['shape'];
    final isCircle = shape == 'circle';
    const double size = 160;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: assessmentRunTapTargetKey,
          onTap: () => _submitResponse(true),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: isCircle ? null : BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.assessmentRunTapPrompt,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildChoiceStage(AppLocalizations l10n, PlannedTrial trial) {
    final visual = _buildStimulusVisual(trial);
    final options = _stimulusOptions(trial);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (visual != null) ...[
          visual,
          const SizedBox(height: 24),
        ],
        if (options.isEmpty)
          Text(
            l10n.assessmentRunChoicePrompt,
            style: Theme.of(context).textTheme.bodyLarge,
          )
        else
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final code in options)
                FilledButton.tonal(
                  key: assessmentRunOptionKey(code),
                  onPressed: () => _submitOption(trial, code),
                  child: Text(_optionLabel(trial, code)),
                ),
            ],
          ),
      ],
    );
  }

  Widget? _buildStimulusVisual(PlannedTrial trial) {
    final theme = Theme.of(context);
    switch (widget.task.taskType) {
      case AssessmentTaskType.choiceReaction:
        final shape = trial.stimulus['shape'];
        if (shape is String) {
          return _shapeBox(shape);
        }
        final expression = trial.stimulus['expression'];
        if (expression is String && expression.isNotEmpty) {
          return Text(expression, style: theme.textTheme.displaySmall);
        }
        final leftShape = trial.stimulus['left_shape'];
        final rightShape = trial.stimulus['right_shape'];
        if (leftShape is String && rightShape is String) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _shapeBox(leftShape),
              const SizedBox(width: 16),
              _shapeBox(rightShape),
            ],
          );
        }
        return null;
      case AssessmentTaskType.stroop:
        final word = trial.stimulus['word'];
        if (word is! String) {
          return null;
        }
        final ink = trial.stimulus['ink'];
        return Text(
          word,
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: ink == 'red' ? Colors.red : Colors.blue,
          ),
        );
      case AssessmentTaskType.switching:
        final value = trial.stimulus['value'];
        return Text('$value', style: theme.textTheme.displayMedium);
      case AssessmentTaskType.nBack:
        final letter = trial.stimulus['letter'];
        return Text('$letter', style: theme.textTheme.displayMedium);
      default:
        return null;
    }
  }

  Widget _shapeBox(String shape) {
    final isCircle = shape == 'circle';
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(12),
      ),
    );
  }

  void _submitOption(PlannedTrial trial, String code) {
    if (widget.task.taskType == AssessmentTaskType.nBack) {
      _submitResponse(code == 'same');
      return;
    }
    _submitResponse(code);
  }

  String _optionLabel(PlannedTrial trial, String code) {
    final label = _optionLabels(trial)[code] ?? code;
    if (widget.task.taskType == AssessmentTaskType.decisionFatigue) {
      final value = trial.stimulus[code];
      if (value is int) {
        return '$label $value';
      }
    }
    return label;
  }

  Widget _buildDigitDisplay(AppLocalizations l10n) {
    final trial = _engine.current;
    final digits = _digitsOf(trial);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _stimulusPrompt(trial),
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          digits.join(' '),
          key: assessmentRunDigitDisplayKey,
          style: theme.textTheme.displaySmall?.copyWith(letterSpacing: 8),
        ),
      ],
    );
  }

  Widget _buildDigitInput(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.assessmentRunDigitPrompt,
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 320,
          child: TextField(
            key: assessmentRunDigitInputKey,
            controller: _digitInput,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: theme.textTheme.displaySmall,
            onSubmitted: (_) => _submitDigitInput(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              key: assessmentRunDigitClearKey,
              onPressed: _digitInput.clear,
              child: Text(l10n.assessmentRunClear),
            ),
            const SizedBox(width: 12),
            FilledButton(
              key: assessmentRunDigitSubmitKey,
              onPressed: _submitDigitInput,
              child: Text(l10n.assessmentRunSubmit),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSaveFailed(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.assessmentRunSaveFailed('$_saveError'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: assessmentRunSaveRetryKey,
          onPressed: () => unawaited(_finishSession()),
          child: Text(l10n.commonRefresh),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 刺激取值
  // ---------------------------------------------------------------------------

  String _stimulusPrompt(PlannedTrial? trial) {
    final prompt = trial?.stimulus['prompt'];
    return prompt is String ? prompt : '';
  }

  List<String> _stimulusOptions(PlannedTrial trial) {
    final raw = trial.stimulus['options'];
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is String) item,
      ];
    }
    return const <String>[];
  }

  Map<String, String> _optionLabels(PlannedTrial trial) {
    final raw = trial.stimulus['option_labels'];
    if (raw is Map) {
      final labels = <String, String>{};
      for (final entry in raw.entries) {
        labels[entry.key.toString()] = entry.value.toString();
      }
      return labels;
    }
    return const <String, String>{};
  }

  List<int> _digitsOf(PlannedTrial? trial) {
    final raw = trial?.stimulus['digits'];
    if (raw is List) {
      return [
        for (final item in raw)
          if (item is int) item,
      ];
    }
    return const <int>[];
  }
}
