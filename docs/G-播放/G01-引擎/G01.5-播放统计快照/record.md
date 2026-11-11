# G01.5 记录

- 2026-10-29：按 A07.33 的需要确定字段和回退规则；实现 `PlaybackStats` 和 `readPlaybackStats`。测试与门禁结果见本文件末尾（工具链不可用时写明）。

## 决定

- 帧率不放进快照：会话的 `PlaybackState.frameRate` 已经按 `container-fps` → 过滤后的 `estimated-vf-fps` 取过，面板直接用它，避免两个来源不一致。
- 丢帧先读 `frame-drop-count`，为空才用 `decoder-frame-drop-count`；不做相加，避免重复计数。
- 2026-10-29：按用户要求删去视口（osd/window）字段和读取，播放信息面板改为 9 行。
- 编码器先读 `metadata/by-key/encoder`，空时读 `metadata` 逐行解析，键名大小写不敏感；没有就 null。
- 每个属性独立 500 ms 超时；一个属性失败不影响其他字段。

## 代码

- `packages/live_player/lib/src/playback_stats.dart`
- `packages/live_player/lib/src/mpv_engine.dart`
- `packages/live_player/lib/live_player.dart`
- `packages/live_player/test/playback_stats_test.dart`

## 测试

- 解析：整数/小数、空串、异常、超时、负数/NaN 丢弃。
- 编码器：`metadata/by-key/encoder` 命中、大小写、从 `metadata` 回退。
- 丢帧/解码帧：首选缺失时回退。
- 测试文件 `packages/live_player/test/playback_stats_test.dart` 已写；本环境没有 Flutter SDK，`flutter test` 未运行。
- `dart format --page-width 120 --set-exit-if-changed`（临时 Dart 3.13.5）通过。


2026-10-30已随5.4.22发布。当前执行者独立运行完整门禁和最终包验证；具体证据与原设备边界见Y01.33/verify.md。
