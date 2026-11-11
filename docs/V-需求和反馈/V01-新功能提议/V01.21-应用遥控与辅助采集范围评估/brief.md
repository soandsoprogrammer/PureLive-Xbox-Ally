# V01.21 应用遥控与辅助采集范围评估

来源：[GitHub #126](https://github.com/wzgrx/PureLive/issues/126)，2026-10-31。

当前 `apps/pure_live/lib/shared/remote/playback_remote.dart` 只接收页面注册的目标，`app/remote_runtime.dart` 只安装直播链接推送。单间、电视直播、多画面分别注册目标，首页与设置没有目标。因此反馈的适用范围限制属实，不能仅修改网页按钮文案即视为实现。

应用级方向/确认/返回需保留页面覆盖优先级、弹窗取消链、撤销配对与旧目标失效；不能让已关闭的房间接收下一页面的命令。需定义控制范围，并验证首页、分区、关注、搜索、设置与弹窗。

辅助截图/录屏是界面采集；目前录制是媒体流，投屏是媒体投放，均不等同屏幕镜像。Android官方 [Media projection](https://developer.android.com/media/grow/media-projection) 要求每次采集会话由本机同意，应用需要采集类型前台服务。Flutter [Platform Views](https://docs.flutter.dev/platform-integration/android/platform-views) 的原生视图合成也需单独核对，不能以Flutter普通控件截图冒充包含原生视频的系统截图。镜像还需发送/接收协商、资源退役和断开后的原房恢复。

本轮结论：保留issue开放，已回复逐项评估；尚未实现上述扩展，不随5.4.27缺陷修复标为完成。控制其他软件或整台设备、ADB/无障碍式全设备遥控不纳入本直播应用。后续先完成应用级导航及辅助反馈采集的方案，再按协议和平台分别实施验收。
