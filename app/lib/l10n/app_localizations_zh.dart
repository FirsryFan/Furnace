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
  String get navMindnet => 'Mindnet';

  @override
  String get navTags => '标签';

  @override
  String get navThread => 'Thread';

  @override
  String get navTasks => '任务';

  @override
  String get navTime => 'Time';

  @override
  String get navAnki => 'Knowledge';

  @override
  String get navKnowledge => 'Knowledge';

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
  String get settingsTheme => '主题';

  @override
  String get settingsThemeSystem => '跟随系统';

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
  String get timeMarkBusy => '标记为忙碌';

  @override
  String get timeMarkOpen => '标记为开放';

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
  String get ankiStartReview => '开始复习';

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
  String get ankiNewKnowledgePoint => '新建词条';

  @override
  String get ankiAutoBlank => '自动挖空';

  @override
  String get ankiSource => '来源';

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
  String get ankiNoDueCards => '没有到期词条';

  @override
  String get ankiCorrect => '正确';

  @override
  String get ankiWrong => '错误';

  @override
  String get ankiYourAnswer => '你的答案';

  @override
  String get packagesImport => '导入知识包';

  @override
  String get packagesExport => '导出知识包';

  @override
  String get packagesImportHint => '选择一个 .kpak 文件';

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
  String get tagsDeleteBody => '它的整棵子树会一起删除，已挂载该标签的事件/词条会失去这个标签。';

  @override
  String get threadTitle => 'Thread';

  @override
  String get threadSort => '更新与排序';

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
  String get threadEnergy2 => '极低 · 只适合机械事务';

  @override
  String get threadEnergy3 => '偏低 · 轻松任务';

  @override
  String get threadEnergy4 => '偏低 · 轻松任务';

  @override
  String get threadEnergy5 => '中等 · 常规任务';

  @override
  String get threadEnergy6 => '中等 · 常规任务';

  @override
  String get threadEnergy7 => '偏高 · 需要专注';

  @override
  String get threadEnergy8 => '偏高 · 需要专注';

  @override
  String get threadEnergy9 => '极高 · 攻坚';

  @override
  String get threadEnergy10 => '极高 · 攻坚';

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
  String get threadExpectedNear => '期望时刻临近';

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
  String get threadSortHint => '重新排序';

  @override
  String get propTitleHint => '这件事叫什么。排序不读标题，但你自己靠它认出来。';

  @override
  String get propDescriptionHint => '详细说明。排序不读正文，只给你自己看。';

  @override
  String get propEstimateHint => '你估计要花多久。排序用它判断截止时刻之前装不装得下。';

  @override
  String get propExpectedHint => '你打算什么时候做。临近时它会变黄并提权，但它永远不会让它变红——因为可以推迟。';

  @override
  String get propDeadlineHint => '真正的硬底线。装不下就会进「时间不足」，并移出主列表。';

  @override
  String get propEnergyHint => '这件事需要多少精力（1-10）。与你当前的精力越接近，排序越靠前。';

  @override
  String get propAlgorithm => '排序参数';

  @override
  String get propAlgorithmHint =>
      '这个事件在最近一次排序中拿到的原始分量与权重。总分＝各分量×权重之和。右侧按钮可以改权重。';

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
  String get propWeightsEditable => '权重对所有事件生效，可编辑。';

  @override
  String get propResetWeights => '恢复默认权重';

  @override
  String get propTemplatesNote => '事件模板与批量修改会复用这里的同一套参数。';

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
  String knowledgeNextIn(int days) {
    return '下次复习：$days 天后';
  }

  @override
  String knowledgeBoosted(int count, String factor) {
    return '同时提权了 $count 个相关词条（最高 $factor 倍）';
  }

  @override
  String get knowledgeCreateTask => '生成任务';

  @override
  String get knowledgeTaskCreated => '已生成任务';

  @override
  String get knowledgeInsight => '今日复盘';

  @override
  String get knowledgeReviewTab => '复习';

  @override
  String get knowledgeInsightEmpty => '今天还没有记录';

  @override
  String get knowledgeInsightWrong => '答错的';

  @override
  String get knowledgeInsightBoost => '被提权的相关词条';

  @override
  String knowledgeInsightDistance(int distance) {
    return '距离 $distance';
  }

  @override
  String knowledgeInsightFactor(String factor) {
    return '$factor 倍';
  }

  @override
  String get settingsDemoData => '载入示例数据';

  @override
  String get settingsDemoDataHint => '生成一批示例标签、词条、事件与日程块，方便先看界面效果。';

  @override
  String get settingsDemoDataConfirm => '把示例数据加进当前工作区？';

  @override
  String get settingsDemoDataBlocked => '当前工作区已有内容，示例数据不会载入（避免重复）。';

  @override
  String get settingsDemoDataDone => '示例数据已载入';

  @override
  String get settingsUsageDoc => '使用文档';

  @override
  String get settingsUsageDocHint => '排序算法与全部参数的说明都在这里';

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
  String get aiSend => '发送';

  @override
  String get aiThinking => '思考中…';

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
  String get settingsAiSave => '保存';

  @override
  String get settingsAiSaved => '已保存';

  @override
  String get settingsAiKeyRequired => '填入 API key 后才能启用';

  @override
  String get settingsAiPlatformNote =>
      'Android 上没有 Node 运行时与桌面浏览器，脚本型 skill 与浏览器扩展能力只在 Windows 上可用。';
}
