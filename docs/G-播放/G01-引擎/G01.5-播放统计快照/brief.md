# G01.5 播放统计快照：任务书

## 来源

A07.33 播放信息面板的前置。用户 2026-10-29 要求在直播间显示类似斗鱼/B 站自带面板的流信息；mpv 属性的读取和解析放在 `live_player`，界面只消费快照。

## 目标

在 `packages/live_player` 新增只读快照，供界面的“播放信息”面板使用：

- 分辨率：`video-params/w,h`
- 视频编码：`video-format`（短名映射在界面层）
- 编码器：`metadata/by-key/encoder`，空时解析 `metadata`；读不到为 null
- 音频：`audio-params/samplerate`、`audio-params/channel-count`、`audio-bitrate`
- 丢帧/已解码：`frame-drop-count`（缺失用 `decoder-frame-drop-count`）/ `estimated-frame-number`（缺失用 `estimated-frame-count`）
- 缓冲：`demuxer-cache-duration`
- 下载速率：`cache-speed`（字节/秒）
- 版本：`mpv-version`、`ffmpeg-version`
- 复制用：`video-codec`、`audio-codec`

帧率不在这里重复读：会话已有 `PlaybackState.frameRate`（`container-fps`，否则过滤后的 `estimated-vf-fps`）。

## 不做

- 不显示 Cookie、请求头、URL 的 query/token、客户端地址、设备 id。
- 不读 HDR/色彩/像素格式/旋转/输出后端/窗口尺寸等高级项。
- 不改变播放行为，不改变 mpv 配置。

## 验收

- `MpvEngine` 实现 `PlaybackStatsSource.readStats()`；属性缺失、空值、异常、超时都返回 null。
- 每项读取有 500 ms 超时，一次快照用 `Future.wait` 并发读取。
- 单元测试覆盖：正常值、缺项、空值、异常/超时、encoder 元数据、丢帧/解码帧回退。
- 不访问真实平台；不依赖原生 mpv（测试用注入的读取函数）。
