?# 开发进�?
> 记录每一轮自�?手动迭代的进展，作为持续开发的“长期记忆”�?
---

## 2026-09-07 轮次：Threadflow 定稿对齐（R0–R1 文档阶段�?
> 项目定稿更名�?**Threadflow**（权威规范：docs/THREADFLOW_SPEC.md；差距与迁移：docs/GAP_ANALYSIS.md）�?
- [x] R0：全量备�?`class-productivity` �?`_backup/2026-09-07/`�?30 文件�?- [x] 定稿存档：`docs/THREADFLOW_SPEC.md`（逐字权威版）
- [x] 差距清单：`docs/GAP_ANALYSIS.md`（D1–D13 决策、逐条差距矩阵、常量缺省表�?tfpkg 草案、R0–R6 路线�?- [x] `docs/DATA_MODEL.md` 重写�?v2（树形标�?path、Tasks+expected_at/energy_required、ThreadStates、CompletionLogs、TaskTemplates、ClozeSlots/ClozeHistory、CardStates 呈现单元+FSRS 字段、BoostEntries、Themes、Attachments；schema 1�? 迁移步骤�?- [x] `docs/ARCHITECTURE.md` 对齐（命名映�?D2、ThreadRanker/FSRS/ClozeEngine/DiffusionBoost/TimeWindowEngine 分层、闭环流程、常量收口）
- [x] 环境结案：本�?Flutter 3.47.2 / Dart 3.13.2 可用；pub.dev 可达（O1 关闭）；TimeBlock.available 语义确认同向无需翻转（O2 关闭�?- [ ] 文档子代理产出验证：PRD 取代标记、README 更名、OPEN_QUESTIONS 结案、KNOWLEDGE_PACKAGE +.tfpkg 节、PRIVACY 双轨、MILESTONES R0–R6、FEATURE_MATRIX 重建

---

## 已完�?
### 需求与设计
- [x] 需求沟通（团队、Windows 优先、离线优先、隐私、知识包分享、中英双语）
- [x] PRD、架构、数据模型、知识包格式、隐私设计、里程碑文档
- [x] 待确认问题清单与默认决定

### M1：Flutter 项目骨架（源码）
- [x] `app/pubspec.yaml`、`analysis_options.yaml`、`l10n.yaml`
- [x] 中英�?ARB 文案
- [x] 应用入口 `main.dart`、根组件 `KnowFlowApp`
- [x] 桌面/移动自适应导航�?`HomeShell`
- [x] 设置页（语言/主题切换，内存态）
- [x] 五大模块占位页（思维导图/任务/时间/背诵/设置�?- [x] 开发环境文�?`docs/DEV_SETUP.md`
- [x] 引导脚本 `scripts/bootstrap.ps1`

### 核心算法原型（纯 Dart，待�?Flutter 环境后跑测试�?- [x] SM-2 间隔重复调度 `Sm2Scheduler`
- [x] 任务自动编排引擎 `TaskScheduler`
- [x] 自动挖空生成�?`ClozeGenerator`
- [x] 领域实体：Task、TimeBlock、KnowledgePoint、CardTemplate、SrsState
- [x] 对应单元测试文件

### M2：数据层（源码）
- [x] Drift 表结构：Profile、LocalSettings、Tag、ObjectTag、MindMap、MindNode、Task、TaskDependency、TimeBlock、TaskTimeBlock、KnowledgePoint、CardTemplate、CardState、ReviewLog、KnowledgePackage、PackageItem
- [x] `AppDatabase` + 连接 + 外键
- [x] Repository：Settings、Tag、Task、TimeBlock、Anki、MindMap
- [x] Riverpod providers 装配数据库与 Repository
- [x] AnkiService（Repository + SM-2 调度�?- [x] TaskSchedulerService（Repository + 调度引擎�?
### 知识包（部分源码�?- [x] `KnowledgePackageManifest` JSON 模型
- [x] `.kpak` zip 编解码器 `KnowledgePackageCodec`
- [x] `PackageRepository` �?`PackageImportService`（导入标�?知识�?模板/思维导图，去重并保留复习进度�?- [x] 对应单元测试

---

### M3-M6：基础 UI（源码）
- [x] 导航壳加入“知识库”页（共 6 个模块）
- [x] 思维导图页：新建导图、节点树、添加节点、重命名、删除节点、节点转标签
- [x] 任务页：新建任务、优先级/预估、完成切换、删除、查看自动建�?- [x] 任务详情页：子任务、依赖、提醒设置、本地通知调度
- [x] 时间板块页：新建/删除时间块、时间选择
- [x] Anki 页：加载到期卡片、三种题型呈现、显示答案、忘�?模糊/记得评分
- [x] Anki 管理页：新建知识点、新建选择�?填空�?大题模板
- [x] 知识库页：导入预览确认、文件选择导入 `.kpak`，调�?`PackageImportService`
- [x] 知识库页：导�?`.kpak`（`PackageExportService` + 文件保存�?- [x] `PackageExportService`：从本地标签/知识�?模板/思维导图生成 manifest
- [x] `NotificationService`：本地提醒通知（Windows/Android 预留�?- [x] 设置持久化：启动加载 Profile/Settings，语言/主题切换写入数据�?- [x] 任务建议“一键采纳”：把建议任务链接到对应时间�?- [x] Anki 填空判分：提交后判断正确/错误，选择题显示正�?错误反馈
- [x] Anki 管理页统计：知识点数、模板数、到期卡片数�?天复习次�?- [x] 时间块可用状态切换（影响任务调度建议�?- [x] 时间块显示已关联任务
- [x] 标签管理页（新增/删除标签�?- [x] 设置页支持修改作�?姓名
- [x] Anki 模板/知识点删�?- [x] Anki 模板编辑（题�?题目/答案/选项�?- [x] 任务编辑（标�?优先�?预估时间/截止时间，可清除截止时间�?- [x] 知识点编辑（标题/内容�?- [x] 时间块编辑（标题/开�?结束/可用状态）
- [x] 自动挖空：管理页一键生成填空模�?- [x] 自动挖空：导入知识包时，无模板的知识点自动生成填空模�?- [x] 任务列表支持点击圆圈快速完�?恢复
- [x] 思维导图节点支持折叠/展开
- [x] 任务列表显示截止时间
- [x] 新增测试：任务调�?timeBlockId、知识包导入自动挖空/去重、设置档案持久化
- [x] 思维导图节点“转为任务”（可同时带上标签）
- [x] 时间块支持精�?适合类型属性（创建/编辑�?- [x] 时间板块“今日安排”汇总视图（按时间块展示已关联任务）
- [x] 导出知识包时显示隐私说明（不包含任务/时间/复习进度�?- [x] 知识包导入预览显示“升级”提示（旧版�?�?新版本）
- [x] 时间块支持标签关联（编辑弹窗中添�?移除标签�?- [x] 任务调度引擎：优先选择“适合类型”匹配任务标签的时间�?- [x] Anki 管理页新�?7 天复习柱状图
- [x] 知识点支持来源字段（创建/编辑�?- [x] 思维导图节点支持备注编辑/显示/清除
- [x] 新增 `docs/FEATURE_MATRIX.md` 需�?实现功能矩阵
- [x] 思维导图节点支持同级上移/下移排序
- [x] 本地化补全：导出默认名称/作者、任务空态文�?- [x] 修复 Flutter 实机问题：本地化 import、Drift 列定义、通知�?v22 API、build_runner --force-jit
- [x] Anki 选择题选项随机打乱（每次复习顺序不同）
- [x] 设置页支持本地数据库备份（保�?.db 文件�?- [x] 标签关联：任务详情页可添�?移除标签
- [x] 标签关联：知识点详情弹窗可添�?移除标签
- [x] Windows 构建脚本 `scripts/build_windows.ps1` 与发布文�?`docs/DEPLOY.md`

---

## 下一步（R2–R6，详�?docs/GAP_ANALYSIS.md §6�?
1. R2：Drift schema v2 迁移（`schemaVersion 1�?`，表/�?索引�?DATA_MODEL §7�? Repository 扩展 + 迁移�?CRUD 单测；db 文件迁移�?`threadflow.db`�?2. R3：纯 Dart 核心 —�?`ThreadRanker`（加权公�?硬约�?疲劳惩罚，常�?`ThreadflowDefaults`）、Dart FSRS 替换 SM-2、`ClozeEngine`（自由挖�?出题/错题绑定状态机）、`DiffusionBoost`（图谱距�?BFS+衰减）、`TimeWindowEngine`（重复规则展开/占用/空闲窗口）、TagTree/Template/BatchEdit 服务�?3. R4：`.tfpkg` 编解码（逻辑全量转储+附件+主题，可�?AES-GCM�? 覆盖/追加合并器；主题 JSON 与外观系统（缩放/字体/背景）�?4. R5：UI 迁移与联动：Threadflow 词表、Thread 顶栏+更新排序、硬约束红标、日/�?月日�?冲突一键调整、Knowledge 新复习流+生成任务、Mindnet 系导�?设目�?.mm-OPML�?5. R6：拖�?re-parent、双语补全、FEATURE_MATRIX/PROGRESS 回写、Windows build 冒烟�?
---

## 环境�?026-08-31 更新�?
- 本机已装 Flutter 3.47.2（stable�? Dart 3.13.2；pub.dev 可达；Drift �?`dart run build_runner build --delete-conflicting-outputs` 生成代码�?`flutter test` 验证�?- 注：早期轮次的“当前机器未安装 Flutter/Dart”限制已解除（见上轮“M6 基础 UI”）�?