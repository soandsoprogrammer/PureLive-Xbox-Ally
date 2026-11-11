# A07.33 播放信息面板

## 界面

- 入口：`RoomMenuEntry.playbackInfo`，菜单第二组“获取直链”后面；行尾有 ›。
- 面板：`RoomPanelKind.playbackInfo`，`RoomSidePanel` 外框，标题“播放信息”，标题栏“复制”。
- 三种位置沿用页面：竖屏在画面下方；横屏全屏、宽屏在右侧 360；面板内部滚动。

## 字段

| 行 | 显示 | 来源 |
|---|---|---|
| 分辨率 | `2560 × 1440` | `PlaybackStats.width/height` |
| 帧率 | `60.0 fps` | `session.state.frameRate` |
| 编码 | `H.265` | `PlaybackStats.videoFormat` 映射 |
| 编码器 | 元数据原文，最多两行 | `PlaybackStats.encoder` |
| 音频 | `48 kHz · 立体声 · 160 kbps` | `sampleRate`、`channels`、`audioBitrate` |
| 丢帧 / 已解码 | `2 / 503` | `droppedFrames` / `decodedFrames` |
| 缓冲 | `6.40 s` | `bufferSeconds` |
| 下载码率 | `3.0 Mbps`（3 次平均） | `downloadBytesPerSecond` |
| 流主机 | `cn-zjjh-ct-04-05.bilivideo.com` | `session.state.line.url.host`；中继写“本机中继” |

底部：`mpv 0.41.0 · FFmpeg 9.0.2`，读不到不显示。

排版：固定 104px 标签列、值左对齐、行间细分隔线；播放器内核并入卡片底部；2× 字号或窄面板改为标签在上、值在下。

## 代码

| 文件 | 内容 |
|---|---|
| `features/live_play/buttons/room_menu_button.dart` | 菜单项、图标、分组、`roomMenuOpensPanel` |
| `shared/panels/room_panel.dart` | `RoomPanelKind.playbackInfo` |
| `features/live_play/logic/playback_info.dart` | 纯行模型和格式化：分辨率、fps、编码名、音频、帧数、缓冲、下载、主机、编码器 |
| `features/live_play/dialogs/playback_info_panel.dart` | 面板、1 秒轮询、复制、后台停止 |
| `features/live_play/live_play_page.dart` | `_panelOf` 分发 |
| `assets/translations/zh.json`、`en.json` | `playback_info*` |

## 刷新与复制

- 打开立即读一次；之后每 1 秒读 `PlaybackStatsSource.readStats`；会话状态变化时立即重建。
- 关闭面板、页面销毁或应用进后台后停止定时器。
- 复制文本按显示行生成，带完整 `videoCodec`/`audioCodec` 和版本；不拼接 URL query、Cookie、请求头。
