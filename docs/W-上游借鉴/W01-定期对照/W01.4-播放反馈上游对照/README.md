# W01.4 播放反馈上游对照

2026-10-23，本轮仅围绕 #21–#25 的行为对照，不宣称完成全部上游周检。

| 参考副本 | 引用 | 本次读到的提交 |
|---|---|---|
| phone | upstream/master | e1fe2b90ef66e119cc0aa930d166076fadf86b54 |
| tv | origin/main | 6a1186630b41df36d0ae4ed7bb996d6c1c745897 |
| media | origin/main | 13cae1869580b5a96ffae8d1278fb9ab1d10ddee |

| 对照 | 观察及处置 |
|---|---|
| 3.x v3.2.11 | lib/modules/live_play/widgets/video_player/video_controller.dart:494/816/854/1527：已有常亮、系统音量和应用亮度语义。保留进入房间不覆盖设备音量、用户拖动才写入、离开恢复亮度。 |
| 手机最新 | lib/domains/live/presentation/multiview/multiview_controller.dart:946 已有全局静音；playback/controllers/live_play_controller.dart:277 检查 WakelockPlus.enabled。4.x 已有静音状态，不引入新控制器；常亮补串行恢复而非照搬 GetX。 |
| 电视最新 | services/favorites 中 preferPlatform 为可见平台集合中的持久设置；4.x 缺陷来自手机选择框绕开 AppOptionPresenter，复用既有电视选项框。 |
| SC | 手机最新提供活动集合与定时到期；4.x 已有 D-044 会话历史，本轮仅补入口，不引入跨启动存储。 |
| media_core | 固定 origin/main 提交；本轮 lib 下关键词搜索无命中，不能据此宣称媒体核心全仓没有相关行为，不迁移后端。 |

Apple 行为参照官方 [MPVolumeView](https://developer.apple.com/documentation/mediaplayer/mpvolumeview)、[UIScreen.brightness](https://developer.apple.com/documentation/uikit/uiscreen/brightness)、[isIdleTimerDisabled](https://developer.apple.com/documentation/uikit/uiapplication/isidletimerdisabled)；[wakelock_plus](https://pub.dev/packages/wakelock_plus) 提示系统可能释放屏幕锁。音量必须在物理设备确认。实际读取缓存插件 1.8.1 的原生 idleTimerLock 实现，针对旧锁状态补复核；没有证明这就是反馈者设备的全部根因。

没有复制上游代码、修改参考副本或照搬架构。按行为独立实现，来源和边界如上。
