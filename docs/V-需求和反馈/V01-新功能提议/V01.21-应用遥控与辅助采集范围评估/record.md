# V01.21 应用遥控与辅助采集范围评估

来源：[GitHub #126](https://github.com/wzgrx/PureLive/issues/126)，2026-10-31。

当前 `apps/pure_live/lib/shared/remote/playback_remote.dart` 只接收页面注册的目标，`app/remote_runtime.dart` 只安装直播链接推送。单间、电视直播、多画面分别注册目标，首页与设置没有目标。因此反馈的适用范围限制属实，不能仅修改网页按钮文案即视为实现。

应用级方向/确认/返回需保留页面覆盖优先级、弹窗取消链、撤销配对与旧目标失效；不能让已关闭的房间接收下一页面的命令。需定义控制范围，并验证首页、分区、关注、搜索、设置与弹窗。

辅助截图/录屏是界面采集；目前录制是媒体流，投屏是媒体投放，均不等同屏幕镜像。Android官方 [Media projection](https://developer.android.com/media/grow/media-projection) 要求每次采集会话由本机同意，应用需要采集类型前台服务。Flutter [Platform Views](https://docs.flutter.dev/platform-integration/android/platform-views) 的原生视图合成也需单独核对，不能以Flutter普通控件截图冒充包含原生视频的系统截图。镜像还需发送/接收协商、资源退役和断开后的原房恢复。

本轮结论：保留issue开放，已回复逐项评估；尚未实现上述扩展，不随5.4.27缺陷修复标为完成。控制其他软件或整台设备、ADB/无障碍式全设备遥控不纳入本直播应用。后续先完成应用级导航及辅助反馈采集的方案，再按协议和平台分别实施验收。

## 5.5.0 发布收尾


5.5.0+5132，安装包源码 `b0b5773bef14822fd10d45e9155cd571e2e03e83`，代码 PR [#139](https://github.com/wzgrx/PureLive/pull/139)，代码合并 `b81cc8dbfe0cfb41d04dbb62ff1f397231883015`。最终源提交完整 all/14 门禁通过，检查前后源码保持一致。

十个安装包与 SHA256SUMS 逐项核对构建、本地、GitHub 摘要及匿名下载。发布页：[5.5.0](https://github.com/wzgrx/PureLive/releases/tag/v5.5.0)。同源 Android 三 ABI、Windows ZIP/安装器、Linux TAR、Apple 四包分别留有包检查证据。Windows 实际验证六页设置对齐、固定/记忆窗口策略及同一路径前后台进程正常退出；隔离安装器验证拒绝退出时中止删除。Android 9 专用 AVD 验证下载源、目录选择、下载完成的首焦，官方下载哈希匹配且没有安装下载的正式版；Android 16 专用 AVD 验证关注分区按钮显示和点击、定制信息层、浏览器 PNG/WebM 导出与系统停止共享。Android 原生发送、Linux 原生接收实际显示页面变化，停止后恢复原播放，捕获与前台服务关闭。Apple 同源托管构建、两台托管 Mac 四次最终 ZIP 启动、模拟器及原生录制/播放与 ReplayKit 生命周期探针分别验收。

这些是受控原生与托管环境证据，不是原 Sony/Huawei 设备或原私有账号验收。#131、#135 保持开放等待原场景复验；#33、#47、#49 按既定决定暂缓，不称已修复；#96 维持拒绝。斗鱼真实公开房间有实际取流证据，登录拒绝与游客恢复分支由脱敏响应回归，不伪造原账号失败。B站 Raw 开关默认关闭，接口确认条件和候选改写有回归，公开实网只返回普通档，未声称已获得真实 Raw 高码率。屏幕共享只含画面，iOS 范围为本应用；不声称覆盖系统级遥控或跨应用 iOS 广播。

默认 Chromium 无附加参数连接直接网络内的 Linux X11 原生端，实际 1280×900 画面与 PNG 导出通过。Android 模拟器 NAT 下的 mDNS 超时反例保留；此前关闭 mDNS 的模拟器测试不单独作为通用浏览器证明。官方网络限制见 https://developer.android.com/studio/run/emulator-networking-address 。

原始证据在仓库外 outputs/purelive-550-20261031；失败反证、环境失败与中断日志保留，不计为通过。Windows 仅独立数据，物理设备未操作，专用 AVD 数据/显示/appop 恢复、临时 root 撤销，测试进程停止。原 Claude 47 份未提交文件及 HEAD 保持。
