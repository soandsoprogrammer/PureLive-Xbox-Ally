# V01.22 常驻时间与播放速率显示

来源：[GitHub #128](https://github.com/wzgrx/PureLive/issues/128)，2026-10-31。

5.4.27基线：`apps/pure_live/lib/features/live_play/player/bar_parts.dart` 的 PlayerClock 属于控制栏，`player_controls.dart` 在全屏布局使用，随控制栏一起隐藏。电视 `tv/room/tv_room_overlays.dart` 尚无对应公共时钟；不能把点击后出现时间视为已有常驻功能。

`features/live_play/dialogs/playback_info_panel.dart` 已采样当前会话统计并平滑下载速率；`packages/live_player/lib/src/playback_stats.dart` 的 downloadBytesPerSecond 表示当前媒体字节输入速率，并非全设备吞吐量。上游 [mpv 属性说明](https://github.com/mpv-player/mpv/blob/master/DOCS/man/input.rst) 明确 raw-input-rate 是可能缺失或不准确的估计值，不能用编码码率替代，也不能将未知值伪装为零。

方案：共享仅展示的信息层；时间与当前流下载速率分别开关，跟随控制栏或常驻，支持四角位置及字体大小、颜色与恢复默认。电视 OK 呼出时可查看，常驻层不获取遥控焦点。需避让字幕、弹幕、玻璃控制栏和屏幕安全区；横竖屏、大字体、无统计平台分别验收。优先复用当前会话统计，不另建播放器，不在每个显示组件各起一套高速定时采样。时间变化只刷新自身显示。

5.4.27仅完成评估。用户后续按D084要求全部采纳需求开发后发布，本轮实现已进入V02.68；实现与验收记录见A07.36。当前候选已覆盖核心行为和受控手机验证，最终同源包的跨端验收与发布由Y01.39继续；发布确认前保持issue开放。
