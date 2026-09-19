# 开发进度

> 记录每一轮自动/手动迭代的进展，作为持续开发的“长期记忆”。

---

## 2026-09-19 轮次七：清理剩余问题 + v0.1.0 发版

### 1. 补齐批次 5 的两块（此前只有模型/库层，没接 UI）

**主题系统（spec §4）**

- 新增 `data/repositories/theme_repository.dart`：内置深浅主题的**幂等播种**、当前主题
  （存 `LocalSettings.active_theme_id`）、保存/导入/导出/删除。
  关键语义：**编辑内置主题会另存为副本**，出厂默认永不被就地覆盖；删除当前主题会自动回落到"跟随系统"，
  不会留下悬空引用；损坏的 payload 解析失败时回退内置深色而不是抛异常。
- 新增 `features/settings/application/appearance_providers.dart`：把"当前主题"解析为
  `ActiveAppearance`（主题文档 + 旧的 system/light/dark 回退），供 app 与设置页共用。
- 新增 `features/settings/presentation/appearance_section.dart`：外观区 —— 跟随系统 + 主题列表
  （色卡预览、编辑、导出、删除）+ 导入。
- 新增 `features/settings/presentation/theme_editor_page.dart`：明暗、主色、背景色与透明度、
  页面缩放 80%–150%、动画开关、字体族。
- `app/app.dart` 重写：`MaterialApp` 的主题由**主题文档**驱动，不再用硬编码的 `AppTheme`
  （该文件已删除）；页面缩放与动画开关在 `builder` 里对整棵树生效。

**`.tfpkg` 工作区打包（spec §3）**

- 新增 `features/settings/presentation/data_section.dart`：设置页「数据」区。
  - 导出：写入带时间戳的 `.tfpkg`。
  - 导入：先读 manifest 显示**预览**（多少行/多少表/多少主题）并让用户选**追加或覆盖**，
    然后**自动备份**当前工作区（`pre-import-<时间戳>.tfpkg`）再导入；完成后刷新相关 provider
    并报告写入行数、以及被跳过的未来版本表。
- 修正 `TfpkgService.importDump` 的覆盖语义：现在只清空**包内出现过的表**。
  原实现"覆盖=清空整库"，会把包里根本没带的表一起抹掉。

**顺带修掉的真 bug**

- 通知服务的 Windows 标识仍是 `KnowFlow` / `com.knowflow.app`，与产品名不一致 → 改为
  `Threadflow` / `com.threadflow.app`，并换了一个不再像占位符的 GUID（附注：AppUserModelId
  必须跨版本稳定，改动会让 Windows 丢弃已排期的提醒）。

### 2. 剩余问题清单（本轮结束时的真实状态）

已完成：主题系统全链路、`.tfpkg` 导出/导入 UI、通知品牌、覆盖语义修正。
**仍未做**（已写入 `docs/DEPLOY.md` §5）：

- 字体**文件**导入（只能填字体族名称）；"正文/编辑器字体"与界面字体目前共用同一套字体族，
  要独立生效需在阅读视图再包一层 `DefaultTextStyle`。
- 日程块的拖拽移动/拉伸边缘改时长。
- 真机运行验证（用户有 Android 手机，待测）。

### 3. Windows release 在本工作区也需要 ASCII 路径（新发现）

`flutter build windows --release` **失败**，报错与 Android release 同源：
`Unable to read file ...\.dart_tool\flutter_build\<hash>\app.dill` → `MSB8066`。
debug 走 JIT 不受影响。解法同样是 junction：

```powershell
cmd /c mklink /J E:\threadflow-android "<真实路径>"
cd E:\threadflow-android; flutter build windows --release
```

已实测：Windows release 产物打包 **35.66 MB**，`knowflow.exe` 启动后窗口正常、占用 255 MB。

### 4. v0.1.0 产物（本轮实测）

| 产物 | 大小 | 验证 |
| --- | --- | --- |
| `dist/Threadflow-0.1.0-android.apk` | 62.07 MB | `apksigner`：`CN=Threadflow`；`aapt2`：包名 `com.threadflow.knowflow`、targetSdk 36、三套 `libsqlite3.so` |
| `dist/Threadflow-0.1.0-windows-x64.zip` | 35.66 MB | 启动实测：进程存活、有窗口句柄、255 MB |
| 测试 | — | **190/190 全绿**（上一轮 172，本轮 +18 项主题仓库测试） |
| 静态检查 | — | `dart analyze` **0 error** |

---

## 2026-09-19 轮次六之二：源码已上传 GitHub（公开仓库 Furnace）

仓库：**https://github.com/FirsryFan/Furnace**（公开，MIT）

### 上传过程与最终状态

- 远端起始只有 `LICENSE` + `README.md`（1 个提交 `a397880`）。把它的 `.git` 接入本地工作目录以**保留历史**，
  然后分两次提交推送：
  - `620cc8e9` — `feat: Threadflow 首个可运行版本（Windows + Android）`（179 个文件，1.84 MB）
  - `fdb0b212` — `chore: 固化行尾策略（.gitattributes）`
- 远端核对（GitHub API）：两个提交都在 `main` 上；公开 tree 共 **180 个 blob**、`truncated=false`。

### 忽略策略（两个关键取舍）

1. **`lib/data/database/database.g.dart` 故意提交** —— Drift 生成的 schema 代码。不提交的话，
   全新 clone 必须先跑 `build_runner` 才能编译；提交它也让 schema 变更在 diff 里可审。
   因此给 `app/.gitignore` 里的 `lib/**/*.g.dart` 加了 `!` 例外。
2. **构建产物全部排除** —— `app/build/` **1324 MB**、`app/windows/` **311 MB**（几乎全是
   `ephemeral/` 等 CMake 生成物）、`.dart_tool/` 284 MB。最终入库仅 **1.84 MB**。
3. `gradle-wrapper.jar` / `gradlew` 也保留入库（Flutter 模板默认排除），clone 后 `./gradlew`
   即可用，无需额外 bootstrap。

### 安全处理（**重要**）

用户在本轮中途把仓库从私有改为**公开**（实测 `private=False, visibility=public`）。签名密钥必须随之排除：

- 生成过 `app/android/threadflow-release.jks` 与 `key.properties`（开发口令）。
  **已确认没有任何提交包含它们**（`git log --all -- <jks>` 为空），并已加入 `.gitignore`，
  因此公开仓库的**全历史**里都没有密钥。
- 全历史审计（遍历所有提交的所有文件名，共 181 个）：无 `.jks`/`.keystore`/`key.properties`/
  `*.db`/`*.apk`/`*.aab`/口令类文件。
- `app/build.gradle.kts` 在 `key.properties` 缺失时**回退使用 debug 证书**，所以别人 clone 后
  `flutter build apk` 仍能出包（可装机自测，不适合分发）。keystore 保留在本地，
  **这台机器仍能产出正式签名包**。

### 行尾策略（新增 `.gitattributes`）

`core.autocrlf` 依赖机器设置，已经造成过一次 `LICENSE` 整文件假差异，并让 `gradlew.bat` 在索引里存成 LF。
现用 `.gitattributes` 明确规则，并用 `git ls-files --eol` 核对：`gradlew` 保持 LF
（否则 macOS/Linux 报 bad interpreter）、批处理/PowerShell 用 CRLF、二进制（jar/jks/图片/字体/apk/db）
不做转换、生成文件标记 `linguist-generated`。

### 文档

根 `README.md` 重写为仓库门面：模块表、当前状态与已知未完成项、目录结构、Windows/Android 构建命令、
**签名注意事项**、文档索引。构建 Android 前指向 `docs/DEPLOY.md`（其中记录了 6 个必须避开的坑）。

### 下一步

- 用户在 **Android 真机**上安装 `dist/Threadflow-0.1.0-release.apk` 验证运行。
- 之后可做：主题与 `.tfpkg` 接入设置页 UI、字体导入、页面缩放、日程块拖拽。

---

## 2026-09-19 轮次六：Android 落地（从零装工具链 → 产出已签名 release APK）

> 用户要求：“把没有做的做完，尽早完成 Android 版本，这是我大部分的适用场景。”
> 结果：**release APK 已产出并用正式 keystore 签名**，`dist/Threadflow-0.1.0-release.apk`（61.72 MB）。

### 1. 起点：这台机器完全没有 Android 工具链

`flutter doctor` 报 `✗ Unable to locate Android SDK`；`ANDROID_HOME` 为空、常见 SDK 路径都不存在、`java` 不在 PATH。
所以“Android 做不了”一直是**环境缺失**，不是代码问题。全部按**用户级、无管理员**方式装好：

| 组件 | 位置 | 方式 |
| --- | --- | --- |
| JDK 21 | `C:\Program Files\Microsoft\jdk-21.0.12.101-hotspot` | `winget install --id Microsoft.OpenJDK.21` |
| Android SDK | `C:\AndroidDev\sdk` | cmdline-tools 解包 + `sdkmanager` 装组件 |
| NDK 28.2.13676358 | `C:\AndroidDev\sdk\ndk\...`（2172 MB） | 腾讯镜像下载后**核对官方 size/sha1 一致** |
| Gradle 9.3.1-all（224MB） | `~\.gradle\wrapper\dists\...` | 腾讯镜像 + 核对官方 sha256 一致，手动放进 wrapper 缓存 |

用户级环境变量 `ANDROID_HOME` / `ANDROID_SDK_ROOT` / `JAVA_HOME` 已写入；`flutter config --android-sdk` 已设置。
`flutter doctor` 现在显示 `[✓] Android toolchain - Android SDK version 36.0.0`。

### 2. 踩到并解决的 6 个环境/依赖坑（每个都有明确报错）

1. **Gradle 发行包下载失败**：wrapper 的下载是纯 Java、无重试，先被连接超时打死，后又被
   GitHub CDN 的连接重置打断（下到 101MB 处）。→ 改从腾讯镜像取，**核对官方 sha256 完全一致**
   （`17f277867f6914d61b1aa02efab1ba7bb439ad652ca485cd8ca6842fccec6e43`），手动放入 wrapper 缓存并写 `.ok`。
2. **`maven.google.com` 不可达**：`dl.google.com` 的 CDN 路径可通但只有 ~60KB/s 并 `Read timed out`。
   实测同一 jar 传 8 秒：CDN 501KB vs **阿里云 12389KB**。→ 写 `google-cdn.init.gradle` 重写仓库 URL。
   - 第一版只钩 root build，**Flutter 插件的 included build 仍在慢源上超时**；改用
     `beforeSettings`（对每个 settings 生效）+ `gradle.beforeProject` + `allprojects` 三层覆盖。
   - 也不能靠 hosts：**无管理员权限，hosts 不可写**。
3. **AGP 拒绝非 ASCII 路径**：`Your project path contains non-ASCII characters` → `android.overridePathCheck=true`。
4. **Kotlin 增量缓存写失败**：`Could not close incremental caches ... class-fq-name-to-source.tab` → `kotlin.incremental=false`。
5. **`flutter_local_notifications` 要求 core library desugaring** → 打开 `isCoreLibraryDesugaringEnabled`
   并加 `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")`。
6. **插件 compileSdk 冲突**：`file_picker` 8.3.7 硬编码 `compileSdk 34`，而
   `flutter_plugin_android_lifecycle` 要求消费方编译到 36 → 构建失败。
   - 我先试了三种 Gradle 钩子（`subprojects{afterEvaluate}`、`gradle.projectsEvaluated`、`beforeEvaluate`），
     分别报 “Cannot run Project.afterEvaluate when the project is already evaluated” 和
     “It is too late to set compileSdk / It has already been read”。**这是在猜生命周期，不对。**
   - 最终用**干净解法**：把 `file_picker` 升到 **12.3.0**。升级后 `flutter_plugin_android_lifecycle`
     不再在依赖树里，冲突根源消失；同时按 12.x 新 API 改了 3 处调用
     （静态 `FilePicker.pickFiles/saveFile`、`saveFile` 需要 bytes 且返回 `Uri?`、
     `PlatformFile.bytes` → `await readAsBytes()`）。

### 3. 最后一个坑：release 的 AOT 编译要求 ASCII 路径

debug 能构建（JIT），release 失败：
`Error: Unable to read file ...\flutter_build\<hash>\app.dill` → `Target android_aot_release_android-arm64 failed`。
根因同样是路径里的 `一THREADRIPPER一`（Flutter→Gradle 传参被 ANSI 破坏）。
→ 用**目录 junction** 造一条纯 ASCII 路径（无需管理员）：
`mklink /J E:\threadflow-android <真实 app 路径>`，再从该路径构建。已固化进 `scripts/build_android.ps1`。

### 4. 交付验证（全部是对真实产物的读取，不是推测）

- `flutter build apk --debug` → **成功**，`app-debug.apk` 161.72 MB。
- `flutter build apk --release` → **成功**，`app-release.apk` 61.72 MB。
- `aapt2 dump badging`：包名 `com.threadflow.knowflow`、versionName 0.1.0、
  应用名 **Threadflow**、`compileSdkVersion='36'`、`targetSdkVersion:'36'`、
  `native-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'`。
- 权限：`POST_NOTIFICATIONS`、`RECEIVE_BOOT_COMPLETED`、`VIBRATE`（+ 插件自带的一条）。
- APK 内 `lib/{arm64-v8a,armeabi-v7a,x86_64}/libsqlite3.so` **三套齐全**。
- `apksigner verify --print-certs`：`CN=Threadflow, OU=Personal, O=Threadflow, C=CN`
  （不再是 `CN=Android Debug`）→ 已生成 `android/threadflow-release.jks` 并接线（缺 keystore 时回退 debug，
  保证全新 clone 也能构建）。
- `flutter test --concurrency=1` → **172/172 全绿**；`dart analyze` → **0 error**。
- 产物已放到 `dist/`：`Threadflow-0.1.0-release.apk` + `dist/windows/`（Windows debug 运行目录 19 个文件）。

### 5. 未验证 / 待你处理

- **没有真机或模拟器**（`adb devices` 为空），所以**未在任何 Android 设备上安装运行过**——
  能构建、能签名、清单与 native 库正确，但**实际运行效果未经确认**。
- 正式 keystore 的口令是开发用值并明文放在 `android/key.properties`（已在 `.gitignore` 内）。
  **对外发布前请重新生成并妥善保管**：换 keystore 会导致已安装用户无法覆盖升级。
- 仍属批次 5 未做的部分：主题 JSON 的**接入**（模型与测试已完成，见下）、字体导入、页面缩放。
  `.tfpkg` 编解码与服务层已完成并有 8 项测试，但**尚未接入设置页 UI**。
- 界面仍未经肉眼检阅。

### 6. 本轮顺带完成（批次 5 的两块，纯代码 + 测试）

- `core/theme/theme_profile.dart`：主题 JSON 文档模型（颜色/背景/透明度/背景图/字体/缩放 0.8–1.5/动画开关、
  内置深浅主题、宽容解析、`toThemeData()`），14 项测试。
- `data/package/tfpkg_codec.dart` + `data/package/tfpkg_service.dart`：`.tfpkg` 全量逻辑转储
  （**通用遍历 sqlite_master 导出所有用户表**，不为 28 张表手写序列化；BLOB 用 base64 标记往返；
  附件与主题随包；覆盖/追加两种合并；未知表与未知列容错），8 项测试。
- 修掉一个真 bug：设置页“备份数据”读的是 `knowflow.db`，而实际库是 `threadflow.db`
  ——旧写法在全新安装上永远报 not found。

---

## 2026-09-08 轮次五：日视图不按小时分 + 日视图宽度（用户 2 条）

### 1. 不要默认按小时来分（schema 4 → 5）

- **默认行高 60 → 30 分钟**：`TimeViewSettings.minutesPerRow` 默认改为 30，`_CalendarPageState._minutesPerRow` 同步改 30。
- **次小时行**：新增 `rowLabel(row, minutesPerRow)`（显示真实时间 `HH:MM`）与 `isMajorTick`（整点画重分隔线，次小时画淡线且不写字）。日视图与周视图都改用这两个函数。
- **记录“用户自己选过”**：新增列 `minutes_per_row_chosen`。`_setMinutesPerRow` 在选择时写 `chosen: true`，以后再改默认值也不会覆盖用户刻意的选择。
- 迁移 `_upgradeV4ToV5`：给缺列的表补上该列，然后把 `chosen = 0` 的行从旧的 60 改成 30（刻意选过 60/15 的保持不动）。

### 2. 日视图要有宽度

- `_DayGrid` 改用 `LayoutBuilder` 约束宽度：**最小 340、最大 760**，宽屏居中而不是拉满，窄屏横向滚动而不是压扁。
- 周视图同样加下限 **560**：不足时横向滚动，7 列不再被挤成细条。

### 3. 踩到并修掉一个真实的“版本号撒谎”问题

- **现象**：实测真实库 `user_version = 5`，但 `time_view_settings` **没有** `minutes_per_row_chosen` 列。
- **根因**：Drift 只在 `user_version < schemaVersion` 时才跑 `onUpgrade`。这份开发库在前一版（迁移实现有缺陷时）就被打上了 5，于是修复版的迁移**永远不会执行**；而 Drift 生成的 mapper 对该列做非空读取 → 读到该表就抛异常。这是**真实存在的潜在崩溃**，不是测试造假。
- **修法（两层）**：
  1. `_upgradeV4ToV5` 先补列、再改值；
  2. `beforeOpen` 新增 `_ensureColumns()` **自愈**：每次打开都按当前 schema 探测并补齐缺失列（`tasks.started_at`、`completion_logs` 三列、`time_view_settings.minutes_per_row_chosen`）。健康库在这里什么都不做。
- 同时补上 `_tableFor` 的 switch（原先只认 tasks / completion_logs，补列时报 `unknown table time_view_settings`）。
- **开发库处理**：那份被跳过迁移的旧库备份为 `threadflow-v4-stale-*.db.bak`，并重建干净的 v5 库（28 表）。自愈只补列、不重解释旧值，所以旧库里的 60 不会自动变 30——重置是为了让新默认值真正生效。

### 4. 我自己造过一个不真实的测试场景

- 我一度写下“v4 库没有 `minutes_per_row_chosen` 列”的测试并断言迁移会补列，但它失败在 Drift mapper 上。
- 事实是：v3→v4 用**当时的 schema** 建表，v4 发布版的表**本来就带这一列**（只是值恒为 60）。真正缺列的来源是第 3 条那种“版本号撒谎”的库。已改为两个真实场景：① 表带列但值 60 → 迁移改 30；② 版本号谎报 5、表缺列 → `beforeOpen` 自愈。

### 5. 本轮验证（实测）

- `flutter test -r expanded --concurrency=1` → **150/150 全绿**（上一轮 138，本轮 +12）。
- `dart analyze` → **0 error**。
- `flutter build windows --debug` → **成功**；启动实测进程存活、有窗口句柄。
- **真实库实测**：自愈前 `cols` 缺 `minutes_per_row_chosen`；启动一次后该列出现（值 0）→ **自愈在真实文件上生效**。随后重置开发库，新库 `user_version=5`、28 表。

---

## 2026-09-08 轮次四：反馈(3) 日历/时间轴重构完成 + 反馈(2) 收尾

> 本轮按默认值推进了两处此前的歧义（用户未答复）：月视图主交互＝**点选该日 + 下方详情面板**（双击进日视图）；周序号＝**全年连续 ISO 周号**，不做逐月重置。

### 1. 数据层：schema 3 → 4（纯加表，幂等迁移）

- `TimeTemplates`（`time_templates`）：日/周模板。`payload` 为 JSON 的 `{blocks:[...]}`，每个块含 `title/start/end/available/repeatRule/dows/monthDay/color`；`start`/`end` 是**从本地午夜起的分钟数**（与时区无关）。
- `TimeViewSettings`（`time_view_settings`，单行）：`timelineSpanDays`(默认 730)、`timelinePxPerDay`(6)、`timelineCollapsed`(false)、`minutesPerRow`(60)。
- 迁移 `_upgradeV3ToV4` 用存在性探测保证 v1→v4 / v2→v4 / v3→v4 三条路径都不重复建表（沿用上一轮的幂等做法）。
- 新仓库：`TimeTemplateRepository`（含 `applyToDays` 物化、`blocksOf` 解析）、`TimeViewRepository`；已装配进 `repository_providers`。
- 新测试：`v4_migration_test`（真实 v3 库文件就地升级）、`time_template_repository_test`（9 项）、`calendar_support_test`（8 项）。

### 2. 日历重写（`features/timeboard/presentation/calendar_page.dart`）

四种视图：**日 / 周 / 月 / 时间轴**。

- **多年时间轴**：跨度 30–3650 天（滑条，用户自定义）、缩放（1–40 px/天，缩放按钮）、**折叠开关**——不折叠＝单条横向滚动，折叠＝按窗口宽度自动分行、纵向滚动。左侧显示该行起始年月，每月 1 日画主干线；块按真实起止时间定位（同一天内的块在时间轴上按分钟比例摆放）。
- **周视图**：左侧 **ISO 周号列**（`W38`）；表头整行与每个日列都能右键/长按出菜单；右侧 7 列时间网格。
- **月视图**：每行左侧 **ISO 周号**；每个格子显示该日的彩色块卡片（最多 3 个 + `+N`）；**单击选中该日**，下方**详情面板**显示该日全部日程块的起止时间并可编辑/删除，面板顶栏有「新建 / 进日视图 / 进周视图」三个 icon 按钮；双击格子直接进日视图；右键/长按弹菜单。
- **右键菜单**（桌面右键、触屏长按，同一套）：日格 → 新建块 / 套用模板 / 打开日视图 / 打开周视图；周行 → 打开周视图 / 套用日模板 / 套用周模板 / 新建块。
- **日程块**：起止时间**任意到分钟**（时间选择器 + ±5 分钟微调），**不做重叠避让**；显示为**半透明彩色卡片**（8 色稳定配色 + 按 id 哈希，忙碌块更不透明、开放块更淡），忙碌/开放语义（D6）靠透明度继续可见。
- **模板**：`showTemplatesSheet` 支持「日/周」范围切换、列出模板（显示块数）、一键套用到目标日或整周、删除模板，以及**把当前周/日保存为模板**（从日历里已有的块反向生成）。

### 3. 反馈(2) 收尾：右键菜单 + 全局快捷键

- **标签树**：三点菜单保留为触屏兜底，但**整行右键/长按**现在直接弹上下文菜单（新建子标签/重命名/删除，带图标）；单击有子节点的行＝展开/折叠。
- **全局快捷键**（`home_shell.dart`，`Shortcuts` + `Actions`）：`Ctrl+R` 重新排序（若不在 Thread 页会先切过去）、`Ctrl+1..4` 跳转前四个模块。
- 各输入框 `Enter` 提交（上一轮已做，本轮补到日历建块/编辑与模板命名）。

### 4. 踩坑记录

- **`IsoWeek.number` 差一位**：我最初写 `(diff ~/ 7) + 2`，测试实测 2026-01-01 得到第 2 周（应为第 1 周）。根因是把“距第一个周四的周数”与“周号”差了个 1（第一个周四本身就在第 1 周）。改为 `+ 1` 后 8 项 ISO 测试全过。**这是该算法最经典的 off-by-one，测试直接抓到了。**
- 我为了消一个 “unused import” 警告删掉了 `time_template_repository.dart` 的 import，结果 `TemplateBlock` 变成未定义类型——**analyze 的警告不能盲从，要看它是否真的未被使用**。

### 5. 本轮验证（实测）

- `flutter test -r expanded --concurrency=1` → **138/138 全绿**（上一轮 120，本轮 +18）。
- `dart analyze` → **0 error**（1 warning、其余 info）。
- `flutter build windows --debug` → **成功**；启动实测 12 秒后进程存活、窗口句柄 `hwnd=1508716`、内存 444MB。
- **真实库升级实测**：直接读 `%APPDATA%\com.example\knowflow\threadflow.db` → `user_version = 4`、**28 张表**、`time_templates` 与 `time_view_settings` 均存在。
- ⚠️ 仍未做：界面肉眼检阅（无法截图）、Android、批次 5（主题/.tfpkg）。**块尚未支持拖拽移动/拉伸边缘改时长**（改时间目前走对话框）。

---

## 2026-09-08 轮次三：用户 4 条反馈（1、2、4 完成；3 未动）

> 用户反馈要点：(1) 排序参数说明集中到 设置→使用文档；(2) 交互细节需打磨，例：标签加子标签不该用三点菜单，要用 Enter 等快捷键，并要求我主动发现更多问题；(3) 新增多年时间轴视图 + 月/周/日联动 + 周模板日模板 + 块随意起止不避重叠 + 透明彩色卡片 + 右键菜单；(4) Thread 事件不能删除、状态色用错了、权重计算有问题。

### 1. 反馈(1) 完成：参数说明集中

- 新增 `features/settings/presentation/usage_doc_page.dart`：总分公式、五个分量的现实意义、**当前权重 vs 出厂值对照表**、事件条四色含义。
- 设置页新增「使用文档」入口；属性页与权重对话框各加 help 图标直达该页。
- 属性页**移除全部内联小字说明**，只保留参数名与实时数值——按用户要求统一放到使用文档。

### 2. 反馈(4) 完成：删除、状态色条、权重修正

- **事件删除**：左滑（Dismissible + 二次确认）+ 三点菜单里的删除项；已归档条目同样支持。此前确实**没有任何删除入口**。
- **状态色条**：新增 `features/thread/presentation/widgets/thread_status_edge.dart`，事件条左边缘 5px 圆角色条：
  绿＝已完成 / 蓝＝等待中 / 黄＝已过期期望时刻 / 红＝已过截止时刻；**截止优先于期望**（两者都过 → 红）。
- **权重计算修正**（两个实测缺陷）：
  1. 五个权重相加 = **1.05**（`wExpected=0.05` 是加在定稿四权重之上的），总分被放大 5% 且可能 >1 → 新增 `RankWeights.sum` / `normalized()`，排序器统一用归一化权重，总分恒定 [0,1]。
  2. 缺失值被当成“半匹配”：精力未设置时 `energyFit=0.5`、无预估用时时 `windowFit=0.5`，各自把分数压低一截 → 改为返回 `null`（`RankScore.energyFit/windowFit` 现可空），`fit` 只对有数据的分量取平均，两边都无数据才用中性值。
  - 取证：写临时 `dart run` 探针打印权重与分量实测值（探针已删）。新测试：「total cannot exceed 1」「缺失值不再算半匹配」。

### 3. 反馈(2) 部分完成：交互打磨 + 一个会丢数据的真 bug

- **修复 ID 撞车（严重）**：8 个仓库的 ID 生成器都是
  `'$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'`，
  **同一微秒内连续插入生成重复主键** → `UNIQUE constraint failed: time_blocks.id / diffusion_logs.id`。
  - 影响场景：示例数据装载、批量导入、任何紧凑循环插入。
  - 修复：新增 `data/ids.dart`（`Ids.next(prefix)` / `Ids.uuid()`，uuid v4），8 个仓库全部改用；新增 `test/data/ids_test.dart`（5000 次连续生成必须唯一）。
  - **发现路径值得记住**：全量测试串行跑报出两处 UNIQUE 冲突，而单独跑同一文件却通过——「单独过、全量崩」正是共享状态或时间随机性的信号。
- **Enter 提交**：标签树（新建/重命名）、新建事件、属性页预估用时补 `onSubmitted`，此前按 Enter 无反应。

### 4. 反馈(3) 未完成：日历/时间轴重构（下一轮主体）

动手前需明确两处交互歧义（**已向用户提问，未答复前不擅自定案**）：

- 月视图单元格的**主交互**：点一下选中该日（旁边出详情面板做增删改）还是弹层打开当日详情？
- 周序号列的**呈现**：每月内独立编号（第 1..5 周）还是全年连续 ISO 周号（第 1..53 周）？

已确定要做：多年可定义长度时间轴（缩放 + 折叠：不折叠左右滚动 / 折叠则上下滚动）、月视图选中整周或某日切换周/日视图、周模板与日模板一键套用、日程块起止任意（不避重叠）、块改半透明彩色卡片、日/周视图右键菜单 + 左侧周序号。

### 5. 本轮验证（实测）

- `flutter test -r expanded --concurrency=1` → **120/120 全绿**（上一轮 116，新增 3 项 ID 唯一性 + 1 项权重归一化）。
- `dart analyze` → **0 error**（1 条 warning、其余 info 级）。
- `flutter build windows --debug` → **成功**；启动实测 12 秒后进程存活且有窗口句柄（`hwnd=1376420`）。
- ⚠️ 仍未做：界面肉眼检阅（无法截图）、Android、批次 5（主题/.tfpkg）。

---

## 2026-09-08 轮次二：图形界面全部落地 + 真机可运行（Windows）

> 用户要求：“把图形化界面也落地，我直接检阅 flutter 的完整软件成果”。
> 本轮把蓝图 v2 里除批次 5（主题/.tfpkg）外的界面全部做完并接线。

### 1. 新界面（全部新增文件，未覆盖旧实现）

| 模块 | 文件 | 内容 |
| --- | --- | --- |
| Thread | `features/thread/presentation/thread_page.dart` | 事件流 + 已归档 两个并列视图；新建事件可设精力 |
| Thread | `.../event_properties_page.dart` | **属性页**：每个参数一张卡、卡底一行“现实意义”小字；算法区展示 5 个分量的 值×权重=贡献；权重可编辑、可一键恢复默认 |
| Thread | `.../widgets/energy_bar.dart` | 红→绿渐变数字条按钮；点开是带节点滑条 + 现实语义小字 |
| Thread | `.../widgets/thread_status_bar.dart` | 可折叠顶栏；目标只显示标题、点击进完整编辑；过期确认后立即排序 |
| Knowledge | `features/anki/presentation/knowledge_page.dart` | 模块外壳：复习 / 管理 两个 tab |
| Knowledge | `.../review_page.dart` | 心流复习页：一题一个空、提交判分、三键评分 + 生成任务；顶部显示剩余张数与待清数 |
| Knowledge | `.../knowledge_insight_page.dart` | **独立复盘页**：按天显示“答错的 / 被提权的相关词条（距离 + 倍数）” |
| Knowledge | `features/anki/application/review_service.dart` | 复习引擎：自由挖空抽卡、FSRS 调度、错题 active 绑定、标签树扩散、按天台账、Knowledge→Thread 生成事件 |
| Time | `features/timeboard/presentation/calendar_page.dart` | 日/周/月三视图；**纵轴缩放 15/30/60 分钟每格**；忙碌块实心、开放块描边；点空白建块、点块改块 |
| Time | `.../time_page.dart` | Time 模块外壳：日历 / 日程块列表 两个 tab |
| 标签 | `features/tags/presentation/tag_tree_page.dart` | **Mindnet 并入标签**后的树形编辑：递归树、展开折叠、建子标签、改名、删除、面包屑显示完整路径 |

导航壳改为：标签 / Thread / Time / Knowledge / 知识库 / 设置（Mindnet 页不再挂在导航上，数据与代码保留）。

### 2. 关键语义修正（本轮发现问题，均已修 + 有测试）

1. **图谱扩散的“图”换成标签树**：Mindnet 取消后，`DiffusionBoost` 的节点图已不存在。新增 `domain/services/cloze/tag_diffusion.dart`，用标签路径树算距离，**保持定稿语义**：距离 1＝父子/兄弟 → ×1.8；距离 2＝隔代 → ×1.3；表兄弟（同祖父、各两层）实测为 4，不触发提权。
   - ⚠️ 过程记录：我第一次把“堂表兄弟”断言成距离 2，**实测打印距离矩阵**后发现是实现正确、断言错误——改的是测试不是实现。
2. **未复习过的新词条曾整条排不进队列**：`buildQueue` 只在“已存在 card_state”时才产出题目，新词条永远不出现。已修：无状态即视为到期，真正需要时才创建单元状态（不再产生空 `unit_key` 占位状态）。
3. **事务嵌套**：`DiffusionLogRepository.appendAll` 在事务里又调用带事务的 `append`，Drift 不允许。已拆成 `_append`（调用方持有事务）。
4. **`upsertBoost` 支持指定剩余周期**（抽卡时消耗一次 boost）；`addClozeHistory` 的 `correct` 参数与表结构（INTEGER）对齐。

### 3. 本地化

- 中英 ARB 各新增约 90 条。
- ⚠️ **重大踩坑**：我用 PowerShell 的 `Get-Content/Set-Content` 批量改 ARB 占位符类型，导致**中文被 GBK 往返写成乱码**（`"鏃?"`），`gen-l10n` 报 “value is not a string”。
  - 这正是本文件 2026-09-07 轮次已记录的教训，本轮**自己违反了**。
  - 补救：用 `write` 工具整份重建两个 ARB；并把 `calendarWeekdays` 数组拆成 `calendarWeekday1..7`（ARB 不支持数组值）。
  - **规则强化：含中文的文件只用 read/write/edit 工具改，永不走 PowerShell 文本往返。**

### 4. 验证（本轮实测）

- `flutter test` → **116/116 全绿**（上一轮 105，本轮新增 1 项复习引擎 + 10 项复习引擎/扩散测试）。
- `dart analyze` → **0 error**（68 条 info/warning 级）。
- `flutter build windows --debug` → **成功**，产物 `app/build/windows/x64/runner/Debug/knowflow.exe`。
- **启动实测**：`Start-Process` 后 12 秒进程仍存活、有真实窗口句柄（`MainWindowHandle=1901812`）、内存约 434MB → **不闪退**。
- **建库实测**（用 `sqlite3` Dart 包直接读真实库文件）：`threadflow.db` 的 `user_version = 3`、**26 张表**，`completion_logs` 12 列（含 `actual_minutes` / `include_in_model` / `duration_suspicious`）、`tasks` 含 `started_at` → 当前代码的全新建库路径正确。
  - 附带发现并清理：`%APPDATA%\com.example\knowflow\knowflow.db`（**v2 时代的遗留文件**，`user_version=2`、18 表、缺 `completion_logs`）是一次非原子中断留下的残骸。
  - ⚠️ 注意：app 优先使用 `threadflow.db`，仅当它不存在且 `knowflow.db` 存在时才回退到后者。因此这份残骸从未被当前 app 使用，已删除。

### 4.1 运行方式（Windows）

```powershell
cd "E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity\app"
flutter run -d windows        # 开发调试（支持热重载）
# 或直接用已构建产物（免编译）：
.\build\windows\x64\runner\Debug\knowflow.exe
```

首次打开是**空工作区**。建议顺序：**设置 → 载入示例数据**（会生成 8 个标签、4 个词条、6 个事件、3 个日程块，并预置精力 7 / 目标“数学”），然后按 **Thread → Time → Knowledge → 标签** 依次查看。
数据库位置：`%APPDATA%\com.example\knowflow\threadflow.db`。

### 5. 未完成 / 未验证

- **批次 5 未做**：主题 JSON 与外观系统、`.tfpkg` 全量打包、字体导入、缩放 0.8–1.5。
- **`.kpak` 词条级 Markdown/JSON 导入导出**未做。
- **标签拖拽改层级**未做（当前靠“新建子标签”建层级；改名/删除已有）。
- **Android 未做**：`app/android` 目录不存在，需 `flutter create --platforms=android .`；`flutter doctor` 显示 Android toolchain ✗。
- **Time 冲突弹窗与“只挪期望时刻”一键调整**未接入 UI（`TimeWindowEngine.isBusyAt` 已具备）。
- 界面**未经肉眼检阅**：本会话只能确认“能编译、能启动、进程存活、有窗口”，**布局与交互手感需用户实机确认**。

---

## 2026-09-08 轮次：R3 核心算法结案 + 第一批次 Thread UI（蓝图 v2 落地）

> 依据：`docs/DESIGN_BLUEPRINT.md` v2（用户 13 条批注修订版）。用户选择：主力平台 Windows + Android 手机版；优先模块 Thread；构思先讨论再直接写 Flutter。

### 0. 先纠正上一轮记录的失真（重要）

上一轮（2026-09-07）本文写“R3 未开始”、`FEATURE_MATRIX.md` 把 ThreadRanker/FSRS/自由挖空/图谱扩散全标 🔴——**与代码实际不符**。本轮实测：

- 这些算法**早已写入代码**（`thread_ranker.dart`、`time_window_engine.dart`、`fsrs_scheduler.dart`(FSRS-6)、`cloze_engine.dart`+`ForcedMachine`、`diffusion_boost.dart`）。
- 本轮开工前基线：`flutter test` **78/78 全绿**。
- 教训：文档的“未实现”标记必须与源码核对后再写。

### 1. 本轮环境结论（实测）

- `flutter pub outdated` 成功 → **pub.dev 可达**（V1 结案）：`flutter_quill`/`cryptography`/`table_calendar` 等可选型，不必全手写。
- `app/android` **不存在**（`Test-Path` = False）→ 打安卓包前需先 `flutter create --platforms=android .`（V3 结案）。
- `dart test` **不可用**（未依赖 `package:test`），一律用 `flutter test`。
- 项目目录**不是 git 仓库**，无版本历史可回滚。

### 2. 算法层：按用户 13 条批注改写 `ThreadRanker`

- **deadline 与 expected_time 解耦**（用户 16）：红标（`insufficient`）**只看 deadline**；`deadline < now` 单独进 `overdue` 桶；`expected_time` 临近/已过只产生**黄标 + `expectedPressure` 提权**，永不触发红标。
- **新增可调权重** `RankWeights`（urgency/goal/fit/fatigue/**expected**），可被 UI 编辑；新增 `RankScore.expectedPressure/energyFit/windowFit` 与各分量**贡献值**，供属性页展示。
- **目标匹配简化**（用户 7）：只用自由文本关键词命中（节点分支保留但不再使用）。
- **黄标窗口** `expectedNearWindowMinutes = 120`：窗口内渐升，过点仍饱和，之后按 `expectedSoftHalfLifeMinutes` 衰减回 0。
- 新增 `domain/services/time/actual_time.dart`（用户 14）：**不跑计时器**，实际用时＝完成时刻−开始时刻；默认异常规则 `actual > estimate×3 且 actual > 30min` → 默认不计入模型，可逐条改。
- 测试：`thread_ranker_test` 扩到 21 项、新增 `actual_time_test` 9 项。

### 3. 数据层：Drift schema **2 → 3**（纯增量，幂等迁移）

- `Tasks.started_at`；`CompletionLogs.actual_minutes / include_in_model / duration_suspicious`。
- 新表 `ThreadRankSettings`（单行：5 个权重 + 顶栏折叠 + 实际用时总开关）、`DiffusionLogs`（按天留痕，供独立复盘界面，用户 19）。
- 新仓库 `ThreadRankRepository`、`DiffusionLogRepository`，并在 `repository_providers` 装配。
- `TaskRepository`：新增 `startTask` / `setCompletionInModel` / `getModelCompletionLogs` / `getDurationCalibration`；`completeTask` 改为计算并落盘实际用时。
- ⚠️ **踩坑记录**：`Migrator.createTable` 永远按**当前** schema 建表，所以 v1→v2 路径建出的 `completion_logs` 已含 v3 列，v2→v3 再 `addColumn` 会 `duplicate column name`。修法：`_upgradeV2ToV3` 全部改为**先探测再改**（`_tableExists` / `_columnExists`），使迁移幂等。
- 新测试 `v3_migration_test`、`threadflow_v3_repository_test`。

### 4. UI 层：Thread 第一批次（用户 1–13 条）

- `features/thread/` 新模块：`thread_rank_service.dart`（组装排序）、`thread_page.dart`（**事件流 / 已归档 两个并列视图**，用户 5+11）、`event_properties_page.dart`（**属性页**，用户 6+13）、`widgets/energy_colors.dart`、`widgets/energy_bar.dart`、`widgets/thread_status_bar.dart`。
- 顶栏（用户 2/3/8）：**可折叠**、目标只给标题+🎯 按钮进详情、精力是**红→绿渐变的数字条按钮**（只显示数字，无 `/10`），点开是**带节点的水平滑条 + 现实语义小字**；排序是 **icon 按钮**。
- 属性页（用户 6/13）：**所有参数可编辑，每个参数卡底部都有解释现实意义的小字**；含**算法区分量拆解**（紧急度/目标匹配/状态适配/期望压力/疲劳惩罚，各自 值×权重=贡献）与**权重编辑对话框**（全局生效，可一键恢复默认）。列表本身**不显示任何理由**（不做 L1）。
- 导航：`tasks` 页在 Thread 模块替换为 `ThreadPage`，新增导航词条 `navThread`。
- 本地化：新增 ~50 条中英词条，`flutter gen-l10n` 重生成。

### 5. 验证结果（本轮实测）

- `flutter test` → **105/105 全绿**（基线 78 + 本轮新增 27）。
- `dart analyze` → **0 error**（65 条 info/warning 级，含既有 `withOpacity` 弃用、`await_only_futures` 等历史项）。
- ⚠️ **未验证**：UI 没有在真实窗口跑过（本会话没有执行 `flutter run`），所以**布局与手感未经肉眼确认**；Windows/Android 构建也**未实测**。

### 6. 下一步

1. 用户确认蓝图中剩余 5 条待定（Q2.1 归档是否拆两个界面、Q2.4 权重是否事件级、Q2.7 新增事件是否标“未参与排序”、Q4.1 active 插入间隔、Q4.2 复盘是否要历史趋势）。
2. 批次 1 收尾：Thread 事件卡片补标签末级展示、开始/完成按钮与"未参与排序"标记；跑一次 `flutter run` 做双端手感确认。
3. 批次 2：Time 日历（日/周/月 + 纵轴缩放 15/30/60）+ 冲突只挪 `expected_at`。
4. 批次 3：Knowledge 新复习流（FSRS + 自由挖空 + active 当日队列集中重现 + 严格逐字符判分）+ 图谱扩散独立复盘界面（用 `DiffusionLogs`）。
5. 批次 4：标签体系合并 Mindnet + OPML/.mm 导入导出。
6. 批次 5：主题系统 + `.tfpkg` + 字体/缩放 + `flutter create --platforms=android .` 后做安卓构建冒烟。

---

## 2026-09-07 轮次：Threadflow 定稿对齐（R0–R1 文档阶段完成，R2 进行中）

> 项目定稿更名为 **Threadflow**（权威规范：docs/THREADFLOW_SPEC.md；差距与迁移：docs/GAP_ANALYSIS.md）。

- [x] R0：全量备份 `class-productivity` → `_backup/2026-09-07/`（630 文件）
- [x] 定稿存档：`docs/THREADFLOW_SPEC.md`（逐字权威版）
- [x] 差距清单：`docs/GAP_ANALYSIS.md`（D1–D13 决策、逐条差距矩阵、常量缺省表、.tfpkg 草案、R0–R6 路线）
- [x] `docs/DATA_MODEL.md` 重写为 v2（树形标签 path、Tasks+expected_at/energy_required、ThreadStates、CompletionLogs、TaskTemplates、ClozeSlots/ClozeHistory、CardStates 呈现单元+FSRS 字段、BoostEntries、Themes、Attachments；schema 1→2 迁移步骤）
- [x] `docs/ARCHITECTURE.md` 对齐（命名映射 D2、ThreadRanker/FSRS/ClozeEngine/DiffusionBoost/TimeWindowEngine 分层、闭环流程、常量收口）
- [x] 环境结案：本机 Flutter 3.47.2 / Dart 3.13.2 可用；pub.dev 可达（O1 关闭）；TimeBlock.available 语义确认同向无需翻转（O2 关闭）
- [x] 文档对齐完成：PRD 取代标记、README 更名、OPEN_QUESTIONS 结案、KNOWLEDGE_PACKAGE +.tfpkg 节、PRIVACY 双轨、MILESTONES R0–R6、FEATURE_MATRIX 重建
- [x] R2 起点：Drift schema v2 全部表/列已入 `tables.dart` 并生成 `database.g.dart`（build_runner --force-jit 规避沙箱 AOT 写盘限制）；`dart analyze` 定位 16 错误（Theme 类名冲突×12 待 @DataClassName、anki 仓库 Value 包裹×2、anki_page 空安全×1）
- [x] R2 完成：@DataClassName('ThemeProfile') 消冲突；Repository v2 扩展——TaskRepository(+expected_at/energy_required/完成→CompletionLogs 快照)、TagRepository 树形（parent_id/path 级联改名/移动/子树删除/导入系）、AnkiRepository（呈现单元 unitKey、槽位/挖空历史、图谱扩散 BoostEntries、ReviewLogs v2 扩展）、ThreadStateRepository（单行精力/目标/2h 过期判定）、repository_providers 装配
- [x] R2 验证：真实 v1 SQLite 文件就地迁移 v2 单测通过（含标签 path 回填去重、card_states 回填 knowledge_point_id/unit_key='preset:…'、review_logs 扩展列）；v2 仓库行为 14 项全绿；**全量 35/35 测试通过；dart analyze 0 错误 0 警告**
- [ ] R3：纯 Dart 核心算法（ThreadRanker/FSRS/ClozeEngine/图谱扩散/TimeWindow/TagTree 服务/模板/批改）

> ⚠️ 编码教训（写入本文件备忘）：pwsh 的 Get-Content/Set-Content 文本往返在中文环境下按 GBK 解码会损坏 UTF-8 文档——文档一律用 read/edit/write 工具或 .NET UTF8 API 操作；build_runner 必须带 `--force-jit`（AOT 快照写盘被沙箱拦截）；`flutter analyze` 的 LSP 通道在沙箱下崩溃，验证用 `dart analyze`。

---

## 已完成

### 需求与设计
- [x] 需求沟通（团队、Windows 优先、离线优先、隐私、知识包分享、中英双语）
- [x] PRD、架构、数据模型、知识包格式、隐私设计、里程碑文档
- [x] 待确认问题清单与默认决定

### M1：Flutter 项目骨架（源码）
- [x] `app/pubspec.yaml`、`analysis_options.yaml`、`l10n.yaml`
- [x] 中英文 ARB 文案
- [x] 应用入口 `main.dart`、根组件 `KnowFlowApp`
- [x] 桌面/移动自适应导航壳 `HomeShell`
- [x] 设置页（语言/主题切换，内存态）
- [x] 五大模块占位页（思维导图/任务/时间/背诵/设置）
- [x] 开发环境文档 `docs/DEV_SETUP.md`
- [x] 引导脚本 `scripts/bootstrap.ps1`

### 核心算法原型（纯 Dart，待有 Flutter 环境后跑测试）
- [x] SM-2 间隔重复调度 `Sm2Scheduler`
- [x] 任务自动编排引擎 `TaskScheduler`
- [x] 自动挖空生成器 `ClozeGenerator`
- [x] 领域实体：Task、TimeBlock、KnowledgePoint、CardTemplate、SrsState
- [x] 对应单元测试文件

### M2：数据层（源码）
- [x] Drift 表结构：Profile、LocalSettings、Tag、ObjectTag、MindMap、MindNode、Task、TaskDependency、TimeBlock、TaskTimeBlock、KnowledgePoint、CardTemplate、CardState、ReviewLog、KnowledgePackage、PackageItem
- [x] `AppDatabase` + 连接 + 外键
- [x] Repository：Settings、Tag、Task、TimeBlock、Anki、MindMap
- [x] Riverpod providers 装配数据库与 Repository
- [x] AnkiService（Repository + SM-2 调度）
- [x] TaskSchedulerService（Repository + 调度引擎）

### 知识包（部分源码）
- [x] `KnowledgePackageManifest` JSON 模型
- [x] `.kpak` zip 编解码器 `KnowledgePackageCodec`
- [x] `PackageRepository` 与 `PackageImportService`（导入标签/知识点/模板/思维导图，去重并保留复习进度）
- [x] 对应单元测试

---

### M3-M6：基础 UI（源码）
- [x] 导航壳加入“知识库”页（共 6 个模块）
- [x] 思维导图页：新建导图、节点树、添加节点、重命名、删除节点、节点转标签
- [x] 任务页：新建任务、优先级/预估、完成切换、删除、查看自动建议
- [x] 任务详情页：子任务、依赖、提醒设置、本地通知调度
- [x] 时间板块页：新建/删除时间块、时间选择
- [x] Anki 页：加载到期卡片、三种题型呈现、显示答案、忘记/模糊/记得评分
- [x] Anki 管理页：新建知识点、新建选择题/填空题/大题模板
- [x] 知识库页：导入预览确认、文件选择导入 `.kpak`，调用 `PackageImportService`
- [x] 知识库页：导出 `.kpak`（`PackageExportService` + 文件保存）
- [x] `PackageExportService`：从本地标签/知识点/模板/思维导图生成 manifest
- [x] `NotificationService`：本地提醒通知（Windows/Android 预留）
- [x] 设置持久化：启动加载 Profile/Settings，语言/主题切换写入数据库
- [x] 任务建议“一键采纳”：把建议任务链接到对应时间块
- [x] Anki 填空判分：提交后判断正确/错误，选择题显示正确/错误反馈
- [x] Anki 管理页统计：知识点数、模板数、到期卡片数、7天复习次数
- [x] 时间块可用状态切换（影响任务调度建议）
- [x] 时间块显示已关联任务
- [x] 标签管理页（新增/删除标签）
- [x] 设置页支持修改作者/姓名
- [x] Anki 模板/知识点删除
- [x] Anki 模板编辑（题型/题目/答案/选项）
- [x] 任务编辑（标题/优先级/预估时间/截止时间，可清除截止时间）
- [x] 知识点编辑（标题/内容）
- [x] 时间块编辑（标题/开始/结束/可用状态）
- [x] 自动挖空：管理页一键生成填空模板
- [x] 自动挖空：导入知识包时，无模板的知识点自动生成填空模板
- [x] 任务列表支持点击圆圈快速完成/恢复
- [x] 思维导图节点支持折叠/展开
- [x] 任务列表显示截止时间
- [x] 新增测试：任务调度 timeBlockId、知识包导入自动挖空/去重、设置档案持久化
- [x] 思维导图节点“转为任务”（可同时带上标签）
- [x] 时间块支持精力/适合类型属性（创建/编辑）
- [x] 时间板块“今日安排”汇总视图（按时间块展示已关联任务）
- [x] 导出知识包时显示隐私说明（不包含任务/时间/复习进度）
- [x] 知识包导入预览显示“升级”提示（旧版本 → 新版本）
- [x] 时间块支持标签关联（编辑弹窗中添加/移除标签）
- [x] 任务调度引擎：优先选择“适合类型”匹配任务标签的时间块
- [x] Anki 管理页新增 7 天复习柱状图
- [x] 知识点支持来源字段（创建/编辑）
- [x] 思维导图节点支持备注编辑/显示/清除
- [x] 新增 `docs/FEATURE_MATRIX.md` 需求-实现功能矩阵
- [x] 思维导图节点支持同级上移/下移排序
- [x] 本地化补全：导出默认名称/作者、任务空态文案
- [x] 修复 Flutter 实机问题：本地化 import、Drift 列定义、通知库 v22 API、build_runner --force-jit
- [x] Anki 选择题选项随机打乱（每次复习顺序不同）
- [x] 设置页支持本地数据库备份（保存 .db 文件）
- [x] 标签关联：任务详情页可添加/移除标签
- [x] 标签关联：知识点详情弹窗可添加/移除标签
- [x] Windows 构建脚本 `scripts/build_windows.ps1` 与发布文档 `docs/DEPLOY.md`

---

## 下一步（R2–R6，详见 docs/GAP_ANALYSIS.md §6）

1. R2 收尾：修复 dart analyze 16 错误（@DataClassName 等）；Repository 扩展（ThreadStates/TaskTemplates/CompletionLogs/树形 Tag/复习单元 API）；schema 迁移与 CRUD 单测（`flutter test`）；db 文件迁移到 `threadflow.db`（已实现兼容回退）。
2. R3：纯 Dart 核心 —— `ThreadRanker`（加权公式+硬约束+疲劳惩罚，常量 `ThreadflowDefaults`）、Dart FSRS 替换 SM-2、`ClozeEngine`（自由挖空/出题/错题绑定状态机）、`DiffusionBoost`（图谱距离 BFS+衰减）、`TimeWindowEngine`（重复规则展开/占用/空闲窗口）、TagTree/Template/BatchEdit 服务。
3. R4：`.tfpkg` 编解码（逻辑全量转储+附件+主题，可选 AES-GCM）+ 覆盖/追加合并器；主题 JSON 与外观系统（缩放/字体/背景）。
4. R5：UI 迁移与联动：Threadflow 词表、Thread 顶栏+更新排序、硬约束红标、日/周/月日历+冲突一键调整、Knowledge 新复习流+生成任务、Mindnet 系导入/设目标/.mm-OPML。
5. R6：拖拽 re-parent、双语补全、FEATURE_MATRIX/PROGRESS 回写、Windows build 冒烟、pubspec 更名 threadflow。

---

## 环境（2026-09-07 更新）

- 本机已装 Flutter 3.47.2（stable）/ Dart 3.13.2；pub.dev 可达；build_runner 需 `--force-jit`（沙箱限制 AOT 快照写盘）；`dart analyze` 可用（`flutter analyze` 的 LSP 通道在沙箱下截断崩溃，用 `dart analyze` 替代）。
- 注：早期轮次的“当前机器未安装 Flutter/Dart”限制已解除（见上轮“M6 基础 UI”）。
