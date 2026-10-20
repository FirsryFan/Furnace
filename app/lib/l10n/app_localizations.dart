import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Furnace'**
  String get appTitle;

  /// No description provided for @navMindMap.
  ///
  /// In en, this message translates to:
  /// **'Mind Map'**
  String get navMindMap;

  /// No description provided for @navTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get navTags;

  /// No description provided for @navThread.
  ///
  /// In en, this message translates to:
  /// **'Thread'**
  String get navThread;

  /// No description provided for @navTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get navTasks;

  /// No description provided for @navTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get navTime;

  /// User-facing term (2026-10-02): 闪存卡 / flashcard. It replaced the older words 「知识点」 and 「词条」. Code, database columns and the MindNet contract still say knowledgePoint / KP on purpose - renaming identifiers or the schema would be a migration with no user-visible benefit.
  ///
  /// In en, this message translates to:
  /// **'Flashcards'**
  String get navAnki;

  /// Top-level destination for the question bank (题库): the overview list plus the intake/paper/photo/material entries.
  ///
  /// In en, this message translates to:
  /// **'Questions'**
  String get navQuestions;

  /// No description provided for @navPackages.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get navPackages;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @tagsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tagsTitle;

  /// No description provided for @settingsProfileName.
  ///
  /// In en, this message translates to:
  /// **'Profile name'**
  String get settingsProfileName;

  /// No description provided for @settingsBackup.
  ///
  /// In en, this message translates to:
  /// **'Backup data'**
  String get settingsBackup;

  /// No description provided for @settingsBackupDone.
  ///
  /// In en, this message translates to:
  /// **'Backup saved'**
  String get settingsBackupDone;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get commonTitle;

  /// No description provided for @commonContent.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get commonContent;

  /// No description provided for @commonName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get commonName;

  /// No description provided for @commonDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get commonDescription;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get commonStart;

  /// No description provided for @commonEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get commonEnd;

  /// No description provided for @commonClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// No description provided for @commonRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageZh.
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get settingsLanguageZh;

  /// No description provided for @settingsLanguageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEn;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @mindMapNewMap.
  ///
  /// In en, this message translates to:
  /// **'New mind map'**
  String get mindMapNewMap;

  /// No description provided for @mindMapAddNode.
  ///
  /// In en, this message translates to:
  /// **'Add node'**
  String get mindMapAddNode;

  /// No description provided for @mindMapPromoteTag.
  ///
  /// In en, this message translates to:
  /// **'Promote to tag'**
  String get mindMapPromoteTag;

  /// No description provided for @mindMapPromoteTask.
  ///
  /// In en, this message translates to:
  /// **'Promote to task'**
  String get mindMapPromoteTask;

  /// No description provided for @mindMapRenameNode.
  ///
  /// In en, this message translates to:
  /// **'Rename node'**
  String get mindMapRenameNode;

  /// No description provided for @mindMapEditNotes.
  ///
  /// In en, this message translates to:
  /// **'Edit notes'**
  String get mindMapEditNotes;

  /// No description provided for @mindMapMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get mindMapMoveUp;

  /// No description provided for @mindMapMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get mindMapMoveDown;

  /// No description provided for @tasksNewTask.
  ///
  /// In en, this message translates to:
  /// **'New event'**
  String get tasksNewTask;

  /// No description provided for @tasksPriorityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get tasksPriorityHigh;

  /// No description provided for @tasksPriorityMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get tasksPriorityMedium;

  /// No description provided for @tasksPriorityLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get tasksPriorityLow;

  /// No description provided for @tasksEstimateMinutes.
  ///
  /// In en, this message translates to:
  /// **'Estimate (minutes)'**
  String get tasksEstimateMinutes;

  /// No description provided for @tasksExpectedAt.
  ///
  /// In en, this message translates to:
  /// **'Expected time'**
  String get tasksExpectedAt;

  /// No description provided for @tasksSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Suggestions'**
  String get tasksSuggestions;

  /// No description provided for @tasksNoSuggestions.
  ///
  /// In en, this message translates to:
  /// **'No suggestions'**
  String get tasksNoSuggestions;

  /// No description provided for @tasksSubtasks.
  ///
  /// In en, this message translates to:
  /// **'Subtasks'**
  String get tasksSubtasks;

  /// No description provided for @tasksDependencies.
  ///
  /// In en, this message translates to:
  /// **'Dependencies'**
  String get tasksDependencies;

  /// No description provided for @tasksAddSubtask.
  ///
  /// In en, this message translates to:
  /// **'Add subtask'**
  String get tasksAddSubtask;

  /// No description provided for @tasksAddDependency.
  ///
  /// In en, this message translates to:
  /// **'Add dependency'**
  String get tasksAddDependency;

  /// No description provided for @tasksRemindAt.
  ///
  /// In en, this message translates to:
  /// **'Remind at'**
  String get tasksRemindAt;

  /// No description provided for @tasksReminder.
  ///
  /// In en, this message translates to:
  /// **'Reminder'**
  String get tasksReminder;

  /// No description provided for @tasksReminderPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Notifications are not allowed, so this reminder will not appear. Allow notifications for Furnace in system settings, then set the reminder again.'**
  String get tasksReminderPermissionDenied;

  /// No description provided for @tasksDueAt.
  ///
  /// In en, this message translates to:
  /// **'Deadline'**
  String get tasksDueAt;

  /// No description provided for @timeNewBlock.
  ///
  /// In en, this message translates to:
  /// **'New schedule block'**
  String get timeNewBlock;

  /// No description provided for @timeTodaySchedule.
  ///
  /// In en, this message translates to:
  /// **'Today\'s schedule'**
  String get timeTodaySchedule;

  /// No description provided for @timeAvailable.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get timeAvailable;

  /// No description provided for @timeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Busy'**
  String get timeUnavailable;

  /// No description provided for @timeEnergy.
  ///
  /// In en, this message translates to:
  /// **'Energy'**
  String get timeEnergy;

  /// No description provided for @timeEnergyHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get timeEnergyHigh;

  /// No description provided for @timeEnergyMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get timeEnergyMedium;

  /// No description provided for @timeEnergyLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get timeEnergyLow;

  /// No description provided for @timeSuitable.
  ///
  /// In en, this message translates to:
  /// **'Suitable for'**
  String get timeSuitable;

  /// No description provided for @timeSuitableMemorize.
  ///
  /// In en, this message translates to:
  /// **'Memorize'**
  String get timeSuitableMemorize;

  /// No description provided for @timeSuitableDeepWork.
  ///
  /// In en, this message translates to:
  /// **'Deep work'**
  String get timeSuitableDeepWork;

  /// No description provided for @timeSuitableReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get timeSuitableReview;

  /// No description provided for @timeNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get timeNone;

  /// No description provided for @calendarTimeline.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get calendarTimeline;

  /// No description provided for @calendarAddBlock.
  ///
  /// In en, this message translates to:
  /// **'New schedule block'**
  String get calendarAddBlock;

  /// No description provided for @calendarOpenDay.
  ///
  /// In en, this message translates to:
  /// **'Open day view'**
  String get calendarOpenDay;

  /// No description provided for @calendarOpenWeek.
  ///
  /// In en, this message translates to:
  /// **'Open week view'**
  String get calendarOpenWeek;

  /// No description provided for @calendarDayEmpty.
  ///
  /// In en, this message translates to:
  /// **'No blocks on this day yet'**
  String get calendarDayEmpty;

  /// No description provided for @timeArbitraryRangeHint.
  ///
  /// In en, this message translates to:
  /// **'Start and end are free-form (minute precision), and overlapping blocks are allowed.'**
  String get timeArbitraryRangeHint;

  /// No description provided for @timeBusyHint.
  ///
  /// In en, this message translates to:
  /// **'Busy = a hard block that occupies time (class, meeting); open = a soft block you can plan into.'**
  String get timeBusyHint;

  /// No description provided for @timePlusFiveMinutes.
  ///
  /// In en, this message translates to:
  /// **'Add 5 minutes'**
  String get timePlusFiveMinutes;

  /// No description provided for @timeMinusFiveMinutes.
  ///
  /// In en, this message translates to:
  /// **'Subtract 5 minutes'**
  String get timeMinusFiveMinutes;

  /// No description provided for @timeTemplates.
  ///
  /// In en, this message translates to:
  /// **'Schedule templates'**
  String get timeTemplates;

  /// No description provided for @timeApplyTemplate.
  ///
  /// In en, this message translates to:
  /// **'Apply a template'**
  String get timeApplyTemplate;

  /// No description provided for @timeApplyDayTemplate.
  ///
  /// In en, this message translates to:
  /// **'Apply a day template'**
  String get timeApplyDayTemplate;

  /// No description provided for @timeApplyWeekTemplate.
  ///
  /// In en, this message translates to:
  /// **'Apply a week template'**
  String get timeApplyWeekTemplate;

  /// No description provided for @timeNoTemplates.
  ///
  /// In en, this message translates to:
  /// **'No templates yet. Lay out a week or a day in the calendar, then save it here.'**
  String get timeNoTemplates;

  /// No description provided for @timeDeleteTemplate.
  ///
  /// In en, this message translates to:
  /// **'Delete template'**
  String get timeDeleteTemplate;

  /// No description provided for @timeSaveTemplate.
  ///
  /// In en, this message translates to:
  /// **'Save as template'**
  String get timeSaveTemplate;

  /// No description provided for @timeTemplateBlockCount.
  ///
  /// In en, this message translates to:
  /// **'{count} block(s)'**
  String timeTemplateBlockCount(int count);

  /// No description provided for @timeTemplateApplied.
  ///
  /// In en, this message translates to:
  /// **'Applied {count} block(s)'**
  String timeTemplateApplied(int count);

  /// No description provided for @timelineZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get timelineZoomIn;

  /// No description provided for @timelineZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get timelineZoomOut;

  /// No description provided for @timelineFold.
  ///
  /// In en, this message translates to:
  /// **'Fold (scroll vertically)'**
  String get timelineFold;

  /// No description provided for @timelineUnfold.
  ///
  /// In en, this message translates to:
  /// **'Unfold (scroll horizontally)'**
  String get timelineUnfold;

  /// No description provided for @timelineSpanDays.
  ///
  /// In en, this message translates to:
  /// **'{days} days'**
  String timelineSpanDays(int days);

  /// No description provided for @calendarDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get calendarDay;

  /// No description provided for @calendarWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get calendarWeek;

  /// No description provided for @calendarMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get calendarMonth;

  /// No description provided for @calendarToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get calendarToday;

  /// No description provided for @calendarPrev.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get calendarPrev;

  /// No description provided for @calendarNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get calendarNext;

  /// No description provided for @calendarZoom.
  ///
  /// In en, this message translates to:
  /// **'Vertical zoom'**
  String get calendarZoom;

  /// No description provided for @calendarZoom15.
  ///
  /// In en, this message translates to:
  /// **'15 min / row'**
  String get calendarZoom15;

  /// No description provided for @calendarZoom30.
  ///
  /// In en, this message translates to:
  /// **'30 min / row'**
  String get calendarZoom30;

  /// No description provided for @calendarZoom60.
  ///
  /// In en, this message translates to:
  /// **'60 min / row'**
  String get calendarZoom60;

  /// No description provided for @calendarWeekday1.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get calendarWeekday1;

  /// No description provided for @calendarWeekday2.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get calendarWeekday2;

  /// No description provided for @calendarWeekday3.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get calendarWeekday3;

  /// No description provided for @calendarWeekday4.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get calendarWeekday4;

  /// No description provided for @calendarWeekday5.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get calendarWeekday5;

  /// No description provided for @calendarWeekday6.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get calendarWeekday6;

  /// No description provided for @calendarWeekday7.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get calendarWeekday7;

  /// No description provided for @ankiShowAnswer.
  ///
  /// In en, this message translates to:
  /// **'Show answer'**
  String get ankiShowAnswer;

  /// No description provided for @ankiSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get ankiSubmit;

  /// No description provided for @ankiForgot.
  ///
  /// In en, this message translates to:
  /// **'Forgot'**
  String get ankiForgot;

  /// No description provided for @ankiFuzzy.
  ///
  /// In en, this message translates to:
  /// **'Fuzzy'**
  String get ankiFuzzy;

  /// No description provided for @ankiRemembered.
  ///
  /// In en, this message translates to:
  /// **'Remembered'**
  String get ankiRemembered;

  /// No description provided for @ankiManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get ankiManage;

  /// No description provided for @ankiStats.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get ankiStats;

  /// No description provided for @ankiReviews7d.
  ///
  /// In en, this message translates to:
  /// **'7d reviews'**
  String get ankiReviews7d;

  /// No description provided for @ankiNewKnowledgePoint.
  ///
  /// In en, this message translates to:
  /// **'New flashcard'**
  String get ankiNewKnowledgePoint;

  /// No description provided for @ankiAutoBlank.
  ///
  /// In en, this message translates to:
  /// **'Auto blank'**
  String get ankiAutoBlank;

  /// No description provided for @ankiSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get ankiSource;

  /// No description provided for @ankiCardGroup.
  ///
  /// In en, this message translates to:
  /// **'Card group (tag)'**
  String get ankiCardGroup;

  /// No description provided for @ankiCardGroupNone.
  ///
  /// In en, this message translates to:
  /// **'No group (loose card)'**
  String get ankiCardGroupNone;

  /// No description provided for @ankiNewTemplate.
  ///
  /// In en, this message translates to:
  /// **'New template'**
  String get ankiNewTemplate;

  /// No description provided for @ankiQuestion.
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get ankiQuestion;

  /// No description provided for @ankiAnswer.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get ankiAnswer;

  /// No description provided for @ankiOptions.
  ///
  /// In en, this message translates to:
  /// **'Options (one per line)'**
  String get ankiOptions;

  /// No description provided for @ankiType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get ankiType;

  /// No description provided for @ankiTypeMcq.
  ///
  /// In en, this message translates to:
  /// **'Multiple choice'**
  String get ankiTypeMcq;

  /// No description provided for @ankiTypeFillBlank.
  ///
  /// In en, this message translates to:
  /// **'Fill in blank'**
  String get ankiTypeFillBlank;

  /// No description provided for @ankiTypeEssay.
  ///
  /// In en, this message translates to:
  /// **'Essay'**
  String get ankiTypeEssay;

  /// No description provided for @ankiNoDueCards.
  ///
  /// In en, this message translates to:
  /// **'No cards due'**
  String get ankiNoDueCards;

  /// No description provided for @ankiCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get ankiCorrect;

  /// No description provided for @ankiWrong.
  ///
  /// In en, this message translates to:
  /// **'Wrong'**
  String get ankiWrong;

  /// No description provided for @ankiYourAnswer.
  ///
  /// In en, this message translates to:
  /// **'Your answer'**
  String get ankiYourAnswer;

  /// No description provided for @ankiHint.
  ///
  /// In en, this message translates to:
  /// **'Hint'**
  String get ankiHint;

  /// No description provided for @ankiHintHelper.
  ///
  /// In en, this message translates to:
  /// **'Shown only when you ask for it; asking is not an answer'**
  String get ankiHintHelper;

  /// No description provided for @ankiJudgeStrict.
  ///
  /// In en, this message translates to:
  /// **'Strict'**
  String get ankiJudgeStrict;

  /// No description provided for @ankiJudgeLenient.
  ///
  /// In en, this message translates to:
  /// **'Lenient'**
  String get ankiJudgeLenient;

  /// No description provided for @ankiJudgeSelf.
  ///
  /// In en, this message translates to:
  /// **'Self'**
  String get ankiJudgeSelf;

  /// No description provided for @ankiJudgeStrictHint.
  ///
  /// In en, this message translates to:
  /// **'Exact characters: dictation and spelling practice'**
  String get ankiJudgeStrictHint;

  /// No description provided for @ankiJudgeLenientHint.
  ///
  /// In en, this message translates to:
  /// **'Ignores spaces, full/half width, punctuation and case; tolerates one typo'**
  String get ankiJudgeLenientHint;

  /// No description provided for @ankiJudgeSelfHint.
  ///
  /// In en, this message translates to:
  /// **'See the answer, then judge yourself'**
  String get ankiJudgeSelfHint;

  /// No description provided for @ankiJudgeYourself.
  ///
  /// In en, this message translates to:
  /// **'Compare with the answer and grade yourself'**
  String get ankiJudgeYourself;

  /// No description provided for @ankiAfterAnswerPrompt.
  ///
  /// In en, this message translates to:
  /// **'After seeing the answer, how close were you?'**
  String get ankiAfterAnswerPrompt;

  /// No description provided for @ankiNearMiss.
  ///
  /// In en, this message translates to:
  /// **'Nearly had it'**
  String get ankiNearMiss;

  /// No description provided for @ankiStillForgot.
  ///
  /// In en, this message translates to:
  /// **'Still didn\'t know it'**
  String get ankiStillForgot;

  /// No description provided for @ankiAfterAnswerHint.
  ///
  /// In en, this message translates to:
  /// **'Only tells the cognitive model whether this was forgetting or learning; the next review date is unchanged.'**
  String get ankiAfterAnswerHint;

  /// No description provided for @ankiNextCard.
  ///
  /// In en, this message translates to:
  /// **'Next card'**
  String get ankiNextCard;

  /// No description provided for @ankiExposureTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reading only, not a review: due date unchanged, no review log'**
  String get ankiExposureTooltip;

  /// No description provided for @ankiExposureRecorded.
  ///
  /// In en, this message translates to:
  /// **'Noted as reading only: not a review, due date unchanged'**
  String get ankiExposureRecorded;

  /// No description provided for @reviewZoneChip.
  ///
  /// In en, this message translates to:
  /// **'Model\'s read: {zone}'**
  String reviewZoneChip(Object zone);

  /// No description provided for @ankiTypePreference.
  ///
  /// In en, this message translates to:
  /// **'Card type preference'**
  String get ankiTypePreference;

  /// No description provided for @ankiTypePreferenceMixed.
  ///
  /// In en, this message translates to:
  /// **'Mixed (currently: fill in blank)'**
  String get ankiTypePreferenceMixed;

  /// No description provided for @ankiTypePreferenceFillBlankLenient.
  ///
  /// In en, this message translates to:
  /// **'Lenient fill in blank'**
  String get ankiTypePreferenceFillBlankLenient;

  /// No description provided for @ankiTypePreferenceNotSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved: it applies from the next generated card on'**
  String get ankiTypePreferenceNotSaved;

  /// No description provided for @ankiJudgePreference.
  ///
  /// In en, this message translates to:
  /// **'Default judging mode'**
  String get ankiJudgePreference;

  /// No description provided for @ankiJudgePreferenceDetail.
  ///
  /// In en, this message translates to:
  /// **'Only decides what a new answer starts as; the control above each card still wins.'**
  String get ankiJudgePreferenceDetail;

  /// No description provided for @ankiTypePreferenceDetail.
  ///
  /// In en, this message translates to:
  /// **'Used when a card is generated for new material (auto blank, package import, AI).'**
  String get ankiTypePreferenceDetail;

  /// No description provided for @reviewPreferences.
  ///
  /// In en, this message translates to:
  /// **'Review preferences'**
  String get reviewPreferences;

  /// No description provided for @reviewPlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Review plan'**
  String get reviewPlanTitle;

  /// No description provided for @reviewPlanToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get reviewPlanToday;

  /// No description provided for @reviewPlanEmpty.
  ///
  /// In en, this message translates to:
  /// **'No card group has a daily target yet. Add one to plan \"how much per group, per day\": a group is a tag, and its whole subtree counts as that group.'**
  String get reviewPlanEmpty;

  /// No description provided for @reviewPlanAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a group target'**
  String get reviewPlanAdd;

  /// No description provided for @reviewPlanPickGroup.
  ///
  /// In en, this message translates to:
  /// **'Which card group?'**
  String get reviewPlanPickGroup;

  /// No description provided for @reviewPlanNoTags.
  ///
  /// In en, this message translates to:
  /// **'No tags yet: a card group is a tag, so create the tag first.'**
  String get reviewPlanNoTags;

  /// No description provided for @reviewPlanGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily target for {tag}'**
  String reviewPlanGroupTitle(String tag);

  /// No description provided for @reviewPlanGroupBody.
  ///
  /// In en, this message translates to:
  /// **'The tag and everything under it count as this group.'**
  String get reviewPlanGroupBody;

  /// No description provided for @reviewPlanUngroupedTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} cards are in no card group'**
  String reviewPlanUngroupedTitle(int count);

  /// No description provided for @reviewPlanUngroupedBody.
  ///
  /// In en, this message translates to:
  /// **'A card group is a tag, and daily targets are set per group, so a card with no tag falls outside every target - the plan cannot see it. Give them a group once and you can set that group\'s daily amount right away.'**
  String get reviewPlanUngroupedBody;

  /// No description provided for @reviewPlanUngroupedAction.
  ///
  /// In en, this message translates to:
  /// **'Put them in one group'**
  String get reviewPlanUngroupedAction;

  /// No description provided for @reviewPlanUngroupedDone.
  ///
  /// In en, this message translates to:
  /// **'Moved {count} cards into \"{tag}\"'**
  String reviewPlanUngroupedDone(int count, String tag);

  /// No description provided for @todayPlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Today\'s list'**
  String get todayPlanTitle;

  /// No description provided for @todayPlanUncalibrated.
  ///
  /// In en, this message translates to:
  /// **'The bonus is not calibrated: this order is a hint, not a measurement.'**
  String get todayPlanUncalibrated;

  /// No description provided for @todayPlanEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing is due today. That is not \"nothing to do\" - the due queue is just empty; which new cards to learn is your call, and this page will not invent them.'**
  String get todayPlanEmpty;

  /// No description provided for @todayPlanCount.
  ///
  /// In en, this message translates to:
  /// **'{count} things to do today'**
  String todayPlanCount(int count);

  /// No description provided for @todayPlanOmitted.
  ///
  /// In en, this message translates to:
  /// **'{count} more sit past this page\'s cap (the list is meant to be followed, not read as a directory).'**
  String todayPlanOmitted(int count);

  /// No description provided for @todayPlanKindReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get todayPlanKindReview;

  /// No description provided for @todayPlanKindPractice.
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get todayPlanKindPractice;

  /// No description provided for @todayPlanMetricRetention.
  ///
  /// In en, this message translates to:
  /// **'retention'**
  String get todayPlanMetricRetention;

  /// No description provided for @todayPlanMetricReachability.
  ///
  /// In en, this message translates to:
  /// **'reachability'**
  String get todayPlanMetricReachability;

  /// No description provided for @todayPlanPrice.
  ///
  /// In en, this message translates to:
  /// **'{metric} V={value}, cost {cost}'**
  String todayPlanPrice(String metric, String value, String cost);

  /// No description provided for @todayPlanPracticeHint.
  ///
  /// In en, this message translates to:
  /// **'Problems are priced by the model (plan_today / evaluate_problem_fit); this page only lists due cards.'**
  String get todayPlanPracticeHint;

  /// No description provided for @todayPlanFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read today\'s list: {error}'**
  String todayPlanFailed(String error);

  /// No description provided for @todayStudyPlanTitle.
  ///
  /// In en, this message translates to:
  /// **'What to do today'**
  String get todayStudyPlanTitle;

  /// No description provided for @todayStudyPlanLoading.
  ///
  /// In en, this message translates to:
  /// **'Building today\'s plan…'**
  String get todayStudyPlanLoading;

  /// No description provided for @todayStudyPlanTotal.
  ///
  /// In en, this message translates to:
  /// **'About {minutes} min in total'**
  String todayStudyPlanTotal(int minutes);

  /// No description provided for @todayStudyPlanSkipped.
  ///
  /// In en, this message translates to:
  /// **'{count} step(s) skipped'**
  String todayStudyPlanSkipped(int count);

  /// No description provided for @todayStudyPlanStepMinutes.
  ///
  /// In en, this message translates to:
  /// **'About {minutes} min'**
  String todayStudyPlanStepMinutes(int minutes);

  /// No description provided for @todayStudyPlanFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read today\'s plan: {error}'**
  String todayStudyPlanFailed(String error);

  /// No description provided for @todayStudyPlanRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get todayStudyPlanRetry;

  /// No description provided for @todayStudyPlanGoPractice.
  ///
  /// In en, this message translates to:
  /// **'Practice in the question bank'**
  String get todayStudyPlanGoPractice;

  /// No description provided for @todayStudyPlanGoReview.
  ///
  /// In en, this message translates to:
  /// **'Review due cards'**
  String get todayStudyPlanGoReview;

  /// No description provided for @todayStudyPlanGoChains.
  ///
  /// In en, this message translates to:
  /// **'Open the question bank'**
  String get todayStudyPlanGoChains;

  /// No description provided for @todayStudyPlanGoVocabulary.
  ///
  /// In en, this message translates to:
  /// **'Open the vocabulary'**
  String get todayStudyPlanGoVocabulary;

  /// No description provided for @materialIntakeTitle.
  ///
  /// In en, this message translates to:
  /// **'Add material'**
  String get materialIntakeTitle;

  /// No description provided for @materialIntakeEntryHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the AI\'s mindnet.material/1 envelope: see what would be created, then confirm'**
  String get materialIntakeEntryHint;

  /// No description provided for @materialIntakeIntro.
  ///
  /// In en, this message translates to:
  /// **'Paper material -> the AI reads it into a mindnet.material/1 envelope -> this page does the last steps: paste it, look at the proposals (each with the page and line it came from), then confirm. Nothing is written into knowledge points before you confirm; connections land as clue edges in knowledge_edges (strictly directed, ls uncalibrated, only when both ends exist).'**
  String get materialIntakeIntro;

  /// No description provided for @materialIntakeEnvelopeLabel.
  ///
  /// In en, this message translates to:
  /// **'Envelope (mindnet.material/1)'**
  String get materialIntakeEnvelopeLabel;

  /// No description provided for @materialIntakeEnvelopeHint.
  ///
  /// In en, this message translates to:
  /// **'protocol: mindnet.material/1 · batch_id: ... · items: [ ... ]'**
  String get materialIntakeEnvelopeHint;

  /// No description provided for @materialIntakePreview.
  ///
  /// In en, this message translates to:
  /// **'See proposals'**
  String get materialIntakePreview;

  /// No description provided for @materialIntakeClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get materialIntakeClear;

  /// No description provided for @materialIntakePickPhoto.
  ///
  /// In en, this message translates to:
  /// **'Pick a photo'**
  String get materialIntakePickPhoto;

  /// No description provided for @materialIntakePhotoHint.
  ///
  /// In en, this message translates to:
  /// **'The photo goes to a vision model; its answer is read straight into a run request (checked, not executed, and nothing is written).'**
  String get materialIntakePhotoHint;

  /// No description provided for @materialIntakePhotoPickFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not pick a photo: {message}'**
  String materialIntakePhotoPickFailed(String message);

  /// No description provided for @materialIntakePhotoReadFailed.
  ///
  /// In en, this message translates to:
  /// **'The photo did not read into a request: {message}'**
  String materialIntakePhotoReadFailed(String message);

  /// No description provided for @materialIntakePasteRun.
  ///
  /// In en, this message translates to:
  /// **'Paste a run/1'**
  String get materialIntakePasteRun;

  /// No description provided for @materialIntakeRunDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Paste a run/1: check it, then dry-run it'**
  String get materialIntakeRunDialogTitle;

  /// No description provided for @materialIntakeRunHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a mindnet.run/1 request here'**
  String get materialIntakeRunHint;

  /// No description provided for @materialIntakeRunCheck.
  ///
  /// In en, this message translates to:
  /// **'Check this request'**
  String get materialIntakeRunCheck;

  /// No description provided for @materialIntakeRunNote.
  ///
  /// In en, this message translates to:
  /// **'Checked and dry-run only, nothing is written; a valid request gets the dry run button. The photo path and this one look at the same checks.'**
  String get materialIntakeRunNote;

  /// No description provided for @materialIntakeRunGraphFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the graph inventory: {message} (it says which ids already exist)'**
  String materialIntakeRunGraphFailed(String message);

  /// No description provided for @materialPhotoReportTitle.
  ///
  /// In en, this message translates to:
  /// **'The request read from the photo'**
  String get materialPhotoReportTitle;

  /// No description provided for @materialPhotoReportValid.
  ///
  /// In en, this message translates to:
  /// **'Structurally valid: no hard errors'**
  String get materialPhotoReportValid;

  /// No description provided for @materialPhotoReportInvalid.
  ///
  /// In en, this message translates to:
  /// **'Structurally invalid: the whole request is refused'**
  String get materialPhotoReportInvalid;

  /// No description provided for @materialPhotoReportSize.
  ///
  /// In en, this message translates to:
  /// **'Image sent: {width}×{height}'**
  String materialPhotoReportSize(int width, int height);

  /// No description provided for @materialPhotoReportCounts.
  ///
  /// In en, this message translates to:
  /// **'{actions} actions · {evidence} with evidence'**
  String materialPhotoReportCounts(int actions, int evidence);

  /// No description provided for @materialPhotoReportErrors.
  ///
  /// In en, this message translates to:
  /// **'Hard errors (each one refuses the whole request)'**
  String get materialPhotoReportErrors;

  /// No description provided for @materialPhotoReportPreviews.
  ///
  /// In en, this message translates to:
  /// **'What it would do'**
  String get materialPhotoReportPreviews;

  /// No description provided for @materialPhotoReportWarnings.
  ///
  /// In en, this message translates to:
  /// **'Suggestions (not blocking)'**
  String get materialPhotoReportWarnings;

  /// No description provided for @materialPhotoReportRaw.
  ///
  /// In en, this message translates to:
  /// **'What the model said'**
  String get materialPhotoReportRaw;

  /// No description provided for @materialPhotoReportNoRaw.
  ///
  /// In en, this message translates to:
  /// **'(no answer)'**
  String get materialPhotoReportNoRaw;

  /// No description provided for @materialPhotoReportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read it'**
  String get materialPhotoReportFailed;

  /// No description provided for @materialPhotoReportPickAnother.
  ///
  /// In en, this message translates to:
  /// **'Pick another'**
  String get materialPhotoReportPickAnother;

  /// No description provided for @materialPhotoReportRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get materialPhotoReportRetry;

  /// No description provided for @materialPhotoReportRehearse.
  ///
  /// In en, this message translates to:
  /// **'Run it once (writes nothing)'**
  String get materialPhotoReportRehearse;

  /// No description provided for @materialPhotoReportEditAndRun.
  ///
  /// In en, this message translates to:
  /// **'Edit it and run it'**
  String get materialPhotoReportEditAndRun;

  /// No description provided for @materialIntakeRunDialogTitleEdited.
  ///
  /// In en, this message translates to:
  /// **'Edit it and run it (the same run/1)'**
  String get materialIntakeRunDialogTitleEdited;

  /// No description provided for @materialPhotoReportRehearseBusy.
  ///
  /// In en, this message translates to:
  /// **'Running it through…'**
  String get materialPhotoReportRehearseBusy;

  /// No description provided for @materialPhotoReportRehearseFailed.
  ///
  /// In en, this message translates to:
  /// **'The dry run stopped'**
  String get materialPhotoReportRehearseFailed;

  /// No description provided for @materialPhotoReportRehearseHeader.
  ///
  /// In en, this message translates to:
  /// **'Dry run (run only, nothing written)'**
  String get materialPhotoReportRehearseHeader;

  /// No description provided for @materialPhotoReportRehearseNote.
  ///
  /// In en, this message translates to:
  /// **'Read-only: no knowledge points, no edges and no review records are touched. Actually applying this request is a different step.'**
  String get materialPhotoReportRehearseNote;

  /// No description provided for @materialPhotoReportRehearseTrails.
  ///
  /// In en, this message translates to:
  /// **'Where each action landed'**
  String get materialPhotoReportRehearseTrails;

  /// No description provided for @materialPhotoReportRehearseNoMs.
  ///
  /// In en, this message translates to:
  /// **'No model reading for these nodes (the engine assumes the 0.8 default): {ids}'**
  String materialPhotoReportRehearseNoMs(String ids);

  /// No description provided for @materialPhotoReportRehearseUnknown.
  ///
  /// In en, this message translates to:
  /// **'These node ids are not in the library and no action creates them: {ids}'**
  String materialPhotoReportRehearseUnknown(String ids);

  /// No description provided for @materialPhotoReportHandOver.
  ///
  /// In en, this message translates to:
  /// **'Hand the new things over for confirmation (list only)'**
  String get materialPhotoReportHandOver;

  /// No description provided for @materialPhotoReportHandOverBusy.
  ///
  /// In en, this message translates to:
  /// **'Recording…'**
  String get materialPhotoReportHandOverBusy;

  /// No description provided for @materialPhotoReportHandOverNote.
  ///
  /// In en, this message translates to:
  /// **'This step writes exactly two list tables (`material_intake_batches` / `material_intake_proposals`): `knowledge_points` / `knowledge_edges` are not touched — they are only really created when you confirm them in the pending list right below on this page. Pressing it again for the same run yields the same batch.'**
  String get materialPhotoReportHandOverNote;

  /// No description provided for @materialPhotoReportHandOverDone.
  ///
  /// In en, this message translates to:
  /// **'Recorded as a pending batch ({batchId}) — it is right below on this page.'**
  String materialPhotoReportHandOverDone(String batchId);

  /// No description provided for @materialPhotoReportHandOverOpen.
  ///
  /// In en, this message translates to:
  /// **'Go see that batch ({count} waiting)'**
  String materialPhotoReportHandOverOpen(int count);

  /// No description provided for @materialPhotoReportHandOverFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not record it: {message}'**
  String materialPhotoReportHandOverFailed(String message);

  /// No description provided for @materialIntakeRunDetailLink.
  ///
  /// In en, this message translates to:
  /// **'What that run actually did'**
  String get materialIntakeRunDetailLink;

  /// No description provided for @materialIntakeRunDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'What that run actually did (read only)'**
  String get materialIntakeRunDetailTitle;

  /// No description provided for @materialIntakeTopicHubs.
  ///
  /// In en, this message translates to:
  /// **'Also create topic hubs (off by default: a topic groups things, it is not a card relation)'**
  String get materialIntakeTopicHubs;

  /// No description provided for @materialIntakePendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Pending list ({count} batches, survives closing the page)'**
  String materialIntakePendingTitle(int count);

  /// No description provided for @materialIntakePendingHint.
  ///
  /// In en, this message translates to:
  /// **'These were looked at but never confirmed: resuming shows exactly the batch you saw (nothing is recomputed), and knowledge points and clue edges are written only after you confirm.'**
  String get materialIntakePendingHint;

  /// No description provided for @materialIntakePendingBatch.
  ///
  /// In en, this message translates to:
  /// **'{batch}: {count} pending'**
  String materialIntakePendingBatch(int count, String batch);

  /// No description provided for @materialIntakeRestore.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get materialIntakeRestore;

  /// No description provided for @materialIntakeDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirmed ({count} batches)'**
  String materialIntakeDoneTitle(int count);

  /// No description provided for @materialIntakeDoneHint.
  ///
  /// In en, this message translates to:
  /// **'Nothing left to confirm here; to change them go where they landed — knowledge points in the manage page, clue edges in a point\'s detail.'**
  String get materialIntakeDoneHint;

  /// No description provided for @materialIntakeDoneBatch.
  ///
  /// In en, this message translates to:
  /// **'{batch}: {count} confirmed'**
  String materialIntakeDoneBatch(int count, String batch);

  /// No description provided for @materialIntakeDoneOpen.
  ///
  /// In en, this message translates to:
  /// **'See what was confirmed'**
  String get materialIntakeDoneOpen;

  /// No description provided for @materialIntakeDoneDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'What this batch confirmed ({batch})'**
  String materialIntakeDoneDialogTitle(String batch);

  /// No description provided for @materialIntakeDoneNote.
  ///
  /// In en, this message translates to:
  /// **'These are in the database: knowledge points in knowledge_points, connections as clue edges in knowledge_edges (ls uncalibrated). Rows marked \"already exists - no duplicate\" were in the library when you confirmed; the rest were written just now.'**
  String get materialIntakeDoneNote;

  /// No description provided for @materialIntakeUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo this batch'**
  String get materialIntakeUndo;

  /// No description provided for @materialIntakeUndoTitle.
  ///
  /// In en, this message translates to:
  /// **'Undo this batch?'**
  String get materialIntakeUndoTitle;

  /// No description provided for @materialIntakeUndoBody.
  ///
  /// In en, this message translates to:
  /// **'The knowledge points and clue edges this batch created will be deleted and the proposals go back to pending. Rows that were already in the library when you confirmed, plus any cards, tags or other clue edges, are left untouched. If even one row cannot be undone, the whole batch stays as it is and you get the reasons.'**
  String get materialIntakeUndoBody;

  /// No description provided for @materialIntakeUndoConfirm.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get materialIntakeUndoConfirm;

  /// No description provided for @materialIntakeUndone.
  ///
  /// In en, this message translates to:
  /// **'Undone: deleted {points} knowledge points and {edges} clue edges; {restored} proposals are back to pending.'**
  String materialIntakeUndone(int points, int edges, int restored);

  /// No description provided for @materialIntakeUndoneNothing.
  ///
  /// In en, this message translates to:
  /// **'This batch created nothing of its own: {restored} proposals are back to pending.'**
  String materialIntakeUndoneNothing(int restored);

  /// No description provided for @materialIntakeUndoLogLine.
  ///
  /// In en, this message translates to:
  /// **'This batch has been undone {count} time(s) before.'**
  String materialIntakeUndoLogLine(int count);

  /// No description provided for @materialIntakeUndoLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Undo log'**
  String get materialIntakeUndoLogTitle;

  /// No description provided for @materialIntakeUndoLogNote.
  ///
  /// In en, this message translates to:
  /// **'Every undo attempt leaves an entry: what it deleted, or why it did not (nothing in the library changed).'**
  String get materialIntakeUndoLogNote;

  /// No description provided for @materialIntakeUndoLogDone.
  ///
  /// In en, this message translates to:
  /// **'Undone'**
  String get materialIntakeUndoLogDone;

  /// No description provided for @materialIntakeUndoLogNotDone.
  ///
  /// In en, this message translates to:
  /// **'Not undone'**
  String get materialIntakeUndoLogNotDone;

  /// No description provided for @materialIntakeUndoLogBlocked.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason} ({count} reason(s) at the time)'**
  String materialIntakeUndoLogBlocked(String reason, int count);

  /// No description provided for @materialIntakeUndoBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'This batch cannot be undone'**
  String get materialIntakeUndoBlockedTitle;

  /// No description provided for @materialIntakeUndoBlockedNote.
  ///
  /// In en, this message translates to:
  /// **'Nothing was deleted. Undo only deletes what this batch created itself, and these rows have other things attached:'**
  String get materialIntakeUndoBlockedNote;

  /// No description provided for @materialIntakeUndoBlockedRow.
  ///
  /// In en, this message translates to:
  /// **'{title} - {reason}'**
  String materialIntakeUndoBlockedRow(String title, String reason);

  /// No description provided for @materialIntakeBadEnvelope.
  ///
  /// In en, this message translates to:
  /// **'Rejected as a whole: {error}'**
  String materialIntakeBadEnvelope(String error);

  /// No description provided for @materialIntakeProposals.
  ///
  /// In en, this message translates to:
  /// **'{count} proposals'**
  String materialIntakeProposals(int count);

  /// No description provided for @materialIntakeSkipped.
  ///
  /// In en, this message translates to:
  /// **'{count} stayed outside the list'**
  String materialIntakeSkipped(int count);

  /// No description provided for @materialIntakePending.
  ///
  /// In en, this message translates to:
  /// **'Saved as pending ({count} rows); closing this page does not lose them'**
  String materialIntakePending(int count);

  /// No description provided for @materialIntakeNothingToDo.
  ///
  /// In en, this message translates to:
  /// **'This batch has nothing to change: every item stayed outside the graph, and each skipped row says why.'**
  String get materialIntakeNothingToDo;

  /// No description provided for @materialIntakeKindPoint.
  ///
  /// In en, this message translates to:
  /// **'knowledge point'**
  String get materialIntakeKindPoint;

  /// No description provided for @materialIntakeKindConnection.
  ///
  /// In en, this message translates to:
  /// **'connection'**
  String get materialIntakeKindConnection;

  /// No description provided for @materialIntakeConnectionClue.
  ///
  /// In en, this message translates to:
  /// **'clue edge: strictly directed, ls uncalibrated'**
  String get materialIntakeConnectionClue;

  /// No description provided for @materialIntakeExisting.
  ///
  /// In en, this message translates to:
  /// **'already exists - no duplicate'**
  String get materialIntakeExisting;

  /// No description provided for @materialIntakeRename.
  ///
  /// In en, this message translates to:
  /// **'Edit this one'**
  String get materialIntakeRename;

  /// No description provided for @materialIntakeRenameDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit this one (not confirmed yet)'**
  String get materialIntakeRenameDialogTitle;

  /// No description provided for @materialIntakeRenameField.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get materialIntakeRenameField;

  /// No description provided for @materialIntakeRenameSave.
  ///
  /// In en, this message translates to:
  /// **'Save it'**
  String get materialIntakeRenameSave;

  /// No description provided for @materialIntakeEditBody.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get materialIntakeEditBody;

  /// No description provided for @materialIntakeEditBodyHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. the meaning, an example sentence, the original text - fill in what the machine missed'**
  String get materialIntakeEditBodyHint;

  /// No description provided for @materialIntakeProposalBody.
  ///
  /// In en, this message translates to:
  /// **'Body: {body}'**
  String materialIntakeProposalBody(String body);

  /// No description provided for @materialIntakeCantLand.
  ///
  /// In en, this message translates to:
  /// **'cannot land yet: {reason} (get that end into the graph first)'**
  String materialIntakeCantLand(String reason);

  /// No description provided for @materialIntakeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm and write ({count})'**
  String materialIntakeConfirm(int count);

  /// No description provided for @materialIntakeApplied.
  ///
  /// In en, this message translates to:
  /// **'Wrote {created} rows (knowledge points and clue edges), {existing} already existed, {deferred} connections could not land, {remaining} still pending'**
  String materialIntakeApplied(
      int created, int existing, int deferred, int remaining);

  /// No description provided for @materialIntakeFrom.
  ///
  /// In en, this message translates to:
  /// **'Source: {source} · {region}'**
  String materialIntakeFrom(String source, String region);

  /// No description provided for @materialIntakeQuote.
  ///
  /// In en, this message translates to:
  /// **'margin: “{quote}”'**
  String materialIntakeQuote(String quote);

  /// No description provided for @materialIntakeNoSource.
  ///
  /// In en, this message translates to:
  /// **'no source recorded'**
  String get materialIntakeNoSource;

  /// No description provided for @reviewPlanNewCardsPerDay.
  ///
  /// In en, this message translates to:
  /// **'New cards per day'**
  String get reviewPlanNewCardsPerDay;

  /// No description provided for @reviewPlanReviewCardsPerDay.
  ///
  /// In en, this message translates to:
  /// **'Reviews per day'**
  String get reviewPlanReviewCardsPerDay;

  /// No description provided for @reviewPlanZeroIsUnlimited.
  ///
  /// In en, this message translates to:
  /// **'0 new cards per day means no new cards today; 0 or empty reviews per day means no review limit. A card answered wrong today still comes back.'**
  String get reviewPlanZeroIsUnlimited;

  /// No description provided for @reviewPlanTarget.
  ///
  /// In en, this message translates to:
  /// **'Target: {newCards} new · {reviewCards} reviews'**
  String reviewPlanTarget(int newCards, int reviewCards);

  /// No description provided for @reviewPlanDoneToday.
  ///
  /// In en, this message translates to:
  /// **'Done today: {count}'**
  String reviewPlanDoneToday(int count);

  /// No description provided for @reviewPlanNewRemaining.
  ///
  /// In en, this message translates to:
  /// **'New cards left: {count}'**
  String reviewPlanNewRemaining(int count);

  /// No description provided for @reviewPlanRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining allowance: {count}'**
  String reviewPlanRemaining(int count);

  /// No description provided for @reviewPlanReviewsUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Remaining allowance: no limit'**
  String get reviewPlanReviewsUnlimited;

  /// No description provided for @reviewPlanNewCardsNormal.
  ///
  /// In en, this message translates to:
  /// **'Today\'s allowance is still open.'**
  String get reviewPlanNewCardsNormal;

  /// No description provided for @reviewPlanNewCardsStopped.
  ///
  /// In en, this message translates to:
  /// **'New-card allowance used up: no more new cards from this group today.'**
  String get reviewPlanNewCardsStopped;

  /// No description provided for @reviewPlanReviewsStopped.
  ///
  /// In en, this message translates to:
  /// **'Review allowance used up: that is today\'s reviews, come back tomorrow.'**
  String get reviewPlanReviewsStopped;

  /// No description provided for @reviewPlanEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit target'**
  String get reviewPlanEdit;

  /// No description provided for @reviewPlanClear.
  ///
  /// In en, this message translates to:
  /// **'Remove target (back to no limit)'**
  String get reviewPlanClear;

  /// No description provided for @ankiAutoBlankUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Cannot build a card for the current type preference: this content does not have enough to blank out'**
  String get ankiAutoBlankUnsupported;

  /// No description provided for @packagesImport.
  ///
  /// In en, this message translates to:
  /// **'Import .kpak'**
  String get packagesImport;

  /// No description provided for @packagesExport.
  ///
  /// In en, this message translates to:
  /// **'Export .kpak'**
  String get packagesExport;

  /// No description provided for @packagesImported.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get packagesImported;

  /// No description provided for @packagesExportName.
  ///
  /// In en, this message translates to:
  /// **'Library name'**
  String get packagesExportName;

  /// No description provided for @packagesExportAuthor.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get packagesExportAuthor;

  /// No description provided for @packagesVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get packagesVersion;

  /// No description provided for @packagesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No packages yet'**
  String get packagesEmpty;

  /// No description provided for @packagesPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Import preview'**
  String get packagesPreviewTitle;

  /// No description provided for @packagesImportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get packagesImportConfirm;

  /// No description provided for @privacyExportNote.
  ///
  /// In en, this message translates to:
  /// **'The exported file does not contain your events, schedule, or review progress.'**
  String get privacyExportNote;

  /// No description provided for @packagesUpgrade.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get packagesUpgrade;

  /// No description provided for @packagesDefaultName.
  ///
  /// In en, this message translates to:
  /// **'My Library'**
  String get packagesDefaultName;

  /// No description provided for @packagesDefaultAuthor.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get packagesDefaultAuthor;

  /// No description provided for @packagesInstalledTitle.
  ///
  /// In en, this message translates to:
  /// **'Imported packages'**
  String get packagesInstalledTitle;

  /// No description provided for @packagesScopeLabel.
  ///
  /// In en, this message translates to:
  /// **'Export scope'**
  String get packagesScopeLabel;

  /// No description provided for @packagesScopeAll.
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get packagesScopeAll;

  /// No description provided for @packagesScopeByTag.
  ///
  /// In en, this message translates to:
  /// **'Filter by tags'**
  String get packagesScopeByTag;

  /// No description provided for @packagesScopeHint.
  ///
  /// In en, this message translates to:
  /// **'Filtering by tags exports only the flashcards under those tags, and no mind maps.'**
  String get packagesScopeHint;

  /// No description provided for @packagesSelectTags.
  ///
  /// In en, this message translates to:
  /// **'Select tags'**
  String get packagesSelectTags;

  /// No description provided for @packagesNoTags.
  ///
  /// In en, this message translates to:
  /// **'No tags yet, so there is nothing to filter by'**
  String get packagesNoTags;

  /// No description provided for @packagesItemsCount.
  ///
  /// In en, this message translates to:
  /// **'items'**
  String get packagesItemsCount;

  /// No description provided for @packagesCardTemplates.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get packagesCardTemplates;

  /// No description provided for @packagesImportedAt.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get packagesImportedAt;

  /// No description provided for @packagesVersionHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 1.0.0'**
  String get packagesVersionHint;

  /// No description provided for @tagsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tags yet'**
  String get tagsEmpty;

  /// No description provided for @tagsNewTop.
  ///
  /// In en, this message translates to:
  /// **'New top-level tag'**
  String get tagsNewTop;

  /// No description provided for @tagsNewChild.
  ///
  /// In en, this message translates to:
  /// **'New under \"{parent}\"'**
  String tagsNewChild(String parent);

  /// No description provided for @tagsNameHint.
  ///
  /// In en, this message translates to:
  /// **'The name cannot contain / (hierarchy comes from nesting)'**
  String get tagsNameHint;

  /// No description provided for @tagsRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get tagsRename;

  /// No description provided for @tagsAddChild.
  ///
  /// In en, this message translates to:
  /// **'New child tag'**
  String get tagsAddChild;

  /// No description provided for @tagsExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get tagsExpand;

  /// No description provided for @tagsCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get tagsCollapse;

  /// No description provided for @tagsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{label}\"?'**
  String tagsDeleteTitle(String label);

  /// No description provided for @tagsDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Its whole subtree is deleted, and events/items carrying this tag lose it.'**
  String get tagsDeleteBody;

  /// No description provided for @threadTitle.
  ///
  /// In en, this message translates to:
  /// **'Thread'**
  String get threadTitle;

  /// No description provided for @threadSort.
  ///
  /// In en, this message translates to:
  /// **'Update & sort'**
  String get threadSort;

  /// No description provided for @threadRhythmReading.
  ///
  /// In en, this message translates to:
  /// **'Attention {percent}% · {minutes} min in'**
  String threadRhythmReading(int percent, int minutes);

  /// No description provided for @threadRhythmAdviceHard.
  ///
  /// In en, this message translates to:
  /// **'Good moment for the hard stuff'**
  String get threadRhythmAdviceHard;

  /// No description provided for @threadRhythmAdviceModerate.
  ///
  /// In en, this message translates to:
  /// **'Keep the normal pace'**
  String get threadRhythmAdviceModerate;

  /// No description provided for @threadRhythmAdviceRest.
  ///
  /// In en, this message translates to:
  /// **'Time for a break'**
  String get threadRhythmAdviceRest;

  /// No description provided for @threadRhythmEmpty.
  ///
  /// In en, this message translates to:
  /// **'Not enough study history yet - do a few cards first'**
  String get threadRhythmEmpty;

  /// No description provided for @threadRhythmHide.
  ///
  /// In en, this message translates to:
  /// **'Hide this reading'**
  String get threadRhythmHide;

  /// No description provided for @threadRhythmUncalibrated.
  ///
  /// In en, this message translates to:
  /// **'Rhythm parameters are uncalibrated; a hint, not a measurement'**
  String get threadRhythmUncalibrated;

  /// No description provided for @threadRhythmToggle.
  ///
  /// In en, this message translates to:
  /// **'Attention availability'**
  String get threadRhythmToggle;

  /// No description provided for @threadCognitiveRankToggle.
  ///
  /// In en, this message translates to:
  /// **'Cognitive ordering (goal + just reviewed)'**
  String get threadCognitiveRankToggle;

  /// No description provided for @threadCognitiveRankNote.
  ///
  /// In en, this message translates to:
  /// **'Cognitive ordering is on: tasks closer to the current goal or to just-reviewed knowledge points come first; the boosts are uncalibrated - a hint, not a measurement'**
  String get threadCognitiveRankNote;

  /// No description provided for @threadNeedsSort.
  ///
  /// In en, this message translates to:
  /// **'Needs re-sorting'**
  String get threadNeedsSort;

  /// No description provided for @threadNoEvents.
  ///
  /// In en, this message translates to:
  /// **'No events yet'**
  String get threadNoEvents;

  /// No description provided for @threadGoal.
  ///
  /// In en, this message translates to:
  /// **'Main goal'**
  String get threadGoal;

  /// No description provided for @threadGoalEmpty.
  ///
  /// In en, this message translates to:
  /// **'No goal set'**
  String get threadGoalEmpty;

  /// No description provided for @threadEnergy.
  ///
  /// In en, this message translates to:
  /// **'Energy'**
  String get threadEnergy;

  /// No description provided for @threadEnergyEmpty.
  ///
  /// In en, this message translates to:
  /// **'Energy not set'**
  String get threadEnergyEmpty;

  /// No description provided for @threadEnergy1.
  ///
  /// In en, this message translates to:
  /// **'Very low · mechanical chores only'**
  String get threadEnergy1;

  /// No description provided for @threadEnergy3.
  ///
  /// In en, this message translates to:
  /// **'Low · light tasks'**
  String get threadEnergy3;

  /// No description provided for @threadEnergy5.
  ///
  /// In en, this message translates to:
  /// **'Medium · routine work'**
  String get threadEnergy5;

  /// No description provided for @threadEnergy7.
  ///
  /// In en, this message translates to:
  /// **'High · needs focus'**
  String get threadEnergy7;

  /// No description provided for @threadEnergy9.
  ///
  /// In en, this message translates to:
  /// **'Very high · deep push'**
  String get threadEnergy9;

  /// No description provided for @threadStaleTitle.
  ///
  /// In en, this message translates to:
  /// **'State may be outdated'**
  String get threadStaleTitle;

  /// No description provided for @threadStaleBody.
  ///
  /// In en, this message translates to:
  /// **'More than 2 hours since the last update. Confirm to sort with the current state.'**
  String get threadStaleBody;

  /// No description provided for @threadArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get threadArchive;

  /// No description provided for @threadArchiveCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get threadArchiveCompleted;

  /// No description provided for @threadArchiveInsufficient.
  ///
  /// In en, this message translates to:
  /// **'Not enough time'**
  String get threadArchiveInsufficient;

  /// No description provided for @threadArchiveOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get threadArchiveOverdue;

  /// No description provided for @threadInsufficientDetail.
  ///
  /// In en, this message translates to:
  /// **'needs {needed} min, {available} min available'**
  String threadInsufficientDetail(String needed, String available);

  /// No description provided for @threadArchiveEmpty.
  ///
  /// In en, this message translates to:
  /// **'Archive is empty'**
  String get threadArchiveEmpty;

  /// No description provided for @threadDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\"?'**
  String threadDeleteTitle(String title);

  /// No description provided for @threadDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This event is deleted permanently (subtasks and dependencies go with it). It cannot be undone.'**
  String get threadDeleteBody;

  /// No description provided for @threadCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse status bar'**
  String get threadCollapse;

  /// No description provided for @threadExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand status bar'**
  String get threadExpand;

  /// No description provided for @propAlgorithm.
  ///
  /// In en, this message translates to:
  /// **'Ranking parameters'**
  String get propAlgorithm;

  /// No description provided for @propAlgorithmNoData.
  ///
  /// In en, this message translates to:
  /// **'No ranking yet - press \"Update & sort\" in the status bar first.'**
  String get propAlgorithmNoData;

  /// No description provided for @propUrgency.
  ///
  /// In en, this message translates to:
  /// **'Urgency'**
  String get propUrgency;

  /// No description provided for @propUrgencyHint.
  ///
  /// In en, this message translates to:
  /// **'Countdown to the deadline: it climbs faster the closer the deadline is, and reads full marks when overdue or within 15 minutes.'**
  String get propUrgencyHint;

  /// No description provided for @propGoalMatch.
  ///
  /// In en, this message translates to:
  /// **'Goal match'**
  String get propGoalMatch;

  /// No description provided for @propGoalMatchHint.
  ///
  /// In en, this message translates to:
  /// **'How much this event\'s tags overlap with the current goal text. No goal or no tags means 0.'**
  String get propGoalMatchHint;

  /// No description provided for @propFit.
  ///
  /// In en, this message translates to:
  /// **'State fit'**
  String get propFit;

  /// No description provided for @propFitHint.
  ///
  /// In en, this message translates to:
  /// **'Average of \"energy required vs your energy now\" and \"estimate vs the next free window\".'**
  String get propFitHint;

  /// No description provided for @propExpectedPressure.
  ///
  /// In en, this message translates to:
  /// **'Expected pressure'**
  String get propExpectedPressure;

  /// No description provided for @propExpectedPressureHint.
  ///
  /// In en, this message translates to:
  /// **'Derived from the expected moment: rises as it approaches, stays saturated while just past it, then decays back to 0.'**
  String get propExpectedPressureHint;

  /// No description provided for @propFatigue.
  ///
  /// In en, this message translates to:
  /// **'Fatigue penalty'**
  String get propFatigue;

  /// No description provided for @propFatigueHint.
  ///
  /// In en, this message translates to:
  /// **'If you just did something with the same tag within the last hour, points are deducted on a time decay so you do not chain the same kind of work.'**
  String get propFatigueHint;

  /// No description provided for @propTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get propTotal;

  /// No description provided for @propFlagInsufficient.
  ///
  /// In en, this message translates to:
  /// **'Currently flagged \"not enough time\" and moved out of the main list.'**
  String get propFlagInsufficient;

  /// No description provided for @propFlagOverdue.
  ///
  /// In en, this message translates to:
  /// **'Currently flagged \"overdue\" and moved out of the main list.'**
  String get propFlagOverdue;

  /// No description provided for @propFlagExpectedNear.
  ///
  /// In en, this message translates to:
  /// **'Currently flagged yellow: the expected moment is near or already past.'**
  String get propFlagExpectedNear;

  /// No description provided for @propWeights.
  ///
  /// In en, this message translates to:
  /// **'Ranking weights'**
  String get propWeights;

  /// No description provided for @propWeightsHint.
  ///
  /// In en, this message translates to:
  /// **'Weights apply to all events, not just this one. Saving re-sorts automatically.'**
  String get propWeightsHint;

  /// No description provided for @propResetWeights.
  ///
  /// In en, this message translates to:
  /// **'Restore default weights'**
  String get propResetWeights;

  /// No description provided for @knowledgeRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count} left'**
  String knowledgeRemaining(int count);

  /// No description provided for @knowledgeActiveCount.
  ///
  /// In en, this message translates to:
  /// **'{count} to clear'**
  String knowledgeActiveCount(int count);

  /// No description provided for @knowledgeSessionDone.
  ///
  /// In en, this message translates to:
  /// **'This round is done'**
  String get knowledgeSessionDone;

  /// No description provided for @knowledgeWillRepeat.
  ///
  /// In en, this message translates to:
  /// **'Wrong: this blank will come back today until you get it right twice in a row.'**
  String get knowledgeWillRepeat;

  /// No description provided for @knowledgeForcedWait.
  ///
  /// In en, this message translates to:
  /// **'You got this blank right once - it comes back in {minutes} min.'**
  String knowledgeForcedWait(int minutes);

  /// No description provided for @knowledgeForcedWaitCheck.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get knowledgeForcedWaitCheck;

  /// No description provided for @knowledgeNewBlank.
  ///
  /// In en, this message translates to:
  /// **'New blank'**
  String get knowledgeNewBlank;

  /// No description provided for @knowledgeNextIn.
  ///
  /// In en, this message translates to:
  /// **'Next review in {days} day(s)'**
  String knowledgeNextIn(int days);

  /// No description provided for @knowledgeBoosted.
  ///
  /// In en, this message translates to:
  /// **'{count} related item(s) lifted too (up to x{factor})'**
  String knowledgeBoosted(int count, String factor);

  /// No description provided for @knowledgeCreateTask.
  ///
  /// In en, this message translates to:
  /// **'Create event'**
  String get knowledgeCreateTask;

  /// No description provided for @knowledgeTaskCreated.
  ///
  /// In en, this message translates to:
  /// **'Event created'**
  String get knowledgeTaskCreated;

  /// No description provided for @knowledgeInsight.
  ///
  /// In en, this message translates to:
  /// **'Today\'s review'**
  String get knowledgeInsight;

  /// No description provided for @knowledgeMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get knowledgeMoreActions;

  /// No description provided for @knowledgeReviewTab.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get knowledgeReviewTab;

  /// No description provided for @knowledgeInsightEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded today'**
  String get knowledgeInsightEmpty;

  /// No description provided for @knowledgeInsightWrong.
  ///
  /// In en, this message translates to:
  /// **'Went wrong'**
  String get knowledgeInsightWrong;

  /// No description provided for @knowledgeInsightBoost.
  ///
  /// In en, this message translates to:
  /// **'Related items lifted'**
  String get knowledgeInsightBoost;

  /// No description provided for @knowledgeInsightDistance.
  ///
  /// In en, this message translates to:
  /// **'distance {distance}'**
  String knowledgeInsightDistance(int distance);

  /// No description provided for @knowledgeInsightFactor.
  ///
  /// In en, this message translates to:
  /// **'x{factor}'**
  String knowledgeInsightFactor(String factor);

  /// No description provided for @knowledgeEdges.
  ///
  /// In en, this message translates to:
  /// **'Clue edges'**
  String get knowledgeEdges;

  /// No description provided for @knowledgeEdgesIntro.
  ///
  /// In en, this message translates to:
  /// **'Connections from your material land here once you confirm them: strictly directed (A → B does not mean B → A), ls has no calibration source so it is always marked uncalibrated, and an end that is not in the library is shown by id.'**
  String get knowledgeEdgesIntro;

  /// No description provided for @knowledgeEdgesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No clue edges yet — connections from material only land here after you confirm them under \"Add material\".'**
  String get knowledgeEdgesEmpty;

  /// No description provided for @knowledgeEdgesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} clue edges'**
  String knowledgeEdgesCount(int count);

  /// No description provided for @knowledgeEdgesOriginContains.
  ///
  /// In en, this message translates to:
  /// **'the material stated containment'**
  String get knowledgeEdgesOriginContains;

  /// No description provided for @knowledgeEdgesOriginProduce.
  ///
  /// In en, this message translates to:
  /// **'the material stated production'**
  String get knowledgeEdgesOriginProduce;

  /// No description provided for @knowledgeEdgesOriginTopic.
  ///
  /// In en, this message translates to:
  /// **'topic grouping'**
  String get knowledgeEdgesOriginTopic;

  /// No description provided for @knowledgeEdgesOriginManual.
  ///
  /// In en, this message translates to:
  /// **'hand-written'**
  String get knowledgeEdgesOriginManual;

  /// No description provided for @knowledgeEdgesOriginMaterial.
  ///
  /// In en, this message translates to:
  /// **'material (relation not stated)'**
  String get knowledgeEdgesOriginMaterial;

  /// No description provided for @knowledgeEdgesLs.
  ///
  /// In en, this message translates to:
  /// **'ls {ls} (uncalibrated)'**
  String knowledgeEdgesLs(String ls);

  /// No description provided for @knowledgeEdgesLsCalibrated.
  ///
  /// In en, this message translates to:
  /// **'ls {ls}'**
  String knowledgeEdgesLsCalibrated(String ls);

  /// No description provided for @knowledgeEdgesNoLs.
  ///
  /// In en, this message translates to:
  /// **'the material gave no ls (none is claimed)'**
  String get knowledgeEdgesNoLs;

  /// No description provided for @knowledgeEdgesMissingEnd.
  ///
  /// In en, this message translates to:
  /// **'one end is not in the library, shown by id'**
  String get knowledgeEdgesMissingEnd;

  /// No description provided for @knowledgePointEdgesEmpty.
  ///
  /// In en, this message translates to:
  /// **'this knowledge point has no clue edges yet (they appear once a material connection is confirmed)'**
  String get knowledgePointEdgesEmpty;

  /// No description provided for @knowledgePointEdgesNotInGraph.
  ///
  /// In en, this message translates to:
  /// **'this knowledge point is not in the material graph (no external_id), so there are no edges to show'**
  String get knowledgePointEdgesNotInGraph;

  /// No description provided for @knowledgePointEdgesOutgoing.
  ///
  /// In en, this message translates to:
  /// **'points at: {other}'**
  String knowledgePointEdgesOutgoing(String other);

  /// No description provided for @knowledgePointEdgesIncoming.
  ///
  /// In en, this message translates to:
  /// **'pointed at by: {other}'**
  String knowledgePointEdgesIncoming(String other);

  /// No description provided for @knowledgeEdgeAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a clue edge'**
  String get knowledgeEdgeAdd;

  /// No description provided for @knowledgeEdgeAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Hand-write a clue edge'**
  String get knowledgeEdgeAddTitle;

  /// No description provided for @knowledgeEdgeDirectionOutgoing.
  ///
  /// In en, this message translates to:
  /// **'it points at…'**
  String get knowledgeEdgeDirectionOutgoing;

  /// No description provided for @knowledgeEdgeDirectionIncoming.
  ///
  /// In en, this message translates to:
  /// **'…points at it'**
  String get knowledgeEdgeDirectionIncoming;

  /// No description provided for @knowledgeEdgePickOther.
  ///
  /// In en, this message translates to:
  /// **'the other end'**
  String get knowledgeEdgePickOther;

  /// No description provided for @knowledgeEdgeNoOtherPoints.
  ///
  /// In en, this message translates to:
  /// **'no other knowledge point in the graph to connect to (hand-written points have no in-graph id)'**
  String get knowledgeEdgeNoOtherPoints;

  /// No description provided for @knowledgeEdgeCreated.
  ///
  /// In en, this message translates to:
  /// **'added a hand-written clue edge (ls stays empty — no calibration source, so none is claimed)'**
  String get knowledgeEdgeCreated;

  /// No description provided for @knowledgeEdgeAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'this direction already has an edge ({origin}); nothing was added'**
  String knowledgeEdgeAlreadyExists(String origin);

  /// No description provided for @knowledgeEdgeEndpointMissing.
  ///
  /// In en, this message translates to:
  /// **'both ends must already be in the graph; nothing was added'**
  String get knowledgeEdgeEndpointMissing;

  /// No description provided for @knowledgeEdgeSamePoint.
  ///
  /// In en, this message translates to:
  /// **'start and end are the same point; nothing was added'**
  String get knowledgeEdgeSamePoint;

  /// No description provided for @knowledgeEdgeDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'delete this hand-written edge'**
  String get knowledgeEdgeDeleteTooltip;

  /// No description provided for @knowledgeEdgeDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this hand-written clue edge?'**
  String get knowledgeEdgeDeleteConfirm;

  /// No description provided for @knowledgeEdgeDeleted.
  ///
  /// In en, this message translates to:
  /// **'deleted the hand-written edge'**
  String get knowledgeEdgeDeleted;

  /// No description provided for @knowledgeEdgeNotFound.
  ///
  /// In en, this message translates to:
  /// **'that edge is already gone'**
  String get knowledgeEdgeNotFound;

  /// No description provided for @knowledgeEdgeNotManual.
  ///
  /// In en, this message translates to:
  /// **'only hand-written edges can be deleted here (material edges belong to the material step)'**
  String get knowledgeEdgeNotManual;

  /// No description provided for @knowledgeEdgeWalkTitle.
  ///
  /// In en, this message translates to:
  /// **'What this point connects to ({point})'**
  String knowledgeEdgeWalkTitle(String point);

  /// No description provided for @knowledgeEdgeWalkHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a name to keep walking this line: whichever end you go to, you see that end\'s edges (read-only, nothing is created or deleted).'**
  String get knowledgeEdgeWalkHint;

  /// No description provided for @knowledgeEdgeWalkTooltip.
  ///
  /// In en, this message translates to:
  /// **'Walk along this edge to this end'**
  String get knowledgeEdgeWalkTooltip;

  /// No description provided for @settingsDemoData.
  ///
  /// In en, this message translates to:
  /// **'Load demo data'**
  String get settingsDemoData;

  /// No description provided for @settingsDemoDataHint.
  ///
  /// In en, this message translates to:
  /// **'Creates sample tags, flashcards, events and schedule blocks so the UI can be inspected right away.'**
  String get settingsDemoDataHint;

  /// No description provided for @settingsDemoDataConfirm.
  ///
  /// In en, this message translates to:
  /// **'Add the demo data to the current workspace?'**
  String get settingsDemoDataConfirm;

  /// No description provided for @settingsDemoDataBlocked.
  ///
  /// In en, this message translates to:
  /// **'The workspace already has content, so the demo data was not loaded (to avoid duplicates).'**
  String get settingsDemoDataBlocked;

  /// No description provided for @settingsDemoDataDone.
  ///
  /// In en, this message translates to:
  /// **'Demo data loaded'**
  String get settingsDemoDataDone;

  /// No description provided for @settingsCardGroups.
  ///
  /// In en, this message translates to:
  /// **'Deck settings'**
  String get settingsCardGroups;

  /// No description provided for @settingsCardGroupsHint.
  ///
  /// In en, this message translates to:
  /// **'A deck is a tag: give a tag a daily new/review cap and its whole subtree counts as that deck; grading mode and card type are changed here too.'**
  String get settingsCardGroupsHint;

  /// No description provided for @settingsQuestionBankHint.
  ///
  /// In en, this message translates to:
  /// **'Question overview, intake, paper assembly, photo cleanup and material intake all start here.'**
  String get settingsQuestionBankHint;

  /// No description provided for @settingsUsageDoc.
  ///
  /// In en, this message translates to:
  /// **'Usage guide'**
  String get settingsUsageDoc;

  /// No description provided for @settingsUsageDocHint.
  ///
  /// In en, this message translates to:
  /// **'How each part works and what its limits are: AI, review, knowledge base, question bank, photos/materials, cognitive model, ranking'**
  String get settingsUsageDocHint;

  /// No description provided for @docAiTitle.
  ///
  /// In en, this message translates to:
  /// **'What the assistant can do, and what waits for your consent'**
  String get docAiTitle;

  /// No description provided for @docAiBody.
  ///
  /// In en, this message translates to:
  /// **'The AI can only change data through tools, and every tool carries a risk level: read-only calls (query_tasks, query_schedule, query_content, fetch_page, evaluate_problem_fit, compose_paper, find_similar_questions, find_questions_by_capability, plan_today, review_metrics and friends) run immediately; writes (creating tags, flashcards, tasks, documents, material intake, applying today\'s plan...) wait for your consent in both the per-action and the plan-first modes; deletions ask every single time and can be undone. You see what a call will change before it runs and get one undo after it; the model never sees your API key, and skill scripts do not receive it either.'**
  String get docAiBody;

  /// No description provided for @docReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review and flashcards'**
  String get docReviewTitle;

  /// No description provided for @docReviewBody.
  ///
  /// In en, this message translates to:
  /// **'Flashcards hang off tags, and the tag tree is the deck: a daily new/review cap set on one tag covers its whole subtree (no row at all means no cap). Due dates come from FSRS alone - the cognitive model only changes what today\'s queue puts first. Grading can be strict, lenient or self-assessed; lenient ignores typos and word order, and a card you got wrong ignores the daily cap and comes back the same day. Deck settings live in Settings -> Deck settings (also reachable from the review screen\'s app bar). Cards with no tag belong to no group, so no daily target can reach them: the deck settings screen shows how many such cards exist and offers a one-tap \"put them all in one group\" fix, and the new-flashcard dialog can take a group up front.'**
  String get docReviewBody;

  /// No description provided for @docKnowledgeTitle.
  ///
  /// In en, this message translates to:
  /// **'Knowledge base and tags'**
  String get docKnowledgeTitle;

  /// No description provided for @docKnowledgeBody.
  ///
  /// In en, this message translates to:
  /// **'Tags form a tree, with / separating the levels. Deleting a tag also deletes its whole subtree together with the flashcards and review history inside it (the AI\'s delete tool asks for each one and leaves an undoable snapshot). Both card shapes - cards generated from a template and cards created directly per unit - count on the cognitive readings page, and the orphan banner there cleans up only when you press its button.'**
  String get docKnowledgeBody;

  /// No description provided for @docBankTitle.
  ///
  /// In en, this message translates to:
  /// **'Question bank and paper assembly'**
  String get docBankTitle;

  /// No description provided for @docBankBody.
  ///
  /// In en, this message translates to:
  /// **'The intake page turns pasted text or picked images into drafts for proofreading: the AI only structures them, and nothing is written until you press save, while an identical question (same stem fingerprint) points at the existing row instead of duplicating it. The paper page assembles a paper only from questions you already have (at-risk and developing points first); when it cannot fill the paper it lists the missing knowledge points honestly - the AI never writes questions. The paper can be copied out as printable plain text. On the cognitive model page the capability-move profile opens a read-only list of questions whose chains used a move.'**
  String get docBankBody;

  /// No description provided for @docMaterialTitle.
  ///
  /// In en, this message translates to:
  /// **'Photos, materials and rehearsal'**
  String get docMaterialTitle;

  /// No description provided for @docMaterialBody.
  ///
  /// In en, this message translates to:
  /// **'Photo intake turns one photo into four kinds of proposals - extra tags, flashcards, MindNet knowledge-point nodes and questions transcribed verbatim - and writes nothing before you confirm; material intake turns a piece of material into knowledge points / cards / connections, again only writing after you confirm, with an undo trail. A photo can also become a run/1 request carrying mechanism parameters: the mechanism panel lets you try or rehearse it, and a rehearsal only reports readings without touching your data. Saying \"do not install the goal mechanism\" really leaves it out.'**
  String get docMaterialBody;

  /// No description provided for @docTodayTitle.
  ///
  /// In en, this message translates to:
  /// **'What to do today, and when'**
  String get docTodayTitle;

  /// No description provided for @docTodayBody.
  ///
  /// In en, this message translates to:
  /// **'Today\'s list shows the cards due today; the rhythm layer reports alpha(tau) attention availability; conflicting tasks and schedule blocks are flagged and can be pushed back with one tap; the cognitive ranking tier only changes which card comes first, never due dates, and is recomputed only when you press the sort button. Counterfactual V(pi) and the retention probe likewise only affect ordering.'**
  String get docTodayBody;

  /// No description provided for @docCognitiveTitle.
  ///
  /// In en, this message translates to:
  /// **'How to read the cognitive model'**
  String get docCognitiveTitle;

  /// No description provided for @docCognitiveBody.
  ///
  /// In en, this message translates to:
  /// **'Cognitive model in settings is a read-only readings page: R is current memory strength, R0 is the strength right after learning, Sigma is accumulated effort, and the developing-zone / dead-end column is the tierB diffusion verdict on the tag graph (starts are the most recently reviewed points, targets are the ones due today); with no tags or no usable start and target it reads unavailable, which is not the same as healthy. \"Danger\" comes from the metacognition rows: it appears only when your self-rated confidence and your actual recall differ enough, and a missing verdict is not the same as healthy. The capability-move profile groups stuck risk by the moves on solved chains and answers which kind of move to practise; tapping a row lists the questions whose chains used it (read-only). At the top of the readings page there is a read-only knowledge-network view that draws knowledge points and tags as one graph (colour = cognitive zone, size = card count); tap a node to read it. The statements at the top record that it does not move due dates, that its parameters are uncalibrated and that it does not decide for you. The AI\'s evaluate_problem_fit tool reads the same numbers to judge whether a question is worth doing now.'**
  String get docCognitiveBody;

  /// No description provided for @docFormulaTitle.
  ///
  /// In en, this message translates to:
  /// **'How the score is computed'**
  String get docFormulaTitle;

  /// No description provided for @docFormulaBody.
  ///
  /// In en, this message translates to:
  /// **'Total = urgency x weight + goal match x weight + state fit x weight + expected pressure x weight - fatigue penalty x weight. Every component is between 0 and 1, the weights are normalized internally, so the total is between 0 and 1 as well. The order is only recomputed when you press the sort button - nothing changes in the background.'**
  String get docFormulaBody;

  /// No description provided for @docCurrentWeights.
  ///
  /// In en, this message translates to:
  /// **'Current weights (shipped values in brackets)'**
  String get docCurrentWeights;

  /// No description provided for @docWeightsNormalized.
  ///
  /// In en, this message translates to:
  /// **'Edited weights are normalized automatically: even if they do not add up to 1, the total never exceeds 1 because the ranker rescales by their sum.'**
  String get docWeightsNormalized;

  /// No description provided for @docStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Event bar edge colours'**
  String get docStatusTitle;

  /// No description provided for @docStatusBody.
  ///
  /// In en, this message translates to:
  /// **'Green = completed; blue = waiting (expected moment not reached); yellow = expected moment has passed; red = deadline has passed. The colour only expresses state and never changes the ordering.'**
  String get docStatusBody;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsAboutHint.
  ///
  /// In en, this message translates to:
  /// **'Version, data location, network egress, known gaps'**
  String get settingsAboutHint;

  /// No description provided for @aboutVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get aboutVersionLabel;

  /// No description provided for @aboutVersionValue.
  ///
  /// In en, this message translates to:
  /// **'{version} (build {build})'**
  String aboutVersionValue(String version, int build);

  /// No description provided for @aboutDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Where the data lives'**
  String get aboutDataTitle;

  /// No description provided for @aboutDataBody.
  ///
  /// In en, this message translates to:
  /// **'The database, skills, AI-written documents and image attachments all live under this directory. Backing up means copying furnace.db (or using \"Back up data\" above).'**
  String get aboutDataBody;

  /// No description provided for @aboutDataDirLabel.
  ///
  /// In en, this message translates to:
  /// **'Application data directory'**
  String get aboutDataDirLabel;

  /// No description provided for @aboutNetworkTitle.
  ///
  /// In en, this message translates to:
  /// **'Network egress'**
  String get aboutNetworkTitle;

  /// No description provided for @aboutNetworkBody.
  ///
  /// In en, this message translates to:
  /// **'Only two things reach the network on their own: (1) AI requests, sent to the endpoint you configured in AI settings - conversation text and images both go there; (2) fetch_page, which reads public pages with GET only, no cookies, refuses loopback and private addresses, follows at most 5 redirects and caps a body at 2 MiB. A skill\'s scripts run only if you switch its network permission on, and that switch decides whether the script runs at all - it does not block individual domains.'**
  String get aboutNetworkBody;

  /// No description provided for @aboutGapsTitle.
  ///
  /// In en, this message translates to:
  /// **'Known gaps'**
  String get aboutGapsTitle;

  /// No description provided for @aboutGapsBody.
  ///
  /// In en, this message translates to:
  /// **'(1) No DOCX / PDF output - create_document writes .md / .txt only; (2) a skill\'s networkAllow is a switch, not per-domain enforcement (that would need OS-level egress control); (3) skill scripts run on Windows only, so those tools are absent on Android; (4) the browser bridge (browser_bridge) is not implemented; (5) the cognitive model has only the memory tier and the fast scheduler wired up - the run/1 session protocol, metacognition and rhythm tiers are not (see docs/MINDNET_ROADMAP.md); (6) fetch_page cannot refuse a host whose address fails to resolve (recorded, unfixed).'**
  String get aboutGapsBody;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsThemeSystemEntry.
  ///
  /// In en, this message translates to:
  /// **'Follow the system'**
  String get settingsThemeSystemEntry;

  /// No description provided for @settingsThemeSystemHint.
  ///
  /// In en, this message translates to:
  /// **'Switch automatically with the system brightness (built-in themes)'**
  String get settingsThemeSystemHint;

  /// No description provided for @settingsThemeBuiltin.
  ///
  /// In en, this message translates to:
  /// **'Built-in theme'**
  String get settingsThemeBuiltin;

  /// No description provided for @settingsThemeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom theme'**
  String get settingsThemeCustom;

  /// No description provided for @settingsThemeImport.
  ///
  /// In en, this message translates to:
  /// **'Import theme'**
  String get settingsThemeImport;

  /// No description provided for @settingsThemeImportHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a .json theme file'**
  String get settingsThemeImportHint;

  /// No description provided for @settingsThemeImportInvalid.
  ///
  /// In en, this message translates to:
  /// **'Not a valid theme file (it must be JSON with fields like name and colors)'**
  String get settingsThemeImportInvalid;

  /// No description provided for @settingsThemeImported.
  ///
  /// In en, this message translates to:
  /// **'Imported theme \"{name}\"'**
  String settingsThemeImported(String name);

  /// No description provided for @settingsThemeExport.
  ///
  /// In en, this message translates to:
  /// **'Export theme'**
  String get settingsThemeExport;

  /// No description provided for @settingsThemeExported.
  ///
  /// In en, this message translates to:
  /// **'Theme exported'**
  String get settingsThemeExported;

  /// No description provided for @settingsThemeDeleted.
  ///
  /// In en, this message translates to:
  /// **'Theme deleted'**
  String get settingsThemeDeleted;

  /// No description provided for @settingsThemeBuiltinProtected.
  ///
  /// In en, this message translates to:
  /// **'Built-in themes cannot be deleted (editing saves a copy)'**
  String get settingsThemeBuiltinProtected;

  /// No description provided for @settingsThemeBuiltinHint.
  ///
  /// In en, this message translates to:
  /// **'This is a built-in theme. Saving stores a copy, so the shipped default stays untouched.'**
  String get settingsThemeBuiltinHint;

  /// No description provided for @settingsThemeEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit theme'**
  String get settingsThemeEdit;

  /// No description provided for @settingsThemeSaved.
  ///
  /// In en, this message translates to:
  /// **'Theme saved'**
  String get settingsThemeSaved;

  /// No description provided for @settingsThemeBrightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get settingsThemeBrightness;

  /// No description provided for @settingsThemePrimary.
  ///
  /// In en, this message translates to:
  /// **'Primary colour'**
  String get settingsThemePrimary;

  /// No description provided for @settingsThemeBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get settingsThemeBackground;

  /// No description provided for @settingsThemeOpacity.
  ///
  /// In en, this message translates to:
  /// **'Background opacity'**
  String get settingsThemeOpacity;

  /// No description provided for @settingsThemeScale.
  ///
  /// In en, this message translates to:
  /// **'Page scale'**
  String get settingsThemeScale;

  /// No description provided for @settingsThemeScaleHint.
  ///
  /// In en, this message translates to:
  /// **'80%-150%; affects body text and control sizes.'**
  String get settingsThemeScaleHint;

  /// No description provided for @settingsThemeAnimations.
  ///
  /// In en, this message translates to:
  /// **'Animations'**
  String get settingsThemeAnimations;

  /// No description provided for @settingsThemeAnimationsOn.
  ///
  /// In en, this message translates to:
  /// **'Animations enabled'**
  String get settingsThemeAnimationsOn;

  /// No description provided for @settingsThemeAnimationsOff.
  ///
  /// In en, this message translates to:
  /// **'Animations disabled'**
  String get settingsThemeAnimationsOff;

  /// No description provided for @settingsThemeFonts.
  ///
  /// In en, this message translates to:
  /// **'Fonts'**
  String get settingsThemeFonts;

  /// No description provided for @settingsThemeFontUi.
  ///
  /// In en, this message translates to:
  /// **'UI font (empty = system default)'**
  String get settingsThemeFontUi;

  /// No description provided for @settingsThemeFontEditor.
  ///
  /// In en, this message translates to:
  /// **'Body/editor font (empty = system default)'**
  String get settingsThemeFontEditor;

  /// No description provided for @settingsThemeFontHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a font family name. Importing font files is not implemented yet.'**
  String get settingsThemeFontHint;

  /// No description provided for @settingsData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get settingsData;

  /// No description provided for @settingsTfpkgExport.
  ///
  /// In en, this message translates to:
  /// **'Export workspace (.tfpkg)'**
  String get settingsTfpkgExport;

  /// No description provided for @settingsTfpkgExportHint.
  ///
  /// In en, this message translates to:
  /// **'Pack everything into one file for backup or moving machines'**
  String get settingsTfpkgExportHint;

  /// No description provided for @settingsTfpkgImport.
  ///
  /// In en, this message translates to:
  /// **'Import workspace (.tfpkg)'**
  String get settingsTfpkgImport;

  /// No description provided for @settingsTfpkgImportHint.
  ///
  /// In en, this message translates to:
  /// **'Restore from a .tfpkg; the current data is backed up first'**
  String get settingsTfpkgImportHint;

  /// No description provided for @settingsTfpkgImportPreview.
  ///
  /// In en, this message translates to:
  /// **'About to import: {rows} rows, {tables} tables, {themes} themes'**
  String settingsTfpkgImportPreview(int rows, int tables, int themes);

  /// No description provided for @settingsTfpkgMergeReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace (clear, then write)'**
  String get settingsTfpkgMergeReplace;

  /// No description provided for @settingsTfpkgMergeAppend.
  ///
  /// In en, this message translates to:
  /// **'Append (keep local, skip clashes)'**
  String get settingsTfpkgMergeAppend;

  /// No description provided for @settingsTfpkgImportDone.
  ///
  /// In en, this message translates to:
  /// **'Import finished: {rows} rows written'**
  String settingsTfpkgImportDone(int rows);

  /// No description provided for @settingsTfpkgExportDone.
  ///
  /// In en, this message translates to:
  /// **'Workspace exported'**
  String get settingsTfpkgExportDone;

  /// No description provided for @settingsTfpkgInvalid.
  ///
  /// In en, this message translates to:
  /// **'This is not a valid .tfpkg file'**
  String get settingsTfpkgInvalid;

  /// No description provided for @settingsTfpkgSkippedTables.
  ///
  /// In en, this message translates to:
  /// **'{count} table(s) came from a newer version and were skipped'**
  String settingsTfpkgSkippedTables(int count);

  /// No description provided for @settingsBackupNote.
  ///
  /// In en, this message translates to:
  /// **'This is a copy of the raw database file; prefer .tfpkg for regular backups.'**
  String get settingsBackupNote;

  /// No description provided for @navAi.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get navAi;

  /// No description provided for @aiTitle.
  ///
  /// In en, this message translates to:
  /// **'AI chat'**
  String get aiTitle;

  /// No description provided for @aiNewConversation.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get aiNewConversation;

  /// No description provided for @aiEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Just say what you need, for example: put next week revision into my schedule.'**
  String get aiEmptyHint;

  /// No description provided for @aiInputHint.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get aiInputHint;

  /// No description provided for @aiInputKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Enter sends · Shift+Enter adds a line break'**
  String get aiInputKeyHint;

  /// No description provided for @aiInputResizeHandle.
  ///
  /// In en, this message translates to:
  /// **'Drag up or down to resize the message box'**
  String get aiInputResizeHandle;

  /// No description provided for @aiShowConversationList.
  ///
  /// In en, this message translates to:
  /// **'Show the chat list'**
  String get aiShowConversationList;

  /// No description provided for @aiHideConversationList.
  ///
  /// In en, this message translates to:
  /// **'Hide the chat list'**
  String get aiHideConversationList;

  /// No description provided for @aiSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get aiSend;

  /// No description provided for @aiPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'These need your confirmation'**
  String get aiPendingTitle;

  /// No description provided for @aiApproveAll.
  ///
  /// In en, this message translates to:
  /// **'Run all'**
  String get aiApproveAll;

  /// No description provided for @aiRejectAll.
  ///
  /// In en, this message translates to:
  /// **'Reject all'**
  String get aiRejectAll;

  /// No description provided for @aiNeedsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Needs its own confirmation'**
  String get aiNeedsConfirm;

  /// No description provided for @aiAutoExecuted.
  ///
  /// In en, this message translates to:
  /// **'Ran automatically'**
  String get aiAutoExecuted;

  /// No description provided for @aiUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get aiUndo;

  /// No description provided for @aiUndone.
  ///
  /// In en, this message translates to:
  /// **'Undone'**
  String get aiUndone;

  /// No description provided for @aiNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'AI is not set up'**
  String get aiNotConfigured;

  /// No description provided for @aiNotConfiguredHint.
  ///
  /// In en, this message translates to:
  /// **'Add an API key in Settings > AI and the chat screen appears here. Until then the app makes no network request at all.'**
  String get aiNotConfiguredHint;

  /// No description provided for @aiGoToSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get aiGoToSettings;

  /// No description provided for @aiDeleteConversation.
  ///
  /// In en, this message translates to:
  /// **'Delete chat'**
  String get aiDeleteConversation;

  /// No description provided for @aiDeleteConversationConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this chat? This cannot be undone.'**
  String get aiDeleteConversationConfirm;

  /// No description provided for @aiAttachImage.
  ///
  /// In en, this message translates to:
  /// **'Attach image'**
  String get aiAttachImage;

  /// No description provided for @aiRemoveImage.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get aiRemoveImage;

  /// No description provided for @aiImageTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Image too large: even after compression it is over 4 MB, so it was not sent. Use a smaller image, or crop the parts you do not need.'**
  String get aiImageTooLarge;

  /// No description provided for @aiImageUnreadable.
  ///
  /// In en, this message translates to:
  /// **'This image could not be read: unsupported format or damaged file. Use PNG, JPG, WebP or GIF.'**
  String get aiImageUnreadable;

  /// No description provided for @aiUsageCurrent.
  ///
  /// In en, this message translates to:
  /// **'This turn'**
  String get aiUsageCurrent;

  /// No description provided for @aiUsageLast.
  ///
  /// In en, this message translates to:
  /// **'Last turn'**
  String get aiUsageLast;

  /// No description provided for @aiUsageRounds.
  ///
  /// In en, this message translates to:
  /// **'Rounds'**
  String get aiUsageRounds;

  /// No description provided for @aiUsageSteps.
  ///
  /// In en, this message translates to:
  /// **'Tool calls'**
  String get aiUsageSteps;

  /// No description provided for @aiUsageTotalTokens.
  ///
  /// In en, this message translates to:
  /// **'Total tokens'**
  String get aiUsageTotalTokens;

  /// No description provided for @aiUsagePromptCompletion.
  ///
  /// In en, this message translates to:
  /// **'prompt {prompt} + completion {completion}'**
  String aiUsagePromptCompletion(int prompt, int completion);

  /// No description provided for @aiUsageTokensPerSecond.
  ///
  /// In en, this message translates to:
  /// **'Tokens/s'**
  String get aiUsageTokensPerSecond;

  /// No description provided for @aiUsageCacheHit.
  ///
  /// In en, this message translates to:
  /// **'Cache hit rate'**
  String get aiUsageCacheHit;

  /// No description provided for @aiUsageCacheAbsent.
  ///
  /// In en, this message translates to:
  /// **'This endpoint reported no cache accounting.'**
  String get aiUsageCacheAbsent;

  /// No description provided for @aiUsageCachePartial.
  ///
  /// In en, this message translates to:
  /// **'Only some rounds reported cache accounting.'**
  String get aiUsageCachePartial;

  /// No description provided for @aiUsageContext.
  ///
  /// In en, this message translates to:
  /// **'Context used'**
  String get aiUsageContext;

  /// No description provided for @aiUsageContextEstimate.
  ///
  /// In en, this message translates to:
  /// **'Estimated against a {tokens}-token window; the window is a configured value, not a measurement.'**
  String aiUsageContextEstimate(int tokens);

  /// No description provided for @aiUsagePending.
  ///
  /// In en, this message translates to:
  /// **'{count} awaiting approval'**
  String aiUsagePending(int count);

  /// No description provided for @aiUsageRejected.
  ///
  /// In en, this message translates to:
  /// **'{count} rejected'**
  String aiUsageRejected(int count);

  /// No description provided for @aiUsageLiveEstimate.
  ///
  /// In en, this message translates to:
  /// **'Still streaming: counted from the text that has arrived so far.'**
  String get aiUsageLiveEstimate;

  /// No description provided for @aiUsageNoUsage.
  ///
  /// In en, this message translates to:
  /// **'This turn reported no token usage.'**
  String get aiUsageNoUsage;

  /// No description provided for @aiUsageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get aiUsageUnavailable;

  /// No description provided for @settingsAiSection.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get settingsAiSection;

  /// No description provided for @settingsAiEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable AI'**
  String get settingsAiEnabled;

  /// No description provided for @settingsAiApiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get settingsAiApiKey;

  /// No description provided for @settingsAiApiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Stored in plain text locally, and exported inside .tfpkg'**
  String get settingsAiApiKeyHint;

  /// No description provided for @settingsAiBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get settingsAiBaseUrl;

  /// No description provided for @settingsAiModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get settingsAiModel;

  /// No description provided for @settingsAiPermissionMode.
  ///
  /// In en, this message translates to:
  /// **'Permission mode'**
  String get settingsAiPermissionMode;

  /// No description provided for @settingsAiPermissionPlan.
  ///
  /// In en, this message translates to:
  /// **'Plan (confirm writes once per turn)'**
  String get settingsAiPermissionPlan;

  /// No description provided for @settingsAiPermissionAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto (run everything but deletions, undoable)'**
  String get settingsAiPermissionAuto;

  /// No description provided for @settingsAiPermissionHint.
  ///
  /// In en, this message translates to:
  /// **'Deletions always ask one by one, in every mode.'**
  String get settingsAiPermissionHint;

  /// No description provided for @settingsAiMaxRounds.
  ///
  /// In en, this message translates to:
  /// **'Tool-call round limit per message'**
  String get settingsAiMaxRounds;

  /// No description provided for @settingsAiMaxRoundsValue.
  ///
  /// In en, this message translates to:
  /// **'{rounds} rounds'**
  String settingsAiMaxRoundsValue(int rounds);

  /// No description provided for @settingsAiMaxRoundsHint.
  ///
  /// In en, this message translates to:
  /// **'Each extra round is another paid model call; more rounds let one message finish longer multi-step work. Defaults to 8.'**
  String get settingsAiMaxRoundsHint;

  /// No description provided for @settingsAiSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get settingsAiSave;

  /// No description provided for @settingsAiSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get settingsAiSaved;

  /// No description provided for @settingsAiKeyRequired.
  ///
  /// In en, this message translates to:
  /// **'An API key is required to enable this'**
  String get settingsAiKeyRequired;

  /// No description provided for @settingsAiPlatformNote.
  ///
  /// In en, this message translates to:
  /// **'Android has no Node runtime and no desktop browser, so script-based abilities are Windows-only.'**
  String get settingsAiPlatformNote;

  /// No description provided for @skillsTitle.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get skillsTitle;

  /// No description provided for @skillsIntro.
  ///
  /// In en, this message translates to:
  /// **'A .fskill is a zip package: a prompt, plus optional declared tools and scripts. Installing only unpacks files onto disk. Enabling a skill adds its prompt (and its reference files) to what the model is told; a declared tool can then be called, and every call is confirmed by you first.'**
  String get skillsIntro;

  /// No description provided for @skillsInstall.
  ///
  /// In en, this message translates to:
  /// **'Install .fskill'**
  String get skillsInstall;

  /// No description provided for @skillsInstallSample.
  ///
  /// In en, this message translates to:
  /// **'Install the sample skill'**
  String get skillsInstallSample;

  /// No description provided for @skillsBuiltinTitle.
  ///
  /// In en, this message translates to:
  /// **'Built-in skills:'**
  String get skillsBuiltinTitle;

  /// No description provided for @skillsBuiltinInstall.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get skillsBuiltinInstall;

  /// No description provided for @skillsInstalling.
  ///
  /// In en, this message translates to:
  /// **'Installing...'**
  String get skillsInstalling;

  /// No description provided for @skillsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No skills installed.'**
  String get skillsEmpty;

  /// No description provided for @skillsPlatforms.
  ///
  /// In en, this message translates to:
  /// **'Platforms'**
  String get skillsPlatforms;

  /// No description provided for @skillsNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get skillsNetwork;

  /// No description provided for @skillsNetworkNone.
  ///
  /// In en, this message translates to:
  /// **'none allowed'**
  String get skillsNetworkNone;

  /// No description provided for @skillsPermissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get skillsPermissions;

  /// No description provided for @skillsPermissionsNone.
  ///
  /// In en, this message translates to:
  /// **'none requested'**
  String get skillsPermissionsNone;

  /// No description provided for @skillsTools.
  ///
  /// In en, this message translates to:
  /// **'Declared tools'**
  String get skillsTools;

  /// No description provided for @skillsToolsNone.
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get skillsToolsNone;

  /// No description provided for @skillsContainerNote.
  ///
  /// In en, this message translates to:
  /// **'The script container is enabled (Windows only): once an enabled skill is part of a turn, its declared script tools appear in the model\'s tool list. Every call waits for your individual confirmation in the conversation, and only then does a one-shot child process start. The child does not receive the app\'s environment, so it cannot borrow your API key.'**
  String get skillsContainerNote;

  /// No description provided for @skillsContainerNoteUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Script execution is Windows only: there is no Node runtime on this device, so declared script tools do not appear in the model\'s tool list (the skill\'s prompt still applies).'**
  String get skillsContainerNoteUnavailable;

  /// No description provided for @skillsContainerPromptOnly.
  ///
  /// In en, this message translates to:
  /// **'This skill has no scripts to run: only its prompt applies, on both Android and Windows, for as long as it stays enabled.'**
  String get skillsContainerPromptOnly;

  /// No description provided for @skillsContainerRunnable.
  ///
  /// In en, this message translates to:
  /// **'This machine can run the skill\'s scripts (Windows), so its declared tools are offered to the model while it is enabled.'**
  String get skillsContainerRunnable;

  /// No description provided for @skillsContainerNotRunnable.
  ///
  /// In en, this message translates to:
  /// **'This machine cannot run the skill\'s scripts (it declares {platforms} only), so its tools are not offered to the model; its prompt still applies while it is enabled.'**
  String skillsContainerNotRunnable(String platforms);

  /// No description provided for @skillsUnsupportedCapability.
  ///
  /// In en, this message translates to:
  /// **'The container does not provide the host capability {capability} (see docs/SKILL_FORMAT.md §4): a skill asking for it has its script calls refused rather than run without it.'**
  String skillsUnsupportedCapability(String capability);

  /// No description provided for @skillsNetworkConsent.
  ///
  /// In en, this message translates to:
  /// **'Allow network ({domains})'**
  String skillsNetworkConsent(String domains);

  /// No description provided for @skillsNetworkNoConsent.
  ///
  /// In en, this message translates to:
  /// **'Network not allowed ({domains}): its script calls are refused until you turn this on.'**
  String skillsNetworkNoConsent(String domains);

  /// No description provided for @skillsNetworkDeclaredNone.
  ///
  /// In en, this message translates to:
  /// **'This skill declares no network use (networkAllow is empty).'**
  String get skillsNetworkDeclaredNone;

  /// No description provided for @skillsNetworkConsentNote.
  ///
  /// In en, this message translates to:
  /// **'Turning this on lets this skill\'s scripts use the network. What you are shown is the domain list it declares; the container confines by declaration, it does not block other domains at the OS level.'**
  String get skillsNetworkConsentNote;

  /// No description provided for @skillsNetworkToggleFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not change this skill\'s network permission'**
  String get skillsNetworkToggleFailed;

  /// No description provided for @skillsPath.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get skillsPath;

  /// No description provided for @skillsRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get skillsRemove;

  /// No description provided for @skillsRemoveConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove skill'**
  String get skillsRemoveConfirmTitle;

  /// No description provided for @skillsRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'{name}: delete this skill\'s files from disk? This cannot be undone from inside the app.'**
  String skillsRemoveConfirm(String name);

  /// No description provided for @skillsCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get skillsCancel;

  /// No description provided for @skillsRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remove this skill'**
  String get skillsRemoveFailed;

  /// No description provided for @skillsToggleFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not change this skill\'s state'**
  String get skillsToggleFailed;

  /// No description provided for @skillsInstallFailed.
  ///
  /// In en, this message translates to:
  /// **'Installation refused or failed'**
  String get skillsInstallFailed;

  /// No description provided for @settingsThemeBackgroundNone.
  ///
  /// In en, this message translates to:
  /// **'No background image'**
  String get settingsThemeBackgroundNone;

  /// No description provided for @settingsThemeBackgroundSet.
  ///
  /// In en, this message translates to:
  /// **'Background image set'**
  String get settingsThemeBackgroundSet;

  /// No description provided for @settingsThemeBackgroundPick.
  ///
  /// In en, this message translates to:
  /// **'Pick an image'**
  String get settingsThemeBackgroundPick;

  /// No description provided for @settingsThemeBackgroundBlur.
  ///
  /// In en, this message translates to:
  /// **'Background blur'**
  String get settingsThemeBackgroundBlur;

  /// No description provided for @settingsThemeBackgroundFailed.
  ///
  /// In en, this message translates to:
  /// **'That image could not be read'**
  String get settingsThemeBackgroundFailed;

  /// No description provided for @settingsTfpkgExportSecretsHint.
  ///
  /// In en, this message translates to:
  /// **'This package would include your AI API key. If you are sending it to someone else, choose the version without secrets.'**
  String get settingsTfpkgExportSecretsHint;

  /// No description provided for @settingsTfpkgExportWithSecrets.
  ///
  /// In en, this message translates to:
  /// **'Include (for my own backup)'**
  String get settingsTfpkgExportWithSecrets;

  /// No description provided for @settingsTfpkgExportNoSecrets.
  ///
  /// In en, this message translates to:
  /// **'Without secrets (to share)'**
  String get settingsTfpkgExportNoSecrets;

  /// No description provided for @settingsTfpkgExportDoneNoSecrets.
  ///
  /// In en, this message translates to:
  /// **'Workspace exported (API key excluded)'**
  String get settingsTfpkgExportDoneNoSecrets;

  /// No description provided for @cognitiveModelTitle.
  ///
  /// In en, this message translates to:
  /// **'Cognitive model'**
  String get cognitiveModelTitle;

  /// No description provided for @cognitiveModelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read-only readings: R / band / zone'**
  String get cognitiveModelSubtitle;

  /// No description provided for @cognitiveGraphTitle.
  ///
  /// In en, this message translates to:
  /// **'Knowledge network (read-only)'**
  String get cognitiveGraphTitle;

  /// No description provided for @cognitiveGraphHint.
  ///
  /// In en, this message translates to:
  /// **'Dots are knowledge points (colour = cognitive zone, size = card count), squares are tags, and a line means the point hangs off that tag. Nothing here is editable: no due dates and no ordering change.'**
  String get cognitiveGraphHint;

  /// No description provided for @cognitiveGraphEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing to draw yet: create knowledge points and tags, then review a few cards.'**
  String get cognitiveGraphEmpty;

  /// No description provided for @cognitiveGraphSummary.
  ///
  /// In en, this message translates to:
  /// **'{points} knowledge points · {tags} tags · {links} links'**
  String cognitiveGraphSummary(int points, int tags, int links);

  /// No description provided for @cognitiveGraphPointDetail.
  ///
  /// In en, this message translates to:
  /// **'Zone: {zone} · {cards} cards · mean R {mean}'**
  String cognitiveGraphPointDetail(String zone, int cards, String mean);

  /// No description provided for @cognitiveGraphTagDetail.
  ///
  /// In en, this message translates to:
  /// **'{count} knowledge points hang off this tag'**
  String cognitiveGraphTagDetail(int count);

  /// No description provided for @cognitiveGraphTapHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a dot or a square to read it (read-only).'**
  String get cognitiveGraphTapHint;

  /// No description provided for @cognitiveAdvisorMode.
  ///
  /// In en, this message translates to:
  /// **'Advisor mode: due dates are not changed'**
  String get cognitiveAdvisorMode;

  /// No description provided for @cognitiveAdvisorModeDetail.
  ///
  /// In en, this message translates to:
  /// **'FSRS still owns when a card is due. The model only influences the queue order and the numbers on this page.'**
  String get cognitiveAdvisorModeDetail;

  /// No description provided for @cognitiveUncalibratedWeights.
  ///
  /// In en, this message translates to:
  /// **'Weights such as ls are not calibrated'**
  String get cognitiveUncalibratedWeights;

  /// No description provided for @cognitiveUncalibratedWeightsDetail.
  ///
  /// In en, this message translates to:
  /// **'The model\'s edge weights (ls and friends) have no calibration source, so this ordering is a heuristic, not a measurement.'**
  String get cognitiveUncalibratedWeightsDetail;

  /// No description provided for @cognitiveReadOnlyNote.
  ///
  /// In en, this message translates to:
  /// **'Read-only page: nothing here is written to the database'**
  String get cognitiveReadOnlyNote;

  /// No description provided for @mechanismPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Mechanisms and parameters'**
  String get mechanismPanelTitle;

  /// No description provided for @mechanismPanelSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Which mechanisms the engines install, what each parameter is, and which values are not calibrated'**
  String get mechanismPanelSubtitle;

  /// No description provided for @mechanismPanelReadOnlyNote.
  ///
  /// In en, this message translates to:
  /// **'This panel writes exactly two settings (the switch and the slider below) and nothing else; the setups and parameters shown are the ones the engines actually run with'**
  String get mechanismPanelReadOnlyNote;

  /// No description provided for @mechanismSwitchGoalTitle.
  ///
  /// In en, this message translates to:
  /// **'Install the goal mechanism (context.goal)'**
  String get mechanismSwitchGoalTitle;

  /// No description provided for @mechanismSwitchGoalBody.
  ///
  /// In en, this message translates to:
  /// **'When off, the library-diagnosis run no longer installs it, so the diffusion has no starts/targets to pull towards and its readings change. The problem-pricing run still installs it (that path prices starts/targets). Never chosen = installed.'**
  String get mechanismSwitchGoalBody;

  /// No description provided for @mechanismGoalBetaTitle.
  ///
  /// In en, this message translates to:
  /// **'Goal bias strength (context.goal.beta_goal)'**
  String get mechanismGoalBetaTitle;

  /// No description provided for @mechanismGoalBetaBody.
  ///
  /// In en, this message translates to:
  /// **'How hard the goal pulls the diffusion towards starts/targets: 0 = no pull at all, and the shipped value is the transcribed default written below (an uncalibrated placeholder). It changes this one number and nothing about what is installed.'**
  String get mechanismGoalBetaBody;

  /// No description provided for @mechanismGoalBetaShipped.
  ///
  /// In en, this message translates to:
  /// **'shipped value'**
  String get mechanismGoalBetaShipped;

  /// No description provided for @mechanismGoalBetaFromSetting.
  ///
  /// In en, this message translates to:
  /// **'yours'**
  String get mechanismGoalBetaFromSetting;

  /// No description provided for @mechanismGoalBetaReset.
  ///
  /// In en, this message translates to:
  /// **'Back to the shipped value'**
  String get mechanismGoalBetaReset;

  /// No description provided for @mechanismGoalBetaApplies.
  ///
  /// In en, this message translates to:
  /// **'Every run that installs the goal mechanism reads this number: the library-diagnosis run (the reading above on this page) and the problem-pricing run (the V(π) ordering behind evaluate_problem_fit / plan_today). The tools\' module_defaults carries exactly it - empty when you have never tuned it (the shipped value untouched).'**
  String get mechanismGoalBetaApplies;

  /// No description provided for @mechanismGoalBetaOffNote.
  ///
  /// In en, this message translates to:
  /// **'The goal mechanism is not installed (the switch above is off), so the runs that would install it do not use this value; the number stays for when you turn it back on.'**
  String get mechanismGoalBetaOffNote;

  /// No description provided for @mechanismDisabledBySetting.
  ///
  /// In en, this message translates to:
  /// **'you turned it off (it ships installed)'**
  String get mechanismDisabledBySetting;

  /// No description provided for @mechanismPanelSetupsHeader.
  ///
  /// In en, this message translates to:
  /// **'The three engine setups'**
  String get mechanismPanelSetupsHeader;

  /// No description provided for @mechanismPanelSetupCount.
  ///
  /// In en, this message translates to:
  /// **'{count} mechanism(s) installed'**
  String mechanismPanelSetupCount(int count);

  /// No description provided for @mechanismPanelOverridesHeader.
  ///
  /// In en, this message translates to:
  /// **'Overrides (not the transcribed defaults):'**
  String get mechanismPanelOverridesHeader;

  /// No description provided for @mechanismPanelNoOverrides.
  ///
  /// In en, this message translates to:
  /// **'No overrides: every value is the transcribed default'**
  String get mechanismPanelNoOverrides;

  /// No description provided for @mechanismPanelMechanismsHeader.
  ///
  /// In en, this message translates to:
  /// **'Mechanisms'**
  String get mechanismPanelMechanismsHeader;

  /// No description provided for @mechanismPanelInstalledIn.
  ///
  /// In en, this message translates to:
  /// **'Installed in: '**
  String get mechanismPanelInstalledIn;

  /// No description provided for @mechanismPanelOnlyOutside.
  ///
  /// In en, this message translates to:
  /// **'Only inside the rhythm reading - not installed into an engine'**
  String get mechanismPanelOnlyOutside;

  /// No description provided for @mechanismPanelNoParams.
  ///
  /// In en, this message translates to:
  /// **'This layer declares no numeric parameters: it keeps a per-node state bag only'**
  String get mechanismPanelNoParams;

  /// No description provided for @mechanismPanelUncalibrated.
  ///
  /// In en, this message translates to:
  /// **'NOT CALIBRATED'**
  String get mechanismPanelUncalibrated;

  /// No description provided for @mechanismPanelCalibrated.
  ///
  /// In en, this message translates to:
  /// **'calibrated'**
  String get mechanismPanelCalibrated;

  /// No description provided for @mechanismPanelOverridden.
  ///
  /// In en, this message translates to:
  /// **'overridden'**
  String get mechanismPanelOverridden;

  /// No description provided for @mechanismPanelTranscribed.
  ///
  /// In en, this message translates to:
  /// **'transcribed default'**
  String get mechanismPanelTranscribed;

  /// No description provided for @mechanismPanelRange.
  ///
  /// In en, this message translates to:
  /// **'range'**
  String get mechanismPanelRange;

  /// No description provided for @mechanismPanelSummary.
  ///
  /// In en, this message translates to:
  /// **'{params} parameters, {uncalibrated} of them not calibrated'**
  String mechanismPanelSummary(int params, int uncalibrated);

  /// No description provided for @mechanismPanelNameSeparator.
  ///
  /// In en, this message translates to:
  /// **', '**
  String get mechanismPanelNameSeparator;

  /// No description provided for @mechanismPanelOpen.
  ///
  /// In en, this message translates to:
  /// **'Mechanisms and parameters'**
  String get mechanismPanelOpen;

  /// No description provided for @mechanismNameShunting.
  ///
  /// In en, this message translates to:
  /// **'Shunting inhibition'**
  String get mechanismNameShunting;

  /// No description provided for @mechanismNameCapacity.
  ///
  /// In en, this message translates to:
  /// **'Attention capacity'**
  String get mechanismNameCapacity;

  /// No description provided for @mechanismNameIgnition.
  ///
  /// In en, this message translates to:
  /// **'Ignition threshold'**
  String get mechanismNameIgnition;

  /// No description provided for @mechanismNameGoal.
  ///
  /// In en, this message translates to:
  /// **'Goal context'**
  String get mechanismNameGoal;

  /// No description provided for @mechanismNameRhythm.
  ///
  /// In en, this message translates to:
  /// **'Rhythm gate'**
  String get mechanismNameRhythm;

  /// No description provided for @mechanismNameMemory.
  ///
  /// In en, this message translates to:
  /// **'DSR memory layer'**
  String get mechanismNameMemory;

  /// No description provided for @mechanismSetupLibraryDiagnosis.
  ///
  /// In en, this message translates to:
  /// **'The library-diagnosis run'**
  String get mechanismSetupLibraryDiagnosis;

  /// No description provided for @mechanismSetupProblemEvaluator.
  ///
  /// In en, this message translates to:
  /// **'The problem-pricing run'**
  String get mechanismSetupProblemEvaluator;

  /// No description provided for @mechanismSetupRunRehearsal.
  ///
  /// In en, this message translates to:
  /// **'The transcript-request rehearsal'**
  String get mechanismSetupRunRehearsal;

  /// No description provided for @cognitiveZoneNote.
  ///
  /// In en, this message translates to:
  /// **'Zone uses the same ReviewZone vocabulary as the review queue. \"Unavailable\" only means nothing was diagnosed this time - it is not the same as \"healthy (checked, nothing to report)\".'**
  String get cognitiveZoneNote;

  /// No description provided for @cognitiveFastLayerNote.
  ///
  /// In en, this message translates to:
  /// **'Zones come from the tierB fast layer'**
  String get cognitiveFastLayerNote;

  /// No description provided for @cognitiveFastLayerRanDetail.
  ///
  /// In en, this message translates to:
  /// **'It ran this time: each zone is the diffusion verdict on the tag graph (weak / empty / slow / overloaded / off-goal / dead-end). Starts are the most recently reviewed knowledge points, targets are the ones due today.'**
  String get cognitiveFastLayerRanDetail;

  /// No description provided for @cognitiveFastLayerNotRunDetail.
  ///
  /// In en, this message translates to:
  /// **'It did not run this time: there are no tags, or no usable start and target, so every zone reads unavailable.'**
  String get cognitiveFastLayerNotRunDetail;

  /// No description provided for @cognitiveDangerNote.
  ///
  /// In en, this message translates to:
  /// **'\"Danger (confident but forgetting)\" is now computed by the metacognition layer: it appears only when a knowledge point is lit up on the tag graph this run while its cards have gone untouched for a long time. A knowledge point that is not listed is not therefore fine - it may simply not have been judged this time.'**
  String get cognitiveDangerNote;

  /// No description provided for @cognitiveMetacognitionTitle.
  ///
  /// In en, this message translates to:
  /// **'How the model reads you'**
  String get cognitiveMetacognitionTitle;

  /// No description provided for @cognitiveMetacognitionDetail.
  ///
  /// In en, this message translates to:
  /// **'Compares how much the model believes in a node (belief, from fluency, encoding strength and recency) with how much its cards can actually still be recalled. The wider the gap, the more it is worth a look.'**
  String get cognitiveMetacognitionDetail;

  /// No description provided for @cognitiveMetacognitionCalibration.
  ///
  /// In en, this message translates to:
  /// **'mean gap {gap} (smaller is better; the weights are uncalibrated, so this is for reference)'**
  String cognitiveMetacognitionCalibration(Object gap);

  /// No description provided for @cognitiveMetacognitionDanger.
  ///
  /// In en, this message translates to:
  /// **'danger: {nodes} (being studied, but the cards are long untouched)'**
  String cognitiveMetacognitionDanger(Object nodes);

  /// No description provided for @cognitiveMetacognitionAnxiety.
  ///
  /// In en, this message translates to:
  /// **'underrated: {nodes} (the cards are fine; you feel they are not)'**
  String cognitiveMetacognitionAnxiety(Object nodes);

  /// No description provided for @cognitiveMetacognitionNoRows.
  ///
  /// In en, this message translates to:
  /// **'No knowledge point could be judged this time: each one needs at least one card, and the diagnosis has to have run.'**
  String get cognitiveMetacognitionNoRows;

  /// No description provided for @cognitiveMetacognitionLevel.
  ///
  /// In en, this message translates to:
  /// **'No knowledge point crossed the 0.2 gap threshold: nothing is in danger or underrated this run.'**
  String get cognitiveMetacognitionLevel;

  /// No description provided for @cognitiveSummary.
  ///
  /// In en, this message translates to:
  /// **'{cards} card(s), model {model}'**
  String cognitiveSummary(int cards, String model);

  /// No description provided for @cognitiveSummaryBands.
  ///
  /// In en, this message translates to:
  /// **'Bands: {bands}'**
  String cognitiveSummaryBands(String bands);

  /// No description provided for @cognitiveSummaryNumbers.
  ///
  /// In en, this message translates to:
  /// **'New cards {newCards}, mean R {meanR}'**
  String cognitiveSummaryNumbers(int newCards, String meanR);

  /// No description provided for @cognitiveReadAt.
  ///
  /// In en, this message translates to:
  /// **'Read at {moment}'**
  String cognitiveReadAt(String moment);

  /// No description provided for @cognitiveEmpty.
  ///
  /// In en, this message translates to:
  /// **'No cards to observe yet. Add a flashcard and review a few cards first.'**
  String get cognitiveEmpty;

  /// No description provided for @cognitiveOrphanTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} card states whose flashcard is gone'**
  String cognitiveOrphanTitle(int count);

  /// No description provided for @cognitiveOrphanDetail.
  ///
  /// In en, this message translates to:
  /// **'They can never be reviewed again, so they are not listed as cards. Clearing them deletes the rows (and their review logs) for good.'**
  String get cognitiveOrphanDetail;

  /// No description provided for @cognitiveOrphanAction.
  ///
  /// In en, this message translates to:
  /// **'Clear {count}'**
  String cognitiveOrphanAction(int count);

  /// No description provided for @cognitiveOrphanDone.
  ///
  /// In en, this message translates to:
  /// **'Cleared {count} unusable card states'**
  String cognitiveOrphanDone(int count);

  /// No description provided for @cognitiveNewCard.
  ///
  /// In en, this message translates to:
  /// **'new'**
  String get cognitiveNewCard;

  /// No description provided for @cognitiveSeenCard.
  ///
  /// In en, this message translates to:
  /// **'seen'**
  String get cognitiveSeenCard;

  /// No description provided for @cognitiveCardId.
  ///
  /// In en, this message translates to:
  /// **'card {id}'**
  String cognitiveCardId(String id);

  /// No description provided for @cognitiveRetrievability.
  ///
  /// In en, this message translates to:
  /// **'R {value}'**
  String cognitiveRetrievability(String value);

  /// No description provided for @cognitiveGain.
  ///
  /// In en, this message translates to:
  /// **'gain {value}'**
  String cognitiveGain(String value);

  /// No description provided for @cognitiveEncoding.
  ///
  /// In en, this message translates to:
  /// **'R0 {value}'**
  String cognitiveEncoding(String value);

  /// No description provided for @cognitiveEncodingPrior.
  ///
  /// In en, this message translates to:
  /// **'R0 {value} (measurement prior)'**
  String cognitiveEncodingPrior(String value);

  /// No description provided for @cognitivePriorNote.
  ///
  /// In en, this message translates to:
  /// **'Measurement priors'**
  String get cognitivePriorNote;

  /// No description provided for @cognitivePriorCount.
  ///
  /// In en, this message translates to:
  /// **'{count} cards now start from a measurement prior (uncalibrated); the rest start from their own review history or the model\'s defaults. Once a card has actually been reviewed, the observation takes over and the prior stops speaking.'**
  String cognitivePriorCount(int count);

  /// No description provided for @cognitivePriorNone.
  ///
  /// In en, this message translates to:
  /// **'No measurement priors yet: every card starts from the model\'s defaults or its own review history. One measurement gives this part of the material an estimate about you.'**
  String get cognitivePriorNone;

  /// No description provided for @cognitiveSavings.
  ///
  /// In en, this message translates to:
  /// **'Sigma {value}'**
  String cognitiveSavings(String value);

  /// No description provided for @cognitiveTags.
  ///
  /// In en, this message translates to:
  /// **'tags {count}'**
  String cognitiveTags(int count);

  /// No description provided for @cognitiveColumnBand.
  ///
  /// In en, this message translates to:
  /// **'Band'**
  String get cognitiveColumnBand;

  /// No description provided for @cognitiveColumnZone.
  ///
  /// In en, this message translates to:
  /// **'Zone'**
  String get cognitiveColumnZone;

  /// No description provided for @cognitiveColumnSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule (FSRS)'**
  String get cognitiveColumnSchedule;

  /// No description provided for @cognitiveGainNotUsed.
  ///
  /// In en, this message translates to:
  /// **'gain does not decide this position: the card is forced or boosted, so the model did not place it (D5)'**
  String get cognitiveGainNotUsed;

  /// No description provided for @cognitiveNewCardNotOrdered.
  ///
  /// In en, this message translates to:
  /// **'new cards are neither scored nor ordered by the model (D4)'**
  String get cognitiveNewCardNotOrdered;

  /// No description provided for @cognitiveNoSchedule.
  ///
  /// In en, this message translates to:
  /// **'unscheduled'**
  String get cognitiveNoSchedule;

  /// No description provided for @cognitiveDue.
  ///
  /// In en, this message translates to:
  /// **'due {moment}'**
  String cognitiveDue(String moment);

  /// No description provided for @cognitiveInterval.
  ///
  /// In en, this message translates to:
  /// **'interval {days} d'**
  String cognitiveInterval(String days);

  /// No description provided for @cognitiveSuggestedInterval.
  ///
  /// In en, this message translates to:
  /// **'a Good answer now would schedule {days} d'**
  String cognitiveSuggestedInterval(int days);

  /// No description provided for @cognitiveErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'The readings could not be loaded'**
  String get cognitiveErrorTitle;

  /// No description provided for @cognitiveBandForced.
  ///
  /// In en, this message translates to:
  /// **'forced today'**
  String get cognitiveBandForced;

  /// No description provided for @cognitiveBandBoosted.
  ///
  /// In en, this message translates to:
  /// **'boosted (heuristic)'**
  String get cognitiveBandBoosted;

  /// No description provided for @cognitiveBandModel.
  ///
  /// In en, this message translates to:
  /// **'model-ranked'**
  String get cognitiveBandModel;

  /// No description provided for @cognitiveBandUnseen.
  ///
  /// In en, this message translates to:
  /// **'unseen'**
  String get cognitiveBandUnseen;

  /// No description provided for @cognitiveZoneProximal.
  ///
  /// In en, this message translates to:
  /// **'proximal (almost recalled)'**
  String get cognitiveZoneProximal;

  /// No description provided for @cognitiveZoneEmpty.
  ///
  /// In en, this message translates to:
  /// **'empty (no way in)'**
  String get cognitiveZoneEmpty;

  /// No description provided for @cognitiveZoneDeadEnd.
  ///
  /// In en, this message translates to:
  /// **'dead end'**
  String get cognitiveZoneDeadEnd;

  /// No description provided for @cognitiveZoneSlow.
  ///
  /// In en, this message translates to:
  /// **'slow (needs too many rounds)'**
  String get cognitiveZoneSlow;

  /// No description provided for @cognitiveZoneOverload.
  ///
  /// In en, this message translates to:
  /// **'overload (outcompeted by capacity)'**
  String get cognitiveZoneOverload;

  /// No description provided for @cognitiveZoneOffGoal.
  ///
  /// In en, this message translates to:
  /// **'off goal'**
  String get cognitiveZoneOffGoal;

  /// No description provided for @cognitiveZoneDanger.
  ///
  /// In en, this message translates to:
  /// **'danger (confident but forgotten)'**
  String get cognitiveZoneDanger;

  /// No description provided for @cognitiveZoneHealthy.
  ///
  /// In en, this message translates to:
  /// **'healthy (checked, nothing to report)'**
  String get cognitiveZoneHealthy;

  /// No description provided for @cognitiveZoneUnavailable.
  ///
  /// In en, this message translates to:
  /// **'unavailable (no diagnosis)'**
  String get cognitiveZoneUnavailable;

  /// No description provided for @assessmentTitle.
  ///
  /// In en, this message translates to:
  /// **'Give the model a starting point'**
  String get assessmentTitle;

  /// The assessment page's framing: abstract parameters, self-report first, everything uncalibrated
  ///
  /// In en, this message translates to:
  /// **'Every number on the reading page comes either from your review history or from the model\'s defaults. This does a third thing: one short assessment that replaces the defaults with an estimate about you. It measures abstract parameters (starting retrievability, fluency), not how many cards you memorised; self-report starts, objective checks come later. Every prior is still marked uncalibrated - it is a starting point, not a conclusion.'**
  String get assessmentIntro;

  /// No description provided for @assessmentStepScope.
  ///
  /// In en, this message translates to:
  /// **'1. Scope'**
  String get assessmentStepScope;

  /// No description provided for @assessmentStepSelf.
  ///
  /// In en, this message translates to:
  /// **'2. Self-report'**
  String get assessmentStepSelf;

  /// No description provided for @assessmentStepRecall.
  ///
  /// In en, this message translates to:
  /// **'3. Recall check'**
  String get assessmentStepRecall;

  /// No description provided for @assessmentStepResult.
  ///
  /// In en, this message translates to:
  /// **'4. Reading'**
  String get assessmentStepResult;

  /// No description provided for @assessmentScopeHint.
  ///
  /// In en, this message translates to:
  /// **'Pick one area (a selected tag includes its children). The tighter the scope, the more the priors deserve to be taken seriously; spread over the whole library they are only an average.'**
  String get assessmentScopeHint;

  /// How many knowledge points the chosen scope contains
  ///
  /// In en, this message translates to:
  /// **'{count} knowledge points in this area'**
  String assessmentScopeCount(Object count);

  /// No description provided for @assessmentScopeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing to measure yet: create tags on the tags page and knowledge points in flashcards first.'**
  String get assessmentScopeEmpty;

  /// No description provided for @assessmentNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get assessmentNext;

  /// No description provided for @assessmentBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get assessmentBack;

  /// No description provided for @assessmentSelfHint.
  ///
  /// In en, this message translates to:
  /// **'Without looking anything up, how much could you retell right now? 0 = nothing at all, 5 = I could teach it. Self-report is not an exam; it gives the model a starting point, and objective checks will correct it.'**
  String get assessmentSelfHint;

  /// Self-report progress
  ///
  /// In en, this message translates to:
  /// **'Self-rated {answered} / {total}'**
  String assessmentSelfAnswered(Object answered, Object total);

  /// No description provided for @assessmentRecallHint.
  ///
  /// In en, this message translates to:
  /// **'These three knowledge points are the two ends and the middle of the scope - the same set every time, so different days can be compared. Write your retelling, then rate it: did it hold up?'**
  String get assessmentRecallHint;

  /// No description provided for @assessmentRecallAnswer.
  ///
  /// In en, this message translates to:
  /// **'What I retold (optional)'**
  String get assessmentRecallAnswer;

  /// No description provided for @assessmentRecallRating.
  ///
  /// In en, this message translates to:
  /// **'Did my retelling hold up?'**
  String get assessmentRecallRating;

  /// No description provided for @assessmentFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish and recompute priors'**
  String get assessmentFinish;

  /// No description provided for @assessmentResultTitle.
  ///
  /// In en, this message translates to:
  /// **'This round\'s reading'**
  String get assessmentResultTitle;

  /// No description provided for @assessmentResultPending.
  ///
  /// In en, this message translates to:
  /// **'The button below ends this round: it writes the answers as evidence, then recomputes the priors for the scope.'**
  String get assessmentResultPending;

  /// Evidence steps written and knowledge points covered by one round
  ///
  /// In en, this message translates to:
  /// **'Wrote {steps} evidence steps and recomputed priors for {points} knowledge points.'**
  String assessmentResultBody(Object steps, Object points);

  /// Mean starting R0 across the priors in scope
  ///
  /// In en, this message translates to:
  /// **'Mean starting R0 {r0}'**
  String assessmentResultR0(Object r0);

  /// Mean confidence n/(n+3) across the priors in scope
  ///
  /// In en, this message translates to:
  /// **'Mean confidence {confidence} (n/(n+3): more samples move it toward 1)'**
  String assessmentResultConfidence(Object confidence);

  /// No description provided for @assessmentResultUncalibrated.
  ///
  /// In en, this message translates to:
  /// **'Every prior is marked uncalibrated: these constants are still the model\'s defaults. With so few answers they are a starting point, not a conclusion; calibration waits for objective checks to accumulate.'**
  String get assessmentResultUncalibrated;

  /// No description provided for @assessmentNoEvidence.
  ///
  /// In en, this message translates to:
  /// **'This round wrote no evidence at all (everything was skipped), so there are no priors - an empty round must not pollute the reading.'**
  String get assessmentNoEvidence;

  /// Entry point to the assessment on the reading page
  ///
  /// In en, this message translates to:
  /// **'Measure (give the model a starting point)'**
  String get assessmentEntryAction;

  /// No description provided for @capabilityProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Capability moves (from solved chains)'**
  String get capabilityProfileTitle;

  /// No description provided for @capabilityProfileDetail.
  ///
  /// In en, this message translates to:
  /// **'Aggregated per step\'s stuck risk; steps with no risk reading are only counted, never averaged in.'**
  String get capabilityProfileDetail;

  /// No description provided for @capabilityProfileUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The profile could not be read (database read failed).'**
  String get capabilityProfileUnavailable;

  /// No description provided for @capabilityProfileEmpty.
  ///
  /// In en, this message translates to:
  /// **'No reasoning chains yet: solve a question once from its detail page and there will be something to aggregate.'**
  String get capabilityProfileEmpty;

  /// No description provided for @capabilityProfileRow.
  ///
  /// In en, this message translates to:
  /// **'{action}: {steps} steps, {risky} high-risk, average risk {risk}'**
  String capabilityProfileRow(String action, int steps, int risky, String risk);

  /// No description provided for @capabilityProfileNoRisk.
  ///
  /// In en, this message translates to:
  /// **'no risk reading (no judgement given)'**
  String get capabilityProfileNoRisk;

  /// No description provided for @capabilityProfileUnknownNote.
  ///
  /// In en, this message translates to:
  /// **'Unknown moves are shown verbatim - that is not \"fine\", it means the vocabulary does not know it yet.'**
  String get capabilityProfileUnknownNote;

  /// No description provided for @capabilityActionQuestionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Questions by capability move: {label}'**
  String capabilityActionQuestionsTitle(String label);

  /// No description provided for @capabilityActionQuestionsNote.
  ///
  /// In en, this message translates to:
  /// **'These are the questions whose latest solved chain used this move; questions without a chain cannot appear here.'**
  String get capabilityActionQuestionsNote;

  /// No description provided for @capabilityActionQuestionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No solved question uses \"{label}\" yet - solve one from its detail page first.'**
  String capabilityActionQuestionsEmpty(String label);

  /// No description provided for @capabilityActionQuestionsAllSubjects.
  ///
  /// In en, this message translates to:
  /// **'All subjects'**
  String get capabilityActionQuestionsAllSubjects;

  /// No description provided for @capabilityActionQuestionsSecondAction.
  ///
  /// In en, this message translates to:
  /// **'Add a second move (optional)'**
  String get capabilityActionQuestionsSecondAction;

  /// No description provided for @capabilityActionQuestionsSecondActionNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get capabilityActionQuestionsSecondActionNone;

  /// No description provided for @capabilityActionQuestionsRequireAll.
  ///
  /// In en, this message translates to:
  /// **'Both moves must appear on the same chain'**
  String get capabilityActionQuestionsRequireAll;

  /// No description provided for @capabilityActionQuestionsMeta.
  ///
  /// In en, this message translates to:
  /// **'{subject} · {source} · moves on the chain: {actions}'**
  String capabilityActionQuestionsMeta(
      String subject, String source, String actions);

  /// No description provided for @capabilityActionQuestionsFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the question bank: {message}'**
  String capabilityActionQuestionsFailed(String message);

  /// No description provided for @capabilityVocabularyTitle.
  ///
  /// In en, this message translates to:
  /// **'Capability vocabulary'**
  String get capabilityVocabularyTitle;

  /// No description provided for @capabilityVocabularyHint.
  ///
  /// In en, this message translates to:
  /// **'The vocabulary names the move a student is stuck on. Built-in moves are read-only because their keys already live in saved data. Custom entries stay on this page until you tap Save; saved entries take effect from the next solve.'**
  String get capabilityVocabularyHint;

  /// No description provided for @capabilityVocabularyBuiltInSection.
  ///
  /// In en, this message translates to:
  /// **'Built-in moves (read-only, {count})'**
  String capabilityVocabularyBuiltInSection(int count);

  /// No description provided for @capabilityVocabularyBuiltInNote.
  ///
  /// In en, this message translates to:
  /// **'Built-in moves are defined in code; changing one means shipping a new build. This list is read-only.'**
  String get capabilityVocabularyBuiltInNote;

  /// No description provided for @capabilityVocabularyCustomSection.
  ///
  /// In en, this message translates to:
  /// **'Custom moves ({count})'**
  String capabilityVocabularyCustomSection(int count);

  /// No description provided for @capabilityVocabularyCustomEmpty.
  ///
  /// In en, this message translates to:
  /// **'No custom moves yet. Use Add move, or paste JSON to import below.'**
  String get capabilityVocabularyCustomEmpty;

  /// No description provided for @capabilityVocabularyAdd.
  ///
  /// In en, this message translates to:
  /// **'Add move'**
  String get capabilityVocabularyAdd;

  /// No description provided for @capabilityVocabularyEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit move'**
  String get capabilityVocabularyEditTitle;

  /// No description provided for @capabilityVocabularyKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'key (stable id)'**
  String get capabilityVocabularyKeyLabel;

  /// No description provided for @capabilityVocabularyKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Lower snake case, for example force_diagram_analysis; cannot change after saving.'**
  String get capabilityVocabularyKeyHint;

  /// No description provided for @capabilityVocabularyLabelZh.
  ///
  /// In en, this message translates to:
  /// **'Chinese name'**
  String get capabilityVocabularyLabelZh;

  /// No description provided for @capabilityVocabularyLabelEn.
  ///
  /// In en, this message translates to:
  /// **'English name (optional)'**
  String get capabilityVocabularyLabelEn;

  /// No description provided for @capabilityVocabularyDescriptionZh.
  ///
  /// In en, this message translates to:
  /// **'One-line description (optional)'**
  String get capabilityVocabularyDescriptionZh;

  /// No description provided for @capabilityVocabularySubjectHints.
  ///
  /// In en, this message translates to:
  /// **'Subjects where it appears'**
  String get capabilityVocabularySubjectHints;

  /// No description provided for @capabilityVocabularyMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get capabilityVocabularyMoveUp;

  /// No description provided for @capabilityVocabularyMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get capabilityVocabularyMoveDown;

  /// No description provided for @capabilityVocabularyImport.
  ///
  /// In en, this message translates to:
  /// **'Paste JSON to import'**
  String get capabilityVocabularyImport;

  /// No description provided for @capabilityVocabularyImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Paste vocabulary JSON'**
  String get capabilityVocabularyImportTitle;

  /// No description provided for @capabilityVocabularyImportHint.
  ///
  /// In en, this message translates to:
  /// **'Accepts a customActions list, or a plain array of custom moves'**
  String get capabilityVocabularyImportHint;

  /// No description provided for @capabilityVocabularyImportInvalidJson.
  ///
  /// In en, this message translates to:
  /// **'Could not parse the JSON: {message}'**
  String capabilityVocabularyImportInvalidJson(String message);

  /// No description provided for @capabilityVocabularyImportDone.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} move(s) (not saved yet)'**
  String capabilityVocabularyImportDone(int count);

  /// No description provided for @capabilityVocabularyRevert.
  ///
  /// In en, this message translates to:
  /// **'Discard changes'**
  String get capabilityVocabularyRevert;

  /// No description provided for @capabilityVocabularySaved.
  ///
  /// In en, this message translates to:
  /// **'Saved. The next solve uses the new vocabulary.'**
  String get capabilityVocabularySaved;

  /// No description provided for @capabilityVocabularySaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save: {message}'**
  String capabilityVocabularySaveFailed(String message);

  /// No description provided for @capabilityVocabularyDirty.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get capabilityVocabularyDirty;

  /// No description provided for @capabilityVocabularyIssuesTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} operation(s) were rejected'**
  String capabilityVocabularyIssuesTitle(int count);

  /// No description provided for @capabilityVocabularyIssueDismiss.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get capabilityVocabularyIssueDismiss;

  /// No description provided for @capabilityVocabularyLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the vocabulary: {message}'**
  String capabilityVocabularyLoadFailed(String message);

  /// No description provided for @capabilityVocabularyLeaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get capabilityVocabularyLeaveTitle;

  /// No description provided for @capabilityVocabularyLeaveBody.
  ///
  /// In en, this message translates to:
  /// **'Leaving will discard these changes.'**
  String get capabilityVocabularyLeaveBody;

  /// No description provided for @capabilityVocabularyLeaveStay.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get capabilityVocabularyLeaveStay;

  /// No description provided for @capabilityVocabularyLeaveDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard and leave'**
  String get capabilityVocabularyLeaveDiscard;

  /// No description provided for @capabilityVocabularySettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Capability vocabulary'**
  String get capabilityVocabularySettingsTitle;

  /// No description provided for @capabilityVocabularySettingsHint.
  ///
  /// In en, this message translates to:
  /// **'Add capability moves the built-in vocabulary does not have. Saved entries take effect on the next solve.'**
  String get capabilityVocabularySettingsHint;

  /// No description provided for @learningInsightTitle.
  ///
  /// In en, this message translates to:
  /// **'Learning insights'**
  String get learningInsightTitle;

  /// No description provided for @learningInsightRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get learningInsightRefresh;

  /// No description provided for @learningInsightLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load learning insights: {message}'**
  String learningInsightLoadFailed(String message);

  /// No description provided for @learningInsightRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get learningInsightRetry;

  /// No description provided for @learningInsightOverlayFallback.
  ///
  /// In en, this message translates to:
  /// **'Could not read the custom capability vocabulary; showing the built-in vocabulary.'**
  String get learningInsightOverlayFallback;

  /// No description provided for @learningInsightEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No solution chains yet'**
  String get learningInsightEmptyTitle;

  /// No description provided for @learningInsightEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Run AI solve on a few question detail pages first; insights appear once chains exist.'**
  String get learningInsightEmptyBody;

  /// No description provided for @learningInsightSummary.
  ///
  /// In en, this message translates to:
  /// **'{chains} chains · {steps} steps · {questions} questions'**
  String learningInsightSummary(int chains, int steps, int questions);

  /// No description provided for @learningInsightAdviceSection.
  ///
  /// In en, this message translates to:
  /// **'What to do next'**
  String get learningInsightAdviceSection;

  /// No description provided for @learningInsightAdviceEmpty.
  ///
  /// In en, this message translates to:
  /// **'No actionable advice right now'**
  String get learningInsightAdviceEmpty;

  /// No description provided for @learningInsightAdviceAction.
  ///
  /// In en, this message translates to:
  /// **'Action: {label}'**
  String learningInsightAdviceAction(String label);

  /// No description provided for @learningInsightAdviceQuestions.
  ///
  /// In en, this message translates to:
  /// **'{count} questions'**
  String learningInsightAdviceQuestions(int count);

  /// No description provided for @learningInsightAdviceSteps.
  ///
  /// In en, this message translates to:
  /// **'{count} steps'**
  String learningInsightAdviceSteps(int count);

  /// No description provided for @learningInsightAdviceHighRisk.
  ///
  /// In en, this message translates to:
  /// **'{count} high-risk steps'**
  String learningInsightAdviceHighRisk(int count);

  /// No description provided for @learningInsightActionSection.
  ///
  /// In en, this message translates to:
  /// **'Capability action breakdown'**
  String get learningInsightActionSection;

  /// No description provided for @learningInsightActionEmpty.
  ///
  /// In en, this message translates to:
  /// **'No action readings yet'**
  String get learningInsightActionEmpty;

  /// No description provided for @learningInsightActionBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get learningInsightActionBuiltIn;

  /// No description provided for @learningInsightActionCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get learningInsightActionCustom;

  /// No description provided for @learningInsightActionUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get learningInsightActionUnknown;

  /// No description provided for @learningInsightActionCounts.
  ///
  /// In en, this message translates to:
  /// **'{steps} steps · {questions} questions · {highRisk} high-risk'**
  String learningInsightActionCounts(int steps, int questions, int highRisk);

  /// No description provided for @learningInsightRiskAverage.
  ///
  /// In en, this message translates to:
  /// **'Average risk {percent}'**
  String learningInsightRiskAverage(String percent);

  /// No description provided for @learningInsightRiskUnread.
  ///
  /// In en, this message translates to:
  /// **'Average risk: no readings'**
  String get learningInsightRiskUnread;

  /// No description provided for @learningInsightLastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last seen {time}'**
  String learningInsightLastSeen(String time);

  /// No description provided for @learningInsightUnknownSection.
  ///
  /// In en, this message translates to:
  /// **'Actions outside the vocabulary ({count})'**
  String learningInsightUnknownSection(int count);

  /// No description provided for @learningInsightUnknownHint.
  ///
  /// In en, this message translates to:
  /// **'These actions are not in the vocabulary yet; consider adding them.'**
  String get learningInsightUnknownHint;

  /// No description provided for @learningInsightOpenVocabulary.
  ///
  /// In en, this message translates to:
  /// **'Open vocabulary'**
  String get learningInsightOpenVocabulary;

  /// No description provided for @learningInsightNeverUsedSection.
  ///
  /// In en, this message translates to:
  /// **'Vocabulary actions never seen'**
  String get learningInsightNeverUsedSection;

  /// No description provided for @learningInsightNeverUsedHint.
  ///
  /// In en, this message translates to:
  /// **'No samples for these actions yet; that does not mean they should not be used.'**
  String get learningInsightNeverUsedHint;

  /// No description provided for @learningInsightStuckSection.
  ///
  /// In en, this message translates to:
  /// **'Stuck hotspots (knowledge points)'**
  String get learningInsightStuckSection;

  /// No description provided for @learningInsightStuckCounts.
  ///
  /// In en, this message translates to:
  /// **'{highRiskSteps} high-risk steps · {questions} questions · {chains} chains'**
  String learningInsightStuckCounts(
      int highRiskSteps, int questions, int chains);

  /// No description provided for @learningInsightCrossSection.
  ///
  /// In en, this message translates to:
  /// **'Action × knowledge point stuck points'**
  String get learningInsightCrossSection;

  /// No description provided for @learningInsightSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Learning insights'**
  String get learningInsightSettingsTitle;

  /// No description provided for @learningInsightSettingsHint.
  ///
  /// In en, this message translates to:
  /// **'Review capability actions and stuck points in solution chains, and what to practice next'**
  String get learningInsightSettingsHint;

  /// No description provided for @practiceRecommendationTitle.
  ///
  /// In en, this message translates to:
  /// **'What to practice next'**
  String get practiceRecommendationTitle;

  /// No description provided for @practiceRecommendationEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recommendations yet: collect a few questions and run AI solving, then check back.'**
  String get practiceRecommendationEmpty;

  /// No description provided for @practiceRecommendationFailed.
  ///
  /// In en, this message translates to:
  /// **'Practice recommendations are unavailable right now.'**
  String get practiceRecommendationFailed;

  /// No description provided for @practiceRecommendationRank.
  ///
  /// In en, this message translates to:
  /// **'Rank {rank}'**
  String practiceRecommendationRank(int rank);

  /// No description provided for @practiceRecommendationActions.
  ///
  /// In en, this message translates to:
  /// **'Matched actions: {labels}'**
  String practiceRecommendationActions(String labels);

  /// No description provided for @practiceRecommendationMoreReasons.
  ///
  /// In en, this message translates to:
  /// **'{count} more reason(s)'**
  String practiceRecommendationMoreReasons(int count);

  /// No description provided for @practiceRecommendationSkipped.
  ///
  /// In en, this message translates to:
  /// **'{count} more question(s) not shown'**
  String practiceRecommendationSkipped(int count);

  /// No description provided for @practiceRecommendationReasonMatchedAdviceAction.
  ///
  /// In en, this message translates to:
  /// **'Matches a practice action from your learning advice'**
  String get practiceRecommendationReasonMatchedAdviceAction;

  /// No description provided for @practiceRecommendationReasonMatchedHighRiskKnowledgePoint.
  ///
  /// In en, this message translates to:
  /// **'Covers a stuck knowledge point'**
  String get practiceRecommendationReasonMatchedHighRiskKnowledgePoint;

  /// No description provided for @practiceRecommendationReasonUnknownActionScaffold.
  ///
  /// In en, this message translates to:
  /// **'Uses an action outside the vocabulary; build the basics first'**
  String get practiceRecommendationReasonUnknownActionScaffold;

  /// No description provided for @practiceRecommendationReasonUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Answer and solution are complete'**
  String get practiceRecommendationReasonUpToDate;

  /// No description provided for @practiceRecommendationReasonMissingSolution.
  ///
  /// In en, this message translates to:
  /// **'Missing solution'**
  String get practiceRecommendationReasonMissingSolution;

  /// No description provided for @practiceRecommendationReasonMissingAnswer.
  ///
  /// In en, this message translates to:
  /// **'Missing answer'**
  String get practiceRecommendationReasonMissingAnswer;

  /// No description provided for @practiceRecommendationReasonTooHard.
  ///
  /// In en, this message translates to:
  /// **'Harder than target'**
  String get practiceRecommendationReasonTooHard;

  /// No description provided for @practiceRecommendationReasonTooEasy.
  ///
  /// In en, this message translates to:
  /// **'Easier than target'**
  String get practiceRecommendationReasonTooEasy;

  /// No description provided for @practiceRecommendationReasonUnrelated.
  ///
  /// In en, this message translates to:
  /// **'Little relation to current advice'**
  String get practiceRecommendationReasonUnrelated;

  /// No description provided for @learningMetricsTitle.
  ///
  /// In en, this message translates to:
  /// **'Learning effect (the review log decides)'**
  String get learningMetricsTitle;

  /// No description provided for @learningMetricsDetail.
  ///
  /// In en, this message translates to:
  /// **'Retention is \"how much was still there after that long\", read from review outcomes only - not from the model\'s own opinion of itself. Calibration waits for reviews that recorded a prediction.'**
  String get learningMetricsDetail;

  /// No description provided for @learningMetricsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No reviews yet - these numbers grow as you review.'**
  String get learningMetricsEmpty;

  /// No description provided for @learningMetricsNoBuckets.
  ///
  /// In en, this message translates to:
  /// **'There are reviews, but no second review of any card yet, so there is no interval to bucket.'**
  String get learningMetricsNoBuckets;

  /// No description provided for @learningMetricsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The review log could not be read (see the error above), so this block has no numbers.'**
  String get learningMetricsUnavailable;

  /// Review count and overall retention on the reading page
  ///
  /// In en, this message translates to:
  /// **'{reviewed} reviews, {retention}% recalled overall'**
  String learningMetricsOverall(Object reviewed, Object retention);

  /// One interval bucket: day range, review count, retention percent
  ///
  /// In en, this message translates to:
  /// **'{range} d: {samples} reviews, {retention}% recalled'**
  String learningMetricsBucket(Object range, Object samples, Object retention);

  /// Brier score and expected calibration error
  ///
  /// In en, this message translates to:
  /// **'Calibration: Brier {brier} (lower is better), ECE {ece} (per-bin gap between prediction and outcome)'**
  String learningMetricsCalibration(Object brier, Object ece);

  /// No description provided for @learningMetricsNoCalibration.
  ///
  /// In en, this message translates to:
  /// **'No calibration samples yet: from this version on, every review records what the model predicted before the answer. Old reviews have no such value and are not back-filled.'**
  String get learningMetricsNoCalibration;

  /// No description provided for @settingsThemeIcons.
  ///
  /// In en, this message translates to:
  /// **'Icons'**
  String get settingsThemeIcons;

  /// No description provided for @settingsThemeIconsHint.
  ///
  /// In en, this message translates to:
  /// **'Icons are set per semantic slot. A name this build does not know falls back to the slot\'s built-in icon.'**
  String get settingsThemeIconsHint;

  /// No description provided for @iconPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick an icon'**
  String get iconPickerTitle;

  /// No description provided for @iconPickerSearch.
  ///
  /// In en, this message translates to:
  /// **'Search icon names'**
  String get iconPickerSearch;

  /// No description provided for @iconPickerRestoreDefault.
  ///
  /// In en, this message translates to:
  /// **'Restore default'**
  String get iconPickerRestoreDefault;

  /// No description provided for @iconPickerDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get iconPickerDefault;

  /// No description provided for @iconPickerEmpty.
  ///
  /// In en, this message translates to:
  /// **'No icon matches that name'**
  String get iconPickerEmpty;

  /// No description provided for @iconCategoryCommon.
  ///
  /// In en, this message translates to:
  /// **'Common'**
  String get iconCategoryCommon;

  /// No description provided for @iconCategoryNavigation.
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get iconCategoryNavigation;

  /// No description provided for @iconCategoryTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get iconCategoryTime;

  /// No description provided for @iconCategoryKnowledge.
  ///
  /// In en, this message translates to:
  /// **'Knowledge'**
  String get iconCategoryKnowledge;

  /// No description provided for @iconCategoryObjects.
  ///
  /// In en, this message translates to:
  /// **'Objects'**
  String get iconCategoryObjects;

  /// No description provided for @iconCategoryMedia.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get iconCategoryMedia;

  /// No description provided for @iconCategoryPeople.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get iconCategoryPeople;

  /// No description provided for @iconCategoryAi.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get iconCategoryAi;

  /// No description provided for @iconCategoryUi.
  ///
  /// In en, this message translates to:
  /// **'Interface'**
  String get iconCategoryUi;

  /// No description provided for @questionIntakeTitle.
  ///
  /// In en, this message translates to:
  /// **'Question intake'**
  String get questionIntakeTitle;

  /// No description provided for @questionIntakeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Paste a question, photograph it, or browse the bank'**
  String get questionIntakeSubtitle;

  /// No description provided for @questionIntakeEntryHint.
  ///
  /// In en, this message translates to:
  /// **'Paste, photograph, browse'**
  String get questionIntakeEntryHint;

  /// No description provided for @questionBankRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh the question bank'**
  String get questionBankRefresh;

  /// No description provided for @questionBankFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the question bank: {message}'**
  String questionBankFailed(String message);

  /// No description provided for @questionBankEmpty.
  ///
  /// In en, this message translates to:
  /// **'The question bank is empty'**
  String get questionBankEmpty;

  /// No description provided for @questionBankEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Questions come from three places: intake (paste or pick a file), photo cleanup, and material intake. The AI never writes questions for you.'**
  String get questionBankEmptyHint;

  /// No description provided for @questionBankIntro.
  ///
  /// In en, this message translates to:
  /// **'The four buttons above add material to the bank; the list below filters by subject - tap a row for its detail and solution chain.'**
  String get questionBankIntro;

  /// No description provided for @questionBankSummary.
  ///
  /// In en, this message translates to:
  /// **'{questions} questions · {subjects} subjects'**
  String questionBankSummary(int questions, int subjects);

  /// No description provided for @questionBankAllSubjects.
  ///
  /// In en, this message translates to:
  /// **'All subjects'**
  String get questionBankAllSubjects;

  /// No description provided for @questionBankNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No questions in this subject yet'**
  String get questionBankNoMatch;

  /// No description provided for @questionBankUntitled.
  ///
  /// In en, this message translates to:
  /// **'(no stem)'**
  String get questionBankUntitled;

  /// No description provided for @questionBankPointCount.
  ///
  /// In en, this message translates to:
  /// **'{count} knowledge points'**
  String questionBankPointCount(int count);

  /// No description provided for @questionIntakePasteSection.
  ///
  /// In en, this message translates to:
  /// **'Paste a question'**
  String get questionIntakePasteSection;

  /// No description provided for @questionIntakePhotoSection.
  ///
  /// In en, this message translates to:
  /// **'Photograph / pick images'**
  String get questionIntakePhotoSection;

  /// No description provided for @questionIntakeLibrarySection.
  ///
  /// In en, this message translates to:
  /// **'Question bank'**
  String get questionIntakeLibrarySection;

  /// No description provided for @questionIntakeStemLabel.
  ///
  /// In en, this message translates to:
  /// **'Stem'**
  String get questionIntakeStemLabel;

  /// No description provided for @questionIntakeStemHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the stem as-is (formulas keep their LaTeX)'**
  String get questionIntakeStemHint;

  /// No description provided for @questionIntakeSubjectLabel.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get questionIntakeSubjectLabel;

  /// No description provided for @questionIntakeSubjectNone.
  ///
  /// In en, this message translates to:
  /// **'Unlabelled'**
  String get questionIntakeSubjectNone;

  /// No description provided for @questionIntakeQuestionTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Question type'**
  String get questionIntakeQuestionTypeLabel;

  /// No description provided for @questionIntakeTypeSolution.
  ///
  /// In en, this message translates to:
  /// **'Solution'**
  String get questionIntakeTypeSolution;

  /// No description provided for @questionIntakeTypeSingleChoice.
  ///
  /// In en, this message translates to:
  /// **'Single choice'**
  String get questionIntakeTypeSingleChoice;

  /// No description provided for @questionIntakeTypeMultiChoice.
  ///
  /// In en, this message translates to:
  /// **'Multiple choice'**
  String get questionIntakeTypeMultiChoice;

  /// No description provided for @questionIntakeOptionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get questionIntakeOptionsLabel;

  /// No description provided for @questionIntakeOptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Option {label}'**
  String questionIntakeOptionLabel(String label);

  /// No description provided for @questionIntakeOptionContentHint.
  ///
  /// In en, this message translates to:
  /// **'Option text'**
  String get questionIntakeOptionContentHint;

  /// No description provided for @questionIntakeAddOption.
  ///
  /// In en, this message translates to:
  /// **'Add an option'**
  String get questionIntakeAddOption;

  /// No description provided for @questionIntakeRemoveOption.
  ///
  /// In en, this message translates to:
  /// **'Remove this option'**
  String get questionIntakeRemoveOption;

  /// No description provided for @questionIntakeCorrectTooltip.
  ///
  /// In en, this message translates to:
  /// **'Mark as correct'**
  String get questionIntakeCorrectTooltip;

  /// No description provided for @questionIntakeAnswerLabel.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get questionIntakeAnswerLabel;

  /// No description provided for @questionIntakeSolutionLabel.
  ///
  /// In en, this message translates to:
  /// **'Solution notes'**
  String get questionIntakeSolutionLabel;

  /// No description provided for @questionIntakeSourceLevelLabel.
  ///
  /// In en, this message translates to:
  /// **'Source tier'**
  String get questionIntakeSourceLevelLabel;

  /// No description provided for @questionIntakeSourceLabelLabel.
  ///
  /// In en, this message translates to:
  /// **'Source label'**
  String get questionIntakeSourceLabelLabel;

  /// No description provided for @questionIntakeSourceLabelHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 2024 Hunan Normal University High School monthly exam'**
  String get questionIntakeSourceLabelHint;

  /// No description provided for @questionIntakeYearLabel.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get questionIntakeYearLabel;

  /// No description provided for @questionIntakeRegionLabel.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get questionIntakeRegionLabel;

  /// No description provided for @questionIntakeDifficultyLabel.
  ///
  /// In en, this message translates to:
  /// **'Difficulty (1–10, optional)'**
  String get questionIntakeDifficultyLabel;

  /// No description provided for @questionIntakeSubmit.
  ///
  /// In en, this message translates to:
  /// **'Save to bank'**
  String get questionIntakeSubmit;

  /// No description provided for @questionIntakeSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved: {stem}'**
  String questionIntakeSaved(String stem);

  /// No description provided for @questionIntakeDuplicate.
  ///
  /// In en, this message translates to:
  /// **'This question is already in the bank (same fingerprint): {stem}'**
  String questionIntakeDuplicate(String stem);

  /// No description provided for @questionIntakeStemRequired.
  ///
  /// In en, this message translates to:
  /// **'The stem cannot be empty'**
  String get questionIntakeStemRequired;

  /// No description provided for @questionIntakeDifficultyInvalid.
  ///
  /// In en, this message translates to:
  /// **'Difficulty must be a number between 1 and 10'**
  String get questionIntakeDifficultyInvalid;

  /// No description provided for @questionIntakePickImages.
  ///
  /// In en, this message translates to:
  /// **'Pick images / photograph'**
  String get questionIntakePickImages;

  /// No description provided for @questionIntakePicking.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get questionIntakePicking;

  /// No description provided for @questionIntakePhotoAdded.
  ///
  /// In en, this message translates to:
  /// **'Saved {count}; waiting for the AI to structure them'**
  String questionIntakePhotoAdded(int count);

  /// No description provided for @questionIntakePhotoFailed.
  ///
  /// In en, this message translates to:
  /// **'Picking images failed: {error}'**
  String questionIntakePhotoFailed(String error);

  /// No description provided for @questionIntakeDropHint.
  ///
  /// In en, this message translates to:
  /// **'You can also drag photos here (WeChat chat images work too)'**
  String get questionIntakeDropHint;

  /// No description provided for @questionIntakeDropActive.
  ///
  /// In en, this message translates to:
  /// **'Release to add the photos'**
  String get questionIntakeDropActive;

  /// No description provided for @questionIntakeDropBusy.
  ///
  /// In en, this message translates to:
  /// **'Still importing the previous photos; try again in a moment'**
  String get questionIntakeDropBusy;

  /// No description provided for @questionIntakeDropSkippedNonImage.
  ///
  /// In en, this message translates to:
  /// **'Skipped {count} non-image file(s)'**
  String questionIntakeDropSkippedNonImage(int count);

  /// No description provided for @questionIntakeDropDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Ignored {count} duplicate file(s)'**
  String questionIntakeDropDuplicates(int count);

  /// No description provided for @questionIntakeDropUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Could not read {count} file(s)'**
  String questionIntakeDropUnreadable(int count);

  /// No description provided for @questionAuditSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Intake audit'**
  String get questionAuditSectionTitle;

  /// No description provided for @questionAuditClean.
  ///
  /// In en, this message translates to:
  /// **'No hard issues found in this check'**
  String get questionAuditClean;

  /// No description provided for @questionAuditReadOnly.
  ///
  /// In en, this message translates to:
  /// **'The audit only reports; it never edits the question.'**
  String get questionAuditReadOnly;

  /// No description provided for @questionAuditEvidence.
  ///
  /// In en, this message translates to:
  /// **'Evidence'**
  String get questionAuditEvidence;

  /// No description provided for @questionAuditBadgeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Intake audit: {errors} error(s), {warnings} warning(s)'**
  String questionAuditBadgeTooltip(int errors, int warnings);

  /// No description provided for @questionAuditGroupHeader.
  ///
  /// In en, this message translates to:
  /// **'{label} · {count}'**
  String questionAuditGroupHeader(String label, int count);

  /// No description provided for @questionSerialUnnumbered.
  ///
  /// In en, this message translates to:
  /// **'TR-unassigned'**
  String get questionSerialUnnumbered;

  /// No description provided for @questionSerialCopyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy the question number'**
  String get questionSerialCopyTooltip;

  /// No description provided for @questionSerialCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied {label}'**
  String questionSerialCopied(String label);

  /// No description provided for @questionZujuanSearch.
  ///
  /// In en, this message translates to:
  /// **'Search this question on Zujuan'**
  String get questionZujuanSearch;

  /// No description provided for @questionZujuanCopyKeyword.
  ///
  /// In en, this message translates to:
  /// **'Copy keyword'**
  String get questionZujuanCopyKeyword;

  /// No description provided for @questionZujuanCopied.
  ///
  /// In en, this message translates to:
  /// **'Keyword copied: {keyword}'**
  String questionZujuanCopied(String keyword);

  /// No description provided for @questionZujuanNoCandidates.
  ///
  /// In en, this message translates to:
  /// **'No usable search keyword in the stem'**
  String get questionZujuanNoCandidates;

  /// No description provided for @questionZujuanBankHint.
  ///
  /// In en, this message translates to:
  /// **'Zujuan filters by your current subject. Switch to the matching subject on the site first, or searches may return nothing.'**
  String get questionZujuanBankHint;

  /// No description provided for @questionZujuanOpenUrl.
  ///
  /// In en, this message translates to:
  /// **'Open search page'**
  String get questionZujuanOpenUrl;

  /// No description provided for @questionZujuanUrlCopied.
  ///
  /// In en, this message translates to:
  /// **'Search page link copied: paste it in a browser to open'**
  String get questionZujuanUrlCopied;

  /// No description provided for @questionDetailImagesSection.
  ///
  /// In en, this message translates to:
  /// **'Question images'**
  String get questionDetailImagesSection;

  /// No description provided for @questionImageCount.
  ///
  /// In en, this message translates to:
  /// **'{count} image(s)'**
  String questionImageCount(int count);

  /// No description provided for @questionImageOpenTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open at full size'**
  String get questionImageOpenTooltip;

  /// No description provided for @questionImageLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'This image could not be loaded'**
  String get questionImageLoadFailed;

  /// No description provided for @questionImageAdd.
  ///
  /// In en, this message translates to:
  /// **'Add image'**
  String get questionImageAdd;

  /// No description provided for @questionImageAddDone.
  ///
  /// In en, this message translates to:
  /// **'Added {count} image(s)'**
  String questionImageAddDone(int count);

  /// No description provided for @questionImageAddSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped {count} file(s) that were not usable images'**
  String questionImageAddSkipped(int count);

  /// No description provided for @questionImageAddFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not add images: {error}'**
  String questionImageAddFailed(String error);

  /// No description provided for @questionImageHeicUnsupported.
  ///
  /// In en, this message translates to:
  /// **'HEIC images are not supported yet; convert them to JPG or PNG first'**
  String get questionImageHeicUnsupported;

  /// No description provided for @questionImageDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete this image'**
  String get questionImageDeleteTooltip;

  /// No description provided for @questionImageDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this image?'**
  String get questionImageDeleteTitle;

  /// No description provided for @questionImageDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get questionImageDeleteAction;

  /// No description provided for @questionImageDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Removes "{fileName}" from this question.'**
  String questionImageDeleteConfirm(String fileName);

  /// No description provided for @questionImageDeleted.
  ///
  /// In en, this message translates to:
  /// **'Image deleted'**
  String get questionImageDeleted;

  /// No description provided for @questionImageDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete the image: {error}'**
  String questionImageDeleteFailed(String error);

  /// No description provided for @questionImageEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'No images yet; add a photo of the question (HEIC is not supported yet)'**
  String get questionImageEmptyHint;

  /// No description provided for @questionAnswerImageTitle.
  ///
  /// In en, this message translates to:
  /// **'Answer & solution screenshots'**
  String get questionAnswerImageTitle;

  /// No description provided for @questionAnswerImageAdd.
  ///
  /// In en, this message translates to:
  /// **'Add answer screenshot'**
  String get questionAnswerImageAdd;

  /// No description provided for @questionAnswerImageEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'No answer screenshots yet: sign in on Zujuan and save a screenshot of the answer/solution (HEIC is not supported yet)'**
  String get questionAnswerImageEmptyHint;

  /// No description provided for @questionAnswerImageDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this screenshot?'**
  String get questionAnswerImageDeleteTitle;

  /// No description provided for @questionAnswerImageDeleted.
  ///
  /// In en, this message translates to:
  /// **'Screenshot deleted'**
  String get questionAnswerImageDeleted;

  /// No description provided for @questionIntakePhotoPending.
  ///
  /// In en, this message translates to:
  /// **'Images waiting'**
  String get questionIntakePhotoPending;

  /// No description provided for @questionIntakeNoPhotos.
  ///
  /// In en, this message translates to:
  /// **'No photos yet. Picked images are stored locally until the AI turns them into tags, knowledge points, flashcards or questions.'**
  String get questionIntakeNoPhotos;

  /// No description provided for @questionIntakePhotoSummary.
  ///
  /// In en, this message translates to:
  /// **'{mime} · .{extension}'**
  String questionIntakePhotoSummary(String mime, String extension);

  /// No description provided for @questionIntakePhotoStem.
  ///
  /// In en, this message translates to:
  /// **'To recognise (image): {filename}'**
  String questionIntakePhotoStem(String filename);

  /// No description provided for @questionIntakeRemovePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove from the list'**
  String get questionIntakeRemovePhoto;

  /// No description provided for @questionIntakeNoQuestions.
  ///
  /// In en, this message translates to:
  /// **'The question bank is still empty'**
  String get questionIntakeNoQuestions;

  /// No description provided for @questionIntakeListLimitNote.
  ///
  /// In en, this message translates to:
  /// **'Showing at most the most recent {count}'**
  String questionIntakeListLimitNote(int count);

  /// No description provided for @questionIntakeDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get questionIntakeDelete;

  /// No description provided for @questionIntakeDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted: {stem}'**
  String questionIntakeDeleted(String stem);

  /// No description provided for @questionIntakeDeletedWithImages.
  ///
  /// In en, this message translates to:
  /// **'Deleted: {stem} (removed {count} image(s))'**
  String questionIntakeDeletedWithImages(String stem, int count);

  /// No description provided for @questionIntakeDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this question? It will not come back from sync.'**
  String get questionIntakeDeleteConfirm;

  /// No description provided for @questionIntakeCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get questionIntakeCancel;

  /// No description provided for @questionIntakeSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search stems or serial numbers (multiple: TR-00001, 2-5)'**
  String get questionIntakeSearchHint;

  /// No description provided for @questionIntakeFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get questionIntakeFilterAll;

  /// No description provided for @questionIntakeOptionCount.
  ///
  /// In en, this message translates to:
  /// **'{count} options'**
  String questionIntakeOptionCount(int count);

  /// No description provided for @questionIntakeStateRaw.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get questionIntakeStateRaw;

  /// No description provided for @questionIntakeStateStructured.
  ///
  /// In en, this message translates to:
  /// **'Structured'**
  String get questionIntakeStateStructured;

  /// No description provided for @questionIntakeStateProcessed.
  ///
  /// In en, this message translates to:
  /// **'Processed'**
  String get questionIntakeStateProcessed;

  /// No description provided for @questionIntakeOriginManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get questionIntakeOriginManual;

  /// No description provided for @questionIntakeOriginAiScan.
  ///
  /// In en, this message translates to:
  /// **'Photo/scan'**
  String get questionIntakeOriginAiScan;

  /// No description provided for @questionIntakeOriginFurnace.
  ///
  /// In en, this message translates to:
  /// **'Built in Furnace'**
  String get questionIntakeOriginFurnace;

  /// No description provided for @questionIntakeSourceGaokao.
  ///
  /// In en, this message translates to:
  /// **'Gaokao paper'**
  String get questionIntakeSourceGaokao;

  /// No description provided for @questionIntakeSourceProvincialDiagnostic.
  ///
  /// In en, this message translates to:
  /// **'Provincial/city diagnostic'**
  String get questionIntakeSourceProvincialDiagnostic;

  /// No description provided for @questionIntakeSourceEliteSchool.
  ///
  /// In en, this message translates to:
  /// **'Elite school test'**
  String get questionIntakeSourceEliteSchool;

  /// No description provided for @questionIntakeSourceSchool.
  ///
  /// In en, this message translates to:
  /// **'School test'**
  String get questionIntakeSourceSchool;

  /// No description provided for @questionIntakeSourcePersonal.
  ///
  /// In en, this message translates to:
  /// **'Self-made'**
  String get questionIntakeSourcePersonal;

  /// No description provided for @questionIntakeSourceUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unlabelled'**
  String get questionIntakeSourceUnknown;

  /// No description provided for @zujuanPickOpenButton.
  ///
  /// In en, this message translates to:
  /// **'Find by filters'**
  String get zujuanPickOpenButton;

  /// No description provided for @zujuanPickTitle.
  ///
  /// In en, this message translates to:
  /// **'Find questions by filters'**
  String get zujuanPickTitle;

  /// No description provided for @zujuanPickIntro.
  ///
  /// In en, this message translates to:
  /// **'Pick filters and copy the link to open Zujuan in a browser; the app only builds the link and does not fetch pages.'**
  String get zujuanPickIntro;

  /// No description provided for @zujuanPickSubject.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get zujuanPickSubject;

  /// No description provided for @zujuanPickKnowledgePoint.
  ///
  /// In en, this message translates to:
  /// **'Knowledge point id'**
  String get zujuanPickKnowledgePoint;

  /// No description provided for @zujuanPickKnowledgePointHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty for all knowledge points of the subject'**
  String get zujuanPickKnowledgePointHint;

  /// No description provided for @zujuanPickDifficulty.
  ///
  /// In en, this message translates to:
  /// **'Difficulty'**
  String get zujuanPickDifficulty;

  /// No description provided for @zujuanPickAny.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get zujuanPickAny;

  /// No description provided for @zujuanPickYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get zujuanPickYear;

  /// No description provided for @zujuanPickYearEarlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get zujuanPickYearEarlier;

  /// No description provided for @zujuanPickProvince.
  ///
  /// In en, this message translates to:
  /// **'Province'**
  String get zujuanPickProvince;

  /// No description provided for @zujuanPickGrade.
  ///
  /// In en, this message translates to:
  /// **'Grade'**
  String get zujuanPickGrade;

  /// No description provided for @zujuanPickGradeSenior1.
  ///
  /// In en, this message translates to:
  /// **'Grade 10'**
  String get zujuanPickGradeSenior1;

  /// No description provided for @zujuanPickGradeSenior2.
  ///
  /// In en, this message translates to:
  /// **'Grade 11'**
  String get zujuanPickGradeSenior2;

  /// No description provided for @zujuanPickGradeSenior3.
  ///
  /// In en, this message translates to:
  /// **'Grade 12'**
  String get zujuanPickGradeSenior3;

  /// No description provided for @zujuanPickSort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get zujuanPickSort;

  /// No description provided for @zujuanPickUrl.
  ///
  /// In en, this message translates to:
  /// **'Search link'**
  String get zujuanPickUrl;

  /// No description provided for @zujuanPickCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get zujuanPickCopy;

  /// No description provided for @zujuanPickCopied.
  ///
  /// In en, this message translates to:
  /// **'Search link copied: paste it in a browser'**
  String get zujuanPickCopied;

  /// No description provided for @zujuanPickNoScrapeHint.
  ///
  /// In en, this message translates to:
  /// **'The app does not fetch Zujuan pages (the site blocks scraping). To see answers and solutions, sign in to Zujuan in your browser and view them there.'**
  String get zujuanPickNoScrapeHint;

  /// No description provided for @zujuanPickLoginHint.
  ///
  /// In en, this message translates to:
  /// **'Answers and solutions are visible after signing in to Zujuan (free accounts see about 30 questions per day). Paste viewed stems, answers, and solutions back in with Paste Zujuan questions.'**
  String get zujuanPickLoginHint;

  /// No description provided for @zujuanPasteOpenButton.
  ///
  /// In en, this message translates to:
  /// **'Paste Zujuan questions'**
  String get zujuanPasteOpenButton;

  /// No description provided for @zujuanPasteTitle.
  ///
  /// In en, this message translates to:
  /// **'Paste Zujuan questions'**
  String get zujuanPasteTitle;

  /// No description provided for @zujuanPasteIntro.
  ///
  /// In en, this message translates to:
  /// **'Copy question text from Zujuan (multiple questions are fine), parse it, then preview, select, edit stems, and import.'**
  String get zujuanPasteIntro;

  /// No description provided for @zujuanPasteLoginHint.
  ///
  /// In en, this message translates to:
  /// **'Zujuan answers require signing in (free accounts see about 30 questions per day). Paste answers and solutions in too and they will be recognized.'**
  String get zujuanPasteLoginHint;

  /// No description provided for @zujuanPasteInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Question text'**
  String get zujuanPasteInputLabel;

  /// No description provided for @zujuanPasteInputHint.
  ///
  /// In en, this message translates to:
  /// **'Paste question text with answers and solutions; separate questions with blank lines'**
  String get zujuanPasteInputHint;

  /// No description provided for @zujuanPasteParse.
  ///
  /// In en, this message translates to:
  /// **'Parse'**
  String get zujuanPasteParse;

  /// No description provided for @zujuanPasteParseEmpty.
  ///
  /// In en, this message translates to:
  /// **'No questions were parsed from this text: paste at least one question stem and try again.'**
  String get zujuanPasteParseEmpty;

  /// No description provided for @zujuanPastePreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} question(s) parsed'**
  String zujuanPastePreviewTitle(int count);

  /// No description provided for @zujuanPasteItemStem.
  ///
  /// In en, this message translates to:
  /// **'Stem (editable)'**
  String get zujuanPasteItemStem;

  /// No description provided for @zujuanPasteItemOptions.
  ///
  /// In en, this message translates to:
  /// **'{count} option(s)'**
  String zujuanPasteItemOptions(int count);

  /// No description provided for @zujuanPasteItemSource.
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String zujuanPasteItemSource(String source);

  /// No description provided for @zujuanPasteItemYear.
  ///
  /// In en, this message translates to:
  /// **'{year}'**
  String zujuanPasteItemYear(int year);

  /// No description provided for @zujuanPastePartial.
  ///
  /// In en, this message translates to:
  /// **'Incomplete parse: check the stem and options'**
  String get zujuanPastePartial;

  /// No description provided for @zujuanPasteImport.
  ///
  /// In en, this message translates to:
  /// **'Import all'**
  String get zujuanPasteImport;

  /// No description provided for @zujuanPasteImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing…'**
  String get zujuanPasteImporting;

  /// No description provided for @zujuanPasteNothingSelected.
  ///
  /// In en, this message translates to:
  /// **'Nothing selected: check the questions to import first.'**
  String get zujuanPasteNothingSelected;

  /// No description provided for @zujuanPasteSummary.
  ///
  /// In en, this message translates to:
  /// **'Imported {saved} · duplicates {duplicates} · failed {failed}'**
  String zujuanPasteSummary(int saved, int duplicates, int failed);

  /// No description provided for @zujuanPaperOpenButton.
  ///
  /// In en, this message translates to:
  /// **'Scan paper'**
  String get zujuanPaperOpenButton;

  /// No description provided for @zujuanPaperTitle.
  ///
  /// In en, this message translates to:
  /// **'Paper check'**
  String get zujuanPaperTitle;

  /// No description provided for @zujuanPaperIntro.
  ///
  /// In en, this message translates to:
  /// **'Paste the whole Zujuan paper page to see which questions are already in the library and which are missing. The app does not fetch pages; the check is local.'**
  String get zujuanPaperIntro;

  /// No description provided for @zujuanPaperInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Paste paper page'**
  String get zujuanPaperInputLabel;

  /// No description provided for @zujuanPaperInputHint.
  ///
  /// In en, this message translates to:
  /// **'The paper page URL or the whole page text; whatever select-all copy gives you in the browser'**
  String get zujuanPaperInputHint;

  /// No description provided for @zujuanPaperParse.
  ///
  /// In en, this message translates to:
  /// **'Parse'**
  String get zujuanPaperParse;

  /// No description provided for @zujuanPaperParseEmpty.
  ///
  /// In en, this message translates to:
  /// **'No questions recognised: paste the whole Zujuan paper page text (it must contain question links).'**
  String get zujuanPaperParseEmpty;

  /// No description provided for @zujuanPaperHeader.
  ///
  /// In en, this message translates to:
  /// **'{count} questions · {matched} in library · {missing} missing'**
  String zujuanPaperHeader(int count, int matched, int missing);

  /// No description provided for @zujuanPaperUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled paper'**
  String get zujuanPaperUntitled;

  /// No description provided for @zujuanPaperMatchedSection.
  ///
  /// In en, this message translates to:
  /// **'In library'**
  String get zujuanPaperMatchedSection;

  /// No description provided for @zujuanPaperMatchedItem.
  ///
  /// In en, this message translates to:
  /// **'{serial} · {preview}'**
  String zujuanPaperMatchedItem(String serial, String preview);

  /// No description provided for @zujuanPaperMissingSection.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get zujuanPaperMissingSection;

  /// No description provided for @zujuanPaperMissingWithLink.
  ///
  /// In en, this message translates to:
  /// **'{id} (link available)'**
  String zujuanPaperMissingWithLink(String id);

  /// No description provided for @zujuanPaperMissingNoLink.
  ///
  /// In en, this message translates to:
  /// **'{id} (no link)'**
  String zujuanPaperMissingNoLink(String id);

  /// No description provided for @zujuanPaperNoBank.
  ///
  /// In en, this message translates to:
  /// **'This page has no paper id (bankId), so missing-question links cannot be built; copy the question page links individually.'**
  String get zujuanPaperNoBank;

  /// No description provided for @zujuanPaperCopyMissing.
  ///
  /// In en, this message translates to:
  /// **'Copy missing links'**
  String get zujuanPaperCopyMissing;

  /// No description provided for @zujuanPaperCopied.
  ///
  /// In en, this message translates to:
  /// **'Missing links copied'**
  String get zujuanPaperCopied;

  /// No description provided for @zujuanPaperClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get zujuanPaperClose;

  /// No description provided for @questionDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Question detail'**
  String get questionDetailTitle;

  /// No description provided for @questionDetailQuestionMissing.
  ///
  /// In en, this message translates to:
  /// **'This question is no longer in the library (it may have just been deleted).'**
  String get questionDetailQuestionMissing;

  /// No description provided for @questionDetailEditSource.
  ///
  /// In en, this message translates to:
  /// **'Edit source'**
  String get questionDetailEditSource;

  /// No description provided for @questionDetailEditSourceTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit the source'**
  String get questionDetailEditSourceTitle;

  /// No description provided for @questionDetailEditSourceHint.
  ///
  /// In en, this message translates to:
  /// **'A field left empty is left unchanged; the stem, answer and options are never touched.'**
  String get questionDetailEditSourceHint;

  /// No description provided for @questionDetailEditSourceYearBad.
  ///
  /// In en, this message translates to:
  /// **'The year must be an integer between 1900 and 2200'**
  String get questionDetailEditSourceYearBad;

  /// No description provided for @questionSourceCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy original link'**
  String get questionSourceCopyLink;

  /// No description provided for @questionSourceCopyDone.
  ///
  /// In en, this message translates to:
  /// **'Original link copied'**
  String get questionSourceCopyDone;

  /// No description provided for @questionSourceZujuan.
  ///
  /// In en, this message translates to:
  /// **'Zujuan original'**
  String get questionSourceZujuan;

  /// No description provided for @questionSourceEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit source link'**
  String get questionSourceEdit;

  /// No description provided for @questionSourceAdd.
  ///
  /// In en, this message translates to:
  /// **'Add source link'**
  String get questionSourceAdd;

  /// No description provided for @questionSourceEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit source link'**
  String get questionSourceEditTitle;

  /// No description provided for @questionSourceEditInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Paste the original link or a Zujuan question page'**
  String get questionSourceEditInputLabel;

  /// No description provided for @questionSourceEditInputHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. /10q35583902.html or https://zujuan.xkw.com/10q35583902.html'**
  String get questionSourceEditInputHint;

  /// No description provided for @questionSourceEditPreviewUrl.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get questionSourceEditPreviewUrl;

  /// No description provided for @questionSourceEditPreviewQuestionId.
  ///
  /// In en, this message translates to:
  /// **'Zujuan question id'**
  String get questionSourceEditPreviewQuestionId;

  /// No description provided for @questionSourceEditPreviewBankId.
  ///
  /// In en, this message translates to:
  /// **'Zujuan bankId'**
  String get questionSourceEditPreviewBankId;

  /// No description provided for @questionSourceEditPreviewNoUrl.
  ///
  /// In en, this message translates to:
  /// **'No link saved'**
  String get questionSourceEditPreviewNoUrl;

  /// No description provided for @questionSourceEditEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Could not recognise a link or question id: paste a full URL, a /10q...html path, or a Zujuan question id (e.g. 10q35583902.html).'**
  String get questionSourceEditEmptyHint;

  /// No description provided for @questionSourceEditSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get questionSourceEditSave;

  /// No description provided for @questionSourceEditSaved.
  ///
  /// In en, this message translates to:
  /// **'Original link saved'**
  String get questionSourceEditSaved;

  /// No description provided for @questionSourceEditFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the original link: {error}'**
  String questionSourceEditFailed(String error);

  /// No description provided for @questionSourceEditClear.
  ///
  /// In en, this message translates to:
  /// **'Clear link'**
  String get questionSourceEditClear;

  /// No description provided for @questionSourceEditClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'This removes the original link from the question. Clear it?'**
  String get questionSourceEditClearConfirm;

  /// No description provided for @questionSourceEditCleared.
  ///
  /// In en, this message translates to:
  /// **'Original link cleared'**
  String get questionSourceEditCleared;

  /// No description provided for @questionSourceCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get questionSourceCancel;

  /// No description provided for @questionDetailCorrectOption.
  ///
  /// In en, this message translates to:
  /// **'correct'**
  String get questionDetailCorrectOption;

  /// No description provided for @questionDetailYear.
  ///
  /// In en, this message translates to:
  /// **'{year}'**
  String questionDetailYear(int year);

  /// No description provided for @questionDetailDifficulty.
  ///
  /// In en, this message translates to:
  /// **'Difficulty {value}'**
  String questionDetailDifficulty(String value);

  /// No description provided for @questionDetailAiQuality.
  ///
  /// In en, this message translates to:
  /// **'AI self-rated quality {value}'**
  String questionDetailAiQuality(String value);

  /// No description provided for @questionDetailTrapNote.
  ///
  /// In en, this message translates to:
  /// **'Trap'**
  String get questionDetailTrapNote;

  /// No description provided for @questionDetailReasoningSection.
  ///
  /// In en, this message translates to:
  /// **'AI solving and stuck-point review'**
  String get questionDetailReasoningSection;

  /// No description provided for @questionDetailSolveButton.
  ///
  /// In en, this message translates to:
  /// **'Solve with AI'**
  String get questionDetailSolveButton;

  /// No description provided for @questionDetailResolveButton.
  ///
  /// In en, this message translates to:
  /// **'Solve again'**
  String get questionDetailResolveButton;

  /// No description provided for @questionDetailSolving.
  ///
  /// In en, this message translates to:
  /// **'Solving…'**
  String get questionDetailSolving;

  /// No description provided for @questionDetailNoChainYet.
  ///
  /// In en, this message translates to:
  /// **'No reasoning chain yet. Use the button above to have the AI solve it; the chain is saved to your local library.'**
  String get questionDetailNoChainYet;

  /// No description provided for @questionDetailChainFromLibrary.
  ///
  /// In en, this message translates to:
  /// **'Below is the chain saved by the most recent run; solving again saves a new one.'**
  String get questionDetailChainFromLibrary;

  /// No description provided for @questionDetailRunFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'This run did not succeed'**
  String get questionDetailRunFailedTitle;

  /// No description provided for @questionDetailFailureReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get questionDetailFailureReasonLabel;

  /// No description provided for @questionDetailRawReplyLabel.
  ///
  /// In en, this message translates to:
  /// **'Raw model reply'**
  String get questionDetailRawReplyLabel;

  /// No description provided for @questionDetailRawReplyMissing.
  ///
  /// In en, this message translates to:
  /// **'(no raw reply was kept)'**
  String get questionDetailRawReplyMissing;

  /// No description provided for @questionDetailOverallRisk.
  ///
  /// In en, this message translates to:
  /// **'Highest stuck-point risk in the chain: about {percent}%'**
  String questionDetailOverallRisk(int percent);

  /// No description provided for @questionDetailMostLikelyStep.
  ///
  /// In en, this message translates to:
  /// **'The step you are most likely to get stuck on is step {index}'**
  String questionDetailMostLikelyStep(int index);

  /// No description provided for @questionDetailEvidenceCoverage.
  ///
  /// In en, this message translates to:
  /// **'{covered} of {total} steps have your state readings'**
  String questionDetailEvidenceCoverage(int covered, int total);

  /// No description provided for @questionDetailStepTitle.
  ///
  /// In en, this message translates to:
  /// **'Step {index}'**
  String questionDetailStepTitle(int index);

  /// No description provided for @questionDetailUnknownAction.
  ///
  /// In en, this message translates to:
  /// **'Action not in the catalogue: {actionType}'**
  String questionDetailUnknownAction(String actionType);

  /// No description provided for @questionDetailStepGoalLabel.
  ///
  /// In en, this message translates to:
  /// **'What this step achieves'**
  String get questionDetailStepGoalLabel;

  /// No description provided for @questionDetailStepJustificationLabel.
  ///
  /// In en, this message translates to:
  /// **'Why it holds'**
  String get questionDetailStepJustificationLabel;

  /// No description provided for @questionDetailStepCheckLabel.
  ///
  /// In en, this message translates to:
  /// **'How to check'**
  String get questionDetailStepCheckLabel;

  /// No description provided for @questionDetailStepKnowledgeLabel.
  ///
  /// In en, this message translates to:
  /// **'Knowledge points involved'**
  String get questionDetailStepKnowledgeLabel;

  /// No description provided for @questionDetailModelRisk.
  ///
  /// In en, this message translates to:
  /// **'Model\'s risk judgement: about {percent}%'**
  String questionDetailModelRisk(int percent);

  /// No description provided for @questionDetailFusedRisk.
  ///
  /// In en, this message translates to:
  /// **'Combined with your state readings: about {percent}%'**
  String questionDetailFusedRisk(int percent);

  /// No description provided for @questionDetailSuggestionLabel.
  ///
  /// In en, this message translates to:
  /// **'Suggestion'**
  String get questionDetailSuggestionLabel;

  /// No description provided for @questionDetailUnmatchedHintsTitle.
  ///
  /// In en, this message translates to:
  /// **'No state readings for these knowledge points'**
  String get questionDetailUnmatchedHintsTitle;

  /// No description provided for @questionDetailUnmatchedHintsBody.
  ///
  /// In en, this message translates to:
  /// **'That does not mean they are fine - it means no memory reading is stored for them yet.'**
  String get questionDetailUnmatchedHintsBody;

  /// No description provided for @questionDetailKnowledgePointsLabel.
  ///
  /// In en, this message translates to:
  /// **'Knowledge points linked to this question'**
  String get questionDetailKnowledgePointsLabel;

  /// No description provided for @questionDetailKnowledgePointNoReading.
  ///
  /// In en, this message translates to:
  /// **'No state readings yet'**
  String get questionDetailKnowledgePointNoReading;

  /// No description provided for @questionDetailStatesLoading.
  ///
  /// In en, this message translates to:
  /// **'Reading your learning state…'**
  String get questionDetailStatesLoading;

  /// No description provided for @questionDetailStatesFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the state readings: {error}'**
  String questionDetailStatesFailed(String error);

  /// No description provided for @questionPaperTitle.
  ///
  /// In en, this message translates to:
  /// **'Build a paper'**
  String get questionPaperTitle;

  /// No description provided for @questionPaperEntryHint.
  ///
  /// In en, this message translates to:
  /// **'Assemble a practice paper from your weak and at-risk points'**
  String get questionPaperEntryHint;

  /// No description provided for @questionPaperSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Picks only from questions you already have: at-risk points first, gaps listed honestly - AI never writes questions for you.'**
  String get questionPaperSubtitle;

  /// No description provided for @questionPaperTargetCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Target question count'**
  String get questionPaperTargetCountLabel;

  /// No description provided for @questionPaperCountOption.
  ///
  /// In en, this message translates to:
  /// **'{count} questions'**
  String questionPaperCountOption(int count);

  /// No description provided for @questionPaperSubjectLabel.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get questionPaperSubjectLabel;

  /// No description provided for @questionPaperSubjectAny.
  ///
  /// In en, this message translates to:
  /// **'Any subject'**
  String get questionPaperSubjectAny;

  /// No description provided for @questionPaperSubjectNone.
  ///
  /// In en, this message translates to:
  /// **'No subject'**
  String get questionPaperSubjectNone;

  /// No description provided for @questionPaperSourceLevelLabel.
  ///
  /// In en, this message translates to:
  /// **'Minimum source level'**
  String get questionPaperSourceLevelLabel;

  /// No description provided for @questionPaperSourceLevelAny.
  ///
  /// In en, this message translates to:
  /// **'Any source'**
  String get questionPaperSourceLevelAny;

  /// No description provided for @questionPaperHeadline.
  ///
  /// In en, this message translates to:
  /// **'Wanted {want}, assembled {got}'**
  String questionPaperHeadline(int want, int got);

  /// No description provided for @questionPaperFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not build the paper: {error}'**
  String questionPaperFailed(String error);

  /// No description provided for @questionPaperShortNotice.
  ///
  /// In en, this message translates to:
  /// **'Not enough questions locally - not an error, your bank simply does not have enough yet. Collect more and come back.'**
  String get questionPaperShortNotice;

  /// No description provided for @questionPaperOverallNeed.
  ///
  /// In en, this message translates to:
  /// **'Overall training need {need}'**
  String questionPaperOverallNeed(String need);

  /// No description provided for @questionPaperCandidateCount.
  ///
  /// In en, this message translates to:
  /// **'{count} candidates'**
  String questionPaperCandidateCount(int count);

  /// No description provided for @questionPaperEmptyBank.
  ///
  /// In en, this message translates to:
  /// **'Your question bank is empty: collect questions first, then come back.'**
  String get questionPaperEmptyBank;

  /// No description provided for @questionPaperEmptyPlan.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches the current filters: loosen the subject or the source level.'**
  String get questionPaperEmptyPlan;

  /// No description provided for @questionPaperUncoveredTitle.
  ///
  /// In en, this message translates to:
  /// **'No candidates in your bank → collect questions'**
  String get questionPaperUncoveredTitle;

  /// No description provided for @questionPaperUncoveredBody.
  ///
  /// In en, this message translates to:
  /// **'These knowledge points are at risk but your bank has no related question. AI does not write questions, so this stays empty on purpose.'**
  String get questionPaperUncoveredBody;

  /// No description provided for @questionPaperDeferredTitle.
  ///
  /// In en, this message translates to:
  /// **'Pushed out this round'**
  String get questionPaperDeferredTitle;

  /// No description provided for @questionPaperDeferredBody.
  ///
  /// In en, this message translates to:
  /// **'Candidates exist but were pushed out by the target count or the per-point cap; raise the target count.'**
  String get questionPaperDeferredBody;

  /// No description provided for @questionPaperKnowledgePointLabel.
  ///
  /// In en, this message translates to:
  /// **'Knowledge point'**
  String get questionPaperKnowledgePointLabel;

  /// No description provided for @questionPaperKnowledgePointNone.
  ///
  /// In en, this message translates to:
  /// **'No knowledge point'**
  String get questionPaperKnowledgePointNone;

  /// No description provided for @questionPaperItemIndex.
  ///
  /// In en, this message translates to:
  /// **'Question {index}'**
  String questionPaperItemIndex(int index);

  /// No description provided for @questionPaperItemReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Why it is here'**
  String get questionPaperItemReasonLabel;

  /// No description provided for @questionPaperItemImprovementLabel.
  ///
  /// In en, this message translates to:
  /// **'What it improves'**
  String get questionPaperItemImprovementLabel;

  /// No description provided for @questionPaperItemBackgroundLabel.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get questionPaperItemBackgroundLabel;

  /// No description provided for @questionSimilarTitle.
  ///
  /// In en, this message translates to:
  /// **'Similar questions'**
  String get questionSimilarTitle;

  /// No description provided for @questionSimilarSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Searches the existing question bank only. When nothing is similar it says so instead of padding the list.'**
  String get questionSimilarSubtitle;

  /// No description provided for @questionSimilarLoading.
  ///
  /// In en, this message translates to:
  /// **'Scanning the question bank…'**
  String get questionSimilarLoading;

  /// No description provided for @questionSimilarFailed.
  ///
  /// In en, this message translates to:
  /// **'Similar-question search failed: {error}'**
  String questionSimilarFailed(String error);

  /// No description provided for @questionSimilarCount.
  ///
  /// In en, this message translates to:
  /// **'Found {count} similar question(s)'**
  String questionSimilarCount(int count);

  /// No description provided for @questionSimilarEmpty.
  ///
  /// In en, this message translates to:
  /// **'No similar questions in the bank yet.'**
  String get questionSimilarEmpty;

  /// No description provided for @questionSimilarGoIntake.
  ///
  /// In en, this message translates to:
  /// **'Add questions'**
  String get questionSimilarGoIntake;

  /// No description provided for @questionSimilarCrossSubject.
  ///
  /// In en, this message translates to:
  /// **'Cross-subject transfer'**
  String get questionSimilarCrossSubject;

  /// No description provided for @handwritingQueueTitle.
  ///
  /// In en, this message translates to:
  /// **'Handwriting intake'**
  String get handwritingQueueTitle;

  /// No description provided for @handwritingQueueEntryHint.
  ///
  /// In en, this message translates to:
  /// **'Turn photos into tags, knowledge points, flashcards or questions - confirmed one by one before anything is written'**
  String get handwritingQueueEntryHint;

  /// No description provided for @handwritingQueueSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The model only organises what is really on the page (questions are transcribed, never invented); every item is written only after you confirm it.'**
  String get handwritingQueueSubtitle;

  /// No description provided for @handwritingQueueEmpty.
  ///
  /// In en, this message translates to:
  /// **'No photos yet. Take one on the intake page, then come back here.'**
  String get handwritingQueueEmpty;

  /// No description provided for @handwritingQueueGoIntake.
  ///
  /// In en, this message translates to:
  /// **'Open intake page'**
  String get handwritingQueueGoIntake;

  /// No description provided for @handwritingQueuePhotosLabel.
  ///
  /// In en, this message translates to:
  /// **'Photos to organise'**
  String get handwritingQueuePhotosLabel;

  /// No description provided for @handwritingQueueOrganizeAction.
  ///
  /// In en, this message translates to:
  /// **'Organise this'**
  String get handwritingQueueOrganizeAction;

  /// No description provided for @handwritingQueueAnalyze.
  ///
  /// In en, this message translates to:
  /// **'Organise this photo'**
  String get handwritingQueueAnalyze;

  /// No description provided for @handwritingQueueAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Reading the photo...'**
  String get handwritingQueueAnalyzing;

  /// No description provided for @handwritingQueueNotAnalyzed.
  ///
  /// In en, this message translates to:
  /// **'This photo has not been organised yet.'**
  String get handwritingQueueNotAnalyzed;

  /// No description provided for @handwritingQueueNothingFound.
  ///
  /// In en, this message translates to:
  /// **'The model proposed nothing to organise: this page may have no tags, knowledge points, cards or questions.'**
  String get handwritingQueueNothingFound;

  /// No description provided for @handwritingQueueFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'This run failed'**
  String get handwritingQueueFailureTitle;

  /// No description provided for @handwritingQueueForget.
  ///
  /// In en, this message translates to:
  /// **'Discard result'**
  String get handwritingQueueForget;

  /// No description provided for @handwritingQueueProposalsLabel.
  ///
  /// In en, this message translates to:
  /// **'Proposals to confirm'**
  String get handwritingQueueProposalsLabel;

  /// No description provided for @handwritingQueueApplyAll.
  ///
  /// In en, this message translates to:
  /// **'Confirm all'**
  String get handwritingQueueApplyAll;

  /// No description provided for @handwritingQueueApplying.
  ///
  /// In en, this message translates to:
  /// **'Writing...'**
  String get handwritingQueueApplying;

  /// No description provided for @handwritingQueueReportSummary.
  ///
  /// In en, this message translates to:
  /// **'This confirmation: {applied} succeeded, {failed} failed'**
  String handwritingQueueReportSummary(int applied, int failed);

  /// No description provided for @handwritingProposalApply.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get handwritingProposalApply;

  /// No description provided for @handwritingProposalApplied.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get handwritingProposalApplied;

  /// No description provided for @handwritingProposalConfidence.
  ///
  /// In en, this message translates to:
  /// **'Model confidence: {band}'**
  String handwritingProposalConfidence(String band);

  /// No description provided for @handwritingProposalConfidenceHigh.
  ///
  /// In en, this message translates to:
  /// **'fairly sure'**
  String get handwritingProposalConfidenceHigh;

  /// No description provided for @handwritingProposalConfidenceMedium.
  ///
  /// In en, this message translates to:
  /// **'unsure'**
  String get handwritingProposalConfidenceMedium;

  /// No description provided for @handwritingProposalConfidenceLow.
  ///
  /// In en, this message translates to:
  /// **'not sure'**
  String get handwritingProposalConfidenceLow;

  /// No description provided for @handwritingProposalCardCount.
  ///
  /// In en, this message translates to:
  /// **'{count} card(s)'**
  String handwritingProposalCardCount(int count);

  /// No description provided for @handwritingQuestionMissingStem.
  ///
  /// In en, this message translates to:
  /// **'The stem was not recognised; retake the photo or type it in'**
  String get handwritingQuestionMissingStem;

  /// No description provided for @handwritingQuestionOptions.
  ///
  /// In en, this message translates to:
  /// **'Options ({count})'**
  String handwritingQuestionOptions(int count);

  /// No description provided for @handwritingQuestionAnswer.
  ///
  /// In en, this message translates to:
  /// **'Answer: {value}'**
  String handwritingQuestionAnswer(String value);

  /// No description provided for @handwritingQuestionSolution.
  ///
  /// In en, this message translates to:
  /// **'Solution: {value}'**
  String handwritingQuestionSolution(String value);

  /// No description provided for @handwritingQuestionEmptyValue.
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get handwritingQuestionEmptyValue;

  /// No description provided for @handwritingQuestionEditForIntake.
  ///
  /// In en, this message translates to:
  /// **'Edit and save'**
  String get handwritingQuestionEditForIntake;

  /// No description provided for @handwritingQuestionSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved as {serial} (handwriting item marked as confirmed)'**
  String handwritingQuestionSaved(String serial);

  /// No description provided for @handwritingQuestionSavedUnnumbered.
  ///
  /// In en, this message translates to:
  /// **'Saved (unnumbered; handwriting item marked as confirmed)'**
  String get handwritingQuestionSavedUnnumbered;

  /// No description provided for @handwritingQueuePreviewLoading.
  ///
  /// In en, this message translates to:
  /// **'Checking what will happen…'**
  String get handwritingQueuePreviewLoading;

  /// No description provided for @handwritingQueuePreviewNeedsReview.
  ///
  /// In en, this message translates to:
  /// **'Review before confirming'**
  String get handwritingQueuePreviewNeedsReview;

  /// No description provided for @handwritingQueuePreviewBlocked.
  ///
  /// In en, this message translates to:
  /// **'Cannot confirm'**
  String get handwritingQueuePreviewBlocked;

  /// No description provided for @handwritingQueuePreviewBlockedSummary.
  ///
  /// In en, this message translates to:
  /// **'{ready} ready, {needsReview} to review, {blocked} blocked'**
  String handwritingQueuePreviewBlockedSummary(
      int ready, int needsReview, int blocked);

  /// No description provided for @questionPaperDifficultyLabel.
  ///
  /// In en, this message translates to:
  /// **'Target difficulty'**
  String get questionPaperDifficultyLabel;

  /// No description provided for @questionPaperDifficultyAny.
  ///
  /// In en, this message translates to:
  /// **'Any difficulty'**
  String get questionPaperDifficultyAny;

  /// No description provided for @questionPaperDifficultyOption.
  ///
  /// In en, this message translates to:
  /// **'Difficulty {value}'**
  String questionPaperDifficultyOption(String value);

  /// No description provided for @questionPaperDifficultyHint.
  ///
  /// In en, this message translates to:
  /// **'Difficulty is a preference, not a hard filter: closer questions rank higher, and questions with no difficulty value are treated as half-fit (ranked lower, never excluded).'**
  String get questionPaperDifficultyHint;

  /// No description provided for @questionPaperCapLabel.
  ///
  /// In en, this message translates to:
  /// **'Per knowledge point cap'**
  String get questionPaperCapLabel;

  /// No description provided for @questionPaperCapAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get questionPaperCapAuto;

  /// No description provided for @questionPaperCapOption.
  ///
  /// In en, this message translates to:
  /// **'Up to {cap}'**
  String questionPaperCapOption(int cap);

  /// No description provided for @questionPaperReset.
  ///
  /// In en, this message translates to:
  /// **'Reset paper settings'**
  String get questionPaperReset;

  /// No description provided for @questionPaperActionProfileLabel.
  ///
  /// In en, this message translates to:
  /// **'Order by capability profile (uncalibrated)'**
  String get questionPaperActionProfileLabel;

  /// No description provided for @questionPaperActionProfileHint.
  ///
  /// In en, this message translates to:
  /// **'Questions that hit the moves you struggle with move up a little; does nothing when you have no solved chains, and can be turned off.'**
  String get questionPaperActionProfileHint;

  /// No description provided for @questionPaperActionProfileNote.
  ///
  /// In en, this message translates to:
  /// **'This paper was ordered by your \"{actions}\" moves (uncalibrated, can be turned off)'**
  String questionPaperActionProfileNote(String actions);

  /// No description provided for @questionPaperCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy paper'**
  String get questionPaperCopy;

  /// No description provided for @questionPaperCopyDone.
  ///
  /// In en, this message translates to:
  /// **'Paper copied — paste it into Word or a print preview.'**
  String get questionPaperCopyDone;

  /// No description provided for @questionPaperCopyReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get questionPaperCopyReasonLabel;

  /// No description provided for @questionPaperCopyImprovementLabel.
  ///
  /// In en, this message translates to:
  /// **'Improvement'**
  String get questionPaperCopyImprovementLabel;

  /// No description provided for @questionPaperCopyBackgroundLabel.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get questionPaperCopyBackgroundLabel;

  /// No description provided for @questionPaperCopyUncoveredHeading.
  ///
  /// In en, this message translates to:
  /// **'Knowledge points with no candidates'**
  String get questionPaperCopyUncoveredHeading;

  /// No description provided for @questionPaperCopyDeferredHeading.
  ///
  /// In en, this message translates to:
  /// **'Knowledge points blocked by the cap'**
  String get questionPaperCopyDeferredHeading;

  /// No description provided for @questionPaperExportDocx.
  ///
  /// In en, this message translates to:
  /// **'Export Word'**
  String get questionPaperExportDocx;

  /// No description provided for @questionPaperExportDocxBusy.
  ///
  /// In en, this message translates to:
  /// **'Exporting…'**
  String get questionPaperExportDocxBusy;

  /// No description provided for @questionPaperExportDocxDone.
  ///
  /// In en, this message translates to:
  /// **'Exported {questions} question(s) with {images} image(s): {fileName}'**
  String questionPaperExportDocxDone(
      int questions, int images, String fileName);

  /// No description provided for @questionPaperExportDocxEmptyDone.
  ///
  /// In en, this message translates to:
  /// **'The paper is empty: only the title and gap notes were exported ({fileName})'**
  String questionPaperExportDocxEmptyDone(String fileName);

  /// No description provided for @questionPaperExportDocxFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get questionPaperExportDocxFailed;

  /// No description provided for @questionPaperExportDocxWarnings.
  ///
  /// In en, this message translates to:
  /// **'{count} warning(s)'**
  String questionPaperExportDocxWarnings(int count);

  /// No description provided for @questionPaperExportDocxWarningsAction.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get questionPaperExportDocxWarningsAction;

  /// No description provided for @questionPaperExportDocxWarningsTitle.
  ///
  /// In en, this message translates to:
  /// **'Export warnings'**
  String get questionPaperExportDocxWarningsTitle;

  /// No description provided for @questionPaperExportDocxMissingQuestions.
  ///
  /// In en, this message translates to:
  /// **'Missing questions'**
  String get questionPaperExportDocxMissingQuestions;

  /// No description provided for @questionPaperExportDocxSkippedImages.
  ///
  /// In en, this message translates to:
  /// **'Skipped images'**
  String get questionPaperExportDocxSkippedImages;

  /// No description provided for @questionPaperExportDocxFormulaFailures.
  ///
  /// In en, this message translates to:
  /// **'Formula compilation failures'**
  String get questionPaperExportDocxFormulaFailures;

  /// No description provided for @questionPaperExportDocxImageLoadNotes.
  ///
  /// In en, this message translates to:
  /// **'Image notes'**
  String get questionPaperExportDocxImageLoadNotes;

  /// No description provided for @questionPaperExportDocxMissingFields.
  ///
  /// In en, this message translates to:
  /// **'Missing fields'**
  String get questionPaperExportDocxMissingFields;

  /// No description provided for @questionPaperExportDocxMissingStem.
  ///
  /// In en, this message translates to:
  /// **'{count} missing stem(s)'**
  String questionPaperExportDocxMissingStem(int count);

  /// No description provided for @questionPaperExportDocxMissingAnswer.
  ///
  /// In en, this message translates to:
  /// **'{count} missing answer(s)'**
  String questionPaperExportDocxMissingAnswer(int count);

  /// No description provided for @questionPaperExportDocxMissingSolution.
  ///
  /// In en, this message translates to:
  /// **'{count} missing solution(s)'**
  String questionPaperExportDocxMissingSolution(int count);

  /// No description provided for @questionPaperExportDocxMoreItems.
  ///
  /// In en, this message translates to:
  /// **'and {count} more'**
  String questionPaperExportDocxMoreItems(int count);

  /// No description provided for @paperSubjectQuotaTitle.
  ///
  /// In en, this message translates to:
  /// **'Subject quotas'**
  String get paperSubjectQuotaTitle;

  /// No description provided for @paperSubjectQuotaHint.
  ///
  /// In en, this message translates to:
  /// **'Blank = no limit; a max of 0 selects none from that subject.'**
  String get paperSubjectQuotaHint;

  /// No description provided for @paperSubjectQuotaNoSubjects.
  ///
  /// In en, this message translates to:
  /// **'Subject quotas only apply to selected subjects: pick subjects above, then set a max or minimum for each.'**
  String get paperSubjectQuotaNoSubjects;

  /// No description provided for @paperSubjectQuotaMaxLabel.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get paperSubjectQuotaMaxLabel;

  /// No description provided for @paperSubjectQuotaMinLabel.
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get paperSubjectQuotaMinLabel;

  /// No description provided for @paperSubjectQuotaClear.
  ///
  /// In en, this message translates to:
  /// **'Clear quotas'**
  String get paperSubjectQuotaClear;

  /// No description provided for @paperSubjectQuotaInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a non-negative whole number'**
  String get paperSubjectQuotaInvalid;

  /// No description provided for @paperSubjectDistribution.
  ///
  /// In en, this message translates to:
  /// **'Subject distribution'**
  String get paperSubjectDistribution;

  /// No description provided for @paperSubjectQuotaBlocked.
  ///
  /// In en, this message translates to:
  /// **'{count} question(s) blocked by subject caps'**
  String paperSubjectQuotaBlocked(int count);

  /// No description provided for @paperSubjectQuotaBlockedItem.
  ///
  /// In en, this message translates to:
  /// **'{subject} (limit {limit}): {detail}'**
  String paperSubjectQuotaBlockedItem(String subject, int limit, String detail);

  /// No description provided for @paperSubjectQuotaBlockedMore.
  ///
  /// In en, this message translates to:
  /// **'and {count} more blocked question(s)'**
  String paperSubjectQuotaBlockedMore(int count);

  /// No description provided for @paperSubjectQuotaShortfallTitle.
  ///
  /// In en, this message translates to:
  /// **'Minimum shortfalls'**
  String get paperSubjectQuotaShortfallTitle;

  /// No description provided for @paperSubjectQuotaShortfall.
  ///
  /// In en, this message translates to:
  /// **'{subject}: short by {missing} (available: {available})'**
  String paperSubjectQuotaShortfall(String subject, int missing, int available);

  /// No description provided for @paperSubjectQuotaShortfallEmpty.
  ///
  /// In en, this message translates to:
  /// **'No usable questions for {subject} in the bank'**
  String paperSubjectQuotaShortfallEmpty(String subject);

  /// No description provided for @paperDomainQuotaTitle.
  ///
  /// In en, this message translates to:
  /// **'Domain quotas'**
  String get paperDomainQuotaTitle;

  /// No description provided for @paperDomainQuotaHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty for no cap; a cap of 0 excludes the domain entirely. Domains are the first segment of a knowledge-point tag path, separate from the subject quota above.'**
  String get paperDomainQuotaHint;

  /// No description provided for @paperDomainQuotaMaxLabel.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get paperDomainQuotaMaxLabel;

  /// No description provided for @paperDomainQuotaMinLabel.
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get paperDomainQuotaMinLabel;

  /// No description provided for @paperDomainQuotaClear.
  ///
  /// In en, this message translates to:
  /// **'Clear quotas'**
  String get paperDomainQuotaClear;

  /// No description provided for @paperDomainQuotaInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a non-negative whole number'**
  String get paperDomainQuotaInvalid;

  /// No description provided for @paperDomainQuotaDistribution.
  ///
  /// In en, this message translates to:
  /// **'Domain distribution'**
  String get paperDomainQuotaDistribution;

  /// No description provided for @paperDomainQuotaBlocked.
  ///
  /// In en, this message translates to:
  /// **'{count} question(s) blocked by domain caps'**
  String paperDomainQuotaBlocked(int count);

  /// No description provided for @paperDomainQuotaBlockedItem.
  ///
  /// In en, this message translates to:
  /// **'{domain} (cap {limit}): {detail}'**
  String paperDomainQuotaBlockedItem(String domain, int limit, String detail);

  /// No description provided for @paperDomainQuotaBlockedMore.
  ///
  /// In en, this message translates to:
  /// **'and {count} more blocked question(s)'**
  String paperDomainQuotaBlockedMore(int count);

  /// No description provided for @paperDomainQuotaShortfallTitle.
  ///
  /// In en, this message translates to:
  /// **'Domain minimum shortfalls'**
  String get paperDomainQuotaShortfallTitle;

  /// No description provided for @paperDomainQuotaShortfall.
  ///
  /// In en, this message translates to:
  /// **'{domain}: short by {missing} (available: {available})'**
  String paperDomainQuotaShortfall(String domain, int missing, int available);

  /// No description provided for @paperDomainQuotaShortfallEmpty.
  ///
  /// In en, this message translates to:
  /// **'No usable questions for {domain} in the bank'**
  String paperDomainQuotaShortfallEmpty(String domain);

  /// No description provided for @paperDomainQuotaUncovered.
  ///
  /// In en, this message translates to:
  /// **'Uncovered domains: {domains}'**
  String paperDomainQuotaUncovered(String domains);

  /// No description provided for @paperManualSelectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Manual selection'**
  String get paperManualSelectionTitle;

  /// No description provided for @paperManualSelectionAdd.
  ///
  /// In en, this message translates to:
  /// **'Choose questions'**
  String get paperManualSelectionAdd;

  /// No description provided for @paperManualSelectionHint.
  ///
  /// In en, this message translates to:
  /// **'Mandatory questions are always included (capped only by the target count); excluded questions are never picked; exclusion wins on conflicts.'**
  String get paperManualSelectionHint;

  /// No description provided for @paperManualSelectionIncludeTitle.
  ///
  /// In en, this message translates to:
  /// **'Mandatory ({count})'**
  String paperManualSelectionIncludeTitle(int count);

  /// No description provided for @paperManualSelectionExcludeTitle.
  ///
  /// In en, this message translates to:
  /// **'Excluded ({count})'**
  String paperManualSelectionExcludeTitle(int count);

  /// No description provided for @paperManualSelectionRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get paperManualSelectionRemove;

  /// No description provided for @paperManualSelectionClear.
  ///
  /// In en, this message translates to:
  /// **'Clear manual selection'**
  String get paperManualSelectionClear;

  /// No description provided for @paperManualSelectionPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose questions'**
  String get paperManualSelectionPickerTitle;

  /// No description provided for @paperManualSelectionPickerFilterHint.
  ///
  /// In en, this message translates to:
  /// **'Filter by stem or question ID'**
  String get paperManualSelectionPickerFilterHint;

  /// No description provided for @paperManualSelectionPickerInclude.
  ///
  /// In en, this message translates to:
  /// **'Mark mandatory'**
  String get paperManualSelectionPickerInclude;

  /// No description provided for @paperManualSelectionPickerExclude.
  ///
  /// In en, this message translates to:
  /// **'Mark excluded'**
  String get paperManualSelectionPickerExclude;

  /// No description provided for @paperManualSelectionPickerNone.
  ///
  /// In en, this message translates to:
  /// **'No selectable questions in the bank'**
  String get paperManualSelectionPickerNone;

  /// No description provided for @paperManualSelectionPickerFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to read the question bank: {message}'**
  String paperManualSelectionPickerFailed(String message);

  /// No description provided for @paperManualSelectionOutcomeIncluded.
  ///
  /// In en, this message translates to:
  /// **'{count} mandatory question(s) included'**
  String paperManualSelectionOutcomeIncluded(int count);

  /// No description provided for @paperManualSelectionMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'Mandatory but missing from the bank ({count})'**
  String paperManualSelectionMissingTitle(int count);

  /// No description provided for @paperManualSelectionSkippedTitle.
  ///
  /// In en, this message translates to:
  /// **'Mandatory but squeezed out by the target count ({count})'**
  String paperManualSelectionSkippedTitle(int count);

  /// No description provided for @paperManualSelectionConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'Mandatory/excluded conflicts (exclusion wins, {count})'**
  String paperManualSelectionConflictTitle(int count);

  /// No description provided for @paperManualSelectionMore.
  ///
  /// In en, this message translates to:
  /// **'{count} more not listed'**
  String paperManualSelectionMore(int count);

  /// No description provided for @paperQualityTitle.
  ///
  /// In en, this message translates to:
  /// **'Paper quality check'**
  String get paperQualityTitle;

  /// No description provided for @paperQualitySummary.
  ///
  /// In en, this message translates to:
  /// **'{questionCount} of {requestedCount} questions ({percent} filled)'**
  String paperQualitySummary(
      int questionCount, int requestedCount, String percent);

  /// No description provided for @paperQualityCoverage.
  ///
  /// In en, this message translates to:
  /// **'Knowledge point coverage {percent}'**
  String paperQualityCoverage(String percent);

  /// No description provided for @paperQualityQuotaUnsatisfied.
  ///
  /// In en, this message translates to:
  /// **'Minimum quotas are not satisfied; the findings below explain the gap.'**
  String get paperQualityQuotaUnsatisfied;

  /// No description provided for @paperQualityClean.
  ///
  /// In en, this message translates to:
  /// **'No criteria were triggered.'**
  String get paperQualityClean;

  /// No description provided for @paperQualityGroupHeader.
  ///
  /// In en, this message translates to:
  /// **'{label} ({count})'**
  String paperQualityGroupHeader(String label, int count);

  /// No description provided for @paperQualityEvidenceToggle.
  ///
  /// In en, this message translates to:
  /// **'Show evidence'**
  String get paperQualityEvidenceToggle;

  /// No description provided for @paperQualityEvidenceCollapse.
  ///
  /// In en, this message translates to:
  /// **'Hide evidence'**
  String get paperQualityEvidenceCollapse;

  /// No description provided for @paperQualityEvidenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Evidence'**
  String get paperQualityEvidenceTitle;

  /// No description provided for @paperQualityTruncated.
  ///
  /// In en, this message translates to:
  /// **'{count} more finding(s) were truncated'**
  String paperQualityTruncated(int count);

  /// No description provided for @paperQualityFailed.
  ///
  /// In en, this message translates to:
  /// **'The quality check is unavailable right now.'**
  String get paperQualityFailed;

  /// No description provided for @tasksDueAtConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'That time clashes with a schedule block'**
  String get tasksDueAtConflictTitle;

  /// No description provided for @tasksDueAtConflictBody.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" {range} is a busy block, so it cannot be scheduled there.'**
  String tasksDueAtConflictBody(String title, String range);

  /// No description provided for @tasksDueAtConflictMoveBefore.
  ///
  /// In en, this message translates to:
  /// **'Move before it ({moment})'**
  String tasksDueAtConflictMoveBefore(String moment);

  /// No description provided for @tasksDueAtConflictMoveAfter.
  ///
  /// In en, this message translates to:
  /// **'Move after it ({moment})'**
  String tasksDueAtConflictMoveAfter(String moment);

  /// No description provided for @tasksDueAtConflictKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep it as is'**
  String get tasksDueAtConflictKeep;

  /// No description provided for @tasksDueAtConflictNoFreeMoment.
  ///
  /// In en, this message translates to:
  /// **'No free slot in that direction'**
  String get tasksDueAtConflictNoFreeMoment;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
