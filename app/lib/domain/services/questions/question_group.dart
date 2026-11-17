/// 题组识别（纯逻辑，不碰 DB / Flutter）：一篇文章 + 若干小问在库里是**多行**
/// `questions`，整卷导入把材料原文内联进每个小问的 stem（`【材料 Sx-Mx】…` 后接
/// `\n\n【题目】\n` 再写小问题干）。这里只从 stem + `source_label` 推导组键，
/// 不改表、不读库：读表层（`question_library_reader.dart` /
/// `question_corpus_reader.dart`）拿它把 N 行折成一道题，列表与组卷按**合题**
/// 计数（用户口径：英语阅读 A 篇 = 文章 + 3 小问 = 1 道题；语文现代文阅读 II =
/// 文章 + 2 选择 + 2 解答 = 1 道题）。
///
/// 三条判据（都不是猜测，全部来自导入器 `exam_paper_question_importer.dart`
/// 的 `_assembleStem` 拼法）：
///
/// 1. **必须从材料标题开头**：`stem` 去掉首尾空白后以 `【材料 …】` 起头；没有这个
///    前缀的题保持独立（手工题、单题、其它学科题都不受影响）。
/// 2. **同一 `source_label`**：组键里带来源标签；两份不同卷子的 `S1-M1` 不会
///    合成一组。来源标签为空时**不建组**（宁可不折，也不把不相干的题并掉）。
/// 3. **同组材料必须一致**：
///    * 有 `【题目】` 分隔（整卷导入的真实形态）时，组键取「材料标题 + 材料全文」，
///      多材料（`material_ids: [S1-M1, S1-M2]`）也能区分——只认同 `S1-M1` 但第二份
///      材料不同的两组不会被误并；
///    * 老数据没有 `【题目】` 分隔时退一步只用**首个材料标题**做组键（无法可靠切出
///      材料正文的边界；这是有意的保守退路，见交付说明）。
library;

/// `stem` 开头的材料标题：`【材料 S1-M1】` / `【材料一】`（允许标题内有空白）。
final RegExp _leadingMaterialMarker = RegExp(r'^【材料\s*([^】\n]*?)\s*】');

/// 整卷导入在材料与题干之间写的分隔行（`\n\n【题目】\n`）。
final RegExp _questionSectionMarker = RegExp(r'\n[ \t]*【题目】[ \t]*\n');

/// 组键里区分「材料全文」与「仅材料标题」两种口径的前缀。
const String _materialKeyPrefix = 'material';
const String _markerKeyPrefix = 'marker';

/// 一道题的题组签名。
class QuestionGroupSignature {
  const QuestionGroupSignature({
    required this.groupKey,
    required this.label,
    this.material,
  });

  /// 组键：同一篇文章的每个小问拿到的都是同一个值；独立题为 null。
  ///
  /// 形如 `<source_label>\u0001material\u0001<材料全文>`（旧数据是
  /// `<source_label>\u0001marker\u0001<材料标题>`）。分隔符用不可见的 `\u0001`，
  /// 避免题面里恰好出现普通分隔符造成碰撞。
  final String groupKey;

  /// 组的中文标签（`材料 S1-M1`），列表卡显示用。
  final String label;

  /// 材料全文（含 `【材料 …】` 标题行，不含 `【题目】` 之后的小问题干）。
  ///
  /// 旧数据没有 `【题目】` 分隔时无法可靠切出边界，为 null；此时列表卡回落到
  /// 代表题的题干摘要，不硬拼一个可能把小问也算进去的「材料」。
  final String? material;

  @override
  String toString() => 'QuestionGroupSignature($label, $groupKey)';
}

/// 推导一道题的题组签名；不是题组（没有材料前缀 / 来源标签为空）时返回 null。
///
/// 纯函数：同一对 `stem` + `sourceLabel` 永远得到同一个签名，不依赖时间/随机数。
QuestionGroupSignature? questionGroupSignatureOf({
  required String stem,
  required String sourceLabel,
}) {
  final source = sourceLabel.trim();
  if (source.isEmpty) {
    return null;
  }
  final text = stem.trim();
  if (text.isEmpty) {
    return null;
  }
  final marker = _leadingMaterialMarker.firstMatch(text);
  if (marker == null) {
    return null;
  }
  final markerId = (marker.group(1) ?? '').trim();
  if (markerId.isEmpty) {
    return null;
  }

  final questionSection = _questionSectionMarker.firstMatch(text);
  if (questionSection != null) {
    final material = text.substring(0, questionSection.start).trim();
    if (material.isEmpty) {
      // 有分隔行却没有材料正文：不建组（残缺数据不猜）。
      return null;
    }
    return QuestionGroupSignature(
      groupKey: '$source\u0001$_materialKeyPrefix\u0001'
          '${_normalizeMaterial(material)}',
      label: '材料 $markerId',
      material: material,
    );
  }

  // 旧数据（材料直接拼小问题干、没有【题目】分隔）：只能按首个材料标题归组。
  return QuestionGroupSignature(
    groupKey: '$source\u0001$_markerKeyPrefix\u0001$markerId',
    label: '材料 $markerId',
  );
}

/// 组内一行的题面拆分结果：材料原文（含 `【材料 …】` 标题行）+ 小问题干。
class QuestionGroupStemParts {
  const QuestionGroupStemParts(
      {required this.material, required this.question});

  /// 材料原文（含 `【材料 …】` 标题行，不含 `【题目】` 分隔行）。
  final String material;

  /// 小问题干（`【题目】` 之后的部分）。
  final String question;
}

/// 把「材料 + 【题目】 + 小问」的整卷导入题面拆成材料与小问题干。
///
/// 组卷卷面要"材料只出现一次、小问连续排"，所以导出层必须先切：本函数与
/// [questionGroupSignatureOf] 用同一套判据（同一个 `【题目】` 分隔行）。
/// 不是题组 / 旧数据没有分隔行时返回 null——调用方**不要猜**，回落到代表题整段
/// 渲染，并把"未展开"写进导出提示。
QuestionGroupStemParts? splitQuestionGroupStem(String stem) {
  final text = stem.trim();
  if (text.isEmpty) return null;
  if (_leadingMaterialMarker.firstMatch(text) == null) return null;
  final section = _questionSectionMarker.firstMatch(text);
  if (section == null) return null;
  final material = text.substring(0, section.start).trim();
  final question = text.substring(section.end).trim();
  if (material.isEmpty || question.isEmpty) return null;
  return QuestionGroupStemParts(material: material, question: question);
}

/// 材料全文的归一化（只收拾行尾空白与整体首尾空白）。
///
/// 不做更激进的空白折叠：同一份整卷导入写出的材料逐字相同，归一化只是为了容忍
/// 「行尾多一个空格」这类无意义差异，不该把有意义的空行/缩进改掉。
String _normalizeMaterial(String material) {
  final lines = <String>[
    for (final line in material.split('\n')) line.trimRight(),
  ];
  return lines.join('\n').trim();
}
