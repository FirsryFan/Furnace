# 知识包格式与分享机制

> 工作名：知序 Furnace（历史工作名；产品定稿：**Furnace**，见 [FURNACE_SPEC.md](FURNACE_SPEC.md)）
> 格式：`.kpak`＝分享子集格式（v1 基线，见本文第 1–6 节）；`.tfpkg`＝Furnace 全量工作区格式（定稿，见本文第 7 节）
> 目标：让同学之间方便地分享“知识点库”，且不泄露个人数据。
> 定稿依据：D4（`.kpak` 与 `.tfpkg` 双轨）、D13（主题 JSON）；实体命名、决策编号与格式草案一律以 [GAP_ANALYSIS.md](GAP_ANALYSIS.md)（§3 表清单、§5 `.tfpkg` 草案）为准，本文件不私造版本。

---

## 1. 为什么用文件包

- 不需要服务器、账号、网络。
- 和网盘/QQ/微信/U 盘完全兼容。
- 一个文件就是一个完整知识库，版本清晰。
- 导入后本地生成背诵内容，完全离线可用。

---

## 2. 包结构

```
xxx.kpak
├── manifest.json          # 必需：包元数据与内容清单
├── assets/                # 可选：图片、音频等附件
│   └── ...
└── [保留目录]              # 后续扩展：模板、样式等
```

`manifest.json` 顶层字段：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| formatVersion | int | 是 | 格式版本，当前为 1 |
| packageId | string | 是 | 包唯一 ID（UUID） |
| name | string | 是 | 知识包名称 |
| version | string | 是 | 语义化版本，如 `1.0.0` |
| author | string | 是 | 作者显示名 |
| exportedAt | string | 是 | ISO8601 导出时间 |
| description | string | 否 | 包说明 |
| tags | array | 否 | 标签列表 |
| knowledgePoints | array | 否 | 知识点列表 |
| mindMaps | array | 否 | 思维导图列表 |

### 2.1 Tag 对象

```json
{
  "id": "tag-1",
  "name": "光合作用",
  "color": 4283215696,
  "description": "高中生物必修一"
}
```

### 2.2 KnowledgePoint 对象

```json
{
  "id": "kp-1",
  "title": "光合作用场所",
  "content": "光合作用主要场所是叶绿体。",
  "source": "生物必修一 P.xx",
  "tags": ["tag-1"],
  "templates": [
    {
      "id": "tpl-1",
      "type": "fill_blank",
      "question": "光合作用的主要场所是___。",
      "answer": "叶绿体"
    },
    {
      "id": "tpl-2",
      "type": "mcq",
      "question": "光合作用的主要场所是？",
      "options": ["叶绿体", "线粒体", "核糖体", "高尔基体"],
      "answer": "叶绿体"
    },
    {
      "id": "tpl-3",
      "type": "essay",
      "question": "请简述光合作用的主要场所及其功能。",
      "answer": "叶绿体是光合作用的主要场所，内含叶绿素，能吸收光能并将二氧化碳和水转化为有机物和氧气。"
    }
  ]
}
```

模板字段说明：

- `type`：
  - `mcq`：选择题，需提供 `options`（至少 2 个），`answer` 为正确选项文本。
  - `fill_blank`：填空题，`question` 中用 `___` 表示挖空位置，`answer` 为填空答案。
  - `essay`：大题，只提供 `question` 和 `answer`，复习时不给输入框。
- 一个知识点可以有多个模板，背诵时自动选择其中一个。
- 自动挖空：如果某个知识点没有模板，导入器可基于 `content` 自动生成一个 `fill_blank` 模板（用标题或关键词挖空）。这是后续“智能挖空”的增强点。

### 2.3 MindMap 对象（可选）

```json
{
  "id": "map-1",
  "title": "光合作用",
  "nodes": [
    {
      "id": "node-1",
      "parentId": null,
      "text": "光合作用",
      "notes": "",
      "isTag": true,
      "tagId": "tag-1",
      "children": [
        {
          "id": "node-2",
          "parentId": "node-1",
          "text": "场所",
          "isTag": false,
          "children": []
        }
      ]
    }
  ]
}
```

---

## 3. 导入规则

1. 用户选择 `.kpak` 文件。
2. 校验 `formatVersion`，不兼容则提示。
3. 显示包名、作者、版本、内容统计（知识点数/卡片数/标签数）。
4. 用户确认后导入：
   - 标签：按 `packageId + tag.id` 去重。
   - 知识点：按 `packageId + knowledgePoint.id` 去重，升级时更新内容，但**不重置**已存在的 CardState 复习进度。
   - 模板：同样按 `packageId + template.id` 去重；新增模板自动创建新的 CardState。
   - 思维导图：按 `packageId + map.id` 去重，升级时整体替换该导图内容。
5. 导入完成后提示“可在背诵填空/思维导图中查看”。

---

## 4. 导出规则

1. 用户选择要导出的范围：全部或按标签/知识点/导图筛选。
2. 导出内容只包含：
   - 选中的知识点及其模板；
   - 相关标签；
   - 选中的思维导图；
   - 可选附件。
3. **绝不导出**：
   - 个人任务、子任务、依赖、提醒；
   - 个人时间块；
   - 复习进度（CardState、ReviewLog）；
   - 本地设置、个人档案。
4. 生成 `.kpak` 文件，文件名建议：`{包名}-v{版本}.kpak`。

---

## 5. 版本与升级

- 包内 `packageId` 不变、`version` 升高 → 视为升级。
- 升级只更新“知识内容”，不覆盖本地个人复习进度。
- 如果 `packageId` 相同但 `version` 降低，提示“旧版本”，由用户决定是否仍要导入。

---

## 6. 后续增强（暂不做）

- ~~知识包加密：可选密码，使用 AES 加密内容。~~ → **已勾销定案：`.kpak` 仍不做加密**（班级分享子集保持公开轻量语义）；加密能力由 `.tfpkg` 承载——可选密码 AES-GCM，见第 7 节。
- 签名校验：作者私钥签名，防止包被篡改。
- 局域网直传：同一 WiFi 下自动发现并发送包。
- 增量更新：只下载变更部分。

---

## 7. `.tfpkg` 全量工作区格式（Furnace 定稿）

> 本节为 [GAP_ANALYSIS.md](GAP_ANALYSIS.md) §5 草案的展开与落稿，是 `.tfpkg` 的完整可实现格式规格。决策依据：定稿 [FURNACE_SPEC.md](FURNACE_SPEC.md) §3（数据持久化与打包传输）、D4（双轨打包）、D13（主题 JSON）；实体键与表名与 GAP §3 变更清单对齐，行内字段定义以 DATA_MODEL v2 节为准（只读引用），本节不逐字段重复。

### 7.1 定位与分工

- `.tfpkg`（Furnace Package）：**全量工作区打包**——SQLite 数据逻辑全量 + 附件 + 主题配置，压缩为单个文件；由**「导出工作区」**产生（定稿 §3）。
- 用途：**备份 / 迁移 / 整体传输**（换机、重装、归档、同用户多设备间合并）。
- 与 `.kpak` 分工（D4）：`.kpak`＝班级分享子集（本文第 1–6 节，不含个人数据）；`.tfpkg`＝**含全部个人数据**，不是分享格式——分享场景一律走 `.kpak`。
- 导出范围：整个工作区，无范围筛选概念（范围筛选是 `.kpak` 的行为）。
- 合并模式：导入时提供「**覆盖**」与「**追加**」两种选项（定稿 §3）。

### 7.2 包结构

```
{workspace}-{yyyyMMdd-HHmm}.tfpkg
├── manifest.json      # 必需：格式头 + 全量逻辑转储（JSON）
├── attachments/       # 附件原字节（与 manifest.attachments 清单一一对应）
└── themes/            # 主题 JSON 文件（D13 主题文件语义，可独立导入；内容为 entities.Themes 各行 payload 的副本）
```

- 压缩：zip（archive 库），压缩默认开。
- 加密包（用户设密码时）在顶层额外含明文信封条目 `crypto.json`，见 §7.5；无 README 等其他条目（GAP §5）。
- `manifest.formatVersion`：int，当前 = **1**。

### 7.3 manifest 约定：全量逻辑转储

`manifest.json` 顶层字段：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| formatVersion | int | 是 | 格式版本，当前 = 1 |
| exportedAt | string | 是 | ISO8601 导出时间 |
| workspaceName | string | 是 | 工作区名（导入预览、默认备份文件名用） |
| appVersion | string | 否 | 导出端应用版本（兼容提示/审计用） |
| entities | object | 是 | 全量逻辑转储：键＝下表「转储键」，值为该实体行数组（空数组可省略键） |
| attachments | array | 否 | 附件清单：relPath、sha256、sizeBytes、mime、owner 信息（见下） |

**转储是逻辑 JSON 转储，不是裸拷 `.db` 文件。** 承载的实体类别清单（键名与 GAP_ANALYSIS §3 表变更清单对齐；保留表沿用 DATA_MODEL 既有表名）：

| 实体类别 | 转储键（hub 命名） | 转储内容与说明 |
| --- | --- | --- |
| 个人档案（profiles） | `Profile` | 本地用户档案 |
| 本地设置（settings） | `LocalSettings` | language 等；themeMode 语义已移交 Themes（GAP §3） |
| Thread 状态（thread-state） | `ThreadStates` | energy(1–10)、goal_text、goal_node_id、goal_path、updated_at |
| 标签（tags） | `Tags`（含对象-标签关联 `ObjectTag`） | 树形 parent_id/path；任务/日程块等对象的标签关联行随附，保证标签关系可恢复 |
| 任务与子任务/依赖/提醒（tasks） | `Tasks`、`TaskDependency` | expected_at/energy_required/completed_at；子任务（parent）、依赖、提醒（remind_at）等既有保留能力随附（GAP §2.1 保留行） |
| 完成记录（completions） | `CompletionLogs` | 疲劳惩罚与 Knowledge 上下文依赖的完成历史 |
| 任务模板（task-templates） | `TaskTemplates` | 名称+时长+标签+精力默认值 |
| 日程时间块（time-blocks，含 repeat） | `TimeBlocks` | repeat_rule 规则与 available 语义（D6） |
| 思维导图（mindmaps/nodes） | `MindMap`、`MindNode` | 节点树与连接关系 |
| 知识点（knowledge-points） | `KnowledgePoints`（含 .kpak 导入映射 `KnowledgePackage`/`PackageItem`） | content_format（plain/markdown）、external_id/package_id；导入映射随附，保证包升级判定跨机可恢复 |
| 卡片模板＝作者预设卡（card-templates） | `CardTemplates` | type 含 mcq/mcq_multi/ordered_multi/fill_blank/essay 等，clozeTemplate 保留兼容 |
| 挖空槽位与挖空历史（cloze-slots） | `ClozeSlots`、`ClozeHistory` | 槽位定义（位置/片段、exhausted 标记）＋已用槽位历史（自由挖空状态机数据） |
| 卡片状态＝呈现单元（card-states） | `CardStates` | (knowledge_point_id, slot_key) 唯一、FSRS 字段（stability/difficulty/due）、learning_forced 等状态 |
| 复习日志（review-logs） | `ReviewLogs` | rating_fsrs、response_seconds、mode、strict、correct |
| 图谱扩散提权（boost-entries） | `BoostEntries` | factor、remaining_cycles、created_at |
| 主题配置（themes） | `Themes` | 每行含 payload JSON（主/辅色、背景、透明度/图、字体、缩放、动画）；`themes/*.json`＝同内容副本 |
| 附件（attachments 清单） | `Attachments`（可选先建表）＋清单 | 清单登记于 manifest.attachments：relPath、sha256、sizeBytes、mime、ownerType/ownerId（表已建且有登记时）；实际字节在 `attachments/` |

示例骨架：

```json
{
  "formatVersion": 1,
  "exportedAt": "2026-09-01T10:00:00+08:00",
  "workspaceName": "高三复习",
  "appVersion": "1.0.0",
  "entities": {
    "Profile": [], "LocalSettings": [], "ThreadStates": [],
    "Tags": [], "ObjectTag": [], "Tasks": [], "TaskDependency": [],
    "CompletionLogs": [], "TaskTemplates": [], "TimeBlocks": [],
    "MindMap": [], "MindNode": [],
    "KnowledgePoints": [], "KnowledgePackage": [], "PackageItem": [],
    "CardTemplates": [], "ClozeSlots": [], "ClozeHistory": [],
    "CardStates": [], "ReviewLogs": [], "BoostEntries": [], "Themes": []
  },
  "attachments": [
    { "relPath": "attachments/kp-1/a.png", "sha256": "<hex>", "sizeBytes": 10240,
      "mime": "image/png", "ownerType": "knowledgePoint", "ownerId": "kp-…" }
  ]
}
```

**为什么不直接拷 sqlite 文件**：

- **合并粒度**：覆盖/追加的语义在「实体行」层面实现（本地数据并入、知识类按包升级去重），裸拷 `.db` 无法表达。
- **跨版本容错**：逻辑转储可按实体忽略未知字段、做逐实体迁移（v1→v2→…），SQLite 文件与 schema/内部结构强耦合，格式一升级即整体失效。
- **可审计**：JSON 可读、可 diff、可核对“包里到底有什么”——隐私清单、误导出排查、编解码测试都依赖这一层。
- 快照一致性取舍见 §7.6（单用户离线场景无需数据库文件级快照）。

### 7.4 导入与合并策略（覆盖 / 追加）

通用流程：

1. 用户选择 `.tfpkg` 文件。
2. 校验 `formatVersion`，不兼容则提示，不落任何数据。
3. 预览：workspaceName、导出时间、实体/附件统计、文件大小；**明示“全量、含全部个人数据”**（隐私文案见 [PRIVACY.md](PRIVACY.md) §3.2）。
4. 选择合并模式：**覆盖** 或 **追加**。
5. 完成后给出结果报告（新增/升级/跳过/保留本地的行数与附件数；覆盖模式提示备份文件位置）。

**覆盖 ＝「备份 → 整体替换」**：

- 导入前**自动把当前库完整导出为 `.tfpkg` 备份**（与「导出工作区」同一导出路径实现；文件名 `{workspace}-backup-{yyyyMMdd-HHmm}.tfpkg`，保存位置由用户确认并提示），**备份成功才开始替换**——防误覆盖不可逆。
- 替换＝清空现有业务数据，按 manifest.entities 整体重建（含附件与主题，进度随包完整恢复）。
- 任一步骤失败：中止并提示保留的备份，可用备份恢复原状。

**追加 ＝「按稳定 id 去重合并」**（可重复执行，幂等：同一包追加两次结果一致）：

1. **本地运行数据直接并入**：任务（tasks）、日程时间块（timeblocks）、完成记录（completions）、Thread 状态（thread-state）等个人运行数据**追加导入即并入**——按稳定 id（UUID 主键）查重：id 不存在→原样并入；id 冲突→保留本地。
2. **知识类按包升级去重**：知识点（knowledge points）/卡片模板（templates，预设卡）/挖空槽位（slots）/卡片状态（cards，呈现单元）/标签（tags）/思维导图（mindmaps）按 external/package id 走 `.kpak` **既有升级去重逻辑**（本文 §3 导入规则、§5 版本与升级）：同 packageId 视为升级——更新知识内容、**不重置**本地 CardState 复习进度；无包来源（本地原创）的实体按稳定 id 查重并入。
3. **进度本地优先，不随追加跨包迁移**：CardStates/ReviewLogs/ClozeHistory/BoostEntries 的进度行——归属知识点本地已有→保留本地进度；归属知识点为新增→按 `.kpak` 导入语义在本地重建全新进度（个人复习进度是本地资产，见 PRIVACY.md）。**含进度的整机恢复请用「覆盖」导入备份文件**。
4. **其余冲突默认保留本地**：个人档案、本地设置、任务模板、主题、附件按稳定 id/唯一键查重（附件按 relPath、主题按 id）：不冲突即并入，冲突一律保留本地行/文件，导入侧跳过并计入结果报告。

### 7.5 加密（可选密码，AES-GCM）

- **默认可选**：不设密码＝普通 zip（manifest 明文，便于审计/预览）；设密码＝加密包。
- 加密范围：zip 内 `manifest.json` 与 `attachments/*`、`themes/*` 全部载荷**同密**（GAP §5），不区分强弱数据。
- 算法与派生：AES-256-GCM；密码经 PBKDF2-HMAC-SHA256（随机 16B salt，默认 120000 次迭代）派生 256-bit 密钥。
- 包结构：加密包在 zip 顶层增加**唯一明文条目 `crypto.json`**（信封）；其余载荷条目字节格式＝`[12B 随机 nonce ‖ AES-GCM 密文（输出含 16B tag）]`，每条目 nonce 独立随机、随条目自描述。

`crypto.json`（仅加密包存在）字段说明：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| formatVersion | int | 是 | 格式版本，= 1（解密前即可校验包格式版本） |
| encrypted | bool | 是 | true＝加密包 |
| cipher | string | 是 | `AES-256-GCM` |
| kdf | string | 是 | `PBKDF2-HMAC-SHA256` |
| iterations | int | 是 | 迭代次数（导出时写入，默认 120000） |
| salt | string | 是 | 随机盐，base64（16B） |

- 导入流程：打开 zip → 存在 `crypto.json`＝要求输入密码 → 按参数派生密钥、逐条目解密（每条目自带 nonce）→ 之后走与明文包相同的流程（校验格式版本/预览/选合并模式）；AES-GCM tag 校验失败＝提示“密码错误或文件损坏”，**不落任何数据**。
- 密码不存储、不设找回通道：导出时明示“忘记密码将无法打开，请自行妥善保管”。
- 依赖与降级：加密依赖 cryptography 库；不可用（pub.dev 受限）时按 GAP O1 默认决定——加密入口禁用并提示、codec 接口与本文档先行。
- `.kpak` 不做加密（§6 勾销项），两格式加密状态互不影响。

### 7.6 文件名与实现要点

- 文件名建议：`{workspace}-{yyyyMMdd-HHmm}.tfpkg`（覆盖导入自动备份：`{workspace}-backup-{yyyyMMdd-HHmm}.tfpkg`）；workspace 内非法文件名字符（`\ / : * ? " < > |`）与首尾空白清洗后使用。
- 依赖：zip 用 archive 库（定稿 §5 技术栈）；加密用 cryptography（降级见 §7.5）。
- **快照一致性**：导出＝「导出工作区」触发后（空闲/模态流程中）对 SQLite 做**只读一致读取**——单事务内完成全部实体查询并序列化为 JSON，即“导出开始时刻”的库快照。**取舍**：单用户离线场景无多进程/多用户并发写，故不做数据库文件级快照（不拷 `.db`、不依赖 WAL checkpoint/文件锁等）；导出期间 UI 置于模态、完成前禁用会写库的入口即可，附件在清单登记后逐个拷贝。
- 附件完整性：导出时先算 sha256 再写入 zip 并登记清单；导入时按清单校验，损坏项跳过并明确提示（覆盖模式以自动备份为兜底）。
- 落地阶段：GAP §6 R4（tfpkg codec＋merge），DoD＝编解码往返测试。
