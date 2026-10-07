# 数据刷新：写库即刷新（响应式）

> 目标：**任何一次写库，界面都不再需要重启或手动刷新**。
> 代码：`app/lib/core/state/data_change_bus.dart`、`app/lib/core/state/data_revision.dart`、
> `app/lib/data/database/db_write_interceptor.dart`（装配点 `app/lib/data/database/database.dart` 的 `instrumentWrites`）。

## 1. 之前为什么会"必须重启"

界面的数据全部来自 `FutureProvider`（非 autoDispose），页面 `ref.watch` 到的是**缓存值**。
写库只发生在动作所在的那个页面里，由它自己 `ref.invalidate` 一下；于是：

- 跨页写入（AI 助手加了一条任务、导入了知识包、复习评分改了卡状态）没人通知别的页面；
- 时间派生的事实（到期的卡、今天的日程、"N 分钟前排序"）在应用一直开着时不会自己变。

两条合起来就是用户看到的"要重启才更新"。

## 2. 机制：一条链，四个文件

```
写语句 → drift QueryExecutor
       → DbWriteInterceptor（runInsert / runUpdate / runDelete / runCustom / runBatched）
       → DataChangeBus.recordChange()          // 进程内，微任务合并
       → dataRevisionProvider（int）
       → 所有 ref.watchDatabaseRevision() 的 provider 重新执行
       → 挂在它们上面的页面重建
```

设计要点：

1. **拦截点在执行器层，不在仓储层。** 仓储、原生 `customStatement`、`batch()`、AI 工具层全都经过
   `QueryExecutor`，所以"新写路径忘记通知"这件事在结构上不可能发生——不需要每个仓储记得加一行。
2. **读不通知**（只拦 insert/update/delete/custom/batch）。`PRAGMA`、自愈用的
   `CREATE INDEX IF NOT EXISTS` 会多换一次刷新，但它们都跑在第一个监听者出现之前。
3. **合并粒度 = 一个微任务。** 一次 `batch()` 写 N 行 → 1 次通知；被 `await` 分开的 N 次写 → N 次通知
   （这是实测行为，测试里钉住了两种）。真正的成本控制来自 Riverpod 的惰性：**没有监听者的 provider
   不会被重算**，所以批量导入不会变成 O(N × provider) 的抖动。
4. **刻意不用 `Timer` 做去抖。** pending timer 会让 `flutter_test` 在测试收尾时报
   "A Timer is still pending"，代价是污染整个既有测试面。

## 3. 不变量（以后新增读库代码时必须遵守）

1. 任何"从库里读出来给界面看"的 provider，**第一行**写 `ref.watchDatabaseRevision();`。
2. **不要在 provider 的 `build()` 里写库**（会自激）。已知的两个例外是
   `timeViewRepository.ensure()` 与 `themeRepository.ensureBuiltins()`：它们只在缺行时写一次，
   第二次读不再写，因此收敛；新增类似代码前先确认它确实收敛。
3. 页面若把列表存在自己的 `State` 里（`initState` 拉一次），必须补一条
   `ref.listenManual(dataRevisionProvider, …)` 的刷新路径，并且**不能打断用户正在做的事**：
   复习页在答题中途不刷新队列（`review_page.dart`），只在队列未被触碰时重取。
4. 前台恢复也算一次变化：`home_shell.dart` 用 `WidgetsBindingObserver`，`resumed` 时
   `recordChange()`。到期卡 / 今天的日程 / "N 分钟前"都是时钟派生，后台放一夜没有任何写。

## 4. 订阅了 revision 的 provider（19 个）

| 模块 | provider |
|---|---|
| 标签 | `allTagsProvider` |
| 任务 | `taskListProvider`、`scheduleSuggestionsProvider` |
| 日程（Time） | `timeBlocksProvider`、`timeBlockTasksProvider`、`timeBlockScheduleProvider`、`calendarBlocksProvider`、`timeViewSettingsProvider`、`timeTemplatesProvider` |
| 思维导图 | `mindMapsProvider`、`mindNodesProvider` |
| 知识点 | `ankiKnowledgePointsProvider`、`ankiStatsProvider`、`insightSummaryProvider` |
| Thread | `threadStateProvider`、`currentWeightsProvider` |
| 设置 | `currentProfileProvider` |
| 认知读数 | `cognitiveObservationInputsProvider`（同时转 `autoDispose`：它扫全表，不该常驻） |
| 知识库 | `packageLibraryProvider` |

## 5. 刻意**不**订阅的

- **主题**（`themesProvider`、`activeAppearanceProvider`）：写主题的两处已经自己 `invalidate`；
  若订阅它，每次复习评分都会重建整个 App 的 `ThemeData`，纯成本无收益。
- **`ThreadFeedNotifier.build()`**：排序结果刻意只存在于内存（`thread_rank_service.dart` 注释）。
  改为在 `thread_page.dart` 里监听 revision：已有排序结果时自动 `sort()`。
  排序器 `ThreadRankService.build()` 明确"Never touches the database to write"，所以不会自激。
- **AI 会话/消息**（`conversationsProvider`、`messagesProvider`）：保留既有手动 invalidate，
  避免在一次流式回复期间被外部重取打断。

## 6. 验证（本会话实跑）

- `test/core/state/data_change_bus_test.dart`（3 条）：微任务合并、独立批次各一次、无监听者时 revision 仍可读。
- `test/data/database/db_write_interceptor_test.dart`（6 条）：读不通知；一次写通知一次；`batch()` 只通知一次；
  被 `await` 分开的三次写通知三次；**没人 invalidate 的情况下，应用自己的读 provider 会重新取数**。
- `test/features/reactivity_live_page_test.dart`（2 条）：挂载真实的标签页 + 外部写入 → 页面出现新标签；
  **对照组**：把 `dataRevisionProvider` 冻结成常量（复现改动前的行为）→ 同样的写不可见。
  两条一起才说明"测的是这条链"，而不是别的巧合。
- 全量 `flutter test --concurrency=1` → `All tests passed! (+557 ~2)`；`dart analyze lib test tool` → 0 error / 0 warning。

## 7. 尚未覆盖（如实列出）

- 主题之外的"设置类"读取仍走各自的手动 invalidate（设置页写入自己会刷新）。
- Thread 事件流的**首次**排序仍需用户动作（Ctrl+R / 按钮）——自动重排只发生在已有排序结果时。
- 跨进程/多窗口同步不在范围内（本应用是单进程本地库）。
