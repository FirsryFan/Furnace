# 数据模型（Furnace v2）

> 产品：Furnace（前身：知序 Furnace）
> 更新：2026-09-07（对齐 [FURNACE_SPEC.md](FURNACE_SPEC.md) 定稿；差距与决策见 [GAP_ANALYSIS.md](GAP_ANALYSIS.md) 决策 D 系列与 §3）
> 存储：SQLite（Drift）
> 约定：所有表包含 `id`（TEXT UUID）、`created_at`、`updated_at`（INTEGER 毫秒时间戳），除单行表外。
> 版本：schema v1 → v2（迁移步骤见文末 §7；只加列/加表，不删列）

---

## 1. 概念 ↔ 实现映射（决策 D2）

| 定稿概念（用户可见） | 内部实现（代码/表） |
| --- | --- |
| Thread 事件 | `Tasks` 行（保留列名 task 系；新增字段见 2.7） |
| Time 日程块 | `TimeBlocks` |
| Knowledge 词条 | `KnowledgePoints` |
| Knowledge 呈现单元（挖空方式/预设卡） | `CardStates`（唯一键 = knowledge_point_id + unit_key） |
| Mindnet 导图/节点 | `MindMaps` / `MindNodes` |
| Thread 状态顶栏（精力/目标） | `ThreadStates`（单行） |
| 完成历史（隐式 History） | `CompletionLogs` |
| 任务模板 / 批处理 | `TaskTemplates` + `ObjectTags(task_template)` |
| 挖空位 | `ClozeSlots` |
| 挖空使用/作答历史 | `ClozeHistory`、`ReviewLogs` |
| 图谱扩散提权 | `BoostEntries` |
| 主题配置 | `Themes` + `LocalSettings.active_theme_id` |

## 2. 实体关系总览

```
Profile 1 ─── 1 LocalSettings(单行)      ThreadStates(单行)

Tag(树形: parent_id + path)
MindMap 1 ─── n MindNode
MindNode n ─── 0..1 Tag (source_node_id / tag_id)

Tag n ─── n ObjectTag ──→ Task / TaskTemplate / TimeBlock / KnowledgePoint / CardTemplate / Task 系

Task n ─── 1 Task(parent)
Task n ─── n TaskDependency
Task 1 ─── n CompletionLog（历史快照）
Task n ─── n TaskTimeBlock（软块建议占用）

TimeBlock n ─── n ObjectTag(tag)

KnowledgePoint 1 ─── n CardTemplate(预设卡, legacy)
KnowledgePoint 1 ─── n ClozeSlot（结构化挖空位）
KnowledgePoint 1 ─── n CardState（呈现单元：preset / cloze / essay 自评）
CardState 1 ─── n ReviewLog
KnowledgePoint 1 ─── n BoostEntry（答错扩散提权）
KnowledgePoint n ─── n ObjectTag(tag)

KnowledgePackage 1 ─── n PackageItem（.kpak 导入来源记录）
Theme 1 ─── n (LocalSettings.active_theme_id 指向当前)
Attachment n ─── 1 owner(多态)
```

## 3. 表结构（v2）

### 3.1 Profiles（不变）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | 本地 UUID |
| display_name | TEXT | 导出知识包作者名 |
| avatar_color | INTEGER NULL | 头像颜色索引 |
| created_at | INTEGER | |

### 3.2 LocalSettings（单行）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | INTEGER PK | 固定 1 |
| language | TEXT | `system`/`zh`/`en`（v2 语义不变） |
| theme_mode | TEXT | **弃用**（v1 遗留，保留列；UI 不再读写，改由 active_theme_id 驱动） |
| profile_id | TEXT NULL FK | 当前档案 |
| active_theme_id | TEXT NULL FK→Themes | v2：当前主题（NULL=内置随系统） |
| created_at / updated_at | INTEGER | |

### 3.3 Tags（树形化，D3）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | |
| parent_id | TEXT NULL FK→Tags | 父标签（树形层级） |
| name | TEXT | 末级显示名（不得含 `/`） |
| path | TEXT | **权威查询键**，完整树形路径字符串，如 `文化课/学科/语文/作文`；顶层=自身 name；UNIQUE |
| color | INTEGER NULL | ARGB |
| description | TEXT NULL | |
| source_node_id | TEXT NULL | 若由 Mindnet 节点生成：节点 id（“系”导入时每个标签各记其来源节点） |
| created_at / updated_at | INTEGER | |

> 一致性：path 由 (parent.path, '/', name) 派生并在写入时缓存；改名/移动时级联刷新子树 path；`/` 禁止出现在 name 中（导入 Mindnet 标题时若含 `/` 需净化或允许转义，见实现）。

### 3.4 ObjectTags（不变）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | |
| tag_id | TEXT FK | |
| object_type | TEXT | `task` / `task_template`(v2) / `time_block` / `knowledge_point` / `card_template` |
| object_id | TEXT | |
| created_at | INTEGER | |

唯一索引：`(tag_id, object_type, object_id)`

### 3.5 MindMaps（不变） / 3.6 MindNodes（不变）

字段同 v1：MindMap(id,title,root_node_id,…)；MindNode(id,map_id,parent_id,text,notes,is_tag,tag_id,position_x/y 预留,collapsed,sort_order,…)。

> v2 使用要点：标签“系”导入与“设为当前目标”都只读节点树（parent_id、sort_order 兄弟序、text），不需要新列。

### 3.7 Tasks（= Thread 事件行；加列）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | |
| parent_id | TEXT NULL | 子任务（保留能力） |
| title | TEXT | 事件标题 |
| description | TEXT NULL | 详情（Markdown） |
| status | TEXT | `todo`/`doing`/`done` |
| priority | INTEGER | 0=低 1=中 2=高（保留；算法分量已由 v2 加权公式取代，排序引擎不使用本列，仅遗留 UI/手动参考） |
| estimate_minutes | INTEGER NULL | 期望用时（= estimated_duration，分钟） |
| expected_at | INTEGER NULL | **v2**：期望时刻（软约束） |
| due_at | INTEGER NULL | 截止时刻（硬约束 deadline） |
| remind_at | INTEGER NULL | 提醒（保留能力） |
| energy_required | INTEGER NULL | **v2**：精力要求 1–10；NULL=算法忽略 |
| completed_at | INTEGER NULL | **v2**：完成时刻（便利冗余；权威在 CompletionLogs） |
| created_at / updated_at | INTEGER | |

### 3.8 TaskDependencies（不变） / 3.9 TaskTimeBlocks（不变）

同 v1。

### 3.10 TaskTemplates（v2 新表，1.1.4）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | |
| name | TEXT | 模板名（如“阅读 20 分钟”） |
| estimate_minutes | INTEGER NULL | 套用时默认时长 |
| energy_required | INTEGER NULL | 套用时默认精力要求 |
| created_at / updated_at | INTEGER | |

模板默认标签：`ObjectTags(object_type='task_template')`。套用模板 = 以模板参数预填事件（标签复制关联）。

### 3.11 CompletionLogs（v2 新表，D7）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | |
| task_id | TEXT FK | 完成的事件 |
| title | TEXT | 标题快照 |
| tag_ids | TEXT | 完成时刻标签 id 快照，JSON 数组字符串 |
| tag_paths | TEXT NULL | 完成时刻标签 path 快照，JSON 数组（供疲劳惩罚免联表） |
| estimate_minutes | INTEGER NULL | |
| energy_required | INTEGER NULL | |
| completed_at | INTEGER | 完成时刻 |
| created_at | INTEGER | |

> 供：ThreadRanker 疲劳惩罚（60 分钟窗口、时间衰减）；Knowledge 上下文参考。完成任务动作 = 更新 Tasks.status + completed_at 并插入本表。

### 3.12 ThreadStates（v2 新表，单行，1.1.3 状态顶栏）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | INTEGER PK | 固定 1 |
| energy | INTEGER NULL | 当前精力水平 1–10 |
| goal_text | TEXT NULL | 当前主要目标（自由文本） |
| goal_node_id | TEXT NULL | 目标来源 Mindnet 节点 |
| goal_path | TEXT NULL | 节点路径缓存（如 `生物/光合作用`） |
| updated_at | INTEGER NULL | 最近一次更新/确认时间（>2h 判定） |
| created_at | INTEGER | |

> 约束：goal_text 与 goal_node_id 至少一项；节点模式时 goal_path 与 goal_node_id 同写。

### 3.13 TimeBlocks（语义重定义 D6）

字段同 v1：id, title, start_at, end_at, repeat_rule, available, energy, suitable_for, created_at, updated_at。

| 字段 | v2 语义 |
| --- | --- |
| repeat_rule | TEXT NULL；JSON：`{"type":"none"} \| {"type":"daily"} \| {"type":"weekly","dows":[1,3,5]}`（1=周一…7=周日）；NULL=none |
| available | **false=忙碌硬块**（上课/开会/通勤；计入 Thread 占用时长、参与冲突检测）；**true=开放软块**（碎片/深度；供软性推荐与建议采纳，不计占用）。v1 存量数据迁移翻转规则见 GAP O2 结论（读 time_board_page.dart 后定，代码迁移时落地）。 |
| energy / suitable_for | 软块匹配属性（沿用） |

### 3.14 KnowledgePoints（词条）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | |
| title | TEXT | 词条标题 |
| content | TEXT | 正文 |
| content_format | TEXT | **v2**：`plain`/`markdown`（默认 markdown；v1 存量按 plain 处理不强制改写） |
| source | TEXT NULL | |
| external_id / package_id | TEXT NULL | .kpak 去重升级用 |
| created_at / updated_at | INTEGER | |

### 3.15 CardTemplates（预设卡，legacy 保留）

字段同 v1：id, knowledge_point_id, type, question, answer, options, cloze_template, hint, sort_order, external_id, …

`type` v2 扩展取值：`mcq`（单选）/ `mcq_multi`（多选）/ `ordered_multi`（有序多选）/ `fill_blank` / `essay`。
`options`：JSON 数组字符串；`mcq_multi`/`ordered_multi` 时 `answer` 存正确项索引数组 JSON（有序多选=期望顺序）。
其余为作者预置内容卡，v2 复习队列按“呈现单元”调度（3.16），不再按模板独立出题。

### 3.16 CardStates（呈现单元 = 调度主体，FSRS 挂载点；结构变更）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | |
| knowledge_point_id | TEXT NULL FK | **v2**：所属词条（从 v1 的 card_template 反查回填；代码层强制非空） |
| card_template_id | TEXT NULL FK | legacy 预设卡来源（unit_key=preset:* 时必有） |
| unit_key | TEXT NULL | **v2** 呈现单元键（词条内唯一，见下）；preset 卡/自由挖空槽位/自评各一格式 |
| due_at | INTEGER NULL | 下次出现时间 |
| stability / difficulty | REAL | **v2** FSRS 状态 |
| interval_days | REAL | 兼容保留（FSRS 派生展示值） |
| ease | REAL | 弃用（保留列） |
| repetitions / lapses | INTEGER | FSRS 派生计数 |
| state | TEXT | `new`/`learning`/`review`/`relearning`/`forced`(v2) |
| forced | INTEGER | **v2** 0/1 强制绑定中 |
| forced_streak | INTEGER | **v2** 强制期连续正确计数 |
| last_reviewed_at | INTEGER NULL | |
| created_at / updated_at | INTEGER | |

唯一索引（v2）：`(knowledge_point_id, unit_key)`（sqlite 允许多个 NULL 共存，legacy 行 unit_key 为 NULL 时不受限；代码保证新写入非空）。

**unit_key 编码约定**（实现处集中定义，单测锁定）：
- 预设卡：`preset:{card_template_id}`
- 自由挖空槽位：`cloze:{cloze_slot_id}`（复习时题目形式——单选/多选/有序多选/填空——由词条/槽位派生并随机化呈现，见 3.17 与 GAP §4.2）
- 词条自评（简答题、整词条自测）：`essay:{knowledge_point_id}`

> 挖空/出题是“呈现层派生”，不单独建调度单元 → 错题强制绑定发生在单元级（unit_key 级），与定稿“该挖空方式立即强制生效”对齐（GAP D11）。

### 3.17 ClozeSlots（v2 新表，结构化挖空位，1.3.1/1.3.2）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | |
| knowledge_point_id | TEXT FK | |
| slot_key | TEXT | 词条内稳定键（如 `c0`、`c1`…） |
| definition | TEXT | JSON：正文中挖空片段的稳定定位（起始/长度/片段 id；词条正文以 Markdown/富文本存储时按“文本 token 化后的跨度”记，正文微调后按最近匹配重锚定） |
| exhausted | INTEGER | 0/1：无可挖新空位的内部标记（定稿 1.3.2：打标后仅从历史方式抽取） |
| created_at / updated_at | INTEGER | |

唯一索引：`(knowledge_point_id, slot_key)`

### 3.18 ClozeHistory（v2 新表，挖空历史）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | |
| knowledge_point_id | TEXT FK | |
| slot_key | TEXT | 被抽到的槽位 |
| correct | INTEGER | 0 错 / 1 对 |
| used_at | INTEGER | |
| created_at | INTEGER | |

> 自由挖空“新空位 = 历史未出现过的位置”判定 = 该词条 ClozeHistory 未含此 slot_key；无可挖新位 → ClozeSlots.exhausted=1。

### 3.19 ReviewLogs（复习记录，扩展）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | |
| card_state_id | TEXT FK | |
| card_template_id | TEXT NULL FK | legacy（unit_key=preset 时冗余） |
| unit_key | TEXT NULL | v2 冗余快照 |
| rating | INTEGER | v1 3 档（0 忘记/1 模糊/2 记得，保留兼容列） |
| rating_fsrs | INTEGER NULL | v2：1=Again 2=Hard 3=Good 4=Easy（3 键 UI 映射见 GAP §4.2） |
| correct | INTEGER NULL | v2：0/1 自动判分结果 |
| judge_mode | TEXT NULL | v2：`auto`（严格逐字符比对）/`self`（用户自判） |
| format | TEXT NULL | v2：实际呈现形式 `mcq`/`mcq_multi`/`ordered_multi`/`fill`/`essay` |
| ms_taken | INTEGER NULL | v2：作答耗时 ms |
| reviewed_solution | INTEGER NULL | v9：做错之后有没有对过答案（`0`/`1`）；**NULL = 没问过或不适用**，不写 false |
| closeness | REAL NULL | v9：对答案后想起来的程度 0–1；NULL = 没问过或这次答对了。当前 UI 只给两个文档锚点 0.5 / 0.6（见 `docs/MINDNET_ROADMAP.md` §4） |
| reviewed_at | INTEGER | |
| created_at | INTEGER | |

### 3.20 BoostEntries（v2 新表，图谱扩散，1.3.3/D12）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | |
| knowledge_point_id | TEXT FK | 被提权的词条 |
| factor | REAL | 1.8（距离 1）/ 1.3（距离 2），同词条多来源取最大 |
| remaining_cycles | INTEGER | 剩余有效抽卡周期，初始 3；每发生一次抽卡选择事件 -1，归 0 删除 |
| created_at | INTEGER | |

> 写入时机：某词条卡片答错 → 取该词条标签中 Tag.source_node_id 非空的节点 → 在该导图树上 BFS（边：父子 + 兄弟相邻）距离 ≤2 → 对“标签来源节点命中上述节点”的词条写/刷新 BoostEntry。抽取权重 = base × factor。

### 3.21 Themes（v2 新表，4.1/4.2）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | |
| name | TEXT | 主题名 |
| is_builtin | INTEGER | 0/1（内置 light/dark 只读） |
| payload | TEXT | JSON：primary/secondary 色、背景色、背景透明度、背景图相对路径（本地文件复制至内部 themes/ 目录）、ui_font/editor_font、scale(0.8–1.5)、animations 开关 |
| created_at / updated_at | INTEGER | |

> 导出/导入 = payload JSON 文件（+图片附件打包进 .tfpkg；单主题分享另以 zip/JSON+图形式，见实现）。

### 3.22 Attachments（v2 新表，§3 存储方案）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | TEXT PK | |
| owner_type | TEXT | `knowledge_point` / `theme` / … |
| owner_id | TEXT | |
| rel_path | TEXT | 相对内部目录的路径 |
| mime | TEXT NULL | |
| created_at | INTEGER | |

### 3.23 KnowledgePackages / 3.24 PackageItems（不变）

同 v1（.kpak 导入来源与映射）。

---

## 4. 关键索引（v2 增补）

- Tags：`path` UNIQUE；`(parent_id)`
- Tasks：`(status)`, `(due_at)`, `(completed_at)`
- CompletionLogs：`(task_id)`, `(completed_at)`
- CardStates：UNIQUE `(knowledge_point_id, unit_key)`；`(due_at)`；`(state)`
- ClozeSlots：UNIQUE `(knowledge_point_id, slot_key)`
- ClozeHistory：`(knowledge_point_id)`
- ReviewLogs：`(card_state_id)`, `(reviewed_at)`
- BoostEntries：`(knowledge_point_id)`
- TimeBlocks：`(start_at)`；ObjectTags、TaskDependency、MindNode、CardTemplate 等沿用 v1

## 5. 数据一致性规则（v2 增补）

1. 完成任务：status→done 时写 `completed_at` 并**必须**插 `CompletionLogs`（快照当时 tags/estimate/energy）。
2. 删除事件：级联删子任务/依赖/TaskTimeBlock；CompletionLogs 保留（历史不随事件删除）或按任务级联（产品取舍：保留——疲劳惩罚与统计需要；删除词条/标签时不受影响）。
3. 标签改名/改父级：级联刷新该标签及子树的 `path`；历史快照（CompletionLogs.tag_paths、manifest）不动。
4. 删除标签：删 ObjectTags；Tags 子级一并删除；MindNode 关联回退。
5. 删除词条：级联删 CardTemplate/CardState/ClozeSlot/ClozeHistory/ReviewLog/BoostEntry；CompletionLogs 不涉及。
6. 导入 .tfpkg「覆盖」前，先自动把当前库导出为 .tfpkg 备份；「追加」按 GAP §5/文档合并规则逐实体并入。
7. 时间一律本地毫秒时间戳（沿用 v1）。

## 6. .kpak 知识包内模型（沿用 v1）

见 [KNOWLEDGE_PACKAGE.md](KNOWLEDGE_PACKAGE.md)（.kpak 第 1–6 节 + .tfpkg 第 7 节）。

## 7. schema v1 → v2 迁移步骤（Drift onUpgrade 依据）

> 步骤顺序即代码 `MigrationStrategy.onUpgrade` 中的顺序（1→2）。原则：先建新表/新索引，再对既有表 ALTER ADD COLUMN，后回填数据；不重建表。

1. 建新表：ThreadStates、TaskTemplates、CompletionLogs、ClozeSlots、ClozeHistory、BoostEntries、Themes、Attachments。
2. Tasks：ADD `expected_at` INTEGER NULL；ADD `energy_required` INTEGER NULL；ADD `completed_at` INTEGER NULL。
3. LocalSettings：ADD `active_theme_id` TEXT NULL（不建 FK 以免旧行悬空；代码级校验）。
4. KnowledgePoints：ADD `content_format` TEXT NULL（NULL=plain，代码按 plain 读）。
5. CardTemplates：无 DDL（type 取值扩展纯代码）。
6. CardStates：ADD `knowledge_point_id` TEXT NULL；ADD `unit_key` TEXT NULL；ADD `stability` REAL NULL；ADD `difficulty` REAL NULL；ADD `forced` INTEGER NULL DEFAULT 0；ADD `forced_streak` INTEGER NULL DEFAULT 0。
7. CardStates 回填：`knowledge_point_id = (SELECT knowledge_point_id FROM card_templates WHERE card_templates.id = card_states.card_template_id)`；`unit_key = 'preset:' || card_template_id`（有模板的存量行）；`stability/difficulty` 初值按 FSRS new 卡默认。
8. ReviewLogs：ADD `rating_fsrs` INTEGER NULL；ADD `correct` INTEGER NULL；ADD `judge_mode` TEXT NULL；ADD `format` TEXT NULL；ADD `ms_taken` INTEGER NULL；ADD `unit_key` TEXT NULL（回填同 7）。
9. TimeBlocks：无 DDL（available 语义翻转是数据迁移：按 O2 结论在 v2 首次启动时执行一次 UPDATE；repeat_rule 文本格式转换见实现兼容层——v1 若有存量文本型规则则原样保留读取）。
10. Tags：ADD `parent_id` TEXT NULL；ADD `path` TEXT NULL；回填 `path = name`（存量平铺标签视为顶层）；建 UNIQUE index on path（先清重复名冲突策略：同名平铺标签保留其一并追加序号，见实现）。
11. 建新索引（§4）：CardStates UNIQUE(knowledge_point_id, unit_key) 等。

> 版本号：`schemaVersion = 2`。迁移前建议用户数据自动备份（v2 首次启动前或升级弹窗）。

---

## 8. v3 → v9 增量（本文档只细化到 v2，之后以迁移代码为准）

本文档 §1–§7 描述的是 v1 → v2；v3 起的每一步写在 `app/lib/data/database/database.dart` 的
`onUpgrade` / `_upgradeV*ToV*` 里，`_ensureColumns()` 是"版本号已是最新但列/表缺失"的自愈兜底
（对应测试：`app/test/data/database/v5..v9_migration_test.dart`、`app/test/features/ai/v7_migration_test.dart`）。
其中 v9 这一步与认知模型的事件语义绑定，单独记在这里：

| 序 | 表 | 变更 | 语义 |
| --- | --- | --- | --- |
| v7 | `local_settings` | ADD `ai_max_rounds` INTEGER NULL；ADD `anki_judge_mode` TEXT NULL；ADD `anki_card_type_preference` TEXT NULL | 三个 NULL 都表示"用户没选"，分别解析为 `AiConfig.defaultMaxRounds`（8）、`strict` 判分、`mixed` 题型 |
| v8 | 新表 `review_group_plans` | tag_id 唯一 + 名称/两档每日上限 | **没有行 = 不限额**（不是 0），删标签连带删方案 |
| v9 | `review_logs` | ADD `reviewed_solution` INTEGER NULL；ADD `closeness` REAL NULL | 做错后"对过答案"是 `retrieval_failure_feedback` 而不是 `lapse`（MindNet `IO_PROTOCOL.md` §2.3）；NULL ≠ false |

> v9 的教训：`_tableFor()` 必须认识 `review_logs`，否则自愈路径会抛
> `Invalid argument(s): unknown table review_logs`，真实旧库将无法打开——`v9_migration_test` 就是为了这条存在的。

---

## 9. v10：测评层三张表（M1b，`docs/ASSESSMENT_DESIGN.md` §5）

测评层是 milestone ①「用测评初始化认知模型」。设计口径：先自评起步、客观抽检逐步；
测的是**抽象参数**（`R0`/`D`/`fluency`），不是背了几张卡；instrument 按板块设计。

| 表 | 关键列 | 语义 |
| --- | --- | --- |
| `assessment_sessions` | `id` / `subject_key`（空串=不分科）/ `scope_tag_ids`（JSON，tag id 而不是路径）/ `started_at` / `finished_at`（NULL=没做完）/ `budget`（JSON，NULL=没设）/ `note` | 一次**测量事件**。结束时间只记一次：重复 finish 不把事实往后推 |
| `assessment_responses` | `id` / `session_id` / `knowledge_point_id`（NULL=整卷性步骤）/ `step_kind`(`self_report`\|`recall`\|`objective`) / `prompt` / `answer` / `correct` / `self_rating`(0–5) / `confidence`(0–5) / `elapsed_ms` / `judged_by`(`self`\|`ai`\|`auto`) | **只追加**的证据行。`correct`（客观）与 `self_rating`（主观）是两个列：先验层正是靠两者之差算校准偏置 |
| `cognitive_priors` | 主键 `(knowledge_point_id, source)` / `source`(`assessment:self`\|`:objective`\|`:blended`) / `r0` / `d`（NULL=没抽检）/ `fluency`（NULL=没自评）/ `n` / `calibrated`(默认 0) / `created_at` | **派生**的先验，随时可整表重算。不写进 `card_states`（先验≠观测） |

迁移与自愈：`schemaVersion` 9 → 10，`_upgradeV9ToV10()` 建三张表（全部**只加不删、建成空表**——
没有人被测过就是空表，不开测评界面的安装读到的行为与之前完全一致）；`_ensureColumns()` 额外做
"版本号已经是最新但表缺失"的自愈（Drift 在 `user_version` 已等于当前版本时**完全跳过** `onUpgrade`）。
测试：`app/test/data/database/v10_migration_test.dart`（真实 v9 文件升级 / 自愈路径 / 外键实测）、
`app/test/data/repositories/assessment_repository_test.dart`（步骤往返、无证据步骤被拒、先验是派生的、多来源合并）。

### 9.1 同步三分类（用户口径③：不做实时同步）

同步在 **Windows 出一个可发布 release 时做一次**，现在的 `.tfpkg` 导出/导入就是载体
（`exportDump` 按 `user_tables()` 动态枚举，新表自动进包）。为了让那天不做数据手术，新表从第一天
就按三类标好：

| 类 | 表 | 合并规则 |
| --- | --- | --- |
| 只追加（日志） | `assessment_responses`、`review_logs`、`completion_logs`、`diffusion_logs`、`exposure_logs` | 并集 + 按 id 去重 |
| 可合并（状态） | `assessment_sessions`（按 `finished_at` 取完整的一轮）、`card_states`、`tasks` | 字段级 last-write-wins + 冲突留痕 |
| 派生（可重算） | `cognitive_priors` | 不参与合并：导入后本地 `rebuildPriors()` 重算 |

> v10 的实测教训：本项目生成的 schema **不带任何外键约束**——`references(...)` 只是意图声明，
> `PRAGMA foreign_key_list(review_logs)` 为空，连 v2 就存在的表也没有。所以"删一轮连步骤一起删"
> 只能写在仓储里（`AssessmentRepository.deleteSession`），`v10_migration_test` 用断言把这条钉住，
> 免得后来者以为有数据库兜底而省掉显式清理。

## 10. v11：`review_logs.predicted_r`（M6 校准曲线）

| 列 | 类型 | 语义 |
| --- | --- | --- |
| `predicted_r` | `REAL`，可空 | 判分**之前**模型对"这张卡这次能不能想起来"的预测（`R`）。NULL = 没有预测 |

这一列存在的唯一理由是**校准必须诚实**：如果预测是在复习之后按新状态重算的，那等于拿已知答案给自己打分，
Brier/ECE 会系统性地好看。因此：

- 写入点是 `review_service.dart` 的复习流程（`state` = 复习前的行，`moment` = 展示答案的时刻），
  且 `AnkiRepository.addReviewLog` **从不自己推导**这个值；
- v11 之前的所有行一律 NULL。NULL 表示"当时没有记预测"，**不等于**"预测 0.5"，所以
  `LearningMetrics.hasCalibration` 在没有任何带预测的样本时是 false，读数页明说"校准曲线还没有样本"；
- 迁移 `_upgradeV10ToV11()` 只加列（`_addColumnIfMissing`），`_ensureColumns()` 同步登记，
  同样防"版本号跑在列前面"；
- 历史**不补算**：补算出来的预测不是预测。曲线从这一版开始积累。

证据：`app/test/data/database/v11_migration_test.dart`（真实 v10 文件升级后老行 `predicted_r` 为 NULL +
自愈路径能写能读）、`app/test/data/repositories/anki_repository_test.dart`（`retentionSamples` 的判分、
间隔、NULL 预测）、`app/test/features/anki/review_service_test.dart`（写入的预测与答对答错无关——
这条断言就是"预测在判分之前算"的守卫）。

## 11. v12：题库四张表（`docs/QUESTION_BANK_DESIGN.md`）

题库是"组卷 / 搜题 / 加工"共同的地基。设计口径（用户）：**价值在选择题与加工题，不在来源数量**——
来源分级只是排序权重，低价值题压后不删；AI **不出题**，只解题并交出自述思维链。

| 表 | 关键列 | 语义 |
| --- | --- | --- |
| `questions` | `id` / `stem` / `answer`(NULL=后补) / `solution` / `subject_key` / `question_type` / `source_level`(`gaokao`\|`provincial_diagnostic`\|`elite_school`\|`school`\|`personal`\|`unknown`) / `source_label` / `year` / `region` / `difficulty` + `difficulty_source`(`prior`\|`ai`\|`manual`) / `stem_fingerprint` / `trap_note` / `state`(`raw`\|`structured`\|`processed`) / `ai_quality` + `ai_quality_note` / `origin`(`manual`\|`ai_scan`\|`furnace`) / `created_at` / `updated_at` | 题目实体。`state` 是**加工进度**不是质量；质量在 `ai_quality`。题干与选项**只追加**；两条受限写路径：加工列 `state`/`trap_note`/`difficulty`/`ai_quality`（`QuestionRepository.updateProcessing`），来源元信息 `source_level`/`source_label`/`year`/`region`（`updateSource`，`source_level` 走词表白名单；轮次一百零一） |
| `question_options` | `id` / `question_id` / `label` / `content` / `is_correct` / `sort_order` / `created_at` | 选择题选项。`questions.answer` 仍写正确答案，判分只读那一列（选项表不参与判分，免得两处真相） |
| `reasoning_chains` | `id` / `question_id` / `source`(`ai`\|`user`) / `model`(NULL 可) / `summary` / `step_count` / `created_at` | 一条链 = 一次"AI 亲自解题"的产物。同题可多条（不同解法/模型）互不覆盖；链是**派生数据**，可随时重跑，故不参与跨设备合并 |
| `reasoning_steps` | `id` / `chain_id` / `idx`(0 起) / `goal` / `action_type` / `justification` / `check_method` / `stuck_risk`(0–1，NULL 可) / `knowledge_hints`(JSON 文本) / `note` / `created_at` | 链内步骤。`action_type` 存**原串**（`domain/services/reasoning/capability_action.dart` 的词表 key），词表演进不丢历史数据 |

指纹去重：`stemFingerprint()`（`lib/data/repositories/question_repository.dart`，纯 Dart FNV-1a 64 位）
只挡"完全同一道题"（去空白 + 标点归一 + 小写后同哈希）；近似重复留给后续按考点链找相似题。
同指纹入库返回既有题目（`ingest` 的 `created == false`），不是抛错。

同步三分类：`questions` / `question_options` 归**只追加**（并集 + 按 id 去重）；
`reasoning_chains` / `reasoning_steps` 归**派生**（导入后本地重跑或用本地副本，不合并）。

**能力动作画像（轮次一百零二）不落库**：它是 `reasoning_steps` 的派生聚合（按 `action_type` 分桶算条数/
高风险条数/平均 `stuck_risk`），每次从步骤表现算（`capability_profile.dart` + `capabilityProfileProvider`）。
与卡点评估同一条口径：派生计算不新增列、不新增表 —— 链一重跑，画像跟着变，不存在"画像过期了"这种状态。

迁移与自愈：`schemaVersion` 11 → 12，`_upgradeV11ToV12()` 建四张空表（全部只加不删——
没人收过题就是空表，不开题库界面的安装行为与之前完全一致）；`_ensureColumns()` 同时做
"版本号已是最新但表缺失"的自愈。

> 与 v10 同一条教训：本项目生成的 schema **不带任何外键约束**，所以 `deleteQuestion` 必须显式
> 删选项、标签边、链、步骤，`v12_migration_test` / `question_repository_test` 用断言把这条钉住。

证据：`app/test/data/database/v12_migration_test.dart`（真实 v11 文件升级后老数据一行不少 + 四张新表
可写可读 + 自愈路径）、`app/test/data/repositories/question_repository_test.dart`（指纹去重、空题干被拒、
加工不改题干、来源/质量排序、检索过滤、删除级联、链与步骤往返与钳位）。

## 12. v14：`exposure_logs`（读了没测，MindNet `exposure`）

（v13 是两张拍照整理表，写在 `docs/HANDWRITING_INTAKE_DESIGN.md` §4。）

`IO_PROTOCOL.md` §2.2 的五类动作里，`exposure`（"我看了/读了，但没测自己"）是本应用此前唯一
无法产生的：复习页只有"显示答案 + 打分"两条路，读书或看补充资料完全进不了模型。
`docs/MINDNET_ROADMAP.md` §2 把它列为落地顺序第 2 片的后一半。

| 列 | 类型 | 语义 |
| --- | --- | --- |
| `id` | TEXT PK | `Ids.next('exposure')` |
| `card_state_id` | TEXT | 哪一行卡的状态被读了（`references(CardStates#id)` 只是意图声明，本项目 schema 不带外键，见 v10/v12 的教训） |
| `source` | TEXT 非空 | 读发生在哪里。当前唯一生产者是复习页的"读过，没测自己"（`kExposureSourceAnswerReveal = 'answer_reveal'`）；路线图里的材料摄取会写自己的值 |
| `exposed_at` | INTEGER | 阅读的墙钟时刻（ms），与 `review_logs.reviewed_at` 同一个钟 |
| `created_at` | INTEGER | 写入时刻（当前 = `exposed_at`） |

**为什么单独一张表，而不是塞进 `review_logs`**：`review_logs` 是*测试*记录——留存率桶与 M6
标定曲线都从它算（`docs/ASSESSMENT_DESIGN.md` §7）。曝光没有评分也没有对错：塞进去就得给
`rating`（NOT NULL）编一个值，而且"看了没测"会被算成一次成功回忆。分开之后，
留存率/标定/复习次数一律不受影响（`v14_migration_test` 用 `review_logs` 为空的断言钉住这条）。

模型侧仍然收到事件，而且是**它自己的事件类型**：`ReviewService.recordExposure` →
`CognitiveModel.modelStateAfterReview(row, rating: 3, nowHours, reread: true)` →
`DsrEventType.reread`。它的 S 增益被 `kappa_reread_ratio`（默认 0.1，"再读只有十分之一的增益"）
缩放、`R0` **不动**（只有 `retrieval_success` 抬 R0）；FSRS 的 `due_at`/`stability`/`difficulty`/
`repetitions`/`lapses`/`last_reviewed_at`/`forced` **一个都不写**——读不是提取证据，间隔只能由
提取证据推动（D1）。模型两列被写，且 advisor 不可用时按 `grade` 的同一契约为 null（不阻断事件）。

迁移与自愈：`schemaVersion` 13 → 14，`_upgradeV13ToV14()` 建空表，`_ensureColumns()` 同时做
"版本号已是最新但表缺失"的自愈（`schemaVersion` 跑在表前面的老文件不会每次写曝光都报
`no such table`）。

证据：`app/test/data/database/v14_migration_test.dart`（真实 v13 文件升级后老数据一行不少 +
新表可写可读 + 曝光不产生复习记录 + 自愈路径）、`app/test/features/anki/review_service_test.dart`
（不写复习记录/不动 FSRS 七列/只写模型两列且 R0 未被抬）、
`app/test/domain/services/srs/dsr_card_state_test.dart`（同一行上 reread vs `retrieval_success` vs
`lapse` 的 S 与 R0 轨迹不同）、`app/test/features/anki/review_page_test.dart`
（按钮只在"答案已揭示、还没写库"时出现；按下后写曝光、不写复习记录、到期日不变）。

## 13. v24：题目编号（SCP 式整体编号）与题目图片（轮次一百二十一）

用户要"每道题一个独有编号，像 SCP 对异常的编号，整体跨学科，不按学科分"。这一版只把
**编号本身**与**题目配图**落到 schema，题库其余实体不动。

| 改动 | 类型 | 语义 |
| --- | --- | --- |
| `questions.serial_no` | INTEGER，可空 | 跨学科整体序列号，从 1 起；显示层格式化成 `TR-00001`（`kQuestionSerialMinDigits = 5`，超过 5 位不截断）。可空是为了兼容 v23 老库、v23 及更早的 `.tfpkg` 包、`append` 导入可能撞号的行——**宁可重复也不丢题**，所以不加 UNIQUE 索引 |
| `attachments.sort_order` | INTEGER 非空，默认 0 | 同一 owner 内多张图的展示顺序；老行补 0，新图由 `QuestionMediaStore` 取当前最大值 + 1，首张为 0 |

**编号怎么发**：唯一插入点 `QuestionRepository.ingest` 在**同一个事务**里先读
`SELECT MAX(serial_no)`，再算 `max + 1`，然后插入题目。事务内读-算-写保证并发不撞号；
`QuestionDraft` 不带编号参数，调用方无法自己指定（编号是仓储的职责，不是收题页的）。

> v24 时用的是 `nextQuestionSerial`（`lib/domain/services/questions/question_number.dart`，
> 纯 `max + 1`）；**v33 起改为** `allocateQuestionSerial(highestExisting: MAX, lastIssued: 高水位)`
> （`lib/domain/services/questions/question_serial_allocator.dart`）+ 回写 `question_serial_counters`，
> 见 §22。

**老库回填**：`_upgradeV23ToV24()` 补两列后调 `backfillQuestionSerialNumbers()`——按
`(created_at, id)` 升序给 `serial_no IS NULL` 的行逐行补 1..N，已有号不动。逐行 UPDATE 而
不用窗口函数，是为了让三种 SQLite 实现语义一致（桌面/Android/测试内存库）。`_ensureColumns()`
里也有一份同样的自愈：版本号已经是 24 但列被老文件盖掉时补列并回填。

**两个刻意的取舍（已写进测试注释）**：

1. **编号不加 UNIQUE**：`append` 导入是"整包 dump + 跳过 id 冲突"，两个库各自从 1 发号，
   合并后必然撞号。撞号只是显示重复，去重（UNIQUE）会让整包导入失败——不符合"纸端/设备端
   双向同步"的主线场景。冲突在 UI 上以"题号可能重复"呈现，后续要真唯一得引入命名空间/来源前缀。
2. **号不回收只做到"不腾空"（v24 时）**：当时分配规则是"现存最大 + 1"，删掉**当前最大号**
   那道题后它的号会被下一道新题接手。这条取舍在 **v33** 补上了：新增单行高水位表
   `question_serial_counters`，分配取 `max(现存最大, 历史最大发放) + 1` 并回写，删号不再被接手
   （见 §22）；题库的不变量仍是只追加，删题是清理手段。

**题目图片**：复用 `attachments` 表（`owner_type = 'question'`、`owner_id = questionId`），
新的 `QuestionMediaStore`（`lib/features/questions/data/question_media_store.dart`）负责"文件 +
表行"永远同步：

- 磁盘：`<application support>/question_images/<questionId>/<attId>/<原文件名>`；
- DB：`rel_path` 存**相对 app support 的 POSIX 路径**（Windows app 目录会随安装位置/改名移动，
  存绝对路径会在换安装目录后全部失效）；
- `save` 先写文件再插行（文件失败不会留悬挂行；行失败有文件残留，`deleteForQuestion` 兜底）；
- `delete` 先删行再删文件并收掉空目录；`deleteForQuestion` 在删题时调用（`deleteQuestion`
  本身仍不清理附件，见 v12 教训——调用方要显式清）。

**与拍照整理 store 的分工**：`HandwritingIntakeStore` 的 owner 是"还没确认的收题页"
（`owner_type = 'handwriting_intake'`、`owner_id` 空），图片在题目存在之前就落盘；题目配图
属于已入库的题。两者都写 `attachments`，但 owner 不同——混用会让"题目没确认时的临时图"
出现在某道题的配图里。

**包导入**：`TfpkgService.importDump` 在事务收尾后调用 `backfillQuestionSerialNumbers()`：
v23 及更早的包没有 `serial_no` 列，导入后补号；v24 包自带号，已有号不动。

证据：`app/test/data/database/v24_migration_test.dart`（真实 v23 文件升级后老题 `[1, 2]`、
`sort_order` 为 0、新入库题号 3；版本 24 但缺列的自愈；`backfill` 只补 NULL 且接 `MAX + 1`、
重复调用幂等）、`app/test/features/questions/data/question_media_store_test.dart`（落盘与表行、
排序、owner 隔离、同名不覆盖、越界文件名被剥成 basename、删行删文件收空目录）、
`app/test/domain/services/questions/question_number_test.dart`（格式化/解析/发号边界）、
`app/test/data/repositories/question_repository_test.dart`（入库 1/2、同指纹重复入库号不变、
删掉最大号后下一题不接手旧号——v33 高水位，见 §22）、`app/test/data/package/tfpkg_test.dart`（编号随包走；v23 包没有
`serial_no` 时导入后补 1、2）。

## 14. v25：能力动作词表 overlay 持久化（轮次一百二十三）

用户要"以后能自己往能力动作词表里加动作，不用等发版"。这一版只加**一列可空偏好**与读写层，
把轮次一百二十一留在纯逻辑层的 overlay 接到数据库与生产解题管道上。

| 改动 | 类型 | 语义 |
| --- | --- | --- |
| `local_settings.capability_action_overlay_json` | TEXT，可空 | 用户自定义动作的 JSON（`CapabilityActionOverlay.toJson` 产物，形如 `{"version":1,"customActions":[...]}`）；**NULL = 用户没改过 = 出厂词表**，与 language / themeMode / goalBeta 同一条可空偏好契约 |

**为什么只存用户条目**：内置 20 个动作跟着代码走，存整张词表会在发版改内置表时把用户库钉死在旧表上；
存合并结果等于把"内置 + 自定义"的派生数据当事实。合并永远在读取时做
（`CapabilityActionOverlay.catalog`），提示词渲染与解析器 `lookup` 吃同一个合并对象。

**迁移**：`_upgradeV24ToV25()` 只 `addColumnIfMissing`，**不写默认值**；表不存在时直接返回，
交给 `_ensureColumns` 自愈（版本号已经是 25 但列被老文件盖掉时补列）。测试锁的事实：真实 v24
文件升级后 language/themeMode/goalBeta 原样保留、新列 NULL；伪造 v25 缺列文件靠自愈补列后能读写；
保存后关库重开仍是 v25、不再迁移且值还在（`app/test/data/database/v25_migration_test.dart`）。

**读写层**：`lib/features/questions/application/capability_vocabulary_store.dart`

- `CapabilityVocabularyStore.load()`：设置行不存在 / 列为 NULL / JSON 语法错 / 形状不对
  一律读作 `CapabilityActionOverlay.empty`（出厂词表），**永不抛异常**——词表只影响动作归类，
  不该挡住解题或启动；
- `save(overlay)`：先 `ensureSettings()`（单行表可能还不存在）；`overlay.isEmpty` 时写回
  **NULL**（回到出厂词表，不留下空壳 JSON），否则写 `jsonEncode(overlay.toJson())`；
- provider：`capabilityVocabularyStoreProvider`（同步取 store）与
  `capabilityActionOverlayProvider`（`FutureProvider`，保存后由界面 invalidate 刷新）。

**接进解题管道**：`QuestionReasoningService` 新增可选参数
`Future<CapabilityActionOverlay> Function()? overlayLoader`（生产 provider 传 `store.load`）；
每次 `solveAndDecompose` 都重新取一次词表，而不是构造时读死——管道是长活对象，用户改词表后
下一次解题就该生效。`_loadOverlay()` 失败（loader 抛异常）退回内置词表；拿到 `catalog` 后同时
用于 `solveThenDecompose(capabilityCatalog: catalog.actions)` 与
`parseChain(raw, lookup: catalog.byKey)`——两处必须同源，否则出现"提示词允许、解析器不认识"。

**未做**：词表编辑 UI 与 l10n（界面写入口未接，本轮只有纯逻辑编辑层与未知动作发现器由队友
交付）；跨设备同步词表（overlay 目前只在本机 `local_settings` 里）。

证据：`app/test/data/database/v25_migration_test.dart`（真实 v24 升级 / 伪造 v25 自愈 / 关库重开
仍在）、`app/test/features/questions/application/capability_vocabulary_store_test.dart`（NULL 与
坏 JSON 读作空、保存往返、空词表写回 NULL、坏数据可被覆盖、provider invalidate 语义）、
`app/test/features/questions/application/question_reasoning_service_test.dart`（自定义动作进提示词
且被解析成 customAction、loader 抛异常退回内置词表、空 overlay 行为不变）、
`app/test/data/repositories/question_repository_test.dart`（`findBySerialNo` 与
`search(serialNos:)` 的过滤语义）。

## 15. v26：题目来源字段（组卷网定点找题，轮次一百二十八）

定点找题的链路是"按筛选条件拿到组卷网列表链接 → 用户在浏览器里找到题 → 把题面粘回 App → 入库"。
要重建链接、要能核对"这题是从哪来的"，题库就需要记住外部来源标识。v26 只加三列可空文本，
其余结构不动。

| 改动 | 类型 | 语义 |
| --- | --- | --- |
| `questions.source_url` | TEXT，可空 | 外部来源页的原始链接（组卷网题目详情页或用户粘贴里带的 URL）；**NULL = 没有外部来源**（自建题、拍照题） |
| `questions.zujuan_question_id` | TEXT，可空 | 组卷网 `questionid`（详情页 `<bankid>q<questionid>.html` 的后半段） |
| `questions.zujuan_bank_id` | TEXT，可空 | 组卷网 `bankid`（详情页路径的前半段，随学科变化） |

**为什么三列都存、而不是只存 URL**：URL 会被站点改版/清洗丢参数；question/bank id 是稳定身份，
可以随时用 `zujuanQuestionDetailUrl` 重建链接，也能做"这题我是不是已经收过"的人工核对。
**为什么加 UNIQUE**：不加。题干指纹（`stem_fingerprint`）已经拦住同题重复入库；来源 id 是
可后补、可缺失的元数据（粘贴文本里常常只有一个 id），加唯一约束会让首次迁移遇脏数据失败、
也让"先入库后补来源"做不到。**NULL 不等于没有来源，只是没记录**。

**写入路径**：`QuestionDraft` 新增 `sourceUrl / zujuanQuestionId / zujuanBankId` 三个可空字段，
`QuestionRepository.ingest` 用 `Value(draft.xxx)` 原样写入；粘贴导入把 `origin` 写 `'zujuan'`、
`state` 写 `'raw'`（题面是别人站的原文，先当原料，等用户整理后再 `structured`）。
`app/lib/features/questions/application/zujuan_paste_import.dart` 是装配层：
`zujuanDraftFromPasted(pasted, {required subjectKey, stemOverride})` 单条 +
`zujuanDraftsFromPaste(raw, {required subjectKey, defaultSourceLevel})` 批量（只跳过空题干，
不因一条坏草稿中断整批），选项的 `isCorrect` 一律 false（答案可能分小问，不猜）。

**迁移**：`_upgradeV25ToV26()` 对 questions 表 `addColumnIfMissing` 三列，表不存在直接返回；
`_ensureColumns()` 里加同样的自愈块（版本号已是 26 但列被老文件盖掉时补列）。
`database.g.dart` 由 `dart run build_runner build --delete-conflicting-outputs` 重新生成
（耗时约 120 s；不要用默认短超时跑，会被杀在半路）。

**测试锁的事实**（`app/test/data/database/v26_migration_test.dart`，3 例）：
真实 v25 文件升级后老题原样保留、题号 1/2 在、三列 NULL，并能在 v26 上入库带来源的新题（题号 3）；
带来源入库后关库重开（已 v26 不再迁移）仍读回 `source_url`/`zujuan_question_id`/`zujuan_bank_id` /
`origin='zujuan'` / `state='raw'`；伪造 v26 缺列文件靠 `_ensureColumns` 补列后可读可写。
装配层 `app/test/features/questions/application/zujuan_paste_import_test.dart` 15 例覆盖字段搬运、
链接回填优先级、缺 id 不猜链接、空白归一、批量顺序与默认档位。

## 16. v27：附件角色（`attachments.role`，答案/解析截图随题保存，轮次一百三十四）

组卷网的答案与解析是一整张 JPEG（登录后可见，免费账号每天约 30 道），用户会把截图存回题目。
这些图必须和题干配图分开：题干配图属于"题长什么样"，答案截图属于"答案长什么样"，导出 Word
时前者跟在题干后、后者进卷末"参考答案与解析"附录。v27 只给附件表加一列可空文本，不动其它表。

| 改动 | 类型 | 语义 |
| --- | --- | --- |
| `attachments.role` | TEXT，可空 | 附件的用途。**NULL / 空串 = 旧数据与别处附件，读作题干配图**；`stem` = 题干配图；`answer` = 答案（及解析）截图；`solution` = 解析截图（预留，读取端先与 answer 同桶） |

**为什么可空、为什么不在旧行上回填**：`attachments` 是多态附件表（`owner_type`/`owner_id`），同一个表还挂消息、材料等
别的 owner；迁移时无法判断一张图是不是题干图，回填只会把别处附件误标成 `stem`。因此 NULL 即"未分类"，
读侧统一折叠成 `stem`（旧版本拍进去的题干图正好都是这个语义），写入端则一律显式写角色。

**读写口径**（`app/lib/features/questions/data/question_media_store.dart`）：
- `QuestionImageRole` 常量 `stem` / `answer` / `solution`；顶层 `effectiveQuestionImageRole(String? stored)` 把
  NULL / 空串 / 纯空白折成 `stem`，未知值原样保留（不静默改写，便于以后加角色）。
- `save({..., String role = QuestionImageRole.stem, ...})` 写 `Value(effectiveRole)`；`sortOrder` 按**角色内**
  排号（题干图 0,1,2…、答案截图也从 0 起），两个角色的顺序互不影响。
- `list(questionId, {String? role})`：不传 = 全部角色；`stem` = `role IS NULL OR role = 'stem'`（旧行不丢）；
  其它角色精确匹配；排序仍是 `sortOrder, createdAt, id`。
- `deleteForQuestion` 不区分角色，整题删除时两种图一起清。
- 应用层读图：题干配图用 `loadQuestionDocxImages` → `list(questionId, role: stem)`，答案截图不进题干位置。

**迁移**：`_upgradeV26ToV27()` 对 `attachments` 表 `addColumnIfMissing` 一列 role（表不存在直接返回）；
`_ensureColumns()` 里加同样的自愈块（版本号已是 27 但老文件被盖掉时补列）。`database.g.dart` 由
`dart run build_runner build --delete-conflicting-outputs` 重新生成（约 88 s，只 `AttachmentsCompanion` 变化）。

**测试锁的事实**（`app/test/data/database/v27_migration_test.dart` 3 例 +
`app/test/features/questions/data/question_media_store_test.dart` 角色组 7 例，共 +20 全绿）：
真实 v26 文件升级后老行 role 仍 NULL、按 stem 读得到、按 answer 读为空，写 answer 截图从 0 排号且不挤进题干图；
伪造"版本 27 但缺列"的文件靠 `_ensureColumns` 补列后可读可写；带角色入库关库重开（不再迁移）读回 answer、
NULL 读回 NULL、读侧折算不回写；未知角色原样落库、读取时不计入两桶。



## 17. v28：复习提醒的开关与时刻（轮次一百三十五）

五应用领域里「flashcard 推送」的推送半边终于落地：设置页一个开关 + 一个每天的时刻，到点若还有到期卡片
就用系统本地通知提醒一次。v28 只给单行设置表加两列可空字段，不新建表、不动调度数据。

| 改动 | 类型 | 语义 |
| --- | --- | --- |
| `local_settings.review_reminder_enabled` | BOOL，可空 | 是否每天提醒复习。**NULL = 用户没选过，读作 `false`** |
| `local_settings.review_reminder_minutes` | INT，可空 | 提醒时刻 = 本地时间的当天第几分钟（0..1439，1200 = 20:00）。**NULL = 没选过，读作域层出厂值 20:00** |

**为什么可空、为什么迁移不回填**：与 `goal_beta` / `capability_action_overlay_json` 同一套契约——
回填会把今天的出厂值冻进每一台已有安装，以后想改出厂时刻就永远达不到了。提醒本身是会弹系统通知的
东西，升级更不该替用户把它打开，所以 NULL 读作关闭。

**读写口径**（`app/lib/data/repositories/settings_repository.dart`）：
- `getReviewReminderEnabled()`：无设置行 / NULL → `false`。
- `getReviewReminderMinutes()`：原样返回 `int?`；**`null` 不是 `0`**——0 是午夜、是用户能选的合法值，
  两者必须可区分。出厂值翻译在域层（`kDefaultReviewReminderMinutesOfDay`），仓库不替它决定。
- `updateReviewReminderEnabled(bool)` 直接写；`updateReviewReminderMinutes(int)` 校验 0..1439，越界抛
  `ArgumentError`（不静默 clamp：clamp 出来的时刻与调用方要的不是一回事，还会伪装成用户的选择）。
- 关掉开关不清时刻：用户再打开时还是上次选的时间。

**到期侧数据**（`app/lib/data/repositories/anki_repository.dart`）：新增 `nextDueAtAfter(int afterMillis)`——
返回严格大于该时刻的最小 `due_at`，没有则 `null`。`due_at` 为 NULL 的卡表示「现在到期」，已由
`getDueCardStates` 覆盖，不算未来到期时刻。复习提醒据此判断「今天之后还会不会到期」。

**迁移**：`_upgradeV27ToV28()` 对 `local_settings` 表两次 `addColumnIfMissing`（表不存在直接返回）；
`_ensureColumns()` 的 `local_settings` 列表加同样两列做自愈（版本号已是 28 但老文件被盖掉时补列）。
`database.g.dart` 由 `dart run build_runner build --delete-conflicting-outputs` 重新生成（62 s，只
`LocalSettingsCompanion` / 表类变化）。

**测试锁的事实**（`app/test/data/database/v28_migration_test.dart` 4 例 +
`settings_repository_test.dart` 复习提醒组 3 例 + `anki_repository_test.dart` `nextDueAtAfter` 组 4 例，共 +20 全绿）：
真实 v27 文件升级后老设置行读作关 / 没选过、升级后能立刻写能读且关库重开不丢；伪造「版本 28 但缺列」的
文件靠 `_ensureColumns` 补列后可读可写、0 与 NULL 区分；越界分钟抛 `ArgumentError` 且不写库；
`nextDueAtAfter` 只认严格更大、恰好等于的时刻不算、NULL `due_at` 不当未来时刻、没有更晚到期返回 null。

## 18. v29：标签树排序方式（`local_settings.tag_tree_sort_mode`，轮次一百三十八）

标签树的三种排序（字典序 / 按内容量 / 按添加时间）此前只在本次会话内记住，重启就回到字典序。
v29 给单行设置表加一列可空文本，把用户最后选的档位落盘；不新建表、不动标签树本身。

| 改动 | 类型 | 语义 |
| --- | --- | --- |
| `local_settings.tag_tree_sort_mode` | TEXT，可空 | 标签树同层排序方式，存域层 `TagTreeSortMode.code`：`alphabetical` / `object_count` / `created_at`。**NULL = 没选过，读作出厂「字典序」** |

**为什么存 code、不存中文**：中文标签（`labelZh`）是界面文案，改文案会把已存值变成读不懂的字符串；
code 是域层 `tag_tree_sort.dart` 的稳定机器编码，UI 显示名仍由域层/l10n 决定。

**读写口径**（`app/lib/data/repositories/settings_repository.dart`）：
- `getTagTreeSortMode()`：无设置行 / NULL → `null`；原样返回字符串，不翻译成枚举——
  仓库不 import 域层，语义翻译归读侧 `tagTreeSortModeFromStorage`（`tag_tree_view.dart:313`）。
- `updateTagTreeSortMode(String? mode)`：两端空白 trim；**空白串存成 NULL**（"空"不是第四种状态）；
  传 `null` = 恢复出厂排序。未知 code **不拒绝**：合法集合归域层管，未来版本写的模式这一版读不懂时
  由 `tagTreeSortModeFromStorage` 降级成字典序，不炸。写入要求设置行已存在（应用在启动时
  `SettingsController` 已 `ensureSettings`；测试需自己先建行）。

**迁移**：`_upgradeV28ToV29()` 对 `local_settings` `addColumnIfMissing` 一列（表不存在直接返回）；
`_ensureColumns()` 的 `local_settings` 列表加同一列做自愈（版本号已是 29 但老文件被盖掉时补列）。
迁移**不回填**：回填会把出厂字典序冻成一次用户选择，以后改出厂档位就达不到了（与
`goal_beta` / `review_reminder_minutes` 同一个契约）。`database.g.dart` 由
`dart run build_runner build --delete-conflicting-outputs` 重新生成（96 s，只 `LocalSettings` 表类/Companion 变化）。

**测试锁的事实**（`app/test/data/database/v29_migration_test.dart` 4 例 +
`settings_repository_test.dart` 排序方式组 3 例，共 +12 全绿）：
真实 v28 文件升级后老设置行读作没选过、升级后立刻能写能读、关库重开不丢；伪造「版本 29 但缺列」的
文件靠 `_ensureColumns` 补列后可读可写；空白串存成 NULL、未知 code 原样保留且读侧降级成字典序、
`null` 清回出厂；新库没有设置行时读作没选过。

## 19. v30：题目自定义题名（`questions.title`，轮次一百三十九）

题库总览要按名字扫读、要能重命名。此前题目没有名字列，界面只能拿题干前两行当标题——
同一种题型的开头往往一模一样（「已知函数 f(x)…」「如图所示…」），扫读全是重影，
也搜不出「那道传送带题」。v30 给 `questions` 加一列可空文本。

| 改动 | 类型 | 语义 |
| --- | --- | --- |
| `questions.title` | TEXT，可空 | 用户自己起的名字，或域层自动生成的短名。**NULL = 还没名字**，界面回落题干摘要 |

**为什么不每次从题干现算**：题干前 N 字不是名字——它不稳定（换排版/加公式就变）、不可改、
也不能表达「这道题考什么」。存成列之后才有「稳定、可改、可去重」的语义；自动生成只是**填空**，
写进去之后用户改过就不再被自动覆盖。长度（32）、去重后缀「（2）」、保留原名的边界归域层纯逻辑
`app/lib/domain/services/questions/question_title_suggestion.dart`，仓库不碰这些规则。

**读写口径**（`app/lib/data/repositories/question_repository.dart`）：
- `setQuestionTitle(String id, String? title)`：改一道题的名字，返回是否命中；不存在返回 `false`，不抛。
- `setQuestionTitles(Map<String, String?> titles)`：一次事务批量改，返回真正 UPDATE 命中的行数；
  key 空白/不存在的 id 静默跳过；没有任何有效条目时不写库、返回 0。
- 两个入口都只做存储归一：两端 `trim`；`null`、空串、全空白一律写 **NULL**（没有第三种空值），
  与 `source_url` 同一契约；**不在这里截断长度**——截断/去重是域层的事，仓库越权会让 UI 与
  自动命名拿到不同口径。

**迁移**：`_upgradeV29ToV30()` 对 `questions` `addColumnIfMissing` 一列（表不存在直接返回）；
`_ensureColumns()` 的 `questions` 块加同一列做自愈（版本号已是 30 但老文件被盖掉时补列）。
迁移**不回填**：回填会把一批由旧模型生成的短名冻在每一台老安装上，用户看不出「这是自动生成的」，
与 `review_reminder_minutes` / `goal_beta` 同一个契约。`database.g.dart` 由
`dart run build_runner build --delete-conflicting-outputs` 重新生成（71 s，`Questions`/`QuestionsCompanion` 变化）。

**测试锁的事实**（`app/test/data/database/v30_migration_test.dart` 3 例 +
`app/test/data/repositories/question_repository_title_test.dart` 5 例，共 +8 全绿）：
真实 v29 文件升级后老题目读作没有题名、升级后立刻能命名且关库重开不丢；伪造「版本 30 但缺列」的
文件靠 `_ensureColumns` 补列后可读可写；空白串清成 NULL、批量改名只统计命中行、不存在的 id 不抛；
`updatedAt` 由调用方给的时刻驱动；题名不影响题干指纹去重（第二次同题干仍返回 `created: false`）。

## 20. v31：多图/多页整理的来源照片清单（`handwriting_intake_runs.source_photos`，轮次一百四十八）

拍照整理一直是「一个 run = 一张照片」：run 的主键 `source_ref` 就是那张照片的相对路径。
要做「一次选 N 张、合并整理成一组成果」（多页连拍、同一题的正面/反面），run 的身份就不能
再等于某一张照片的路径了——否则选 3 张只能写出 3 条互不相干的 run。v31 给 run 表加一列可空
文本，存这组照片的清单。

| 改动 | 类型 | 语义 |
| --- | --- | --- |
| `handwriting_intake_runs.source_photos` | TEXT，可空 | JSON 字符串数组（照片相对路径，按用户选择顺序）。**NULL / `[]` = 单图 run**（`source_ref` 是照片路径）；非空 = 多图 run（`source_ref` 是 `multi:<id>`） |

**多图 run 的身份**：`multiSourceRefFor(List<String> relPaths)`（应用层
`app/lib/features/questions/application/handwriting_proposal_service.dart`）把路径**排序**后用
`\u0000` 连接，做 64 位 FNV-1a 变体（每步 `& 0x7FFFFFFFFFFFFFFF` 掩到 63 位），输出
`multi:<16 位十六进制>`。所以同一组照片无论选择顺序如何都得到同一个 id——重新整理同一组
是**整批替换**（仓库按 `source_ref` 删旧行再写新行），不会越整理越多；提案 id 同步是
`multi:<id>#<proposal_id>`，与单图 `<照片路径>#<proposal_id>` 同一命名契约。

**迁移**：`_upgradeV30ToV31()` 对 `handwriting_intake_runs` `addColumnIfMissing` 一列
（表不存在直接返回）；`_ensureColumns()` 的该表块加同一列做自愈（版本号已是 31 但老文件被盖掉时补列）；
`_tableFor()` 的 switch 也登记了这张表——自愈补列走 `m.addColumn(_tableFor(name), column)`，
漏登记会抛 `unknown table handwriting_intake_runs`（v31 迁移测试实测抓到过这个错误，补 case 后通过）。
迁移**不回填**：NULL 本来就是「单图」的正确读法，回填只会给老 run 造一条假清单。
`database.g.dart` 由 `dart run build_runner build --delete-conflicting-outputs` 重新生成（88 s，804 outputs）。

**读写口径**（`app/lib/data/repositories/handwriting_proposal_repository.dart`）：
- `HandwritingStoredRun.sourcePhotos` 默认 `const []`，`isMulti => sourcePhotos.isNotEmpty`；
- `saveRun(..., List<String> sourcePhotos = const [])`：空清单写 **NULL**（单图语义，不存 `[]`），
  非空才 `jsonEncode`；`runs()` / `runOf(sourceRef)` 读回时 `_decodeSourcePhotos` 解析；
- `_decodeSourcePhotos(String? raw)` 对坏 JSON / 非数组 / 数组里的非字符串与空白项一律**容忍**
  （降级成空清单 = 单图语义），不让一行坏数据把整条队列读崩。与 `source_url` 的「空串归 NULL、
  UI 与自动命名同一口径」是同一个原则。

**测试锁的事实**（`app/test/data/database/v31_migration_test.dart` 3 例全绿）：
真实 v30 文件升级后老 run 读作单图（`isMulti == false`）、升级后立刻能存多图清单且关库重开不丢；
伪造「版本 31 但缺 `source_photos` 列」的文件靠 `_ensureColumns` 补列后可读可写（这条会经过
`_tableFor`，是补 case 的直接来源）；坏 JSON / `[]` / 混入非字符串元素一律读成单图、不抛异常。
## 21. v32：题库「自测作答」记录（`question_attempts`，轮次一百五十五）

轮次一百五十四给题目详情页加了「自测」（选择题先作答、提交后判分），但判分结果只活在
`_QuestionBodyState` 的内存里：关掉详情页，这次做没做、对没对就没了。v32 给题库加一张
**只追加**的作答表，把「判分成功」的提交落下来，详情页读它显示「自测几次 / 对几次 / 最近一次」。

| 表 | 列 | 类型 | 语义 |
| --- | --- | --- | --- |
| `question_attempts` | `id` | TEXT PK | `Ids.next('qa')` |
| | `question_id` | TEXT references `questions(id)` | 作答的是哪道题 |
| | `selected_labels` | TEXT，默认 `'[]'` | JSON 字符串数组，已归一化（trim → 大写 → 去空 → 去重 → 升序） |
| | `is_correct` | BOOL，非空 | 这次判对了吗；只存判分成功的作答，所以不需要「NULL = 没判过」 |
| | `attempted_at` | INT，非空 | 提交时刻（epoch ms） |

**口径**（表定义 `app/lib/data/database/tables.dart:1595-1617`）：
- 一行 = 一次**判分成功**的提交；空选（`emptySelection`）、非客观题（`notObjective`）根本不落库，
  否则「做过几次」会被误触的次数污染。
- **只追加**：改答案、重做一遍都是新行；历史是既成事实，不更新也不覆盖。
- 与 `review_logs` 分开：那是闪存卡复习测试（参与调度），这里是题库里点开一道题自己先做一遍的
  学习痕迹，**不参与任何调度与排序权重**。
- 归一化落在 `QuestionAttemptRepository.encodeSelectedLabels()`（`app/lib/data/repositories/question_attempt_repository.dart:83`），
  不交给调用方：界面传进来的 label 可能带空格或大小写不同，存进去的形状必须唯一。
- 排序口径两处各写一次且必须相同：**`attempted_at` 降序，同一毫秒按 `id` 升序**
  （SQL 在 `historyFor`，领域层在 `QuestionAttemptHistory.fromEntries`）。

**迁移**：`_upgradeV31ToV32()`（`app/lib/data/database/database.dart:916`）表已存在直接返回，
否则 `Migrator.createTable(questionAttempts)`；`_ensureColumns()` 自愈（:419）在版本号已是 32
但表被盖没时补建；`schemaVersion => 32`（:115）。`database.g.dart` 由
`dart run build_runner build --delete-conflicting-outputs` 重新生成（57 s、814 outputs）。
本迁移只新建表、**不改已有表的任何列**，所以没有回填问题。

**删题连带清理**：本项目不用外键级联，`QuestionRepository.deleteQuestion()` 的事务里显式补一行
`await (_db.delete(_db.questionAttempts)..where((t) => t.questionId.equals(id))).go();`
（`app/lib/data/repositories/question_repository.dart:764`，在 objectTags 之后、questions 之前）。

**读写接口**（`app/lib/data/repositories/question_attempt_repository.dart`）：
- `record({questionId, selectedLabels, isCorrect, DateTime? now})`（:22）→ 插入一行并返回 id；
- `historyFor(questionId, {limit = 200})`（:46）→ 新→旧的 `QuestionAttemptEntry` 列表；
  `limit <= 0` 直接返回空表（不先去数据库拿一行再丢掉）；
- `deleteForQuestion(questionId)`（:73）→ 删除行数（删题事务内部用）。
- provider：`questionAttemptRepositoryProvider`（`app/lib/data/repositories/repository_providers.dart:102`）；
  详情页只读视图 `questionAttemptHistoryProvider`（`app/lib/features/questions/presentation/question_detail_providers.dart:55`，
  `FutureProvider.autoDispose.family` + `ref.watchDatabaseRevision()`，写库后自动重读）。

**测试锁的事实**（`app/test/data/database/v32_migration_test.dart` 4 例、
`app/test/data/repositories/question_attempt_repository_test.dart` 6 例、
`app/test/domain/services/questions/attempt_history_test.dart` 16 例，全绿）：
- 真实 v31 文件升级后 `user_version` = 32、原题还在、作答表可写可读且关库重开不丢；
- 被盖成「版本 32 但缺 `question_attempts` 表」的老文件靠 `_ensureColumns` 自愈建表，可写可读；
- v30 老库一路升到 32（同一次迁移里 v30→v31 补 `source_photos`、v31→v32 建表都生效）；
- 健康 v32 库重开不重建表、行还在；
- 仓储层：label 归一化 `[' b','a ','A','']` → `["A","B"]`、`attempted_at` 是 epoch 毫秒、
  新→旧排序、同毫秒按 id 升序、limit 生效、`deleteForQuestion` 只删该题、
  `deleteQuestion` 连带清空该题作答且不碰别的题。

## 22. v33：题目编号高水位（`question_serial_counters`，轮次一百六十三）

`docs/QUESTION_BANK_DESIGN.md` §11.1 的诚实清单②：分配规则是「现存最大 + 1」，删掉最大号那道题后号会被下一道题接手，「发出即永久保留」没做到。v33 加一张**单行**高水位表补上：分配改成 `max(现存最大号, 历史最大发放号) + 1`，并把发放号回写。题号从「尽量不回收」变成「不回收」。

| 表 | 列 | 类型 | 语义 |
| --- | --- | --- | --- |
| `question_serial_counters` | `id` | INT PK | 固定 1（单行表，`app/lib/data/database/tables.dart:1630`） |
| | `last_issued` | INT，非空 | 这个库发出去过的最大题号（>= 1） |

**为什么单独一张表、而不是塞 `local_settings`**：这一行只被题库写入（`ingest` 的事务里），与设置项没有语义关系；「没有这一行」在这里正好表达「老库还没记过高水位」，分配器退回旧行为。

**分配**（`QuestionRepository.ingest`，`app/lib/data/repositories/question_repository.dart:206-218`，全在同一个事务里）：

- 读 `MAX(serial_no)`（原逻辑，不变）；
- 读 `question_serial_counters` 第 1 行（可能没有）；
- `allocateQuestionSerial(highestExisting: MAX, lastIssued: counter?.lastIssued)`（`app/lib/domain/services/questions/question_serial_allocator.dart:37`）：合法候选（>= 1）取最大者 M，都没有 → 1，否则 M + 1；M 达到 `kMaxAllocatableQuestionSerial = 999999999`（:27，与题号检索 9 位上限对齐）时饱和返回上限、不回绕负数；
- `insertOnConflictUpdate(id: 1, lastIssued: serialNo)` 回写高水位。

**迁移**：`_upgradeV32ToV33()`（`app/lib/data/database/database.dart:946`）表不存在就 `Migrator.createTable(questionSerialCounters)`，然后**把高水位抬到现存最大号**（`_raiseQuestionSerialHighWaterToCurrentMax()` :1252）——否则升级后先删最大号那题、再入库，号仍会被接手；`_ensureColumns()` 自愈（:433）在版本号已是 33 但表被盖没时补建（否则第一次 `ingest` 就 no such table，一道题也存不进去）；`schemaVersion => 33`（:121）。**历史不回填**：迁移前删掉的号已经无从知道，能做的只是把「现存的曾经发出去过的号」抬进高水位。

**包导入**：`.tfpkg` 导入结束后统一调 `backfillQuestionSerialNumbers()`（:1219）补空号；带号的题（v24 包）一行不动，但补号结束会把高水位抬到现存最大号（:1232/:1244 两处出口都调同一个 helper），所以「带号导入 → 删掉那题 → 入库」也不会接手旧号。

**为什么不会退化成 `MAX`**：`ingest` 每次都会写高水位；即使高水位行被手工清空，下一次 ingest 又按 `max(现存, 空)` 起算并写回。

**测试锁的事实**（`app/test/data/database/v33_migration_test.dart` 5 例、`app/test/data/repositories/question_repository_test.dart` 16 例、`app/test/domain/services/questions/question_serial_allocator_test.dart` 21 例）：

- 真实 v32 文件升级后 `user_version` = 33、老题原样在、高水位被抬到现存最大号；第一次 ingest 把高水位写成 2，删掉最大号那题后下一题拿 3，重开后还有效；
- 升级后**还没入库**就先删掉最大号那题，下一题仍拿「旧最大号 + 1」（seed 生效的证明）；
- 模拟 v24 包向题库写一个大号，导入后补号把高水位抬上去，删掉这道带号题再入库也不接手；
- 被盖成「版本 33 但缺 `question_serial_counters` 表」的老文件靠 `_ensureColumns` 自愈建表；
- v31 老库一路升到 33（v31→v32 建作答表与 v32→v33 建高水位表都生效）；
- 没有高水位行时退回「现存最大 + 1」，这次分配后把高水位写进去；并发 `Future.wait` 6 道题不撞号。



## 23. v34：题库列表排序偏好（`local_settings.question_library_sort_mode`，轮次一百六十八）

题库页的排序菜单（最新 / 按题号 / 错题优先）原先只活在页面 State 里：关掉应用再进去又回到「最新」，
用户每次重启都要重选一遍（`docs/QUESTION_BANK_DESIGN.md` §42.3 明写的边界）。v34 给单行设置表加一列可空文本，
把用户的选择落下来。

| 改动 | 类型 | 语义 |
| --- | --- | --- |
| `local_settings.question_library_sort_mode` | TEXT，可空 | 稳定 encode：`newest` / `serial` / `wrong_first`。**NULL = 用户没选过**，读作出厂档位「最新在前」 |

**为什么存 encode 不存中文**：改文案不会让已存值变成读不懂的字符串，换语言之后读回来的还是同一个档位；
encode 一经发出就不再改（改了等于把老安装的选择变成「未知值」）。翻译在应用层：
`String questionLibrarySortCode(QuestionLibrarySort sort)` 与
`QuestionLibrarySort questionLibrarySortFromStorage(String? code)`
（`app/lib/features/questions/application/question_library_sort.dart`），NULL / 空串 / 未知 code 一律降级成
`newest`——「没选过」与「未来版本才认识的档位」读出来是同一个行为，不报错、不换档。

**迁移**：`_upgradeV33ToV34()`（`app/lib/data/database/database.dart:975-983`）对 `local_settings`
`addColumnIfMissing` 一列（表不存在直接返回）；`_ensureColumns()` 的 `local_settings` 列表加同一列做自愈
（:299，版本号已是 34 但老文件被盖掉时补列）；`schemaVersion => 34`（:125）。迁移**不回填**：
回填会把出厂档位冻成一次明确的用户选择，以后改出厂排序就达不到了（与 `tag_tree_sort_mode` /
`review_reminder_minutes` / `goal_beta` 同一个契约）。本迁移只加列、不改既有行，因此老库升级后
`getQuestionLibrarySortMode()` 读作 NULL。

**读写接口**（`app/lib/data/repositories/settings_repository.dart`）：
- `Future<String?> getQuestionLibrarySortMode()`：`getSettings()?.questionLibrarySortMode`（没有设置行 → NULL，
  读侧兜底，不靠迁移补行）；
- `Future<void> updateQuestionLibrarySortMode(String? mode)`：先 `ensureSettings()`（设置行是懒创建的，
  不先确保行存在会写 0 行、丢掉用户选择），code `trim()` 后为空写 **NULL**（空白不是第四种状态），
  非空原样写（未知 code 不拒绝——由读侧降级），并刷新 `updatedAt`。
- provider：`questionLibrarySortPreferenceProvider`（`app/lib/features/questions/application/question_library_sort_preference.dart`，
  `FutureProvider.autoDispose` + `ref.watchDatabaseRevision()`，写库后自动重读，页面不必手动 invalidate）。

**测试锁的事实**（`app/test/data/database/v34_migration_test.dart` 4 例、
`app/test/features/questions/application/question_library_sort_test.dart` 的 codec 3 例，全绿）：
- 真实 v33 文件升级后 `user_version` = 34、老设置行读作「没选过」（NULL → `newest`）、升级后立刻能写能读、
  关库重开值还在；
- 被盖成「版本 34 但缺 `question_library_sort_mode` 列」的老文件靠 `_ensureColumns` 补列，可读可写；
- 空白串存成 NULL；未知 code 不被拒，读侧降级成 `newest`；传 `null` = 恢复出厂；
- codec：三种档位 encode 稳定且可原样读回，两端空白 trim 后仍认得。

## 24. v35：用户自我描述 persona（`local_settings.user_persona`，轮次一百七十二）

用户要一个"自己描述自己"的 persona（见 `docs/PERSONA_DESIGN.md`）。v35 给单行设置表加
一列可空长文本，存**用户的原话**，不存模型抽取的结构化档案。

| 改动 | 类型 | 语义 |
| --- | --- | --- |
| `local_settings.user_persona` | TEXT，可空 | 归一化后的用户原文（最多 8000 字，**存储层不截断**）。**NULL = 没写过**；空白文本在仓库层就写成 NULL，所以"没写"只有一种表示 |

**为什么存原话、不在迁移里回填**：回填会把一个迁移瞬间并不存在的"自我描述"变成一行
用户从没写过的文本（与 `tag_tree_sort_mode` / `review_reminder_minutes` / `goal_beta`
同一契约：只加列、不改既有行）。老库升级后 `getUserPersona()` 读作 NULL。

**迁移**：`_upgradeV34ToV35()`（`app/lib/data/database/database.dart:1003-1010`）对
`local_settings` `addColumnIfMissing` 一列（表不存在直接返回）；`_ensureColumns()` 的
`local_settings` 列表加同一列做自愈（:310，版本号已是 35 但老文件被盖掉时补列）；
`schemaVersion => 35`（:129）；onUpgrade 链 :238 `if (from < 35) await _upgradeV34ToV35();`。
`database.g.dart` 由 `dart run build_runner build --delete-conflicting-outputs` 重新生成
（145s、803 outputs）。

**读写接口**（`app/lib/data/repositories/settings_repository.dart`）：
- `Future<String?> getUserPersona()`（:296）：`getSettings()?.userPersona`（没有设置行 →
  NULL，读侧兜底，不靠迁移补行）；原样返回，不做归一化——仓库不 import 域层；
- `Future<void> updateUserPersona(String? text)`（:308）：先 `ensureSettings()`（设置行懒
  创建，不先确保会写 0 行、丢掉用户输入），`trim()` 后空或 `null` 写 **NULL**，非空原样写
  （未知内容不拒绝），刷新 `updatedAt`。**不在仓库层截断长度**：静默截断会丢用户的话，
  超长由编辑页用域层 `userPersonaTooLong` 拦。
- provider：`userPersonaProvider`（`app/lib/features/settings/application/user_persona_provider.dart`，
  `FutureProvider.autoDispose<String?>` + `ref.watchDatabaseRevision()`，返回归一化文本，
  空 → NULL；写库后自动重读，页面不必手动 invalidate）。

**领域契约**：`app/lib/domain/services/cognitive/user_persona.dart`（`normalizeUserPersona` /
`userPersonaForStorage` / `userPersonaIsPresent` / `userPersonaTooLong` /
`userPersonaPromptBlock` / `userPersonaPreview`；引导行与 8000 上限见
`docs/PERSONA_DESIGN.md` §3）。注入位置（AI 对话系统提示、日期之后规则之前、空 persona
逐字节不变）见同文档 §5。

**测试锁的事实**（`app/test/data/database/v35_migration_test.dart` 4 例，全绿）：
- 真实 v34 文件（`PRAGMA user_version=34` 且 `local_settings` 无 `user_persona` 列）
  升级后 `user_version` = 35、`getUserPersona()` 读作 NULL、升级后立刻能写能读且关库
  重开值还在；
- 被盖成「版本 35 但缺 `user_persona` 列」的老文件靠 `_ensureColumns` 补列，可读可写；
- 空白串存成 NULL；超长（8001 字）**原样保留不截断**；传 `null` = 清除；
- 新库没有设置行时读作 NULL（不自动建行）。

---

## 25. v36：两个用户可调的显示/排期偏好（`local_settings.review_retention` + `time_view_settings.hour_height`，轮次一百七十五）

来源：`docs/REVIEW_FEEDBACK.md` 第 6 条（Time 行高应可自由拖拽缩放）与第 14 条
（闪存卡间隔太短：目标记忆保持率不可调）。两列一起进 v36：都是「用户调一次、之后
每次读」的偏好，都放在已有的单行设置表里，都不需要回填。

| 改动 | 类型 | 语义 |
| --- | --- | --- |
| `local_settings.review_retention` | REAL，可空 | 目标记忆保持率（0.75–0.95 的合法区间由域层夹）。**NULL = 没设过**，读作 `kDefaultReviewRetention`（0.85）。值越小 → FSRS 的 `intervalModifier` 越大 → 间隔越长 |
| `time_view_settings.hour_height` | REAL，可空 | Time 日/周网格**每小时的像素高度**（连续值，不是旧的三挡 `minutesPerRow`）。**NULL = 没拖过**，行高按旧公式 `44 * (60 / minutesPerRow)` 推——行为与这一列存在之前逐字节相同 |

**为什么 NULL 不落默认值**：回填会把「今天的出厂值」冻进每一台已有安装，以后改默认
（例如把 0.85 调成 0.88）老用户就永远收不到；语义上「没设过」与「显式选了 0.85」也
不是同一件事（`ReviewSpacing.standard.retention == 0.85` 但两者走的分支不同：前者
每次读都可能变，后者固定）。

**迁移**：`_upgradeV35ToV36()`（`app/lib/data/database/database.dart:1036-1046`）
对两张表各 `_addColumnIfMissing` 一列（表不存在直接跳过）；`_ensureColumns()` 的
`time_view_settings` 列表加 `hourHeight`（:280）、`local_settings` 列表加
`reviewRetention`（:328）做自愈（版本号已是 36 但老文件被盖掉时补列）；
`schemaVersion => 36`（:134）；onUpgrade 链 :246 `if (from < 36) await _upgradeV35ToV36();`。
`database.g.dart` 由 `dart run build_runner build --delete-conflicting-outputs` 重新生成。

**读写接口**：

- 保持率 —— `app/lib/data/repositories/settings_repository.dart`：
  `Future<double?> getReviewRetention()`（:327）= `getSettings()?.reviewRetention`，
  **原样返回**；`Future<void> updateReviewRetention(double? retention)`（:338）先
  `ensureSettings()`（设置行懒创建，不先确保会写 0 行）再写值，传 `null` = 回到出厂。
  仓库**不校验范围**（合法集合是域层契约），不偷偷改写用户的选择。
- 行高 —— `app/lib/data/repositories/time_template_repository.dart` 的
  `TimeViewRepository`：`get()`（:208）返回整行或 null；`update({..., double? hourHeight})`
  （:226，:250 写列）；`clearHourHeight()`（:260）写**真正的 NULL**——`update(hourHeight: null)`
  在 `Value.absent()` 的写法里表示「本次不改」，清空必须走单独方法。
- provider：`reviewRetentionProvider`（`app/lib/features/anki/application/review_retention_provider.dart`，
  `FutureProvider.autoDispose<ReviewSpacing>` + `selectReviewSpacing()` 写库后 invalidate）。

**领域契约**：

- `app/lib/domain/services/srs/review_retention.dart`：`kDefaultReviewRetention=0.85`、
  `kReviewRetentionMin=0.75`、`kReviewRetentionMax=0.95`；
  `enum ReviewSpacing { longer(0.80), standard(0.85), shorter(0.90) }` 三挡 UI
  （`longer` = 间隔更长）；`fromRetention()` 用中点（0.825/0.875）把任意存量值映射回挡位；
  `normalizeReviewRetention()` 把 null/NaN/∞ 读作 0.85、越界夹到 0.75–0.95。
  消费方 `ReviewService.grade()` 每次判分读一次 `FsrsParameters(requestRetention: ...)`，
  读库失败回落到默认参数（不阻断判分）。
- 行高吸附：`app/lib/features/timeboard/presentation/calendar_page.dart` 的
  `snapCalendarHourHeight()`（:51）把拖动结果夹到区间并吸附挡位，页面用
  `_hourHeight`（:109）优先、NULL 时回落旧公式（:113-114）。

**测试锁的事实**（`app/test/data/database/v36_migration_test.dart` 3 例，全绿）：
- 真实 v35 文件（`PRAGMA user_version=35` 且两列被 DROP）升级后两处读作 NULL /
  没拖过，升级后立刻能写能读、关库重开值还在（0.9 / 120）；
- 被盖成「版本 36 但缺两列」的老文件靠 `_ensureColumns` 补列，可读可写；
- `clearHourHeight()` 写回真 NULL；越界保持率（0.99）仓库原样存读，夹取只发生在
  `normalizeReviewRetention`（读回 0.95）；`updateReviewRetention(null)` 清回没设过。

---

## 26. schema v37（2026-10-25，轮次一百七十六）：标签用途声明 `tags.usage_codes`

对应 `docs/REVIEW_FEEDBACK.md` §10（标签全局没有边界）与 §11（时间表只应看到
「纳入时间表」那棵树）。目标不是给标签分会话/分区，而是**同一棵树按用途声明可见
集合**：时间表、题库、知识网络、任务、闪卡分别在标签选择器里只看自己那部分标签。

### 26.1 表结构

| 表 | 列 | 类型 | 语义 |
| --- | --- | --- | --- |
| `tags` | `usage_codes` | TEXT，可空 | 这一级声明的用途 code，逗号分隔 |

- 列定义 `app/lib/data/database/tables.dart:213`（注释 :209-212）。
- 取值只允许五个稳定 code：`time` / `question` / `knowledge` / `task` /
  `flashcard`（=`TagUsage` 枚举声明序；不存中文、不存枚举序号）。
- `NULL` = 这一级没有声明（用途从最近的声明祖先继承）；整条链都没声明 =
  **不限制**（所有地方都能用这个标签）。
- 空集合由编码器写成 `NULL`；手写/坏数据里的空串或全认不出的 code 解码成
  `null`，即「没有声明」。**非 null 空集也按没有声明处理**，不让坏数据意外截断
  继承链（`tag_usage.dart:70-73` 的契约）。

### 26.2 为什么是一列而不是新表

- 声明挂在标签行上，生命周期跟着标签走：删标签/移动标签不需要同步第二张表。
- 继承在**读取时**按 `parent_id` 向上找第一个非空声明，因此移动子树、改名、
  调整层级都不需要重写任何子标签的声明。
- 没有新表 = 没有外键、没有级联删除、没有 `_tableFor` 之外的新映射。

### 26.3 迁移

- `app/lib/data/database/database.dart:139` `schemaVersion => 37`；
  onUpgrade 链 :253-255 `if (from < 37) await _upgradeV36ToV37();`；
  迁移函数 :1067-1073（表不存在直接 return，否则 `_addColumnIfMissing(m, 'tags',
  tags.usageCodes)`——**只补列、不回填**，回填等于凭空给用户写一条从没做过的
  声明，会把「不限制」变成硬边界，与 v34/v35/v36 同一契约）。
- 自愈：`_ensureColumns()` 的 expected map 加 `'tags': [tags.usageCodes]`
  （:280）；自愈补列会调 `_tableFor('tags')`，所以 v37 同时给
  `_tableFor` 加 `case 'tags': return tags;`（:1309）。**这是 v37 首跑迁移测试
  踩到的坑**：`Invalid argument(s): unknown table tags`——新增表/列进自愈列表时
  必须同步登记 `_tableFor`。
- `database.g.dart` 用 `dart run build_runner build --delete-conflicting-outputs`
  重新生成（89s，904 outputs）。
- doc 注释的迁移函数链（:115）末尾追加 `_upgradeV36ToV37`。

### 26.4 领域契约（`app/lib/domain/services/tags/tag_usage.dart`）

- `enum TagUsage {time,question,knowledge,task,flashcard}`（:11），`.code` 是
  落库值，`fromCode()` 对未知 code 返回 null（:24-29）。
- `String? encodeTagUsageCodes(Iterable<TagUsage>)`（:35）：空集合 → `null`，
  输出顺序固定为枚举声明序（同一集合永远同一串，便于测试与 diff）。
- `Set<TagUsage>? decodeTagUsageCodes(String?)`（:46）：null/空串/全未知 → null，
  容忍空格，大小写敏感。
- `class TagUsageNode{id, parentId, Set<TagUsage>? declaredUsages}`（:59）是解析
  快照；`declaredUsages` 用 `UnmodifiableSetView` 包装。
- `class TagUsageResolver`（:79）构造即不可变、对未知 id 安全（返回 null/true）：
  `nodeOf` / `declaredFor`（本级声明）/ `effectiveFor`（最近声明祖先的集合，null=
  不限制）/ `effectiveSourceTagId`（哪个标签提供了生效声明，UI 可标「继承自」）/
  `hasAnyDeclaration` / `declaredTagCount` / `isVisibleFor` /
  `visibleTagIdsFor` / `visibleOf(ids, usage)`（保持原顺序过滤）；成环保护：
  沿父链第二次遇到同一 id 返回 null，不挂 UI。

### 26.5 读写接口

- `TagRepository`（`app/lib/data/repositories/tag_repository.dart`）：
  `TagUsageResolver resolverFor(Iterable<Tag> tags)`（:109，纯映射）；
  `Future<void> updateTagUsageCodes(String tagId, Set<TagUsage> usages)`（:122，
  写 `usageCodes` + `updatedAt`，空集合写回 `NULL`；**不级联子标签**，继承读侧算）。
- 应用层 `app/lib/features/tags/application/tag_usage_providers.dart`：
  `tagUsageResolverProvider`（:12，`FutureProvider.autoDispose`，watch
  `databaseRevision` + `getAllTags()`，任何写库自动重算）；
  `setTagUsages(WidgetRef, tagId, usages)`（:23，写库后 invalidate；失败原样上抛，
  由对话框提示）。

### 26.6 测试锁的事实

- `app/test/domain/services/tags/tag_usage_test.dart` **23 例**：编码/解码 8
  （空集合→null、顺序稳定、未知 code 忽略、空格/空串容忍、非 null 空集按无声明）；
  继承解析 12（本级优先、继承最近祖先、断链返回 null、环保护、declaredTagCount、
  effectiveSourceTagId）；过滤 3（visibleOf 保持顺序、isVisibleFor 对未知 id 为 true）。
- `app/test/data/database/v37_migration_test.dart` **3 例**：真实 v36 文件（建 tags
  两行 → `ALTER TABLE tags DROP COLUMN usage_codes` → `PRAGMA user_version=36`）
  升级后两行还在、`usageCodes` 读 null（不限制）→ 写 `{time}` 后子标签继承 →
  关库重开还在；写空集合写回 `NULL` 恢复继承；被盖成「版本 37 但缺列」时靠
  `_ensureColumns` 自愈（`getAllTags()` 不抛、能写）。
- 实测：`flutter test test/domain/services/tags/tag_usage_test.dart
  test/data/database/v37_migration_test.dart --concurrency=1` → `+23: All tests
  passed!`。

### 26.7 边界（截至本版）

- UI 消费才起步：时间表标签选择器与标签树「用途边界」对话框是第一批；题库/知识
  网络/任务/闪卡的选择器还没接 `isVisibleFor`（默认不限制，行为与改动前一致）。
- 声明只影响**选择器可见性**，不迁移、不隐藏已经挂上去的标签关系（历史数据照旧）。
- 没有「批量给一棵子树设用途」的入口：一次一个标签；继承让常见的「根上开一次」
  够用。
- 没有权限/多用户概念：这是本地单用户库，用途只是显示口径。

