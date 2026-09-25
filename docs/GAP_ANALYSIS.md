# 差距分析：Furnace 定稿 vs Furnace 现状

> 生成日期：2026-09-07
> 上游规范：[FURNACE_SPEC.md](FURNACE_SPEC.md)（权威，冲突以此为准）
> 现状基线：`class-productivity/app`（57 个 Dart 源文件，Drift schema v1，Flutter 3.47.2 / Dart 3.13.2 实机可用）
> 用途：逐条核对「定稿 vs 现状」差距与迁移方案；本文为后续所有文档与代码变更的 hub（命名、常量、格式决策一律读本文，禁止各文件私造版本）。

---

## 1. 命名与定位决策（D 系列）

| 编号 | 决策 | 内容 |
| --- | --- | --- |
| D1 | 产品名 | 全面启用 **Furnace**。应用标题/文案/ARB 全部替换“知序/Furnace”；Dart 包名最终由 `knowflow` 改为 **`furnace`**（本行原写 `threadflow`，是当时的中间名，已于 2026-09-21 全局改名时纠正）；工作目录沿用 `class-productivity/`（本轮未重命名）。 |
| D2 | 模块命名（用户可见层） | Mindnet＝思维导图；Thread＝任务事件流（待办）；Time＝时间/日程；Knowledge＝记忆/复习；“知识库/知识包页”降级为次级入口（见 D4）。导航文案、页面标题全部按定稿词表；**代码内部**保留现有目录/表名（tasks/timeboard/anki/mindmap…）及 `Task` 类，新增 Thread 概念采用新名（`ThreadRanker`、`ThreadState`、`CompletionLog`…），理由：内部改名是纯机械噪声，风险大于收益；对应关系记录在 ARCHITECTURE.md，绝不让“内部 task / 外部 Thread”产生行为分歧。 |
| D3 | 标签 = 树形路径字符串 | 标签系统升级为**树形**：标签保留 `parent_id` + 缓存完整路径 `path`（`文化课/学科/语文/作文`）。路径是权威查询键；UI 默认只显示末级，hover/点击展开全路径。Mindnet “系”导入 = 把节点子树逐节点创建/关联为标签，路径按节点层级拼接。 |
| D4 | `.kpak` 与 `.tfpkg` 并存 | `.kpak` 保留＝班级分享子集（知识点/模板/标签/导图，不含个人数据）；`.tfpkg` 新增＝定稿的“全量工作区打包”（SQLite 数据逻辑全量 + 附件 + 主题），用于备份/迁移/整体传输，合并提供“覆盖/追加”。知识库（`.kpak` 导入导出）从主导航移入设置/次级页。 |
| D5 | 富文本 | Knowledge 词条正文以 Markdown 富文本为主：内置编辑器先做「结构化 Markdown + 引用本地图片」，`flutter_quill` 是否引入取决于网络可用性（见 Open O1）；导入/导出 Markdown 与 JSON 必做。 |
| D6 | Time 块语义 | 语义对齐（**存量数据无需翻转**，已读调度器代码确认）：`available=false`＝**忙碌硬块**（上课/开会/通勤：计入 Thread 硬约束占用时长、参与冲突检测、不可被建议采纳）；`available=true`＝**开放软块**（自习/碎片/深度等：供软性匹配与建议采纳、状态适配的空闲窗口匹配，不计占用）。定稿 1.1.3 公式中“该时间段内所有 Time 日程块的总时长”解释为“充当不可用窗口的忙碌块总时长”（与定稿 §1.2 开篇“为 Thread 提供不可用窗口数据”一致），此解释记入 ARCHITECTURE 4.1。 |
| D7 | 完成历史 | 新增完成记录 `CompletionLog`（任务标签快照 + 完成时刻 + 预估/实际属性），服务疲劳惩罚与 Knowledge 上下文；完成任务不再只改 status。 |
| D8 | “更新与排序”为唯一重排入口 | Thread 页不做自动轮询/自动重排。旧的“新任务自动建议（TaskScheduler 建议清单＋一键采纳）”保留为**创建时/显式点按**的辅助建议，不触碰列表顺序；新排序算法结果仅在用户点击“更新与排序”后呈现。 |
| D9 | FSRS 替换 SM-2 | SM-2 存档（模块保留，测试删/迁），复习调度迁移到 Dart 版 FSRS（官方默认权重常量 + 三参模型本地计算），表结构加 stability/difficulty 等（见 §3）；评分按钮 忘记/模糊/记得 映射 Again/Hard/Good（保留 3 键 UI，扩展 Easy 预留）。 |
| D10 | 算法常量显式化 | 定稿公式未给全部数值参数。所有缺口常量集中为默认值（§4 常量表），代码统一读取 `FurnaceDefaults`，UI 不直接硬编码；常量本身可调（后续“排序规则深度自定义”的载体）。 |
| D11 | 错题强制绑定建模 | “挖空方式”＝一个可调度单元（slot presentation）。强制绑定＝该单元进入短间隔学习队列（10 分钟）并带“必须连续 2 次正确”计数器，达标后解除，回归自由挖空。 |
| D12 | 图谱扩散建模 | 答错卡片 → 取词条标签中源自 Mindnet 节点的标签 → 在导图图上 BFS（边＝父子 + 兄弟）距离 ≤2 → 命中词条的卡片获得提权（距离 1 ×1.8 / 距离 2 ×1.3），以 `BoostEntry(remaining=3)` 计数 3 次抽卡周期后自动衰减清除。 |
| D13 | 外观系统存储 | 主题＝JSON 文件模型（颜色/背景/透明度/字体/缩放/动画开关），内置 light/dark，可导入导出；背景图导入时复制到内部目录。缩放 0.8–1.5 应用整体缩放。 |

## 2. 逐条差距矩阵

> 状态列：🟢 已满足 / 🟡 部分满足（注明缺口）/ 🔴 缺失。阶段列 R1–R6 见 §6。

### 2.1 Thread（对应现状 tasks 模块）

| 定稿条目 | 现状 | 状态 | 差距与迁移 | 阶段 |
| --- | --- | --- | --- | --- |
| 1.1.1 id/title/estimated_duration/deadline | Task(id,title,estimate_minutes,due_at) | 🟡 | 补 `expected_at`（期望时刻）、`energy_required`(1–10, null=忽略)。缺省即算法忽略语义写入引擎。 | R3 |
| 1.1.1 tags 完整树形路径＋折叠显示 | Tag 扁平（name 可含 `/`，无层级）；ObjectTags 关联 task；UI 无路径折叠 | 🔴 | Tag.parent_id + path 缓存（D3）；Task 标签展示组件：默认末级＋悬停/点击展开路径。 | R3/R5 |
| 1.1.2 手动建标签 / Mindnet 系导入 | 手动标签 ✅；思维导图节点可“转标签”（单节点，无子树批量） | 🟡 | “节点转标签”升级为“导入系（含子树）”，保留层级；整棵子树可一键导入为标签路径。 | R5 |
| 1.1.3 仅手动“更新与排序” | 无该按钮；TaskScheduler 会给出建议（不动列表） | 🔴 | Thread 页顶栏常驻：左＝当前目标＋精力水平，右＝“更新与排序”。点击时若状态 2h 未更新先弹确认/修改。排序引擎见 R3。 | R5 |
| 1.1.3 状态输入持久化 | 无能量/目标概念 | 🔴 | 新增单行状态表 `ThreadStates`（energy 1–10、goal_text、goal_node_id、updated_at）。 | R3 |
| 1.1.3 加权公式（0.4/0.3/0.2/−0.1） | 调度建议：依赖→优先级→截止→时间块匹配（规则型） | 🔴 | 新纯 Dart `ThreadRanker`：四分量归一 0..1 加权求和；给出每事件分解得分（可解释 UI）。缺省常量见表 §4.1。 | R3 |
| 1.1.3 硬性约束置底标红 | 无 | 🔴 | `实际可用 = (deadline−now) − 区间内忙碌块总时长`（D6 语义）；`estimate > 实际可用` → 标红置底不参与排序；“时间不足（需 X，可用 Y）”提示。Time 侧提供区间占用查询。 | R3/R5 |
| 1.1.4 任务模板 | 无 | 🔴 | `TaskTemplates`（名称+时长+标签+精力默认值）；创建事件可套用。 | R3/R5 |
| 1.1.4 批量修改 | 无 | 🔴 | 按标签筛选后批量改数值字段的 service+UI。 | R5 |
| （保留项）子任务/依赖/提醒 | Task.parent/dependencies/remind_at + NotificationService | 🟢 | 保留，文档标注为超集能力，不与定稿冲突。 | — |

### 2.2 Time（现状 timeboard 模块）

| 定稿条目 | 现状 | 状态 | 差距与迁移 | 阶段 |
| --- | --- | --- | --- | --- |
| 1.2.1 日程块 id/title/start/end/repeat | 表齐全；repeatRule 列存在但 UI/引擎未实现重复展开 | 🟡 | 实现 repeat 规则解析与区间展开（none/daily/weekly+dow…）；补标签软匹配链路（现有 ObjectTags 支持 time_block）。 | R3/R5 |
| 1.2.1 软性匹配推荐 | suitable_for/energy 属性存在，调度引擎按适合类型匹配 | 🟡 | 语义并入 D6；软块推荐保留。 | R3 |
| 1.2.2 日历视图 日/周/月 | 无日历；列表＋今日安排汇总 | 🔴 | 日/周/月视图（无第三方则手写轻量日历网格）；点空白/点块弹浮窗创建/编辑。 | R5 |
| 1.2.3 冲突弹窗警告 | 无 | 🔴 | 事件期望/截止时刻落在忙碌块内 → 弹窗警告；提供“移至之前/之后”一键（联动调整 expected/deadline 并保证 estimate 可完整放入空闲区）。 | R5 |
| 1.2.3 实时向 Thread 供数 | Repository 存在部分查询 | 🟡 | 提供确定性接口：当前时刻、[t1,t2] 忙碌占用总时长、下一空闲窗口（引擎用）。 | R3 |

### 2.3 Knowledge（现状 anki 模块）

| 定稿条目 | 现状 | 状态 | 差距与迁移 | 阶段 |
| --- | --- | --- | --- | --- |
| 1.3.1 富文本正文＋结构化挖空位＋复习日志 | content 纯文本；挖空＝CardTemplate.clozeTemplate “___” 手写；ReviewLogs 有 | 🟡 | 词条正文升级 Markdown/富文本；新增结构化挖空位记录（槽位＝正文可挖片段，位置稳定 ID）；ReviewLogs 扩展 FSRS 字段。 | R3 |
| 1.3.1 Markdown/JSON 导入导出 | 无（仅 .kpak） | 🔴 | 词条级 Markdown/JSON 导入导出（D5）。 | R5 |
| 1.3.2 自由挖空 | 自动挖空 ClozeGenerator 存在（管理页一键/导入时生成 fill_blank 模板） | 🟡 | 改造成“自由挖空”运行时机制：以概率决定是否创造新空位；新空位＝历史未出现；无新空位打内部标记转历史抽取。挖空历史表记录已用槽位。 | R3 |
| 1.3.2 五种题目形式 | 单选 mcq / 填空 fill_blank / 简答 essay 自评 | 🟡 | 补：多选、有序多选；填空/简答补严格模式（逐字符比对）与非严格（自判）双模式；判断题型与槽位的派生关系。 | R3/R5 |
| 1.3.2 错题强制绑定 | 无 | 🔴 | D11：答错→立即重做一次→10 分钟短间隔再出现→连续两次正确解除；强制期间只抽该绑定方式。 | R3/R5 |
| 1.3.3 FSRS | SM-2（Sm2Scheduler，接口化） | 🔴 | D9：Dart FSRS 移植（默认权重常量＋状态机），替换接入点，算法纯 Dart＋单测。 | R3 |
| 1.3.4 Mindnet 图谱扩散 | 无（卡片与导图仅经标签弱关联） | 🔴 | D12：答错时扩散提权；BoostEntry 计数衰减；抽卡权重参与自由挖空与模板混合队列。 | R3 |
| （联动）Knowledge→Thread 生成任务 | 无 | 🔴 | 复习结果页“生成任务”按钮 → 建 Thread 事件（标题=词条标题，详情带上下文，可带同标签）。 | R5 |

### 2.4 Mindnet（现状 mindmap 模块）

| 定稿条目 | 现状 | 状态 | 差距与迁移 | 阶段 |
| --- | --- | --- | --- | --- |
| 1.4.1 节点增删改/父子 | 树形增删改、折叠、同级上下移、备注 | 🟢 | 拖拽移动（跨父级 re-parent）后置打磨。 | R6 |
| 1.4.2 OPML / FreeMind(.mm) 导入导出 | 无（仅 .kpak 内含导图） | 🔴 | 实现 .mm/OPML 编解码（xml 解析手写或轻量库），UI 入口。 | R5 |
| 1.4.3 子树导入 Thread 标签 | 单节点转标签 | 🔴 | 任意节点选为“系”→一键导入其与全部子节点为树形标签（D3）。 | R5 |
| 1.4.3 节点设为当前目标 | 无 | 🔴 | 节点“设为当前目标”→写 ThreadStates.goal_node_id（含路径），算法按子树提升权重。 | R5 |

### 2.5 模块联动闭环（定稿 §2）

| 触发源→目标 | 现状 | 状态 | 迁移 | 阶段 |
| --- | --- | --- | --- | --- |
| Knowledge→Thread | 无 | 🔴 | 生成任务按钮（上表）。 | R5 |
| Mindnet→Thread | 单节点标签 | 🔴 | 系导入＋设为当前目标（上表）。 | R5 |
| Time→Thread | 部分 | 🟡 | 区间占用/空闲窗口接口（R3 表 2.2 末行）。 | R3 |
| Thread→History（隐式） | status=done 即了事 | 🔴 | CompletionLog 完成记录（D7），供疲劳惩罚与 Knowledge 上下文。 | R3 |

### 2.6 持久化与打包（定稿 §3）

| 定稿条目 | 现状 | 状态 | 差距与迁移 | 阶段 |
| --- | --- | --- | --- | --- |
| SQLite＋本地文件 | Drift SQLite ✅；无附件/背景图文件管理 | 🟡 | 附件目录规范化；背景图/主题文件进内部目录。 | R4 |
| `.tfpkg` 导出/导入（覆盖/追加） | 无 | 🔴 | D4：全量逻辑转储 JSON manifest（含全部表内容、附件、主题）→ zip；可选加密（依赖可用时 AES）；合并器：覆盖（整库替换）/追加（按稳定 id 合并、冲突规则见 KNOWLEDGE_PACKAGE.md 扩展节）。 | R4 |
| 加密/压缩 | zip（archive）✅ 加密未实现 | 🟡 | 压缩默认开；加密可选密码（cryptography 依赖，网络受限则先留接口+文档，见 O1）。 | R4 |

### 2.7 外观自定义（定稿 §4）

| 定稿条目 | 现状 | 状态 | 差距与迁移 | 阶段 |
| --- | --- | --- | --- | --- |
| UI/编辑器字体分设 | 无 | 🔴 | 设置存字体族；本地字体文件可导入运行时加载（FontLoader）。 | R4 |
| 缩放 80%–150% | 无 | 🔴 | 整体 scale 应用。 | R4 |
| 语言中英/扩展 | ARB zh/en ✅ | 🟢 | 词表全量按 D1/D2 更新；扩展机制（额外 ARB 目录）预留。 | R6 |
| 主题色/背景/透明度/背景图 | theme_mode system/light/dark（ThemeMode） | 🔴 | 主题 JSON 模型＋主/辅色＋背景色/透明度/图片（导入复制）；动画开关。 | R4 |
| 主题文件导出导入 | 无 | 🔴 | JSON 主题文件，内置默认深/浅。 | R4 |

### 2.8 交互细节（定稿 §6）

| 条目 | 现状 | 状态 | 迁移 | 阶段 |
| --- | --- | --- | --- | --- |
| Thread 顶栏（目标+精力 + 更新与排序按钮） | 无 | 🔴 | R5 |
| >2h 状态过期确认弹窗 | 无 | 🔴 | 确认后写新时间戳。 | R5 |
| “时间不足”红标签 | 无 | 🔴 | 列表底部/卡片红色标签。 | R5 |

## 3. 数据层 v2 变更清单（Drift）

> 详细定义与迁移 SQL 见 DATA_MODEL.md v2 节；原则：所有既有表只加列/加表，不删列不重构既有数据；数据库文件版本号 +1，Drift migration step 内逐表 ALTER。

| 表 | 变更 |
| --- | --- |
| LocalSettings | 删除/弃用 themeMode 语义（改主题表）；language 保留。 |
| ThreadStates（新） | 单行：energy 1–10、goal_text、goal_node_id、goal_path、updated_at。 |
| Tags | +parent_id、+path（缓存）、+is_leaf_path 语义（path 为权威）。 |
| Tasks | +expected_at、+energy_required、+completed_at（冗余便利，权威在 CompletionLog）。 |
| TaskTemplates（新） | name、estimate_minutes、energy_required、标签集（子表或 JSON）。 |
| CompletionLogs（新） | task_id、completed_at、tag_ids(JSON 快照)、estimate_minutes、energy_required、title 快照。 |
| TimeBlocks | repeat_rule 语义落地（JSON 规则：type=daily/weekly, dows）；available 语义按 D6 重定义（值迁移见 O2）。 |
| KnowledgePoints | content 升级字段 content_format（plain/markdown）；+external_id/package_id 已有。 |
| CardTemplates | 保留为“作者预设卡”（legacy），type 扩 `mcq_multi`/`ordered_multi`；clozeTemplate 保留兼容。 |
| CardStates | 主体改为“呈现单元”：+knowledge_point_id（非空，迁自模板）、+slot_key（可空：自由挖空槽位 id 或 preset 卡 id）、card_template_id 改可空；+FSRS 字段：stability、difficulty、due（已存在 due_at）、state 扩 `learning_forced` 等；unique(card_template_id) 迁移为 unique(knowledge_point_id, slot_key)（slot_key 非空）。 |
| ReviewLogs | +rating_fsrs(1–4)、+response_seconds、+mode（slot/preset）、+strict、+correct(布尔)。 |
| ClozeSlots（新） | knowledge_point_id、slot_key、位置/片段定义（JSON：range or token ids）、exhausted 标记。 |
| ClozeHistory（新） | knowledge_point_id、slot_key、used_at、result(错/对)。 |
| BoostEntries（新） | card_state_id 或 (kp_id, slot_key)、factor、remaining_cycles(3)、created_at。 |
| Themes（新） | id、name、is_builtin、payload(JSON：主/辅色、背景色/透明度/图、字体、缩放、动画)。 |
| Attachments（新，可选先建表） | id、owner_type/owner_id、rel_path、mime。 |

## 4. 算法常量缺省表（D10）

> 定稿未给的数值参数统一收口于此，进入 `FurnaceDefaults`。凡 UI/文档引用同一来源。

### 4.1 ThreadRanker

| 常量 | 缺省 | 说明 |
| --- | --- | --- |
| wUrgency / wGoal / wFit / wFatigue | 0.4 / 0.3 / 0.2 / 0.1 | 定稿权重。 |
| urgencyHalfLifeMin | 240 | 紧急度 = 0.5^(剩余分钟/240)，deadline≤15min 或已过期 → 1；无 deadline → 0。 |
| expectedSoftHalfLifeMin | 360 | 仅有 expected_time 时按软约束给≤0.5 紧急度。 |
| goalMatchMode | auto | free-text：关键词命中（分词 hit 比例）；node：路径前缀/树交集计数。 |
| energyBestDelta | 0 | 适配度 energy 分量 = 1 − min(1,|required−current|/9)。 |
| fatigueWindowMin | 60 | 疲劳惩罚窗口（1 小时）；decay = 1−age/60。 |
| fatigueNormDenom | 2.0 | raw=Σ 重叠标签数×decay；penalty=min(1,raw/2)。 |
| insufficientMarginMin | 0 | estimate > available 即置底（可留余量微调）。 |

### 4.2 Knowledge 复习

| 常量 | 缺省 | 说明 |
| --- | --- | --- |
| newClozeProbability | 0.5 | 每张到期词条抽卡时尝试“创造新空位”的概率。 |
| forcedRelearnMinutes | 10 | 错题短间隔重出现。 |
| forcedConsecutiveCorrect | 2 | 连续两次正确解除强制。 |
| boostDistance1 / boostDistance2 | 1.8 / 1.3 | 图谱扩散提权因子。 |
| boostCycles | 3 | 提权持续抽卡周期数。 |
| fsrs | 官方默认权重 | FSRS 默认参数常量表（迁移时锁版本注明）。 |
| ratingMap | 忘记→Again、模糊→Hard、记得→Good | 3 键 UI → FSRS 4 档映射。 |

### 4.3 自定义系统

| 常量 | 缺省 | 说明 |
| --- | --- | --- |
| scaleMin / scaleMax | 0.8 / 1.5 | 页面缩放范围。 |
| energyScaleMin / Max | 1 / 10 | 精力刻度。 |

## 5. `.tfpkg` 格式要点（草案，详细见 KNOWLEDGE_PACKAGE.md 扩展节）

- 单文件 zip：`manifest.json`（formatVersion=1、全量逻辑转储：所有业务表实体 + attachments 清单 + theme 快照）、`attachments/*`、`themes/*`、`README` 无。
- 全量转储（JSON）优于直接拷 .db：合并策略可逐实体实现、跨版本可容错、内容可审计。
- 覆盖：导入前自动生成当前库的 .tfpkg 备份（防误覆盖）。
- 追加：稳定 id 冲突时默认保留本地（knowledge 类实体按 external/package id 走 .kpak 已有升级逻辑）。
- 加密：可选密码（AES-GCM）；无密码=普通 zip。zip 内 manifest 与附件同密。

## 6. 迁移路线图

| 阶段 | 内容 | DoD |
| --- | --- | --- |
| R0 | 全量备份 `class-productivity` 到 `_backup/2026-09-07` | 文件树校验 |
| R1 | 文档对齐：README/PRD(标记被取代)/ARCHITECTURE/DATA_MODEL v2/KNOWLEDGE_PACKAGE(+tfpkg)/PRIVACY/MILESTONES 重排/FEATURE_MATRIX 重建/OPEN_QUESTIONS 结案 | 本文 §2 每行都有落点 |
| R2 | schema v2 + 迁移 + Repository 扩展 + 单测（无 UI） | `flutter test` 数据层绿；`database.g.dart` 重生成 |
| R3 | 纯 Dart 核心：ThreadRanker＋常量表、FSRS、自由挖空＋错题绑定状态机、图谱扩散、Time 占用/窗口引擎、模板/批改服务 | `dart test` 全绿（含新算法向量测试） |
| R4 | 打包/主题：tfpkg codec＋merge、Theme JSON＋外观设置、字体/缩放/动画接入 | 编解码往返测试；设置页可调 |
| R5 | UI 迁移与联动：命名/词表、Thread 顶栏＋排序页、硬约束红标、日历视图＋冲突一键调整、Knowledge 新复习流＋生成任务、Mindnet 系导入/设目标/.mm-OPML | `flutter analyze` 0 error；widget 冒烟 |
| R6 | 打磨：拖拽 re-parent、双语补全、PROGRESS/矩阵回写、Windows build 冒烟 | `scripts/build_windows.ps1` 可跑通或记录阻塞 |

## 7. 保留 / 兼容 / 弃用

- 保留：子任务、依赖、提醒（本地通知）、.kpak 班级分享、任务建议清单（降级为显式辅助）、复习统计（适配 FSRS）、标签/模板/知识点管理、设置档案与备份 .db。
- 弃用（代码保留存档，UI 下线）：无 — PRD 时代无与定稿硬冲突的功能；SM-2 保留为 `srs/sm2_scheduler.dart` 存档文件但不再被调用。
- 兼容：导入 .kpak 时旧模板照常生成 CardState（preset 卡）；新自由挖空从现有 content 自动推导首批槽位（沿用 ClozeGenerator 逻辑增强）。

## 8. 待决问题（默认决定延续“无反馈按默认执行”风格）

| 编号 | 问题 | 默认决定 |
| --- | --- | --- |
| O1 | pub.dev 网络是否可用（新增 flutter_quill/cryptography/table_calendar） | 不可用则全手写轻量实现（纯 Dart/自有组件），接口先行 |
| O2 | 既有 TimeBlock.available 数据的真实语义 | ✅ 已结案（2026-09-07）：读 `task_scheduler.dart` 确认 available=true 才是任务可排入的开放块；与 D6 语义同向、存量不翻转。 |
| O3 | Thread 顶栏挂在“任务页”还是全局 AppBar | 默认全局（桌面壳顶栏常驻） |
| O4 | 中文产品文案中 Thread/Time 等是否保留英文词 | 保留英文模块名＋中文功能名（定稿原文如此：Thread（动态优先级事件流）） |
| O5 | 有序多选/多选的判分规则 | 顺序全对才对；多选：全选对才计对（严格模式）；非严格用户自判 |
