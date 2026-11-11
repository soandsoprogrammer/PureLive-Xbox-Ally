# A07.33 播放信息面板：任务书

## 来源

用户 2026-10-29：希望在直播间看到类似斗鱼/B 站自带播放器的流信息，形式参考：

- B 站：Mime Type、Player Core、Video Info、Audio Info、Encoder、Stream Host、Buffer Length、Decoded Frames、Download Bitrate
- 斗鱼：Resolution、Frame rate、Codec、Encoder、Audio bitrate、Viewport、Dropped / Decoded、Buffer、Download bitrate

## 目标

在直播间右上角菜单加“播放信息”，用和“切换直播间”一样的右侧面板显示 **9 行**：

1. 分辨率
2. 帧率
3. 编码
4. 编码器（流元数据）
5. 音频（采样率、声道、码率）
6. 丢帧 / 已解码
7. 缓冲
8. 下载码率
9. 流主机

底部一行小字显示 mpv/FFmpeg 版本。缺项显示“—”。不做高级折叠，不做画面上的半透明浮层。

## 显示位置

- 右上角菜单 →“播放信息”（放在“获取直链”后面）。
- 和“切换直播间”一样打开房间面板并替换菜单：竖屏在画面下方，横屏全屏/宽屏在右侧 360；面板可滚动。
- 不遮画面、不加拖动/收起逻辑。

## 范围

- 只做直播间（手机竖屏、全屏、宽屏）；电视和多画面不做。
- 依赖 G01.5 的 `PlaybackStats`/`PlaybackStatsSource`。
- 复制动作只复制这 9 行 + 版本 + 完整 codec/encoder；不含 Cookie、请求头、URL query。

## 验收

- 菜单入口存在，打开后替换菜单面板，位置与“切换直播间”一致。
- 9 行有值；斗鱼 FLV 能看到 `H.265`、`obs-output module …`、`2560 × 1440`、`2 / 503`、`6.40 s`、`3.0 Mbps`；B 站 HLS 能看到流主机。
- 缺失值“—”；1 秒刷新；关闭/后台停止轮询。
- 复制文本不含 query/Cookie；门禁通过。
