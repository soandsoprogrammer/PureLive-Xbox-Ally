# A17.26 电视识别与导航记录

- Dart原来的平台调用异常会永久缓存false；新增可重试失败、已确认电视的正向锁定与恢复时provider更新，首帧/恢复再次核对；用户显式手机选择保持优先。
- 原生原本已有UI_MODE_TYPE_TELEVISION与FEATURE_LEANBACK；补充设备电视特征/配置及仅保存已确认电视的身份，不声称原实现遗漏leanback。
- 设置嵌套Navigator的方向边界改为parentScope；共享设置Slider使用directional导航，使上下离开、左右调整。旧行为反例与恢复/覆盖策略回归通过。
- Sony KD-65X8566E未接入本轮，不据模拟器推断其具体SoC、网络或原机长时间断电根因。最终受控电视布局、重启和导航验证见Y01.39。

状态：源码候选待最终门禁与原生验收，未公开发布。发布与元数据收尾见Y01.39。

## 电视原生导航发现的第二层焦点问题

API28电视模式实测发现上下可移焦，但左右没有调节滑块。通过仅受控AVD的VM对象检查，实际焦点在无onTap的外层InkWell；Flutter方向导航下该控件忽略canRequestFocus，导致单测直接聚焦滑块时漏检。新增按真实directional导航进入滑块的反证测试，改前0.5不变而失败；SettingsRow显式将无动作外层FocusNode标为skipTraversal，保留滑块与计数器的内部焦点，修复后34项设置及焦点回归通过。原生新构建复验仍待进行，不能将旧试包当最终源码。

上游依据：[Flutter InkWell实现](https://flutter.googlesource.com/mirrors/flutter.git/+/refs/heads/main/packages/flutter/lib/src/material/ink_well.dart)方向导航分支返回true；[焦点说明](https://docs.flutter.dev/ui/interactivity/focus)区分skipTraversal和canRequestFocus。修复不修改共享Flutter SDK。

受控API28最新开发试包复验：设置首行上键已停留、回顶标题恢复，滑块左右50%→55%→50%、上下切换全局静音和音量增强均成功。另发现播放信息页经内部链接打开时未继承TV样式及初始焦点；以及1280×720下内部Slider可见而整行描边仍裁切12像素。新增实际TV路由和相同尺寸的反证均失败后，HUD页使用TV设置壳、共享设置正文约束及首焦；TV滚动在整行可容纳时显示完整SettingsRow，超高行保留其当前控件。七项相关回归通过，最新原生构建复验待进行；不把试包视为正式同源包。

## 5.5.0 发布收尾


5.5.0+5132，安装包源码 `b0b5773bef14822fd10d45e9155cd571e2e03e83`，代码 PR [#139](https://github.com/wzgrx/PureLive/pull/139)，代码合并 `b81cc8dbfe0cfb41d04dbb62ff1f397231883015`。最终源提交完整 all/14 门禁通过，检查前后源码保持一致。

十个安装包与 SHA256SUMS 逐项核对构建、本地、GitHub 摘要及匿名下载。发布页：[5.5.0](https://github.com/wzgrx/PureLive/releases/tag/v5.5.0)。同源 Android 三 ABI、Windows ZIP/安装器、Linux TAR、Apple 四包分别留有包检查证据。Windows 实际验证六页设置对齐、固定/记忆窗口策略及同一路径前后台进程正常退出；隔离安装器验证拒绝退出时中止删除。Android 9 专用 AVD 验证下载源、目录选择、下载完成的首焦，官方下载哈希匹配且没有安装下载的正式版；Android 16 专用 AVD 验证关注分区按钮显示和点击、定制信息层、浏览器 PNG/WebM 导出与系统停止共享。Android 原生发送、Linux 原生接收实际显示页面变化，停止后恢复原播放，捕获与前台服务关闭。Apple 同源托管构建、两台托管 Mac 四次最终 ZIP 启动、模拟器及原生录制/播放与 ReplayKit 生命周期探针分别验收。

这些是受控原生与托管环境证据，不是原 Sony/Huawei 设备或原私有账号验收。#131、#135 保持开放等待原场景复验；#33、#47、#49 按既定决定暂缓，不称已修复；#96 维持拒绝。斗鱼真实公开房间有实际取流证据，登录拒绝与游客恢复分支由脱敏响应回归，不伪造原账号失败。B站 Raw 开关默认关闭，接口确认条件和候选改写有回归，公开实网只返回普通档，未声称已获得真实 Raw 高码率。屏幕共享只含画面，iOS 范围为本应用；不声称覆盖系统级遥控或跨应用 iOS 广播。

默认 Chromium 无附加参数连接直接网络内的 Linux X11 原生端，实际 1280×900 画面与 PNG 导出通过。Android 模拟器 NAT 下的 mDNS 超时反例保留；此前关闭 mDNS 的模拟器测试不单独作为通用浏览器证明。官方网络限制见 https://developer.android.com/studio/run/emulator-networking-address 。

原始证据在仓库外 outputs/purelive-550-20261031；失败反证、环境失败与中断日志保留，不计为通过。Windows 仅独立数据，物理设备未操作，专用 AVD 数据/显示/appop 恢复、临时 root 撤销，测试进程停止。原 Claude 47 份未提交文件及 HEAD 保持。
