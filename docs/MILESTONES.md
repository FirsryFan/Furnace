# 开发里程碑与 MVP 范围

> 工作名：Threadflow（定稿名；原工作名「知序 KnowFlow」按 GAP D1 弃用，应用标题/ARB/`pubspec.name` 全面替换）
> 目标：v0.1 的 M0–M6 里程碑已在源码层面完成并跑通核心闭环（Windows 实机可用）；本文件现按 [GAP_ANALYSIS.md](GAP_ANALYSIS.md) §6 组织「Threadflow 定稿迁移」里程碑（R0–R6）。
> 权威：产品定稿见 [THREADFLOW_SPEC.md](THREADFLOW_SPEC.md)（存档 2026-09-07）；命名/常量/格式/阶段等一切决策以 GAP_ANALYSIS.md 为 hub，本文件不新增决策、不私造编号。

---

## 1. 定稿基线

> 现状基线（2026-09-07 核对，SPEC/GAP 存档日）：旧里程碑 **M0–M6 已达成**（源码层面；`app/` 57 个 Dart 源文件、Drift schema v1；Flutter 3.47.2 / Dart 3.13.2 Windows 实机可用，详见 PROGRESS.md）。
> 产品已定稿为 **Threadflow**，核心闭环不变（创建/导入知识点 → 复习与间隔重复；导图节点转标签 → 关联事件/词条；事件 + 时间块 → 排序建议；导出知识包 → 导入背诵；中英切换）。定稿与现状的逐条差异见 GAP §2，历史成果全部保留、按差距迁移，无推倒重来。

### 历史里程碑（v0.1「知序 KnowFlow」计划，M0–M6 已完成）

<details>
<summary>M0–M6 历史清单（源码层面已完成；点击展开）</summary>

**M0：需求与设计 ✅**
- [x] PRD、架构设计、数据模型、知识包格式、隐私设计

**M1：Flutter 项目骨架 ✅**
- [x] Flutter 项目（Windows 平台）
- [x] 应用壳：导航栏、主题、中英双语框架
- [x] 本地数据库接入（Drift）
- [x] Profile / Settings 基础表
- [x] 首次启动向导：设置显示名、语言

**M2：数据层 ✅**
- [x] 全部表结构 + 迁移
- [x] Repository 层
- [x] 种子示例数据（演示知识点/任务/时间块）
- [x] 单元测试：CRUD

**M3：标签与思维导图 ✅**
- [x] 标签 CRUD
- [x] 思维导图树形渲染（CustomPainter / 节点组件）
- [x] 节点添加/删除/重命名/折叠
- [x] 节点转标签
- [x] 标签关联到对象

**M4：任务编排 + 时间板块 ✅**
- [x] 任务 CRUD、子任务、依赖、优先级、提醒
- [x] 时间块 CRUD、重复规则、精力属性
- [x] 自动调度建议引擎 v1（依赖→优先级→截止→时间块匹配）
- [x] 建议清单 UI：一键采纳

**M5：Anki 背诵 ✅**
- [x] 知识点 CRUD + 模板管理
- [x] 自动挖空（基于模板；无模板时简单自动生成）
- [x] 三种题型复习界面
- [x] SM-2 间隔重复调度（现按 D9 存档，迁移 FSRS）
- [x] 今日复习队列 + 简单统计

**M6：知识包导入导出 ✅**
- [x] `.kpak` 导出（含清单/知识点/标签/导图）
- [x] `.kpak` 导入（去重/升级/保留进度）
- [x] 导入前预览与隐私清单

**M7：打磨与发布（v0.1 收尾项，未随 M0–M6 完成）**
- [ ] 中英双语完整覆盖 → 并入定稿词表更新（GAP 2.7「语言」行，阶段 R6）
- [ ] Windows 构建冒烟 → R6 DoD（`scripts/build_windows.ps1` 可跑通或记录阻塞）
- [ ] 崩溃日志与基本自检、用户手册/班级使用说明、真实数据试用与反馈 → 未列入 GAP §6 R0–R6，作发布前补充事项，不再单列里程碑

</details>

---

## 2. Threadflow 定稿迁移里程碑

> 阶段内容与 DoD 均抄列自 [GAP_ANALYSIS.md](GAP_ANALYSIS.md) §6；「差距行」编号对应 GAP §2 各表（2.1 Thread / 2.2 Time / 2.3 Knowledge / 2.4 Mindnet / 2.5 模块联动 / 2.6 持久化与打包 / 2.7 外观自定义 / 2.8 交互细节）。阶段列标「R3/R5」的行＝核心/数据部分在 R3、UI 部分在 R5，由两个阶段分别认领。数据层工作（R2）以 GAP §3 变更清单为准。

### R0：全量备份 ✅（2026-09-07 完成）

- 内容：全量备份 `class-productivity` 到 `_backup/2026-09-07`（实测已就位）。
- DoD：文件树校验。
- 差距行：无（工程性前置步骤，非 §2 业务差距）。

### R1：文档对齐 ✅（2026-09-07 完成）

- 内容：README / PRD（标记被取代）/ ARCHITECTURE / DATA_MODEL v2 / KNOWLEDGE_PACKAGE（+tfpkg）/ PRIVACY / MILESTONES 重排（本文）/ FEATURE_MATRIX 重建 / OPEN_QUESTIONS 结案（含 O2：TimeBlock.available 存量与 D6 同向、无需翻转）。
- DoD：GAP §2 每行都有落点。
- 差距行：无 §2 业务差距行（文档层落点）；本阶段产物（THREADFLOW_SPEC / GAP_ANALYSIS 存档 2026-09-07）是后续所有代码变更的唯一 hub（GAP 头部声明）。

### R2：schema v2 数据层

- 内容：schema v2 + 迁移 + Repository 扩展 + 单测（无 UI）。
- 差距行：§2 无行直接标注 R2 —— 对应 GAP §3「数据层 v2 变更清单」（原则：只加列/加表、不删列不重构既有数据，数据库版本 +1、逐表 ALTER）：
  - 新表：`ThreadStates`、`TaskTemplates`、`CompletionLogs`、`ClozeSlots`、`ClozeHistory`、`BoostEntries`、`Themes`、`Attachments`；
  - 既有表：LocalSettings（弃用 themeMode 语义，language 保留）、Tags（+parent_id/path）、Tasks（+expected_at/energy_required/completed_at）、TimeBlocks（repeat_rule 语义落地；available 语义按 D6 落档——O2 已结案 2026-09-07：存量与 D6 同向、无需翻转）、KnowledgePoints（content_format）、CardTemplates（type 扩 mcq_multi/ordered_multi）、CardStates（呈现单元化 + FSRS 字段）、ReviewLogs（+rating_fsrs 等）。
- DoD：`flutter test` 数据层绿；`database.g.dart` 重生成。

### R3：纯 Dart 核心算法

- 内容：ThreadRanker＋常量表、FSRS、自由挖空＋错题绑定状态机、图谱扩散、Time 占用/窗口引擎、模板/批改服务。
- 差距行（GAP §2 阶段列含 R3 的行）：
  - **2.1 Thread**：1.1.1 补 `expected_at`/`energy_required`（缺省即算法忽略）；1.1.3 状态输入持久化（ThreadStates）；1.1.3 加权公式（ThreadRanker，常量缺省表 §4.1）；以及 R3/R5 行的 R3 侧——1.1.1 标签树形数据层（D3）、1.1.3 硬性约束「实际可用时间」计算（忙碌块按 D6 语义计占用）、1.1.4 任务模板表（TaskTemplates）；
  - **2.2 Time**：1.2.1 软性匹配推荐（语义并入 D6，O2 结案：available=true＝开放软块，存量不翻转；软块推荐保留）＋标签软匹配链路（TimeBlocks↔事件）；1.2.1 repeat 规则解析/区间展开引擎（R3/R5 的 R3 侧）；1.2.3 确定性供数接口（当前时刻 / [t1,t2] 忙碌占用总时长 / 下一空闲窗口）；
  - **2.3 Knowledge**：1.3.1 词条正文升级 Markdown/富文本 + 结构化挖空槽位 + ReviewLogs 扩 FSRS 字段；1.3.2 自由挖空运行时机制（新空位概率/无空位打标记）；1.3.2 错题强制绑定状态机（D11，R3/R5 的 R3 侧）；1.3.2 题式核心侧：题型与槽位派生关系＋批改服务（填空/简答逐字符严格比对、多选/有序多选判分，规则见 O5）；1.3.3 FSRS（D9，替换 SM-2 接入点）；1.3.4 Mindnet 图谱扩散（D12，BoostEntry 计数衰减）；
  - **2.5 模块联动**：Time→Thread 占用/空闲接口（同 2.2 末行）；Thread→History 完成记录 `CompletionLogs`（D7）。
- DoD：`dart test` 全绿（含新算法向量测试）。

### R4：打包 / 主题

- 内容：tfpkg codec＋merge、Theme JSON＋外观设置、字体/缩放/动画接入。
- 差距行（阶段列含 R4 的行）：
  - **2.6 持久化与打包**：SQLite＋本地文件（附件目录规范化；背景图/主题文件复制进内部目录，🟡 补齐）；`.tfpkg` 导出/导入（全量逻辑转储 JSON manifest → zip，覆盖/追加合并，D4，格式要点见 GAP §5）；加密/压缩（压缩默认开，可选密码 AES-GCM，依赖可用性见 O1）；
  - **2.7 外观自定义**：UI/编辑器字体分设（FontLoader）；页面缩放 80%–150%（0.8–1.5 整体缩放，D13）；主题色/背景色/透明度/背景图 + 动画开关；主题 JSON 文件导入导出 + 内置默认深/浅主题（Themes 表）。
- DoD：编解码往返测试；设置页可调。

### R5：UI 迁移与联动

- 内容：命名/词表、Thread 顶栏＋排序页、硬约束红标、日历视图＋冲突一键调整、Knowledge 新复习流＋生成任务、Mindnet 系导入/设目标/.mm-OPML。
- 差距行（阶段列含 R5 的行）：
  - **2.1 Thread**：1.1.1 标签路径 UI（默认末级＋悬停/点击展开，R3/R5 的 R5 侧）；1.1.2 Mindnet「系」导入；1.1.3 顶栏（左＝当前目标＋精力、右＝「更新与排序」，与 2.8 顶栏条目同一实现）；1.1.3 硬性约束标红置底与「时间不足（需 X/可用 Y）」展示（R5 侧，与 2.8 红标签条目同一实现）；1.1.4 模板套用 UI、按标签批量修改；
  - **2.2 Time**：1.2.1 repeat 规则 UI 展开（R5 侧）；1.2.2 日/周/月日历视图＋点击空白/块弹浮窗创建编辑；1.2.3 冲突弹窗警告＋「移至该日程块之前/之后」一键调整；
  - **2.3 Knowledge**：1.3.1 词条级 Markdown/JSON 导入导出；1.3.2 新题式（多选/有序多选）与严格/非严格模式复习 UI（R5 侧，判分规则见 O5）；1.3.2 错题强制绑定复习流（R5 侧）；联动「生成任务」按钮（Knowledge→Thread，标题＝词条标题）；
  - **2.4 Mindnet**：1.4.2 OPML/FreeMind（.mm）导入导出；1.4.3 节点「系」整棵子树导入 Thread 树形标签；1.4.3 节点设为「当前目标」（写 ThreadStates.goal_node_id）；
  - **2.5 模块联动**：Knowledge→Thread、Mindnet→Thread（同 2.3/2.4 各对应行）；
  - **2.8 交互细节**：Thread 顶栏、「>2h 未更新」过期确认弹窗（确认/修改后写新时间戳）、「时间不足」红标签（均并入 2.1 对应行实现）。
- DoD：`flutter analyze` 0 error；widget 冒烟。

### R6：打磨

- 内容：拖拽 re-parent、双语补全、PROGRESS/矩阵回写、Windows build 冒烟。
- 差距行（阶段列含 R6 的行）：
  - **2.4 Mindnet**：1.4.1 拖拽移动（跨父级 re-parent，树形操作已具备，此项后置打磨）；
  - **2.7 外观自定义**：「语言中英/扩展」行（现状 🟢）——定稿词表全量按 D1/D2 更新，扩展机制（额外 ARB 目录）预留。
- DoD：`scripts/build_windows.ps1` 可跑通或记录阻塞。

---

## 3. 风险与对策

> 由 v0.1 版本改写：已完成项降级为历史，未决风险改写为定稿迁移语境；O 编号见 GAP §8。

| 风险 | 对策 |
| --- | --- |
| SM-2 → FSRS 迁移（D9） | SM-2 保留为存档文件（不再被调用）；Dart FSRS 采用官方默认权重常量＋本地三参模型，替换接入点并配算法向量单测比对（R3 DoD） |
| 定稿公式缺少数值参数（D10） | 所有缺省常量集中收口为 `ThreadflowDefaults` 常量表（GAP §4），UI 不硬编码；常量可调，作为后续「排序规则深度自定义」的载体 |
| `.tfpkg` 加密依赖可用性（O1） | cryptography 不可用则压缩默认开、加密留接口＋文档说明，依赖可用时补 AES-GCM（R4） |
| 富文本编辑器依赖可用性（O1） | flutter_quill 不可用则先做「结构化 Markdown＋引用本地图片」的编辑器；词条 Markdown/JSON 导入导出必做（R3/R5） |
| `.tfpkg` 格式后期变更 | manifest 自带 `formatVersion=1`（沿用 .kpak 经验）；覆盖导入前自动生成当前库 `.tfpkg` 备份；`.kpak` 既有升级/去重逻辑继续沿用 |
| 思维导图自由画布复杂度高 | 树形布局已落地（M3）；拖拽移动（跨父级 re-parent）后置 R6 打磨，不做自由画布 |
| 个人开发时间不足 | 按 R0–R6 最小切片推进：先数据层与纯 Dart 核心（R2/R3，无 UI、可单测），再 UI 迁移（R5），发布前只保定稿闭环功能 |

---

## 4. 发布节奏建议

| 版本 | 内容 | 状态/时间 |
| --- | --- | --- |
| v0.1 历史基线 | 旧计划 M1–M6（含 M0 设计文档）核心闭环，源码层面完成 | 已完成（2026-09-07 前；未打包发布） |
| v0.2 定稿迁移版 | R1–R6 完成（R0 备份已于 2026-09-07、R1 文档对齐已于 2026-09-07 完成）＝ Threadflow 定稿功能全量落地，Windows 可用发布版 | R2–R6 推进中；时间视投入 |
| v0.3 Android | 同一套代码适配 Android 8+（定稿目标平台） | 视需要 |

> 时间仅为粗估，取决于实际开发投入。学生项目建议按 §2 的 R 顺序推进：先拿到数据层与纯 Dart 核心的测试全绿（R2/R3），再做 UI 迁移（R5）。
