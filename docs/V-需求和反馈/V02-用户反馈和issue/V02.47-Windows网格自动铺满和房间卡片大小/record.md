# V02.47 Windows 网格自动铺满和房间卡片大小：记录

- 日期：2026-10-25
- 执行者：Claude（Qoder）
- 分支和提交：`ai/V02.47`，单次提交（功能、格式、analyze、owners 和测试修正合并为本提交）
- 任务书：[brief.md](brief.md)；说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 | 做了 | `paging.dart`：`autoPageSize = 0`、`pageSizesOf` 的 `auto` 标记和保留已存值、`PageFillScheduler`、翻页条的 `auto/allowAuto` 和“自动”菜单项 |
| c2 | 做了 | `room_grid.dart`：`pageFillCount`（覆盖可用高度，最后一行可部分显示）、`RoomGridGeometry.ofGrid/maxColumns`、自动容量、页首锚定、`_fillAutoPage` 和有进展保护；`popular_page/catalog` 允许 0 |
| c3 | 做了 | `favorite_page.dart`：网格/离线行在 `Expanded` 内测量，自动只重算切片，翻页条支持“自动” |
| c4 | 做了 | `Settings.roomCardSize` + `RoomCardSize` 六档 XS/S/M/L/XL/XXL + `watchRoomCardSize`；所有房间网格改用 `ofGrid`；选项在“房间卡片设置 → 桌面端 → 外观”，移动端目标不显示；只在桌面系统生效，手机端固定 M（不可修改） |
| c5 | 做了 | 15 种语言新增 8 个键（XS/S/M/L/XL/XXL 六个档位加标题和说明）；更新每页默认数量的说明 |

## 根因

- 窗口放大不铺满：`usesDesktopPages` 在 Windows 上走固定翻页；`pageSizesOf` 把设置 0 回落成 20/12；`RoomFeedView._fillViewport` 在桌面直接返回（`room_grid.dart:509-512`，改动前）。
- 不能调卡片大小：列数只由 `GridColumns.roomMinWidth`（160/180/200）和固定 8 列上限决定，没有设置项；设置页只有外观预设、间距和字号。

## 改了哪些文件

- `apps/pure_live/lib/shared/rooms/paging.dart`
- `apps/pure_live/lib/shared/rooms/room_grid.dart`
- `apps/pure_live/lib/shared/rooms/room_cards.dart`
- `apps/pure_live/lib/features/favorite/favorite_page.dart`
- `apps/pure_live/lib/features/popular/popular_page.dart`、`popular_catalog.dart`
- `apps/pure_live/lib/features/history/history_page.dart`、`features/search/search_view.dart`
- `apps/pure_live/lib/features/settings/settings_catalog.dart`
- `packages/live_store/lib/src/settings/settings.dart`
- `apps/pure_live/assets/translations/*.json`（15 个）
- 测试：`test/shared/paging_test.dart`、`test/shared/card_size_test.dart`、`popular_test.dart`、`favorite_test.dart`、`settings_page_test.dart`、`settings_defaults_test.dart`

## 新设置、翻译键、门禁基线

- 新设置 `room_card_size`（`StringSetting`，默认 `standard` = M，允许 `smaller/small/standard/large/xlarge/xxlarge`，section `roomCard`，backupKey `cardSize`）；已加入 `Settings.all` 和 `newInV4`。
- 新翻译键：`room_card_size`、`room_card_size_desc`、`room_card_size_smaller`/`_small`/`_standard`/`_large`/`_xlarge`/`_xxlarge`（显示 XS/S/M/L/XL/XXL）；改 `settings_page_default_size_hint`。15 种语言齐全。
- 没有改门禁基线。

## 测试

- 新增 `paging_test.dart`：`pageSizesOf` 自动标记/已存值、`pageFillCount`（整行/刚好整除/多一排/上限）、`PageFillScheduler`。
- 新增 `card_size_test.dart`：M 档等于现有列数表；六档在 1920/1280 的列数；关注大卡片 300 的缩放；未知值回落。
- 改了 `popular_test.dart`（桌面固定数量用例先写入 20，新增自动铺满/缩放/切回自动）、`favorite_test.dart`（自动切片随窗口、固定值不变）、`settings_page_test.dart`（桌面可见、Android 不可见、选“大”写入）、`settings_defaults_test.dart`（新键）。
- GitHub Actions 的 Test 工作流在这一个提交上通过：格式、`dart analyze --fatal-infos`、完整门禁（含全部 app/package 测试）都绿。
- 本机没有 Flutter/Dart，测试由 CI 的 Ubuntu + Flutter 3.47.7 跑。门禁前修了几处测试：R04.1 用例固定每页 20 以免自动补页多请求；`PageFillScheduler` 测试主动排帧；固定每页数量改看翻页条文字（已构建的卡片数受 Sliver 缓存影响）。

## 真机上要看的

- Windows 1280×720、最大化 1920×1080 的铺满；拖动窗口后的数量变化。
- 第 2 页放大后是否落在包含原页首卡片的页。
- 手动 20 固定；切回“自动”恢复。
- 六档卡片大小 XS/S/M/L/XL/XXL；关注页网格/离线行、搜索、历史。
- Android 上设置不可见、布局不变。

## 停在哪（没做完时写）

- 做完的阶段：代码、翻译、文档、自动测试和 CI 门禁。
- 正在做的阶段：Windows 真机验收。
- 已知问题：本机没有 Flutter/Dart，真机步骤未跑；生成文档和 `docs/inventory/OWNERS.md` 已更新。
- 下一步：按上面的真机步骤在 Windows 上验收；通过后把任务状态改为“完成”。


## 5.4.16 候选进展

PR #55固定7688dbb7d44f98cdea3d33f98af08f3aede69254非快进整合，原任务号与既有快手V02.44冲突，登记为V02.47；原D-058与WebDAV决定冲突，保留两边并改为D-060。审查发现PageFillScheduler在20已应用、40待处理、最新又20时错误应用40；新增失败回归后修正为取消过期更新。

当前定向回归共21项通过；原生截图、安装包哈希和真实服务器/原机验证不由此替代，发布前继续按清单核对。


## 5.4.16 最终交付

PR55原提交历史保留，自动容量/手动20/翻页锚点及六档控件在Windows正式包验证，实际网格XS/M/XXL和六档几何单测分别记录，默认M恢复；本地完整all/14通过。

[发布与分层验证记录](../../../Y-发布和运营/Y03-发布说明和README/releases/v5.4.16.md)。此前候选阶段的待验状态由本节及最终回执更新。
