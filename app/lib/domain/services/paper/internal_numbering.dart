/// 题单内部编号（不是 T 来源号）。
///
/// 用户规则：第 1 节第 3 题 = `1.3`；它的第 2 个变式 = `【变 1.3.2】`；
/// 第 2 个知识点 = `【知 1.3.2】`；该知识点第 1 个扩展题 = `【扩 1.3.2.1】`。
/// T 编号仍保留作来源定位，两者并存。
library;

import '../../../domain/services/paper/paper_composer.dart';

/// 题单内部原题号：按学科出现顺序分节，节内按题目顺序编号。
///
/// 目前题目没有章节元数据，所以"节"取该学科在卷内的出现顺序；这是当前唯一
/// 可从题目本身确定的层级，不伪造教材章节。
Map<String, String> assignInternalNumbers(List<PaperItem> items) {
  final sectionBySubject = <String, int>{};
  final countBySubject = <String, int>{};
  final result = <String, String>{};
  for (final item in items) {
    final subject = item.subjectKey.trim().isEmpty ? 'unknown' : item.subjectKey;
    final section = sectionBySubject.putIfAbsent(
      subject,
      () => sectionBySubject.length + 1,
    );
    final number = (countBySubject[subject] ?? 0) + 1;
    countBySubject[subject] = number;
    result[item.questionId] = '$section.$number';
  }
  return result;
}

String variantInternalNo(String originalNo, int index) => '【变 $originalNo.$index】';

String knowledgeInternalNo(String originalNo, int index) => '【知 $originalNo.$index】';

String expansionInternalNo(String knowledgeNo, int index) =>
    '【扩 $knowledgeNo.$index】';
