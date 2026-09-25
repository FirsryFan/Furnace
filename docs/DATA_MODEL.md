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
