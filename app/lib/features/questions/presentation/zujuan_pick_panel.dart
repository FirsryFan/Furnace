/// 收题页「定点找题」面板：把筛选条件拼成组卷网列表页链接（不联网、不抓页面）。
///
/// 为什么只复制链接、不直接打开：仓库没有 url_launcher 依赖（详情页的组卷网入口
/// 同一个取舍），而且组卷网按站点当前学科过滤——用户得先确认网站上的学科。
///
/// 链接规则全在域层 `zujuan_query.dart`；本文件只做三件事：
///  1. 表单学科 → 面板默认学科（认不出就数学，见 [zujuanPickDefaultSubject]）；
///  2. 下拉框取值 → [ZujuanQuerySpec]（非法值交给域层忽略）；
///  3. 画面板、复制链接。
///
/// 本切片不做题型 / 学期 / 页码：题型 id 是逐学科词表（见
/// `ZujuanSubject.questionTypeIds`），做成下拉要多一层学科联动；页码固定第 1 页；
/// 学期同理。写进注释，免得以后误以为漏掉了。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/services/zujuan/zujuan_query.dart';
import '../../../l10n/app_localizations.dart';

/// 收题页表单里的「定点找题」入口按钮。
const Key zujuanPickOpenButtonKey = Key('zujuan-pick-open');

/// 面板根（测试用来确认打开 / 关闭）。
const Key zujuanPickSheetKey = Key('zujuan-pick-sheet');
const Key zujuanPickSubjectFieldKey = Key('zujuan-pick-subject');
const Key zujuanPickKnowledgePointFieldKey = Key('zujuan-pick-knowledge-point');
const Key zujuanPickDifficultyFieldKey = Key('zujuan-pick-difficulty');
const Key zujuanPickYearFieldKey = Key('zujuan-pick-year');
const Key zujuanPickProvinceFieldKey = Key('zujuan-pick-province');
const Key zujuanPickGradeFieldKey = Key('zujuan-pick-grade');
const Key zujuanPickSortFieldKey = Key('zujuan-pick-sort');
const Key zujuanPickUrlKey = Key('zujuan-pick-url');
const Key zujuanPickCopyKey = Key('zujuan-pick-copy');

/// 组卷网六个学科的中文名（与站点列表页一致）。
///
/// 只有六个：历史 / 信息学 / 强基在组卷网没有列表页（域层 [zujuanSubjectFor]
/// 对它们返回 null）。学科名沿用中文、不做英文翻译——站点本身只有中文，面板里
/// 出现英文名反而对不上网站筛选面板。
const Map<ZujuanSubject, String> zujuanSubjectLabelsZh =
    <ZujuanSubject, String>{
  ZujuanSubject.chinese: '语文',
  ZujuanSubject.math: '数学',
  ZujuanSubject.english: '英语',
  ZujuanSubject.physics: '物理',
  ZujuanSubject.chemistry: '化学',
  ZujuanSubject.biology: '生物',
};

/// 学科中文名；未知学科回退站点 path（六科枚举之外不会发生）。
String zujuanSubjectLabel(ZujuanSubject subject) =>
    zujuanSubjectLabelsZh[subject] ?? subject.path;

/// 表单的学科键 → 面板默认学科；认不出（空 / 历史 / 信息学 / 强基）回退数学。
ZujuanSubject zujuanPickDefaultSubject(String? formSubjectKey) =>
    zujuanSubjectFor(formSubjectKey ?? '') ?? ZujuanSubject.math;

/// 年份下拉的候选：今年 +1 起往回 [count] 个（2026 年看到 2027…2020）。
///
/// 「更早以前」用 -1 表示（域层的 y-1 段），不在这个列表里，由 UI 单独加一项。
List<int> zujuanPickYearOptions({int? currentYear, int count = 8}) {
  final year = currentYear ?? DateTime.now().year;
  return <int>[for (var i = 0; i < count; i++) year + 1 - i];
}

/// 省份名 → 6 位行政区码串；未知 / 空回退 null（不拼坏段）。
String? zujuanPickProvinceCode(String? provinceName) {
  final name = provinceName?.trim() ?? '';
  if (name.isEmpty) return null;
  final code = zujuanProvinceCodes[name];
  return code == null ? null : '$code';
}

/// 把面板上的取值装进 [ZujuanQuerySpec]。
///
/// 空 / 未知取值一律交给域层忽略；知识点 id 非法时域层回退学科根节点，所以只要
/// 有学科就一定能拼出一个可打开的链接。
ZujuanQuerySpec zujuanPickSpec({
  required ZujuanSubject subject,
  String knowledgePointId = '',
  ZujuanDifficulty? difficulty,
  int? year,
  String? provinceName,
  int? grade,
  ZujuanSort? sort,
}) =>
    ZujuanQuerySpec(
      subject: subject,
      knowledgePointId: knowledgePointId,
      difficulty: difficulty,
      year: year,
      provinceCode: zujuanPickProvinceCode(provinceName),
      grade: grade,
      sort: sort,
    );

/// 面板当前条件对应的列表页链接。
String zujuanPickUrlFor(ZujuanQuerySpec spec) => zujuanFilteredSearchUrl(spec);

/// 打开「定点找题」底部面板。
///
/// [initialSubjectKey] 是收题表单当前的学科键（可能为 null / 历史 / 信息学），
/// 面板自己决定默认学科（见 [zujuanPickDefaultSubject]）。
Future<void> showZujuanPickPanel(
  BuildContext context, {
  required AppLocalizations l10n,
  String? initialSubjectKey,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _ZujuanPickSheet(
      l10n: l10n,
      initialSubjectKey: initialSubjectKey,
    ),
  );
}

class _ZujuanPickSheet extends StatefulWidget {
  const _ZujuanPickSheet({required this.l10n, this.initialSubjectKey});

  final AppLocalizations l10n;
  final String? initialSubjectKey;

  @override
  State<_ZujuanPickSheet> createState() => _ZujuanPickSheetState();
}

class _ZujuanPickSheetState extends State<_ZujuanPickSheet> {
  late ZujuanSubject _subject;
  final _knowledgePointController = TextEditingController();

  /// 下拉框用的原始取值：'any' / 'easy' / 'medium' / 'hard'。
  ///
  /// 不用可空枚举是因为 DropdownButton 选中 null 时显示的是 hint 而不是
  /// 「不限」这一项，回显会丢。
  String _difficultyValue = 'any';

  /// 0 = 不限；-1 = 更早以前；其余是年份。
  int _yearValue = 0;

  /// 空串 = 不限；其余是省名。
  String _provinceValue = '';

  /// 0 = 不限；10/11/12 = 高一/高二/高三。
  int _gradeValue = 0;
  ZujuanSort _sort = ZujuanSort.comprehensive;

  @override
  void initState() {
    super.initState();
    _subject = zujuanPickDefaultSubject(widget.initialSubjectKey);
    _knowledgePointController.addListener(_onKnowledgePointChanged);
  }

  @override
  void dispose() {
    _knowledgePointController
      ..removeListener(_onKnowledgePointChanged)
      ..dispose();
    super.dispose();
  }

  void _onKnowledgePointChanged() => setState(() {});

  ZujuanDifficulty? get _difficulty => switch (_difficultyValue) {
        'easy' => ZujuanDifficulty.easy,
        'medium' => ZujuanDifficulty.medium,
        'hard' => ZujuanDifficulty.hard,
        _ => null,
      };

  ZujuanQuerySpec get _spec => zujuanPickSpec(
        subject: _subject,
        knowledgePointId: _knowledgePointController.text,
        difficulty: _difficulty,
        year: _yearValue == 0 ? null : _yearValue,
        provinceName: _provinceValue.isEmpty ? null : _provinceValue,
        grade: _gradeValue == 0 ? null : _gradeValue,
        sort: _sort,
      );

  String get _url => zujuanPickUrlFor(_spec);

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.of(context);
    // 顺序照 `question_zujuan_search.dart`：先写剪贴板，再关面板，最后提示。
    await Clipboard.setData(ClipboardData(text: _url));
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(content: Text(widget.l10n.zujuanPickCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    final yearOptions = zujuanPickYearOptions();
    return SafeArea(
      key: zujuanPickSheetKey,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        children: [
          Text(l10n.zujuanPickTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(l10n.zujuanPickIntro, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          DropdownButtonFormField<ZujuanSubject>(
            key: zujuanPickSubjectFieldKey,
            initialValue: _subject,
            decoration: InputDecoration(
              labelText: l10n.zujuanPickSubject,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final subject in ZujuanSubject.values)
                DropdownMenuItem<ZujuanSubject>(
                  value: subject,
                  child: Text(zujuanSubjectLabel(subject)),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _subject = value);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            key: zujuanPickKnowledgePointFieldKey,
            controller: _knowledgePointController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.zujuanPickKnowledgePoint,
              hintText: l10n.zujuanPickKnowledgePointHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: zujuanPickDifficultyFieldKey,
                  initialValue: _difficultyValue,
                  decoration: InputDecoration(
                    labelText: l10n.zujuanPickDifficulty,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem<String>(
                      value: 'any',
                      child: Text(l10n.zujuanPickAny),
                    ),
                    for (final difficulty in ZujuanDifficulty.values)
                      DropdownMenuItem<String>(
                        value: difficulty.name,
                        child: Text(difficulty.labelZh),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _difficultyValue = value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: zujuanPickYearFieldKey,
                  initialValue: _yearValue,
                  decoration: InputDecoration(
                    labelText: l10n.zujuanPickYear,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem<int>(
                      value: 0,
                      child: Text(l10n.zujuanPickAny),
                    ),
                    DropdownMenuItem<int>(
                      value: -1,
                      child: Text(l10n.zujuanPickYearEarlier),
                    ),
                    for (final year in yearOptions)
                      DropdownMenuItem<int>(
                        value: year,
                        child: Text('$year'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _yearValue = value);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: zujuanPickProvinceFieldKey,
                  initialValue: _provinceValue,
                  decoration: InputDecoration(
                    labelText: l10n.zujuanPickProvince,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem<String>(
                      value: '',
                      child: Text(l10n.zujuanPickAny),
                    ),
                    for (final province in zujuanProvinceNames)
                      DropdownMenuItem<String>(
                        value: province,
                        child: Text(province),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _provinceValue = value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: zujuanPickGradeFieldKey,
                  initialValue: _gradeValue,
                  decoration: InputDecoration(
                    labelText: l10n.zujuanPickGrade,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem<int>(
                      value: 0,
                      child: Text(l10n.zujuanPickAny),
                    ),
                    DropdownMenuItem<int>(
                      value: 10,
                      child: Text(l10n.zujuanPickGradeSenior1),
                    ),
                    DropdownMenuItem<int>(
                      value: 11,
                      child: Text(l10n.zujuanPickGradeSenior2),
                    ),
                    DropdownMenuItem<int>(
                      value: 12,
                      child: Text(l10n.zujuanPickGradeSenior3),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _gradeValue = value);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ZujuanSort>(
            key: zujuanPickSortFieldKey,
            initialValue: _sort,
            decoration: InputDecoration(
              labelText: l10n.zujuanPickSort,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final sort in ZujuanSort.values)
                DropdownMenuItem<ZujuanSort>(
                  value: sort,
                  child: Text(sort.labelZh),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _sort = value);
              }
            },
          ),
          const SizedBox(height: 16),
          Text(l10n.zujuanPickUrl, style: theme.textTheme.labelSmall),
          const SizedBox(height: 4),
          SelectableText(_url, key: zujuanPickUrlKey),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.zujuanPickNoScrapeHint),
                  const SizedBox(height: 8),
                  Text(l10n.zujuanPickLoginHint),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonClose),
              ),
              const Spacer(),
              FilledButton.icon(
                key: zujuanPickCopyKey,
                onPressed: _copy,
                icon: const Icon(Icons.link),
                label: Text(l10n.zujuanPickCopy),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
