/// 组卷网（zujuan.xkw.com）列表页「定点找题」链接：纯逻辑（不联网、不读 DB、不碰 UI）。
///
/// 规则唯一权威：D:/dsh-data/skills/zujuan-source-standards/references/url-grammar.md
/// （§2 列表页结构、§3 题型 ID 与知识点根节点、§4 省份码）。本文件所有取值都抄自
/// 那份实测文档，不凭记忆猜。文档开头已声明：这些是实测记录、不是永久契约，
/// 站点改版后要重新从列表页按钮的 data-href 读（url-grammar.md:3）。
///
/// 链接形状（url-grammar.md:25-35）：
///
///     https://zujuan.xkw.com/<学科path>/zsd<知识点id>/<筛选段拼接>/
///
/// 筛选段**直接拼接、无分隔符**，顺序固定：
/// d(难度) → qt(题型) → fl(分类) → x(只看新题) → y(年份) → a(省份) →
/// g(年级) → te(学期) → o(排序) → p(页码)。
///
/// 页码段紧跟排序段之后、**不加斜杠**（url-grammar.md:52-61）：
/// 正确 /gzyw/zsd23177/a370000o1p2/，错误 /gzyw/zsd23177/a370000o1/p2/（实测 404）；
/// 第 1 页省略 p，第 2 页起拼 p<n>。
///
/// 边界：本文件只拼「用户可在浏览器里手动打开的链接」，不做网络请求、不解析页面、
/// 不判断题库里有没有题。站点按 bankId cookie 过滤学科，链接带对学科 path 只是
/// 必要条件，用户仍要确认站点当前学科（zujuan_link.dart 的 library doc 记录过
/// 连搜 19 条全部 0 结果的事故）。
library;

import 'zujuan_link.dart' show zujuanBaseUrl;

/// 可定点找题的六个学科（url-grammar.md:79-99）。
///
/// [zujuanSubjectFor] 接受两类写法：仓库学科键（math / physics / chemistry /
/// biology / chinese / english）与站点 path（gzsx / gzwl / gzhx / gzsw / gzyw /
/// gzyy）；中文名不在接口范围内（返回 null，不猜）。
///
/// 说明：仓库的八轨道词表（capability_action.dart:68-77）里没有 english 轨道，
/// 但组卷网有英语列表页（gzyy，url-grammar.md:83），所以这里保留英语映射；
/// history / informatics / qiangji 在组卷网没有对应学科，解析返回 null。
enum ZujuanSubject {
  chinese(
    path: 'gzyw',
    rootKnowledgePointId: '23177',
    questionTypeIds: <int, String>{
      2602: '现代文阅读',
      2611: '语言文字运用',
      2603: '文言文阅读',
      2605: '古代诗歌阅读',
      2604: '名篇名句默写',
      2608: '作文题',
      2618: '整本书阅读',
      2613: '判断题',
    },
  ),
  math(
    path: 'gzsx',
    rootKnowledgePointId: '27925',
    questionTypeIds: <int, String>{
      2701: '单选',
      2704: '多选',
      2702: '填空',
      2703: '解答',
      2706: '判断',
      2707: '概念填空',
    },
  ),
  english(
    path: 'gzyy',
    rootKnowledgePointId: '29978',
    questionTypeIds: <int, String>{
      2801: '听力选择',
      2802: '听力填空',
      2803: '单项选择',
      2809: '阅读理解',
      2808: '完形填空',
      2813: '语法填空',
      2806: '改错',
      2818: '选词填空',
      2807: '翻译',
      2805: '完成句子',
      2804: '单词拼写',
      2812: '短文填空',
      2814: '书面表达',
      2823: '书信写作',
    },
  ),
  physics(
    path: 'gzwl',
    rootKnowledgePointId: '41934',
    questionTypeIds: <int, String>{
      2901: '单选',
      2908: '多选',
      2902: '填空',
      2903: '实验',
      2904: '解答',
      2909: '综合',
      2907: '判断',
      2905: '作图',
      2906: '知识点填空',
    },
  ),
  chemistry(
    path: 'gzhx',
    rootKnowledgePointId: '43452',
    questionTypeIds: <int, String>{
      3011: '单选',
      3012: '多选',
      3003: '填空',
      3010: '判断',
      3005: '计算',
      3009: '解答',
      3013: '综合',
    },
  ),
  biology(
    path: 'gzsw',
    rootKnowledgePointId: '44886',
    questionTypeIds: <int, String>{
      310101: '单选',
      3103: '多选',
      3106: '解答',
      3107: '实验',
      3104: '判断',
      3105: '填空',
    },
  );

  const ZujuanSubject({
    required this.path,
    required this.rootKnowledgePointId,
    required this.questionTypeIds,
  });

  /// URL 里的学科段（如 gzsx、gzsw）；见 url-grammar.md:25-35、§3。
  final String path;

  /// 该学科知识树的根节点 id（"综合库"= 全量；url-grammar.md:90-99）。
  ///
  /// 只写数字，不带 zsd 前缀；拼链接时统一加 zsd。
  final String rootKnowledgePointId;

  /// 该学科的题型 id → 中文名（url-grammar.md:77-86）。
  ///
  /// 逐学科不同、不许照抄：同一个题型 id 在别的学科会静默 0 条。UI 的题型下拉
  /// 应该直接读这张表；[ZujuanQuerySpec.questionTypeId] 不在这张表里时会被忽略。
  final Map<int, String> questionTypeIds;
}

/// 把仓库学科键或站点 path 解析成 [ZujuanSubject]；认不出返回 null（不猜）。
///
/// 接受：math / physics / chemistry / biology / chinese / english（大小写不敏感、
/// 两端空白先 trim），以及 gzsx / gzwl / gzhx / gzsw / gzyw / gzyy。
/// 不接受中文名与 history / informatics / qiangji（组卷网没有对应列表页）。
ZujuanSubject? zujuanSubjectFor(String subjectKey) {
  final key = subjectKey.trim().toLowerCase();
  if (key.isEmpty) return null;
  for (final subject in ZujuanSubject.values) {
    if (subject.path == key) return subject;
  }
  switch (key) {
    case 'chinese':
      return ZujuanSubject.chinese;
    case 'math':
      return ZujuanSubject.math;
    case 'english':
      return ZujuanSubject.english;
    case 'physics':
      return ZujuanSubject.physics;
    case 'chemistry':
      return ZujuanSubject.chemistry;
    case 'biology':
      return ZujuanSubject.biology;
  }
  return null;
}

/// 组卷网难度段（url-grammar.md:41）：d1 容易 / d2 适中 / d3 困难。
enum ZujuanDifficulty {
  easy('d1', '容易'),
  medium('d2', '适中'),
  hard('d3', '困难');

  const ZujuanDifficulty(this.code, this.labelZh);

  /// URL 里的难度段（d1 / d2 / d3）。
  final String code;

  /// 与站点筛选面板同词的中文名。
  final String labelZh;
}

/// 组卷网排序段（url-grammar.md:49）：o0 综合 / o1 最热（推荐）/ o2 最新。
///
/// 推荐 [hot]：实测同一省份、同一天「最热」取回 7 个唯一出处，「最新」只有 3 个，
/// 且联盟卷不集中在 9 月发布（url-grammar.md:63-73）。
enum ZujuanSort {
  comprehensive('o0', '综合'),
  hot('o1', '最热（推荐）'),
  latest('o2', '最新');

  const ZujuanSort(this.code, this.labelZh);

  /// URL 里的排序段（o0 / o1 / o2）。
  final String code;

  /// 与站点筛选面板同词的中文名。
  final String labelZh;
}

/// 实测八省行政区码（url-grammar.md:118-131）。
///
/// 只是「已实测可用」的省份清单，供 UI 下拉与展示名用；[ZujuanQuerySpec.provinceCode]
/// 接受任意 6 位数字行政区码（站点支持的省份不止这 8 个，表外的码不校验存在性）。
const Map<String, int> zujuanProvinceCodes = <String, int>{
  '山东': 370000,
  '广东': 440000,
  '四川': 510000,
  '浙江': 330000,
  '陕西': 610000,
  '北京': 110000,
  '重庆': 500000,
  '上海': 310000,
};

/// 与 [zujuanProvinceCodes] 同序的省份名（UI 下拉用；测试钉住两表一致）。
const List<String> zujuanProvinceNames = <String>[
  '山东',
  '广东',
  '四川',
  '浙江',
  '陕西',
  '北京',
  '重庆',
  '上海',
];

/// 一次「定点找题」的筛选条件；可空字段表示该段不拼（= 站点默认全量）。
///
/// 非法/未知取值不会抛异常：拼链接时**忽略该段**（口径见 [zujuanFiltersOf]）。
class ZujuanQuerySpec {
  const ZujuanQuerySpec({
    required this.subject,
    this.knowledgePointId,
    this.difficulty,
    this.questionTypeId,
    this.classificationId,
    this.onlyNew = false,
    this.year,
    this.provinceCode,
    this.grade,
    this.semester,
    this.sort,
    this.page = 1,
  });

  /// 学科；决定 URL 的 path 段与可用题型 id 词表。
  final ZujuanSubject subject;

  /// 知识点树节点 id（纯数字，如 44886 或 43452）；null/非法时回退学科根节点。
  final String? knowledgePointId;

  /// 难度段；null = 不限。
  final ZujuanDifficulty? difficulty;

  /// 题型 id；必须在该学科 [ZujuanSubject.questionTypeIds] 表内，否则忽略该段。
  final int? questionTypeId;

  /// 分类 id（fl 段）：4081 典型题 / 4802 压轴题 / 3 同步题 / 4805 新文化等 /
  /// 4809 课本原题（url-grammar.md:43）；<= 0 忽略。
  final int? classificationId;

  /// 只看新题（x4，出现即生效；url-grammar.md:44）。
  final bool onlyNew;

  /// 年份段：-1 = 更早以前（y-1），否则拼 y<year>（如 y2025）。
  final int? year;

  /// 省份行政区码（a 段，6 位数字，如 370000）；不是 6 位数字时忽略。
  final String? provinceCode;

  /// 年级 g 段：10 高一 / 11 高二 / 12 高三（url-grammar.md:47）；其它值忽略。
  final int? grade;

  /// 学期 te 段：1 上 / 2 下（url-grammar.md:48）；其它值忽略。
  final int? semester;

  /// 排序段；null = 站点默认（综合）。
  final ZujuanSort? sort;

  /// 页码：第 1 页省略 p 段，第 2 页起拼 p<n>；< 1 当 1（url-grammar.md:50-61）。
  final int page;

  @override
  bool operator ==(Object other) =>
      other is ZujuanQuerySpec &&
      other.subject == subject &&
      other.knowledgePointId == knowledgePointId &&
      other.difficulty == difficulty &&
      other.questionTypeId == questionTypeId &&
      other.classificationId == classificationId &&
      other.onlyNew == onlyNew &&
      other.year == year &&
      other.provinceCode == provinceCode &&
      other.grade == grade &&
      other.semester == semester &&
      other.sort == sort &&
      other.page == page;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        subject,
        knowledgePointId,
        difficulty,
        questionTypeId,
        classificationId,
        onlyNew,
        year,
        provinceCode,
        grade,
        semester,
        sort,
        page,
      ]);

  @override
  String toString() => 'ZujuanQuerySpec(subject: $subject,'
      ' knowledgePointId: $knowledgePointId,'
      ' difficulty: $difficulty,'
      ' questionTypeId: $questionTypeId,'
      ' classificationId: $classificationId,'
      ' onlyNew: $onlyNew,'
      ' year: $year,'
      ' provinceCode: $provinceCode,'
      ' grade: $grade,'
      ' semester: $semester,'
      ' sort: $sort,'
      ' page: $page)';
}

/// 把 [spec] 拼成地址里那串「筛选段」（url-grammar.md:31-35）。
///
/// 按 d → qt → fl → x → y → a → g → te → o → p 顺序**直接拼接、无分隔符**；
/// 返回的串**含页码段 p**（第 1 页不拼），拼 URL 时整体接在知识点路径后、
/// 末尾再加一个斜杠（见 [zujuanFilteredSearchUrl]）。
///
/// 顺序按文档 §2 的 d → qt → … 排列；注意文档 §2 末尾的站点翻页按钮实例
/// /gzhx/zsd43452/qt3011d2o2p2/ 是用户点击顺序（qt 在 d 前），和 compile.mjs:5
/// 的实测 data-href 顺序（d2qt2703fl4081o2p2，d 在 qt 前）不同。两种顺序在站点
/// 是否等价没有实测过；生成侧统一按文档 §2 + compile.mjs:5 的顺序，不跟随点击顺序。
///
/// 空条件返回空串。非法/未知取值忽略对应段，不抛异常、也不拼坏段：
///  * 题型 id 必须在该学科 [ZujuanSubject.questionTypeIds] 表内（跨科 id 会让
///    站点静默 0 条，url-grammar.md:88）；
///  * 分类 id 必须 > 0；
///  * 年份只接受 -1（更早）或 1900..2999（防呆范围，不是站点契约）；
///  * 省份码必须是 6 位数字（不校验是否在这 8 个省里）；
///  * 年级只接受 10..12、学期只接受 1..2、页码 < 1 当 1。
String zujuanFiltersOf(ZujuanQuerySpec spec) {
  final segments = <String>[];
  final difficulty = spec.difficulty;
  if (difficulty != null) {
    segments.add(difficulty.code);
  }
  final questionTypeId = spec.questionTypeId;
  if (questionTypeId != null &&
      spec.subject.questionTypeIds.containsKey(questionTypeId)) {
    segments.add('qt$questionTypeId');
  }
  final classificationId = spec.classificationId;
  if (classificationId != null && classificationId > 0) {
    segments.add('fl$classificationId');
  }
  if (spec.onlyNew) {
    segments.add('x4');
  }
  final year = spec.year;
  if (year == -1) {
    segments.add('y-1');
  } else if (year != null && year >= _minYear && year <= _maxYear) {
    segments.add('y$year');
  }
  final provinceCode = _normalizeProvinceCode(spec.provinceCode);
  if (provinceCode != null) {
    segments.add('a$provinceCode');
  }
  final grade = spec.grade;
  if (grade != null && grade >= 10 && grade <= 12) {
    segments.add('g$grade');
  }
  final semester = spec.semester;
  if (semester != null && (semester == 1 || semester == 2)) {
    segments.add('te$semester');
  }
  final sort = spec.sort;
  if (sort != null) {
    segments.add(sort.code);
  }
  final page = spec.page < 1 ? 1 : spec.page;
  if (page > 1) {
    segments.add('p$page');
  }
  return segments.join();
}

/// 拼出列表页绝对链接：
///
///     https://zujuan.xkw.com/<学科path>/zsd<知识点id>/<筛选段>/
///
/// 知识点 id 非法/空白时回退该学科根节点（url-grammar.md:90-99），所以给了
/// [ZujuanQuerySpec.subject] 就一定能拼出链接；没有筛选段时只到
/// /<path>/zsd<id>/（与 [zujuanKnowledgePointUrl] 同形）。
String zujuanFilteredSearchUrl(ZujuanQuerySpec spec) {
  final base = _knowledgePointBaseUrl(spec.subject, spec.knowledgePointId);
  final filters = zujuanFiltersOf(spec);
  if (filters.isEmpty) return base;
  return '$base$filters/';
}

/// 只到知识点列表页、不带任何筛选段的链接：/<path>/zsd<id>/。
///
/// 返回类型按契约写成 String?，但实际**不会**返回 null：知识点 id 非法/空白时
/// 回退该学科根节点（根节点 = 综合库全量，url-grammar.md:90-99）。保留可空返回
/// 是为了和调用方「没有学科就不给链接」的判空习惯一致。
String? zujuanKnowledgePointUrl({
  required ZujuanSubject subject,
  String? knowledgePointId,
}) =>
    _knowledgePointBaseUrl(subject, knowledgePointId);

const int _minYear = 1900;
const int _maxYear = 2999;

final RegExp _digitsPattern = RegExp(r'^[0-9]+$');

/// 知识点路径：/<path>/zsd<id>/；id 非法/空白回退学科根节点。
String _knowledgePointBaseUrl(ZujuanSubject subject, String? knowledgePointId) {
  final id = _normalizeKnowledgePointId(knowledgePointId) ??
      subject.rootKnowledgePointId;
  final path = subject.path;
  return '$zujuanBaseUrl/$path/zsd$id/';
}

/// 知识点 id 归一：trim → 纯数字 → 正数（前导零去掉），否则 null。
///
/// 站点知识点 id 是纯数字（url-grammar.md:90-99）；带字母/负号/0 的串不是合法
/// 节点，回退根节点而不是拼一个必然 404 的路径。
String? _normalizeKnowledgePointId(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty || !_digitsPattern.hasMatch(trimmed)) return null;
  final value = int.tryParse(trimmed);
  if (value == null || value <= 0) return null;
  return value.toString();
}

/// 省份码归一：trim 后必须正好 6 位数字，否则 null（不拼坏段）。
String? _normalizeProvinceCode(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.length != 6 || !_digitsPattern.hasMatch(trimmed)) return null;
  return trimmed;
}
