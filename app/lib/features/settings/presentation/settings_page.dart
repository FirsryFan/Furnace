/// 设置页：分区列表（2026-11-15 第二遍清理，task-113）。
///
/// 第一遍（task-107/settings-redesign）把原来 20 个平铺的 `ListTile` 分成七块；
/// 第二遍解决的是**入口位置**问题（用户反馈：很多入口要合并；管线/外接入口要
/// 清理；「认知模型」进去基本是闪存卡读数；卡组设置不该放总设置）：
///
///  1. 档案卡（只读摘要；点按改名）；
///  2. 学习与计划——**只留普通学生真正会用的 5 项**：今日计划 / 复习提醒 /
///     学习洞察 / 自我描述 / 评测与认知档案；
///  3. AI——只留「AI 接入」（模型 / API / 权限）。轮次上限、工具清单、技能包
///     这类开发者参数下沉到 `AiSettingsPage` 里默认折叠的「开发者参数」；
///  4. 外观与阅读——语言 + 主题 + Markdown 排版；
///  5. 数据——**一个入口组**：`备份与恢复`（导出/导入工作区 .tfpkg）作为统一
///     备份入口，题库包（.tqb）/ 学习数据 / 数据位置 / 知识库（.kpak）都在
///     同一张卡里；诊断包是排障工具，不在用户数据区（见 7）；
///  6. 帮助——使用文档 / 关于；
///  7. 开发者（默认折叠）——开发者信息（认知读数）、设计与内容板块、高考资源库、
///     诊断包、预设选择（原型）、示例数据、能力动作词表。
///
/// 从总设置移走的入口（功能都还在，只是归位到各自的模块）：
///
///  * **卡组设置** → 闪存卡模块。卡组就是标签树，每日新卡/复习上限 + 判分方式
///    都在 `ReviewPlanPage`（闪存卡页「更多」菜单里的「卡组设置」）；
///  * **认知模型** → 学习状态模块。用户层只到顶层 MindNet（学习状态）页，设置
///    不再放「认知模型」原页，避免同一组读数两个门、且看起来全是闪存卡；
///  * **高考资源库** → 开发者分区（只读索引，不是日常学习入口）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../../../app/settings/settings_controller.dart';
import '../../../domain/services/cognitive/user_persona.dart';
import '../../ai/presentation/ai_settings_page.dart';
import '../../assessment/presentation/assessment_center_page.dart';
import '../../cognitive/presentation/cognitive_developer_page.dart';
import '../../cognitive/presentation/today_plan_page.dart';
import '../../design_board/presentation/design_board_page.dart';
import '../../library/presentation/gaokao_library_page.dart';
import '../../packages/presentation/packages_page.dart';
import '../../questions/presentation/learning_insight_page.dart';
import '../../student_preset/application/preset_selection.dart';
import '../../student_preset/presentation/preset_select_page.dart';
import '../../tags/presentation/tag_tree_page.dart';
import '../../thread/application/thread_rank_service.dart';
import '../../timeboard/presentation/calendar_page.dart';
import '../../timeboard/presentation/time_board_page.dart';
import '../application/demo_data_service.dart';
import '../application/user_persona_provider.dart';
import 'about_page.dart';
import 'appearance_section.dart';
import 'capability_vocabulary_page.dart';
import 'data_backup_page.dart';
import 'data_location_tile.dart';
import 'data_section.dart';
import 'review_reminder_section.dart';
import 'settings_layout.dart';
import 'settings_profile_card.dart';
import 'usage_doc_page.dart';
import 'user_persona_page.dart';

/// 「自我描述」的设置入口（task-187）。
const Key settingsUserPersonaTileKey = Key('settings-user-persona-tile');

/// 知识库（.kpak）管理入口：从顶层导航下沉到设置（决策记录 D7）。
const Key settingsKnowledgeLibraryTileKey =
    Key('settings-knowledge-library-tile');

/// 评测与认知档案的入口（用户评测板块设计文档 v1.0）。
const Key settingsAssessmentTileKey = Key('settings-assessment-tile');

/// 只读「设计与内容板块」的入口（通宵 task-25）：开发者分区，默认折叠。
const Key settingsDesignBoardTileKey = Key('settings-design-board-tile');

/// 预设选择（task-64 原型）的入口：开发者分区，默认折叠。
const Key settingsPresetSelectTileKey = Key('settings-preset-select-tile');

/// 页面级分区标题的 key（测试用来断言分区顺序与存在性）。
const Key settingsSectionLearningKey = Key('settings-section-learning');
const Key settingsSectionAiKey = Key('settings-section-ai');
const Key settingsSectionAppearanceReadingKey =
    Key('settings-section-appearance-reading');
const Key settingsSectionDataKey = Key('settings-section-data');
const Key settingsSectionHelpKey = Key('settings-section-help');
const Key settingsSectionDeveloperKey = Key('settings-section-developer');

/// 「开发者」分区的显示/隐藏按钮（默认隐藏，测试点它展开）。
const Key settingsDeveloperToggleKey = Key('settings-developer-toggle');

/// 学习分区里的关键入口（测试用 key 定位，避免依赖中英文文案）。
const Key settingsTodayPlanTileKey = Key('settings-today-plan-tile');
const Key settingsLearningInsightTileKey = Key('settings-learning-insight-tile');

/// 高考资源库入口：第二遍清理后它属于开发者分区（只读索引，非日常入口）。
const Key settingsHighSchoolLibraryTileKey =
    Key('settings-gaokao-library-tile');

/// 诊断包入口：第二遍清理后从「数据」移到开发者分区（排障工具）。
const Key settingsDiagnosticsTileKey = Key('settings-diagnostics-tile');

/// AI / 外观 / 帮助 / 开发者分区里的入口。
const Key settingsAiTileKey = Key('settings-ai-tile');
const Key settingsLanguageTileKey = Key('settings-language-tile');
const Key settingsUsageDocTileKey = Key('settings-usage-doc-tile');
const Key settingsAboutTileKey = Key('settings-about-tile');
const Key settingsDemoDataTileKey = Key('settings-demo-data-tile');

/// Settings page: profile card + seven sections, developer entries collapsed.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  /// 开发者分区是否展开。默认 false：普通学生看到的只有 1-6 块。
  bool _developerExpanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final persona = ref.watch(userPersonaProvider).valueOrNull;
    final presetSelection = ref.watch(presetSelectionProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
      // 桌面宽屏（2560）上整行铺满会把分区拉成一条条长横线；设置页是一列
      // 短行，给内容一个最大宽度再居中，分区和卡片边界才看得出来。
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 988),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const SettingsProfileCard(),
              _learningSection(l10n, persona),
              _aiSection(l10n),
              _appearanceReadingSection(l10n, settings),
              _dataSection(l10n),
              _helpSection(l10n),
              _developerSection(l10n, presetSelection),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. 学习与计划
  // ---------------------------------------------------------------------------

  Widget _learningSection(AppLocalizations l10n, String? persona) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(
          key: settingsSectionLearningKey,
          icon: Icons.school_outlined,
          title: l10n.settingsSectionLearning,
        ),
        SettingsSectionCard(
          children: [
            SettingsNavTile(
              tileKey: settingsTodayPlanTileKey,
              icon: Icons.today_outlined,
              title: l10n.settingsTodayPlan,
              onTap: () => _push(context, const TodayPlanPage()),
            ),
            // 复习提醒：开关 + 每天提醒时刻（v28 两列，排程在 features/anki）。
            const ReviewReminderSection(),
            // 学习洞察入口（task-39）：只读展示已聚合好的解题链洞察与卡点。
            SettingsNavTile(
              tileKey: settingsLearningInsightTileKey,
              icon: Icons.auto_graph,
              title: l10n.learningInsightSettingsTitle,
              subtitle: l10n.learningInsightSettingsHint,
              onTap: () => _push(context, const LearningInsightPage()),
            ),
            // 自我描述（task-187）：AI 对话会把它当背景。
            SettingsNavTile(
              tileKey: settingsUserPersonaTileKey,
              icon: Icons.person_outline,
              title: l10n.personaTitle,
              subtitle: userPersonaIsPresent(persona)
                  ? userPersonaPreview(persona, maxChars: 40)
                  : l10n.personaSettingsSubtitle,
              onTap: () => _push(context, const UserPersonaPage()),
            ),
            // 评测与认知档案（用户评测板块设计文档 v1.0）：本地任务测能力，结果
            // 写进 cog_* 八表；属于"学习/能力"而不是开发者工具。
            SettingsNavTile(
              tileKey: settingsAssessmentTileKey,
              icon: Icons.psychology_outlined,
              title: l10n.settingsAssessmentTitle,
              subtitle: l10n.settingsAssessmentHint,
              onTap: () => _push(context, const AssessmentCenterPage()),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 3. AI
  // ---------------------------------------------------------------------------

  Widget _aiSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(
          key: settingsSectionAiKey,
          icon: Icons.smart_toy_outlined,
          title: l10n.settingsSectionAi,
        ),
        SettingsSectionCard(
          children: [
            // 普通用户只需要模型 / API / 权限：这三样都在 AiSettingsPage 的第一屏。
            // 轮次上限、可用工具清单、技能包（.fskill）属于开发者参数，在那一页
            // 默认折叠，不混进这一行。
            SettingsNavTile(
              tileKey: settingsAiTileKey,
              icon: Icons.smart_toy_outlined,
              title: l10n.settingsAiSection,
              subtitle: l10n.settingsAiApiKeyHint,
              onTap: () => _push(context, const AiSettingsPage()),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 4. 外观与阅读
  // ---------------------------------------------------------------------------

  Widget _appearanceReadingSection(
    AppLocalizations l10n,
    SettingsState settings,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(
          key: settingsSectionAppearanceReadingKey,
          icon: Icons.palette_outlined,
          title: l10n.settingsSectionAppearanceReading,
        ),
        SettingsSectionCard(
          children: [
            SettingsNavTile(
              tileKey: settingsLanguageTileKey,
              icon: Icons.language,
              title: l10n.settingsLanguage,
              subtitle: _languageLabel(l10n, settings.language),
              onTap: () => _pickLanguage(context),
            ),
            // 主题（跟随系统/主题文档/导入）+「Markdown 排版」入口。
            // Markdown 页面与入口行由 task-104 提供，这里只挂在同一分区里，
            // 不重复实现 Markdown 主题。
            const AppearanceSection(showHeader: false),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 5. 数据
  // ---------------------------------------------------------------------------

  Widget _dataSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(
          key: settingsSectionDataKey,
          icon: Icons.folder_outlined,
          title: l10n.settingsData,
        ),
        SettingsSectionCard(
          children: [
            // 一个入口组：备份与恢复（.tfpkg 导出/导入）+ 题库包（.tqb）+
            // 学习数据 + 知识库，全部在同一张卡里；诊断包在开发者分区。
            const DataSection(showHeader: false),
            // 数据位置：本机数据目录，点按复制。放在数据区，而不是只写在关于页。
            const SettingsDataLocationTile(),
            // 知识库（.kpak）管理：已导入知识包的启用/禁用/卸载/导入导出；
            // 它不再是顶层目的地（决策记录 D7），设置页是唯一入口。
            SettingsNavTile(
              tileKey: settingsKnowledgeLibraryTileKey,
              icon: Icons.library_books_outlined,
              title: l10n.settingsKnowledgeLibrary,
              subtitle: l10n.settingsKnowledgeLibraryHint,
              onTap: () => _push(context, const PackagesPage()),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 6. 帮助
  // ---------------------------------------------------------------------------

  Widget _helpSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(
          key: settingsSectionHelpKey,
          icon: Icons.help_outline,
          title: l10n.settingsSectionHelp,
        ),
        SettingsSectionCard(
          children: [
            SettingsNavTile(
              tileKey: settingsUsageDocTileKey,
              icon: Icons.menu_book_outlined,
              title: l10n.settingsUsageDoc,
              subtitle: l10n.settingsUsageDocHint,
              onTap: () => _push(context, const UsageDocPage()),
            ),
            // 版本、开源许可与反馈链接都在这一页；数据位置在数据分区。
            SettingsNavTile(
              tileKey: settingsAboutTileKey,
              icon: Icons.info_outline,
              title: l10n.settingsAbout,
              subtitle: l10n.settingsAboutHint,
              onTap: () => _push(context, const AboutPage()),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 7. 开发者（默认折叠）
  // ---------------------------------------------------------------------------

  Widget _developerSection(
    AppLocalizations l10n,
    PresetSelection? presetSelection,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(
          key: settingsSectionDeveloperKey,
          icon: Icons.build_outlined,
          title: l10n.settingsSectionDeveloper,
          trailing: TextButton.icon(
            key: settingsDeveloperToggleKey,
            onPressed: () => setState(
              () => _developerExpanded = !_developerExpanded,
            ),
            icon: Icon(
              _developerExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            label: Text(
              _developerExpanded
                  ? l10n.settingsDeveloperHide
                  : l10n.settingsDeveloperShow,
            ),
          ),
        ),
        if (!_developerExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              l10n.settingsDeveloperHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (_developerExpanded)
          SettingsSectionCard(
            children: [
              // 开发者信息（task-103）：模型 id、R0/Gain/Σ、band/zone 等原始读数。
              SettingsNavTile(
                tileKey: settingsCognitiveDeveloperTileKey,
                icon: Icons.build_outlined,
                title: l10n.mindnetDeveloperInfo,
                subtitle: l10n.mindnetDeveloperInfoHint,
                onTap: () => _push(context, const CognitiveDeveloperPage()),
              ),
              // 设计/内容板块的只读入口（通宵 task-25）：内容来自本地 asset。
              SettingsNavTile(
                tileKey: settingsDesignBoardTileKey,
                icon: Icons.dashboard_customize_outlined,
                title: '设计与内容板块',
                subtitle: 'FURNACE 设计参考库、内容 schema、能力矩阵状态（只读）',
                onTap: () => _push(context, const DesignBoardPage()),
              ),
              // 高考资源库：只读索引（高考真题、试题分析、专题资料）。第二遍清理
              // 把学生资料入口的理想位置定在「题库」模块，设置里只保留开发者
              // 入口，避免普通设置列表被资料库占一行。
              SettingsNavTile(
                tileKey: settingsHighSchoolLibraryTileKey,
                icon: Icons.school_outlined,
                title: '高考资源库',
                subtitle: '高考真题、试题分析、专题资料；只读索引',
                onTap: () => _push(context, const GaokaoLibraryPage()),
              ),
              // 诊断包（D01）：排障用的打包导出，不是日常备份。第二遍清理把它
              // 从「数据」移到开发者，用户数据区只留备份/恢复这一类。
              SettingsNavTile(
                tileKey: settingsDiagnosticsTileKey,
                icon: Icons.monitor_heart_outlined,
                title: l10n.settingsDiagnosticExport,
                subtitle: l10n.settingsDiagnosticExportHint,
                onTap: () => _push(context, const DiagnosticsBundlePage()),
              ),
              // 预设选择（task-64 原型）：只读本地 asset + 内存选择。
              SettingsNavTile(
                tileKey: settingsPresetSelectTileKey,
                icon: Icons.tune_outlined,
                title: '预设选择（原型）',
                subtitle: presetSelection == null
                    ? '4 档预设 × 3 题小样；诊断用，非高考分'
                    : '已选：${presetSelection.presetName}（内存，可随时改选）',
                onTap: () => _push(context, const PresetSelectPage()),
              ),
              // 示例数据：一次性生成示例标签/闪存卡/事件/日程，动作行（不导航）。
              ListTile(
                key: settingsDemoDataTileKey,
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(l10n.settingsDemoData),
                subtitle: Text(l10n.settingsDemoDataHint),
                onTap: () => _loadDemoData(context, ref),
              ),
              // 能力动作词表（task-29）：内置动作只读，自定义动作下一次解题生效。
              SettingsNavTile(
                icon: Icons.account_tree_outlined,
                title: l10n.capabilityVocabularySettingsTitle,
                subtitle: l10n.capabilityVocabularySettingsHint,
                onTap: () => _push(context, const CapabilityVocabularyPage()),
              ),
            ],
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 共用动作
  // ---------------------------------------------------------------------------

  /// 统一的子页跳转（所有入口都是 `MaterialPageRoute`，不经过命名路由）。
  static void _push(BuildContext context, Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (context) => page),
    );
  }

  String _languageLabel(AppLocalizations l10n, AppLanguage language) {
    return switch (language) {
      AppLanguage.system => l10n.settingsLanguageSystem,
      AppLanguage.zh => l10n.settingsLanguageZh,
      AppLanguage.en => l10n.settingsLanguageEn,
    };
  }

  /// One-shot demo workspace so the UI can be reviewed without manual typing.
  Future<void> _loadDemoData(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(demoDataServiceProvider);

    if (await service.hasExistingData()) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsDemoDataBlocked)),
      );
      return;
    }
    if (!context.mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsDemoData),
        content: Text(l10n.settingsDemoDataConfirm),
        actions: [
          IconButton(
            tooltip: l10n.commonCancel,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          IconButton.filled(
            tooltip: l10n.commonConfirm,
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await service.seed();
    // Every module reads its own provider, so refresh them all.
    ref.invalidate(allTagsProvider);
    ref.invalidate(timeBlocksProvider);
    ref.invalidate(calendarBlocksProvider);
    ref.invalidate(threadFeedProvider);
    ref.invalidate(threadStateProvider);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.settingsDemoDataDone)),
    );
  }

  Future<void> _pickLanguage(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showDialog<AppLanguage>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.settingsLanguage),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, AppLanguage.system),
            child: Text(l10n.settingsLanguageSystem),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, AppLanguage.zh),
            child: Text(l10n.settingsLanguageZh),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, AppLanguage.en),
            child: Text(l10n.settingsLanguageEn),
          ),
        ],
      ),
    );
    if (choice != null) {
      ref.read(settingsControllerProvider.notifier).setLanguage(choice);
    }
  }
}
