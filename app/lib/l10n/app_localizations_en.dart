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
  String get navAnki => 'Flashcards';

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
  String get tasksReminderPermissionDenied =>
      'Notifications are not allowed, so this reminder will not appear. Allow notifications for Furnace in system settings, then set the reminder again.';

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
  String get ankiNewKnowledgePoint => 'New flashcard';

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
  String get ankiHint => 'Hint';

  @override
  String get ankiHintHelper =>
      'Shown only when you ask for it; asking is not an answer';

  @override
  String get ankiJudgeStrict => 'Strict';

  @override
  String get ankiJudgeLenient => 'Lenient';

  @override
  String get ankiJudgeSelf => 'Self';

  @override
  String get ankiJudgeStrictHint =>
      'Exact characters: dictation and spelling practice';

  @override
  String get ankiJudgeLenientHint =>
      'Ignores spaces, full/half width, punctuation and case; tolerates one typo';

  @override
  String get ankiJudgeSelfHint => 'See the answer, then judge yourself';

  @override
  String get ankiJudgeYourself => 'Compare with the answer and grade yourself';

  @override
  String get ankiAfterAnswerPrompt =>
      'After seeing the answer, how close were you?';

  @override
  String get ankiNearMiss => 'Nearly had it';

  @override
  String get ankiStillForgot => 'Still didn\'t know it';

  @override
  String get ankiAfterAnswerHint =>
      'Only tells the cognitive model whether this was forgetting or learning; the next review date is unchanged.';

  @override
  String get ankiNextCard => 'Next card';

  @override
  String get ankiExposureTooltip =>
      'Reading only, not a review: due date unchanged, no review log';

  @override
  String get ankiExposureRecorded =>
      'Noted as reading only: not a review, due date unchanged';

  @override
  String reviewZoneChip(Object zone) {
    return 'Model\'s read: $zone';
  }

  @override
  String get ankiTypePreference => 'Card type preference';

  @override
  String get ankiTypePreferenceMixed => 'Mixed (currently: fill in blank)';

  @override
  String get ankiTypePreferenceFillBlankLenient => 'Lenient fill in blank';

  @override
  String get ankiTypePreferenceNotSaved =>
      'Saved: it applies from the next generated card on';

  @override
  String get ankiJudgePreference => 'Default judging mode';

  @override
  String get ankiJudgePreferenceDetail =>
      'Only decides what a new answer starts as; the control above each card still wins.';

  @override
  String get ankiTypePreferenceDetail =>
      'Used when a card is generated for new material (auto blank, package import, AI).';

  @override
  String get reviewPreferences => 'Review preferences';

  @override
  String get reviewPlanTitle => 'Review plan';

  @override
  String get reviewPlanToday => 'Today';

  @override
  String get reviewPlanEmpty =>
      'No card group has a daily target yet. Add one to plan \"how much per group, per day\": a group is a tag, and its whole subtree counts as that group.';

  @override
  String get reviewPlanAdd => 'Add a group target';

  @override
  String get reviewPlanPickGroup => 'Which card group?';

  @override
  String get reviewPlanNoTags =>
      'No tags yet: a card group is a tag, so create the tag first.';

  @override
  String reviewPlanGroupTitle(String tag) {
    return 'Daily target for $tag';
  }

  @override
  String get reviewPlanGroupBody =>
      'The tag and everything under it count as this group.';

  @override
  String get todayPlanTitle => 'Today\'s list';

  @override
  String get todayPlanUncalibrated =>
      'The bonus is not calibrated: this order is a hint, not a measurement.';

  @override
  String get todayPlanEmpty =>
      'Nothing is due today. That is not \"nothing to do\" - the due queue is just empty; which new cards to learn is your call, and this page will not invent them.';

  @override
  String todayPlanCount(int count) {
    return '$count things to do today';
  }

  @override
  String todayPlanOmitted(int count) {
    return '$count more sit past this page\'s cap (the list is meant to be followed, not read as a directory).';
  }

  @override
  String get todayPlanKindReview => 'Review';

  @override
  String get todayPlanKindPractice => 'Practice';

  @override
  String get todayPlanMetricRetention => 'retention';

  @override
  String get todayPlanMetricReachability => 'reachability';

  @override
  String todayPlanPrice(String metric, String value, String cost) {
    return '$metric V=$value, cost $cost';
  }

  @override
  String get todayPlanPracticeHint =>
      'Problems are priced by the model (plan_today / evaluate_problem_fit); this page only lists due cards.';

  @override
  String todayPlanFailed(String error) {
    return 'Could not read today\'s list: $error';
  }

  @override
  String get materialIntakeTitle => 'Add material';

  @override
  String get materialIntakeEntryHint =>
      'Paste the AI\'s mindnet.material/1 envelope: see what would be created, then confirm';

  @override
  String get materialIntakeIntro =>
      'Paper material -> the AI reads it into a mindnet.material/1 envelope -> this page does the last steps: paste it, look at the proposals (each with the page and line it came from), then confirm. Nothing is written into knowledge points before you confirm; connections land as clue edges in knowledge_edges (strictly directed, ls uncalibrated, only when both ends exist).';

  @override
  String get materialIntakeEnvelopeLabel => 'Envelope (mindnet.material/1)';

  @override
  String get materialIntakeEnvelopeHint =>
      'protocol: mindnet.material/1 · batch_id: ... · items: [ ... ]';

  @override
  String get materialIntakePreview => 'See proposals';

  @override
  String get materialIntakeClear => 'Clear';

  @override
  String get materialIntakePickPhoto => 'Pick a photo';

  @override
  String get materialIntakePhotoHint =>
      'The photo goes to a vision model; its answer is read straight into a run request (checked, not executed, and nothing is written).';

  @override
  String materialIntakePhotoPickFailed(String message) {
    return 'Could not pick a photo: $message';
  }

  @override
  String materialIntakePhotoReadFailed(String message) {
    return 'The photo did not read into a request: $message';
  }

  @override
  String get materialPhotoReportTitle => 'The request read from the photo';

  @override
  String get materialPhotoReportValid => 'Structurally valid: no hard errors';

  @override
  String get materialPhotoReportInvalid =>
      'Structurally invalid: the whole request is refused';

  @override
  String materialPhotoReportSize(int width, int height) {
    return 'Image sent: $width×$height';
  }

  @override
  String materialPhotoReportCounts(int actions, int evidence) {
    return '$actions actions · $evidence with evidence';
  }

  @override
  String get materialPhotoReportErrors =>
      'Hard errors (each one refuses the whole request)';

  @override
  String get materialPhotoReportPreviews => 'What it would do';

  @override
  String get materialPhotoReportWarnings => 'Suggestions (not blocking)';

  @override
  String get materialPhotoReportRaw => 'What the model said';

  @override
  String get materialPhotoReportNoRaw => '(no answer)';

  @override
  String get materialPhotoReportFailed => 'Could not read it';

  @override
  String get materialIntakeTopicHubs =>
      'Also create topic hubs (off by default: a topic groups things, it is not a card relation)';

  @override
  String materialIntakePendingTitle(int count) {
    return 'Pending list ($count batches, survives closing the page)';
  }

  @override
  String get materialIntakePendingHint =>
      'These were looked at but never confirmed: resuming shows exactly the batch you saw (nothing is recomputed), and knowledge points and clue edges are written only after you confirm.';

  @override
  String materialIntakePendingBatch(int count, String batch) {
    return '$batch: $count pending';
  }

  @override
  String get materialIntakeRestore => 'Resume';

  @override
  String materialIntakeDoneTitle(int count) {
    return 'Confirmed ($count batches)';
  }

  @override
  String get materialIntakeDoneHint =>
      'Nothing left to confirm here; to change them go where they landed — knowledge points in the manage page, clue edges in a point\'s detail.';

  @override
  String materialIntakeDoneBatch(int count, String batch) {
    return '$batch: $count confirmed';
  }

  @override
  String get materialIntakeDoneOpen => 'See what was confirmed';

  @override
  String materialIntakeDoneDialogTitle(String batch) {
    return 'What this batch confirmed ($batch)';
  }

  @override
  String get materialIntakeDoneNote =>
      'These are in the database: knowledge points in knowledge_points, connections as clue edges in knowledge_edges (ls uncalibrated). Rows marked \"already exists - no duplicate\" were in the library when you confirmed; the rest were written just now.';

  @override
  String get materialIntakeUndo => 'Undo this batch';

  @override
  String get materialIntakeUndoTitle => 'Undo this batch?';

  @override
  String get materialIntakeUndoBody =>
      'The knowledge points and clue edges this batch created will be deleted and the proposals go back to pending. Rows that were already in the library when you confirmed, plus any cards, tags or other clue edges, are left untouched. If even one row cannot be undone, the whole batch stays as it is and you get the reasons.';

  @override
  String get materialIntakeUndoConfirm => 'Undo';

  @override
  String materialIntakeUndone(int points, int edges, int restored) {
    return 'Undone: deleted $points knowledge points and $edges clue edges; $restored proposals are back to pending.';
  }

  @override
  String materialIntakeUndoneNothing(int restored) {
    return 'This batch created nothing of its own: $restored proposals are back to pending.';
  }

  @override
  String get materialIntakeUndoBlockedTitle => 'This batch cannot be undone';

  @override
  String get materialIntakeUndoBlockedNote =>
      'Nothing was deleted. Undo only deletes what this batch created itself, and these rows have other things attached:';

  @override
  String materialIntakeUndoBlockedRow(String title, String reason) {
    return '$title - $reason';
  }

  @override
  String materialIntakeBadEnvelope(String error) {
    return 'Rejected as a whole: $error';
  }

  @override
  String materialIntakeProposals(int count) {
    return '$count proposals';
  }

  @override
  String materialIntakeSkipped(int count) {
    return '$count stayed outside the list';
  }

  @override
  String materialIntakePending(int count) {
    return 'Saved as pending ($count rows); closing this page does not lose them';
  }

  @override
  String get materialIntakeNothingToDo =>
      'This batch has nothing to change: every item stayed outside the graph, and each skipped row says why.';

  @override
  String get materialIntakeKindPoint => 'knowledge point';

  @override
  String get materialIntakeKindConnection => 'connection';

  @override
  String get materialIntakeConnectionClue =>
      'clue edge: strictly directed, ls uncalibrated';

  @override
  String get materialIntakeExisting => 'already exists - no duplicate';

  @override
  String materialIntakeConfirm(int count) {
    return 'Confirm and write ($count)';
  }

  @override
  String materialIntakeApplied(
      int created, int existing, int deferred, int remaining) {
    return 'Wrote $created rows (knowledge points and clue edges), $existing already existed, $deferred connections could not land, $remaining still pending';
  }

  @override
  String materialIntakeFrom(String source, String region) {
    return 'Source: $source · $region';
  }

  @override
  String materialIntakeCantLand(String reason) {
    return 'cannot land yet: $reason (get that end into the graph first)';
  }

  @override
  String materialIntakeQuote(String quote) {
    return 'margin: “$quote”';
  }

  @override
  String get materialIntakeNoSource => 'no source recorded';

  @override
  String get reviewPlanNewCardsPerDay => 'New cards per day';

  @override
  String get reviewPlanReviewCardsPerDay => 'Reviews per day';

  @override
  String get reviewPlanZeroIsUnlimited =>
      '0 or empty reviews per day means no limit. Once the review allowance is used up, this group stops drawing new cards for the day - a card answered wrong today still comes back.';

  @override
  String reviewPlanTarget(int newCards, int reviewCards) {
    return 'Target: $newCards new · $reviewCards reviews';
  }

  @override
  String reviewPlanDoneToday(int count) {
    return 'Done today: $count';
  }

  @override
  String reviewPlanRemaining(int count) {
    return 'Remaining allowance: $count';
  }

  @override
  String get reviewPlanReviewsUnlimited => 'Remaining allowance: no limit';

  @override
  String get reviewPlanNewCardsNormal => 'New cards are drawn normally.';

  @override
  String get reviewPlanNewCardsStopped =>
      'Review allowance used up: this group stops drawing new cards today. A card answered wrong today still comes back.';

  @override
  String get reviewPlanEdit => 'Edit target';

  @override
  String get reviewPlanClear => 'Remove target (back to no limit)';

  @override
  String get ankiAutoBlankUnsupported =>
      'Cannot build a card for the current type preference: this content does not have enough to blank out';

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
  String get packagesInstalledTitle => 'Imported packages';

  @override
  String get packagesScopeLabel => 'Export scope';

  @override
  String get packagesScopeAll => 'Everything';

  @override
  String get packagesScopeByTag => 'Filter by tags';

  @override
  String get packagesScopeHint =>
      'Filtering by tags exports only the flashcards under those tags, and no mind maps.';

  @override
  String get packagesSelectTags => 'Select tags';

  @override
  String get packagesNoTags => 'No tags yet, so there is nothing to filter by';

  @override
  String get packagesItemsCount => 'items';

  @override
  String get packagesCardTemplates => 'Cards';

  @override
  String get packagesImportedAt => 'Imported';

  @override
  String get packagesVersionHint => 'e.g. 1.0.0';

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
  String threadRhythmReading(int percent, int minutes) {
    return 'Attention $percent% · $minutes min in';
  }

  @override
  String get threadRhythmAdviceHard => 'Good moment for the hard stuff';

  @override
  String get threadRhythmAdviceModerate => 'Keep the normal pace';

  @override
  String get threadRhythmAdviceRest => 'Time for a break';

  @override
  String get threadRhythmEmpty =>
      'Not enough study history yet - do a few cards first';

  @override
  String get threadRhythmHide => 'Hide this reading';

  @override
  String get threadRhythmUncalibrated =>
      'Rhythm parameters are uncalibrated; a hint, not a measurement';

  @override
  String get threadRhythmToggle => 'Attention availability';

  @override
  String get threadCognitiveRankToggle =>
      'Cognitive ordering (goal + just reviewed)';

  @override
  String get threadCognitiveRankNote =>
      'Cognitive ordering is on: tasks closer to the current goal or to just-reviewed knowledge points come first; the boosts are uncalibrated - a hint, not a measurement';

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
  String knowledgeForcedWait(int minutes) {
    return 'You got this blank right once - it comes back in $minutes min.';
  }

  @override
  String get knowledgeForcedWaitCheck => 'Check again';

  @override
  String get knowledgeNewBlank => 'New blank';

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
  String get knowledgeEdges => 'Clue edges';

  @override
  String get knowledgeEdgesIntro =>
      'Connections from your material land here once you confirm them: strictly directed (A → B does not mean B → A), ls has no calibration source so it is always marked uncalibrated, and an end that is not in the library is shown by id.';

  @override
  String get knowledgeEdgesEmpty =>
      'No clue edges yet — connections from material only land here after you confirm them under \"Add material\".';

  @override
  String knowledgeEdgesCount(int count) {
    return '$count clue edges';
  }

  @override
  String get knowledgeEdgesOriginContains => 'the material stated containment';

  @override
  String get knowledgeEdgesOriginProduce => 'the material stated production';

  @override
  String get knowledgeEdgesOriginTopic => 'topic grouping';

  @override
  String get knowledgeEdgesOriginManual => 'hand-written';

  @override
  String get knowledgeEdgesOriginMaterial => 'material (relation not stated)';

  @override
  String knowledgeEdgesLs(String ls) {
    return 'ls $ls (uncalibrated)';
  }

  @override
  String knowledgeEdgesLsCalibrated(String ls) {
    return 'ls $ls';
  }

  @override
  String get knowledgeEdgesNoLs => 'the material gave no ls (none is claimed)';

  @override
  String get knowledgeEdgesMissingEnd =>
      'one end is not in the library, shown by id';

  @override
  String get knowledgePointEdgesEmpty =>
      'this knowledge point has no clue edges yet (they appear once a material connection is confirmed)';

  @override
  String get knowledgePointEdgesNotInGraph =>
      'this knowledge point is not in the material graph (no external_id), so there are no edges to show';

  @override
  String knowledgePointEdgesOutgoing(String other) {
    return 'points at: $other';
  }

  @override
  String knowledgePointEdgesIncoming(String other) {
    return 'pointed at by: $other';
  }

  @override
  String get knowledgeEdgeAdd => 'Add a clue edge';

  @override
  String get knowledgeEdgeAddTitle => 'Hand-write a clue edge';

  @override
  String get knowledgeEdgeDirectionOutgoing => 'it points at…';

  @override
  String get knowledgeEdgeDirectionIncoming => '…points at it';

  @override
  String get knowledgeEdgePickOther => 'the other end';

  @override
  String get knowledgeEdgeNoOtherPoints =>
      'no other knowledge point in the graph to connect to (hand-written points have no in-graph id)';

  @override
  String get knowledgeEdgeCreated =>
      'added a hand-written clue edge (ls stays empty — no calibration source, so none is claimed)';

  @override
  String knowledgeEdgeAlreadyExists(String origin) {
    return 'this direction already has an edge ($origin); nothing was added';
  }

  @override
  String get knowledgeEdgeEndpointMissing =>
      'both ends must already be in the graph; nothing was added';

  @override
  String get knowledgeEdgeSamePoint =>
      'start and end are the same point; nothing was added';

  @override
  String get knowledgeEdgeDeleteTooltip => 'delete this hand-written edge';

  @override
  String get knowledgeEdgeDeleteConfirm =>
      'Delete this hand-written clue edge?';

  @override
  String get knowledgeEdgeDeleted => 'deleted the hand-written edge';

  @override
  String get knowledgeEdgeNotFound => 'that edge is already gone';

  @override
  String get knowledgeEdgeNotManual =>
      'only hand-written edges can be deleted here (material edges belong to the material step)';

  @override
  String knowledgeEdgeWalkTitle(String point) {
    return 'What this point connects to ($point)';
  }

  @override
  String get knowledgeEdgeWalkHint =>
      'Tap a name to keep walking this line: whichever end you go to, you see that end\'s edges (read-only, nothing is created or deleted).';

  @override
  String get knowledgeEdgeWalkTooltip => 'Walk along this edge to this end';

  @override
  String get settingsDemoData => 'Load demo data';

  @override
  String get settingsDemoDataHint =>
      'Creates sample tags, flashcards, events and schedule blocks so the UI can be inspected right away.';

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
      'How each part works and what its limits are: AI, review, knowledge base, cognitive model, ranking';

  @override
  String get docAiTitle =>
      'What the assistant can do, and what waits for your consent';

  @override
  String get docAiBody =>
      'The AI can only change data through tools, and every tool carries a risk level: read-only calls (query_content, fetch_page, evaluate_problem_fit) run immediately; writes (creating tags, flashcards, tasks, documents...) wait for your consent in both the per-action and the plan-first modes; deletions ask every single time and can be undone. You see what a call will change before it runs and get one undo after it; the model never sees your API key, and skill scripts do not receive it either.';

  @override
  String get docReviewTitle => 'Review and flashcards';

  @override
  String get docReviewBody =>
      'Flashcards hang off tags, and the tag tree is the deck: a daily new/review cap set on one tag covers its whole subtree (no row at all means no cap). Due dates come from FSRS alone - the cognitive model only changes what today\'s queue puts first. Grading can be strict, lenient or self-assessed; lenient ignores typos and word order, and a card you got wrong ignores the daily cap and comes back the same day.';

  @override
  String get docKnowledgeTitle => 'Knowledge base and tags';

  @override
  String get docKnowledgeBody =>
      'Tags form a tree, with / separating the levels. Deleting a tag also deletes its whole subtree together with the flashcards and review history inside it (the AI\'s delete tool asks for each one and leaves an undoable snapshot). Both card shapes - cards generated from a template and cards created directly per unit - count on the cognitive readings page, and the orphan banner there cleans up only when you press its button.';

  @override
  String get docCognitiveTitle => 'How to read the cognitive model';

  @override
  String get docCognitiveBody =>
      'Cognitive model in settings is a read-only readings page: R is current memory strength, R0 is the strength right after learning, Sigma is accumulated effort, and the developing-zone / dead-end column is the tierB diffusion verdict on the tag graph (starts are the most recently reviewed points, targets are the ones due today); with no tags or no usable start and target it reads unavailable, which is not the same as healthy. \"Danger\" needs confidence data this app does not store, so it never appears. The statements at the top record that it does not move due dates, that its parameters are uncalibrated and that it does not decide for you. The AI\'s evaluate_problem_fit tool reads the same numbers to judge whether a question is worth doing now.';

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
  String get settingsAbout => 'About';

  @override
  String get settingsAboutHint =>
      'Version, data location, network egress, known gaps';

  @override
  String get aboutVersionLabel => 'Version';

  @override
  String aboutVersionValue(String version, int build) {
    return '$version (build $build)';
  }

  @override
  String get aboutDataTitle => 'Where the data lives';

  @override
  String get aboutDataBody =>
      'The database, skills, AI-written documents and image attachments all live under this directory. Backing up means copying furnace.db (or using \"Back up data\" above).';

  @override
  String get aboutDataDirLabel => 'Application data directory';

  @override
  String get aboutNetworkTitle => 'Network egress';

  @override
  String get aboutNetworkBody =>
      'Only two things reach the network on their own: (1) AI requests, sent to the endpoint you configured in AI settings - conversation text and images both go there; (2) fetch_page, which reads public pages with GET only, no cookies, refuses loopback and private addresses, follows at most 5 redirects and caps a body at 2 MiB. A skill\'s scripts run only if you switch its network permission on, and that switch decides whether the script runs at all - it does not block individual domains.';

  @override
  String get aboutGapsTitle => 'Known gaps';

  @override
  String get aboutGapsBody =>
      '(1) No DOCX / PDF output - create_document writes .md / .txt only; (2) a skill\'s networkAllow is a switch, not per-domain enforcement (that would need OS-level egress control); (3) skill scripts run on Windows only, so those tools are absent on Android; (4) the browser bridge (browser_bridge) is not implemented; (5) the cognitive model has only the memory tier and the fast scheduler wired up - the run/1 session protocol, metacognition and rhythm tiers are not (see docs/MINDNET_ROADMAP.md); (6) fetch_page cannot refuse a host whose address fails to resolve (recorded, unfixed).';

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
  String get aiInputKeyHint => 'Enter sends · Shift+Enter adds a line break';

  @override
  String get aiInputResizeHandle => 'Drag up or down to resize the message box';

  @override
  String get aiShowConversationList => 'Show the chat list';

  @override
  String get aiHideConversationList => 'Hide the chat list';

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
  String get aiAttachImage => 'Attach image';

  @override
  String get aiRemoveImage => 'Remove image';

  @override
  String get aiImageTooLarge =>
      'Image too large: even after compression it is over 4 MB, so it was not sent. Use a smaller image, or crop the parts you do not need.';

  @override
  String get aiImageUnreadable =>
      'This image could not be read: unsupported format or damaged file. Use PNG, JPG, WebP or GIF.';

  @override
  String get aiUsageCurrent => 'This turn';

  @override
  String get aiUsageLast => 'Last turn';

  @override
  String get aiUsageRounds => 'Rounds';

  @override
  String get aiUsageSteps => 'Tool calls';

  @override
  String get aiUsageTotalTokens => 'Total tokens';

  @override
  String aiUsagePromptCompletion(int prompt, int completion) {
    return 'prompt $prompt + completion $completion';
  }

  @override
  String get aiUsageTokensPerSecond => 'Tokens/s';

  @override
  String get aiUsageCacheHit => 'Cache hit rate';

  @override
  String get aiUsageCacheAbsent =>
      'This endpoint reported no cache accounting.';

  @override
  String get aiUsageCachePartial =>
      'Only some rounds reported cache accounting.';

  @override
  String get aiUsageContext => 'Context used';

  @override
  String aiUsageContextEstimate(int tokens) {
    return 'Estimated against a $tokens-token window; the window is a configured value, not a measurement.';
  }

  @override
  String aiUsagePending(int count) {
    return '$count awaiting approval';
  }

  @override
  String aiUsageRejected(int count) {
    return '$count rejected';
  }

  @override
  String get aiUsageLiveEstimate =>
      'Still streaming: counted from the text that has arrived so far.';

  @override
  String get aiUsageNoUsage => 'This turn reported no token usage.';

  @override
  String get aiUsageUnavailable => '—';

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
  String get settingsAiMaxRounds => 'Tool-call round limit per message';

  @override
  String settingsAiMaxRoundsValue(int rounds) {
    return '$rounds rounds';
  }

  @override
  String get settingsAiMaxRoundsHint =>
      'Each extra round is another paid model call; more rounds let one message finish longer multi-step work. Defaults to 8.';

  @override
  String get settingsAiSave => 'Save';

  @override
  String get settingsAiSaved => 'Saved';

  @override
  String get settingsAiKeyRequired => 'An API key is required to enable this';

  @override
  String get settingsAiPlatformNote =>
      'Android has no Node runtime and no desktop browser, so script-based abilities are Windows-only.';

  @override
  String get skillsTitle => 'Skills';

  @override
  String get skillsIntro =>
      'A .fskill is a zip package: a prompt, plus optional declared tools and scripts. Installing only unpacks files onto disk. Enabling a skill adds its prompt (and its reference files) to what the model is told; a declared tool can then be called, and every call is confirmed by you first.';

  @override
  String get skillsInstall => 'Install .fskill';

  @override
  String get skillsInstallSample => 'Install the sample skill';

  @override
  String get skillsBuiltinTitle => 'Built-in skills:';

  @override
  String get skillsBuiltinInstall => 'Install';

  @override
  String get skillsInstalling => 'Installing...';

  @override
  String get skillsEmpty => 'No skills installed.';

  @override
  String get skillsEnabled => 'Enabled';

  @override
  String get skillsDisabled => 'Disabled';

  @override
  String get skillsPlatforms => 'Platforms';

  @override
  String get skillsNetwork => 'Network';

  @override
  String get skillsNetworkNone => 'none allowed';

  @override
  String get skillsPermissions => 'Permissions';

  @override
  String get skillsPermissionsNone => 'none requested';

  @override
  String get skillsTools => 'Declared tools';

  @override
  String get skillsToolsNone => 'none';

  @override
  String get skillsContainerNote =>
      'The script container is enabled (Windows only): once an enabled skill is part of a turn, its declared script tools appear in the model\'s tool list. Every call waits for your individual confirmation in the conversation, and only then does a one-shot child process start. The child does not receive the app\'s environment, so it cannot borrow your API key.';

  @override
  String get skillsContainerNoteUnavailable =>
      'Script execution is Windows only: there is no Node runtime on this device, so declared script tools do not appear in the model\'s tool list (the skill\'s prompt still applies).';

  @override
  String get skillsContainerPromptOnly =>
      'This skill has no scripts to run: only its prompt applies, on both Android and Windows, for as long as it stays enabled.';

  @override
  String get skillsContainerRunnable =>
      'This machine can run the skill\'s scripts (Windows), so its declared tools are offered to the model while it is enabled.';

  @override
  String skillsContainerNotRunnable(String platforms) {
    return 'This machine cannot run the skill\'s scripts (it declares $platforms only), so its tools are not offered to the model; its prompt still applies while it is enabled.';
  }

  @override
  String skillsUnsupportedCapability(String capability) {
    return 'The container does not provide the host capability $capability (see docs/SKILL_FORMAT.md §4): a skill asking for it has its script calls refused rather than run without it.';
  }

  @override
  String skillsNetworkConsent(String domains) {
    return 'Allow network ($domains)';
  }

  @override
  String skillsNetworkNoConsent(String domains) {
    return 'Network not allowed ($domains): its script calls are refused until you turn this on.';
  }

  @override
  String get skillsNetworkDeclaredNone =>
      'This skill declares no network use (networkAllow is empty).';

  @override
  String get skillsNetworkConsentNote =>
      'Turning this on lets this skill\'s scripts use the network. What you are shown is the domain list it declares; the container confines by declaration, it does not block other domains at the OS level.';

  @override
  String get skillsNetworkToggleFailed =>
      'Could not change this skill\'s network permission';

  @override
  String get skillsPath => 'Files';

  @override
  String get skillsRemove => 'Remove';

  @override
  String get skillsRemoveConfirmTitle => 'Remove skill';

  @override
  String skillsRemoveConfirm(String name) {
    return '$name: delete this skill\'s files from disk? This cannot be undone from inside the app.';
  }

  @override
  String get skillsCancel => 'Cancel';

  @override
  String get skillsRemoveFailed => 'Could not remove this skill';

  @override
  String get skillsToggleFailed => 'Could not change this skill\'s state';

  @override
  String get skillsInstallFailed => 'Installation refused or failed';

  @override
  String get settingsThemeBackgroundNone => 'No background image';

  @override
  String get settingsThemeBackgroundSet => 'Background image set';

  @override
  String get settingsThemeBackgroundPick => 'Pick an image';

  @override
  String get settingsThemeBackgroundBlur => 'Background blur';

  @override
  String get settingsThemeBackgroundFailed => 'That image could not be read';

  @override
  String get settingsTfpkgExportSecretsHint =>
      'This package would include your AI API key. If you are sending it to someone else, choose the version without secrets.';

  @override
  String get settingsTfpkgExportWithSecrets => 'Include (for my own backup)';

  @override
  String get settingsTfpkgExportNoSecrets => 'Without secrets (to share)';

  @override
  String get settingsTfpkgExportDoneNoSecrets =>
      'Workspace exported (API key excluded)';

  @override
  String get cognitiveModelTitle => 'Cognitive model';

  @override
  String get cognitiveModelSubtitle => 'Read-only readings: R / band / zone';

  @override
  String get cognitiveAdvisorMode => 'Advisor mode: due dates are not changed';

  @override
  String get cognitiveAdvisorModeDetail =>
      'FSRS still owns when a card is due. The model only influences the queue order and the numbers on this page.';

  @override
  String get cognitiveUncalibratedWeights =>
      'Weights such as ls are not calibrated';

  @override
  String get cognitiveUncalibratedWeightsDetail =>
      'The model\'s edge weights (ls and friends) have no calibration source, so this ordering is a heuristic, not a measurement.';

  @override
  String get cognitiveReadOnlyNote =>
      'Read-only page: nothing here is written to the database';

  @override
  String get cognitiveZoneNote =>
      'Zone uses the same ReviewZone vocabulary as the review queue. \"Unavailable\" only means nothing was diagnosed this time - it is not the same as \"healthy (checked, nothing to report)\".';

  @override
  String get cognitiveFastLayerNote => 'Zones come from the tierB fast layer';

  @override
  String get cognitiveFastLayerRanDetail =>
      'It ran this time: each zone is the diffusion verdict on the tag graph (weak / empty / slow / overloaded / off-goal / dead-end). Starts are the most recently reviewed knowledge points, targets are the ones due today.';

  @override
  String get cognitiveFastLayerNotRunDetail =>
      'It did not run this time: there are no tags, or no usable start and target, so every zone reads unavailable.';

  @override
  String get cognitiveDangerNote =>
      '\"Danger (confident but forgetting)\" is now computed by the metacognition layer: it appears only when a knowledge point is lit up on the tag graph this run while its cards have gone untouched for a long time. A knowledge point that is not listed is not therefore fine - it may simply not have been judged this time.';

  @override
  String get cognitiveMetacognitionTitle => 'How the model reads you';

  @override
  String get cognitiveMetacognitionDetail =>
      'Compares how much the model believes in a node (belief, from fluency, encoding strength and recency) with how much its cards can actually still be recalled. The wider the gap, the more it is worth a look.';

  @override
  String cognitiveMetacognitionCalibration(Object gap) {
    return 'mean gap $gap (smaller is better; the weights are uncalibrated, so this is for reference)';
  }

  @override
  String cognitiveMetacognitionDanger(Object nodes) {
    return 'danger: $nodes (being studied, but the cards are long untouched)';
  }

  @override
  String cognitiveMetacognitionAnxiety(Object nodes) {
    return 'underrated: $nodes (the cards are fine; you feel they are not)';
  }

  @override
  String get cognitiveMetacognitionNoRows =>
      'No knowledge point could be judged this time: each one needs at least one card, and the diagnosis has to have run.';

  @override
  String get cognitiveMetacognitionLevel =>
      'No knowledge point crossed the 0.2 gap threshold: nothing is in danger or underrated this run.';

  @override
  String cognitiveSummary(int cards, String model) {
    return '$cards card(s), model $model';
  }

  @override
  String cognitiveSummaryBands(String bands) {
    return 'Bands: $bands';
  }

  @override
  String cognitiveSummaryNumbers(int newCards, String meanR) {
    return 'New cards $newCards, mean R $meanR';
  }

  @override
  String cognitiveReadAt(String moment) {
    return 'Read at $moment';
  }

  @override
  String get cognitiveEmpty =>
      'No cards to observe yet. Add a flashcard and review a few cards first.';

  @override
  String cognitiveOrphanTitle(int count) {
    return '$count card states whose flashcard is gone';
  }

  @override
  String get cognitiveOrphanDetail =>
      'They can never be reviewed again, so they are not listed as cards. Clearing them deletes the rows (and their review logs) for good.';

  @override
  String cognitiveOrphanAction(int count) {
    return 'Clear $count';
  }

  @override
  String cognitiveOrphanDone(int count) {
    return 'Cleared $count unusable card states';
  }

  @override
  String get cognitiveNewCard => 'new';

  @override
  String get cognitiveSeenCard => 'seen';

  @override
  String cognitiveCardId(String id) {
    return 'card $id';
  }

  @override
  String cognitiveRetrievability(String value) {
    return 'R $value';
  }

  @override
  String cognitiveGain(String value) {
    return 'gain $value';
  }

  @override
  String cognitiveEncoding(String value) {
    return 'R0 $value';
  }

  @override
  String cognitiveEncodingPrior(String value) {
    return 'R0 $value (measurement prior)';
  }

  @override
  String get cognitivePriorNote => 'Measurement priors';

  @override
  String cognitivePriorCount(int count) {
    return '$count cards now start from a measurement prior (uncalibrated); the rest start from their own review history or the model\'s defaults. Once a card has actually been reviewed, the observation takes over and the prior stops speaking.';
  }

  @override
  String get cognitivePriorNone =>
      'No measurement priors yet: every card starts from the model\'s defaults or its own review history. One measurement gives this part of the material an estimate about you.';

  @override
  String cognitiveSavings(String value) {
    return 'Sigma $value';
  }

  @override
  String cognitiveTags(int count) {
    return 'tags $count';
  }

  @override
  String get cognitiveColumnBand => 'Band';

  @override
  String get cognitiveColumnZone => 'Zone';

  @override
  String get cognitiveColumnSchedule => 'Schedule (FSRS)';

  @override
  String get cognitiveGainNotUsed =>
      'gain does not decide this position: the card is forced or boosted, so the model did not place it (D5)';

  @override
  String get cognitiveNewCardNotOrdered =>
      'new cards are neither scored nor ordered by the model (D4)';

  @override
  String get cognitiveNoSchedule => 'unscheduled';

  @override
  String cognitiveDue(String moment) {
    return 'due $moment';
  }

  @override
  String cognitiveInterval(String days) {
    return 'interval $days d';
  }

  @override
  String cognitiveSuggestedInterval(int days) {
    return 'a Good answer now would schedule $days d';
  }

  @override
  String get cognitiveErrorTitle => 'The readings could not be loaded';

  @override
  String get cognitiveBandForced => 'forced today';

  @override
  String get cognitiveBandBoosted => 'boosted (heuristic)';

  @override
  String get cognitiveBandModel => 'model-ranked';

  @override
  String get cognitiveBandUnseen => 'unseen';

  @override
  String get cognitiveZoneProximal => 'proximal (almost recalled)';

  @override
  String get cognitiveZoneEmpty => 'empty (no way in)';

  @override
  String get cognitiveZoneDeadEnd => 'dead end';

  @override
  String get cognitiveZoneSlow => 'slow (needs too many rounds)';

  @override
  String get cognitiveZoneOverload => 'overload (outcompeted by capacity)';

  @override
  String get cognitiveZoneOffGoal => 'off goal';

  @override
  String get cognitiveZoneDanger => 'danger (confident but forgotten)';

  @override
  String get cognitiveZoneHealthy => 'healthy (checked, nothing to report)';

  @override
  String get cognitiveZoneUnavailable => 'unavailable (no diagnosis)';

  @override
  String get assessmentTitle => 'Give the model a starting point';

  @override
  String get assessmentIntro =>
      'Every number on the reading page comes either from your review history or from the model\'s defaults. This does a third thing: one short assessment that replaces the defaults with an estimate about you. It measures abstract parameters (starting retrievability, fluency), not how many cards you memorised; self-report starts, objective checks come later. Every prior is still marked uncalibrated - it is a starting point, not a conclusion.';

  @override
  String get assessmentStepScope => '1. Scope';

  @override
  String get assessmentStepSelf => '2. Self-report';

  @override
  String get assessmentStepRecall => '3. Recall check';

  @override
  String get assessmentStepResult => '4. Reading';

  @override
  String get assessmentScopeHint =>
      'Pick one area (a selected tag includes its children). The tighter the scope, the more the priors deserve to be taken seriously; spread over the whole library they are only an average.';

  @override
  String assessmentScopeCount(Object count) {
    return '$count knowledge points in this area';
  }

  @override
  String get assessmentScopeEmpty =>
      'Nothing to measure yet: create tags on the tags page and knowledge points in flashcards first.';

  @override
  String get assessmentNext => 'Next';

  @override
  String get assessmentBack => 'Back';

  @override
  String get assessmentSkip => 'Skip this time';

  @override
  String get assessmentSelfHint =>
      'Without looking anything up, how much could you retell right now? 0 = nothing at all, 5 = I could teach it. Self-report is not an exam; it gives the model a starting point, and objective checks will correct it.';

  @override
  String assessmentSelfAnswered(Object answered, Object total) {
    return 'Self-rated $answered / $total';
  }

  @override
  String get assessmentRecallHint =>
      'These three knowledge points are the two ends and the middle of the scope - the same set every time, so different days can be compared. Write your retelling, then rate it: did it hold up?';

  @override
  String get assessmentRecallPrompt => 'Retell this knowledge point';

  @override
  String get assessmentRecallAnswer => 'What I retold (optional)';

  @override
  String get assessmentRecallRating => 'Did my retelling hold up?';

  @override
  String get assessmentFinish => 'Finish and recompute priors';

  @override
  String get assessmentResultTitle => 'This round\'s reading';

  @override
  String get assessmentResultPending =>
      'The button below ends this round: it writes the answers as evidence, then recomputes the priors for the scope.';

  @override
  String assessmentResultBody(Object steps, Object points) {
    return 'Wrote $steps evidence steps and recomputed priors for $points knowledge points.';
  }

  @override
  String assessmentResultR0(Object r0) {
    return 'Mean starting R0 $r0';
  }

  @override
  String assessmentResultConfidence(Object confidence) {
    return 'Mean confidence $confidence (n/(n+3): more samples move it toward 1)';
  }

  @override
  String get assessmentResultUncalibrated =>
      'Every prior is marked uncalibrated: these constants are still the model\'s defaults. With so few answers they are a starting point, not a conclusion; calibration waits for objective checks to accumulate.';

  @override
  String get assessmentNoEvidence =>
      'This round wrote no evidence at all (everything was skipped), so there are no priors - an empty round must not pollute the reading.';

  @override
  String get assessmentEntryAction =>
      'Measure (give the model a starting point)';

  @override
  String get learningMetricsTitle => 'Learning effect (the review log decides)';

  @override
  String get learningMetricsDetail =>
      'Retention is \"how much was still there after that long\", read from review outcomes only - not from the model\'s own opinion of itself. Calibration waits for reviews that recorded a prediction.';

  @override
  String get learningMetricsEmpty =>
      'No reviews yet - these numbers grow as you review.';

  @override
  String get learningMetricsNoBuckets =>
      'There are reviews, but no second review of any card yet, so there is no interval to bucket.';

  @override
  String get learningMetricsUnavailable =>
      'The review log could not be read (see the error above), so this block has no numbers.';

  @override
  String learningMetricsOverall(Object reviewed, Object retention) {
    return '$reviewed reviews, $retention% recalled overall';
  }

  @override
  String learningMetricsBucket(Object range, Object samples, Object retention) {
    return '$range d: $samples reviews, $retention% recalled';
  }

  @override
  String learningMetricsCalibration(Object brier, Object ece) {
    return 'Calibration: Brier $brier (lower is better), ECE $ece (per-bin gap between prediction and outcome)';
  }

  @override
  String get learningMetricsNoCalibration =>
      'No calibration samples yet: from this version on, every review records what the model predicted before the answer. Old reviews have no such value and are not back-filled.';

  @override
  String get settingsThemeIcons => 'Icons';

  @override
  String get settingsThemeIconsHint =>
      'Icons are set per semantic slot. A name this build does not know falls back to the slot\'s built-in icon.';

  @override
  String get iconPickerTitle => 'Pick an icon';

  @override
  String get iconPickerSearch => 'Search icon names';

  @override
  String get iconPickerRestoreDefault => 'Restore default';

  @override
  String get iconPickerDefault => 'Default';

  @override
  String get iconPickerEmpty => 'No icon matches that name';

  @override
  String get iconCategoryCommon => 'Common';

  @override
  String get iconCategoryNavigation => 'Navigation';

  @override
  String get iconCategoryTime => 'Time';

  @override
  String get iconCategoryKnowledge => 'Knowledge';

  @override
  String get iconCategoryObjects => 'Objects';

  @override
  String get iconCategoryMedia => 'Media';

  @override
  String get iconCategoryPeople => 'People';

  @override
  String get iconCategoryAi => 'AI';

  @override
  String get iconCategoryUi => 'Interface';

  @override
  String get questionIntakeTitle => 'Question intake';

  @override
  String get questionIntakeSubtitle =>
      'Paste a question, photograph it, or browse the bank';

  @override
  String get questionIntakeEntryHint => 'Paste, photograph, browse';

  @override
  String get questionIntakePasteSection => 'Paste a question';

  @override
  String get questionIntakePhotoSection => 'Photograph / pick images';

  @override
  String get questionIntakeLibrarySection => 'Question bank';

  @override
  String get questionIntakeStemLabel => 'Stem';

  @override
  String get questionIntakeStemHint =>
      'Paste the stem as-is (formulas keep their LaTeX)';

  @override
  String get questionIntakeSubjectLabel => 'Subject';

  @override
  String get questionIntakeSubjectNone => 'Unlabelled';

  @override
  String get questionIntakeQuestionTypeLabel => 'Question type';

  @override
  String get questionIntakeTypeSolution => 'Solution';

  @override
  String get questionIntakeTypeSingleChoice => 'Multiple choice';

  @override
  String get questionIntakeOptionsLabel => 'Options';

  @override
  String questionIntakeOptionLabel(String label) {
    return 'Option $label';
  }

  @override
  String get questionIntakeOptionContentHint => 'Option text';

  @override
  String get questionIntakeAddOption => 'Add an option';

  @override
  String get questionIntakeRemoveOption => 'Remove this option';

  @override
  String get questionIntakeCorrectTooltip => 'Mark as correct';

  @override
  String get questionIntakeAnswerLabel => 'Answer';

  @override
  String get questionIntakeSolutionLabel => 'Solution notes';

  @override
  String get questionIntakeSourceLevelLabel => 'Source tier';

  @override
  String get questionIntakeSourceLabelLabel => 'Source label';

  @override
  String get questionIntakeSourceLabelHint =>
      'e.g. 2024 Hunan Normal University High School monthly exam';

  @override
  String get questionIntakeYearLabel => 'Year';

  @override
  String get questionIntakeRegionLabel => 'Region';

  @override
  String get questionIntakeDifficultyLabel => 'Difficulty (1–10, optional)';

  @override
  String get questionIntakeSubmit => 'Save to bank';

  @override
  String questionIntakeSaved(String stem) {
    return 'Saved: $stem';
  }

  @override
  String questionIntakeDuplicate(String stem) {
    return 'This question is already in the bank (same fingerprint): $stem';
  }

  @override
  String get questionIntakeStemRequired => 'The stem cannot be empty';

  @override
  String get questionIntakeDifficultyInvalid =>
      'Difficulty must be a number between 1 and 10';

  @override
  String get questionIntakePickImages => 'Pick images / photograph';

  @override
  String get questionIntakePicking => 'Saving…';

  @override
  String questionIntakePhotoAdded(int count) {
    return 'Saved $count; waiting for the AI to structure them';
  }

  @override
  String questionIntakePhotoFailed(String error) {
    return 'Picking images failed: $error';
  }

  @override
  String get questionIntakePhotoPending => 'Images waiting';

  @override
  String get questionIntakeNoPhotos =>
      'No photos yet. Picked images are stored locally until the AI turns them into stems.';

  @override
  String questionIntakePhotoSummary(String mime, String extension) {
    return '$mime · .$extension';
  }

  @override
  String questionIntakePhotoStem(String filename) {
    return 'To recognise (image): $filename';
  }

  @override
  String get questionIntakeRemovePhoto => 'Remove from the list';

  @override
  String get questionIntakeNoQuestions => 'The question bank is still empty';

  @override
  String questionIntakeListLimitNote(int count) {
    return 'Showing at most the most recent $count';
  }

  @override
  String get questionIntakeDelete => 'Delete';

  @override
  String questionIntakeDeleted(String stem) {
    return 'Deleted: $stem';
  }

  @override
  String get questionIntakeDeleteConfirm =>
      'Delete this question? It will not come back from sync.';

  @override
  String get questionIntakeCancel => 'Cancel';

  @override
  String get questionIntakeSearchHint => 'Search stems';

  @override
  String get questionIntakeFilterAll => 'All';

  @override
  String questionIntakeOptionCount(int count) {
    return '$count options';
  }

  @override
  String get questionIntakeStateRaw => 'Waiting';

  @override
  String get questionIntakeStateStructured => 'Structured';

  @override
  String get questionIntakeStateProcessed => 'Processed';

  @override
  String get questionIntakeOriginManual => 'Manual';

  @override
  String get questionIntakeOriginAiScan => 'Photo/scan';

  @override
  String get questionIntakeOriginFurnace => 'Built in Furnace';

  @override
  String get questionIntakeSourceGaokao => 'Gaokao paper';

  @override
  String get questionIntakeSourceProvincialDiagnostic =>
      'Provincial/city diagnostic';

  @override
  String get questionIntakeSourceEliteSchool => 'Elite school test';

  @override
  String get questionIntakeSourceSchool => 'School test';

  @override
  String get questionIntakeSourcePersonal => 'Self-made';

  @override
  String get questionIntakeSourceUnknown => 'Unlabelled';

  @override
  String get questionDetailTitle => 'Question detail';

  @override
  String get questionDetailQuestionMissing =>
      'This question is no longer in the library (it may have just been deleted).';

  @override
  String get questionDetailCorrectOption => 'correct';

  @override
  String questionDetailYear(int year) {
    return '$year';
  }

  @override
  String questionDetailDifficulty(String value) {
    return 'Difficulty $value';
  }

  @override
  String questionDetailAiQuality(String value) {
    return 'AI self-rated quality $value';
  }

  @override
  String get questionDetailTrapNote => 'Trap';

  @override
  String get questionDetailReasoningSection =>
      'AI solving and stuck-point review';

  @override
  String get questionDetailSolveButton => 'Solve with AI';

  @override
  String get questionDetailResolveButton => 'Solve again';

  @override
  String get questionDetailSolving => 'Solving…';

  @override
  String get questionDetailNoChainYet =>
      'No reasoning chain yet. Use the button above to have the AI solve it; the chain is saved to your local library.';

  @override
  String get questionDetailChainFromLibrary =>
      'Below is the chain saved by the most recent run; solving again saves a new one.';

  @override
  String get questionDetailRunFailedTitle => 'This run did not succeed';

  @override
  String get questionDetailFailureReasonLabel => 'Reason';

  @override
  String get questionDetailRawReplyLabel => 'Raw model reply';

  @override
  String get questionDetailRawReplyMissing => '(no raw reply was kept)';

  @override
  String questionDetailOverallRisk(int percent) {
    return 'Highest stuck-point risk in the chain: about $percent%';
  }

  @override
  String questionDetailMostLikelyStep(int index) {
    return 'The step you are most likely to get stuck on is step $index';
  }

  @override
  String questionDetailEvidenceCoverage(int covered, int total) {
    return '$covered of $total steps have your state readings';
  }

  @override
  String questionDetailStepTitle(int index) {
    return 'Step $index';
  }

  @override
  String questionDetailUnknownAction(String actionType) {
    return 'Action not in the catalogue: $actionType';
  }

  @override
  String get questionDetailStepGoalLabel => 'What this step achieves';

  @override
  String get questionDetailStepJustificationLabel => 'Why it holds';

  @override
  String get questionDetailStepCheckLabel => 'How to check';

  @override
  String get questionDetailStepKnowledgeLabel => 'Knowledge points involved';

  @override
  String questionDetailModelRisk(int percent) {
    return 'Model\'s risk judgement: about $percent%';
  }

  @override
  String questionDetailFusedRisk(int percent) {
    return 'Combined with your state readings: about $percent%';
  }

  @override
  String get questionDetailSuggestionLabel => 'Suggestion';

  @override
  String get questionDetailUnmatchedHintsTitle =>
      'No state readings for these knowledge points';

  @override
  String get questionDetailUnmatchedHintsBody =>
      'That does not mean they are fine - it means no memory reading is stored for them yet.';

  @override
  String get questionDetailKnowledgePointsLabel =>
      'Knowledge points linked to this question';

  @override
  String get questionDetailKnowledgePointNoReading => 'No state readings yet';

  @override
  String get questionDetailStatesLoading => 'Reading your learning state…';

  @override
  String questionDetailStatesFailed(String error) {
    return 'Could not read the state readings: $error';
  }

  @override
  String get questionPaperTitle => 'Build a paper';

  @override
  String get questionPaperEntryHint =>
      'Assemble a practice paper from your weak and at-risk points';

  @override
  String get questionPaperSubtitle =>
      'Picks only from questions you already have: at-risk points first, gaps listed honestly - AI never writes questions for you.';

  @override
  String get questionPaperTargetCountLabel => 'Target question count';

  @override
  String questionPaperCountOption(int count) {
    return '$count questions';
  }

  @override
  String get questionPaperSubjectLabel => 'Subject';

  @override
  String get questionPaperSubjectAny => 'Any subject';

  @override
  String get questionPaperSubjectNone => 'No subject';

  @override
  String get questionPaperSourceLevelLabel => 'Minimum source level';

  @override
  String get questionPaperSourceLevelAny => 'Any source';

  @override
  String questionPaperHeadline(int want, int got) {
    return 'Wanted $want, assembled $got';
  }

  @override
  String questionPaperFailed(String error) {
    return 'Could not build the paper: $error';
  }

  @override
  String get questionPaperShortNotice =>
      'Not enough questions locally - not an error, your bank simply does not have enough yet. Collect more and come back.';

  @override
  String questionPaperOverallNeed(String need) {
    return 'Overall training need $need';
  }

  @override
  String questionPaperCandidateCount(int count) {
    return '$count candidates';
  }

  @override
  String get questionPaperEmptyBank =>
      'Your question bank is empty: collect questions first, then come back.';

  @override
  String get questionPaperEmptyPlan =>
      'Nothing matches the current filters: loosen the subject or the source level.';

  @override
  String get questionPaperUncoveredTitle =>
      'No candidates in your bank → collect questions';

  @override
  String get questionPaperUncoveredBody =>
      'These knowledge points are at risk but your bank has no related question. AI does not write questions, so this stays empty on purpose.';

  @override
  String get questionPaperDeferredTitle => 'Pushed out this round';

  @override
  String get questionPaperDeferredBody =>
      'Candidates exist but were pushed out by the target count or the per-point cap; raise the target count.';

  @override
  String get questionPaperKnowledgePointLabel => 'Knowledge point';

  @override
  String get questionPaperKnowledgePointNone => 'No knowledge point';

  @override
  String questionPaperItemIndex(int index) {
    return 'Question $index';
  }

  @override
  String get questionPaperItemReasonLabel => 'Why it is here';

  @override
  String get questionPaperItemImprovementLabel => 'What it improves';

  @override
  String get questionPaperItemBackgroundLabel => 'Background';

  @override
  String get questionSimilarTitle => 'Similar questions';

  @override
  String get questionSimilarSubtitle =>
      'Searches the existing question bank only. When nothing is similar it says so instead of padding the list.';

  @override
  String get questionSimilarLoading => 'Scanning the question bank…';

  @override
  String questionSimilarFailed(String error) {
    return 'Similar-question search failed: $error';
  }

  @override
  String questionSimilarCount(int count) {
    return 'Found $count similar question(s)';
  }

  @override
  String get questionSimilarEmpty => 'No similar questions in the bank yet.';

  @override
  String get questionSimilarGoIntake => 'Add questions';

  @override
  String get questionSimilarCrossSubject => 'Cross-subject transfer';

  @override
  String get handwritingQueueTitle => 'Handwriting intake';

  @override
  String get handwritingQueueEntryHint =>
      'Turn photos into tags, knowledge points and flashcards - confirmed one by one before anything is written';

  @override
  String get handwritingQueueSubtitle =>
      'The model only organises what is on the page; every item is written only after you confirm it.';

  @override
  String get handwritingQueueEmpty =>
      'No photos yet. Take one on the intake page, then come back here.';

  @override
  String get handwritingQueueGoIntake => 'Open intake page';

  @override
  String get handwritingQueuePhotosLabel => 'Photos to organise';

  @override
  String get handwritingQueueOrganizeAction => 'Organise this';

  @override
  String get handwritingQueueAnalyze => 'Organise this photo';

  @override
  String get handwritingQueueAnalyzing => 'Reading the photo...';

  @override
  String get handwritingQueueNotAnalyzed =>
      'This photo has not been organised yet.';

  @override
  String get handwritingQueueNothingFound =>
      'The model proposed nothing to organise: this page may have no tags, knowledge points or cards.';

  @override
  String get handwritingQueueFailureTitle => 'This run failed';

  @override
  String get handwritingQueueForget => 'Discard result';

  @override
  String get handwritingQueueProposalsLabel => 'Proposals to confirm';

  @override
  String get handwritingQueueApplyAll => 'Confirm all';

  @override
  String get handwritingQueueApplying => 'Writing...';

  @override
  String handwritingQueueReportSummary(int applied, int failed) {
    return 'This confirmation: $applied succeeded, $failed failed';
  }

  @override
  String get handwritingProposalApply => 'Confirm';

  @override
  String get handwritingProposalApplied => 'Confirmed';

  @override
  String handwritingProposalConfidence(String band) {
    return 'Model confidence: $band';
  }

  @override
  String get handwritingProposalConfidenceHigh => 'fairly sure';

  @override
  String get handwritingProposalConfidenceMedium => 'unsure';

  @override
  String get handwritingProposalConfidenceLow => 'not sure';

  @override
  String handwritingProposalCardCount(int count) {
    return '$count card(s)';
  }

  @override
  String get questionPaperDifficultyLabel => 'Target difficulty';

  @override
  String get questionPaperDifficultyAny => 'Any difficulty';

  @override
  String questionPaperDifficultyOption(String value) {
    return 'Difficulty $value';
  }

  @override
  String get questionPaperDifficultyHint =>
      'Difficulty is a preference, not a hard filter: closer questions rank higher, and questions with no difficulty value are treated as half-fit (ranked lower, never excluded).';

  @override
  String get questionPaperCapLabel => 'Per knowledge point cap';

  @override
  String get questionPaperCapAuto => 'Auto';

  @override
  String questionPaperCapOption(int cap) {
    return 'Up to $cap';
  }

  @override
  String get questionPaperReset => 'Reset paper settings';

  @override
  String get questionPaperCopy => 'Copy paper';

  @override
  String get questionPaperCopyDone =>
      'Paper copied — paste it into Word or a print preview.';

  @override
  String get questionPaperCopyReasonLabel => 'Reason';

  @override
  String get questionPaperCopyImprovementLabel => 'Improvement';

  @override
  String get questionPaperCopyBackgroundLabel => 'Background';

  @override
  String get questionPaperCopyUncoveredHeading =>
      'Knowledge points with no candidates';

  @override
  String get questionPaperCopyDeferredHeading =>
      'Knowledge points blocked by the cap';

  @override
  String get tasksDueAtConflictTitle =>
      'That time clashes with a schedule block';

  @override
  String tasksDueAtConflictBody(String title, String range) {
    return '\"$title\" $range is a busy block, so it cannot be scheduled there.';
  }

  @override
  String tasksDueAtConflictMoveBefore(String moment) {
    return 'Move before it ($moment)';
  }

  @override
  String tasksDueAtConflictMoveAfter(String moment) {
    return 'Move after it ($moment)';
  }

  @override
  String get tasksDueAtConflictKeep => 'Keep it as is';

  @override
  String get tasksDueAtConflictNoFreeMoment => 'No free slot in that direction';
}
