# 标签树排序：三种口径与数据源（轮次一百二十八）

`docs/QUESTION_BANK_DESIGN.md` §5 的标签树是几个系统共用的语言（知识点挂边、收题页筛题、
拍照整理建标签都走它）。本文件只回答一件事：**标签树里同一层的兄弟节点，按什么顺序摆。**

用户口径（2026-10-20）：默认三种顺序——**字典序 / 按标签下内容量 / 按添加时间**；排序是
展示层的事，不能改变标签的父子关系、路径与任何数据。

## 1. 现状（轮次一百二十八之前）

`app/lib/features/tags/presentation/tag_tree_page.dart` 在 `_buildTree` 里写死：

```dart
list.sort((a, b) => a.name.compareTo(b.name));
```

问题不在"字典序不好"，而在于：

1. 口径写死在页面里，换一种排法要改 UI 代码；
2. 只有一种排法，用户没法按"哪层内容多"决定先看哪一支；
3. 页面之外（将来的标签选择器、按内容量做诊断）拿不到同一套排序；
4. 排序只比较 `name`，同名时顺序取决于输入顺序（不是全序，测试会飘）。

## 2. 纯逻辑层（已交付，`app/lib/domain/services/tags/tag_tree_sort.dart`）

不依赖 Flutter / drift / `dart:io`；不建树、不查库、不做 UI、不碰 l10n。

| 符号 | 形状 |
|---|---|
| `TagTreeSortMode` | `alphabetical('alphabetical','字典序')` / `byObjectCount('object_count','按内容量')` / `byCreatedAt('created_at','按添加时间')`；字段 `code`（持久化用）、`labelZh`（直接给 UI，l10n 接线由 UI 层负责）；`static byCode(String raw)` 反查（trim + 小写，认不出 null） |
| `TagTreeSortEntry` | `id` / `name` / `createdAt` / `objectCount`（缺省 0）；`sortableObjectCount` 把负数当 0 |
| `sortTagTreeSiblings(siblings, mode)` | 只排**同层兄弟**；返回新列表，不修改入参；全序（四字段兜底决胜），同输入同输出 |

三种口径的实际比较顺序（契约，测试逐条钉住）：

| mode | 主键 | 决胜 |
|---|---|---|
| `alphabetical` | `name.compareTo` 升序 | `createdAt` → `id` |
| `byObjectCount` | `sortableObjectCount` **降序**（多者在前） | `name` → `createdAt` → `id` |
| `byCreatedAt` | `createdAt` 升序（先加的在前） | `name` → `id` |

两条刻意约定：

- **字典序就是 Dart `String.compareTo`**（UTF-16 代码单元序），不换 collation、不做拼音
  转换——页面现在的行为逐字节不变，避免"换个排序顺便把所有中文名重排一遍"；
- **空标签不沉底**也不置顶：内容量都是 0 时按名字决胜，用户看到的仍是可预期的顺序。

## 3. 数据源（已交付，`TagRepository.objectCountByTagId`）

```dart
Future<Map<String, int>> objectCountByTagId({
  bool includeDescendants = false,
  Set<String>? objectTypes,
})
```

- 直接模式：一条 `SELECT tag_id, COUNT(*) FROM object_tags GROUP BY tag_id`（`selectOnly` +
  `groupBy`），没有挂边的标签不出现在结果里（调用方按 0 处理）；
- 累计模式：读出 `tags` 表建父链，把每个标签的计数沿 `parent_id` 向上累加；`visited`
  防环，父节点不存在的"碎片"跳过；返回值包含 `tags` 表全部 id（含 0）；
- `objectTypes` 用 `isIn` 过滤；传空集合得到空 map（不是"全部"）；
- 口径：**默认只算直接挂在本标签下的对象**。子树累计是显式开关——"这个标签下有多少东西"
  两种理解都合理，默认取字面意思，避免把子标签的量重复算进父标签。

## 4. 树装配与排序偏好（轮次一百二十八，threadflow-engine）

`app/lib/domain/services/tags/tag_tree_view.dart` 把"扁平标签 + 计数"装成页面直接能渲染的树：

- `TagTreeViewTag{id, parentId?, name, path?, createdAt, description?}`；
- `TagTreeViewNode{tagId, parentId?, name, path, depth, objectCount, children, hasChildren, childCount}`；
- `TagTreeView{roots, byId, preorder, orphanIds, cycleIds, isEmpty, totalCount}`；
- `buildTagTreeView({tags, objectCounts, mode, countDescendants})`——同层顺序复用
  `sortTagTreeSiblings`（不复制排序实现）；父节点不在输入里的当根并记 `orphanIds`；
  环（自环 / 两节点 / 长环）按确定性规则断开并记 `cycleIds`，断开的节点当根；
  `countDescendants = true` 时节点计数 = 自身 + 子树累计（断环边不算）。

偏好：`tagTreeSortModeFromStorage(String?)`（null / 空 / 认不出 → `alphabetical`）、
`tagTreeSortModeToStorage(mode)`。**本轮只做会话内记忆，不做数据库迁移**——排序偏好是
展示偏好，不该为了它加一列 schema；等设置页面需要跨设备/跨重启时再落到 `local_settings`。

## 5. UI 接线（已交付，threadflow-engine，轮次一百二十八）

- `tag_tree_page.dart` 用 `buildTagTreeView` 替换写死的 `name.compareTo`：
  `tagObjectCountsProvider`（`objectCountByTagId()`，默认直接计数）+ `tagTreeSortModeProvider`
  （`StateProvider<TagTreeSortMode>`，默认 `alphabetical`）→ 树；展开状态仍按 tag id 保留；
- AppBar `PopupMenuButton<TagTreeSortMode>` 三档 `CheckedPopupMenuItem`，切换立即重排；
- `byObjectCount` 模式在 tile 尾部显示内容量角标（`ValueKey('tag-object-count-<tagId>')`），
  其他模式不显示；
- 计数与标签异步：`valueOrNull ?? const {}`，未到按 0，不阻塞树显示，不写库、无迁移。
- **l10n**：本轮只硬编码中文；轮次一百三十九已把排序按钮 tooltip 接成
  `l10n.tagsSort`（三档模式名仍来自 `TagTreeSortMode.labelZh`，en 界面是中文，留给后续）。
  排序偏好只在会话内（`tagTreeSortModeProvider`），跨重启持久化留到以后
  （`tagTreeSortModeToStorage` 已备好）。

## 6. 刻意未做

- **不做拼音/部首排序**：要做也是新增第四种 `TagTreeSortMode`，不偷偷改字典序；
- **不做跨层排序**（按内容量把子标签提到父层前面）：层内排序是用户口径，跨层会破坏树；
- **不做数据库持久化**（见 §4）；
- **不做"最近使用"排序**：没有使用时间列，凭空造一个需要新的写路径，先不做。

## 7. 验收

- `app/test/domain/services/tags/tag_tree_sort_test.dart`：三口径、全序决胜、不修改入参、
  `byCode` 脏值；
- `app/test/domain/services/tags/tag_tree_view_test.dart`（threadflow-engine）：树装配、孤儿、
  环、计数、偏好编解码；
- `app/test/data/repositories/tag_repository_test.dart`：直接/累计计数、`objectTypes` 过滤、
  空集合与 `tags` 全量返回；
- UI：`app/test/features/tags/presentation/tag_tree_page_test.dart`（threadflow-engine，8 例：
  默认字典序无角标、按内容量重排+角标、按添加时间、展开状态跨重排保留、切回字典序复原、
  空库不崩、计数 pending 按 0、选择器三档打勾与即时重排）。


## 8. 多选批量操作与 l10n 接线（轮次一百三十九，task-119 + Lead 接线）

**问题**：用户反馈「编辑标签要一个个点开、移到菜单、处理完再退出，很繁琐」——逐个标签改一棵
树时，真正贵的是**重复的指针移动**，不是单次点击本身。

**做法**：进入多选后整行变勾选，底部一条操作条，一次落在一批标签上。

- 页面状态：`_selectionMode` / `_selected` / `_batchBusy`；退出多选、批量成功都清空选择
  （被删的 id 不能留在集合里，否则下一次批量操作会指向不存在的行）。
- 多选行：整行点击切换勾选；展开箭头保留（点箭头只展开、不勾选）；⋮ 菜单与长按/右键在
  多选里隐藏，避免两套动作抢同一个入口。
- 底部条：`已选 N 项` / 全选·清空选择 / 批量移动 / 批量删除；0 项时删除与移动禁用
  （否则「全选」按钮永远出不来）。
- 批量删除：确认框列出前 5 个标签名 + 总数，说明「整棵子树一起删除」，逐个 `deleteTag`；
  失败逐个收集，最后 SnackBar 汇总「成功 N 个、失败 M 个：前 3 条原因」。
- 批量移动：目标列表 = 顶层 + 其余标签，**排除被选标签自身与全部后代**（否则 `moveTag`
  会按环拒绝）；逐个 `moveTag`，同样汇总成功/失败。
- 执行期 `_batchBusy` 锁入口（多选开关、勾选、批量按钮都禁用），避免半途重入。
- l10n：Lead 在轮次一百三十九接线 13 个 key——`tagsSelectMode` / `tagsSelectedCount` /
  `tagsSelectAll` / `tagsClearSelection` / `tagsBatchDelete` / `tagsBatchMove` /
  `tagsBatchDeleteTitle` / `tagsBatchDeletePreview` / `tagsMoveDialogTitle` /
  `tagsMoveToRoot` / `tagsBatchBusy` / `tagsBatchResultDone` / `tagsBatchResultMixed`，
  另加通用动词 `commonMove` 与 tooltip `tagsSort`；结果句用 `commonDelete` / `commonMove`
  作 {action}。

**验收**：`app/test/features/tags/presentation/tag_tree_page_test.dart` 24 例（原 13 + 新 11：
进入/退出、勾选计数、全选与清空、箭头展开不改选择、级联删除、取消删除、路径级联移动、
目标排除被选与后代、失败汇总、执行期禁用、普通模式不回归）。

