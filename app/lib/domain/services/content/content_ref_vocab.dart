/// `content_refs` 的词表（schema v47，2026-11-15）。
///
/// 契约：`INTEGRATION-CONTRACT-2026-11-15.md` §2.2 / §2.4。
///
/// 两条边界：
///  * `content_refs` 只存"内容 id ↔ 产品对象"的引用，**不复制正文**（没有
///    题干/答案/解析/DAG 文本字段）。
///  * 产品对象的本地 id（`task-…` / `q-…` / `kp-…` / `tpl-…`）**禁止**写回内容
///    包；跨设备只认 C 层 `content_id`。
library;

/// `content_refs.object_type` 的固定词表（产品对象类型）。
abstract final class ContentObjectType {
  /// Thread 节点（`tasks.id`）。
  static const String task = 'task';

  /// 题库题目（`questions.id`）。
  static const String question = 'question';

  /// 产品知识点（`knowledge_points.id`）。
  static const String knowledgePoint = 'knowledge_point';

  /// 内容卡模板（`card_templates.id`）。
  static const String cardTemplate = 'card_template';

  static const Set<String> values = {
    task,
    question,
    knowledgePoint,
    cardTemplate,
  };
}

/// `content_refs.role` 的固定词表：同一产品对象上"这条引用是干什么的"。
abstract final class ContentRefRole {
  /// 计划节点指向内容来源包/套卷（`QSET-…`）。
  static const String sourcePackage = 'source_package';

  /// 练习节点指向卷内某道题（`Q-…`）。
  static const String paperItem = 'paper_item';

  /// 产品知识点指向内容知识节点（`kp-…`）。
  static const String node = 'node';

  /// 产品对象指向 Thinking DAG 的某个节点（`N-…`）。
  static const String dagNode = 'dag_node';

  /// 卡片指向它的内容种子（DAG 节点 / 错因）。
  static const String cardSeed = 'card_seed';

  /// 分析与渲染引用的证据对象（`E-…` / 题眼 / 陷阱）。
  static const String analysisRef = 'analysis_ref';

  static const Set<String> values = {
    sourcePackage,
    paperItem,
    node,
    dagNode,
    cardSeed,
    analysisRef,
  };
}
