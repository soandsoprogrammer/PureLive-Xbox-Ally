# X04.2 记录

2026-10-23，分支 ai/V02.21，基于 da1e678d7072807aa59a9de4f5e9f91f106cd7c3。

## 实现

iOS 加入 DeviceControls，公开 UIScreen、AVAudioSession、MPVolumeView 原生通道注册并加入 Xcode 源文件。读取不改设备音量，拖动才设置，退出和后台恢复亮度。ScreenWake 保留引用计数，15 秒复核、前台恢复、错误重试及串行最终关闭；没有把插件注册或第三方播放器认定为已证实根因。

## 回归

新增 4 条本任务回归，见 room_popups_test.dart、frame_rate_test.dart。改前失败日志：sc-ipad-before.log、wake-before.log；改后定向测试通过。日志保存在本机 outputs/purelive-issues-20261023-batch2；没有把编译失败或测试夹具错误算作缺陷证据。

合计新增 13 条：静音 2、电视首选平台 1、SC 3、iPad 手势 1、常亮恢复 3、取流诊断 3。选定回归含旧 #12/#14，结果与全量门禁分别保留。可选 Widget 截图使用合成数据，不是真机视频或验收。

## 停在哪

实现与定向回归完成，未发布；真机步骤见 verify.md。推送前必须运行完整门禁，提交后 Apple 原生编译和模拟器启动结果附在 PR 与本机回执；此记录不预先声称通过。未操作正式安装、原始 Claude 目录或用户账号。


2026-10-23 原生构建：Apple run 39964303651 在 Swift 编译失败，PlayerDeviceControls.swift 两处把 FlutterPluginRegistrar.viewController 写成函数调用。Xcode 明确将其导入为 UIViewController? 属性；已改为 registrar.viewController 的属性访问，不改通道行为。修正后的原生构建与启动必须重验，旧失败日志保存在本机；推送前完整门禁照常重新执行。


## 5.4.9 发布

PR #27 合并 37a5f703901022cd7fcb88c0907cd3c84cd4ea68，实际构建与标签提交 a0fad683c0562e5856f0eddeec7f2df2efd030b9，随 [5.4.9](https://github.com/wzgrx/PureLive/releases/tag/v5.4.9) 发布。完整门禁、十包哈希及各端启动核验通过，详见 Y01.20；反馈者 iPad、Sony 电视、真实付费 SC 和各端完整交互未全部覆盖，保留待真机，不据此宣称所有硬件验收。
