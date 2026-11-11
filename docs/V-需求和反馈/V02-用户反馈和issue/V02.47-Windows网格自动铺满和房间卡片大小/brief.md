# V02.47 Windows 网格自动铺满和房间卡片大小：任务书

## 范围

- 做：桌面编号翻页的“自动”每页数量按覆盖当前网格可用高度的行 × 列计算，最后一行可只露出一部分；窗口大小变化时重算并加载补足；翻页条可选择“自动”或固定数量。
- 做：桌面房间网格的六档卡片大小（XS / S / M / L / XL / XXL），所有房间网格共用；手机端固定 M（不可修改），电视保持现状。
- 不做：去掉编号翻页；修改分区卡片页（面积卡片）；修改电视自己的网格；动 3.x 的每页数量键名和默认值。

## 必须遵守

- 默认行为：未改设置时，“自动”是默认（`pageDefaultSize = 0`），但渲染结果要铺满窗口；卡片大小默认 `standard`，列数和改动前一致。
- 同一功能同一个组件：热门、分区房间、关注、搜索、历史都用 `RoomGridGeometry.ofGrid`；手机端 `watchRoomCardSize` 返回标准。
- 文案：中文在 `assets/translations/zh.json`，15 种语言键集合一致，按键排序、4 空格缩进；`zh_Hant.json` 由脚本生成。
- 代码、注释、提交信息用英文；提交以 `[V02.47]` 开头；不推 master；不提交 `.qoder/`、`repomix-output.xml`。
- 不自造第二套分页或卡片尺寸逻辑；沿用 `RoomFeed.page/pageRooms/goToPage` 和 `GridColumns.count`。

## 验收

1. Windows 1280×720 和最大化 1920×1080：热门页卡片铺满，翻页条显示“自动”。
2. 拖动窗口大小：每页数量随行 × 列变化，底部没有大片空白（最后一行可以显示不全）；第 2 页以上缩放后落在包含原页首卡片的页。
3. 手动选 20：固定 20 张，缩放不变；切回“自动”恢复铺满。
4. 六档卡片大小逐档切换：列数和卡片尺寸变化；M 档与改动前一致。
5. 关注页（网格和离线行）、搜索、历史页表现一致。
6. Android 模拟器/真机：设置里没有“房间卡片大小”，网格布局不变。

## 测试

- `apps/pure_live/test/shared/paging_test.dart`、`card_size_test.dart`（新）。
- `apps/pure_live/test/features/popular/popular_test.dart`：桌面固定数量用例先写入 20；新增自动铺满/缩放/切回自动用例。
- `apps/pure_live/test/features/favorite/favorite_test.dart`：桌面自动切片随窗口变化；固定值缩放不变。
- `apps/pure_live/test/features/settings/settings_page_test.dart`：桌面可见、Android 不可见、选“大”写入键值。
- `packages/live_store/test/settings_defaults_test.dart`、`apps/pure_live/test/i18n_test.dart`。
- `bash tools/gate/gate.sh --all` 通过。

## 真机步骤

1. 运行 Windows 版，打开热门；放大/缩小窗口，数一页卡片数量，确认铺满。
2. 翻到第 2 页，放大窗口，确认仍在包含原页首卡片的页。
3. 设置 → 外观 → 房间卡片设置 → 桌面端 → 外观 → 房间卡片大小，逐档切换；返回热门看列数和卡片尺寸。切到移动端目标时这一项不显示。
4. 关注页切换网格/离线，重复第 1、3 步；搜索和历史看卡片大小。
5. Android 上确认设置不可见、布局不变。

## 报告格式

- 在 `record.md` 写每条的完成情况、偏差、测试数量、真机结果；没做的写“待真机/未运行”和原因。


## 5.4.16 最终交付

PR55原提交历史保留，自动容量/手动20/翻页锚点及六档控件在Windows正式包验证，实际网格XS/M/XXL和六档几何单测分别记录，默认M恢复；本地完整all/14通过。

[发布与分层验证记录](../../../Y-发布和运营/Y03-发布说明和README/releases/v5.4.16.md)。此前候选阶段的待验状态由本节及最终回执更新。
