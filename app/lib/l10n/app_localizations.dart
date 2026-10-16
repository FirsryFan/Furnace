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

  /// No description provided for @navMindnet.
  ///
  /// In en, this message translates to:
  /// **'Mindnet'**
  String get navMindnet;

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

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

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

  /// No description provided for @timeMarkBusy.
  ///
  /// In en, this message translates to:
  /// **'Mark as busy'**
  String get timeMarkBusy;

  /// No description provided for @timeMarkOpen.
  ///
  /// In en, this message translates to:
  /// **'Mark as open'**
  String get timeMarkOpen;

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

  /// No description provided for @ankiStartReview.
  ///
  /// In en, this message translates to:
  /// **'Start review'**
  String get ankiStartReview;

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

  /// No description provided for @materialIntakeCantLand.
  ///
  /// In en, this message translates to:
  /// **'cannot land yet: {reason} (get that end into the graph first)'**
  String materialIntakeCantLand(String reason);

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
  /// **'0 or empty reviews per day means no limit. Once the review allowance is used up, this group stops drawing new cards for the day - a card answered wrong today still comes back.'**
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
  /// **'New cards are drawn normally.'**
  String get reviewPlanNewCardsNormal;

  /// No description provided for @reviewPlanNewCardsStopped.
  ///
  /// In en, this message translates to:
  /// **'Review allowance used up: this group stops drawing new cards today. A card answered wrong today still comes back.'**
  String get reviewPlanNewCardsStopped;

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

  /// No description provided for @packagesImportHint.
  ///
  /// In en, this message translates to:
  /// **'Select a .kpak file'**
  String get packagesImportHint;

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

  /// No description provided for @threadEnergy2.
  ///
  /// In en, this message translates to:
  /// **'Very low · mechanical chores only'**
  String get threadEnergy2;

  /// No description provided for @threadEnergy3.
  ///
  /// In en, this message translates to:
  /// **'Low · light tasks'**
  String get threadEnergy3;

  /// No description provided for @threadEnergy4.
  ///
  /// In en, this message translates to:
  /// **'Low · light tasks'**
  String get threadEnergy4;

  /// No description provided for @threadEnergy5.
  ///
  /// In en, this message translates to:
  /// **'Medium · routine work'**
  String get threadEnergy5;

  /// No description provided for @threadEnergy6.
  ///
  /// In en, this message translates to:
  /// **'Medium · routine work'**
  String get threadEnergy6;

  /// No description provided for @threadEnergy7.
  ///
  /// In en, this message translates to:
  /// **'High · needs focus'**
  String get threadEnergy7;

  /// No description provided for @threadEnergy8.
  ///
  /// In en, this message translates to:
  /// **'High · needs focus'**
  String get threadEnergy8;

  /// No description provided for @threadEnergy9.
  ///
  /// In en, this message translates to:
  /// **'Very high · deep push'**
  String get threadEnergy9;

  /// No description provided for @threadEnergy10.
  ///
  /// In en, this message translates to:
  /// **'Very high · deep push'**
  String get threadEnergy10;

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

  /// No description provided for @threadExpectedNear.
  ///
  /// In en, this message translates to:
  /// **'Expected time is near'**
  String get threadExpectedNear;

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

  /// No description provided for @threadSortHint.
  ///
  /// In en, this message translates to:
  /// **'Re-sort'**
  String get threadSortHint;

  /// No description provided for @propTitleHint.
  ///
  /// In en, this message translates to:
  /// **'What this event is called. The ranking never reads the title, but you recognise it by it.'**
  String get propTitleHint;

  /// No description provided for @propDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Longer notes. The ranking never reads this either - it is only for you.'**
  String get propDescriptionHint;

  /// No description provided for @propEstimateHint.
  ///
  /// In en, this message translates to:
  /// **'How long you think it takes. The ranking uses it to check whether it still fits before the deadline.'**
  String get propEstimateHint;

  /// No description provided for @propExpectedHint.
  ///
  /// In en, this message translates to:
  /// **'When you plan to do it. Near that moment it turns yellow and gets a boost - but it can never turn anything red, because it can be postponed.'**
  String get propExpectedHint;

  /// No description provided for @propDeadlineHint.
  ///
  /// In en, this message translates to:
  /// **'The real hard bottom line. If it no longer fits, the event moves to \"not enough time\" and leaves the main list.'**
  String get propDeadlineHint;

  /// No description provided for @propEnergyHint.
  ///
  /// In en, this message translates to:
  /// **'How much energy this needs (1-10). The closer to your current energy, the higher it ranks.'**
  String get propEnergyHint;

  /// No description provided for @propAlgorithm.
  ///
  /// In en, this message translates to:
  /// **'Ranking parameters'**
  String get propAlgorithm;

  /// No description provided for @propAlgorithmHint.
  ///
  /// In en, this message translates to:
  /// **'The raw components and weights this event scored in the last sort. Total = sum of component x weight. Use the buttons on the right to edit the weights.'**
  String get propAlgorithmHint;

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

  /// No description provided for @propWeightsEditable.
  ///
  /// In en, this message translates to:
  /// **'Weights apply to every event and are editable.'**
  String get propWeightsEditable;

  /// No description provided for @propResetWeights.
  ///
  /// In en, this message translates to:
  /// **'Restore default weights'**
  String get propResetWeights;

  /// No description provided for @propTemplatesNote.
  ///
  /// In en, this message translates to:
  /// **'Event templates and batch edits reuse exactly these parameters.'**
  String get propTemplatesNote;

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

  /// No description provided for @settingsUsageDoc.
  ///
  /// In en, this message translates to:
  /// **'Usage guide'**
  String get settingsUsageDoc;

  /// No description provided for @settingsUsageDocHint.
  ///
  /// In en, this message translates to:
  /// **'How each part works and what its limits are: AI, review, knowledge base, cognitive model, ranking'**
  String get settingsUsageDocHint;

  /// No description provided for @docAiTitle.
  ///
  /// In en, this message translates to:
  /// **'What the assistant can do, and what waits for your consent'**
  String get docAiTitle;

  /// No description provided for @docAiBody.
  ///
  /// In en, this message translates to:
  /// **'The AI can only change data through tools, and every tool carries a risk level: read-only calls (query_content, fetch_page, evaluate_problem_fit) run immediately; writes (creating tags, flashcards, tasks, documents...) wait for your consent in both the per-action and the plan-first modes; deletions ask every single time and can be undone. You see what a call will change before it runs and get one undo after it; the model never sees your API key, and skill scripts do not receive it either.'**
  String get docAiBody;

  /// No description provided for @docReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review and flashcards'**
  String get docReviewTitle;

  /// No description provided for @docReviewBody.
  ///
  /// In en, this message translates to:
  /// **'Flashcards hang off tags, and the tag tree is the deck: a daily new/review cap set on one tag covers its whole subtree (no row at all means no cap). Due dates come from FSRS alone - the cognitive model only changes what today\'s queue puts first. Grading can be strict, lenient or self-assessed; lenient ignores typos and word order, and a card you got wrong ignores the daily cap and comes back the same day.'**
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

  /// No description provided for @docCognitiveTitle.
  ///
  /// In en, this message translates to:
  /// **'How to read the cognitive model'**
  String get docCognitiveTitle;

  /// No description provided for @docCognitiveBody.
  ///
  /// In en, this message translates to:
  /// **'Cognitive model in settings is a read-only readings page: R is current memory strength, R0 is the strength right after learning, Sigma is accumulated effort, and the developing-zone / dead-end column is the tierB diffusion verdict on the tag graph (starts are the most recently reviewed points, targets are the ones due today); with no tags or no usable start and target it reads unavailable, which is not the same as healthy. \"Danger\" needs confidence data this app does not store, so it never appears. The statements at the top record that it does not move due dates, that its parameters are uncalibrated and that it does not decide for you. The AI\'s evaluate_problem_fit tool reads the same numbers to judge whether a question is worth doing now.'**
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

  /// No description provided for @aiThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking...'**
  String get aiThinking;

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

  /// No description provided for @skillsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get skillsEnabled;

  /// No description provided for @skillsDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get skillsDisabled;

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

  /// No description provided for @cognitiveZoneNote.
  ///
  /// In en, this message translates to:
  /// **'Zone uses the same ReviewZone vocabulary as the review queue. \"Unavailable\" only means nothing was diagnosed this time - it is not the same as \"healthy (checked, nothing to report)\".'**
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
  /// **'This panel writes exactly one setting and nothing else; the setups and parameters shown are the ones the engines actually run with'**
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

  /// No description provided for @assessmentSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip this time'**
  String get assessmentSkip;

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

  /// No description provided for @assessmentRecallPrompt.
  ///
  /// In en, this message translates to:
  /// **'Retell this knowledge point'**
  String get assessmentRecallPrompt;

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
  /// **'Multiple choice'**
  String get questionIntakeTypeSingleChoice;

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

  /// No description provided for @questionIntakePhotoPending.
  ///
  /// In en, this message translates to:
  /// **'Images waiting'**
  String get questionIntakePhotoPending;

  /// No description provided for @questionIntakeNoPhotos.
  ///
  /// In en, this message translates to:
  /// **'No photos yet. Picked images are stored locally until the AI turns them into stems.'**
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
  /// **'Search stems'**
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
  /// **'Turn photos into tags, knowledge points and flashcards - confirmed one by one before anything is written'**
  String get handwritingQueueEntryHint;

  /// No description provided for @handwritingQueueSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The model only organises what is on the page; every item is written only after you confirm it.'**
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
  /// **'The model proposed nothing to organise: this page may have no tags, knowledge points or cards.'**
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
