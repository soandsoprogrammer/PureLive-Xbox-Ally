# A07.26 任务书

先读 AGENTS.md、docs/PROCESS.md 第 5、8、14 节、docs/specs/ENGINEERING.md 与 UI.md、本目录 README.md。

## 背景与验收

来源：issue [23](https://github.com/wzgrx/PureLive/issues/23)。

全屏 PlayerView 和 RoomPanelKind 没有醒目留言入口；原 SuperChatList 仅在聊天区打开。控制器已提供活动 superChats 和最多 500 条会话历史。

全屏有活动留言时显示 SC 入口，最后一条过期后入口隐藏；复用同一列表和关闭链，退出全屏也能关闭；提供默认开启的显示开关，不改变 D-044 会话历史范围。

## 可改范围

- apps/pure_live/lib/features/live_play/
- apps/pure_live/lib/features/settings/settings_catalog.dart
- apps/pure_live/assets/translations/
- packages/live_store/lib/src/settings/settings.dart
- apps/pure_live/test/features/live_play/

## 阶段与测试

1. 保存改动前失败的定向回归结果。
2. 复用已有状态和弹层；新增文字进入翻译，设置键只加不改。
3. 定向回归、受影响成员静态检查、推送前完整门禁；同一时间一个本地重任务。
4. 写逐端真机步骤；不能验证的停在待真机，不据模拟器推定真机通过。分支 ai/V02.21，不推 master，不改版本与更新文件。


电视实现同时覆盖 apps/pure_live/lib/tv/room/ 和 apps/pure_live/test/tv/；与主播放器复用同一 SC 列表、同一设置和会话历史，电视方向键只滚动留言，不换台。


设置默认值基线范围还包括 packages/live_store/test/settings_defaults_test.dart：新键归入 v4 新增、默认 true，不改 3.x 基线值。
