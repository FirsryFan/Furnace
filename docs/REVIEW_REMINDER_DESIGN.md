# 复习提醒设计（本地通知）

> 轮次一百三十五 · schema v28 · 五应用领域 #2「flashcard 推送」的推送半边

## 1. 目标与非目标

**目标**：用户打开开关并选一个每天的时刻（默认 20:00）后，到点若还有到期卡片，就用系统本地通知
提醒一次「今天有 N 张卡到期」。到点前如果没有到期卡、之后 24 小时内也没有卡到期，就**不弹**。

**非目标**（这一版明确不做）：

- 不做每日重复通知（`flutter_local_notifications` 的 daily repeating 在触发时读不了库，而到期数会变）；
- 不做推送服务 / 云端同步（App 没有网络层，五应用领域的「同步」半边不在这条线）；
- 不在 App 未运行时后台重排（Windows/Android 都需后台调度器，代价远大于收益）；
- 不读通知点击事件做深链（本轮只保证点开 App 后看到的是当日状态）。

## 2. 为什么要「只排下一次 + 每次重排」

本地通知一旦排下去就与库脱钩：用户 20:30 复习完今天所有卡，如果通知是 20:00 排的 repeating，今晚还会再弹
一次「有 12 张到期」，而库里已经 0 张。反过来，如果只排一次、从不重排，用户第二天也收不到提醒。

所以本轮的口径是：**每次条件变化都重新算、重新排**——

| 触发时机 | 位置 | 理由 |
| --- | --- | --- |
| App 启动（首帧后） | `lib/app/shell/home_shell.dart` | 隔夜后到期集合已变 |
| App 从后台恢复 | 同上（`AppLifecycleState.resumed`） | 用户可能在外面复习过/改过系统时间 |
| 复习队列清空（本轮复习完） | `lib/features/anki/presentation/review_page.dart` | 今晚不该再弹「还有到期」 |
| 设置页改动开关/时刻 | `lib/features/settings/presentation/review_reminder_section.dart` | 用户刚改的意图必须立刻生效 |

重排 = **先 cancel 同一个通知 id，再按新时刻 schedule**。这个顺序保证：旧计划一定被清掉（哪怕 schedule 失败，
旧通知也不会在错误的时间弹出），而且同一 id 反复排不会堆叠。

## 3. 数据与四态

schema v28 给单行设置表加两列（`docs/DATA_MODEL.md` §17）：

- `local_settings.review_reminder_enabled`（BOOL 可空）：NULL = 没选过 = 关闭；
- `local_settings.review_reminder_minutes`（INT 可空）：0..1439；NULL = 没选过 = 域层默认 20:00。

纯逻辑层 `planReviewReminder`（`app/lib/domain/services/scheduling/review_reminder_plan.dart`）给出四态：

| reason | 何时 | when |
| --- | --- | --- |
| `disabled` | 开关关闭 | null |
| `dueNow` | 现在就有到期卡；或无到期卡但下一张到期不晚于现在 | 下一个偏好时刻（严格晚于 now） |
| `dueSoon` | 现在没有到期卡，且下一张到期早于下一个偏好时刻 | 下一张到期的时刻 |
| `nothingDue` | 现在没有到期卡，且下一张到期晚于下一个偏好时刻（或根本没有下一张） | null |

`when` 永远严格晚于 `now`：偏好的 HH:mm 若已过，用日期构造器进位到明天（不做 `add(Duration)`，避免
夏令时/月末错位；本机 Asia/Shanghai 无 DST，但规则不依赖这一点）。

## 4. 应用层

`app/lib/features/anki/application/review_reminder_service.dart`：

- `ReminderNotifier` 接口（`app/lib/core/notifications/reminder_notifier.dart`）：`scheduleReminder({id,title,body,when})`
  返回 `bool`（false = 没有通知权限）、`cancelReminder(id)`。`NotificationService` 实现它，行为不变；
- `ReviewReminderService.refresh({required ReviewReminderTexts texts})`：读开关与时刻 → 数到期卡 → 
  `nextDueAtAfter` → `planReviewReminder` → 不排就 cancel，排就 cancel-then-schedule；
- 时间来源统一走注入的 `clock`（默认 `DateTime.now`），`getDueCardStates` 与 `nextDueAtAfter` 用同一个 now，
  否则测试注入的时钟与查询时刻会不同步；
- `ReviewReminderOutcome.toJson` 三键 `scheduled` / `cancelled` / `permission_denied` + 内嵌 `plan`。
  `cancelled` 的语义是「这一次 refresh 调用过 cancel」——成功排程时也是 true（cancel-then-schedule 的幂等重置），
  不是「最终没有通知」。

**异常策略**：service 不吞插件异常（权限、平台不支持、时区数据缺失由调用方决定怎么处理）；UI 侧接
`refresh` 的地方统一 try/catch + `debugPrint`，通知失败绝不能拖垮启动或复习流程。

## 5. 通知与权限

- 通知 id 固定 `kReviewReminderNotificationId = 20261021`，与任务提醒的 `task.id.hashCode` 不共用命名空间（碰撞概率可以忽略，
  且取消是按 id 精确取消）；
- Android 13+ 需要 `POST_NOTIFICATIONS`，`NotificationService._mayPostNotifications` 已处理（拒绝 → 返回 false → 
  设置页 SnackBar 提示）；
- Windows 用 `WindowsInitializationSettings(appName:'Furnace', appUserModelId:'com.furnace.app', guid:…)`，无需运行时权限；
- 通知正文由 l10n 文案给：`reviewReminderNotificationDueBody(count)` / `reviewReminderNotificationSoonBody`。

## 6. 文案

12 个 l10n 键（五文件手改）：设置入口标题/关闭态/开启态（带 HH:mm）/对话框标题/说明/开关标题/开关提示/时间行/
通知标题/到期通知正文（带数量）/即将到期正文/权限被拒提示。关掉开关不清时刻，再打开还是上次的时间。

## 7. 未做 / 已知限制

- 真正的每日重复（当前靠启动/恢复/复习结束/设置改动四个时机重排，App 连续多天不打开则不会提醒）；
- 通知点击深链（点开只到首页，不直接进复习队列）；
- 时区/夏令时真机验证（当前机器 Asia/Shanghai，无 DST）；
- Windows 通知的点击回调与激活 ID 未接；
- 服务端推送（同步半边）未做。

## 8. 证据

- 纯逻辑 66 例：`app/test/domain/services/scheduling/review_reminder_plan_test.dart`；
- 数据层：本轮新增 11 例（`v28_migration_test.dart` 4 + `settings_repository_test.dart` 3 + `anki_repository_test.dart` 4 个 `nextDueAtAfter` 用例）；三个文件一起跑共 +20 例（含既有用例）。
- 应用层 21 例：`app/test/features/anki/application/review_reminder_service_test.dart`（开关/空计划、有到期、dueSoon、偏好边界、权限与顺序、幂等与异常）；
- UI 6 例：`app/test/features/settings/review_reminder_settings_test.dart`（默认关闭、开启写库与时间行、关闭取消通知、权限被拒 SnackBar、分钟文案边界）；
- 接线 2 例：`app/test/app/review_reminder_wiring_test.dart`（HomeShell 启动首帧 refresh 一次 + resumed 再 refresh）、`app/test/features/anki/review_page_reminder_test.dart`（一张 essay 卡答完进结束态，refresh 一次）；
- 组合回归：`test/features/settings` 整目录 +34；`review_reminder_wiring_test.dart` + `home_shell_narrow_test.dart` + settings 组合 +36；复习页两文件 +15；均 EXIT 0。

**测试接地的前提（本轮修的坑）**：`NotificationService` 构造函数曾立即 `_plugin.initialize(...)`，widget test 没有平台实现，
一旦外 pump HomeShell 的测试走到启动首帧 refresh 就抛 `LateInitializationError`。现改为惰性初始化：
构造函数只 `tzdata.initializeTimeZones()`（纯 Dart），`_ensureInitialized()` 在真正 `scheduleReminder` / `cancelReminder` 时才调插件；
插件失败的异常照旧传给调用方，测试里表现为被 catch 的一行 `debugPrint`。
