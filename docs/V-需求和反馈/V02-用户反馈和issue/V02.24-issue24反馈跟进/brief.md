# V02.24 任务书

先读 AGENTS.md、docs/PROCESS.md 第 5、8、14 节、docs/specs/ENGINEERING.md 与 UI.md、本目录 README.md。

## 背景与验收

来源：issue [24](https://github.com/wzgrx/PureLive/issues/24)。

background_playback.dart:286 仅 Android 支持 DeviceControls，AppDelegate 未注册设备通道，因此 iPad 不安装亮度/音量拖动处理。screen_wake.dart:23 仅首次持有请求开启，平台异常被吞后和恢复前台时没有补申请；后者是确认的实现缺口，iPad 实际失效仍需真机确认。

补 iOS 亮度/媒体音量原生通道，进入直播间不改音量，退出和后台恢复亮度；屏幕常亮按引用计数申请，恢复前台及受控周期重新确认，离开/暂停/关闭设置释放。不要声称模拟器验证了物理音量或长期防息屏。

## 可改范围

- apps/pure_live/ios/Runner/
- apps/pure_live/lib/features/live_play/logic/background_playback.dart
- packages/live_player/lib/src/screen_wake.dart
- apps/pure_live/test/
- packages/live_player/test/

## 阶段与测试

1. 保存改动前失败的定向回归结果。
2. 复用已有状态和弹层；新增文字进入翻译，设置键只加不改。
3. 定向回归、受影响成员静态检查、推送前完整门禁；同一时间一个本地重任务。
4. 写逐端真机步骤；不能验证的停在待真机，不据模拟器推定真机通过。分支 ai/V02.21，不推 master，不改版本与更新文件。


原生工程接线包括 apps/pure_live/ios/Runner.xcodeproj/project.pbxproj。苹果通道只用公开的 UIScreen、AVAudioSession、MPVolumeView API；物理音量不能用模拟器验收。
