# V02.25 issue25反馈跟进

来源：issue [25](https://github.com/wzgrx/PureLive/issues/25)。选择依据：维护者本次“全面分析评估解决”与 D-003；沿用现有组件、图标和状态，小范围补齐，不扩大重构。

## 现状与根因

background_playback.dart:286 仅 Android 支持 DeviceControls，AppDelegate 未注册设备通道，因此 iPad 不安装亮度/音量拖动处理。screen_wake.dart:23 仅首次持有请求开启，平台异常被吞后和恢复前台时没有补申请；后者是确认的实现缺口，iPad 实际失效仍需真机确认。

## 预期行为

补 iOS 亮度/媒体音量原生通道，进入直播间不改音量，退出和后台恢复亮度；屏幕常亮按引用计数申请，恢复前台及受控周期重新确认，离开/暂停/关闭设置释放。不要声称模拟器验证了物理音量或长期防息屏。

## 范围

- apps/pure_live/ios/Runner/
- apps/pure_live/lib/features/live_play/logic/background_playback.dart
- packages/live_player/lib/src/screen_wake.dart
- apps/pure_live/test/
- packages/live_player/test/

不改版本号、发布资产、两个更新 JSON、签名与正式安装数据。功能验证与物理设备验收分开记录。


原生工程接线包括 apps/pure_live/ios/Runner.xcodeproj/project.pbxproj。苹果通道只用公开的 UIScreen、AVAudioSession、MPVolumeView API；物理音量不能用模拟器验收。
