# 标定协议 v1（本地那一条）

`docs/REASONING_LAYER_DESIGN.md:236` 早就引用了这份文档（"`docs/CALIBRATION.md` 的协议还没跑过"），
但文件一直不存在。这份文档把它落地：**在本仓库有的数据上，能标什么、怎么标、什么时候必须拒绝给数**。

一句话口径：这一层只**检验**模型的预测（"你当时说的 R 准不准"），
**不写回任何参数**——`cognitive_priors.calibrated` 依然写 0（`assessment_repository.dart` 永远不写 1）。

## 1. 管什么 / 不管什么

| | 内容 |
| --- | --- |
| 管 | ① 估计量：二参数 logistic 重标定（全局偏置 `b`、斜率 `a`、标准误、显著性）；② 诚实规则：四种"不算"的结局；③ 接线：`calibration.dart` → `calibration_reader.dart` → 只读 AI 工具 `review_metrics`；④ 与 M6 的 Brier/ECE 的分工 |
| 不管 | ① MindNet 侧六个实验（`ls` / `W_DAR` / `β_goal` / `kappa_reach` / `T_ign` 等）——那批实验数据不在本仓库，协议在外部只读文档 `E:\Document\MindNet\docs\CALIBRATION.md`（`docs/MINDNET_ROADMAP.md:32`、`:82`）；② 把 `calibrated` 从 0 翻成 1（需要真实数据 + 显式动作）；③ 按知识点分别标定；④ 自动改模型参数 |

## 2. 样本从哪来（口径即验收）

- **预测必须在判分之前落库**：`app/lib/features/anki/application/review_service.dart:919-925` 在评分前
  算出 `predictedR`（取不到就 `NULL`，注释"M6: the prediction is written down *now*, while the
  outcome is still unknown to it"），经 `AnkiRepository.addReviewLog(predictedR: …)` 写进
  `review_logs.predicted_r`（v11 加的列，`tables.dart:385`）。
- **读取只用一条 SQL**：`AnkiRepository.retentionSamples()`（`anki_repository.dart:486-521`），
  `LEFT JOIN card_states`（孤儿日志也算一次真实复习），末尾 `withIntervals(...)` 补上"距上次复习几天"。
- **"没有预测"与"预测 0.5"是两件事**：老行 `NULL` = 没有预测，历史**不补算**——事后重算的 R 是拿
  复习后的状态给自己打分，那样的样本会让校准曲线失去意义。
- **"记得"的判定**：`recalledFromReview`（`learning_metrics.dart:24`）——客观判分 > FSRS ≥ Good >
  v1 旧评分 ≥"记住了"；`fuzzy` / `Hard` 都不算。

## 3. 估计量

对每条样本取 `x = logit(R)`、`y = 1/0`，拟合

```
p = σ(a·x + b)
```

`b`（截距）是**全局偏置**：`b > 0` ＝ 模型系统性低估自己（实际比预测更常记住），`b < 0` ＝ 过度自信。
`a`（斜率）是**离散度**：`a ≈ 1` 合适、`a < 1` 预测太平、`a > 1` 预测太极端。

- **求解**：解析梯度/信息矩阵上的牛顿迭代，起始点固定 `(a, b) = (1, 0)`，**没有随机初始化**（同输入必得同输出）。
- **带回溯**（`kMaxBacktrackingSteps = 40`）：纯牛顿步在"预测集中在两端、中间混着两类结果"时会来回
  过冲（中间箱的权重压倒两端，步长被放得极大），数据明明有有限的最大似然解却报"没收敛"。每一步先取
  牛顿方向，再二分回溯找第一个让对数似然真的变大的步长；走不动就当作没收敛。
- **收敛判据** `kGradientTolerance = 1e-7`：用 `1e-10` 时，迭代在已经到顶之后仍无法让似然"更大"
  （双精度平坦区在 `1e-13` 量级），最后会因为"走不动"而**误报**没收敛——这是本片真实修过的 bug。
- **`kLogitEpsilon = 1e-3`**：夹到 `1e-6` 会把 `logit` 推到 ±13.8，样本权重掉到 `1e-12` 量级，
  信息矩阵退化 → 用实现细节否掉真实样本。`1e-3` 等于把"完全确定"读成 99.9% / 0.1%：记忆预测本来
  就不该是完全确定的。
- **标准误**：从观测信息矩阵的逆取对角线开方；`biasZ = |b| / se(b)`，
  `kCalibrationSignificanceZ = 1.96`（双侧 95%）只用来**措辞**（"显著/不显著"），不用来决定给不给数。

门槛与守卫：

| 常量 | 值 | 为什么 |
| --- | --- | --- |
| `kMinCalibrationSamples` | 30 | 不来自论文，是"再多一条反例就能把结论翻过来"的规模；低于它就拒绝拟合 |
| `kMinSlopeSamplesForTrust` | 200 | 截距在 30 条就有意义，但区分"太极端/太平"需要更多样本；**仍然算 a**（截距的正确性依赖它），只是标成不可读 |
| `kMaxUsableCoefficientMagnitude` | 10.0 | 数据"几乎可分"时 MLE 不存在，系数会冲到几十上百 |
| `kMaxUsableStdError` | 10.0 | 同上，标准误一起冲高，`b=27±15000` 比"拒绝给数"坏得多 |

## 4. 五种结局（`CalibrationVerdict`）

| verdict | 条件 | 中文 | 给数吗 |
| --- | --- | --- | --- |
| `no_samples` | 一条带预测的样本都没有 | 还没有样本 | 不给（说明"v11 之前的复习没有这个值，也不补算"） |
| `too_few_samples` | `n < 30` | 样本不足 | 不给（理由里带实际条数与 30） |
| `single_class` | 全是"记得"或全是"忘记" | 只有一类结果 | 不给（似然没有有限最大值；理由点名缺哪一类） |
| `not_converged` | 牛顿/信息矩阵退化，或数据几乎可分 | 拟合没收敛 | 不给（"硬报一个系数就是在骗人"） |
| `ok` | 以上都不成立 | 可以看 | 给 `b`、`a`、标准误、显著性、对数似然、迭代次数 |

## 5. 为什么这么保守

- **"不算"是一个正当结论，不是错误**：摘要、`toJson().refusal`、AI 工具都会**原样**转达它。
- **"没跑"不等于"健康"**：没有预测样本时，任何"模型很准"的说法都是编的。
- **不给假精确**：与其报一个 `b = 27 ± 15000`，不如说"这批数据几乎可分，标定不了"。

## 6. 接线

| 文件 | 职责 |
| --- | --- |
| `app/lib/domain/services/cognitive/calibration.dart` | 纯逻辑：`CalibrationReport.read(samples:)` + 五种结局 + 回溯牛顿。无 DB / 无 Flutter / 无时钟 |
| `app/lib/features/cognitive/application/calibration_reader.dart` | `readCalibrationReading(db, …)`：**一次** `retentionSamples` 同时喂 `LearningMetrics`（留存/Brier/ECE）与 `CalibrationReport`（偏置）——两半讲的是同一批复习 |
| `app/lib/features/ai/tools/metrics_tools.dart` | 只读工具 `review_metrics`：整体留存、最多 4 个有样本的间隔桶、Brier/ECE、`report.summaryZh`；样本不足时照原话转达。`readOnly => true`（任何权限模式都不逐条询问） |
| `app/lib/features/ai/domain/tool_registry.dart` | 在 `ComposePaperTool` 之后注册 `ReviewMetricsTool(db: db)` |

与 `library_diagnosis_reader.dart` 的分工是刻意的：**诊断读模型自己的状态（自证）**，
**标定只读 `review_logs`**——后者是全 app 唯一一条"外部"检查。

## 7. 刻意未做 / 已知缺口

- **不写回参数**：`calibrated` 保持 0；检验结果只做展示与对话，不改 `ls` / `W_DAR` 等任何系数。
- **不做逐知识点标定**：样本量按知识点切开后普遍不足 30 条，切了只会得到一堆"样本不足"。
- **不做六个 MindNet 实验**：数据不在本仓库（外部只读文档）。
- **不做先验与观测的联合标定**：`cognitive_priors` 与 `assessment_repository` 的合并规则仍按 M1d 的固定口径。
- **工具不给"建议改什么参数"**：那需要先有标定结论，且改参数必须是显式动作。

## 8. 验收记录（本会话实跑）

- `dart analyze lib test` → `94 issues found.`，`error` / `warning` 行计数 **0**（与基线同数）。
- `flutter test test/domain/services/cognitive/calibration_test.dart --concurrency=1` → **17 例全绿**
  （四种"不算"、过度自信/低估/校准良好、斜率门槛、边界 0/1、确定性、`toJson` 契约）。
- `flutter test test/features/ai/metrics_tools_test.dart --concurrency=1` → **12 例全绿**
  （只读两条证明、空库、无预测、样本不足、过度自信、分桶默认开、间隔分桶、`since_days`、`limit`、非法参数、注册与 schema）。
- 回归 `flutter test test/domain/services/cognitive test/features/ai test/features/cognitive --concurrency=1`
  → `+569 All tests passed!`。
