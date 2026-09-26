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

  /// No description provided for @navAnki.
  ///
  /// In en, this message translates to:
  /// **'Knowledge'**
  String get navAnki;

  /// No description provided for @navKnowledge.
  ///
  /// In en, this message translates to:
  /// **'Knowledge'**
  String get navKnowledge;

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
  /// **'New knowledge point'**
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

  /// No description provided for @settingsDemoData.
  ///
  /// In en, this message translates to:
  /// **'Load demo data'**
  String get settingsDemoData;

  /// No description provided for @settingsDemoDataHint.
  ///
  /// In en, this message translates to:
  /// **'Creates sample tags, knowledge points, events and schedule blocks so the UI can be inspected right away.'**
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
  /// **'The ranking algorithm and every parameter explained in one place'**
  String get settingsUsageDocHint;

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
