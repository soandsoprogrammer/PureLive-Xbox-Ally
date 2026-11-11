# G01.5 播放统计快照

A07.33 的播放信息面板只消费 `PlaybackStats`；mpv 属性名、超时和回退规则都在 `live_player` 内。

## 代码

| 文件 | 内容 |
|---|---|
| `packages/live_player/lib/src/playback_stats.dart` | `PlaybackStats`、`PlaybackStatsSource`、`readPlaybackStats(read)`；每个属性 500 ms 超时，异常/空值转 null |
| `packages/live_player/lib/src/mpv_engine.dart` | `MpvEngine implements PlaybackStatsSource`，`readStats()` 复用 `_readProperty` |
| `packages/live_player/lib/live_player.dart` | 导出新类型 |
| `packages/live_player/test/playback_stats_test.dart` | 注入读取函数的解析测试 |

## 属性

| 字段 | mpv 属性 | 回退 |
|---|---|---|
| 宽/高 | `video-params/w`、`video-params/h` | — |
| 视频编码 | `video-format` | — |
| 编码器 | `metadata/by-key/encoder` | 解析 `metadata`；大小写不敏感 |
| 采样率/声道 | `audio-params/samplerate`、`audio-params/channel-count` | — |
| 音频码率 | `audio-bitrate` | — |
| 丢帧 | `frame-drop-count` | `decoder-frame-drop-count` |
| 已解码 | `estimated-frame-number` | `estimated-frame-count` |
| 缓冲 | `demuxer-cache-duration` | — |
| 下载速率 | `cache-speed` | — |
| 版本 | `mpv-version`、`ffmpeg-version` | — |
| 复制详情 | `video-codec`、`audio-codec` | — |

## 说明

- `estimated-frame-number`/`estimated-frame-count`、`frame-drop-count` 在个别平台或版本可能为空，界面显示“—”；不推测。
- 编码器标签是推流端写进流元数据的（OBS 的 `obs-output module`），不是播放器的编码器。
- 不把 URL、Cookie、请求头放进快照。
