# 功能矩阵

> ⚠️ **本矩阵的 2026-09-07 版曾把已实现的算法标为「未实现」，与源码不符。**
> 实测基线（2026-09-08）：算法层代码早已存在，`flutter test` 105/105 全绿。本表状态列已按 **2026-09-08 实测** 更新；逐条经过说明见 [PROGRESS.md](PROGRESS.md) 同日轮次。
> 本轮设计依据：[DESIGN_BLUEPRINT.md](DESIGN_BLUEPRINT.md) v2（用户 13 条批注）。

> 对齐：Furnace 定稿（[FURNACE_SPEC.md](FURNACE_SPEC.md)，存档 2026-09-07）
> 状态与阶段来源：[GAP_ANALYSIS.md](GAP_ANALYSIS.md) §2 逐条差距矩阵（每行状态与该表一致，禁止夸大）；阶段定义见 GAP §6 与本仓库 [MILESTONES.md](MILESTONES.md) §2
> 术语：按定稿词表（事件/日程块/词条/节点/系/主题…）；代码内部模块名（tasks/timeboard/anki/mindmap）对照见 ARCHITECTURE.md（D2）
> 代码位置均相对 `app/lib/`，与 GAP 现状列核对过的实际文件

## 2026-09-08 实测状态修正（覆盖下表的 R3 行）

| 能力 | 2026-09-07 表 | 2026-09-08 实测 |
| --- | --- | --- |
| `ThreadRanker` 加权排序 + 硬约束 | 🔴 R3 | ✅ 已实现（`domain/services/scheduling/thread_ranker.dart`，21 项测试） |
| `TimeWindowEngine` 重复展开/占用/空闲窗口 | 🟡 | ✅ 已实现（含 8 项测试） |
| FSRS 间隔重复（定稿 D9） | 🔴 R3 | ✅ 已实现（`domain/services/srs/fsrs_scheduler.dart`，FSRS-6，9 项测试） |
| 自由挖空 + 错题强制绑定状态机 | 🔴 R3 | ✅ 算法已实现（`domain/services/cloze/cloze_engine.dart`）；**接入复习 UI 仍未做** |
| Mindnet 图谱扩散提权 | 🔴 R3 | ✅ 算法已实现（`domain/services/cloze/diffusion_boost.dart`）；**独立复盘界面仍未做** |
| `CompletionLogs` 完成历史 | 🔴 R3 | ✅ 已实现（含 v3 实际用时字段） |
| 树形 Tag（parent_id + path） | 🔴 R3 | ✅ 已实现 |
| **Thread 排序 UI（顶栏 + 排序 + 属性页）** | —（新） | ✅ 2026-09-08 新增（`features/thread/`，用户批注 1–13 落地） |

状态图例：

- ✅ 已实现（＝GAP「🟢 已满足」，源码层面/实机可用）
- 🟡 部分（注明缺口与目标阶段；＝GAP「🟡 部分满足」）
- 🔴 未实现（规划中，标注目标阶段 R\* 与预计位置；＝GAP「🔴 缺失」）

---

## 核心模块

### Mindnet（思维导图）——对应 GAP 2.4

| 需求 | 状态 | 实现位置 / 缺口 |
| --- | --- | --- |
| 导图新建/切换；节点增删改、父子关系、折叠/展开（1.4.1） | ✅ | `features/mindmap/presentation/mind_map_page.dart` |
| 节点同级上移/下移、备注编辑/显示/清除（1.4.1） | ✅ | 同上 |
| 节点拖拽移动（跨父级 re-parent）（1.4.1 后置项） | 🔴 R6 | 树形操作已具备，拖拽留 R6 打磨（mindmap 模块） |
| 导入/导出 OPML、FreeMind（.mm）（1.4.2） | 🔴 R5 | 现仅 `.kpak` 内含导图；R5 实现 xml 编解码＋UI 入口（`features/mindmap/…`） |
| 节点转标签（单节点） | ✅ | `mind_map_page.dart`（现状为单节点、无子树批量） |
| 节点选为「系」→ 整棵子树导入 Thread 树形标签（1.4.3，D3） | 🔴 R5 | 规划中 · mindmap＋tags 模块；标签树形数据层先行（R3） |
| 节点设为「当前目标」（1.4.3） | 🔴 R5 | 规划中 · 写 `ThreadStates.goal_node_id`（表在 R2/R3）＋Thread 顶栏联动 |

> 模块联动（定稿 §2）：Mindnet→Thread 见上两行；Knowledge→Thread 见 Knowledge 节「生成任务」行。

### Thread（任务事件流）——对应 GAP 2.1

| 需求 | 状态 | 实现位置 / 缺口 |
| --- | --- | --- |
| 事件固定字段与 CRUD：id/title/期望用时/截止（1.1.1） | 🟡 缺口：缺 `expected_at`（期望时刻）与 `energy_required`（精力要求 1–10，null=忽略），缺省即算法忽略语义待写入引擎 → R3 | 现为 Task(id,title,estimate_minutes,due_at)：`data/database/tables.dart`、`domain/entities/task.dart`；CRUD/编辑 UI：`features/tasks/presentation/tasks_page.dart`、`task_detail_page.dart` |
| 标签＝完整树形路径（parent_id＋path 缓存），UI 默认末级＋悬停/点击展开（1.1.1 tags，D3） | 🔴 R3/R5 | 现为扁平 Tag＋ObjectTags 关联（`features/tags/presentation/tags_page.dart`、`data/repositories/tag_repository.dart`）；R3 建树数据、R5 折叠展示组件 |
| 标签：手动创建/删除、关联事件/词条/日程块（1.1.2 前半） | ✅ | `tags_page.dart`＋`TagRepository`＋各详情页（任务/词条/时间块弹窗均支持增删标签） |
| Mindnet「系」导入标签（1.1.2 后半） | 🔴 R5 | 见 Mindnet 节「系导入」行（保留完整层级路径） |
| 顶栏：左＝当前目标＋精力水平、右＝「更新与排序」唯一重排入口（1.1.3；交互 §6 / GAP 2.8） | 🔴 R5 | 规划中 · `features/tasks/…`（顶栏常驻）；现状无自动轮询，符合「仅手动触发」精神 |
| 状态输入持久化：`ThreadStates`（energy 1–10、goal_text、goal_node_id、updated_at）（1.1.3） | 🔴 R3 | 新表（GAP §3）；顶栏 UI 在 R5 |
| 加权综合排序 ThreadRanker：0.4/0.3/0.2/−0.1，每事件分解得分可解释（1.1.3） | 🔴 R3 | 新纯 Dart 实现（常量表 GAP §4.1）；现 TaskScheduler 规则型引擎保留为显式建议（下下行） |
| 硬性约束：实际可用＝(deadline−now)−区间忙碌块总时长（忙碌块按 D6 语义计占用）；超时标红置底、提示「需 X 分钟，可用 Y 分钟」（1.1.3；GAP 2.8 红标签） | 🔴 R3/R5 | 计算引擎 R3（依赖 Time 供数接口）；红标 UI R5（tasks 列表/卡片） |
| 任务模板：名称＋时长＋标签＋精力，创建时套用（1.1.4） | 🔴 R3/R5 | `TaskTemplates` 表 R3；套用 UI R5 |
| 按标签筛选后批量修改数值字段（1.1.4） | 🔴 R5 | 规划中 · service＋UI（tasks 模块） |
| 完成任务写完成记录 `CompletionLogs`（标签快照＋时刻，供疲劳惩罚/Knowledge 上下文）（D7，联动 Thread→History） | 🔴 R3 | 新表（GAP §3）；挂在任务完成动作上 |
| 子任务、依赖、提醒（本地通知）（保留项，GAP 2.1 末行 🟢） | ✅ | `task_detail_page.dart`＋`core/notifications/notification_service.dart` |
| 调度建议清单＋一键采纳（D8：保留为创建时/显式辅助建议，不触碰列表顺序） | ✅ | `features/tasks/application/task_scheduler_service.dart`、`tasks_page.dart`；引擎 `domain/services/scheduling/task_scheduler.dart` |

> 交互细节（定稿 §6 / GAP 2.8：顶栏、>2h 过期确认弹窗、「时间不足」红标签）均已并入上表 1.1.3 对应行，不重复列。

### Time（时间/日程）——对应 GAP 2.2

| 需求 | 状态 | 实现位置 / 缺口 |
| --- | --- | --- |
| 日程块 CRUD：标题/开始/结束/重复规则字段、标签挂载（1.2.1） | ✅ | `features/timeboard/presentation/time_board_page.dart`（创建/编辑弹窗、可用状态切换、标签经 ObjectTags） |
| 日程块重复规则展开（none/daily/weekly+dow…）（1.2.1） | 🔴 R3/R5 | `repeatRule` 列已在 `data/database/tables.dart`；解析/区间展开引擎 R3、UI 呈现 R5 |
| 忙碌/开放语义与软性匹配推荐（D6：available=false＝忙碌硬块，计 Thread 硬约束占用、参与冲突检测、不可被建议采纳；available=true＝开放软块，供软性匹配与建议采纳，不计占用） | 🟡 缺口：语义并入 D6、软块推荐保留 → R3（O2 已结案 2026-09-07：available=true 本就是任务可排入的开放块，与 D6 同向，存量不翻转） | 引擎现按「适合类型」匹配（TaskScheduler 调度链路）；D6 解释已记入 ARCHITECTURE 4.1 |
| 事件落在日程块内的冲突弹窗警告＋「移至该日程块之前/之后」一键调整（1.2.3） | 🔴 R5 | 规划中 · timeboard＋tasks 联动（联动调整 expected/deadline，保证期望用时可放入空闲区） |
| 向 Thread 确定性供数：当前时刻 / [t1,t2] 忙碌占用总时长 / 下一空闲窗口（1.2.3；联动 Time→Thread） | 🟡 缺口：现仅部分查询，需接口化 → R3 | `data/repositories/time_block_repository.dart`（消费方：ThreadRanker，R3） |
| 今日安排汇总（含时间块已关联任务显示）（v0.1 保留能力） | ✅ | `time_board_page.dart` |

> 日历视图（日/周/月）见「平台与体验」节对应行（定稿 1.2.2 / GAP 2.2）。

### Knowledge（记忆/复习）——对应 GAP 2.3（代码 anki 模块）

| 需求 | 状态 | 实现位置 / 缺口 |
| --- | --- | --- |
| 词条 CRUD、来源字段；卡模板管理（1.3.1 基础） | ✅ | `features/anki/presentation/anki_manage_page.dart` |
| 词条正文 Markdown/富文本＋content_format＋内置编辑器（1.3.1，D5） | 🟡 缺口：content 现为纯文本（`domain/entities/knowledge_point.dart`）；升级 R3，编辑器取舍按 O1 | 管理页编辑器（现纯文本编辑） |
| 结构化挖空位记录＋复习日志（1.3.1） | 🟡 缺口：挖空为模板 `clozeTemplate`「___」手写、无槽位记录；ReviewLogs 缺 FSRS 字段 → R3 | `domain/entities/card_template.dart`、ReviewLogs（`data/database/tables.dart`） |
| 词条级 Markdown/JSON 导入导出（1.3.1） | 🔴 R5 | 现仅 `.kpak` 整体包；词条级编解码 R5（`features/packages/…` codec 扩展） |
| 自由挖空运行时机制：概率决定创造新空位、历史未出现、无空位打标记转历史抽取（1.3.2） | 🟡 缺口：现为一次性自动挖空（管理页一键/导入时生成 fill_blank）→ 改造 R3 | `domain/services/cloze/cloze_generator.dart`（首批槽位推导沿用其逻辑增强，GAP §7 兼容） |
| 五种题目形式：单选/填空/简答已有，补多选、有序多选与严格/非严格双模式（1.3.2） | 🟡 | 现有三题式复习流 `features/anki/presentation/anki_page.dart`；题型扩展核心 R3、UI R5（判分规则见 O5） |
| 错题强制绑定：答错立即重做→约 10 分钟短间隔再出现→连续两次正确解除（1.3.2，D11） | 🔴 R3/R5 | 强制绑定状态机 R3（`learning_forced` 等状态入 CardStates）；复习流 UI R5 |
| FSRS 间隔重复：完全本地、按历史复习动态调整（1.3.3，D9） | 🔴 R3 | 现 SM-2：`domain/services/srs/sm2_scheduler.dart`（存档、不再被调用）；Dart FSRS 替换接入点（`features/anki/application/anki_service.dart`），评分 忘记/模糊/记得 → Again/Hard/Good |
| Mindnet 图谱扩散提权：答错词条取关联节点，距离 1 ×1.8 / 距离 2 ×1.3，3 次抽卡周期衰减（1.3.4，D12） | 🔴 R3 | `BoostEntries` 表（GAP §3）；提权并入抽卡/挖空队列权重 |
| 复习队列与三种评分 UI（v0.1 能力，评分映射 FSRS 于 R3） | ✅ | `anki_page.dart`＋`anki_service.dart` |
| 复习统计 / 7 天柱状图（GAP §7 保留，统计口径适配 FSRS） | ✅ | `features/anki/application/anki_stats_service.dart`＋`anki_manage_page.dart` |
| 联动：复习中「生成任务」按钮 → 建 Thread 事件（标题＝词条标题，带上下文/同标签）（GAP 2.3 末行 / 2.5 Knowledge→Thread） | 🔴 R5 | 规划中 · anki 复习结果页 → `features/tasks/…` 创建入口 |

---

## 分享与隐私

> 双轨：`.kpak`（班级分享子集）保留 ✅；`.tfpkg`（定稿全量工作区打包）新增 🔴 R4（D4）。

| 需求 | 状态 | 实现位置 / 缺口 |
| --- | --- | --- |
| `.kpak` 导出：班级分享子集（词条/模板/标签/导图），不含个人任务/进度（D4） | ✅ | `features/packages/application/package_export_service.dart`＋`KnowledgePackageCodec`（`data/package/…`） |
| `.kpak` 导入：预览/去重/升级/保留复习进度；导入自动挖空 | ✅ | `package_import_service.dart`＋`features/packages/presentation/packages_page.dart` |
| 知识库（`.kpak`）入口降级为次级入口（D4） | 🔴 R5 | 现仍为导航一级页；随 R5 导航/词表调整落实 |
| `.tfpkg` 导出/导入：全量逻辑转储（JSON manifest＋附件＋主题）→ zip，合并策略提供覆盖/追加；覆盖前自动备份当前库（定稿 §3，D4） | 🔴 R4 | 规划中 · package 模块 codec 扩展（格式要点见 GAP §5） |
| `.tfpkg` 加密：可选密码 AES-GCM（GAP 2.6 加密/压缩行） | 🟡 缺口：zip（archive）编解码已有（`.kpak` 在用），加密未实现 → R4 | 依赖可用性 O1：pub.dev 不可用则先留接口＋文档 |
| 本地数据默认不联网（本地优先） | ✅ | 架构设计＋`docs/PRIVACY.md` |

---

## 平台与体验

| 需求 | 状态 | 实现位置 / 缺口 |
| --- | --- | --- |
| Windows 10/11 优先 | ✅ | Flutter 项目（`app/windows`）＋`scripts/build_windows.ps1`（R6 DoD 冒烟） |
| Android 8+ 适配 | 🔴 v0.3 | 同一套 Flutter 代码，见 MILESTONES §4 发布节奏（不在 R 阶段内） |
| 中英双语（ARB zh/en） | ✅（词表待 R6 更新） | `lib/l10n/app_*.arb`（词表全量按 D1/D2 更新＋扩展 ARB 目录预留 → R6，GAP 2.7） |
| 本地通知提醒 | ✅ | `core/notifications/notification_service.dart` |
| 隐私文档 | ✅ | `docs/PRIVACY.md` |
| 主题自定义：主/辅色、背景色、透明度、背景图片、动画开关（定稿 §4.1） | 🔴 R4 | 现为 ThemeMode system/light/dark（`core/theme/app_theme.dart`、设置页）；R4 主题 JSON 模型＋`Themes` 表 |
| 主题文件导入导出＋内置默认深/浅主题（定稿 §4.2） | 🔴 R4 | 规划中 · settings 模块（背景图导入复制进内部目录） |
| UI 字体与编辑器正文字体分设、本地字体文件导入（定稿 §4.1） | 🔴 R4 | 规划中 · FontLoader 运行时加载（settings 模块） |
| 页面缩放 80%–150%（整体缩放）（定稿 §4.1） | 🔴 R4 | 常量 0.8–1.5（GAP §4.3）；整体 scale 应用 |
| 日/周/月日历视图：切换、点击空白/时间块弹浮窗创建或编辑（定稿 1.2.2 / GAP 2.2） | 🔴 R5 | 现为列表＋今日安排汇总（`time_board_page.dart`）；日历网格 R5（table_calendar 或手写，O1） |
| 本地存储：SQLite＋本地文件，附件/背景图文件管理（定稿 §3） | 🟡 缺口：附件目录规范化、背景图/主题文件入内部目录 → R4 | Drift SQLite ✅（`data/database/`）；附件/背景文件管理未做 |

---

## 说明

- ✅/🟡/🔴 与 [GAP_ANALYSIS.md](GAP_ANALYSIS.md) §2 的状态列（🟢/🟡/🔴）逐行一致：🟡 均注明缺口，🔴 均标注目标阶段（R\* 定义见 GAP §6 / MILESTONES §2；Android 适配为 v0.3 发布节奏目标，不在 R 阶段内）。未实现的 🔴 行只写模块级预计位置，不预写不存在的文件细节。
- 产品定稿（2026-09-07）未推翻既有闭环；「v0.1 保留能力」行源自 PROGRESS.md 实现记录，未在 GAP §2 单独占行。
- 环境：本机已装 **Flutter 3.47.2 / Dart 3.13.2**（Windows 实机可用）。
- 验证手段：`dart analyze`（0 error）＋ `flutter test`（全绿）；Windows 构建冒烟：`scripts/build_windows.ps1`（R6 DoD）。
