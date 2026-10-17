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

