# 纯粹直播 · Windows 掌机版

完整解压后，双击 `purelive-gpui.exe`。播放由 Rust 实现，视频通过 Windows Media Foundation 和 D3D11 硬解，音频通过 WASAPI 输出。直播平台解析、账号和弹幕数据仍由随包的 `purelive-platforms.exe` 提供。

播放器支持 H.264/AAC 的 HTTP FLV 和未加密的 HLS（MPEG-TS、fMP4）。线路选择依平台提供的格式和画质而定。弹幕默认开启并记住开关，支持四个平台的现有表情和平台提供的 SC 历史。

热门页用 LB/RB 切平台，关注页用 LB/RB 切筛选。LT/RT 切换栏目。搜索页的 View 键打开平台筛选，Menu 键打开设置。直播中 LB/RB 切换已开播的关注房间。
