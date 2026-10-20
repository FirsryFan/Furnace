// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Furnace';

  @override
  String get navMindMap => '思维导图';

  @override
  String get navTags => '标签';

  @override
  String get navThread => 'Thread';

  @override
  String get navTasks => '任务';

  @override
  String get navTime => 'Time';

  @override
  String get navAnki => '闪存卡';

  @override
  String get navQuestions => '题库';

  @override
  String get navPackages => '知识库';

  @override
  String get navSettings => '设置';

  @override
  String get tagsTitle => '标签';

  @override
  String get settingsProfileName => '姓名';

  @override
  String get settingsBackup => '备份数据';

  @override
  String get settingsBackupDone => '备份已保存';

  @override
  String get commonAdd => '添加';

  @override
  String get commonDelete => '删除';

  @override
  String get commonCancel => '取消';

  @override
  String get commonSave => '保存';

  @override
  String get commonClose => '关闭';

  @override
  String get commonTitle => '标题';

  @override
  String get commonContent => '内容';

  @override
  String get commonName => '名称';

  @override
  String get commonDescription => '描述';

  @override
  String get commonConfirm => '确认';

  @override
  String get commonEdit => '编辑';

  @override
  String get commonStart => '开始';

  @override
  String get commonEnd => '结束';

  @override
  String get commonClear => '清除';

  @override
  String get commonRefresh => '刷新';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsLanguageSystem => '跟随系统';

  @override
  String get settingsLanguageZh => '中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get mindMapNewMap => '新建思维导图';

  @override
  String get mindMapAddNode => '添加节点';

  @override
  String get mindMapPromoteTag => '转为标签';

  @override
  String get mindMapPromoteTask => '转为任务';

  @override
  String get mindMapRenameNode => '重命名节点';

  @override
  String get mindMapEditNotes => '编辑备注';

  @override
  String get mindMapMoveUp => '上移';

  @override
  String get mindMapMoveDown => '下移';

  @override
  String get tasksNewTask => '新建事件';

  @override
  String get tasksPriorityHigh => '高';

  @override
  String get tasksPriorityMedium => '中';

  @override
  String get tasksPriorityLow => '低';

  @override
  String get tasksEstimateMinutes => '期望用时（分钟）';

  @override
  String get tasksExpectedAt => '期望时刻';

  @override
  String get tasksSuggestions => '建议';

  @override
  String get tasksNoSuggestions => '暂无建议';

  @override
  String get tasksSubtasks => '子任务';

  @override
  String get tasksDependencies => '依赖';

  @override
  String get tasksAddSubtask => '添加子任务';

  @override
  String get tasksAddDependency => '添加依赖';

  @override
  String get tasksRemindAt => '提醒时间';

  @override
  String get tasksReminder => '提醒';

  @override
  String get tasksReminderPermissionDenied =>
      '系统没有允许通知权限，这条提醒不会弹出。请在系统设置里允许 Furnace 发送通知后重新设置提醒。';

  @override
  String get tasksDueAt => '截止时刻';

  @override
  String get timeNewBlock => '新建日程块';

  @override
  String get timeTodaySchedule => '今日安排';

  @override
  String get timeAvailable => '可用';

  @override
  String get timeUnavailable => '忙碌';

  @override
  String get timeEnergy => '精力';

  @override
  String get timeEnergyHigh => '高';

  @override
  String get timeEnergyMedium => '中';

  @override
  String get timeEnergyLow => '低';

  @override
  String get timeSuitable => '适合';

  @override
  String get timeSuitableMemorize => '背诵';

  @override
  String get timeSuitableDeepWork => '深度工作';

  @override
  String get timeSuitableReview => '复习';

  @override
  String get timeNone => '无';

  @override
  String get calendarTimeline => '时间轴';

  @override
  String get calendarAddBlock => '新建日程块';

  @override
  String get calendarOpenDay => '打开日视图';

  @override
  String get calendarOpenWeek => '打开周视图';

  @override
  String get calendarDayEmpty => '这一天还没有日程块';

  @override
  String get timeArbitraryRangeHint => '起止时间可以任意指定（精确到分钟），允许与其它块重叠。';

  @override
  String get timeBusyHint => '忙碌＝上课/开会这类占时间的硬块；开放＝可自由安排的软块。';

  @override
  String get timePlusFiveMinutes => '加 5 分钟';

  @override
  String get timeMinusFiveMinutes => '减 5 分钟';

  @override
  String get timeTemplates => '日程模板';

  @override
  String get timeApplyTemplate => '套用模板';

  @override
  String get timeApplyDayTemplate => '套用日模板';

  @override
  String get timeApplyWeekTemplate => '套用周模板';

  @override
  String get timeNoTemplates => '还没有模板。先在日历里排好一周或一天，再在这里保存。';

  @override
  String get timeDeleteTemplate => '删除模板';

  @override
  String get timeSaveTemplate => '保存为模板';

  @override
  String timeTemplateBlockCount(int count) {
    return '$count 个日程块';
  }

  @override
  String timeTemplateApplied(int count) {
    return '已套用 $count 个日程块';
  }

  @override
  String get timelineZoomIn => '放大时间轴';

  @override
  String get timelineZoomOut => '缩小时间轴';

  @override
  String get timelineFold => '折叠（上下滚动）';

  @override
  String get timelineUnfold => '展开（左右滚动）';

  @override
  String timelineSpanDays(int days) {
    return '$days 天';
  }

  @override
  String get calendarDay => '日';

  @override
  String get calendarWeek => '周';

  @override
  String get calendarMonth => '月';

  @override
  String get calendarToday => '回到今天';

  @override
  String get calendarPrev => '上一段';

  @override
  String get calendarNext => '下一段';

  @override
  String get calendarZoom => '纵轴缩放';

  @override
  String get calendarZoom15 => '15 分钟 / 格';

  @override
  String get calendarZoom30 => '30 分钟 / 格';

  @override
  String get calendarZoom60 => '60 分钟 / 格';

  @override
  String get calendarWeekday1 => '一';

  @override
  String get calendarWeekday2 => '二';

  @override
  String get calendarWeekday3 => '三';

  @override
  String get calendarWeekday4 => '四';

  @override
  String get calendarWeekday5 => '五';

  @override
  String get calendarWeekday6 => '六';

  @override
  String get calendarWeekday7 => '日';

  @override
  String get ankiShowAnswer => '显示答案';

  @override
  String get ankiSubmit => '提交';

  @override
  String get ankiForgot => '忘记';

  @override
  String get ankiFuzzy => '模糊';

  @override
  String get ankiRemembered => '记得';

  @override
  String get ankiManage => '管理';

  @override
  String get ankiStats => '统计';

  @override
  String get ankiReviews7d => '7天复习';

  @override
  String get ankiNewKnowledgePoint => '新建闪存卡';

  @override
  String get ankiAutoBlank => '自动挖空';

  @override
  String get ankiSource => '来源';

  @override
  String get ankiCardGroup => '卡组（标签）';

  @override
  String get ankiCardGroupNone => '不设置（散卡）';

  @override
  String get ankiNewTemplate => '新建模板';

  @override
  String get ankiQuestion => '题目';

  @override
  String get ankiAnswer => '答案';

  @override
  String get ankiOptions => '选项（每行一个）';

  @override
  String get ankiType => '题型';

  @override
  String get ankiTypeMcq => '选择题';

  @override
  String get ankiTypeFillBlank => '填空题';

  @override
  String get ankiTypeEssay => '大题';

  @override
  String get ankiNoDueCards => '没有到期的闪存卡';

  @override
  String get ankiCorrect => '正确';

  @override
  String get ankiWrong => '错误';

  @override
  String get ankiYourAnswer => '你的答案';

  @override
  String get ankiHint => '提示';

  @override
  String get ankiHintHelper => '做题时可以点出来看，不算作答';

  @override
  String get ankiJudgeStrict => '严格';

  @override
  String get ankiJudgeLenient => '宽松';

  @override
  String get ankiJudgeSelf => '自判';

  @override
  String get ankiJudgeStrictHint => '逐字比对：默写、单词拼写用这个';

  @override
  String get ankiJudgeLenientHint => '忽略空格、全半角、中英标点和大小写，容忍一个错别字';

  @override
  String get ankiJudgeSelfHint => '先看答案，再由你自己判对错';

  @override
  String get ankiJudgeYourself => '对照答案，自己判分';

  @override
  String get ankiAfterAnswerPrompt => '对答案后，你想起来多少？';

  @override
  String get ankiNearMiss => '差点想起来';

  @override
  String get ankiStillForgot => '还是不会';

  @override
  String get ankiAfterAnswerHint => '只影响认知模型把这次算作遗忘还是学习；下次复习时间不变。';

  @override
  String get ankiNextCard => '下一张';

  @override
  String get ankiExposureTooltip => '只算读过，不算一次复习：不改到期日，也不进复习记录';

  @override
  String get ankiExposureRecorded => '已记下「读过、没测」：这次不算复习，到期日不变';

  @override
  String reviewZoneChip(Object zone) {
    return '模型看这块：$zone';
  }

  @override
  String get ankiTypePreference => '生成题型偏好';

  @override
  String get ankiTypePreferenceMixed => '混合（当前：填空题）';

  @override
  String get ankiTypePreferenceFillBlankLenient => '宽松填空题';

  @override
  String get ankiTypePreferenceNotSaved => '已保存：从现在起生成的卡片就按它来';

  @override
  String get ankiJudgePreference => '判分方式';

  @override
  String get ankiJudgePreferenceDetail => '只决定新的一次作答从哪种判分方式开始；每张卡上方的选择仍然优先。';

  @override
  String get ankiTypePreferenceDetail => '在为新内容生成卡片时生效（自动挖空、知识包导入、AI 建卡）。';

  @override
  String get reviewPreferences => '复习偏好';

  @override
  String get reviewPlanTitle => '复习计划';

  @override
  String get reviewPlanToday => '今天';

  @override
  String get reviewPlanEmpty =>
      '还没有任何卡组设了每日任务量。加一个就能安排「每天各个卡组的任务量」：一个卡组就是一个标签，它下面的整个子树都算这个卡组。';

  @override
  String get reviewPlanAdd => '添加卡组任务量';

  @override
  String get reviewPlanPickGroup => '选择卡组';

  @override
  String get reviewPlanNoTags => '还没有标签：卡组就是标签，请先建标签。';

  @override
  String reviewPlanGroupTitle(String tag) {
    return '$tag 的每日任务量';
  }

  @override
  String get reviewPlanGroupBody => '这个标签以及它下面的所有标签都算作这个卡组。';

  @override
  String reviewPlanUngroupedTitle(int count) {
    return '有 $count 张卡还没有卡组';
  }

  @override
  String get reviewPlanUngroupedBody =>
      '卡组就是标签，而每日任务量是按卡组设的：没有标签的卡不属于任何卡组，也就落在任何每日任务量之外——计划看不到它们。把它们归到一个卡组后，就能马上给这个卡组设每天多少张。';

  @override
  String get reviewPlanUngroupedAction => '把它们归到一个卡组';

  @override
  String reviewPlanUngroupedDone(int count, String tag) {
    return '已把 $count 张卡归到「$tag」';
  }

  @override
  String get todayPlanTitle => '今日清单';

  @override
  String get todayPlanUncalibrated => '加成未标定：这份顺序是提示，不是测量。';

  @override
  String get todayPlanEmpty =>
      '今天没有到期的卡。这不是「没事做」——只是到期队列空着；新卡该学什么是你自己挑的，这一页不会替你编。';

  @override
  String todayPlanCount(int count) {
    return '今天 $count 件事';
  }

  @override
  String todayPlanOmitted(int count) {
    return '另有 $count 件排在这一页的上限之外（清单是给人照做的，不是名录）。';
  }

  @override
  String get todayPlanKindReview => '复习';

  @override
  String get todayPlanKindPractice => '练习';

  @override
  String get todayPlanMetricRetention => '留存';

  @override
  String get todayPlanMetricReachability => '可达性';

  @override
  String todayPlanPrice(String metric, String value, String cost) {
    return '$metric V=$value，成本 $cost';
  }

  @override
  String get todayPlanPracticeHint =>
      '候选题的价格来自模型（plan_today / evaluate_problem_fit）；这一页只列到期的卡。';

  @override
  String todayPlanFailed(String error) {
    return '读不到今天的清单：$error';
  }

  @override
  String get todayStudyPlanTitle => '今天做什么';

  @override
  String get todayStudyPlanLoading => '正在排今天的计划…';

  @override
  String todayStudyPlanTotal(int minutes) {
    return '共约 $minutes 分钟';
  }

  @override
  String todayStudyPlanSkipped(int count) {
    return '跳过 $count 条';
  }

  @override
  String todayStudyPlanStepMinutes(int minutes) {
    return '约 $minutes 分钟';
  }

  @override
  String todayStudyPlanFailed(String error) {
    return '读不到今天的计划：$error';
  }

  @override
  String get todayStudyPlanRetry => '重试';

  @override
  String get todayStudyPlanGoPractice => '去题库练这些题';

  @override
  String get todayStudyPlanGoReview => '去复习到期卡';

  @override
  String get todayStudyPlanGoChains => '去题库补链';

  @override
  String get todayStudyPlanGoVocabulary => '去词表';

  @override
  String get materialIntakeTitle => '添加资料';

  @override
  String get materialIntakeEntryHint =>
      '把 AI 读出来的 mindnet.material/1 信封贴进来：先看会建什么，再点头';

  @override
  String get materialIntakeIntro =>
      '纸上的材料由 AI 读成 mindnet.material/1 信封，这一页做后面两步：贴进来 → 看提案（每条都带出自哪一页哪一行）→ 点头。确认之前一个知识点都不写；连接落成 knowledge_edges 的线索边（严格有向、ls 未标定，两端都在才落）。';

  @override
  String get materialIntakeEnvelopeLabel => '信封（mindnet.material/1）';

  @override
  String get materialIntakeEnvelopeHint =>
      'protocol: mindnet.material/1 · batch_id: … · items: [ … ]';

  @override
  String get materialIntakePreview => '看提案';

  @override
  String get materialIntakeClear => '清空';

  @override
  String get materialIntakePickPhoto => '选一张照片';

  @override
  String get materialIntakePhotoHint =>
      '照片发给有视觉能力的模型，回话直接读成一份 run 请求（只校验、不执行，也不写库）。';

  @override
  String materialIntakePhotoPickFailed(String message) {
    return '没选成照片：$message';
  }

  @override
  String materialIntakePhotoReadFailed(String message) {
    return '照片没读成请求：$message';
  }

  @override
  String get materialIntakePasteRun => '贴一份 run/1';

  @override
  String get materialIntakeRunDialogTitle => '贴一份 run/1：先校验，再试跑';

  @override
  String get materialIntakeRunHint => '把一份 mindnet.run/1 请求贴在这里';

  @override
  String get materialIntakeRunCheck => '校验这份请求';

  @override
  String get materialIntakeRunNote =>
      '只校验、只试跑，不写库；合法的那份才有「试跑一遍」。照片那条路与这一条看的是同一套自检。';

  @override
  String materialIntakeRunGraphFailed(String message) {
    return '读图清单失败：$message（要拿它判断哪些 id 是库里已有的）';
  }

  @override
  String get materialPhotoReportTitle => '照片读出来的请求';

  @override
  String get materialPhotoReportValid => '结构上合法：没有硬错';

  @override
  String get materialPhotoReportInvalid => '结构上不合法：整份会被拒绝';

  @override
  String materialPhotoReportSize(int width, int height) {
    return '发出去的图：$width×$height';
  }

  @override
  String materialPhotoReportCounts(int actions, int evidence) {
    return '动作 $actions 条 · 带出处 $evidence 条';
  }

  @override
  String get materialPhotoReportErrors => '硬错（每一条都会让整份被拒绝）';

  @override
  String get materialPhotoReportPreviews => '会做什么';

  @override
  String get materialPhotoReportWarnings => '建议（不拦）';

  @override
  String get materialPhotoReportRaw => '模型的原话';

  @override
  String get materialPhotoReportNoRaw => '（没有回话）';

  @override
  String get materialPhotoReportFailed => '没读出来';

  @override
  String get materialPhotoReportPickAnother => '换一张';

  @override
  String get materialPhotoReportRetry => '重试';

  @override
  String get materialPhotoReportRehearse => '试跑一遍（不落库）';

  @override
  String get materialPhotoReportEditAndRun => '改一改再跑';

  @override
  String get materialIntakeRunDialogTitleEdited => '改一改再跑（同一份 run/1）';

  @override
  String get materialPhotoReportRehearseBusy => '正在试跑…';

  @override
  String get materialPhotoReportRehearseFailed => '试跑没跑完';

  @override
  String get materialPhotoReportRehearseHeader => '试跑结果（只跑不落库）';

  @override
  String get materialPhotoReportRehearseNote =>
      '只读演练：不写知识点、不写边、不动复习记录。要真的把这份请求落库执行，是另一件事。';

  @override
  String get materialPhotoReportRehearseTrails => '每条动作走到哪一步';

  @override
  String materialPhotoReportRehearseNoMs(String ids) {
    return '这些节点没有模型读数（引擎按默认 0.8 算）：$ids';
  }

  @override
  String materialPhotoReportRehearseUnknown(String ids) {
    return '这些节点库里没有、也没有动作去建它：$ids';
  }

  @override
  String get materialPhotoReportHandOver => '把要新建的东西交给人确认（只落清单）';

  @override
  String get materialPhotoReportHandOverBusy => '正在记…';

  @override
  String get materialPhotoReportHandOverNote =>
      '这一步只落两张清单表（`material_intake_batches` / `material_intake_proposals`）：`knowledge_points` / `knowledge_edges` 一行都不动 —— 就在**这一页下面的待确认清单**里点头，才真的建。同一跑再按一次，落的还是那一批。';

  @override
  String materialPhotoReportHandOverDone(String batchId) {
    return '已经记成一批待确认提案（$batchId）—— 就在这一页下面。';
  }

  @override
  String materialPhotoReportHandOverOpen(int count) {
    return '去看看这一批（$count 条待确认）';
  }

  @override
  String materialPhotoReportHandOverFailed(String message) {
    return '没记成：$message';
  }

  @override
  String get materialIntakeRunDetailLink => '这一跑当时做了什么';

  @override
  String get materialIntakeRunDetailTitle => '这一跑当时做了什么（只读）';

  @override
  String get materialIntakeTopicHubs => '顺便建主题分组（默认不建：分组不是卡片关系）';

  @override
  String materialIntakePendingTitle(int count) {
    return '待确认清单（$count 批，关掉页面也在）';
  }

  @override
  String get materialIntakePendingHint =>
      '这些都是看过、还没点头的：接着看就是当初那一份（不重算），确认之后才会写知识点与线索边。';

  @override
  String materialIntakePendingBatch(int count, String batch) {
    return '$batch：$count 条待确认';
  }

  @override
  String get materialIntakeRestore => '接着确认';

  @override
  String materialIntakeDoneTitle(int count) {
    return '已经确认完的（$count 批）';
  }

  @override
  String get materialIntakeDoneHint =>
      '这些都不用再点头了：想改就去它们落地的地方 —— 知识点在知识模块的管理页，线索边在知识点详情里。';

  @override
  String materialIntakeDoneBatch(int count, String batch) {
    return '$batch：$count 条已确认';
  }

  @override
  String get materialIntakeDoneOpen => '看看确认了什么';

  @override
  String materialIntakeDoneDialogTitle(String batch) {
    return '这批确认了什么（$batch）';
  }

  @override
  String get materialIntakeDoneNote =>
      '这些都进库了：知识点在 knowledge_points，连接是 knowledge_edges 里的线索边（ls 未标定）。标「已存在，不重复建」的那几条是确认时库里就有的，其余是这次才写下去的。';

  @override
  String get materialIntakeUndo => '撤回这一批';

  @override
  String get materialIntakeUndoTitle => '撤回这一批？';

  @override
  String get materialIntakeUndoBody =>
      '这一批自己新建的知识点与线索边会删掉，提案退回待确认。确认时库里就有的行、以及任何卡片 / 标签 / 别的线索边，一个字都不动。只要有一条撤不干净，整批都不撤，原因会告诉你。';

  @override
  String get materialIntakeUndoConfirm => '撤回';

  @override
  String materialIntakeUndone(int points, int edges, int restored) {
    return '已撤回：删掉 $points 个知识点、$edges 条线索边，$restored 条提案退回待确认。';
  }

  @override
  String materialIntakeUndoneNothing(int restored) {
    return '这一批没有自己新建的行：$restored 条提案退回待确认。';
  }

  @override
  String materialIntakeUndoLogLine(int count) {
    return '这一批被撤回过 $count 次（撤回是删行，流水留着）。';
  }

  @override
  String get materialIntakeUndoLogTitle => '撤回记录';

  @override
  String get materialIntakeUndoLogNote =>
      '点过撤回就留一笔：撤成了记删了什么，没撤成记为什么（那时库里一个字没动）。';

  @override
  String get materialIntakeUndoLogDone => '撤成了';

  @override
  String get materialIntakeUndoLogNotDone => '没撤成';

  @override
  String materialIntakeUndoLogBlocked(String reason, int count) {
    return '理由：$reason（当时一共 $count 条理由）';
  }

  @override
  String get materialIntakeUndoBlockedTitle => '这一批撤不了';

  @override
  String get materialIntakeUndoBlockedNote =>
      '整批一条也没删。撤回只删这一批自己新建的东西，下面这些上面挂着别的：';

  @override
  String materialIntakeUndoBlockedRow(String title, String reason) {
    return '$title —— $reason';
  }

  @override
  String materialIntakeBadEnvelope(String error) {
    return '整份拒绝：$error';
  }

  @override
  String materialIntakeProposals(int count) {
    return '$count 条提案';
  }

  @override
  String materialIntakeSkipped(int count) {
    return '$count 条留在清单外';
  }

  @override
  String materialIntakePending(int count) {
    return '已登记为待确认（$count 条）：关掉页面也不会丢';
  }

  @override
  String get materialIntakeNothingToDo => '这份材料没有要动的东西：每条都留在图外，原因逐条写在下面。';

  @override
  String get materialIntakeKindPoint => '知识点';

  @override
  String get materialIntakeKindConnection => '连接';

  @override
  String get materialIntakeConnectionClue => '线索边：严格有向，ls 未标定';

  @override
  String get materialIntakeExisting => '已存在，不重复建';

  @override
  String get materialIntakeRename => '改一改这一条';

  @override
  String get materialIntakeRenameDialogTitle => '改一改这一条（还没点头）';

  @override
  String get materialIntakeRenameField => '标题';

  @override
  String get materialIntakeRenameSave => '存下来';

  @override
  String get materialIntakeEditBody => '正文';

  @override
  String get materialIntakeEditBodyHint => '例：释义、例句、原文；机器读不全的就在这儿补';

  @override
  String materialIntakeProposalBody(String body) {
    return '正文：$body';
  }

  @override
  String materialIntakeCantLand(String reason) {
    return '这条现在落不了：$reason（先让缺的那一端进图）';
  }

  @override
  String materialIntakeConfirm(int count) {
    return '确认入库（$count 条）';
  }

  @override
  String materialIntakeApplied(
      int created, int existing, int deferred, int remaining) {
    return '写入 $created 条（知识点与线索边）、$existing 条已存在、$deferred 条连接落不了、还剩 $remaining 条待确认';
  }

  @override
  String materialIntakeFrom(String source, String region) {
    return '出处：$source · $region';
  }

  @override
  String materialIntakeQuote(String quote) {
    return '页边：「$quote」';
  }

  @override
  String get materialIntakeNoSource => '未标出处';

  @override
  String get reviewPlanNewCardsPerDay => '每天新卡';

  @override
  String get reviewPlanReviewCardsPerDay => '每天复习';

  @override
  String get reviewPlanZeroIsUnlimited =>
      '每天新卡填 0 表示今天不抽新卡；每天复习填 0 或留空表示不限量。今天答错的卡仍然会回来。';

  @override
  String reviewPlanTarget(int newCards, int reviewCards) {
    return '目标：新卡 $newCards · 复习 $reviewCards';
  }

  @override
  String reviewPlanDoneToday(int count) {
    return '今天已完成：$count';
  }

  @override
  String reviewPlanNewRemaining(int count) {
    return '剩余新卡：$count';
  }

  @override
  String reviewPlanRemaining(int count) {
    return '剩余额度：$count';
  }

  @override
  String get reviewPlanReviewsUnlimited => '剩余额度：不限';

  @override
  String get reviewPlanNewCardsNormal => '今天的额度还没用完。';

  @override
  String get reviewPlanNewCardsStopped => '新卡额度用完了：这个卡组今天不再抽新卡。';

  @override
  String get reviewPlanReviewsStopped => '复习额度用完了：今天的复习到这里，明天再来。';

  @override
  String get reviewPlanEdit => '修改任务量';

  @override
  String get reviewPlanClear => '删除任务量（恢复为不限）';

  @override
  String get ankiAutoBlankUnsupported => '按当前题型偏好生成不了：这段内容里没有足够的可挖空信息';

  @override
  String get packagesImport => '导入知识包';

  @override
  String get packagesExport => '导出知识包';

  @override
  String get packagesImported => '导入完成';

  @override
  String get packagesExportName => '知识库名称';

  @override
  String get packagesExportAuthor => '作者';

  @override
  String get packagesVersion => '版本';

  @override
  String get packagesEmpty => '还没有知识包';

  @override
  String get packagesPreviewTitle => '导入预览';

  @override
  String get packagesImportConfirm => '导入';

  @override
  String get privacyExportNote => '导出的文件不包含你的事件、日程和复习进度。';

  @override
  String get packagesUpgrade => '升级';

  @override
  String get packagesDefaultName => '我的知识库';

  @override
  String get packagesDefaultAuthor => '我';

  @override
  String get packagesInstalledTitle => '已导入的知识包';

  @override
  String get packagesScopeLabel => '导出范围';

  @override
  String get packagesScopeAll => '全部内容';

  @override
  String get packagesScopeByTag => '按标签筛选';

  @override
  String get packagesScopeHint => '按标签筛选时只导出所选标签下的闪存卡，且不含思维导图。';

  @override
  String get packagesSelectTags => '选择标签';

  @override
  String get packagesNoTags => '还没有标签，无法按标签筛选';

  @override
  String get packagesItemsCount => '条目';

  @override
  String get packagesCardTemplates => '卡片';

  @override
  String get packagesImportedAt => '导入时间';

  @override
  String get packagesVersionHint => '例如 1.0.0';

  @override
  String get tagsEmpty => '还没有标签';

  @override
  String get tagsNewTop => '新建顶层标签';

  @override
  String tagsNewChild(String parent) {
    return '在「$parent」下新建';
  }

  @override
  String get tagsNameHint => '名字里不能含 /（层级由父子关系决定）';

  @override
  String get tagsRename => '重命名';

  @override
  String get tagsAddChild => '新建子标签';

  @override
  String get tagsExpand => '展开';

  @override
  String get tagsCollapse => '折叠';

  @override
  String tagsDeleteTitle(String label) {
    return '删除「$label」？';
  }

  @override
  String get tagsDeleteBody => '它的整棵子树会一起删除，已挂载该标签的事件/闪存卡会失去这个标签。';

  @override
  String get threadTitle => 'Thread';

  @override
  String get threadSort => '更新与排序';

  @override
  String threadRhythmReading(int percent, int minutes) {
    return '注意力可用性 $percent% · 已专注 $minutes 分钟';
  }

  @override
  String get threadRhythmAdviceHard => '现在适合做难的';

  @override
  String get threadRhythmAdviceModerate => '按普通节奏继续';

  @override
  String get threadRhythmAdviceRest => '该休息一下了';

  @override
  String get threadRhythmEmpty => '还没有足够的学习记录，先做几张卡再来看看';

  @override
  String get threadRhythmHide => '隐藏这个读数';

  @override
  String get threadRhythmUncalibrated => '节律参数未标定，这只是提示不是测量';

  @override
  String get threadRhythmToggle => '注意力可用性读数';

  @override
  String get threadCognitiveRankToggle => '认知排序（目标 + 刚复习过）';

  @override
  String get threadCognitiveRankNote =>
      '认知排序已打开：离当前目标或刚复习过的知识点近的任务排前面；加成未标定，只是次序提示';

  @override
  String get threadNeedsSort => '需要重新排序';

  @override
  String get threadNoEvents => '还没有事件';

  @override
  String get threadGoal => '当前主要目标';

  @override
  String get threadGoalEmpty => '未设置目标';

  @override
  String get threadEnergy => '精力';

  @override
  String get threadEnergyEmpty => '未设置精力';

  @override
  String get threadEnergy1 => '极低 · 只适合机械事务';

  @override
  String get threadEnergy3 => '偏低 · 轻松任务';

  @override
  String get threadEnergy5 => '中等 · 常规任务';

  @override
  String get threadEnergy7 => '偏高 · 需要专注';

  @override
  String get threadEnergy9 => '极高 · 攻坚';

  @override
  String get threadStaleTitle => '状态可能已过期';

  @override
  String get threadStaleBody => '距离上次更新已超过 2 小时，确认后就按当前状态排序。';

  @override
  String get threadArchive => '已归档';

  @override
  String get threadArchiveCompleted => '已完成';

  @override
  String get threadArchiveInsufficient => '时间不足';

  @override
  String get threadArchiveOverdue => '已逾期';

  @override
  String threadInsufficientDetail(String needed, String available) {
    return '需 $needed 分钟，可用 $available 分钟';
  }

  @override
  String get threadArchiveEmpty => '归档是空的';

  @override
  String threadDeleteTitle(String title) {
    return '删除「$title」？';
  }

  @override
  String get threadDeleteBody => '这条事件会被永久删除（子任务与依赖一起删掉），无法撤销。';

  @override
  String get threadCollapse => '折叠顶栏';

  @override
  String get threadExpand => '展开顶栏';

  @override
  String get propAlgorithm => '排序参数';

  @override
  String get propAlgorithmNoData => '还没有排序结果：先在顶栏点「更新与排序」。';

  @override
  String get propUrgency => '紧急度';

  @override
  String get propUrgencyHint => '由截止时刻倒计时算出：越接近期限涨得越快，已过期或 15 分钟内记满分。';

  @override
  String get propGoalMatch => '目标匹配度';

  @override
  String get propGoalMatchHint => '这件事的标签与当前目标文字的重合比例。没设目标或没打标签就是 0。';

  @override
  String get propFit => '状态适配度';

  @override
  String get propFitHint => '「精力要求 vs 你现在精力」与「预估用时 vs 下一段空闲窗口」两者的平均。';

  @override
  String get propExpectedPressure => '期望压力';

  @override
  String get propExpectedPressureHint =>
      '由期望时刻算出：越临近越高，过点了仍在窗口内保持满分，久了自动衰减回 0。';

  @override
  String get propFatigue => '同类疲劳惩罚';

  @override
  String get propFatigueHint => '最近一小时内如果刚做过同类标签的事，会按时间衰减扣分，避免连续做同一类。';

  @override
  String get propTotal => '总分';

  @override
  String get propFlagInsufficient => '当前被标记为「时间不足」，已移出主列表。';

  @override
  String get propFlagOverdue => '当前被标记为「已逾期」，已移出主列表。';

  @override
  String get propFlagExpectedNear => '当前被标为黄色：期望时刻已临近或已过。';

  @override
  String get propWeights => '排序权重';

  @override
  String get propWeightsHint => '权重对所有事件生效（不是只对这一条）。改完会自动重新排序。';

  @override
  String get propResetWeights => '恢复默认权重';

  @override
  String knowledgeRemaining(int count) {
    return '剩 $count 张';
  }

  @override
  String knowledgeActiveCount(int count) {
    return '待清 $count';
  }

  @override
  String get knowledgeSessionDone => '今天这一轮做完了';

  @override
  String get knowledgeWillRepeat => '答错了：这个空会在今天之内再出现，直到连续两次答对。';

  @override
  String knowledgeForcedWait(int minutes) {
    return '这个空刚答对一次，要过一会儿才再出现：还有 $minutes 分钟。';
  }

  @override
  String get knowledgeForcedWaitCheck => '到点了，继续';

  @override
  String get knowledgeNewBlank => '新空';

  @override
  String knowledgeNextIn(int days) {
    return '下次复习：$days 天后';
  }

  @override
  String knowledgeBoosted(int count, String factor) {
    return '同时提权了 $count 个相关闪存卡（最高 $factor 倍）';
  }

  @override
  String get knowledgeCreateTask => '生成任务';

  @override
  String get knowledgeTaskCreated => '已生成任务';

  @override
  String get knowledgeInsight => '今日复盘';

  @override
  String get knowledgeMoreActions => '更多';

  @override
  String get knowledgeReviewTab => '复习';

  @override
  String get knowledgeInsightEmpty => '今天还没有记录';

  @override
  String get knowledgeInsightWrong => '答错的';

  @override
  String get knowledgeInsightBoost => '被提权的相关闪存卡';

  @override
  String knowledgeInsightDistance(int distance) {
    return '距离 $distance';
  }

  @override
  String knowledgeInsightFactor(String factor) {
    return '$factor 倍';
  }

  @override
  String get knowledgeEdges => '线索边';

  @override
  String get knowledgeEdgesIntro =>
      '资料里的连接在你点头之后落在这里：严格有向（A → B 不代表 B → A），ls 没有标定来源、一律标未标定，有一端不在库里就按 id 显示。';

  @override
  String get knowledgeEdgesEmpty => '还没有线索边 —— 材料里的连接要在「添加资料」里确认之后才会落在这里。';

  @override
  String knowledgeEdgesCount(int count) {
    return '$count 条线索边';
  }

  @override
  String get knowledgeEdgesOriginContains => '材料里写了包含关系';

  @override
  String get knowledgeEdgesOriginProduce => '材料里写了产出关系';

  @override
  String get knowledgeEdgesOriginTopic => '主题分组';

  @override
  String get knowledgeEdgesOriginManual => '手写';

  @override
  String get knowledgeEdgesOriginMaterial => '材料（没写是哪种关系）';

  @override
  String knowledgeEdgesLs(String ls) {
    return 'ls $ls（未标定）';
  }

  @override
  String knowledgeEdgesLsCalibrated(String ls) {
    return 'ls $ls';
  }

  @override
  String get knowledgeEdgesNoLs => '材料没给 ls（不假装有）';

  @override
  String get knowledgeEdgesMissingEnd => '有一端不在库里，按 id 显示';

  @override
  String get knowledgePointEdgesEmpty => '这个知识点还没有线索边（材料里的连接确认之后才会有）';

  @override
  String get knowledgePointEdgesNotInGraph =>
      '这个知识点不在材料图里（没有 external_id），所以没有边可看';

  @override
  String knowledgePointEdgesOutgoing(String other) {
    return '它指向：$other';
  }

  @override
  String knowledgePointEdgesIncoming(String other) {
    return '指向它：$other';
  }

  @override
  String get knowledgeEdgeAdd => '加一条线索边';

  @override
  String get knowledgeEdgeAddTitle => '手写一条线索边';

  @override
  String get knowledgeEdgeDirectionOutgoing => '它指向……';

  @override
  String get knowledgeEdgeDirectionIncoming => '……指向它';

  @override
  String get knowledgeEdgePickOther => '另一端';

  @override
  String get knowledgeEdgeNoOtherPoints => '图里还没有别的知识点可以连（手写的知识点没有图内的 id，连不了边）';

  @override
  String get knowledgeEdgeCreated => '已加一条手写线索边（ls 为空 —— 没有标定来源就不假装有）';

  @override
  String knowledgeEdgeAlreadyExists(String origin) {
    return '这个方向已经有一条边了（$origin），没重复加';
  }

  @override
  String get knowledgeEdgeEndpointMissing => '两端都必须已经在图里，这一条没加';

  @override
  String get knowledgeEdgeSamePoint => '起点和终点是同一个点，这一条没加';

  @override
  String get knowledgeEdgeDeleteTooltip => '删掉这条手写边';

  @override
  String get knowledgeEdgeDeleteConfirm => '删掉这条手写线索边？';

  @override
  String get knowledgeEdgeDeleted => '已删掉这条手写边';

  @override
  String get knowledgeEdgeNotFound => '这条边已经不在了';

  @override
  String get knowledgeEdgeNotManual => '只有手写的边能这样删（材料确认来的边要回材料那一步）';

  @override
  String knowledgeEdgeWalkTitle(String point) {
    return '这个点连着谁（$point）';
  }

  @override
  String get knowledgeEdgeWalkHint => '点名字可以顺着这条线接着走：走到哪一端，就看哪一端的边（只读，不建也不删）。';

  @override
  String get knowledgeEdgeWalkTooltip => '顺着这条边走到这一端';

  @override
  String get settingsDemoData => '载入示例数据';

  @override
  String get settingsDemoDataHint => '生成一批示例标签、闪存卡、事件与日程块，方便先看界面效果。';

  @override
  String get settingsDemoDataConfirm => '把示例数据加进当前工作区？';

  @override
  String get settingsDemoDataBlocked => '当前工作区已有内容，示例数据不会载入（避免重复）。';

  @override
  String get settingsDemoDataDone => '示例数据已载入';

  @override
  String get settingsCardGroups => '卡组设置';

  @override
  String get settingsCardGroupsHint =>
      '卡组就是标签树：给一个标签设每日新卡/复习上限，它整棵子树都算这个卡组；判分方式与卡片类型也在这里改。';

  @override
  String get settingsQuestionBankHint => '题库总览、收题、组卷、拍照整理、材料入库，都从这一页进。';

  @override
  String get settingsUsageDoc => '使用文档';

  @override
  String get settingsUsageDocHint =>
      'AI、复习、知识库、题库、拍照/资料、认知模型与排序算法：怎么用、有什么限制都写在这里';

  @override
  String get docAiTitle => 'AI 助手能做什么、什么要你确认';

  @override
  String get docAiBody =>
      'AI 只能通过工具改数据，每个工具都带风险等级：读操作（query_tasks / query_schedule / query_content / fetch_page / evaluate_problem_fit / compose_paper / find_similar_questions / find_questions_by_capability / plan_today / review_metrics 等）直接执行；写操作（建标签、建闪存卡、建任务、写文档、材料入库、应用今日计划…）在「逐条确认」和「先计划后确认」两种模式下都要你点同意；删除类操作在任何模式下都逐条确认，并且可以撤销。执行前会告诉你改什么，执行后可以撤销一次；模型看不到你的 API key，skill 脚本也拿不到它。';

  @override
  String get docReviewTitle => '复习与闪存卡';

  @override
  String get docReviewBody =>
      '闪存卡挂在标签下，标签树就是卡组：给一个标签设每日新卡/复习上限，它整棵子树都算进去（没有设置就是不限额）。到期时间只由 FSRS 决定，认知模型只改「今天先复习哪张」的顺序。判分有严格、宽松、自评三种；选宽松时错别字和语序不算错，答错的卡不受每日配额限制，当天会强制重来。卡组与这几种约定的入口在「设置 → 卡组设置」（复习页右上角也有）。没有挂标签的旧卡不属于任何卡组，任何每日任务量都管不到：卡组设置页会提示有多少张这样的卡，并提供「把它们归到一个卡组」一键补齐；新建卡时也可以直接选卡组。';

  @override
  String get docKnowledgeTitle => '知识库与标签';

  @override
  String get docKnowledgeBody =>
      '标签是一棵树，路径用 / 分隔。删除一个标签会连同它整棵子树、子树里的闪存卡与复习记录一起删除（AI 的删除工具会逐条确认并留下可撤销的快照）。卡片有两种存在形态——模板生成的卡、以及按单元直接建的卡——认知读数页都算数；读数页顶部的孤儿横幅只在你按它的按钮时才清理。';

  @override
  String get docBankTitle => '题库与组卷';

  @override
  String get docBankBody =>
      '收题页把粘贴的文本或选中的图片变成待校对草稿：AI 只做结构化，你不点「入库」就不会写库，同一道题（题干指纹相同）会指向已有题目而不是重复入库。组卷页只从已有题库里凑卷（优先危险/发展区知识点），凑不齐会如实列出缺哪些知识点——AI 不会自己出题；卷面可以复制成可打印的纯文本。认知模型页的「能力动作画像」还能点开，按解题链上的能力动作找题。';

  @override
  String get docMaterialTitle => '拍照、资料与演练';

  @override
  String get docMaterialBody =>
      '拍照整理把一张照片变成四类待确认产物：补充标签、闪存卡、MindNet 知识点节点、题目（原样誊写），确认前不写学习数据；资料入库把一段材料整理成知识点/卡片/连接三类提案，确认后才落库，撤回有记录可查。照片还能整理成一份带机制参数的 run/1 请求，「机制面板」里可以试跑/演练：演练只给读数，不直接改你的数据；你说「不装目标机制」就真的不装。';

  @override
  String get docTodayTitle => '今天做什么、什么时候做';

  @override
  String get docTodayBody =>
      '今日清单列出今天到期的卡；节律层给出 α(τ) 注意力可用性读数；任务与日程块时间冲突会提示并可一键顺延；认知排序档位只改「先复习哪张」，不做到期时间，而且只有点顶栏排序按钮时才重算。反事实 V(π) 与留存探针同样只影响顺序。';

  @override
  String get docCognitiveTitle => '认知模型读数怎么理解';

  @override
  String get docCognitiveBody =>
      '设置里的「认知模型」是只读读数页：R 是当前记忆强度，R0 是刚记住时的强度，Σ 是累计投入；「发展区/死角」由标签图上的快层扩散给出（起点=最近复习的知识点，目标=今天到期的），没有标签、或没有可用的起点与目标时显示「不可用」——它不等于「健康」。「危险」由元认知行给出：复习时自评的把握与实际表现差得够远才会出现，样本不足时不出现，「不出现」不等于健康。「能力动作画像」按解题链上的动作聚合卡点风险，回答「我最该练哪类动作」，点一行可以按动作找题（只读）。读数页顶部还有一个「知识网络图」入口：把知识点与标签画成一张只读的图（颜色=认知区域，大小=卡片数），点节点看读数。页面顶部几条声明说明它不改到期时间、参数尚未标定、不替你做决定。AI 的 evaluate_problem_fit 工具读的是同一批数字，用来判断一道题值不值得现在做。';

  @override
  String get docFormulaTitle => '总分怎么算';

  @override
  String get docFormulaBody =>
      '总分 = 紧急度×权重 + 目标匹配×权重 + 状态适配×权重 + 期望压力×权重 − 疲劳惩罚×权重。所有分量的原始值都在 0 到 1 之间，权重内部会归一化，所以总分也在 0 到 1 之间。只有点顶栏的排序按钮才会重算，软件不会在后台自动改顺序。';

  @override
  String get docCurrentWeights => '当前权重（括号内为出厂值）';

  @override
  String get docWeightsNormalized =>
      '你改的权重会自动归一化：即使相加不等于 1，总分也不会超过 1，因为内部按权重总和重新折算。';

  @override
  String get docStatusTitle => '事件条左边缘的颜色';

  @override
  String get docStatusBody =>
      '绿色＝已完成；蓝色＝等待中（还没到期望时刻）；黄色＝已经过了期望时刻；红色＝已经过了截止时刻。颜色只表达状态，不改变排序。';

  @override
  String get settingsAbout => '关于';

  @override
  String get settingsAboutHint => '版本、数据位置、出网范围、已知未做';

  @override
  String get aboutVersionLabel => '版本';

  @override
  String aboutVersionValue(String version, int build) {
    return '$version（构建 $build）';
  }

  @override
  String get aboutDataTitle => '数据位置';

  @override
  String get aboutDataBody =>
      '数据库、skill、AI 生成的文档与图片附件都在这个目录下；备份就是复制 furnace.db（也可以用上面的「备份数据」）。';

  @override
  String get aboutDataDirLabel => '应用数据目录';

  @override
  String get aboutNetworkTitle => '出网范围';

  @override
  String get aboutNetworkBody =>
      '会主动联网的只有两处：① AI 请求——发给你在「AI 设置」里填的端点（对话文字与图片都走它）；② fetch_page——抓公开网页，只发 GET、不带 cookie、拒绝内网与回环地址、最多跟 5 次跳转、单次正文上限 2 MiB。skill 脚本要联网必须在安装时声明域名、并由你打开网络开关；那个开关只决定脚本能不能跑，不会逐个域名拦截。';

  @override
  String get aboutGapsTitle => '已知未做';

  @override
  String get aboutGapsBody =>
      '① 不生成 DOCX / PDF（create_document 只写 .md / .txt）；② skill 的 networkAllow 只是开关，没有域名级拦截（需要系统级出口控制）；③ skill 脚本只能在 Windows 上运行，Android 上相关工具不出现；④ 浏览器桥（browser_bridge）还没做；⑤ 认知模型只接了记忆层与快排，run/1 会话协议、元认知层、节律层还没接（见 docs/MINDNET_ROADMAP.md）；⑥ fetch_page 对解析不出 IP 的地址不会拦（已记录，未修）。';

  @override
  String get settingsAppearance => '外观';

  @override
  String get settingsThemeSystemEntry => '跟随系统';

  @override
  String get settingsThemeSystemHint => '按系统深浅色自动切换（内置主题）';

  @override
  String get settingsThemeBuiltin => '内置主题';

  @override
  String get settingsThemeCustom => '自定义主题';

  @override
  String get settingsThemeImport => '导入主题';

  @override
  String get settingsThemeImportHint => '选择一个 .json 主题文件';

  @override
  String get settingsThemeImportInvalid =>
      '这个文件不是有效的主题（需要包含 name、colors 等字段的 JSON）';

  @override
  String settingsThemeImported(String name) {
    return '已导入主题「$name」';
  }

  @override
  String get settingsThemeExport => '导出主题';

  @override
  String get settingsThemeExported => '主题已导出';

  @override
  String get settingsThemeDeleted => '主题已删除';

  @override
  String get settingsThemeBuiltinProtected => '内置主题不能删除（可以编辑，保存会另存为副本）';

  @override
  String get settingsThemeBuiltinHint => '这是内置主题。保存时会另存为一个副本，内置默认值保持不变。';

  @override
  String get settingsThemeEdit => '编辑主题';

  @override
  String get settingsThemeSaved => '主题已保存';

  @override
  String get settingsThemeBrightness => '明暗';

  @override
  String get settingsThemePrimary => '主色调';

  @override
  String get settingsThemeBackground => '背景';

  @override
  String get settingsThemeOpacity => '背景透明度';

  @override
  String get settingsThemeScale => '页面缩放';

  @override
  String get settingsThemeScaleHint => '80%–150%，影响正文与控件尺寸。';

  @override
  String get settingsThemeAnimations => '动画';

  @override
  String get settingsThemeAnimationsOn => '开启动画效果';

  @override
  String get settingsThemeAnimationsOff => '已关闭动画';

  @override
  String get settingsThemeFonts => '字体';

  @override
  String get settingsThemeFontUi => '界面字体（留空＝系统默认）';

  @override
  String get settingsThemeFontEditor => '正文/编辑器字体（留空＝系统默认）';

  @override
  String get settingsThemeFontHint => '填字体族名称。字体文件导入功能尚未实现。';

  @override
  String get settingsData => '数据';

  @override
  String get settingsTfpkgExport => '导出工作区（.tfpkg）';

  @override
  String get settingsTfpkgExportHint => '把全部数据打包成一个文件，用于备份或换机';

  @override
  String get settingsTfpkgImport => '导入工作区（.tfpkg）';

  @override
  String get settingsTfpkgImportHint => '从 .tfpkg 恢复，导入前会自动备份当前数据';

  @override
  String settingsTfpkgImportPreview(int rows, int tables, int themes) {
    return '即将导入：$rows 行数据、$tables 张表、$themes 个主题';
  }

  @override
  String get settingsTfpkgMergeReplace => '覆盖（清空后写入）';

  @override
  String get settingsTfpkgMergeAppend => '追加（保留本地，跳过冲突）';

  @override
  String settingsTfpkgImportDone(int rows) {
    return '导入完成：写入 $rows 行';
  }

  @override
  String get settingsTfpkgExportDone => '工作区已导出';

  @override
  String get settingsTfpkgInvalid => '这个文件不是有效的 .tfpkg';

  @override
  String settingsTfpkgSkippedTables(int count) {
    return '有 $count 张表来自更新的版本，已跳过';
  }

  @override
  String get settingsBackupNote => '这是原始数据库文件的副本；日常备份建议用 .tfpkg。';

  @override
  String get navAi => '对话';

  @override
  String get aiTitle => 'AI 对话';

  @override
  String get aiNewConversation => '新对话';

  @override
  String get aiEmptyHint => '直接说要做什么，例如「帮我把下周的复习计划排进日程」。';

  @override
  String get aiInputHint => '输入消息…';

  @override
  String get aiInputKeyHint => 'Enter 发送 · Shift+Enter 换行';

  @override
  String get aiInputResizeHandle => '上下拖动调整输入框高度';

  @override
  String get aiShowConversationList => '展开对话列表';

  @override
  String get aiHideConversationList => '收起对话列表';

  @override
  String get aiSend => '发送';

  @override
  String get aiPendingTitle => '以下操作需要你确认';

  @override
  String get aiApproveAll => '全部执行';

  @override
  String get aiRejectAll => '全部拒绝';

  @override
  String get aiNeedsConfirm => '需单独确认';

  @override
  String get aiAutoExecuted => '已自动执行';

  @override
  String get aiUndo => '撤销';

  @override
  String get aiUndone => '已撤销';

  @override
  String get aiNotConfigured => 'AI 尚未接入';

  @override
  String get aiNotConfiguredHint =>
      '在「设置 → AI」里填入 API key 后，这里会出现对话界面。未接入时应用不会发起任何网络请求。';

  @override
  String get aiGoToSettings => '去设置';

  @override
  String get aiDeleteConversation => '删除对话';

  @override
  String get aiDeleteConversationConfirm => '删除这个对话？此操作不可撤销。';

  @override
  String get aiAttachImage => '添加图片';

  @override
  String get aiRemoveImage => '移除图片';

  @override
  String get aiImageTooLarge => '图片太大：压缩后仍超过 4 MB，无法发送。请换一张更小的图片，或先裁剪掉不需要的部分。';

  @override
  String get aiImageUnreadable =>
      '无法读取这张图片：格式不支持或文件已损坏。请换成 PNG、JPG、WebP 或 GIF。';

  @override
  String get aiUsageCurrent => '本轮';

  @override
  String get aiUsageLast => '最近一轮';

  @override
  String get aiUsageRounds => '轮数';

  @override
  String get aiUsageSteps => '步数';

  @override
  String get aiUsageTotalTokens => '总 token';

  @override
  String aiUsagePromptCompletion(int prompt, int completion) {
    return '输入 $prompt + 输出 $completion';
  }

  @override
  String get aiUsageTokensPerSecond => 'tokens/s';

  @override
  String get aiUsageCacheHit => '缓存命中率';

  @override
  String get aiUsageCacheAbsent => '该服务未返回缓存命中数据。';

  @override
  String get aiUsageCachePartial => '只有部分轮次返回了缓存命中数据。';

  @override
  String get aiUsageContext => '上下文占用';

  @override
  String aiUsageContextEstimate(int tokens) {
    return '按 $tokens token 窗口估算；窗口是配置值，不是实测值。';
  }

  @override
  String aiUsagePending(int count) {
    return '$count 待确认';
  }

  @override
  String aiUsageRejected(int count) {
    return '$count 已拒绝';
  }

  @override
  String get aiUsageLiveEstimate => '仍在生成：按已到达的文本估算。';

  @override
  String get aiUsageNoUsage => '本轮没有返回 token 用量。';

  @override
  String get aiUsageUnavailable => '—';

  @override
  String get settingsAiSection => 'AI 接入';

  @override
  String get settingsAiEnabled => '启用 AI';

  @override
  String get settingsAiApiKey => 'API Key';

  @override
  String get settingsAiApiKeyHint => '明文存放在本地数据库，且会随 .tfpkg 导出';

  @override
  String get settingsAiBaseUrl => 'Base URL';

  @override
  String get settingsAiModel => '模型';

  @override
  String get settingsAiPermissionMode => '权限模式';

  @override
  String get settingsAiPermissionPlan => '按计划（写入前汇总确认一次）';

  @override
  String get settingsAiPermissionAuto => '自动（除删除外直接执行，可撤销）';

  @override
  String get settingsAiPermissionHint => '删除类操作在任何模式下都需要逐条确认。';

  @override
  String get settingsAiMaxRounds => '单条消息的工具调用轮数上限';

  @override
  String settingsAiMaxRoundsValue(int rounds) {
    return '$rounds 轮';
  }

  @override
  String get settingsAiMaxRoundsHint =>
      '每多一轮都是一次额外的付费模型调用；轮数越大，一条消息越能一次做完较长的多步任务。默认 8 轮。';

  @override
  String get settingsAiSave => '保存';

  @override
  String get settingsAiSaved => '已保存';

  @override
  String get settingsAiKeyRequired => '填入 API key 后才能启用';

  @override
  String get settingsAiPlatformNote =>
      'Android 上没有 Node 运行时与桌面浏览器，脚本型 skill 与浏览器扩展能力只在 Windows 上可用。';

  @override
  String get skillsTitle => 'Skill 管理';

  @override
  String get skillsIntro =>
      '.fskill 是一个 zip 包：一段提示词，外加可选的工具与脚本声明。安装只是把文件解开到磁盘上；启用后它的提示词（与参考文件）会随系统提示词一起发给模型，它声明的工具也可以被调用——每次调用都会先让你确认。';

  @override
  String get skillsInstall => '安装 .fskill';

  @override
  String get skillsInstallSample => '安装示例 skill';

  @override
  String get skillsBuiltinTitle => '内置技能：';

  @override
  String get skillsBuiltinInstall => '安装';

  @override
  String get skillsInstalling => '正在安装…';

  @override
  String get skillsEmpty => '还没有安装任何 skill。';

  @override
  String get skillsPlatforms => '支持平台';

  @override
  String get skillsNetwork => '允许联网';

  @override
  String get skillsNetworkNone => '不允许联网';

  @override
  String get skillsPermissions => '申请的宿主能力';

  @override
  String get skillsPermissionsNone => '未申请';

  @override
  String get skillsTools => '声明的工具';

  @override
  String get skillsToolsNone => '无';

  @override
  String get skillsContainerNote =>
      '脚本执行容器已启用（仅 Windows）：启用的 skill 一进入本轮，它声明的脚本工具就会出现在模型的工具列表里。每次调用都会在对话里等你单独确认，确认后才会启动一次性子进程；子进程拿不到应用的环境变量，也不能借用你的 API key。';

  @override
  String get skillsContainerNoteUnavailable =>
      '脚本执行只支持 Windows：这台设备上没有 Node 运行时，所以声明出来的脚本工具不会出现在模型的工具列表里（技能提示词仍然生效）。';

  @override
  String get skillsContainerPromptOnly =>
      '这个 skill 只有提示词，没有脚本要运行（提示词随「已启用」在安卓与 Windows 上都生效）。';

  @override
  String get skillsContainerRunnable =>
      '本机可以运行这个 skill 的脚本（Windows），声明的工具会随「已启用」一起交给模型。';

  @override
  String skillsContainerNotRunnable(String platforms) {
    return '本机不能运行这个 skill 的脚本（它只声明支持 $platforms），工具不会出现在模型面前；提示词仍然随「已启用」生效。';
  }

  @override
  String skillsUnsupportedCapability(String capability) {
    return '宿主能力 $capability 容器不提供（见 docs/SKILL_FORMAT.md §4）：申请了它，这个 skill 的脚本调用会被直接拒绝，而不是缺了能力硬跑。';
  }

  @override
  String skillsNetworkConsent(String domains) {
    return '允许联网（$domains）';
  }

  @override
  String skillsNetworkNoConsent(String domains) {
    return '未允许联网（$domains）：在你打开左边这个开关之前，它的脚本调用会被拒绝。';
  }

  @override
  String get skillsNetworkDeclaredNone => '这个 skill 没有声明要联网（networkAllow 为空）。';

  @override
  String get skillsNetworkConsentNote =>
      '打开开关等于放行这个 skill 的脚本联网。你看到的是它声明的域名清单；容器按声明约束，并没有在系统层面挡住别的域名。';

  @override
  String get skillsNetworkToggleFailed => '切换这个 skill 的网络许可失败';

  @override
  String get skillsPath => '文件位置';

  @override
  String get skillsRemove => '删除';

  @override
  String get skillsRemoveConfirmTitle => '删除 skill';

  @override
  String skillsRemoveConfirm(String name) {
    return '$name：确认把这个 skill 的文件从磁盘上删掉？在应用里无法撤销。';
  }

  @override
  String get skillsCancel => '取消';

  @override
  String get skillsRemoveFailed => '删除这个 skill 失败';

  @override
  String get skillsToggleFailed => '切换这个 skill 的状态失败';

  @override
  String get skillsInstallFailed => '安装被拒绝或失败';

  @override
  String get settingsThemeBackgroundNone => '未设置背景图';

  @override
  String get settingsThemeBackgroundSet => '已设置背景图';

  @override
  String get settingsThemeBackgroundPick => '选择背景图';

  @override
  String get settingsThemeBackgroundBlur => '背景模糊';

  @override
  String get settingsThemeBackgroundFailed => '这个图片文件读不出来';

  @override
  String get settingsTfpkgExportSecretsHint =>
      '这个包会带上你的 AI API key。如果是要发给别人，请选择不含密钥的版本。';

  @override
  String get settingsTfpkgExportWithSecrets => '包含（自己备份用）';

  @override
  String get settingsTfpkgExportNoSecrets => '不含密钥（发给别人）';

  @override
  String get settingsTfpkgExportDoneNoSecrets => '工作区已导出（未包含 API key）';

  @override
  String get cognitiveModelTitle => '认知模型';

  @override
  String get cognitiveModelSubtitle => '只读读数：R / 分组 / 发展区';

  @override
  String get cognitiveGraphTitle => '知识网络图（只读）';

  @override
  String get cognitiveGraphHint =>
      '圆点=知识点（颜色=认知区域，大小=卡片数），方块=标签；一条线=这个知识点挂在那个标签上。图上没有任何可改的东西：不改到期时间，也不改排序。';

  @override
  String get cognitiveGraphEmpty => '还没有可画的读数：先建知识点与标签，再复习几张卡。';

  @override
  String cognitiveGraphSummary(int points, int tags, int links) {
    return '$points 个知识点 · $tags 个标签 · $links 条连线';
  }

  @override
  String cognitiveGraphPointDetail(String zone, int cards, String mean) {
    return '区域：$zone · $cards 张卡 · 平均 R $mean';
  }

  @override
  String cognitiveGraphTagDetail(int count) {
    return '这个标签下挂着 $count 个知识点';
  }

  @override
  String get cognitiveGraphTapHint => '点一个圆点或方块看它的读数（只读）。';

  @override
  String get cognitiveAdvisorMode => '顾问模式：不改到期时间';

  @override
  String get cognitiveAdvisorModeDetail => '到期时间仍由 FSRS 决定；模型只影响队列顺序和本页读数。';

  @override
  String get cognitiveUncalibratedWeights => 'ls 等边权未标定';

  @override
  String get cognitiveUncalibratedWeightsDetail =>
      '模型的边权（ls 等）没有标定来源，所以这个排序只是启发式参考，不是测量结果。';

  @override
  String get cognitiveReadOnlyNote => '只读页面：不会写入数据库';

  @override
  String get mechanismPanelTitle => '机制与参数';

  @override
  String get mechanismPanelSubtitle => '引擎里装了哪些机制、每个参数是多少、哪些还没标定';

  @override
  String get mechanismPanelReadOnlyNote =>
      '面板只写这两个设置（下面那个开关和这个滑块），不写别的表；装配和参数就是引擎正在用的那一份';

  @override
  String get mechanismSwitchGoalTitle => '装目标机制（context.goal）';

  @override
  String get mechanismSwitchGoalBody =>
      '关掉之后：库诊断那一跑不再装它，扩散没有起点/目标可拉，读数会变；题目定价那一跑仍然装它（那一路要用起点/目标定价）。没选过 = 装。';

  @override
  String get mechanismGoalBetaTitle => '目标偏置强度（context.goal.beta_goal）';

  @override
  String get mechanismGoalBetaBody =>
      '目标把扩散往起点/目标拉多用力：0 = 完全不牵引，出厂值就是下面写的转录默认值（未标定的占位值）。它只改这一个数字，不改装了什么。';

  @override
  String get mechanismGoalBetaShipped => '出厂值';

  @override
  String get mechanismGoalBetaFromSetting => '你调的';

  @override
  String get mechanismGoalBetaReset => '回到出厂值';

  @override
  String get mechanismGoalBetaApplies =>
      '装了目标机制的每一跑都读这个数：库诊断那一跑（本页上面那份读数），以及题目定价那一跑（evaluate_problem_fit / plan_today 的 V(π) 排序）。工具读数里的 module_defaults 带的就是它 —— 没调过的时候是空的（出厂值一个字没动）。';

  @override
  String get mechanismGoalBetaOffNote =>
      '目标机制没有装（上面那个开关关着），所以装了它的那些跑都不会用这个值；数字还留着，等你再打开。';

  @override
  String get mechanismDisabledBySetting => '你关掉了（出厂会装）';

  @override
  String get mechanismPanelSetupsHeader => '引擎的三处装配';

  @override
  String mechanismPanelSetupCount(int count) {
    return '装了 $count 个机制';
  }

  @override
  String get mechanismPanelOverridesHeader => '覆盖（不是转录默认值）：';

  @override
  String get mechanismPanelNoOverrides => '没有覆盖：全部按转录默认值';

  @override
  String get mechanismPanelMechanismsHeader => '机制清单';

  @override
  String get mechanismPanelInstalledIn => '装在：';

  @override
  String get mechanismPanelOnlyOutside => '只在节律读数里，不装进引擎';

  @override
  String get mechanismPanelNoParams => '这一层没有号参数：它只维护每个节点的状态袋';

  @override
  String get mechanismPanelUncalibrated => '未标定';

  @override
  String get mechanismPanelCalibrated => '已标定';

  @override
  String get mechanismPanelOverridden => '被覆盖';

  @override
  String get mechanismPanelTranscribed => '转录默认值';

  @override
  String get mechanismPanelRange => '范围';

  @override
  String mechanismPanelSummary(int params, int uncalibrated) {
    return '$params 个参数，其中 $uncalibrated 个未标定';
  }

  @override
  String get mechanismPanelNameSeparator => '、';

  @override
  String get mechanismPanelOpen => '机制与参数';

  @override
  String get mechanismNameShunting => '侧抑制（分流）';

  @override
  String get mechanismNameCapacity => '注意容量';

  @override
  String get mechanismNameIgnition => '点火阈值';

  @override
  String get mechanismNameGoal => '目标上下文';

  @override
  String get mechanismNameRhythm => '节律闸门';

  @override
  String get mechanismNameMemory => 'DSR 记忆层';

  @override
  String get mechanismSetupLibraryDiagnosis => '库诊断那一跑';

  @override
  String get mechanismSetupProblemEvaluator => '题目定价那一跑';

  @override
  String get mechanismSetupRunRehearsal => '转写请求演练那一跑';

  @override
  String get cognitiveZoneNote =>
      '发展区/死角沿用复习队列的同一套 ReviewZone 词表。「不可用」只表示这次没做诊断，它不等于「健康（查过，没问题）」。';

  @override
  String get cognitiveFastLayerNote => '发展区来自快层诊断';

  @override
  String get cognitiveFastLayerRanDetail =>
      '这次跑过：取值来自标签图上的扩散结果（弱/空/慢/过载/偏离目标/死路）。起点=最近复习的几个知识点，目标=今天到期的那些。';

  @override
  String get cognitiveFastLayerNotRunDetail =>
      '这次没跑：没有标签，或没有可用的起点与目标，所以区域一律是「不可用」。';

  @override
  String get cognitiveDangerNote =>
      '「危险（自信但记不住）」现在由元认知层算出来：只有当某个知识点这次在标签图上被点亮、而它的卡片已经很久没碰时才会出现。没有列出来的知识点不等于没问题，它可能只是这次没被判断。';

  @override
  String get cognitiveMetacognitionTitle => '模型怎么看你';

  @override
  String get cognitiveMetacognitionDetail =>
      '把「模型信多少」（信念，来自充分度、编码强度与新鲜度）和「卡片真实还能回忆多少」放在一起比。差得越大，越值得看一眼。';

  @override
  String cognitiveMetacognitionCalibration(Object gap) {
    return '平均偏差 $gap（越小越准；权重未标定，只作参考）';
  }

  @override
  String cognitiveMetacognitionDanger(Object nodes) {
    return '危险：$nodes（正在学，但卡片很久没碰）';
  }

  @override
  String cognitiveMetacognitionAnxiety(Object nodes) {
    return '低估：$nodes（卡片还行，你却觉得不行）';
  }

  @override
  String get cognitiveMetacognitionNoRows =>
      '这次没有一个知识点能被判断：每个知识点至少要有一张卡，而且这次诊断得跑起来。';

  @override
  String get cognitiveMetacognitionLevel =>
      '没有一个知识点越过 0.2 的差距阈值：这次既没有危险，也没有低估。';

  @override
  String cognitiveSummary(int cards, String model) {
    return '$cards 张卡 · 模型 $model';
  }

  @override
  String cognitiveSummaryBands(String bands) {
    return '分组：$bands';
  }

  @override
  String cognitiveSummaryNumbers(int newCards, String meanR) {
    return '新卡 $newCards 张 · 平均 R $meanR';
  }

  @override
  String cognitiveReadAt(String moment) {
    return '读数时刻 $moment';
  }

  @override
  String get cognitiveEmpty => '还没有可观察的卡片。先添加闪存卡并复习几张卡。';

  @override
  String cognitiveOrphanTitle(int count) {
    return '有 $count 条卡片状态所属的闪存卡已经不存在';
  }

  @override
  String get cognitiveOrphanDetail =>
      '它们不可能再被复习，所以这里不再把它们当成卡片显示。点右边会把这些行（连同它们的复习日志）真正删掉。';

  @override
  String cognitiveOrphanAction(int count) {
    return '清掉这 $count 条';
  }

  @override
  String cognitiveOrphanDone(int count) {
    return '已清掉 $count 条失效卡片状态';
  }

  @override
  String get cognitiveNewCard => '新卡';

  @override
  String get cognitiveSeenCard => '老卡';

  @override
  String cognitiveCardId(String id) {
    return '卡 $id';
  }

  @override
  String cognitiveRetrievability(String value) {
    return 'R $value';
  }

  @override
  String cognitiveGain(String value) {
    return '增益 $value';
  }

  @override
  String cognitiveEncoding(String value) {
    return 'R0 $value';
  }

  @override
  String cognitiveEncodingPrior(String value) {
    return 'R0 $value（测评先验）';
  }

  @override
  String get cognitivePriorNote => '测评先验';

  @override
  String cognitivePriorCount(int count) {
    return '$count 张卡的起点现在来自测评先验（未标定）；其余是复习观测或模型默认值。卡片一旦真的复习过，观测就接管，先验不再说话。';
  }

  @override
  String get cognitivePriorNone =>
      '还没有测评先验：每张卡的起点都是模型默认值或它自己的复习观测。测一次会给这部分知识一个关于你的估计。';

  @override
  String cognitiveSavings(String value) {
    return 'Σ $value';
  }

  @override
  String cognitiveTags(int count) {
    return '标签 $count';
  }

  @override
  String get cognitiveColumnBand => '分组';

  @override
  String get cognitiveColumnZone => '发展区/死角';

  @override
  String get cognitiveColumnSchedule => '排程（FSRS）';

  @override
  String get cognitiveGainNotUsed =>
      '增益不参与排序：该卡在 forced/boosted 组里，位置不是模型决定的（D5）';

  @override
  String get cognitiveNewCardNotOrdered => '新卡不交由模型评分与排序（D4）';

  @override
  String get cognitiveNoSchedule => '未排程';

  @override
  String cognitiveDue(String moment) {
    return '到期 $moment';
  }

  @override
  String cognitiveInterval(String days) {
    return '当前间隔 $days 天';
  }

  @override
  String cognitiveSuggestedInterval(int days) {
    return '现在答「记得」FSRS 会排 $days 天';
  }

  @override
  String get cognitiveErrorTitle => '读数加载失败';

  @override
  String get cognitiveBandForced => '强制今天回';

  @override
  String get cognitiveBandBoosted => '标签扩散提升（启发式）';

  @override
  String get cognitiveBandModel => '模型排序';

  @override
  String get cognitiveBandUnseen => '新卡';

  @override
  String get cognitiveZoneProximal => '发展区（差一点就想起来）';

  @override
  String get cognitiveZoneEmpty => '空（进不去）';

  @override
  String get cognitiveZoneDeadEnd => '死角（想得到、走不下去）';

  @override
  String get cognitiveZoneSlow => '过慢（要太多轮才点亮）';

  @override
  String get cognitiveZoneOverload => '容量竞争（被挤掉）';

  @override
  String get cognitiveZoneOffGoal => '偏离目标';

  @override
  String get cognitiveZoneDanger => '危险（自信但记不住）';

  @override
  String get cognitiveZoneHealthy => '健康（查过，没问题）';

  @override
  String get cognitiveZoneUnavailable => '不可用（未做诊断）';

  @override
  String get assessmentTitle => '给模型一个起点';

  @override
  String get assessmentIntro =>
      '读数页上的数字要么来自你的复习记录，要么来自模型的默认值。这里做第三件事：用一次简短的测评，把默认值换成关于你的估计。测的是抽象参数（起点的可提取性、流畅度），不是背了多少张卡；先自评起步，客观抽检随后补。所有先验都标着未标定——它给你一个起点，不是结论。';

  @override
  String get assessmentStepScope => '① 选范围';

  @override
  String get assessmentStepSelf => '② 自评';

  @override
  String get assessmentStepRecall => '③ 复述抽检';

  @override
  String get assessmentStepResult => '④ 读数';

  @override
  String get assessmentScopeHint =>
      '选一块范围（选中标签会连它的子标签一起算）。范围越集中，这一批先验越值得当真；分散到全库，它就只是平均值。';

  @override
  String assessmentScopeCount(Object count) {
    return '这块里有 $count 个知识点';
  }

  @override
  String get assessmentScopeEmpty => '还没有可测的知识点：先在标签页建标签、在闪存卡里建知识点，再回来。';

  @override
  String get assessmentNext => '下一步';

  @override
  String get assessmentBack => '上一步';

  @override
  String get assessmentSelfHint =>
      '不看资料，现在能复述多少？0 = 完全想不起来，5 = 能完整讲出来。自评不是考试，它给模型一个起点；答不准也没关系，客观抽检会来修正它。';

  @override
  String assessmentSelfAnswered(Object answered, Object total) {
    return '已自评 $answered / $total 个';
  }

  @override
  String get assessmentRecallHint =>
      '下面三个知识点是范围的两端与中间各一个——每次给同一批，才能比较不同时间。写下你的复述，然后给自己一个分：说法对得上吗？';

  @override
  String get assessmentRecallAnswer => '我复述的内容（可留空）';

  @override
  String get assessmentRecallRating => '我的复述对得上吗？';

  @override
  String get assessmentFinish => '完成并重算先验';

  @override
  String get assessmentResultTitle => '这一轮的读数';

  @override
  String get assessmentResultPending => '下面这支按钮会结束这一轮：先把回答写成证据，再重算范围内的先验。';

  @override
  String assessmentResultBody(Object steps, Object points) {
    return '写入 $steps 步证据，重算 $points 个知识点的先验。';
  }

  @override
  String assessmentResultR0(Object r0) {
    return '平均起点 R0 $r0';
  }

  @override
  String assessmentResultConfidence(Object confidence) {
    return '平均置信度 $confidence（n/(n+3)，样本越多越靠近 1）';
  }

  @override
  String get assessmentResultUncalibrated =>
      '全部先验标着未标定：这批常数还是模型默认值。它在你答得少的时候只该当起点，不该当结论；等客观抽检攒够样本，标定才是下一步。';

  @override
  String get assessmentNoEvidence => '这一轮一步证据都没写（全部跳过），所以没有先验——空的一轮不会污染读数。';

  @override
  String get assessmentEntryAction => '测一测（给模型一个起点）';

  @override
  String get capabilityProfileTitle => '能力动作画像（来自解题链）';

  @override
  String get capabilityProfileDetail => '按每条步骤的卡点风险聚合；没有风险读数的步骤只算条数、不进平均。';

  @override
  String get capabilityProfileUnavailable => '画像读不出来（读库失败）。';

  @override
  String get capabilityProfileEmpty => '还没有解题链：先去题目详情页按一次「AI 解题」，这里才有东西可聚合。';

  @override
  String capabilityProfileRow(
      String action, int steps, int risky, String risk) {
    return '$action：$steps 步，其中 $risky 步高风险，平均风险 $risk';
  }

  @override
  String get capabilityProfileNoRisk => '没有风险读数（未给判断）';

  @override
  String get capabilityProfileUnknownNote =>
      '词表里没有的动作按原样显示 —— 那不是「没问题」，是「这个词表还不认识它」。';

  @override
  String capabilityActionQuestionsTitle(String label) {
    return '按能力动作找题：$label';
  }

  @override
  String get capabilityActionQuestionsNote =>
      '这里的题按「最新一条解题链里出现过这个动作」筛；没解过链的题不会出现在这里。';

  @override
  String capabilityActionQuestionsEmpty(String label) {
    return '还没有解过含「$label」的题 —— 先去题目详情页按一次「AI 解题」。';
  }

  @override
  String get capabilityActionQuestionsAllSubjects => '全部学科';

  @override
  String get capabilityActionQuestionsSecondAction => '再叠加一个动作（可选）';

  @override
  String get capabilityActionQuestionsSecondActionNone => '不叠加';

  @override
  String get capabilityActionQuestionsRequireAll => '两个动作都得出现在同一条链里';

  @override
  String capabilityActionQuestionsMeta(
      String subject, String source, String actions) {
    return '$subject · $source · 链上动作：$actions';
  }

  @override
  String capabilityActionQuestionsFailed(String message) {
    return '读题库失败：$message';
  }

  @override
  String get capabilityVocabularyTitle => '能力动作词表';

  @override
  String get capabilityVocabularyHint =>
      '词表决定「学生卡在哪一步动作」怎么命名。内置动作只读（key 已写进历史数据）；自定义条目只暂存在本页，点「保存」才落库，保存后从下一次解题开始生效。';

  @override
  String capabilityVocabularyBuiltInSection(int count) {
    return '内置动作（只读，共 $count 个）';
  }

  @override
  String get capabilityVocabularyBuiltInNote =>
      '内置词表由代码定义；改内置动作要改代码并发版，这里只读展示。';

  @override
  String capabilityVocabularyCustomSection(int count) {
    return '自定义动作（$count 条）';
  }

  @override
  String get capabilityVocabularyCustomEmpty =>
      '还没有自定义动作：点「新增动作」，或在下面粘贴 JSON 导入。';

  @override
  String get capabilityVocabularyAdd => '新增动作';

  @override
  String get capabilityVocabularyEditTitle => '编辑动作';

  @override
  String get capabilityVocabularyKeyLabel => 'key（稳定标识）';

  @override
  String get capabilityVocabularyKeyHint =>
      '小写蛇形，例如 force_diagram_analysis；保存后不可改';

  @override
  String get capabilityVocabularyLabelZh => '中文名';

  @override
  String get capabilityVocabularyLabelEn => '英文名（可选）';

  @override
  String get capabilityVocabularyDescriptionZh => '一句话说明（可选）';

  @override
  String get capabilityVocabularySubjectHints => '会出现的学科';

  @override
  String get capabilityVocabularyMoveUp => '上移';

  @override
  String get capabilityVocabularyMoveDown => '下移';

  @override
  String get capabilityVocabularyImport => '粘贴 JSON 导入';

  @override
  String get capabilityVocabularyImportTitle => '粘贴词表 JSON';

  @override
  String get capabilityVocabularyImportHint =>
      '支持 customActions 列表，或直接给自定义动作数组';

  @override
  String capabilityVocabularyImportInvalidJson(String message) {
    return 'JSON 解析失败：$message';
  }

  @override
  String capabilityVocabularyImportDone(int count) {
    return '已导入 $count 条（还没保存）';
  }

  @override
  String get capabilityVocabularyRevert => '放弃修改';

  @override
  String get capabilityVocabularySaved => '已保存：下一次解题起用新词表';

  @override
  String capabilityVocabularySaveFailed(String message) {
    return '保存失败：$message';
  }

  @override
  String get capabilityVocabularyDirty => '有未保存的修改';

  @override
  String capabilityVocabularyIssuesTitle(int count) {
    return '$count 条操作没有被接受';
  }

  @override
  String get capabilityVocabularyIssueDismiss => '知道了';

  @override
  String capabilityVocabularyLoadFailed(String message) {
    return '读词表失败：$message';
  }

  @override
  String get capabilityVocabularyLeaveTitle => '有未保存的修改';

  @override
  String get capabilityVocabularyLeaveBody => '离开会丢掉这些修改。';

  @override
  String get capabilityVocabularyLeaveStay => '留下继续编辑';

  @override
  String get capabilityVocabularyLeaveDiscard => '放弃并离开';

  @override
  String get capabilityVocabularySettingsTitle => '能力动作词表';

  @override
  String get capabilityVocabularySettingsHint => '添加内置词表里没有的能力动作；保存后下一次解题生效';

  @override
  String get learningInsightTitle => '学习洞察';

  @override
  String get learningInsightRefresh => '刷新';

  @override
  String learningInsightLoadFailed(String message) {
    return '读学习洞察失败：$message';
  }

  @override
  String get learningInsightRetry => '重试';

  @override
  String get learningInsightOverlayFallback => '没读到自定义能力词表，已按内置词表展示。';

  @override
  String get learningInsightEmptyTitle => '还没有解题链';

  @override
  String get learningInsightEmptyBody => '先在题目详情页用「AI 解题」跑出几条链，这里才会长出洞察。';

  @override
  String learningInsightSummary(int chains, int steps, int questions) {
    return '$chains 条链 · $steps 步 · $questions 道题';
  }

  @override
  String get learningInsightAdviceSection => '下一步做什么';

  @override
  String get learningInsightAdviceEmpty => '暂时没有可执行的建议';

  @override
  String learningInsightAdviceAction(String label) {
    return '动作：$label';
  }

  @override
  String learningInsightAdviceQuestions(int count) {
    return '$count 道题';
  }

  @override
  String learningInsightAdviceSteps(int count) {
    return '$count 步';
  }

  @override
  String learningInsightAdviceHighRisk(int count) {
    return '高危 $count 步';
  }

  @override
  String get learningInsightActionSection => '能力动作分布';

  @override
  String get learningInsightActionEmpty => '还没有动作读数';

  @override
  String get learningInsightActionBuiltIn => '内置';

  @override
  String get learningInsightActionCustom => '自定义';

  @override
  String get learningInsightActionUnknown => '未知';

  @override
  String learningInsightActionCounts(int steps, int questions, int highRisk) {
    return '$steps 步 · $questions 道题 · 高危 $highRisk 步';
  }

  @override
  String learningInsightRiskAverage(String percent) {
    return '平均风险 $percent';
  }

  @override
  String get learningInsightRiskUnread => '平均风险：未读数';

  @override
  String learningInsightLastSeen(String time) {
    return '最近 $time';
  }

  @override
  String learningInsightUnknownSection(int count) {
    return '词表外的动作（$count）';
  }

  @override
  String get learningInsightUnknownHint => '这些动作不在词表里，不是没问题——建议补词表。';

  @override
  String get learningInsightOpenVocabulary => '去词表页补';

  @override
  String get learningInsightNeverUsedSection => '词表里从没出现过的动作';

  @override
  String get learningInsightNeverUsedHint => '这些动作还没有样本，不代表不该用。';

  @override
  String get learningInsightStuckSection => '卡点热区（知识点）';

  @override
  String learningInsightStuckCounts(
      int highRiskSteps, int questions, int chains) {
    return '高危 $highRiskSteps 步 · $questions 道题 · $chains 条链';
  }

  @override
  String get learningInsightCrossSection => '动作 × 知识点卡点';

  @override
  String get learningInsightSettingsTitle => '学习洞察';

  @override
  String get learningInsightSettingsHint => '看解题链里的能力动作与卡点，以及下一步练什么';

  @override
  String get practiceRecommendationTitle => '下一步练什么';

  @override
  String get practiceRecommendationEmpty => '还没有可推荐的题：先多收几道题、跑几次 AI 解题，再回来看。';

  @override
  String get practiceRecommendationFailed => '配题推荐暂时算不出来';

  @override
  String practiceRecommendationRank(int rank) {
    return '第 $rank 名';
  }

  @override
  String practiceRecommendationActions(String labels) {
    return '命中动作：$labels';
  }

  @override
  String practiceRecommendationMoreReasons(int count) {
    return '另有 $count 条理由';
  }

  @override
  String practiceRecommendationSkipped(int count) {
    return '还有 $count 道没显示';
  }

  @override
  String get practiceRecommendationReasonMatchedAdviceAction => '命中学习建议的练习动作';

  @override
  String get practiceRecommendationReasonMatchedHighRiskKnowledgePoint =>
      '命中卡点知识点';

  @override
  String get practiceRecommendationReasonUnknownActionScaffold => '词表外的动作，先补基础';

  @override
  String get practiceRecommendationReasonUpToDate => '答案解析齐全';

  @override
  String get practiceRecommendationReasonMissingSolution => '缺解析';

  @override
  String get practiceRecommendationReasonMissingAnswer => '缺答案';

  @override
  String get practiceRecommendationReasonTooHard => '难度偏高';

  @override
  String get practiceRecommendationReasonTooEasy => '难度偏低';

  @override
  String get practiceRecommendationReasonUnrelated => '与当前建议关系不大';

  @override
  String get learningMetricsTitle => '学习效果（复习日志说了算）';

  @override
  String get learningMetricsDetail =>
      '留存率是「隔了多久再看还记得多少」，只看复习结果，不看模型的自我感觉；校准度要等带预测的复习攒出样本。';

  @override
  String get learningMetricsEmpty => '还没有复习记录——这里会随着你复习慢慢长出数字。';

  @override
  String get learningMetricsNoBuckets => '有复习记录，但还没有「第二次复习」，所以还分不出间隔。';

  @override
  String get learningMetricsUnavailable => '复习日志读不出来（见上方错误），这一块暂时没有数字。';

  @override
  String learningMetricsOverall(Object reviewed, Object retention) {
    return '$reviewed 次复习，整体留存 $retention%';
  }

  @override
  String learningMetricsBucket(Object range, Object samples, Object retention) {
    return '$range 天：$samples 次，记住 $retention%';
  }

  @override
  String learningMetricsCalibration(Object brier, Object ece) {
    return '校准：Brier $brier（越小越准），ECE $ece（预测与实际的分箱差距）';
  }

  @override
  String get learningMetricsNoCalibration =>
      '校准曲线还没有样本：从这一版起，每次复习都会在判分前记下模型当时的预测，攒够就会显示。历史复习没有这个值，也不补算。';

  @override
  String get settingsThemeIcons => '图标';

  @override
  String get settingsThemeIconsHint => '图标按语义槽位设置；主题文件里这个版本不认识的名字会回退到该槽位的内置图标。';

  @override
  String get iconPickerTitle => '选择图标';

  @override
  String get iconPickerSearch => '搜索图标名';

  @override
  String get iconPickerRestoreDefault => '恢复默认';

  @override
  String get iconPickerDefault => '默认';

  @override
  String get iconPickerEmpty => '没有匹配的图标';

  @override
  String get iconCategoryCommon => '常用';

  @override
  String get iconCategoryNavigation => '导航';

  @override
  String get iconCategoryTime => '时间';

  @override
  String get iconCategoryKnowledge => '知识';

  @override
  String get iconCategoryObjects => '物件';

  @override
  String get iconCategoryMedia => '媒体';

  @override
  String get iconCategoryPeople => '人物';

  @override
  String get iconCategoryAi => '智能';

  @override
  String get iconCategoryUi => '界面';

  @override
  String get questionIntakeTitle => '收题';

  @override
  String get questionIntakeSubtitle => '粘贴建题、拍照存附件、题库列表';

  @override
  String get questionIntakeEntryHint => '粘贴、拍照、查题库';

  @override
  String get questionBankRefresh => '刷新题库';

  @override
  String questionBankFailed(String message) {
    return '读题库失败：$message';
  }

  @override
  String get questionBankEmpty => '题库还是空的';

  @override
  String get questionBankEmptyHint => '题从三个地方来：收题（粘贴或选文件）、拍照整理、材料入库。AI 不会替你出题。';

  @override
  String get questionBankIntro => '上面四个按钮是往题库里加东西的入口；下面按学科筛，点一行看这道题的详情与解题链。';

  @override
  String questionBankSummary(int questions, int subjects) {
    return '共 $questions 道题 · $subjects 个学科';
  }

  @override
  String get questionBankAllSubjects => '全部学科';

  @override
  String get questionBankNoMatch => '这个学科下还没有题';

  @override
  String get questionBankUntitled => '（题干没读到）';

  @override
  String questionBankPointCount(int count) {
    return '$count 个知识点';
  }

  @override
  String get questionIntakePasteSection => '粘贴建题';

  @override
  String get questionIntakePhotoSection => '拍照 / 选图';

  @override
  String get questionIntakeLibrarySection => '题库列表';

  @override
  String get questionIntakeStemLabel => '题干';

  @override
  String get questionIntakeStemHint => '直接粘贴题干（公式保留 LaTeX 原样）';

  @override
  String get questionIntakeSubjectLabel => '学科';

  @override
  String get questionIntakeSubjectNone => '未标注';

  @override
  String get questionIntakeQuestionTypeLabel => '题型';

  @override
  String get questionIntakeTypeSolution => '解答题';

  @override
  String get questionIntakeTypeSingleChoice => '选择题';

  @override
  String get questionIntakeTypeMultiChoice => '多选题';

  @override
  String get questionIntakeOptionsLabel => '选项';

  @override
  String questionIntakeOptionLabel(String label) {
    return '选项 $label';
  }

  @override
  String get questionIntakeOptionContentHint => '选项内容';

  @override
  String get questionIntakeAddOption => '加一个选项';

  @override
  String get questionIntakeRemoveOption => '删除这个选项';

  @override
  String get questionIntakeCorrectTooltip => '标为正确答案';

  @override
  String get questionIntakeAnswerLabel => '答案';

  @override
  String get questionIntakeSolutionLabel => '解析';

  @override
  String get questionIntakeSourceLevelLabel => '来源分级';

  @override
  String get questionIntakeSourceLabelLabel => '来源说明';

  @override
  String get questionIntakeSourceLabelHint => '例如：2024 湖南师大附中月考';

  @override
  String get questionIntakeYearLabel => '年份';

  @override
  String get questionIntakeRegionLabel => '地区';

  @override
  String get questionIntakeDifficultyLabel => '难度（1–10，可空）';

  @override
  String get questionIntakeSubmit => '入库';

  @override
  String questionIntakeSaved(String stem) {
    return '已入库：$stem';
  }

  @override
  String questionIntakeDuplicate(String stem) {
    return '已存在同题（指纹重复）：$stem';
  }

  @override
  String get questionIntakeStemRequired => '题干不能为空';

  @override
  String get questionIntakeDifficultyInvalid => '难度请填 1–10 之间的数字';

  @override
  String get questionIntakePickImages => '选图 / 拍照';

  @override
  String get questionIntakePicking => '正在保存…';

  @override
  String questionIntakePhotoAdded(int count) {
    return '已存 $count 张，等 AI 整理';
  }

  @override
  String questionIntakePhotoFailed(String error) {
    return '这次选图失败了：$error';
  }

  @override
  String get questionIntakeDropHint => '也可以把照片直接拖到这里（支持微信聊天记录里的图片）';

  @override
  String get questionIntakeDropActive => '松手即可添加照片';

  @override
  String get questionIntakeDropBusy => '上一批照片还在处理，稍等一下再拖';

  @override
  String questionIntakeDropSkippedNonImage(int count) {
    return '已跳过 $count 个非图片文件';
  }

  @override
  String questionIntakeDropDuplicates(int count) {
    return '已忽略 $count 个重复文件';
  }

  @override
  String questionIntakeDropUnreadable(int count) {
    return '有 $count 个文件读不出来';
  }

  @override
  String get questionAuditSectionTitle => '入库体检';

  @override
  String get questionAuditClean => '本次检查未发现硬伤';

  @override
  String get questionAuditReadOnly => '体检只报不改：这里只列出问题，不会自动改题';

  @override
  String get questionAuditEvidence => '判定依据';

  @override
  String questionAuditBadgeTooltip(int errors, int warnings) {
    return '入库体检：错误 $errors 条、存疑 $warnings 条';
  }

  @override
  String questionAuditGroupHeader(String label, int count) {
    return '$label · $count 条';
  }

  @override
  String get questionSerialUnnumbered => 'TR-未编号';

  @override
  String get questionSerialCopyTooltip => '复制题号';

  @override
  String questionSerialCopied(String label) {
    return '已复制 $label';
  }

  @override
  String get questionZujuanSearch => '去组卷网搜这道题';

  @override
  String get questionZujuanCopyKeyword => '复制检索词';

  @override
  String questionZujuanCopied(String keyword) {
    return '检索词已复制：$keyword';
  }

  @override
  String get questionZujuanNoCandidates => '题干里没有可用的检索词';

  @override
  String get questionZujuanBankHint => '组卷网按当前学科过滤：先在网站上切到对应学科，否则会搜不到';

  @override
  String get questionZujuanOpenUrl => '打开搜索页';

  @override
  String get questionZujuanUrlCopied => '搜索页链接已复制：到浏览器粘贴打开';

  @override
  String get questionDetailImagesSection => '题目配图';

  @override
  String questionImageCount(int count) {
    return '共 $count 张';
  }

  @override
  String get questionImageOpenTooltip => '点开看大图';

  @override
  String get questionImageLoadFailed => '这张图读不出来';

  @override
  String get questionIntakePhotoPending => '待整理图片';

  @override
  String get questionIntakeNoPhotos =>
      '还没有拍照。选中的图片会存在本地，等 AI 整理成标签、知识点、闪存卡或题目。';

  @override
  String questionIntakePhotoSummary(String mime, String extension) {
    return '$mime · .$extension';
  }

  @override
  String questionIntakePhotoStem(String filename) {
    return '待识别（图片）：$filename';
  }

  @override
  String get questionIntakeRemovePhoto => '从清单移除';

  @override
  String get questionIntakeNoQuestions => '这个题库还是空的';

  @override
  String questionIntakeListLimitNote(int count) {
    return '最多显示最近 $count 条';
  }

  @override
  String get questionIntakeDelete => '删除';

  @override
  String questionIntakeDeleted(String stem) {
    return '已删除：$stem';
  }

  @override
  String questionIntakeDeletedWithImages(String stem, int count) {
    return '已删除：$stem（同时清理 $count 张配图）';
  }

  @override
  String get questionIntakeDeleteConfirm => '删除这道题？它不会被同步回来。';

  @override
  String get questionIntakeCancel => '取消';

  @override
  String get questionIntakeSearchHint => '搜题干或题号';

  @override
  String get questionIntakeFilterAll => '全部';

  @override
  String questionIntakeOptionCount(int count) {
    return '$count 个选项';
  }

  @override
  String get questionIntakeStateRaw => '待整理';

  @override
  String get questionIntakeStateStructured => '已结构化';

  @override
  String get questionIntakeStateProcessed => '已加工';

  @override
  String get questionIntakeOriginManual => '手工';

  @override
  String get questionIntakeOriginAiScan => '拍照/扫描';

  @override
  String get questionIntakeOriginFurnace => 'Furnace 内建';

  @override
  String get questionIntakeSourceGaokao => '高考真题';

  @override
  String get questionIntakeSourceProvincialDiagnostic => '强省强市诊断';

  @override
  String get questionIntakeSourceEliteSchool => '名校测试';

  @override
  String get questionIntakeSourceSchool => '学校题';

  @override
  String get questionIntakeSourcePersonal => '自建';

  @override
  String get questionIntakeSourceUnknown => '未标注';

  @override
  String get zujuanPickOpenButton => '定点找题';

  @override
  String get zujuanPickTitle => '定点找题';

  @override
  String get zujuanPickIntro => '选筛选条件，复制链接到浏览器打开组卷网；App 只生成链接，不抓取页面。';

  @override
  String get zujuanPickSubject => '学科';

  @override
  String get zujuanPickKnowledgePoint => '知识点 id';

  @override
  String get zujuanPickKnowledgePointHint => '留空 = 该学科全部知识点';

  @override
  String get zujuanPickDifficulty => '难度';

  @override
  String get zujuanPickAny => '不限';

  @override
  String get zujuanPickYear => '年份';

  @override
  String get zujuanPickYearEarlier => '更早';

  @override
  String get zujuanPickProvince => '省份';

  @override
  String get zujuanPickGrade => '年级';

  @override
  String get zujuanPickGradeSenior1 => '高一';

  @override
  String get zujuanPickGradeSenior2 => '高二';

  @override
  String get zujuanPickGradeSenior3 => '高三';

  @override
  String get zujuanPickSort => '排序';

  @override
  String get zujuanPickUrl => '检索链接';

  @override
  String get zujuanPickCopy => '复制链接';

  @override
  String get zujuanPickCopied => '检索链接已复制：到浏览器粘贴打开';

  @override
  String get zujuanPickNoScrapeHint =>
      'App 不抓取组卷网页面（站点有反爬）；要看答案与解析，请你在浏览器里登录组卷网后查看。';

  @override
  String get zujuanPickLoginHint =>
      '登录后可看答案与解析（免费账号每天约 30 道）；把看过的题面/答案/解析粘回来，用「粘贴组卷网题面」入库。';

  @override
  String get zujuanPasteOpenButton => '粘贴组卷网题面';

  @override
  String get zujuanPasteTitle => '粘贴组卷网题面';

  @override
  String get zujuanPasteIntro => '从组卷网复制题目文本（可以多题），解析后预览、勾选、改题干，再按「全部入库」。';

  @override
  String get zujuanPasteLoginHint =>
      '组卷网答案需登录后查看（免费账号每天约 30 道）；把答案/解析一起粘进来会自动识别。';

  @override
  String get zujuanPasteInputLabel => '题面文本';

  @override
  String get zujuanPasteInputHint => '粘贴含【答案】【解析】的题面；多题之间用空行分隔';

  @override
  String get zujuanPasteParse => '解析';

  @override
  String get zujuanPasteParseEmpty => '这段文本里没解析出题目：粘贴至少一道题的题干再试。';

  @override
  String zujuanPastePreviewTitle(int count) => '解析出 $count 道题';

  @override
  String get zujuanPasteItemStem => '题干（可改）';

  @override
  String zujuanPasteItemOptions(int count) => '$count 个选项';

  @override
  String zujuanPasteItemSource(String source) => '来源：$source';

  @override
  String zujuanPasteItemYear(int year) => '$year 年';

  @override
  String get zujuanPastePartial => '识别不完整：请核对题干与选项';

  @override
  String get zujuanPasteImport => '全部入库';

  @override
  String get zujuanPasteImporting => '正在入库…';

  @override
  String get zujuanPasteNothingSelected => '没有勾选任何题：先勾选要入库的题。';

  @override
  String zujuanPasteSummary(int saved, int duplicates, int failed) =>
      '已入库 $saved 道 · 重复 $duplicates 道 · 失败 $failed 道';

  @override
  String get questionDetailTitle => '题目详情';

  @override
  String get questionDetailQuestionMissing => '这道题已不在题库里（可能刚被删掉）。';

  @override
  String get questionDetailEditSource => '改来源';

  @override
  String get questionDetailEditSourceTitle => '改一改来源';

  @override
  String get questionDetailEditSourceHint => '留空的字段 = 不改那一列；题干、答案与选项一个字不动。';

  @override
  String get questionDetailEditSourceYearBad => '年份要写 1900–2200 之间的整数';

  @override
  String get questionDetailCorrectOption => '正确答案';

  @override
  String questionDetailYear(int year) {
    return '$year 年';
  }

  @override
  String questionDetailDifficulty(String value) {
    return '难度 $value';
  }

  @override
  String questionDetailAiQuality(String value) {
    return 'AI 自评质量 $value';
  }

  @override
  String get questionDetailTrapNote => '坑点';

  @override
  String get questionDetailReasoningSection => 'AI 解题与卡点评估';

  @override
  String get questionDetailSolveButton => 'AI 解题';

  @override
  String get questionDetailResolveButton => '再解一次';

  @override
  String get questionDetailSolving => '正在解题…';

  @override
  String get questionDetailNoChainYet => '还没有思维链。点上面的按钮让 AI 解一遍，链会存进本地题库。';

  @override
  String get questionDetailChainFromLibrary => '以下是最近一次解题存下来的链；再解一次会另存一条新的。';

  @override
  String get questionDetailRunFailedTitle => '这次解题没有成功';

  @override
  String get questionDetailFailureReasonLabel => '失败原因';

  @override
  String get questionDetailRawReplyLabel => '模型原始回复';

  @override
  String get questionDetailRawReplyMissing => '（没有留下原始回复）';

  @override
  String questionDetailOverallRisk(int percent) {
    return '整条链的最高卡点风险：约 $percent%';
  }

  @override
  String questionDetailMostLikelyStep(int index) {
    return '最可能卡住的是第 $index 步';
  }

  @override
  String questionDetailEvidenceCoverage(int covered, int total) {
    return '其中 $covered/$total 步有你的状态读数';
  }

  @override
  String questionDetailStepTitle(int index) {
    return '第 $index 步';
  }

  @override
  String questionDetailUnknownAction(String actionType) {
    return '词表里没有这个动作：$actionType';
  }

  @override
  String get questionDetailStepGoalLabel => '这一步要达成什么';

  @override
  String get questionDetailStepJustificationLabel => '为什么这样走';

  @override
  String get questionDetailStepCheckLabel => '怎么自检';

  @override
  String get questionDetailStepKnowledgeLabel => '涉及的知识点';

  @override
  String questionDetailModelRisk(int percent) {
    return '模型判断的风险：约 $percent%';
  }

  @override
  String questionDetailFusedRisk(int percent) {
    return '合上你的状态读数：约 $percent%';
  }

  @override
  String get questionDetailSuggestionLabel => '建议';

  @override
  String get questionDetailUnmatchedHintsTitle => '这些知识点还没有你的状态数据';

  @override
  String get questionDetailUnmatchedHintsBody => '这不代表它们没问题，只是本地还没有对应的记忆读数。';

  @override
  String get questionDetailKnowledgePointsLabel => '这道题挂载的知识点';

  @override
  String get questionDetailKnowledgePointNoReading => '暂无你的状态数据';

  @override
  String get questionDetailStatesLoading => '正在读你的学习状态…';

  @override
  String questionDetailStatesFailed(String error) {
    return '状态读数没读出来：$error';
  }

  @override
  String get questionPaperTitle => '组卷';

  @override
  String get questionPaperEntryHint => '按薄弱点和危险区，从题库里凑一份练习卷';

  @override
  String get questionPaperSubtitle => '只从你已有的题里选：优先危险区；缺口如实列出，AI 不会替你出题。';

  @override
  String get questionPaperTargetCountLabel => '目标题数';

  @override
  String questionPaperCountOption(int count) {
    return '$count 道';
  }

  @override
  String get questionPaperSubjectLabel => '学科';

  @override
  String get questionPaperSubjectAny => '不限学科';

  @override
  String get questionPaperSubjectNone => '未标注学科';

  @override
  String get questionPaperSourceLevelLabel => '来源下限';

  @override
  String get questionPaperSourceLevelAny => '不限来源';

  @override
  String questionPaperHeadline(int want, int got) {
    return '想要 $want 道，凑到 $got 道';
  }

  @override
  String questionPaperFailed(String error) {
    return '组卷没算出来：$error';
  }

  @override
  String get questionPaperShortNotice => '题库不够：这不是错误，是本地还没有足够的题。去收题再回来。';

  @override
  String questionPaperOverallNeed(String need) {
    return '整体该练程度 $need';
  }

  @override
  String questionPaperCandidateCount(int count) {
    return '候选 $count 道';
  }

  @override
  String get questionPaperEmptyBank => '题库还是空的：先去收题，再回来组卷。';

  @override
  String get questionPaperEmptyPlan => '按当前条件一道也凑不出：把学科或来源下限放宽一点。';

  @override
  String get questionPaperUncoveredTitle => '题库里没有候选 → 去收题';

  @override
  String get questionPaperUncoveredBody =>
      '这些知识点在危险区，但题库里一道相关的题都没有。AI 不能自己出题，所以这里如实留空。';

  @override
  String get questionPaperDeferredTitle => '这轮被挤掉的知识点';

  @override
  String get questionPaperDeferredBody =>
      '有候选，但受目标题数或每个知识点的配额限制没排进来；把目标题数调大一些。';

  @override
  String get questionPaperKnowledgePointLabel => '知识点';

  @override
  String get questionPaperKnowledgePointNone => '未标注知识点';

  @override
  String questionPaperItemIndex(int index) {
    return '第 $index 题';
  }

  @override
  String get questionPaperItemReasonLabel => '为什么排它';

  @override
  String get questionPaperItemImprovementLabel => '提升点';

  @override
  String get questionPaperItemBackgroundLabel => '知识背景';

  @override
  String get questionSimilarTitle => '找相似题';

  @override
  String get questionSimilarSubtitle => '只从已有题库里找；找不到就说没有，不拿看着像的凑数。';

  @override
  String get questionSimilarLoading => '正在翻题库…';

  @override
  String questionSimilarFailed(String error) {
    return '找相似题没算出来：$error';
  }

  @override
  String questionSimilarCount(int count) {
    return '库里找到 $count 道相似题';
  }

  @override
  String get questionSimilarEmpty => '库里还没有相似的题。';

  @override
  String get questionSimilarGoIntake => '去收题';

  @override
  String get questionSimilarCrossSubject => '跨学科迁移';

  @override
  String get handwritingQueueTitle => '拍照整理';

  @override
  String get handwritingQueueEntryHint => '把拍好的照片整理成标签、知识点、闪存卡或题目，逐条确认才写库';

  @override
  String get handwritingQueueSubtitle =>
      'AI 只整理照片里真实存在的内容（题目原样誊写，不自己出题）：每一条都要你点确认才会写进库里。';

  @override
  String get handwritingQueueEmpty => '还没有拍照或选图。先去收题页拍一张，再回来整理。';

  @override
  String get handwritingQueueGoIntake => '去收题页';

  @override
  String get handwritingQueuePhotosLabel => '待整理照片';

  @override
  String get handwritingQueueOrganizeAction => '整理这张';

  @override
  String get handwritingQueueAnalyze => '整理这张照片';

  @override
  String get handwritingQueueAnalyzing => '正在看照片…';

  @override
  String get handwritingQueueNotAnalyzed => '这张照片还没整理过。';

  @override
  String get handwritingQueueNothingFound =>
      '模型没给出可整理的产物：这张照片里可能没有标签、知识点、卡片或题目。';

  @override
  String get handwritingQueueFailureTitle => '这次整理失败了';

  @override
  String get handwritingQueueForget => '丢弃整理结果';

  @override
  String get handwritingQueueProposalsLabel => '待确认的产物';

  @override
  String get handwritingQueueApplyAll => '全部确认';

  @override
  String get handwritingQueueApplying => '正在写库…';

  @override
  String handwritingQueueReportSummary(int applied, int failed) {
    return '本次确认：成功 $applied 条，失败 $failed 条';
  }

  @override
  String get handwritingProposalApply => '确认';

  @override
  String get handwritingProposalApplied => '已确认';

  @override
  String handwritingProposalConfidence(String band) {
    return '模型自评：$band';
  }

  @override
  String get handwritingProposalConfidenceHigh => '较确定';

  @override
  String get handwritingProposalConfidenceMedium => '拿不准';

  @override
  String get handwritingProposalConfidenceLow => '不太确定';

  @override
  String handwritingProposalCardCount(int count) {
    return '$count 张卡片';
  }

  @override
  String get handwritingQuestionMissingStem => '没认出题干，重拍或手填';

  @override
  String handwritingQuestionOptions(int count) {
    return '选项（$count 个）';
  }

  @override
  String handwritingQuestionAnswer(String value) {
    return '答案：$value';
  }

  @override
  String handwritingQuestionSolution(String value) {
    return '解析：$value';
  }

  @override
  String get handwritingQuestionEmptyValue => '没有';

  @override
  String get handwritingQuestionEditForIntake => '编辑后保存';

  @override
  String handwritingQuestionSaved(String serial) {
    return '已入库：$serial（拍照整理已标记为确认）';
  }

  @override
  String get handwritingQuestionSavedUnnumbered => '已入库（未编号，拍照整理已标记为确认）';

  @override
  String get handwritingQueuePreviewLoading => '正在预检…';

  @override
  String get handwritingQueuePreviewNeedsReview => '确认前看一眼';

  @override
  String get handwritingQueuePreviewBlocked => '不能确认';

  @override
  String handwritingQueuePreviewBlockedSummary(
    int ready,
    int needsReview,
    int blocked,
  ) {
    return '$ready 条能确认、$needsReview 条要先看一眼、$blocked 条不能确认';
  }

  @override
  String get questionPaperDifficultyLabel => '目标难度';

  @override
  String get questionPaperDifficultyAny => '不限难度';

  @override
  String questionPaperDifficultyOption(String value) {
    return '难度 $value';
  }

  @override
  String get questionPaperDifficultyHint =>
      '难度是偏好不是硬筛：越接近越靠前；题库里没填难度的题会按「半贴合」排后面，不会被排除。';

  @override
  String get questionPaperCapLabel => '每个知识点上限';

  @override
  String get questionPaperCapAuto => '自动';

  @override
  String questionPaperCapOption(int cap) {
    return '最多 $cap 道';
  }

  @override
  String get questionPaperReset => '重置组卷条件';

  @override
  String get questionPaperActionProfileLabel => '按能力动作画像排（未标定）';

  @override
  String get questionPaperActionProfileHint =>
      '命中「你最该练的动作」的题往前排一点；没有解题链时不起作用，可以关。';

  @override
  String questionPaperActionProfileNote(String actions) {
    return '这一卷按「$actions」这类动作排过（未标定，可关）';
  }

  @override
  String get questionPaperCopy => '复制卷面';

  @override
  String get questionPaperCopyDone => '卷面已复制：粘到 Word 或打印预览就能用。';

  @override
  String get questionPaperCopyReasonLabel => '理由';

  @override
  String get questionPaperCopyImprovementLabel => '提升点';

  @override
  String get questionPaperCopyBackgroundLabel => '背景';

  @override
  String get questionPaperCopyUncoveredHeading => '未覆盖的知识点';

  @override
  String get questionPaperCopyDeferredHeading => '被上限挡下的知识点';

  @override
  String get questionPaperExportDocx => '导出 Word';

  @override
  String get questionPaperExportDocxBusy => '正在导出…';

  @override
  String questionPaperExportDocxDone(
      int questions, int images, String fileName) {
    return '已导出 $questions 道题（配图 $images 张）：$fileName';
  }

  @override
  String questionPaperExportDocxEmptyDone(String fileName) {
    return '卷面是空的：只导出了标题与缺口说明（$fileName）';
  }

  @override
  String get questionPaperExportDocxFailed => '导出失败';

  @override
  String questionPaperExportDocxWarnings(int count) {
    return '有 $count 处提示';
  }

  @override
  String get questionPaperExportDocxWarningsAction => '查看';

  @override
  String get questionPaperExportDocxWarningsTitle => '导出提示';

  @override
  String get questionPaperExportDocxMissingQuestions => '缺失题目';

  @override
  String get questionPaperExportDocxSkippedImages => '跳过的配图';

  @override
  String get questionPaperExportDocxFormulaFailures => '公式编译失败';

  @override
  String get questionPaperExportDocxImageLoadNotes => '读图提示';

  @override
  String get questionPaperExportDocxMissingFields => '卷面缺字段';

  @override
  String questionPaperExportDocxMissingStem(int count) {
    return '缺题干 $count 道';
  }

  @override
  String questionPaperExportDocxMissingAnswer(int count) {
    return '缺答案 $count 道';
  }

  @override
  String questionPaperExportDocxMissingSolution(int count) {
    return '缺解析 $count 道';
  }

  @override
  String questionPaperExportDocxMoreItems(int count) {
    return '等 $count 条';
  }

  @override
  String get paperSubjectQuotaTitle => '学科配额';

  @override
  String get paperSubjectQuotaHint => '留空 = 不限；上限 0 = 这一科一道都不选。';

  @override
  String get paperSubjectQuotaNoSubjects => '学科配额只作用于已选学科：先在上面选中学科，再给每科设上限或保底。';

  @override
  String get paperSubjectQuotaMaxLabel => '上限';

  @override
  String get paperSubjectQuotaMinLabel => '保底';

  @override
  String get paperSubjectQuotaClear => '清空配额';

  @override
  String get paperSubjectQuotaInvalid => '请输入非负整数';

  @override
  String get paperSubjectDistribution => '学科分布';

  @override
  String paperSubjectQuotaBlocked(int count) {
    return '被学科上限挡下 $count 道';
  }

  @override
  String paperSubjectQuotaBlockedItem(
      String subject, int limit, String detail) {
    return '$subject（上限 $limit 道）：$detail';
  }

  @override
  String paperSubjectQuotaBlockedMore(int count) {
    return '还有 $count 道被挡下的题没列出';
  }

  @override
  String get paperSubjectQuotaShortfallTitle => '保底缺口';

  @override
  String paperSubjectQuotaShortfall(
      String subject, int missing, int available) {
    return '$subject 还差 $missing 道（可用 $available 道）';
  }

  @override
  String paperSubjectQuotaShortfallEmpty(String subject) {
    return '$subject 在题库里没有可用题';
  }

  @override
  String get paperDomainQuotaTitle => '领域配额';

  @override
  String get paperDomainQuotaHint =>
      '留空 = 不限；上限 0 = 这个领域一道都不选。领域是知识点标签路径的第一段，与上面的学科配额是两套键。';

  @override
  String get paperDomainQuotaMaxLabel => '上限';

  @override
  String get paperDomainQuotaMinLabel => '保底';

  @override
  String get paperDomainQuotaClear => '清空配额';

  @override
  String get paperDomainQuotaInvalid => '请输入非负整数';

  @override
  String get paperDomainQuotaDistribution => '领域分布';

  @override
  String paperDomainQuotaBlocked(int count) {
    return '被领域上限挡下 $count 道';
  }

  @override
  String paperDomainQuotaBlockedItem(String domain, int limit, String detail) {
    return '$domain（上限 $limit 道）：$detail';
  }

  @override
  String paperDomainQuotaBlockedMore(int count) {
    return '还有 $count 道被挡下的题没列出';
  }

  @override
  String get paperDomainQuotaShortfallTitle => '领域保底缺口';

  @override
  String paperDomainQuotaShortfall(String domain, int missing, int available) {
    return '$domain 还差 $missing 道（可用 $available 道）';
  }

  @override
  String paperDomainQuotaShortfallEmpty(String domain) {
    return '$domain 在题库里没有可用题';
  }

  @override
  String paperDomainQuotaUncovered(String domains) {
    return '未覆盖领域：$domains';
  }

  @override
  String get paperManualSelectionTitle => '手工指定';

  @override
  String get paperManualSelectionAdd => '选择题';

  @override
  String get paperManualSelectionHint =>
      '必收题点名就要（只受目标题数上限）；排除题任何阶段都不选；两者冲突时排除优先。';

  @override
  String paperManualSelectionIncludeTitle(int count) {
    return '必收（$count 道）';
  }

  @override
  String paperManualSelectionExcludeTitle(int count) {
    return '排除（$count 道）';
  }

  @override
  String get paperManualSelectionRemove => '移除';

  @override
  String get paperManualSelectionClear => '清空手工选择';

  @override
  String get paperManualSelectionPickerTitle => '选择题';

  @override
  String get paperManualSelectionPickerFilterHint => '按题干或题目 id 过滤';

  @override
  String get paperManualSelectionPickerInclude => '设为必收';

  @override
  String get paperManualSelectionPickerExclude => '设为排除';

  @override
  String get paperManualSelectionPickerNone => '题库里没有可选的题';

  @override
  String paperManualSelectionPickerFailed(String message) {
    return '读取题库失败：$message';
  }

  @override
  String paperManualSelectionOutcomeIncluded(int count) {
    return '本卷收下必收题 $count 道';
  }

  @override
  String paperManualSelectionMissingTitle(int count) {
    return '必收但题库里没有（$count 道）';
  }

  @override
  String paperManualSelectionSkippedTitle(int count) {
    return '必收但被目标题数挤掉（$count 道）';
  }

  @override
  String paperManualSelectionConflictTitle(int count) {
    return '必收与排除冲突（排除生效，$count 道）';
  }

  @override
  String paperManualSelectionMore(int count) {
    return '还有 $count 道没列出';
  }

  @override
  String get paperQualityTitle => '组卷质量体检';

  @override
  String paperQualitySummary(
      int questionCount, int requestedCount, String percent) {
    return '题数 $questionCount / 想要 $requestedCount 道（填充率 $percent）';
  }

  @override
  String paperQualityCoverage(String percent) {
    return '知识点覆盖率 $percent';
  }

  @override
  String get paperQualityQuotaUnsatisfied => '保底配额没满足：下面会说明差在哪。';

  @override
  String get paperQualityClean => '没有命中任何判据';

  @override
  String paperQualityGroupHeader(String label, int count) {
    return '$label（$count）';
  }

  @override
  String get paperQualityEvidenceToggle => '查看依据';

  @override
  String get paperQualityEvidenceCollapse => '收起依据';

  @override
  String get paperQualityEvidenceTitle => '判定依据';

  @override
  String paperQualityTruncated(int count) {
    return '还有 $count 条判据被截断';
  }

  @override
  String get paperQualityFailed => '体检暂时算不出来';

  @override
  String get tasksDueAtConflictTitle => '这段时间撞上了日程块';

  @override
  String tasksDueAtConflictBody(String title, String range) {
    return '「$title」$range 是忙碌日程块，不能排进去。';
  }

  @override
  String tasksDueAtConflictMoveBefore(String moment) {
    return '移到这块之前（$moment）';
  }

  @override
  String tasksDueAtConflictMoveAfter(String moment) {
    return '移到这块之后（$moment）';
  }

  @override
  String get tasksDueAtConflictKeep => '保持不动';

  @override
  String get tasksDueAtConflictNoFreeMoment => '这个方向找不到空闲时段';
}
