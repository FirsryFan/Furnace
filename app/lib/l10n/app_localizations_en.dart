// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Furnace';

  @override
  String get navMindMap => 'Mind Map';

  @override
  String get navMindnet => 'Mindnet';

  @override
  String get navTags => 'Tags';

  @override
  String get navThread => 'Thread';

  @override
  String get navTasks => 'Tasks';

  @override
  String get navTime => 'Time';

  @override
  String get navAnki => 'Knowledge';

  @override
  String get navKnowledge => 'Knowledge';

  @override
  String get navPackages => 'Library';

  @override
  String get navSettings => 'Settings';

  @override
  String get tagsTitle => 'Tags';

  @override
  String get settingsProfileName => 'Profile name';

  @override
  String get settingsBackup => 'Backup data';

  @override
  String get settingsBackupDone => 'Backup saved';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonClose => 'Close';

  @override
  String get commonTitle => 'Title';

  @override
  String get commonContent => 'Content';

  @override
  String get commonName => 'Name';

  @override
  String get commonDescription => 'Description';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonStart => 'Start';

  @override
  String get commonEnd => 'End';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsLanguageZh => '中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get mindMapNewMap => 'New mind map';

  @override
  String get mindMapAddNode => 'Add node';

  @override
  String get mindMapPromoteTag => 'Promote to tag';

  @override
  String get mindMapPromoteTask => 'Promote to task';

  @override
  String get mindMapRenameNode => 'Rename node';

  @override
  String get mindMapEditNotes => 'Edit notes';

  @override
  String get mindMapMoveUp => 'Move up';

  @override
  String get mindMapMoveDown => 'Move down';

  @override
  String get tasksNewTask => 'New event';

  @override
  String get tasksPriorityHigh => 'High';

  @override
  String get tasksPriorityMedium => 'Medium';

  @override
  String get tasksPriorityLow => 'Low';

  @override
  String get tasksEstimateMinutes => 'Estimate (minutes)';

  @override
  String get tasksExpectedAt => 'Expected time';

  @override
  String get tasksSuggestions => 'Suggestions';

  @override
  String get tasksNoSuggestions => 'No suggestions';

  @override
  String get tasksSubtasks => 'Subtasks';

  @override
  String get tasksDependencies => 'Dependencies';

  @override
  String get tasksAddSubtask => 'Add subtask';

  @override
  String get tasksAddDependency => 'Add dependency';

  @override
  String get tasksRemindAt => 'Remind at';

  @override
  String get tasksReminder => 'Reminder';

  @override
  String get tasksDueAt => 'Deadline';

  @override
  String get timeNewBlock => 'New schedule block';

  @override
  String get timeTodaySchedule => 'Today\'s schedule';

  @override
  String get timeAvailable => 'Open';

  @override
  String get timeUnavailable => 'Busy';

  @override
  String get timeEnergy => 'Energy';

  @override
  String get timeEnergyHigh => 'High';

  @override
  String get timeEnergyMedium => 'Medium';

  @override
  String get timeEnergyLow => 'Low';

  @override
  String get timeSuitable => 'Suitable for';

  @override
  String get timeSuitableMemorize => 'Memorize';

  @override
  String get timeSuitableDeepWork => 'Deep work';

  @override
  String get timeSuitableReview => 'Review';

  @override
  String get timeNone => 'None';

  @override
  String get timeMarkBusy => 'Mark as busy';

  @override
  String get timeMarkOpen => 'Mark as open';

  @override
  String get calendarTimeline => 'Timeline';

  @override
  String get calendarAddBlock => 'New schedule block';

  @override
  String get calendarOpenDay => 'Open day view';

  @override
  String get calendarOpenWeek => 'Open week view';

  @override
  String get calendarDayEmpty => 'No blocks on this day yet';

  @override
  String get timeArbitraryRangeHint =>
      'Start and end are free-form (minute precision), and overlapping blocks are allowed.';

  @override
  String get timeBusyHint =>
      'Busy = a hard block that occupies time (class, meeting); open = a soft block you can plan into.';

  @override
  String get timePlusFiveMinutes => 'Add 5 minutes';

  @override
  String get timeMinusFiveMinutes => 'Subtract 5 minutes';

  @override
  String get timeTemplates => 'Schedule templates';

  @override
  String get timeApplyTemplate => 'Apply a template';

  @override
  String get timeApplyDayTemplate => 'Apply a day template';

  @override
  String get timeApplyWeekTemplate => 'Apply a week template';

  @override
  String get timeNoTemplates =>
      'No templates yet. Lay out a week or a day in the calendar, then save it here.';

  @override
  String get timeDeleteTemplate => 'Delete template';

  @override
  String get timeSaveTemplate => 'Save as template';

  @override
  String timeTemplateBlockCount(int count) {
    return '$count block(s)';
  }

  @override
  String timeTemplateApplied(int count) {
    return 'Applied $count block(s)';
  }

  @override
  String get timelineZoomIn => 'Zoom in';

  @override
  String get timelineZoomOut => 'Zoom out';

  @override
  String get timelineFold => 'Fold (scroll vertically)';

  @override
  String get timelineUnfold => 'Unfold (scroll horizontally)';

  @override
  String timelineSpanDays(int days) {
    return '$days days';
  }

  @override
  String get calendarDay => 'Day';

  @override
  String get calendarWeek => 'Week';

  @override
  String get calendarMonth => 'Month';

  @override
  String get calendarToday => 'Today';

  @override
  String get calendarPrev => 'Previous';

  @override
  String get calendarNext => 'Next';

  @override
  String get calendarZoom => 'Vertical zoom';

  @override
  String get calendarZoom15 => '15 min / row';

  @override
  String get calendarZoom30 => '30 min / row';

  @override
  String get calendarZoom60 => '60 min / row';

  @override
  String get calendarWeekday1 => 'Mon';

  @override
  String get calendarWeekday2 => 'Tue';

  @override
  String get calendarWeekday3 => 'Wed';

  @override
  String get calendarWeekday4 => 'Thu';

  @override
  String get calendarWeekday5 => 'Fri';

  @override
  String get calendarWeekday6 => 'Sat';

  @override
  String get calendarWeekday7 => 'Sun';

  @override
  String get ankiStartReview => 'Start review';

  @override
  String get ankiShowAnswer => 'Show answer';

  @override
  String get ankiSubmit => 'Submit';

  @override
  String get ankiForgot => 'Forgot';

  @override
  String get ankiFuzzy => 'Fuzzy';

  @override
  String get ankiRemembered => 'Remembered';

  @override
  String get ankiManage => 'Manage';

  @override
  String get ankiStats => 'Stats';

  @override
  String get ankiReviews7d => '7d reviews';

  @override
  String get ankiNewKnowledgePoint => 'New knowledge point';

  @override
  String get ankiAutoBlank => 'Auto blank';

  @override
  String get ankiSource => 'Source';

  @override
  String get ankiNewTemplate => 'New template';

  @override
  String get ankiQuestion => 'Question';

  @override
  String get ankiAnswer => 'Answer';

  @override
  String get ankiOptions => 'Options (one per line)';

  @override
  String get ankiType => 'Type';

  @override
  String get ankiTypeMcq => 'Multiple choice';

  @override
  String get ankiTypeFillBlank => 'Fill in blank';

  @override
  String get ankiTypeEssay => 'Essay';

  @override
  String get ankiNoDueCards => 'No cards due';

  @override
  String get ankiCorrect => 'Correct';

  @override
  String get ankiWrong => 'Wrong';

  @override
  String get ankiYourAnswer => 'Your answer';

  @override
  String get packagesImport => 'Import .kpak';

  @override
  String get packagesExport => 'Export .kpak';

  @override
  String get packagesImportHint => 'Select a .kpak file';

  @override
  String get packagesImported => 'Imported';

  @override
  String get packagesExportName => 'Library name';

  @override
  String get packagesExportAuthor => 'Author';

  @override
  String get packagesVersion => 'Version';

  @override
  String get packagesEmpty => 'No packages yet';

  @override
  String get packagesPreviewTitle => 'Import preview';

  @override
  String get packagesImportConfirm => 'Import';

  @override
  String get privacyExportNote =>
      'The exported file does not contain your events, schedule, or review progress.';

  @override
  String get packagesUpgrade => 'Upgrade';

  @override
  String get packagesDefaultName => 'My Library';

  @override
  String get packagesDefaultAuthor => 'Me';

  @override
  String get tagsEmpty => 'No tags yet';

  @override
  String get tagsNewTop => 'New top-level tag';

  @override
  String tagsNewChild(String parent) {
    return 'New under \"$parent\"';
  }

  @override
  String get tagsNameHint =>
      'The name cannot contain / (hierarchy comes from nesting)';

  @override
  String get tagsRename => 'Rename';

  @override
  String get tagsAddChild => 'New child tag';

  @override
  String get tagsExpand => 'Expand';

  @override
  String get tagsCollapse => 'Collapse';

  @override
  String tagsDeleteTitle(String label) {
    return 'Delete \"$label\"?';
  }

  @override
  String get tagsDeleteBody =>
      'Its whole subtree is deleted, and events/items carrying this tag lose it.';

  @override
  String get threadTitle => 'Thread';

  @override
  String get threadSort => 'Update & sort';

  @override
  String get threadNeedsSort => 'Needs re-sorting';

  @override
  String get threadNoEvents => 'No events yet';

  @override
  String get threadGoal => 'Main goal';

  @override
  String get threadGoalEmpty => 'No goal set';

  @override
  String get threadEnergy => 'Energy';

  @override
  String get threadEnergyEmpty => 'Energy not set';

  @override
  String get threadEnergy1 => 'Very low · mechanical chores only';

  @override
  String get threadEnergy2 => 'Very low · mechanical chores only';

  @override
  String get threadEnergy3 => 'Low · light tasks';

  @override
  String get threadEnergy4 => 'Low · light tasks';

  @override
  String get threadEnergy5 => 'Medium · routine work';

  @override
  String get threadEnergy6 => 'Medium · routine work';

  @override
  String get threadEnergy7 => 'High · needs focus';

  @override
  String get threadEnergy8 => 'High · needs focus';

  @override
  String get threadEnergy9 => 'Very high · deep push';

  @override
  String get threadEnergy10 => 'Very high · deep push';

  @override
  String get threadStaleTitle => 'State may be outdated';

  @override
  String get threadStaleBody =>
      'More than 2 hours since the last update. Confirm to sort with the current state.';

  @override
  String get threadArchive => 'Archive';

  @override
  String get threadArchiveCompleted => 'Completed';

  @override
  String get threadArchiveInsufficient => 'Not enough time';

  @override
  String get threadArchiveOverdue => 'Overdue';

  @override
  String threadInsufficientDetail(String needed, String available) {
    return 'needs $needed min, $available min available';
  }

  @override
  String get threadExpectedNear => 'Expected time is near';

  @override
  String get threadArchiveEmpty => 'Archive is empty';

  @override
  String threadDeleteTitle(String title) {
    return 'Delete \"$title\"?';
  }

  @override
  String get threadDeleteBody =>
      'This event is deleted permanently (subtasks and dependencies go with it). It cannot be undone.';

  @override
  String get threadCollapse => 'Collapse status bar';

  @override
  String get threadExpand => 'Expand status bar';

  @override
  String get threadSortHint => 'Re-sort';

  @override
  String get propTitleHint =>
      'What this event is called. The ranking never reads the title, but you recognise it by it.';

  @override
  String get propDescriptionHint =>
      'Longer notes. The ranking never reads this either - it is only for you.';

  @override
  String get propEstimateHint =>
      'How long you think it takes. The ranking uses it to check whether it still fits before the deadline.';

  @override
  String get propExpectedHint =>
      'When you plan to do it. Near that moment it turns yellow and gets a boost - but it can never turn anything red, because it can be postponed.';

  @override
  String get propDeadlineHint =>
      'The real hard bottom line. If it no longer fits, the event moves to \"not enough time\" and leaves the main list.';

  @override
  String get propEnergyHint =>
      'How much energy this needs (1-10). The closer to your current energy, the higher it ranks.';

  @override
  String get propAlgorithm => 'Ranking parameters';

  @override
  String get propAlgorithmHint =>
      'The raw components and weights this event scored in the last sort. Total = sum of component x weight. Use the buttons on the right to edit the weights.';

  @override
  String get propAlgorithmNoData =>
      'No ranking yet - press \"Update & sort\" in the status bar first.';

  @override
  String get propUrgency => 'Urgency';

  @override
  String get propUrgencyHint =>
      'Countdown to the deadline: it climbs faster the closer the deadline is, and reads full marks when overdue or within 15 minutes.';

  @override
  String get propGoalMatch => 'Goal match';

  @override
  String get propGoalMatchHint =>
      'How much this event\'s tags overlap with the current goal text. No goal or no tags means 0.';

  @override
  String get propFit => 'State fit';

  @override
  String get propFitHint =>
      'Average of \"energy required vs your energy now\" and \"estimate vs the next free window\".';

  @override
  String get propExpectedPressure => 'Expected pressure';

  @override
  String get propExpectedPressureHint =>
      'Derived from the expected moment: rises as it approaches, stays saturated while just past it, then decays back to 0.';

  @override
  String get propFatigue => 'Fatigue penalty';

  @override
  String get propFatigueHint =>
      'If you just did something with the same tag within the last hour, points are deducted on a time decay so you do not chain the same kind of work.';

  @override
  String get propTotal => 'Total';

  @override
  String get propFlagInsufficient =>
      'Currently flagged \"not enough time\" and moved out of the main list.';

  @override
  String get propFlagOverdue =>
      'Currently flagged \"overdue\" and moved out of the main list.';

  @override
  String get propFlagExpectedNear =>
      'Currently flagged yellow: the expected moment is near or already past.';

  @override
  String get propWeights => 'Ranking weights';

  @override
  String get propWeightsHint =>
      'Weights apply to all events, not just this one. Saving re-sorts automatically.';

  @override
  String get propWeightsEditable =>
      'Weights apply to every event and are editable.';

  @override
  String get propResetWeights => 'Restore default weights';

  @override
  String get propTemplatesNote =>
      'Event templates and batch edits reuse exactly these parameters.';

  @override
  String knowledgeRemaining(int count) {
    return '$count left';
  }

  @override
  String knowledgeActiveCount(int count) {
    return '$count to clear';
  }

  @override
  String get knowledgeSessionDone => 'This round is done';

  @override
  String get knowledgeWillRepeat =>
      'Wrong: this blank will come back today until you get it right twice in a row.';

  @override
  String knowledgeNextIn(int days) {
    return 'Next review in $days day(s)';
  }

  @override
  String knowledgeBoosted(int count, String factor) {
    return '$count related item(s) lifted too (up to x$factor)';
  }

  @override
  String get knowledgeCreateTask => 'Create event';

  @override
  String get knowledgeTaskCreated => 'Event created';

  @override
  String get knowledgeInsight => 'Today\'s review';

  @override
  String get knowledgeReviewTab => 'Review';

  @override
  String get knowledgeInsightEmpty => 'Nothing recorded today';

  @override
  String get knowledgeInsightWrong => 'Went wrong';

  @override
  String get knowledgeInsightBoost => 'Related items lifted';

  @override
  String knowledgeInsightDistance(int distance) {
    return 'distance $distance';
  }

  @override
  String knowledgeInsightFactor(String factor) {
    return 'x$factor';
  }

  @override
  String get settingsDemoData => 'Load demo data';

  @override
  String get settingsDemoDataHint =>
      'Creates sample tags, knowledge points, events and schedule blocks so the UI can be inspected right away.';

  @override
  String get settingsDemoDataConfirm =>
      'Add the demo data to the current workspace?';

  @override
  String get settingsDemoDataBlocked =>
      'The workspace already has content, so the demo data was not loaded (to avoid duplicates).';

  @override
  String get settingsDemoDataDone => 'Demo data loaded';

  @override
  String get settingsUsageDoc => 'Usage guide';

  @override
  String get settingsUsageDocHint =>
      'The ranking algorithm and every parameter explained in one place';

  @override
  String get docFormulaTitle => 'How the score is computed';

  @override
  String get docFormulaBody =>
      'Total = urgency x weight + goal match x weight + state fit x weight + expected pressure x weight - fatigue penalty x weight. Every component is between 0 and 1, the weights are normalized internally, so the total is between 0 and 1 as well. The order is only recomputed when you press the sort button - nothing changes in the background.';

  @override
  String get docCurrentWeights =>
      'Current weights (shipped values in brackets)';

  @override
  String get docWeightsNormalized =>
      'Edited weights are normalized automatically: even if they do not add up to 1, the total never exceeds 1 because the ranker rescales by their sum.';

  @override
  String get docStatusTitle => 'Event bar edge colours';

  @override
  String get docStatusBody =>
      'Green = completed; blue = waiting (expected moment not reached); yellow = expected moment has passed; red = deadline has passed. The colour only expresses state and never changes the ordering.';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsThemeSystemEntry => 'Follow the system';

  @override
  String get settingsThemeSystemHint =>
      'Switch automatically with the system brightness (built-in themes)';

  @override
  String get settingsThemeBuiltin => 'Built-in theme';

  @override
  String get settingsThemeCustom => 'Custom theme';

  @override
  String get settingsThemeImport => 'Import theme';

  @override
  String get settingsThemeImportHint => 'Pick a .json theme file';

  @override
  String get settingsThemeImportInvalid =>
      'Not a valid theme file (it must be JSON with fields like name and colors)';

  @override
  String settingsThemeImported(String name) {
    return 'Imported theme \"$name\"';
  }

  @override
  String get settingsThemeExport => 'Export theme';

  @override
  String get settingsThemeExported => 'Theme exported';

  @override
  String get settingsThemeDeleted => 'Theme deleted';

  @override
  String get settingsThemeBuiltinProtected =>
      'Built-in themes cannot be deleted (editing saves a copy)';

  @override
  String get settingsThemeBuiltinHint =>
      'This is a built-in theme. Saving stores a copy, so the shipped default stays untouched.';

  @override
  String get settingsThemeEdit => 'Edit theme';

  @override
  String get settingsThemeSaved => 'Theme saved';

  @override
  String get settingsThemeBrightness => 'Brightness';

  @override
  String get settingsThemePrimary => 'Primary colour';

  @override
  String get settingsThemeBackground => 'Background';

  @override
  String get settingsThemeOpacity => 'Background opacity';

  @override
  String get settingsThemeScale => 'Page scale';

  @override
  String get settingsThemeScaleHint =>
      '80%-150%; affects body text and control sizes.';

  @override
  String get settingsThemeAnimations => 'Animations';

  @override
  String get settingsThemeAnimationsOn => 'Animations enabled';

  @override
  String get settingsThemeAnimationsOff => 'Animations disabled';

  @override
  String get settingsThemeFonts => 'Fonts';

  @override
  String get settingsThemeFontUi => 'UI font (empty = system default)';

  @override
  String get settingsThemeFontEditor =>
      'Body/editor font (empty = system default)';

  @override
  String get settingsThemeFontHint =>
      'Enter a font family name. Importing font files is not implemented yet.';

  @override
  String get settingsData => 'Data';

  @override
  String get settingsTfpkgExport => 'Export workspace (.tfpkg)';

  @override
  String get settingsTfpkgExportHint =>
      'Pack everything into one file for backup or moving machines';

  @override
  String get settingsTfpkgImport => 'Import workspace (.tfpkg)';

  @override
  String get settingsTfpkgImportHint =>
      'Restore from a .tfpkg; the current data is backed up first';

  @override
  String settingsTfpkgImportPreview(int rows, int tables, int themes) {
    return 'About to import: $rows rows, $tables tables, $themes themes';
  }

  @override
  String get settingsTfpkgMergeReplace => 'Replace (clear, then write)';

  @override
  String get settingsTfpkgMergeAppend => 'Append (keep local, skip clashes)';

  @override
  String settingsTfpkgImportDone(int rows) {
    return 'Import finished: $rows rows written';
  }

  @override
  String get settingsTfpkgExportDone => 'Workspace exported';

  @override
  String get settingsTfpkgInvalid => 'This is not a valid .tfpkg file';

  @override
  String settingsTfpkgSkippedTables(int count) {
    return '$count table(s) came from a newer version and were skipped';
  }

  @override
  String get settingsBackupNote =>
      'This is a copy of the raw database file; prefer .tfpkg for regular backups.';

  @override
  String get navAi => 'Chat';

  @override
  String get aiTitle => 'AI chat';

  @override
  String get aiNewConversation => 'New chat';

  @override
  String get aiEmptyHint =>
      'Just say what you need, for example: put next week revision into my schedule.';

  @override
  String get aiInputHint => 'Type a message...';

  @override
  String get aiSend => 'Send';

  @override
  String get aiThinking => 'Thinking...';

  @override
  String get aiPendingTitle => 'These need your confirmation';

  @override
  String get aiApproveAll => 'Run all';

  @override
  String get aiRejectAll => 'Reject all';

  @override
  String get aiNeedsConfirm => 'Needs its own confirmation';

  @override
  String get aiAutoExecuted => 'Ran automatically';

  @override
  String get aiUndo => 'Undo';

  @override
  String get aiUndone => 'Undone';

  @override
  String get aiNotConfigured => 'AI is not set up';

  @override
  String get aiNotConfiguredHint =>
      'Add an API key in Settings > AI and the chat screen appears here. Until then the app makes no network request at all.';

  @override
  String get aiGoToSettings => 'Open settings';

  @override
  String get aiDeleteConversation => 'Delete chat';

  @override
  String get aiDeleteConversationConfirm =>
      'Delete this chat? This cannot be undone.';

  @override
  String get settingsAiSection => 'AI';

  @override
  String get settingsAiEnabled => 'Enable AI';

  @override
  String get settingsAiApiKey => 'API key';

  @override
  String get settingsAiApiKeyHint =>
      'Stored in plain text locally, and exported inside .tfpkg';

  @override
  String get settingsAiBaseUrl => 'Base URL';

  @override
  String get settingsAiModel => 'Model';

  @override
  String get settingsAiPermissionMode => 'Permission mode';

  @override
  String get settingsAiPermissionPlan => 'Plan (confirm writes once per turn)';

  @override
  String get settingsAiPermissionAuto =>
      'Auto (run everything but deletions, undoable)';

  @override
  String get settingsAiPermissionHint =>
      'Deletions always ask one by one, in every mode.';

  @override
  String get settingsAiSave => 'Save';

  @override
  String get settingsAiSaved => 'Saved';

  @override
  String get settingsAiKeyRequired => 'An API key is required to enable this';

  @override
  String get settingsAiPlatformNote =>
      'Android has no Node runtime and no desktop browser, so script-based abilities are Windows-only.';
}
