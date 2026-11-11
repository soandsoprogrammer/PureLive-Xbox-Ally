# V02.23 issue23反馈跟进

来源：issue [23](https://github.com/wzgrx/PureLive/issues/23)。选择依据：维护者本次“全面分析评估解决”与 D-003；沿用现有组件、图标和状态，小范围补齐，不扩大重构。

## 现状与根因

全屏 PlayerView 和 RoomPanelKind 没有醒目留言入口；原 SuperChatList 仅在聊天区打开。控制器已提供活动 superChats 和最多 500 条会话历史。

## 预期行为

全屏有活动留言时显示 SC 入口，最后一条过期后入口隐藏；复用同一列表和关闭链，退出全屏也能关闭；提供默认开启的显示开关，不改变 D-044 会话历史范围。

## 范围

- apps/pure_live/lib/features/live_play/
- apps/pure_live/lib/features/settings/settings_catalog.dart
- apps/pure_live/assets/translations/
- packages/live_store/lib/src/settings/settings.dart
- apps/pure_live/test/features/live_play/

不改版本号、发布资产、两个更新 JSON、签名与正式安装数据。功能验证与物理设备验收分开记录。


电视实现同时覆盖 apps/pure_live/lib/tv/room/ 和 apps/pure_live/test/tv/；与主播放器复用同一 SC 列表、同一设置和会话历史，电视方向键只滚动留言，不换台。
