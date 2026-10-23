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
  String get navQuestions => 'Questions';

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
  String get commonMove => 'Move';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsLanguageZh => '中文';

  @override
  String get settingsLanguageEn => 'English';

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
  String get ankiCardGroup => 'Card group (tag)';

  @override
  String get ankiCardGroupNone => 'No group (loose card)';

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
  String reviewPlanUngroupedTitle(int count) {
    return '$count cards are in no card group';
  }

  @override
  String get reviewPlanUngroupedBody =>
      'A card group is a tag, and daily targets are set per group, so a card with no tag falls outside every target - the plan cannot see it. Give them a group once and you can set that group\'s daily amount right away.';

  @override
  String get reviewPlanUngroupedAction => 'Put them in one group';

  @override
  String reviewPlanUngroupedDone(int count, String tag) {
    return 'Moved $count cards into \"$tag\"';
  }

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
  String get todayStudyPlanTitle => 'What to do today';

  @override
  String get todayStudyPlanLoading => 'Building today\'s plan…';

  @override
  String todayStudyPlanTotal(int minutes) {
    return 'About $minutes min in total';
  }

  @override
  String todayStudyPlanSkipped(int count) {
    return '$count step(s) skipped';
  }

  @override
  String todayStudyPlanStepMinutes(int minutes) {
    return 'About $minutes min';
  }

  @override
  String todayStudyPlanFailed(String error) {
    return 'Could not read today\'s plan: $error';
  }

  @override
  String get todayStudyPlanRetry => 'Retry';

  @override
  String get todayStudyPlanGoPractice => 'Practice in the question bank';

  @override
  String get todayStudyPlanGoReview => 'Review due cards';

  @override
  String get todayStudyPlanGoChains => 'Open the question bank';

  @override
  String get todayStudyPlanGoVocabulary => 'Open the vocabulary';

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
  String get materialIntakePasteRun => 'Paste a run/1';

  @override
  String get materialIntakeRunDialogTitle =>
      'Paste a run/1: check it, then dry-run it';

  @override
  String get materialIntakeRunHint => 'Paste a mindnet.run/1 request here';

  @override
  String get materialIntakeRunCheck => 'Check this request';

  @override
  String get materialIntakeRunNote =>
      'Checked and dry-run only, nothing is written; a valid request gets the dry run button. The photo path and this one look at the same checks.';

  @override
  String materialIntakeRunGraphFailed(String message) {
    return 'Could not read the graph inventory: $message (it says which ids already exist)';
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
  String get materialPhotoReportPickAnother => 'Pick another';

  @override
  String get materialPhotoReportRetry => 'Try again';

  @override
  String get materialPhotoReportRehearse => 'Run it once (writes nothing)';

  @override
  String get materialPhotoReportEditAndRun => 'Edit it and run it';

  @override
  String get materialIntakeRunDialogTitleEdited =>
      'Edit it and run it (the same run/1)';

  @override
  String get materialPhotoReportRehearseBusy => 'Running it through…';

  @override
  String get materialPhotoReportRehearseFailed => 'The dry run stopped';

  @override
  String get materialPhotoReportRehearseHeader =>
      'Dry run (run only, nothing written)';

  @override
  String get materialPhotoReportRehearseNote =>
      'Read-only: no knowledge points, no edges and no review records are touched. Actually applying this request is a different step.';

  @override
  String get materialPhotoReportRehearseTrails => 'Where each action landed';

  @override
  String materialPhotoReportRehearseNoMs(String ids) {
    return 'No model reading for these nodes (the engine assumes the 0.8 default): $ids';
  }

  @override
  String materialPhotoReportRehearseUnknown(String ids) {
    return 'These node ids are not in the library and no action creates them: $ids';
  }

  @override
  String get materialPhotoReportHandOver =>
      'Hand the new things over for confirmation (list only)';

  @override
  String get materialPhotoReportHandOverBusy => 'Recording…';

  @override
  String get materialPhotoReportHandOverNote =>
      'This step writes exactly two list tables (`material_intake_batches` / `material_intake_proposals`): `knowledge_points` / `knowledge_edges` are not touched — they are only really created when you confirm them in the pending list right below on this page. Pressing it again for the same run yields the same batch.';

  @override
  String materialPhotoReportHandOverDone(String batchId) {
    return 'Recorded as a pending batch ($batchId) — it is right below on this page.';
  }

  @override
  String materialPhotoReportHandOverOpen(int count) {
    return 'Go see that batch ($count waiting)';
  }

  @override
  String materialPhotoReportHandOverFailed(String message) {
    return 'Could not record it: $message';
  }

  @override
  String get materialIntakeRunDetailLink => 'What that run actually did';

  @override
  String get materialIntakeRunDetailTitle =>
      'What that run actually did (read only)';

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
  String materialIntakeUndoLogLine(int count) {
    return 'This batch has been undone $count time(s) before.';
  }

  @override
  String get materialIntakeUndoLogTitle => 'Undo log';

  @override
  String get materialIntakeUndoLogNote =>
      'Every undo attempt leaves an entry: what it deleted, or why it did not (nothing in the library changed).';

  @override
  String get materialIntakeUndoLogDone => 'Undone';

  @override
  String get materialIntakeUndoLogNotDone => 'Not undone';

  @override
  String materialIntakeUndoLogBlocked(String reason, int count) {
    return 'Reason: $reason ($count reason(s) at the time)';
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
  String get materialIntakeRename => 'Edit this one';

  @override
  String get materialIntakeRenameDialogTitle =>
      'Edit this one (not confirmed yet)';

  @override
  String get materialIntakeRenameField => 'Title';

  @override
  String get materialIntakeRenameSave => 'Save it';

  @override
  String get materialIntakeEditBody => 'Body';

  @override
  String get materialIntakeEditBodyHint =>
      'e.g. the meaning, an example sentence, the original text - fill in what the machine missed';

  @override
  String materialIntakeProposalBody(String body) {
    return 'Body: $body';
  }

  @override
  String materialIntakeCantLand(String reason) {
    return 'cannot land yet: $reason (get that end into the graph first)';
  }

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
      '0 new cards per day means no new cards today; 0 or empty reviews per day means no review limit. A card answered wrong today still comes back.';

  @override
  String reviewPlanTarget(int newCards, int reviewCards) {
    return 'Target: $newCards new · $reviewCards reviews';
  }

  @override
  String reviewPlanDoneToday(int count) {
    return 'Done today: $count';
  }

  @override
  String reviewPlanNewRemaining(int count) {
    return 'New cards left: $count';
  }

  @override
  String reviewPlanRemaining(int count) {
    return 'Remaining allowance: $count';
  }

  @override
  String get reviewPlanReviewsUnlimited => 'Remaining allowance: no limit';

  @override
  String get reviewPlanNewCardsNormal => 'Today\'s allowance is still open.';

  @override
  String get reviewPlanNewCardsStopped =>
      'New-card allowance used up: no more new cards from this group today.';

  @override
  String get reviewPlanReviewsStopped =>
      'Review allowance used up: that is today\'s reviews, come back tomorrow.';

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
  String get tagsSelectMode => 'Select';

  @override
  String tagsSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get tagsSelectAll => 'Select all';

  @override
  String get tagsClearSelection => 'Clear selection';

  @override
  String get tagsBatchDelete => 'Delete selected';

  @override
  String get tagsBatchMove => 'Move selected';

  @override
  String tagsBatchDeleteTitle(int count) {
    return 'Delete $count tags?';
  }

  @override
  String tagsBatchDeletePreview(String names, int count) {
    return '$names ($count total)';
  }

  @override
  String get tagsMoveDialogTitle => 'Move to';

  @override
  String get tagsMoveToRoot => 'Top level';

  @override
  String get tagsSort => 'Sort';

  @override
  String get tagsBatchBusy => 'Working…';

  @override
  String tagsBatchResultDone(String action, int count) {
    return '$action $count tags';
  }

  @override
  String tagsBatchResultMixed(int success, int failed, String errors) {
    return '$success succeeded, $failed failed: $errors';
  }

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
  String get threadEnergy3 => 'Low · light tasks';

  @override
  String get threadEnergy5 => 'Medium · routine work';

  @override
  String get threadEnergy7 => 'High · needs focus';

  @override
  String get threadEnergy9 => 'Very high · deep push';

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
  String get propAlgorithm => 'Ranking parameters';

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
  String get propResetWeights => 'Restore default weights';

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
  String get knowledgeMoreActions => 'More';

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
  String get settingsCardGroups => 'Deck settings';

  @override
  String get settingsCardGroupsHint =>
      'A deck is a tag: give a tag a daily new/review cap and its whole subtree counts as that deck; grading mode and card type are changed here too.';

  @override
  String get reviewReminderSettingTitle => 'Review reminder';

  @override
  String get reviewReminderSettingOff => 'Off';

  @override
  String reviewReminderSettingOn(String time) {
    return 'Every day at $time when cards are due';
  }

  @override
  String get reviewReminderDialogTitle => 'Review reminder';

  @override
  String get reviewReminderDialogBody =>
      'At that time, if cards are still due, a system notification reminds you once. It fires even when the app is closed; it will not appear if notifications are not allowed.';

  @override
  String get reviewReminderToggleTitle => 'Enable review reminder';

  @override
  String get reviewReminderToggleHint =>
      'Only reminds you about due cards; it does not change the review plan.';

  @override
  String get reviewReminderTimeLabel => 'Reminder time';

  @override
  String get reviewReminderNotificationTitle => 'Furnace review reminder';

  @override
  String reviewReminderNotificationDueBody(int count) {
    return '$count card(s) are due; a few minutes of review will clear them.';
  }

  @override
  String get reviewReminderNotificationSoonBody =>
      'Some cards are due for review.';

  @override
  String get reviewReminderPermissionDenied =>
      'Notifications are not allowed, so this reminder will not appear.';

  @override
  String get settingsQuestionBankHint =>
      'Question overview, intake, paper assembly, photo cleanup and material intake all start here.';

  @override
  String get settingsUsageDoc => 'Usage guide';

  @override
  String get settingsUsageDocHint =>
      'How each part works and what its limits are: AI, review, knowledge base, question bank, photos/materials, cognitive model, ranking';

  @override
  String get docAiTitle =>
      'What the assistant can do, and what waits for your consent';

  @override
  String get docAiBody =>
      'The AI can only change data through tools, and every tool carries a risk level: read-only calls (query_tasks, query_schedule, query_content, fetch_page, evaluate_problem_fit, compose_paper, find_similar_questions, find_questions_by_capability, plan_today, review_metrics and friends) run immediately; writes (creating tags, flashcards, tasks, documents, material intake, applying today\'s plan...) wait for your consent in both the per-action and the plan-first modes; deletions ask every single time and can be undone. You see what a call will change before it runs and get one undo after it; the model never sees your API key, and skill scripts do not receive it either.';

  @override
  String get docReviewTitle => 'Review and flashcards';

  @override
  String get docReviewBody =>
      'Flashcards hang off tags, and the tag tree is the deck: a daily new/review cap set on one tag covers its whole subtree (no row at all means no cap). Due dates come from FSRS alone - the cognitive model only changes what today\'s queue puts first. Grading can be strict, lenient or self-assessed; lenient ignores typos and word order, and a card you got wrong ignores the daily cap and comes back the same day. Deck settings live in Settings -> Deck settings (also reachable from the review screen\'s app bar). Cards with no tag belong to no group, so no daily target can reach them: the deck settings screen shows how many such cards exist and offers a one-tap \"put them all in one group\" fix, and the new-flashcard dialog can take a group up front.';

  @override
  String get docKnowledgeTitle => 'Knowledge base and tags';

  @override
  String get docKnowledgeBody =>
      'Tags form a tree, with / separating the levels. Deleting a tag also deletes its whole subtree together with the flashcards and review history inside it (the AI\'s delete tool asks for each one and leaves an undoable snapshot). Both card shapes - cards generated from a template and cards created directly per unit - count on the cognitive readings page, and the orphan banner there cleans up only when you press its button.';

  @override
  String get docBankTitle => 'Question bank and paper assembly';

  @override
  String get docBankBody =>
      'The intake page turns pasted text or picked images into drafts for proofreading: the AI only structures them, and nothing is written until you press save, while an identical question (same stem fingerprint) points at the existing row instead of duplicating it. The paper page assembles a paper only from questions you already have (at-risk and developing points first); when it cannot fill the paper it lists the missing knowledge points honestly - the AI never writes questions. The paper can be copied out as printable plain text. On the cognitive model page the capability-move profile opens a read-only list of questions whose chains used a move.';

  @override
  String get docMaterialTitle => 'Photos, materials and rehearsal';

  @override
  String get docMaterialBody =>
      'Photo intake turns one photo into four kinds of proposals - extra tags, flashcards, MindNet knowledge-point nodes and questions transcribed verbatim - and writes nothing before you confirm; material intake turns a piece of material into knowledge points / cards / connections, again only writing after you confirm, with an undo trail. A photo can also become a run/1 request carrying mechanism parameters: the mechanism panel lets you try or rehearse it, and a rehearsal only reports readings without touching your data. Saying \"do not install the goal mechanism\" really leaves it out.';

  @override
  String get docTodayTitle => 'What to do today, and when';

  @override
  String get docTodayBody =>
      'Today\'s list shows the cards due today; the rhythm layer reports alpha(tau) attention availability; conflicting tasks and schedule blocks are flagged and can be pushed back with one tap; the cognitive ranking tier only changes which card comes first, never due dates, and is recomputed only when you press the sort button. Counterfactual V(pi) and the retention probe likewise only affect ordering.';

  @override
  String get docCognitiveTitle => 'How to read the cognitive model';

  @override
  String get docCognitiveBody =>
      'Cognitive model in settings is a read-only readings page: R is current memory strength, R0 is the strength right after learning, Sigma is accumulated effort, and the developing-zone / dead-end column is the tierB diffusion verdict on the tag graph (starts are the most recently reviewed points, targets are the ones due today); with no tags or no usable start and target it reads unavailable, which is not the same as healthy. \"Danger\" comes from the metacognition rows: it appears only when your self-rated confidence and your actual recall differ enough, and a missing verdict is not the same as healthy. The capability-move profile groups stuck risk by the moves on solved chains and answers which kind of move to practise; tapping a row lists the questions whose chains used it (read-only). At the top of the readings page there is a read-only knowledge-network view that draws knowledge points and tags as one graph (colour = cognitive zone, size = card count); tap a node to read it. The statements at the top record that it does not move due dates, that its parameters are uncalibrated and that it does not decide for you. The AI\'s evaluate_problem_fit tool reads the same numbers to judge whether a question is worth doing now.';

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
  String get settingsQuestionPackSection => 'Question bank package (.tqb)';

  @override
  String get settingsQuestionPackExport => 'Export question bank package';

  @override
  String get settingsQuestionPackExportHint =>
      'Questions and images only; no other workspace data';

  @override
  String settingsQuestionPackExportDone(int questions, int media, String size) {
    return 'Exported $questions question(s) and $media image(s) ($size)';
  }

  @override
  String get settingsQuestionPackExportEmpty =>
      'There are no questions to export yet';

  @override
  String get settingsQuestionPackImport => 'Import question bank package';

  @override
  String get settingsQuestionPackImportHint =>
      'Only adds questions; never overwrites the existing bank';

  @override
  String settingsQuestionPackImportPreview(int questions, int media) {
    return 'This package contains $questions question(s) and $media image(s)';
  }

  @override
  String get settingsQuestionPackImportConfirm =>
      'Newly added questions never overwrite existing ones; identical stems (by fingerprint) are skipped';

  @override
  String settingsQuestionPackImportDone(int created, int skipped, int media) {
    return 'Import finished: $created created, $skipped skipped, $media image(s) written';
  }

  @override
  String settingsQuestionPackPreviewUpdate(int count) {
    return 'Will update $count existing question(s) from zujuan.com (serial number and your title are kept)';
  }

  @override
  String settingsQuestionPackImportUpdated(int count) {
    return 'Updated $count existing question(s)';
  }

  @override
  String get settingsQuestionPackImportUpdateNote =>
      'Updating overwrites the stem, answer, solution and images carried by the package; serial numbers, your titles, and any images or tags not in the package are kept';

  @override
  String settingsQuestionPackWarnings(int count) {
    return 'Warnings: $count (for example, missing tags were skipped)';
  }

  @override
  String settingsQuestionPackFailures(int count) {
    return '$count question(s) failed to import; the rest were written';
  }

  @override
  String get settingsQuestionPackInvalid => 'This is not a valid .tqb file';

  @override
  String get settingsQuestionPackFilterTitle => 'Export scope';

  @override
  String get settingsQuestionPackFilterSubjects => 'Subjects';

  @override
  String get settingsQuestionPackFilterSources => 'Source tiers';

  @override
  String get settingsQuestionPackFilterSerialRange => 'Serial number range';

  @override
  String get settingsQuestionPackFilterSerialHint => 'Leave blank for no limit';

  @override
  String get settingsQuestionPackFilterSerialFrom => 'Start serial';

  @override
  String get settingsQuestionPackFilterSerialTo => 'End serial';

  @override
  String get settingsQuestionPackFilterSerialInvalid =>
      'Serial numbers can only contain digits';

  @override
  String get settingsQuestionPackFilterSerialReversed =>
      'The start serial cannot be greater than the end serial';

  @override
  String get settingsQuestionPackFilterExport => 'Export';

  @override
  String get settingsQuestionPackFilterEmpty =>
      'No questions match these filters; try widening them';

  @override
  String get settingsQuestionPackExportWarningsTitle => 'Export warnings';

  @override
  String settingsQuestionPackPreviewCreate(int count) {
    return 'Will create $count question(s)';
  }

  @override
  String settingsQuestionPackPreviewSkip(int count) {
    return 'Skip $count (already in the bank, or duplicated in the package)';
  }

  @override
  String settingsQuestionPackPreviewMissingTags(int count) {
    return 'Missing $count tag(s); those questions will import without them';
  }

  @override
  String get settingsQuestionPackPreviewNoNew =>
      'The package has no new questions to import';

  @override
  String get settingsQuestionPackFilterTags => 'Tag paths';

  @override
  String get settingsQuestionPackFilterTagSelect => 'Select tag paths';

  @override
  String settingsQuestionPackFilterTagsSelected(int count) {
    return 'Tag paths: $count selected';
  }

  @override
  String get settingsQuestionPackTagPickerTitle => 'Filter by tag path';

  @override
  String get settingsQuestionPackTagPickerSearch => 'Search tag paths';

  @override
  String get settingsQuestionPackTagPickerEmpty =>
      'No tags yet. Create one on the Tags page first.';

  @override
  String get settingsQuestionPackTagPickerNoMatch => 'No matching tag paths';

  @override
  String settingsQuestionPackTagQuestionCount(int count) {
    return '$count question(s)';
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
  String get cognitiveGraphTitle => 'Knowledge network (read-only)';

  @override
  String get cognitiveGraphHint =>
      'Dots are knowledge points (colour = cognitive zone, size = card count), squares are tags, and a line means the point hangs off that tag. Nothing here is editable: no due dates and no ordering change.';

  @override
  String get cognitiveGraphEmpty =>
      'Nothing to draw yet: create knowledge points and tags, then review a few cards.';

  @override
  String cognitiveGraphSummary(int points, int tags, int links) {
    return '$points knowledge points · $tags tags · $links links';
  }

  @override
  String cognitiveGraphPointDetail(String zone, int cards, String mean) {
    return 'Zone: $zone · $cards cards · mean R $mean';
  }

  @override
  String cognitiveGraphTagDetail(int count) {
    return '$count knowledge points hang off this tag';
  }

  @override
  String get cognitiveGraphTapHint =>
      'Tap a dot or a square to read it (read-only).';

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
  String get mechanismPanelTitle => 'Mechanisms and parameters';

  @override
  String get mechanismPanelSubtitle =>
      'Which mechanisms the engines install, what each parameter is, and which values are not calibrated';

  @override
  String get mechanismPanelReadOnlyNote =>
      'This panel writes exactly two settings (the switch and the slider below) and nothing else; the setups and parameters shown are the ones the engines actually run with';

  @override
  String get mechanismSwitchGoalTitle =>
      'Install the goal mechanism (context.goal)';

  @override
  String get mechanismSwitchGoalBody =>
      'When off, the library-diagnosis run no longer installs it, so the diffusion has no starts/targets to pull towards and its readings change. The problem-pricing run still installs it (that path prices starts/targets). Never chosen = installed.';

  @override
  String get mechanismGoalBetaTitle =>
      'Goal bias strength (context.goal.beta_goal)';

  @override
  String get mechanismGoalBetaBody =>
      'How hard the goal pulls the diffusion towards starts/targets: 0 = no pull at all, and the shipped value is the transcribed default written below (an uncalibrated placeholder). It changes this one number and nothing about what is installed.';

  @override
  String get mechanismGoalBetaShipped => 'shipped value';

  @override
  String get mechanismGoalBetaFromSetting => 'yours';

  @override
  String get mechanismGoalBetaReset => 'Back to the shipped value';

  @override
  String get mechanismGoalBetaApplies =>
      'Every run that installs the goal mechanism reads this number: the library-diagnosis run (the reading above on this page) and the problem-pricing run (the V(π) ordering behind evaluate_problem_fit / plan_today). The tools\' module_defaults carries exactly it - empty when you have never tuned it (the shipped value untouched).';

  @override
  String get mechanismGoalBetaOffNote =>
      'The goal mechanism is not installed (the switch above is off), so the runs that would install it do not use this value; the number stays for when you turn it back on.';

  @override
  String get mechanismDisabledBySetting =>
      'you turned it off (it ships installed)';

  @override
  String get mechanismPanelSetupsHeader => 'The three engine setups';

  @override
  String mechanismPanelSetupCount(int count) {
    return '$count mechanism(s) installed';
  }

  @override
  String get mechanismPanelOverridesHeader =>
      'Overrides (not the transcribed defaults):';

  @override
  String get mechanismPanelNoOverrides =>
      'No overrides: every value is the transcribed default';

  @override
  String get mechanismPanelMechanismsHeader => 'Mechanisms';

  @override
  String get mechanismPanelInstalledIn => 'Installed in: ';

  @override
  String get mechanismPanelOnlyOutside =>
      'Only inside the rhythm reading - not installed into an engine';

  @override
  String get mechanismPanelNoParams =>
      'This layer declares no numeric parameters: it keeps a per-node state bag only';

  @override
  String get mechanismPanelUncalibrated => 'NOT CALIBRATED';

  @override
  String get mechanismPanelCalibrated => 'calibrated';

  @override
  String get mechanismPanelOverridden => 'overridden';

  @override
  String get mechanismPanelTranscribed => 'transcribed default';

  @override
  String get mechanismPanelRange => 'range';

  @override
  String mechanismPanelSummary(int params, int uncalibrated) {
    return '$params parameters, $uncalibrated of them not calibrated';
  }

  @override
  String get mechanismPanelNameSeparator => ', ';

  @override
  String get mechanismPanelOpen => 'Mechanisms and parameters';

  @override
  String get mechanismNameShunting => 'Shunting inhibition';

  @override
  String get mechanismNameCapacity => 'Attention capacity';

  @override
  String get mechanismNameIgnition => 'Ignition threshold';

  @override
  String get mechanismNameGoal => 'Goal context';

  @override
  String get mechanismNameRhythm => 'Rhythm gate';

  @override
  String get mechanismNameMemory => 'DSR memory layer';

  @override
  String get mechanismSetupLibraryDiagnosis => 'The library-diagnosis run';

  @override
  String get mechanismSetupProblemEvaluator => 'The problem-pricing run';

  @override
  String get mechanismSetupRunRehearsal => 'The transcript-request rehearsal';

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
  String get capabilityProfileTitle => 'Capability moves (from solved chains)';

  @override
  String get capabilityProfileDetail =>
      'Aggregated per step\'s stuck risk; steps with no risk reading are only counted, never averaged in.';

  @override
  String get capabilityProfileUnavailable =>
      'The profile could not be read (database read failed).';

  @override
  String get capabilityProfileEmpty =>
      'No reasoning chains yet: solve a question once from its detail page and there will be something to aggregate.';

  @override
  String capabilityProfileRow(
      String action, int steps, int risky, String risk) {
    return '$action: $steps steps, $risky high-risk, average risk $risk';
  }

  @override
  String get capabilityProfileNoRisk => 'no risk reading (no judgement given)';

  @override
  String get capabilityProfileUnknownNote =>
      'Unknown moves are shown verbatim - that is not \"fine\", it means the vocabulary does not know it yet.';

  @override
  String capabilityActionQuestionsTitle(String label) {
    return 'Questions by capability move: $label';
  }

  @override
  String get capabilityActionQuestionsNote =>
      'These are the questions whose latest solved chain used this move; questions without a chain cannot appear here.';

  @override
  String capabilityActionQuestionsEmpty(String label) {
    return 'No solved question uses \"$label\" yet - solve one from its detail page first.';
  }

  @override
  String get capabilityActionQuestionsAllSubjects => 'All subjects';

  @override
  String get capabilityActionQuestionsSecondAction =>
      'Add a second move (optional)';

  @override
  String get capabilityActionQuestionsSecondActionNone => 'None';

  @override
  String get capabilityActionQuestionsRequireAll =>
      'Both moves must appear on the same chain';

  @override
  String capabilityActionQuestionsMeta(
      String subject, String source, String actions) {
    return '$subject · $source · moves on the chain: $actions';
  }

  @override
  String capabilityActionQuestionsFailed(String message) {
    return 'Could not read the question bank: $message';
  }

  @override
  String get capabilityVocabularyTitle => 'Capability vocabulary';

  @override
  String get capabilityVocabularyHint =>
      'The vocabulary names the move a student is stuck on. Built-in moves are read-only because their keys already live in saved data. Custom entries stay on this page until you tap Save; saved entries take effect from the next solve.';

  @override
  String capabilityVocabularyBuiltInSection(int count) {
    return 'Built-in moves (read-only, $count)';
  }

  @override
  String get capabilityVocabularyBuiltInNote =>
      'Built-in moves are defined in code; changing one means shipping a new build. This list is read-only.';

  @override
  String capabilityVocabularyCustomSection(int count) {
    return 'Custom moves ($count)';
  }

  @override
  String get capabilityVocabularyCustomEmpty =>
      'No custom moves yet. Use Add move, or paste JSON to import below.';

  @override
  String get capabilityVocabularyAdd => 'Add move';

  @override
  String get capabilityVocabularyEditTitle => 'Edit move';

  @override
  String get capabilityVocabularyKeyLabel => 'key (stable id)';

  @override
  String get capabilityVocabularyKeyHint =>
      'Lower snake case, for example force_diagram_analysis; cannot change after saving.';

  @override
  String get capabilityVocabularyLabelZh => 'Chinese name';

  @override
  String get capabilityVocabularyLabelEn => 'English name (optional)';

  @override
  String get capabilityVocabularyDescriptionZh =>
      'One-line description (optional)';

  @override
  String get capabilityVocabularySubjectHints => 'Subjects where it appears';

  @override
  String get capabilityVocabularyMoveUp => 'Move up';

  @override
  String get capabilityVocabularyMoveDown => 'Move down';

  @override
  String get capabilityVocabularyImport => 'Paste JSON to import';

  @override
  String get capabilityVocabularyImportTitle => 'Paste vocabulary JSON';

  @override
  String get capabilityVocabularyImportHint =>
      'Accepts a customActions list, or a plain array of custom moves';

  @override
  String capabilityVocabularyImportInvalidJson(String message) {
    return 'Could not parse the JSON: $message';
  }

  @override
  String capabilityVocabularyImportDone(int count) {
    return 'Imported $count move(s) (not saved yet)';
  }

  @override
  String get capabilityVocabularyRevert => 'Discard changes';

  @override
  String get capabilityVocabularySaved =>
      'Saved. The next solve uses the new vocabulary.';

  @override
  String capabilityVocabularySaveFailed(String message) {
    return 'Could not save: $message';
  }

  @override
  String get capabilityVocabularyDirty => 'Unsaved changes';

  @override
  String capabilityVocabularyIssuesTitle(int count) {
    return '$count operation(s) were rejected';
  }

  @override
  String get capabilityVocabularyIssueDismiss => 'Got it';

  @override
  String capabilityVocabularyLoadFailed(String message) {
    return 'Could not read the vocabulary: $message';
  }

  @override
  String get capabilityVocabularyLeaveTitle => 'Unsaved changes';

  @override
  String get capabilityVocabularyLeaveBody =>
      'Leaving will discard these changes.';

  @override
  String get capabilityVocabularyLeaveStay => 'Keep editing';

  @override
  String get capabilityVocabularyLeaveDiscard => 'Discard and leave';

  @override
  String get capabilityVocabularySettingsTitle => 'Capability vocabulary';

  @override
  String get capabilityVocabularySettingsHint =>
      'Add capability moves the built-in vocabulary does not have. Saved entries take effect on the next solve.';

  @override
  String get learningInsightTitle => 'Learning insights';

  @override
  String get learningInsightRefresh => 'Refresh';

  @override
  String learningInsightLoadFailed(String message) {
    return 'Could not load learning insights: $message';
  }

  @override
  String get learningInsightRetry => 'Retry';

  @override
  String get learningInsightOverlayFallback =>
      'Could not read the custom capability vocabulary; showing the built-in vocabulary.';

  @override
  String get learningInsightEmptyTitle => 'No solution chains yet';

  @override
  String get learningInsightEmptyBody =>
      'Run AI solve on a few question detail pages first; insights appear once chains exist.';

  @override
  String learningInsightSummary(int chains, int steps, int questions) {
    return '$chains chains · $steps steps · $questions questions';
  }

  @override
  String get learningInsightAdviceSection => 'What to do next';

  @override
  String get learningInsightAdviceEmpty => 'No actionable advice right now';

  @override
  String learningInsightAdviceAction(String label) {
    return 'Action: $label';
  }

  @override
  String learningInsightAdviceQuestions(int count) {
    return '$count questions';
  }

  @override
  String learningInsightAdviceSteps(int count) {
    return '$count steps';
  }

  @override
  String learningInsightAdviceHighRisk(int count) {
    return '$count high-risk steps';
  }

  @override
  String get learningInsightActionSection => 'Capability action breakdown';

  @override
  String get learningInsightActionEmpty => 'No action readings yet';

  @override
  String get learningInsightActionBuiltIn => 'Built-in';

  @override
  String get learningInsightActionCustom => 'Custom';

  @override
  String get learningInsightActionUnknown => 'Unknown';

  @override
  String learningInsightActionCounts(int steps, int questions, int highRisk) {
    return '$steps steps · $questions questions · $highRisk high-risk';
  }

  @override
  String learningInsightRiskAverage(String percent) {
    return 'Average risk $percent';
  }

  @override
  String get learningInsightRiskUnread => 'Average risk: no readings';

  @override
  String learningInsightLastSeen(String time) {
    return 'Last seen $time';
  }

  @override
  String learningInsightUnknownSection(int count) {
    return 'Actions outside the vocabulary ($count)';
  }

  @override
  String get learningInsightUnknownHint =>
      'These actions are not in the vocabulary yet; consider adding them.';

  @override
  String get learningInsightOpenVocabulary => 'Open vocabulary';

  @override
  String get learningInsightNeverUsedSection => 'Vocabulary actions never seen';

  @override
  String get learningInsightNeverUsedHint =>
      'No samples for these actions yet; that does not mean they should not be used.';

  @override
  String get learningInsightStuckSection => 'Stuck hotspots (knowledge points)';

  @override
  String learningInsightStuckCounts(
      int highRiskSteps, int questions, int chains) {
    return '$highRiskSteps high-risk steps · $questions questions · $chains chains';
  }

  @override
  String get learningInsightCrossSection =>
      'Action × knowledge point stuck points';

  @override
  String get learningInsightSettingsTitle => 'Learning insights';

  @override
  String get learningInsightSettingsHint =>
      'Review capability actions and stuck points in solution chains, and what to practice next';

  @override
  String get practiceRecommendationTitle => 'What to practice next';

  @override
  String get practiceRecommendationEmpty =>
      'No recommendations yet: collect a few questions and run AI solving, then check back.';

  @override
  String get practiceRecommendationFailed =>
      'Practice recommendations are unavailable right now.';

  @override
  String practiceRecommendationRank(int rank) {
    return 'Rank $rank';
  }

  @override
  String practiceRecommendationActions(String labels) {
    return 'Matched actions: $labels';
  }

  @override
  String practiceRecommendationMoreReasons(int count) {
    return '$count more reason(s)';
  }

  @override
  String practiceRecommendationSkipped(int count) {
    return '$count more question(s) not shown';
  }

  @override
  String get practiceRecommendationReasonMatchedAdviceAction =>
      'Matches a practice action from your learning advice';

  @override
  String get practiceRecommendationReasonMatchedHighRiskKnowledgePoint =>
      'Covers a stuck knowledge point';

  @override
  String get practiceRecommendationReasonUnknownActionScaffold =>
      'Uses an action outside the vocabulary; build the basics first';

  @override
  String get practiceRecommendationReasonUpToDate =>
      'Answer and solution are complete';

  @override
  String get practiceRecommendationReasonMissingSolution => 'Missing solution';

  @override
  String get practiceRecommendationReasonMissingAnswer => 'Missing answer';

  @override
  String get practiceRecommendationReasonTooHard => 'Harder than target';

  @override
  String get practiceRecommendationReasonTooEasy => 'Easier than target';

  @override
  String get practiceRecommendationReasonUnrelated =>
      'Little relation to current advice';

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
  String get questionBankRefresh => 'Refresh the question bank';

  @override
  String questionBankFailed(String message) {
    return 'Could not read the question bank: $message';
  }

  @override
  String get questionBankEmpty => 'The question bank is empty';

  @override
  String get questionBankEmptyHint =>
      'Questions come from three places: intake (paste or pick a file), photo cleanup, and material intake. The AI never writes questions for you.';

  @override
  String get questionBankIntro =>
      'The four buttons above add material to the bank; the list below filters by subject - tap a row for its detail and solution chain.';

  @override
  String questionBankSummary(int questions, int subjects) {
    return '$questions questions · $subjects subjects';
  }

  @override
  String get questionBankAllSubjects => 'All subjects';

  @override
  String get questionBankNoMatch => 'No questions in this subject yet';

  @override
  String get questionBankUntitled => '(no stem)';

  @override
  String questionBankPointCount(int count) {
    return '$count knowledge points';
  }

  @override
  String get questionTitleUntitled => 'Untitled question';

  @override
  String get questionTitleDialogTitle => 'Name this question';

  @override
  String get questionTitleFieldLabel => 'Title';

  @override
  String get questionTitleFieldHint =>
      'A short name you can recognize at a glance';

  @override
  String get questionTitleEditTooltip => 'Edit title';

  @override
  String get questionTitleRename => 'Rename';

  @override
  String get questionTitleAutoGenerate => 'Generate';

  @override
  String get questionTitleClear => 'Clear title';

  @override
  String get questionTitleAutoFilled =>
      'Generated from the stem - edit it if needed';

  @override
  String questionTitleInvalid(int maxLength) {
    return 'The title cannot contain line breaks or tabs, and is at most $maxLength characters';
  }

  @override
  String questionTitleSaveFailed(String error) {
    return 'Could not save the title: $error';
  }

  @override
  String get questionTitleSaved => 'Title saved';

  @override
  String get questionTitleCleared => 'Title cleared';

  @override
  String questionTitleAutoNamed(String title) {
    return 'Named automatically: $title';
  }

  @override
  String get questionBankCopySerial => 'Copy question number';

  @override
  String get questionBankRowMenuTooltip => 'More actions';

  @override
  String get questionBankAutoNameTooltip => 'Auto-name untitled questions';

  @override
  String get questionBankAutoNameMenu => 'Auto-name';

  @override
  String questionBankAutoNameDialogTitle(int count) {
    return 'Auto-name $count questions?';
  }

  @override
  String get questionBankAutoNameDialogBody =>
      'Builds short names from the stem and subject; existing titles are kept, and you can rename any of them afterwards.';

  @override
  String get questionBankAutoNameStart => 'Start naming';

  @override
  String questionBankAutoNameDone(int count) {
    return 'Named $count questions automatically';
  }

  @override
  String get questionBankAutoNameNothing => 'Nothing to name';

  @override
  String questionBankAutoNameFailed(String error) {
    return 'Auto-naming failed: $error';
  }

  @override
  String questionBankAutoNamePartial(int done, int failed) {
    return 'Named $done; $failed could not be saved';
  }

  @override
  String questionBankTruncated(int count) {
    return 'Showing the latest $count; use search for more';
  }

  @override
  String get questionBankSelect => 'Select multiple';

  @override
  String questionBankSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get questionBankSelectAll => 'Select all';

  @override
  String get questionBankClearSelection => 'Clear selection';

  @override
  String get questionBankTagSelected => 'Add tags';

  @override
  String get questionBankExportSelected => 'Export selected';

  @override
  String get questionBankDeleteSelected => 'Delete';

  @override
  String questionBankDeleteTitle(int count) {
    return 'Delete $count questions?';
  }

  @override
  String questionBankDeleteBody(String preview) {
    return 'About to delete: $preview. This cannot be undone.';
  }

  @override
  String questionBankDeleteDone(int count) {
    return 'Deleted $count questions';
  }

  @override
  String questionBankDeleteFailed(int count) {
    return '$count could not be deleted';
  }

  @override
  String questionBankTagDone(int added, int skipped) {
    return 'Added $added links; skipped $skipped (already tagged)';
  }

  @override
  String questionBankTagMissing(int count) {
    return '$count tag paths no longer exist';
  }

  @override
  String questionBankExportDone(int count, String sizeText) {
    return 'Exported $count questions ($sizeText)';
  }

  @override
  String get questionBankExportEmpty =>
      'The selected questions are no longer in the bank';

  @override
  String questionBankExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String questionBankTagFailed(String error) {
    return 'Tagging failed: $error';
  }

  @override
  String get questionBulkTagDialogTitle => 'Tag selected questions';

  @override
  String get questionBulkTagSearchHint => 'Search tag paths';

  @override
  String get questionBulkTagNoMatch => 'No matching tags';

  @override
  String get questionBulkTagConfirm => 'Add tags';

  @override
  String get questionBankSearchHint =>
      'Search number, title, stem, source, or tags';

  @override
  String get questionBankTagFilterTitle => 'Filter by tags';

  @override
  String questionBankTagFilterSelected(int count) {
    return '$count tags selected';
  }

  @override
  String get questionBankFilterClear => 'Clear filters';

  @override
  String questionBankFilteredCount(int shown, int total) {
    return '$shown of $total questions';
  }

  @override
  String get questionBankFilterNoMatch => 'No questions match the filters';

  @override
  String get questionBankTagFilterClear => 'Clear tags';

  @override
  String get questionBankSnapshotBadge => 'Card image';

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
  String get questionIntakeTypeSingleChoice => 'Single choice';

  @override
  String get questionIntakeTypeMultiChoice => 'Multiple choice';

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
  String get questionIntakeDropHint =>
      'You can also drag photos here (WeChat chat images work too)';

  @override
  String get questionIntakeDropActive => 'Release to add the photos';

  @override
  String get questionIntakeDropBusy =>
      'Still importing the previous photos; try again in a moment';

  @override
  String questionIntakeDropSkippedNonImage(int count) {
    return 'Skipped $count non-image file(s)';
  }

  @override
  String questionIntakeDropDuplicates(int count) {
    return 'Ignored $count duplicate file(s)';
  }

  @override
  String questionIntakeDropUnreadable(int count) {
    return 'Could not read $count file(s)';
  }

  @override
  String get questionAuditSectionTitle => 'Intake audit';

  @override
  String get questionAuditClean => 'No hard issues found in this check';

  @override
  String get questionAuditReadOnly =>
      'The audit only reports; it never edits the question.';

  @override
  String get questionAuditEvidence => 'Evidence';

  @override
  String questionAuditBadgeTooltip(int errors, int warnings) {
    return 'Intake audit: $errors error(s), $warnings warning(s)';
  }

  @override
  String questionAuditGroupHeader(String label, int count) {
    return '$label · $count';
  }

  @override
  String get questionSerialUnnumbered => 'TR-unassigned';

  @override
  String get questionSerialCopyTooltip => 'Copy the question number';

  @override
  String questionSerialCopied(String label) {
    return 'Copied $label';
  }

  @override
  String get questionZujuanSearch => 'Search this question on Zujuan';

  @override
  String get questionZujuanCopyKeyword => 'Copy keyword';

  @override
  String questionZujuanCopied(String keyword) {
    return 'Keyword copied: $keyword';
  }

  @override
  String get questionZujuanNoCandidates =>
      'No usable search keyword in the stem';

  @override
  String get questionZujuanBankHint =>
      'Zujuan filters by your current subject. Switch to the matching subject on the site first, or searches may return nothing.';

  @override
  String get questionZujuanOpenUrl => 'Open search page';

  @override
  String get questionZujuanUrlCopied =>
      'Search page link copied: paste it in a browser to open';

  @override
  String get questionDetailImagesSection => 'Question images';

  @override
  String get questionDetailOriginalCardImage => 'Original question image';

  @override
  String questionImageCount(int count) {
    return '$count image(s)';
  }

  @override
  String get questionImageOpenTooltip => 'Open at full size';

  @override
  String get questionImageLoadFailed => 'This image could not be loaded';

  @override
  String get questionImageAdd => 'Add image';

  @override
  String questionImageAddDone(int count) {
    return 'Added $count image(s)';
  }

  @override
  String questionImageAddSkipped(int count) {
    return 'Skipped $count file(s) that were not usable images';
  }

  @override
  String questionImageAddFailed(String error) {
    return 'Could not add images: $error';
  }

  @override
  String get questionImageHeicUnsupported =>
      'HEIC images are not supported yet; convert them to JPG or PNG first';

  @override
  String get questionImageDeleteTooltip => 'Delete this image';

  @override
  String get questionImageDeleteTitle => 'Delete this image?';

  @override
  String get questionImageDeleteAction => 'Delete';

  @override
  String questionImageDeleteConfirm(String fileName) {
    return 'Removes \"$fileName\" from this question.';
  }

  @override
  String get questionImageDeleted => 'Image deleted';

  @override
  String questionImageDeleteFailed(String error) {
    return 'Could not delete the image: $error';
  }

  @override
  String get questionImageEmptyHint =>
      'No images yet; add a photo of the question (HEIC is not supported yet)';

  @override
  String get questionAnswerImageTitle => 'Answer & solution screenshots';

  @override
  String get questionAnswerImageAdd => 'Add answer screenshot';

  @override
  String get questionAnswerImageEmptyHint =>
      'No answer screenshots yet: sign in on Zujuan and save a screenshot of the answer/solution (HEIC is not supported yet)';

  @override
  String get questionAnswerImageDeleteTitle => 'Delete this screenshot?';

  @override
  String get questionAnswerImageDeleted => 'Screenshot deleted';

  @override
  String get questionIntakePhotoPending => 'Images waiting';

  @override
  String get questionIntakeNoPhotos =>
      'No photos yet. Picked images are stored locally until the AI turns them into tags, knowledge points, flashcards or questions.';

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
  String questionIntakeDeletedWithImages(String stem, int count) {
    return 'Deleted: $stem (removed $count image(s))';
  }

  @override
  String get questionIntakeDeleteConfirm =>
      'Delete this question? It will not come back from sync.';

  @override
  String get questionIntakeCancel => 'Cancel';

  @override
  String get questionIntakeSearchHint =>
      'Search stems or serial numbers (multiple: TR-00001, 2-5)';

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
  String get zujuanPickOpenButton => 'Find by filters';

  @override
  String get zujuanPickTitle => 'Find questions by filters';

  @override
  String get zujuanPickIntro =>
      'Pick filters and copy the link to open Zujuan in a browser; the app only builds the link and does not fetch pages.';

  @override
  String get zujuanPickSubject => 'Subject';

  @override
  String get zujuanPickKnowledgePoint => 'Knowledge point id';

  @override
  String get zujuanPickKnowledgePointHint =>
      'Leave empty for all knowledge points of the subject';

  @override
  String get zujuanPickDifficulty => 'Difficulty';

  @override
  String get zujuanPickAny => 'Any';

  @override
  String get zujuanPickYear => 'Year';

  @override
  String get zujuanPickYearEarlier => 'Earlier';

  @override
  String get zujuanPickProvince => 'Province';

  @override
  String get zujuanPickGrade => 'Grade';

  @override
  String get zujuanPickGradeSenior1 => 'Grade 10';

  @override
  String get zujuanPickGradeSenior2 => 'Grade 11';

  @override
  String get zujuanPickGradeSenior3 => 'Grade 12';

  @override
  String get zujuanPickSort => 'Sort';

  @override
  String get zujuanPickUrl => 'Search link';

  @override
  String get zujuanPickCopy => 'Copy link';

  @override
  String get zujuanPickCopied => 'Search link copied: paste it in a browser';

  @override
  String get zujuanPickNoScrapeHint =>
      'The app does not fetch Zujuan pages (the site blocks scraping). To see answers and solutions, sign in to Zujuan in your browser and view them there.';

  @override
  String get zujuanPickLoginHint =>
      'Answers and solutions are visible after signing in to Zujuan (free accounts see about 30 questions per day). Paste viewed stems, answers, and solutions back in with Paste Zujuan questions.';

  @override
  String get zujuanPasteOpenButton => 'Paste Zujuan questions';

  @override
  String get zujuanPasteTitle => 'Paste Zujuan questions';

  @override
  String get zujuanPasteIntro =>
      'Copy question text from Zujuan (multiple questions are fine), parse it, then preview, select, edit stems, and import.';

  @override
  String get zujuanPasteLoginHint =>
      'Zujuan answers require signing in (free accounts see about 30 questions per day). Paste answers and solutions in too and they will be recognized.';

  @override
  String get zujuanPasteInputLabel => 'Question text';

  @override
  String get zujuanPasteInputHint =>
      'Paste question text with answers and solutions; separate questions with blank lines';

  @override
  String get zujuanPasteParse => 'Parse';

  @override
  String get zujuanPasteParseEmpty =>
      'No questions were parsed from this text: paste at least one question stem and try again.';

  @override
  String zujuanPastePreviewTitle(int count) {
    return '$count question(s) parsed';
  }

  @override
  String get zujuanPasteItemStem => 'Stem (editable)';

  @override
  String zujuanPasteItemOptions(int count) {
    return '$count option(s)';
  }

  @override
  String zujuanPasteItemSource(String source) {
    return 'Source: $source';
  }

  @override
  String zujuanPasteItemYear(int year) {
    return '$year';
  }

  @override
  String get zujuanPastePartial =>
      'Incomplete parse: check the stem and options';

  @override
  String get zujuanPasteImport => 'Import all';

  @override
  String get zujuanPasteImporting => 'Importing…';

  @override
  String get zujuanPasteNothingSelected =>
      'Nothing selected: check the questions to import first.';

  @override
  String zujuanPasteSummary(int saved, int duplicates, int failed) {
    return 'Imported $saved · duplicates $duplicates · failed $failed';
  }

  @override
  String get zujuanPaperOpenButton => 'Scan paper';

  @override
  String get zujuanPaperTitle => 'Paper check';

  @override
  String get zujuanPaperIntro =>
      'Paste the whole Zujuan paper page to see which questions are already in the library and which are missing. The app does not fetch pages; the check is local.';

  @override
  String get zujuanPaperInputLabel => 'Paste paper page';

  @override
  String get zujuanPaperInputHint =>
      'The paper page URL or the whole page text; whatever select-all copy gives you in the browser';

  @override
  String get zujuanPaperParse => 'Parse';

  @override
  String get zujuanPaperParseEmpty =>
      'No questions recognised: paste the whole Zujuan paper page text (it must contain question links).';

  @override
  String zujuanPaperHeader(int count, int matched, int missing) {
    return '$count questions · $matched in library · $missing missing';
  }

  @override
  String get zujuanPaperUntitled => 'Untitled paper';

  @override
  String get zujuanPaperMatchedSection => 'In library';

  @override
  String zujuanPaperMatchedItem(String serial, String preview) {
    return '$serial · $preview';
  }

  @override
  String get zujuanPaperMissingSection => 'Missing';

  @override
  String zujuanPaperMissingWithLink(String id) {
    return '$id (link available)';
  }

  @override
  String zujuanPaperMissingNoLink(String id) {
    return '$id (no link)';
  }

  @override
  String get zujuanPaperNoBank =>
      'This page has no paper id (bankId), so missing-question links cannot be built; copy the question page links individually.';

  @override
  String get zujuanPaperCopyMissing => 'Copy missing links';

  @override
  String get zujuanPaperCopied => 'Missing links copied';

  @override
  String get zujuanPaperClose => 'Close';

  @override
  String get questionDetailTitle => 'Question detail';

  @override
  String get questionDetailQuestionMissing =>
      'This question is no longer in the library (it may have just been deleted).';

  @override
  String get questionDetailEditSource => 'Edit source';

  @override
  String get questionDetailEditSourceTitle => 'Edit the source';

  @override
  String get questionDetailEditSourceHint =>
      'A field left empty is left unchanged; the stem, answer and options are never touched.';

  @override
  String get questionDetailEditSourceYearBad =>
      'The year must be an integer between 1900 and 2200';

  @override
  String get questionSourceCopyLink => 'Copy original link';

  @override
  String get questionSourceCopyDone => 'Original link copied';

  @override
  String get questionSourceZujuan => 'Zujuan original';

  @override
  String get questionSourceEdit => 'Edit source link';

  @override
  String get questionSourceAdd => 'Add source link';

  @override
  String get questionSourceEditTitle => 'Edit source link';

  @override
  String get questionSourceEditInputLabel =>
      'Paste the original link or a Zujuan question page';

  @override
  String get questionSourceEditInputHint =>
      'e.g. /10q35583902.html or https://zujuan.xkw.com/10q35583902.html';

  @override
  String get questionSourceEditPreviewUrl => 'Link';

  @override
  String get questionSourceEditPreviewQuestionId => 'Zujuan question id';

  @override
  String get questionSourceEditPreviewBankId => 'Zujuan bankId';

  @override
  String get questionSourceEditPreviewNoUrl => 'No link saved';

  @override
  String get questionSourceEditEmptyHint =>
      'Could not recognise a link or question id: paste a full URL, a /10q...html path, or a Zujuan question id (e.g. 10q35583902.html).';

  @override
  String get questionSourceEditSave => 'Save';

  @override
  String get questionSourceEditSaved => 'Original link saved';

  @override
  String questionSourceEditFailed(String error) {
    return 'Could not save the original link: $error';
  }

  @override
  String get questionSourceEditClear => 'Clear link';

  @override
  String get questionSourceEditClearConfirm =>
      'This removes the original link from the question. Clear it?';

  @override
  String get questionSourceEditCleared => 'Original link cleared';

  @override
  String get questionSourceCancel => 'Cancel';

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
      'Turn photos into tags, knowledge points, flashcards or questions - confirmed one by one before anything is written';

  @override
  String get handwritingQueueSubtitle =>
      'The model only organises what is really on the page (questions are transcribed, never invented); every item is written only after you confirm it.';

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
  String handwritingQueueBatchAll(int count) {
    return 'Analyze all ($count pending)';
  }

  @override
  String handwritingQueueBatchProgress(int current, int total) {
    return 'Analyzing $current/$total';
  }

  @override
  String get handwritingQueueBatchStop => 'Stop';

  @override
  String get handwritingQueueBatchStopping => 'Stopping…';

  @override
  String handwritingQueueBatchReport(int succeeded, int failed, int skipped) {
    return 'Succeeded $succeeded, failed $failed, skipped $skipped';
  }

  @override
  String get handwritingQueueBatchStopped =>
      'Stopped; remaining photos were not analysed';

  @override
  String get handwritingQueueNothingFound =>
      'The model proposed nothing to organise: this page may have no tags, knowledge points, cards or questions.';

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
  String get handwritingQuestionMissingStem =>
      'The stem was not recognised; retake the photo or type it in';

  @override
  String handwritingQuestionOptions(int count) {
    return 'Options ($count)';
  }

  @override
  String handwritingQuestionAnswer(String value) {
    return 'Answer: $value';
  }

  @override
  String handwritingQuestionSolution(String value) {
    return 'Solution: $value';
  }

  @override
  String get handwritingQuestionEmptyValue => 'none';

  @override
  String get handwritingQuestionEditForIntake => 'Edit and save';

  @override
  String handwritingQuestionSaved(String serial) {
    return 'Saved as $serial (handwriting item marked as confirmed)';
  }

  @override
  String get handwritingQuestionSavedUnnumbered =>
      'Saved (unnumbered; handwriting item marked as confirmed)';

  @override
  String get handwritingQueuePreviewLoading => 'Checking what will happen…';

  @override
  String get handwritingQueuePreviewNeedsReview => 'Review before confirming';

  @override
  String get handwritingQueuePreviewBlocked => 'Cannot confirm';

  @override
  String handwritingQueuePreviewBlockedSummary(
      int ready, int needsReview, int blocked) {
    return '$ready ready, $needsReview to review, $blocked blocked';
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
  String get questionPaperActionProfileLabel =>
      'Order by capability profile (uncalibrated)';

  @override
  String get questionPaperActionProfileHint =>
      'Questions that hit the moves you struggle with move up a little; does nothing when you have no solved chains, and can be turned off.';

  @override
  String questionPaperActionProfileNote(String actions) {
    return 'This paper was ordered by your \"$actions\" moves (uncalibrated, can be turned off)';
  }

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
  String get questionPaperExportDocx => 'Export Word';

  @override
  String get questionPaperExportDocxBusy => 'Exporting…';

  @override
  String questionPaperExportDocxDone(
      int questions, int images, String fileName) {
    return 'Exported $questions question(s) with $images image(s): $fileName';
  }

  @override
  String questionPaperExportDocxEmptyDone(String fileName) {
    return 'The paper is empty: only the title and gap notes were exported ($fileName)';
  }

  @override
  String get questionPaperExportDocxFailed => 'Export failed';

  @override
  String questionPaperExportDocxWarnings(int count) {
    return '$count warning(s)';
  }

  @override
  String get questionPaperExportDocxWarningsAction => 'View';

  @override
  String get questionPaperExportDocxWarningsTitle => 'Export warnings';

  @override
  String get questionPaperExportDocxMissingQuestions => 'Missing questions';

  @override
  String get questionPaperExportDocxSkippedImages => 'Skipped images';

  @override
  String get questionPaperExportDocxFormulaFailures =>
      'Formula compilation failures';

  @override
  String get questionPaperExportDocxImageLoadNotes => 'Image notes';

  @override
  String get questionPaperExportDocxMissingFields => 'Missing fields';

  @override
  String questionPaperExportDocxMissingStem(int count) {
    return '$count missing stem(s)';
  }

  @override
  String questionPaperExportDocxMissingAnswer(int count) {
    return '$count missing answer(s)';
  }

  @override
  String questionPaperExportDocxMissingSolution(int count) {
    return '$count missing solution(s)';
  }

  @override
  String questionPaperExportDocxMoreItems(int count) {
    return 'and $count more';
  }

  @override
  String get paperSubjectQuotaTitle => 'Subject quotas';

  @override
  String get paperSubjectQuotaHint =>
      'Blank = no limit; a max of 0 selects none from that subject.';

  @override
  String get paperSubjectQuotaNoSubjects =>
      'Subject quotas only apply to selected subjects: pick subjects above, then set a max or minimum for each.';

  @override
  String get paperSubjectQuotaMaxLabel => 'Max';

  @override
  String get paperSubjectQuotaMinLabel => 'Min';

  @override
  String get paperSubjectQuotaClear => 'Clear quotas';

  @override
  String get paperSubjectQuotaInvalid => 'Enter a non-negative whole number';

  @override
  String get paperSubjectDistribution => 'Subject distribution';

  @override
  String paperSubjectQuotaBlocked(int count) {
    return '$count question(s) blocked by subject caps';
  }

  @override
  String paperSubjectQuotaBlockedItem(
      String subject, int limit, String detail) {
    return '$subject (limit $limit): $detail';
  }

  @override
  String paperSubjectQuotaBlockedMore(int count) {
    return 'and $count more blocked question(s)';
  }

  @override
  String get paperSubjectQuotaShortfallTitle => 'Minimum shortfalls';

  @override
  String paperSubjectQuotaShortfall(
      String subject, int missing, int available) {
    return '$subject: short by $missing (available: $available)';
  }

  @override
  String paperSubjectQuotaShortfallEmpty(String subject) {
    return 'No usable questions for $subject in the bank';
  }

  @override
  String get paperDomainQuotaTitle => 'Domain quotas';

  @override
  String get paperDomainQuotaHint =>
      'Leave empty for no cap; a cap of 0 excludes the domain entirely. Domains are the first segment of a knowledge-point tag path, separate from the subject quota above.';

  @override
  String get paperDomainQuotaMaxLabel => 'Max';

  @override
  String get paperDomainQuotaMinLabel => 'Min';

  @override
  String get paperDomainQuotaClear => 'Clear quotas';

  @override
  String get paperDomainQuotaInvalid => 'Enter a non-negative whole number';

  @override
  String get paperDomainQuotaDistribution => 'Domain distribution';

  @override
  String paperDomainQuotaBlocked(int count) {
    return '$count question(s) blocked by domain caps';
  }

  @override
  String paperDomainQuotaBlockedItem(String domain, int limit, String detail) {
    return '$domain (cap $limit): $detail';
  }

  @override
  String paperDomainQuotaBlockedMore(int count) {
    return 'and $count more blocked question(s)';
  }

  @override
  String get paperDomainQuotaShortfallTitle => 'Domain minimum shortfalls';

  @override
  String paperDomainQuotaShortfall(String domain, int missing, int available) {
    return '$domain: short by $missing (available: $available)';
  }

  @override
  String paperDomainQuotaShortfallEmpty(String domain) {
    return 'No usable questions for $domain in the bank';
  }

  @override
  String paperDomainQuotaUncovered(String domains) {
    return 'Uncovered domains: $domains';
  }

  @override
  String get paperManualSelectionTitle => 'Manual selection';

  @override
  String get paperManualSelectionAdd => 'Choose questions';

  @override
  String get paperManualSelectionHint =>
      'Mandatory questions are always included (capped only by the target count); excluded questions are never picked; exclusion wins on conflicts.';

  @override
  String paperManualSelectionIncludeTitle(int count) {
    return 'Mandatory ($count)';
  }

  @override
  String paperManualSelectionExcludeTitle(int count) {
    return 'Excluded ($count)';
  }

  @override
  String get paperManualSelectionRemove => 'Remove';

  @override
  String get paperManualSelectionClear => 'Clear manual selection';

  @override
  String get paperManualSelectionPickerTitle => 'Choose questions';

  @override
  String get paperManualSelectionPickerFilterHint =>
      'Filter by stem or question ID';

  @override
  String get paperManualSelectionPickerInclude => 'Mark mandatory';

  @override
  String get paperManualSelectionPickerExclude => 'Mark excluded';

  @override
  String get paperManualSelectionPickerNone =>
      'No selectable questions in the bank';

  @override
  String paperManualSelectionPickerFailed(String message) {
    return 'Failed to read the question bank: $message';
  }

  @override
  String paperManualSelectionOutcomeIncluded(int count) {
    return '$count mandatory question(s) included';
  }

  @override
  String paperManualSelectionMissingTitle(int count) {
    return 'Mandatory but missing from the bank ($count)';
  }

  @override
  String paperManualSelectionSkippedTitle(int count) {
    return 'Mandatory but squeezed out by the target count ($count)';
  }

  @override
  String paperManualSelectionConflictTitle(int count) {
    return 'Mandatory/excluded conflicts (exclusion wins, $count)';
  }

  @override
  String paperManualSelectionMore(int count) {
    return '$count more not listed';
  }

  @override
  String get paperQualityTitle => 'Paper quality check';

  @override
  String paperQualitySummary(
      int questionCount, int requestedCount, String percent) {
    return '$questionCount of $requestedCount questions ($percent filled)';
  }

  @override
  String paperQualityCoverage(String percent) {
    return 'Knowledge point coverage $percent';
  }

  @override
  String get paperQualityQuotaUnsatisfied =>
      'Minimum quotas are not satisfied; the findings below explain the gap.';

  @override
  String get paperQualityClean => 'No criteria were triggered.';

  @override
  String paperQualityGroupHeader(String label, int count) {
    return '$label ($count)';
  }

  @override
  String get paperQualityEvidenceToggle => 'Show evidence';

  @override
  String get paperQualityEvidenceCollapse => 'Hide evidence';

  @override
  String get paperQualityEvidenceTitle => 'Evidence';

  @override
  String paperQualityTruncated(int count) {
    return '$count more finding(s) were truncated';
  }

  @override
  String get paperQualityFailed =>
      'The quality check is unavailable right now.';

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

  @override
  String get handwritingMergeModeEnter => 'Select photos';

  @override
  String get handwritingMergeModeExit => 'Cancel selection';

  @override
  String handwritingMergeButton(int count) {
    return 'Merge $count photo(s)';
  }

  @override
  String get handwritingMergeNeedTwo => 'Select at least two photos to merge.';

  @override
  String get handwritingMergeHint =>
      'Multi-page or burst photos are sent to the model in selection order; the same question across pages is merged into one item.';

  @override
  String handwritingMergeRunTitle(int count) {
    return 'Multi-page intake ($count photos)';
  }

  @override
  String get handwritingMergeRunFailed => 'Merge failed';

  @override
  String get handwritingMergedBadge => 'Merged';

  @override
  String get handwritingMergeUnselectable =>
      'Photos that are already organised cannot be merged';

  @override
  String settingsQuestionPackBackupCreated(String path) {
    return 'Existing question bank backed up before import: $path';
  }

  @override
  String get settingsQuestionPackBackupFailed =>
      'Backup before import failed (import continues)';

  @override
  String get settingsQuestionPackBackupsTitle => 'Pre-import backups';

  @override
  String get settingsQuestionPackBackupsEmpty =>
      'No pre-import backups yet. Importing a question pack will first export the current bank as a backup.';

  @override
  String get settingsQuestionPackBackupsHint =>
      'Before each pack import, the current bank is exported to a .tqb file in the app documents directory. Deleting a backup removes only that file; the question bank is untouched.';

  @override
  String get settingsQuestionPackBackupDeleteTooltip => 'Delete this backup';

  @override
  String settingsQuestionPackBackupDeleteConfirm(String name) {
    return 'Delete backup \"$name\"? Only this backup file is removed; questions in the bank are untouched.';
  }

  @override
  String get settingsQuestionPackBackupDeleteDone => 'Backup deleted';

  @override
  String settingsQuestionPackBackupDeleteFailed(String error) {
    return 'Failed to delete backup: $error';
  }

  @override
  String get settingsQuestionPackRestoreTooltip => 'Restore from this backup';

  @override
  String get settingsQuestionPackRestoreAction => 'Restore';

  @override
  String settingsQuestionPackRestoreConfirm(String name) {
    return 'Restore the question bank from \"$name\"?';
  }

  @override
  String get settingsQuestionPackRestoreConfirmBody =>
      'Questions in the backup are updated into the current bank by number. The current bank is backed up again first; questions not present in the backup are kept.';

  @override
  String settingsQuestionPackRestoreFailed(String error) {
    return 'Restore failed: $error';
  }

  @override
  String get settingsQuestionPackBackupPruneAction => 'Prune old backups';

  @override
  String settingsQuestionPackBackupPruneTooltip(int keep) {
    return 'Delete older backups, keeping the most recent $keep';
  }

  @override
  String settingsQuestionPackBackupPruneConfirm(int count, int keep) {
    return 'Delete the oldest $count backup(s), keeping the most recent $keep? This cannot be undone.';
  }

  @override
  String settingsQuestionPackBackupPruneDone(int count) {
    return 'Deleted $count old backup(s)';
  }

  @override
  String settingsQuestionPackBackupPruneFailed(String error) {
    return 'Pruning old backups failed: $error';
  }

  @override
  String get questionDetailSelfTest => 'Self test';

  @override
  String get questionDetailSelfTestExit => 'End self-test';

  @override
  String get questionDetailSelfTestSubmit => 'Submit answer';

  @override
  String get questionDetailSelfTestCorrect => 'Correct';

  @override
  String get questionDetailSelfTestIncorrect => 'Incorrect';

  @override
  String questionDetailSelfTestCorrectLabels(String labels) {
    return 'Correct answer: $labels';
  }

  @override
  String get questionDetailSelfTestHiddenHint =>
      'Self-testing: answers and solutions appear after you submit.';

  @override
  String questionDetailAttemptHistory(int total, int correct) {
    return 'Self-tested $total time(s) · $correct correct';
  }

  @override
  String questionDetailAttemptLastCorrect(String at) {
    return 'Last correct: $at';
  }

  @override
  String questionDetailAttemptLastIncorrect(String at) {
    return 'Last incorrect: $at';
  }

  @override
  String get questionBankWrongOnly => 'Wrong answers';

  @override
  String get questionBankWrongOnlyTooltip =>
      'Only questions answered wrong in self-tests';

  @override
  String questionBankWrongCount(int count) {
    return '$count wrong';
  }

  @override
  String get questionDetailAttemptClearAction => 'Clear records';

  @override
  String get questionDetailAttemptClearConfirmTitle => 'Clear attempt records?';

  @override
  String get questionDetailAttemptClearConfirmBody =>
      'Self-test counts and the wrong-answer mark for this question will be reset. This cannot be undone.';

  @override
  String get questionDetailAttemptClearDone => 'Attempt records cleared';

  @override
  String questionDetailAttemptClearFailed(String error) {
    return 'Clear failed: $error';
  }

  @override
  String questionDetailAttemptDetailToggle(int count) {
    return 'Show details ($count)';
  }

  @override
  String get questionDetailAttemptDetailHide => 'Hide details';
}
